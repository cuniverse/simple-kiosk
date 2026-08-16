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
  - **세션 위생**: 앱 시작 + 대기화면 진입 시 쿠키 자동 삭제 → 이전 사용자의 로그인 상태가 다음 사용자에게 노출되지 않음
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
- **뒤로/앞으로 버튼**: `showHistoryButtons` 활성화 시 바의 **시작점** 에 표시
- **키보드 토글 버튼**: `showKeyboardToggle` 활성화 시 바의 **끝점** 에 표시
- **툴바 감추기 버튼**: 좌·우·상·하 툴바에서 `툴바 감추기` 버튼으로 전체 툴바를 감춤. 감춘 뒤에는
  `←`, `→`, 툴바 복원, `⌨`(가상 키보드) 버튼만 플로팅으로 표시. 컨트롤을
  드래그한 뒤 놓으면 왼쪽 위·오른쪽 위·왼쪽 아래·오른쪽 아래 중 가까운 모서리에 정렬
- **사이니지 감추기 제스처**: `화면 보호기 시작`을 더블클릭한 뒤 5초 안에 `툴바 감추기`를 더블클릭해야 사이니지 창이 감추어짐
- 각 버튼을 단일 클릭하면 기존처럼 화면 보호기 시작과 툴바 감추기만 수행
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
  "languages": [       // 언어와 언어별 메뉴 목록
    { "id": "ko", "label": "한국어", "defaultMenu": "home", "icon": "assets/icons/languages/kr.png", "items": [ ... ] },
    { "id": "en", "label": "English", "items": [ ... ] }
  ]
}
```

설정 변경 후 **앱 재시작**이 필요합니다. (개발 중 핫리스타트는 `R` 키)

---

## 4. 메뉴 관리

### 다국어 기본 형식

```json
"defaultLanguage": "ko",
"languageSelection": {
  "title": "언어를 선택하세요",
  "subtitle": "Please select your language"
},
"languages": [
  {
    "id": "ko",
    "label": "한국어",
    "subtitle": "Korean",
    "defaultMenu": "home",
    "items": [
      { "id": "home", "title": "홈", "url": "https://ko.example.com" }
    ]
  },
  {
    "id": "en",
    "label": "English",
    "subtitle": "영어",
    "items": [
      { "id": "home", "title": "Home", "url": "https://en.example.com" }
    ]
  }
]
```

- 화면보호기를 터치해 해제할 때마다 `languages`의 각 항목이 300×140dp 대형 버튼으로 표시됩니다.
- 툴바의 **언어 선택** 아이콘을 누르면 현재 WebView 상태를 유지한 채 언어 선택
  화면으로 다시 돌아갈 수 있습니다.
- 언어를 추가하려면 `languages` 배열에 고유한 `id`, 버튼에 표시할 `label`, 한 개 이상의 `items`를 가진 객체를 추가합니다.
- `defaultLanguage`는 앱 내부에서 언어 선택 전 준비할 기본 언어입니다.
- 각 언어의 `items`는 서로 완전히 독립적이므로 메뉴 개수, 이름, URL, 아이콘이 달라도 됩니다.
- `languages[].defaultMenu`는 언어 선택 직후 처음 표시할 메뉴 ID입니다. 생략하면
  해당 언어의 첫 번째 `items` 항목을 사용합니다.
- 언어의 `icon`에는 함께 배포되는 국기 이미지(`assets/icons/languages/kr.png`
  등), `icon:language`, 다른 앱 에셋 경로 또는 HTTPS 이미지 주소를 지정할 수 있습니다.
- 영어 기본 아이콘은 미국·영국 국기를 대각선으로 합성한
  `assets/icons/languages/en-us-gb.png`입니다.
- 기존 최상위 `items` 배열만 있는 설정도 단일 언어 설정으로 계속 동작합니다.

### 메뉴 항목 형식

| 필드 | 필수 | 설명 |
|------|------|------|
| `id` | ✓ | 메뉴 식별자. 중복 금지 권장. |
| `title` | ✓ | 버튼에 표시될 텍스트. (아이콘만 표시할 때도 툴팁/접근성으로 사용됨) |
| `url` | ✓ | 버튼을 눌렀을 때 WebView에 로드할 URL |
| `icon` | ✗ | 아이콘 (자세한 형식은 [§6](#6-아이콘-사용)) |
| `showTitle` | ✗ | `false` 면 아이콘만 표시 (기본 `true`) |
| `keepStateOnTap` | ✗ | 항목별 상태 유지 오버라이드. `null`(기본) 이면 `layout.keepStateOnTap` 값을 따른다. 자세한 동작은 [§5 keepStateOnTap](#keepstateontap--메뉴-상태-유지-동작) 참고 |

### 주의 사항

- **운영에서는 HTTPS 사용 권장.** HTTP도 동작하지만 보안/신뢰성 측면에서 HTTPS가 안전합니다.
- 메뉴는 위에서 아래(또는 왼쪽에서 오른쪽) 순서로 표시됩니다.
- `defaultMenu`로 지정한 항목이 **홈(기본 페이지)** 역할을 하며, 설정이 없으면 첫 번째 항목을 사용합니다.
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
  "navPosition": "bottom",
  "sideWidth": 220,
  "barHeight": 96,
  "breakpoint": 720,
  "buttonHeight": 0,
  "buttonWidth": 0,
  "buttonGap": 8,
  "buttonAlignment": "stretch",
  "showHistoryButtons": true,
  "showKeyboardToggle": true,
  "keepStateOnTap": false,
  "toolbarInitiallyHidden": true,
  "toolbarAutoHideSec": 10
}
```

