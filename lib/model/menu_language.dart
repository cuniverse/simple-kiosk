import 'menu_item.dart';

/// 사용자가 선택할 수 있는 언어와 해당 언어 전용 메뉴 목록.
class MenuLanguage {
  final String id;
  final String label;
  final String? subtitle;
  final String? icon;
  final List<MenuItem> items;

  const MenuLanguage({
    required this.id,
    required this.label,
    required this.items,
    this.subtitle,
    this.icon,
  });

  factory MenuLanguage.fromJson(Map<String, dynamic> json, int index) {
    final id = json['id'];
    final label = json['label'];
    final subtitle = json['subtitle'];
    final icon = json['icon'];
    final rawItems = json['items'];
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
    if (rawItems is! List || rawItems.isEmpty) {
      throw FormatException('menu.json languages[$index].items: 한 개 이상 필요');
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

    return MenuLanguage(
      id: id.trim(),
      label: label.trim(),
      subtitle: subtitle is String && subtitle.trim().isNotEmpty
          ? subtitle.trim()
          : null,
      icon: icon is String && icon.trim().isNotEmpty ? icon.trim() : null,
      items: List.unmodifiable(items),
    );
  }
}
