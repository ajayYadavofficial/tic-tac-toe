import 'package:flutter/material.dart';

import '../core/nakama_client.dart';
import 'lobby_screen.dart';

// ── Consistent theme colors (shared with lobby) ──
const _kBlue = Color(0xFF4A90D9);
const _kCoral = Color(0xFFE8734A);
const _kBg = Color(0xFFF8F9FC);
const _kCardBg = Colors.white;
const _kTextPrimary = Color(0xFF2D3142);
const _kTextSecondary = Color(0xFF9A9BB2);

class NicknameScreen extends StatefulWidget {
  const NicknameScreen({super.key});

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen>
    with SingleTickerProviderStateMixin {
  final _usernameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _focusNode = FocusNode();
  bool _loading = false;
  bool _initializing = true;
  String? _error;
  String? _previousUsername;

  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _loadPreviousUsername();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _usernameCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Animation<double> _stagger(double begin, double end) {
    return CurvedAnimation(
      parent: _animCtrl,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  Future<void> _loadPreviousUsername() async {
    final client = NakamaGameClient.instance;
    final saved = await client.getSavedUsername();
    if (!mounted) return;
    setState(() {
      _previousUsername = saved;
      if (saved != null && saved.isNotEmpty) {
        _usernameCtrl.text = saved;
      }
      _initializing = false;
    });
    _animCtrl.forward(from: 0);
  }

  Future<void> _confirm() async {
    if (!_formKey.currentState!.validate()) return;

    final username = _usernameCtrl.text.trim();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = NakamaGameClient.instance;
      final deviceId = await client.getOrCreateDeviceId();
      await client.authenticateDevice(deviceId);
      await client.connectSocket();

      try {
        await client.updateUsername(username);
      } catch (e) {
        final errMsg = e.toString().toLowerCase();
        if (errMsg.contains('taken') ||
            errMsg.contains('in use') ||
            errMsg.contains('already')) {
          setState(() {
            _error = 'Username "$username" is already taken. Try a different one.';
            _loading = false;
          });
          return;
        }
        rethrow;
      }

      await client.persistUsername(username);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LobbyScreen()),
      );
    } on StateError catch (e) {
      debugPrint('Auth state error: $e');
      setState(() {
        _error = 'Session error. Please try again.';
      });
    } catch (e) {
      debugPrint('Sign-in error: $e');
      final errMsg = e.toString().toLowerCase();
      if (errMsg.contains('socket') || errMsg.contains('connection')) {
        setState(() {
          _error =
              'Cannot reach the server. Check your connection and try again.';
        });
      } else {
        setState(() {
          _error = 'Could not sign in. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReturning =
        _previousUsername != null && _previousUsername!.isNotEmpty;

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: _initializing
            ? const Center(
                child: CircularProgressIndicator(color: _kBlue),
              )
            : Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // ── Decorative X O ──
                        _FadeSlide(
                          animation: _stagger(0.0, 0.3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              _DecoSymbol(symbol: 'X', color: _kBlue, size: 56),
                              SizedBox(width: 20),
                              _DecoSymbol(symbol: 'O', color: _kCoral, size: 56),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Title ──
                        _FadeSlide(
                          animation: _stagger(0.05, 0.35),
                          child: const Text(
                            'TIC TAC TOE',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: _kTextPrimary,
                              letterSpacing: 3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _FadeSlide(
                          animation: _stagger(0.08, 0.38),
                          child: Text(
                            isReturning
                                ? 'Welcome back!'
                                : 'Challenge players around the world',
                            style: const TextStyle(
                              fontSize: 14,
                              color: _kTextSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),

                        // ── Card with form ──
                        _FadeSlide(
                          animation: _stagger(0.15, 0.5),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
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
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    isReturning
                                        ? 'Continue as ${_previousUsername!} or pick a new name'
                                        : 'Pick a username to get started',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: _kTextSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 24),

                                  // ── Username field ──
                                  TextFormField(
                                    controller: _usernameCtrl,
                                    focusNode: _focusNode,
                                    autofocus: true,
                                    maxLength: 20,
                                    textCapitalization: TextCapitalization.none,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: _kTextPrimary,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: 'Username',
                                      labelStyle: const TextStyle(
                                        color: _kTextSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      prefixIcon: Container(
                                        width: 44,
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          Icons.person_rounded,
                                          color: _kBlue,
                                          size: 22,
                                        ),
                                      ),
                                      filled: true,
                                      fillColor: _kBg,
                                      counterStyle: const TextStyle(
                                        color: _kTextSecondary,
                                        fontSize: 11,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: const BorderSide(
                                          color: _kBlue,
                                          width: 2,
                                        ),
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: const BorderSide(
                                          color: _kCoral,
                                          width: 1.5,
                                        ),
                                      ),
                                      focusedErrorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: const BorderSide(
                                          color: _kCoral,
                                          width: 2,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                    ),
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Enter a username';
                                      }
                                      if (v.trim().length < 2) {
                                        return 'At least 2 characters';
                                      }
                                      return null;
                                    },
                                    onFieldSubmitted: (_) => _confirm(),
                                  ),

                                  // ── Error ──
                                  if (_error != null) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: _kCoral.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.error_outline_rounded,
                                              size: 18, color: _kCoral),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _error!,
                                              style: const TextStyle(
                                                color: _kCoral,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 20),

                                  // ── Submit button ──
                                  SizedBox(
                                    height: 52,
                                    child: Material(
                                      color: _kBlue,
                                      borderRadius: BorderRadius.circular(50),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(50),
                                        onTap: _loading ? null : _confirm,
                                        child: Center(
                                          child: _loading
                                              ? const SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2.5,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : Text(
                                                  isReturning
                                                      ? "Let's Play"
                                                      : 'Get Started',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 16,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // ── Footer tagline ──
                        _FadeSlide(
                          animation: _stagger(0.3, 0.6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 24,
                                height: 2,
                                decoration: BoxDecoration(
                                  color: _kBlue.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Real-time multiplayer',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _kTextSecondary,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                width: 24,
                                height: 2,
                                decoration: BoxDecoration(
                                  color: _kCoral.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(1),
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
}

// ═══════════════════════════════════════════════════════════════
//  Reusable widgets (same as lobby for consistency)
// ═══════════════════════════════════════════════════════════════

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

class _DecoSymbol extends StatelessWidget {
  final String symbol;
  final Color color;
  final double size;

  const _DecoSymbol({
    required this.symbol,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      symbol,
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w900,
        color: color,
        height: 1,
      ),
    );
  }
}
