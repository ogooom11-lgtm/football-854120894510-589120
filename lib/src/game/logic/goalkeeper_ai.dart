import 'dart:math' as math;

import '../config/game_constants.dart';
import '../enums/ai_difficulty.dart';
import '../enums/kick_type.dart';
import '../enums/team_id.dart';
import '../math/vec2.dart';
import '../models/goalkeeper.dart';
import '../models/player_game.dart';
import '../models/shooting.dart';
import '../models/team_game.dart';
import 'goalkeeper_prediction.dart';
import 'match_engine.dart';

class GoalkeeperAi {
  GoalkeeperAi(this.random, {this.difficulty = AiDifficulty.medium})
    : _predictor = GoalkeeperPredictor(random);

  final math.Random random;
  final AiDifficulty difficulty;
  final GoalkeeperPredictor _predictor;

  void update({
    required PlayerGame keeper,
    required TeamGame team,
    required TeamGame opponent,
    required MatchEngine engine,
    required double dt,
  }) {
    final ball = engine.ball;
    final stats = keeper.profile.goalkeeperStats;
    keeper.goalkeeperReactionTimer = math.max(
      0,
      keeper.goalkeeperReactionTimer - dt,
    );
    keeper.goalkeeperDecisionLockTimer = math.max(
      0,
      keeper.goalkeeperDecisionLockTimer - dt,
    );

    if (ball.owner == keeper) {
      _setState(keeper, GoalkeeperState.distribution, GoalkeeperAction.stay);
      keeper.goalkeeperVelocity = keeper.goalkeeperVelocity * 0.72;
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
      if (!humanControlled || keeper.catchTimer >= humanDecisionSeconds) {
        _distribute(keeper, team, engine, stats);
      }
      return;
    }
    keeper.catchTimer = 0;

    final activeDiveMotion =
        keeper.keeperGroundTimer > 0 &&
        keeper.jumpAnimationTimer > 0.10 &&
        (keeper.goalkeeperState == GoalkeeperState.diving ||
            keeper.goalkeeperState == GoalkeeperState.jumping);
    if (keeper.keeperGroundTimer > 0 && !activeDiveMotion) {
      keeper.goalkeeperVelocity = Vec2.zero();
      _setState(keeper, GoalkeeperState.recovering, GoalkeeperAction.recover);
      _updateDebug(keeper, ballSpeed: ball.vel.length, ballHeight: ball.heightMeters);
      return;
    }

    final context = _buildContext(keeper, team, opponent, engine);
    final shotThreat = _isShotThreat(context, team);
    if (shotThreat) {
      _handleShotThreat(keeper, team, engine, stats, context, dt);
      return;
    }

    keeper.goalkeeperPrediction = null;
    final crossThreat = context.isCross &&
        engine.isInPenaltyBox(ball.pos, team.id) &&
        ball.owner == null;
    if (crossThreat) {
      _handleCross(keeper, team, engine, stats, context, dt);
      return;
    }

    final looseRush = _shouldRushLooseBall(
      keeper,
      team,
      opponent,
      engine,
      stats,
      context,
    );
    if (looseRush) {
      _setState(
        keeper,
        context.isOneVsOne
            ? GoalkeeperState.oneVsOne
            : GoalkeeperState.comingOut,
        GoalkeeperAction.rushOut,
      );
      _moveWithAcceleration(
        keeper,
        ball.pos,
        stats,
        dt,
        sprint: true,
      );
      _resolveContact(keeper, team, engine, stats, context);
      return;
    }

    final target = _positioningTarget(keeper, team, context, stats);
    final returning = keeper.pos.distanceTo(target) > 28 &&
        _pitchDistanceMeters(ball.pos, context.goalCenter) > 20;
    _setState(
      keeper,
      returning ? GoalkeeperState.returningToGoal : GoalkeeperState.positioning,
      returning ? GoalkeeperAction.returnToGoal : GoalkeeperAction.position,
    );
    _moveWithAcceleration(keeper, target, stats, dt);
    _updateDebug(
      keeper,
      ballSpeed: ball.vel.length,
      ballHeight: ball.heightMeters,
      ballCurve: ball.curve,
    );
  }

