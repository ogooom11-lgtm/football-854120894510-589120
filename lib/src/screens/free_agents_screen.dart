import 'package:flutter/material.dart';

import '../game/models/player_profile.dart';
import '../game/models/shooting.dart';
import '../storage/roster_storage.dart';

/// Standalone page showing all players and goalkeepers who do not belong
/// to any team (free agents). Tapping a player opens his full details,
/// including his piyasa degeri (market value).
class FreeAgentsScreen extends StatefulWidget {
  const FreeAgentsScreen({super.key});

  @override
  State<FreeAgentsScreen> createState() => _FreeAgentsScreenState();
}

class _FreeAgentsScreenState extends State<FreeAgentsScreen> {
  final RosterStorage _storage = RosterStorage();
  SavedGameData? _data;
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _storage.load();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  List<PlayerProfile> _freePlayers(SavedGameData data) {
    final assignedIds = data.teams
        .where((team) => !team.isDeleted)
        .expand((team) => team.playerIds)
        .toSet();
    final query = _search.trim().toLowerCase();
    return data.players
        .where(
          (player) =>
              !assignedIds.contains(player.id) &&
              (query.isEmpty ||
                  player.name.toLowerCase().contains(query) ||
                  (player.number?.toString().contains(query) ?? false)),
        )
        .toList()
      ..sort((a, b) {
        final byValue = b.marketValue.compareTo(a.marketValue);
        return byValue != 0 ? byValue : a.name.compareTo(b.name);
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
    final free = _freePlayers(data);
    final keepers = free.where((p) => p.isGoalkeeper).toList();
    final fieldPlayers = free.where((p) => !p.isGoalkeeper).toList();
    return Scaffold(
      backgroundColor: const Color(0xff08140f),
      appBar: AppBar(
        title: const Text('Serbest Oyuncular'),
        backgroundColor: const Color(0xff0d1a16),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Oyuncu ara (ad veya numara)',
                isDense: true,
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${free.length} serbest oyuncu',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          ),
          const Divider(height: 12),
          Expanded(
            child: free.isEmpty
                ? const Center(
                    child: Text(
                      'Serbest oyuncu yok.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    children: [
                      if (keepers.isNotEmpty) ...[
                        _sectionHeader('Kaleciler (${keepers.length})'),
                        for (final player in keepers)
                          _playerTile(player),
                      ],
                      if (fieldPlayers.isNotEmpty) ...[
                        if (keepers.isNotEmpty) const SizedBox(height: 8),
                        _sectionHeader('Saha oyunculari (${fieldPlayers.length})'),
                        for (final player in fieldPlayers)
                          _playerTile(player),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
      ),
    );
  }

  Widget _playerTile(PlayerProfile player) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xff0d1a16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: player.isGoalkeeper
              ? const Color(0xffffd34d).withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: ListTile(
        leading: Icon(
          player.isGoalkeeper ? Icons.back_hand : Icons.directions_run,
          color: player.isGoalkeeper
              ? const Color(0xffffd34d)
              : Colors.white70,
        ),
        title: Text(
          player.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          'OVR ${player.effectiveOverall.toStringAsFixed(0)}'
          '${player.isSuspended ? ' | CEZALI ${player.suspendedMatchesRemaining} mac' : ''}'
          '${player.isInjured ? ' | SAKAT ${player.injuredDaysRemaining} gun' : ''}',
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xff00a86b).withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xff00a86b).withValues(alpha: 0.4),
            ),
          ),
          child: Text(
            player.marketValueText,
            style: const TextStyle(
              color: Color(0xff00e08b),
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
        onTap: () => _showPlayerDetail(player),
      ),
    );
  }

  void _showPlayerDetail(PlayerProfile player) {
    final passPercent = player.passes == 0
        ? 0
        : (player.successfulPasses * 100 / player.passes).round();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff102019),
        title: Text(player.name),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xff00a86b).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xff00a86b).withValues(alpha: 0.45),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PIYASA DEGERI',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${player.marketValueText}  (${player.marketValueFull})',
                        style: const TextStyle(
                          fontSize: 22,
                          color: Color(0xff00e08b),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 7,
                  children: [
                    _stat('Mevki', player.isGoalkeeper ? 'Kaleci' : 'Saha'),
                    _stat('OVR', player.effectiveOverall.round()),
                    _stat('Efektif OVR', player.effectiveOverall.round()),
                    _stat('Boy', (player.heightMeters * 100).round()),
                    _stat(
                      'Ayak',
                      player.preferredFoot == PreferredFoot.left
                          ? 'Sol'
                          : 'Sag',
                    ),
                    _stat('Zayif ayak', '${player.weakFootRating}/5'),
                    _stat('Genel', player.overallRating.round()),
                    _stat('Sut', player.shootingRating.round()),
                    _stat('Bitiricilik', player.finishingRating.round()),
                    _stat('Sut gucu', player.shotPowerRating.round()),
                    _stat('Uzaktan sut', player.longShotsRating.round()),
                    _stat('Falso', player.curveRating.round()),
                    _stat('Sogukkanlilik', player.composureRating.round()),
                    _stat('Denge', player.balanceRating.round()),
                    _stat('Pas', player.passingRating.round()),
                    _stat('Hiz', player.speedRating.round()),
                    _stat('Enerji', player.staminaRating.round()),
                    _stat('Dayaniklilik', player.dayaniklilikGucu.round()),
                    _stat('Zeka', player.zekaGucu.round()),
                    _stat('Kalecilik', player.goalkeepingRating.round()),
                    if (player.isGoalkeeper) ...[
                      _stat('GK Reaksiyon', player.goalkeeperReactionRating.round()),
                      _stat('GK Pozisyon', player.goalkeeperPositioningRating.round()),
                      _stat('GK Atlayis', player.goalkeeperDivingRating.round()),
                      _stat('GK Handling', player.goalkeeperHandlingRating.round()),
                      _stat('GK Yakalayis', player.goalkeeperCatchingRating.round()),
                      _stat('GK Sicrama', player.goalkeeperJumpingRating.round()),
                      _stat('GK Karar', player.goalkeeperDecisionRating.round()),
                      _stat('GK Bire Bir', player.goalkeeperOneVsOneRating.round()),
                      _stat('GK Yuksek Top', player.goalkeeperHighBallsRating.round()),
                      _stat('GK Erisim', player.goalkeeperReachRating.round()),
                      _stat('GK Ongoru', player.goalkeeperAnticipationRating.round()),
                      _stat('GK Sektirme', player.goalkeeperParryingRating.round()),
                      _stat('GK Dagitim', player.goalkeeperDistributionRating.round()),
                    ],
                    _stat('Mac', player.matchesPlayed),
                    _stat('Dakika', player.minutesPlayed),
                    _stat('Gol', player.goals),
                    _stat('Asist', player.assists),
                    _stat('Pas', player.passes),
                    _stat('Basarili pas', player.successfulPasses),
                    _stat('Pas %', passPercent),
                    _stat('Dripling', player.dribbles),
                    _stat('Basarili dripling', player.successfulDribbles),
                    _stat('Mudahale', player.tackles),
                    _stat('Sut', player.shots),
                    _stat('Isabetli sut', player.shotsOnTarget),
                    _stat('Kacan firsat', player.missedChances),
                    _stat('Uzaklastirma', player.clearances),
                    _stat('Kurtaris', player.saves),
                    _stat('Yaptigi faul', player.foulsCommitted),
                    _stat('Aldigi faul', player.foulsReceived),
                    _stat('Sari', player.yellowCards),
                    _stat('Kirmizi', player.redCards),
                    _stat('Puan', player.points.toStringAsFixed(1)),
                    _stat('Fitness', '%${(player.fitness * 100).round()}'),
                    _stat('Sakatlik gunu', player.injuredDaysRemaining),
                    _stat('Ceza maci', player.suspendedMatchesRemaining),
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
                if (player.matchHistory.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Son maclar: ${player.matchHistory.take(4).map((record) => '${record.scoreText} ${record.rating.toStringAsFixed(1)}').join(' | ')}',
                    style: const TextStyle(color: Colors.white60),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, Object value) {
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
}
