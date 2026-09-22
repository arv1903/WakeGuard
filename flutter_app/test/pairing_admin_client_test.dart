import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:driver_monitor/services/monitoring_client.dart';

void main() {
  late HttpServer server;
  late Uri baseUri;
  HttpRequest? lastRequest;
  final receivedBodies = <Map<String, dynamic>>[];

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      lastRequest = request;
      if (request.method == 'POST') {
        final body = await utf8.decoder.bind(request).join();
        receivedBodies.add(body.isEmpty ? {} : jsonDecode(body));
      }
      if (request.uri.path.endsWith('/pairings')) {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'devices': [
            {
              'token_preview': 'AB12CD34',
              'device_name': "Marvin's Phone",
              'issued_at': 1757568000,
              'expires_at': 1757654400,
            },
            {
              'token_preview': 'ZZ99YY88',
              'device_name': '',
              'issued_at': 1757571600,
              'expires_at': 1757575200,
            },
          ],
        }));
      } else {
        request.response.statusCode = 200;
        request.response.write('{}');
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    lastRequest = null;
    receivedBodies.clear();
  });

  MonitoringClient clientWithToken({String? token}) =>
      MonitoringClient(baseUrl: baseUri.toString(), token: token);

  test('listPairings parses devices and sends the auth header', () async {
    final client = clientWithToken(token: 'master-token');

    final devices = await client.listPairings();

    expect(lastRequest!.uri.path, '/api/v1/pairings');
    expect(
      lastRequest!.headers.value('Authorization'),
      'Bearer master-token',
    );
    expect(devices.length, 2);
    expect(devices[0].tokenPreview, 'AB12CD34');
    expect(devices[0].deviceName, "Marvin's Phone");
    expect(devices[0].expiresAt, isA<DateTime>());
  });

  test('listPairings labels unnamed devices as Unknown', () async {
    final client = clientWithToken();

    final devices = await client.listPairings();

    expect(devices[1].deviceName, 'Unknown');
  });

  test('revokePairing posts the preview and reports the result', () async {
    final client = clientWithToken(token: 'master-token');

    final ok = await client.revokePairing('AB12CD34');

    expect(ok, isTrue);
    expect(lastRequest!.uri.path, '/api/v1/pairings/revoke');
    expect(lastRequest!.method, 'POST');
    expect(receivedBodies.single, {'token_preview': 'AB12CD34'});
  });

  test('revokePairing returns false when nothing matched (404)', () async {
    final client = clientWithToken();

    // Point the client at a server returning 404
    final failing = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    failing.listen((request) async {
      request.response.statusCode = 404;
      request.response.write('{"error": "no matching companion token"}');
      await request.response.close();
    });
    addTearDown(failing.close);

    final gone = MonitoringClient(
      baseUrl: 'http://127.0.0.1:${failing.port}',
    );
    expect(await gone.revokePairing('NOPE1234'), isFalse);
    expect(await client.revokePairing('AB12CD34'), isTrue);
  });
}
