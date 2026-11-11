# Test models

## The rule

TIMES.jl is translated, tested and improved only on models released under a
clearly stated open-source or open-data licence that allows redistribution
and derivative works: an OSI-approved software licence, or an
Open Definition-conformant data licence such as CC0, CC BY or CC BY-SA.
These do not qualify:

- a model with no stated licence (all rights reserved by default), even if
  its files are public;
- a non-commercial (NC) or no-derivatives (ND) licence;
- a closed-source or proprietary model.

Such a model is never used in this work: not for reference runs, fixtures,
crafted test cases, timings, profiling, debugging, or as evidence for a
design decision.

Users may later run TIMES.jl on proprietary models. That is their choice and
their data. The translation and its improvement do not learn from those
models: nothing derived from a closed model (data, results, timings, error
reports that carry its data) comes back into this repository, its issues or
its pull requests.

`reference/suite.toml` records each model's `licence` (SPDX id) and what
derived from it may be published (`redistribute`):

- `public`: references and fixtures;
- `summary`: only the summary results the tests and comparisons need (model
  size, solve status, objective values, timings, gate verdicts and
  differences: the rows of `summary.csv`). References, dumps and fixtures stay
  on James's machine and are not committed or packed for release;
- `private`: nothing (the TIM exception).

`reference/python/test_suite.py` fails on any model without an open licence,
unless its entry names an `exception`.

### The one exception: TIM

TIM (`MaREI-EPMG/times-ireland-model`, MaREI, UCC) is CC BY-NC-SA 4.0. Its
source is public, but the non-commercial clause is not an open-source
licence. James kept it as a named exception on 27 Oct 2026, with these
conditions:

- research use only, never commercial work;
- its source is an esma-ie fork of MaREI's repository, with DD files James
  generates from it, carrying MaREI's licence and attribution. Nothing from
  the archived `esma-cgep` organisation is used (including its
  `tim-gams`);
- it runs only on James's machine (`redistribute = "private"`);
- nothing derived from it (references, fixtures, crafted cases) is committed
  to this repository or published as a release asset;
- it never becomes a CI fixture.

## Models in the suite

