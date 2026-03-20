import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:nakama/nakama.dart';

import '../core/nakama_client.dart';
import 'game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _client = NakamaGameClient.instance;

  bool _loading = false;
  bool _searching = false;
  String? _error;
  List<String> _openMatches = [];
  bool _authenticated = false;
  String? _matchmakerTicket;
  StreamSubscription<MatchmakerMatched>? _matchmakerSub;

  @override
  void initState() {
    super.initState();
    _authenticate();
  }

  @override
  void dispose() {
    _matchmakerSub?.cancel();
    super.dispose();
  }

  Future<void> _authenticate() async {
    setState(() { _loading = true; _error = null; });
    try {
      final deviceId = 'device-${Random().nextInt(999999)}';
      await _client.authenticateDevice(deviceId);
      await _client.connectSocket();
      setState(() { _authenticated = true; });
      await _refreshMatches();
    } catch (e) {
      setState(() { _error = 'Connection failed: $e'; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _refreshMatches() async {
    final matches = await _client.listMatches();
    setState(() { _openMatches = matches; });
  }

  Future<void> _createMatch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final matchId = await _client.createMatch();
      await _client.joinMatch(matchId);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => GameScreen(matchId: matchId),
      ));
    } catch (e) {
      setState(() { _error = 'Failed to create match: $e'; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _joinMatch(String matchId) async {
    setState(() { _loading = true; _error = null; });
    try {
      await _client.joinMatch(matchId);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => GameScreen(matchId: matchId),
      ));
    } catch (e) {
      setState(() { _error = 'Failed to join match: $e'; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _quickPlay() async {
    setState(() { _searching = true; _error = null; });
    try {
      final ticket = await _client.addToMatchmaker();
      setState(() { _matchmakerTicket = ticket.ticket; });

      _matchmakerSub?.cancel();
      _matchmakerSub = _client.onMatchmakerMatched.listen((matched) async {
        if (!mounted) return;
        setState(() { _searching = false; _matchmakerTicket = null; });
        _matchmakerSub?.cancel();

        // Our OnMatchmakerMatched returns a matchId directly (not a token).
        // Prefer matchId; fall back to token if present.
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
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => GameScreen(matchId: realMatchId),
        ));
      });
    } catch (e) {
      setState(() { _searching = false; _error = 'Matchmaking failed: $e'; });
    }
  }

  Future<void> _cancelQuickPlay() async {
    final ticket = _matchmakerTicket;
    if (ticket != null) {
      await _client.removeFromMatchmaker(ticket);
    }
    _matchmakerSub?.cancel();
    setState(() { _searching = false; _matchmakerTicket = null; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tic-Tac-Toe'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_authenticated && !_loading)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh matches',
              onPressed: _refreshMatches,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Multiplayer\nTic-Tac-Toe',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 48),

                if (_loading)
                  const Center(child: CircularProgressIndicator()),

                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                ],

                if (_authenticated && !_loading) ...[
                  // Quick Play (matchmaker)
                  if (_searching) ...[
                    const Center(
                      child: Column(children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Finding an opponent...'),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _cancelQuickPlay,
                      child: const Text('Cancel'),
                    ),
                  ] else ...[
                    FilledButton.icon(
                      icon: const Icon(Icons.bolt),
                      label: const Text('Quick Play'),
                      onPressed: _quickPlay,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Create Private Match'),
                      onPressed: _createMatch,
                    ),
                  ],

                  const SizedBox(height: 32),

                  if (_openMatches.isNotEmpty) ...[
                    const Text(
                      'Open Matches',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    ..._openMatches.map((id) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.sports_esports),
                        title: Text(
                          id.split('.').first,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        ),
                        trailing: FilledButton(
                          onPressed: () => _joinMatch(id),
                          child: const Text('Join'),
                        ),
                      ),
                    )),
                  ] else if (!_searching)
                    const Text(
                      'No open matches. Use Quick Play or create one!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
