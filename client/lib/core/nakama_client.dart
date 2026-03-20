import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:nakama/nakama.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'constants.dart';
import '../models/game_state.dart';
import '../models/game_template.dart';

/// Singleton wrapper around the Nakama SDK.
/// Handles device auth, session lifecycle, RPCs, match WebSocket,
/// and automatic reconnection with exponential backoff.
class NakamaGameClient {
  NakamaGameClient._();
  static final NakamaGameClient instance = NakamaGameClient._();

  // SharedPreferences keys
  static const _keyDeviceId = 'device_id';
  static const _keyUsername = 'username';
  static const _keySessionToken = 'session_token';
  static const _keyRefreshToken = 'refresh_token';

  late final NakamaBaseClient _client;
  Session? _session;
  NakamaWebsocketClient? _socket;

  Session? get session => _session;
  bool get isAuthenticated => _session != null;

  // --- Reconnection state ---
  bool _reconnecting = false;
  bool _intentionalDisconnect = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  static const _maxReconnectAttempt = 6; // max ~32s backoff
  static const _baseReconnectDelay = Duration(seconds: 1);

  // Stream exposed to the UI for incoming match messages
  final StreamController<MatchData> _matchDataController =
      StreamController.broadcast();
  Stream<MatchData> get matchDataStream => _matchDataController.stream;

  // Cache last state/result per matchId so late subscribers don't miss the first broadcast
  final Map<String, MatchData> _cachedMatchData = {};
  MatchData? getCachedState(String matchId) => _cachedMatchData[matchId];

  // Stream exposed to the UI when matchmaker finds a game
  final StreamController<MatchmakerMatched> _matchmakerMatchedController =
      StreamController.broadcast();
  Stream<MatchmakerMatched> get onMatchmakerMatched =>
      _matchmakerMatchedController.stream;

  // Stream notifying UI of connection status changes (true = connected)
  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();
  Stream<bool> get onConnectionStatusChanged =>
      _connectionStatusController.stream;

  /// Call once at app startup.
  void init() {
    _client = getNakamaClient(
      host: AppConstants.nakamaHost,
      ssl: AppConstants.nakamaSSL,
      serverKey: AppConstants.nakamaServerKey,
      httpPort: AppConstants.nakamaHttpPort,
      grpcPort: 7349,
    );
  }

  // ---------------------------------------------------------------------------
  // Device ID management
  // ---------------------------------------------------------------------------

