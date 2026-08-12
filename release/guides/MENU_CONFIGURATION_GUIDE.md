# Simple Kiosk 메뉴 설정 상세 가이드

이 문서는 `menu.json`을 수정하여 메뉴, 툴바, 색상 및 대기화면을 구성하는 방법을
설명합니다. JSON을 수정하기 전에 원본 파일을 반드시 백업하세요.

## 1. 설정 파일 위치와 반영 방법

개발 프로젝트의 원본 설정 파일:

```text
assets/config/menu.json
```

| 환경 | 설정 위치 및 반영 방법 |
|---|---|
| 개발 환경 | `assets/config/menu.json` 수정 후 앱을 재시작합니다. `flutter run` 중에는 대문자 `R`로 핫 리스타트합니다. |
| Windows 배포본 | `<설치 폴더>\data\flutter_assets\assets\config\menu.json`을 수정하고 앱을 완전히 종료한 후 다시 실행합니다. |
| Android 배포본 | APK 내부 에셋을 직접 수정하지 않습니다. 프로젝트 원본을 수정한 뒤 APK를 다시 빌드하고 설치합니다. |
| macOS 배포본 | 앱 번들 직접 수정은 서명 무결성을 깨뜨릴 수 있습니다. 프로젝트 원본을 수정한 뒤 앱을 다시 빌드합니다. |

Windows에서 기본 설치 폴더가 `C:\SimpleKiosk`라면 실제 경로는 다음과 같습니다.

```text
C:\SimpleKiosk\data\flutter_assets\assets\config\menu.json
```

## 2. 안전하게 수정하는 순서

1. Simple Kiosk를 완전히 종료합니다.
2. 기존 `menu.json`을 `menu.backup.json` 같은 이름으로 복사합니다.
3. UTF-8을 지원하는 편집기로 `menu.json`을 엽니다.
4. JSON 문법을 지키면서 필요한 값만 수정합니다.
5. 아래 방법으로 JSON 문법을 검사합니다.
6. 앱을 다시 실행하고 모든 메뉴를 시험합니다.

PowerShell에서 문법 검사:

```powershell
Get-Content .\menu.json -Raw | ConvertFrom-Json | Out-Null
```

macOS 또는 Linux에서 문법 검사:

```bash
python3 -m json.tool assets/config/menu.json >/dev/null
```

JSON 작성 시 다음 사항에 주의하세요.

- 문자열은 큰따옴표(`"`)로 감쌉니다.
- 항목 사이는 쉼표로 구분하지만 마지막 항목 뒤에는 쉼표를 넣지 않습니다.
- JSON에는 `// 설명` 같은 주석을 넣을 수 없습니다.
- `true`와 `false`는 따옴표 없이 소문자로 작성합니다.
- Windows 경로를 JSON 문자열로 쓸 때는 `C:/kiosk_media` 형식을 권장합니다.

## 3. 전체 구조

설정 파일은 `layout`, `idle`, `items` 세 영역으로 구성됩니다.

```json
{
  "layout": {
    "navPosition": "bottom"
  },
  "idle": {
    "enabled": false,
    "mode": "none"
  },
  "items": [
    {
      "id": "home",
      "title": "홈",
      "url": "https://example.com",
      "icon": "icon:home"
    }
  ]
}
```

- `layout`: 툴바 위치, 크기, 버튼과 색상 설정
- `idle`: 일정 시간 사용하지 않을 때 표시할 대기화면 설정
- `items`: 실제로 표시할 메뉴 버튼 목록
- `items`는 한 개 이상 있어야 하며 첫 번째 항목이 기본 홈 메뉴가 됩니다.
- 생략 가능한 값을 쓰지 않으면 앱의 기본값이 적용됩니다.

## 4. 메뉴 항목 설정: `items`

기본 메뉴 한 개의 형식은 다음과 같습니다.

```json
{
  "id": "notice",
  "title": "공지사항",
  "url": "https://example.com/notice",
  "icon": "icon:notice",
  "showTitle": true,
  "keepStateOnTap": true
}
```

