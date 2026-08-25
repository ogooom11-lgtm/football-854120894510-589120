import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/enums/player_role.dart';
import '../game/models/player_profile.dart';
import '../game/models/shooting.dart';
import '../game/models/team_profile.dart';
import '../storage/roster_storage.dart';
import 'player_detail_screen.dart';
import 'team_detail_screen.dart';

/// Standalone page: pick a team, see its players (sorted by name)
/// and edit them from there. Player value/settings editing only
/// appears when the admin session was opened with the secret
/// "kimo@" prefix (adminFullAccess).
class TeamPlayersScreen extends StatefulWidget {
  const TeamPlayersScreen({super.key, this.initialTeamId, this.adminFullAccess = false});

  final String? initialTeamId;

  /// Whether the admin logged in with the secret "kimo@" prefix, which
  /// unlocks the hidden player values/settings editor on this page.
  final bool adminFullAccess;

  @override
  State<TeamPlayersScreen> createState() => _TeamPlayersScreenState();
}

class _TeamPlayersScreenState extends State<TeamPlayersScreen> {
  final RosterStorage _storage = RosterStorage();
  SavedGameData? _data;
  bool _loading = true;
  String _selectedTeamId = '';
  String _search = '';
  String _addPlayerId = '';
  String _sortBy = 'name';
  bool _sortAsc = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _storage.load();
    if (!mounted) return;
    final teams = data.activeTeams;
    var selected = widget.initialTeamId ?? data.blueTeamId;
    if (!teams.any((team) => team.id == selected)) {
      selected = teams.isNotEmpty ? teams.first.id : '';
    }
    setState(() {
      _data = data;
      _selectedTeamId = selected;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final data = _data;
    if (data == null) return;
    await _storage.save(data);
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openTeamDetail(String teamId) async {
    await _save();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TeamDetailScreen(teamId: teamId)),
    );
    _load();
  }

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

