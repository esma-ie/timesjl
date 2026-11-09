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

## What is pinned, and why

| Setting | Value | Why |
| --- | --- | --- |
| cuOpt | 26.10 (wheel `libcuopt-mathopt-cu12==26.10.*`; `-cu13` with `--cuda 13`) | cuOpt.jl 0.5.0 loads only 26.10; `Project.toml` pins `cuOpt = "=0.5.0"`. Change the two together. |
| Method | `barrier` and `pdlp`, one solve each, both with crossover; `dual_simplex` on request | cuOpt's default, *concurrent*, returns whichever method finishes first, so two nights would not compare. Crossover gives a vertex, as CPLEX's crossover does for the references. |
| PDLP tolerances | 1e-6 (`--pdlp-tol`) | cuOpt's default is 1e-4, too loose for a 1e-6 objective check. |
| Barrier | cuDSS deterministic mode | The same factorisation every night. |
| Threads | `TIMESJL_THREADS`, default 12 | The local run limits (CLAUDE.md). |
| Gate | `barrier` (`--gate`) | Only its failures set the exit code; PDLP is reported, as evidence for Phase 2. |

Everything else keeps cuOpt's defaults (including its LP presolve). The
report records every parameter set, the cuOpt version, the GPU and the
driver.

## Running it

From the repository root on a Linux machine with an NVIDIA GPU (compute
capability 7.0+; 7.5+ for CUDA 13), with `libcuopt_mathopt.so` on
`LD_LIBRARY_PATH` (`wsl2/setup_cuopt.sh` does all of this):

```bash
julia --project=scripts/cuopt -e 'using Pkg; Pkg.instantiate()'

# the public CI fixtures (test/fixtures/public_fixtures.toml): what the nightly workflow runs
julia --project=scripts/cuopt scripts/cuopt/cuopt_layer3.jl cuopt.json --summary cuopt.md

# one fixture, or a reference run on the workstation (as scripts/parity_report.jl --ref)
julia --project=scripts/cuopt scripts/cuopt/cuopt_layer3.jl cuopt.json --only demo12_off
julia --project=scripts/cuopt scripts/cuopt/cuopt_layer3.jl otus.json --ref ~/timesjl-reference --root otus=../OTUS9r OTUS9r-reference
```

The JSON has the record shape of `scripts/parity_report.jl` (`meta.lane =
"cuopt"`), one layer-3 record per GAMS solver and cuOpt method. It is not
embedded in the dashboard. A report of a model that is not
`redistribute = "public"` (TIM) stays on James's machine: never commit,
attach or publish it.

## On James's workstation (Windows 11, Quadro RTX 4000): WSL2

cuOpt runs on Linux only, and on Windows 11 through WSL2. `wsl2/` sets that up
without touching Windows, GAMS, CPLEX or the reference runs:

```powershell
# from the repository root, as administrator the first time
powershell -ExecutionPolicy Bypass -File scripts\cuopt\wsl2\setup_wsl2.ps1 -Ref main
```

1. `setup_wsl2.ps1` (Windows): checks the driver (527.41+ for CUDA 12) and
   the GPU, installs Ubuntu 26.04 in WSL (24.04 if WSL does not offer it),
   writes `%USERPROFILE%\.wslconfig` with `processors=12` unless one exists,
   then runs the Linux half. A new distribution asks for a Linux user first;
   run the script again after that.
2. `setup_cuopt.sh` (Ubuntu; also works on a native Ubuntu): Julia, the cuOpt
   wheel in `~/.venvs/cuopt`, `~/.config/timesjl/cuopt.env` (sourced from
   `~/.bashrc`), a TIMESjl checkout in `~/git/TIMESjl`, a small LP on the GPU
   (objective 205) and demo12.

Notes for the workstation:

- **Never install a Linux NVIDIA driver inside WSL.** The Windows driver
  provides the GPU there; the script warns if it finds one.
- **Keep data on the Linux side.** `/mnt/c` is slow; copy a reference run
  with `rsync` before solving it (the script prints the command).
- **Run limits.** A WSL run counts as one of the four CPU-heavy runs allowed
  at once; the Windows run slots (`reference/python/runlimits.py`) do not see
  WSL. `.wslconfig` caps WSL at 12 processors.
- **Timings from WSL are indicative.** Compare them only with each other.
- **The Quadro RTX 4000 has 8 GB.** PDLP needs little memory; barrier's
  factorisation is the part that may not fit on the largest models.

## Nightly on GitHub

`.github/workflows/nightly-gpu.yml` runs the public fixtures on a GitHub GPU
runner (Tesla T4, 16 GB; Turing, as the Quadro RTX 4000) every night and on
demand. It is off until the repository variable `CUOPT_NIGHTLY` is `true`,
and it runs on the runner named by `GPU_RUNNER` (default `gpu-t4`). Its job
summary is the Markdown table; the JSON is kept as an artifact for 30 days.
