# 원격 WEB 관리자 SSH 키

원격 WEB 관리자 reverse forwarding 전용 개인 키를 다음 이름으로 배치합니다.

```text
assets/ssh/web-admin-tunnel-key
```

`pubspec.yaml`에 이 폴더가 Flutter asset으로 등록되어 있으므로 키를 추가한 뒤 Windows
패키지를 빌드하면 ZIP과 설치 프로그램에 자동 포함됩니다. 키가 없는 개발 빌드에서는
원격 연결 기능이 켜져 있어도 `SSH 접속 키가 포함되지 않음` 상태로 대기합니다.

현재 개발 트리의 `web-admin-tunnel-key`는 요청에 따라
`C:\Users\purit\.ssh\id_rsa`를 임시 복사한 파일입니다.
