import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/connection_service.dart';
import '../../theme.dart';

/// Full-screen connection setup for the mobile companion.
///
/// Matches the Stitch "Connection Setup" mockup: shield logo, URL input,
/// Connect button, Pair with Code option.
class ConnectionSetupScreen extends StatefulWidget {
  const ConnectionSetupScreen({super.key, required this.connectionService});

  final ConnectionService connectionService;

  @override
  State<ConnectionSetupScreen> createState() => _ConnectionSetupScreenState();
}

class _ConnectionSetupScreenState extends State<ConnectionSetupScreen>
    with SingleTickerProviderStateMixin {
  final _urlController = TextEditingController();
  final _codeController = TextEditingController();
  final _urlFocus = FocusNode();
  bool _isConnecting = false;
  bool _isExchanging = false;
  _SetupPhase _phase = _setupPhase;

  // Pairing code fetched from the backend (displayed on desktop).
  String? _pairingCode;

  late AnimationController _pulseCtrl;

  static _SetupPhase _setupPhase = _SetupPhase.input;
  static String? _savedUrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    if (_savedUrl != null) _urlController.text = _savedUrl!;
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _urlController.dispose();
    _codeController.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _connect() async {
    final url = _urlController.text.trim();
    if (url.length < 5) {
      setState(() {
        _phase = _SetupPhase.error;
      });
      _resetPhaseAfterDelay();
      return;
    }

    final normalised = url.startsWith('http') ? url : 'http://$url';
    setState(() {
      _isConnecting = true;        _phase = _SetupPhase.connecting;
    });

    try {
      await widget.connectionService.connectTo(normalised);
      // Try a health check — if 401/403, we need pairing.
      final client = widget.connectionService.client;
      final request = await HttpClient().getUrl(
        Uri.parse('${widget.connectionService.backendUrl}/api/v1/health'),
      );
      if (client.token != null) {
        request.headers.add('Authorization', 'Bearer ${client.token}');
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        // Connected — reconnect the SSE/MJPEG streams.
        client.connect();
        _savedUrl = normalised;
        setState(() {
          _isConnecting = false;
          _phase = _SetupPhase.connected;
        });
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        // Need pairing.
        setState(() {
          _isConnecting = false;
          _phase = _SetupPhase.needsPairing;
        });
      } else {
        throw Exception('HTTP ${response.statusCode}: $body');
      }
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _phase = _SetupPhase.error;
      });
      _resetPhaseAfterDelay();
    }
  }

  Future<void> _fetchPairingCode() async {
    setState(() {
      _isConnecting = true;        _phase = _SetupPhase.connecting;
    });

    try {
      final result = await widget.connectionService.client.fetchPairing();
      setState(() {
        _isConnecting = false;
        _pairingCode = result['code'] as String?;
        _phase = _SetupPhase.showingCode;
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _phase = _SetupPhase.error;
      });
      _resetPhaseAfterDelay();
    }
  }

  Future<void> _exchangeCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isExchanging = true;
    });

    try {
      await widget.connectionService.completePairing(code);
      setState(() {
        _isExchanging = false;
        _phase = _SetupPhase.connected;
      });
    } catch (e) {
      setState(() {
        _isExchanging = false;
        _phase = _SetupPhase.showingCode;
      });
      _resetPhaseAfterDelay();
    }
  }

  void _resetPhaseAfterDelay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _phase == _SetupPhase.error) {
        setState(() => _phase = _SetupPhase.input);
      }
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      backgroundColor: Stitch.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 32, 20, 20 + bottomPad),
          child: Column(
            children: [
              const SizedBox(height: 40),
              _buildLogo(),
              const SizedBox(height: 32),
              _buildUrlCard(),
              const SizedBox(height: 24),
              _buildPairButton(),
              const SizedBox(height: 16),
              _buildPairingCodeEntry(),
              const SizedBox(height: 16),
              Text(
                'Enter the IP address shown on the desktop app',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'JetBrains Mono',
                  color: Stitch.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        // Shield with pulsing rings
        SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer pulse ring
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) {
                  final v = _pulseCtrl.value;
                  return Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Stitch.primary.withValues(alpha: 0.08 * (1 - v)),
                    ),
                  );
                },
              ),
              // Inner pulse ring (offset)
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) {
                  final v = (_pulseCtrl.value + 0.5) % 1.0;
                  return Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Stitch.primary.withValues(alpha: 0.12 * (1 - v)),
                    ),
                  );
                },
              ),
              // Shield icon
              Icon(
                Icons.shield,
                size: 48,
                color: Stitch.primary,
                shadows: [
                  Shadow(
                    color: Stitch.primary.withValues(alpha: 0.5),
                    blurRadius: 12,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'WakeGuard',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Stitch.onBackground,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Driver Safety Companion',
          style: TextStyle(
            fontSize: 14,
            color: Stitch.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildUrlCard() {
    // Status dot color
    Color dotColor;
    switch (_phase) {
      case _SetupPhase.connected:
        dotColor = Stitch.secondary;
      case _SetupPhase.connecting:
      case _SetupPhase.showingCode:
        dotColor = Stitch.primary;
      case _SetupPhase.error:
        dotColor = Stitch.error;
      default:
        dotColor = Stitch.outlineVariant;
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Stitch.container,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label with status dot
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  boxShadow: _phase == _SetupPhase.connected
                      ? [
                          BoxShadow(
                            color: Stitch.secondary.withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'BACKEND ADDRESS',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w500,
                  color: Stitch.onSurface,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // URL input
          TextField(
            controller: _urlController,
            focusNode: _urlFocus,
            style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 14,
              color: Stitch.onSurface,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.dns, size: 20, color: Stitch.primary),
              hintText: '192.168.1.50:8765',
              hintStyle: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 14,
                color: Stitch.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              filled: true,
              fillColor: _phase == _SetupPhase.error
                  ? Stitch.error.withValues(alpha: 0.08)
                  : Stitch.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: _phase == _SetupPhase.error
                      ? Stitch.error
                      : Stitch.primary,
                  width: 1,
                ),
              ),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 16),
          // Connect button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isConnecting ? null : _connect,
              style: ElevatedButton.styleFrom(
                backgroundColor: _phase == _SetupPhase.connected
                    ? Stitch.secondary
                    : _phase == _SetupPhase.error
                        ? Stitch.error
                        : Stitch.primary,
                foregroundColor: _phase == _SetupPhase.connected
                    ? Stitch.onSecondary
                    : _phase == _SetupPhase.error
                        ? Stitch.onError
                        : Stitch.onPrimary,
                disabledBackgroundColor:
                    Stitch.primary.withValues(alpha: 0.5),
                disabledForegroundColor:
                    Stitch.onPrimary.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: _isConnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Stitch.onPrimary,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _phase == _SetupPhase.connected
                              ? Icons.check_circle
                              : _phase == _SetupPhase.error
                                  ? Icons.error
                                  : Icons.link,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _phase == _SetupPhase.connected
                              ? 'Connected'
                              : _phase == _SetupPhase.error
                                  ? 'Invalid Address'
                                  : _phase == _SetupPhase.needsPairing
                                      ? 'Pair Required'
                                      : 'Connect',
                          style: const TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPairButton() {
    if (_phase == _SetupPhase.connected) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        onPressed: _isConnecting ? null : _fetchPairingCode,
        icon: const Icon(Icons.qr_code_scanner, size: 18),
        label: const Text(
          'PAIR WITH CODE',
          style: TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 1,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: Stitch.primary,
          side: BorderSide(
            color: Stitch.outlineVariant,
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _buildPairingCodeEntry() {
    if (_phase != _SetupPhase.showingCode) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Stitch.container,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Stitch.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.qr_code, size: 40, color: Stitch.primary),
          const SizedBox(height: 12),
          Text(
            _pairingCode ?? '------',
            style: const TextStyle(
              fontSize: 32,
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.w700,
              color: Stitch.primary,
              letterSpacing: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter this code on the desktop',
            style: TextStyle(
              fontSize: 12,
              color: Stitch.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 18,
              letterSpacing: 4,
              color: Stitch.onSurface,
            ),
            decoration: InputDecoration(
              hintText: 'Enter code',
              hintStyle: TextStyle(
                color: Stitch.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              filled: true,
              fillColor: Stitch.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Stitch.primary),
              ),
            ),
            textInputAction: TextInputAction.go,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => _exchangeCode(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _isExchanging ? null : _exchangeCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Stitch.primary,
                foregroundColor: Stitch.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: _isExchanging
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Stitch.onPrimary,
                      ),
                    )
                  : const Text(
                      'EXCHANGE',
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _SetupPhase {
  input,
  connecting,
  connected,
  needsPairing,
  showingCode,
  error,
}
