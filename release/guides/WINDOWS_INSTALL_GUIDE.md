# 여의도성당Signage Windows 최초 설치 가이드

이 문서는 `simple-kiosk-windows-setup-<version>.exe` 또는 ZIP 배포 파일을 처음 설치하는 운영
담당자를 위한 안내서입니다.

일반 사용자는 installer EXE 사용을 권장합니다. 다운로드 직후 installer 실행 시에는
Windows SmartScreen 확인이 한 번 표시될 수 있지만 설치 후 바로가기 실행과 앱 내부
자동 업데이트에서는 다운로드한 실행 파일을 직접 열지 않습니다.

installer는 앱 실행에 필요한 Visual C++ Runtime DLL을 앱 폴더에 함께 설치하고,
Microsoft Visual C++ Redistributable을 자동 설치하거나 업데이트합니다. 또한
Microsoft Edge WebView2 Runtime을 확인하고 누락된 PC에서 Microsoft 서명 Evergreen
Bootstrapper를 자동 실행합니다. WebView2 자동 설치에는 인터넷 연결이 필요합니다.

기본 설치 위치는 `%LOCALAPPDATA%\Programs\SimpleKiosk`이며 관리자 권한이 필요하지
않습니다. ZIP은 포터블 설치나 복구가 필요한 운영자를 위한 보조 배포본입니다.

## installer 권장 설치

1. `simple-kiosk-windows-setup-<version>.exe`를 실행합니다.
2. 최초 SmartScreen 화면이 표시되면 배포 출처를 확인한 뒤 실행합니다.
3. 설치 위치, Windows 로그인 시 자동 실행, 바탕화면 바로가기 생성 여부를 선택합니다.
4. 설치 완료 후 시작 메뉴의 `여의도성당Signage`를 실행합니다.

installer는 자동 업데이트용 런처와 버전 포인터를 자동 구성합니다. **Windows 로그인 시
여의도성당Signage 자동 실행**은 기본적으로 선택되며, 필요하지 않으면 설치 옵션에서 해제할 수
있습니다. 같은 PC에 기존 설치 정보가 있으면 그 설치 위치를 먼저 확인해 기본 경로로
사용합니다. 설치 위치를 바꾸거나 자동 실행을 해제하면 이전 `Simple Kiosk` 및 `여의도성당Signage` 시작프로그램
바로가기를 제거하고, 자동 실행을 선택한 경우에만 새 설치 경로로 다시 등록합니다.
자동 업데이트가 새 버전을 설치해도 시작프로그램은 특정 버전의 EXE가 아닌 고정된
`ysignage_launcher.exe`를 실행하므로 변경된 현재 버전이 다음 실행부터 자동 선택됩니다.
기존 `Simple Kiosk` 이름의 바탕화면·시작프로그램 바로가기와 시작 메뉴 그룹은
업데이트 성공 후 `여의도성당Signage` 이름으로 자동 변경됩니다.
일반 실행과 자동 업데이트 과정에서는 PowerShell이나 CMD 스크립트를 사용하지 않습니다.
자동 업데이트는 `ysignage_updater.exe`가 ZIP 검증·설치·재시작·정상 실행 확인 및
실패 시 이전 버전 복구를 처리합니다.

가상 키보드는 Windows 기본 화면 키보드를 사용합니다. 프로그램의 **설정 > 가상 키보드
방식** 또는 웹 관리자 페이지의 **사이니지 구성 > 레이아웃 > 키보드 방식**에서 기존
앱 내장 키보드로 변경할 수 있습니다.

사용자 매뉴얼은 설치 폴더의 `USER_MANUAL.html`과 시작 메뉴의 **여의도성당Signage 사용자
매뉴얼**에서 기본 브라우저로 열 수 있습니다. 인터넷 연결이 필요 없는 단일 HTML이며,
자동 업데이트 후에는 새 버전에 포함된 매뉴얼로 함께 갱신됩니다. 포터블 ZIP에도 같은
파일이 포함됩니다.

실행 중에는 Windows 알림 영역에 **여의도성당Signage** 트레이 아이콘이 표시됩니다. 창 닫기,
`Alt + F4`는 화면만 감추고 프로세스를 유지합니다.
트레이 메뉴에서 사이니지 보이기·감추기, 설정, 사용자 매뉴얼을 열 수 있으며 프로그램을
완전히 끝낼 때는 설정 화면 하단 또는 트레이 메뉴의 **완전 종료**를 사용합니다.

