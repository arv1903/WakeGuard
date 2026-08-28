import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/connection_service.dart';
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
  bool _telegramEnabled = true;
  bool _alarmEnabled = true;
  bool _sessionLogging = false;
  bool _forgetting = false;

  // Threshold values
  double _attentionSensitivity = 85;
  int _drowsyDetection = 2; // 0=Low, 1=Medium, 2=High
  double _perclosTolerance = 12;

  @override
  void initState() {
    super.initState();
    widget.connectionService.addListener(_onUpdate);
  }

  @override
  void dispose() {
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
                  decoration: const BoxDecoration(
                    color: Stitch.secondary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'NODE ACTIVE // UPLINK SECURE',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w500,
                    color: Stitch.onSurfaceVariant,
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
          Text(
            'Current Profile',
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
              const Text(
                'Standard Night Drive',
                style: TextStyle(
                  fontSize: 20,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w600,
                  color: Stitch.onSurface,
                ),
              ),
              const Icon(Icons.check_circle, color: Stitch.secondary, size: 20),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: Stitch.containerHigh,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () {},
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.tune, size: 18, color: Stitch.primary),
                      SizedBox(width: 8),
                      Text(
                        'INITIATE RECALIBRATION',
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'JetBrains Mono',
                          fontWeight: FontWeight.w700,
                          color: Stitch.primary,
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
            label: 'Attention Sensitivity',
            value: '${_attentionSensitivity.round()}%',
            color: Stitch.primary,
            sliderValue: _attentionSensitivity / 100,
            activeColor: Stitch.primary,
            onChanged: (v) => setState(() => _attentionSensitivity = v * 100),
          ),
          const SizedBox(height: 20),
          _ThresholdSlider(
            label: 'Drowsy Detection',
            value: ['Low', 'Medium', 'High'][_drowsyDetection],
            color: Stitch.tertiaryFixedDim,
            sliderValue: _drowsyDetection / 2,
            activeColor: Stitch.tertiaryFixedDim,
            onChanged: (v) => setState(() => _drowsyDetection = (v * 2).round()),
          ),
          const SizedBox(height: 20),
          _ThresholdSlider(
            label: 'PERCLOS Tolerance',
            value: '${_perclosTolerance.round()}%',
            color: Stitch.secondary,
            sliderValue: _perclosTolerance / 30,
            activeColor: Stitch.secondary,
            onChanged: (v) => setState(() => _perclosTolerance = v * 30),
          ),
        ],
      ),
    );
  }

  Widget _buildModulesCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Stitch.surfaceLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _ModuleToggle(
            icon: Icons.send,
            title: 'Telegram Notifications',
            value: _telegramEnabled,
            onChanged: (v) => setState(() => _telegramEnabled = v),
          ),
          _Divider(),
          _ModuleToggle(
            icon: Icons.volume_up,
            title: 'Alarm Sound',
            value: _alarmEnabled,
            onChanged: (v) => setState(() => _alarmEnabled = v),
          ),
          _Divider(),
          _ModuleToggle(
            icon: Icons.data_saver_on,
            title: 'Session Logging',
            value: _sessionLogging,
            onChanged: (v) => setState(() => _sessionLogging = v),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard() {
    final email = widget.authService.email ?? 'user@example.com';
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
              onTap: () {},
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: const Text(
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

// ─── Divider ────────────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: Stitch.containerHighest,
    );
  }
}
