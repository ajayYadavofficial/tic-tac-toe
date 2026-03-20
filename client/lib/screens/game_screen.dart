import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nakama/nakama.dart';

import '../core/constants.dart';
import '../core/nakama_client.dart';
import '../models/game_state.dart';
import 'result_screen.dart';

class GameScreen extends StatefulWidget {
  final String matchId;
  const GameScreen({super.key, required this.matchId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final _client = NakamaGameClient.instance;

  GameState _state = GameState.initial();
  GameResult? _result;
  String _statusText = 'Waiting for opponent...';

  StreamSubscription<MatchData>? _matchDataSub;
  bool _liveUpdateReceived = false;
  bool _movePending = false; // prevents double-tap sending duplicate moves

  // Timer countdown (Blitz mode)
  Timer? _countdownTimer;
  double _remainingFraction = 1.0; // 1.0 = full, 0.0 = expired

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _matchDataSub?.cancel();
    super.dispose();
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

    final json = jsonDecode(utf8.decode(data.data ?? [])) as Map<String, dynamic>;

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
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
    }
  }

  String _buildStatusText() {
    if (_state.status == 'waiting') return 'Waiting for opponent...';
    final myId = _client.session?.userId ?? '';
    final myMark = _state.playerX == myId ? 'X' : 'O';
    if (_state.turn == myMark) return 'Your turn ($myMark)';
    return "Opponent's turn (${_state.turn})";
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

  Widget _buildPlayerHeader() {
    final myId = _client.session?.userId ?? '';
    final myMark = _state.playerX == myId ? 'X' : 'O';
    final opponentMark = myMark == 'X' ? 'O' : 'X';

    final myName = myMark == 'X'
        ? (_state.playerXName.isNotEmpty ? _state.playerXName : 'You (X)')
        : (_state.playerOName.isNotEmpty ? _state.playerOName : 'You (O)');
    final opponentName = opponentMark == 'X'
        ? (_state.playerXName.isNotEmpty ? _state.playerXName : 'Opponent (X)')
        : (_state.playerOName.isNotEmpty ? _state.playerOName : 'Opponent (O)');

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _PlayerChip(name: myName, mark: myMark, isActive: _state.turn == myMark),
        const Text('vs', style: TextStyle(color: Colors.grey)),
        _PlayerChip(name: opponentName, mark: opponentMark, isActive: _state.turn == opponentMark),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Match'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_state.status == 'playing') ...[
                    _buildPlayerHeader(),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    _statusText,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  if (_state.turnSecs > 0 && _state.status == 'playing') ...[
                    const SizedBox(height: 16),
                    _TurnTimerBar(
                      fraction: _remainingFraction,
                      turnSecs: _state.turnSecs,
                    ),
                  ],
                  const SizedBox(height: 32),

                  AspectRatio(
                    aspectRatio: 1,
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemCount: 9,
                      itemBuilder: (_, i) => _BoardCell(
                        value: _state.board[i],
                        onTap: () => _onCellTap(i),
                        enabled: _isMyTurn && _state.board[i].isEmpty && _result == null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  final String name;
  final String mark;
  final bool isActive;

  const _PlayerChip({required this.name, required this.mark, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = mark == 'X' ? Colors.indigo : Colors.orange;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isActive ? color : Colors.grey.shade300, width: isActive ? 2 : 1),
      ),
      child: Column(
        children: [
          Text(mark, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _TurnTimerBar extends StatelessWidget {
  final double fraction;
  final int turnSecs;

  const _TurnTimerBar({required this.fraction, required this.turnSecs});

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(Colors.red, Colors.green, fraction) ?? Colors.green;
    final remaining = (fraction * turnSecs).ceil();

    return Column(
      children: [
        Text(
          '${remaining}s',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 8,
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
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
        ? Colors.indigo
        : value == 'O'
            ? Colors.orange
            : null;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: enabled
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Center(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
