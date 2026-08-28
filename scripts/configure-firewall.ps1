[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Install', 'Remove')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$InstallRoot,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$tcpRuleName = 'YSignage Web Admin'
$mdnsRuleName = 'YSignage mDNS Discovery'
$ruleGroup = 'YSignage'
$settingsPath = Join-Path $InstallRoot 'config\admin-api.json'
$statePath = Join-Path $InstallRoot 'state\firewall.json'
$markerPath = Join-Path $InstallRoot 'state\firewall-managed'

$enabled = $true
$port = 80
$mdnsEnabled = $true
if (Test-Path -LiteralPath $settingsPath) {
    try {
        $settings = Get-Content -Raw -Encoding UTF8 -LiteralPath $settingsPath | ConvertFrom-Json
        if ($settings.enabled -is [bool]) { $enabled = [bool]$settings.enabled }
        if ($settings.port -is [int] -and $settings.port -ge 1 -and $settings.port -le 65535) {
            $port = [int]$settings.port
        }
        if ($settings.mdnsEnabled -is [bool]) { $mdnsEnabled = [bool]$settings.mdnsEnabled }
    }
    catch {
        Write-Warning "Could not read admin API settings; using safe defaults: $($_.Exception.Message)"
    }
}

$plan = [ordered]@{
    action = $Action
    installRoot = $InstallRoot
    profile = @('Domain', 'Private')
    remoteAddress = 'LocalSubnet'
    webAdmin = [ordered]@{ enabled = $enabled; protocol = 'TCP'; port = $port }
    mdns = [ordered]@{ enabled = ($enabled -and $mdnsEnabled); protocol = 'UDP'; port = 5353 }
}
if ($DryRun) {
    $plan | ConvertTo-Json -Depth 4
    exit 0
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Administrator privileges are required to change Windows Firewall rules.'
}

function Remove-ManagedFirewallRules {
    foreach ($ruleName in @($tcpRuleName, $mdnsRuleName)) {
        Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue |
            Remove-NetFirewallRule -Confirm:$false
    }
}

Remove-ManagedFirewallRules
Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue

if ($Action -eq 'Remove' -or -not $enabled) {
    exit 0
}

$temporaryPath = "$statePath.tmp"
try {
    New-NetFirewallRule `
        -DisplayName $tcpRuleName `
        -Group $ruleGroup `
        -Direction Inbound `
        -Action Allow `
        -Enabled True `
        -Profile Domain, Private `
        -Protocol TCP `
        -LocalPort $port `
        -RemoteAddress LocalSubnet | Out-Null

    if ($mdnsEnabled) {
        New-NetFirewallRule `
            -DisplayName $mdnsRuleName `
            -Group $ruleGroup `
            -Direction Inbound `
            -Action Allow `
            -Enabled True `
            -Profile Domain, Private `
            -Protocol UDP `
            -LocalPort 5353 `
            -RemoteAddress LocalSubnet | Out-Null
    }

    $stateDirectory = Split-Path -Parent $statePath
    New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null
    $plan.updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    $plan | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -LiteralPath $temporaryPath
    Move-Item -Force -LiteralPath $temporaryPath -Destination $statePath
    Set-Content -Encoding ASCII -LiteralPath $markerPath -Value 'managed'
}
catch {
    Remove-ManagedFirewallRules
    Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
    throw
}
