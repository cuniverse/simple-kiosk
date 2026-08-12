# Simple Kiosk Windows 최초 설치 가이드

이 문서는 `simple-kiosk-windows-x64-1.0.0.zip` 배포 파일을 처음 설치하는 운영 담당자를 위한 안내서입니다.
이 배포본은 별도 설치 프로그램이 없는 **포터블 앱**입니다. 압축을 푼 폴더 전체가 프로그램이므로 파일 일부만 복사하면 실행되지 않습니다.

## 1. 지원 환경

- Windows 10/11 64비트
- 인터넷 연결(표시할 웹사이트 접속용)
- Microsoft Edge WebView2 Runtime

Windows 11에는 WebView2 Runtime이 일반적으로 포함되어 있습니다. Windows 10 또는 실행 오류가 발생하는 PC에서는 다음 명령으로 설치합니다.

```powershell
winget install --id Microsoft.EdgeWebView2Runtime -e
```

`winget`을 사용할 수 없다면 Microsoft의 WebView2 Runtime 공식 다운로드 페이지에서 Evergreen Standalone Installer(x64)를 설치하세요.

## 2. 설치

1. `simple-kiosk-windows-x64-1.0.0.zip`을 대상 PC로 복사합니다.
2. ZIP 파일을 마우스 오른쪽 버튼으로 클릭하고 **속성**을 엽니다.
3. 속성 아래쪽에 **차단 해제**가 표시되면 체크하고 **적용**합니다.
4. ZIP의 모든 파일을 예를 들어 `C:\SimpleKiosk`에 압축 해제합니다.
5. `C:\SimpleKiosk\simple_kiosk.exe`를 실행합니다.

다음 항목은 항상 같은 폴더에 있어야 합니다.

- `simple_kiosk.exe`
- `flutter_windows.dll` 및 기타 DLL 파일
- `data` 폴더 전체

바탕화면에 바로가기가 필요하면 `simple_kiosk.exe`를 우클릭하고 **보내기 > 바탕 화면에 바로 가기 만들기**를 선택합니다.

## 3. 최초 실행 확인

앱 실행 후 다음을 확인합니다.

1. 전체 화면으로 열리는지 확인합니다.
2. 하단 메뉴와 웹페이지가 정상 표시되는지 확인합니다.
3. 각 메뉴를 눌러 사이트 접속, 뒤로/앞으로, 가상 키보드를 점검합니다.
4. 방화벽 또는 보안 프로그램 알림이 나타나면 조직 정책에 따라 웹 접속을 허용합니다.

화면이 흰색이거나 WebView 관련 오류가 발생하면 앱을 종료하고 WebView2 Runtime을 설치한 뒤 다시 실행합니다.

## 4. 메뉴 및 URL 설정 변경

자동 업데이트 설치의 운영 오버라이드는 다음 위치에 있습니다.

```text
C:\ProgramData\SimpleKiosk\config\menu.override.json
```

변경 전 파일을 백업하고, 앱을 완전히 종료한 상태에서 UTF-8 형식으로 편집하세요. JSON 문법 오류가 있으면 메뉴가 로드되지 않을 수 있습니다. 변경 후 앱을 다시 실행해야 반영됩니다.

주요 설정:

- `items[].title`: 메뉴 이름
- `items[].url`: 연결할 URL(운영 환경에서는 HTTPS 권장)
- `items[].icon`: 메뉴 아이콘
- `layout`: 메뉴 위치, 크기, 색상, 표시 옵션
- `idle`: 대기 화면과 전환 시간

전체 설정 설명은 소스 저장소의 `docs/MANUAL.md`를 참고하세요.

## 5. Windows 시작 시 자동 실행(선택)

1. `Win + R`을 누릅니다.
2. `shell:startup`을 입력하고 Enter를 누릅니다.
3. 시작프로그램 폴더에 `C:\ProgramData\SimpleKiosk\SimpleKiosk.cmd`의 바로가기를 복사합니다.

실행 파일 자체를 시작프로그램 폴더로 옮기면 안 됩니다. 반드시 설치 폴더에 있는 실행 파일을 가리키는 바로가기를 사용하세요.

## 6. 업데이트

관리자 화면에서 자동 업데이트를 켜거나 `지금 업데이트 확인`을 사용합니다. 자동
업데이트 설치는 운영 오버라이드와 `media` 폴더를 변경하지 않으며 실패 시 이전 정상
버전으로 롤백합니다.

DLL이나 `data` 폴더 일부만 덮어쓰지 마세요. 실행 파일과 동봉 파일의 버전이 다르면 앱이 시작되지 않을 수 있습니다.

## 7. 제거

앱을 종료하고 설치 폴더(예: `C:\SimpleKiosk`)와 생성한 바로가기를 삭제하면 됩니다. 별도의 Windows 제거 프로그램이나 서비스는 없습니다.

## 8. 문제 해결

### 앱이 실행되지 않음

- ZIP을 완전히 압축 해제했는지 확인합니다.
- `data` 폴더와 DLL 파일이 실행 파일 옆에 있는지 확인합니다.
- WebView2 Runtime을 설치하거나 복구합니다.
- 보안 프로그램이 실행 파일 또는 DLL을 격리했는지 확인합니다.

### 웹사이트가 표시되지 않음

- PC의 인터넷 연결과 대상 URL을 Edge 브라우저에서 확인합니다.
- 사내 프록시, 방화벽, 인증서 정책을 확인합니다.
- `menu.override.json`의 URL과 JSON 문법을 확인합니다.

### 설정 변경이 반영되지 않음

- 앱을 작업 관리자에서도 완전히 종료한 뒤 다시 실행합니다.
- `C:\ProgramData\SimpleKiosk\config\menu.override.json`을 편집했는지 확인합니다.
