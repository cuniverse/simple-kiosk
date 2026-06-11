# Simple Kiosk

성당 로비 또는 디지털 사이니지용 Flutter 키오스크 WebView 앱입니다.
좌측(또는 하단) 네비게이션 버튼을 누르면 설정된 URL을 우측 WebView 영역에 표시합니다.

## 지원 OS

- Android
- Windows
- macOS

> iOS / Linux도 `flutter_inappwebview`가 지원하지만, 본 프로젝트는 Android / Windows / macOS를 지원 대상으로 합니다.

## 주요 기능

- JSON 설정(`assets/config/menu.json`) 기반 메뉴 구성
- 좌측 사이드 네비게이션, 좁은 화면에서는 하단 네비게이션으로 자동 전환
- 49인치 가로형 터치 사이니지에 적합한 큰 버튼 (최소 높이 72dp)
- 현재 선택된 메뉴 시각적 강조 표시
- WebView 로딩 인디케이터 및 에러 화면(재시도 버튼)
- 새 창 / 팝업 / 외부 스킴 (tel:, mailto:, intent: 등) 차단
- 다운로드 차단
- HTML5 video 인라인 재생 허용, JavaScript 허용
- Android Back 버튼: WebView 뒤로갈 수 있으면 뒤로, 아니면 홈 메뉴로 이동(앱 종료 방지)

## 실행 방법

```bash
flutter pub get

# Android 기기 또는 에뮬레이터에서 실행
flutter run -d android

# Windows에서 실행 (WebView2 Runtime 필요할 수 있음)
flutter run -d windows

# macOS에서 실행
flutter run -d macos
```

### 플랫폼 폴더가 없는 경우

이 저장소는 Dart 소스/에셋/설정 위주로 관리됩니다.
처음 빌드하기 전에 플랫폼 폴더(`android/`, `windows/`, `macos/` 등)를 생성해야 할 수 있습니다.

```bash
flutter create --platforms=android,windows,macos .
flutter pub get
```

> `flutter create`는 기존 파일을 덮어쓰지 않습니다.

## 메뉴 설정 변경 방법

`assets/config/menu.json` 파일을 수정합니다. 각 항목은 다음 필드를 가집니다.

```json
[
  {
    "id": "home",
    "title": "홈",
    "url": "https://example.com"
  },
  {
    "id": "notice",
    "title": "공지",
    "url": "https://example.com/notice"
  }
]
```

- `id`: 메뉴 식별자 (문자열, 중복 불가 권장)
- `title`: 버튼에 표시될 텍스트
- `url`: WebView에 로드할 URL
  - **운영 환경에서는 HTTPS 사용을 권장합니다.** HTTP도 동작하지만, 보안과 신뢰성 측면에서 HTTPS를 권장합니다.

수정 후에는 앱을 다시 실행하면 변경사항이 반영됩니다.

### Android에서 HTTP 사용이 필요한 경우

Android 9(API 28) 이상에서는 기본적으로 평문 HTTP 트래픽이 차단됩니다.
HTTP URL을 사용해야 하는 경우, `AndroidManifest.xml`의 `<application>`에
`android:usesCleartextTraffic="true"` 또는 `networkSecurityConfig`를 설정해야 합니다.

## Windows에서 실행 시 주의사항

- **새 Windows 환경에서 처음 빌드한다면 [docs/WINDOWS_SETUP.md](docs/WINDOWS_SETUP.md) 를 먼저 따라가세요.**
  개발자 모드 활성화, NuGet CLI 설치, WebView2 Runtime 설치를 한 번에 처리합니다.
- 자동 셋업 스크립트:
  ```powershell
  ./scripts/setup-windows-dev.ps1        # 점검 + 설치
  ./scripts/setup-windows-dev.ps1 -Run   # 셋업 후 바로 flutter run -d windows
  ```
- **WebView2 Runtime이 필요할 수 있습니다.**
  Windows 11에는 기본 포함되어 있지만, 일부 Windows 10 환경에서는 설치되어 있지 않을 수 있습니다.
  설치되지 않은 경우 Microsoft 공식 페이지에서 "Microsoft Edge WebView2 Runtime"을 다운로드해 설치하세요.
- `flutter_inappwebview` Windows 구현은 WebView2를 기반으로 동작합니다.

### 키오스크 전체화면 모드

- 데스크톱(Windows / macOS / Linux) 빌드는 시작 시 자동으로 **borderless fullscreen** 으로 표시됩니다.
  ([lib/main.dart](lib/main.dart), [`window_manager`](https://pub.dev/packages/window_manager) 사용)
- Android는 `immersiveSticky` 모드로 시스템 UI(상태바/네비게이션 바)를 자동 숨김 처리합니다.
- 종료: `flutter run` 콘솔에서 `q`, 또는 `Alt + F4`.
- 개발 중 일반 창으로 띄우고 싶다면 환경변수 `SIMPLE_KIOSK_WINDOWED=1` 설정 후 실행:
  ```powershell
  $env:SIMPLE_KIOSK_WINDOWED = '1'
  flutter run -d windows
  ```

## macOS에서 실행 시 주의사항

- macOS 데스크톱 앱 빌드를 위해 Xcode와 CocoaPods 설정이 필요합니다.
- WebView에서 외부 URL을 로드할 수 있도록 macOS entitlements에 `com.apple.security.network.client`가 포함되어 있습니다.
- 키오스크 용도로 배포하는 경우 전체 화면 실행, 자동 로그인, 절전 방지 등 macOS 시스템 설정을 함께 구성하는 것을 권장합니다.

## WebView 제약사항

- 일부 사이트는 보안 정책상 `iframe`/WebView 임베드를 차단합니다. 이 경우 앱에서 우회할 수 없습니다.
- 일부 사이트는 User-Agent 검사 등으로 WebView 접속 자체를 차단할 수 있습니다.
- 동영상 **자동재생**은 브라우저/플랫폼 정책 영향을 받습니다 (사용자 제스처 없이는 재생이 시작되지 않을 수 있음).
- Windows에서는 WebView2 Runtime이 설치되어 있어야 동작합니다.
- macOS에서는 앱 샌드박스 및 entitlements 설정에 따라 네트워크 접근 권한이 필요합니다.
- 다운로드 / 팝업 / 외부 스킴(전화, 메일 등)은 키오스크 보안 정책상 의도적으로 차단됩니다.

## 프로젝트 구조

```text
lib/
  main.dart                       # 앱 진입점, 화면 방향 설정
  app.dart                        # MaterialApp, 메뉴 로딩, 홈 레이아웃, Back 버튼 정책
  model/menu_item.dart            # 메뉴 항목 모델
  service/menu_config_loader.dart # menu.json 로더
  widget/navigation_menu.dart     # 사이드 / 하단 공용 네비게이션
  widget/kiosk_webview.dart       # WebView 위젯 (로딩/에러/차단 정책)

assets/
  config/menu.json                # 메뉴 설정
```
