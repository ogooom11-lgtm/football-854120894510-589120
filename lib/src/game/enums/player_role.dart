/// Player roles, independent of how many players stand in a formation line
/// (plan item 19). A formation decides which roles it uses; the role itself
/// decides how the player behaves in every phase of play.
enum PlayerRole {
  goalkeeper,
  leftBack,
  rightBack,
  centerBackLeft,
  centerBackRight,
  sweeper,
  leftWingBack,
  rightWingBack,
  defensiveMidfielder,
  midfieldLeft,
  midfieldRight,
  attackingMidfielder,
  leftWing,
  rightWing,
  striker,
}

extension PlayerRoleInfo on PlayerRole {
  String get code => switch (this) {
        PlayerRole.goalkeeper => 'GK',
        PlayerRole.leftBack => 'LB',
        PlayerRole.rightBack => 'RB',
        PlayerRole.centerBackLeft => 'CB1',
        PlayerRole.centerBackRight => 'CB2',
        PlayerRole.sweeper => 'LIB',
        PlayerRole.leftWingBack => 'LWB',
        PlayerRole.rightWingBack => 'RWB',
        PlayerRole.defensiveMidfielder => 'DM',
        PlayerRole.midfieldLeft => 'CM1',
        PlayerRole.midfieldRight => 'CM2',
        PlayerRole.attackingMidfielder => 'AM',
        PlayerRole.leftWing => 'LW',
        PlayerRole.rightWing => 'RW',
        PlayerRole.striker => 'ST',
      };

  String get turkishName => switch (this) {
        PlayerRole.goalkeeper => 'Kaleci',
        PlayerRole.leftBack => 'Sol bek',
        PlayerRole.rightBack => 'Sag bek',
        PlayerRole.centerBackLeft => 'Sol stoper',
        PlayerRole.centerBackRight => 'Sag stoper',
        PlayerRole.sweeper => 'Libero',
        PlayerRole.leftWingBack => 'Sol kanat bek',
        PlayerRole.rightWingBack => 'Sag kanat bek',
        PlayerRole.defensiveMidfielder => 'On liberi',
        PlayerRole.midfieldLeft => 'Orta saha',
        PlayerRole.midfieldRight => 'Orta saha',
        PlayerRole.attackingMidfielder => 'Ofansif orta saha',
        PlayerRole.leftWing => 'Sol kanat',
        PlayerRole.rightWing => 'Sag kanat',
        PlayerRole.striker => 'Forvet',
      };

  bool get isGoalkeeper => this == PlayerRole.goalkeeper;

  bool get isDefender =>
      this == PlayerRole.centerBackLeft ||
      this == PlayerRole.centerBackRight ||
      this == PlayerRole.sweeper ||
      this == PlayerRole.leftBack ||
      this == PlayerRole.rightBack ||
      this == PlayerRole.leftWingBack ||
      this == PlayerRole.rightWingBack;

  bool get isMidfield =>
      this == PlayerRole.defensiveMidfielder ||
      this == PlayerRole.midfieldLeft ||
      this == PlayerRole.midfieldRight ||
      this == PlayerRole.attackingMidfielder;

  bool get isWide =>
      this == PlayerRole.leftWing ||
      this == PlayerRole.rightWing ||
      this == PlayerRole.leftBack ||
      this == PlayerRole.rightBack ||
      this == PlayerRole.leftWingBack ||
      this == PlayerRole.rightWingBack;

  bool get isAttacker =>
      this == PlayerRole.striker ||
      this == PlayerRole.leftWing ||
      this == PlayerRole.rightWing;

  /// The playmaker roles (plan item 21): the libero and the attacking
  /// midfielder roam the most; centre backs are the most restricted.
  bool get isPlaymaker =>
      this == PlayerRole.sweeper || this == PlayerRole.attackingMidfielder;

  /// Anchor-side role group used by the shape engine to morph formations
  /// between their attacking/defensive/pressing/transition shapes.
  RoleGroup get group => switch (this) {
        PlayerRole.goalkeeper => RoleGroup.keeper,
        PlayerRole.centerBackLeft ||
        PlayerRole.centerBackRight ||
        PlayerRole.sweeper => RoleGroup.centralDefence,
        PlayerRole.leftBack ||
        PlayerRole.rightBack ||
        PlayerRole.leftWingBack ||
        PlayerRole.rightWingBack => RoleGroup.fullBack,
        PlayerRole.defensiveMidfielder => RoleGroup.holdingMidfield,
        PlayerRole.midfieldLeft ||
        PlayerRole.midfieldRight => RoleGroup.centralMidfield,
        PlayerRole.attackingMidfielder => RoleGroup.attackingMidfield,
        PlayerRole.leftWing || PlayerRole.rightWing => RoleGroup.wing,
        PlayerRole.striker => RoleGroup.striker,
      };

  /// How much freedom this role has to leave its anchor (plan items 2 and 21).
  /// 0 = glued to the anchor, 1 = free roaming. The libero and the playmaker
  /// are the freest, centre backs the least free.
  double get movementFreedom => switch (this) {
        PlayerRole.goalkeeper => 0.00,
        PlayerRole.centerBackLeft || PlayerRole.centerBackRight => 0.14,
        PlayerRole.sweeper => 0.62,
        PlayerRole.leftBack || PlayerRole.rightBack => 0.42,
        PlayerRole.leftWingBack || PlayerRole.rightWingBack => 0.58,
        PlayerRole.defensiveMidfielder => 0.34,
        PlayerRole.midfieldLeft || PlayerRole.midfieldRight => 0.52,
        PlayerRole.attackingMidfielder => 0.80,
        PlayerRole.leftWing || PlayerRole.rightWing => 0.68,
        PlayerRole.striker => 0.74,
      };

