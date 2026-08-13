import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/enums/ai_play_style.dart';
import '../game/models/formation.dart';
import '../game/models/league.dart';
import '../game/models/match_event.dart';
import '../storage/roster_storage.dart';
import 'game_screen.dart';

class LeagueScreen extends StatefulWidget {
  const LeagueScreen({super.key});

  @override
  State<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends State<LeagueScreen>
    with SingleTickerProviderStateMixin {
  LeagueSeason? _season;
  final RosterStorage _storage = RosterStorage();
  late final TabController _tabController;
  bool _loading = true;
  bool _simulating = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadLeague();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadLeague() async {
    final data = await _storage.load();
    if (!mounted) return;
    setState(() {
      _season = data.leagueSeason ?? LeagueFactory.createDefaultSeason();
      _loading = false;
    });
  }

  Future<void> _saveLeague() async {
    final data = await _storage.load();
    data.leagueSeason = _season;
    await _storage.save(data);
  }

  Future<void> _playCurrentFixture() async {
    final season = _season;
    if (season == null) return;

    final fixture = season.currentFixture;
    if (fixture == null) return;

    final homeTeam = season.teams[fixture.homeIndex];
    final awayTeam = season.teams[fixture.awayIndex];

    final setup = season.createCurrentMatchSetup();
    if (setup == null) return;

    if (!mounted) return;
    final result = await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => GameScreen(setup: setup)));

