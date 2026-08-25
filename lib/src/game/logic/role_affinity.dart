import '../enums/player_role.dart';
import '../models/player_profile.dart';

/// Scores how well a player fits each field role based on his attribute
/// profile. Used by the formation editors to highlight "where this player
/// is best suited to play".
class RoleAffinity {
  const RoleAffinity({required this.role, required this.score});

  final PlayerRole role;

  /// 0-99 fit score.
  final double score;
}

List<RoleAffinity> preferredRolesFor(PlayerProfile profile) {
  if (profile.isGoalkeeper) {
    return const [
      RoleAffinity(role: PlayerRole.goalkeeper, score: 99),
    ];
  }
  final speed = profile.speedRating / 100;
  final finishing = profile.finishingRating / 100;
  final shooting = profile.shootingRating / 100;
  final passing = profile.passingRating / 100;
  final stamina = profile.staminaRating / 100;
  final balance = profile.balanceRating / 100;
  final curve = profile.curveRating / 100;
  final composure = profile.composureRating / 100;
  final zeka = profile.zekaGucu / 100;
  final dayaniklilik = profile.dayaniklilikGucu / 100;
  final height = ((profile.heightMeters - 1.60) / 0.35).clamp(0.0, 1.0).toDouble();

  double scale(double raw) => (raw * 100).clamp(5.0, 99.0).toDouble();

  final scores = <PlayerRole, double>{
    PlayerRole.centerBackLeft: scale(
      balance * 0.30 + dayaniklilik * 0.25 + speed * 0.15 + height * 0.25 + zeka * 0.05,
    ),
    PlayerRole.centerBackRight: scale(
      balance * 0.30 + dayaniklilik * 0.25 + speed * 0.15 + height * 0.25 + zeka * 0.05,
    ),
    PlayerRole.sweeper: scale(
      passing * 0.30 + zeka * 0.25 + balance * 0.20 + composure * 0.15 + height * 0.10,
    ),
    PlayerRole.leftWingBack: scale(
      speed * 0.32 + stamina * 0.25 + balance * 0.18 + passing * 0.15 + dayaniklilik * 0.10,
    ),
    PlayerRole.rightWingBack: scale(
      speed * 0.32 + stamina * 0.25 + balance * 0.18 + passing * 0.15 + dayaniklilik * 0.10,
    ),
    PlayerRole.midfieldLeft: scale(
      passing * 0.30 + zeka * 0.24 + stamina * 0.20 + composure * 0.14 + shooting * 0.12,
    ),
    PlayerRole.midfieldRight: scale(
      passing * 0.30 + zeka * 0.24 + stamina * 0.20 + composure * 0.14 + shooting * 0.12,
    ),
    PlayerRole.leftWing: scale(
      speed * 0.34 + curve * 0.18 + finishing * 0.16 + stamina * 0.14 + shooting * 0.10 + balance * 0.08,
    ),
    PlayerRole.rightWing: scale(
      speed * 0.34 + curve * 0.18 + finishing * 0.16 + stamina * 0.14 + shooting * 0.10 + balance * 0.08,
    ),
    PlayerRole.striker: scale(
      finishing * 0.36 + shooting * 0.24 + speed * 0.20 + composure * 0.10 + balance * 0.10,
    ),
  };

  final result = scores.entries
      .map((entry) => RoleAffinity(role: entry.key, score: entry.value))
      .toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  return result;
}

/// The three best roles for the player, e.g. "Forvet, Sag kanat, Orta saha".
String preferredRolesText(PlayerProfile profile, {int count = 3}) {
  final roles = preferredRolesFor(profile).take(count).toList();
  if (roles.isEmpty) return '-';
  return roles.map((affinity) => affinity.role.turkishName).join(' • ');
}
