import 'dart:math' as math;

import 'goalkeeper.dart';
import 'shooting.dart';

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
    required this.yellowCards,
    required this.redCards,
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
  final int yellowCards;
  final int redCards;
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
      yellowCards: (json['yellowCards'] as num?)?.toInt() ?? 0,
      redCards: (json['redCards'] as num?)?.toInt() ?? 0,
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
        'yellowCards': yellowCards,
        'redCards': redCards,
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
    this.finishingRating = 60,
    this.shotPowerRating = 65,
    this.longShotsRating = 55,
    this.curveRating = 50,
    this.composureRating = 55,
    this.balanceRating = 60,
    this.preferredFoot = PreferredFoot.right,
    this.weakFootRating = 3,
    this.passingRating = 60,
    this.goalkeepingRating = 45,
    this.goalkeeperReactionRating = 60,
    this.goalkeeperPositioningRating = 60,
    this.goalkeeperDivingRating = 60,
    this.goalkeeperHandlingRating = 58,
    this.goalkeeperCatchingRating = 55,
    this.goalkeeperJumpingRating = 60,
    this.goalkeeperDecisionRating = 55,
    this.goalkeeperOneVsOneRating = 60,
    this.goalkeeperHighBallsRating = 55,
    this.goalkeeperComposureRating = 58,
    this.goalkeeperAccelerationRating = 60,
    this.goalkeeperReachRating = 60,
    this.goalkeeperFootworkRating = 60,
    this.goalkeeperAnticipationRating = 60,
    this.goalkeeperParryingRating = 58,
    this.goalkeeperDistributionRating = 60,
    this.speedRating = 60,
    this.staminaRating = 60,
    this.dayaniklilikGucu = 60,
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
    this.yellowCards = 0,
    this.redCards = 0,
    this.suspendedMatchesRemaining = 0,
    this.minutesPlayed = 0,
    this.matchesPlayed = 0,
    this.points = 0,
    this.injuredDaysRemaining = 0,
    this.fitness = 1.0,
    this.fitnessUpdatedAt = 0,
    this.marketValue = 1000000000,
    this.injuryUpdatedAt = 0,
    this.country = 'غير محدد',
    List<PlayerMatchRecord>? matchHistory,
  }) : matchHistory = matchHistory ?? <PlayerMatchRecord>[];

  final String id;
  String name;

  /// The player's national country (مطلب الدول). Managed and assigned from
  /// the admin section; shown on the player pages.
  String country;
  final double heightMeters;
  final bool isGoalkeeper;
  int? number;
  double overallRating;
  double shootingRating;
  double finishingRating;
  double shotPowerRating;
  double longShotsRating;
  double curveRating;
  double composureRating;
  double balanceRating;
  PreferredFoot preferredFoot;
  int weakFootRating;
  double passingRating;
  double goalkeepingRating;
  double goalkeeperReactionRating;
  double goalkeeperPositioningRating;
  double goalkeeperDivingRating;
  double goalkeeperHandlingRating;
  double goalkeeperCatchingRating;
  double goalkeeperJumpingRating;
  double goalkeeperDecisionRating;
  double goalkeeperOneVsOneRating;
  double goalkeeperHighBallsRating;
  double goalkeeperComposureRating;
  double goalkeeperAccelerationRating;
  double goalkeeperReachRating;
  double goalkeeperFootworkRating;
  double goalkeeperAnticipationRating;
  double goalkeeperParryingRating;
  double goalkeeperDistributionRating;
  double speedRating;
  double staminaRating;

  /// Dayaniklilik Gücü — resistance to injuries and recovery quality.
  /// Higher values reduce injury probability and shorten recovery time.
  double dayaniklilikGucu;

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
  int yellowCards;
  int redCards;

  /// Number of team matches the player must still miss.
  int suspendedMatchesRemaining;

  /// Ban counter used by the standalone penalties page
  /// (penalties_page.dart). Kept in sync with
  /// [suspendedMatchesRemaining] so a ban really prevents the player
  /// from playing.
  int get banMatches => suspendedMatchesRemaining;
  set banMatches(int value) {
    suspendedMatchesRemaining = value.clamp(0, 99).toInt();
  }

  /// Whether the player is currently banned from matches.
  bool get isBanned => suspendedMatchesRemaining > 0;

  int minutesPlayed;
  int matchesPlayed;
  double points;

  /// Injury: number of days remaining before recovery. 0 = fit.
  int injuredDaysRemaining;

  /// Persistent match fitness. It recovers outside matches based on stamina.
  double fitness;
  int fitnessUpdatedAt;

  /// Piyasa degeri (market value). Every player starts at 1 billion and the
  /// value goes up/down based on his performances when the market update
  /// is applied from the admin page.
  double marketValue;

  /// Timestamp (ms) of the last daily injury recovery, so injured players
  /// lose one injury day per real day that passes.
  int injuryUpdatedAt;

  final List<PlayerMatchRecord> matchHistory;

  bool get isInjured => injuredDaysRemaining > 0;
  bool get isSuspended => suspendedMatchesRemaining > 0;
  bool get isUnavailable => isInjured || isSuspended;

  /// Isabetli sut yuzdesi: shots on target / total shots.
  int get shootingAccuracyPercent => shots == 0
      ? 0
      : (shotsOnTarget * 100 / shots).round().clamp(0, 100).toInt();

  /// Applies a small, performance-driven drift to the player's attributes
  /// after a played match. Great performances nudge finishing, composure
  /// and intelligence up; poor ones nudge them down. Deliberately tiny so
  /// careers evolve gradually instead of swinging.
  void applyMatchDevelopment({
    required double rating,
    required int matchGoals,
    required int matchAssists,
    required int matchShotsOnTarget,
    required int matchSuccessfulPasses,
    required int matchPasses,
    required int matchFoulsCommitted,
    required int matchSaves,
  }) {
    double drift(double current, double delta) =>
        current.clamp(30, 99).toDouble() + delta <= 99 &&
                current.clamp(30, 99).toDouble() + delta >= 30
            ? current + delta
            : current;

    final form = (rating - 6.5) * 0.045;
    shootingRating = drift(shootingRating, form);
    finishingRating = drift(
      finishingRating,
      form + matchGoals * 0.06 + matchShotsOnTarget * 0.012,
    );
    shotPowerRating = drift(shotPowerRating, matchGoals * 0.025);
    composureRating = drift(composureRating, form * 0.6);
    final passRate =
        matchPasses == 0 ? 0.0 : matchSuccessfulPasses / matchPasses;
    passingRating = drift(
      passingRating,
      (passRate - 0.72) * 0.10 + matchAssists * 0.03,
    );
    if (isGoalkeeper) {
      goalkeepingRating = drift(goalkeepingRating, matchSaves * 0.02 + form * 0.5);
      goalkeeperHandlingRating = drift(goalkeeperHandlingRating, matchSaves * 0.015);
    }
    if (matchFoulsCommitted >= 3) {
      composureRating = drift(composureRating, -0.05);
    }
    // A gentle market-value response to form (±2% at the extremes).
    if (rating >= 7.8) {
      marketValue = (marketValue * 1.02).clamp(1e6, 5e9).toDouble();
    } else if (rating < 5.8) {
      marketValue = (marketValue * 0.985).clamp(1e6, 5e9).toDouble();
    }
  }

  /// Advances injury recovery and disciplinary suspension by one team match.
  void advanceUnavailableStatusAfterTeamMatch() {
    if (injuredDaysRemaining > 0) {
      final recoveryDays = (5 + dayaniklilikSkill * 5).round();
      injuredDaysRemaining = math.max(
        0,
        injuredDaysRemaining - recoveryDays,
      ).toInt();
    }
    if (suspendedMatchesRemaining > 0) {
      suspendedMatchesRemaining -= 1;
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

  /// Every real day that passes removes one injury day. Returns true when
  /// the remaining injury days actually changed (so the caller can save).
  bool recoverInjuryDays(DateTime now) {
    final nowMs = now.millisecondsSinceEpoch;
    if (injuredDaysRemaining <= 0) {
      injuryUpdatedAt = nowMs;
      return false;
    }
    if (injuryUpdatedAt <= 0) {
      injuryUpdatedAt = nowMs;
      return false;
    }
    final elapsedDays =
        ((nowMs - injuryUpdatedAt) / Duration.millisecondsPerDay).floor();
    if (elapsedDays <= 0) {
      return false;
    }
    injuredDaysRemaining = math.max(
      0,
      injuredDaysRemaining - elapsedDays,
    ).toInt();
    injuryUpdatedAt = nowMs;
    return true;
  }

  /// Base market value for every player: 1 billion.
  static const double baseMarketValue = 1000000000;
  static const double minMarketValue = 1000;
  static const double maxMarketValue = 100000000000;

  /// Recalculates the piyasa degeri based on the player's performances.
  /// [strong] applies bigger swings using the full career; the light mode
  /// only looks at the last few matches and makes small adjustments.
  /// Players who have never played stay at exactly 1 billion.
  void recalculateMarketValue({required bool strong}) {
    if (matchesPlayed <= 0) {
      marketValue = baseMarketValue;
      return;
    }
    final ovr = effectiveOverall;
    final skillFactor = (0.50 + (ovr - 50) * 0.032).clamp(0.35, 2.6);
    final recent = matchHistory.take(strong ? 10 : 5).toList();
    var formFactor = 1.0;
    if (recent.isNotEmpty) {
      final avgRating =
          recent.map((r) => r.rating).reduce((a, b) => a + b) / recent.length;
      final delta = avgRating - 6.0;
      formFactor = strong ? 1 + delta * 0.22 : 1 + delta * 0.08;
    }
    final minutes = math.max(1, minutesPlayed);
    final games = math.max(1, matchesPlayed);
    final goalsPer90 = goals / (minutes / 90);
    final assistsPer90 = assists / (minutes / 90);
    final production = isGoalkeeper
        ? saves / (minutes / 90) * 0.35 + (points / games) * 0.15
        : goalsPer90 * 1.1 + assistsPer90 * 0.55 + (points / games) * 0.10;
    final perfFactor = strong ? 1 + production * 0.30 : 1 + production * 0.10;
    final careerFactor =
        strong ? (1 + (points / games - 6.0) * 0.05) : 1.0;
    final value =
        baseMarketValue *
        skillFactor *
        formFactor *
        perfFactor *
        careerFactor;
    marketValue = value.clamp(minMarketValue, maxMarketValue).toDouble();
  }

  /// Compact market value text: "1.00 Mr" (milyar), "850 Mn" (milyon),
  /// "12 B" (bin).
  String get marketValueText {
    final v = marketValue;
    if (v >= 1000000000) {
      final b = v / 1000000000;
      return '${b.toStringAsFixed(b >= 10 ? 0 : 2)} Mr';
    }
    if (v >= 1000000) {
      final m = v / 1000000;
      return '${m.toStringAsFixed(m >= 10 ? 0 : 1)} Mn';
    }
    return '${v.round()} B';
  }

  /// Full market value with thousand separators, e.g. 1.250.000.000.
  String get marketValueFull {
    final digits = marketValue.round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  double get effectiveOverall {
    final technical = isGoalkeeper
        ? goalkeeperStats.composite * 100 * 0.48 +
            passingRating * 0.18 +
            speedRating * 0.14 +
            staminaRating * 0.20
        : shootingStats.composite * 100 * 0.28 +
            passingRating * 0.30 +
            speedRating * 0.22 +
            staminaRating * 0.20;
    return ((overallRating + technical) / 2).clamp(1, 99).toDouble();
  }

  double get passSkill => (passingRating / 100).clamp(0.05, 0.99).toDouble();
  double get shotSkill => (shootingRating / 100).clamp(0.05, 0.99).toDouble();
  double get finishingSkill =>
      (finishingRating / 100).clamp(0.05, 0.99).toDouble();
  double get shotPowerSkill =>
      (shotPowerRating / 100).clamp(0.05, 0.99).toDouble();
  double get longShotsSkill =>
      (longShotsRating / 100).clamp(0.05, 0.99).toDouble();
  double get curveSkill => (curveRating / 100).clamp(0.05, 0.99).toDouble();
  double get composureSkill =>
      (composureRating / 100).clamp(0.05, 0.99).toDouble();
  double get balanceSkill =>
      (balanceRating / 100).clamp(0.05, 0.99).toDouble();
  PlayerShootingStats get shootingStats => PlayerShootingStats(
    shooting: shotSkill,
    finishing: finishingSkill,
    shotPower: shotPowerSkill,
    longShots: longShotsSkill,
    curve: curveSkill,
    composure: composureSkill,
    balance: balanceSkill,
    preferredFoot: preferredFoot,
    weakFoot: weakFootRating.clamp(1, 5).toInt(),
  );
  double get keeperSkill =>
      (goalkeepingRating / 100).clamp(0.05, 0.99).toDouble();
  GoalkeeperStats get goalkeeperStats => GoalkeeperStats(
    reaction: (goalkeeperReactionRating / 100).clamp(0.05, 0.99).toDouble(),
    positioning:
        (goalkeeperPositioningRating / 100).clamp(0.05, 0.99).toDouble(),
    diving: (goalkeeperDivingRating / 100).clamp(0.05, 0.99).toDouble(),
    handling: (goalkeeperHandlingRating / 100).clamp(0.05, 0.99).toDouble(),
    catching: (goalkeeperCatchingRating / 100).clamp(0.05, 0.99).toDouble(),
    jumping: (goalkeeperJumpingRating / 100).clamp(0.05, 0.99).toDouble(),
    decision: (goalkeeperDecisionRating / 100).clamp(0.05, 0.99).toDouble(),
    oneVsOne:
        (goalkeeperOneVsOneRating / 100).clamp(0.05, 0.99).toDouble(),
    highBalls:
        (goalkeeperHighBallsRating / 100).clamp(0.05, 0.99).toDouble(),
    composure:
        (goalkeeperComposureRating / 100).clamp(0.05, 0.99).toDouble(),
    speed: speedSkill,
    acceleration:
        (goalkeeperAccelerationRating / 100).clamp(0.05, 0.99).toDouble(),
    reach: (goalkeeperReachRating / 100).clamp(0.05, 0.99).toDouble(),
    footwork: (goalkeeperFootworkRating / 100).clamp(0.05, 0.99).toDouble(),
    anticipation:
        (goalkeeperAnticipationRating / 100).clamp(0.05, 0.99).toDouble(),
    parrying:
        (goalkeeperParryingRating / 100).clamp(0.05, 0.99).toDouble(),
    distribution:
        (goalkeeperDistributionRating / 100).clamp(0.05, 0.99).toDouble(),
  );
  double get speedSkill => (speedRating / 100).clamp(0.05, 0.99).toDouble();
  double get staminaSkill => (staminaRating / 100).clamp(0.05, 0.99).toDouble();
  double get dayaniklilikSkill =>
      (dayaniklilikGucu / 100).clamp(0.05, 0.99).toDouble();
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
    final shooting = isGoalkeeper
        ? 28 + rng.nextDouble() * 22
        : base + rng.nextDouble() * 8 - 4;
    final keeperRating = isGoalkeeper
        ? base + 12 + rng.nextDouble() * 10
        : 20 + rng.nextDouble() * 18;
    double keeperVariation(double offset) =>
        (keeperRating + offset + rng.nextDouble() * 8 - 4)
            .clamp(15, 97)
            .toDouble();
    return PlayerProfile(
      id: '$stamp-${rng.nextInt(999999)}',
      name: name.trim().isEmpty ? 'Oyuncu' : name.trim(),
      heightMeters: double.parse(height.toStringAsFixed(2)),
      isGoalkeeper: isGoalkeeper,
      number: rng.nextInt(98) + 1,
      overallRating: base,
      shootingRating: shooting,
      finishingRating: (shooting + rng.nextDouble() * 10 - 5)
          .clamp(20, 96)
          .toDouble(),
      shotPowerRating: (shooting + 7 + rng.nextDouble() * 8 - 4)
          .clamp(25, 97)
          .toDouble(),
      longShotsRating: (shooting - 8 + rng.nextDouble() * 10 - 5)
          .clamp(15, 95)
          .toDouble(),
      curveRating: (shooting - 10 + rng.nextDouble() * 14 - 7)
          .clamp(12, 95)
          .toDouble(),
      composureRating: (base + rng.nextDouble() * 14 - 6)
          .clamp(20, 96)
          .toDouble(),
      balanceRating: (base + rng.nextDouble() * 12 - 5)
          .clamp(25, 96)
          .toDouble(),
      preferredFoot: rng.nextDouble() < 0.24
          ? PreferredFoot.left
          : PreferredFoot.right,
      weakFootRating: 1 + rng.nextInt(5),
      passingRating: base + rng.nextDouble() * 8 - 4,
      goalkeepingRating: keeperRating,
      goalkeeperReactionRating: keeperVariation(1),
      goalkeeperPositioningRating: keeperVariation(1),
      goalkeeperDivingRating: keeperVariation(1),
      goalkeeperHandlingRating: keeperVariation(-2),
      goalkeeperCatchingRating: keeperVariation(-3),
      goalkeeperJumpingRating: keeperVariation(0),
      goalkeeperDecisionRating: keeperVariation(-2),
      goalkeeperOneVsOneRating: keeperVariation(0),
      goalkeeperHighBallsRating: keeperVariation(-3),
      goalkeeperComposureRating: keeperVariation(-2),
      goalkeeperAccelerationRating: keeperVariation(-1),
      goalkeeperReachRating: keeperVariation(1),
      goalkeeperFootworkRating: keeperVariation(-1),
      goalkeeperAnticipationRating: keeperVariation(0),
      goalkeeperParryingRating: keeperVariation(-2),
      goalkeeperDistributionRating: keeperVariation(-2),
      speedRating: base + rng.nextDouble() * 12 - 6,
      staminaRating: base + rng.nextDouble() * 12 - 6,
      dayaniklilikGucu: (base + rng.nextDouble() * 18 - 7).clamp(25, 95).toDouble(),
      zekaGucu: 40 + rng.nextDouble() * 30,
    );
  }

  factory PlayerProfile.fromJson(Map<String, dynamic> json) {
    final shooting = (json['shootingRating'] as num?)?.toDouble() ?? 60;
    final overall = (json['overallRating'] as num?)?.toDouble() ?? 60;
    final stamina = (json['staminaRating'] as num?)?.toDouble() ?? 60;
    final intelligence = (json['zekaGucu'] as num?)?.toDouble() ?? 50;
    final goalkeeper =
        (json['goalkeepingRating'] as num?)?.toDouble() ?? 35;
    double goalkeeperValue(String key, [double offset = 0]) =>
        (json[key] as num?)?.toDouble() ??
        (goalkeeper + offset).clamp(10, 99).toDouble();
    return PlayerProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      heightMeters: (json['heightMeters'] as num).toDouble(),
      isGoalkeeper: json['isGoalkeeper'] as bool? ?? false,
      number: (json['number'] as num?)?.toInt(),
      overallRating: overall,
      shootingRating: shooting,
      finishingRating:
          (json['finishingRating'] as num?)?.toDouble() ?? shooting,
      shotPowerRating:
          (json['shotPowerRating'] as num?)?.toDouble() ??
          (shooting + 7).clamp(20, 99).toDouble(),
      longShotsRating:
          (json['longShotsRating'] as num?)?.toDouble() ??
          (shooting - 8).clamp(10, 99).toDouble(),
      curveRating:
          (json['curveRating'] as num?)?.toDouble() ??
          (shooting - 10).clamp(10, 99).toDouble(),
      composureRating:
          (json['composureRating'] as num?)?.toDouble() ?? intelligence,
      balanceRating:
          (json['balanceRating'] as num?)?.toDouble() ??
          ((overall + stamina) / 2).clamp(10, 99).toDouble(),
      preferredFoot: PreferredFoot.values.firstWhere(
        (foot) => foot.name == json['preferredFoot'],
        orElse: () => PreferredFoot.right,
      ),
      weakFootRating: ((json['weakFootRating'] as num?)?.toInt() ?? 3)
          .clamp(1, 5)
          .toInt(),
      passingRating: (json['passingRating'] as num?)?.toDouble() ?? 60,
      goalkeepingRating: goalkeeper,
      goalkeeperReactionRating: goalkeeperValue('goalkeeperReactionRating', 1),
      goalkeeperPositioningRating:
          goalkeeperValue('goalkeeperPositioningRating', 1),
      goalkeeperDivingRating: goalkeeperValue('goalkeeperDivingRating', 1),
      goalkeeperHandlingRating: goalkeeperValue('goalkeeperHandlingRating', -2),
      goalkeeperCatchingRating: goalkeeperValue('goalkeeperCatchingRating', -3),
      goalkeeperJumpingRating: goalkeeperValue('goalkeeperJumpingRating'),
      goalkeeperDecisionRating: goalkeeperValue('goalkeeperDecisionRating', -2),
      goalkeeperOneVsOneRating: goalkeeperValue('goalkeeperOneVsOneRating'),
      goalkeeperHighBallsRating:
          goalkeeperValue('goalkeeperHighBallsRating', -3),
      goalkeeperComposureRating:
          goalkeeperValue('goalkeeperComposureRating', -2),
      goalkeeperAccelerationRating:
          goalkeeperValue('goalkeeperAccelerationRating', -1),
      goalkeeperReachRating: goalkeeperValue('goalkeeperReachRating', 1),
      goalkeeperFootworkRating: goalkeeperValue('goalkeeperFootworkRating', -1),
      goalkeeperAnticipationRating:
          goalkeeperValue('goalkeeperAnticipationRating'),
      goalkeeperParryingRating: goalkeeperValue('goalkeeperParryingRating', -2),
      goalkeeperDistributionRating:
          goalkeeperValue('goalkeeperDistributionRating', -2),
      speedRating: (json['speedRating'] as num?)?.toDouble() ?? 60,
      staminaRating: (json['staminaRating'] as num?)?.toDouble() ?? 60,
      dayaniklilikGucu:
          (json['dayaniklilikGucu'] as num?)?.toDouble() ??
          (json['staminaRating'] as num?)?.toDouble() ??
          60,
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
      yellowCards: (json['yellowCards'] as num?)?.toInt() ?? 0,
      redCards: (json['redCards'] as num?)?.toInt() ?? 0,
      suspendedMatchesRemaining:
          (json['suspendedMatchesRemaining'] as num?)?.toInt() ?? 0,
      minutesPlayed: (json['minutesPlayed'] as num?)?.toInt() ?? 0,
      matchesPlayed: (json['matchesPlayed'] as num?)?.toInt() ?? 0,
      points: (json['points'] as num?)?.toDouble() ?? 0,
      injuredDaysRemaining: (json['injuredDaysRemaining'] as num?)?.toInt() ?? 0,
      fitness: (json['fitness'] as num?)?.toDouble() ?? 1.0,
      fitnessUpdatedAt: (json['fitnessUpdatedAt'] as num?)?.toInt() ?? 0,
      marketValue: (json['marketValue'] as num?)?.toDouble() ?? 1000000000,
      country: json['country'] as String? ?? 'غير محدد',
      injuryUpdatedAt: (json['injuryUpdatedAt'] as num?)?.toInt() ?? 0,
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
        'finishingRating': double.parse(finishingRating.toStringAsFixed(1)),
        'shotPowerRating': double.parse(shotPowerRating.toStringAsFixed(1)),
        'longShotsRating': double.parse(longShotsRating.toStringAsFixed(1)),
        'curveRating': double.parse(curveRating.toStringAsFixed(1)),
        'composureRating': double.parse(composureRating.toStringAsFixed(1)),
        'balanceRating': double.parse(balanceRating.toStringAsFixed(1)),
        'preferredFoot': preferredFoot.name,
        'weakFootRating': weakFootRating,
        'passingRating': double.parse(passingRating.toStringAsFixed(1)),
        'goalkeepingRating': double.parse(goalkeepingRating.toStringAsFixed(1)),
        'goalkeeperReactionRating':
            double.parse(goalkeeperReactionRating.toStringAsFixed(1)),
        'goalkeeperPositioningRating':
            double.parse(goalkeeperPositioningRating.toStringAsFixed(1)),
        'goalkeeperDivingRating':
            double.parse(goalkeeperDivingRating.toStringAsFixed(1)),
        'goalkeeperHandlingRating':
            double.parse(goalkeeperHandlingRating.toStringAsFixed(1)),
        'goalkeeperCatchingRating':
            double.parse(goalkeeperCatchingRating.toStringAsFixed(1)),
        'goalkeeperJumpingRating':
            double.parse(goalkeeperJumpingRating.toStringAsFixed(1)),
        'goalkeeperDecisionRating':
            double.parse(goalkeeperDecisionRating.toStringAsFixed(1)),
        'goalkeeperOneVsOneRating':
            double.parse(goalkeeperOneVsOneRating.toStringAsFixed(1)),
        'goalkeeperHighBallsRating':
            double.parse(goalkeeperHighBallsRating.toStringAsFixed(1)),
        'goalkeeperComposureRating':
            double.parse(goalkeeperComposureRating.toStringAsFixed(1)),
        'goalkeeperAccelerationRating':
            double.parse(goalkeeperAccelerationRating.toStringAsFixed(1)),
        'goalkeeperReachRating':
            double.parse(goalkeeperReachRating.toStringAsFixed(1)),
        'goalkeeperFootworkRating':
            double.parse(goalkeeperFootworkRating.toStringAsFixed(1)),
        'goalkeeperAnticipationRating':
            double.parse(goalkeeperAnticipationRating.toStringAsFixed(1)),
        'goalkeeperParryingRating':
            double.parse(goalkeeperParryingRating.toStringAsFixed(1)),
        'goalkeeperDistributionRating':
            double.parse(goalkeeperDistributionRating.toStringAsFixed(1)),
        'speedRating': double.parse(speedRating.toStringAsFixed(1)),
        'staminaRating': double.parse(staminaRating.toStringAsFixed(1)),
        'dayaniklilikGucu': double.parse(dayaniklilikGucu.toStringAsFixed(1)),
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
        'yellowCards': yellowCards,
        'redCards': redCards,
        'suspendedMatchesRemaining': suspendedMatchesRemaining,
        'minutesPlayed': minutesPlayed,
        'matchesPlayed': matchesPlayed,
        'points': double.parse(points.toStringAsFixed(1)),
        'injuredDaysRemaining': injuredDaysRemaining,
        'fitness': double.parse(fitness.toStringAsFixed(3)),
        'fitnessUpdatedAt': fitnessUpdatedAt,
        'marketValue': marketValue.round(),
        'injuryUpdatedAt': injuryUpdatedAt,
        'country': country,
        'matchHistory': matchHistory.map((r) => r.toJson()).toList(),
      };
}
