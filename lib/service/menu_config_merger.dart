import 'dart:convert';

const Object _noDifference = Object();

class MenuMergeResult {
  final Map<String, dynamic> json;
  final List<String> warnings;

  const MenuMergeResult(this.json, this.warnings);
}

/// 새 기본 설정과 운영자 오버라이드를 병합한다.
class MenuConfigMerger {
  static const int currentSchemaVersion = 2;

  /// 완성된 설정에서 기본값과 다른 값만 추려 저장용 override를 만든다.
  ///
  /// 객체는 필드 단위로 축약하고, 배열은 삭제와 순서의 의미를 보존하기
  /// 위해 변경된 경우에만 배열 전체를 저장한다.
  static Map<String, dynamic> createOverride(
    Map<String, dynamic> defaults,
    Map<String, dynamic> effective,
  ) {
    final result = <String, dynamic>{
      'schemaVersion': defaults['schemaVersion'] ?? currentSchemaVersion,
    };
    final difference = _difference(defaults, effective);
    if (difference is Map) {
      for (final entry in difference.entries) {
        final key = entry.key.toString();
        if (key != 'schemaVersion') result[key] = _clone(entry.value);
      }
    }
    return result;
  }

  static MenuMergeResult merge(
    Map<String, dynamic> defaults,
    Map<String, dynamic>? override,
  ) {
    if (override == null) return MenuMergeResult(_cloneMap(defaults), const []);
    final schema = override['schemaVersion'] ?? currentSchemaVersion;
    if (schema is! num || schema.toInt() > currentSchemaVersion) {
      throw FormatException('지원하지 않는 menu.override schemaVersion: $schema');
    }

    final warnings = <String>[];
    final result = _cloneMap(defaults);
    for (final entry in override.entries) {
      if (entry.key == 'schemaVersion' || entry.key == 'items') continue;
      result[entry.key] = _mergeValue(result[entry.key], entry.value);
    }
    result['schemaVersion'] = defaults['schemaVersion'] ?? currentSchemaVersion;
    if (override.containsKey('items')) {
      final defaultItems = defaults['items'] ?? _firstLanguageItems(defaults);
      result['items'] = _mergeItems(defaultItems, override['items'], warnings);
      // 기존 items 오버라이드는 기존 단일 언어 동작을 그대로 유지한다.
      if (!override.containsKey('languages')) result.remove('languages');
    } else if (defaults.containsKey('items')) {
      result['items'] = _clone(defaults['items']);
    } else {
      result.remove('items');
    }
    return MenuMergeResult(result, List.unmodifiable(warnings));
  }

  static dynamic _firstLanguageItems(Map<String, dynamic> defaults) {
    final languages = defaults['languages'];
    if (languages is List && languages.isNotEmpty && languages.first is Map) {
      final language = languages.first as Map;
      final items = language['items'];
      if (items is List) return items;
      final topics = language['topics'];
      if (topics is List && topics.isNotEmpty && topics.first is Map) {
        return (topics.first as Map)['items'];
      }
    }
    throw const FormatException('menu.defaults.json: items 또는 languages 필요');
  }

  static dynamic _mergeValue(dynamic base, dynamic patch) {
    if (patch == null) return _clone(base);
    if (base is Map && patch is Map) {
      final result = <String, dynamic>{
        for (final entry in base.entries)
          entry.key.toString(): _clone(entry.value),
      };
      for (final entry in patch.entries) {
        final key = entry.key.toString();
        result[key] = _mergeValue(result[key], entry.value);
      }
      return result;
    }
    return _clone(patch);
  }