| Model | Licence | Owner | Use |
| --- | --- | --- | --- |
| TIMES_Demo demo12 (`etsap-TIMES/TIMES_Demo` @ 962db86) | CC-BY-4.0 (data), GPL-3.0 (code) | IEA-ETSAP | references and public fixtures |
| TIMES-NZ 3.0.8, cases steady-v308 and shift-v308 (`EECA-NZ/TIMES-NZ-Model-Files` main 8165e1d through the esma-ie fork; DD export of 28 Oct 2026 in `timesjl-sources/TIMES-NZ/dd/`) | MIT | EECA | references and public fixtures (from M1.2, 29 Oct 2026) |
| OTUS9r, cases reference and tax1_wo_mou (`esma-ie/OTUS9r` @ `598e179`, public from 30 Oct 2026; the DD export of 28 Oct 2026 in its `dd/`) | CC-BY-SA-4.0 (ESMA), over US EPA EPAUS9rT_v20.4 (US public domain) | ESMA | references and public fixtures (from M1.2, 29 Oct 2026) |
| OTCGEN, case gc_ref (`esma-ie/OTCGEN` @ `08af95f`, public from 30 Oct 2026; the DD export of 30 Oct 2026 in its `dd/`) | CC-BY-SA-4.0 (ESMA), over US EPA Generative COMET v0.0.0 (US public domain) | ESMA | references and public fixtures (from M1.2, 30 Oct 2026) |
| OTNYC, case s1_nyc_ref (`esma-ie/OTNYC` @ `bc1d276`, public from 30 Oct 2026; the DD export of 30 Oct 2026 in its `dd/`) | CC-BY-SA-4.0 (ESMA), over US EPA COMET-NYC v16.0.1 (US public domain) | ESMA | references and public fixtures (from M1.2, 30 Oct 2026) |
| TIM, cases bau, mitigation_cb2024-300mt and its myopic variant (`esma-ie/times-ireland-model-marei`; James's DD export of 28 Oct 2026 in `timesjl-sources/TIM/dd/`) | CC-BY-NC-SA-4.0 | MaREI, UCC | the named exception: James's machine only, nothing derived committed |
| JRC-EU-TIMES, PSI WIMBY version, scenario cli_ll and, from 11 Nov 2026, the other eight WIMBY scenarios cli_hh to cli_mm (`gitea.psi.ch/WIMBY/JRC-EU-TIMES` @ c18a076; DD and run files extracted from its dumps into `timesjl-sources/JRC-EU-TIMES`) | GPL-3.0-or-later (WIMBY), over JRC-EU-TIMES data (CC-BY-4.0) | WIMBY project (PSI); data JRC | large-model reference, summary results only (James, 29 Oct 2026) |

TIM is in the suite from 29 Oct 2026 as the exception above, from James's DD
export of the esma-ie fork (local source `tim`, never committed).

### Model repositories maintained by ESMA

ESMA's forks and models (TIMES-NZ, TIM, OTUS9r, OTCGEN, OTNYC, DEVTAI) use one layout so
the harness can treat them alike:

```
dd/
  README.md            provenance: source commit of the Veda workbooks,
                       Veda version, TIMES version targeted, date, generator,
                       and any hand edits (ideally none)
  <scenario>/          one folder per scenario, lower case, no version in
    <scenario>.run     the name (versions live in git tags and the README)
    *.dd
```

The repository root keeps the upstream LICENSE (and a NOTICE crediting the
original authors); GDX, LST and VD outputs are not committed.

### Tiers

Each suite case has a `tier` (`reference/suite.toml`; James, 30 Oct 2026).
The core tier is one baseline case per model (TIMES_Demo demo12,
TIMES-NZ-steady-v308, OTCGEN-gc_ref, OTNYC-s1_nyc_ref, OTUS9r-reference,
TIM-bau), rerun in every development cycle. The milestone tier (TIMES-NZ-shift-v308, OTUS9r-tax1_wo_mou, the TIM
carbon-budget cases, JRC-EU-TIMES-cli_ll) runs at milestone gates, or when a
change reaches a feature only those cases have. OTUS9r-tax1_wo_mou is paused
there: its REDUCE-on CPLEX solve did not leave crossover in 9 h, and its
REDUCE-off optimum has unscaled infeasibilities. It stays paused, and
JRC-EU-TIMES-cli_ll is deferred, until later Phase 1 milestones (James, 31 Oct
2026); neither ran for the M1.2 gate. JRC-EU-TIMES-cli_ll's checkpoints run
nightly from 5 Nov 2026, and its two untranslated features, currency
conversion and the power-flow grid, are M1.3 changes 26 and 27 (James,
7 Nov 2026).

### Primary test models

From 27 Oct 2026 the primary test models are TIMES_Demo demo12, TIM and
OTUS9r:

- **demo12**: the CI fixtures (layers 1-3), small enough for every pull
  request.
- **TIM**: James's machine only (the exception above); its results are not
  committed.
- **OTUS9r** (Open TIMES US 9R, ESMA): published on 30 Oct 2026 as
  `esma-ie/OTUS9r` (CC BY-SA 4.0). It is redeveloped from the US EPA's
  EPAUS9rT v20.4 (EPA ORD, data.gov, DOI 10.23719/1528539): the EPA original
  is committed unchanged at tag `epaus9rt-v20.4` (archive SHA-256 in the
  commit message and the release), and `dd/` holds the Veda DD export of the
  two suite cases. The data.gov record gives the EPA ScienceHub licence (US
  public domain unless otherwise specified), access level public, and states
  no restriction (checked 30 Oct 2026); OTUS9r's README credits EPAUS9rT. At
  nine regions it is a local reference; a reduced CI variant made from the
  same open data can be a fixture.

In the suite from 30 Oct 2026, beside the primary models:

- **OTCGEN** and **OTNYC** (ESMA): published on 30 Oct 2026 as
  `esma-ie/OTCGEN` and `esma-ie/OTNYC` (CC BY-SA 4.0), in the same way as
  OTUS9r. They are redeveloped from the US EPA's Generative COMET v0.0.0
  (DOI 10.23719/1532263; the EPA release is populated for New York City) and
  COMET-NYC v16.0.1 (DOI 10.23719/1532264), both published by EPA ORD on
  data.gov under the EPA ScienceHub licence (US public domain unless
  otherwise specified; checked 30 Oct 2026). The EPA originals are committed
  unchanged at tags `gcomet-v0.0.0` and `comet-nyc-v16.0.1`, with the EPA
  archives attached to the releases; `dd/` holds the reference case of each
  (GC_REF, S1_NYC_REF), exported on 30 Oct 2026 from workbooks checked
  against the tags. Both are small (2 and 7 regions) and set no MID_YEAR,
  OBLONG or VARCOST switch, the second objective configuration on real
  models; OTNYC is the only open model whose data reach TIMES's FLO_SHARE
  auto-relax step (`pp_qafs.mod`). Their policy cases were exported and
  checked on 30 Oct 2026 and can join the milestone tier later.

Candidates, not yet in the suite: OTAI (CC-BY-SA-4.0, ESMA; no TIM data,
James 27 Oct 2026), DEVTAI (ESMA's two-region power model; needs a LICENSE),
and JRC-EU-TIMES v1.1.1 (CC-BY-4.0). OTAI and JRC-EU-TIMES v1.1.1 are Veda
Excel only, so they join at M1.4 through xl2times unless DD files are added.

JRC-EU-TIMES in the suite is PSI's WIMBY version. PSI's repository holds only
GAMS `DUMPOPT=11` dumps of nine scenarios (TIMES v4.8.3). The DD files were
cut unchanged out of the dumps and the run files rebuilt from them, in the
`dd/<scenario>/` layout below, with provenance in `dd/README.md`; the nine
scenarios reproduce PSI's objective values within 5.1e-8 (28-29 Oct 2026).
All nine are the same size; cli_ll, the closest to PSI (4.8e-9), is the
suite's test case. The folder is not a
git repository: `scripts/run_references.ps1` checks the SHA-256 of its
`dd/manifest.json` and skips the model if the folder is missing. Its
`NOTICE` credits the WIMBY project and the JRC. Still to ask PSI: which JRC
release the data derive from, and the original run files.

## Removed models

- **DemoS** (27 Oct 2026). The VEDA-TIMES step-by-step demo models
  DemoS_001 to DemoS_012 (and Model_Demo_Adv_Veda) are listed as an IEA-ETSAP
  project by E4SMA and KanORS-EMR, and are distributed through an ETSAP
  download form and the Veda installer. None of these sources states a
  licence. The copy used here, `olejandro/demos-dd`, has none either.
  Their end state, DemoS_012, is the model IEA-ETSAP publishes as TIMES_Demo
  demo12 under CC BY 4.0: its `base.dd` sets `RUN_NAME 'DemoS_012'`, and
  98-100% of the records in the four largest DD files are identical to
  DemoS_012's (compared 27 Oct 2026). demo12 therefore stays in
  the suite; the earlier steps, which have no licence, are gone.
- **TIMES-GEO** (22 Oct 2026): no licence file.
- **Olexandr Balyk's PROTO** (22 Oct 2026): AGPL-3.0. It was removed as a
  test model, not for its licence.
- **ETSAP-TIAM**: never used (not open source).

On 27 Oct 2026 the work moved to a new private repository with a filtered
history: the DemoS fixtures, the crafted DemoS cases and the crafted states
built on DemoS dumps were removed from every commit, and no release assets
or tags were carried over. On 30 Oct 2026 it was published as
`esma-ie/TIMESjl` with a fresh history (one first commit), because the
private history and pull requests still held text and figures from models
without an open licence. The private repositories are kept, unpublished.

## What CI checks now

Without DemoS, CI runs:

- the reference tooling on synthetic data: the dump reader, layer-1
  comparison and the canonical LP (`test/fixtures/tiny_dump`);
- the model-free unit tests: GAMS EPS arithmetic, the run switches, GAMS
  assignment semantics and the variable store;
- the harness tests (Python), including the licence check on
  `reference/suite.toml`;
- `test/unit/test_public_parity.jl`: layers 1-3 for every fixture in
  `test/fixtures/public_fixtures.toml`.

The first fixture is `demo12_off`: TIMES_Demo demo12, reduce_off, made on
28 Oct 2026 from the licensed reference run of 21 Oct (GAMS 52.1.0 + CPLEX;
GAMS/HiGHS failed under that licence, so the solution file holds the CPLEX
optimum only). It checks layer 2 (8,695 rows, 9,669 columns, 31,391
nonzeros), layer 3 and layer 1 of the coefficient files translated so far,
so **CI again checks every translated equation family and coefficient file
against GAMS on an openly licensed model**. The fixture's licence is CC BY
4.0 with attribution to IEA-ETSAP (`test/fixtures/public_fixtures.toml`).

From 10 Nov 2026 (M1.4 change 2c) CI also compiles demo12 from its own run and DD
files, with no GAMS (`test/unit/test_ddsource.jl`). The DD files come from the pinned
download of `etsap-TIMES/TIMES_Demo` @ 962db86 (`Artifacts.toml`); the run file is the
harness's patched copy (`test/fixtures/demo12_off_run`, CC BY 4.0, IEA-ETSAP). The result
is checked against the `demo12_off_input` dump.
From change 6 (10 Nov 2026) the same test covers the 11 demo12 variants that have an input
fixture: their own DD files are in `reference/dd/` (CC BY 4.0, as demo12) and their patched run
files in `test/fixtures/<prefix>_run`.

Coverage the removed tests gave, and where it has to come from now:

| Removed test | What it checked | Open-model replacement |
| --- | --- | --- |
| `test_eq_actflo`, `_capact`, `_ptrans`, `_cumflo`, `_combal`, `_obj`, `test_bounds`, `test_generate` | core families, objective, bounds, generation driver and its refusals | demo12 fixture (whole model); refusal tests to rewrite on demo12 |
| `test_canonical_dump` | CONVERT reader on a real export | any public fixture (layer 2) |
| `test_eq_peak`, `_ire`, `_uc`, `_cpt`, `_floshr`, `_acteff`, `_actbnd` | trade, peak, user-constraint, capacity-transfer, flow-share, efficiency and activity-bound families, with a crafted ACTBND case | demo12 reaches most of them (`scripts/m11_probe.jl` lists which); crafted cases on demo12 for the rest |
| `test_eq_ucdyn` | dynamic user constraints (GROWTH) | none yet: demo12 has no dynamic UCs; a crafted case on demo12 (CC BY permits derivatives with attribution) |
| `test_eq_stg`, `_caflac`, `_ucrs`, `_ashar`, `_cum` | storage, VDA availabilities, timeslice and cumulative UCs, on crafted cases | TIM checks them locally; for CI, crafted cases on demo12 or TIMES-NZ |
| `test_coef_cpt`, `_nio`, `_ptr`, `coef_ptr_case`, `scripts/make_coef_ptr_unit.jl` | M1.2 layer 1, an OBLONG NO variant and a crafted FLO_FUNC state run through GAMS | a demo12 ppm/coef fixture with `coef_symbols`; the OBLONG NO and FLO_FUNC cases rebuilt on demo12 |
| `test_mod_vars` (fixture part), `test_coef_state` (gput!, layer1) | variable metadata; computed-symbol mechanics | a demo12 metadata fixture; tests on demo12's dumps |

The M1.2 coefficient tests (coef_obj, coef_alt, coef_shp, coef_ext) were
rebuilt on demo12 on 28-29 Oct 2026 (`test/unit/test_public_parity.jl` and the
`*_unit_gams` fixtures).

## Adding a test model

1. Check the licence at its source, and record the URL and the date checked.
   It must be an open licence as defined above.
2. Add a `[[model]]` entry to `reference/suite.toml` with `licence` (SPDX
   id) and `redistribute = "public"` (or `"summary"` if only summary results
   may be published), and pin its repository and commit in
   the header table, in `reference/README.md` and in
   `scripts/run_references.ps1`.
3. Make the reference run with a licensed GAMS (`reference/README.md`).
4. Copy it into `test/fixtures`:
   `julia --project=test scripts/make_m11_fixture.jl <reference>/<model>/<variant> <prefix>`
   (and `make_m12_fixture.jl` for the coefficient dumps), and add an entry to
   `test/fixtures/public_fixtures.toml`. Keep CI fixtures small: a model above
   a few tens of MB of fixtures stays a local reference.
5. Credit the model's authors as its licence requires (CC BY needs
   attribution), in the fixture's entry and in `AUTHORS.md`.
