[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$PackagePath,
    [Parameter(Mandatory=$true)][string]$Version,
    [Parameter(Mandatory=$true)][string]$ExpectedSha256,
    [Parameter(Mandatory=$true)][int]$AppPid,
    [string]$DataRoot = "$env:ProgramData\SimpleKiosk",
    [ValidateRange(2, 10)][int]$RetainVersions = 2,
    [ValidateRange(1, 365)][int]$LogRetentionDays = 30
)

$ErrorActionPreference = 'Stop'
$logPath = Join-Path $DataRoot 'logs\updater.log'
$statePath = Join-Path $DataRoot 'state\update-state.json'
$pointerPath = Join-Path $DataRoot 'current.json'
New-Item -ItemType Directory -Force -Path (Split-Path $logPath), (Split-Path $statePath) | Out-Null
if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 5MB) {
    $rotatedLog = Join-Path (Split-Path $logPath) "updater-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    Move-Item -LiteralPath $logPath -Destination $rotatedLog
}

function Write-Log([string]$Message) {
    "$(Get-Date -Format o) [updater] $Message" | Add-Content -Encoding UTF8 $logPath
}
function Write-State([string]$Status, [string]$ErrorMessage = '') {
    $failureCount = 0
    if (Test-Path -LiteralPath $statePath) {
        try {
            $previousState = Get-Content -Raw -Encoding UTF8 $statePath | ConvertFrom-Json
            if ($previousState.version -eq $Version) { $failureCount = [int]$previousState.failureCount }
        } catch { $failureCount = 0 }
    }
    if ($Status -eq 'failed') { $failureCount++ }
    if ($Status -eq 'installed') { $failureCount = 0 }
    $state = [ordered]@{ schemaVersion=1; status=$Status; version=$Version; failureCount=$failureCount; updatedAt=(Get-Date).ToUniversalTime().ToString('o') }
    if ($ErrorMessage) { $state.error = $ErrorMessage }
    $temporary = "$statePath.tmp"
    $state | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $temporary
    Move-Item -LiteralPath $temporary -Destination $statePath -Force
}
function Write-Pointer([string]$Current, [string]$Previous) {
    $temporary = "$pointerPath.tmp"
    [ordered]@{ schemaVersion=1; currentVersion=$Current; previousVersion=$Previous; updatedAt=(Get-Date).ToUniversalTime().ToString('o') } |
        ConvertTo-Json | Set-Content -Encoding UTF8 $temporary
    Move-Item -LiteralPath $temporary -Destination $pointerPath -Force
}
function Invoke-Maintenance([string]$Current, [string]$Previous) {
    $protected = @($Current, $Previous) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $versionsRoot = Join-Path $DataRoot 'versions'
    $candidates = @(Get-ChildItem -LiteralPath $versionsRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $protected -notcontains $_.Name } |
        Sort-Object LastWriteTimeUtc -Descending)
    $extraSlots = [Math]::Max(0, $RetainVersions - $protected.Count)
    $candidates | Select-Object -Skip $extraSlots | ForEach-Object {
        Write-Log "Removing old version $($_.Name)"
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }

    $cutoff = (Get-Date).AddDays(-$LogRetentionDays)
    Get-ChildItem -LiteralPath (Join-Path $DataRoot 'logs') -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $logPath -and $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force
    Get-ChildItem -LiteralPath (Join-Path $DataRoot 'downloads') -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $PackagePath -and $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
        Remove-Item -Force
}

