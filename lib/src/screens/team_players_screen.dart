import 'package:flutter/material.dart';

import '../game/enums/player_role.dart';
import '../game/models/player_profile.dart';
import '../game/models/shooting.dart';
import '../game/models/team_profile.dart';
import '../storage/roster_storage.dart';
import '../game/models/jersey_kit.dart';

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

/// Sort keys of the players page (مطلب الفرز الكامل: القيمة، معدل النقاط،
/// الأهداف، السرعة، الإنهاء...).
enum _PlayerSort {
  name('الاسم'),
  number('الرقم'),
  marketValue('القيمة السوقية'),
  averagePoints('معدل النقاط'),
  totalPoints('مجموع النقاط'),
  goals('الأهداف'),
  assists('الصناعة'),
  overall('التقييم العام'),
  speed('السرعة'),
  finishing('الإنهاء'),
  shotPower('قوة التسديد'),
  successfulPasses('التمريرات الناجحة'),
  matchesPlayed('المباريات'),
  stamina('التحمل'),
  zeka('الذكاء');

  const _PlayerSort(this.label);

  final String label;

  /// Numeric comparison value used by the roster sort. The [name] key is
  /// handled with a string comparison by the caller before reaching here.
  double valueOf(PlayerProfile player) => switch (this) {
    _PlayerSort.number => (player.number ?? 99).toDouble(),
    _PlayerSort.marketValue => player.marketValue,
    _PlayerSort.averagePoints => player.matchesPlayed == 0
        ? 0.0
        : player.points / player.matchesPlayed,
    _PlayerSort.totalPoints => player.points,
    _PlayerSort.goals => player.goals.toDouble(),
    _PlayerSort.assists => player.assists.toDouble(),
    _PlayerSort.overall => player.effectiveOverall,
    _PlayerSort.speed => player.speedRating,
    _PlayerSort.finishing => player.finishingRating,
    _PlayerSort.shotPower => player.shotPowerRating,
    _PlayerSort.successfulPasses => player.successfulPasses.toDouble(),
    _PlayerSort.matchesPlayed => player.matchesPlayed.toDouble(),
    _PlayerSort.stamina => player.staminaRating,
    _PlayerSort.zeka => player.zekaGucu,
    _PlayerSort.name => 0,
  };
}

