class MonitoringSnapshot {
  const MonitoringSnapshot({
    required this.schemaVersion,
    required this.sequence,
    required this.serverId,
    required this.timestamp,
    required this.sessionId,
    required this.tripStartedAt,
    required this.tripActive,
    required this.attention,
    required this.perclos,
    required this.emaDrowsy,
    required this.ear,
    required this.eyesClosed,
    required this.microsleep,
    required this.blinksPerMin,
    required this.pitch,
    required this.yaw,
    required this.roll,
    required this.poseValid,
    required this.faceFound,
    required this.faceLost,
    required this.faceLostProgress,
    required this.headDown,
    required this.lookingAway,
    required this.headTilt,
    required this.focused,
    required this.unfocused,
    required this.alert,
    required this.alertSeverity,
    required this.alarmMuted,
    required this.fps,
    required this.calibrationState,
    required this.calibrationProgress,
    required this.calibrationError,
    required this.calibrationValidSamples,
  });

  factory MonitoringSnapshot.initial() => const MonitoringSnapshot(
        schemaVersion: 2,
        sequence: 0,
        serverId: '',
        timestamp: 0,
        sessionId: null,
        tripStartedAt: null,
        tripActive: false,
        attention: 100,
        perclos: 0,
        emaDrowsy: 0,
        ear: null,
        eyesClosed: false,
        microsleep: false,
        blinksPerMin: 0,
        pitch: 0,
        yaw: 0,
        roll: 0,
        poseValid: false,
        faceFound: false,
        faceLost: false,
        faceLostProgress: 0,
        headDown: false,
        lookingAway: false,
        headTilt: false,
        focused: false,
        unfocused: false,
        alert: null,
        alertSeverity: 0,
        alarmMuted: false,
        fps: 0,
        calibrationState: 'idle',
        calibrationProgress: 0,
        calibrationError: null,
        calibrationValidSamples: 0,
      );

  factory MonitoringSnapshot.fromJson(Map<String, dynamic> json) {
    double number(String key, [double fallback = 0]) {
      final value = json[key];
      return value is num ? value.toDouble() : fallback;
    }

    bool flag(String key) => json[key] == true;

    return MonitoringSnapshot(
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      serverId: json['server_id'] as String? ?? '',
      timestamp: number('timestamp'),
      sessionId: json['session_id'] as String?,
      tripStartedAt: json['trip_started_at'] is num
          ? (json['trip_started_at'] as num).toDouble()
          : null,
      tripActive: flag('trip_active'),
      attention: number('attention', 100),
      perclos: number('perclos'),
      emaDrowsy: number('ema_drowsy'),
      ear: json['ear'] is num ? (json['ear'] as num).toDouble() : null,
      eyesClosed: flag('eyes_closed'),
      microsleep: flag('microsleep'),
      blinksPerMin: number('blinks_per_min'),
      pitch: number('pitch'),
      yaw: number('yaw'),
      roll: number('roll'),
      poseValid: flag('pose_valid'),
      faceFound: flag('face_found'),
      faceLost: flag('face_lost'),
      faceLostProgress: number('face_lost_progress'),
      headDown: flag('head_down'),
      lookingAway: flag('looking_away'),
      headTilt: flag('head_tilt'),
      focused: flag('focused'),
      unfocused: flag('unfocused'),
      alert: json['alert'] as String?,
      alertSeverity: (json['alert_severity'] as num?)?.toInt() ?? 0,
      alarmMuted: flag('alarm_muted'),
      fps: number('fps'),
      calibrationState: json['calibration_state'] as String? ?? 'idle',
      calibrationProgress: number('calibration_progress'),
      calibrationError: json['calibration_error'] as String?,
      calibrationValidSamples:
          (json['calibration_valid_samples'] as num?)?.toInt() ?? 0,
    );
  }

  final int schemaVersion;
  final int sequence;
  final String serverId;
  final double timestamp;
  final String? sessionId;
  final double? tripStartedAt;
  final bool tripActive;
  final double attention;
  final double perclos;
  final double emaDrowsy;
  final double? ear;
  final bool eyesClosed;
  final bool microsleep;
  final double blinksPerMin;
  final double pitch;
  final double yaw;
  final double roll;
  final bool poseValid;
  final bool faceFound;
  final bool faceLost;
  final double faceLostProgress;
  final bool headDown;
  final bool lookingAway;
  final bool headTilt;
  final bool focused;
  final bool unfocused;
  final String? alert;
  final int alertSeverity;
  final bool alarmMuted;
  final double fps;
  final String calibrationState;
  final double calibrationProgress;
  final String? calibrationError;
  final int calibrationValidSamples;

  String get status {
    if (alertSeverity >= 4) return 'Critical';
    if (alertSeverity >= 3) return 'Drowsy';
    if (alertSeverity >= 2) return 'Distracted';
    if (focused) return 'Focused';
    if (unfocused) return 'Unfocused';
    if (faceLost) return 'Face not detected';
    return 'Monitoring';
  }
}
