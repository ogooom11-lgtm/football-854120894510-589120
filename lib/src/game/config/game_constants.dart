class GameConstants {
  const GameConstants._();

  static const double virtualWidth = 1200;
  static const double virtualHeight = 700;
  static const double leftBound = 50;
  static const double rightBound = virtualWidth - 50;
  static const double topBound = 50;
  static const double bottomBound = virtualHeight - 50;
  static const double pitchWidth = rightBound - leftBound;
  static const double pitchHeight = bottomBound - topBound;

  static const double playerRadius = 9;
  // The goalkeeper uses the same on-field footprint as every other player.
  static const double goalkeeperRadius = playerRadius;
  static const double ballRadius = 5;
  static const double goalPixelHeight = 130;
  static const double goalDepth = 24;
  static const double goalHeightMeters = 2.44;
  static const double crossbarMinMeters = 2.43;
  static const double crossbarMaxMeters = 2.45;

  static const double realSecondsPerGameMinute = 5 * 60 / 90;
  static const double gravityMeters = 9.8;
  static const double replayFreezeSeconds = 2.6;
  static const double periodPauseSeconds = 2.2;
  /// A straight red card costs the player exactly one team match
  /// (المطلب: عقاب الكرت الأحمر مباراة واحدة).
  static const int redCardSuspensionMatches = 1;
  /// Standard free-kick wall distance: 9.15 m converted to the pitch scale
  /// (105 m ≈ pitchWidth px) — the human wall stands clearly farther from
  /// the ball than before.
  static double get freeKickWallDistancePx =>
      9.15 * GameConstants.pitchWidth / 105;
}
