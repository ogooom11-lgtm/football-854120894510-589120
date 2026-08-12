import 'dart:math' as math;

import '../config/game_constants.dart';
import '../enums/kick_type.dart';
import '../models/ball_game.dart';

class BallPhysics {
  const BallPhysics();

  void update(BallGame ball, double dt) {
    if (ball.owner != null) {
      ball.attachTo(ball.owner!);
      return;
    }

    final frameScale = dt * 60;
    ball.pos = ball.pos + ball.vel * frameScale;

    final previousHeight = ball.heightMeters;
    ball.heightMeters += ball.verticalVelocity * dt;
    ball.verticalVelocity -= GameConstants.gravityMeters * dt;

    if (ball.heightMeters <= 0) {
      if (previousHeight > 0.05 && ball.verticalVelocity < -0.25) {
        ball.heightMeters = 0;
        ball.verticalVelocity = -ball.verticalVelocity * 0.46;
        ball.vel = ball.vel * 0.82;
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
        ? 9.6
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
