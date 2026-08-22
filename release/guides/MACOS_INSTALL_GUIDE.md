# 여의도성당Signage macOS 최초 설치 가이드

## 패키지 구성

- `simple_kiosk.app`: macOS 애플리케이션
- `INSTALL_GUIDE.md`: 현재 문서
- `MENU_CONFIG_GUIDE.md`: 메뉴·툴바·대기화면 설정 상세 가이드
- `SHA256SUMS.txt`: 실행 파일 무결성 확인값

## 최초 설치

1. ZIP을 완전히 풉니다.
2. `simple_kiosk.app`을 `/Applications` 폴더로 이동합니다.
3. 앱을 실행하고 모든 메뉴, 네트워크, 가상 키보드 및 대기화면을 확인합니다.

설치 전에 터미널에서 아래 명령을 실행하면 파일 손상 여부를 확인할 수 있습니다.

```bash
shasum -a 256 -c SHA256SUMS.txt
```

## Gatekeeper 및 배포 서명

기본 로컬/CI 빌드는 Apple Developer ID 서명과 공증이 적용되지 않습니다. 내부에서
직접 만든 파일임을 확인할 수 있을 때만 Finder에서 앱을 Control-클릭한 후 `열기`를
사용하세요. 외부 배포 전에는 Developer ID 서명과 Apple 공증을 적용해야 합니다.

## 운영

- 기본 실행은 전체 화면 사이니지 모드입니다.
- 종료: `Command + Q`
- 개발용 창 모드: 실행 전 `SIMPLE_KIOSK_WINDOWED=1` 환경변수 설정
- 절전 방지, 자동 로그인 및 로그인 항목 등록은 단말기 운영 정책에 맞춰 설정합니다.
- 메뉴 변경: `assets/config/menu.defaults.json` 수정 후 macOS 패키지를 다시 빌드합니다.
