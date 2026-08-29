import '../enums/player_role.dart';
import 'tactics/shape_profile.dart';

enum FormationType {
  bus541,
  kontrollu5311,
  midfield361,
  classic442,
  modern4231,
  wingback352,
  diamond41212,
  wing433,
  magic4222,
  narrow4312,
  total343,
  brazil424,
  false460,
  bielsa3331,
  modern3241,
  pyramid235,
  metodo2323,
  total1333,
  christmas4321,
  anchor4141,
  support4411,
  counter523,
  creators3421,
  balanced,
  attacking,
  compact,
}

class FormationSpot {
  const FormationSpot({
    required this.role,
    required this.number,
    required this.x,
    required this.y,
  });

  final PlayerRole role;
  final int number;
  final double x;
  final double y;
}

class FormationPlan {
  const FormationPlan({
    required this.type,
    required this.name,
    required this.spots,
  });

  final FormationType type;
  final String name;
  final List<FormationSpot> spots;
}

class _FormationSpec {
  const _FormationSpec(this.title, this.lines, this.roles);

  final String title;
  final List<int> lines;

  /// Explicit role for every slot (goalkeeper first), from the defensive
  /// lines to the attacking lines, top to bottom inside each line. Roles are
  /// declared per formation and are never derived from the line counts
  /// (plan item 19).
  final List<PlayerRole> roles;
}

const _gk = PlayerRole.goalkeeper;
const _lb = PlayerRole.leftBack;
const _rb = PlayerRole.rightBack;
const _cb1 = PlayerRole.centerBackLeft;
const _cb2 = PlayerRole.centerBackRight;
const _lib = PlayerRole.sweeper;
const _lwb = PlayerRole.leftWingBack;
const _rwb = PlayerRole.rightWingBack;
const _dm = PlayerRole.defensiveMidfielder;
const _cm1 = PlayerRole.midfieldLeft;
const _cm2 = PlayerRole.midfieldRight;
const _am = PlayerRole.attackingMidfielder;
const _lw = PlayerRole.leftWing;
const _rw = PlayerRole.rightWing;
const _st = PlayerRole.striker;

