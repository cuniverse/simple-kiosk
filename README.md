# 여의도성당Signage

GitHub: https://github.com/cuniverse/simple-kiosk

성당 로비용 Flutter 디지털 사이니지 WebView 앱입니다.
좌측(또는 하단) 네비게이션 버튼을 누르면 설정된 URL을 우측 WebView 영역에 표시합니다.

- 최신 안정 버전: [`v1.2.27`](https://github.com/cuniverse/simple-kiosk/releases/tag/v1.2.27)
- 변경 내역: [RELEASE_NOTES.md](RELEASE_NOTES.md)
- 운영자 매뉴얼: [docs/MANUAL.md](docs/MANUAL.md)
- Windows 최초 설치: [docs/WINDOWS_FIRST_INSTALL.md](docs/WINDOWS_FIRST_INSTALL.md)

## 지원 OS

- Android
- Windows
- macOS

> iOS / Linux도 `flutter_inappwebview`가 지원하지만, 본 프로젝트는 Android / Windows / macOS를 지원 대상으로 합니다.

## 주요 기능

- 기본 JSON(`assets/config/menu.defaults.json`) + 외부 운영 오버라이드 기반 메뉴 구성
- 좌측 사이드 네비게이션, 좁은 화면에서는 하단 네비게이션으로 자동 전환
- 49인치 가로형 터치 사이니지에 적합한 큰 버튼 (최소 높이 72dp)
- 현재 선택된 메뉴 시각적 강조 표시
- 모든 배치의 툴바 감추기/복원 — 숨김 상태에서는 뒤로·앞으로·툴바 복원·가상 키보드만 플로팅 표시하며 네 모서리로 드래그 이동
- WebView 로딩 인디케이터 및 에러 화면(재시도 버튼)
- **메뉴별 독립 WebView (IndexedStack)** — 다른 메뉴로 갔다가 돌아와도 스크롤/내부 페이지 상태 유지 (`keepStateOnTap` 옵션)
- 같은 메뉴 더블 탭 시 강제 초기 URL 재로드
- 새 창 / 팝업 / 외부 스킴 (tel:, mailto:, intent: 등) 차단
- 다운로드 차단
- HTML5 video 인라인 재생 허용, JavaScript 허용
- Android Back 버튼: WebView 뒤로갈 수 있으면 뒤로, 아니면 홈 메뉴로 이동(앱 종료 방지)
- **자동 복구 루틴 (무인 운영)**:
  - 페이지 로드 에러 시 5초 후 자동 재시도, 3회 실패 시 WebView 통째로 재생성
  - 렌더러 프로세스 종료/응답없음 감지 → 자동 재생성
  - JS heartbeat 검사 (4초) — Alt+F4 등으로 WebView2 자식 창만 닫혀도 자동 복구
  - 메뉴 클릭 후 3초 내 응답 없으면 WebView 재생성
  - 메뉴 JSON 로드 실패 시 5초 후 자동 재시도
- **세션/메모리 위생**:
  - 대기화면 진입 시 설정에 따라 쿠키만 삭제(기본), 모든 사이트 데이터 삭제 또는 유지
  - 보존 도메인을 제외한 세션 정리 + 홈 외 모든 WebView 마운트 해제(메모리 회수)
- **자체 가상 키보드 (멀티 OS)**:
  - 한글(두벌식 자모 조합) / 영문(QWERTY) / 숫자·특수문자 모드
  - 드래그 가능한 플로팅 윈도우
  - WebView input 포커스 시 자동 호출 + 네비게이션 바 토글로 수동 호출 가능
  - 모든 OS (Windows / macOS / Linux / Android / iOS) 에서 동일 디자인/동작
- **대기화면(Idle)**: 일정 시간 무조작 시 슬라이드쇼/단일 이미지/URL/폴더/웹 포토갤러리 모드로 전환
- **Windows 업데이트·복구**: GitHub stable Release와 SHA-256을 검증하는 자동·수동 업데이트, 네이티브 Updater, 시작 실패 자동 롤백, 사용자 승인형 Setup 보조 설치 지원
- **원격 파일 관리**: WEB 관리자에서 업데이트에 유지되는 `exdata/` 폴더의 파일을 Windows 탐색기 형태로 업로드·다운로드·이름 변경·삭제
- **원격 운영·진단**: 로컬·원격 WEB 관리자에서 상태 확인, 설정·업데이트·재시작, 진단 자료 내보내기와 GitHub 이슈 등록 지원
- **UI 테마**: 레이아웃·동작과 UI 모양을 분리하고, 프리로드 테마 적용 및 편집한 모양의 사용자 테마 저장 지원

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

## Windows 설치 및 업데이트

Windows에서 앱을 다시 실행하면 기존 인스턴스가 트레이에 숨겨져 있어도 완전히 종료한
뒤 새 인스턴스를 시작합니다. 기존 프로세스가 종료되기 전에는 두 인스턴스가 동시에
실행되지 않으며, 기존 프로세스가 응답하지 않으면 해당 인스턴스만 강제 종료합니다.

처음 설치하는 PC에는 [최신 GitHub Release](https://github.com/cuniverse/simple-kiosk/releases/latest)의
`simple-kiosk-windows-setup-<version>.exe` 사용을 권장합니다. 설치 없이 시험하거나 별도
경로에서 운영하려면 `simple-kiosk-windows-<version>.zip`을 풀고 `ysignage.exe`를
실행합니다. 새 PC에서 포터블 ZIP을 사용할 때는 먼저 `InstallPrerequisites.cmd`를
실행하세요. 자세한 절차는 [Windows 최초 설치 문서](docs/WINDOWS_FIRST_INSTALL.md)에 있습니다.

### 업데이트 동작

- 자동 업데이트는 기본적으로 꺼져 있습니다. **설정 > 업데이트** 또는 WEB 관리자에서
  켜면 앱 시작 직후 stable Release를 확인하고 새 버전을 설치합니다.
- 수동 업데이트는 설정의 **지금 업데이트 확인 / 지금 설치**, WEB 관리자 또는 `F9`로
  실행합니다. 사용자가 직접 요청한 설치는 같은 버전의 이전 실패 횟수와 관계없이 다시
  시도합니다.
- 자동 설치가 같은 버전에서 3회 실패하면 반복 재시작을 막기 위해 일시 차단합니다.
  대상 버전이 바뀌거나 첫 실패 후 24시간이 지나면 실패 횟수와 시간 창을 초기화하고
  정상적인 자동 설치 절차를 다시 시작합니다.
- 기본 네이티브 Updater가 수동 설치 중 실패하면 실제 실패 사유를 표시하고 Setup 설치로
  전환할지 묻습니다. 사용자가 승인한 경우에만 같은 GitHub Release의 Setup EXE를
  다운로드하고 GitHub 자산의 SHA-256을 검증한 뒤 실행합니다. 자동 업데이트에서는
  Setup을 임의로 실행하지 않습니다.
- 업데이트 상태 문구는 마우스로 선택해 복사할 수 있습니다. 설치 실패 진단에는 종료
  코드뿐 아니라 `update-state.json`에 기록된 실제 오류 내용도 표시됩니다.
- 설치 후 새 버전이 정상 시작되지 않으면 이전 버전으로 자동 롤백합니다. 운영 설정,
  사용자 테마와 `exdata/` 파일은 업데이트 후에도 유지됩니다.

## WEB 관리자와 진단

프로그램의 **설정 > 관리 API / 관리자 페이지**에서 관리 서버를 켤 수 있습니다. 같은
PC에서는 로컬 관리자 주소를, 같은 네트워크에서는 기본적으로
`http://ysignage.local`을 사용합니다. 원격 WEB 관리자 연결이 구성된 장비에는
`http://ysignage<번호>.signage.cuniverse.net/` 형식의 주소가 배정됩니다.

WEB 관리자는 다음 운영 기능을 제공합니다.

- 실행 상태와 버전 확인, 사이니지 표시·감추기, 재시작과 완전 종료
- 언어·주제·메뉴, 레이아웃, 화면보호기, UI 테마와 업데이트 정책 편집
- 업데이트 후에도 유지되는 `exdata/` 전용 파일 탐색기와 다중·드래그 업로드
- 설정 백업·복원 및 프로그램·WebView·Updater·관리 API 로그가 포함된 진단 자료 내보내기
- 분류, 제목, 문제 설명, 재현 방법과 기대 결과를 작성하는 GitHub 이슈 등록

앱 설정의 **진단 정보로 이슈 등록**을 누르면 먼저 진단 자료를 내보낸 뒤 WEB 관리자의
진단·이슈 작성 화면을 바로 엽니다. GitHub 로그인이 없는 환경에서 실제 이슈를 등록하려면
GW 서버에 [`deploy/github-issue-relay`](deploy/github-issue-relay/README.md)의 중계기를
구성해야 합니다. 관리 페이지는 운영망의 접근 정책과 방화벽으로 보호하세요.

## 운영 단축키

| 키 | 기능 |
|---|---|
| `F1` | 앱 안에서 사용자 매뉴얼 열기 |
| `F9` | 수동 업데이트 확인·설치 |
| `F12` | 프로그램·Updater 버전과 GitHub 정보 표시 |
| `Ctrl+Alt+Shift+F4` 3초 | 화면 장애 시 네이티브 경로로 강제 종료(최후 수단) |

## 플랫폼별 릴리스 패키지

각 스크립트는 `dist/`에 버전이 포함된 ZIP을 만들며, ZIP 내부에는 플랫폼 실행 파일,
한국어 `INSTALL_GUIDE.md`, 상세 메뉴 설정 문서 `MENU_CONFIG_GUIDE.md`가 포함됩니다.

```bash
# Android (macOS/Linux)
bash scripts/package-android.sh

# macOS
bash scripts/package-macos.sh
```

```powershell
# Windows PowerShell
.\scripts\package-windows.ps1

# ZIP과 installer EXE 함께 생성 (Inno Setup 6 필요)
.\scripts\package-windows.ps1 -BuildInstaller

# 패키지 파일명에 사용할 버전을 직접 지정
.\scripts\package-windows.ps1 -PackageVersion 1.2.27
```

GitHub Actions 릴리스는 태그를 패키지 버전의 기준으로 사용합니다. 예를 들어
`v1.2.27` 태그는 업데이트 및 포터블 실행용 `simple-kiosk-windows-1.2.27.zip`, 최초
설치용 `simple-kiosk-windows-setup-1.2.27.exe`, 자동 업데이트용
`update-manifest.json`을 생성합니다. ZIP 안의
`ysignage.exe`는 압축 해제 후 직접 실행할 수 있습니다. 로컬에서
`-PackageVersion`을 생략하면 기존처럼 `pubspec.yaml`의 `version`을 사용합니다.

macOS에서는 Windows 네이티브 앱을 직접 빌드할 수 없습니다. GitHub 저장소의
`Build Windows release` Actions 워크플로를 수동 실행하거나 `v*` 태그를 푸시하면
Windows 러너가 ZIP을 생성합니다. 완성된 ZIP은 Actions Artifact와 GitHub Releases에
동시에 게시됩니다. Android와 macOS 패키지는 위의 로컬 스크립트로 생성합니다.

> Android는 현재 `android/app/build.gradle.kts` 설정에 따라 디버그 키로 서명됩니다.
> 외부 배포 전에는 조직의 정식 키스토어와 CI 비밀값을 구성해야 합니다. macOS 외부
> 배포 역시 Developer ID 서명 및 Apple 공증이 필요합니다.

### 플랫폼 폴더가 없는 경우

이 저장소는 Dart 소스/에셋/설정 위주로 관리됩니다.
처음 빌드하기 전에 플랫폼 폴더(`android/`, `windows/`, `macos/` 등)를 생성해야 할 수 있습니다.

```bash
flutter create --platforms=android,windows,macos .
flutter pub get
```

> `flutter create`는 기존 파일을 덮어쓰지 않습니다.

## 메뉴 설정 변경 방법

개발 기본값은 `assets/config/menu.defaults.json`에서 수정합니다. Windows 운영 설정은
`<ysignage.exe가 들어 있는 폴더>\config\menu.override.json`에 변경한 값만 기록합니다.
최상위 구조는 `layout`, `idle`, `languages`를 사용합니다. 화면보호기를 해제하면
동일한 큰 터치 버튼으로 등록된 언어와 주제를 차례로 선택하고 해당 언어·주제의 메뉴만
표시합니다.

프로그램 시작 시 schemaVersion 1, 최상위 `items`, `languages[].items`, 이전 웹 관리자가
만든 단일 `default` 주제 구조를 발견하면 현재 언어→주제→메뉴 구조로 자동
마이그레이션합니다. 변환 전 파일은 `backups/menu.override.before-migration-*.json`에
보관하며, 변환 결과가 유효하지 않으면 원본을 변경하지 않습니다.

### 최소 예시

```json
{
  "defaultLanguage": "ko",
  "languages": [
    {
      "id": "ko",
      "label": "한국어",
      "icon": "assets/icons/languages/kr.png",
      "defaultTopic": "general",
      "topics": [
        {
          "id": "general", "label": "전체", "defaultMenu": "home",
          "items": [
            { "id": "home", "title": "홈", "url": "https://example.com" }
          ]
        }
      ]
    },
    {
      "id": "en",
      "label": "English",
      "topics": [
        {
          "id": "general", "label": "General",
          "items": [
            { "id": "home", "title": "Home", "url": "https://example.com/en" }
          ]
        }
      ]
    }
  ]
}
```

언어를 추가하려면 `languages` 배열에 고유한 `id`, `label`, 한 개 이상의 `topics`를
가진 객체를 추가합니다. 각 주제는 고유한 `id`, 버튼 이름인 `label`, 독립된 `items`
목록을 가집니다. 기존 `languages[].items`는 단일 기본 주제로 자동 변환됩니다.
선택 화면 아이콘은 `icon`에 함께 배포되는 국기 이미지
(`assets/icons/languages/kr.png` 등), `icon:language`, 다른 `assets/...` 경로
또는 `https://...` 형식으로 지정합니다.
영어 기본 아이콘은 미국·영국 국기를 대각선으로 합성한
`assets/icons/languages/en-us-gb.png`를 사용합니다.
언어·주제·메뉴 항목에 `"hidden": true`를 지정하면 해당 선택 화면 또는 툴바에서
숨깁니다. 숨긴 기본 항목은 같은 범위의 첫 표시 항목으로 대체되며, 모든 언어나 표시
주제의 모든 메뉴를 숨긴 구성은 검증에서 거부됩니다.

### languages[].topics[].items[] — 메뉴 항목 필드

| 필드 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `id` | string | (필수) | 메뉴 식별자 (중복 불가 권장) |
| `title` | string | (필수) | 버튼에 표시될 텍스트 / 접근성 라벨 |
| `url` | string | (필수) | WebView에 로드할 URL. **운영 환경에서는 HTTPS 권장** |
| `icon` | string | `null` | 아이콘 경로. `assets/...`, `http(s)://...`, 또는 `icon:이름` (내장 머터리얼 아이콘) |
| `selectedIcon` | string | `null` | 선택 상태에서 사용할 아이콘 경로. 생략하면 `icon`을 그대로 사용 |
| `hidden` | bool | `false` | `true`이면 이 메뉴를 툴바에서 숨김 |
| `showTitle` | bool | `true` | 아이콘 있을 때 텍스트 동시 표시 여부. 아이콘 없으면 무시(텍스트 강제 표시) |
| `keepStateOnTap` | bool | `null` (=layout 값 상속) | 단일 클릭 시 이 항목의 현재 페이지 상태 유지 여부. 항목별 오버라이드 |

### layout — 네비게이션/외관 설정

아래 기본값은 현재 배포되는 `menu.defaults.json` 기준입니다.

| 필드 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `navPosition` | `auto`/`left`/`right`/`top`/`bottom` | `right` | 네비게이션 위치. `auto` 는 폭 `breakpoint` 기준 자동 전환 |
| `breakpoint` | number(dp) | `720` | `auto` 모드에서 사이드/하단을 가르는 폭 |
| `sideWidth` | number(dp) | `230` | 사이드 모드 폭 |
| `barHeight` | number(dp) | `102` | 상/하단 모드 높이 |
| `buttonHeight` | number(dp) | `0`(자동) | 각 버튼 높이 |
| `buttonWidth` | number(dp) | `0`(균등) | 하단 모드에서 버튼 폭. `0` 이고 `stretch` 이면 균등 분배 |
| `buttonGap` | number(dp) | `10` | 버튼 간 간격 |
| `buttonAlignment` | `start`/`center`/`end`/`spaceBetween`/`spaceAround`/`spaceEvenly`/`stretch` | `stretch` | 정렬 방식 |
| `showHistoryButtons` | bool | `true` | 하단 기능 버튼 묶음의 가장 앞에 WebView ←/→ 버튼 표시 |
| `showKeyboardToggle` | bool | `true` | 네비 끝 위치에 OS 가상 키보드 토글 버튼 표시 |
| `showSelectedTopic` | bool | `true` | 현재 주제만 작은 읽기 전용 상태 라벨로 표시 |
| `selectedTopicLabelColor` | color | `#f8fafc` | 읽기 전용 현재 주제 라벨의 글자색 |
| `windowsKioskLockdown` | bool | `true` | Windows에서 사이니지 표시 중 앱 전환·셸 단축키 차단 |
| `windowsKioskShortcuts` | object | 모두 `true` | 잠금 중 차단할 키와 키 조합을 개별 선택 |
| `windowsAlwaysOnTop` | bool | `false` | Windows 사이니지 창을 다른 일반 창보다 항상 위에 유지 |
| `windowsPreventScreenSaver` | bool | `true` | 사이니지 표시 중 Windows 화면보호기 실행 방지 |
| `windowsPreventDisplaySleep` | bool | `true` | 사이니지 표시 중 Windows 화면 자동 끄기 방지 |
| `keyboardMode` | `windows`/`builtin` | `windows` | Windows 기본 화면 키보드 또는 앱 내장 키보드 선택 |
| `keepStateOnTap` | bool | `false` | **기본 동작**: 같은 메뉴 단일 탭 시 상태 유지(아무 동작 없음), 더블 탭(300ms 이내) 시 강제 재로드. 항목별 `items[].keepStateOnTap` 으로 오버라이드 가능 |
| `toolbarInitiallyHidden` | bool | `false` | 앱 시작 시 툴바를 감춘 상태로 표시 |
| `toolbarAutoHideSec` | number | `0` | 툴바 복원 후 입력이 없을 때 다시 숨길 시간(초). `0`이면 자동 숨김 해제 |
| `barColor` | color | 테마 | 네비 바 배경색 |
| `buttonColor` / `buttonForegroundColor` | color | 테마 | 비선택 버튼 색 |
| `selectedButtonColor` / `selectedButtonForegroundColor` | color | 테마 (primary) | 선택 버튼 색 |

색상은 `#RGB`, `#RRGGBB`, `#AARRGGBB` 또는 `transparent` 형식.

### UI 글꼴

`layout.fontFamily`에 글꼴 이름을 지정할 수 있습니다. 탐색 순서는 실행 파일 기준
`fonts` 폴더 → Flutter 패키지 글꼴 → Windows 시스템 글꼴 → Flutter 기본 글꼴입니다.
외부 글꼴은 `fonts/<글꼴 이름>/` 폴더에 TTF/OTF 파일을 넣거나 파일 이름을 글꼴
이름으로 시작하게 구성합니다.

패키지에는 `Pretendard`, `NanumSquare`, `NanumGothic`, `NanumBrush`,
`KoPubDotum`, `Catholic`이 포함됩니다. 라이선스는
`assets/fonts/licenses`에서 확인할 수 있으며, 가톨릭체는 개인과 가톨릭
교회기관의 비영리·사목 목적에만 사용할 수 있습니다.

화면별 글꼴은 다음 우선순위로 적용됩니다.

- 툴바: `items[].fontFamily` → `layout.menuFontFamily` → `layout.fontFamily`
- 언어 선택: `languages[].fontFamily` → `languageSelection.fontFamily` → `layout.fontFamily`

빈 값이나 생략된 개별 설정은 상위 전체 설정을 상속합니다.

### idle — 대기화면 설정

자세한 옵션은 [docs/MANUAL.md](docs/MANUAL.md) 참고. 현재 배포 기본값은 300초 후
`gallery` 대기화면이며, `modes`에서 `slideshow`·`folder`·`gallery`를 복수 선택할 수
있습니다. `image`와 `url`은 단일 모드로 사용합니다.

### 전체 예시 (이 저장소의 기본 설정)

```json
{
  "layout": {
    "navPosition": "bottom",
    "buttonAlignment": "stretch",
    "showHistoryButtons": true,
    "showKeyboardToggle": true,
    "showSelectedTopic": true,
    "selectedTopicLabelColor": "#f8fafc",
    "windowsKioskLockdown": true,
    "windowsKioskShortcuts": {
      "windowsKey": true,
      "altTab": true,
      "altEscape": true,
      "altF4": true,
      "altSpace": true,
      "ctrlEscape": true,
      "ctrlShiftEscape": true,
      "launchApp1": true,
      "launchApp2": true,
      "launchMail": true,
      "browserHome": true,
      "browserSearch": true,
      "browserFavorites": true
    },
    "windowsAlwaysOnTop": false,
    "windowsPreventScreenSaver": true,
    "windowsPreventDisplaySleep": true,
    "keepStateOnTap": false,
    "toolbarInitiallyHidden": true,
    "toolbarAutoHideSec": 10,
    "barColor": "#000000",
    "buttonColor": "#171717",
    "buttonForegroundColor": "#ffffff",
    "selectedButtonColor": "#facc15",
    "selectedButtonForegroundColor": "#000000"
  },
  "idle": {
    "enabled": true,
    "timeoutSec": 60,
    "mode": "slideshow",
    "slideshow": {
      "intervalSec": 6,
      "transition": "fade",
      "images": ["assets/idle/slide1.jpg", "assets/idle/slide2.jpg"]
    }
  },
  "defaultLanguage": "ko",
  "languages": [
    {
      "id": "ko",
      "label": "한국어",
      "items": [
        { "id": "home", "title": "홈", "url": "https://example.com", "icon": "icon:home" },
        { "id": "notice", "title": "공지", "url": "https://example.com/notice", "icon": "icon:notice" }
      ]
    },
    {
      "id": "en",
      "label": "English",
      "items": [
        { "id": "home", "title": "Home", "url": "https://example.com/en", "icon": "icon:home" }
      ]
    }
  ]
}
```

수정 후에는 앱을 다시 실행하면 변경사항이 반영됩니다.

### Android에서 HTTP 사용이 필요한 경우

Android 9(API 28) 이상에서는 기본적으로 평문 HTTP 트래픽이 차단됩니다.
HTTP URL을 사용해야 하는 경우, `AndroidManifest.xml`의 `<application>`에
`android:usesCleartextTraffic="true"` 또는 `networkSecurityConfig`를 설정해야 합니다.

## 가상 키보드

Windows에서는 기본적으로 Windows 화상 키보드를 사용합니다. 설정의
`layout.keyboardMode`를 `builtin`으로 바꾸면 Flutter 자체 가상 키보드를 사용합니다.
Windows 키보드 실행이 불가능하면 내장 키보드로 자동 대체됩니다.

- 한글(두벌식 자모 조합) / 영문(QWERTY) / 숫자·특수문자 모드 토글
- Shift 단일/잠금
- 화면 어디든 드래그 가능한 **플로팅 윈도우** 형태
- 자동 호출: 앱 설정 입력 폼과 WebView 내 `<input>` / `<textarea>` /
  `[contenteditable]`(iframe 포함) 포커스 시
- 수동 호출: 네비게이션 바의 키보드 토글 버튼(`showKeyboardToggle: true`)
- 한글 조합 결과를 `input` / `change` 이벤트 디스패치로 페이지에 정상 전달

| OS | 동작 |
|---|---|
| Windows | Windows 키보드(기본) 또는 Flutter 내장 키보드 |
| Android / iOS / macOS / Linux | Flutter 내장 키보드 |

> 향후 추가 언어 레이아웃은 [lib/widget/virtual_keyboard.dart](lib/widget/virtual_keyboard.dart) 의 `_KbMode` 와 `_rows` 에 추가하면 됩니다.

## Windows에서 실행 시 주의사항

프로그램의 **설정 > Windows 시작프로그램**에서 현재 등록 상태를 확인하고 등록하거나
삭제할 수 있습니다. 자동 실행 시 즉시 전체 화면을 표시하는 `사이니지 모드`와 창을
숨기고 트레이에서만 실행하는 `숨김 모드`를 선택할 수 있습니다.

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

### 사이니지 전체화면 모드

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
- 사이니지 용도로 배포하는 경우 전체 화면 실행, 자동 로그인, 절전 방지 등 macOS 시스템 설정을 함께 구성하는 것을 권장합니다.

## WebView 제약사항

- 일부 사이트는 보안 정책상 `iframe`/WebView 임베드를 차단합니다. 이 경우 앱에서 우회할 수 없습니다.
- 일부 사이트는 User-Agent 검사 등으로 WebView 접속 자체를 차단할 수 있습니다.
- 동영상 **자동재생**은 브라우저/플랫폼 정책 영향을 받습니다 (사용자 제스처 없이는 재생이 시작되지 않을 수 있음).
- Windows에서는 WebView2 Runtime이 설치되어 있어야 동작합니다.
- macOS에서는 앱 샌드박스 및 entitlements 설정에 따라 네트워크 접근 권한이 필요합니다.
- 다운로드 / 팝업 / 외부 스킴(전화, 메일 등)은 사이니지 보안 정책상 의도적으로 차단됩니다.

## 프로젝트 구조

```text
lib/
  main.dart                          # 앱 진입점, 로깅과 전체화면 초기화
  app.dart                           # MaterialApp, 메뉴 로딩, IndexedStack 기반 메뉴별 WebView,
                                     #   대기화면 라이프사이클, Back 버튼 정책
  model/
    menu_item.dart                   # 주제별 메뉴 항목 모델
    menu_language.dart               # 언어와 기본 주제 모델
    menu_topic.dart                  # 주제와 기본 메뉴 모델
    layout_config.dart               # 네비게이션 레이아웃/색상 설정
    idle_config.dart                 # 대기화면 설정
    menu_config.dart                 # 위 셋을 묶은 최상위 설정
  service/
    menu_config_loader.dart          # 기본값·오버라이드 병합 설정 로더
    menu_config_merger.dart          # 설정 스키마 호환 병합
    admin_api_controller.dart        # 로컬/원격 WEB 관리자 HTTP API
    configuration_backup_service.dart # 운영 설정 백업·가져오기·직전 설정 복원
    diagnostics_service.dart         # 로그·시스템·업데이트 진단 자료 생성
    exdata_file_service.dart         # exdata 경계 내부 파일 관리
    update_controller.dart           # 자동/수동 업데이트 UI 흐름 제어
    update_service.dart              # Release 조회·다운로드·해시 검증·Updater 실행
    web_admin_ssh_tunnel_controller.dart # 원격 WEB 관리자 SSH 터널과 ID 관리
    keyboard_controller.dart         # 가상 키보드 표시 상태/입력 이벤트 라우터
    system_keyboard.dart             # SystemKeyboard.show/hide (KeyboardController 래퍼)
    hangul_composer.dart             # 두벌식 한글 자모 조합기
    media_scanner.dart               # 대기화면 폴더 모드용 미디어 스캐너
    video_controller_factory.dart    # 대기화면 비디오 컨트롤러 팩토리
  widget/
    update_admin_dialog.dart         # PIN 보호 설정·업데이트·진단 화면
    navigation_menu.dart             # 사이드/하단 공용 네비, 히스토리/키보드 토글
    kiosk_webview.dart               # WebView 위젯 (로딩/에러/차단/자동 복구/heartbeat/키보드 입력 주입)
    virtual_keyboard.dart            # 플로팅 가상 키보드 위젯
    idle_gate.dart                   # 대기화면 표시 게이트
    idle_overlay.dart                # 대기화면 오버레이
    material_icon_registry.dart      # icon:이름 → IconData 매핑

assets/
  admin/index.html                   # 내장 웹 관리자 페이지
  config/menu.defaults.json          # 메뉴/레이아웃/대기화면 기본 설정
  icons/                             # 메뉴 아이콘 이미지
  idle/                              # 대기화면용 미디어
  ssh/                               # 원격 WEB 관리자 접속 전용 SSH 키
packages/
  dartssh2-3.3.1/                    # 소스 포함 SSH 및 stream-local forwarding 라이브러리
deploy/
  github-issue-relay/                # 로그인 없는 GitHub 이슈 등록용 PHP/Nginx 예시
tool/
  windows_updater.dart               # 네이티브 Windows Updater 진입점
```

원격 WEB 관리자용 개인 키는 `assets/ssh/web-admin-tunnel-key`에 추가합니다. 이 폴더는
Flutter asset으로 등록되어 Windows ZIP과 설치 프로그램에 자동 포함됩니다. 키가 없는
개발 빌드는 원격 연결을 시도하지 않고 설정 화면에 키 미포함 상태를 표시합니다.

원격 WEB 관리자의 GitHub 이슈 리포트를 로그인 없이 바로 등록하려면 GW 서버에
[`deploy/github-issue-relay`](deploy/github-issue-relay/README.md)의 PHP 중계기와
Nginx location을 설치합니다. GitHub App 개인키는 GW 서버에만 저장합니다.