  GoalkeeperContext _buildContext(
    PlayerGame keeper,
    TeamGame team,
    TeamGame opponent,
    MatchEngine engine,
  ) {
    final ball = engine.ball;
    final goalX = team.side == TeamSide.left
        ? GameConstants.leftBound + 18
        : GameConstants.rightBound - 18;
    final centerY = GameConstants.virtualHeight / 2;
    final goalTop = centerY - GameConstants.goalPixelHeight / 2;
    final goalBottom = centerY + GameConstants.goalPixelHeight / 2;
    final opponentOwner = ball.owner != null && ball.owner!.teamId != team.id;
    final owner = opponentOwner ? ball.owner : null;
    final attackers = opponent.players
        .where(
          (player) =>
              !player.isSentOff && engine.isInPenaltyBox(player.pos, team.id),
        )
        .length;
    final nearestDefenderDistance = team.players
        .where((player) => player != keeper && !player.isSentOff)
        .map((player) => _pitchDistanceMeters(player.pos, ball.pos))
        .fold<double>(
          99.0,
          (best, value) => math.min(best, value).toDouble(),
        );
    final isCross = ball.lastKickType == KickType.highPass &&
        ball.heightMeters > 0.35;
    final ownerDistance = owner == null
        ? double.infinity
        : _pitchDistanceMeters(owner.pos, Vec2(goalX, centerY));
    final oneVsOne = owner != null && ownerDistance < 14 && attackers <= 2;
    final throughBall = ball.owner == null &&
        (ball.lastKickType == KickType.pass ||
            ball.lastKickType == KickType.highPass) &&
        _movingTowardGoal(ball.vel, team);
    return GoalkeeperContext(
      goalkeeperPosition: keeper.pos.copy(),
      goalkeeperHeight: keeper.profile.heightMeters,
      goalCenter: Vec2(goalX, centerY),
      goalTop: goalTop,
      goalBottom: goalBottom,
      goalLineX: goalX,
      ballPosition: ball.pos.copy(),
      ballVelocity: ball.vel.copy(),
      ballHeight: ball.heightMeters,
      ballVerticalVelocity: ball.verticalVelocity,
      ballCurve: ball.curve,
      shotType: ball.shotType,
      shooterPosition: ball.lastTouch?.pos.copy(),
      nearestDefenderDistance: nearestDefenderDistance,
      numberOfAttackers: attackers,
      isBallOwned: ball.owner != null,
      isCross: isCross,
      isOneVsOne: oneVsOne,
      isThroughBall: throughBall,
      isCorner: engine.restartKind == RestartKind.corner,
      isFreeKick:
          ball.dippingFreeKick || engine.restartKind == RestartKind.freeKick,
      visibilityFactor: _visibilityFactor(keeper, engine),
      fatigue: (1 - keeper.stamina).clamp(0.0, 1.0).toDouble(),
    );
  }

  bool _isShotThreat(GoalkeeperContext context, TeamGame team) {
    return context.ballVelocity.length > 1.2 &&
        _movingTowardGoal(context.ballVelocity, team) &&
        (context.ballPosition.x - context.goalLineX).abs() <
            390 * difficulty.visionRange;
  }

