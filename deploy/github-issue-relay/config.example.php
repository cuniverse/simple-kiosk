<?php

return [
    // GitHub App 설정 화면의 Client ID. App ID도 가능하지만 Client ID를 권장합니다.
    'github_app_client_id' => 'Iv23liExampleClientId',

    // GitHub App을 cuniverse/simple-kiosk에 설치한 뒤 확인한 Installation ID.
    'github_installation_id' => '12345678',

    // GitHub App 설정 화면에서 발급받은 PEM 개인키의 서버 내부 절대경로.
    'github_private_key_file' => '/etc/simple-kiosk-issue-relay/github-app.pem',

    'github_repository_owner' => 'cuniverse',
    'github_repository_name' => 'simple-kiosk',
    'github_api_version' => '2026-03-10',

    // 저장소에 실제로 존재하는 라벨만 지정합니다. 필요 없으면 빈 배열로 둡니다.
    'github_issue_labels' => [],
];
