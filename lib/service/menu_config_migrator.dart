import 'dart:convert';

import 'menu_config_merger.dart';

/// 구형 운영 메뉴 설정을 현재 언어 → 주제 → 메뉴 구조로 변환한다.
class MenuConfigMigrator {
  const MenuConfigMigrator._();

  static bool needsMigration(
    Map<String, dynamic> defaults,
    Map<String, dynamic> override,
  ) {
    if (override.isEmpty) return false;
    final schema = override['schemaVersion'];
    if (schema == null || (schema is num && schema.toInt() < 2)) return true;
    if (override.containsKey('items')) return true;
    final languages = override['languages'];
    if (languages is List &&
        languages.any(
          (language) =>
              language is Map &&
              language.containsKey('items') &&
              !language.containsKey('topics'),
        )) {
      return true;
    }
    return _hasSyntheticLegacyTopics(defaults, override);
  }

  /// [override]의 의미를 보존하면서 schemaVersion 2 구조로 변환한다.
  ///
  /// schemaVersion 1의 `items` 패치 객체는 기본 설정과 먼저 병합해야 완전한 메뉴
  /// 목록이 되므로 이 경우에만 유효 설정 전체를 현재 구조로 저장한다.
  static Map<String, dynamic> migrate(
    Map<String, dynamic> defaults,
    Map<String, dynamic> override,
  ) {
    if (_hasSyntheticLegacyTopics(defaults, override)) {
      return _migrateSyntheticLegacyTopics(defaults, override);
    }
    final source = override['items'] is Map
        ? MenuConfigMerger.merge(defaults, override).json
        : _cloneMap(override);
    final result = _normalizeLegacyShape(source);
    result['schemaVersion'] = MenuConfigMerger.currentSchemaVersion;
    return result;
  }

  static bool _hasSyntheticLegacyTopics(
    Map<String, dynamic> defaults,
    Map<String, dynamic> override,
  ) {
    final defaultLanguages = defaults['languages'];
    final overrideLanguages = override['languages'];
    if (defaultLanguages is! List || overrideLanguages is! List) return false;
    final defaultsById = <String, Map>{
      for (final language in defaultLanguages.whereType<Map>())
        if (language['id'] is String) language['id'] as String: language,
    };
    for (final language in overrideLanguages.whereType<Map>()) {
      final topics = language['topics'];
      if (topics is! List || topics.length != 1 || topics.first is! Map) {
        continue;
      }
      final topic = topics.first as Map;
      if (topic['id'] != 'default') continue;
      final defaultLanguage = defaultsById[language['id']];
      final defaultTopics = defaultLanguage?['topics'];
      if (defaultTopics is List &&
          defaultTopics.isNotEmpty &&
          !defaultTopics.any(
            (candidate) => candidate is Map && candidate['id'] == 'default',
          )) {
        return true;
      }
    }
    return false;
  }

