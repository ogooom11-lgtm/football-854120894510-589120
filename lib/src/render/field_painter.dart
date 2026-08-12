import 'package:flutter/material.dart';

import '../game/config/game_constants.dart';

class FieldPainter {
  const FieldPainter();

  void paint(Canvas canvas) {
    final grass = Paint()..color = const Color(0xff087a36);
    final stripe = Paint()..color = const Color(0xff066d31);
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final thinLine = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    final goalPaint = Paint()
      ..color = const Color(0xffd7dde2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, GameConstants.virtualWidth, GameConstants.virtualHeight),
      grass,
    );
    for (var x = 0.0; x < GameConstants.virtualWidth; x += 140) {
      canvas.drawRect(
        Rect.fromLTWH(x, GameConstants.topBound, 70, GameConstants.pitchHeight),
        stripe,
      );
    }

    final pitch = Rect.fromLTRB(
      GameConstants.leftBound,
      GameConstants.topBound,
      GameConstants.rightBound,
      GameConstants.bottomBound,
    );
    canvas.drawRect(pitch, line);
    canvas.drawLine(
      const Offset(GameConstants.virtualWidth / 2, GameConstants.topBound),
      const Offset(GameConstants.virtualWidth / 2, GameConstants.bottomBound),
      line,
    );
    canvas.drawCircle(
      const Offset(GameConstants.virtualWidth / 2, GameConstants.virtualHeight / 2),
      60,
      line,
    );
    canvas.drawCircle(
      const Offset(GameConstants.virtualWidth / 2, GameConstants.virtualHeight / 2),
      4,
      Paint()..color = Colors.white,
    );

    _drawPenaltyBoxes(canvas, line, thinLine);
    _drawGoals(canvas, goalPaint);
  }

  void _drawPenaltyBoxes(Canvas canvas, Paint line, Paint thinLine) {
    const boxWidth = 120.0;
    const boxHeight = 230.0;
    const smallWidth = 45.0;
    const smallHeight = 120.0;
    final midY = GameConstants.virtualHeight / 2;
    canvas.drawRect(
      Rect.fromLTWH(
        GameConstants.leftBound,
        midY - boxHeight / 2,
        boxWidth,
        boxHeight,
      ),
      line,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        GameConstants.rightBound - boxWidth,
        midY - boxHeight / 2,
        boxWidth,
        boxHeight,
      ),
      line,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        GameConstants.leftBound,
        midY - smallHeight / 2,
        smallWidth,
        smallHeight,
      ),
      thinLine,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        GameConstants.rightBound - smallWidth,
        midY - smallHeight / 2,
        smallWidth,
        smallHeight,
      ),
      thinLine,
    );
    canvas.drawCircle(
      const Offset(GameConstants.leftBound + 88, GameConstants.virtualHeight / 2),
      3,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      const Offset(GameConstants.rightBound - 88, GameConstants.virtualHeight / 2),
      3,
      Paint()..color = Colors.white,
    );
  }

  void _drawGoals(Canvas canvas, Paint goalPaint) {
    final top = GameConstants.virtualHeight / 2 - GameConstants.goalPixelHeight / 2;
    final bottom = GameConstants.virtualHeight / 2 + GameConstants.goalPixelHeight / 2;
    canvas.drawLine(
      Offset(GameConstants.leftBound, top),
      Offset(GameConstants.leftBound - GameConstants.goalDepth, top),
      goalPaint,
    );
    canvas.drawLine(
      Offset(GameConstants.leftBound, bottom),
      Offset(GameConstants.leftBound - GameConstants.goalDepth, bottom),
      goalPaint,
    );
    canvas.drawLine(
      Offset(GameConstants.leftBound - GameConstants.goalDepth, top),
      Offset(GameConstants.leftBound - GameConstants.goalDepth, bottom),
      goalPaint,
    );
    canvas.drawLine(
      Offset(GameConstants.rightBound, top),
      Offset(GameConstants.rightBound + GameConstants.goalDepth, top),
      goalPaint,
    );
    canvas.drawLine(
      Offset(GameConstants.rightBound, bottom),
      Offset(GameConstants.rightBound + GameConstants.goalDepth, bottom),
      goalPaint,
    );
    canvas.drawLine(
      Offset(GameConstants.rightBound + GameConstants.goalDepth, top),
      Offset(GameConstants.rightBound + GameConstants.goalDepth, bottom),
      goalPaint,
    );
  }
}
