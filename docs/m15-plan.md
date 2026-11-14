# M1.5 run options: plan, part 1: the stepped (myopic) solve (14 Nov 2026)

Source: TIMES v4.9.7, etsap-TIMES/TIMES_model @ d9a6a25. Started on
14 Nov 2026, before the M1.3 and M1.4 gates close: James asked for every
refused feature to be translated, the stepped solve second in the order
(after the unit commitment), and said "you can start myopic run tests before
M1.3 and M1.4 close" (#108, decision 3; `docs/decisions.md`). The M1.5 gate
still waits for the gates before it. One change per PR, in the order below;
GAMS names kept; every function cites its lines.

This file covers the stepped solve only. The other run options of M1.5 (the
OBJ variants, MID_YEAR, DSCAUTO, VAR_UC, the restart points with FIXBOH) are
added to it as a second part.

## Goal

Run a stepped (myopic) TIMES model in TIMES.jl: `$SET TIMESTEP n` in the run
file. The model is not solved once over the whole horizon. It is solved in
steps of n years: each step sees a few periods only, keeps what the earlier
steps decided, and knows nothing of the periods after its own.

Each step must equal GAMS: the data the step's model is generated from
(layer 1, 1e-9), the step's rows, columns, coefficients, right-hand sides and
bounds (layer 2, 1e-9), and the step's objective (layer 3, 1e-6). When it
passes, the two refusals of a stepped run are removed (`generate!`,
`src/model/generate.jl` L44; `bounds_unported`, `src/model/bndmain.jl` L104).

## What GAMS does in a stepped run

Up to the end of the equation declarations a stepped run is an ordinary run
with two differences, both translated in M1.3 change 30 (`docs/m13-plan.md`):
no RTP_CAPVL (coef_alt.lin L81) and the salvage preparation left to the steps
(eqobsalv.mod L23-25). Then `maindrv.mod` L109-113 includes `solve.stp` in
place of `solve.mod`:

1. **Before the loop** (solve.stp L43-107). The first step's periods are
   chosen: SUBT is the set of periods the step solves, BACKWARD the periods
   before it (already solved), FORWARD the periods after it (not yet seen).
   Levels left from earlier solves are cleared (clearsol.stp). The user's
   fixed bounds on capacity and on user constraints are copied to lower and
   upper bounds, so that a later step can relax them by a tolerance.
2. **Each step** (the WHILE loop, L109-321):
   - the horizon ends at the step's last period (MIYR_VL), so the salvage
     value and the objective coefficients are computed again for that end
     (coef_alt.lin L134-158, eqobsalv.mod L26-82);
   - user constraints that sum over periods or link two periods are cut to
     the step's periods, and their right-hand sides are moved by what the
     earlier steps already used (L132-193);
   - every variable of a BACKWARD period is fixed at the level the earlier
     step found; every variable of a FORWARD period is fixed at 0
     (L199-282);
   - the model is generated over SUBT only and solved (L285-294). The
     equations are the ordinary ones: the macros `%R_T%`, `%TX%` and
     `%R_V_T%` (maindrv.mod L38-41) put `SUBT(T)` where a run that is not
     stepped has `T`;
   - the next step's periods are chosen (L303-308): it starts G_OVERLAP
     years before the first FORWARD period, so two steps share the periods
     of the overlap, and the later step decides them again;
   - the bounds are set again for the next step (bndmain.mod with its
     second argument 1, L319).
3. **After the loop** (L325-330): levels and marginals are tidied for the
   report.

The levels of one step are an input of the next. So the steps cannot be
checked from a single dump, and a matrix cannot be exported without a solve.
The reference keeps every step for that reason (harness 0.3.4, below).

## The GAMS code to translate

