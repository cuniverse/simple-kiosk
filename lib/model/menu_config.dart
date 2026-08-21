import 'menu_item.dart';
import 'menu_language.dart';
import 'layout_config.dart';
import 'idle_config.dart';
import 'webview_data_policy.dart';

/// `menu.json` 전체를 표현하는 설정.
///
/// 두 가지 JSON 구조를 지원한다.
///
/// 1. 객체 형식 (권장):
/// ```json
/// {
///   "layout": { "navPosition": "left", "sideWidth": 240 },
///   "idle":   { "enabled": true, "mode": "slideshow", ... },
///   "items":  [ { "id": "home", ... } ]
/// }
/// ```
///
/// 2. 배열 형식 (구버전, 하위 호환):
/// ```json
/// [ { "id": "home", ... } ]
/// ```
/// 이 경우 [layout], [idle] 모두 기본값이 된다.
class MenuConfig {
  final LayoutConfig layout;
  final IdleConfig idle;
  final List<MenuLanguage> languages;
  final String defaultLanguageId;
  final String languageSelectionTitle;
  final String languageSelectionSubtitle;
  final String topicSelectionTitle;
  final String topicSelectionSubtitle;
  final bool skipSingleTopic;
  final WebViewDataPolicy webViewDataPolicy;

  /// 기존 단일 메뉴 소비 코드와 설정을 위한 기본 언어 메뉴.
  List<MenuItem> get items => language(defaultLanguageId).items;

  MenuLanguage language(String id) =>
      languages.firstWhere((language) => language.id == id);

  const MenuConfig({
    required this.layout,
    required this.idle,
    required this.languages,
    required this.defaultLanguageId,
    this.languageSelectionTitle = '언어를 선택하세요',
    this.languageSelectionSubtitle = 'Please select your language',
    this.topicSelectionTitle = '주제를 선택하세요',
    this.topicSelectionSubtitle = 'Please select a topic',
    this.skipSingleTopic = true,
    this.webViewDataPolicy = WebViewDataPolicy.defaults,
  });
}
