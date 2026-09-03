import 'dart:math' as math;

import '../config/game_constants.dart';
import '../enums/kick_type.dart';
import '../math/vec2.dart';
import '../models/ball_game.dart';
import '../models/shooting.dart';

class BallPhysics {
  const BallPhysics();

  void update(BallGame ball, double dt) {
    if (ball.owner != null) {
      ball.attachTo(ball.owner!);
      return;
    }

    final frameScale = dt * 60;
    if (ball.lastKickType == KickType.shoot &&
        ball.curve.abs() > 0.001 &&
        ball.vel.length > 0.2) {
      final direction = ball.vel.normalized();
      final perpendicular = Vec2(-direction.y, direction.x);
      ball.vel = ball.vel + perpendicular * (ball.curve * dt);
      ball.curve *= math.pow(0.982, frameScale).toDouble();
      ball.spin *= math.pow(0.988, frameScale).toDouble();
    }
    ball.pos = ball.pos + ball.vel * frameScale;

    final previousHeight = ball.heightMeters;
    ball.heightMeters += ball.verticalVelocity * dt;
    // A dipping free kick dips less when the shot is powerful: strong
    // efforts carry over the wall, weak ones still dip into it
    // (مطلب: التسديدة القوية تعبر الحائط).
    final dipStrength = 5.30 -
        2.70 * (ball.shotPower01 / 1.7).clamp(0.0, 1.0);
    final gravity = ball.dippingFreeKick
        ? GameConstants.gravityMeters * dipStrength
        : GameConstants.gravityMeters;
    ball.verticalVelocity -= gravity * dt;

    if (ball.heightMeters <= 0) {
      if (previousHeight > 0.05 && ball.verticalVelocity < -0.25) {
        ball.heightMeters = 0;
        ball.verticalVelocity = -ball.verticalVelocity * 0.46;
        ball.vel = ball.vel * 0.82;
        ball.curve *= 0.55;
        ball.spin *= 0.68;
        ball.hasBouncedSinceKick = true;
        if (ball.verticalVelocity < 0.8) {
          ball.verticalVelocity = 0;
        }
      } else {
        ball.heightMeters = 0;
        ball.verticalVelocity = 0;
      }
    }

    final highPass = ball.lastPassWasHigh;
    // Shots and lofted passes keep much more of their speed in the air so
    // they travel realistically fast instead of dying out mid-flight.
    final drag = ball.heightMeters > 0.08 ? (highPass ? 0.986 : 0.977) : 0.985;
    ball.vel = ball.vel * math.pow(drag, frameScale).toDouble();
    final airSpeedLimit = ball.lastKickType == KickType.shoot
        ? switch (ball.shotType) {
            ShotType.power => 13.4,
            ShotType.finesse => 10.6,
            ShotType.chip => 8.8,
            ShotType.volley => 10.4,
            ShotType.header => 8.4,
            _ => 11.4,
          }
        : highPass
        ? 11.2
        : 6.6;
    if (ball.heightMeters > 0.08 && ball.vel.length > airSpeedLimit) {
      ball.vel = ball.vel.normalized() * airSpeedLimit;
    }
    // A lofted ball keeps advancing toward its target while it is still
    // in the air (it never parks in one spot and drops straight down).
    if (highPass &&
        !ball.hasBouncedSinceKick &&
        ball.heightMeters > 0.25 &&
        ball.highPassCruiseSpeed > 0 &&
        ball.vel.length < ball.highPassCruiseSpeed) {
      ball.vel = ball.vel.normalized(
        ball.lastTouch?.lastDirection ?? Vec2(1, 0),
      ) * ball.highPassCruiseSpeed;
    }
    if (ball.vel.length < 0.07) {
      ball.vel = ball.vel * 0;
    }
  }
}
