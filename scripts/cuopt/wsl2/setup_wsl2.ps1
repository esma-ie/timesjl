<#
.SYNOPSIS
    Sets up WSL2 Ubuntu with NVIDIA cuOpt on James's Windows workstation,
    for the cuOpt lane of TIMES.jl (scripts/cuopt/README.md).

.DESCRIPTION
    Windows side. From the repository root, in PowerShell (as administrator
    the first time, when WSL itself may need installing):

        powershell -ExecutionPolicy Bypass -File scripts\cuopt\wsl2\setup_wsl2.ps1

    1. Checks the NVIDIA Windows driver and the GPU. cuOpt needs driver
       527.41 or later for CUDA 12 (580 or later for CUDA 13) and a Volta or
       newer GPU; the Quadro RTX 4000 is Turing (compute capability 7.5).
    2. Updates WSL and installs the Ubuntu distribution (Ubuntu-26.04 when
       WSL offers it, else Ubuntu-24.04). A new distribution asks for a Linux
       user name and password; run this script again after that.
    3. Writes %USERPROFILE%\.wslconfig (processors, optional memory) unless
       one exists already.
    4. Runs setup_cuopt.sh inside Ubuntu: Julia, the cuOpt 26.10 library,
       a TIMESjl checkout on the Linux side, a GPU smoke test and demo12.

    Nothing of GAMS, CPLEX, VEDA or the reference runs on Windows changes.
    WSL2 is a lightweight VM: shut it down with 'wsl --shutdown'.

.PARAMETER Ref
    Branch or commit of esma-ie/TIMESjl to set up (main once the cuOpt lane
    is merged; until then its pull-request branch).
#>
[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu-26.04',
    [string]$Fallback = 'Ubuntu-24.04',
    [ValidateSet('12', '13')][string]$Cuda = '12',
    [int]$Processors = 12,
    [string]$Memory = '',          # e.g. '128GB'; empty: WSL's default (half of the RAM)
    [string]$Ref = 'main',
    [switch]$NoDemo
)

$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'                # wsl.exe prints UTF-8 instead of UTF-16

function Say([string]$text) { Write-Host "`n== $text" -ForegroundColor Cyan }

# --- 1. Driver and GPU ----------------------------------------------------------
Say 'NVIDIA driver and GPU'
$smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if (-not $smi) { throw 'nvidia-smi not found: install the NVIDIA driver for the Quadro RTX 4000 first.' }
$gpu = (& nvidia-smi --query-gpu=name,driver_version,compute_cap --format=csv,noheader | Select-Object -First 1)
if (-not $gpu) { throw 'nvidia-smi returned no GPU.' }
Write-Host $gpu
$null, $driver, $cc = ($gpu -split ',\s*')
$minDriver = if ($Cuda -eq '13') { [version]'580.0' } else { [version]'527.41' }
if ([version]$driver -lt $minDriver) {
    throw "Driver $driver is older than $minDriver, which cuOpt with CUDA $Cuda needs. Update it from nvidia.com."
}
$minCc = if ($Cuda -eq '13') { 7.5 } else { 7.0 }
if ([double]$cc -lt $minCc) { throw "Compute capability $cc is below $minCc (cuOpt, CUDA $Cuda)." }

# --- 2. WSL and the distribution ---------------------------------------------------
Say 'WSL'
$installed = @()
& wsl.exe --status *> $null
if ($LASTEXITCODE -eq 0) {
    & wsl.exe --update
    $installed = @(& wsl.exe --list --quiet | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
$target = @($Distro, $Fallback) | Where-Object { $installed -contains $_ } | Select-Object -First 1
if (-not $target) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw 'Installing WSL or a distribution needs an administrator PowerShell.' }
    $online = (& wsl.exe --list --online) -join "`n"
    $target = if ($online -match "(?m)^\s*$([regex]::Escape($Distro))\s") { $Distro } else { $Fallback }
    if ($target -ne $Distro) { Write-Host "$Distro is not offered by this WSL; installing $Fallback." }
    Write-Host "Installing $target. Create your Linux user when asked, type 'exit', then run this script again."
    & wsl.exe --install -d $target
    return
}
Write-Host "Using $target"

# --- 3. .wslconfig ------------------------------------------------------------------
Say '.wslconfig'
$cfg = Join-Path $env:USERPROFILE '.wslconfig'
if (Test-Path $cfg) {
    Write-Host "$cfg exists; left as it is:"
    Get-Content $cfg | ForEach-Object { Write-Host "   $_" }
} else {
    $lines = @('[wsl2]', "# TIMES.jl cuOpt lane (scripts/cuopt/wsl2/setup_wsl2.ps1): at most $Processors threads",
               "processors=$Processors")
    if ($Memory) { $lines += "memory=$Memory" }
    [IO.File]::WriteAllText($cfg, ($lines -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding $false))
    Write-Host "wrote $cfg; restarting WSL so it takes effect"
    & wsl.exe --shutdown
}

# --- 4. cuOpt inside Ubuntu ------------------------------------------------------------
Say "cuOpt in $target"
# LF line endings whatever the checkout has (Git on Windows may have written CRLF)
$sh = (Get-Content -Raw (Join-Path $PSScriptRoot 'setup_cuopt.sh')) -replace "`r", ''
$tmp = Join-Path $env:TEMP 'timesjl_setup_cuopt.sh'
[IO.File]::WriteAllText($tmp, $sh, (New-Object Text.UTF8Encoding $false))
$linuxTmp = (& wsl.exe -d $target -- wslpath -a ($tmp -replace '\\', '/')).Trim()
$shArgs = @('--cuda', $Cuda, '--ref', $Ref)
if ($NoDemo) { $shArgs += '--no-demo' }
& wsl.exe -d $target -- bash $linuxTmp @shArgs
if ($LASTEXITCODE -ne 0) { throw "setup_cuopt.sh failed (exit code $LASTEXITCODE)." }
Say "Done. Open Ubuntu with: wsl -d $target"
