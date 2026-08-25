import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/enums/player_role.dart';
import '../game/models/match_event.dart';
import '../game/models/player_profile.dart';
import '../game/models/shooting.dart';
import '../game/models/team_profile.dart';
import '../storage/roster_storage.dart';

/// Full player profile page: identity, market value, career summary,
/// "man of the match" highlights and every played match with goals,
/// assists (with minutes), cards and the match rating.
class PlayerDetailScreen extends StatefulWidget {
  const PlayerDetailScreen({super.key, required this.playerId});

  final String playerId;

  @override
  State<PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<PlayerDetailScreen> {
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

  PlayerProfile? get _player {
    final data = _data;
    if (data == null) return null;
    final matches = data.players.where((player) => player.id == widget.playerId);
    return matches.isEmpty ? null : matches.first;
  }

  SavedTeamProfile? get _team {
    final data = _data;
    final player = _player;
    if (data == null || player == null) return null;
    for (final team in data.activeTeams) {
      if (team.playerIds.contains(player.id)) return team;
    }
    return null;
  }

  static String _dateText(int timestamp) {
    if (timestamp <= 0) return 'Tarih yok';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  static Color _ratingColor(double rating) {
    if (rating >= 8.5) return const Color(0xffb8860b);
    if (rating >= 7.5) return const Color(0xff2ee59d);
    if (rating >= 6.5) return const Color(0xff9ccc65);
    if (rating >= 5.5) return const Color(0xffffb74d);
    return const Color(0xffff6b6b);
  }

  FinishedMatchSummary? _archiveFor(String matchId) {
    final data = _data;
    if (data == null || matchId.isEmpty) return null;
    for (final match in data.matchArchive) {
      if (match.matchId == matchId) return match;
    }
    return null;
  }

  /// Player match records sorted newest first using the archive timestamp.
  List<PlayerMatchRecord> _recordsNewestFirst(PlayerProfile player) {
    final records = player.matchHistory.toList();
    records.sort((a, b) {
      final ta = _archiveFor(a.matchId)?.timestamp ?? 0;
      final tb = _archiveFor(b.matchId)?.timestamp ?? 0;
      if (ta != tb) return tb.compareTo(ta);
      return a.matchId.compareTo(b.matchId);
    });
    return records;
  }

  List<Widget> _goalLines(PlayerProfile player, PlayerMatchRecord record) {
    final archive = _archiveFor(record.matchId);
    if (archive == null) return const [];
    final lines = <Widget>[];
    for (final goal in archive.goals) {
      final isScorer =
          goal.scorerPlayerId != null
              ? goal.scorerPlayerId == player.id
              : goal.scorerName == player.name;
      final isAssister =
          goal.assisterPlayerId != null
              ? goal.assisterPlayerId == player.id
              : (goal.assisterName ?? '') == player.name;
      if (isScorer) {
        lines.add(_miniEvent(
          Icons.sports_soccer,
          const Color(0xffffd34d),
          'Gol ${goal.minute}'
          '${goal.isPenalty ? " (P)" : ''}',
        ));
      }
      if (isAssister) {
        lines.add(_miniEvent(Icons.swap_horiz, const Color(0xff2ee59d), 'Asist ${goal.minute}'));
      }
    }
    return lines;
  }

  Widget _miniEvent(IconData icon, Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  void _copyName(PlayerProfile player) {
    Clipboard.setData(ClipboardData(text: player.name));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${player.name} adi panoya kopyalandi')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xff08140f),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final player = _player;
    if (player == null) {
      return Scaffold(
        backgroundColor: const Color(0xff08140f),
        appBar: AppBar(title: const Text('Oyuncu')),
        body: const Center(
          child: Text('Oyuncu bulunamadi.', style: TextStyle(color: Colors.white60)),
        ),
      );
    }
    final team = _team;
    final role = team == null ? null : team.roleByPlayerId[player.id];
    final records = _recordsNewestFirst(player);
    final manOfMatch =
        records.where((record) => record.rating >= 8.5).toList();
    final passPercent = player.passes == 0
        ? 0
        : (player.successfulPasses * 100 / player.passes).round();

    return Scaffold(
      backgroundColor: const Color(0xff08140f),
      appBar: AppBar(
        title: Text('Oyuncu profili — ${player.name}'),
        actions: [
          IconButton(
            tooltip: 'Adi kopyala',
            onPressed: () => _copyName(player),
            icon: const Icon(Icons.copy_all_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
        children: [
          _headerCard(player, team, role),
          const SizedBox(height: 10),
          _summaryRow(player, passPercent),
          const SizedBox(height: 14),
          _sectionTitle(Icons.emoji_events, 'MACIN ADAMI OLDUGU MACLAR'),
          if (manOfMatch.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '8.5 ve uzeri puan alan maci yok.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            )
          else
            for (final record in manOfMatch)
              _highlightRow(player, record),
          const SizedBox(height: 12),
          _sectionTitle(Icons.event_note, 'TUM MACLAR (${records.length})'),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Kayitli mac performansi yok. Bir mac oynatinca detaylar burada gorunur.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            )
          else
            for (final record in records)
              _matchCard(player, record),
          const SizedBox(height: 12),
          _sectionTitle(Icons.tune, 'OZELLIK DETAYLARI'),
          _attributesCard(player),
        ],
      ),
    );
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
    PlayerProfile player,
    SavedTeamProfile? team,
    PlayerRole? role,
  ) {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0x66ffd34d), Color(0x14ffd34d)],
              ),
              border: Border.all(color: const Color(0xffffd34d), width: 1.6),
            ),
            child: Center(
              child: Text(
                '${player.number ?? ''}',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Color(0xffffd34d),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
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
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (player.isUnavailable) ...[
                      const SizedBox(width: 8),
                      _badge(
                        player.isSuspended
                            ? 'CEZALI ${player.suspendedMatchesRemaining}'
                            : 'SAKAT ${player.injuredDaysRemaining} gun',
                        Colors.redAccent,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    role?.turkishName ?? (player.isGoalkeeper ? 'Kaleci' : 'Saha oyuncusu'),
                    team == null ? 'Takim yok' : team.name,
                    if (player.country.isNotEmpty) player.country,
                    '${player.heightMeters.toStringAsFixed(2)} m',
                    player.preferredFoot == PreferredFoot.left ? 'Sol ayak' : 'Sag ayak',
                  ].join('  •  '),
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    _infoChip('OVR', player.effectiveOverall.toStringAsFixed(0), gold: true),
                    _infoChip(
                      'Puan ort.',
                      player.matchesPlayed > 0
                          ? player.pointAverage.toStringAsFixed(1)
                          : '-',
                    ),
                    _infoChip('Mac', '${player.matchesPlayed}'),
                    _infoChip('Dakika', '${player.minutesPlayed}'),
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
                  'PIYASA DEGERI',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  player.marketValueText,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: Color(0xff00e08b),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  player.marketValueFull,
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(PlayerProfile player, int passPercent) {
    final items = <(String, String, bool)>[
      ('GOL', '${player.goals}', player.goals > 0),
      ('ASIST', '${player.assists}', player.assists > 0),
      ('SUT', '${player.shotsOnTarget}/${player.shots}', false),
      ('SUT %', '${player.shootingAccuracyPercent}', false),
      ('PAS', '${player.successfulPasses}/${player.passes}', false),
      ('PAS %', '$passPercent', false),
      ('DRIPLING', '${player.successfulDribbles}/${player.dribbles}', false),
      ('MUDAHALE', '${player.tackles}', false),
      ('SAVUNMA', player.isGoalkeeper ? 'KURTARIS ${player.saves}' : 'UZAKLASTIRMA ${player.clearances}', false),
      ('KARTLAR', '${player.yellowCards}S / ${player.redCards}K', player.yellowCards + player.redCards > 0),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.045),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: items[i].$3
                      ? const Color(0xffffd34d).withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.09),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    items[i].$1,
                    style: const TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w800,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    items[i].$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: items[i].$3
                          ? const Color(0xffffd34d)
                          : const Color(0xffe8f0ec),
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

  Widget _highlightRow(PlayerProfile player, PlayerMatchRecord record) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff33270c), Color(0xff1a1508)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffffd34d).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: Color(0xffffd34d), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${record.teamName} ${record.scoreText} ${record.opponentName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '${_dateText(_archiveFor(record.matchId)?.timestamp ?? 0)}  •  ${record.minutes} dakika  •  ${record.goals} gol  •  ${record.assists} asist',
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
          ),
          _ratingBadge(record.rating),
        ],
      ),
    );
  }

