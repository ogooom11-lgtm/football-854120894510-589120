import 'dart:async';

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
  String _subBenchSort = 'rating';
  bool _emergencyKeeperMode = false;
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
  bool _goalkeeperDebugVisible = false;
  double _varBallZoom = 1.0;
  String? _varTargetPlayerId;
  String? _switchModeHint;
  Timer? _switchHintTimer;

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
    _switchHintTimer?.cancel();
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
      if (key == LogicalKeyboardKey.f8) {
        setState(() => _goalkeeperDebugVisible = !_goalkeeperDebugVisible);
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
      // C: switch the BLUE controlled player to the next man.
      // Q: switch the RED controlled player to the next man.
      // B: toggle BLUE automatic switching.  E: toggle RED automatic.
      if (key == LogicalKeyboardKey.keyC &&
          !_engine.replayMode &&
          !_engine.finished) {
        if (!_engine.blueAiControlled) {
          _engine.switchControlledPlayer(TeamId.blue);
          _showSwitchHint(
            _engine.isAutoSwitchEnabled(TeamId.blue)
                ? 'Mavi oyuncu degistirildi (C)'
                : 'Manuel: mavi oyuncu degistirildi (C)',
          );
          setState(() {});
          return;
        }
      }
      if (key == LogicalKeyboardKey.keyQ &&
          !_engine.replayMode &&
          !_engine.finished) {
        if (!_engine.redAiControlled) {
          _engine.switchControlledPlayer(TeamId.red);
          _showSwitchHint(
            _engine.isAutoSwitchEnabled(TeamId.red)
                ? 'Kirmizi oyuncu degistirildi (Q)'
                : 'Manuel: kirmizi oyuncu degistirildi (Q)',
          );
          setState(() {});
          return;
        }
      }
      if (key == LogicalKeyboardKey.keyB &&
          !_engine.replayMode &&
          !_engine.finished) {
        if (!_engine.blueAiControlled) {
          final enabled = _engine.toggleAutoSwitch(TeamId.blue);
          _showSwitchHint(
            enabled
                ? 'Mavi oto degisim: ACIK (B)'
                : 'Mavi oto degisim: KAPALI (B)',
          );
          setState(() {});
          return;
        }
      }
      if (key == LogicalKeyboardKey.keyE &&
          !_engine.replayMode &&
          !_engine.finished) {
        if (!_engine.redAiControlled) {
          final enabled = _engine.toggleAutoSwitch(TeamId.red);
          _showSwitchHint(
            enabled
                ? 'Kirmizi oto degisim: ACIK (E)'
                : 'Kirmizi oto degisim: KAPALI (E)',
          );
          setState(() {});
          return;
        }
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

  void _showSwitchHint(String text) {
    _switchHintTimer?.cancel();
    setState(() => _switchModeHint = text);
    _switchHintTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _switchModeHint = null);
      }
    });
  }

  Widget _switchModeHintWidget() {
    final hint = _switchModeHint;
    if (hint == null) {
      return const SizedBox.shrink();
    }
    return Positioned(
      top: 74,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xff0d1a16).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xffd4af37).withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              hint,
              style: const TextStyle(
                color: Color(0xfff5d67b),
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
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
      _engine.substitute(victim.teamId, outIndex, benchIndex, minute: _engine.minute);
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
    _emergencyKeeperMode = false;
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
          _engine.substitute(teamId, _subOutIndex, _subBenchIndex, minute: _engine.minute)) {
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
                    showGoalkeeperDebug: _goalkeeperDebugVisible,
                  ),
                ),
              ),
              if (!_engine.replayMode && !_engine.finished) _matchHud(),
              if (_goalkeeperDebugVisible && !_engine.replayMode)
                _goalkeeperDebugPanel(),
              if (_engine.ball.owner?.isGoalkeeper == true &&
                  !_engine.isTeamAiControlled(_engine.ball.owner!.teamId) &&
                  !_engine.replayMode &&
                  !_engine.finished)
                _keeperDistributionControls(),
              if (_engine.banner != null) _banner(),
              if (_switchModeHint != null) _switchModeHintWidget(),
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

  Widget _goalkeeperDebugPanel() {
    Widget row(PlayerGame keeper, String teamName) {
      final debug = keeper.goalkeeperDebug;
      final impact = debug.predictedImpact;
      return Text(
        '$teamName • ${debug.state.name}/${debug.action.name} • '
        'Impact ${impact == null ? "-" : impact.y.toStringAsFixed(1)} • '
        'TTI ${debug.timeToImpact.isFinite ? debug.timeToImpact.toStringAsFixed(2) : "-"}s • '
        'React ${debug.reactionTime.toStringAsFixed(2)}s • '
        'Conf ${(debug.predictionConfidence * 100).round()}% • '
        'Reach ${debug.reachRadius.toStringAsFixed(1)} • '
        'Ball ${debug.ballSpeed.toStringAsFixed(2)} / ${debug.ballHeight.toStringAsFixed(2)}m • '
        'Curve ${debug.ballCurve.toStringAsFixed(2)}',
        style: const TextStyle(
          color: Color(0xffb3e5fc),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    return Positioned(
      left: 14,
      top: 76,
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: const Color(0xff07120e).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xff40c4ff)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GOALKEEPER DEBUG • F8',
              style: TextStyle(
                color: Color(0xffffd34d),
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            row(_engine.blueTeam.goalkeeper, _engine.blueTeam.name),
            const SizedBox(height: 3),
            row(_engine.redTeam.goalkeeper, _engine.redTeam.name),
          ],
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

  /// Team energy bar: when the squad is tired it is instantly visible in
  /// the HUD (مطلب: الفريق يلي لاعبينه تعبانة يظهر ذلك).
  Widget _teamEnergyBar(TeamGame team) {
    final outfield = team.players
        .where((player) => !player.isGoalkeeper && !player.isSentOff)
        .toList();
    final avg = outfield.isEmpty
        ? 1.0
        : outfield.map((player) => player.stamina).reduce((a, b) => a + b) /
            outfield.length;
    final color = avg > 0.66
        ? const Color(0xff2ee59d)
        : avg > 0.45
            ? const Color(0xffffd34d)
            : const Color(0xffff5c5c);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 64 * avg.clamp(0.0, 1.0),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'طاقة ${(avg * 100).round()}%',
            style: TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
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
              _teamEnergyBar(_engine.blueTeam),
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
              _teamEnergyBar(_engine.redTeam),
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
                  ? 'Korneri kullanmak icin HAZIR dugmesine bas.'
                  : 'Rakip izin verilen mesafenin disinda tutulur.',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            if (_engine.restartKind == RestartKind.corner &&
                _engine.isCornerWaitingForManualInputFor(
                  _engine.teamById(teamId),
                )) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _engine.markCornerReady(teamId),
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: const Text('HAZIR — korneri kullan'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff00a86b),
                  ),
                ),
              ),
            ],
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
                      '${player.profile.name} — '
                      '${player.profile.heightMeters.toStringAsFixed(2)} m',
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
                  child: Text('تأكيد الحائط (${_wallPlayerIds.length})'),
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
                'Kirmizi: 0=Pres  `=Defans',
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
                      _subSortDropdown(),
                      const SizedBox(width: 6),
                      // Emergency: field player in the keeper slot
                      // (مطلب: تعيين لاعب أرضي حارساً).
                      FilterChip(
                        label: const Text(
                          'حارس طوارئ',
                          style: TextStyle(fontSize: 10),
                        ),
                        selected: _emergencyKeeperMode,
                        onSelected: (value) =>
                            setState(() => _emergencyKeeperMode = value),
                        visualDensity: VisualDensity.compact,
                      ),
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
                                          final (benchIndex, player) =
                                              _sortedBenchPairs(team)[index];
                                          return _matchBenchPlayerCard(
                                            player,
                                            enabled: canSubstitute &&
                                                !player.profile.isUnavailable,
                                          );
                                        },
                                      ),
                              ),
                              _reentrySection(team),
                              if (team.substitutionLog.isNotEmpty) ...[
                                const Divider(height: 1),
                                Container(
                                  constraints: const BoxConstraints(
                                    maxHeight: 118,
                                  ),
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    8,
                                    12,
                                    8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(
                                      alpha: 0.03,
                                    ),
                                    border: Border(
                                      top: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.07,
                                        ),
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Expanded(
                                            child: Text(
                                              'Cikanlar',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ),
                                          if (!_injurySubActive &&
                                              team.substitutionLog
                                                  .isNotEmpty)
                                            TextButton.icon(
                                              onPressed: () {
                                                setState(() {
                                                  _engine
                                                      .undoLastSubstitutionFor(
                                                        team.id,
                                                      );
                                                });
                                              },
                                              icon: const Icon(
                                                Icons.undo,
                                                size: 15,
                                              ),
                                              label: const Text(
                                                'Geri al',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                              style: TextButton.styleFrom(
                                                visualDensity: VisualDensity
                                                    .compact,
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                  horizontal: 8,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      Expanded(
                                        child: ListView.builder(
                                          itemCount:
                                              team.substitutionLog.length,
                                          itemBuilder: (context, index) {
                                            final record =
                                                team.substitutionLog[index];
                                            return Text(
                                              '${record.outgoing.profile.name} → ${record.incoming.profile.name}'
                                              ' (${record.minute.ceil()}\x27)',
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.white60,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
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

  /// Bench sorted by the chosen key (مطلب: قائمة البدلاء مرتبة).
  List<(int, PlayerGame)> _sortedBenchPairs(TeamGame team) {
    final pairs = [for (var i = 0; i < team.bench.length; i++) (i, team.bench[i])];
    int compare((int, PlayerGame) a, (int, PlayerGame) b) {
      switch (_subBenchSort) {
        case 'stamina':
          return b.$2.stamina.compareTo(a.$2.stamina);
        case 'position':
          final byRole = a.$2.role.code.compareTo(b.$2.role.code);
          if (byRole != 0) return byRole;
          return b.$2.profile.effectiveOverall
              .compareTo(a.$2.profile.effectiveOverall);
        default:
          return b.$2.profile.effectiveOverall
              .compareTo(a.$2.profile.effectiveOverall);
      }
    }

    return pairs..sort(compare);
  }

  Widget _subSortDropdown() {
    return DropdownButton<String>(
      value: _subBenchSort,
      isDense: true,
      underline: const SizedBox.shrink(),
      style: const TextStyle(fontSize: 11, color: Colors.white70),
      dropdownColor: const Color(0xff102019),
      items: const [
        DropdownMenuItem(value: 'rating', child: Text('ترتيب: الأعلى تقييماً')),
        DropdownMenuItem(value: 'stamina', child: Text('ترتيب: الأعلى طاقة')),
        DropdownMenuItem(value: 'position', child: Text('ترتيب: المركز')),
      ],
      onChanged: (value) {
        if (value != null) setState(() => _subBenchSort = value);
      },
    );
  }

  /// Re-entry + sent-off-return section (مطلب: إعادة إدخال أي لاعب سبق
  /// الخروج، حتى المصاب أو المطرود إذا لم يوجد بدلاء).
  Widget _reentrySection(TeamGame team) {
    final canUseLog = team.substitutionsUsed < team.substitutionLimit;
    final benchEmpty = team.bench.isEmpty;
    final sentOff = <int, PlayerGame>{
      for (var i = 0; i < team.players.length; i++)
        if (team.players[i].isSentOff) i: team.players[i],
    };
    final candidates = team.substitutedOut;
    if (candidates.isEmpty && sentOff.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 150),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xff2a1a08).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xffffd34d).withValues(alpha: 0.35),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'إعادة إدخال من خرجوا سابقاً',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Color(0xffffd34d),
              ),
            ),
            const SizedBox(height: 4),
            for (var logIndex = 0; logIndex < candidates.length; logIndex++)
              _reentryCard(
                team,
                candidates[logIndex],
                subtitle:
                    'خرج د${candidates[logIndex].leftMatchMinute?.ceil() ?? '-'}'
                    '${candidates[logIndex].profile.isUnavailable && !benchEmpty ? ' • متاح فقط بدون بدلاء' : ''}',
                enabled: canUseLog &&
                    (benchEmpty ||
                        !candidates[logIndex].profile.isUnavailable),
                onReturn: () {
                  // Drop target selection: swap with the currently selected
                  // on-pitch index.
                  _performReentry(team, logIndex, _subOutIndex);
                },
              ),
            for (final entry in sentOff.entries)
              _reentryCard(
                team,
                entry.value,
                subtitle: 'مطرود • عودة طارئة لمركزه',
                enabled: true,
                onReturn: () {
                  setState(() {
                    _engine.reinstateSentOff(
                      team.id,
                      entry.key,
                      minute: _engine.minute,
                    );
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  void _performReentry(TeamGame team, int logIndex, int outIndex) {
    final changed = _engine.reenterFromLog(
      team.id,
      outIndex,
      logIndex,
      minute: _engine.minute,
    );
    if (!changed && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر الإعادة: تأكد من تطابق مركز الحارس وعدم نفاد التبديلات',
          ),
        ),
      );
    }
    setState(() {});
  }

  Widget _reentryCard(
    TeamGame team,
    PlayerGame player, {
    required String subtitle,
    required bool enabled,
    required VoidCallback onReturn,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${player.number}. ${player.profile.name} — $subtitle',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: enabled ? Colors.white70 : Colors.white24,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 22,
            child: FilledButton.tonal(
              onPressed: enabled ? onReturn : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(fontSize: 10),
              ),
              child: const Text('إعادة'),
            ),
          ),
        ],
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
    if (benchIndex < 0) {
      // Re-entry candidate dragged from the previously-subbed list.
      final logIndex = team.substitutedOut.indexOf(dragged);
      if (logIndex < 0) return false;
      if (team.substitutionsUsed >= team.substitutionLimit) return false;
      if (!_emergencyKeeperMode &&
          dragged.isGoalkeeper != target.isGoalkeeper) {
        return false;
      }
      if (_injurySubActive && target != _injuryVictim) return false;
      return team.bench.isEmpty || !dragged.profile.isUnavailable;
    }
    if (dragged.profile.isUnavailable) return false;
    if (team.substitutionsUsed >= team.substitutionLimit) return false;
    if (!_emergencyKeeperMode &&
        dragged.profile.isGoalkeeper != target.isGoalkeeper) {
      return false;
    }
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
      // If the two players are standing almost on top of each other, the
      // swap would just flip them back and forth without any real change —
      // reject it so the game doesn't keep swapping between close players.
      final target = team.players[targetSlot];
      if (dragged != target &&
          dragged.pos.distanceTo(target.pos) < 20) {
        return;
      }
      setState(() {
        _engine.swapPlayerPositions(team.id, activeIndex, targetSlot);
      });
      return;
    }
    final logIndex = team.substitutedOut.indexOf(dragged);
    if (team.bench.indexOf(dragged) < 0 && logIndex >= 0) {
      final changed = _engine.reenterFromLog(
        team.id,
        targetSlot,
        logIndex,
        minute: _engine.minute,
      );
      if (changed && _injurySubActive) {
        _engine.popInjuryForcedSub();
      }
      if (changed) {
        setState(() {
          _injurySubActive = false;
          _injuryVictim = null;
        });
      }
      return;
    }
    final benchIndex = team.bench.indexOf(dragged);
    if (benchIndex < 0) return;
    final changed = _engine.substitute(
      team.id,
      targetSlot,
      benchIndex,
      minute: _engine.minute,
      allowKeeperSwap: _emergencyKeeperMode,
    );
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
                  const SizedBox(width: 6),
                  // Replay speed: slow motion to fast forward
                  // (مطلب تبطيئ العرض وتسريعه).
                  for (final speed in const [0.25, 0.5, 1.0, 2.0])
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: ChoiceChip(
                        label: Text('${speed}x'),
                        selected: _engine.replaySpeed == speed,
                        onSelected: (_) => setState(
                          () => _engine.replaySpeed = speed,
                        ),
                        labelStyle: const TextStyle(fontSize: 11),
                        visualDensity: VisualDensity.compact,
                      ),
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
                          _engine.seekReplayToEvent(selectedEvent);
                          setState(() {});
                        },
                        icon: const Icon(Icons.my_location, size: 17),
                        label: const Text('Ana git'),
                      ),
                      if (_engine.canToggleTimelineDecision(selectedEvent)) ...[
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            _engine.toggleTimelineDecision(selectedEvent);
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

  double _possessionFor(TeamId id) {
    final total = _engine.blueControlSeconds + _engine.redControlSeconds;
    if (total <= 0) {
      return 50;
    }
    final share = id == TeamId.blue
        ? _engine.blueControlSeconds / total
        : _engine.redControlSeconds / total;
    return share * 100;
  }

  Widget _resultPanel() {
    final best = _engine.bestPlayer();
    final events = [..._engine.timelineEvents];
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: 680,
        constraints: const BoxConstraints(maxHeight: 720),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xff12242c), Color(0xff0d1720)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xffffd34d).withValues(alpha: 0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 30,
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ---- Score header ------------------------------------
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        _engine.blueTeam.name,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Color(0xfff4d03f),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        '${_engine.blueTeam.score} - ${_engine.redTeam.score}',
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        _engine.redTeam.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Color(0xff7ab8ff),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (_engine.shootout != null)
                Text(
                  'الترجيح: الأزرق ${_engine.shootout!.goalsFor(TeamId.blue)} - '
                  '${_engine.shootout!.goalsFor(TeamId.red)} الأحمر',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              const SizedBox(height: 10),

              // ---- Events: goals and cards with minutes --------------
              _summarySectionTitle('أهداف وبطاقات بالدقائق'),
              if (events.isEmpty)
                const Text(
                  'لا أحداث',
                  style: TextStyle(color: Colors.white38),
                )
              else
                ...events.where((e) => !e.canceled).map((event) {
                  final icon = _timelineEventIcon(event.kind);
                  final color = _timelineEventColor(event.kind);
                  final teamName = event.teamId == null
                      ? ''
                      : _engine.teamById(event.teamId!).name;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 42,
                          child: Text(
                            event.minute > 0 ? "${event.minute}'" : '-',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: color,
                            ),
                          ),
                        ),
                        Icon(icon, size: 16, color: color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${event.title} • ${event.detail}'
                            '${teamName.isEmpty ? '' : '  ($teamName)'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 12),

              // ---- Cards per player ---------------------------------
              if (_engine.disciplinaryEvents.isNotEmpty) ...[
                _summarySectionTitle('مذكرة البطاقات'),
                ..._engine.disciplinaryEvents.map((event) {
                  final isRed =
                      event.card == 'red' || event.card == 'secondYellow';
                  final label = event.card == 'secondYellow'
                      ? 'صفراء ثانية = حمراء'
                      : isRed
                          ? 'حمراء'
                          : 'صفراء';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      children: [
                        Container(
                          width: 14,
                          height: 18,
                          decoration: BoxDecoration(
                            color: isRed ? Colors.redAccent : Colors.amber,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${event.playerName} — $label د${event.minute}'
                            '${event.suspensionMatches > 0 ? ' • إيقاف ${event.suspensionMatches}م' : ''}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
              ],

              // ---- Quick stats grid ----------------------------------
              _summarySectionTitle('إحصائيات سريعة'),
              const SizedBox(height: 6),
              _statCompareRow(
                'الاستحواذ',
                '${_possessionFor(TeamId.blue).toStringAsFixed(0)}%',
                '${_possessionFor(TeamId.red).toStringAsFixed(0)}%',
              ),
              _statCompareRow(
                'التمريرات (ناجحة)',
                '${_engine.blueSuccessfulPasses}/${_engine.bluePasses}',
                '${_engine.redSuccessfulPasses}/${_engine.redPasses}',
              ),
              _statCompareRow(
                'التسديدات',
                '${_engine.blueShots}',
                '${_engine.redShots}',
              ),
              _statCompareRow(
                'الأخطاء',
                '${_engine.blueTeam.players.fold<int>(0, (sum, p) => sum + p.matchFoulsCommitted)}',
                '${_engine.redTeam.players.fold<int>(0, (sum, p) => sum + p.matchFoulsCommitted)}',
              ),
              _statCompareRow(
                'البطاقات',
                '${_engine.disciplinaryEvents.where((e) => e.teamId == TeamId.blue).length}',
                '${_engine.disciplinaryEvents.where((e) => e.teamId == TeamId.red).length}',
              ),
              _statCompareRow(
                'التصديات',
                '${_engine.blueTeam.goalkeeper.matchSaves}',
                '${_engine.redTeam.goalkeeper.matchSaves}',
              ),
              _statCompareRow(
                'التبعيدات',
                '${_engine.blueTeam.players.fold<int>(0, (sum, p) => sum + p.matchClearances)}',
                '${_engine.redTeam.players.fold<int>(0, (sum, p) => sum + p.matchClearances)}',
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'رجل المباراة: ${best.profile.name}  '
                  'أهداف ${best.matchGoals} • تمرير ناجح '
                  '${best.matchSuccessfulPasses}/${best.matchPasses} • '
                  'تسديد ${best.matchShotsOnTarget}/${best.matchShots} • '
                  'إنقاذ ${best.matchSaves}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 14),
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
              const SizedBox(height: 8),
              const Text(
                'Esc: القائمة الرئيسية',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summarySectionTitle(String text) {
    return Row(
      children: [
        Container(width: 4, height: 14, color: const Color(0xffffd34d)),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        ),
      ],
    );
  }

  Widget _statCompareRow(String label, String blue, String red) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              blue,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xfff4d03f),
              ),
            ),
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              red,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xff7ab8ff),
              ),
            ),
          ),
        ],
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
