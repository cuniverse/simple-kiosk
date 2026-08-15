[CmdletBinding()]
param(
    [string]$PackageRoot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = Split-Path -Parent $PSScriptRoot
}
$runtimeId = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'

function Get-WebView2Version {
    $registryPaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$runtimeId",
        "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$runtimeId",
        "HKCU:\Software\Microsoft\EdgeUpdate\Clients\$runtimeId"
    )
    foreach ($registryPath in $registryPaths) {
        $version = (Get-ItemProperty -LiteralPath $registryPath -Name 'pv' -ErrorAction SilentlyContinue).pv
        if (-not [string]::IsNullOrWhiteSpace($version) -and $version -ne '0.0.0.0') {
            return $version
        }
    }
    return $null
}

function Assert-MicrosoftSignature([string]$Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
        $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw "Microsoft 서명을 확인할 수 없습니다: $Path ($($signature.Status))"
    }
}

$vcRedistributable = Join-Path $PackageRoot 'prerequisites\vc_redist.x64.exe'
if (-not (Test-Path -LiteralPath $vcRedistributable -PathType Leaf)) {
    throw "Visual C++ Runtime 설치 파일을 찾을 수 없습니다: $vcRedistributable"
}
Assert-MicrosoftSignature $vcRedistributable
Write-Host 'Installing or updating Microsoft Visual C++ Runtime...'
$vcProcess = Start-Process -FilePath $vcRedistributable `
    -ArgumentList '/install', '/quiet', '/norestart' `
    -Wait `
    -PassThru
if ($vcProcess.ExitCode -notin @(0, 1638, 3010)) {
    throw "Visual C++ Runtime 설치 실패. 종료 코드: $($vcProcess.ExitCode)"
}
Write-Host 'Microsoft Visual C++ Runtime is ready.'

$installedVersion = Get-WebView2Version
if (-not [string]::IsNullOrWhiteSpace($installedVersion)) {
    Write-Host "Microsoft Edge WebView2 Runtime is already installed: $installedVersion"
    exit 0
}

$bootstrapper = Join-Path $PackageRoot 'prerequisites\MicrosoftEdgeWebview2Setup.exe'
if (-not (Test-Path -LiteralPath $bootstrapper -PathType Leaf)) {
    throw "WebView2 Runtime 설치 파일을 찾을 수 없습니다: $bootstrapper"
}

Assert-MicrosoftSignature $bootstrapper

Write-Host 'Installing Microsoft Edge WebView2 Runtime...'
$process = Start-Process -FilePath $bootstrapper `
    -ArgumentList '/silent', '/install' `
    -Wait `
    -PassThru
if ($process.ExitCode -ne 0) {
    throw "WebView2 Runtime 설치 실패. 종료 코드: $($process.ExitCode)"
}

$installedVersion = Get-WebView2Version
if ([string]::IsNullOrWhiteSpace($installedVersion)) {
    throw '설치 후에도 Microsoft Edge WebView2 Runtime을 확인할 수 없습니다.'
}
Write-Host "Microsoft Edge WebView2 Runtime installed: $installedVersion"
