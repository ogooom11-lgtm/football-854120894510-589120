import 'dart:math' as math;

import '../config/game_constants.dart';
import '../enums/ai_play_style.dart';
import '../enums/player_role.dart';
import '../enums/team_id.dart';
import '../math/vec2.dart';
import '../models/formation.dart';
import '../models/player_game.dart';
import '../models/team_game.dart';
import '../models/tactics/shape_profile.dart';
import '../logic/match_engine.dart';
import 'danger_zone.dart';
import 'team_play_state.dart';
import 'team_shape_kind.dart';

/// Builds the per-team tactical context that drives every player's dynamic
/// target (plan item 29):
///
/// FORMATION → PLAYER ROLES → BASE POSITIONS → TEAM STATE → BALL LOCATION →
/// OPPONENT LOCATION → TEAM COMPACTNESS → TACTICAL STYLE → SCORE + TIME →
/// RISK LEVEL → PLAYER PRIORITY → DYNAMIC TARGET → PLAYER MOVEMENT.
///
/// The pipeline is re-evaluated every tick; nothing is cached between states,
/// so the team shape follows the ball, the opponent, the score and the clock
/// instead of frozen coordinates (plan items 22 and 28).
class TacticalEngine {
  const TacticalEngine();

  TacticalContext evaluate({
    required MatchEngine engine,
    required TeamGame team,
    required TeamPlayState playState,
    required TeamShapeKind shapeKind,
  }) {
    final style = engine.playStyleFor(team.id);
    final opponent = engine.opponentOf(team);
    final plan = formationPlan(team.formation);
    final profile = formationShapeProfile(team.formation);
    const dangerMapper = DangerMapper();

    final ballZone = dangerMapper.zoneFor(engine.ball.pos, team.side);
    final opponentBallZone = dangerMapper.zoneFor(
      engine.ball.pos,
      opponent.side,
    );
    final ballAdvance = advanceOf(engine.ball.pos, team);
    final scoreUrgency = scoreUrgencyFor(team, opponent, engine);
    final riskLevel = riskLevelFor(
      team,
      opponent,
      engine,
      style,
      ballZone,
      playState,
    );
    final compactness = measureCompactness(team);
    final targetCompactness = targetCompactnessFor(
      playState,
      style,
      scoreUrgency,
    );
    final lineHeight = lineHeightFor(
      playState,
      style,
      ballZone,
      scoreUrgency,
      riskLevel,
      ballAdvance,
    );
    final defensiveLineX = defensiveLineXFor(
      team,
      playState,
      lineHeight,
      ballZone,
      ballAdvance,
    );
    final offsideLineX = engine.offsideLineFor(team);
    final width = widthFor(playState, style, profile, scoreUrgency);
    final blockCenter = blockCenterOf(team);

    String? falseNineId;
    if (profile.interiorInterchange && playState.inPossession) {
      falseNineId = _designateFalseNine(team);
    }

    return TacticalContext._(
      engine: engine,
      team: team,
      playState: playState,
      shapeKind: shapeKind,
      style: style,
      plan: plan,
      profile: profile,
      ballZone: ballZone,
      opponentBallZone: opponentBallZone,
      scoreUrgency: scoreUrgency,
      riskLevel: riskLevel,
      compactness: compactness,
      targetCompactness: targetCompactness,
      lineHeight: lineHeight,
      defensiveLineX: defensiveLineX,
      offsideLineX: offsideLineX,
      width: width,
      blockCenter: blockCenter,
      falseNineId: falseNineId,
    );
  }

  // ---------------------------------------------------------------------
  // Score, time and risk (plan items 17 and 29)
  // ---------------------------------------------------------------------

  /// -1.0 when chasing the game, +1.0 when comfortably ahead.
  double scoreUrgencyFor(TeamGame team, TeamGame opponent, MatchEngine engine) {
    final diff = (team.score - opponent.score).toDouble();
    final lateGame =
        engine.minute >= 75 || engine.period.name.startsWith('extra');
    var urgency = (diff * 0.5).clamp(-1.0, 1.0).toDouble();
    if (lateGame) {
      // A late lead must be protected; a late deficit must be chased.
      urgency = urgency >= 0
          ? math.min(1.0, urgency + 0.35)
          : math.max(-1.0, urgency - 0.35);
    }
    return urgency;
  }

