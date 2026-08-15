[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$InstallRoot,
    [Parameter(Mandatory=$true)][string]$Version
)

$ErrorActionPreference = 'Stop'
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$pointerPath = Join-Path $InstallRoot 'current.json'
$previousVersion = $null

if (Test-Path -LiteralPath $pointerPath) {
    try {
        $existing = Get-Content -Raw -Encoding UTF8 $pointerPath | ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace($existing.currentVersion) -and
            $existing.currentVersion -ne $Version) {
            $previousVersion = [string]$existing.currentVersion
        } elseif (-not [string]::IsNullOrWhiteSpace($existing.previousVersion) -and
                  $existing.previousVersion -ne $Version) {
            $previousVersion = [string]$existing.previousVersion
        }
    } catch {
        # 손상된 포인터는 installer가 설치한 버전을 기준으로 복구한다.
    }
}

foreach ($directory in @('config', 'media', 'state', 'logs', 'downloads', 'updater', 'versions')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot $directory) | Out-Null
}

$pointer = [ordered]@{
    schemaVersion = 1
    currentVersion = $Version
    previousVersion = $previousVersion
    updatedAt = (Get-Date).ToUniversalTime().ToString('o')
}
$temporaryPath = "$pointerPath.tmp"
$pointer | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $temporaryPath
Move-Item -Force -LiteralPath $temporaryPath -Destination $pointerPath
