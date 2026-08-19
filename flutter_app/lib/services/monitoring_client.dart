import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/monitoring_snapshot.dart';

enum BackendConnectionState { disconnected, connecting, connected, error }

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

  String get baseUrl => _baseUrl;

  /// Latest JPEG frame from the persistent MJPEG stream, or null before the
  /// first frame arrives. Only the newest frame is retained, so a slow UI
  /// never falls behind the camera.
  ValueListenable<Uint8List?> get latestFrameBytes => _latestFrameBytes;

  bool get isStale => lastUpdate == null ||
      DateTime.now().difference(lastUpdate!).inSeconds > 3;

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
    snapshot = next;
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