### 옵션 표

| 키 | 타입 | 기본값 | 설명 |
|----|------|--------|------|
| `navPosition` | `auto`\|`left`\|`right`\|`top`\|`bottom` | `auto` | 네비 위치. `auto`는 화면 폭에 따라 자동 |
| `sideWidth` | 숫자 > 0 | `220` | `left`/`right`일 때 사이드 폭(dp) |
| `barHeight` | 숫자 > 0 | `96` | `top`/`bottom`일 때 바 높이(dp) |
| `breakpoint` | 숫자 > 0 | `720` | `auto` 모드의 임계 폭. 이 이상이면 좌측, 미만이면 하단 |
| `buttonHeight` | 숫자 ≥ 0 | `0` | 버튼 높이(dp). `0`=자동 |
| `buttonWidth` | 숫자 ≥ 0 | `0` | 하단/상단 모드 버튼 폭. `0`=균등 분배 |
| `buttonGap` | 숫자 ≥ 0 | `8` | 버튼 사이 간격(dp) |
| `buttonAlignment` | 문자열 | `stretch` | 정렬 방식 (아래 표) |
| `showHistoryButtons` | bool | `false` | 네비 **시작점** 에 ←/→ 버튼 표시 |
| `showKeyboardToggle` | bool | `false` | 네비 **끝점** 에 OS 가상 키보드 토글 버튼 표시 ([§9](#9-가상-키보드) 참고) |
| `keyboardMode` | `windows` / `builtin` | `windows` | Windows 화면 키보드 또는 앱 내장 키보드 선택 |
| `keepStateOnTap` | bool | `false` | 같은 메뉴 단일 탭 시 페이지 상태 유지 (아래 [keepStateOnTap](#keepstateontap--메뉴-상태-유지-동작) 참고) |
| `toolbarInitiallyHidden` | bool | `true` | 앱 시작 시 툴바를 감춘 상태로 표시 |
| `toolbarAutoHideSec` | 숫자 ≥ 0 | `10` | 복원한 툴바를 입력 없이 표시할 시간(초). `0`이면 자동 숨김 해제 |
| `barColor` | 색상 문자열 | (테마) | 툴바 배경색. 웹 관리자의 색상 선택기에서 변경 가능 |
| `buttonColor` | 색상 문자열 | (테마) | 비선택 버튼 배경색 |
| `buttonForegroundColor` | 색상 문자열 | (테마) | 비선택 버튼 텍스트/아이콘 색 |
| `selectedButtonColor` | 색상 문자열 | (테마) | 선택된 버튼 배경색 |
| `selectedButtonForegroundColor` | 색상 문자열 | (테마) | 선택된 버튼 텍스트/아이콘 색 |

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

`icon` 필드에는 3가지 형식이 가능합니다.

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

### B. 로컬 PNG 파일

```json
"icon": "assets/icons/custom.png"
```

- 파일을 `assets/icons/` 폴더에 넣고
- 권장 크기: **96×96px** 이상 정사각형, 투명 배경
- `pubspec.yaml` 의 `assets/icons/` 가 이미 등록되어 있어 자동으로 포함됨

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

| 키 | 기본값 | 설명 |
|----|--------|------|
| `enabled` | `false` | 대기화면 사용 여부 |
| `timeoutSec` | `60` | 무입력 → 대기화면 진입까지의 초. `0` 이면 무입력 진입 안 함 |
| `startOnLaunch` | `true` | 앱 시작 시 즉시 대기화면을 띄울지 |
| `modes` | `["none"]` | 표시 콘텐츠 배열. `slideshow`, `folder`, `gallery`는 복수 지정 가능 |
| `mode` | `none` | 기존 단일 모드 호환 설정. `modes`가 있으면 `modes` 우선 |
| `showHint` | `true` | "화면을 터치해 주세요" 안내 배지 표시 |
| `hintText` | `화면을 터치해 주세요` | 안내 문구 |

### A. 단일 이미지

```json
"idle": {
  "enabled": true, "timeoutSec": 60, "mode": "image",
  "image": "assets/idle/welcome.jpg"
}
```

### B. 슬라이드쇼 (이미지 리스트)

```json
"idle": {
  "enabled": true, "timeoutSec": 60, "mode": "slideshow",
  "slideshow": {
    "intervalSec": 6,
    "transition": "fade",       // "fade" | "none"
    "images": [
      "assets/idle/slide1.jpg",
      "assets/idle/slide2.jpg",
      "assets/idle/slide3.jpg"
    ]
  }
}
```

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
      "http://ycatholic.or.kr/bbs/board.php?bo_table=gallery",
      "https://example.com/second-gallery"
    ],
    "intervalSec": 8,
    "lookbackDays": 30,
    "minPosts": 2,
    "refreshIntervalMin": 5,
    "shuffle": false,
    "maxPosts": 4,
    "maxImages": 40,
    "transition": "fade"
  },
  "showHint": true,
  "hintText": "화면을 터치해 주세요"
}
```

| 키 | 기본값 | 설명 |
|----|--------|------|
| `urls` | 필수 | 그누보드 계열 포토갤러리 목록 URL 배열 |
| `url` | - | 기존 단일 게시판 호환 설정. `urls`가 있으면 `urls` 우선 |
| `intervalSec` | `8` | 사진 한 장을 표시할 시간(초) |
| `lookbackDays` | 미지정 | 현재 시각부터 과거 며칠까지 작성된 게시물을 우선 선택 |
| `minPosts` | `1` | 기간 조건의 결과가 부족할 때 최신순으로 보충할 최소 게시물 수 |
| `refreshIntervalMin` | `5` | 실행 중 게시판을 다시 확인하는 주기(분) |
| `shuffle` | `false` | `true`이면 미리 만든 무작위 순서로 사진을 순회 |
| `maxPosts` | `4` | 최종적으로 사진을 수집할 게시물 수의 상한 |
| `maxImages` | `40` | 한 번에 순환할 최대 사진 수 |
| `transition` | `fade` | 사진 전환 효과 (`fade` / `none`) |

- 목록 썸네일 대신 각 게시물 본문의 원본 이미지 링크를 우선 사용합니다.
- `lookbackDays: 30`이면 갱신 시각을 기준으로 정확히 30일 전까지의 게시물을 선택합니다.
- `lookbackDays`를 생략하면 기존처럼 최신 게시물을 `maxPosts`개까지 읽습니다.
- 기간 조건에 맞는 게시물이 `minPosts`보다 적거나 없으면 최신 게시물로 `minPosts`개까지 보충합니다.
- 5분 갱신 시 현재 사진의 URL과 재생 위치를 유지하므로 슬라이드가 처음부터 다시 시작되지 않습니다.
- 갱신에 실패하면 현재 재생 목록을 유지하고 다음 주기에 다시 시도합니다.
- 키보드 `←` / `→` 또는 화면 좌우 스와이프로 이전·다음 사진을 볼 수 있습니다.
- 화면을 탭하면 보호기가 종료되며, 다시 진입하면 마지막 사진과 재생 순서부터 이어집니다.
- 랜덤 모드에서도 갱신할 때 기존 무작위 순서는 유지하고 새 사진만 순서에 추가합니다.
- `minPosts`는 `maxPosts`보다 클 수 없습니다.
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

## 9. 가상 키보드

Windows에서는 기본적으로 Windows 화상 키보드를 사용합니다. **외부 메뉴 설정 >
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
| 메뉴 클릭 후 3초 내 응답 없음 | WebView 재생성, 사용자가 가려던 URL 로 이동 |
| 메뉴 JSON 로드 실패 | 5초 후 자동 재시도 (반복) |

### WebView 데이터 정책

모든 메뉴 WebView는 동일한 WebView 프로필을 사용하므로 쿠키, 캐시와 Local Storage가
공유됩니다. 웹 관리자의 **WebView 데이터**에서 화면보호기 진입 시 정책을 선택합니다.

- `keep`: 쿠키·캐시·Local Storage를 모두 유지
- `cookiesOnly`(기본): 쿠키만 삭제하고 캐시·Local Storage는 유지
- `allSiteData`: 쿠키·캐시·Local Storage·IndexedDB 등 사이트 데이터 전체 삭제

`preserveDomains`에 `catholic.or.kr`처럼 도메인을 한 줄씩 지정하면 해당 도메인과
하위 도메인의 로그인 데이터는 삭제 대상에서 제외합니다. 프로그램 시작 시에는 데이터를
임의로 삭제하지 않으며, 화면보호기 진입 시 선택한 정책을 적용합니다.

### 메모리 정리 (대기화면 진입 시)

메뉴별로 독립 된 WebView 가 생성되므로, 대기화면 진입 시점에
**홈(`defaultMenu`) 이외의 모든 WebView 를 언mount** 해 WebView2 인스턴스를 회수합니다.
다음 사용자가 다른 메뉴를 누르면 그 시점에 새로 mount 됩니다.

---

## 11. 운영 팁

### 기능키

- `F1`: 프로그램 안에서 사용자 매뉴얼 팝업 표시
- `F12`: 프로그램·Updater 버전과 GitHub 정보 표시
- `F9`: 업데이트 확인 후 사용자 동의 시 다운로드, 설치 및 자동 재시작

### Windows 시스템 트레이

- 프로그램 실행 중 Windows 알림 영역에 **여의도성당Signage** 트레이 아이콘이 표시됩니다.
- 창 닫기 또는 `Alt + F4`도 완전히 종료하지 않고 사이니지 화면을 감춥니다.
- 트레이 아이콘을 왼쪽 클릭하면 사이니지 화면을 보이거나 감출 수 있습니다.
- 트레이 메뉴에서 **사이니지 보이기**, **사이니지 감추기**, **설정**, **사용자 매뉴얼**, **완전 종료**를 선택할 수 있습니다.
- **설정**은 기존과 동일하게 관리자 PIN 인증 후 열립니다.
- 프로그램을 완전히 끝내려면 설정 화면 하단 또는 트레이 메뉴의 **완전 종료**를 사용합니다.

### Windows 최초 실행 필수 구성요소

- installer와 포터블 ZIP에는 앱 실행에 필요한 Visual C++ Runtime DLL이 포함됩니다.
- installer와 `InstallPrerequisites.cmd`는 Microsoft Visual C++ Redistributable을 자동 설치하거나 업데이트합니다.
- installer는 Microsoft Edge WebView2 Runtime을 확인하고 없으면 자동 설치합니다.
- 포터블 ZIP을 새 PC에서 사용할 때 WebView2가 없으면 `InstallPrerequisites.cmd`를 먼저 실행하세요.
- WebView2 자동 설치에는 인터넷 연결이 필요합니다.

### 원격 관리자 페이지와 API

- 프로그램의 **설정 > 관리 API / 관리자 페이지**에서 사용 여부와 포트를 지정합니다. 기본 포트는 `80`입니다.
- mDNS는 기본으로 켜지며, 같은 로컬 네트워크에서 `http://ysignage.local`로 관리자 페이지에 접속할 수 있습니다.
- 여러 대를 같은 네트워크에서 운영할 때는 장치별로 서로 다른 `.local` 이름을 설정해야 합니다.
- 다른 PC에서 `http://<사이니지 IP>:<포트>/`에 접속하면 관리자 페이지가 열립니다.
- 로그인 PIN은 프로그램 설정에 사용하는 관리자 PIN과 같습니다. PIN 파일을 삭제한 상태의 기본값은 `1259`입니다.
- 관리자 페이지에서 상태 확인, 메뉴 설정 변경, 사이니지 보이기·감추기, 업데이트, 재시작과 완전 종료를 수행할 수 있습니다.
- 외부 메뉴 설정에는 오버라이드가 없어도 현재 적용 중인 기본 구성이 표시됩니다. 레이아웃·화면보호기·언어·메뉴 항목을 설정 화면에서 편집하고, 필요한 경우 **고급 JSON**을 사용할 수 있습니다.
- **전체 기본값 복원** 외에도 레이아웃·화면보호기·언어·언어별 메뉴 단위와 각 필드별로
  기본값을 복원할 수 있습니다. 기본 설정과 언어 ID·메뉴 ID가 일치하는 메뉴는 메뉴
  전체 또는 메뉴 내부의 개별 값만 복원할 수 있으며, **저장 후 즉시 적용** 전에는 실제
  사이니지 설정이 변경되지 않습니다.
- 실행 상태·관리 API·외부 메뉴 설정·백업 및 진단은 탭으로 구분됩니다. 복수 표시 모드는 체크박스로 선택하고 메뉴 항목 화면에서도 언어를 추가하거나 삭제할 수 있습니다.
- 메뉴 설정은 저장 전에 기본 설정과 병합 검증되며, 올바른 설정은 저장 직후 사이니지에 적용됩니다.
- 백업 및 진단 탭에서 메뉴·언어·툴바·관리 API·업데이트 정책을 하나의 JSON으로 내보내거나 가져올 수 있습니다. 저장·가져오기 전 상태는 직전 설정으로 보관되어 복원할 수 있으며 관리자 PIN은 백업하지 않습니다.
- 같은 화면에서 프로그램·WebView·업데이트·API 로그와 시스템 정보를 포함한 진단 보고서를 다운로드할 수 있습니다.
- 관리 페이지는 HTTP로 PIN을 전송하므로 신뢰할 수 있는 내부망에서만 사용하고 Windows 방화벽으로 접근 대상을 제한하세요.

### 콘텐츠 교체 빈도

- 대기화면 슬라이드쇼/폴더는 **외부 폴더 경로** 로 두면 앱 재배포 없이 운영자가 파일만 갈아주면 됩니다.
- 메뉴 변경은 `menu.json` 수정 후 **앱 재시작** 필요.

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
