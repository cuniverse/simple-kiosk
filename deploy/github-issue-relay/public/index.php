<?php

declare(strict_types=1);

const MAX_REQUEST_BYTES = 65536;
const MAX_TITLE_BYTES = 500;
const MAX_BODY_BYTES = 30000;

function respond(int $status, array $payload): void
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    header('X-Content-Type-Options: nosniff');
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function base64UrlEncode(string $value): string
{
    return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
}

function githubJwt(string $clientId, string $privateKeyFile): string
{
    $privateKeyPem = @file_get_contents($privateKeyFile);
    if ($privateKeyPem === false) {
        throw new RuntimeException('GitHub App 개인키를 읽을 수 없습니다.');
    }

    $privateKey = openssl_pkey_get_private($privateKeyPem);
    if ($privateKey === false) {
        throw new RuntimeException('GitHub App 개인키 형식이 올바르지 않습니다.');
    }

    $now = time();
    $header = base64UrlEncode(json_encode(
        ['alg' => 'RS256', 'typ' => 'JWT'],
        JSON_THROW_ON_ERROR
    ));
    $claims = base64UrlEncode(json_encode(
        ['iat' => $now - 60, 'exp' => $now + 540, 'iss' => $clientId],
        JSON_THROW_ON_ERROR
    ));
    $unsignedToken = $header . '.' . $claims;

    $signature = '';
    if (!openssl_sign($unsignedToken, $signature, $privateKey, OPENSSL_ALGO_SHA256)) {
        throw new RuntimeException('GitHub App JWT 서명에 실패했습니다.');
    }

    return $unsignedToken . '.' . base64UrlEncode($signature);
}

function githubRequest(
    string $method,
    string $path,
    ?array $body,
    string $bearerToken,
    string $apiVersion
): array {
    if (!function_exists('curl_init')) {
        throw new RuntimeException('PHP cURL 확장이 설치되어 있지 않습니다.');
    }

    $curl = curl_init('https://api.github.com' . $path);
    if ($curl === false) {
        throw new RuntimeException('GitHub 요청을 초기화하지 못했습니다.');
    }

    $headers = [
        'Accept: application/vnd.github+json',
        'Authorization: Bearer ' . $bearerToken,
        'Content-Type: application/json',
        'User-Agent: simple-kiosk-issue-relay',
        'X-GitHub-Api-Version: ' . $apiVersion,
    ];
    curl_setopt_array($curl, [
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 5,
        CURLOPT_TIMEOUT => 20,
        CURLOPT_FOLLOWLOCATION => false,
    ]);
    if ($body !== null) {
        curl_setopt($curl, CURLOPT_POSTFIELDS, json_encode(
            $body,
            JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
        ));
    }

    $responseBody = curl_exec($curl);
    if ($responseBody === false) {
        $error = curl_error($curl);
        curl_close($curl);
        throw new RuntimeException('GitHub 통신 실패: ' . $error);
    }
    $status = (int) curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    curl_close($curl);

    $decoded = json_decode($responseBody, true);
    return [
        'status' => $status,
        'body' => is_array($decoded) ? $decoded : [],
        'raw' => $responseBody,
    ];
}

function requiredConfig(array $config, string $key): string
{
    $value = trim((string) ($config[$key] ?? ''));
    if ($value === '') {
        throw new RuntimeException("설정 '{$key}' 값이 없습니다.");
    }
    return $value;
}

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    header('Allow: POST');
    respond(405, ['ok' => false, 'message' => 'POST 요청만 허용됩니다.']);
}

$contentLength = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
if ($contentLength > MAX_REQUEST_BYTES) {
    respond(413, ['ok' => false, 'message' => '이슈 리포트가 너무 큽니다.']);
}

