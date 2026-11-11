# TIMES.jl — working rules for Claude

This repository ports the IEA-ETSAP TIMES model generator from GAMS to
Julia/JuMP. These rules apply in every Claude session (claude.ai Project,
Claude Code in the terminal, VS Code, or the desktop app).

## Baseline
- Translate only from TIMES v4.9.7, `etsap-TIMES/TIMES_model` @ `d9a6a25`
  (Antti Lehtilä's v4.9.7 commit; James's fork holds the same commit).
  Version (James, 11 Nov 2026): v4.9.7 until the M1.3 gate closes; then the
  whole baseline moves to v4.9.8 (`7064680`): the source download re-pinned,
  its diff translated, every GAMS reference rerun with it.
- Equation reference: `jamesglynn/TIMES_Documentation`, Part II.
- If the GAMS code and the documentation disagree, follow the GAMS code and
  log the discrepancy in `docs/discrepancies.md`.

## Phase 1 rules (faithful translation)
- Match GAMS results exactly. Do not reformulate, aggregate, substitute or
  tune for performance; that is Phase 2.
- Keep the GAMS names (`EQ_COMBAL`, `VAR_ACT`, `COEF_CPT`, ...).
- Cite the GAMS source in every docstring: `# GAMS: <file> L<start>-<end>, v4.9.7`.
- Write `$`-conditions as explicit sparse index sets. Never build dense
  Cartesian products.
- Copy GAMS defaults, implicit zeros and interpolation exactly, and document them.
- Translate one GAMS file or equation family per change (one PR each).

## How to work
- Before writing code, name the GAMS files and line ranges being translated.
- If you have not seen the relevant GAMS source, read it from the
  `TIMES_model` clone; never reconstruct it from memory.
- Flag any behaviour you cannot confirm from the source instead of guessing.
- For each change, say how GAMS parity will be checked.
- Milestone order, tolerances and definition of done: `docs/translation-guide.md`
  (M1.0 foundations → M1.1 model generation on GAMS dumps → M1.2 coefficients
  → M1.3 preprocessing → M1.4 DD reader → M1.5 run options → M1.6 reporting
  → M1.7 release). Do not start a milestone until the previous gate passes.
  One exception (James, 3 Nov 2026): M1.4 is developed alongside M1.3, in a
  second Claude tab working in its own git worktree (`../TIMESjl-m14`). It is
  checked against the `input/` dumps, which do not depend on M1.3. Its gate
  still waits for the M1.3 gate.
- Approved plans (James, 3 Nov 2026): the Phase 1 plan is approved, with
  M1.3 in the order of `docs/m13-plan.md`. Work through it without waiting
  for a plan approval per change, and stop only to depart from it. James
  reviews PRs at two check-ins, 9:00 and 16:30 (from 5 Nov 2026). Each PR starts with a
  "Decisions for you" list.
- Decision log (James, 11 Nov 2026): every question in a PR's "Decisions for
  you" list or at a check-in goes into `docs/decisions.md` with its outcome.
  A merge accepts a recommendation the PR already builds in. A question with
  no built-in default, or a choice the PR made for him, stays on the log's
  "Open decisions" list and is asked again at each 9:00 check-in until James
  answers; nothing that depends on it starts. Rule-level decisions (known
  differences, licences and test data, departures from these rules or the
  plan) need James's explicit yes; a merge never counts. Update the log in
  each PR, and record the outcome when it merges or James answers.

## Validation (every PR)
| Layer | Check | Tolerance |
| --- | --- | --- |
| Data | preprocessed sets/params vs GAMS dump | 1e-9 |
| Matrix | rows, columns, coefficients, RHS, bounds vs CONVERT DumpGDX | 1e-9 |
| Solution | objective; each optimum cross-evaluated in the other model | 1e-6 |
| Reporting | report parameters and `.vd` vs GAMS | 1e-6 |

Any mismatch blocks the merge. Justified differences go in
`docs/known-differences.md`.

## Reference runs
- `reference/README.md` describes the GAMS harness. Reference solver is CPLEX
  on a licensed GAMS; HiGHS is run on both sides for open-source parity and CI.
