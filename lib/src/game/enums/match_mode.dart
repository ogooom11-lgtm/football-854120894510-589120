/// Match modes. LIG MODU (league) was removed from the game,
/// so only knockout matches remain. The enum name is kept in save
/// files for backward compatibility with older saves.
enum MatchMode { knockout }

extension MatchModeText on MatchMode {
  String get title => switch (this) {
    MatchMode.knockout => 'Eleme',
  };

  String get description => switch (this) {
    MatchMode.knockout =>
      'Beraberlikte 120. dakikaya kadar uzatma, sonra penaltilar.',
  };
}
