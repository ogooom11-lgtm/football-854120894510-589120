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

class PlayerAi {
  PlayerAi(this.random, {this.difficulty = AiDifficulty.medium});

  final math.Random random;
  final AiDifficulty difficulty;

  void update({
    required PlayerGame player,
    required TeamGame team,
    required TeamGame opponent,
    required MatchEngine engine,
    required double dt,
  }) {
    if (player.manualOverride > 0) {
      return;
    }
    if (engine.ball.owner == player) {
      _withBall(player, team, opponent, engine, dt);
      return;
    }
    _withoutBall(player, team, opponent, engine, dt);
  }

  void _withoutBall(
    PlayerGame player,
    TeamGame team,
    TeamGame opponent,
    MatchEngine engine,
    double dt,
  ) {
    final ball = engine.ball;
    final restartTarget = player.restartTarget;
    if (restartTarget != null) {
      engine.moveTowards(player, restartTarget, 1.0, dt);
      return;
    }
    // During the kickoff everyone holds his position in his own half —
    // nobody advances past the halfway line until the ball is played.
    if (engine.restartKind == RestartKind.kickoff) {
      return;
    }
    // During a corner the defenders man-mark the nearest attacker so the
    // box stays tight — every player picks up a player.
    if (engine.isCornerAttackActiveFor(opponent) && player.role.isDefender) {
      final mark = _cornerMarkTarget(player, opponent, engine);
      if (mark != null) {
        engine.moveTowards(player, mark, 1.0, dt);
        _maybeJumpForHighBall(player, engine);
        return;
      }
    }
    final target = engine.coverageTargetFor(player, team) ??
        _roleTarget(player, team, engine);
    final emergencyDrop = _attackerShouldDrop(player, team, engine);

    var finalTarget = target;
    if (ball.owner != null && ball.owner!.teamId == team.id) {
      // Our keeper caught the ball: defenders and midfielders come close
      // to offer a short, open pass; attackers stay forward.
      if (ball.owner!.isGoalkeeper &&
          engine.isInPenaltyBox(ball.owner!.pos, team.id)) {
        if (player.role.isDefender ||
            player.role == PlayerRole.midfieldLeft ||
            player.role == PlayerRole.midfieldRight) {
          final lane = (player.number % 3) - 1;
          final target = ball.owner!.pos -
              Vec2(team.attackDirection * 30, 0) +
              Vec2(0, lane * 52.0);
          engine.moveTowards(player, target, 1.0, dt);
          return;
        }
      }
      final lineX = _secondLastDefenderLine(opponent, team.attackDirection);
      final beyondLine = team.attackDirection == 1
          ? player.pos.x > lineX - 6
          : player.pos.x < lineX + 6;
      if (player.role.isAttacker && beyondLine) {
        // Attackers hold the offside line: they stay just behind the
        // second-last defender instead of drifting offside.
        finalTarget.x = lineX - team.attackDirection * 8;
      }
      if (player.role == PlayerRole.striker &&
          ball.pos.y < GameConstants.virtualHeight / 2 - 90) {
        finalTarget.y = GameConstants.virtualHeight / 2 - 10;
      } else if (player.role == PlayerRole.striker &&
          ball.pos.y > GameConstants.virtualHeight / 2 + 90) {
        finalTarget.y = GameConstants.virtualHeight / 2 + 10;
      }
      // A winger charging down the wing: the striker and the closest
      // midfielder enter the box so the winger has a passing target.
      final wideOnTheAttack =
          ball.owner!.role.isWide &&
          (team.attackDirection == 1
              ? ball.owner!.pos.x > GameConstants.virtualWidth * 0.62
              : ball.owner!.pos.x < GameConstants.virtualWidth * 0.38);
      if (wideOnTheAttack) {
        final goalMouthY = GameConstants.virtualHeight / 2;
        if (player.role == PlayerRole.striker) {
          // Enter the box but never beyond the offside line.
          final boxX = team.attackDirection == 1
              ? math.min(GameConstants.rightBound - 88, lineX - 8)
              : math.max(GameConstants.leftBound + 88, lineX + 8);
          finalTarget = Vec2(boxX, goalMouthY);
        } else if (player.role == PlayerRole.midfieldLeft ||
            player.role == PlayerRole.midfieldRight) {
          final otherMid = team.players.firstWhere(
            (mate) =>
                mate != player &&
                (mate.role == PlayerRole.midfieldLeft ||
                    mate.role == PlayerRole.midfieldRight),
            orElse: () => player,
          );
          final closer =
              (player.pos.x - otherMid.pos.x) * team.attackDirection >= 0;
          if (closer) {
            finalTarget = Vec2(
              team.attackDirection == 1
                  ? GameConstants.rightBound - 120
                  : GameConstants.leftBound + 120,
              goalMouthY,
            );
          }
        }
      }
    } else if (ball.owner != null && ball.owner!.teamId != team.id) {
      if (engine.shouldWaitForKeeperRelease(team)) {
        // The opponent keeper has the ball: attackers only press him when
        // one of his own defenders is standing close to him. Otherwise
        // everyone holds the release-wait position.
        final keeper = ball.owner!;
        final keeperTeam = engine.teamById(keeper.teamId);
        final defenderNear = keeperTeam.players.any(
          (mate) =>
              !mate.isGoalkeeper &&
              !mate.isSentOff &&
              mate.pos.distanceTo(keeper.pos) < 85,
        );
        final nearestChaser = team.closestTo(
          keeper.pos,
          includeGoalkeeper: false,
        );
        if (defenderNear &&
            nearestChaser == player &&
            player.role.isAttacker) {
          finalTarget = keeper.pos - Vec2(team.attackDirection * 14, 0);
        } else {
          finalTarget = _keeperReleaseWaitTarget(
            player,
            team,
            opponent,
            engine,
          );
        }
      } else {
        if (emergencyDrop) {
          finalTarget = _attackerDefensiveTarget(player, team, engine);
        }
        final carrier = ball.owner!;
        final nearestDefenders = [...team.players.where((p) => !p.isGoalkeeper)]
          ..sort(
            (a, b) => a.pos
                .distanceTo(carrier.pos)
                .compareTo(b.pos.distanceTo(carrier.pos)),
          );
        final canJoinPress =
            emergencyDrop &&
            player.role == PlayerRole.striker &&
            player.pos.distanceTo(carrier.pos) < 155;
        if (nearestDefenders.take(2).contains(player) || canJoinPress) {
          finalTarget = carrier.pos - Vec2(team.attackDirection * 12, 0);
        }
        // Defenders close down a shooter: when the opponent carrying the
        // ball is in shooting range, the nearest defender steps between
        // the shooter and the goal to block the shot.
        if (player.role.isDefender) {
          final goalCenter = engine.goalCenterFor(team);
          final carrierToGoal = goalCenter - carrier.pos;
          final inShootingRange =
              (carrier.pos - goalCenter).length < 240 &&
              (team.attackDirection == 1
                  ? carrier.pos.x > GameConstants.virtualWidth * 0.55
                  : carrier.pos.x < GameConstants.virtualWidth * 0.45);
          if (inShootingRange &&
              (nearestDefenders.first == player ||
                  nearestDefenders.take(2).contains(player))) {
            final blockSpot =
                carrier.pos + carrierToGoal.normalized(Vec2(0, 1)) * 20;
            finalTarget = blockSpot;
          }
        }
      }
    } else if (ball.owner == null) {
      if (engine.isCornerAttackActiveFor(team) && !player.isGoalkeeper) {
        finalTarget = _cornerAttackTarget(player, team, engine);
      }
      final nearest = team.closestTo(ball.pos);
      // Only the closest player chases a loose ball, and only when it is
      // reasonably near — everyone else holds his position.
      if (nearest == player &&
          player.pos.distanceTo(ball.pos) < 120) {
        finalTarget = ball.pos;
      }
    }

    _maybeJumpForHighBall(player, engine);
    // AI players run at exactly the same natural speed as a controlled
    // player (force 1.0 = player.speed), so there is no speed advantage
    // or disadvantage for the team the human does not control.
    final cautionFactor =
        player.yellowCardsThisMatch > 0 &&
            ball.owner != null &&
            ball.owner!.teamId != team.id
        ? 0.92
        : 1.0;
    engine.moveTowards(
      player,
      finalTarget,
      (1.0 * cautionFactor).clamp(0.4, 1.0).toDouble(),
      dt,
    );
  }

