import 'dart:io';

/// 앱 버전 폴더와 독립적으로 유지되는 운영 데이터 경로.
class RuntimePaths {
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
  static String? get appState => child('state/app-state.json');
  static String? get downloads => child('downloads');
  static String? get logs => child('logs');

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
    ]) {
      await Directory(child(relative)!).create(recursive: true);
    }
  }

  static Future<void> atomicWrite(String path, String contents) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temporary = File('$path.tmp');
    await temporary.writeAsString(contents, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(path);
  }
}
