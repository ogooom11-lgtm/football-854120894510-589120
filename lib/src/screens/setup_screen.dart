import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/enums/ai_difficulty.dart';
import '../game/enums/ai_play_style.dart';
import '../game/enums/match_mode.dart';
import '../game/enums/player_role.dart';
import '../game/enums/team_id.dart';
import '../game/models/formation.dart';
import '../game/models/jersey_kit.dart';
import '../game/models/match_event.dart';
import '../game/models/player_profile.dart';
import '../game/models/shooting.dart';
import '../game/models/team_profile.dart';
import '../game/models/team_setup.dart';
import '../storage/roster_storage.dart';
import 'account_detail_screen.dart';
import 'game_screen.dart';
import 'league_screen.dart';

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
    final password = _adminPasswordController.text.trim();
    if (!data.adminPasswordSet) {
      if (password.length < 3) {
        setState(() => _adminPasswordError = true);
        return;
      }
      setState(() {
        data.setAdminPassword(password);
        data.adminLoggedIn = true;
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
      _showAdminPasswordField = false;
      _adminPasswordController.clear();
      _setupTab = _pendingAdminTab;
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

  Future<void> _openLeague() async {
    await _save();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LeagueScreen()));
    // Reload after returning from league screen
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
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _topBar(),
                const SizedBox(height: 14),
                _setupTabs(),
                const SizedBox(height: 14),
                Expanded(child: _setupPage(data)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _setupTabs() {
    final data = _data;
    final segments = <ButtonSegment<int>>[
      const ButtonSegment(
        value: 0,
        icon: Icon(Icons.account_circle),
        label: Text('Hesap'),
      ),
      const ButtonSegment(
        value: 1,
        icon: Icon(Icons.sports_soccer),
        label: Text('Mac'),
      ),
      const ButtonSegment(
        value: 2,
        icon: Icon(Icons.groups),
        label: Text('Takimlar'),
      ),
      const ButtonSegment(
        value: 3,
        icon: Icon(Icons.directions_run),
        label: Text('Oyuncular'),
      ),
      const ButtonSegment(
        value: 4,
        icon: Icon(Icons.help_outline),
        label: Text('Aciklama'),
      ),
      const ButtonSegment(
        value: 6,
        icon: Icon(Icons.gavel),
        label: Text('CEZALAR'),
      ),
      if (data?.adminLoggedIn == true)
        const ButtonSegment(
          value: 5,
          icon: Icon(Icons.admin_panel_settings),
          label: Text('Yonetim'),
        ),
    ];
    final selectedValue = segments.any((segment) => segment.value == _setupTab)
        ? _setupTab
        : 0;
    return SegmentedButton<int>(
      segments: segments,
      selected: {selectedValue},
      onSelectionChanged: (selection) {
        final target = selection.first;
        if (target == 6 && data?.adminLoggedIn != true) {
          _openAdminLogin(targetTab: 6);
          return;
        }
        setState(() => _setupTab = target);
      },
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
      5 => data.adminLoggedIn ? _adminPage(data) : _helpPage(),
      6 => data.adminLoggedIn ? _penaltiesPage(data) : _lockedPenaltiesPage(),
      _ => _helpPage(),
    };
  }

  Widget _topBar() {
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xff0f8f4f),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.sports_soccer, size: 34, color: Colors.white),
        ),
        const SizedBox(width: 14),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'BOMBAN FUTBOL',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            Text(
              'Flutter masaustu surumu',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
        const Spacer(),
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
                    hintText: _data?.adminPasswordSet == true
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
        if (!_showAdminPasswordField)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _openAccountDetail,
                icon: const Icon(Icons.person, size: 18, color: Colors.white70),
                label: const Text(
                  'Hesap',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24, width: 1),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _openLeague,
                icon: const Icon(
                  Icons.emoji_events,
                  size: 18,
                  color: Color(0xffffd34d),
                ),
                label: const Text(
                  'LIG MODU',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xffffd34d),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xffffd34d), width: 1.5),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _startMatch,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Maca basla'),
              ),
            ],
          ),
      ],
    );
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
                  leading: const Icon(Icons.shield),
                  title: Text(team.name),
                  subtitle: Text(
                    'Oyuncu ${players.length} | saha $fielders | kaleci $keepers | G ${team.wins} B ${team.draws} M ${team.losses}',
                  ),
                  trailing: SizedBox(
                    width: 240,
                    child: Row(
                      children: [
                        Expanded(child: _ownerDropdown(data, team)),
                        const SizedBox(width: 10),
                        Text(
                          team.rating.toStringAsFixed(1),
                          style: const TextStyle(fontWeight: FontWeight.w900),
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
          'Mac sayfasi: iki takimi, mac tipini ve dizilisi sec.\n\n'
          'Hesaplar sayfasi: hesap olustur, giris yap ve aktif duzenleyici hesabi sec. Farkli sahipli iki takim oynayabilir ama mac baslamadan iki takim sahibinin de giris yapmis olmasi gerekir.\n\n'
          'Takimlar sayfasi: tum takimlari, takim sahibini, guc puanini ve galibiyet/maglubiyet durumunu gosterir. Sahipsiz takimlara buradan sahip sec.\n\n'
          'Oyuncular sayfasi: oyuncu ekle, adini duzenle, kaleci olarak isaretle ve oyuncuyu yalniz bir takima bagla. Bir oyuncu baska takima verilirse eski takimindan otomatik cikar.\n\n'
          'Mac kadrolari: her takim icin ilk 11, yedekler ve oyuncu mevkisini sec. Takim sahibi giris yapmadan kadro duzenlenmez.\n\n'
          'Oyun icinde F1/F2 degisiklik ekranini acar. Enter once cikacak oyuncuyu, sonra girecek oyuncuyu onaylar.\n\n'
          'VAR icin R tusuna iki kez bas. Alt cubuk kaydi akici oynatir; oklar veya A/D kaydi 3 saniyelik adimlarla ileri geri alir. Gol dugmeleri golu iptal eder veya geri alir.',
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
                Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Rey:${profile.effectiveOverall.toStringAsFixed(0)} Hiz:${profile.speedRating.toStringAsFixed(0)} Enerji:${profile.staminaRating.toStringAsFixed(0)} Day:${profile.dayaniklilikGucu.toStringAsFixed(0)} Gol:${profile.goals} Pas:${profile.successfulPasses}/${profile.passes} Sut:${profile.shotsOnTarget}/${profile.shots} Kacan:${profile.missedChances}${profile.isSuspended ? ' • CEZALI ${profile.suspendedMatchesRemaining} mac' : ''}${profile.isInjured ? ' • SAKAT ${profile.injuredDaysRemaining} gun' : ''}',
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
            tooltip: 'Sil',
            onPressed: canEdit ? () => _deletePlayer(profile) : null,
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
                  onPressed: () {
                    setState(() {
                      data.adminLoggedIn = false;
                      _setupTab = 0;
                    });
                    _save();
                  },
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
    final playerQuery = _adminPlayerSearch.trim().toLowerCase();
    final teamQuery = _adminTeamSearch.trim().toLowerCase();
    final players = data.players
        .where(
          (player) => playerQuery.isEmpty ||
              player.name.toLowerCase().contains(playerQuery),
        )
        .toList()
      ..sort((a, b) => b.effectiveOverall.compareTo(a.effectiveOverall));
    final teams = data.teams
        .where(
          (team) => teamQuery.isEmpty ||
              team.name.toLowerCase().contains(teamQuery),
        )
        .toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Container(
            decoration: _adminPanelDecoration(const Color(0xff00d084)),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Yonetim: oyuncu yetenekleri',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            data.adminLoggedIn = false;
                            _setupTab = 0;
                          });
                          _save();
                        },
                        icon: const Icon(Icons.logout),
                        label: const Text('Cikis'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
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
                        _adminPlayerCard(players[index]),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Container(
            decoration: _adminPanelDecoration(const Color(0xffffd34d)),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Yonetim: takimlar',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Yonetimde takim ara',
                      isDense: true,
                    ),
                    onChanged: (value) =>
                        setState(() => _adminTeamSearch = value),
                  ),
                ),
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
          ),
        ),
      ],
    );
  }

  Widget _adminPlayerCard(PlayerProfile profile) {
    return ExpansionTile(
      leading: Icon(profile.isGoalkeeper ? Icons.back_hand : Icons.person),
      title: Text(
        '${profile.name}  ${profile.effectiveOverall.toStringAsFixed(0)}',
      ),
      subtitle: Text(
        '${profile.heightMeters.toStringAsFixed(2)} m | mac ${profile.matchesPlayed} | puan ${profile.points.toStringAsFixed(1)}',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
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
        'G ${team.wins} B ${team.draws} M ${team.losses} | oyuncu ${team.playerIds.length}',
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
    setState(() => team.isDeleted = true);
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
          _jerseySelector(data.blueTeam, _blueKitIndex, (i) {
            setState(() => _blueKitIndex = i);
            _save();
          }, 'Mavi'),
          const SizedBox(height: 10),
          _lineupEditor(data.blueTeam, data),
          const Divider(height: 26),
          _summaryBlock(data.redTeam, data.redPlayerIds, data),
          const SizedBox(height: 6),
          _jerseySelector(data.redTeam, _redKitIndex, (i) {
            setState(() => _redKitIndex = i);
            _save();
          }, 'Kirmizi'),
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

  Widget _jerseySelector(
    SavedTeamProfile team,
    int selectedIndex,
    ValueChanged<int> onChanged,
    String label,
  ) {
    final kits = team.jerseyKits.isEmpty
        ? JerseyFactory.defaultKits()
        : team.jerseyKits;
    final value = selectedIndex.clamp(0, kits.length - 1).toInt();
    return DropdownButtonFormField<int>(
      value: value,
      isDense: true,
      decoration: InputDecoration(labelText: '$label forma'),
      items: [
        for (var i = 0; i < kits.length; i++)
          DropdownMenuItem<int>(
            value: i,
            child: Row(
              children: [
                _kitSwatch(kits[i].shirtColor),
                const SizedBox(width: 6),
                _kitSwatch(kits[i].shortsColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(kits[i].name, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      onChanged: (index) {
        if (index == null) {
          return;
        }
        team.activeKitIndex = index;
        onChanged(index);
      },
    );
  }

  Widget _kitSwatch(Color color) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24),
      ),
    );
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
    final isAdmin = data.adminLoggedIn;
    final ownerMatches = data.accounts
        .where((account) => account.id == team.ownerAccountId)
        .toList();
    final ownerName = ownerMatches.isEmpty ? null : ownerMatches.first.username;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                team.name,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            if (isAdmin)
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 18,
                ),
                onPressed: () => _deleteTeam(team),
                tooltip: 'Takimi sil',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          'Oyuncu: ${selected.length}  Deger: ${team.rating.toStringAsFixed(1)}',
        ),
        Text(
          'Galibiyet: ${team.wins}, Maglubiyet: ${team.losses}, Beraberlik: ${team.draws}',
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
                                      : _formationPlayerStats(selectedPlayer),
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
                  : player!.id == selectedPlayerId
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
                        '${player!.number ?? spot.number}',
                        style: TextStyle(
                          color: player!.id == selectedPlayerId
                              ? Colors.black
                              : const Color(0xffffd34d),
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Text(
                          player!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: player!.id == selectedPlayerId
                                ? Colors.black
                                : Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${spot.role.code} • ${player!.effectiveOverall.round()}',
                        style: TextStyle(
                          color: player!.id == selectedPlayerId
                              ? Colors.black87
                              : Colors.white60,
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
          );
          if (player == null) return content;
          return Draggable<PlayerProfile>(
            data: player!,
            feedback: Material(
              color: Colors.transparent,
              child: _dragPlayerCard(player!),
            ),
            childWhenDragging: Opacity(opacity: 0.28, child: content),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onSelected(player!.id),
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

  Widget _formationPlayerStats(PlayerProfile player) {
    final passPercent = player.passes == 0
        ? 0
        : (player.successfulPasses * 100 / player.passes).round();
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
          accent.withValues(alpha: 0.13),
          const Color(0xff0d1a16),
          const Color(0xff08140f),
        ],
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: accent.withValues(alpha: 0.38), width: 1.2),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: const Color(0xff0d1a16),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    );
  }
}
