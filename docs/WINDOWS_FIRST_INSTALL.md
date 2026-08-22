# 여의도성당Signage Windows 최초 설치 요약

Windows 배포본은 installer EXE와 포터블 ZIP을 함께 제공합니다. 상세 절차와 문제 해결은
[Windows 설치 및 운영 가이드](../release/guides/WINDOWS_INSTALL_GUIDE.md)를 참고하세요.

## 권장: installer 설치

1. 릴리스의 `simple-kiosk-windows-setup-<version>.exe`를 실행합니다.
2. Windows 시작프로그램 등록과 바탕화면 바로가기 생성을 선택합니다.
3. 설치가 끝나면 여의도성당Signage를 실행합니다.

installer는 앱과 함께 Microsoft Visual C++ Runtime 및 Microsoft Edge WebView2 Runtime을
확인·설치하고, 시작 메뉴 프로그램 그룹과 제거 프로그램을 등록합니다. 기본 설치 위치는
`%LOCALAPPDATA%\Programs\SimpleKiosk`이며 이전 설치 위치가 있으면 그 위치를 재사용합니다.

## 포터블 ZIP 실행

1. `simple-kiosk-windows-<version>.zip`을 대상 PC로 복사합니다.
2. ZIP 파일 속성에 **차단 해제**가 표시되면 선택한 뒤 전체 파일을 전용 폴더에 풉니다.
3. 처음 설치하는 PC에서는 `InstallPrerequisites.cmd`를 실행합니다.
4. `ysignage.exe`를 실행합니다.

`ysignage.exe`, `simple_kiosk.exe` 호환 복사본, DLL과 `data` 폴더는 항상 함께 있어야
합니다. 일부 파일만 복사하거나 기존 버전에 덮어쓰면 실행되지 않을 수 있습니다.

포터블 실행은 설치 없이 가능하지만 자동 업데이트·롤백과 Windows 시작프로그램을 안정적으로
사용하려면 상세 가이드의 **포터블 런처 설치** 절차에 따라 `ysignage_launcher.exe`를
구성하세요.

## 설정과 업데이트

- 운영 설정: `<프로그램 폴더>\config\menu.override.json`
- 사용자 미디어: `<프로그램 폴더>\media`
- 자동 업데이트: 프로그램 설정 또는 웹 관리자의 업데이트 기능 사용
- 메뉴 구성: 웹 관리자의 **사이니지 구성** 사용 권장

기본 설정은 앱에 포함된 `assets/config/menu.defaults.json`이며 운영 환경에서는 이 파일을
직접 수정하지 않습니다. 관리자 화면에서 저장한 설정은 외부 오버라이드 파일에 기록되어
업데이트와 롤백 후에도 유지됩니다.

## 제거

- installer 설치: Windows **설정 > 앱 > 설치된 앱** 또는 시작 메뉴의
  **여의도성당Signage 제거**를 실행합니다. 설정·사용자 파일 삭제 여부를 선택할 수 있습니다.
- 포터블 실행: 앱을 완전히 종료하고 직접 만든 바로가기를 제거한 뒤 프로그램 폴더를
  삭제합니다.

여의도성당Signage는 Windows 서비스를 설치하지 않습니다.