  Widget _matchCard(PlayerProfile player, PlayerMatchRecord record) {
    final archive = _archiveFor(record.matchId);
    final timestamp = archive?.timestamp ?? 0;
    final parts = record.scoreText.split('-');
    final homeScore =
        parts.length == 2 ? int.tryParse(parts[0].trim()) : null;
    final awayScore =
        parts.length == 2 ? int.tryParse(parts[1].trim()) : null;
    final isWin = homeScore != null &&
        awayScore != null &&
        homeScore > awayScore;
    final isDraw = homeScore != null && homeScore == awayScore;
    final goalLines = _goalLines(player, record);
    final cards = record.yellowCards + record.redCards;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff10231c), Color(0xff0c1712)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isWin
                    ? Icons.trending_up
                    : (isDraw ? Icons.remove : Icons.trending_down),
                size: 16,
                color: isWin
                    ? const Color(0xff2ee59d)
                    : (isDraw
                          ? Colors.white38
                          : const Color(0xffff6b6b)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${record.teamName}  ${record.scoreText}  ${record.opponentName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
              if (record.rating >= 8.5) ...[
                _badge('MACIN ADAMI', const Color(0xffffd34d)),
                const SizedBox(width: 8),
              ],
              _ratingBadge(record.rating),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '${_dateText(timestamp)}  •  ${record.minutes} dakika'
            '${record.injured ? '  •  SAKATLANDI' : ''}',
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              _infoChip('GOL', '${record.goals}', gold: record.goals > 0),
              _infoChip('ASIST', '${record.assists}', gold: record.assists > 0),
              _infoChip('SUT', '${record.shotsOnTarget}/${record.shots}'),
              _infoChip('PAS', '${record.successfulPasses}/${record.passes}'),
              if (record.tackles > 0) _infoChip('MUDAHALE', '${record.tackles}'),
              if (player.isGoalkeeper && record.saves > 0)
                _infoChip('KURTARIS', '${record.saves}'),
              if (!player.isGoalkeeper && record.clearances > 0)
                _infoChip('UZAKLASTIRMA', '${record.clearances}'),
              if (record.dribbles > 0)
                _infoChip('DRIPL', '${record.successfulDribbles}/${record.dribbles}'),
              if (record.missedChances > 0)
                _infoChip('KACAN FIRSAT', '${record.missedChances}'),
              if (cards > 0)
                _infoChip('KART', '${record.yellowCards}S ${record.redCards}K', gold: record.redCards > 0),
              if (goalLines.isEmpty && (record.goals > 0 || record.assists > 0))
                _infoChip('Dakika detayi', 'arsivde yok', gold: false),
            ],
          ),
          if (goalLines.isNotEmpty) ...[
            const SizedBox(height: 7),
            Wrap(spacing: 6, runSpacing: 5, children: goalLines),
          ],
        ],
      ),
    );
  }

  Widget _ratingBadge(double rating) {
    final color = _ratingColor(rating);
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color, width: 1.6),
      ),
      child: Text(
        rating.toStringAsFixed(1),
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }

  Widget _attributesCard(PlayerProfile player) {
    final passPercent = player.passes == 0
        ? 0
        : (player.successfulPasses * 100 / player.passes).round();
    final items = <(String, String)>[
      ('Genel', player.overallRating.toStringAsFixed(0)),
      ('Efektif OVR', player.effectiveOverall.toStringAsFixed(0)),
      ('Sut', player.shootingRating.toStringAsFixed(0)),
      ('Bitiricilik', player.finishingRating.toStringAsFixed(0)),
      ('Sut gucu', player.shotPowerRating.toStringAsFixed(0)),
      ('Uzaktan sut', player.longShotsRating.toStringAsFixed(0)),
      ('Falso', player.curveRating.toStringAsFixed(0)),
      ('Sogukkanlilik', player.composureRating.toStringAsFixed(0)),
      ('Denge', player.balanceRating.toStringAsFixed(0)),
      ('Pas', player.passingRating.toStringAsFixed(0)),
      ('Hiz', player.speedRating.toStringAsFixed(0)),
      ('Enerji', player.staminaRating.toStringAsFixed(0)),
      ('Dayaniklilik', player.dayaniklilikGucu.toStringAsFixed(0)),
      ('Zeka', player.zekaGucu.toStringAsFixed(0)),
      ('Kalecilik', player.goalkeepingRating.toStringAsFixed(0)),
      ('Zayif ayak', '${player.weakFootRating}/5'),
      ('Boy', '${(player.heightMeters * 100).round()} cm'),
      ('Puan (toplam)', player.points.toStringAsFixed(1)),
      ('Pas %', '$passPercent'),
      ('Fitness', '%${(player.fitness * 100).round()}'),
    ];
    if (player.isGoalkeeper) {
      items.addAll(<(String, String)>[
        ('GK Reaksiyon', player.goalkeeperReactionRating.toStringAsFixed(0)),
        ('GK Pozisyon', player.goalkeeperPositioningRating.toStringAsFixed(0)),
        ('GK Atlayis', player.goalkeeperDivingRating.toStringAsFixed(0)),
        ('GK Handling', player.goalkeeperHandlingRating.toStringAsFixed(0)),
        ('GK Yakalayis', player.goalkeeperCatchingRating.toStringAsFixed(0)),
        ('GK Sicrama', player.goalkeeperJumpingRating.toStringAsFixed(0)),
        ('GK Karar', player.goalkeeperDecisionRating.toStringAsFixed(0)),
        ('GK Bire Bir', player.goalkeeperOneVsOneRating.toStringAsFixed(0)),
        ('GK Yuksek Top', player.goalkeeperHighBallsRating.toStringAsFixed(0)),
        ('GK Erisim', player.goalkeeperReachRating.toStringAsFixed(0)),
        ('GK Ongoru', player.goalkeeperAnticipationRating.toStringAsFixed(0)),
        ('GK Sektirme', player.goalkeeperParryingRating.toStringAsFixed(0)),
        ('GK Dagitim', player.goalkeeperDistributionRating.toStringAsFixed(0)),
      ]);
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in items)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xff12281e).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${item.$1}: ',
                    style: const TextStyle(fontSize: 11.5, color: Colors.white54),
                  ),
                  Text(
                    item.$2,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Color(0xffe8f0ec),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoChip(String label, String value, {bool gold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: gold
            ? const Color(0xffffd34d).withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: gold
              ? const Color(0xffffd34d).withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.12),
        ),
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
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: gold ? const Color(0xffffd34d) : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}
