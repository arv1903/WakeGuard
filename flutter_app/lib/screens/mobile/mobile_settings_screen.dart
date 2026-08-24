import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/connection_service.dart';
import '../../services/monitoring_client.dart';
import '../../theme.dart';

/// Mobile settings screen matching the Stitch "Settings" mockup.
///
/// Shows connection info, preference toggles, and Forget Device.
class MobileSettingsScreen extends StatefulWidget {
  const MobileSettingsScreen({
    super.key,
    required this.connectionService,
    this.onForgetDevice,
  });

  final ConnectionService connectionService;
  final VoidCallback? onForgetDevice;

  @override
  State<MobileSettingsScreen> createState() => _MobileSettingsScreenState();
}

class _MobileSettingsScreenState extends State<MobileSettingsScreen> {
  bool _alertSounds = true;
  bool _hapticFeedback = true;
  bool _forgetting = false;

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
      if (mounted) {
        widget.onForgetDevice?.call();
      }
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
    final cs = widget.connectionService;
    final connected =
        cs.client.connectionState == BackendConnectionState.connected;

    return Container(
      color: Stitch.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Connection section ──
            _sectionHeader('Connection'),
            const SizedBox(height: 8),
            _buildConnectionCard(connected, cs),
            const SizedBox(height: 24),

            // ── Preferences section ──
            _sectionHeader('Preferences'),
            const SizedBox(height: 8),
            _buildPreferencesCard(),
            const SizedBox(height: 24),

            // ── Device section ──
            _sectionHeader('Device'),
            const SizedBox(height: 8),
            _buildForgetButton(),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Disconnecting will clear local telemetry caches\nand require re-pairing via standard protocols.',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'JetBrains Mono',
                  color: Stitch.onSurfaceVariant.withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontFamily: 'JetBrains Mono',
        fontWeight: FontWeight.w500,
        color: Stitch.primary,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildConnectionCard(bool connected, ConnectionService cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Stitch.container,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status + ping
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Stitch.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated ping dot
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (connected)
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Stitch.secondary.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                            ),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: connected
                                  ? Stitch.secondary
                                  : Stitch.onSurfaceVariant,
                              shape: BoxShape.circle,
                              boxShadow: connected
                                  ? [
                                      BoxShadow(
                                        color: Stitch.secondary
                                            .withValues(alpha: 0.6),
                                        blurRadius: 6,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      connected ? 'NODE ACTIVE' : 'OFFLINE',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'JetBrains Mono',
                        fontWeight: FontWeight.w500,
                        color: connected
                            ? Stitch.secondary
                            : Stitch.onSurfaceVariant,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Icon(Icons.signal_cellular_alt,
                      size: 14, color: Stitch.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    connected ? '32ms' : '—',
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'JetBrains Mono',
                      fontWeight: FontWeight.w500,
                      color: Stitch.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Backend address
          const Text(
            'Backend Address',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.w500,
              color: Stitch.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Stitch.containerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    cs.backendUrl ?? '—',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'JetBrains Mono',
                      fontWeight: FontWeight.w500,
                      color: Stitch.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    if (cs.backendUrl != null) {
                      // Copy to clipboard
                    }
                  },
                  child: const Icon(Icons.content_copy,
                      size: 18, color: Stitch.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Token expiry
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Session Token Expiry',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'JetBrains Mono',
                      fontWeight: FontWeight.w500,
                      color: Stitch.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cs.tokenExpiryFormatted,
                    style: const TextStyle(
                      fontSize: 14,
                      fontFamily: 'JetBrains Mono',
                      fontWeight: FontWeight.w500,
                      color: Stitch.primaryFixedDim,
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Stitch.surfaceBright,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'REFRESH',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                    color: Stitch.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Stitch.container,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        children: [
          _ToggleRow(
            icon: Icons.volume_up,
            title: 'Alert Sounds',
            subtitle: 'Audio warnings for critical events',
            value: _alertSounds,
            onChanged: (v) => setState(() => _alertSounds = v),
          ),
          _ToggleRow(
            icon: Icons.vibration,
            title: 'Haptic Feedback',
            subtitle: 'Physical vibration alerts',
            value: _hapticFeedback,
            onChanged: (v) => setState(() => _hapticFeedback = v),
          ),
        ],
      ),
    );
  }

  Widget _buildForgetButton() {
    return GestureDetector(
      onTap: _forgetting ? null : _forgetDevice,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Stitch.errorContainer.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Stitch.error.withValues(alpha: 0.8),
            width: 1.5,
          ),
        ),
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
                : const Icon(Icons.delete_forever, color: Stitch.error),
            const SizedBox(width: 8),
            const Text(
              'FORGET THIS DEVICE',
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'JetBrains Mono',
                fontWeight: FontWeight.w500,
                color: Stitch.error,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Toggle Row ──────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: Stitch.containerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Icon circle
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Stitch.containerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: Stitch.onSurfaceVariant),
                ),
                const SizedBox(width: 14),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Stitch.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'JetBrains Mono',
                          fontWeight: FontWeight.w500,
                          color: Stitch.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Toggle
                SizedBox(
                  width: 48,
                  height: 26,
                  child: Switch(
                    value: value,
                    onChanged: onChanged,
                    activeThumbColor: Stitch.primary,
                    activeTrackColor: Stitch.primary.withValues(alpha: 0.2),
                    inactiveThumbColor: Stitch.outline,
                    inactiveTrackColor: Stitch.surfaceLowest,
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
