import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../model/idle_config.dart';
import '../model/layout_config.dart';
import '../model/menu_config.dart';
import '../model/menu_language.dart';
import '../model/webview_data_policy.dart';
import 'app_logger.dart';
import 'menu_config_migrator.dart';
import 'menu_config_merger.dart';
import 'runtime_paths.dart';

/// 기본 설정과 외부 운영 설정을 읽고 구형 형식을 자동 마이그레이션하는 로더.
///
/// 두 가지 최상위 JSON 구조를 모두 지원한다.
///
/// - 현재 형식: `{ "languages": [{ "topics": [...] }] }`
/// - 구형 형식: 최상위 `items` 또는 `languages[].items`
class MenuConfigLoader {
  /// 기본 에셋 경로.
  static const String defaultAssetPath = 'assets/config/menu.defaults.json';

  final String assetPath;

  const MenuConfigLoader({this.assetPath = defaultAssetPath});

  /// 앱에 포함된 기본 설정 원본을 반환한다.
  Future<Map<String, dynamic>> readDefaults() async {
    final decoded = json.decode(await rootBundle.loadString(assetPath));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('menu.defaults.json: 최상위 객체 필요');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> readOverride() async {
    final path = RuntimePaths.menuOverride;
    if (path == null || !await File(path).exists()) return <String, dynamic>{};
    final decoded = json.decode(await File(path).readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('menu.override.json: 최상위 객체 필요');
    }
    return decoded;
  }

  /// 기본 설정과 오버라이드를 병합한 현재 유효 설정을 반환한다.
  ///
  /// 오버라이드가 없으면 기본 설정 전체를 반환하며, 병합 설정이 유효하지
  /// 않으면 앱과 동일하게 마지막 정상 설정을 사용한다.
  Future<Map<String, dynamic>> readEffective() async {
    final defaults = await readDefaults();
    try {
      final merged =
          MenuConfigMerger.merge(defaults, await readOverride()).json;
      parse(merged);
      return merged;
    } catch (_) {
      final lastGoodPath = RuntimePaths.lastGoodConfig;
      if (lastGoodPath != null && await File(lastGoodPath).exists()) {
        final decoded = json.decode(await File(lastGoodPath).readAsString());
        if (decoded is Map<String, dynamic>) {
          parse(decoded);
          return decoded;
        }
      }
      rethrow;
    }
  }

  Future<void> saveOverride(Map<String, dynamic> override) async {
    final raw = await rootBundle.loadString(assetPath);
    final defaults = json.decode(raw);
    if (defaults is! Map<String, dynamic>) {
      throw const FormatException('menu.defaults.json: 최상위 객체 필요');
    }
    final merged = MenuConfigMerger.merge(defaults, override).json;
    parse(merged);
    final path = RuntimePaths.menuOverride;
    if (path == null) {
      throw UnsupportedError('메뉴 설정 저장 경로를 사용할 수 없습니다.');
    }
    await RuntimePaths.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(override),
    );
  }

  /// 에셋에서 메뉴 설정을 로드한다.
  ///
  /// 파싱 실패 시 [FormatException]을 던진다.
  Future<MenuConfig> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final defaults = json.decode(raw);
    if (defaults is! Map<String, dynamic>) {
      throw const FormatException('menu.defaults.json: 최상위 객체 필요');
    }

