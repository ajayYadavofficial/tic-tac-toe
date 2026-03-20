import 'dart:async';

import 'package:flutter/material.dart';

import 'core/nakama_client.dart';
import 'screens/lobby_screen.dart';
import 'screens/nickname_screen.dart';

void main() {
  NakamaGameClient.instance.init();
  runApp(const TicTacToeApp());
}

class TicTacToeApp extends StatelessWidget {
  const TicTacToeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tic-Tac-Toe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const _Splash(),
    );
  }
}

/// Splash: tries to restore session from stored tokens, otherwise NicknameScreen.
///
/// Flow:
///   1. Try restoring session from persisted tokens (fast, no network if valid)
///   2. If tokens expired but refresh works → refreshed session, go to Lobby
///   3. If refresh fails → re-authenticate with stored device ID
///   4. If no device ID at all → first launch, go to NicknameScreen
class _Splash extends StatefulWidget {
  const _Splash();

  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> {
  static const _bootTimeout = Duration(seconds: 15);
  bool _booting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // Guard against double invocation (hot reload, parent rebuild)
    if (_booting) return;
    _booting = true;
    setState(() { _error = null; });

    try {
      await _doBoot().timeout(_bootTimeout);
    } on TimeoutException {
      debugPrint('Splash boot timed out');
      if (mounted) {
        setState(() { _error = 'Connection timed out. Check your network.'; _booting = false; });
      }
    } catch (e) {
      debugPrint('Splash boot error: $e');
      if (mounted) {
        setState(() { _error = 'Failed to connect. Please try again.'; _booting = false; });
      }
    }
  }

  Future<void> _doBoot() async {
    final client = NakamaGameClient.instance;

    // Step 1: Must have both device ID and username to skip nickname screen
    final hasCredentials = await client.hasStoredCredentials();
    if (!hasCredentials) {
      _goToNickname();
      return;
    }

    final savedUsername = await client.getSavedUsername();

    // Step 2: Try restoring the session from stored tokens
    final restored = await client.tryRestoreSession();
    if (restored) {
      try {
        await client.connectSocket();
        // Re-apply the stored username so the server has the correct name
        if (savedUsername != null && savedUsername.isNotEmpty) {
          try {
            await client.updateUsername(savedUsername);
          } catch (e) {
            debugPrint('Username restore failed: $e — proceeding with existing server name');
          }
        }
        _goToLobby();
        return;
      } catch (e) {
        debugPrint('Socket connect after restore failed: $e');
        // Token may be server-invalidated (logout). Fall through to re-auth.
      }
    }

    // Step 3: Tokens gone, expired, or server-invalidated — fresh auth with device ID
    final deviceId = await client.getOrCreateDeviceId();
    await client.authenticateDevice(deviceId);
    await client.connectSocket();

    // Only go to lobby if we still have a username (not logged out)
    if (savedUsername != null && savedUsername.isNotEmpty) {
      try {
        await client.updateUsername(savedUsername);
      } catch (e) {
        debugPrint('Username restore after re-auth failed: $e — proceeding with existing server name');
      }
      _goToLobby();
    } else {
      _goToNickname();
    }
  }

  void _goToLobby() {
    if (!mounted) return;
    _booting = false;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LobbyScreen()),
    );
  }

  void _goToNickname() {
    if (!mounted) return;
    _booting = false;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const NicknameScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, color: Colors.red),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      onPressed: _boot,
                    ),
                  ],
                ),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