  double riskLevelFor(
    TeamGame team,
    TeamGame opponent,
    MatchEngine engine,
    AiPlayStyle style,
    DangerZone ballZone,
    TeamPlayState playState,
  ) {
    var risk = 0.34 + style.riskFactor * 0.30;
    final diff = team.score - opponent.score;
    if (diff > 0) {
      risk -= 0.11 * math.min(diff, 2);
    } else if (diff < 0) {
      risk += 0.13 * math.min(-diff, 2);
    }
    final lateGame =
        engine.minute >= 75 || engine.period.name.startsWith('extra');
    if (lateGame && diff < 0) {
      risk += 0.18;
    } else if (lateGame && diff > 0) {
      risk -= 0.15;
    }
    // No gambles while the own goal is under direct threat (plan item 13):
    // protecting the dangerous zone always outranks risking forward.
    if (playState.outOfPossession && ballZone.isHot) {
      risk = math.min(risk, 0.22);
    }
    return risk.clamp(0.05, 1.0).toDouble();
  }

  // ---------------------------------------------------------------------
  // Compactness (plan item 5)
  // ---------------------------------------------------------------------

  /// Current block tightness of the team (0 = fully stretched, 1 = fully
  /// compact). The team moves as one block: when the gaps between the lines
  /// grow too big the block pulls together, when it is too tight in
  /// possession the block expands.
  double measureCompactness(TeamGame team) {
    var defenders = 0, mids = 0, attackers = 0;
    var defSum = 0.0, midSum = 0.0, attSum = 0.0;
    var spreadSum = 0.0;
    var count = 0;
    for (final player in team.players) {
      if (player.isGoalkeeper || player.isSentOff) {
        continue;
      }
      final advance = advanceOf(player.pos, team);
      if (player.role.isDefender) {
        defSum += advance;
        defenders++;
      } else if (player.role.isMidfield) {
        midSum += advance;
        mids++;
      } else {
        attSum += advance;
        attackers++;
      }
      spreadSum += (player.pos.y - GameConstants.virtualHeight / 2).abs();
      count++;
    }
    if (count == 0) {
      return 0.5;
    }
    final defLine = defenders > 0 ? defSum / defenders : 0.2;
    final midLine = mids > 0 ? midSum / mids : (defLine + 0.2).clamp(0.0, 1.0);
    final attLine =
        attackers > 0 ? attSum / attackers : (midLine + 0.2).clamp(0.0, 1.0);
    final verticalGap = ((midLine - defLine) + (attLine - midLine)) / 2.0;
    final horizontalSpread =
        (spreadSum / count) / (GameConstants.pitchHeight / 2);
    final tightness =
        1.0 - (verticalGap * 0.62 + horizontalSpread * 0.38).clamp(0.0, 1.0);
    return tightness.toDouble();
  }

  double targetCompactnessFor(
    TeamPlayState playState,
    AiPlayStyle style,
    double scoreUrgency,
  ) {
    var target = playState.baseCompactness * style.compactnessBias;
    // A protected lead squeezes the block, a chased deficit stretches it a
    // little to find players between the lines (plan item 17).
    target -= scoreUrgency * 0.08;
    return target.clamp(0.18, 0.92).toDouble();
  }

  // ---------------------------------------------------------------------
  // Lines (plan items 9 and 10)
  // ---------------------------------------------------------------------

  /// The height of the whole block (fraction of pitch width from the own
  /// goal). The line advances when the danger is far, retreats when danger
  /// approaches and freezes deep when the opponent reaches the hot zones
  /// (plan item 9).
  double lineHeightFor(
    TeamPlayState playState,
    AiPlayStyle style,
    DangerZone ballZone,
    double scoreUrgency,
    double riskLevel,
    double ballAdvance,
  ) {
    var height = switch (playState) {
      TeamPlayState.possession => 0.40,
      TeamPlayState.attackingTransition => 0.42,
      TeamPlayState.organizedDefense => 0.30,
      TeamPlayState.defensiveTransition => 0.33,
      TeamPlayState.pressing => 0.44,
    };
    // The block follows the ball's depth.
    height += (ballAdvance - 0.5) * 0.34;
    // Style bias (defensive line factor around 1.0).
    height += (style.defensiveLineFactor - 1.0) * 0.16;
    // Danger, result and risk adjustments.
    height -= ballZone.weight * 0.16;
    height -= scoreUrgency * 0.07;
    height += (riskLevel - 0.4) * 0.10;
    return height.clamp(0.13, 0.62).toDouble();
  }

