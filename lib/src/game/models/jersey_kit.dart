import 'dart:ui';

/// A complete jersey kit for a team.
class JerseyKit {
  const JerseyKit({
    required this.name,
    required this.shirtColor,
    required this.shortsColor,
    required this.socksColor,
    required this.numberColor,
    required this.goalkeeperShirtColor,
    this.isCustom = false,
  });

  final String name;
  final Color shirtColor;
  final Color shortsColor;
  final Color socksColor;
  final Color numberColor;
  final Color goalkeeperShirtColor;

  /// True for kits created by the user (they can be edited and deleted).
  /// Ready-made kits shipped with the game can also be removed from a team,
  /// but they are never re-created on load once the user deleted them.
  final bool isCustom;

  JerseyKit copyWith({
    String? name,
    Color? shirtColor,
    Color? shortsColor,
    Color? socksColor,
    Color? numberColor,
    Color? goalkeeperShirtColor,
    bool? isCustom,
  }) {
    return JerseyKit(
      name: name ?? this.name,
      shirtColor: shirtColor ?? this.shirtColor,
      shortsColor: shortsColor ?? this.shortsColor,
      socksColor: socksColor ?? this.socksColor,
      numberColor: numberColor ?? this.numberColor,
      goalkeeperShirtColor: goalkeeperShirtColor ?? this.goalkeeperShirtColor,
      isCustom: isCustom ?? this.isCustom,
    );
  }

  /// Preview of the kit colors.
  String get description =>
      'Forma: $_colorName(shirtColor), Sort: $_colorName(shortsColor)';

  static String _colorName(Color c) {
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    if (r > 200 && g < 80 && b < 80) return 'Kirmizi';
    if (r < 80 && g > 180 && b < 80) return 'Yesil';
    if (r < 80 && g < 80 && b > 180) return 'Mavi';
    if (r > 200 && g > 180 && b < 80) return 'Sari';
    if (r > 200 && g > 100 && b < 50) return 'Turuncu';
    if (r < 60 && g < 60 && b < 60) return 'Siyah';
    if (r > 220 && g > 220 && b > 220) return 'Beyaz';
    if (r > 120 && g < 60 && b > 120) return 'Mor';
    if (r > 200 && g > 150 && b > 150) return 'Pembe';
    if (r < 80 && g > 150 && b > 150) return 'Turkuaz';
    if (r > 100 && g > 100 && b < 60) return 'Zeytin';
    return 'Ozel';
  }

  factory JerseyKit.fromJson(Map<String, dynamic> json) {
    return JerseyKit(
      name: json['name'] as String? ?? 'Forma',
      isCustom: json['isCustom'] as bool? ?? false,
      shirtColor: Color(json['shirtColor'] as int? ?? 0xffffffff),
      shortsColor: Color(json['shortsColor'] as int? ?? 0xff000000),
      socksColor: Color(json['socksColor'] as int? ?? 0xffffffff),
      numberColor: Color(json['numberColor'] as int? ?? 0xffffffff),
      goalkeeperShirtColor:
          Color(json['goalkeeperShirtColor'] as int? ?? 0xff00ff00),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'isCustom': isCustom,
        'shirtColor': shirtColor.toARGB32(),
        'shortsColor': shortsColor.toARGB32(),
        'socksColor': socksColor.toARGB32(),
        'numberColor': numberColor.toARGB32(),
        'goalkeeperShirtColor': goalkeeperShirtColor.toARGB32(),
      };
}

/// Predefined team kits for quick selection.
class JerseyFactory {
  static List<JerseyKit> defaultKits() => [
        // Home kit
        const JerseyKit(
          name: 'Ic Saha (Ev)',
          shirtColor: Color(0xffe53935),
          shortsColor: Color(0xff1a1a1a),
          socksColor: Color(0xffe53935),
          numberColor: Color(0xffffffff),
          goalkeeperShirtColor: Color(0xff00c853),
        ),
        // Away kit
        const JerseyKit(
          name: 'Dis Saha (Deplasman)',
          shirtColor: Color(0xffffffff),
          shortsColor: Color(0xffffffff),
          socksColor: Color(0xffffffff),
          numberColor: Color(0xff1a1a1a),
          goalkeeperShirtColor: Color(0xffff6d00),
        ),
        // Third kit
        const JerseyKit(
          name: 'Alternatif',
          shirtColor: Color(0xff1a237e),
          shortsColor: Color(0xff1a237e),
          socksColor: Color(0xff1a237e),
          numberColor: Color(0xffffffff),
          goalkeeperShirtColor: Color(0xffffd600),
        ),
        const JerseyKit(
          name: 'Siyah Altin',
          shirtColor: Color(0xff111111),
          shortsColor: Color(0xffd4af37),
          socksColor: Color(0xff111111),
          numberColor: Color(0xffffd54f),
          goalkeeperShirtColor: Color(0xff00bfa5),
        ),
        const JerseyKit(
          name: 'Zumrut Yesili',
          shirtColor: Color(0xff008f5a),
          shortsColor: Color(0xffffffff),
          socksColor: Color(0xff008f5a),
          numberColor: Color(0xffffffff),
          goalkeeperShirtColor: Color(0xffff7043),
        ),
        const JerseyKit(
          name: 'Mor Gece',
          shirtColor: Color(0xff5e35b1),
          shortsColor: Color(0xff1b103d),
          socksColor: Color(0xff7e57c2),
          numberColor: Color(0xffffffff),
          goalkeeperShirtColor: Color(0xffc6ff00),
        ),
        const JerseyKit(
          name: 'Turkuaz Dalga',
          shirtColor: Color(0xff00acc1),
          shortsColor: Color(0xff004d60),
          socksColor: Color(0xff00acc1),
          numberColor: Color(0xffffffff),
          goalkeeperShirtColor: Color(0xffff1744),
        ),
        const JerseyKit(
          name: 'Turuncu Alev',
          shirtColor: Color(0xffff6d00),
          shortsColor: Color(0xff212121),
          socksColor: Color(0xffff8f00),
          numberColor: Color(0xffffffff),
          goalkeeperShirtColor: Color(0xff00e676),
        ),
        const JerseyKit(
          name: 'Pembe Firtina',
          shirtColor: Color(0xffec407a),
          shortsColor: Color(0xff6a1b4d),
          socksColor: Color(0xfff48fb1),
          numberColor: Color(0xffffffff),
          goalkeeperShirtColor: Color(0xff2979ff),
        ),
        const JerseyKit(
          name: 'Bordo Klasik',
          shirtColor: Color(0xff7f1734),
          shortsColor: Color(0xfff5f5dc),
          socksColor: Color(0xff7f1734),
          numberColor: Color(0xffffffff),
          goalkeeperShirtColor: Color(0xffffd600),
        ),
        const JerseyKit(
          name: 'Neon Yesil',
          shirtColor: Color(0xff76ff03),
          shortsColor: Color(0xff263238),
          socksColor: Color(0xff76ff03),
          numberColor: Color(0xff101010),
          goalkeeperShirtColor: Color(0xffd500f9),
        ),
        const JerseyKit(
          name: 'Gok Mavisi',
          shirtColor: Color(0xff42a5f5),
          shortsColor: Color(0xffffffff),
          socksColor: Color(0xff90caf9),
          numberColor: Color(0xff0d47a1),
          goalkeeperShirtColor: Color(0xffffab00),
        ),
        const JerseyKit(
          name: 'Gumus Deplasman',
          shirtColor: Color(0xffb0bec5),
          shortsColor: Color(0xff37474f),
          socksColor: Color(0xffcfd8dc),
          numberColor: Color(0xff102027),
          goalkeeperShirtColor: Color(0xffe040fb),
        ),
      ];

