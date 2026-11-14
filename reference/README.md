# GAMS reference harness

Produces the GAMS reference dumps that every TIMES.jl parity test compares
against. It runs the unmodified TIMES v4.9.7 source under GAMS; it never edits
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
| `matrix/`, `matrix_dictmap/` | CONVERT `DumpGDX` and `DictMap` of the scalar model | Layer 2 |
| `raw/` | CONVERT dictionary and MPS file (`tjl_model.mps.gz`: CPLEX MPS, gzipped), listings, logs, GAMS profile, each run's patched run file (`tjl_<run>.run`, harness 0.2.2+), the pre-solve run's QA log (`tjl_presolve_qa_check.log`, harness 0.3.2+; `reference/python/keep_qa_log.py` copies it into earlier references from the work folder) | Debugging, timings, switches for `scripts/m11_probe.jl`; the QA log for `scripts/m13_gate.jl` (M1.3 change 25b) |
| `manifest.json` | TIMES version and commit, GAMS version, solver and options, wall times, model attributes (`resGen`, `resUsd`, `numEqu`, `numVar`, `numNZ`, `objVal`, ...), input checksums | Provenance, benchmarks |

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
`-Checkpoints` for both passes).

## Requirements

- GAMS with a licence for the reference solver (CPLEX by default)
- Python 3.11 or later with `pyarrow`, `pandas` and the GAMS Python API:
  `pip install pyarrow pandas "gamsapi[transfer]==<your GAMS version>"`
- Local clones of the TIMES source and the test models:

| Root | Repository | Commit |
| --- | --- | --- |
| `times_source` | `etsap-TIMES/TIMES_model` | `d9a6a25` (v4.9.7; checked) |
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

On James's workstation every run uses at most 12 solver threads and at most
4 GAMS runs run at the same time (James, 29 Oct 2026), so that the machine
stays usable and every test gets the same resources. `make_reference.py`
passes `threads=12` to GAMS and rewrites the `threads` line of each model's
solver option file (e.g. PSI's `threads -1`) in the run's work folder, never
in the source; the manifest records both (`limits`, `patch.solver_option_changes`).
Before each GAMS run it takes one of 4 machine-wide slots (lock files in
`<temp>/timesjl-run-slots`, `reference/python/runlimits.py`) and waits while all
are taken; the wait is recorded as `slot_wait_s` and is not part of `wall_s`.
Change the limits with `--threads`, `--max-parallel` and `--slot-dir` (or
`TIMESJL_THREADS`, `TIMESJL_MAX_PARALLEL`, `TIMESJL_SLOT_DIR`;
`run_references.ps1 -Threads -MaxParallel`); 0 disables a limit. GAMS's own
default is one solver thread, so models without a `threads` option now solve
with 12.

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
an error or an expected dump is missing, and `raw/` holds the listings. A
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