### 삭제

Windows 설정의 **앱 > 설치된 앱 > 여의도성당Signage > 제거** 또는 시작 메뉴의 제거 항목을
사용합니다. 제거하면 시작 메뉴·바탕화면·시작프로그램 바로가기와 설치된 모든 앱 버전,
업데이트 캐시는 항상 삭제됩니다.

제거 과정에서 설정과 사용자 파일도 함께 삭제할지 묻습니다. 기본값인 **아니요**를
선택하면 `config`, `media`, `state`, `logs`, `diagnostics`, `backups`를 보존하므로 나중에
같은 위치에 재설치할 때 다시 사용할 수 있습니다. **예**를 선택하면 해당 데이터까지
삭제합니다. 자동 제거처럼 확인창이 표시되지 않는 경우에는 안전하게 사용자 데이터를
보존합니다.

## ZIP 수동 설치

ZIP의 `ysignage.exe`를 바로 실행하는 완전한 포터블 방식도 계속 지원합니다. 이 경우
설정과 로그는 압축을 푼 실행 파일 폴더에 저장됩니다. 포터블 폴더에서 자동 업데이트와
롤백까지 사용하려면 PowerShell에서 다음을 한 번 실행합니다.

포터블 ZIP에도 Visual C++ Runtime DLL과 Microsoft Visual C++ Redistributable이 포함되어 있습니다.
새 PC에서는 `InstallPrerequisites.cmd`를 먼저 실행해 VC++ Runtime을 설치하거나 업데이트합니다. WebView2가 없는 경우에는
먼저 ZIP 루트의 `InstallPrerequisites.cmd`를 실행하면 포함된 Microsoft 서명 Bootstrapper가
WebView2 Runtime을 사용자별로 설치합니다. 인터넷 연결이 필요합니다.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\updater\install-launcher.ps1 -PackageDirectory . -Version <version>
```

이후 압축을 푼 **프로그램 폴더의 `ysignage_launcher.exe`**를 Windows 시작 프로그램이나
작업 스케줄러에 등록합니다. 설정·로그·업데이트 파일도 기본적으로 이 폴더 아래에
저장됩니다. 별도 위치가 필요할 때만 `SIMPLE_KIOSK_DATA_DIR` 환경변수를 지정합니다.

### Windows 키오스크 잠금

기본값 `layout.windowsKioskLockdown: true`에서는 사이니지 표시 중 `Alt+Tab`, `Alt+Esc`,
`Alt+F4`, `Win` 키 조합(`Win+Tab`, `Win+D`, `Win+R` 포함),
`Ctrl+Esc`, `Ctrl+Shift+Esc`와 앱 실행 전용 키를 차단합니다. 트레이·관리 API·숨김 제스처로
사이니지를 감추면 잠금과 선택적인 최상위 상태가 즉시 해제되고 다시 표시하면 자동 적용됩니다.
웹 관리자의 **레이아웃** 설정에서 `Windows 키 및 조합`, `Alt+Tab`, `Alt+Esc`,
`Alt+F4`, `Alt+Space`, `Ctrl+Esc`, `Ctrl+Shift+Esc`와 각 앱·메일·브라우저 실행 키를
체크박스로 개별 허용하거나 차단할 수 있습니다. `Windows 키오스크 잠금`은 이 항목들의
전체 스위치이며, 기존 설정 파일은 모든 항목을 차단하는 이전 동작을 그대로 유지합니다.
`windowsPreventScreenSaver`와 `windowsPreventDisplaySleep`의 기본값은 모두 `true`이며,
사이니지가 보이는 동안 각각 Windows 화면보호기와 화면 자동 끄기를 방지합니다. 사이니지를
감추거나 종료하면 시스템의 원래 전원 정책이 즉시 다시 적용됩니다.

Windows 보안 화면인 `Ctrl+Alt+Del`, 서비스·예약 작업 등 외부 정책으로 실행되는 프로세스는
일반 프로그램의 키보드 훅으로 차단할 수 없습니다. 완전한 단말 잠금이 필요한 운영 환경에서는
Windows Assigned Access 또는 Shell Launcher와 AppLocker 정책을 함께 적용하세요.

화면이 투명해지거나 입력을 받지 않는 비상 상황에서는 화면의 왼쪽 위와 오른쪽 위 모서리를
동시에 8초간 계속 누르거나 `Ctrl+Alt+Shift+F4`를 3초간 계속 누르면 Dart·WebView 상태와
무관한 Windows 네이티브 경로로 프로세스를 강제 종료합니다. 한쪽 터치를 떼거나 모서리 밖으로
이동하면 8초 대기는 취소됩니다. 정상 종료가 아니므로 복구가 불가능할 때만 사용하세요.
`Ctrl+Alt+Del` 보안 화면에서
작업 관리자를 열어 `ysignage.exe`를 종료하는 Windows 기본 복구 방법도 항상 사용할 수 있습니다.

### 관리자 PIN 설정

최초 관리자 PIN은 `1259`입니다. 관리자 화면의 `PIN 변경`에서 숫자 4~12자리로
변경할 수 있습니다. 변경 PIN은 평문이 아닌 솔트가 적용된 PBKDF2-HMAC-SHA256
해시로 `<프로그램 폴더>\config\admin-pin.json`에 저장됩니다. 이 파일을 삭제하면
다음 인증부터 기본 PIN `1259`로 돌아갑니다.

### 관리 API와 관리자 페이지

관리 API는 기본적으로 사용하며 모든 IPv4 인터페이스의 TCP `80` 포트에서 대기합니다.
프로그램의 **설정 > 관리 API / 관리자 페이지**에서 사용 여부와 포트를 변경할 수 있고,
설정은 `<프로그램 폴더>\config\admin-api.json`에 저장됩니다. 포트가 이미 사용 중이면
사이니지는 계속 실행되며 설정 화면에 API 시작 오류가 표시됩니다.

mDNS도 기본으로 사용하며 `ysignage.local`을 관리 API의 로컬 네트워크 주소로
광고합니다. 따라서 기본 포트에서는 같은 네트워크의 브라우저로
`http://ysignage.local`에 접속할 수 있습니다. 여러 대를 운영하면 각 장치의 mDNS
호스트 이름을 `ysignage-1.local`, `ysignage-2.local`처럼 다르게 설정하세요.

