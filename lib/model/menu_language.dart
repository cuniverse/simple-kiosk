import 'menu_item.dart';
import 'menu_topic.dart';

/// 사용자가 선택할 수 있는 언어와 해당 언어 전용 주제 목록.
class MenuLanguage {
  final String id;
  final String label;
  final bool hidden;
  final String? subtitle;
  final String? icon;
  final List<MenuItem> _legacyItems;
  final List<MenuTopic> topics;
  final String? _defaultMenuId;
  final String? _defaultTopicId;

  /// `languages[].items` 구형 설정은 내부적으로 단일 기본 주제로 취급한다.
  List<MenuTopic> get effectiveTopics => topics.isNotEmpty
      ? topics
      : [
          MenuTopic(
            id: 'default',
            label: label,
            items: _legacyItems,
            defaultMenuId: _defaultMenuId,
          ),
        ];

  String get defaultTopicId => _defaultTopicId ?? effectiveTopics.first.id;

  MenuTopic topic(String id) =>
      effectiveTopics.firstWhere((topic) => topic.id == id);

  MenuTopic get defaultTopic => topic(defaultTopicId);

  /// 기존 단일 주제 소비 코드와의 호환용 기본 주제 메뉴.
  List<MenuItem> get items => defaultTopic.items;

  String get defaultMenuId => defaultTopic.defaultMenuId;

  MenuItem get defaultItem => defaultTopic.defaultItem;

  const MenuLanguage({
    required this.id,
    required this.label,
    required List<MenuItem> items,
    this.hidden = false,
    this.topics = const [],
    String? defaultMenuId,
    String? defaultTopicId,
    this.subtitle,
    this.icon,
  })  : _legacyItems = items,
        _defaultMenuId = defaultMenuId,
        _defaultTopicId = defaultTopicId;

