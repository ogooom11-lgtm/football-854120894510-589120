import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/config/game_constants.dart';

/// Draws a realistic football pitch: alternating mowing stripes, all
/// standard field lines (boundaries, halfway line, centre circle, penalty
/// areas, six-yard boxes, penalty spots, penalty arcs, corner arcs) and
/// goal frames with a simple net.
class FieldPainter {
  const FieldPainter();

  void paint(Canvas canvas) {
    final width = GameConstants.virtualWidth;
    final height = GameConstants.virtualHeight;
    final midX = width / 2;
    final midY = height / 2;

    // --- Grass base -----------------------------------------------------
    final grassBase = Paint()..color = const Color(0xff2e9e44);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      grassBase,
    );
    // Vertical mowing stripes (alternating lighter/darker green).
    final stripeDark = Paint()..color = const Color(0xff2a9340);
    const stripeWidth = 72.0;
    for (var x = 0.0; x < width; x += stripeWidth * 2) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, stripeWidth, height),
        stripeDark,
      );
    }
    // Slight horizontal bands for a richer grass texture.
    final bandPaint = Paint()..color = Colors.white.withValues(alpha: 0.025);
    for (var y = 0.0; y < height; y += 130) {
      canvas.drawRect(
        Rect.fromLTWH(0, y, width, 65),
        bandPaint,
      );
    }
    // Radial vignette so the edges look deeper, like a real broadcast.
    final vignette = Paint()
      ..shader = RadialGradient(
        radius: 0.95,
        colors: [
          Colors.transparent,
          Colors.transparent,
          Colors.black.withValues(alpha: 0.42),
        ],
        stops: const [0.55, 0.82, 1.0],
      ).createShader(
        Rect.fromLTWH(0, 0, width, height),
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), vignette);

    // --- Lines ----------------------------------------------------------
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4;
    final thinLine = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    final spotPaint = Paint()..color = Colors.white;

    final pitch = Rect.fromLTRB(
      GameConstants.leftBound,
      GameConstants.topBound,
      GameConstants.rightBound,
      GameConstants.bottomBound,
    );

    // Boundary + halfway line.
    canvas.drawRect(pitch, line);
    canvas.drawLine(
      Offset(midX, GameConstants.topBound),
      Offset(midX, GameConstants.bottomBound),
      line,
    );

    // Centre circle + centre spot.
    canvas.drawCircle(Offset(midX, midY), 62, line);
    canvas.drawCircle(Offset(midX, midY), 4, spotPaint);

    // Corner arcs (quarter circles at each corner).
    const cornerRadius = 18.0;
    for (final corner in [
      (Offset(GameConstants.leftBound, GameConstants.topBound), 0.0),
      (
        Offset(GameConstants.rightBound, GameConstants.topBound),
        math.pi / 2,
      ),
      (
        Offset(GameConstants.leftBound, GameConstants.bottomBound),
        -math.pi / 2,
      ),
      (
        Offset(GameConstants.rightBound, GameConstants.bottomBound),
        math.pi,
      ),
    ]) {
      canvas.drawArc(
        Rect.fromCircle(center: corner.$1, radius: cornerRadius * 2),
        corner.$2,
        math.pi / 2,
        false,
        thinLine,
      );
    }

    _drawPenaltyAreas(canvas, line, thinLine, spotPaint);
    _drawGoals(canvas);
  }

  void _drawPenaltyAreas(
    Canvas canvas,
    Paint line,
    Paint thinLine,
    Paint spotPaint,
  ) {
    const boxWidth = 132.0;
    const boxHeight = 240.0;
    const smallWidth = 48.0;
    const smallHeight = 125.0;
    final midY = GameConstants.virtualHeight / 2;
    final left = GameConstants.leftBound;
    final right = GameConstants.rightBound;
    const spotDistance = 92.0;
    // Penalty arc radius (like the real 9.15 m D): the arc is the part of
    // the circle that bulges OUT of the penalty box, centred on the spot.
    const arcRadius = 73.0;
    // Half-angle between the goal-line direction and the box edge.
    final arcHalfAngle = math.acos(
      ((boxWidth - spotDistance) / arcRadius).clamp(-1.0, 1.0),
    );

    for (final side in [left, right]) {
      final isLeft = side == left;
      final boxLeft = isLeft ? side : side - boxWidth;
      final smallLeft = isLeft ? side : side - smallWidth;

      // Penalty area (big box).
      canvas.drawRect(
        Rect.fromLTWH(boxLeft, midY - boxHeight / 2, boxWidth, boxHeight),
        line,
      );
      // Six-yard box.
      canvas.drawRect(
        Rect.fromLTWH(
          smallLeft,
          midY - smallHeight / 2,
          smallWidth,
          smallHeight,
        ),
        thinLine,
      );
      // Penalty spot.
      final spotX = isLeft ? side + spotDistance : side - spotDistance;
      canvas.drawCircle(Offset(spotX, midY), 3.4, spotPaint);
      // Penalty arc: only the bulge outside the penalty area is drawn.
      // Left side bulges toward the pitch (angle 0 = right/positive x),
      // right side bulges toward the pitch as well (angle pi = left).
      final arcRect = Rect.fromCircle(
        center: Offset(spotX, midY),
        radius: arcRadius,
      );
      final startAngle = isLeft ? -arcHalfAngle : math.pi - arcHalfAngle;
      canvas.drawArc(
        arcRect,
        startAngle,
        arcHalfAngle * 2,
        false,
        thinLine,
      );
    }
  }

  void _drawGoals(Canvas canvas) {
    final top = GameConstants.virtualHeight / 2 - GameConstants.goalPixelHeight / 2;
    final bottom = GameConstants.virtualHeight / 2 + GameConstants.goalPixelHeight / 2;
    final left = GameConstants.leftBound;
    final right = GameConstants.rightBound;
    final depth = GameConstants.goalDepth;

    final post = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6;
    final net = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    for (final isLeft in [true, false]) {
      final x = isLeft ? left : right;
      final backX = isLeft ? left - depth : right + depth;
      // Goal frame (posts + crossbar).
      canvas.drawLine(Offset(x, top), Offset(backX, top), post);
      canvas.drawLine(Offset(x, bottom), Offset(backX, bottom), post);
      canvas.drawLine(Offset(backX, top), Offset(backX, bottom), post);
      canvas.drawLine(Offset(x, top), Offset(x, bottom), post);
      // Simple net grid inside the goal.
      for (var y = top + 8; y < bottom - 2; y += 12) {
        canvas.drawLine(Offset(x, y), Offset(backX, y), net);
      }
      for (var gx = x; (isLeft ? gx > backX : gx < backX);) {
        canvas.drawLine(Offset(gx, top), Offset(gx, bottom), net);
        gx += isLeft ? -8 : 8;
      }
    }
  }
}
