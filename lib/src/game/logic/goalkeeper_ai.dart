import 'dart:math' as math;

import '../config/game_constants.dart';
import '../enums/kick_type.dart';
import '../enums/player_role.dart';
import '../enums/ai_difficulty.dart';
import '../enums/team_id.dart';
import '../math/vec2.dart';
import '../models/player_game.dart';
import '../models/team_game.dart';
import 'match_engine.dart';

class GoalkeeperAi {
  GoalkeeperAi(this.random, {this.difficulty = AiDifficulty.medium});

  final math.Random random;
  final AiDifficulty difficulty;

  void update({
    required PlayerGame keeper,
    required TeamGame team,
    required TeamGame opponent,
    required MatchEngine engine,
    required double dt,
  }) {
    final ball = engine.ball;
    final keeperSkill = keeper.profile.keeperSkill;
    if (ball.owner == keeper) {
      keeper.catchTimer += dt;
      keeper.keeperState = 'top elde';
      _distribute(keeper, team, opponent, engine);
      return;
    }
    keeper.catchTimer = 0;
    keeper.keeperState = keeper.keeperGroundTimer > 0 ? 'yerde' : 'yuruyor';

    final goalX = team.side == TeamSide.left
        ? GameConstants.leftBound + 18
        : GameConstants.rightBound - 18;
    final goalTop =
        GameConstants.virtualHeight / 2 - GameConstants.goalPixelHeight / 2;
    final goalBottom =
        GameConstants.virtualHeight / 2 + GameConstants.goalPixelHeight / 2;
    final ballInBox = engine.isInPenaltyBox(ball.pos, team.id);

    final yFromBall =
        GameConstants.virtualHeight / 2 +
        (ball.pos.y - GameConstants.virtualHeight / 2) * 0.40;
    var basePos = Vec2(
      goalX,
      clampDoubleValue(yFromBall, goalTop + 14, goalBottom - 14),
    );

    final shotTowardsGoal =
        ball.vel.length > 2.2 &&
        ((team.side == TeamSide.left && ball.vel.x < 0) ||
            (team.side == TeamSide.right && ball.vel.x > 0));
    if (shotTowardsGoal &&
        keeper.pos.distanceTo(ball.pos) <
            (245 + keeperSkill * 105) * difficulty.visionRange) {
      final projectedY = ball.vel.x.abs() > 0.1
          ? ball.pos.y + (goalX - ball.pos.x) * (ball.vel.y / ball.vel.x)
          : ball.pos.y;
      final saveY = clampDoubleValue(projectedY, goalTop + 10, goalBottom - 10);
      basePos = Vec2(goalX + team.attackDirection * 8, saveY);
      if (keeper.keeperDiveCooldown <= 0 && keeper.keeperGroundTimer <= 0) {
        keeper
          ..keeperState = 'atlayis'
          ..keeperGroundTimer = 1.08 - keeperSkill * 0.22
          ..keeperDiveCooldown = 1.42 - keeperSkill * 0.18;
      }
      engine.moveTowards(
        keeper,
        basePos,
        keeper.keeperGroundTimer > 0
            ? 0.78 + keeperSkill * 0.18
            : 0.66 + keeperSkill * 0.24,
        dt,
      );
    } else {
      final opponentOwner = ball.owner != null && ball.owner!.teamId != team.id;
      final attackerMovingAtGoal =
          opponentOwner &&
          (goalX - ball.owner!.pos.x) * ball.owner!.lastDirection.x > 0.35 &&
          ball.owner!.pos.distanceTo(
                Vec2(goalX, GameConstants.virtualHeight / 2),
              ) <
              150;
      final looseBallToClaim =
          ball.owner == null &&
          ballInBox &&
          keeper.pos.distanceTo(ball.pos) <
              (82 + keeperSkill * 42) * difficulty.aggressionFactor;
      final closeOneOnOne =
          attackerMovingAtGoal &&
          keeper.pos.distanceTo(ball.owner!.pos) < 62 + keeperSkill * 28;
      if (looseBallToClaim || closeOneOnOne) {
        final claimTarget = Vec2(
          ball.pos.x
              .clamp(
                team.side == TeamSide.left
                    ? GameConstants.leftBound + 8
                    : GameConstants.rightBound - 135,
                team.side == TeamSide.left
                    ? GameConstants.leftBound + 135
                    : GameConstants.rightBound - 8,
              )
              .toDouble(),
          ball.pos.y
              .clamp(
                GameConstants.virtualHeight / 2 - 130,
                GameConstants.virtualHeight / 2 + 130,
              )
              .toDouble(),
        );
        engine.moveTowards(keeper, claimTarget, 0.70 + keeperSkill * 0.22, dt);
      } else {
        // If the attacker is not facing goal, hold the line and prepare to dive.
        engine.moveTowards(keeper, basePos, 0.48 + keeperSkill * 0.18, dt);
      }
    }

    if (keeper.pos.distanceTo(ball.pos) <
            keeper.radius + GameConstants.ballRadius + 9 &&
        ball.heightMeters <= keeper.bodyReachMeters + 0.15) {
      final isShot = ball.lastKickType == KickType.shoot;
      final catchChance = isShot
          ? (0.18 + keeperSkill * 0.24) * difficulty.anticipationFactor
          : ((ball.vel.length < 6.8 ? 0.48 : 0.30) + keeperSkill * 0.28) *
                difficulty.anticipationFactor;
      if (random.nextDouble() < catchChance) {
        ball.attachTo(keeper);
        keeper.catchTimer = 0;
        keeper.keeperState = 'top elde';
      } else {
        if (isShot) {
          engine.parryFromGoalkeeper(keeper);
          return;
        }
        final clearY = keeper.pos.y > GameConstants.virtualHeight / 2
            ? -1.0
            : 1.0;
        engine.releaseFromPlayer(
          keeper,
          Vec2(team.attackDirection * 0.58, clearY * 0.85),
          0.95,
          type: KickType.pass,
          loft: ball.heightMeters > 1.0 ? 1.0 : 0,
        );
      }
    }
  }