$rawRequest = file_get_contents('php://input', false, null, 0, MAX_REQUEST_BYTES + 1);
if ($rawRequest === false || strlen($rawRequest) > MAX_REQUEST_BYTES) {
    respond(413, ['ok' => false, 'message' => '이슈 리포트가 너무 큽니다.']);
}
try {
    $request = json_decode($rawRequest, true, 32, JSON_THROW_ON_ERROR);
} catch (JsonException $error) {
    respond(400, ['ok' => false, 'message' => 'JSON 요청 형식이 올바르지 않습니다.']);
}
if (!is_array($request)) {
    respond(400, ['ok' => false, 'message' => 'JSON 객체가 필요합니다.']);
}
if (!is_string($request['title'] ?? null) ||
    (isset($request['body']) && !is_string($request['body']))) {
    respond(422, ['ok' => false, 'message' => '이슈 제목과 본문은 문자열이어야 합니다.']);
}
$title = trim($request['title']);
$body = trim($request['body'] ?? '');
if ($title === '') {
    respond(422, ['ok' => false, 'message' => '이슈 제목을 입력하세요.']);
}
if (strlen($title) > MAX_TITLE_BYTES || strlen($body) > MAX_BODY_BYTES) {
    respond(422, ['ok' => false, 'message' => '이슈 제목 또는 본문이 너무 깁니다.']);
}

try {
    $configPath = getenv('ISSUE_RELAY_CONFIG') ?: '/etc/simple-kiosk-issue-relay/config.php';
    if (!is_file($configPath)) {
        throw new RuntimeException('이슈 중계 서버 설정 파일을 찾을 수 없습니다.');
    }

    $config = require $configPath;
    if (!is_array($config)) {
        throw new RuntimeException('이슈 중계 서버 설정 형식이 올바르지 않습니다.');
    }

    $clientId = requiredConfig($config, 'github_app_client_id');
    $installationId = requiredConfig($config, 'github_installation_id');
    $privateKeyFile = requiredConfig($config, 'github_private_key_file');
    $repositoryOwner = requiredConfig($config, 'github_repository_owner');
    $repositoryName = requiredConfig($config, 'github_repository_name');
    $apiVersion = trim((string) ($config['github_api_version'] ?? '2026-03-10'));

    $jwt = githubJwt($clientId, $privateKeyFile);
    $tokenResponse = githubRequest(
        'POST',
        '/app/installations/' . rawurlencode($installationId) . '/access_tokens',
        null,
        $jwt,
        $apiVersion
    );
    if ($tokenResponse['status'] !== 201) {
        throw new RuntimeException(
            'GitHub App 설치 토큰 발급 실패 (HTTP ' . $tokenResponse['status'] . ')'
        );
    }

    $installationToken = (string) ($tokenResponse['body']['token'] ?? '');
    if ($installationToken === '') {
        throw new RuntimeException('GitHub App 설치 토큰 응답이 올바르지 않습니다.');
    }

    $issuePayload = ['title' => $title, 'body' => $body];
    $labels = $config['github_issue_labels'] ?? [];
    if (is_array($labels) && $labels !== []) {
        $issuePayload['labels'] = array_values(array_map('strval', $labels));
    }

    $issueResponse = githubRequest(
        'POST',
        '/repos/' . rawurlencode($repositoryOwner) . '/' . rawurlencode($repositoryName) . '/issues',
        $issuePayload,
        $installationToken,
        $apiVersion
    );
    if ($issueResponse['status'] !== 201) {
        $githubMessage = (string) ($issueResponse['body']['message'] ?? '알 수 없는 오류');
        throw new RuntimeException(
            'GitHub 이슈 생성 실패 (HTTP ' . $issueResponse['status'] . '): ' . $githubMessage
        );
    }

    respond(201, [
        'ok' => true,
        'number' => (int) ($issueResponse['body']['number'] ?? 0),
        'url' => (string) ($issueResponse['body']['html_url'] ?? ''),
        'message' => 'GitHub 이슈가 등록되었습니다.',
    ]);
} catch (Throwable $error) {
    error_log('[simple-kiosk-issue-relay] ' . $error->getMessage());
    respond(502, [
        'ok' => false,
        'message' => 'GitHub 이슈 등록에 실패했습니다. 서버 로그를 확인하세요.',
    ]);
}
