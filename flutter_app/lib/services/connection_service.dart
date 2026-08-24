import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'monitoring_client.dart';

/// Persistent connection state for the mobile companion.
///
/// Wraps [MonitoringClient] and stores [backendUrl] / [bearerToken] in
/// [SharedPreferences] so the user doesn't have to re-pair every launch.
class ConnectionService extends ChangeNotifier {
  ConnectionService({required this.client});

  final MonitoringClient client;

  String? _backendUrl;
  String? _bearerToken;
  DateTime? _tokenExpiresAt;
  bool _initialised = false;

  // ── Getters ──────────────────────────────────────────────────────────────

  String? get backendUrl => _backendUrl;
  String? get bearerToken => _bearerToken;
  bool get isPaired => _bearerToken != null && _bearerToken!.isNotEmpty;
  bool get isExpired =>
      _tokenExpiresAt != null && DateTime.now().isAfter(_tokenExpiresAt!);
  bool get isInitialised => _initialised;

  Duration? get tokenTimeLeft {
    if (_tokenExpiresAt == null) return null;
    final diff = _tokenExpiresAt!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  static const _keyUrl = 'wg_backend_url';
  static const _keyToken = 'wg_bearer_token';
  static const _keyExpiry = 'wg_token_expiry_ms';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _backendUrl = prefs.getString(_keyUrl);
    final token = prefs.getString(_keyToken);
    final expiryMs = prefs.getInt(_keyExpiry);

    if (token != null && token.isNotEmpty) {
      _bearerToken = token;
      if (expiryMs != null) {
        _tokenExpiresAt = DateTime.fromMillisecondsSinceEpoch(expiryMs);
      }
    }
    _initialised = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    if (_backendUrl != null) {
      await prefs.setString(_keyUrl, _backendUrl!);
    } else {
      await prefs.remove(_keyUrl);
    }
    if (_bearerToken != null && _bearerToken!.isNotEmpty) {
      await prefs.setString(_keyToken, _bearerToken!);
    } else {
      await prefs.remove(_keyToken);
    }
    if (_tokenExpiresAt != null) {
      await prefs.setInt(
          _keyExpiry, _tokenExpiresAt!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_keyExpiry);
    }
  }

  // ── Connection ───────────────────────────────────────────────────────────

  /// Set the backend URL and optionally a manually-entered token.
  Future<void> connectTo(String url, {String? manualToken}) async {
    _backendUrl = url;
    if (manualToken != null && manualToken.isNotEmpty) {
      _bearerToken = manualToken;
      // Manual tokens — no known expiry; set 24h from now as a guess.
      _tokenExpiresAt = DateTime.now().add(const Duration(hours: 24));
    }
    await _save();
    _applyToClient();
    notifyListeners();
  }

  /// Complete the pairing handshake: exchange code for a bearer token.
  Future<void> completePairing(String code) async {
    final result = await client.exchangePairing(code);
    final token = result['access_token'] as String?;
    final expiresAt = result['expires_at'] as num?;
    if (token == null || token.isEmpty) {
      throw const FormatException('Pairing response missing access_token');
    }
    _bearerToken = token;
    _tokenExpiresAt = expiresAt != null
        ? DateTime.fromMillisecondsSinceEpoch((expiresAt * 1000).toInt())
        : DateTime.now().add(const Duration(hours: 24));
    await _save();
    _applyToClient();
    notifyListeners();
  }

  /// Revoke the companion token and clear stored credentials.
  Future<void> forgetDevice() async {
    final oldToken = _bearerToken;
    _bearerToken = null;
    _tokenExpiresAt = null;
    _backendUrl = null;
    client.token = null;
    client.disconnect();
    await _save();
    notifyListeners();

    // Best-effort remote revoke (fire-and-forget).
    if (oldToken != null && oldToken.isNotEmpty && _backendUrl != null) {
      try {
        client.token = oldToken;
        await client.forgetDevice();
      } catch (_) {
        // Backend may be unreachable — local credentials already cleared.
      }
      client.token = null;
    }
  }

  /// Reconnect using stored credentials.
  Future<bool> reconnect() async {
    if (_backendUrl == null) return false;
    _applyToClient();
    // Give the SSE loop a moment to establish.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return client.connectionState == BackendConnectionState.connected;
  }

  void _applyToClient() {
    client.configure(
      baseUrl: _backendUrl ?? 'http://127.0.0.1:8765',
      token: _bearerToken,
    );
  }

  /// Format the remaining token lifetime as a human string like "14h 22m".
  String get tokenExpiryFormatted {
    final left = tokenTimeLeft;
    if (left == null) return '—';
    final h = left.inHours;
    final m = left.inMinutes.remainder(60);
    final s = left.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}
