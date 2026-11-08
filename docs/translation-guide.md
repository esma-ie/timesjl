# TIMES.jl Translation Guide (GAMS → Julia/JuMP)

## Purpose
Port the TIMES model generator from GAMS to Julia/JuMP with exact numerical
parity. Phase 1 is a faithful translation: no reformulation and no
optimisation. Performance work happens in Phase 2.

## Source of truth
- Baseline: TIMES v4.9.7, etsap-TIMES/TIMES_model @ d9a6a25. Pin this commit
  and never translate from any other version.
- Equation reference: jamesglynn/TIMES_Documentation, Part II.
- If the GAMS code and the documentation disagree, the GAMS code is
  authoritative. Log every discrepancy in `docs/discrepancies.md`.

## Porting order (equations outwards)
1. M1.0 Foundations: repo, CI, GAMS reference harness (DEBUG dump,
   post-coef dump, pre-solve dump, CONVERT DumpGDX, solution, timings),
   comparison tool.
2. M1.1 Model generation: variables, core + VDA equations, bounds and
   objective, built from GAMS-dumped data.
3. M1.2 Coefficients (coefmain, coef_*).
4. M1.3 Preprocessing (ppmain, pp_*, VDA prep, REDUCE).
5. M1.4 GAMS-free DD/.run reader.
6. M1.5 Run options (OBJ variants, MID_YEAR, DSCAUTO, VAR_UC, FIXBOH, ...).
7. M1.6 Reporting + Veda .vd output.
8. M1.7 Phase 1 release + baseline benchmarks.
Do not start a milestone until the previous one passes its parity gate.

## Translation rules
- Keep the GAMS names for sets, parameters, variables and equations
  (e.g. `EQ_COMBAL`, `VAR_ACT`, `COEF_CPT`) so each piece can be traced
  back to the GAMS code.
- Every Julia function or constraint block cites its GAMS file and line
  range in a docstring, e.g. `# GAMS: eqcombal.mod L45-112, v4.9.7`.
- Translate one GAMS file or equation family at a time. Make a separate PR
  for each.
- Write `$`-conditions and domain controls as explicit sparse index sets.
  Never build dense Cartesian products.
- Write each equation in the same algebraic form as in GAMS. No
  substitutions, aggregations or "equivalent" rewrites in Phase 1.
- Copy any GAMS defaults, implicit zeros or interpolation behaviour
  exactly, and document them.
- Leave the Phase 2 work (direct mode, triplets, threading, names off)
  until Phase 2.

## Validation (every PR)
| Layer      | Check                                                   | Tolerance |
|------------|---------------------------------------------------------|-----------|
| Data       | Preprocessed sets/params vs GAMS dump                   | 1e-9      |
| Matrix     | Rows, columns, coefficients, RHS, bounds vs DumpGDX     | 1e-9      |
| Solution   | Objective; check each optimum in the other model        | 1e-6      |
| Reporting  | Report parameters vs GAMS outputs                       | 1e-6      |

Test models: only models with a clearly stated open-source or open-data
licence (docs/test-models.md). TIMES_Demo demo12 (CC BY 4.0;
etsap-TIMES/TIMES_Demo @ 962db86; no discrete-capacity data, so not
DSC-dependent; joins at M1.1), TIMES-NZ (MIT; M1.4), OTAI (CC BY-SA 4.0,
Veda Excel only, via xl2times at M1.4). TIM (CC BY-NC-SA 4.0) is a named
exception: local references only, never committed. The DemoS models were
removed on 27 Oct 2026 (no stated licence). `reference/suite.toml` lists
each model's licence and the milestone at which it joins.
Any mismatch blocks the merge. Record known, justified differences in
`docs/known-differences.md`.

## Definition of done (per component)
- Matches GAMS on all test models at the tolerances above
- GAMS source referenced in docstrings
- Unit tests plus a regression fixture
- Timings logged against GAMS
- Discrepancies recorded

## Decisions (confirmed 17 Oct 2026)
- "No reformulation" = same mathematics as GAMS; sparse data structures
  allowed from day one. Confirmed.
- Extension scope: core + VDA in Phase 1; DSC next; MACRO, stochastic,
  ETL, climate, damage after M1.7. Default unless changed.
- Reference solver: CPLEX via James's GAMS licence for reference runs;
  HiGHS on both sides for open-source parity and CI; Gurobi trial
  possible later for benchmarks. Confirmed.
- Repo: esma-ie/TIMESjl (from 27 Oct 2026; the earlier esma-ie/TIMES.jl is
  archived, private). Licence GPL-3.0-or-later, same as TIMES_model; to go
  public before the MVP as an open experiment in AI-assisted translation.
  Olexandr Balyk and ETSAP members consulted. Confirmed.
- Veda .vd output: in Phase 1 (M1.6). Default unless changed.
- Phase 1 performance target (confirmed 18 Oct 2026): model generation
  (preprocessing to solver hand-off) no worse than 5x GAMS, warm, at M1.7.
  Correctness comes first; speed is Phase 2's job.

## Status
Entries up to 22 Oct 2026 summarise the pre-publication work. Until 27 Oct
2026 the translation was also checked on models without an open licence;
those checks, their figures and their crafted cases are not published
(docs/test-models.md). The evidence on open models is in the entries from
27 Oct 2026 on and in docs/gams-julia-map.md.

- 18 Oct 2026: M1.0 gate PASS with the PyPI GAMS 54.6.0 demo system (HiGHS
  and demo CPLEX); U1-U4 settled (docs/discrepancies.md). Licensed-GAMS
  references for larger models still to be produced on James's machine.
