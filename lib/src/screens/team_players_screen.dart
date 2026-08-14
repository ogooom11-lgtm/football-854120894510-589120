import 'package:flutter/material.dart';

import '../game/enums/player_role.dart';
import '../game/models/player_profile.dart';
import '../game/models/team_profile.dart';
import '../storage/roster_storage.dart';

/// Standalone page: pick a team, see its players (always sorted by NAME,
/// never by rating) and edit every player value from here.
///
/// Reachable only from the admin page after unlocking with the secret
/// `kimo@` password prefix.
class TeamPlayersScreen extends StatefulWidget {
  const TeamPlayersScreen({super.key});

  @override
  State<TeamPlayersScreen> createState() => _TeamPlayersScreenState();
}

class _TeamPlayersScreenState extends State<TeamPlayersScreen> {
  final RosterStorage _storage = RosterStorage();
  final TextEditingController _searchController = TextEditingController();
  SavedGameData? _data;
  bool _loading = true;
  String? _teamId;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await _storage.load();
    if (!mounted) return;
    final teams = data.teams.where((team) => !team.isDeleted).toList();
    setState(() {
      _data = data;
      _teamId = teams.isEmpty ? null : teams.first.id;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final data = _data;
    if (data == null) return;
    await _storage.save(data);
  }

  List<SavedTeamProfile> get _teams =>
      (_data?.teams ?? const <SavedTeamProfile>[])
          .where((team) => !team.isDeleted)
          .toList()
        ..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

  SavedTeamProfile? get _selectedTeam {
    final teams = _teams;
    if (teams.isEmpty) return null;
    final matches = teams.where((team) => team.id == _teamId);
    return matches.isEmpty ? teams.first : matches.first;
  }

  /// Players of the selected team, ALWAYS ordered alphabetically by name so
  /// the list never reshuffles when a rating changes.
  List<PlayerProfile> _teamPlayers(SavedGameData data, SavedTeamProfile team) {
    final list = data.players
        .where((profile) => team.playerIds.contains(profile.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (_search.isEmpty) {
      return list;
    }
    final query = _search.toLowerCase();
    return list
        .where((profile) => profile.name.toLowerCase().contains(query))
        .toList();
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
        title: const Text('Takim Oyunculari'),
        backgroundColor: const Color(0xff0d1a16),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _teamSelector(),
            const SizedBox(height: 14),
            Expanded(
              child: team == null
                  ? const Center(child: Text('Kayitli takim yok'))
                  : _playerList(data, team),
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamSelector() {
    final teams = _teams;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          const Icon(Icons.shield, color: Color(0xffffd34d)),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              value: teams.any((team) => team.id == _teamId)
                  ? _teamId
                  : (teams.isEmpty ? null : teams.first.id),
              isDense: true,
              decoration: const InputDecoration(labelText: 'Takim sec'),
              items: teams
                  .map(
                    (team) => DropdownMenuItem<String>(
                      value: team.id,
                      child: Text(
                        team.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _teamId = value),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Oyuncu ara',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              onChanged: (value) => setState(() => _search = value.trim()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerList(SavedGameData data, SavedTeamProfile team) {
    final players = _teamPlayers(data, team);
    return Container(
      decoration: _panelDecoration(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${team.name} — ${players.length} oyuncu (isme gore sirali)',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  'Takim gucu: ${team.rating.toStringAsFixed(1)}',
                  style: const TextStyle(color: Colors.white60),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: players.isEmpty
                ? const Center(child: Text('Bu takimda oyuncu yok'))
                : ListView.builder(
                    itemCount: players.length,
                    itemBuilder: (context, index) =>
                        _playerCard(team, players[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _playerCard(SavedTeamProfile team, PlayerProfile profile) {
    final allowedRoles = profile.isGoalkeeper
        ? const [PlayerRole.goalkeeper]
        : PlayerRole.values.where((role) => !role.isGoalkeeper).toList();
    final currentRole = allowedRoles.contains(team.roleByPlayerId[profile.id])
        ? team.roleByPlayerId[profile.id]!
        : allowedRoles.first;
    final isStarter = team.starterPlayerIds.contains(profile.id);
    return ExpansionTile(
      leading: Icon(
        profile.isGoalkeeper ? Icons.back_hand : Icons.directions_run,
        color: profile.isGoalkeeper
            ? const Color(0xffffd34d)
            : Colors.white70,
      ),
      title: Text(
        profile.name,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        'Rey ${profile.effectiveOverall.toStringAsFixed(0)} | '
        'Zeka ${profile.zekaGucu.toStringAsFixed(0)} | '
        '${currentRole.turkishName}${isStarter ? ' | ilk 11' : ''}'
        '${profile.isInjured ? ' | Sakat (${profile.injuredDaysRemaining}g)' : ''}',
        style: const TextStyle(fontSize: 12, color: Colors.white54),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: profile.name,
                decoration: const InputDecoration(labelText: 'Oyuncu adi'),
                onChanged: (value) {
                  if (value.trim().isNotEmpty) {
                    profile.name = value.trim();
                  }
                },
                onFieldSubmitted: (_) {
                  setState(() {});
                  _save();
                },
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<PlayerRole>(
                value: currentRole,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Mevki'),
                items: allowedRoles
                    .map(
                      (role) => DropdownMenuItem(
                        value: role,
                        child: Text(role.turkishName),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => team.roleByPlayerId[profile.id] = value);
                  _save();
                },
              ),
            ),
            const SizedBox(width: 10),
            FilterChip(
              selected: isStarter,
              label: const Text('Ilk 11'),
              onSelected: (value) {
                setState(() {
                  if (value) {
                    if (team.starterPlayerIds.length < 11) {
                      team.starterPlayerIds.add(profile.id);
                    }
                  } else {
                    team.starterPlayerIds.remove(profile.id);
                  }
                });
                _save();
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        _slider(
          'Genel oyun',
          profile.overallRating,
          (value) => profile.overallRating = value,
        ),
        _slider('Sut', profile.shootingRating,
            (value) => profile.shootingRating = value),
        _slider('Pas', profile.passingRating,
            (value) => profile.passingRating = value),
        _slider('Kalecilik', profile.goalkeepingRating,
            (value) => profile.goalkeepingRating = value),
        _slider('Hiz', profile.speedRating,
            (value) => profile.speedRating = value),
        _slider('Enerji', profile.staminaRating,
            (value) => profile.staminaRating = value),
        _slider('Zeka gucu', profile.zekaGucu,
            (value) => profile.zekaGucu = value),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Mac ${profile.matchesPlayed} | Gol ${profile.goals} | '
            'Asist ${profile.assists} | Pas ${profile.successfulPasses}/${profile.passes} | '
            'Sut ${profile.shotsOnTarget}/${profile.shots} | Kurtaris ${profile.saves}',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ),
        if (profile.isInjured)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.healing, color: Colors.redAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sakatlik: ${profile.injuredDaysRemaining} gun kaldi',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => profile.injuredDaysRemaining = 0);
                    _save();
                  },
                  child: const Text('Sakatligi kaldir'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _slider(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 100, child: Text(label)),
        Expanded(
          child: Slider(
            min: 1,
            max: 99,
            divisions: 98,
            value: value.clamp(1, 99).toDouble(),
            label: value.toStringAsFixed(0),
            onChanged: (newValue) => setState(() => onChanged(newValue)),
            onChangeEnd: (_) => _save(),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(value.toStringAsFixed(0), textAlign: TextAlign.end),
        ),
      ],
    );
  }

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: const Color(0xff0d1a16),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    );
  }
}
