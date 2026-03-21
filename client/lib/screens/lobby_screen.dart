import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/nakama_client.dart';
import '../core/web_lifecycle_stub.dart'
    if (dart.library.js_interop) '../core/web_lifecycle_web.dart';
import '../models/game_state.dart';
import '../models/game_template.dart';
import 'leaderboard_screen.dart';
import 'matchmaking_screen.dart';
import 'nickname_screen.dart';

// ── Theme colors inspired by reference (blue X, coral O) ──
const _kBlue = Color(0xFF4A90D9);
const _kCoral = Color(0xFFE8734A);
const _kBg = Color(0xFFF8F9FC);
const _kCardBg = Colors.white;
const _kTextPrimary = Color(0xFF2D3142);
const _kTextSecondary = Color(0xFF9A9BB2);

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final _client = NakamaGameClient.instance;

  List<GameTemplate> _templates = [];
  String _username = '';
  PlayerStats _stats = const PlayerStats();
  List<LeaderboardEntry> _leaderboard = [];
  bool _loading = true;
  bool _loggingOut = false;
  String? _error;

  late AnimationController _staggerController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _registerBrowserCloseHandler();
    _staggerController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _load();
  }

  @override
  void dispose() {
    _staggerController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _registerBrowserCloseHandler() {
    setupWebBeforeUnload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _client.logout();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final results = await Future.wait([
        _client.listTemplates(),
        _client.getPlayerStats(),
        _client.getLeaderboard(),
      ]);
      if (!mounted) return;
      setState(() {
        _username = prefs.getString('username') ?? '';
        _templates = results[0] as List<GameTemplate>;
        _stats = results[1] as PlayerStats;
        _leaderboard = results[2] as List<LeaderboardEntry>;
        _loading = false;
      });
      _staggerController.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      final errMsg = e.toString().toLowerCase();
      if (errMsg.contains('auth token') ||
          errMsg.contains('code 16') ||
          errMsg.contains('unauthenticated')) {
        debugPrint('Session invalid in lobby, redirecting to login: $e');
        await _client.fullLogout();
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const NicknameScreen()),
          (_) => false,
        );
        return;
      }
      setState(() {
        _error = 'Failed to load lobby. Tap retry.';
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout', style: TextStyle(color: _kTextPrimary)),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kCoral,
              shape: const StadiumBorder(),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() { _loggingOut = true; });
    try {
      await _client.fullLogout();
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const NicknameScreen()),
      (_) => false,
    );
  }

  Future<void> _playTemplate(GameTemplate template) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatchmakingScreen(template: template),
      ),
    );
    if (mounted) _load();
  }

  void _openFullLeaderboard() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeaderboardScreen(entries: _leaderboard),
      ),
    );
  }

  // Staggered interval helper
  Animation<double> _stagger(double begin, double end) {
    return CurvedAnimation(
      parent: _staggerController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: _kBlue),
              )
            : _error != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kTextSecondary, fontSize: 16)),
            const SizedBox(height: 24),
            _PillButton(
              label: 'Retry',
              color: _kBlue,
              onTap: _load,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar: greeting + actions ──
          _FadeSlide(
            animation: _stagger(0.0, 0.25),
            child: _buildTopBar(),
          ),
          const SizedBox(height: 28),

          // ── Hero: decorative X O with title ──
          _FadeSlide(
            animation: _stagger(0.05, 0.3),
            child: _buildHeroSection(),
          ),
          const SizedBox(height: 28),

          // ── Stats card ──
          _FadeSlide(
            animation: _stagger(0.1, 0.4),
            child: _StatsCard(stats: _stats),
          ),
          const SizedBox(height: 20),

          // ── Compact Leaderboard (between stats & game modes) ──
          if (_leaderboard.isNotEmpty) ...[
            _FadeSlide(
              animation: _stagger(0.15, 0.45),
              child: _LeaderboardCard(
                entries: _leaderboard,
                onViewAll: () => _openFullLeaderboard(),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── Game Modes ──
          _FadeSlide(
            animation: _stagger(0.25, 0.55),
            child: const Text(
              'Choose your mode',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _kTextPrimary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          ...List.generate(_templates.length, (i) {
            return _FadeSlide(
              animation: _stagger(0.3 + i * 0.08, 0.6 + i * 0.08),
              child: _GameModeCard(
                template: _templates[i],
                onPlay: () => _playTemplate(_templates[i]),
              ),
            );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        // Avatar circle with initial
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kBlue, Color(0xFF6CB4EE)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(
            _username.isNotEmpty ? _username[0].toUpperCase() : '?',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hey, $_username',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _kTextPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const Text(
                'Ready to play?',
                style: TextStyle(fontSize: 13, color: _kTextSecondary),
              ),
            ],
          ),
        ),
        // Refresh
        _CircleIconBtn(
          icon: Icons.refresh_rounded,
          onTap: _load,
        ),
        const SizedBox(width: 8),
        // Logout
        _CircleIconBtn(
          icon: _loggingOut ? null : Icons.logout_rounded,
          loading: _loggingOut,
          onTap: _loggingOut ? null : _logout,
        ),
      ],
    );
  }

  Widget _buildHeroSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
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
      child: Column(
        children: [
          // Decorative X and O
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _DecoSymbol(symbol: 'X', color: _kBlue, size: 48),
              const SizedBox(width: 16),
              _DecoSymbol(symbol: 'O', color: _kCoral, size: 48),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'TIC TAC TOE',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: _kTextPrimary,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Challenge players around the world',
            style: TextStyle(fontSize: 13, color: _kTextSecondary),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Reusable widgets
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

/// Decorative X / O symbol
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

/// Pill-shaped button
class _PillButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PillButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(50),
      child: InkWell(
        borderRadius: BorderRadius.circular(50),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular icon button with subtle background
class _CircleIconBtn extends StatelessWidget {
  final IconData? icon;
  final VoidCallback? onTap;
  final bool loading;

  const _CircleIconBtn({this.icon, this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: loading
              ? const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _kBlue),
                  ),
                )
              : Icon(icon, size: 20, color: _kTextSecondary),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Stats Card
// ═══════════════════════════════════════════════════════════════

class _StatsCard extends StatelessWidget {
  final PlayerStats stats;

  const _StatsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final totalGames = stats.wins + stats.losses + stats.draws;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kBlue, Color(0xFF6CB4EE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _kBlue.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Score — hero number
          Text(
            '${stats.score}',
            style: const TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'YOUR SCORE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.7),
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 20),
          // Mini stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatPill(label: 'Won', value: stats.wins, color: const Color(0xFF4ADE80)),
              _StatPill(label: 'Lost', value: stats.losses, color: const Color(0xFFF87171)),
              _StatPill(label: 'Draw', value: stats.draws, color: const Color(0xFFFBBF24)),
              _StatPill(label: 'Played', value: totalGames, color: Colors.white),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatPill({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            '$value',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Game Mode Card
// ═══════════════════════════════════════════════════════════════

class _GameModeCard extends StatelessWidget {
  final GameTemplate template;
  final VoidCallback onPlay;

  const _GameModeCard({required this.template, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final isBlitz = template.variant == 'blitz';
    final accent = isBlitz ? _kCoral : _kBlue;
    final symbol = isBlitz ? 'O' : 'X';
    final subtitle = isBlitz
        ? '${template.turnSecs}s per turn'
        : 'No time limit';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onPlay,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                // Decorative symbol circle
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    symbol,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Title + description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _kTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 13, color: _kTextSecondary),
                      ),
                    ],
                  ),
                ),
                // Play pill button
                Material(
                  color: accent,
                  borderRadius: BorderRadius.circular(50),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(50),
                    onTap: onPlay,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                      child: Text(
                        'Play',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
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
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Leaderboard Card
// ═══════════════════════════════════════════════════════════════

class _LeaderboardCard extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  final VoidCallback? onViewAll;

  const _LeaderboardCard({required this.entries, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final top = entries.take(5).toList();

    return Container(
      width: double.infinity,
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
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with "View All" arrow
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.emoji_events_rounded,
                    size: 18, color: Color(0xFFD97706)),
              ),
              const SizedBox(width: 10),
              const Text(
                'Leaderboard',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _kTextPrimary,
                ),
              ),
              const Spacer(),
              if (onViewAll != null)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: onViewAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'View All',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _kBlue,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.arrow_forward_ios_rounded, size: 12, color: _kBlue),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Compact rows
          ...List.generate(top.length, (i) => _LeaderboardRow(entry: top[i])),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final LeaderboardEntry entry;

  const _LeaderboardRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final (medal, medalColor) = switch (entry.rank) {
      1 => ('1st', const Color(0xFFD97706)),
      2 => ('2nd', const Color(0xFF6B7280)),
      3 => ('3rd', const Color(0xFF92400E)),
      _ => ('${entry.rank}th', _kTextSecondary),
    };

    final isTop3 = entry.rank <= 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isTop3 ? medalColor.withValues(alpha: 0.06) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isTop3 ? medalColor.withValues(alpha: 0.15) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(7),
            ),
            alignment: Alignment.center,
            child: Text(
              '${entry.rank}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: isTop3 ? medalColor : _kTextSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Player name
          Expanded(
            child: Text(
              entry.username.isNotEmpty ? entry.username : 'Anonymous',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isTop3 ? FontWeight.w600 : FontWeight.w400,
                color: _kTextPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Score chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _kBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '${entry.score}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: _kBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