  static Map<String, dynamic> _migrateSyntheticLegacyTopics(
    Map<String, dynamic> defaults,
    Map<String, dynamic> override,
  ) {
    final result = _cloneMap(defaults);
    for (final entry in override.entries) {
      if (entry.key == 'schemaVersion' || entry.key == 'languages') continue;
      result[entry.key] = _clone(entry.value);
    }

    final defaultLanguages = (defaults['languages'] as List)
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList();
    final defaultsById = <String, Map<String, dynamic>>{
      for (final language in defaultLanguages)
        if (language['id'] is String) language['id'] as String: language,
    };
    final migratedLanguages = <dynamic>[];
    final usedIds = <String>{};
    for (final raw in (override['languages'] as List)) {
      if (raw is! Map) continue;
      final oldLanguage = Map<String, dynamic>.from(raw);
      final id = oldLanguage['id'];
      if (id is String) usedIds.add(id);
      final base = id is String ? defaultsById[id] : null;
      final topics = oldLanguage['topics'];
      final synthetic = base != null &&
          topics is List &&
          topics.length == 1 &&
          topics.first is Map &&
          (topics.first as Map)['id'] == 'default';
      if (!synthetic) {
        migratedLanguages.add(_clone(oldLanguage));
        continue;
      }

      final migrated = _cloneMap(base);
      for (final entry in oldLanguage.entries) {
        if (entry.key == 'topics' || entry.key == 'defaultTopic') continue;
        migrated[entry.key] = _clone(entry.value);
      }
      final legacyTopic = Map<String, dynamic>.from(topics.first as Map);
      final legacyItems = legacyTopic['items'];
      final legacyById = <String, Map>{
        if (legacyItems is List)
          for (final item in legacyItems.whereType<Map>())
            if (item['id'] is String) item['id'] as String: item,
      };
      final migratedTopics = migrated['topics'];
      if (migratedTopics is List) {
        for (final topic in migratedTopics.whereType<Map>()) {
          final items = topic['items'];
          if (items is! List) continue;
          for (var index = 0; index < items.length; index++) {
            final item = items[index];
            if (item is! Map || item['id'] is! String) continue;
            final legacy = legacyById[item['id']];
            if (legacy == null) continue;
            items[index] = <String, dynamic>{
              ...Map<String, dynamic>.from(item),
              ...Map<String, dynamic>.from(_clone(legacy) as Map),
            };
          }
        }
        final oldDefaultMenu = legacyTopic['defaultMenu'];
        if (oldDefaultMenu is String) {
          for (final topic in migratedTopics.whereType<Map>()) {
            final items = topic['items'];
            if (items is List &&
                items.whereType<Map>().any(
                      (item) => item['id'] == oldDefaultMenu,
                    )) {
              migrated['defaultTopic'] = topic['id'];
              break;
            }
          }
        }
      }
      migratedLanguages.add(migrated);
    }
    for (final language in defaultLanguages) {
      if (language['id'] is String && usedIds.add(language['id'] as String)) {
        migratedLanguages.add(_clone(language));
      }
    }
    result['languages'] = migratedLanguages;
    result['schemaVersion'] = MenuConfigMerger.currentSchemaVersion;
    return result;
  }

  static Map<String, dynamic> _normalizeLegacyShape(
    Map<String, dynamic> source,
  ) {
    final result = _cloneMap(source);
    final topLevelItems = result['items'];
    if (topLevelItems is List) {
      result.remove('items');
      result['defaultLanguage'] = 'default';
      result['languages'] = [
        {
          'id': 'default',
          'label': '시작',
          'defaultTopic': 'default',
          'topics': [
            _legacyTopic(
              label: '기본 주제',
              items: topLevelItems,
            ),
          ],
        },
      ];
      return result;
    }

    final languages = result['languages'];
    if (languages is! List) return result;
    for (final language in languages) {
      if (language is! Map<String, dynamic> ||
          language.containsKey('topics') ||
          language['items'] is! List) {
        continue;
      }
      final items = language.remove('items') as List;
      final defaultMenu = language.remove('defaultMenu');
      language['defaultTopic'] = 'default';
      language['topics'] = [
        _legacyTopic(
          label: (language['label'] as String?) ?? '기본 주제',
          items: items,
          defaultMenu: defaultMenu,
        ),
      ];
    }
    return result;
  }

  static Map<String, dynamic> _legacyTopic({
    required String label,
    required List<dynamic> items,
    Object? defaultMenu,
  }) {
    final topic = <String, dynamic>{
      'id': 'default',
      'label': label,
      'items': items,
    };
    if (defaultMenu is String && defaultMenu.trim().isNotEmpty) {
      topic['defaultMenu'] = defaultMenu.trim();
    }
    return topic;
  }

  static Map<String, dynamic> _cloneMap(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

  static dynamic _clone(dynamic value) => jsonDecode(jsonEncode(value));
}
