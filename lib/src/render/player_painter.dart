import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/models/jersey_kit.dart';
import '../game/models/player_game.dart';

class PlayerPainter {
  const PlayerPainter();

  void paint(
    Canvas canvas,
    PlayerGame player,
    Color color, {
    Offset? position,
    bool showControlledName = true,
    JerseyKit? jerseyKit,
    JerseyKit? goalkeeperKit,
  }) {
    final isKeeper = player.isGoalkeeper;
    final playerColor = isKeeper && goalkeeperKit != null
        ? goalkeeperKit.shirtColor
        : jerseyKit?.shirtColor ?? color;
    final shortsColor = jerseyKit?.shortsColor ?? color;
    final numberClr = isKeeper && goalkeeperKit != null
        ? goalkeeperKit.numberColor
        : jerseyKit?.numberColor ?? Colors.white;
    final body = Paint()..color = playerColor;
    final border = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final rawCenter = position ?? player.pos.toOffset();
    final jumpDuration = player.isGoalkeeper ? 0.62 : 0.48;
    final jumpPhase = player.jumpAnimationTimer <= 0
        ? 0.0
        : math.sin(
            (1 -
                    (player.jumpAnimationTimer / jumpDuration).clamp(0.0, 1.0)) *
                math.pi,
          );
    final center = rawCenter.translate(0, -jumpPhase * (player.isGoalkeeper ? 13 : 9));
    if (player.isGoalkeeper && player.keeperGroundTimer > 0) {
      final rect = Rect.fromCenter(
        center: center,
        width: player.radius * 2.9,
        height: player.radius * 1.15,
      );
      canvas.drawOval(rect, body);
      canvas.drawOval(rect, border);
    } else if (player.isGoalkeeper && jumpPhase > 0.02) {
      // While diving/jumping the keeper stretches vertically — a narrow,
      // tall body shape — instead of staying a plain circle.
      final stretch = 0.55 + jumpPhase * 0.45;
      final rect = Rect.fromCenter(
        center: center.translate(0, -player.radius * 0.55),
        width: player.radius * (2.1 - jumpPhase * 0.5),
        height: player.radius * (2.05 + jumpPhase * 1.1),
      );
      canvas.drawOval(rect, body);
      canvas.drawOval(rect, border);
      if (stretch > 0.85) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: center.translate(0, player.radius * 1.05),
              width: player.radius * 1.1,
              height: player.radius * 0.45,
            ),
            const Radius.circular(2),
          ),
          Paint()..color = shortsColor,
        );
      }
    } else {
      canvas.drawCircle(center, player.radius, body);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center.translate(0, player.radius * 0.45),
            width: player.radius * 1.35,
            height: player.radius * 0.55,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = shortsColor,
      );
      canvas.drawCircle(center, player.radius, border);
    }
    if (player.isGoalkeeper) {
      _keeperCue(canvas, player, center);
    }
    _fatigueCue(canvas, player, center);
    if (player.yellowCardsThisMatch > 0) {
      final cardRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          center.dx - player.radius - 7,
          center.dy - player.radius - 13,
          7,
          10,
        ),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(cardRect, Paint()..color = const Color(0xffffd34d));
    }
    if (player.jumpBoostMeters > 0) {
      canvas.drawCircle(
        center,
        player.radius + 5,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    if (player.controlled && showControlledName) {
      canvas.drawCircle(
        center,
        player.radius + 7,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    _text(
      canvas,
      player.number.toString(),
      center,
      11,
      numberClr,
      FontWeight.w800,
    );
    if (player.controlled) {
      _text(
        canvas,
        player.profile.name,
        Offset(center.dx, center.dy - 26),
        10,
        Colors.white,
        FontWeight.w700,
      );
    }
  }

  void _fatigueCue(Canvas canvas, PlayerGame player, Offset center) {
    if (player.stamina > 0.42) {
      return;
    }
    final severity = ((0.42 - player.stamina) / 0.42).clamp(0.0, 1.0);
    final color = severity > 0.55
        ? const Color(0xffff4d4d)
        : const Color(0xffffc857);
    final iconCenter = center.translate(player.radius + 7, -player.radius - 8);
    final battery = RRect.fromRectAndRadius(
      Rect.fromCenter(center: iconCenter, width: 13, height: 8),
      const Radius.circular(2),
    );
    final cap = Rect.fromCenter(
      center: iconCenter.translate(7.3, 0),
      width: 2.4,
      height: 4.6,
    );
    canvas.drawRRect(
      battery,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.72)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      battery,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.drawRect(cap, Paint()..color = color);
    final fillWidth = 9.0 * player.stamina.clamp(0.08, 0.42) / 0.42;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(iconCenter.dx - 5, iconCenter.dy - 2.5, fillWidth, 5),
        const Radius.circular(1.2),
      ),
      Paint()..color = color.withValues(alpha: 0.82),
    );
  }

  void _keeperCue(Canvas canvas, PlayerGame player, Offset center) {
    if (player.keeperGroundTimer > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: player.radius + 8),
        -0.7,
        1.4,
        false,
        Paint()
          ..color = const Color(0xff8bd3ff)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
      final groundCue =
          player.jumpAnimationTimer <= 0.10 || player.keeperState == 'yerde'
          ? 'YERDE'
          : player.keeperState == 'kurtaris'
          ? 'KURTARIS'
          : 'ATLAYIS';
      _text(
        canvas,
        groundCue,
        center.translate(0, -24),
        8,
        const Color(0xffbde8ff),
        FontWeight.w900,
      );
      return;
    }
    if (player.keeperState == 'top elde') {
      final heldBall = center.translate(0, -player.radius - 5);
      canvas.drawCircle(heldBall, 4.2, Paint()..color = Colors.white);
      canvas.drawCircle(
        heldBall,
        4.2,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      _text(
        canvas,
        'TOP ELDE',
        center.translate(0, -27),
        8,
        const Color(0xffbde8ff),
        FontWeight.w900,
      );
    }
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
        style: TextStyle(fontSize: size, color: color, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }
}
