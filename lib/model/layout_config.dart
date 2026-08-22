import 'package:flutter/material.dart';

/// 네비게이션 바 표시 위치.
///
/// - [auto]: 화면 폭이 [LayoutConfig.breakpoint] 이상이면 [left], 아니면 [bottom].
/// - [left] / [right]: 항상 좌/우측 세로 사이드.
/// - [top] / [bottom]: 항상 상/하단 가로 바.
enum NavPosition { auto, left, right, top, bottom }

/// Windows에서 사용할 화면 키보드 종류.
enum KeyboardMode { windows, builtIn }

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

KeyboardMode _parseKeyboardMode(Object? raw) {
  if (raw == null) return KeyboardMode.windows;
  if (raw is! String) {
    throw const FormatException('menu.json layout.keyboardMode: 문자열 필요');
  }
  switch (raw.toLowerCase()) {
    case 'windows':
    case 'system':
      return KeyboardMode.windows;
    case 'builtin':
    case 'built-in':
      return KeyboardMode.builtIn;
    default:
      throw FormatException('menu.json: 알 수 없는 keyboardMode 값 "$raw"');
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

  /// 네비게이션 바 끝점(우/하)에 OS 가상 키보드 호출/닫기 토글 버튼을
  /// 표시할지 여부. 운영자가 수동으로 키보드를 띄울 수 있게 해준다.
  final bool showKeyboardToggle;

  /// 현재 선택한 주제 이름을 툴바 시작 위치에 작은 상태 라벨로 표시할지 여부.
  final bool showSelectedTopic;

  /// Windows 사이니지 표시 중 앱 전환·셸 단축키를 차단할지 여부.
  final bool windowsKioskLockdown;

  /// Windows 사이니지 창을 다른 일반 창보다 항상 위에 유지할지 여부.
  final bool windowsAlwaysOnTop;

  /// Windows 기본 화면 키보드 또는 앱 내장 키보드 선택.
  final KeyboardMode keyboardMode;

  /// 메뉴 버튼을 한 번 누를 때 설정된 URL 로 강제 초기화하지 않고, 현재
  /// 페이지 상태(스크롤/내부 네비 등)를 유지할지 여부.
  ///
  /// - `false` (기본): 모든 클릭이 설정된 URL 로 이동(현재 동작).
  /// - `true`: 다른 메뉴를 누르면 그 항목으로 전환만 하고, **이미 선택된**
  ///   메뉴를 단일 클릭하면 아무 동작도 하지 않는다. 같은 메뉴를 빠르게
  ///   더블 탭하면 설정된 URL 로 새로 로드한다.
  final bool keepStateOnTap;

  /// 앱 시작 시 툴바를 감춘 상태로 표시할지 여부.
  final bool toolbarInitiallyHidden;

  /// 펼친 툴바를 사용자 입력 없이 유지할 시간(초).
  /// `0`이면 자동 숨김을 사용하지 않는다.
  final int toolbarAutoHideSec;

  /// 네비게이션 바 배경색. `null`이면 테마 기본값.
  final Color? barColor;

  /// 비선택 버튼의 배경색. `null`이면 테마 기본값.
  final Color? buttonColor;

  /// 비선택 버튼의 전경색(텍스트/아이콘). `null`이면 테마 기본값.
  final Color? buttonForegroundColor;

  /// 선택된 버튼의 배경색. `null`이면 테마 기본값(primary).
  final Color? selectedButtonColor;

  /// 선택된 버튼의 전경색. `null`이면 테마 기본값(onPrimary).
  final Color? selectedButtonForegroundColor;

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
    this.showKeyboardToggle = false,
    this.showSelectedTopic = true,
    this.windowsKioskLockdown = true,
    this.windowsAlwaysOnTop = false,
    this.keyboardMode = KeyboardMode.windows,
    this.keepStateOnTap = false,
    this.toolbarInitiallyHidden = true,
    this.toolbarAutoHideSec = 10,
    this.barColor,
    this.buttonColor,
    this.buttonForegroundColor,
    this.selectedButtonColor,
    this.selectedButtonForegroundColor,
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
      showKeyboardToggle: () {
        final v = json['showKeyboardToggle'];
        if (v == null) return defaults.showKeyboardToggle;
        if (v is bool) return v;
        throw const FormatException(
          'menu.json layout.showKeyboardToggle: bool 필요',
        );
      }(),
      showSelectedTopic: () {
        final v = json['showSelectedTopic'];
        if (v == null) return defaults.showSelectedTopic;
        if (v is bool) return v;
        throw const FormatException(
          'menu.json layout.showSelectedTopic: bool 필요',
        );
      }(),
      windowsKioskLockdown: () {
        final v = json['windowsKioskLockdown'];
        if (v == null) return defaults.windowsKioskLockdown;
        if (v is bool) return v;
        throw const FormatException(
          'menu.json layout.windowsKioskLockdown: bool 필요',
        );
      }(),
      windowsAlwaysOnTop: () {
        final v = json['windowsAlwaysOnTop'];
        if (v == null) return defaults.windowsAlwaysOnTop;
        if (v is bool) return v;
        throw const FormatException(
          'menu.json layout.windowsAlwaysOnTop: bool 필요',
        );
      }(),
      keyboardMode: _parseKeyboardMode(json['keyboardMode']),
      keepStateOnTap: () {
        final v = json['keepStateOnTap'];
        if (v == null) return defaults.keepStateOnTap;
        if (v is bool) return v;
        throw const FormatException(
          'menu.json layout.keepStateOnTap: bool 필요',
        );
      }(),
      toolbarInitiallyHidden: () {
        final v = json['toolbarInitiallyHidden'];
        if (v == null) return defaults.toolbarInitiallyHidden;
        if (v is bool) return v;
        throw const FormatException(
          'menu.json layout.toolbarInitiallyHidden: bool 필요',
        );
      }(),
      toolbarAutoHideSec: () {
        final v = json['toolbarAutoHideSec'];
        if (v == null) return defaults.toolbarAutoHideSec;
        if (v is num && v >= 0) return v.toInt();
        throw const FormatException(
          'menu.json layout.toolbarAutoHideSec: 0 이상의 숫자 필요',
        );
      }(),
      barColor: _parseColor(json['barColor'], 'barColor'),
      buttonColor: _parseColor(json['buttonColor'], 'buttonColor'),
      buttonForegroundColor:
          _parseColor(json['buttonForegroundColor'], 'buttonForegroundColor'),
      selectedButtonColor:
          _parseColor(json['selectedButtonColor'], 'selectedButtonColor'),
      selectedButtonForegroundColor: _parseColor(
        json['selectedButtonForegroundColor'],
        'selectedButtonForegroundColor',
      ),
    );
  }
}

/// 색상 문자열을 [Color] 로 파싱한다.
///
/// 지원 형식 (대소문자 무관, `#` 선택):
/// - `#RGB`        → 짧은 표현 (예: `#f00` = 빨강)
/// - `#RRGGBB`     → 불투명 RGB
/// - `#AARRGGBB`   → 알파 + RGB
/// - 명명 색상: `transparent`
Color? _parseColor(Object? raw, String key) {
  if (raw == null) return null;
  if (raw is! String) {
    throw FormatException('menu.json layout.$key: 문자열 필요');
  }
  var s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  if (s == 'transparent') return const Color(0x00000000);

  if (s.startsWith('#')) s = s.substring(1);

  // #RGB → #RRGGBB 로 확장.
  if (s.length == 3) {
    s = s.split('').map((c) => '$c$c').join();
  }

  if (s.length == 6) {
    s = 'ff$s'; // 알파 채우기
  }

  if (s.length != 8 || int.tryParse(s, radix: 16) == null) {
    throw FormatException(
      'menu.json layout.$key: 색상 형식 오류 "$raw" '
      '(예: "#1976d2", "#80ffffff")',
    );
  }
  return Color(int.parse(s, radix: 16));
}