- 18 Oct 2026: TIMES_Demo demo12 added to the suite. The harness hooks work on
  it under v4.9.7 (ppm and coef dumps written), but the model is 8,695 rows x
  9,669 columns with REDUCE off and 3,233 x 4,485 with REDUCE on, above the
  2,000-row demo limit, so its references need licensed GAMS.
  `scripts/run_references.ps1` runs the whole suite on Windows.
- 20 Oct 2026: M1.1 input switched from the coef dump to a pre-solve dump
  (harness run with SOLVE_NOW=NO). pp_qack.mod runs after eqmain and before
  the solve and changes sets the equations read (RTP_VNTBYR, PRC_CG, AFS);
  the pre-solve dump is the state the SOLVE statement generates from. It
  needs no solve, so it can be produced under the demo licence for every
  model.
- 20 Oct 2026: first whole-model parity: a model generated entirely by
  TIMES.jl from the pre-solve dump (EQ_ACTFLO, EQ_CAPACT, EQ_PTRANS,
  EQ_CUMFLO, EQ_COMBAL, the objective rows, bounds) is identical to the
  CONVERT export (layer 2), and the TIMES.jl HiGHS optimum equals the GAMS
  HiGHS and CPLEX objectives, each optimum feasible and optimal in the other
  model (layer 3). Next: a generation driver that refuses data for
  untranslated equation families; `scripts/m11_probe.jl` lists, per model,
  the families still missing and checks layers 2 and 3 where none are.
- 20-21 Oct 2026: the M1.1 equation families, one GAMS file per change:
  EQ_PEAK; EQ_IRE (bilateral trade) and the non-dynamic user constraints
  (EQE_UCT/UCRT/UCTS/UCRTS with VAR_UC YES, their bounds from bnd_ucw.mod);
  EQ(l)_CPT, EQ(l)_INSHR/OUTSHR and EQE_ACTEFF (VDA); EQ(l)_ACTBND; the
  dynamic user constraints (EQE_UCSU/UCRSU/UCRSUS/UCSUS, LHS direction,
  GROWTH attribute); EQ(l)_ASHAR (standard processes); EQE/EQL_CAFLAC and
  EQL_CAPFLO (VDA commodity availabilities, with the AFS removal of
  equ_ext.vda L79, `afs_solve`, used by EQ_CAPACT too; GAMS gives x/INF = 0,
  G17); EQE_UCRS (timeslice-level user constraints, UC_DS, with the
  eqmain.mod L224 map; UC_TIME cancels in two-sided constraints, D24);
  storage (EQ_STGTSS and EQ_STSBAL, EQ_STGAUX, EQ(l)_STGIN/STGOUT,
  cal_stgn.mod in EQ_COMBAL and EQ_PEAK, the EQ_CAPACT storage term, storage
  flow costs in EQ_OBJVAR, the storage terms of EQ(l)_CAFLAC and
  EQL_CAPFLO, bnd_stg.mod; D25-D30, G18-G20); carbon budgets (EQ_CUMNET/
  EQ_CUMPRD, the COM_CUM part of bnd_cum.mod, and the multi-period user
  constraints EQE_UC/EQE_UCR, equcwrap.mod L22/L24, %8 = 2: FPD-weighted
  period sums, UC_CUMFLO and UC_CUMCOM terms). Rows with no variable left,
  after combining terms, are not generated, as in GAMS (G22). Still refused:
  storage flexibility (%STSFLX%: EQ_STSLEV and the VAR_UDP/VAR_STS terms),
  inter-period storage (EQ_STGIPS, STK) and EQ(l)_ASHAR of storage
  processes. Families that only occur above the demo licence's size limit
  were checked on crafted cases at the time; on open models, demo12 reaches
  most of them and the rest wait for crafted cases on demo12 or TIMES-NZ
  (docs/gams-julia-map.md, "no open-model check yet").
- 21 Oct 2026: first licensed references, from James's machine (GAMS 52.1.0
  with CPLEX, harness 0.2.1, both variants). TIMES_Demo-demo12 passes layers
  2 and 3 (reduce_off: objective and cross-evaluation against CPLEX). The
  licence has no GAMS/HiGHS, so above the 2,000-row demo limit the GAMS
  HiGHS solve stops with return code 3 and summary.csv shows CHECK; for
  those models HiGHS parity is the TIMES.jl HiGHS optimum against GAMS
  CPLEX. The CPLEX optimum of a reference run can miss its own GAMS LP at a
  row by more than 1e-6 (known-differences K1).
- 21 Oct 2026: **M1.1 gate PASS** (James). Layers 2 and 3 pass (reduce_off)
  on every model of the M1.1 set at the time; on open models that is
  TIMES_Demo demo12. K1 approved for Phase 1, with tighter tolerances for
  Phase 2 (docs/phase2-notes.md, P2-1); timings in docs/timings.md. REDUCE
  YES (the as_run variants) stays with M1.3. M1.2 starts.
