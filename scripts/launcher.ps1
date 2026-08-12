[CmdletBinding()]
param([string]$DataRoot = "$env:ProgramData\SimpleKiosk")

$ErrorActionPreference = 'Stop'
$pointerPath = Join-Path $DataRoot 'current.json'
$logPath = Join-Path $DataRoot 'logs\updater.log'
New-Item -ItemType Directory -Force -Path (Split-Path $logPath) | Out-Null

function Write-Log([string]$Message) {
    "$(Get-Date -Format o) [launcher] $Message" | Add-Content -Encoding UTF8 $logPath
}

if (-not (Test-Path -LiteralPath $pointerPath)) {
    Write-Log 'current.json not found.'
    throw "현재 버전 포인터가 없습니다: $pointerPath"
}

$pointer = Get-Content -Raw -Encoding UTF8 $pointerPath | ConvertFrom-Json
$candidates = @($pointer.currentVersion, $pointer.previousVersion) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Select-Object -Unique

foreach ($version in $candidates) {
    $exe = Join-Path $DataRoot "versions\$version\simple_kiosk.exe"
    if (Test-Path -LiteralPath $exe) {
        Write-Log "Starting version $version"
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -WindowStyle Hidden
        exit 0
    }
    Write-Log "Version $version is incomplete: $exe"
}

throw '실행 가능한 현재/이전 버전을 찾지 못했습니다.'