  SavedTeamProfile? get _selectedTeam {
    final data = _data;
    if (data == null) return null;
    final matches = data.teams.where(
      (team) => team.id == _selectedTeamId && !team.isDeleted,
    );
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xff08140f),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final data = _data!;
    final team = _selectedTeam;
    return Scaffold(
      backgroundColor: const Color(0xff08140f),
      appBar: AppBar(
        title: const Text('Takim Oyuncuları'),
        actions: [
          if (widget.adminFullAccess)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: Chip(
                  avatar: Icon(Icons.verified, size: 16, color: Color(0xffffd34d)),
                  label: Text(
                    'Gelismis erisim (kimo@)',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: team == null
          ? const Center(
              child: Text(
                'Kayitli takim yok',
                style: TextStyle(color: Colors.white60),
              ),
            )
          : Column(
              children: [
                _teamHeader(data, team),
                const Divider(height: 1),
                _rosterToolbar(data, team),
                const Divider(height: 1),
                Expanded(child: _playerList(data, team)),
              ],
            ),
    );
  }

  Widget _teamHeader(SavedGameData data, SavedTeamProfile team) {
    final players = data.players
        .where((player) => team.playerIds.contains(player.id))
        .toList();
    final keepers = players.where((player) => player.isGoalkeeper).length;
    final fielders = players.length - keepers;
    final owner = data.accounts
        .where((account) => account.id == team.ownerAccountId)
        .toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(color: Color(0xff0d1a16)),
      child: Row(
        children: [
          const Icon(Icons.shield, color: Color(0xffffd34d)),
          const SizedBox(width: 10),
          SizedBox(
            width: 300,
            child: DropdownButtonFormField<String>(
              value: team.id,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Takim sec'),
              items: [
                for (final item in data.activeTeams)
                  DropdownMenuItem(value: item.id, child: Text(item.name)),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedTeamId = value;
                    _addPlayerId = '';
                  });
                }
              },
            ),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${team.name}  •  ${team.rating.toStringAsFixed(1)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  'Oyuncu: ${players.length} (kaleci $keepers, saha $fielders) | G ${team.wins} B ${team.draws} M ${team.losses} | Toplam deger: ${formatMarketValue(data.teamTotalValue(team))}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                Text(
                  'Form: ${team.formText}'
                  '${team.country.isNotEmpty ? '  •  Ulke: ${team.country}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                Text(
                  'Sahip: ${owner.isEmpty ? 'Secilmedi' : owner.first.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _openTeamDetail(team.id),
            icon: const Icon(Icons.receipt_long, size: 17),
            label: const Text(
              'Mac sonuclari',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          const Tooltip(
            message: 'Takim silme isi sadece Yonetim (admin) panelinden yapilir.',
            child: Icon(Icons.admin_panel_settings_outlined,
                color: Colors.white24),
          ),
        ],
      ),
    );
  }

  Widget _rosterToolbar(SavedGameData data, SavedTeamProfile team) {
    final assignedIds = data.teams
        .where((item) => !item.isDeleted)
        .expand((item) => item.playerIds)
        .toSet();
    final freePlayers = data.players
        .where((player) => !assignedIds.contains(player.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Oyuncu ara',
                isDense: true,
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 168,
            child: DropdownButtonFormField<String>(
              value: _sortBy,
              isDense: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.sort, size: 18),
                labelText: 'Sirala',
              ),
              items: const [
                DropdownMenuItem(value: 'name', child: Text('Ad')),
                DropdownMenuItem(value: 'number', child: Text('Numara')),
                DropdownMenuItem(value: 'ovr', child: Text('Efektif OVR')),
                DropdownMenuItem(
                  value: 'value',
                  child: Text('Piyasa degeri'),
                ),
                DropdownMenuItem(
                  value: 'pointAvg',
                  child: Text('Puan ortalamasi'),
                ),
                DropdownMenuItem(value: 'goals', child: Text('Gol')),
                DropdownMenuItem(value: 'assists', child: Text('Asist')),
                DropdownMenuItem(value: 'shots', child: Text('Sut')),
                DropdownMenuItem(value: 'passPct', child: Text('Pas %')),
                DropdownMenuItem(value: 'speed', child: Text('Hiz')),
                DropdownMenuItem(
                  value: 'finishing',
                  child: Text('Bitiricilik'),
                ),
                DropdownMenuItem(value: 'stamina', child: Text('Enerji')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _sortBy = value);
                }
              },
            ),
          ),
          IconButton(
            tooltip: _sortAsc
                ? 'Artan siralama — tikla, azalan yap'
                : 'Azalan siralama — tikla, artan yap',
            onPressed: () => setState(() => _sortAsc = !_sortAsc),
            icon: Icon(
              _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
              color: const Color(0xffffd34d),
            ),
          ),
          if (freePlayers.isNotEmpty) ...[
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                value: freePlayers.any((player) => player.id == _addPlayerId)
                    ? _addPlayerId
                    : null,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Takima oyuncu ekle'),
                items: [
                  for (final player in freePlayers)
                    DropdownMenuItem(
                      value: player.id,
                      child: Text(player.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() => _addPlayerId = value ?? ''),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _addPlayerId.isEmpty
                  ? null
                  : () => _addPlayerToTeam(data, team),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Ekle'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addPlayerToTeam(
    SavedGameData data,
    SavedTeamProfile team,
  ) async {
    final matches = data.players.where((player) => player.id == _addPlayerId);
    if (matches.isEmpty) return;
    final profile = matches.first;
    setState(() {
      if (!team.playerIds.contains(profile.id)) {
        team.playerIds.add(profile.id);
        team.roleByPlayerId[profile.id] = profile.isGoalkeeper
            ? PlayerRole.goalkeeper
            : PlayerRole.midfieldLeft;
        if (team.starterPlayerIds.length < 11) {
          team.starterPlayerIds.add(profile.id);
        }
      }
      _addPlayerId = '';
    });
    await _save();
  }

  /// Sorts the roster by the selected key (name, number, OVR, market value,
  /// point average, goals, assists, shots, pass %, speed, finishing or
  /// stamina) in the selected direction.
  List<PlayerProfile> _sortedPlayers(
    SavedGameData data,
    SavedTeamProfile team,
    String query,
  ) {
    final players = data.players
        .where(
          (player) =>
              team.playerIds.contains(player.id) &&
              (query.isEmpty ||
                  player.name.toLowerCase().contains(query) ||
                  (player.number?.toString().contains(query) ?? false)),
        )
        .toList();
    players.sort((a, b) {
      final comparison = switch (_sortBy) {
        'name' => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        'number' => (a.number ?? 0).compareTo(b.number ?? 0),
        'ovr' => a.effectiveOverall.compareTo(b.effectiveOverall),
        'value' => a.marketValue.compareTo(b.marketValue),
        'pointAvg' => a.pointAverage.compareTo(b.pointAverage),
        'goals' => a.goals.compareTo(b.goals),
        'assists' => a.assists.compareTo(b.assists),
        'shots' => a.shots.compareTo(b.shots),
        'passPct' => _passPercent(a).compareTo(_passPercent(b)),
        'speed' => a.speedRating.compareTo(b.speedRating),
        'finishing' => a.finishingRating.compareTo(b.finishingRating),
        _ => a.staminaRating.compareTo(b.staminaRating),
      };
      return _sortAsc ? comparison : -comparison;
    });
    return players;
  }

  int _passPercent(PlayerProfile player) => player.passes == 0
      ? 0
      : (player.successfulPasses / player.passes * 100).round();

  Widget _playerList(SavedGameData data, SavedTeamProfile team) {
    final query = _search.trim().toLowerCase();
    final players = _sortedPlayers(data, team, query);
    if (players.isEmpty) {
      return Center(
        child: Text(
          query.isEmpty
              ? 'Bu takimda oyuncu yok.'
              : 'Aramaya uygun oyuncu bulunamadi.',
          style: const TextStyle(color: Colors.white60),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
      itemCount: players.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) => _playerCard(data, team, players[index]),
    );
  }

  Widget _playerCard(SavedGameData data, SavedTeamProfile team, PlayerProfile player) {
    final canEdit = widget.adminFullAccess ||
        team.ownerAccountId == data.activeAccountId ||
        team.ownerAccountId.isEmpty;
    final isStarter = team.starterPlayerIds.contains(player.id);
    final role = team.roleByPlayerId[player.id];
    final passPercent = _passPercent(player);
    final unavailable = player.isSuspended || player.isInjured;
    return InkWell(
      onTap: () => _openPlayerDetail(player.id),
      child: Tooltip(
        message: 'Oyuncu profilini ac',
        child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isStarter
              ? const [Color(0xff17301f), Color(0xff0d1a16)]
              : const [Color(0xff0f1d16), Color(0xff0b1510)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: unavailable
              ? Colors.redAccent.withValues(alpha: 0.55)
              : isStarter
              ? const Color(0xffffd34d).withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.10),
          width: isStarter || unavailable ? 1.4 : 1,
        ),
        boxShadow: isStarter
            ? const [BoxShadow(color: Color(0x22ffd34d), blurRadius: 8)]
            : const [],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: player.isGoalkeeper
                ? const Color(0x55ffd34d)
                : const Color(0x22ffd34d),
            child: Text(
              '${player.number ?? '-'}',
              style: const TextStyle(
                color: Color(0xffffd34d),
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        player.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _badge(
                      isStarter ? 'ILK 11' : 'YEDEK',
                      color: isStarter
                          ? const Color(0xff2ee59d)
                          : Colors.white38,
                    ),
                    if (player.isSuspended) ...[
                      const SizedBox(width: 5),
                      _badge(
                        'CEZALI ${player.suspendedMatchesRemaining} mac',
                        color: Colors.redAccent,
                      ),
                    ],
                    if (player.isInjured) ...[
                      const SizedBox(width: 5),
                      _badge(
                        'SAKAT ${player.injuredDaysRemaining} gun',
                        color: Colors.redAccent,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${role?.turkishName ?? 'Mevki yok'}'
                  '${player.country.isNotEmpty ? '  •  Ulke: ${player.country}' : ''}'
                  '  •  Sut %${player.shootingAccuracyPercent}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _statChip(
                      'OVR',
                      player.effectiveOverall.toStringAsFixed(0),
                      gold: true,
                    ),
                    _statChip('Deger', player.marketValueText),
                    _statChip(
                      'Puan ort.',
                      player.pointAverage.toStringAsFixed(1),
                    ),
                    _statChip('Gol', '${player.goals}'),
                    _statChip('Asist', '${player.assists}'),
                    _statChip('Pas %', '$passPercent'),
                    _statChip(
                      'Hiz',
                      player.speedRating.toStringAsFixed(0),
                    ),
                    _statChip(
                      'Bitiricilik',
                      player.finishingRating.toStringAsFixed(0),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Adi kopyala',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: player.name));
              _showMessage('${player.name} adi panoya kopyalandi');
            },
            icon: const Icon(Icons.copy_all_outlined, size: 18),
          ),
          if (widget.adminFullAccess)
            IconButton(
              tooltip: 'Degerleri ve ayarlari duzenle',
              onPressed: () => _editPlayerValues(player),
              icon: const Icon(Icons.tune, color: Color(0xffffd34d)),
            ),
          IconButton(
            tooltip: 'Adi duzenle',
            onPressed: canEdit ? () => _editPlayerName(player) : null,
            icon: const Icon(Icons.edit, size: 18),
          ),
          IconButton(
            tooltip: 'Numarayi duzenle',
            onPressed: canEdit ? () => _editPlayerNumber(player) : null,
            icon: const Icon(Icons.tag, size: 18),
          ),
          IconButton(
            tooltip: 'Takimdan cikar',
            onPressed: canEdit ? () => _removePlayerFromTeam(data, team, player) : null,
            icon: const Icon(Icons.person_remove_outlined, size: 18),
          ),
          IconButton(
            tooltip: widget.adminFullAccess
                ? 'Oyuncuyu sil'
                : 'Oyuncu silme islemini sadece yonetici (admin) yapabilir',
            onPressed:
                widget.adminFullAccess ? () => _deletePlayer(player) : null,
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
          ),
        ],
      ),
      ),
      ),
    );
  }

  Widget _badge(String text, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.50)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _statChip(String label, String value, {bool gold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: gold
            ? const Color(0x33ffd34d)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: gold
              ? const Color(0xffffd34d).withValues(alpha: 0.40)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Text(
        '$label  $value',
        style: TextStyle(
          color: gold ? const Color(0xffffd34d) : Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Future<void> _editPlayerName(PlayerProfile player) async {
    final controller = TextEditingController(text: player.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff102019),
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
    if (name == null || name.trim().isEmpty || !mounted) return;
    setState(() => player.name = name.trim());
    await _save();
  }

  Future<void> _editPlayerNumber(PlayerProfile player) async {
    final controller = TextEditingController(text: '${player.number ?? ''}');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff102019),
        title: const Text('Forma numarasi'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Numara (1-99)'),
          onSubmitted: (text) {
            final parsed = int.tryParse(text.trim());
            if (parsed != null) {
              Navigator.of(context).pop(parsed.clamp(1, 99).toInt());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              if (parsed != null) {
                Navigator.of(context).pop(parsed.clamp(1, 99).toInt());
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    setState(() => player.number = value);
    await _save();
  }

  Future<void> _removePlayerFromTeam(
    SavedGameData data,
    SavedTeamProfile team,
    PlayerProfile player,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff102019),
        title: const Text('Takimdan cikar'),
        content: Text(
          '${player.name} oyuncusunu ${team.name} takimindan cikarmak istediginize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cikar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      team.playerIds.remove(player.id);
      team.starterPlayerIds.remove(player.id);
      team.roleByPlayerId.remove(player.id);
      team.slotByPlayerId.remove(player.id);
    });
    await _save();
  }

  Future<void> _deletePlayer(PlayerProfile player) async {
    final data = _data;
    if (data == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff102019),
        title: const Text('Oyuncuyu sil'),
        content: Text(
          '${player.name} oyuncusunu tamamen silmek istediginize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      data.players.removeWhere((item) => item.id == player.id);
      data.transferRequests.removeWhere(
        (request) => request.playerId == player.id,
      );
      for (final team in data.teams) {
        team.playerIds.remove(player.id);
        team.starterPlayerIds.remove(player.id);
        team.roleByPlayerId.remove(player.id);
        team.slotByPlayerId.remove(player.id);
      }
    });
    await _save();
  }

  // ---------------------------------------------------------------------
  // Hidden player values/settings editor — only visible with kimo@ access.
  // ---------------------------------------------------------------------

  Future<void> _editPlayerValues(PlayerProfile player) async {
    final data = _data;
    if (data == null || !widget.adminFullAccess) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xff102019),
          title: Text('${player.name} • Degerler'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _slider(setDialogState, 'Genel oyun', player.overallRating,
                      (v) => player.overallRating = v),
                  _slider(setDialogState, 'Sut', player.shootingRating,
                      (v) => player.shootingRating = v),
                  _slider(setDialogState, 'Bitiricilik', player.finishingRating,
                      (v) => player.finishingRating = v),
                  _slider(setDialogState, 'Sut gucu', player.shotPowerRating,
                      (v) => player.shotPowerRating = v),
                  _slider(setDialogState, 'Uzaktan sut', player.longShotsRating,
                      (v) => player.longShotsRating = v),
                  _slider(setDialogState, 'Falso', player.curveRating,
                      (v) => player.curveRating = v),
                  _slider(setDialogState, 'Sogukkanlilik',
                      player.composureRating, (v) => player.composureRating = v),
                  _slider(setDialogState, 'Denge', player.balanceRating,
                      (v) => player.balanceRating = v),
                  _slider(setDialogState, 'Pas', player.passingRating,
                      (v) => player.passingRating = v),
                  _slider(setDialogState, 'Kalecilik', player.goalkeepingRating,
                      (v) => player.goalkeepingRating = v),
                  if (player.isGoalkeeper) ...[
                    _slider(setDialogState, 'GK Reaksiyon',
                        player.goalkeeperReactionRating,
                        (v) => player.goalkeeperReactionRating = v),
                    _slider(setDialogState, 'GK Pozisyon',
                        player.goalkeeperPositioningRating,
                        (v) => player.goalkeeperPositioningRating = v),
                    _slider(setDialogState, 'GK Atlayis',
                        player.goalkeeperDivingRating,
                        (v) => player.goalkeeperDivingRating = v),
                    _slider(setDialogState, 'GK Handling',
                        player.goalkeeperHandlingRating,
                        (v) => player.goalkeeperHandlingRating = v),
                    _slider(setDialogState, 'GK Yakalayis',
                        player.goalkeeperCatchingRating,
                        (v) => player.goalkeeperCatchingRating = v),
                    _slider(setDialogState, 'GK Sicrama',
                        player.goalkeeperJumpingRating,
                        (v) => player.goalkeeperJumpingRating = v),
                    _slider(setDialogState, 'GK Karar',
                        player.goalkeeperDecisionRating,
                        (v) => player.goalkeeperDecisionRating = v),
                    _slider(setDialogState, 'GK Bire Bir',
                        player.goalkeeperOneVsOneRating,
                        (v) => player.goalkeeperOneVsOneRating = v),
                    _slider(setDialogState, 'GK Yuksek Top',
                        player.goalkeeperHighBallsRating,
                        (v) => player.goalkeeperHighBallsRating = v),
                    _slider(setDialogState, 'GK Sogukkanlilik',
                        player.goalkeeperComposureRating,
                        (v) => player.goalkeeperComposureRating = v),
                    _slider(setDialogState, 'GK Hizlanma',
                        player.goalkeeperAccelerationRating,
                        (v) => player.goalkeeperAccelerationRating = v),
                    _slider(setDialogState, 'GK Erisim', player.goalkeeperReachRating,
                        (v) => player.goalkeeperReachRating = v),
                    _slider(setDialogState, 'GK Ayak Hareketi',
                        player.goalkeeperFootworkRating,
                        (v) => player.goalkeeperFootworkRating = v),
                    _slider(setDialogState, 'GK Ongoru',
                        player.goalkeeperAnticipationRating,
                        (v) => player.goalkeeperAnticipationRating = v),
                    _slider(setDialogState, 'GK Sektirme',
                        player.goalkeeperParryingRating,
                        (v) => player.goalkeeperParryingRating = v),
                    _slider(setDialogState, 'GK Dagitim',
                        player.goalkeeperDistributionRating,
                        (v) => player.goalkeeperDistributionRating = v),
                  ],
                  _slider(setDialogState, 'Hiz', player.speedRating,
                      (v) => player.speedRating = v),
                  _slider(setDialogState, 'Enerji', player.staminaRating,
                      (v) => player.staminaRating = v),
                  _slider(setDialogState, 'Dayaniklilik', player.dayaniklilikGucu,
                      (v) => player.dayaniklilikGucu = v),
                  _slider(setDialogState, 'Zeka', player.zekaGucu,
                      (v) => player.zekaGucu = v),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SizedBox(width: 128, child: Text('Tercih edilen ayak')),
                      DropdownButton<PreferredFoot>(
                        value: player.preferredFoot,
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
                          if (value != null) {
                            setDialogState(() => player.preferredFoot = value);
                          }
                        },
                      ),
                      const Spacer(),
                      const Text('Zayif ayak'),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: player.weakFootRating.clamp(1, 5).toInt(),
                        items: [
                          for (var value = 1; value <= 5; value++)
                            DropdownMenuItem(
                              value: value,
                              child: Text('$value/5'),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => player.weakFootRating = value);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Mac cezasi',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          'Sari ${player.yellowCards} • Kirmizi ${player.redCards}',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 10),
                        DropdownButton<int>(
                          value: player.suspendedMatchesRemaining
                              .clamp(0, 50)
                              .toInt(),
                          items: [
                            for (var matches = 0; matches <= 50; matches++)
                              DropdownMenuItem(
                                value: matches,
                                child: Text('$matches mac'),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(
                                () => player.suspendedMatchesRemaining = value,
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Vazgec'),
            ),
            FilledButton(
              onPressed: () async {
                await _save();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(
    StateSetter setDialogState,
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 128, child: Text(label)),
        Expanded(
          child: Slider(
            min: 1,
            max: 99,
            divisions: 98,
            value: value.clamp(1, 99).toDouble(),
            label: value.toStringAsFixed(0),
            onChanged: (newValue) => setDialogState(() => onChanged(newValue)),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(value.toStringAsFixed(0), textAlign: TextAlign.end),
        ),
      ],
    );
  }
}
