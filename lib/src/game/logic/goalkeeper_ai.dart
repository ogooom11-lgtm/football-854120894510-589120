import 'dart:math' as math;

import '../config/game_constants.dart';
import '../enums/kick_type.dart';
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
      keeper.keeperState = 'top elde';
      // A goalkeeper who catches during a dive must finish the landing and
      // recovery before standing up or distributing the ball.
      if (keeper.keeperGroundTimer > 0) {
        keeper.catchTimer = 0;
        return;
      }
      keeper.catchTimer += dt;
      final waitingForHumanGoalKick =
          engine.isGoalKickPendingFor(team) &&
          engine.isRestartWaitingForHuman(team);
      final humanControlled = !engine.isTeamAiControlled(team.id);
      final humanDecisionSeconds = waitingForHumanGoalKick ? 3.2 : 2.8;
      // Human teams get a realistic window to choose a ground or high
      // distribution. The automatic fallback still prevents time-wasting.
      if (!humanControlled || keeper.catchTimer >= humanDecisionSeconds) {
        _distribute(keeper, team, engine);
      }
      return;
    }
    keeper.catchTimer = 0;
    if (keeper.keeperGroundTimer <= 0) {
      keeper.keeperState = 'yuruyor';
    } else if (keeper.jumpAnimationTimer <= 0.10) {
      keeper.keeperState = 'yerde';
    }

    final goalX = team.side == TeamSide.left
        ? GameConstants.leftBound + 18
        : GameConstants.rightBound - 18;
    final goalTop =
        GameConstants.virtualHeight / 2 - GameConstants.goalPixelHeight / 2;
    final goalBottom =
        GameConstants.virtualHeight / 2 + GameConstants.goalPixelHeight / 2;
    final ballInBox = engine.isInPenaltyBox(ball.pos, team.id);
    final cannotRehandleOwnRelease =
        keeper.keeperRehandleCooldown > 0 && ball.lastTouch == keeper;

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
          ..jumpBoostMeters = 0.12 + keeperSkill * 0.08
          ..jumpAnimationTimer = 0.62
          // The first part is the dive; the remaining time is a genuine
          // grounded recovery. Skill helps, but no keeper rises instantly.
          ..keeperGroundTimer = 1.72 - keeperSkill * 0.18
          ..keeperDiveCooldown = 1.95 - keeperSkill * 0.15;
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
          !cannotRehandleOwnRelease &&
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

    // Catch only at genuine body/arm contact. Skill changes anticipation and
    // success probability, not the physical length of the keeper's arms.
    final handlingReach =
        keeper.radius + GameConstants.ballRadius + 4 + keeperSkill * 8;
    if (!cannotRehandleOwnRelease &&
        keeper.keeperState != 'yerde' &&
        keeper.keeperParryCooldown <= 0 &&
        keeper.pos.distanceTo(ball.pos) < handlingReach &&
        ball.heightMeters <= keeper.bodyReachMeters) {
      final isShot = ball.lastKickType == KickType.shoot;
      final speedPenalty = math.max(0.0, ball.vel.length - 6.5) * 0.025;
      final catchChance = (isShot
              ? 0.10 + keeperSkill * 0.66 - speedPenalty
              : (ball.vel.length < 6.8 ? 0.40 : 0.24) +
                    keeperSkill * 0.48)
          .clamp(0.08, 0.92) *
          difficulty.anticipationFactor;
      if (random.nextDouble() < catchChance.clamp(0.06, 0.94)) {
        if (isShot) {
          keeper.profile.saves += 1;
          keeper.matchSaves += 1;
          engine.shotDiagnostics.saved += 1;
        }
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

    final useLong =
        goalKick ||
        random.nextDouble() < 0.28 + keeper.profile.passSkill * 0.22;
    engine.distributeFromGoalkeeper(
      keeper,
      high: useLong,
      power: useLong ? (goalKick ? 1.72 : 1.18) : 0.84,
    );
    keeper.catchTimer = 0;
  }
}
