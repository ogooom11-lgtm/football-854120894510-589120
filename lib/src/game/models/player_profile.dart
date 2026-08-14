import 'dart:math' as math;

class PlayerMatchRecord {
  const PlayerMatchRecord({
    required this.matchId,
    required this.teamName,
    required this.opponentName,
    required this.scoreText,
    required this.minutes,
    required this.goals,
    required this.assists,
    required this.passes,
    required this.successfulPasses,
    required this.dribbles,
    required this.successfulDribbles,
    required this.tackles,
    required this.shots,
    required this.shotsOnTarget,
    required this.missedChances,
    required this.clearances,
    required this.saves,
    required this.foulsCommitted,
    required this.foulsReceived,
    required this.rating,
    required this.injured,
  });

  final String matchId;
  final String teamName;
  final String opponentName;
  final String scoreText;
  final int minutes;
  final int goals;
  final int assists;
  final int passes;
  final int successfulPasses;
  final int dribbles;
  final int successfulDribbles;
  final int tackles;
  final int shots;
  final int shotsOnTarget;
  final int missedChances;
  final int clearances;
  final int saves;
  final int foulsCommitted;
  final int foulsReceived;
  final double rating;
  final bool injured;

  factory PlayerMatchRecord.fromJson(Map<String, dynamic> json) {
    return PlayerMatchRecord(
      matchId: json['matchId'] as String? ?? '',
      teamName: json['teamName'] as String? ?? '',
      opponentName: json['opponentName'] as String? ?? '',
      scoreText: json['scoreText'] as String? ?? '',
      minutes: (json['minutes'] as num?)?.toInt() ?? 0,
      goals: (json['goals'] as num?)?.toInt() ?? 0,
      assists: (json['assists'] as num?)?.toInt() ?? 0,
      passes: (json['passes'] as num?)?.toInt() ?? 0,
      successfulPasses: (json['successfulPasses'] as num?)?.toInt() ?? 0,
      dribbles: (json['dribbles'] as num?)?.toInt() ?? 0,
      successfulDribbles: (json['successfulDribbles'] as num?)?.toInt() ?? 0,
      tackles: (json['tackles'] as num?)?.toInt() ?? 0,
      shots: (json['shots'] as num?)?.toInt() ?? 0,
      shotsOnTarget: (json['shotsOnTarget'] as num?)?.toInt() ?? 0,
      missedChances: (json['missedChances'] as num?)?.toInt() ?? 0,
      clearances: (json['clearances'] as num?)?.toInt() ?? 0,
      saves: (json['saves'] as num?)?.toInt() ?? 0,
      foulsCommitted: (json['foulsCommitted'] as num?)?.toInt() ?? 0,
      foulsReceived: (json['foulsReceived'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 6,
      injured: json['injured'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'matchId': matchId,
        'teamName': teamName,
        'opponentName': opponentName,
        'scoreText': scoreText,
        'minutes': minutes,
        'goals': goals,
        'assists': assists,
        'passes': passes,
        'successfulPasses': successfulPasses,
        'dribbles': dribbles,
        'successfulDribbles': successfulDribbles,
        'tackles': tackles,
        'shots': shots,
        'shotsOnTarget': shotsOnTarget,
        'missedChances': missedChances,
        'clearances': clearances,
        'saves': saves,
        'foulsCommitted': foulsCommitted,
        'foulsReceived': foulsReceived,
        'rating': double.parse(rating.toStringAsFixed(1)),
        'injured': injured,
      };
}

class PlayerProfile {
  PlayerProfile({
    required this.id,
    required this.name,
    required this.heightMeters,
    required this.isGoalkeeper,
    this.number,
    this.overallRating = 60,
    this.shootingRating = 60,
    this.passingRating = 60,
    this.goalkeepingRating = 45,
    this.speedRating = 60,
    this.staminaRating = 60,
    this.zekaGucu = 50,
    this.goals = 0,
    this.assists = 0,
    this.passes = 0,
    this.successfulPasses = 0,
    this.dribbles = 0,
    this.successfulDribbles = 0,
    this.tackles = 0,
    this.shots = 0,
    this.shotsOnTarget = 0,
    this.missedChances = 0,
    this.clearances = 0,
    this.saves = 0,
    this.foulsCommitted = 0,
    this.foulsReceived = 0,
    this.minutesPlayed = 0,
    this.matchesPlayed = 0,
    this.yellowCards = 0,
    this.redCards = 0,
    this.banMatches = 0,
    this.points = 0,
    this.injuredDaysRemaining = 0,
    this.fitness = 1.0,
    this.fitnessUpdatedAt = 0,
    List<PlayerMatchRecord>? matchHistory,
  }) : matchHistory = matchHistory ?? <PlayerMatchRecord>[];

  final String id;
  String name;
  final double heightMeters;
  final bool isGoalkeeper;
  final int? number;
  double overallRating;
  double shootingRating;
  double passingRating;
  double goalkeepingRating;
  double speedRating;
  double staminaRating;

  /// Zeka Gücü — AI decision intelligence derived from performance.
  /// 0-99 scale. Higher = smarter AI decisions for this player.
  double zekaGucu;

  int goals;
  int assists;
  int passes;
  int successfulPasses;
  int dribbles;
  int successfulDribbles;
  int tackles;
  int shots;
  int shotsOnTarget;
  int missedChances;
  int clearances;
  int saves;
  int foulsCommitted;
  int foulsReceived;
  int minutesPlayed;
  int matchesPlayed;
  double points;

  /// Toplam sari kart sayisi.
  int yellowCards;

  /// Toplam kirmizi kart sayisi.
  int redCards;

  /// Kalan ceza (men) mac sayisi. 0 = oynayabilir.
  int banMatches;

  /// Injury: number of days remaining before recovery. 0 = fit.
  int injuredDaysRemaining;

  /// Persistent match fitness. It recovers outside matches based on stamina.
  double fitness;
  int fitnessUpdatedAt;

  final List<PlayerMatchRecord> matchHistory;

  bool get isInjured => injuredDaysRemaining > 0;

  /// Cezali (men edilmis) mi?
  bool get isBanned => banMatches > 0;

  /// Sakat veya cezali oyuncu maca cikamaz.
  bool get isAvailable => !isInjured && !isBanned;

  /// Bir mac oynandiktan sonra ceza suresini bir azaltir.
  void serveBanMatch() {
    if (banMatches > 0) {
      banMatches -= 1;
    }
  }

  void recoverFitness(DateTime now) {
    if (fitnessUpdatedAt <= 0) {
      fitness = 1.0;
      fitnessUpdatedAt = now.millisecondsSinceEpoch;
      return;
    }
    final elapsedHours =
        (now.millisecondsSinceEpoch - fitnessUpdatedAt) / 3600000;
    if (elapsedHours <= 0) {
      return;
    }
    final days = elapsedHours / 24;
    final dailyRecovery = 0.14 + staminaSkill * 0.22;
    fitness = (fitness + days * dailyRecovery).clamp(0.18, 1.0).toDouble();
    fitnessUpdatedAt = now.millisecondsSinceEpoch;
  }

  double get effectiveOverall {
    final technical = isGoalkeeper
        ? goalkeepingRating * 0.48 +
            passingRating * 0.18 +
            speedRating * 0.14 +
            staminaRating * 0.20
        : shootingRating * 0.28 +
            passingRating * 0.30 +
            speedRating * 0.22 +
            staminaRating * 0.20;
    return ((overallRating + technical) / 2).clamp(1, 99).toDouble();
  }

  double get passSkill => (passingRating / 100).clamp(0.05, 0.99).toDouble();
  double get shotSkill => (shootingRating / 100).clamp(0.05, 0.99).toDouble();
  double get keeperSkill =>
      (goalkeepingRating / 100).clamp(0.05, 0.99).toDouble();
  double get speedSkill => (speedRating / 100).clamp(0.05, 0.99).toDouble();
  double get staminaSkill => (staminaRating / 100).clamp(0.05, 0.99).toDouble();
  double get zekaSkill => (zekaGucu / 100).clamp(0.1, 0.99).toDouble();

  /// Update zekaGücü based on recent match performance.
  void recalculateZekaGucu() {
    if (matchesPlayed == 0) {
      zekaGucu = 50;
      return;
    }
    final recent = matchHistory.take(10).toList();
    if (recent.isEmpty) {
      zekaGucu = 50;
      return;
    }
    var sum = 0.0;
    for (final record in recent) {
      sum += record.rating * 8.0 +
          record.goals * 3.5 +
          record.assists * 2.8 +
          (record.passes > 0
              ? (record.successfulPasses / record.passes) * 12
              : 0) +
          (record.dribbles > 0
              ? (record.successfulDribbles / record.dribbles) * 6
              : 0) +
          record.tackles * 1.8 +
          record.saves * 2.2 +
          record.minutes / 90 * 3;
    }
    zekaGucu = (sum / recent.length).clamp(10, 99).toDouble();
  }

  factory PlayerProfile.generated({
    required String name,
    required bool isGoalkeeper,
    math.Random? random,
  }) {
    final rng = random ?? math.Random();
    final height = 1.70 + rng.nextDouble() * 0.25;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final base = 48 + rng.nextDouble() * 28;
    return PlayerProfile(
      id: '$stamp-${rng.nextInt(999999)}',
      name: name.trim().isEmpty ? 'Oyuncu' : name.trim(),
      heightMeters: double.parse(height.toStringAsFixed(2)),
      isGoalkeeper: isGoalkeeper,
      number: rng.nextInt(98) + 1,
      overallRating: base,
      shootingRating: isGoalkeeper
          ? 28 + rng.nextDouble() * 22
          : base + rng.nextDouble() * 8 - 4,
      passingRating: base + rng.nextDouble() * 8 - 4,
      goalkeepingRating: isGoalkeeper
          ? base + 12 + rng.nextDouble() * 10
          : 20 + rng.nextDouble() * 18,
      speedRating: base + rng.nextDouble() * 12 - 6,
      staminaRating: base + rng.nextDouble() * 12 - 6,
      zekaGucu: 40 + rng.nextDouble() * 30,
    );
  }

  factory PlayerProfile.fromJson(Map<String, dynamic> json) {
    return PlayerProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      heightMeters: (json['heightMeters'] as num).toDouble(),
      isGoalkeeper: json['isGoalkeeper'] as bool? ?? false,
      number: (json['number'] as num?)?.toInt(),
      overallRating: (json['overallRating'] as num?)?.toDouble() ?? 60,
      shootingRating: (json['shootingRating'] as num?)?.toDouble() ?? 60,
      passingRating: (json['passingRating'] as num?)?.toDouble() ?? 60,
      goalkeepingRating:
          (json['goalkeepingRating'] as num?)?.toDouble() ?? 35,
      speedRating: (json['speedRating'] as num?)?.toDouble() ?? 60,
      staminaRating: (json['staminaRating'] as num?)?.toDouble() ?? 60,
      zekaGucu: (json['zekaGucu'] as num?)?.toDouble() ?? 50,
      goals: (json['goals'] as num?)?.toInt() ?? 0,
      assists: (json['assists'] as num?)?.toInt() ?? 0,
      passes: (json['passes'] as num?)?.toInt() ?? 0,
      successfulPasses: (json['successfulPasses'] as num?)?.toInt() ?? 0,
      dribbles: (json['dribbles'] as num?)?.toInt() ?? 0,
      successfulDribbles: (json['successfulDribbles'] as num?)?.toInt() ?? 0,
      tackles: (json['tackles'] as num?)?.toInt() ?? 0,
      shots: (json['shots'] as num?)?.toInt() ?? 0,
      shotsOnTarget: (json['shotsOnTarget'] as num?)?.toInt() ?? 0,
      missedChances: (json['missedChances'] as num?)?.toInt() ?? 0,
      clearances: (json['clearances'] as num?)?.toInt() ?? 0,
      saves: (json['saves'] as num?)?.toInt() ?? 0,
      foulsCommitted: (json['foulsCommitted'] as num?)?.toInt() ?? 0,
      foulsReceived: (json['foulsReceived'] as num?)?.toInt() ?? 0,
      minutesPlayed: (json['minutesPlayed'] as num?)?.toInt() ?? 0,
      matchesPlayed: (json['matchesPlayed'] as num?)?.toInt() ?? 0,
      yellowCards: (json['yellowCards'] as num?)?.toInt() ?? 0,
      redCards: (json['redCards'] as num?)?.toInt() ?? 0,
      banMatches: (json['banMatches'] as num?)?.toInt() ?? 0,
      points: (json['points'] as num?)?.toDouble() ?? 0,
      injuredDaysRemaining: (json['injuredDaysRemaining'] as num?)?.toInt() ?? 0,
      fitness: (json['fitness'] as num?)?.toDouble() ?? 1.0,
      fitnessUpdatedAt: (json['fitnessUpdatedAt'] as num?)?.toInt() ?? 0,
      matchHistory: (json['matchHistory'] as List<dynamic>? ?? const [])
          .map((item) =>
              PlayerMatchRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  void addMatchRecord(PlayerMatchRecord record) {
    matchHistory.insert(0, record);
    if (matchHistory.length > 80) {
      matchHistory.removeRange(80, matchHistory.length);
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'heightMeters': heightMeters,
        'isGoalkeeper': isGoalkeeper,
        'number': number,
        'overallRating': double.parse(overallRating.toStringAsFixed(1)),
        'shootingRating': double.parse(shootingRating.toStringAsFixed(1)),
        'passingRating': double.parse(passingRating.toStringAsFixed(1)),
        'goalkeepingRating': double.parse(goalkeepingRating.toStringAsFixed(1)),
        'speedRating': double.parse(speedRating.toStringAsFixed(1)),
        'staminaRating': double.parse(staminaRating.toStringAsFixed(1)),
        'zekaGucu': double.parse(zekaGucu.toStringAsFixed(1)),
        'goals': goals,
        'assists': assists,
        'passes': passes,
        'successfulPasses': successfulPasses,
        'dribbles': dribbles,
        'successfulDribbles': successfulDribbles,
        'tackles': tackles,
        'shots': shots,
        'shotsOnTarget': shotsOnTarget,
        'missedChances': missedChances,
        'clearances': clearances,
        'saves': saves,
        'foulsCommitted': foulsCommitted,
        'foulsReceived': foulsReceived,
        'minutesPlayed': minutesPlayed,
        'matchesPlayed': matchesPlayed,
        'yellowCards': yellowCards,
        'redCards': redCards,
        'banMatches': banMatches,
        'points': double.parse(points.toStringAsFixed(1)),
        'injuredDaysRemaining': injuredDaysRemaining,
        'fitness': double.parse(fitness.toStringAsFixed(3)),
        'fitnessUpdatedAt': fitnessUpdatedAt,
        'matchHistory': matchHistory.map((r) => r.toJson()).toList(),
      };
}
