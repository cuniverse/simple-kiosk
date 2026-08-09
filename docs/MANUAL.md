# Simple Kiosk 사용 매뉴얼

성당 로비 / 디지털 사이니지용 키오스크 앱의 **운영자 / 콘텐츠 관리자**를 위한 매뉴얼입니다.
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

- **목적**: 키오스크/사이니지 단말기에서 미리 정의된 웹페이지 몇 개를 메뉴 버튼으로 전환해 보여주기.
- **핵심 정책**:
  - 새 창 / 팝업 / 외부 스킴(`tel:`, `mailto:` 등) **차단**
  - 다운로드 **차단**
  - **메뉴별 독립 WebView** (IndexedStack): 다른 메뉴에 다녀와도 스크롤/내부 페이지 상태 유지
  - 같은 메뉴 **더블 탭** (300ms 이내) 으로 강제 초기 URL 재로드
  - 대기화면을 띄워 무인 운영
  - **세션 위생**: 앱 시작 + 대기화면 진입 시 쿠키 자동 삭제 → 이전 사용자의 로그인 상태가 다음 사용자에게 노출되지 않음
  - **자동 복구**: 페이지 에러 / 렌더러 종료 / Alt+F4 등 비정상 상황에서 WebView 자동 재생성
- **모든 설정은 한 파일**: `assets/config/menu.json` (앱 재시작 후 반영)

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
- **툴바 숨김 버튼**: 하단 바의 맨 오른쪽 `⌄` 버튼. 숨긴 뒤에는 화면 우측 하단에
  `←`, `→`, `⌃`(툴바 복원), `⌨`(가상 키보드) 버튼만 플로팅으로 표시
- **대기화면**: 일정 시간 무입력 시 자동 진입, 화면 터치로 해제
- **메뉴별 WebView**: 메뉴 인덱스마다 독립된 WebView 인스턴스를 lazy 생성하여 IndexedStack 으로 전환

---

## 3. 설정 파일 한눈에 보기

`assets/config/menu.json` 전체 구조:

```json
{
  "layout": { ... },   // 네비게이션 바 모양/위치
  "idle":   { ... },   // 대기화면 설정 (옵션)
  "items":  [ ... ]    // 메뉴 항목 목록
}
```

세 섹션 모두 변경 후 **앱 재시작**이 필요합니다. (개발 중 핫리스타트는 `R` 키)

---

## 4. 메뉴 관리

### 기본 형식

