import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:new_football/src/game/config/game_constants.dart';
import 'package:new_football/src/game/enums/kick_type.dart';
import 'package:new_football/src/game/enums/match_mode.dart';
import 'package:new_football/src/game/enums/player_role.dart';
import 'package:new_football/src/game/enums/team_id.dart';
import 'package:new_football/src/game/logic/ball_physics.dart';
import 'package:new_football/src/game/logic/goalkeeper_prediction.dart';
import 'package:new_football/src/game/logic/match_engine.dart';
import 'package:new_football/src/game/logic/shot_calculator.dart';
import 'package:new_football/src/game/math/vec2.dart';
import 'package:new_football/src/game/models/ball_game.dart';
import 'package:new_football/src/game/models/formation.dart';
import 'package:new_football/src/game/models/goalkeeper.dart';
import 'package:new_football/src/game/models/jersey_kit.dart';
import 'package:new_football/src/game/models/match_event.dart';
import 'package:new_football/src/game/models/player_game.dart';
import 'package:new_football/src/game/models/player_profile.dart';
import 'package:new_football/src/game/models/shooting.dart';
import 'package:new_football/src/game/models/team_profile.dart';
import 'package:new_football/src/game/models/team_setup.dart';
import 'package:new_football/src/storage/roster_storage.dart';

/// Builds a match setup from the default saved game (LIG MODU removed).
MatchSetup _testMatchSetup() {
  final data = SavedGameData.defaults();
  return MatchSetup(
    mode: MatchMode.knockout,
    blue: TeamSetup(
      id: TeamId.blue,
      name: data.blueName,
      formation: data.blueFormation,
      players: data.players
          .where((player) => data.bluePlayerIds.contains(player.id))
          .toList(),
      starterPlayerIds: data.blueTeam.starterPlayerIds,
      roleByPlayerId: data.blueTeam.roleByPlayerId,
      slotByPlayerId: data.blueTeam.slotByPlayerId,
      storageTeamId: data.blueTeam.id,
      rating: data.blueTeam.rating,
      jerseyKit: data.blueTeam.activeKit,
      goalkeeperKit: data.blueTeam.goalkeeperKit,
    ),
    red: TeamSetup(
      id: TeamId.red,
      name: data.redName,
      formation: data.redFormation,
      players: data.players
          .where((player) => data.redPlayerIds.contains(player.id))
          .toList(),
      starterPlayerIds: data.redTeam.starterPlayerIds,
      roleByPlayerId: data.redTeam.roleByPlayerId,
      slotByPlayerId: data.redTeam.slotByPlayerId,
      storageTeamId: data.redTeam.id,
      rating: data.redTeam.rating,
      jerseyKit: data.redTeam.activeKit,
      goalkeeperKit: data.redTeam.goalkeeperKit,
    ),
  );
}

