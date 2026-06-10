/// 메뉴 항목 모델.
///
/// `assets/config/menu.json`에 정의된 단일 항목을 표현한다.
/// JSON 구조 예:
/// ```json
/// { "id": "home", "title": "홈", "url": "https://example.com" }
/// ```
class MenuItem {
  /// 메뉴 식별자(중복 불가 권장).
  final String id;

  /// 네비게이션 버튼에 표시될 텍스트.
  final String title;

  /// 버튼을 눌렀을 때 WebView에 로드할 URL.
  /// 운영에서는 HTTPS 사용을 권장한다.
  final String url;

  const MenuItem({
    required this.id,
    required this.title,
    required this.url,
  });

  /// JSON 한 항목을 모델로 변환한다.
  ///
  /// 필수 필드(id/title/url)가 비어있으면 [FormatException]을 던진다.
  factory MenuItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final url = json['url'];

    if (id is! String || id.isEmpty) {
      throw const FormatException('menu item: "id" 누락 또는 형식 오류');
    }
    if (title is! String || title.isEmpty) {
      throw const FormatException('menu item: "title" 누락 또는 형식 오류');
    }
    if (url is! String || url.isEmpty) {
      throw const FormatException('menu item: "url" 누락 또는 형식 오류');
    }

    return MenuItem(id: id, title: title, url: url);
  }
}
