# Pure mocks: never registers a real task or edits the user's startup folder.
$ErrorActionPreference = 'Stop'
$scriptUnderTest = Join-Path $PSScriptRoot '..\scripts\configure-startup.ps1'
$fixtureRoot = 'B:\Startup & Test'
$fixtureLauncher = Join-Path $fixtureRoot 'ysignage_launcher.exe'

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Reset-Fixture {
    $global:StartupTestState = @{
        Task = $null; Links = @{}; Approval = @{}; Registrations = 0
        TaskNames = @{}; Removed = @(); FailRegistration = $false; FailRemoval = $false
    }
}
function New-FixtureTask([string]$Path, [string]$Arguments, [bool]$Enabled = $true) {
    $actions = [pscustomobject]@{ Entry = [pscustomobject]@{ Path = $Path; Arguments = $Arguments } }
    $actions | Add-Member ScriptMethod Item { param($Index) return $this.Entry }
    return [pscustomobject]@{ Enabled = $Enabled; Definition = [pscustomobject]@{ Actions = $actions } }
}
$fakeFolder = [pscustomobject]@{}
$fakeFolder | Add-Member ScriptMethod GetTask {
    param($Name)
    if ($null -eq $global:StartupTestState.Task) {
        throw [Runtime.InteropServices.COMException]::new('Missing', -2147024894)
    }
    return $global:StartupTestState.Task
}
$fakeFolder | Add-Member ScriptMethod RegisterTask {
    param($Name, $Xml, $Flags, $User, $Password, $Logon, $Sddl)
    if ($global:StartupTestState.FailRegistration) { throw 'Registration denied' }
    Assert-True ($Flags -eq 6 -and $Logon -eq 3 -and $null -eq $Password) 'Unexpected registration security/mode'
    [xml]$definition = $Xml
    Assert-True ($definition.Task.Triggers.LogonTrigger.Delay -eq 'PT0S') 'Startup has a delay'
    Assert-True ($definition.Task.Principals.Principal.RunLevel -eq 'LeastPrivilege') 'Unexpected elevation'
    Assert-True ($definition.Task.Settings.ExecutionTimeLimit -eq 'PT0S') 'Task has an execution limit'
    Assert-True ($definition.Task.Settings.Priority -eq '5') 'Interactive app was assigned background priority'
    $global:StartupTestState.Task = New-FixtureTask $definition.Task.Actions.Exec.Command $definition.Task.Actions.Exec.Arguments
    $global:StartupTestState.Registrations++
    $global:StartupTestState.TaskNames[$Name] = $true
    return $global:StartupTestState.Task
}
$fakeFolder | Add-Member ScriptMethod DeleteTask { param($Name, $Flags) $global:StartupTestState.Task = $null }
$fakeScheduler = [pscustomobject]@{ Folder = $fakeFolder }
$fakeScheduler | Add-Member ScriptMethod Connect {}
$fakeScheduler | Add-Member ScriptMethod GetFolder { param($Path) return $this.Folder }
$fakeShell = [pscustomobject]@{}
$fakeShell | Add-Member ScriptMethod CreateShortcut {
    param($Path)
    return $global:StartupTestState.Links[[IO.Path]::GetFileName($Path)]
}
function New-Object {
    param([Parameter(Position = 0)][string]$TypeName,
          [Parameter(Position = 1)][object[]]$ArgumentList, [string]$ComObject)
    if ($ComObject -eq 'Schedule.Service') { return $fakeScheduler }
    if ($ComObject -eq 'WScript.Shell') { return $fakeShell }
    Microsoft.PowerShell.Utility\New-Object @PSBoundParameters
}
function Test-Path {
    param([string]$LiteralPath, [string]$PathType)
    if ($LiteralPath.StartsWith('HKCU:')) { return $global:StartupTestState.Approval.Count -gt 0 }
    if ([IO.Path]::GetFileName($LiteralPath) -eq 'ysignage_launcher.exe') { return $true }
    return $global:StartupTestState.Links.ContainsKey([IO.Path]::GetFileName($LiteralPath))
}
function Get-ItemProperty { param([string]$LiteralPath) return [pscustomobject]$global:StartupTestState.Approval }
function Remove-Item {
    param([string]$LiteralPath, [switch]$Force)
    if ($global:StartupTestState.FailRemoval) { throw 'Shortcut is locked' }
    $name = [IO.Path]::GetFileName($LiteralPath)
    $global:StartupTestState.Removed += $name
    $global:StartupTestState.Links.Remove($name)
}
function Add-Legacy([string]$Name = 'Simple Kiosk.lnk', [string]$Target = $fixtureLauncher) {
    $global:StartupTestState.Links[$Name] = [pscustomobject]@{ TargetPath = $Target; Arguments = '--startup-mode hidden' }
}
function Invoke-Fixture([string]$Action = 'Migrate') {
    (& $scriptUnderTest -Action $Action -InstallRoot $fixtureRoot) | ConvertFrom-Json
}

