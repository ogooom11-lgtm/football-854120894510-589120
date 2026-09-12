/// Behaviour profile of a formation (plan items 4 and 24).
///
/// Every formation preset owns a base shape plus an attacking, defensive,
/// pressing and transition shape. The numbers below are *morph magnitudes*
/// (fractions of pitch width/height), never fixed offsets: the shape engine
/// combines them with the role of the player, the ball, the opponent and the
/// match state to produce the current dynamic target.
class FormationShapeProfile {
  const FormationShapeProfile({
    this.attackingLineHeight = 0.10,
    this.defensiveBlockDrop = 0.08,
    this.pressingLineHeight = 0.06,
    this.transitionDrop = 0.05,
    this.attackingWidth = 1.08,
    this.defensiveWidth = 0.82,
    this.pressingWidth = 0.90,
    this.wingsDropInDefense = false,
    this.interiorInterchange = false,
  });

  /// How far the team pushes up as a block when in possession
  /// (fullbacks advance the most, the holding midfielder the least).
  final double attackingLineHeight;

  /// How deep the block retreats when the opponent has the ball organised.
  final double defensiveBlockDrop;

  /// Line height while pressing high.
  final double pressingLineHeight;

  /// Extra depth taken during the defensive transition (just after losing
  /// the ball) while the counter-press settles.
  final double transitionDrop;

  /// Width multipliers (1.0 = base spread): possession stretches the block,
  /// defence shrinks it (plan item 8).
  final double attackingWidth;
  final double defensiveWidth;
  final double pressingWidth;

  /// Wide forwards fall back to the midfield line out of possession:
  /// 4-3-3 becomes 4-5-1, 4-2-4 protects its centre (plan items 25, 26).
  final bool wingsDropInDefense;

  /// 4-6-0 behaviour (plan item 27): there is no fixed striker; the most
  /// advanced interior player attacks the striker zone while a team-mate
  /// covers the zone he leaves.
  final bool interiorInterchange;
}
