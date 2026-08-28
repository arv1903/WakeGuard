import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Information about a registered desktop device.
class DeviceInfo {
  final String id;
  final String deviceName;
  final String? platform;
  final String? apiHost;
  final int? apiPort;
  final String? lastSeenAt;

  DeviceInfo({
    required this.id,
    required this.deviceName,
    this.platform,
    this.apiHost,
    this.apiPort,
    this.lastSeenAt,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      id: json['id'] as String,
      deviceName: json['device_name'] as String? ?? 'Unknown',
      platform: json['platform'] as String?,
      apiHost: json['api_host'] as String?,
      apiPort: json['api_port'] as int?,
      lastSeenAt: json['last_seen_at'] as String?,
    );
  }

  String get displayPlatform {
    switch (platform) {
      case 'windows':
        return 'Windows';
      case 'linux':
        return 'Linux';
      case 'macos':
        return 'macOS';
      default:
        return platform ?? 'Unknown';
    }
  }

  String get connectionUrl {
    if (apiHost == null) return '';
    final port = apiPort ?? 8765;
    return 'http://$apiHost:$port';
  }
}

/// Discovers desktop devices and handles pairing for the Flutter companion.
class DeviceDiscoveryService {
  final HttpClient _http = HttpClient();

  /// Fetch all devices registered to the current user.
  Future<List<DeviceInfo>> discoverDevices(String backendUrl, String jwt) async {
    final request = await _http.getUrl(
      Uri.parse('$backendUrl/api/v1/device/discover'),
    );
    request.headers.add('Authorization', 'Bearer $jwt');

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw Exception('Device discovery failed (${response.statusCode}): $body');
    }

    final data = jsonDecode(body) as Map<String, dynamic>;
    final devices = data['devices'] as List<dynamic>? ?? [];
    return devices
        .map((d) => DeviceInfo.fromJson(d as Map<String, dynamic>))
        .toList();
  }

  /// Pair with a specific device — returns a scoped access token and
  /// the device's connection URL.
  Future<PairingResult> pairWithDevice(
    String backendUrl,
    String jwt,
    String deviceId,
  ) async {
    final body = utf8.encode(jsonEncode({'device_id': deviceId}));

    final request = await _http.postUrl(
      Uri.parse('$backendUrl/api/v1/auth/pair'),
    );
    request.headers.contentType = ContentType.json;
    request.headers.add('Authorization', 'Bearer $jwt');
    request.headers.contentLength = body.length;
    request.add(body);

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      final error = jsonDecode(responseBody);
      throw Exception(error['error'] ?? 'Pairing failed');
    }

    final result = jsonDecode(responseBody) as Map<String, dynamic>;
    final device = result['device'] as Map<String, dynamic>?;
    final host = device?['api_host'] as String?;
    final port = device?['api_port'] as int? ?? 8765;

    return PairingResult(
      accessToken: result['access_token'] as String,
      expiresAt: result['expires_at'] as num?,
      deviceUrl: host != null ? 'http://$host:$port' : null,
    );
  }

  void dispose() {
    _http.close(force: true);
  }
}

/// Result of a successful device pairing.
class PairingResult {
  final String accessToken;
  final num? expiresAt;
  final String? deviceUrl;

  PairingResult({
    required this.accessToken,
    this.expiresAt,
    this.deviceUrl,
  });
}
