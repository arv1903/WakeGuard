import 'package:flutter_test/flutter_test.dart';
import 'package:driver_monitor/models/monitoring_snapshot.dart';

void main() {
  group('MonitoringSnapshot.fromJson', () {
    test('parses a full JSON payload', () {
      final json = <String, dynamic>{
        'schema_version': 1,
        'sequence': 42,
        'server_id': 'abc123',
        'timestamp': 1700000000.0,
        'session_id': 'sess-001',
        'trip_started_at': 1699999000.0,
        'trip_active': true,
        'attention': 87.5,
        'perclos': 0.12,
        'ema_drowsy': 0.3,
        'ear': 0.25,
        'eyes_closed': false,
        'microsleep': false,
        'blinks_per_min': 15.0,
        'pitch': -5.0,
        'yaw': 3.2,
        'roll': 1.0,
        'pose_valid': true,
        'face_found': true,
        'face_lost': false,
        'face_lost_progress': 0.0,
        'head_down': false,
        'looking_away': false,
        'head_tilt': false,
        'focused': true,
        'unfocused': false,
        'alert': null,
        'alert_severity': 0,
        'alarm_muted': false,
        'fps': 30.0,
      };

      final snap = MonitoringSnapshot.fromJson(json);

      expect(snap.schemaVersion, 1);
      expect(snap.sequence, 42);
      expect(snap.serverId, 'abc123');
      expect(snap.timestamp, 1700000000.0);
      expect(snap.sessionId, 'sess-001');
      expect(snap.tripStartedAt, 1699999000.0);
      expect(snap.tripActive, true);
      expect(snap.attention, 87.5);
      expect(snap.perclos, 0.12);
      expect(snap.emaDrowsy, 0.3);
      expect(snap.ear, 0.25);
      expect(snap.eyesClosed, false);
      expect(snap.microsleep, false);
      expect(snap.blinksPerMin, 15.0);
      expect(snap.pitch, -5.0);
      expect(snap.yaw, 3.2);
      expect(snap.roll, 1.0);
      expect(snap.poseValid, true);
      expect(snap.faceFound, true);
      expect(snap.faceLost, false);
      expect(snap.headDown, false);
      expect(snap.focused, true);
      expect(snap.alert, null);
      expect(snap.alertSeverity, 0);
      expect(snap.fps, 30.0);
    });

    test('handles empty JSON with defaults', () {
      final snap = MonitoringSnapshot.fromJson(<String, dynamic>{});

      expect(snap.sequence, 0);
      expect(snap.serverId, '');
      expect(snap.attention, 100.0);
      expect(snap.perclos, 0.0);
      expect(snap.ear, isNull);
      expect(snap.tripActive, false);
      expect(snap.sessionId, isNull);
      expect(snap.tripStartedAt, isNull);
      expect(snap.alert, isNull);
      expect(snap.focused, false);
    });

    test('handles int values where doubles expected', () {
      final json = <String, dynamic>{
        'attention': 80,
        'perclos': 0,
        'pitch': -10,
        'yaw': 5,
      };
      final snap = MonitoringSnapshot.fromJson(json);
      expect(snap.attention, 80.0);
      expect(snap.perclos, 0.0);
      expect(snap.pitch, -10.0);
    });

    test('initial() produces a sensible default snapshot', () {
      final snap = MonitoringSnapshot.initial();

      expect(snap.sequence, 0);
      expect(snap.attention, 100.0);
      expect(snap.tripActive, false);
      expect(snap.serverId, '');
      expect(snap.alert, isNull);
      expect(snap.focused, false);
    });
  });

  group('status getter', () {
    test('returns Critical for severity >= 4', () {
      final snap = MonitoringSnapshot.fromJson({
        'alert_severity': 4,
        'alert': 'MICROSLEEP',
      });
      expect(snap.status, 'Critical');
    });

    test('returns Drowsy for severity 3', () {
      final snap = MonitoringSnapshot.fromJson({
        'alert_severity': 3,
        'alert': 'HEAD NODDING',
      });
      expect(snap.status, 'Drowsy');
    });

    test('returns Distracted for severity 2', () {
      final snap = MonitoringSnapshot.fromJson({
        'alert_severity': 2,
        'alert': 'DISTRACTED',
      });
      expect(snap.status, 'Distracted');
    });

    test('returns Focused when focused flag is set', () {
      final snap = MonitoringSnapshot.fromJson({'focused': true});
      expect(snap.status, 'Focused');
    });

    test('returns Unfocused when unfocused flag is set', () {
      final snap = MonitoringSnapshot.fromJson({'unfocused': true});
      expect(snap.status, 'Unfocused');
    });

    test('returns Face not detected when faceLost is set', () {
      final snap = MonitoringSnapshot.fromJson({'face_lost': true});
      expect(snap.status, 'Face not detected');
    });

    test('returns Monitoring for default state', () {
      final snap = MonitoringSnapshot.initial();
      expect(snap.status, 'Monitoring');
    });
  });
}
