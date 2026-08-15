import 'package:flutter/material.dart';

import '../game/models/player_profile.dart';
import '../game/models/shooting.dart';
import '../game/models/team_profile.dart';
import '../storage/roster_storage.dart';

/// Standalone page showing all players and goalkeepers who do not belong
/// to any team (free agents). Tapping a player opens his full details,
/// including his piyasa degeri (market value). The account can request a
/// transfer into one of its own teams; the request is queued for the
/// admin to accept or reject. While pending, the player is reserved so
/// other accounts cannot request him.
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
  final Map<String, String> _selectedTeamByPlayer = <String, String>{};

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

  Future<void> _save() async {
    final data = _data;
    if (data == null) return;
    await _storage.save(data);
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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

  /// Teams the current account owns and can request a transfer into.
  List<SavedTeamProfile> _ownTeams(SavedGameData data) {
    return data.teams
        .where(
          (team) =>
              !team.isDeleted && team.ownerAccountId == data.activeAccountId,
        )
        .toList();
  }

  Future<void> _requestTransfer(
    SavedGameData data,
    PlayerProfile player,
    String teamId,
  ) async {
    final team = data.teams.firstWhere((item) => item.id == teamId);
    if (data.transferRequestFor(player.id) != null) {
      _showMessage('Bu oyuncu icin zaten bir transfer talebi var');
      return;
    }
    setState(() {
      data.transferRequests.add(
        TransferRequest.create(
          playerId: player.id,
          targetTeamId: teamId,
          requesterAccountId: data.activeAccountId,
        ),
      );
      _selectedTeamByPlayer.remove(player.id);
    });
    await _save();
    _showMessage(
      '${player.name} → ${team.name}: transfer talebi yonetime gonderildi',
    );
  }

  Future<void> _cancelRequest(SavedGameData data, TransferRequest request) async {
    setState(() {
      data.transferRequests.removeWhere((item) => item.id == request.id);
    });
    await _save();
    _showMessage('Transfer talebi iptal edildi');
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
    final account = data.activeAccount;
    final ownTeams = _ownTeams(data);
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
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${free.length} serbest oyuncu',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
                if (ownTeams.isEmpty)
                  const Expanded(
                    child: Text(
                      'Bu hesabin takimi yok — transfer istenemez.',
                      textAlign: TextAlign.end,
                      style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
                    ),
                  )
                else
                  Text(
                    'Hesap: ${account.username}',
                    textAlign: TextAlign.end,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
              ],
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
                          _playerCard(data, player),
                      ],
                      if (fieldPlayers.isNotEmpty) ...[
                        if (keepers.isNotEmpty) const SizedBox(height: 8),
                        _sectionHeader('Saha oyunculari (${fieldPlayers.length})'),
                        for (final player in fieldPlayers)
                          _playerCard(data, player),
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

  Widget _playerCard(SavedGameData data, PlayerProfile player) {
    final request = data.transferRequestFor(player.id);
    final ownRequest = request != null &&
        request.requesterAccountId == data.activeAccountId;
    final reservedByOther = request != null && !ownRequest;
    final ownTeams = _ownTeams(data);
    final selectedTeam = _selectedTeamByPlayer[player.id];
    final canRequest =
        ownTeams.isNotEmpty && request == null && !player.isUnavailable;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: reservedByOther
            ? Colors.white.withValues(alpha: 0.02)
            : const Color(0xff0d1a16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: reservedByOther
              ? Colors.white24
              : player.isGoalkeeper
              ? const Color(0xffffd34d).withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _showPlayerDetail(player),
            child: Row(
              children: [
                Icon(
                  player.isGoalkeeper ? Icons.back_hand : Icons.directions_run,
                  color: player.isGoalkeeper
                      ? const Color(0xffffd34d)
                      : Colors.white70,
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
                        'OVR ${player.effectiveOverall.toStringAsFixed(0)}'
                        ' | Sut gucu ${player.shotPowerRating.toStringAsFixed(0)}'
                        ' | Sut %${player.shootingAccuracyPercent}'
                        ' | Hiz ${player.speedRating.toStringAsFixed(0)}'
                        '${player.isSuspended ? ' | CEZALI ${player.suspendedMatchesRemaining} mac' : ''}'
                        '${player.isInjured ? ' | SAKAT ${player.injuredDaysRemaining} gun' : ''}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (reservedByOther)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock, size: 14, color: Colors.white54),
                        SizedBox(width: 4),
                        Text(
                          'REZERVE',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
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
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (ownRequest) ...[
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Transfer talebi yonetici onayini bekliyor…',
                    style: TextStyle(
                      color: Color(0xffffd34d),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _cancelRequest(data, request),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Iptal'),
                ),
              ],
            ),
          ] else if (reservedByOther) ...[
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Bu oyuncu baska bir hesap tarafindan rezerve edildi.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ],
            ),
          ] else if (canRequest) ...[
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: ownTeams.any((team) => team.id == selectedTeam)
                        ? selectedTeam
                        : null,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Takim sec',
                      isDense: true,
                    ),
                    items: [
                      for (final team in ownTeams)
                        DropdownMenuItem(
                          value: team.id,
                          child: Text(
                            team.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(
                      () => _selectedTeamByPlayer[player.id] = value ?? '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: selectedTeam == null || selectedTeam.isEmpty
                      ? null
                      : () => _requestTransfer(data, player, selectedTeam),
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('Transfer iste'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff00a86b),
                  ),
                ),
              ],
            ),
          ] else if (player.isUnavailable) ...[
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Sakat/cezali oyuncu transfer edilemez.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ],
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