다른 PC의 브라우저에서 `http://ysignage.local`또는 `http://<사이니지 IP>:<포트>/`에 접속합니다. 로그인 암호는
프로그램 설정과 동일한 관리자 PIN입니다. 관리자 페이지에서 상태 확인, 메뉴 설정 변경,
화면 보이기·감추기, 업데이트, 재시작과 완전 종료를 수행할 수 있습니다.
로그인 세션은 마지막 활동 후 30분 동안 유효합니다. 관리자 탭 이동, 입력·클릭, API 요청이
있으면 자동 연장되며 설정 적용으로 관리 API가 다시 시작되어도 유지됩니다. 작업 없이 30분이
지나 실제 세션이 만료되면 페이지를 초기화하지 않고 PIN 재인증 오버레이를 표시하므로 저장하지
않은 설정을 유지한 상태로 작업을 계속할 수 있습니다.
사이니지 구성 화면은 기본값과 오버라이드를 병합한 실제 적용 구성을 표시하며,
레이아웃·화면보호기·언어·메뉴 항목별 폼과 고급 JSON 편집을 제공합니다.
전체 설정뿐 아니라 레이아웃·화면보호기·언어·언어별 메뉴와 개별 설정값을 각각
프로그램 기본값으로 되돌릴 수 있습니다. 기본 언어·메뉴와 ID가 일치하는 항목은 메뉴
전체 또는 메뉴 내부의 개별 값만 복원할 수 있으며 저장 전까지 실제 설정에는 반영되지 않습니다.

REST 클라이언트는 먼저 `POST /api/login`에 `{"pin":"1259"}` 형식으로 로그인한 뒤 반환된
토큰을 `Authorization: Bearer <token>` 헤더로 보냅니다. 자동화 도구에서는
`X-Admin-Pin: <PIN>` 또는 HTTP Basic 인증의 암호로 PIN을 직접 사용할 수도 있습니다.