    await RuntimePaths.ensureStructure();
    try {
      Map<String, dynamic>? override;
      final overridePath = RuntimePaths.menuOverride;
      if (overridePath != null && await File(overridePath).exists()) {
        final overrideFile = File(overridePath);
        final original = await overrideFile.readAsString();
        final decoded = json.decode(original);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('menu.override.json: 최상위 객체 필요');
        }
        override = decoded;
        if (MenuConfigMigrator.needsMigration(defaults, override)) {
          final migrated = MenuConfigMigrator.migrate(defaults, override);
          final validated = MenuConfigMerger.merge(defaults, migrated).json;
          parse(validated);
          await _backupBeforeMigration(original);
          await RuntimePaths.atomicWrite(
            overridePath,
            const JsonEncoder.withIndent('  ').convert(migrated),
          );
          override = migrated;
          AppLogger.info(
            LogCategory.app,
            '구형 메뉴 설정을 schemaVersion 2 구조로 마이그레이션했습니다.',
          );
        }
      }
      final merged = MenuConfigMerger.merge(defaults, override).json;
      _resolveExternalMediaPaths(merged);
      final config = parse(merged);
      final lastGoodPath = RuntimePaths.lastGoodConfig;
      if (lastGoodPath != null) {
        await RuntimePaths.atomicWrite(
          lastGoodPath,
          const JsonEncoder.withIndent('  ').convert(merged),
        );
      }
      return config;
    } catch (error, stackTrace) {
      AppLogger.error(LogCategory.app, error, stackTrace);
      final lastGoodPath = RuntimePaths.lastGoodConfig;
      if (lastGoodPath != null && await File(lastGoodPath).exists()) {
        final decoded = json.decode(await File(lastGoodPath).readAsString());
        return parse(decoded);
      }
      rethrow;
    }
  }

  static Future<void> _backupBeforeMigration(String original) async {
    final backupRoot = RuntimePaths.backups;
    if (backupRoot == null) return;
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final path = '$backupRoot${Platform.pathSeparator}'
        'menu.override.before-migration-$timestamp.json';
    await RuntimePaths.atomicWrite(path, original);
  }

  /// 이미 병합된 JSON을 검증하고 모델로 변환한다.
  static MenuConfig parse(dynamic decoded) {
    final LayoutConfig layout;
    IdleConfig idle = IdleConfig.defaults;
    List<MenuLanguage> languages;
    String? requestedDefaultLanguage;
    var selectionTitle = '언어를 선택하세요';
    var selectionSubtitle = 'Please select your language';
    var topicSelectionTitle = '주제를 선택하세요';
    var topicSelectionSubtitle = 'Please select a topic';
    var skipSingleTopic = true;
    var webViewDataPolicy = WebViewDataPolicy.defaults;
    final registeredLanguageIds = <String>{};

    if (decoded is List) {
      // 구버전: 배열 = items만 정의된 형식.
      layout = LayoutConfig.defaults;
      languages = [_legacyLanguage(decoded)];
    } else if (decoded is Map<String, dynamic>) {
      final layoutValue = decoded['layout'];
      if (layoutValue == null) {
        layout = LayoutConfig.defaults;
      } else if (layoutValue is Map<String, dynamic>) {
        layout = LayoutConfig.fromJson(layoutValue);
      } else {
        throw const FormatException(
          'menu.json: "layout"은 객체여야 함',
        );
      }

      final idleValue = decoded['idle'];
      if (idleValue == null) {
        idle = IdleConfig.defaults;
      } else if (idleValue is Map<String, dynamic>) {
        idle = IdleConfig.fromJson(idleValue);
      } else {
        throw const FormatException(
          'menu.json: "idle"은 객체여야 함',
        );
      }

      final webViewDataValue = decoded['webViewData'];
      if (webViewDataValue != null) {
        if (webViewDataValue is! Map<String, dynamic>) {
          throw const FormatException('menu.json: "webViewData"는 객체여야 함');
        }
        webViewDataPolicy = WebViewDataPolicy.fromJson(webViewDataValue);
      }

      final languagesValue = decoded['languages'];
      if (languagesValue != null) {
        if (languagesValue is! List || languagesValue.isEmpty) {
          throw const FormatException(
              'menu.json: "languages"는 한 개 이상의 배열이어야 함');
        }
        languages = <MenuLanguage>[];
        final languageIds = <String>{};
        for (var i = 0; i < languagesValue.length; i++) {
          final raw = languagesValue[i];
          if (raw is! Map<String, dynamic>) {
            throw FormatException('menu.json languages[$i]: 객체 필요');
          }
          final language = MenuLanguage.fromJson(raw, i);
          if (!languageIds.add(language.id)) {
            throw FormatException(
                'menu.json languages: 언어 id 중복 (${language.id})');
          }
          registeredLanguageIds.add(language.id);
          if (!language.hidden) languages.add(language);
        }
        if (languages.isEmpty) {
          throw const FormatException(
            'menu.json languages: 표시할 언어가 한 개 이상 필요',
          );
        }
      } else {
        final itemsValue = decoded['items'];
        if (itemsValue is! List) {
          throw const FormatException(
            'menu.json: "languages" 또는 "items"가 필요함',
          );
        }
        languages = [_legacyLanguage(itemsValue)];
      }

      final defaultLanguageValue = decoded['defaultLanguage'];
      if (defaultLanguageValue != null && defaultLanguageValue is! String) {
        throw const FormatException('menu.json: "defaultLanguage"는 문자열이어야 함');
      }
      requestedDefaultLanguage = defaultLanguageValue as String?;

      final selectionValue = decoded['languageSelection'];
      if (selectionValue != null) {
        if (selectionValue is! Map<String, dynamic>) {
          throw const FormatException('menu.json: "languageSelection"은 객체여야 함');
        }
        final title = selectionValue['title'];
        final subtitle = selectionValue['subtitle'];
        final topicTitle = selectionValue['topicTitle'];
        final topicSubtitle = selectionValue['topicSubtitle'];
        final skipSingle = selectionValue['skipSingleTopic'];
        if (title != null && (title is! String || title.trim().isEmpty)) {
          throw const FormatException(
              'menu.json languageSelection.title: 문자열 필요');
        }
        if (subtitle != null && subtitle is! String) {
          throw const FormatException(
              'menu.json languageSelection.subtitle: 문자열 필요');
        }
        if (topicTitle != null &&
            (topicTitle is! String || topicTitle.trim().isEmpty)) {
          throw const FormatException(
            'menu.json languageSelection.topicTitle: 문자열 필요',
          );
        }
        if (topicSubtitle != null && topicSubtitle is! String) {
          throw const FormatException(
            'menu.json languageSelection.topicSubtitle: 문자열 필요',
          );
        }
        if (skipSingle != null && skipSingle is! bool) {
          throw const FormatException(
            'menu.json languageSelection.skipSingleTopic: bool 필요',
          );
        }
        if (title is String) selectionTitle = title.trim();
        if (subtitle is String) selectionSubtitle = subtitle.trim();
        if (topicTitle is String) topicSelectionTitle = topicTitle.trim();
        if (topicSubtitle is String) {
          topicSelectionSubtitle = topicSubtitle.trim();
        }
        if (skipSingle is bool) skipSingleTopic = skipSingle;
      }
    } else {
      throw const FormatException(
        'menu.json: 최상위 구조는 객체 또는 배열이어야 함',
      );
    }

    final requestedId = requestedDefaultLanguage?.trim().isNotEmpty == true
        ? requestedDefaultLanguage!.trim()
        : null;
    if (requestedId != null &&
        registeredLanguageIds.isNotEmpty &&
        !registeredLanguageIds.contains(requestedId)) {
      throw FormatException(
        'menu.json defaultLanguage: 등록되지 않은 언어 ($requestedId)',
      );
    }
    final defaultLanguageId = languages.any(
      (language) => language.id == requestedId,
    )
        ? requestedId!
        : languages.first.id;
    return MenuConfig(
      layout: layout,
      idle: idle,
      languages: List.unmodifiable(languages),
      defaultLanguageId: defaultLanguageId,
      languageSelectionTitle: selectionTitle,
      languageSelectionSubtitle: selectionSubtitle,
      topicSelectionTitle: topicSelectionTitle,
      topicSelectionSubtitle: topicSelectionSubtitle,
      skipSingleTopic: skipSingleTopic,
      webViewDataPolicy: webViewDataPolicy,
    );
  }

  static MenuLanguage _legacyLanguage(List<dynamic> rawItems) {
    return MenuLanguage.fromJson({
      'id': 'default',
      'label': '시작',
      'items': rawItems,
    }, 0);
  }

  static dynamic _resolveExternalMediaPaths(dynamic value) {
    if (value is Map) {
      for (final key in value.keys.toList()) {
        value[key] = _resolveExternalMediaPaths(value[key]);
      }
      return value;
    }
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        value[i] = _resolveExternalMediaPaths(value[i]);
      }
      return value;
    }
    if (value is String &&
        (value.startsWith('media/') || value.startsWith(r'media\'))) {
      return RuntimePaths.child(value) ?? value;
    }
    return value;
  }
}