  void _handleShotThreat(
    PlayerGame keeper,
    TeamGame team,
    MatchEngine engine,
    GoalkeeperStats stats,
    GoalkeeperContext context,
    double dt,
  ) {
    final ball = engine.ball;
    final newTrajectory =
        keeper.goalkeeperObservedTrajectoryId != ball.trajectoryId;
    final lockedByDive =
        keeper.keeperGroundTimer > 0 && keeper.jumpAnimationTimer > 0.10;
    if (newTrajectory) {
      keeper.goalkeeperObservedTrajectoryId = ball.trajectoryId;
      if (!lockedByDive) {
        final reaction = _reactionTime(keeper, stats, context);
        keeper
          ..goalkeeperReactionTimer = reaction
          ..goalkeeperLastReactionTime = reaction
          ..goalkeeperDecisionLockTimer = 0
          ..goalkeeperPrediction = null;
      }
    }

    if (!lockedByDive &&
        (keeper.goalkeeperDecisionLockTimer <= 0 ||
            keeper.goalkeeperPrediction == null)) {
      keeper.goalkeeperPrediction = _predictor.predict(stats, context);
      keeper.goalkeeperDecisionTarget =
          keeper.goalkeeperPrediction!.predictedImpact.copy();
      keeper.goalkeeperDecisionLockTimer =
          (0.30 - stats.decision * 0.20).clamp(0.10, 0.30).toDouble();
      keeper.goalkeeperAction = _chooseSaveAction(
        keeper,
        stats,
        context,
        keeper.goalkeeperPrediction!,
      );
    }
    final prediction = keeper.goalkeeperPrediction!;
    final ready = prediction.timeToImpact < 0.85;
    if (keeper.goalkeeperReactionTimer > 0) {
      _setState(
        keeper,
        ready ? GoalkeeperState.ready : GoalkeeperState.anticipating,
        ready ? GoalkeeperAction.ready : GoalkeeperAction.track,
      );
      final reflexAbility = stats.reaction * 0.58 +
          stats.anticipation * 0.25 +
          stats.positioning * 0.17;
      final reflexWindow = 0.05 + reflexAbility * 0.12;
      if (prediction.timeToImpact + reflexWindow <
          keeper.goalkeeperReactionTimer) {
        _moveWithAcceleration(
          keeper,
          _positioningTarget(keeper, team, context, stats),
          stats,
          dt,
        );
        _updatePredictionDebug(keeper, prediction, context);
        return;
      }
    }

    final action = keeper.goalkeeperAction;
    final saveY = (keeper.goalkeeperDecisionTarget?.y ?? context.goalCenter.y)
        .clamp(context.goalTop - 12, context.goalBottom + 12)
        .toDouble();
    final target = Vec2(
      context.goalLineX + team.attackDirection * 8,
      saveY,
    );
    if (!prediction.reachable) {
      _setState(keeper, GoalkeeperState.tracking, GoalkeeperAction.track);
      _moveWithAcceleration(keeper, target, stats, dt);
      _updatePredictionDebug(keeper, prediction, context);
      return;
    }

    if (action == GoalkeeperAction.diveLeft ||
        action == GoalkeeperAction.diveRight) {
      _startDive(keeper, stats, action);
      _moveWithAcceleration(keeper, target, stats, dt, diving: true);
    } else if (action == GoalkeeperAction.jump) {
      _startJump(keeper, stats);
      _moveWithAcceleration(keeper, target, stats, dt, diving: true);
    } else {
      _setState(
        keeper,
        action == GoalkeeperAction.backpedal
            ? GoalkeeperState.returningToGoal
            : prediction.timeToImpact < 0.24
            ? GoalkeeperState.anticipating
            : GoalkeeperState.tracking,
        action,
      );
      _moveWithAcceleration(keeper, target, stats, dt);
    }
    _resolveContact(keeper, team, engine, stats, context);
    _updatePredictionDebug(keeper, prediction, context);
  }

  GoalkeeperAction _chooseSaveAction(
    PlayerGame keeper,
    GoalkeeperStats stats,
    GoalkeeperContext context,
    GoalkeeperPrediction prediction,
  ) {
    if (!prediction.reachable) return GoalkeeperAction.track;
    final advancedFromLine =
        (keeper.pos.x - context.goalLineX).abs() > 28;
    if (context.shotType == ShotType.chip &&
        advancedFromLine &&
        prediction.timeToImpact > 0.24) {
      return GoalkeeperAction.backpedal;
    }
    final gap = prediction.predictedImpact.y - keeper.pos.y;
    if (prediction.impactHeight > keeper.profile.heightMeters * 0.72) {
      return GoalkeeperAction.jump;
    }
    if (gap.abs() > 13 + stats.footwork * 7) {
      return gap < 0
          ? GoalkeeperAction.diveLeft
          : GoalkeeperAction.diveRight;
    }
    final catchScore = _catchScore(stats, context, prediction.impactSpeed);
    return catchScore >= 0.58
        ? GoalkeeperAction.catchBall
        : GoalkeeperAction.parry;
  }

