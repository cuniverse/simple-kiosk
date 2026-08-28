# 여의도성당Signage Windows 최초 설치 요약

Windows 배포본은 installer EXE와 포터블 ZIP을 함께 제공합니다. 상세 절차와 문제 해결은
[Windows 설치 및 운영 가이드](../release/guides/WINDOWS_INSTALL_GUIDE.md)를 참고하세요.
배포 파일은 [최신 GitHub Release](https://github.com/cuniverse/simple-kiosk/releases/latest)에서
받을 수 있습니다.

## 권장: installer 설치

1. 릴리스의 `simple-kiosk-windows-setup-<version>.exe`를 실행합니다.
2. Windows 시작프로그램 등록, 바탕화면 바로가기와 **사설 네트워크에서 WEB 관리 자동
   허용** 여부를 선택합니다. 방화벽 자동 허용은 기본값이며 관리자 승인이 한 번 필요합니다.
3. 설치가 끝나면 여의도성당Signage를 실행합니다.

installer는 앱과 함께 Microsoft Visual C++ Runtime 및 Microsoft Edge WebView2 Runtime을
확인·설치하고, 시작 메뉴 프로그램 그룹과 제거 프로그램을 등록합니다. 기본 설치 위치는
`%LOCALAPPDATA%\Programs\SimpleKiosk`이며 이전 설치 위치가 있으면 그 위치를 재사용합니다.
방화벽 자동 허용은 현재 WEB 관리 TCP 포트와 mDNS UDP 5353을 도메인·사설 네트워크의
같은 서브넷에만 열며, 프로그램 제거 시 해당 규칙을 함께 삭제합니다.
규칙이 없거나 이후 WEB 관리 포트·mDNS 설정이 바뀌면 앱 시작 또는 설정 저장 시 관리자
승인을 한 번 요청해 규칙을 자동으로 새 설정에 맞춥니다.

## 포터블 ZIP 실행

1. `simple-kiosk-windows-<version>.zip`을 대상 PC로 복사합니다.
2. ZIP 파일 속성에 **차단 해제**가 표시되면 선택한 뒤 전체 파일을 전용 폴더에 풉니다.
3. 처음 설치하는 PC에서는 `InstallPrerequisites.cmd`를 실행합니다.
4. `ysignage.exe`를 실행합니다.

포터블 실행에서도 WEB 관리가 켜져 있고 일치하는 관리 규칙이 없으면 첫 실행 시 관리자
승인을 요청합니다. 공개 네트워크나 인터넷 전체를 여는 규칙은 만들지 않습니다.

`ysignage.exe`, `simple_kiosk.exe` 호환 복사본, DLL과 `data` 폴더는 항상 함께 있어야
합니다. 일부 파일만 복사하거나 기존 버전에 덮어쓰면 실행되지 않을 수 있습니다.

포터블 실행은 설치 없이 가능하지만 자동 업데이트·롤백과 Windows 시작프로그램을 안정적으로
사용하려면 상세 가이드의 **포터블 런처 설치** 절차에 따라 `ysignage_launcher.exe`를
구성하세요.

## 설정과 업데이트

- 운영 설정: `<프로그램 폴더>\config\menu.override.json`
- 사용자 미디어: `<프로그램 폴더>\media`
- 업데이트 후 유지할 운영 파일: `<프로그램 폴더>\exdata`
- 자동 업데이트: 기본 OFF. 프로그램 설정 또는 WEB 관리자에서 사용 여부와 정책 설정
- 수동 업데이트: 설정의 **지금 업데이트 확인 / 지금 설치**, WEB 관리자 또는 `F9`
- 메뉴 구성: 웹 관리자의 **사이니지 구성** 사용 권장

기본 설정은 앱에 포함된 `assets/config/menu.defaults.json`이며 운영 환경에서는 이 파일을
직접 수정하지 않습니다. 관리자 화면에서 저장한 설정은 외부 오버라이드 파일에 기록되어
업데이트와 롤백 후에도 유지됩니다.

수동으로 요청한 설치는 같은 버전의 이전 실패 횟수와 관계없이 다시 시도합니다. 기본
Updater가 실패하면 오류 내용을 표시하고 Setup 설치로 전환할지 확인하며, 승인한 경우에만
같은 Release의 Setup EXE를 내려받아 SHA-256 검증 후 실행합니다. 자동 업데이트는 같은
버전에서 3회 실패하면 차단하고, 대상 버전이 바뀌거나 첫 실패 후 24시간이 지나면 실패
횟수와 시간 창을 초기화합니다. 자동 업데이트에서는 Setup을 임의로 실행하지 않습니다.

설정의 **진단 정보로 이슈 등록**은 진단 자료를 먼저 내보낸 뒤 원격 WEB 관리자의
진단·GitHub 이슈 작성 화면을 엽니다. 업데이트 상태 문구는 선택해서 복사할 수 있습니다.

## 제거

- installer 설치: Windows **설정 > 앱 > 설치된 앱** 또는 시작 메뉴의
  **여의도성당Signage 제거**를 실행합니다. 설정·사용자 파일 삭제 여부를 선택할 수 있습니다.
- 포터블 실행: 앱을 완전히 종료하고 직접 만든 바로가기를 제거한 뒤 프로그램 폴더를
  삭제합니다.

여의도성당Signage는 Windows 서비스를 설치하지 않습니다.
