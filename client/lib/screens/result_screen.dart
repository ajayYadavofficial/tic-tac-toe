import 'package:flutter/material.dart';

import '../models/game_state.dart';
import 'lobby_screen.dart';

// ── Consistent theme colors (shared with lobby & game) ──
const _kBlue = Color(0xFF4A90D9);
const _kCoral = Color(0xFFE8734A);
const _kBg = Color(0xFFF8F9FC);
const _kCardBg = Colors.white;
const _kTextPrimary = Color(0xFF2D3142);
const _kTextSecondary = Color(0xFF9A9BB2);

class ResultScreen extends StatefulWidget {
  final GameResult result;
  final String myUserId;

  const ResultScreen({
    super.key,
    required this.result,
    required this.myUserId,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _stagger(double begin, double end) {
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final isDraw = result.result == 'draw';
    final isWinner = !isDraw && result.winner == widget.myUserId;

    final (headline, accentColor, points) = isDraw
        ? ("It's a Draw!", const Color(0xFFFBBF24), '+50')
        : isWinner
            ? ('You Win!', const Color(0xFF4ADE80), '+200')
            : ('You Lose', _kCoral, '+0');

    final myMark = result.playerX == widget.myUserId ? 'X' : 'O';
    final opponentMark = myMark == 'X' ? 'O' : 'X';
    final myName = myMark == 'X' ? result.playerXName : result.playerOName;
    final opponentName =
        opponentMark == 'X' ? result.playerXName : result.playerOName;

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Result hero card ──
                  _FadeSlide(
                    animation: _stagger(0.0, 0.3),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 32, horizontal: 24),
                      decoration: BoxDecoration(
                        color: _kCardBg,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.15),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Result icon
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              isDraw
                                  ? Icons.handshake_rounded
                                  : isWinner
                                      ? Icons.emoji_events_rounded
                                      : Icons.sentiment_dissatisfied_rounded,
                              size: 36,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            headline,
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: _kTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: Text(
                              '$points pts',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: accentColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Player labels ──
                  _FadeSlide(
                    animation: _stagger(0.1, 0.4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
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
                            child: _PlayerLabel(
                              name:
                                  myName.isNotEmpty ? myName : 'You',
                              mark: myMark,
                              isYou: true,
                              isWinner: !isDraw &&
                                  result.winner == widget.myUserId,
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
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
                            child: _PlayerLabel(
                              name: opponentName.isNotEmpty
                                  ? opponentName
                                  : 'Opponent',
                              mark: opponentMark,
                              isYou: false,
                              isWinner: !isDraw &&
                                  result.winner != widget.myUserId,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Final board ──
                  _FadeSlide(
                    animation: _stagger(0.2, 0.5),
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
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemCount: 9,
                          itemBuilder: (_, i) => _ResultBoardCell(
                            value: result.board[i],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Action buttons ──
                  _FadeSlide(
                    animation: _stagger(0.35, 0.65),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: Material(
                            color: _kBlue,
                            borderRadius: BorderRadius.circular(50),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(50),
                              onTap: () => _goToLobby(context),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.bolt_rounded,
                                        color: Colors.white, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Play Again',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: Material(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(50),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(50),
                              onTap: () => _goToLobby(context),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Text(
                                  'Back to Lobby',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _kTextPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
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
    );
  }

  void _goToLobby(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LobbyScreen()),
      (_) => false,
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

class _PlayerLabel extends StatelessWidget {
  final String name;
  final String mark;
  final bool isYou;
  final bool isWinner;

  const _PlayerLabel({
    required this.name,
    required this.mark,
    required this.isYou,
    required this.isWinner,
  });

  @override
  Widget build(BuildContext context) {
    final color = mark == 'X' ? _kBlue : _kCoral;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Gradient avatar
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
            boxShadow: isWinner
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
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
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isWinner ? _kTextPrimary : _kTextSecondary,
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
    );
  }
}

class _ResultBoardCell extends StatelessWidget {
  final String value;

  const _ResultBoardCell({required this.value});

  @override
  Widget build(BuildContext context) {
    final color = value == 'X'
        ? _kBlue
        : value == 'O'
            ? _kCoral
            : null;

    return Container(
      decoration: BoxDecoration(
        color: value.isNotEmpty
            ? (color ?? Colors.grey).withValues(alpha: 0.06)
            : const Color(0xFFF0F1F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: value.isNotEmpty
            ? [
                BoxShadow(
                  color: (color ?? Colors.grey).withValues(alpha: 0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ]
            : null,
      ),
      child: Center(
        child: Text(
          value,
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ),
    );
  }
}
