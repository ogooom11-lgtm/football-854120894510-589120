import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/enums/ai_play_style.dart';
import '../game/models/formation.dart';
import '../game/models/player_profile.dart';
import '../game/models/team_profile.dart';
import '../storage/roster_storage.dart';

/// Detailed account page showing all teams and player stats.
class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key});

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen>
    with SingleTickerProviderStateMixin {
  final RosterStorage _storage = RosterStorage();
  SavedGameData? _data;
  late final TabController _tabController;
  bool _loading = true;
  final FocusNode _adminShortcutFocus = FocusNode();
  String _adminShortcutBuffer = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _adminShortcutFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _adminShortcutFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await _storage.load();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
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
    return KeyboardListener(
      focusNode: _adminShortcutFocus,
      autofocus: true,
      onKeyEvent: _handleAdminShortcut,
      child: Scaffold(
      backgroundColor: const Color(0xff08140f),
      appBar: AppBar(
        title: const Text('Hesap Detayi'),
        backgroundColor: const Color(0xff0d1a16),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xffffd34d),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Takimlarim'),
            Tab(text: 'Oyuncularim'),
            Tab(text: 'Tum Takimlar'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_myTeamsTab(data), _myPlayersTab(data), _allTeamsTab(data)],
      ),
    ),
    );
  }

  void _handleAdminShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return;
    }
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final allPressed = (pressed.contains(LogicalKeyboardKey.controlLeft) ||
            pressed.contains(LogicalKeyboardKey.controlRight)) &&
        (pressed.contains(LogicalKeyboardKey.shiftLeft) ||
            pressed.contains(LogicalKeyboardKey.shiftRight)) &&
        pressed.contains(LogicalKeyboardKey.keyA) &&
        pressed.contains(LogicalKeyboardKey.keyD) &&
        pressed.contains(LogicalKeyboardKey.keyC);
    if (allPressed) {
      _adminShortcutBuffer = '';
      _showAdminPanel();
      return;
    }
    if (!HardwareKeyboard.instance.isControlPressed ||
        !HardwareKeyboard.instance.isShiftPressed) {
      _adminShortcutBuffer = '';
      return;
    }
    final key = event.logicalKey;
    final letter = key == LogicalKeyboardKey.keyA
        ? 'a'
        : key == LogicalKeyboardKey.keyD
        ? 'd'
        : key == LogicalKeyboardKey.keyC
        ? 'c'
        : '';
    if (letter.isEmpty) {
      _adminShortcutBuffer = '';
      return;
    }
    _adminShortcutBuffer = (_adminShortcutBuffer + letter).replaceAll(
      RegExp(r'[^adc]'),
      '',
    );
    if (_adminShortcutBuffer.endsWith('adc')) {
      _adminShortcutBuffer = '';
      _showAdminPanel();
    }
  }

  Future<void> _showAdminPanel() async {
    final data = _data;
    if (data == null) return;
    final teams = data.teams.where((team) => !team.isDeleted).toList();
    if (teams.isEmpty) return;
    var selectedTeamId = teams.first.id;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final team = teams.firstWhere((item) => item.id == selectedTeamId);
          final players = data.players
              .where((player) => team.playerIds.contains(player.id))
              .toList();
          return AlertDialog(
            backgroundColor: const Color(0xff102019),
            title: const Text('لوحة الإدارة — الفرق واللاعبون'),
            content: SizedBox(
              width: 640,
              height: 500,
              child: Column(
                children: [
                  DropdownButton<String>(
                    value: selectedTeamId,
                    isExpanded: true,
                    items: [
                      for (final item in teams)
                        DropdownMenuItem(value: item.id, child: Text(item.name)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedTeamId = value);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final player in players)
                          ListTile(
                            title: Text(player.name),
                            subtitle: Text(
                              'تسديد ' + player.shootingRating.toStringAsFixed(0) +
                                  ' | تمرير ' + player.passingRating.toStringAsFixed(0) +
                                  ' | سرعة ' + player.speedRating.toStringAsFixed(0) +
                                  ' | طاقة ' + player.staminaRating.toStringAsFixed(0),
                            ),
                            trailing: const Icon(Icons.edit),
                            onTap: () => _showPlayerEditor(player),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showPlayerEditor(PlayerProfile player) async {
    final data = _data;
    if (data == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xff102019),
          title: Text('تعديل ' + player.name),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _adminEditorSlider('القوة العامة', player.overallRating, (v) {
                    setDialogState(() => player.overallRating = v);
                  }),
                  _adminEditorSlider('دقة التسديد', player.shootingRating, (v) {
                    setDialogState(() => player.shootingRating = v);
                  }),
                  _adminEditorSlider('دقة التمرير / الاحتفاظ', player.passingRating, (v) {
                    setDialogState(() => player.passingRating = v);
                  }),
                  _adminEditorSlider('السرعة', player.speedRating, (v) {
                    setDialogState(() => player.speedRating = v);
                  }),
                  _adminEditorSlider('الطاقة', player.staminaRating, (v) {
                    setDialogState(() => player.staminaRating = v);
                  }),
                  _adminEditorSlider('مهارة الحارس', player.goalkeepingRating, (v) {
                    setDialogState(() => player.goalkeepingRating = v);
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                await _storage.save(data);
                if (context.mounted) Navigator.pop(context);
                if (mounted) setState(() {});
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adminEditorSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 155, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(1, 99).toDouble(),
            min: 1,
            max: 99,
            divisions: 98,
            label: value.toStringAsFixed(0),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 32, child: Text(value.toStringAsFixed(0))),
      ],
    );
  }

  Widget _myTeamsTab(SavedGameData data) {
    final myTeams = data.teams
        .where((t) => t.ownerAccountId == data.activeAccountId && !t.isDeleted)
        .toList();

    if (myTeams.isEmpty) {
      return const Center(
        child: Text(
          'Henuz takimin yok. Admin panelinden olusturabilirsin.',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: myTeams.length,
      itemBuilder: (ctx, index) {
        final team = myTeams[index];
        final players = data.players
            .where((p) => team.playerIds.contains(p.id))
            .toList();
        return _teamCard(team, players, data);
      },
    );
  }

  Widget _teamCard(
    SavedTeamProfile team,
    List<PlayerProfile> players,
    SavedGameData data,
  ) {
    final isOwner = team.ownerAccountId == data.activeAccountId;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff0d1a16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isOwner
              ? const Color(0xffffd34d).withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  team.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xffffd34d).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${team.rating.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xffffd34d),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _miniStat('O', team.played),
              _miniStat('G', team.wins),
              _miniStat('B', team.draws),
              _miniStat('M', team.losses),
              const Spacer(),
              Text(
                team.formation.title.split(' ').first,
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(width: 8),
              Text(
                team.playStyle.title,
                style: const TextStyle(color: Color(0xffffd34d), fontSize: 12),
              ),
            ],
          ),
          if (team.isDeleted)
            const Text('SILINMIS', style: TextStyle(color: Colors.redAccent)),
          if (team.matchHistory.isNotEmpty) ...[
            const Divider(height: 16),
            const Text(
              'Son 5 mac:',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 4),
            ...team.matchHistory
                .take(5)
                .map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '${r.result} ${r.scoreText} vs ${r.opponentName}',
                      style: TextStyle(
                        fontSize: 12,
                        color: r.result == 'G'
                            ? Colors.greenAccent
                            : r.result == 'M'
                            ? Colors.redAccent
                            : Colors.white60,
                      ),
                    ),
                  ),
                ),
          ],
          if (players.isNotEmpty) ...[
            const Divider(height: 16),
            const Text(
              'Oyuncular:',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: players.length,
                itemBuilder: (ctx, i) {
                  final p = players[i];
                  return Container(
                    width: 100,
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: p.isInjured
                          ? Colors.red.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: p.isInjured
                                ? Colors.redAccent
                                : Colors.white,
                          ),
                        ),
                        Text(
                          'OVR:${p.overallRating.toStringAsFixed(0)} ZK:${p.zekaGucu.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white54,
                          ),
                        ),
                        if (p.isInjured)
                          Text(
                            'Sakat ${p.injuredDaysRemaining}g',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.redAccent,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniStat(String label, int value) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: label,
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
            TextSpan(
              text: '$value',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _myPlayersTab(SavedGameData data) {
    final myTeamIds = data.teams
        .where((t) => t.ownerAccountId == data.activeAccountId && !t.isDeleted)
        .expand((t) => t.playerIds)
        .toSet();
    final myPlayers =
        data.players.where((p) => myTeamIds.contains(p.id)).toList()
          ..sort((a, b) => b.points.compareTo(a.points));

    if (myPlayers.isEmpty) {
      return const Center(
        child: Text(
          'Oyuncu bulunamadi.',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: myPlayers.length,
      itemBuilder: (ctx, index) {
        final p = myPlayers[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.isInjured
                ? Colors.red.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          '#${p.number ?? index + 1} ',
                          style: const TextStyle(color: Colors.white54),
                        ),
                        Expanded(
                          child: Text(
                            p.name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xffffd34d).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'OVR ${p.overallRating.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Color(0xffffd34d),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.cyan.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'ZK ${p.zekaGucu.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Colors.cyanAccent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _statChip('Gol', p.goals),
                  _statChip('Asist', p.assists),
                  _statChip(
                    'Pas %',
                    p.passes > 0 ? (p.successfulPasses * 100 ~/ p.passes) : 0,
                  ),
                  _statChip('Sut', p.shots),
                  _statChip('Kurtaris', p.saves),
                  _statChip('Top', p.clearances + p.tackles),
                  _statChip('Puan', p.points.toInt()),
                  _statChip('Mac', p.matchesPlayed),
                ],
              ),
              if (p.isInjured)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Sakatlik: ${p.injuredDaysRemaining} gun kaldi',
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _statChip(String label, int value) {
    return Text(
      '$label: $value',
      style: const TextStyle(fontSize: 11, color: Colors.white60),
    );
  }

  Widget _allTeamsTab(SavedGameData data) {
    final activeTeams = data.teams.where((t) => !t.isDeleted).toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: activeTeams.length,
      itemBuilder: (ctx, index) {
        final team = activeTeams[index];
        final ownerAccount = data.accounts
            .where((a) => a.id == team.ownerAccountId)
            .toList();
        final ownerName = ownerAccount.isEmpty
            ? 'Sahipsiz'
            : ownerAccount.first.username;

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${index + 1}. ',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: index == 0
                          ? const Color(0xffffd34d)
                          : Colors.white60,
                      fontSize: 16,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      team.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xffffd34d).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${team.rating.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xffffd34d),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    '$ownerName',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    'G:${team.wins} B:${team.draws} M:${team.losses} O:${team.played}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
              if (team.matchHistory.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  team.matchHistory
                      .take(3)
                      .map((r) => r.scoreText)
                      .join('  |  '),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
