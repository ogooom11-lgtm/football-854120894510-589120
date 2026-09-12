import '../enums/player_role.dart';
import '../enums/ai_play_style.dart';

/// The five team states of the game model (plan item 3). The formation never
/// freezes a player's position — the current state decides what the team is
/// trying to do, and the state is re-evaluated continuously during the match.
enum TeamPlayState {
  /// الاستحواذ — possession: stretch the pitch, create passing angles,
  /// push the block forward.
  possession,

  /// الانتقال الهجومي — attacking transition: exploit the space before the
  /// opponent re-organises.
  attackingTransition,

  /// الدفاع المنظم — organised defence: shrink the space, protect the goal.
  organizedDefense,

  /// الانتقال الدفاعي — defensive transition: stop the counter before it
  /// becomes dangerous.
  defensiveTransition,

  /// الضغط — pressing: force the mistake or win the ball back.
  pressing,
}

extension TeamPlayStateInfo on TeamPlayState {
  bool get inPossession =>
      this == TeamPlayState.possession || this == TeamPlayState.attackingTransition;

  bool get outOfPossession =>
      this == TeamPlayState.organizedDefense ||
      this == TeamPlayState.defensiveTransition ||
      this == TeamPlayState.pressing;

  /// Human-readable key used by debug overlays.
  String get key => switch (this) {
        TeamPlayState.possession => 'POSSSESSION',
        TeamPlayState.attackingTransition => 'ATT-TRANSITION',
        TeamPlayState.organizedDefense => 'ORG-DEFENSE',
        TeamPlayState.defensiveTransition => 'DEF-TRANSITION',
        TeamPlayState.pressing => 'PRESSING',
      };

  /// How urgently players move while the team is in this state — part of the
  /// movement layer where speed follows the state (plan item 22).
  double get urgency => switch (this) {
        TeamPlayState.possession => 0.86,
        TeamPlayState.attackingTransition => 0.97,
        TeamPlayState.organizedDefense => 0.84,
        TeamPlayState.defensiveTransition => 0.99,
        TeamPlayState.pressing => 0.95,
      };

  /// Target block tightness (0 = stretched, 1 = compact) before style and
  /// score adjustments (plan item 5).
  double get baseCompactness => switch (this) {
        TeamPlayState.possession => 0.30,
        TeamPlayState.attackingTransition => 0.34,
        TeamPlayState.organizedDefense => 0.72,
        TeamPlayState.defensiveTransition => 0.80,
        TeamPlayState.pressing => 0.58,
      };

  /// Which players lead the pressing in this state (plan item 6): the
  /// nearest player engages, close players support, far players hold width
  /// or tighten.
  double rolePressBias(PlayerRole role, AiPlayStyle style) {
    final intensity = style.pressingIntensity;
    final base = switch (this) {
      TeamPlayState.possession => 0.0,
      TeamPlayState.attackingTransition => 0.25,
      TeamPlayState.organizedDefense => 0.55,
      TeamPlayState.defensiveTransition => 0.95,
      TeamPlayState.pressing => 0.85,
    };
    return (base * (0.55 + intensity * 0.75)) *
        (0.6 + role.pressingPriority * 0.6);
  }
}
