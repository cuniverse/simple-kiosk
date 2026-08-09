[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
Set-Location $projectDir

$versionLine = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(.+)$'
if (-not $versionLine) {
    throw 'pubspec.yaml에서 version을 찾을 수 없습니다.'
}
$version = $versionLine.Matches[0].Groups[1].Value.Trim().Replace('+', '-')
$packageName = "simple-kiosk-windows-$version"
$distDir = Join-Path $projectDir 'dist'
$archive = Join-Path $distDir "$packageName.zip"
$stageRoot = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
$stage = Join-Path $stageRoot $packageName

try {
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
    Copy-Item -Path (Join-Path $releaseDir '*') -Destination $stage -Recurse -Force
    Copy-Item 'release\guides\WINDOWS_INSTALL_GUIDE.md' (Join-Path $stage 'INSTALL_GUIDE.md')
    Copy-Item 'release\guides\MENU_CONFIGURATION_GUIDE.md' (Join-Path $stage 'MENU_CONFIG_GUIDE.md')

    $exe = Join-Path $stage 'simple_kiosk.exe'
    if (-not (Test-Path $exe)) { throw 'simple_kiosk.exe를 찾을 수 없습니다.' }
    $hash = (Get-FileHash -Algorithm SHA256 $exe).Hash.ToLowerInvariant()
    "$hash  simple_kiosk.exe" | Set-Content -Encoding ascii (Join-Path $stage 'SHA256SUMS.txt')

    if (Test-Path $archive) { Remove-Item $archive -Force }
    Compress-Archive -Path $stage -DestinationPath $archive -CompressionLevel Optimal
    Write-Host "Created: $archive"
}
finally {
    if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }
}
