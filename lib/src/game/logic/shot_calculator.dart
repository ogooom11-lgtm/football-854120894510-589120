import 'dart:math' as math;

import '../config/game_constants.dart';
import '../models/shooting.dart';

class ShotCalculator {
  ShotCalculator(this.random);

  final math.Random random;

  ShotResult calculate(ShotContext context) {
    final stats = context.stats;
    final baseAccuracy = _baseAccuracy(context);
    final distanceFactor = _distanceFactor(context);
    final angleFactor = _angleFactor(context.facingAngleDegrees);
    final pressureFactor = _pressureFactor(context);
    final movementFactor = _movementFactor(context);
    final balanceFactor = (0.82 + stats.balance * 0.18)
        .clamp(0.70, 1.0)
        .toDouble();
    final ballQualityFactor = _ballQualityFactor(context);
    final bodyFactor = _bodyPositionFactor(context.bodyLean);
    final supportFootFactor =
        (0.85 + context.supportFootQuality * 0.15).clamp(0.72, 1.0);
    final footFactor = context.usingPreferredFoot
        ? 1.0
        : (0.72 + context.stats.weakFoot.clamp(1, 5) * 0.055)
              .clamp(0.76, 0.995)
              .toDouble();
    final fatigueFactor = (1 - context.fatigue * 0.20)
        .clamp(0.76, 1.0)
        .toDouble();
    final firstTimeFactor = _firstTimeFactor(context);
    final typeAccuracyFactor = _shotTypeAccuracyFactor(context);
    final powerAccuracyFactor = _powerAccuracyFactor(context);

    final accuracy = (baseAccuracy *
            distanceFactor *
            angleFactor *
            pressureFactor *
            movementFactor *
            balanceFactor *
            ballQualityFactor *
            bodyFactor *
            supportFootFactor *
            footFactor *
            fatigueFactor *
            firstTimeFactor *
            typeAccuracyFactor *
            powerAccuracyFactor)
        .clamp(0.05, 0.98)
        .toDouble();

    // Shots from inside the penalty area are extremely dangerous: the
    // closer the shot, the more accurate and the faster it arrives.
    final closeRangeBoost = context.distanceMeters <= 16 ? 1.0 : 0.0;

    final baseSigma = switch (stats.level) {
      PlayerLevel.weak => 0.22,
      PlayerLevel.normal => 0.16,
      PlayerLevel.good => 0.11,
      PlayerLevel.excellent => 0.07,
      PlayerLevel.worldClass => 0.04,
    };
    final conditions = (distanceFactor *
            angleFactor *
            pressureFactor *
            movementFactor *
            balanceFactor *
            ballQualityFactor)
        .clamp(0.18, 1.0)
        .toDouble();
    final sigmaPixels = (baseSigma *
            context.goalWidthPixels *
            (0.82 + (1 - accuracy) * 0.75) /
            math.sqrt(conditions) *
            (closeRangeBoost > 0 ? 0.66 : 1.0))
        .clamp(2.4, context.goalWidthPixels * 0.72)
        .toDouble();
    final lateralError = _gaussian() * sigmaPixels;

    final baseHeight = _baseTargetHeight(context);
    // Height error is kept smaller so shots do not constantly clip the
    // crossbar band; missing high is possible but less frequent.
    final heightSigma = (baseSigma *
            (1.05 + context.powerInput * 0.72) /
            math.sqrt(conditions) *
            (1.08 - stats.balance * 0.26))
        .clamp(0.02, 1.15)
        .toDouble();
    final heightError = _gaussian() * heightSigma;
    final leanLift = context.bodyLean.clamp(-1.0, 1.0) * 0.52;
    final targetHeight = (baseHeight + heightError + leanLift)
        .clamp(0.0, context.shotType == ShotType.chip ? 5.2 : 4.9)
        .toDouble();

    final releasePower = _releasePower(context) *
        (closeRangeBoost > 0 ? 1.09 : 1.0);
    final gravity = context.freeKick
        ? GameConstants.gravityMeters * 5.30
        : GameConstants.gravityMeters;
    final verticalVelocity = targetHeight <= 0.04
        ? 0.0
        : math.sqrt(2 * gravity * targetHeight);
    final curve = _curve(context);
    final finalTarget = context.intendedTarget.copy()
      ..y += lateralError;
    final horizontalPixels =
        (context.intendedTarget.x - context.playerPosition.x).abs();
    final horizontalPixelsPerSecond = math.max(120.0, 8.2 * releasePower * 60);
    final flightSeconds = horizontalPixels / horizontalPixelsPerSecond;
    final curveCompensation = curve * flightSeconds * flightSeconds * 30;
    final launchTarget = finalTarget.copy()..y -= curveCompensation;

    return ShotResult(
      target: context.intendedTarget.copy(),
      finalTarget: finalTarget,
      launchTarget: launchTarget,
      power: releasePower,
      speed: 8.2 * releasePower,
      targetHeight: targetHeight,
      verticalVelocity: verticalVelocity,
      lateralError: lateralError,
      heightError: heightError,
      curve: curve,
      accuracy: accuracy,
      shotType: context.shotType,
    );
  }

