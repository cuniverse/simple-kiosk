import 'menu_item.dart';
import 'layout_config.dart';

/// `menu.json` 전체를 표현하는 설정.
///
/// 두 가지 JSON 구조를 지원한다.
///
/// 1. 객체 형식 (권장):
/// ```json
/// {
///   "layout": { "navPosition": "left", "sideWidth": 240 },
///   "items": [ { "id": "home", ... } ]
/// }
/// ```
///
/// 2. 배열 형식 (구버전, 하위 호환):
/// ```json
/// [ { "id": "home", ... } ]
/// ```
/// 이 경우 [layout]은 모두 기본값([LayoutConfig.defaults])이 된다.
class MenuConfig {
  final LayoutConfig layout;
  final List<MenuItem> items;

  const MenuConfig({required this.layout, required this.items});
}