Reset-Fixture
Add-Legacy
$status = Invoke-Fixture
Assert-True ($status.registered -and $status.mode -eq 'hidden') 'Legacy mode was not migrated'
Assert-True ($global:StartupTestState.Links.Count -eq 0) 'Legacy shortcut remains'
$null = Invoke-Fixture
Add-Legacy
$null = Invoke-Fixture
Assert-True ($global:StartupTestState.Registrations -eq 1) 'Repeated upgrades re-registered the task'
Assert-True ($global:StartupTestState.Links.Count -eq 0) 'Installer-created duplicate was not removed'
$null = Invoke-Fixture 'Register'
Assert-True ($global:StartupTestState.TaskNames.Count -eq 1) 'More than one task name used'
$null = Invoke-Fixture 'Unregister'
Assert-True ($null -eq $global:StartupTestState.Task) 'Unregister left a task'

foreach ($approvalState in @(3, 7, 1)) {
    Reset-Fixture
    Add-Legacy
    $global:StartupTestState.Approval['Simple Kiosk.lnk'] = [byte[]]@($approvalState, 0, 0, 0)
    $null = Invoke-Fixture
    Assert-True ($global:StartupTestState.Registrations -eq 0 -and $global:StartupTestState.Links.Count -eq 1) 'Disabled/unknown startup state was changed'
}
foreach ($approvalState in @(2, 6)) {
    Reset-Fixture
    Add-Legacy
    $global:StartupTestState.Approval['Simple Kiosk.lnk'] = [byte[]]@($approvalState, 0, 0, 0)
    $null = Invoke-Fixture
    Assert-True ($global:StartupTestState.Registrations -eq 1 -and $global:StartupTestState.Links.Count -eq 0) 'Enabled legacy registration was not migrated'
}
Reset-Fixture
$null = Invoke-Fixture
Assert-True ($global:StartupTestState.Registrations -eq 0) 'Unregistered user was opted in'
Reset-Fixture
$global:StartupTestState.Task = New-FixtureTask $fixtureLauncher '--startup-mode hidden' $false
Add-Legacy
$null = Invoke-Fixture
Assert-True (-not $global:StartupTestState.Task.Enabled -and $global:StartupTestState.Registrations -eq 0) 'Disabled task was enabled'

Reset-Fixture
Add-Legacy
$global:StartupTestState.FailRegistration = $true
try { $null = Invoke-Fixture; throw 'Expected registration failure' } catch {
    Assert-True ($_.Exception.Message -match 'Registration denied') 'Unexpected failure'
}
Assert-True ($global:StartupTestState.Links.Count -eq 1 -and $null -eq $global:StartupTestState.Task) 'Failed registration removed working startup'
Reset-Fixture
Add-Legacy
$global:StartupTestState.FailRemoval = $true
try { $null = Invoke-Fixture; throw 'Expected cleanup failure' } catch {
    Assert-True ($_.Exception.Message -match 'Shortcut is locked') 'Unexpected cleanup failure'
}
$global:StartupTestState.FailRemoval = $false
$null = Invoke-Fixture
Assert-True ($global:StartupTestState.Registrations -eq 1 -and $global:StartupTestState.Links.Count -eq 0) 'Cleanup retry created a second task'
Reset-Fixture
Add-Legacy -Target 'B:\Other Install\ysignage_launcher.exe'
$null = Invoke-Fixture
Assert-True ($global:StartupTestState.Registrations -eq 0 -and $global:StartupTestState.Links.Count -eq 1) 'Another installation was migrated'
Write-Output 'Startup migration, idempotence, disabled-state preservation and recovery checks passed.'