| 키 | 타입 | 필수 | 기본값 | 설명 |
|---|---|---:|---|---|
| `id` | 문자열 | 예 | 없음 | 메뉴 식별자입니다. 영문 소문자, 숫자, `_`, `-` 조합을 권장하며 중복하지 마세요. |
| `title` | 문자열 | 예 | 없음 | 버튼에 표시할 이름입니다. 제목을 숨겨도 접근성 라벨로 사용됩니다. |
| `url` | 문자열 | 예 | 없음 | 메뉴를 선택했을 때 열 URL입니다. 운영 환경에서는 HTTPS를 권장합니다. |
| `icon` | 문자열 | 아니요 | 없음 | 내장 아이콘, 로컬 에셋 또는 네트워크 이미지입니다. |
| `showTitle` | bool | 아니요 | `true` | `false`이면 아이콘만 표시합니다. 아이콘이 없으면 빈 버튼 방지를 위해 제목이 표시됩니다. |
| `keepStateOnTap` | bool | 아니요 | `layout` 값 상속 | 이 메뉴의 현재 웹페이지·스크롤 상태 유지 방식을 개별 지정합니다. |

### 메뉴 추가

`items` 배열 안에 객체를 추가합니다. 화면에는 작성한 순서대로 표시됩니다.

```json
"items": [
  {
    "id": "home",
    "title": "홈",
    "url": "https://example.com",
    "icon": "icon:home"
  },
  {
    "id": "news",
    "title": "새소식",
    "url": "https://example.com/news",
    "icon": "icon:news"
  }
]
```

### 메뉴 순서 변경과 삭제

- 순서 변경: `items` 안의 객체 순서를 바꿉니다.
- 삭제: 해당 객체 전체를 삭제하고 앞뒤의 쉼표를 정리합니다.
- 첫 번째 메뉴를 바꾸면 앱의 홈 복귀 대상도 함께 바뀝니다.

### 페이지 상태 유지: `keepStateOnTap`

- `false`: 메뉴 버튼을 누를 때 설정된 초기 URL로 이동합니다.
- `true`: 이미 열었던 메뉴로 돌아갈 때 현재 내부 페이지와 스크롤 상태를 유지합니다.
- 선택된 메뉴를 빠르게 두 번 누르면 설정된 초기 URL로 강제 재로드합니다.
- `items[].keepStateOnTap`이 있으면 `layout.keepStateOnTap`보다 우선합니다.

## 5. 아이콘 설정

### 내장 Material 아이콘

별도 이미지 파일이 필요 없어 가장 안정적입니다.

```json
"icon": "icon:home"
```

사용 가능한 이름:

```text
home, notice, announcement, gallery, photo, video, movie, info,
church, menu, list, calendar, event, mail, phone, map, location,
settings, book, document, news, people, group, star, favorite,
search, help, link, web, music, mic, camera, image, download, qr
```

### 프로젝트에 포함한 이미지

```json
"icon": "assets/icons/custom.png"
```

- 원본 이미지를 `assets/icons/`에 넣고 패키지를 다시 빌드합니다.
- 96×96px 이상의 정사각형 PNG와 투명 배경을 권장합니다.
- 배포 후 파일만 추가하면 Flutter 에셋 목록에 등록되지 않을 수 있으므로 재빌드가
  안전합니다.

### 네트워크 이미지

```json
"icon": "https://example.com/images/menu.png"
```

네트워크 장애나 서버 변경의 영향을 받으므로 무인 운영에는 내장 아이콘 또는 로컬
이미지를 권장합니다.

