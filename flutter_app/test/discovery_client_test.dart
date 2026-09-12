import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:driver_monitor/services/discovery_client.dart';

void main() {
  group('DiscoveryReply parsing', () {
    test('parses a valid v1 reply', () {
      final reply = DiscoveryReply.tryParse(
        utf8.encode('{"service":"wakeguard","v":1,"port":8765,'
            '"device_name":"DESKTOP-AB12","platform":"windows"}'),
      );

      expect(reply, isNotNull);
      expect(reply!.service, 'wakeguard');
      expect(reply.port, 8765);
      expect(reply.deviceName, 'DESKTOP-AB12');
      expect(reply.platform, 'windows');
    });

    test('rejects wrong service name', () {
      final reply = DiscoveryReply.tryParse(utf8.encode(
          '{"service":"other","v":1,"port":8765,"device_name":"x"}'));
      expect(reply, isNull);
    });

    test('rejects wrong protocol version', () {
      final reply = DiscoveryReply.tryParse(utf8.encode(
          '{"service":"wakeguard","v":2,"port":8765,"device_name":"x"}'));
      expect(reply, isNull);
    });

    test('rejects missing or invalid port', () {
      expect(
        DiscoveryReply.tryParse(utf8.encode(
            '{"service":"wakeguard","v":1,"device_name":"x"}')),
        isNull,
      );
      expect(
        DiscoveryReply.tryParse(utf8.encode(
            '{"service":"wakeguard","v":1,"port":"8765","device_name":"x"}')),
        isNull,
      );
      expect(
        DiscoveryReply.tryParse(utf8.encode(
            '{"service":"wakeguard","v":1,"port":99999,"device_name":"x"}')),
        isNull,
      );
    });

    test('rejects garbage bytes and empty payloads', () {
      expect(DiscoveryReply.tryParse(utf8.encode('not json')), isNull);
      expect(DiscoveryReply.tryParse(utf8.encode('{}')), isNull);
      expect(DiscoveryReply.tryParse(const []), isNull);
    });

    test('deviceName falls back to Unknown', () {
      final reply = DiscoveryReply.tryParse(
          utf8.encode('{"service":"wakeguard","v":1,"port":8765}'));
      expect(reply!.deviceName, 'Unknown');
    });
  });

  group('DiscoveredBackend URL and ordering', () {
    DiscoveredBackend backend(String host, {int port = 8765}) =>
        DiscoveredBackend(
          host: host,
          port: port,
          deviceName: 'd',
          platform: 'windows',
        );

    test('builds http URL from host and port', () {
      expect(backend('192.168.1.50').url, 'http://192.168.1.50:8765');
      expect(
        backend('192.168.1.50', port: 9000).url,
        'http://192.168.1.50:9000',
      );
    });

    test('isLoopback detects loopback replies (spoof guard)', () {
      expect(backend('127.0.0.1').isLoopback, isTrue);
      expect(backend('::1').isLoopback, isTrue);
      expect(backend('192.168.1.50').isLoopback, isFalse);
    });

    test('lower numeric IPv4 wins the tie-break', () {
      final a = backend('192.168.1.50');
      final b = backend('10.68.99.7');
      expect(DiscoveredBackend.pickBest([a, b]), same(b));
      expect(DiscoveredBackend.pickBest([b, a]), same(b));
    });

    test('non-IP hosts sort lexically after IPs', () {
      final ip = backend('192.168.1.50');
      final name = backend('desktop.local');
      expect(DiscoveredBackend.pickBest([name, ip]), same(ip));
    });

    test('null-safe on empty list', () {
      expect(DiscoveredBackend.pickBest([]), isNull);
    });

    test('filters loopback replies before selection', () {
      final good = backend('192.168.1.50');
      final spoof = backend('127.0.0.1');
      final picked = DiscoveredBackend.pickBest([good, spoof]);
      expect(picked, same(good));
    });
  });
}