- 21 Oct 2026: M1.2 (0) and (1). `src/coef/state.jl`: computed GAMS sets and
  parameters replace the dump's (`gput!`, `gassign!`), and `layer1` checks
  them against a dump; `scripts/m12_probe.jl` runs the translated steps on
  each reference run's ppm dump against its coef dump. coefmain.mod L11 and
  coef_cpt.mod L13-63 (with pp_shapr.mod's base assignment). With OBLONG YES
  or OBJ MOD `%CTST%` is `**0` and coef_cpt.mod computes no COEF_CPT (G23);
  L19-21 need an OBLONG NO run (harness 0.2.3 model overrides). COEF_CPT at
  the PYR_S vintages of PRC_RESID processes is overwritten later by
  coef_ext.vda L19-23. Shaped availability (NCAP_AFM/AFX/AFSM/AFSX),
  VALIDATE and STAGES are refused.
- 21 Oct 2026: M1.2 (2): coef_nio.mod for models without capacity-related
  commodity flows (NCAP_ICOM, NCAP_OCOM, RCAP_OCAP, NCAP_COM and NCAP_CLED
  are refused, as cal_cap.mod is in M1.1). The dump reader now reads a zero
  scalar as absent: GDX writes `Scalar CNT / 0 /` (unlike any indexed zero),
  which read as EPS before.
- 21 Oct 2026: M1.2 (3): coef_ptr.mod L9-54, with the FLO_FUNC paths checked
  on a crafted state run through coef_ptr.mod by GAMS (docs/m12-plan.md,
  finding 3; that state has since been removed and is to be rebuilt on
  demo12). The reduced-flow conversion (L38-40, L42) is refused until REDUCE
  (M1.3). `OPTION` projection semantics confirmed (discrepancies G26-G28).
- 21 Oct 2026: M1.1 timings on one machine (James's workstation, Julia
  1.13.2 against GAMS 52.1.0; docs/timings.md): TIMES.jl generation is 6.8x
  GAMS equations + hand-over on demo12.
- 21 Oct 2026: M1.2 (4): coef_obj.mod with filparam.gms and fillcost.gms,
  with a crafted state replayed through coef_obj.mod by GAMS
  (scripts/gams_replay.jl). Refused: ANNCOST LEV, VALIDATE, elastic demand
  shapes, blending, investment costs outside RDCUR.
- 22 Oct 2026: M1.2 (5): coef_alt.lin (the coefmain.mod call), with four
  crafted switch settings replayed through GAMS. COEF_CPT is now computed
  (coef_alt.lin under OBLONG) for every reference run; NCAP_CPX-shaped
  records wait for coef_shp.mod. G33.
- 27 Oct 2026: the DemoS models leave the suite, the harness and the tests
  (no licence stated by IEA-ETSAP, KanORS-EMR or E4SMA; James). Rule from now
  on: open-licence models only, TIM as a named local-only exception, and no
  learning from closed models (docs/test-models.md). On open models, the
  evidence that stands is TIMES_Demo demo12 passing layers 2 and 3 (licensed
  run, 21 Oct) and the coefficient files passing layer 1 on demo12. CI checks
  no equation family against GAMS until a demo12 fixture is added
  (test/fixtures/public_fixtures.toml).
- 27 Oct 2026: moved to a new private repository with a filtered history:
  the fixtures, crafted cases and crafted states built on the removed models
  were taken out of every commit, with no release assets and no tags
  (published as esma-ie/TIMESjl on 30 Oct 2026 with a fresh history: one
  first commit). Primary test models from here on: TIMES_Demo
  demo12 (CC BY 4.0, CI fixtures), TIM (named exception, James's machine
  only) and OTUS9r (once it is published with an open licence). The M1.0 to
  M1.2 evidence earned on the removed models is to be re-earned on these
  models.
- 28 Oct 2026: M1.2 (4) re-earned on an open model. coef_obj.mod passes layer
  1 on TIMES_Demo demo12 (42 symbols, in CI through
  test/fixtures/public_fixtures.toml) and on a crafted state built on demo12
  and replayed through coef_obj.mod by GAMS (coefobj_unit_gams regenerated;
  scripts/check_replay.jl validates the replay by reproducing demo12's own
  coef dump). The earlier crafted state went with the removed fixtures.
- 28 Oct 2026: M1.2 (5) re-earned on an open model: coef_alt.lin passes layer
  1 on TIMES_Demo demo12 (17 symbols, COEF_CPT included, in CI) and on its
  four crafted switch settings rebuilt on demo12 (coefalt_unit_gams
  regenerated).
- 28 Oct 2026: M1.2 (6): coef_shp.mod L10-37, L43-74 passes layer 1 on
  TIMES_Demo demo12 (no shaping data there: OPYEAR, Z and the cleared work
  symbols) and on two crafted demo12 states (FLO_FUNCX and NCAP_CPX shapes)
  replayed through coef_shp.mod by GAMS. Refused with coef_nio's
  capacity-related commodity flows: L39-42, L77-94, L96. G34.
- 28 Oct 2026: M1.2 (7): coef_ext.vda L12-83, the last file of the
  coefficient stage, passes layer 1 on TIMES_Demo demo12 and on two crafted
  demo12 states replayed through coef_ext.vda by GAMS (eqlducs.vda and
  eqashar.vda included). The whole stage now matches demo12's coef dump on
  126 symbols with nothing excluded (CI). Refused: WAVER, the ETL/CLI/ABS/
  MACRO extensions, reduced flows, unit-commitment preprocessing, FLO_ASHAR,
  COM_CSTBAL. G35. The M1.2 gate waits on James: TIM locally and the stage
  timing against GAMS.
- 29 Oct 2026: the TIM figures of 20-21 Oct (row and column counts, timings,
  objectives, record counts, which features it uses) are removed from the
  repository: they came from a TIM source that is no longer used (the
  archived esma-cgep organisation, CLAUDE.md), and TIM material is never
  committed. TIM's new export (esma-ie fork, 28 Oct) is checked on James's
  machine only. The million-row timings and memory figures are to be measured
  again on an open model (TIMES-NZ, OTUS9r or JRC-EU-TIMES).
- 30 Oct 2026: references for TIMES-NZ 3.0.8 (steady-v308, shift-v308) and
  OTUS9r (reference, tax1_wo_mou) on James's workstation (GAMS 52.1.0 +
  CPLEX). Every coefficient file passes layer 1 on all five reference runs
  of the public suite models (demo12, TIMES-NZ x2, OTUS9r x2): 35 checks,
  29.6 M records at 1e-9, no mismatch (docs/dashboard/suite-public.json).
  Layer 2 is refused on TIMES-NZ (EQ(l)_FLOMRK, EQ_SLSIFT) and OTUS9r
  (EQ(l)_UCRTP, EQN_UCRTC). The repository is published as esma-ie/TIMESjl
  with a fresh history, and OTUS9r as esma-ie/OTUS9r (the EPA original at tag
  epaus9rt-v20.4, the DD export in dd/); the suite pins OTUS9r by commit.
  The suite gets two tiers: core (one baseline case per model, the default
  batch) and milestone (policy and secondary scenarios, very large models);
  OTUS9r-tax1_wo_mou is paused in the milestone tier.
