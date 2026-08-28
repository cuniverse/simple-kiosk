[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Version,
    [Parameter(Mandatory=$true)][string]$PackagePath,
    [string]$SetupPath,
    [string]$OutputPath = 'dist\update-manifest.json',
    [string]$MinimumUpdaterVersion = '1.1.0',
    # 이전 앱은 이 값을 자기 설정 스키마와 비교하므로, 업데이트 패키지 형식 자체가
    # 달라지지 않는 한 최초 지원값 1을 유지해야 구버전에서 새 버전으로 올라올 수 있다.
    [ValidateRange(1, 2147483647)][int]$ConfigSchemaVersion = 1,
    [switch]$RequireAuthenticode,
    [string]$SignerThumbprint
)
$ErrorActionPreference = 'Stop'
$Version = $Version.Trim() -replace '^v', ''
if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') {
    throw "Semantic Version 형식이 아닙니다: $Version"
}
if ($MinimumUpdaterVersion -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') {
    throw "최소 Updater 버전 형식이 올바르지 않습니다: $MinimumUpdaterVersion"
}
if ($RequireAuthenticode -and $SignerThumbprint -notmatch '^[0-9a-fA-F]{40,64}$') {
    throw '서명 필수 manifest에는 올바른 SignerThumbprint가 필요합니다.'
}
$package = Get-Item -LiteralPath $PackagePath
$setup = if ([string]::IsNullOrWhiteSpace($SetupPath)) { $null } else { Get-Item -LiteralPath $SetupPath }
$manifest = [ordered]@{
    schemaVersion = 1
    version = $Version
    channel = 'stable'
    publishedAt = (Get-Date).ToUniversalTime().ToString('o')
    minimumUpdaterVersion = $MinimumUpdaterVersion
    configSchemaVersion = $ConfigSchemaVersion
    package = [ordered]@{
        file = $package.Name
        sha256 = (Get-FileHash -LiteralPath $package.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        authenticodeRequired = [bool]$RequireAuthenticode
        signerThumbprint = if ($RequireAuthenticode) { $SignerThumbprint.ToUpperInvariant() } else { $null }
    }
    setup = if ($null -eq $setup) { $null } else { [ordered]@{
        file = $setup.Name
        sha256 = (Get-FileHash -LiteralPath $setup.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    } }
}
$output = [IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force -Path (Split-Path $output) | Out-Null
$manifest | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $output
Write-Host "Created: $output"
