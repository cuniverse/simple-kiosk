import 'menu_item.dart';

/// 한 언어에서 선택할 수 있는 주제와 해당 주제 전용 메뉴 목록.
class MenuTopic {
  final String id;
  final String label;
  final bool hidden;
  final String? subtitle;
  final String? icon;
  final List<MenuItem> items;
  final String? _defaultMenuId;

  String get defaultMenuId => _defaultMenuId ?? items.first.id;

  MenuItem get defaultItem =>
      items.firstWhere((item) => item.id == defaultMenuId);

  const MenuTopic({
    required this.id,
    required this.label,
    required this.items,
    this.hidden = false,
    String? defaultMenuId,
    this.subtitle,
    this.icon,
  }) : _defaultMenuId = defaultMenuId;

  factory MenuTopic.fromJson(
    Map<String, dynamic> json,
    int languageIndex,
    int topicIndex,
  ) {
    final path = 'menu.json languages[$languageIndex].topics[$topicIndex]';
    final id = json['id'];
    final label = json['label'];
    final subtitle = json['subtitle'];
    final icon = json['icon'];
    final rawItems = json['items'];
    final defaultMenu = json['defaultMenu'];
    final hidden = json['hidden'];
    if (id is! String || id.trim().isEmpty) {
      throw FormatException('$path.id: 비어있지 않은 문자열 필요');
    }
    if (label is! String || label.trim().isEmpty) {
      throw FormatException('$path.label: 비어있지 않은 문자열 필요');
    }
    if (subtitle != null && subtitle is! String) {
      throw FormatException('$path.subtitle: 문자열 필요');
    }
    if (icon != null && icon is! String) {
      throw FormatException('$path.icon: 문자열 필요');
    }
    if (hidden != null && hidden is! bool) {
      throw FormatException('$path.hidden: bool 필요');
    }
    if (rawItems is! List || rawItems.isEmpty) {
      throw FormatException('$path.items: 한 개 이상 필요');
    }
    if (defaultMenu != null &&
        (defaultMenu is! String || defaultMenu.trim().isEmpty)) {
      throw FormatException('$path.defaultMenu: 비어있지 않은 문자열 필요');
    }

    final items = <MenuItem>[];
    final itemIds = <String>{};
    for (var itemIndex = 0; itemIndex < rawItems.length; itemIndex++) {
      final raw = rawItems[itemIndex];
      if (raw is! Map<String, dynamic>) {
        throw FormatException('$path.items[$itemIndex]: 객체 필요');
      }
      final item = MenuItem.fromJson(raw);
      if (!itemIds.add(item.id)) {
        throw FormatException('$path.items: 메뉴 id 중복 (${item.id})');
      }
      if (!item.hidden) items.add(item);
    }

    final requestedDefaultMenu =
        defaultMenu is String ? defaultMenu.trim() : null;
    if (requestedDefaultMenu != null &&
        !itemIds.contains(requestedDefaultMenu)) {
      throw FormatException(
        '$path.defaultMenu: 등록되지 않은 메뉴 ($requestedDefaultMenu)',
      );
    }
    final isHidden = hidden as bool? ?? false;
    final defaultMenuId = items.isEmpty
        ? null
        : items.any((item) => item.id == requestedDefaultMenu)
            ? requestedDefaultMenu
            : items.first.id;
    return MenuTopic(
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