const Map<FormationType, _FormationSpec> _formationSpecs = {
  FormationType.bus541: _FormationSpec('5-4-1 Otobus Cekme Sistemi', [5, 4, 1], [
    _gk,
    _lwb, _cb1, _lib, _cb2, _rwb,
    _lw, _cm1, _cm2, _rw,
    _st,
  ]),
  FormationType.kontrollu5311: _FormationSpec(
    '5-3-1-1 Kontrollu Savunma',
    [5, 3, 1, 1],
    [
      _gk,
      _lwb, _cb1, _lib, _cb2, _rwb,
      _cm1, _dm, _cm2,
      _am,
      _st,
    ],
  ),
  FormationType.midfield361: _FormationSpec('3-6-1 Orta Saha Duvari', [3, 6, 1], [
    _gk,
    _cb1, _lib, _cb2,
    _lwb, _cm1, _dm, _am, _cm2, _rwb,
    _st,
  ]),
  FormationType.classic442: _FormationSpec('4-4-2 Klasik Ingiliz Sistemi', [4, 4, 2], [
    _gk,
    _lb, _cb1, _cb2, _rb,
    _lw, _cm1, _cm2, _rw,
    _st, _st,
  ]),
  FormationType.modern4231: _FormationSpec('4-2-3-1 Modern Sistem', [4, 2, 3, 1], [
    _gk,
    _lb, _cb1, _cb2, _rb,
    _dm, _dm,
    _lw, _am, _rw,
    _st,
  ]),
  FormationType.wingback352: _FormationSpec('3-5-2 Kanat Bekli Sistem', [3, 5, 2], [
    _gk,
    _cb1, _lib, _cb2,
    _lwb, _dm, _cm1, _cm2, _rwb,
    _st, _st,
  ]),
  FormationType.diamond41212: _FormationSpec('4-1-2-1-2 Elmas', [4, 1, 2, 1, 2], [
    _gk,
    _lb, _cb1, _cb2, _rb,
    _dm,
    _cm1, _cm2,
    _am,
    _st, _st,
  ]),
  FormationType.wing433: _FormationSpec('4-3-3 Kanat Hucum Sistemi', [4, 3, 3], [
    _gk,
    _lb, _cb1, _cb2, _rb,
    _cm1, _dm, _cm2,
    _lw, _st, _rw,
  ]),
  FormationType.magic4222: _FormationSpec('4-2-2-2 Sihirli Kare', [4, 2, 2, 2], [
    _gk,
    _lb, _cb1, _cb2, _rb,
    _dm, _dm,
    _am, _am,
    _st, _st,
  ]),
  FormationType.narrow4312: _FormationSpec('4-3-1-2 Dar Elmas', [4, 3, 1, 2], [
    _gk,
    _lb, _cb1, _cb2, _rb,
    _cm1, _dm, _cm2,
    _am,
    _st, _st,
  ]),
  FormationType.total343: _FormationSpec('3-4-3 Total Hucum', [3, 4, 3], [
    _gk,
    _cb1, _lib, _cb2,
    _lwb, _cm1, _cm2, _rwb,
    _lw, _st, _rw,
  ]),
  FormationType.brazil424: _FormationSpec('4-2-4 Brezilya Sistemi', [4, 2, 4], [
    _gk,
    _lb, _cb1, _cb2, _rb,
    _dm, _cm1,
    _lw, _st, _st, _rw,
  ]),
  FormationType.false460: _FormationSpec('4-6-0 Sahte Forvetsiz Sistem', [4, 6], [
    _gk,
    _lb, _cb1, _cb2, _rb,
    _lw, _cm1, _dm, _am, _cm2, _rw,
  ]),
  FormationType.bielsa3331: _FormationSpec('3-3-3-1 Bielsa Sistemi', [3, 3, 3, 1], [
    _gk,
    _cb1, _lib, _cb2,
    _cm1, _dm, _cm2,
    _lw, _am, _rw,
    _st,
  ]),
  FormationType.modern3241: _FormationSpec('3-2-4-1 Modern WM', [3, 2, 4, 1], [
    _gk,
    _cb1, _lib, _cb2,
    _dm, _dm,
    _lw, _am, _am, _rw,
    _st,
  ]),
  FormationType.pyramid235: _FormationSpec('2-3-5 Piramit', [2, 3, 5], [
    _gk,
    _cb1, _cb2,
    _cm1, _dm, _cm2,
    _lw, _st, _st, _st, _rw,
  ]),
  FormationType.metodo2323: _FormationSpec('2-3-2-3 Metodo', [2, 3, 2, 3], [
    _gk,
    _cb1, _cb2,
    _cm1, _dm, _cm2,
    _am, _am,
    _lw, _st, _rw,
  ]),
  FormationType.total1333: _FormationSpec('1-3-3-3 Total Futbol', [1, 3, 3, 3], [
    _gk,
    _lib,
    _lb, _cb1, _rb,
    _cm1, _dm, _cm2,
    _lw, _st, _rw,
  ]),
  FormationType.christmas4321: _FormationSpec('4-3-2-1 Noel Agaci', [4, 3, 2, 1], [
    _gk,
    _lb, _cb1, _cb2, _rb,
    _cm1, _dm, _cm2,
    _am, _am,
    _st,
  ]),
  FormationType.anchor4141: _FormationSpec('4-1-4-1 Tek On Libero', [4, 1, 4, 1], [
    _gk,
    _lb, _cb1, _cb2, _rb,
    _dm,
    _lw, _cm1, _cm2, _rw,
    _st,
  ]),
  FormationType.support4411: _FormationSpec('4-4-1-1 Destek Forvetli Sistem', [4, 4, 1, 1], [
    _gk,
    _lb, _cb1, _cb2, _rb,
    _lw, _cm1, _cm2, _rw,
    _am,
    _st,
  ]),
  FormationType.counter523: _FormationSpec('5-2-3 Kanat Kontra Sistemi', [5, 2, 3], [
    _gk,
    _lwb, _cb1, _lib, _cb2, _rwb,
    _dm, _cm1,
    _lw, _st, _rw,
  ]),
  FormationType.creators3421: _FormationSpec(
    '3-4-2-1 Cift Oyun Kuruculu Sistem',
    [3, 4, 2, 1],
    [
      _gk,
      _cb1, _lib, _cb2,
      _lwb, _cm1, _cm2, _rwb,
      _am, _am,
      _st,
    ],
  ),
};

