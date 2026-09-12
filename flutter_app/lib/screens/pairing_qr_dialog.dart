import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/monitoring_client.dart';
import '../services/pairing_qr.dart';
import '../theme.dart';

/// Desktop-side pairing: shows the backend's one-time code as a QR code so a
/// phone can pair by scanning — for networks where UDP discovery is blocked.
///
/// The QR payload embeds this desktop's own baseUrl (host + port) plus the
/// one-time code; the phone exchanges the code for a scoped bearer token via
/// the existing unauthenticated `/api/v1/pairing/exchange` endpoint.
class PairingQrDialog extends StatefulWidget {
  const PairingQrDialog({super.key, required this.client});

  final MonitoringClient client;

  @override
  State<PairingQrDialog> createState() => _PairingQrDialogState();
}

class _PairingQrDialogState extends State<PairingQrDialog> {
  PairingQrPayload? _payload;
  DateTime? _expiresAt;
  bool _failed = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.client.fetchPairing();
      final uri = Uri.tryParse(widget.client.baseUrl);
      final host = uri?.host ?? '';
      if (!mounted) return;
      if (host.isEmpty) {
        setState(() { _failed = true; });
        return;
      }
      final expiresAt = data['expires_at'];
      setState(() {
        _payload = PairingQrPayload(
          code: (data['code'] as String? ?? '').trim(),
          host: host,
          port: (uri?.port != 0 ? uri?.port : null) ?? 8765,
        );
        _expiresAt = expiresAt is num
            ? DateTime.fromMillisecondsSinceEpoch((expiresAt * 1000).toInt())
            : null;
        _failed = false;
      });
      _startTicker();
    } catch (_) {
      if (!mounted) return;
      setState(() { _failed = true; _payload = null; });
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final left = _timeLeft;
      setState(() {});
      // Auto-refresh once the code window lapses so the dialog never shows
      // a dead QR.
      if (_payload != null && left <= Duration.zero) _load();
    });
  }

  Duration get _timeLeft {
    if (_expiresAt == null) return Duration.zero;
    final diff = _expiresAt!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  String get _countdownText {
    final left = _timeLeft;
    final m = left.inMinutes;
    final s = left.inSeconds.remainder(60);
    return 'EXPIRES IN $m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        key: const Key('pairing-qr-dialog'),
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.qr_code_2, size: 20, color: AppColors.accent),
              const SizedBox(width: 10),
              Text('PAIR A PHONE',
                  style: AppTextStyles.labelCaps.copyWith(
                      fontSize: 14, color: AppColors.textPrimary)),
              const Spacer(),
              IconButton(
                key: const Key('pairing-close'),
                icon: const Icon(Icons.close, size: 18),
                color: AppColors.textSecondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              'Scan with the WakeGuard mobile app. '
              'The code is single-use and rotates automatically.',
              style: AppTextStyles.bodySm
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            if (_failed)
              _buildFailure()
            else if (_payload == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
              )
            else
              _buildQr(),
          ],
        ),
      ),
    );
  }

  Widget _buildQr() {
    return Column(children: [
      Center(
        key: const Key('pairing-qr'),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: _payload!.toJson(),
            version: QrVersions.auto,
            size: 200,
            backgroundColor: Colors.white,
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        _payload!.code,
        key: const Key('pairing-code'),
        style: AppTextStyles.mono.copyWith(
            fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 4),
      ),
      if (_expiresAt != null) ...[
        const SizedBox(height: 6),
        Text(_countdownText,
            style: AppTextStyles.labelSm
                .copyWith(color: AppColors.textSecondary)),
      ],
      const SizedBox(height: 16),
      OutlinedButton(
        key: const Key('pairing-refresh'),
        onPressed: _load,
        child: const Text('REFRESH'),
      ),
    ]);
  }

  Widget _buildFailure() {
    return Column(children: [
      const Icon(Icons.wifi_off, size: 32, color: AppColors.offlineYellow),
      const SizedBox(height: 12),
      Text('Could not reach the backend to generate a pairing code.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySm
              .copyWith(color: AppColors.textSecondary)),
      const SizedBox(height: 16),
      OutlinedButton(
        key: const Key('pairing-retry'),
        onPressed: _load,
        child: const Text('RETRY'),
      ),
    ]);
  }
}