  /// The x coordinate the defensive line should hold right now (plan item 9).
  /// The line reads the ball, the attackers and the space behind: it never
  /// sits ahead of the danger and freezes deep when the opponent reaches the
  /// critical zone (plan items 12 and 13).
  double defensiveLineXFor(
    TeamGame team,
    TeamPlayState playState,
    double lineHeight,
    DangerZone ballZone,
    double ballAdvance,
  ) {
    final d = team.attackDirection;
    final ownGoalX = team.side == TeamSide.left
        ? GameConstants.leftBound
        : GameConstants.rightBound;
    var lineFraction = lineHeight;
    // The line never advances past the ball while defending.
    if (playState.outOfPossession) {
      lineFraction = math.min(lineFraction, ballAdvance + 0.10);
    }
    // In the critical zone the line is pinned: it holds and protects the
    // goal instead of stepping out.
    if (ballZone == DangerZone.critical) {
      lineFraction = math.min(lineFraction, 0.24);
    }
    lineFraction = lineFraction.clamp(0.10, 0.66).toDouble();
    return ownGoalX + d * GameConstants.pitchWidth * lineFraction;
  }

  double widthFor(
    TeamPlayState playState,
    AiPlayStyle style,
    FormationShapeProfile profile,
    double scoreUrgency,
  ) {
    var width = switch (playState) {
      TeamPlayState.possession => profile.attackingWidth,
      TeamPlayState.attackingTransition => (profile.attackingWidth + 1.0) / 2,
      TeamPlayState.organizedDefense => profile.defensiveWidth,
      TeamPlayState.defensiveTransition => profile.defensiveWidth,
      TeamPlayState.pressing => profile.pressingWidth,
    };
    width *= style.widthFactor;
    width -= scoreUrgency * 0.03;
    return width.clamp(0.55, 1.30).toDouble();
  }

  Vec2 blockCenterOf(TeamGame team) {
    var sumX = 0.0;
    var sumY = 0.0;
    var count = 0;
    for (final player in team.players) {
      if (player.isGoalkeeper || player.isSentOff) {
        continue;
      }
      sumX += player.pos.x;
      sumY += player.pos.y;
      count++;
    }
    if (count == 0) {
      return Vec2(
        GameConstants.virtualWidth / 2,
        GameConstants.virtualHeight / 2,
      );
    }
    return Vec2(sumX / count, sumY / count);
  }

  /// 4-6-0 (plan item 27): the most advanced interior player temporarily
  /// becomes the "striker zone" runner; his zone is covered by the nearest
  /// team-mate through the coverage system, so the striker zone exists as a
  /// behaviour, not as a fixed role.
  String? _designateFalseNine(TeamGame team) {
    PlayerGame? best;
    var bestScore = -1.0;
    for (final player in team.players) {
      if (player.isGoalkeeper ||
          player.isSentOff ||
          !(player.role == PlayerRole.attackingMidfielder ||
              player.role == PlayerRole.midfieldLeft ||
              player.role == PlayerRole.midfieldRight ||
              player.role == PlayerRole.defensiveMidfielder)) {
        continue;
      }
      final advance = advanceOf(player.pos, team);
      final central = 1.0 -
          ((player.pos.y - GameConstants.virtualHeight / 2) /
                  (GameConstants.pitchHeight / 2))
              .abs();
      final score = advance * 0.7 + central * 0.3;
      if (score > bestScore) {
        bestScore = score;
        best = player;
      }
    }
    return best?.id;
  }

  /// How advanced a point is for [team]: 0 = own goal line, 1 = opponent goal.
  double advanceOf(Vec2 point, TeamGame team) {
    final d = team.attackDirection;
    final ownGoalX = team.side == TeamSide.left
        ? GameConstants.leftBound
        : GameConstants.rightBound;
    return (((point.x - ownGoalX) * d) / GameConstants.pitchWidth)
        .clamp(0.0, 1.0)
        .toDouble();
  }
}

/// The full tactical picture of one team for the current tick. Player AI
/// reads this to compute its dynamic target; it is rebuilt every tick.
class TacticalContext {
  TacticalContext._({
    required this.engine,
    required this.team,
    required this.playState,
    required this.shapeKind,
    required this.style,
    required this.plan,
    required this.profile,
    required this.ballZone,
    required this.opponentBallZone,
    required this.scoreUrgency,
    required this.riskLevel,
    required this.compactness,
    required this.targetCompactness,
    required this.lineHeight,
    required this.defensiveLineX,
    required this.offsideLineX,
    required this.width,
    required this.blockCenter,
    required this.falseNineId,
  }) {
    for (var i = 0; i < team.players.length && i < plan.spots.length; i++) {
      _spotIndex[team.players[i].id] = i;
    }
  }

