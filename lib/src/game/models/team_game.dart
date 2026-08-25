import 'dart:math' as math;
import 'dart:ui';

import '../config/game_constants.dart';
import '../enums/player_role.dart';
import '../enums/team_id.dart';
import '../math/vec2.dart';
import 'formation.dart';
import 'goalkeeper.dart';
import 'jersey_kit.dart';
import 'match_event.dart';
import 'player_game.dart';
import 'player_profile.dart';
import 'team_setup.dart';

/// A completed substitution, kept so it can be undone and so the game can
/// show who left the pitch.
class SubstitutionRecord {
  SubstitutionRecord({
    required this.outIndex,
    required this.outgoing,
    required this.incoming,
    required this.benchIndex,
    required this.minute,
    this.reentry = false,
  });

  final int outIndex;
  final PlayerGame outgoing;
  final PlayerGame incoming;
  /// -1 when the incoming player came back from the "substituted out" list
  /// instead of the bench.
  final int benchIndex;
  final double minute;
  /// True when a previously substituted player was brought back onto the
  /// pitch (used to replace an injured or sent-off player).
  final bool reentry;
}

class TeamGame {
  TeamGame({
    required this.id,
    required this.name,
    required this.side,
    required this.color,
    required this.formation,
    required this.players,
    required this.bench,
    this.storageTeamId,
    this.rating = 50,
  });

  final TeamId id;
  final String? storageTeamId;
  final double rating;
  String name;
  TeamSide side;
  Color color;
  JerseyKit? jerseyKit;
  JerseyKit? goalkeeperKit;
  FormationType formation;
  List<PlayerGame> players;
  final List<PlayerGame> bench;
  final List<PlayerGame> substitutedOut = [];
  /// Players who left the match for good (injured or sent off with no
  /// replacement path) — they cannot be brought back.
  final List<PlayerGame> removedFromMatch = [];
  final List<SubstitutionRecord> substitutionLog = [];
  int score = 0;
  int substitutionsUsed = 0;
  int bonusSubstitutions = 0;
  int get substitutionLimit => 5 + bonusSubstitutions;
  final List<GoalEvent> goals = [];

  factory TeamGame.fromSetup({
    required TeamSetup setup,
    required TeamSide side,
    required Color color,
    math.Random? random,
  }) {
    final rng = random ?? math.Random();
    final plan = formationPlan(setup.formation);
    final selected = [
      ...setup.players.where((profile) => !profile.isUnavailable),
    ];
    final selectedById = {for (final profile in selected) profile.id: profile};
    final starterProfiles = <PlayerProfile>[
      for (final id in setup.starterPlayerIds)
        if (selectedById[id] != null) selectedById[id]!,
    ];
    for (final profile in selected) {
      if (starterProfiles.length >= 11) {
        break;
      }
      if (!starterProfiles.contains(profile)) {
        starterProfiles.add(profile);
      }
    }
    final starters = starterProfiles.take(11).toList(growable: true);
    final benchProfiles = selected
        .where((profile) => !starters.contains(profile))
        .toList(growable: true);
    final keeperProfile =
        _takeProfileOrNull(starters, (profile) => profile.isGoalkeeper) ??
        _takeProfileOrNull(benchProfiles, (profile) => profile.isGoalkeeper) ??
        PlayerProfile.generated(
          name: '${setup.name} Kaleci',
          isGoalkeeper: true,
          random: rng,
        );

    final players = <PlayerGame>[];
    for (var spotIndex = 0; spotIndex < plan.spots.length; spotIndex++) {
      final spot = plan.spots[spotIndex];
      final assignedProfile = _takeProfileOrNull(
        starters,
        (profile) =>
            !profile.isGoalkeeper &&
            setup.slotByPlayerId[profile.id] == spotIndex,
      );
      final profile = spot.role.isGoalkeeper
          ? keeperProfile
          : assignedProfile ??
                _takeProfileOrNull(
                  starters,
                  (profile) =>
                      !profile.isGoalkeeper &&
                      setup.roleByPlayerId[profile.id] == spot.role,
                ) ??
                _takeProfileOrNull(
                  starters,
                  (profile) => !profile.isGoalkeeper,
                ) ??
                PlayerProfile.generated(
                  name: '${setup.name} ${spot.number}',
                  isGoalkeeper: false,
                  random: rng,
                );
      players.add(
        PlayerGame(
          profile: profile,
          teamId: setup.id,
          role: spot.role,
          number: profile.number ?? spot.number,
          position: pitchPoint(spot.x, spot.y, side),
        )..stamina = profile.fitness,
      );
    }
    final bench = <PlayerGame>[];
    for (var i = 0; i < benchProfiles.length; i++) {
      final profile = benchProfiles[i];
      bench.add(
        PlayerGame(
          profile: profile,
          teamId: setup.id,
          role: profile.isGoalkeeper
              ? PlayerRole.goalkeeper
              : setup.roleByPlayerId[profile.id] ?? PlayerRole.midfieldLeft,
          number: profile.number ?? 20 + i,
          position: pitchPoint(0.5, 0.5, side),
        )..stamina = profile.fitness,
      );
    }
    final team =
        TeamGame(
            id: setup.id,
            storageTeamId: setup.storageTeamId,
            rating: setup.rating,
            name: setup.name.trim().isEmpty
                ? setup.id.turkishName
                : setup.name.trim(),
            side: side,
            color: color,
            formation: setup.formation,
            players: players,
            bench: bench,
          )
          ..jerseyKit = setup.jerseyKit
          ..goalkeeperKit = setup.goalkeeperKit;
    team.resetDirections();
    return team;
  }