```json
"items": [
  {
    "id": "home",
    "title": "홈",
    "url": "https://example.com",
    "icon": "icon:home"
  },
  {
    "id": "notice",
    "title": "공지",
    "url": "https://example.com/notice",
    "icon": "icon:notice"
  }
]
```

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
- 첫 번째 항목이 **홈(기본 페이지)** 역할을 합니다.
- 메뉴별로 독립 WebView 가 생성되며, **한 번이라도 방문한 메뉴만 메모리에 살아있습니다** (방문 전엔 mount 되지 않음).
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
  "keepStateOnTap": false
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
| `keepStateOnTap` | bool | `false` | 같은 메뉴 단일 탭 시 페이지 상태 유지 (아래 [keepStateOnTap](#keepstateontap--메뉴-상태-유지-동작) 참고) |
| `barColor` | 색상 문자열 | (테마) | 네비 바 배경색 |
| `buttonColor` | 색상 문자열 | (테마) | 비선택 버튼 배경색 |
| `buttonForegroundColor` | 색상 문자열 | (테마) | 비선택 버튼 텍스트/아이콘 색 |
| `selectedButtonColor` | 색상 문자열 | (테마) | 선택된 버튼 배경색 |
| `selectedButtonForegroundColor` | 색상 문자열 | (테마) | 선택된 버튼 텍스트/아이콘 색 |

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
  "mode": "slideshow",
  "showHint": true,
  "hintText": "화면을 터치해 주세요"
}
```

| 키 | 기본값 | 설명 |
|----|--------|------|
| `enabled` | `false` | 대기화면 사용 여부 |
| `timeoutSec` | `60` | 무입력 → 대기화면 진입까지의 초. `0` 이면 무입력 진입 안 함 |
| `startOnLaunch` | `true` | 앱 시작 시 즉시 대기화면을 띄울지 |
| `mode` | `none` | 표시 콘텐츠 (`none` / `image` / `slideshow` / `folder` / `url`) |
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
  "enabled": true, "timeoutSec": 60, "mode": "folder",
  "folder": {
    "path": "assets/idle/",
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
| `path` | 필수 | 폴더 경로. `assets/...` 또는 OS 절대 경로 |
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

### D. URL 풀스크린

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

이 동작은 키오스크에서 사용자가 헤맬 가능성을 최소화합니다.

---

## 9. 가상 키보드

OS 시스템 키보드 대신 **Flutter 자체 가상 키보드**를 내장해 모든 OS 에서 동일한 디자인과 동작을 제공합니다.

### 특징

- **한글 두벌식 자모 조합** (초성/중성/종성, 이중 모음, 겹받침 포함)
- 영문 QWERTY / 숫자·특수문자 모드 토글
- Shift 단일 입력 / 잠금 / 해제 (한 번 탕 → 다음 글자만 적용, 두 번 탕 → 잠금, 세 번 탕 → 해제)
- 함들을 드래그해 화면 어디에나 이동 가능한 **플로팅 윈도우**
- WebView 내 `<input>` / `<textarea>` / `[contenteditable]` 포커스 시 자동 표시
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

### 세션 위생 (쿠키)

이전 사용자의 로그인 상태가 다음 사용자에게 노출되지 않도록 다음 시점에 자동으로 모든 쿠키를 삭제합니다.

1. **앱 시작 시** ([lib/main.dart](../lib/main.dart))
2. **대기화면 진입 시** ([lib/app.dart](../lib/app.dart) `_onEnterIdle`)

캐시(이미지/JS/CSS) 는 유지되어 다음 로딩 성능 손해는 없습니다.

### 메모리 정리 (대기화면 진입 시)

메뉴별로 독립 된 WebView 가 생성되므로, 대기화면 진입 시점에
**홈(첫 번째 항목) 이외의 모든 WebView 를 언mount** 해 WebView2 인스턴스를 회수합니다.
다음 사용자가 다른 메뉴를 누르면 그 시점에 새로 mount 됩니다.

---

## 11. 운영 팁

### 콘텐츠 교체 빈도

- 대기화면 슬라이드쇼/폴더는 **외부 폴더 경로** 로 두면 앱 재배포 없이 운영자가 파일만 갈아주면 됩니다.
- 메뉴 변경은 `menu.json` 수정 후 **앱 재시작** 필요.

### 키오스크 모드

- **Android**: Lock Task Mode 또는 카니발/MDM 솔루션으로 홈 버튼 차단 권장.
- **Windows**: 키오스크 모드 사용자 계정 + 시작 프로그램으로 앱 자동 실행.
  - WebView2 Runtime 사전 설치 필요 (Windows 10 일부 환경).
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
  - 본 키오스크의 **운영 환경(Android/Windows)** 에서는 정상 표시됩니다.
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
  "items": [
    {
      "id": "home", "title": "홈",
      "url": "https://example.com",
      "icon": "icon:home"
    },
    {
      "id": "notice", "title": "공지",
      "url": "https://example.com/notice",
      "icon": "icon:notice"
    },
    {
      "id": "gallery", "title": "포토갤러리",
      "url": "https://example.com/gallery",
      "icon": "icon:gallery"
    },
    {
      "id": "jubo", "title": "주보",
      "url": "https://example.com/jubo",
      "icon": "icon:book"
    }
  ]
}
```
