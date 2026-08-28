import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages Supabase Auth state for the Flutter companion app.
///
/// Stores JWT + refresh token in [SharedPreferences] so the user doesn't
/// have to re-login every launch.
class AuthService extends ChangeNotifier {
  String? _jwt;
  String? _refreshToken;
  String? _userId;
  String? _email;
  bool _initialised = false;

  // ── Getters ──────────────────────────────────────────────────────────

  String? get jwt => _jwt;
  String? get userId => _userId;
  String? get email => _email;
  bool get isInitialised => _initialised;
  bool get isLoggedIn => _jwt != null && _jwt!.isNotEmpty;

  // ── Persistence ──────────────────────────────────────────────────────

  static const _keyJwt = 'wg_auth_jwt';
  static const _keyRefresh = 'wg_auth_refresh';
  static const _keyUserId = 'wg_auth_user_id';
  static const _keyEmail = 'wg_auth_email';

  /// Restore saved session from SharedPreferences.
  Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    _jwt = prefs.getString(_keyJwt);
    _refreshToken = prefs.getString(_keyRefresh);
    _userId = prefs.getString(_keyUserId);
    _email = prefs.getString(_keyEmail);
    _initialised = true;
    notifyListeners();
    return isLoggedIn;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    if (_jwt != null && _jwt!.isNotEmpty) {
      await prefs.setString(_keyJwt, _jwt!);
    } else {
      await prefs.remove(_keyJwt);
    }
    if (_refreshToken != null && _refreshToken!.isNotEmpty) {
      await prefs.setString(_keyRefresh, _refreshToken!);
    } else {
      await prefs.remove(_keyRefresh);
    }
    if (_userId != null) {
      await prefs.setString(_keyUserId, _userId!);
    } else {
      await prefs.remove(_keyUserId);
    }
    if (_email != null) {
      await prefs.setString(_keyEmail, _email!);
    } else {
      await prefs.remove(_keyEmail);
    }
  }

  // ── Auth actions ─────────────────────────────────────────────────────

  /// Register a new account via the backend's auth endpoint.
  Future<void> register(
    String email,
    String password, {
    String displayName = '',
    required String backendUrl,
  }) async {
    final body = utf8.encode(jsonEncode({
      'email': email,
      'password': password,
      'display_name': displayName,
    }));

    final request = await HttpClient().postUrl(
      Uri.parse('$backendUrl/api/v1/auth/register'),
    );
    request.headers.contentType = ContentType.json;
    request.headers.contentLength = body.length;
    request.add(body);

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      final error = jsonDecode(responseBody);
      throw Exception(error['error'] ?? 'Registration failed');
    }

    final result = jsonDecode(responseBody) as Map<String, dynamic>;
    _applyToken(result, email);
  }

  /// Sign in with email/password via the backend's auth endpoint.
  Future<void> login(
    String email,
    String password, {
    required String backendUrl,
  }) async {
    final body = utf8.encode(jsonEncode({
      'email': email,
      'password': password,
    }));

    final request = await HttpClient().postUrl(
      Uri.parse('$backendUrl/api/v1/auth/login'),
    );
    request.headers.contentType = ContentType.json;
    request.headers.contentLength = body.length;
    request.add(body);

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      final error = jsonDecode(responseBody);
      throw Exception(error['error'] ?? 'Login failed');
    }

    final result = jsonDecode(responseBody) as Map<String, dynamic>;
    _applyToken(result, email);
  }

  void _applyToken(Map<String, dynamic> result, String email) {
    _jwt = result['access_token'] as String?;
    _refreshToken = result['refresh_token'] as String?;
    _userId = result['user_id'] as String?;
    _email = email;
    _save();
    notifyListeners();
  }

  /// Clear all stored credentials.
  Future<void> logout() async {
    _jwt = null;
    _refreshToken = null;
    _userId = null;
    _email = null;
    await _save();
    notifyListeners();
  }
}
