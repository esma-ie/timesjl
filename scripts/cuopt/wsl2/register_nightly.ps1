<#
.SYNOPSIS
    Registers (or removes) the Windows scheduled task that runs the local cuOpt
    nightly in WSL2 on James's workstation (scripts/cuopt/README.md).

.DESCRIPTION
    From the repository root in PowerShell (no administrator needed):

        powershell -ExecutionPolicy Bypass -File scripts\cuopt\wsl2\register_nightly.ps1
        powershell -ExecutionPolicy Bypass -File scripts\cuopt\wsl2\register_nightly.ps1 -Unregister

    The task "TIMESjl cuOpt nightly (WSL2)" runs every night at -At (local
    time) as the current user: python nightly_task.py, which takes one of the
    workstation's four run slots and runs nightly_local.sh in WSL2. It wakes
    the computer if it sleeps, runs when the user is logged on (WSL
    distributions belong to the user), starts as soon as possible after a
    missed night, and never runs twice at once. What it solves is set in
    ~/.config/timesjl/cuopt-nightly.conf inside WSL.

    -Until <date> ends the task: no run starts after that day (James, 11 Nov 2026:
    the local nightly runs until 8 Dec 2026, then is reassessed):

        powershell -ExecutionPolicy Bypass -File scripts\cuopt\wsl2\register_nightly.ps1 -Until 2026-12-08

    This file and nightly_task.py are used from this Windows checkout; the
    WSL checkout (~/git/TIMESjl) is the one the nightly updates and runs.
#>
[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu-26.04',
    [string]$At = '01:17',
    [string]$Until = '',
    [string]$Dir = '~/git/TIMESjl',
    [string]$Python = '',
    [string]$TaskName = 'TIMESjl cuOpt nightly (WSL2)',
    [switch]$Unregister
)

$ErrorActionPreference = 'Stop'

if ($Unregister) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed the scheduled task '$TaskName'."
    return
}

if (-not $Python) { $Python = (Get-Command python -ErrorAction Stop).Source }
if ($Python -match 'WindowsApps') {
    throw "'$Python' is the Microsoft Store stub, not a Python install. Pass -Python <path to python.exe> (the one make_reference.py runs with)."
}
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$task = Join-Path $PSScriptRoot 'nightly_task.py'
if (-not (Test-Path (Join-Path $repo 'reference\python\runlimits.py'))) { throw "reference\python\runlimits.py not found under $repo." }

$action = New-ScheduledTaskAction -Execute $Python -Argument "`"$task`" --distro $Distro --dir $Dir" -WorkingDirectory $repo
$trigger = New-ScheduledTaskTrigger -Daily -At $At
# -Until: the last day a run may start (the trigger's end boundary, 23:59:59 that day)
if ($Until) { $trigger.EndBoundary = ([datetime]$Until).Date.AddDays(1).AddSeconds(-1).ToString('s') }
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 10) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
    -Description 'TIMES.jl: cuOpt layer 3 in WSL2, local only (scripts/cuopt/wsl2/nightly_task.py)' -Force | Out-Null

Write-Host "Registered '$TaskName': every night at $At, $Distro, checkout $Dir."
if ($Until) { Write-Host "  Ends:      no run starts after $(([datetime]$Until).ToString('d MMM yyyy'))." }
Write-Host "  Log:       $env:LOCALAPPDATA\timesjl\cuopt-nightly.log"
Write-Host "  Results:   \\wsl.localhost\$Distro\home\<your Linux user>\timesjl-cuopt\nightly\latest\"
Write-Host "  Run now:   Start-ScheduledTask -TaskName '$TaskName'"
Write-Host "  Remove:    powershell -ExecutionPolicy Bypass -File scripts\cuopt\wsl2\register_nightly.ps1 -Unregister"
