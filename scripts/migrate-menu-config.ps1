[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$LegacyMenu,
    [Parameter(Mandatory=$true)][string]$OriginalDefaults,
    [string]$DataRoot
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($DataRoot)) {
    $DataRoot = Split-Path -Parent $PSScriptRoot
}

function ConvertTo-Map($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $map = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) { $map[$property.Name] = ConvertTo-Map $property.Value }
        return $map
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [System.Collections.IDictionary]) {
        return @($Value | ForEach-Object { ConvertTo-Map $_ })
    }
    return $Value
}
function Get-Difference($Base, $Current) {
    if ($Base -is [System.Collections.IDictionary] -and $Current -is [System.Collections.IDictionary]) {
        $diff = [ordered]@{}
        foreach ($key in $Current.Keys) {
            if (-not $Base.Contains($key)) { $diff[$key] = $Current[$key]; continue }
            $child = Get-Difference $Base[$key] $Current[$key]
            if ($null -ne $child) { $diff[$key] = $child }
        }
        if ($diff.Count -eq 0) { return $null }
        return $diff
    }
    $baseJson = $Base | ConvertTo-Json -Depth 50 -Compress
    $currentJson = $Current | ConvertTo-Json -Depth 50 -Compress
    if ($baseJson -eq $currentJson) { return $null }
    return $Current
}

$legacyPath = (Resolve-Path -LiteralPath $LegacyMenu).Path
$defaultsPath = (Resolve-Path -LiteralPath $OriginalDefaults).Path
$legacy = ConvertTo-Map (Get-Content -Raw -Encoding UTF8 $legacyPath | ConvertFrom-Json)
$defaults = ConvertTo-Map (Get-Content -Raw -Encoding UTF8 $defaultsPath | ConvertFrom-Json)
if ($legacy -isnot [System.Collections.IDictionary] -or $defaults -isnot [System.Collections.IDictionary]) {
    throw '메뉴 설정 최상위는 객체여야 합니다.'
}

$override = [ordered]@{ schemaVersion = 1 }
foreach ($section in @('layout', 'idle')) {
    $difference = Get-Difference $defaults[$section] $legacy[$section]
    if ($null -ne $difference) { $override[$section] = $difference }
}

$defaultById = @{}
foreach ($item in @($defaults['items'])) { $defaultById[[string]$item['id']] = $item }
$legacyById = @{}
foreach ($item in @($legacy['items'])) { $legacyById[[string]$item['id']] = $item }
$itemOverrides = [ordered]@{}
$additions = @()
foreach ($id in $legacyById.Keys) {
    if ($defaultById.ContainsKey($id)) {
        $difference = Get-Difference $defaultById[$id] $legacyById[$id]
        if ($null -ne $difference) { $itemOverrides[$id] = $difference }
    } else { $additions += $legacyById[$id] }
}
$disabled = @($defaultById.Keys | Where-Object { -not $legacyById.ContainsKey($_) })
$legacyOrder = @($legacy['items'] | ForEach-Object { [string]$_['id'] })
$defaultOrder = @($defaults['items'] | ForEach-Object { [string]$_['id'] })
$items = [ordered]@{ overrides=$itemOverrides; additions=$additions; disabledIds=$disabled }
if (($legacyOrder -join '|') -ne ($defaultOrder -join '|')) { $items.order = $legacyOrder }
$override.items = $items

$configDir = Join-Path $DataRoot 'config'
$backupDir = Join-Path $DataRoot "backups\$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Force -Path $configDir, $backupDir | Out-Null
Copy-Item -LiteralPath $legacyPath -Destination (Join-Path $backupDir 'menu.legacy.json')
Copy-Item -LiteralPath $defaultsPath -Destination (Join-Path $backupDir 'menu.original-defaults.json')
$target = Join-Path $configDir 'menu.override.json'
$temporary = "$target.tmp"
$override | ConvertTo-Json -Depth 50 | Set-Content -Encoding UTF8 $temporary
Move-Item -LiteralPath $temporary -Destination $target -Force
Write-Host "Created override: $target"
Write-Host "Backup: $backupDir"
