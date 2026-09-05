# 여의도성당Signage 사용 매뉴얼

성당 로비용 디지털 사이니지 앱의 **운영자 / 콘텐츠 관리자**를 위한 매뉴얼입니다.
개발자용 설치·빌드 안내는 [README.md](../README.md) 를 참조하세요.

---

## 목차

1. [개요](#1-개요)
2. [화면 구성](#2-화면-구성)
3. [설정 파일 한눈에 보기](#3-설정-파일-한눈에-보기)
4. [메뉴 관리](#4-메뉴-관리)
5. [네비게이션 바 레이아웃](#5-네비게이션-바-레이아웃)
6. [아이콘 사용](#6-아이콘-사용)
7. [대기화면(Idle Screen)](#7-대기화면idle-screen)
8. [뒤로 / 앞으로 컨트롤](#8-뒤로--앞으로-컨트롤)
9. [가상 키보드](#9-가상-키보드)
10. [자동 복구 / 세션 위생](#10-자동-복구--세션-위생)
11. [운영 팁](#11-운영-팁)
12. [문제 해결](#12-문제-해결)

---

## 1. 개요

- **목적**: 사이니지 단말기에서 미리 정의된 웹페이지 몇 개를 메뉴 버튼으로 전환해 보여주기.
- **핵심 정책**:
  - 새 창 / 팝업 / 외부 스킴(`tel:`, `mailto:` 등) **차단**
  - 다운로드 **차단**
  - **메뉴별 독립 WebView** (IndexedStack): 다른 메뉴에 다녀와도 스크롤/내부 페이지 상태 유지
  - 같은 메뉴 **더블 탭** (300ms 이내) 으로 강제 초기 URL 재로드
  - 대기화면을 띄워 무인 운영하고, 해제 직후 큰 버튼으로 언어 선택
  - 언어별로 완전히 독립된 메뉴 이름·URL·아이콘 구성
  - **세션 위생**: 대기화면 진입 시 정책에 따라 쿠키 또는 전체 사이트 데이터를 정리하고,
    필요한 도메인의 로그인 데이터는 보존 가능
  - **자동 복구**: 페이지 에러 / 렌더러 종료 / Alt+F4 등 비정상 상황에서 WebView 자동 재생성
- **기본값과 운영 설정 분리**: `assets/config/menu.defaults.json` + 외부 `menu.override.json`

---

## 2. 화면 구성

```
┌──────────────────────────────────────────────────┐
│                                                  │
│                WebView (콘텐츠)                   │
│                                                  │
│                                                  │
├──────────────────────────────────────────────────┤
│ [←][→]  [홈] [공지] [갤러리] [주보] [...]  [⌨]   │  ← 네비게이션 바
└──────────────────────────────────────────────────┘
   ↑                                            ↑
   히스토리 ←/→ (옵션)                      키보드 토글 (옵션)
```

- **네비게이션 바**: 좌/우/상/하 어디에든 배치 가능 (설정으로 변경)
- **뒤로/앞으로 버튼**: `showHistoryButtons` 활성화 시 키보드·설정 등 하단 기능 버튼 묶음의 가장 앞에 표시
- **키보드 토글 버튼**: `showKeyboardToggle` 활성화 시 바의 **끝점** 에 표시
- **언어 선택으로 돌아가기**: 세로 바의 최상단 또는 가로 바의 맨 왼쪽에 있는 전용 뒤로가기 버튼으로 언어 선택 화면으로 이동
- **현재 주제 라벨**: `showSelectedTopic` 활성화 시 현재 주제 제목을 표시하며 클릭하면 현재 언어의 주제 선택 화면으로 이동
- **툴바 감추기 버튼**: 좌·우·상·하 툴바에서 `툴바 감추기` 버튼으로 전체 툴바를 감춤. 감춘 뒤에는
  `←`, `→`, 툴바 복원, `⌨`(가상 키보드) 버튼만 플로팅으로 표시. 컨트롤을
  드래그한 뒤 놓으면 왼쪽 위·오른쪽 위·왼쪽 아래·오른쪽 아래 중 가까운 모서리에 정렬
- **기능 버튼 자동 정렬**: 키보드·설정·화면 보호기·툴바 감추기 버튼은 표시 개수와
  앞·뒤 네비게이션 버튼을 포함한 표시 개수와 툴바 폭에 맞춰 같은 크기로 조절됩니다.
  사이드 툴바에서는 최소 40px 크기를 유지하며, 한 줄 공간이 부족하면 균형 있게 여러 줄로 배치
  (기능 버튼 6개는 3개씩 두 줄)
- **사이니지 감추기 제스처**: `화면 보호기 시작`을 더블클릭한 뒤 5초 안에 `툴바 감추기`를 더블클릭해야 사이니지 창이 감추어짐
- 각 버튼을 단일 클릭하면 기존처럼 화면 보호기 시작과 툴바 감추기만 수행
- **버전 오버레이**: 현재 앱 버전을 작은 반투명 글씨로 표시. 언어 선택 화면은 우측 하단,
  사이드 툴바는 하단 기능 버튼 아래, 하단 툴바는 툴바 바로 위 우측, 상단 툴바는 화면 우측 하단에 배치
- **대기화면**: 일정 시간 무입력 시 자동 진입, 화면 터치로 해제한 뒤 언어 선택.
  언어 선택 화면의 `화면 보호기로 돌아가기` 버튼으로 즉시 복귀하며, 언어를 선택하지
  않고 `idle.timeoutSec` 동안 입력이 없어도 자동으로 화면보호기로 돌아감
- **메뉴별 WebView**: 메뉴 인덱스마다 독립된 WebView 인스턴스를 lazy 생성하여 IndexedStack 으로 전환

---

## 3. 설정 파일 한눈에 보기

`assets/config/menu.defaults.json` 전체 구조:

```json
{
  "layout": { ... },   // 네비게이션 바 모양/위치
  "idle":   { ... },   // 대기화면 설정 (옵션)
  "webViewData": { ... }, // WebView 데이터 정리 정책
  "defaultLanguage": "ko",
  "languageSelection": { ... },
  "languages": [       // 언어, 언어별 주제와 주제별 메뉴 목록
    { "id": "ko", "label": "한국어", "defaultTopic": "general", "topics": [ ... ] },
    { "id": "en", "label": "English", "topics": [ ... ] }
  ]
}
```

설정 변경 후 **앱 재시작**이 필요합니다. (개발 중 핫리스타트는 `R` 키)

Windows에서는 프로그램 시작 시 구형 `menu.override.json`을 자동 검사합니다.
schemaVersion 1, 최상위 `items`, `languages[].items`와 이전 웹 관리자가 만든 단일
`default` 주제는 현재 언어→주제→메뉴 구조로 변환됩니다. 원본은 프로그램 폴더의
`backups/menu.override.before-migration-*.json`에 백업되고, 검증에 성공한 경우에만
새 설정으로 교체됩니다.

---

## 4. 메뉴 관리

### 다국어 기본 형식

```json
"defaultLanguage": "ko",
"languageSelection": {
  "fontFamily": "Catholic",
  "backgroundColor": "#ffffff",
  "foregroundColor": "#111827",
  "secondaryForegroundColor": "#4b5563",
  "buttonWidth": 400,
  "buttonHeight": 190,
  "buttonColor": "#3f51b5",
  "buttonForegroundColor": "#ffffff",
  "selectedButtonColor": "#3f51b5",
  "selectedButtonForegroundColor": "#ffffff",
  "title": "언어를 선택하세요",
  "subtitle": "Please select your language",
  "topicTitle": "주제를 선택하세요",
  "topicSubtitle": "Please select a topic",
  "skipSingleTopic": true
},
"languages": [
  {
    "id": "ko",
    "label": "한국어",
    "subtitle": "Korean",
    "defaultTopic": "general",
    "topics": [
      {
        "id": "general",
        "label": "전체",
        "defaultMenu": "home",
        "items": [
          { "id": "home", "title": "홈", "url": "https://ko.example.com" }
        ]
      }
    ]
  },
  {
    "id": "en",
    "label": "English",
    "subtitle": "영어",
    "topics": [
      {
        "id": "general",
        "label": "General",
        "items": [
          { "id": "home", "title": "Home", "url": "https://en.example.com" }
        ]
      }
    ]
  }
]
```

| `languageSelection` 키 | 기본값 | 설명 |
|---|---:|---|
| `fontFamily` | `Catholic` | 제목·부제·선택 버튼의 전체 글꼴 |
| `backgroundColor` | `#ffffff` | 언어·주제 선택 화면 배경색 |
| `foregroundColor` | `#111827` | 제목과 기본 강조 요소 색상 |
| `secondaryForegroundColor` | `#4b5563` | 부제 글자색 |
| `buttonWidth` / `buttonHeight` | `400` / `190` | 언어·주제 선택 버튼 크기(dp). 좁은 화면에서는 너비 자동 축소 |
| `buttonColor` / `buttonForegroundColor` | `#3f51b5` / `#ffffff` | 일반 선택 버튼 배경·전경색 |
| `selectedButtonColor` / `selectedButtonForegroundColor` | `#3f51b5` / `#ffffff` | 선택되어 상단으로 이동한 언어 버튼 배경·전경색 |

색상 값을 생략하거나 빈 문자열로 두면 현재 테마 색상을 상속합니다.

- 화면보호기를 해제하면 언어 버튼이 표시되고, 언어를 선택하면 해당 버튼이 상단으로
  이동한 뒤 `topics`의 주제 버튼이 표시됩니다.
- `languageSelection.skipSingleTopic`이 `true`이면 주제가 하나뿐인 언어는 주제 화면을
  건너뛰고 바로 진입합니다. 기본값은 `true`입니다.
- 언어와 주제 선택 버튼은 동일한 큰 터치 규격으로 표시되며 화면 폭이 부족하면 자동으로
  줄바꿈되거나 스크롤됩니다. 버튼 문구는 단어 내부를 나누지 않고 공백 위치에서
  우선 줄바꿈하며, 긴 단어는 버튼 폭에 맞게 글자 크기를 자동 조절합니다.
- 툴바 시작 위치의 **뒤로가기** 아이콘을 누르면 현재 WebView 상태를 유지한 채 언어 선택
  화면으로 다시 돌아갈 수 있습니다.
- 돌아가기 버튼의 긴 문구는 언어별 `languageSelectionBackLabel`, 좁은 가로
  툴바의 짧은 문구는 `languageSelectionLabel`로 설정합니다. 생략하면 `ko`, `en`,
  `es`, `fr`, `pt`, `it` 언어 ID에 맞는 기본 번역을 사용하고 알 수 없는 ID는
  한국어 문구를 사용합니다.
- 주제 선택 화면의 제목과 부제는 언어별 `topicSelectionTitle`,
  `topicSelectionSubtitle`로 설정하고, 언어 목록으로 돌아가는 버튼은
  `changeLanguageLabel`로 설정합니다. 생략하면 지원 언어 ID에 맞는 기본 번역을
  사용하며, 알 수 없는 언어 ID의 제목·부제는 전역 설정을 사용합니다.
- 언어를 추가하려면 고유한 `id`, 버튼에 표시할 `label`, 한 개 이상의 `topics`를 추가합니다.
- `defaultLanguage`는 앱 내부에서 언어 선택 전 준비할 기본 언어입니다.
- `languages[].defaultTopic`은 해당 언어의 기본 주제이며 생략하면 첫 주제를 사용합니다.
- 각 `topics[]`는 고유한 `id`, 표시할 `label`, 선택적 `subtitle`·`icon`, 독립된
  `items` 목록을 가집니다.
- `topics[].defaultMenu`는 주제 선택 직후 표시할 메뉴이며 생략하면 첫 메뉴를 사용합니다.
- 언어의 `icon`에는 함께 배포되는 국기 이미지(`assets/icons/languages/kr.png`
  등), `icon:language`, 다른 앱 에셋 경로 또는 HTTPS 이미지 주소를 지정할 수 있습니다.
- 영어 기본 아이콘은 미국·영국 국기를 대각선으로 합성한
  `assets/icons/languages/en-us-gb.png`입니다.
- 언어·주제·메뉴 항목에 `hidden: true`를 지정하면 해당 선택 화면 또는 툴바에서
  숨깁니다. 생략하면 표시하며, 숨긴 기본 항목은 같은 범위의 첫 표시 항목으로
  자동 대체됩니다.
- 모든 언어를 숨기거나 표시되는 주제의 메뉴를 모두 숨긴 설정은 저장할 수 없습니다.
- 기존 최상위 `items` 또는 `languages[].items` 설정도 단일 언어·단일 주제로 계속 동작합니다.

### 메뉴 항목 형식

| 필드 | 필수 | 설명 |
|------|------|------|
| `id` | ✓ | 메뉴 식별자. 중복 금지 권장. |
| `title` | ✓ | 버튼에 표시될 텍스트. (아이콘만 표시할 때도 툴팁/접근성으로 사용됨) |
| `url` | `file`과 택 1 | 버튼을 눌렀을 때 WebView에 로드할 URL |
| `file` | `url`과 택 1 | 로컬 파일. 확장자로 이미지·동영상·페이지를 자동 판별. `assets/...`, `exdata/...`, 절대경로 지원 |
| `backgroundColor` | ✗ | 이미지 파일 배경색. 생략하면 `webViewBrightness`에 따라 밝은 화면은 흰색, 어두운 화면은 검정 계열 사용 |
| `icon` | ✗ | 아이콘 (자세한 형식은 [§6](#6-아이콘-사용)) |
| `selectedIcon` | ✗ | 선택 상태에서 표시할 아이콘. 생략하거나 비우면 `icon` 사용 |
| `showIcon` | ✗ | 아이콘 표시 재정의. 생략하면 테마 설정을 따르고, `false`는 경로를 보존한 채 감추며, `true`는 테마가 기본 감춤이어도 표시 |
| `hidden` | ✗ | `true`이면 이 메뉴를 툴바에서 숨김. 기본 `false` |
| `showTitle` | ✗ | `false` 면 아이콘만 표시 (기본 `true`) |
| `keepStateOnTap` | ✗ | 항목별 상태 유지 오버라이드. `null`(기본) 이면 `layout.keepStateOnTap` 값을 따른다. 자세한 동작은 [§5 keepStateOnTap](#keepstateontap--메뉴-상태-유지-동작) 참고 |

### 주의 사항

- `url`과 `file`을 동시에 지정할 수 없습니다. `file`의 이미지 확장자(`jpg`, `jpeg`,
  `png`, `gif`, `webp`, `bmp`)는 이미지로, 동영상 확장자(`mp4`, `mov`, `m4v`,
  `webm`, `mkv`, `avi`)는 동영상으로 표시하며 나머지는 로컬 페이지로 엽니다.
- WEB 관리자의 파일 관리에서 올린 파일은
  `"file": "exdata/media/intro.mp4"`처럼 지정하면 업데이트 후에도 유지됩니다.
- 이미지는 핀치로 `50%~300%` 확대·축소할 수 있습니다. 배율 변경 시 WebView와
  같은 확대 컨트롤이 표시되며 `25%` 단위 조절과 아이콘 더블클릭 `100%` 복원을
  지원합니다.
- **운영에서는 HTTPS 사용 권장.** HTTP도 동작하지만 보안/신뢰성 측면에서 HTTPS가 안전합니다.
- 메뉴는 위에서 아래(또는 왼쪽에서 오른쪽) 순서로 표시됩니다.
- 선택한 주제의 `defaultMenu` 항목이 **홈(기본 페이지)** 역할을 하며, 설정이 없으면 첫 번째 항목을 사용합니다.
- 메뉴별로 독립 WebView 가 생성되며, **한 번이라도 방문한 메뉴만 메모리에 살아있습니다** (방문 전엔 mount 되지 않음).
- 처음 방문하는 메뉴는 기존 화면을 유지한 채 백그라운드에서 준비하고 로딩 오버레이를
  표시합니다. 기본 문서가 표시 가능한 시점에 즉시 전환하며, 12초 이상 지연되면
  취소하거나 다시 시도할 수 있습니다.
- 한쪽 WebView 에서 로그인하면 같은 도메인의 다른 메뉴 WebView 에도 로그인 상태가 공유됩니다(쿠키/세션 공유).

### Android HTTP 사용

Android 9 이상은 평문 HTTP가 기본 차단입니다.
HTTP를 써야 한다면 `AndroidManifest.xml`의 `<application>`에:

```xml
android:usesCleartextTraffic="true"
```

또는 `networkSecurityConfig` 를 추가하세요.

---

## 5. 네비게이션 바 레이아웃

```json
"layout": {
  "brightness": "dark",
  "webViewBrightness": "light",
  "hideItemIcons": true,
  "hideTopicIcons": true,
  "navPosition": "bottom",
  "sideWidth": 230,
  "barHeight": 102,
  "breakpoint": 720,
  "buttonHeight": 0,
  "buttonWidth": 0,
  "buttonGap": 10,
  "buttonAlignment": "stretch",
  "showHistoryButtons": true,
  "showKeyboardToggle": true,
  "showSelectedTopic": true,
  "selectedTopicLabelColor": "#f8fafc",
  "keepStateOnTap": false,
  "toolbarInitiallyHidden": true,
  "toolbarAutoHideSec": 10
}
```

### 옵션 표

아래 기본값은 현재 배포되는 `menu.defaults.json` 기준입니다.

| 키 | 타입 | 기본값 | 설명 |
|----|------|--------|------|
| `brightness` | `light` / `dark` | `dark` (생략 시 `light`) | 테마의 밝은(White)·어두운(Dark) 계열 지정 |
| `webViewBrightness` | `light` / `dark` | `light` | WebView 페이지의 `prefers-color-scheme`. 테마 `brightness`와 독립 |
| `hideItemIcons` | bool | `true` | 개별 `showIcon`이 없는 메뉴의 아이콘을 기본적으로 감춤 |
| `hideTopicIcons` | bool | `true` | 주제 선택 버튼의 아이콘을 기본적으로 감춤. 주제별 `showIcon: true/false`로 표시 여부 재정의 |
| `navPosition` | `auto`\|`left`\|`right`\|`top`\|`bottom` | `right` | 네비 위치. `auto`는 화면 폭에 따라 자동 |
| `sideWidth` | 숫자 > 0 | `230` | `left`/`right`일 때 사이드 폭(dp) |
| `barHeight` | 숫자 > 0 | `102` | `top`/`bottom`일 때 바 높이(dp) |
| `breakpoint` | 숫자 > 0 | `720` | `auto` 모드의 임계 폭. 이 이상이면 좌측, 미만이면 하단 |
| `buttonHeight` | 숫자 ≥ 0 | `0` | 버튼 높이(dp). `0`=자동 |
| `buttonWidth` | 숫자 ≥ 0 | `0` | 하단/상단 모드 버튼 폭. `0`=균등 분배 |
| `buttonGap` | 숫자 ≥ 0 | `10` | 버튼 사이 간격(dp) |
| `buttonAlignment` | 문자열 | `stretch` | 정렬 방식 (아래 표) |
| `showHistoryButtons` | bool | `true` | 하단 기능 버튼 묶음의 가장 앞에 WebView ←/→ 버튼 표시 |
| `showKeyboardToggle` | bool | `true` | 네비 **끝점** 에 OS 가상 키보드 토글 버튼 표시 ([§9](#9-가상-키보드) 참고) |
| `showSelectedTopic` | bool | `true` | 현재 주제 제목을 표시하며 클릭하면 현재 언어의 주제 선택 화면으로 이동 |
| `selectedTopicLabelColor` | color | `#f8fafc` | 클릭 가능한 현재 주제 제목의 글자색 |
| `windowsKioskLockdown` | bool | `false` | Windows 사이니지 표시 중 앱 전환·셸 단축키 차단. 기본적으로 사용하지 않음 |
| `windowsKioskShortcuts` | object | 모두 `true` | 잠금 중 차단할 키와 키 조합을 개별 선택 |
| `windowsDisableEdgeSwipe` | bool | `true` | 전체화면 가장자리 스와이프로 작업 표시줄 등 시스템 UI가 열리는 동작 차단 |
| `windowsAlwaysOnTop` | bool | `false` | 사이니지 창을 다른 일반 창보다 항상 위에 유지 |
| `windowsPreventScreenSaver` | bool | `true` | 사이니지 표시 중 Windows 화면보호기 실행 방지 |
| `windowsPreventDisplaySleep` | bool | `true` | 사이니지 표시 중 Windows 화면 자동 끄기 방지 |
| `keyboardMode` | `windows` / `builtin` | `windows` | Windows 화면 키보드 또는 앱 내장 키보드 선택 |
| `keepStateOnTap` | bool | `false` | 같은 메뉴 단일 탭 시 페이지 상태 유지 (아래 [keepStateOnTap](#keepstateontap--메뉴-상태-유지-동작) 참고) |
| `toolbarInitiallyHidden` | bool | `false` | 앱 시작 시 툴바를 감춘 상태로 표시 |
| `toolbarAutoHideSec` | 숫자 ≥ 0 | `0` | 복원한 툴바를 입력 없이 표시할 시간(초). `0`이면 자동 숨김 해제 |
| `barColor` | 색상 문자열 | `#000000` | 툴바 배경색. 웹 관리자의 색상 선택기에서 변경 가능 |
| `buttonColor` | 색상 문자열 | `#171717` | 비선택 버튼 배경색 |
| `buttonForegroundColor` | 색상 문자열 | `#ffffff` | 비선택 버튼 텍스트/아이콘 색 |
| `selectedButtonColor` | 색상 문자열 | `#facc15` | 선택된 버튼 배경색 |
| `selectedButtonForegroundColor` | 색상 문자열 | `#000000` | 선택된 버튼 텍스트/아이콘 색 |

`windowsKioskShortcuts`에서는 `windowsKey`, `altTab`, `altEscape`, `altF4`,
`altSpace`, `ctrlEscape`, `ctrlShiftEscape`, `launchApp1`, `launchApp2`,
`launchMail`, `browserHome`, `browserSearch`, `browserFavorites`를 각각
`true`(차단) 또는 `false`(허용)로 지정할 수 있습니다. `windowsKey`는 시작 메뉴와
`Win+Tab`, `Win+D`, `Win+R` 등 모든 Windows 키 조합에 함께 적용됩니다.
상위 `windowsKioskLockdown`이 꺼져 있으면 개별 설정은 적용되지 않습니다.
`windowsDisableEdgeSwipe`는 키 차단과 독립적으로 동작하며, 사이니지를 감추거나
종료하면 자동으로 해제됩니다. 화면 가장자리에서 시작하는 Windows 시스템
제스처만 차단하며 페이지 안쪽에서 시작하는 스크롤·드래그에는 영향을 주지 않습니다.
비상 종료용 `Ctrl+Alt+Shift+F4`와 Windows 보안 화면 `Ctrl+Alt+Del`은 안전을 위해
이 설정으로 차단하지 않습니다.

### `keepStateOnTap` — 메뉴 상태 유지 동작

- `false`(기본): 메뉴 버튼을 누를 때마다 해당 메뉴에 설정된 URL로 이동합니다.
- `true`: 다른 메뉴에서 돌아올 때 기존 스크롤과 내부 페이지 상태를 유지합니다. 이미 선택된
  메뉴를 한 번 누르면 아무 동작도 하지 않고, 300ms 이내에 두 번 누르면 설정된 URL을
  강제로 다시 불러옵니다.
- 각 `items[]`의 `keepStateOnTap` 값이 있으면 `layout.keepStateOnTap`보다 우선합니다.

### 색상 문자열 형식

대소문자 무관, `#` 선택. 다음 형식 지원:

| 형식 | 예시 | 의미 |
|------|------|------|
| `#RGB` | `#f00` | 짧은 표현 = `#ff0000` |
| `#RRGGBB` | `#1976d2` | 불투명 RGB |
| `#AARRGGBB` | `#801976d2` | 알파 + RGB (`80` ≈ 50% 투명) |
| `transparent` | `transparent` | 완전 투명 |

미지정(`null`/생략) 시 시스템 테마(Material 3)의 기본 색을 사용합니다.

### `buttonAlignment` 값

| 값 | 동작 |
|----|------|
| `stretch` | (하단/상단 기본) `buttonWidth=0` 일 때 균등 분배. 사이드에서는 `start`로 동작 |
| `start` | 위/왼쪽으로 모음 |
| `center` | 가운데 정렬 |
| `end` | 아래/오른쪽으로 모음 |
| `spaceBetween` | 양 끝에 붙이고 사이 균등 |
| `spaceAround` | 항목 좌우(상하)에 같은 여백 |
| `spaceEvenly` | 항목 사이 + 양 끝 모두 균등 |

### 예시

**49인치 가로 사이니지 — 좌측 큰 사이드**
```json
"layout": {
  "navPosition": "left",
  "sideWidth": 280,
  "buttonHeight": 96,
  "buttonGap": 12,
  "buttonAlignment": "start",
  "showHistoryButtons": true
}
```

**세로 모바일 — 하단 균등 분배**
```json
"layout": {
  "navPosition": "bottom",
  "barHeight": 110,
  "buttonAlignment": "stretch",
  "showHistoryButtons": false
}
```

**하단 바에 고정 폭 + 가운데 정렬**
```json
"layout": {
  "navPosition": "bottom",
  "barHeight": 120,
  "buttonHeight": 100,
  "buttonWidth": 160,
  "buttonGap": 16,
  "buttonAlignment": "center"
}
```

---

## 6. 아이콘 사용

`icon`과 `selectedIcon` 필드에는 3가지 형식이 가능합니다. `selectedIcon`은
선택 사항이며 지정하지 않으면 선택 상태에서도 `icon`을 사용합니다.

### A. Material 아이콘 (권장)

별도 파일이 필요 없습니다.

```json
"icon": "icon:home"
```

사용 가능한 키 목록 (`lib/widget/material_icon_registry.dart`):

```
home, notice, announcement, gallery, photo, video, movie, info,
church, menu, list, calendar, event, mail, phone, map, location,
settings, book, document, news, people, group, star, favorite,
search, help, link, web, music, mic, camera, image, download, qr
```

새 아이콘이 필요하면 위 파일의 `_icons` 맵에 한 줄 추가하면 됩니다.

### B. 로컬 이미지 파일

```json
"icon": "assets/icons/custom.png"
```

- 파일을 `assets/icons/` 폴더에 넣고
- 권장 크기: **96×96px** 이상 정사각형, 투명 배경
- `pubspec.yaml` 의 `assets/icons/` 가 이미 등록되어 있어 자동으로 포함됨

확장자를 생략하면 같은 이름의 아이콘 패밀리에서 테마의 `brightness`에
맞는 파일을 자동 선택합니다.

```json
"icon": "assets/icons/custom"
```

- `dark`: `custom-white.*` 우선
- `light`: `custom-black.*` 우선
- 우선 변형이 없으면 `custom-color.*`, `custom.*`, 반대 명암 변형 순으로 대체
- 검색 확장자: `png`, `jpg`, `jpeg`, `webp`, `bmp`, `gif`
- `custom.png`처럼 확장자를 명시하면 자동 선택 없이 지정한 파일만 사용

### C. 네트워크 이미지

```json
"icon": "https://example.com/icon.png"
```

- 네트워크 장애 시 깨진 이미지 표시. **로컬 에셋 권장.**

### 아이콘만 표시(텍스트 숨김)

```json
{
  "id": "home", "title": "홈",
  "url": "...", "icon": "icon:home",
  "showTitle": false
}
```

`title` 은 툴팁/스크린리더 라벨로 사용됩니다.

### 선택 상태 아이콘 변경

```json
{
  "id": "home",
  "title": "홈",
  "url": "https://example.com",
  "icon": "assets/icons/home.png",
  "selectedIcon": "assets/icons/home-selected.png"
}
```

메뉴가 선택되면 `selectedIcon`을 표시하고, 선택이 해제되면 다시 `icon`을 표시합니다.

---

## 7. 대기화면(Idle Screen)

무인 운영을 위한 핵심 기능입니다.
- **콜드 스타트** 시 자동 진입
- 일정 시간 **무입력** 시 자동 진입
- 화면 어디든 터치 → 사라지고 **첫 메뉴(홈)로 리셋**

### 공통 옵션

```json
"idle": {
  "enabled": true,
  "timeoutSec": 60,
  "startOnLaunch": true,
  "modes": ["slideshow"],
  "showHint": true,
  "hintText": "화면을 터치해 주세요"
}
```

아래 기본값은 현재 배포되는 `menu.defaults.json` 기준입니다.

| 키 | 기본값 | 설명 |
|----|--------|------|
| `enabled` | `true` | 대기화면 사용 여부 |
| `timeoutSec` | `300` | 무입력 → 대기화면 진입까지의 초. `0` 이면 무입력 진입 안 함 |
| `startOnLaunch` | `true` | 앱 시작 시 즉시 대기화면을 띄울지 |
| `modes` | `["gallery"]` | 표시 콘텐츠 배열. `slideshow`, `folder`, `gallery`는 복수 지정 가능 |
| `mode` | `none` | 기존 단일 모드 호환 설정. `modes`가 있으면 `modes` 우선 |
| `showHint` | `true` | "화면을 터치해 주세요" 안내 배지 표시 |
| `hintText` | `화면을 터치해 주세요` | 안내 문구 |
| `hintFontSize` | `40` | 안내 글자 크기(px), 12~96 |
| `hintPaddingHorizontal` | `40` | 안내 버튼 좌우 여백(px), 0~120 |
| `hintPaddingVertical` | `24` | 안내 버튼 위아래 여백(px), 0~120 |
| `hintBackgroundColor` | `#FACC15` | 안내 버튼 배경색, 기본 노란색 |
| `hintTextColor` | `#171717` | 안내 글자색, 기본 짙은 회색 |

WEB 관리자 **사이니지 구성 → 화면 보호기**에서 터치 안내의 크기와 색상을 변경하고
**저장 후 즉시 적용**할 수 있습니다. 좁은 화면에서는 버튼 전체가 화면 폭에 맞게 축소됩니다.
색상은 `#RGB`, `#RRGGBB`, 투명도를 포함한 `#AARRGGBB`, `transparent` 형식입니다.

### A. 단일 이미지

```json
"idle": {
  "enabled": true, "timeoutSec": 60, "mode": "image",
  "image": "assets/idle/welcome.jpg"
}
```

### B. 슬라이드쇼 (이미지·동영상 리스트)

```json
"idle": {
  "enabled": true, "timeoutSec": 60, "mode": "slideshow",
  "slideshow": {
    "intervalSec": 6,
    "transition": "fade",       // "fade" | "none"
    "images": [
      "assets/idle/slide1.jpg",
      "assets/idle/event.mp4",
      "assets/idle/slide3.jpg"
    ]
  }
}
```

- 지원 동영상 확장자: `.mp4 .mov .m4v .webm .mkv .avi`
- YouTube의 `youtu.be`, `watch`, `embed`, `shorts`, `live` 주소도 사용할 수 있습니다.
- YouTube 영상은 소리와 함께 자동재생되며, 종료되면 다음 슬라이드로 이동합니다.
- 동영상은 자체 재생 시간이 끝나면 다음 슬라이드로 이동합니다. 항목이 하나뿐이면 반복 재생합니다.
- 에셋, 로컬 파일 및 `http(s)` 동영상 주소를 사용할 수 있습니다.
- Windows에서는 설치된 미디어 코덱과 파일 내부 인코딩의 호환성이 필요하며 `.mp4(H.264/AAC)`를 권장합니다.

### C. 폴더 자동 순회 (이미지 + 동영상 혼합)

가장 유연한 모드. 폴더에 파일만 넣으면 자동으로 발견·재생.

```json
"idle": {
  "enabled": true, "timeoutSec": 60, "modes": ["folder"],
  "folder": {
    "paths": ["assets/idle/", "C:/kiosk_media"],
    "intervalSec": 8,
    "shuffle": false,
    "includeImages": true,
    "includeVideos": true,
    "transition": "fade"
  }
}
```

| 키 | 기본값 | 설명 |
|----|--------|------|
| `paths` | 필수 | 폴더 경로 배열. 에셋과 OS 절대 경로를 함께 지정 가능 |
| `path` | - | 기존 단일 폴더 호환 설정. `paths`가 있으면 `paths` 우선 |
| `intervalSec` | `8` | 이미지 1장당 표시 시간(초). 동영상은 끝까지 재생 후 다음 |
| `shuffle` | `false` | `true`면 매 진입마다 무작위 순서 |
| `includeImages` | `true` | 이미지 포함 (`.jpg .jpeg .png .gif .webp .bmp`) |
| `includeVideos` | `true` | 동영상 포함 (`.mp4 .mov .m4v .webm .mkv .avi`) |
| `transition` | `fade` | 이미지 전환 효과 |

**경로 예시**
- 에셋: `"assets/idle/"`
- Windows: `"C:/kiosk_media"`
- Android: `"/storage/emulated/0/kiosk_media"` (권한 필요, 아래 참고)
- macOS: `"/Users/kiosk/Pictures/signage"`
- 웹: **에셋만 가능** (파일시스템 접근 불가)

**Android 외부 폴더 사용 시 권한** (`AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
                 android:maxSdkVersion="32"/>
```

**Windows 코덱**: WMP에서 재생되는 형식은 모두 지원. `.mp4(H.264)` 권장.
일부 형식이 안 된다면 [K-Lite Codec Pack](https://codecguide.com/) 설치.

### D. 포토갤러리 게시물

웹 포토갤러리의 최신 게시물을 읽어 게시물 본문의 원본 사진을 순환 표시합니다.
사진 하단에는 해당 게시물 제목이 그라데이션 오버레이로 표시됩니다.

```json
"idle": {
  "enabled": true,
  "timeoutSec": 300,
  "startOnLaunch": true,
  "modes": ["gallery"],
  "gallery": {
    "urls": [
      {
        "url": "http://ycatholic.or.kr/bbs/board.php?bo_table=gallery",
        "lookbackDays": 30,
        "minPosts": 2,
        "maxPosts": 4
      },
      {
        "url": "https://example.com/second-gallery",
        "lookbackDays": 7,
        "minPosts": 1,
        "maxPosts": 2
      }
    ],
    "intervalSec": 8,
    "refreshIntervalMin": 5,
    "shuffle": false,
    "maxImages": 40,
    "transition": "fade"
  },
  "showHint": true,
  "hintText": "화면을 터치해 주세요"
}
```

| 키 | 기본값 | 설명 |
|----|--------|------|
| `urls` | 필수 | 갤러리 주소별 `url`, `lookbackDays`, `minPosts`, `maxPosts` 설정 배열. 기존 URL 문자열 배열도 계속 지원 |
| `url` | - | 기존 단일 게시판 호환 설정. `urls`가 있으면 `urls` 우선 |
| `intervalSec` | `8` | 사진 한 장을 표시할 시간(초) |
| `lookbackDays` | 미지정 | 기존 문자열 주소의 공통값. 새 설정에서는 `urls`의 주소 객체마다 지정 |
| `minPosts` | `1` | 기존 문자열 주소의 공통값. 새 설정에서는 `urls`의 주소 객체마다 지정 |
| `refreshIntervalMin` | `5` | 실행 중 게시판을 다시 확인하는 주기(분) |
| `shuffle` | `false` | `true`이면 미리 만든 무작위 순서로 사진을 순회 |
| `maxPosts` | `4` | 기존 문자열 주소의 공통값. 새 설정에서는 `urls`의 주소 객체마다 지정 |
| `maxImages` | `40` | 한 번에 순환할 최대 사진 수 |
| `transition` | `fade` | 사진 전환 효과 (`fade` / `none`) |

- 목록 썸네일 대신 각 게시물 본문의 원본 이미지 링크를 우선 사용합니다.
- 각 `urls` 항목의 `lookbackDays: 30`은 해당 주소에서 갱신 시각 기준 정확히 30일 전까지의 게시물을 선택합니다.
- `lookbackDays`를 생략하면 기존처럼 최신 게시물을 `maxPosts`개까지 읽습니다.
- 주소별 기간 조건에 맞는 게시물이 `minPosts`보다 적거나 없으면 해당 주소의 최신 게시물로 `minPosts`개까지 보충합니다.
- 5분 갱신 시 현재 사진의 URL과 재생 위치를 유지하므로 슬라이드가 처음부터 다시 시작되지 않습니다.
- 갱신에 실패하면 현재 재생 목록을 유지하고 다음 주기에 다시 시도합니다.
- 키보드 `←` / `→` 또는 화면 좌우 스와이프로 이전·다음 사진을 볼 수 있습니다.
- 화면을 탭하면 보호기가 종료되며, 다시 진입하면 마지막 사진과 재생 순서부터 이어집니다.
- 랜덤 모드에서도 갱신할 때 기존 무작위 순서는 유지하고 새 사진만 순서에 추가합니다.
- 각 주소의 `minPosts`는 같은 주소의 `maxPosts`보다 클 수 없습니다.
- 게시물 하나에 사진이 여러 장이면 모든 사진에 같은 게시물 제목이 표시됩니다.
- 개별 게시물 읽기에 실패하면 해당 목록 썸네일로 대체합니다.
- 게시판 전체를 읽지 못하면 안전 화면을 표시하며 터치로 정상 화면에 복귀할 수 있습니다.
- 현재 파서는 그누보드 갤러리의 `.card`, `.bo_tit`, `#bo_v_con` 구조를 기준으로 합니다.
  사이트 스킨 구조가 바뀌면 파서도 함께 수정해야 합니다.

### E. 복수 모드 조합

`slideshow`, `folder`, `gallery`는 함께 지정할 수 있으며 배열 순서대로 각 소스의
콘텐츠를 하나의 재생 목록으로 합칩니다. 폴더 동영상은 끝까지 재생한 후 다음 항목으로 이동합니다.

```json
"idle": {
  "enabled": true,
  "modes": ["slideshow", "folder", "gallery"],
  "slideshow": { "images": ["assets/idle/welcome.jpg"] },
  "folder": { "paths": ["C:/kiosk_media", "D:/event_media"] },
  "gallery": {
    "urls": ["https://example.com/gallery-a", "https://example.com/gallery-b"]
  }
}
```

- `url` 모드는 반드시 단독으로만 지정해야 합니다.
- `image`, `none`도 복수 모드 조합에는 사용할 수 없습니다.
- 슬라이드쇼·미디어 폴더·갤러리·복수 모드는 키보드 `←` / `→`와 화면 좌우
  스와이프로 이전·다음 항목을 이동할 수 있습니다. 단순 탭은 화면보호기를 종료합니다.
- 이전 형식인 문자열 `mode`, `folder.path`, `gallery.url`도 계속 지원합니다.

### F. URL 풀스크린

특정 웹페이지(슬라이드 호스팅, 외부 사이니지 시스템 등)를 풀스크린으로 표시.

```json
"idle": {
  "enabled": true, "timeoutSec": 60, "mode": "url",
  "url": "https://example.com/attract"
}
```

- 페이지 내부 링크 클릭도 모두 dismiss 처리(콘텐츠 고정).
- YouTube 주소를 입력하면 일반 웹페이지 대신 전용 플레이어로 소리 포함 자동재생하며 반복합니다.

---

## 8. 뒤로 / 앞으로 컨트롤

`layout.showHistoryButtons: true` 로 활성화합니다.

### 동작 규칙

- **메뉴 클릭** = 히스토리 리셋 (새 탭처럼)
- 페이지 내 **링크 클릭** 만 히스토리에 추가됨
- ←/→ 는 **현재 메뉴 안에서만** 동작
- 갈 수 없는 방향은 자동으로 비활성(흐릿)

예시:
```
홈 메뉴 클릭          → [홈]
홈 페이지 내 링크 클릭 → [홈, 글A]
글A 내 다른 링크 클릭 → [홈, 글A, 글B]
← 클릭               → 글A 표시
공지 메뉴 클릭        → [공지]   ← 히스토리 리셋
```

이 동작은 사이니지에서 사용자가 헤맬 가능성을 최소화합니다.

---

## UI 글꼴 설정

웹 관리자 **레이아웃 → UI 글꼴** 또는 `layout.fontFamily`에서 글꼴 이름을
지정합니다. 실행 파일 기준 `fonts` 폴더의 외부 TTF/OTF가 가장 우선하고,
패키지 글꼴, Windows 시스템 글꼴, Flutter 기본 글꼴 순서로 폴백합니다.

포함된 패키지 글꼴 이름은 `Pretendard`, `NanumSquare`, `NanumGothic`,
`NanumBrush`, `KoPubDotum`, `Catholic`, `MuseumClassic`(박물관체),
`Seoul`(서울남산체), `SeoulHangang`(서울한강체)입니다. `박물관체`, `서울체`,
`서울남산체`, `서울한강체`도 설정 이름으로 사용할 수 있습니다. 빈 값은
Flutter 기본 글꼴입니다.
가톨릭체는 개인과 가톨릭 교회기관의 비영리·사목 목적에만 사용해야 합니다.

- 전체 UI: `layout.fontFamily`
- 툴바 전체: `layout.menuFontFamily`
- 개별 툴바 메뉴: `languages[].topics[].items[].fontFamily`
- 언어 선택 화면 전체: `languageSelection.fontFamily`
- 개별 언어 버튼: `languages[].fontFamily`

개별 설정이 없으면 화면 전체 설정을, 화면 전체 설정도 없으면 전체 UI 설정을
상속합니다. 웹 관리자에서도 같은 항목을 편집할 수 있습니다.

## 9. 가상 키보드

Windows에서는 기본적으로 Windows 화상 키보드를 사용합니다. **사이니지 구성 >
레이아웃 > 키보드 방식**에서 `내장 키보드`로 변경할 수 있습니다. Windows 키보드를
실행할 수 없는 환경에서는 Flutter 내장 키보드가 자동으로 표시됩니다.

### 특징

- 반복 표시·감춤과 실제 창 상태 확인을 지원하는 Windows 화상 키보드 호출
- 설정에서 Windows 키보드와 Flutter 내장 키보드 선택
- **한글 두벌식 자모 조합** (초성/중성/종성, 이중 모음, 겹받침 포함)
- 영문 QWERTY / 숫자·특수문자 모드 토글
- Shift 단일 입력 / 잠금 / 해제 (한 번 탕 → 다음 글자만 적용, 두 번 탕 → 잠금, 세 번 탕 → 해제)
- 함들을 드래그해 화면 어디에나 이동 가능한 **플로팅 윈도우**
- 앱 설정 입력 폼과 WebView 내 `<input>` / `<textarea>` / `[contenteditable]`
  (iframe 포함) 포커스 시 자동 표시
- 네비게이션 바의 키보드 토글 버튼(`layout.showKeyboardToggle: true`) 으로 수동 호출 가능
- 한글 조합 결과를 페이지의 활성 요소에 주입하고 `input`/`change` 이벤트를 디스패치 → 검색창/폼/로그인 모두 정상 동작

### 구조

```
┌─────────────────────────────────────────────────┐
│ [✥] 가상 키보드                       [✕] │  ← 함들(드래그) + 닫기
├─────────────────────────────────────────────────┤
│  ㅎ  ㅈ  ㄷ  ㄱ  ㅅ  ㅛ  ㅕ  ㅑ  ㅐ  ㅔ  │
│  ㅁ  ㄴ  ㅇ  ㄹ  ㅎ  ㅗ  ㅓ  ㅏ  ㅣ       │
│  ㅋ  ㅌ  ㅊ  ㅍ  ㅠ  ㅜ  ㅡ             │
│ [⇧][EN][!#1][   space   ][⌫][↵]              │
└─────────────────────────────────────────────────┘
```

### 추가 언어 레이아웃

`lib/widget/virtual_keyboard.dart` 의 `_KbMode` 엔서다는 값을 추가하고
`_rows` 게터에 해당 모드의 구성을 넘먴건게 높이면 됩니다. 한글은 자모
조합이 필요하므로 [HangulComposer](../lib/service/hangul_composer.dart) 같은 조합기를
해당 언어에 맞게 추가하면 됩니다.

---

## 10. 자동 복구 / 세션 위생

### 자동 복구 루틴 (무인 운영)

| 상황 | 동작 |
|---|---|
| 페이지 로드 에러 시 | 5초 카운트다운 후 자동 재시도 |
| 3회 연속 실패 | WebView 위젯을 통째로 재생성 + 홈으로 복귀 |
| 렌더러 프로세스 종료/응답없음 | 즉시 위젯 재생성 |
| Alt+F4 등으로 WebView2 자식창만 닫힘 | JS heartbeat (4초 도착 없음) 감지 → 자동 재생성 |
| 메뉴 클릭 후 12초 내 응답 없음 | WebView 재생성, 사용자가 가려던 URL 로 이동 |
| 메뉴 JSON 로드 실패 | 5초 후 자동 재시도 (반복) |

### WebView 데이터 정책

모든 메뉴 WebView는 동일한 WebView 프로필을 사용하므로 쿠키, 캐시와 Local Storage가
공유됩니다. 웹 관리자의 **WebView 데이터**에서 화면보호기 진입 시 정책을 선택합니다.

- `keep`: 쿠키·캐시·Local Storage를 모두 유지
- `cookiesOnly`(기본): 쿠키만 삭제하고 캐시·Local Storage는 유지
- `allSiteData`: 쿠키·캐시·Local Storage·IndexedDB 등 사이트 데이터 전체 삭제

쿠키 동의만 기억시키려면 `preserveCookies`에 `도메인|쿠키이름`을 지정합니다. 예를 들어
`example.com|CookieConsent`는 `example.com`과 그 하위 도메인의 이름이 정확히
`CookieConsent`인 쿠키만 남깁니다. 쿠키 이름은 대소문자를 구분합니다.

`preserveDomains`에 `catholic.or.kr`처럼 지정하면 해당 도메인과 하위 도메인의 **모든
쿠키**가 남아 로그인 세션도 유지될 수 있습니다. 꼭 필요한 경우에만 사용하세요.
`preserveCookies`는 `cookiesOnly` 정책에만 적용되며, 프로그램 시작 시에는 데이터를
임의로 삭제하지 않습니다.

### 메모리 정리 (대기화면 진입 시)

메뉴별로 독립 된 WebView 가 생성되므로, 대기화면 진입 시점에
**홈(`defaultMenu`) 이외의 모든 WebView 마운트를 해제**해 WebView2 인스턴스를 회수합니다.
다음 사용자가 다른 메뉴를 누르면 그 시점에 새로 mount 됩니다.

Windows에서는 툴바로 다른 메뉴를 선택해 화면 뒤로 간 WebView도 `pause()` 상태로 전환하고,
다시 선택하면 `resume()`합니다. 같은 WebView 인스턴스를 유지하므로 스크롤·페이지 상태는
그대로이며, 백그라운드 JavaScript·미디어는 선택할 때까지 일시 중지될 수 있습니다.

---

## 11. 운영 팁

### 기능키

- `F1`: 프로그램 안에서 사용자 매뉴얼 팝업 표시
- `F12`: 프로그램·Updater 버전과 GitHub 정보 표시
- `F9`: 업데이트 확인 후 사용자 동의 시 다운로드, 설치 및 자동 재시작

### Windows 업데이트와 실패 복구

- 자동 업데이트는 기본 OFF입니다. 관리자가 켜면 앱 시작 직후 stable Release를 확인하고
  새 버전이 있으면 즉시 설치를 시도합니다. 이후 확인 주기와 설치 시간대·유휴 설치 조건은
  업데이트 정책을 따릅니다.
- 설정의 **지금 업데이트 확인 / 지금 설치**, WEB 관리자와 `F9`는 수동 요청입니다. 수동
  설치는 같은 대상 버전에서 이전에 누적된 3회 실패 차단을 무시하고 매번 다시 시도합니다.
- 자동 설치가 같은 대상 버전에서 3회 실패하면 반복 실행을 막기 위해 차단합니다. Release의
  대상 버전이 바뀌거나 첫 실패 시각부터 24시간이 지나면 실패 횟수와 시간 창을 모두
  초기화하고 정상 자동 설치 절차를 다시 시작합니다.
- 수동 설치에서 네이티브 Updater가 실패하면 `update-state.json`의 실제 실패 사유를
  표시하고 **Setup으로 업데이트**할지 묻습니다. 승인한 경우에만 같은 GitHub Release의
  Setup EXE를 다운로드하고 Release 자산 SHA-256을 검증한 뒤 실행합니다. 거절하면
  다운로드하지 않으며, 자동 업데이트에서는 Setup을 실행하지 않습니다.
- 설정 화면의 업데이트 상태는 마우스로 선택·복사할 수 있습니다. 문제를 신고할 때는
  **진단 정보로 이슈 등록**을 사용하면 추가 입력·확인 없이 시스템 정보,
  최근 로그와 업데이트 상태를 수집해 GitHub 이슈를 바로 등록합니다.
- Windows에서 업데이트 HTTPS 인증서 검증이 실패하면 Windows 인증서 저장소와 SSL
  정책으로 서버 인증서를 다시 검증합니다. 검증에 성공한 인증서·서버 주소·포트에만
  재시도를 허용하며, 인증서 신뢰·유효기간·서버 주소·폐기 확인을 생략하지 않습니다.
  브라우저에서는 다운로드되지만 구버전 앱에서 `CERTIFICATE_VERIFY_FAILED`가 발생하면
  이 수정이 포함된 Setup을 브라우저로 다운로드해 한 번 수동 설치해야 합니다.
- GitHub 비인증 API의 공인 IP당 시간당 요청 한도가 소진되어 403/429가 발생하면 API를
  사용하지 않는 공개 Release 경로로 자동 전환합니다. 여러 PC가 같은 인터넷 회선을
  사용해도 API 한도 때문에 업데이트 확인이 중단되지 않습니다.

웹 관리자 **실행 상태 → ZIP 강제 업데이트**에서 릴리스 페이지의
`simple-kiosk-windows-버전.zip`을 선택하고 **ZIP 업로드**를 누릅니다.
업로드한 버전을 확인한 뒤 **이 ZIP으로 강제 업데이트**를 누르면 설치와 재시작을
진행합니다. Source code ZIP과 Setup EXE는 이 기능에서 사용하지 않습니다.
최대 2GB이며 원격 연결에서도 작은 조각으로 나누어 업로드합니다.
GitHub 접속 없이 같은 버전 재설치와 이전 버전 설치를 요청할 수 있습니다.
패키지 구성·경로와 설치 전 ZIP 무결성을 검사하고, 기존 설치 폴더는 복구용으로 보존합니다.
업로드한 ZIP의 출처는 관리자에게 맡기며, 계산한 SHA-256은 업로드 이후 파일 변조 검사에 사용합니다.

### Windows 시스템 트레이

- 프로그램 실행 중 Windows 알림 영역에 **여의도성당Signage** 트레이 아이콘이 표시됩니다.
- 프로그램을 다시 실행하면 트레이에 숨은 기존 인스턴스도 완전히 종료한 뒤 새 인스턴스를
  시작합니다. 기존 프로세스가 응답하지 않으면 해당 PID만 강제 종료하며, 두 인스턴스를
  동시에 실행하지 않습니다. 구버전에서 처음 교체하는 경우에도 실행 파일명이 같은 기존
  프로세스를 찾아 종료합니다.
- 기본 Windows 키오스크 잠금에서는 사이니지 창을 항상 위에 유지하고 `Alt+Tab`, `Alt+F4`,
  Windows 키 조합과 작업 관리자 단축키를 차단합니다. 사이니지를 감추면 잠금이 해제됩니다.
- 트레이 아이콘을 클릭하면 메뉴가 즉시 열립니다.
- 트레이 메뉴에서 **사이니지 보이기**, **사이니지 감추기**, **사이니지 재시작**, **웹관리자 열기**, **설정**, **사용자 매뉴얼**, **완전 종료**를 선택할 수 있습니다.
- 리버스 포워딩의 현재 상태가 트레이 메뉴에 `연결됨` 또는 `연결 안 됨`으로 표시됩니다.
  실제 포워딩 확인이 완료된 연결 상태에서는 녹색 점등 아이콘과 외부 WEB 관리자 주소가
  함께 표시되며, 그 외 상태에는 회색 소등 아이콘이 표시됩니다.
- **설정**은 기존과 동일하게 관리자 PIN 인증 후 열립니다.
- 프로그램을 완전히 끝내려면 설정 화면 하단 또는 트레이 메뉴의 **완전 종료**를 사용합니다.
- 화면이 투명하거나 먹통이 되어 정상 종료할 수 없다면 화면의 왼쪽 위와 오른쪽 위 모서리를
  동시에 8초간 계속 누르거나 `Ctrl+Alt+Shift+F4`를 3초간 눌러 네이티브 경로로 강제
  종료할 수 있습니다. 한쪽 터치를 떼거나 모서리 밖으로 이동하면 8초 대기는 취소됩니다.
  최후 수단으로만 사용하세요.

### Windows 최초 실행 필수 구성요소

- installer와 포터블 ZIP에는 앱 실행에 필요한 Visual C++ Runtime DLL이 포함됩니다.
- installer와 `InstallPrerequisites.cmd`는 Microsoft Visual C++ Redistributable을 자동 설치하거나 업데이트합니다.
- installer는 Microsoft Edge WebView2 Runtime을 확인하고 없으면 자동 설치합니다.
- 포터블 ZIP을 새 PC에서 사용할 때 WebView2가 없으면 `InstallPrerequisites.cmd`를 먼저 실행하세요.
- WebView2 자동 설치에는 인터넷 연결이 필요합니다.

### 원격 관리자 페이지와 API

- 프로그램의 **설정 > 관리 API / 관리자 페이지**에서 사용 여부와 포트를 지정합니다. 기본 포트는 `80`입니다.
- **원격 WEB 관리자 연결**은 기본으로 켜집니다. 앱에 포함된 접속 전용 SSH 키로 GW에
  연결하고 `/run/signage/ysignage1.sock`부터 사용 가능한 ID를 찾습니다. 연결에 성공한
  ID는 `config/admin-api.json`에 저장되어 다음 접속 때 먼저 사용됩니다. 저장된 ID가
  거절되면 자동 배정 모드에서는 다시 `ysignage1`부터 사용 가능한 ID를 찾아 저장값을 갱신합니다.
- 앱 설정의 **원격 접속 ID 고정** 또는 웹 관리자 **관리 API 설정 → ID 지정 방식 → 수동 고정**에서
  `yeouido`, `church-lobby`처럼 ID를 직접 입력하고 관리 API 설정을 저장할 수 있습니다.
  영문·숫자·하이픈 1~63자를 허용하며 처음과 끝은 영문 또는 숫자여야 합니다. 대문자는 소문자로 저장합니다.
  고정 여부(`webAdminSshForwardingIdFixed`)와 ID는 버전 폴더 밖의
  `config/admin-api.json`에 저장하여 재시작·업데이트 후에도 유지합니다.
  설정 백업 가져오기와 직전 설정 복원도 해당 PC의 고정 ID를 보존합니다.
  고정 ID 배정이 중복 등으로 거절되면 `church-lobby-1`, `church-lobby-2`처럼 번호를 붙여
  시도합니다. 이미 `church-lobby-2`라면 다음 후보는 `church-lobby-3`이며 번호를 중첩하지 않습니다.
  번호를 붙여 63자를 넘게 되면 이름 끝부분을 줄여 길이를 맞춥니다.
  성공한 ID를 저장하고 다음 연결에서 먼저 사용합니다. SSH 접속·인증 등 일반 연결 오류는
  저장된 ID로 재시도하며 번호를 변경하지 않습니다.
  다른 ID를 쓰려면 직접 변경하여 저장하거나 자동 배정으로 전환하세요.
- ID가 배정되면 설정의 **원격 WEB 관리자 연결** 바로 아래에
  `http://ysignage7.signage.cuniverse.net/` 또는 `http://ysignage7-1.signage.cuniverse.net/` 주소가 표시되며 클릭해서 접속할 수
  있습니다. 연결 직후와 이후 30초 간격으로 외부 URL에서 관리 HTTP 서버까지 실제 왕복
  접속을 확인하고, 실패하면 상태를 **끊김·재시도**로 표시한 뒤 10초 간격으로 SSH 연결과
  ID 배정을 계속 재시도합니다. 설정 화면에는 실제 forwarding 상태와 마지막 정상 확인
  시간이 함께 표시됩니다.
- mDNS는 기본으로 켜지며, 같은 로컬 네트워크에서 `http://ysignage.local`로 관리자 페이지에 접속할 수 있습니다.
- 여러 대를 같은 네트워크에서 운영할 때는 장치별로 서로 다른 `.local` 이름을 설정해야 합니다.
- Setup의 **사설 네트워크에서 WEB 관리 자동 허용**은 기본으로 선택됩니다. 관리자 승인을
  한 번 받으면 현재 관리 TCP 포트와 mDNS UDP 5353을 `Domain`·`Private` 프로필의
  `LocalSubnet`에만 허용하고, 제거 시 해당 규칙을 삭제합니다. 공개 네트워크는 허용하지
  않습니다. 포터블 ZIP은 Setup 단계가 없으므로 첫 실행 시 필요한 경우 승인을 요청합니다.
- Setup 설치 후 관리 API 포트나 mDNS 사용 여부를 바꾸면 앱이 저장된 방화벽 상태와 새
  설정을 비교합니다. 규칙이 없거나 다를 때만 관리자 승인을 요청해 자동으로 교체하며,
  관리 API를 끄면 Setup이 관리한 규칙을 제거합니다. 이미 일치하면 승인 창이 나타나지
  않습니다.
- 다른 PC에서 `http://<사이니지 IP>:<포트>/`에 접속하면 관리자 페이지가 열립니다.
- 로그인 PIN은 프로그램 설정에 사용하는 관리자 PIN과 같습니다. PIN 파일을 삭제한 상태의 기본값은 `1259`입니다.
- 로그인 세션은 마지막 활동 후 30분 동안 유효합니다. 관리자 탭 이동, 입력·클릭, API 요청이 있으면 자동 연장되며 설정 적용으로 관리 API가 다시 시작되어도 유지됩니다. 작업 없이 30분이 지나 실제 만료되면 현재 화면과 저장하지 않은 설정을 유지한 채 PIN 재인증 오버레이가 표시되며, 인증 후 중단된 요청을 자동으로 다시 수행합니다.
- 관리자 페이지에서 상태 확인, 화면 미리보기, 메뉴 설정 변경, 사이니지 보이기·감추기, 업데이트, 재시작과 완전 종료를 수행할 수 있습니다.
- **화면 미리보기** 탭은 사이니지가 배치된 Windows 모니터의 실제 데스크톱을 운영 확인용 JPEG로 표시합니다.
  미리보기 위의 **사이니지 보이기·숨기기** 버튼으로 창 표시를 제어하고, 옆에서 실행 중인 사이니지 버전을 확인할 수 있습니다.
  미리보기의 사이니지 영역을 클릭하면 같은 위치에 실제 마우스 왼쪽 클릭을 전달합니다.
  화면 보호기 해제, 언어·주제 선택, 툴바와 웹페이지 버튼 조작에 사용할 수 있습니다.
  축소 비율과 가로·세로 여백은 자동 보정합니다. 일시 정지 상태, 5초 이상 지난 화면,
  숨김·최소화 상태와 다른 창이 가린 영역에서는 클릭하지 않습니다.
  마우스나 터치로 누른 채 움직이면 실제 사이니지에 드래그를 전달하고, 놓으면 종료합니다.
  미리보기 밖에서 놓아도 입력이 해제되며, 탭 전환·포커스 이탈 시 드래그를 취소합니다.
  연결이 끊기면 마지막 입력 후 3초 내에 누름을 자동 해제합니다. 휠·키보드 입력은 지원하지 않습니다.
  기본값은 2fps·가로 1280px·JPEG 품질 45이고, 각각 1~5fps·640~1920px·20~80 범위에서
  저장할 수 있습니다. 사이니지를 숨기면 그 아래에 드러난 실제 데스크톱 화면을 계속
  갱신하고 숨김·최소화 상태를 텍스트로 표시합니다. 첫 렌더링 전에 생성된 빈 검은 프레임은 전송하지
  않고, 마지막 정상 화면이 있으면 이를 유지하면서 다음 캡처를 계속 시도합니다. 미리보기
  탭이 실제로 열려 있고 브라우저가 보이는 동안에만 동작하며, 탭을 벗어나거나 브라우저가
  백그라운드로 가면 즉시 중지합니다. 동시에 여러 요청이 들어오면 같은 캡처를 공유하여
  장비 부하가 요청 수만큼 늘어나지 않습니다. 느린 원격망에서는 1~2fps와 낮은 JPEG
  품질을 권장합니다.
- 사이니지 구성에는 오버라이드가 없어도 현재 적용 중인 기본 구성이 표시됩니다. 레이아웃·화면보호기·언어·주제·메뉴 항목을 설정 화면에서 편집하고, 각 언어·주제·메뉴의 **표시 여부**를 선택할 수 있습니다. 필요한 경우 **고급 JSON**을 사용할 수 있습니다.
- **전체 기본값 복원** 외에도 레이아웃·화면보호기·언어·언어별 메뉴 단위와 각 필드별로
  기본값을 복원할 수 있습니다. 기본 설정과 언어 ID·메뉴 ID가 일치하는 메뉴는 메뉴
  전체 또는 메뉴 내부의 개별 값만 복원할 수 있으며, **저장 후 즉시 적용** 전에는 실제
  사이니지 설정이 변경되지 않습니다.
- 실행 상태·화면 미리보기·관리 API·파일 관리·사이니지 구성·백업 및 진단은 탭으로 구분됩니다. 복수 표시 모드는 체크박스로 선택하고 메뉴 항목 화면에서도 언어를 추가하거나 삭제할 수 있습니다.
- **파일 관리** 탭은 데이터 루트의 `exdata/`만 표시합니다. Windows 탐색기 형태의 경로 이동·검색·정렬과 새 폴더, 다중/드래그 업로드, 다운로드, 이름 변경, 삭제를 지원합니다. `..`, 절대경로, 링크를 통한 `exdata/` 외부 접근은 거부합니다.
- `exdata/`에 올린 운영 파일은 업데이트 후에도 유지되며 설정에서는 `exdata/photos/`, `exdata/welcome.jpg` 같은 상대경로로 지정할 수 있습니다. 폴더 전체는 `*` 대신 폴더 경로 자체를 사용합니다.
- **사이니지 구성 → UI 모양·테마**에서는 밝기 계열, 메뉴 아이콘 기본 표시, 글꼴, 툴바·버튼 크기와 간격, 색상 및 **언어 선택 화면의 글꼴·배경·버튼 크기·색상**을 테마로 적용합니다. 툴바 위치, 표시 기능, 키오스크 잠금 같은 레이아웃·동작 값은 바뀌지 않습니다.
- 프리로드 테마 이름은 각 `assets/themes/*.json` 파일에서 읽습니다. 직접 편집한 UI 모양은 데이터 루트의 `themes/`에 사용자 테마로 별도 저장되며 업데이트 후에도 유지됩니다. 프리로드 테마와 같은 이름은 사용할 수 없습니다.
- 선택한 테마 ID는 `uiTheme`에 저장됩니다. 업데이트 후 앱이 재실행되거나 설정을 다시 불러오면 최신 테마를 적용하고, 직접 수정한 값만 별도 재정의로 유지합니다. 기본 설정이 바뀌어도 선택한 테마는 유지됩니다. 테마가 삭제되면 저장된 예비 모양(`uiThemeFallback`)을 사용합니다.
- 구버전 업데이트 후 첫 실행에서는 기존 테마 선택과 색상·UI 모양 재정의를 덮어쓰고 **고대비(텍스트)**에 자동 연결합니다. 언어·주제 선택 화면의 색상도 함께 적용합니다. 메뉴 구성, 문구, 툴바 위치와 동작 설정은 유지합니다. `state/high-contrast-text-default-v2.json`에 완료 상태를 기록하며, 과거 v1 적용 이력이 있어도 이번 전환은 한 번 실행됩니다. 이후 사용자가 다시 선택한 테마나 수정한 값은 재실행 시 초기화하지 않습니다.
- 테마 적용 후 UI 모양 값을 직접 바꾸면 경고가 표시됩니다. 다른 테마를 적용하기 전에 현재 모양을 사용자 테마로 저장할 수 있습니다.
- 기본 테마는 **고대비(텍스트)**입니다. 메뉴 아이콘은 기본적으로 감추며, 메뉴별 `showIcon: true`로 명시한 항목만 표시합니다. 기존 고대비 기본값 마이그레이션은 툴바 위치와 키오스크 동작을 유지하며, 이전 설정은 `backups/menu.override.before-high-contrast-*.json`에 백업합니다.
- 메뉴 설정은 저장 전에 기본 설정과 병합 검증되며, 올바른 설정은 저장 직후 사이니지에 적용됩니다.
- 백업 및 진단 탭에서 메뉴·언어·툴바·관리 API·업데이트 정책을 하나의 JSON으로 내보내거나 가져올 수 있습니다. 저장·가져오기 전 상태는 직전 설정으로 보관되어 복원할 수 있으며 관리자 PIN은 백업하지 않습니다.
- 같은 화면에서 프로그램·WebView·업데이트·API 로그와 시스템 정보를 포함한 진단 보고서를 다운로드할 수 있습니다.
- 앱 설정의 **진단 정보로 이슈 등록**은 WEB 관리자 화면을 열지 않고 진단 정보를
  중계 서버로 즉시 전송해 자동 이슈를 생성합니다. 등록 후에는 이슈 번호와 **이슈 보기**를 표시합니다.
- **GitHub 이슈 리포트**에서 분류·제목·문제 설명·재현 방법·기대 결과를 작성하면 프로그램 버전과 Windows 환경을 포함한 이슈가 중계 서버를 통해 바로 등록됩니다. GitHub 로그인은 필요하지 않으며, GW Nginx와 PHP 중계 서버가 구성되어 있어야 합니다.
- 관리 페이지는 HTTP로 PIN과 화면 미리보기를 전송하므로 신뢰할 수 있는 내부망에서만 사용하고 Windows 방화벽으로 접근 대상을 제한하세요.

### 콘텐츠 교체 빈도

- 대기화면 슬라이드쇼/폴더는 **외부 폴더 경로** 로 두면 앱 재배포 없이 운영자가 파일만 갈아주면 됩니다.
- Windows 운영 메뉴 변경은 웹 관리자의 **사이니지 구성**을 사용하거나
  `config/menu.override.json`을 수정한 뒤 앱을 다시 불러옵니다. 개발 기본값인
  `assets/config/menu.defaults.json`을 직접 수정했다면 앱 재시작이 필요합니다.

### 사이니지 모드

- **Android**: Lock Task Mode 또는 카니발/MDM 솔루션으로 홈 버튼 차단 권장.
- **Windows**: 사이니지 모드 사용자 계정 + 시작 프로그램으로 앱 자동 실행.
  - 프로그램 **설정 > Windows 시작프로그램**에서 등록 상태와 설치 경로 일치 여부를 확인할 수 있습니다.
  - `사이니지 모드로 표시` 또는 `숨김 모드로 시작`을 선택한 뒤 등록 정보를 저장합니다.
  - 숨김 모드에서는 Windows 로그인 후 트레이 아이콘만 표시되며 트레이 메뉴로 사이니지를 열 수 있습니다.
  - installer는 WebView2 Runtime이 없는 PC에서 자동 설치합니다.
- **자동 부팅 후 자동 실행**: OS 별 시작 프로그램 등록.

### 디스플레이

- **49인치 가로형 터치 사이니지** 등 큰 화면 가정.
- 작은 화면에서 테스트 시 `navPosition: bottom` 으로 자동 전환됩니다.

### 보안

- HTTPS 사이트 사용 권장.
- WebView 내 `tel:`, `mailto:`, `intent:` 등 외부 스킴은 자동 차단됨 (전화/메일 앱 의도치 않은 실행 방지).
- 새 창/팝업/다운로드도 차단되어 사용자가 시스템 외부로 빠져나가지 못합니다.

---

## 12. 문제 해결

### 메뉴 변경이 반영 안 됨
- `flutter run` 환경에서는 **`R` (대문자, 핫리스타트)** 을 누르세요. 핫리로드(`r`)는 에셋 변경이 반영되지 않습니다.
- 운영 환경에서는 앱을 종료 후 다시 실행.

### 상단에 로딩바가 계속 돈다
- Chrome(웹) 빌드에서만 발생할 수 있으며, iframe 구조 한계 때문입니다.
- Android/Windows 네이티브 빌드에서는 8초 안전 타임아웃으로 자동 처리됩니다.

### 일부 사이트가 표시되지 않는다
- Chrome(웹) 빌드: `X-Frame-Options` / `frame-ancestors` 헤더가 있는 사이트는 iframe 임베드 차단됨.
  - 본 사이니지의 **운영 환경(Android/Windows)** 에서는 정상 표시됩니다.
- 네이티브 빌드: User-Agent 검사 등으로 자체 차단하는 사이트는 우회 불가.

### Windows에서 동영상이 안 나옴
- WMP에서 재생되는지 먼저 확인.
- 안 되면 [K-Lite Codec Pack](https://codecguide.com/) 또는 Microsoft Store 의 코덱 확장 설치.

### Android에서 외부 폴더 미디어가 안 보임
- `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` 권한 추가 후 앱 권한 허용 필요.
- 또는 폴더를 `assets/...` 안으로 옮기고 앱과 함께 배포.

### 뒤로 버튼이 안 보임
- `layout.showHistoryButtons: true` 로 설정했는지 확인.
- 페이지 이동이 일어나야 활성화됩니다. 메뉴 첫 페이지에서는 비활성이 정상.

### macOS에서 외부 URL이 안 열림
- App Sandbox 때문입니다. `macos/Runner/*.entitlements` 두 파일에 다음 추가:
  ```xml
  <key>com.apple.security.network.client</key>
  <true/>
  ```

---

## 참고: 설정 전체 예시

```json
{
  "layout": {
    "navPosition": "bottom",
    "barHeight": 96,
    "buttonAlignment": "stretch",
    "showHistoryButtons": true
  },
  "idle": {
    "enabled": true,
    "timeoutSec": 90,
    "startOnLaunch": true,
    "mode": "folder",
    "folder": {
      "path": "assets/idle/",
      "intervalSec": 8,
      "shuffle": false,
      "includeImages": true,
      "includeVideos": true,
      "transition": "fade"
    },
    "showHint": true,
    "hintText": "화면을 터치해 주세요"
  },
  "defaultLanguage": "ko",
  "languages": [
    {
      "id": "ko",
      "label": "한국어",
      "items": [
        { "id": "home", "title": "홈", "url": "https://example.com" },
        { "id": "notice", "title": "공지", "url": "https://example.com/notice" }
      ]
    },
    {
      "id": "en",
      "label": "English",
      "items": [
        { "id": "home", "title": "Home", "url": "https://example.com/en" },
        { "id": "notice", "title": "Notices", "url": "https://example.com/en/notice" }
      ]
    }
  ]
}
```
