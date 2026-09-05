import 'dart:io';

/// 앱 버전 폴더와 독립적으로 유지되는 운영 데이터 경로.
class RuntimePaths {
  static int _atomicWriteSequence = 0;
  static final Map<String, Future<void>> _atomicWrites = {};

  static String? get dataRoot {
    final overridden = Platform.environment['SIMPLE_KIOSK_DATA_DIR'];
    if (overridden != null && overridden.trim().isNotEmpty) {
      return overridden.trim();
    }
    if (!Platform.isWindows) return null;
    return File(Platform.resolvedExecutable).parent.path;
  }

  static String? child(String relativePath) {
    final root = dataRoot;
    if (root == null) return null;
    return '$root${Platform.pathSeparator}'
        '${relativePath.replaceAll('/', Platform.pathSeparator)}';
  }

  static String? get menuOverride => child('config/menu.override.json');
  static String? get updatePolicy => child('config/update-policy.json');
  static String? get adminPin => child('config/admin-pin.json');
  static String? get adminApiSettings => child('config/admin-api.json');
  static String? get updateState => child('state/update-state.json');
  static String? get lastGoodConfig => child('state/last-good-config.json');
  static String? get previousSettingsBackup =>
      child('state/previous-settings-backup.json');
  static String? get highContrastDefaultMigration =>
      child('state/high-contrast-text-default-v2.json');
  static String? get appState => child('state/app-state.json');
  static String? get downloads => child('downloads');
  static String? get logs => child('logs');
  static String? get backups => child('backups');
  static String? get fonts => child('fonts');
  static String? get exdata => child('exdata');
  static String? get themes => child('themes');

  static Future<void> ensureStructure() async {
    final root = dataRoot;
    if (root == null) return;
    for (final relative in [
      'config',
      'media',
      'state',
      'logs',
      'downloads',
      'versions',
      'diagnostics',
      'backups',
      'fonts',
      'exdata',
      'themes',
    ]) {
      await Directory(child(relative)!).create(recursive: true);
    }
  }

  static Future<void> atomicWrite(String path, String contents) async {
    final writeKey = Platform.isWindows
        ? File(path).absolute.path.toLowerCase()
        : File(path).absolute.path;
    final previous = _atomicWrites[writeKey];
    late final Future<void> operation;
    operation = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // A failed write must not permanently block later recovery writes.
        }
      }
      await _atomicWriteNow(path, contents);
    }();
    _atomicWrites[writeKey] = operation;
    try {
      await operation;
    } finally {
      if (identical(_atomicWrites[writeKey], operation)) {
        _atomicWrites.remove(writeKey);
      }
    }
  }

  static Future<void> _atomicWriteNow(String path, String contents) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final sequence = _atomicWriteSequence++;
    final temporary = File(
      '$path.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}-$sequence',
    );
    try {
      await temporary.writeAsString(contents, flush: true);
      // File.rename replaces an existing file on the same volume. Keeping the
      // old file in place until this operation avoids the delete/rename gap.
      await temporary.rename(path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
