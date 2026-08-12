enum KickType { shoot, pass, highPass }

extension KickTypeText on KickType {
  String get title => switch (this) {
        KickType.shoot => 'Sut',
        KickType.pass => 'Pas',
        KickType.highPass => 'Yuksek pas',
      };
}
