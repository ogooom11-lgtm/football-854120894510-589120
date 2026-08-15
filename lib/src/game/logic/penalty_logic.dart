import 'dart:math' as math;

import '../enums/player_role.dart';
import '../enums/team_id.dart';
import '../models/player_game.dart';
import '../models/team_game.dart';

enum PenaltyLane { leftLow, center, rightLow, leftHigh, rightHigh }

extension PenaltyLaneText on PenaltyLane {
  String get title => switch (this) {
    PenaltyLane.leftLow => 'Sol alt',
    PenaltyLane.center => 'Orta',
    PenaltyLane.rightLow => 'Sag alt',
    PenaltyLane.leftHigh => 'Sol ust',
    PenaltyLane.rightHigh => 'Sag ust',
  };

  String get sideTitle => switch (this) {
    PenaltyLane.leftLow || PenaltyLane.leftHigh => 'Sol',
    PenaltyLane.center => 'Orta',
    PenaltyLane.rightLow || PenaltyLane.rightHigh => 'Sag',
  };
}

class PenaltyKickResult {
  const PenaltyKickResult({
    required this.teamId,
    required this.shooterName,
    required this.goalkeeperName,
    required this.shotLane,
    required this.keeperLane,
    required this.heightMeters,
    required this.power,
    required this.scored,
    required this.minute,
  });

  final TeamId teamId;
  final String shooterName;
  final String goalkeeperName;
  final PenaltyLane shotLane;
  final PenaltyLane keeperLane;
  final double heightMeters;
  final double power;
  final bool scored;
  final int minute;

  String get summary =>
      '$shooterName: ${shotLane.title}, ${heightMeters.toStringAsFixed(2)} m, kaleci ${keeperLane.sideTitle} - ${scored ? 'Gol' : 'Kurtaris'}';
}

class ActivePenalty {
  ActivePenalty({
    required this.shootingTeam,
    required this.shootout,
    required this.minute,
    required this.shooterId,
  });

  final TeamId shootingTeam;
  final bool shootout;
  final int minute;
  String shooterId;
  PenaltyLane shotDirection = PenaltyLane.center;
  PenaltyLane keeperDirection = PenaltyLane.center;
  double countdown = 0;
  double preparationTimer = 1.2;
  PenaltyKickResult? result;
}

class PenaltyShootout {
  PenaltyShootout({required this.firstTeam});

  final TeamId firstTeam;
  final List<PenaltyKickResult> results = [];

  int goalsFor(TeamId teamId) => results
      .where((result) => result.teamId == teamId && result.scored)
      .length;

  int takenBy(TeamId teamId) =>
      results.where((result) => result.teamId == teamId).length;

  TeamId get nextTeam {
    if (results.isEmpty) {
      return firstTeam;
    }
    final blueTaken = takenBy(TeamId.blue);
    final redTaken = takenBy(TeamId.red);
    if (blueTaken == redTaken) {
      return firstTeam;
    }
    return firstTeam.opponent;
  }

  bool get complete {
    final blueTaken = takenBy(TeamId.blue);
    final redTaken = takenBy(TeamId.red);
    final blueGoals = goalsFor(TeamId.blue);
    final redGoals = goalsFor(TeamId.red);
    final blueRemaining = (5 - blueTaken).clamp(0, 5);
    final redRemaining = (5 - redTaken).clamp(0, 5);

    if (blueGoals > redGoals + redRemaining) {
      return true;
    }
    if (redGoals > blueGoals + blueRemaining) {
      return true;
    }
    if (blueTaken >= 5 && redTaken >= 5 && blueTaken == redTaken) {
      return blueGoals != redGoals;
    }
    return false;
  }

  TeamId? get winner {
    if (!complete) {
      return null;
    }
    return goalsFor(TeamId.blue) > goalsFor(TeamId.red)
        ? TeamId.blue
        : TeamId.red;
  }
}

class PenaltyLogic {
  PenaltyLogic(this.random);

  final math.Random random;

  PenaltyKickResult takeKick({
    required TeamGame shootingTeam,
    required TeamGame defendingTeam,
    required int kickIndex,
    required int minute,
  }) {
    final shooters =
        shootingTeam.players
            .where((player) => !player.isGoalkeeper && !player.isSentOff)
            .toList()
          ..sort((a, b) => _shooterValue(b).compareTo(_shooterValue(a)));
    final shooter = shooters[kickIndex % shooters.length];
    final keeper = defendingTeam.goalkeeper;
    final shotLane = _chooseShotLane(shooter);
    final keeperLane = _chooseKeeperLane(keeper, shotLane);
    return takeSelectedKick(
      shootingTeam: shootingTeam,
      defendingTeam: defendingTeam,
      kickIndex: kickIndex,
      minute: minute,
      shotDirection: shotLane,
      keeperDirection: keeperLane,
      power: 1.05 + random.nextDouble() * 0.45,
    );
  }

