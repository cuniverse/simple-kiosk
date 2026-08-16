import 'dart:io';

import 'package:flutter/services.dart';

import 'runtime_paths.dart';

enum StartupLaunchMode { signage, hidden }

class WindowsStartupStatus {
  final bool supported;
  final bool registered;
  final bool targetMatches;
  final StartupLaunchMode mode;
  final String? shortcutPath;
  final String? targetPath;

  const WindowsStartupStatus({
    required this.supported,
    required this.registered,
    required this.targetMatches,
    required this.mode,
    this.shortcutPath,
    this.targetPath,
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
    );
  }
}

class WindowsStartupService {
  static const _channel = MethodChannel('simple_kiosk/windows_startup');

  bool get supported => Platform.isWindows;

  String get _installRoot =>
      RuntimePaths.dataRoot ?? File(Platform.resolvedExecutable).parent.path;

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
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'getStatus',
      {'targetPath': _launcherPath},
    );
    return WindowsStartupStatus.fromMap(result ?? const {});
  }

  Future<WindowsStartupStatus> register(StartupLaunchMode mode) async {
    if (!supported) return getStatus();
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

  Future<WindowsStartupStatus> unregister() async {
    if (!supported) return getStatus();
    await _channel.invokeMethod<bool>('unregister');
    return getStatus();
  }
}