  static PlayerProfile? _takeProfileOrNull(
    List<PlayerProfile> profiles,
    bool Function(PlayerProfile profile) test,
  ) {
    final index = profiles.indexWhere(test);
    if (index == -1) {
      return null;
    }
    return profiles.removeAt(index);
  }

  static Vec2 pitchPoint(double x, double y, TeamSide side) {
    final mirroredX = side == TeamSide.right ? 1 - x : x;
    return Vec2(
      GameConstants.leftBound + GameConstants.pitchWidth * mirroredX,
      GameConstants.topBound + GameConstants.pitchHeight * y,
    );
  }

  int get attackDirection => side == TeamSide.left ? 1 : -1;

  /// The goalkeeper to use right now. Prefers a keeper who is actually able
  /// to play (not sent off, not injured); falls back to any keeper and
  /// finally to any available outfielder so a team can never be left
  /// without a last line.
  PlayerGame get goalkeeper {
    final able = players.where(
      (player) =>
          player.role == PlayerRole.goalkeeper &&
          !player.isSentOff &&
          !player.isInjuredInMatch,
    );
    if (able.isNotEmpty) return able.first;
    final any =
        players.where((player) => player.role == PlayerRole.goalkeeper);
    if (any.isNotEmpty) return any.first;
    return players.firstWhere(
      (player) => !player.isSentOff,
      orElse: () => players.first,
    );
  }

  /// Whether the team currently has a goalkeeper who can actually play.
  bool get hasActiveGoalkeeper =>
      players.any(
        (player) =>
            player.role == PlayerRole.goalkeeper &&
            !player.isSentOff &&
            !player.isInjuredInMatch,
      );

  PlayerGame? playerById(String id) {
    for (final player in players) {
      if (player.id == id) {
        return player;
      }
    }
    return null;
  }

  PlayerGame closestTo(Vec2 point, {bool includeGoalkeeper = false}) {
    final available = players.where((player) => !player.isSentOff);
    final candidates = includeGoalkeeper
        ? available
        : available.where((player) => !player.isGoalkeeper);
    return candidates.reduce(
      (a, b) => a.pos.distanceTo(point) <= b.pos.distanceTo(point) ? a : b,
    );
  }

  void resetPositions() {
    final plan = formationPlan(formation);
    for (var i = 0; i < players.length; i++) {
      final spot = plan.spots[i];
      if (players[i].isSentOff) {
        players[i]
          ..pos = Vec2(-100, -100)
          ..controlled = false;
        continue;
      }
      players[i]
        ..role = spot.role
        ..number = spot.number
        ..homePos = pitchPoint(spot.x, spot.y, side)
        ..pos.setFrom(pitchPoint(spot.x, spot.y, side))
        ..aiCooldown = 0
        ..manualOverride = 0
        ..movementIntensity = 0
        ..turningIntensity = 0
        ..jumpBoostMeters = 0
        ..keeperGroundTimer = 0
        ..keeperDiveCooldown = 0
        ..keeperParryCooldown = 0
        ..keeperRehandleCooldown = 0
        ..goalkeeperState = GoalkeeperState.idle
        ..goalkeeperAction = GoalkeeperAction.stay
        ..goalkeeperVelocity = Vec2.zero()
        ..goalkeeperDecisionTarget = null
        ..goalkeeperPrediction = null
        ..goalkeeperObservedTrajectoryId = -1
        ..goalkeeperReactionTimer = 0
        ..goalkeeperDecisionLockTimer = 0
        ..keeperState = 'hazir';
    }
    resetDirections();
  }

  void updateHomePositionsOnly() {
    final plan = formationPlan(formation);
    for (var i = 0; i < players.length; i++) {
      final spot = plan.spots[i];
      players[i]
        ..role = spot.role
        ..number = spot.number
        ..homePos = pitchPoint(spot.x, spot.y, side);
    }
    resetDirections();
  }

  void switchSide() {
    side = side.opposite;
    updateHomePositionsOnly();
  }

  void resetDirections() {
    for (final player in players) {
      player.lastDirection = Vec2(attackDirection.toDouble(), 0);
      player.controlled = false;
    }
  }

