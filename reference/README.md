# GAMS reference harness

Produces the GAMS reference dumps that every TIMES.jl parity test compares
against. It runs the unmodified TIMES v4.9.8 source under GAMS; it never edits
TIMES files.

## What it produces

For each model and variant, under `<out>/<model>/<variant>/`:

| Path | Content | Used for |
| --- | --- | --- |
| `ppm/` | Every symbol after preprocessing (after `ppm_ext`, the point of the `DEBUG` dump) | Layer 1, M1.3 |
| `coef/` | Every symbol after coefficient calculation (after `coef_ext`) | Layer 1, M1.2 |
| `presolve/` | Every symbol just before the SOLVE statement: a third run with `SOLVE_NOW=NO`, so `solve.mod` L22 skips the solve and `maindrv.mod` L114 the reports. The state equations are generated from, after `eqmain`, `bndmain`, `pp_qack` and `pp_clean` | Input data for M1.1; layer 1 for sets the equation files compute (e.g. `AFS`) |
| `input/`, `init/`, `prep/`, `prelv/` | M1.3 checkpoints (harness 0.3.0), written by the pre-solve run: every symbol before `$BATINCLUDE maindrv.mod` (the state preprocessing starts from: DD files read, switches set), after the extensions' `init_ext` (`maindrv.mod` L55), at their `prep_ext` (`preppm.mod` L217) and at their `pp_prelv` (`ppmain.mod` L615). With `ppm/` they split preprocessing into four segments (`scripts/m13_inventory.jl`) | Input data and layer 1 for M1.3 (`docs/m13-plan.md`); `input/` is also what the M1.4 DD reader must reproduce |
| `equ/` | Stepped (myopic) runs only (TIMESTEP or FIXBOH; harness 0.3.3), written by the pre-solve run: every symbol after `eqmain.mod` and the extensions' `equ_ext` (`maindrv.mod` L79-80), before the MODEL statement, `bndmain` and `pp_qack`. In a stepped run `presolve/` is not a pre-solve state: with `SOLVE_NOW=NO` the run still goes through the loop of `solve.stp` (`maindrv.mod` L111-113), every step without a solve, so `presolve/` holds the state after the last step | Layer 1 for the preparation of a stepped run (M1.3 change 30); the state the stepped solve starts from (M1.5) |
| `final/` | Every symbol at the end of the run (`gdx=`), including levels and marginals | Layers 3–4 |
| `matrix/`, `matrix_dictmap/` | CONVERT `DumpGDX` and `DictMap` of the scalar model. A stepped run has none at this level: it has one model per step, under `steps/<k>/` | Layer 2 |
| `steps/<k>/` | Stepped (myopic) runs only (harness 0.3.4), one folder per step k = 1, 2, ... of the loop of `solve.stp`: `final/` (every symbol just after the SOLVE of step k: the data that step's model was generated from, and its levels and marginals), `matrix/` and `matrix_dictmap/` (CONVERT's export of that step's model) | Layers 1 to 3 of each step of the stepped solve (`docs/m15-plan.md`) |
| `raw/` | CONVERT dictionary and MPS file (`tjl_model.mps.gz`: CPLEX MPS, gzipped), listings, logs, GAMS profile, each run's patched run file (`tjl_<run>.run`, harness 0.2.2+), the pre-solve run's QA log (`tjl_presolve_qa_check.log`, harness 0.3.2+; `reference/python/keep_qa_log.py` copies it into earlier references from the work folder). A stepped run has them per step: `tjl_model_step<k>.mps.gz`, `tjl_dict_step<k>.txt`, and `tjl_point<k>.gdx`, GAMS's point file (levels and marginals) after the SOLVE of step k | Debugging, timings, switches for `scripts/m11_probe.jl`; the QA log for `scripts/m13_gate.jl` (M1.3 change 25b) |
| `manifest.json` | TIMES version and commit, GAMS version, solver and options, wall times, model attributes (`resGen`, `resUsd`, `numEqu`, `numVar`, `numNZ`, `objVal`, ...), input checksums. For a stepped run also `steps` (how many) and, for the first solve run and the CONVERT run, each step's rows, columns, nonzeros, statuses and objective | Provenance, benchmarks |

Variants: `reduce_off` (forces `$SET REDUCE NO`, used first for matrix
parity) and `as_run` (the model's own settings).

Symbols are stored as Arrow IPC files; the format is described at the top of
[`python/gdx2arrow.py`](python/gdx2arrow.py).

## How it hooks into TIMES

The harness passes the extension tag `TJLREF` to `$BATINCLUDE initmty.mod`.
TIMES adds it to its extension list (initmty.mod L472-473) and `main_ext.mod`
then includes [`gams/ppm_ext.tjlref`](gams/ppm_ext.tjlref) and
[`gams/coef_ext.tjlref`](gams/coef_ext.tjlref) after the standard extensions
at those two stages. A short block after `$BATINCLUDE maindrv.mod` saves the
model attributes. Each change to the run file is recorded in the manifest.

The M1.3 checkpoints use the same mechanism at three more stages TIMES
already offers its extensions: [`gams/init_ext.tjlref`](gams/init_ext.tjlref)
(`maindrv.mod` L55), [`gams/prep_ext.tjlref`](gams/prep_ext.tjlref)
(`preppm.mod` L217) and [`gams/pp_prelv.tjlref`](gams/pp_prelv.tjlref)
(`ppmain.mod` L615). `TJLREF` is the last extension in the list, so each dump
follows the standard extensions' file at that stage (`init_ext.vda`,
`prep_ext.vda`, `pp_prelv.vda`). The first checkpoint has no stage: the run-file
patch puts `execute_unload 'tjl_input.gdx'` just before `$BATINCLUDE
maindrv.mod`. All four dump only when GAMS is started with
`--TJL_CHECKPOINTS=1`, which the harness passes to the pre-solve run alone.
A stepped run has a fifth, [`gams/equ_ext.tjlref`](gams/equ_ext.tjlref)
(`maindrv.mod` L80), which dumps only when `%STEPPED%` is set as well.

### The steps of a stepped run

A stepped (myopic) run (`$SET TIMESTEP n`, or FIXBOH) has no single model:
`solve.stp` solves one model per step, a few periods at a time, and builds
each on the levels of the step before. The reference keeps every step
(harness 0.3.4), again without editing TIMES. TIMES has two hooks of its own
for a web front end, which it includes when the run is started with
`--GAMS_CGI=WWW`: `www_in.cgi` before preprocessing (`maindrv.mod` L50) and
`www_out.cgi` after every SOLVE (`solve.mod` L44), which in a stepped run is
once per step. The harness supplies both files,
[`gams/www_in.cgi`](gams/www_in.cgi) and [`gams/www_out.cgi`](gams/www_out.cgi).
Both leave at their first line unless `%STEPPED%` is set, so GAMS itself
decides whether a run is stepped, and a run that is not stepped is unchanged
(checked on demo12: every symbol of every dump is the same as before, but
for the harness's own record of the solve, which holds run times).

- The first solve run of every model is started with `--GAMS_CGI=WWW
  --TJL_STEPS=DUMP`. After the SOLVE of step k it writes every symbol
  (`tjl_step<k>.gdx`, kept as `steps/<k>/final/`), and GAMS writes its point
  file of that solve (`OPTION SAVEPOINT=2`; kept as `raw/tjl_point<k>.gdx`).
- CONVERT returns no solution, so a plain CONVERT run would build its second
  step on nothing. The CONVERT run of a stepped reference is started with
  `--GAMS_CGI=WWW --TJL_STEPS=LOAD`: after the export of step k it loads the
  point of step k (`execute_loadpoint`), so step k+1 is generated from the
  same levels as in the solve run, and it gives step k+1 its own option file
  (`convert.op2`, ...) so that each step's export has its own file names. The
  manifest records each step's size in both runs and whether they agree
  (`runs.convert.steps_match_solve`); a difference ends the reference with
  `CHECK`.

Checked with GAMS 54.6.1 on the crafted case demo12_step (TIMESTEP 20, three
steps), both variants: the CONVERT run's three models have the solve run's
rows, columns and nonzeros, and HiGHS on each step's MPS file gives the
objective GAMS/CPLEX reports for that step.

Harness 0.3.5 (15 Nov 2026): GAMS writes "N projected" after the number of
single variables in MODEL STATISTICS when it moved N starting levels onto
their bounds, which a later step of a stepped run can do. The harness reads
the line with or without it (0.3.4 took such a step for one without
statistics and ended the reference with `CHECK`). Checked on the crafted
case demo12_step2 (TIMESTEP 20, G_OVERLAP 15), both variants. A reference
made with 0.3.4 stays valid.

`execute_unload` with no symbol list writes every symbol the compiled program
declares, so even the input dump holds symbols TIMES declares later in its
source with data (and empty ones); the pre-solve run skips the reports
(`maindrv.mod` L114), so its dumps lack the report-only symbols the solve run's
`ppm/` has.

### Checkpoints for references that exist: `--only presolve`

`make_reference.py --only presolve` runs only the pre-solve run and adds its
dumps (`presolve/` and the four checkpoints) to an existing reference, keeping
the manifest's other runs and dumps; the pass is recorded under
`presolve_pass`. Where a reference has no `ppm/` or `coef/` yet, the pass
writes those too, so it also makes a complete layer-1 reference for M1.2 and
M1.3. It needs no solve, so it works for every model under the PyPI GAMS demo
licence (tested with GAMS 54.6.1 on TIMES_Demo demo12, OTCGEN and OTNYC: its
demo12 `ppm/` equals the licensed reference's at 1e-9). On James's workstation:
`scripts\run_references.ps1 -Checkpoints -Resume` does it for the core tier.

### Matrix and MPS without a solve: `--only convert`

`make_reference.py --only convert` (harness 0.3.1) runs only the CONVERT run and
adds `matrix/`, `matrix_dictmap/`, `raw/tjl_dict.txt` and `raw/tjl_model.mps.gz`
to a reference, keeping the manifest's other runs and dumps (recorded under
`convert_pass`), or makes a reference with only those when there is none.
`--only presolve,convert` runs both passes. There is no solve, so it fits models
whose full reference would take hours (JRC-EU-TIMES); CONVERT still generates
the model, so it needs a GAMS licence for the model's size. The MPS file is
CONVERT's `CplexMPS` output (`reference/gams/convert.opt`), gzipped; tested
with GAMS 54.6.1 on TIMES_Demo demo12, where it equals the full reference's MPS
file apart from the date line. On James's workstation:
`scripts\run_references.ps1 -Models <model> -Matrix -Resume` (with
`-Checkpoints` for both passes). A stepped reference needs its solve run
first: the pass exports the steps only where `raw/tjl_point<k>.gdx` exist
(harness 0.3.4), so a stepped reference made with an earlier harness is
rerun in full.

## Requirements

- GAMS with a licence for the reference solver (CPLEX by default)
- Python 3.11 or later with `pyarrow`, `pandas` and the GAMS Python API:
  `pip install pyarrow pandas "gamsapi[transfer]==<your GAMS version>"`
- Local clones of the TIMES source and the test models:

| Root | Repository | Commit |
| --- | --- | --- |
| `times_source` | `etsap-TIMES/TIMES_model` | `7064680` (v4.9.8; checked; `run_references.ps1` clones it as `TIMES_model-v4.9.8`. References made before 26 Nov 2026 are v4.9.7, `d9a6a25`, and a `--only` pass never adds v4.9.8 runs to them) |
| `times_demo` | `etsap-TIMES/TIMES_Demo` | `962db86` |
| `times_nz_dd` | local folder `timesjl-sources/TIMES-NZ` (DD export of EECA main 8165e1d, TIMES-NZ 3.0.8) | pinned by the SHA-256 of `dd/manifest.json` |
| `otus` | `esma-ie/OTUS9r` (`dd/`: the Veda DD export of 28 Oct 2026; EPA original at tag `epaus9rt-v20.4`) | `598e179` |
| `otcgen` | `esma-ie/OTCGEN` (`dd/gc_ref`: the Veda DD export of 30 Oct 2026; EPA original, Generative COMET v0.0.0, at tag `gcomet-v0.0.0`) | `08af95f` |
| `otnyc` | `esma-ie/OTNYC` (`dd/s1_nyc_ref`: the Veda DD export of 30 Oct 2026; EPA original, COMET-NYC v16.0.1, at tag `comet-nyc-v16.0.1`) | `bc1d276` |
| `tim` | local folder `timesjl-sources/TIM` (James's export; the licence exception, local only) | pinned by the SHA-256 of `dd/manifest.json` |
| `jrc_eu_times` | local folder `timesjl-sources/JRC-EU-TIMES`: DD and run files extracted from the dumps in `gitea.psi.ch/WIMBY/JRC-EU-TIMES` @ `c18a076` | not git; pinned by the SHA-256 of `dd/manifest.json` (`reference/suite.toml` header) |

TIM returns as a research-only exception once its DD files are in an esma-ie
fork of `MaREI-EPMG/times-ireland-model`. Nothing from the `esma-cgep`
archive is used.

Only models under a clearly stated open-source or open-data licence are
used (see [`docs/test-models.md`](../docs/test-models.md)). Each model's
licence and whether material derived from it may be published with this
repository (`redistribute = public | summary | private`; `summary`: only the
summary results in `summary.csv`, never references or fixtures) is recorded in
`reference/suite.toml`, and `reference/python/test_suite.py` fails on a model
without an open licence unless its entry names an exception (TIM is the only
one). The DemoS models were removed on 27 Oct 2026 (no stated licence);
TIMES-GEO and PROTO on 22 Oct 2026; ETSAP-TIAM is never used.

## Run limits

On James's workstation runs share a pool of threads (James, 26 Nov 2026;
`reference/python/runlimits.py`), which replaced "at most 12 solver threads
per run and at most 4 runs at a time" (29 Oct 2026):

- Each model has a thread class, `threads` in `suite.toml`: 6 for the small
  models, 12 (the default) for the large ones. `make_reference.py` passes it to
  GAMS (`threads=`) and rewrites the `threads` line of the model's solver option
  file (e.g. PSI's `threads -1`) in the run's work folder, never in the source;
  the manifest records both (`limits`, `patch.solver_option_changes`).
- A solve run reserves its class from its start; the pre-solve and CONVERT runs,
  which do not solve, reserve 1. While a run with one SOLVE goes on, the harness
  reads its GAMS log: at CPLEX's "Barrier time" it keeps 4 threads (crossover),
  and once GAMS reads the solution back, 1. A stepped run, or a solver log it does
  not recognise, keeps its class to the end. The manifest records `pool_threads`,
  `pool_phases` and the run's `peak_ram_gb`.
- A run starts only when its threads are free (reserved threads within 48 less
  the 2 kept free; the measured load also leaving 2 CPUs idle) and its RAM is
  free (its last `peak_ram_gb` plus 10%, or 16 GB the first time). There is no
  limit on the number of runs. The ledger is one JSON file per run in
  `<temp>/timesjl-run-slots`, changed under a lock file; the wait to start is
  `slot_wait_s`, not part of `wall_s`. Runs that do not use the ledger (Veda, a
  Julia script started without the launcher below) are seen only through the
  measured load and RAM.

Change it with `--threads` (one count for every model), `--pool` (0 turns the
pool off), `--max-parallel` (an optional run limit) and `--slot-dir` (or
`TIMESJL_THREADS`, `TIMESJL_POOL`, `TIMESJL_MAX_PARALLEL`, `TIMESJL_SLOT_DIR`;
`run_references.ps1 -Threads -MaxParallel`). GAMS's own default is one solver
thread, so models without a `threads` option solve with their class.

### TIMES.jl's Julia scripts: the launcher

A Julia script joins the pool when it is started through
`reference/python/pool_run.py`. Put the launcher, the model's class and `--`
in front of the usual command (PowerShell, from the repository folder):

```
$py = "C:\git\esma\.timesjl-venv\Scripts\python.exe"
& $py reference\python\pool_run.py --threads 6 --label "demo12 from DD" -- julia --project=test scripts\run_dd.jl ..\timesjl-sources\TIMES_Demo\model\demo12.run --solve
& $py reference\python\pool_run.py --model TIMES_Demo-demo12 -- julia --project=test scripts\m13_gate.jl ..\timesjl-reference --from-dd ..\timesjl-sources --solve TIMES_Demo-demo12
```

- `--threads 6` (small model) or `--threads 12` (large) is the class; or
  `--model <name>` takes it from `suite.toml` or `crafted.toml`. `--label` is
  the run's name in the ledger. `--ram-gb N` is the RAM the run needs (16 by
  default); `--timeout-hours H` gives up (exit code 3) if the pool has no room
  in that time, otherwise the launcher waits.
- The launcher waits until the class fits, reserves it, and only then starts
  the command, so the reservation covers model generation. The command gets
  `TIMESJL_THREADS` set to the class, which the scripts give to HiGHS.
- The command's output appears as usual, and its exit code is the launcher's.
  The launcher's own lines start `[pool_run]` and go to the error output: what
  it reserved, and at the end the exit code, the phases and the peak RAM
  (`--quiet` leaves them out, `--record <file>.json` saves them). In a script
  that sends the error output to a file (`2>`), use `--quiet`: Windows
  PowerShell 5.1 shows such lines as errors.
- The reservation drops to 1 thread when the script prints
  `[timesjl-pool] phase=reporting`, which TIMES.jl does once the last solve of
  the process is over (`TIMES.pool_phase`, `src/pool.jl`): `run_dd.jl`,
  `m11_large.jl solve`, and `m11_probe.jl`, `m13_gate.jl --solve` and
  `parity_report.jl` after their last model. A stepped run in `m13_gate.jl`, or
  a run that fails before its last solve, prints nothing and keeps its class to
  its end. The launcher also knows `phase=after-barrier` (the hold after barrier, as for a GAMS run), but
  TIMES.jl does not print it: HiGHS, as the scripts call it, does not say when
  its interior point method ends, so a HiGHS run keeps its class until the
  solve returns.
- The marker lines are printed only under the launcher (it sets
  `TIMESJL_POOL_MARKERS`); a script started as before prints what it printed
  before. Ctrl-C stops the command and frees the reservation.

## Running it

**Windows, licensed GAMS (recommended):** one script does all of the above
and the run itself, one model at a time, small models first:

```
powershell -ExecutionPolicy Bypass -File scripts\run_references.ps1                 # core tier
powershell -ExecutionPolicy Bypass -File scripts\run_references.ps1 -Set milestone  # milestone tier
powershell -ExecutionPolicy Bypass -File scripts\run_references.ps1 -Set all        # whole suite
powershell -ExecutionPolicy Bypass -File scripts\run_references.ps1 -Set M1.1       # M1.1 models only
```

Every reference is made with GAMS 54 (James, 30 Oct 2026). The script stops
if the GAMS it finds (PATH, then the newest install under `C:\GAMS`, or
`-Gams`) is another major version, and `-Resume` treats a run made with
another version as not done, so `-Set all -Resume` brings every reference
to GAMS 54. `-GamsMajor ''` turns the check off for experiments that are not
compared or published.

The suite has two tiers (`tier` in `suite.toml`; James, 30 Oct 2026). The
**core** tier is the everyday development loop: one baseline case per model
(BAU or Reference), so a batch stays short enough to rerun every cycle. The
**milestone** tier holds the policy and secondary scenarios and the very large
models; it runs at milestone gates, or when a change touches a feature only
those cases reach. `make_reference.py --tier core|milestone` selects the same
way.

It checks that CPLEX (and HiGHS) solve a one-row LP under your licence, clones
and pins every repository above into `..\timesjl-sources` (your own clones are
not touched), builds a venv with the GAMS Python API for your GAMS version,
using the first 64-bit Python 3.11+ it finds that has wheels for that API
(GAMS 52.1.0's `gamsapi` stops at Python 3.14, so a default Python 3.15 is
skipped and `py -3.13` used instead), runs this harness, runs the M1.0 gate if Julia is on PATH, and writes
`summary.csv` plus one zip per model in `_packed\`. `-Resume` skips finished
runs; `-Models a,b` picks models. It also runs under PowerShell 7 on Linux.

By hand, one model (both variants):

```
python reference/python/make_reference.py \
    --out ../timesjl-reference \
    --root times_source=../TIMES_model \
    --root times_demo=../TIMES_Demo \
    --model TIMES_Demo-demo12
```

Whole suite, with HiGHS as a second solver:

```
python reference/python/make_reference.py \
    --out ../timesjl-reference --solvers CPLEX,HIGHS \
    --root times_source=../TIMES_model --root times_demo=../TIMES_Demo \
    --root times_nz_dd=../timesjl-sources/TIMES-NZ
```

Each model/variant ends with `OK` or `CHECK`; `CHECK` means a GAMS run returned
an error, an expected dump is missing, or the steps of a stepped run have
another size in the CONVERT run than in the solve run; `raw/` holds the
listings. A
model whose `--root` is missing stops the run before any GAMS call.

## Without a licensed GAMS

The demo licence of the PyPI GAMS system runs the harness itself, but it
solves and exports only models up to 2,000 rows or columns:

```
pip install pyarrow pandas "gamsapi[transfer]==54.6.0" gamspy_base==54.6.0 gamspy_highs==54.6.0
python reference/python/register_highs.py          # one-off: add HiGHS to the PyPI GAMS system
python reference/python/make_reference.py --out ../timesjl-reference \
    --root times_source=../TIMES_model --root times_demo=../TIMES_Demo \
    --model TIMES_Demo-demo12 --solvers HIGHS,CPLEX \
    --gams "$(python -c 'import gamspy_base;print(gamspy_base.directory)')/gams"
```

No model in the suite fits that limit at present: TIMES_Demo demo12 has
8,695 rows with REDUCE off, and TIMES-NZ and TIM are larger, so their solves,
CONVERT exports and all timings need a licensed GAMS. The pre-solve dump needs
no solve and can be made under the demo licence for any model. The M1.0 gate
first passed on 18 Oct 2026 under the demo licence; see `docs/discrepancies.md` ("Settled") for
the CONVERT layouts found by the first run.