  double _baseAccuracy(ShotContext context) {
    final s = context.stats;
    if (context.distanceMeters <= 16) {
      return s.shooting * 0.34 + s.finishing * 0.50 + s.composure * 0.16;
    }
    if (context.distanceMeters >= 20) {
      return s.shooting * 0.38 + s.longShots * 0.47 + s.composure * 0.15;
    }
    final blend = (context.distanceMeters - 16) / 4;
    final close = s.shooting * 0.34 + s.finishing * 0.50 + s.composure * 0.16;
    final long = s.shooting * 0.38 + s.longShots * 0.47 + s.composure * 0.15;
    return close + (long - close) * blend;
  }

  double _distanceFactor(ShotContext context) {
    final distance = context.distanceMeters;
    final base = distance <= 5.5
        ? 1.0
        : distance <= 11
        ? 0.98
        : distance <= 16
        ? 0.92
        : distance <= 20
        ? 0.82
        : distance <= 25
        ? 0.70
        : distance <= 30
        ? 0.58
        : 0.42;
    final longShotBonus = (context.stats.longShots - 0.5) * 0.25;
    return (base + longShotBonus).clamp(0.28, 1.04).toDouble();
  }

  double _angleFactor(double degrees) {
    final angle = degrees.abs();
    if (angle <= 10) return 1.0;
    if (angle <= 25) return 0.96;
    if (angle <= 45) return 0.88;
    if (angle <= 65) return 0.72;
    if (angle <= 90) return 0.55;
    return 0.40;
  }

  double _pressureFactor(ShotContext context) {
    final distance = context.nearestDefenderMeters;
    final raw = distance >= 5
        ? 1.0
        : distance >= 3
        ? 0.95
        : distance >= 1.5
        ? 0.85
        : distance >= 0.7
        ? 0.70
        : 0.50;
    final absorbed = context.stats.composure * 0.58;
    return (1 - (1 - raw) * (1 - absorbed)).clamp(0.50, 1.0).toDouble();
  }

  double _movementFactor(ShotContext context) {
    var factor = context.movementRatio < 0.08
        ? 1.10
        : context.movementRatio < 0.35
        ? 1.05
        : context.sprinting
        ? 0.90
        : 1.0;
    if (context.turning) factor *= 0.85;
    final control = context.stats.shooting * 0.45 +
        context.stats.composure * 0.30 +
        context.stats.balance * 0.25;
    return (1 - (1 - factor) * (1.08 - control * 0.42))
        .clamp(0.72, 1.10)
        .toDouble();
  }

  double _ballQualityFactor(ShotContext context) {
    final incoming = context.incomingBallSpeed * 2;
    var speedFactor = incoming < 5
        ? 1.0
        : incoming < 10
        ? 0.95
        : incoming < 15
        ? 0.88
        : incoming < 20
        ? 0.80
        : 0.70;
    final heightFactor = context.ballHeight <= 0.10
        ? 1.0
        : context.ballHeight <= 0.30
        ? 0.96
        : context.ballHeight <= 0.70
        ? 0.86
        : 0.72;
    final technique = context.stats.finishing * 0.55 +
        context.stats.composure * 0.45;
    speedFactor = 1 - (1 - speedFactor) * (1.10 - technique * 0.38);
    return (speedFactor * heightFactor).clamp(0.55, 1.0).toDouble();
  }