const playableFormationTypes = [
  FormationType.bus541,
  FormationType.kontrollu5311,
  FormationType.midfield361,
  FormationType.classic442,
  FormationType.modern4231,
  FormationType.wingback352,
  FormationType.diamond41212,
  FormationType.wing433,
  FormationType.magic4222,
  FormationType.narrow4312,
  FormationType.total343,
  FormationType.brazil424,
  FormationType.false460,
  FormationType.bielsa3331,
  FormationType.modern3241,
  FormationType.pyramid235,
  FormationType.metodo2323,
  FormationType.total1333,
  FormationType.christmas4321,
  FormationType.anchor4141,
  FormationType.support4411,
  FormationType.counter523,
  FormationType.creators3421,
];

extension FormationText on FormationType {
  String get title =>
      _formationSpecs[_normalized]?.title ?? '4-3-3 Kanat Hucum Sistemi';

  FormationType get _normalized => switch (this) {
    FormationType.balanced => FormationType.total343,
    FormationType.attacking => FormationType.wing433,
    FormationType.compact => FormationType.wingback352,
    _ => this,
  };

  FormationType get next {
    final values = playableFormationTypes;
    final index = values.indexOf(_normalized);
    return values[(index + 1) % values.length];
  }
}

FormationType formationFromName(Object? value) {
  final name = value?.toString();
  if (name == null || name.isEmpty) {
    return FormationType.wing433;
  }
  return FormationType.values
      .firstWhere(
        (type) => type.name == name,
        orElse: () => switch (name) {
          'balanced' => FormationType.total343,
          'attacking' => FormationType.wing433,
          'compact' => FormationType.wingback352,
          _ => FormationType.wing433,
        },
      )
      ._normalized;
}

FormationPlan formationPlan(FormationType type) {
  final normalized = type._normalized;
  final spec =
      _formationSpecs[normalized] ?? _formationSpecs[FormationType.wing433]!;
  return FormationPlan(
    type: normalized,
    name: spec.title,
    spots: _buildSpots(spec),
  );
}

/// The behaviour profile every shape of this formation morphs from
/// (plan items 4 and 24): each preset becomes a behavioural system with a
/// base, attacking, defensive, pressing and transition shape.
FormationShapeProfile formationShapeProfile(FormationType type) {
  final normalized = type._normalized;
  return _shapeProfiles[normalized] ?? const FormationShapeProfile();
}

