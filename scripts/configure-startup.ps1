[CmdletBinding()]
param(
    [ValidateSet('Status', 'Plan', 'Register', 'Unregister', 'Migrate')]
    [string]$Action = 'Status',
    [Parameter(Mandatory = $true)][string]$InstallRoot,
    [ValidateSet('signage', 'hidden')][string]$Mode = 'signage',
    [switch]$OnlyMatchingTarget
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$rootPath = [IO.Path]::GetFullPath($InstallRoot)
$launcherPath = Join-Path $rootPath 'ysignage_launcher.exe'
$userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$taskName = 'ysignage-startup-' + $userSid

function Escape-Xml([string]$Value) { [Security.SecurityElement]::Escape($Value) }
function Same-Path([string]$Left, [string]$Right) {
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
    return [IO.Path]::GetFullPath($Left).Equals([IO.Path]::GetFullPath($Right), [StringComparison]::OrdinalIgnoreCase)
}
function Is-OwnedStartupTarget([string]$Target) {
    if (Same-Path $Target $launcherPath) { return $true }
    if ([string]::IsNullOrWhiteSpace($Target)) { return $false }
    $targetFullPath = [IO.Path]::GetFullPath($Target)
    $insideRoot = $targetFullPath.StartsWith($rootPath.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
    return $insideRoot -and ([IO.Path]::GetFileName($Target) -in @('ysignage.exe', 'simple_kiosk.exe', 'SimpleKiosk.cmd'))
}
function Find-LegacyStartup {
    $shell = New-Object -ComObject WScript.Shell
    $startupFolder = [Environment]::GetFolderPath('Startup')
    foreach ($name in @('여의도성당Signage.lnk', 'Simple Kiosk.lnk', 'SimpleKiosk.lnk')) {
        $shortcutPath = Join-Path $startupFolder $name
        if (-not (Test-Path -LiteralPath $shortcutPath)) { continue }
        $shortcut = $shell.CreateShortcut($shortcutPath)
        if (-not (Is-OwnedStartupTarget ([string]$shortcut.TargetPath))) { continue }
        $approvalPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
        $approval = $null
        if (Test-Path -LiteralPath $approvalPath) {
            $approval = (Get-ItemProperty -LiteralPath $approvalPath).PSObject.Properties[$name].Value
        }
        # Unknown approval states are left alone, like explicitly disabled ones.
        $enabled = $null -eq $approval -or ($approval.Length -gt 0 -and $approval[0] -in @(2, 6))
        return @{ enabled = $enabled; mode = $(if ([string]$shortcut.Arguments -match '--startup-mode\s+hidden') { 'hidden' } else { 'signage' }) }
    }
    return $null
}
function Remove-LegacyShortcuts {
    $startupFolder = [Environment]::GetFolderPath('Startup')
    foreach ($name in @('여의도성당Signage.lnk', 'Simple Kiosk.lnk', 'SimpleKiosk.lnk')) {
        $shortcut = Join-Path $startupFolder $name
        if (Test-Path -LiteralPath $shortcut) {
            if ($OnlyMatchingTarget) {
                $shell = New-Object -ComObject WScript.Shell
                if (-not (Is-OwnedStartupTarget $shell.CreateShortcut($shortcut).TargetPath)) { continue }
            }
            Remove-Item -LiteralPath $shortcut -Force
        }
    }
}

# InteractiveToken uses the signed-in user's desktop without storing a password.
# No logon delay, idle/network requirement, or battery restriction is applied.
function New-StartupXml {
return @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Signage at user logon</Description></RegistrationInfo>
  <Triggers><LogonTrigger><Enabled>true</Enabled><UserId>$(Escape-Xml $userSid)</UserId><Delay>PT0S</Delay></LogonTrigger></Triggers>
  <Principals><Principal id="User"><UserId>$(Escape-Xml $userSid)</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>false</AllowHardTerminate><StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable><RunOnlyIfIdle>false</RunOnlyIfIdle>
    <Enabled>true</Enabled><ExecutionTimeLimit>PT0S</ExecutionTimeLimit><Priority>5</Priority>
  </Settings>
  <Actions Context="User"><Exec><Command>$(Escape-Xml $launcherPath)</Command><Arguments>--startup-mode $Mode</Arguments><WorkingDirectory>$(Escape-Xml $rootPath)</WorkingDirectory></Exec></Actions>
</Task>
"@
}
if ($Action -eq 'Plan') { Write-Output (New-StartupXml); exit 0 }

$scheduler = New-Object -ComObject Schedule.Service
$scheduler.Connect()
$folder = $scheduler.GetFolder('\')
$task = $null
try { $task = $folder.GetTask($taskName) } catch {
    # Missing task is expected; access/service errors must not look unregistered.
    if (($_.Exception.GetBaseException().HResult -band 0xFFFF) -ne 2) { throw }
}

if ($Action -eq 'Migrate') {
    $OnlyMatchingTarget = $true
    if ($null -ne $task) {
        # Keep an existing task's mode and disabled state. Retry only cleanup.
        if ($task.Enabled -and (Same-Path ([string]$task.Definition.Actions.Item(1).Path) $launcherPath)) {
            Remove-LegacyShortcuts
        }
    } else {
        $legacy = Find-LegacyStartup
        if ($null -ne $legacy -and $legacy.enabled) {
            $Mode = $legacy.mode
            $Action = 'Register'
        }
    }
}
if ($Action -eq 'Register') {
    if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) { throw "Launcher not found: $launcherPath" }
    # TASK_CREATE_OR_UPDATE = 6, TASK_LOGON_INTERACTIVE_TOKEN = 3.
    $task = $folder.RegisterTask($taskName, (New-StartupXml), 6, $userSid, $null, 3, $null)
    if (-not $task.Enabled) { throw 'The startup task was not enabled.' }
    # Retain the old working registration if task registration fails.
    Remove-LegacyShortcuts
} elseif ($Action -eq 'Unregister') {
    if ($null -ne $task) {
        $matches = Same-Path ([string]$task.Definition.Actions.Item(1).Path) $launcherPath
        if (-not $OnlyMatchingTarget -or $matches) {
            $folder.DeleteTask($taskName, 0)
            $task = $null
        }
    }
    Remove-LegacyShortcuts
}

$status = @{ supported = $true; registered = $false; targetMatches = $false; mode = $Mode; method = 'task'; taskName = $taskName }
if ($null -ne $task) {
    $execAction = $task.Definition.Actions.Item(1)
    $status.registered = $true
    $status.enabled = [bool]$task.Enabled
    $status.targetPath = [string]$execAction.Path
    $status.targetMatches = Same-Path $status.targetPath $launcherPath
    $status.mode = if ([string]$execAction.Arguments -match '--startup-mode\s+hidden') { 'hidden' } else { 'signage' }
}
$status | ConvertTo-Json -Compress