  double _bodyPositionFactor(double lean) {
    final amount = lean.abs().clamp(0.0, 1.0);
    return (1 - amount * (lean > 0 ? 0.18 : 0.10)).clamp(0.76, 1.0).toDouble();
  }

  double _firstTimeFactor(ShotContext context) {
    if (!context.firstTime) return 1.0;
    final base = switch (context.stats.level) {
      PlayerLevel.weak => 0.75,
      PlayerLevel.normal => 0.82,
      PlayerLevel.good => 0.88,
      PlayerLevel.excellent => 0.93,
      PlayerLevel.worldClass => 0.96,
    };
    final technique = context.stats.finishing * 0.55 +
        context.stats.composure * 0.45;
    return (base + (1 - base) * technique * 0.28).clamp(base, 0.985).toDouble();
  }

  double _shotTypeAccuracyFactor(ShotContext context) {
    final s = context.stats;
    return switch (context.shotType) {
      ShotType.ground => 1.03,
      ShotType.low => 1.01,
      ShotType.normal => 1.0,
      ShotType.power => (0.82 + s.shooting * 0.12 + s.shotPower * 0.06),
      ShotType.finesse => (0.96 + s.curve * 0.07),
      ShotType.chip => (0.78 + s.finishing * 0.12 + s.composure * 0.08),
      ShotType.volley => (0.68 + s.finishing * 0.16 + s.balance * 0.10),
      ShotType.header => (0.66 + s.finishing * 0.12 + s.balance * 0.12),
    };
  }

  double _powerAccuracyFactor(ShotContext context) {
    final ideal = context.distanceMeters > 25 ? 0.82 : 0.67;
    final difference = (context.powerInput - ideal).abs();
    final weakness = 1 -
        (context.stats.shooting * 0.55 + context.stats.shotPower * 0.45);
    return (1 - difference * (0.10 + weakness * 0.34)).clamp(0.72, 1.0).toDouble();
  }

  double _baseTargetHeight(ShotContext context) {
    final power = context.powerInput;
    return switch (context.shotType) {
      ShotType.ground => 0.02 + power * 0.10,
      ShotType.low => 0.14 + power * 0.34,
      ShotType.normal => 0.45 + power * 0.72,
      ShotType.power => 0.55 + power * 0.92,
      ShotType.finesse => 0.38 + power * 0.58,
      ShotType.chip => 1.65 + power * 2.15,
      ShotType.volley => (0.40 +
              context.ballHeight * 0.60 +
              power * 0.72)
          .clamp(0.35, 2.1)
          .toDouble(),
      ShotType.header =>
        (0.32 + context.ballHeight * 0.42 + power * 0.42)
            .clamp(0.25, 1.65)
            .toDouble(),
    };
  }

  double _releasePower(ShotContext context) {
    final s = context.stats;
    var power = (0.64 + context.powerInput * 0.44) *
        (0.72 + s.shotPower * 0.34) *
        (0.91 + s.balance * 0.09) *
        (1 - context.fatigue * 0.14);
    power *= switch (context.shotType) {
      ShotType.ground => 0.95,
      ShotType.low => 1.0,
      ShotType.normal => 1.0,
      ShotType.power => 1.16,
      ShotType.finesse => 0.88,
      ShotType.chip => 0.67,
      ShotType.volley => 0.74,
      ShotType.header => 0.58,
    };
    return power.clamp(0.48, 1.58).toDouble();
  }

  double _curve(ShotContext context) {
    final typeFactor = switch (context.shotType) {
      ShotType.finesse => 1.0,
      ShotType.power => 0.22,
      ShotType.chip => 0.30,
      ShotType.volley => 0.18,
      ShotType.header => 0.04,
      _ => 0.42,
    };
    if (typeFactor <= 0 || context.stats.curve < 0.18) return 0;
    final attackDirection =
        context.intendedTarget.x >= context.playerPosition.x ? 1.0 : -1.0;
    final footSign = context.stats.preferredFoot == PreferredFoot.right
        ? attackDirection
        : -attackDirection;
    final weakFootFactor = context.usingPreferredFoot
        ? 1.0
        : 0.45 + context.stats.weakFoot * 0.09;
    return footSign * context.stats.curve * typeFactor * weakFootFactor * 2.1;
  }

  double _gaussian() {
    final u1 = (1 - random.nextDouble()).clamp(0.000001, 1.0);
    final u2 = 1 - random.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
}
