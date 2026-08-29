import 'dart:math' as math;

import '../config/game_constants.dart';
import '../enums/kick_type.dart';
import '../enums/player_role.dart';
import '../enums/ai_difficulty.dart';
import '../enums/team_id.dart';
import '../math/vec2.dart';
import '../models/player_game.dart';
import '../models/team_game.dart';
import '../tactics/danger_zone.dart';
import '../tactics/tactical_engine.dart';
import '../tactics/team_play_state.dart';
import 'match_engine.dart';

/// What a defending player is doing right now — the defensive decision chain
/// of plan items 14 and 23: protect the goal → stop the danger → cover the
/// pressing team-mate → close the passing lane → press → return to shape.
enum DefensiveDuty {
  protectGoal,
  pressCarrier,
  coverPresser,
  closeLane,
  holdShape,
}

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

  // =====================================================================
  // Off the ball — the movement pipeline of plan item 29
  // =====================================================================

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

    final context = engine.tacticalContextFor(team);
    Vec2 finalTarget;
    var force = context.playState.urgency;

    if (ball.owner != null && ball.owner!.teamId != team.id) {
      // ---------------- Opponent has the ball (plan item 23, defensive
      // priority): protect the goal, stop the danger, cover, close the
      // lane, press, return to shape.
      final duty = _selectDefensiveDuty(player, team, opponent, context, engine);
      switch (duty) {
        case DefensiveDuty.protectGoal:
          finalTarget = _protectGoalTarget(player, team, engine);
          force += 0.10;
        case DefensiveDuty.pressCarrier:
          finalTarget = _pressTarget(player, team, engine, context);
          force += 0.12;
        case DefensiveDuty.coverPresser:
          finalTarget = _coverTarget(player, team, opponent, engine, context);
          force += 0.04;
        case DefensiveDuty.closeLane:
          finalTarget = _passLaneTarget(player, team, opponent, engine, context);
        case DefensiveDuty.holdShape:
          final covered = engine.coverageTargetFor(player, team);
          if (covered != null) {
            finalTarget = covered;
          } else if (player.role.isAttacker && engine.shouldAttackersDrop(team)) {
            // Attackers help the defence when the result or the danger
            // demands it, without turning into defenders (plan item 11).
            final drop = _attackerDefensiveTarget(player, team, engine);
            final anchor = context.dynamicAnchor(player);
            finalTarget = Vec2(
              drop.x * 0.65 + anchor.x * 0.35,
              drop.y * 0.65 + anchor.y * 0.35,
            );
          } else {
            finalTarget = context.dynamicAnchor(player);
            // Centre backs keep depth, cover and watch the nearest striker
            // (plan item 20): a light goal-side marking bias on top of the
            // shape anchor.
            if (player.role.group == RoleGroup.centralDefence) {
              final mark = _centreBackMark(player, team, opponent, context, engine);
              if (mark != null) {
                finalTarget = Vec2(
                  finalTarget.x * 0.55 + mark.x * 0.45,
                  finalTarget.y * 0.55 + mark.y * 0.45,
                );
              }
            }
          }
      }
    } else if (ball.owner != null && ball.owner!.teamId == team.id) {
      // ---------------- We have the ball (plan item 23, offensive
      // priority): exploit the chance, support the carrier, create space,
      // attack the box, keep the width, otherwise return to shape.
      finalTarget = _attackingTarget(player, team, opponent, context, engine);
    } else {
      // ---------------- Loose ball: only the closest player chases and
      // only when it is realistically reachable; everybody else keeps his
      // dynamic shape (plan item 6: not everybody runs at the ball).
      if (engine.isCornerAttackActiveFor(team) && !player.isGoalkeeper) {
        finalTarget = _cornerAttackTarget(player, team, engine);
      } else {
        final chase = _looseBallChaser(team, engine);
        if (chase == player) {
          finalTarget = _interceptionPoint(player, engine);
          force += 0.10;
        } else if (_isSecondChaser(player, chase, team, engine) &&
            player.pos.distanceTo(ball.pos) < 190) {
          // The second player moves to the landing/receiving area instead
          // of joining the same chase.
          finalTarget = _interceptionPoint(player, engine);
          force += 0.04;
        } else {
          final covered = engine.coverageTargetFor(player, team);
          finalTarget = covered ?? context.dynamicAnchor(player);
        }
      }
    }

    _maybeJumpForHighBall(player, engine);
    // The run force is computed, never a fixed value: it follows the state,
    // the distance, the danger, the role and the fatigue (plan item 22).
    engine.moveTowards(player, finalTarget, _movementForce(player, finalTarget, context, force), dt);
  }

  // ----------------------------------------------------------------------
  // Defensive decisions (plan items 6, 12, 13, 14, 15)
  // ----------------------------------------------------------------------

  DefensiveDuty _selectDefensiveDuty(
    PlayerGame player,
    TeamGame team,
    TeamGame opponent,
    TacticalContext context,
    MatchEngine engine,
  ) {
    final carrier = engine.ball.owner!;
    final role = player.role;
    final critical = context.ballZone == DangerZone.critical;

    // 1) Protect the goal: when the carrier operates in the critical zone,
    // the deepest defender takes the space between ball and goal (plan
    // items 12 and 13) — pushing the opponent away from the goal area.
    if (critical && role.isDefender) {
      final protector = _goalProtector(team, engine);
      if (protector == player) {
        return DefensiveDuty.protectGoal;
      }
    }

    // 2) Stop the danger: the designated presser engages the carrier.
    if (_isDesignatedPresser(player, team, carrier, context, engine)) {
      return DefensiveDuty.pressCarrier;
    }

    // 3) Cover the presser: the closest defender behind the presser picks
    // up the space/second man so no dangerous gap opens (plan item 15).
    if (role.isDefender || role == PlayerRole.defensiveMidfielder) {
      final presser = _designatedPresser(team, carrier, context, engine);
      if (presser != null && presser != player && _isNaturalCover(player, team, presser)) {
        return DefensiveDuty.coverPresser;
      }
    }

    // 4) Close the passing lane toward our hot zones.
    if (context.ballZone.isHot &&
        (role.isMidfield || role.isDefender) &&
        _guardsHotLane(player, team, opponent, engine, context)) {
      return DefensiveDuty.closeLane;
    }

    // 5) Everybody else holds the dynamic shape (plan items 6 and 28).
    return DefensiveDuty.holdShape;
  }

  /// The player who engages the ball carrier: chosen from pressing priority
  /// and real reachability — never the goalkeeper, never the whole team
  /// (plan item 6).
  PlayerGame? _designatedPresser(
    TeamGame team,
    PlayerGame carrier,
    TacticalContext context,
    MatchEngine engine,
  ) {
    PlayerGame? best;
    var bestScore = -1.0;
    for (final player in team.players) {
      if (player.isGoalkeeper || player.isSentOff) {
        continue;
      }
      final distance = player.pos.distanceTo(carrier.pos);
      if (distance > 430) {
        continue;
      }
      final stateBias = context.playState.rolePressBias(player.role, context.style);
      final reach = 1.0 - (distance / 430).clamp(0.0, 1.0);
      final score = stateBias * 1.4 + player.role.pressingPriority + reach * 0.8;
      if (score > bestScore) {
        bestScore = score;
        best = player;
      }
    }
    return best;
  }

  bool _isDesignatedPresser(
    PlayerGame player,
    TeamGame team,
    PlayerGame carrier,
    TacticalContext context,
    MatchEngine engine,
  ) {
    final presser = _designatedPresser(team, carrier, context, engine);
    return presser == player;
  }

  /// The defender who guards the space between the ball and our goal when
  /// the opponent attacks the critical zone (plan items 12, 13).
  PlayerGame _goalProtector(TeamGame team, MatchEngine engine) {
    final goalCenter = engine.goalCenterFor(team);
    final ball = engine.ball.pos;
    final defenders = team.players
        .where((player) =>
            !player.isGoalkeeper &&
            !player.isSentOff &&
            player.role.group == RoleGroup.centralDefence)
        .toList()
      ..sort((a, b) {
        final aScore = a.pos.distanceTo(ball) * 0.55 +
            a.pos.distanceTo(goalCenter) * 0.45;
        final bScore = b.pos.distanceTo(ball) * 0.55 +
            b.pos.distanceTo(goalCenter) * 0.45;
        return aScore.compareTo(bScore);
      });
    return defenders.isNotEmpty
        ? defenders.first
        : team.closestTo(goalCenter, includeGoalkeeper: false);
  }

  /// Is this player the natural cover behind the presser? (plan item 15)
  bool _isNaturalCover(PlayerGame player, TeamGame team, PlayerGame presser) {
    final goalCenter = Vec2(
      team.side == TeamSide.left ? GameConstants.leftBound : GameConstants.rightBound,
      GameConstants.virtualHeight / 2,
    );
    final presserToGoal = (goalCenter - presser.pos).length;
    final playerToGoal = (goalCenter - player.pos).length;
    return playerToGoal < presserToGoal + 30 &&
        player.pos.distanceTo(presser.pos) < 240;
  }

  /// Goal-side marking position for a centre back watching the nearest
  /// opponent attacker (plan item 20: keep depth, cover, mark the striker).
  Vec2? _centreBackMark(
    PlayerGame player,
    TeamGame team,
    TeamGame opponent,
    TacticalContext context,
    MatchEngine engine,
  ) {
    final ourHalf = team.attackDirection == 1
        ? engine.ball.pos.x < GameConstants.virtualWidth * 0.55
        : engine.ball.pos.x > GameConstants.virtualWidth * 0.45;
    if (!ourHalf) {
      return null;
    }
    PlayerGame? nearest;
    var bestDistance = 210.0;
    for (final rival in opponent.players) {
      if (rival.isGoalkeeper ||
          rival.isSentOff ||
          !(rival.role.isAttacker ||
              rival.role == PlayerRole.attackingMidfielder)) {
        continue;
      }
      final distance = rival.pos.distanceTo(player.pos);
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = rival;
      }
    }
    if (nearest == null) {
      return null;
    }
    final goalCenter = engine.goalCenterFor(team);
    final mark = nearest.pos +
        (goalCenter - nearest.pos).normalized(Vec2(0, 1)) * 14;
    // Never mark beyond the defensive line or outside the own zone.
    final lineFraction = (context.defensiveLineX -
            (team.side == TeamSide.left
                ? GameConstants.leftBound
                : GameConstants.rightBound)) *
        team.attackDirection /
        GameConstants.pitchWidth;
    final ownGoalX = team.side == TeamSide.left
        ? GameConstants.leftBound
        : GameConstants.rightBound;
    final markFraction =
        ((mark.x - ownGoalX) * team.attackDirection / GameConstants.pitchWidth)
            .clamp(0.06, lineFraction + 0.03)
            .toDouble();
    mark.x = ownGoalX +
        team.attackDirection * GameConstants.pitchWidth * markFraction;
    mark.clampTo(
      GameConstants.leftBound + 30,
      GameConstants.topBound + 30,
      GameConstants.rightBound - 30,
      GameConstants.bottomBound - 30,
    );
    return mark;
  }

  /// Stand between the ball and the goal, close enough to smother a shot
  /// but not so close that the carrier plays around him (plan item 12).
  Vec2 _protectGoalTarget(PlayerGame player, TeamGame team, MatchEngine engine) {    final goalCenter = engine.goalCenterFor(team);
    final ball = engine.ball.pos;
    final direction = (goalCenter - ball).normalized(Vec2(0, 1));
    final target = ball + direction * 30;
    target.clampTo(
      GameConstants.leftBound + 30,
      GameConstants.topBound + 30,
      GameConstants.rightBound - 30,
      GameConstants.bottomBound - 30,
    );
    return target;
  }

  /// The presser approaches from the goal side and steers the carrier away
  /// from the goal, toward the touchline or backwards (plan item 12).
  Vec2 _pressTarget(
    PlayerGame player,
    TeamGame team,
    MatchEngine engine,
    TacticalContext context,
  ) {
    final carrier = engine.ball.owner!;
    final goalCenter = engine.goalCenterFor(team);
    final goalSide = (goalCenter - carrier.pos).normalized(Vec2(-1, 0));
    final centerY = GameConstants.virtualHeight / 2;
    final outward = Vec2(
      0,
      carrier.pos.y >= centerY
          ? GameConstants.bottomBound - carrier.pos.y
          : GameConstants.topBound - carrier.pos.y,
    ).normalized(Vec2(0, 1));
    // 70% goal-side block, 30% steering outward: the opponent is pushed
    // away from the goal, not merely followed.
    final steer = goalSide * 0.72 + outward * 0.28;
    return carrier.pos + steer.normalized(Vec2(0, 1)) * 10;
  }

  /// Cover position: goal-side behind the presser, shading the most
  /// dangerous free opponent (plan item 15).
  Vec2 _coverTarget(
    PlayerGame player,
    TeamGame team,
    TeamGame opponent,
    MatchEngine engine,
    TacticalContext context,
  ) {
    final goalCenter = engine.goalCenterFor(team);
    final carrier = engine.ball.owner!;
    final presser = _designatedPresser(team, carrier, context, engine);
    final base = presser?.pos ?? carrier.pos;
    var target = base + (goalCenter - base).normalized(Vec2(0, 1)) * 68;

    // Shade the second opponent in the neighbourhood if he is free.
    PlayerGame? secondMan;
    var bestDistance = double.infinity;
    for (final rival in opponent.players) {
      if (rival.isGoalkeeper || rival == carrier || rival.isSentOff) {
        continue;
      }
      final distance = rival.pos.distanceTo(base);
      if (distance < 150 && distance < bestDistance) {
        bestDistance = distance;
        secondMan = rival;
      }
    }
    if (secondMan != null) {
      final shade = secondMan.pos +
          (goalCenter - secondMan.pos).normalized(Vec2(0, 1)) * 24;
      target = target * 0.5 + shade * 0.5;
    }
    target.clampTo(
      GameConstants.leftBound + 30,
      GameConstants.topBound + 30,
      GameConstants.rightBound - 30,
      GameConstants.bottomBound - 30,
    );
    return target;
  }

  /// Intercept position on the passing lane from the carrier toward our hot
  /// zones (plan items 13 and 14).
  Vec2 _passLaneTarget(
    PlayerGame player,
    TeamGame team,
    TeamGame opponent,
    MatchEngine engine,
    TacticalContext context,
  ) {
    final goalCenter = engine.goalCenterFor(team);
    final carrier = engine.ball.pos;
    PlayerGame? hottest;
    var bestThreat = -1.0;
    for (final rival in opponent.players) {
      if (rival.isGoalkeeper || rival == engine.ball.owner || rival.isSentOff) {
        continue;
      }
      final threat = 1.0 - (rival.pos.distanceTo(goalCenter) /
              (GameConstants.pitchWidth * 0.9));
      if (threat > bestThreat &&
          rival.pos.distanceTo(player.pos) < 260) {
        bestThreat = threat;
        hottest = rival;
      }
    }
    if (hottest == null) {
      return context.dynamicAnchor(player);
    }
    // Cut the lane at 45% from the carrier toward the dangerous receiver.
    final lane = hottest.pos - carrier;
    return carrier + lane * 0.45;
  }

  bool _guardsHotLane(
    PlayerGame player,
    TeamGame team,
    TeamGame opponent,
    MatchEngine engine,
    TacticalContext context,
  ) {
    final goalCenter = engine.goalCenterFor(team);
    final carrier = engine.ball.owner!;
    for (final rival in opponent.players) {
      if (rival.isGoalkeeper || rival == carrier || rival.isSentOff) {
        continue;
      }
      final lane = rival.pos - carrier.pos;
      final laneLength = lane.length;
      if (laneLength < 30) {
        continue;
      }
      // Is the player close to the carrier→rival line, and does that line
      // point into our hot zone?
      final toPlayer = player.pos - carrier.pos;
      final projection = toPlayer.dot(lane.normalized(Vec2(0, 1)));
      if (projection < 0 || projection > laneLength + 60) {
        continue;
      }
      final perpendicular =
          (toPlayer - lane.normalized(Vec2(0, 1)) * projection).length;
      final receiverZone = const DangerMapper()
          .zoneFor(rival.pos, team.side);
      if (perpendicular < 55 &&
          (receiverZone.isHot ||
              rival.pos.distanceTo(goalCenter) < 300)) {
        return true;
      }
    }
    return false;
  }

  // ----------------------------------------------------------------------
  // Attacking movement (plan items 8, 10, 20, 23)
  // ----------------------------------------------------------------------

  Vec2 _attackingTarget(
    PlayerGame player,
    TeamGame team,
    TeamGame opponent,
    TacticalContext context,
    MatchEngine engine,
  ) {
    final carrier = engine.ball.owner!;
    final anchor = context.dynamicAnchor(player);
    final lineX = engine.offsideLineFor(team) - team.attackDirection * 8;

    // Support the carrier: the two nearest team-mates offer a passing angle
    // behind/side of the carrier (plan item 23: support the ball carrier).
    final supportSpot = _carrierSupportSpot(player, team, carrier, context);
    if (supportSpot != null) {
      return supportSpot;
    }

    final role = player.role;

    // Striker: threatens the defensive line, drifts to the ball side and
    // attacks the box when the ball is wide and advanced (plan item 20).
    if (role == PlayerRole.striker) {
      final wideAdvanced = _carrierWideAndAdvanced(carrier, team);
      if (wideAdvanced) {
        final boxX = team.attackDirection == 1
            ? math.min(GameConstants.rightBound - 88, lineX)
            : math.max(GameConstants.leftBound + 88, lineX);
        return Vec2(boxX, GameConstants.virtualHeight / 2);
      }
      return anchor;
    }

    // Wingers: keep the width in possession, attack the box from the far
    // post when the carrier reaches the end line (plan item 20).
    if (role == PlayerRole.leftWing || role == PlayerRole.rightWing) {
      if (_carrierWideAndAdvanced(carrier, team) &&
          (carrier.pos.y - player.pos.y).abs() > 120) {
        final farPostY = GameConstants.virtualHeight / 2 +
            (player.pos.y > GameConstants.virtualHeight / 2 ? 58 : -58);
        final boxX = team.attackDirection == 1
            ? math.min(GameConstants.rightBound - 100, lineX)
            : math.max(GameConstants.leftBound + 100, lineX);
        return Vec2(boxX, farPostY);
      }
      return anchor;
    }

    // Attacking midfielder: lives between the lines, supports the striker,
    // enters the box as the second runner (plan item 20).
    if (role == PlayerRole.attackingMidfielder) {
      final advanced = team.attackDirection == 1
          ? carrier.pos.x > GameConstants.virtualWidth * 0.62
          : carrier.pos.x < GameConstants.virtualWidth * 0.38;
      if (advanced) {
        final boxX = team.attackDirection == 1
            ? math.min(GameConstants.rightBound - 118, lineX)
            : math.max(GameConstants.leftBound + 118, lineX);
        return Vec2(boxX, anchor.y);
      }
      return anchor;
    }

    // Central midfielders: one joins the box as the second runner when the
    // ball is wide and advanced, the other keeps the balance.
    if (role == PlayerRole.midfieldLeft || role == PlayerRole.midfieldRight) {
      if (_carrierWideAndAdvanced(carrier, team) &&
          _isClosestCentralMid(player, team)) {
        final boxX = team.attackDirection == 1
            ? GameConstants.rightBound - 120
            : GameConstants.leftBound + 120;
        return Vec2(boxX, GameConstants.virtualHeight / 2);
      }
      return anchor;
    }

    return anchor;
  }

  /// Passing angle offer: the closest one goes short behind the carrier,
  /// the second at a wider angle (plan item 23: support the ball carrier).
  Vec2? _carrierSupportSpot(
    PlayerGame player,
    TeamGame team,
    PlayerGame carrier,
    TacticalContext context,
  ) {
    if (player == carrier || player.isGoalkeeper) {
      return null;
    }
    final fieldPlayers = team.players
        .where((mate) => mate != carrier && !mate.isGoalkeeper && !mate.isSentOff)
        .toList()
      ..sort(
        (a, b) => a.pos
            .distanceTo(carrier.pos)
            .compareTo(b.pos.distanceTo(carrier.pos)),
      );
    final rank = fieldPlayers.indexOf(player);
    if (rank != 0 && rank != 1) {
      return null;
    }
    final d = team.attackDirection;
    // Support behind and beside the carrier — a safe backward/angled pass.
    final sideSign = rank == 0
        ? (player.pos.y >= carrier.pos.y ? 1.0 : -1.0)
        : -1.0 * (player.pos.y >= carrier.pos.y ? 1.0 : -1.0);
    final depth = rank == 0 ? 52.0 : 86.0;
    final spot = Vec2(
      carrier.pos.x - d * depth,
      carrier.pos.y + sideSign * (rank == 0 ? 34.0 : 62.0),
    );
    spot.clampTo(
      GameConstants.leftBound + 40,
      GameConstants.topBound + 35,
      GameConstants.rightBound - 40,
      GameConstants.bottomBound - 35,
    );
    return spot;
  }

  bool _carrierWideAndAdvanced(PlayerGame carrier, TeamGame team) {
    if (!carrier.role.isWide) {
      return false;
    }
    return team.attackDirection == 1
        ? carrier.pos.x > GameConstants.virtualWidth * 0.62
        : carrier.pos.x < GameConstants.virtualWidth * 0.38;
  }

  bool _isClosestCentralMid(PlayerGame player, TeamGame team) {
    final mids = team.players
        .where((mate) =>
            !mate.isSentOff &&
            (mate.role == PlayerRole.midfieldLeft ||
                mate.role == PlayerRole.midfieldRight))
        .toList();
    if (mids.length < 2) {
      return true;
    }
    final other = mids.firstWhere((mate) => mate != player, orElse: () => player);
    final d = team.attackDirection;
    return (player.pos.x - other.pos.x) * d >= 0;
  }

  // ----------------------------------------------------------------------
  // Loose-ball discipline (plan item 6)
  // ----------------------------------------------------------------------

  PlayerGame _looseBallChaser(TeamGame team, MatchEngine engine) {
    return team.closestTo(engine.ball.pos, includeGoalkeeper: false);
  }

  bool _isSecondChaser(
    PlayerGame player,
    PlayerGame chase,
    TeamGame team,
    MatchEngine engine,
  ) {
    if (player == chase || player.isGoalkeeper) {
      return false;
    }
    var secondClosest = true;
    for (final mate in team.players) {
      if (mate == player ||
          mate == chase ||
          mate.isGoalkeeper ||
          mate.isSentOff) {
        continue;
      }
      if (mate.pos.distanceTo(engine.ball.pos) <
          player.pos.distanceTo(engine.ball.pos)) {
        secondClosest = false;
        break;
      }
    }
    return secondClosest;
  }

  /// Where the ball will realistically be reachable — the chaser runs to
  /// the interception point instead of the current ball spot.
  Vec2 _interceptionPoint(PlayerGame player, MatchEngine engine) {
    final ball = engine.ball;
    final speed = ball.vel.length;
    if (speed < 40) {
      return ball.pos;
    }
    final travel = (speed * 0.28).clamp(0.0, 130.0).toDouble();
    return ball.pos + ball.vel.normalized(Vec2(0, 1)) * travel;
  }

  // ----------------------------------------------------------------------
  // Movement force (plan item 22)
  // ----------------------------------------------------------------------

  /// Speed is computed every tick from the state, the distance, the danger,
  /// the role and the fatigue — there are no fixed movement constants.
  double _movementForce(
    PlayerGame player,
    Vec2 target,
    TacticalContext context,
    double baseForce,
  ) {
    var force = baseForce;
    final distance = player.pos.distanceTo(target);
    force += (distance / 460).clamp(0.0, 0.14);
    if (context.playState == TeamPlayState.defensiveTransition) {
      force += 0.08;
    }
    if (context.playState == TeamPlayState.attackingTransition &&
        player.role.isAttacker) {
      force += 0.07;
    }
    if (context.ballZone.isHot && player.role.isDefender) {
      force += 0.10;
    }
    force -= (1.0 - player.stamina) * 0.22;
    force *= player.role.speedBias;
    return force.clamp(0.45, 1.0).toDouble();
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
    final context = engine.tacticalContextFor(team);
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
                          player.role == PlayerRole.leftWingBack ||
                          player.role == PlayerRole.leftBack
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
          (p.role.isAttacker || p.role.isMidfield),
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
              player.role == PlayerRole.leftWingBack ||
              player.role == PlayerRole.leftBack
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

    // Style and risk bias the with-ball decision scores: patient styles and
    // protected leads prefer safe circulation, chasing styles gamble.
    final safeBias = (context.style.riskFactor - context.riskLevel) * 26.0;
    final gambleBias = (context.riskLevel - 0.35) * 18.0;

    final roleShotBias = switch (player.role) {
      PlayerRole.striker => 34.0,
      PlayerRole.leftWing ||
      PlayerRole.rightWing ||
      PlayerRole.attackingMidfielder => 22.0,
      PlayerRole.midfieldLeft || PlayerRole.midfieldRight => 17.0,
      PlayerRole.sweeper || PlayerRole.defensiveMidfielder => 8.0,
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
        (pressure < 28 ? 10 : 0) +
        gambleBias * 0.5;
    final crossScore =
        (player.role.isWide ? 34 : -18) +
        (finalThird ? 22 : -8) +
        (nearEndLine ? 26 : 0) +
        (crossTarget != null ? 18 : -30);
    final throughPassScore =
        ((player.role == PlayerRole.midfieldLeft ||
                player.role == PlayerRole.midfieldRight ||
                player.role == PlayerRole.sweeper ||
                player.role == PlayerRole.attackingMidfielder ||
                player.role == PlayerRole.defensiveMidfielder)
            ? 28
            : 8) +
        (forwardTarget != null ? 22 : -28) +
        (pressure < 38 ? -4 : 6) +
        gambleBias;
    final safePassScore =
        (safeTarget != null ? 28 : -40) +
        (pressure < 45 ? 28 : 4) +
        (player.role.isDefender && ownThird ? 22 : 0) +
        safeBias;
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
                    player.role == PlayerRole.leftWingBack ||
                    player.role == PlayerRole.leftBack
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
      PlayerRole.attackingMidfielder => Vec2(goalMouthX - d * 58, centerY),
      PlayerRole.midfieldLeft => Vec2(goalMouthX - d * 58, centerY - 26),
      PlayerRole.midfieldRight => Vec2(goalMouthX - d * 58, centerY + 26),
      PlayerRole.leftWingBack => Vec2(goalMouthX - d * 98, centerY - 92),
      PlayerRole.rightWingBack => Vec2(goalMouthX - d * 98, centerY + 92),
      PlayerRole.leftBack => Vec2(goalMouthX - d * 108, centerY - 86),
      PlayerRole.rightBack => Vec2(goalMouthX - d * 108, centerY + 86),
      PlayerRole.centerBackLeft => Vec2(goalMouthX - d * 118, centerY - 46),
      PlayerRole.centerBackRight => Vec2(goalMouthX - d * 118, centerY + 46),
      PlayerRole.sweeper => Vec2(goalMouthX - d * 136, centerY),
      PlayerRole.goalkeeper => player.homePos.copy(),
      PlayerRole.defensiveMidfielder => Vec2(goalMouthX - d * 128, centerY),
    };
    target.clampTo(
      GameConstants.leftBound + 32,
      GameConstants.topBound + 28,
      GameConstants.rightBound - 32,
      GameConstants.bottomBound - 28,
    );
    return target;
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
        PlayerRole.leftWing ||
        PlayerRole.leftWingBack ||
        PlayerRole.leftBack => 0.28,
        PlayerRole.rightWing ||
        PlayerRole.rightWingBack ||
        PlayerRole.rightBack => 0.72,
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
      _ => engine.tacticalContextFor(team).dynamicAnchor(player),
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
