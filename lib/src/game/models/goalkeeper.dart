import '../math/vec2.dart';
import 'shooting.dart';

enum GoalkeeperState {
  idle,
  positioning,
  tracking,
  ready,
  anticipating,
  diving,
  jumping,
  catching,
  parrying,
  deflecting,
  punching,
  comingOut,
  oneVsOne,
  recovering,
  returningToGoal,
  distribution,
}

enum GoalkeeperAction {
  stay,
  position,
  track,
  ready,
  moveLeft,
  moveRight,
  moveForward,
  backpedal,
  diveLeft,
  diveRight,
  jump,
  catchBall,
  parry,
  punch,
  rushOut,
  recover,
  returnToGoal,
}

class GoalkeeperStats {
  const GoalkeeperStats({
    required this.reaction,
    required this.positioning,
    required this.diving,
    required this.handling,
    required this.catching,
    required this.jumping,
    required this.decision,
    required this.oneVsOne,
    required this.highBalls,
    required this.composure,
    required this.speed,
    required this.acceleration,
    required this.reach,
    required this.footwork,
    required this.anticipation,
    required this.parrying,
    required this.distribution,
  });

  factory GoalkeeperStats.forLevel(PlayerLevel level) {
    final core = switch (level) {
      PlayerLevel.weak => const [0.45, 0.45, 0.45, 0.40, 0.40, 0.45, 0.40, 0.45, 0.40, 0.40],
      PlayerLevel.normal => const [0.60, 0.60, 0.60, 0.58, 0.55, 0.60, 0.55, 0.60, 0.55, 0.58],
      PlayerLevel.good => const [0.75, 0.75, 0.75, 0.72, 0.70, 0.75, 0.72, 0.75, 0.70, 0.72],
      PlayerLevel.excellent => const [0.87, 0.87, 0.88, 0.86, 0.84, 0.86, 0.86, 0.88, 0.85, 0.86],
      PlayerLevel.worldClass => const [0.95, 0.96, 0.96, 0.94, 0.94, 0.95, 0.96, 0.96, 0.94, 0.95],
    };
    final quality = core[0];
    return GoalkeeperStats(
      reaction: core[0],
      positioning: core[1],
      diving: core[2],
      handling: core[3],
      catching: core[4],
      jumping: core[5],
      decision: core[6],
      oneVsOne: core[7],
      highBalls: core[8],
      composure: core[9],
      speed: (quality * 0.90).clamp(0.35, 0.94).toDouble(),
      acceleration: (quality * 0.94).clamp(0.38, 0.96).toDouble(),
      reach: (0.45 + quality * 0.52).clamp(0.45, 0.97).toDouble(),
      footwork: (quality * 0.92).clamp(0.36, 0.95).toDouble(),
      anticipation: (quality * 0.97).clamp(0.38, 0.97).toDouble(),
      parrying: core[3],
      distribution: (quality * 0.90).clamp(0.35, 0.95).toDouble(),
    );
  }

  final double reaction;
  final double positioning;
  final double diving;
  final double handling;
  final double catching;
  final double jumping;
  final double decision;
  final double oneVsOne;
  final double highBalls;
  final double composure;
  final double speed;
  final double acceleration;
  final double reach;
  final double footwork;
  final double anticipation;
  final double parrying;
  final double distribution;

  double get composite =>
      reaction * 0.16 +
      positioning * 0.14 +
      diving * 0.14 +
      handling * 0.09 +
      catching * 0.08 +
      jumping * 0.07 +
      decision * 0.09 +
      oneVsOne * 0.07 +
      highBalls * 0.06 +
      composure * 0.04 +
      reach * 0.03 +
      anticipation * 0.03;

  PlayerLevel get level {
    if (composite >= 0.90) return PlayerLevel.worldClass;
    if (composite >= 0.82) return PlayerLevel.excellent;
    if (composite >= 0.70) return PlayerLevel.good;
    if (composite >= 0.55) return PlayerLevel.normal;
    return PlayerLevel.weak;
  }
}

class GoalkeeperContext {
  const GoalkeeperContext({
    required this.goalkeeperPosition,
    required this.goalkeeperHeight,
    required this.goalCenter,
    required this.goalTop,
    required this.goalBottom,
    required this.goalLineX,
    required this.ballPosition,
    required this.ballVelocity,
    required this.ballHeight,
    required this.ballVerticalVelocity,
    required this.ballCurve,
    required this.shotType,
    required this.shooterPosition,
    required this.nearestDefenderDistance,
    required this.numberOfAttackers,
    required this.isBallOwned,
    required this.isCross,
    required this.isOneVsOne,
    required this.isThroughBall,
    required this.isCorner,
    required this.isFreeKick,
    required this.visibilityFactor,
    required this.fatigue,
  });

  final Vec2 goalkeeperPosition;
  final double goalkeeperHeight;
  final Vec2 goalCenter;
  final double goalTop;
  final double goalBottom;
  final double goalLineX;
  final Vec2 ballPosition;
  final Vec2 ballVelocity;
  final double ballHeight;
  final double ballVerticalVelocity;
  final double ballCurve;
  final ShotType? shotType;
  final Vec2? shooterPosition;
  final double nearestDefenderDistance;
  final int numberOfAttackers;
  final bool isBallOwned;
  final bool isCross;
  final bool isOneVsOne;
  final bool isThroughBall;
  final bool isCorner;
  final bool isFreeKick;
  final double visibilityFactor;
  final double fatigue;
}

class GoalkeeperPrediction {
  const GoalkeeperPrediction({
    required this.predictedImpact,
    required this.timeToImpact,
    required this.confidence,
    required this.requiredReach,
    required this.impactHeight,
    required this.impactSpeed,
    required this.reachable,
  });

  final Vec2 predictedImpact;
  final double timeToImpact;
  final double confidence;
  final double requiredReach;
  final double impactHeight;
  final double impactSpeed;
  final bool reachable;
}

class GoalkeeperDebugData {
  GoalkeeperState state = GoalkeeperState.idle;
  GoalkeeperAction action = GoalkeeperAction.stay;
  Vec2? predictedImpact;
  double timeToImpact = 0;
  double reactionTime = 0;
  double predictionConfidence = 0;
  double reachRadius = 0;
  double ballSpeed = 0;
  double ballHeight = 0;
  double ballCurve = 0;
}
