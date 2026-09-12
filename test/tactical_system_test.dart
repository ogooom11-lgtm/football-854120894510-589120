import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:new_football/src/game/config/game_constants.dart';
import 'package:new_football/src/game/enums/ai_play_style.dart';
import 'package:new_football/src/game/enums/match_mode.dart';
import 'package:new_football/src/game/enums/player_role.dart';
import 'package:new_football/src/game/enums/team_id.dart';
import 'package:new_football/src/game/logic/match_engine.dart';
import 'package:new_football/src/game/math/vec2.dart';
import 'package:new_football/src/game/models/formation.dart';
import 'package:new_football/src/game/models/player_profile.dart';
import 'package:new_football/src/game/models/team_setup.dart';
import 'package:new_football/src/game/tactics/danger_zone.dart';
import 'package:new_football/src/game/tactics/tactical_engine.dart';
import 'package:new_football/src/game/tactics/team_play_state.dart';

/// Both teams are human-controlled in these tests so the pre-kickoff state
/// freezes every AI decision: attaching the ball to a player then ticking
/// gives a fully deterministic tactical state machine.
MatchSetup _setup({
  FormationType blueFormation = FormationType.wing433,
  bool aiControlled = false,
}) {
  final rng = math.Random(7);
  List<PlayerProfile> squad(String prefix) {
    return [
      PlayerProfile.generated(
          name: '$prefix GK', isGoalkeeper: true, random: rng),
      for (var i = 0; i < 15; i++)
        PlayerProfile.generated(
            name: '$prefix $i', isGoalkeeper: false, random: rng),
    ];
  }

  return MatchSetup(
    mode: MatchMode.knockout,
    blue: TeamSetup(
      id: TeamId.blue,
      name: 'Blue',
      formation: blueFormation,
      players: squad('B'),
    ),
    red: TeamSetup(
      id: TeamId.red,
      name: 'Red',
      formation: FormationType.classic442,
      players: squad('R'),
    ),
    blueAiControlled: aiControlled,
    redAiControlled: aiControlled,
  );
}

