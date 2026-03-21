import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nakama/nakama.dart';

import '../core/nakama_client.dart';
import '../models/game_template.dart';
import 'game_screen.dart';

// ── Consistent theme colors ──
const _kBlue = Color(0xFF4A90D9);
const _kCoral = Color(0xFFE8734A);
const _kBg = Color(0xFFF8F9FC);
const _kCardBg = Colors.white;
const _kTextPrimary = Color(0xFF2D3142);
const _kTextSecondary = Color(0xFF9A9BB2);

class MatchmakingScreen extends StatefulWidget {
  final GameTemplate template;

  const MatchmakingScreen({super.key, required this.template});

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen>
    with TickerProviderStateMixin {
  final _client = NakamaGameClient.instance;

  static const _matchmakingTimeout = Duration(seconds: 60);

  String? _ticket;
  StreamSubscription<MatchmakerMatched>? _matchmakerSub;
  Timer? _timeoutTimer;
  String? _error;

  // Animations
  late AnimationController _pulseCtrl;
  late AnimationController _rotateCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _pulseAnim;

  // Elapsed timer
  Timer? _elapsedTimer;
  int _elapsedSecs = 0;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _rotateCtrl = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();

    _fadeCtrl = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..forward();

    _startMatchmaking();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _rotateCtrl.dispose();
    _fadeCtrl.dispose();
    _timeoutTimer?.cancel();
    _elapsedTimer?.cancel();
    _matchmakerSub?.cancel();
    final t = _ticket;
    if (t != null) {
      _client.removeFromMatchmaker(t).catchError((_) {});
    }
    super.dispose();
  }

  Future<void> _startMatchmaking() async {
    setState(() {
      _error = null;
      _elapsedSecs = 0;
    });

    // Start elapsed counter
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() { _elapsedSecs++; });
    });

    try {
      debugPrint(
          'Matchmaking: template=${widget.template.name} id=${widget.template.id} variant=${widget.template.variant} turnSecs=${widget.template.turnSecs}');
      final ticket =
          await _client.addToMatchmaker(templateId: widget.template.id);
      setState(() { _ticket = ticket.ticket; });

      _timeoutTimer?.cancel();
      _timeoutTimer = Timer(_matchmakingTimeout, () {
        if (!mounted) return;
        _matchmakerSub?.cancel();
        _elapsedTimer?.cancel();
        final t = _ticket;
        if (t != null) {
          _client.removeFromMatchmaker(t).catchError((_) {});
          _ticket = null;
        }
        setState(() { _error = 'No opponents found. Please try again.'; });
      });

      _matchmakerSub?.cancel();
      _matchmakerSub = _client.onMatchmakerMatched.listen((matched) async {
        if (!mounted) return;
        _timeoutTimer?.cancel();
        _elapsedTimer?.cancel();
        _matchmakerSub?.cancel();

        final matchId = matched.matchId;
        final token = matched.token;

        String realMatchId;
        if (matchId != null && matchId.isNotEmpty) {
          await _client.joinMatch(matchId);
          realMatchId = matchId;
        } else if (token != null && token.isNotEmpty) {
          realMatchId = await _client.joinMatchByToken(token);
        } else {
          return;
        }

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => GameScreen(matchId: realMatchId)),
        );
      });
    } catch (e) {
      _elapsedTimer?.cancel();
      setState(() { _error = 'Matchmaking error: $e'; });
    }
  }

  Future<void> _cancel() async {
    _timeoutTimer?.cancel();
    _elapsedTimer?.cancel();
    final t = _ticket;
    if (t != null) {
      await _client.removeFromMatchmaker(t);
    }
    _matchmakerSub?.cancel();
    if (mounted) Navigator.pop(context);
  }

  String get _elapsedFormatted {
    final m = _elapsedSecs ~/ 60;
    final s = _elapsedSecs % 60;
    return m > 0
        ? '${m}m ${s.toString().padLeft(2, '0')}s'
        : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final isBlitz = widget.template.variant == 'blitz';
    final accent = isBlitz ? _kCoral : _kBlue;

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeCtrl,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_error != null)
                      _buildError(accent)
                    else
                      _buildSearching(accent, isBlitz),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearching(Color accent, bool isBlitz) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Animated search orb ──
        SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer rotating ring
              AnimatedBuilder(
                animation: _rotateCtrl,
                builder: (_, child) => Transform.rotate(
                  angle: _rotateCtrl.value * 2 * math.pi,
                  child: child,
                ),
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withValues(alpha: 0.15),
                      width: 2,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Orbiting dot
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Middle pulsing ring
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Container(
                  width: 110 * _pulseAnim.value,
                  height: 110 * _pulseAnim.value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withValues(alpha: 0.1),
                      width: 1.5,
                    ),
                  ),
                ),
              ),

              // Center icon circle
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [accent, accent.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    isBlitz ? 'O' : 'X',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),

        // ── Title ──
        Text(
          'Finding opponent...',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: _kTextPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.template.name,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: accent,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.template.description,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: _kTextSecondary,
          ),
        ),
        const SizedBox(height: 24),

        // ── Elapsed time chip ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timer_outlined, size: 16, color: _kTextSecondary),
              const SizedBox(width: 6),
              Text(
                _elapsedFormatted,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _kTextPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),

        // ── Cancel button ──
        SizedBox(
          height: 48,
          width: 160,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(50),
            child: InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: _cancel,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: _kTextSecondary.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: const Center(
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _kTextSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError(Color accent) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Error icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kCoral.withValues(alpha: 0.1),
          ),
          child: const Icon(
            Icons.wifi_off_rounded,
            size: 36,
            color: _kCoral,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'No match found',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _kTextPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: _kTextSecondary,
            ),
          ),
        ),
        const SizedBox(height: 32),

        // Retry button
        SizedBox(
          height: 50,
          width: 200,
          child: Material(
            color: accent,
            borderRadius: BorderRadius.circular(50),
            child: InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: _startMatchmaking,
              child: const Center(
                child: Text(
                  'Try Again',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Back button
        SizedBox(
          height: 48,
          width: 200,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(50),
            child: InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: _cancel,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: _kTextSecondary.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: const Center(
                  child: Text(
                    'Back to Lobby',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _kTextSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
