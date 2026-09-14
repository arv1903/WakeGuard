import 'dart:async';

import 'package:clock/clock.dart';

import 'connection_service.dart';
import 'discovery_client.dart';
import 'monitoring_client.dart';

/// Keeps the mobile companion paired when the desktop backend's address
/// changes (DHCP renewal, restart, AP switch).
///
/// The [MonitoringClient] retries its SSE/MJPEG loops forever — but always
/// against the same URL, so a moved backend means an eternal reconnect loop
/// against a dead address. This service listens for that state: after a
/// short grace period (real drops are often momentary) it re-runs LAN
/// discovery via [DiscoveryClient] and, when the backend is found at a new
/// address, re-points the connection through `ConnectionService.connectTo`
/// — which persists the new URL while keeping the stored bearer token.
/// Probes back off (5s doubling, capped at 40s) while nothing is found and
/// reset the moment a connection succeeds or an address is adopted.
class BackendRecoveryService {
  BackendRecoveryService({
    required this.connectionService,
    DiscoveryClient? discoveryClient,
    this.shouldRun,
  }) : _discovery = discoveryClient ?? DiscoveryClient();

  final ConnectionService connectionService;
  final DiscoveryClient _discovery;

  /// Optional gate (e.g. the user is signed in). While false, drops are
  /// ignored and probes are skipped — unauthenticated users have nothing to
  /// recover and no right to scan the network.
  final bool Function()? shouldRun;

  static const _tick = Duration(seconds: 1);
  static const _gracePeriod = Duration(seconds: 10);
  static const _baseRetryDelay = Duration(seconds: 5);
  static const _maxRetryDelay = Duration(seconds: 40);

  MonitoringClient get _client => connectionService.client;

  bool _tracking = false;
  DateTime? _probeAllowedAfter;
  DateTime? _lastProbeAt;
  Timer? _timer;
  bool _disposed = false;

  /// Probes performed for the current outage (0 when connected). Exposed
  /// for tests and a future "searching for desktop…" indicator.
  int get attempts => _tracking ? _attempts : 0;
  int _attempts = 0;

  void start() {
    _client.addListener(_onClientUpdate);
    _timer = Timer.periodic(_tick, (_) => _tickCheck());
  }

  void stop() {
    _disposed = true;
    _client.removeListener(_onClientUpdate);
    _timer?.cancel();
    _timer = null;
  }

  void _reset() {
    _tracking = false;
    _attempts = 0;
    _probeAllowedAfter = null;
    _lastProbeAt = null;
  }

  /// Wait required before the next probe, given [_attempts] probes done:
  /// base delay after the 1st probe, then doubling, capped.
  Duration _requiredDelay() {
    var delay = _baseRetryDelay;
    for (var i = 1; i < _attempts; i++) {
      delay = delay * 2 >= _maxRetryDelay ? _maxRetryDelay : delay * 2;
    }
    return delay;
  }

  bool get _allowed => shouldRun?.call() ?? true;

  void _onClientUpdate() {
    if (_disposed) return;
    final state = _client.connectionState;
    if (state == BackendConnectionState.connected) {
      _reset();
      return;
    }
    if (state == BackendConnectionState.disconnected ||
        state == BackendConnectionState.error) {
      // `connecting` is deliberately not tracked — it is the client's own
      // normal retry loop doing its job.
      if (_tracking || !_allowed) return;
      _tracking = true;
      _attempts = 0;
      _probeAllowedAfter = clock.now().add(_gracePeriod);
      _lastProbeAt = null;
    }
  }

  void _tickCheck() {
    if (_disposed || !_tracking || !_allowed) return;
    final now = clock.now();
    if (_probeAllowedAfter != null && now.isBefore(_probeAllowedAfter!)) {
      return; // still inside the grace window
    }
    final sinceLast =
        _lastProbeAt == null ? null : now.difference(_lastProbeAt!);
    if (sinceLast != null && sinceLast < _requiredDelay()) return;

    _lastProbeAt = now;
    _attempts++;
    unawaited(_probe());
  }

  Future<void> _probe() async {
    try {
      final backends = await _discovery.discover();
      if (_disposed || !_tracking) return;
      final best = DiscoveredBackend.pickBest(backends);
      if (best == null) return;
      if (best.url == _client.baseUrl) return; // same address, nothing to do
      await connectionService.connectTo(best.url);
      // Adopted: this recovery round is done. If the new address also
      // fails, the next `disconnected` event re-arms tracking from scratch.
      _reset();
    } catch (_) {
      // Discovery is best-effort; the next tick retries after backoff.
    }
  }
}
