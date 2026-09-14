import 'dart:convert';

/// Payload encoded in the desktop's pairing QR code (protocol v1).
///
/// A superset of the backend's `driver-monitor://pair?code=...` URI: the
/// one-time pairing code plus the desktop's LAN address, so the phone can
/// connect even when UDP discovery is blocked (AP isolation, VPNs).
/// Scanned in-app, so no OS deep-link registration is involved.
class PairingQrPayload {
  PairingQrPayload({
    required this.code,
    required this.host,
    this.port = 8765,
  });

  static const version = 1;

  final String code;
  final String host;
  final int port;

  String get url => 'http://$host:$port';

  /// Compact JSON — fewer modules means a larger, easier-to-scan QR.
  String toJson() =>
      '{"v":$version,"code":${jsonEncode(code)},"host":${jsonEncode(host)},"port":$port}';

  /// Lenient parse for camera input: returns null on anything that isn't a
  /// valid v1 payload. The code is trimmed and upper-cased to match the
  /// backend's own normalization (`PairingManager.exchange`).
  static PairingQrPayload? tryParse(String raw) {
    if (raw.isEmpty) return null;
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      json = decoded;
    } on FormatException {
      return null;
    }
    if (json['v'] != version) return null;
    final code = json['code'];
    final host = json['host'];
    final port = json['port'];
    if (code is! String || code.trim().isEmpty) return null;
    if (host is! String || host.trim().isEmpty) return null;
    if (port is! int || port <= 0 || port > 65535) return null;
    return PairingQrPayload(
      code: code.trim().toUpperCase(),
      host: host.trim(),
      port: port,
    );
  }
}