$tempRoot = Join-Path $DataRoot "downloads\extract-$([Guid]::NewGuid())"
try {
    if (Test-Path -LiteralPath $statePath) {
        $prior = Get-Content -Raw -Encoding UTF8 $statePath | ConvertFrom-Json
        if ($prior.version -eq $Version -and [int]$prior.failureCount -ge 3) {
            throw 'This version is blocked after three failed install attempts.'
        }
    }
    Write-State 'installing'
    if (-not (Test-Path -LiteralPath $PackagePath)) { throw 'Update ZIP not found.' }
    $actualHash = (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $ExpectedSha256.ToLowerInvariant()) { throw 'Update ZIP SHA-256 mismatch.' }

    $process = Get-Process -Id $AppPid -ErrorAction SilentlyContinue
    if ($process) {
        Write-Log "Waiting for app PID $AppPid"
        if (-not $process.WaitForExit(30000)) { throw 'App did not exit within 30 seconds.' }
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $rootFull = [IO.Path]::GetFullPath($tempRoot + [IO.Path]::DirectorySeparatorChar)
    $archive = [IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        foreach ($entry in $archive.Entries) {
            $target = [IO.Path]::GetFullPath((Join-Path $tempRoot $entry.FullName))
            if (-not $target.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Unsafe ZIP entry rejected: $($entry.FullName)"
            }
        }
    } finally { $archive.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($PackagePath, $tempRoot)

    $packageRoot = Get-ChildItem -LiteralPath $tempRoot -Directory | Select-Object -First 1
    if (-not $packageRoot) { $packageRoot = Get-Item -LiteralPath $tempRoot }
    $exe = Join-Path $packageRoot.FullName 'simple_kiosk.exe'
    $data = Join-Path $packageRoot.FullName 'data'
    if (-not (Test-Path -LiteralPath $exe) -or -not (Test-Path -LiteralPath $data)) {
        throw 'Package is missing simple_kiosk.exe or data.'
    }

    $versionRoot = Join-Path $DataRoot "versions\$Version"
    if (Test-Path -LiteralPath $versionRoot) { Remove-Item -LiteralPath $versionRoot -Recurse -Force }
    Move-Item -LiteralPath $packageRoot.FullName -Destination $versionRoot

    $previous = ''
    if (Test-Path -LiteralPath $pointerPath) {
        $pointer = Get-Content -Raw -Encoding UTF8 $pointerPath | ConvertFrom-Json
        $previous = [string]$pointer.currentVersion
    }
    Write-Pointer $Version $previous
    Remove-Item -LiteralPath (Join-Path $DataRoot 'state\app-state.json') -Force -ErrorAction SilentlyContinue
    & (Join-Path $DataRoot 'launcher.ps1') -DataRoot $DataRoot -SkipUpdaterSync

    $deadline = (Get-Date).AddSeconds(45)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1
        $appStatePath = Join-Path $DataRoot 'state\app-state.json'
        if (Test-Path -LiteralPath $appStatePath) {
            $appState = Get-Content -Raw -Encoding UTF8 $appStatePath | ConvertFrom-Json
            if ($appState.status -eq 'ready' -and $appState.version -eq $Version) { $ready = $true; break }
        }
    }
    if (-not $ready) {
        Write-Log "Version $Version health check failed; rolling back to $previous"
        if ([string]::IsNullOrWhiteSpace($previous)) { throw 'Health check failed and no rollback version exists.' }
        Write-Pointer $previous $Version
        & (Join-Path $DataRoot 'launcher.ps1') -DataRoot $DataRoot -SkipUpdaterSync
        throw 'New version health check failed; rolled back.'
    }
    try {
        $packagedLauncher = Join-Path $versionRoot 'updater\launcher.ps1'
        $packagedCommand = Join-Path $versionRoot 'updater\launcher.cmd'
        if (Test-Path -LiteralPath $packagedLauncher) {
            Copy-Item -LiteralPath $packagedLauncher -Destination (Join-Path $DataRoot 'launcher.ps1') -Force
        }
        if (Test-Path -LiteralPath $packagedCommand) {
            Copy-Item -LiteralPath $packagedCommand -Destination (Join-Path $DataRoot 'SimpleKiosk.cmd') -Force
        }
    } catch {
        Write-Log "Launcher synchronization deferred: $($_.Exception.Message)"
    }
    Write-State 'installed'
    Write-Log "Version $Version installed successfully"
    Invoke-Maintenance $Version $previous
} catch {
    Write-State 'failed' $_.Exception.Message
    Write-Log "FAILED: $($_.Exception.Message)"
    exit 1
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
