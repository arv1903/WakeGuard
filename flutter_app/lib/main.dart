import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'models/monitoring_snapshot.dart';
import 'services/local_backend.dart';
import 'services/monitoring_client.dart';

// ─── Color System ───────────────────────────────────────────────────────────
// Deep navy surfaces — elevation through brightness alone, no borders.

class _C {
  _C._();

  // Surfaces (brightness order)
  static const background = Color(0xFF0a0e14);
  static const surface0 = Color(0xFF0e1219);
  static const surface1 = Color(0xFF131a24);
  static const surface2 = Color(0xFF19222e);

  // Text
  static const textPrimary = Color(0xFFe6edf3);
  static const textSecondary = Color(0xFF7d8590);
  static const textMuted = Color(0xFF484f58);

  // Accent
  static const accent = Color(0xFF22d3ee);

  // Semantic
  static const alertRed = Color(0xFFf87171);
  static const alertOrange = Color(0xFFfb923c);
  static const alertAmber = Color(0xFFfbbf24);
  static const focusedGreen = Color(0xFF34d399);
  static const offlineYellow = Color(0xFFfbbf24);

  // Gauge
  static const gaugeTrack = Color(0x15ffffff);

  static Color severity(int level) {
    if (level >= 4) return alertRed;
    if (level >= 3) return alertOrange;
    if (level >= 2) return alertAmber;
    return accent;
  }
}

// ─── Entry Point ────────────────────────────────────────────────────────────

void main() {
  const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://127.0.0.1:8765',
  );
  const autoStart = String.fromEnvironment(
    'AUTO_START_BACKEND',
    defaultValue: 'false',
  ) == 'true';
  runApp(DriverMonitorApp(apiUrl: apiUrl, autoStartBackend: autoStart));
}

class DriverMonitorApp extends StatefulWidget {
  const DriverMonitorApp({
    super.key,
    required this.apiUrl,
    required this.autoStartBackend,
  });

  final String apiUrl;
  final bool autoStartBackend;

  @override
  State<DriverMonitorApp> createState() => _DriverMonitorAppState();
}

class _DriverMonitorAppState extends State<DriverMonitorApp> {
  late final MonitoringClient client;
  late final LocalBackendProcess backend;

  @override
  void initState() {
    super.initState();
    client = MonitoringClient(baseUrl: widget.apiUrl);
    backend = LocalBackendProcess();
    if (widget.autoStartBackend) {
      unawaited(_startBackend());
    } else {
      client.connect();
    }
  }

  Future<void> _startBackend() async {
    await backend.start();
    if (mounted) client.connect();
  }

