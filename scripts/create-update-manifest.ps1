[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Version,
    [Parameter(Mandatory=$true)][string]$PackagePath,
    [string]$OutputPath = 'dist\update-manifest.json'
)
$ErrorActionPreference = 'Stop'
$Version = $Version.Trim() -replace '^v', ''
if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') {
    throw "Semantic Version 형식이 아닙니다: $Version"
}
$package = Get-Item -LiteralPath $PackagePath
$manifest = [ordered]@{
    schemaVersion = 1
    version = $Version
    channel = 'stable'
    publishedAt = (Get-Date).ToUniversalTime().ToString('o')
    minimumUpdaterVersion = '1.0.0'
    configSchemaVersion = 1
    package = [ordered]@{
        file = $package.Name
        sha256 = (Get-FileHash -LiteralPath $package.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
$output = [IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force -Path (Split-Path $output) | Out-Null
$manifest | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $output
Write-Host "Created: $output"
