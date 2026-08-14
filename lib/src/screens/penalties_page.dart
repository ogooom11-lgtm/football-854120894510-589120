import 'package:flutter/material.dart';

import '../game/models/player_profile.dart';
import '../game/models/team_profile.dart';
import '../storage/roster_storage.dart';

/// CEZALAR — oyuncu ceza (men) yonetimi.
///
/// Oyuncular takimlarina gore gruplanir. Eksi/arti ile mac cezasini
/// degistir. Yonetici sifresi ile acilir (kimo@ gerekmez) ve
/// "Kilitle" ile tekrar kapatilir.
class PenaltiesPage extends StatefulWidget {
  const PenaltiesPage({
    super.key,
    required this.data,
    required this.onSave,
    required this.onLock,
  });

  final SavedGameData data;

  /// Degisiklikleri diske yazar.
  final Future<void> Function() onSave;

  /// Sayfayi kilitler (sifre tekrar sorulur).
  final VoidCallback onLock;

  @override
  State<PenaltiesPage> createState() => _PenaltiesPageState();
}

class _PenaltiesPageState extends State<PenaltiesPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedTeamIds = <String>{};
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  SavedGameData get _data => widget.data;

  List<SavedTeamProfile> get _teams =>
      _data.teams.where((team) => !team.isDeleted).toList()
        ..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

  /// Takim oyuncularini isme gore sirali dondurur (guce gore degil).
  List<PlayerProfile> _playersOf(SavedTeamProfile team) {
    return _data.players
        .where((profile) => team.playerIds.contains(profile.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  bool _teamMatchesSearch(SavedTeamProfile team) {
    if (_search.isEmpty) return true;
    final query = _search.toLowerCase();
    if (team.name.toLowerCase().contains(query)) return true;
    return _playersOf(team)
        .any((profile) => profile.name.toLowerCase().contains(query));
  }

  List<PlayerProfile> _visiblePlayers(SavedTeamProfile team) {
    final players = _playersOf(team);
    if (_search.isEmpty || team.name.toLowerCase().contains(_search.toLowerCase())) {
      return players;
    }
    final query = _search.toLowerCase();
    return players
        .where((profile) => profile.name.toLowerCase().contains(query))
        .toList();
  }

  int get _totalBanned =>
      _data.players.where((profile) => profile.isBanned).length;

  Future<void> _changeBan(PlayerProfile profile, int delta) async {
    setState(() {
      profile.banMatches = (profile.banMatches + delta).clamp(0, 99).toInt();
    });
    await widget.onSave();
  }

  Future<void> _openPlayerMenu(PlayerProfile profile) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xff102019),
        title: Text(profile.name),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'yellow'),
            child: const Text('Sari kart ekle (+1)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'red'),
            child: const Text('Kirmizi kart ekle (+1 kart, +1 mac ceza)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'ban3'),
            child: const Text('3 mac ceza ver'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'clearBan'),
            child: const Text('Cezayi kaldir'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'clearCards'),
            child: const Text('Kartlari sifirla'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgec'),
          ),
        ],
      ),
    );
    if (action == null) return;
    setState(() {
      switch (action) {
        case 'yellow':
          profile.yellowCards += 1;
          // Her 4 sari kartta otomatik 1 mac ceza.
          if (profile.yellowCards % 4 == 0) {
            profile.banMatches += 1;
          }
          break;
        case 'red':
          profile.redCards += 1;
          profile.banMatches += 1;
          break;
        case 'ban3':
          profile.banMatches += 3;
          break;
        case 'clearBan':
          profile.banMatches = 0;
          break;
        case 'clearCards':
          profile.yellowCards = 0;
          profile.redCards = 0;
          break;
      }
    });
    await widget.onSave();
  }

  @override
  Widget build(BuildContext context) {
    final teams = _teams.where(_teamMatchesSearch).toList();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xff140d0d),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xff7a2c2c), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Takim veya oyuncu ara',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                isDense: true,
                filled: true,
                fillColor: const Color(0xff1c1010),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xff5a2323)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xff5a2323)),
                ),
              ),
              onChanged: (value) => setState(() => _search = value.trim()),
            ),
          ),
          Expanded(
            child: teams.isEmpty
                ? const Center(
                    child: Text(
                      'Takim bulunamadi',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: teams.length,
                    itemBuilder: (context, index) => _teamBlock(teams[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.gavel, color: Color(0xffe05a5a), size: 30),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CEZALAR',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  'Oyuncular takimlarina gore gruplanir. '
                  'Eksi/arti ile mac cezasini degistir.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xff5a2323)),
            ),
            child: Row(
              children: [
                const Icon(Icons.block, size: 16, color: Colors.white60),
                const SizedBox(width: 6),
                Text(
                  '$_totalBanned cezali oyuncu',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton.icon(
            onPressed: widget.onLock,
            icon: const Icon(Icons.lock_outline, size: 16),
            label: const Text('Kilitle'),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _teamBlock(SavedTeamProfile team) {
    final players = _playersOf(team);
    final bannedCount = players.where((profile) => profile.isBanned).length;
    // Arama yapiliyorsa eslesen takimlar acik gelsin.
    final expanded =
        _expandedTeamIds.contains(team.id) || _search.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xff180f0f),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xff4a2020)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              if (_expandedTeamIds.contains(team.id)) {
                _expandedTeamIds.remove(team.id);
              } else {
                _expandedTeamIds.add(team.id);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xff2a1414),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shield,
                      size: 19,
                      color: Color(0xffe05a5a),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          team.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${players.length} oyuncu • $bannedCount cezali',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                children: [
                  if (_visiblePlayers(team).isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Bu takimda oyuncu yok',
                        style: TextStyle(color: Colors.white38),
                      ),
                    ),
                  for (final profile in _visiblePlayers(team))
                    _playerRow(profile),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _playerRow(PlayerProfile profile) {
    final banned = profile.isBanned;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xff120b0b),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: banned ? const Color(0xffb03a3a) : const Color(0xff3a1a1a),
        ),
      ),
      child: Row(
        children: [
          Icon(
            profile.isGoalkeeper ? Icons.back_hand : Icons.person,
            size: 20,
            color: Colors.white54,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'Sari ${profile.yellowCards} • '
                  'Kirmizi ${profile.redCards} • '
                  'OVR ${profile.effectiveOverall.toStringAsFixed(0)}'
                  '${profile.isInjured ? ' • Sakat' : ''}',
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cezayi azalt',
            icon: const Icon(Icons.remove_circle_outline, size: 22),
            color: Colors.white54,
            onPressed: profile.banMatches > 0
                ? () => _changeBan(profile, -1)
                : null,
          ),
          SizedBox(
            width: 62,
            child: Text(
              '${profile.banMatches} MAC',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: banned
                    ? const Color(0xffff7676)
                    : const Color(0xff4ade80),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Ceza ekle',
            icon: const Icon(Icons.add_circle_outline, size: 22),
            color: Colors.white54,
            onPressed: () => _changeBan(profile, 1),
          ),
          IconButton(
            tooltip: 'Diger islemler',
            icon: const Icon(Icons.more_vert, size: 20),
            color: Colors.white54,
            onPressed: () => _openPlayerMenu(profile),
          ),
        ],
      ),
    );
  }
}