- 30 Oct 2026, evening: OTCGEN (from the US EPA's Generative COMET v0.0.0) and
  OTNYC (from COMET-NYC v16.0.1) are published as esma-ie/OTCGEN and
  esma-ie/OTNYC in the same way as OTUS9r, and join the core tier with one
  reference case each (OTCGEN-gc_ref, OTNYC-s1_nyc_ref), pinned by commit.
  Both preprocess under v4.9.7 (GAMS 54.6.1, no solve); references to follow
  on James's workstation.
- 30 Oct 2026: GAMS 54 is the reference GAMS for every run (James).
  run_references.ps1 0.1.17 stops on another major version and -Resume
  redoes runs made with one. On 30 Oct the core references of demo12,
  TIMES-NZ-steady-v308, OTUS9r-reference (reduce_off) and TIM were already
  GAMS 54.6.1; TIMES-NZ-shift-v308, OTUS9r-reference as_run and
  OTUS9r-tax1_wo_mou were GAMS 52.1.0, to be rerun.
- 31 Oct 2026: M1.3 change 0 (docs/m13-plan.md), alongside the M1.2
  close-out (James): harness 0.3.0 dumps four M1.3 checkpoints in the
  pre-solve run (`input/` before maindrv.mod, `init/` at init_ext, `prep/` at
  prep_ext, `prelv/` at pp_prelv), so preprocessing splits into four segments
  each checked from GAMS's own state; `--only presolve` adds them to existing
  references, under the demo licence too. demo12 checkpoint fixtures in CI;
  `scripts/m13_inventory.jl` and `scripts/m13_probe.jl`.
- 31 Oct 2026: M1.2 (3) re-earned on an open model: the FLO_FUNC and FLO_SUM
  paths of coef_ptr.mod pass layer 1 on two crafted demo12 states run
  through coef_ptr.mod by GAMS 54.6.1 (test/unit/coef_ptr_case.jl, CI), the
  check that went with the removed models on 27 Oct.
- 31 Oct 2026: references of the core tier and TIMES-NZ shift on GAMS 54.6.1
  (the weekend batch: every run PASSes the M1.0 gate, reduce_off and
  as_run). Every coefficient file passes layer 1 on all six public runs,
  with no mismatch; OTCGEN and OTNYC, after the YK1 fix (coef_alt.lin L32),
  also cover the OBLONG NO path of coef_cpt.mod (L19-21, G23)
  (docs/dashboard/suite-public-weekend.json). The coefficient stage is timed
  against GAMS on James's workstation (docs/timings.md): 75x on demo12 (one
  1/64 s step of the GAMS profile) to 359x on OTCGEN, a Phase 2 matter.
- 31 Oct 2026: **M1.2 gate PASS** (James). Every translated coefficient file
  passes layer 1 at 1e-9 on demo12 with nothing excluded and on the crafted
  states (CI), on every public reference run of the core tier and on
  TIMES-NZ shift; TIM was checked locally (its results stay on James's
  machine); the stage is timed against GAMS. Paths still refused are listed
  in docs/m12-plan.md. OTUS9r-tax1_wo_mou (paused) and JRC-EU-TIMES-cli_ll
  were not run for the gate: James defers both to later Phase 1 milestones.
  M1.3 starts.
- 31 Oct 2026: M1.3 (1): the init segment (maindrv.mod L55: init_ext.dsc,
  init_ext.vda with equcrtp.vda INIT_EXT) matches GAMS on every set and
  parameter at the init checkpoint on the five core models, reduce_off and
  as_run, and on demo12 in CI; TIM-bau checked locally. Discrete-capacity
  data is refused, and the paths no core model reaches wait for crafted
  demo12 states (change 1b). prepparm.gms moves to change 6. New GAMS
  semantics: G36 (a GDX file holds only the labels its records use).
- 1 Nov 2026: M1.3 (1b): the init_ext.vda paths no core model reaches
  (updatable OFF-ranges, peaking and storage flags, partial loads, the
  FLO_COST clean-up, VDA_CEH, FLO_EFF, IRE_FLOSUM, COM_AGG, SHELL ANSWER,
  WAVER, UC_ACTBET) pass layer 1 on two crafted demo12 states run through
  init_ext.vda by GAMS 54.6.1 (CI). Discrete-capacity data stays refused.
- 1 Nov 2026: M1.3 (2): ppmain.mod L1-137 (trade, process and commodity
  sets, primary groups, storage defaults, the NCAP_PASTI spread) matches
  GAMS at the prep checkpoint on the symbols it settles (27) on the five
  core models, reduce_off and as_run, and on demo12 in CI; TIM-bau checked
  locally. Four crafted demo12 states run through L1-137 by GAMS 54.6.1
  cover storage, guessed primary groups and NCAP_PASTY (CI). PASTYEAR is
  checked from change 3. The QA log (L35, pp_qaput) is an open item. New
  GAMS semantics: G37.
