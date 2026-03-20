import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/nakama_client.dart';
import '../core/web_lifecycle_stub.dart'
    if (dart.library.js_interop) '../core/web_lifecycle_web.dart';
import '../models/game_state.dart';
import '../models/game_template.dart';
import 'matchmaking_screen.dart';
import 'nickname_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> with WidgetsBindingObserver {
  final _client = NakamaGameClient.instance;

  List<GameTemplate> _templates = [];
  String _username = '';
  PlayerStats _stats = const PlayerStats();
  List<LeaderboardEntry> _leaderboard = [];
  bool _loading = true;
  bool _loggingOut = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _registerBrowserCloseHandler();
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// On web, register beforeunload to logout when the browser tab closes.
  void _registerBrowserCloseHandler() {
    setupWebBeforeUnload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On mobile: log out when app is detached (killed)
    if (state == AppLifecycleState.detached) {
      _client.logout();
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
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
    } catch (e) {
      if (!mounted) return;
      final errMsg = e.toString().toLowerCase();
      // Auth token invalid/expired — session is stale, go back to login
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
      setState(() { _error = 'Failed to load lobby. Tap retry.'; _loading = false; });
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
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
    } catch (_) {
      // Best-effort
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lobby'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _load,
            ),
          IconButton(
            icon: _loggingOut
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _loggingOut ? null : _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_error!, style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _load, child: const Text('Retry')),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_username.isNotEmpty) ...[
                          Text(
                            'Welcome, $_username!',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Pick a game mode to find an opponent.',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          _StatsCard(stats: _stats),
                          const SizedBox(height: 16),
                          if (_leaderboard.isNotEmpty)
                            _LeaderboardCard(entries: _leaderboard),
                          const SizedBox(height: 24),
                        ],
                        const Text(
                          'Game Modes',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 12),
                        ..._templates.map((t) => _TemplateCard(
                              template: t,
                              onPlay: () => _playTemplate(t),
                            )),
                      ],
                    )),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final GameTemplate template;
  final VoidCallback onPlay;

  const _TemplateCard({required this.template, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final isBlitz = template.variant == 'blitz';
    final icon = isBlitz ? Icons.bolt : Icons.grid_3x3;
    final iconColor = isBlitz
        ? Colors.orange
        : Theme.of(context).colorScheme.primary;
    final bgColor = isBlitz
        ? Colors.orange.withValues(alpha: 0.15)
        : Theme.of(context).colorScheme.primaryContainer;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    template.description,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: onPlay,
              child: const Text('Play'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final PlayerStats stats;

  const _StatsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatItem(label: 'Wins', value: '${stats.wins}', color: Colors.green),
            _StatItem(label: 'Losses', value: '${stats.losses}', color: Colors.red),
            _StatItem(label: 'Draws', value: '${stats.draws}', color: Colors.orange),
            _StatItem(label: 'Score', value: '${stats.score}', color: Theme.of(context).colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatItem({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

class _LeaderboardCard extends StatelessWidget {
  final List<LeaderboardEntry> entries;

  const _LeaderboardCard({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.leaderboard, size: 20, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                const Text(
                  'Leaderboard',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...entries.take(5).map((e) => _LeaderboardRow(entry: e)),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final LeaderboardEntry entry;

  const _LeaderboardRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final rankColor = switch (entry.rank) {
      1 => Colors.amber.shade700,
      2 => Colors.grey.shade500,
      3 => Colors.brown.shade400,
      _ => Colors.transparent,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '#${entry.rank}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: rankColor != Colors.transparent ? rankColor : null,
              ),
            ),
          ),
          Expanded(
            child: Text(
              entry.username.isNotEmpty ? entry.username : 'Anonymous',
              style: const TextStyle(fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${entry.score}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