  void _handleCross(
    PlayerGame keeper,
    TeamGame team,
    MatchEngine engine,
    GoalkeeperStats stats,
    GoalkeeperContext context,
    double dt,
  ) {
    final distance = _pitchDistanceMeters(keeper.pos, engine.ball.pos);
    final crossScore = stats.highBalls * 0.38 +
        stats.jumping * 0.22 +
        stats.decision * 0.24 +
        stats.reach * 0.16 -
        context.numberOfAttackers * 0.035;
    if (distance < 7.5 && crossScore > 0.58) {
      final high = engine.ball.heightMeters > keeper.profile.heightMeters * 0.70;
      if (high) {
        _startJump(keeper, stats);
      } else {
        _setState(keeper, GoalkeeperState.comingOut, GoalkeeperAction.moveForward);
      }
      _moveWithAcceleration(
        keeper,
        engine.ball.pos,
        stats,
        dt,
        sprint: true,
        diving: high,
      );
      _resolveContact(keeper, team, engine, stats, context);
    } else {
      _setState(keeper, GoalkeeperState.ready, GoalkeeperAction.ready);
      _moveWithAcceleration(
        keeper,
        _positioningTarget(keeper, team, context, stats),
        stats,
        dt,
      );
    }
    _updateDebug(
      keeper,
      ballSpeed: engine.ball.vel.length,
      ballHeight: engine.ball.heightMeters,
      ballCurve: engine.ball.curve,
    );
  }

  bool _shouldRushLooseBall(
    PlayerGame keeper,
    TeamGame team,
    TeamGame opponent,
    MatchEngine engine,
    GoalkeeperStats stats,
    GoalkeeperContext context,
  ) {
    final ball = engine.ball;
    if (context.isOneVsOne) {
      final owner = ball.owner!;
      final controlled = ball.vel.length < 2.2;
      return !controlled ||
          _pitchDistanceMeters(keeper.pos, owner.pos) < 8 + stats.oneVsOne * 3;
    }
    final inBox = engine.isInPenaltyBox(ball.pos, team.id);
    final sweeperRange = context.isThroughBall &&
        _pitchDistanceMeters(ball.pos, context.goalCenter) <
            16 + stats.anticipation * 8;
    if (ball.owner != null || (!inBox && !sweeperRange)) {
      return false;
    }
    final keeperDistance = keeper.pos.distanceTo(ball.pos);
    if (keeperDistance >
        (80 + stats.decision * 50) * difficulty.aggressionFactor) {
      return false;
    }
    final keeperPixelsPerSecond = math.max(80, keeper.speed * 60);
    final keeperArrival = keeperDistance / keeperPixelsPerSecond;
    final attackers = opponent.players.where((player) => !player.isSentOff);
    final attackerArrival = attackers.isEmpty
        ? double.infinity
        : attackers
              .map(
                (player) =>
                    player.pos.distanceTo(ball.pos) /
                    math.max(90, player.speed * 60),
              )
              .reduce(math.min);
    final decisionMargin = (stats.decision + stats.anticipation) * 0.09;
    return keeperArrival + decisionMargin < attackerArrival;
  }

  Vec2 _positioningTarget(
    PlayerGame keeper,
    TeamGame team,
    GoalkeeperContext context,
    GoalkeeperStats stats,
  ) {
    final distanceToGoal = _pitchDistanceMeters(
      context.ballPosition,
      context.goalCenter,
    );
    final advancePixels = (context.isOneVsOne
            ? 48 + stats.oneVsOne * 18
            : distanceToGoal <= 8
            ? 34
            : distanceToGoal <= 12
            ? 25
            : distanceToGoal <= 16
            ? 17
            : 8)
        .toDouble();
    final trackedY = context.goalCenter.y +
        (context.ballPosition.y - context.goalCenter.y) *
            (0.30 + stats.positioning * 0.17);
    if (keeper.goalkeeperDecisionLockTimer <= 0 ||
        keeper.goalkeeperDecisionTarget == null) {
      final maxErrorMeters = switch (stats.level) {
        PlayerLevel.weak => 0.60,
        PlayerLevel.normal => 0.40,
        PlayerLevel.good => 0.25,
        PlayerLevel.excellent => 0.12,
        PlayerLevel.worldClass => 0.06,
      };
      final errorPixels = (random.nextDouble() * 2 - 1) *
          maxErrorMeters *
          GameConstants.pitchHeight /
          68;
      keeper.goalkeeperDecisionTarget = Vec2(
        context.goalLineX + team.attackDirection * advancePixels,
        (trackedY + errorPixels)
            .clamp(context.goalTop + 10, context.goalBottom - 10)
            .toDouble(),
      );
      keeper.goalkeeperDecisionLockTimer =
          (0.30 - stats.decision * 0.18).clamp(0.11, 0.30).toDouble();
    }
    return keeper.goalkeeperDecisionTarget!.copy();
  }

