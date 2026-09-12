import '../math/vec2.dart';

enum PlayerLevel { weak, normal, good, excellent, worldClass }

enum PreferredFoot { left, right }

enum ShotType { ground, low, normal, power, finesse, chip, volley, header }

class PlayerShootingStats {
  const PlayerShootingStats({
    required this.shooting,
    required this.finishing,
    required this.shotPower,
    required this.longShots,
    required this.curve,
    required this.composure,
    required this.balance,
    required this.preferredFoot,
    required this.weakFoot,
  });

  factory PlayerShootingStats.forLevel(
    PlayerLevel level, {
    PreferredFoot preferredFoot = PreferredFoot.right,
    int weakFoot = 3,
  }) {
    final values = switch (level) {
      PlayerLevel.weak => const [0.55, 0.50, 0.65, 0.40, 0.35, 0.35, 0.45],
      PlayerLevel.normal => const [0.68, 0.65, 0.72, 0.55, 0.50, 0.55, 0.60],
      PlayerLevel.good => const [0.78, 0.76, 0.80, 0.68, 0.68, 0.72, 0.72],
      PlayerLevel.excellent => const [0.87, 0.86, 0.88, 0.80, 0.80, 0.85, 0.84],
      PlayerLevel.worldClass => const [0.94, 0.94, 0.94, 0.91, 0.91, 0.94, 0.93],
    };
    return PlayerShootingStats(
      shooting: values[0],
      finishing: values[1],
      shotPower: values[2],
      longShots: values[3],
      curve: values[4],
      composure: values[5],
      balance: values[6],
      preferredFoot: preferredFoot,
      weakFoot: weakFoot.clamp(1, 5).toInt(),
    );
  }

  final double shooting;
  final double finishing;
  final double shotPower;
  final double longShots;
  final double curve;
  final double composure;
  final double balance;
  final PreferredFoot preferredFoot;
  final int weakFoot;

  double get composite =>
      shooting * 0.28 +
      finishing * 0.20 +
      shotPower * 0.12 +
      longShots * 0.12 +
      curve * 0.08 +
      composure * 0.12 +
      balance * 0.08;

  PlayerLevel get level {
    if (composite >= 0.90) return PlayerLevel.worldClass;
    if (composite >= 0.82) return PlayerLevel.excellent;
    if (composite >= 0.72) return PlayerLevel.good;
    if (composite >= 0.60) return PlayerLevel.normal;
    return PlayerLevel.weak;
  }
}

class ShotContext {
  const ShotContext({
    required this.stats,
    required this.playerPosition,
    required this.intendedTarget,
    required this.facingAngleDegrees,
    required this.distanceMeters,
    required this.nearestDefenderMeters,
    required this.movementRatio,
    required this.sprinting,
    required this.turning,
    required this.incomingBallSpeed,
    required this.ballHeight,
    required this.bodyLean,
    required this.supportFootQuality,
    required this.usingPreferredFoot,
    required this.firstTime,
    required this.fatigue,
    required this.powerInput,
    required this.shotType,
    required this.goalWidthPixels,
    required this.freeKick,
  });

  final PlayerShootingStats stats;
  final Vec2 playerPosition;
  final Vec2 intendedTarget;
  final double facingAngleDegrees;
  final double distanceMeters;
  final double nearestDefenderMeters;
  final double movementRatio;
  final bool sprinting;
  final bool turning;
  final double incomingBallSpeed;
  final double ballHeight;
  final double bodyLean;
  final double supportFootQuality;
  final bool usingPreferredFoot;
  final bool firstTime;
  final double fatigue;
  final double powerInput;
  final ShotType shotType;
  final double goalWidthPixels;
  final bool freeKick;
}

class ShotResult {
  const ShotResult({
    required this.target,
    required this.finalTarget,
    required this.launchTarget,
    required this.power,
    required this.speed,
    required this.targetHeight,
    required this.verticalVelocity,
    required this.lateralError,
    required this.heightError,
    required this.curve,
    required this.accuracy,
    required this.shotType,
  });

  final Vec2 target;
  final Vec2 finalTarget;
  final Vec2 launchTarget;
  final double power;
  final double speed;
  final double targetHeight;
  final double verticalVelocity;
  final double lateralError;
  final double heightError;
  final double curve;
  final double accuracy;
  final ShotType shotType;
}

class ShotDiagnostics {
  int shots = 0;
  int groundShots = 0;
  int lowShots = 0;
  int powerShots = 0;
  int finesseShots = 0;
  int chips = 0;
  int volleys = 0;
  int headers = 0;
  int posts = 0;
  int crossbars = 0;
  int goals = 0;
  int saved = 0;
  int blocked = 0;
  double accuracyTotal = 0;

  void record(ShotResult result) {
    shots += 1;
    accuracyTotal += result.accuracy;
    switch (result.shotType) {
      case ShotType.ground:
        groundShots += 1;
        break;
      case ShotType.low:
        lowShots += 1;
        break;
      case ShotType.power:
        powerShots += 1;
        break;
      case ShotType.finesse:
        finesseShots += 1;
        break;
      case ShotType.chip:
        chips += 1;
        break;
      case ShotType.volley:
        volleys += 1;
        break;
      case ShotType.header:
        headers += 1;
        break;
      case ShotType.normal:
        break;
    }
  }

  double get averageAccuracy => shots == 0 ? 0 : accuracyTotal / shots;
}
