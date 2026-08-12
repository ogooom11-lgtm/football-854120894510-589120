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
import '../models/team_game.dart';
import '../models/team_setup.dart';
import 'ball_physics.dart';
import 'goalkeeper_ai.dart';
import 'offside_logic.dart';
import 'penalty_logic.dart';
import 'player_ai.dart';

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
  bool wallSelectionPending = false;
  TeamId? wallDefendingTeamId;
  final List<PlayerGame> _wallCandidates = [];
  List<PlayerGame> get wallCandidates => List.unmodifiable(_wallCandidates);
  PlayerGame? _recentKicker;
  double _recentKickerGrace = 0;
  final List<ReplayFrame> replayFrames = [];
  bool replayMode = false;
  bool replayPlaying = false;
  int replayIndex = 0;
  double _replayPlaybackAccumulator = 0;
  bool substitutionPaused = false;
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
  final List<PlayerGame> _forcedSubs = [];
  double _replayAccumulator = 0;

  TeamGame get teamInPossession {
    if (ball.owner != null) {
      return teamById(ball.owner!.teamId);
    }
    return ball.pos.x < GameConstants.virtualWidth / 2
        ? teamBySide(TeamSide.left)
        : teamBySide(TeamSide.right);
  }

  List<PlayerGame> get allPlayers => [...blueTeam.players, ...redTeam.players];

  List<PlayerGame> get allMatchPlayers => [
    ...allPlayers,
    ...blueTeam.substitutedOut,
    ...redTeam.substitutedOut,
  ];

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
        (!_cornerPlayersAreSet() ||
            (_cornerManualWaitTeamId == team.id &&
                _cornerManualWaitTimer > 0));
  }

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
      return ball.owner!.teamId == team.id ? TeamMode.attack : TeamMode.defense;
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
      _tickReplay(dt);
      return;
    }
    if (finished) {
      return;
    }
    if (substitutionPaused) {
      return;
    }
    _tickCooldowns(dt);

    if (_pauseTimer > 0) {
      _pauseTimer -= dt;
      _recordReplay(dt);
      if (_pauseTimer <= 0) {
        final callback = _afterPause;
        _afterPause = null;
        banner = null;
        varReviewActive = false;
        varReason = null;
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
      _tickPenalty(dt);
      return;
    }

    minute += dt / GameConstants.realSecondsPerGameMinute;
    _trackPossession(dt);
    _tickSetPieceAttack(dt);
    _checkPeriodEnd();
    _tickAiAutoControl(dt);

    for (final team in [blueTeam, redTeam]) {
      final opponent = opponentOf(team);
      for (final player in team.players) {
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
    _preventOverlap();
    _enforceRestartRestrictions();
    _checkOffsideTouch();
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
    controlled.lastDirection = step.normalized(
      Vec2(team.attackDirection.toDouble(), 0),
    );
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

  PlayerGame controlledPlayer(TeamId id) {
    final team = teamById(id);
    final includeGoalkeeper =
        ball.owner == team.goalkeeper ||
        team.goalkeeper.pos.distanceTo(ball.pos) <
            GameConstants.goalkeeperRadius + GameConstants.ballRadius + 16;
    return team.closestTo(ball.pos, includeGoalkeeper: includeGoalkeeper);
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
    if (restartKind == RestartKind.goalKick && player != team.goalkeeper) {
      player = team.goalkeeper;
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
    if (restartKind == RestartKind.corner && !_cornerPlayersAreSet()) {
      return;
    }
    if (ball.owner != player) {
      ball.attachTo(player);
    }

    final maxPower = type == KickType.highPass
        ? restartKind == RestartKind.goalKick
            ? 2.65
            : restartKind == RestartKind.corner
            ? 2.40
            : 1.95
        : type == KickType.shoot
        ? 1.55
        : 1.45;
    final clampedPower = power.clamp(0.55, maxPower).toDouble();
    final direction = player.lastDirection.normalized(
      Vec2(team.attackDirection.toDouble(), 0),
    );
    PlayerGame? target;
    var kickDirection = direction;
    var loft = 0.0;
    var finalPower = clampedPower;

    if (type == KickType.shoot) {
      final shotError = _shotError(player, team, clampedPower);
      kickDirection =
          shotTargetFor(player, team, aimError: shotError) - ball.pos;
      final distanceToGoal = player.pos.distanceTo(goalCenterFor(team));
      final inPenaltyBox = isInPenaltyBox(
        player.pos,
        opponentOf(team).id,
      );
      final distanceFactor = (distanceToGoal / 420).clamp(0.0, 1.0);
      final highShotChance = 0.22 + distanceFactor * 0.54;
      final maximumHeight = inPenaltyBox ? 3.3 : 4.0;
      if (random.nextDouble() < highShotChance) {
        final minimumHeight = inPenaltyBox ? 0.20 : 0.55;
        final height = minimumHeight +
            (maximumHeight - minimumHeight) *
                (0.28 + random.nextDouble() * 0.72) *
                (0.72 + distanceFactor * 0.28);
        loft = math.sqrt(2 * GameConstants.gravityMeters * height)
            .clamp(0.0, math.sqrt(2 * GameConstants.gravityMeters * maximumHeight))
            .toDouble();
      } else {
        loft = 0;
      }
      finalPower = 0.68 + clampedPower * 0.20 + distanceFactor * 0.24;
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
        loft = 5.75 + clampedPower * 1.50;
        finalPower = 0.86 + clampedPower * 0.27;
      } else {
        finalPower = 0.74 + clampedPower * 0.22;
      }
    } else {
      target = _targetInDirection(team, player, direction);
      kickDirection = target == null ? direction : target.pos - ball.pos;
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

    releaseFromPlayer(
      player,
      kickDirection,
      finalPower,
      type: type,
      target: target,
      loft: loft,
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
    final shooters = shooting.players.where((p) => !p.isGoalkeeper).toList();
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
    final callback = _afterPause;
    _pauseTimer = 0;
    _afterPause = null;
    banner = null;
    varReviewActive = false;
    varReason = null;
    currentOffside = null;
    callback?.call();
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
      player.lastDirection = step.normalized();
    }
    player.keepInsideField();
    _clampRestartPosition(player);
  }

  void releaseFromPlayer(
    PlayerGame player,
    Vec2 direction,
    double power, {
    required KickType type,
    PlayerGame? target,
    double loft = 0,
  }) {
    final team = teamById(player.teamId);
    var adjustedDirection = direction;
    final skill = type == KickType.shoot
        ? player.profile.shotSkill
        : player.profile.passSkill;
    var adjustedPower = power * (0.82 + player.stamina * 0.13 + skill * 0.08);
    if (player.errorFactor > 0 || skill < 0.90) {
      final side = Vec2(-adjustedDirection.y, adjustedDirection.x).normalized();
      final errorScale =
          (type == KickType.shoot ? 54.0 : 92.0) * (1.18 - skill * 0.55);
      adjustedDirection +=
          side *
          ((random.nextDouble() - 0.5) * player.errorFactor * errorScale);
      if (type == KickType.shoot) {
        adjustedPower *= 1 - player.errorFactor * 0.08 + skill * 0.03;
      }
    }
    _recordKickStats(player, team, type, adjustedDirection);
    ball.release(
      direction: adjustedDirection,
      power: adjustedPower,
      toucher: player,
      receiver: target,
      kickType: type,
      loft: loft,
      highPass: type == KickType.highPass,
    );
    _recentKicker = player;
    _recentKickerGrace = type == KickType.highPass
        ? 0.30
        : type == KickType.shoot
        ? 0.22
        : 0.24;
    player.lastDirection = adjustedDirection.normalized(
      Vec2(team.attackDirection.toDouble(), 0),
    );
    _finishRestartFor(team);

    if (_offsideExemptNextKick) {
      _offsideExemptNextKick = false;
      _offsideCandidate = null;
      return;
    }

    if (type == KickType.pass || type == KickType.highPass) {
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
      if (mate == passer) {
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
    restartKind = RestartKind.kickoff;
    restartTeamId = ownerTeam;
    final owner = teamById(
      ownerTeam,
    ).players.firstWhere((player) => player.role == PlayerRole.striker);
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
      ..intendedReceiver = null
      ..lastKickType = null
      ..lastPassWasHigh = false
      ..hasBouncedSinceKick = false;
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
    final gameMinutes = dt / GameConstants.realSecondsPerGameMinute;
    for (final player in allPlayers) {
      player.minutesThisMatch += gameMinutes;
      player.aiCooldown = math.max(0, player.aiCooldown - dt);
      player.manualOverride = math.max(0, player.manualOverride - dt);
      player.keeperGroundTimer = math.max(0, player.keeperGroundTimer - dt);
      player.keeperDiveCooldown = math.max(0, player.keeperDiveCooldown - dt);
      player.keeperParryCooldown = math.max(
        0,
        player.keeperParryCooldown - dt,
      );
      if (player.isGoalkeeper && player.keeperGroundTimer <= 0) {
        player.keeperState = ball.owner == player ? 'top elde' : 'hazir';
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
      for (final defender in sorted.where((p) => p.teamId != owner.teamId)) {
        if (defender.pos.distanceTo(owner.pos) <
            defender.radius + owner.radius + 3) {
          final defendingTeam = teamById(defender.teamId);
          final tackleChance = defender.role.isDefender ? 0.32 : 0.20;
          final lateContact =
              (owner.pos.x - defender.pos.x) *
                  teamById(owner.teamId).attackDirection >
              -6;
          if (isInPenaltyBox(owner.pos, defendingTeam.id) &&
              lateContact &&
              random.nextDouble() < 0.025) {
            _startVarReview(
              'VAR PENALTI',
              'Ceza sahasinda kontrolsuz mudahale',
              () => startPenalty(owner.teamId, shootout: false),
            );
            return;
          }
          if (!isInPenaltyBox(owner.pos, defendingTeam.id) &&
              lateContact &&
              random.nextDouble() < 0.018) {
            defender.profile.foulsCommitted += 1;
            defender.matchFoulsCommitted += 1;
            owner.profile.foulsReceived += 1;
            owner.matchFoulsReceived += 1;
            _checkInjury(owner, defender, lateContact: lateContact);
            _handleFreeKick(owner.teamId, owner.pos.copy());
            _startPause(
              'FAUL',
              '${defender.profile.name}: kontrolsuz mudahale',
              1.1,
              null,
            );
            ball.vel = Vec2.zero();
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
      if (player.isGoalkeeper && player.keeperParryCooldown > 0) {
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

      if (_isLogicalHandball(player)) {
        final attackingTeam = ball.lastTouch?.teamId;
        if (attackingTeam != null && attackingTeam != player.teamId) {
          _deflectFromPlayer(player, strong: true);
          if (isInPenaltyBox(player.pos, player.teamId)) {
            _startVarReview(
              'VAR PENALTI',
              'Elle oynama: top el hizasinda ${ball.heightMeters.toStringAsFixed(2)} m yukseklikte oyuncuya carpti',
              () => startPenalty(attackingTeam, shootout: false),
            );
          } else {
            _handleFreeKick(attackingTeam, player.pos.copy());
            _startPause(
              'ELLE OYNAMA',
              '${player.profile.name}: ceza sahasi disinda el',
              1.25,
              null,
            );
          }
          return;
        }
      }

      if (!_canReachBall(player)) {
        continue;
      }

      if (ball.heightMeters > 1.15 && !player.isGoalkeeper) {
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
    final strongContact =
        ball.vel.length > 4.2 || ball.lastKickType == KickType.shoot;
    return inHandHeight && strongContact && random.nextDouble() < 0.28;
  }

  void _deflectFromPlayer(PlayerGame player, {required bool strong}) {
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
      ..heightMeters = math.max(ball.heightMeters, strong ? 0.18 : 0.05);
  }

  /// A saved shot normally remains live as a rebound instead of becoming a
  /// clean catch every time.
  void parryFromGoalkeeper(PlayerGame keeper) {
    final team = teamById(keeper.teamId);
    final reboundDirection = Vec2(
      team.attackDirection.toDouble(),
      (random.nextDouble() - 0.5) * 1.35,
    ).normalized(Vec2(team.attackDirection.toDouble(), 0));
    final reboundSpeed = math.max(3.6, ball.vel.length * 0.66) +
        random.nextDouble() * 1.25;
    ball
      ..owner = null
      ..lastTouch = keeper
      ..lastPasser = null
      ..intendedReceiver = null
      ..vel = reboundDirection * reboundSpeed
      ..heightMeters = math.max(ball.heightMeters, 0.12)
      ..verticalVelocity = ball.heightMeters > 0.45 ? 0.55 : 0.18;
    keeper
      ..keeperState = 'kurtaris'
      ..keeperGroundTimer = math.max(keeper.keeperGroundTimer, 0.32)
      ..keeperParryCooldown = 0.18;
    if (ball.lastKickType == KickType.shoot) {
      keeper.profile.saves += 1;
      keeper.matchSaves += 1;
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
      _startPause(
        'OFSAYT',
        '${candidate.event.kind}: ${candidate.event.offenderName}',
        GameConstants.replayFreezeSeconds,
        () {
          final defending = teamById(candidate.event.attackingTeam.opponent);
          final taker = defending.closestTo(
            restartSpot,
            includeGoalkeeper: false,
          );
          _handleFreeKick(defending.id, restartSpot);
        },
        isVar: true,
        reason: '${candidate.event.kind}: ${candidate.event.offenderName}',
      );
    } else if (minute - candidate.createdMinute > 2.2) {
      _offsideCandidate = null;
    }
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

    final inGoalMouth =
        ball.pos.y - GameConstants.ballRadius > goalTop &&
        ball.pos.y + GameConstants.ballRadius < goalBottom;
    if (inGoalMouth) {
      final hitsCrossbar =
          ball.heightMeters >= GameConstants.crossbarMinMeters - 0.16 &&
          ball.heightMeters <= GameConstants.crossbarMaxMeters + 0.16;
      if (hitsCrossbar) {
        ball
          ..pos = Vec2(
            crossedLeft
                ? GameConstants.leftBound + GameConstants.ballRadius + 0.5
                : GameConstants.rightBound - GameConstants.ballRadius - 0.5,
            ball.pos.y,
          )
          ..vel = Vec2(-ball.vel.x * 0.58, ball.vel.y * 0.74)
          ..verticalVelocity = -math.max(1.1, ball.verticalVelocity.abs() * 0.48);
        return;
      }
      if (ball.heightMeters < GameConstants.crossbarMinMeters) {
        final scoringTeam = crossedLeft
            ? teamBySide(TeamSide.right)
            : teamBySide(TeamSide.left);
        _scoreGoal(scoringTeam);
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
        ? attacking.players.firstWhere((p) => p.role.isWide)
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
    restartKind = isCorner ? RestartKind.corner : RestartKind.goalKick;
    restartTeamId = restartTeam.id;
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
    // Track assist: last passer before the shot gets an assist
    if (ball.lastPasser != null &&
        ball.lastPasser!.teamId == scoringTeam.id &&
        ball.lastKickType == KickType.pass) {
      ball.lastPasser!.matchAssists += 1;
      ball.lastPasser!.profile.assists += 1;
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
    scoringTeam.goals.add(
      GoalEvent(
        teamId: scoringTeam.id,
        scorerName: scorer,
        minute: minute.ceil(),
        isPenalty: isPenalty,
      ),
    );
    _startPause(
      'GOL',
      '${scoringTeam.name} - $scorer | top aglarda',
      2.0,
      () => resetKickoff(conceding.id),
    );
  }

  void startPenalty(TeamId shootingTeam, {required bool shootout}) {
    if (activePenalty != null || period == MatchPeriod.penalties && !shootout) {
      return;
    }
    final team = teamById(shootingTeam);
    final defending = opponentOf(team);
    final shooter = _placePenalty(team, defending);
    activePenalty = ActivePenalty(
      shootingTeam: shootingTeam,
      shootout: shootout,
      minute: minute.ceil(),
      shooterId: shooter.id,
    );
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
      defending.goalkeeper.keeperState = 'atlayis';
      defending.goalkeeper.keeperGroundTimer = math.max(
        defending.goalkeeper.keeperGroundTimer,
        0.55,
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
      resetKickoff(defending.id);
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
      ),
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
    final sideOffset = GameConstants.goalPixelHeight * 0.32;
    var targetY = switch (result.shotLane) {
      PenaltyLane.leftLow || PenaltyLane.leftHigh => goalCenterY - sideOffset,
      PenaltyLane.center => goalCenterY,
      PenaltyLane.rightLow || PenaltyLane.rightHigh => goalCenterY + sideOffset,
    };
    final savedSide = _samePenaltySide(result.shotLane, result.keeperLane);
    if (!result.scored && !savedSide) {
      targetY +=
          result.shotLane == PenaltyLane.leftLow ||
              result.shotLane == PenaltyLane.leftHigh
          ? -46
          : 46;
    }
    final target = Vec2(goalX, targetY);
    ball.release(
      direction: target - ball.pos,
      power: 1.12 + result.power * 0.22,
      toucher: shooter,
      receiver: null,
      kickType: KickType.shoot,
      loft: _penaltyLoft(result.heightMeters),
    );

    final keeperGoalX = defending.side == TeamSide.left
        ? GameConstants.leftBound + 14
        : GameConstants.rightBound - 14;
    final keeperY = switch (result.keeperLane) {
      PenaltyLane.leftLow || PenaltyLane.leftHigh => goalCenterY - sideOffset,
      PenaltyLane.center => goalCenterY,
      PenaltyLane.rightLow || PenaltyLane.rightHigh => goalCenterY + sideOffset,
    };
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

  PlayerGame _placePenalty(TeamGame shooting, TeamGame defending) {
    final shootingRight = shooting.side == TeamSide.left;
    final spotX = shootingRight
        ? GameConstants.rightBound - 88
        : GameConstants.leftBound + 88;
    final goalX = shootingRight
        ? GameConstants.rightBound - 8
        : GameConstants.leftBound + 8;
    final shooter = shooting.players.firstWhere(
      (p) => p.role == PlayerRole.striker,
    );
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
      _tickPenalty(dt);
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
  }) {
    banner = MatchBanner(title, subtitle, seconds);
    varReviewActive = isVar;
    varReason = reason;
    _pauseTimer = seconds;
    _afterPause = after;
  }

  void _startVarReview(String title, String reason, void Function() after) {
    _startPause(
      title,
      'VAR incelemesi: $reason',
      GameConstants.replayFreezeSeconds,
      after,
      isVar: true,
      reason: reason,
    );
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
    while (_replayPlaybackAccumulator >= 0.08) {
      _replayPlaybackAccumulator -= 0.08;
      replayIndex += 1;
      if (replayIndex >= replayFrames.length) {
        replayIndex = replayFrames.length - 1;
        replayPlaying = false;
        break;
      }
    }
  }

  void toggleGoalReview(int index) {
    final goals = reviewGoals;
    if (index < 0 || index >= goals.length) {
      return;
    }
    final goal = goals[index];
    final team = teamById(goal.teamId);
    goal.canceled = !goal.canceled;
    team.score += goal.canceled ? -1 : 1;
    team.score = math.max(0, team.score).toInt();
    banner = MatchBanner(
      goal.canceled ? 'GOL IPTAL' : 'GOL GERI ALINDI',
      "VAR karari: ${goal.minute}' ${goal.scorerName}",
      2.0,
    );
  }

  bool substitute(TeamId id, int outIndex, int benchIndex) {
    final team = teamById(id);
    final ownerWasOut =
        outIndex >= 0 &&
        outIndex < team.players.length &&
        ball.owner == team.players[outIndex];
    final ok = team.substitute(outIndex, benchIndex);
    if (!ok) {
      return false;
    }
    if (ownerWasOut) {
      ball.attachTo(team.players[outIndex]);
    }
    _startPause(
      '${team.name}: oyuncu degisikligi',
      '${team.substitutionsUsed}/5',
      0.8,
      null,
    );
    return true;
  }

  void setSubstitutionPaused(bool value) {
    substitutionPaused = value;
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
    );
  }

  PlayerGame bestPlayer() {
    return allMatchPlayers.reduce(
      (a, b) => _playerMatchScore(a) >= _playerMatchScore(b) ? a : b,
    );
  }

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
    player.lastDirection = direction;
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
        final centerX = GameConstants.virtualWidth / 2;
        if (defending.side == TeamSide.left && player.pos.x < centerX + 12) {
          player.pos.x = centerX + 12;
        } else if (defending.side == TeamSide.right &&
            player.pos.x > centerX - 12) {
          player.pos.x = centerX - 12;
        }
        if (isInPenaltyBox(player.pos, defending.id)) {
          player.pos.x = defending.side == TeamSide.left
              ? GameConstants.leftBound + 150
              : GameConstants.rightBound - 150;
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
  }

  void _finishRestartFor(TeamGame team) {
    if (restartTeamId == team.id) {
      final finishedKind = restartKind;
      if (finishedKind == RestartKind.corner) {
        setPieceAttackTeamId = team.id;
        setPieceAttackTimer = 5.2;
      }
      restartKind = null;
      restartTeamId = null;
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
    Vec2 direction,
  ) {
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
      player.profile.shots += 1;
      player.matchShots += 1;
      if (team.id == TeamId.blue) {
        blueShots += 1;
      } else {
        redShots += 1;
      }
      final projectedY = _shotTargetY(player, team, direction);
      final top =
          GameConstants.virtualHeight / 2 - GameConstants.goalPixelHeight / 2;
      final bottom =
          GameConstants.virtualHeight / 2 + GameConstants.goalPixelHeight / 2;
      if (projectedY != null && projectedY > top && projectedY < bottom) {
        player.profile.shotsOnTarget += 1;
        player.matchShotsOnTarget += 1;
      } else {
        player.profile.missedChances += 1;
        player.matchMissedChances += 1;
      }
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
    passer.profile.successfulPasses += 1;
    passer.matchSuccessfulPasses += 1;
    if (passer.teamId == TeamId.blue) {
      blueSuccessfulPasses += 1;
    } else {
      redSuccessfulPasses += 1;
    }
    // Track assists: if the receiver scores a goal within reasonable time
    // (handled in _scoreGoal), and dribble tracking
    receiver.matchDribbles += 1;
    receiver.matchSuccessfulDribbles += 1;
  }

  double _shotError(PlayerGame player, TeamGame team, double power) {
    final opponent = opponentOf(team);
    final pressure = opponent.players
        .map((p) => p.pos.distanceTo(player.pos))
        .reduce(math.min);
    final distance = player.pos.distanceTo(goalCenterFor(team));
    final pressurePenalty = pressure < 34
        ? 38
        : pressure < 58
        ? 18
        : 0;
    final distancePenalty = math.max(0, distance - 210) * 0.12;
    final powerPenalty = (power - 1.05).abs() * 22;
    final fatiguePenalty = player.errorFactor * 65;
    final skillBonus = player.profile.shootingRating * 0.42;
    final teamBonus = (team.rating - 50) * 0.35;
    final spread = math.max(
      5.0,
      10 +
          pressurePenalty +
          distancePenalty +
          powerPenalty +
          fatiguePenalty -
          skillBonus -
          teamBonus,
    );
    return (random.nextDouble() - random.nextDouble()) * spread;
  }

  /// Picks a target inside the goal, favouring the space away from the keeper.
  /// An open goal is aimed at a corner most of the time.
  Vec2 shotTargetFor(
    PlayerGame player,
    TeamGame attackingTeam, {
    double aimError = 0,
  }) {
    final goal = goalCenterFor(attackingTeam);
    final keeper = opponentOf(attackingTeam).goalkeeper;
    final centerY = GameConstants.virtualHeight / 2;
    final top = centerY - GameConstants.goalPixelHeight / 2 + 13;
    final bottom = centerY + GameConstants.goalPixelHeight / 2 - 13;
    final keeperInPosition =
        keeper.pos.distanceTo(goal) < 76 && keeper.keeperGroundTimer < 0.18;
    final openGoal = !keeperInPosition;

    double targetY;
    if (openGoal || random.nextDouble() < 0.78) {
      final aimTop = openGoal
          ? random.nextBool()
          : keeper.pos.y >= centerY;
      final edge = 8 + random.nextDouble() * 22;
      targetY = aimTop ? top + edge : bottom - edge;
    } else {
      // Keep a small share of shots central or low for natural variation.
      targetY = centerY + (random.nextDouble() - 0.5) * 34;
    }
    return Vec2(goal.x, (targetY + aimError).clamp(top, bottom).toDouble());
  }

  double _teamStrengthFactor(TeamGame team) {
    return (0.92 + team.rating.clamp(1, 99) / 100 * 0.16).clamp(0.92, 1.08);
  }

  double? _shotTargetY(PlayerGame player, TeamGame team, Vec2 direction) {
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
      final centerX = GameConstants.virtualWidth / 2;
      final opponent = opponentOf(defending);
      var opponentSlot = 0;
      for (final player in opponent.players) {
        if (player.isGoalkeeper) {
          continue;
        }
        player.restartTarget = Vec2(
          defending.side == TeamSide.left
              ? centerX + 34 + (random.nextDouble() - 0.5) * 28
              : centerX - 34 + (random.nextDouble() - 0.5) * 28,
          GameConstants.topBound + 88 + (opponentSlot % 5) * 72 +
              (random.nextDouble() - 0.5) * 22,
        );
        opponentSlot += 1;
      }
      var outletSlot = 0;
      for (final player in restartTeam.players.where((p) => !p.isGoalkeeper)) {
        final lane = outletSlot % 5;
        final row = outletSlot ~/ 5;
        player.restartTarget = Vec2(
          defending.side == TeamSide.left
              ? GameConstants.leftBound + 170 + row * 72 +
                  (random.nextDouble() - 0.5) * 30
              : GameConstants.rightBound - 170 - row * 72 +
                  (random.nextDouble() - 0.5) * 30,
          GameConstants.topBound + 96 + lane * 70 +
              (random.nextDouble() - 0.5) * 24,
        );
        outletSlot += 1;
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
    var defendSlot = 0;
    for (final player in defending.players.where((p) => !p.isGoalkeeper)) {
      player.restartTarget = Vec2(
        targetBoxX + defending.attackDirection * (24 + (defendSlot % 3) * 19),
        GameConstants.virtualHeight / 2 - 76 + defendSlot * 22 +
            (random.nextDouble() - 0.5) * 14,
      );
      defendSlot += 1;
    }
  }

  void _commitPlayerMinutes() {
    if (_statsCommitted) {
      return;
    }
    _statsCommitted = true;
    for (final player in allPlayers) {
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
            rating: rating,
            injured: player.isInjuredInMatch,
          ),
        );
      }
      player.profile
        ..fitness = player.stamina
        ..fitnessUpdatedAt = DateTime.now().millisecondsSinceEpoch;
      player.minutesThisMatch = 0;
    }
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

  /// Check if a player gets injured after a foul.
  void _checkInjury(
    PlayerGame victim,
    PlayerGame fouler, {
    required bool lateContact,
  }) {
    final fatigue = 1 - victim.stamina;
    final severity = lateContact ? 0.18 : 0.06;
    final injuryChance = fatigue * severity * 0.45;
    if (random.nextDouble() < injuryChance) {
      final days = (7 + random.nextInt(84)).clamp(7, 90);
      victim.profile.injuredDaysRemaining = days;
      victim.isInjuredInMatch = true;
      injuryEvents.add(
        InjuryEvent(
          playerName: victim.profile.name,
          teamId: victim.teamId,
          days: days,
          minute: minute.ceil(),
        ),
      );
      banner = MatchBanner(
        'SAKATLIK',
        '${victim.profile.name}: $days gun sahalardan uzak',
        3.0,
      );
      _forcedSubs.add(victim);
    }
  }

  /// Check if forced subs are needed due to injury.
  bool get hasInjuryForcedSub => _forcedSubs.isNotEmpty;

  PlayerGame? popInjuryForcedSub() {
    if (_forcedSubs.isEmpty) return null;
    return _forcedSubs.removeAt(0);
  }

  /// Handle free kick: give ball to fouled team.
  void _handleFreeKick(TeamId fouledTeamId, Vec2 foulSpot) {
    final team = teamById(fouledTeamId);
    final defending = opponentOf(team);
    final taker = team.closestTo(foulSpot, includeGoalkeeper: true);
    restartKind = RestartKind.freeKick;
    restartTeamId = fouledTeamId;
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
      ..addAll(defending.players.where((player) => !player.isGoalkeeper).toList()
        ..sort((a, b) => a.pos.distanceTo(foulSpot)
            .compareTo(b.pos.distanceTo(foulSpot))));
  }

  void chooseFreeKickWall(Iterable<String> playerIds) {
    if (!wallSelectionPending || wallDefendingTeamId == null) {
      return;
    }
    final defending = teamById(wallDefendingTeamId!);
    final selected = _wallCandidates
        .where((player) => playerIds.contains(player.id))
        .take(5)
        .toList();
    wallSelectionPending = false;
    wallDefendingTeamId = null;
    _wallCandidates.clear();
    if (selected.isEmpty) {
      return;
    }
    final ownGoal = goalCenterFor(opponentOf(defending));
    final towardGoal = (ownGoal - ball.pos).normalized(
      Vec2(-defending.attackDirection.toDouble(), 0),
    );
    final lineCenter = ball.pos + towardGoal * 66;
    final lateral = Vec2(-towardGoal.y, towardGoal.x);
    for (var index = 0; index < selected.length; index++) {
      final offset = index - (selected.length - 1) / 2;
      selected[index]
        ..restartTarget = null
        ..pos = lineCenter + lateral * (offset * 21)
        ..lastDirection = towardGoal * -1;
    }
  }

  void declineFreeKickWall() => chooseFreeKickWall(const <String>[]);

  /// Check if the ball went out for a throw-in.
  void _checkThrowIn() {
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
    final target = _aiMovementTarget(team, controlled, ballPos);
    final toTarget = target - controlled.pos;
    if (toTarget.length > 2) {
      // Direct movement bypassing AI check (since we ARE the AI)
      _movePlayerDirect(controlled, toTarget.normalized(), dt);
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

    // Corner kick handling
    if (isCornerWaitingForManualInputFor(team)) {
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
        releaseFromPlayer(
          controlled,
          shotTargetFor(controlled, team) - ball.pos,
          1.08 + random.nextDouble() * 0.22,
          type: KickType.shoot,
          loft: random.nextDouble() < 0.62
              ? 2.35 + random.nextDouble() * 1.10
              : 0,
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
    moveControlledTeam(id, (carryTarget - controlled.pos).normalized(), dt);
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
        shooting.players.firstWhere((p) => p.role == PlayerRole.striker);

    // Choose shot direction based on shooter skill
    final skill = shooter.profile.shotSkill;
    final preferredLane = skill > 0.7
        ? (random.nextBool() ? PenaltyLane.leftHigh : PenaltyLane.rightHigh)
        : (random.nextBool() ? PenaltyLane.leftLow : PenaltyLane.rightLow);

    selectPenaltyShot(preferredLane);

    // Take the kick after a brief delay
    if (penalty.countdown <= 0.1) {
      takeInteractivePenalty(0.92 + random.nextDouble() * 0.38);
    }
  }
}
