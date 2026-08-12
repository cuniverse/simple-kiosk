# Simple Kiosk Windows 최초 설치 가이드

이 문서는 `simple-kiosk-windows-<version>.zip` 배포 파일을 처음 설치하는 운영
담당자를 위한 안내서입니다.

Simple Kiosk는 별도 설치 프로그램이 없는 **포터블 앱**입니다. 압축을 푼 폴더
전체가 프로그램이므로 `simple_kiosk.exe`만 따로 복사하거나 실행에 필요한 파일을
삭제하면 정상적으로 실행되지 않습니다.

## 자동 업데이트용 권장 설치

직접 실행 방식도 계속 사용할 수 있지만 자동 업데이트와 롤백을 사용하려면 관리자
PowerShell에서 압축을 푼 폴더를 현재 위치로 두고 다음을 실행합니다.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\updater\install-launcher.ps1 -PackageDirectory . -Version 1.2.2
```

이후 `C:\ProgramData\SimpleKiosk\SimpleKiosk.cmd`를 Windows 시작 프로그램이나 작업
스케줄러에 등록합니다. 운영 데이터는 프로그램 버전 폴더와 분리됩니다.

### 관리자 PIN 설정

PIN은 평문으로 저장하지 않습니다. SHA-256을 시스템 환경변수로 등록하고 앱을 다시
시작하면 툴바에 업데이트 관리 버튼이 나타납니다.

```powershell
$pin = Read-Host '관리자 PIN'
$bytes = [Text.Encoding]::UTF8.GetBytes($pin)
$hash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-', '').ToLower()
[Environment]::SetEnvironmentVariable('SIMPLE_KIOSK_ADMIN_PIN_HASH', $hash, 'Machine')
```

자동 업데이트 기본값은 OFF입니다. 관리자가 켜면 stable Release를 6시간마다 확인하고
다운로드하며, 기본 설정상 02:00~05:00 사이 화면 보호기 상태에서만 설치합니다.

### 기존 설정 마이그레이션

기존 설치 버전의 수정되지 않은 원본 기본 설정을 확보한 경우에만 실행합니다.

```powershell
.\updater\migrate-menu-config.ps1 `
  -LegacyMenu 'C:\기존설치\data\flutter_assets\assets\config\menu.json' `
  -OriginalDefaults 'C:\백업\menu.original.json'
```

결과는 `config\menu.override.json`에 저장되고 원본 파일은 날짜별 `backups` 폴더에
보관됩니다. 원본 기본 설정이 없다면 자동 추정하지 말고 수동 검토해야 합니다.

```text
C:\ProgramData\SimpleKiosk\
  current.json
  config\menu.override.json
  config\update-policy.json
  media\
  state\update-state.json
  logs\updater.log
  versions\<version>\
