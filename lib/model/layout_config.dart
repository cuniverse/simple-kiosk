/// 네비게이션 바 표시 위치.
///
/// - [auto]: 화면 폭이 [LayoutConfig.breakpoint] 이상이면 [left], 아니면 [bottom].
/// - [left] / [right]: 항상 좌/우측 세로 사이드.
/// - [top] / [bottom]: 항상 상/하단 가로 바.
enum NavPosition { auto, left, right, top, bottom }

/// 네비게이션 바 내부에서 버튼들을 배치할 정렬 방식.
///
/// - [start]: 시작(위/왼쪽)에 모음
/// - [center]: 가운데
/// - [end]: 끝(아래/오른쪽)
/// - [spaceBetween]: 양 끝에 붙이고 사이를 균등 분배
/// - [spaceAround]: 각 항목 좌우(혹은 상하)에 같은 여백
/// - [spaceEvenly]: 항목 사이 + 양 끝 모두 균등 분배
/// - [stretch]: 사용 가능한 공간을 항목들이 균등하게 나눠 가짐
///   (하단 바의 기본 동작. `buttonWidth`가 지정되지 않을 때만 의미가 있다.)
enum NavAlignment {
  start,
  center,
  end,
  spaceBetween,
  spaceAround,
  spaceEvenly,
  stretch,
}

NavPosition _parseNavPosition(Object? raw) {
  if (raw is! String) return NavPosition.auto;
  switch (raw.toLowerCase()) {
    case 'left':
      return NavPosition.left;
    case 'right':
      return NavPosition.right;
    case 'top':
      return NavPosition.top;
    case 'bottom':
      return NavPosition.bottom;
    case 'auto':
      return NavPosition.auto;
    default:
      throw FormatException('menu.json: 알 수 없는 navPosition 값 "$raw"');
  }
}

NavAlignment _parseAlignment(Object? raw, NavAlignment fallback) {
  if (raw == null) return fallback;
  if (raw is! String) {
    throw const FormatException('menu.json: buttonAlignment는 문자열이어야 함');
  }
  switch (raw.toLowerCase()) {
    case 'start':
      return NavAlignment.start;
    case 'center':
      return NavAlignment.center;
    case 'end':
      return NavAlignment.end;
    case 'spacebetween':
    case 'space-between':
      return NavAlignment.spaceBetween;
    case 'spacearound':
    case 'space-around':
      return NavAlignment.spaceAround;
    case 'spaceevenly':
    case 'space-evenly':
      return NavAlignment.spaceEvenly;
    case 'stretch':
      return NavAlignment.stretch;
    default:
      throw FormatException('menu.json: 알 수 없는 buttonAlignment 값 "$raw"');
  }
}

/// 네비게이션 바 레이아웃 설정.
///
/// `menu.json`의 선택적 `layout` 섹션에서 로드된다.
/// 값이 누락되면 모두 기본값을 사용한다.
class LayoutConfig {
  /// 네비게이션 바 위치.
  final NavPosition navPosition;

  /// 사이드 네비게이션(`left`/`right`)일 때의 폭(dp).
  final double sideWidth;

  /// 하단/상단 네비게이션(`top`/`bottom`)일 때의 높이(dp).
  final double barHeight;

  /// [NavPosition.auto] 모드에서 사이드/바를 가르는 화면 폭(dp).
  final double breakpoint;

  /// 각 버튼의 높이(dp). `0`이면 아이콘/텍스트 유무에 따라 자동 결정.
  ///
  /// - 사이드 모드: 각 버튼의 세로 크기.
  /// - 하단/상단 모드: 각 버튼의 세로 크기(바 높이 - 패딩 안에서 동작).
  final double buttonHeight;

  /// 하단/상단 모드에서 각 버튼의 가로 폭(dp). `0`이면 가용 공간을 균등 분배(stretch).
  ///
  /// 사이드 모드에서는 무시되며, `sideWidth`에서 안쪽 패딩을 뺀 값을 사용한다.
  final double buttonWidth;

  /// 버튼 간 간격(dp).
  final double buttonGap;

  /// 네비게이션 바 내부에서 버튼들을 배치할 방향의 정렬.
  ///
  /// - 사이드 모드: 세로 방향 정렬(위/가운데/아래 ...).
  /// - 하단/상단 모드: 가로 방향 정렬(왼쪽/가운데/오른쪽 ...).
  ///
  /// 기본값은 사이드는 `start`, 하단/상단은 `stretch`이지만, JSON에서 명시한 값이
  /// 우선한다. `stretch`는 하단/상단 모드에서만 의미가 있다.
  final NavAlignment buttonAlignment;

  /// 네비게이션 바 시작점(좌/상)에 WebView 뒤로/앞으로 컨트롤을 표시할지.
  final bool showHistoryButtons;

  const LayoutConfig({
    this.navPosition = NavPosition.auto,
    this.sideWidth = 220,
    this.barHeight = 96,
    this.breakpoint = 720,
    this.buttonHeight = 0,
    this.buttonWidth = 0,
    this.buttonGap = 8,
    this.buttonAlignment = NavAlignment.stretch,
    this.showHistoryButtons = false,
  });

  /// 모든 기본값을 가진 설정.
  static const LayoutConfig defaults = LayoutConfig();

  factory LayoutConfig.fromJson(Map<String, dynamic> json) {
    final navPosition = _parseNavPosition(json['navPosition']);

    double parsePositive(String key, double fallback) {
      final v = json[key];
      if (v == null) return fallback;
      if (v is num) {
        if (v <= 0) {
          throw FormatException('menu.json layout.$key: 0 이하 값 불가');
        }
        return v.toDouble();
      }
      throw FormatException('menu.json layout.$key: 숫자가 아님');
    }

    double parseNonNegative(String key, double fallback) {
      final v = json[key];
      if (v == null) return fallback;
      if (v is num) {
        if (v < 0) {
          throw FormatException('menu.json layout.$key: 음수 불가');
        }
        return v.toDouble();
      }
      throw FormatException('menu.json layout.$key: 숫자가 아님');
    }

    return LayoutConfig(
      navPosition: navPosition,
      sideWidth: parsePositive('sideWidth', defaults.sideWidth),
      barHeight: parsePositive('barHeight', defaults.barHeight),
      breakpoint: parsePositive('breakpoint', defaults.breakpoint),
      buttonHeight: parseNonNegative('buttonHeight', defaults.buttonHeight),
      buttonWidth: parseNonNegative('buttonWidth', defaults.buttonWidth),
      buttonGap: parseNonNegative('buttonGap', defaults.buttonGap),
      buttonAlignment:
          _parseAlignment(json['buttonAlignment'], defaults.buttonAlignment),
      showHistoryButtons: () {
        final v = json['showHistoryButtons'];
        if (v == null) return defaults.showHistoryButtons;
        if (v is bool) return v;
        throw const FormatException(
          'menu.json layout.showHistoryButtons: bool 필요',
        );
      }(),
    );
  }
}