  void _moveWithAcceleration(
    PlayerGame keeper,
    Vec2 target,
    GoalkeeperStats stats,
    double dt, {
    bool sprint = false,
    bool diving = false,
  }) {
    if (keeper.keeperGroundTimer > 0 && !diving) {
      keeper.goalkeeperVelocity = Vec2.zero();
      return;
    }
    final offset = target - keeper.pos;
    if (offset.length < 0.8) {
      keeper.goalkeeperVelocity = keeper.goalkeeperVelocity * 0.72;
      return;
    }
    final speedScale = sprint ? 1.18 : diving ? 1.06 : 0.86;
    final maxVelocity = keeper.speed *
        (0.72 + stats.speed * 0.38) *
        speedScale;
    final desired = offset.normalized() * maxVelocity;
    final delta = desired - keeper.goalkeeperVelocity;
    final maxChange = (0.045 + stats.acceleration * 0.13) * dt * 60;
    final change = delta.length > maxChange
        ? delta.normalized() * maxChange
        : delta;
    keeper.goalkeeperVelocity = keeper.goalkeeperVelocity + change;
    final step = keeper.goalkeeperVelocity * dt * 60;
    keeper.pos = keeper.pos + step;
    keeper.stamina = math.max(
      0.12,
      keeper.stamina -
          step.length *
              0.000014 *
              0.18 *
              (1.20 - keeper.profile.staminaSkill * 0.52),
    );
    if (!keeper.goalkeeperVelocity.isZero) {
      keeper.lastDirection = keeper.goalkeeperVelocity.normalized();
    }
    keeper.keepInsideField();
  }

  void _startDive(
    PlayerGame keeper,
    GoalkeeperStats stats,
    GoalkeeperAction action,
  ) {
    if (keeper.keeperDiveCooldown > 0 || keeper.keeperGroundTimer > 0) return;
    final recovery = (1.78 -
            stats.diving * 0.30 -
            stats.reaction * 0.08 +
            (1 - keeper.stamina) * 0.16)
        .clamp(1.36, 1.78)
        .toDouble();
    keeper
      ..keeperState = 'atlayis'
      ..goalkeeperState = GoalkeeperState.diving
      ..goalkeeperAction = action
      ..goalkeeperReactionTimer = 0
      ..jumpBoostMeters = 0.10 + stats.jumping * 0.13
      ..jumpAnimationTimer = 0.62
      ..keeperGroundTimer = recovery
      ..keeperDiveCooldown = recovery + 0.25;
  }

  void _startJump(PlayerGame keeper, GoalkeeperStats stats) {
    if (keeper.keeperDiveCooldown > 0 || keeper.keeperGroundTimer > 0) return;
    final recovery = (1.72 -
            stats.jumping * 0.24 +
            (1 - keeper.stamina) * 0.15)
        .clamp(1.38, 1.76)
        .toDouble();
    keeper
      ..keeperState = 'atlayis'
      ..goalkeeperState = GoalkeeperState.jumping
      ..goalkeeperAction = GoalkeeperAction.jump
      ..goalkeeperReactionTimer = 0
      ..jumpBoostMeters = 0.16 + stats.jumping * 0.15
      ..jumpAnimationTimer = 0.62
      ..keeperGroundTimer = recovery
      ..keeperDiveCooldown = recovery + 0.22;
  }