    if (result is FinishedMatchSummary) {
      final blueScore = result.blueScore;
      final redScore = result.redScore;

      // Get scorers from the summary
      final homeScorers = <String>[];
      final awayScorers = <String>[];

      if (blueScore > 0) {
        for (var i = 0; i < blueScore; i++) {
          homeScorers.add('${homeTeam.name} #${i + 1}');
        }
      }
      if (redScore > 0) {
        for (var i = 0; i < redScore; i++) {
          awayScorers.add('${awayTeam.name} #${i + 1}');
        }
      }

      setState(() {
        season.recordResult(
          fixture,
          blueScore,
          redScore,
          homeScorers,
          awayScorers,
        );
        for (final player in [...homeTeam.players, ...awayTeam.players]) {
          final played = player.matchHistory.any(
            (record) => record.matchId == result.matchId,
          );
          if (!played && player.isUnavailable) {
            player.advanceUnavailableStatusAfterTeamMatch();
          }
        }
      });
      await _saveLeague();
    }
  }

  Future<void> _simulateAll() async {
    final season = _season;
    if (season == null || season.seasonFinished) return;

    setState(() => _simulating = true);
    final rng = math.Random();

    while (!season.seasonFinished) {
      final fixture = season.currentFixture;
      if (fixture == null) break;

      // Quick simulation: random score
      final homeTeam = season.teams[fixture.homeIndex];
      final awayTeam = season.teams[fixture.awayIndex];
      final ratingDiff = (homeTeam.rating - awayTeam.rating) / 10;

      // Simple simulation
      final homeBase = 1.2 + ratingDiff * 0.3;
      final awayBase = 1.0 - ratingDiff * 0.2;

      var homeScore = 0;
      var awayScore = 0;

      for (var i = 0; i < 90; i += 15) {
        if (rng.nextDouble() < (0.09 + homeBase * 0.045).clamp(0.04, 0.34)) {
          homeScore++;
        }
        if (rng.nextDouble() < (0.07 + awayBase * 0.043).clamp(0.03, 0.30)) {
          awayScore++;
        }
      }

      homeScore = homeScore.clamp(0, 6).toInt();
      awayScore = awayScore.clamp(0, 5).toInt();

      final homeScorers = List.generate(homeScore, (i) => 'Golcu #${i + 1}');
      final awayScorers = List.generate(awayScore, (i) => 'Golcu #${i + 1}');

      season.recordResult(
        fixture,
        homeScore,
        awayScore,
        homeScorers,
        awayScorers,
      );
      for (final player in [...homeTeam.players, ...awayTeam.players]) {
        if (player.isUnavailable) {
          player.advanceUnavailableStatusAfterTeamMatch();
        }
      }
    }

    await _saveLeague();
    setState(() => _simulating = false);
  }

  Future<void> _resetSeason() async {
    final season = _season;
    if (season == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ligi Sifirla'),
        content: const Text('Tum maclar ve puan durumu silinecek. Emin misin?'),
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
      _season = LeagueFactory.createDefaultSeason();
    });
    await _saveLeague();
  }

  Future<void> _newSeason() async {
    setState(() {
      _season = LeagueFactory.createDefaultSeason();
    });
    await _saveLeague();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final season = _season!;
    final fixture = season.currentFixture;

    return Scaffold(
      backgroundColor: const Color(0xff08140f),
      appBar: AppBar(
        title: Text(season.name),
        backgroundColor: const Color(0xff0d1a16),
        actions: [
          if (season.seasonFinished)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Yeni Sezon',
              onPressed: _newSeason,
            ),
          if (!season.seasonFinished && !_simulating)
            IconButton(
              icon: const Icon(Icons.fast_forward),
              tooltip: 'Tumunu Simule Et',
              onPressed: _simulateAll,
            ),
          if (season.fixtures.any((f) => f.played))
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Sifirla',
              onPressed: _resetSeason,
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'new') _newSeason();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'new', child: Text('Yeni Sezon')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xffffd34d),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Puan Durumu'),
            Tab(text: 'Fikstur'),
            Tab(text: 'Mac'),
          ],
        ),
      ),
      body: _simulating
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Maclar simule ediliyor...'),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Takim veya fikstur ara',
                      isDense: true,
                    ),
                    onChanged: (value) =>
                        setState(() => _searchQuery = value),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _standingsTab(season),
                      _fixturesTab(season),
                      _matchTab(season, fixture),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _standingsTab(LeagueSeason season) {
    final query = _searchQuery.trim().toLowerCase();
    final sorted = season.sortedStandings
        .where(
          (standing) => query.isEmpty ||
              season.teams[standing.teamIndex].name
                  .toLowerCase()
                  .contains(query),
        )
        .toList();

    return Container(
      color: const Color(0xff08140f),
      child: Column(
        children: [
          if (season.championTeamName != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              color: const Color(0xffffd34d).withValues(alpha: 0.18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.emoji_events, color: Color(0xffffd34d)),
                  const SizedBox(width: 8),
                  Text(
                    'SAMPIYON: ${season.championTeamName}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xffffd34d),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: sorted.length,
              itemBuilder: (ctx, index) {
                final standing = sorted[index];
                final team = season.teams[standing.teamIndex];
                final isChampion = season.seasonFinished && index == 0;
                final isRelegation =
                    season.seasonFinished && index >= sorted.length - 2;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: isChampion
                        ? const Color(0xffffd34d).withValues(alpha: 0.08)
                        : isRelegation
                        ? Colors.red.withValues(alpha: 0.06)
                        : Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isChampion
                          ? const Color(0xffffd34d).withValues(alpha: 0.3)
                          : Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: index == 0
                                  ? const Color(0xffffd34d)
                                  : Colors.white70,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          child: standing.teamIndex < 8
                              ? Icon(
                                  Icons.shield,
                                  size: 20,
                                  color: _teamColor(standing.teamIndex),
                                )
                              : null,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                team.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${team.playStyle.title} • ${team.formation.title.split(' ').first}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _statCell('O', standing.played),
                        _statCell('G', standing.wins),
                        _statCell('B', standing.draws),
                        _statCell('M', standing.losses),
                        _statCell(
                          'A',
                          standing.goalsFor,
                          color: Colors.greenAccent,
                        ),
                        _statCell(
                          'Y',
                          standing.goalsAgainst,
                          color: Colors.redAccent,
                        ),
                        _statCell(
                          'Av',
                          standing.goalDifference,
                          bold: true,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 48,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xffffd34d,
                            ).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${standing.points}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: Color(0xffffd34d),
                            ),
                          ),
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

  Widget _statCell(String label, int value, {bool bold = false, Color? color}) {
    return SizedBox(
      width: 36,
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.white38,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
              color: color ?? Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Color _teamColor(int index) {
    const colors = [
      Color(0xffffd34d),
      Color(0xff0a4f93),
      Color(0xffe74c3c),
      Color(0xff2ecc71),
      Color(0xff9b59b6),
      Color(0xff3498db),
      Color(0xffe67e22),
      Color(0xff1abc9c),
    ];
    return colors[index % colors.length];
  }

  Widget _fixturesTab(LeagueSeason season) {
    final totalMatchdays = (season.teams.length - 1) * 2;

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: totalMatchdays,
      itemBuilder: (ctx, matchdayIndex) {
        final matchday = matchdayIndex + 1;
        final query = _searchQuery.trim().toLowerCase();
        final fixtures = season.matchdayFixtures(matchday).where((fixture) {
          if (query.isEmpty) return true;
          final home = season.teams[fixture.homeIndex].name.toLowerCase();
          final away = season.teams[fixture.awayIndex].name.toLowerCase();
          return home.contains(query) || away.contains(query);
        }).toList();
        if (fixtures.isEmpty) return const SizedBox.shrink();
        final allPlayed = fixtures.every((f) => f.played);
        final isCurrent =
            matchday == season.currentMatchday && !season.seasonFinished;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isCurrent
                ? const Color(0xffffd34d).withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isCurrent
                  ? const Color(0xffffd34d).withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.05),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Row(
                  children: [
                    Text(
                      '$matchday. Hafta',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: isCurrent
                            ? const Color(0xffffd34d)
                            : Colors.white,
                      ),
                    ),
                    const Spacer(),
                    if (allPlayed)
                      const Icon(
                        Icons.check_circle,
                        size: 16,
                        color: Colors.greenAccent,
                      )
                    else if (isCurrent)
                      const Icon(
                        Icons.play_circle_fill,
                        size: 16,
                        color: Color(0xffffd34d),
                      ),
                  ],
                ),
              ),
              ...fixtures.map((f) => _fixtureRow(season, f)),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  Widget _fixtureRow(LeagueSeason season, LeagueFixture f) {
    final home = season.teams[f.homeIndex];
    final away = season.teams[f.awayIndex];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              home.name,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: f.played && (f.homeScore ?? 0) > (f.awayScore ?? 0)
                    ? FontWeight.w800
                    : FontWeight.w500,
                color: f.played && (f.homeScore ?? 0) > (f.awayScore ?? 0)
                    ? Colors.white
                    : Colors.white70,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: f.played
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              f.resultText(season.teams),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: f.played ? Colors.white : Colors.white54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              away.name,
              style: TextStyle(
                fontWeight: f.played && (f.awayScore ?? 0) > (f.homeScore ?? 0)
                    ? FontWeight.w800
                    : FontWeight.w500,
                color: f.played && (f.awayScore ?? 0) > (f.homeScore ?? 0)
                    ? Colors.white
                    : Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _matchTab(LeagueSeason season, LeagueFixture? fixture) {
    if (season.seasonFinished) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events, size: 72, color: Color(0xffffd34d)),
            const SizedBox(height: 16),
            Text(
              'Lig Tamamlandi!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sampiyon: ${season.championTeamName ?? "Belli degil"}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xffffd34d),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _newSeason,
              icon: const Icon(Icons.refresh),
              label: const Text('Yeni Sezon'),
            ),
          ],
        ),
      );
    }

    if (fixture == null) {
      return const Center(child: Text('Fikstur hazirlaniyor...'));
    }

    final home = season.teams[fixture.homeIndex];
    final away = season.teams[fixture.awayIndex];

    return Center(
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${fixture.matchday}. Hafta',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white60,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Icon(
                        Icons.shield,
                        size: 48,
                        color: _teamColor(fixture.homeIndex),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        home.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${home.rating.toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white60),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        home.formation.title.split(' ').first,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white38,
                        ),
                      ),
                      Text(
                        home.playStyle.title,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xffffd34d),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'VS',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white24,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Icon(
                        Icons.shield,
                        size: 48,
                        color: _teamColor(fixture.awayIndex),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        away.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${away.rating.toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white60),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        away.formation.title.split(' ').first,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white38,
                        ),
                      ),
                      Text(
                        away.playStyle.title,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xffffd34d),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: _playCurrentFixture,
                icon: const Icon(Icons.play_arrow, size: 28),
                label: const Text(
                  'MACI OYNAT',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff00a86b),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Her iki takim AI kontrolunde oynar. Mac sonucu lige islenir.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
            if (season.fixtures.any((f) => f.played)) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _simulateAll,
                icon: const Icon(Icons.fast_forward),
                label: const Text('Tum Kalan Maclari Simule Et'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
