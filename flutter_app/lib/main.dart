import 'dart:async';

import 'package:flutter/material.dart';

import 'services/local_backend.dart';
import 'services/monitoring_client.dart';
import 'theme.dart';
import 'screens/app_shell.dart';

void main() {
  const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://127.0.0.1:8765');
  const autoStart = String.fromEnvironment('AUTO_START_BACKEND', defaultValue: 'false') == 'true';
  runApp(DriverMonitorApp(apiUrl: apiUrl, autoStartBackend: autoStart));
}

class DriverMonitorApp extends StatefulWidget {
  const DriverMonitorApp({super.key, required this.apiUrl, required this.autoStartBackend});
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.surface1,
          contentTextStyle: AppTextStyles.bodySm.copyWith(color: AppColors.textPrimary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: AppShell(client: client),
    );
  }
}