- 1 Nov 2026: M1.3 (3): ppmain.mod L138-191 with filparam.gms for G_OFFTHD
  (B/E/D/M, the alternative objective's periods, LEAD/LAGT, IPD/FPD, MINYR,
  PASTMILE, EOHYEARS, PERIODYR) matches GAMS at the prep checkpoint on the
  symbols it settles (20, PASTYEAR included) on the five core models,
  reduce_off and as_run, and on demo12 in CI; TIM-bau checked locally.
  Eight crafted demo12 states run through L1-191 by GAMS 54.6.1 cover the
  reset first and last periods and every G_OFFTHD option (CI). New GAMS
  semantics: G38.
- 1 Nov 2026: M1.3 (4): timslice.mod with pp_off.mod (timeslice levels and
  tree, year fractions, TS_OFF and dynamic timeslices, storage cycles and
  lags, the unit-commitment hour maps) matches GAMS at the prep checkpoint on
  the 24 symbols it writes on the five core models, reduce_off and as_run,
  and on demo12 in CI; TIM-bau checked locally. Six crafted demo12 states run
  through ppmain.mod L1-196 by GAMS 54.6.1 cover normalisation, zero
  fractions, TS_CYCLE, TS_OFF with and without DYNTS and unit commitment
  (CI). pp_off.mod is a function change 5 reuses. New GAMS semantics: G39.
- 2 Nov 2026: M1.3 (5): ppmain.mod L199-247 (past investments moved off the
  milestones, NCAP_START as PRC_NOFF, delayed processes, RTP_OFF, RTP, RVP)
  matches GAMS at the prep checkpoint on the symbols it settles on the five
  core models, reduce_off and as_run, and on demo12 in CI; TIM-bau checked
  locally. Three crafted demo12 states run through ppmain.mod L1-247 by GAMS
  54.6.1 cover INT_DEFAULT('PASTI'), user PRC_NOFF ranges through pp_off.mod,
  NCAP_START outside the year range or not an integer, and G_OFFTHD
  thresholds (CI). No new GAMS semantics. Next: preppm.mod (change 6).
- 2 Nov 2026: M1.3 (6a): preppm.mod L1-212 (the interpolation of user data,
  with prepparm.gms, fillparm.gms, filparam.gms, fillvint.gms and
  prepret.dsc PREP) matches GAMS at the prep checkpoint on the 109 symbols it
  settles on the five core models, reduce_off and as_run, and on demo12 in
  CI; TIM-bau checked locally. Four crafted demo12 states run through
  ppmain.mod L1-247 and preppm.mod L1-212 by GAMS 54.6.1 cover every
  interpolation option, exponential growth, write caches, the special-case
  merges, retirements and refits, and G_NOINTERP, on 125 symbols with the
  macros' scratch (CI). Currency conversion (curex.gms) is refused. New GAMS
  semantics: G40, G41. Next: prep_ext.vda (change 6b), which ends the
  init -> prep segment.
- 3 Nov 2026: M1.3 (6b): preppm.mod L213-217 (prep_ext.vda with equcrtp.vda
  PREP_EXT) completes the init -> prep segment. From GAMS's init dump, the
  translated steps reproduce the prep dump on every set and parameter (821
  or 822; the QA-log scalars PUTOUT, PUTGRP and ERRLEV left out) on the five
  core models, reduce_off and as_run, and on demo12 in CI. Three crafted
  demo12 states run by GAMS 54.6.1 cover the PRC_RESID options, the
  commodity-specific availabilities, ACT_FLO, the unit-commitment
  parameters, FLO_ASHAR, cost-neutral ILEDs and the dynamic process bounds,
  159 symbols each (CI). New GAMS semantics: G42. Next: change 7
  (preppm.mod L218-253 with preshape.gms, ppmain.mod L249-460), the start of
  the prep -> prelv segment.
- 3 Nov 2026: M1.3 (7a): preppm.mod L218-252 (preshape.gms) and ppmain.mod
  L249-328 (the horizon, the commodity groups and RC, the primary and shadow
  primary groups) match GAMS at the prelv checkpoint on the 39 symbols they
  settle on the five core models, reduce_off and as_run, and on demo12 in
  CI. Two crafted demo12 states run by GAMS 54.6.1 cover every preshape.gms
  option, the commodity-group integrity check, trade and material shadow
  groups and the capacity-related flows, 192 symbols each (CI). New GAMS
  semantics: G43. Next: change 7b (ppmain.mod L329-460, the timeslice
  levels).
- 3 Nov 2026: M1.3 (7b): ppmain.mod L329-460 (the commodity and process
  timeslice levels, peaking, storage, RPCS_VAR) matches GAMS at the prelv
  checkpoint on the 24 symbols it settles on the five core models,
  reduce_off and as_run, and on demo12 in CI. Two crafted demo12 states run
  by GAMS 54.6.1 cover levels a region lacks, user COM_TS and PRC_TS,
  COM_OFF, peak timeslices at other levels and night storage, 217 symbols
  each (CI). New GAMS semantics: G44. Next: change 8 (ppmain.mod L462-614,
  pp_prelv.vda), which ends the prep -> prelv segment.
- 3 Nov 2026: M1.3 (8a): ppmain.mod L461-611 (lifetimes, refits, capacity
  transfer, capacity bounds, activity and flow availability, PG activity
  flows) matches GAMS at the prelv checkpoint on the 30 symbols it settles
  on the five core models, reduce_off and as_run, and on demo12 in CI. Three
  crafted demo12 states run by GAMS 54.6.1 cover short lifetimes, lead-time
  rounding, refits, every capacity-bound path, PRC_AOFF, PRC_FOFF, OBJ LIN,
  %VALIDATE% and PRC_SIMV, 233 symbols each (CI). No new GAMS semantics.
  Next: change 8b (pp_prelv.vda), which ends the prep -> prelv segment.
