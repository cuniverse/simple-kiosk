# GitHub 이슈 중계 서버(PHP)

웹 관리자 사용자가 GitHub에 로그인하지 않아도 `cuniverse/simple-kiosk`에 이슈를
등록하는 PHP 엔드포인트입니다. 브라우저에는 GitHub 인증정보를 제공하지 않습니다.
GW 서버가 GitHub App 개인키로 10분 이내의 JWT를 만들고, 1시간 유효한 설치 토큰을
발급받은 뒤 이슈를 생성합니다.

WEB 관리자와 GW 사이의 기존 접속 방식은 **HTTP 그대로 유지**합니다. PHP가 GitHub
공식 API를 호출하는 서버 외부 통신만 GitHub가 요구하는 HTTPS를 사용합니다.

## 1. GitHub App 만들기

1. GitHub의 **Settings → Developer settings → GitHub Apps → New GitHub App**을 엽니다.
2. 이름은 예를 들어 `simple-kiosk-issue-relay`로 지정합니다.
3. Webhook은 사용하지 않으므로 비활성화합니다.
4. **Repository permissions → Issues**만 `Read and write`로 지정합니다.
5. App을 생성한 뒤 **Install App**에서 `cuniverse/simple-kiosk` 저장소 하나에만
   설치합니다.
6. App 설정 화면의 **Client ID**와 설치 URL의 Installation ID를 기록합니다.
7. **Generate a private key**로 PEM 파일을 한 번 발급합니다.

GitHub의 이슈 생성 API에는 `Issues: write` 권한이 필요합니다. GitHub App JWT의
`iss`에는 Client ID 사용이 권장됩니다.

## 2. Ubuntu/Debian GW 서버 설치

배포판의 기본 PHP 버전을 따르는 메타 패키지를 설치합니다. Nginx 설정은
`/run/php/php-fpm.sock` 공용 소켓을 사용하므로 PHP 버전이 바뀌어도 수정할 필요가
없습니다.

```bash
sudo apt update
sudo apt install php-fpm php-curl
sudo install -d -o root -g www-data -m 0750 /etc/simple-kiosk-issue-relay
sudo install -d -o root -g root -m 0755 /var/www/simple-kiosk-issue-relay/public
sudo install -o root -g root -m 0644 public/index.php /var/www/simple-kiosk-issue-relay/public/index.php
sudo install -o root -g www-data -m 0640 config.example.php /etc/simple-kiosk-issue-relay/config.php
sudo install -o root -g www-data -m 0640 /받은/개인키.pem /etc/simple-kiosk-issue-relay/github-app.pem
sudo editor /etc/simple-kiosk-issue-relay/config.php
```

`config.php`에서 다음 값을 실제 값으로 변경합니다.

- `github_app_client_id`
- `github_installation_id`
- `github_private_key_file`
- 저장소 소유자와 이름

`config.php`와 PEM 파일은 웹 루트 밖에 두며 PHP-FPM 사용자(`www-data`)만 읽을 수
있게 합니다. PEM은 프로그램 설치 파일이나 `assets/`에 넣지 않습니다.

## 3. Nginx 적용

`nginx.conf.example`의 `limit_req_zone`은 Nginx의 `http {}` 블록에 넣고,
`location = /api/github-issues`는 현재 `*.signage.cuniverse.net`을 처리하는
`server {}` 블록에 넣습니다.

중요한 점은 정확히 일치하는 PHP location을 기존 `location /`과 나란히 두는
것입니다. 그러면 이슈 요청만 PHP로 가고, 나머지 WEB 관리자 요청은 기존
`/run/signage/ysignage숫자.sock`으로 계속 전달됩니다.

```bash
sudo nginx -t
sudo systemctl reload "$(basename "$(readlink -f /run/php/php-fpm.sock)" .sock)"
sudo systemctl reload nginx
```

PHP-FPM 소켓은 다음 명령으로 확인합니다.

```bash
ls -l /run/php/php-fpm.sock
readlink -f /run/php/php-fpm.sock
```

## 4. 동작 확인

먼저 서버에서 직접 호출합니다.

```bash
curl -i -X POST 'http://ysignage1.signage.cuniverse.net/api/github-issues' \
  -H 'Content-Type: application/json' \
  --data '{"title":"[질문] 이슈 중계 시험","body":"PHP 중계 서버 동작 시험입니다."}'
```

정상이면 HTTP `201`과 다음 형태의 JSON이 반환됩니다.

```json
{
  "ok": true,
  "number": 123,
  "url": "https://github.com/cuniverse/simple-kiosk/issues/123",
  "message": "GitHub 이슈가 등록되었습니다."
}
```

오류 원인은 PHP-FPM/Nginx 로그에서 확인합니다.

```bash
sudo journalctl -u "$(basename "$(readlink -f /run/php/php-fpm.sock)" .sock)" -n 100 --no-pager
sudo tail -n 100 /var/log/nginx/error.log
```

`401`이면 Client ID 또는 PEM을, `404`이면 Installation ID와 App 설치 저장소를,
`403`이면 App의 `Issues: Read and write` 권한을 먼저 확인합니다. 권한을 나중에
변경했다면 저장소 소유자가 변경된 권한을 다시 승인해야 합니다.

## 운영 제한

- Nginx 예시는 IP당 분당 3회로 제한합니다.
- 이 엔드포인트는 기존 원격 WEB 관리자 주소에서만 노출합니다.