```

외부 미디어는 오버라이드에서 `media/...` 상대 경로로 지정할 수 있습니다.

## 1. 패키지 구성

- `simple_kiosk.exe`: 애플리케이션 실행 파일
- `flutter_windows.dll` 및 기타 DLL: 실행에 필요한 라이브러리
- `data/`: 앱 리소스와 설정 파일
- `INSTALL_GUIDE.md`: 현재 설치 가이드
- `MENU_CONFIG_GUIDE.md`: 메뉴·툴바·대기화면 설정 상세 가이드
- `SHA256SUMS.txt`: 실행 파일 무결성 확인용 SHA-256 값

## 2. 지원 환경

- Windows 10/11 64비트
- 표시할 웹사이트에 접속할 수 있는 네트워크
- Microsoft Edge WebView2 Runtime

Windows 11에는 WebView2 Runtime이 일반적으로 포함되어 있습니다. Windows 10이거나
WebView 관련 오류가 발생하는 PC에서는 PowerShell 또는 터미널에서 다음 명령으로
설치합니다.

```powershell
winget install --id Microsoft.EdgeWebView2Runtime -e
```

`winget`을 사용할 수 없다면 Microsoft 공식 WebView2 Runtime 다운로드 페이지에서
Evergreen Standalone Installer(x64)를 내려받아 설치하세요.

## 3. 최초 설치

1. 배포받은 ZIP 파일을 대상 PC로 복사합니다.
2. ZIP 파일을 마우스 오른쪽 버튼으로 클릭하고 **속성**을 엽니다.
3. 속성 아래쪽에 **차단 해제**가 표시되면, 배포 출처를 확인한 후 체크하고
   **적용**을 누릅니다.
4. ZIP의 모든 파일을 `C:\SimpleKiosk` 같은 전용 폴더에 완전히 압축 해제합니다.
5. 필요하면 아래 방법으로 실행 파일의 무결성을 확인합니다.
6. `C:\SimpleKiosk\simple_kiosk.exe`를 실행합니다.

### SHA-256 무결성 확인

압축을 푼 폴더에서 PowerShell을 열고 다음 명령을 실행합니다.

```powershell
$expected = ((Get-Content .\SHA256SUMS.txt -Raw).Trim() -split '\s+')[0]
$actual = (Get-FileHash .\simple_kiosk.exe -Algorithm SHA256).Hash.ToLower()
$actual -eq $expected
```

결과가 `True`이면 패키지에 기록된 값과 일치합니다. `False`이면 파일을 실행하지
말고 배포 담당자에게 새 패키지를 요청하세요.

바탕화면 바로가기가 필요하면 `simple_kiosk.exe`를 마우스 오른쪽 버튼으로 클릭한
후 **보내기 > 바탕 화면에 바로 가기 만들기**를 선택합니다.

## 4. 최초 실행 확인

앱을 실행한 후 다음 항목을 확인합니다.

1. 앱이 전체 화면으로 열리는지 확인합니다.
2. 하단 툴바와 웹페이지가 정상적으로 표시되는지 확인합니다.
3. 메뉴 이동과 뒤로/앞으로 기능을 확인합니다.
4. 가상 키보드 켜기/끄기 기능을 확인합니다.
5. 툴바를 감췄을 때 웹페이지가 다시 로드되거나 현재 상태를 잃지 않는지 확인합니다.
6. 숨김 상태의 오버레이 아이콘이 표시되고 네 모서리로 드래그되는지 확인합니다.
7. 대기화면을 사용하는 경우 설정된 시간 후 정상적으로 전환되는지 확인합니다.
8. 방화벽 또는 보안 프로그램 알림이 나타나면 조직 정책에 따라 웹 접속을 허용합니다.

화면이 흰색이거나 WebView 관련 오류가 발생하면 앱을 종료하고 WebView2 Runtime을
설치한 후 다시 실행합니다.

## 5. 메뉴 및 URL 설정 변경

자동 업데이트 설치의 운영 오버라이드는 다음 위치에 있습니다.

```text
C:\ProgramData\SimpleKiosk\config\menu.override.json
```

앱을 완전히 종료한 상태에서 파일을 백업한 후 UTF-8 형식으로 편집하세요. JSON 문법에
오류가 있으면 메뉴가 로드되지 않을 수 있습니다. 변경 사항은 앱을 다시 실행해야
반영됩니다.

주요 설정은 다음과 같습니다.

- `items[].title`: 메뉴 이름
- `items[].url`: 연결할 URL(운영 환경에서는 HTTPS 권장)
- `items[].icon`: 메뉴 아이콘
- `layout`: 메뉴 위치, 크기, 색상 및 표시 옵션
- `idle`: 대기화면과 전환 시간

전체 필드와 용도별 예시는 패키지에 포함된 `MENU_CONFIG_GUIDE.md`를 참고하세요.

## 6. Windows 시작 시 자동 실행(선택)

1. `Win + R`을 누릅니다.
2. `shell:startup`을 입력하고 Enter를 누릅니다.
3. `C:\ProgramData\SimpleKiosk\SimpleKiosk.cmd`의 바로가기를 복사합니다.

실행 파일 자체를 시작프로그램 폴더로 옮기면 안 됩니다. 반드시 설치 폴더의 실행
파일을 가리키는 바로가기를 사용하세요.

## 7. 업데이트

관리자 화면에서 자동 업데이트를 켜거나 `지금 업데이트 확인`을 사용합니다. 설치는
운영 설정과 미디어를 보존하며 시작 검증에 실패하면 이전 정상 버전으로 롤백합니다.

DLL 또는 `data` 폴더 일부만 덮어쓰지 마세요. 실행 파일과 동봉 파일의 버전이 다르면
앱이 시작되지 않을 수 있습니다.

## 8. 제거

1. Simple Kiosk를 종료합니다.
2. 설치 폴더(예: `C:\SimpleKiosk`)를 삭제합니다.
3. 바탕화면과 시작프로그램에 만든 바로가기를 삭제합니다.

별도의 Windows 제거 프로그램이나 서비스는 없습니다.

## 9. 문제 해결

### 앱이 실행되지 않음

- ZIP을 완전히 압축 해제했는지 확인합니다.
- `data` 폴더와 DLL 파일이 실행 파일 옆에 있는지 확인합니다.
- WebView2 Runtime을 설치하거나 복구합니다.
- 보안 프로그램이 실행 파일 또는 DLL을 격리했는지 확인합니다.

### 웹사이트가 표시되지 않음

- PC의 인터넷 연결과 대상 URL을 Microsoft Edge에서 확인합니다.
- 사내 프록시, 방화벽 및 인증서 정책을 확인합니다.
- `menu.override.json`의 URL과 JSON 문법을 확인합니다.

### 설정 변경이 반영되지 않음

- 앱을 작업 관리자에서도 완전히 종료한 후 다시 실행합니다.
- `C:\ProgramData\SimpleKiosk\config\menu.override.json`을 수정했는지 확인합니다.

### Windows 보안 경고가 표시됨

기본 빌드는 코드 서명 인증서로 서명되지 않을 수 있습니다. 배포 출처와 SHA-256 값을
확인할 수 없는 파일은 실행하지 마세요. 조직 외부에 배포할 때는 코드 서명 인증서로
실행 파일과 배포 패키지에 서명하는 것을 권장합니다.

## 10. 운영 참고

- 앱 종료: `Alt + F4`
- 개발 및 점검용 창 모드: 실행 전에 `SIMPLE_KIOSK_WINDOWED=1` 환경변수 설정
- 장시간 운영 단말기는 절전 및 화면 꺼짐 정책을 별도로 조정
- 운영 단말기에서는 Windows 자동 업데이트 재시작 정책과 네트워크 복구 정책을 확인
