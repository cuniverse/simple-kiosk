import 'menu_item.dart';

/// 사용자가 선택할 수 있는 언어와 해당 언어 전용 메뉴 목록.
class MenuLanguage {
  final String id;
  final String label;
  final String? subtitle;
  final String? icon;
  final List<MenuItem> items;
  final String? _defaultMenuId;

  String get defaultMenuId => _defaultMenuId ?? items.first.id;

  MenuItem get defaultItem =>
      items.firstWhere((item) => item.id == defaultMenuId);

  const MenuLanguage({
    required this.id,
    required this.label,
    required this.items,
    String? defaultMenuId,
    this.subtitle,
    this.icon,
  }) : _defaultMenuId = defaultMenuId;

  factory MenuLanguage.fromJson(Map<String, dynamic> json, int index) {
    final id = json['id'];
    final label = json['label'];
    final subtitle = json['subtitle'];
    final icon = json['icon'];
    final rawItems = json['items'];
    final defaultMenu = json['defaultMenu'];
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
    if (defaultMenu != null &&
        (defaultMenu is! String || defaultMenu.trim().isEmpty)) {
      throw FormatException(
        'menu.json languages[$index].defaultMenu: 비어있지 않은 문자열 필요',
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
