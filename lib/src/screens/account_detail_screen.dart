import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
    return Scaffold(
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
    // Oyuncular isme gore siralanir; guc/puan degisince sira kaymaz.
    final myPlayers =
        data.players.where((p) => myTeamIds.contains(p.id)).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

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
