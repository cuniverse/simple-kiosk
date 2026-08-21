import 'menu_item.dart';
import 'menu_topic.dart';

/// 사용자가 선택할 수 있는 언어와 해당 언어 전용 주제 목록.
class MenuLanguage {
  final String id;
  final String label;
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
        topics.add(topic);
      }
      final defaultTopicId =
          defaultTopic is String ? defaultTopic.trim() : topics.first.id;
      if (!topicIds.contains(defaultTopicId)) {
        throw FormatException(
          'menu.json languages[$index].defaultTopic: 등록되지 않은 주제 ($defaultTopicId)',
        );
      }
      final selectedTopic =
          topics.firstWhere((topic) => topic.id == defaultTopicId);
      return MenuLanguage(
        id: id.trim(),
        label: label.trim(),
        subtitle: subtitle is String && subtitle.trim().isNotEmpty
            ? subtitle.trim()
            : null,
        icon: icon is String && icon.trim().isNotEmpty ? icon.trim() : null,
        items: selectedTopic.items,
        topics: List.unmodifiable(topics),
        defaultMenuId: selectedTopic.defaultMenuId,
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
      items.add(item);
    }

    final defaultMenuId =
        defaultMenu is String ? defaultMenu.trim() : items.first.id;
    if (!itemIds.contains(defaultMenuId)) {
      throw FormatException(
        'menu.json languages[$index].defaultMenu: 등록되지 않은 메뉴 ($defaultMenuId)',
      );
    }

    return MenuLanguage(
      id: id.trim(),
      label: label.trim(),
      subtitle: subtitle is String && subtitle.trim().isNotEmpty
          ? subtitle.trim()
          : null,
      icon: icon is String && icon.trim().isNotEmpty ? icon.trim() : null,
      items: List.unmodifiable(items),
      defaultMenuId: defaultMenuId,
    );
  }
}