| 메서드와 경로 | 기능 |
|---|---|
| `GET /api/status` | 실행·화면·버전·업데이트 상태 확인 |
| `GET /api/config` | 현재 `menu.override.json` 확인 |
| `GET /api/config/effective` | 기본값과 오버라이드를 병합한 실제 적용 메뉴 설정 확인 |
| `GET /api/config/defaults` | 프로그램에 포함된 기본 메뉴 설정 확인(복원 UI 기준값) |
| `PUT /api/config` | 메뉴 설정 검증·저장·즉시 적용 |
| `POST /api/config/validate` | 전체 메뉴 설정을 저장하지 않고 유효성 검사 |
| `GET`, `PUT /api/config-backup` | 통합 설정 백업 다운로드·검증 후 가져오기 |
| `POST /api/config-backup/restore-previous` | 마지막 변경 전 설정 복원 |
| `GET /api/diagnostics` | 시스템 정보와 분류 로그가 포함된 진단 보고서 다운로드 |
| `GET /api/logs/{app,webview,update,api}` | 분류별 로그 다운로드 |
| `GET`, `PUT /api/server-settings` | 관리 API·mDNS 사용 여부, 포트와 호스트 이름 확인·변경 |
| `POST /api/actions/show` | 사이니지 화면 표시 |
| `POST /api/actions/hide` | 사이니지 화면 감추기 |
| `POST /api/actions/update` | 업데이트 확인·다운로드·설치 |
| `POST /api/actions/restart` | 프로그램 재시작 |
| `POST /api/actions/shutdown` | 프로그램 완전 종료 |

외부 접속이 차단되면 관리자 PowerShell에서 실제 사용 포트에 맞춰 방화벽 규칙을 추가합니다.

```powershell
New-NetFirewallRule -DisplayName "여의도성당Signage Admin API" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80
New-NetFirewallRule -DisplayName "여의도성당Signage mDNS" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 5353
```

관리 페이지는 TLS가 없는 HTTP이므로 인터넷에 직접 노출하지 말고 신뢰할 수 있는 내부망과
제한된 방화벽 범위에서만 사용하세요. 설치 직후 기본 PIN도 반드시 변경하는 것을 권장합니다.

자동 업데이트 기본값은 OFF입니다. 관리자가 켜면 stable Release를 6시간마다 확인하고
다운로드하며, 기본 설정상 02:00~05:00 사이 화면 보호기 상태에서만 설치합니다.
관리자 화면에서 확인 주기, 설치 시간대, 유휴 설치 여부, 버전·로그 보관 기간을 변경할
수 있습니다. 별도 데이터 폴더에 제한된 ACL이 필요하면 설치 명령에
`-DataRoot <경로> -ConfigureAcl`을 추가합니다.

### 수동 복구와 진단 자료

웹 관리자 페이지의 **백업·진단** 탭에서는 적용 중인 메뉴·언어·툴바·관리 API·
업데이트 정책을 하나의 JSON 파일로 내보내거나 가져올 수 있습니다. 가져오기 전에
전체 설정을 검증하며 문제가 생기면 **직전 설정 복원**을 사용할 수 있습니다.
관리자 PIN은 백업에 포함되지 않습니다. 같은 탭에서 분류별 로그와 시스템 정보를
포함한 진단 보고서도 내려받을 수 있습니다.

설치된 버전을 확인하거나 특정 정상 버전으로 되돌리려면 다음을 실행합니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\updater\recover.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\updater\recover.ps1 -Version 1.2.8
```

관리자 화면의 `진단 자료 내보내기` 또는 아래 명령은 설정 정책, 상태, 로그를 ZIP으로
만듭니다. 메뉴 오버라이드는 기본적으로 제외되며 필요할 때만 `-IncludeMenuConfig`를
지정합니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\updater\export-diagnostics.ps1
```

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
<ysignage.exe가 들어 있는 프로그램 폴더>\
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

