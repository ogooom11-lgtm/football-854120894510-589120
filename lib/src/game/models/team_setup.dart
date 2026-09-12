import '../enums/ai_difficulty.dart';
import '../enums/ai_play_style.dart';
import '../enums/match_mode.dart';
import '../enums/player_role.dart';
import '../enums/team_id.dart';
import 'formation.dart';
import 'jersey_kit.dart';
import 'player_profile.dart';

class TeamSetup {
  const TeamSetup({
    required this.id,
    required this.name,
    required this.formation,
    required this.players,
    this.starterPlayerIds = const {},
    this.roleByPlayerId = const {},
    this.slotByPlayerId = const {},
    this.storageTeamId,
    this.rating = 50,
    this.jerseyKit,
    this.goalkeeperKit,
  });

  final TeamId id;
  final String name;
  final FormationType formation;
  final List<PlayerProfile> players;
  final Set<String> starterPlayerIds;
  final Map<String, PlayerRole> roleByPlayerId;
  final Map<String, int> slotByPlayerId;
  final String? storageTeamId;
  final double rating;
  final JerseyKit? jerseyKit;
  final JerseyKit? goalkeeperKit;
}

class MatchSetup {
  const MatchSetup({
    required this.mode,
    required this.blue,
    required this.red,
    this.blueAiControlled = false,
    this.redAiControlled = false,
    this.aiDifficulty = AiDifficulty.medium,
    this.bluePlayStyle = AiPlayStyle.balanced,
    this.redPlayStyle = AiPlayStyle.balanced,
  });

  final MatchMode mode;
  final TeamSetup blue;
  final TeamSetup red;
  final bool blueAiControlled;
  final bool redAiControlled;
  final AiDifficulty aiDifficulty;
  final AiPlayStyle bluePlayStyle;
  final AiPlayStyle redPlayStyle;
}