  double _secondLastDefenderLine(
    TeamGame defendingTeam,
    int attackingDirection,
  ) {
    final defenders = [...defendingTeam.players]
      ..sort(
        (a, b) => attackingDirection == 1
            ? b.pos.x.compareTo(a.pos.x)
            : a.pos.x.compareTo(b.pos.x),
      );
    return defenders.length > 1 ? defenders[1].pos.x : defenders.first.pos.x;
  }

  /// Man-marking target during a corner: the defender stands between the
  /// attacker he is marking and his own goal.
  Vec2? _cornerMarkTarget(
    PlayerGame defender,
    TeamGame opponent,
    MatchEngine engine,
  ) {
    PlayerGame? best;
    var bestDistance = double.infinity;
    for (final candidate in opponent.players) {
      if (candidate.isGoalkeeper ||
          candidate.isSentOff ||
          (!candidate.role.isAttacker && !candidate.role.isWide)) {
        continue;
      }
      final distance = candidate.pos.distanceTo(defender.pos);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    if (best == null) {
      return null;
    }
    final d = engine.teamById(defender.teamId).attackDirection;
    final target = best.pos - Vec2(d * 14, 0);
    target.clampTo(
      GameConstants.leftBound + 30,
      GameConstants.topBound + 30,
      GameConstants.rightBound - 30,
      GameConstants.bottomBound - 30,
    );
    return target;
  }

  void _withBall(
    PlayerGame player,
    TeamGame team,
    TeamGame opponent,
    MatchEngine engine,
    double dt,
  ) {
    if (engine.ball.owner == player && engine.isRestartWaitingForHuman(team)) {
      player.lastDirection = Vec2(team.attackDirection.toDouble(), 0);
      return;
    }
    if (engine.kickoffPending && engine.ball.owner == player) {
      player.lastDirection = Vec2(team.attackDirection.toDouble(), 0);
      return;
    }
    // Keep a throw-in in hand until an actual pass command is given.
    if (engine.restartKind == RestartKind.throwIn && engine.ball.owner == player) {
      player.lastDirection = Vec2(team.attackDirection.toDouble(), 0);
      return;
    }
    if (engine.isCornerWaitingForManualInputFor(team)) {
      player.lastDirection = Vec2(team.attackDirection.toDouble(), 0);
      return;
    }
    if (player.aiCooldown > 0) {
      final d = team.attackDirection;
      final wideEnd =
          player.role.isWide &&
          (d == 1
              ? player.pos.x > GameConstants.rightBound - 125
              : player.pos.x < GameConstants.leftBound + 125);
      final carryTarget = wideEnd
          ? Vec2(
              player.pos.x - d * 16,
              GameConstants.virtualHeight / 2 +
                  (player.role == PlayerRole.leftWing ||
                          player.role == PlayerRole.leftWingBack
                      ? -70
                      : 70),
            )
          : player.pos + Vec2(d * 55, 0);
      engine.moveTowards(player, carryTarget, 1.0, dt);
      return;
    }

    final nearestOpponent = opponent.players.reduce(
      (a, b) =>
          a.pos.distanceTo(player.pos) <= b.pos.distanceTo(player.pos) ? a : b,
    );
    final pressure = nearestOpponent.pos.distanceTo(player.pos);
    final goalCenter = engine.goalCenterFor(team);
    final distanceToGoal = player.pos.distanceTo(goalCenter);
    final finalThird = team.attackDirection == 1
        ? player.pos.x > GameConstants.virtualWidth * 0.70
        : player.pos.x < GameConstants.virtualWidth * 0.30;
    final ownThird = team.attackDirection == 1
        ? player.pos.x < GameConstants.virtualWidth * 0.33
        : player.pos.x > GameConstants.virtualWidth * 0.67;
    final nearEndLine = team.attackDirection == 1
        ? player.pos.x > GameConstants.rightBound - 115
        : player.pos.x < GameConstants.leftBound + 115;
    final goodAngle =
        (player.pos.y - GameConstants.virtualHeight / 2).abs() < 150;

    final boxTargets = team.players.where(
      (p) =>
          p != player &&
          (p.role == PlayerRole.striker ||
              p.role == PlayerRole.midfieldLeft ||
              p.role == PlayerRole.midfieldRight ||
              p.role == PlayerRole.rightWing ||
              p.role == PlayerRole.leftWing),
    );
    final forwardTargets = team.players.where(
      (p) => p != player && !p.isGoalkeeper,
    );
    final backTargets = team.players.where(
      (p) =>
          p != player &&
          !p.isGoalkeeper &&
          (p.pos.x - player.pos.x) * team.attackDirection < -10,
    );
    final crossTarget = engine.chooseBestPass(
      player,
      boxTargets,
      preferForward: false,
    );
    final forwardTarget = engine.chooseBestPass(
      player,
      forwardTargets,
      preferForward: true,
    );
    final safeTarget = engine.chooseBestPass(
      player,
      pressure < (42 * difficulty.reactionFactor) ? backTargets : forwardTargets,
      preferForward: pressure >= (42 / difficulty.reactionFactor),
    );

    if (_shouldLaunchCounter(player, team, engine, ownThird) && random.nextDouble() < (0.58 + difficulty.anticipationFactor * 0.15)) {
      final outlet = engine.chooseBestPass(
        player,
        team.players.where(
          (mate) =>
              mate != player &&
              !mate.isGoalkeeper &&
              (mate.role.isAttacker || mate.role.isWide),
        ),
        preferForward: true,
      );
      if (outlet != null && random.nextDouble() < 0.58) {
        final distance = player.pos.distanceTo(outlet.pos);
        final highRelease = distance > 190 || pressure < 34;
        engine.releaseFromPlayer(
          player,
          outlet.pos - engine.ball.pos,
          highRelease ? 0.98 : 0.78,
          type: highRelease ? KickType.highPass : KickType.pass,
          target: outlet,
          loft: highRelease ? 4.25 + random.nextDouble() * 0.7 : 0,
        );
        player.aiCooldown = 0.42;
        return;
      }
      final laneY = player.role == PlayerRole.leftWing
          ? GameConstants.topBound + GameConstants.pitchHeight * 0.22
          : player.role == PlayerRole.rightWing
          ? GameConstants.topBound + GameConstants.pitchHeight * 0.78
          : GameConstants.virtualHeight / 2 + (random.nextDouble() - 0.5) * 70;
      engine.moveTowards(
        player,
        Vec2(player.pos.x + team.attackDirection * 118, laneY),
        1.0,
        dt,
      );
      player.aiCooldown = 0.12;
      return;
    }

    final keeperOffLine =
        opponent.goalkeeper.pos.distanceTo(goalCenter) > 72 ||
        opponent.goalkeeper.keeperGroundTimer > 0.15;
    final shootingPocket = finalThird && goodAngle && distanceToGoal < 178;
    final emptyGoalChance = shootingPocket && keeperOffLine;
    if (emptyGoalChance ||
        (shootingPocket && distanceToGoal < 132 * difficulty.visionRange) ||
        (shootingPocket && pressure > (34 / difficulty.aggressionFactor) && random.nextDouble() < (0.78 * difficulty.anticipationFactor))) {
      final shotPower = emptyGoalChance
          ? 1.22
          : 1.06 + random.nextDouble() * 0.22;
      engine.takeContextualShot(player, team, shotPower);
      player.aiCooldown = 0.62 + random.nextDouble() * 0.42;
      return;
    }

    if (player.role.isWide && finalThird) {
      if (crossTarget != null &&
          (nearEndLine || pressure < (48 * difficulty.reactionFactor) || random.nextDouble() < (0.68 * difficulty.anticipationFactor))) {
        final highCross = nearEndLine || random.nextDouble() < 0.62;
        engine.releaseFromPlayer(
          player,
          crossTarget.pos - engine.ball.pos,
          highCross ? 0.96 : 0.80,
          type: highCross ? KickType.highPass : KickType.pass,
          target: crossTarget,
          loft: highCross ? 5.05 + random.nextDouble() * 0.65 : 0,
        );
        player.aiCooldown = 0.55 + random.nextDouble() * 0.25;
        return;
      }
      final wingLaneY =
          player.role == PlayerRole.leftWing ||
              player.role == PlayerRole.leftWingBack
          ? GameConstants.topBound + GameConstants.pitchHeight * 0.15
          : GameConstants.topBound + GameConstants.pitchHeight * 0.85;
      final wingTarget = Vec2(
        player.pos.x + team.attackDirection * (nearEndLine ? 18 : 92),
        wingLaneY,
      );
      engine.moveTowards(player, wingTarget, 1.0, dt);
      player.aiCooldown = 0.10;
      return;
    }

    final roleShotBias = switch (player.role) {
      PlayerRole.striker => 34.0,
      PlayerRole.leftWing || PlayerRole.rightWing => 22.0,
      PlayerRole.midfieldLeft || PlayerRole.midfieldRight => 17.0,
      PlayerRole.sweeper => 8.0,
      _ => -12.0,
    };
    final shotScore =
        roleShotBias +
        (finalThird ? 34 : -26) +
        (goodAngle ? 18 : -20) +
        (distanceToGoal < 155
            ? 22
            : distanceToGoal < 260
            ? 8
            : -18) -
        (pressure < 28 ? 10 : 0);
    final crossScore =
        (player.role.isWide ? 34 : -18) +
        (finalThird ? 22 : -8) +
        (nearEndLine ? 26 : 0) +
        (crossTarget != null ? 18 : -30);
    final throughPassScore =
        ((player.role == PlayerRole.midfieldLeft ||
                player.role == PlayerRole.midfieldRight ||
                player.role == PlayerRole.sweeper)
            ? 28
            : 8) +
        (forwardTarget != null ? 22 : -28) +
        (pressure < 38 ? -4 : 6);
    final safePassScore =
        (safeTarget != null ? 28 : -40) +
        (pressure < 45 ? 28 : 4) +
        (player.role.isDefender && ownThird ? 22 : 0);
    // A defender under pressure in his own third must clear the ball
    // (long ball forward) instead of risking a short pass near his goal.
    final inOwnBox = engine.isInPenaltyBox(player.pos, team.id);
    final clearScore = (player.role.isDefender && ownThird && pressure < 52)
        ? (inOwnBox ? 110 : 62)
        : (inOwnBox && player.role.isDefender)
        ? 85
        : -30;
    final dribbleScore =
        (player.role.isWide
            ? 28
            : player.role == PlayerRole.striker
            ? 18
            : 10) +
        (pressure > 38
            ? 26
            : pressure > 24
            ? 8
            : -18) +
        (player.role.isDefender && ownThird ? -35 : 0) +
        (nearEndLine && player.role.isWide ? 18 : 0);

    final decisions = <({String action, double score})>[
      (action: 'shot', score: shotScore.toDouble()),
      (action: 'cross', score: crossScore.toDouble()),
      (action: 'through', score: throughPassScore.toDouble()),
      (action: 'safePass', score: safePassScore.toDouble()),
      (action: 'clear', score: clearScore.toDouble()),
      (action: 'dribble', score: dribbleScore.toDouble()),
    ]..sort((a, b) => b.score.compareTo(a.score));

    final action = decisions.first.action;
    if (action == 'shot') {
      final shotPower = 1.00 + random.nextDouble() * 0.35;
      engine.takeContextualShot(player, team, shotPower);
      player.aiCooldown = 0.65 + random.nextDouble() * 0.55;
      return;
    }

    if (action == 'cross' && crossTarget != null) {
      engine.releaseFromPlayer(
        player,
        crossTarget.pos - engine.ball.pos,
        0.92,
        type: KickType.highPass,
        target: crossTarget,
        loft: 5.0 + random.nextDouble() * 0.65,
      );
      player.aiCooldown = 0.75;
      return;
    }

    if (action == 'through' && forwardTarget != null) {
      final longPass = player.pos.distanceTo(forwardTarget.pos) > 205;
      engine.releaseFromPlayer(
        player,
        forwardTarget.pos - engine.ball.pos,
        longPass ? 1.0 : 0.78,
        type: longPass ? KickType.highPass : KickType.pass,
        target: forwardTarget,
        loft: longPass ? 4.55 : 0,
      );
      player.aiCooldown = 0.55 + random.nextDouble() * 0.45;
      return;
    }

    if (action == 'safePass' && safeTarget != null) {
      engine.releaseFromPlayer(
        player,
        safeTarget.pos - engine.ball.pos,
        0.72,
        type: KickType.pass,
        target: safeTarget,
      );
      player.aiCooldown = 0.45;
      return;
    }

    if (action == 'clear') {
      engine.releaseFromPlayer(
        player,
        Vec2(team.attackDirection.toDouble(), random.nextDouble() - 0.5),
        1.08,
        type: KickType.highPass,
        loft: 4.15,
      );
      player.aiCooldown = 0.6;
      return;
    }

    var laneY = player.pos.y;
    if (player.role == PlayerRole.leftWing) {
      laneY = GameConstants.topBound + GameConstants.pitchHeight * 0.23;
    } else if (player.role == PlayerRole.rightWing) {
      laneY = GameConstants.topBound + GameConstants.pitchHeight * 0.77;
    } else if (player.role == PlayerRole.striker) {
      laneY =
          GameConstants.virtualHeight / 2 + (random.nextDouble() - 0.5) * 42;
    }

    var dribbleTarget = Vec2(player.pos.x + team.attackDirection * 70, laneY);
    if (nearEndLine && player.role.isWide) {
      dribbleTarget = Vec2(
        player.pos.x - team.attackDirection * 8,
        GameConstants.virtualHeight / 2 +
            (player.role == PlayerRole.leftWing ||
                    player.role == PlayerRole.leftWingBack
                ? -55
                : 55),
      );
    }
    if (pressure < 45) {
      dribbleTarget +=
          (player.pos - nearestOpponent.pos).normalized(Vec2(0, 1)) * 30;
    }
    engine.moveTowards(player, dribbleTarget, 1.0, dt);
    player.aiCooldown = 0.18 + random.nextDouble() * 0.18;
  }

  Vec2 _roleTarget(PlayerGame player, TeamGame team, MatchEngine engine) {
    final ball = engine.ball;
    final mode = engine.teamMode(team);
    final d = team.attackDirection;
    final ballY = clampDoubleValue(
      ball.pos.y,
      GameConstants.topBound + 70,
      GameConstants.bottomBound - 70,
    );
    final base = player.homePos.copy();
    // Ball in the attacking third: forwards push into the box, a midfielder
    // joins as the second runner and the sweeper sits on the edge of the
    // box as the trailer for rebounds/long shots.
    final inFinalThird = d == 1
        ? ball.pos.x > GameConstants.virtualWidth * 0.70
        : ball.pos.x < GameConstants.virtualWidth * 0.30;

    final push = switch (mode) {
      TeamMode.attack => switch (player.role) {
        PlayerRole.striker ||
        PlayerRole.leftWing ||
        PlayerRole.rightWing => 132,
        PlayerRole.midfieldLeft || PlayerRole.midfieldRight => 96,
        PlayerRole.leftWingBack || PlayerRole.rightWingBack => 138,
        PlayerRole.sweeper => 150,
        PlayerRole.centerBackLeft || PlayerRole.centerBackRight => 145,
        PlayerRole.goalkeeper => 0,
      },
      TeamMode.defense => switch (player.role) {
        PlayerRole.striker => -22,
        PlayerRole.leftWing || PlayerRole.rightWing => -58,
        PlayerRole.midfieldLeft || PlayerRole.midfieldRight => -72,
        PlayerRole.leftWingBack || PlayerRole.rightWingBack => -85,
        PlayerRole.sweeper => -90,
        PlayerRole.centerBackLeft || PlayerRole.centerBackRight => -65,
        PlayerRole.goalkeeper => 0,
      },
      TeamMode.press => switch (player.role) {
        PlayerRole.striker => 44,
        PlayerRole.leftWing || PlayerRole.rightWing => 36,
        PlayerRole.midfieldLeft || PlayerRole.midfieldRight => 15,
        PlayerRole.leftWingBack || PlayerRole.rightWingBack => 10,
        _ => 0,
      },
    };
    final compact = switch (mode) {
      TeamMode.attack => 0.10,
      TeamMode.defense => 0.42,
      TeamMode.press => 0.28,
    };

    base.x += d * push;
    base.y += (ballY - base.y) * compact;

    // Defenders support possession close to the halfway line, keeping a
    // compact rest-defence instead of being stranded near their own goal.
    // Pushing up this line keeps the offside line far away from the goal.
    if (mode == TeamMode.attack && player.role.isDefender) {
      final supportLine = GameConstants.virtualWidth / 2 -
          d * (player.role == PlayerRole.sweeper ? 86 : 52);
      base.x = (base.x + supportLine) * 0.5;
    }

    // Attacking third: keep 1-2 men in the box and one trailer on the edge.
    if (mode == TeamMode.attack && inFinalThird) {
      switch (player.role) {
        case PlayerRole.striker:
          base.x += d * 22;
        case PlayerRole.leftWing || PlayerRole.rightWing:
          base.x += d * 16;
        case PlayerRole.midfieldLeft || PlayerRole.midfieldRight:
          // The midfielder closest to the box joins it as the second
          // runner; the other sits just outside for the rebound.
          final otherMid = team.players.firstWhere(
            (mate) =>
                mate != player &&
                (mate.role == PlayerRole.midfieldLeft ||
                    mate.role == PlayerRole.midfieldRight),
            orElse: () => player,
          );
          final closerToBox =
              (player.pos.x - otherMid.pos.x) * d >= 0;
          base.x += d * (closerToBox ? 112 : 64);
        case PlayerRole.sweeper:
          // Trailer: waits at the edge of the penalty area to shoot or to
          // collect the second ball.
          base.x += d * 44;
        case _:
          break;
      }
    }

    switch (player.role) {
      case PlayerRole.striker:
        base.y =
            GameConstants.virtualHeight / 2 +
            (ballY - GameConstants.virtualHeight / 2) * 0.22;
        if (mode == TeamMode.attack) {
          base.x += d * 30;
        }
      case PlayerRole.leftWing:
        base.y =
            GameConstants.topBound +
            GameConstants.pitchHeight * (mode == TeamMode.attack ? 0.16 : 0.22);
        if (mode != TeamMode.defense) {
          base.y += (ballY - base.y) * 0.20;
        }
      case PlayerRole.rightWing:
        base.y =
            GameConstants.topBound +
            GameConstants.pitchHeight * (mode == TeamMode.attack ? 0.84 : 0.78);
        if (mode != TeamMode.defense) {
          base.y += (ballY - base.y) * 0.20;
        }
      case PlayerRole.midfieldLeft:
        base.y =
            GameConstants.virtualHeight / 2 -
            (mode == TeamMode.attack ? 64 : 35) +
            (ballY - GameConstants.virtualHeight / 2) * 0.16;
      case PlayerRole.midfieldRight:
        base.y =
            GameConstants.virtualHeight / 2 +
            (mode == TeamMode.attack ? 64 : 35) +
            (ballY - GameConstants.virtualHeight / 2) * 0.16;
      case PlayerRole.leftWingBack:
        base.y =
            GameConstants.topBound +
            GameConstants.pitchHeight * (mode == TeamMode.attack ? 0.18 : 0.25);
        if (ball.pos.y < GameConstants.virtualHeight / 2) {
          base.x += d * (mode == TeamMode.attack ? 48 : 0);
        }
      case PlayerRole.rightWingBack:
        base.y =
            GameConstants.topBound +
            GameConstants.pitchHeight * (mode == TeamMode.attack ? 0.82 : 0.75);
        if (ball.pos.y > GameConstants.virtualHeight / 2) {
          base.x += d * (mode == TeamMode.attack ? 48 : 0);
        }
      case PlayerRole.sweeper:
        base.y =
            GameConstants.virtualHeight / 2 +
            (ballY - GameConstants.virtualHeight / 2) * 0.26;
        if (mode == TeamMode.attack) {
          base.x += d * 24;
        } else if (mode == TeamMode.defense) {
          base.x -= d * 20;
        }
      case PlayerRole.centerBackLeft:
        base.y =
            GameConstants.virtualHeight / 2 -
            55 +
            (ballY - GameConstants.virtualHeight / 2) * 0.18;
        if (mode == TeamMode.attack) {
          base.x += d * 16;
        }
      case PlayerRole.centerBackRight:
        base.y =
            GameConstants.virtualHeight / 2 +
            55 +
            (ballY - GameConstants.virtualHeight / 2) * 0.18;
        if (mode == TeamMode.attack) {
          base.x += d * 16;
        }
      case PlayerRole.goalkeeper:
        break;
    }

    base.clampTo(
      GameConstants.leftBound + 35,
      GameConstants.topBound + 25,
      GameConstants.rightBound - 35,
      GameConstants.bottomBound - 25,
    );
    return base;
  }

  Vec2 _cornerAttackTarget(
    PlayerGame player,
    TeamGame team,
    MatchEngine engine,
  ) {
    final ball = engine.ball;
    if (ball.heightMeters > 0.7 &&
        ball.pos.distanceTo(player.pos) < 125 &&
        !player.role.isDefender) {
      return ball.pos;
    }
    final d = team.attackDirection;
    final goalMouthX = d == 1
        ? GameConstants.rightBound - 78
        : GameConstants.leftBound + 78;
    final centerY = GameConstants.virtualHeight / 2;
    final target = switch (player.role) {
      PlayerRole.striker => Vec2(goalMouthX, centerY),
      PlayerRole.leftWing => Vec2(goalMouthX - d * 18, centerY - 58),
      PlayerRole.rightWing => Vec2(goalMouthX - d * 18, centerY + 58),
      PlayerRole.midfieldLeft => Vec2(goalMouthX - d * 58, centerY - 26),
      PlayerRole.midfieldRight => Vec2(goalMouthX - d * 58, centerY + 26),
      PlayerRole.leftWingBack => Vec2(goalMouthX - d * 98, centerY - 92),
      PlayerRole.rightWingBack => Vec2(goalMouthX - d * 98, centerY + 92),
      PlayerRole.centerBackLeft => Vec2(goalMouthX - d * 118, centerY - 46),
      PlayerRole.centerBackRight => Vec2(goalMouthX - d * 118, centerY + 46),
      PlayerRole.sweeper => Vec2(goalMouthX - d * 136, centerY),
      PlayerRole.goalkeeper => player.homePos.copy(),
    };
    target.clampTo(
      GameConstants.leftBound + 32,
      GameConstants.topBound + 28,
      GameConstants.rightBound - 32,
      GameConstants.bottomBound - 28,
    );
    return target;
  }

  bool _attackerShouldDrop(
    PlayerGame player,
    TeamGame team,
    MatchEngine engine,
  ) {
    return player.role.isAttacker && engine.shouldAttackersDrop(team);
  }

  Vec2 _attackerDefensiveTarget(
    PlayerGame player,
    TeamGame team,
    MatchEngine engine,
  ) {
    final ballY = clampDoubleValue(
      engine.ball.pos.y,
      GameConstants.topBound + 72,
      GameConstants.bottomBound - 72,
    );
    final danger = engine.teamUnderDanger(team);
    final xRatio = danger ? 0.29 : 0.39;
    final supportX = team.attackDirection == 1
        ? GameConstants.leftBound + GameConstants.pitchWidth * xRatio
        : GameConstants.rightBound - GameConstants.pitchWidth * xRatio;
    final centerY = GameConstants.virtualHeight / 2;
    final target = switch (player.role) {
      PlayerRole.striker => Vec2(
        supportX + team.attackDirection * (danger ? 24 : 48),
        centerY + (ballY - centerY) * 0.30,
      ),
      PlayerRole.leftWing => Vec2(
        supportX,
        GameConstants.topBound +
            GameConstants.pitchHeight * (ballY < centerY ? 0.25 : 0.34),
      ),
      PlayerRole.rightWing => Vec2(
        supportX,
        GameConstants.topBound +
            GameConstants.pitchHeight * (ballY > centerY ? 0.75 : 0.66),
      ),
      _ => player.homePos.copy(),
    };
    target.clampTo(
      GameConstants.leftBound + 30,
      GameConstants.topBound + 32,
      GameConstants.rightBound - 30,
      GameConstants.bottomBound - 32,
    );
    return target;
  }

  Vec2 _keeperReleaseWaitTarget(
    PlayerGame player,
    TeamGame team,
    TeamGame opponent,
    MatchEngine engine,
  ) {
    if (engine.isGoalKickLockedAgainst(team.id)) {
      final centerX = GameConstants.virtualWidth / 2;
      final lane = switch (player.role) {
        PlayerRole.leftWing || PlayerRole.leftWingBack => 0.28,
        PlayerRole.rightWing || PlayerRole.rightWingBack => 0.72,
        PlayerRole.striker => 0.50,
        PlayerRole.midfieldLeft => 0.40,
        PlayerRole.midfieldRight => 0.60,
        _ => 0.50,
      };
      return Vec2(
        opponent.side == TeamSide.left ? centerX + 36 : centerX - 36,
        GameConstants.topBound + GameConstants.pitchHeight * lane,
      );
    }
    final boxGuardX = opponent.side == TeamSide.left
        ? GameConstants.leftBound + 178
        : GameConstants.rightBound - 178;
    final centerY = GameConstants.virtualHeight / 2;
    final ballY = clampDoubleValue(
      engine.ball.pos.y,
      GameConstants.topBound + 72,
      GameConstants.bottomBound - 72,
    );
    final target = switch (player.role) {
      PlayerRole.striker => Vec2(
        boxGuardX + team.attackDirection * 18,
        centerY + (ballY - centerY) * 0.18,
      ),
      PlayerRole.leftWing => Vec2(boxGuardX, centerY - 82),
      PlayerRole.rightWing => Vec2(boxGuardX, centerY + 82),
      PlayerRole.midfieldLeft => Vec2(
        boxGuardX - team.attackDirection * 62,
        centerY - 58,
      ),
      PlayerRole.midfieldRight => Vec2(
        boxGuardX - team.attackDirection * 62,
        centerY + 58,
      ),
      _ => _roleTarget(player, team, engine),
    };
    target.clampTo(
      GameConstants.leftBound + 34,
      GameConstants.topBound + 34,
      GameConstants.rightBound - 34,
      GameConstants.bottomBound - 34,
    );
    return target;
  }

  bool _shouldLaunchCounter(
    PlayerGame player,
    TeamGame team,
    MatchEngine engine,
    bool ownThird,
  ) {
    if (!player.role.isAttacker) {
      return false;
    }
    final ownHalf = team.attackDirection == 1
        ? player.pos.x < GameConstants.virtualWidth * 0.50
        : player.pos.x > GameConstants.virtualWidth * 0.50;
    return (ownThird || ownHalf) && engine.counterOpportunityFor(team, player);
  }

  void _maybeJumpForHighBall(PlayerGame player, MatchEngine engine) {
    final ball = engine.ball;
    if (ball.owner != null || ball.heightMeters < 1.25) {
      player.jumpBoostMeters = 0;
      return;
    }
    final close = player.pos.distanceTo(ball.pos) < 24;
    final nearHead =
        ball.heightMeters <= player.profile.heightMeters + 0.18 &&
        ball.heightMeters >= player.profile.heightMeters - 0.24;
    if (close && nearHead) {
      player
        ..jumpBoostMeters = 0.10 + random.nextDouble() * 0.03
        ..jumpAnimationTimer = 0.48;
    } else {
      player.jumpBoostMeters *= 0.85;
      if (player.jumpBoostMeters < 0.01) {
        player.jumpBoostMeters = 0;
      }
    }
  }
}