const Map<FormationType, FormationShapeProfile> _shapeProfiles = {
  // The bus: deep block, small advances, wings track back.
  FormationType.bus541: FormationShapeProfile(
    attackingLineHeight: 0.055,
    defensiveBlockDrop: 0.045,
    pressingLineHeight: 0.045,
    transitionDrop: 0.035,
    attackingWidth: 0.94,
    defensiveWidth: 0.70,
    pressingWidth: 0.82,
    wingsDropInDefense: true,
  ),
  FormationType.kontrollu5311: FormationShapeProfile(
    attackingLineHeight: 0.07,
    defensiveBlockDrop: 0.055,
    pressingLineHeight: 0.05,
    transitionDrop: 0.04,
    attackingWidth: 0.98,
    defensiveWidth: 0.72,
    pressingWidth: 0.84,
    wingsDropInDefense: true,
  ),
  FormationType.midfield361: FormationShapeProfile(
    attackingLineHeight: 0.10,
    defensiveBlockDrop: 0.075,
    pressingLineHeight: 0.06,
    transitionDrop: 0.05,
    attackingWidth: 1.08,
    defensiveWidth: 0.80,
    pressingWidth: 0.88,
  ),
  FormationType.classic442: FormationShapeProfile(
    attackingLineHeight: 0.09,
    defensiveBlockDrop: 0.08,
    pressingLineHeight: 0.055,
    transitionDrop: 0.05,
    attackingWidth: 1.04,
    defensiveWidth: 0.82,
    pressingWidth: 0.88,
    wingsDropInDefense: true,
  ),
  FormationType.modern4231: FormationShapeProfile(
    attackingLineHeight: 0.10,
    defensiveBlockDrop: 0.08,
    pressingLineHeight: 0.065,
    transitionDrop: 0.05,
    attackingWidth: 1.10,
    defensiveWidth: 0.80,
    pressingWidth: 0.90,
    wingsDropInDefense: true,
  ),
  FormationType.wingback352: FormationShapeProfile(
    attackingLineHeight: 0.12,
    defensiveBlockDrop: 0.085,
    pressingLineHeight: 0.07,
    transitionDrop: 0.055,
    attackingWidth: 1.12,
    defensiveWidth: 0.84,
    pressingWidth: 0.92,
  ),
  FormationType.diamond41212: FormationShapeProfile(
    attackingLineHeight: 0.10,
    defensiveBlockDrop: 0.08,
    pressingLineHeight: 0.06,
    transitionDrop: 0.05,
    attackingWidth: 0.98,
    defensiveWidth: 0.74,
    pressingWidth: 0.86,
    wingsDropInDefense: true,
  ),
  // 4-3-3 (plan item 25): fullbacks push high (2-3-5 feel in possession),
  // wings and midfield drop into a 4-5-1 block out of possession.
  FormationType.wing433: FormationShapeProfile(
    attackingLineHeight: 0.125,
    defensiveBlockDrop: 0.085,
    pressingLineHeight: 0.075,
    transitionDrop: 0.05,
    attackingWidth: 1.14,
    defensiveWidth: 0.86,
    pressingWidth: 0.92,
    wingsDropInDefense: true,
  ),
  FormationType.magic4222: FormationShapeProfile(
    attackingLineHeight: 0.10,
    defensiveBlockDrop: 0.08,
    pressingLineHeight: 0.06,
    transitionDrop: 0.05,
    attackingWidth: 1.02,
    defensiveWidth: 0.80,
    pressingWidth: 0.88,
    wingsDropInDefense: true,
  ),
  FormationType.narrow4312: FormationShapeProfile(
    attackingLineHeight: 0.10,
    defensiveBlockDrop: 0.08,
    pressingLineHeight: 0.06,
    transitionDrop: 0.05,
    attackingWidth: 0.92,
    defensiveWidth: 0.74,
    pressingWidth: 0.86,
    wingsDropInDefense: true,
  ),
  FormationType.total343: FormationShapeProfile(
    attackingLineHeight: 0.13,
    defensiveBlockDrop: 0.08,
    pressingLineHeight: 0.08,
    transitionDrop: 0.05,
    attackingWidth: 1.16,
    defensiveWidth: 0.86,
    pressingWidth: 0.94,
  ),
  // 4-2-4 (plan item 26): huge attacking presence, but both wide forwards
  // sprint back when the ball is lost to protect the midfield depth.
  FormationType.brazil424: FormationShapeProfile(
    attackingLineHeight: 0.13,
    defensiveBlockDrop: 0.09,
    pressingLineHeight: 0.07,
    transitionDrop: 0.06,
    attackingWidth: 1.12,
    defensiveWidth: 0.82,
    pressingWidth: 0.90,
    wingsDropInDefense: true,
  ),
  // 4-6-0 (plan item 27): no fixed striker — the most advanced interior
  // player enters the striker zone and a team-mate covers his zone.
  FormationType.false460: FormationShapeProfile(
    attackingLineHeight: 0.12,
    defensiveBlockDrop: 0.08,
    pressingLineHeight: 0.07,
    transitionDrop: 0.05,
    attackingWidth: 1.10,
    defensiveWidth: 0.86,
    pressingWidth: 0.94,
    interiorInterchange: true,
  ),
  FormationType.bielsa3331: FormationShapeProfile(
    attackingLineHeight: 0.14,
    defensiveBlockDrop: 0.09,
    pressingLineHeight: 0.09,
    transitionDrop: 0.055,
    attackingWidth: 1.10,
    defensiveWidth: 0.84,
    pressingWidth: 0.95,
    wingsDropInDefense: true,
  ),
  FormationType.modern3241: FormationShapeProfile(
    attackingLineHeight: 0.12,
    defensiveBlockDrop: 0.08,
    pressingLineHeight: 0.07,
    transitionDrop: 0.05,
    attackingWidth: 1.10,
    defensiveWidth: 0.84,
    pressingWidth: 0.92,
    wingsDropInDefense: true,
  ),
  FormationType.pyramid235: FormationShapeProfile(
    attackingLineHeight: 0.12,
    defensiveBlockDrop: 0.10,
    pressingLineHeight: 0.06,
    transitionDrop: 0.06,
    attackingWidth: 1.14,
    defensiveWidth: 0.88,
    pressingWidth: 0.92,
    wingsDropInDefense: true,
  ),
  FormationType.metodo2323: FormationShapeProfile(
    attackingLineHeight: 0.11,
    defensiveBlockDrop: 0.085,
    pressingLineHeight: 0.06,
    transitionDrop: 0.055,
    attackingWidth: 1.05,
    defensiveWidth: 0.82,
    pressingWidth: 0.90,
    wingsDropInDefense: true,
  ),
  FormationType.total1333: FormationShapeProfile(
    attackingLineHeight: 0.13,
    defensiveBlockDrop: 0.08,
    pressingLineHeight: 0.08,
    transitionDrop: 0.05,
    attackingWidth: 1.15,
    defensiveWidth: 0.86,
    pressingWidth: 0.94,
  ),
  FormationType.christmas4321: FormationShapeProfile(
    attackingLineHeight: 0.10,
    defensiveBlockDrop: 0.08,
    pressingLineHeight: 0.06,
    transitionDrop: 0.05,
    attackingWidth: 1.00,
    defensiveWidth: 0.78,
    pressingWidth: 0.90,
    wingsDropInDefense: true,
  ),
  FormationType.anchor4141: FormationShapeProfile(
    attackingLineHeight: 0.10,
    defensiveBlockDrop: 0.08,
    pressingLineHeight: 0.06,
    transitionDrop: 0.05,
    attackingWidth: 1.05,
    defensiveWidth: 0.80,
    pressingWidth: 0.90,
    wingsDropInDefense: true,
  ),
  FormationType.support4411: FormationShapeProfile(
    attackingLineHeight: 0.10,
    defensiveBlockDrop: 0.08,
    pressingLineHeight: 0.06,
    transitionDrop: 0.05,
    attackingWidth: 1.04,
    defensiveWidth: 0.80,
    pressingWidth: 0.90,
    wingsDropInDefense: true,
  ),
  FormationType.counter523: FormationShapeProfile(
    attackingLineHeight: 0.11,
    defensiveBlockDrop: 0.05,
    pressingLineHeight: 0.05,
    transitionDrop: 0.04,
    attackingWidth: 1.08,
    defensiveWidth: 0.80,
    pressingWidth: 0.86,
    wingsDropInDefense: true,
  ),
  FormationType.creators3421: FormationShapeProfile(
    attackingLineHeight: 0.11,
    defensiveBlockDrop: 0.08,
    pressingLineHeight: 0.065,
    transitionDrop: 0.05,
    attackingWidth: 1.06,
    defensiveWidth: 0.82,
    pressingWidth: 0.92,
    wingsDropInDefense: true,
  ),
};

