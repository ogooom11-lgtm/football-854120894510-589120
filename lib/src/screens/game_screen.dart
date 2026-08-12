import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/enums/ai_difficulty.dart';
import '../game/enums/kick_type.dart';
import '../game/enums/ai_play_style.dart';
import '../game/logic/match_engine.dart';
import '../game/enums/team_id.dart';
import '../game/logic/penalty_logic.dart';
import '../game/math/vec2.dart';
import '../game/models/player_game.dart';
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

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final last = _lastTick;
    _lastTick = elapsed;
    if (last == null) {
      return;
    }
    final dt = (elapsed - last).inMicroseconds / Duration.microsecondsPerSecond;
    _applyMovement(dt.clamp(0, 0.05).toDouble());
    _engine.tick(dt.clamp(0, 0.05).toDouble());
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
        if (_engine.replayMode) {
          _engine.closeReplay();
          setState(() {});
          return;
        }
        if (_subTeam != null) {
          _engine.setSubstitutionPaused(false);
          setState(() => _subTeam = null);
          return;
        }
        Navigator.of(context).maybePop(_engine.createFinishedSummary());
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

  void _openSubstitution(TeamId teamId) {
    final team = _engine.teamById(teamId);
    if (team.bench.isEmpty || team.substitutionsUsed >= 5) {
      return;
    }
    setState(() {
      _subTeam = teamId;
      _subOutIndex = 0;
      _subBenchIndex = 0;
      _subPickingBench = false;
    });
    _engine.setSubstitutionPaused(true);
    _injurySubActive = _engine.hasInjuryForcedSub;
    if (_injurySubActive) {
      _injuryVictim = _engine.popInjuryForcedSub();
    }
  }

  bool _handleSubstitutionKey(LogicalKeyboardKey key) {
    final teamId = _subTeam;
    if (teamId == null) {
      return false;
    }
    final team = _engine.teamById(teamId);
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      if (_subPickingBench) {
        _subBenchIndex = (_subBenchIndex - 1).clamp(0, team.bench.length - 1);
      } else {
        _subOutIndex = (_subOutIndex - 1).clamp(0, team.players.length - 1);
      }
      return true;
    }
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyS) {
      if (_subPickingBench) {
        _subBenchIndex = (_subBenchIndex + 1).clamp(0, team.bench.length - 1);
      } else {
        _subOutIndex = (_subOutIndex + 1).clamp(0, team.players.length - 1);
      }
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
      _subPickingBench = false;
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD) {
      _subPickingBench = true;
      return true;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (!_subPickingBench) {
        _subPickingBench = true;
        return true;
      }
      if (_engine.substitute(teamId, _subOutIndex, _subBenchIndex)) {
        _engine.setSubstitutionPaused(false);
        _subTeam = null;
      }
      return true;
    }
    return true;
  }

  (TeamId, KickType)? _actionForKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.space) {
      return (TeamId.blue, KickType.shoot);
    }
    if (key == LogicalKeyboardKey.keyZ) {
      return (TeamId.blue, KickType.pass);
    }
    if (key == LogicalKeyboardKey.keyX) {
      return (TeamId.blue, KickType.highPass);
    }
    if (key == LogicalKeyboardKey.keyO) {
      return (TeamId.red, KickType.shoot);
    }
    if (key == LogicalKeyboardKey.keyP) {
      return (TeamId.red, KickType.pass);
    }
    if (key == LogicalKeyboardKey.keyL) {
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
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: GamePainter(_engine)),
                    ),
                    if (_engine.banner != null) _banner(),
                    if (_engine.wallSelectionPending) _freeKickWallPanel(),
                    if (_engine.activePenalty != null &&
                        _engine.activePenalty!.result == null)
                      _penaltyKeyboardHint(),
                    if (_subTeam != null) _substitutionPanel(),
                    if (_engine.replayMode) _replayPanel(),
                    if (_engine.finished) _resultPanel(),
                  ],
                ),
              ),
            ],
          ),
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

  Widget _banner() {
    final banner = _engine.banner!;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              banner.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              banner.subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, color: Colors.white70),
            ),
            if (_engine.varReviewActive) ...[
              const SizedBox(height: 14),
              const Text(
                'R veya Enter: VAR gec',
                style: TextStyle(color: Colors.white70),
              ),
            ],
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
    final outPlayer =
        team.players[_subOutIndex.clamp(0, team.players.length - 1)];
    final benchPlayer =
        team.bench[_subBenchIndex.clamp(0, team.bench.length - 1)];
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 460,
        margin: const EdgeInsets.only(left: 28),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xff101820).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${team.name} degisiklik ${team.substitutionsUsed}/5${_injurySubActive ? " (ZORUNLU SAKATLIK)" : ""}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: _injurySubActive ? Colors.redAccent : Colors.white,
              ),
            ),
            if (_injuryVictim != null)
              Text(
                '${_injuryVictim!.profile.name} sakatlandi! Hemen degistirin.',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 10),
            Text(
              'Cikan: ${outPlayer.number} ${outPlayer.profile.name}  Enerji ${(outPlayer.stamina * 100).round()}%',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              'Giren: ${benchPlayer.number} ${benchPlayer.profile.name}  Enerji ${(benchPlayer.stamina * 100).round()}%',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              _subPickingBench
                  ? '2. Adim: girecek oyuncuyu sec'
                  : '1. Adim: cikacak oyuncuyu sec',
              style: const TextStyle(color: Color(0xffffd34d)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: Row(
                children: [
                  Expanded(
                    child: _subList(
                      team.players,
                      _subOutIndex,
                      active: !_subPickingBench,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _subList(
                      team.bench,
                      _subBenchIndex,
                      active: _subPickingBench,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Yukari/Asagi sec, Enter sonraki adim/onay, Sol/Sag kolon, Esc cikis',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subList(
    List<PlayerGame> players,
    int selectedIndex, {
    required bool active,
  }) {
    return ListView.builder(
      itemCount: players.length,
      itemBuilder: (context, index) {
        final player = players[index];
        final selected = index == selectedIndex;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          color: selected
              ? (active
                    ? const Color(0xffffd34d).withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.12))
              : Colors.transparent,
          child: Text(
            '${player.number} ${player.profile.name} ${(player.stamina * 100).round()}%',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  Widget _replayPanel() {
    final frame = _engine.currentReplayFrame;
    final goals = _engine.reviewGoals;
    return Positioned(
      left: 24,
      right: 24,
      bottom: 20,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xff101820).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  frame == null
                      ? 'VAR'
                      : 'VAR ${frame.minute.toStringAsFixed(1)} - ${frame.description}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    _engine.toggleReplayPlayback();
                    setState(() {});
                  },
                  icon: Icon(
                    _engine.replayPlaying ? Icons.pause : Icons.play_arrow,
                  ),
                  label: Text(_engine.replayPlaying ? 'Duraklat' : 'Oynat'),
                ),
                TextButton.icon(
                  onPressed: () {
                    _engine.closeReplay();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Cik'),
                ),
              ],
            ),
            Slider(
              value: _engine.replayProgress.clamp(0, 1).toDouble(),
              onChanged: (value) {
                _engine.setReplayProgress(value);
                setState(() {});
              },
            ),
            if (goals.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < goals.length; i++)
                    OutlinedButton.icon(
                      onPressed: () {
                        _engine.toggleGoalReview(i);
                        setState(() {});
                      },
                      icon: Icon(
                        goals[i].canceled ? Icons.undo : Icons.cancel_outlined,
                        size: 17,
                      ),
                      label: Text(
                        "${goals[i].minute}' ${goals[i].scorerName}${goals[i].canceled ? ' iptal' : ''}",
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

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
            const Text(
              'Esc: Ana menu',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
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
