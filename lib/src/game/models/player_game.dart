import '../config/game_constants.dart';
import '../enums/player_role.dart';
import '../enums/team_id.dart';
import '../math/vec2.dart';
import 'player_profile.dart';

class PlayerGame {
  PlayerGame({
    required this.profile,
    required this.teamId,
    required this.role,
    required this.number,
    required Vec2 position,
  })  : id = '${teamId.name}-$number-${profile.id}',
        pos = position,
        homePos = position.copy();

  final String id;
  final PlayerProfile profile;
  final TeamId teamId;
  PlayerRole role;
  int number;
  Vec2 pos;
  Vec2 homePos;
  /// Temporary reachable target used while a restart is being organised.
  /// This lets players walk into shape rather than teleporting on set pieces.
  Vec2? restartTarget;
  Vec2 lastDirection = Vec2(1, 0);
  bool controlled = false;
  double aiCooldown = 0;
  double manualOverride = 0;
  double catchTimer = 0;
  double jumpBoostMeters = 0;
  double stamina = 1.0;
  double minutesThisMatch = 0;
  String keeperState = 'hazir';
  double keeperGroundTimer = 0;
  double keeperDiveCooldown = 0;
  double keeperParryCooldown = 0;

  // Per-match stats
  int matchGoals = 0;
  int matchAssists = 0;
  int matchPasses = 0;
  int matchSuccessfulPasses = 0;
  int matchDribbles = 0;
  int matchSuccessfulDribbles = 0;
  int matchTackles = 0;
  int matchShots = 0;
  int matchShotsOnTarget = 0;
  int matchMissedChances = 0;
  int matchClearances = 0;
  int matchSaves = 0;
  int matchFoulsCommitted = 0;
  int matchFoulsReceived = 0;

  /// Set to true when player gets injured during this match.
  bool isInjuredInMatch = false;

  bool get isGoalkeeper => role.isGoalkeeper;

  double get bodyReachMeters =>
      profile.heightMeters * (keeperGroundTimer > 0 ? 0.36 : 1.0) +
      jumpBoostMeters +
      (isGoalkeeper ? 0.28 : 0.02);

  double get radius => isGoalkeeper
      ? GameConstants.goalkeeperRadius
      : GameConstants.playerRadius;

  double get speed {
    // Fatigue gradually affects speed; a tired player should slow down, not
    // become unusable after a short spell of pressing.
    final staminaFactor = 0.58 + stamina * 0.42;
    final speedFactor = 0.74 + profile.speedSkill * 0.52;
    if (role == PlayerRole.goalkeeper) {
      return 2.48 *
          speedFactor *
          staminaFactor *
          (keeperGroundTimer > 0 ? 0.33 : 1.0);
    }
    if (role.isWide) {
      return 3.38 * speedFactor * staminaFactor;
    }
    if (role == PlayerRole.striker) {
      return 3.28 * speedFactor * staminaFactor;
    }
    if (role == PlayerRole.midfieldLeft || role == PlayerRole.midfieldRight) {
      return 3.08 * speedFactor * staminaFactor;
    }
    return 2.92 * speedFactor * staminaFactor;
  }

  double get errorFactor {
    final fatigue = (1.0 - stamina).clamp(0.0, 0.75).toDouble();
    final skillGap = (1.0 - profile.effectiveOverall / 100).clamp(0.0, 0.9);
    return (fatigue * 0.72 + skillGap * 0.28).clamp(0.0, 0.85).toDouble();
  }

  void keepInsideField() {
    pos.clampTo(
      GameConstants.leftBound + radius,
      GameConstants.topBound + radius,
      GameConstants.rightBound - radius,
      GameConstants.bottomBound - radius,
    );
  }
}
