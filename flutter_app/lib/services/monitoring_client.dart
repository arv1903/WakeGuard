import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/monitoring_snapshot.dart';

enum BackendConnectionState { disconnected, connecting, connected, error }

// ─── Client-side severity smoother ────────────────────────────────────────
// The backend already applies EMA to all numeric telemetry fields. This
// class only debounces the alert severity / status label to prevent rapid
// flicker in the UI without adding extra lag to the underlying metrics.

class _SnapshotSmoother {
  int _smoothedSeverity = 0;
  String? _displayedStatus;
  bool _initialised = false;

  // Severity EMA — needs to cross hysteresis thresholds to change status.
  static const _aSeverity = 0.35;

  double _ema(double prev, double raw, double alpha) =>
      alpha * raw + (1 - alpha) * prev;

  /// Debounce alert severity and return display-ready snapshot.
  /// All numeric metrics are passed through directly from [raw].
  MonitoringSnapshot smooth(MonitoringSnapshot raw) {
    if (!_initialised) {
      _smoothedSeverity = raw.alertSeverity;
      _displayedStatus = raw.status;
      _initialised = true;
      return raw;
    }

    // Backend already applies EMA to these metrics — pass through directly
    // to avoid double-smoothing which adds artificial lag.
    // Only severity gets a thin hysteresis layer here to prevent status flicker.

    // Status hysteresis — smoothed severity must cross thresholds to change
    // the displayed text, preventing rapid flicker while alerting immediately
    // on critical events.
    _smoothedSeverity = raw.alertSeverity >= 3
        ? raw.alertSeverity
        : _ema(_smoothedSeverity.toDouble(), raw.alertSeverity.toDouble(),
                _aSeverity)
            .round();
    final newStatus = _statusFromSeverity(
      raw.alertSeverity >= 3 ? raw.alertSeverity : _smoothedSeverity,
      raw,
    );
    if (newStatus != _displayedStatus) {
      if (raw.alertSeverity >= 3 || _smoothedSeverity >= 3) {
        _displayedStatus = newStatus;
        _pendingCount = 0;
      } else {
        _pendingCount++;
        if (_pendingCount >= 2) {
          _displayedStatus = newStatus;
          _pendingCount = 0;
        }
      }
    } else {
      _pendingCount = 0;
    }

    return MonitoringSnapshot(
      schemaVersion: raw.schemaVersion,
      sequence: raw.sequence,
      serverId: raw.serverId,
      timestamp: raw.timestamp,
      sessionId: raw.sessionId,
      tripStartedAt: raw.tripStartedAt,
      tripActive: raw.tripActive,
      attention: raw.attention,
      perclos: raw.perclos,
      emaDrowsy: raw.emaDrowsy,
      ear: raw.ear,
      eyesClosed: raw.eyesClosed,
      microsleep: raw.microsleep,
      blinksPerMin: raw.blinksPerMin,
      pitch: raw.pitch,
      yaw: raw.yaw,
      roll: raw.roll,
      poseValid: raw.poseValid,
      faceFound: raw.faceFound,
      faceLost: raw.faceLost,
      faceLostProgress: raw.faceLostProgress,
      headDown: raw.headDown,
      lookingAway: raw.lookingAway,
      headTilt: raw.headTilt,
      focused: raw.focused,
      unfocused: raw.unfocused,
      alert: raw.alert,
      alertSeverity: raw.alertSeverity,
      alarmMuted: raw.alarmMuted,
      fps: raw.fps,
      calibrationState: raw.calibrationState,
      calibrationProgress: raw.calibrationProgress,
      calibrationError: raw.calibrationError,
      calibrationValidSamples: raw.calibrationValidSamples,
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
      : _baseUrl = _cleanBaseUrl(baseUrl);

  String _baseUrl;
  String? token;
  final HttpClient _http = HttpClient();
  MonitoringSnapshot snapshot = MonitoringSnapshot.initial();
  BackendConnectionState connectionState = BackendConnectionState.disconnected;
  String? errorMessage;
  DateTime? lastUpdate;
  int _generation = 0;
  bool _disposed = false;

  final ValueNotifier<Uint8List?> _latestFrameBytes =
      ValueNotifier<Uint8List?>(null);
  final _SnapshotSmoother _smoother = _SnapshotSmoother();

  String get baseUrl => _baseUrl;

  /// Latest JPEG frame from the persistent MJPEG stream, or null before the
  /// first frame arrives. Only the newest frame is retained, so a slow UI
  /// never falls behind the camera.
  ValueListenable<Uint8List?> get latestFrameBytes => _latestFrameBytes;

  // SSE waits 25s for next event; marking stale at 3s is a UX lie.
  // Consider stale only after 30s (25 + buffer) to avoid flicker during normal waits.
  bool get isStale =>
      lastUpdate == null ||
      DateTime.now().difference(lastUpdate!).inSeconds > 30;

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
        if (token != null && token!.isNotEmpty)
          'Authorization': 'Bearer $token',
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
    _resetMjpegState();
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
    _resetMjpegState();
    _smoother.reset();
    notifyListeners();
  }

  /// Maintains one persistent HTTP connection to the MJPEG endpoint and
  /// publishes the newest decoded JPEG frame. Reconnects with backoff on
  /// drops; the backend drops old frames itself, so the client can never
  /// block detection.
  void _startMjpeg(int generation) {
    _runMjpeg(generation);
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
          throw const HttpException(
              'Video stream is missing its MJPEG boundary');
        }
        final separator = utf8.encode('--$boundary');

        await for (final chunk in response) {
          if (generation != _generation || _disposed) return;
          _feedMjpegBytes(chunk, separator);
        }
        // Stream ended normally (server closed); treat it as a reconnect.
      } catch (error) {
        if (generation != _generation || _disposed) return;
        // Don't overwrite connectionState — the SSE event loop manages
        // it. MJPEG failures are expected while the pipeline is idle
        // (no frames published). Retry silently.
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
    var boundary = contentType.substring(index + marker.length).trim();
    final semicolon = boundary.indexOf(';');
    if (semicolon >= 0) boundary = boundary.substring(0, semicolon).trim();
    if (boundary.length >= 2 &&
        ((boundary.startsWith('"') && boundary.endsWith('"')) ||
            (boundary.startsWith("'") && boundary.endsWith("'")))) {
      boundary = boundary.substring(1, boundary.length - 1);
    }
    return boundary.isEmpty ? null : boundary;
  }

