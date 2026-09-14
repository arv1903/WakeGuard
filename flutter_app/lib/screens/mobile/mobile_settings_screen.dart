import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/connection_service.dart';
import '../../services/monitoring_client.dart';
import '../../theme.dart';

/// Mobile settings screen matching the Stitch "Settings" mockup.
///
/// Shows calibration, thresholds, toggles, account, and forget device.
class MobileSettingsScreen extends StatefulWidget {
  const MobileSettingsScreen({
    super.key,
    required this.connectionService,
    required this.authService,
    this.onForgetDevice,
  });

  final ConnectionService connectionService;
  final AuthService authService;
  final VoidCallback? onForgetDevice;

  @override
  State<MobileSettingsScreen> createState() => _MobileSettingsScreenState();
}

class _MobileSettingsScreenState extends State<MobileSettingsScreen> {
  bool _forgetting = false;
  bool _calibrating = false;
  bool _loggingOut = false;

  // Threshold positions — 0 Alert, 1 Balanced, 2 Relaxed (same names and
  // values as the desktop calibration screen; lower thresholds = more
  // sensitive detection).
  int _poseSensitivity = 1;
  int _drowsySensitivity = 1;
  int _appliedPose = 1;
  int _appliedDrowsy = 1;
  Timer? _settingsDebounce;

  static const _sensitivityLabels = ['Alert', 'Balanced', 'Relaxed'];

  static const Map<int, Map<String, double>> _poseThresholds = {
    0: {'pitch_threshold': 10.0, 'yaw_threshold': 15.0, 'roll_threshold': 6.0},
    1: {'pitch_threshold': 20.0, 'yaw_threshold': 30.0, 'roll_threshold': 10.0},
    2: {'pitch_threshold': 28.0, 'yaw_threshold': 38.0, 'roll_threshold': 18.0},
  };

  static const Map<int, Map<String, double>> _drowsyThresholds = {
    0: {'ear_threshold': 0.15, 'microsleep_duration': 0.8},
    1: {'ear_threshold': 0.20, 'microsleep_duration': 1.5},
    2: {'ear_threshold': 0.25, 'microsleep_duration': 2.5},
  };

