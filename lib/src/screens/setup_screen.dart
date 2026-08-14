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
import '../game/models/match_event.dart';
import '../game/models/player_profile.dart';
import '../game/models/jersey_kit.dart';
import '../game/models/team_profile.dart';
import '../game/models/team_setup.dart';
import '../storage/roster_storage.dart';
import 'game_screen.dart';
import 'account_detail_screen.dart';
import 'penalties_page.dart';
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

  /// True only when the admin logged in using the secret `kimo@` prefix.
  /// Gates the hidden player data / player editing section.
  bool _playerDataUnlocked = false;

  /// Kilitli sekmeye tiklandiginda, sifre dogrulaninca acilacak sekme.
  /// 5 = Yonetim, 6 = CEZALAR.
  int _pendingAdminTab = 5;

  /// Ust uste hatali yonetici sifresi denemesi sayisi.
  int _adminFailCount = 0;

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
        ..playerIds = data.bluePlayerIds;
    }
    if (data.isTeamOwnerLoggedIn(data.redTeam)) {
      data.redTeam
        ..name = _redNameController.text.trim().isEmpty
            ? 'Kirmizi Takim'
            : _redNameController.text.trim()
        ..formation = data.redFormation
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

  Future<void> _openAdminLogin() async {
    setState(() {
      _pendingAdminTab = 5;
      _showAdminPasswordField = true;
      _adminPasswordError = false;
    });
  }

  Future<void> _submitAdminPassword() async {
    final data = _data;
    if (data == null) return;
    final typed = _adminPasswordController.text.trim();
    // `kimo@<sifre>` = admin girisi + gizli oyuncu bilgileri bolumu.
    final unlockPlayers = SavedGameData.hasPlayerDataPrefix(typed);
    final password = SavedGameData.stripPlayerDataPrefix(typed).trim();
    if (!data.adminPasswordSet) {
      if (password.length < 3) {
        setState(() => _adminPasswordError = true);
        return;
      }
      setState(() {
        data.setAdminPassword(password);
        data.adminLoggedIn = true;
        _playerDataUnlocked = unlockPlayers;
        _showAdminPasswordField = false;
        _adminPasswordController.clear();
        _setupTab = _pendingAdminTab;
      });
      await _save();
      return;
    }
    if (!data.checkAdminPassword(password)) {
      setState(() {
        _adminPasswordError = true;
        _adminFailCount += 1;
      });
      return;
    }
    setState(() {
      _adminFailCount = 0;
      data.adminLoggedIn = true;
      _playerDataUnlocked = unlockPlayers;
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

  /// 3 basarisiz denemeden sonra yonetici sifresini tamamen sifirlar.
  /// Kayitli hash silinir; bir sonraki girilen sifre YENI sifre olur.
  Future<void> _resetAdminPasswordFlow() async {
    final data = _data;
    if (data == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.lock_reset,
          color: Colors.orangeAccent,
          size: 34,
        ),
        title: const Text('Yonetici sifresini sifirla'),
        content: const Text(
          'Kayitli yonetici sifresi silinecek.\n\n'
          'Bundan sonra sifre alanina yazacagin ilk sifre '
          'YENI yonetici sifresi olarak kaydedilir.\n\n'
          'Devam edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sifirla'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      data.adminPasswordHash = '';
      _adminFailCount = 0;
      _adminPasswordError = false;
      _adminPasswordController.clear();
    });
    await _save();
    _showMessage('Sifre sifirlandi — yeni sifreni yaz');
  }

  Future<void> _adminLogout(SavedGameData data) async {
    setState(() {
      data.adminLoggedIn = false;
      _playerDataUnlocked = false;
      // Sekme gizlenmez; ayni sekmede kilitli ekran gosterilir.
      _pendingAdminTab = (_setupTab == 5 || _setupTab == 6) ? _setupTab : 5;
    });
    await _save();
  }

  Future<void> _openTeamPlayersScreen() async {
    await _save();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TeamPlayersScreen()));
    _load();
  }

  /// Admin: reset an account password without knowing the old one.
  Future<void> _adminResetAccountPassword(
    SavedGameData data,
    SavedAccountProfile account,
  ) async {
    final controller = TextEditingController();
    final newPassword = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${account.username} — yeni sifre'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Yeni sifre (en az 3 karakter)',
          ),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newPassword == null) {
      return;
    }
    if (newPassword.trim().length < 3) {
      _showMessage('Sifre en az 3 karakter olmali');
      return;
    }
    final ok = data.adminResetAccountPassword(account.id, newPassword);
    if (!ok) {
      _showMessage('Sifre degistirilemedi');
      return;
    }
    setState(() {});
    await _save();
    _showMessage('${account.username} sifresi guncellendi');
  }

  /// Admin: delete an account (with confirmation).
  Future<void> _adminDeleteAccount(
    SavedGameData data,
    SavedAccountProfile account,
  ) async {
    if (data.accounts.length <= 1) {
      _showMessage('Son hesap silinemez');
      return;
    }
    final ownedCount = data.teams
        .where((team) => team.ownerAccountId == account.id && !team.isDeleted)
        .length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: Colors.redAccent, size: 34),
        title: const Text('Hesabi sil'),
        content: Text(
          '"${account.username}" hesabini silmek uzeresiniz.\n\n'
          '${ownedCount > 0 ? 'Bu hesaba ait $ownedCount takim sahipsiz kalacak (takimlar silinmez).\n\n' : ''}'
          'Bu islem geri alinamaz. Emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Evet, sil'),
          ),
        ],
      ),
    );
    if (confirm != true) {
      return;
    }
    final ok = data.adminDeleteAccount(account.id);
    if (!ok) {
      _showMessage('Hesap silinemedi');
      return;
    }
    setState(() {
      _blueNameController.text = data.blueTeam.name;
      _redNameController.text = data.redTeam.name;
    });
    await _save();
    _showMessage('${account.username} silindi');
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
    final injuredStarter = data.players.where(
      (player) => team.starterPlayerIds.contains(player.id) && player.isInjured,
    );
    if (injuredStarter.isNotEmpty) {
      return team.name + ': ' + injuredStarter.first.name + ' sakat ve oynayamaz';
    }
    final bannedStarter = data.players.where(
      (player) => team.starterPlayerIds.contains(player.id) && player.isBanned,
    );
    if (bannedStarter.isNotEmpty) {
      final banned = bannedStarter.first;
      return '${team.name}: ${banned.name} cezali '
          '(${banned.banMatches} mac) ve oynayamaz';
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
    final blue = data.teams.where(
      (team) => team.id == summary.blueStorageTeamId,
    );
    final red = data.teams.where((team) => team.id == summary.redStorageTeamId);
    if (blue.isEmpty || red.isEmpty) {
      return;
    }
    final blueTeam = blue.first;
    final redTeam = red.first;
    // Mac oynandi: bu iki takimin cezali oyuncularinin ceza suresi 1 azalir.
    final involvedIds = {...blueTeam.playerIds, ...redTeam.playerIds};
    for (final player in data.players) {
      if (involvedIds.contains(player.id)) {
        player.serveBanMatch();
      }
    }
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
    final timestamp = DateTime.now().millisecondsSinceEpoch;
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
    final locked = data?.adminLoggedIn != true;
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
      // Yonetici sekmeleri HER ZAMAN gorunur. Kilitliyken tiklaninca
      // sifre sorulur, sekme gizlenmez.
      ButtonSegment(
        value: 6,
        icon: Icon(locked ? Icons.lock_outline : Icons.gavel),
        label: const Text('CEZALAR'),
      ),
      ButtonSegment(
        value: 5,
        icon: Icon(
          locked ? Icons.lock_outline : Icons.admin_panel_settings,
        ),
        label: const Text('Yonetim'),
      ),
    ];
    final selectedValue = segments.any((segment) => segment.value == _setupTab)
        ? _setupTab
        : 0;
    return SegmentedButton<int>(
      segments: segments,
      selected: {selectedValue},
      onSelectionChanged: (selection) => _onTabSelected(selection.first),
    );
  }

  /// Kilitli bir yonetici sekmesine tiklanirsa sekmeyi gizlemek yerine
  /// sifre alanini acar.
  void _onTabSelected(int tab) {
    final adminTab = tab == 5 || tab == 6;
    if (adminTab && _data?.adminLoggedIn != true) {
      setState(() {
        _pendingAdminTab = tab;
        _showAdminPasswordField = true;
        _adminPasswordError = false;
      });
      return;
    }
    setState(() => _setupTab = tab);
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
      5 => data.adminLoggedIn ? _adminPage(data) : _lockedPage('Yonetim'),
      6 => data.adminLoggedIn ? _penaltiesPage(data) : _lockedPage('CEZALAR'),
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
                    errorText: _adminPasswordError
                        ? (_adminFailCount >= 3
                              ? 'Hatali sifre — sifirlamak icin X yanindaki ? '
                                    'butonunu kullan'
                              : 'Hatali sifre')
                        : null,
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
              if (_adminFailCount >= 3)
                IconButton(
                  icon: const Icon(
                    Icons.help_outline,
                    color: Colors.orangeAccent,
                  ),
                  onPressed: _resetAdminPasswordFlow,
                  tooltip: 'Sifreyi sifirla',
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
          Expanded(
            child: ListView.separated(
              itemCount: data.accounts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final account = data.accounts[index];
                final teamCount = data.teams
                    .where((team) => team.ownerAccountId == account.id)
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
                      (team) => team.ownerAccountId == account.id,
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
    final teams = data.teams;
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
      onChanged: (value) {
        if (value == null) {
          return;
        }
        setState(() => team.ownerAccountId = value);
        _save();
      },
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
    final teams = data.teams;
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
    // Oyuncular her zaman ISME gore siralanir; guc degisince liste
    // yer degistirmez.
    final goalkeepers =
        data.players.where((player) => player.isGoalkeeper).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final fieldPlayers =
        data.players.where((player) => !player.isGoalkeeper).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
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
    for (final team in data.teams) {
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
                  'Rey:${profile.effectiveOverall.toStringAsFixed(0)} Hiz:${profile.speedRating.toStringAsFixed(0)} Enerji:${profile.staminaRating.toStringAsFixed(0)} Gol:${profile.goals} Pas:${profile.successfulPasses}/${profile.passes} Sut:${profile.shotsOnTarget}/${profile.shots} Kacan:${profile.missedChances}',
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

  /// Kilitli yonetici sayfasi icin bilgi ekrani. Sekme gizlenmez,
  /// sadece icerik kilitli gosterilir.
  Widget _lockedPage(String title) {
    return Container(
      decoration: _panelDecoration(),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 54, color: Colors.white24),
            const SizedBox(height: 14),
            Text(
              '$title kilitli',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Devam etmek icin yonetici sifresini gir.',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => setState(() {
                _pendingAdminTab = _setupTab;
                _showAdminPasswordField = true;
                _adminPasswordError = false;
              }),
              icon: const Icon(Icons.key),
              label: const Text('Sifre gir'),
            ),
          ],
        ),
      ),
    );
  }

  /// CEZALAR sayfasi — normal yonetici sifresi ile acilir (kimo@ gerekmez).
  Widget _penaltiesPage(SavedGameData data) {
    return PenaltiesPage(
      key: ValueKey('cezalar-${data.players.length}'),
      data: data,
      onSave: _save,
      onLock: () => _adminLogout(data),
    );
  }

  Widget _adminPage(SavedGameData data) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: _adminAccountsPanel(data)),
        const SizedBox(width: 16),
        Expanded(flex: 2, child: _adminTeamsPanel(data)),
      ],
    );
  }

  /// Admin panel — accounts only. Password reset + account delete.
  Widget _adminAccountsPanel(SavedGameData data) {
    final accounts = [...data.accounts]
      ..sort(
        (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
      );
    return Container(
      decoration: _panelDecoration(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Yonetim: hesaplar',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _adminLogout(data),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Kilitle'),
                ),
              ],
            ),
          ),
          if (_playerDataUnlocked)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openTeamPlayersScreen,
                  icon: const Icon(Icons.manage_accounts),
                  label: const Text('Oyuncu bilgileri (takim sec)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xffffd34d),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: accounts.isEmpty
                ? const Center(child: Text('Hesap yok'))
                : ListView.separated(
                    itemCount: accounts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        _adminAccountRow(data, accounts[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _adminAccountRow(SavedGameData data, SavedAccountProfile account) {
    final teamCount = data.teams
        .where((team) => team.ownerAccountId == account.id && !team.isDeleted)
        .length;
    final loggedIn = data.isAccountLoggedIn(account.id);
    final isActive = account.id == data.activeAccountId;
    final isLastAccount = data.accounts.length <= 1;
    return ListTile(
      leading: Icon(
        loggedIn ? Icons.verified_user : Icons.account_circle,
        color: loggedIn ? Colors.greenAccent : Colors.white70,
      ),
      title: Text(
        account.username,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        'Takim: $teamCount | '
        '${account.hasPassword ? 'sifre var' : 'sifre yok'}'
        '${isActive ? ' | aktif' : ''}',
        style: const TextStyle(fontSize: 12, color: Colors.white54),
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'Sifreyi degistir',
            icon: const Icon(Icons.key, color: Color(0xffffd34d)),
            onPressed: () => _adminResetAccountPassword(data, account),
          ),
          IconButton(
            tooltip: isLastAccount ? 'Son hesap silinemez' : 'Hesabi sil',
            icon: Icon(
              Icons.delete_outline,
              color: isLastAccount ? Colors.white24 : Colors.redAccent,
            ),
            onPressed: isLastAccount
                ? null
                : () => _adminDeleteAccount(data, account),
          ),
        ],
      ),
    );
  }

  /// Admin panel — team list with delete (confirmation dialog).
  Widget _adminTeamsPanel(SavedGameData data) {
    final teams = data.teams.where((team) => !team.isDeleted).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return Container(
      decoration: _panelDecoration(),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Yonetim: takimlar',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: teams.isEmpty
                ? const Center(child: Text('Takim yok'))
                : ListView.separated(
                    itemCount: teams.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final team = teams[index];
                      final ownerMatches = data.accounts.where(
                        (account) => account.id == team.ownerAccountId,
                      );
                      final ownerName = ownerMatches.isEmpty
                          ? 'Sahipsiz'
                          : ownerMatches.first.username;
                      return ListTile(
                        leading: const Icon(Icons.shield),
                        title: Text(
                          team.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          'Sahip: $ownerName | oyuncu ${team.playerIds.length} | '
                          'guc ${team.rating.toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Takimi sil',
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                          onPressed: () => _deleteTeam(team),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }


  Future<void> _deleteTeam(SavedTeamProfile team) async {
    final data = _data;
    final playerCount = team.playerIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: Colors.redAccent,
          size: 34,
        ),
        title: const Text('DIKKAT — Takimi sil'),
        content: Text(
          '"${team.name}" takimini silmek uzeresiniz.\n\n'
          'Kadrodaki $playerCount oyuncu bosa dusecek ve takimin '
          'mac gecmisi listelerden kaldirilacak.\n\n'
          'Bu islem geri alinamaz. Devam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Evet, sil'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      team.isDeleted = true;
      if (data != null) {
        final remaining = data.teams.where((t) => !t.isDeleted).toList();
        if (remaining.isNotEmpty) {
          if (data.blueTeamId == team.id) {
            data.blueTeamId = remaining.first.id;
            data.bluePlayerIds = data.blueTeam.playerIds;
            data.blueFormation = data.blueTeam.formation;
            _blueNameController.text = data.blueTeam.name;
          }
          if (data.redTeamId == team.id) {
            data.redTeamId = remaining.length > 1
                ? remaining[1].id
                : remaining.first.id;
            data.redPlayerIds = data.redTeam.playerIds;
            data.redFormation = data.redTeam.formation;
            _redNameController.text = data.redTeam.name;
          }
        }
      }
    });
    await _save();
    _showMessage('${team.name} silindi');
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
          const Divider(height: 26),
          _summaryBlock(data.redTeam, data.redPlayerIds, data),
          const SizedBox(height: 10),
          _lineupEditor(data.redTeam, data),
          const SizedBox(height: 14),
          const Text(
            'Ilk 11 tam olmadan mac baslamaz. Yeni eklenen oyuncunun boyu 1.70-1.80 m arasinda rastgele atanir.',
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

  Widget _lineupEditor(SavedTeamProfile team, SavedGameData data) {
    // Kadro listesi isme gore sabit sirada durur (guce gore degil).
    final players = data.players
        .where((profile) => team.playerIds.contains(profile.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final starters = players
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
                Text(
                  'Degisiklik 5',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
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
                                    'OVR:${profile.overallRating.toStringAsFixed(0)} ZK:${profile.zekaGucu.toStringAsFixed(0)}',
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
                                        setState(
                                          () =>
                                              team.roleByPlayerId[profile.id] =
                                                  value,
                                        );
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

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: const Color(0xff0d1a16),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    );
  }
}
