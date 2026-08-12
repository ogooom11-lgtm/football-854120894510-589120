enum PlayerRole {
  goalkeeper,
  centerBackLeft,
  centerBackRight,
  sweeper,
  leftWingBack,
  rightWingBack,
  midfieldLeft,
  midfieldRight,
  leftWing,
  rightWing,
  striker,
}

extension PlayerRoleInfo on PlayerRole {
  String get code => switch (this) {
        PlayerRole.goalkeeper => 'GK',
        PlayerRole.centerBackLeft => 'CB1',
        PlayerRole.centerBackRight => 'CB2',
        PlayerRole.sweeper => 'LIB',
        PlayerRole.leftWingBack => 'LWB',
        PlayerRole.rightWingBack => 'RWB',
        PlayerRole.midfieldLeft => 'CM1',
        PlayerRole.midfieldRight => 'CM2',
        PlayerRole.leftWing => 'LW',
        PlayerRole.rightWing => 'RW',
        PlayerRole.striker => 'ST',
      };

  String get turkishName => switch (this) {
        PlayerRole.goalkeeper => 'Kaleci',
        PlayerRole.centerBackLeft => 'Sol stoper',
        PlayerRole.centerBackRight => 'Sag stoper',
        PlayerRole.sweeper => 'Libero',
        PlayerRole.leftWingBack => 'Sol bek',
        PlayerRole.rightWingBack => 'Sag bek',
        PlayerRole.midfieldLeft => 'Orta saha',
        PlayerRole.midfieldRight => 'Oyun kurucu',
        PlayerRole.leftWing => 'Sol kanat',
        PlayerRole.rightWing => 'Sag kanat',
        PlayerRole.striker => 'Forvet',
      };

  bool get isGoalkeeper => this == PlayerRole.goalkeeper;

  bool get isDefender =>
      this == PlayerRole.centerBackLeft ||
      this == PlayerRole.centerBackRight ||
      this == PlayerRole.sweeper ||
      this == PlayerRole.leftWingBack ||
      this == PlayerRole.rightWingBack;

  bool get isWide =>
      this == PlayerRole.leftWing ||
      this == PlayerRole.rightWing ||
      this == PlayerRole.leftWingBack ||
      this == PlayerRole.rightWingBack;

  bool get isAttacker =>
      this == PlayerRole.striker ||
      this == PlayerRole.leftWing ||
      this == PlayerRole.rightWing;
}
