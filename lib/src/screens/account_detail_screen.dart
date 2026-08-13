import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/enums/ai_play_style.dart';
import '../game/enums/team_id.dart';
import '../game/models/formation.dart';
import '../game/models/match_event.dart';
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
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
            Tab(text: 'Mac Arsivi'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Ara',
                isDense: true,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _myTeamsTab(data),
                _myPlayersTab(data),
                _allTeamsTab(data),
                _matchHistoryTab(data),
              ],
            ),
          ),
        ],
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
    if (!data.adminLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('افتح لوحة الإدارة وسجّل دخول المدير أولاً'),
        ),
      );
      return;
    }
    final teams = data.teams.where((team) => !team.isDeleted).toList();
    if (teams.isEmpty) return;
    var selectedTeamId = teams.first.id;
    var adminSearch = '';
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final team = teams.firstWhere((item) => item.id == selectedTeamId);
          final players = data.players
              .where(
                (player) =>
                    team.playerIds.contains(player.id) &&
                    (adminSearch.isEmpty ||
                        player.name.toLowerCase().contains(adminSearch)),
              )
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
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'ابحث عن لاعب في الفريق',
                      isDense: true,
                    ),
                    onChanged: (value) => setDialogState(
                      () => adminSearch = value.trim().toLowerCase(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final player in players)
                          ListTile(
                            title: Text(player.name),
                            subtitle: Text(
                              'تسديد ${player.shootingRating.toStringAsFixed(0)}'
                              ' | تمرير ${player.passingRating.toStringAsFixed(0)}'
                              ' | سرعة ${player.speedRating.toStringAsFixed(0)}'
                              ' | طاقة ${player.staminaRating.toStringAsFixed(0)}',
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
          title: Text('تعديل ${player.name}'),
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
                  _adminEditorSlider('إنهاء الهجمة', player.finishingRating, (v) {
                    setDialogState(() => player.finishingRating = v);
                  }),
                  _adminEditorSlider('قوة التسديد', player.shotPowerRating, (v) {
                    setDialogState(() => player.shotPowerRating = v);
                  }),
                  _adminEditorSlider('التسديد البعيد', player.longShotsRating, (v) {
                    setDialogState(() => player.longShotsRating = v);
                  }),
                  _adminEditorSlider('الانحناء', player.curveRating, (v) {
                    setDialogState(() => player.curveRating = v);
                  }),
                  _adminEditorSlider('الهدوء', player.composureRating, (v) {
                    setDialogState(() => player.composureRating = v);
                  }),
                  _adminEditorSlider('التوازن', player.balanceRating, (v) {
                    setDialogState(() => player.balanceRating = v);
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
                  if (player.isGoalkeeper) ...[
                    _adminEditorSlider('رد الفعل', player.goalkeeperReactionRating, (v) {
                      setDialogState(() => player.goalkeeperReactionRating = v);
                    }),
                    _adminEditorSlider('التمركز', player.goalkeeperPositioningRating, (v) {
                      setDialogState(() => player.goalkeeperPositioningRating = v);
                    }),
                    _adminEditorSlider('الارتماء', player.goalkeeperDivingRating, (v) {
                      setDialogState(() => player.goalkeeperDivingRating = v);
                    }),
                    _adminEditorSlider('التعامل', player.goalkeeperHandlingRating, (v) {
                      setDialogState(() => player.goalkeeperHandlingRating = v);
                    }),
                    _adminEditorSlider('الإمساك', player.goalkeeperCatchingRating, (v) {
                      setDialogState(() => player.goalkeeperCatchingRating = v);
                    }),
                    _adminEditorSlider('القفز', player.goalkeeperJumpingRating, (v) {
                      setDialogState(() => player.goalkeeperJumpingRating = v);
                    }),
                    _adminEditorSlider('القرار', player.goalkeeperDecisionRating, (v) {
                      setDialogState(() => player.goalkeeperDecisionRating = v);
                    }),
                    _adminEditorSlider('واحد ضد واحد', player.goalkeeperOneVsOneRating, (v) {
                      setDialogState(() => player.goalkeeperOneVsOneRating = v);
                    }),
                    _adminEditorSlider('الكرات العالية', player.goalkeeperHighBallsRating, (v) {
                      setDialogState(() => player.goalkeeperHighBallsRating = v);
                    }),
                    _adminEditorSlider('مدى الوصول', player.goalkeeperReachRating, (v) {
                      setDialogState(() => player.goalkeeperReachRating = v);
                    }),
                    _adminEditorSlider('التوقع', player.goalkeeperAnticipationRating, (v) {
                      setDialogState(() => player.goalkeeperAnticipationRating = v);
                    }),
                    _adminEditorSlider('الإبعاد', player.goalkeeperParryingRating, (v) {
                      setDialogState(() => player.goalkeeperParryingRating = v);
                    }),
                    _adminEditorSlider('التوزيع', player.goalkeeperDistributionRating, (v) {
                      setDialogState(() => player.goalkeeperDistributionRating = v);
                    }),
                  ],
                  _adminEditorSlider(
                    'قوة التحمّل Dayaniklilik',
                    player.dayaniklilikGucu,
                    (v) {
                      setDialogState(() => player.dayaniklilikGucu = v);
                    },
                  ),
                  _adminEditorSlider('قوة الذكاء', player.zekaGucu, (v) {
                    setDialogState(() => player.zekaGucu = v);
                  }),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('عقوبة إيقاف بالمباريات'),
                    subtitle: Text(
                      'بطاقات: ${player.yellowCards} صفراء، ${player.redCards} حمراء',
                    ),
                    trailing: DropdownButton<int>(
                      value: player.suspendedMatchesRemaining.clamp(0, 20).toInt(),
                      items: [
                        for (var matches = 0; matches <= 20; matches++)
                          DropdownMenuItem(
                            value: matches,
                            child: Text('$matches'),
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
                  ),
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
    final query = _searchQuery.trim().toLowerCase();
    final myTeams = data.teams
        .where(
          (team) =>
              team.ownerAccountId == data.activeAccountId &&
              !team.isDeleted &&
              (query.isEmpty ||
                  team.name.toLowerCase().contains(query) ||
                  data.players.any((player) =>
                      team.playerIds.contains(player.id) &&
                      player.name.toLowerCase().contains(query))),
        )
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
                  team.rating.toStringAsFixed(0),
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
                        color: r.result.startsWith('G')
                            ? Colors.greenAccent
                            : r.result.startsWith('M')
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
    final query = _searchQuery.trim().toLowerCase();
    final myPlayers = data.players
        .where(
          (player) =>
              myTeamIds.contains(player.id) &&
              (query.isEmpty ||
                  player.name.toLowerCase().contains(query) ||
                  (player.number?.toString().contains(query) ?? false)),
        )
        .toList()
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
            color: p.isUnavailable
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
                  _statChip('Dayaniklilik', p.dayaniklilikGucu.round()),
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
              if (p.isSuspended)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Mac cezasi: ${p.suspendedMatchesRemaining} mac kaldi',
                    style: const TextStyle(
                      color: Colors.orangeAccent,
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
    final query = _searchQuery.trim().toLowerCase();
    final activeTeams = data.teams
        .where(
          (team) =>
              !team.isDeleted &&
              (query.isEmpty || team.name.toLowerCase().contains(query)),
        )
        .toList()
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
                      team.rating.toStringAsFixed(0),
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
                    ownerName,
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

  Widget _matchHistoryTab(SavedGameData data) {
    final query = _searchQuery.trim().toLowerCase();
    final matches = data.matchArchive.where((match) {
      if (query.isEmpty) return true;
      return match.blueName.toLowerCase().contains(query) ||
          match.redName.toLowerCase().contains(query) ||
          '${match.blueScore}-${match.redScore}'.contains(query) ||
          _archiveDate(match.timestamp).toLowerCase().contains(query) ||
          match.goals.any(
            (goal) => goal.scorerName.toLowerCase().contains(query),
          ) ||
          match.playerStats.any(
            (player) => player.name.toLowerCase().contains(query),
          );
    }).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (matches.isEmpty) {
      return const Center(
        child: Text(
          'Arama ile eslesen kayitli mac bulunamadi.',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final match = matches[index];
        final scorers = match.goals
            .map(
              (goal) =>
                  '${goal.scorerName} ${goal.minute}\'${goal.isPenalty ? ' (P)' : ''}${goal.assisterName == null ? '' : ' (A: ${goal.assisterName})'}',
            )
            .join(' • ');
        return Card(
          color: const Color(0xff0d1a16),
          margin: const EdgeInsets.only(bottom: 9),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Container(
                  width: 72,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xffffd34d).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${match.blueScore} - ${match.redScore}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xffffd34d),
                        ),
                      ),
                      Text(
                        _archiveDate(match.timestamp),
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${match.blueName}  —  ${match.redName}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        scorers.isEmpty ? 'Gol kaydi yok' : scorers,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Topla oynama %${match.bluePossessionPercent.round()}-%${match.redPossessionPercent.round()}  •  Sut ${match.blueShots}-${match.redShots}  •  Oyuncu kaydi ${match.playerStats.length}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _showArchivedMatch(match),
                  icon: const Icon(Icons.analytics_outlined, size: 18),
                  label: const Text('Detaylar'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _archiveDate(int timestamp) {
    if (timestamp <= 0) return 'Eski kayit';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year} ${two(date.hour)}:${two(date.minute)}';
  }

  Future<void> _showArchivedMatch(FinishedMatchSummary match) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xff08140f),
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 1040,
          height: 720,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xff103d2d), Color(0xff111b22)],
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.sports_soccer,
                      color: Color(0xffffd34d),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${match.blueName}  ${match.blueScore} - ${match.redScore}  ${match.redName}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Text(
                      _archiveDate(match.timestamp),
                      style: const TextStyle(color: Colors.white54),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              if (match.goals.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  color: Colors.white.withValues(alpha: 0.035),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      for (final goal in match.goals)
                        Chip(
                          avatar: Icon(
                            Icons.sports_soccer,
                            size: 16,
                            color: goal.teamId == TeamId.blue
                                ? Colors.lightBlueAccent
                                : Colors.redAccent,
                          ),
                          label: Text(
                            '${goal.minute}\' ${goal.scorerName}${goal.isPenalty ? ' (Penalti)' : ''}${goal.assisterName == null ? '' : ' • Asist: ${goal.assisterName}'}',
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _archiveTeamPanel(
                        match,
                        TeamId.blue,
                        match.blueName,
                        Colors.lightBlueAccent,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _archiveTeamPanel(
                        match,
                        TeamId.red,
                        match.redName,
                        Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _archiveTeamPanel(
    FinishedMatchSummary match,
    TeamId teamId,
    String teamName,
    Color color,
  ) {
    final players = match.playerStats
        .where((player) => player.teamId == teamId)
        .toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));
    final isBlue = teamId == TeamId.blue;
    final passes = isBlue ? match.bluePasses : match.redPasses;
    final successful = isBlue
        ? match.blueSuccessfulPasses
        : match.redSuccessfulPasses;
    final possession = isBlue
        ? match.bluePossessionPercent
        : match.redPossessionPercent;
    final shots = isBlue ? match.blueShots : match.redShots;
    final tackles = players.fold<int>(0, (sum, player) => sum + player.tackles);
    final saves = players.fold<int>(0, (sum, player) => sum + player.saves);
    final fouls = players.fold<int>(
      0,
      (sum, player) => sum + player.foulsCommitted,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(
                teamName,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 9,
                runSpacing: 5,
                children: [
                  _archiveTotal('Topla oynama', '%${possession.round()}'),
                  _archiveTotal(
                    'Pas',
                    '$successful/$passes (%${passes == 0 ? 0 : successful * 100 ~/ passes})',
                  ),
                  _archiveTotal('Sut', '$shots'),
                  _archiveTotal('Mudahale', '$tackles'),
                  _archiveTotal('Kurtaris', '$saves'),
                  _archiveTotal('Faul', '$fouls'),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: players.isEmpty
              ? const Center(
                  child: Text(
                    'Bu eski kayitta oyuncu detayi yok.',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
                  itemCount: players.length,
                  itemBuilder: (context, index) {
                    final player = players[index];
                    return ExpansionTile(
                      dense: true,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: CircleAvatar(
                        radius: 17,
                        backgroundColor: color.withValues(alpha: 0.16),
                        child: Text(
                          '${player.number}',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      title: Text(
                        player.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${player.role} • ${player.minutes} dk • ${player.goals} gol • ${player.assists} asist',
                        style: const TextStyle(fontSize: 10),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          player.rating.toStringAsFixed(1),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _archiveTotal('Gol', '${player.goals}'),
                              _archiveTotal('Asist', '${player.assists}'),
                              _archiveTotal(
                                'Pas',
                                '${player.successfulPasses}/${player.passes}',
                              ),
                              _archiveTotal(
                                'Dripling',
                                '${player.successfulDribbles}/${player.dribbles}',
                              ),
                              _archiveTotal('Mudahale', '${player.tackles}'),
                              _archiveTotal(
                                'Sut',
                                '${player.shotsOnTarget}/${player.shots}',
                              ),
                              _archiveTotal(
                                'Kacan firsat',
                                '${player.missedChances}',
                              ),
                              _archiveTotal('Uzaklastirma', '${player.clearances}'),
                              _archiveTotal('Kurtaris', '${player.saves}'),
                              _archiveTotal(
                                'Yaptigi faul',
                                '${player.foulsCommitted}',
                              ),
                              _archiveTotal(
                                'Aldigi faul',
                                '${player.foulsReceived}',
                              ),
                              _archiveTotal('Sari', '${player.yellowCards}'),
                              _archiveTotal('Kirmizi', '${player.redCards}'),
                              _archiveTotal(
                                'Enerji',
                                '%${player.staminaPercent}',
                              ),
                              _archiveTotal(
                                'Sakat',
                                player.injured ? 'Evet' : 'Hayir',
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _archiveTotal(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 10, color: Colors.white70),
      ),
    );
  }

}
