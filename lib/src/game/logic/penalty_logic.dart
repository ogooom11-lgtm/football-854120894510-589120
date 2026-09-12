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
    final saveSkill = keeperStats.reaction * 0.34 +
        keeperStats.diving * 0.30 +
        keeperStats.oneVsOne * 0.22 +
        keeperStats.positioning * 0.14;

    // Everything below is driven by the shooter's attributes and by the
    // power he chose — a penalty is never a guaranteed goal.
    final finishing = shooter.profile.finishingSkill; // bitiricilik
    final composure = shooter.profile.composureSkill; // soguk kanlilik
    final shotTechnique = shooter.profile.shotSkill;

    // Power cuts both ways: a soft penalty is easy to reach, a blasted one
    // sails over the bar. Both extremes are punished.
    final powerFromIdeal = (clampedPower - 1.08).abs() / 0.62;
    final powerRisk = powerFromIdeal.clamp(0.0, 1.0).toDouble();
    final highRisk = height > 1.85;
    final overTheBar = height > 2.44;
    final tooWeak = clampedPower < 0.72;

    final missChance = 0.028 + // woodwork / pure bad luck
        powerRisk * 0.095 + // badly struck
        (1 - finishing) * 0.105 + // bitiricilik
        (1 - shotTechnique) * 0.045 + // sut teknigi
        (1 - composure) * 0.055 + // baski altinda
        (highRisk ? 0.035 : 0.0) + // aiming high is risky
        (overTheBar ? 0.55 : 0.0) + // blazed over the bar
        (tooWeak ? 0.02 : 0.0);

    // Reaching the ball: high shots are harder to get to, hard shots leave
    // the keeper less time to react.
    final reachBonus = height > 1.90
        ? -0.14
        : height > 1.55
        ? -0.04
        : 0.05;
    final shotSpeedBonus = (clampedPower - 0.90) * 0.16;
    final saveChance = guessed
        ? (0.26 +
                saveSkill * 0.22 +
                reachBonus -
                shotSpeedBonus -
                (finishing - 0.5) * 0.10)
            .clamp(0.07, 0.66)
            .toDouble()
        : (keeperDirection == PenaltyLane.center &&
                    shotLane == PenaltyLane.center
                ? (0.34 + saveSkill * 0.30 - shotSpeedBonus)
                    .clamp(0.12, 0.72)
                    .toDouble()
                : (0.02 + saveSkill * 0.05).clamp(0.01, 0.12).toDouble());

    final scored =
        random.nextDouble() > (missChance + saveChance).clamp(0.04, 0.90);

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
