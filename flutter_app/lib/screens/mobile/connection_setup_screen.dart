import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/connection_service.dart';
import '../../services/device_discovery_service.dart';
import '../../theme.dart';

/// Full-screen connection setup matching the Stitch "Connection Setup" mockup.
///
/// Shows pulsing logo, backend URL card, auth card with sign in/create account
/// toggle, and device discovery list.
class ConnectionSetupScreen extends StatefulWidget {
  const ConnectionSetupScreen({
    super.key,
    required this.connectionService,
    required this.authService,
  });

  final ConnectionService connectionService;
  final AuthService authService;

  @override
  State<ConnectionSetupScreen> createState() => _ConnectionSetupScreenState();
}

class _ConnectionSetupScreenState extends State<ConnectionSetupScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _backendUrlController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  bool _isRegistering = false;
  bool _showManualEntry = false;
  String? _error;

  // Device discovery state
  List<DeviceInfo> _devices = [];
  bool _devicesLoaded = false;

  final _discoveryService = DeviceDiscoveryService();

  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _backendUrlController.text = 'http://127.0.0.1:8765';
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _backendUrlController.dispose();
    _nameController.dispose();
    _discoveryService.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final backendUrl = _backendUrlController.text.trim();

    if (email.isEmpty || password.isEmpty || backendUrl.isEmpty) {
      setState(() => _error = 'All fields are required');
      return;
    }

    final normalisedUrl = backendUrl.startsWith('http')
        ? backendUrl
        : 'http://$backendUrl';

    setState(() { _isLoading = true; _error = null; });

    try {
      if (_isRegistering) {
        await widget.authService.register(
          email, password,
          displayName: _nameController.text.trim(),
          backendUrl: normalisedUrl,
        );
      } else {
        await widget.authService.login(
          email, password,
          backendUrl: normalisedUrl,
        );
      }

      await widget.connectionService.connectTo(normalisedUrl);
      await _discoverDevices(normalisedUrl);
      setState(() { _isLoading = false; });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _discoverDevices(String backendUrl) async {
    final jwt = widget.authService.jwt;
    if (jwt == null) return;
    try {
      final devices = await _discoveryService.discoverDevices(backendUrl, jwt);
      setState(() { _devices = devices; _devicesLoaded = true; });
    } catch (e) {
      setState(() { _devicesLoaded = true; });
    }
  }

  Future<void> _pairWithDevice(DeviceInfo device) async {
    final jwt = widget.authService.jwt;
    if (jwt == null) return;

    setState(() { _isLoading = true; _error = null; });

    try {
      final result = await _discoveryService.pairWithDevice(
        _backendUrlController.text.trim().startsWith('http')
            ? _backendUrlController.text.trim()
            : 'http://${_backendUrlController.text.trim()}',
        jwt,
        device.id,
      );

      final deviceUrl = result.deviceUrl ?? device.connectionUrl;
      await widget.connectionService.connectTo(
        deviceUrl,
        manualToken: result.accessToken,
      );

      setState(() { _isLoading = false; });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      backgroundColor: Stitch.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomPad),
          child: Column(
            children: [
              // Logo
              _buildLogo(),
              const SizedBox(height: 24),

              // Error banner
              if (_error != null) ...[
                _buildErrorBanner(),
                const SizedBox(height: 16),
              ],

              // Auth flow
              if (!widget.authService.isLoggedIn) ...[
                _buildBackendUrlCard(),
                const SizedBox(height: 16),
                _buildAuthCard(),
              ] else if (!_devicesLoaded) ...[
                _buildBackendUrlCard(),
                const SizedBox(height: 16),
                _buildDiscoveringCard(),
              ] else ...[
                _buildDeviceList(),
              ],

              const SizedBox(height: 16),
              _buildManualToggle(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Logo ───────────────────────────────────────────────────────────────

  Widget _buildLogo() {
    return Column(
      children: [
        SizedBox(
          width: 128,
          height: 128,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing ring
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) {
                  final v = _pulseCtrl.value;
                  return Container(
                    width: 128,
                    height: 128,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Stitch.primary.withValues(alpha: 0.2 * (1 - v)),
                    ),
                  );
                },
              ),
              // Shield icon
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Stitch.primary.withValues(alpha: 0.1),
                ),
                child: Icon(
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
            color: Stitch.onSurface,
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

  // ── Error Banner ───────────────────────────────────────────────────────

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Stitch.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Stitch.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Stitch.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connection Refused',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Stitch.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 13,
                    color: Stitch.onErrorContainer.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Backend URL Card ───────────────────────────────────────────────────

  Widget _buildBackendUrlCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Stitch.container,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Stitch.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.dns, size: 16, color: Stitch.primary),
              const SizedBox(width: 8),
              Text(
                'BACKEND SERVER',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w700,
                  color: Stitch.onSurface,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Stitch.surfaceLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Stitch.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 18, color: Stitch.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _backendUrlController,
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 14,
                      color: Stitch.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: '192.168.1.100:8080',
                      hintStyle: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 14,
                        color: Stitch.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Stitch.secondary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Auth Card ──────────────────────────────────────────────────────────

  Widget _buildAuthCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Stitch.container,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Stitch.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toggle buttons
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Stitch.surfaceLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Stitch.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isRegistering = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: !_isRegistering ? Stitch.containerHighest : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'SIGN IN',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'JetBrains Mono',
                          fontWeight: FontWeight.w700,
                          color: !_isRegistering ? Stitch.onSurface : Stitch.onSurfaceVariant,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isRegistering = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _isRegistering ? Stitch.containerHighest : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'CREATE ACCOUNT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'JetBrains Mono',
                          fontWeight: FontWeight.w700,
                          color: _isRegistering ? Stitch.onSurface : Stitch.onSurfaceVariant,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Name field (register only)
          if (_isRegistering) ...[
            _AuthField(
              label: 'DISPLAY NAME',
              icon: Icons.person_outline,
              controller: _nameController,
              hint: 'Your name',
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
          ],

          // Email
          _AuthField(
            label: 'OPERATIVE EMAIL',
            icon: Icons.mail,
            controller: _emailController,
            hint: 'agent@wakeguard.sys',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),

          // Password
          _AuthField(
            label: 'ACCESS KEY',
            icon: Icons.key,
            controller: _passwordController,
            hint: '••••••••',
            obscure: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _login(),
          ),
          const SizedBox(height: 20),

          // Submit
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: Stitch.primary,
                foregroundColor: Stitch.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                shadowColor: Stitch.primary.withValues(alpha: 0.2),
              ),
              child: _isLoading
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
                        const Icon(Icons.login, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _isRegistering ? 'CREATE ACCOUNT' : 'INITIATE LINK',
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'JetBrains Mono',
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
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

  // ── Device Discovery ───────────────────────────────────────────────────

  Widget _buildDiscoveringCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Stitch.container,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Stitch.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Stitch.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Scanning local subnet...',
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'JetBrains Mono',
                  color: Stitch.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Stitch.container,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Stitch.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Stitch.outlineVariant, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.radar, size: 18, color: Stitch.secondary),
                const SizedBox(width: 8),
                Text(
                  'PAIRED DEVICES',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w700,
                    color: Stitch.secondary,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.sync, size: 16, color: Stitch.secondary),
              ],
            ),
          ),

          // Devices
          if (_devices.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.desktop_windows,
                      size: 32, color: Stitch.onSurfaceVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text(
                    'No devices found',
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'JetBrains Mono',
                      color: Stitch.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Make sure your desktop is running\nwith Supabase configured',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Stitch.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            )
          else
            ..._devices.map((device) => _buildDeviceTile(device)),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(DeviceInfo device) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : () => _pairWithDevice(device),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Stitch.outlineVariant, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Stitch.surfaceLowest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Stitch.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Icon(
                  device.platform == 'windows'
                      ? Icons.desktop_windows
                      : device.platform == 'macos'
                          ? Icons.laptop_mac
                          : Icons.computer,
                  size: 20,
                  color: Stitch.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.deviceName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Stitch.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${device.displayPlatform} • ${device.apiHost ?? ""}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'JetBrains Mono',
                        fontWeight: FontWeight.w500,
                        color: Stitch.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: Stitch.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  // ── Manual Toggle ──────────────────────────────────────────────────────

  Widget _buildManualToggle() {
    return GestureDetector(
      onTap: () => setState(() => _showManualEntry = !_showManualEntry),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.settings_ethernet, size: 14, color: Stitch.primary),
          const SizedBox(width: 6),
          Text(
            _showManualEntry ? 'Hide manual options' : 'Manual Configuration Link',
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.w700,
              color: Stitch.primary,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Auth Field ─────────────────────────────────────────────────────────────

class _AuthField extends StatefulWidget {
  const _AuthField({
    required this.label,
    required this.icon,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
  });

  final String label;
  final IconData icon;
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<_AuthField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'JetBrains Mono',
            fontWeight: FontWeight.w700,
            color: Stitch.onSurfaceVariant,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Stitch.surfaceLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Stitch.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: Stitch.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  obscureText: widget.obscure && _obscured,
                  style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 14,
                    color: Stitch.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 14,
                      color: Stitch.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  onSubmitted: widget.onSubmitted,
                ),
              ),
              if (widget.obscure)
                GestureDetector(
                  onTap: () => setState(() => _obscured = !_obscured),
                  child: Icon(
                    _obscured ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                    color: Stitch.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
