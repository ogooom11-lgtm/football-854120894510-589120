import '../enums/team_id.dart';
import '../math/vec2.dart';

class GoalEvent {
  GoalEvent({
    required this.teamId,
    required this.scorerName,
    required this.minute,
    this.isPenalty = false,
    this.canceled = false,
    this.scorerPlayerId,
    this.assisterPlayerId,
  });

  final TeamId teamId;
  final String scorerName;
  final int minute;
  final bool isPenalty;
  final String? scorerPlayerId;
  final String? assisterPlayerId;
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
  const MatchBanner(
    this.title,
    this.subtitle,
    this.seconds, {
    this.minute,
    this.kind = 'info',
  });

  final String title;
  final String subtitle;
  final double seconds;
  final int? minute;
  final String kind;
}

class DisciplinaryEvent {
  DisciplinaryEvent({
    required this.teamId,
    required this.playerId,
    required this.playerName,
    required this.minute,
    required this.card,
    required this.reason,
    this.suspensionMatches = 0,
    this.canceled = false,
  });

  final TeamId teamId;
  final String playerId;
  final String playerName;
  final int minute;
  final String card;
  final String reason;
  final int suspensionMatches;
  bool canceled;

  bool get isRed => card == 'red' || card == 'secondYellow';

  String get title => switch (card) {
        'yellow' => 'SARI KART',
        'secondYellow' => 'IKINCI SARI / KIRMIZI',
        _ => 'KIRMIZI KART',
      };
}

class MatchTimelineEvent {
  MatchTimelineEvent({
    required this.id,
    required this.kind,
    required this.title,
    required this.detail,
    required this.minute,
    required this.replayIndex,
    this.teamId,
    this.relatedPlayerId,
    this.canceled = false,
  });

  final String id;
  final String kind;
  final String title;
  final String detail;
  final int minute;
  final int replayIndex;
  final TeamId? teamId;
  final String? relatedPlayerId;
  bool canceled;
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

class FinishedGoalSummary {
  const FinishedGoalSummary({
    required this.teamId,
    required this.scorerName,
    required this.minute,
    required this.isPenalty,
    this.scorerPlayerId,
    this.assisterPlayerId,
    this.assisterName,
  });

  final TeamId teamId;
  final String scorerName;
  final int minute;
  final bool isPenalty;
  final String? scorerPlayerId;
  final String? assisterPlayerId;
  final String? assisterName;

  factory FinishedGoalSummary.fromJson(Map<String, dynamic> json) {
    return FinishedGoalSummary(
      teamId: TeamId.values.firstWhere(
        (team) => team.name == json['teamId'],
        orElse: () => TeamId.blue,
      ),
      scorerName: json['scorerName'] as String? ?? 'Oyuncu',
      minute: (json['minute'] as num?)?.toInt() ?? 0,
      isPenalty: json['isPenalty'] as bool? ?? false,
      scorerPlayerId: json['scorerPlayerId'] as String?,
      assisterPlayerId: json['assisterPlayerId'] as String?,
      assisterName: json['assisterName'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'teamId': teamId.name,
    'scorerName': scorerName,
    'minute': minute,
    'isPenalty': isPenalty,
    'scorerPlayerId': scorerPlayerId,
    'assisterPlayerId': assisterPlayerId,
    'assisterName': assisterName,
  };
}

class FinishedPlayerSummary {
  const FinishedPlayerSummary({
    required this.playerId,
    required this.teamId,
    required this.name,
    required this.number,
    required this.role,
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
    required this.staminaPercent,
    required this.injured,
  });

  final String playerId;
  final TeamId teamId;
  final String name;
  final int number;
  final String role;
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
  final int staminaPercent;
  final bool injured;

  factory FinishedPlayerSummary.fromJson(Map<String, dynamic> json) {
    return FinishedPlayerSummary(
      playerId: json['playerId'] as String? ?? '',
      teamId: TeamId.values.firstWhere(
        (team) => team.name == json['teamId'],
        orElse: () => TeamId.blue,
      ),
      name: json['name'] as String? ?? 'Oyuncu',
      number: (json['number'] as num?)?.toInt() ?? 0,
      role: json['role'] as String? ?? '',
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
      staminaPercent: (json['staminaPercent'] as num?)?.toInt() ?? 100,
      injured: json['injured'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'playerId': playerId,
    'teamId': teamId.name,
    'name': name,
    'number': number,
    'role': role,
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
    'staminaPercent': staminaPercent,
    'injured': injured,
  };
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
    required this.timestamp,
    this.goals = const [],
    this.playerStats = const [],
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
  final int timestamp;
  final List<FinishedGoalSummary> goals;
  final List<FinishedPlayerSummary> playerStats;

  factory FinishedMatchSummary.fromJson(Map<String, dynamic> json) {
    return FinishedMatchSummary(
      matchId: json['matchId'] as String? ?? '',
      blueStorageTeamId: json['blueStorageTeamId'] as String?,
      redStorageTeamId: json['redStorageTeamId'] as String?,
      blueName: json['blueName'] as String? ?? 'Mavi',
      redName: json['redName'] as String? ?? 'Kirmizi',
      blueScore: (json['blueScore'] as num?)?.toInt() ?? 0,
      redScore: (json['redScore'] as num?)?.toInt() ?? 0,
      blueRatingDelta: (json['blueRatingDelta'] as num?)?.toDouble() ?? 0,
      redRatingDelta: (json['redRatingDelta'] as num?)?.toDouble() ?? 0,
      bluePossessionPercent:
          (json['bluePossessionPercent'] as num?)?.toDouble() ?? 50,
      redPossessionPercent:
          (json['redPossessionPercent'] as num?)?.toDouble() ?? 50,
      bluePasses: (json['bluePasses'] as num?)?.toInt() ?? 0,
      redPasses: (json['redPasses'] as num?)?.toInt() ?? 0,
      blueSuccessfulPasses:
          (json['blueSuccessfulPasses'] as num?)?.toInt() ?? 0,
      redSuccessfulPasses:
          (json['redSuccessfulPasses'] as num?)?.toInt() ?? 0,
      blueShots: (json['blueShots'] as num?)?.toInt() ?? 0,
      redShots: (json['redShots'] as num?)?.toInt() ?? 0,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      goals: (json['goals'] as List<dynamic>? ?? const [])
          .map(
            (item) => FinishedGoalSummary.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
      playerStats: (json['playerStats'] as List<dynamic>? ?? const [])
          .map(
            (item) => FinishedPlayerSummary.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'matchId': matchId,
    'blueStorageTeamId': blueStorageTeamId,
    'redStorageTeamId': redStorageTeamId,
    'blueName': blueName,
    'redName': redName,
    'blueScore': blueScore,
    'redScore': redScore,
    'blueRatingDelta': blueRatingDelta,
    'redRatingDelta': redRatingDelta,
    'bluePossessionPercent': bluePossessionPercent,
    'redPossessionPercent': redPossessionPercent,
    'bluePasses': bluePasses,
    'redPasses': redPasses,
    'blueSuccessfulPasses': blueSuccessfulPasses,
    'redSuccessfulPasses': redSuccessfulPasses,
    'blueShots': blueShots,
    'redShots': redShots,
    'timestamp': timestamp,
    'goals': goals.map((goal) => goal.toJson()).toList(),
    'playerStats': playerStats.map((player) => player.toJson()).toList(),
  };
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
