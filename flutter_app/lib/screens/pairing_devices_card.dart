import 'dart:async';

import 'package:flutter/material.dart';

import '../services/monitoring_client.dart';
import '../theme.dart';

/// Live list of paired companion tokens for the desktop settings screen.
///
/// Admin surface: shows device name (or Unknown), a token preview, and time
/// until expiry; each row revokes individually. The backend never returns
/// the secret itself, only an 8-character preview.
class PairingDevicesCard extends StatefulWidget {
  const PairingDevicesCard({
    super.key,
    required this.client,
    required this.onShowQr,
  });

  final MonitoringClient client;
  final VoidCallback onShowQr;

  @override
  State<PairingDevicesCard> createState() => _PairingDevicesCardState();
}

class _PairingDevicesCardState extends State<PairingDevicesCard> {
  List<PairingDevice>? _devices;
  bool _failed = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // Keep the expiry countdowns honest without per-second churn.
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final devices = await widget.client.listPairings();
      if (!mounted) return;
      setState(() { _devices = devices; _failed = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _failed = true; });
    }
  }

  Future<void> _revoke(PairingDevice device) async {
    // Optimistic removal; restored on failure.
    setState(() { _devices?.remove(device); });
    try {
      final ok = await widget.client.revokePairing(device.tokenPreview);
      if (!ok) throw Exception('no matching companion token');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not revoke ${_displayName(device)}'),
        backgroundColor: AppColors.alertRed,
      ));
      _load();
    }
  }

  String _displayName(PairingDevice device) =>
      device.deviceName.trim().isEmpty ? 'Unknown' : device.deviceName;

  String _remaining(PairingDevice device) {
    final left = device.expiresAt.difference(DateTime.now());
    if (left.isNegative) return 'EXPIRED';
    final h = left.inHours;
    final m = left.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}m left' : '${m}m left';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('PAIRED DEVICES',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.textSecondary)),
          const Spacer(),
          if (_devices != null && _devices!.isNotEmpty)
            IconButton(
              key: const Key('pairing-refresh-icon'),
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh, size: 18),
              color: AppColors.textSecondary,
              onPressed: _load,
            ),
        ]),
        const SizedBox(height: 4),
        _buildBody(),
      ],
    );
  }

  Widget _buildBody() {
    if (_failed) {
      return Row(children: [
        Text('Could not load paired devices.',
            style: TextStyle(
                fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(width: 12),
        OutlinedButton(
          key: const Key('pairing-list-retry'),
          onPressed: _load,
          child: const Text('RETRY'),
        ),
      ]);
    }
    final devices = _devices;
    if (devices == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (devices.isEmpty) {
      return Text('No paired devices. Pair one with the QR button below.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary));
    }
    return Column(
      children: [
        for (final device in devices)
          _buildTile(context, device),
      ],
    );
  }

  Widget _buildTile(BuildContext context, PairingDevice device) {
    final expired = device.isExpired;
    return Container(
      key: Key('pairing-device-${device.tokenPreview}'),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0x33444748), width: 0.5),
        ),
      ),
      child: Row(children: [
        Icon(
          expired ? Icons.phone_disabled : Icons.smartphone,
          size: 20,
          color: expired ? AppColors.offlineYellow : AppColors.textSecondary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_displayName(device),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(
                '${device.tokenPreview} • ${_remaining(device)}',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: expired
                      ? AppColors.offlineYellow
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Revoke device',
          icon: const Icon(Icons.delete_outline, size: 20),
          color: AppColors.alertRed,
          onPressed: () => _revoke(device),
        ),
      ]),
    );
  }
}
