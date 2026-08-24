import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/monitoring_client.dart';
import '../theme.dart';

class CalibrationSettingsScreen extends StatefulWidget {
  const CalibrationSettingsScreen({super.key, required this.client});
  final MonitoringClient client;
  @override
  State<CalibrationSettingsScreen> createState() =>
      _CalibrationSettingsScreenState();
}

class _CalibrationSettingsScreenState extends State<CalibrationSettingsScreen>
    with SingleTickerProviderStateMixin {
  bool _commandPending = false;
  String? _lastCalibrationState;
  late AnimationController _ringCtrl;
  late Map<String, double> _thresholds;

  /// Module toggle state — owned here so it survives widget rebuilds.
  final Map<String, bool> _moduleState = {
    'telegram_enabled': true,
    'alarm_enabled': true,
    'logging_enabled': false,
  };

  @override
  void initState() {
    super.initState();
    _thresholds = Map<String, double>.from(_defaults);
    _ringCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 4));
    _lastCalibrationState = widget.client.snapshot.calibrationState;
    widget.client.addListener(_onClientUpdate);
    if (_lastCalibrationState == 'running') _ringCtrl.repeat();
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    widget.client.removeListener(_onClientUpdate);
    super.dispose();
  }

  void _onClientUpdate() {
    if (!mounted) return;
    final state = widget.client.snapshot.calibrationState;
    if (state != _lastCalibrationState) {
      _lastCalibrationState = state;
      if (state == 'running') {
        _ringCtrl.repeat();
      } else {
        _ringCtrl.stop();
      }
      _commandPending = false;
      if (state == 'succeeded') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Calibration completed successfully'),
          backgroundColor: AppColors.focusedGreen,
          duration: Duration(seconds: 2),
        ));
      } else if (state == 'failed') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              widget.client.snapshot.calibrationError ?? 'Calibration failed'),
          backgroundColor: AppColors.alertRed,
        ));
      }
    }
    setState(() {});
  }

  Future<void> _sendSetting(String key, double value) async {
    try {
      await widget.client.sendCommand('/api/v1/settings', {key: value});
    } catch (_) {}
  }

  Future<void> _toggleModule(String key, bool value) async {
    setState(() => _moduleState[key] = value);
    try {
      await widget.client.sendCommand('/api/v1/settings', {key: value});
    } catch (_) {
      // Revert on failure
      setState(() => _moduleState[key] = !value);
    }
  }

  Future<void> _startCalibration() async {
    setState(() => _commandPending = true);
    _ringCtrl.reset();
    try {
      await widget.client
          .sendCommand('/api/v1/calibration/start', {'duration': 4});
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Calibration started — keep looking straight ahead'),
            duration: Duration(seconds: 2)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Calibration failed: $e'),
            backgroundColor: AppColors.alertRed));
        setState(() => _commandPending = false);
        _ringCtrl.reset();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
        child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(header: true, child: _buildHeader()),
        const SizedBox(height: 24),
        _buildCalibrationCard(),
        const SizedBox(height: 24),
        LayoutBuilder(builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 1100;
          if (isNarrow) {
            return Column(children: [
              _ThresholdCard(
                icon: Icons.visibility,
                title: 'Eye & EAR Thresholds',
                children: [
                  _slider('EarClosed (EAR Threshold)', 'ear_threshold', 0.10,
                      0.30, (v) => v.toStringAsFixed(2)),
                  const SizedBox(height: 24),
                  _slider('Microsleep Duration (s)', 'microsleep_duration', 0.5,
                      3.5, (v) => '${v.toStringAsFixed(1)}s'),
                ],
              ),
              const SizedBox(height: 24),
              _ThresholdCard(
                icon: Icons.threed_rotation,
                title: 'Head Pose Distraction',
                children: [
                  _slider('Pitch (Up/Down) \u00B1\u00B0', 'pitch_threshold', 5,
                      30, (v) => '${v.toStringAsFixed(1)}\u00B0'),
                  const SizedBox(height: 24),
                  _slider('Yaw (Left/Right) \u00B1\u00B0', 'yaw_threshold', 10,
                      40, (v) => '${v.toStringAsFixed(1)}\u00B0'),
                  const SizedBox(height: 24),
                  _slider('Roll (Tilt) \u00B1\u00B0', 'roll_threshold', 5, 20,
                      (v) => '${v.toStringAsFixed(1)}\u00B0'),
                ],
              ),
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: _ThresholdCard(
              icon: Icons.visibility,
              title: 'Eye & EAR Thresholds',
              children: [
                _slider('EarClosed (EAR Threshold)', 'ear_threshold', 0.10,
                    0.30, (v) => v.toStringAsFixed(2)),
                const SizedBox(height: 24),
                _slider('Microsleep Duration (s)', 'microsleep_duration', 0.5,
                    3.5, (v) => '${v.toStringAsFixed(1)}s'),
              ],
            )),
            const SizedBox(width: 24),
            Expanded(
                child: _ThresholdCard(
              icon: Icons.threed_rotation,
              title: 'Head Pose Distraction',
              children: [
                _slider('Pitch (Up/Down) \u00B1\u00B0', 'pitch_threshold', 5,
                    30, (v) => '${v.toStringAsFixed(1)}\u00B0'),
                const SizedBox(height: 24),
                _slider('Yaw (Left/Right) \u00B1\u00B0', 'yaw_threshold', 10,
                    40, (v) => '${v.toStringAsFixed(1)}\u00B0'),
                const SizedBox(height: 24),
                _slider('Roll (Tilt) \u00B1\u00B0', 'roll_threshold', 5, 20,
                    (v) => '${v.toStringAsFixed(1)}\u00B0'),
              ],
            )),
          ]);
        }),
        const SizedBox(height: 24),
        Card(
            child: Padding(
          padding: const EdgeInsets.all(24),
          child: LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 900;
            if (narrow) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SYSTEM MODULES',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                  color: AppColors.textSecondary)),
                          SizedBox(height: 4),
                          Text('Enable or disable auxiliary output services.',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary)),
                        ]),
                    const SizedBox(height: 16),
                    Wrap(spacing: 16, runSpacing: 8, children: [
                      _ModuleToggle(
                          icon: Icons.photo_camera_outlined,
                          label: 'Telegram Snapshot',
                          value: _moduleState['telegram_enabled']!,
                          onChanged: (v) => _toggleModule('telegram_enabled', v)),
                      _ModuleToggle(
                          icon: Icons.volume_up,
                          label: 'Windows Audio Alarm',
                          value: _moduleState['alarm_enabled']!,
                          onChanged: (v) => _toggleModule('alarm_enabled', v)),
                      _ModuleToggle(
                          icon: Icons.subject,
                          label: 'Threaded Logging',
                          value: _moduleState['logging_enabled']!,
                          onChanged: (v) => _toggleModule('logging_enabled', v)),
                    ]),
                  ]);
            }
            return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SYSTEM MODULES',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: AppColors.textSecondary)),
                        SizedBox(height: 4),
                        Text('Enable or disable auxiliary output services.',
                            style: TextStyle(
                                fontSize: 14, color: AppColors.textSecondary)),
                      ]),
                  Row(children: [
                    _ModuleToggle(
                        icon: Icons.photo_camera_outlined,
                        label: 'Telegram Snapshot',
                        value: _moduleState['telegram_enabled']!,
                        onChanged: (v) => _toggleModule('telegram_enabled', v)),
                    const SizedBox(width: 24),
                    _ModuleToggle(
                        icon: Icons.volume_up,
                        label: 'Windows Audio Alarm',
                        value: _moduleState['alarm_enabled']!,
                        onChanged: (v) => _toggleModule('alarm_enabled', v)),
                    const SizedBox(width: 24),
                    _ModuleToggle(
                        icon: Icons.subject,
                        label: 'Threaded Logging',
                        value: _moduleState['logging_enabled']!,
                        onChanged: (v) => _toggleModule('logging_enabled', v)),
                  ]),
                ]);
          }),
        )),
      ]),
    ));
  }

  // Default values used by Reset to Defaults.
  static const _defaults = {
    'ear_threshold': 0.20,
    'microsleep_duration': 1.5,
    'pitch_threshold': 20.0,
    'yaw_threshold': 30.0,
    'roll_threshold': 10.0,
  };

  Widget _slider(String label, String key, double min, double max,
      String Function(double) format) {
    return _SliderRow(
      label: label,
      value: _thresholds[key]!,
      min: min,
      max: max,
      format: format,
      onChanged: (value) => setState(() => _thresholds[key] = value),
      onEnd: (value) => _sendSetting(key, value),
    );
  }

  Future<void> _resetToDefaults() async {
    try {
      await widget.client.sendCommand('/api/v1/settings', _defaults);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings reset to defaults.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _thresholds = Map<String, double>.from(_defaults));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Reset failed: $e'),
              backgroundColor: AppColors.alertRed),
        );
      }
    }
  }

  Widget _buildHeader() {
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 600;
      if (narrow) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('System Configuration & Calibration',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -1)),
          const SizedBox(height: 4),
          const Text('Adjust core Driver Monitoring System parameters.',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          Semantics(
              button: true,
              label: 'Reset settings to defaults',
              child: Material(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _resetToDefaults,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.restore,
                                  size: 18, color: AppColors.textSecondary),
                              SizedBox(width: 8),
                              Text('Reset to Defaults',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary)),
                            ])),
                  ))),
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('System Configuration & Calibration',
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -1)),
          SizedBox(height: 4),
          Text('Adjust core Driver Monitoring System parameters.',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
        ])),
        const SizedBox(width: 16),
        Semantics(
            button: true,
            label: 'Reset settings to defaults',
            child: Material(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _resetToDefaults,
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child:
                          Row(mainAxisSize: MainAxisSize.min, children: const [
                        Icon(Icons.restore,
                            size: 18, color: AppColors.textSecondary),
                        SizedBox(width: 8),
                        Text('Reset to Defaults',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.textSecondary)),
                      ])),
                ))),
      ]);
    });
  }

  Widget _buildCalibrationCard() {
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 600;
        if (narrow) {
          return Column(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: const [
                Icon(Icons.face_retouching_natural,
                    color: AppColors.textPrimary),
                SizedBox(width: 12),
                Flexible(
                    child: Text('Neutral Pose Auto-Calibration',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary))),
              ]),
              const SizedBox(height: 8),
              const Text(
                  'Look straight ahead with eyes open. The system will capture neutral head pose metrics from live camera frames.',
                  style:
                      TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            ]),
            const SizedBox(height: 24),
            _calibrationProgress(),
          ]);
        }
        return Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: const [
                  Icon(Icons.face_retouching_natural,
                      color: AppColors.textPrimary),
                  SizedBox(width: 12),
                  Text('Neutral Pose Auto-Calibration',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ]),
                const SizedBox(height: 8),
                const Text(
                    'Look straight ahead with eyes open. The system will capture neutral head pose metrics from live camera frames.',
                    style: TextStyle(
                        fontSize: 14, color: AppColors.textSecondary)),
              ])),
          const SizedBox(width: 32),
          _calibrationProgress(),
        ]);
      }),
    ));
  }

  Widget _calibrationProgress() {
    final snap = widget.client.snapshot;
    final running = snap.calibrationState == 'running' || _commandPending;
    final progress = snap.calibrationProgress.clamp(0.0, 1.0);
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ringCtrl,
            builder: (context, _) {
              return CustomPaint(
                size: const Size(180, 180),
                painter: _CalibrationRingPainter(
                  progress: progress,
                  animValue: running ? _ringCtrl.value : 0,
                  active: running,
                ),
              );
            },
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${(progress * 100).round()}%',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: running
                        ? AppColors.focusedGreen
                        : AppColors.textPrimary,
                  )),
              if (running)
                Text('${snap.calibrationValidSamples} samples',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              SizedBox(
                width: 120,
                child: ElevatedButton(
                  onPressed: running ? null : _startCalibration,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.textPrimary,
                    foregroundColor: AppColors.surface0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Tooltip(
                    message: running
                        ? '${snap.calibrationValidSamples} valid samples'
                        : 'Start 4 second calibration',
                    child: Icon(running ? Icons.refresh : Icons.play_arrow,
                        size: 18),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Calibration Ring Painter ───────────────────────────────────────────────

class _CalibrationRingPainter extends CustomPainter {
  _CalibrationRingPainter(
      {required this.progress, required this.animValue, required this.active});
  final double progress;
  final double animValue;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    // Track
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = AppColors.surface2
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8);

    // Progress arc
    final sweepAngle = 2 * math.pi * progress;
    if (sweepAngle > 0) {
      // Glow
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweepAngle,
        false,
        Paint()
          ..color = AppColors.focusedGreen.withValues(alpha: 0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      // Stroke
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweepAngle,
        false,
        Paint()
          ..color = AppColors.focusedGreen
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round,
      );
    }

    // Animated rotating dot during calibration
    if (active) {
      final dotAngle = animValue * 2 * math.pi;
      final dotOffset = Offset(
        center.dx + radius * math.cos(dotAngle - math.pi / 2),
        center.dy + radius * math.sin(dotAngle - math.pi / 2),
      );
      canvas.drawCircle(
          dotOffset,
          5,
          Paint()
            ..color = AppColors.focusedGreen
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawCircle(dotOffset, 3, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_CalibrationRingPainter old) =>
      old.progress != progress ||
      old.animValue != animValue ||
      old.active != active;
}

// ─── Helper Widgets ─────────────────────────────────────────────────────────

class _ThresholdCard extends StatelessWidget {
  const _ThresholdCard(
      {required this.icon, required this.title, required this.children});
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0x44444748))),
              child: Icon(icon, size: 18, color: AppColors.textPrimary)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 16),
        ...children,
      ]),
    ));
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow(
      {required this.label,
      required this.value,
      required this.min,
      required this.max,
      required this.format,
      required this.onChanged,
      this.onEnd});
  final String label;
  final double value, min, max;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onEnd;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(4)),
          child: Text(format(value),
              style: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: AppColors.textPrimary)),
        ),
      ]),
      const SizedBox(height: 8),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          activeTrackColor: AppColors.textPrimary,
          inactiveTrackColor: AppColors.surface2,
          thumbColor: AppColors.textPrimary,
          overlayColor: AppColors.textPrimary.withValues(alpha: 0.1),
        ),
        child: Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeEnd: onEnd,
        ),
      ),
    ]);
  }
}

class _ModuleToggle extends StatelessWidget {
  const _ModuleToggle(
      {required this.icon,
      required this.label,
      required this.value,
      required this.onChanged});
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: AppColors.textSecondary),
      const SizedBox(width: 8),
      Text(label,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
      const SizedBox(width: 8),
      Switch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: AppColors.focusedGreen,
      ),
    ]);
  }
}
