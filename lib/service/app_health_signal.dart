import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'runtime_paths.dart';

class AppHealthSignal {
  static Future<void> markReady() async {
    final path = RuntimePaths.appState;
    if (path == null) return;
    final info = await PackageInfo.fromPlatform();
    await RuntimePaths.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'status': 'ready',
        'version': info.version,
        'pid': pid,
        'readyAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }
}
