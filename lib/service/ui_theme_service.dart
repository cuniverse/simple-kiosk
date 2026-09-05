import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'runtime_paths.dart';

class UiThemeException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const UiThemeException(this.statusCode, this.code, this.message);

  @override
  String toString() => message;
}

class UiTheme {
  final String id;
  final String name;
  final String description;
  final bool preloaded;
  final Map<String, dynamic> values;

  const UiTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.preloaded,
    required this.values,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'preloaded': preloaded,
        'values': values,
      };
}

typedef PreloadedThemeLoader = Future<List<Map<String, dynamic>>> Function();

class UiThemeService {
  static const appearanceKeys = <String>{
    'brightness',
    'hideItemIcons',
    'hideTopicIcons',
    'fontFamily',
    'menuFontFamily',
    'sideWidth',
    'barHeight',
    'buttonHeight',
    'buttonWidth',
    'buttonGap',
    'barColor',
    'selectedTopicLabelColor',
    'buttonColor',
    'buttonForegroundColor',
    'selectedButtonColor',
    'selectedButtonForegroundColor',
  };

  static const languageSelectionAppearanceKeys = <String>{
    'fontFamily',
    'backgroundColor',
    'foregroundColor',
    'secondaryForegroundColor',
    'buttonWidth',
    'buttonHeight',
    'buttonColor',
    'buttonForegroundColor',
    'selectedButtonColor',
    'selectedButtonForegroundColor',
  };

  final String? userThemeDirectory;
  final PreloadedThemeLoader _preloadedThemeLoader;

  UiThemeService({
    String? userThemeDirectory,
    PreloadedThemeLoader? preloadedThemeLoader,
  })  : userThemeDirectory = userThemeDirectory ?? RuntimePaths.themes,
        _preloadedThemeLoader =
            preloadedThemeLoader ?? _loadPreloadedThemesFromAssets;

  Future<void> ensureReady() async {
    final directory = userThemeDirectory;
    if (directory != null) await Directory(directory).create(recursive: true);
  }

  Future<UiTheme?> find(String id) async {
    for (final theme in await list()) {
      if (theme.id == id) return theme;
    }
    return null;
  }

  /// 테마가 관리하는 모양 값만 복사한다. 메뉴와 동작 설정은 포함하지 않는다.
  static Map<String, dynamic> appearanceValues(Map<String, dynamic> config) {
    final layout = config['layout'];
    final selection = config['languageSelection'];
    return {
      if (layout is Map)
        for (final key in appearanceKeys)
          if (layout.containsKey(key)) key: layout[key],
      if (selection is Map)
        'languageSelection': {
          for (final key in languageSelectionAppearanceKeys)
            if (selection.containsKey(key)) key: selection[key],
        },
    };
  }

  static void applyValues(
    Map<String, dynamic> config,
    Map<String, dynamic> values,
  ) {
    final layout = Map<String, dynamic>.from(config['layout'] as Map? ?? {});
    for (final key in appearanceKeys) {
      if (values.containsKey(key)) layout[key] = values[key];
    }
    config['layout'] = layout;
    final rawSelection = values['languageSelection'];
    if (rawSelection is Map) {
      final selection =
          Map<String, dynamic>.from(config['languageSelection'] as Map? ?? {});
      for (final key in languageSelectionAppearanceKeys) {
        if (rawSelection.containsKey(key)) selection[key] = rawSelection[key];
      }
      config['languageSelection'] = selection;
    }
  }

  /// 이전 버전의 전체 설정을 저장해도 당시 테마에서 상속한 값은 고정하지 않는다.
  static void removeInheritedValues(Map<String, dynamic> config) {
    if (config['uiTheme'] is! String || (config['uiTheme'] as String).isEmpty) {
      return;
    }
    final baseline = config['uiThemeFallback'];
    if (baseline is! Map) return;
    final layout = config['layout'];
    if (layout is Map) {
      for (final key in appearanceKeys) {
        if (baseline.containsKey(key) && layout[key] == baseline[key]) {
          layout.remove(key);
        }
      }
    }
    final selection = config['languageSelection'];
    final selectionBaseline = baseline['languageSelection'];
    if (selection is Map && selectionBaseline is Map) {
      for (final key in languageSelectionAppearanceKeys) {
        if (selectionBaseline.containsKey(key) &&
            selection[key] == selectionBaseline[key]) {
          selection.remove(key);
        }
      }
    }
  }

