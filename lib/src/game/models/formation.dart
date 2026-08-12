import '../enums/player_role.dart';

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
  const _FormationSpec(this.title, this.lines);

  final String title;
  final List<int> lines;
}

const Map<FormationType, _FormationSpec> _formationSpecs = {
  FormationType.bus541: _FormationSpec('5-4-1 Otobus Cekme Sistemi', [5, 4, 1]),
  FormationType.kontrollu5311: _FormationSpec('5-3-1-1 Kontrollu Savunma', [
    5,
    3,
    1,
    1,
  ]),
  FormationType.midfield361: _FormationSpec('3-6-1 Orta Saha Duvari', [
    3,
    6,
    1,
  ]),
  FormationType.classic442: _FormationSpec('4-4-2 Klasik Ingiliz Sistemi', [
    4,
    4,
    2,
  ]),
  FormationType.modern4231: _FormationSpec('4-2-3-1 Modern Sistem', [
    4,
    2,
    3,
    1,
  ]),
  FormationType.wingback352: _FormationSpec('3-5-2 Kanat Bekli Sistem', [
    3,
    5,
    2,
  ]),
  FormationType.diamond41212: _FormationSpec('4-1-2-1-2 Elmas', [
    4,
    1,
    2,
    1,
    2,
  ]),
  FormationType.wing433: _FormationSpec('4-3-3 Kanat Hucum Sistemi', [4, 3, 3]),
  FormationType.magic4222: _FormationSpec('4-2-2-2 Sihirli Kare', [4, 2, 2, 2]),
  FormationType.narrow4312: _FormationSpec('4-3-1-2 Dar Elmas', [4, 3, 1, 2]),
  FormationType.total343: _FormationSpec('3-4-3 Total Hucum', [3, 4, 3]),
  FormationType.brazil424: _FormationSpec('4-2-4 Brezilya Sistemi', [4, 2, 4]),
  FormationType.false460: _FormationSpec('4-6-0 Sahte Forvetsiz Sistem', [
    4,
    6,
  ]),
  FormationType.bielsa3331: _FormationSpec('3-3-3-1 Bielsa Sistemi', [
    3,
    3,
    3,
    1,
  ]),
  FormationType.modern3241: _FormationSpec('3-2-4-1 Modern WM', [3, 2, 4, 1]),
  FormationType.pyramid235: _FormationSpec('2-3-5 Piramit', [2, 3, 5]),
  FormationType.metodo2323: _FormationSpec('2-3-2-3 Metodo', [2, 3, 2, 3]),
  FormationType.total1333: _FormationSpec('1-3-3-3 Total Futbol', [1, 3, 3, 3]),
  FormationType.christmas4321: _FormationSpec('4-3-2-1 Noel Agaci', [
    4,
    3,
    2,
    1,
  ]),
  FormationType.anchor4141: _FormationSpec('4-1-4-1 Tek On Libero', [
    4,
    1,
    4,
    1,
  ]),
  FormationType.support4411: _FormationSpec('4-4-1-1 Destek Forvetli Sistem', [
    4,
    4,
    1,
    1,
  ]),
  FormationType.counter523: _FormationSpec('5-2-3 Kanat Kontra Sistemi', [
    5,
    2,
    3,
  ]),
  FormationType.creators3421: _FormationSpec(
    '3-4-2-1 Cift Oyun Kuruculu Sistem',
    [3, 4, 2, 1],
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
    spots: _buildSpots(spec.lines),
  );
}

List<FormationSpot> _buildSpots(List<int> lines) {
  final spots = <FormationSpot>[
    const FormationSpot(
      role: PlayerRole.goalkeeper,
      number: 1,
      x: 0.03,
      y: 0.50,
    ),
  ];
  final outfieldLines = lines.length;
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final count = lines[lineIndex];
    final roles = _rolesForLine(lineIndex, outfieldLines, count);
    final x = _lineX(lineIndex, outfieldLines);
    for (var i = 0; i < count; i++) {
      spots.add(
        FormationSpot(
          role: roles[i],
          number: _numberForRole(roles[i], spots.length),
          x: x,
          y: _lineY(i, count),
        ),
      );
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

List<PlayerRole> _rolesForLine(int index, int lineCount, int count) {
  final isDefense = index == 0;
  final isAttack = index == lineCount - 1;
  if (isDefense) {
    return switch (count) {
      1 => [PlayerRole.sweeper],
      2 => [PlayerRole.centerBackLeft, PlayerRole.centerBackRight],
      3 => [
        PlayerRole.centerBackLeft,
        PlayerRole.sweeper,
        PlayerRole.centerBackRight,
      ],
      4 => [
        PlayerRole.leftWingBack,
        PlayerRole.centerBackLeft,
        PlayerRole.centerBackRight,
        PlayerRole.rightWingBack,
      ],
      _ => [
        PlayerRole.leftWingBack,
        PlayerRole.centerBackLeft,
        PlayerRole.sweeper,
        PlayerRole.centerBackRight,
        PlayerRole.rightWingBack,
      ],
    };
  }
  if (isAttack) {
    return switch (count) {
      1 => [PlayerRole.striker],
      2 => [PlayerRole.leftWing, PlayerRole.striker],
      3 => [PlayerRole.leftWing, PlayerRole.striker, PlayerRole.rightWing],
      4 => [
        PlayerRole.leftWing,
        PlayerRole.striker,
        PlayerRole.striker,
        PlayerRole.rightWing,
      ],
      _ => [
        PlayerRole.leftWing,
        PlayerRole.midfieldLeft,
        PlayerRole.striker,
        PlayerRole.midfieldRight,
        PlayerRole.rightWing,
      ],
    };
  }
  return switch (count) {
    1 => [PlayerRole.sweeper],
    2 => [PlayerRole.midfieldLeft, PlayerRole.midfieldRight],
    3 => [
      PlayerRole.midfieldLeft,
      PlayerRole.sweeper,
      PlayerRole.midfieldRight,
    ],
    4 => [
      PlayerRole.leftWing,
      PlayerRole.midfieldLeft,
      PlayerRole.midfieldRight,
      PlayerRole.rightWing,
    ],
    5 => [
      PlayerRole.leftWingBack,
      PlayerRole.midfieldLeft,
      PlayerRole.sweeper,
      PlayerRole.midfieldRight,
      PlayerRole.rightWingBack,
    ],
    _ => [
      PlayerRole.leftWingBack,
      PlayerRole.leftWing,
      PlayerRole.midfieldLeft,
      PlayerRole.sweeper,
      PlayerRole.midfieldRight,
      PlayerRole.rightWing,
    ],
  };
}

int _numberForRole(PlayerRole role, int fallback) {
  return switch (role) {
        PlayerRole.goalkeeper => 1,
        PlayerRole.rightWingBack => 2,
        PlayerRole.leftWingBack => 3,
        PlayerRole.centerBackLeft => 4,
        PlayerRole.centerBackRight => 5,
        PlayerRole.sweeper => 6,
        PlayerRole.rightWing => 7,
        PlayerRole.midfieldLeft => 8,
        PlayerRole.striker => 9,
        PlayerRole.midfieldRight => 10,
        PlayerRole.leftWing => 11,
      } +
      fallback ~/ 11;
}
