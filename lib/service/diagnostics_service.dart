import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'app_logger.dart';
import 'runtime_paths.dart';

class DiagnosticsService {
  const DiagnosticsService();

  Future<Map<String, dynamic>> createReport() async {
    final package = await PackageInfo.fromPlatform();
    final logs = <String, String>{};
    for (final category in LogCategory.values) {
      logs[category.name] = await AppLogger.read(category);
    }
    return {
      'schemaVersion': 1,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'application': {
        'name': package.appName,
        'version': package.version,
        'buildNumber': package.buildNumber,
      },
      'system': {
        'operatingSystem': Platform.operatingSystem,
        'operatingSystemVersion': Platform.operatingSystemVersion,
        'locale': Platform.localeName,
        'numberOfProcessors': Platform.numberOfProcessors,
        'dartVersion': Platform.version,
        'executable': Platform.resolvedExecutable,
        'dataRoot': RuntimePaths.dataRoot,
      },
      'logs': logs,
    };
  }
}
