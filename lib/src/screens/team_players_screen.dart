import 'package:flutter/material.dart';

import '../game/enums/player_role.dart';
import '../game/models/player_profile.dart';
import '../game/models/shooting.dart';
import '../game/models/team_profile.dart';
import '../storage/roster_storage.dart';

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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${team.name}  •  ${team.rating.toStringAsFixed(1)}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                'Oyuncu: ${players.length} (kaleci $keepers, saha $fielders) | G ${team.wins} B ${team.draws} M ${team.losses}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              Text(
                'Sahip: ${owner.isEmpty ? 'Secilmedi' : owner.first.username}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () => _deleteTeam(team),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Takimi sil'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
            ),
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

  Widget _playerList(SavedGameData data, SavedTeamProfile team) {
    final query = _search.trim().toLowerCase();
    final players = data.players
        .where(
          (player) =>
              team.playerIds.contains(player.id) &&
              (query.isEmpty ||
                  player.name.toLowerCase().contains(query) ||
                  (player.number?.toString().contains(query) ?? false)),
        )
        .toList()
      ..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : (a.number ?? 0).compareTo(b.number ?? 0);
      });
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xff0d1a16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isStarter
              ? const Color(0xffffd34d).withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Icon(
            player.isGoalkeeper ? Icons.back_hand : Icons.directions_run,
            color: player.isGoalkeeper
                ? const Color(0xffffd34d)
                : Colors.white70,
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 44,
            child: Text(
              '#${player.number ?? '-'}',
              style: const TextStyle(
                color: Colors.white60,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  'OVR ${player.effectiveOverall.toStringAsFixed(0)} | '
                  'Sut gucu ${player.shotPowerRating.toStringAsFixed(0)} | '
                  'Sut %${player.shootingAccuracyPercent} | '
                  'Hiz ${player.speedRating.toStringAsFixed(0)} | '
                  '${role?.turkishName ?? 'Mevki yok'} | '
                  'Deger ${player.marketValueText} | '
                  '${isStarter ? 'ILK 11' : 'YEDEK'}'
                  '${player.isSuspended ? ' | CEZALI ${player.suspendedMatchesRemaining} mac' : ''}'
                  '${player.isInjured ? ' | SAKAT ${player.injuredDaysRemaining} gun' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
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
            icon: const Icon(Icons.edit),
          ),
          IconButton(
            tooltip: 'Numarayi duzenle',
            onPressed: canEdit ? () => _editPlayerNumber(player) : null,
            icon: const Icon(Icons.tag),
          ),
          IconButton(
            tooltip: 'Takimdan cikar',
            onPressed: canEdit ? () => _removePlayerFromTeam(data, team, player) : null,
            icon: const Icon(Icons.person_remove_outlined),
          ),
          IconButton(
            tooltip: 'Oyuncuyu sil',
            onPressed: canEdit ? () => _deletePlayer(player) : null,
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          ),
        ],
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

  Future<void> _deleteTeam(SavedTeamProfile team) async {
    final data = _data;
    if (data == null) return;
    if (data.activeTeams.length <= 1) {
      _showMessage('En az bir aktif takim kalmali');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff102019),
        title: const Text('Takimi Sil'),
        content: Text(
          '${team.name} takimini silmek istediginize emin misiniz?\n'
          'Bu islem geri alinamaz.',
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
      team.isDeleted = true;
      data.transferRequests.removeWhere(
        (request) => request.targetTeamId == team.id,
      );
      if (_selectedTeamId == team.id) {
        final remaining = data.activeTeams
            .where((item) => item.id != team.id)
            .toList();
        _selectedTeamId = remaining.isNotEmpty ? remaining.first.id : '';
      }
    });
    await _save();
    _showMessage('${team.name} takimi silindi');
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
