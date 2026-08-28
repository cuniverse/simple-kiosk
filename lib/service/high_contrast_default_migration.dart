import 'dart:convert';
import 'dart:io';

import 'runtime_paths.dart';
import 'ui_theme_service.dart';

typedef MenuOverrideValidator = void Function(Map<String, dynamic> override);

/// 고대비 UI 기본값을 기존 설치에 한 번 강제 적용한다.
class HighContrastDefaultMigration {
  static const migrationId = 'high-contrast-default-v1';

  final String? markerPath;
  final String? overridePath;
  final String? backupRoot;

  const HighContrastDefaultMigration({
    this.markerPath,
    this.overridePath,
    this.backupRoot,
  });

  factory HighContrastDefaultMigration.runtime() =>
      HighContrastDefaultMigration(
        markerPath: RuntimePaths.highContrastDefaultMigration,
        overridePath: RuntimePaths.menuOverride,
        backupRoot: RuntimePaths.backups,
      );

  Future<Map<String, dynamic>?> apply(
    Map<String, dynamic> defaults,
    Map<String, dynamic>? override, {
    MenuOverrideValidator? validate,
  }) async {
    final marker = markerPath;
    if (marker == null || await File(marker).exists()) return override;

    var result = override;
    if (override != null) {
      result = applyAppearanceDefaults(defaults, override);
      validate?.call(result);
      final destination = overridePath;
      if (destination != null) {
        final file = File(destination);
        final original = await file.exists()
            ? await file.readAsString()
            : const JsonEncoder.withIndent('  ').convert(override);
        await _backup(original);
        await RuntimePaths.atomicWrite(
          destination,
          const JsonEncoder.withIndent('  ').convert(result),
        );
      }
    }

    await RuntimePaths.atomicWrite(
      marker,
      const JsonEncoder.withIndent('  ').convert({
        'migration': migrationId,
        'appliedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    return result;
  }

  static Map<String, dynamic> applyAppearanceDefaults(
    Map<String, dynamic> defaults,
    Map<String, dynamic> override,
  ) {
    final defaultLayout = defaults['layout'];
    if (defaultLayout is! Map) {
      throw const FormatException('기본 설정의 layout 객체가 없습니다.');
    }
    final result = jsonDecode(jsonEncode(override)) as Map<String, dynamic>;
    final existingLayout = result['layout'];
    final layout = existingLayout is Map
        ? Map<String, dynamic>.from(existingLayout)
        : <String, dynamic>{};
    for (final key in UiThemeService.appearanceKeys) {
      if (defaultLayout.containsKey(key)) {
        layout[key] = jsonDecode(jsonEncode(defaultLayout[key]));
      }
    }
    result['layout'] = layout;
    return result;
  }

  Future<void> _backup(String original) async {
    final root = backupRoot;
    if (root == null) return;
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final path = '$root${Platform.pathSeparator}'
        'menu.override.before-high-contrast-$timestamp.json';
    await RuntimePaths.atomicWrite(path, original);
  }
}