  final MatchEngine engine;
  final TeamGame team;
  final TeamPlayState playState;
  final TeamShapeKind shapeKind;
  final AiPlayStyle style;
  final FormationPlan plan;
  final FormationShapeProfile profile;
  final DangerZone ballZone;
  final DangerZone opponentBallZone;
  final double scoreUrgency;
  final double riskLevel;
  final double compactness;
  final double targetCompactness;
  final double lineHeight;
  final double defensiveLineX;
  final double offsideLineX;
  final double width;
  final Vec2 blockCenter;
  final String? falseNineId;

  final Map<String, int> _spotIndex = {};

  bool get inPossession => playState.inPossession;

  FormationSpot _spotOf(PlayerGame player) {
    final index = _spotIndex[player.id] ?? 0;
    return plan.spots[math.min(index, plan.spots.length - 1)];
  }

  // ---------------------------------------------------------------------
  // The anchor pipeline (plan items 1, 2, 24 and 29)
  // ---------------------------------------------------------------------

  /// The static formation anchor of the player (plan item 1: the formation
  /// decides where the player *starts*).
  Vec2 baseAnchor(PlayerGame player) {
    final spot = _spotOf(player);
    return TeamGame.pitchPoint(spot.x, spot.y, team.side);
  }

  /// The shape-morphed anchor: the same formation expressed as its current
  /// attacking / defensive / pressing / transition shape (plan item 4).
  Vec2 shapeAnchor(PlayerGame player) {
    final spot = _spotOf(player);
    final role = player.role;
    final group = role.group;
    final d = team.attackDirection;
    final ownGoalX = team.side == TeamSide.left
        ? GameConstants.leftBound
        : GameConstants.rightBound;

    var fx = spot.x;
    var fy = 0.5 + (spot.y - 0.5) * width;

    switch (shapeKind) {
      case TeamShapeKind.attacking:
        fx += profile.attackingLineHeight * _advanceFactor(group) * _riskShapeScale;
      case TeamShapeKind.defensive:
        fx -= profile.defensiveBlockDrop * _dropFactor(group);
      case TeamShapeKind.pressing:
        fx += profile.pressingLineHeight * _pressAdvanceFactor(group);
      case TeamShapeKind.transition:
        fx -= profile.transitionDrop * _dropFactor(group) * 0.85;
      case TeamShapeKind.base:
        break;
    }
    // Result and time lean the whole block (plan item 17): chasing a deficit
    // pushes the shape up, protecting a lead drops it a little.
    fx -= scoreUrgency * 0.05;

    fx = fx.clamp(0.02, 0.97).toDouble();
    fy = fy.clamp(0.06, 0.94).toDouble();
    return Vec2(
      ownGoalX + d * GameConstants.pitchWidth * fx,
      GameConstants.topBound + GameConstants.pitchHeight * fy,
    );
  }

  double get _riskShapeScale => 0.85 + riskLevel * 0.3;

  /// Who advances the most when the team attacks: fullbacks join the
  /// midfield, the holding midfielder protects behind (plan item 25).
  double _advanceFactor(RoleGroup group) => switch (group) {
        RoleGroup.keeper => 0.0,
        RoleGroup.centralDefence => 0.35,
        RoleGroup.fullBack => 1.00,
        RoleGroup.holdingMidfield => 0.18,
        RoleGroup.centralMidfield => 0.60,
        RoleGroup.attackingMidfield => 0.55,
        RoleGroup.wing => 0.35,
        RoleGroup.striker => 0.20,
      };

  /// Who drops the deepest when defending: wide forwards fall back toward
  /// the midfield line (4-3-3 → 4-5-1, plan item 25), the striker stays
  /// higher as the lone outlet.
  double _dropFactor(RoleGroup group) => switch (group) {
        RoleGroup.keeper => 0.05,
        RoleGroup.centralDefence => 0.30,
        RoleGroup.fullBack => 0.45,
        RoleGroup.holdingMidfield => 0.50,
        RoleGroup.centralMidfield => 0.75,
        RoleGroup.attackingMidfield => 0.90,
        RoleGroup.wing => profile.wingsDropInDefense ? 1.8 : 0.55,
        RoleGroup.striker => 0.55,
      };

  double _pressAdvanceFactor(RoleGroup group) => switch (group) {
        RoleGroup.keeper => 0.0,
        RoleGroup.centralDefence => 0.50,
        RoleGroup.fullBack => 0.90,
        RoleGroup.holdingMidfield => 0.40,
        RoleGroup.centralMidfield => 0.80,
        RoleGroup.attackingMidfield => 0.90,
        RoleGroup.wing => 0.85,
        RoleGroup.striker => 1.00,
      };