  @override
  void dispose() {
    client.dispose();
    unawaited(backend.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Driver Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: _C.background,
        colorSchemeSeed: _C.accent,
        cardTheme: const CardThemeData(
          color: _C.surface0,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: _C.surface1,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _C.surface2,
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide.none,
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide.none,
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: _C.accent, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
      home: DashboardPage(client: client),
    );
  }
}

// ─── Dashboard ──────────────────────────────────────────────────────────────

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.client});

  final MonitoringClient client;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: client,
      builder: (context, _) {
        final snap = client.snapshot;
        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 880;
                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 24 : 12,
                    vertical: wide ? 20 : 14,
                  ),
                  child: _DashboardContent(
                     client: client,
                     snapshot: snap,
                     wide: wide,
                     onCommandError: (e) => _showError(context, e),
                     onSummary: () => _showSummary(context),
                     onSettingsTap: () => _showConnectionDialog(context),
                     displayedStatus: client.displayedStatus,
                   ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────────────

  Future<void> _showConnectionDialog(BuildContext context) async {
    final urlCtrl = TextEditingController(text: client.baseUrl);
    final tokenCtrl = TextEditingController(text: client.token ?? '');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect to device'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Backend URL',
                  hintText: 'http://192.168.1.20:8765',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tokenCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Bearer token',
                ),
              ),
              if (client.token != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      try {
                        await client.forgetDevice();
                        tokenCtrl.clear();
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        tokenCtrl.clear();
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(e.toString())),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.link_off, size: 18),
                    label: const Text('Forget paired device'),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              client.configure(
                baseUrl: urlCtrl.text,
                token: tokenCtrl.text,
              );
              Navigator.pop(ctx);
              unawaited(_showPairingDialog(context));
            },
            child: const Text('Pair'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              client.configure(
                baseUrl: urlCtrl.text,
                token: tokenCtrl.text,
              );
              Navigator.pop(ctx);
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    urlCtrl.dispose();
    tokenCtrl.dispose();
  }

  Future<void> _showPairingDialog(BuildContext context) async {
    final codeCtrl = TextEditingController();
    String? pairingCode;
    String? message;
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> showCode() async {
            setState(() { busy = true; message = null; });
            try {
              final d = await client.fetchPairing();
              if (!ctx.mounted) return;
              setState(() {
                pairingCode = d['code'] as String?;
                codeCtrl.text = pairingCode ?? '';
                message = pairingCode == null
                    ? 'Backend did not return a pairing code.'
                    : 'Code expires soon. Share only with the paired device.';
              });
            } catch (e) {
              if (ctx.mounted) setState(() => message = e.toString());
            } finally {
              if (ctx.mounted) setState(() => busy = false);
            }
          }

          Future<void> pair() async {
            setState(() { busy = true; message = null; });
            try {
              await client.exchangePairing(codeCtrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              if (ctx.mounted) setState(() => message = e.toString());
            } finally {
              if (ctx.mounted) setState(() => busy = false);
            }
          }

          return AlertDialog(
            title: const Text('Pair companion device'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Reveal a local code on the desktop, then enter it '
                    'here on the companion device.',
                    style: TextStyle(color: _C.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Pairing code',
                      hintText: '8-character code',
                    ),
                  ),
                  if (pairingCode != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      pairingCode!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 6,
                        color: _C.accent,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                  if (message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _C.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : showCode,
                child: const Text('Reveal code'),
              ),
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: busy ? null : pair,
                child: Text(busy ? 'Pairing…' : 'Pair'),
              ),
            ],
          );
        },
      ),
    );
    codeCtrl.dispose();
  }

  void _showError(BuildContext context, Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }

  Future<void> _showSummary(BuildContext context) async {
    try {
      final s = await client.fetchCurrentSummary();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Trip summary'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryRow('Duration', '${_fmt(s['duration'])} s'),
              _summaryRow('Avg attention', _fmt(s['attention_avg'])),
              _summaryRow('Lowest attention', _fmt(s['attention_min'])),
              _summaryRow('Max PERCLOS', _fmtPct(s['perclos_max'])),
              _summaryRow('Alerts', '${s['alert_count'] ?? 0}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _C.textSecondary)),
          Text(value, style: const TextStyle(color: _C.textPrimary)),
        ],
      ),
    );
  }

  String _fmt(Object? v) => v is num ? v.toStringAsFixed(1) : '—';
  String _fmtPct(Object? v) => v is num ? '${(v * 100).toStringAsFixed(1)}%' : '—';
}

// ─── Layout ─────────────────────────────────────────────────────────────────

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.client,
    required this.snapshot,
    required this.wide,
    required this.onCommandError,
    required this.onSummary,
    this.onSettingsTap,
    this.displayedStatus,
  });

  final MonitoringClient client;
  final MonitoringSnapshot snapshot;
  final bool wide;
  final void Function(Object error) onCommandError;
  final VoidCallback onSummary;
  final VoidCallback? onSettingsTap;
  final String? displayedStatus;

  @override
  Widget build(BuildContext context) {
    final camera = _CameraView(client: client, snapshot: snapshot);
    final status = _StatusHero(snapshot: snapshot, client: client, onSettingsTap: onSettingsTap, displayedStatus: displayedStatus);
    final metrics = _MetricRow(snapshot: snapshot);

    if (wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: camera),
              const SizedBox(width: 16),
              Expanded(flex: 4, child: status),
            ],
          ),
          const SizedBox(height: 16),
          metrics,
          const SizedBox(height: 16),
          _ControlBar(
            client: client,
            onError: onCommandError,
            onSummary: onSummary,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        status,
        const SizedBox(height: 12),
        camera,
        const SizedBox(height: 12),
        metrics,
        const SizedBox(height: 12),
        _ControlBar(
          client: client,
          onError: onCommandError,
          onSummary: onSummary,
        ),
      ],
    );
  }
}

