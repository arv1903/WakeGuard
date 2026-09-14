import 'package:flutter_test/flutter_test.dart';

import 'package:driver_monitor/services/pairing_qr.dart';

void main() {
  group('PairingQrPayload round-trip', () {
    test('encodes to the documented JSON shape', () {
      final payload = PairingQrPayload(
        code: 'AB12CD34',
        host: '192.168.1.50',
        port: 8765,
      );
      expect(
        payload.toJson(),
        '{"v":1,"code":"AB12CD34","host":"192.168.1.50","port":8765}',
      );
    });

    test('round-trips through tryParse', () {
      const raw =
          '{"v":1,"code":"AB12CD34","host":"192.168.1.50","port":8765}';
      final payload = PairingQrPayload.tryParse(raw);
      expect(payload, isNotNull);
      expect(payload!.code, 'AB12CD34');
      expect(payload.host, '192.168.1.50');
      expect(payload.port, 8765);
      expect(payload.url, 'http://192.168.1.50:8765');
    });

    test('rejects wrong version, missing fields, and bad types', () {
      expect(
        PairingQrPayload.tryParse('{"v":2,"code":"A","host":"h","port":1}'),
        isNull,
      );
      expect(
        PairingQrPayload.tryParse('{"v":1,"host":"h","port":1}'),
        isNull,
      );
      expect(
        PairingQrPayload.tryParse('{"v":1,"code":"A","host":"h","port":"1"}'),
        isNull,
      );
      expect(
        PairingQrPayload.tryParse(
            '{"v":1,"code":"A","host":"h","port":99999}'),
        isNull,
      );
      expect(PairingQrPayload.tryParse('not json at all'), isNull);
      expect(PairingQrPayload.tryParse(''), isNull);
    });

    test('normalizes whitespace and case in the code', () {
      final payload = PairingQrPayload.tryParse(
        '{"v":1,"code":"  ab12cd34 ","host":"192.168.1.50","port":8765}',
      );
      expect(payload!.code, 'AB12CD34');
    });
  });

  group('Desktop QR content', () {
    test('uses a LAN-style host, never loopback', () {
      // The whole point: loopback QR codes would pair the phone to itself.
      final payload = PairingQrPayload(code: 'AB12CD34', host: '10.68.99.104');
      expect(payload.url.startsWith('http://127.'), isFalse);
      expect(payload.url, 'http://10.68.99.104:8765');
    });
  });
}
