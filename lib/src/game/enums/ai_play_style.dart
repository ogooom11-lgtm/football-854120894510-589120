/// AI playing style that influences tactical behavior.
enum AiPlayStyle {
  /// Tiki-Taka: short passes, high possession, patient build-up.
  tikiTaka,

  /// Direct: long balls, quick transitions, physical.
  direct,

  /// Counter-attack: defend deep, fast breaks.
  counter,

  /// Possession: control the ball, wait for openings.
  possession,

  /// Defensive: park the bus, few risks.
  defensive,

  /// Aggressive: high press, all-out attack, risky.
  aggressive,

  /// Balanced: mix of everything.
  balanced,
}

extension AiPlayStyleInfo on AiPlayStyle {
  String get title => switch (this) {
        AiPlayStyle.tikiTaka => 'Tiki-Taka',
        AiPlayStyle.direct => 'Direkt Oyun',
        AiPlayStyle.counter => 'Kontra Atak',
        AiPlayStyle.possession => 'Top Kontrolu',
        AiPlayStyle.defensive => 'Defansif',
        AiPlayStyle.aggressive => 'Saldirgan',
        AiPlayStyle.balanced => 'Dengeli',
      };

  String get description => switch (this) {
        AiPlayStyle.tikiTaka =>
          'Kisa paslar, yuksek top hakimiyeti, sabirli hucum.',
        AiPlayStyle.direct => 'Uzun toplar, hizli gecisler, fiziksel oyun.',
        AiPlayStyle.counter => 'Derinde savunma, hizli kontralar.',
        AiPlayStyle.possession =>
          'Topu cevir, bosluk bekle, kontrollu oyun.',
        AiPlayStyle.defensive => 'Guvenlik oncelikli, az risk.',
        AiPlayStyle.aggressive => 'Yuksek pres, surekli hucum, riskli oyun.',
        AiPlayStyle.balanced => 'Her seyden biraz, dengeli yaklasim.',
      };

  /// How far AI prefers to pass (1.0 = normal, >1.0 = longer).
  double get passRangeFactor => switch (this) {
        AiPlayStyle.tikiTaka => 0.62,
        AiPlayStyle.direct => 1.65,
        AiPlayStyle.counter => 1.45,
        AiPlayStyle.possession => 0.68,
        AiPlayStyle.defensive => 0.85,
        AiPlayStyle.aggressive => 1.12,
        AiPlayStyle.balanced => 1.0,
      };

  /// How often AI shoots from distance (1.0 = normal, >1.0 = more).
  double get shootingTendency => switch (this) {
        AiPlayStyle.tikiTaka => 0.58,
        AiPlayStyle.direct => 1.25,
        AiPlayStyle.counter => 1.15,
        AiPlayStyle.possession => 0.45,
        AiPlayStyle.defensive => 0.35,
        AiPlayStyle.aggressive => 1.55,
        AiPlayStyle.balanced => 1.0,
      };

  /// How high the defensive line sits (1.0 = normal, >1.0 = higher).
  double get defensiveLineFactor => switch (this) {
        AiPlayStyle.tikiTaka => 1.18,
        AiPlayStyle.direct => 0.72,
        AiPlayStyle.counter => 0.48,
        AiPlayStyle.possession => 1.22,
        AiPlayStyle.defensive => 0.28,
        AiPlayStyle.aggressive => 1.42,
        AiPlayStyle.balanced => 1.0,
      };

  /// Pressing intensity (0.0-1.0).
  double get pressingIntensity => switch (this) {
        AiPlayStyle.tikiTaka => 0.72,
        AiPlayStyle.direct => 0.55,
        AiPlayStyle.counter => 0.42,
        AiPlayStyle.possession => 0.65,
        AiPlayStyle.defensive => 0.22,
        AiPlayStyle.aggressive => 0.92,
        AiPlayStyle.balanced => 0.60,
      };

  /// Risk factor for risky passes and dribbles (0.0-1.0).
  double get riskFactor => switch (this) {
        AiPlayStyle.tikiTaka => 0.35,
        AiPlayStyle.direct => 0.62,
        AiPlayStyle.counter => 0.48,
        AiPlayStyle.possession => 0.22,
        AiPlayStyle.defensive => 0.12,
        AiPlayStyle.aggressive => 0.78,
        AiPlayStyle.balanced => 0.40,
      };

  /// Build-up speed, affects how quickly AI moves forward (1.0 = normal).
  double get tempoFactor => switch (this) {
        AiPlayStyle.tikiTaka => 0.58,
        AiPlayStyle.direct => 1.42,
        AiPlayStyle.counter => 1.65,
        AiPlayStyle.possession => 0.48,
        AiPlayStyle.defensive => 0.35,
        AiPlayStyle.aggressive => 1.38,
        AiPlayStyle.balanced => 1.0,
      };

  /// How much width AI uses (1.0 = normal, >1.0 = wider).
  double get widthFactor => switch (this) {
        AiPlayStyle.tikiTaka => 1.12,
        AiPlayStyle.direct => 0.78,
        AiPlayStyle.counter => 1.08,
        AiPlayStyle.possession => 1.18,
        AiPlayStyle.defensive => 0.62,
        AiPlayStyle.aggressive => 1.25,
        AiPlayStyle.balanced => 1.0,
      };

  /// Block tightness bias (plan item 5): >1.0 keeps the team compact as a
  /// block, <1.0 lets it stretch.
  double get compactnessBias => switch (this) {
        AiPlayStyle.tikiTaka => 1.12,
        AiPlayStyle.direct => 0.92,
        AiPlayStyle.counter => 1.05,
        AiPlayStyle.possession => 0.96,
        AiPlayStyle.defensive => 1.20,
        AiPlayStyle.aggressive => 1.08,
        AiPlayStyle.balanced => 1.0,
      };

  /// How long and hard the team counter-presses right after losing the ball
  /// (plan item 16): 0.0 = straight back into the block, 1.0 = aggressive
  /// gegenpressing.
  double get counterPressIntensity => switch (this) {
        AiPlayStyle.tikiTaka => 0.78,
        AiPlayStyle.direct => 0.62,
        AiPlayStyle.counter => 0.55,
        AiPlayStyle.possession => 0.68,
        AiPlayStyle.defensive => 0.25,
        AiPlayStyle.aggressive => 0.95,
        AiPlayStyle.balanced => 0.55,
      };
}
