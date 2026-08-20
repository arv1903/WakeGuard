import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/monitoring_snapshot.dart';

enum BackendConnectionState { disconnected, connecting, connected, error }

// ─── Client-side EMA smoother ──────────────────────────────────────────────
// Smooths numeric fields that stutter (PERCLOS, blink rate, head pose) and
// debounces the status text so it doesn't flicker between rapid alert
// transitions. Raw data is untouched; only the display snapshot is smoothed.

class _SnapshotSmoother {
  double _attention = 0;
  double _perclos = 0;
  double _drowsy = 0;
  double _blinks = 0;
  double _pitch = 0;
  double _yaw = 0;
  double _roll = 0;
  int _smoothedSeverity = 0;
  String? _displayedStatus;
  bool _initialised = false;

  // Per-field alpha: higher = more responsive, lower = smoother.
  static const _aAttention = 0.35;
  static const _aPerclos   = 0.30;
  static const _aDrowsy    = 0.30;
  static const _aBlinks    = 0.20;
  static const _aPose      = 0.35;
  // Severity EMA — needs to cross hysteresis thresholds to change status.
  static const _aSeverity  = 0.25;

  double _ema(double prev, double raw, double alpha) =>
      alpha * raw + (1 - alpha) * prev;

  /// Apply EMA smoothing to a snapshot and return the display-ready version.
  MonitoringSnapshot smooth(MonitoringSnapshot raw) {
    if (!_initialised) {
      _attention = raw.attention;
      _perclos   = raw.perclos;
      _drowsy    = raw.emaDrowsy;
      _blinks    = raw.blinksPerMin;
      _pitch     = raw.pitch;
      _yaw       = raw.yaw;
      _roll      = raw.roll;
      _smoothedSeverity = raw.alertSeverity;
      _displayedStatus  = raw.status;
      _initialised = true;
      return raw;
    }

    _attention = _ema(_attention, raw.attention, _aAttention);
    _perclos   = _ema(_perclos,   raw.perclos,   _aPerclos);
    _drowsy    = _ema(_drowsy,    raw.emaDrowsy,  _aDrowsy);
    _blinks    = _ema(_blinks,    raw.blinksPerMin, _aBlinks);
    _pitch     = _ema(_pitch,     raw.pitch,     _aPose);
    _yaw       = _ema(_yaw,       raw.yaw,       _aPose);
    _roll      = _ema(_roll,      raw.roll,      _aPose);

    // Status hysteresis — smoothed severity must cross thresholds to change
    // the displayed text, preventing rapid flicker.
    _smoothedSeverity = _ema(_smoothedSeverity.toDouble(), raw.alertSeverity.toDouble(), _aSeverity).round();
    final newStatus = _statusFromSeverity(_smoothedSeverity, raw);
    if (newStatus != _displayedStatus) {
      // Only update if the new status has been stable for a few frames.
      _pendingCount++;
      if (_pendingCount >= 3) {
        _displayedStatus = newStatus;
        _pendingCount = 0;
      }
    } else {
      _pendingCount = 0;
    }

    return MonitoringSnapshot(
      schemaVersion: raw.schemaVersion,
      sequence:     raw.sequence,
      serverId:     raw.serverId,
      timestamp:    raw.timestamp,
      sessionId:    raw.sessionId,
      tripStartedAt: raw.tripStartedAt,
      tripActive:   raw.tripActive,
      attention:    _attention,
      perclos:      _perclos,
      emaDrowsy:    _drowsy,
      ear:          raw.ear,
      eyesClosed:   raw.eyesClosed,
      microsleep:   raw.microsleep,
      blinksPerMin: _blinks,
      pitch:        _pitch,
      yaw:          _yaw,
      roll:         _roll,
      poseValid:    raw.poseValid,
      faceFound:    raw.faceFound,
      faceLost:     raw.faceLost,
      faceLostProgress: raw.faceLostProgress,
      headDown:     raw.headDown,
      lookingAway:  raw.lookingAway,
      headTilt:     raw.headTilt,
      focused:      raw.focused,
      unfocused:    raw.unfocused,
      alert:        raw.alert,
      alertSeverity: raw.alertSeverity,
      fps:          raw.fps,
    );
  }