## 6. 툴바 레이아웃 설정: `layout`

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
  "toolbarAutoHideSec": 10,
  "barColor": "#1f2937",
  "buttonColor": "#374151",
  "buttonForegroundColor": "#ffffff",
  "selectedButtonColor": "#2563eb",
  "selectedButtonForegroundColor": "#ffffff"
}
```

| 키 | 타입 | 기본값 | 허용값 및 설명 |
|---|---|---|---|
| `navPosition` | 문자열 | `auto` | `auto`, `left`, `right`, `top`, `bottom` |
| `sideWidth` | 양수 | `220` | 좌우 툴바 폭(dp) |
| `barHeight` | 양수 | `96` | 상하 툴바 높이(dp) |
| `breakpoint` | 양수 | `720` | `auto`에서 이 폭 이상이면 왼쪽, 미만이면 하단 툴바 사용 |
| `buttonHeight` | 0 이상 | `0` | 버튼 높이(dp), `0`은 자동 |
| `buttonWidth` | 0 이상 | `0` | 상하 툴바 버튼 폭(dp), `0`은 가용 공간 분배 |
| `buttonGap` | 0 이상 | `8` | 버튼 사이 간격(dp) |
| `buttonAlignment` | 문자열 | `stretch` | `start`, `center`, `end`, `spaceBetween`, `spaceAround`, `spaceEvenly`, `stretch` |
| `showHistoryButtons` | bool | `false` | 뒤로·앞으로 버튼 표시 |
| `showKeyboardToggle` | bool | `false` | 가상 키보드 켜기·끄기 버튼 표시 |
| `keepStateOnTap` | bool | `false` | 모든 메뉴의 기본 상태 유지 동작 |
| `toolbarInitiallyHidden` | bool | `true` | 앱 시작 시 하단 툴바를 숨김 상태로 표시 |
| `toolbarAutoHideSec` | 0 이상의 숫자 | `10` | 펼친 툴바를 입력 없이 표시할 시간(초). `0`이면 자동 숨김 해제 |

툴바는 기본적으로 숨김 상태로 시작합니다. 오버레이의 복원 버튼으로 툴바를 표시한
뒤 `toolbarAutoHideSec` 동안 화면 터치, 드래그 또는 스크롤 입력이 없으면 다시
자동으로 숨겨집니다. 입력이 발생하면 제한 시간은 처음부터 다시 계산됩니다.

툴바를 숨겨도 같은 WebView가 유지되므로 현재 페이지, 입력 내용과 스크롤 위치가
바뀌지 않습니다. 숨김 상태에서는 뒤로, 앞으로, 툴바 복원, 가상 키보드 버튼이
오버레이로 표시되며 드래그 후 가까운 화면 모서리에 정렬됩니다. 이 두 설정은 현재
숨김 기능을 지원하는 하단 툴바에 적용됩니다.

### 버튼 정렬 예

- `stretch`: 상하 툴바에서 버튼을 균등 분배
- `start`: 왼쪽 또는 위쪽에 모음
- `center`: 가운데에 모음
- `end`: 오른쪽 또는 아래쪽에 모음
- `spaceBetween`: 처음과 끝을 양쪽 끝에 두고 사이를 균등 배치
- `spaceAround`: 각 버튼 둘레에 같은 여백 배치
- `spaceEvenly`: 버튼 사이와 양 끝의 여백을 모두 동일하게 배치

### 색상 형식

| 형식 | 예 | 설명 |
|---|---|---|
| `#RGB` | `#f00` | `#ff0000`의 축약형 |
| `#RRGGBB` | `#2563eb` | 불투명 RGB |
| `#AARRGGBB` | `#802563eb` | 알파 값이 앞에 있는 ARGB |
| `transparent` | `transparent` | 완전 투명 |

색상을 생략하면 앱 테마의 기본 색상이 적용됩니다.

## 7. 대기화면 설정: `idle`

공통 설정:

```json
"idle": {
  "enabled": true,
  "timeoutSec": 60,
  "startOnLaunch": true,
  "mode": "image",
  "image": "assets/idle/welcome.jpg",
  "showHint": true,
  "hintText": "화면을 터치해 주세요"
}
```

| 키 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `enabled` | bool | `false` | 대기화면 기능 사용 여부 |
| `timeoutSec` | 숫자 | `60` | 마지막 입력 후 진입할 때까지의 초. `0` 이하는 자동 진입 안 함 |
| `startOnLaunch` | bool | `true` | 앱 시작 직후 대기화면 표시 여부 |
| `modes` | 배열 | `["none"]` | `slideshow`, `folder`, `gallery`는 복수 지정 가능 |
| `mode` | 문자열 | `none` | 기존 단일 모드 호환 설정. `modes`가 있으면 무시 |
| `showHint` | bool | `true` | 터치 안내 문구 표시 여부 |
| `hintText` | 문자열 | `화면을 터치해 주세요` | 안내 문구 |

`enabled`가 `true`여도 선택한 모드에 필요한 이미지, URL 또는 폴더가 비어 있으면
대기화면이 동작하지 않습니다.

### 단일 이미지: `image`

```json
"idle": {
  "enabled": true,
  "timeoutSec": 60,
  "startOnLaunch": true,
  "mode": "image",
  "image": "assets/idle/welcome.jpg",
  "showHint": true,
  "hintText": "화면을 터치해 주세요"
}
```

### 이미지 슬라이드쇼: `slideshow`

```json
"idle": {
  "enabled": true,
  "timeoutSec": 60,
  "mode": "slideshow",
  "slideshow": {
    "intervalSec": 6,
    "transition": "fade",
    "images": [
      "assets/idle/slide1.jpg",
      "assets/idle/slide2.jpg",
      "https://example.com/slide3.jpg"
    ]
  },
  "showHint": true,
  "hintText": "화면을 터치해 주세요"
}
```