  /// Merges the saved kits with the ready-made ones. Ready-made kits the
  /// user deleted are listed in [hiddenNames] and are never brought back.
  static List<JerseyKit> completeKits(
    Iterable<JerseyKit>? saved, {
    Iterable<String> hiddenNames = const <String>[],
  }) {
    final hidden = hiddenNames.toSet();
    final result = saved?.toList() ?? <JerseyKit>[];
    for (final kit in defaultKits()) {
      if (hidden.contains(kit.name)) {
        continue;
      }
      if (!result.any((existing) => existing.name == kit.name)) {
        result.add(kit);
      }
    }
    return result;
  }

  /// Colors offered when the user builds a new kit.
  static List<JerseyColor> palette() => const [
        JerseyColor('Beyaz', Color(0xfff5f7f5)),
        JerseyColor('Siyah', Color(0xff111418)),
        JerseyColor('Kirmizi', Color(0xffe53935)),
        JerseyColor('Bordo', Color(0xff7f1734)),
        JerseyColor('Lacivert', Color(0xff1a237e)),
        JerseyColor('Mavi', Color(0xff1565c0)),
        JerseyColor('Acik Mavi', Color(0xff42a5f5)),
        JerseyColor('Cam Gobegi', Color(0xff00acc1)),
        JerseyColor('Turkuaz', Color(0xff00e5d0)),
        JerseyColor('Yesil', Color(0xff2e7d32)),
        JerseyColor('Zumrut', Color(0xff008f5a)),
        JerseyColor('Neon Yesil', Color(0xff76ff03)),
        JerseyColor('Sari', Color(0xffffd600)),
        JerseyColor('Altin', Color(0xffd4af37)),
        JerseyColor('Turuncu', Color(0xffff6d00)),
        JerseyColor('Kahverengi', Color(0xff6d4c41)),
        JerseyColor('Mor', Color(0xff5e35b1)),
        JerseyColor('Mor Menekse', Color(0xff9c27b0)),
        JerseyColor('Pembe', Color(0xffec407a)),
        JerseyColor('Gumus', Color(0xffb0bec5)),
        JerseyColor('Gri', Color(0xff607d8b)),
        JerseyColor('Fildisi', Color(0xfffff8e1)),
        JerseyColor('Zeytin', Color(0xff827717)),
        JerseyColor('Lila', Color(0xffb39ddb)),
      ];

  static List<JerseyKit> redTeamKits() => [
        const JerseyKit(
          name: 'Ic Saha (Ev)',
          shirtColor: Color(0xff0a4f93),
          shortsColor: Color(0xff0a4f93),
          socksColor: Color(0xff0a4f93),
          numberColor: Color(0xffffffff),
          goalkeeperShirtColor: Color(0xff00e676),
        ),
        const JerseyKit(
          name: 'Dis Saha (Deplasman)',
          shirtColor: Color(0xffffffff),
          shortsColor: Color(0xff0a4f93),
          socksColor: Color(0xffffffff),
          numberColor: Color(0xff0a4f93),
          goalkeeperShirtColor: Color(0xffff1744),
        ),
        const JerseyKit(
          name: 'Alternatif',
          shirtColor: Color(0xffffd600),
          shortsColor: Color(0xff1a1a1a),
          socksColor: Color(0xffffd600),
          numberColor: Color(0xff1a1a1a),
          goalkeeperShirtColor: Color(0xff00b0ff),
        ),
      ];
}

/// A named color offered in the kit editor.
class JerseyColor {
  const JerseyColor(this.name, this.color);

  final String name;
  final Color color;
}
