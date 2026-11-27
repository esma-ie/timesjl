# TIMES.jl

A Julia/JuMP translation of the IEA-ETSAP TIMES model generator, validated
against the GAMS code for numerical parity.

> **Status (27 Nov 2026): Phase 1. M1.0 to M1.4 passed; M1.5 and M1.6 under
> way; the Phase 2 speed work has started alongside.**
> TIMES.jl reads a TIMES model from its own `.run` and DD files,
> preprocesses it, builds it and solves it without GAMS. It runs city,
> national and multi-regional models: New York City (OTNYC, OTCGEN), New
> Zealand (TIMES-NZ) and the United States in nine regions (OTUS9r, 2.5
> million rows). On every open test model it builds the same matrix as GAMS,
> and its optimum agrees with GAMS's
> ([Probes against GAMS](#probes-against-gams)). It has no release yet, it
> does not write TIMES's report parameters or VEDA files yet (M1.6), a few
> TIMES features are not translated yet, and its interfaces may still
> change. It is still much slower than GAMS at building a model; that is
> the Phase 2 work. See [Progress](#progress).
>
> TIMES.jl is an independent project of ESMA Ltd. It is not an official
> IEA-ETSAP product and is not endorsed by IEA-ETSAP or the TIMES maintainers.

## Quick start

Try TIMES.jl on your own machine with the open TIMES demo model (demo12): it
reads the model's `.run` and DD files, preprocesses it, builds the LP and
solves it with the open-source solver HiGHS. No GAMS, no solver licence, no cost.

### What you need

| | |
| --- | --- |
| Julia | 1.10 or later, installed with juliaup (below) |
| Internet | on the first run, to download the Julia packages, the TIMES v4.9.8 source and the demo models from GitHub |
| Operating system | Windows or Linux (tested); macOS should work (every dependency, HiGHS included, has macOS builds) but is not tested yet |

You do not need GAMS, CPLEX, Python, VEDA or Git. HiGHS and every other
dependency are Julia packages that Julia installs for you.

### 1. Install Julia

Use juliaup, Julia's official installer, which also keeps Julia up to date:

- **Windows** (PowerShell or Command Prompt): `winget install --id Julia.Julia -e`
  (or install "Julia" from the Microsoft Store)
- **macOS and Linux** (terminal): `curl -fsSL https://install.julialang.org | sh`

Open a new terminal afterwards and check that `julia --version` prints 1.10
or later.

### 2. Install TIMES.jl

Start Julia (type `julia` in a terminal), then at the `julia>` prompt:

```julia
using Pkg
Pkg.add(url="https://github.com/esma-ie/TIMESjl")
```

This installs TIMES.jl and its dependencies (JuMP, HiGHS, Arrow, ...) and
precompiles them, which takes a few minutes the first time. TIMES.jl is not
in Julia's package registry yet, so it is added from its GitHub address.

### 3. Run the demo model

In Julia:

```julia
using TIMES
r = run_model(joinpath(TIMES.times_demo_dir(), "demo12.run"); out="demo12_out")
```

The first call downloads the TIMES v4.9.8 source and the TIMES_Demo models
(each checked by hash; see [Baseline](#baseline)). `run_model` prints one
line per step:

```
== demo12: compiled in 0.9 s (0 compile warnings), input written to ...\demo12_out in 9.3 s
== demo12: preprocessed in 106.4 s; QA log in ...\demo12_out\QA_CHECK.LOG
== demo12: model generated in 6.1 s: 3233 rows, 4485 columns
== demo12: HiGHS OPTIMAL in 1.1 s, objective 2.3960685737007916e7
== demo12: solution written to ...\demo12_out\solution in 6.0 s
```

The rows, columns and objective are the ones GAMS gives for the same model
(objective 23960685.737007827 with CPLEX in the reference run). The first
run in a Julia session is slow, about 3 minutes in all, because Julia
compiles TIMES.jl's code as it first uses it. Further runs in the same
session reuse that compiled code: run the `run_model(...)` line again and
demo12 takes about 2 seconds. So keep the Julia session open between runs.
(Timings on a Windows workstation, 18 Nov 2026.)

`demo12_out` is made in the folder Julia was started in (`pwd()` shows it).
It holds:

- the model's input data as compiled from its DD files (Arrow files);
- `QA_CHECK.LOG`, the QA log TIMES writes;
- `solution/`: the level and marginal of every variable and equation, as
  Arrow files (readable from Julia, Python with `pyarrow`, R with `arrow`).

In Julia, `r.objective` is the objective and `r.model.model` the JuMP model,
for example to inspect it or solve it again with another solver.
`?run_model` at the `julia>` prompt lists every option.

TIMES.jl does not write TIMES's report parameters or VEDA `.vd` files yet
(milestone M1.6), so the results cannot be opened in VEDA.

### 4. Run your own model

```julia
using TIMES
run_model(raw"C:\VEDA\GAMS_WrkTIMES\scenario.run"; dd=[raw"C:\VEDA\GAMS_WrkTIMES"], out="results")
```

- The `.run` file is the one VEDA writes for a scenario (in VEDA's GAMS
  working folder, `GAMS_WrkTIMES` or similar), or one edited by hand.
- `dd` lists the folders that hold the scenario's DD files, searched in
  order. Without it, the `.run` file's own folder is used.
- On Windows, write paths as `raw"C:\..."` (or with forward slashes,
  `"C:/..."`): in a plain Julia string a backslash starts an escape.
- `solve=false` stops after building the model; `optimizer=` takes another
  JuMP solver, such as `Gurobi.Optimizer` if you have it installed and
  licensed.

If the model uses a TIMES feature that TIMES.jl does not translate yet, the
run stops with `not translated` and names the GAMS file it would need (see
[Progress](#progress)). Results come with no comparison against GAMS: to
check a model against GAMS, see [`reference/README.md`](reference/README.md).

### Tips

- **Threads.** HiGHS uses up to 12 threads by default. Pass `threads=4` to
  `run_model`, or set `TIMESJL_THREADS` before starting Julia:
  `$env:TIMESJL_THREADS = "4"` in PowerShell, `set TIMESJL_THREADS=4` in
  Command Prompt, `export TIMESJL_THREADS=4` on macOS and Linux.
- **Solver options.** As GAMS TIMES reads `<solver>.opt`, `run_model` reads
  `highs.opt` from the `.run` file's folder if there is one. It is written as
  a GAMS option file, one HiGHS option per line, with `*` for comment lines:

  ```
  * HiGHS's interior point method, with crossover
  solver ipm
  run_crossover on
  ```

  Pass `optfile="path\to\file.opt"` to read another file, or `optfile=false`
  to read none (`--optfile <file>` and `--no-optfile` for `scripts/run_dd.jl`).
  The run prints the options it used and a note for any line HiGHS does not
  take. VEDA's `cplex.opt` is not read: CPLEX's option names are not HiGHS's,
  and the run says so. The thread limit above still applies.
- **Updating.** `using Pkg; Pkg.update("TIMES")` fetches the latest `main`.
- **Offline or behind a firewall.** Clone
  [etsap-TIMES/TIMES_model](https://github.com/etsap-TIMES/TIMES_model) at
  commit `7064680` and set `TIMESJL_TIMES_SOURCE` to that folder, so the
  TIMES source is not downloaded. Julia uses the usual `HTTPS_PROXY`
  setting for its downloads.

### Working on TIMES.jl itself

To run the tests and the scripts, clone the repository (Julia 1.11 or later
for the `test` environment):

```
git clone https://github.com/esma-ie/TIMESjl.git
cd TIMESjl
julia --project=test -e "using Pkg; Pkg.instantiate()"
julia --project=. -e "using Pkg; Pkg.test()"
```

The last command runs the test set that CI runs on every pull request: unit
tests and the parity checks on demo12 and its crafted variants. From the
clone, `julia --project=test scripts/run_dd.jl <run file> [--dd <folder>]
--solve --out <folder>` runs a model from the terminal, and on Windows you
can drag a `.run` file onto `scripts\run_dd.cmd` in File Explorer.

On Julia 1.10 the `instantiate` command stops with "expected package `TIMES`
to be registered", because 1.10 does not read the `[sources]` entry in
`test/Project.toml`. Start `julia --project=test` and run
`using Pkg; Pkg.develop(path="."); Pkg.instantiate()` instead.

## An experiment in AI-assisted translation

TIMES.jl is also an experiment: how useful is AI at translating a large,
mature GAMS code base such as TIMES into open-source languages and tool
stacks, when every step must reproduce the original's results?

- **Who writes the code.** Almost all of the code, tests and documentation
  here are written by AI models (Anthropic's Claude), working from the TIMES
  v4.9.8 GAMS source under the rules in [`CONTRIBUTING.md`](CONTRIBUTING.md)
  and [`CLAUDE.md`](CLAUDE.md). An AI-written commit ends with a
  `Co-Authored-By: Claude ...` line, as Claude Code supplies it; where that
  line names a model (for example `Claude Fable 5.2`), that model wrote the
  commit. A human
  directs the work, reviews every pull request and decides what is merged.
  The first commit is the exception: it holds the pre-publication work of
  17-30 Oct 2026 in one piece (see below).
- **Why trust it.** Not because of who or what wrote it, but because of the
  checks in [Validation](#validation): every translated equation family is
  compared with reference runs of the GAMS code, and a change that does not
  reproduce GAMS is not merged. Where the GAMS code and the documentation
  disagree, the GAMS code is followed and the disagreement is logged in
  [`docs/discrepancies.md`](docs/discrepancies.md).
- **What is being tested.** How much of TIMES can be translated this way, how
  quickly and at what cost, where AI translation goes wrong (mismatches the
  parity checks catch, behaviour that cannot be confirmed from the source),
  and how much human review it needs.
- **Working in the open.** The commit history, pull requests and
  [`docs/`](docs/) record each step, including the failures, so the
  experiment can be assessed by anyone. Its outcome is open: it may show
  that the approach works, or where it does not. The public history starts
  on 30 Oct 2026 with one commit holding the work of the first two weeks,
  which was developed in a private repository. Its commit-by-commit history
  is not published because it held test material from models without an
  open licence ([`docs/test-models.md`](docs/test-models.md)); the
  [`docs/`](docs/) record those two weeks, including what went wrong.

## Baseline

| Item | Value |
| --- | --- |
| TIMES GAMS source | v4.9.8, [etsap-TIMES/TIMES_model](https://github.com/etsap-TIMES/TIMES_model) @ `7064680` (v4.9.7 @ `d9a6a25` until 26 Nov 2026; the v4.9.8 diff is being translated) |
| Equation reference | TIMES Documentation, Part II |
| Julia | 1.10 or later (developed on 1.13) |

The GAMS code is authoritative. Where it disagrees with the documentation the
difference is logged in [`docs/discrepancies.md`](docs/discrepancies.md).

To read a model's `.run` and `.dd` files, TIMES.jl compiles TIMES's own files as GAMS
does, so it needs the v4.9.8 source. It downloads that commit's GitHub archive on
first use and checks it by hash ([`Artifacts.toml`](Artifacts.toml),
`TIMES.times_source()`). To use a local clone of the same commit instead, set
`TIMESJL_TIMES_SOURCE`. The open demo models (`etsap-TIMES/TIMES_Demo` @ 962db86,
CC BY 4.0, IEA-ETSAP) come the same way (`TIMES.times_demo_dir()`).

## Phases

**Phase 1 — faithful translation.** Same sets, parameters, variables,
equations and coefficients as GAMS, with GAMS names kept. Ported from the
equations outwards:

| Milestone | Scope | Status (27 Nov 2026) |
| --- | --- | --- |
| M1.0 | Repository, CI, GAMS reference harness, comparison tool | passed 18 Oct |
| M1.1 | Variables, core + VDA equations, bounds, objective, built from GAMS-dumped data | passed 21 Oct |
| M1.2 | Coefficients (`coefmain.mod`, `coef_*.mod`) | passed 31 Oct |
| M1.3 | Preprocessing (`ppmain.mod`, `pp_*.mod`, VDA prep, REDUCE) | passed 25 Nov; the stochastic extension, moved out of the gate, is being translated (2 of its 7 changes merged) |
| M1.4 | GAMS-free DD and `.run` reader | passed 25 Nov |
| M1.5 | Run options (OBJ variants, MID_YEAR, DSCAUTO, VAR_UC, FIXBOH, ...) | under way since 14 Nov: stepped (myopic) runs, the solver option file; more options remain |
| M1.6 | Reporting and Veda `.vd` output | started 27 Nov, with the reference harness (GAMS's solution before its report, and its `.vd` files) |
| M1.7 | Phase 1 release and baseline benchmarks | not started |

**Phase 2 — performance.** Faster preprocessing, generation and solver
hand-off, each change held to parity with GAMS. Since 26 Nov the speed work
runs alongside the rest of Phase 1, limited to changes that leave the
generated LP identical (the same rows, columns and order). The target is
model generation within five times GAMS's time on every open model, aimed
for 2 Dec 2026 ([`docs/phase2-notes.md`](docs/phase2-notes.md)). It started
on 27 Nov with the measuring tools: an exact identity check of the LP, a
timing script and a profile.

**Baseline move.** The TIMES source moved from v4.9.7 to v4.9.8 on 26 Nov.
The source download is re-pinned; the v4.9.8 changes to five GAMS files
are still to be translated, and the GAMS reference runs are being redone
with v4.9.8. Until then the results below are against v4.9.7.

## Progress

As of 27 Nov 2026 (`main`):

- **Runs without GAMS.** `run_model` ([`src/run.jl`](src/run.jl); see
  [Quick start](#quick-start)) takes a model's `.run` file and DD files,
  compiles them as GAMS's compile phase does, runs TIMES's preprocessing
  and coefficients, builds the model and solves it with HiGHS. Stepped
  (myopic) runs are solved step by step, as GAMS does.
- **City, national and multi-regional models.** Every open test model
  runs from its own DD files to the same matrix and optimum as GAMS: the
  TIMES demo (demo12), two models of New York City (OTNYC, OTCGEN), New
  Zealand (TIMES-NZ, two scenarios) and the United States in nine regions
  (OTUS9r, two scenarios, up to 2.5 million rows). JRC-EU-TIMES, a
  multi-country model of Europe, matches GAMS to the end of preprocessing.
  See [Probes against GAMS](#probes-against-gams) below. TIMES.jl has not
  been run on a global model yet: the test suite has none, because a test
  model needs an open licence ([`docs/test-models.md`](docs/test-models.md)).
- **CI.** Every pull request runs 36,123 tests (all pass on 27 Nov): demo12
  and crafted variants of it that add features demo12 itself does not use,
  each against fixtures from GAMS.
- **Features.** The core and VDA formulations are translated. The M1.3
  changes merged up to 27 Nov (changes 28 to 70, and 73) added features that had
  been refused, each checked on a crafted demo12 case: trade and storage in
  ASHAR, ANNCOST LEV, stepped (myopic) runs, exchange bounds (IREBND, XBND,
  grid bounds EQ_GR_XBND), commodity and flow bounds as equations (BNDNET,
  BNDPRD, FLOBND, FLOFR), linear dispatching, unit commitment by start-up
  type and its ANNUL, INVCOST and ONLINE attributes, storage cycle limits
  (STGCCL), refinery blending, simulated vintages (CAPVAC), bounds on costs
  (BNDCST), nested user constraints and the VDA betting constraints,
  market-based trade, storage flexibility, commodity flows tied to
  capacity (NCAP_ICOM, NCAP_OCOM, NCAP_COM), residual load curves, damage
  costs (linear form), PTDF power grids, gas grids, dynamic timeslice trees
  (TS_OFF), costs on commodity balances (COM_CSTBAL) and elastic demand
  (the linear form). Of the stochastic extension, the DD reader and the
  scenario tags of every equation are in; the stochastic model itself is
  not.
- **Not translated yet.** These features stop generation with an error
  that names the GAMS file. Still to come in Phase 1: the stochastic
  model, the remaining run options (M1.5), TIMES's report parameters and
  VEDA files (M1.6), and the v4.9.8 changes. Moved after the Phase 1
  release (26 and 27 Nov): MACRO; the mixed-integer and nonlinear
  features (ETL, the DSC lumpy investments, discrete unit commitment,
  TIMES-Micro, nonlinear damage costs); the other extensions (climate,
  ABS, ECB, IER, ...); and the run options VALIDATE, PREP_ANS and
  INTEXT_ONLY ([`docs/m13-plan.md`](docs/m13-plan.md)).
- **Discrepancies.** 46 places where the GAMS code and the documentation
  disagree are logged in [`docs/discrepancies.md`](docs/discrepancies.md).
  Four known differences between TIMES.jl
  and GAMS are listed in [`docs/known-differences.md`](docs/known-differences.md).
- **Dashboard.** [`docs/dashboard/index.html`](docs/dashboard/index.html),
  opened in a browser, shows these results in slides
  ([`docs/dashboard/README.md`](docs/dashboard/README.md)).

Speed was not a Phase 1 aim, and TIMES.jl is slow at building large models
today. Timings are recorded and compared with GAMS for Phase 2
([`docs/timings.md`](docs/timings.md)).

### Probes against GAMS

The probes run TIMES.jl beside GAMS on the same model and compare the
two at each stage, from the DD files to the optimum. Each open model is
run twice, with REDUCE off and as its run file sets it. The table is from
the workstation's nightly batch of 18-19 Nov 2026 (GAMS 54.6.1, CPLEX;
TIMES.jl with HiGHS; TIMES v4.9.7). The batch of 23 Nov 2026, on the code
the M1.3 and M1.4 gates were passed on, gave the same verdicts: every
preprocessing step, all 14 matrices and all 281 checks.

| Model | Scale | Based on | Rows (REDUCE off) | Preprocessing steps | Matrix | Optimum vs GAMS/CPLEX |
| --- | --- | --- | ---: | --- | --- | --- |
| TIMES_Demo demo12 | demo | the IEA-ETSAP demo | 8,695 | match | identical | 4e-15 |
| OTNYC | city | US EPA COMET-NYC | 504,698 | match | identical | 1e-15 |
| OTCGEN | city | US EPA Generative COMET (New York City) | 1,257,132 | match | identical | 2e-15 |
| TIMES-NZ steady | national | New Zealand's TIMES-NZ | 1,408,361 | match | identical | 2e-10 |
| TIMES-NZ shift | national | New Zealand's TIMES-NZ | 1,483,415 | match | identical | 3e-9 (see below) |
| OTUS9r reference | multi-regional | US EPA EPAUS9rT, 9 US regions | 2,174,010 | match | identical | GAMS's optimum checked in TIMES.jl |
| OTUS9r tax1 | multi-regional | US EPA EPAUS9rT, 9 US regions | 2,528,996 | match | identical | GAMS's optimum checked in TIMES.jl |

What each column checks:

- **Preprocessing steps** ([`scripts/m13_probe.jl`](scripts/m13_probe.jl)):
  each of TIMES's 35 preprocessing steps, run from GAMS's own data before
  the step and compared with GAMS's data after it, at 1e-9. 490 of 490
  steps match (batches of 17 and 23 Nov).
- **Matrix** ([`scripts/m13_gate.jl`](scripts/m13_gate.jl) `--from-dd`):
  the whole run from the model's DD files, with every set and parameter
  compared with GAMS at six checkpoints along the way, then every row,
  column, coefficient, right-hand side and bound of the LP against GAMS's
  CONVERT export, at 1e-9. All 14 runs match.
- **Optimum:** the relative difference between HiGHS's objective in
  TIMES.jl and CPLEX's in GAMS, the larger of the model's two runs (the
  tolerance is 1e-6). For OTUS9r, CPLEX's optimum from GAMS is put into
  the TIMES.jl model and checked against every constraint and the
  objective; HiGHS's own solve of OTUS9r is followed separately. For
  TIMES-NZ shift with REDUCE off, HiGHS usually reaches the batch's
  one-hour time limit, as it did on 18-19 Nov (the matrix was identical to
  GAMS's); the 3e-9 is from the daytime batch of 18 Nov, when HiGHS
  finished in 58 minutes. The run as its run file sets it matched at 4e-11.
- Altogether the batch makes 281 checks on these models, and all pass
  ([dashboard](docs/dashboard/index.html)).

JRC-EU-TIMES, a multi-country model of the European energy system, is
followed too; its licence lets us publish summary results only. Its DD
files compile to the same 851 sets and parameters as GAMS in all nine of
its scenarios. Run from GAMS's input dump (scenario cli_ll, REDUCE off and
as run), TIMES.jl now matches GAMS for all 850 sets and parameters at
every checkpoint to the end of preprocessing, and its QA log is identical.
Its matrix and optimum are not compared with GAMS yet.

## Validation

Every change is checked against reference runs of the GAMS code:

| Layer | Check | Tolerance |
| --- | --- | --- |
| Data | Preprocessed sets and parameters vs GAMS dump | 1e-9 |
| Matrix | Rows, columns, coefficients, RHS, bounds vs CONVERT dump | 1e-9 |
| Solution | Objective; each optimum checked in the other model | 1e-6 |
| Reporting | Report parameters and `.vd` files vs GAMS outputs (from M1.6) | 1e-6 |

Reference runs are produced with the harness in [`reference/`](reference/),
and only from test models with a clearly stated open-source or open-data
licence ([`docs/test-models.md`](docs/test-models.md)). TIMES.jl does not
learn from closed or proprietary models.

## Repository layout

```
src/            TIMES module (one Julia file per GAMS file, same stems)
  run.jl        run_model and PRESOLVE_STEPS: a model from its run and DD files
  solver_options.jl  the solver option file run_model reads (highs.opt)
  dd/           the reader of .run and DD files (M1.4)
  prep/         preprocessing (M1.3)
  coef/         coefficients (M1.2)
  model/        variables, equations, bounds, objective (M1.1)
  ext/          the VDA extension and others
  reference/    reading GAMS reference dumps (Arrow) and comparing them
reference/      GAMS harness that produces reference dumps from test models;
                crafted demo12 cases in reference/dd/
scripts/        gates and probes (m13_gate.jl, m13_probe.jl, ...), run_dd.jl,
                parity_report.jl
test/           unit tests and parity tests, fixtures from open models only
docs/           plans, GAMS-to-Julia map, discrepancies, known differences,
                decision log, dashboard
```

## Origins and acknowledgements

TIMES.jl builds on two earlier pieces of work:

- the **TIMES2JuMP feasibility study** for IEA-ETSAP (James Glynn and
  Siddharth Krishna, 2026), which set out the translation approach and the
  parity requirements this repository follows;
- the **[TIMES.jl prototype](https://github.com/olejandro/times.jl)** by
  Olexandr Balyk (2024-2025), with review contributions from Oscar Dowson,
  which was the second experiment in the ETSAP community that showed a
  subset of TIMES functional equations running in JuMP from GAMS-exported
  data. The previous experiments were led by Antti Lehtilä and completed in
  2018. Olex's prototype provided a conceptual starting point for this
  translation; the code here is a new implementation against TIMES v4.9.7
  (v4.9.8 from 26 Nov 2026),
  starting from a blank skeleton, and components of the TIMES2JuMP prototype
  may be ported into it in future.

See [`AUTHORS.md`](AUTHORS.md) for the authors of TIMES itself.

## Licence

GPL-3.0-or-later, the same licence as the TIMES GAMS code. See
[`LICENSE`](LICENSE), [`NOTICE`](NOTICE) and [`AUTHORS.md`](AUTHORS.md).

**Intended move to the AGPL.** If IEA-ETSAP releases the TIMES code under the
GNU Affero General Public License version 3 (AGPL-3.0), TIMES.jl intends to
follow it and relicense to AGPL-3.0-or-later, so that the translation keeps
the licence of the code it is derived from. Until then TIMES.jl stays under
GPL-3.0-or-later. Contributions are accepted on terms that allow this move
(see [`CONTRIBUTING.md`](CONTRIBUTING.md#licensing-of-contributions)).
