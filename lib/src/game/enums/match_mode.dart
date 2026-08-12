enum MatchMode { knockout, league }

extension MatchModeText on MatchMode {
  String get title => switch (this) {
        MatchMode.knockout => 'Eleme',
        MatchMode.league => 'Lig maci',
      };

  String get description => switch (this) {
        MatchMode.knockout =>
          'Beraberlikte 120. dakikaya kadar uzatma, sonra penaltilar.',
        MatchMode.league => '90 dakika ve uzatma dakikalari sonunda biter.',
      };
}
