import 'dart:math' as math;

import '../enums/ai_difficulty.dart';
import '../enums/ai_play_style.dart';
import '../enums/match_mode.dart';
import '../enums/team_id.dart';
import 'formation.dart';
import 'player_profile.dart';
import 'jersey_kit.dart';
import 'team_setup.dart';

/// Represents one team in a league.
class LeagueTeam {
  LeagueTeam({
    required this.name,
    required this.rating,
    required this.formation,
    required this.players,
    this.playStyle = AiPlayStyle.balanced,
    this.difficulty = AiDifficulty.medium,
    List<JerseyKit>? jerseyKits,
  }) : jerseyKits = jerseyKits ?? JerseyFactory.defaultKits();

  final String name;
  final double rating;
  final FormationType formation;
  final List<PlayerProfile> players;
  final AiPlayStyle playStyle;
  final AiDifficulty difficulty;
  List<JerseyKit> jerseyKits;

  TeamSetup toTeamSetup(TeamId id) {
    final kits = jerseyKits.isEmpty ? JerseyFactory.defaultKits() : jerseyKits;
    final activeKit = kits.first;
    return TeamSetup(
      id: id,
      name: name,
      formation: formation,
      players: players,
      starterPlayerIds: players.take(11).map((p) => p.id).toSet(),
      rating: rating,
      jerseyKit: activeKit,
      goalkeeperKit: JerseyKit(
        name: 'Kaleci',
        shirtColor: activeKit.goalkeeperShirtColor,
        shortsColor: activeKit.shortsColor,
        socksColor: activeKit.socksColor,
        numberColor: activeKit.numberColor,
        goalkeeperShirtColor: activeKit.goalkeeperShirtColor,
      ),
    );
  }

