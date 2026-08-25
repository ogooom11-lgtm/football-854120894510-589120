import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/enums/ai_difficulty.dart';
import '../game/enums/ai_play_style.dart';
import '../game/enums/match_mode.dart';
import '../game/enums/player_role.dart';
import '../game/enums/team_id.dart';
import '../game/logic/role_affinity.dart';
import '../game/models/formation.dart';
import '../game/models/jersey_kit.dart';
import '../game/models/match_event.dart';
import '../game/models/player_profile.dart';
import '../game/models/shooting.dart';
import '../game/models/team_profile.dart';
import '../game/models/team_setup.dart';
import '../storage/roster_storage.dart';
import 'account_detail_screen.dart';
import 'free_agents_screen.dart';
import 'game_screen.dart';
import 'player_detail_screen.dart';
import 'team_detail_screen.dart';
import 'team_players_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final RosterStorage _storage = RosterStorage();
  final TextEditingController _newAccountController = TextEditingController();
  final TextEditingController _newPlayerController = TextEditingController();
  final TextEditingController _newTeamController = TextEditingController();
  final TextEditingController _importPlayersPathController =
      TextEditingController();
  final TextEditingController _blueNameController = TextEditingController();
  final TextEditingController _redNameController = TextEditingController();
  final TextEditingController _newCountryController = TextEditingController();
  final FocusNode _keyboardFocus = FocusNode();
  final Set<LogicalKeyboardKey> _pressedKeys = <LogicalKeyboardKey>{};
  SavedGameData? _data;
  bool _newIsGoalkeeper = false;
  int _setupTab = 0;
  bool _blueAiControlled = false;
  bool _redAiControlled = false;
  AiDifficulty _aiDifficulty = AiDifficulty.medium;
  AiPlayStyle _bluePlayStyle = AiPlayStyle.balanced;
  AiPlayStyle _redPlayStyle = AiPlayStyle.balanced;
  int _blueKitIndex = 0;
  int _redKitIndex = 0;
  Timer? _adminUnlockTimer;
  final TextEditingController _adminPasswordController =
      TextEditingController();
  bool _showAdminPasswordField = false;
  bool _adminPasswordError = false;
  int _pendingAdminTab = 5;
  int _adminSubTab = 0;
  String _adminTransferPlayerId = '';
  String _adminTransferTeamId = '';
  // Admin "Değer" tab (kimo@ only).
  String _valueTeamId = '';
  bool _valueQuickUp = true;
  int _valueQuickStep = 1;
  String _valueSearch = '';
  String _valueTeamFilter = 'all';
  final Set<String> _valueSelectedPlayerIds = {};
  final List<({String attrKey, bool up, int amount})> _valueAdjustments = [
    (attrKey: 'shotPower', up: true, amount: 5),
  ];
  String _penaltySearch = '';
  String _accountSearch = '';
  String _teamSearch = '';
  String _playerSearch = '';
  String _adminPlayerSearch = '';
  String _adminTeamSearch = '';
  final Map<String, String> _lineupSearchByTeam = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newAccountController.dispose();
    _newPlayerController.dispose();
    _newTeamController.dispose();
    _importPlayersPathController.dispose();
    _blueNameController.dispose();
    _redNameController.dispose();
    _newCountryController.dispose();
    _adminUnlockTimer?.cancel();
    _adminPasswordController.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await _storage.load();
    if (!mounted) {
      return;
    }
    // Keep the current admin session alive across in-app page reloads.
    // It only expires when the app restarts or the admin locks it.
    final previous = _data;
    if (previous != null && previous.adminLoggedIn) {
      data.adminLoggedIn = true;
      data.adminFullAccess = previous.adminFullAccess;
    }
    _blueNameController.text = data.blueTeam.name;
    _redNameController.text = data.redTeam.name;
    _blueAiControlled = data.blueAiControlled;
    _redAiControlled = data.redAiControlled;
    _aiDifficulty = data.aiDifficulty;
    _bluePlayStyle = data.bluePlayStyle;
    _redPlayStyle = data.redPlayStyle;
    _blueKitIndex = data.blueTeam.activeKitIndex;
    _redKitIndex = data.redTeam.activeKitIndex;
    setState(() => _data = data);
  }

  Future<void> _save() async {
    final data = _data;
    if (data == null) {
      return;
    }
    if (data.isTeamOwnerLoggedIn(data.blueTeam)) {
      data.blueTeam
        ..name = _blueNameController.text.trim().isEmpty
            ? 'Mavi Takim'
            : _blueNameController.text.trim()
        ..formation = data.blueFormation
        ..playStyle = _bluePlayStyle
        ..aiDifficulty = _aiDifficulty
        ..playerIds = data.bluePlayerIds;
    }
    if (data.isTeamOwnerLoggedIn(data.redTeam)) {
      data.redTeam
        ..name = _redNameController.text.trim().isEmpty
            ? 'Kirmizi Takim'
            : _redNameController.text.trim()
        ..formation = data.redFormation
        ..playStyle = _redPlayStyle
        ..aiDifficulty = _aiDifficulty
        ..playerIds = data.redPlayerIds;
    }
    for (final team in data.teams) {
      team.ensureLineupDefaults(data.players);
    }
    data
      ..blueName = data.blueTeam.name
      ..redName = data.redTeam.name
      ..blueAiControlled = _blueAiControlled
      ..redAiControlled = _redAiControlled
      ..aiDifficulty = _aiDifficulty
      ..bluePlayStyle = _bluePlayStyle
      ..redPlayStyle = _redPlayStyle;
    data.blueTeam.activeKitIndex = _blueKitIndex;
    data.redTeam.activeKitIndex = _redKitIndex;
    await _storage.save(data);
  }

  Future<void> _addAccount() async {
    final data = _data;
    if (data == null || _newAccountController.text.trim().isEmpty) {
      return;
    }
    final password = await _askPassword('Yeni hesap sifresi', requireNew: true);
    if (password == null) {
      return;
    }
    final account = SavedAccountProfile.create(
      _newAccountController.text,
      password: password,
    );
    setState(() {
      data.accounts.add(account);
      data.activeAccountId = account.id;
      data.loggedInAccountIds.add(account.id);
      _newAccountController.clear();
      _setupTab = 1;
    });
    await _save();
  }

  Future<void> _switchAccount(String id) async {
    final data = _data;
    if (data == null) {
      return;
    }
    final account = data.accounts.firstWhere((account) => account.id == id);
    if (!account.hasPassword) {
      final newPassword = await _askPassword(
        '${account.username} sifre belirle',
        requireNew: true,
      );
      if (newPassword == null) {
        return;
      }
      account.setPassword(newPassword);
    } else {
      final password = await _askPassword('${account.username} sifresi');
      if (password == null || !account.checkPassword(password)) {
        _showMessage('Sifre hatali');
        return;
      }
    }
    setState(() {
      data.activeAccountId = id;
      data.loggedInAccountIds.add(id);
      _blueNameController.text = data.blueTeam.name;
      _redNameController.text = data.redTeam.name;
    });
    await _save();
  }

  Future<String?> _askPassword(String title, {bool requireNew = false}) async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(
            labelText: requireNew ? 'Yeni sifre' : 'Sifre',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (password == null || password.trim().length < 3) {
      if (password != null) {
        _showMessage('Sifre en az 3 karakter olmali');
      }
      return null;
    }
    return password.trim();
  }

  void _showMessage(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _handleSetupKey(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _pressedKeys.add(event.logicalKey);
      if (_adminComboActive() && _adminUnlockTimer == null) {
        _adminUnlockTimer = Timer(const Duration(seconds: 3), () {
          _adminUnlockTimer = null;
          if (_adminComboActive()) {
            _openAdminLogin();
          }
        });
      }
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(event.logicalKey);
      if (!_adminComboActive()) {
        _adminUnlockTimer?.cancel();
        _adminUnlockTimer = null;
      }
    }
  }

  bool _adminComboActive() {
    final ctrl =
        _pressedKeys.contains(LogicalKeyboardKey.controlLeft) ||
        _pressedKeys.contains(LogicalKeyboardKey.controlRight);
    final shift =
        _pressedKeys.contains(LogicalKeyboardKey.shiftLeft) ||
        _pressedKeys.contains(LogicalKeyboardKey.shiftRight);
    return ctrl &&
        shift &&
        _pressedKeys.contains(LogicalKeyboardKey.keyA) &&
        _pressedKeys.contains(LogicalKeyboardKey.keyD) &&
        _pressedKeys.contains(LogicalKeyboardKey.keyC);
  }

  Future<void> _openAdminLogin({int targetTab = 5}) async {
    setState(() {
      _pendingAdminTab = targetTab;
      _showAdminPasswordField = true;
      _adminPasswordError = false;
    });
  }

  Future<void> _submitAdminPassword() async {
    final data = _data;
    if (data == null) return;
    final raw = _adminPasswordController.text.trim();
    // Secret prefix "kimo@" unlocks the hidden player values/settings
    // editor. It is stripped before verifying the real admin password,
    // e.g. admin password "123456" -> type "kimo@123456".
    var password = raw;
    var fullAccess = false;
    if (raw.toLowerCase().startsWith('kimo@')) {
      fullAccess = true;
      password = raw.substring(5).trim();
    }
    if (!data.adminPasswordSet) {
      if (password.length < 3) {
        setState(() => _adminPasswordError = true);
        return;
      }
      setState(() {
        data.setAdminPassword(password);
        data.adminLoggedIn = true;
        data.adminFullAccess = fullAccess;
        _showAdminPasswordField = false;
        _adminPasswordController.clear();
        _setupTab = _pendingAdminTab;
      });
      await _save();
      return;
    }
    if (!data.checkAdminPassword(password)) {
      setState(() => _adminPasswordError = true);
      return;
    }
    setState(() {
      data.adminLoggedIn = true;
      data.adminFullAccess = fullAccess;
      _showAdminPasswordField = false;
      _adminPasswordController.clear();
      _setupTab = _pendingAdminTab;
    });
    await _save();
  }

  /// Locks the admin session (also hides the kimo@ full-access editor).
  Future<void> _lockAdmin() async {
    final data = _data;
    if (data == null) return;
    setState(() {
      data.adminLoggedIn = false;
      data.adminFullAccess = false;
      _adminSubTab = 0;
      _setupTab = 0;
    });
    await _save();
  }

  void _cancelAdminLogin() {
    setState(() {
      _showAdminPasswordField = false;
      _adminPasswordController.clear();
      _adminPasswordError = false;
    });
  }

  Future<void> _logoutAccount(String id) async {
    final data = _data;
    if (data == null || data.loggedInAccountIds.length <= 1) {
      return;
    }
    setState(() {
      data.loggedInAccountIds.remove(id);
      if (data.activeAccountId == id) {
        data.activeAccountId = data.loggedInAccountIds.first;
      }
    });
    await _save();
  }

  Future<void> _addTeam() async {
    final data = _data;
    if (data == null || _newTeamController.text.trim().isEmpty) {
      return;
    }
    final team = SavedTeamProfile.create(
      ownerAccountId: data.activeAccountId,
      name: _newTeamController.text,
      playerIds: const [],
    );
    setState(() {
      data.teams.add(team);
      data.blueTeamId = team.id;
      data.bluePlayerIds = team.playerIds;
      data.blueFormation = team.formation;
      _blueNameController.text = team.name;
      if (data.redTeamId == data.blueTeamId && data.ownedTeams.length > 1) {
        data.redTeamId = data.ownedTeams
            .firstWhere((ownedTeam) => ownedTeam.id != team.id)
            .id;
        data.redPlayerIds = data.redTeam.playerIds;
        data.redFormation = data.redTeam.formation;
        _redNameController.text = data.redTeam.name;
      }
      _newTeamController.clear();
    });
    await _save();
  }

  Future<void> _addPlayer() async {
    final data = _data;
    if (data == null || _newPlayerController.text.trim().isEmpty) {
      return;
    }
    final profile = PlayerProfile.generated(
      name: _newPlayerController.text,
      isGoalkeeper: _newIsGoalkeeper,
    );
    setState(() {
      data.players.add(profile);
      _newPlayerController.clear();
      _newIsGoalkeeper = false;
    });
    await _save();
  }

  Future<void> _importPlayersFromTextFile() async {
    final data = _data;
    final path = _importPlayersPathController.text.trim();
    if (data == null || path.isEmpty) {
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      _showMessage('Dosya bulunamadi');
      return;
    }
    final lines = await file.readAsLines();
    var added = 0;
    setState(() {
      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#')) {
          continue;
        }
        final lower = line.toLowerCase();
        final isGoalkeeper = lower.contains('gk') || lower.contains('kaleci');
        final name = line
            .replaceAll(RegExp(r'\bGK\b', caseSensitive: false), '')
            .replaceAll(RegExp('kaleci', caseSensitive: false), '')
            .replaceAll(',', ' ')
            .trim();
        if (name.isEmpty) {
          continue;
        }
        data.players.add(
          PlayerProfile.generated(name: name, isGoalkeeper: isGoalkeeper),
        );
        added += 1;
      }
    });
    await _save();
    _showMessage('$added oyuncu eklendi');
  }

  Future<void> _deletePlayer(PlayerProfile profile) async {
    final data = _data;
    if (data == null) {
      return;
    }
    setState(() {
      data.players.removeWhere((player) => player.id == profile.id);
      data.bluePlayerIds.remove(profile.id);
      data.redPlayerIds.remove(profile.id);
      data.transferRequests.removeWhere(
        (request) => request.playerId == profile.id,
      );
      for (final team in data.teams) {
        team.playerIds.remove(profile.id);
        team.starterPlayerIds.remove(profile.id);
        team.roleByPlayerId.remove(profile.id);
      }
    });
    await _save();
  }

  Future<void> _assignPlayerToTeam(
    PlayerProfile profile,
    String? teamId,
  ) async {
    final data = _data;
    if (data == null) {
      return;
    }
    if (teamId != null) {
      final target = data.teams.firstWhere((team) => team.id == teamId);
      if (!data.ownsTeam(target)) {
        return;
      }
    }
    setState(() {
      for (final team in data.teams) {
        team.playerIds.remove(profile.id);
        team.starterPlayerIds.remove(profile.id);
        team.roleByPlayerId.remove(profile.id);
      }
      if (teamId != null) {
        final team = data.teams.firstWhere((team) => team.id == teamId);
        team.playerIds.add(profile.id);
        team.roleByPlayerId[profile.id] = profile.isGoalkeeper
            ? PlayerRole.goalkeeper
            : PlayerRole.midfieldLeft;
        if (team.starterPlayerIds.length < 11) {
          team.starterPlayerIds.add(profile.id);
        }
      }
      if (data.teams.any((team) => team.id == data.blueTeamId)) {
        data.bluePlayerIds = data.blueTeam.playerIds;
      }
      if (data.teams.any((team) => team.id == data.redTeamId)) {
        data.redPlayerIds = data.redTeam.playerIds;
      }
    });
    await _save();
  }

  Future<void> _editPlayerName(PlayerProfile profile) async {
    final controller = TextEditingController(text: profile.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Oyuncu adini duzenle'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Oyuncu adi'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) {
      return;
    }
    setState(() => profile.name = name.trim());
    await _save();
  }

  Future<void> _openAccountDetail() async {
    await _save();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AccountDetailScreen()));
    _load();
  }

  Future<void> _startMatch() async {
    final data = _data;
    if (data == null) {
      return;
    }
    for (final player in data.players) {
      player.recoverFitness(DateTime.now());
    }
    await _save();
    if (!mounted) {
      return;
    }
    if (data.blueTeamId == data.redTeamId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Iki taraf icin farkli takim sec')),
      );
      return;
    }
    final blueValidation = _teamValidation(data.blueTeam, data);
    final redValidation = _teamValidation(data.redTeam, data);
    if (blueValidation != null || redValidation != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(blueValidation ?? redValidation!)));
      return;
    }
    final bluePlayers = data.players
        .where((profile) => data.bluePlayerIds.contains(profile.id))
        .toList();
    final redPlayers = data.players
        .where((profile) => data.redPlayerIds.contains(profile.id))
        .toList();
    final setup = MatchSetup(
      mode: data.mode,
      blueAiControlled: _blueAiControlled,
      redAiControlled: _redAiControlled,
      aiDifficulty: _aiDifficulty,
      bluePlayStyle: _bluePlayStyle,
      redPlayStyle: _redPlayStyle,
      blue: TeamSetup(
        id: TeamId.blue,
        name: _blueNameController.text,
        formation: data.blueFormation,
        players: bluePlayers,
        starterPlayerIds: data.blueTeam.starterPlayerIds,
        roleByPlayerId: data.blueTeam.roleByPlayerId,
        slotByPlayerId: data.blueTeam.slotByPlayerId,
        storageTeamId: data.blueTeam.id,
        rating: data.blueTeam.rating,
        jerseyKit: data.blueTeam.activeKit,
        goalkeeperKit: data.blueTeam.goalkeeperKit,
      ),
      red: TeamSetup(
        id: TeamId.red,
        name: _redNameController.text,
        formation: data.redFormation,
        players: redPlayers,
        starterPlayerIds: data.redTeam.starterPlayerIds,
        roleByPlayerId: data.redTeam.roleByPlayerId,
        slotByPlayerId: data.redTeam.slotByPlayerId,
        storageTeamId: data.redTeam.id,
        rating: data.redTeam.rating,
        jerseyKit: data.redTeam.activeKit,
        goalkeeperKit: data.redTeam.goalkeeperKit,
      ),
    );
    if (!mounted) {
      return;
    }
    final result = await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => GameScreen(setup: setup)));
    if (result is FinishedMatchSummary) {
      _applyMatchSummary(data, result);
      await _save();
    }
    _load();
  }

  String? _teamValidation(SavedTeamProfile team, SavedGameData data) {
    if (team.ownerAccountId.isEmpty) {
      return '${team.name}: once takim sahibi secilmeli';
    }
    if (!data.isTeamOwnerLoggedIn(team)) {
      return '${team.name}: takim sahibi giris yapmali';
    }
    final unavailableStarter = data.players.where(
      (player) =>
          team.starterPlayerIds.contains(player.id) && player.isUnavailable,
    );
    if (unavailableStarter.isNotEmpty) {
      final player = unavailableStarter.first;
      final reason = player.isSuspended
          ? '${player.suspendedMatchesRemaining} mac cezali'
          : '${player.injuredDaysRemaining} gun sakat';
      return '${team.name}: ${player.name} $reason ve oynayamaz';
    }
    team.ensureLineupDefaults(data.players);
    final selected = data.players
        .where((profile) => team.playerIds.contains(profile.id))
        .toList();
    final starters = selected
        .where((profile) => team.starterPlayerIds.contains(profile.id))
        .toList();
    final keepers = selected.where((profile) => profile.isGoalkeeper).length;
    final fielders = selected.where((profile) => !profile.isGoalkeeper).length;
    if (keepers < 1 || fielders < 10) {
      return '${team.name}: en az 10 saha oyuncusu ve 1 kaleci gerekli';
    }
    final starterKeepers = starters
        .where((profile) => profile.isGoalkeeper)
        .length;
    final starterFielders = starters
        .where((profile) => !profile.isGoalkeeper)
        .length;
    if (starters.length != 11 || starterKeepers != 1 || starterFielders != 10) {
      return '${team.name}: 1 kaleci ve 10 saha oyuncusu ilk 11 secilmeli';
    }
    return null;
  }

  void _applyMatchSummary(SavedGameData data, FinishedMatchSummary summary) {
    data.archiveMatch(summary);
    final blue = data.teams.where(
      (team) => team.id == summary.blueStorageTeamId,
    );
    final red = data.teams.where((team) => team.id == summary.redStorageTeamId);
    if (blue.isEmpty || red.isEmpty) {
      return;
    }
    final blueTeam = blue.first;
    final redTeam = red.first;
    final blueBefore = blueTeam.rating;
    final redBefore = redTeam.rating;
    late final String blueResult;
    late final String redResult;
    if (summary.blueScore > summary.redScore) {
      blueTeam.wins += 1;
      redTeam.losses += 1;
      blueResult = 'Galibiyet';
      redResult = 'Maglubiyet';
    } else if (summary.redScore > summary.blueScore) {
      redTeam.wins += 1;
      blueTeam.losses += 1;
      blueResult = 'Maglubiyet';
      redResult = 'Galibiyet';
    } else {
      blueTeam.draws += 1;
      redTeam.draws += 1;
      blueResult = 'Beraberlik';
      redResult = 'Beraberlik';
    }
    blueTeam.rating = (blueTeam.rating + summary.blueRatingDelta)
        .clamp(1, 99)
        .toDouble();
    redTeam.rating = (redTeam.rating + summary.redRatingDelta)
        .clamp(1, 99)
        .toDouble();
    final timestamp = summary.timestamp;
    blueTeam.addMatchRecord(
      TeamMatchRecord(
        matchId: summary.matchId,
        opponentName: summary.redName,
        scoreText: '${summary.blueScore}-${summary.redScore}',
        result: blueResult,
        ratingBefore: blueBefore,
        ratingAfter: blueTeam.rating,
        possessionPercent: summary.bluePossessionPercent,
        passes: summary.bluePasses,
        successfulPasses: summary.blueSuccessfulPasses,
        shots: summary.blueShots,
        goals: summary.blueScore,
        timestamp: timestamp,
      ),
    );
    redTeam.addMatchRecord(
      TeamMatchRecord(
        matchId: summary.matchId,
        opponentName: summary.blueName,
        scoreText: '${summary.redScore}-${summary.blueScore}',
        result: redResult,
        ratingBefore: redBefore,
        ratingAfter: redTeam.rating,
        possessionPercent: summary.redPossessionPercent,
        passes: summary.redPasses,
        successfulPasses: summary.redSuccessfulPasses,
        shots: summary.redShots,
        goals: summary.redScore,
        timestamp: timestamp,
      ),
    );

    // Only players who missed this fixture serve one suspension match or
    // receive one week of injury recovery. Newly injured/sent-off players
    // have a record for this match, so their new penalty is not shortened.
    final involvedIds = {...blueTeam.playerIds, ...redTeam.playerIds};
    for (final player in data.players.where(
      (profile) => involvedIds.contains(profile.id),
    )) {
      final playedThisMatch = player.matchHistory.any(
        (record) => record.matchId == summary.matchId,
      );
      if (!playedThisMatch && player.isUnavailable) {
        player.advanceUnavailableStatusAfterTeamMatch();
      }
    }
  }

  static const List<(int, IconData, String)> _navItems = [
    (0, Icons.account_circle, 'Hesap'),
    (1, Icons.sports_soccer, 'Mac'),
    (2, Icons.groups, 'Takimlar'),
    (3, Icons.directions_run, 'Oyuncular'),
    (4, Icons.help_outline, 'Aciklama'),
    (5, Icons.admin_panel_settings, 'Yonetim'),
    (6, Icons.gavel, 'Cezalar'),
  ];

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return KeyboardListener(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: _handleSetupKey,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xff07130e),
                Color(0xff04100a),
                Color(0xff0a1a12),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sideNav(data),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      children: [
                        _headerBar(data),
                        const SizedBox(height: 12),
                        Expanded(child: _setupPage(data)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sideNav(SavedGameData data) {
    final account = data.activeAccount;
    return Container(
      width: 110,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xff0e1f18), Color(0xff081310)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffd4af37).withValues(alpha: 0.22)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xff00c896), Color(0xff0a7d5a)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xff00c896).withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.sports_soccer, size: 30, color: Colors.white),
            ),
            const SizedBox(height: 6),
            const Text(
              'BOMBAN',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.8,
                color: Color(0xfff5d67b),
              ),
            ),
            const Text(
              'FUTBOL',
              style: TextStyle(
                fontSize: 8.5,
                letterSpacing: 3.4,
                color: Colors.white38,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                children: [
                  for (final item in _navItems)
                    _navItem(data, item.$1, item.$2, item.$3),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _setupTab = 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 11,
                      backgroundColor:
                          const Color(0xff00c896).withValues(alpha: 0.45),
                      child: Text(
                        account.username.isNotEmpty
                            ? account.username[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        account.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(
    SavedGameData data,
    int value,
    IconData icon,
    String label,
  ) {
    final active = _setupTab == value;
    final locked = (value == 5 || value == 6) && data.adminLoggedIn != true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            // CEZALAR and Yonetim stay visible but always ask for the
            // admin password when the admin is not logged in.
            if (locked) {
              _openAdminLogin(targetTab: value);
              return;
            }
            setState(() => _setupTab = value);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              gradient: active
                  ? const LinearGradient(
                      colors: [Color(0xff12402e), Color(0xff0d2b20)],
                    )
                  : null,
              borderRadius: BorderRadius.circular(14),
              border: active
                  ? Border.all(
                      color: const Color(0xffffd34d).withValues(alpha: 0.65),
                      width: 1.2,
                    )
                  : Border.all(color: Colors.transparent),
              boxShadow: active
                  ? const [BoxShadow(color: Color(0x3300c896), blurRadius: 10)]
                  : const [],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: active
                      ? const Color(0xfff5d67b)
                      : (locked ? Colors.white30 : Colors.white60),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: active ? Colors.white : Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerBar(SavedGameData data) {
    final (title, subtitle) = switch (_setupTab) {
      0 => (
          'Hesaplar',
          'Hesap olustur, giris yap ve aktif duzenleyiciyi sec'
        ),
      1 => ('Mac Ayarlari', 'Takim, dizilis, forma ve kadroyu sec'),
      2 => ('Takimlar', 'Takim yonetimi, formlar, degerler ve sonuclar'),
      3 => ('Oyuncular', 'Kadroyu yonet; oyuncuya tiklayip profilini ac'),
      4 => ('Aciklama', 'Nasil oynanir, kisayollar ve yonetim'),
      5 => ('Yonetim', 'Yonetici paneli'),
      _ => ('Cezalar', 'Ceza ve sakatlik yonetimi'),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 13, 20, 13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff0d1d16), Color(0xff0a1511)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffd4af37).withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (_showAdminPasswordField)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _adminPasswordController,
                    autofocus: true,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: data.adminPasswordSet
                          ? 'Yonetici sifresi'
                          : 'Yeni yonetici sifresi',
                      hintStyle: const TextStyle(color: Colors.white38),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: _adminPasswordError
                              ? Colors.redAccent
                              : const Color(0xffffd34d),
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      isDense: true,
                      errorText: _adminPasswordError ? 'Hatali sifre' : null,
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    onSubmitted: (_) => _submitAdminPassword(),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.check, color: Color(0xffffd34d)),
                  onPressed: _submitAdminPassword,
                  tooltip: 'Onayla',
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: _cancelAdminLogin,
                  tooltip: 'Iptal',
                ),
              ],
            ),
          if (!_showAdminPasswordField) ...[
            OutlinedButton.icon(
              onPressed: _openAccountDetail,
              icon: const Icon(Icons.person, size: 18, color: Colors.white70),
              label: Text(
                data.activeAccount.username,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24, width: 1),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _startMatch,
              icon: const Icon(Icons.play_arrow),
              label: const Text(
                'Maca basla',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff00c896),
                foregroundColor: const Color(0xff00130c),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shadowColor: const Color(0xff00c896).withValues(alpha: 0.5),
                elevation: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _setupPage(SavedGameData data) {
    return switch (_setupTab) {
      0 => _accountPage(data),
      1 => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 430, child: _matchSettings(data)),
          const SizedBox(width: 18),
          Expanded(child: _teamSummary(data)),
        ],
      ),
      2 => _teamsPage(data),
      3 => _playerPool(data),
      5 => data.adminLoggedIn ? _adminPage(data) : _lockedAdminPage(),
      6 => data.adminLoggedIn ? _penaltiesPage(data) : _lockedPenaltiesPage(),
      _ => _helpPage(),
    };
  }

  Widget _accountPage(SavedGameData data) {
    final query = _accountSearch.trim().toLowerCase();
    final accounts = data.accounts
        .where(
          (account) => query.isEmpty ||
              account.username.toLowerCase().contains(query),
        )
        .toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Hesaplar',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _newAccountController,
                  decoration: const InputDecoration(
                    labelText: 'Yeni hesap adi',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addAccount(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _addAccount,
                icon: const Icon(Icons.add),
                label: const Text('Olustur'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Hesap ara',
              isDense: true,
            ),
            onChanged: (value) => setState(() => _accountSearch = value),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: accounts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final account = accounts[index];
                final teamCount = data.teams
                    .where(
                      (team) =>
                          team.ownerAccountId == account.id && !team.isDeleted,
                    )
                    .length;
                final active = account.id == data.activeAccountId;
                final loggedIn = data.isAccountLoggedIn(account.id);
                return ExpansionTile(
                  leading: Icon(
                    loggedIn ? Icons.verified_user : Icons.account_circle,
                    color: loggedIn ? Colors.greenAccent : Colors.white70,
                  ),
                  title: Text(account.username),
                  subtitle: Text(
                    'Takim sayisi: $teamCount${active ? ' | aktif duzenleyici' : ''}',
                  ),
                  trailing: SizedBox(
                    width: 170,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (!active)
                          OutlinedButton(
                            onPressed: () => _switchAccount(account.id),
                            child: Text(loggedIn ? 'Aktif' : 'Giris'),
                          ),
                        if (loggedIn)
                          TextButton(
                            onPressed: data.loggedInAccountIds.length <= 1
                                ? null
                                : () => _logoutAccount(account.id),
                            child: const Text('Cikis'),
                          ),
                      ],
                    ),
                  ),
                  children: [
                    for (final team in data.teams.where(
                      (team) =>
                          team.ownerAccountId == account.id && !team.isDeleted,
                    ))
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.shield_outlined),
                        title: Text(team.name),
                        subtitle: Text(
                          team.playerIds
                              .take(12)
                              .map((id) {
                                final matches = data.players
                                    .where((profile) => profile.id == id)
                                    .toList();
                                if (matches.isEmpty) {
                                  return '';
                                }
                                final role = team.roleByPlayerId[id];
                                return '${matches.first.name}${role == null ? '' : ' (${role.code})'}';
                              })
                              .where((text) => text.isNotEmpty)
                              .join(', '),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _matchSettings(SavedGameData data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: ListView(
        children: [
          const Text(
            'Mac ayarlari',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          _teamDropdown(
            title: 'Mavi takim',
            value: data.blueTeamId,
            onChanged: (id) {
              final team = data.teams.firstWhere((team) => team.id == id);
              setState(() {
                data.blueTeamId = team.id;
                data.bluePlayerIds = team.playerIds;
                data.blueFormation = team.formation;
                _bluePlayStyle = team.playStyle;
                _blueNameController.text = team.name;
              });
              _save();
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _blueNameController,
            decoration: const InputDecoration(labelText: 'Mavi takim adi'),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 10),
          _teamDropdown(
            title: 'Kirmizi takim',
            value: data.redTeamId,
            onChanged: (id) {
              final team = data.teams.firstWhere((team) => team.id == id);
              setState(() {
                data.redTeamId = team.id;
                data.redPlayerIds = team.playerIds;
                data.redFormation = team.formation;
                _redPlayStyle = team.playStyle;
                _redNameController.text = team.name;
              });
              _save();
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _redNameController,
            decoration: const InputDecoration(labelText: 'Kirmizi takim adi'),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 18),
          const Text('Mac tipi', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          SegmentedButton<MatchMode>(
            segments: [
              ButtonSegment(
                value: MatchMode.league,
                label: Text(MatchMode.league.title),
              ),
              ButtonSegment(
                value: MatchMode.knockout,
                label: Text(MatchMode.knockout.title),
              ),
            ],
            selected: {data.mode},
            onSelectionChanged: (selection) {
              setState(() => data.mode = selection.first);
              _save();
            },
          ),
          const SizedBox(height: 8),
          Text(
            data.mode.description,
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          const Divider(height: 28),
          _formationDropdown(
            title: 'Mavi dizilis',
            value: data.blueFormation,
            onChanged: (value) {
              setState(() => data.blueFormation = value);
              _save();
            },
          ),
          const SizedBox(height: 12),
          _formationDropdown(
            title: 'Kirmizi dizilis',
            value: data.redFormation,
            onChanged: (value) {
              setState(() => data.redFormation = value);
              _save();
            },
          ),
          const Divider(height: 28),
          const Text(
            'Yapay zeka ve oyun stili',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mavi takim AI kontrolu'),
            value: _blueAiControlled,
            onChanged: (value) {
              setState(() => _blueAiControlled = value);
              _save();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Kirmizi takim AI kontrolu'),
            value: _redAiControlled,
            onChanged: (value) {
              setState(() => _redAiControlled = value);
              _save();
            },
          ),
          DropdownButtonFormField<AiDifficulty>(
            value: _aiDifficulty,
            decoration: const InputDecoration(labelText: 'AI zorlugu'),
            items: AiDifficulty.values
                .map(
                  (difficulty) => DropdownMenuItem(
                    value: difficulty,
                    child: Text(difficulty.title),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _aiDifficulty = value);
              _save();
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<AiPlayStyle>(
            value: _bluePlayStyle,
            decoration: const InputDecoration(labelText: 'Mavi oyun stili'),
            items: AiPlayStyle.values
                .map((style) => DropdownMenuItem(
                      value: style,
                      child: Text(style.title),
                    ))
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _bluePlayStyle = value);
              _save();
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<AiPlayStyle>(
            value: _redPlayStyle,
            decoration: const InputDecoration(labelText: 'Kirmizi oyun stili'),
            items: AiPlayStyle.values
                .map((style) => DropdownMenuItem(
                      value: style,
                      child: Text(style.title),
                    ))
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _redPlayStyle = value);
              _save();
            },
          ),
          const Divider(height: 28),
          const Text(
            'Penalti aciklamasi',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'Eleme macinda skor esit kalirsa oyun 120. dakikaya uzar. Sonra penaltilar otomatik ve akilli sekilde oynanir: sut yonu, yukseklik, kaleci tahmini ve oyuncu boyu sonuca etki eder.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _formationDropdown({
    required String title,
    required FormationType value,
    required ValueChanged<FormationType> onChanged,
  }) {
    return DropdownButtonFormField<FormationType>(
      value: value,
      decoration: InputDecoration(labelText: title),
      items: playableFormationTypes
          .map((type) => DropdownMenuItem(value: type, child: Text(type.title)))
          .toList(),
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }

  Widget _teamsPage(SavedGameData data) {
    final query = _teamSearch.trim().toLowerCase();
    final teams = data.activeTeams
        .where(
          (team) => query.isEmpty || team.name.toLowerCase().contains(query),
        )
        .toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Takimlar',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _newTeamController,
                  decoration: const InputDecoration(
                    labelText: 'Yeni takim',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addTeam(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _addTeam,
                icon: const Icon(Icons.add),
                label: const Text('Ekle'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Takim ara',
              isDense: true,
            ),
            onChanged: (value) => setState(() => _teamSearch = value),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: teams.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final team = teams[index];
                final players = data.players
                    .where((player) => team.playerIds.contains(player.id))
                    .toList();
                final keepers = players.where((p) => p.isGoalkeeper).length;
                final fielders = players.where((p) => !p.isGoalkeeper).length;
                return ListTile(
                  onTap: () => _openTeamPlayers(team.id),
                  leading: const Icon(Icons.shield),
                  title: Text(team.name),
                  subtitle: Text(
                    'Oyuncu ${players.length} | saha $fielders | kaleci $keepers | Toplam deger ${formatMarketValue(data.teamTotalValue(team))} | G ${team.wins} B ${team.draws} M ${team.losses} | ${team.formText}',
                  ),
                  trailing: SizedBox(
                    width: 344,
                    child: Row(
                      children: [
                        Expanded(child: _ownerDropdown(data, team)),
                        const SizedBox(width: 10),
                        Text(
                          team.rating.toStringAsFixed(1),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(width: 2),
                        IconButton(
                          tooltip: 'Takim sonucu ve mac gecmisi',
                          onPressed: () => _openTeamDetail(team.id),
                          icon: const Icon(Icons.receipt_long),
                        ),
                        IconButton(
                          tooltip: 'Formalar (renkler)',
                          onPressed: () => _showKitManager(team),
                          icon: const Icon(Icons.checkroom),
                        ),
                        IconButton(
                          tooltip: 'Oyunculari yonet',
                          onPressed: () => _openTeamPlayers(team.id),
                          icon: const Icon(Icons.manage_search),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _ownerDropdown(SavedGameData data, SavedTeamProfile team) {
    final canChangeOwner = data.adminLoggedIn || team.ownerAccountId.isEmpty;
    return DropdownButtonFormField<String>(
      value: data.accounts.any((account) => account.id == team.ownerAccountId)
          ? team.ownerAccountId
          : null,
      decoration: const InputDecoration(labelText: 'Sahip', isDense: true),
      items: data.accounts
          .map(
            (account) => DropdownMenuItem(
              value: account.id,
              child: Text(account.username, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: canChangeOwner
          ? (value) {
              if (value == null) {
                return;
              }
              setState(() => team.ownerAccountId = value);
              _save();
            }
          : null,
    );
  }

  Widget _helpPage() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: const SingleChildScrollView(
        child: Text(
          'Mac sayfasi: iki takimi ve dizilisi sec.\n\n'
          'Hesaplar sayfasi: hesap olustur, giris yap ve aktif duzenleyici hesabi sec. Farkli sahipli iki takim oynayabilir ama mac baslamadan iki takim sahibinin de giris yapmis olmasi gerekir.\n\n'
          'Takimlar sayfasi: tum takimlari, takim sahibini, guc puanini ve galibiyet/maglubiyet durumunu gosterir. Sahipsiz takimlara buradan sahip sec.\n\n'
          'Oyuncular sayfasi: oyuncu ekle, adini duzenle, kaleci olarak isaretle ve oyuncuyu yalniz bir takima bagla. Bir oyuncu baska takima verilirse eski takimindan otomatik cikar.\n\n'
          'Mac kadrolari: her takim icin ilk 11, yedekler ve oyuncu mevkisini sec. Takim sahibi giris yapmadan kadro duzenlenmez.\n\n'
          'Oyun icinde F1/F2 gorsel dizilis ve degisiklik ekranini acar. Oyuncularin yerini surukleyerek hak kullanmadan degistirebilir, yedegi sahadaki daireye birakarak degisiklik yapabilirsin. F8 kaleci tahmin, erisim ve karar debug cizgilerini acar.\n\n'
          'VAR icin R tusuna iki kez bas. Alt cubuk kaydi akici oynatir; oklar veya A/D kaydi 3 saniyelik adimlarla ileri geri alir. HIZ satirindaki dugmeler (veya - / + tuslari) oynatmayi 0.25x ile 4.0x arasinda yavaslatir/hizlandirir. Her VAR karari (faul, el, ofsayt, kart, penalti, gol) aninda, o saniyede uygulanir; OLAYLAR listesinden her karar iptal edilebilir veya geri verilebilir. Golu iptal veya geri al dugmesi de calisir.\n\n'
          'Takim Oyuncuları sayfasinda siralama menusuyle oyuncu degerine, puan ortalamasina, gole, pase, hiz veya bitiricilige gore sirala ve oyuncu adini panoya kopyala. Ulke atamasi ve yeni ulke ekleme isi Yonetim > Ulkeler tanesinden yapilir; takim silme yalnizca Yonetim panelindendir.\n\n'
          'Kirmizi kart 1 mac stop cezasina mal olur. Degisiklik panelinde SAHADAN AYRILANLAR listesinden cikmis bir oyuncuyu sakat/kirmizi kartli oyuncunun yerine geri dondur; harris sakatlanir ve harris yedegi yoksa "Kaleci sec" ile sahadaki bir oyuncuyu kaleci yapabilirsin. Mac sonuc ekraninda kartlarin dakikalari ve takim istatistiklari (top, pas, sut, faul, kart) goruntulenir. Yonetim > Değer (kimo@): takim geneli deger artir/azalt (kucuk/buyuk) veya coklu oyuncu secip ozellik bazinda toplu duzeltme yap.\n\n'
          'Formalar: her takim kendi forma listesini tutar. Mac sayfasindaki forma satirindaki + tusu veya Takimlar sayfasindaki forma simgesiyle yeni forma ekleyebilirsin; forma/short/corap/numara/kaleci renklerini hazir renk secicisinden ya da ozel renk olusturucustan (ton + parlaklik) secersin. Her takima istedigince forma ekleyebilir, kullan, duzenle, kopyalayabilir veya silebilirsin....\n\n'
          'Oyuncu profili: herhangi bir sayfada oyuncu adina tiklayinca tam profil acilir — her macin skoru, dakikasi, golu ve asisti (dakikalarlariyla), aldigi puan (not), kartlari ve istatistikleri; 8.5 uzeri not alan "macin adami" oldugu maclar ayri listede; piyasa degeri ve tum ozellikler de gosterilir....\n\n'
          'Takim sayfasi: takim adina tiklayinca (veya Takimlar sayfasindaki fis simgesiyle) tum mac sonuclari, form durumu (ornek: 4 galibiyet art arda) ve kadronun toplam piyasa degeri goruntulenir.',
          style: TextStyle(color: Colors.white70, height: 1.55, fontSize: 15),
        ),
      ),
    );
  }

  Widget _teamDropdown({
    required String title,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final data = _data!;
    final teams = data.activeTeams;
    if (teams.isEmpty) {
      return InputDecorator(
        decoration: InputDecoration(labelText: title),
        child: const Text('Kayitli takim yok'),
      );
    }
    final currentValue = teams.any((team) => team.id == value)
        ? value
        : teams.first.id;
    return DropdownButtonFormField<String>(
      value: currentValue,
      decoration: InputDecoration(labelText: title),
      items: teams
          .map(
            (team) => DropdownMenuItem(
              value: team.id,
              child: Text(
                '${team.name}  ${data.isTeamOwnerLoggedIn(team) ? 'giris var' : 'giris yok'}  ${team.rating.toStringAsFixed(1)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (id) {
        if (id != null) {
          onChanged(id);
        }
      },
    );
  }

  Widget _playerPool(SavedGameData data) {
    final query = _playerSearch.trim().toLowerCase();
    bool matches(PlayerProfile player) =>
        query.isEmpty ||
        player.name.toLowerCase().contains(query) ||
        (player.number?.toString().contains(query) ?? false);
    final goalkeepers = data.players
        .where((player) => player.isGoalkeeper && matches(player))
        .toList()
      ..sort((a, b) => b.effectiveOverall.compareTo(a.effectiveOverall));
    final fieldPlayers = data.players
        .where((player) => !player.isGoalkeeper && matches(player))
        .toList()
      ..sort((a, b) => b.effectiveOverall.compareTo(a.effectiveOverall));
    return Container(
      decoration: _panelDecoration(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Kayitli oyuncular',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _openFreeAgents,
                  icon: const Icon(Icons.person_search, size: 18),
                  label: const Text('Serbest oyuncular'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _newPlayerController,
                    decoration: const InputDecoration(
                      labelText: 'Oyuncu adi',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addPlayer(),
                  ),
                ),
                const SizedBox(width: 10),
                FilterChip(
                  selected: _newIsGoalkeeper,
                  label: const Text('Kaleci'),
                  onSelected: (value) =>
                      setState(() => _newIsGoalkeeper = value),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _addPlayer,
                  icon: const Icon(Icons.add),
                  label: const Text('Ekle'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _importPlayersPathController,
                    decoration: const InputDecoration(
                      labelText: 'TXT dosya yolu',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _importPlayersFromTextFile,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Ice aktar'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Oyuncu ara (ad veya numara)',
                isDense: true,
              ),
              onChanged: (value) => setState(() => _playerSearch = value),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                _playerSection('Saha oyunculari', fieldPlayers, data),
                const Divider(height: 18),
                _playerSection('Kaleciler', goalkeepers, data),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerSection(
    String title,
    List<PlayerProfile> players,
    SavedGameData data,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Text(
            '$title (${players.length})',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        if (players.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text('Kayit yok', style: TextStyle(color: Colors.white54)),
          ),
        for (final profile in players) _playerRow(data, profile),
      ],
    );
  }

  SavedTeamProfile? _teamForPlayer(SavedGameData data, PlayerProfile profile) {
    for (final team in data.activeTeams) {
      if (team.playerIds.contains(profile.id)) {
        return team;
      }
    }
    return null;
  }

  Widget _playerRow(SavedGameData data, PlayerProfile profile) {
    final assignedTeam = _teamForPlayer(data, profile);
    final canEdit =
        assignedTeam == null ||
        assignedTeam.ownerAccountId == data.activeAccountId;
    final ownedTeams = data.ownedTeams;
    final currentValue = canEdit ? assignedTeam?.id : null;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            profile.isGoalkeeper ? Icons.back_hand : Icons.directions_run,
            color: profile.isGoalkeeper
                ? const Color(0xffffd34d)
                : Colors.white70,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => _openPlayerDetail(profile.id),
                  child: Tooltip(
                    message: 'Oyuncu profilini ac (maclar, goller, asistler, puanlar)',
                    child: Text(
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xffdce8e2),
                      ),
                    ),
                  ),
                ),
                Text(
                  'Rey:${profile.effectiveOverall.toStringAsFixed(0)} SutGuc:${profile.shotPowerRating.toStringAsFixed(0)} Sut%:${profile.shootingAccuracyPercent} Hiz:${profile.speedRating.toStringAsFixed(0)} Enerji:${profile.staminaRating.toStringAsFixed(0)} Day:${profile.dayaniklilikGucu.toStringAsFixed(0)} Gol:${profile.goals} Pas:${profile.successfulPasses}/${profile.passes} Deger:${profile.marketValueText}${profile.isSuspended ? ' • CEZALI ${profile.suspendedMatchesRemaining} mac' : ''}${profile.isInjured ? ' • SAKAT ${profile.injuredDaysRemaining} gun' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 56,
            child: Text('${profile.heightMeters.toStringAsFixed(2)} m'),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 190,
            child: canEdit
                ? DropdownButtonFormField<String>(
                    value: ownedTeams.any((team) => team.id == currentValue)
                        ? currentValue
                        : null,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Takim'),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Bos'),
                      ),
                      ...ownedTeams.map(
                        (team) => DropdownMenuItem<String>(
                          value: team.id,
                          child: Text(
                            team.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => _assignPlayerToTeam(profile, value),
                  )
                : Text(
                    '${assignedTeam.name} hesabinda',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
          ),
          IconButton(
            tooltip: 'Duzenle',
            onPressed: canEdit ? () => _editPlayerName(profile) : null,
            icon: const Icon(Icons.edit),
          ),
          IconButton(
            tooltip: data.adminFullAccess
                ? 'Sil'
                : 'Oyuncu silme islemini sadece yonetici (admin) yapabilir',
            onPressed: data.adminFullAccess
                ? () => _deletePlayer(profile)
                : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  Widget _lockedPenaltiesPage() {
    return Center(
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(28),
        decoration: _adminPanelDecoration(Colors.redAccent),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 54, color: Colors.redAccent),
            const SizedBox(height: 12),
            const Text(
              'CEZALAR sayfasi kilitli',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Oyuncu mac cezalarini gormek ve degistirmek icin yonetici sifresi gerekir.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => _openAdminLogin(targetTab: 6),
              icon: const Icon(Icons.password),
              label: const Text('Sifre ile ac'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _penaltiesPage(SavedGameData data) {
    final query = _penaltySearch.trim().toLowerCase();
    final activeTeams = data.teams.where((team) => !team.isDeleted).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final assignedIds = activeTeams.expand((team) => team.playerIds).toSet();
    final unassigned = data.players
        .where(
          (player) =>
              !assignedIds.contains(player.id) &&
              (query.isEmpty || player.name.toLowerCase().contains(query)),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final groups = <(String, List<PlayerProfile>)>[];
    for (final team in activeTeams) {
      final teamMatches = query.isNotEmpty &&
          team.name.toLowerCase().contains(query);
      final players = data.players
          .where(
            (player) =>
                team.playerIds.contains(player.id) &&
                (query.isEmpty ||
                    teamMatches ||
                    player.name.toLowerCase().contains(query)),
          )
          .toList()
        ..sort((a, b) {
          final suspension = b.suspendedMatchesRemaining.compareTo(
            a.suspendedMatchesRemaining,
          );
          return suspension != 0 ? suspension : a.name.compareTo(b.name);
        });
      if (players.isNotEmpty || query.isEmpty) {
        groups.add((team.name, players));
      }
    }
    if (unassigned.isNotEmpty) groups.add(('Takimsiz oyuncular', unassigned));
    final suspendedCount = data.players
        .where((player) => player.suspendedMatchesRemaining > 0)
        .length;
    return Container(
      decoration: _adminPanelDecoration(Colors.redAccent),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.gavel, color: Colors.redAccent, size: 30),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CEZALAR',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Oyuncular takimlarina gore gruplanir. Eksi/arti ile mac cezasini degistir.',
                        style: TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.block, size: 17),
                  label: Text('$suspendedCount cezali oyuncu'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _lockAdmin,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Kilitle'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Takim veya oyuncu ara',
                isDense: true,
              ),
              onChanged: (value) => setState(() => _penaltySearch = value),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: groups.isEmpty
                ? const Center(
                    child: Text(
                      'Aramaya uygun takim veya oyuncu bulunamadi.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      final activeSuspensions = group.$2
                          .where(
                            (player) => player.suspendedMatchesRemaining > 0,
                          )
                          .length;
                      return Card(
                        color: const Color(0xff0d1a16),
                        margin: const EdgeInsets.only(bottom: 9),
                        child: ExpansionTile(
                          key: ValueKey('${group.$1}-$query'),
                          initiallyExpanded: query.isNotEmpty,
                          leading: const CircleAvatar(
                            backgroundColor: Color(0x22ff5252),
                            child: Icon(Icons.shield, color: Colors.redAccent),
                          ),
                          title: Text(
                            group.$1,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            '${group.$2.length} oyuncu • $activeSuspensions cezali',
                          ),
                          children: [
                            for (final player in group.$2)
                              _penaltyPlayerRow(player),
                            if (group.$2.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'Bu takimda oyuncu yok.',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _penaltyPlayerRow(PlayerProfile player) {
    final matches = player.suspendedMatchesRemaining;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: matches > 0
            ? Colors.redAccent.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: matches > 0
              ? Colors.redAccent.withValues(alpha: 0.35)
              : Colors.white10,
        ),
      ),
      child: Row(
        children: [
          Icon(
            player.isGoalkeeper ? Icons.back_hand : Icons.person,
            color: matches > 0 ? Colors.redAccent : Colors.white60,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  'Sari ${player.yellowCards} • Kirmizi ${player.redCards} • OVR ${player.effectiveOverall.round()}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Bir mac azalt',
            onPressed: matches <= 0
                ? null
                : () {
                    setState(() => player.suspendedMatchesRemaining -= 1);
                    _save();
                  },
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 92,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _setPlayerSuspensionDialog(player),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '$matches MAC',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: matches > 0
                        ? Colors.redAccent
                        : Colors.greenAccent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Bir mac ekle',
            onPressed: matches >= 50
                ? null
                : () {
                    setState(() {
                      player.suspendedMatchesRemaining = (matches + 1)
                          .clamp(0, 50)
                          .toInt();
                    });
                    _save();
                  },
            icon: const Icon(Icons.add_circle_outline),
          ),
          PopupMenuButton<int>(
            tooltip: 'Ceza sayisini dogrudan sec',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              setState(() => player.suspendedMatchesRemaining = value);
              _save();
            },
            itemBuilder: (context) => [
              for (final value in const [0, 1, 2, 3, 5, 10, 20, 30, 50])
                PopupMenuItem(value: value, child: Text('$value mac')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _setPlayerSuspensionDialog(PlayerProfile player) async {
    final controller = TextEditingController(
      text: '${player.suspendedMatchesRemaining}',
    );
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xff101820),
        title: Text('${player.name} • Mac cezasi'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Oynayamayacagi mac sayisi',
            helperText: '0 cezayi tamamen kaldirir.',
          ),
          onSubmitted: (text) {
            final parsed = int.tryParse(text.trim());
            if (parsed != null) {
              Navigator.of(dialogContext).pop(parsed.clamp(0, 99).toInt());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              if (parsed != null) {
                Navigator.of(
                  dialogContext,
                ).pop(parsed.clamp(0, 99).toInt());
              }
            },
            child: const Text('Uygula'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    setState(() => player.suspendedMatchesRemaining = value);
    await _save();
  }

  Widget _adminPage(SavedGameData data) {
    final subTab =
        (_adminSubTab == 2 || _adminSubTab == 5) && !data.adminFullAccess
            ? 0
            : _adminSubTab;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: _adminPanelDecoration(const Color(0xff00d084)),
          child: Row(
            children: [
              const Icon(
                Icons.admin_panel_settings,
                color: Color(0xff00d084),
                size: 30,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YONETIM',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'Hesap sifrelerini degistir, hesap/takim sil.',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (data.adminFullAccess)
                const Chip(
                  avatar: Icon(Icons.verified, size: 16, color: Color(0xffffd34d)),
                  label: Text(
                    'Gelismis erisim (kimo@)',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              const SizedBox(width: 10),
              PopupMenuButton<String>(
                tooltip: 'Piyasa degerlerini guncelle',
                onSelected: (value) =>
                    _updateMarketValues(strong: value == 'strong'),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'light',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.trending_up),
                      title: Text('Hafif guncelleme'),
                      subtitle: Text('Son maclara gore kucuk degisimler'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'strong',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.trending_up),
                      title: Text('Guclu guncelleme'),
                      subtitle: Text('Kariyere gore buyuk degisimler'),
                    ),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xff00d084).withValues(alpha: 0.6),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.attach_money, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Piyasa Guncelle',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: _changeAdminPassword,
                icon: const Icon(Icons.password),
                label: const Text('Sifre degistir'),
              ),
              TextButton.icon(
                onPressed: _lockAdmin,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Kilitle'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SegmentedButton<int>(
          segments: [
            const ButtonSegment(
              value: 0,
              icon: Icon(Icons.account_circle),
              label: Text('Hesaplar'),
            ),
            const ButtonSegment(
              value: 1,
              icon: Icon(Icons.groups),
              label: Text('Takimlar'),
            ),
            ButtonSegment(
              value: 3,
              icon: const Icon(Icons.swap_horiz),
              label: Text(
                'Transferler${data.pendingTransfers.isEmpty ? '' : ' (${data.pendingTransfers.length})'}',
              ),
            ),
            if (data.adminFullAccess)
              const ButtonSegment(
                value: 2,
                icon: Icon(Icons.tune),
                label: Text('Oyuncu ayarlari'),
              ),
            const ButtonSegment(
              value: 4,
              icon: Icon(Icons.public),
              label: Text('Ulkeler'),
            ),
            if (data.adminFullAccess)
              const ButtonSegment(
                value: 5,
                icon: Icon(Icons.trending_up),
                label: Text('Değer'),
              ),
          ],
          selected: {subTab},
          onSelectionChanged: (selection) =>
              setState(() => _adminSubTab = selection.first),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: switch (subTab) {
            1 => _adminTeamsTab(data),
            2 when data.adminFullAccess => _adminPlayersTab(data),
            3 => _adminTransfersTab(data),
            4 => _adminCountriesTab(data),
            5 when data.adminFullAccess => _adminValueTab(data),
            _ => _adminAccountsTab(data),
          },
        ),
      ],
    );
  }

  /// Admin page: country management. The admin adds new countries and
  /// removes the unused ones; players and teams get their country from the
  /// dropdowns on the Takimlar / Oyuncu ayarlari tabs.
  Widget _adminCountriesTab(SavedGameData data) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newCountryController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.public),
                  labelText: 'Yeni ulke ekle',
                  isDense: true,
                ),
                onSubmitted: (_) => _addCountry(data),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: () => _addCountry(data),
              icon: const Icon(Icons.add),
              label: const Text('Ekle'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.separated(
            itemCount: data.countries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final country = data.countries[index];
              final playerCount =
                  data.players.where((profile) => profile.country == country)
                      .length;
              final teamCount = data.teams
                  .where((item) => !item.isDeleted && item.country == country)
                  .length;
              final inUse = playerCount + teamCount > 0;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xff0d1a16),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: inUse
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.white.withValues(alpha: 0.20),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.public, color: Color(0xffffd34d)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            country,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '$playerCount oyuncu  •  $teamCount takim'
                            '${inUse ? '' : '  •  kullanilmiyor'}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: inUse
                          ? 'Ulke kullaniliyor; once oyuncu/takim ulkeleri degistir'
                          : 'Ulkeyi sil',
                      onPressed: inUse
                          ? null
                          : () {
                              setState(() {
                                data.countries.remove(country);
                              });
                              _save();
                            },
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _addCountry(SavedGameData data) {
    final name = _newCountryController.text.trim();
    if (name.isEmpty) {
      return;
    }
    if (data.countries.contains(name)) {
      _showMessage('Bu ulke zaten listesinde');
      return;
    }
    setState(() {
      data.countries.add(name);
      _newCountryController.clear();
    });
    _save();
  }

  // ---------------------------------------------------------------------
  // Admin "Değer" tab — only visible with kimo@ (adminFullAccess).
  // Quick team-wide value raise/lower (small or big) plus a batch editor:
  // select any players/keepers, stack attribute adjustments and apply.
  // ---------------------------------------------------------------------

  static const _valueAttributes = [
    (key: 'overall', label: 'Genel oyun (OVR)'),
    (key: 'speed', label: 'Hız'),
    (key: 'stamina', label: 'Dayanıklılık'),
    (key: 'shotPower', label: 'Şut gücü'),
    (key: 'shooting', label: 'İska'),
    (key: 'finishing', label: 'Bitiricilik'),
    (key: 'passing', label: 'Pas'),
    (key: 'longShots', label: 'Uzun şut'),
    (key: 'curve', label: 'Kavis'),
    (key: 'composure', label: 'Soğukkanlılık'),
    (key: 'balance', label: 'Denge'),
    (key: 'zeka', label: 'Zekâ'),
    (key: 'dayaniklilik', label: 'Dayanıklılık gücü'),
    (key: 'goalkeeping', label: 'Kalecilik (genel)'),
    (key: 'gkReaction', label: 'Kaleci refleks'),
    (key: 'gkPositioning', label: 'Kaleci konumlanma'),
    (key: 'gkDiving', label: 'Kaleci düşme/sılta'),
    (key: 'gkHighBalls', label: 'Kaleci yüksek top'),
  ];

  double _readAttr(PlayerProfile player, String key) => switch (key) {
        'overall' => player.overallRating,
        'speed' => player.speedRating,
        'stamina' => player.staminaRating,
        'shotPower' => player.shotPowerRating,
        'shooting' => player.shootingRating,
        'finishing' => player.finishingRating,
        'passing' => player.passingRating,
        'longShots' => player.longShotsRating,
        'curve' => player.curveRating,
        'composure' => player.composureRating,
        'balance' => player.balanceRating,
        'zeka' => player.zekaGucu,
        'dayaniklilik' => player.dayaniklilikGucu,
        'goalkeeping' => player.goalkeepingRating,
        'gkReaction' => player.goalkeeperReactionRating,
        'gkPositioning' => player.goalkeeperPositioningRating,
        'gkDiving' => player.goalkeeperDivingRating,
        _ => player.goalkeeperHighBallsRating,
      };

  void _writeAttr(PlayerProfile player, String key, double value) {
    final clamped = value.clamp(1.0, 99.0).toDouble();
    switch (key) {
      case 'overall':
        player.overallRating = clamped;
      case 'speed':
        player.speedRating = clamped;
      case 'stamina':
        player.staminaRating = clamped;
      case 'shotPower':
        player.shotPowerRating = clamped;
      case 'shooting':
        player.shootingRating = clamped;
      case 'finishing':
        player.finishingRating = clamped;
      case 'passing':
        player.passingRating = clamped;
      case 'longShots':
        player.longShotsRating = clamped;
      case 'curve':
        player.curveRating = clamped;
      case 'composure':
        player.composureRating = clamped;
      case 'balance':
        player.balanceRating = clamped;
      case 'zeka':
        player.zekaGucu = clamped;
      case 'dayaniklilik':
        player.dayaniklilikGucu = clamped;
      case 'goalkeeping':
        player.goalkeepingRating = clamped;
      case 'gkReaction':
        player.goalkeeperReactionRating = clamped;
      case 'gkPositioning':
        player.goalkeeperPositioningRating = clamped;
      case 'gkDiving':
        player.goalkeeperDivingRating = clamped;
      default:
        player.goalkeeperHighBallsRating = clamped;
    }
  }

  /// The core attributes a team-wide quick adjust touches.
  static const _coreAttributeKeys = [
    'overall',
    'speed',
    'stamina',
    'shotPower',
    'shooting',
    'finishing',
    'passing',
    'composure',
    'balance',
    'zeka',
    'dayaniklilik',
    'goalkeeping',
  ];

  void _applyTeamValueAdjust(SavedGameData data) {
    final team = data.activeTeams
        .where((item) => item.id == _valueTeamId)
        .toList();
    if (team.isEmpty) {
      _showMessage('Once bir takim sec');
      return;
    }
    final target = team.first;
    final delta = (_valueQuickUp ? 1 : -1) * _valueQuickStep.toDouble();
    var count = 0;
    for (final player in data.players) {
      if (!target.playerIds.contains(player.id)) continue;
      for (final key in _coreAttributeKeys) {
        _writeAttr(player, key, _readAttr(player, key) + delta);
      }
      player.recalculateMarketValue(strong: false);
      count += 1;
    }
    _save();
    _showMessage(
      '${target.name}: $count oyuncunun degerleri '
      '${_valueQuickUp ? 'yukari' : 'asagi'} alindi ($delta.toStringAsFixed(0))',
    );
  }

  void _applyValueAdjustments(SavedGameData data) {
    final selected = data.players
        .where((player) => _valueSelectedPlayerIds.contains(player.id))
        .toList();
    if (selected.isEmpty) {
      _showMessage('Once oyuncu secin');
      return;
    }
    if (_valueAdjustments.isEmpty) {
      _showMessage('En az bir duzeltme satiri ekleyin');
      return;
    }
    for (final player in selected) {
      for (final adjustment in _valueAdjustments) {
        final delta =
            (adjustment.up ? 1 : -1) * adjustment.amount.toDouble();
        _writeAttr(
          player,
          adjustment.attrKey,
          _readAttr(player, adjustment.attrKey) + delta,
        );
      }
      player.recalculateMarketValue(strong: false);
    }
    _save();
    _showMessage(
      '${selected.length} oyuncunun degerleri guncellendi '
      '(${_valueAdjustments.length} duzeltme)',
    );
  }

  Widget _adminValueTab(SavedGameData data) {
    final teamFilterValue = _valueTeamFilter;
    final players = data.players
        .where(
          (player) =>
              _valueSearch.isEmpty ||
              player.name.toLowerCase().contains(_valueSearch),
        )
        .where(
          (player) {
            if (teamFilterValue == 'all') {
              return true;
            }
            return player.isGoalkeeper
                ? teamFilterValue == 'gk'
                : teamFilterValue == 'field';
          },
        )
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        // --- Team-wide quick adjust -------------------------------------
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xffffd34d).withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.bolt, size: 17, color: Color(0xffffd34d)),
                  SizedBox(width: 7),
                  Text(
                    'Takim geneli deger ayari',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: data.activeTeams
                              .any((team) => team.id == _valueTeamId)
                          ? _valueTeamId
                          : null,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'Takim',
                      ),
                      items: [
                        for (final team in data.activeTeams)
                          DropdownMenuItem(
                            value: team.id,
                            child: Text(
                              team.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _valueTeamId = value ?? ''),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.trending_up, size: 16),
                          label: Text('Artir'),
                        ),
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.trending_down, size: 16),
                          label: Text('Azalt'),
                        ),
                      ],
                      selected: {_valueQuickUp},
                      onSelectionChanged: (selection) =>
                          setState(() => _valueQuickUp = selection.first),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(
                          value: 1,
                          label: Text('Kucuk 1'),
                        ),
                        ButtonSegment(
                          value: 3,
                          label: Text('Buyuk 3'),
                        ),
                      ],
                      selected: {_valueQuickStep},
                      onSelectionChanged: (selection) => setState(
                        () => _valueQuickStep = selection.first,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _valueTeamId.isEmpty
                        ? null
                        : () => _applyTeamValueAdjust(data),
                    icon: const Icon(Icons.done, size: 16),
                    label: const Text('Tum takim'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // --- Batch editor -------------------------------------------------
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.playlist_add_check,
                      size: 17, color: Color(0xffffd34d)),
                  const SizedBox(width: 7),
                  Text(
                    'Oyuncular ve harrislar icin toplu deger duzeltmesi',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'oyunculari sec → duzeltmeleri ekleyin → uygula',
                    style: TextStyle(color: Colors.white38, fontSize: 10.5),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Oyuncu ara',
                        isDense: true,
                      ),
                      onChanged: (value) =>
                          setState(() => _valueSearch = value.trim().toLowerCase()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: teamFilterValue,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'Filtre',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('Hepsi'),
                        ),
                        DropdownMenuItem(
                          value: 'field',
                          child: Text('Saha'),
                        ),
                        DropdownMenuItem(
                          value: 'gk',
                          child: Text('Kaleci'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _valueTeamFilter = value ?? 'all'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(
                      () => _valueSelectedPlayerIds
                        ..clear()
                        ..addAll(players.map((player) => player.id)),
                    ),
                    child: const Text('Tumu sec'),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _valueSelectedPlayerIds.clear()),
                    child: const Text('Temizle'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 190),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: players.length,
                  itemBuilder: (context, index) {
                    final player = players[index];
                    final selected =
                        _valueSelectedPlayerIds.contains(player.id);
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        '${player.name}  ${player.effectiveOverall.toStringAsFixed(0)}'
                        '${player.isGoalkeeper ? '  •  KALECI' : ''}',
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'Şut ${player.shotPowerRating.toStringAsFixed(0)} • Zeka ${player.zekaGucu.toStringAsFixed(0)} • OVR ${player.overallRating.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 10, color: Colors.white38),
                      ),
                      secondary: player.isGoalkeeper
                          ? const Icon(Icons.back_hand, size: 16)
                          : null,
                      value: selected,
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _valueSelectedPlayerIds.add(player.id);
                        } else {
                          _valueSelectedPlayerIds.remove(player.id);
                        }
                      }),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.add, size: 14, color: Colors.white54),
                  const SizedBox(width: 6),
                  Text(
                    'Duzeltmeler (secili ${_valueSelectedPlayerIds.length} oyuncu):',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (var index = 0; index < _valueAdjustments.length;
                  index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: _valueAdjustments[index].attrKey,
                          isDense: true,
                          decoration: const InputDecoration(
                            labelText: 'Ozellik',
                          ),
                          items: [
                            for (final attribute in _valueAttributes)
                              DropdownMenuItem(
                                value: attribute.key,
                                child: Text(
                                  attribute.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) => setState(
                            () => _valueAdjustments[index] = (
                              attrKey: value ??
                                  _valueAdjustments[index].attrKey,
                              up: _valueAdjustments[index].up,
                              amount: _valueAdjustments[index].amount,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: true,
                              icon: Icon(Icons.arrow_upward, size: 15),
                            ),
                            ButtonSegment(
                              value: false,
                              icon: Icon(Icons.arrow_downward, size: 15),
                            ),
                          ],
                          selected: {_valueAdjustments[index].up},
                          onSelectionChanged: (selection) => setState(
                            () => _valueAdjustments[index] = (
                              attrKey: _valueAdjustments[index].attrKey,
                              up: selection.first,
                              amount: _valueAdjustments[index].amount,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 74,
                        child: DropdownButtonFormField<int>(
                          value: _valueAdjustments[index].amount,
                          isDense: true,
                          decoration: const InputDecoration(
                            labelText: 'Kadar',
                          ),
                          items: [
                            for (final amount in const [1, 2, 3, 5, 10])
                              DropdownMenuItem(
                                value: amount,
                                child: Text('±$amount'),
                              ),
                          ],
                          onChanged: (value) => setState(
                            () => _valueAdjustments[index] = (
                              attrKey: _valueAdjustments[index].attrKey,
                              up: _valueAdjustments[index].up,
                              amount: value ?? _valueAdjustments[index].amount,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Satiri sil',
                        onPressed: () =>
                            setState(() => _valueAdjustments.removeAt(index)),
                        icon: const Icon(Icons.close, size: 15),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => setState(
                      () => _valueAdjustments.add(
                        (attrKey: 'overall', up: true, amount: 1),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('Duzeltme ekle (+)'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () => _applyValueAdjustments(data),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Uygula'),
                  ),
                ],
              ),
            ],
          ),
        ),
        ],
      ),
    );
  }

  /// Admin page: accounts list with change-password and delete-account.
  Widget _adminAccountsTab(SavedGameData data) {
    final query = _accountSearch.trim().toLowerCase();
    final accounts = data.accounts
        .where(
          (account) => query.isEmpty ||
              account.username.toLowerCase().contains(query),
        )
        .toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _adminPanelDecoration(const Color(0xff00d084)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hesaplar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sifre unutulduysa buradan yeni sifre belirle. Hesap silinebilir.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Hesap ara',
              isDense: true,
            ),
            onChanged: (value) => setState(() => _accountSearch = value),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: accounts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final account = accounts[index];
                final teamCount = data.teams
                    .where(
                      (team) =>
                          team.ownerAccountId == account.id && !team.isDeleted,
                    )
                    .length;
                final active = account.id == data.activeAccountId;
                final loggedIn = data.isAccountLoggedIn(account.id);
                return ListTile(
                  leading: Icon(
                    loggedIn ? Icons.verified_user : Icons.account_circle,
                    color: loggedIn ? Colors.greenAccent : Colors.white70,
                  ),
                  title: Text(account.username),
                  subtitle: Text(
                    'Takim sayisi: $teamCount${active ? ' | aktif duzenleyici' : ''}',
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _changeAccountPassword(account),
                        icon: const Icon(Icons.password, size: 17),
                        label: const Text('Sifre degistir'),
                      ),
                      TextButton.icon(
                        onPressed: () => _deleteAccount(account),
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 17,
                          color: Colors.redAccent,
                        ),
                        label: Text(
                          'Hesabi sil',
                          style: TextStyle(color: Colors.redAccent.shade200),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Admin page: teams list with delete (with warning) and team settings.
  Widget _adminTeamsTab(SavedGameData data) {
    final teamQuery = _adminTeamSearch.trim().toLowerCase();
    final teams = data.teams
        .where(
          (team) => teamQuery.isEmpty ||
              team.name.toLowerCase().contains(teamQuery),
        )
        .toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _adminPanelDecoration(const Color(0xffffd34d)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Takimlar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'Takim silmeden once uyari gosterilir.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Yonetimde takim ara',
              isDense: true,
            ),
            onChanged: (value) => setState(() => _adminTeamSearch = value),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: teams.length,
              itemBuilder: (context, index) =>
                  _adminTeamCard(data, teams[index]),
            ),
          ),
        ],
      ),
    );
  }

  /// Hidden player values/settings editor. This tab only appears when the
  /// admin logged in with the secret prefix "kimo@" (adminFullAccess).
  /// Admin page: pending transfer requests. The admin sees the player,
  /// his market value (copyable) and the target team, then accepts
  /// (player is added to the team) or rejects the request.
  Widget _adminTransfersTab(SavedGameData data) {
    final pending = data.pendingTransfers;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _adminPanelDecoration(const Color(0xffffd34d)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Transfer Talepleri',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'Serbest oyuncular icin gelen transfer isteklerini onayla veya reddet.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xffffd34d).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.swap_horiz, color: Color(0xffffd34d)),
                const SizedBox(width: 10),
                const SizedBox(
                  width: 130,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Yonetici transferi',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        'Talep olmadan direkt takas',
                        style: TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: data.players.any((profile) =>
                            profile.id == _adminTransferPlayerId)
                        ? _adminTransferPlayerId
                        : null,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Oyuncu'),
                    items: [
                      for (final profile in data.players)
                        DropdownMenuItem(
                          value: profile.id,
                          child: Text(
                            profile.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _adminTransferPlayerId = value ?? ''),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: data.activeTeams.any((team) =>
                            team.id == _adminTransferTeamId)
                        ? _adminTransferTeamId
                        : null,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Hedef takim'),
                    items: [
                      for (final team in data.activeTeams)
                        DropdownMenuItem(
                          value: team.id,
                          child: Text(team.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _adminTransferTeamId = value ?? ''),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _adminTransferPlayerId.isEmpty ||
                          _adminTransferTeamId.isEmpty
                      ? null
                      : () => _applyAdminTransfer(data),
                  icon: const Icon(Icons.done, size: 16),
                  label: const Text('Uygula'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          Expanded(
            child: pending.isEmpty
                ? const Center(
                    child: Text(
                      'Bekleyen transfer talebi yok.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  )
                : ListView.separated(
                    itemCount: pending.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final request = pending[index];
                      final player = data.players
                          .where((item) => item.id == request.playerId)
                          .toList();
                      final profile =
                          player.isEmpty ? null : player.first;
                      final team = data.teams
                          .where((item) => item.id == request.targetTeamId)
                          .toList();
                      final targetTeam = team.isEmpty ? null : team.first;
                      final account = data.accounts
                          .where(
                            (item) =>
                                item.id == request.requesterAccountId,
                          )
                          .toList();
                      final requester =
                          account.isEmpty ? null : account.first;
                      final date = request.createdAt == 0
                          ? ''
                          : DateTime.fromMillisecondsSinceEpoch(
                              request.createdAt,
                            ).toString().split('.').first;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              profile?.isGoalkeeper == true
                                  ? Icons.back_hand
                                  : Icons.person,
                              color: profile == null
                                  ? Colors.white38
                                  : const Color(0xffffd34d),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          profile?.name ?? 'Silinmis oyuncu',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      if (profile != null)
                                        IconButton(
                                          tooltip: 'Adi kopyala',
                                          onPressed: () {
                                            Clipboard.setData(
                                              ClipboardData(
                                                text: profile.name,
                                              ),
                                            );
                                            _showMessage(
                                              '${profile.name} adi kopyalandi',
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.copy,
                                            size: 14,
                                            color: Colors.white54,
                                          ),
                                          constraints:
                                              const BoxConstraints(),
                                          padding: const EdgeInsets.all(2),
                                        ),
                                    ],
                                  ),
                                  Text(
                                    '${targetTeam?.name ?? 'Silinmis takim'} ← ${requester?.username ?? 'Silinmis hesap'}'
                                    '${date.isEmpty ? '' : ' • $date'}',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (profile != null)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xff00a86b,
                                  ).withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(
                                      0xff00a86b,
                                    ).withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      profile.marketValueText,
                                      style: const TextStyle(
                                        color: Color(0xff00e08b),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () => _copyMarketValue(profile),
                                      child: const Icon(
                                        Icons.copy,
                                        size: 14,
                                        color: Colors.white60,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            OutlinedButton.icon(
                              onPressed: profile == null ||
                                      targetTeam == null
                                  ? null
                                  : () => _acceptTransfer(
                                      data,
                                      request,
                                      profile,
                                      targetTeam,
                                    ),
                              icon: const Icon(
                                Icons.check,
                                size: 16,
                                color: Color(0xff00e08b),
                              ),
                              label: const Text(
                                'Kabul',
                                style: TextStyle(
                                  color: Color(0xff00e08b),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: const Color(
                                    0xff00a86b,
                                  ).withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            TextButton.icon(
                              onPressed: () => _rejectTransfer(
                                data,
                                request,
                              ),
                              icon: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.redAccent,
                              ),
                              label: Text(
                                'Reddet',
                                style: TextStyle(
                                  color: Colors.redAccent.shade200,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Direct admin transfer: moves the player from whatever team he is in
  /// (and clears his pending transfer requests) straight into the target
  /// team — no transfer request needed.
  Future<void> _applyAdminTransfer(SavedGameData data) async {
    final player = data.players
        .where((profile) => profile.id == _adminTransferPlayerId)
        .toList();
    final team = data.activeTeams
        .where((item) => item.id == _adminTransferTeamId)
        .toList();
    if (player.isEmpty || team.isEmpty) return;
    final profile = player.first;
    final target = team.first;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yonetici transferi'),
        content: Text(
          '${profile.name} oyuncusu ${target.name} takimina direkt '
          'transfer edilsin mi?\nOyuncu, mevcut takimidaki yerinden cikarilir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Transfer et'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      for (final item in data.teams) {
        item.playerIds.remove(profile.id);
        item.starterPlayerIds.remove(profile.id);
        item.roleByPlayerId.remove(profile.id);
        item.slotByPlayerId.remove(profile.id);
      }
      data.transferRequests.removeWhere(
        (request) => request.playerId == profile.id,
      );
      if (!target.playerIds.contains(profile.id)) {
        target.playerIds.add(profile.id);
        target.roleByPlayerId[profile.id] = profile.isGoalkeeper
            ? PlayerRole.goalkeeper
            : PlayerRole.midfieldLeft;
        if (target.starterPlayerIds.length < 11) {
          target.starterPlayerIds.add(profile.id);
        }
      }
      _adminTransferPlayerId = '';
      _adminTransferTeamId = '';
    });
    await _save();
    _showMessage('${profile.name} → ${target.name} (yonetici transferi)');
  }

  Future<void> _copyMarketValue(PlayerProfile profile) async {
    await Clipboard.setData(
      ClipboardData(
        text:
            '${profile.name}: ${profile.marketValueFull} TL (${profile.marketValueText})',
      ),
    );
    if (!mounted) return;
    _showMessage('${profile.marketValueFull} kopyalandi');
  }

  Future<void> _acceptTransfer(
    SavedGameData data,
    TransferRequest request,
    PlayerProfile profile,
    SavedTeamProfile targetTeam,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transferi Onayla'),
        content: Text(
          '${profile.name} (${profile.marketValueText}) oyuncusu '
          '${targetTeam.name} takimina eklenecek. Onayliyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Kabul Et'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      // Add the player to the target team (free agents have no team yet).
      targetTeam.playerIds.add(profile.id);
      targetTeam.roleByPlayerId[profile.id] = profile.isGoalkeeper
          ? PlayerRole.goalkeeper
          : PlayerRole.midfieldLeft;
      if (targetTeam.starterPlayerIds.length < 11) {
        targetTeam.starterPlayerIds.add(profile.id);
      }
      request.status = 'accepted';
      data.transferRequests.removeWhere((item) => item.id == request.id);
    });
    await _save();
    _showMessage('${profile.name} → ${targetTeam.name} transferi onaylandi');
  }

  Future<void> _rejectTransfer(
    SavedGameData data,
    TransferRequest request,
  ) async {
    setState(() {
      request.status = 'rejected';
      data.transferRequests.removeWhere((item) => item.id == request.id);
    });
    await _save();
    _showMessage('Transfer talebi reddedildi');
  }

  Widget _adminPlayersTab(SavedGameData data) {
    final playerQuery = _adminPlayerSearch.trim().toLowerCase();
    final players = data.players
        .where(
          (player) => playerQuery.isEmpty ||
              player.name.toLowerCase().contains(playerQuery),
        )
        .toList()
      ..sort((a, b) => b.effectiveOverall.compareTo(a.effectiveOverall));
    return Container(
      decoration: _adminPanelDecoration(const Color(0xff00d084)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Oyuncu degerleri ve ayarlari',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Gizli bolum — yalnizca kimo@ sifresiyle acilir.',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openTeamPlayers(''),
                  icon: const Icon(Icons.groups, size: 17),
                  label: const Text('Takim oyunculari sayfasi'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Yonetimde oyuncu ara',
                isDense: true,
              ),
              onChanged: (value) =>
                  setState(() => _adminPlayerSearch = value),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: players.length,
              itemBuilder: (context, index) =>
                  _adminPlayerCard(data, players[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lockedAdminPage() {
    return Center(
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(28),
        decoration: _adminPanelDecoration(const Color(0xff00d084)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 54, color: Color(0xff00d084)),
            const SizedBox(height: 12),
            const Text(
              'YONETIM sayfasi kilitli',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Hesap sifrelerini degistirmek ve hesap/takim silmek icin yonetici sifresi gerekir.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => _openAdminLogin(targetTab: 5),
              icon: const Icon(Icons.password),
              label: const Text('Sifre ile ac'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeAdminPassword() async {
    final data = _data;
    if (data == null) return;
    final password = await _askPassword(
      'Yeni yonetici sifresi',
      requireNew: true,
    );
    if (password == null || !mounted) return;
    setState(() => data.setAdminPassword(password));
    await _save();
    _showMessage('Yonetici sifresi degistirildi');
  }

  /// Admin resets an account password (used when the password is forgotten).
  Future<void> _changeAccountPassword(SavedAccountProfile account) async {
    final password = await _askPassword(
      '${account.username} icin yeni sifre',
      requireNew: true,
    );
    if (password == null || !mounted) return;
    setState(() => account.setPassword(password));
    await _save();
    _showMessage('${account.username} sifresi degistirildi');
  }

  Future<void> _deleteAccount(SavedAccountProfile account) async {
    final data = _data;
    if (data == null) return;
    if (data.accounts.length <= 1) {
      _showMessage('En az bir hesap kalmali');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hesabi Sil'),
        content: Text(
          '${account.username} hesabini silmek istediginize emin misiniz?\n'
          'Hesaba ait takimlar sahipsiz kalir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      data.accounts.removeWhere((item) => item.id == account.id);
      data.loggedInAccountIds.remove(account.id);
      if (data.activeAccountId == account.id) {
        data.activeAccountId = data.accounts.first.id;
        data.loggedInAccountIds.add(data.activeAccountId);
      }
      for (final team in data.teams) {
        if (team.ownerAccountId == account.id) {
          team.ownerAccountId = '';
        }
      }
    });
    await _save();
    _showMessage('${account.username} hesabi silindi');
  }

  Future<void> _openTeamPlayers(String teamId) async {
    final data = _data;
    await _save();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamPlayersScreen(
          initialTeamId: teamId.isEmpty ? null : teamId,
          adminFullAccess: data?.adminFullAccess ?? false,
        ),
      ),
    );
    _load();
  }

  Future<void> _openFreeAgents() async {
    await _save();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FreeAgentsScreen()));
    _load();
  }

  /// Opens the full player profile page (goals, assists, per-match
  /// ratings, man-of-the-match matches, attributes).
  Future<void> _openPlayerDetail(String playerId) async {
    await _save();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerDetailScreen(playerId: playerId),
      ),
    );
    _load();
  }

  /// Opens the team page with the full match-results history, form and
  /// total squad value.
  Future<void> _openTeamDetail(String teamId) async {
    await _save();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamDetailScreen(teamId: teamId),
      ),
    );
    _load();
  }

  /// Applies the piyasa degeri update to every player. The light mode uses
  /// only the last few matches with small swings; the strong mode uses the
  /// whole career with bigger swings.
  Future<void> _updateMarketValues({required bool strong}) async {
    final data = _data;
    if (data == null) return;
    var up = 0;
    var down = 0;
    setState(() {
      for (final player in data.players) {
        final before = player.marketValue;
        player.recalculateMarketValue(strong: strong);
        if (player.marketValue > before + 0.5) {
          up += 1;
        } else if (player.marketValue < before - 0.5) {
          down += 1;
        }
      }
    });
    await _save();
    _showMessage(
      'Piyasa guncellendi (${strong ? 'guclu' : 'hafif'}): $up artti, $down dustu',
    );
  }

  Widget _adminPlayerCard(SavedGameData data, PlayerProfile profile) {
    return ExpansionTile(
      leading: Icon(profile.isGoalkeeper ? Icons.back_hand : Icons.person),
      title: Text(
        '${profile.name}  ${profile.effectiveOverall.toStringAsFixed(0)}',
      ),
      subtitle: Text(
        '${profile.heightMeters.toStringAsFixed(2)} m | mac ${profile.matchesPlayed} | puan ${profile.points.toStringAsFixed(1)} | deger ${profile.marketValueText}'
        '${profile.country.isNotEmpty ? ' | Ulke: ${profile.country}' : ''}',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        DropdownButtonFormField<String?>(
          value: profile.country.isNotEmpty ? profile.country : null,
          isDense: true,
          decoration: const InputDecoration(labelText: 'Oyuncu ulkesi'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Ulke yok'),
            ),
            for (final country in data.countries)
              DropdownMenuItem<String?>(
                value: country,
                child: Text(country),
              ),
          ],
          onChanged: (value) {
            setState(() => profile.country = value ?? '');
            _save();
          },
        ),
        const SizedBox(height: 8),
        _adminSkillSlider(
          label: 'Genel oyun',
          value: profile.overallRating,
          onChanged: (value) => profile.overallRating = value,
        ),
        _adminSkillSlider(
          label: 'Sut',
          value: profile.shootingRating,
          onChanged: (value) => profile.shootingRating = value,
        ),
        _adminSkillSlider(
          label: 'Bitiricilik',
          value: profile.finishingRating,
          onChanged: (value) => profile.finishingRating = value,
        ),
        _adminSkillSlider(
          label: 'Sut gucu',
          value: profile.shotPowerRating,
          onChanged: (value) => profile.shotPowerRating = value,
        ),
        _adminSkillSlider(
          label: 'Uzaktan sut',
          value: profile.longShotsRating,
          onChanged: (value) => profile.longShotsRating = value,
        ),
        _adminSkillSlider(
          label: 'Falso',
          value: profile.curveRating,
          onChanged: (value) => profile.curveRating = value,
        ),
        _adminSkillSlider(
          label: 'Sogukkanlilik',
          value: profile.composureRating,
          onChanged: (value) => profile.composureRating = value,
        ),
        _adminSkillSlider(
          label: 'Denge',
          value: profile.balanceRating,
          onChanged: (value) => profile.balanceRating = value,
        ),
        _adminSkillSlider(
          label: 'Pas',
          value: profile.passingRating,
          onChanged: (value) => profile.passingRating = value,
        ),
        _adminSkillSlider(
          label: 'Kalecilik',
          value: profile.goalkeepingRating,
          onChanged: (value) => profile.goalkeepingRating = value,
        ),
        if (profile.isGoalkeeper) ..._goalkeeperAdminSliders(profile),
        _adminSkillSlider(
          label: 'Hiz',
          value: profile.speedRating,
          onChanged: (value) => profile.speedRating = value,
        ),
        _adminSkillSlider(
          label: 'Enerji',
          value: profile.staminaRating,
          onChanged: (value) => profile.staminaRating = value,
        ),
        _adminSkillSlider(
          label: 'Dayaniklilik',
          value: profile.dayaniklilikGucu,
          onChanged: (value) => profile.dayaniklilikGucu = value,
        ),
        _adminSkillSlider(
          label: 'Zeka',
          value: profile.zekaGucu,
          onChanged: (value) => profile.zekaGucu = value,
        ),
        Row(
          children: [
            const SizedBox(width: 128, child: Text('Tercih edilen ayak')),
            DropdownButton<PreferredFoot>(
              value: profile.preferredFoot,
              items: const [
                DropdownMenuItem(
                  value: PreferredFoot.left,
                  child: Text('Sol'),
                ),
                DropdownMenuItem(
                  value: PreferredFoot.right,
                  child: Text('Sag'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => profile.preferredFoot = value);
                _save();
              },
            ),
            const Spacer(),
            const Text('Zayif ayak'),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: profile.weakFootRating.clamp(1, 5).toInt(),
              items: [
                for (var value = 1; value <= 5; value++)
                  DropdownMenuItem(value: value, child: Text('$value/5')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => profile.weakFootRating = value);
                _save();
              },
            ),
          ],
        ),
        _suspensionEditor(profile),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Son maclar: ${profile.matchHistory.take(4).map((record) => '${record.scoreText} ${record.rating.toStringAsFixed(1)}').join(' | ')}',
            style: const TextStyle(color: Colors.white60),
          ),
        ),
      ],
    );
  }

  List<Widget> _goalkeeperAdminSliders(PlayerProfile profile) => [
    _adminSkillSlider(
      label: 'GK Reaksiyon',
      value: profile.goalkeeperReactionRating,
      onChanged: (value) => profile.goalkeeperReactionRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Pozisyon',
      value: profile.goalkeeperPositioningRating,
      onChanged: (value) => profile.goalkeeperPositioningRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Atlayis',
      value: profile.goalkeeperDivingRating,
      onChanged: (value) => profile.goalkeeperDivingRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Handling',
      value: profile.goalkeeperHandlingRating,
      onChanged: (value) => profile.goalkeeperHandlingRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Yakalayis',
      value: profile.goalkeeperCatchingRating,
      onChanged: (value) => profile.goalkeeperCatchingRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Sicrama',
      value: profile.goalkeeperJumpingRating,
      onChanged: (value) => profile.goalkeeperJumpingRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Karar',
      value: profile.goalkeeperDecisionRating,
      onChanged: (value) => profile.goalkeeperDecisionRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Bire Bir',
      value: profile.goalkeeperOneVsOneRating,
      onChanged: (value) => profile.goalkeeperOneVsOneRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Yuksek Top',
      value: profile.goalkeeperHighBallsRating,
      onChanged: (value) => profile.goalkeeperHighBallsRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Sogukkanlilik',
      value: profile.goalkeeperComposureRating,
      onChanged: (value) => profile.goalkeeperComposureRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Hizlanma',
      value: profile.goalkeeperAccelerationRating,
      onChanged: (value) => profile.goalkeeperAccelerationRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Erisim',
      value: profile.goalkeeperReachRating,
      onChanged: (value) => profile.goalkeeperReachRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Ayak Hareketi',
      value: profile.goalkeeperFootworkRating,
      onChanged: (value) => profile.goalkeeperFootworkRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Ongoru',
      value: profile.goalkeeperAnticipationRating,
      onChanged: (value) => profile.goalkeeperAnticipationRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Sektirme',
      value: profile.goalkeeperParryingRating,
      onChanged: (value) => profile.goalkeeperParryingRating = value,
    ),
    _adminSkillSlider(
      label: 'GK Dagitim',
      value: profile.goalkeeperDistributionRating,
      onChanged: (value) => profile.goalkeeperDistributionRating = value,
    ),
  ];

  Widget _suspensionEditor(PlayerProfile profile) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Mac cezasi',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: 'Bir mac azalt',
            onPressed: profile.suspendedMatchesRemaining <= 0
                ? null
                : () {
                    setState(() => profile.suspendedMatchesRemaining -= 1);
                    _save();
                  },
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 74,
            child: Text(
              '${profile.suspendedMatchesRemaining} mac',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            tooltip: 'Bir mac ceza ekle',
            onPressed: () {
              setState(() {
                profile.suspendedMatchesRemaining =
                    (profile.suspendedMatchesRemaining + 1).clamp(0, 20).toInt();
              });
              _save();
            },
            icon: const Icon(Icons.add_circle_outline),
          ),
          const SizedBox(width: 10),
          Text(
            'Sari ${profile.yellowCards} • Kirmizi ${profile.redCards}',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _adminSkillSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: Slider(
            min: 1,
            max: 99,
            divisions: 98,
            value: value.clamp(1, 99).toDouble(),
            label: value.toStringAsFixed(0),
            onChanged: (newValue) {
              setState(() => onChanged(newValue));
            },
            onChangeEnd: (_) => _save(),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(value.toStringAsFixed(0), textAlign: TextAlign.end),
        ),
      ],
    );
  }

  Widget _adminTeamCard(SavedGameData data, SavedTeamProfile team) {
    return ExpansionTile(
      leading: const Icon(Icons.shield),
      title: Text('${team.name}  ${team.rating.toStringAsFixed(1)}'),
      subtitle: Text(
        'G ${team.wins} B ${team.draws} M ${team.losses} | oyuncu ${team.playerIds.length}'
        '${team.country.isNotEmpty ? ' | Ulke: ${team.country}' : ''}',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        TextFormField(
          initialValue: team.name,
          decoration: const InputDecoration(labelText: 'Takim adi'),
          onChanged: (value) =>
              team.name = value.trim().isEmpty ? team.name : value.trim(),
          onFieldSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        _ownerDropdown(data, team),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          value: team.country.isNotEmpty ? team.country : null,
          isDense: true,
          decoration: const InputDecoration(labelText: 'Takim ulkesi'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Ulke yok'),
            ),
            for (final country in data.countries)
              DropdownMenuItem<String?>(
                value: country,
                child: Text(country),
              ),
          ],
          onChanged: (value) {
            setState(() => team.country = value ?? '');
            _save();
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<FormationType>(
          value: playableFormationTypes.contains(team.formation)
              ? team.formation
              : FormationType.wing433,
          decoration: const InputDecoration(labelText: 'Dizilis'),
          items: playableFormationTypes
              .map(
                (type) =>
                    DropdownMenuItem(value: type, child: Text(type.title)),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() => team.formation = value);
            _save();
          },
        ),
        _adminSkillSlider(
          label: 'Takim gucu',
          value: team.rating,
          onChanged: (value) => team.rating = value,
        ),
        if (data.adminLoggedIn) ...[
          DropdownButtonFormField<AiPlayStyle>(
            value: team.playStyle,
            decoration: const InputDecoration(labelText: 'AI Oyun Stili'),
            items: AiPlayStyle.values
                .map((s) => DropdownMenuItem(value: s, child: Text(s.title)))
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => team.playStyle = value);
              _save();
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<AiDifficulty>(
            value: team.aiDifficulty,
            decoration: const InputDecoration(labelText: 'AI Zorlugu'),
            items: AiDifficulty.values
                .map(
                  (difficulty) => DropdownMenuItem(
                    value: difficulty,
                    child: Text(difficulty.title),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => team.aiDifficulty = value);
              _save();
            },
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            team.matchHistory.isEmpty
                ? 'Mac kaydi yok'
                : team.matchHistory
                      .take(5)
                      .map(
                        (record) =>
                            '${record.scoreText} ${record.result} ${record.ratingAfter.toStringAsFixed(1)}',
                      )
                      .join(' | '),
            style: const TextStyle(color: Colors.white60),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: team.isDeleted
              ? OutlinedButton.icon(
                  onPressed: () {
                    setState(() => team.isDeleted = false);
                    _save();
                  },
                  icon: const Icon(Icons.restore),
                  label: const Text('Takimi geri getir'),
                )
              : FilledButton.tonalIcon(
                  onPressed: () => _deleteTeam(team),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Takimi sil'),
                ),
        ),
      ],
    );
  }

  Future<void> _deleteTeam(SavedTeamProfile team) async {
    final data = _data;
    if (data == null) return;
    if (data.activeTeams.length <= 1 && !team.isDeleted) {
      _showMessage('En az bir aktif takim kalmali');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Takimi Sil'),
        content: Text(
          '${team.name} takimini silmek istediginize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      team.isDeleted = true;
      data.transferRequests.removeWhere(
        (request) => request.targetTeamId == team.id,
      );
    });
    await _save();
  }

  Widget _teamSummary(SavedGameData data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: ListView(
        children: [
          const Text(
            'Mac kadrolari',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          _summaryBlock(data.blueTeam, data.bluePlayerIds, data),
          const SizedBox(height: 6),
          _kitStrip(data.blueTeam, 'Mavi', (index) {
            setState(() => _blueKitIndex = index);
            _save();
          }),
          const SizedBox(height: 10),
          _lineupEditor(data.blueTeam, data),
          const Divider(height: 26),
          _summaryBlock(data.redTeam, data.redPlayerIds, data),
          const SizedBox(height: 6),
          _kitStrip(data.redTeam, 'Kirmizi', (index) {
            setState(() => _redKitIndex = index);
            _save();
          }),
          const SizedBox(height: 10),
          _lineupEditor(data.redTeam, data),
          const SizedBox(height: 14),
          const Text(
            'Ilk 11 tam olmadan mac baslamaz. Yeni eklenen oyuncunun boyu 1.70-1.95 m arasinda rastgele atanir.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Kit (jersey) system: every team keeps its own list of kits. Teams can
  // create unlimited custom-colored kits from the editor, switch the
  // active kit per match, rename, duplicate and delete kits.
  // ---------------------------------------------------------------------

  static int _clampKitIndex(int index, int length) {
    if (length <= 1) return 0;
    if (index < 0) return 0;
    if (index > length - 1) return length - 1;
    return index;
  }

  void _syncKitIndices() {
    final data = _data;
    if (data == null) return;
    _blueKitIndex = _clampKitIndex(
      data.blueTeam.activeKitIndex,
      data.blueTeam.jerseyKits.length,
    );
    _redKitIndex = _clampKitIndex(
      data.redTeam.activeKitIndex,
      data.redTeam.jerseyKits.length,
    );
  }

  /// Compact horizontal strip of the team's kits on the match page.
  /// Tapping a kit activates it; the plus/tune buttons open the editor
  /// and the full kit manager.
  Widget _kitStrip(
    SavedTeamProfile team,
    String label,
    ValueChanged<int> onChanged,
  ) {
    final data = _data!;
    final isBlue = team.id == data.blueTeam.id;
    final rawIndex = isBlue ? _blueKitIndex : _redKitIndex;
    final kits =
        team.jerseyKits.isEmpty ? JerseyFactory.defaultKits() : team.jerseyKits;
    final value = _clampKitIndex(rawIndex, kits.length);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          const Icon(Icons.checkroom, size: 18, color: Color(0xffffd34d)),
          const SizedBox(width: 7),
          Text(
            '$label forma',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white70,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 58,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < kits.length; i++)
                    _kitCard(kits[i], i == value, () {
                      team.activeKitIndex = i;
                      onChanged(i);
                    }),
                  _kitCardAction(
                    Icons.add,
                    'Yeni forma ekle',
                    () => _showKitEditor(team),
                  ),
                  _kitCardAction(
                    Icons.tune,
                    'Formalari yonet',
                    () => _showKitManager(team),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kitCard(JerseyKit kit, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 76,
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 5),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xffffd34d).withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? const Color(0xffffd34d)
                : Colors.white.withValues(alpha: 0.10),
            width: active ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CustomPaint(
              size: const Size(42, 36),
              painter: _KitPreviewPainter(kit),
            ),
            const SizedBox(height: 3),
            Text(
              kit.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                color: active ? const Color(0xffffd34d) : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kitCardAction(
    IconData icon,
    String tooltip,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 46,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Center(
            child: Icon(icon, size: 19, color: const Color(0xffffd34d)),
          ),
        ),
      ),
    );
  }

  /// Full kit manager for a team: list of all kits with activate/edit/
  /// duplicate/delete actions and a "new kit" button.
  Future<void> _showKitManager(SavedTeamProfile team) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Container(
          width: 700,
          constraints: const BoxConstraints(maxHeight: 600),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.checkroom, color: Color(0xffffd34d), size: 22),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Forma yonetimi',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          team.name,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close, color: Colors.white54),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: team.jerseyKits.isEmpty
                    ? const Center(
                        child: Text(
                          'Kayitli forma yok.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView(
                        children: [
                          for (var i = 0; i < team.jerseyKits.length; i++)
                            _kitManagerRow(dialogContext, team, i),
                        ],
                      ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => _showKitEditor(team),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Yeni forma ekle'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    _syncKitIndices();
    if (mounted) {
      setState(() {});
    }
    _save();
  }

  Widget _kitManagerRow(
    BuildContext dialogContext,
    SavedTeamProfile team,
    int index,
  ) {
    final kit = team.jerseyKits[index];
    final isActive = team.activeKitIndex == index;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xffffd34d).withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? const Color(0xffffd34d).withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.09),
        ),
      ),
      child: Row(
        children: [
          CustomPaint(size: const Size(50, 42), painter: _KitPreviewPainter(kit)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isActive ? 'AKTIF FORMA' : 'Yedek forma',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isActive ? const Color(0xffffd34d) : Colors.white54,
                  ),
                ),
              ],
            ),
          ),
          if (!isActive)
            TextButton(
              onPressed: () {
                team.activeKitIndex = index;
                _syncKitIndices();
                setState(() {});
                _save();
              },
              child: const Text('Kullan'),
            ),
          IconButton(
            tooltip: 'Formayi duzenle',
            onPressed: () => _showKitEditor(team, editIndex: index),
            icon: const Icon(Icons.edit, size: 19, color: Colors.white70),
          ),
          IconButton(
            tooltip: 'Formayi ciktir (ayni renkler, yeni ad)',
            onPressed: () {
              final copy = JerseyKit(
                name: '${kit.name} (Kopya)',
                shirtColor: kit.shirtColor,
                shortsColor: kit.shortsColor,
                socksColor: kit.socksColor,
                numberColor: kit.numberColor,
                goalkeeperShirtColor: kit.goalkeeperShirtColor,
              );
              team.jerseyKits.insert(index + 1, copy);
              _syncKitIndices();
              setState(() {});
              _save();
            },
            icon: const Icon(Icons.copy_all, size: 18, color: Colors.white70),
          ),
          IconButton(
            tooltip: team.jerseyKits.length <= 1
                ? 'En az bir forma kalmali'
                : 'Formayi sil',
            onPressed: team.jerseyKits.length <= 1
                ? null
                : () {
                    team.jerseyKits.removeAt(index);
                    if (team.activeKitIndex >= team.jerseyKits.length) {
                      team.activeKitIndex = team.jerseyKits.length - 1;
                    }
                    _syncKitIndices();
                    setState(() {});
                    _save();
                  },
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the kit editor. [editIndex] != null edits an existing kit,
  /// otherwise a new kit is appended and made active.
  Future<void> _showKitEditor(SavedTeamProfile team, {int? editIndex}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _KitEditorDialog(
        team: team,
        editIndex: editIndex,
      ),
    );
    if (saved != true) return;
    _syncKitIndices();
    if (mounted) {
      setState(() {});
    }
    _save();
  }

  Widget _summaryBlock(
    SavedTeamProfile team,
    Set<String> ids,
    SavedGameData data,
  ) {
    final selected = data.players
        .where((profile) => ids.contains(profile.id))
        .toList();
    final keepers = selected.where((profile) => profile.isGoalkeeper).length;
    final fielders = selected.where((profile) => !profile.isGoalkeeper).length;
    final valid = keepers >= 1 && fielders >= 10;
    final ownerReady = data.isTeamOwnerLoggedIn(team);
    final ownerMatches = data.accounts
        .where((account) => account.id == team.ownerAccountId)
        .toList();
    final ownerName = ownerMatches.isEmpty ? null : ownerMatches.first.username;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Team deletion is an admin-only action (Yonetim paneli) — the
        // delete button no longer lives on the match-setup summary.
        InkWell(
          onTap: () => _openTeamDetail(team.id),
          child: Tooltip(
            message: 'Takim sayfasini ac (sonuclar, forma, deger)',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  team.name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.receipt_long,
                  size: 15,
                  color: Color(0xffffd34d),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Oyuncu: ${selected.length}  Deger: ${team.rating.toStringAsFixed(1)}  Toplam deger: ${formatMarketValue(data.teamTotalValue(team))}',
        ),
        Text(
          'Galibiyet: ${team.wins}, Maglubiyet: ${team.losses}, Beraberlik: ${team.draws}  |  Form: ${team.formText}',
        ),
        Text(
          'Sahip: ${ownerName ?? 'Secilmedi'} (${ownerReady ? 'giris var' : 'giris yok'})',
        ),
        Text('Kaleci: $keepers, saha: $fielders'),
        Text(
          valid ? 'Maca hazir' : '10 saha oyuncusu ve 1 kaleci gerekli',
          style: TextStyle(
            color: valid ? Colors.greenAccent : Colors.orangeAccent,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          selected.take(7).map((profile) => profile.name).join(', '),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }

  Future<void> _openVisualFormationEditor(
    SavedTeamProfile team,
    SavedGameData data,
  ) async {
    team.ensureLineupDefaults(data.players);
    final presetNameController = TextEditingController();
    final searchController = TextEditingController();
    String? selectedPlayerId;
    String search = '';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final plan = formationPlan(team.formation);
          final members = data.players
              .where(
                (player) =>
                    team.playerIds.contains(player.id) &&
                    (search.isEmpty ||
                        player.name.toLowerCase().contains(search)),
              )
              .toList()
            ..sort((a, b) {
              if (a.isGoalkeeper != b.isGoalkeeper) {
                return a.isGoalkeeper ? -1 : 1;
              }
              return b.effectiveOverall.compareTo(a.effectiveOverall);
            });
          final selectedMatches = data.players.where(
            (player) => player.id == selectedPlayerId,
          );
          final selectedPlayer =
              selectedMatches.isEmpty ? null : selectedMatches.first;
          return Dialog(
            backgroundColor: const Color(0xff08140f),
            insetPadding: const EdgeInsets.all(18),
            child: SizedBox(
              width: 1180,
              height: 760,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xff103d2d), Color(0xff111b22)],
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.account_tree,
                          color: Color(0xffffd34d),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${team.name} • Gorsel Dizilis Editoru',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 18),
                        SizedBox(
                          width: 280,
                          child: DropdownButtonFormField<FormationType>(
                            value: playableFormationTypes.contains(team.formation)
                                ? team.formation
                                : FormationType.wing433,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Once dizilisi sec',
                            ),
                            items: [
                              for (final formation in playableFormationTypes)
                                DropdownMenuItem(
                                  value: formation,
                                  child: Text(
                                    formation.title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setDialogState(() {
                                _setSelectedTeamFormation(team, data, value);
                                team.activeFormationPresetId = null;
                                team.ensureLineupDefaults(data.players);
                              });
                            },
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Kaydet ve kapat',
                          onPressed: () async {
                            team.ensureLineupDefaults(data.players);
                            await _save();
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 260,
                          child: DropdownButtonFormField<String>(
                            value: team.savedFormations.any(
                              (preset) =>
                                  preset.id == team.activeFormationPresetId,
                            )
                                ? team.activeFormationPresetId
                                : null,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Kayitli takim dizilisi',
                            ),
                            items: [
                              for (final preset in team.savedFormations)
                                DropdownMenuItem(
                                  value: preset.id,
                                  child: Text(
                                    preset.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (presetId) {
                              if (presetId == null) return;
                              final preset = team.savedFormations.firstWhere(
                                (item) => item.id == presetId,
                              );
                              setDialogState(() {
                                team.applyFormationPreset(preset);
                                _setSelectedTeamFormation(
                                  team,
                                  data,
                                  team.formation,
                                );
                                team.ensureLineupDefaults(data.players);
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: presetNameController,
                            decoration: const InputDecoration(
                              labelText: 'Dizilis kayit adi',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () {
                            final name = presetNameController.text.trim();
                            if (name.isEmpty) {
                              _showMessage('Dizilis icin bir ad yaz');
                              return;
                            }
                            team.ensureLineupDefaults(data.players);
                            if (team.starterPlayerIds.length != 11 ||
                                team.slotByPlayerId.length != 11) {
                              _showMessage(
                                'Kaydetmeden once 11 daireyi de doldur',
                              );
                              return;
                            }
                            setDialogState(() {
                              team.saveCurrentFormation(name);
                              presetNameController.clear();
                            });
                            _save();
                          },
                          icon: const Icon(Icons.save),
                          label: const Text('Takima kaydet'),
                        ),
                        if (team.activeFormationPresetId != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Kayitli dizilisi sil',
                            onPressed: () {
                              setDialogState(() {
                                team.savedFormations.removeWhere(
                                  (preset) =>
                                      preset.id == team.activeFormationPresetId,
                                );
                                team.activeFormationPresetId = null;
                              });
                              _save();
                            },
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          'Ilk 11: ${team.starterPlayerIds.length}/11',
                          style: TextStyle(
                            color: team.starterPlayerIds.length == 11
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 7,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 10, 14),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final pitchWidth = constraints.maxWidth;
                                final pitchHeight = constraints.maxHeight;
                                return Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xff087a36),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.white70,
                                      width: 2,
                                    ),
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        left: pitchWidth / 2 - 1,
                                        top: 0,
                                        bottom: 0,
                                        child: Container(
                                          width: 2,
                                          color: Colors.white38,
                                        ),
                                      ),
                                      Positioned(
                                        left: pitchWidth / 2 - 58,
                                        top: pitchHeight / 2 - 58,
                                        child: Container(
                                          width: 116,
                                          height: 116,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white38,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                      for (var slotIndex = 0;
                                          slotIndex < plan.spots.length;
                                          slotIndex++)
                                        _formationSlot(
                                          team: team,
                                          data: data,
                                          plan: plan,
                                          slotIndex: slotIndex,
                                          pitchWidth: pitchWidth,
                                          pitchHeight: pitchHeight,
                                          selectedPlayerId: selectedPlayerId,
                                          onSelected: (playerId) {
                                            setDialogState(
                                              () => selectedPlayerId = playerId,
                                            );
                                          },
                                          onDrop: (profile) {
                                            setDialogState(() {
                                              _assignPlayerToFormationSlot(
                                                team,
                                                profile,
                                                slotIndex,
                                              );
                                              selectedPlayerId = profile.id;
                                            });
                                          },
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 5,
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(0, 0, 14, 14),
                            decoration: BoxDecoration(
                              color: const Color(0xff0d1a16),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: TextField(
                                    controller: searchController,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(Icons.search),
                                      labelText: 'Oyuncu ara ve sahaya surukle',
                                      isDense: true,
                                    ),
                                    onChanged: (value) => setDialogState(
                                      () => search = value.trim().toLowerCase(),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: ListView.builder(
                                    itemCount: members.length,
                                    itemBuilder: (context, index) {
                                      final player = members[index];
                                      final slot = team.slotByPlayerId[player.id];
                                      return Draggable<PlayerProfile>(
                                        data: player,
                                        feedback: Material(
                                          color: Colors.transparent,
                                          child: _dragPlayerCard(player),
                                        ),
                                        childWhenDragging: Opacity(
                                          opacity: 0.35,
                                          child: _rosterPlayerTile(
                                            player,
                                            slot,
                                            selectedPlayerId == player.id,
                                          ),
                                        ),
                                        child: InkWell(
                                          onTap: () => setDialogState(
                                            () => selectedPlayerId = player.id,
                                          ),
                                          child: _rosterPlayerTile(
                                            player,
                                            slot,
                                            selectedPlayerId == player.id,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  flex: 2,
                                  child: selectedPlayer == null
                                      ? const Center(
                                          child: Text(
                                            'Tum istatistikleri gormek icin oyuncuya tikla',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white54,
                                            ),
                                          ),
                                        )
                                      : _formationPlayerStats(
                                          team,
                                          data,
                                          selectedPlayer,
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Oyuncuyu tutup daireye birak. Dolu daireye birakirsan oyuncular yer degistirir.',
                            style: TextStyle(color: Colors.white60),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            setDialogState(() {
                              team
                                ..slotByPlayerId.clear()
                                ..starterPlayerIds.clear()
                                ..activeFormationPresetId = null;
                            });
                          },
                          child: const Text('Sahayı temizle'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () async {
                            team.ensureLineupDefaults(data.players);
                            await _save();
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          },
                          icon: const Icon(Icons.check),
                          label: const Text('Uygula ve kapat'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    presetNameController.dispose();
    searchController.dispose();
    if (mounted) setState(() {});
  }

  Widget _formationSlot({
    required SavedTeamProfile team,
    required SavedGameData data,
    required FormationPlan plan,
    required int slotIndex,
    required double pitchWidth,
    required double pitchHeight,
    required String? selectedPlayerId,
    required ValueChanged<String> onSelected,
    required ValueChanged<PlayerProfile> onDrop,
  }) {
    final spot = plan.spots[slotIndex];
    final assigned = team.slotByPlayerId.entries.where(
      (entry) => entry.value == slotIndex,
    );
    PlayerProfile? player;
    if (assigned.isNotEmpty) {
      final matches = data.players.where(
        (profile) => profile.id == assigned.first.key,
      );
      if (matches.isNotEmpty) player = matches.first;
    }
    final left = (18 + spot.x * (pitchWidth - 100)).clamp(
      0.0,
      pitchWidth - 84,
    ).toDouble();
    final top = (18 + spot.y * (pitchHeight - 90)).clamp(
      0.0,
      pitchHeight - 64,
    ).toDouble();
    return Positioned(
      left: left,
      top: top,
      width: 84,
      height: 64,
      child: DragTarget<PlayerProfile>(
        onWillAcceptWithDetails: (details) =>
            details.data.isGoalkeeper == spot.role.isGoalkeeper &&
            !details.data.isUnavailable &&
            team.playerIds.contains(details.data.id),
        onAcceptWithDetails: (details) => onDrop(details.data),
        builder: (context, candidates, rejected) {
          final highlighted = candidates.isNotEmpty;
          final content = AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: highlighted
                  ? const Color(0xffffd34d)
                  : player == null
                  ? Colors.black.withValues(alpha: 0.30)
                  : player.id == selectedPlayerId
                  ? const Color(0xffffd34d).withValues(alpha: 0.88)
                  : const Color(0xff102019).withValues(alpha: 0.94),
              border: Border.all(
                color: highlighted
                    ? Colors.white
                    : player == null
                    ? Colors.white54
                    : Colors.white,
                width: highlighted ? 3 : 1.5,
              ),
              boxShadow: [
                if (player != null)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 8,
                  ),
              ],
            ),
            alignment: Alignment.center,
            child: player == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add, size: 18, color: Colors.white70),
                      Text(
                        spot.role.code,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${player.number ?? spot.number}',
                        style: TextStyle(
                          color: player.id == selectedPlayerId
                              ? Colors.black
                              : const Color(0xffffd34d),
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Text(
                          player.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: player.id == selectedPlayerId
                                ? Colors.black
                                : Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${spot.role.code} • ${player.effectiveOverall.round()}',
                        style: TextStyle(
                          color: player.id == selectedPlayerId
                              ? Colors.black87
                              : Colors.white60,
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
          );
          if (player == null) return content;
          final assignedPlayer = player;
          return Draggable<PlayerProfile>(
            data: assignedPlayer,
            feedback: Material(
              color: Colors.transparent,
              child: _dragPlayerCard(assignedPlayer),
            ),
            childWhenDragging: Opacity(opacity: 0.28, child: content),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onSelected(assignedPlayer.id),
              child: content,
            ),
          );
        },
      ),
    );
  }

  void _setSelectedTeamFormation(
    SavedTeamProfile team,
    SavedGameData data,
    FormationType formation,
  ) {
    team.formation = formation;
    if (team.id == data.blueTeamId) {
      data.blueFormation = formation;
    }
    if (team.id == data.redTeamId) {
      data.redFormation = formation;
    }
  }

  void _assignPlayerToFormationSlot(
    SavedTeamProfile team,
    PlayerProfile profile,
    int newSlot,
  ) {
    final plan = formationPlan(team.formation);
    if (newSlot < 0 || newSlot >= plan.spots.length) return;
    if (profile.isGoalkeeper != plan.spots[newSlot].role.isGoalkeeper) return;
    final oldSlot = team.slotByPlayerId[profile.id];
    String? occupyingPlayerId;
    for (final entry in team.slotByPlayerId.entries) {
      if (entry.value == newSlot && entry.key != profile.id) {
        occupyingPlayerId = entry.key;
        break;
      }
    }
    if (occupyingPlayerId != null) {
      if (oldSlot != null) {
        team.slotByPlayerId[occupyingPlayerId] = oldSlot;
        team.starterPlayerIds.add(occupyingPlayerId);
        team.roleByPlayerId[occupyingPlayerId] = plan.spots[oldSlot].role;
      } else {
        team.slotByPlayerId.remove(occupyingPlayerId);
        team.starterPlayerIds.remove(occupyingPlayerId);
      }
    }
    team
      ..slotByPlayerId[profile.id] = newSlot
      ..starterPlayerIds.add(profile.id)
      ..roleByPlayerId[profile.id] = plan.spots[newSlot].role
      ..activeFormationPresetId = null;
    if (team.starterPlayerIds.length > 11) {
      final removable = team.starterPlayerIds.firstWhere(
        (id) => !team.slotByPlayerId.containsKey(id),
        orElse: () => '',
      );
      if (removable.isNotEmpty) team.starterPlayerIds.remove(removable);
    }
  }

  Widget _dragPlayerCard(PlayerProfile player) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xff102019),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xffffd34d)),
      ),
      child: Text(
        '${player.name} • OVR ${player.effectiveOverall.round()}',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _rosterPlayerTile(
    PlayerProfile player,
    int? slot,
    bool selected,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xffffd34d).withValues(alpha: 0.17)
            : Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? const Color(0xffffd34d) : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Icon(
            player.isGoalkeeper ? Icons.back_hand : Icons.person,
            color: player.isGoalkeeper
                ? const Color(0xffffd34d)
                : Colors.white70,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  'OVR ${player.effectiveOverall.round()} • Sut ${player.shootingRating.round()} • Pas ${player.passingRating.round()} • Hiz ${player.speedRating.round()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 9),
                ),
              ],
            ),
          ),
          Text(
            slot == null ? 'YEDEK' : 'SLOT ${slot + 1}',
            style: TextStyle(
              color: slot == null ? Colors.white38 : Colors.greenAccent,
              fontWeight: FontWeight.w800,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _formationPlayerStats(
    SavedTeamProfile team,
    SavedGameData data,
    PlayerProfile player,
  ) {
    final passPercent = player.passes == 0
        ? 0
        : (player.successfulPasses * 100 / player.passes).round();
    // The team's fastest player and best finisher (bitiricilik) among the
    // current squad members — shown whenever a player is selected so the
    // user can compare and place people in the right spots.
    PlayerProfile? fastest;
    PlayerProfile? bestFinisher;
    for (final mate in data.players) {
      if (!team.playerIds.contains(mate.id) || mate.isGoalkeeper) {
        continue;
      }
      if (fastest == null || mate.speedRating > fastest.speedRating) {
        fastest = mate;
      }
      if (bestFinisher == null ||
          mate.finishingRating > bestFinisher.finishingRating) {
        bestFinisher = mate;
      }
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            player.name,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Color(0xffffd34d),
            ),
          ),
          const SizedBox(height: 7),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xffffd34d).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xffffd34d).withValues(alpha: 0.40),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'En uygun mevkiler: ${preferredRolesText(player)}',
                  style: const TextStyle(
                    color: Color(0xfff5d67b),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Takimin en hizlisi: ${fastest?.name ?? '-'} '
                  '(${fastest == null ? 0 : fastest.speedRating.round()})   •   '
                  'En iyi bitirici: ${bestFinisher?.name ?? '-'} '
                  '(${bestFinisher == null ? 0 : bestFinisher.finishingRating.round()})',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 7,
            children: [
              _formationStat('Forma no', player.number ?? 0),
              _formationStat('OVR', player.overallRating.round()),
              _formationStat('Efektif OVR', player.effectiveOverall.round()),
              _formationStat('Sut', player.shootingRating.round()),
              _formationStat('Bitiricilik', player.finishingRating.round()),
              _formationStat('Sut gucu', player.shotPowerRating.round()),
              _formationStat('Uzaktan sut', player.longShotsRating.round()),
              _formationStat('Falso', player.curveRating.round()),
              _formationStat('Sogukkanlilik', player.composureRating.round()),
              _formationStat('Denge', player.balanceRating.round()),
              _formationStat('Zayif ayak', '${player.weakFootRating}/5'),
              _formationStat('Pas gucu', player.passingRating.round()),
              _formationStat('Kaleci gucu', player.goalkeepingRating.round()),
              if (player.isGoalkeeper) ...[
                _formationStat('GK Reaksiyon', player.goalkeeperReactionRating.round()),
                _formationStat('GK Pozisyon', player.goalkeeperPositioningRating.round()),
                _formationStat('GK Atlayis', player.goalkeeperDivingRating.round()),
                _formationStat('GK Handling', player.goalkeeperHandlingRating.round()),
                _formationStat('GK Yakalayis', player.goalkeeperCatchingRating.round()),
                _formationStat('GK Sicrama', player.goalkeeperJumpingRating.round()),
                _formationStat('GK Karar', player.goalkeeperDecisionRating.round()),
                _formationStat('GK Bire Bir', player.goalkeeperOneVsOneRating.round()),
                _formationStat('GK Yuksek Top', player.goalkeeperHighBallsRating.round()),
                _formationStat('GK Erisim', player.goalkeeperReachRating.round()),
                _formationStat('GK Ongoru', player.goalkeeperAnticipationRating.round()),
                _formationStat('GK Sektirme', player.goalkeeperParryingRating.round()),
                _formationStat('GK Dagitim', player.goalkeeperDistributionRating.round()),
              ],
              _formationStat('Hiz gucu', player.speedRating.round()),
              _formationStat('Enerji gucu', player.staminaRating.round()),
              _formationStat('Dayaniklilik', player.dayaniklilikGucu.round()),
              _formationStat('Zeka', player.zekaGucu.round()),
              _formationStat('Boy', (player.heightMeters * 100).round()),
              _formationStat('Mac', player.matchesPlayed),
              _formationStat('Dakika', player.minutesPlayed),
              _formationStat('Gol', player.goals),
              _formationStat('Asist', player.assists),
              _formationStat('Pas', player.passes),
              _formationStat('Basarili pas', player.successfulPasses),
              _formationStat('Pas %', passPercent),
              _formationStat('Dripling', player.dribbles),
              _formationStat('Basarili dripling', player.successfulDribbles),
              _formationStat('Mudahale', player.tackles),
              _formationStat('Sut', player.shots),
              _formationStat('Isabetli sut', player.shotsOnTarget),
              _formationStat('Kacan firsat', player.missedChances),
              _formationStat('Uzaklastirma', player.clearances),
              _formationStat('Kurtaris', player.saves),
              _formationStat('Yaptigi faul', player.foulsCommitted),
              _formationStat('Aldigi faul', player.foulsReceived),
              _formationStat('Sari', player.yellowCards),
              _formationStat('Kirmizi', player.redCards),
              _formationStat('Puan', player.points.toStringAsFixed(1)),
              _formationStat('Fitness', '%${(player.fitness * 100).round()}'),
              _formationStat('Sakatlik gunu', player.injuredDaysRemaining),
              _formationStat(
                'Ceza maci',
                player.suspendedMatchesRemaining,
              ),
            ],
          ),
          if (player.isUnavailable) ...[
            const SizedBox(height: 8),
            Text(
              player.isInjured
                  ? 'SAKAT: ${player.injuredDaysRemaining} gun'
                  : 'CEZALI: ${player.suspendedMatchesRemaining} mac',
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _formationStat(String label, Object value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _lineupEditor(SavedTeamProfile team, SavedGameData data) {
    final allTeamPlayers = data.players
        .where((profile) => team.playerIds.contains(profile.id))
        .toList();
    final query = (_lineupSearchByTeam[team.id] ?? '').trim().toLowerCase();
    final players = allTeamPlayers
        .where(
          (profile) => query.isEmpty ||
              profile.name.toLowerCase().contains(query) ||
              (profile.number?.toString().contains(query) ?? false),
        )
        .toList();
    final starters = allTeamPlayers
        .where((profile) => team.starterPlayerIds.contains(profile.id))
        .length;
    final canEdit = data.isTeamOwnerLoggedIn(team) || data.adminLoggedIn;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${team.name} ilk 11: $starters/11${canEdit ? '' : ' | sahip giris yok'}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: canEdit
                      ? () => _openVisualFormationEditor(team, data)
                      : null,
                  icon: const Icon(Icons.account_tree, size: 17),
                  label: const Text('Gorsel dizilis'),
                ),
                const SizedBox(width: 8),
                Text(
                  'Degisiklik 5',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 19),
                labelText: 'Kadroda oyuncu ara',
                isDense: true,
              ),
              onChanged: (value) => setState(
                () => _lineupSearchByTeam[team.id] = value,
              ),
            ),
          ),
          SizedBox(
            height: 250,
            child: players.isEmpty
                ? const Center(child: Text('Bu takimda oyuncu yok'))
                : ListView.builder(
                    itemCount: players.length,
                    itemBuilder: (context, index) {
                      final profile = players[index];
                      final isStarter = team.starterPlayerIds.contains(
                        profile.id,
                      );
                      final allowedRoles = profile.isGoalkeeper
                          ? const [PlayerRole.goalkeeper]
                          : PlayerRole.values
                                .where((role) => !role.isGoalkeeper)
                                .toList();
                      final role =
                          allowedRoles.contains(team.roleByPlayerId[profile.id])
                          ? team.roleByPlayerId[profile.id]!
                          : allowedRoles.first;
                      return SizedBox(
                        height: 44,
                        child: Row(
                          children: [
                            Checkbox(
                              value: isStarter,
                              onChanged: canEdit
                                  ? (value) {
                                      setState(() {
                                        if (value == true) {
                                          if (profile.isUnavailable) {
                                            return;
                                          }
                                          if (team.starterPlayerIds.length <
                                              11) {
                                            team.starterPlayerIds.add(
                                              profile.id,
                                            );
                                          }
                                        } else {
                                          team.starterPlayerIds.remove(
                                            profile.id,
                                          );
                                        }
                                        team.activeFormationPresetId = null;
                                      });
                                      _save();
                                    }
                                  : null,
                            ),
                            SizedBox(
                              width: 34,
                              child: Text('#${profile.number ?? index + 1}'),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    profile.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  Text(
                                    'OVR:${profile.overallRating.toStringAsFixed(0)} DY:${profile.dayaniklilikGucu.toStringAsFixed(0)} ZK:${profile.zekaGucu.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.white38,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 150,
                              child: DropdownButton<PlayerRole>(
                                value: role,
                                isExpanded: true,
                                underline: const SizedBox.shrink(),
                                items: allowedRoles
                                    .map(
                                      (role) => DropdownMenuItem(
                                        value: role,
                                        child: Text(role.turkishName),
                                      ),
                                    )
                                    .toList(),
                                onChanged: canEdit
                                    ? (value) {
                                        if (value == null) {
                                          return;
                                        }
                                        setState(() {
                                          if (!isStarter) {
                                            team
                                              ..roleByPlayerId[profile.id] = value
                                              ..activeFormationPresetId = null;
                                            return;
                                          }
                                          final plan = formationPlan(
                                            team.formation,
                                          );
                                          final matchingSlots = List<int>.generate(
                                            plan.spots.length,
                                            (slot) => slot,
                                          ).where(
                                            (slot) =>
                                                plan.spots[slot].role == value,
                                          );
                                          if (matchingSlots.isEmpty) return;
                                          final occupiedSlots = team
                                              .slotByPlayerId
                                              .entries
                                              .where(
                                                (entry) =>
                                                    entry.key != profile.id,
                                              )
                                              .map((entry) => entry.value)
                                              .toSet();
                                          final emptyMatches = matchingSlots.where(
                                            (slot) =>
                                                !occupiedSlots.contains(slot),
                                          );
                                          _assignPlayerToFormationSlot(
                                            team,
                                            profile,
                                            emptyMatches.isNotEmpty
                                                ? emptyMatches.first
                                                : matchingSlots.first,
                                          );
                                        });
                                        _save();
                                      }
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _adminPanelDecoration(Color accent) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: 0.14),
          const Color(0xff0e1c17),
          const Color(0xff08110d),
        ],
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.2),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: accent.withValues(alpha: 0.06),
          blurRadius: 30,
        ),
      ],
    );
  }

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [
          Color(0xff11201a),
          Color(0xff0b1512),
          Color(0xff0a1310),
        ],
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: const Color(0xffd4af37).withValues(alpha: 0.18),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.28),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}

/// Kit editor dialog: name the kit, pick shirt/shorts/socks/number/keeper
/// colors from presets or build a custom color with hue + lightness
/// sliders. Works for both creating a new kit and editing an existing one.
class _KitEditorDialog extends StatefulWidget {
  const _KitEditorDialog({required this.team, this.editIndex});

  final SavedTeamProfile team;
  final int? editIndex;

  @override
  State<_KitEditorDialog> createState() => _KitEditorDialogState();
}

class _KitEditorDialogState extends State<_KitEditorDialog> {
  late final TextEditingController _nameController;
  late Color _shirt;
  late Color _shorts;
  late Color _socks;
  late Color _number;
  late Color _keeper;
  int _customPart = 0;
  double _hue = 140;
  double _lightness = 0.55;

  bool get _isEditing => widget.editIndex != null;

  @override
  void initState() {
    super.initState();
    final kit = _isEditing
        ? widget.team.jerseyKits[widget.editIndex!]
        : const JerseyKit(
            name: 'Yeni forma',
            shirtColor: Color(0xff1f9d55),
            shortsColor: Color(0xff101418),
            socksColor: Color(0xff1f9d55),
            numberColor: Color(0xffffffff),
            goalkeeperShirtColor: Color(0xffffd600),
          );
    _shirt = kit.shirtColor;
    _shorts = kit.shortsColor;
    _socks = kit.socksColor;
    _number = kit.numberColor;
    _keeper = kit.goalkeeperShirtColor;
    _nameController = TextEditingController(
      text: _isEditing ? kit.name : '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  List<({String label, Color value, ValueChanged<Color> set})> get _parts => [
        (label: 'Forma', value: _shirt, set: (c) => setState(() => _shirt = c)),
        (label: 'Sort', value: _shorts, set: (c) => setState(() => _shorts = c)),
        (label: 'Corap', value: _socks, set: (c) => setState(() => _socks = c)),
        (label: 'Numara', value: _number, set: (c) => setState(() => _number = c)),
        (label: 'Kaleci', value: _keeper, set: (c) => setState(() => _keeper = c)),
      ];

  Color get _customColor => _hslToColor(
        _hue % 360,
        0.74.clamp(0.0, 1.0).toDouble(),
        _lightness.clamp(0.08, 0.92).toDouble(),
      );

  void _applyCustom() {
    final part = _parts[_customPart];
    part.set(_customColor);
  }

  void _saveKit() {
    final team = widget.team;
    final name = _nameController.text.trim().isEmpty
        ? 'Forma ${team.jerseyKits.length + 1}'
        : _nameController.text.trim();
    final kit = JerseyKit(
      name: name,
      shirtColor: _shirt,
      shortsColor: _shorts,
      socksColor: _socks,
      numberColor: _number,
      goalkeeperShirtColor: _keeper,
    );
    final editIndex = widget.editIndex;
    if (editIndex != null && editIndex < team.jerseyKits.length) {
      team.jerseyKits[editIndex] = kit;
    } else {
      team.jerseyKits.add(kit);
      team.activeKitIndex = team.jerseyKits.length - 1;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final partLabels = const [
      'Forma',
      'Sort',
      'Corap',
      'Numara',
      'Kaleci',
    ];
    return Dialog(
      child: Container(
        width: 780,
        constraints: const BoxConstraints(maxHeight: 640),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.checkroom, color: Color(0xffffd34d), size: 22),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _isEditing ? 'Formayi duzenle' : 'Yeni forma olustur',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white54),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Forma adi',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Column(
                      children: [
                        CustomPaint(
                          size: const Size(56, 46),
                          painter: _KitPreviewPainter(
                            JerseyKit(
                              name: '',
                              shirtColor: _shirt,
                              shortsColor: _shorts,
                              socksColor: _socks,
                              numberColor: _number,
                              goalkeeperShirtColor: _keeper,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Kaleci: ${_kitColorText(_keeper)}',
                          style: const TextStyle(
                            fontSize: 9.5,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final part in _parts) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        child: Text(
                          part.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      Container(
                        width: 26,
                        height: 26,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: part.value,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final preset in JerseyFactory.presetColors)
                              _presetSwatch(
                                Color(preset.$2),
                                part.value.toARGB32() == preset.$2,
                                () => part.set(Color(preset.$2)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xff00c896).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xff00c896).withValues(alpha: 0.30),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.palette,
                          size: 17,
                          color: Color(0xff00c896),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'Ozel renk olustur (herhangi bir renk)',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 130,
                          child: DropdownButtonFormField<int>(
                            value: _customPart,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Uygula',
                            ),
                            items: [
                              for (var i = 0; i < partLabels.length; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text(partLabels[i]),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _customPart = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const SizedBox(
                          width: 46,
                          child: Text(
                            'Ton',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white60,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: _hue,
                            min: 0,
                            max: 360,
                            divisions: 360,
                            onChanged: (value) =>
                                setState(() => _hue = value),
                          ),
                        ),
                        const SizedBox(
                          width: 58,
                          child: Text(
                            'Parlaklik',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white60,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: _lightness,
                            min: 0.08,
                            max: 0.92,
                            divisions: 84,
                            onChanged: (value) =>
                                setState(() => _lightness = value),
                          ),
                        ),
                        Container(
                          width: 42,
                          height: 26,
                          decoration: BoxDecoration(
                            color: _customColor,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                              color:
                                  Colors.white.withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _applyCustom,
                          child: const Text('Uygula'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Vazgec'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saveKit,
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(
                      _isEditing ? 'Kaydet' : 'Formayi ekle',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presetSwatch(
    Color color,
    bool selected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 20,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

/// Draws a small jersey + shorts + socks preview for a kit.
class _KitPreviewPainter extends CustomPainter {
  _KitPreviewPainter(this.kit);

  final JerseyKit kit;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Shirt: top 56% of the box.
    final sh = h * 0.56;
    final path = Path();
    path.moveTo(w * 0.36, sh * 0.02);
    path.quadraticBezierTo(w * 0.5, sh * 0.15, w * 0.64, sh * 0.02);
    path.lineTo(w * 0.78, sh * 0.06);
    path.lineTo(w * 1.0, sh * 0.17);
    path.lineTo(w * 0.97, sh * 0.35);
    path.lineTo(w * 0.84, sh * 0.30);
    path.lineTo(w * 0.84, sh * 0.98);
    path.lineTo(w * 0.16, sh * 0.98);
    path.lineTo(w * 0.16, sh * 0.30);
    path.lineTo(w * 0.03, sh * 0.35);
    path.lineTo(w * 0.0, sh * 0.17);
    path.lineTo(w * 0.22, sh * 0.06);
    path.close();
    canvas.drawPath(path, Paint()..color = kit.shirtColor);

    // Number on the shirt.
    final tp = TextPainter(
      text: TextSpan(
        text: '10',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: h * 0.21,
          color: kit.numberColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset((w - tp.width) / 2, sh * 0.44),
    );

    // Shorts: middle strip.
    final shorts = Path();
    final sy = h * 0.60;
    final shh = h * 0.20;
    shorts.moveTo(w * 0.14, sy);
    shorts.lineTo(w * 0.86, sy);
    shorts.lineTo(w * 0.92, sy + shh);
    shorts.lineTo(w * 0.55, sy + shh);
    shorts.lineTo(w * 0.50, sy + shh * 0.42);
    shorts.lineTo(w * 0.45, sy + shh);
    shorts.lineTo(w * 0.08, sy + shh);
    shorts.close();
    canvas.drawPath(shorts, Paint()..color = kit.shortsColor);

    // Socks: two small rounded rectangles at the bottom.
    for (final fx in const [0.30, 0.58]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * fx, h * 0.845, w * 0.14, h * 0.145),
          const Radius.circular(3),
        ),
        Paint()..color = kit.socksColor,
      );
    }
  }

  @override
  bool shouldRepaint(_KitPreviewPainter oldDelegate) {
    return oldDelegate.kit.shirtColor != kit.shirtColor ||
        oldDelegate.kit.shortsColor != kit.shortsColor ||
        oldDelegate.kit.socksColor != kit.socksColor ||
        oldDelegate.kit.numberColor != kit.numberColor ||
        oldDelegate.kit.goalkeeperShirtColor != kit.goalkeeperShirtColor;
  }
}

/// Simple RGB caption for the kit editor preview.
String _kitColorText(Color c) {
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  return 'R$r G$g B$b';
}

/// HSL to Color (h in degrees, s and l as 0..1 fractions).
Color _hslToColor(double h, double s, double l) {
  final c = (1.0 - (2.0 * l - 1.0).abs()) * s;
  final hp = (h % 360) / 60.0;
  final hpMod = hp % 2.0;
  final x = c * (1.0 - (hpMod - 1.0).abs());
  double r = 0.0, g = 0.0, b = 0.0;
  if (hp < 1) {
    r = c;
    g = x;
  } else if (hp < 2) {
    r = x;
    g = c;
  } else if (hp < 3) {
    g = c;
    b = x;
  } else if (hp < 4) {
    g = x;
    b = c;
  } else if (hp < 5) {
    r = x;
    b = c;
  } else {
    r = c;
    b = x;
  }
  final m = l - c / 2.0;
  int to255(double v) => ((v + m) * 255).round().clamp(0, 255);
  return Color.fromARGB(255, to255(r), to255(g), to255(b));
}
