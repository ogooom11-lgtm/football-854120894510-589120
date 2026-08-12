/// AI difficulty level for single-player and AI-controlled teams.
enum AiDifficulty {
  /// Easy – AI makes more mistakes, slower reactions.
  easy,

  /// Medium – balanced AI.
  medium,

  /// Hard – AI makes fewer mistakes, faster reactions, smarter decisions.
  hard,
}

extension AiDifficultyInfo on AiDifficulty {
  String get title => switch (this) {
        AiDifficulty.easy => 'Kolay',
        AiDifficulty.medium => 'Orta',
        AiDifficulty.hard => 'Zor',
      };

  String get description => switch (this) {
        AiDifficulty.easy =>
          'AI daha fazla hata yapar, daha yavas tepki verir.',
        AiDifficulty.medium => 'Dengeli AI.',
        AiDifficulty.hard =>
          'AI daha az hata yapar, daha hizli ve akilli kararlar alir.',
      };

  /// Reaction speed multiplier (lower = slower).
  double get reactionFactor => switch (this) {
        AiDifficulty.easy => 0.72,
        AiDifficulty.medium => 1.0,
        AiDifficulty.hard => 1.38,
      };

  /// Error factor applied to AI decisions (higher = more mistakes).
  double get errorFactor => switch (this) {
        AiDifficulty.easy => 0.32,
        AiDifficulty.medium => 0.12,
        AiDifficulty.hard => 0.02,
      };

  /// How aggressively AI presses and tackles (higher = more aggressive).
  double get aggressionFactor => switch (this) {
        AiDifficulty.easy => 0.58,
        AiDifficulty.medium => 0.82,
        AiDifficulty.hard => 1.12,
      };

  /// How far AI can "see" for tactical decisions.
  double get visionRange => switch (this) {
        AiDifficulty.easy => 0.78,
        AiDifficulty.medium => 1.0,
        AiDifficulty.hard => 1.28,
      };

  /// How well AI anticipates passes and shots.
  double get anticipationFactor => switch (this) {
        AiDifficulty.easy => 0.62,
        AiDifficulty.medium => 1.0,
        AiDifficulty.hard => 1.35,
      };
}