  factory MenuLanguage.fromJson(Map<String, dynamic> json, int index) {
    final id = json['id'];
    final label = json['label'];
    final subtitle = json['subtitle'];
    final icon = json['icon'];
    final rawItems = json['items'];
    final rawTopics = json['topics'];
    final defaultMenu = json['defaultMenu'];
    final defaultTopic = json['defaultTopic'];
    final hidden = json['hidden'];
    if (id is! String || id.trim().isEmpty) {
      throw FormatException('menu.json languages[$index].id: 비어있지 않은 문자열 필요');
    }
    if (label is! String || label.trim().isEmpty) {
      throw FormatException(
        'menu.json languages[$index].label: 비어있지 않은 문자열 필요',
      );
    }
    if (subtitle != null && subtitle is! String) {
      throw FormatException('menu.json languages[$index].subtitle: 문자열 필요');
    }
    if (icon != null && icon is! String) {
      throw FormatException('menu.json languages[$index].icon: 문자열 필요');
    }
    if (hidden != null && hidden is! bool) {
      throw FormatException('menu.json languages[$index].hidden: bool 필요');
    }
    final isHidden = hidden as bool? ?? false;
    if (rawTopics == null && (rawItems is! List || rawItems.isEmpty)) {
      throw FormatException(
        'menu.json languages[$index]: topics 또는 items 한 개 이상 필요',
      );
    }
    if (defaultMenu != null &&
        (defaultMenu is! String || defaultMenu.trim().isEmpty)) {
      throw FormatException(
        'menu.json languages[$index].defaultMenu: 비어있지 않은 문자열 필요',
      );
    }
    if (defaultTopic != null &&
        (defaultTopic is! String || defaultTopic.trim().isEmpty)) {
      throw FormatException(
        'menu.json languages[$index].defaultTopic: 비어있지 않은 문자열 필요',
      );
    }

    if (rawTopics != null) {
      if (rawTopics is! List || rawTopics.isEmpty) {
        throw FormatException(
          'menu.json languages[$index].topics: 한 개 이상 필요',
        );
      }
      final topics = <MenuTopic>[];
      final topicIds = <String>{};
      for (var topicIndex = 0; topicIndex < rawTopics.length; topicIndex++) {
        final raw = rawTopics[topicIndex];
        if (raw is! Map<String, dynamic>) {
          throw FormatException(
            'menu.json languages[$index].topics[$topicIndex]: 객체 필요',
          );
        }
        final topic = MenuTopic.fromJson(raw, index, topicIndex);
        if (!topicIds.add(topic.id)) {
          throw FormatException(
            'menu.json languages[$index].topics: 주제 id 중복 (${topic.id})',
          );
        }
        if (!topic.hidden) topics.add(topic);
      }
      final requestedDefaultTopic =
          defaultTopic is String ? defaultTopic.trim() : null;
      if (requestedDefaultTopic != null &&
          !topicIds.contains(requestedDefaultTopic)) {
        throw FormatException(
          'menu.json languages[$index].defaultTopic: 등록되지 않은 주제 ($requestedDefaultTopic)',
        );
      }
      if (!isHidden && topics.isEmpty) {
        throw FormatException(
          'menu.json languages[$index].topics: 표시할 주제가 한 개 이상 필요',
        );
      }
      if (!isHidden) {
        final emptyTopic = topics.where((topic) => topic.items.isEmpty);
        if (emptyTopic.isNotEmpty) {
          throw FormatException(
            'menu.json languages[$index].topics(${emptyTopic.first.id}).items: '
            '표시할 메뉴가 한 개 이상 필요',
          );
        }
      }
      final defaultTopicId = topics.isEmpty
          ? null
          : topics.any((topic) => topic.id == requestedDefaultTopic)
              ? requestedDefaultTopic
              : topics.first.id;
      final selectedTopic = defaultTopicId == null
          ? null
          : topics.firstWhere((topic) => topic.id == defaultTopicId);
      return MenuLanguage(
        id: id.trim(),
        label: label.trim(),
        hidden: isHidden,
        subtitle: subtitle is String && subtitle.trim().isNotEmpty
            ? subtitle.trim()
            : null,
        icon: icon is String && icon.trim().isNotEmpty ? icon.trim() : null,
        items: selectedTopic?.items ?? const [],
        topics: List.unmodifiable(topics),
        defaultMenuId: selectedTopic?.defaultMenuId,
        defaultTopicId: defaultTopicId,
      );
    }

    final items = <MenuItem>[];
    final itemIds = <String>{};
    for (var itemIndex = 0; itemIndex < rawItems.length; itemIndex++) {
      final raw = rawItems[itemIndex];
      if (raw is! Map<String, dynamic>) {
        throw FormatException(
          'menu.json languages[$index].items[$itemIndex]: 객체 필요',
        );
      }
      final item = MenuItem.fromJson(raw);
      if (!itemIds.add(item.id)) {
        throw FormatException(
          'menu.json languages[$index].items: 메뉴 id 중복 (${item.id})',
        );
      }
      if (!item.hidden) items.add(item);
    }

    final requestedDefaultMenu =
        defaultMenu is String ? defaultMenu.trim() : null;
    if (requestedDefaultMenu != null &&
        !itemIds.contains(requestedDefaultMenu)) {
      throw FormatException(
        'menu.json languages[$index].defaultMenu: 등록되지 않은 메뉴 ($requestedDefaultMenu)',
      );
    }
    if (!isHidden && items.isEmpty) {
      throw FormatException(
        'menu.json languages[$index].items: 표시할 메뉴가 한 개 이상 필요',
      );
    }
    final defaultMenuId = items.isEmpty
        ? null
        : items.any((item) => item.id == requestedDefaultMenu)
            ? requestedDefaultMenu
            : items.first.id;

    return MenuLanguage(
      id: id.trim(),
      label: label.trim(),
      hidden: isHidden,
      subtitle: subtitle is String && subtitle.trim().isNotEmpty
          ? subtitle.trim()
          : null,
      icon: icon is String && icon.trim().isNotEmpty ? icon.trim() : null,
      items: List.unmodifiable(items),
      defaultMenuId: defaultMenuId,
    );
  }
}
