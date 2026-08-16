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

function Migrate-LegacyShortcuts([string]$NativeLauncher) {
    $shortcutRoots = @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('Startup'),
        [Environment]::GetFolderPath('Programs')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) }
    $legacyScript = [IO.Path]::GetFullPath((Join-Path $DataRoot 'launcher.ps1'))
    $legacyCommand = [IO.Path]::GetFullPath((Join-Path $DataRoot 'SimpleKiosk.cmd'))
    $shell = New-Object -ComObject WScript.Shell
    foreach ($link in (Get-ChildItem -LiteralPath $shortcutRoots -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue)) {
        $shortcut = $shell.CreateShortcut($link.FullName)
        $target = [string]$shortcut.TargetPath
        $arguments = [string]$shortcut.Arguments
        $targetsLegacyCommand = -not [string]::IsNullOrWhiteSpace($target) -and
            [IO.Path]::GetFullPath($target).Equals($legacyCommand, [StringComparison]::OrdinalIgnoreCase)
        $runsLegacyScript = $arguments.IndexOf($legacyScript, [StringComparison]::OrdinalIgnoreCase) -ge 0
        if ($targetsLegacyCommand -or $runsLegacyScript) {
            $shortcut.TargetPath = $NativeLauncher
            $shortcut.Arguments = ''
            $shortcut.WorkingDirectory = $DataRoot
            $shortcut.IconLocation = "$NativeLauncher,0"
            $shortcut.Save()
            Write-Log "Migrated shortcut to native launcher: $($link.FullName)"
        }
    }
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
    $versionRoot = Join-Path $DataRoot "versions\$version"
    $exe = Join-Path $versionRoot 'ysignage.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        $exe = Join-Path $versionRoot 'simple_kiosk.exe'
    }
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
        $packagedNativeLauncher = Join-Path $versionRoot 'ysignage_launcher.exe'
        $installedNativeLauncher = Join-Path $DataRoot 'ysignage_launcher.exe'
        if (Test-Path -LiteralPath $packagedNativeLauncher) {
            Copy-Item -LiteralPath $packagedNativeLauncher -Destination $installedNativeLauncher -Force
            Write-Log "Starting version $version through native launcher"
            Start-Process -FilePath $installedNativeLauncher -ArgumentList @(
                '--data-root', $DataRoot, '--skip-updater-sync'
            ) -WorkingDirectory $DataRoot -WindowStyle Hidden

            # 1.2.11 updater needs this script for rollback until the new app
            # reports ready. Remove legacy entry points only after that signal.
            $ready = $false
            $deadline = (Get-Date).AddSeconds(45)
            $appStatePath = Join-Path $DataRoot 'state\app-state.json'
            while ((Get-Date) -lt $deadline) {
                if (Test-Path -LiteralPath $appStatePath) {
                    try {
                        $appState = Get-Content -Raw -Encoding UTF8 $appStatePath | ConvertFrom-Json
                        if ($appState.status -eq 'ready' -and $appState.version -eq $version) {
                            $ready = $true
                            break
                        }
                    } catch {
                        # 앱이 원자적으로 상태 파일을 교체하는 순간이면 다시 읽는다.
                    }
                }
                Start-Sleep -Seconds 1
            }
            if ($ready) {
                try {
                    Migrate-LegacyShortcuts $installedNativeLauncher
                    Remove-Item -LiteralPath (Join-Path $DataRoot 'SimpleKiosk.cmd') -Force -ErrorAction SilentlyContinue
                    if ([IO.Path]::GetFullPath($PSCommandPath).Equals(
                            [IO.Path]::GetFullPath((Join-Path $DataRoot 'launcher.ps1')),
                            [StringComparison]::OrdinalIgnoreCase)) {
                        Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
                    }
                    Write-Log 'Legacy PowerShell launcher removed after ready signal'
                } catch {
                    Write-Log "Legacy shortcut migration failed: $($_.Exception.Message)"
                }
            } else {
                Write-Log "Version $version did not report ready; keeping legacy launcher for rollback"
            }
            exit 0
        }
        Write-Log "Starting legacy version $version"
        $env:SIMPLE_KIOSK_DATA_DIR = $DataRoot
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -WindowStyle Hidden
        exit 0
    }
    Write-Log "Version $version is incomplete: $exe"
}

throw '실행 가능한 현재/이전 버전을 찾지 못했습니다.'