void main() {
  group('match modes', () {
    test('both Eleme and Lig maci exist', () {
      expect(MatchMode.values.length, 2);
      expect(MatchMode.league.title, 'Lig maci');
      expect(MatchMode.knockout.title, 'Eleme');
    });
  });

  group('local account security', () {
    test('different passwords produce different hashes', () {
      expect(localPasswordHash('alpha'), isNot(localPasswordHash('bravo')));
      expect(localPasswordHash('alpha'), localPasswordHash(' alpha '));
    });
  });

  group('player availability', () {
    test('cards and match suspension survive JSON round trip', () {
      final player = PlayerProfile.generated(
        name: 'Test Player',
        isGoalkeeper: false,
      )
        ..dayaniklilikGucu = 88
        ..finishingRating = 84
        ..shotPowerRating = 91
        ..longShotsRating = 79
        ..curveRating = 82
        ..composureRating = 86
        ..balanceRating = 77
        ..goalkeeperReactionRating = 89
        ..goalkeeperPositioningRating = 87
        ..goalkeeperCatchingRating = 84
        ..goalkeeperParryingRating = 86
        ..preferredFoot = PreferredFoot.left
        ..weakFootRating = 4
        ..yellowCards = 4
        ..redCards = 1
        ..suspendedMatchesRemaining = 3
        ..injuredDaysRemaining = 14;

      final restored = PlayerProfile.fromJson(player.toJson());
      expect(restored.dayaniklilikGucu, 88);
      expect(restored.finishingRating, 84);
      expect(restored.shotPowerRating, 91);
      expect(restored.longShotsRating, 79);
      expect(restored.curveRating, 82);
      expect(restored.composureRating, 86);
      expect(restored.balanceRating, 77);
      expect(restored.goalkeeperReactionRating, 89);
      expect(restored.goalkeeperPositioningRating, 87);
      expect(restored.goalkeeperCatchingRating, 84);
      expect(restored.goalkeeperParryingRating, 86);
      expect(restored.preferredFoot, PreferredFoot.left);
      expect(restored.weakFootRating, 4);
      expect(restored.yellowCards, 4);
      expect(restored.redCards, 1);
      expect(restored.suspendedMatchesRemaining, 3);
      expect(restored.isUnavailable, isTrue);

      restored.advanceUnavailableStatusAfterTeamMatch();
      expect(restored.suspendedMatchesRemaining, 2);
      expect(restored.injuredDaysRemaining, 5);
    });
  });

  group('jersey kits', () {
    test('includes the ten expanded color choices', () {
      final kits = JerseyFactory.defaultKits();
      expect(kits.length, 13);
      expect(kits.map((kit) => kit.name).toSet().length, 13);
    });

    test('old saved kits are expanded without duplicates', () {
      final oldKits = JerseyFactory.defaultKits().take(3);
      final expanded = JerseyFactory.completeKits(oldKits);
      expect(expanded.length, 13);
    });
  });

  group('realistic shot calculator', () {
    const weak = PlayerShootingStats(
      shooting: 0.55,
      finishing: 0.50,
      shotPower: 0.65,
      longShots: 0.40,
      curve: 0.35,
      composure: 0.35,
      balance: 0.45,
      preferredFoot: PreferredFoot.right,
      weakFoot: 2,
    );
    const worldClass = PlayerShootingStats(
      shooting: 0.94,
      finishing: 0.94,
      shotPower: 0.94,
      longShots: 0.91,
      curve: 0.91,
      composure: 0.94,
      balance: 0.93,
      preferredFoot: PreferredFoot.right,
      weakFoot: 5,
    );

    ShotContext context(
      PlayerShootingStats stats, {
      double distance = 18,
      ShotType type = ShotType.normal,
      double pressure = 4,
    }) {
      return ShotContext(
        stats: stats,
        playerPosition: Vec2(300, 350),
        intendedTarget: Vec2(1150, 320),
        facingAngleDegrees: 10,
        distanceMeters: distance,
        nearestDefenderMeters: pressure,
        movementRatio: 0.45,
        sprinting: false,
        turning: false,
        incomingBallSpeed: 0,
        ballHeight: 0,
        bodyLean: 0,
        supportFootQuality: 0.9,
        usingPreferredFoot: true,
        firstTime: false,
        fatigue: 0.1,
        powerInput: 0.68,
        shotType: type,
        goalWidthPixels: GameConstants.goalPixelHeight,
        freeKick: false,
      );
    }

    test('level presets match the supplied shooting plan', () {
      final weakPreset = PlayerShootingStats.forLevel(PlayerLevel.weak);
      final worldPreset = PlayerShootingStats.forLevel(PlayerLevel.worldClass);
      expect(weakPreset.shooting, 0.55);
      expect(weakPreset.shotPower, 0.65);
      expect(worldPreset.finishing, 0.94);
      expect(worldPreset.longShots, 0.91);
      expect(worldPreset.balance, 0.93);
    });

    test('world-class players produce a tighter Gaussian spread', () {
      final weakCalculator = ShotCalculator(math.Random(11));
      final worldCalculator = ShotCalculator(math.Random(11));
      var weakError = 0.0;
      var worldError = 0.0;
      for (var index = 0; index < 1000; index++) {
        weakError += weakCalculator.calculate(context(weak)).lateralError.abs();
        worldError += worldCalculator
            .calculate(context(worldClass))
            .lateralError
            .abs();
      }
      expect(worldError / 1000, lessThan(weakError / 1000));
    });

    test('curve is executed by ball physics instead of changing accuracy', () {
      final shooter = PlayerGame(
        profile: PlayerProfile.generated(name: 'Curve', isGoalkeeper: false),
        teamId: TeamId.blue,
        role: PlayerRole.striker,
        number: 9,
        position: Vec2(200, 350),
      );
      final ball = BallGame(pos: Vec2(210, 350));
      ball.release(
        direction: Vec2(1, 0),
        power: 1,
        toucher: shooter,
        kickType: KickType.shoot,
        curve: 2,
        spin: 2,
        shotType: ShotType.finesse,
      );
      const BallPhysics().update(ball, 1 / 60);
      expect(ball.vel.y, greaterThan(0));
      expect(ball.curve, lessThan(2));
    });

    test('distance and shot type affect accuracy, height and power', () {
      final calculator = ShotCalculator(math.Random(19));
      final close = calculator.calculate(context(worldClass, distance: 10));
      final far = calculator.calculate(context(worldClass, distance: 32));
      final ground = calculator.calculate(
        context(worldClass, type: ShotType.ground),
      );
      final power = calculator.calculate(
        context(worldClass, type: ShotType.power),
      );
      expect(close.accuracy, greaterThan(far.accuracy));
      expect(ground.targetHeight, lessThan(power.targetHeight));
      expect(power.power, greaterThan(ground.power));
    });
  });

  group('goalkeeper prediction model', () {
    GoalkeeperContext context({double ballY = 350, double curve = 0}) {
      return GoalkeeperContext(
        goalkeeperPosition: Vec2(68, 350),
        goalkeeperHeight: 1.88,
        goalCenter: Vec2(68, 350),
        goalTop: 285,
        goalBottom: 415,
        goalLineX: 68,
        ballPosition: Vec2(300, ballY),
        ballVelocity: Vec2(-6, 0),
        ballHeight: 0.6,
        ballVerticalVelocity: 1.2,
        ballCurve: curve,
        shotType: ShotType.normal,
        shooterPosition: Vec2(310, 350),
        nearestDefenderDistance: 3,
        numberOfAttackers: 1,
        isBallOwned: false,
        isCross: false,
        isOneVsOne: false,
        isThroughBall: false,
        isCorner: false,
        isFreeKick: false,
        visibilityFactor: 1,
        fatigue: 0,
      );
    }

    test('goalkeeper level presets match the supplied plan', () {
      final weak = GoalkeeperStats.forLevel(PlayerLevel.weak);
      final world = GoalkeeperStats.forLevel(PlayerLevel.worldClass);
      expect(weak.reaction, 0.45);
      expect(weak.catching, 0.40);
      expect(world.positioning, 0.96);
      expect(world.diving, 0.96);
      expect(world.highBalls, 0.94);
    });

    test('world-class prediction has tighter human error and confidence', () {
      final weakStats = GoalkeeperStats.forLevel(PlayerLevel.weak);
      final worldStats = GoalkeeperStats.forLevel(PlayerLevel.worldClass);
      final weakPredictor = GoalkeeperPredictor(math.Random(31));
      final worldPredictor = GoalkeeperPredictor(math.Random(31));
      var weakError = 0.0;
      var worldError = 0.0;
      var weakConfidence = 0.0;
      var worldConfidence = 0.0;
      for (var index = 0; index < 1000; index++) {
        final weak = weakPredictor.predict(weakStats, context());
        final world = worldPredictor.predict(worldStats, context());
        weakError += (weak.predictedImpact.y - 350).abs();
        worldError += (world.predictedImpact.y - 350).abs();
        weakConfidence += weak.confidence;
        worldConfidence += world.confidence;
      }
      expect(worldError, lessThan(weakError));
      expect(worldConfidence, greaterThan(weakConfidence));
    });
  });

  group('goalkeeper recovery', () {
    test('keeper moves only during the dive and stays locked after landing', () {
      final profile = PlayerProfile.generated(
        name: 'Recovery Keeper',
        isGoalkeeper: true,
      )..speedRating = 80;
      final keeper = PlayerGame(
        profile: profile,
        teamId: TeamId.blue,
        role: PlayerRole.goalkeeper,
        number: 1,
        position: Vec2.zero(),
      );
      final standingSpeed = keeper.speed;

      keeper
        ..keeperState = 'atlayis'
        ..keeperGroundTimer = 1.4
        ..jumpAnimationTimer = 0.62;
      final diveSpeed = keeper.speed;
      expect(diveSpeed, greaterThan(0));
      expect(diveSpeed, lessThan(standingSpeed));

      keeper
        ..keeperState = 'yerde'
        ..jumpAnimationTimer = 0.05;
      expect(keeper.speed, 0);

      keeper.keeperGroundTimer = 0;
      expect(keeper.speed, standingSpeed);
    });

    test('keeper cannot distribute while down or recollect his own release', () {
      final setup = _testMatchSetup();
      final engine = MatchEngine(setup);
      final keeper = engine.blueTeam.goalkeeper;
      engine.ball.attachTo(keeper);

      keeper.keeperGroundTimer = 1.2;
      expect(
        engine.distributeFromGoalkeeper(keeper, high: false),
        isFalse,
      );
      expect(engine.ball.owner, keeper);

      keeper.keeperGroundTimer = 0;
      expect(
        engine.distributeFromGoalkeeper(keeper, high: false),
        isTrue,
      );
      expect(engine.ball.owner, isNull);
      expect(engine.ball.lastTouch, keeper);
      expect(keeper.keeperRehandleCooldown, greaterThanOrEqualTo(1.35));
    });
  });

  group('discipline and substitutions', () {
    test('red cards always carry a two-match suspension', () {
      expect(GameConstants.redCardSuspensionMatches, 2);
    });

    test('position swaps are free and injury bonus raises the limit', () {
      final setup = _testMatchSetup();
      final engine = MatchEngine(setup);
      final team = engine.blueTeam;
      final firstProfile = team.players[1].profile;
      final secondProfile = team.players[2].profile;

      expect(team.swapPlayerPositions(1, 2), isTrue);
      expect(team.players[1].profile, secondProfile);
      expect(team.players[2].profile, firstProfile);
      expect(team.substitutionsUsed, 0);
      expect(team.substitutionLimit, 5);

      team
        ..substitutionsUsed = 5
        ..bonusSubstitutions = 1;
      expect(team.substitutionLimit, 6);
      final fieldBenchIndex = team.bench.indexWhere(
        (player) => !player.profile.isGoalkeeper,
      );
      expect(fieldBenchIndex, greaterThanOrEqualTo(0));
      expect(team.substitute(1, fieldBenchIndex), isTrue);
      expect(team.substitutionsUsed, 6);
    });
  });

  group('saved formations', () {
    test('assigns unique compatible slots and restores a named preset', () {
      final players = [
        PlayerProfile.generated(name: 'Keeper', isGoalkeeper: true),
        for (var index = 0; index < 10; index++)
          PlayerProfile.generated(name: 'Player $index', isGoalkeeper: false),
      ];
      final team = SavedTeamProfile.create(
        ownerAccountId: 'owner',
        name: 'Test Team',
        playerIds: players.map((player) => player.id),
        formation: FormationType.wing433,
      );
      team.ensureLineupDefaults(players);

      expect(team.slotByPlayerId.length, 11);
      expect(team.slotByPlayerId.values.toSet().length, 11);
      final plan = formationPlan(team.formation);
      for (final entry in team.slotByPlayerId.entries) {
        final player = players.firstWhere((item) => item.id == entry.key);
        expect(
          plan.spots[entry.value].role.isGoalkeeper,
          player.isGoalkeeper,
        );
      }

      final preset = team.saveCurrentFormation('Best Eleven');
      team
        ..formation = FormationType.classic442
        ..slotByPlayerId.clear();
      team.applyFormationPreset(preset);
      team.ensureLineupDefaults(players);
      expect(team.formation, FormationType.wing433);
      expect(team.activeFormationPresetId, preset.id);
      expect(team.slotByPlayerId.length, 11);

      final restored = SavedTeamProfile.fromJson(
        team.toJson(),
        fallbackOwnerAccountId: 'owner',
      );
      expect(restored.savedFormations.single.name, 'Best Eleven');
      expect(restored.slotByPlayerId, team.slotByPlayerId);
    });
  });

  group('match archive', () {
    test('preserves real goals and complete player performance', () {
      final summary = FinishedMatchSummary(
        matchId: 'match-1',
        blueStorageTeamId: 'blue-team',
        redStorageTeamId: 'red-team',
        blueName: 'Blue',
        redName: 'Red',
        blueScore: 1,
        redScore: 0,
        blueRatingDelta: 1.2,
        redRatingDelta: -1.2,
        bluePossessionPercent: 55,
        redPossessionPercent: 45,
        bluePasses: 400,
        redPasses: 350,
        blueSuccessfulPasses: 330,
        redSuccessfulPasses: 270,
        blueShots: 9,
        redShots: 6,
        timestamp: 123456,
        goals: const [
          FinishedGoalSummary(
            teamId: TeamId.blue,
            scorerName: 'Real Scorer',
            minute: 37,
            isPenalty: false,
          ),
        ],
        playerStats: const [
          FinishedPlayerSummary(
            playerId: 'player-1',
            teamId: TeamId.blue,
            name: 'Real Scorer',
            number: 9,
            role: 'SF',
            minutes: 90,
            goals: 1,
            assists: 0,
            passes: 31,
            successfulPasses: 25,
            dribbles: 4,
            successfulDribbles: 3,
            tackles: 1,
            shots: 4,
            shotsOnTarget: 2,
            missedChances: 1,
            clearances: 0,
            saves: 0,
            foulsCommitted: 1,
            foulsReceived: 2,
            yellowCards: 0,
            redCards: 0,
            rating: 8.2,
            staminaPercent: 72,
            injured: false,
          ),
        ],
      );

      final restored = FinishedMatchSummary.fromJson(summary.toJson());
      expect(restored.goals.single.scorerName, 'Real Scorer');
      expect(restored.goals.single.minute, 37);
      expect(restored.playerStats.single.shotsOnTarget, 2);
      expect(restored.playerStats.single.rating, 8.2);

      final data = SavedGameData.defaults();
      data.archiveMatch(summary);
      final restoredData = SavedGameData.fromJson(data.toJson());
      expect(restoredData.matchArchive.single.matchId, 'match-1');
    });
  });

  group('shot speed realism', () {
    test('shots are clearly faster than passes', () {
      final engine = MatchEngine(_testMatchSetup());
      final shooter = engine.blueTeam.players[1];
      shooter.profile.shotPowerRating = 70;
      shooter.profile.passingRating = 70;
      engine.ball
        ..owner = shooter
        ..pos = shooter.pos.copy();
      engine.releaseFromPlayer(
        shooter,
        Vec2(1, 0),
        1.0,
        type: KickType.shoot,
      );
      final shotSpeed = engine.ball.vel.length;

      final passer = engine.blueTeam.players[2];
      engine.ball
        ..owner = passer
        ..pos = passer.pos.copy();
      engine.releaseFromPlayer(
        passer,
        Vec2(1, 0),
        1.0,
        type: KickType.pass,
      );
      final passSpeed = engine.ball.vel.length;
      expect(shotSpeed, greaterThan(passSpeed));
    });

    test('shot speed scales with shot power rating', () {
      final weak = MatchEngine(_testMatchSetup());
      final weakShooter = weak.blueTeam.players[1];
      weakShooter.profile.shotPowerRating = 30;
      weak.ball
        ..owner = weakShooter
        ..pos = weakShooter.pos.copy();
      weak.releaseFromPlayer(
        weakShooter,
        Vec2(1, 0),
        1.0,
        type: KickType.shoot,
      );
      final weakSpeed = weak.ball.vel.length;

      final strong = MatchEngine(_testMatchSetup());
      final strongShooter = strong.blueTeam.players[1];
      strongShooter.profile.shotPowerRating = 95;
      strong.ball
        ..owner = strongShooter
        ..pos = strongShooter.pos.copy();
      strong.releaseFromPlayer(
        strongShooter,
        Vec2(1, 0),
        1.0,
        type: KickType.shoot,
      );
      final strongSpeed = strong.ball.vel.length;
      expect(strongSpeed, greaterThan(weakSpeed * 1.08));
    });

    test('high pass keeps a forward cruise speed while airborne', () {
      final engine = MatchEngine(_testMatchSetup());
      final passer = engine.blueTeam.players[1];
      engine.ball
        ..owner = passer
        ..pos = passer.pos.copy();
      engine.releaseFromPlayer(
        passer,
        Vec2(1, 0),
        1.0,
        type: KickType.highPass,
        loft: 5.0,
      );
      expect(engine.ball.highPassCruiseSpeed, greaterThan(0));
      expect(engine.ball.lastPassWasHigh, isTrue);
    });
  });

  group('clean pass tracking', () {
    test('opponent touch clears the clean-pass marker', () {
      final engine = MatchEngine(_testMatchSetup());
      final passer = engine.blueTeam.players[1];
      final receiver = engine.blueTeam.players[2];
      final opponent = engine.redTeam.players.firstWhere(
        (player) => !player.isGoalkeeper,
      );
      engine.ball
        ..owner = passer
        ..pos = passer.pos.copy();
      engine.releaseFromPlayer(
        passer,
        receiver.pos - passer.pos,
        0.8,
        type: KickType.pass,
        target: receiver,
      );
      expect(engine.ball.potentialAssister, passer);
      engine.ball.attachTo(opponent);
      expect(engine.ball.potentialAssister, isNull);
    });
  });

  group('market value', () {
    test('fresh players start at 1 billion and stay until they play', () {
      final player = PlayerProfile.generated(name: 'New', isGoalkeeper: false);
      expect(player.marketValue, 1000000000);
      player.recalculateMarketValue(strong: false);
      expect(player.marketValue, 1000000000);
      player.recalculateMarketValue(strong: true);
      expect(player.marketValue, 1000000000);
    });

    test('good performances raise the value, strong moves it more', () {
      final player = PlayerProfile.generated(name: 'Star', isGoalkeeper: false);
      player
        ..matchesPlayed = 10
        ..minutesPlayed = 900
        ..goals = 12
        ..assists = 4
        ..points = 82
        ..addMatchRecord(
          PlayerMatchRecord(
            matchId: 'm1',
            teamName: 'T',
            opponentName: 'O',
            scoreText: '2-0',
            minutes: 90,
            goals: 2,
            assists: 1,
            passes: 30,
            successfulPasses: 25,
            dribbles: 4,
            successfulDribbles: 3,
            tackles: 1,
            shots: 5,
            shotsOnTarget: 3,
            missedChances: 1,
            clearances: 0,
            saves: 0,
            foulsCommitted: 1,
            foulsReceived: 2,
            yellowCards: 0,
            redCards: 0,
            rating: 8.5,
            injured: false,
          ),
        );
      player.recalculateMarketValue(strong: false);
      final lightValue = player.marketValue;
      expect(lightValue, greaterThan(1000000000));
      player.recalculateMarketValue(strong: true);
      expect(player.marketValue, greaterThan(lightValue));
      expect(player.marketValueText, isNotEmpty);
      expect(player.marketValueFull, isNotEmpty);
    });

    test('market value survives JSON round trip', () {
      final player = PlayerProfile.generated(name: 'P', isGoalkeeper: true)
        ..marketValue = 7500000000;
      final restored = PlayerProfile.fromJson(player.toJson());
      expect(restored.marketValue, 7500000000);
    });
  });

  group('daily injury recovery', () {
    test('injury days decrease one per real day', () {
      final player = PlayerProfile.generated(name: 'Hasta', isGoalkeeper: false);
      final now = DateTime.now();
      player
        ..injuredDaysRemaining = 10
        ..injuryUpdatedAt = now
            .subtract(const Duration(days: 3))
            .millisecondsSinceEpoch;
      expect(player.recoverInjuryDays(now), isTrue);
      expect(player.injuredDaysRemaining, 7);
      // Same day again: no double recovery.
      expect(player.recoverInjuryDays(now), isFalse);
      expect(player.injuredDaysRemaining, 7);
    });

    test('injury timestamp survives JSON round trip', () {
      final player = PlayerProfile.generated(name: 'Hasta', isGoalkeeper: false)
        ..injuredDaysRemaining = 5
        ..injuryUpdatedAt = 123456789;
      final restored = PlayerProfile.fromJson(player.toJson());
      expect(restored.injuredDaysRemaining, 5);
      expect(restored.injuryUpdatedAt, 123456789);
    });
  });

  group('ban fields for penalties page', () {
    test('banMatches/isBanned stay in sync with suspension', () {
      final player = PlayerProfile.generated(
        name: 'Banned',
        isGoalkeeper: false,
      );
      expect(player.isBanned, isFalse);
      player.banMatches = 4;
      expect(player.banMatches, 4);
      expect(player.suspendedMatchesRemaining, 4);
      expect(player.isBanned, isTrue);
      player.banMatches = 0;
      expect(player.isBanned, isFalse);
    });
  });
}
