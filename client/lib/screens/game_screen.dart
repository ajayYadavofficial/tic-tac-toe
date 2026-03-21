import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nakama/nakama.dart';

import '../core/constants.dart';
import '../core/nakama_client.dart';
import '../models/game_state.dart';
import 'lobby_screen.dart';
import 'result_screen.dart';

// ── Consistent theme colors (shared with lobby) ──
const _kBlue = Color(0xFF4A90D9);
const _kCoral = Color(0xFFE8734A);
const _kBg = Color(0xFFF8F9FC);
const _kCardBg = Colors.white;
const _kTextPrimary = Color(0xFF2D3142);
const _kTextSecondary = Color(0xFF9A9BB2);

class GameScreen extends StatefulWidget {
  final String matchId;
  const GameScreen({super.key, required this.matchId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  final _client = NakamaGameClient.instance;

  GameState _state = GameState.initial();
  GameResult? _result;
  String _statusText = 'Waiting for opponent...';
  bool _gameOver = false;

  StreamSubscription<MatchData>? _matchDataSub;
  bool _liveUpdateReceived = false;
  bool _movePending = false;

  // Timer countdown (Blitz mode)
  Timer? _countdownTimer;
  double _remainingFraction = 1.0;

  // Entry animation
  late AnimationController _entryController;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _matchDataSub = _client.matchDataStream.listen((data) {
      if (data.matchId == widget.matchId) _liveUpdateReceived = true;
      _onMatchData(data);
    });
    final cached = _client.getCachedState(widget.matchId);
    if (cached != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_liveUpdateReceived) _onMatchData(cached);
      });
    }
    _entryController.forward();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _matchDataSub?.cancel();
    _entryController.dispose();
    super.dispose();
  }

  /// Back button pressed — resign and go to lobby.
  Future<void> _onBackPressed() async {
    if (_gameOver) {
      _goToLobby();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Leave Game?',
            style: TextStyle(fontWeight: FontWeight.w700, color: _kTextPrimary)),
        content: const Text('Leaving will count as a forfeit. Are you sure?',
            style: TextStyle(color: _kTextSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay',
                style: TextStyle(color: _kBlue, fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kCoral,
              shape: const StadiumBorder(),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _client.sendResign(widget.matchId);
      _client.leaveMatch(widget.matchId).catchError((_) {});
      _goToLobby();
    }
  }

  void _goToLobby() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LobbyScreen()),
    );
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    if (_state.turnSecs <= 0 || _state.turnStartedAt <= 0) return;
    _countdownTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final elapsed = now - _state.turnStartedAt;
      final remaining = _state.turnSecs - elapsed;
      setState(() {
        _remainingFraction = (remaining / _state.turnSecs).clamp(0.0, 1.0);
      });
      if (remaining <= 0) {
        _countdownTimer?.cancel();
      }
    });
  }

  void _onMatchData(MatchData data) {
    if (data.matchId != widget.matchId) return;

    final json =
        jsonDecode(utf8.decode(data.data ?? [])) as Map<String, dynamic>;

    switch (data.opCode) {
      case AppConstants.opCodeState:
        setState(() {
          _state = GameState.fromJson(json);
          _result = null;
          _movePending = false;
          _statusText = _buildStatusText();
        });
        _startCountdownTimer();

      case AppConstants.opCodeResult:
        final result = GameResult.fromJson(json);
        _gameOver = true;
        setState(() {
          _result = result;
          _statusText = _buildResultText(result);
        });
        if (mounted) {
          final myId = _client.session?.userId ?? '';
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ResultScreen(result: result, myUserId: myId),
            ),
          );
        }

      case AppConstants.opCodeError:
        final msg = json['message'] as String? ?? 'Invalid move';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: _kCoral,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
    }
  }

  String _buildStatusText() {
    if (_state.status == 'waiting') return 'Waiting for opponent...';
    final myId = _client.session?.userId ?? '';
    final myMark = _state.playerX == myId ? 'X' : 'O';
    if (_state.turn == myMark) return 'Your turn';
    return "Opponent's turn";
  }

  String _buildResultText(GameResult result) {
    if (result.result == 'draw') return "It's a draw!";
    final myId = _client.session?.userId ?? '';
    return result.winner == myId ? 'You win!' : 'You lose!';
  }

  bool get _isMyTurn {
    if (_state.status != 'playing') return false;
    final myId = _client.session?.userId ?? '';
    final myMark = _state.playerX == myId ? 'X' : 'O';
    return _state.turn == myMark;
  }

  void _onCellTap(int index) {
    if (!_isMyTurn) return;
    if (_state.board[index].isNotEmpty) return;
    if (_result != null) return;
    if (_movePending) return;
    _movePending = true;
    _client.sendMove(widget.matchId, index);
  }

  Animation<double> _stagger(double begin, double end) {
    return CurvedAnimation(
      parent: _entryController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBackPressed();
      },
      child: Scaffold(
        backgroundColor: _kBg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    // ── Top bar ──
                    _FadeSlide(
                      animation: _stagger(0.0, 0.3),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 8),
                        child: Row(
                          children: [
                            Material(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _onBackPressed,
                                child: const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Icon(Icons.arrow_back_rounded,
                                      size: 20, color: _kTextSecondary),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Match',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: _kTextPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // ── Player header ──
                          if (_state.status == 'playing') ...[
                            _FadeSlide(
                              animation: _stagger(0.1, 0.4),
                              child: _buildPlayerHeader(),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // ── Status text ──
                          _FadeSlide(
                            animation: _stagger(0.15, 0.45),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(
                                color: _isMyTurn
                                    ? _kBlue.withValues(alpha: 0.08)
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(50),
                              ),
                              child: Text(
                                _statusText,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      _isMyTurn ? _kBlue : _kTextSecondary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),

                          // ── Turn timer (Blitz) ──
                          if (_state.turnSecs > 0 &&
                              _state.status == 'playing') ...[
                            const SizedBox(height: 16),
                            _FadeSlide(
                              animation: _stagger(0.2, 0.5),
                              child: _TurnTimerCard(
                                fraction: _remainingFraction,
                                turnSecs: _state.turnSecs,
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),

                          // ── Board ──
                          _FadeSlide(
                            animation: _stagger(0.25, 0.6),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _kCardBg,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: _kBlue.withValues(alpha: 0.08),
                                    blurRadius: 24,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: GridView.builder(
                                  shrinkWrap: true,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                  ),
                                  itemCount: 9,
                                  itemBuilder: (_, i) => _BoardCell(
                                    value: _state.board[i],
                                    onTap: () => _onCellTap(i),
                                    enabled: _isMyTurn &&
                                        _state.board[i].isEmpty &&
                                        _result == null,
                                  ),
                                ),
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
        ),
      ),
    );
  }

  Widget _buildPlayerHeader() {
    final myId = _client.session?.userId ?? '';
    final myMark = _state.playerX == myId ? 'X' : 'O';
    final opponentMark = myMark == 'X' ? 'O' : 'X';

    final myName = myMark == 'X'
        ? (_state.playerXName.isNotEmpty ? _state.playerXName : 'You')
        : (_state.playerOName.isNotEmpty ? _state.playerOName : 'You');
    final opponentName = opponentMark == 'X'
        ? (_state.playerXName.isNotEmpty ? _state.playerXName : 'Opponent')
        : (_state.playerOName.isNotEmpty ? _state.playerOName : 'Opponent');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _PlayerChip(
              name: myName,
              mark: myMark,
              isActive: _state.turn == myMark,
              isYou: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'VS',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _kTextSecondary,
                letterSpacing: 1,
              ),
            ),
          ),
          Expanded(
            child: _PlayerChip(
              name: opponentName,
              mark: opponentMark,
              isActive: _state.turn == opponentMark,
              isYou: false,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Sub-widgets
// ═══════════════════════════════════════════════════════════════

/// Fade + slide-up wrapper driven by a parent animation
class _FadeSlide extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _FadeSlide({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Opacity(
          opacity: animation.value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - animation.value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _PlayerChip extends StatelessWidget {
  final String name;
  final String mark;
  final bool isActive;
  final bool isYou;

  const _PlayerChip({
    required this.name,
    required this.mark,
    required this.isActive,
    required this.isYou,
  });

  @override
  Widget build(BuildContext context) {
    final color = mark == 'X' ? _kBlue : _kCoral;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? color.withValues(alpha: 0.3) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Gradient avatar circle
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: mark == 'X'
                    ? [_kBlue, const Color(0xFF6CB4EE)]
                    : [_kCoral, const Color(0xFFFF9A76)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(11),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Name + mark
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isActive ? _kTextPrimary : _kTextSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isYou ? '$mark · You' : mark,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnTimerCard extends StatelessWidget {
  final double fraction;
  final int turnSecs;

  const _TurnTimerCard({required this.fraction, required this.turnSecs});

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(_kCoral, _kBlue, fraction) ?? _kBlue;
    final remaining = (fraction * turnSecs).ceil();
    final isLow = remaining <= 3;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLow
              ? _kCoral.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: (isLow ? _kCoral : Colors.black).withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Timer icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.timer_rounded, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          // Seconds text
          Text(
            '${remaining}s',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(width: 14),
          // Progress bar
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardCell extends StatelessWidget {
  final String value;
  final VoidCallback onTap;
  final bool enabled;

  const _BoardCell({
    required this.value,
    required this.onTap,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final color = value == 'X'
        ? _kBlue
        : value == 'O'
            ? _kCoral
            : null;

    return Material(
      color: enabled ? _kCardBg : const Color(0xFFF0F1F5),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        splashColor: _kBlue.withValues(alpha: 0.1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: enabled
                  ? _kBlue.withValues(alpha: 0.2)
                  : Colors.grey.shade200,
              width: enabled ? 1.5 : 1,
            ),
            boxShadow: value.isNotEmpty
                ? [
                    BoxShadow(
                      color: (color ?? Colors.grey).withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    )
                  ]
                : null,
          ),
          child: Center(
            child: AnimatedScale(
              scale: value.isNotEmpty ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