  static List<dynamic> _mergeItems(
    dynamic defaultsRaw,
    dynamic overrideRaw,
    List<String> warnings,
  ) {
    if (defaultsRaw is! List) {
      throw const FormatException('menu.defaults.json items: 배열 필요');
    }
    if (overrideRaw == null) return _clone(defaultsRaw) as List<dynamic>;
    if (overrideRaw is! Map) {
      throw const FormatException('menu.override.json items: 객체 필요');
    }

    final overrides = overrideRaw['overrides'];
    final additions = overrideRaw['additions'];
    final disabledIds = overrideRaw['disabledIds'];
    final order = overrideRaw['order'];
    if (overrides != null && overrides is! Map) {
      throw const FormatException('menu.override items.overrides: 객체 필요');
    }
    if (additions != null && additions is! List) {
      throw const FormatException('menu.override items.additions: 배열 필요');
    }
    if (disabledIds != null && disabledIds is! List) {
      throw const FormatException('menu.override items.disabledIds: 배열 필요');
    }
    if (order != null && order is! List) {
      throw const FormatException('menu.override items.order: 배열 필요');
    }

    final disabled =
        (disabledIds as List? ?? const []).whereType<String>().toSet();
    final result = <Map<String, dynamic>>[];
    final knownIds = <String>{};
    for (final raw in defaultsRaw) {
      if (raw is! Map) throw const FormatException('기본 메뉴 항목: 객체 필요');
      final item = _cloneMap(Map<String, dynamic>.from(raw));
      final id = item['id'];
      if (id is! String || !knownIds.add(id)) {
        throw FormatException('기본 메뉴 id 누락 또는 중복: $id');
      }
      if (disabled.contains(id)) continue;
      final patch = overrides is Map ? overrides[id] : null;
      final merged = _mergeValue(item, patch) as Map<String, dynamic>;
      if (patch is Map) {
        final patchedUrl = patch['url'];
        final patchedFile = patch['file'];
        if (patchedFile is String && patchedFile.trim().isNotEmpty) {
          merged.remove('url');
        } else if (patchedUrl is String && patchedUrl.trim().isNotEmpty) {
          merged.remove('file');
        }
      }
      result.add(merged);
    }

    if (overrides is Map) {
      for (final id in overrides.keys.whereType<String>()) {
        if (!knownIds.contains(id)) warnings.add('제거된 기본 메뉴의 오버라이드: $id');
      }
    }
    for (final raw in additions as List? ?? const []) {
      if (raw is! Map) throw const FormatException('추가 메뉴 항목: 객체 필요');
      final item = _cloneMap(Map<String, dynamic>.from(raw));
      final id = item['id'];
      if (id is! String || id.isEmpty || knownIds.contains(id)) {
        throw FormatException('추가 메뉴 id 누락 또는 중복: $id');
      }
      knownIds.add(id);
      result.add(item);
    }

    final orderedIds =
        (order as List? ?? const []).whereType<String>().toList();
    if (orderedIds.isEmpty) return result;
    final byId = {for (final item in result) item['id'] as String: item};
    final ordered = <Map<String, dynamic>>[];
    final used = <String>{};
    for (final id in orderedIds) {
      final item = byId[id];
      if (item != null && used.add(id)) ordered.add(item);
    }
    ordered.addAll(result.where((item) => used.add(item['id'] as String)));
    return ordered;
  }

  static Map<String, dynamic> _cloneMap(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

  static dynamic _clone(dynamic value) => jsonDecode(jsonEncode(value));

  static Object? _difference(dynamic base, dynamic effective) {
    if (_deepEquals(base, effective)) return _noDifference;
    if (base is Map && effective is Map) {
      final result = <String, dynamic>{};
      for (final entry in effective.entries) {
        final key = entry.key.toString();
        if (key == 'schemaVersion') continue;
        if (!base.containsKey(key)) {
          result[key] = _clone(entry.value);
          continue;
        }
        final difference = _difference(base[key], entry.value);
        if (!identical(difference, _noDifference)) {
          result[key] = _clone(difference);
        }
      }
      return result.isEmpty ? _noDifference : result;
    }
    return _clone(effective);
  }

  static bool _deepEquals(dynamic left, dynamic right) {
    if (identical(left, right) || left == right) return true;
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var i = 0; i < left.length; i++) {
        if (!_deepEquals(left[i], right[i])) return false;
      }
      return true;
    }
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key) ||
            !_deepEquals(entry.value, right[entry.key])) {
          return false;
        }
      }
      return true;
    }
    return false;
  }
}
