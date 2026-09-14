import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/monitoring_client.dart';
import '../theme.dart';

/// Renders the live MJPEG camera feed from [MonitoringClient.latestFrameBytes].
///
/// Decodes at most one frame per [minDecodeInterval] and always keeps only
/// the newest frame, so a slow UI can never fall behind the camera. Shared
/// by the desktop and mobile live monitors.
class MjpegView extends StatefulWidget {
  const MjpegView({super.key, required this.client});

  final MonitoringClient client;

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> {
  ui.Image? _frame;
  bool _decoding = false;
  Uint8List? _pendingBytes;
  DateTime _lastDecodeTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Minimum interval between decodes to prevent CPU thrashing
  static const _minDecodeInterval = Duration(milliseconds: 30);

  @override
  void initState() {
    super.initState();
    widget.client.latestFrameBytes.addListener(_onFrame);
    final existing = widget.client.latestFrameBytes.value;
    if (existing != null) _onFrame();
  }

  @override
  void didUpdateWidget(MjpegView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      oldWidget.client.latestFrameBytes.removeListener(_onFrame);
      _pendingTimer?.cancel();
      _pendingTimer = null;
      _pendingBytes = null;
      final oldFrame = _frame;
      _frame = null;
      _decoding = false;
      widget.client.latestFrameBytes.addListener(_onFrame);
      oldFrame?.dispose();
      final existing = widget.client.latestFrameBytes.value;
      if (existing != null) _onFrame();
    }
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    widget.client.latestFrameBytes.removeListener(_onFrame);
    _frame?.dispose();
    _decoding = false;
    super.dispose();
  }

  void _onFrame() {
    final bytes = widget.client.latestFrameBytes.value;
    if (bytes == null) return;
    if (_decoding) {
      // A decode is in progress — keep only the latest frame, discard stale ones
      _pendingBytes = bytes;
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastDecodeTime) < _minDecodeInterval &&
        _frame != null) {
      // Too soon after last decode and we already have a frame — queue it
      _pendingBytes = bytes;
      _schedulePendingDecode();
      return;
    }
    _decode(bytes);
  }

  Timer? _pendingTimer;
  void _schedulePendingDecode() {
    if (_pendingTimer != null) return;
    _pendingTimer = Timer(_minDecodeInterval, () {
      _pendingTimer = null;
      if (!mounted) return;
      final pending = _pendingBytes;
      if (pending != null && !_decoding) {
        _pendingBytes = null;
        _decode(pending);
      }
    });
  }

  void _decode(Uint8List bytes) {
    _decoding = true;
    _lastDecodeTime = DateTime.now();
    ui.instantiateImageCodec(bytes).then((codec) {
      if (!mounted || !_decoding) {
        codec.dispose();
        return;
      }
      codec.getNextFrame().then((info) {
        if (!mounted || !_decoding) {
          info.image.dispose();
          codec.dispose();
          return;
        }
        codec.dispose();
        final oldFrame = _frame;
        _frame = info.image;
        _decoding = false;
        setState(() {});
        oldFrame?.dispose();
        // If new frames arrived while we were decoding, process the latest
        final pending = _pendingBytes;
        if (pending != null) {
          _pendingBytes = null;
          _decode(pending);
        }
      }).catchError((_) {
        _decoding = false;
      });
    }).catchError((_) {
      _decoding = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    if (frame == null) {
      return const ColoredBox(
          color: Stitch.surfaceLow, child: _CameraLoadingPlaceholder());
    }
    return RawImage(
        image: frame, fit: BoxFit.cover, filterQuality: FilterQuality.medium);
  }
}

// ─── Camera Loading Placeholder with Scanning Animation ────────────────────

class _CameraLoadingPlaceholder extends StatelessWidget {
  const _CameraLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(size: Size.infinite, painter: _GridPainter()),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.videocam_outlined, size: 24, color: Stitch.onSurfaceVariant),
          SizedBox(height: 12),
          Text('Connecting to camera...',
              style: TextStyle(
                  color: Stitch.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          SizedBox(height: 6),
          SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                  minHeight: 2)),
        ]),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 1;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
