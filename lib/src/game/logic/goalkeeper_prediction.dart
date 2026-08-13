import 'dart:math' as math;

import '../config/game_constants.dart';
import '../models/goalkeeper.dart';
import '../models/shooting.dart';

class GoalkeeperPredictor {
  GoalkeeperPredictor(this.random);

  final math.Random random;

  GoalkeeperPrediction predict(
    GoalkeeperStats stats,
    GoalkeeperContext context,
  ) {
    final horizontalPerSecond = context.ballVelocity.x * 60;
    final distanceX = context.goalLineX - context.ballPosition.x;
    final movingTowardGoal =
        horizontalPerSecond.abs() > 0.01 && distanceX / horizontalPerSecond > 0;
    if (!movingTowardGoal) {
      return GoalkeeperPrediction(
        predictedImpact: context.ballPosition.copy(),
        timeToImpact: double.infinity,
        confidence: 0,
        requiredReach: double.infinity,
        impactHeight: context.ballHeight,
        impactSpeed: context.ballVelocity.length,
        reachable: false,
      );
    }

    final time = (distanceX / horizontalPerSecond).clamp(0.0, 4.0).toDouble();
    final curveReadAbility =
        (stats.anticipation * 0.48 + stats.decision * 0.30 + stats.reaction * 0.22)
            .clamp(0.35, 0.98)
            .toDouble();
    final curveDisplacement =
        context.ballCurve * curveReadAbility * time * time * 30;
    var predictedY = context.ballPosition.y +
        context.ballVelocity.y * 60 * time +
        curveDisplacement;

    final maximumErrorMeters = switch (stats.level) {
      PlayerLevel.weak => 0.80,
      PlayerLevel.normal => 0.50,
      PlayerLevel.good => 0.30,
      PlayerLevel.excellent => 0.15,
      PlayerLevel.worldClass => 0.08,
    };
    final errorPixels = _gaussian().clamp(-2.0, 2.0) *
        maximumErrorMeters *
        (GameConstants.pitchHeight / 68) *
        0.50;
    predictedY += errorPixels;

    final gravity = context.isFreeKick
        ? GameConstants.gravityMeters * 5.30
        : GameConstants.gravityMeters;
    final impactHeight = math.max(
      0.0,
      context.ballHeight +
          context.ballVerticalVelocity * time -
          0.5 * gravity * time * time,
    );
    final confidenceBase = switch (stats.level) {
      PlayerLevel.weak => 0.55,
      PlayerLevel.normal => 0.65,
      PlayerLevel.good => 0.75,
      PlayerLevel.excellent => 0.85,
      PlayerLevel.worldClass => 0.93,
    };
    final curvePenalty = context.ballCurve.abs() * (1 - curveReadAbility) * 0.10;
    final confidence = (confidenceBase * context.visibilityFactor -
            curvePenalty -
            context.fatigue * 0.08)
        .clamp(0.20, 0.97)
        .toDouble();
    final requiredReach = (predictedY - context.goalkeeperPosition.y).abs();
    final lateralReach = 14 + stats.diving * 38 + stats.reach * 24;
    final verticalReach =
        context.goalkeeperHeight + 0.38 + stats.jumping * 0.30;
    final reachable = requiredReach <= lateralReach &&
        impactHeight <= verticalReach &&
        predictedY >= context.goalTop - 20 &&
        predictedY <= context.goalBottom + 20;

    return GoalkeeperPrediction(
      predictedImpact: context.ballPosition.copy()
        ..x = context.goalLineX
        ..y = predictedY,
      timeToImpact: time,
      confidence: confidence,
      requiredReach: requiredReach,
      impactHeight: impactHeight,
      impactSpeed: context.ballVelocity.length,
      reachable: reachable,
    );
  }

  double _gaussian() {
    final u1 = (1 - random.nextDouble()).clamp(0.000001, 1.0);
    final u2 = 1 - random.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
}