- `ysignage.exe`: 애플리케이션 실행 파일
- `simple_kiosk.exe`: 1.2.11 자동 업데이트 검사용 호환 복사본
- `flutter_windows.dll`, `msvcp140.dll`, `vcruntime140*.dll` 및 기타 DLL: 실행에 필요한 라이브러리
- `data/`: 앱 리소스와 설정 파일
- `prerequisites/`: Microsoft 서명 VC++ Redistributable 및 WebView2 Evergreen Bootstrapper
- `InstallPrerequisites.cmd`: 포터블 PC의 VC++ Runtime 및 WebView2 확인·설치 도구
- `INSTALL_GUIDE.md`: 현재 설치 가이드
- `MENU_CONFIG_GUIDE.md`: 메뉴·툴바·대기화면 설정 상세 가이드
- `SHA256SUMS.txt`: 실행 파일 무결성 확인용 SHA-256 값

## 2. 지원 환경

- Windows 10/11 64비트
- 표시할 웹사이트에 접속할 수 있는 네트워크
- Microsoft Edge WebView2 Runtime

Visual C++ Runtime DLL은 installer와 포터블 ZIP에 포함됩니다. Windows 11에는 WebView2
Runtime이 일반적으로 포함되어 있으며 installer는 누락된 경우 자동 설치합니다. 자동 설치가
네트워크 또는 조직 정책으로 실패한 경우 PowerShell 또는 터미널에서 다음 명령으로 설치합니다.

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
6. 새 PC에서는 `InstallPrerequisites.cmd`를 먼저 실행해 VC++ Runtime과 WebView2를 준비합니다.
7. `C:\SimpleKiosk\ysignage.exe`를 실행합니다.

### SHA-256 무결성 확인

압축을 푼 폴더에서 PowerShell을 열고 다음 명령을 실행합니다.

```powershell
$expected = ((Get-Content .\SHA256SUMS.txt -Raw).Trim() -split '\s+')[0]
$actual = (Get-FileHash .\ysignage.exe -Algorithm SHA256).Hash.ToLower()
$actual -eq $expected
```

결과가 `True`이면 패키지에 기록된 값과 일치합니다. `False`이면 파일을 실행하지
말고 배포 담당자에게 새 패키지를 요청하세요.

