import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'models/monitoring_snapshot.dart';
import 'services/local_backend.dart';
import 'services/monitoring_client.dart';

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
        colorSchemeSeed: Colors.teal,
        scaffoldBackgroundColor: const Color(0xff0b1117),
        cardTheme: const CardThemeData(
          color: Color(0xff131d26),
          margin: EdgeInsets.zero,
        ),
      ),
      home: DashboardPage(client: client),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.client});

  final MonitoringClient client;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: client,
      builder: (context, _) {
        final snapshot = client.snapshot;
        return Scaffold(
          appBar: AppBar(
            title: const Row(
              children: [
                Icon(Icons.directions_car_filled_rounded),
                SizedBox(width: 12),
                Text('Driver Monitor'),
              ],
            ),
            actions: [
              _ConnectionPill(client: client),
              IconButton(
                tooltip: 'Connection settings',
                onPressed: () => _showConnectionDialog(context),
                icon: const Icon(Icons.settings_outlined),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final content = _DashboardContent(
                  client: client,
                  snapshot: snapshot,
                  wide: wide,
                  onCommandError: (error) => _showError(context, error),
                  onSummary: () => _showSummary(context),
                );
                return SingleChildScrollView(
                  padding: EdgeInsets.all(wide ? 24 : 16),
                  child: content,
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showConnectionDialog(BuildContext context) async {
    final urlController = TextEditingController(text: client.baseUrl);
    final tokenController = TextEditingController(text: client.token ?? '');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Connect to monitoring device'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Backend URL',
                  hintText: 'http://192.168.1.20:8765',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tokenController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Bearer token (optional on localhost)',
                ),
              ),
              if (client.token != null) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      try {
                        await client.forgetDevice();
                        tokenController.clear();
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (error) {
                        tokenController.clear();
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text(error.toString())),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.link_off),
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
                baseUrl: urlController.text,
                token: tokenController.text,
              );
              Navigator.pop(dialogContext);
              unawaited(_showPairingDialog(context));
            },
            child: const Text('Pair device'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              client.configure(
                baseUrl: urlController.text,
                token: tokenController.text,
              );
              Navigator.pop(dialogContext);
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    urlController.dispose();
    tokenController.dispose();
  }

  Future<void> _showPairingDialog(BuildContext context) async {
    final codeController = TextEditingController();
    String? pairingCode;
    String? message;
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          Future<void> showLocalCode() async {
            setState(() {
              busy = true;
              message = null;
            });
            try {
              final details = await client.fetchPairing();
              if (!context.mounted) return;
              setState(() {
                pairingCode = details['code'] as String?;
                codeController.text = pairingCode ?? '';
                message = pairingCode == null
                    ? 'The backend did not return a pairing code.'
                    : 'Code expires soon. Share it only with the paired phone.';
              });
            } catch (error) {
              if (context.mounted) setState(() => message = error.toString());
            } finally {
              if (context.mounted) setState(() => busy = false);
            }
          }

          Future<void> pair() async {
            setState(() {
              busy = true;
              message = null;
            });
            try {
              await client.exchangePairing(codeController.text);
              if (context.mounted) Navigator.pop(dialogContext);
            } catch (error) {
              if (context.mounted) setState(() => message = error.toString());
            } finally {
              if (context.mounted) setState(() => busy = false);
            }
          }

          return AlertDialog(
            title: const Text('Pair companion device'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'On the desktop, reveal a local code. Enter that code here on the companion device to receive a short-lived access token.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Pairing code',
                      hintText: '8-character code',
                    ),
                  ),
                  if (pairingCode != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      pairingCode!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                  if (message != null) ...[
                    const SizedBox(height: 12),
                    Text(message!, textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : showLocalCode,
                child: const Text('Reveal local code'),
              ),
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: busy ? null : pair,
                child: Text(busy ? 'Working…' : 'Pair'),
              ),
            ],
          );
        },
      ),
    );
    codeController.dispose();
  }

  void _showError(BuildContext context, Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }

  Future<void> _showSummary(BuildContext context) async {
    try {
      final summary = await client.fetchCurrentSummary();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Current trip summary'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Duration: ${_formatNumber(summary['duration'])} s'),
              Text('Average attention: ${_formatNumber(summary['attention_avg'])}'),
              Text('Lowest attention: ${_formatNumber(summary['attention_min'])}'),
              Text('Maximum PERCLOS: ${_formatPercent(summary['perclos_max'])}'),
              Text('Alerts: ${summary['alert_count'] ?? 0}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  String _formatNumber(Object? value) =>
      value is num ? value.toStringAsFixed(1) : '—';

  String _formatPercent(Object? value) =>
      value is num ? '${(value * 100).toStringAsFixed(1)}%' : '—';
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.client,
    required this.snapshot,
    required this.wide,
    required this.onCommandError,
    required this.onSummary,
  });

  final MonitoringClient client;
  final MonitoringSnapshot snapshot;
  final bool wide;
  final void Function(Object error) onCommandError;
  final VoidCallback onSummary;

  @override
  Widget build(BuildContext context) {
    final camera = _CameraCard(client: client, snapshot: snapshot);
    final status = _StatusCard(snapshot: snapshot);
    final metrics = _MetricsGrid(snapshot: snapshot);

    if (wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: camera),
              const SizedBox(width: 20),
              Expanded(flex: 4, child: status),
            ],
          ),
          const SizedBox(height: 20),
          metrics,
          const SizedBox(height: 20),
          _Controls(
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
        const SizedBox(height: 16),
        camera,
        const SizedBox(height: 16),
        metrics,
        const SizedBox(height: 16),
        _Controls(
          client: client,
          onError: onCommandError,
          onSummary: onSummary,
        ),
      ],
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.client});

  final MonitoringClient client;

  @override
  Widget build(BuildContext context) {
    final connected = client.connectionState == BackendConnectionState.connected &&
        !client.isStale;
    final color = connected ? Colors.tealAccent : Colors.amber;
    final label = connected
        ? 'Connected'
        : client.connectionState == BackendConnectionState.connecting
            ? 'Connecting'
            : 'Offline';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        avatar: Icon(Icons.circle, size: 10, color: color),
        label: Text(label),
        side: BorderSide(color: color.withOpacity(.35)),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.snapshot});

  final MonitoringSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(snapshot);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('CURRENT STATUS', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 12),
            Text(
              snapshot.status,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 20),
            Center(child: _AttentionGauge(value: snapshot.attention, color: color)),
            const SizedBox(height: 18),
            Text(
              snapshot.alert ?? (snapshot.tripActive ? 'Monitoring active' : 'Trip stopped'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (snapshot.faceLost) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: snapshot.faceLostProgress.clamp(0, 1).toDouble(),
                color: Colors.orange,
              ),
              const SizedBox(height: 6),
              const Text('Face signal unavailable', textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttentionGauge extends StatelessWidget {
  const _AttentionGauge({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      height: 120,
      child: CustomPaint(
        painter: _GaugePainter(value: value, color: color),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 28),
            child: Text(
              value.toStringAsFixed(0),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
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
    final center = Offset(size.width / 2, size.height - 4);
    final radius = size.width / 2 - 12;
    final background = Paint()
      ..color = Colors.white.withOpacity(.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    final foreground = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, 3.14, 3.14, false, background);
    canvas.drawArc(
      rect,
      3.14,
      3.14 * (value.clamp(0, 100).toDouble() / 100),
      false,
      foreground,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}

class _CameraCard extends StatelessWidget {
  const _CameraCard({required this.client, required this.snapshot});

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
            Positioned(
              left: 16,
              top: 16,
              child: Chip(
                avatar: Icon(
                  Icons.videocam,
                  size: 16,
                  color: snapshot.faceFound ? Colors.tealAccent : Colors.orange,
                ),
                label: Text(snapshot.faceFound ? 'Driver detected' : 'No face detected'),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: Text(
                '${snapshot.fps.toStringAsFixed(1)} FPS',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
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
      color: const Color(0xff070b0f),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, size: 48, color: Colors.white.withOpacity(.5)),
            const SizedBox(height: 12),
            Text(message),
          ],
        ),
      ),
    );
  }
}

/// Renders the newest JPEG frame from the persistent MJPEG stream. Frames are
/// decoded on the UI thread with the codec cached, so dropped frames are
/// simply skipped and playback stays smooth.
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
  void didUpdateWidget(_MjpegView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      oldWidget.client.latestFrameBytes.removeListener(_onFrame);
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
    if (bytes == null) return;
    _decode(bytes);
  }

  void _decode(Uint8List bytes) {
    // Drop stale work: only the newest frame is rendered, so a slow codec
    // never queues frames behind the live feed.
    _pendingDecode = true;
    ui.instantiateImageCodec(bytes).then((codec) {
      if (!mounted || !_pendingDecode) {
        codec.dispose();
        return;
      }
      codec.getNextFrame().then((frameInfo) {
        if (!mounted || !_pendingDecode) {
          frameInfo.image.dispose();
          codec.dispose();
          return;
        }
        _pendingDecode = false;
        _codec?.dispose();
        _codec = codec;
        setState(() => _frame = frameInfo.image);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    if (frame == null) {
      return _CameraPlaceholder(
        message: widget.client.connectionState == BackendConnectionState.connected
            ? 'Waiting for camera stream…'
            : 'Connect to the monitoring device',
      );
    }
    return RawImage(
      image: frame,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.snapshot});

  final MonitoringSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetricTile(
          label: 'PERCLOS',
          value: '${(snapshot.perclos * 100).toStringAsFixed(1)}%',
          icon: Icons.remove_red_eye_outlined,
        ),
        _MetricTile(
          label: 'DROWSINESS',
          value: '${(snapshot.emaDrowsy * 100).toStringAsFixed(1)}%',
          icon: Icons.bedtime_outlined,
        ),
        _MetricTile(
          label: 'BLINK RATE',
          value: '${snapshot.blinksPerMin.toStringAsFixed(1)}/min',
          icon: Icons.visibility_outlined,
        ),
        _MetricTile(
          label: 'HEAD POSE',
          value: snapshot.poseValid
              ? '${snapshot.yaw.toStringAsFixed(0)}° yaw'
              : 'Unavailable',
          icon: Icons.face_retouching_natural_outlined,
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: Colors.tealAccent),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 4),
                  Text(value, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.client,
    required this.onError,
    required this.onSummary,
  });

  final MonitoringClient client;
  final void Function(Object error) onError;
  final VoidCallback onSummary;

  Future<void> _command(String path, [Map<String, dynamic>? payload]) async {
    try {
      await client.sendCommand(path, payload);
    } catch (error) {
      onError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: () => _command('/api/v1/trips/start'),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start trip'),
            ),
            OutlinedButton.icon(
              onPressed: () => _command('/api/v1/trips/stop'),
              icon: const Icon(Icons.stop),
              label: const Text('Stop trip'),
            ),
            OutlinedButton.icon(
              onPressed: () => _command('/api/v1/calibration/start'),
              icon: const Icon(Icons.center_focus_strong),
              label: const Text('Calibrate'),
            ),
            OutlinedButton.icon(
              onPressed: () => _command('/api/v1/alarm/mute'),
              icon: const Icon(Icons.volume_off_outlined),
              label: const Text('Mute alarm'),
            ),
            OutlinedButton.icon(
              onPressed: onSummary,
              icon: const Icon(Icons.insights_outlined),
              label: const Text('Trip summary'),
            ),
          ],
        ),
      ),
    );
  }
}

Color _severityColor(MonitoringSnapshot snapshot) {
  if (snapshot.alertSeverity >= 4) return Colors.redAccent;
  if (snapshot.alertSeverity >= 3) return Colors.orangeAccent;
  if (snapshot.alertSeverity >= 2) return Colors.amber;
  if (snapshot.focused) return Colors.tealAccent;
  return Colors.blueAccent;
}
