import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nakama/nakama.dart';

import '../core/nakama_client.dart';
import '../models/game_template.dart';
import 'game_screen.dart';

class MatchmakingScreen extends StatefulWidget {
  final GameTemplate template;

  const MatchmakingScreen({super.key, required this.template});

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen> {
  final _client = NakamaGameClient.instance;

  static const _matchmakingTimeout = Duration(seconds: 60);

  String? _ticket;
  StreamSubscription<MatchmakerMatched>? _matchmakerSub;
  Timer? _timeoutTimer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startMatchmaking();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _matchmakerSub?.cancel();
    // Best-effort cancel of matchmaker ticket to prevent ghost matches
    final t = _ticket;
    if (t != null) {
      _client.removeFromMatchmaker(t).catchError((_) {});
    }
    super.dispose();
  }

  Future<void> _startMatchmaking() async {
    setState(() { _error = null; });
    try {
      debugPrint('Matchmaking: template=${widget.template.name} id=${widget.template.id} variant=${widget.template.variant} turnSecs=${widget.template.turnSecs}');
      final ticket = await _client.addToMatchmaker(templateId: widget.template.id);
      setState(() { _ticket = ticket.ticket; });

      // Auto-cancel after timeout if no opponent found
      _timeoutTimer?.cancel();
      _timeoutTimer = Timer(_matchmakingTimeout, () {
        if (!mounted) return;
        _matchmakerSub?.cancel();
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
          MaterialPageRoute(builder: (_) => GameScreen(matchId: realMatchId)),
        );
      });
    } catch (e) {
      setState(() { _error = 'Matchmaking error: $e'; });
    }
  }

  Future<void> _cancel() async {
    _timeoutTimer?.cancel();
    final t = _ticket;
    if (t != null) {
      await _client.removeFromMatchmaker(t);
    }
    _matchmakerSub?.cancel();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.template.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_error != null) ...[
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 24),
                    FilledButton(onPressed: _startMatchmaking, child: const Text('Retry')),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _cancel, child: const Text('Back')),
                  ] else ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 32),
                    const Text(
                      'Finding an opponent...',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.template.description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 40),
                    OutlinedButton(
                      onPressed: _cancel,
                      child: const Text('Cancel'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