void main() {
  // -------------------------------------------------------------------
  // Formation presets as behavioural systems (plan items 19, 24-27)
  // -------------------------------------------------------------------
  group('formation presets', () {
    test('all 23 playable formations expose 11 role slots with one keeper',
        () {
      expect(playableFormationTypes.length, 23);
      for (final type in playableFormationTypes) {
        final plan = formationPlan(type);
        expect(plan.spots.length, 11, reason: '$type must field 11 players');
        expect(
          plan.spots.where((spot) => spot.role.isGoalkeeper).length,
          1,
          reason: '$type must have exactly one goalkeeper',
        );
        for (final spot in plan.spots) {
          expect(spot.x, inInclusiveRange(0.0, 1.0), reason: '$type x bounds');
          expect(spot.y, inInclusiveRange(0.0, 1.0), reason: '$type y bounds');
        }
      }
    });

    test('roles come from the preset, not from the line count (plan 19)', () {
      final plan = formationPlan(FormationType.modern4231);
      final roles = plan.spots.map((spot) => spot.role).toSet();
      expect(
        roles,
        containsAll([
          PlayerRole.leftBack,
          PlayerRole.rightBack,
          PlayerRole.defensiveMidfielder,
          PlayerRole.attackingMidfielder,
          PlayerRole.leftWing,
          PlayerRole.rightWing,
          PlayerRole.striker,
        ]),
      );
    });

    test('4-3-3 uses the LB-CB-CB-RB / CM-DM-CM / LW-ST-RW block (plan 25)',
        () {
      final roles = formationPlan(FormationType.wing433)
          .spots
          .map((spot) => spot.role)
          .toList();
      expect(roles, [
        PlayerRole.goalkeeper,
        PlayerRole.leftBack,
        PlayerRole.centerBackLeft,
        PlayerRole.centerBackRight,
        PlayerRole.rightBack,
        PlayerRole.midfieldLeft,
        PlayerRole.defensiveMidfielder,
        PlayerRole.midfieldRight,
        PlayerRole.leftWing,
        PlayerRole.striker,
        PlayerRole.rightWing,
      ]);
    });

    test('4-6-0 has no fixed striker — the zone exists as behaviour (plan 27)',
        () {
      final roles = formationPlan(FormationType.false460)
          .spots
          .map((spot) => spot.role)
          .toList();
      expect(roles, isNot(contains(PlayerRole.striker)));
      expect(
        formationShapeProfile(FormationType.false460).interiorInterchange,
        isTrue,
      );
    });

    test('4-2-4 fields four forwards and its wings track back (plan 26)', () {
      final plan = formationPlan(FormationType.brazil424);
      expect(plan.spots.where((spot) => spot.role.isAttacker).length, 4);
      expect(
        formationShapeProfile(FormationType.brazil424).wingsDropInDefense,
        isTrue,
      );
    });

    test('every formation owns all five shape parameters (plan 24)', () {
      for (final type in playableFormationTypes) {
        final profile = formationShapeProfile(type);
        expect(profile.attackingLineHeight, greaterThan(0));
        expect(profile.defensiveBlockDrop, greaterThan(0));
        expect(profile.pressingLineHeight, greaterThan(0));
        expect(profile.transitionDrop, greaterThan(0));
      }
    });

    test('new roles carry freedom, zones and tilt metadata (plan 2, 7, 21)',
        () {
      expect(PlayerRole.sweeper.movementFreedom,
          greaterThan(PlayerRole.centerBackLeft.movementFreedom));
      expect(PlayerRole.attackingMidfielder.movementFreedom,
          greaterThan(PlayerRole.centerBackRight.movementFreedom));
      expect(PlayerRole.centerBackLeft.maxAdvance,
          lessThan(PlayerRole.striker.maxAdvance));
      expect(PlayerRole.defensiveMidfielder.minAdvance,
          greaterThan(PlayerRole.centerBackLeft.minAdvance));
      expect(PlayerRole.leftWing.ballSideTilt, greaterThan(0));
    });
  });

  // -------------------------------------------------------------------
  // Danger zones (plan item 13)
  // -------------------------------------------------------------------
  group('danger zones', () {
    const mapper = DangerMapper();

    test('zones escalate toward the goal', () {
      final far = mapper.zoneFor(Vec2(600, 90), TeamSide.left);
      final mid = mapper.zoneFor(Vec2(320, 140), TeamSide.left);
      final hot = mapper.zoneFor(Vec2(230, 350), TeamSide.left);
      final box = mapper.zoneFor(Vec2(90, 350), TeamSide.left);

      expect(far, DangerZone.safe);
      expect(mid, DangerZone.medium);
      expect(hot, anyOf(DangerZone.dangerous, DangerZone.critical));
      expect(box, DangerZone.critical);
    });
  });

  // -------------------------------------------------------------------
  // Team states, shapes, lines, risk (plan items 3, 5, 9, 10, 16, 17)
  // -------------------------------------------------------------------
  group('tactical engine', () {
    test('possession, transitions and organised defence follow the ball', () {
      final engine = MatchEngine(_setup());
      final blue = engine.blueTeam;
      final red = engine.redTeam;

      // Blue wins possession (fresh kick-off, no previous possessor). The
      // carrier is parked at the top touchline so the frozen kick-off
      // geometry never brings an opponent into tackle range.
      blue.players[9].pos.setFrom(Vec2(500, 110));
      engine.ball.attachTo(blue.players[9]);
      engine.tick(0.05);
      expect(engine.currentPlayState(blue), TeamPlayState.possession);
      expect(engine.currentPlayState(red).outOfPossession, isTrue);

      // Red steals it: blue goes through the defensive transition (plan 16)
      // before settling into the organised defence.
      red.players[9].pos.setFrom(Vec2(700, 110));
      engine.ball.attachTo(red.players[9]);
      engine.tick(0.05);
      expect(
          engine.currentPlayState(blue), TeamPlayState.defensiveTransition);
      engine.possessionStateTimer = 10;
      engine.tick(0.05);
      expect(engine.currentPlayState(blue), TeamPlayState.organizedDefense);
    });

    test('defensive line drops when the danger approaches (plan 9, 13)', () {
      final engine = MatchEngine(_setup());
      final blue = engine.blueTeam;
      final carrier = engine.redTeam.players[10];

      // Ball far from the blue goal → relatively advanced line.
      carrier.pos.setFrom(Vec2(1000, 350));
      engine.ball.attachTo(carrier);
      var context = engine.tacticalContextFor(blue);
      final farLine = context.defensiveLineX - GameConstants.leftBound;

      // Ball at the blue box → the line is pinned deep.
      carrier.pos.setFrom(Vec2(GameConstants.leftBound + 80, 350));
      engine.ball.attachTo(carrier);
      context = engine.tacticalContextFor(blue);
      final pinnedLine = context.defensiveLineX - GameConstants.leftBound;

      expect(pinnedLine, lessThan(farLine));
    });

    test('attackers hold the offside line in possession (plan 10)', () {
      final engine = MatchEngine(_setup());
      final blue = engine.blueTeam;
      final striker =
          blue.players.firstWhere((p) => p.role == PlayerRole.striker);

      striker.pos.setFrom(Vec2(GameConstants.virtualWidth - 150, 350));
      engine.ball.attachTo(blue.players[6]);
      final context = engine.tacticalContextFor(blue);
      final target = context.dynamicAnchor(striker);
      final beyond =
          (target.x - engine.offsideLineFor(blue)) * blue.attackDirection;
      expect(beyond, lessThanOrEqualTo(9.0));
    });

    test('compactness: organised defence is tighter than possession (plan 5)',
        () {
      const tactical = TacticalEngine();
      final defenseTarget = tactical.targetCompactnessFor(
        TeamPlayState.organizedDefense,
        AiPlayStyle.balanced,
        0,
      );
      final attackTarget = tactical.targetCompactnessFor(
        TeamPlayState.possession,
        AiPlayStyle.balanced,
        0,
      );
      expect(defenseTarget, greaterThan(attackTarget));
    });

    test('risk follows the score and the clock (plan 17)', () {
      final engine = MatchEngine(_setup());
      final blue = engine.blueTeam;
      final red = engine.redTeam;
      const tactical = TacticalEngine();
      final anyZone = DangerZone.medium;
      final anyState = TeamPlayState.possession;

      engine.minute = 30;
      final neutral = tactical.riskLevelFor(
          blue, red, engine, AiPlayStyle.balanced, anyZone, anyState);

      red.score = 1;
      engine.minute = 85;
      final chasing = tactical.riskLevelFor(
          blue, red, engine, AiPlayStyle.balanced, anyZone, anyState);

      blue.score = 1;
      red.score = 0;
      final protecting = tactical.riskLevelFor(
          blue, red, engine, AiPlayStyle.balanced, anyZone, anyState);

      expect(chasing, greaterThan(neutral));
      expect(protecting, lessThan(neutral));
    });

    test('dynamic target leans toward the ball — never a fixed point (22, 28)',
        () {
      final engine = MatchEngine(_setup());
      final blue = engine.blueTeam;
      final dm = blue.players
          .firstWhere((p) => p.role == PlayerRole.defensiveMidfielder);

      blue.players[6].pos.setFrom(Vec2(300, 170));
      engine.ball.attachTo(blue.players[6]);
      final top = engine.tacticalContextFor(blue).dynamicAnchor(dm);

      blue.players[6].pos.setFrom(Vec2(300, 530));
      engine.ball.attachTo(blue.players[6]);
      final bottom = engine.tacticalContextFor(blue).dynamicAnchor(dm);

      expect(top.y, lessThan(bottom.y),
          reason: 'the block must lean toward the ball side (plan 7)');
    });

    test('4-3-3 drops its wings in defence and pushes its fullbacks in '
        'possession (plan 25)', () {
      final engine = MatchEngine(_setup());
      final blue = engine.blueTeam;
      final winger =
          blue.players.firstWhere((p) => p.role == PlayerRole.leftWing);
      final leftBack =
          blue.players.firstWhere((p) => p.role == PlayerRole.leftBack);

      // Organised defence (red holds the ball, counter-press expired).
      engine.ball.attachTo(engine.redTeam.players[6]);
      engine.possessionStateTimer = 10;
      final defensive = engine.tacticalContextFor(blue);
      final wingerDrop = defensive.shapeAnchor(winger).x;
      final wingerBase = defensive.baseAnchor(winger).x;
      expect(wingerDrop, lessThan(wingerBase),
          reason: 'the winger drops behind his base line: 4-3-3 → 4-5-1');

      // Possession: the fullback advances beyond his base line (2-3-5 feel).
      engine.ball.attachTo(blue.players[6]);
      final attacking = engine.tacticalContextFor(blue);
      final backPush = attacking.shapeAnchor(leftBack).x;
      final backBase = attacking.baseAnchor(leftBack).x;
      expect(backPush, greaterThan(backBase));
    });

    test('false nine: 4-6-0 sends the most advanced interior player into the '
        'striker zone (plan 27)', () {
      final engine = MatchEngine(_setup(
        blueFormation: FormationType.false460,
      ));
      final blue = engine.blueTeam;
      expect(
        blue.players.map((p) => p.role),
        isNot(contains(PlayerRole.striker)),
      );

      engine.ball.attachTo(blue.players[6]);
      final context = engine.tacticalContextFor(blue);
      expect(context.falseNineId, isNotNull);
      final falseNine =
          blue.players.firstWhere((p) => p.id == context.falseNineId);
      final target = context.dynamicAnchor(falseNine);
      final advance = (target.x - GameConstants.leftBound) /
          GameConstants.pitchWidth;
      expect(advance, greaterThan(0.4),
          reason: 'the false nine attacks the advanced striker zone');
    });

    test('full AI simulation keeps every player inside the pitch', () {
      final engine = MatchEngine(_setup(aiControlled: true));
      for (var i = 0; i < 900; i++) {
        engine.tick(1 / 60);
      }
      for (final team in [engine.blueTeam, engine.redTeam]) {
        for (final player in team.players) {
          if (player.isSentOff) {
            continue;
          }
          expect(
            player.pos.x,
            inInclusiveRange(25, GameConstants.virtualWidth - 25),
            reason: '${team.name} ${player.role.code} left the pitch',
          );
          expect(
            player.pos.y,
            inInclusiveRange(25, GameConstants.virtualHeight - 25),
            reason: '${team.name} ${player.role.code} left the pitch',
          );
        }
      }
    });
  });
}
