import 'dart:math' as math;
import 'dart:ui';

import '../config/game_constants.dart';
import '../enums/ai_difficulty.dart';
import '../enums/ai_play_style.dart';
import '../enums/kick_type.dart';
import '../enums/match_mode.dart';
import '../enums/player_role.dart';
import '../enums/team_id.dart';
import '../math/vec2.dart';
import '../models/ball_game.dart';
import '../models/formation.dart';
import '../models/match_event.dart';
import '../models/player_game.dart';
import '../models/player_profile.dart';
import '../models/shooting.dart';
import '../models/team_game.dart';
import '../models/team_setup.dart';
import 'ball_physics.dart';
import 'goalkeeper_ai.dart';
import 'offside_logic.dart';
import 'penalty_logic.dart';
import 'player_ai.dart';
import 'shot_calculator.dart';

enum TeamMode { attack, defense, press }

enum MatchPeriod {
  firstHalf,
  secondHalf,
  extraFirst,
  extraSecond,
  penalties,
  finished,
}

enum RestartKind { kickoff, goalKick, corner, throwIn, freeKick }

class MatchEngine {
  MatchEngine(MatchSetup setup)
    : mode = setup.mode,
      random = math.Random(),
      blueTeam = TeamGame.fromSetup(
        setup: setup.blue,
        side: TeamSide.left,
        color: const Color(0xfff4d03f),
      ),
      redTeam = TeamGame.fromSetup(
        setup: setup.red,
        side: TeamSide.right,
        color: const Color(0xff0a4f93),
      ),
      ball = BallGame(
        pos: Vec2(
          GameConstants.virtualWidth / 2,
          GameConstants.virtualHeight / 2,
        ),
      ),
      blueAiControlled = setup.blueAiControlled,
      redAiControlled = setup.redAiControlled,
      aiDifficulty = setup.aiDifficulty,
      bluePlayStyle = setup.bluePlayStyle,
      redPlayStyle = setup.redPlayStyle {
    _playerAi = PlayerAi(random, difficulty: setup.aiDifficulty);
    _goalkeeperAi = GoalkeeperAi(random, difficulty: setup.aiDifficulty);
    _penaltyLogic = PenaltyLogic(random);
    _shotCalculator = ShotCalculator(random);
    firstHalfStoppage = (1 + random.nextInt(4)).toDouble();
    secondHalfStoppage = (2 + random.nextInt(5)).toDouble();
    extraFirstStoppage = random.nextInt(2).toDouble();
    extraSecondStoppage = random.nextInt(2).toDouble();
    resetKickoff(TeamId.blue);
  }

  final MatchMode mode;
  final math.Random random;
  final bool blueAiControlled;
  final bool redAiControlled;
  final AiDifficulty aiDifficulty;
  final AiPlayStyle bluePlayStyle;
  final AiPlayStyle redPlayStyle;
  TeamMode? blueTacticalOverride;
  TeamMode? redTacticalOverride;
  final String matchId = DateTime.now().microsecondsSinceEpoch.toString();
  final TeamGame blueTeam;
  final TeamGame redTeam;
  final BallGame ball;
  final BallPhysics _ballPhysics = const BallPhysics();
  final OffsideLogic _offsideLogic = const OffsideLogic();
  late final PlayerAi _playerAi;
  late final GoalkeeperAi _goalkeeperAi;
  late final PenaltyLogic _penaltyLogic;
  late final ShotCalculator _shotCalculator;
  final ShotDiagnostics shotDiagnostics = ShotDiagnostics();

  MatchPeriod period = MatchPeriod.firstHalf;
  double minute = 0;
  late final double firstHalfStoppage;
  late final double secondHalfStoppage;
  late final double extraFirstStoppage;
  late final double extraSecondStoppage;
  bool finished = false;
  TeamId? winner;

  MatchBanner? banner;
  bool varReviewActive = false;
  String? varReason;
  String? varReviewCategory;
  String? varRecommendedDecision;
  List<String> varDecisionOptions = const [];
  void Function(String decision)? _varDecisionResolver;
  double _pauseTimer = 0;
  void Function()? _afterPause;
  OffsideEvent? currentOffside;
  OffsideCandidate? _offsideCandidate;
  bool _offsideExemptNextKick = false;
  ActivePenalty? activePenalty;
  PenaltyShootout? shootout;
  Vec2? _penaltyKeeperTarget;
  bool _penaltyBallDeflected = false;
  RestartKind? restartKind;
  TeamId? restartTeamId;
  TeamId? setPieceAttackTeamId;
  double setPieceAttackTimer = 0;
  TeamId? _cornerManualWaitTeamId;
  double _cornerManualWaitTimer = 0;
  bool _cornerReadyOverride = false;
  bool wallSelectionPending = false;
  TeamId? wallDefendingTeamId;
  final List<PlayerGame> _wallCandidates = [];
  final Set<String> _lockedWallPlayerIds = <String>{};
  final Map<String, Vec2> _lockedWallPositions = <String, Vec2>{};
  Vec2? _restartSpot;
  List<PlayerGame> get wallCandidates => List.unmodifiable(_wallCandidates);
  PlayerGame? _recentKicker;
  double _recentKickerGrace = 0;
  final List<ReplayFrame> replayFrames = [];
  final List<MatchTimelineEvent> timelineEvents = [];
  int _timelineSerial = 0;
  bool replayMode = false;
  bool replayPlaying = false;
  int replayIndex = 0;
  double _replayPlaybackAccumulator = 0;

  /// VAR replay playback speed. 1.0 = real time, 0.25 = slow motion,
  /// 4.0 = fast forward.
  double replaySpeed = 1.0;

  bool substitutionPaused = false;

  void setReplaySpeed(double value) {
    replaySpeed = value.clamp(0.25, 4.0).toDouble();
  }
  double blueControlSeconds = 0;
  double redControlSeconds = 0;
  int bluePasses = 0;
  int redPasses = 0;
  int blueSuccessfulPasses = 0;
  int redSuccessfulPasses = 0;
  int blueShots = 0;
  int redShots = 0;
  bool _statsCommitted = false;
  final List<InjuryEvent> injuryEvents = [];
  final List<DisciplinaryEvent> disciplinaryEvents = [];
  final List<PlayerGame> _forcedSubs = [];
  final Set<String> _injuryBonusAwardedPlayerIds = <String>{};
  double _replayAccumulator = 0;

  TeamGame get teamInPossession {
    if (ball.owner != null) {
      return teamById(ball.owner!.teamId);
    }
    return ball.pos.x < GameConstants.virtualWidth / 2
        ? teamBySide(TeamSide.left)
        : teamBySide(TeamSide.right);
  }

  List<PlayerGame> get allPlayers => [
    ...blueTeam.players.where((player) => !player.isSentOff),
    ...redTeam.players.where((player) => !player.isSentOff),
  ];

  List<PlayerGame> get allMatchPlayers {
    final list = <PlayerGame>[
      ...blueTeam.players,
      ...redTeam.players,
      ...blueTeam.substitutedOut,
      ...redTeam.substitutedOut,
    ];
    // Players who left for good but are not part of the lists above.
    for (final team in [blueTeam, redTeam]) {
      for (final player in team.removedFromMatch) {
        if (!list.any((existing) => existing.id == player.id)) {
          list.add(player);
        }
      }
    }
    return list;
  }

  bool isTeamAiControlled(TeamId id) =>
      id == TeamId.blue ? blueAiControlled : redAiControlled;

  /// Human-controlled restarts stay frozen until the user actually kicks.
  bool isRestartWaitingForHuman(TeamGame team) =>
      restartKind != null &&
      restartTeamId == team.id &&
      !isTeamAiControlled(team.id);

  ReplayFrame? get currentReplayFrame =>
      replayMode && replayFrames.isNotEmpty ? replayFrames[replayIndex] : null;

  bool get isFrozen =>
      finished ||
      replayMode ||
      substitutionPaused ||
      wallSelectionPending ||
      _pauseTimer > 0 ||
      activePenalty != null ||
      period == MatchPeriod.penalties;

  double get replayProgress => replayFrames.isEmpty
      ? 0
      : replayIndex / math.max(1, replayFrames.length - 1);

  List<GoalEvent> get reviewGoals {
    final goals = [...blueTeam.goals, ...redTeam.goals]
      ..sort((a, b) => a.minute.compareTo(b.minute));
    return goals;
  }

  bool get kickoffPending => restartKind == RestartKind.kickoff;

  bool isGoalKickPendingFor(TeamGame team) {
    return restartKind == RestartKind.goalKick && restartTeamId == team.id;
  }

  bool isGoalKickLockedAgainst(TeamId id) {
    return restartKind == RestartKind.goalKick && restartTeamId != id;
  }

  bool isCornerAttackActiveFor(TeamGame team) {
    return setPieceAttackTeamId == team.id && setPieceAttackTimer > 0;
  }

  bool isCornerWaitingForManualInputFor(TeamGame team) {
    return restartKind == RestartKind.corner &&
        restartTeamId == team.id &&
        (!isTeamAiControlled(team.id) ||
            (!_cornerPlayersAreSet() && !_cornerReadyOverride) ||
            (_cornerManualWaitTeamId == team.id &&
                _cornerManualWaitTimer > 0));
  }

  /// The human player pressed the corner "HAZIR" button: skip the waiting
  /// timer and allow the corner to be taken immediately.
  void markCornerReady(TeamId id) {
    if (restartKind == RestartKind.corner && restartTeamId == id) {
      _cornerManualWaitTeamId = null;
      _cornerManualWaitTimer = 0;
      _cornerReadyOverride = true;
    }
  }

  bool canAiTakeCornerFor(TeamGame team) =>
      restartKind == RestartKind.corner &&
      restartTeamId == team.id &&
      isTeamAiControlled(team.id) &&
      _cornerPlayersAreSet() &&
      _cornerManualWaitTimer <= 0;

  bool _cornerPlayersAreSet() {
    if (restartKind != RestartKind.corner) {
      return true;
    }
    return allPlayers
        .where((player) => !player.isGoalkeeper && player != ball.owner)
        .every((player) =>
            player.restartTarget == null ||
            player.pos.distanceTo(player.restartTarget!) < 20);
  }

  void markCornerManualControl(TeamId id) {
    if (restartKind == RestartKind.corner && restartTeamId == id) {
      _cornerManualWaitTeamId = id;
      _cornerManualWaitTimer = 3.0;
    }
  }

  bool shouldWaitForKeeperRelease(TeamGame team) {
    final opponent = opponentOf(team);
    final keeperProtected =
        ball.owner == opponent.goalkeeper &&
        isInPenaltyBox(opponent.goalkeeper.pos, opponent.id);
    final goalKickProtected =
        restartKind == RestartKind.goalKick && restartTeamId == opponent.id;
    return keeperProtected || goalKickProtected;
  }

  bool _ballProtectedByKeeperAgainst(TeamId challengingTeamId) {
    final owner = ball.owner;
    if (owner == null || owner.teamId == challengingTeamId) {
      return false;
    }
    final keeperProtected =
        owner.isGoalkeeper && isInPenaltyBox(owner.pos, owner.teamId);
    // Until the restart is taken, the opponent may position itself but cannot
    // tackle or attach to the stationary ball.
    final restartProtected =
        restartKind != null && restartTeamId == owner.teamId;
    return keeperProtected || restartProtected;
  }

  TeamGame? get penaltyShootingTeam =>
      activePenalty == null ? null : teamById(activePenalty!.shootingTeam);

  TeamGame? get penaltyDefendingTeam => activePenalty == null
      ? null
      : opponentOf(teamById(activePenalty!.shootingTeam));

  String get periodTitle => switch (period) {
    MatchPeriod.firstHalf => '1. yari',
    MatchPeriod.secondHalf => '2. yari',
    MatchPeriod.extraFirst => 'Uzatma 1',
    MatchPeriod.extraSecond => 'Uzatma 2',
    MatchPeriod.penalties => 'Penaltilar',
    MatchPeriod.finished => 'Mac bitti',
  };

