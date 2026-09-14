import 'package:flutter/material.dart';

import '../services/connection_service.dart';
import '../services/pairing_scanner_controller.dart';
import '../theme.dart';

/// Full-screen QR scanner for pairing with the desktop backend.
///
/// The scanned payload (see `PairingQrPayload`) carries the desktop's LAN
/// address plus a one-time pairing code. This screen points the client at
/// that address, exchanges the code for a scoped bearer token via the
/// unauthenticated `/api/v1/pairing/exchange`, and pops on success — the
/// shell takes over once `ConnectionService.isPaired` flips.
class PairingScannerScreen extends StatefulWidget {
  const PairingScannerScreen({
    super.key,
    required this.connectionService,
    PairingScannerController? controller,
  }) : _controller = controller;

  final ConnectionService connectionService;

  /// Injectable for tests; defaults to the real camera controller.
  final PairingScannerController? _controller;

  @override
  State<PairingScannerScreen> createState() => _PairingScannerScreenState();
}

class _PairingScannerScreenState extends State<PairingScannerScreen> {
  late final PairingScannerController _controller;
  bool _pairing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = widget._controller ?? PairingScannerController();
    _controller.onPayload = _pairWith;
    _controller.onError = (message) {
      if (!mounted) return;
      setState(() { _error = message; });
    };
    // Camera start may fail on platform unsupported (tests/desktop) — the
    // placeholder keeps the screen meaningful either way.
    _controller.start().catchError((Object _) {});
  }

  @override
  void dispose() {
    _controller.onPayload = null;
    _controller.onError = null;
    _controller.stop();
    super.dispose();
  }

  Future<void> _pairWith(payload) async {
    if (_pairing) return; // debounce repeated camera frames
    setState(() { _pairing = true; _error = null; });
    try {
      await widget.connectionService.connectTo(payload.url);
      await widget.connectionService.completePairing(payload.code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pairing = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Stitch.background,
      appBar: AppBar(
        backgroundColor: Stitch.background,
        foregroundColor: Stitch.onSurface,
        title: const Text(
          'Scan Pairing QR',
          style: TextStyle(
            fontSize: 16,
            fontFamily: 'JetBrains Mono',
            fontWeight: FontWeight.w600,
            color: Stitch.onSurface,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildCameraArea()),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'On the desktop: Settings → Companion Devices → SHOW PAIRING QR.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Stitch.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraArea() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Camera preview when available; neutral surface otherwise.
        Positioned.fill(
          child: Container(
            color: Stitch.surfaceLowest,
            child: Center(
              child: Icon(Icons.qr_code_scanner,
                  size: 72,
                  color: Stitch.onSurfaceVariant.withValues(alpha: 0.4)),
            ),
          ),
        ),
        // Status / error overlay.
        if (_pairing)
          _OverlayCard(
            icon: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Stitch.primary),
            ),
            text: 'Pairing with desktop…',
          )
        else if (_error != null)
          _OverlayCard(
            icon: const Icon(Icons.error_outline, size: 18, color: Stitch.error),
            text: _error!,
          ),
      ],
    );
  }
}

class _OverlayCard extends StatelessWidget {
  const _OverlayCard({required this.icon, required this.text});

  final Widget icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Stitch.container,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Stitch.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: Stitch.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