  /// Allowed depth band (fraction of pitch width measured from the team's own
  /// goal line) the role may operate inside — its "zone" (plan item 2).
  double get minAdvance => switch (this) {
        PlayerRole.goalkeeper => 0.00,
        PlayerRole.centerBackLeft ||
        PlayerRole.centerBackRight ||
        PlayerRole.sweeper => 0.08,
        PlayerRole.leftBack ||
        PlayerRole.rightBack ||
        PlayerRole.leftWingBack ||
        PlayerRole.rightWingBack => 0.10,
        PlayerRole.defensiveMidfielder => 0.16,
        PlayerRole.midfieldLeft || PlayerRole.midfieldRight => 0.22,
        PlayerRole.attackingMidfielder => 0.30,
        PlayerRole.leftWing || PlayerRole.rightWing => 0.22,
        PlayerRole.striker => 0.34,
      };

  double get maxAdvance => switch (this) {
        PlayerRole.goalkeeper => 0.10,
        PlayerRole.centerBackLeft || PlayerRole.centerBackRight => 0.58,
        PlayerRole.sweeper => 0.62,
        PlayerRole.leftBack || PlayerRole.rightBack => 0.78,
        PlayerRole.leftWingBack || PlayerRole.rightWingBack => 0.86,
        PlayerRole.defensiveMidfielder => 0.72,
        PlayerRole.midfieldLeft || PlayerRole.midfieldRight => 0.84,
        PlayerRole.attackingMidfielder => 0.92,
        PlayerRole.leftWing || PlayerRole.rightWing => 0.93,
        PlayerRole.striker => 0.96,
      };

  /// How strongly the player shifts toward the ball's side (plan item 7).
  /// The near side presses/supports, the middle closes passing lanes, the far
  /// side tucks inside without abandoning its task.
  double get ballSideTilt => switch (this) {
        PlayerRole.goalkeeper => 0.00,
        PlayerRole.centerBackLeft || PlayerRole.centerBackRight => 0.16,
        PlayerRole.sweeper => 0.20,
        PlayerRole.leftBack ||
        PlayerRole.rightBack ||
        PlayerRole.leftWingBack ||
        PlayerRole.rightWingBack => 0.26,
        PlayerRole.defensiveMidfielder => 0.30,
        PlayerRole.midfieldLeft || PlayerRole.midfieldRight => 0.34,
        PlayerRole.attackingMidfielder => 0.38,
        PlayerRole.leftWing || PlayerRole.rightWing => 0.34,
        PlayerRole.striker => 0.30,
      };

  /// Priority in the defensive decision chain (plan item 23): which roles are
  /// natural ball-winners when the team decides who presses and who covers.
  double get pressingPriority => switch (this) {
        PlayerRole.goalkeeper => 0.00,
        PlayerRole.centerBackLeft || PlayerRole.centerBackRight => 0.35,
        PlayerRole.sweeper => 0.40,
        PlayerRole.leftBack || PlayerRole.rightBack => 0.62,
        PlayerRole.leftWingBack || PlayerRole.rightWingBack => 0.72,
        PlayerRole.defensiveMidfielder => 0.90,
        PlayerRole.midfieldLeft || PlayerRole.midfieldRight => 0.82,
        PlayerRole.attackingMidfielder => 0.74,
        PlayerRole.leftWing || PlayerRole.rightWing => 0.70,
        PlayerRole.striker => 0.66,
      };

  /// Willingness to track back and help the defence without becoming a
  /// defender (plan item 11).
  double get defensiveHelpFactor => switch (this) {
        PlayerRole.goalkeeper => 0.00,
        PlayerRole.centerBackLeft || PlayerRole.centerBackRight => 1.00,
        PlayerRole.sweeper => 1.00,
        PlayerRole.leftBack || PlayerRole.rightBack => 0.95,
        PlayerRole.leftWingBack || PlayerRole.rightWingBack => 0.90,
        PlayerRole.defensiveMidfielder => 0.92,
        PlayerRole.midfieldLeft || PlayerRole.midfieldRight => 0.80,
        PlayerRole.attackingMidfielder => 0.66,
        PlayerRole.leftWing || PlayerRole.rightWing => 0.60,
        PlayerRole.striker => 0.48,
      };

  /// Base running speed multiplier used by the movement layer (plan item 22):
  /// speed emerges from role, distance, state, stamina, danger and pressure.
  double get speedBias => switch (this) {
        PlayerRole.goalkeeper => 1.00,
        PlayerRole.centerBackLeft || PlayerRole.centerBackRight => 0.96,
        PlayerRole.sweeper => 0.98,
        PlayerRole.leftBack || PlayerRole.rightBack => 1.02,
        PlayerRole.leftWingBack || PlayerRole.rightWingBack => 1.06,
        PlayerRole.defensiveMidfielder => 0.99,
        PlayerRole.midfieldLeft || PlayerRole.midfieldRight => 1.00,
        PlayerRole.attackingMidfielder => 1.02,
        PlayerRole.leftWing || PlayerRole.rightWing => 1.05,
        PlayerRole.striker => 1.04,
      };
}

enum RoleGroup {
  keeper,
  centralDefence,
  fullBack,
  holdingMidfield,
  centralMidfield,
  attackingMidfield,
  wing,
  striker,
}
