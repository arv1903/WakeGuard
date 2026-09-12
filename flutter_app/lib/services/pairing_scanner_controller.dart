import 'dart:async';

import 'package:mobile_scanner/mobile_scanner.dart';

import 'pairing_qr.dart';

/// Decouples [PairingScannerScreen] from the real camera so tests can inject
/// QR payloads directly. The default implementation drives a
/// [MobileScannerController]; tests override [start]/[stop] as no-ops.
class PairingScannerController {
  MobileScannerController? _scanner;

  /// Called by the screen with every raw camera payload; implementors parse
  /// and invoke [onPayload] (or [onError]) exactly once per code.
  void Function(PairingQrPayload payload)? onPayload;
  void Function(String message)? onError;

  /// Simulates a scan in tests by feeding the raw QR string directly.
  void handleRawPayload(String raw) => _handleBarcode(raw);

  void _handleBarcode(String raw) {
    final payload = PairingQrPayload.tryParse(raw);
    if (payload == null) {
      onError?.call('Not a WakeGuard QR code.');
      return;
    }
    onPayload?.call(payload);
  }

  Future<void> start() async {
    _scanner = MobileScannerController(
      detectionTimeoutMs: 1500,
      formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    );
    _scanner!.barcodes.listen((capture) {
      for (final barcode in capture.barcodes) {
        final raw = barcode.rawValue;
        if (raw != null && raw.isNotEmpty) _handleBarcode(raw);
      }
    });
    await _scanner!.start();
  }

  Future<void> stop() async {
    await _scanner?.stop();
    _scanner?.dispose();
    _scanner = null;
  }
}
