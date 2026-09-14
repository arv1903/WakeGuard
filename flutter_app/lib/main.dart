import 'dart:async';

import 'package:flutter/material.dart';

import 'services/auth_service.dart';
import 'services/backend_recovery_service.dart';
import 'services/connection_service.dart';
import 'services/local_backend.dart';
import 'services/monitoring_client.dart';
import 'theme.dart';
import 'screens/app_shell.dart';
import 'screens/mobile/mobile_app_shell.dart';

void main() {
  const apiUrl =
      String.fromEnvironment('API_URL', defaultValue: 'http://127.0.0.1:8765');
  const autoStart =
      String.fromEnvironment('AUTO_START_BACKEND', defaultValue: 'false') ==
          'true';
  runApp(DriverMonitorApp(apiUrl: apiUrl, autoStartBackend: autoStart));
}

class DriverMonitorApp extends StatefulWidget {
  const DriverMonitorApp(
      {super.key, required this.apiUrl, required this.autoStartBackend});
  final String apiUrl;
  final bool autoStartBackend;

  /// Deployment token for backends started with --api-token. Desktop runs
  /// against a token-protected backend must pass the same value, e.g.:
  ///   flutter run -d windows --dart-define=WAKEGUARD_API_TOKEN=<token>
  static const apiToken = String.fromEnvironment('WAKEGUARD_API_TOKEN');

  @override
  State<DriverMonitorApp> createState() => _DriverMonitorAppState();
}

class _DriverMonitorAppState extends State<DriverMonitorApp> {
  late final MonitoringClient client;
  late final ConnectionService connectionService;
  late final AuthService authService;
  late final LocalBackendProcess backend;
  BackendRecoveryService? _recovery;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    client = MonitoringClient(
      baseUrl: widget.apiUrl,
      token: DriverMonitorApp.apiToken.isEmpty
          ? null
          : DriverMonitorApp.apiToken,
    );
    authService = AuthService();
    connectionService = ConnectionService(client: client, authService: authService);
    backend = LocalBackendProcess();
    _init();
  }

  Future<void> _init() async {
    // Safety net: even if _init hangs (e.g. SharedPreferences slow, backend
    // unreachable), the UI must render within a few seconds so the user can
    // reach the login screen.
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && !_ready) {
        debugPrint('[WakeGuard] Init timed out – forcing UI render');
        setState(() => _ready = true);
      }
    });

    try {
      // Load persisted auth and connection state.
      await authService.load();
      await connectionService.load();

      // Phones: auto-recover when the desktop moves (DHCP, restart, AP
      // switch). Desktop hosts its own backend — nothing to recover there.
      if (!LocalBackendProcess.supported) {
        _recovery = BackendRecoveryService(
          connectionService: connectionService,
          shouldRun: () => authService.isLoggedIn,
        )..start();
      }

      if (widget.autoStartBackend) {
        await _startBackend();
      } else {
        // If we have stored credentials, reconnect; otherwise connect to default.
        if (connectionService.isPaired && !connectionService.isExpired) {
          await connectionService.reconnect();
        } else {
          client.connect();
        }
      }
    } catch (e) {
      debugPrint('[WakeGuard] Init failed: $e');
    }
    // Always render the UI — timeout or error must not leave the user stuck
    // on the spinner with no way to reach the login screen.
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _startBackend() async {
    // Wire port from apiUrl so backend and client agree (fixes hardcoded 8765 mismatch)
    int? port;
    try {
      final uri = Uri.tryParse(widget.apiUrl);
      if (uri != null && uri.hasPort) port = uri.port;
    } catch (_) {}
    await backend.start(port: port);
    if (mounted) client.connect();
  }

  @override
  void dispose() {
    _recovery?.stop();
    client.dispose();
    unawaited(backend.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Global error handling prevents white-screen on snapshot fromJson crashes
    ErrorWidget.builder = (details) => Material(
          color: AppColors.background,
          child: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Something went wrong\n${details.exception}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary)))),
        );
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
    };
    return MaterialApp(
      title: 'WakeGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorSchemeSeed: AppColors.accent,
        fontFamily: 'Inter',
        textTheme: const TextTheme(
          headlineLarge: AppTextStyles.headlineLg,
          headlineMedium: AppTextStyles.headlineMd,
          headlineSmall: AppTextStyles.headlineSm,
          bodyLarge: AppTextStyles.bodyLg,
          bodyMedium: AppTextStyles.bodyMd,
          bodySmall: AppTextStyles.bodySm,
          labelLarge: AppTextStyles.labelCaps,
          labelSmall: AppTextStyles.labelSm,
        ),
        cardTheme: const CardThemeData(
          color: AppColors.surface0,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12))),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.surface1,
          contentTextStyle:
              AppTextStyles.bodySm.copyWith(color: AppColors.textPrimary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: _ready
          ? LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < AppBreakpoints.medium;
                if (isMobile) {
                  return MobileAppShell(
                    connectionService: connectionService,
                    authService: authService,
                  );
                }
                return AppShell(client: client);
              },
            )
          : const Scaffold(
              backgroundColor: AppColors.background,
              body: Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
            ),
    );
  }
}
