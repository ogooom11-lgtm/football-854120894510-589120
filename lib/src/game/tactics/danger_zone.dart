import 'dart:math' as math;

import '../config/game_constants.dart';
import '../enums/team_id.dart';
import '../math/vec2.dart';

/// Danger zoning of the pitch (plan item 13): the space is split into safe,
/// medium, dangerous and critical areas around a team's own goal. The closer
/// the ball comes to the goal, the higher the priority of protecting the
/// zone, stopping the player and intercepting the pass.
enum DangerZone {
  safe,
  medium,
  dangerous,
  critical,
}

extension DangerZoneInfo on DangerZone {
  /// Continuous protection weight used by the movement pipeline.
  double get weight => switch (this) {
        DangerZone.safe => 0.00,
        DangerZone.medium => 0.33,
        DangerZone.dangerous => 0.66,
        DangerZone.critical => 1.00,
      };

  bool get isHot => this == DangerZone.dangerous || this == DangerZone.critical;
}

class DangerMapper {
  const DangerMapper();

  /// Classifies [point] from the perspective of the team defending the goal
  /// on side [defendingSide]. Central proximity counts more than width:
  /// a ball at the corner flag is far less dangerous than one at the penalty
  /// spot, even at the same distance.
  DangerZone zoneFor(Vec2 point, TeamSide defendingSide) {
    final goalX = defendingSide == TeamSide.left
        ? GameConstants.leftBound
        : GameConstants.rightBound;
    final goalCenter = Vec2(goalX, GameConstants.virtualHeight / 2);
    final distance = point.distanceTo(goalCenter);
    final centrality = 1.0 -
        ((point.y - GameConstants.virtualHeight / 2) /
                (GameConstants.pitchHeight / 2))
            .abs()
            .clamp(0.0, 1.0);
    final inBox = _inPenaltyBox(point, defendingSide);

    // Distance term, steepened so only genuinely close balls score high.
    final raw =
        (1.0 - distance / (GameConstants.pitchWidth * 1.1)).clamp(0.0, 1.0);
    final proximity = math.pow(raw, 1.6).toDouble();
    final threat = proximity * 0.72 + centrality * 0.28 + (inBox ? 0.34 : 0);

    if ((inBox && distance < GameConstants.pitchWidth * 0.16) ||
        threat >= 0.86) {
      return DangerZone.critical;
    }
    if (threat >= 0.72) {
      return DangerZone.dangerous;
    }
    if (threat >= 0.36) {
      return DangerZone.medium;
    }
    return DangerZone.safe;
  }

  bool _inPenaltyBox(Vec2 point, TeamSide defendingSide) {
    // Matches MatchEngine.isInPenaltyBox dimensions.
    const boxDepth = 135.0;
    const boxHalfWidth = 130.0;
    final insideDepth = defendingSide == TeamSide.left
        ? point.x < GameConstants.leftBound + boxDepth
        : point.x > GameConstants.rightBound - boxDepth;
    final insideWidth =
        (point.y - GameConstants.virtualHeight / 2).abs() < boxHalfWidth;
    return insideDepth && insideWidth;
  }
}
