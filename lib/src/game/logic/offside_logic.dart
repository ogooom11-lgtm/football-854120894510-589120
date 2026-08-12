import '../config/game_constants.dart';
import '../math/vec2.dart';
import '../models/ball_game.dart';
import '../models/match_event.dart';
import '../models/player_game.dart';
import '../models/team_game.dart';

class OffsideCandidate {
  const OffsideCandidate({
    required this.offender,
    required this.event,
    required this.createdMinute,
  });

  final PlayerGame offender;
  final OffsideEvent event;
  final double createdMinute;
}

class OffsideLogic {
  const OffsideLogic();

  OffsideCandidate? evaluatePass({
    required TeamGame attackingTeam,
    required TeamGame defendingTeam,
    required PlayerGame passer,
    required PlayerGame? receiver,
    required BallGame ball,
    required double minute,
    required bool highPass,
  }) {
    final direction = attackingTeam.attackDirection;
    final defenders = [...defendingTeam.players]
      ..sort(
        (a, b) => direction == 1
            ? b.pos.x.compareTo(a.pos.x)
            : a.pos.x.compareTo(b.pos.x),
      );
    if (defenders.isEmpty) {
      return null;
    }

    final lineX = defenders.length > 1
        ? defenders[1].pos.x
        : defenders.first.pos.x;
    final passStart = ball.pos.copy();
    final passDirection = ball.vel.normalized(
      receiver == null
          ? Vec2(direction.toDouble(), 0)
          : receiver.pos - passer.pos,
    );

    PlayerGame? offender;
    var bestScore = -999999.0;
    for (final candidate in attackingTeam.players) {
      if (candidate == passer || candidate.isGoalkeeper) {
        continue;
      }
      if (!_isInOpponentHalf(candidate, direction)) {
        continue;
      }
      if (!_isAheadOfBall(candidate, passStart, direction)) {
        continue;
      }
      if (!_isBeyondSecondLast(candidate, lineX, direction)) {
        continue;
      }

      final intended = candidate == receiver;
      final pathDistance = _distanceToPassPath(
        candidate.pos,
        passStart,
        passDirection,
        highPass ? 620 : 430,
      );
      final closeToLane = pathDistance < (highPass ? 92 : 58);
      final closeToBall = candidate.pos.distanceTo(ball.pos) < 92;
      if (!intended && !closeToLane && !closeToBall) {
        continue;
      }

      final involvementScore =
          (intended ? 1000.0 : 0.0) +
          (highPass ? 100.0 : 55.0) -
          pathDistance +
          _goalwardDistance(candidate, passStart, direction) * 0.16;
      if (involvementScore > bestScore) {
        bestScore = involvementScore;
        offender = candidate;
      }
    }

    if (offender == null) {
      return null;
    }

    final kind = offender == receiver
        ? 'Aktif ofsayt'
        : highPass
        ? 'Yuksek pasta ofsayt'
        : 'Oyuna mudahale ofsayti';
    return OffsideCandidate(
      offender: offender,
      createdMinute: minute,
      event: OffsideEvent(
        attackingTeam: attackingTeam.id,
        offenderName: offender.profile.name,
        kind: kind,
        minute: minute.ceil(),
        lineX: lineX,
        ballPos: passStart,
        offenderPos: offender.pos.copy(),
      ),
    );
  }

  OffsideCandidate? evaluatePassFifa({
    required TeamGame attackingTeam,
    required TeamGame defendingTeam,
    required PlayerGame passer,
    required PlayerGame? receiver,
    required BallGame ball,
    required double minute,
    required bool highPass,
  }) {
    return evaluatePass(
      attackingTeam: attackingTeam,
      defendingTeam: defendingTeam,
      passer: passer,
      receiver: receiver,
      ball: ball,
      minute: minute,
      highPass: highPass,
    );
  }

  bool _isInOpponentHalf(PlayerGame player, int direction) {
    return direction == 1
        ? player.pos.x > GameConstants.virtualWidth / 2 + 1
        : player.pos.x < GameConstants.virtualWidth / 2 - 1;
  }

  bool _isAheadOfBall(PlayerGame player, Vec2 ballPos, int direction) {
    return direction == 1
        ? player.pos.x > ballPos.x + 3
        : player.pos.x < ballPos.x - 3;
  }

  bool _isBeyondSecondLast(PlayerGame player, double lineX, int direction) {
    return direction == 1 ? player.pos.x > lineX + 2 : player.pos.x < lineX - 2;
  }

  double _goalwardDistance(PlayerGame player, Vec2 ballPos, int direction) {
    return (player.pos.x - ballPos.x) * direction;
  }

  double _distanceToPassPath(
    Vec2 point,
    Vec2 start,
    Vec2 direction,
    double maxProjection,
  ) {
    final toPoint = point - start;
    final projection = toPoint
        .dot(direction)
        .clamp(0, maxProjection)
        .toDouble();
    final closest = start + direction * projection;
    return point.distanceTo(closest);
  }
}