- `intervalSec`: 이미지 한 장을 표시할 시간이며 0보다 커야 합니다.
- `transition`: `fade` 또는 `none`
- `images`: 한 개 이상의 로컬 에셋 또는 HTTP(S) 이미지 경로

### 폴더 자동 순회: `folder`

```json
"idle": {
  "enabled": true,
  "timeoutSec": 60,
  "modes": ["folder"],
  "folder": {
    "paths": ["C:/kiosk_media", "D:/event_media"],
    "intervalSec": 8,
    "shuffle": false,
    "includeImages": true,
    "includeVideos": true,
    "transition": "fade"
  }
}
```

| 키 | 기본값 | 설명 |
|---|---|---|
| `paths` | 필수 | 에셋 또는 운영체제 절대 폴더 경로 배열 |
| `path` | - | 기존 단일 폴더 호환 설정 |
| `intervalSec` | `8` | 이미지 한 장 표시 시간. 동영상은 재생 완료 후 다음 항목으로 이동 |
| `shuffle` | `false` | 진입할 때 재생 순서를 섞을지 여부 |
| `includeImages` | `true` | 이미지 포함 여부 |
| `includeVideos` | `true` | 동영상 포함 여부 |
| `transition` | `fade` | `fade` 또는 `none` |

지원 이미지 확장자: `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`, `.bmp`

지원 동영상 확장자: `.mp4`, `.mov`, `.m4v`, `.webm`, `.mkv`, `.avi`

폴더 바로 아래의 파일만 검색하며 하위 폴더는 검색하지 않습니다. Windows에서는
호환성이 좋은 MP4(H.264) 동영상을 권장합니다.

`assets/idle/`을 사용할 경우 파일을 프로젝트에 추가한 후 반드시 앱을 다시 빌드해야
합니다. Windows나 macOS에서 절대 경로를 사용하면 패키지를 다시 만들지 않고 해당
폴더의 미디어를 교체할 수 있습니다. Android 외부 폴더는 별도 저장소 권한과 단말기별
경로 구성이 필요하므로 기본 패키지에서는 `assets/idle/` 사용을 권장합니다.

### 웹페이지 대기화면: `url`

```json
"idle": {
  "enabled": true,
  "timeoutSec": 60,
  "mode": "url",
  "url": "https://example.com/attract",
  "showHint": true,
  "hintText": "화면을 터치해 주세요"
}
```

### 포토갤러리 게시물 대기화면: `gallery`

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

최신 게시물 본문의 사진을 순환하며 하단에 게시물 제목을 표시합니다.
`lookbackDays`는 갱신 시점의 현재 시각부터 과거 며칠까지의 게시물을 선택합니다.
조건에 맞는 게시물이 없거나 `minPosts`보다 적으면 최신순으로 최소 개수까지 보충합니다.
`maxPosts`는 최종 게시물 수의 상한이므로 `minPosts`보다 크거나 같아야 합니다.
`lookbackDays`를 생략하면 기존처럼 최신 게시물을 `maxPosts`개까지 읽습니다.
기본 5분마다 게시판을 갱신하지만 현재 표시 중인 사진과 슬라이드 위치는 유지합니다.
갱신 실패 시에도 기존 재생 목록은 중단하지 않습니다.
`shuffle`이 `true`이면 재생 목록을 미리 섞으며, 갱신 시 기존 순서와 현재 위치를 유지합니다.
키보드 좌우 방향키와 화면 좌우 스와이프로 이전·다음 사진을 이동할 수 있습니다.
보호기를 닫았다 다시 열어도 마지막으로 보던 사진부터 이어집니다.
`maxImages`는 한 번에 순환할 최대 사진 수입니다.
현재 기능은 그누보드 갤러리 구조를 기준으로 하므로 사이트 스킨이 변경되면 앱의
갤러리 파서도 수정해야 할 수 있습니다.

### 복수 모드 조합

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

세 모드의 콘텐츠는 `modes` 배열 순서대로 하나의 재생 목록으로 합쳐집니다.
`url`은 반드시 단독 모드여야 하며 `image`, `none`도 복수 조합에 사용할 수 없습니다.
기존 `mode`, `folder.path`, `gallery.url` 형식도 계속 지원합니다.

## 8. 용도별 설정 예

### 하단 툴바와 메뉴 상태 유지

```json
"layout": {
  "navPosition": "bottom",
  "barHeight": 96,
  "buttonAlignment": "stretch",
  "showHistoryButtons": true,
  "showKeyboardToggle": true,
  "keepStateOnTap": true,
  "toolbarInitiallyHidden": true,
  "toolbarAutoHideSec": 10
}
```