- 3 Nov 2026: M1.3 (8b): pp_prelv.vda (with pp_lvlfc.mod for FLO_FR)
  completes the prep -> prelv segment. From GAMS's prep dump, the
  translated steps reproduce the prelv dump on every set and parameter (821;
  the QA-log scalars left out) on the five core models, reduce_off and
  as_run, and on demo12 in CI. Two crafted demo12 states run by GAMS 54.6.1
  cover FLO_FR levelling, the 'N' defaults, IRE_BND, storage shares,
  %SHELL% ANSWER and the VDA_FLOP groups, 246 symbols each (CI). TS_OFF data
  (dynslite.vda) is refused. New GAMS semantics: G45. Next: change 9
  (ppmain.mod L616-682), the start of the prelv -> ppm segment.
- 4 Nov 2026: M1.3 (9): ppmain.mod L616-682 (pp_qafs.mod, SHAPE/MULTI with
  filshape.gms and filparam.gms, the defaults, the capacity-only flows)
  starts the prelv -> ppm segment. The probe compares it at ppm on what
  nothing later changes (PASS, five core models, both variants; demo12 in
  CI). The new replay check (scripts/m13_replay.jl) runs ppmain.mod
  L616-682 in GAMS from the core models' prelv dumps and compares all 34
  symbols at L682. Three crafted demo12 states cover what the core models
  do not reach, 34 symbols each (CI). New GAMS semantics: G46, G47. Next:
  change 10 (ppmain.mod L683-799), the commodity and availability
  attributes by timeslice.
- 4 Nov 2026: M1.3 (10): ppmain.mod L683-797 (pp_lvlfc.mod for the
  commodity attributes, COM_FR, RS_FR and RTCS_FR, the elastic demand
  steps, pp_lvlbr.mod for NCAP_AF, pp_lvlpk.mod) as the probe step
  ppmain_tsattr. Compared at ppm on the 15-18 symbols nothing later
  changes (PASS, five core models, both variants; demo12 in CI); the
  replay check now runs ppmain.mod L616-797 and compares all 65 symbols at
  L797 (PASS, five core models, both variants). Three crafted demo12
  states cover the paths the core models do not reach, 65 symbols each
  (CI). TIMES-Micro (L749) and %DYNTS% with TS_OFF data (L742) refused.
  New GAMS semantics: G48. Next: change 11 (ppmain.mod L800-845), the flow
  attributes, FLO_SHAR and FLO_MARK.
- 4 Nov 2026: M1.3 (11a): ppmain.mod L800-821 (pp_lvlfc.mod for the flow
  attributes, the FLO_PKCOI default, pp_chp.mod) as the probe step
  ppmain_flo; change 11 is split into 11a and 11b. Compared at ppm on the
  13-14 symbols nothing later changes (PASS, five core models, both
  variants; demo12 in CI); the replay check now runs ppmain.mod L616-821
  and compares 82 symbols at L821 (PASS, five core models, both variants).
  Three crafted demo12 states cover what the core models do not reach (CI).
  Next: change 11b (ppmain.mod L823-845), FLO_FUNC, FLO_SUM, FLO_SHAR and
  FLO_MARK.
- 5 Nov 2026: M1.3 (11b): ppmain.mod L823-843 (pp_lvlff.mod, pp_lvlfs.mod,
  the PRC_ACTFLO sums, pp_lvlbr.mod for FLO_SHAR, eqflomrk.mod) as the probe
  step ppmain_flofs. Compared at ppm on the 8-10 symbols nothing later
  changes (PASS, five core models, both variants; demo12 in CI); the replay
  check now runs ppmain.mod L616-843 and compares 101 symbols at L843
  (PASS, five core models, both variants). Two crafted demo12 states cover
  what the core models do not reach (CI). New GAMS semantics: G49. Next:
  change 12 (ppmain.mod L846-935), trade and marketplaces.
- 5 Nov 2026: M1.3 (12): ppmain.mod L846-933 (the trade attributes
  levelled, pp_lvlif.mod, the marketplaces) as the probe step ppmain_ire.
  Compared at ppm on the 11 symbols nothing later changes (PASS, five core
  models, both variants; demo12 in CI); the replay check now runs ppmain.mod
  L616-933 and compares 112 symbols at L933 (PASS, five core models, both
  variants). Two crafted demo12 states cover the marketplace and
  distribution paths (CI). Next: change 13 (ppmain.mod L936-1056), in two
  parts like 11.
- 5 Nov 2026: M1.3 (13a): ppmain.mod L936-1001 (the commodity subsets and
  COM_LIM defaults, the trade conversions, pp_lvlbd.mod, FLO_BND and ACT_BND
  from FLO_BDLVL) as the probe step ppmain_bnd. Compared at ppm on the
  16-17 symbols nothing later changes (PASS, five core models, both
  variants; demo12 in CI); the replay check now runs ppmain.mod L616-1001
  and compares 126 symbols at L1001 (PASS, five core models, both
  variants). One crafted demo12 state covers the bound aggregation (CI).
  Next: change 13b (ppmain.mod L1003-1056), the cumulative bounds and the
  RHS commodities.
- 5 Nov 2026: M1.3 (13b): ppmain.mod L1003-1056 (the cumulative bounds,
  the RHS commodities) as the probe step ppmain_cum. Compared at ppm on the
  15 symbols nothing later changes (PASS, five core models, both variants;
  demo12 in CI); the replay check now runs ppmain.mod L616-1056 and compares
  140 symbols at L1056 (PASS, five core models, both variants). Two crafted
  demo12 states cover the rest (CI). Next: change 14 (ppmain.mod
  L1058-1101), storage.
