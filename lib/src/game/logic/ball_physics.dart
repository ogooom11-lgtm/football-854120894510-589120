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
    final gravity = ball.dippingFreeKick
        ? GameConstants.gravityMeters * 5.30
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
    final drag = ball.heightMeters > 0.08 ? (highPass ? 0.978 : 0.966) : 0.985;
    ball.vel = ball.vel * math.pow(drag, frameScale).toDouble();
    final airSpeedLimit = ball.lastKickType == KickType.shoot
        ? switch (ball.shotType) {
            ShotType.power => 11.8,
            ShotType.finesse => 9.2,
            ShotType.chip => 7.4,
            ShotType.volley => 8.8,
            ShotType.header => 7.2,
            _ => 10.2,
          }
        : highPass
        ? 9.4
        : 6.6;
    if (ball.heightMeters > 0.08 && ball.vel.length > airSpeedLimit) {
      ball.vel = ball.vel.normalized() * airSpeedLimit;
    }
    if (ball.vel.length < 0.07) {
      ball.vel = ball.vel * 0;
    }
  }
}