  PenaltyKickResult takeSelectedKick({
    required TeamGame shootingTeam,
    required TeamGame defendingTeam,
    required int kickIndex,
    required int minute,
    required PenaltyLane shotDirection,
    required PenaltyLane keeperDirection,
    required double power,
    PlayerGame? selectedShooter,
  }) {
    final shooters =
        shootingTeam.players
            .where((player) => !player.isGoalkeeper && !player.isSentOff)
            .toList()
          ..sort((a, b) => _shooterValue(b).compareTo(_shooterValue(a)));
    final shooter =
        selectedShooter != null &&
            selectedShooter.teamId == shootingTeam.id &&
            !selectedShooter.isGoalkeeper
        ? selectedShooter
        : shooters[kickIndex % shooters.length];
    final keeper = defendingTeam.goalkeeper;
    final clampedPower = power.clamp(0.55, 1.65).toDouble();
    final height = _heightFromPower(clampedPower, shotDirection);
    final shotLane = _laneWithHeight(shotDirection, height);
    final guessed = _sameSide(shotLane, keeperDirection);
    final keeperStats = keeper.profile.goalkeeperStats;
    final saveSkill = keeperStats.reaction * 0.36 +
        keeperStats.diving * 0.28 +
        keeperStats.oneVsOne * 0.24 +
        keeperStats.positioning * 0.12;
    final highRisk = height > 1.65;
    final tooHigh = height > 2.44;
    final tooWeak = clampedPower < 0.72;
    // A good finisher very rarely misses the frame — the miss chance is
    // small and scales strongly with skill.
    final missChance =
        (tooHigh ? 0.30 : 0.02) +
        (highRisk ? 0.05 : 0) +
        (tooWeak ? 0.03 : 0) +
        (1 - shooter.profile.finishingSkill) * 0.07 +
        (1 - shooter.profile.composureSkill) * 0.08;
    final saveChance = guessed
        ? (height > 1.55 ? 0.24 : 0.20) + saveSkill * 0.14
        : (keeperDirection == PenaltyLane.center &&
                  shotLane == PenaltyLane.center
              ? 0.16 + saveSkill * 0.10
              : 0.03 + saveSkill * 0.05);
    final shooterBonus =
        (shooter.profile.heightMeters - 1.70) * 0.32 +
        shooter.profile.finishingSkill * 0.16 +
        shooter.profile.composureSkill * 0.14 +
        shooter.profile.shotSkill * 0.07 +
        (shooter.role.isAttacker ? 0.05 : 0);
    final keeperBonus =
        (keeper.profile.heightMeters - 1.70) * 0.16 + saveSkill * 0.08;
    final scored =
        random.nextDouble() >
        (missChance + saveChance + keeperBonus - shooterBonus).clamp(
          0.03,
          0.72,
        );

    return PenaltyKickResult(
      teamId: shootingTeam.id,
      shooterName: shooter.profile.name,
      goalkeeperName: keeper.profile.name,
      shotLane: shotLane,
      keeperLane: keeperDirection,
      heightMeters: height,
      power: clampedPower,
      scored: scored,
      minute: minute,
    );
  }

  double _shooterValue(PlayerGame player) {
    final roleBonus = player.role.isAttacker
        ? 0.35
        : player.role.isWide
        ? 0.18
        : 0.08;
    return roleBonus +
        player.profile.heightMeters +
        player.profile.finishingSkill * 0.34 +
        player.profile.composureSkill * 0.26 +
        random.nextDouble() * 0.18;
  }

  PenaltyLane _chooseShotLane(PlayerGame shooter) {
    final highChance =
        (shooter.role.isAttacker ? 0.18 : 0.10) +
        shooter.profile.shotSkill * 0.08;
    if (random.nextDouble() < highChance) {
      return random.nextBool() ? PenaltyLane.leftHigh : PenaltyLane.rightHigh;
    }
    final roll = random.nextDouble();
    if (roll < 0.42) {
      return PenaltyLane.leftLow;
    }
    if (roll < 0.84) {
      return PenaltyLane.rightLow;
    }
    return PenaltyLane.center;
  }

  PenaltyLane _chooseKeeperLane(PlayerGame keeper, PenaltyLane shotLane) {
    final stats = keeper.profile.goalkeeperStats;
    final readSkill = stats.reaction * 0.40 +
        stats.anticipation * 0.34 +
        stats.oneVsOne * 0.26;
    final readChance =
        0.10 +
        (keeper.profile.heightMeters - 1.70) * 0.35 +
        readSkill * 0.36;
    if (random.nextDouble() < readChance) {
      return shotLane;
    }
    return PenaltyLane.values[random.nextInt(PenaltyLane.values.length)];
  }

  bool _sameSide(PenaltyLane a, PenaltyLane b) {
    if (a == PenaltyLane.center || b == PenaltyLane.center) {
      return a == b;
    }
    final aLeft = a == PenaltyLane.leftLow || a == PenaltyLane.leftHigh;
    final bLeft = b == PenaltyLane.leftLow || b == PenaltyLane.leftHigh;
    return aLeft == bLeft;
  }

  double _heightFromPower(double power, PenaltyLane direction) {
    if (direction == PenaltyLane.center) {
      return 0.35 + (power - 0.55) / 1.10 * 1.05;
    }
    return 0.45 + (power - 0.55) / 1.10 * 2.25;
  }

  PenaltyLane _laneWithHeight(PenaltyLane direction, double height) {
    if (direction == PenaltyLane.center) {
      return PenaltyLane.center;
    }
    final left =
        direction == PenaltyLane.leftLow || direction == PenaltyLane.leftHigh;
    if (height > 1.50) {
      return left ? PenaltyLane.leftHigh : PenaltyLane.rightHigh;
    }
    return left ? PenaltyLane.leftLow : PenaltyLane.rightLow;
  }
}
