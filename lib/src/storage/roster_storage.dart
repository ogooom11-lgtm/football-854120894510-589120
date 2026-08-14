import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../game/enums/match_mode.dart';
import '../game/enums/ai_difficulty.dart';
import '../game/enums/ai_play_style.dart';
import '../game/models/formation.dart';
import '../game/models/match_event.dart';
import '../game/models/player_profile.dart';
import '../game/models/team_profile.dart';

class SavedAccountProfile {
  SavedAccountProfile({
    required this.id,
    required this.username,
    required this.passwordHash,
  });

  final String id;
  String username;
  String passwordHash;

  bool get hasPassword => passwordHash.isNotEmpty;

  bool checkPassword(String password) {
    return passwordHash.isNotEmpty &&
        passwordHash == localPasswordHash(password);
  }

  void setPassword(String password) {
    passwordHash = localPasswordHash(password);
  }

  factory SavedAccountProfile.create(String username, {String password = ''}) {
    final rng = math.Random();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return SavedAccountProfile(
      id: '$stamp-${rng.nextInt(999999)}',
      username: username.trim().isEmpty ? 'Hesap' : username.trim(),
      passwordHash: password.trim().isEmpty ? '' : localPasswordHash(password),
    );
  }

  factory SavedAccountProfile.fromJson(Map<String, dynamic> json) {
    return SavedAccountProfile(
      id: json['id'] as String,
      username: json['username'] as String? ?? 'Hesap',
      passwordHash: json['passwordHash'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'passwordHash': passwordHash,
  };
}

class SavedGameData {
  SavedGameData({
    required this.accounts,
    required this.activeAccountId,
    required this.loggedInAccountIds,
    required this.adminPasswordHash,
    this.adminLoggedIn = false,
    this.adminFullAccess = false,
    required this.players,
    required this.teams,
    required this.blueTeamId,
    required this.redTeamId,
    required this.blueName,
    required this.redName,
    required this.blueFormation,
    required this.redFormation,
    required this.mode,
    required this.bluePlayerIds,
    required this.redPlayerIds,
    this.blueAiControlled = false,
    this.redAiControlled = false,
    this.aiDifficulty = AiDifficulty.medium,
    this.bluePlayStyle = AiPlayStyle.balanced,
    this.redPlayStyle = AiPlayStyle.balanced,
    List<FinishedMatchSummary>? matchArchive,
  }) : matchArchive = matchArchive ?? <FinishedMatchSummary>[];

  final List<SavedAccountProfile> accounts;
  String activeAccountId;
  Set<String> loggedInAccountIds;
  String adminPasswordHash;
  bool adminLoggedIn;
  bool adminFullAccess;
  final List<PlayerProfile> players;
  final List<SavedTeamProfile> teams;
  String blueTeamId;
  String redTeamId;
  String blueName;
  String redName;
  FormationType blueFormation;
  FormationType redFormation;
  MatchMode mode;
  Set<String> bluePlayerIds;
  Set<String> redPlayerIds;
  bool blueAiControlled;
  bool redAiControlled;
  AiDifficulty aiDifficulty;
  AiPlayStyle bluePlayStyle;
  AiPlayStyle redPlayStyle;
  final List<FinishedMatchSummary> matchArchive;

  void archiveMatch(FinishedMatchSummary summary) {
    matchArchive.removeWhere((match) => match.matchId == summary.matchId);
    matchArchive.insert(0, summary);
    if (matchArchive.length > 200) {
      matchArchive.removeRange(200, matchArchive.length);
    }
  }

  SavedAccountProfile get activeAccount => accounts.firstWhere(
    (account) => account.id == activeAccountId,
    orElse: () => accounts.first,
  );

  List<SavedTeamProfile> get ownedTeams => teams
      .where(
        (team) => team.ownerAccountId == activeAccountId && !team.isDeleted,
      )
      .toList(growable: false);

  List<SavedTeamProfile> get activeTeams =>
      teams.where((team) => !team.isDeleted).toList(growable: false);

  bool isAccountLoggedIn(String id) => loggedInAccountIds.contains(id);

  bool isTeamOwnerLoggedIn(SavedTeamProfile team) =>
      team.ownerAccountId.isNotEmpty &&
      loggedInAccountIds.contains(team.ownerAccountId);

  bool get adminPasswordSet => adminPasswordHash.isNotEmpty;

  bool checkAdminPassword(String password) {
    return adminPasswordHash.isNotEmpty &&
        adminPasswordHash == localPasswordHash(password);
  }

  void setAdminPassword(String password) {
    adminPasswordHash = localPasswordHash(password);
  }

  factory SavedGameData.defaults() {
    final rng = math.Random(7);
    final account = SavedAccountProfile.create('Ana Hesap');
    final names = [
      'Emir',
      'Arda',
      'Mert',
      'Deniz',
      'Kerem',
      'Can',
      'Efe',
      'Berk',
      'Kaan',
      'Yigit',
      'Ozan',
      'Burak',
      'Selim',
      'Murat',
      'Baris',
      'Umut',
      'Onur',
      'Eren',
      'Hakan',
      'Ali',
      'Volkan',
      'Serkan',
    ];
    final players = <PlayerProfile>[];
    for (var i = 0; i < names.length; i++) {
      players.add(
        PlayerProfile.generated(
          name: names[i],
          isGoalkeeper: i == 0 || i == 11,
          random: rng,
        ),
      );
    }
    final blueTeam = SavedTeamProfile.create(
      ownerAccountId: account.id,
      name: 'Mavi Takim',
      playerIds: players.take(11).map((player) => player.id),
      formation: FormationType.wing433,
    );
    final redTeam = SavedTeamProfile.create(
      ownerAccountId: account.id,
      name: 'Kirmizi Takim',
      playerIds: players.skip(11).take(11).map((player) => player.id),
      formation: FormationType.classic442,
    );
    blueTeam.ensureLineupDefaults(players);
    redTeam.ensureLineupDefaults(players);
    return SavedGameData(
      accounts: [account],
      activeAccountId: account.id,
      loggedInAccountIds: {account.id},
      adminPasswordHash: '',
      players: players,
      teams: [blueTeam, redTeam],
      blueTeamId: blueTeam.id,
      redTeamId: redTeam.id,
      blueName: blueTeam.name,
      redName: redTeam.name,
      blueFormation: blueTeam.formation,
      redFormation: redTeam.formation,
      mode: MatchMode.knockout,
      bluePlayerIds: blueTeam.playerIds,
      redPlayerIds: redTeam.playerIds,
      blueAiControlled: false,
      redAiControlled: false,
      aiDifficulty: AiDifficulty.medium,
      bluePlayStyle: AiPlayStyle.balanced,
      redPlayStyle: AiPlayStyle.balanced,
    );
  }

  factory SavedGameData.fromJson(Map<String, dynamic> json) {
    final fallbackAccount = SavedAccountProfile.create('Ana Hesap');
    final accounts = (json['accounts'] as List<dynamic>? ?? const [])
        .map(
          (item) => SavedAccountProfile.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    if (accounts.isEmpty) {
      accounts.add(fallbackAccount);
    }
    var activeAccountId =
        json['activeAccountId'] as String? ?? accounts.first.id;
    if (!accounts.any((account) => account.id == activeAccountId)) {
      activeAccountId = accounts.first.id;
    }
    final accountIds = accounts.map((account) => account.id).toSet();
    final loggedInAccountIds = Set<String>.from(
      json['loggedInAccountIds'] as List<dynamic>? ?? [activeAccountId],
    ).where(accountIds.contains).toSet();
    if (loggedInAccountIds.isEmpty) {
      loggedInAccountIds.add(activeAccountId);
    }

    final players = (json['players'] as List<dynamic>? ?? [])
        .map((item) => PlayerProfile.fromJson(item as Map<String, dynamic>))
        .toList();
    var teams = (json['teams'] as List<dynamic>? ?? [])
        .map(
          (item) => SavedTeamProfile.fromJson(
            item as Map<String, dynamic>,
            fallbackOwnerAccountId: activeAccountId,
          ),
        )
        .toList();
    final legacyBlueIds = Set<String>.from(
      json['bluePlayerIds'] as List<dynamic>? ?? const [],
    );
    final legacyRedIds = Set<String>.from(
      json['redPlayerIds'] as List<dynamic>? ?? const [],
    );
    if (teams.isEmpty) {
      teams = [
        SavedTeamProfile.create(
          ownerAccountId: activeAccountId,
          name: json['blueName'] as String? ?? 'Mavi Takim',
          playerIds: legacyBlueIds.isEmpty
              ? players.take(11).map((player) => player.id)
              : legacyBlueIds,
        ),
        SavedTeamProfile.create(
          ownerAccountId: activeAccountId,
          name: json['redName'] as String? ?? 'Kirmizi Takim',
          playerIds: legacyRedIds.isEmpty
              ? players.skip(11).take(11).map((player) => player.id)
              : legacyRedIds,
        ),
      ];
    }
    for (final team in teams) {
      if (!accounts.any((account) => account.id == team.ownerAccountId)) {
        team.ownerAccountId = '';
      }
      team.ensureLineupDefaults(players);
    }

    final activeTeams = teams.where((team) => !team.isDeleted).toList();
    if (activeTeams.isEmpty) {
      final replacement = SavedTeamProfile.create(
        ownerAccountId: activeAccountId,
        name: 'Yeni Takim',
        playerIds: players.take(11).map((player) => player.id),
      );
      replacement.ensureLineupDefaults(players);
      teams.add(replacement);
      activeTeams.add(replacement);
    }
    final playableTeams = activeTeams;
    final blueTeamId = json['blueTeamId'] as String? ?? playableTeams.first.id;
    final redTeamId =
        json['redTeamId'] as String? ??
        (playableTeams.length > 1
            ? playableTeams[1].id
            : playableTeams.first.id);
    final blueTeam = playableTeams.firstWhere(
      (team) => team.id == blueTeamId,
      orElse: () => playableTeams.first,
    );
    final redTeam = playableTeams.firstWhere(
      (team) => team.id == redTeamId,
      orElse: () =>
          playableTeams.length > 1 ? playableTeams[1] : playableTeams.first,
    );
    return SavedGameData(
        accounts: accounts,
        activeAccountId: activeAccountId,
        loggedInAccountIds: loggedInAccountIds,
        adminPasswordHash: json['adminPasswordHash'] as String? ?? '',
        // Administrator sessions are intentionally not restored after restart.
        adminLoggedIn: false,
        adminFullAccess: false,
        players: players,
        teams: teams,
        blueTeamId: blueTeam.id,
        redTeamId: redTeam.id,
        blueName: blueTeam.name,
        redName: redTeam.name,
        blueFormation: formationFromName(
          json['blueFormation'] ?? blueTeam.formation.name,
        ),
        redFormation: formationFromName(
          json['redFormation'] ?? redTeam.formation.name,
        ),
        mode: MatchMode.values.firstWhere(
          (mode) => mode.name == json['mode'],
          orElse: () => MatchMode.knockout,
        ),
        bluePlayerIds: blueTeam.playerIds,
        redPlayerIds: redTeam.playerIds,
        blueAiControlled: json['blueAiControlled'] as bool? ?? false,
        redAiControlled: json['redAiControlled'] as bool? ?? false,
        aiDifficulty: AiDifficulty.values.firstWhere(
          (d) => d.name == json['aiDifficulty'],
          orElse: () => AiDifficulty.medium,
        ),
        bluePlayStyle: AiPlayStyle.values.firstWhere(
          (s) => s.name == json['bluePlayStyle'],
          orElse: () => AiPlayStyle.balanced,
        ),
        redPlayStyle: AiPlayStyle.values.firstWhere(
          (s) => s.name == json['redPlayStyle'],
          orElse: () => AiPlayStyle.balanced,
        ),
        matchArchive: (json['matchArchive'] as List<dynamic>? ?? const [])
            .map(
              (item) => FinishedMatchSummary.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .take(200)
            .toList(),
      );
  }

  SavedTeamProfile get blueTeam => teams.firstWhere(
    (team) => team.id == blueTeamId && !team.isDeleted,
    orElse: () => ownedTeams.isNotEmpty ? ownedTeams.first : activeTeams.first,
  );

  SavedTeamProfile get redTeam => teams.firstWhere(
    (team) => team.id == redTeamId && !team.isDeleted,
    orElse: () {
      final owned = ownedTeams;
      if (owned.length > 1) {
        return owned[1];
      }
      return activeTeams.length > 1 ? activeTeams[1] : activeTeams.first;
    },
  );

  bool ownsTeam(SavedTeamProfile team) =>
      team.ownerAccountId == activeAccountId;

  void selectFirstOwnedTeams() {
    final owned = ownedTeams;
    if (owned.isEmpty) {
      return;
    }
    blueTeamId = owned.first.id;
    redTeamId = owned.length > 1 ? owned[1].id : owned.first.id;
    bluePlayerIds = blueTeam.playerIds;
    redPlayerIds = redTeam.playerIds;
    blueFormation = blueTeam.formation;
    redFormation = redTeam.formation;
    blueName = blueTeam.name;
    redName = redTeam.name;
  }

  Map<String, dynamic> toJson() {
    return {
      'accounts': accounts.map((account) => account.toJson()).toList(),
      'activeAccountId': activeAccountId,
      'loggedInAccountIds': loggedInAccountIds.toList(),
      'adminPasswordHash': adminPasswordHash,
      'adminLoggedIn': adminLoggedIn,
      'adminFullAccess': adminFullAccess,
      'players': players.map((player) => player.toJson()).toList(),
      'teams': teams.map((team) => team.toJson()).toList(),
      'blueTeamId': blueTeamId,
      'redTeamId': redTeamId,
      'blueName': blueName,
      'redName': redName,
      'blueFormation': blueFormation.name,
      'redFormation': redFormation.name,
      'mode': mode.name,
      'bluePlayerIds': bluePlayerIds.toList(),
      'redPlayerIds': redPlayerIds.toList(),
      'blueAiControlled': blueAiControlled,
      'redAiControlled': redAiControlled,
      'aiDifficulty': aiDifficulty.name,
      'bluePlayStyle': bluePlayStyle.name,
      'redPlayStyle': redPlayStyle.name,
      'matchArchive': matchArchive.map((match) => match.toJson()).toList(),
    };
  }
}

class RosterStorage {
  RosterStorage();

  File get _file {
    final appData = Platform.environment['APPDATA'];
    final base = appData == null || appData.isEmpty
        ? Directory.current.path
        : '$appData${Platform.pathSeparator}BombanFutbol';
    return File('$base${Platform.pathSeparator}kayitli_oyuncular.json');
  }

  Future<SavedGameData> load() async {
    try {
      final file = _file;
      if (!await file.exists()) {
        final defaults = SavedGameData.defaults();
        await save(defaults);
        return defaults;
      }
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final data = SavedGameData.fromJson(json);
      if (data.players.isEmpty) {
        return SavedGameData.defaults();
      }
      return data;
    } catch (_) {
      return SavedGameData.defaults();
    }
  }

  Future<void> save(SavedGameData data) async {
    final file = _file;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data.toJson()),
    );
  }
}

String localPasswordHash(String password) {
  var hash = 0x811c9dc5;
  final text = 'bomban-v2:${password.trim()}';
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
