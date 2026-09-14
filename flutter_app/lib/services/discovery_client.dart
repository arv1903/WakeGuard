import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// UDP discovery protocol v1 (see yolo/discovery.py for the responder).
///
/// The phone broadcasts b"WG-DISCOVER" to udp/48765; any WakeGuard backend on
/// the subnet replies with a small JSON descriptor. The backend's IP is taken
/// from the reply's *source address* — never from a payload field — so a
/// spoofed packet cannot redirect the client.
class DiscoveryClient {
  DiscoveryClient({this.timeout = const Duration(milliseconds: 1200)});

  /// How long to listen for replies after the probe.
  final Duration timeout;

  static const probeMagic = 'WG-DISCOVER';
  static const discoveryPort = 48765;

  RawDatagramSocket? _socket;

  /// Broadcasts the probe and collects replies for [timeout].
  ///
  /// Returns every distinct backend that answered, loopback replies filtered
  /// out (nothing useful runs on 127.0.0.1 from the phone's perspective, and
  /// accepting it would let a spoofed packet point the client at itself).
  Future<List<DiscoveredBackend>> discover() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
    );
    _socket = socket;
    socket.broadcastEnabled = true;
    try {
      final backends = <DiscoveredBackend>[];
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final backend = _parseReply(datagram);
        if (backend != null) backends.add(backend);
      });

      socket.send(
        utf8.encode(probeMagic),
        InternetAddress('255.255.255.255'),
        discoveryPort,
      );

      await Future<void>.delayed(timeout);
      return DiscoveredBackend.dedupe(backends);
    } finally {
      socket.close();
      _socket = null;
    }
  }

  DiscoveredBackend? _parseReply(Datagram datagram) {
    final host = datagram.address.address;
    if (host == '255.255.255.255') return null; // broadcast echo, not a reply
    final reply = DiscoveryReply.tryParse(datagram.data);
    if (reply == null) return null;
    return DiscoveredBackend(
      host: host,
      port: reply.port,
      deviceName: reply.deviceName,
      platform: reply.platform,
    );
  }

  void close() {
    _socket?.close();
    _socket = null;
  }
}

/// Parsed reply payload — validation happens here, once.
class DiscoveryReply {
  DiscoveryReply({
    required this.service,
    required this.port,
    required this.deviceName,
    required this.platform,
  });

  final String service;
  final int port;
  final String deviceName;
  final String platform;

  static DiscoveryReply? tryParse(List<int> bytes) {
    if (bytes.isEmpty) return null;
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) return null;
      json = decoded;
    } on FormatException {
      return null;
    }
    if (json['service'] != 'wakeguard') return null;
    if (json['v'] != 1) return null;
    final port = json['port'];
    if (port is! int || port <= 0 || port > 65535) return null;
    return DiscoveryReply(
      service: json['service'] as String,
      port: port,
      deviceName: (json['device_name'] as String?)?.trim().isEmpty == true
          ? 'Unknown'
          : (json['device_name'] as String?) ?? 'Unknown',
      platform: (json['platform'] as String?) ?? 'unknown',
    );
  }
}

/// A backend found on the LAN, ready to connect to.
class DiscoveredBackend {
  DiscoveredBackend({
    required this.host,
    required this.port,
    required this.deviceName,
    required this.platform,
  });

  final String host;
  final int port;
  final String deviceName;
  final String platform;

  String get url => 'http://$host:$port';

  bool get isLoopback =>
      host == '127.0.0.1' || host == '::1' || host == 'localhost';

  /// Deterministic selection when several backends answer: lowest IPv4 first,
  /// non-IP hostnames last (lexical among themselves).
  static DiscoveredBackend? pickBest(Iterable<DiscoveredBackend> backends) {
    final usable =
        backends.where((b) => !b.isLoopback).toList(growable: false);
    if (usable.isEmpty) return null;
    usable.sort(_compare);
    return usable.first;
  }

  static List<DiscoveredBackend> dedupe(List<DiscoveredBackend> backends) =>
      backends.where((b) => !b.isLoopback).toList();

  static int _compare(DiscoveredBackend a, DiscoveredBackend b) {
    final aIp = InternetAddress.tryParse(a.host);
    final bIp = InternetAddress.tryParse(b.host);
    if (aIp != null && bIp != null) {
      final aOctets = aIp.rawAddress;
      final bOctets = bIp.rawAddress;
      final cmp = _compareBytes(aOctets, bOctets);
      if (cmp != 0) return cmp;
    } else if (aIp != null) {
      return -1; // real IPs before hostnames
    } else if (bIp != null) {
      return 1;
    }
    return a.host.compareTo(b.host);
  }

  static int _compareBytes(List<int> a, List<int> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      final cmp = (a[i] & 0xff).compareTo(b[i] & 0xff);
      if (cmp != 0) return cmp;
    }
    return a.length.compareTo(b.length);
  }
}
