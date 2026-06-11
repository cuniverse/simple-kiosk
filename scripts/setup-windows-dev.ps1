<#
.SYNOPSIS
    simple-kiosk 의 Windows 개발 환경을 자동으로 점검하고 부족한 항목을 설치/구성한다.

.DESCRIPTION
    1) Windows 개발자 모드(심볼릭 링크 지원) 활성화 여부 점검
    2) NuGet CLI(nuget.exe) 설치 및 PATH 등록 (flutter_inappwebview_windows 의존성)
    3) WebView2 Runtime 설치 여부 점검
    4) flutter doctor 실행
    5) (옵션) flutter clean / pub get / run -d windows

    상세 배경: docs/WINDOWS_SETUP.md

.PARAMETER Run
    셋업 후 'flutter run -d windows' 까지 실행한다.

.PARAMETER SkipWebView2
    WebView2 Runtime 점검/설치를 건너뛴다.

.EXAMPLE
    PS> .\scripts\setup-windows-dev.ps1

.EXAMPLE
    PS> .\scripts\setup-windows-dev.ps1 -Run
#>

[CmdletBinding()]
param(
    [switch]$Run,
    [switch]$SkipWebView2
)

$ErrorActionPreference = 'Stop'

function Write-Step    { param([string]$msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok      { param([string]$msg) Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-WarnMsg { param([string]$msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-ErrMsg  { param([string]$msg) Write-Host "  [FAIL] $msg" -ForegroundColor Red }

# ────────────────────────────────────────────────────────────
# 0. 위치 확인 (프로젝트 루트로 이동)
# ────────────────────────────────────────────────────────────
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Split-Path -Parent $scriptDir
Set-Location $projectDir
Write-Step "프로젝트 루트: $projectDir"

if (-not (Test-Path "$projectDir\pubspec.yaml")) {
    Write-ErrMsg "pubspec.yaml 을 찾지 못함. Flutter 프로젝트 루트에서 실행해야 한다."
    exit 1
}

# ────────────────────────────────────────────────────────────
# 1. Windows 개발자 모드 (심볼릭 링크 지원) 점검
# ────────────────────────────────────────────────────────────
Write-Step "Windows 개발자 모드 확인"
$devModeKey  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
$devModeName = 'AllowDevelopmentWithoutDevLicense'
$devModeOn   = $false
try {
    $val = (Get-ItemProperty -Path $devModeKey -Name $devModeName -ErrorAction Stop).$devModeName
    $devModeOn = ($val -eq 1)
} catch {
    $devModeOn = $false
}

if ($devModeOn) {
    Write-Ok "개발자 모드 활성화됨"
} else {
    Write-WarnMsg "개발자 모드가 꺼져있다. Flutter 플러그인 빌드(.plugin_symlinks)에 심볼릭 링크가 필요하다."
    Write-Host "  설정 페이지를 연다: ms-settings:developers"
    Start-Process "ms-settings:developers" | Out-Null
    Write-Host "  설정에서 켠 뒤 새 터미널을 열고 이 스크립트를 다시 실행하라." -ForegroundColor Yellow
    # 계속 진행은 가능하지만 빌드는 실패한다.
}

# ────────────────────────────────────────────────────────────
# 2. NuGet CLI 점검 / 설치 / PATH 등록
# ────────────────────────────────────────────────────────────
Write-Step "NuGet CLI(nuget.exe) 확인"

function Find-NugetExe {
    $cmd = Get-Command nuget -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Microsoft.NuGet_Microsoft.Winget.Source_8wekyb3d8bbwe\nuget.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }

    $found = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" `
                -Filter 'nuget.exe' -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1
    if ($found) { return $found.FullName }

    return $null
}

$nugetExe = Find-NugetExe
if (-not $nugetExe) {
    Write-WarnMsg "nuget.exe 미설치. winget 으로 설치 시도."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Microsoft.NuGet -e --accept-source-agreements --accept-package-agreements
        $nugetExe = Find-NugetExe
    } else {
        Write-ErrMsg "winget 을 찾을 수 없다. 수동 설치: https://www.nuget.org/downloads"
        exit 1
    }
}

if (-not $nugetExe) {
    Write-ErrMsg "설치 후에도 nuget.exe 를 찾지 못함. 수동 설치 필요."
    exit 1
}

Write-Ok "nuget.exe 위치: $nugetExe"
$nugetDir = Split-Path -Parent $nugetExe

# 사용자 PATH 영구 등록
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$nugetDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$nugetDir", 'User')
    Write-Ok "사용자 PATH 에 nuget 디렉터리 추가됨"
} else {
    Write-Ok "사용자 PATH 에 이미 등록됨"
}

# 현재 세션 PATH 갱신
if ($env:Path -notlike "*$nugetDir*") {
    $env:Path = "$nugetDir;$env:Path"
}

# 동작 확인
try {
    $nugetVersion = (& $nugetExe help 2>&1 | Select-Object -First 1)
    Write-Ok "nuget 동작 확인: $nugetVersion"
} catch {
    Write-WarnMsg "nuget 호출 실패: $_"
}

# ────────────────────────────────────────────────────────────
# 3. WebView2 Runtime 점검
# ────────────────────────────────────────────────────────────
if (-not $SkipWebView2) {
    Write-Step "WebView2 Runtime 확인"
    $webview2Keys = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
        'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
        'HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    )
    $wv2 = $null
    foreach ($k in $webview2Keys) {
        try {
            $v = (Get-ItemProperty -Path $k -Name pv -ErrorAction Stop).pv
            if ($v) { $wv2 = $v; break }
        } catch { }
    }

    if ($wv2) {
        Write-Ok "WebView2 Runtime 버전: $wv2"
    } else {
        Write-WarnMsg "WebView2 Runtime 미설치. winget 으로 설치 시도."
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget install --id Microsoft.EdgeWebView2Runtime -e --accept-source-agreements --accept-package-agreements
        } else {
            Write-WarnMsg "winget 미사용. 수동 설치: https://developer.microsoft.com/microsoft-edge/webview2/"
        }
    }
} else {
    Write-Step "WebView2 Runtime 점검 건너뜀 (-SkipWebView2)"
}

# ────────────────────────────────────────────────────────────
# 4. Flutter 점검
# ────────────────────────────────────────────────────────────
Write-Step "flutter doctor"
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-ErrMsg "flutter 가 PATH 에 없다. https://docs.flutter.dev/get-started/install/windows"
    exit 1
}
flutter --version
flutter doctor

# ────────────────────────────────────────────────────────────
# 5. 의존성 / 실행
# ────────────────────────────────────────────────────────────
Write-Step "flutter pub get"
flutter pub get

if ($Run) {
    Write-Step "flutter run -d windows"
    flutter clean
    flutter pub get
    flutter run -d windows
} else {
    Write-Host "`n셋업 완료. 다음 명령으로 실행 가능:" -ForegroundColor Cyan
    Write-Host "    flutter run -d windows" -ForegroundColor Cyan
    Write-Host "(또는 ./scripts/setup-windows-dev.ps1 -Run)" -ForegroundColor Cyan
}
