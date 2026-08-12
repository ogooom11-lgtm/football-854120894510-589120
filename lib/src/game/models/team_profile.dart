import '../enums/ai_difficulty.dart';
import '../enums/ai_play_style.dart';
import '../enums/player_role.dart';
import 'jersey_kit.dart';
import 'formation.dart';
import 'player_profile.dart';

/// A stored team owned by an account. Ownership cannot be changed
/// after creation except by an admin.
class SavedTeamProfile {
  SavedTeamProfile({
    required this.id,
    required this.ownerAccountId,
    required this.name,
    required this.playerIds,
    required this.formation,
    Set<String>? starterPlayerIds,
    Map<String, PlayerRole>? roleByPlayerId,
    List<TeamMatchRecord>? matchHistory,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.rating = 50,
    this.playStyle = AiPlayStyle.balanced,
    this.aiDifficulty = AiDifficulty.medium,
    this.isDeleted = false,
    List<JerseyKit>? jerseyKits,
    this.activeKitIndex = 0,
  }) : starterPlayerIds = starterPlayerIds ?? <String>{},
       roleByPlayerId = roleByPlayerId ?? <String, PlayerRole>{},
       matchHistory = matchHistory ?? <TeamMatchRecord>[],
       jerseyKits = jerseyKits ?? JerseyFactory.defaultKits();

  final String id;
  String ownerAccountId; // can only be changed by admin tools
  String name;
  Set<String> playerIds;
  FormationType formation;
  Set<String> starterPlayerIds;
  Map<String, PlayerRole> roleByPlayerId;
  final List<TeamMatchRecord> matchHistory;
  int wins;
  int losses;
  int draws;
  double rating;
  AiPlayStyle playStyle;
  AiDifficulty aiDifficulty;
  bool isDeleted; // soft delete
  List<JerseyKit> jerseyKits;
  int activeKitIndex;

  int get played => wins + losses + draws;

  JerseyKit get activeKit => activeKitIndex < jerseyKits.length
      ? jerseyKits[activeKitIndex]
      : jerseyKits.first;

  JerseyKit get goalkeeperKit => JerseyKit(
    name: 'Kaleci',
    shirtColor: activeKit.goalkeeperShirtColor,
    shortsColor: activeKit.shortsColor,
    socksColor: activeKit.socksColor,
    numberColor: activeKit.numberColor,
    goalkeeperShirtColor: activeKit.goalkeeperShirtColor,
  );