| File | Lines | What |
| --- | --- | --- |
| maindrv.mod | 38-41, 92, 109-114 | the macros `%R_T%`, `%TX%`, `%R_V_T%`, `%RTPX%`; bndmain.mod called with 0 before the loop; solve.stp in place of solve.mod |
| solve.stp | 9-26 | the header (aborts with STAGES and SENSIS, needs VAR_UC YES) and the declarations |
| solve.stp | 43-57 | the first step: YR_V1, YR_VL (the TIMESTEP), G_OVERLAP (default half the step), SUBT, BACKWARD, FORWARD, RT_PP, NO_RT, RTC_NET, RTC_PRD |
| clearsol.stp (solve.stp L60) | 1-35 | RVT; the levels of the flow, activity, capacity and user-constraint variables cleared |
| solve.stp | 61-66 | VAR_ACT and VAR_COMNET levels from a solution given at the start |
| solve.stp | 69-98 | fixed bounds copied to lower and upper (CAP_BND, UC_RHS*, PRC_DYNUC); UC_RN (user constraints with a negative coefficient); R_UC; RTP_VARP; RTP_CAPYR; VAR_CAP levels |
| solve.stp | 101-107 | STP_UCT (the user constraints' period sets as given), STP_DIV (ALTOBJ > 1) |
| solve.stp | 109-128 | the loop's start: BACKWARD, NO_RT, RT_PP, the vintages V without FORWARD, MIYR_VL, the end of horizon; coef_alt.lin STP; OBJ_LIFE; eqobsalv.mod STP EXIT; RVPRL |
| coef_alt.lin | 134-158 | STP: RTP_CAPVL and the divisors OBJ_DIVI, OBJ_DIVIV, OBJ_DIVIII for the step's end of horizon (LINFLO only: OBJ ALT or LIN) |
| eqobsalv.mod | 26-85 | the salvage preparation, run in each step (`STP EXIT`) |
| solve.stp | 132-151 | user constraints cut to the step: UC_T_SUM, UC_T_EACH, UC_T_SUCC, UC_T, UC_DYNBND; CM_MAXC (CLI, refused) |
| solve.stp | 153-192 | the tolerances; UC_BND from the right-hand sides and the slack levels of the earlier steps; the right-hand sides, the cumulative bounds and CAP_BND moved by them |
| bnd_ucw.mod (solve.stp L193), bnd_ucv.mod | 13-21 | the bounds of the user-constraint slack variables for the step |
| solve.stp | 195-220 | BACKWARD variables fixed at their levels (VAR_ACT, VAR_FLO, VAR_IRE, VAR_SIN, VAR_SOUT, VAR_UPS, VAR_UPT, VAR_UDP, VAR_COMNET, VAR_COMPRD, VAR_ELAST, VAR_DAM, VAR_NCAP, VAR_SCAP); VAR_CAP bounds; NO_RVP |
| solve.stp, bnd_cum.mod | 222-230; 12-48 | cumulative bounds for a horizon that ends at MIYR_VL |
| solve.stp | 232-264 | blending; the trade of a region fixed by REG_FIXT (FIXBOH only, see "Flagged") |
| solve.stp | 266-282 | FORWARD variables fixed at 0 |
| solve.stp, solve.mod | 285-295; 12-44 | the solve: BRATIO, SOLVEOPT=MERGE (the levels of variables outside the step's model stay), pp_clean.mod, the SOLVE, PRESOL = 0 |
| solve.stp | 299-319 | marginals restored; the next step's SUBT; V and the user constraints' period sets restored; bndmain.mod with 1 |
| bndmain.mod | 15, 44-46, 57-59, 64, 69 | the parts that depend on its second argument or on the macros: the clears of the first call only; NCAP_BND, COMNET and COMPRD bounds over `%R_T%`; bnd_cum.mod in the first call only |
| solve.stp | 325-330 | after the loop: VAR_NCAP levels, marginals of NO_RT, EQ_IRE marginals |

The macros `%R_T%`, `%TX%`, `%R_V_T%` and `%RTPX%` are used in these files
(lines that use one, v4.9.7). Each use is translated as a predicate on the
period, true for every period when the run is not stepped, so the generated
LP of every other run stays identical.

| Translated families | Lines |
| --- | --- |
| eqactups.vda, eqlducs.vda | 9 each |
| bndmain.mod, eqstgtss.mod, equcwrap.mod | 3 each |
| eqcaflac.vda, equcrtp.vda | 2 each |
| bnd_act.mod, eqactbnd, eqactflo, eqashar.vda, eqblnd, eqbndcom, eqcapact, eqcapvac, eqcombal, eqflobnd, eqflofr, eqflomrk, eqfloshr, eqire, eqirebnd, eqpeak, eqptrans, eqstgaux (.mod, .lin), eqstgflo, eqstgips (.mod, .lin), eqxbnd, pp_actef.vda | 1 each |
| powerflo.vda, resloadc.vda | 7, 5 |

In refused code, translated with its feature: equ_ext.abs 14, equ_ext.etl 12,
gasgrids.vda 11, equ_ext.dsc 2, prepret.dsc 1, equ_ext.ecb 2, eqdamage 1,
eqobjels 1.

## The reference: every step of the GAMS run (harness 0.3.4)

`reference/README.md`, "The steps of a stepped run". For each step k the
reference holds:

- `steps/<k>/final/`: every symbol just after the SOLVE of step k. That is
  the data step k's model was generated from (SUBT, the bounds, the
  right-hand sides, the salvage coefficients, ...) and the levels and
  marginals step k found, which are the input of step k+1.
- `steps/<k>/matrix/`, `steps/<k>/matrix_dictmap/`: CONVERT's export of step
  k's model, generated from the levels of the solve run.
- `raw/tjl_model_step<k>.mps.gz`: the same model as an MPS file.

TIMES is not edited: the harness uses the two hooks TIMES has for a web
front end (`www_in.cgi`, `www_out.cgi`).

The crafted case **demo12_step** (demo12 with `$SET TIMESTEP 20`, OBJ MOD,
CC BY 4.0; `reference/dd/demo12_step/`) has periods 2005, 2010, 2015, 2020,
2030 and 2050, the default overlap of 10 years, and three steps. GAMS 54.6.1,
CPLEX and HiGHS, both variants optimal:

| Step | SUBT | BACKWARD | FORWARD | Horizon ends | Rows / columns / nonzeros, REDUCE off | as run | Objective |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 2005, 2010, 2015, 2020 | none | 2030, 2050 | 2025 | 5,921 / 6,717 / 20,736 | 2,201 / 3,183 / 12,216 | 12,397,965.9863 |
| 2 | 2020, 2030 | 2005, 2010, 2015 | 2050 | 2040 | 2,975 / 4,421 / 12,438 | 1,133 / 2,305 / 7,782 | 20,325,417.7629 |
| 3 | 2050 | 2005 to 2030 | none | 2052 | 1,380 / 3,179 / 6,930 | 540 / 1,949 / 4,756 | 23,960,685.7370 |

GAMS/HiGHS gives the same three objectives as GAMS/CPLEX in both variants.
The CONVERT run's models have the solve run's sizes, and HiGHS on each MPS
file gives the step's objective.

## The changes

| # | Change | GAMS | Parity check |
| --- | --- | --- | --- |
| 1 | The per-step reference: harness 0.3.4 | none (the hooks at maindrv.mod L50 and solve.mod L44) | sizes of each step in the CONVERT run equal the solve run's; HiGHS on each step's MPS file; a reference that is not stepped unchanged |
| 2 | The partition and the preparation of a step: `stp_init!`, `stp_step_prep!`, `stp_next!` (working names) | solve.stp L18-26, L43-107, L111-196, L299-314; clearsol.stp; coef_alt.lin L134-158; eqobsalv.mod L26-85 | layer 1 per step: every set and parameter of `steps/<k>/final` at 1e-9 (less the harness's own TJL symbols), fed with GAMS's levels of step k-1 |
| 3 | The equations over SUBT and the bounds of a step | maindrv.mod L38-41 and every macro use above; solve.stp L115 (V), L195-282; bndmain.mod with its second argument; bnd_ucw.mod; bnd_cum.mod | layer 2 per step: `steps/<k>/matrix` at 1e-9 (rows, columns, order, coefficients, right-hand sides, bounds), fed with GAMS's levels of step k-1; every model that is not stepped: LP identical |
| 4 | The driver `solve_stepped!` (the loop, the solve, the levels kept between steps as SOLVEOPT=MERGE does, L325-330); the two refusals removed | solve.stp L109, L285-295, L303-321, L325-330; solve.mod L12-44 | layer 3 per step and at the end, 1e-6: TIMES.jl with HiGHS, each step on its own levels, against GAMS/CPLEX and GAMS/HiGHS; a public fixture of the steps in CI; `scripts/m13_gate.jl` runs the stepped case to the end |
| 5 | A second crafted case for branches demo12_step does not reach (below) | the same lines | layers 1 to 3 per step |

In change 3 a fixed variable stays a column: GAMS's matrix has the BACKWARD
and FORWARD variables as columns with equal lower and upper bounds, and the
layer 2 check compares them so. The JuMP model is built anew for each step.

Change 2 and change 3 are checked on GAMS's levels, not TIMES.jl's own, so a
difference in one step cannot hide in the next. Change 4 then runs the chain
on TIMES.jl's own levels. An LP can have more than one optimum; if a later
step's model differs from GAMS's only because an earlier step chose another
optimum with the same objective, the step's objective is still compared at
1e-6, and each side's optimum is cross-evaluated in the other's model, as
layer 3 does for every run.

## What demo12_step reaches, and what it does not

Reached (records in the dump of step 2): user constraints by region and
period (UC_R_EACH, UC_T_EACH, UC_RHSRT 8, UC_RHSRTS 6) with UC_RN 3, R_UC 2
and UC_BND 14; cumulative flow bounds (FLO_CUM 18, VAR_CUMFLO 18) through
bnd_cum.mod in each step; VAR_CAP with RTP_VARP 18 and NO_RVP 4; RTC_NET 84
and RTC_PRD 12; trade between the two regions; the salvage preparation
(OBJ_LIFE 674, OBJSCC 107).

Not reached, translated as GAMS has them and to be flagged in each PR:

| Branch | Lines of solve.stp | In a second crafted case? |
| --- | --- | --- |
| G_OVERLAP given by the user | 45 | yes |
| OBJ ALT or LIN (LINFLO): STP_DIV, coef_alt.lin STP | 104-107, 124 | yes |
| CAP_BND | 69, 96, 190-191, 218-219, 279 | yes |
| a cumulative user constraint (UC_T_SUM) | 132-137 | yes |
| a dynamic user constraint (UC_T_SUCC, UC_DYNBND, PRC_DYNUC) | 144-151, 183-185 | yes |
| user constraints summed over regions (UC_R_SUM) and their right-hand sides | 141-144, 157, 178-179 | yes |
| COM_CUM (VAR_CUMCOM) | 186-189, 222-230 | yes |
| REG_CUMCST | 196 | yes, if demo12's data allow |
| VAR_UPS, VAR_UPT, VAR_UDP (dispatching, unit commitment), VAR_SCAP (retirement) | 204-206, 220 | to try: a stepped variant of demo12_uc |
| blending, elastic demand, damage | 208-209, 232-233, 281 | with those features |
| FIXBOH and REG_FIXT | 46-49, 158, 177, 180-181, 186-189, 234-264, 315-317 | no: see "Flagged" |

## Flagged

- **FIXBOH** (a run fixed to an earlier solution up to a year) and
  **REG_FIXT** take their levels from a restart point (SPOINT or LPOINT),
  which TIMES.jl refuses, and no open model has one. Their branches of
  solve.stp stay refused until the restart points are translated (part 2 of
  this plan); a run with them stops with the usual message.
- **STAGES, SPINES and SENSIS** with a stepped run: solve.stp L11-12 aborts
  or takes other branches; refused with the stochastic extension.
- **CLI** (CM_MAXC, L147) and **TM_HSX** (the tolerances of L154): refused
  with their extensions.
- A start from a given solution (L61-66, `VAR_UC.L('SOLVE_STATUS')`): needs
  a restart point; translated for the case without one (no levels).

## Not in this plan

The report of a stepped run (M1.6), timings (Phase 2), and the solver's
advanced basis (`BRATIO=1`, L285: a solver setting that does not change the
LP or its optimum value).
