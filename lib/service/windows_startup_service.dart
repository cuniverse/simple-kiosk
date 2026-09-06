import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'runtime_paths.dart';
import 'app_logger.dart';

enum StartupLaunchMode { signage, hidden }

class WindowsStartupStatus {
  final bool supported;
  final bool registered;
  final bool targetMatches;
  final StartupLaunchMode mode;
  final String? shortcutPath;
  final String? targetPath;
  final bool fastStartup;
  final bool enabled;

  const WindowsStartupStatus({
    required this.supported,
    required this.registered,
    required this.targetMatches,
    required this.mode,
    this.shortcutPath,
    this.targetPath,
    this.fastStartup = false,
    this.enabled = true,
  });

  factory WindowsStartupStatus.fromMap(Map<Object?, Object?> map) {
    final mode = map['mode'] == 'hidden'
        ? StartupLaunchMode.hidden
        : StartupLaunchMode.signage;
    return WindowsStartupStatus(
      supported: map['supported'] == true,
      registered: map['registered'] == true,
      targetMatches: map['targetMatches'] == true,
      mode: mode,
      shortcutPath: map['shortcutPath'] as String?,
      targetPath: map['targetPath'] as String?,
      fastStartup: map['method'] == 'task',
      enabled: map['enabled'] != false,
    );
  }
}

class WindowsStartupService {
  WindowsStartupService({
    String? installRootOverride,
    Future<ProcessResult> Function(String, List<String>)? processRunner,
  })  : _installRootOverride = installRootOverride,
        _processRunner = processRunner ??
            ((executable, arguments) => Process.run(executable, arguments,
                stdoutEncoding: utf8, stderrEncoding: utf8));

  final String? _installRootOverride;
  final Future<ProcessResult> Function(String, List<String>) _processRunner;
  static const _channel = MethodChannel('simple_kiosk/windows_startup');

  bool get supported => Platform.isWindows;

  String get _installRoot =>
      _installRootOverride ??
      RuntimePaths.dataRoot ??
      File(Platform.resolvedExecutable).parent.path;

  Future<WindowsStartupStatus?> _taskAction(String action,
      [StartupLaunchMode mode = StartupLaunchMode.signage]) async {
    final script = File(
        '$_installRoot${Platform.pathSeparator}updater${Platform.pathSeparator}configure-startup.ps1');
    if (!await script.exists()) return null;
    final result = await _processRunner('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      script.path,
      '-Action',
      action,
      '-InstallRoot',
      _installRoot,
      '-Mode',
      mode.name,
    ]);
    if (result.exitCode != 0) {
      throw StateError(
          'Windows 자동 실행 설정 실패: ${result.stderr.toString().trim()}');
    }
    return WindowsStartupStatus.fromMap(
        jsonDecode(result.stdout.toString()) as Map<String, dynamic>);
  }

  String get _launcherPath {
    final launcher = RuntimePaths.child('ysignage_launcher.exe');
    return launcher != null && File(launcher).existsSync()
        ? launcher
        : Platform.resolvedExecutable;
  }

  Future<WindowsStartupStatus> getStatus() async {
    if (!supported) {
      return const WindowsStartupStatus(
        supported: false,
        registered: false,
        targetMatches: false,
        mode: StartupLaunchMode.signage,
      );
    }
    final task = await _taskAction('Status');
    if (task?.registered == true) return task!;
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'getStatus',
      {'targetPath': _launcherPath},
    );
    return WindowsStartupStatus.fromMap(result ?? const {});
  }

  Future<WindowsStartupStatus> register(StartupLaunchMode mode) async {
    if (!supported) return getStatus();
    final task = await _taskAction('Register', mode);
    if (task != null) return task;
    final registered = await _channel.invokeMethod<bool>('register', {
      'targetPath': _launcherPath,
      'workingDirectory': _installRoot,
      'mode': mode.name,
    });
    if (registered != true) {
      throw StateError('Windows 시작프로그램 바로가기를 만들지 못했습니다.');
    }
    return getStatus();
  }

  /// Update migration never opts an unregistered or disabled user into startup.
  Future<void> migrateLegacyRegistration() async {
    if (!supported) return;
    try {
      await _taskAction('Migrate');
    } catch (error, stackTrace) {
      // Preserve the previous startup entry and retry on the next launch.
      AppLogger.error(LogCategory.app, error, stackTrace);
    }
  }

  Future<WindowsStartupStatus> unregister() async {
    if (!supported) return getStatus();
    await _taskAction('Unregister');
    await _channel.invokeMethod<bool>('unregister');
    return getStatus();
  }
}