  void _resolveContact(
    PlayerGame keeper,
    TeamGame team,
    MatchEngine engine,
    GoalkeeperStats stats,
    GoalkeeperContext context,
  ) {
    final ball = engine.ball;
    final cannotRehandle =
        keeper.keeperRehandleCooldown > 0 && ball.lastTouch == keeper;
    if (cannotRehandle || keeper.keeperParryCooldown > 0) return;
    final physicalReach =
        keeper.radius + GameConstants.ballRadius + 3 + stats.reach * 8;
    if (keeper.pos.distanceTo(ball.pos) > physicalReach ||
        ball.heightMeters > keeper.bodyReachMeters) {
      return;
    }
    if (!engine.isInPenaltyBox(keeper.pos, team.id)) {
      ball.attachTo(keeper);
      engine.releaseFromPlayer(
        keeper,
        Vec2(team.attackDirection.toDouble(), (random.nextDouble() - 0.5) * 0.6),
        1.05 + stats.distribution * 0.32,
        type: KickType.highPass,
        loft: 4.8 + stats.distribution * 1.8,
      );
      _setState(keeper, GoalkeeperState.returningToGoal, GoalkeeperAction.returnToGoal);
      return;
    }

    final isShot = ball.lastKickType == KickType.shoot;
    final isHighBall = context.isCross || ball.heightMeters > 1.25;
    final catchScore = _catchScore(stats, context, ball.vel.length);
    final speedThreshold = isShot
        ? ball.shotType == ShotType.power
            ? 0.76
            : 0.60
        : isHighBall
        ? 0.62 + context.numberOfAttackers * 0.025
        : 0.48;
    final humanError = (random.nextDouble() - 0.5) *
        (1 - stats.composure) *
        0.14;
    if (catchScore + humanError >= speedThreshold) {
      if (isShot) {
        keeper.profile.saves += 1;
        keeper.matchSaves += 1;
        engine.shotDiagnostics.saved += 1;
      }
      ball.attachTo(keeper);
      keeper
        ..catchTimer = 0
        ..goalkeeperVelocity = Vec2.zero();
      _setState(keeper, GoalkeeperState.catching, GoalkeeperAction.catchBall);
      return;
    }

    if (isHighBall &&
        stats.highBalls * 0.45 + stats.jumping * 0.30 + stats.decision * 0.25 >
            0.58) {
      engine.punchFromGoalkeeper(keeper, control: stats.parrying);
      _setState(keeper, GoalkeeperState.punching, GoalkeeperAction.punch);
      return;
    }
    engine.parryFromGoalkeeper(keeper, control: stats.parrying);
    _setState(keeper, GoalkeeperState.parrying, GoalkeeperAction.parry);
  }

  double _catchScore(
    GoalkeeperStats stats,
    GoalkeeperContext context,
    double speed,
  ) {
    final base = stats.handling * 0.25 +
        stats.catching * 0.28 +
        stats.positioning * 0.15 +
        stats.reaction * 0.10 +
        stats.composure * 0.12 +
        (context.isCross ? stats.highBalls : stats.decision) * 0.10;
    final speedPenalty = math.max(0.0, speed - 3.2) * 0.055;
    final heightPenalty = math.max(0.0, context.ballHeight - 1.0) * 0.07;
    return (base - speedPenalty - heightPenalty - context.fatigue * 0.12)
        .clamp(0.08, 0.96)
        .toDouble();
  }

  double _reactionTime(
    PlayerGame keeper,
    GoalkeeperStats stats,
    GoalkeeperContext context,
  ) {
    final range = switch (stats.level) {
      PlayerLevel.weak => (0.25, 0.40),
      PlayerLevel.normal => (0.21, 0.32),
      PlayerLevel.good => (0.17, 0.26),
      PlayerLevel.excellent => (0.13, 0.21),
      PlayerLevel.worldClass => (0.09, 0.17),
    };
    final rawHumanDelay =
        range.$1 + random.nextDouble() * (range.$2 - range.$1);
    final humanDelay = rawHumanDelay /
        (0.86 + difficulty.reactionFactor * 0.14);
    final visibilityDelay = (1 - context.visibilityFactor) * 0.18;
    final fatigueDelay = (1 - keeper.stamina) * 0.08;
    final readyBonus = keeperReadyBonus(stats, context);
    return (humanDelay + visibilityDelay + fatigueDelay - readyBonus)
        .clamp(0.07, 0.48)
        .toDouble();
  }

  double keeperReadyBonus(
    GoalkeeperStats stats,
    GoalkeeperContext context,
  ) {
    final closeThreat = _pitchDistanceMeters(
      context.ballPosition,
      context.goalCenter,
    ) < 16;
    return closeThreat ? 0.025 + stats.anticipation * 0.045 : 0;
  }

