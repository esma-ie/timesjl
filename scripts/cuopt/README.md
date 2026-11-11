# cuOpt lane: layer 3 on the GPU

[NVIDIA cuOpt](https://github.com/NVIDIA/cuopt) (Apache-2.0, a COIN-OR
project) solves LPs on the GPU with PDLP and barrier. This lane solves the
model TIMES.jl generates with cuOpt and checks the optimum against GAMS, with
the layer-3 tolerances of `docs/translation-guide.md`:

- the objective within 1e-6 (relative) of every GAMS optimum of the run;
- cuOpt's optimum feasible in GAMS's matrix (1e-6).

It is **informational**. No pull request waits on it, and it changes nothing
TIMES.jl generates (Phase 1). Layer 2 runs first: a run whose matrix differs
from GAMS's is reported as *skipped*, so a cuOpt result is never read against
a translation error. GPU solving belongs to Phase 2 (`docs/phase2-notes.md`,
P2-4); the lane collects the evidence early.

It runs every night in two places (James, 10 Nov 2026):

| Where | What | Results |
| --- | --- | --- |
| GitHub, GPU runner (Tesla T4) | public CI fixtures, at 25, 50 and 100% of the GPU | job summary and a 30-day artifact |
| James's workstation, WSL2 (Quadro RTX 4000) | fixtures and local reference runs (TIM allowed), at 100% | `~/timesjl-cuopt/nightly/` in WSL; never leaves the machine |

## What is pinned, and why

| Setting | Value | Why |
| --- | --- | --- |
| cuOpt | 26.10 (wheel `libcuopt-mathopt-cu12==26.10.*`; `-cu13` with `--cuda 13`) | cuOpt.jl 0.5.0 loads only 26.10; `Project.toml` pins `cuOpt = "=0.5.0"`. Change the two together. |
| Method | `barrier` and `pdlp`, one solve each, both with crossover; `dual_simplex` on request | cuOpt's default, *concurrent*, returns whichever method finishes first, so two nights would not compare. Crossover gives a vertex, as CPLEX's crossover does for the references. |
| PDLP tolerances | 1e-6 (`--pdlp-tol`) | cuOpt's default is 1e-4, too loose for a 1e-6 objective check. |
| Barrier | cuDSS deterministic mode | The same factorisation every night. |
| CPU threads | `TIMESJL_THREADS`, default 12 (4 on the GitHub runner) | The local run limits (CLAUDE.md). They bound cuOpt's CPU side only: presolve, the host side of barrier's factorisation, crossover. The GPU is never limited by them. |
| GPU share | 100% unless `sweep.sh` sets a lower one | See below. |
| Gate | `barrier` (`--gate`) | Only its failures set the exit code; PDLP is reported, as evidence for Phase 2. |

Everything else keeps cuOpt's defaults (including its LP presolve). The
report records every parameter set, the cuOpt version, the GPU, the driver,
the GPU share and the CPU threads.

## GPU-share sweep

`sweep.sh` runs `cuopt_layer3.jl` once per GPU share, one level at a time,
and `sweep_summary.py` puts the levels side by side:

```bash
scripts/cuopt/sweep.sh --out sweep --shares "25 50 100" -- --only demo12_off --quiet
```

- **How a share is set.** NVIDIA MPS (Multi-Process Service) caps a process
  to a percentage of the GPU's threads (Volta and newer); in practice that is
  a share of the SMs, about 10 of a T4's 40 at 25%. Each level gets
  its own MPS daemon with `set_default_active_thread_percentage`, set before
  the run's CUDA context exists; with MPS the 100% level runs under MPS too,
  so the cap is the only thing that changes.
- **Where.** MPS needs native Linux. NVIDIA does not ship it for WSL2, so on
  the workstation only 100% runs; levels below are recorded as *skipped*,
  never run uncapped under their label.
- **What is compared.** cuOpt's own solve time (not Julia start-up or model
  generation), the speed-up of the full GPU over each smaller share, and
  whether the objective is the same at every share. nvidia-smi is sampled
  every second (utilisation, memory, SM clock, power, temperature), and the
  compute processes every two seconds to show that the MPS server carried
  the run.
- **Read with care.** "GPU busy" is the share of *time* a kernel ran, not of
  SMs; a capped level can still read near 100%. A small model (demo12 has
  8,695 rows) cannot fill even a quarter of a GPU, so its times hardly change
  with the share: it measures the fixed costs. Scaling shows on models of
  hundreds of thousands of rows and up.

## Running it by hand

From the repository root on a Linux machine with an NVIDIA GPU (compute
capability 7.0+; 7.5+ for CUDA 13), with `libcuopt_mathopt.so` on
`LD_LIBRARY_PATH` (`wsl2/setup_cuopt.sh` does all of this):