  factory SavedTeamProfile.create({
    required String ownerAccountId,
    required String name,
    required Iterable<String> playerIds,
    FormationType formation = FormationType.wing433,
  }) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final ids = playerIds.toSet();
    return SavedTeamProfile(
      id: '$stamp-${DateTime.now().millisecondsSinceEpoch}',
      ownerAccountId: ownerAccountId,
      name: name.trim().isEmpty ? 'Takim' : name.trim(),
      playerIds: ids,
      starterPlayerIds: ids.take(11).toSet(),
      formation: formation,
      jerseyKits: JerseyFactory.defaultKits(),
      activeKitIndex: 0,
    );
  }

  factory SavedTeamProfile.fromJson(
    Map<String, dynamic> json, {
    required String fallbackOwnerAccountId,
  }) {
    final roles = <String, PlayerRole>{};
    final rawRoles = json['roleByPlayerId'];
    if (rawRoles is Map<String, dynamic>) {
      for (final entry in rawRoles.entries) {
        roles[entry.key] = _roleFromName(entry.value);
      }
    }
    return SavedTeamProfile(
      id: json['id'] as String,
      ownerAccountId: json.containsKey('ownerAccountId')
          ? json['ownerAccountId'] as String? ?? ''
          : fallbackOwnerAccountId,
      name: json['name'] as String? ?? 'Takim',
      playerIds: Set<String>.from(
        json['playerIds'] as List<dynamic>? ?? const [],
      ),
      starterPlayerIds: Set<String>.from(
        json['starterPlayerIds'] as List<dynamic>? ?? const [],
      ),
      roleByPlayerId: roles,
      matchHistory: (json['matchHistory'] as List<dynamic>? ?? const [])
          .map((item) => TeamMatchRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
      formation: formationFromName(json['formation']),
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      losses: (json['losses'] as num?)?.toInt() ?? 0,
      draws: (json['draws'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 50,
      playStyle: AiPlayStyle.values.firstWhere(
        (s) => s.name == json['playStyle'],
        orElse: () => AiPlayStyle.balanced,
      ),
      aiDifficulty: AiDifficulty.values.firstWhere(
        (d) => d.name == json['aiDifficulty'],
        orElse: () => AiDifficulty.medium,
      ),
      isDeleted: json['isDeleted'] as bool? ?? false,
      jerseyKits:
          (json['jerseyKits'] as List<dynamic>?)
              ?.map((k) => JerseyKit.fromJson(k as Map<String, dynamic>))
              .toList() ??
          JerseyFactory.defaultKits(),
      activeKitIndex: (json['activeKitIndex'] as num?)?.toInt() ?? 0,
    );
  }

  void ensureLineupDefaults(List<PlayerProfile> players) {
    final playerById = {for (final player in players) player.id: player};
    playerIds = playerIds.where(playerById.containsKey).toSet();
    starterPlayerIds = starterPlayerIds.intersection(playerIds);
    roleByPlayerId.removeWhere((id, _) => !playerIds.contains(id));

    final members = players.where((player) => playerIds.contains(player.id));
    for (final player in members) {
      roleByPlayerId.putIfAbsent(
        player.id,
        () => player.isGoalkeeper
            ? PlayerRole.goalkeeper
            : _defaultRoleForIndex(roleByPlayerId.length),
      );
    }

    final starters = members
        .where((player) => starterPlayerIds.contains(player.id))
        .toList();
    if (starterPlayerIds.isEmpty) {
      final keeper = members.where((player) => player.isGoalkeeper).take(1);
      final fielders = members.where((player) => !player.isGoalkeeper).take(10);
      starterPlayerIds = [
        ...keeper,
        ...fielders,
      ].map((player) => player.id).toSet();
    } else if (starterPlayerIds.length > 11) {
      starterPlayerIds = starters.take(11).map((player) => player.id).toSet();
    }
  }

  void addMatchRecord(TeamMatchRecord record) {
    matchHistory.insert(0, record);
    if (matchHistory.length > 120) {
      matchHistory.removeRange(120, matchHistory.length);
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ownerAccountId': ownerAccountId,
      'name': name,
      'playerIds': playerIds.toList(),
      'starterPlayerIds': starterPlayerIds.toList(),
      'roleByPlayerId': roleByPlayerId.map(
        (id, role) => MapEntry(id, role.name),
      ),
      'matchHistory': matchHistory.map((record) => record.toJson()).toList(),
      'formation': formation.name,
      'wins': wins,
      'losses': losses,
      'draws': draws,
      'rating': double.parse(rating.toStringAsFixed(1)),
      'playStyle': playStyle.name,
      'aiDifficulty': aiDifficulty.name,
      'isDeleted': isDeleted,
      'jerseyKits': jerseyKits.map((k) => k.toJson()).toList(),
      'activeKitIndex': activeKitIndex,
    };
  }
}

/// Detailed per-match record for a team.
class TeamMatchRecord {
  const TeamMatchRecord({
    required this.matchId,
    required this.opponentName,
    required this.scoreText,
    required this.result,
    required this.ratingBefore,
    required this.ratingAfter,
    required this.possessionPercent,
    required this.passes,
    required this.successfulPasses,
    required this.shots,
    required this.goals,
    required this.timestamp,
  });

  final String matchId;
  final String opponentName;
  final String scoreText;
  final String result;
  final double ratingBefore;
  final double ratingAfter;
  final double possessionPercent;
  final int passes;
  final int successfulPasses;
  final int shots;
  final int goals;
  final int timestamp; // ms since epoch

  factory TeamMatchRecord.fromJson(Map<String, dynamic> json) {
    return TeamMatchRecord(
      matchId: json['matchId'] as String? ?? '',
      opponentName: json['opponentName'] as String? ?? '',
      scoreText: json['scoreText'] as String? ?? '',
      result: json['result'] as String? ?? '',
      ratingBefore: (json['ratingBefore'] as num?)?.toDouble() ?? 50,
      ratingAfter: (json['ratingAfter'] as num?)?.toDouble() ?? 50,
      possessionPercent: (json['possessionPercent'] as num?)?.toDouble() ?? 50,
      passes: (json['passes'] as num?)?.toInt() ?? 0,
      successfulPasses: (json['successfulPasses'] as num?)?.toInt() ?? 0,
      shots: (json['shots'] as num?)?.toInt() ?? 0,
      goals: (json['goals'] as num?)?.toInt() ?? 0,
      timestamp: json['timestamp'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'matchId': matchId,
      'opponentName': opponentName,
      'scoreText': scoreText,
      'result': result,
      'ratingBefore': double.parse(ratingBefore.toStringAsFixed(1)),
      'ratingAfter': double.parse(ratingAfter.toStringAsFixed(1)),
      'possessionPercent': double.parse(possessionPercent.toStringAsFixed(1)),
      'passes': passes,
      'successfulPasses': successfulPasses,
      'shots': shots,
      'goals': goals,
      'timestamp': timestamp,
    };
  }
}

/// Team ranking entry for public leaderboard.
class TeamRankEntry {
  const TeamRankEntry({
    required this.rank,
    required this.name,
    required this.rating,
    required this.played,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsFor,
    required this.goalsAgainst,
  });

  final int rank;
  final String name;
  final double rating;
  final int played;
  final int wins;
  final int draws;
  final int losses;
  final int goalsFor;
  final int goalsAgainst;

  int get points => wins * 3 + draws;
  int get goalDifference => goalsFor - goalsAgainst;
}

PlayerRole _roleFromName(Object? value) {
  final name = value?.toString();
  if (name == null || name.isEmpty) return PlayerRole.midfieldLeft;
  return PlayerRole.values.firstWhere(
    (role) => role.name == name,
    orElse: () => PlayerRole.midfieldLeft,
  );
}

PlayerRole _defaultRoleForIndex(int index) {
  const roles = [
    PlayerRole.goalkeeper,
    PlayerRole.centerBackLeft,
    PlayerRole.centerBackRight,
    PlayerRole.leftWingBack,
    PlayerRole.rightWingBack,
    PlayerRole.sweeper,
    PlayerRole.midfieldLeft,
    PlayerRole.midfieldRight,
    PlayerRole.leftWing,
    PlayerRole.rightWing,
    PlayerRole.striker,
  ];
  return roles[index % roles.length];
}