  String get clockText {
    final shown = minute.clamp(0, 130).toDouble();
    final m = shown.floor();
    final s = ((shown - m) * 60).floor();
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  TeamGame teamById(TeamId id) => id == TeamId.blue ? blueTeam : redTeam;

  TeamGame opponentOf(TeamGame team) =>
      team.id == TeamId.blue ? redTeam : blueTeam;

  TeamGame teamBySide(TeamSide side) =>
      blueTeam.side == side ? blueTeam : redTeam;

  TeamMode teamMode(TeamGame team) {
    if (lateCloseGamePressure && teamUnderDanger(team)) {
      return TeamMode.defense;
    }
    if (ball.owner != null) {
      if (ball.owner!.teamId == team.id) {
        // Protecting a one-goal lead in the last minutes: even in
        // possession the team stays compact and plays it safe. A team
        // under strain does the same.
        if (teamEndgameProtecting(team) || teamUnderStress(team)) {
          return TeamMode.defense;
        }
        return TeamMode.attack;
      }
      // Losing in the last minutes: press hard and look for the goal.
      if (teamEndgameChasing(team)) {
        return TeamMode.press;
      }
      return TeamMode.defense;
    }
    if (team.attackDirection == 1) {
      return ball.pos.x > GameConstants.virtualWidth / 2
          ? TeamMode.press
          : TeamMode.defense;
    }
    return ball.pos.x < GameConstants.virtualWidth / 2
        ? TeamMode.press
        : TeamMode.defense;
  }

  bool get lateCloseGamePressure {
    final closeScore = (blueTeam.score - redTeam.score).abs() <= 1;
    final lateRegulation =
        (period == MatchPeriod.firstHalf || period == MatchPeriod.secondHalf) &&
        minute >= 78;
    final lateExtra =
        (period == MatchPeriod.extraFirst ||
            period == MatchPeriod.extraSecond) &&
        minute >= 112;
    return closeScore && (lateRegulation || lateExtra);
  }

  /// The last stretch of the match, when late tactics kick in.
  bool get endgameActive {
    final regulation = period == MatchPeriod.secondHalf && minute >= 85;
    final firstExtra = period == MatchPeriod.extraFirst && minute >= 106;
    final secondExtra = period == MatchPeriod.extraSecond && minute >= 116;
    return regulation || firstExtra || secondExtra;
  }

  /// A team that leads in the last minutes drops deep and defends hard to
  /// protect the lead.
  bool teamEndgameProtecting(TeamGame team) =>
      endgameActive && team.score > opponentOf(team).score;

  /// A team that trails in the last minutes pushes up and presses hard to
  /// find the equalizer.
  bool teamEndgameChasing(TeamGame team) =>
      endgameActive && team.score < opponentOf(team).score;

  /// Average stamina of the players currently on the pitch.
  double teamAverageStamina(TeamGame team) {
    var sum = 0.0;
    var count = 0;
    for (final player in team.players) {
      if (player.isSentOff) continue;
      sum += player.stamina;
      count += 1;
    }
    return count == 0 ? 1.0 : sum / count;
  }

  bool teamIsTired(TeamGame team) => teamAverageStamina(team) < 0.45;

  int sentOffCount(TeamGame team) =>
      team.players.where((player) => player.isSentOff).length;

  bool teamShortOnPlayers(TeamGame team) {
    final mine = team.players.where((player) => !player.isSentOff).length;
    final theirs =
        opponentOf(team).players.where((player) => !player.isSentOff).length;
    return mine < theirs;
  }

  /// A team under strain — tired players, a red card or a numerical
  /// disadvantage — concentrates on defence and clears every dangerous
  /// ball instead of taking risks.
  bool teamUnderStress(TeamGame team) =>
      teamIsTired(team) ||
      sentOffCount(team) > 0 ||
      teamShortOnPlayers(team);

  bool teamUnderDanger(TeamGame team) {
    final opponentHasBall = ball.owner != null && ball.owner!.teamId != team.id;
    final looseBall = ball.owner == null;
    if (!opponentHasBall && !looseBall) {
      return false;
    }

    final dangerLine = team.side == TeamSide.left
        ? GameConstants.leftBound + GameConstants.pitchWidth * 0.36
        : GameConstants.rightBound - GameConstants.pitchWidth * 0.36;
    final deepNearGoal = team.side == TeamSide.left
        ? ball.pos.x <= dangerLine
        : ball.pos.x >= dangerLine;
    final centralThreat =
        (ball.pos.y - GameConstants.virtualHeight / 2).abs() < 190;
    final towardGoal = team.side == TeamSide.left
        ? ball.vel.x < -1.0
        : ball.vel.x > 1.0;
    return isInPenaltyBox(ball.pos, team.id) ||
        (deepNearGoal && centralThreat) ||
        (deepNearGoal && towardGoal);
  }

  bool shouldAttackersDrop(TeamGame team) {
    return teamUnderDanger(team) ||
        (lateCloseGamePressure && teamMode(team) == TeamMode.defense);
  }

  bool counterOpportunityFor(TeamGame team, PlayerGame player) {
    final deepStart = team.attackDirection == 1
        ? player.pos.x < GameConstants.virtualWidth * 0.46
        : player.pos.x > GameConstants.virtualWidth * 0.54;
    if (!deepStart) {
      return false;
    }
    final opponent = opponentOf(team);
    final opponentsAhead = opponent.players.where((opponentPlayer) {
      if (opponentPlayer.isGoalkeeper) {
        return false;
      }
      final xGap = (opponentPlayer.pos.x - player.pos.x) * team.attackDirection;
      return xGap < 135;
    }).length;
    return lateCloseGamePressure || opponentsAhead >= 3;
  }

  void tick(double dt) {
    if (replayMode) {
      // While the VAR screen is open everyone on the pitch rests and
      // regains stamina.
      _recoverStaminaWhileFrozen(dt);
      _tickReplay(dt);
      return;
    }
    if (finished) {
      return;
    }
    if (substitutionPaused) {
      // The substitution panel is open: players catch their breath.
      _recoverStaminaWhileFrozen(dt);
      return;
    }
    _tickCooldowns(dt);

    if (_pauseTimer > 0) {
      _pauseTimer -= dt;
      _recoverStaminaWhileFrozen(dt);
      _recordReplay(dt);
      if (_pauseTimer <= 0) {
        final callback = _afterPause;
        _afterPause = null;
        banner = null;
        varReviewActive = false;
        varReason = null;
        varReviewCategory = null;
        varRecommendedDecision = null;
        varDecisionOptions = const [];
        _varDecisionResolver = null;
        currentOffside = null;
        callback?.call();
      }
      return;
    }

    if (wallSelectionPending) {
      return;
    }

    if (period == MatchPeriod.penalties) {
      _tickShootout(dt);
      return;
    }

    if (activePenalty != null) {
      if (activePenalty!.result == null) {
        // The keeper stays glued to his goal line until the shot is
        // actually taken — he never wanders off the line beforehand.
        final defending = penaltyDefendingTeam;
        if (defending != null) {
          final keeper = defending.goalkeeper;
          keeper.pos = Vec2(
            defending.side == TeamSide.left
                ? GameConstants.leftBound + 14
                : GameConstants.rightBound - 14,
            GameConstants.virtualHeight / 2,
          );
          keeper
            ..keeperState = 'hazir'
            ..keeperGroundTimer = 0
            ..lastDirection = Vec2(defending.attackDirection.toDouble(), 0);
        }
        _tickAiPenalty(dt);
      } else {
        _tickPenalty(dt);
      }
      return;
    }

    final elapsedGameMinutes = dt / GameConstants.realSecondsPerGameMinute;
    minute += elapsedGameMinutes;
    for (final player in allPlayers) {
      player.minutesThisMatch += elapsedGameMinutes;
    }
    _trackPossession(dt);
    _tickSetPieceAttack(dt);
    _checkPeriodEnd();
    _tickAiAutoControl(dt);

    for (final team in [blueTeam, redTeam]) {
      final opponent = opponentOf(team);
      for (final player in team.players) {
        if (player.isSentOff) {
          continue;
        }
        if (player.isGoalkeeper) {
          _goalkeeperAi.update(
            keeper: player,
            team: team,
            opponent: opponent,
            engine: this,
            dt: dt,
          );
        } else {
          _playerAi.update(
            player: player,
            team: team,
            opponent: opponent,
            engine: this,
            dt: dt,
          );
        }
      }
    }

    _ballPhysics.update(ball, dt);
    _handleBallContacts();
    _handleCornerJostle(dt);
    _preventOverlap();
    _enforceRestartRestrictions();
    _checkOffsideTouch();
    if (_pauseTimer > 0 || varReviewActive) {
      _recordReplay(dt);
      return;
    }
    _checkGoalAndOut();
    _checkThrowIn();
    _recordReplay(dt);
  }

  void moveControlledTeam(TeamId id, Vec2 direction, double dt) {
    if (isFrozen) {
      return;
    }
    if (isGoalKickLockedAgainst(id)) {
      return;
    }
    // Skip if this team is AI-controlled
    if (id == TeamId.blue && blueAiControlled) {
      return;
    }
    if (id == TeamId.red && redAiControlled) {
      return;
    }
    final team = teamById(id);
    final controlled = controlledPlayer(id);
    for (final player in team.players) {
      player.controlled = player == controlled;
    }
    if (direction.isZero) {
      return;
    }
    // The taker must stay at the touchline/corner arc until releasing the ball.
    if ((restartKind == RestartKind.throwIn ||
            restartKind == RestartKind.corner ||
            restartKind == RestartKind.freeKick) &&
        restartTeamId == id &&
        ball.owner == controlled) {
      return;
    }
    final step =
        direction.normalized() *
        controlled.speed *
        _teamStrengthFactor(team) *
        dt *
        60;
    controlled.pos = controlled.pos + step;
    _drainStamina(controlled, step.length);
    final movementDirection = step.normalized(
      Vec2(team.attackDirection.toDouble(), 0),
    );
    controlled
      ..turningIntensity = math.max(
        controlled.turningIntensity,
        ((1 - controlled.lastDirection.normalized().dot(movementDirection)) / 2)
            .clamp(0.0, 1.0)
            .toDouble(),
      )
      ..movementIntensity = math.max(
        controlled.movementIntensity,
        direction.length.clamp(0.0, 1.0).toDouble(),
      )
      ..lastDirection = movementDirection;
    controlled.keepInsideField();
    _clampRestartPosition(controlled);
    controlled.manualOverride = 0.28;
    if (controlled.pos.distanceTo(ball.pos) <
            controlled.radius + GameConstants.ballRadius + 8 &&
        _canReachBall(controlled) &&
        !_isRecentKicker(controlled) &&
        !_ballProtectedByKeeperAgainst(id)) {
      ball.attachTo(controlled);
    }
  }

  /// Auto-switch of the controlled player, per team. When enabled (default)
  /// the game always controls the best player (ball owner when attacking,
  /// the closest chaser when defending). When disabled the player stays on
  /// his chosen man and switches manually (C for blue, Q for red).
  final Map<TeamId, bool> _autoSwitchEnabled = <TeamId, bool>{
    TeamId.blue: true,
    TeamId.red: true,
  };
  final Map<TeamId, String> _manualControlledPlayerIds = <TeamId, String>{};

  bool isAutoSwitchEnabled(TeamId id) => _autoSwitchEnabled[id] ?? true;

  bool toggleAutoSwitch(TeamId id) {
    _autoSwitchEnabled[id] = !isAutoSwitchEnabled(id);
    return isAutoSwitchEnabled(id);
  }

  PlayerGame controlledPlayer(TeamId id) {
    final team = teamById(id);
    // When the team owns the ball, control is always the ball owner.
    if (ball.owner != null && ball.owner!.teamId == id) {
      return ball.owner!;
    }
    // Manual mode: stick to the player the human selected (C/Q keys).
    if (!isAutoSwitchEnabled(id)) {
      final manualId = _manualControlledPlayerIds[id];
      if (manualId != null) {
        final manual = team.players.where(
          (player) =>
              player.id == manualId &&
              !player.isSentOff &&
              player.manualOverride <= 0,
        );
        if (manual.isNotEmpty) {
          return manual.first;
        }
      }
    }
    final includeGoalkeeper =
        ball.owner == team.goalkeeper ||
        team.goalkeeper.pos.distanceTo(ball.pos) <
            GameConstants.goalkeeperRadius + GameConstants.ballRadius + 16;
    return team.closestTo(ball.pos, includeGoalkeeper: includeGoalkeeper);
  }

  /// Switches the controlled player of [id] to the NEXT best man: the next
  /// player who can meet the opponent carrier / ball. When the team owns
  /// the ball the ball owner is always returned.
  PlayerGame switchControlledPlayer(TeamId id) {
    final team = teamById(id);
    if (ball.owner != null && ball.owner!.teamId == id) {
      final owner = ball.owner!;
      _manualControlledPlayerIds[id] = owner.id;
      return owner;
    }
    final anchor = ball.owner != null ? ball.owner!.pos : ball.pos;
    final candidates = team.players
        .where(
          (player) => !player.isSentOff && !player.isGoalkeeper,
        )
        .toList()
      ..sort(
        (a, b) => a.pos
            .distanceTo(anchor)
            .compareTo(b.pos.distanceTo(anchor)),
      );
    if (candidates.isEmpty) {
      return controlledPlayer(id);
    }
    final current = controlledPlayer(id);
    var currentIndex = candidates.indexWhere((p) => p.id == current.id);
    if (currentIndex < 0) {
      currentIndex = -1;
    }
    final next = candidates[(currentIndex + 1) % candidates.length];
    _manualControlledPlayerIds[id] = next.id;
    return next;
  }

  void manualKick(
    TeamId id,
    KickType type,
    double power, {
    PlayerGame? preferredPlayer,
  }) {
    if (isFrozen) {
      return;
    }
    // Skip if this team is AI-controlled
    if (id == TeamId.blue && blueAiControlled) {
      return;
    }
    if (id == TeamId.red && redAiControlled) {
      return;
    }
    final team = teamById(id);
    if (restartKind != null && restartTeamId != id) {
      return;
    }
    if (restartKind == RestartKind.throwIn && type == KickType.shoot) {
      return;
    }
    var player =
        preferredPlayer != null &&
            preferredPlayer.teamId == id &&
            team.players.contains(preferredPlayer)
        ? preferredPlayer
        : controlledPlayer(id);
    if (restartKind == RestartKind.corner && restartTeamId == team.id) {
      _cornerManualWaitTeamId = null;
      _cornerManualWaitTimer = 0;
    }
    if (restartKind == RestartKind.goalKick && ball.owner != null) {
      player = ball.owner!;
    }
    if (ball.owner != player &&
        player.pos.distanceTo(ball.pos) >
            player.radius + GameConstants.ballRadius + 18) {
      if (ball.owner != null && ball.owner!.teamId == id) {
        player = ball.owner!;
      } else {
        return;
      }
    }
    if (restartKind == RestartKind.kickoff && type == KickType.shoot) {
      return;
    }
    if (restartKind == RestartKind.corner &&
        !_cornerPlayersAreSet() &&
        !_cornerReadyOverride) {
      return;
    }

    if (ball.owner == player &&
        player.isGoalkeeper &&
        (type == KickType.pass || type == KickType.highPass)) {
      distributeFromGoalkeeper(
        player,
        high: type == KickType.highPass,
        power: power,
      );
      return;
    }

    final incomingBallSpeed = ball.vel.length;
    final incomingBallHeight = ball.heightMeters;
    final aerialContact = ball.owner == null && ball.heightMeters > 0.35;
    if (aerialContact) {
      final maximumManualReach = player.profile.heightMeters +
          (player.isGoalkeeper ? 0.70 : 0.15);
      if (ball.heightMeters <= maximumManualReach) {
        player.jumpBoostMeters = math.max(
          player.jumpBoostMeters,
          player.isGoalkeeper ? 0.16 : 0.12,
        );
      }
      // A ball above the player's real reach must simply pass overhead.
      if (!_canReachBall(player)) {
        return;
      }
      player.jumpAnimationTimer = player.isGoalkeeper ? 0.62 : 0.48;
    } else if (ball.owner != player) {
      ball.attachTo(player);
    }

    // The maximum shot power depends on the player's shot-power rating:
    // weak shooters physically cannot hit rockets, strong ones can.
    final maxPower = type == KickType.highPass
        ? restartKind == RestartKind.goalKick
            ? 2.65
            : restartKind == RestartKind.corner
            ? 2.40
            : 1.95
        : type == KickType.shoot
        ? (1.18 + player.profile.shotPowerRating / 100.0 * 0.52)
              .clamp(1.18, 1.70)
              .toDouble()
        : 1.45;
    final clampedPower = power.clamp(0.55, maxPower).toDouble();
    final direction = player.lastDirection.normalized(
      Vec2(team.attackDirection.toDouble(), 0),
    );
    PlayerGame? target;
    var kickDirection = direction;
    var loft = 0.0;
    var finalPower = clampedPower;
    ShotResult? shotResult;

    if (type == KickType.shoot) {
      shotResult = _calculateShot(
        player,
        team,
        clampedPower,
        firstTime: aerialContact,
        incomingBallSpeed: incomingBallSpeed,
        incomingBallHeight: incomingBallHeight,
        freeKick: restartKind == RestartKind.freeKick,
      );
      kickDirection = shotResult.launchTarget - ball.pos;
      loft = shotResult.verticalVelocity;
      finalPower = shotResult.power;
      shotDiagnostics.record(shotResult);
    } else if (restartKind == RestartKind.corner) {
      final highDelivery = type == KickType.highPass;
      final candidates = team.players.where(
        (mate) =>
            mate != player &&
            !mate.isGoalkeeper &&
            (highDelivery
                ? mate.pos.distanceTo(goalCenterFor(team)) < 270
                : mate.pos.distanceTo(player.pos) < 260),
      );
      target = chooseBestPass(player, candidates, preferForward: false);
      kickDirection =
          (target?.pos ?? _cornerDeliverySpot(team, high: highDelivery)) -
          ball.pos;
      if (highDelivery) {
        // The long-pass button sends the cross arcing into the penalty
        // area; the ball arrives over the box at a head-ball height of
        // 1.80-2.20 m (computed by simulating the flight).
        final landingPos =
            target?.pos ?? _cornerDeliverySpot(team, high: true);
        final computed = _cornerHighBallParams(player, landingPos, clampedPower);
        loft = computed.$1;
        finalPower = computed.$2;
      } else {
        finalPower = 0.74 + clampedPower * 0.22;
      }
    } else if (restartKind == RestartKind.throwIn) {
      // Throw-in: even the long-pass button makes a short, safe toss to
      // the nearest teammate — never a long ball.
      final mates = team.players.where(
        (mate) => mate != player && !mate.isGoalkeeper && !mate.isSentOff,
      ).toList()
        ..sort(
          (a, b) => a.pos
              .distanceTo(player.pos)
              .compareTo(b.pos.distanceTo(player.pos)),
        );
      target = mates.isEmpty ? null : mates.first;
      kickDirection = target == null ? direction : target.pos - ball.pos;
      loft = 1.5 + clampedPower * 0.6;
      finalPower = 0.52 + clampedPower * 0.20;
    } else {
      target = player.isGoalkeeper
          ? chooseBestPass(
              player,
              team.players.where(
                (mate) =>
                    mate != player && !mate.isGoalkeeper && !mate.isSentOff,
              ),
              preferForward: true,
            )
          : _targetInDirection(team, player, direction);
      kickDirection = target == null
          ? (player.isGoalkeeper
                ? Vec2(team.attackDirection.toDouble(), 0)
                : direction)
          : target.pos - ball.pos;
      if (type == KickType.highPass) {
        final keeperGoalKick =
            restartKind == RestartKind.goalKick && player.isGoalkeeper;
        loft = keeperGoalKick
            ? 8.5 + clampedPower * 3.8
            : 5.35 + clampedPower * 1.55;
        finalPower = keeperGoalKick
            ? 0.95 + clampedPower * 0.33
            : 0.78 + clampedPower * 0.23;
      } else {
        finalPower = 0.62 + clampedPower * 0.25;
      }
    }

    if (aerialContact && type != KickType.shoot) {
      // Aerial passes redirect the incoming ball and retain part of its lift.
      finalPower *= 0.68;
      final retainedLift = ball.verticalVelocity > 0
          ? ball.verticalVelocity * 0.55
          : 1.15;
      loft = math.max(loft * 0.52, retainedLift).clamp(0.85, 2.45).toDouble();
    }

    releaseFromPlayer(
      player,
      kickDirection,
      finalPower,
      type: type,
      target: target,
      loft: loft,
      curve: shotResult?.curve ?? 0,
      spin: shotResult == null ? 0 : shotResult.curve.abs(),
      shotType: shotResult?.shotType,
    );
    player.manualOverride = 0.36;
  }

  void selectPenaltyShot(PenaltyLane lane) {
    activePenalty?.shotDirection = lane;
  }

  void selectPenaltyKeeper(PenaltyLane lane) {
    activePenalty?.keeperDirection = lane;
  }

  void cyclePenaltyShooter() {
    final penalty = activePenalty;
    if (penalty == null || penalty.result != null) {
      return;
    }
    final shooting = teamById(penalty.shootingTeam);
    final shooters = shooting.players
        .where((player) => !player.isGoalkeeper && !player.isSentOff)
        .toList();
    if (shooters.length < 2) {
      return;
    }
    final currentIndex = shooters.indexWhere((p) => p.id == penalty.shooterId);
    final next = shooters[(currentIndex + 1) % shooters.length];
    penalty.shooterId = next.id;
    final shootingRight = shooting.side == TeamSide.left;
    final spotX = shootingRight
        ? GameConstants.rightBound - 88
        : GameConstants.leftBound + 88;
    next
      ..pos = Vec2(spotX, GameConstants.virtualHeight / 2)
      ..lastDirection = Vec2(shooting.attackDirection.toDouble(), 0);
    ball
      ..owner = next
      ..pos = next.pos + Vec2(shooting.attackDirection * 16, 0)
      ..vel = Vec2.zero()
      ..heightMeters = 0
      ..verticalVelocity = 0;
  }

  void takeInteractivePenalty(double power) {
    final penalty = activePenalty;
    if (penalty == null || penalty.result != null) {
      return;
    }
    final shooting = teamById(penalty.shootingTeam);
    final defending = opponentOf(shooting);
    if (isTeamAiControlled(defending.id)) {
      final keeperStats = defending.goalkeeper.profile.goalkeeperStats;
      final readAbility = keeperStats.reaction * 0.42 +
          keeperStats.anticipation * 0.34 +
          keeperStats.oneVsOne * 0.24;
      final readsShot = random.nextDouble() <
          (0.12 + readAbility * 0.40) * aiDifficulty.anticipationFactor;
      penalty.keeperDirection = readsShot
          ? penalty.shotDirection
          : PenaltyLane.values[random.nextInt(PenaltyLane.values.length)];
    }
    final result = _penaltyLogic.takeSelectedKick(
      shootingTeam: shooting,
      defendingTeam: defending,
      kickIndex: shooting.goals.length + (shootout?.results.length ?? 0),
      minute: penalty.minute,
      shotDirection: penalty.shotDirection,
      keeperDirection: penalty.keeperDirection,
      power: power,
      selectedShooter: shooting.playerById(penalty.shooterId),
    );
    penalty
      ..result = result
      ..countdown = 2.6;
    banner = MatchBanner(
      result.scored ? 'PENALTI GOL' : 'PENALTI KACIRDI',
      result.summary,
      2.6,
    );
    _startPenaltyVisual(shooting, defending, result);
    if (penalty.shootout) {
      shootout?.results.add(result);
    } else if (result.scored) {
      _recordPenaltyGoal(shooting, result);
    }
  }

  void skipCurrentReview() {
    if (_pauseTimer <= 0) {
      return;
    }
    if (varReviewActive && varRecommendedDecision != null) {
      resolveVarDecision(varRecommendedDecision!);
      return;
    }
    final callback = _afterPause;
    _pauseTimer = 0;
    _afterPause = null;
    banner = null;
    varReviewActive = false;
    varReason = null;
    currentOffside = null;
    callback?.call();
  }

  void setFormation(TeamId id, FormationType formation) {
    final team = teamById(id);
    team.formation = formation;
    team.updateHomePositionsOnly();
  }

  void cycleFormation(TeamId id) {
    final team = teamById(id);
    team.formation = team.formation.next;
    team.updateHomePositionsOnly();
    _startPause(
      '${team.name}: ${team.formation.title}',
      'Dizilis degisti',
      1.0,
      null,
    );
  }

  /// Assigns the nearest suitable teammate to a space vacated by a player.
  Vec2? coverageTargetFor(PlayerGame player, TeamGame team) {
    if (player.isGoalkeeper || ball.owner == player || player.restartTarget != null) {
      return null;
    }
    PlayerGame? vacancy;
    var bestDistance = 0.0;
    for (final teammate in team.players) {
      if (teammate == player || teammate.isGoalkeeper || ball.owner == teammate) {
        continue;
      }
      final departed = teammate.pos.distanceTo(teammate.homePos);
      if (departed < 118) {
        continue;
      }
      final closestCover = team.players
          .where((candidate) => candidate != teammate && !candidate.isGoalkeeper)
          .reduce((a, b) => a.pos.distanceTo(teammate.homePos) <
                  b.pos.distanceTo(teammate.homePos)
              ? a
              : b);
      if (closestCover == player && departed > bestDistance) {
        vacancy = teammate;
        bestDistance = departed;
      }
    }
    return vacancy?.homePos.copy();
  }

  void moveTowards(PlayerGame player, Vec2 target, double force, double dt) {
    final diff = target - player.pos;
    if (diff.lengthSquared <= 1) {
      return;
    }
    var step =
        diff.normalized() *
        player.speed *
        _teamStrengthFactor(teamById(player.teamId)) *
        force *
        dt *
        60;
    if (step.length > diff.length) {
      step = diff;
    }
    player.pos = player.pos + step;
    _drainStamina(player, step.length);
    if (!step.isZero) {
      final movementDirection = step.normalized();
      player
        ..turningIntensity = math.max(
          player.turningIntensity,
          ((1 - player.lastDirection.normalized().dot(movementDirection)) / 2)
              .clamp(0.0, 1.0)
              .toDouble(),
        )
        ..movementIntensity = math.max(
          player.movementIntensity,
          force.clamp(0.0, 1.0).toDouble(),
        )
        ..lastDirection = movementDirection;
    }
    player.keepInsideField();
    _clampRestartPosition(player);
  }

  bool distributeFromGoalkeeper(
    PlayerGame keeper, {
    required bool high,
    double power = 1.0,
  }) {
    if (!keeper.isGoalkeeper ||
        ball.owner != keeper ||
        isFrozen ||
        keeper.keeperGroundTimer > 0) {
      return false;
    }
    final team = teamById(keeper.teamId);
    final goalKick = isGoalKickPendingFor(team);
    final candidates = team.players.where(
      (mate) => mate != keeper && !mate.isGoalkeeper && !mate.isSentOff,
    );
    final opponent = opponentOf(team);
    final preferred = high
        ? candidates.where(
            (mate) => mate.role.isAttacker || mate.role.isWide,
          )
        : candidates.where(
            (mate) =>
                mate.role.isDefender ||
                mate.role == PlayerRole.midfieldLeft ||
                mate.role == PlayerRole.midfieldRight ||
                mate.role == PlayerRole.sweeper,
          );
    // A normal keeper throw/clearance must never fly to the opposite goal:
    // high throws are capped to a short-to-mid distance (~430 px).
    final capped = high && !goalKick
        ? candidates.where(
            (mate) => keeper.pos.distanceTo(mate.pos) <= 430,
          )
        : candidates;
    // Fallback for a high throw: the nearest teammate still inside the
    // capped distance — never someone at the other end of the pitch.
    PlayerGame? nearestCapped;
    var nearestCappedDistance = double.infinity;
    for (final mate in capped) {
      final distance = keeper.pos.distanceTo(mate.pos);
      if (distance < nearestCappedDistance) {
        nearestCappedDistance = distance;
        nearestCapped = mate;
      }
    }
    final target =
        // Short distribution: pass to the nearest OPEN teammate (the one
        // with no opponent marking him). If everyone is marked, fall back
        // to the nearest candidate.
        high
        ? (chooseBestPass(
                keeper,
                preferred.isEmpty ? capped : preferred.where(capped.contains),
                preferForward: true,
              ) ??
              nearestCapped ??
              team.closestTo(keeper.homePos, includeGoalkeeper: false))
        : _nearestOpenTeammate(
            keeper,
            preferred.isEmpty ? capped : preferred,
            opponent,
            team,
          );
    final forward = Vec2(team.attackDirection.toDouble(), 0);
    ball.pos = keeper.pos +
        forward * (keeper.radius + GameConstants.ballRadius + 8);
    double releaseLoft;
    double releasePower;
    if (high && goalKick) {
      // A goal-kick long ball must come to rest past a quarter of the pitch
      // and before its last third — never rocket to the far end of the
      // field. The exact launch power is computed by simulating the flight.
      final computed = _goalKickLongPassParams(keeper, target);
      releaseLoft = computed.$1;
      releasePower = computed.$2;
    } else {
      final clampedPower = power.clamp(0.72, goalKick ? 2.35 : 1.35).toDouble();
      releasePower = (high
              ? math.max(
                  clampedPower,
                  1.15 - keeper.profile.goalkeeperStats.distribution * 0.25,
                )
              : math.max(clampedPower, 0.82))
          .toDouble();
      releaseLoft = high
          ? (3.2 + keeper.profile.goalkeeperStats.distribution * 0.9)
          : 0;
    }
    releaseFromPlayer(
      keeper,
      target.pos - ball.pos,
      releasePower,
      type: high ? KickType.highPass : KickType.pass,
      target: target,
      loft: releaseLoft,
    );
    keeper
      ..catchTimer = 0
      ..keeperParryCooldown = math.max(keeper.keeperParryCooldown, 0.48)
      ..manualOverride = 0.42
      ..lastDirection = forward;
    return ball.owner == null && ball.vel.length > 0.1;
  }

  /// Picks the loft and release power for a goal-kick long ball so the ball
  /// comes to rest between just past a quarter of the pitch and its middle,
  /// measured from the keeper's own goal line — and never beyond the
  /// intended receiver. Mirrors [BallPhysics] frame by frame so the result
  /// is predictable.
  (double, double) _goalKickLongPassParams(PlayerGame keeper, PlayerGame target) {
    final team = teamById(keeper.teamId);
    final dir = team.attackDirection;
    final ownGoalX = team.side == TeamSide.left
        ? GameConstants.leftBound.toDouble()
        : GameConstants.rightBound.toDouble();
    final fraction = 0.40 + random.nextDouble() * 0.12;
    var restX = ownGoalX + dir * GameConstants.pitchWidth * fraction;
    // Never send the ball past the intended receiver.
    if (dir == 1 && restX > target.pos.x - 20) restX = target.pos.x;
    if (dir == -1 && restX < target.pos.x + 20) restX = target.pos.x;
    final distance =
        (Vec2(restX, target.pos.y) - ball.pos).length.clamp(240.0, 780.0).toDouble();
    final passSkill = keeper.profile.passSkill;
    final baseSpeed = 7.6 + passSkill * 2.0;
    final powerFactor =
        0.76 + keeper.stamina * 0.12 + keeper.profile.passSkill * 0.18;
    const loft = 11.5;
    var bestPower = 1.0;
    var bestError = double.infinity;
    for (var candidate = 0.60; candidate <= 2.001; candidate += 0.05) {
      final power = candidate.toDouble();
      final launch = baseSpeed * power * powerFactor;
      final rest = _simulateHighPassRestDistance(launch, loft);
      final error = (rest - distance).abs();
      if (error < bestError) {
        bestError = error;
        bestPower = power;
      }
    }
    return (loft, bestPower);
  }

  /// Picks the loft for a corner cross so the ball arrives over the penalty
  /// area at a head-ball height of 1.80–2.20 m when it has covered the
  /// distance to [landingPos]. [clampedPower] is the user's power input; a
  /// single press of the long-pass button keeps the launch speed in a
  /// controlled band instead of firing a rocket over everyone's head.
  (double, double) _cornerHighBallParams(
    PlayerGame player,
    Vec2 landingPos,
    double clampedPower,
  ) {
    final distance = (landingPos - ball.pos).length.clamp(80.0, 430.0).toDouble();
    final passSkill = player.profile.passSkill;
    final baseSpeed = 7.6 + passSkill * 2.0;
    final powerFactor =
        0.76 + player.stamina * 0.12 + player.profile.passSkill * 0.18;
    final power = (0.92 + clampedPower * 0.10).clamp(0.92, 1.25).toDouble();
    final launch = (baseSpeed * power * powerFactor).clamp(3.0, 11.2).toDouble();
    final targetHeight = 1.80 + random.nextDouble() * 0.40;
    double coveredAtArrival(double loft) =>
        _highPassDistanceAtHeight(launch, loft, targetHeight);
    var low = 1.0;
    var high = 13.0;
    final atHigh = coveredAtArrival(high);
    final atLow = coveredAtArrival(low);
    if (atHigh < 0 || atHigh < distance) {
      // Even the highest arc falls short of the landing spot: use the
      // highest arc so the ball drops as close as possible.
      return (13.0, power);
    }
    if (atLow >= distance) {
      // Even the flattest arc overshoots: use the lowest possible arc.
      return (1.0, power);
    }
    for (var i = 0; i < 26; i++) {
      final mid = (low + high) / 2;
      final covered = coveredAtArrival(mid);
      if (covered < 0 || covered < distance) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return (((low + high) / 2).clamp(1.0, 13.0).toDouble(), power);
  }

  /// Simulates a high pass launched at [launchSpeed] px/frame with vertical
  /// velocity [loft] m/s and returns the total horizontal distance (px) the
  /// ball travels before coming to rest. Mirrors [BallPhysics.update].
  double _simulateHighPassRestDistance(double launchSpeed, double loft) {
    const dt = 1.0 / 60.0;
    const airDrag = 0.986;
    const groundDrag = 0.985;
    const airLimit = 11.2;
    var speed = launchSpeed;
    var height = 0.08;
    var vertical = loft;
    final cruise = launchSpeed * 0.34;
    var bounced = false;
    var distance = 0.0;
    for (var frame = 0; frame < 2400; frame++) {
      distance += speed;
      final previousHeight = height;
      height += vertical * dt;
      vertical -= GameConstants.gravityMeters * dt;
      if (height <= 0) {
        if (previousHeight > 0.05 && vertical < -0.25) {
          height = 0;
          vertical = -vertical * 0.46;
          speed *= 0.82;
          bounced = true;
          if (vertical < 0.8) vertical = 0;
        } else {
          height = 0;
          vertical = 0;
        }
      }
      final inAir = height > 0.08;
      speed *= inAir ? airDrag : groundDrag;
      if (inAir && speed > airLimit) speed = airLimit;
      if (!bounced && height > 0.25 && speed < cruise) speed = cruise;
      if (speed < 0.07) speed = 0;
      if (speed == 0 && vertical == 0) break;
    }
    return distance;
  }

  /// Simulates a high pass and returns the horizontal distance (px) covered
  /// at the moment the ball is falling through [arrivalHeight] meters while
  /// still in the air. Returns -1 if the ball never reaches that height on
  /// a downward flight.
  double _highPassDistanceAtHeight(
    double launchSpeed,
    double loft,
    double arrivalHeight,
  ) {
    const dt = 1.0 / 60.0;
    const airDrag = 0.986;
    const groundDrag = 0.985;
    const airLimit = 11.2;
    var speed = launchSpeed;
    var height = 0.08;
    var vertical = loft;
    final cruise = launchSpeed * 0.34;
    var distance = 0.0;
    for (var frame = 0; frame < 1200; frame++) {
      distance += speed;
      height += vertical * dt;
      vertical -= GameConstants.gravityMeters * dt;
      if (height <= 0) {
        return -1;
      }
      final inAir = height > 0.08;
      speed *= inAir ? airDrag : groundDrag;
      if (inAir && speed > airLimit) speed = airLimit;
      if (height > 0.25 && speed < cruise) speed = cruise;
      if (height <= arrivalHeight && vertical < 0) {
        return distance;
      }
    }
    return -1;
  }

  /// Nearest teammate who is open (no opponent within ~55 px). If all are
  /// marked, returns the closest candidate regardless.
  PlayerGame _nearestOpenTeammate(
    PlayerGame passer,
    Iterable<PlayerGame> candidates,
    TeamGame opponent,
    TeamGame team,
  ) {
    PlayerGame? openBest;
    var openDistance = double.infinity;
    PlayerGame? anyBest;
    var anyDistance = double.infinity;
    for (final mate in candidates) {
      if (mate == passer || mate.isSentOff) {
        continue;
      }
      final distance = passer.pos.distanceTo(mate.pos);
      final nearestOpponent = opponent.players
          .map((opp) => opp.pos.distanceTo(mate.pos))
          .reduce(math.min);
      if (nearestOpponent > 55 && distance < openDistance) {
        openDistance = distance;
        openBest = mate;
      }
      if (distance < anyDistance) {
        anyDistance = distance;
        anyBest = mate;
      }
    }
    return openBest ?? anyBest ?? team.closestTo(passer.homePos, includeGoalkeeper: false);
  }

  void releaseFromPlayer(
    PlayerGame player,
    Vec2 direction,
    double power, {
    required KickType type,
    PlayerGame? target,
    double loft = 0,
    double curve = 0,
    double spin = 0,
    ShotType? shotType,
  }) {
    final team = teamById(player.teamId);
    var adjustedDirection = direction;
    final skill = type == KickType.shoot
        ? player.profile.shotSkill
        : player.profile.passSkill;
    final dippingFreeKick =
        restartKind == RestartKind.freeKick && type == KickType.shoot;
    var adjustedPower = type == KickType.shoot
        ? power
        : power * (0.76 + player.stamina * 0.12 + skill * 0.18);
    if (type != KickType.shoot &&
        (player.errorFactor > 0 || skill < 0.90)) {
      final side = Vec2(-adjustedDirection.y, adjustedDirection.x).normalized();
      final errorScale = 92.0 * (1.18 - skill * 0.55);
      adjustedDirection +=
          side *
          ((random.nextDouble() - 0.5) * player.errorFactor * errorScale);
    }
    _recordKickStats(
      player,
      team,
      type,
      adjustedDirection,
      power: adjustedPower,
      loft: loft,
      curve: curve,
    );
    ball.release(
      direction: adjustedDirection,
      power: adjustedPower,
      toucher: player,
      receiver: target,
      kickType: type,
      loft: loft,
      highPass: type == KickType.highPass,
      dippingFreeKick: dippingFreeKick,
      curve: curve,
      spin: spin,
      shotType: shotType,
    );
    _recentKicker = player;
    _recentKickerGrace = type == KickType.highPass
        ? 0.30
        : type == KickType.shoot
        ? 0.22
        : 0.24;
    if (player.isGoalkeeper) {
      // Do not allow the keeper to chase and immediately collect his own
      // distribution. The lock ends early in practice as soon as another
      // player touches the ball because lastTouch then changes.
      player.keeperRehandleCooldown = math.max(
        player.keeperRehandleCooldown,
        1.35,
      );
    }
    player.lastDirection = adjustedDirection.normalized(
      Vec2(team.attackDirection.toDouble(), 0),
    );
    _finishRestartFor(team);

    if (_offsideExemptNextKick) {
      _offsideExemptNextKick = false;
      _offsideCandidate = null;
      return;
    }

    if (type == KickType.pass ||
        type == KickType.highPass ||
        type == KickType.shoot) {
      _offsideCandidate = _offsideLogic.evaluatePass(
        attackingTeam: team,
        defendingTeam: opponentOf(team),
        passer: player,
        receiver: target,
        ball: ball,
        minute: minute,
        highPass: type == KickType.highPass,
      );
    }
  }

  PlayerGame? chooseBestPass(
    PlayerGame passer,
    Iterable<PlayerGame> candidates, {
    required bool preferForward,
  }) {
    final team = teamById(passer.teamId);
    final opponent = opponentOf(team);
    final d = team.attackDirection;
    PlayerGame? best;
    var bestScore = -999999.0;
    for (final mate in candidates) {
      if (mate == passer || mate.isSentOff) {
        continue;
      }
      final distance = passer.pos.distanceTo(mate.pos);
      if (distance < 28) {
        continue;
      }
      final nearestOpponent = opponent.players
          .map((opp) => opp.pos.distanceTo(mate.pos))
          .reduce(math.min);
      final forwardBonus = preferForward
          ? (mate.pos.x - passer.pos.x) * d
          : 0.0;
      final widthBonus = mate.role.isWide
          ? (mate.pos.y - GameConstants.virtualHeight / 2).abs() * 0.08
          : 0.0;
      final distancePenalty = (distance - 180).abs() * 0.08;
      var score =
          nearestOpponent * 1.45 +
          forwardBonus * 0.75 +
          widthBonus -
          distancePenalty;
      if (mate.role == PlayerRole.striker && preferForward) {
        score += 32;
      }
      if (score > bestScore) {
        bestScore = score;
        best = mate;
      }
    }
    return best;
  }

  Vec2 goalCenterFor(TeamGame attackingTeam) {
    return Vec2(
      attackingTeam.side == TeamSide.left
          ? GameConstants.rightBound + 8
          : GameConstants.leftBound - 8,
      GameConstants.virtualHeight / 2,
    );
  }

  bool isInPenaltyBox(Vec2 pos, TeamId defendingTeamId) {
    final team = teamById(defendingTeamId);
    final minX = team.side == TeamSide.left
        ? GameConstants.leftBound
        : GameConstants.rightBound - 135;
    final maxX = team.side == TeamSide.left
        ? GameConstants.leftBound + 135
        : GameConstants.rightBound;
    return pos.x >= minX &&
        pos.x <= maxX &&
        pos.y >= GameConstants.virtualHeight / 2 - 130 &&
        pos.y <= GameConstants.virtualHeight / 2 + 130;
  }

  void resetKickoff(TeamId ownerTeam) {
    blueTeam.resetPositions();
    redTeam.resetPositions();
    _offsideCandidate = null;
    _offsideExemptNextKick = false;
    setPieceAttackTeamId = null;
    setPieceAttackTimer = 0;
    _cornerManualWaitTeamId = null;
    _cornerManualWaitTimer = 0;
    _cornerReadyOverride = false;
    restartKind = RestartKind.kickoff;
    restartTeamId = ownerTeam;
    _restartSpot = Vec2(
      GameConstants.virtualWidth / 2,
      GameConstants.virtualHeight / 2,
    );
    _lockedWallPlayerIds.clear();
    _lockedWallPositions.clear();
    final kickoffTeam = teamById(ownerTeam);
    final owner = kickoffTeam.players.firstWhere(
      (player) => !player.isSentOff && player.role == PlayerRole.striker,
      orElse: () => kickoffTeam.players.firstWhere(
        (player) => !player.isSentOff && !player.isGoalkeeper,
      ),
    );
    ball
      ..pos = Vec2(
        GameConstants.virtualWidth / 2,
        GameConstants.virtualHeight / 2,
      )
      ..vel = Vec2.zero()
      ..heightMeters = 0
      ..verticalVelocity = 0
      ..owner = owner
      ..lastTouch = owner
      ..lastPasser = null
      ..potentialAssister = null
      ..intendedReceiver = null
      ..lastKickType = null
      ..lastPassWasHigh = false
      ..hasBouncedSinceKick = false
      ..goalLineMissCommitted = false
      ..curve = 0
      ..spin = 0
      ..shotType = null;
  }

  void _tickCooldowns(double dt) {
    if (_pauseTimer <= 0) {
      _cornerManualWaitTimer = math.max(0, _cornerManualWaitTimer - dt);
      if (_cornerManualWaitTimer <= 0) {
        _cornerManualWaitTeamId = null;
      }
    }
    _recentKickerGrace = math.max(0, _recentKickerGrace - dt);
    if (_recentKickerGrace <= 0) {
      _recentKicker = null;
    }
    for (final player in allPlayers) {
      player.aiCooldown = math.max(0, player.aiCooldown - dt);
      player.tackleContactCooldown = math.max(
        0,
        player.tackleContactCooldown - dt,
      );
      player.handballReviewCooldown = math.max(
        0,
        player.handballReviewCooldown - dt,
      );
      player.manualOverride = math.max(0, player.manualOverride - dt);
      player.movementIntensity = math.max(
        0,
        player.movementIntensity - dt * 1.35,
      );
      player.turningIntensity = math.max(
        0,
        player.turningIntensity - dt * 2.4,
      );
      player.keeperGroundTimer = math.max(0, player.keeperGroundTimer - dt);
      player.keeperDiveCooldown = math.max(0, player.keeperDiveCooldown - dt);
      player.keeperParryCooldown = math.max(
        0,
        player.keeperParryCooldown - dt,
      );
      player.keeperRehandleCooldown = math.max(
        0,
        player.keeperRehandleCooldown - dt,
      );
      player.jumpAnimationTimer = math.max(0, player.jumpAnimationTimer - dt);
      if (player.isGoalkeeper) {
        if (player.keeperGroundTimer <= 0) {
          player.keeperState = ball.owner == player ? 'top elde' : 'hazir';
        } else if (player.jumpAnimationTimer <= 0.10 &&
            ball.owner != player) {
          player.keeperState = 'yerde';
        }
      }
      if (player.jumpBoostMeters > 0) {
        player.jumpBoostMeters = math.max(
          0,
          player.jumpBoostMeters - dt * 0.35,
        );
      }
    }
  }

  void _handleBallContacts() {
    final sorted = allPlayers
      ..sort(
        (a, b) =>
            a.pos.distanceTo(ball.pos).compareTo(b.pos.distanceTo(ball.pos)),
      );

    if (ball.owner != null) {
      final owner = ball.owner!;
      if (_ballProtectedByKeeperAgainst(owner.teamId.opponent)) {
        return;
      }
      // A teammate who is NOT the controlled player can take possession
      // from the controlled carrier by running right next to him (a
      // one-touch pass via the run).
      if (!isTeamAiControlled(owner.teamId) &&
          ball.owner == controlledPlayer(owner.teamId)) {
        for (final mate in sorted.where(
          (p) => p.teamId == owner.teamId && p != owner && !p.isSentOff,
        )) {
          if (mate.controlled) {
            continue;
          }
          if (mate.pos.distanceTo(owner.pos) >=
              mate.radius + owner.radius + 3) {
            continue;
          }
          if (mate.tackleContactCooldown > 0) {
            continue;
          }
          mate.tackleContactCooldown = 0.8;
          owner.tackleContactCooldown = 0.8;
          ball.attachTo(mate);
          return;
        }
      }
      for (final defender in sorted.where((p) => p.teamId != owner.teamId)) {
        if (defender.pos.distanceTo(owner.pos) <
            defender.radius + owner.radius + 3) {
          if (defender.tackleContactCooldown > 0) {
            return;
          }
          final defendingTeam = teamById(defender.teamId);
          final cautious = defender.yellowCardsThisMatch > 0;
          final tackleChance =
              (defender.role.isDefender ? 0.34 : 0.22) *
              (cautious ? 0.72 : 1.0);
          final lateContact =
              (owner.pos.x - defender.pos.x) *
                  teamById(owner.teamId).attackDirection >
              8;
          final contactSeverity =
              random.nextDouble() +
              (lateContact ? 0.18 : 0) +
              (defender.manualOverride > 0 ? 0.08 : 0) +
              (1 - defender.stamina) * 0.12 -
              (cautious ? 0.24 : 0);
          final extremelyViolent = contactSeverity >= 1.22;
          final violent = contactSeverity >= 0.94;
          final reckless = contactSeverity >= 0.74;
          // Only an extreme collision (impact >= 1.30 — a genuinely
          // reckless late tackle) can injure the player even without a
          // foul being called. Injuries are intentionally rare.
          if (contactSeverity >= 1.30) {
            _checkInjury(owner, violent: true, reckless: true);
          }
          var foulChance =
              0.006 +
              (lateContact ? 0.035 : 0) +
              (reckless ? 0.10 : 0) +
              (violent ? 0.20 : 0) +
              (extremelyViolent ? 0.42 : 0);
          if (cautious) {
            foulChance *= 0.55;
          }
          defender.tackleContactCooldown = cautious ? 0.95 : 0.68;
          if (random.nextDouble() < foulChance) {
            final foulSpot = owner.pos.copy();
            final inBox = isInPenaltyBox(foulSpot, defendingTeam.id);
            final recommended = extremelyViolent
                ? 'red'
                : violent
                ? 'yellow'
                : 'foul';
            _startVarDecision(
              title: inBox ? 'VAR PENALTI KONTROLU' : 'VAR FAUL KONTROLU',
              reason:
                  '${defender.profile.name}: temas siddeti ${contactSeverity.toStringAsFixed(2)}',
              category: inBox ? 'penalty' : 'foul',
              recommendedDecision: recommended,
              options: const ['playOn', 'foul', 'yellow', 'red'],
              resolve: (decision) {
                if (decision == 'playOn') {
                  defender.tackleContactCooldown = 1.1;
                  defender.pos = defender.pos -
                      Vec2(
                        teamById(owner.teamId).attackDirection * 5.0,
                        0,
                      );
                  return;
                }
                _applyReviewedFoul(
                  victim: owner,
                  fouler: defender,
                  foulSpot: foulSpot,
                  inPenaltyBox: inBox,
                  violent: violent,
                  reckless: reckless,
                  cardDecision: decision,
                );
              },
            );
            return;
          }
          if (random.nextDouble() < tackleChance) {
            if (defender.role.isDefender || defender.isGoalkeeper) {
              defender.profile.clearances += 1;
              defender.matchClearances += 1;
            }
            defender.matchTackles += 1;
            defender.profile.tackles += 1;
            ball.attachTo(defender);
          } else {
            // Attacker kept the ball - successful dribble
            owner.matchDribbles += 1;
            owner.matchSuccessfulDribbles += 1;
          }
          return;
        }
      }
      return;
    }

    for (final player in sorted) {
      if (player.isGoalkeeper &&
          (player.keeperParryCooldown > 0 ||
              (player.keeperRehandleCooldown > 0 &&
                  ball.lastTouch == player))) {
        continue;
      }
      if (player.pos.distanceTo(ball.pos) >
          player.radius +
              GameConstants.ballRadius +
              (ball.heightMeters > 0.8 ? 11 : 6)) {
        continue;
      }
      if (_isRecentKicker(player)) {
        continue;
      }

      // Any opponent touch on a pass (even a deflection) means the pass
      // was not "clean": it no longer counts as a successful pass.
      if (ball.potentialAssister != null &&
          ball.potentialAssister!.teamId != player.teamId) {
        ball.potentialAssister = null;
      }

      if (_isLogicalHandball(player)) {
        final attackingTeam = ball.lastTouch?.teamId;
        if (attackingTeam != null && attackingTeam != player.teamId) {
          final foulSpot = player.pos.copy();
          final contactHeight = ball.heightMeters;
          final attacker = ball.lastTouch;
          final inBox = isInPenaltyBox(foulSpot, player.teamId);
          player.handballReviewCooldown = 6.0;
          final recommended = ball.lastKickType == KickType.shoot
              ? 'yellow'
              : 'handball';
          _startVarDecision(
            title: inBox ? 'VAR EL / PENALTI' : 'VAR EL KONTROLU',
            reason:
                '${player.profile.name}: yanal kol temasi ${contactHeight.toStringAsFixed(2)} m',
            category: 'handball',
            recommendedDecision: recommended,
            options: const ['playOn', 'handball', 'yellow', 'red'],
            resolve: (decision) {
              if (decision == 'playOn') {
                return;
              }
              _applyReviewedHandball(
                offender: player,
                attacker: attacker,
                attackingTeam: attackingTeam,
                foulSpot: foulSpot,
                inPenaltyBox: inBox,
                cardDecision: decision,
              );
            },
          );
          return;
        }
      }

      if (!_canReachBall(player)) {
        continue;
      }

      if (ball.heightMeters > 1.15 && !player.isGoalkeeper) {
        player
          ..jumpBoostMeters = math.max(player.jumpBoostMeters, 0.11)
          ..jumpAnimationTimer = 0.48;
        final team = teamById(player.teamId);
        final goal = goalCenterFor(team);
        final forward = Vec2(team.attackDirection.toDouble(), 0);
        final headerTarget =
            player.role.isAttacker && player.pos.distanceTo(goal) < 210
            ? goal - ball.pos
            : forward;
        releaseFromPlayer(
          player,
          headerTarget,
          0.82,
          type: KickType.pass,
          loft: 0.4,
        );
        return;
      }

      if (!_canSecureControl(player)) {
        _deflectFromPlayer(player, strong: true);
        return;
      }

      if (player.isGoalkeeper && ball.lastKickType == KickType.shoot) {
        parryFromGoalkeeper(player);
        return;
      }

      final controlChance =
          (player.isGoalkeeper ? 0.82 : 0.94) - player.errorFactor * 0.18;
      if (random.nextDouble() < controlChance) {
        _recordReception(player);
        if (player.isGoalkeeper && ball.lastKickType == KickType.shoot) {
          player.profile.saves += 1;
          player.matchSaves += 1;
          player.keeperState = 'top elde';
        }
        ball.attachTo(player);
      } else {
        _deflectFromPlayer(player, strong: false);
      }
      return;
    }
  }

  bool _canReachBall(PlayerGame player) {
    if (ball.heightMeters <= 0.35) {
      return true;
    }
    return ball.heightMeters <= player.bodyReachMeters + 0.01;
  }

  bool _isRecentKicker(PlayerGame player) {
    return _recentKickerGrace > 0 && _recentKicker == player;
  }

  bool _canSecureControl(PlayerGame player) {
    if (player.isGoalkeeper && isInPenaltyBox(player.pos, player.teamId)) {
      return ball.heightMeters <= player.bodyReachMeters + 0.10;
    }
    final lowControlHeight = player.profile.heightMeters * 0.70;
    final lowEnough = ball.heightMeters <= lowControlHeight;
    final loose =
        ball.lastKickType == null ||
        ball.hasBouncedSinceKick ||
        ball.vel.length < 3.5;
    final groundPass =
        ball.lastKickType == KickType.pass &&
        lowEnough &&
        ball.vel.length < 7.0;
    return lowEnough && (loose || groundPass);
  }

  bool _isLogicalHandball(PlayerGame player) {
    if (player.handballReviewCooldown > 0) {
      return false;
    }
    if (player.isGoalkeeper && isInPenaltyBox(player.pos, player.teamId)) {
      return false;
    }
    if (ball.lastTouch == null || ball.lastTouch!.teamId == player.teamId) {
      return false;
    }
    final handMin = player.profile.heightMeters * 0.43;
    final handMax = player.profile.heightMeters * 0.78;
    final inHandHeight =
        ball.heightMeters >= handMin && ball.heightMeters <= handMax;
    if (!inHandHeight || player.jumpAnimationTimer > 0) {
      return false;
    }

    // Hands are modelled on the two lateral sides of the body. A ball hitting
    // the player from directly in front or behind is a chest/back contact,
    // never an automatic handball.
    final facing = player.lastDirection.normalized(
      Vec2(teamById(player.teamId).attackDirection.toDouble(), 0),
    );
    final contactDirection = (ball.pos - player.pos).normalized(Vec2(0, 1));
    final frontBackAlignment = facing.dot(contactDirection).abs();
    final hitsLateralArmZone = frontBackAlignment < 0.56;
    if (!hitsLateralArmZone) {
      return false;
    }

    final strongContact =
        ball.vel.length > 4.6 || ball.lastKickType == KickType.shoot;
    final chance = (0.07 + ball.vel.length * 0.018).clamp(0.07, 0.24);
    return strongContact && random.nextDouble() < chance;
  }

  void _deflectFromPlayer(PlayerGame player, {required bool strong}) {
    if (ball.lastKickType == KickType.shoot && !player.isGoalkeeper) {
      shotDiagnostics.blocked += 1;
    }
    // A teammate's deflection of a pass also counts as a successful pass —
    // the ball reached one of the passer's own players.
    _markPassSuccessfulIfDue(player);
    final incoming = ball.vel.isZero
        ? (ball.pos - player.pos).normalized(
            Vec2(teamById(player.teamId).attackDirection.toDouble(), 0),
          )
        : ball.vel.normalized();
    final side = (ball.pos - player.pos).normalized(Vec2(0, 1));
    final scatter = Vec2(
      incoming.x * 0.45 + side.x * (random.nextDouble() - 0.5) * 1.2,
      incoming.y * 0.45 + side.y * (random.nextDouble() - 0.5) * 1.2,
    ).normalized(incoming);
    ball
      ..owner = null
      ..lastTouch = player
      ..intendedReceiver = null
      ..vel = scatter * (strong ? math.max(3.8, ball.vel.length * 0.58) : 2.2)
      ..verticalVelocity = ball.heightMeters > 0.45
          ? math.max(0.2, ball.verticalVelocity * -0.18)
          : 0.45
      ..heightMeters = math.max(ball.heightMeters, strong ? 0.18 : 0.05)
      ..curve *= 0.40
      ..spin *= 0.55
      ..trajectoryId += 1;
  }

  /// A saved shot normally remains live as a rebound instead of becoming a
  /// clean catch every time. Better parrying sends it away from danger with
  /// less random scatter; the goalkeeper never receives the shot finalTarget.
  void parryFromGoalkeeper(PlayerGame keeper, {double? control}) {
    final team = teamById(keeper.teamId);
    final parryControl = (control ?? keeper.profile.goalkeeperStats.parrying)
        .clamp(0.05, 0.99)
        .toDouble();
    final sideScatter =
        (random.nextDouble() - 0.5) * (1.45 - parryControl * 0.90);
    final reboundDirection = Vec2(
      team.attackDirection.toDouble(),
      sideScatter,
    ).normalized(Vec2(team.attackDirection.toDouble(), 0));
    final reboundSpeed = math.max(
          3.2,
          ball.vel.length * (0.52 + (1 - parryControl) * 0.17),
        ) +
        random.nextDouble() * (1.15 - parryControl * 0.62);
    ball
      ..owner = null
      ..lastTouch = keeper
      ..lastPasser = null
      ..intendedReceiver = null
      ..vel = reboundDirection * reboundSpeed
      ..heightMeters = math.max(ball.heightMeters, 0.12)
      ..verticalVelocity = ball.heightMeters > 0.45 ? 0.55 : 0.18
      ..curve *= 0.32
      ..spin *= 0.48
      ..trajectoryId += 1;
    final stats = keeper.profile.goalkeeperStats;
    // The keeper gets up fast — about three quarters of a second.
    final recoverySeconds = (0.82 - stats.diving * 0.06 - stats.reaction * 0.03)
        .clamp(0.60, 0.82)
        .toDouble();
    keeper
      ..keeperState = 'kurtaris'
      ..jumpBoostMeters = math.max(keeper.jumpBoostMeters, 0.12)
      ..jumpAnimationTimer = 0.62
      ..keeperGroundTimer = math.max(
        keeper.keeperGroundTimer,
        recoverySeconds,
      )
      ..keeperDiveCooldown = math.max(
        keeper.keeperDiveCooldown,
        recoverySeconds + 0.22,
      )
      ..keeperParryCooldown = 0.24;
    if (ball.lastKickType == KickType.shoot) {
      keeper.profile.saves += 1;
      keeper.matchSaves += 1;
      shotDiagnostics.saved += 1;
    }
  }

  void punchFromGoalkeeper(PlayerGame keeper, {double control = 0.6}) {
    final team = teamById(keeper.teamId);
    final safeSide = keeper.pos.y < GameConstants.virtualHeight / 2 ? -1.0 : 1.0;
    final controlled = control.clamp(0.05, 0.99).toDouble();
    final direction = Vec2(
      team.attackDirection.toDouble(),
      safeSide * (0.55 + controlled * 0.48) +
          (random.nextDouble() - 0.5) * (1 - controlled) * 0.65,
    ).normalized(Vec2(team.attackDirection.toDouble(), safeSide));
    ball
      ..owner = null
      ..lastTouch = keeper
      ..lastPasser = null
      ..intendedReceiver = null
      ..vel = direction * (5.0 + controlled * 2.2)
      ..verticalVelocity = 1.2 + controlled * 0.8
      ..heightMeters = math.max(ball.heightMeters, 0.75)
      ..curve *= 0.22
      ..spin *= 0.38
      ..trajectoryId += 1;
    final recovery = (0.80 - keeper.profile.goalkeeperStats.jumping * 0.08)
        .clamp(0.60, 0.80)
        .toDouble();
    keeper
      ..keeperState = 'kurtaris'
      ..jumpAnimationTimer = 0.62
      ..jumpBoostMeters = math.max(keeper.jumpBoostMeters, 0.16)
      ..keeperGroundTimer = math.max(keeper.keeperGroundTimer, recovery)
      ..keeperDiveCooldown = math.max(keeper.keeperDiveCooldown, recovery + 0.2)
      ..keeperParryCooldown = 0.24;
  }

  /// During a corner the box is packed: opposing players push and jostle
  /// for position (each defender tries to mark the man nearest to him).
  /// Contact is mostly harmless — a foul is only called about 10% of the
  /// time, matching real corner-kick wrestling.
  void _handleCornerJostle(double dt) {
    final attackingId = setPieceAttackTeamId;
    final duringCorner =
        restartKind == RestartKind.corner || attackingId != null;
    if (!duringCorner) {
      return;
    }
    final attacking = attackingId != null ? teamById(attackingId) : null;
    final boxCenterX = attacking == null
        ? null
        : attacking.side == TeamSide.left
        ? GameConstants.leftBound + 135
        : GameConstants.rightBound - 135;
    final inBoxZone = boxCenterX == null
        ? null
        : (Vec2 pos) =>
              (pos.x - boxCenterX).abs() < 130 &&
              (pos.y - GameConstants.virtualHeight / 2).abs() < 150;

    final players = allPlayers.where((p) => !p.isGoalkeeper).toList();
    for (var i = 0; i < players.length; i++) {
      for (var j = i + 1; j < players.length; j++) {
        final a = players[i];
        final b = players[j];
        if (a.teamId == b.teamId) {
          continue;
        }
        if (inBoxZone != null &&
            !inBoxZone(a.pos) &&
            !inBoxZone(b.pos)) {
          continue;
        }
        final diff = b.pos - a.pos;
        final distance = diff.length;
        if (distance <= 0 || distance > a.radius + b.radius + 16) {
          continue;
        }
        final direction = diff.normalized();
        // Push each other slightly — jostling for position.
        final push = (1 - distance / (a.radius + b.radius + 16)) * 0.55;
        a.pos = a.pos - direction * push;
        b.pos = b.pos + direction * push;
        a.keepInsideField();
        b.keepInsideField();

        // About 10% of corners end in a foul from the box wrestling:
        // ~0.35% per touching pair per second, over roughly 30 contact
        // pair-seconds per corner => ~10% per corner.
        final foulChance = 0.0035 * dt;
        if (random.nextDouble() >= foulChance) {
          continue;
        }
        final victim = random.nextBool() ? a : b;
        final fouler = victim == a ? b : a;
        if (fouler.tackleContactCooldown > 0 || victim.isInjuredInMatch) {
          continue;
        }
        final foulSpot = victim.pos.copy();
        final inBox = isInPenaltyBox(foulSpot, fouler.teamId);
        fouler.tackleContactCooldown = 1.4;
        _startVarDecision(
          title: inBox ? 'VAR PENALTI KONTROLU' : 'VAR FAUL KONTROLU',
          reason:
              '${fouler.profile.name}: korner itismesi • ${victim.profile.name}',
          category: inBox ? 'penalty' : 'foul',
          recommendedDecision: 'foul',
          options: const ['playOn', 'foul', 'yellow'],
          resolve: (decision) {
            if (decision == 'playOn') {
              return;
            }
            _applyReviewedFoul(
              victim: victim,
              fouler: fouler,
              foulSpot: foulSpot,
              inPenaltyBox: inBox,
              violent: false,
              reckless: false,
              cardDecision: decision,
            );
          },
        );
        return;
      }
    }
  }

  void _preventOverlap() {
    const minExtra = 3.0;
    for (var i = 0; i < allPlayers.length; i++) {
      for (var j = i + 1; j < allPlayers.length; j++) {
        final a = allPlayers[i];
        final b = allPlayers[j];
        final diff = b.pos - a.pos;
        final distance = diff.length;
        final minDistance = a.radius + b.radius + minExtra;
        if (distance > 0 && distance < minDistance) {
          final direction = diff.normalized();
          final overlap = minDistance - distance;
          a.pos = a.pos - direction * (overlap / 2);
          b.pos = b.pos + direction * (overlap / 2);
          a.keepInsideField();
          b.keepInsideField();
        }
      }
    }
  }

  void _checkOffsideTouch() {
    final candidate = _offsideCandidate;
    if (candidate == null) {
      return;
    }
    if (ball.lastTouch != null &&
        ball.lastTouch!.teamId != candidate.offender.teamId) {
      _offsideCandidate = null;
      return;
    }
    final attacking = teamById(candidate.event.attackingTeam);
    final defending = opponentOf(attacking);
    final offenderDistance = candidate.offender.pos.distanceTo(ball.pos);
    final touched =
        ball.owner == candidate.offender ||
        (ball.owner == null &&
            offenderDistance < candidate.offender.radius + 12 &&
            _canReachBall(candidate.offender));
    final challengingOpponent =
        ball.owner == null &&
        offenderDistance < candidate.offender.radius + 26 &&
        defending.players.any(
          (player) => player.pos.distanceTo(ball.pos) < player.radius + 28,
        );
    final blockingKeeper =
        ball.lastKickType == KickType.shoot &&
        offenderDistance < 42 &&
        defending.goalkeeper.pos.distanceTo(ball.pos) < 95;
    if (touched || challengingOpponent || blockingKeeper) {
      _offsideCandidate = null;
      currentOffside = candidate.event;
      final restartSpot = candidate.offender.pos.copy()
        ..clampTo(
          GameConstants.leftBound + 18,
          GameConstants.topBound + 18,
          GameConstants.rightBound - 18,
          GameConstants.bottomBound - 18,
        );
      _startVarDecision(
        title: 'VAR OFSAYT',
        reason: '${candidate.event.kind}: ${candidate.event.offenderName}',
        category: 'offside',
        recommendedDecision: 'offside',
        options: const ['onside', 'offside'],
        resolve: (decision) {
          if (decision == 'offside') {
            _recordTimelineEvent(
              kind: 'offside',
              title: 'OFSAYT',
              detail: candidate.event.offenderName,
              teamId: candidate.event.attackingTeam,
              relatedPlayerId: candidate.offender.id,
            );
            final defending = teamById(candidate.event.attackingTeam.opponent);
            _handleFreeKick(defending.id, restartSpot);
            _startPause(
              'OFSAYT ONAYLANDI',
              candidate.event.offenderName,
              1.25,
              null,
              kind: 'var',
            );
          }
        },
      );
    } else if (minute - candidate.createdMinute > 2.2) {
      _offsideCandidate = null;
    }
  }

  bool _tryEmergencyGoalkeeperSave({required bool crossedLeft}) {
    if (ball.lastKickType != KickType.shoot) return false;
    final defending = crossedLeft
        ? teamBySide(TeamSide.left)
        : teamBySide(TeamSide.right);
    final keeper = defending.goalkeeper;
    if (keeper.isSentOff ||
        keeper.keeperState == 'yerde' ||
        ball.heightMeters > keeper.bodyReachMeters) {
      return false;
    }
    // Goal-line resolution may run one frame after physical contact. Permit a
    // save only when the real ball and goalkeeper bodies overlap; there is no
    // random chance and no teleport toward a precomputed target.
    final physicalReach = keeper.radius +
        GameConstants.ballRadius +
        3 +
        keeper.profile.goalkeeperStats.reach * 8;
    if (keeper.pos.distanceTo(ball.pos) > physicalReach) return false;
    ball.pos.x = crossedLeft
        ? GameConstants.leftBound + GameConstants.ballRadius + 2
        : GameConstants.rightBound - GameConstants.ballRadius - 2;
    parryFromGoalkeeper(
      keeper,
      control: keeper.profile.goalkeeperStats.parrying,
    );
    return true;
  }

  void _checkGoalAndOut() {
    final goalTop =
        GameConstants.virtualHeight / 2 - GameConstants.goalPixelHeight / 2;
    final goalBottom =
        GameConstants.virtualHeight / 2 + GameConstants.goalPixelHeight / 2;
    // The whole ball must cross the goal line before a goal/out is awarded.
    final crossedLeft =
        ball.pos.x + GameConstants.ballRadius < GameConstants.leftBound;
    final crossedRight =
        ball.pos.x - GameConstants.ballRadius > GameConstants.rightBound;

    if (!crossedLeft && !crossedRight) {
      return;
    }

    final nearPost =
        (ball.pos.y - goalTop).abs() <= GameConstants.ballRadius + 2.5 ||
        (ball.pos.y - goalBottom).abs() <= GameConstants.ballRadius + 2.5;
    if (nearPost &&
        !ball.goalLineMissCommitted &&
        ball.heightMeters < GameConstants.crossbarMinMeters + 0.10) {
      shotDiagnostics.posts += 1;
      final postY = (ball.pos.y - goalTop).abs() <
              (ball.pos.y - goalBottom).abs()
          ? goalTop
          : goalBottom;
      ball
        ..pos.x = crossedLeft
            ? GameConstants.leftBound + GameConstants.ballRadius + 0.5
            : GameConstants.rightBound - GameConstants.ballRadius - 0.5
        ..vel = Vec2(-ball.vel.x * 0.62, (ball.pos.y - postY).sign * 3.2)
        ..curve *= 0.45
        ..spin *= 0.65;
      return;
    }

    final inGoalMouth =
        ball.pos.y - GameConstants.ballRadius > goalTop &&
        ball.pos.y + GameConstants.ballRadius < goalBottom;
    if (inGoalMouth && !ball.goalLineMissCommitted) {
      final hitsCrossbar =
          ball.heightMeters >= GameConstants.crossbarMinMeters - 0.08 &&
          ball.heightMeters <= GameConstants.crossbarMaxMeters + 0.08;
      if (hitsCrossbar) {
        shotDiagnostics.crossbars += 1;
        final scoringTeam = crossedLeft
            ? teamBySide(TeamSide.right)
            : teamBySide(TeamSide.left);
        final overLineX = crossedLeft
            ? GameConstants.leftBound - GameConstants.ballRadius - 0.5
            : GameConstants.rightBound + GameConstants.ballRadius + 0.5;
        final backInX = crossedLeft
            ? GameConstants.leftBound + GameConstants.ballRadius + 0.5
            : GameConstants.rightBound - GameConstants.ballRadius - 0.5;
        final roll = random.nextDouble();
        if (roll < 0.30) {
          // The crossbar rebounds the ball INTO the goal.
          ball
            ..pos = Vec2(overLineX, ball.pos.y)
            ..vel = Vec2(crossedLeft ? -0.8 : 0.8, 0)
            ..verticalVelocity = 0
            ..heightMeters = math.max(0.1, ball.heightMeters - 1.2);
          _scoreGoal(scoringTeam);
          return;
        }
        if (roll < 0.60) {
          // The crossbar sends the ball OVER the bar — it goes out (miss).
          ball
            ..pos = Vec2(overLineX, ball.pos.y)
            ..vel = Vec2(crossedLeft ? -1.4 : 1.4, (random.nextDouble() - 0.5))
            ..verticalVelocity = 3.4
            ..goalLineMissCommitted = true;
          return;
        }
        // Otherwise it bounces back into play.
        ball
          ..pos = Vec2(backInX, ball.pos.y)
          ..vel = Vec2(-ball.vel.x * 0.62, ball.vel.y * 0.8)
          ..verticalVelocity = -math.max(1.2, ball.verticalVelocity.abs() * 0.5);
        return;
      }
      if (ball.heightMeters < GameConstants.crossbarMinMeters) {
        if (_tryEmergencyGoalkeeperSave(crossedLeft: crossedLeft)) {
          return;
        }
        final scoringTeam = crossedLeft
            ? teamBySide(TeamSide.right)
            : teamBySide(TeamSide.left);
        _scoreGoal(scoringTeam);
        return;
      }
    }

    ball.goalLineMissCommitted = true;

    // Missed shots remain visible beyond the goal line until they leave the
    // canvas. This makes wide and over-the-bar attempts travel naturally
    // before the goal-kick/corner restart is awarded.
    if (ball.lastKickType == KickType.shoot) {
      final leftCanvasExit =
          ball.pos.x + GameConstants.ballRadius < -GameConstants.goalDepth;
      final rightCanvasExit =
          ball.pos.x - GameConstants.ballRadius >
          GameConstants.virtualWidth + GameConstants.goalDepth;
      if (!leftCanvasExit && !rightCanvasExit && ball.vel.length > 0.25) {
        return;
      }
    }

    final outBy = ball.lastTouch?.teamId;
    final defending = crossedLeft
        ? teamBySide(TeamSide.left)
        : teamBySide(TeamSide.right);
    final attacking = opponentOf(defending);
    final restartTeam = outBy == defending.id ? attacking : defending;
    final restartPlayer = restartTeam == attacking && outBy == defending.id
        ? attacking.players.firstWhere(
            (player) => !player.isSentOff && player.role.isWide,
            orElse: () => attacking.closestTo(ball.pos),
          )
        : restartTeam.goalkeeper.isSentOff
        ? restartTeam.closestTo(ball.pos, includeGoalkeeper: false)
        : restartTeam.goalkeeper;
    final isCorner = restartTeam == attacking;
    final restartPos = isCorner
        ? _cornerSpot(crossedLeft, ball.pos.y < GameConstants.virtualHeight / 2)
        : _goalKickSpot(defending);
    _offsideCandidate = null;
    _offsideExemptNextKick = true;
    setPieceAttackTeamId = null;
    setPieceAttackTimer = 0;
    _cornerManualWaitTeamId = isCorner ? restartTeam.id : null;
    _cornerManualWaitTimer = isCorner ? 3.0 : 0;
    _cornerReadyOverride = false;
    restartKind = isCorner ? RestartKind.corner : RestartKind.goalKick;
    restartTeamId = restartTeam.id;
    _restartSpot = restartPos.copy();
    ball
      ..owner = restartPlayer
      ..pos = restartPos
      ..vel = Vec2.zero()
      ..heightMeters = 0
      ..verticalVelocity = 0;
    restartPlayer
      ..pos = restartPos - Vec2(restartTeam.attackDirection * 16, 0)
      ..lastDirection = Vec2(restartTeam.attackDirection.toDouble(), 0);
    _shapeRestartPlayers(restartTeam, defending, isCorner: isCorner);
    _startPause(
      isCorner ? 'KORNER' : 'KALE VURUSU',
      restartTeam.name,
      0.8,
      null,
    );
  }

  void _scoreGoal(
    TeamGame scoringTeam, {
    bool isPenalty = false,
    String? scorerName,
  }) {
    if (ball.lastKickType == KickType.shoot) {
      shotDiagnostics.goals += 1;
    }
    // Credit the teammate who delivered the last completed pass before the
    // shot, but never credit the scorer as assisting himself.
    final assister = ball.potentialAssister;
    if (assister != null &&
        assister.teamId == scoringTeam.id &&
        assister != ball.lastTouch) {
      assister.matchAssists += 1;
      assister.profile.assists += 1;
    }
    final conceding = opponentOf(scoringTeam);
    scoringTeam.score += 1;
    final netY = ball.pos.y
        .clamp(
          GameConstants.virtualHeight / 2 - GameConstants.goalPixelHeight / 2 + 8,
          GameConstants.virtualHeight / 2 + GameConstants.goalPixelHeight / 2 - 8,
        )
        .toDouble();
    final scorer =
        scorerName ??
        (ball.lastTouch?.teamId == scoringTeam.id
            ? ball.lastTouch!.profile.name
            : 'Kendi kalesine');
    if (ball.lastTouch?.teamId == scoringTeam.id) {
      ball.lastTouch!.profile.goals += 1;
      ball.lastTouch!.matchGoals += 1;
    }
    ball
      ..owner = null
      ..vel = Vec2.zero()
      ..heightMeters = 0
      ..verticalVelocity = 0
      ..pos = Vec2(
        scoringTeam.side == TeamSide.left
            ? GameConstants.rightBound + GameConstants.goalDepth - 4
            : GameConstants.leftBound - GameConstants.goalDepth + 4,
        netY,
      );
    final goalEvent = GoalEvent(
      teamId: scoringTeam.id,
      scorerName: scorer,
      minute: minute.ceil(),
      isPenalty: isPenalty,
      scorerPlayerId: ball.lastTouch?.teamId == scoringTeam.id
          ? ball.lastTouch!.id
          : null,
      assisterPlayerId:
          assister != null && assister.teamId == scoringTeam.id
          ? assister.id
          : null,
    );
    scoringTeam.goals.add(goalEvent);
    final goalTimelineEvent = _recordTimelineEvent(
      kind: 'goal',
      title: 'GOL',
      detail: '${scoringTeam.name} • $scorer',
      teamId: scoringTeam.id,
      relatedPlayerId: goalEvent.scorerPlayerId,
    );
    _startVarDecision(
      title: 'VAR GOL KONTROLU',
      reason: '${scoringTeam.name} • $scorer',
      category: 'goal',
      recommendedDecision: 'confirm',
      options: const ['confirm', 'cancel'],
      resolve: (decision) {
        if (decision == 'cancel') {
          goalEvent.canceled = true;
          goalTimelineEvent.canceled = true;
          scoringTeam.score = math.max(0, scoringTeam.score - 1).toInt();
          if (ball.lastTouch?.teamId == scoringTeam.id) {
            ball.lastTouch!.profile.goals = math.max(
              0,
              ball.lastTouch!.profile.goals - 1,
            ).toInt();
            ball.lastTouch!.matchGoals = math.max(
              0,
              ball.lastTouch!.matchGoals - 1,
            ).toInt();
          }
          if (assister != null && assister.teamId == scoringTeam.id) {
            assister.profile.assists = math.max(
              0,
              assister.profile.assists - 1,
            ).toInt();
            assister.matchAssists = math.max(
              0,
              assister.matchAssists - 1,
            ).toInt();
          }
          _startPause(
            'GOL IPTAL',
            'VAR karari • $scorer',
            1.2,
            () => _startGoalKickFor(conceding),
            kind: 'var',
          );
        } else {
          _startPause(
            'GOL',
            '${scoringTeam.name} • $scorer',
            2.0,
            () => resetKickoff(conceding.id),
            kind: 'goal',
          );
        }
      },
    );
  }

  void startPenalty(
    TeamId shootingTeam, {
    required bool shootout,
    bool recordTimeline = true,
  }) {
    if (activePenalty != null || period == MatchPeriod.penalties && !shootout) {
      return;
    }
    final team = teamById(shootingTeam);
    final defending = opponentOf(team);
    final shooter = _placePenalty(team, defending, shootout: shootout);
    activePenalty = ActivePenalty(
      shootingTeam: shootingTeam,
      shootout: shootout,
      minute: minute.ceil(),
      shooterId: shooter.id,
    );
    if (recordTimeline) {
      _recordTimelineEvent(
        kind: shootout ? 'shootout' : 'penalty',
        title: shootout ? 'PENALTI SERISI' : 'PENALTI KARARI',
        detail: '${team.name} • ${shooter.profile.name}',
        teamId: team.id,
        relatedPlayerId: shooter.id,
      );
    }
    _penaltyKeeperTarget = null;
    _penaltyBallDeflected = false;
    banner = MatchBanner(
      shootout ? 'PENALTI' : 'PENALTI KARARI',
      '${team.name}: yon sec, sut tusuna basili tut',
      1.4,
    );
  }

  void _tickPenalty(double dt) {
    final penalty = activePenalty;
    if (penalty == null) {
      return;
    }
    if (penalty.result == null) {
      return;
    }
    final shooting = teamById(penalty.shootingTeam);
    final defending = opponentOf(shooting);
    final target = _penaltyKeeperTarget;
    if (target != null) {
      defending.goalkeeper.keeperState = _penaltyBallDeflected
          ? 'kurtaris'
          : defending.goalkeeper.jumpAnimationTimer > 0.10
          ? 'atlayis'
          : 'yerde';
      final penaltyRecovery = (0.88 -
              defending.goalkeeper.profile.goalkeeperStats.diving * 0.08 -
              defending.goalkeeper.profile.goalkeeperStats.reaction * 0.04)
          .clamp(0.55, 0.88)
          .toDouble();
      defending.goalkeeper.keeperGroundTimer = math.max(
        defending.goalkeeper.keeperGroundTimer,
        penaltyRecovery,
      );
      moveTowards(defending.goalkeeper, target, 1.18, dt);
    }
    _ballPhysics.update(ball, dt);
    if (!penalty.result!.scored &&
        !_penaltyBallDeflected &&
        defending.goalkeeper.pos.distanceTo(ball.pos) <
            defending.goalkeeper.radius + GameConstants.ballRadius + 12) {
      _deflectFromPlayer(defending.goalkeeper, strong: true);
      defending.goalkeeper.profile.saves += 1;
      defending.goalkeeper.matchSaves += 1;
      defending.goalkeeper.keeperState = 'kurtaris';
      _penaltyBallDeflected = true;
    }
    penalty.countdown -= dt;
    if (penalty.countdown > 0) {
      return;
    }

    final result = penalty.result!;
    activePenalty = null;
    banner = null;
    _penaltyKeeperTarget = null;
    _penaltyBallDeflected = false;
    if (penalty.shootout) {
      if (shootout?.complete ?? false) {
        winner = shootout!.winner;
        finished = true;
        period = MatchPeriod.finished;
        _commitPlayerMinutes();
        banner = MatchBanner(
          'MAC BITTI',
          '${teamById(winner!).name} kazandi',
          1000,
        );
      }
      return;
    }
    if (!result.scored) {
      // Saved/missed penalty: the match continues from the penalty area —
      // the keeper collects the ball and the waiting players (who were
      // standing on the edge of the box) are ready for the rebound or the
      // counter-attack. No midfield kickoff.
      restartKind = null;
      restartTeamId = null;
      _restartSpot = null;
      setPieceAttackTeamId = null;
      setPieceAttackTimer = 0;
      final keeper = defending.goalkeeper;
      final goalLineX = defending.side == TeamSide.left
          ? GameConstants.leftBound + 16
          : GameConstants.rightBound - 16;
      keeper
        ..pos = Vec2(goalLineX, GameConstants.virtualHeight / 2)
        ..keeperState = 'top elde'
        ..manualOverride = 0.5;
      ball
        ..owner = keeper
        ..pos = keeper.pos + Vec2(keeper.lastDirection.x * 14, 0)
        ..vel = Vec2.zero()
        ..heightMeters = 0
        ..verticalVelocity = 0;
      banner = MatchBanner(
        'KURTARILDI',
        '${defending.name} kaleci ile devam',
        1.6,
      );
    } else {
      resetKickoff(defending.id);
    }
  }

  void _recordPenaltyGoal(TeamGame scoringTeam, PenaltyKickResult result) {
    scoringTeam.score += 1;
    final scorer = scoringTeam.players.where(
      (player) => player.profile.name == result.shooterName,
    );
    if (scorer.isNotEmpty) {
      scorer.first.profile.goals += 1;
      scorer.first.matchGoals += 1;
    }
    scoringTeam.goals.add(
      GoalEvent(
        teamId: scoringTeam.id,
        scorerName: result.shooterName,
        minute: result.minute,
        isPenalty: true,
        scorerPlayerId: scorer.isEmpty ? null : scorer.first.id,
      ),
    );
    _recordTimelineEvent(
      kind: 'goal',
      title: 'PENALTI GOLU',
      detail: '${scoringTeam.name} • ${result.shooterName}',
      teamId: scoringTeam.id,
      relatedPlayerId: scorer.isEmpty ? null : scorer.first.id,
    );
  }

  void _startPenaltyVisual(
    TeamGame shooting,
    TeamGame defending,
    PenaltyKickResult result,
  ) {
    final shooter =
        ball.owner ??
        shooting.players.firstWhere((p) => p.role == PlayerRole.striker);
    final goalX = shooting.side == TeamSide.left
        ? GameConstants.rightBound + 28
        : GameConstants.leftBound - 28;
    final goalCenterY = GameConstants.virtualHeight / 2;
    final halfGoal = GameConstants.goalPixelHeight / 2;
    final sideOffset = GameConstants.goalPixelHeight * 0.32;
    var targetY = switch (result.shotLane) {
      PenaltyLane.leftLow || PenaltyLane.leftHigh => goalCenterY - sideOffset,
      PenaltyLane.center => goalCenterY,
      PenaltyLane.rightLow || PenaltyLane.rightHigh => goalCenterY + sideOffset,
    };
    final savedSide = _samePenaltySide(result.shotLane, result.keeperLane);
    var loft = _penaltyLoft(result.heightMeters);
    if (!result.scored) {
      if (savedSide) {
        // Keeper guessed right: aim stays in the corner — the keeper dives
        // and saves/parries it there.
      } else if (result.heightMeters > 2.44) {
        // Over the bar: keep the aim central, the height sends it over.
        targetY = goalCenterY;
        loft = math.max(loft, _penaltyLoft(2.55));
      } else {
        // Missed wide: just off the post — a small, realistic miss, scaled
        // by the shooter's finishing (good finishers miss by less).
        final missAmount =
            (10 + (1 - shooter.profile.finishingSkill) * 22).toDouble();
        final laneSign = result.shotLane == PenaltyLane.leftLow ||
                result.shotLane == PenaltyLane.leftHigh
            ? -1.0
            : 1.0;
        targetY = goalCenterY + laneSign * (halfGoal + missAmount);
      }
    }
    final target = Vec2(goalX, targetY);
    ball.release(
      direction: target - ball.pos,
      power: 1.12 + result.power * 0.22,
      toucher: shooter,
      receiver: null,
      kickType: KickType.shoot,
      loft: loft,
    );

    final keeperGoalX = defending.side == TeamSide.left
        ? GameConstants.leftBound + 14
        : GameConstants.rightBound - 14;
    final keeperY = switch (result.keeperLane) {
      PenaltyLane.leftLow || PenaltyLane.leftHigh => goalCenterY - sideOffset,
      PenaltyLane.center => goalCenterY,
      PenaltyLane.rightLow || PenaltyLane.rightHigh => goalCenterY + sideOffset,
    };
    defending.goalkeeper
      ..jumpBoostMeters = math.max(defending.goalkeeper.jumpBoostMeters, 0.16)
      ..jumpAnimationTimer = 0.62;
    _penaltyKeeperTarget = Vec2(keeperGoalX, keeperY);
    _penaltyBallDeflected = false;
  }

  double _penaltyLoft(double heightMeters) {
    return math.sqrt(
          math.max(0.15, heightMeters) * 2 * GameConstants.gravityMeters,
        ) *
        1.02;
  }

  bool _samePenaltySide(PenaltyLane shot, PenaltyLane keeper) {
    if (shot == PenaltyLane.center || keeper == PenaltyLane.center) {
      return shot == keeper;
    }
    final shotLeft =
        shot == PenaltyLane.leftLow || shot == PenaltyLane.leftHigh;
    final keeperLeft =
        keeper == PenaltyLane.leftLow || keeper == PenaltyLane.leftHigh;
    return shotLeft == keeperLeft;
  }

  PlayerGame _placePenalty(
    TeamGame shooting,
    TeamGame defending, {
    bool shootout = false,
  }) {
    final shootingRight = shooting.side == TeamSide.left;
    final spotX = shootingRight
        ? GameConstants.rightBound - 88
        : GameConstants.leftBound + 88;
    final goalX = shootingRight
        ? GameConstants.rightBound - 8
        : GameConstants.leftBound + 8;
    final shooter = shooting.players.firstWhere(
      (player) => !player.isSentOff && player.role == PlayerRole.striker,
      orElse: () => shooting.players.firstWhere(
        (player) => !player.isSentOff && !player.isGoalkeeper,
      ),
    );
    if (shootout) {
      // Penalty shootout: everyone waits on the centre circle as usual.
      for (final player in allMatchPlayers) {
        if (player == shooter || player == defending.goalkeeper) {
          continue;
        }
        final sideOffset = player.teamId == shooting.id ? -1 : 1;
        player.pos = Vec2(
          GameConstants.virtualWidth / 2 - shooting.attackDirection * 120,
          GameConstants.virtualHeight / 2 +
              sideOffset * 70 +
              (player.number % 5) * 18,
        );
        player.keepInsideField();
      }
      shooter.pos = Vec2(spotX, GameConstants.virtualHeight / 2);
      shooter.lastDirection = Vec2(shooting.attackDirection.toDouble(), 0);
      ball
        ..owner = shooter
        ..pos = shooter.pos + Vec2(shooting.attackDirection * 16, 0)
        ..vel = Vec2.zero()
        ..heightMeters = 0
        ..verticalVelocity = 0;
      defending.goalkeeper.pos = Vec2(goalX, GameConstants.virtualHeight / 2);
      return shooter;
    }
    // Edge of the penalty area (16-yard line), where the waiting players
    // stand during an in-match penalty.
    final boxEdgeX = shootingRight
        ? GameConstants.rightBound - 135
        : GameConstants.leftBound + 135;
    // Defenders hold a compact line just behind the penalty spot.
    final defenseX = shootingRight
        ? GameConstants.rightBound - 168
        : GameConstants.leftBound + 168;
    final centerY = GameConstants.virtualHeight / 2;
    final d = shooting.attackDirection;

    var attackerSlot = 0;
    final attackersAtBox = shooting.players.where(
      (player) => player != shooter && !player.isGoalkeeper && !player.isSentOff,
    );
    for (final player in attackersAtBox) {
      player.pos = Vec2(
        boxEdgeX - d * ((attackerSlot % 2) * 22),
        centerY - 105 + attackerSlot * 30 + (player.number % 4) * 9,
      );
      player.keepInsideField();
      attackerSlot += 1;
    }

    // One defending attacker stays high near the halfway line, ready to
    // launch a counter-attack if the penalty is saved.
    final counterMan = defending.players.firstWhere(
      (player) =>
          !player.isSentOff &&
          (player.role == PlayerRole.striker ||
              player.role == PlayerRole.leftWing ||
              player.role == PlayerRole.rightWing),
      orElse: () => defending.players.firstWhere(
        (player) => !player.isSentOff && !player.isGoalkeeper,
      ),
    );
    counterMan.pos = Vec2(
      GameConstants.virtualWidth / 2 - d * 130,
      centerY - 95,
    );
    counterMan.keepInsideField();

    var defenderSlot = 0;
    for (final player in defending.players.where(
      (player) => player != defending.goalkeeper && !player.isSentOff,
    )) {
      if (player == counterMan) {
        continue;
      }
      player.pos = Vec2(
        defenseX - d * ((defenderSlot % 3) * 18),
        centerY - 92 + defenderSlot * 26,
      );
      player.keepInsideField();
      defenderSlot += 1;
    }

    shooter.pos = Vec2(spotX, centerY);
    shooter.lastDirection = Vec2(d.toDouble(), 0);
    ball
      ..owner = shooter
      ..pos = shooter.pos + Vec2(d * 16, 0)
      ..vel = Vec2.zero()
      ..heightMeters = 0
      ..verticalVelocity = 0;
    defending.goalkeeper.pos = Vec2(goalX, centerY);
    return shooter;
  }

  void _checkPeriodEnd() {
    switch (period) {
      case MatchPeriod.firstHalf:
        if (minute >= 45 + firstHalfStoppage && _attackHasFinished()) {
          _startPause(
            'DEVRE ARASI',
            '+${firstHalfStoppage.toInt()} dakika',
            GameConstants.periodPauseSeconds,
            () {
              minute = 45;
              period = MatchPeriod.secondHalf;
              _switchSidesAndRestart(TeamId.red);
            },
          );
        }
      case MatchPeriod.secondHalf:
        if (minute >= 90 + secondHalfStoppage && _attackHasFinished()) {
          if (mode == MatchMode.knockout && blueTeam.score == redTeam.score) {
            _startPause(
              'UZATMA',
              'Eleme maci devam ediyor',
              GameConstants.periodPauseSeconds,
              () {
                minute = 90;
                period = MatchPeriod.extraFirst;
                _switchSidesAndRestart(TeamId.blue);
              },
            );
          } else {
            _finishNormal();
          }
        }
      case MatchPeriod.extraFirst:
        if (minute >= 105 + extraFirstStoppage && _attackHasFinished()) {
          _startPause(
            'UZATMA ARASI',
            '+${extraFirstStoppage.toInt()} dakika',
            GameConstants.periodPauseSeconds,
            () {
              minute = 105;
              period = MatchPeriod.extraSecond;
              _switchSidesAndRestart(TeamId.red);
            },
          );
        }
      case MatchPeriod.extraSecond:
        if (minute >= 120 + extraSecondStoppage && _attackHasFinished()) {
          if (blueTeam.score == redTeam.score) {
            _startPause(
              'PENALTILAR',
              'Seri penalti basliyor',
              GameConstants.periodPauseSeconds,
              () {
                period = MatchPeriod.penalties;
                shootout = PenaltyShootout(firstTeam: TeamId.blue);
                banner = null;
              },
            );
          } else {
            _finishNormal();
          }
        }
      case MatchPeriod.penalties:
      case MatchPeriod.finished:
        break;
    }
  }

  /// Lets a genuine attack conclude before the referee ends a period.
  bool _attackHasFinished() {
    final owner = ball.owner;
    if (owner != null) {
      final attacking = teamById(owner.teamId);
      final finalThird = attacking.attackDirection == 1
          ? owner.pos.x > GameConstants.virtualWidth * 0.66
          : owner.pos.x < GameConstants.virtualWidth * 0.34;
      return !finalThird;
    }
    final towardLeftGoal = ball.vel.x < -0.6 &&
        ball.pos.x < GameConstants.virtualWidth * 0.38;
    final towardRightGoal = ball.vel.x > 0.6 &&
        ball.pos.x > GameConstants.virtualWidth * 0.62;
    return !(towardLeftGoal || towardRightGoal);
  }

  void _tickShootout(double dt) {
    if (activePenalty != null) {
      if (activePenalty!.result == null) {
        _tickAiPenalty(dt);
      } else {
        _tickPenalty(dt);
      }
      return;
    }
    final state = shootout;
    if (state == null || state.complete) {
      return;
    }
    startPenalty(state.nextTeam, shootout: true);
  }

  void _finishNormal() {
    finished = true;
    period = MatchPeriod.finished;
    _commitPlayerMinutes();
    winner = blueTeam.score == redTeam.score
        ? null
        : blueTeam.score > redTeam.score
        ? TeamId.blue
        : TeamId.red;
    banner = MatchBanner(
      'MAC BITTI',
      winner == null ? 'Beraberlik' : '${teamById(winner!).name} kazandi',
      1000,
    );
  }

  void _switchSidesAndRestart(TeamId owner) {
    blueTeam.switchSide();
    redTeam.switchSide();
    resetKickoff(owner);
  }

  void _startPause(
    String title,
    String subtitle,
    double seconds,
    void Function()? after, {
    bool isVar = false,
    String? reason,
    String kind = 'info',
  }) {
    banner = MatchBanner(
      title,
      subtitle,
      seconds,
      minute: minute.ceil(),
      kind: kind,
    );
    varReviewActive = isVar;
    varReason = reason;
    _pauseTimer = seconds;
    _afterPause = after;
  }

  void _startVarDecision({
    required String title,
    required String reason,
    required String category,
    required String recommendedDecision,
    required List<String> options,
    required void Function(String decision) resolve,
  }) {
    final reviewTimelineEvent = _recordTimelineEvent(
      kind: 'var',
      title: title,
      detail: reason,
    );
    void resolver(String decision) {
      if (decision == 'playOn' ||
          decision == 'onside' ||
          decision == 'cancel') {
        reviewTimelineEvent.canceled = true;
      }
      resolve(decision);
    }
    final recommended = recommendedDecision;
    _varDecisionResolver = resolver;
    varReviewCategory = category;
    varRecommendedDecision = recommended;
    varDecisionOptions = List.unmodifiable(options);
    _startPause(
      title,
      'VAR incelemesi: $reason',
      GameConstants.replayFreezeSeconds + 1.4,
      () => resolver(recommended),
      isVar: true,
      reason: reason,
      kind: 'var',
    );
  }

  void resolveVarDecision(String decision) {
    if (!varReviewActive || !varDecisionOptions.contains(decision)) {
      return;
    }
    final resolver = _varDecisionResolver;
    _pauseTimer = 0;
    _afterPause = null;
    banner = null;
    varReviewActive = false;
    varReason = null;
    varReviewCategory = null;
    varRecommendedDecision = null;
    varDecisionOptions = const [];
    _varDecisionResolver = null;
    currentOffside = null;
    resolver?.call(decision);
  }

  MatchTimelineEvent _recordTimelineEvent({
    required String kind,
    required String title,
    required String detail,
    TeamId? teamId,
    String? relatedPlayerId,
    int? minuteOverride,
    int? replayIndexOverride,
  }) {
    final serial = _timelineSerial++;
    final event = MatchTimelineEvent(
      id: '$matchId-$serial',
      kind: kind,
      title: title,
      detail: detail,
      minute: minuteOverride ?? minute.ceil(),
      replayIndex: replayIndexOverride ??
          (replayFrames.isEmpty ? 0 : replayFrames.length - 1),
      teamId: teamId,
      relatedPlayerId: relatedPlayerId,
    );
    timelineEvents.add(event);
    timelineEvents.sort((a, b) {
      final byMinute = a.minute.compareTo(b.minute);
      if (byMinute != 0) return byMinute;
      final byFrame = a.replayIndex.compareTo(b.replayIndex);
      if (byFrame != 0) return byFrame;
      return a.id.compareTo(b.id);
    });
    return event;
  }

  void seekReplayToEvent(MatchTimelineEvent event) {
    if (replayFrames.isEmpty) return;
    replayIndex = event.replayIndex.clamp(0, replayFrames.length - 1).toInt();
    replayPlaying = false;
  }

  PlayerGame replayFocusPlayer() {
    final frame = currentReplayFrame;
    if (frame == null || frame.players.isEmpty) {
      return allMatchPlayers.first;
    }
    final ballPoint = Vec2(frame.ballX, frame.ballY);
    PlayerGame? best;
    var bestDistance = double.infinity;
    for (final player in allMatchPlayers) {
      final positions = frame.players.where((item) => item.id == player.id);
      if (positions.isEmpty) continue;
      final position = Vec2(positions.first.x, positions.first.y);
      final distance = position.distanceTo(ballPoint);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = player;
      }
    }
    return best ?? allMatchPlayers.first;
  }

  /// Records a VAR decision from the replay screen. The decision is always
  /// executed at the CURRENT moment of the match (now), stamped with the
  /// current minute — a decision can never be applied to a past period.
  MatchTimelineEvent? addVarDecisionAtCurrentReplay(
    String kind,
    PlayerGame player,
  ) {
    final frame = currentReplayFrame;
    if (!replayMode || frame == null) return null;
    final eventFrame = replayIndex;
    final team = teamById(player.teamId);

    switch (kind) {
      case 'foul':
      case 'handball': {
        player.profile.foulsCommitted += 1;
        player.matchFoulsCommitted += 1;
        final event = _recordTimelineEvent(
          kind: kind,
          title: kind == 'foul' ? 'VAR: FAUL EKLENDI' : 'VAR: EL EKLENDI',
          detail: player.profile.name,
          teamId: player.teamId,
          relatedPlayerId: player.id,
          replayIndexOverride: eventFrame,
        );
        // The restart happens right now from the live ball position.
        if (!finished) {
          closeReplay();
          final fouledTeam = opponentOf(team);
          if (isInPenaltyBox(ball.pos, player.teamId)) {
            startPenalty(fouledTeam.id, shootout: false);
          } else {
            _handleFreeKick(fouledTeam.id, ball.pos);
          }
          _startPause(
            kind == 'foul' ? 'VAR: FAUL' : 'VAR: ELLE OYNAMA',
            'Karar aninda uygulandi',
            1.6,
            null,
            kind: 'var',
          );
        }
        return event;
      }
      case 'offside': {
        final event = _recordTimelineEvent(
          kind: 'offside',
          title: 'VAR: OFSAYT EKLENDI',
          detail: player.profile.name,
          teamId: player.teamId,
          relatedPlayerId: player.id,
          replayIndexOverride: eventFrame,
        );
        // The defending team gets a free kick right now.
        if (!finished) {
          closeReplay();
          _handleFreeKick(opponentOf(team).id, ball.pos);
          _startPause(
            'VAR: OFSAYT',
            'Karar aninda uygulandi',
            1.6,
            null,
            kind: 'var',
          );
        }
        return event;
      }
      case 'yellowCard':
      case 'redCard':
        _issueCard(
          player,
          violent: kind == 'redCard',
          reckless: kind == 'yellowCard',
          reason: 'VAR onayli kart',
          forcedCard: kind == 'redCard' ? 'red' : 'yellow',
          eventReplayIndex: eventFrame,
        );
        final matches = timelineEvents.where(
          (event) =>
              event.relatedPlayerId == player.id &&
              (event.kind == 'yellowCard' || event.kind == 'redCard'),
        );
        return matches.isEmpty ? null : matches.last;
      case 'penalty':
        final event = _recordTimelineEvent(
          kind: 'penalty',
          title: 'VAR: PENALTI EKLENDI',
          detail: team.name,
          teamId: team.id,
          relatedPlayerId: player.id,
          replayIndexOverride: eventFrame,
        );
        if (!finished) {
          closeReplay();
          startPenalty(team.id, shootout: false, recordTimeline: false);
        }
        return event;
      case 'goal':
        team.score += 1;
        player.profile.goals += 1;
        player.matchGoals += 1;
        final goal = GoalEvent(
          teamId: team.id,
          scorerName: player.profile.name,
          minute: minute.ceil(),
          scorerPlayerId: player.id,
        );
        team.goals.add(goal);
        return _recordTimelineEvent(
          kind: 'goal',
          title: 'VAR: GOL EKLENDI',
          detail: '${team.name} • ${player.profile.name}',
          teamId: team.id,
          relatedPlayerId: player.id,
          replayIndexOverride: eventFrame,
        );
      case 'injury':
        final resistance = player.profile.dayaniklilikSkill;
        final days = (8 + (1 - resistance) * 24)
            .round()
            .clamp(5, 35)
            .toInt();
        player.profile.injuredDaysRemaining = math.max(
          player.profile.injuredDaysRemaining,
          days,
        ).toInt();
        player.isInjuredInMatch = true;
        injuryEvents.add(
          InjuryEvent(
            playerName: player.profile.name,
            teamId: player.teamId,
            days: days,
            minute: minute.ceil(),
          ),
        );
        if (team.players.contains(player)) {
          _queueForcedInjurySub(player);
        }
        return _recordTimelineEvent(
          kind: 'injury',
          title: 'VAR: SAKATLIK EKLENDI',
          detail: '${player.profile.name} • $days gun',
          teamId: team.id,
          relatedPlayerId: player.id,
          replayIndexOverride: eventFrame,
        );
      default:
        return null;
    }
  }

  void openReplay({bool fromStart = true}) {
    if (replayFrames.isEmpty) {
      return;
    }
    replayMode = true;
    replayPlaying = true;
    replayIndex = fromStart ? 0 : replayFrames.length - 1;
    banner = MatchBanner(
      'VAR KAYDI',
      'Alt cubukla izle, golleri iptal et veya geri al',
      1000,
    );
  }

  void closeReplay() {
    replayMode = false;
    replayPlaying = false;
    banner = null;
  }

  void toggleReplayPlayback() {
    replayPlaying = !replayPlaying;
  }

  void seekReplay(int delta) {
    if (!replayMode || replayFrames.isEmpty) {
      return;
    }
    replayIndex = (replayIndex + delta).clamp(0, replayFrames.length - 1);
  }

  void seekReplaySeconds(double seconds) {
    final frames = (seconds / 0.08).round();
    seekReplay(frames);
  }

  void setReplayProgress(double value) {
    if (replayFrames.isEmpty) {
      return;
    }
    replayIndex = (value.clamp(0, 1) * (replayFrames.length - 1)).round();
  }

  void _tickReplay(double dt) {
    if (!replayPlaying || replayFrames.isEmpty) {
      return;
    }
    _replayPlaybackAccumulator += dt;
    // Slow motion (0.25x) stretches each frame, fast forward (4x) rushes
    // through it.
    final frameStep = 0.08 / replaySpeed;
    while (_replayPlaybackAccumulator >= frameStep) {
      _replayPlaybackAccumulator -= frameStep;
      replayIndex += 1;
      if (replayIndex >= replayFrames.length) {
        replayIndex = replayFrames.length - 1;
        replayPlaying = false;
        break;
      }
    }
  }

  /// Starts a goal kick for [team]: the keeper takes the ball from the
  /// six-yard spot while every other player keeps his current position
  /// (they are only pushed out of the penalty area). No one is sent back
  /// to the halfway line.
  void _startGoalKickFor(TeamGame team) {
    _offsideCandidate = null;
    _offsideExemptNextKick = true;
    setPieceAttackTeamId = null;
    setPieceAttackTimer = 0;
    _cornerManualWaitTeamId = null;
    _cornerManualWaitTimer = 0;
    _cornerReadyOverride = false;
    restartKind = RestartKind.goalKick;
    restartTeamId = team.id;
    _restartSpot = _goalKickSpot(team).copy();
    final keeper = team.goalkeeper.isSentOff
        ? team.closestTo(ball.pos, includeGoalkeeper: false)
        : team.goalkeeper;
    ball
      ..owner = keeper
      ..pos = _restartSpot!.copy()
      ..vel = Vec2.zero()
      ..heightMeters = 0
      ..verticalVelocity = 0;
    keeper
      ..pos = _restartSpot! - Vec2(team.attackDirection * 16, 0)
      ..lastDirection = Vec2(team.attackDirection.toDouble(), 0);
    _shapeRestartPlayers(team, opponentOf(team), isCorner: false);
  }

  void toggleGoalReview(int index) {
    final goals = reviewGoals;
    if (index < 0 || index >= goals.length) {
      return;
    }
    final goal = goals[index];
    final team = teamById(goal.teamId);
    goal.canceled = !goal.canceled;
    final timelineMatches = timelineEvents.where(
      (event) =>
          event.kind == 'goal' &&
          event.minute == goal.minute &&
          (goal.scorerPlayerId == null ||
              event.relatedPlayerId == goal.scorerPlayerId),
    );
    if (timelineMatches.isNotEmpty) {
      timelineMatches.first.canceled = goal.canceled;
    }
    final delta = goal.canceled ? -1 : 1;
    team.score = math.max(0, team.score + delta).toInt();
    final scorer = allMatchPlayers.where(
      (player) => player.id == goal.scorerPlayerId,
    );
    if (scorer.isNotEmpty) {
      scorer.first.profile.goals = math.max(
        0,
        scorer.first.profile.goals + delta,
      ).toInt();
      scorer.first.matchGoals = math.max(
        0,
        scorer.first.matchGoals + delta,
      ).toInt();
    }
    final assister = allMatchPlayers.where(
      (player) => player.id == goal.assisterPlayerId,
    );
    if (assister.isNotEmpty) {
      assister.first.profile.assists = math.max(
        0,
        assister.first.profile.assists + delta,
      ).toInt();
      assister.first.matchAssists = math.max(
        0,
        assister.first.matchAssists + delta,
      ).toInt();
    }
    if (goal.canceled) {
      // A disallowed goal restarts with a goal kick for the conceding side.
      _startGoalKickFor(opponentOf(teamById(goal.teamId)));
    }
    banner = MatchBanner(
      goal.canceled ? 'GOL IPTAL' : 'GOL GERI ALINDI',
      "VAR karari: ${goal.minute}' ${goal.scorerName}",
      2.0,
    );
  }

  /// Every referee decision recorded on the timeline can be canceled or
  /// reinstated from the VAR screen — goals, penalties, fouls, handballs,
  /// offsides and cards.
  bool canToggleTimelineDecision(MatchTimelineEvent timeline) =>
      timeline.kind == 'goal' ||
      timeline.kind == 'penalty' ||
      timeline.kind == 'foul' ||
      timeline.kind == 'handball' ||
      timeline.kind == 'offside' ||
      timeline.kind == 'yellowCard' ||
      timeline.kind == 'redCard';

  void toggleTimelineDecision(MatchTimelineEvent timeline) {
    if (timeline.kind == 'goal') {
      final goals = reviewGoals;
      final goalIndex = goals.indexWhere(
        (goal) =>
            goal.minute == timeline.minute &&
            (timeline.relatedPlayerId == null ||
                goal.scorerPlayerId == timeline.relatedPlayerId),
      );
      if (goalIndex >= 0) {
        toggleGoalReview(goalIndex);
        timeline.canceled = goals[goalIndex].canceled;
      }
      return;
    }
    if (timeline.kind == 'penalty') {
      // A penalty decision is tied to the penalty goal it produced (if any).
      final goals = reviewGoals;
      final goalIndex = goals.indexWhere(
        (goal) =>
            goal.minute == timeline.minute &&
            goal.teamId == timeline.teamId &&
            goal.isPenalty,
      );
      if (goalIndex >= 0) {
        toggleGoalReview(goalIndex);
        timeline.canceled = goals[goalIndex].canceled;
        return;
      }
      timeline.canceled = !timeline.canceled;
      banner = MatchBanner(
        timeline.canceled
            ? 'PENALTI KARARI IPTAL'
            : 'PENALTI KARARI GERI ALINDI',
        "VAR ${timeline.minute}'",
        2.0,
        minute: timeline.minute,
        kind: 'var',
      );
      return;
    }
    if (timeline.kind == 'foul' || timeline.kind == 'handball') {
      final canceling = !timeline.canceled;
      final playerId = timeline.relatedPlayerId;
      if (playerId != null) {
        final players = allMatchPlayers.where((player) => player.id == playerId);
        if (players.isNotEmpty) {
          final player = players.first;
          final delta = canceling ? -1 : 1;
          player.matchFoulsCommitted = math.max(
            0,
            player.matchFoulsCommitted + delta,
          ).toInt();
          player.profile.foulsCommitted = math.max(
            0,
            player.profile.foulsCommitted + delta,
          ).toInt();
          // A card issued by this same decision is canceled or reinstated
          // together with it.
          for (final card in disciplinaryEvents) {
            if (card.minute == timeline.minute &&
                card.playerId == playerId &&
                card.canceled != canceling) {
              _applyCardToggle(card, player, canceling);
            }
          }
        }
      }
      timeline.canceled = canceling;
      banner = MatchBanner(
        timeline.kind == 'foul'
            ? (canceling ? 'FAUL KARARI IPTAL' : 'FAUL KARARI GERI ALINDI')
            : (canceling ? 'EL KARARI IPTAL' : 'EL KARARI GERI ALINDI'),
        "VAR ${timeline.minute}'",
        2.0,
        minute: timeline.minute,
        kind: 'var',
      );
      return;
    }
    if (timeline.kind == 'offside') {
      timeline.canceled = !timeline.canceled;
      banner = MatchBanner(
        timeline.canceled ? 'OFSAYT IPTAL' : 'OFSAYT GERI VERILDI',
        "VAR ${timeline.minute}'",
        2.0,
        minute: timeline.minute,
        kind: 'var',
      );
      return;
    }
    if (timeline.kind != 'yellowCard' && timeline.kind != 'redCard') {
      return;
    }
    DisciplinaryEvent? cardEvent;
    for (final event in disciplinaryEvents) {
      if (event.minute == timeline.minute &&
          event.playerId == timeline.relatedPlayerId &&
          event.isRed == (timeline.kind == 'redCard')) {
        cardEvent = event;
        break;
      }
    }
    final resolvedCard = cardEvent;
    if (resolvedCard == null) return;
    final players = allMatchPlayers.where(
      (player) => player.id == resolvedCard.playerId,
    );
    if (players.isEmpty) return;
    final player = players.first;
    _applyCardToggle(resolvedCard, player, !resolvedCard.canceled);
    timeline.canceled = resolvedCard.canceled;
    banner = MatchBanner(
      resolvedCard.canceled ? 'KART IPTAL' : 'KART GERI VERILDI',
      "VAR ${timeline.minute}' • ${resolvedCard.playerName}",
      2.0,
      minute: timeline.minute,
      kind: 'var',
    );
  }

  /// Applies or reverts the effects of a disciplinary event on the player.
  /// [canceling] removes the card; otherwise it reinstates it.
  void _applyCardToggle(DisciplinaryEvent card, PlayerGame player, bool canceling) {
    final delta = canceling ? -1 : 1;
    final includesYellow =
        card.card == 'yellow' || card.card == 'secondYellow';
    final includesRed = card.card == 'red' || card.card == 'secondYellow';
    if (includesYellow) {
      player.yellowCardsThisMatch = math.max(
        0,
        player.yellowCardsThisMatch + delta,
      ).toInt();
      player.matchYellowCards = math.max(
        0,
        player.matchYellowCards + delta,
      ).toInt();
      player.profile.yellowCards = math.max(
        0,
        player.profile.yellowCards + delta,
      ).toInt();
    }
    if (includesRed) {
      player.matchRedCards = math.max(
        0,
        player.matchRedCards + delta,
      ).toInt();
      player.profile.redCards = math.max(
        0,
        player.profile.redCards + delta,
      ).toInt();
      player.isSentOff = !canceling;
      if (canceling) {
        player
          ..pos = player.homePos.copy()
          ..controlled = false;
      } else {
        if (ball.owner == player) ball.owner = null;
        player
          ..pos = Vec2(-100, -100)
          ..controlled = false;
      }
    }
    if (card.suspensionMatches > 0) {
      player.profile.suspendedMatchesRemaining = canceling
          ? math.max(
              0,
              player.profile.suspendedMatchesRemaining -
                  card.suspensionMatches,
            ).toInt()
          : math.max(
              player.profile.suspendedMatchesRemaining,
              card.suspensionMatches,
            ).toInt();
    }
    card.canceled = canceling;
  }

  bool swapPlayerPositions(TeamId id, int firstIndex, int secondIndex) {
    final team = teamById(id);
    final swapped = team.swapPlayerPositions(firstIndex, secondIndex);
    if (swapped && firstIndex != secondIndex) {
      _startPause(
        '${team.name}: pozisyon degisikligi',
        'Oyuncu degisikligi hakki kullanilmadi',
        0.55,
        null,
      );
    }
    return swapped;
  }

  bool substitute(TeamId id, int outIndex, int benchIndex, {double minute = 0}) {
    final team = teamById(id);
    final ownerWasOut =
        outIndex >= 0 &&
        outIndex < team.players.length &&
        ball.owner == team.players[outIndex];
    final ok = team.substitute(outIndex, benchIndex, minute: minute);
    if (!ok) {
      return false;
    }
    if (ownerWasOut) {
      ball.attachTo(team.players[outIndex]);
    }
    _startPause(
      '${team.name}: oyuncu degisikligi',
      '${team.substitutionsUsed}/${team.substitutionLimit}',
      0.8,
      null,
    );
    return true;
  }

  /// Brings a previously substituted player back onto the pitch in place of
  /// an injured or sent-off player (outIndex). Their played minutes and
  /// stats are preserved because the same PlayerGame object returns.
  bool reenterSubstituted(
    TeamId id,
    int outIndex,
    PlayerGame incoming, {
    double minute = 0,
  }) {
    final team = teamById(id);
    final outgoing = (outIndex >= 0 && outIndex < team.players.length)
        ? team.players[outIndex]
        : null;
    if (outgoing == null || !substitutedOutContains(team, incoming)) {
      return false;
    }
    final ok = team.reenterSubstituted(outIndex, incoming, minute: minute);
    if (!ok) {
      return false;
    }
    _recordTimelineEvent(
      kind: 'substitution',
      title: 'SAHAYA DONUS',
      detail:
          '${outgoing.profile.name} cikti • ${incoming.profile.name} dondu',
      teamId: id,
      relatedPlayerId: incoming.id,
      minuteOverride: minute.ceil(),
    );
    _startPause(
      '${team.name}: oyuncu degisikligi',
      'sahan donusu — ${incoming.profile.name}',
      0.8,
      null,
    );
    return true;
  }

  bool substitutedOutContains(TeamGame team, PlayerGame player) =>
      team.substitutedOut.any((candidate) => candidate.id == player.id);

  /// Designates an outfield player as the team's goalkeeper for the rest of
  /// the match (used when the keeper is injured or sent off and there is no
  /// backup keeper). A keeper who can no longer play and is still in the XI
  /// leaves the match for good.
  void designateGoalkeeper(PlayerGame player) {
    if (player.role == PlayerRole.goalkeeper) {
      return;
    }
    player
      ..role = PlayerRole.goalkeeper
      ..restartTarget = null;
    final team = teamById(player.teamId);
    for (final lost in team.players
        .where(
          (keeper) =>
              keeper != player &&
              keeper.role == PlayerRole.goalkeeper &&
              (keeper.isInjuredInMatch || keeper.isSentOff),
        )
        .toList()) {
      lost
        ..exitedAtMinute = minute
        ..controlled = false;
      if (ball.owner == lost) {
        ball.owner = null;
      }
      team.players.remove(lost);
      team.removedFromMatch.add(lost);
    }
    _recordTimelineEvent(
      kind: 'goalkeeperDesignation',
      title: 'KALECI DEGISIKLIGI',
      detail: '${player.profile.name} kaleci olarak belirlendi',
      teamId: player.teamId,
      relatedPlayerId: player.id,
    );
    _startPause(
      'KALECI SECIMI',
      '${player.profile.name} artik kalede',
      1.2,
      null,
    );
  }

  void setSubstitutionPaused(bool value) {
    substitutionPaused = value;
  }

  /// Reverts the last substitution of [id]'s team (undo from the
  /// substitution panel).
  bool undoLastSubstitutionFor(TeamId id) {
    final team = teamById(id);
    final last = team.substitutionLog.isEmpty
        ? null
        : team.substitutionLog.last;
    final ok = team.undoLastSubstitution();
    if (!ok) {
      return false;
    }
    // If the ball was with the player who just came on, give it back to
    // the restored player so play does not continue with a bench player.
    if (last != null && ball.owner == last.incoming) {
      if (last.outIndex >= 0 && last.outIndex < team.players.length) {
        ball.attachTo(team.players[last.outIndex]);
      } else {
        ball.owner = null;
      }
    }
    _startPause(
      '${team.name}: degisiklik geri alindi',
      '${team.substitutionsUsed}/${team.substitutionLimit}',
      0.6,
      null,
    );
    return true;
  }

  FinishedMatchSummary? createFinishedSummary() {
    if (!finished) {
      return null;
    }
    final totalControl = math.max(1.0, blueControlSeconds + redControlSeconds);
    return FinishedMatchSummary(
      matchId: matchId,
      blueStorageTeamId: blueTeam.storageTeamId,
      redStorageTeamId: redTeam.storageTeamId,
      blueName: blueTeam.name,
      redName: redTeam.name,
      blueScore: blueTeam.score,
      redScore: redTeam.score,
      blueRatingDelta: _ratingDelta(blueTeam),
      redRatingDelta: _ratingDelta(redTeam),
      bluePossessionPercent: blueControlSeconds / totalControl * 100,
      redPossessionPercent: redControlSeconds / totalControl * 100,
      bluePasses: bluePasses,
      redPasses: redPasses,
      blueSuccessfulPasses: blueSuccessfulPasses,
      redSuccessfulPasses: redSuccessfulPasses,
      blueShots: blueShots,
      redShots: redShots,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      goals: reviewGoals.where((goal) => !goal.canceled).map((goal) {
        final assisters = allMatchPlayers.where(
          (player) => player.profile.id == goal.assisterPlayerId,
        );
        return FinishedGoalSummary(
          teamId: goal.teamId,
          scorerName: goal.scorerName,
          minute: goal.minute,
          isPenalty: goal.isPenalty,
          scorerPlayerId: goal.scorerPlayerId,
          assisterPlayerId: goal.assisterPlayerId,
          assisterName: assisters.isEmpty ? null : assisters.first.profile.name,
        );
      }).toList(),
      playerStats: allMatchPlayers
          .where((player) => player.minutesThisMatch > 0)
          .map(
            (player) => FinishedPlayerSummary(
              playerId: player.profile.id,
              teamId: player.teamId,
              name: player.profile.name,
              number: player.number,
              role: player.role.code,
              minutes: player.minutesThisMatch.round(),
              goals: player.matchGoals,
              assists: player.matchAssists,
              passes: player.matchPasses,
              successfulPasses: player.matchSuccessfulPasses,
              dribbles: player.matchDribbles,
              successfulDribbles: player.matchSuccessfulDribbles,
              tackles: player.matchTackles,
              shots: player.matchShots,
              shotsOnTarget: player.matchShotsOnTarget,
              missedChances: player.matchMissedChances,
              clearances: player.matchClearances,
              saves: player.matchSaves,
              foulsCommitted: player.matchFoulsCommitted,
              foulsReceived: player.matchFoulsReceived,
              yellowCards: player.matchYellowCards,
              redCards: player.matchRedCards,
              rating: matchRatingFor(player),
              staminaPercent: (player.stamina * 100).round(),
              injured: player.isInjuredInMatch,
            ),
          )
          .toList(),
    );
  }

  PlayerGame bestPlayer() {
    return allMatchPlayers.reduce(
      (a, b) => _playerMatchScore(a) >= _playerMatchScore(b) ? a : b,
    );
  }

  int playedMinutesFor(PlayerGame player) => player.minutesThisMatch.round();

  /// The periods (in match minutes) during which [player] was on the pitch.
  /// An open segment ends with null while the player is still in the game.
  List<(int, int?)> presenceSegmentsFor(PlayerGame player) {
    final team = teamById(player.teamId);
    final segments = <(int, int?)>[];
    var entry = 0.0;
    var everCameIn = false;
    for (final record in team.substitutionLog) {
      if (record.incoming.id == player.id) {
        entry = record.minute;
        everCameIn = true;
      } else if (record.outgoing.id == player.id) {
        segments.add((entry.ceil(), record.minute.ceil()));
      }
    }
    final onPitchNow = team.players.any(
      (candidate) => candidate.id == player.id && !candidate.isSentOff,
    );
    if (onPitchNow) {
      segments.add((entry.ceil(), null));
      return segments;
    }
    final inPitchList =
        team.players.any((candidate) => candidate.id == player.id);
    if (!everCameIn && segments.isEmpty && !inPitchList) {
      // Never played (pure bench player).
      return segments;
    }
    if (segments.isEmpty) {
      final exit = (player.exitedAtMinute ?? minute).ceil();
      segments.add((entry.ceil(), exit));
      return segments;
    }
    final last = segments.last;
    if (last.$2 == null) {
      final exit = (player.exitedAtMinute ?? minute).ceil();
      segments[segments.length - 1] = (last.$1, exit);
    } else if (player.exitedAtMinute != null &&
        player.exitedAtMinute!.ceil() > (last.$2 ?? 0)) {
      segments.add((entry.ceil(), player.exitedAtMinute!.ceil()));
    }
    return segments;
  }

  /// Compact VAR label, e.g. "0'-62' • 75'-" or "yedek".
  String presenceTextFor(PlayerGame player) {
    final segments = presenceSegmentsFor(player);
    if (segments.isEmpty) {
      return 'yedek';
    }
    return segments
        .map(
          (segment) =>
              "${segment.$1}'-${segment.$2 == null ? _matchMinuteNow() : '${segment.$2}\''}",
        )
        .join(' • ');
  }

  String _matchMinuteNow() => "${minute.toInt()}'";

  double matchRatingFor(PlayerGame player) =>
      _playerMatchRating(player, math.max(1, playedMinutesFor(player)).toInt());

  double _playerMatchScore(PlayerGame player) {
    return player.matchGoals * 7 +
        player.matchSuccessfulPasses * 0.35 +
        player.matchShotsOnTarget * 1.2 +
        player.matchClearances * 1.1 +
        player.matchSaves * 2.2 +
        (player.stamina - 0.5);
  }

  void _trackPossession(double dt) {
    if (ball.owner?.teamId == TeamId.blue ||
        (ball.owner == null && ball.pos.x < GameConstants.virtualWidth / 2)) {
      blueControlSeconds += dt;
    } else {
      redControlSeconds += dt;
    }
  }

  void _recordReplay(double dt) {
    _replayAccumulator += dt;
    if (_replayAccumulator < 0.08) {
      return;
    }
    _replayAccumulator = 0;
    replayFrames.add(
      ReplayFrame(
        minute: minute,
        ballX: ball.pos.x,
        ballY: ball.pos.y,
        ballHeight: ball.heightMeters,
        blueScore: blueTeam.score,
        redScore: redTeam.score,
        description: _replayDescription(),
        players: allPlayers
            .map((p) => ReplayPlayerFrame(id: p.id, x: p.pos.x, y: p.pos.y))
            .toList(),
      ),
    );
    if (replayFrames.length > 5200) {
      replayFrames.removeAt(0);
    }
  }

  String _replayDescription() {
    final owner = ball.owner;
    if (owner != null) {
      if (owner.isGoalkeeper) {
        return '${teamById(owner.teamId).name}: kaleci topu tuttu';
      }
      return '${owner.profile.name} topu kontrol ediyor';
    }
    if (ball.heightMeters > 0.08) {
      return 'Top havada ${ball.heightMeters.toStringAsFixed(2)} m';
    }
    if (ball.lastKickType == KickType.shoot) {
      return 'Sut yolda';
    }
    if (ball.lastKickType == KickType.highPass) {
      return 'Yuksek pas yolda';
    }
    return 'Top bosta';
  }

  /// While play is stopped — substitution panel open, VAR screen open or a
  /// referee pause — every player on the pitch rests and regains stamina.
  void _recoverStaminaWhileFrozen(double dt) {
    if (dt <= 0) {
      return;
    }
    for (final player in allPlayers) {
      if (player.stamina >= 1.0) {
        continue;
      }
      final rate = 0.010 + player.profile.staminaSkill * 0.012;
      player.stamina = (player.stamina + dt * rate)
          .clamp(0.0, 1.0)
          .toDouble();
    }
  }

  void _drainStamina(PlayerGame player, double pixelDistance) {
    if (pixelDistance <= 0.01 || activePenalty != null) {
      return;
    }
    final roleLoad = player.isGoalkeeper
        ? 0.18
        : player.role.isWide || player.role.isAttacker
        ? 1.12
        : 0.92;
    player.stamina = math.max(
      0.12,
      player.stamina -
          pixelDistance *
              0.000014 *
              roleLoad *
              (1.20 - player.profile.staminaSkill * 0.52),
    );
  }

  /// Pressing costs extra energy through the engine, so it cannot conflict
  /// with the normal movement drain handled above.
  void applyPressingStamina(TeamId id, double dt) {
    if (isFrozen || dt <= 0) {
      return;
    }
    for (final player in teamById(id).players) {
      if (player.isGoalkeeper) {
        continue;
      }
      final endurance = 1.18 - player.profile.staminaSkill * 0.42;
      player.stamina = math.max(
        0.12,
        player.stamina - dt * 0.0024 * endurance,
      );
    }
  }

  AiPlayStyle playStyleFor(TeamId id) =>
      id == TeamId.blue ? bluePlayStyle : redPlayStyle;

  /// Set tactical override (press/defend) for a team.
  void setTacticalOverride(TeamId id, TeamMode? mode) {
    if (id == TeamId.blue) {
      blueTacticalOverride = mode;
    } else {
      redTacticalOverride = mode;
    }
  }

  /// Get effective team mode considering tactical overrides.
  TeamMode effectiveTeamMode(TeamGame team) {
    final override = team.id == TeamId.blue
        ? blueTacticalOverride
        : redTacticalOverride;
    if (override != null) return override;
    return teamMode(team);
  }

  /// Direct player movement without AI check (used by AI itself).
  void _movePlayerDirect(PlayerGame player, Vec2 direction, double dt) {
    if (direction.isZero) {
      return;
    }
    final team = teamById(player.teamId);
    final step = direction * player.speed * _teamStrengthFactor(team) * dt * 60;
    player.pos = player.pos + step;
    _drainStamina(player, step.length);
    final movementDirection = direction.normalized();
    player
      ..turningIntensity = math.max(
        player.turningIntensity,
        ((1 - player.lastDirection.normalized().dot(movementDirection)) / 2)
            .clamp(0.0, 1.0)
            .toDouble(),
      )
      ..movementIntensity = 1.0
      ..lastDirection = movementDirection;
    player.keepInsideField();
    _clampRestartPosition(player);
    player.manualOverride = 0.28;
    if (player.pos.distanceTo(ball.pos) <
            player.radius + GameConstants.ballRadius + 8 &&
        _canReachBall(player) &&
        !_isRecentKicker(player) &&
        !_ballProtectedByKeeperAgainst(player.teamId)) {
      ball.attachTo(player);
    }
  }

  void _clampRestartPosition(PlayerGame player) {
    if (restartKind == RestartKind.freeKick &&
        _lockedWallPlayerIds.contains(player.id)) {
      final locked = _lockedWallPositions[player.id];
      if (locked != null) {
        player.pos.setFrom(locked);
      }
      return;
    }
    if (restartKind == RestartKind.kickoff) {
      final centerX = GameConstants.virtualWidth / 2;
      if (ball.owner == player && player.teamId == restartTeamId) {
        player.pos.x = player.pos.x
            .clamp(centerX - 14, centerX + 14)
            .toDouble();
        return;
      }
      final team = teamById(player.teamId);
      if (team.side == TeamSide.left && player.pos.x > centerX - 8) {
        player.pos.x = centerX - 8;
      } else if (team.side == TeamSide.right && player.pos.x < centerX + 8) {
        player.pos.x = centerX + 8;
      }
    }
    if (restartKind == RestartKind.freeKick && restartTeamId != null &&
        player.teamId != restartTeamId) {
      final away = player.pos - ball.pos;
      if (away.length < 66) {
        final direction = away.normalized(
          Vec2(teamById(player.teamId).attackDirection.toDouble(), 0),
        );
        player.pos = ball.pos + direction * 66;
        player.keepInsideField();
      }
    }
    if (restartKind == RestartKind.goalKick && restartTeamId != null) {
      final defending = teamById(restartTeamId!);
      if (player.teamId != restartTeamId) {
        // Opponents keep their general position for a goal kick — they
        // are only pushed back if they are closer to the goal than a
        // third of the pitch.
        final limitX = defending.side == TeamSide.left
            ? GameConstants.leftBound +
                GameConstants.pitchWidth / 3.0 +
                24.0
            : GameConstants.rightBound -
                GameConstants.pitchWidth / 3.0 -
                24.0;
        if (defending.side == TeamSide.left) {
          if (player.pos.x < limitX) {
            player.pos.x = limitX;
          }
        } else if (player.pos.x > limitX) {
          player.pos.x = limitX;
        }
      }
    }
  }

  void _enforceRestartRestrictions() {
    if (restartKind == null) {
      return;
    }
    for (final player in allMatchPlayers) {
      _clampRestartPosition(player);
    }
    final spot = _restartSpot;
    if (spot != null) {
      ball
        ..pos = spot.copy()
        ..vel = Vec2.zero()
        ..heightMeters = 0
        ..verticalVelocity = 0;
    }
  }

  void _finishRestartFor(TeamGame team) {
    if (restartTeamId == team.id) {
      final finishedKind = restartKind;
      if (finishedKind == RestartKind.corner) {
        setPieceAttackTeamId = team.id;
        setPieceAttackTimer = 5.2;
        _cornerReadyOverride = false;
      }
      if (finishedKind == RestartKind.freeKick) {
        for (final player in allMatchPlayers.where(
          (candidate) => _lockedWallPlayerIds.contains(candidate.id),
        )) {
          player
            ..jumpBoostMeters = math.max(player.jumpBoostMeters, 0.13)
            ..jumpAnimationTimer = 0.48;
        }
      }
      restartKind = null;
      restartTeamId = null;
      _restartSpot = null;
      _lockedWallPlayerIds.clear();
      _lockedWallPositions.clear();
      for (final player in allPlayers) {
        player.restartTarget = null;
      }
    }
  }

  void _tickSetPieceAttack(double dt) {
    if (setPieceAttackTeamId == null) {
      return;
    }
    if (ball.owner != null && ball.owner!.teamId != setPieceAttackTeamId) {
      setPieceAttackTeamId = null;
      setPieceAttackTimer = 0;
      return;
    }
    setPieceAttackTimer = math.max(0, setPieceAttackTimer - dt);
    if (setPieceAttackTimer <= 0) {
      setPieceAttackTeamId = null;
    }
  }

  void _recordKickStats(
    PlayerGame player,
    TeamGame team,
    KickType type,
    Vec2 direction, {
    required double power,
    required double loft,
    double curve = 0,
  }) {
    if (type == KickType.pass || type == KickType.highPass) {
      player.profile.passes += 1;
      player.matchPasses += 1;
      if (team.id == TeamId.blue) {
        bluePasses += 1;
      } else {
        redPasses += 1;
      }
      final ownThird = team.attackDirection == 1
          ? player.pos.x < GameConstants.virtualWidth * 0.34
          : player.pos.x > GameConstants.virtualWidth * 0.66;
      if (type == KickType.highPass && ownThird) {
        player.profile.clearances += 1;
        player.matchClearances += 1;
      }
    } else if (type == KickType.shoot) {
      // A "shot" that is not even directed at the opponent goal is just a
      // long ball (distance) — it never counts as a shot. Only strikes
      // that head towards the goal count in the stats.
      final goal = goalCenterFor(team);
      final toGoal = goal - ball.pos;
      if (toGoal.lengthSquared > 1) {
        final aim = direction.normalized(
          Vec2(team.attackDirection.toDouble(), 0),
        );
        final towardGoal = aim.dot(
          toGoal.normalized(Vec2(team.attackDirection.toDouble(), 0)),
        );
        if (towardGoal < 0.30) {
          return;
        }
      }
      player.profile.shots += 1;
      player.matchShots += 1;
      if (team.id == TeamId.blue) {
        blueShots += 1;
      } else {
        redShots += 1;
      }
      final projectedY = _shotTargetY(team, direction);
      final top =
          GameConstants.virtualHeight / 2 - GameConstants.goalPixelHeight / 2;
      final bottom =
          GameConstants.virtualHeight / 2 + GameConstants.goalPixelHeight / 2;
      final goalX = goalCenterFor(team).x;
      final horizontalSpeed = math.max(0.1, _shotLaunchSpeed(player, power) * 60);
      final flightSeconds = (goalX - ball.pos.x).abs() / horizontalSpeed;
      final shotGravity = restartKind == RestartKind.freeKick
          ? GameConstants.gravityMeters * 5.30
          : GameConstants.gravityMeters;
      final curvedProjectedY = projectedY == null
          ? null
          : projectedY + curve * flightSeconds * flightSeconds * 30;
      final projectedHeight = math.max(
        0.0,
        ball.heightMeters +
            loft * flightSeconds -
            0.5 * shotGravity * flightSeconds * flightSeconds,
      );
      if (curvedProjectedY != null &&
          curvedProjectedY > top &&
          curvedProjectedY < bottom &&
          projectedHeight < GameConstants.crossbarMinMeters) {
        player.profile.shotsOnTarget += 1;
        player.matchShotsOnTarget += 1;
      } else {
        player.profile.missedChances += 1;
        player.matchMissedChances += 1;
      }
    }
  }

  /// Launch speed of a shot in pixels/frame, scaled by the shooter's
  /// shot-power rating. Mirrors BallGame.release() so the shot-on-target
  /// projection uses the same speed the physics will produce.
  double _shotLaunchSpeed(PlayerGame shooter, double power) {
    final shotPowerSkill = shooter.profile.shotPowerRating / 100.0;
    return (9.2 + shotPowerSkill * 3.6) * power;
  }

  /// A pass is successful the moment ANY of the passer's teammates touches
  /// the ball — a clean reception or even a deflection. Each pass is
  /// counted at most once (guarded by ball.passSuccessCounted).
  void _markPassSuccessfulIfDue(PlayerGame toucher) {
    final passer = ball.lastPasser;
    if (passer == null || passer == toucher) {
      return;
    }
    if (passer.teamId != toucher.teamId) {
      return;
    }
    if (ball.lastKickType != KickType.pass &&
        ball.lastKickType != KickType.highPass) {
      return;
    }
    if (ball.passSuccessCounted) {
      return;
    }
    ball.passSuccessCounted = true;
    passer.profile.successfulPasses += 1;
    passer.matchSuccessfulPasses += 1;
    if (passer.teamId == TeamId.blue) {
      blueSuccessfulPasses += 1;
    } else {
      redSuccessfulPasses += 1;
    }
  }

  void _recordReception(PlayerGame receiver) {
    final passer = ball.lastPasser;
    if (passer == null ||
        passer == receiver ||
        passer.teamId != receiver.teamId ||
        (ball.lastKickType != KickType.pass &&
            ball.lastKickType != KickType.highPass)) {
      return;
    }
    // As soon as a teammate touches the ball the pass is successful.
    _markPassSuccessfulIfDue(receiver);
    // Track assists: if the receiver scores a goal within reasonable time
    // (handled in _scoreGoal), and dribble tracking
    receiver.matchDribbles += 1;
    receiver.matchSuccessfulDribbles += 1;
  }

  void takeContextualShot(
    PlayerGame player,
    TeamGame team,
    double power, {
    bool firstTime = false,
    double incomingBallSpeed = 0,
    double? incomingBallHeight,
  }) {
    final shot = _calculateShot(
      player,
      team,
      power,
      firstTime: firstTime,
      incomingBallSpeed: incomingBallSpeed,
      incomingBallHeight: incomingBallHeight ?? ball.heightMeters,
      freeKick: restartKind == RestartKind.freeKick && restartTeamId == team.id,
    );
    shotDiagnostics.record(shot);
    releaseFromPlayer(
      player,
      shot.launchTarget - ball.pos,
      shot.power,
      type: KickType.shoot,
      loft: shot.verticalVelocity,
      curve: shot.curve,
      spin: shot.curve.abs(),
      shotType: shot.shotType,
    );
  }

  ShotResult _calculateShot(
    PlayerGame player,
    TeamGame team,
    double rawPower, {
    required bool firstTime,
    required double incomingBallSpeed,
    required double incomingBallHeight,
    required bool freeKick,
  }) {
    final intendedTarget = _intendedShotTarget(player, team);
    final toTarget = intendedTarget - player.pos;
    final facing = player.lastDirection.normalized(
      Vec2(team.attackDirection.toDouble(), 0),
    );
    final targetDirection = toTarget.normalized(
      Vec2(team.attackDirection.toDouble(), 0),
    );
    final dot = facing.dot(targetDirection).clamp(-1.0, 1.0).toDouble();
    final facingAngleDegrees = math.acos(dot) * 180 / math.pi;
    final opponents = opponentOf(team).players.where((p) => !p.isSentOff);
    final nearestDefenderMeters = opponents.isEmpty
        ? 10.0
        : opponents
              .map((defender) => _pitchDistanceMeters(defender.pos, player.pos))
              .reduce(math.min);
    final distanceMeters = _pitchDistanceMeters(player.pos, intendedTarget);
    final powerInput = ((rawPower - 0.55) / 1.0)
        .clamp(0.0, 1.0)
        .toDouble();
    final shotType = _shotTypeFor(
      player,
      team,
      distanceMeters,
      powerInput,
      firstTime: firstTime,
      incomingBallHeight: incomingBallHeight,
      freeKick: freeKick,
    );
    final leaningBack = (powerInput - 0.66) * 0.58 +
        player.turningIntensity * 0.30 -
        player.profile.balanceSkill * 0.08;
    final supportFootQuality = (0.66 +
            player.profile.balanceSkill * 0.24 +
            player.profile.composureSkill * 0.10 -
            player.turningIntensity * 0.22)
        .clamp(0.15, 1.0)
        .toDouble();
    final lateral = (intendedTarget.y - player.pos.y) * team.attackDirection;
    final usesRightFoot = lateral <= 0;
    final usingPreferredFoot =
        (usesRightFoot && player.profile.preferredFoot == PreferredFoot.right) ||
        (!usesRightFoot && player.profile.preferredFoot == PreferredFoot.left);
    final context = ShotContext(
      stats: player.profile.shootingStats,
      playerPosition: player.pos.copy(),
      intendedTarget: intendedTarget,
      facingAngleDegrees: facingAngleDegrees,
      distanceMeters: distanceMeters,
      nearestDefenderMeters: nearestDefenderMeters,
      movementRatio: player.movementIntensity.clamp(0.0, 1.0).toDouble(),
      sprinting: player.movementIntensity > 0.82,
      turning: player.turningIntensity > 0.30,
      incomingBallSpeed: incomingBallSpeed,
      ballHeight: incomingBallHeight,
      bodyLean: leaningBack.clamp(-1.0, 1.0).toDouble(),
      supportFootQuality: supportFootQuality,
      usingPreferredFoot: usingPreferredFoot,
      firstTime: firstTime,
      fatigue: (1 - player.stamina).clamp(0.0, 1.0).toDouble(),
      powerInput: powerInput,
      shotType: shotType,
      goalWidthPixels: GameConstants.goalPixelHeight,
      freeKick: freeKick,
    );
    return _shotCalculator.calculate(context);
  }

  ShotType _shotTypeFor(
    PlayerGame player,
    TeamGame team,
    double distanceMeters,
    double powerInput, {
    required bool firstTime,
    required double incomingBallHeight,
    required bool freeKick,
  }) {
    if (firstTime) {
      return incomingBallHeight >= player.profile.heightMeters * 0.70
          ? ShotType.header
          : ShotType.volley;
    }
    final keeper = opponentOf(team).goalkeeper;
    final keeperAdvanced =
        _pitchDistanceMeters(keeper.pos, goalCenterFor(team)) > 5.2;
    if (!freeKick &&
        keeperAdvanced &&
        distanceMeters < 18 &&
        powerInput < 0.42) {
      return ShotType.chip;
    }
    if (powerInput <= 0.22) return ShotType.ground;
    if (powerInput <= 0.40) return ShotType.low;
    if (powerInput >= 0.80) return ShotType.power;
    final wideBodyAngle =
        (player.pos.y - GameConstants.virtualHeight / 2).abs() > 72;
    if (player.profile.curveSkill >= 0.68 &&
        (wideBodyAngle || freeKick) &&
        powerInput < 0.76) {
      return ShotType.finesse;
    }
    return ShotType.normal;
  }

  Vec2 _intendedShotTarget(PlayerGame player, TeamGame team) {
    final goal = goalCenterFor(team);
    final keeper = opponentOf(team).goalkeeper;
    final centerY = GameConstants.virtualHeight / 2;
    final top = centerY - GameConstants.goalPixelHeight / 2 + 9;
    final bottom = centerY + GameConstants.goalPixelHeight / 2 - 9;
    final openGoal =
        keeper.pos.distanceTo(goal) >= 76 || keeper.keeperGroundTimer > 0.18;
    final aimTop = openGoal
        ? player.pos.y >= centerY
        : keeper.pos.y >= centerY;
    final edge = 9 + (1 - player.profile.composureSkill) * 11;
    final tacticalY = aimTop ? top + edge : bottom - edge;
    final facing = player.lastDirection.normalized(
      Vec2(team.attackDirection.toDouble(), 0),
    );
    final towardGoal = facing.x * team.attackDirection > 0.12;
    if (!towardGoal || facing.x.abs() < 0.05) {
      return Vec2(goal.x, tacticalY);
    }
    final timeToGoalLine = (goal.x - player.pos.x) / facing.x;
    final directionalY = (player.pos.y + facing.y * timeToGoalLine)
        .clamp(top - 48, bottom + 48)
        .toDouble();
    // Direction supplies the user's target; composure contributes a limited
    // tactical correction away from the goalkeeper without guaranteeing it.
    final correction = 0.18 + player.profile.composureSkill * 0.14;
    return Vec2(goal.x, directionalY * (1 - correction) + tacticalY * correction);
  }

  double _pitchDistanceMeters(Vec2 first, Vec2 second) {
    final dx = (first.x - second.x) * 105 / GameConstants.pitchWidth;
    final dy = (first.y - second.y) * 68 / GameConstants.pitchHeight;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _teamStrengthFactor(TeamGame team) {
    return (0.92 + team.rating.clamp(1, 99) / 100 * 0.16).clamp(0.92, 1.08);
  }

  double? _shotTargetY(TeamGame team, Vec2 direction) {
    if (direction.x.abs() < 0.01) {
      return null;
    }
    final goalX = goalCenterFor(team).x;
    final t = (goalX - ball.pos.x) / direction.x;
    if (t <= 0) {
      return null;
    }
    return ball.pos.y + direction.y * t;
  }

  Vec2 _cornerSpot(bool leftSide, bool topSide) {
    return Vec2(
      leftSide ? GameConstants.leftBound + 7 : GameConstants.rightBound - 7,
      topSide ? GameConstants.topBound + 7 : GameConstants.bottomBound - 7,
    );
  }

  Vec2 _goalKickSpot(TeamGame defending) {
    return Vec2(
      defending.side == TeamSide.left
          ? GameConstants.leftBound + 58
          : GameConstants.rightBound - 58,
      GameConstants.virtualHeight / 2 + (random.nextBool() ? -42 : 42),
    );
  }

  void _shapeRestartPlayers(
    TeamGame restartTeam,
    TeamGame defending, {
    required bool isCorner,
  }) {
    if (!isCorner) {
      // Goal kick: every player keeps his current position — nobody is
      // sent back to the halfway line. The restart position clamps only
      // push opponents out of the penalty area.
      for (final player in allPlayers) {
        player.restartTarget = null;
      }
      return;
    }
    final targetBoxX = defending.side == TeamSide.left
        ? GameConstants.leftBound + 120
        : GameConstants.rightBound - 120;
    var attackSlot = 0;
    for (final player in restartTeam.players.where((p) => !p.isGoalkeeper)) {
      if (player == ball.owner) {
        continue;
      }
      player.restartTarget = Vec2(
        targetBoxX + restartTeam.attackDirection * (attackSlot % 3) * 18 +
            (random.nextDouble() - 0.5) * 16,
        GameConstants.virtualHeight / 2 - 75 + attackSlot * 24 +
            (random.nextDouble() - 0.5) * 16,
      );
      attackSlot += 1;
    }
    // Defenders man-mark the attackers: each defender takes the attacking
    // player whose corner target is closest to him and stands between that
    // attacker and his own goal.
    final attackTargets = restartTeam.players
        .where((p) => !p.isGoalkeeper && p != ball.owner)
        .map((p) => MapEntry(p.id, p.restartTarget))
        .toList();
    var defendSlot = 0;
    for (final player in defending.players.where((p) => !p.isGoalkeeper)) {
      MapEntry<String, Vec2?>? marked;
      var bestDistance = double.infinity;
      for (final entry in attackTargets) {
        final target = entry.value;
        if (target == null) continue;
        final distance = target.distanceTo(player.pos);
        if (distance < bestDistance) {
          bestDistance = distance;
          marked = entry;
        }
      }
      if (marked != null && marked.value != null) {
        player.restartTarget = marked.value! +
            Vec2(
              defending.attackDirection * (14 + (defendSlot % 3) * 8),
              (defendSlot.isEven ? -1 : 1) * 6,
            );
      } else {
        player.restartTarget = Vec2(
          targetBoxX +
              defending.attackDirection * (24 + (defendSlot % 3) * 19),
          GameConstants.virtualHeight / 2 - 76 + defendSlot * 22 +
              (random.nextDouble() - 0.5) * 14,
        );
      }
      defendSlot += 1;
    }
  }

  void _commitPlayerMinutes() {
    if (_statsCommitted) {
      return;
    }
    _statsCommitted = true;
    for (final player in allMatchPlayers) {
      final minutes = player.minutesThisMatch.round();
      player.profile.minutesPlayed += minutes;
      if (minutes > 0) {
        final team = teamById(player.teamId);
        final opponent = opponentOf(team);
        final rating = _playerMatchRating(player, minutes);
        player.profile.matchesPlayed += 1;
        player.profile.points += rating;
        player.profile.addMatchRecord(
          PlayerMatchRecord(
            matchId: matchId,
            teamName: team.name,
            opponentName: opponent.name,
            scoreText: '${team.score}-${opponent.score}',
            minutes: minutes,
            goals: player.matchGoals,
            assists: player.matchAssists,
            passes: player.matchPasses,
            successfulPasses: player.matchSuccessfulPasses,
            dribbles: player.matchDribbles,
            successfulDribbles: player.matchSuccessfulDribbles,
            tackles: player.matchTackles,
            shots: player.matchShots,
            shotsOnTarget: player.matchShotsOnTarget,
            missedChances: player.matchMissedChances,
            clearances: player.matchClearances,
            saves: player.matchSaves,
            foulsCommitted: player.matchFoulsCommitted,
            foulsReceived: player.matchFoulsReceived,
            yellowCards: player.matchYellowCards,
            redCards: player.matchRedCards,
            rating: rating,
            injured: player.isInjuredInMatch,
          ),
        );
        player.profile.recalculateZekaGucu();
        _applyMatchAttributeDrift(player, rating);
      }
      player.profile
        ..fitness = player.stamina
        ..fitnessUpdatedAt = DateTime.now().millisecondsSinceEpoch;
    }
  }

  /// After every match the player's attributes drift a little: strength,
  /// IQ, shot power and the rest change with small, performance-based
  /// amounts instead of staying frozen.
  void _applyMatchAttributeDrift(PlayerGame player, double rating) {
    final profile = player.profile;
    double nudge(
      double value,
      double delta, {
      double lo = 40.0,
      double hi = 99.0,
    }) =>
        (value + delta).clamp(lo, hi).toDouble();

    // A gentle random walk so values evolve slowly match to match.
    final jitter = (random.nextDouble() - 0.5) * 0.8;
    final performance = (rating - 6.0) * 0.18;

    profile.overallRating = nudge(profile.overallRating, jitter + performance);
    profile.speedRating = nudge(profile.speedRating, jitter * 0.7);
    profile.composureRating = nudge(
      profile.composureRating,
      player.matchFoulsCommitted >= 4 ? -0.7 : performance * 0.5,
    );
    profile.balanceRating = nudge(profile.balanceRating, jitter * 0.5);
    profile.dayaniklilikGucu = nudge(
      profile.dayaniklilikGucu,
      player.stamina > 0.65 ? 0.3 : -0.3,
    );
    if (player.matchGoals >= 1) {
      profile.finishingRating = nudge(
        profile.finishingRating,
        0.6 + player.matchGoals * 0.3,
      );
    }
    if (player.matchShots >= 3) {
      profile.shotPowerRating = nudge(profile.shotPowerRating, 0.4);
      profile.shootingRating = nudge(profile.shootingRating, 0.3);
    }
    if (player.matchShotsOnTarget >= 2) {
      profile.longShotsRating = nudge(profile.longShotsRating, 0.4);
    }
    if (player.matchAssists >= 1) {
      profile.passingRating = nudge(profile.passingRating, 0.5);
      profile.curveRating = nudge(profile.curveRating, 0.3);
    }
    if (player.matchSuccessfulPasses >= 20) {
      profile.passingRating = nudge(profile.passingRating, 0.3);
    }
    if (player.matchTackles >= 5 && player.role.isDefender) {
      profile.dayaniklilikGucu = nudge(profile.dayaniklilikGucu, 0.4);
    }
    if (player.matchSaves >= 4 && player.isGoalkeeper) {
      profile.goalkeepingRating = nudge(profile.goalkeepingRating, 0.5);
      profile.goalkeeperDivingRating = nudge(profile.goalkeeperDivingRating, 0.3);
    }
    profile.zekaGucu = nudge(profile.zekaGucu, performance * 0.4);

    // The market value follows the (small) new attribute values.
    profile.recalculateMarketValue(strong: false);
  }

  double _playerMatchRating(PlayerGame player, int minutes) {
    final passRate = player.matchPasses == 0
        ? 0.0
        : player.matchSuccessfulPasses / player.matchPasses;
    final dribbleRate = player.matchDribbles == 0
        ? 0.0
        : player.matchSuccessfulDribbles / player.matchDribbles;
    final rating =
        5.7 +
        player.matchGoals * 1.2 +
        player.matchAssists * 0.85 +
        player.matchShotsOnTarget * 0.22 +
        player.matchSaves * 0.38 +
        player.matchClearances * 0.18 +
        player.matchTackles * 0.22 +
        passRate * 0.55 +
        dribbleRate * 0.28 +
        minutes / 90 * 0.35 -
        player.matchMissedChances * 0.18 -
        player.matchFoulsCommitted * 0.12 -
        player.matchYellowCards * 0.22 -
        player.matchRedCards * 1.10 -
        (1 - player.stamina) * 0.25;
    return rating.clamp(1, 10).toDouble();
  }

  double _ratingDelta(TeamGame team) {
    final totalControl = math.max(1.0, blueControlSeconds + redControlSeconds);
    final possession = team.id == TeamId.blue
        ? blueControlSeconds / totalControl
        : redControlSeconds / totalControl;
    final passes = team.id == TeamId.blue ? bluePasses : redPasses;
    final success = team.id == TeamId.blue
        ? blueSuccessfulPasses
        : redSuccessfulPasses;
    final passRate = passes == 0 ? 0.0 : success / passes;
    final shots = team.id == TeamId.blue ? blueShots : redShots;
    final scoreDiff = team.score - opponentOf(team).score;
    return scoreDiff * 1.8 +
        (possession - 0.5) * 4 +
        passRate * 2 +
        shots * 0.08;
  }

  PlayerGame? _targetInDirection(
    TeamGame team,
    PlayerGame player,
    Vec2 direction,
  ) {
    PlayerGame? best;
    var bestScore = -9999.0;
    for (final mate in team.players.where(
      (p) => p != player && !p.isGoalkeeper,
    )) {
      final toMate = mate.pos - player.pos;
      if (toMate.lengthSquared <= 1) {
        continue;
      }
      final dot = direction.normalized().dot(toMate.normalized());
      if (dot < 0.25) {
        continue;
      }
      final score = dot * 110 - (toMate.length - 185).abs() * 0.10;
      if (score > bestScore) {
        bestScore = score;
        best = mate;
      }
    }
    return best;
  }

  /// A goalkeeper who commits a foul goes down on the ground — the same
  /// "yerde" state the painter uses for keeper dives.
  void _knockFoulerDown(PlayerGame player) {
    if (!player.isGoalkeeper || player.isSentOff) {
      return;
    }
    player
      ..keeperGroundTimer = math.max(player.keeperGroundTimer, 1.1)
      ..jumpAnimationTimer = 0
      ..keeperState = 'yerde';
  }

  void _applyReviewedHandball({
    required PlayerGame offender,
    required PlayerGame? attacker,
    required TeamId attackingTeam,
    required Vec2 foulSpot,
    required bool inPenaltyBox,
    required String cardDecision,
  }) {
    offender.matchFoulsCommitted += 1;
    offender.profile.foulsCommitted += 1;
    _knockFoulerDown(offender);
    _recordTimelineEvent(
      kind: 'handball',
      title: 'ELLE OYNAMA',
      detail: offender.profile.name,
      teamId: offender.teamId,
      relatedPlayerId: offender.id,
    );
    if (attacker != null) {
      attacker.matchFoulsReceived += 1;
      attacker.profile.foulsReceived += 1;
    }
    final card = _issueCard(
      offender,
      violent: cardDecision == 'red',
      reckless: cardDecision == 'yellow',
      reason: 'VAR: elle tehlikeli atagi kesti',
      forcedCard: cardDecision == 'handball' ? 'none' : cardDecision,
    );
    ball
      ..owner = null
      ..pos = foulSpot.copy()
      ..vel = Vec2.zero()
      ..heightMeters = 0
      ..verticalVelocity = 0;
    if (inPenaltyBox) {
      startPenalty(attackingTeam, shootout: false);
      banner = MatchBanner(
        'VAR: PENALTI',
        '${offender.profile.name}: elle oynama${card == null ? '' : ' • ${card.title}'}',
        2.2,
        minute: minute.ceil(),
        kind: card?.isRed == true ? 'redCard' : 'var',
      );
    } else {
      _handleFreeKick(attackingTeam, foulSpot);
      _startPause(
        card?.title ?? 'VAR: ELLE OYNAMA',
        offender.profile.name,
        1.45,
        null,
        kind: card?.isRed == true
            ? 'redCard'
            : card != null
            ? 'yellowCard'
            : 'foul',
      );
    }
  }

  void _applyReviewedFoul({
    required PlayerGame victim,
    required PlayerGame fouler,
    required Vec2 foulSpot,
    required bool inPenaltyBox,
    required bool violent,
    required bool reckless,
    required String cardDecision,
  }) {
    fouler.profile.foulsCommitted += 1;
    fouler.matchFoulsCommitted += 1;
    _knockFoulerDown(fouler);
    _recordTimelineEvent(
      kind: 'foul',
      title: 'FAUL',
      detail: '${fouler.profile.name} → ${victim.profile.name}',
      teamId: fouler.teamId,
      relatedPlayerId: fouler.id,
    );
    victim.profile.foulsReceived += 1;
    victim.matchFoulsReceived += 1;
    final reason = cardDecision == 'red'
        ? 'VAR: asiri sert mudahale'
        : cardDecision == 'yellow'
        ? 'VAR: sert mudahale'
        : 'VAR: faul onaylandi';
    final card = _issueCard(
      fouler,
      violent: cardDecision == 'red',
      reckless: cardDecision == 'yellow',
      reason: reason,
      forcedCard: cardDecision,
    );
    _checkInjury(victim, violent: violent, reckless: reckless);
    ball
      ..owner = null
      ..pos = foulSpot.copy()
      ..vel = Vec2.zero()
      ..heightMeters = 0
      ..verticalVelocity = 0;
    final injuryText = victim.isInjuredInMatch ? ' • SAKATLIK' : '';
    if (inPenaltyBox) {
      startPenalty(victim.teamId, shootout: false);
      banner = MatchBanner(
        'VAR: PENALTI',
        '${fouler.profile.name}${card == null ? '' : ' • ${card.title}'}$injuryText',
        2.2,
        minute: minute.ceil(),
        kind: card?.isRed == true ? 'redCard' : 'var',
      );
    } else {
      _handleFreeKick(victim.teamId, foulSpot);
      _startPause(
        card?.title ?? 'VAR: FAUL',
        '${fouler.profile.name}: $reason$injuryText',
        1.55,
        null,
        kind: card?.isRed == true
            ? 'redCard'
            : card != null
            ? 'yellowCard'
            : 'foul',
      );
    }
  }

  DisciplinaryEvent? _issueCard(
    PlayerGame player, {
    required bool violent,
    required bool reckless,
    required String reason,
    String? forcedCard,
    int? eventMinute,
    int? eventReplayIndex,
  }) {
    if (forcedCard == 'none' || forcedCard == 'foul') {
      return null;
    }
    if (forcedCard == null &&
        !violent &&
        !reckless &&
        random.nextDouble() > 0.18) {
      return null;
    }

    var card = forcedCard ?? (violent ? 'red' : 'yellow');
    var suspension = 0;
    if (card == 'yellow') {
      player
        ..yellowCardsThisMatch += 1
        ..matchYellowCards += 1;
      player.profile.yellowCards += 1;
      if (player.yellowCardsThisMatch >= 2) {
        card = 'secondYellow';
      } else if (player.profile.yellowCards % 5 == 0) {
        suspension = 1;
        player.profile.suspendedMatchesRemaining = math.max(
          player.profile.suspendedMatchesRemaining,
          suspension,
        ).toInt();
      }
    }
    if (card == 'red' || card == 'secondYellow') {
      player
        ..isSentOff = true
        ..matchRedCards += 1
        ..controlled = false
        ..pos = Vec2(-100, -100)
        ..exitedAtMinute = minute;
      player.profile.redCards += 1;
      // Every red card, including a second yellow, carries a one-match
      // suspension. The CEZALAR page can adjust it administratively later.
      suspension = GameConstants.redCardSuspensionMatches;
      player.profile.suspendedMatchesRemaining = math.max(
        player.profile.suspendedMatchesRemaining,
        suspension,
      ).toInt();
      if (ball.owner == player) {
        ball.owner = null;
      }
    }
    final event = DisciplinaryEvent(
      teamId: player.teamId,
      playerId: player.id,
      playerName: player.profile.name,
      minute: eventMinute ?? minute.ceil(),
      card: card,
      reason: reason,
      suspensionMatches: suspension,
    );
    disciplinaryEvents.add(event);
    _recordTimelineEvent(
      kind: event.isRed ? 'redCard' : 'yellowCard',
      title: event.title,
      detail: '${event.playerName} • ${event.reason}',
      teamId: event.teamId,
      relatedPlayerId: player.id,
      minuteOverride: eventMinute,
      replayIndexOverride: eventReplayIndex,
    );
    return event;
  }

  /// Violent challenges always cause an injury; lesser fouls use fatigue and
  /// challenge severity to determine the chance and recovery period.
  void _checkInjury(
    PlayerGame victim, {
    required bool violent,
    required bool reckless,
  }) {
    if (victim.isInjuredInMatch) {
      return;
    }
    final fatigue = 1 - victim.stamina;
    final resistance = victim.profile.dayaniklilikSkill;
    // Injuries are kept rare: even violent challenges injure less than
    // half the time, and ordinary tackles almost never do.
    final rawChance = violent
        ? 0.38 + fatigue * 0.10
        : reckless
        ? 0.05 + fatigue * 0.12
        : 0.006 + fatigue * 0.03;
    final resistanceFactor = (1.18 - resistance * 0.78).clamp(0.38, 1.12);
    final injuryChance = (rawChance * resistanceFactor).clamp(0.008, 0.88);
    if (random.nextDouble() < injuryChance) {
      final minimum = violent ? 24 : reckless ? 9 : 5;
      final spread = violent ? 60 : reckless ? 34 : 17;
      final rawDays = minimum + random.nextInt(spread);
      final durationFactor = (1.34 - resistance * 0.72).clamp(0.62, 1.30);
      final days = (rawDays * durationFactor).round().clamp(4, 90).toInt();
      victim.profile.injuredDaysRemaining = days;
      // The recovery clock starts now: every real day reduces the injury
      // by one day.
      victim.profile.injuryUpdatedAt = DateTime.now().millisecondsSinceEpoch;
      victim.isInjuredInMatch = true;
      injuryEvents.add(
        InjuryEvent(
          playerName: victim.profile.name,
          teamId: victim.teamId,
          days: days,
          minute: minute.ceil(),
        ),
      );
      _recordTimelineEvent(
        kind: 'injury',
        title: 'SAKATLIK',
        detail: '${victim.profile.name} • $days gun',
        teamId: victim.teamId,
        relatedPlayerId: victim.id,
      );
      banner = MatchBanner(
        'SAKATLIK',
        '${victim.profile.name}: $days gun • rakibe +1 degisiklik',
        3.0,
        minute: minute.ceil(),
        kind: 'injury',
      );
      _queueForcedInjurySub(victim);
    }
  }

  void _queueForcedInjurySub(PlayerGame player) {
    if (!_forcedSubs.contains(player)) {
      _forcedSubs.add(player);
    }
    if (_injuryBonusAwardedPlayerIds.add(player.id)) {
      final opponent = opponentOf(teamById(player.teamId));
      opponent.bonusSubstitutions += 1;
      _recordTimelineEvent(
        kind: 'substitutionBonus',
        title: 'EK DEGISIKLIK HAKKI',
        detail:
            '${player.profile.name} sakatlandi • ${opponent.name} +1 degisiklik',
        teamId: opponent.id,
        relatedPlayerId: player.id,
      );
    }
  }

  /// Check if forced subs are needed due to injury.
  bool get hasInjuryForcedSub => _forcedSubs.isNotEmpty;

  PlayerGame? get nextInjuryForcedSub =>
      _forcedSubs.isEmpty ? null : _forcedSubs.first;

  PlayerGame? popInjuryForcedSub() {
    if (_forcedSubs.isEmpty) return null;
    return _forcedSubs.removeAt(0);
  }

  void removeInjuredWithoutReplacement(PlayerGame player) {
    player
      ..isSentOff = true
      ..controlled = false
      ..pos = Vec2(-100, -100)
      ..exitedAtMinute = minute;
    if (ball.owner == player) {
      ball.owner = null;
    }
    teamById(player.teamId).removedFromMatch.add(player);
  }

  /// Handle free kick: give ball to fouled team.
  void _handleFreeKick(TeamId fouledTeamId, Vec2 foulSpot) {
    final team = teamById(fouledTeamId);
    final defending = opponentOf(team);
    final taker = team.closestTo(foulSpot, includeGoalkeeper: true);
    restartKind = RestartKind.freeKick;
    restartTeamId = fouledTeamId;
    _restartSpot = foulSpot.copy();
    _lockedWallPlayerIds.clear();
    _lockedWallPositions.clear();
    ball
      ..owner = taker
      ..pos = foulSpot
      ..vel = Vec2.zero()
      ..heightMeters = 0
      ..verticalVelocity = 0;
    // Ball stays exactly on the foul/offside/handball spot while the taker
    // stands behind it.
    taker.pos = foulSpot - Vec2(team.attackDirection * 20, 0);
    taker.lastDirection = Vec2(team.attackDirection.toDouble(), 0);
    final nearGoal = foulSpot.distanceTo(goalCenterFor(team)) < 330;
    wallSelectionPending = nearGoal;
    wallDefendingTeamId = nearGoal ? defending.id : null;
    _wallCandidates
      ..clear()
      ..addAll(defending.players
          .where((player) => !player.isGoalkeeper && !player.isSentOff)
          .toList()
        ..sort((a, b) => a.pos.distanceTo(foulSpot)
            .compareTo(b.pos.distanceTo(foulSpot))));
    if (nearGoal && isTeamAiControlled(defending.id)) {
      chooseFreeKickWall(_wallCandidates.take(4).map((player) => player.id));
    }
    _shapeFreeKickSupport(team, defending, taker, nearGoal);
  }

  /// Both teams get real set-piece shape: the attacking team sends
  /// runners into and around the box so the taker always has targets, and
  /// the defending team (outside the wall) man-marks the runners so no
  /// gaps are left open.
  void _shapeFreeKickSupport(
    TeamGame attacking,
    TeamGame defending,
    PlayerGame taker,
    bool nearGoal,
  ) {
    final goal = goalCenterFor(attacking);
    var slot = 0;
    for (final attacker in attacking.players.where(
      (player) =>
          !player.isGoalkeeper &&
          player != taker &&
          !player.isSentOff &&
          !player.isInjuredInMatch,
    )) {
      if (nearGoal) {
        // A fan of runners inside and just outside the box.
        attacker.restartTarget = Vec2(
          goal.x - attacking.attackDirection * (16 + (slot % 3) * 30),
          GameConstants.virtualHeight / 2 -
              100 +
              (slot % 7) * 34 +
              (slot.isEven ? -12 : 12),
        )..clampTo(
            GameConstants.leftBound + 20,
            GameConstants.topBound + 20,
            GameConstants.rightBound - 20,
            GameConstants.bottomBound - 20,
          );
      } else {
        // Distant free kick: the attackers push up towards the box.
        attacker.restartTarget = Vec2(
          goal.x - attacking.attackDirection * (150 + (slot % 3) * 40),
          GameConstants.virtualHeight / 2 -
              90 +
              (slot % 5) * 44 +
              (slot.isEven ? -14 : 14),
        )..clampTo(
            GameConstants.leftBound + 20,
            GameConstants.topBound + 20,
            GameConstants.rightBound - 20,
            GameConstants.bottomBound - 20,
          );
      }
      slot += 1;
    }
    // Defenders (who are not in the wall) each take up the runner that is
    // closest to them and stand between that runner and their own goal.
    var defendSlot = 0;
    for (final defender in defending.players.where(
      (player) =>
          !player.isGoalkeeper &&
          !player.isSentOff &&
          !player.isInjuredInMatch,
    )) {
      PlayerGame? marked;
      var bestDistance = double.infinity;
      for (final attacker in attacking.players) {
        if (attacker == taker ||
            attacker.isGoalkeeper ||
            attacker.isSentOff ||
            attacker.restartTarget == null) {
          continue;
        }
        final distance = attacker.pos.distanceTo(defender.pos);
        if (distance < bestDistance) {
          bestDistance = distance;
          marked = attacker;
        }
      }
      if (marked != null && marked.restartTarget != null) {
        defender.restartTarget = marked.restartTarget! +
            Vec2(
              defending.attackDirection * (12 + (defendSlot % 3) * 8),
              defendSlot.isEven ? -8 : 8,
            )..clampTo(
                GameConstants.leftBound + 20,
                GameConstants.topBound + 20,
                GameConstants.rightBound - 20,
                GameConstants.bottomBound - 20,
              );
      } else {
        defender.restartTarget = Vec2(
          goalCenterFor(defending).x +
              defending.attackDirection * (60 + (defendSlot % 3) * 22),
          GameConstants.virtualHeight / 2 - 70 + defendSlot * 24,
        )..clampTo(
            GameConstants.leftBound + 20,
            GameConstants.topBound + 20,
            GameConstants.rightBound - 20,
            GameConstants.bottomBound - 20,
          );
      }
      defendSlot += 1;
    }
  }

  void chooseFreeKickWall(Iterable<String> playerIds) {
    if (!wallSelectionPending || wallDefendingTeamId == null) {
      return;
    }
    final defending = teamById(wallDefendingTeamId!);
    // Any number of players may join the wall — there is no cap.
    final selected = _wallCandidates
        .where((player) => playerIds.contains(player.id))
        .toList();
    wallSelectionPending = false;
    wallDefendingTeamId = null;
    _wallCandidates.clear();
    _lockedWallPlayerIds.clear();
    _lockedWallPositions.clear();
    if (selected.isEmpty) {
      return;
    }
    final ownGoal = goalCenterFor(opponentOf(defending));
    final towardGoal = (ownGoal - ball.pos).normalized(
      Vec2(-defending.attackDirection.toDouble(), 0),
    );
    // The wall stands clearly further from the ball than the 9.15 m rule
    // suggests — the user asked for extra space between ball and wall.
    final lineCenter = ball.pos + towardGoal * 98;
    final lateral = Vec2(-towardGoal.y, towardGoal.x);
    for (var index = 0; index < selected.length; index++) {
      final offset = index - (selected.length - 1) / 2;
      final wallPosition = lineCenter + lateral * (offset * 21);
      selected[index]
        ..restartTarget = null
        ..pos = wallPosition
        ..lastDirection = towardGoal * -1;
      _lockedWallPlayerIds.add(selected[index].id);
      _lockedWallPositions[selected[index].id] = wallPosition.copy();
    }
  }

  void declineFreeKickWall() => chooseFreeKickWall(const <String>[]);

  /// Check if the ball went out for a throw-in.
  void _checkThrowIn() {
    // Once a shot has crossed a goal line, let the goal-line routine finish
    // its visible flight; it must never turn into a throw-in near a corner.
    if (ball.pos.x < GameConstants.leftBound ||
        ball.pos.x > GameConstants.rightBound) {
      return;
    }
    // Keep the ball in the taker's hands until a pass releases it.
    if (restartKind == RestartKind.throwIn && ball.owner != null) {
      return;
    }
    // Throw-ins are only from the touchlines; goal lines are resolved above.
    final outTop =
        ball.pos.y + GameConstants.ballRadius < GameConstants.topBound;
    final outBottom =
        ball.pos.y - GameConstants.ballRadius > GameConstants.bottomBound;

    if (!outTop && !outBottom) return;

    final lastTouchTeam = ball.lastTouch?.teamId;
    final outX = ball.pos.x;
    final outY = outTop ? GameConstants.topBound : GameConstants.bottomBound;
    final throwInTeam = lastTouchTeam == null
        ? TeamId.blue
        : lastTouchTeam.opponent;
    final team = teamById(throwInTeam);
    final taker = team.closestTo(Vec2(outX, outY), includeGoalkeeper: false);

    // Clamp throw-in spot
    final spotX = outX
        .clamp(GameConstants.leftBound + 2, GameConstants.rightBound - 2)
        .toDouble();
    final spotY = outY
        .clamp(GameConstants.topBound + 2, GameConstants.bottomBound - 2)
        .toDouble();

    restartKind = RestartKind.throwIn;
    restartTeamId = throwInTeam;
    _restartSpot = Vec2(spotX, spotY);
    _offsideCandidate = null;
    _offsideExemptNextKick = true;
    ball
      ..owner = taker
      ..pos = Vec2(spotX, spotY)
      ..vel = Vec2.zero()
      ..heightMeters = 0
      ..verticalVelocity = 0;
    taker
      ..pos = Vec2(spotX - team.attackDirection * 14, spotY)
      ..lastDirection = Vec2(team.attackDirection.toDouble(), 0);
    _startPause('TAC', team.name, 0.6, null);
  }

  Vec2 _cornerDeliverySpot(TeamGame team, {required bool high}) {
    final goal = goalCenterFor(team);
    final spread = high ? 62.0 : 38.0;
    return Vec2(
      goal.x - team.attackDirection * (high ? 92 : 132),
      GameConstants.virtualHeight / 2 +
          (random.nextDouble() - 0.5) * spread * 2,
    );
  }

  /// Auto-control AI teams by simulating keyboard inputs.
  void _tickAiAutoControl(double dt) {
    if (activePenalty != null) {
      _tickAiPenalty(dt);
      return;
    }
    if (blueAiControlled) {
      _tickAiTeam(TeamId.blue, dt);
    }
    if (redAiControlled) {
      _tickAiTeam(TeamId.red, dt);
    }
  }

  void _tickAiTeam(TeamId id, double dt) {
    final team = teamById(id);

    // AI movement - move controlled player towards ball or tactical position
    final controlled = controlledPlayer(id);
    final ballPos = ball.pos;
    final takingRestart =
        restartKind != null && restartTeamId == id && ball.owner == controlled;
    if (!takingRestart) {
      final target = _aiMovementTarget(team, controlled, ballPos);
      final toTarget = target - controlled.pos;
      if (toTarget.length > 2) {
        // Direct movement bypassing AI check (since we ARE the AI)
        _movePlayerDirect(controlled, toTarget.normalized(), dt);
      }
    }

    // AI kicking decision
    _tickAiKickDecision(id, controlled, dt);
  }

  Vec2 _aiMovementTarget(TeamGame team, PlayerGame controlled, Vec2 ballPos) {
    final difficulty = aiDifficulty;
    final style = playStyleFor(team.id);

    // If we have the ball, move towards opponent goal
    if (ball.owner != null && ball.owner!.teamId == team.id) {
      // Move the ball carrier forward
      if (ball.owner == controlled) {
        final goalCenter = goalCenterFor(team);
        // Add some width variation based on role and style
        if (controlled.role.isWide) {
          final sideY = controlled.pos.y > GameConstants.virtualHeight / 2
              ? GameConstants.bottomBound - 70
              : GameConstants.topBound + 70;
          return Vec2(goalCenter.x, sideY);
        }
        return goalCenter;
      }
      // Support the ball carrier
      final carrier = ball.owner!;
      final supportSpacing = 60 * style.widthFactor;
      final supportX = carrier.pos.x + team.attackDirection * supportSpacing;
      final supportY =
          GameConstants.virtualHeight / 2 +
          (controlled.pos.y - GameConstants.virtualHeight / 2) * 0.4;
      return Vec2(supportX, supportY);
    }

    // If opponent has the ball, defend
    if (ball.owner != null && ball.owner!.teamId != team.id) {
      final carrier = ball.owner!;
      final distToCarrier = controlled.pos.distanceTo(carrier.pos);
      final pressRange =
          140 * difficulty.aggressionFactor * style.pressingIntensity;
      if (distToCarrier < pressRange || controlled.role.isDefender) {
        // Pressure the ball carrier
        return carrier.pos - Vec2(team.attackDirection * 16, 0);
      }
      // Defensive positioning - affected by defensive line
      final defensiveDepth = 80 * style.defensiveLineFactor;
      final defendX = team.side == TeamSide.left
          ? carrier.pos.x - defensiveDepth
          : carrier.pos.x + defensiveDepth;
      return Vec2(
        defendX
            .clamp(GameConstants.leftBound + 40, GameConstants.rightBound - 40)
            .toDouble(),
        carrier.pos.y
            .clamp(GameConstants.topBound + 40, GameConstants.bottomBound - 40)
            .toDouble(),
      );
    }

    // Loose ball - go get it
    return ballPos;
  }

  void _tickAiKickDecision(TeamId id, PlayerGame controlled, double dt) {
    final team = teamById(id);
    final opponent = opponentOf(team);
    final difficulty = aiDifficulty;

    // Only kick if we have the ball and aren't in a frozen state
    if (ball.owner != controlled) {
      return;
    }

    // Don't kick during kickoff if we're the kicking team and it hasn't started
    if (kickoffPending && restartTeamId == id) {
      // Take the kickoff after a brief pause
      if (minute > 0.02) {
        final mate = team.players.firstWhere(
          (p) => p != controlled && !p.isGoalkeeper,
          orElse: () => controlled,
        );
        if (mate != controlled) {
          releaseFromPlayer(
            controlled,
            mate.pos - ball.pos,
            0.62,
            type: KickType.pass,
            target: mate,
          );
        }
      }
      return;
    }

    // AI corners wait until every player has reached the set-piece shape.
    if (restartKind == RestartKind.corner && restartTeamId == id) {
      if (!canAiTakeCornerFor(team)) {
        return;
      }
      final candidates = team.players.where(
        (mate) => mate != controlled && !mate.isGoalkeeper,
      );
      final target = chooseBestPass(
        controlled,
        candidates,
        preferForward: false,
      );
      if (target != null) {
        releaseFromPlayer(
          controlled,
          target.pos - ball.pos,
          1.0,
          type: random.nextDouble() < 0.55 ? KickType.highPass : KickType.pass,
          target: target,
          loft: random.nextDouble() < 0.55 ? 5.5 : 0,
        );
      }
      return;
    }

    // Shooting decision
    final goalCenter = goalCenterFor(team);
    final distToGoal = controlled.pos.distanceTo(goalCenter);
    final finalThird = team.attackDirection == 1
        ? controlled.pos.x > GameConstants.virtualWidth * 0.68
        : controlled.pos.x < GameConstants.virtualWidth * 0.32;
    final goodAngle =
        (controlled.pos.y - GameConstants.virtualHeight / 2).abs() < 160;

    if (finalThird && goodAngle && distToGoal < 185) {
      final style = playStyleFor(id);
      final baseChance = (distToGoal < 120 ? 0.55 : 0.28);
      final shootChance =
          baseChance * difficulty.anticipationFactor * style.shootingTendency;
      if (random.nextDouble() < shootChance) {
        final shotPower = 1.08 + random.nextDouble() * 0.22;
        final directFreeKick =
            restartKind == RestartKind.freeKick && restartTeamId == id;
        final shot = _calculateShot(
          controlled,
          team,
          shotPower,
          firstTime: false,
          incomingBallSpeed: 0,
          incomingBallHeight: ball.heightMeters,
          freeKick: directFreeKick,
        );
        shotDiagnostics.record(shot);
        releaseFromPlayer(
          controlled,
          shot.launchTarget - ball.pos,
          shot.power,
          type: KickType.shoot,
          loft: shot.verticalVelocity,
          curve: shot.curve,
          spin: shot.curve.abs(),
          shotType: shot.shotType,
        );
        controlled.aiCooldown = 0.55 + random.nextDouble() * 0.35;
        return;
      }
    }

    // Passing decision - find best pass target
    final forwardTargets = team.players.where(
      (p) => p != controlled && !p.isGoalkeeper,
    );
    final bestTarget = chooseBestPass(
      controlled,
      forwardTargets,
      preferForward: true,
    );

    if (bestTarget != null) {
      final dist = controlled.pos.distanceTo(bestTarget.pos);
      final style = playStyleFor(id);
      final pressured = opponent.players.any(
        (p) =>
            p.pos.distanceTo(controlled.pos) <
            (42 * style.pressingIntensity + 18),
      );
      final passThreshold = 140 * style.passRangeFactor;
      if (dist > (60 * style.tempoFactor) &&
          (pressured ||
              dist > passThreshold ||
              random.nextDouble() < (0.15 * style.riskFactor))) {
        final highPass = dist > 180;
        releaseFromPlayer(
          controlled,
          bestTarget.pos - ball.pos,
          highPass ? 0.92 : 0.74,
          type: highPass ? KickType.highPass : KickType.pass,
          target: bestTarget,
          loft: highPass ? 5.0 + random.nextDouble() * 0.8 : 0,
        );
        controlled.aiCooldown = 0.38 + random.nextDouble() * 0.28;
        return;
      }
    }

    // Dribble forward if no good pass option
    final style = playStyleFor(id);
    final carryDistance = 55 * style.tempoFactor;
    final carryTarget =
        controlled.pos + Vec2(team.attackDirection * carryDistance, 0);
    _movePlayerDirect(controlled, (carryTarget - controlled.pos).normalized(), dt);
  }

  void _tickAiPenalty(double dt) {
    final penalty = activePenalty;
    if (penalty == null || penalty.result != null) {
      return;
    }

    final isBlueTurn = penalty.shootingTeam == TeamId.blue;
    final isAiTurn =
        (isBlueTurn && blueAiControlled) || (!isBlueTurn && redAiControlled);

    if (!isAiTurn) {
      return;
    }

    // AI penalty logic: choose direction and shoot
    final shooting = teamById(penalty.shootingTeam);
    final shooter =
        shooting.playerById(penalty.shooterId) ??
        shooting.players.firstWhere(
          (player) => !player.isSentOff && player.role == PlayerRole.striker,
          orElse: () => shooting.players.firstWhere(
            (player) => !player.isSentOff && !player.isGoalkeeper,
          ),
        );

    // Choose shot direction based on shooter skill
    final skill = shooter.profile.shotSkill;
    final preferredLane = skill > 0.7
        ? (random.nextBool() ? PenaltyLane.leftHigh : PenaltyLane.rightHigh)
        : (random.nextBool() ? PenaltyLane.leftLow : PenaltyLane.rightLow);

    selectPenaltyShot(preferredLane);

    // Give a human-controlled goalkeeper time to choose a dive direction.
    penalty.preparationTimer -= dt;
    if (penalty.preparationTimer <= 0) {
      takeInteractivePenalty(0.92 + random.nextDouble() * 0.38);
    }
  }
}
