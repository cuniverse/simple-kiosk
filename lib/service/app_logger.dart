import 'dart:async';
import 'dart:io';

import 'runtime_paths.dart';

enum LogCategory { app, webview, update, api }

class AppLogger {
  static const int maxFileBytes = 2 * 1024 * 1024;
  static const int retainedFiles = 5;
  static const Duration retention = Duration(days: 30);
  static Future<void> _writeQueue = Future<void>.value();

  static Future<void> initialize() async {
    await RuntimePaths.ensureStructure();
    await deleteOldLogs();
  }

  static void info(LogCategory category, String message) =>
      _enqueue(category, 'INFO', message);

  static void warning(LogCategory category, String message) =>
      _enqueue(category, 'WARN', message);

  static void error(
    LogCategory category,
    Object error, [
    StackTrace? stackTrace,
  ]) {
    final details = stackTrace == null ? '$error' : '$error\n$stackTrace';
    _enqueue(category, 'ERROR', details);
  }

  static void _enqueue(LogCategory category, String level, String message) {
    final safe = message
        .replaceAll(
            RegExp(r'([?&](?:token|key|secret|password|pin)=)[^&\s]+',
                caseSensitive: false),
            r'$1[REDACTED]')
        .replaceAll(
            RegExp(r'(Bearer\s+)[A-Za-z0-9._~-]+', caseSensitive: false),
            r'$1[REDACTED]');
    _writeQueue = _writeQueue.then((_) async {
      final path = _path(category);
      if (path == null) return;
      final file = File(path);
      await file.parent.create(recursive: true);
      if (await file.exists() && await file.length() >= maxFileBytes) {
        await _rotate(file);
      }
      final timestamp = DateTime.now().toUtc().toIso8601String();
      await file.writeAsString(
        '[$timestamp] [$level] $safe\n',
        mode: FileMode.append,
        flush: true,
      );
    }).catchError((_) {});
  }

  static Future<void> _rotate(File file) async {
    for (var index = retainedFiles - 1; index >= 1; index--) {
      final source = File('${file.path}.$index');
      if (!await source.exists()) continue;
      final destination = File('${file.path}.${index + 1}');
      if (await destination.exists()) await destination.delete();
      await source.rename(destination.path);
    }
    final first = File('${file.path}.1');
    if (await first.exists()) await first.delete();
    await file.rename(first.path);
  }

  static Future<void> deleteOldLogs() async {
    final directoryPath = RuntimePaths.logs;
    if (directoryPath == null) return;
    final directory = Directory(directoryPath);
    if (!await directory.exists()) return;
    final cutoff = DateTime.now().subtract(retention);
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      try {
        if ((await entity.stat()).modified.isBefore(cutoff)) {
          await entity.delete();
        }
      } catch (_) {}
    }
  }

  static Future<String> read(
    LogCategory category, {
    int maxBytes = 512 * 1024,
  }) async {
    await _writeQueue;
    final path = _path(category);
    if (path == null) return '';
    final files = <File>[
      for (var index = retainedFiles; index >= 1; index--) File('$path.$index'),
      File(path),
    ];
    final buffer = StringBuffer();
    for (final file in files) {
      if (!await file.exists()) continue;
      final contents = await file.readAsString();
      buffer.write(contents);
    }
    final value = buffer.toString();
    return value.length <= maxBytes
        ? value
        : value.substring(value.length - maxBytes);
  }

  static String? _path(LogCategory category) =>
      RuntimePaths.child('logs/${category.name}.log');
}