  void _distribute(
    PlayerGame keeper,
    TeamGame team,
    TeamGame opponent,
    MatchEngine engine,
  ) {
    final goalKick = engine.isGoalKickPendingFor(team);
    if (keeper.catchTimer <
        (goalKick
            ? 0.18 + (1 - keeper.profile.passSkill) * 0.18
            : 0.62 + random.nextDouble() * 0.42)) {
      final safeX = team.side == TeamSide.left
          ? GameConstants.leftBound + 45
          : GameConstants.rightBound - 45;
      engine.moveTowards(
        keeper,
        Vec2(safeX, GameConstants.virtualHeight / 2),
        0.35,
        1 / 60,
      );
      return;
    }

    final shortTargets = team.players.where(
      (player) =>
          player.role == PlayerRole.leftWingBack ||
          player.role == PlayerRole.rightWingBack ||
          player.role == PlayerRole.midfieldLeft ||
          player.role == PlayerRole.midfieldRight ||
          player.role == PlayerRole.sweeper,
    );
    final longTargets = team.players.where(
      (player) => player.role == PlayerRole.striker || player.role.isWide,
    );
    final useLong =
        goalKick ||
        random.nextDouble() < 0.28 + keeper.profile.passSkill * 0.22;
    final target =
        engine.chooseBestPass(
          keeper,
          useLong ? longTargets : shortTargets,
          preferForward: true,
        ) ??
        team.closestTo(keeper.homePos, includeGoalkeeper: false);
    engine.releaseFromPlayer(
      keeper,
      target.pos - engine.ball.pos,
      useLong ? (goalKick ? 1.72 : 1.18) : 0.84,
      type: useLong ? KickType.highPass : KickType.pass,
      target: target,
      loft: useLong ? (goalKick ? 15.0 : 6.1) : 0,
    );
    keeper.catchTimer = 0;
  }
}
