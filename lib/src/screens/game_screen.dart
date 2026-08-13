import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/enums/ai_difficulty.dart';
import '../game/enums/ai_play_style.dart';
import '../game/enums/kick_type.dart';
import '../game/enums/player_role.dart';
import '../game/enums/team_id.dart';
import '../game/logic/match_engine.dart';
import '../game/logic/penalty_logic.dart';
import '../game/math/vec2.dart';
import '../game/models/formation.dart';
import '../game/models/match_event.dart';
import '../game/models/player_game.dart';
import '../game/models/team_game.dart';
import '../game/models/team_setup.dart';
import '../render/game_painter.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.setup});

  final MatchSetup setup;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final MatchEngine _engine;
  late final Ticker _ticker;
  final FocusNode _focusNode = FocusNode();
  final Set<LogicalKeyboardKey> _pressed = {};
  final Set<String> _instantActionLocks = {};
  final Map<String, DateTime> _actionStarts = {};
  final Map<String, String> _actionPlayerIds = {};
  Duration? _lastTick;
  DateTime? _lastRPress;
  TeamId? _subTeam;
  int _subOutIndex = 0;
  int _subBenchIndex = 0;
  bool _subPickingBench = false;
  bool _bluePressing = false;
  bool _redPressing = false;
  bool _blueDefending = false;
  bool _redDefending = false;
  bool _injurySubActive = false;
  PlayerGame? _injuryVictim;
  final Set<String> _wallPlayerIds = {};
  String? _selectedTimelineEventId;
  bool _exitConfirmationOpen = false;
  bool _varPanelMinimized = false;
  double _varBallZoom = 1.0;
  String? _varTargetPlayerId;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _engine = MatchEngine(widget.setup);
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focusNode.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final last = _lastTick;
    _lastTick = elapsed;
    if (last == null || _exitConfirmationOpen) {
      return;
    }
    final dt = (elapsed - last).inMicroseconds / Duration.microsecondsPerSecond;
    _applyMovement(dt.clamp(0, 0.05).toDouble());
    _engine.tick(dt.clamp(0, 0.05).toDouble());
    _processForcedInjurySubstitution();
    if (mounted) {
      setState(() {});
    }
  }

  void _applyMovement(double dt) {
    if (_engine.activePenalty != null) {
      return;
    }
    final blue = _engine.blueAiControlled
        ? Vec2.zero()
        : Vec2(
            (_isPressed(LogicalKeyboardKey.arrowRight) ? 1 : 0) -
                (_isPressed(LogicalKeyboardKey.arrowLeft) ? 1 : 0),
            (_isPressed(LogicalKeyboardKey.arrowDown) ? 1 : 0) -
                (_isPressed(LogicalKeyboardKey.arrowUp) ? 1 : 0),
          );
    final red = _engine.redAiControlled
        ? Vec2.zero()
        : Vec2(
            (_isPressed(LogicalKeyboardKey.keyD) ? 1 : 0) -
                (_isPressed(LogicalKeyboardKey.keyA) ? 1 : 0),
            (_isPressed(LogicalKeyboardKey.keyS) ? 1 : 0) -
                (_isPressed(LogicalKeyboardKey.keyW) ? 1 : 0),
          );
    _engine.moveControlledTeam(TeamId.blue, blue, dt);
    _engine.moveControlledTeam(TeamId.red, red, dt);
    if (!blue.isZero) {
      _engine.markCornerManualControl(TeamId.blue);
    }
    if (!red.isZero) {
      _engine.markCornerManualControl(TeamId.red);
    }
    _trackHeldActions();
    // Extra stamina drain when pressing
    if (_bluePressing) _drainPressStamina(TeamId.blue, dt);
    if (_redPressing) _drainPressStamina(TeamId.red, dt);
  }

  Future<void> _confirmExitMatch() async {
    if (_exitConfirmationOpen || !mounted) {
      return;
    }
    setState(() => _exitConfirmationOpen = true);
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xff101820),
        icon: const Icon(
          Icons.exit_to_app,
          color: Color(0xffffd34d),
          size: 36,
        ),
        title: const Text(
          'هل تريد الخروج من المباراة؟',
          textAlign: TextAlign.center,
        ),
        content: Text(
          _engine.finished
              ? 'سيتم الرجوع إلى القائمة مع حفظ نتيجة المباراة.'
              : 'المباراة لم تنتهِ بعد. إذا خرجت الآن فلن تُحفظ نتيجة هذه المباراة.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            icon: const Icon(Icons.sports_soccer),
            label: const Text('لا، متابعة المباراة'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.exit_to_app),
            label: const Text('نعم، خروج'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _exitConfirmationOpen = false);
    if (shouldExit == true) {
      Navigator.of(context).pop(_engine.createFinishedSummary());
      return;
    }
    _focusNode.requestFocus();
  }

  void _onKey(KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      // Skip keyboard actions for AI-controlled teams
      final isBlueAction = _isBlueActionKey(key);
      final isRedAction = _isRedActionKey(key);
      if ((isBlueAction && _engine.blueAiControlled) ||
          (isRedAction && _engine.redAiControlled)) {
        return;
      }
      if (key == LogicalKeyboardKey.escape) {
        if (_subTeam != null) {
          _closeSubstitutionPanel();
        } else {
          _confirmExitMatch();
        }
        return;
      }
      if (_engine.replayMode) {
        if (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.keyA) {
          _engine.seekReplaySeconds(-3);
        } else if (key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.keyD) {
          _engine.seekReplaySeconds(3);
        } else if (key == LogicalKeyboardKey.space) {
          _engine.toggleReplayPlayback();
        } else if (key == LogicalKeyboardKey.keyG) {
          final goals = _engine.reviewGoals;
          if (goals.isNotEmpty) {
            _engine.toggleGoalReview(goals.length - 1);
          }
        }
        setState(() {});
        return;
      }
      if (_handleSubstitutionKey(key)) {
        setState(() {});
        return;
      }
      if (key == LogicalKeyboardKey.keyR && _handleReplayOpenKey()) {
        setState(() {});
        return;
      }
      if (_engine.varReviewActive &&
          (key == LogicalKeyboardKey.keyR ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter)) {
        _engine.skipCurrentReview();
        setState(() {});
        return;
      }
      if (_handlePenaltyDirectionKey(key)) {
        setState(() {});
        return;
      }
      // Tactical override keys
      if (key == LogicalKeyboardKey.numpad0 && !_engine.blueAiControlled) {
        setState(() {
          _bluePressing = !_bluePressing;
          _blueDefending = false;
          _engine.setTacticalOverride(
            TeamId.blue,
            _bluePressing ? TeamMode.press : null,
          );
        });
        return;
      }
      if (key == LogicalKeyboardKey.numpadDecimal &&
          !_engine.blueAiControlled) {
        setState(() {
          _blueDefending = !_blueDefending;
          _bluePressing = false;
          _engine.setTacticalOverride(
            TeamId.blue,
            _blueDefending ? TeamMode.defense : null,
          );
        });
        return;
      }
      if (key == LogicalKeyboardKey.digit0 && !_engine.redAiControlled) {
        setState(() {
          _redPressing = !_redPressing;
          _redDefending = false;
          _engine.setTacticalOverride(
            TeamId.red,
            _redPressing ? TeamMode.press : null,
          );
        });
        return;
      }
      if (key == LogicalKeyboardKey.backquote && !_engine.redAiControlled) {
        setState(() {
          _redDefending = !_redDefending;
          _redPressing = false;
          _engine.setTacticalOverride(
            TeamId.red,
            _redDefending ? TeamMode.defense : null,
          );
        });
        return;
      }
      if (_engine.activePenalty != null &&
          _engine.activePenalty!.result == null &&
          key == LogicalKeyboardKey.tab) {
        _engine.cyclePenaltyShooter();
        setState(() {});
        return;
      }
      _pressed.add(key);
      _startActionKey(key);
      if (key == LogicalKeyboardKey.keyV) {
        _engine.cycleFormation(TeamId.blue);
      }
      if (key == LogicalKeyboardKey.keyK) {
        _engine.cycleFormation(TeamId.red);
      }
      if (key == LogicalKeyboardKey.f1) {
        _openSubstitution(TeamId.blue);
      }
      if (key == LogicalKeyboardKey.f2) {
        _openSubstitution(TeamId.red);
      }
    } else if (event is KeyUpEvent) {
      _pressed.remove(key);
      _releaseActionKey(key);
    }
  }

  void _startActionKey(LogicalKeyboardKey key) {
    final penalty = _engine.activePenalty;
    if (penalty != null && penalty.result == null) {
      final action = _actionForKey(key);
      if (action != null &&
          action.$1 == penalty.shootingTeam &&
          action.$2 == KickType.shoot) {
        _actionStarts.putIfAbsent('penaltyShot', DateTime.now);
      }
      return;
    }
    final action = _actionForKey(key);
    if (action == null) {
      return;
    }
    final id = action.$1.name + action.$2.name;
    _engine.markCornerManualControl(action.$1);
    final controlled = _engine.controlledPlayer(action.$1);
    if (!_usesPressPower(action.$2)) {
      if (_instantActionLocks.contains(id)) {
        return;
      }
      _fireInstantAction(action, preferredPlayer: controlled, power: 0.94);
      _instantActionLocks.add(id);
      _actionStarts.remove(id);
      _actionPlayerIds.remove(id);
      return;
    }
    _actionStarts.putIfAbsent(id, DateTime.now);
    _actionPlayerIds.putIfAbsent(id, () => controlled.id);
  }

  void _releaseActionKey(LogicalKeyboardKey key) {
    final penalty = _engine.activePenalty;
    if (penalty != null && penalty.result == null) {
      final action = _actionForKey(key);
      if (action == null ||
          action.$1 != penalty.shootingTeam ||
          action.$2 != KickType.shoot) {
        return;
      }
      final started = _actionStarts.remove('penaltyShot');
      if (started == null) {
        return;
      }
      final ms = DateTime.now().difference(started).inMilliseconds;
      final power = (0.55 + ms / 900).clamp(0.55, 1.65).toDouble();
      _engine.takeInteractivePenalty(power);
      return;
    }
    final action = _actionForKey(key);
    if (action == null) {
      return;
    }
    final id = action.$1.name + action.$2.name;
    if (!_usesPressPower(action.$2)) {
      _instantActionLocks.remove(id);
      _actionStarts.remove(id);
      _actionPlayerIds.remove(id);
      return;
    }
    final started = _actionStarts.remove(id);
    if (started == null) {
      return;
    }
    final playerId = _actionPlayerIds.remove(id);
    final ms = DateTime.now().difference(started).inMilliseconds;
    final maxPower = action.$2 == KickType.highPass
        ? _engine.restartKind == RestartKind.goalKick
            ? 2.65
            : _engine.restartKind == RestartKind.corner
            ? 2.40
            : 1.95
        : 1.55;
    final power = (0.55 + ms / 820).clamp(0.55, maxPower).toDouble();
    _engine.manualKick(
      action.$1,
      action.$2,
      power,
      preferredPlayer: _playerById(action.$1, playerId),
    );
  }

  void _trackHeldActions() {
    if (_engine.activePenalty != null ||
        _engine.replayMode ||
        _subTeam != null) {
      return;
    }
    for (final key in _livePressedKeys) {
      final action = _actionForKey(key);
      if (action == null) {
        continue;
      }
      final id = action.$1.name + action.$2.name;
      _engine.markCornerManualControl(action.$1);
      if (!_usesPressPower(action.$2)) {
        if (_instantActionLocks.contains(id)) {
          continue;
        }
        _fireInstantAction(action, power: 0.94);
        _instantActionLocks.add(id);
        continue;
      }
      _actionStarts.putIfAbsent(id, DateTime.now);
      _actionPlayerIds.putIfAbsent(
        id,
        () => _engine.controlledPlayer(action.$1).id,
      );
    }
  }

  Set<LogicalKeyboardKey> get _livePressedKeys => {
    ..._pressed,
    ...HardwareKeyboard.instance.logicalKeysPressed,
  };

  bool _isPressed(LogicalKeyboardKey key) {
    return _pressed.contains(key) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(key);
  }

  bool _usesPressPower(KickType type) {
    return type == KickType.shoot || type == KickType.highPass;
  }

  void _fireInstantAction(
    (TeamId, KickType) action, {
    PlayerGame? preferredPlayer,
    required double power,
  }) {
    _engine.manualKick(
      action.$1,
      action.$2,
      power,
      preferredPlayer: preferredPlayer ?? _engine.controlledPlayer(action.$1),
    );
  }

  bool _handleReplayOpenKey() {
    final now = DateTime.now();
    final last = _lastRPress;
    _lastRPress = now;
    if (last == null || now.difference(last).inMilliseconds > 420) {
      return false;
    }
    _engine.openReplay(fromStart: true);
    _varPanelMinimized = false;
    _varBallZoom = 1.0;
    _varTargetPlayerId = null;
    return true;
  }

  PlayerGame? _playerById(TeamId teamId, String? playerId) {
    if (playerId == null) {
      return null;
    }
    final team = _engine.teamById(teamId);
    final matches = team.players.where((player) => player.id == playerId);
    return matches.isEmpty ? null : matches.first;
  }

  void _processForcedInjurySubstitution() {
    if (_engine.replayMode ||
        _subTeam != null ||
        !_engine.hasInjuryForcedSub) {
      return;
    }
    final victim = _engine.nextInjuryForcedSub;
    if (victim == null) return;
    final team = _engine.teamById(victim.teamId);
    final outIndex = team.players.indexOf(victim);
    final benchIndex = team.bench.indexWhere(
      (candidate) =>
          candidate.profile.isGoalkeeper == victim.profile.isGoalkeeper &&
          !candidate.profile.isUnavailable,
    );
    if (team.substitutionsUsed >= team.substitutionLimit ||
        benchIndex < 0 ||
        outIndex < 0) {
      _engine.popInjuryForcedSub();
      _engine.removeInjuredWithoutReplacement(victim);
      return;
    }
    if (_engine.isTeamAiControlled(victim.teamId)) {
      _engine.popInjuryForcedSub();
      _engine.substitute(victim.teamId, outIndex, benchIndex);
      return;
    }
    _openSubstitution(victim.teamId);
  }

  void _openSubstitution(TeamId teamId) {
    final team = _engine.teamById(teamId);
    if (team.players.isEmpty) return;
    final pendingVictim = _engine.nextInjuryForcedSub;
    final forcedForThisTeam =
        pendingVictim != null && pendingVictim.teamId == teamId;
    final victim = forcedForThisTeam ? pendingVictim : null;
    final compatibleBenchIndex = victim == null
        ? 0
        : team.bench.indexWhere(
            (candidate) =>
                candidate.profile.isGoalkeeper == victim.profile.isGoalkeeper &&
                !candidate.profile.isUnavailable,
          );
    setState(() {
      _subTeam = teamId;
      _injurySubActive = victim != null;
      _injuryVictim = victim;
      _subOutIndex = victim == null ? 0 : team.players.indexOf(victim).clamp(0, team.players.length - 1).toInt();
      _subBenchIndex = compatibleBenchIndex < 0 ? 0 : compatibleBenchIndex;
      _subPickingBench = false;
    });
    _engine.setSubstitutionPaused(true);
  }

  void _closeSubstitutionPanel() {
    if (_injurySubActive) return;
    setState(() {
      _subTeam = null;
      _injuryVictim = null;
      _subPickingBench = false;
    });
    _engine.setSubstitutionPaused(false);
    _focusNode.requestFocus();
  }

  bool _handleSubstitutionKey(LogicalKeyboardKey key) {
    final teamId = _subTeam;
    if (teamId == null) {
      return false;
    }
    final team = _engine.teamById(teamId);
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      if (_subPickingBench && team.bench.isNotEmpty) {
        _subBenchIndex = (_subBenchIndex - 1)
            .clamp(0, team.bench.length - 1)
            .toInt();
      } else if (!_injurySubActive) {
        _subOutIndex = (_subOutIndex - 1)
            .clamp(0, team.players.length - 1)
            .toInt();
      }
      return true;
    }
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyS) {
      if (_subPickingBench && team.bench.isNotEmpty) {
        _subBenchIndex = (_subBenchIndex + 1)
            .clamp(0, team.bench.length - 1)
            .toInt();
      } else if (!_injurySubActive) {
        _subOutIndex = (_subOutIndex + 1)
            .clamp(0, team.players.length - 1)
            .toInt();
      }
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
      _subPickingBench = false;
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD) {
      if (team.bench.isNotEmpty) _subPickingBench = true;
      return true;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (!_subPickingBench) {
        if (team.bench.isNotEmpty &&
            team.substitutionsUsed < team.substitutionLimit) {
          _subPickingBench = true;
        }
        return true;
      }
      if (team.bench.isNotEmpty &&
          _engine.substitute(teamId, _subOutIndex, _subBenchIndex)) {
        if (_injurySubActive) _engine.popInjuryForcedSub();
        _engine.setSubstitutionPaused(false);
        _subTeam = null;
        _injurySubActive = false;
        _injuryVictim = null;
      }
      return true;
    }
    return true;
  }

  (TeamId, KickType)? _actionForKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.numpad1) {
      return (TeamId.blue, KickType.shoot);
    }
    if (key == LogicalKeyboardKey.keyZ ||
        key == LogicalKeyboardKey.numpad2) {
      return (TeamId.blue, KickType.pass);
    }
    if (key == LogicalKeyboardKey.keyX ||
        key == LogicalKeyboardKey.numpad3) {
      return (TeamId.blue, KickType.highPass);
    }
    if (key == LogicalKeyboardKey.keyO ||
        key == LogicalKeyboardKey.digit1) {
      return (TeamId.red, KickType.shoot);
    }
    if (key == LogicalKeyboardKey.keyP ||
        key == LogicalKeyboardKey.digit2) {
      return (TeamId.red, KickType.pass);
    }
    if (key == LogicalKeyboardKey.keyL ||
        key == LogicalKeyboardKey.digit3) {
      return (TeamId.red, KickType.highPass);
    }
    return null;
  }

  bool _handlePenaltyDirectionKey(LogicalKeyboardKey key) {
    final penalty = _engine.activePenalty;
    if (penalty == null || penalty.result != null) {
      return false;
    }
    final shooting = penalty.shootingTeam;
    final defending = shooting.opponent;
    final shotLane = _laneForTeamKey(shooting, key);
    if (shotLane != null) {
      _engine.selectPenaltyShot(shotLane);
      return true;
    }
    final keeperLane = _laneForTeamKey(defending, key);
    if (keeperLane != null) {
      _engine.selectPenaltyKeeper(keeperLane);
      return true;
    }
    return false;
  }

  PenaltyLane? _laneForTeamKey(TeamId team, LogicalKeyboardKey key) {
    if (team == TeamId.blue) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        return PenaltyLane.leftLow;
      }
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        return PenaltyLane.center;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        return PenaltyLane.rightLow;
      }
    } else {
      if (key == LogicalKeyboardKey.keyA) {
        return PenaltyLane.leftLow;
      }
      if (key == LogicalKeyboardKey.keyW || key == LogicalKeyboardKey.keyS) {
        return PenaltyLane.center;
      }
      if (key == LogicalKeyboardKey.keyD) {
        return PenaltyLane.rightLow;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: const Color(0xff04100b),
        body: SizedBox.expand(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: GamePainter(
                    _engine,
                    replayZoom: _engine.replayMode ? _varBallZoom : 1.0,
                  ),
                ),
              ),
              if (!_engine.replayMode && !_engine.finished) _matchHud(),
              if (_engine.ball.owner?.isGoalkeeper == true &&
                  !_engine.isTeamAiControlled(_engine.ball.owner!.teamId) &&
                  !_engine.replayMode &&
                  !_engine.finished)
                _keeperDistributionControls(),
              if (_engine.banner != null) _banner(),
              if (_engine.wallSelectionPending) _freeKickWallPanel(),
              if (_engine.restartKind != null &&
                  _engine.restartTeamId != null &&
                  !_engine.isTeamAiControlled(_engine.restartTeamId!))
                _restartControlHint(),
              if (_engine.activePenalty != null &&
                  _engine.activePenalty!.result == null)
                _penaltyKeyboardHint(),
              if (_subTeam != null) _substitutionPanel(),
              if (_engine.replayMode) _replayPanel(),
              if (_engine.finished && !_engine.replayMode) _resultPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keeperDistributionControls() {
    final keeper = _engine.ball.owner!;
    final teamId = keeper.teamId;
    final passLabel = teamId == TeamId.blue ? 'Z / Numpad 2' : 'P / 2';
    final longLabel = teamId == TeamId.blue ? 'X / Numpad 3' : 'L / 3';
    return Positioned(
      left: 0,
      right: 0,
      bottom: 58,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xff07120e).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xff8bd3ff)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sports_handball, color: Color(0xff8bd3ff)),
              const SizedBox(width: 8),
              Text(
                '${keeper.profile.name}: topu oyuna sok',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: _engine.isFrozen
                    ? null
                    : () {
                        _engine.manualKick(
                          teamId,
                          KickType.pass,
                          0.92,
                          preferredPlayer: keeper,
                        );
                        setState(() {});
                      },
                icon: const Icon(Icons.arrow_forward, size: 17),
                label: Text('Pas $passLabel'),
              ),
              const SizedBox(width: 7),
              FilledButton.tonalIcon(
                onPressed: _engine.isFrozen
                    ? null
                    : () {
                        _engine.manualKick(
                          teamId,
                          KickType.highPass,
                          _engine.isGoalKickPendingFor(
                                _engine.teamById(teamId),
                              )
                              ? 2.1
                              : 1.35,
                          preferredPlayer: keeper,
                        );
                        setState(() {});
                      },
                icon: const Icon(Icons.north_east, size: 17),
                label: Text('Yuksek $longLabel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _matchHud() {
    final totalControl = (_engine.blueControlSeconds + _engine.redControlSeconds)
        .clamp(1.0, double.infinity);
    final bluePossession =
        (_engine.blueControlSeconds / totalControl * 100).round();
    final redPossession = 100 - bluePossession;
    final blueCards = _engine.disciplinaryEvents
        .where((event) => event.teamId == TeamId.blue && !event.canceled)
        .length;
    final redCards = _engine.disciplinaryEvents
        .where((event) => event.teamId == TeamId.red && !event.canceled)
        .length;
    return Positioned(
      left: 18,
      right: 18,
      bottom: 12,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xff07120e).withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 14,
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_engine.blueTeam.name}  •  Top %$bluePossession  •  Pas ${_engine.blueSuccessfulPasses}/${_engine.bluePasses}  •  Sut ${_engine.blueShots}  •  Kart $blueCards',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xffffdf6b),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Icons.sports_soccer, size: 18, color: Colors.white54),
              ),
              Expanded(
                child: Text(
                  '${_engine.redTeam.name}  •  Top %$redPossession  •  Pas ${_engine.redSuccessfulPasses}/${_engine.redPasses}  •  Sut ${_engine.redShots}  •  Kart $redCards',
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff73b9ff),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _restartControlHint() {
    final teamId = _engine.restartTeamId!;
    final kind = switch (_engine.restartKind!) {
      RestartKind.corner => 'KORNER SENDE',
      RestartKind.freeKick => 'SERBEST VURUS SENDE',
      RestartKind.throwIn => 'TAC SENDE',
      RestartKind.goalKick => 'KALE VURUSU SENDE',
      RestartKind.kickoff => 'SANTRA SENDE',
    };
    final controls = teamId == TeamId.blue
        ? 'Numpad 1 / Space: sut  •  Numpad 2 / Z: pas  •  Numpad 3 / X: yuksek pas'
        : '1 / O: sut  •  2 / P: pas  •  3 / L: yuksek pas';
    return Positioned(
      left: 22,
      top: 18,
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xff0d1a16).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xffffd34d)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              kind,
              style: const TextStyle(
                color: Color(0xffffd34d),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _engine.restartKind == RestartKind.corner
                  ? 'Oyuncular yerlesince vurusunu sen kullanacaksin.'
                  : 'Rakip izin verilen mesafenin disinda tutulur.',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(controls, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _freeKickWallPanel() {
    final candidates = _engine.wallCandidates.take(6).toList();
    return Center(
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xff101820).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xffffd34d)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ركلة حرة قريبة — هل تريد حائطاً بشرياً؟',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'اختر حتى خمسة لاعبين. يظهر طول كل لاعب لمساعدتك في الاختيار.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final player in candidates)
                  FilterChip(
                    label: Text(
                      player.profile.name +
                          ' — ' +
                          player.profile.heightMeters.toStringAsFixed(2) +
                          ' m',
                    ),
                    selected: _wallPlayerIds.contains(player.id),
                    onSelected: (selected) {
                      setState(() {
                        if (selected && _wallPlayerIds.length < 5) {
                          _wallPlayerIds.add(player.id);
                        } else {
                          _wallPlayerIds.remove(player.id);
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () {
                    _wallPlayerIds.clear();
                    _engine.declineFreeKickWall();
                    setState(() {});
                  },
                  child: const Text('لا، بدون حائط'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () {
                    _engine.chooseFreeKickWall(_wallPlayerIds);
                    _wallPlayerIds.clear();
                    setState(() {});
                  },
                  child: Text(
                    'تأكيد الحائط (' + _wallPlayerIds.length.toString() + ')',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _varDecisionLabel(String decision) => switch (decision) {
    'playOn' => 'Devam / karar yok',
    'foul' => 'Faul, kart yok',
    'yellow' => 'Sari kart',
    'red' => 'Kirmizi kart',
    'handball' => 'El, kart yok',
    'onside' => 'Ofsayt yok',
    'offside' => 'Ofsayt',
    'confirm' => 'Karari onayla',
    'cancel' => 'Karari iptal et',
    _ => decision,
  };

  Widget _banner() {
    final banner = _engine.banner!;
    final accent = switch (banner.kind) {
      'goal' => const Color(0xff2ee59d),
      'foul' => const Color(0xffff9f43),
      'yellowCard' => const Color(0xffffd34d),
      'redCard' => const Color(0xffff4d5a),
      'injury' => const Color(0xffff6b81),
      'var' => const Color(0xffb388ff),
      _ => const Color(0xff64b5f6),
    };
    final icon = switch (banner.kind) {
      'goal' => Icons.sports_soccer,
      'foul' => Icons.sports,
      'yellowCard' || 'redCard' => Icons.style,
      'injury' => Icons.medical_services_outlined,
      'var' => Icons.videocam_outlined,
      _ => Icons.campaign_outlined,
    };
    return Positioned(
      top: 18,
      right: 22,
      child: Container(
        width: _engine.varReviewActive ? 520 : 390,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xff111b22).withValues(alpha: 0.96),
              accent.withValues(alpha: 0.20),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.70)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          banner.title,
                          style: TextStyle(
                            color: accent,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        "${banner.minute ?? _engine.minute.ceil()}'",
                        style: const TextStyle(
                          color: Colors.white54,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    banner.subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                  if (_engine.varReviewActive) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final decision in _engine.varDecisionOptions)
                          FilledButton.tonal(
                            onPressed: () {
                              _engine.resolveVarDecision(decision);
                              setState(() {});
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  decision == _engine.varRecommendedDecision
                                  ? accent.withValues(alpha: 0.30)
                                  : Colors.white.withValues(alpha: 0.08),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                            ),
                            child: Text(
                              _varDecisionLabel(decision),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'R veya Enter: onerilen VAR kararini uygula',
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _penaltyKeyboardHint() {
    final penalty = _engine.activePenalty!;
    final shooterKeys = penalty.shootingTeam == TeamId.blue
        ? 'Oklar yon, Space basili tut'
        : 'A/S/D yon, O basili tut';
    final keeperKeys = penalty.shootingTeam == TeamId.blue
        ? 'A/S/D kaleci atlayisi'
        : 'Oklar kaleci atlayisi';
    return Positioned(
      left: 28,
      bottom: 28,
      child: Container(
        width: 430,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xff101820).withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PENALTI KONTROL',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            const Text(
              'Secilen yonler gizli tutulur; sadece sahadaki vurus ve kaleci hareketi gorunur.',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(shooterKeys, style: const TextStyle(color: Colors.white70)),
            Text(keeperKeys, style: const TextStyle(color: Colors.white70)),
            const Text(
              'Tab vurucuyu degistirir',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 4),
            const Divider(height: 1, color: Colors.white12),
            const SizedBox(height: 4),
            if (!_engine.blueAiControlled)
              Text(
                'Mavi: Numpad 0=Pres  . =Defans',
                style: TextStyle(
                  color: _bluePressing
                      ? Colors.orangeAccent
                      : _blueDefending
                      ? Colors.blueAccent
                      : Colors.white54,
                  fontSize: 11,
                ),
              ),
            if (!_engine.redAiControlled)
              Text(
                'Kirmizi: 0=Pres  \`=Defans',
                style: TextStyle(
                  color: _redPressing
                      ? Colors.orangeAccent
                      : _redDefending
                      ? Colors.blueAccent
                      : Colors.white54,
                  fontSize: 11,
                ),
              ),
            if (_engine.hasInjuryForcedSub)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'SAKATLIK! F1/F2 zorunlu degisiklik',
                  style: TextStyle(
                    color: Colors.redAccent.shade200,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            if (_engine.blueAiControlled || _engine.redAiControlled)
              Column(
                children: [
                  Text(
                    'AI: ${_engine.blueAiControlled ? "${_engine.blueTeam.name} (${_engine.bluePlayStyle.title})" : ""}${_engine.blueAiControlled && _engine.redAiControlled ? " vs " : ""}${_engine.redAiControlled ? "${_engine.redTeam.name} (${_engine.redPlayStyle.title})" : ""}',
                    style: const TextStyle(
                      color: Color(0xffffd34d),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'Zorluk: ${_engine.aiDifficulty.title}',
                    style: const TextStyle(
                      color: Color(0xffffd34d),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _substitutionPanel() {
    final team = _engine.teamById(_subTeam!);
    final plan = formationPlan(team.formation);
    final canSubstitute =
        team.bench.isNotEmpty &&
        team.substitutionsUsed < team.substitutionLimit;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: Container(
            width: 1080,
            height: 680,
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xff09150f),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _injurySubActive
                    ? Colors.redAccent
                    : const Color(0xffffd34d),
                width: 1.5,
              ),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 30),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xff123f2e), Color(0xff101820)],
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _injurySubActive
                            ? Icons.medical_services
                            : Icons.account_tree,
                        color: _injurySubActive
                            ? Colors.redAccent
                            : const Color(0xffffd34d),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${team.name} • Dizilis ve Degisiklik',
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              _injurySubActive
                                  ? '${_injuryVictim?.profile.name ?? "Oyuncu"} sakatlandi: yedegi bu oyuncunun dairesine surukle.'
                                  : 'Sahadaki oyunculari birbirine surukleyerek yerlerini sinirsiz degistir.',
                              style: TextStyle(
                                color: _injurySubActive
                                    ? Colors.redAccent
                                    : Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: DropdownButtonFormField<FormationType>(
                          value: playableFormationTypes.contains(team.formation)
                              ? team.formation
                              : FormationType.wing433,
                          isDense: true,
                          decoration: const InputDecoration(
                            labelText: 'Dizilis',
                          ),
                          items: [
                            for (final formation in playableFormationTypes)
                              DropdownMenuItem(
                                value: formation,
                                child: Text(
                                  formation.title,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (formation) {
                            if (formation == null) return;
                            setState(() {
                              _engine.setFormation(team.id, formation);
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Chip(
                        avatar: const Icon(Icons.swap_horiz, size: 17),
                        label: Text(
                          '${team.substitutionsUsed}/${team.substitutionLimit}',
                        ),
                      ),
                      if (team.bonusSubstitutions > 0) ...[
                        const SizedBox(width: 6),
                        Chip(
                          avatar: const Icon(
                            Icons.add_circle,
                            size: 17,
                            color: Colors.greenAccent,
                          ),
                          label: Text('+${team.bonusSubstitutions} sakatlik hakki'),
                        ),
                      ],
                      IconButton(
                        tooltip: _injurySubActive
                            ? 'Zorunlu degisiklik tamamlanmali'
                            : 'Kapat',
                        onPressed:
                            _injurySubActive ? null : _closeSubstitutionPanel,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 7,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xff087a36),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white70,
                                    width: 2,
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    Positioned(
                                      left: constraints.maxWidth / 2 - 1,
                                      top: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 2,
                                        color: Colors.white30,
                                      ),
                                    ),
                                    Positioned(
                                      left: constraints.maxWidth / 2 - 52,
                                      top: constraints.maxHeight / 2 - 52,
                                      child: Container(
                                        width: 104,
                                        height: 104,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white30,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                    for (var slot = 0;
                                        slot < plan.spots.length &&
                                            slot < team.players.length;
                                        slot++)
                                      _matchFormationSlot(
                                        team: team,
                                        plan: plan,
                                        slotIndex: slot,
                                        width: constraints.maxWidth,
                                        height: constraints.maxHeight,
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(0, 14, 14, 14),
                          decoration: BoxDecoration(
                            color: const Color(0xff101820),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'YEDEKLER',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xffffd34d),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      canSubstitute
                                          ? 'Yedegi tutup cikacak oyuncunun dairesine birak.'
                                          : team.bench.isEmpty
                                          ? 'Kullanilabilir yedek oyuncu yok.'
                                          : 'Degisiklik hakki doldu. Pozisyon takasi yapabilirsin.',
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: team.bench.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'Yedek yok',
                                          style: TextStyle(
                                            color: Colors.white54,
                                          ),
                                        ),
                                      )
                                    : ListView.builder(
                                        padding: const EdgeInsets.all(8),
                                        itemCount: team.bench.length,
                                        itemBuilder: (context, index) {
                                          final player = team.bench[index];
                                          return _matchBenchPlayerCard(
                                            player,
                                            enabled: canSubstitute &&
                                                !player.profile.isUnavailable,
                                          );
                                        },
                                      ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _injurySubActive
                                        ? null
                                        : _closeSubstitutionPanel,
                                    icon: const Icon(Icons.check),
                                    label: const Text('Tamam'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _matchFormationSlot({
    required TeamGame team,
    required FormationPlan plan,
    required int slotIndex,
    required double width,
    required double height,
  }) {
    final spot = plan.spots[slotIndex];
    final player = team.players[slotIndex];
    final injuryTarget = _injuryVictim == player;
    final left = (16 + spot.x * (width - 96)).clamp(0.0, width - 80).toDouble();
    final top = (16 + spot.y * (height - 82)).clamp(0.0, height - 62).toDouble();
    return Positioned(
      left: left,
      top: top,
      width: 80,
      height: 62,
      child: DragTarget<PlayerGame>(
        onWillAcceptWithDetails: (details) =>
            _canDropMatchPlayer(team, details.data, slotIndex),
        onAcceptWithDetails: (details) {
          _acceptMatchPlayerDrop(team, details.data, slotIndex);
        },
        builder: (context, candidates, rejected) {
          final highlighted = candidates.isNotEmpty;
          final circle = AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: injuryTarget
                  ? Colors.redAccent.withValues(alpha: 0.86)
                  : highlighted
                  ? const Color(0xffffd34d)
                  : player.isSentOff
                  ? Colors.black54
                  : const Color(0xff101820).withValues(alpha: 0.94),
              border: Border.all(
                color: highlighted || injuryTarget
                    ? Colors.white
                    : Colors.white70,
                width: highlighted || injuryTarget ? 3 : 1.5,
              ),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  player.isSentOff ? 'KIRMIZI' : '${player.number}',
                  style: TextStyle(
                    color: highlighted ? Colors.black : const Color(0xffffd34d),
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    player.profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: highlighted ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                    ),
                  ),
                ),
                Text(
                  '${spot.role.code} • ${(player.stamina * 100).round()}%',
                  style: TextStyle(
                    color: highlighted ? Colors.black87 : Colors.white54,
                    fontSize: 8,
                  ),
                ),
              ],
            ),
          );
          if (_injurySubActive || player.isSentOff) return circle;
          return Draggable<PlayerGame>(
            data: player,
            feedback: Material(
              color: Colors.transparent,
              child: _matchDragFeedback(player),
            ),
            childWhenDragging: Opacity(opacity: 0.25, child: circle),
            child: circle,
          );
        },
      ),
    );
  }

  Widget _matchBenchPlayerCard(PlayerGame player, {required bool enabled}) {
    final card = Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: enabled
            ? Colors.white.withValues(alpha: 0.045)
            : Colors.redAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: enabled ? Colors.white12 : Colors.redAccent),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0x22ffd34d),
            child: Text(
              '${player.number}',
              style: const TextStyle(
                color: Color(0xffffd34d),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.profile.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${player.role.code} • OVR ${player.profile.effectiveOverall.round()} • Enerji ${(player.stamina * 100).round()}%',
                  style: const TextStyle(color: Colors.white54, fontSize: 9),
                ),
              ],
            ),
          ),
          Icon(
            enabled ? Icons.drag_indicator : Icons.block,
            color: enabled ? Colors.white54 : Colors.redAccent,
          ),
        ],
      ),
    );
    if (!enabled) return card;
    return Draggable<PlayerGame>(
      data: player,
      feedback: Material(
        color: Colors.transparent,
        child: _matchDragFeedback(player),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: card),
      child: card,
    );
  }

  Widget _matchDragFeedback(PlayerGame player) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xff101820),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xffffd34d)),
      ),
      child: Text(
        '${player.profile.name} • OVR ${player.profile.effectiveOverall.round()}',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  bool _canDropMatchPlayer(
    TeamGame team,
    PlayerGame dragged,
    int targetSlot,
  ) {
    if (targetSlot < 0 || targetSlot >= team.players.length) return false;
    final target = team.players[targetSlot];
    if (target.isSentOff) return false;
    final activeIndex = team.players.indexOf(dragged);
    if (activeIndex >= 0) {
      return !_injurySubActive &&
          !dragged.isSentOff &&
          dragged.isGoalkeeper == target.isGoalkeeper;
    }
    final benchIndex = team.bench.indexOf(dragged);
    if (benchIndex < 0 || dragged.profile.isUnavailable) return false;
    if (team.substitutionsUsed >= team.substitutionLimit) return false;
    if (dragged.profile.isGoalkeeper != target.isGoalkeeper) return false;
    if (_injurySubActive && target != _injuryVictim) return false;
    return true;
  }

  void _acceptMatchPlayerDrop(
    TeamGame team,
    PlayerGame dragged,
    int targetSlot,
  ) {
    final activeIndex = team.players.indexOf(dragged);
    if (activeIndex >= 0) {
      setState(() {
        _engine.swapPlayerPositions(team.id, activeIndex, targetSlot);
      });
      return;
    }
    final benchIndex = team.bench.indexOf(dragged);
    if (benchIndex < 0) return;
    final changed = _engine.substitute(team.id, targetSlot, benchIndex);
    if (!changed) return;
    if (_injurySubActive) {
      _engine.popInjuryForcedSub();
    }
    setState(() {
      _injurySubActive = false;
      _injuryVictim = null;
      _subOutIndex = targetSlot;
      _subBenchIndex = 0;
    });
  }

  Widget _replayPanel() {
    final frame = _engine.currentReplayFrame;
    final events = _engine.timelineEvents;
    final selectedMatches = events.where(
      (event) => event.id == _selectedTimelineEventId,
    );
    final MatchTimelineEvent? selectedEvent =
        selectedMatches.isEmpty ? null : selectedMatches.first;
    final varPlayers = _engine.allMatchPlayers;
    final selectedTargets = varPlayers.where(
      (player) => player.id == _varTargetPlayerId,
    );
    final targetPlayer = selectedTargets.isNotEmpty
        ? selectedTargets.first
        : _engine.replayFocusPlayer();
    if (_varPanelMinimized) {
      return Positioned(
        right: 18,
        bottom: 16,
        child: FilledButton.icon(
          onPressed: () => setState(() => _varPanelMinimized = false),
          icon: const Icon(Icons.open_in_full),
          label: Text(
            frame == null
                ? 'VAR merkezini ac'
                : 'VAR ${frame.minute.toStringAsFixed(1)} • x${_varBallZoom.toStringAsFixed(1)}',
          ),
        ),
      );
    }
    return Positioned(
      left: 16,
      right: 16,
      bottom: 12,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 510),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xff101820).withValues(alpha: 0.98),
              const Color(0xff24143d).withValues(alpha: 0.96),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xffb388ff).withValues(alpha: 0.70),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.video_settings,
                    color: Color(0xffb388ff),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      frame == null
                          ? 'VAR KONTROL MERKEZI'
                          : 'VAR ${frame.minute.toStringAsFixed(1)} • ${frame.description}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '${_engine.replayIndex + 1}/${_engine.replayFrames.length}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'Uzaklastir',
                    onPressed: _varBallZoom <= 1.0
                        ? null
                        : () {
                            setState(() {
                              _varBallZoom = (_varBallZoom - 0.5)
                                  .clamp(1.0, 3.0)
                                  .toDouble();
                            });
                          },
                    icon: const Icon(Icons.zoom_out),
                  ),
                  Text(
                    'Top x${_varBallZoom.toStringAsFixed(1)}',
                    style: const TextStyle(
                      color: Color(0xff8bd3ff),
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Topun etrafina yakinlas',
                    onPressed: _varBallZoom >= 3.0
                        ? null
                        : () {
                            setState(() {
                              _varBallZoom = (_varBallZoom + 0.5)
                                  .clamp(1.0, 3.0)
                                  .toDouble();
                            });
                          },
                    icon: const Icon(Icons.zoom_in),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Paneli kucult',
                    onPressed: () => setState(() => _varPanelMinimized = true),
                    icon: const Icon(Icons.minimize),
                  ),
                  const SizedBox(width: 5),
                  IconButton.filledTonal(
                    tooltip: 'VAR ekranini kapat',
                    onPressed: () {
                      _engine.closeReplay();
                      setState(() {
                        _selectedTimelineEventId = null;
                        _varPanelMinimized = false;
                        _varBallZoom = 1.0;
                        _varTargetPlayerId = null;
                      });
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Basa don',
                    onPressed: () {
                      _engine.setReplayProgress(0);
                      setState(() {});
                    },
                    icon: const Icon(Icons.first_page),
                  ),
                  IconButton(
                    tooltip: '10 saniye geri',
                    onPressed: () {
                      _engine.seekReplaySeconds(-10);
                      setState(() {});
                    },
                    icon: const Icon(Icons.replay_10),
                  ),
                  IconButton(
                    tooltip: '3 saniye geri',
                    onPressed: () {
                      _engine.seekReplaySeconds(-3);
                      setState(() {});
                    },
                    icon: const Icon(Icons.fast_rewind),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      _engine.toggleReplayPlayback();
                      setState(() {});
                    },
                    icon: Icon(
                      _engine.replayPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    label: Text(
                      _engine.replayPlaying ? 'Duraklat' : 'Oynat',
                    ),
                  ),
                  IconButton(
                    tooltip: '3 saniye ileri',
                    onPressed: () {
                      _engine.seekReplaySeconds(3);
                      setState(() {});
                    },
                    icon: const Icon(Icons.fast_forward),
                  ),
                  IconButton(
                    tooltip: '10 saniye ileri',
                    onPressed: () {
                      _engine.seekReplaySeconds(10);
                      setState(() {});
                    },
                    icon: const Icon(Icons.forward_10),
                  ),
                  IconButton(
                    tooltip: 'Sona git',
                    onPressed: () {
                      _engine.setReplayProgress(1);
                      setState(() {});
                    },
                    icon: const Icon(Icons.last_page),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    Text(
                      "${frame?.minute.ceil() ?? 0}' dakikasina ekle:",
                      style: const TextStyle(
                        color: Color(0xffffd34d),
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<String>(
                        value: targetPlayer.id,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: 'Oyuncu / takim',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 7,
                          ),
                        ),
                        items: [
                          for (final player in varPlayers)
                            DropdownMenuItem(
                              value: player.id,
                              child: Text(
                                '${player.profile.name} • ${_engine.teamById(player.teamId).name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _varTargetPlayerId = value);
                          }
                        },
                      ),
                    ),
                    _varAddButton('foul', 'Faul', Icons.sports, targetPlayer),
                    _varAddButton(
                      'handball',
                      'El',
                      Icons.back_hand_outlined,
                      targetPlayer,
                    ),
                    _varAddButton(
                      'offside',
                      'Ofsayt',
                      Icons.flag_outlined,
                      targetPlayer,
                    ),
                    _varAddButton(
                      'yellowCard',
                      'Sari',
                      Icons.style,
                      targetPlayer,
                      color: const Color(0xffffd34d),
                    ),
                    _varAddButton(
                      'redCard',
                      'Kirmizi',
                      Icons.style,
                      targetPlayer,
                      color: Colors.redAccent,
                    ),
                    _varAddButton(
                      'penalty',
                      'Penalti',
                      Icons.gps_fixed,
                      targetPlayer,
                      color: const Color(0xffd980fa),
                    ),
                    _varAddButton(
                      'goal',
                      'Gol',
                      Icons.sports_soccer,
                      targetPlayer,
                      color: const Color(0xff2ee59d),
                    ),
                    _varAddButton(
                      'injury',
                      'Sakatlik',
                      Icons.medical_services_outlined,
                      targetPlayer,
                      color: const Color(0xffff6b81),
                    ),
                  ],
                ),
              ),
              _replayTimeline(events),
              Row(
                children: [
                  const Text(
                    'OLAYLAR',
                    style: TextStyle(
                      color: Color(0xffb388ff),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    '${events.length} kayit • karta tiklayarak ana git',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              SizedBox(
                height: 76,
                child: events.isEmpty
                    ? const Center(
                        child: Text(
                          'Henuz gol, faul, kart, ofsayt veya penalti kaydi yok.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: events.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 7),
                        itemBuilder: (context, index) {
                          final event = events[index];
                          final selected = event.id == _selectedTimelineEventId;
                          final color = _timelineEventColor(event.kind);
                          return InkWell(
                            borderRadius: BorderRadius.circular(9),
                            onTap: () {
                              _engine.seekReplayToEvent(event);
                              setState(() => _selectedTimelineEventId = event.id);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              width: 158,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? color.withValues(alpha: 0.22)
                                    : Colors.white.withValues(alpha: 0.055),
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: selected
                                      ? color
                                      : color.withValues(alpha: 0.35),
                                  width: selected ? 1.6 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _timelineEventIcon(event.kind),
                                    color: color,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          "${event.minute}' • ${event.title}",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                            decoration: event.canceled
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          event.canceled
                                              ? '${event.detail} • IPTAL'
                                              : event.detail,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (selectedEvent != null) ...[
                const SizedBox(height: 9),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _timelineEventColor(
                      selectedEvent.kind,
                    ).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _timelineEventIcon(selectedEvent.kind),
                        color: _timelineEventColor(selectedEvent.kind),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          "${selectedEvent.minute}' ${selectedEvent.title} • ${selectedEvent.detail}${selectedEvent.canceled ? ' • KARAR IPTAL' : ''}",
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          _engine.seekReplayToEvent(selectedEvent!);
                          setState(() {});
                        },
                        icon: const Icon(Icons.my_location, size: 17),
                        label: const Text('Ana git'),
                      ),
                      if (_engine.canToggleTimelineDecision(selectedEvent)) ...[
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            _engine.toggleTimelineDecision(selectedEvent!);
                            setState(() {});
                          },
                          icon: Icon(
                            selectedEvent.canceled ? Icons.undo : Icons.gavel,
                            size: 17,
                          ),
                          label: Text(
                            selectedEvent.canceled
                                ? 'Karari geri ver'
                                : 'Karari iptal et',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _varAddButton(
    String kind,
    String label,
    IconData icon,
    PlayerGame target, {
    Color color = Colors.white70,
  }) {
    return OutlinedButton.icon(
      onPressed: () {
        final event = _engine.addVarDecisionAtCurrentReplay(kind, target);
        setState(() {
          if (event != null) {
            _selectedTimelineEventId = event.id;
          }
        });
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.55)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 10)),
    );
  }

  Widget _replayTimeline(List<MatchTimelineEvent> events) {
    return SizedBox(
      height: 48,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final lastFrame = (_engine.replayFrames.length - 1).clamp(1, 999999);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Slider(
                  value: _engine.replayProgress.clamp(0, 1).toDouble(),
                  onChanged: (value) {
                    _engine.setReplayProgress(value);
                    setState(() {});
                  },
                ),
              ),
              for (final event in events)
                Positioned(
                  left: (12 +
                          (constraints.maxWidth - 24) *
                              (event.replayIndex / lastFrame)
                                  .clamp(0.0, 1.0))
                      .toDouble(),
                  top: 1,
                  child: Tooltip(
                    message: "${event.minute}' ${event.title}: ${event.detail}",
                    child: GestureDetector(
                      onTap: () {
                        _engine.seekReplayToEvent(event);
                        setState(() => _selectedTimelineEventId = event.id);
                      },
                      child: Container(
                        width: 9,
                        height: 15,
                        decoration: BoxDecoration(
                          color: event.canceled
                              ? Colors.white38
                              : _timelineEventColor(event.kind),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: Colors.black54),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Color _timelineEventColor(String kind) => switch (kind) {
    'goal' => const Color(0xff2ee59d),
    'foul' => const Color(0xffff9f43),
    'yellowCard' => const Color(0xffffd34d),
    'redCard' => const Color(0xffff4d5a),
    'penalty' || 'shootout' => const Color(0xffd980fa),
    'offside' => const Color(0xff64b5f6),
    'handball' => const Color(0xffff8a80),
    'injury' => const Color(0xffff6b81),
    'var' => const Color(0xffb388ff),
    _ => Colors.white70,
  };

  IconData _timelineEventIcon(String kind) => switch (kind) {
    'goal' => Icons.sports_soccer,
    'foul' => Icons.sports,
    'yellowCard' || 'redCard' => Icons.style,
    'penalty' || 'shootout' => Icons.gps_fixed,
    'offside' => Icons.flag_outlined,
    'handball' => Icons.back_hand_outlined,
    'injury' => Icons.medical_services_outlined,
    'var' => Icons.video_settings,
    _ => Icons.circle,
  };

  Widget _resultPanel() {
    final blueGoals = _engine.blueTeam.goals;
    final redGoals = _engine.redTeam.goals;
    final best = _engine.bestPlayer();
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: 620,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xff101820).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'MAC SONUCU',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              '${_engine.blueTeam.name} ${_engine.blueTeam.score} - ${_engine.redTeam.score} ${_engine.redTeam.name}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Macin oyuncusu: ${best.profile.name}  G:${best.matchGoals} P:${best.matchSuccessfulPasses}/${best.matchPasses} S:${best.matchShotsOnTarget}/${best.matchShots} K:${best.matchSaves}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _goalList(_engine.blueTeam.name, blueGoals)),
                const SizedBox(width: 16),
                Expanded(child: _goalList(_engine.redTeam.name, redGoals)),
              ],
            ),
            if (_engine.shootout != null) ...[
              const Divider(height: 28),
              Text(
                'Penalti: Mavi ${_engine.shootout!.goalsFor(TeamId.blue)} - ${_engine.shootout!.goalsFor(TeamId.red)} Kirmizi',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _showPlayerStatistics,
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('تفاصيل وإحصائيات جميع اللاعبين'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    _engine.openReplay(fromStart: false);
                    setState(() {
                      _varPanelMinimized = false;
                      _varBallZoom = 1.0;
                      _varTargetPlayerId = null;
                    });
                  },
                  icon: const Icon(Icons.video_settings),
                  label: const Text('فتح مركز تحكم VAR'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Esc: Ana menu',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPlayerStatistics() async {
    final searchController = TextEditingController();
    var query = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final players = _engine.allMatchPlayers
              .where(
                (player) => query.isEmpty ||
                    player.profile.name.toLowerCase().contains(query),
              )
              .toList()
            ..sort((a, b) {
              final byTeam = a.teamId.index.compareTo(b.teamId.index);
              return byTeam != 0
                  ? byTeam
                  : b.minutesThisMatch.compareTo(a.minutesThisMatch);
            });
          return AlertDialog(
            backgroundColor: const Color(0xff0d1a16),
            title: const Row(
              children: [
                Icon(Icons.analytics, color: Color(0xffffd34d)),
                SizedBox(width: 10),
                Text('إحصائيات اللاعبين الكاملة'),
              ],
            ),
            content: SizedBox(
              width: 980,
              height: 620,
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'ابحث عن لاعب',
                      isDense: true,
                    ),
                    onChanged: (value) => setDialogState(
                      () => query = value.trim().toLowerCase(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: players.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 7),
                      itemBuilder: (context, index) {
                        final player = players[index];
                        final team = _engine.teamById(player.teamId);
                        final minutes = _engine.playedMinutesFor(player);
                        final rating = _engine.matchRatingFor(player);
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: team.color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: team.color.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: team.color,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '${player.number}',
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '${player.profile.name} • ${team.name}',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '$minutes dk  •  ${rating.toStringAsFixed(1)}',
                                    style: const TextStyle(
                                      color: Color(0xffffd34d),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 14,
                                runSpacing: 6,
                                children: [
                                  Text('Gol ${player.matchGoals}'),
                                  Text('Asist ${player.matchAssists}'),
                                  Text('Pas ${player.matchSuccessfulPasses}/${player.matchPasses}'),
                                  Text('Dripling ${player.matchSuccessfulDribbles}/${player.matchDribbles}'),
                                  Text('Mudahale ${player.matchTackles}'),
                                  Text('Sut ${player.matchShotsOnTarget}/${player.matchShots}'),
                                  Text('Kacan ${player.matchMissedChances}'),
                                  Text('Kurtaris ${player.matchSaves}'),
                                  Text('Uzaklastirma ${player.matchClearances}'),
                                  Text('Faul ${player.matchFoulsCommitted}/${player.matchFoulsReceived}'),
                                  Text('Kart ${player.matchYellowCards}S ${player.matchRedCards}K'),
                                  Text('Enerji ${(player.stamina * 100).round()}%'),
                                  Text(
                                    'Dayaniklilik ${player.profile.dayaniklilikGucu.round()}',
                                  ),
                                  if (player.isInjuredInMatch)
                                    const Text(
                                      'SAKAT',
                                      style: TextStyle(color: Colors.redAccent),
                                    ),
                                  if (player.isSentOff && !player.isInjuredInMatch)
                                    const Text(
                                      'OYUNDAN ATILDI',
                                      style: TextStyle(color: Colors.redAccent),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('إغلاق'),
              ),
            ],
          );
        },
      ),
    );
    searchController.dispose();
  }

  bool _isBlueActionKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.numpad1 ||
        key == LogicalKeyboardKey.numpad2 ||
        key == LogicalKeyboardKey.numpad3 ||
        key == LogicalKeyboardKey.keyV;
  }

  void _drainPressStamina(TeamId id, double dt) {
    _engine.applyPressingStamina(id, dt);
  }

  bool _isRedActionKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.keyW ||
        key == LogicalKeyboardKey.keyA ||
        key == LogicalKeyboardKey.keyS ||
        key == LogicalKeyboardKey.keyD ||
        key == LogicalKeyboardKey.digit1 ||
        key == LogicalKeyboardKey.digit2 ||
        key == LogicalKeyboardKey.digit3 ||
        key == LogicalKeyboardKey.keyK;
  }

  Widget _goalList(String title, List goals) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        if (goals.isEmpty)
          const Text('Gol yok', style: TextStyle(color: Colors.white60)),
        for (final goal in goals)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              "${goal.minute}'  ${goal.scorerName}${goal.isPenalty ? ' (P)' : ''}${goal.canceled ? ' - iptal' : ''}",
              style: TextStyle(
                color: goal.canceled ? Colors.white38 : Colors.white,
                decoration: goal.canceled ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
      ],
    );
  }
}