```bash
julia --project=scripts/cuopt -e 'using Pkg; Pkg.resolve(); Pkg.instantiate()'

# the public CI fixtures (test/fixtures/public_fixtures.toml); --only demo12_off for one
julia --project=scripts/cuopt scripts/cuopt/cuopt_layer3.jl cuopt.json --only all --summary cuopt.md

# a reference run on the workstation (as scripts/parity_report.jl --ref)
julia --project=scripts/cuopt scripts/cuopt/cuopt_layer3.jl otus.json --ref ~/timesjl-reference --root otus=../OTUS9r OTUS9r-reference
```

The JSON has the record shape of `scripts/parity_report.jl` (`meta.lane =
"cuopt"`), one layer-3 record per GAMS solver and cuOpt method. It is not
embedded in the dashboard. A report of a model that is not
`redistribute = "public"` (TIM) stays on James's machine: never commit,
attach or publish it.

## Nightly on GitHub

`.github/workflows/nightly-gpu.yml`, at 02:17 UTC and on demand, on the GPU
larger runner named by the repository variable `GPU_RUNNER` (default
`gpu-t4`: Linux, 4 vCPU, Tesla T4 16 GB, NVIDIA GPU-optimised image). On
since 10 Nov 2026; the variable `CUOPT_NIGHTLY=false` switches it off.

What it runs comes from the workflow inputs (manual runs), else these
repository variables, else the defaults:

| Variable | Default | Example |
| --- | --- | --- |
| `CUOPT_FIXTURES` | `demo12_off` | `all` (every public fixture with a GAMS optimum) |
| `CUOPT_GPU_SHARES` | `25 50 100` | `100` |
| `CUOPT_METHODS` | `barrier pdlp` | `barrier pdlp dual_simplex` |

The job summary is `sweep.md`; the whole output directory is kept as an
artifact for 30 days. The workflow has no `pull_request` trigger, so forks
cannot run code on the paid runner.

## On James's workstation (Windows 11, Quadro RTX 4000): WSL2

cuOpt runs on Linux only, and on Windows 11 through WSL2. `wsl2/` sets that up
without touching Windows, GAMS, CPLEX or the reference runs, and registers the
local nightly:

```powershell
# from the Windows checkout's root, as administrator the first time
powershell -ExecutionPolicy Bypass -File scripts\cuopt\wsl2\setup_wsl2.ps1 -RegisterNightly
```

1. `setup_wsl2.ps1` (Windows): checks the driver (527.41+ for CUDA 12) and
   the GPU, installs Ubuntu 26.04 in WSL (24.04 if WSL does not offer it),
   then runs the Linux half. A new distribution asks for a Linux user first;
   run the script again after that. It writes no `.wslconfig` unless
   `-Processors` or `-Memory` is given.
2. `setup_cuopt.sh` (Ubuntu; also works on a native Ubuntu): Julia, the cuOpt
   wheel in `~/.venvs/cuopt`, `~/.config/timesjl/cuopt.env` (sourced from
   `~/.bashrc`), `~/.config/timesjl/cuopt-nightly.conf`, a TIMESjl checkout
   in `~/git/TIMESjl`, a small LP on the GPU (objective 205) and demo12.
3. With `-RegisterNightly`, `register_nightly.ps1` registers the Windows
   scheduled task "TIMESjl cuOpt nightly (WSL2)", every night at 01:17
   (`-NightlyAt`). It runs `nightly_task.py`, which takes one of the
   workstation's four run slots (`reference/python/runlimits.py`, as
   `make_reference.py` does) and runs `nightly_local.sh` in WSL. The task wakes
   the computer, runs while James is logged on, and catches up after a
   missed night. `-Until <date>` sets the last night it may start. James
   (11 Nov 2026): it runs until 8 Dec 2026, then it is stopped and reassessed
   (`register_nightly.ps1 -Distro Ubuntu-24.04 -Until 2026-12-08`).

`nightly_local.sh` moves the WSL checkout to `main` (unless it has local
changes), then solves what `~/.config/timesjl/cuopt-nightly.conf` lists:
`FIXTURES` (default `demo12_off`; `all` for every fixture) and `REF_MODELS`
(reference runs, copied from `C:\git\esma\timesjl-reference` to the Linux
side first). Edit that file to change the set; no commit is needed. Results:
`~/timesjl-cuopt/nightly/<date>/`, `latest` pointing at the newest, 30 nights
kept; from Windows, `\\wsl.localhost\Ubuntu-26.04\home\<user>\timesjl-cuopt\nightly\latest\`.
The task's own log is `%LOCALAPPDATA%\timesjl\cuopt-nightly.log`.

Notes for the workstation:

- **Never install a Linux NVIDIA driver inside WSL.** The Windows driver
  provides the GPU there; the script warns if it finds one.
- **Keep data on the Linux side.** `/mnt/c` is slow; the nightly copies
  reference runs with `rsync` before solving them.
- **Run limits.** A cuOpt run uses at most 12 CPU threads. The scheduled
  nightly holds a Windows run slot; a run started by hand in WSL does not, so
  count it yourself.
- **Timings from WSL are indicative.** Compare them only with each other.
- **The Quadro RTX 4000 has 8 GB.** PDLP needs little memory; barrier's
  factorisation is the part that may not fit on the largest models.
