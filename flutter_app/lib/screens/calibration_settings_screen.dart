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
  String _selectedPreset = 'Balanced';

  late Map<String, bool> _moduleState;

  static const Map<String, Map<String, double>> _presetValues = {
    'Alert': {
      'ear_threshold': 0.15,
      'microsleep_duration': 0.8,
      'pitch_threshold': 10.0,
      'yaw_threshold': 15.0,
      'roll_threshold': 6.0,
    },
    'Balanced': {
      'ear_threshold': 0.20,
      'microsleep_duration': 1.5,
      'pitch_threshold': 20.0,
      'yaw_threshold': 30.0,
      'roll_threshold': 10.0,
    },
    'Relaxed': {
      'ear_threshold': 0.25,
      'microsleep_duration': 2.5,
      'pitch_threshold': 28.0,
      'yaw_threshold': 38.0,
      'roll_threshold': 18.0,
    },
  };

  @override
  void initState() {
    super.initState();
    _ringCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 4));
    _lastCalibrationState = widget.client.snapshot.calibrationState;
    // Read persistent settings from the client so they survive tab switches.
    final c = widget.client;
    _selectedPreset = c.selectedPreset;
    _moduleState = {
      'telegram_enabled': c.telegramEnabled,
      'alarm_enabled': c.alarmEnabled,
      'logging_enabled': c.loggingEnabled,
    };
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

  Future<void> _applyPreset(String name) async {
    final values = _presetValues[name]!;
    setState(() => _selectedPreset = name);
    widget.client.selectedPreset = name;
    for (final entry in values.entries) {
      await _sendSetting(entry.key, entry.value);
    }
  }

  Future<void> _toggleModule(String key, bool value) async {
    setState(() => _moduleState[key] = value);
    // Persist to client so it survives tab switches.
    if (key == 'alarm_enabled') widget.client.alarmEnabled = value;
    if (key == 'telegram_enabled') widget.client.telegramEnabled = value;
    if (key == 'logging_enabled') widget.client.loggingEnabled = value;
    try {
      await widget.client.sendCommand('/api/v1/settings', {key: value});
    } catch (_) {
      setState(() => _moduleState[key] = !value);
      if (key == 'alarm_enabled') widget.client.alarmEnabled = !value;
      if (key == 'telegram_enabled') widget.client.telegramEnabled = !value;
      if (key == 'logging_enabled') widget.client.loggingEnabled = !value;
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
            content: Text('Calibration started -- keep looking straight ahead'),
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
        _buildSensitivitySection(),
        const SizedBox(height: 24),
        _buildModulesSection(),
      ]),
    ));
  }

  Widget _buildSensitivitySection() {
    final presets = [
      (
        name: 'Alert',
        icon: Icons.warning_amber_rounded,
        description: 'Detects issues early with tighter thresholds',
        color: AppColors.alertOrange,
      ),
      (
        name: 'Balanced',
        icon: Icons.check_circle_outline,
        description: 'Recommended for most drivers',
        color: AppColors.focusedGreen,
      ),
      (
        name: 'Relaxed',
        icon: Icons.do_not_disturb_on_outlined,
        description: 'Fewer false alerts, more leeway',
        color: AppColors.accent,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 700;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0x44444748))),
                    child: const Icon(Icons.tune,
                        size: 18, color: AppColors.textPrimary)),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text('Detection Sensitivity',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary))),
              ]),
              const SizedBox(height: 4),
              const Text(
                  'Choose how aggressively the system monitors for drowsiness and distraction.',
                  style:
                      TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              if (isNarrow)
                Column(
                    children: presets
                        .map((p) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _SensitivityPreset(
                                name: p.name,
                                icon: p.icon,
                                description: p.description,
                                accentColor: p.color,
                                selected: _selectedPreset == p.name,
                                onTap: () => _applyPreset(p.name),
                              ),
                            ))
                        .toList())
              else
                Row(
                    children: presets
                        .map((p) => Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                    right: p != presets.last ? 12 : 0),
                                child: _SensitivityPreset(
                                  name: p.name,
                                  icon: p.icon,
                                  description: p.description,
                                  accentColor: p.color,
                                  selected: _selectedPreset == p.name,
                                  onTap: () => _applyPreset(p.name),
                                ),
                              ),
                            ))
                        .toList()),
            ],
          );
        }),
      ),
    );
  }

  Future<void> _resetToDefaults() async {
    try {
      await widget.client
          .sendCommand('/api/v1/settings', _presetValues['Balanced']!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings reset to defaults.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _selectedPreset = 'Balanced');
        widget.client.selectedPreset = 'Balanced';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Reset failed: $e'),
            backgroundColor: AppColors.alertRed));
      }
    }
  }

  Widget _buildModulesSection() {
    return Card(
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
        return Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 24,
            runSpacing: 12,
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
    ));
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

// --- Calibration Ring Painter ---

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

    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = AppColors.surface2
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8);

    final sweepAngle = 2 * math.pi * progress;
    if (sweepAngle > 0) {
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

// --- Helper Widgets ---

class _SensitivityPreset extends StatelessWidget {
  const _SensitivityPreset({
    required this.name,
    required this.icon,
    required this.description,
    required this.accentColor,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final IconData icon;
  final String description;
  final Color accentColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? accentColor.withValues(alpha: 0.08)
          : AppColors.surface2,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? accentColor.withValues(alpha: 0.6)
                  : const Color(0x44444748),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 20, color: accentColor),
                const SizedBox(width: 8),
                Text(name,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: selected ? accentColor : AppColors.textPrimary)),
              ]),
              const SizedBox(height: 6),
              Text(description,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
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
