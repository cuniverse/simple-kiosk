import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../model/menu_item.dart';

/// `assets/config/menu.json`에서 메뉴 설정을 읽어오는 로더.
///
/// JSON 파일은 [MenuItem] 객체 배열이어야 한다.
class MenuConfigLoader {
  /// 기본 에셋 경로.
  static const String defaultAssetPath = 'assets/config/menu.json';

  final String assetPath;

  const MenuConfigLoader({this.assetPath = defaultAssetPath});

  /// 에셋에서 메뉴 목록을 로드한다.
  ///
  /// 파싱 실패 시 [FormatException]을 던진다.
  Future<List<MenuItem>> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = json.decode(raw);

    if (decoded is! List) {
      throw const FormatException('menu.json: 최상위 구조는 배열이어야 함');
    }

    final items = <MenuItem>[];
    for (var i = 0; i < decoded.length; i++) {
      final entry = decoded[i];
      if (entry is! Map<String, dynamic>) {
        throw FormatException('menu.json[$i]: 객체 형식이 아님');
      }
      items.add(MenuItem.fromJson(entry));
    }

    if (items.isEmpty) {
      throw const FormatException('menu.json: 메뉴가 비어있음');
    }
    return items;
  }
}