  /// Returns the persisted device ID, generating one on first launch.
  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_keyDeviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_keyDeviceId, id);
    }
    return id;
  }

  // ---------------------------------------------------------------------------
  // Authentication — device-based
  // ---------------------------------------------------------------------------

  /// Authenticate with the device ID. Creates account on first use.
  /// This is the primary auth method — no passwords, no emails.
  Future<Session> authenticateDevice(String deviceId) async {
    _session = await _client.authenticateDevice(
      deviceId: deviceId,
      create: true,
    );
    await _persistSession();
    return _session!;
  }

  /// Try to restore a session from persisted tokens.
  /// Returns true if session was restored (valid or refreshed).
  /// Returns false if re-authentication is needed.
  Future<bool> tryRestoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keySessionToken);
    final refreshToken = prefs.getString(_keyRefreshToken);

    if (token == null || token.isEmpty || refreshToken == null || refreshToken.isEmpty) {
      return false;
    }

    // Restore session object from stored tokens
    final restored = Session.restore(token: token, refreshToken: refreshToken);
    if (restored == null) {
      await _clearSession();
      return false;
    }

    // Check if access token is still valid
    if (!restored.isExpired) {
      _session = restored;
      return true;
    }

    // Access token expired — try refreshing
    if (!restored.isRefreshExpired) {
      try {
        _session = await _client.sessionRefresh(session: restored);
        await _persistSession();
        return true;
      } catch (_) {
        // Refresh failed — need full re-auth
        await _clearSession();
        return false;
      }
    }

    // Both tokens expired
    await _clearSession();
    return false;
  }

  /// Ensure the session is valid before making API calls.
  /// Refreshes if expired. Throws if both tokens are gone.
  Future<void> ensureValidSession() async {
    if (_session == null) {
      throw StateError('Not authenticated');
    }
    if (!_session!.isExpired) return;

    if (_session!.isRefreshExpired) {
      // Both expired — try re-auth with device ID
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString(_keyDeviceId);
      if (deviceId == null || deviceId.isEmpty) {
        throw StateError('Session expired and no device ID available');
      }
      await authenticateDevice(deviceId);
      return;
    }

    // Refresh the session
    try {
      _session = await _client.sessionRefresh(session: _session!);
      await _persistSession();
    } catch (_) {
      await _clearSession();
      throw StateError('Session refresh failed — re-authentication required');
    }
  }

  /// Save session tokens to SharedPreferences.
  Future<void> _persistSession() async {
    if (_session == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySessionToken, _session!.token);
    if (_session!.refreshToken != null) {
      await prefs.setString(_keyRefreshToken, _session!.refreshToken!);
    } else {
      await prefs.remove(_keyRefreshToken);
    }
  }

  /// Clear all stored session data.
  Future<void> _clearSession() async {
    _session = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySessionToken);
    await prefs.remove(_keyRefreshToken);
  }

  /// Save the username to SharedPreferences.
  Future<void> persistUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, username);
  }

  /// Read the saved username from SharedPreferences.
  Future<String?> getSavedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUsername);
  }

  /// Check if this is a returning user (has device ID stored).
  Future<bool> hasStoredCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDeviceId) != null &&
           prefs.getString(_keyUsername) != null;
  }

  // ---------------------------------------------------------------------------
  // Logout
  // ---------------------------------------------------------------------------

  /// Logout: invalidate session server-side, clear local state, close socket.
  /// Keeps device ID and username so the user can re-login seamlessly.
  Future<void> logout() async {
    _intentionalDisconnect = true;
    _cancelReconnect();
    if (_session != null) {
      try {
        await _client.sessionLogout(session: _session!);
      } catch (_) {
        // Best-effort — server may be unreachable
      }
    }
    await _socket?.close();
    _socket = null;
    await _clearSession();
  }

  /// Full logout: releases username on the server so other accounts can
  /// claim it, then clears local session + username. Keeps device ID.
  Future<void> fullLogout() async {
    // Release the username on the server BEFORE invalidating the session
    if (_session != null) {
      try {
        await ensureValidSession();
        await _client.rpc(
          session: _session!,
          id: 'release_username',
          payload: '',
        );
      } catch (_) {
        // Best-effort — server may be unreachable
      }
    }
    await logout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsername);
  }

  // ---------------------------------------------------------------------------
  // WebSocket
  // ---------------------------------------------------------------------------

  /// Open the persistent WebSocket connection to Nakama.
  /// Sets up automatic reconnection with exponential backoff on disconnect.
  Future<void> connectSocket() async {
    if (_session == null) throw StateError('Authenticate before connecting socket');

    await ensureValidSession();

    // Close any existing socket before creating a new one.
    // close() also triggers _clients.clear() in the nakama library,
    // so the next init() will create a fresh WebSocket connection.
    _cancelReconnect();
    try { await _socket?.close(); } catch (_) {}
    _socket = null;
    _intentionalDisconnect = false;

    _socket = NakamaWebsocketClient.init(
      host: AppConstants.nakamaHost,
      ssl: AppConstants.nakamaSSL,
      port: AppConstants.nakamaHttpPort,
      token: _session!.token,
      onDone: () {
        debugPrint('WebSocket closed (intentional=$_intentionalDisconnect)');
        _connectionStatusController.add(false);
        if (!_intentionalDisconnect) {
          _scheduleReconnect();
        }
      },
      onError: (error) {
        debugPrint('WebSocket error: $error');
        _connectionStatusController.add(false);
        if (!_intentionalDisconnect) {
          _scheduleReconnect();
        }
      },
    );

    _socket!.onMatchData.listen((data) {
      // Cache state and result messages so GameScreen can replay on late subscribe
      if (data.opCode == AppConstants.opCodeState ||
          data.opCode == AppConstants.opCodeResult) {
        _cachedMatchData[data.matchId] = data;
      }
      _matchDataController.add(data);
    });
    _socket!.onMatchmakerMatched.listen(_matchmakerMatchedController.add);

    _reconnectAttempt = 0;
    _connectionStatusController.add(true);
  }

  /// Schedule a reconnection attempt with exponential backoff.
  void _scheduleReconnect() {
    if (_reconnecting || _intentionalDisconnect) return;
    if (_reconnectAttempt >= _maxReconnectAttempt) {
      debugPrint('Max reconnection attempts reached');
      return;
    }

    final delay = _baseReconnectDelay * pow(2, _reconnectAttempt);
    debugPrint('Scheduling reconnect attempt ${_reconnectAttempt + 1} in ${delay.inSeconds}s');

    _reconnectTimer = Timer(delay, () async {
      if (_intentionalDisconnect) return;
      _reconnecting = true;
      try {
        await ensureValidSession();
        await connectSocket();
        debugPrint('Reconnected successfully');
        _reconnectAttempt = 0;
      } catch (e) {
        debugPrint('Reconnect attempt failed: $e');
        _reconnectAttempt++;
        _reconnecting = false;
        _scheduleReconnect();
      } finally {
        _reconnecting = false;
      }
    });
  }

  /// Cancel any pending reconnection timer.
  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnecting = false;
  }

  // ---------------------------------------------------------------------------
  // RPCs
  // ---------------------------------------------------------------------------

  /// RPC: create a new match, returns match ID.
  Future<String> createMatch() async {
    await ensureValidSession();
    final payload = await _client.rpc(
      session: _session!,
      id: 'create_match',
      payload: '',
    );
    final json = jsonDecode(payload!) as Map<String, dynamic>;
    return json['match_id'] as String;
  }

  /// RPC: list open matches waiting for a second player.
  Future<List<String>> listMatches() async {
    await ensureValidSession();
    final payload = await _client.rpc(
      session: _session!,
      id: 'list_matches',
      payload: '',
    );
    final json = jsonDecode(payload!) as Map<String, dynamic>;
    final matches = json['matches'] as List<dynamic>;
    return matches
        .map((m) => (m as Map<String, dynamic>)['match_id'] as String)
        .toList();
  }

  /// Join an authoritative match via WebSocket.
  Future<void> joinMatch(String matchId) async {
    await _socket!.joinMatch(matchId);
  }

  /// Join a match using a matchmaker token. Returns the real match ID.
  Future<String> joinMatchByToken(String token) async {
    final match = await _socket!.joinMatch('', token: token);
    return match.matchId;
  }

  /// RPC: list available game templates.
  Future<List<GameTemplate>> listTemplates() async {
    await ensureValidSession();
    final payload = await _client.rpc(
      session: _session!,
      id: 'list_templates',
      payload: '',
    );
    final json = jsonDecode(payload!) as Map<String, dynamic>;
    final list = json['templates'] as List<dynamic>;
    return list
        .map((t) => GameTemplate.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  /// RPC: set the player's display name (nickname).
  Future<void> updateUsername(String username) async {
    await ensureValidSession();
    await _client.rpc(
      session: _session!,
      id: 'update_username',
      payload: jsonEncode({'username': username}),
    );
  }

  /// Enter the matchmaker queue scoped to a template ID (integer).
  /// Players only match with others who picked the same template.
  /// Returns a ticket for cancellation.
  Future<MatchmakerTicket> addToMatchmaker({int templateId = 1}) async {
    final idStr = templateId.toString();
    return _socket!.addMatchmaker(
      minCount: 2,
      maxCount: 2,
      query: '+properties.templateId:$idStr',
      stringProperties: {'templateId': idStr},
    );
  }

  /// Remove from matchmaker queue (cancel Quick Play).
  Future<void> removeFromMatchmaker(String ticket) async {
    await _socket!.removeMatchmaker(ticket);
  }

  /// RPC: get the caller's player stats (wins/losses/draws/score).
  Future<PlayerStats> getPlayerStats() async {
    await ensureValidSession();
    final payload = await _client.rpc(
      session: _session!,
      id: 'player_stats',
      payload: '',
    );
    final json = jsonDecode(payload!) as Map<String, dynamic>;
    return PlayerStats.fromJson(json);
  }

  /// RPC: get the global leaderboard (top 20).
  Future<List<LeaderboardEntry>> getLeaderboard() async {
    await ensureValidSession();
    final payload = await _client.rpc(
      session: _session!,
      id: 'get_leaderboard',
      payload: '',
    );
    final json = jsonDecode(payload!) as Map<String, dynamic>;
    final records = json['records'] as List<dynamic>? ?? [];
    return records
        .map((r) => LeaderboardEntry.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Send a move (OpCode 1) with position 0-8.
  void sendMove(String matchId, int position) {
    final payload = jsonEncode({'position': position});
    _socket!.sendMatchData(
      matchId: matchId,
      opCode: AppConstants.opCodeMove,
      data: utf8.encode(payload),
    );
  }

  Future<void> dispose() async {
    _intentionalDisconnect = true;
    _cancelReconnect();
    await _socket?.close();
    await _matchDataController.close();
    await _matchmakerMatchedController.close();
    await _connectionStatusController.close();
  }
}