  @override
  void initState() {
    super.initState();
    widget.connectionService.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _settingsDebounce?.cancel();
    widget.connectionService.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _forgetDevice() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Stitch.container,
        title: const Text('Forget Device',
            style: TextStyle(color: Stitch.onSurface)),
        content: const Text(
          'This will disconnect and remove saved credentials. '
          'You will need to re-pair to reconnect.',
          style: TextStyle(color: Stitch.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Stitch.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Forget', style: TextStyle(color: Stitch.error)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _forgetting = true);
    try {
      await widget.connectionService.forgetDevice();
      if (mounted) widget.onForgetDevice?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Stitch.error,
        ));
      }
    }
    if (mounted) setState(() => _forgetting = false);
  }

  // ── Real connection state (was hardcoded 'NODE ACTIVE // UPLINK SECURE')

  BackendConnectionState get _connectionState =>
      widget.connectionService.client.connectionState;

  Color get _uplinkColor {
    switch (_connectionState) {
      case BackendConnectionState.connected:
        return Stitch.secondary;
      case BackendConnectionState.connecting:
        return Stitch.primary;
      case BackendConnectionState.error:
      case BackendConnectionState.authRejected:
        return Stitch.error;
      case BackendConnectionState.disconnected:
        return Stitch.onSurfaceVariant;
    }
  }

  String get _uplinkLabel {
    switch (_connectionState) {
      case BackendConnectionState.connected:
        return 'NODE CONNECTED';
      case BackendConnectionState.connecting:
        return 'NODE CONNECTING...';
      case BackendConnectionState.error:
        return 'NODE ERROR // CHECK UPLINK';
      case BackendConnectionState.authRejected:
        return 'NODE ACCESS REVOKED // RE-PAIR REQUIRED';
      case BackendConnectionState.disconnected:
        return 'NODE DISCONNECTED';
    }
  }

  Future<void> _startRecalibration() async {
    if (_calibrating) return;
    setState(() => _calibrating = true);
    try {
      await widget.connectionService.client
          .sendCommand('/api/v1/calibration/start', {'duration': 4});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Calibration failed: $e'),
          backgroundColor: Stitch.error,
        ));
      }
    }
    if (mounted) setState(() => _calibrating = false);
  }

  void _queueThresholdUpdate() {
    _settingsDebounce?.cancel();
    _settingsDebounce = Timer(const Duration(milliseconds: 500), () async {
      final payload = {
        ..._poseThresholds[_poseSensitivity]!,
        ..._drowsyThresholds[_drowsySensitivity]!,
      };
      try {
        await widget.connectionService.client
            .sendCommand('/api/v1/settings', payload);
        if (mounted) {
          setState(() {
            _appliedPose = _poseSensitivity;
            _appliedDrowsy = _drowsySensitivity;
          });
        }
      } catch (e) {
        // Revert to the last applied levels so the UI never lies.
        if (mounted) {
          setState(() {
            _poseSensitivity = _appliedPose;
            _drowsySensitivity = _appliedDrowsy;
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Setting not applied: $e'),
            backgroundColor: Stitch.error,
          ));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Stitch.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page header
            const Text(
              'System Configuration',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Stitch.onSurface,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _uplinkColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _uplinkLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w500,
                    color: _uplinkColor,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Calibration section
            _SectionHeader('CALIBRATION'),
            const SizedBox(height: 12),
            _buildCalibrationCard(),
            const SizedBox(height: 24),

            // Thresholds section
            _SectionHeader('THRESHOLDS'),
            const SizedBox(height: 12),
            _buildThresholdsCard(),
            const SizedBox(height: 24),

            // Modules section
            _SectionHeader('MODULES'),
            const SizedBox(height: 12),
            _buildModulesCard(),
            const SizedBox(height: 24),

            // Operator section
            _SectionHeader('OPERATOR'),
            const SizedBox(height: 12),
            _buildAccountCard(),
            const SizedBox(height: 24),

            // Forget device
            _buildForgetButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildCalibrationCard() {
    // Live state from the backend snapshot (idle | running | succeeded | failed).
    final state = widget.connectionService.client.snapshot.calibrationState;
    final label = switch (state) {
      'running' => 'Calibrating...',
      'succeeded' => 'Calibrated',
      'failed' => 'Calibration failed',
      _ => 'Ready',
    };
    final icon = switch (state) {
      'running' => Icons.sync,
      'succeeded' => Icons.check_circle,
      'failed' => Icons.error_outline,
      _ => Icons.info_outline,
    };
    final iconColor = state == 'succeeded'
        ? Stitch.secondary
        : state == 'failed'
            ? Stitch.error
            : Stitch.onSurfaceVariant;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Stitch.surfaceLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Calibration',
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.w500,
              color: Stitch.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 20,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w600,
                  color: Stitch.onSurface,
                ),
              ),
              Icon(icon, color: iconColor, size: 20),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: Stitch.containerHigh,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: _calibrating ? null : _startRecalibration,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_calibrating) ...[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Stitch.primary),
                        ),
                        const SizedBox(width: 8),
                      ] else
                        const Icon(Icons.tune,
                            size: 18, color: Stitch.primary),
                      const SizedBox(width: 8),
                      Text(
                        _calibrating
                            ? 'CALIBRATING...'
                            : 'INITIATE RECALIBRATION',
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'JetBrains Mono',
                          fontWeight: FontWeight.w700,
                          color: _calibrating
                              ? Stitch.onSurfaceVariant
                              : Stitch.primary,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThresholdsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Stitch.surfaceLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _ThresholdSlider(
            label: 'Head Pose Sensitivity',
            value: _sensitivityLabels[_poseSensitivity],
            color: Stitch.primary,
            sliderValue: _poseSensitivity / 2,
            activeColor: Stitch.primary,
            onChanged: (v) {
              setState(() => _poseSensitivity = (v * 2).round());
              _queueThresholdUpdate();
            },
          ),
          const SizedBox(height: 20),
          _ThresholdSlider(
            label: 'Drowsy Detection',
            value: _sensitivityLabels[_drowsySensitivity],
            color: Stitch.tertiaryFixedDim,
            sliderValue: _drowsySensitivity / 2,
            activeColor: Stitch.tertiaryFixedDim,
            onChanged: (v) {
              setState(() => _drowsySensitivity = (v * 2).round());
              _queueThresholdUpdate();
            },
          ),
          const SizedBox(height: 12),
          if (_poseSensitivity != _appliedPose ||
              _drowsySensitivity != _appliedDrowsy)
            const Text(
              'Applying...',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'JetBrains Mono',
                color: Stitch.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModulesCard() {
    // The backend has no Telegram or session-logging endpoints, so those
    // toggles are gone rather than faked. Alarm state comes from the live
    // snapshot and maps to the real mute/unmute endpoints.
    final alarmEnabled =
        !widget.connectionService.client.snapshot.alarmMuted;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Stitch.surfaceLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _ModuleToggle(
            icon: Icons.volume_up,
            title: 'Alarm Sound',
            value: alarmEnabled,
            onChanged: (enabled) async {
              final path =
                  enabled ? '/api/v1/alarm/unmute' : '/api/v1/alarm/mute';
              try {
                await widget.connectionService.client.sendCommand(path);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Alarm setting failed: $e'),
                    backgroundColor: Stitch.error,
                  ));
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard() {
    final email = widget.authService.email ?? 'unknown account';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Stitch.surfaceLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Stitch.containerHighest,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: Stitch.onSurfaceVariant, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email,
                  style: const TextStyle(
                    fontSize: 14,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w500,
                    color: Stitch.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                const Text(
                  'AUTHENTICATED',
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w700,
                    color: Stitch.secondary,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Stitch.containerHighest,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: _loggingOut
                  ? null
                  : () async {
                      setState(() => _loggingOut = true);
                      try {
                        await widget.authService.logout();
                      } finally {
                        if (mounted) setState(() => _loggingOut = false);
                      }
                    },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _loggingOut
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'LOGOUT',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'JetBrains Mono',
                          fontWeight: FontWeight.w700,
                          color: Stitch.onSurface,
                          letterSpacing: 1,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForgetButton() {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Stitch.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: _forgetting ? null : _forgetDevice,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _forgetting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Stitch.error,
                        ),
                      )
                    : const Icon(Icons.delete_forever, size: 18, color: Stitch.error),
                const SizedBox(width: 8),
                const Text(
                  'FORGET DEVICE',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w700,
                    color: Stitch.error,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Section Header ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontFamily: 'JetBrains Mono',
        fontWeight: FontWeight.w700,
        color: Stitch.primary,
        letterSpacing: 2,
      ),
    );
  }
}

// ─── Threshold Slider ───────────────────────────────────────────────────────

class _ThresholdSlider extends StatelessWidget {
  const _ThresholdSlider({
    required this.label,
    required this.value,
    required this.color,
    required this.sliderValue,
    required this.activeColor,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Color color;
  final double sliderValue;
  final Color activeColor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'JetBrains Mono',
                fontWeight: FontWeight.w500,
                color: Stitch.onSurface,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'JetBrains Mono',
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: activeColor,
            inactiveTrackColor: Stitch.containerHighest,
            thumbColor: activeColor,
            overlayColor: activeColor.withValues(alpha: 0.1),
            trackHeight: 8,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: sliderValue.clamp(0.0, 1.0),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

// ─── Module Toggle ──────────────────────────────────────────────────────────

class _ModuleToggle extends StatelessWidget {
  const _ModuleToggle({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Stitch.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w500,
                    color: Stitch.onSurface,
                  ),
                ),
              ),
              // Custom toggle
              Container(
                width: 48,
                height: 24,
                decoration: BoxDecoration(
                  color: value ? Stitch.primary : Stitch.containerHighest,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      offset: Offset(0, 2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: value ? Stitch.onPrimary : Stitch.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


