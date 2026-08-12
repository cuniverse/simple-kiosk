[CmdletBinding()]
param(
    [string]$Version,
    [string]$DataRoot = "$env:ProgramData\SimpleKiosk",
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$versionsRoot = Join-Path $DataRoot 'versions'
$pointerPath = Join-Path $DataRoot 'current.json'

if (-not (Test-Path -LiteralPath $versionsRoot)) {
    throw "버전 폴더가 없습니다: $versionsRoot"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    Write-Host '설치된 버전:'
    Get-ChildItem -LiteralPath $versionsRoot -Directory |
        Sort-Object LastWriteTimeUtc -Descending |
        ForEach-Object { Write-Host "  $($_.Name)" }
    Write-Host '복구하려면 -Version <버전>을 지정하세요.'
    exit 0
}

if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') {
    throw "올바르지 않은 버전 형식입니다: $Version"
}
$targetRoot = Join-Path $versionsRoot $Version
$targetExe = Join-Path $targetRoot 'simple_kiosk.exe'
$targetData = Join-Path $targetRoot 'data'
if (-not (Test-Path -LiteralPath $targetExe) -or -not (Test-Path -LiteralPath $targetData)) {
    throw "복구 대상이 불완전합니다: $targetRoot"
}

$previous = $null
if (Test-Path -LiteralPath $pointerPath) {
    $pointer = Get-Content -Raw -Encoding UTF8 $pointerPath | ConvertFrom-Json
    $previous = [string]$pointer.currentVersion
}
$temporary = "$pointerPath.tmp"
[ordered]@{
    schemaVersion = 1
    currentVersion = $Version
    previousVersion = $previous
    recoveredAt = (Get-Date).ToUniversalTime().ToString('o')
} | ConvertTo-Json | Set-Content -Encoding UTF8 $temporary
Move-Item -LiteralPath $temporary -Destination $pointerPath -Force
Write-Host "현재 버전을 $Version(으)로 전환했습니다."

if (-not $NoLaunch) {
    & (Join-Path $DataRoot 'launcher.ps1') -DataRoot $DataRoot
}
