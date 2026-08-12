import '../enums/team_id.dart';
import '../math/vec2.dart';

class GoalEvent {
  GoalEvent({
    required this.teamId,
    required this.scorerName,
    required this.minute,
    this.isPenalty = false,
    this.canceled = false,
  });

  final TeamId teamId;
  final String scorerName;
  final int minute;
  final bool isPenalty;
  bool canceled;
}

class OffsideEvent {
  const OffsideEvent({
    required this.attackingTeam,
    required this.offenderName,
    required this.kind,
    required this.minute,
    required this.lineX,
    required this.ballPos,
    required this.offenderPos,
  });

  final TeamId attackingTeam;
  final String offenderName;
  final String kind;
  final int minute;
  final double lineX;
  final Vec2 ballPos;
  final Vec2 offenderPos;
}

class MatchBanner {
  const MatchBanner(this.title, this.subtitle, this.seconds);

  final String title;
  final String subtitle;
  final double seconds;
}

class ReplayPlayerFrame {
  const ReplayPlayerFrame({required this.id, required this.x, required this.y});

  final String id;
  final double x;
  final double y;
}

class ReplayFrame {
  const ReplayFrame({
    required this.minute,
    required this.ballX,
    required this.ballY,
    required this.ballHeight,
    required this.blueScore,
    required this.redScore,
    required this.description,
    required this.players,
  });

  final double minute;
  final double ballX;
  final double ballY;
  final double ballHeight;
  final int blueScore;
  final int redScore;
  final String description;
  final List<ReplayPlayerFrame> players;
}

class FinishedMatchSummary {
  const FinishedMatchSummary({
    required this.matchId,
    required this.blueStorageTeamId,
    required this.redStorageTeamId,
    required this.blueName,
    required this.redName,
    required this.blueScore,
    required this.redScore,
    required this.blueRatingDelta,
    required this.redRatingDelta,
    required this.bluePossessionPercent,
    required this.redPossessionPercent,
    required this.bluePasses,
    required this.redPasses,
    required this.blueSuccessfulPasses,
    required this.redSuccessfulPasses,
    required this.blueShots,
    required this.redShots,
  });

  final String matchId;
  final String? blueStorageTeamId;
  final String? redStorageTeamId;
  final String blueName;
  final String redName;
  final int blueScore;
  final int redScore;
  final double blueRatingDelta;
  final double redRatingDelta;
  final double bluePossessionPercent;
  final double redPossessionPercent;
  final int bluePasses;
  final int redPasses;
  final int blueSuccessfulPasses;
  final int redSuccessfulPasses;
  final int blueShots;
  final int redShots;
}


class InjuryEvent {
  const InjuryEvent({
    required this.playerName,
    required this.teamId,
    required this.days,
    required this.minute,
  });

  final String playerName;
  final TeamId teamId;
  final int days;
  final int minute;

  String get summary => "$playerName: $days gun sahalardan uzak (dk.$minute)";
}
