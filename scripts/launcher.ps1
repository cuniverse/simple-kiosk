[CmdletBinding()]
param(
    [string]$DataRoot,
    [switch]$SkipUpdaterSync
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($DataRoot)) {
    $DataRoot = if ((Split-Path -Leaf $PSScriptRoot) -eq 'updater') {
        Split-Path -Parent $PSScriptRoot
    } else {
        $PSScriptRoot
    }
}
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
        if (-not $SkipUpdaterSync) {
            $sourceUpdater = Join-Path $DataRoot "versions\$version\updater"
            $fixedUpdater = Join-Path $DataRoot 'updater'
            if (Test-Path -LiteralPath $sourceUpdater) {
                New-Item -ItemType Directory -Force -Path $fixedUpdater | Out-Null
                Get-ChildItem -LiteralPath $sourceUpdater -File | ForEach-Object {
                    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $fixedUpdater $_.Name) -Force
                }
                Write-Log "Updater tools synchronized from version $version"
            }
            foreach ($documentName in @(
                'USER_MANUAL.html',
                'INSTALL_GUIDE.md',
                'MENU_CONFIG_GUIDE.md',
                'RELEASE_NOTES.md'
            )) {
                $sourceDocument = Join-Path $DataRoot "versions\$version\$documentName"
                if (Test-Path -LiteralPath $sourceDocument) {
                    Copy-Item -LiteralPath $sourceDocument `
                        -Destination (Join-Path $DataRoot $documentName) -Force
                }
            }
            if (Test-Path -LiteralPath (Join-Path $DataRoot 'USER_MANUAL.html')) {
                Remove-Item -LiteralPath (Join-Path $DataRoot 'USER_MANUAL.md') `
                    -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Log "Starting version $version"
        $env:SIMPLE_KIOSK_DATA_DIR = $DataRoot
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -WindowStyle Hidden
        exit 0
    }
    Write-Log "Version $version is incomplete: $exe"
}

throw '실행 가능한 현재/이전 버전을 찾지 못했습니다.'
