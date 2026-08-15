import 'dart:convert';

class MenuMergeResult {
  final Map<String, dynamic> json;
  final List<String> warnings;

  const MenuMergeResult(this.json, this.warnings);
}

/// 새 기본 설정과 운영자 오버라이드를 병합한다.
class MenuConfigMerger {
  static const int currentSchemaVersion = 2;

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
      return (languages.first as Map)['items'];
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
      result.add(_mergeValue(item, patch) as Map<String, dynamic>);
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
}