class _TeamPlayersScreenState extends State<TeamPlayersScreen> {
  final RosterStorage _storage = RosterStorage();
  SavedGameData? _data;
  bool _loading = true;
  String _selectedTeamId = '';
  String _search = '';
  String _addPlayerId = '';
  _PlayerSort _sortKey = _PlayerSort.name;
  bool _sortAscending = true;

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
                _sortBar(),
                const Divider(height: 1),
                Expanded(child: _playerList(data, team)),
              ],
            ),
    );
  }

  Future<void> _openKitsManager(SavedTeamProfile team) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _KitsManagerDialog(team: team, onSaved: _save),
    );
    if (mounted) setState(() {});
  }

  Widget _sortBar() {
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: _PlayerSort.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final key = _PlayerSort.values[index];
                final selected = key == _sortKey;
                return ChoiceChip(
                  label: Text(key.label),
                  selected: selected,
                  onSelected: (_) => setState(() {
                    if (_sortKey == key) {
                      _sortAscending = !_sortAscending;
                    } else {
                      _sortKey = key;
                      _sortAscending = false;
                    }
                  }),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: _sortAscending ? 'تصاعدي' : 'تنازلي',
            onPressed: () => setState(() => _sortAscending = !_sortAscending),
            icon: Icon(
              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  double _teamTotalValue(List<PlayerProfile> players) {
    var total = 0.0;
    for (final player in players) {
      total += player.marketValue;
    }
    return total;
  }

  String _teamFormText(SavedTeamProfile team) {
    // matchHistory is newest-first; results start with G (win), B (draw)
    // or M (loss).
    final recent = team.matchHistory.take(5).toList();
    if (recent.isEmpty) {
      return 'لا توجد مباريات بعد';
    }
    var streakType = '';
    var streak = 0;
    for (final record in recent) {
      final kind = record.result.isEmpty ? '' : record.result[0];
      if (streakType.isEmpty) {
        streakType = kind;
        streak = 1;
      } else if (kind == streakType) {
        streak++;
      } else {
        break;
      }
    }
    final streakText = switch (streakType) {
      'G' => streak >= 2 ? ' • $streak فوز متتالي' : '',
      'M' => streak >= 2 ? ' • $streak خسائر متتالية' : '',
      'B' => streak >= 2 ? ' • $streak تعادلات متتالية' : '',
      _ => '',
    };
    final badges = recent.map((record) {
      final kind = record.result.isEmpty ? '' : record.result[0];
      return switch (kind) {
        'G' => 'ف',
        'B' => 'ت',
        'M' => 'خ',
        _ => '؟',
      };
    }).join('-');
    return 'آخر النتائج: $badges$streakText';
  }

  String _formatBigValue(double value) {
    if (value >= 1e9) {
      final b = value / 1e9;
      return b >= 100
          ? b.toStringAsFixed(0) + ' مليار'
          : b.toStringAsFixed(1) + ' مليار';
    }
    if (value >= 1e6) {
      return (value / 1e6).toStringAsFixed(0) + ' مليون';
    }
    return value.toStringAsFixed(0);
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
    final totalValue = _teamTotalValue(players);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xff0d1a16),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xffffd34d).withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield, color: Color(0xffffd34d)),
              const SizedBox(width: 10),
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  value: team.id,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'اختر الفريق'),
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'اللاعبون: ${players.length} (حراس $keepers، أرضية $fielders) • '
                    'ف${team.wins} ت${team.draws} خ${team.losses}',
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 12),
                  ),
                  Text(
                    'المالك: ${owner.isEmpty ? 'غير محدد' : owner.first.username}'
                    '${team.country == 'غير محدد' ? '' : ' • ${team.country}'}',
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              // Total value badge (مطلب: مجموع قيم اللاعبين على الفريق).
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xff134e2c), Color(0xff0d3b22)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xffffd34d).withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  children: [
                    const Text(
                      'قيمة الفريق',
                      style: TextStyle(fontSize: 10, color: Colors.white60),
                    ),
                    Text(
                      _formatBigValue(totalValue),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xffffd34d),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.adminFullAccess) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => _deleteTeam(team),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('حذف الفريق'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(
                      color: Colors.redAccent.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          // Form + history summary (مطلب: الفريق يظهر نتيجة آخر مباراة أو
          // سلسلة انتصارات، وبالضغط تظهر كل نتائجه).
          Row(
            children: [
              Text(
                _teamFormText(team),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (team.matchHistory.isNotEmpty) ...[
                TextButton(
                  onPressed: () => _showTeamHistory(team),
                  child: const Text(
                    'عرض كل النتائج',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
              TextButton.icon(
                onPressed: () => _openKitsManager(team),
                icon: const Icon(Icons.checkroom, size: 15),
                label: const Text(
                  'الأطقم',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              if (widget.adminFullAccess)
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    value: _data!.countries.contains(team.country)
                        ? team.country
                        : null,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'دولة الفريق',
                      isDense: true,
                    ),
                    items: [
                      for (final country in _data!.countries)
                        DropdownMenuItem(
                          value: country,
                          child: Text(country, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => team.country = value);
                      _save();
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showTeamHistory(SavedTeamProfile team) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff102019),
        title: Text('نتائج ${team.name}'),
        content: SizedBox(
          width: 460,
          child: team.matchHistory.isEmpty
              ? const Text('لا توجد مباريات مسجلة')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: team.matchHistory.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final record = team.matchHistory[index];
                    final color = record.result.startsWith('G')
                        ? Colors.greenAccent
                        : record.result.startsWith('M')
                            ? Colors.redAccent
                            : Colors.white60;
                    return ListTile(
                      dense: true,
                      leading: Text(
                        record.result,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      title: Text(
                        '${record.scoreText} ضد ${record.opponentName}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        'استحواذ ${record.possessionPercent.toStringAsFixed(0)}% • '
                        'تمرير ${record.successfulPasses}/${record.passes} • '
                        'تسديد ${record.shots}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
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
        int cmp;
        if (_sortKey == _PlayerSort.name) {
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          if (cmp == 0) {
            cmp = (a.number ?? 0).compareTo(b.number ?? 0);
          }
        } else {
          cmp = _sortKey.valueOf(a).compareTo(_sortKey.valueOf(b));
          if (cmp == 0) {
            cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
        }
        return _sortAscending ? cmp : -cmp;
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
    final avgPoints =
        player.matchesPlayed == 0 ? 0.0 : player.points / player.matchesPlayed;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openPlayerDetailSheet(data, team, player),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xff10231b),
              const Color(0xff0d1a16),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isStarter
                ? const Color(0xffffd34d).withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            // Number avatar
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xffffd34d).withValues(alpha: 0.12),
                border: Border.all(
                  color: const Color(0xffffd34d).withValues(alpha: 0.45),
                ),
              ),
              child: Text(
                '${player.number ?? '-'}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Color(0xffffd34d),
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
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'OVR ${player.effectiveOverall.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      if (player.country != 'غير محدد') ...[
                        const SizedBox(width: 4),
                        Text(
                          player.country,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${role?.turkishName ?? 'بلا مركز'}'
                    '${isStarter ? ' • أساسي' : ' • بديل'}'
                    '${player.isSuspended ? ' • موقوف ${player.suspendedMatchesRemaining}م' : ''}'
                    '${player.isInjured ? ' • مصاب ${player.injuredDaysRemaining}ي' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _miniStat('قيمة', player.marketValueText),
                      _miniStat('أهداف', '${player.goals}'),
                      _miniStat('صناعة', '${player.assists}'),
                      _miniStat('معدل النقاط', avgPoints.toStringAsFixed(2)),
                      _miniStat('سرعة', player.speedRating.toStringAsFixed(0)),
                      _miniStat(
                          'إنهاء', player.finishingRating.toStringAsFixed(0)),
                    ],
                  ),
                ],
              ),
            ),
            if (widget.adminFullAccess)
              IconButton(
                tooltip: 'تعديل القيم والإعدادات',
                onPressed: () => _editPlayerValues(player),
                icon: const Icon(Icons.tune, color: Color(0xffffd34d)),
              ),
            IconButton(
              tooltip: 'تعديل الاسم',
              onPressed: canEdit ? () => _editPlayerName(player) : null,
              icon: const Icon(Icons.edit, size: 20),
            ),
            IconButton(
              tooltip: 'تعديل الرقم',
              onPressed: canEdit ? () => _editPlayerNumber(player) : null,
              icon: const Icon(Icons.tag, size: 20),
            ),
            IconButton(
              tooltip: 'إخراج من الفريق',
              onPressed: canEdit
                  ? () => _removePlayerFromTeam(data, team, player)
                  : null,
              icon: const Icon(Icons.person_remove_outlined, size: 20),
            ),
            if (widget.adminFullAccess)
              IconButton(
                tooltip: 'حذف اللاعب (الإدارة فقط)',
                onPressed: () => _deletePlayer(player),
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xff9fe8bd),
            ),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  /// Full player detail sheet: every goal and assist, match-by-match points,
  /// which matches he stood out in (مطلب صفحة تفاصيل اللاعب).
  Future<void> _openPlayerDetailSheet(
    SavedGameData data,
    SavedTeamProfile team,
    PlayerProfile player,
  ) async {
    final avgPoints =
        player.matchesPlayed == 0 ? 0.0 : player.points / player.matchesPlayed;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xff0c1a14),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          maxChildSize: 0.95,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor:
                        const Color(0xffffd34d).withValues(alpha: 0.15),
                    child: Text(
                      '${player.number ?? '-'}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xffffd34d),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          player.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${team.name} • ${player.country} • '
                          'مباريات ${player.matchesPlayed} • دقائق '
                          '${player.minutesPlayed}',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _detailChip('OVR', player.effectiveOverall.toStringAsFixed(0)),
                  _detailChip('القيمة', player.marketValueText),
                  _detailChip('أهداف', '${player.goals}'),
                  _detailChip('صناعة', '${player.assists}'),
                  _detailChip('معدل النقاط', avgPoints.toStringAsFixed(2)),
                  _detailChip('مجموع النقاط', player.points.toStringAsFixed(1)),
                  _detailChip('تسديد', '${player.shots}'),
                  _detailChip('على المرمى', '${player.shotsOnTarget}'),
                  _detailChip('تمرير ناجح', '${player.successfulPasses}'),
                  _detailChip('مراوغات', '${player.successfulDribbles}'),
                  _detailChip('قطع', '${player.tackles}'),
                  _detailChip('إنقاذ', '${player.saves}'),
                  _detailChip('بطاقات', 'ص${player.yellowCards} ح${player.redCards}'),
                ],
              ),
              const SizedBox(height: 14),
              if (widget.adminFullAccess) ...[
                Row(
                  children: [
                    const Text('الجنسية:',
                        style: TextStyle(color: Colors.white70)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _data!.countries.contains(player.country)
                            ? player.country
                            : _data!.countries.isNotEmpty
                                ? _data!.countries.first
                                : null,
                        isDense: true,
                        items: [
                          for (final country in _data!.countries)
                            DropdownMenuItem(
                              value: country,
                              child: Text(country),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => player.country = value);
                            _save();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _addCountryDialog(),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('دولة جديدة'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _assignAsGoalkeeper(team, player),
                    icon: const Icon(Icons.back_hand, size: 16),
                    label: Text(
                      player.isGoalkeeper
                          ? 'تحويله لاعب أرضية'
                          : 'تعيينه حارساً للمرمى',
                    ),
                  ),
                ),
                const Divider(height: 22),
              ],
              const Text(
                'سجل المباريات — نقطة بنقطة',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              if (player.matchHistory.isEmpty)
                const Text(
                  'لم يلعب مباريات بعد.',
                  style: TextStyle(color: Colors.white38),
                )
              else
                ...player.matchHistory.map((record) {
                  final standout = record.rating >= avgPoints + 1.0 &&
                      record.rating >= 7.0;
                  final ratingColor = record.rating >= 7.5
                      ? const Color(0xff7bffb0)
                      : record.rating >= 6.0
                          ? const Color(0xffffd34d)
                          : const Color(0xffff8b8b);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: standout
                          ? Border.all(
                              color: const Color(0xff7bffb0)
                                  .withValues(alpha: 0.4))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: ratingColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            record.rating.toStringAsFixed(1),
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: ratingColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${record.scoreText} ضد ${record.opponentName} • '
                                '${record.minutes} دقيقة'
                                '${standout ? '  ⭐ مباراة مميزة' : ''}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12),
                              ),
                              Text(
                                'أهداف ${record.goals} • صناعة ${record.assists} • '
                                'تمرير ${record.successfulPasses}/${record.passes} • '
                                'تسديد ${record.shotsOnTarget}/${record.shots} • '
                                'قطع ${record.tackles} • إنقاذ ${record.saves}'
                                '${record.yellowCards > 0 ? ' • صفراء ${record.yellowCards}' : ''}'
                                '${record.redCards > 0 ? ' • حمراء ${record.redCards}' : ''}'
                                '${record.injured ? ' • مصاب' : ''}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _detailChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: Color(0xff9fe8bd),
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Future<void> _addCountryDialog() async {
    final data = _data;
    if (data == null) return;
    final controller = TextEditingController();
    final country = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff102019),
        title: const Text('إضافة دولة'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'اسم الدولة'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    if (country == null || country.trim().isEmpty || !mounted) return;
    setState(() {
      if (!data.countries.contains(country.trim())) {
        data.countries.add(country.trim());
      }
    });
    await _save();
  }

  /// Gives a field player the goalkeeper job (مطلب: تعيين حارس بديل عند
  /// إصابة الحارس أو طرده) — the current keeper moves to a field role.
  Future<void> _assignAsGoalkeeper(
    SavedTeamProfile team,
    PlayerProfile player,
  ) async {
    if (!widget.adminFullAccess) {
      _showMessage('تعيين الحارس متاح للإدارة فقط');
      return;
    }
    setState(() {
      if (player.isGoalkeeper) {
        team.roleByPlayerId[player.id] = PlayerRole.midfieldLeft;
      } else {
        for (final entry in team.roleByPlayerId.entries) {
          if (entry.value == PlayerRole.goalkeeper) {
            team.roleByPlayerId[entry.key] = PlayerRole.midfieldLeft;
          }
        }
        team.roleByPlayerId[player.id] = PlayerRole.goalkeeper;
      }
    });
    await _save();
    if (mounted) {
      Navigator.of(context).pop();
      _showMessage('تم تحديث مركز الحارس');
    }
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
    // حذف اللاعب متاح فقط لحساب الإدارة (مطلب صريح).
    if (!widget.adminFullAccess) {
      _showMessage('حذف اللاعب متاح فقط من حساب الإدارة');
      return;
    }
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
    // حذف الفريق متاح فقط لحساب الإدارة (مطلب صريح).
    if (!widget.adminFullAccess) {
      _showMessage('حذف الفريق متاح فقط من حساب الإدارة');
      return;
    }
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


/// Kits manager: choose one of the club kits or build a custom one with
/// per-part colors (مطلب: قمصان أكثر بألوان مخصصة لكل فريق).
class _KitsManagerDialog extends StatefulWidget {
  const _KitsManagerDialog({required this.team, required this.onSaved});

  final SavedTeamProfile team;
  final Future<void> Function() onSaved;

  @override
  State<_KitsManagerDialog> createState() => _KitsManagerDialogState();
}

class _KitsManagerDialogState extends State<_KitsManagerDialog> {
  static const List<Color> _palette = [
    Color(0xffe53935),
    Color(0xffc1272d),
    Color(0xff8a1538),
    Color(0xffff7f00),
    Color(0xffffd700),
    Color(0xff006c35),
    Color(0xff2ecc71),
    Color(0xff75aadb),
    Color(0xff21304d),
    Color(0xff6a0dad),
    Color(0xffff6fa5),
    Color(0xff16a085),
    Color(0xffffffff),
    Color(0xff2c2c2c),
    Color(0xff000000),
  ];

  @override
  Widget build(BuildContext context) {
    final team = widget.team;
    final kits = team.jerseyKits;
    return AlertDialog(
      backgroundColor: const Color(0xff0c1a14),
      title: Text('أطقم ${team.name}'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < kits.length; i++)
                      _kitTile(kits[i], i, active: team.activeKitIndex == i),
                  ],
                ),
              ),
            ),
            const Divider(height: 24),
            FilledButton.tonalIcon(
              onPressed: _createCustomKit,
              icon: const Icon(Icons.palette),
              label: const Text('إنشاء طقم مخصص'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }

  Widget _kitTile(JerseyKit kit, int index, {required bool active}) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        setState(() => widget.team.activeKitIndex = index);
        widget.onSaved();
      },
      child: Container(
        width: 108,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? const Color(0xffffd34d) : Colors.white24,
            width: active ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            // Mini jersey preview
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: kit.shirtColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
                border: Border.all(color: Colors.white24),
              ),
              alignment: Alignment.center,
              child: Text(
                '10',
                style: TextStyle(
                  color: kit.numberColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Container(
              width: 40,
              height: 10,
              decoration: BoxDecoration(
                color: kit.shortsColor,
                border: Border.all(color: Colors.white24),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              kit.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createCustomKit() async {
    final team = widget.team;
    var shirt = const Color(0xff21304d);
    var shorts = const Color(0xffffffff);
    var socks = const Color(0xff21304d);
    var number = const Color(0xffffffff);
    var keeper = const Color(0xff2ecc71);
    final nameController = TextEditingController(text: 'طقم مخصص');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xff102019),
          title: const Text('طقم مخصص'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'اسم الطقم'),
                  ),
                  const SizedBox(height: 10),
                  _colorRow('القميص', shirt, (c) => shirt = c,
                      setDialogState),
                  _colorRow('الشورت', shorts, (c) => shorts = c,
                      setDialogState),
                  _colorRow('الشراب', socks, (c) => socks = c, setDialogState),
                  _colorRow('الرقم', number, (c) => number = c,
                      setDialogState),
                  _colorRow('قميص الحارس', keeper, (c) => keeper = c,
                      setDialogState),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('حفظ الطقم'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    setState(() {
      widget.team.jerseyKits = [
        ...widget.team.jerseyKits,
        JerseyKit(
          name: nameController.text.trim().isEmpty
              ? 'طقم مخصص'
              : nameController.text.trim(),
          shirtColor: shirt,
          shortsColor: shorts,
          socksColor: socks,
          numberColor: number,
          goalkeeperShirtColor: keeper,
        ),
      ];
      widget.team.activeKitIndex = widget.team.jerseyKits.length - 1;
    });
    await widget.onSaved();
  }

  Widget _colorRow(
    String label,
    Color current,
    ValueChanged<Color> onPick,
    void Function(void Function()) setDialogState,
  ) {
    return Row(
      children: [
        SizedBox(width: 96, child: Text(label)),
        Expanded(
          child: Wrap(
            spacing: 4,
            children: [
              for (final color in _palette)
                GestureDetector(
                  onTap: () => setDialogState(() => onPick(color)),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: current == color
                            ? const Color(0xffffd34d)
                            : Colors.white24,
                        width: current == color ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