- 5 Nov 2026: M1.3 (14): ppmain.mod L1058-1099 (the storage processes) as
  the probe step ppmain_stg. Compared at ppm on the 12-13 symbols nothing
  later changes (PASS, five core models, both variants; demo12 in CI); the
  replay check now runs ppmain.mod L616-1099 and compares 151 symbols at
  L1099 (PASS, five core models, both variants). A crafted demo12 state
  covers a flexible stockpile storage (CI). Next: change 15 (ppmain.mod
  L1101-1226), user constraints, in two parts.
- 5 Nov 2026: M1.3 (15a): ppmain.mod L1101-1179 with prepxtra.mod UCINT
  (the user-constraint defaults) as the probe step ppmain_uc. Compared at
  ppm on the 13-15 symbols nothing later changes (PASS, five core models,
  both variants; demo12 in CI); the replay check now runs ppmain.mod
  L616-1179 and compares 172 symbols at L1179 (PASS, five core models, both
  variants). A crafted demo12 state covers the paths the core models do not
  reach (CI). Next: change 15b (ppmain.mod L1181-1226, pp_lvlus.mod).
- 5 Nov 2026: M1.3 (15b): ppmain.mod L1181-1226 with pp_lvlus.mod (the UC
  group maps, the UC attributes levelled to the process and commodity
  timeslices, RCS_COMBAL/RCS_COMPRD) as the probe step ppmain_ucmap.
  Compared at ppm on the 10-17 symbols nothing later changes (PASS, five
  core models, both variants; demo12 in CI); the replay check now runs
  ppmain.mod L616-1226 and compares 185 symbols at L1226 (PASS, five core
  models, both variants). A crafted demo12 state covers the levelling paths
  (CI). Next: change 16 (ppmain.mod L1228-1336), blending.
- 5 Nov 2026: M1.3 (16): ppmain.mod L1228-1333 (the blending block) as the
  probe step ppmain_blend. Blending data (BL_TYPE, OPR) is refused; no
  suite model has any, and without it only the REFUNIT default acts.
  Compared at ppm on the 13 symbols the block writes (PASS, five core
  models, both variants; demo12 in CI); the replay check now runs
  ppmain.mod L616-1333 and compares 198 symbols at L1333 (PASS, five core
  models, both variants). Next: change 17 (pp_reduce.red, dynslite.vda,
  ppmain.mod L1336-1357; cal_red.red).
- 5 Nov 2026: M1.3 (17a): ppmain.mod L1336-1357 with pp_reduce.red (the
  reduction of model size, RTPCS_VARF, RTP_VINTYR) as the probe step
  ppmain_reduce. Compared at ppm on the 18 symbols nothing later changes
  (PASS, five core models, %REDUCE% NO and YES; demo12 in CI); the replay
  check now runs ppmain.mod L616-1350 and compares 216 symbols at L1350
  (PASS, five core models, both variants). Two crafted demo12 states cover
  %REDUCE% YES and unset (CI). Next: change 17b (cal_red.red, layer 2) and
  change 18 (ppm_ext).
