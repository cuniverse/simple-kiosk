[CmdletBinding()]
param(
    [string]$DataRoot = "$env:ProgramData\SimpleKiosk",
    [string]$OutputDirectory,
    [switch]$IncludeMenuConfig
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $DataRoot 'diagnostics'
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$archive = Join-Path $OutputDirectory "simple-kiosk-diagnostics-$stamp.zip"
$staging = Join-Path ([IO.Path]::GetTempPath()) "simple-kiosk-diagnostics-$([Guid]::NewGuid())"

try {
    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    $files = @(
        'current.json',
        'config\update-policy.json',
        'state\update-state.json',
        'state\app-state.json',
        'state\config-error.json'
    )
    if ($IncludeMenuConfig) { $files += 'config\menu.override.json' }
    foreach ($relative in $files) {
        $source = Join-Path $DataRoot $relative
        if (Test-Path -LiteralPath $source) {
            $destination = Join-Path $staging $relative
            New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
            Copy-Item -LiteralPath $source -Destination $destination
        }
    }
    $logs = Join-Path $DataRoot 'logs'
    if (Test-Path -LiteralPath $logs) {
        Copy-Item -LiteralPath $logs -Destination (Join-Path $staging 'logs') -Recurse
    }
    [ordered]@{
        createdAt = (Get-Date).ToUniversalTime().ToString('o')
        computerName = $env:COMPUTERNAME
        osVersion = [Environment]::OSVersion.VersionString
        powershellVersion = $PSVersionTable.PSVersion.ToString()
        dataRoot = $DataRoot
        menuConfigIncluded = [bool]$IncludeMenuConfig
    } | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $staging 'environment.json')

    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $archive -CompressionLevel Optimal
    Write-Output $archive
}
finally {
    if (Test-Path -LiteralPath $staging) {
        $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        $resolvedStaging = [IO.Path]::GetFullPath($staging)
        if ($resolvedStaging.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $staging -Recurse -Force
        }
    }
}