  /// The dynamic target (plan item 28): the formation gives the starting
  /// point, everything else — the ball, the opponent, the compactness, the
  /// style, the score, the clock and the risk — decides where the player
  /// should be *now*.
  Vec2 dynamicAnchor(PlayerGame player) {
    final target = shapeAnchor(player);
    final role = player.role;
    final ball = engine.ball.pos;

    // ---- Ball location (plan items 6 and 7) --------------------------
    // The team leans toward the ball's side; the block stays connected to
    // the ball's depth. These are continuous pulls, never fixed offsets.
    final tiltScale = switch (playState) {
      TeamPlayState.possession => 0.34,
      TeamPlayState.attackingTransition => 0.42,
      TeamPlayState.organizedDefense => 0.52,
      TeamPlayState.defensiveTransition => 0.50,
      TeamPlayState.pressing => 0.56,
    };
    // Freedom (plan item 21): the libero and the playmaker lean toward the
    // ball the most, centre backs barely leave their post.
    final tilt = role.ballSideTilt * tiltScale * (0.75 + role.movementFreedom * 0.5);
    target.y += (ball.y - target.y) * tilt;
    target.x += (ball.x - target.x) * role.ballSideTilt * 0.26;

    // ---- Compactness (plan item 5) ------------------------------------
    // Move the block as a unit toward its target tightness.
    final gapError = compactness - targetCompactness;
    target.x += (target.x - blockCenter.x) * gapError * 0.40;
    target.y +=
        (target.y - GameConstants.virtualHeight / 2) * gapError * 0.30;

    // ---- Opponent location: defensive line (plan item 9) --------------
    if (role.group == RoleGroup.centralDefence) {
      final lineFraction = _fractionFromX(defensiveLineX);
      final fx = math.min(_fractionFromX(target.x), lineFraction);
      target.x = _xFromFraction(fx);
    } else if (role.group == RoleGroup.fullBack && !inPossession) {
      final lineFraction = _fractionFromX(defensiveLineX);
      final fx = math.min(_fractionFromX(target.x), lineFraction + 0.08);
      target.x = _xFromFraction(fx);
    }

    // ---- Offside line (plan item 10) ----------------------------------
    // Attackers own the space next to the opponent's defensive line: when
    // the line advances they retreat, when it drops they go with it.
    if (inPossession &&
        (role.isAttacker || role == PlayerRole.attackingMidfielder)) {
      final lineFraction =
          _fractionFromX(offsideLineX) - 8 / GameConstants.pitchWidth;
      if (lineFraction > role.minAdvance) {
        final fx = math.min(_fractionFromX(target.x), lineFraction);
        target.x = _xFromFraction(fx);
      }
    }

    // ---- 4-6-0 false nine (plan item 27) -------------------------------
    if (profile.interiorInterchange &&
        inPossession &&
        falseNineId == player.id &&
        role.isMidfield) {
      final lineFraction =
          (_fractionFromX(offsideLineX) - 10 / GameConstants.pitchWidth)
              .clamp(0.34, 0.92)
              .toDouble();
      target.x = _xFromFraction(lineFraction);
      target.y = GameConstants.virtualHeight / 2 +
          (ball.y - GameConstants.virtualHeight / 2) * 0.22;
    }

    // ---- Zone clamp (plan item 2) --------------------------------------
    final zoneMargin = 0.02 + riskLevel * 0.03;
    final minFraction = math.max(0.0, role.minAdvance - zoneMargin * 0.5);
    final maxFraction = math.min(0.97, role.maxAdvance + zoneMargin);
    final clamped =
        _fractionFromX(target.x).clamp(minFraction, maxFraction).toDouble();
    target.x = _xFromFraction(clamped);
    target.y = target.y
        .clamp(GameConstants.topBound + 22, GameConstants.bottomBound - 22)
        .toDouble();
    return target;
  }

  double _fractionFromX(double x) {
    final d = team.attackDirection;
    final ownGoalX = team.side == TeamSide.left
        ? GameConstants.leftBound
        : GameConstants.rightBound;
    return (((x - ownGoalX) * d) / GameConstants.pitchWidth)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double _xFromFraction(double fraction) {
    final d = team.attackDirection;
    final ownGoalX = team.side == TeamSide.left
        ? GameConstants.leftBound
        : GameConstants.rightBound;
    return ownGoalX + d * GameConstants.pitchWidth * fraction;
  }
}
