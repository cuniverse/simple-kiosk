import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../model/layout_config.dart';
import '../model/menu_config.dart';
import '../model/menu_item.dart';

/// `assets/config/menu.json`에서 메뉴 설정을 읽어오는 로더.
///
/// 두 가지 최상위 JSON 구조를 모두 지원한다.
///
/// - 객체: `{ "layout": {...}, "items": [...] }`
/// - 배열: `[ ... ]`  (구버전, layout은 기본값)
class MenuConfigLoader {
  /// 기본 에셋 경로.
  static const String defaultAssetPath = 'assets/config/menu.json';

  final String assetPath;

  const MenuConfigLoader({this.assetPath = defaultAssetPath});

  /// 에셋에서 메뉴 설정을 로드한다.
  ///
  /// 파싱 실패 시 [FormatException]을 던진다.
  Future<MenuConfig> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = json.decode(raw);

    final List rawItems;
    final LayoutConfig layout;

    if (decoded is List) {
      // 구버전: 배열 = items만 정의된 형식.
      rawItems = decoded;
      layout = LayoutConfig.defaults;
    } else if (decoded is Map<String, dynamic>) {
      final itemsValue = decoded['items'];
      if (itemsValue is! List) {
        throw const FormatException(
          'menu.json: "items"는 배열이어야 함',
        );
      }
      rawItems = itemsValue;

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
    } else {
      throw const FormatException(
        'menu.json: 최상위 구조는 객체 또는 배열이어야 함',
      );
    }

    final items = <MenuItem>[];
    for (var i = 0; i < rawItems.length; i++) {
      final entry = rawItems[i];
      if (entry is! Map<String, dynamic>) {
        throw FormatException('menu.json items[$i]: 객체 형식이 아님');
      }
      items.add(MenuItem.fromJson(entry));
    }

    if (items.isEmpty) {
      throw const FormatException('menu.json: 메뉴가 비어있음');
    }
    return MenuConfig(layout: layout, items: items);
  }
}
