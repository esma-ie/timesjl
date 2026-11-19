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
added to it as a second part. James, 18 Nov 2026 (q1 and q2 of the M1.3 gate
audit) moved more of the refused features here: %OBJANN% YES (eqobjann.tm), %VALIDATE% YES, %VINTOPT% 1 (fillvint.gms), %WAVER% YES (fillwave.gms), %INTEXT_ONLY% YES and %PREP_ANS% YES; and user constraints with VAR_UC not YES (eqmain.mod L204-207, L229-232; equcwrap.mod L13), and the VDA trade bounds and prices from an earlier run (bnd_ire.vda, equ_ext.vda L67; GDX_IREBND and GDX_IPRIC, init_ext.vda L137-151).

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
| 2 | Done, 14 Nov 2026 ("Change 2 as built", below). The partition and the preparation of a step: `stp_init!`, `stp_step_prep!`, `stp_next!` and the point store `StpPoint`, in `src/model/solve_stp.jl` | solve.stp L9-26, L43-57, L69-107, L111-196, L217, L222-227, L288-289, L295-319; clearsol.stp L8-10; coef_alt.lin L27, L31-63, L134-136, L160 (the block L137-157, LINFLO only, refused until change 6); eqobsalv.mod L19-85; bnd_ucw.mod L13-21; bnd_cum.mod L12-20, L27-38; the data statements of bndmain.mod with its second argument 1 | layer 1 per step: every set and parameter of `steps/<k>/final` at 1e-9 (less the harness's own TJL symbols and Z), fed with GAMS's levels and marginals of step k-1. demo12_step, both variants: 957 symbols in each of the three steps, none differs |
| 3 | Done, 15 Nov 2026 ("Change 3 as built", below). The equations over SUBT and the bounds of a step: `eq_periods`; `stp_bounds_init!`, `stp_step_bounds!`, `stp_bndmain!` and `stp_model` in `src/model/bnd_stp.jl` | maindrv.mod L38-41 and every macro use above; solve.stp L115 (V), L193-233, L267-281, L319; bndmain.mod with its second argument; bnd_ucw.mod with bnd_ucv.mod; bnd_cum.mod | layer 2 per step: `steps/<k>/matrix` at 1e-9 (rows, columns, order, coefficients, right-hand sides, bounds), fed with GAMS's levels of step k-1. demo12_step, both variants: the LP of each of the three steps equals GAMS's. Every model that is not stepped: LP identical (the whole suite) |
| 4 | Done, 15 Nov 2026 ("Change 4 as built", below). The driver `solve_stepped!` (the loop, the solve, the levels kept between steps as SOLVEOPT=MERGE does), `stp_merge_point!`, `stp_finish!`, in `src/model/solve_stp.jl`; the two refusals removed | solve.stp L109, L285-294, L321, L325-329; solve.mod L12-41; err_stat.mod L63-69 | layer 3 per step and at the end, 1e-6: TIMES.jl with HiGHS against GAMS/CPLEX and GAMS/HiGHS, with GAMS's levels between the steps (and layers 1 and 2 again) and on TIMES.jl's own levels. demo12_step, both variants: the objective of each of the three steps equals GAMS's (relative difference under 3e-12). The step fixtures in CI; `scripts/m13_gate.jl` runs the stepped case to the end |
| 5 | Done, 15 Nov 2026 ("Change 5 as built", below). The second crafted case, demo12_step2 (TIMESTEP 20, G_OVERLAP 15; CAP_BND; user constraints summed over the periods and over the regions, dynamic ones; COM_CUM, FLO_CUM, REG_CUMCST). One statement corrected: the lead of the N record in a second pass of bnd_cum.mod (`bnd_cum_flo`, `bnd_cum_com`). Harness 0.3.5 | solve.stp L44, L69-98, L132-196, L217-230, L279, L305; bnd_cum.mod L13-14, L19-20, L27-28, L34-35; bnd_ucv.mod L24-25 | layers 1 to 3 per step, both variants, from GAMS's input dump and from the DD files: all pass; CI: test_solve_stp2.jl on the fixtures of the case |
| 6 | Done, 15 Nov 2026 ("Change 6 as built", below). A stepped run with OBJ ALT or LIN: the divisors of coef_alt.lin STP (`coef_alt_stp!`), with the crafted cases demo12_steplin, demo12_steplino, demo12_stepalt1, demo12_lin and demo12_alt. GAMS's rounding of `**` and POWER in `gpow` and `gpower` (G61). The DD reader sets ALTOBJ. OBJ ALT with several steps fails in GAMS itself (D42) | solve.stp L104-107, L124; coef_alt.lin L137-157; initmty.mod L421-423, L432 | layers 1 to 3 per step, both variants, from GAMS's input dump and from the DD files: all pass; CI: test_solve_stplin.jl on the fixtures of demo12_steplin |
| 7 | Done, 15 Nov 2026 ("Change 7 as built", below). The third crafted case, demo12_step3 (TIMESTEP 20; dispatching and unit commitment, blending, an inter-period store, load shifting, retirement and refits, costs on the storage flows). No change to the translation. GAMS itself keeps blending fixed at zero from the second step on (D43; that part of U7 is settled) | solve.stp L128, L203-207, L220, L232-233, L281 | layers 1 to 3 per step, both variants, from GAMS's input dump and from the DD files: all pass; CI: test_solve_stp3.jl on the fixtures of the case |

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

## Change 2 as built (14 Nov 2026)

`src/model/solve_stp.jl` (GAMS lines of solve.stp unless a file is named):

| Function | GAMS | What |
| --- | --- | --- |
| `stp_init!` | L9-26, L43-57; clearsol.stp L8-10; L69-107 | the control checks; the first partition (YR_VL, G_OVERLAP, YR_V1, SUBT, BACKWARD, FORWARD, RT_PP, NO_RT, RTC_NET, RTC_PRD); RVT; fixed bounds copied to lower and upper (CAP_BND, the user constraints' right-hand sides, PRC_DYNUC); UC_RN, R_UC, RTP_VARP, RTP_CAPYR; STP_UCT, STP_DIV |
| `stp_step_prep!` | L111-196, L217, L222-227, L288-289 | one step up to its SOLVE: BACKWARD, NO_RT, RT_PP, the vintages, MIYR_VL and the end of the horizon; `coef_alt!(tm; stp=true)`; OBJ_LIFE; `eqobsalv_step!`; RVPRL; the user constraints' period sets cut to the step; UC_BND and the right-hand sides, cumulative bounds and CAP_BND it moves; `bnd_ucw_data!`; UC_RTSUC; REG_CUMCST; NO_RVP; `bnd_cum_data!` for a horizon that ends at MIYR_VL; PAR_CUMFLOM and PAR_UCR |
| `stp_next!` | L295-319 | after the SOLVE: PRESOL 0; the marginals restored; the next SUBT and YR_V1; the vintages and the user constraints' period sets restored; `bnd_data!(tm; cum=false)`, bndmain.mod with its second argument 1 |
| `StpPoint`, `stp_level`, `stp_marginal`, `stp_load_point!` | the `.L` and `.M` these lines read | the levels and marginals statements between two steps read (VAR_NCAP, VAR_CAP, the six slack variables of the user constraints, VAR_CUMFLO, VAR_CUMCOM), kept apart from the JuMP model, which is built anew in each step. The run starts with every level zero. Change 4 merges each step's solution into the store, as SOLVEOPT=MERGE does (L286); the layer 1 check loads GAMS's point of the step |

Changed outside that file, for a stepped run only: `coef_alt!(tm; stp=true)`
(src/coef/coef_alt.jl), `eqobsalv_step!` (src/model/eqobjfix_prep.jl; the
statements of eqobsalv.mod L26-82 now test that a vintage is in MODLYEAR,
which every vintage is outside a step), `bnd_cum_data!`, `bnd_ucw_data!` and
`bnd_data!(tm; cum=false)` (src/model/qack_prep.jl; the same statements as
before, callable apart), and `var_uc`, YES in a stepped run (initmty.mod
L446-447). No generated LP changes: model generation still refuses a stepped
run until changes 3 and 4.

Run controls, as GAMS leaves them. maindrv.mod L23 includes setglobs.gms
after the data is read, and its L11 removes REG_FIXT unless FIXBOH is set;
so without FIXBOH, L46 is not compiled (MY_FYEAR stays 0) and every statement
on REG_FIXT does nothing. `stp_init!` empties REG_FIXT and refuses FIXBOH,
STAGES, SPINES, SENSIS, CLI (and UC_CLI data) and TM_HSX with the usual
message.

How it was checked. In GAMS's order, from the `ppm` dump with TIMES.jl's own
state up to solve.stp: `stp_init!`; then for each step `stp_step_prep!`,
`pp_clean!` (solve.mod L12 runs inside the step), every set and parameter
against `steps/<k>/final` at 1e-9, GAMS's levels and marginals of that step
loaded, `stp_next!`.

- demo12_step, REDUCE off and as run: 957 symbols in each of the three steps,
  none differs. The steps are 2005-2020, 2020-2030 and 2050, with MIYR_VL
  2025, 2040 and 2052; after the third, SUBT is empty and the loop ends.
- Not compared: Z (err_stat.mod L56-65 sets it after the SOLVE) and the
  harness's own TJL symbols.
- After the loop the state equals the `presolve` dump on 832 of its 833 sets
  and parameters. PAR_CUMFLOM differs (9 records against none) and should:
  that dump's run makes no solve, so its marginals are all zero, while the
  check loads the solved points.
- CI: `test/unit/test_solve_stp.jl` (44 tests) on three step fixtures,
  `test/fixtures/demo12_step_step<k>` (about 1 MB in all, CC BY 4.0). A step
  fixture holds the sets and parameters that differ from the `equ` fixture,
  the variables the point store reads, and the list of the symbols equal to
  the `equ` fixture's, which the test compares with that fixture; so every
  set and parameter of each step is compared. They are made by
  `scripts/make_step_fixture.jl`.

Translated as GAMS writes them, but not reached by demo12_step, so **not
checked against GAMS** at the time of change 2 (demo12_step2 reaches most
of them since: "Change 5 as built"):

| Branch | Lines of solve.stp |
| --- | --- |
| G_OVERLAP given by the user (a self-check only: with 5, the second step starts at 2030) | 44, 305 |
| STP_DIV (ALTOBJ > 1) | 104-107 |
| CAP_BND copied, relaxed and bounded again | 69, 96, 190-191, 319 |
| user constraints summed over periods or over regions, and the dynamic ones (UC_T_SUM, UC_R_SUM, UC_T_SUCC, UC_DYNBND) | 132-151, 157, 176-179 |
| the UC_BND rows of UC_RHS, UC_RHSR, UC_RHST and UC_RHSTS (demo12_step has UC_RHSRT and UC_RHSRTS) | 155-175 |
| PRC_DYNUC | 76, 183-185 |
| REG_CUMCST | 196 |
| RVPRL (no retirement data) | 128 |
| COM_CUM in the bnd_cum.mod call of each step | 222-227 |
| COR_SALVD and SALV_DEC records a step does not assign keep the step before's value (eqobsalv.mod STP) | 127 |

Not translated, refused or flagged: the LINFLO block of coef_alt.lin STP
(L137-157; refused, change 6); the start from a given solution (L61-66);
the REG_FIXT statements (L186-189, L223, L315-317; FIXBOH refused); CM_MAXC
(L149; CLI refused).

## Change 3 as built (15 Nov 2026)

**The equations of a step.** maindrv.mod L38-40 sets the macros `%R_T%`,
`%TX%` and `%R_V_T%` to `R,SUBT(T)`, `SUBT(T)` and `R,V,SUBT(T)` in a stepped
run, so an equation written with one of them is generated for the periods of
the step only. `eq_periods(tm)` (src/coef/coef_alt.jl) is that set: SUBT in a
stepped run, every period otherwise. It replaces the period test of the
control index, and only that one (a sum inside an equation that runs over T
keeps every period), in:

- `src/model/`: eqactbnd, eqactflo, eqblnd, eqbndcom, eqcapact, eqcapvac,
  eqcombal, eqflobnd, eqflofr, eqflomrk, eqfloshr, eqire, eqirebnd, eqpeak,
  eqptrans, eqstgaux, eqstgflo, eqstgips, eqstgtss, equserco (EQE_UCRT,
  EQE_UCRTS, EQE_UCRS), eqxbnd, and three bound statements of bndmain
  (bnd_act.mod L22, bndmain.mod L46, L57-58);
- `src/ext/vda/`: equcrtp, eqactups, eqlducs, eqashar, eqcaflac, pp_actef,
  eqslsift, powerflo; `src/ext/dsc/prepret.jl`.

The objective, EQ(l)_CPT and the cumulative equations are not written with
these macros: they are cut to the step by the sets `stp_step_prep!` changes
(the vintages V without the pending periods, L115; RTP_VARP; the horizon that
ends at MIYR_VL). The maps of the user constraints' right-hand sides
(UC_RHSMAP, UC_UT, UC_UTS) are built once by eqmain.mod, before solve.stp;
the model of a step reads the stored ones and UC_RTSUC as L195 sets it
(`uc_setup`).

**The bounds of a step** (`src/model/bnd_stp.jl`; GAMS lines of solve.stp
unless a file is named). In GAMS a bound is an attribute of the variable and
lives through the whole run. bndmain.mod's second call (after each SOLVE)
resets VAR_ACT, VAR_FLO, VAR_SIN and VAR_SOUT of storage processes,
VAR_NCAP, VAR_CAP, VAR_COMNET, VAR_COMPRD and part of the user constraints'
slacks before it reads the data again; VAR_IRE, VAR_UPS, VAR_UPT, VAR_UDP,
VAR_SCAP, VAR_BLND, VAR_CUMFLO, VAR_CUMCOM, VAR_CUMCST and VAR_OBJ keep what
a step gave them. So TIMES.jl keeps one bound table for the run and applies
GAMS's statements to it in GAMS's order:

| Function | GAMS | What |
| --- | --- | --- |
| `stp_bounds_init!` (from `stp_init!`) | maindrv.mod L92; bndmain.mod with 0 | the table of an ordinary run (SUBT is every period then, ppmain.mod L253) |
| `stp_step_bounds!` (from `stp_step_prep!`) | L193; L199-233; L267-281 | bnd_ucw.mod with the resets of bnd_ucv.mod L24-25; the periods already solved fixed at the levels of the point store (VAR_ACT, VAR_FLO, VAR_SIN, VAR_SOUT, VAR_IRE, VAR_UPS, VAR_UPT, VAR_UDP, VAR_COMNET, VAR_COMPRD, VAR_NCAP, VAR_SCAP, VAR_BLND), their VAR_CAP freed (CAP_BND for NO_RVP); bnd_cum.mod and the lower bounds of VAR_CUMFLO and VAR_CUMCOM it relaxes (L229-230); the pending periods fixed at zero (VAR_ACT, VAR_FLO, VAR_SIN, VAR_SOUT, VAR_COMNET, VAR_COMPRD, VAR_BLND), their VAR_CAP bounded by CAP_BND |
| `stp_bndmain!` (from `stp_next!`) | L319; bndmain.mod with 1 | the families above reset and taken from the data again, for the periods of the next step where the statement has `%R_T%` |
| `stp_model` | the model the SOLVE of a step gets | the model of one step: a new JuMP model on the run's data, bound table and point store; `generate!` builds it |
| `bnd_ucw!(...; reset=true)` (src/model/bndmain.jl) | bnd_ucv.mod L24-25 | the upper bound of every slack to INF; the lower bound to -INF where the macro's condition holds (all of VAR_UC, VAR_UCT, VAR_UCTS; VAR_UCR under UC_R_EACH; VAR_UCRT and VAR_UCRTS under UC_T_EACH) |

The point store now also keeps the levels these fixes read (VAR_ACT, VAR_FLO,
VAR_IRE, VAR_SIN, VAR_SOUT, VAR_UPS, VAR_UPT, VAR_UDP, VAR_COMNET,
VAR_COMPRD, VAR_SCAP, VAR_BLND).

Two readings the check confirms:

- V is a control index of the fixes over RTP_VINTYR and RTP_CPTYR, and L115
  takes the pending periods out of V. So the fixes of the pending periods at
  zero (L268-272) reach what an earlier vintage does there, not a pending
  vintage's own variables: `VAR_ACT(REG1,2030,2030,EXPLPG1,ANNUAL)` keeps its
  bound from the data in step 1, in GAMS's LP and in TIMES.jl's.
- L270 is a comment in v4.9.7: the trade of a pending period is not fixed.

How it was checked. For each step, in GAMS's order: `stp_step_prep!`,
`stp_model`, `generate!`, then the LP against `steps/<k>/matrix` (the model
GAMS solved in that step, written by CONVERT) at 1e-9: rows, columns,
coefficients, right-hand sides and bounds; then GAMS's levels and marginals
of the step loaded and `stp_next!`.

| Step | REDUCE off: rows / columns / nonzeros, GAMS and TIMES.jl | as run | Layer 2 |
| --- | --- | --- | --- |
| 1 | 5,921 / 6,717 / 20,736 | 2,201 / 3,183 / 12,216 | PASS, PASS |
| 2 | 2,975 / 4,421 / 12,438 | 1,133 / 2,305 / 7,782 | PASS, PASS |
| 3 | 1,380 / 3,179 / 6,930 | 540 / 1,949 / 4,756 | PASS, PASS |

- Negative control: the same check without GAMS's levels loaded between the
  steps passes step 1 and fails steps 2 and 3 on 409 and 584 column bounds
  (as run), so the comparison does test the fixes.
- In the run with REDUCE the trade flows that carry a level are replaced by
  the activity, and every level of VAR_IRE GAMS writes is zero (560, 958 and
  1,270 records); the reference without REDUCE has 179, 216 and 251 nonzero
  levels of VAR_IRE and fixes at them, and its LPs are equal too.
- CI: `test/unit/test_solve_stp.jl` (104 tests) compares the LP of each step
  with three more fixtures, `test/fixtures/demo12_step_step<k>_matrix` (the
  CONVERT matrix and its dictionary, about 1.3 MB in all, CC BY 4.0), and
  tests the bound table between the steps; the step fixtures now hold the
  levels of the variables added to the point store (about 1.4 MB in all).
  Both are made by `scripts/make_step_fixture.jl`.
- Every model that is not stepped: `eq_periods` is every period there and
  `bnd_ucw!` does not reset, so no statement changes; the whole test suite
  passes (34,780 of 34,780 tests), with layer 2 on every fixture.

Families the three LPs hold: EQE_ACTEFF, EQ(l)_COMBAL, EQE_COMPRD, EQE_CPT,
EQ(l)_INSHR, EQ(l)_OUTSHR, EQE_UCRT, EQE_UCRTS, EQL_ACTBND, EQL_CAPACT,
EQ_ACTFLO, EQ_CUMFLO, EQ_IRE, EQ_OBJ and its parts, EQ_PEAK, EQ_PTRANS;
VAR_ACT, VAR_CAP, VAR_COMNET, VAR_COMPRD, VAR_CUMFLO, VAR_FLO, VAR_IRE,
VAR_NCAP, VAR_OBJ, VAR_UCRT, VAR_UCRTS.

Translated as GAMS writes them, but not reached by demo12_step, so **not
checked against GAMS** at the time of change 3 (demo12_step2 reaches the
CAP_BND, VAR_CUMCOM and slack rows since, "Change 5 as built"; the others
wait for the feature's own stepped case):

| Branch | Lines of solve.stp |
| --- | --- |
| the fixes of storage flows (VAR_SIN, VAR_SOUT) | 203-204, 271-272 |
| the fixes of VAR_UPS, VAR_UPT, VAR_UDP (dispatching, unit commitment) | 205-207 |
| VAR_SCAP (early retirement) | 220 |
| CAP_BND on VAR_CAP (NO_RVP; the pending periods) | 218-219, 279 |
| VAR_CUMCOM (COM_CUM) | 227, 230 |
| blending: VAR_BLND levels and fixes | 232-233, 281 |
| the resets of the slacks VAR_UC, VAR_UCR, VAR_UCT, VAR_UCTS (bnd_ucv.mod L24-25; a unit test on a made-up table only) | 193 |
| EQE_UCRS, and the period test of the equation families demo12_step has no row of: storage (EQ_STGAUX, EQ_STGFLO, EQ_STGIPS, EQ_STGTSS), EQ(l)_FLOBND, EQ(l)_FLOFR, EQ(l)_FLOMRK, EQ(l)_BLND, EQ(l)_BNDNET/BNDPRD, EQ(l)_CAPVAC, EQ(l)_IREBND, EQ(l)_XBND, the VDA families (EQ(l)_ASHAR, EQ(l)_CAFLAC, EQ_ACTUPS and the unit commitment, EQ_SLSIFT, the grid) and early retirement | maindrv.mod L38-40 |

Not translated: VAR_ELAST (L211, L276; elastic demand is refused) and VAR_DAM
(L212; damage is refused); the REG_FIXT loops (L199, L234, L266, L282) and
L236-264 (FIXBOH refused); the %SOW% forms (STAGES refused).

One statement to flag: **L281 fixes the blending variables of the pending
periods at zero, and no statement in v4.9.7 lifts that fix** (the only
statements on a bound or level of VAR_BLND outside the reports and the
restart files are L232, L233 and L281; bndmain.mod does not touch VAR_BLND).
So in a stepped run with blending, VAR_BLND would stay fixed at zero when a
pending period becomes a step's own. Translated as written; no open model
has blending in a stepped run, so it is not checked against GAMS
(docs/discrepancies.md, U7). Checked since on demo12_step3: GAMS does keep
the fix (D43; "Change 7 as built", below).

The run as a whole is still refused: `untranslated_families` notes
"(stepped run)" for the run's model, not for the model of a step, until the
loop with the SOLVE (change 4).

## Change 4 as built (15 Nov 2026)

**The loop.** `solve_stepped!(tm, optimizer)` (src/model/solve_stp.jl) solves
a stepped run to its end. `tm` is the run in the state an ordinary run is in
when its model is generated, less `pp_clean!` (solve.mod L12 runs it inside
each step). In GAMS's order (lines of solve.stp unless a file is named):

| # | TIMES.jl | GAMS |
| --- | --- | --- |
| before | `stp_init!` | L9-107 |
| 1 | `stp_step_prep!`: the periods, the data and the bounds of the step | L111-282, L288-289 |
| 2 | `pp_clean!` | solve.mod L12 |
| 3 | `stp_model`, `generate!`: the model of the step, built anew | the model the SOLVE generates (solve.mod L37) |
| 4 | the solve; a step that does not end optimal stops the run with GAMS's message, `*** ERRORS DURING SOLUTION ***` | L291-294; solve.mod L37, L41; err_stat.mod L63-69 |
| 5 | `stp_merge_point!`: the levels and reduced costs of the step's variables into the point of the run; every other variable keeps what the earlier steps left | L286, `OPTION SOLVEOPT=MERGE` |
| 6 | `stp_next!`: the next step's periods, the saved data restored, the bounds set again | L295-319 |
| after | `stp_finish!`: the EPS levels of VAR_NCAP removed; the marginals of VAR_NCAP, VAR_ACT, VAR_FLO and VAR_IRE of the periods before the last step set to zero | L325-329 |

The loop runs while a period is left (L109). It returns one record per step
(the periods, rows, columns, objective, status, and the seconds to prepare,
generate and solve), also kept in `tm.cache["STP_STEPS"]`. The solver is an
argument, as everywhere in `src/`; a `step_hook` is called after each step
with the solved model, which is how the checks below look into a step and
load GAMS's point for the next one.

**The refusals removed.** `untranslated_families` no longer lists a stepped
run. `generate!` on the run as a whole stops with a message that names
`solve_stepped!` (a stepped run has no single model). What a stepped run
still cannot have is listed by `stp_unported` and refused before the first
step: FIXBOH, STAGES, SPINES, SENSIS, the climate extension (CLI), TM_HSX,
and OBJ ALT or LIN (the divisors of coef_alt.lin L137-157, change 6).

**The scripts.** `scripts/run_dd.jl --solve` solves a stepped run from its DD
files step by step, one line per step (its solution is not written to
`solution/` yet: M1.6). `scripts/m13_gate.jl` runs a stepped case to the end
(below). `scripts/m11_probe.jl`, `scripts/parity_report.jl` and the cuOpt
lane compare one LP per run, so they record a stepped run as skipped, with
the reason, instead of refused.

**How it was checked** (`scripts/m13_gate.jl` on TIMES_Demo-demo12_step, both
variants, from GAMS's input dump and from the DD files; HiGHS, 12 threads).
The run is solved twice.

First with GAMS's levels and marginals loaded after each step, so that a
difference in one step cannot hide in the next:

| Step | Layer 1 (957 sets and parameters after the SOLVE; 832 from the DD files) | Layer 2 (the LP against CONVERT's) | Objective, HiGHS here against GAMS/CPLEX | Relative difference |
| --- | --- | --- | --- | --- |
| 1 | PASS | PASS | 12,397,965.9863 | 2.9e-12 |
| 2 | PASS | PASS | 20,325,417.7629 | 1.0e-12 |
| 3 | PASS | PASS | 23,960,685.7370 | 3.2e-13 |

Each optimum is also evaluated in the other side's LP of the step: GAMS's
point in TIMES.jl's LP gives GAMS's objective, with a largest row violation
of 7.6e-8 (REDUCE off) and 1.1e-7 (as run) in step 1 and under 4e-9 after
(the same point is as feasible in GAMS's own LP); HiGHS's point in GAMS's LP
is feasible to 3.7e-9.

Then on TIMES.jl's own levels, the run as a user makes it: the objective of
each step equals GAMS/CPLEX's (2.9e-12, 1.0e-12, 3.3e-13), and the last
equals the final objective of GAMS/HiGHS (23,960,685.737). Both passes give
three steps, as GAMS does.

- CI: `test/unit/test_solve_stp.jl` (181 tests) runs `solve_stepped!` on the
  demo12_step fixtures both ways: layer 2 per step, HiGHS's optimum feasible
  in GAMS's LP and the objective per step against GAMS/CPLEX's on GAMS's
  levels; the objective per step and the final objectives of GAMS/CPLEX and
  GAMS/HiGHS on its own levels. The step fixtures' manifests now hold GAMS's
  objective of each step (`tjl_step_solve`) and the final objectives. GAMS's
  optimum evaluated in TIMES.jl's LP is checked by the gate script, not in CI.
- The whole test suite passes (34,857 tests).

**Flagged.**

- **More than one optimum.** On its own levels the LPs of steps 2 and 3 are
  not GAMS's: HiGHS and CPLEX end step 1 at different optima with the same
  objective, so the periods already solved are fixed at different levels
  (several hundred column bounds differ). On demo12_step the objectives of
  the later steps still agree to 1e-12. That is not guaranteed for every
  model: in a myopic run a later step depends on which optimum an earlier
  step took, and two solvers (or one solver with other settings) can then
  give different later objectives, in GAMS as well. The pass on GAMS's levels
  is the check that does not depend on this.
- **A step must end optimal.** GAMS also goes on after a step with model
  status 2, 7 or 8 (locally optimal, feasible, integer solution; the latter
  need a nonlinear or discrete model) and, under `ERR_ABORT=NO`, after any
  status (err_stat.mod L65). Here a step that is not optimal stops the run.
- **EPS marginals.** GAMS returns EPS as the marginal of a nonbasic variable
  whose reduced cost is zero; here it is zero (no record). No statement that
  prepares a later step's model reads a marginal; PAR_CUMFLOM and PAR_UCR
  (L288-289) can differ in such a record on TIMES.jl's own levels.
- **Equations.** The levels and marginals of the equations of a step are not
  kept: the loop does not read them. The reports of a stepped run need them
  (M1.6).
- **Solver settings not reproduced**: the advanced basis between the steps
  (`BRATIO=1`, L285), the solver option file and PRIOROPT (solve.mod
  L14-15), TOLPROJ (L18). None changes an LP or its optimum value.
- **Not translated**: L330 (MY_FYEAR, for FIXBOH).
- **Not checked against GAMS**: every branch demo12_step does not reach
  (the lists under changes 2 and 3, and below), now also on TIMES.jl's own
  levels; `stp_finish!` on VAR_FLO and VAR_IRE marginals is tested on a
  made-up point as well as on demo12_step.

## Change 5 as built (15 Nov 2026)

A second crafted case, **demo12_step2** (`reference/dd/demo12_step2/`), for
the branches of solve.stp that demo12_step does not reach. It is demo12 with
TIMESTEP 20 and G_OVERLAP 15, the DD files of three other crafted cases
(`ucdyn.dd`, dynamic user constraints; `ucrt.dd`, UC_DYNBND; `cumc.dd`,
cumulative commodity and flow bounds) and `step2.dd`: CAP_BND UP, LO and FX;
a user constraint summed over the periods (UC_T_SUM) for one region and one
summed over the regions as well; a user constraint summed over the regions
with a negative coefficient, each period; REG_CUMCST.

GAMS 54.6.1 solves three steps, and the second and the third solve periods
again:

| Step | Periods solved (SUBT) | Fixed (BACKWARD) | MIYR_VL |
| --- | --- | --- | --- |
| 1 | 2005, 2010, 2015, 2020 | none | 2025 |
| 2 | 2015, 2020, 2030 | 2005, 2010 | 2040 |
| 3 | 2030, 2050 | 2005, 2010, 2015, 2020 | 2052 |

**One statement corrected** (`src/model/bndmain.jl`, `bnd_cum_flo` and
`bnd_cum_com`). bnd_cum.mod is included before the loop and again in every
step (solve.stp L227), and it is not idempotent: the second pass reads the
modifier the first pass left as the row number of MULTI, and the lead
`J+(N-1)` is then -1.2. TIMES.jl stopped there ("not an integer lead");
GAMS rounds the lead (G29), finds no element and sets no modifier. The lead
is now `glead(n - 1)`, as GAMS has it, also in a run that is not stepped.
The effect in GAMS, followed here: from its first step on, a stepped run
applies a cumulative bound to EOH without the modifier of the flexible
horizon (docs/discrepancies.md, D41).

**The harness, 0.3.5.** GAMS writes "N projected" after the number of single
variables in MODEL STATISTICS when it moved N starting levels onto their
bounds; in a stepped run the levels of an earlier step can lie outside a
relaxed bound by a rounding. `parse_solves` reads the line with or without
it (it took such a step for one without statistics, and the reference ended
with CHECK). References made with 0.3.4 stay valid.

**The gate script.** The pre-solve dump of a stepped run is the state after
the last step, so `scripts/m13_gate.jl` leaves the symbols the loop assigns
out of the pre-solve checkpoint and compares them after each step instead
(`steps/<k>/final`). demo12_step2 reaches 19 more of them (46 in all):
CAP_BND, the six UC_RHS tables, PRC_DYNUC, RTP_VARP, RXX, UC_T_SUM, UC_T,
UC_T_EACH, UC_T_SUCC, UC_RTSUC, REG_CUMCST, COM_CUM, FLO_CUM, RC_CUMCOM.

**Checked** with `scripts/m13_gate.jl`, both variants, from GAMS's input
dump and from the DD files (four runs, all PASS; HiGHS with 12 threads).
The chain to the pre-solve state passes (833 symbols at each checkpoint,
959 at coef, 787 at presolve). Then the stepped run, first with GAMS's
levels loaded after each step:

| Step | Layer 1 | Layer 2: rows, columns, nonzeros (REDUCE off; as run) | Objective, GAMS/CPLEX | TIMES.jl with HiGHS on its own levels, relative difference |
| --- | --- | --- | --- | --- |
| 1 | PASS, 957 symbols | PASS: 6,019, 6,813, 21,560; 2,299, 3,279, 13,040 | 42,561,995.5428 | 1.6e-13 |
| 2 | PASS, 957 symbols | PASS: 4,630, 5,960, 18,508; 1,800, 2,916, 11,458 | 77,180,290.0509 | 8.0e-14 |
| 3 | PASS, 957 symbols | PASS: 2,893, 4,637, 12,860; 1,149, 2,523, 8,348 | 80,873,281.9743 | 2.0e-13 |

Each optimum is evaluated in the other side's LP at every step: GAMS's
point in TIMES.jl's LP (largest row violation 1.1e-7 in step 1, under
3e-8 after; it gives GAMS's objective) and HiGHS's point in GAMS's LP
(under 2e-8). On TIMES.jl's own levels the
last objective equals the final objective of GAMS/HiGHS
(80,873,281.97428). From the DD files layer 1 compares 832 symbols per
step.

**What the case reaches** (records in GAMS's dumps of steps 1, 2, 3, as
run; TIMES.jl equal in each):

| Branch | Lines of solve.stp | In demo12_step2 |
| --- | --- | --- |
| G_OVERLAP given | 44, 305 | 15: steps 2 and 3 solve the periods of the overlap again |
| CAP_BND: FX copied to LO and UP, RTP_VARP, the capacity levels | 69, 96-98 | 13 records, RTP_VARP 45 |
| CAP_BND relaxed after each step | 190-191 | UP = MAX(bound, level × (1 + 3e-6)): 50 → 50.00015 where the level sits on the bound, unchanged where it is below; LO × (1 - 3e-6) in every step: 2 → 1.999994 → 1.999988 |
| CAP_BND on the capacity of fixed and of pending periods | 217-219, 279 | NO_RVP 0, 10, 9, with 7 and 5 UP or LO records of CAP_BND on them; UP in the pending periods of step 1 |
| a user constraint summed over the periods | 132-137 | UC_T_SUM 20, 25, 30 |
| dynamic user constraints | 140-151 | UC_T_EACH 24, 18, 12; UC_T_SUCC and UC_RTSUC 78, 61, 44; UC_DYNBND 5 |
| the growth coefficients relaxed | 76, 183-185 | PRC_DYNUC 44 records, 13 relaxed between the steps (UP × (1 + 3e-6), LO × (1 - 1e-5)) |
| user constraints summed over the regions; all six kinds of right-hand side in UC_BND | 141-144, 155-175 | UC_BND 0, 66, 66 (kinds 1 to 6: 1, 3, 18, 6, 26, 12); the absolute tolerance of a constraint with a negative coefficient (UC_RN) |
| the right-hand side copied back | 176 | UC_RHS: 90 → 90.00027 → 90.00054 |
| REG_CUMCST: the upper bound of a range that ends in a fixed period removed | 196 | 5, 5, 3 records |
| COM_CUM and FLO_CUM through bnd_cum.mod in every step; VAR_CUMCOM | 222-230 | COM_CUM 7, FLO_CUM 22; levels of VAR_CUMCOM 5, VAR_CUMFLO 21, VAR_CUMCST 4 |
| the slacks of user constraints reset | 193 (bnd_ucv.mod L24-25) | VAR_UC, VAR_UCR, VAR_UCT, VAR_UCTS are columns of the LPs |

Families its LPs hold beyond demo12_step's: EQE_UC, EQE_UCR, EQE_UCT,
EQE_UCSU, EQE_UCSUS, EQE_UCRSU, EQE_UCRSUS, EQN_UCRTC, EQN_UCRTP, EQ_BNDCST,
EQ_CUMNET, EQ_CUMPRD; VAR_UC, VAR_UCR, VAR_UCT, VAR_UCTS, VAR_CUMCOM,
VAR_CUMCST.

**CI.** Fixtures of the case (about 10 MB: input, ppm, equ, the run file,
and a data and a matrix fixture per step) and `test/unit/test_solve_stp2.jl`
(90 tests): the chain from ppm to equ, each step's partition and layer 1,
the reach figures of the table above, layer 2 per step, and `solve_stepped!`
to the end on GAMS's levels and on its own (HiGHS). `test_ddsource.jl`
compiles the case from its DD files; `test_bnd_cum.jl` has the second and
the third pass of bnd_cum.mod.

**Flagged.**
- A CAP_BND upper bound below the capacity still standing makes the first
  step infeasible, as it makes a run that is not stepped (seen while the
  case was written; the case keeps its bounds above the standing capacity).
- **D41**: a stepped run loses the modifier of a cumulative bound to EOH
  (above). Followed as GAMS runs; a report to ETSAP needs James's yes.
- **Still not reached by an open stepped case**, translated as written:
  the copy-back of L177 and L180-181 (regions in REG_FIXT only) and of
  L178-179 (UC_T after L157: a user constraint summed over the regions
  that has a UC_CAP coefficient; demo12_step2's have UC_NCAP, so UC_T is
  empty and UC_RHST and UC_RHSTS keep their data values); L186-189
  (REG_FIXT); the fixes of storage flows (L203-204, L271-272), of VAR_UPS,
  VAR_UPT, VAR_UDP (L205-207) and VAR_SCAP (L220); RVPRL (L128); blending
  (L232-233, L281; U7); EQE_UCRS.
- **OBJ ALT or LIN in a stepped run stays refused.** The plan had it in
  this change; it is a file of its own (coef_alt.lin L137-157) with a case
  of its own, so it is change 6 (demo12_steplin). The stepped variants of
  the blending and the unit commitment cases are change 7.

## Change 6 as built (15 Nov 2026)

A stepped run with OBJ LIN or OBJ ALT: the divisors of the investment,
fixed and decommissioning costs are corrected in every step for the period
that the end of the step's horizon cuts (coef_alt.lin L137-157, under
LINFLO). Until this change such a run was refused.

**GAMS source** (v4.9.7 @ `d9a6a25`):
- solve.stp L104-107: before the loop, when ALTOBJ > 1, the divisors
  OBJ_DIVI, OBJ_DIVIV and OBJ_DIVIII are saved in STP_DIV, over the
  milestone years only (T). Translated in change 2 (`stp_init!`), checked
  now.
- solve.stp L124 with coef_alt.lin L137-157 (`coef_alt_stp!` in
  `src/coef/coef_alt.jl`, called by `stp_step_prep!`): RTP_CAPVL, the
  relative change of a capacity's discounted availability in the last
  period of the step (L139-146); without OBLONG, combined with the
  correction for trapezoidal periods (L150-153; L148 skips it with OBLONG);
  then each divisor of a milestone year is the saved one times 1+RTP_CAPVL
  (L155-157, over RTP: the divisors of past years keep their values).
- initmty.mod L421-423 and L432 (`init_altobj` in `src/dd/compile.jl`): the
  statements that set the scalar ALTOBJ from the OBJ and OBLONG controls
  (STD 0, ALT 2, LIN 3, OBLONG with ALT -2; 1 otherwise, L420). The DD
  reader stopped at them, so no run with OBJ STD, ALT or LIN could start
  from DD files.

**The cases** (`reference/dd/`, `reference/crafted.toml`). All five are the
run file of demo12_objinv (demo12 with decommissioning costs, a short-lived
plant and a lead time, so all three divisors have records) with other
controls:

| Case | Controls | What it checks | Where |
| --- | --- | --- | --- |
| demo12_steplin | OBJ LIN, TIMESTEP 20 | L137-157 without OBLONG, three steps | fixtures, CI; the gate script |
| demo12_steplino | OBJ LIN, OBLONG YES, TIMESTEP 20 | the OBLONG branch (L148), three steps | the gate script |
| demo12_stepalt1 | OBJ ALT, TIMESTEP 60 | OBJ ALT in a stepped run of one step | the gate script |
| demo12_lin | OBJ LIN | the base that is not stepped; initmty.mod L423 from DD files | the gate script, `scripts/m11_probe.jl` |
| demo12_alt | OBJ ALT | the base that is not stepped; initmty.mod L422 from DD files | the gate script, `scripts/m11_probe.jl` |

**demo12_steplin** (GAMS 54.6.1; the default overlap, half of TIMESTEP:
step 2 solves 2020 again):

| Step | Periods solved (SUBT) | Fixed (BACKWARD) | MIYR_VL | LP as run (rows, columns, nonzeros) | LP with REDUCE off | Objective, GAMS/CPLEX | TIMES.jl with HiGHS, own levels: relative difference |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 2005, 2010, 2015, 2020 | none | 2025 | 2,201, 3,215, 12,253 | 5,921, 6,749, 20,871 | 12,226,884.0052 | 7.1e-13 |
| 2 | 2020, 2030 | 2005, 2010, 2015 | 2040 | 1,133, 2,339, 7,808 | 2,975, 4,535, 12,562 | 20,271,827.2496 | 1.8e-12 |
| 3 | 2050 | 2005 to 2030 | 2052 | 540, 1,959, 4,808 | 1,380, 3,189, 6,982 | 24,230,172.1369 | 2.0e-13 |

What the steps reach (records in GAMS's dump of each step, as run):

| Symbol | Step 1 | Step 2 | Step 3 |
| --- | --- | --- | --- |
| RTP_CAPVL | 396 | 498 | 586 |
| of them positive (the divisor is raised) | 1 | 1 | 1 |
| OBJ_DIVI that differ from the saved value (of 458) | 269 | 359 | 447 |
| STP_DIV (458 + 346 + 18 divisor records, less 42 of past years) | 780 | 780 | 780 |

With OBLONG (demo12_steplino) the steps have 147, 241 and 191 records of
RTP_CAPVL. In its last step all 191 are below 3e-10 in size: the
availability over the step's horizon and the period's own cancel but for
rounding, so the values are what GAMS's rounding of `**` leaves (below).

**Parity.** `scripts/m13_gate.jl` on the five cases, both variants, from
GAMS's input dump and from the DD files: all pass. For the three stepped
cases: the chain to the pre-solve state; with GAMS's levels between the
steps, layer 1 per step (958 sets and parameters; 957 for demo12_stepalt1),
layer 2 per step with GAMS's sizes, each optimum evaluated in the other
side's LP; on TIMES.jl's own levels, the objective of each step against
GAMS/CPLEX's and the last against GAMS/HiGHS's. demo12_steplino:
12,226,966.9684, 20,271,871.1782 and 24,230,247.8344 (relative differences
3.6e-12, 1.5e-12, 1.3e-12). demo12_stepalt1: 24,230,694.1056 (1.2e-13).
demo12_lin and demo12_alt: layers 1 and 2 and the solve (8,695 rows with
REDUCE off, 3,233 as run; objectives 24,229,859.0038 and 24,230,694.1049,
equal to GAMS/CPLEX's and GAMS/HiGHS's).

**GAMS's rounding of powers (G61).** RTP_CAPVL is a difference of terms
`1 - f**n` that nearly cancel, so the last bits of `**` show in it: with
Julia's `^` (the correctly rounded power) values of the order 1e-10
differed from GAMS's beyond 1e-9 relative. Probed on GAMS 54.6.1: `x**y`
is `exp(y*log(x))`, and `POWER(x,n)` is the product by repeated squaring
(`1/x/x` for n = -2). `gpow` and `gpower` (`src/model/gams_data.jl`) now
compute them so. This is shared code: every other fixture and reference
case stays within the tolerances (the full suite; the generated LPs are
unchanged at 1e-9).

**OBJ ALT in a stepped run of several steps fails in GAMS itself (D42).**
coef_alt.lin L51 (L52 with OBLONG) divides COEF_PVT of every period by a
sum over the years of the step's horizon; for a period beyond the horizon
the sum is empty. GAMS 54.6.1 reports "division by zero", skips the solve
of the step, clears the error (err_stat.mod L70) and goes on: on the run
file of demo12_objinv with OBJ ALT and TIMESTEP 20 it skips steps 1 and 2,
solves step 3 alone (objective 4,647,225.0032) and ends with "Normal
completion"; with OBLONG YES as well it skips step 1 and solves steps 2
and 3. TIMES.jl stops at the first such step with a
`DomainError` that names the line. With one step over the whole horizon
(demo12_stepalt1) no sum is empty and the run is as GAMS's.

**CI.** Fixtures of demo12_steplin (about 9.6 MB: input, ppm, equ, the run
file, a data and a matrix fixture per step) and
`test/unit/test_solve_stplin.jl` (91 tests): the chain from ppm to equ,
STP_DIV as saved, each step's partition, layer 1, the record counts and
values above, L155-157 as a relation between the symbols, layer 2 per step,
`solve_stepped!` to the end on GAMS's levels and on its own (HiGHS), and
the `DomainError` of a stepped OBJ ALT. `test_ddsource.jl` compiles the
case from its DD files and checks ALTOBJ for each setting of OBJ and
OBLONG; `test_gnum.jl` has GAMS's values of `**` and POWER where Julia's
`^` differs.

**Flagged.**
- **D42** (above): TIMES.jl stops where GAMS skips a step and goes on. A
  report to ETSAP needs James's yes.
- **initmty.mod L421 (OBJ STD) and L432 (OBLONG with OBJ ALT)** are
  translated as written and checked against the source's `$IFI` lines
  only: no reference run starts from DD files with them. L424 (MACRO) and
  L425 (VALIDATE) stay refused.
- **Checked on the workstation only** (no fixture): demo12_steplino,
  demo12_stepalt1, demo12_lin, demo12_alt.
- **Not checked under OBJ LIN by these five cases**: the weights of
  EQ_CUMFLO, EQ_CUMNET and EQ_CUMPRD (eqcumflo.mod L21, L24, L35;
  eqcumcom.mod L20, L23; the cases have no cumulative bound) and EQ_STGIPS
  (eqstgips.lin, still refused). The first is settled by the crafted case
  demo12_cumlin (15 Nov 2026, below).

**After change 6: the cumulative equations under OBJ LIN (15 Nov 2026).**
demo12_cumlin is the run file of demo12_cumc with OBJ LIN. With OBJ LIN a
period counts in a year range when M(T)+LAGT(T) is after its first year and
M(T)-LEAD(T) before its last, and its weight is the sum of its TPULSE over
the years of the range, where the standard objective counts the years of
the period in the range. In GAMS's LPs of the two cases the cumulative rows
have the same columns, and 46 of the 152 coefficients differ as run (50 of
164 with REDUCE off): for the range 2010-2200 the periods 2020, 2030 and
2050 weigh 7.5, 15 and 12.5 under OBJ LIN against 8, 15 and 12 years.
Nothing was to correct: layers 1 to 3 pass on both variants, from GAMS's
input dump and from the DD files (`scripts/m13_gate.jl`,
`scripts/m11_probe.jl`; 8,721 rows with REDUCE off, 3,259 as run; objective
24,241,216.775, equal to GAMS/CPLEX's and GAMS/HiGHS's). In CI,
`test/unit/test_cum_lin.jl` builds the rows from the pre-solve fixture of
demo12_cumc with the switch OBJ set to LIN and compares them with GAMS's
rows of demo12_cumlin (`test/fixtures/demo12_cumlin_cumrows.json`, 18 KB,
written by `scripts/make_rows_fixture.jl`). Not reached: the exchange
branch of EQ_CUMFLO (L29-30; the same weight).

## Change 7 as built (15 Nov 2026)

The third crafted stepped case, **demo12_step3** (`reference/dd/`,
`reference/crafted.toml`): demo12 with TIMESTEP 20 and the default overlap
(three steps: 2005-2020; 2020 and 2030; 2050), the DD files of five other
crafted cases and one of its own. It brings the variables that demo12_step
and demo12_step2 do not have:

| DD file | What it adds | Statements of solve.stp |
| --- | --- | --- |
| `uc.dd` (demo12_uc) | dispatching and unit commitment: VAR_UPS, VAR_UPT, VAR_UDP | L205-207 |
| `blnd.dd` (demo12_blnd) | refinery blending: VAR_BLND | L232-233, L281 |
| `ips.dd` (demo12_ips), `ls.dd` (demo12_ls) | an inter-period store and load shifting: VAR_SIN, VAR_SOUT | L203-204, L271-272 |
| `refit.dd` (demo12_refit) | retirement and refits: VAR_RCAP, VAR_SCAP, RVPRL | L128, L220 |
| `step3.dd` (new) | FLO_COST and FLO_DELIV on the flows of the two storage processes | L203-204 |

`step3.dd` is there for one reason. A storage flow of a period already
solved is in no row of a later step unless it has a cost: the objective row
then holds VAR_SIN and VAR_SOUT of every period up to the step's horizon
(eqobjvar.mod L88-91). Without the costs GAMS fixes those columns (L203-204)
and CONVERT writes none of them, so the fix could not be compared.

**Nothing was to correct**: the translation of change 3 is unchanged.

Checked on the workstation, GAMS 54.6.1 with CPLEX and HiGHS, REDUCE off
and as run:

- `scripts/m13_gate.jl` from GAMS's input dump: 36 checks, all pass. From
  the DD files: 38 checks, all pass. Per step: layer 1 on every set and
  parameter of the step's dump (958 symbols), layer 2 against the LP GAMS
  solved, each optimum in the other LP, and the objective.
- The LPs, rows, columns and nonzeros per step, equal to GAMS's: 6,635,
  7,485, 23,813; 3,297, 5,003, 14,176; 1,513, 3,685, 7,850 with REDUCE
  off; 2,867, 3,927, 15,165; 1,415, 2,857, 9,424; 649, 2,435, 5,620 as run.
- The objectives of the three steps, GAMS/CPLEX: 12,331,414.7759,
  20,235,475.8098 and 23,870,710.7256. TIMES.jl with HiGHS on its own
  levels: relative differences 2.8e-13, 9.1e-13 and 3.8e-13; the last one
  also equals GAMS/HiGHS's.

**What the case reaches**, counted in the LP GAMS solved in each step (the
counts are the same with REDUCE off and as run). Each cell gives the
columns of the variable, those fixed at zero, and those fixed at another
value:

| Variable | Step 1 | Step 2 | Step 3 |
| --- | --- | --- | --- |
| VAR_UPS | 168; 0; 0 | 54; 11; 1 | 16; 15; 1 |
| VAR_UPT | 72; 0; 0 | 72; 54; 0 | 72; 72; 0 |
| VAR_UDP | 88; 0; 0 | 46; 24; 0 | 32; 32; 0 |
| VAR_SCAP | 27; 1; 0 | 30; 4; 4 | 31; 13; 8 |
| VAR_RCAP | 29; 1; 0 | 30; 1; 0 | 22; 2; 0 |
| VAR_SIN | 46; 0; 0 | 60; 33; 0 | 73; 60; 0 |
| VAR_SOUT | 78; 0; 0 | 76; 31; 2 | 81; 58; 2 |
| VAR_BLND | 36; 0; 0 | 36; 26; 1 | 39; 38; 1 |

The rows of the equation families the first two cases have none of, in
steps 1, 2 and 3: EQL_BLND 7, 4, 2; EQG_BLND 8, 6, 3; EQE_BLND 3, 2, 1;
EQ_STGIPS 16, 11, 5; EQ_STGAUX 14, 11, 5; EQ_SLSIFT 80, 40, 20; EQL_REFIT
12, 13, 5; EQ_CUMRET 17 in each; EQL_SCAP 6, 7, 7; and in steps 1 and 2
EQ_ACTRAMP 32, 8; EQL_ACTUPS 16, 4; EQE_ACTUPS 32, 8; EQ_CAPLOAD 32, 8.
RVPRL (L128) is recomputed with the vintages of the step: 5 of its 8
records differ from the state after eqmain.mod in step 1 and 3 in step 2
(layer 1 of each step).

**Does the case really check each statement?** Each fix statement was
switched off in turn in TIMES.jl, and layer 2 of the three steps repeated
with GAMS's levels (a scratch script, not in the repository):

| Statement switched off | solve.stp | Layer 2 of steps 1, 2, 3 |
| --- | --- | --- |
| none | | pass, pass, pass |
| VAR_SIN of the periods already solved, fixed at its level | L203 | pass, FAIL (33 column bounds), FAIL (60) |
| VAR_SOUT, the same | L204 | pass, FAIL (33), FAIL (60) |
| VAR_UPS, the same | L205 | pass, FAIL (12), FAIL (16) |
| VAR_UPT, the same | L206 | pass, FAIL (54), FAIL (72) |
| VAR_UDP, the same | L207 | pass, FAIL (24), FAIL (32) |
| VAR_SCAP, the same | L220 | pass, FAIL (7), FAIL (20) |
| VAR_BLND, the same | L233 | pass, FAIL (18), FAIL (24) |
| VAR_BLND of the pending periods, fixed at zero | L281 | pass, FAIL (9), FAIL (9) |
| VAR_SIN and VAR_SOUT of the pending periods, fixed at zero | L271-272 | pass, pass, pass |

So the case checks L203-207, L220, L233 and L281. It does not check
L271-272, and no LP can: a pending period has no column in the LP of its
step, and bndmain.mod, included again after every step (L319), frees the
storage flows before the period is solved. L232 sets levels, a starting
point that an LP does not show.

**Blending stays fixed at zero after the first step, in GAMS itself (D43).**
Change 3 flagged that L281 fixes VAR_BLND of the pending periods at zero
and that no statement lifts the fix (docs/discrepancies.md, U7). The LPs
GAMS solved for demo12_step3 show it:

- Step 1 (2005-2020): the 36 VAR_BLND columns are free; 2030 and 2050 have
  none.
- Step 2 (2020, 2030): the nine columns of 2020, solved again, are free.
  The nine of 2030, the step's new period, are fixed at zero. The periods
  already solved are fixed at their levels (L233): all zero but
  `VAR_BLND(REG1,2010,TRAGSL,BIO)`, fixed at 1209.08.
- Step 3 (2050): the nine columns of 2050, the step's only period, are
  fixed at zero; so are those of 2020 and 2030.

TIMES.jl gives the same LPs (layer 2), so there is no known difference:
the translation follows the code. It looks like a fault of v4.9.7: every
other variable that L268-279 fix is free again when its period is solved.
A report to ETSAP needs James's yes (docs/decisions.md, Open decisions).

CI: `test/unit/test_solve_stp3.jl` (109 tests) on the fixtures of the case
as run (`demo12_step3_input`, `_ppm`, `_equ`, and one data and one matrix
fixture per step; about 10 MB): the chain from GAMS's ppm dump, layers 1
and 2 per step, the counts of the two tables above in TIMES.jl's LP and in
GAMS's, the columns of D43, and `solve_stepped!` with HiGHS to the end of
the run (layer 3 per step). `test_ddsource.jl` compiles the case from its
DD files and compares the result with GAMS's input dump.

Flagged:

- **Not reached by an open stepped case**, translated as written: the
  copy-back of L177 and L180-181 and L186-189 (regions in REG_FIXT only);
  L178-179 (a user constraint summed over the regions with a UC_CAP
  coefficient); EQE_UCRS; and L271-272, which no LP shows (above). TODO
  for a later release: a case for L178-179 and for EQE_UCRS.
- **One value each**: one blending level and one VAR_UPS level are fixed
  at a value that is not zero; two of VAR_SOUT and eight of VAR_SCAP.
- Not translated, as before: VAR_ELAST (L211, L276) and VAR_DAM (L212)
  with their refused features, FIXBOH and REG_FIXT, the %SOW% forms.

## What demo12_step reaches, and what it does not

Reached (records in the dump of step 2): user constraints by region and
period (UC_R_EACH, UC_T_EACH, UC_RHSRT 8, UC_RHSRTS 6) with UC_RN 3, R_UC 2
and UC_BND 14; cumulative flow bounds (FLO_CUM 18, VAR_CUMFLO 18) through
bnd_cum.mod in each step; VAR_CAP with RTP_VARP 18 and NO_RVP 4; RTC_NET 84
and RTC_PRD 12; trade between the two regions; the salvage preparation
(OBJ_LIFE 674, OBJSCC 107).

Not reached by demo12_step, translated as GAMS has them. The last column
is the state after change 7 (15 Nov 2026):

| Branch | Lines of solve.stp | Checked against GAMS? |
| --- | --- | --- |
| G_OVERLAP given by the user | 44 | yes: demo12_step2 |
| OBJ ALT or LIN (LINFLO): STP_DIV, coef_alt.lin STP | 104-107, 124 | yes: demo12_steplin, demo12_steplino (OBJ LIN), demo12_stepalt1 (OBJ ALT, one step; with several steps GAMS fails, D42) |
| CAP_BND | 69, 96, 190-191, 218-219, 279 | yes: demo12_step2 |
| a cumulative user constraint (UC_T_SUM) | 132-137 | yes: demo12_step2 |
| a dynamic user constraint (UC_T_SUCC, UC_DYNBND, PRC_DYNUC) | 144-151, 183-185 | yes: demo12_step2 |
| user constraints summed over regions (UC_R_SUM) and their right-hand sides | 141-144, 157, 178-179 | yes for L141-144, L157-176: demo12_step2; no for the copy-back of L178-179 (needs such a constraint with a UC_CAP coefficient) |
| COM_CUM (VAR_CUMCOM) | 186-189, 222-230 | yes for L222-230: demo12_step2; L186-189 are REG_FIXT only |
| REG_CUMCST | 196 | yes: demo12_step2 |
| the fixes of storage flows (VAR_SIN, VAR_SOUT) | 203-204, 271-272 | yes for L203-204: demo12_step3; L271-272 show in no LP ("Change 7 as built") |
| VAR_UPS, VAR_UPT, VAR_UDP (dispatching, unit commitment), VAR_SCAP (retirement), RVPRL | 128, 205-207, 220 | yes: demo12_step3 |
| blending | 232-233, 281 | yes: demo12_step3; GAMS keeps blending fixed at zero after the first step (D43) |
| elastic demand, damage (refused) | 211-212, 276 | no: with those features |
| FIXBOH and REG_FIXT | 46-49, 158, 177, 180-181, 186-189, 234-264, 315-317 | no: see "Flagged" |

## Flagged

- **FIXBOH** (a run fixed to an earlier solution up to a year) and
  **REG_FIXT** take their levels from a restart point (SPOINT or LPOINT),
  which TIMES.jl refuses, and no open model has one. Their branches of
  solve.stp stay refused until the restart points are translated (part 2 of
  this plan); a run with them stops with the usual message.
- **STAGES, SPINES and SENSIS** with a stepped run: solve.stp L11-12 aborts
  or takes other branches; refused with the stochastic extension.
- **CLI** (CM_MAXC, L149) and **TM_HSX** (the tolerances of L154): refused
  with their extensions.
- A start from a given solution (L61-66, `VAR_UC.L('SOLVE_STATUS')`): needs
  a restart point; translated for the case without one (no levels).

## Not in this plan

The report of a stepped run (M1.6), timings (Phase 2), and the solver's
advanced basis (`BRATIO=1`, L285: a solver setting that does not change the
LP or its optimum value).
