<#
.SYNOPSIS
    Produce the licensed-GAMS (CPLEX) reference runs for TIMES.jl, one model at
    a time, on the machine that holds the GAMS licence.

.DESCRIPTION
    1. Checks git, Python 3.11+, GAMS and its version, and that each solver in
       -Solvers solves a one-row LP under your licence (CPLEX must; HiGHS is
       dropped with a warning if it cannot). A model that lists its own
       `solvers` in reference/suite.toml is run with those, whatever -Solvers
       says (.PARAMETER Solvers).
    2. Clones every model repository into <Workspace>\timesjl-sources and checks
       out the commit pinned in reference/suite.toml. Your own clones elsewhere
       are never touched.
    3. Creates a Python venv (<Workspace>\.timesjl-venv) with pyarrow, pandas and
       the GAMS Python API matching your GAMS version (gamsapi on PyPI). Each
       gamsapi release has wheels for a limited range of Python versions (52.1.0:
       3.10-3.14), so the script tries every 64-bit Python 3.11+ it finds
       (python, the py launcher's 3.13/3.12/3.14/3.11, python3.x) until one
       installs, and rebuilds a venv left broken by an earlier run.
    4. For each model, in suite order (small models first): runs
       reference/python/make_reference.py (both variants, CPLEX first, then
       HiGHS, then CONVERT), runs the M1.0 gate if Julia is on PATH, zips the
       result into <Out>\_packed\<model>.zip and updates <Out>\summary.csv.

    Each model is finished (gated, zipped, summarised) before the next starts,
    so the small M1.1 models are ready long before TIMES-NZ.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\run_references.ps1
    The core tier (reference/suite.toml: one baseline case per model) with CPLEX
    and HiGHS: the everyday development loop.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\run_references.ps1 -Set milestone
    The milestone tier: policy and secondary scenarios and the very large models
    (-Set all for both tiers).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\run_references.ps1 -Set M1.1
    Only the models M1.1 needs: TIMES_Demo demo12.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\run_references.ps1 -Models TIMES_Demo-demo12 -Resume
    One model; -Resume skips model/variant runs that already finished OK.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\run_references.ps1 -Checkpoints -Resume
    M1.3 checkpoints only (harness 0.3.0): the pre-solve run of each core model and
    variant again, adding input/, init/, prep/ and prelv/ to the references that
    exist (make_reference.py --only presolve). No solve; -Resume skips references
    that already have them. No gate, no zips.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\run_references.ps1 -Models JRC-EU-TIMES-cli_ll -Matrix -Resume
    CONVERT only (harness 0.3.1): matrix/, matrix_dictmap/ and raw/tjl_model.mps.gz,
    added to the reference or made without one (make_reference.py --only convert).
    No solve, but CONVERT generates the model, so it needs the licensed GAMS.
    -Resume skips references whose CONVERT run is there and made with -GamsMajor.
    With -Checkpoints as well, both runs (--only presolve,convert). No gate, no zips.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\run_references.ps1 -Postsolve -Resume
    M1.6 (harness 0.3.10): with -Postsolve, -Resume also takes a reference for
    not done when it lacks postsolve/ (the solution before the reports) or vd/
    (gdx2veda's files), and reruns it in full: the two come from the solve run
    that gives final/, so there is no pass that adds them alone. A reference
    whose manifest says why it has none (postsolve_skipped, vd_skipped: stepped,
    stochastic) is done. Without -Postsolve, -Resume does not ask for them.
    Licensed solves. The references of -Out must be of the TIMES version of
    this script's source (v4.9.8): make_reference.py refuses to rerun into a
    folder of v4.9.7 references, so give those their own -Out.

.PARAMETER Solvers
    The GAMS solvers of the solve runs, comma-separated, the reference solver
    first (default CPLEX,HIGHS). They are the solvers of every model that has
    no `solvers` line in reference/suite.toml. A model with one is run with
    its own list, with or without -Solvers (script 0.1.20; James, 14 Nov 2026:
    OTCGEN and OTNYC with CPLEX and HiGHS, OTUS9r with CPLEX only), and -Resume
    reruns it in full when a solve run of that list is missing. -Checkpoints
    and -Matrix make no solve run, so they are not affected.

.PARAMETER Python
    Use only this interpreter for the venv (path to python.exe).

.PARAMETER Threads
    Solver threads per run for every model: GAMS threads= and the threads line
    of each model's solver option file. Default 0: each model's thread class
    (reference/suite.toml `threads`: 6 for the small models, 12 for the large).
    The run pool, James's rule for local runs from 26 Nov 2026
    (reference/python/runlimits.py): a run reserves its class until its barrier
    ends, then fewer; a run starts when its threads (of 48, 2 kept free) and
    its RAM are free.

.PARAMETER MaxParallel
    An optional limit on the number of GAMS runs at a time (default 0: none;
    the pool limits threads and RAM, not runs).

.PARAMETER GamsMajor
    GAMS major version every reference run must be made with (default 54, the
    reference GAMS from 30 Oct 2026, James). The run stops if the GAMS found is
    another major version, and -Resume redoes runs made with another one. ''
    turns the check off (not for references that are compared or published).

.PARAMETER GamsApiVersion
    gamsapi version to install; default is your GAMS version. Only for testing
    or when PyPI has no gamsapi release for your exact GAMS version.
#>
[CmdletBinding()]
param(
    [string]$Workspace = '',
    [string]$Out = '',
    # Tiers of reference/suite.toml (James, 30 Oct 2026): core by default.
    [ValidateSet('core', 'milestone', 'all', 'M1.1')]
    [string]$Set = 'core',
    [string[]]$Models = @(),
    [string]$Solvers = 'CPLEX,HIGHS',
    [string]$Gams = '',
    [string]$Python = '',
    [string]$GamsApiVersion = '',
    # Reference GAMS (James, 30 Oct 2026): every reference is made with GAMS 54.
    [string]$GamsMajor = '54',
    [switch]$Resume,
    [switch]$SkipGate,
    [switch]$SkipPack,
    # M1.3 checkpoints only: make_reference.py --only presolve (no solve, no gate, no zips)
    [switch]$Checkpoints,
    # CONVERT only: make_reference.py --only convert (matrix and MPS; no solve, no gate, no zips)
    [switch]$Matrix,
    # M1.6 (harness 0.3.10): -Resume reruns in full a reference without postsolve/ or vd/
    [switch]$Postsolve,
    # Local run limits: the run pool (James, 26 Nov 2026; reference/python/runlimits.py).
    # Threads 0: each model's class (6 or 12); MaxParallel 0: no limit on the number of runs.
    [int]$Threads = 0,
    [int]$MaxParallel = 0
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ScriptVersion = '0.1.22'  # 0.1.22 (27 Nov 2026): -Postsolve (M1.6: postsolve/ and vd/, harness 0.3.10); 0.1.21 (26 Nov 2026): the run pool (per-model thread class, no run limit)
if ($Checkpoints -or $Matrix) { $SkipGate = $true; $SkipPack = $true }

$OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
$Repo = Split-Path -Parent $PSScriptRoot
if (-not $Workspace) { $Workspace = Split-Path -Parent $Repo }
$Workspace = [System.IO.Path]::GetFullPath($Workspace)
if (-not $Out) { $Out = Join-Path $Workspace 'timesjl-reference' }
$Out = [System.IO.Path]::GetFullPath($Out)
$SrcRoot = Join-Path $Workspace 'timesjl-sources'
$Suite = Join-Path (Join-Path $Repo 'reference') 'suite.toml'

# Repositories and pinned commits; must match the header of reference/suite.toml.
$Sources = @(
    # TIMES v4.9.8 (26 Nov 2026) in its own clone: TIMES_model stays at d9a6a25 (v4.9.7) for the
    # references made with it, which make_reference.py never mixes with v4.9.8 runs.
    @{ Root = 'times_source'; Dir = 'TIMES_model-v4.9.8';   Commit = '7064680'; Url = 'https://github.com/etsap-TIMES/TIMES_model.git' },
    @{ Root = 'times_demo';   Dir = 'TIMES_Demo';           Commit = '962db86'; Url = 'https://github.com/etsap-TIMES/TIMES_Demo.git' },
    # OTUS9r, public from 30 Oct 2026: dd/ added in 68588a6 (EPA original at tag epaus9rt-v20.4)
    @{ Root = 'otus';         Dir = 'OTUS9r';               Commit = '598e179'; Url = 'https://github.com/esma-ie/OTUS9r.git' },
    # OTCGEN and OTNYC, public from 30 Oct 2026: dd/ of the reference cases (EPA originals
    # at tags gcomet-v0.0.0 and comet-nyc-v16.0.1)
    @{ Root = 'otcgen';       Dir = 'OTCGEN';               Commit = '08af95f'; Url = 'https://github.com/esma-ie/OTCGEN.git' },
    @{ Root = 'otnyc';        Dir = 'OTNYC';                Commit = 'bc1d276'; Url = 'https://github.com/esma-ie/OTNYC.git' }
)
# Local sources: folders kept in timesjl-sources that are not git repositories,
# pinned by the SHA-256 of a manifest file (header of reference/suite.toml). A
# missing folder skips the models that need it.
$LocalSources = @(
    @{ Root = 'jrc_eu_times'; Dir = 'JRC-EU-TIMES'; Pin = 'dd/manifest.json';
       Sha256 = '3bfa3fde0a832f798d15b72782a36bc59f86247a77c6318e714ca4aaf8db9ac4' },
    @{ Root = 'times_nz_dd';  Dir = 'TIMES-NZ';     Pin = 'dd/manifest.json';
       Sha256 = 'a4b7514e65143c5aebf4dcf48b2ca0e98076545bd4f1b1516d2785fe7e081b45' },
    @{ Root = 'tim';          Dir = 'TIM';          Pin = 'dd/manifest.json';
       Sha256 = '3ccfc10e1b8df9b6b428988107930d45b2e8790d74abccd547c66fc1dd3f93ef' },
    @{ Root = 'otai';         Dir = 'OTAI';         Pin = 'dd/manifest.json';
       Sha256 = '836edf4d8e06ee2a4e603c90d13f67afb889ec89e424258e69befb9343013a53' }
)

# Models the M1.1 gate needs. Only openly licensed models, plus TIM as a named
# licence exception (local only); see reference/suite.toml and docs/test-models.md.
# The DemoS models were removed on 27 Oct 2026 (no stated licence).
$M11Models = @(
    'TIMES_Demo-demo12'
)
$Variants = @('reduce_off', 'as_run')

function Write-Step([string]$msg) { Write-Host ''; Write-Host "== $msg" -ForegroundColor Cyan }
function Fail([string]$msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 2 }

# Run a native command without PowerShell turning its stderr into errors.
function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments, [string]$WorkDir = '', [string]$LogFile = '')
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    if ($WorkDir) { Push-Location $WorkDir }
    try {
        if ($LogFile) {
            & $Exe @Arguments 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $LogFile -Append | Out-Host
        } else {
            & $Exe @Arguments 2>&1 | ForEach-Object { "$_" } | Out-Host
        }
        return $LASTEXITCODE
    } finally {
        if ($WorkDir) { Pop-Location }
        $ErrorActionPreference = $old
    }
}

function Get-NativeOutput {
    param([string]$Exe, [string[]]$Arguments, [string]$WorkDir = '')
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    if ($WorkDir) { Push-Location $WorkDir }
    try {
        $text = (& $Exe @Arguments 2>&1 | ForEach-Object { "$_" }) -join "`n"
        return @{ Code = $LASTEXITCODE; Text = $text }
    } finally {
        if ($WorkDir) { Pop-Location }
        $ErrorActionPreference = $old
    }
}

function Get-Prop($obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    $p = $obj.PSObject.Properties[$name]
    if ($p) { return $p.Value } else { return $null }
}

# ---------------------------------------------------------------- 1. tools
Write-Step 'Checking tools'
if ($Workspace -match '\s' -or $Out -match '\s') {
    Write-Host "WARNING: '$Workspace' contains a space. GAMS include paths with spaces can fail; if a run stops with an include error, use -Workspace C:\timesjl." -ForegroundColor Yellow
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'git is not on PATH.' }

if (-not $Gams) {
    $cmd = Get-Command gams -ErrorAction SilentlyContinue
    if ($cmd) { $Gams = $cmd.Source }
    elseif ($OnWindows -and (Test-Path 'C:\GAMS')) {
        # Newest install first: C:\GAMS\<major> (recent) or C:\GAMS\win64\<x.y> (older).
        $found = Get-ChildItem 'C:\GAMS' -Recurse -Depth 2 -Filter 'gams.exe' -ErrorAction SilentlyContinue |
            Sort-Object { $n = $_.Directory.Name -replace '[^\d.]', ''; if ($n -match '^(\d+(\.\d+)?)') { [double]$Matches[1] } else { 0 } } -Descending |
            Select-Object -First 1
        if ($found) { $Gams = $found.FullName }
    }
}
if (-not $Gams -or -not (Test-Path $Gams)) { Fail 'GAMS not found. Put it on PATH or pass -Gams <path to gams.exe>.' }
$Gams = (Resolve-Path $Gams).Path
Write-Host "GAMS:   $Gams"

$pre = Join-Path $Out '_preflight'
$Logs = Join-Path $Out '_logs'
New-Item -ItemType Directory -Force -Path $pre, $Logs | Out-Null

# Every Python interpreter we can find; the venv step tries the usable ones in
# this order. A helper file avoids passing quotes to native commands, which
# Windows PowerShell 5.1 mangles.
$pyInfo = Join-Path $pre 'pyinfo.py'
Set-Content -Encoding ASCII -Path $pyInfo -Value @(
    'import os, struct, sys',
    'v = sys.version_info',
    'exe = os.path.realpath(sys.executable)',
    'print("TJLPY|%d.%d.%d|%d|%s" % (v[0], v[1], v[2], struct.calcsize("P") * 8, exe))'
)
$cands = New-Object System.Collections.ArrayList
if ($Python) { [void]$cands.Add(@{ Exe = $Python; Pre = '' }) }
else {
    foreach ($n in @('python', 'python3')) {
        $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { [void]$cands.Add(@{ Exe = $c.Source; Pre = '' }) }
    }
    if (Get-Command py -CommandType Application -ErrorAction SilentlyContinue) {
        foreach ($v in @('3.13', '3.12', '3.14', '3.11')) { [void]$cands.Add(@{ Exe = 'py'; Pre = "-$v" }) }
    }
    foreach ($n in @('python3.13', 'python3.12', 'python3.14', 'python3.11')) {
        $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { [void]$cands.Add(@{ Exe = $c.Source; Pre = '' }) }
    }
}
$PyCands = New-Object System.Collections.ArrayList
$seen = @{}
foreach ($c in $cands) {
    $a = @(); if ($c.Pre) { $a += $c.Pre }; $a += $pyInfo
    $r = Get-NativeOutput $c.Exe $a
    if ($r.Code -ne 0 -or $r.Text -notmatch 'TJLPY\|(\d+)\.(\d+)\.(\d+)\|(\d+)\|([^\r\n]+)') { continue }
    $p = [pscustomobject]@{ Exe = $c.Exe; Pre = $c.Pre; Major = [int]$Matches[1]; Minor = [int]$Matches[2];
                            Version = "$($Matches[1]).$($Matches[2]).$($Matches[3])"; Bits = [int]$Matches[4];
                            Path = $Matches[5].Trim() }
    if ($seen.ContainsKey($p.Path)) { continue }
    $seen[$p.Path] = $true
    if ($p.Major -eq 3 -and $p.Minor -ge 11 -and $p.Bits -eq 64) {
        [void]$PyCands.Add($p)
        Write-Host "Python: $($p.Version) $($p.Path)"
    } else {
        Write-Host "Python: $($p.Version) ($($p.Bits)-bit) $($p.Path) - skipped, needs 64-bit 3.11 or later"
    }
}
if ($PyCands.Count -eq 0) {
    Fail 'No 64-bit Python 3.11 or later found. Install Python 3.13 64-bit (winget install Python.Python.3.13) or pass -Python <path to python.exe>.'
}

# One-row LP per solver: proves the licence and reads the GAMS version.
Set-Content -Encoding ASCII -Path (Join-Path $pre 'tiny.gms') -Value @'
$log TJLVER=%system.gamsReleaseMaint%
positive variable x; variable z; equation e, f;
e.. z =e= x;
f.. x =g= 1;
model tiny /all/;
solve tiny using lp minimizing z;
abort$(tiny.solvestat <> 1 or tiny.modelstat <> 1) 'tiny LP did not solve to optimality';
'@
$GamsVersion = $null
# The solvers a [[model]] block of reference/suite.toml lists for itself (`solvers = ["CPLEX", "HIGHS"]`,
# script 0.1.20), upper case, in its order; none when the block has no such line.
function Get-SuiteSolvers([string]$block) {
    if ($block -match '(?m)^\s*solvers\s*=\s*\[([^\]]*)\]') {
        return @($Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim('"').ToUpper() } | Where-Object { $_ })
    }
    return @()
}
# -Solvers first, then any other solver a model of the suite lists: each is tried once
$wantSolvers = @($Solvers -split ',' | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
$trySolvers = @($wantSolvers)
foreach ($b in ((Get-Content -Raw $Suite) -split '\[\[model\]\]' | Select-Object -Skip 1)) {
    foreach ($s in (Get-SuiteSolvers $b)) { if ($trySolvers -notcontains $s) { $trySolvers += $s } }
}
$passedSolvers = @()   # every solver that passed
$okSolvers = @()       # those of -Solvers: the solvers of a model with no list of its own
foreach ($s in $trySolvers) {
    $r = Get-NativeOutput $Gams @('tiny.gms', "lp=$s", 'lo=3', "o=tiny_$s.lst") $pre
    if ($r.Text -match 'TJLVER=(\d+\.\d+\.\d+)') { $GamsVersion = $Matches[1] }
    if ($r.Code -eq 0) {
        $passedSolvers += $s
        if ($wantSolvers -contains $s) { $okSolvers += $s }
        Write-Host "Solver: $s OK"
    }
    elseif ($s -eq 'CPLEX') { Fail "CPLEX could not solve a one-row LP (GAMS return code $($r.Code)); see $pre\tiny_CPLEX.lst. Check the GAMS licence." }
    else { Write-Host "WARNING: $s could not solve a one-row LP (return code $($r.Code)); continuing without it." -ForegroundColor Yellow }
}
if ($okSolvers.Count -eq 0) { Fail 'No solver passed the preflight.' }
if ($okSolvers[0] -ne 'CPLEX') { Write-Host "NOTE: reference solver (first) is $($okSolvers[0])." -ForegroundColor Yellow }
if (-not $GamsVersion) { Fail "Could not read the GAMS version; see $pre." }
Write-Host "GAMS version: $GamsVersion"
if ($GamsMajor -and ($GamsVersion.Split('.')[0] -ne $GamsMajor)) {
    Fail "GAMS $GamsVersion ($Gams) is not GAMS $GamsMajor, the reference GAMS (James, 30 Oct 2026). Pass -Gams <path to the GAMS $GamsMajor gams.exe>, or put it first on PATH."
}

# ---------------------------------------------------------------- 2. sources
Write-Step "Cloning and pinning model repositories in $SrcRoot"
New-Item -ItemType Directory -Force -Path $SrcRoot | Out-Null
$RootArgs = @()
foreach ($s in $Sources) {
    $dir = Join-Path $SrcRoot $s.Dir
    if ((Test-Path $dir) -and -not (Test-Path (Join-Path $dir '.git'))) {
        # e.g. timesjl-sources\OTUS9r, a local folder until the repository was published
        Fail "$dir exists but is not a git clone of $($s.Url). Move it aside (Rename-Item '$dir' '$($s.Dir)-local') and run again."
    }
    if (-not (Test-Path (Join-Path $dir '.git'))) {
        Write-Host "clone  $($s.Url)"
        if ((Invoke-Native git @('clone', '--quiet', $s.Url, $dir)) -ne 0) { Fail "git clone failed for $($s.Url)." }
    }
    $head = (Get-NativeOutput git @('-C', $dir, 'rev-parse', 'HEAD')).Text.Trim()
    if (-not $head.StartsWith($s.Commit)) {
        Invoke-Native git @('-C', $dir, 'fetch', '--quiet', 'origin') | Out-Null
        if ((Invoke-Native git @('-C', $dir, '-c', 'advice.detachedHead=false', 'checkout', '--quiet', $s.Commit)) -ne 0) {
            Fail "could not check out $($s.Commit) in $dir."
        }
    }
    Write-Host ("{0,-13} {1} @ {2}" -f $s.Root, $s.Dir, $s.Commit)
    $RootArgs += @('--root', "$($s.Root)=$dir")
}
$MissingRoots = @()
foreach ($s in $LocalSources) {
    $dir = Join-Path $SrcRoot $s.Dir
    $pin = Join-Path $dir $s.Pin
    if (-not (Test-Path $pin)) {
        Write-Host ("{0,-13} {1} not found: models that need it are skipped" -f $s.Root, $dir) -ForegroundColor Yellow
        $MissingRoots += $s.Root
        continue
    }
    $h = (Get-FileHash -Algorithm SHA256 -Path $pin).Hash.ToLower()
    if ($h -ne $s.Sha256) { Fail "$pin has SHA-256 $h; reference/suite.toml pins $($s.Sha256)." }
    Write-Host ("{0,-13} {1} (local folder, {2} matches its pin)" -f $s.Root, $s.Dir, $s.Pin)
    $RootArgs += @('--root', "$($s.Root)=$dir")
}

# ---------------------------------------------------------------- 3. venv
Write-Step 'Python environment'
if (-not $GamsApiVersion) { $GamsApiVersion = $GamsVersion }
$Venv = Join-Path $Workspace '.timesjl-venv'
if ($OnWindows) { $VenvPy = Join-Path $Venv 'Scripts\python.exe' } else { $VenvPy = Join-Path (Join-Path $Venv 'bin') 'python' }
$Packages = @('pyarrow', 'pandas', "gamsapi[transfer]==$GamsApiVersion")

function Test-Venv {
    if (-not (Test-Path $VenvPy)) { return $false }
    $r = Get-NativeOutput $VenvPy @('-c', 'import pyarrow, pandas, gams.transfer, gams; print(gams.__version__)')
    return ($r.Code -eq 0 -and $r.Text.Trim().EndsWith($GamsApiVersion))
}

if (Test-Venv) {
    Write-Host "venv: $Venv (already has gamsapi $GamsApiVersion)"
} else {
    # Rebuild from scratch with each usable Python in turn. Wheels only: a
    # missing wheel then fails in seconds instead of attempting a source build.
    $tried = @()
    $built = $false
    foreach ($p in $PyCands) {
        if (Test-Path $Venv) { Remove-Item -Recurse -Force $Venv }
        Write-Host "Python $($p.Version): building venv with $($Packages -join ', ')"
        $pipLog = Join-Path $Logs "pip-python$($p.Version).log"
        if (Test-Path $pipLog) { Remove-Item $pipLog }
        $a = @(); if ($p.Pre) { $a += $p.Pre }; $a += @('-m', 'venv', $Venv)
        if ((Invoke-Native $p.Exe $a) -ne 0 -or -not (Test-Path $VenvPy)) {
            $tried += "Python $($p.Version): could not create a venv"
            continue
        }
        Invoke-Native $VenvPy @('-m', 'pip', 'install', '--quiet', '--disable-pip-version-check', '--upgrade', 'pip') '' $pipLog | Out-Null
        $code = Invoke-Native $VenvPy (@('-m', 'pip', 'install', '--quiet', '--disable-pip-version-check', '--only-binary=:all:') + $Packages) '' $pipLog
        if ($code -eq 0 -and (Test-Venv)) {
            $built = $true
            Write-Host "venv: $Venv (Python $($p.Version), gamsapi $GamsApiVersion)"
            break
        }
        $logText = ''
        if (Test-Path $pipLog) { $logText = Get-Content -Raw $pipLog }
        if ($logText -match 'ProxyError|SSLError|CERTIFICATE_VERIFY_FAILED|Could not fetch URL|Failed to establish a new connection|getaddrinfo failed|Temporary failure in name resolution') {
            Fail "pip could not reach PyPI (network, proxy or certificate problem); see $pipLog."
        }
        $tried += "Python $($p.Version): no matching wheels (see $pipLog)"
        Write-Host "Python $($p.Version): no matching wheels; trying the next Python." -ForegroundColor Yellow
    }
    if (-not $built) {
        if (Test-Path $Venv) { Remove-Item -Recurse -Force $Venv }
        Fail ("could not install gamsapi[transfer]==$GamsApiVersion with any Python found:`n  " + ($tried -join "`n  ") +
              "`nInstall Python 3.13 64-bit (winget install Python.Python.3.13) and run the script again; it finds it through the py launcher.")
    }
}

# ---------------------------------------------------------------- 4. models
if ($Models.Count -eq 0) {
    if ($Set -eq 'M1.1') { $Models = $M11Models }
    else {
        # one entry per [[model]] block, in suite order, with its tier (core when absent)
        $entries = foreach ($b in ((Get-Content -Raw $Suite) -split '\[\[model\]\]' | Select-Object -Skip 1)) {
            if ($b -match '(?m)^name\s*=\s*"([^"]+)"') {
                $n = $Matches[1]
                $t = 'core'
                if ($b -match '(?m)^tier\s*=\s*"([^"]+)"') { $t = $Matches[1] }
                [pscustomobject]@{ Name = $n; Tier = $t }
            }
        }
        if ($Set -eq 'all') { $Models = @($entries | ForEach-Object { $_.Name }) }
        else { $Models = @($entries | Where-Object { $_.Tier -eq $Set } | ForEach-Object { $_.Name }) }
        Write-Host ("tier {0}: {1}" -f $Set, ($Models -join ', '))
    }
}
$Julia = $null
if (-not $SkipGate) {
    $jc = Get-Command julia -ErrorAction SilentlyContinue
    if ($jc) {
        $Julia = $jc.Source
        Write-Step 'Julia project (for the M1.0 gate)'
        if ((Invoke-Native $Julia @("--project=$Repo", '-e', 'using Pkg; Pkg.instantiate()')) -ne 0) {
            Write-Host 'WARNING: Pkg.instantiate failed; skipping the gate.' -ForegroundColor Yellow
            $Julia = $null
        }
    } else {
        Write-Host 'Julia not on PATH: the M1.0 gate is skipped (I run it on my side from the zips).' -ForegroundColor Yellow
    }
}

$Packed = Join-Path $Out '_packed'
New-Item -ItemType Directory -Force -Path $Packed | Out-Null
# a -Checkpoints pass keeps summary.csv as the last full batch left it
if ($Checkpoints) { $SummaryCsv = Join-Path $Out 'summary-checkpoints.csv' }
elseif ($Matrix) { $SummaryCsv = Join-Path $Out 'summary-matrix.csv' }
else { $SummaryCsv = Join-Path $Out 'summary.csv' }
$Summary = New-Object System.Collections.ArrayList
$started = Get-Date

# Dumps every finished run must have. 'presolve' came with harness 0.2.0
# (20 Oct 2026); a run from an older harness lacks it, so -Resume redoes it.
$RequiredDumps = @('ppm', 'coef', 'final', 'presolve', 'matrix', 'matrix_dictmap')

# GAMS major version of each GAMS run in a manifest (runs.<tag>.gams_version holds
# the first .lst line naming GAMS, e.g. 'GAMS 54.6.1 ...'). A run made with another
# major version than -GamsMajor, or with none recorded, is not finished for -Resume.
function Test-RunGams($m) {
    if (-not $GamsMajor) { return $true }
    $seen = 0
    foreach ($r in @($m.runs.PSObject.Properties)) {
        $gv = Get-Prop $r.Value 'gams_version'
        if (-not $gv) { continue }
        if ($gv -match 'GAMS\s+(\d+)\.') {
            $seen++
            if ($Matches[1] -ne $GamsMajor) { return $false }
        }
    }
    return ($seen -gt 0)
}

# M1.6 (harness 0.3.10): postsolve/ and vd/ are not in $RequiredDumps, because a stepped or
# stochastic run has no postsolve/ and a stochastic run no vd/ (the manifest then says why:
# postsolve_skipped, vd_skipped), and because asking for them reruns every earlier reference.
# -Postsolve asks: the dump or its note, and the first solve run's gdx2veda files or their note.
function Test-Postsolve($m) {
    if ($null -eq (Get-Prop $m.dumps 'postsolve') -and $null -eq (Get-Prop $m 'postsolve_skipped')) { return $false }
    $vd = Get-Prop (Get-Prop $m 'vd') 'vd'
    if ($null -eq $vd) { return ($null -ne (Get-Prop $m 'vd_skipped')) }
    return ((Get-Prop $vd 'returncode') -eq 0)
}

# $need: the solvers the model lists for itself in the suite (none for the others); each must have its solve run.
function Test-RunOK([string]$dir, [string[]]$need = @()) {
    $mf = Join-Path $dir 'manifest.json'
    if (-not (Test-Path $mf)) { return $false }
    $m = Get-Content -Raw $mf | ConvertFrom-Json
    foreach ($d in $RequiredDumps) { if ($null -eq (Get-Prop $m.dumps $d)) { return $false } }
    if ($Postsolve -and -not (Test-Postsolve $m)) { return $false }
    foreach ($s in $need) { if ($null -eq (Get-Prop $m.runs "solve_$($s.ToLower())")) { return $false } }
    if (-not (Test-RunGams $m)) { return $false }
    foreach ($p in $m.dumps.PSObject.Properties) { if ($null -eq $p.Value) { return $false } }
    foreach ($p in $m.runs.PSObject.Properties) { if ($p.Value.returncode -ne 0) { return $false } }
    return $true
}

# M1.3 checkpoints (harness 0.3.0): made by the pre-solve run, so a reference has
# them when every checkpoint dump is there and that run was made with -GamsMajor.
$CheckpointDumps = @('input', 'init', 'prep', 'prelv', 'presolve')
function Test-Checkpoints([string]$dir) {
    $mf = Join-Path $dir 'manifest.json'
    if (-not (Test-Path $mf)) { return $false }
    $m = Get-Content -Raw $mf | ConvertFrom-Json
    foreach ($d in $CheckpointDumps) { if ($null -eq (Get-Prop $m.dumps $d)) { return $false } }
    $p = Get-Prop $m.runs 'presolve'
    if ($null -eq $p -or $p.returncode -ne 0) { return $false }
    if ($GamsMajor -and -not ("$(Get-Prop $p 'gams_version')" -match "GAMS\s+$GamsMajor\.")) { return $false }
    return $true
}

# CONVERT (harness 0.3.1 for --only convert): a reference has its matrix and MPS when
# both matrix dumps and raw/tjl_model.mps.gz are there and the CONVERT run ended with
# return code 0 under -GamsMajor.
function Test-Matrix([string]$dir) {
    $mf = Join-Path $dir 'manifest.json'
    if (-not (Test-Path $mf)) { return $false }
    if (-not (Test-Path (Join-Path $dir 'raw/tjl_model.mps.gz'))) { return $false }
    $m = Get-Content -Raw $mf | ConvertFrom-Json
    foreach ($d in @('matrix', 'matrix_dictmap')) { if ($null -eq (Get-Prop $m.dumps $d)) { return $false } }
    $p = Get-Prop $m.runs 'convert'
    if ($null -eq $p -or $p.returncode -ne 0) { return $false }
    if ($GamsMajor -and -not ("$(Get-Prop $p 'gams_version')" -match "GAMS\s+$GamsMajor\.")) { return $false }
    return $true
}

# The runs a -Checkpoints / -Matrix pass still owes one model/variant (--only).
function Get-OnlyRuns([string]$dir) {
    $runs = @()
    if ($Checkpoints -and -not ($Resume -and (Test-Checkpoints $dir))) { $runs += 'presolve' }
    if ($Matrix -and -not ($Resume -and (Test-Matrix $dir))) { $runs += 'convert' }
    return ,$runs
}

$i = 0
foreach ($model in $Models) {
    $i++
    Write-Step ("[{0}/{1}] {2}" -f $i, $Models.Count, $model)
    $block = (Get-Content -Raw $Suite) -split '\[\[model\]\]' | Where-Object { $_ -match ('name\s*=\s*"' + [regex]::Escape($model) + '"') }
    $needs = @($MissingRoots | Where-Object { $block -match [regex]::Escape('{' + $_ + '}') })
    if ($needs.Count -gt 0) {
        Write-Host "skipped: its source folder ($($needs -join ', ')) is not in $SrcRoot" -ForegroundColor Yellow
        continue
    }
    # the model's own solvers (suite.toml `solvers`), less any that failed the preflight; else those of -Solvers
    $need = @(Get-SuiteSolvers "$block" | Where-Object { $passedSolvers -contains $_ })
    $modelSolvers = $okSolvers
    if ($need.Count -gt 0) { $modelSolvers = $need }
    if (($modelSolvers -join ',') -ne ($okSolvers -join ',') -and -not ($Checkpoints -or $Matrix)) {
        Write-Host "solvers of this model (reference/suite.toml): $($modelSolvers -join ',')"
    }
    $mrBase = @((Join-Path (Join-Path (Join-Path $Repo 'reference') 'python') 'make_reference.py'),
                '--suite', $Suite, '--out', $Out, '--solvers', ($modelSolvers -join ','), '--gams', $Gams,
                '--model', $model, '--threads', $Threads, '--max-parallel', $MaxParallel) + $RootArgs
    if ($Checkpoints -or $Matrix) {
        # one make_reference call per variant, each with the runs that variant still owes
        $did = 0
        foreach ($v in $Variants) {
            $runs = Get-OnlyRuns (Join-Path (Join-Path $Out $model) $v)
            if ($runs.Count -eq 0) { continue }
            $did++
            $log = Join-Path $Logs "$model-$v-$($runs -join '-').log"
            $code = Invoke-Native $VenvPy (@('-u') + $mrBase + @('--only', ($runs -join ','), '--variant', $v)) '' $log
            if ($code -ne 0) { Write-Host "make_reference reported CHECK for $model/$v (see $log)." -ForegroundColor Yellow }
        }
        if ($did -eq 0) { Write-Host 'already done (-Resume)' }
    } else {
        $todo = @($Variants | Where-Object { -not ($Resume -and (Test-RunOK (Join-Path (Join-Path $Out $model) $_) $need)) })
        if ($todo.Count -gt 0) {
            $mrArgs = $mrBase
            foreach ($v in $todo) { $mrArgs += @('--variant', $v) }
            $code = Invoke-Native $VenvPy (@('-u') + $mrArgs) '' (Join-Path $Logs "$model.log")
            if ($code -ne 0) { Write-Host "make_reference reported CHECK for $model (see $Logs\$model.log)." -ForegroundColor Yellow }
        } else {
            Write-Host 'already done (-Resume)'
        }
    }

    foreach ($v in $Variants) {
        $dir = Join-Path (Join-Path $Out $model) $v
        $mf = Join-Path $dir 'manifest.json'
        $row = [ordered]@{ model = $model; variant = $v; status = 'MISSING'; gate = 'skipped'; rows = ''; cols = '';
                           nonzeros = ''; obj_cplex = ''; obj_highs = ''; rel_diff = ''; wall_cplex_s = '';
                           wall_highs_s = ''; wall_convert_s = ''; gams = '' }
        if (Test-Path $mf) {
            $m = Get-Content -Raw $mf | ConvertFrom-Json
            if ($Checkpoints -or $Matrix) {
                # a -Checkpoints / -Matrix pass is OK when the runs it makes are there
                $ok = ((-not $Checkpoints) -or (Test-Checkpoints $dir)) -and ((-not $Matrix) -or (Test-Matrix $dir))
            } else { $ok = Test-RunOK $dir $need }
            if ($ok) { $row.status = 'OK' } else { $row.status = 'CHECK' }
            $c = Get-Prop $m.runs 'solve_cplex'; $h = Get-Prop $m.runs 'solve_highs'; $cv = Get-Prop $m.runs 'convert'
            $ci = Get-Prop $c 'solveinfo'; $hi = Get-Prop $h 'solveinfo'
            $row.rows = Get-Prop $ci 'numequ'; $row.cols = Get-Prop $ci 'numvar'; $row.nonzeros = Get-Prop $ci 'numnz'
            $row.obj_cplex = Get-Prop $ci 'objval'; $row.obj_highs = Get-Prop $hi 'objval'
            if ($row.obj_cplex -ne $null -and $row.obj_highs -ne $null) {
                $den = [math]::Max(1.0, [math]::Abs([double]$row.obj_cplex))
                $row.rel_diff = '{0:E2}' -f ([math]::Abs([double]$row.obj_cplex - [double]$row.obj_highs) / $den)
            }
            $row.wall_cplex_s = Get-Prop $c 'wall_s'; $row.wall_highs_s = Get-Prop $h 'wall_s'
            $row.wall_convert_s = Get-Prop $cv 'wall_s'; $row.gams = Get-Prop $c 'gams_version'
            if ($Julia) {
                $gl = Join-Path $Logs "$model-$v-gate.log"
                if (Test-Path $gl) { Remove-Item $gl }
                $g = Invoke-Native $Julia @("--project=$Repo", (Join-Path (Join-Path $Repo 'scripts') 'm10_gate.jl'), $dir) '' $gl
                if ($g -eq 0) { $row.gate = 'PASS' } else { $row.gate = 'FAIL' }
            }
        }
        [void]$Summary.Add([pscustomobject]$row)
    }

    # redistribute = "summary" (reference/suite.toml): references stay on this machine and only
    # the summary.csv rows may be published, so there is nothing to pack
    if ($block -match 'redistribute\s*=\s*"summary"') {
        Write-Host "not packed: redistribute = summary (references stay on this machine; summary.csv rows may be published)"
    } elseif (-not $SkipPack -and (Test-Path (Join-Path $Out $model))) {
        $zip = Join-Path $Packed "$model.zip"
        if (Test-Path $zip) { Remove-Item $zip }
        Compress-Archive -Path (Join-Path $Out $model) -DestinationPath $zip
        # the zip of a redistribute = "private" model (TIM: reference/suite.toml) is for James's
        # machine only, never a release asset; the marker file travels with the zip
        if ($block -match 'redistribute\s*=\s*"private"') {
            Set-Content -Path (Join-Path $Packed "$model.PRIVATE.txt") -Value "redistribute = private (reference/suite.toml): do not publish this zip or anything derived from it."
            Write-Host ("packed  {0} ({1:N1} MB) PRIVATE: not for publication" -f $zip, ((Get-Item $zip).Length / 1MB)) -ForegroundColor Yellow
        } else {
            Write-Host ("packed  {0} ({1:N1} MB)" -f $zip, ((Get-Item $zip).Length / 1MB))
        }
    }
    $Summary | Export-Csv -NoTypeInformation -Path $SummaryCsv
}

# ---------------------------------------------------------------- 5. report
Write-Step ("Done in {0:N0} min. Summary: {1}" -f ((Get-Date) - $started).TotalMinutes, $SummaryCsv)
$Summary | Format-Table model, variant, status, gate, rows, cols, obj_cplex, rel_diff, wall_cplex_s -AutoSize |
    Out-String -Width 200 | Write-Host
Write-Host "Script $ScriptVersion, GAMS $GamsVersion, solvers $($okSolvers -join ',') (a model's own list in reference/suite.toml comes first), threads $(if ($Threads -gt 0) { $Threads } else { 'per model (6 or 12)' }), run pool of 48 threads (2 kept free)$(if ($MaxParallel -gt 0) { ", at most $MaxParallel runs at a time" }), sources in $SrcRoot"
Write-Host "Send back: $SummaryCsv and the zips in $Packed (start with the M1.1 models)."
$bad = @($Summary | Where-Object { $_.status -ne 'OK' -or $_.gate -eq 'FAIL' })
if ($bad.Count -gt 0) { exit 1 } else { exit 0 }
