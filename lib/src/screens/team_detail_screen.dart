import 'package:flutter/material.dart';

import '../game/models/player_profile.dart';
import '../game/models/team_profile.dart';
import '../storage/roster_storage.dart';

/// Team detail page: identity, total squad market value, current form
/// (streak + last results) and the full list of played match results.
class TeamDetailScreen extends StatefulWidget {
  const TeamDetailScreen({super.key, required this.teamId});

  final String teamId;

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  final RosterStorage _storage = RosterStorage();
  SavedGameData? _data;
  bool _loading = true;

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

  SavedTeamProfile? get _team {
    final data = _data;
    if (data == null) return null;
    final matches = data.teams
        .where((team) => team.id == widget.teamId && !team.isDeleted);
    return matches.isEmpty ? null : matches.first;
  }

  static String _dateText(int timestamp) {
    if (timestamp <= 0) return 'Tarih yok';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  static Color _resultColor(String result) {
    if (result == 'Galibiyet' || result == 'G') {
      return const Color(0xff2ee59d);
    }
    if (result == 'Beraberlik' || result == 'B') return Colors.white38;
    return const Color(0xffff6b6b);
  }

  static String _resultLetter(String result) {
    if (result == 'Galibiyet') return 'G';
    if (result == 'Beraberlik') return 'B';
    return 'M';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xff08140f),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final data = _data;
    final team = _team;
    if (data == null || team == null) {
      return Scaffold(
        backgroundColor: const Color(0xff08140f),
        appBar: AppBar(title: const Text('Takim')),
        body: const Center(
          child: Text('Takim bulunamadi.', style: TextStyle(color: Colors.white60)),
        ),
      );
    }
    final ownerMatches = data.accounts
        .where((account) => account.id == team.ownerAccountId)
        .toList();
    final ownerName = ownerMatches.isEmpty ? 'Secilmedi' : ownerMatches.first.username;
    final players = data.players
        .where((player) => team.playerIds.contains(player.id))
        .toList();
    final totalValue = data.teamTotalValue(team);
    final form = team.formLetters;

    return Scaffold(
      backgroundColor: const Color(0xff08140f),
      appBar: AppBar(
        title: Text('Takim — ${team.name}'),
        actions: [
          if (data.activeTeams.length > 1)
            IconButton(
              tooltip: 'Baska takim',
              onPressed: () => _pickTeam(data),
              icon: const Icon(Icons.swap_horiz),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
        children: [
          _headerCard(team, ownerName, totalValue, players.length),
          const SizedBox(height: 10),
          _formCard(team, form),
          const SizedBox(height: 10),
          _recordRow(team),
          const SizedBox(height: 14),
          _sectionTitle(Icons.receipt_long,
              'TUM MAC SONUCLARI (${team.matchHistory.length})'),
          if (team.matchHistory.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Bu takim henuz mac oynamamisti.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            )
          else
            for (final record in team.matchHistory)
              _matchRow(record),
        ],
      ),
    );
  }

  Future<void> _pickTeam(SavedGameData data) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Takim sec'),
        children: [
          for (final item in data.activeTeams)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(item.id),
              child: Text(item.name),
            ),
        ],
      ),
    );
    if (picked != null && picked != widget.teamId && mounted) {
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TeamDetailScreen(teamId: picked)),
      );
    }
  }

  Widget _sectionTitle(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
      child: Row(
        children: [
          Icon(icon, size: 17, color: const Color(0xffffd34d)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 1.1,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCard(
    SavedTeamProfile team,
    String ownerName,
    double totalValue,
    int playerCount,
  ) {
    final kit = team.activeKit;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff123324), Color(0xff0b1a13)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffd4af37).withValues(alpha: 0.35)),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kit.shirtColor.withValues(alpha: 0.35),
              border: Border.all(color: kit.shirtColor, width: 2),
            ),
            child: Icon(
              Icons.shield_rounded,
              size: 34,
              color: _isDark(kit.shirtColor)
                  ? Colors.white
                  : const Color(0xff10201a),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    if (team.country.isNotEmpty) team.country,
                    'Sahip: $ownerName',
                    'Oyuncu: $playerCount',
                    'Guc: ${team.rating.toStringAsFixed(1)}',
                  ].join('  •  '),
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    _infoChip('GALIBIYET', '${team.wins}', color: const Color(0xff2ee59d)),
                    _infoChip('BERABERLIK', '${team.draws}', color: Colors.white70),
                    _infoChip('MAGLUBIYET', '${team.losses}', color: const Color(0xffff6b6b)),
                    _infoChip('MAC', '${team.played}', color: Colors.white70),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xff00c896).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xff00c896).withValues(alpha: 0.55),
              ),
            ),
            child: Column(
              children: [
                const Text(
                  'TOPLAM KADRO DEGERI',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  formatMarketValue(totalValue),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: Color(0xff00e08b),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  totalValue.round().toString(),
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formCard(SavedTeamProfile team, List<String> form) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timeline, size: 18, color: Color(0xffffd34d)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team.formText,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Son 10 mac (yeni eskiye)',
                  style: const TextStyle(fontSize: 10.5, color: Colors.white54),
                ),
              ],
            ),
          ),
          Row(
            children: [
              for (final letter in form.reversed) ...[
                Container(
                  margin: const EdgeInsets.only(right: 5),
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _resultColor(letter).withValues(alpha: 0.16),
                    border: Border.all(
                      color: _resultColor(letter),
                      width: 1.4,
                    ),
                  ),
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: _resultColor(letter),
                    ),
                  ),
                ),
              ],
              if (form.isEmpty)
                const Text(
                  'Mac kaydi yok',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recordRow(SavedTeamProfile team) {
    final avgScore = team.played == 0
        ? null
        : (team.wins * 3 + team.draws) / team.played;
    final chips = <(String, String, Color)>[
      ('G', '${team.wins}', const Color(0xff2ee59d)),
      ('B', '${team.draws}', Colors.white70),
      ('M', '${team.losses}', const Color(0xffff6b6b)),
      ('OYNANAN', '${team.played}', Colors.white70),
      if (avgScore != null)
        ('PUAN ORT.', avgScore.toStringAsFixed(2), const Color(0xffffd34d)),
    ];
    return Row(
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.045),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              ),
              child: Column(
                children: [
                  Text(
                    chips[i].$1,
                    style: const TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w800,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    chips[i].$2,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: chips[i].$3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _matchRow(TeamMatchRecord record) {
    final color = _resultColor(record.result);
    final letter = _resultLetter(record.result);
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff10231c), Color(0xff0c1712)],
        ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.16),
              border: Border.all(color: color, width: 1.4),
            ),
            child: Text(
              letter,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              record.scoreText,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'vs ${record.opponentName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '${_dateText(record.timestamp)}  •  Top %${record.possessionPercent.toStringAsFixed(0)}  •  Sut ${record.shots}  •  Pas ${record.successfulPasses}/${record.passes}',
                  style: const TextStyle(fontSize: 10.5, color: Colors.white54),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Guc ${record.ratingBefore.toStringAsFixed(1)} ${record.ratingAfter >= record.ratingBefore ? '▲' : '▼'} ${record.ratingAfter.toStringAsFixed(1)}',
            style: const TextStyle(fontSize: 10.5, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label, String value, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: const TextStyle(
              fontSize: 10.5,
              color: Colors.white54,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static bool _isDark(Color color) {
    final luminance =
        color.r * 0.299 + color.g * 0.587 + color.b * 0.114;
    return luminance < 128;
  }
}
