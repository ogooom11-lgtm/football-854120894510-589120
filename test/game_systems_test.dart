import 'package:flutter_test/flutter_test.dart';

import 'package:new_football/src/game/enums/player_role.dart';
import 'package:new_football/src/game/enums/team_id.dart';
import 'package:new_football/src/game/logic/match_engine.dart';
import 'package:new_football/src/game/math/vec2.dart';
import 'package:new_football/src/game/models/formation.dart';
import 'package:new_football/src/game/models/jersey_kit.dart';
import 'package:new_football/src/game/models/league.dart';
import 'package:new_football/src/game/models/match_event.dart';
import 'package:new_football/src/game/models/player_game.dart';
import 'package:new_football/src/game/models/player_profile.dart';
import 'package:new_football/src/game/models/team_profile.dart';
import 'package:new_football/src/storage/roster_storage.dart';

void main() {
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
        ..yellowCards = 4
        ..redCards = 1
        ..suspendedMatchesRemaining = 3
        ..injuredDaysRemaining = 14;

      final restored = PlayerProfile.fromJson(player.toJson());
      expect(restored.dayaniklilikGucu, 88);
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
      final setup = LeagueFactory.createDefaultSeason().createCurrentMatchSetup();
      expect(setup, isNotNull);
      final engine = MatchEngine(setup!);
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

  group('league progression', () {
    test('current fixture follows matchday order', () {
      final season = LeagueFactory.createDefaultSeason();
      final first = season.currentFixture!;
      expect(first.matchday, 1);

      season.recordResult(first, 1, 0, const ['Golcu'], const []);
      expect(season.currentFixture!.matchday, 1);
      expect(season.currentMatchday, 1);
    });

    test('champion is persisted', () {
      final season = LeagueFactory.createDefaultSeason();
      while (!season.seasonFinished) {
        final fixture = season.currentFixture!;
        season.recordResult(fixture, 1, 0, const ['Golcu'], const []);
      }

      final restored = LeagueSeason.fromJson(season.toJson());
      expect(restored.seasonFinished, isTrue);
      expect(restored.championTeamName, season.championTeamName);
    });
  });
}
