# TIMES.jl

A Julia/JuMP translation of the IEA-ETSAP TIMES model generator, validated
against the GAMS code for numerical parity.

> **Status: early experiment, pre-MVP (Phase 1, milestone M1.3; M1.0 to M1.2
> passed).** Not ready for modelling use. TIMES.jl still builds models from data exported by GAMS
> (it cannot read a TIMES model on its own until M1.4), it has no release, and
> its interfaces will change. For analysis, use TIMES in GAMS.
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

| Milestone | Scope |
| --- | --- |
| M1.0 | Repository, CI, GAMS reference harness, comparison tool |
| M1.1 | Variables, core + VDA equations, bounds, objective, built from GAMS-dumped data |
| M1.2 | Coefficients (`coefmain.mod`, `coef_*.mod`) |
| M1.3 | Preprocessing (`ppmain.mod`, `pp_*.mod`, VDA prep, REDUCE) |
| M1.4 | GAMS-free DD and `.run` reader |
| M1.5 | Run options (OBJ variants, MID_YEAR, DSCAUTO, VAR_UC, FIXBOH, ...) |
| M1.6 | Reporting and Veda `.vd` output |
| M1.7 | Phase 1 release and baseline benchmarks |

**Phase 2 — performance.** Faster preprocessing, generation and solver
hand-off, each change held to parity with GAMS.

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
  reference/    reading GAMS reference dumps (Arrow) and comparing them
reference/      GAMS harness that produces reference dumps from test models
scripts/        m10_gate.jl: checks one reference run (M1.0 gate)
test/           unit tests and parity tests
docs/           GAMS-to-Julia map, discrepancies, known differences
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