// ─── Connection Status ──────────────────────────────────────────────────────

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.client, this.onTap});

  final MonitoringClient client;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final connected =
        client.connectionState == BackendConnectionState.connected &&
            !client.isStale;
    final color = connected ? _C.focusedGreen : _C.offlineYellow;
    final label = connected
        ? 'Live'
        : client.connectionState == BackendConnectionState.connecting
            ? 'Connecting'
            : 'Offline';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 4)],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Status Hero ────────────────────────────────────────────────────────────

class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.snapshot, required this.client, this.onSettingsTap, this.displayedStatus});

  final MonitoringSnapshot snapshot;
  final MonitoringClient client;
  final VoidCallback? onSettingsTap;
  final String? displayedStatus;

  @override
  Widget build(BuildContext context) {
    final color = _C.severity(snapshot.alertSeverity);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Trip / connection row ──
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: snapshot.tripActive ? _C.focusedGreen : _C.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    snapshot.tripActive ? 'Trip active' : 'Trip stopped',
                    style: TextStyle(
                      color: snapshot.tripActive
                          ? _C.textPrimary
                          : _C.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                _ConnectionPill(client: client, onTap: onSettingsTap),
              ],
            ),

            const SizedBox(height: 28),

            // ── Attention gauge ──
            _AttentionGauge(value: snapshot.attention, color: color),

            const SizedBox(height: 20),

            // ── Status label ──
            Text(
              snapshot.alert ?? displayedStatus ?? snapshot.status,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: snapshot.alert != null ? color : _C.textSecondary,
                fontSize: 14,
                fontWeight: snapshot.alert != null ? FontWeight.w600 : FontWeight.w400,
              ),
            ),

            if (snapshot.faceLost) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: snapshot.faceLostProgress.clamp(0, 1).toDouble(),
                  minHeight: 4,
                  backgroundColor: _C.surface2,
                  color: _C.alertOrange,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Face signal unavailable',
                textAlign: TextAlign.center,
                style: TextStyle(color: _C.textMuted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Attention Gauge ────────────────────────────────────────────────────────

class _AttentionGauge extends StatelessWidget {
  const _AttentionGauge({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 110,
      child: CustomPaint(
        painter: _GaugePainter(value: value, color: color),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    color: color,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'ATTENTION',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 2,
                    color: _C.textMuted,
                    fontWeight: FontWeight.w600,
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

class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 2);
    final radius = size.width / 2 - 16;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = _C.gaugeTrack
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    // Glow layer
    final glowPaint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    const startAngle = math.pi;
    const sweepAngle = math.pi;
    final valueSweep = sweepAngle * (value.clamp(0, 100).toDouble() / 100);

    canvas.drawArc(rect, startAngle, sweepAngle, false, trackPaint);
    if (valueSweep > 0) {
      canvas.drawArc(rect, startAngle, valueSweep, false, glowPaint);
      canvas.drawArc(rect, startAngle, valueSweep, false, fillPaint);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color;
}

// ─── Camera Feed ────────────────────────────────────────────────────────────

class _CameraView extends StatelessWidget {
  const _CameraView({required this.client, required this.snapshot});

  final MonitoringClient client;
  final MonitoringSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _MjpegView(client: client),

            // ── Face detection badge (top left) ──
            Positioned(
              left: 12,
              top: 12,
              child: _GlassBadge(
                icon: snapshot.faceFound
                    ? Icons.person_rounded
                    : Icons.person_off_rounded,
                label: snapshot.faceFound ? 'Driver detected' : 'No face',
                color: snapshot.faceFound ? _C.focusedGreen : _C.alertOrange,
              ),
            ),

            // ── FPS badge (bottom right) ──
            Positioned(
              right: 12,
              bottom: 12,
              child: _GlassBadge(
                icon: Icons.speed_rounded,
                label: '${snapshot.fps.toStringAsFixed(0)} fps',
                color: _C.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassBadge extends StatelessWidget {
  const _GlassBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPlaceholder extends StatelessWidget {
  const _CameraPlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _C.surface0,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_off_rounded,
              size: 40,
              color: _C.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(color: _C.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _MjpegView extends StatefulWidget {
  const _MjpegView({required this.client});

  final MonitoringClient client;

  @override
  State<_MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<_MjpegView> {
  ui.Image? _frame;
  ui.Codec? _codec;
  bool _pendingDecode = false;

  @override
  void initState() {
    super.initState();
    widget.client.latestFrameBytes.addListener(_onFrame);
    final existing = widget.client.latestFrameBytes.value;
    if (existing != null) _decode(existing);
  }

  @override
  void didUpdateWidget(_MjpegView old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client) {
      old.client.latestFrameBytes.removeListener(_onFrame);
      widget.client.latestFrameBytes.addListener(_onFrame);
    }
  }

  @override
  void dispose() {
    widget.client.latestFrameBytes.removeListener(_onFrame);
    _codec?.dispose();
    super.dispose();
  }

  void _onFrame() {
    final bytes = widget.client.latestFrameBytes.value;
    if (bytes != null) _decode(bytes);
  }

  void _decode(Uint8List bytes) {
    _pendingDecode = true;
    ui.instantiateImageCodec(bytes).then((codec) {
      if (!mounted || !_pendingDecode) {
        codec.dispose();
        return;
      }
      codec.getNextFrame().then((info) {
        if (!mounted || !_pendingDecode) {
          info.image.dispose();
          codec.dispose();
          return;
        }
        _pendingDecode = false;
        _codec?.dispose();
        _codec = codec;
        setState(() => _frame = info.image);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    if (frame == null) {
      return _CameraPlaceholder(
        message: widget.client.connectionState == BackendConnectionState.connected
            ? 'Waiting for camera…'
            : 'Connect to monitoring device',
      );
    }
    return RawImage(
      image: frame,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
    );
  }
}

// ─── Metrics ────────────────────────────────────────────────────────────────

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.snapshot});

  final MonitoringSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            label: 'PERCLOS',
            value: '${(snapshot.perclos * 100).toStringAsFixed(1)}%',
            color: _metricColor(snapshot.perclos, 0.3, 0.6),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            label: 'DROWSINESS',
            value: '${(snapshot.emaDrowsy * 100).toStringAsFixed(1)}%',
            color: _metricColor(snapshot.emaDrowsy, 0.4, 0.7),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            label: 'BLINK RATE',
            value: '${snapshot.blinksPerMin.toStringAsFixed(0)}/min',
            color: _C.textPrimary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            label: 'HEAD YAW',
            value: snapshot.poseValid
                ? '${snapshot.yaw.toStringAsFixed(0)}°'
                : '—',
            color: snapshot.poseValid ? _C.textPrimary : _C.textMuted,
          ),
        ),
      ],
    );
  }

  Color _metricColor(double value, double warn, double crit) {
    if (value >= crit) return _C.alertRed;
    if (value >= warn) return _C.alertAmber;
    return _C.textPrimary;
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: _C.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Controls ───────────────────────────────────────────────────────────────

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.client,
    required this.onError,
    required this.onSummary,
  });

  final MonitoringClient client;
  final void Function(Object error) onError;
  final VoidCallback onSummary;

  Future<void> _cmd(String path, [Map<String, dynamic>? payload]) async {
    try {
      await client.sendCommand(path, payload);
    } catch (e) {
      onError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ControlButton(
              icon: Icons.play_arrow_rounded,
              label: 'Start trip',
              filled: true,
              onTap: () => _cmd('/api/v1/trips/start'),
            ),
            _ControlButton(
              icon: Icons.stop_rounded,
              label: 'Stop trip',
              onTap: () => _cmd('/api/v1/trips/stop'),
            ),
            _ControlButton(
              icon: Icons.center_focus_strong_rounded,
              label: 'Calibrate',
              onTap: () => _cmd('/api/v1/calibration/start'),
            ),
            _ControlButton(
              icon: Icons.volume_off_rounded,
              label: 'Mute',
              onTap: () => _cmd('/api/v1/alarm/mute'),
            ),
            _ControlButton(
              icon: Icons.insights_rounded,
              label: 'Summary',
              onTap: onSummary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    this.filled = false,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? _C.accent.withOpacity(0.12) : _C.surface2,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: filled ? _C.accent : _C.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: filled ? _C.accent : _C.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
