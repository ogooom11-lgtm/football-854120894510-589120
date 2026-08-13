import '../config/game_constants.dart';
import '../enums/kick_type.dart';
import '../math/vec2.dart';
import 'player_game.dart';
import 'shooting.dart';

class BallGame {
  BallGame({required this.pos});

  Vec2 pos;
  Vec2 vel = Vec2.zero();
  double heightMeters = 0;
  double verticalVelocity = 0;
  PlayerGame? owner;
  PlayerGame? lastTouch;
  PlayerGame? lastPasser;
  PlayerGame? potentialAssister;
  PlayerGame? intendedReceiver;
  KickType? lastKickType;
  bool lastPassWasHigh = false;
  bool hasBouncedSinceKick = false;
  bool goalLineMissCommitted = false;
  bool dippingFreeKick = false;
  double curve = 0;
  double spin = 0;
  ShotType? shotType;

  bool get isOnGround => heightMeters <= 0.04;

  void attachTo(PlayerGame player) {
    if (potentialAssister != null &&
        potentialAssister!.teamId != player.teamId) {
      potentialAssister = null;
    }
    owner = player;
    lastTouch = player;
    vel = Vec2.zero();
    heightMeters = 0;
    verticalVelocity = 0;
    lastKickType = null;
    lastPassWasHigh = false;
    hasBouncedSinceKick = false;
    goalLineMissCommitted = false;
    dippingFreeKick = false;
    curve = 0;
    spin = 0;
    shotType = null;
    final front = player.lastDirection.normalized(
      Vec2(player.teamId == lastTouch?.teamId ? 1 : -1, 0),
    );
    pos = player.pos + front * (player.radius + GameConstants.ballRadius + 6);
  }

  void release({
    required Vec2 direction,
    required double power,
    required PlayerGame toucher,
    PlayerGame? receiver,
    required KickType kickType,
    double loft = 0,
    bool highPass = false,
    bool dippingFreeKick = false,
    double curve = 0,
    double spin = 0,
    ShotType? shotType,
  }) {
    final dir = direction.normalized(toucher.lastDirection);
    owner = null;
    lastTouch = toucher;
    lastPasser = toucher;
    if (kickType == KickType.pass || kickType == KickType.highPass) {
      potentialAssister = toucher;
    }
    intendedReceiver = receiver;
    lastKickType = kickType;
    lastPassWasHigh = highPass;
    hasBouncedSinceKick = false;
    goalLineMissCommitted = false;
    this.dippingFreeKick = dippingFreeKick;
    this.curve = curve;
    this.spin = spin;
    this.shotType = shotType;
    final baseSpeed = kickType == KickType.shoot
        ? 8.2
        : highPass
        ? 7.45
        : loft > 0.2
        ? 6.65
        : 8.85;
    vel = dir * (baseSpeed * power);
    verticalVelocity = loft;
    if (loft > 0.2) {
      heightMeters = heightMeters < 0.08 ? 0.08 : heightMeters;
    }
  }
}
