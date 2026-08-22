/// 메뉴 항목 모델.
///
/// `assets/config/menu.json`에 정의된 단일 항목을 표현한다.
/// JSON 구조 예:
/// ```json
/// {
///   "id": "home",
///   "title": "홈",
///   "url": "https://example.com",
///   "icon": "assets/icons/home.png",
///   "showTitle": false
/// }
/// ```
class MenuItem {
  /// 이 툴바 항목에만 적용할 글꼴. 비어 있으면 툴바 전체 설정을 상속한다.
  final String? fontFamily;

  /// `true`이면 이 항목을 툴바에서 숨긴다. 기본값은 `false`.
  final bool hidden;

  /// 메뉴 식별자(중복 불가 권장).
  final String id;

  /// 네비게이션 버튼에 표시될 텍스트.
  ///
  /// [showTitle]이 `false`이면 화면에는 표시되지 않지만,
  /// 접근성(스크린리더, 툴팁 등) 용도로는 계속 사용된다.
  final String title;

  /// 버튼을 눌렀을 때 WebView에 로드할 URL.
  /// 운영에서는 HTTPS 사용을 권장한다.
  final String url;

  /// 버튼에 표시할 아이콘 경로(선택).
  ///
  /// - `assets/...` 로 시작하면 Flutter 에셋으로 로드한다.
  /// - `http(s)://` 로 시작하면 네트워크 이미지로 로드한다.
  /// - 값이 없거나 비어있으면 텍스트만 표시한다.
  final String? icon;

  /// 버튼에 [title] 텍스트를 표시할지 여부. 기본값은 `true`.
  ///
  /// `false`로 두면 아이콘만 표시한다. 단, 아이콘이 없으면
  /// 이 값과 상관없이 텍스트가 표시된다(빈 버튼 방지).
  final bool showTitle;

  /// 이 항목을 단일 클릭했을 때 현재 페이지 상태(스크롤/내부 네비)를 유지할지
  /// 여부. `null` 이면 [LayoutConfig.keepStateOnTap] 의 값을 사용한다.
  ///
  /// `true` 이면 같은 메뉴를 단일 클릭해도 아무 동작 없이 상태를 유지하고,
  /// 더블 탭(300ms 이내) 시에만 설정된 URL 로 강제 재로드한다.
  final bool? keepStateOnTap;

  const MenuItem({
    required this.id,
    required this.title,
    required this.url,
    this.hidden = false,
    this.fontFamily,
    this.icon,
    this.showTitle = true,
    this.keepStateOnTap,
  });

  /// JSON 한 항목을 모델로 변환한다.
  ///
  /// 필수 필드(id/title/url)가 비어있으면 [FormatException]을 던진다.
  /// `icon`/`showTitle`은 선택 필드이며, 누락되면 기본값을 사용한다.
  factory MenuItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final url = json['url'];
    final icon = json['icon'];
    final showTitle = json['showTitle'];
    final keepState = json['keepStateOnTap'];
    final hidden = json['hidden'];
    final fontFamily = json['fontFamily'];

    if (id is! String || id.isEmpty) {
      throw const FormatException('menu item: "id" 누락 또는 형식 오류');
    }
    if (title is! String || title.isEmpty) {
      throw const FormatException('menu item: "title" 누락 또는 형식 오류');
    }
    if (url is! String || url.isEmpty) {
      throw const FormatException('menu item: "url" 누락 또는 형식 오류');
    }
    if (hidden != null && hidden is! bool) {
      throw const FormatException('menu item: "hidden"은 bool 이어야 함');
    }
    if (fontFamily != null && fontFamily is! String) {
      throw const FormatException('menu item: "fontFamily"는 문자열이어야 함');
    }

    String? iconPath;
    if (icon is String && icon.isNotEmpty) {
      iconPath = icon;
    }

    bool? keepStateOnTap;
    if (keepState != null) {
      if (keepState is! bool) {
        throw const FormatException(
          'menu item: "keepStateOnTap" 은 bool 이어야 함',
        );
      }
      keepStateOnTap = keepState;
    }

    return MenuItem(
      id: id,
      title: title,
      url: url,
      hidden: hidden as bool? ?? false,
      fontFamily: fontFamily is String && fontFamily.trim().isNotEmpty
          ? fontFamily.trim()
          : null,
      icon: iconPath,
      showTitle: showTitle is bool ? showTitle : true,
      keepStateOnTap: keepStateOnTap,
    );
  }
}
