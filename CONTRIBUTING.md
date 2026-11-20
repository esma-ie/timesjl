# Contributing to OpenTIMES.jl

## Phase 1 rules (faithful translation)

1. Translate only from TIMES v4.9.7, `etsap-TIMES/TIMES_model` @ `d9a6a25`.
2. Match GAMS results exactly. Do not reformulate, aggregate, substitute or
   tune for performance; that belongs to Phase 2.
3. Keep the GAMS names for sets, parameters, variables and equations
   (`EQ_COMBAL`, `VAR_ACT`, `COEF_CPT`, ...).
4. Cite the GAMS source in the docstring of every function or constraint
   block, in exactly this form:

   ```julia
   """
       eq_combal!(model, data)

   Commodity balance equations EQG_COMBAL / EQE_COMBAL.

   # GAMS: eqcombal.mod L45-112, v4.9.7
   """
   ```

5. Write `$`-conditions and domain controls as explicit sparse index sets.
   Never build dense Cartesian products.
6. Write each equation in the same algebraic form as in GAMS.
7. Copy GAMS defaults, implicit zeros, `EPS` handling and interpolation
   exactly, and document them in the docstring.
8. One GAMS file or one equation family per pull request.

## Every pull request

- Names the GAMS files and line ranges it translates.
- States how GAMS parity is checked, and on which test models.
- Adds unit tests plus a regression fixture.
- Logs timings against GAMS.
- Records any code/documentation disagreement in
  [`docs/discrepancies.md`](docs/discrepancies.md), and any justified
  difference from GAMS output in
  [`docs/known-differences.md`](docs/known-differences.md).
- Updates the map in [`docs/gams-julia-map.md`](docs/gams-julia-map.md).

Any parity mismatch blocks the merge.

## Behaviour that cannot be confirmed from the source

Do not guess. Flag it in the pull request and in `docs/discrepancies.md`
under "Unconfirmed behaviour" until a reference run settles it.

## Test models and fixtures

OpenTIMES.jl is developed and tested only on models with a clearly stated
open-source or open-data licence that allows redistribution and derivative
works ([`docs/test-models.md`](docs/test-models.md)). A model with no stated
licence, a non-commercial or no-derivatives licence, or a closed or
proprietary model is not used, not even to check something locally.

- Use only models listed in [`reference/suite.toml`](reference/suite.toml),
  which records each model's licence.
- Commit fixtures or references only from models with
  `redistribute = "public"`, and list them in
  [`test/fixtures/public_fixtures.toml`](test/fixtures/public_fixtures.toml).
- If you run OpenTIMES.jl on a proprietary model, keep everything from it out of
  issues and pull requests: no data, results, timings or error output that
  carries its data. Reproduce a problem on an open model instead.
- To propose a new test model, open an issue with a link to its licence
  first.

## AI-assisted contributions

This repository is itself an experiment in AI-assisted translation (see the
[README](README.md#an-experiment-in-ai-assisted-translation)), so
AI-assisted contributions are welcome, on the same terms as any other:

- Say in the pull request which parts were written with AI, and with which
  tool or model.
- You are responsible for the contribution as if you had written it
  yourself: you have read it, and you have the right to submit it.
- It passes the same parity checks. There is no exception for AI-written
  code, and no extra hurdle either.

## Licensing of contributions

OpenTIMES.jl is licensed under GPL-3.0-or-later. It intends to relicense to
AGPL-3.0-or-later if IEA-ETSAP releases the TIMES code under the AGPL (see
the [README](README.md#licence)). So that this move needs no further
permission from contributors, by submitting a contribution you agree that it
is licensed under both GPL-3.0-or-later and AGPL-3.0-or-later.
