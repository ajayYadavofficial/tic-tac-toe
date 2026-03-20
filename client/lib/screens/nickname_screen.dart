import 'package:flutter/material.dart';

import '../core/nakama_client.dart';
import 'lobby_screen.dart';

class NicknameScreen extends StatefulWidget {
  const NicknameScreen({super.key});

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  final _usernameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _initializing = true;
  String? _error;
  String? _previousUsername;

  @override
  void initState() {
    super.initState();
    _loadPreviousUsername();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  /// Check if there's a previously used username and pre-fill it.
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
  }

  Future<void> _confirm() async {
    if (!_formKey.currentState!.validate()) return;

    final username = _usernameCtrl.text.trim();

    setState(() { _loading = true; _error = null; });

    try {
      final client = NakamaGameClient.instance;

      // 1. Generate a unique device ID for this installation
      final deviceId = await client.getOrCreateDeviceId();

      // 2. Authenticate with Nakama using device ID (creates account if new)
      await client.authenticateDevice(deviceId);

      // 3. Connect WebSocket
      await client.connectSocket();

      // 4. Set display name on the server
      try {
        await client.updateUsername(username);
      } catch (e) {
        final errMsg = e.toString().toLowerCase();
        if (errMsg.contains('taken') || errMsg.contains('in use') || errMsg.contains('already')) {
          setState(() {
            _error = 'Username "$username" is already taken. Try a different one.';
            _loading = false;
          });
          return;
        }
        rethrow;
      }

      // 5. Persist username locally
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
          _error = 'Cannot reach the server. Check your connection and try again.';
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
    final isReturning = _previousUsername != null && _previousUsername!.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: _initializing
                  ? const Center(child: CircularProgressIndicator())
                  : Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            isReturning
                                ? 'Welcome back!'
                                : 'Welcome to Tic-Tac-Toe',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isReturning
                                ? 'Continue as ${_previousUsername!} or pick a new username.'
                                : 'Pick a username to get started.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 32),
                          TextFormField(
                            controller: _usernameCtrl,
                            autofocus: true,
                            maxLength: 20,
                            textCapitalization: TextCapitalization.none,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              border: OutlineInputBorder(),
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
                          if (_error != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _error!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13),
                            ),
                          ],
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _loading ? null : _confirm,
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Text(isReturning
                                    ? "Let's Play"
                                    : "Get Started"),
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
}
