import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LocalBackendProcess {
  LocalBackendProcess({
    this.pythonExecutable = const String.fromEnvironment(
      'BACKEND_PYTHON',
      defaultValue: 'python',
    ),
    this.backendRoot = const String.fromEnvironment(
      'BACKEND_ROOT',
      defaultValue: '..',
    ),
  });

  final String pythonExecutable;
  final String backendRoot;
  Process? _process;

  static bool get supported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  bool get isRunning => _process != null;

  Future<bool> start() async {
    if (!supported || isRunning) return isRunning;
    try {
      final process = await Process.start(
        pythonExecutable,
        const [
          'main.py',
          '--headless',
          '--api',
          '--api-host',
          '127.0.0.1',
          '--api-port',
          '8765',
        ],
        workingDirectory: backendRoot,
      );
      _process = process;
      process.stdout.transform(utf8.decoder).listen((_) {});
      process.stderr.transform(utf8.decoder).listen((_) {});
      unawaited(process.exitCode.then((_) {
        if (identical(_process, process)) _process = null;
      }));
      return true;
    } on ProcessException {
      return false;
    }
  }

  Future<void> stop() async {
    final process = _process;
    _process = null;
    process?.kill();
    if (process != null) await process.exitCode;
  }

  Future<void> dispose() => stop();
}
