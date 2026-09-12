import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/config/game_constants.dart';
import '../game/logic/match_engine.dart';
import '../game/models/player_game.dart';
import 'field_painter.dart';
import 'player_painter.dart';

class GamePainter extends CustomPainter {
  GamePainter(
    this.engine, {
    this.replayZoom = 1.0,
    this.showGoalkeeperDebug = false,
  });

  final MatchEngine engine;
  final double replayZoom;
  final bool showGoalkeeperDebug;
  final FieldPainter _fieldPainter = const FieldPainter();
  final PlayerPainter _playerPainter = const PlayerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / GameConstants.virtualWidth,
      size.height / GameConstants.virtualHeight,
    );
    final dx = (size.width - GameConstants.virtualWidth * scale) / 2;
    final dy = (size.height - GameConstants.virtualHeight * scale) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    final replay = engine.currentReplayFrame;
    canvas.save();
    if (replay != null && replayZoom > 1.0) {
      canvas.translate(
        GameConstants.virtualWidth / 2,
        GameConstants.virtualHeight / 2,
      );
      canvas.scale(replayZoom);
      canvas.translate(-replay.ballX, -replay.ballY);
    }

    _fieldPainter.paint(canvas);
    _drawOffside(canvas);
    for (final player in engine.blueTeam.players) {
      if (player.isSentOff) continue;
      final frame = replay?.players.where((item) => item.id == player.id);
      _playerPainter.paint(
        canvas,
        player,
        engine.blueTeam.color,
        position: frame == null || frame.isEmpty
            ? null
            : Offset(frame.first.x, frame.first.y),
        showControlledName: replay == null,
        jerseyKit: engine.blueTeam.jerseyKit,
        goalkeeperKit: engine.blueTeam.goalkeeperKit,
      );
    }
    for (final player in engine.redTeam.players) {
      if (player.isSentOff) continue;
      final frame = replay?.players.where((item) => item.id == player.id);
      _playerPainter.paint(
        canvas,
        player,
        engine.redTeam.color,
        position: frame == null || frame.isEmpty
            ? null
            : Offset(frame.first.x, frame.first.y),
        showControlledName: replay == null,
        jerseyKit: engine.redTeam.jerseyKit,
        goalkeeperKit: engine.redTeam.goalkeeperKit,
      );
    }
    _drawBall(canvas);
    if (showGoalkeeperDebug && replay == null) {
      _drawGoalkeeperDebug(canvas, engine.blueTeam.goalkeeper);
      _drawGoalkeeperDebug(canvas, engine.redTeam.goalkeeper);
    }
    canvas.restore();

    _drawHeader(canvas);
    if (replay != null) {
      _drawReplayStamp(canvas, replay.minute);
    }

    canvas.restore();
  }

  void _drawGoalkeeperDebug(Canvas canvas, PlayerGame keeper) {
    final debug = keeper.goalkeeperDebug;
    final impact = debug.predictedImpact;
    canvas.drawCircle(
      keeper.pos.toOffset(),
      debug.reachRadius,
      Paint()
        ..color = const Color(0xff40c4ff).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    if (impact == null) return;
    canvas.drawLine(
      engine.ball.pos.toOffset(),
      impact.toOffset(),
      Paint()
        ..color = const Color(0xffffab40).withValues(alpha: 0.80)
        ..strokeWidth = 1.5,
    );
    canvas.drawLine(
      keeper.pos.toOffset(),
      impact.toOffset(),
      Paint()
        ..color = const Color(0xff40c4ff).withValues(alpha: 0.90)
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      impact.toOffset(),
      7,
      Paint()
        ..color = const Color(0xffffab40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _drawHeader(Canvas canvas) {
    _text(
      canvas,
      '${engine.blueTeam.name}  ${engine.blueTeam.score} - ${engine.redTeam.score}  ${engine.redTeam.name}',
      const Offset(GameConstants.virtualWidth / 2, 18),
      22,
      Colors.white,
      FontWeight.w800,
    );
    _text(
      canvas,
      '${engine.periodTitle}  ${engine.clockText}',
      const Offset(GameConstants.virtualWidth / 2, 43),
      15,
      Colors.white70,
      FontWeight.w700,
    );
  }

  void _drawBall(Canvas canvas) {
    final ball = engine.ball;
    final replay = engine.currentReplayFrame;
    final ballX = replay?.ballX ?? ball.pos.x;
    final ballY = replay?.ballY ?? ball.pos.y;
    final height = replay?.ballHeight ?? ball.heightMeters;
    final shadowRadius = GameConstants.ballRadius + height * 2.2;
    canvas.drawCircle(
      Offset(ballX, ballY) + Offset(0, 2 + height * 2),
      shadowRadius,
      Paint()..color = Colors.black.withValues(alpha: 0.20),
    );
    canvas.drawCircle(
      Offset(ballX, ballY),
      GameConstants.ballRadius,
      Paint()..color = const Color(0xffffdc2e),
    );
    canvas.drawCircle(
      Offset(ballX, ballY),
      GameConstants.ballRadius,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    if (height > 0.06) {
      _text(
        canvas,
        height.toStringAsFixed(2),
        Offset(ballX, ballY - 24),
        13,
        Colors.white,
        FontWeight.w800,
      );
    }
  }

  void _drawReplayStamp(Canvas canvas, double minute) {
    _text(
      canvas,
      'VAR ${minute.toStringAsFixed(1)}',
      const Offset(GameConstants.virtualWidth - 90, 42),
      18,
      const Color(0xffffd34d),
      FontWeight.w900,
    );
  }

  void _drawOffside(Canvas canvas) {
    final event = engine.currentOffside;
    if (event == null) {
      return;
    }
    // FIFA-style semi-automated offside display
    // Red offside line
    final redLine = Paint()
      ..color = const Color(0xffff3b30)
      ..strokeWidth = 3;
    // Blue defender line  
    final blueLine = Paint()
      ..color = const Color(0xff2196f3)
      ..strokeWidth = 3;

    // Draw red offside line (solid)
    canvas.drawLine(
      Offset(event.lineX, GameConstants.topBound),
      Offset(event.lineX, GameConstants.bottomBound),
      redLine,
    );

    // Draw blue defender line next to offside line
    final defenderX = event.lineX + (engine.teamById(event.attackingTeam).attackDirection * -4);
    canvas.drawLine(
      Offset(defenderX, GameConstants.topBound),
      Offset(defenderX, GameConstants.bottomBound),
      blueLine,
    );

    // Highlight offending player
    canvas.drawCircle(
      event.offenderPos.toOffset(),
      22,
      Paint()
        ..color = const Color(0xffff3b30).withValues(alpha: 0.22)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      event.offenderPos.toOffset(),
      22,
      Paint()
        ..color = const Color(0xffff3b30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Show distance text
    final attackingTeam = engine.teamById(event.attackingTeam);
    final offender = attackingTeam.players.firstWhere(
      (p) => p.profile.name == event.offenderName,
      orElse: () => attackingTeam.players.first,
    );
    final offsideDist = (offender.pos.x - event.lineX).abs();
    _text(
      canvas,
      'Ofsayt: ${offsideDist.toStringAsFixed(1)}px',
      Offset(event.lineX + 8, GameConstants.topBound + 18),
      14,
      const Color(0xffff3b30),
      FontWeight.w900,
    );
  }

  void _text(
    Canvas canvas,
    String value,
    Offset center,
    double size,
    Color color,
    FontWeight weight,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: GameConstants.virtualWidth - 160);
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}