List<FormationSpot> _buildSpots(_FormationSpec spec) {
  var roleIndex = 0;
  final spots = <FormationSpot>[
    FormationSpot(
      role: spec.roles[roleIndex++],
      number: _numberForRole(spec.roles[0], 0),
      x: 0.03,
      y: 0.50,
    ),
  ];
  final lines = spec.lines;
  final outfieldLines = lines.length;
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final count = lines[lineIndex];
    final x = _lineX(lineIndex, outfieldLines);
    for (var i = 0; i < count; i++) {
      final role = spec.roles[roleIndex];
      spots.add(
        FormationSpot(
          role: role,
          number: _numberForRole(role, spots.length),
          x: x,
          y: _lineY(i, count),
        ),
      );
      roleIndex++;
    }
  }
  return spots.take(11).toList(growable: false);
}

double _lineX(int index, int lineCount) {
  if (lineCount == 1) {
    return 0.52;
  }
  const defensive = 0.17;
  const attacking = 0.76;
  return defensive + (attacking - defensive) * (index / (lineCount - 1));
}

double _lineY(int index, int count) {
  if (count == 1) {
    return 0.50;
  }
  final top = count >= 5 ? 0.16 : 0.20;
  final bottom = count >= 5 ? 0.84 : 0.80;
  return top + (bottom - top) * (index / (count - 1));
}

int _numberForRole(PlayerRole role, int fallback) {
  return switch (role) {
        PlayerRole.goalkeeper => 1,
        PlayerRole.rightBack => 2,
        PlayerRole.leftBack => 3,
        PlayerRole.rightWingBack => 2,
        PlayerRole.leftWingBack => 3,
        PlayerRole.centerBackLeft => 4,
        PlayerRole.centerBackRight => 5,
        PlayerRole.sweeper => 6,
        PlayerRole.defensiveMidfielder => 6,
        PlayerRole.rightWing => 7,
        PlayerRole.midfieldLeft => 8,
        PlayerRole.striker => 9,
        PlayerRole.midfieldRight => 10,
        PlayerRole.attackingMidfielder => 10,
        PlayerRole.leftWing => 11,
      } +
      fallback ~/ 11;
}