바탕화면 바로가기가 필요하면 `ysignage.exe`를 마우스 오른쪽 버튼으로 클릭한
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
<프로그램 폴더>\config\menu.override.json
```

앱을 완전히 종료한 상태에서 파일을 백업한 후 UTF-8 형식으로 편집하세요. JSON 문법에
오류가 있으면 메뉴가 로드되지 않을 수 있습니다. 변경 사항은 앱을 다시 실행해야
반영됩니다.

주요 설정은 다음과 같습니다.

- `languages[]`: 화면보호기 해제 후 선택할 언어
- `languages[].defaultTopic`: 언어 선택 후 기본 주제. 생략하면 첫 주제 사용
- `languages[].topics[]`: 언어별 주제 버튼과 주제별 메뉴 구성
- `languages[].topics[].defaultMenu`: 주제 선택 후 처음 표시할 메뉴 ID
- `languages[].topics[].items[]`: 해당 언어·주제에서 사용할 메뉴 이름·URL·아이콘
- `languages[].hidden`: 해당 언어를 언어 선택 화면에서 숨김(기본 `false`)
- `languages[].topics[].hidden`: 해당 주제를 주제 선택 화면에서 숨김(기본 `false`)
- `languages[].topics[].items[].hidden`: 해당 메뉴를 툴바에서 숨김(기본 `false`)
- `languageSelection.skipSingleTopic`: 주제가 하나일 때 주제 화면 생략 여부(기본 `true`)

현재 기본 언어·주제·메뉴를 숨기면 같은 범위에서 첫 번째로 표시 가능한 항목을 대신
사용합니다. 모든 언어를 숨기거나 표시되는 주제의 메뉴를 전부 숨긴 설정은 저장 검증에서
거부됩니다. 웹 관리자의 **사이니지 구성**에서 각 항목의 표시 여부를 선택할 수 있습니다.

프로그램은 시작할 때 `config\menu.override.json`을 검사합니다. schemaVersion 1,
최상위 `items`, `languages[].items` 또는 이전 웹 관리자가 만든 단일 `default` 주제
형식이면 현재 구조로 변환합니다. 변환 전 원본은
`backups\menu.override.before-migration-*.json`에 보관하며, 변환 결과 검증에 실패하면
원본 설정을 교체하지 않고 마지막 정상 설정으로 실행합니다.
- `layout`: 메뉴 위치, 크기, 색상 및 표시 옵션
- `idle`: 대기화면과 전환 시간
- `webViewData.idlePolicy`: 화면보호기 진입 시 WebView 데이터 유지·쿠키 삭제·전체 삭제 정책
- `webViewData.preserveDomains`: 로그인 상태를 유지할 도메인 예외 목록

전체 필드와 용도별 예시는 패키지에 포함된 `MENU_CONFIG_GUIDE.md`를 참고하세요.

## 6. Windows 시작 시 자동 실행(선택)

프로그램의 **설정 > Windows 시작프로그램**에서 현재 등록 여부와 설치 위치 일치 상태를
확인하고 바로가기를 등록하거나 삭제할 수 있습니다. 등록할 때 다음 실행 방식을 선택합니다.

- **사이니지 모드로 표시**: Windows 로그인 후 전체 화면을 바로 표시합니다. 기본값입니다.
- **숨김 모드로 시작**: 창은 표시하지 않고 트레이에서 실행하며, 트레이 메뉴로 화면을 엽니다.

1. `Win + R`을 누릅니다.
2. `shell:startup`을 입력하고 Enter를 누릅니다.
3. 프로그램 폴더에 생성된 `ysignage_launcher.exe`의 바로가기를 복사합니다.

실행 파일 자체를 시작프로그램 폴더로 옮기면 안 됩니다. 반드시 설치 폴더의 실행
파일을 가리키는 바로가기를 사용하세요.

## 7. 업데이트

관리자 화면에서 자동 업데이트를 켜거나 `지금 업데이트 확인`을 사용합니다. 설치는
운영 설정과 미디어를 보존하며 시작 검증에 실패하면 이전 정상 버전으로 롤백합니다.
업데이트 설치는 별도 네이티브 실행 파일에서 진행되므로 PowerShell 창이 표시되거나
PowerShell 실행 정책에 의해 설치가 중단되지 않습니다.

DLL 또는 `data` 폴더 일부만 덮어쓰지 마세요. 실행 파일과 동봉 파일의 버전이 다르면
앱이 시작되지 않을 수 있습니다.

## 8. 제거

installer로 설치했다면 Windows **설정 > 앱 > 설치된 앱** 또는 시작 메뉴의
**여의도성당Signage 제거**를 실행합니다. 제거할 때 설정과 사용자 파일까지 삭제할지
선택할 수 있으며, 보존을 선택하면 `config`, `media`, `state`, `logs` 등이 설치 폴더에
남습니다.

포터블 ZIP을 직접 실행한 경우에는 다음 순서로 제거합니다.

1. 여의도성당Signage를 완전히 종료합니다.
2. 직접 등록한 바탕화면·시작프로그램 바로가기를 삭제합니다.
3. 설정과 사용자 미디어가 필요하지 않은지 확인한 뒤 포터블 프로그램 폴더를 삭제합니다.

Windows 서비스는 설치하지 않습니다.

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
- `<프로그램 폴더>\config\menu.override.json`을 수정했는지 확인합니다.

### Windows 보안 경고가 표시됨

GitHub Actions에 `WINDOWS_SIGNING_CERTIFICATE_BASE64`와
`WINDOWS_SIGNING_CERT_PASSWORD` 비밀값이 모두 등록된 빌드는 실행 파일을 코드
서명하고 검증합니다. manifest에는 서명 인증서 지문이 기록되며, 사이니지 Updater는
설치 전에 신뢰 체인과 인증서 지문을 다시 검증합니다. 비밀값이 없는 빌드는 서명되지
않으므로 배포 출처와 SHA-256 값을 반드시 확인하세요.

## 10. 운영 참고

- 사이니지 화면 감추기: `Alt + F4`
- 앱 완전 종료: 설정 화면 하단 또는 Windows 트레이 메뉴의 **완전 종료**
- 개발 및 점검용 창 모드: 실행 전에 `SIMPLE_KIOSK_WINDOWED=1` 환경변수 설정
- 장시간 운영 단말기는 절전 및 화면 꺼짐 정책을 별도로 조정
- 운영 단말기에서는 Windows 자동 업데이트 재시작 정책과 네트워크 복구 정책을 확인