  double _visibilityFactor(PlayerGame keeper, MatchEngine engine) {
    final ball = engine.ball;
    final segment = keeper.pos - ball.pos;
    final lengthSquared = segment.lengthSquared;
    if (lengthSquared < 1) return 1;
    var blockers = 0;
    for (final player in engine.allPlayers) {
      if (player == keeper || player == ball.lastTouch) continue;
      final fromBall = player.pos - ball.pos;
      final t = (fromBall.dot(segment) / lengthSquared).clamp(0.0, 1.0);
      if (t <= 0.08 || t >= 0.94) continue;
      final closest = ball.pos + segment * t.toDouble();
      if (player.pos.distanceTo(closest) < player.radius + 7) blockers += 1;
    }
    return (1 - blockers * 0.14).clamp(0.50, 1.0).toDouble();
  }

  bool _movingTowardGoal(Vec2 velocity, TeamGame team) {
    return team.side == TeamSide.left ? velocity.x < -0.05 : velocity.x > 0.05;
  }

  void _setState(
    PlayerGame keeper,
    GoalkeeperState state,
    GoalkeeperAction action,
  ) {
    keeper
      ..goalkeeperState = state
      ..goalkeeperAction = action
      ..goalkeeperDebug.state = state
      ..goalkeeperDebug.action = action;
    keeper.keeperState = switch (state) {
      GoalkeeperState.diving || GoalkeeperState.jumping => 'atlayis',
      GoalkeeperState.recovering => 'yerde',
      GoalkeeperState.catching || GoalkeeperState.distribution => 'top elde',
      GoalkeeperState.parrying ||
      GoalkeeperState.deflecting ||
      GoalkeeperState.punching => 'kurtaris',
      GoalkeeperState.ready || GoalkeeperState.anticipating => 'hazir',
      _ => 'yuruyor',
    };
  }

  void _updatePredictionDebug(
    PlayerGame keeper,
    GoalkeeperPrediction prediction,
    GoalkeeperContext context,
  ) {
    keeper.goalkeeperDebug
      ..predictedImpact = prediction.predictedImpact.copy()
      ..timeToImpact = prediction.timeToImpact
      ..reactionTime = keeper.goalkeeperLastReactionTime
      ..predictionConfidence = prediction.confidence
      ..reachRadius = 14 +
          keeper.profile.goalkeeperStats.diving * 38 +
          keeper.profile.goalkeeperStats.reach * 24
      ..ballSpeed = context.ballVelocity.length
      ..ballHeight = context.ballHeight
      ..ballCurve = context.ballCurve;
  }

  void _updateDebug(
    PlayerGame keeper, {
    required double ballSpeed,
    required double ballHeight,
    double ballCurve = 0,
  }) {
    keeper.goalkeeperDebug
      ..predictedImpact = null
      ..timeToImpact = 0
      ..reactionTime = keeper.goalkeeperReactionTimer
      ..predictionConfidence = 0
      ..reachRadius = 14 +
          keeper.profile.goalkeeperStats.diving * 38 +
          keeper.profile.goalkeeperStats.reach * 24
      ..ballSpeed = ballSpeed
      ..ballHeight = ballHeight
      ..ballCurve = ballCurve;
  }

  void _distribute(
    PlayerGame keeper,
    TeamGame team,
    MatchEngine engine,
    GoalkeeperStats stats,
  ) {
    final goalKick = engine.isGoalKickPendingFor(team);
    final distributionDelay = goalKick
        ? 0.20 + (1 - stats.distribution) * 0.20
        : 0.66 + (1 - stats.decision) * 0.35;
    if (keeper.catchTimer < distributionDelay) {
      return;
    }
    final useLong = goalKick ||
        random.nextDouble() < 0.24 + stats.distribution * 0.28;
    engine.distributeFromGoalkeeper(
      keeper,
      high: useLong,
      power: useLong ? (goalKick ? 1.72 : 1.18) : 0.84,
    );
    keeper.catchTimer = 0;
  }

  double _pitchDistanceMeters(Vec2 first, Vec2 second) {
    final dx = (first.x - second.x) * 105 / GameConstants.pitchWidth;
    final dy = (first.y - second.y) * 68 / GameConstants.pitchHeight;
    return math.sqrt(dx * dx + dy * dy);
  }
}