- 5 Nov 2026: M1.3 (18a): ppm_ext.dsc and ppm_ext.vda L11-58 with
  pp_actef.vda (the ACT_EFF preparation) as the probe step ppm_ext_actef.
  Compared at ppm on the 20 symbols nothing later changes (PASS, five core
  models, both variants; demo12 in CI); the replay check now runs
  ppmain.mod L616-1357 and ppm_ext.vda L11-58 and compares 229 symbols at
  L58 (PASS, five core models, both variants). Two crafted demo12 states
  cover ACT_EFF below the process level, on primary-group commodities and
  EPS, ramping, partial loads and NORTS (CI). Next: change 18b (ppm_ext.vda
  L59-169, the segment's all-symbols check), then 17b (cal_red.red).
- 5 Nov 2026: M1.3 (18b): ppm_ext.vda L59-169 with equcrtp.vda PPM_EXT as
  the probe step ppm_ext, the end of the prelv -> ppm segment, compared on
  every set and parameter at ppm (PASS, five core models, both variants;
  demo12 in CI). All four preprocessing segments now match GAMS from their
  own start. Five crafted demo12 states against GAMS to the end of
  ppm_ext.vda (CI). Next: change 17b (cal_red.red, layer 2), then the M1.3
  gate (the chain from the input dump, CI on demo12, timings).
- 5 Nov 2026: M1.3 (17b): cal_red.red, cal_fflo.mod L35-50 and
  bnd_flo.mod L34-39, the model under %REDUCE% YES. demo12 as_run PASS on
  layers 2 and 3 (now in CI as `demo12_red`); the other core models wait for
  M1.1's untranslated equation families in both variants. Next: the M1.3
  gate.
- 5 Nov 2026: M1.3 gate checks (docs/m13-plan.md, "Gate checks"): the
  chain from the input dump PASS at every checkpoint on the five core
  models, both variants (`scripts/m13_gate.jl`); in CI the demo12 chain
  through the coefficients (`test/unit/test_m13_chain.jl`) and the model
  with REDUCE off and on; preprocessing 3.0x GAMS on demo12, 4.8x to 5.5x
  on the large core models (`scripts/m13_timing.jl`, docs/timings.md).
  Outstanding for the gate: TIM-bau on James's machine, and the merge of
  #44-#47.
- 5 Nov 2026: M1.3 (17c): the two REDUCE paths demo12 does not reach (an
  emission whose source flow is the activity flow, cal_red.red L37-38;
  FLO_BND on that flow, bnd_flo.mod L37-39), on a crafted case,
  TIMES_Demo-demo12_red17b (demo12 + red17b.dd; `reference/crafted.toml`,
  a crafted-case suite next to the model suite). Layers 2 and 3 PASS on
  both variants (GAMS 54.6.1, CPLEX and HiGHS), the M1.3 chain PASS; two
  CI fixtures. It also found and fixed an undefined variable in the
  EQ(l)_FLOBND completeness check (M1.1 code, first reached by FLO_BND
  data).
- 5 Nov 2026: the equation families M1.1 left untranslated become M1.3
  changes 19-25 (James), with demo12 variants for advanced features
  (docs/m13-plan.md). M1.3 (19): eqstgips.mod, EQ_STGIPS. OTNYC passes
  layers 2 and 3 on both variants, the first large core model to do so;
  EQ_STGIPS rows match on OTCGEN.
- 5 Nov 2026: M1.3 (19b): eqstgaux.mod L25-32, the inter-period storage
  terms of EQ_STGAUX (rows match on OTCGEN), and the crafted case
  TIMES_Demo-demo12_ips that brings inter-period storage into CI (layers
  2-3 and the M1.3 chain PASS on both variants).
- 5 Nov 2026: demo12 variants for advanced features (docs/demo12-variants.md;
  James approved the list and the release order). Variant 2, dispatching and
  unit commitment (TIMES_Demo-demo12_uc): GAMS generates all 14 families;
  TIMES.jl's preprocessing passes from the input dump, and model generation
  refuses the untranslated families. New CI check for variants
  (test/unit/test_variants.jl): preprocessing input -> ppm, and the exact
  list of refused families.
- 5 Nov 2026: demo12 variant 5, retrofits and lifetime extensions
  (TIMES_Demo-demo12_refit). It found a silent gap: the early-retirement
  checks looked for VNRET, a $MACRO never in a dump, so a model with
  retirements was built without its retirement rows; now keyed on RP_RTF.
  OTUS9r uses early retirement and refits, so M1.3 gains change 20b
  (prepret.dsc equations).
- 6 Nov 2026: M1.3 (20): equcrtp.vda L73-121, the dynamic process and
  commodity bounds (EQN_UCRTP, EQE_UCRTP, EQN_UCRTC). Rows match GAMS on
  OTUS9r (15,962, both variants); the crafted case TIMES_Demo-demo12_ucrt
  reaches the other branches and passes layers 2-3 and the M1.3 chain.
  OTUS9r's whole model now needs only change 20b.
- 6 Nov 2026: M1.3 (20b-1): prepret.dsc L89-117, the retirement and refit
  rows (EQ_CUMRET, EQL_SCAP, EQL_REFIT) match GAMS on demo12_refit and
  OTUS9r. Change 20b is done in four parts (equations, the -VAR_SCAP
  capacity terms, the bounds, the objective); the family stays refused
  until the last.
- 6 Nov 2026: M1.3 (20b-2): prepret.dsc L87-88, the -VAR_SCAP terms of
  early retirement in the capacity equations (EQ_CPT, EQ_CAPACT, EQ_PEAK,
  EQ_CAFLAC, EQL_CAPFLO); rows match GAMS on OTUS9r, demo12_refit and the
  new crafted case demo12_refit_afc. Discrepancy D1 withdrawn (the
  documentation's VAR_SCAP term is in GAMS after all); new GAMS semantics
  note G48.
- 6 Nov 2026: M1.3 (20b-3): prepret.dsc L66-80, the VAR_RCAP and VAR_SCAP
  bounds; every retirement column's bounds match GAMS on OTUS9r,
  demo12_refit and demo12_refit_afc (now with RCAP_BND LO, FX and a
  negative 'N' option).
- 6 Nov 2026: M1.3 (20b-4): prepret.dsc L134-162, the objective terms of
  early retirement; `generate!` now builds models with early retirement.
  demo12_refit and demo12_refit_afc pass layers 2-3 (CI fixtures, whole
  model). OTUS9r's whole model is generated for the first time and passes
  layer 2 on both variants (2,174,010 rows reduce_off).
- 8 Nov 2026: M1.3 (26): curex.gms, currency conversion (preppm.mod
  L27-28), moved ahead of changes 21-25b (James). A crafted demo12 state
  checked against GAMS's own run of curex.gms, and the crafted case
  TIMES_Demo-demo12_curex: the M1.3 chain and the whole model (layers 1-3)
  PASS on both variants; CI fixtures. New GAMS semantics: G51.
- 8 Nov 2026: pp_off.mod's scratch (FIL, STARTOFF, ENDOFF) is kept as GAMS
  leaves it, so a model with OFF ranges passes the all-symbols checks at
  the checkpoints; the crafted OFF-range states compare it.
- 9 Nov 2026: M1.3 (21): equserco.mod L80-106 and uc_pasti.mod, dynamic
  user constraints in the RHS direction, with the UC_DYNT attributes (N,
  CUMSUM, CUM+, SYNC). OTCGEN's whole model is generated for the first time
  and passes layers 2-3 on both variants; every TIMES-NZ user-constraint
  row matches CONVERT; crafted case TIMES_Demo-demo12_ucdyn (CI fixtures)
  passes the M1.3 chain and layers 1-3.
- 9 Nov 2026: M1.3 (22): the user-constraint attribute factors of uc_*.mod
  (PERDISC, PERIOD, NEWFLO, EFF, CAPACT, BUILDUP, COST, DELIV, TAX, SUB);
  ANNUL and ONLINE stay refused. Crafted case TIMES_Demo-demo12_ucattr (CI
  fixtures) passes the M1.3 chain and layers 1-3; the core models' UC rows
  are unchanged.
- 9 Nov 2026: M1.3 (23): eqflomrk.mod L56-105, EQ(l)_FLOMRK. Every TIMES-NZ
  market-share row matches CONVERT; crafted case TIMES_Demo-demo12_flomrk
  (CI fixtures) reaches the exchange and storage branches and all three
  bound types.