- The PyPI GAMS demo licence solves only models under 2,000 rows and columns;
  no suite model fits (TIMES_Demo demo12 has 8,695 rows with REDUCE off), so
  solves, CONVERT exports and all timings come from a licensed GAMS on one
  machine. Pre-solve dumps need no solve and work under the demo licence, and
  so do the M1.3 checkpoint dumps (`input/`, `init/`, `prep/`, `prelv/`,
  harness 0.3.0): `make_reference.py --only presolve` adds them, with `ppm/`
  and `coef/` where missing, to any reference (`run_references.ps1
  -Checkpoints` on James's workstation, which stays the reference of record).
- Full batch on Windows with GAMS and CPLEX: `scripts/run_references.ps1`
  (clones and pins every model repo, runs the suite, then the M1.0 gate).
  It runs the **core** tier by default: one baseline case per model, for fast
  development cycles (James, 30 Oct 2026). Policy and secondary scenarios and
  the very large models are in the **milestone** tier (`-Set milestone`),
  run at milestone gates or when a change reaches a feature only they have.
  `tier` is set per model in `reference/suite.toml`.
- Reference GAMS (James, 30 Oct 2026): every reference run is made with GAMS 54
  (54.6.1 on James's workstation), so solves, dumps and timings compare across
  the suite. `run_references.ps1` stops if the GAMS it finds is another major
  version (`-GamsMajor`, default 54), and `-Resume` redoes any run made with
  another version. References made with GAMS 52.1.0 are rerun.
- cuOpt lane (James, 10 Nov 2026; `scripts/cuopt/README.md`): informational
  layer 3 with NVIDIA cuOpt on the GPU, never a merge gate. Nightly on a
  GitHub T4 runner for the public fixtures (GPU-share sweep 25/50/100% with
  MPS), and in WSL2 on James's workstation for local runs (TIM allowed, results
  stay there). cuOpt's CPU side keeps the 12-thread limit; the GPU is not
  limited by it.
- Single model by hand, from the repo root: pass a `--root` for every
  placeholder that model uses (see `reference/suite.toml`), e.g.
  `python reference/python/make_reference.py --out ../timesjl-reference --solvers CPLEX,HIGHS --root times_source=../TIMES_model --root times_demo=../TIMES_Demo --model TIMES_Demo-demo12`
  (clone `etsap-TIMES/TIMES_model` and `etsap-TIMES/TIMES_Demo`)
  then `julia --project=. scripts/m10_gate.jl ../timesjl-reference/<model>/<variant>`.
- Local run limits on James's Windows workstation (James, 29 Oct 2026), for
  load management and comparable, fair resources across tests: every TIMES
  run (GAMS or TIMES.jl, any solver) uses at most 12 threads, and at most 4
  CPU-heavy runs run at the same time. `make_reference.py` enforces both
  (`--threads 12`: GAMS `threads=` and the `threads` line of solver option
  files; `--max-parallel 4`: shared slot files, `reference/python/runlimits.py`);
  the Julia scripts set HiGHS `threads` from `TIMESJL_THREADS` (default 12).
  Any other script started on that machine keeps to the same limits. Compare
  timings only between runs made under them.

## Test-model licences
- Translate, test, debug, profile and improve TIMES.jl only on models with a
  clearly stated open-source or open-data licence that allows redistribution
  and derivative works (OSI-approved, or Open Definition data licences such
  as CC0, CC BY, CC BY-SA). No licence stated, NC, ND, closed or proprietary:
  never used, not even locally or "just to check". Details and the current
  list: `docs/test-models.md`.
- Users may run TIMES.jl on proprietary models; the translation does not
  learn from them. Nothing derived from a closed model (data, results,
  timings, error reports carrying its data) enters this repository, its
  issues or its pull requests, and no design decision rests on one.
- `reference/suite.toml` records each model's `licence` (SPDX) and
  `redistribute`; `reference/python/test_suite.py` enforces it. CI fixtures
  come only from models with `redistribute = "public"`, listed in
  `test/fixtures/public_fixtures.toml`.
- Primary test models (27 Oct 2026): TIMES_Demo demo12 (CC BY 4.0; CI
  fixtures), TIM (exception, below) and OTUS9r (ESMA, from EPA's public-domain
  EPAUS9rT; `esma-ie/OTUS9r`, CC BY-SA 4.0, public from 30 Oct 2026).
  OTCGEN and OTNYC (ESMA, from EPA's public-domain Generative COMET and
  COMET-NYC; `esma-ie/OTCGEN`, `esma-ie/OTNYC`, CC BY-SA 4.0) joined the
  suite's core tier on 30 Oct 2026.
- One named exception: TIM (CC BY-NC-SA 4.0; public source, non-commercial
  licence), kept by James on 27 Oct 2026 for research use only, never for
  commercial work. Its source is an esma-ie fork of
  MaREI-EPMG/times-ireland-model with DD files James generates. It runs on
  James's machine only; nothing derived from it is committed, published or
  made a fixture.
- Never use anything from the `esma-cgep` GitHub organisation (an archived
  Columbia institution kept for transparency only), including
  `esma-cgep/tim-gams`: no models, DD files, licences or code.
- Removed and never to be re-added without a stated open licence: the DemoS
  models (removed 27 Oct 2026; DemoS_012 stays as TIMES_Demo demo12, CC BY
  4.0), TIMES-GEO, ETSAP-TIAM. PROTO is not a test model.
- Every suite model records `source_repo`, `licence_url` and
  `licence_checked`; ESMA model repositories keep GAMS-ready files in
  `dd/<scenario>/` with provenance in `dd/README.md`.
- If you have not seen a model's licence at its source, ask; do not assume.

## Repository
- Licence GPL-3.0-or-later (derivative of TIMES); keep the ETSAP notice and
  `AUTHORS.md` current. If IEA-ETSAP releases TIMES under the AGPL, TIMES.jl
  intends to relicense to AGPL-3.0-or-later; contributions are accepted under
  both licences (`CONTRIBUTING.md`).
- Repository `esma-ie/TIMESjl`, public from 30 Oct 2026, before the MVP, as
  an open experiment in AI-assisted translation (James, 27 and 30 Oct 2026).
  Its history starts with one commit holding the pre-publication work
  (17-30 Oct 2026), which was developed in private repositories
  (`esma-ie/TIMES.jl`, then `esma-ie/TIMESjl`, now `esma-ie/TIMESjl-private`)
  and is not published: it held material from models without an open
  licence. Keep the public repository so: no branch, commit, pull request,
  issue, release asset or tag may hold anything derived from a model without
  an open licence, and TIM material never enters it.
- Commit messages end with the session attribution lines Claude Code
  supplies. Keep them: the README points readers to the `Co-Authored-By`
  line to see which model wrote each commit.
