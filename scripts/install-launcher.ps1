[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$PackageDirectory,
    [Parameter(Mandatory=$true)][string]$Version,
    [string]$LegacyMenu,
    [string]$OriginalDefaults,
    [string]$DataRoot = "$env:ProgramData\SimpleKiosk"
)
$ErrorActionPreference = 'Stop'
$resolvedPackage = (Resolve-Path -LiteralPath $PackageDirectory).Path
$versionRoot = Join-Path $DataRoot "versions\$Version"
New-Item -ItemType Directory -Force -Path $DataRoot, (Join-Path $DataRoot 'config'), (Join-Path $DataRoot 'media'), (Join-Path $DataRoot 'state'), (Join-Path $DataRoot 'logs'), (Join-Path $DataRoot 'downloads'), (Join-Path $DataRoot 'versions') | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $resolvedPackage 'simple_kiosk.exe'))) { throw 'simple_kiosk.exe가 없습니다.' }
if (Test-Path -LiteralPath $versionRoot) { Remove-Item -LiteralPath $versionRoot -Recurse -Force }
Copy-Item -LiteralPath $resolvedPackage -Destination $versionRoot -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'launcher.ps1') -Destination (Join-Path $DataRoot 'launcher.ps1') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'launcher.cmd') -Destination (Join-Path $DataRoot 'SimpleKiosk.cmd') -Force
if (-not [string]::IsNullOrWhiteSpace($LegacyMenu)) {
    if ([string]::IsNullOrWhiteSpace($OriginalDefaults)) {
        throw '기존 menu.json 마이그레이션에는 해당 버전의 원본 기본 설정이 필요합니다.'
    }
    & (Join-Path $PSScriptRoot 'migrate-menu-config.ps1') -LegacyMenu $LegacyMenu -OriginalDefaults $OriginalDefaults -DataRoot $DataRoot
}
[ordered]@{ schemaVersion=1; currentVersion=$Version; previousVersion=$null; updatedAt=(Get-Date).ToUniversalTime().ToString('o') } |
    ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $DataRoot 'current.json')
& (Join-Path $DataRoot 'launcher.ps1') -DataRoot $DataRoot
