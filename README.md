# TIMES.jl

A Julia/JuMP translation of the IEA-ETSAP TIMES model generator, validated
against the GAMS code for numerical parity.

> **Status: early experiment, pre-MVP (Phase 1; M1.0 to M1.2 passed; M1.3,
> M1.4 and M1.5 under way).** Not ready for modelling use. TIMES.jl can now
> read a TIMES model from its own `.run` and DD files, preprocess it, build it
> and solve it without GAMS, but several TIMES features are not translated
> yet, it has no release, and its interfaces will change. For analysis, use
> TIMES in GAMS. See [Progress](#progress).
>
> TIMES.jl is an independent project of ESMA Ltd. It is not an official
> IEA-ETSAP product and is not endorsed by IEA-ETSAP or the TIMES maintainers.

## An experiment in AI-assisted translation

TIMES.jl is also an experiment: how useful is AI at translating a large,
mature GAMS code base such as TIMES into open-source languages and tool
stacks, when every step must reproduce the original's results?

- **Who writes the code.** Almost all of the code, tests and documentation
  here are written by AI models (Anthropic's Claude), working from the TIMES
  v4.9.7 GAMS source under the rules in [`CONTRIBUTING.md`](CONTRIBUTING.md)
  and [`CLAUDE.md`](CLAUDE.md). Commits authored by `Claude` are AI-written,
  and the model used is named in each commit's `Co-Authored-By` line. A human
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
| TIMES GAMS source | v4.9.7, [etsap-TIMES/TIMES_model](https://github.com/etsap-TIMES/TIMES_model) @ `d9a6a25` |
| Equation reference | TIMES Documentation, Part II |
| Julia | 1.10 or later (developed on 1.13) |

The GAMS code is authoritative. Where it disagrees with the documentation the
difference is logged in [`docs/discrepancies.md`](docs/discrepancies.md).

To read a model's `.run` and `.dd` files, TIMES.jl compiles TIMES's own files as GAMS
does, so it needs the v4.9.7 source. It downloads that commit's GitHub archive on
first use and checks it by hash ([`Artifacts.toml`](Artifacts.toml),
`TIMES.times_source()`). To use a local clone of the same commit instead, set
`TIMESJL_TIMES_SOURCE`. The open demo models (`etsap-TIMES/TIMES_Demo` @ 962db86,
CC BY 4.0, IEA-ETSAP) come the same way (`TIMES.times_demo_dir()`).

## Phases

**Phase 1 — faithful translation.** Same sets, parameters, variables,
equations and coefficients as GAMS, with GAMS names kept. Ported from the
equations outwards:

| Milestone | Scope | Status (15 Nov 2026) |
| --- | --- | --- |
| M1.0 | Repository, CI, GAMS reference harness, comparison tool | passed 18 Oct |
| M1.1 | Variables, core + VDA equations, bounds, objective, built from GAMS-dumped data | passed 21 Oct |
| M1.2 | Coefficients (`coefmain.mod`, `coef_*.mod`) | passed 31 Oct |
| M1.3 | Preprocessing (`ppmain.mod`, `pp_*.mod`, VDA prep, REDUCE) | translated and matching GAMS on the open test models; the gate waits until the TIMES features still refused are translated |
| M1.4 | GAMS-free DD and `.run` reader | built and matching GAMS; the gate follows M1.3's |
| M1.5 | Run options (OBJ variants, MID_YEAR, DSCAUTO, VAR_UC, FIXBOH, ...) | started 14 Nov: stepped (myopic) runs in review |
| M1.6 | Reporting and Veda `.vd` output | not started |
| M1.7 | Phase 1 release and baseline benchmarks | not started |

**Phase 2 — performance.** Faster preprocessing, generation and solver
hand-off, each change held to parity with GAMS.

## Progress

As of 15 Nov 2026 (`main`):

- **Runs without GAMS.** [`scripts/run_dd.jl`](scripts/run_dd.jl) takes a
  model's `.run` file and DD files, compiles them as GAMS's compile phase
  does, runs TIMES's preprocessing and coefficients, builds the model and,
  with `--solve`, solves it with HiGHS.
- **Open test models.** Seven runs of five open models (TIMES_Demo demo12;
  TIMES-NZ steady and shift; OTCGEN; OTNYC; OTUS9r reference and tax1)
  match GAMS, with REDUCE off and as run, in the workstation batch of
  14 Nov 2026:
  - every preprocessing step against GAMS's dump before and after it (490 of
    490 steps);
  - the whole chain from the raw input to the point where GAMS builds the
    model (14 of 14 runs);
  - the matrix and the objective (281 of 281 checks). The largest model is
    OTUS9r: 2.2 million rows, 2.8 million columns and 9.9 million nonzeros
    with REDUCE off.
- **CI.** Every pull request checks 35 runs: demo12 and crafted variants of
  it that add features demo12 itself does not use (992 checks, all pass).
- **Features.** The core and VDA formulations are translated. Changes 28
  to 40 of the M1.3 plan (merged 14 Nov) added features that had been
  refused, each checked on a crafted demo12 case: trade and storage in
  ASHAR, ANNCOST LEV, the data of stepped (myopic) runs, exchange bounds
  (IREBND, XBND), commodity and flow bounds as equations (BNDNET, BNDPRD,
  FLOBND, FLOFR), linear dispatching, unit commitment by start-up type,
  refinery blending, simulated vintages (CAPVAC) and bounds on costs
  (BNDCST).
- **Not translated yet.** These features stop generation with an error
  that names the GAMS file: MACRO; the extensions (stochastic, ETL,
  climate, ABS, ECB, IER); elastic demand; damage costs; dynamic timeslices
  (TS_OFF); PTDF and gas grids; market-based trade; discrete unit commitment
  (a MIP); and a few smaller ones ([`docs/m13-plan.md`](docs/m13-plan.md)).
- **Discrepancies.** 40 places where the GAMS code and the documentation
  disagree are logged in [`docs/discrepancies.md`](docs/discrepancies.md).
  Three known differences between TIMES.jl
  and GAMS are listed in [`docs/known-differences.md`](docs/known-differences.md).
- **Dashboard.** [`docs/dashboard/index.html`](docs/dashboard/index.html),
  opened in a browser, shows these results in slides
  ([`docs/dashboard/README.md`](docs/dashboard/README.md)).

Speed is not a Phase 1 aim; timings are recorded and compared with GAMS for
Phase 2.

## Validation

Every change is checked against reference runs of the GAMS code:

| Layer | Check | Tolerance |
| --- | --- | --- |
| Data | Preprocessed sets and parameters vs GAMS dump | 1e-9 |
| Matrix | Rows, columns, coefficients, RHS, bounds vs CONVERT dump | 1e-9 |
| Solution | Objective; each optimum checked in the other model | 1e-6 |
| Reporting | Report parameters vs GAMS outputs | 1e-6 |

Reference runs are produced with the harness in [`reference/`](reference/),
and only from test models with a clearly stated open-source or open-data
licence ([`docs/test-models.md`](docs/test-models.md)). TIMES.jl does not
learn from closed or proprietary models.

## Repository layout

```
src/            TIMES module (one Julia file per GAMS file, same stems)
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
  translation; the code here is a new implementation against TIMES v4.9.7,
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
