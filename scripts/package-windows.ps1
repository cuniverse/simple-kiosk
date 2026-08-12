[CmdletBinding()]
param(
    # CI에서는 GitHub Release 태그에서 추출한 버전을 전달한다.
    # 생략하면 기존처럼 pubspec.yaml의 version을 사용한다.
    [string]$PackageVersion
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
Set-Location $projectDir

if ([string]::IsNullOrWhiteSpace($PackageVersion)) {
    $versionLine = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(.+)$'
    if (-not $versionLine) {
        throw 'pubspec.yaml에서 version을 찾을 수 없습니다.'
    }
    $PackageVersion = $versionLine.Matches[0].Groups[1].Value.Trim()
}

$PackageVersion = $PackageVersion.Trim() -replace '^v', ''
if ($PackageVersion -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') {
    throw "패키지 버전 형식이 올바르지 않습니다: $PackageVersion"
}

# '+'는 ZIP 파일명에서 빌드 메타데이터 구분 대신 '-'로 표현한다.
$archiveVersion = $PackageVersion.Replace('+', '-')
$packageName = "simple-kiosk-windows-$archiveVersion"
$distDir = Join-Path $projectDir 'dist'
$archive = Join-Path $distDir "$packageName.zip"
$stageRoot = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
$stage = Join-Path $stageRoot $packageName
$pubspecPath = Join-Path $projectDir 'pubspec.yaml'
$originalPubspec = Get-Content -Raw -Encoding UTF8 $pubspecPath

try {
    Write-Host "Package version: $PackageVersion"
    # 태그/인수 버전을 앱 런타임 버전에도 적용한다. 빌드 후 원본은 복원한다.
    $buildPubspec = $originalPubspec -replace '(?m)^version:\s*.+$', "version: $PackageVersion"
    Set-Content -Encoding UTF8 -NoNewline -Path $pubspecPath -Value $buildPubspec
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get 실패' }

    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Windows 릴리스 빌드 실패' }

    $releaseCandidates = @(
        (Join-Path $projectDir 'build\windows\x64\runner\Release'),
        (Join-Path $projectDir 'build\windows\runner\Release')
    )
    $releaseDir = $releaseCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $releaseDir) {
        throw 'Windows Release 출력 폴더를 찾을 수 없습니다.'
    }

    New-Item -ItemType Directory -Force -Path $stage, $distDir | Out-Null
    # 실행 테스트가 만든 WebView2 사용자 프로필(쿠키/캐시/세션)은 배포하지 않는다.
    Get-ChildItem -Path $releaseDir -File |
        Copy-Item -Destination $stage -Force
    Copy-Item (Join-Path $releaseDir 'data') $stage -Recurse -Force
    Copy-Item 'release\guides\WINDOWS_INSTALL_GUIDE.md' (Join-Path $stage 'INSTALL_GUIDE.md')
    Copy-Item 'release\guides\MENU_CONFIGURATION_GUIDE.md' (Join-Path $stage 'MENU_CONFIG_GUIDE.md')
    Copy-Item 'RELEASE_NOTES.md' (Join-Path $stage 'RELEASE_NOTES.md')
    $updaterDir = Join-Path $stage 'updater'
    New-Item -ItemType Directory -Force -Path $updaterDir | Out-Null
    Copy-Item 'scripts\update.ps1' (Join-Path $updaterDir 'update.ps1')
    Copy-Item 'scripts\launcher.ps1' (Join-Path $updaterDir 'launcher.ps1')
    Copy-Item 'scripts\launcher.cmd' (Join-Path $updaterDir 'launcher.cmd')
    Copy-Item 'scripts\install-launcher.ps1' (Join-Path $updaterDir 'install-launcher.ps1')
    Copy-Item 'scripts\migrate-menu-config.ps1' (Join-Path $updaterDir 'migrate-menu-config.ps1')

    $exe = Join-Path $stage 'simple_kiosk.exe'
    if (-not (Test-Path $exe)) { throw 'simple_kiosk.exe를 찾을 수 없습니다.' }
    $hash = (Get-FileHash -Algorithm SHA256 $exe).Hash.ToLowerInvariant()
    "$hash  simple_kiosk.exe" | Set-Content -Encoding ascii (Join-Path $stage 'SHA256SUMS.txt')

    if (Test-Path $archive) { Remove-Item $archive -Force }
    Compress-Archive -Path $stage -DestinationPath $archive -CompressionLevel Optimal
    Write-Host "Created: $archive"
}
finally {
    Set-Content -Encoding UTF8 -NoNewline -Path $pubspecPath -Value $originalPubspec
    if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }
}