  bool swapPlayerPositions(int firstIndex, int secondIndex) {
    if (firstIndex < 0 ||
        secondIndex < 0 ||
        firstIndex >= players.length ||
        secondIndex >= players.length) {
      return false;
    }
    if (firstIndex == secondIndex) return true;
    final first = players[firstIndex];
    final second = players[secondIndex];
    if (first.isSentOff ||
        second.isSentOff ||
        first.isGoalkeeper != second.isGoalkeeper) {
      return false;
    }
    players[firstIndex] = second;
    players[secondIndex] = first;
    final plan = formationPlan(formation);
    players[firstIndex]
      ..role = plan.spots[firstIndex].role
      ..homePos = pitchPoint(
        plan.spots[firstIndex].x,
        plan.spots[firstIndex].y,
        side,
      );
    players[secondIndex]
      ..role = plan.spots[secondIndex].role
      ..homePos = pitchPoint(
        plan.spots[secondIndex].x,
        plan.spots[secondIndex].y,
        side,
      );
    resetDirections();
    return true;
  }

  bool substitute(
    int outIndex,
    int benchIndex, {
    double minute = 0,
  }) {
    if (substitutionsUsed >= substitutionLimit ||
        outIndex < 0 ||
        outIndex >= players.length ||
        benchIndex < 0 ||
        benchIndex >= bench.length) {
      return false;
    }
    final outgoing = players[outIndex];
    final incoming = bench[benchIndex];
    if (outgoing.isGoalkeeper != incoming.profile.isGoalkeeper) {
      return false;
    }
    final role = outgoing.role;
    final number = incoming.profile.number ?? outgoing.number;
    final position = outgoing.pos.copy();
    final home = outgoing.homePos.copy();
    final replacement =
        PlayerGame(
            profile: incoming.profile,
            teamId: id,
            role: role,
            number: number,
            position: position,
          )
          ..homePos = home
          ..lastDirection = Vec2(attackDirection.toDouble(), 0)
          ..stamina = incoming.stamina;
    players[outIndex] = replacement;
    outgoing.exitedAtMinute = minute;
    substitutedOut.add(outgoing);
    substitutionLog.add(
      SubstitutionRecord(
        outIndex: outIndex,
        outgoing: outgoing,
        incoming: replacement,
        benchIndex: benchIndex,
        minute: minute,
      ),
    );
    bench.removeAt(benchIndex);
    substitutionsUsed += 1;
    resetDirections();
    return true;
  }

  /// Brings a previously substituted player [incoming] back onto the pitch
  /// into slot [outIndex], pushing the outgoing player out of the match for
  /// good (injured or sent off). The same PlayerGame object is reused, so
  /// the player's played minutes and match stats stay correct.
  bool reenterSubstituted(
    int outIndex,
    PlayerGame incoming, {
    double minute = 0,
  }) {
    if (outIndex < 0 || outIndex >= players.length) {
      return false;
    }
    if (!substitutedOut.contains(incoming)) {
      return false;
    }
    if (incoming.isSentOff || incoming.isInjuredInMatch) {
      return false;
    }
    final outgoing = players[outIndex];
    final position = outgoing.pos.copy();
    final home = outgoing.homePos.copy();
    players[outIndex] = incoming
      ..pos = position
      ..homePos = home
      ..lastDirection = Vec2(attackDirection.toDouble(), 0);
    outgoing.exitedAtMinute = minute;
    substitutedOut.remove(incoming);
    removedFromMatch.add(outgoing);
    // A re-entry replaces a lost player one-for-one; grant a bonus slot so
    // it does not eat into the team's regular changes.
    bonusSubstitutions += 1;
    substitutionsUsed += 1;
    substitutionLog.add(
      SubstitutionRecord(
        outIndex: outIndex,
        outgoing: outgoing,
        incoming: incoming,
        benchIndex: -1,
        minute: minute,
        reentry: true,
      ),
    );
    resetDirections();
    return true;
  }

  /// Reverts the most recent substitution: the outgoing player returns to
  /// his slot and the substitute goes back to the bench (or, for a
  /// re-entry, back to the substituted-out list).
  bool undoLastSubstitution() {
    if (substitutionLog.isEmpty) {
      return false;
    }
    final record = substitutionLog.removeLast();
    if (record.outIndex < 0 || record.outIndex >= players.length) {
      substitutionLog.insert(0, record);
      return false;
    }
    players[record.outIndex] = record.outgoing
      ..exitedAtMinute = null;
    if (record.reentry) {
      substitutedOut.add(record.incoming);
      removedFromMatch.remove(record.outgoing);
      bonusSubstitutions = math.max(0, bonusSubstitutions - 1);
    } else {
      final benchIndex = record.benchIndex.clamp(0, bench.length).toInt();
      bench.insert(benchIndex, record.incoming);
      substitutedOut.remove(record.outgoing);
    }
    substitutionsUsed = math.max(0, substitutionsUsed - 1);
    resetDirections();
    return true;
  }
}