### 왼쪽 세로 툴바

```json
"layout": {
  "navPosition": "left",
  "sideWidth": 260,
  "buttonHeight": 88,
  "buttonGap": 12,
  "buttonAlignment": "start",
  "showHistoryButtons": true,
  "showKeyboardToggle": true
}
```

### 대기화면 사용 안 함

```json
"idle": {
  "enabled": false,
  "mode": "none"
}
```

## 9. 완성 예제

아래 예제는 그대로 복사한 뒤 URL과 메뉴 이름만 바꾸어 사용할 수 있습니다.

```json
{
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
    "keepStateOnTap": true,
    "toolbarInitiallyHidden": true,
    "toolbarAutoHideSec": 10,
    "barColor": "#1f2937",
    "buttonColor": "#374151",
    "buttonForegroundColor": "#ffffff",
    "selectedButtonColor": "#2563eb",
    "selectedButtonForegroundColor": "#ffffff"
  },
  "idle": {
    "enabled": true,
    "timeoutSec": 60,
    "startOnLaunch": true,
    "mode": "slideshow",
    "slideshow": {
      "intervalSec": 6,
      "transition": "fade",
      "images": [
        "assets/idle/slide1.jpg",
        "assets/idle/slide2.jpg",
        "assets/idle/slide3.jpg"
      ]
    },
    "showHint": true,
    "hintText": "화면을 터치해 주세요"
  },
  "items": [
    {
      "id": "home",
      "title": "홈",
      "url": "https://example.com",
      "icon": "icon:home"
    },
    {
      "id": "notice",
      "title": "공지사항",
      "url": "https://example.com/notice",
      "icon": "icon:notice"
    },
    {
      "id": "gallery",
      "title": "사진",
      "url": "https://example.com/gallery",
      "icon": "icon:gallery",
      "keepStateOnTap": true
    }
  ]
}
```

## 10. 변경 후 확인 목록

- JSON 문법 검사에서 오류가 없는지
- 첫 번째 메뉴가 원하는 홈 페이지인지
- 모든 메뉴의 제목, 아이콘과 URL이 맞는지
- 메뉴를 이동한 뒤 돌아왔을 때 상태 유지 방식이 의도한 것과 같은지
- 뒤로·앞으로 버튼과 가상 키보드 버튼이 보이는지
- 툴바를 숨기고 복원해도 WebView 상태가 유지되는지
- 대기화면 진입 시간, 이미지 순서, 동영상 재생과 터치 해제가 정상인지
- 앱을 재부팅한 후에도 동일하게 동작하는지

## 11. 문제 해결

### 앱에 설정 오류 화면이 표시됨

- 필수 필드인 `id`, `title`, `url`이 비어 있지 않은지 확인합니다.
- `items`가 배열이며 한 개 이상의 메뉴를 포함하는지 확인합니다.
- 숫자 필드에 문자열을 넣거나 bool 필드에 `"true"`를 넣지 않았는지 확인합니다.
- `navPosition`, `buttonAlignment`, `mode`, `transition`의 철자를 확인합니다.
- 백업한 설정으로 되돌린 뒤 한 항목씩 다시 수정합니다.

### 변경 내용이 반영되지 않음

- 앱을 작업 관리자나 활동 관리자에서도 완전히 종료했는지 확인합니다.
- 실제 실행 중인 배포 폴더의 `menu.json`을 수정했는지 확인합니다.
- Android와 macOS에서는 원본 설정 수정 후 새 패키지를 빌드했는지 확인합니다.
- 개발 중 핫 리로드(`r`)가 아닌 핫 리스타트(`R`)를 실행했는지 확인합니다.

### HTTP 사이트가 열리지 않음

운영 사이트는 HTTPS 사용을 권장합니다. Android 9 이상에서 HTTP를 사용하려면
`AndroidManifest.xml`에 `android:usesCleartextTraffic="true"` 또는 제한적인
`networkSecurityConfig` 설정을 추가하고 APK를 다시 빌드해야 합니다.

### 외부 폴더의 미디어가 보이지 않음

- 절대 경로와 폴더 접근 권한을 확인합니다.
- 지원되는 확장자인지 확인합니다.
- 파일이 지정 폴더의 바로 아래에 있는지 확인합니다.
- `includeImages` 또는 `includeVideos`가 `true`인지 확인합니다.
