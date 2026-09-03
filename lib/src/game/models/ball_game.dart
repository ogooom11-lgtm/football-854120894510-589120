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
  /// Normalised shot power (0..~1.7) of the last kick — a stronger free-kick
  /// shot dips less and can clear the wall (مطلب تعبير الحائط حسب الشدة).
  double shotPower01 = 0;
  double curve = 0;
  double spin = 0;
  ShotType? shotType;
  int trajectoryId = 0;

  /// Minimum horizontal speed kept while a lofted ball is still airborne
  /// (0 when the ball is not an in-flight high pass). Prevents the ball
  /// from stopping mid-air and dropping straight down.
  double highPassCruiseSpeed = 0;

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
    highPassCruiseSpeed = 0;
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
    double shotPower01 = 0,
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
    this.shotPower01 = shotPower01;
    this.curve = curve;
    this.spin = spin;
    this.shotType = shotType;
    trajectoryId += 1;
    // Shooting must be clearly faster than passing, and every player's
    // shot speed comes from his shot-power rating:
    //   weak shot power (~30)  -> ~10.1 px/frame
    //   average shot power     -> ~11.3 px/frame
    //   strong shot power (~90)-> ~12.4 px/frame
    final shotPowerSkill = toucher.profile.shotPowerRating / 100.0;
    final passSkill = toucher.profile.passingRating / 100.0;
    final baseSpeed = kickType == KickType.shoot
        ? 9.2 + shotPowerSkill * 3.6
        : highPass
        ? 7.6 + passSkill * 2.0
        : loft > 0.2
        ? 6.9
        : 8.7 + passSkill * 1.7;
    vel = dir * (baseSpeed * power);
    // While an aerial ball is still travelling, keep enough forward
    // momentum so it never hangs in place and drops straight down.
    highPassCruiseSpeed = highPass ? baseSpeed * power * 0.34 : 0;
    verticalVelocity = loft;
    if (loft > 0.2) {
      heightMeters = heightMeters < 0.08 ? 0.08 : heightMeters;
    }
  }
}