  Future<List<UiTheme>> list() async {
    final result = <UiTheme>[];
    for (final json in await _preloadedThemeLoader()) {
      result.add(_parseTheme(json, preloaded: true));
    }
    final directoryPath = userThemeDirectory;
    if (directoryPath != null) {
      final directory = Directory(directoryPath);
      if (await directory.exists()) {
        final files = await directory
            .list(followLinks: false)
            .where((entity) => entity is File && entity.path.endsWith('.json'))
            .cast<File>()
            .toList();
        files.sort((left, right) => left.path.compareTo(right.path));
        for (final file in files) {
          try {
            final decoded = jsonDecode(await file.readAsString());
            if (decoded is Map<String, dynamic>) {
              result.add(_parseTheme(decoded, preloaded: false));
            }
          } catch (_) {
            // 손상된 사용자 테마 하나 때문에 전체 목록을 사용할 수 없게 하지 않는다.
          }
        }
      }
    }
    final ids = <String>{};
    final names = <String>{};
    return result.where((theme) {
      return ids.add(theme.id) && names.add(theme.name.toLowerCase());
    }).toList();
  }

  Future<UiTheme> saveUserTheme(
    String name,
    Map<String, dynamic> values, {
    String description = '',
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty || normalizedName.length > 60) {
      throw const UiThemeException(
          400, 'invalid-theme-name', '테마 이름은 1~60자로 입력하세요.');
    }
    if (RegExp(r'[\\/:*?"<>|]').hasMatch(normalizedName)) {
      throw const UiThemeException(
          400, 'invalid-theme-name', '테마 이름에 파일 경로 문자를 사용할 수 없습니다.');
    }
    final themes = await list();
    if (themes.any((theme) =>
        theme.preloaded &&
        theme.name.toLowerCase() == normalizedName.toLowerCase())) {
      throw const UiThemeException(
          409, 'reserved-theme-name', '프리로드 테마와 같은 이름은 사용할 수 없습니다.');
    }
    final normalizedValues = _normalizeValues(values);
    String? existingHash;
    for (final theme in themes) {
      if (!theme.preloaded &&
          theme.name.toLowerCase() == normalizedName.toLowerCase()) {
        existingHash = theme.id.substring('user:'.length);
        break;
      }
    }
    final hash =
        existingHash ?? sha256.convert(utf8.encode(normalizedName)).toString();
    final theme = UiTheme(
      id: 'user:$hash',
      name: normalizedName,
      description: description.trim(),
      preloaded: false,
      values: normalizedValues,
    );
    final directoryPath = userThemeDirectory;
    if (directoryPath == null) {
      throw const UiThemeException(
          501, 'themes-unavailable', '이 플랫폼에서는 사용자 테마를 저장할 수 없습니다.');
    }
    await ensureReady();
    final file = File('$directoryPath${Platform.pathSeparator}$hash.json');
    await RuntimePaths.atomicWrite(
      file.path,
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'id': theme.id,
        'name': theme.name,
        'description': theme.description,
        'values': theme.values,
      }),
    );
    return theme;
  }

  Future<void> deleteUserTheme(String id) async {
    if (!id.startsWith('user:')) {
      throw const UiThemeException(
          403, 'preloaded-theme', '프리로드 테마는 삭제할 수 없습니다.');
    }
    final hash = id.substring('user:'.length);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const UiThemeException(400, 'invalid-theme-id', '잘못된 테마 ID입니다.');
    }
    final directoryPath = userThemeDirectory;
    if (directoryPath == null) {
      throw const UiThemeException(
          501, 'themes-unavailable', '이 플랫폼에서는 사용자 테마를 삭제할 수 없습니다.');
    }
    final file = File('$directoryPath${Platform.pathSeparator}$hash.json');
    if (!await file.exists()) {
      throw const UiThemeException(
          404, 'theme-not-found', '사용자 테마를 찾을 수 없습니다.');
    }
    await file.delete();
  }

  static UiTheme _parseTheme(
    Map<String, dynamic> json, {
    required bool preloaded,
  }) {
    final id = json['id'];
    final name = json['name'];
    final description = json['description'];
    final values = json['values'];
    if (id is! String ||
        id.trim().isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        values is! Map<String, dynamic>) {
      throw const UiThemeException(
          500, 'invalid-theme', '테마 파일 형식이 올바르지 않습니다.');
    }
    final normalizedId = id.trim();
    if (!preloaded && !RegExp(r'^user:[0-9a-f]{64}$').hasMatch(normalizedId)) {
      throw const UiThemeException(
        500,
        'invalid-theme-id',
        '사용자 테마 ID 형식이 올바르지 않습니다.',
      );
    }
    return UiTheme(
      id: preloaded ? 'preloaded:$normalizedId' : normalizedId,
      name: name.trim(),
      description: description is String ? description.trim() : '',
      preloaded: preloaded,
      values: _normalizeValues(values),
    );
  }

  static Map<String, dynamic> _normalizeValues(Map<String, dynamic> values) {
    final result = <String, dynamic>{};
    for (final entry in values.entries) {
      if (entry.key == 'languageSelection') {
        final raw = entry.value;
        if (raw is! Map) {
          throw const UiThemeException(
            400,
            'invalid-theme-language-selection',
            '테마 languageSelection은 객체여야 합니다.',
          );
        }
        final selection = <String, dynamic>{};
        for (final selectionEntry in raw.entries) {
          final key = selectionEntry.key;
          final value = selectionEntry.value;
          if (key is! String ||
              !languageSelectionAppearanceKeys.contains(key)) {
            continue;
          }
          if (key == 'buttonWidth' || key == 'buttonHeight') {
            if (value != null &&
                (value is! num || !value.isFinite || value <= 0)) {
              throw const UiThemeException(
                400,
                'invalid-theme-language-selection',
                '테마 languageSelection 버튼 크기는 0보다 큰 숫자여야 합니다.',
              );
            }
          } else if (value != null && value is! String) {
            throw const UiThemeException(
              400,
              'invalid-theme-language-selection',
              '테마 languageSelection 글꼴과 색상은 문자열이어야 합니다.',
            );
          }
          selection[key] = value;
        }
        if (selection.isNotEmpty) result['languageSelection'] = selection;
        continue;
      }
      if (!appearanceKeys.contains(entry.key)) continue;
      final value = entry.value;
      if (value is String || value is num || value is bool || value == null) {
        result[entry.key] = value;
      }
    }
    if (result.isEmpty) {
      throw const UiThemeException(400, 'empty-theme', '저장할 UI 모양 값이 없습니다.');
    }
    final brightness = result['brightness'];
    if (brightness == null) {
      result['brightness'] = 'light';
    } else if (brightness is! String ||
        !const {'light', 'white', 'dark'}
            .contains(brightness.trim().toLowerCase())) {
      throw const UiThemeException(
        400,
        'invalid-theme-brightness',
        '테마 brightness는 light 또는 dark여야 합니다.',
      );
    } else {
      result['brightness'] =
          brightness.trim().toLowerCase() == 'dark' ? 'dark' : 'light';
    }
    final hideItemIcons = result['hideItemIcons'];
    if (hideItemIcons == null) {
      result['hideItemIcons'] = false;
    } else if (hideItemIcons is! bool) {
      throw const UiThemeException(
        400,
        'invalid-theme-hide-item-icons',
        '테마 hideItemIcons는 bool이어야 합니다.',
      );
    }
    final hideTopicIcons = result['hideTopicIcons'];
    if (hideTopicIcons == null) {
      result['hideTopicIcons'] = false;
    } else if (hideTopicIcons is! bool) {
      throw const UiThemeException(
        400,
        'invalid-theme-hide-topic-icons',
        '테마 hideTopicIcons는 bool이어야 합니다.',
      );
    }
    return result;
  }

  static Future<List<Map<String, dynamic>>>
      _loadPreloadedThemesFromAssets() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final paths = manifest
        .listAssets()
        .where((path) =>
            path.startsWith('assets/themes/') && path.endsWith('.json'))
        .toList()
      ..sort();
    final result = <Map<String, dynamic>>[];
    for (final path in paths) {
      final decoded = jsonDecode(await rootBundle.loadString(path));
      if (decoded is Map<String, dynamic>) result.add(decoded);
    }
    return result;
  }
}