  int _pendingCount = 0;

  /// Map smoothed severity back to a status label, using the raw snapshot's
  /// boolean flags for non-severity states (focused, face-lost).
  String _statusFromSeverity(int sev, MonitoringSnapshot raw) {
    if (sev >= 4) return 'Critical';
    if (sev >= 3) return 'Drowsy';
    if (sev >= 2) return 'Distracted';
    if (raw.focused) return 'Focused';
    if (raw.unfocused) return 'Unfocused';
    if (raw.faceLost) return 'Face not detected';
    return 'Monitoring';
  }

  /// The debounced status label, updated only after the smoothed severity
  /// has been stable for several consecutive frames.
  String get displayedStatus => _displayedStatus ?? 'Monitoring';

  /// Reset all smoothing state (called on reconnect / new server).
  void reset() {
    _initialised = false;
    _pendingCount = 0;
  }
}

class MonitoringClient extends ChangeNotifier {
  MonitoringClient({required String baseUrl, this.token})
      : _baseUrl = _cleanBaseUrl(baseUrl) {
    _staleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_disposed) notifyListeners();
    });
  }

  String _baseUrl;
  String? token;
  final HttpClient _http = HttpClient();
  MonitoringSnapshot snapshot = MonitoringSnapshot.initial();
  BackendConnectionState connectionState = BackendConnectionState.disconnected;
  String? errorMessage;
  DateTime? lastUpdate;
  int _generation = 0;
  bool _disposed = false;
  Timer? _staleTimer;
  Future<void>? _mjpegTask;
  final ValueNotifier<Uint8List?> _latestFrameBytes = ValueNotifier<Uint8List?>(null);
  final _SnapshotSmoother _smoother = _SnapshotSmoother();

  String get baseUrl => _baseUrl;

  /// Latest JPEG frame from the persistent MJPEG stream, or null before the
  /// first frame arrives. Only the newest frame is retained, so a slow UI
  /// never falls behind the camera.
  ValueListenable<Uint8List?> get latestFrameBytes => _latestFrameBytes;

  bool get isStale => lastUpdate == null ||
      DateTime.now().difference(lastUpdate!).inSeconds > 3;

  /// Smoothed status label — debounced to prevent flicker.
  String get displayedStatus => _smoother.displayedStatus;

  static String _cleanBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'http://127.0.0.1:8765';
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  Map<String, String> _headers() => {
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  void configure({required String baseUrl, String? token}) {
    _baseUrl = _cleanBaseUrl(baseUrl);
    this.token = token?.trim().isEmpty == true ? null : token?.trim();
    snapshot = MonitoringSnapshot.initial();
    lastUpdate = null;
    _smoother.reset();
    connect();
  }

  void connect() {
    final generation = ++_generation;
    connectionState = BackendConnectionState.connecting;
    errorMessage = null;
    notifyListeners();
    unawaited(_runEventLoop(generation));
    _startMjpeg(generation);
  }

  void disconnect() {
    _generation++;
    connectionState = BackendConnectionState.disconnected;
    _latestFrameBytes.value = null;
    _smoother.reset();
    notifyListeners();
  }

  /// Maintains one persistent HTTP connection to the MJPEG endpoint and
  /// publishes the newest decoded JPEG frame. Reconnects with backoff on
  /// drops; the backend drops old frames itself, so the client can never
  /// block detection.
  void _startMjpeg(int generation) {
    _mjpegTask = _runMjpeg(generation);
  }

  Future<void> _runMjpeg(int generation) async {
    var delay = const Duration(milliseconds: 250);
    while (!_disposed && generation == _generation) {
      try {
        final request = await _http.getUrl(
          Uri.parse('$_baseUrl/api/v1/video.mjpg'),
        );
        _headers().forEach(request.headers.add);
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('Video stream returned ${response.statusCode}');
        }

        final contentType = response.headers.contentType?.toString() ?? '';
        final boundary = _mjpegBoundary(contentType);
        if (boundary == null) {
          throw const HttpException('Video stream is missing its MJPEG boundary');
        }
        final separator = utf8.encode('--$boundary');

        await for (final chunk in response) {
          if (generation != _generation || _disposed) return;
          _feedMjpegBytes(chunk, separator);
        }
        // Stream ended normally (server closed); treat it as a reconnect.
      } catch (error) {
        if (generation != _generation || _disposed) return;
        connectionState = BackendConnectionState.error;
        errorMessage = error.toString();
        notifyListeners();
        await Future<void>.delayed(delay);
        delay = Duration(
          milliseconds: (delay.inMilliseconds * 2).clamp(250, 5000).toInt(),
        );
        continue;
      }
      delay = const Duration(milliseconds: 250);
    }
  }

  static String? _mjpegBoundary(String contentType) {
    final lower = contentType.toLowerCase();
    final marker = 'boundary=';
    final index = lower.indexOf(marker);
    if (index < 0) return null;
    return contentType.substring(index + marker.length).trim();
  }

  final BytesBuilder _mjpegBuffer = BytesBuilder(copy: false);

  /// Splits the multipart stream into per-frame JPEG payloads. Frame bodies
  /// carry an explicit Content-Length, so partial frames are buffered and
  /// only complete frames are published.
  void _feedMjpegBytes(List<int> chunk, List<int> separator) {
    _mjpegBuffer.add(chunk);
    final bytes = _mjpegBuffer.toBytes();
    _mjpegBuffer.clear();

    final separatorBytes = separator;
    var cursor = 0;
    while (true) {
      final start = _indexOf(bytes, separatorBytes, cursor);
      if (start < 0) break;
      final headerEnd = _indexOf(bytes, _crlfCrlf, start + separatorBytes.length);
      if (headerEnd < 0) break;
      final headerText = utf8.decode(
        bytes.sublist(start + separatorBytes.length, headerEnd),
        allowMalformed: true,
      );
      final length = _contentLength(headerText);
      if (length == null) break;
      final bodyStart = headerEnd + 4;
      final bodyEnd = bodyStart + length;
      if (bodyEnd > bytes.length) break;
      _latestFrameBytes.value = Uint8List.fromList(
        bytes.sublist(bodyStart, bodyEnd),
      );
      cursor = bodyEnd;
    }
    if (cursor > 0 && cursor < bytes.length) {
      _mjpegBuffer.add(bytes.sublist(cursor));
    }
  }

  static final List<int> _crlfCrlf = utf8.encode('\r\n\r\n');

  static int? _contentLength(String headerText) {
    for (final line in headerText.split('\r\n')) {
      final lower = line.toLowerCase();
      if (lower.startsWith('content-length:')) {
        return int.tryParse(lower.substring('content-length:'.length).trim());
      }
    }
    return null;
  }

  static int _indexOf(List<int> haystack, List<int> needle, int start) {
    if (needle.isEmpty || haystack.length < needle.length) return -1;
    outer:
    for (var i = start; i <= haystack.length - needle.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  Future<void> _runEventLoop(int generation) async {
    var delay = const Duration(milliseconds: 250);
    while (!_disposed && generation == _generation) {
      try {
        final response = await _readOneEvent(snapshot.sequence);
        if (generation != _generation || _disposed) return;
        if (response != null) {
          _apply(response);
          delay = const Duration(milliseconds: 250);
        }
      } catch (error) {
        if (generation != _generation || _disposed) return;
        connectionState = BackendConnectionState.error;
        errorMessage = error.toString();
        notifyListeners();
        await Future<void>.delayed(delay);
        delay = Duration(
          milliseconds: (delay.inMilliseconds * 2).clamp(250, 5000).toInt(),
        );
      }
    }
  }

  Future<MonitoringSnapshot?> _readOneEvent(int after) async {
    final request = await _http.getUrl(
      Uri.parse('$_baseUrl/api/v1/events?after=$after'),
    );
    _headers().forEach(request.headers.add);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Event stream returned ${response.statusCode}');
    }

    connectionState = BackendConnectionState.connected;
    notifyListeners();
    String? dataLine;
    MonitoringSnapshot? result;
    await for (final line in response
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.startsWith('data: ')) {
        dataLine = line.substring(6);
      } else if (line.isEmpty && dataLine != null) {
        final event = jsonDecode(dataLine!) as Map<String, dynamic>;
        result = MonitoringSnapshot.fromJson(
          event['data'] as Map<String, dynamic>,
        );
        dataLine = null;
      }
    }
    return result;
  }

  void _apply(MonitoringSnapshot next) {
    final newServer = next.serverId.isNotEmpty &&
        next.serverId != snapshot.serverId;
    if (!newServer && next.sequence <= snapshot.sequence) return;
    if (newServer) _smoother.reset();
    snapshot = _smoother.smooth(next);
    lastUpdate = DateTime.now();
    connectionState = BackendConnectionState.connected;
    errorMessage = null;
    notifyListeners();
  }

  Future<Map<String, dynamic>> fetchPairing() async {
    final request = await _http.getUrl(Uri.parse('$_baseUrl/api/v1/pairing'));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Pairing code unavailable (${response.statusCode}): $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> exchangePairing(String code) async {
    final request = await _http.postUrl(
      Uri.parse('$_baseUrl/api/v1/pairing/exchange'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(<String, dynamic>{'code': code.trim()}));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Pairing failed (${response.statusCode}): $body');
    }
    final result = jsonDecode(body) as Map<String, dynamic>;
    final issuedToken = result['access_token'];
    if (issuedToken is! String || issuedToken.isEmpty) {
      throw const FormatException('Pairing response did not contain an access token');
    }
    token = issuedToken;
    snapshot = MonitoringSnapshot.initial();
    lastUpdate = null;
    connect();
    return result;
  }

  Future<Map<String, dynamic>> fetchCurrentSummary() async {
    final request = await _http.getUrl(
      Uri.parse('$_baseUrl/api/v1/sessions/current/summary'),
    );
    _headers().forEach(request.headers.add);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Summary returned ${response.statusCode}: $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<void> forgetDevice() async {
    final issuedToken = token;
    token = null;
    disconnect();
    if (issuedToken == null || issuedToken.isEmpty) return;

    try {
      final request = await _http.postUrl(
        Uri.parse('$_baseUrl/api/v1/pairing/revoke'),
      );
      request.headers.add('Authorization', 'Bearer $issuedToken');
      request.headers.contentType = ContentType.json;
      request.write('{}');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.transform(utf8.decoder).join();
        throw HttpException('Device revocation failed (${response.statusCode}): $body');
      }
    } finally {
      // Clear local credentials even if the backend is unreachable. The user
      // can pair again, while a failed remote revoke is surfaced to the UI.
      token = null;
      disconnect();
    }
  }

  Future<void> sendCommand(String path, [Map<String, dynamic>? payload]) async {
    final request = await _http.postUrl(Uri.parse('$_baseUrl$path'));
    request.headers.contentType = ContentType.json;
    _headers().forEach(request.headers.add);
    request.write(jsonEncode(payload ?? <String, dynamic>{}));
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.transform(utf8.decoder).join();
      throw HttpException('Command failed (${response.statusCode}): $body');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _staleTimer?.cancel();
    _latestFrameBytes.dispose();
    _http.close(force: true);
    super.dispose();
  }
}
