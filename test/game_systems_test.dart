import 'package:flutter_test/flutter_test.dart';

import 'package:new_football/src/game/models/jersey_kit.dart';
import 'package:new_football/src/game/models/league.dart';
import 'package:new_football/src/game/models/player_profile.dart';
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