  factory LeagueTeam.fromJson(Map<String, dynamic> json) {
    return LeagueTeam(
      name: json['name'] as String? ?? 'Takim',
      rating: (json['rating'] as num?)?.toDouble() ?? 50,
      formation: formationFromName(json['formation']),
      players:
          (json['players'] as List<dynamic>?)
              ?.map((p) => PlayerProfile.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      playStyle: AiPlayStyle.values.firstWhere(
        (s) => s.name == json['playStyle'],
        orElse: () => AiPlayStyle.balanced,
      ),
      difficulty: AiDifficulty.values.firstWhere(
        (d) => d.name == json['difficulty'],
        orElse: () => AiDifficulty.medium,
      ),
      jerseyKits: (json['jerseyKits'] as List<dynamic>?)
          ?.map((k) => JerseyKit.fromJson(k as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'rating': double.parse(rating.toStringAsFixed(1)),
    'formation': formation.name,
    'players': players.map((p) => p.toJson()).toList(),
    'playStyle': playStyle.name,
    'difficulty': difficulty.name,
    'jerseyKits': jerseyKits.map((k) => k.toJson()).toList(),
  };
}

/// A single fixture in the league.
class LeagueFixture {
  LeagueFixture({
    required this.matchday,
    required this.homeIndex,
    required this.awayIndex,
    this.homeScore,
    this.awayScore,
    this.played = false,
    this.homeGoals = const [],
    this.awayGoals = const [],
    this.matchId,
  });

  final int matchday;
  final int homeIndex;
  final int awayIndex;
  int? homeScore;
  int? awayScore;
  bool played;
  List<String> homeGoals;
  List<String> awayGoals;
  String? matchId;

  String resultText(List<LeagueTeam> teams) {
    if (!played) return 'vs';
    return '${homeScore ?? 0} - ${awayScore ?? 0}';
  }

  factory LeagueFixture.fromJson(Map<String, dynamic> json) {
    return LeagueFixture(
      matchday: json['matchday'] as int? ?? 1,
      homeIndex: json['homeIndex'] as int? ?? 0,
      awayIndex: json['awayIndex'] as int? ?? 1,
      homeScore: json['homeScore'] as int?,
      awayScore: json['awayScore'] as int?,
      played: json['played'] as bool? ?? false,
      homeGoals: List<String>.from(json['homeGoals'] as List<dynamic>? ?? []),
      awayGoals: List<String>.from(json['awayGoals'] as List<dynamic>? ?? []),
      matchId: json['matchId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'matchday': matchday,
    'homeIndex': homeIndex,
    'awayIndex': awayIndex,
    'homeScore': homeScore,
    'awayScore': awayScore,
    'played': played,
    'homeGoals': homeGoals,
    'awayGoals': awayGoals,
    'matchId': matchId,
  };
}

/// Standing row for a team in the league table.
class LeagueStanding {
  LeagueStanding({required this.teamIndex});

  final int teamIndex;
  int played = 0;
  int wins = 0;
  int draws = 0;
  int losses = 0;
  int goalsFor = 0;
  int goalsAgainst = 0;
  int points = 0;

  int get goalDifference => goalsFor - goalsAgainst;

  /// Sort by points, then goal difference, then goals scored.
  static int compare(LeagueStanding a, LeagueStanding b) {
    if (a.points != b.points) return b.points.compareTo(a.points);
    if (a.goalDifference != b.goalDifference) {
      return b.goalDifference.compareTo(a.goalDifference);
    }
    if (a.goalsFor != b.goalsFor) return b.goalsFor.compareTo(a.goalsFor);
    return a.teamIndex.compareTo(b.teamIndex);
  }
}

/// A complete league season.
class LeagueSeason {
  LeagueSeason({
    required this.name,
    required this.teams,
    List<LeagueFixture>? fixtures,
    List<LeagueStanding>? standings,
    this.currentMatchday = 1,
    this.currentFixtureIndex = 0,
    this.seasonFinished = false,
  }) : fixtures = fixtures ?? _generateFixtures(teams.length),
       standings =
           standings ??
           List.generate(teams.length, (i) => LeagueStanding(teamIndex: i));

  final String name;
  final List<LeagueTeam> teams;
  final List<LeagueFixture> fixtures;
  final List<LeagueStanding> standings;
  int currentMatchday;
  int currentFixtureIndex;
  bool seasonFinished;
  String? championTeamName;

  List<LeagueStanding> get sortedStandings =>
      List<LeagueStanding>.from(standings)..sort(LeagueStanding.compare);

  /// Get fixtures for a specific matchday.
  List<LeagueFixture> matchdayFixtures(int matchday) {
    return fixtures.where((f) => f.matchday == matchday).toList();
  }

  /// Get the current fixture to be played.
  LeagueFixture? get currentFixture {
    final unplayed = fixtures.where((f) => !f.played).toList();
    if (unplayed.isEmpty) return null;
    return unplayed.first;
  }

  /// Record a match result.
  void recordResult(
    LeagueFixture fixture,
    int homeScore,
    int awayScore,
    List<String> homeGoalScorers,
    List<String> awayGoalScorers,
  ) {
    fixture.homeScore = homeScore;
    fixture.awayScore = awayScore;
    fixture.homeGoals = homeGoalScorers;
    fixture.awayGoals = awayGoalScorers;
    fixture.played = true;
    fixture.matchId = DateTime.now().microsecondsSinceEpoch.toString();

    final home = standings[fixture.homeIndex];
    final away = standings[fixture.awayIndex];

    home.played += 1;
    away.played += 1;
    home.goalsFor += homeScore;
    home.goalsAgainst += awayScore;
    away.goalsFor += awayScore;
    away.goalsAgainst += homeScore;

    if (homeScore > awayScore) {
      home.wins += 1;
      away.losses += 1;
      home.points += 3;
    } else if (homeScore < awayScore) {
      away.wins += 1;
      home.losses += 1;
      away.points += 3;
    } else {
      home.draws += 1;
      away.draws += 1;
      home.points += 1;
      away.points += 1;
    }

    // Check if season is complete
    if (fixtures.every((f) => f.played)) {
      seasonFinished = true;
      championTeamName = teams[sortedStandings.first.teamIndex].name;
    }
  }

  /// Create a MatchSetup for the current fixture.
  MatchSetup? createCurrentMatchSetup() {
    final fixture = currentFixture;
    if (fixture == null) return null;

    return MatchSetup(
      mode: MatchMode.league,
      blue: teams[fixture.homeIndex].toTeamSetup(TeamId.blue),
      red: teams[fixture.awayIndex].toTeamSetup(TeamId.red),
      blueAiControlled: true,
      redAiControlled: true,
      aiDifficulty: AiDifficulty.medium,
      bluePlayStyle: teams[fixture.homeIndex].playStyle,
      redPlayStyle: teams[fixture.awayIndex].playStyle,
    );
  }

  /// Generate round-robin fixtures for n teams.
  static List<LeagueFixture> _generateFixtures(int teamCount) {
    final fixtures = <LeagueFixture>[];

    // Add a dummy team if odd number
    final n = teamCount.isEven ? teamCount : teamCount + 1;
    final rounds = n - 1;
    final matchesPerRound = n ~/ 2;

    var rotating = List<int>.generate(n, (i) => i < teamCount ? i : -1);

    for (var round = 0; round < rounds; round++) {
      for (var match = 0; match < matchesPerRound; match++) {
        final home = rotating[match];
        final away = rotating[n - 1 - match];
        if (home == -1 || away == -1) continue;

        // First half: home/away as normal
        fixtures.add(
          LeagueFixture(matchday: round + 1, homeIndex: home, awayIndex: away),
        );

        // Second half: reverse home/away
        fixtures.add(
          LeagueFixture(
            matchday: rounds + round + 1,
            homeIndex: away,
            awayIndex: home,
          ),
        );
      }

      // Rotate: keep first team fixed, rotate others
      final last = rotating.removeLast();
      rotating.insert(1, last);
    }

    return fixtures;
  }

  factory LeagueSeason.fromJson(Map<String, dynamic> json) {
    final teams =
        (json['teams'] as List<dynamic>?)
            ?.map((t) => LeagueTeam.fromJson(t as Map<String, dynamic>))
            .toList() ??
        [];

    return LeagueSeason(
      name: json['name'] as String? ?? 'Lig',
      teams: teams,
      fixtures:
          (json['fixtures'] as List<dynamic>?)
              ?.map((f) => LeagueFixture.fromJson(f as Map<String, dynamic>))
              .toList() ??
          _generateFixtures(teams.length),
      standings:
          (json['standings'] as List<dynamic>?)?.map((s) {
            final map = s as Map<String, dynamic>;
            final standing = LeagueStanding(
              teamIndex: map['teamIndex'] as int? ?? 0,
            );
            standing.played = map['played'] as int? ?? 0;
            standing.wins = map['wins'] as int? ?? 0;
            standing.draws = map['draws'] as int? ?? 0;
            standing.losses = map['losses'] as int? ?? 0;
            standing.goalsFor = map['goalsFor'] as int? ?? 0;
            standing.goalsAgainst = map['goalsAgainst'] as int? ?? 0;
            standing.points = map['points'] as int? ?? 0;
            return standing;
          }).toList() ??
          List.generate(teams.length, (i) => LeagueStanding(teamIndex: i)),
      currentMatchday: json['currentMatchday'] as int? ?? 1,
      currentFixtureIndex: json['currentFixtureIndex'] as int? ?? 0,
      seasonFinished: json['seasonFinished'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'teams': teams.map((t) => t.toJson()).toList(),
    'fixtures': fixtures.map((f) => f.toJson()).toList(),
    'standings': standings
        .map(
          (s) => {
            'teamIndex': s.teamIndex,
            'played': s.played,
            'wins': s.wins,
            'draws': s.draws,
            'losses': s.losses,
            'goalsFor': s.goalsFor,
            'goalsAgainst': s.goalsAgainst,
            'points': s.points,
          },
        )
        .toList(),
    'currentMatchday': currentMatchday,
    'currentFixtureIndex': currentFixtureIndex,
    'seasonFinished': seasonFinished,
  };
}

/// Factory to create default league teams.
class LeagueFactory {
  static LeagueSeason createDefaultSeason() {
    final rng = math.Random();
    final teamDefs = [
      ('Galatasaray', 78, FormationType.wing433, AiPlayStyle.possession),
      ('Fenerbahce', 76, FormationType.modern4231, AiPlayStyle.aggressive),
      ('Besiktas', 72, FormationType.classic442, AiPlayStyle.direct),
      ('Trabzonspor', 68, FormationType.wingback352, AiPlayStyle.counter),
      ('Basaksehir', 64, FormationType.anchor4141, AiPlayStyle.defensive),
      ('Adana Demir', 58, FormationType.brazil424, AiPlayStyle.aggressive),
      ('Antalyaspor', 55, FormationType.midfield361, AiPlayStyle.balanced),
      ('Konyaspor', 54, FormationType.modern3241, AiPlayStyle.defensive),
    ];

    final teams = teamDefs.map((def) {
      final names = _turkishPlayerNames;
      final teamCode = def.$1.substring(0, math.min(3, def.$1.length));
      final players = <PlayerProfile>[];
      for (var i = 0; i < 22; i++) {
        final isKeeper = i == 0 || i == 11;
        players.add(
          PlayerProfile.generated(
            name: '${names[i % names.length]}_$teamCode',
            isGoalkeeper: isKeeper,
            random: math.Random(rng.nextInt(99999)),
          ),
        );
      }
      return LeagueTeam(
        name: def.$1,
        rating: def.$2.toDouble(),
        formation: def.$3,
        playStyle: def.$4,
        players: players,
      );
    }).toList();

    return LeagueSeason(name: 'Super Lig 2026', teams: teams);
  }

  static const _turkishPlayerNames = [
    'Emir',
    'Arda',
    'Mert',
    'Deniz',
    'Kerem',
    'Can',
    'Efe',
    'Berk',
    'Kaan',
    'Yigit',
    'Ozan',
    'Burak',
    'Selim',
    'Murat',
    'Baris',
    'Umut',
    'Onur',
    'Eren',
    'Hakan',
    'Ali',
    'Volkan',
    'Serkan',
  ];
}
