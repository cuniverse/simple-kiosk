import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'runtime_paths.dart';
import 'ui_theme_service.dart';

typedef MenuOverrideValidator = FutureOr<void> Function(
    Map<String, dynamic> override);

/// 구버전의 테마와 모양 재정의를 제거하고 고대비 텍스트 테마에 한 번 연결한다.
class HighContrastDefaultMigration {
  static const migrationId = 'high-contrast-text-default-v2';
  static const themeId = 'preloaded:high-contrast-text';

  final String? markerPath;
  final String? overridePath;
  final String? backupRoot;
  final UiThemeService? themeService;

  const HighContrastDefaultMigration({
    this.markerPath,
    this.overridePath,
    this.backupRoot,
    this.themeService,
  });

  factory HighContrastDefaultMigration.runtime(
          {UiThemeService? themeService}) =>
      HighContrastDefaultMigration(
        markerPath: RuntimePaths.highContrastDefaultMigration,
        overridePath: RuntimePaths.menuOverride,
        backupRoot: RuntimePaths.backups,
        themeService: themeService,
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
      final theme = await (themeService ?? UiThemeService()).find(themeId);
      if (theme == null) {
        throw const FormatException('마이그레이션에 필요한 high-contrast-text 테마가 없습니다.');
      }
      final themedDefaults =
          jsonDecode(jsonEncode(defaults)) as Map<String, dynamic>;
      UiThemeService.applyValues(themedDefaults, theme.values);
      result = applyAppearanceDefaults(themedDefaults, override);
      await validate?.call(result);
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
        'uiTheme': themeId,
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
      layout.remove(key);
    }
    result['layout'] = layout;
    final existingSelection = result['languageSelection'];
    if (existingSelection is Map) {
      final selection = Map<String, dynamic>.from(existingSelection);
      for (final key in UiThemeService.languageSelectionAppearanceKeys) {
        selection.remove(key);
      }
      result['languageSelection'] = selection;
    }
    result['uiTheme'] = themeId;
    result['uiThemeFallback'] = UiThemeService.appearanceValues(defaults);
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