  final BytesBuilder _mjpegBuffer = BytesBuilder(copy: false);

  void _resetMjpegState() => _mjpegBuffer.clear();

  /// Splits the multipart stream into per-frame JPEG payloads. Frame bodies
  /// carry an explicit Content-Length, so partial frames are buffered and
  /// only complete frames are published.
  /// Optimized to avoid extra copies: uses takeBytes() and sublistView.
  void _feedMjpegBytes(List<int> chunk, List<int> separator) {
    _mjpegBuffer.add(chunk);
    final bytes = _mjpegBuffer.takeBytes();

    final separatorBytes = separator;
    var cursor = 0;
    Uint8List? lastFrame;
    while (true) {
      final start = _indexOf(bytes, separatorBytes, cursor);
      if (start < 0) break;
      final headerEnd =
          _indexOf(bytes, _crlfCrlf, start + separatorBytes.length);
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
      // Only keep the last complete frame — use view without extra copy
      lastFrame = Uint8List.sublistView(bytes, bodyStart, bodyEnd);
      cursor = bodyEnd;
    }
    if (lastFrame != null) {
      // Copy only the final frame for the ValueNotifier (must own its buffer)
      _latestFrameBytes.value = Uint8List.fromList(lastFrame);
    }
    if (cursor > 0 && cursor < bytes.length) {
      _mjpegBuffer.add(Uint8List.sublistView(bytes, cursor));
    } else if (cursor == 0) {
      // No complete frame found — re-buffer everything
      _mjpegBuffer.add(bytes);
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
    await for (final line
        in response.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.startsWith('data: ')) {
        dataLine = line.substring(6);
      } else if (line.isEmpty && dataLine != null) {
        final event = jsonDecode(dataLine) as Map<String, dynamic>;
        result = MonitoringSnapshot.fromJson(
          event['data'] as Map<String, dynamic>,
        );
        dataLine = null;
      }
    }
    return result;
  }

  void _apply(MonitoringSnapshot next) {
    final newServer =
        next.serverId.isNotEmpty && next.serverId != snapshot.serverId;
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
      throw HttpException(
          'Pairing code unavailable (${response.statusCode}): $body');
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
      throw const FormatException(
          'Pairing response did not contain an access token');
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

  Future<List<Map<String, dynamic>>> fetchTripHistory() async {
    try {
      final request = await _http.getUrl(
        Uri.parse('$_baseUrl/api/v1/sessions/history'),
      );
      _headers().forEach(request.headers.add);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        return [];
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      final list = data['history'] as List<dynamic>?;
      if (list == null) return [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
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
        throw HttpException(
            'Device revocation failed (${response.statusCode}): $body');
      }
    } finally {
      // Clear local credentials even if the backend is unreachable. The user
      // can pair again, while a failed remote revoke is surfaced to the UI.
      token = null;
      disconnect();
    }
  }

  Future<void> sendCommand(String path, [Map<String, dynamic>? payload]) async {
    final body = utf8.encode(jsonEncode(payload ?? <String, dynamic>{}));
    final request = await _http.postUrl(Uri.parse('$_baseUrl$path'));
    request.headers.contentType = ContentType.json;
    request.headers.contentLength = body.length;
    _headers().forEach(request.headers.add);
    request.add(body);
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final respBody = await response.transform(utf8.decoder).join();
      throw HttpException('Command failed (${response.statusCode}): $respBody');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;

    _latestFrameBytes.dispose();
    _http.close(force: true);
    super.dispose();
  }
}
