# M1.3 preprocessing: plan (31 Oct 2026)

Source: TIMES v4.9.7, etsap-TIMES/TIMES_model @ d9a6a25. Translate one file or
block per change, in execution order; GAMS names kept; every function cites
its lines. Agreed with James on 31 Oct 2026; M1.3 translation starts once the
M1.2 gate passes (CLAUDE.md), change 0 (infrastructure) alongside the M1.2
close-out.

## Scope: from the input dump to the ppm dump

maindrv.mod L55-58 (v4.9.7):

- L55: the extensions' `init_ext` (`init_ext.dsc`, `init_ext.vda` with
  `equcrtp.vda` INIT_EXT; `prepparm.gms` is called from `equcrtp.vda`
  PREP_EXT, L55, and belongs to the prep segment);
- L56: `ppmain.mod` and its includes (`timslice.mod`, `pp_off.mod`,
  `preppm.mod` with `prepxtra.mod`, `fillparm.gms`, `fillvint.gms`,
  `curex.gms`, `preshape.gms`; `filparam.gms`, `filshape.gms`, `pp_qafs.mod`,
  the levelising macros `pp_lvl*.mod`, `pp_chp.mod`, `eqflomrk.mod`,
  `pp_reduce.red` with `dynslite.vda`) and the extension stages inside it
  (`prep_ext.vda` at preppm.mod L217, `pp_prelv.vda` at ppmain.mod L615);
- L58: the extensions' `ppm_ext` (`ppm_ext.dsc`, `ppm_ext.vda` with
  `pp_actef.vda`, `resloadc.vda`, `equcrtp.vda` PPM_EXT, `dynslite.vda`).

Plus `cal_red.red` on the equation side, which REDUCE YES needs (M1.1
refused it; the as_run variants of the suite run REDUCE YES).

About 4,200 lines in about 30 files: roughly five times M1.2. The riskiest
part is the interpolation subsystem (`preppm.mod`, `prepparm.gms`,
`fillparm.gms`, `fillvint.gms`): its options decide almost every parameter
the later stages read.

Refused (UnportedError), as in M1.1 and M1.2: TIMES-MICRO / TIMESED
(`pp_micro.mod`), MACRO (`ppmain.tm`), stochastics (`prep_ext.stc`,
`recurrin.stc`), the ETL, CLI, ABS, ECB and MLF extensions, `INTEXT_ONLY` and
`DATAGDX`, and blending (ppmain.mod L1230-1336) unless a suite model needs it.

## Checkpoints (harness 0.3.0)

The harness dumps every symbol at five points of one GAMS run (the pre-solve
run, `--TJL_CHECKPOINTS=1`; reference/README.md), without editing TIMES:

| Checkpoint | Where (v4.9.7) | How |
| --- | --- | --- |
| `input/` | before `$BATINCLUDE maindrv.mod` | run-file patch |
| `init/` | maindrv.mod L55, after `init_ext.dsc`/`.vda` | `init_ext.tjlref` |
| `prep/` | preppm.mod L217, after `prep_ext.vda` | `prep_ext.tjlref` |
| `prelv/` | ppmain.mod L615, after `pp_prelv.vda` | `pp_prelv.tjlref` |
| `ppm/` | maindrv.mod L58, after `ppm_ext.dsc`/`.vda` | `ppm_ext.tjlref` (M1.2) |

So preprocessing splits into four segments, each started from GAMS's own
state and checked at the next checkpoint. A segment can be translated and
checked on its own; the whole chain (input to ppm, then on to the model) is
tested at the gate. `scripts/m13_inventory.jl` lists what each segment
creates or changes on a reference run.

Symbols created or changed per segment (reduce_off, sets and parameters,
`scripts/m13_inventory.jl`, 31 Oct 2026; cloud pre-solve runs with the PyPI
GAMS 54.6.1):

| Segment | demo12 | OTCGEN | OTNYC |
| --- | ---: | ---: | ---: |
| input → init (init_ext) | 7 | 8 | 9 |
| init → prep (ppmain L1-248, preppm L1-217) | 86 | 97 | 98 |
| prep → prelv (preppm L218-253, ppmain L249-615) | 50 | 57 | 57 |
| prelv → ppm (ppmain L616-1357, ppm_ext) | 76 | 80 | 93 |

## Order (one change each)

| # | GAMS | Lines | Checked at |
| --- | --- | --- | --- |
| 0 | infrastructure: harness 0.3.0 checkpoints, `--only presolve`, `m13_inventory.jl`, demo12 checkpoint fixtures, `m13_probe.jl` | | |
| 1 | init_ext.dsc; init_ext.vda with equcrtp.vda (INIT_EXT) | 11-23; 52-156; 15-38 | init |
| 1b | crafted demo12 states for the init_ext.vda paths no core model reaches (OFF-ranges, peaking, storage, partial loads, UC_ACTBET, ...) | | init |
| 2 | ppmain.mod: declarations, control sets, storage sets, NCAP_PASTI spread | 1-137 | prep |
| 3 | ppmain.mod with filparam.gms (G_OFFTHD): years, periods, B/E/D/M, LEAD/LAG, EOHYEARS | 138-191 | prep |
| 4 | timslice.mod, pp_off.mod | 1-123; 1-23 | prep |
| 5 | ppmain.mod: PASTI migration, START/NOFF, RTP_OFF | 199-247 | prep |
| 6a | preppm.mod with prepxtra.mod SAVE, curex.gms (refused), prepret.dsc PREP, fillvint.gms, filparam.gms, prepparm.gms, fillparm.gms (interpolation) | 1-212 | prep |
| 6b | preppm.mod L213-217: prep_ext.vda with equcrtp.vda (PREP_EXT); the segment's all-symbols check; MY_SUM kept by timslice.mod | 213-217; 1-83; 40-62 | prep |
| 7a | preppm.mod with preshape.gms; ppmain.mod: timestep control, horizon, commodity groups and RC, PG/SPG | 218-252; 249-328 | prelv |
| 7b | ppmain.mod: commodity and process timeslice levels (pp_off.mod for COM_OFF), peaking, RPCS_VAR | 329-460 | prelv |
| 8a | ppmain.mod: lifetimes, refits, capacity transfer, capacity bounds, availability years (pp_off.mod for PRC_AOFF, PRC_FOFF), PRC_ACTFLO | 461-611 | prelv |
| 8b | pp_prelv.vda with pp_lvlfc.mod (FLO_FR); the segment's all-symbols check | 1-125 | prelv |
| 9 | ppmain.mod with pp_qafs.mod, filshape.gms, filparam.gms: SHAPE/MULTI, defaults, capacity-only flows | 616-682 | ppm |
| 10 | ppmain.mod with pp_lvlfc.mod, pp_lvlbr.mod, pp_lvlpk.mod: commodity and availability attributes by timeslice | 683-797 | ppm |
| 11a | ppmain.mod with pp_lvlfc.mod (the flow attributes), pp_chp.mod: flow attributes by timeslice, the FLO_PKCOI default, CHP | 800-821; 1-71 | ppm |
| 11b | ppmain.mod with pp_lvlff.mod, pp_lvlfs.mod, pp_lvlbr.mod (FLO_SHAR), eqflomrk.mod: FLO_FUNC, FLO_SUM, FLO_SHAR, FLO_MARK | 823-845 | ppm |
| 12 | ppmain.mod with pp_lvlif.mod: trade and marketplaces | 846-935 | ppm |
| 13a | ppmain.mod with pp_lvlbd.mod: balance types, IRE conversion, bounds | 936-1001 | ppm |
| 13b | ppmain.mod: cumulative constraints, VAR_COMxxx on the balance RHS | 1003-1056 | ppm |
| 14 | ppmain.mod: storage | 1061-1101 | ppm |
| 15a | ppmain.mod with prepxtra.mod UCINT: the user-constraint defaults (years, regions, timeslices, dynamic and cumulative UCs) | 1101-1179; 61-77 | ppm |
| 15b | ppmain.mod with pp_lvlus.mod: the UC group maps, VAR_CAP and VAR_COMxxx for UCs, UC attributes levelled, RCS_COMBAL/RCS_COMPRD | 1181-1226; 1-40 | ppm |
| 16 | ppmain.mod: blending (refused unless needed; any non-blending statements in the block translated) | 1228-1333 | ppm |
| 17a | ppmain.mod end with pp_reduce.red (dynslite.vda refused, as in 8b) | 1336-1357; 1-188 | ppm (reduce_off and as_run) |
| 17b | cal_red.red: flows substituted by activities on the equation side | 1-59 | layer 2 (as_run) |
| 17c | crafted case TIMES_Demo-demo12_red17b for the 17b paths demo12 does not reach (cal_red.red L37-38 with an RPC_ACT source; bnd_flo.mod L37-39) (James, 5 Nov 2026) | — | layers 2-3 (both variants) |
| 18a | ppm_ext.dsc; ppm_ext.vda with pp_actef.vda (LVL): dispatching and partial loads, the VDA_EMCB sums, ACT_EFF prepared, inherited and levelled | 1-16; 11-58; 9-48 | ppm |
| 18b | ppm_ext.vda with equcrtp.vda (PPM_EXT): shape indexes, flows kept from the reduction, commodity and CHP availabilities, NCAP_AFX/AFM options; the segment's all-symbols check (resloadc.vda refused, dynslite.vda refused) | 59-169; 64-72 | ppm |
| 19 | eqstgips.mod: EQ_STGIPS, inter-period storage (James, 5 Nov 2026: the families M1.1 left untranslated become M1.3 changes) | 13-44 | layers 2-3 OTNYC (both variants); EQ_STGIPS rows on OTCGEN |
| 19b | eqstgaux.mod: the inter-period storage terms of EQ_STGAUX | 25-32 | EQ_STGAUX rows on OTCGEN; crafted demo12 case (CI) |
| 20 | equcrtp.vda (EQU_EXT): EQ(l)_UCRTP and EQN_UCRTC, dynamic process and commodity bounds | 73-123 | layers 2-3 OTUS9r |
| 20b | prepret.dsc: early retirement and refits — DSC code that OTUS9r uses (found 5 Nov 2026 by demo12 variant 5; brought into M1.3 by James, 5 Nov 2026). In four parts (6 Nov 2026); the family stays refused until the last: | | layers 2-3 OTUS9r; demo12_refit (CI) |
| 20b-1 | prepret.dsc EQOBJ: EQ_CUMRET, EQL_SCAP, EQL_REFIT (EQ_DSCRET and the EQL_SCAP IN rows refused) | 89-117 | the rows of the three families, OTUS9r and demo12_refit |
| 20b-2 | %RCAPSUB%/%RCAPSBM% (prepret.dsc L87-88): the -VAR_SCAP terms in the translated capacity equations (eqcpt.mod, eqcapact.mod, eqpeak.mod, eqcaflac.vda; cal_cap.mod and cal_caps.mod stay refused with their files) | 87-88 | the rows of those families, OTUS9r, demo12_refit, crafted case demo12_refit_afc |
| 20b-3 | prepret.dsc DECL: the VAR_RCAP and VAR_SCAP bounds (and VAR_DRCAP, refused) | 66-80 | column bounds vs CONVERT: OTUS9r, demo12_refit, demo12_refit_afc |
| 20b-4 | prepret.dsc OBJFIX and OBSALV, the objective terms (eqobj.mod L39, eqobjfix.mod L214, eqobsalv.mod L26, L105); the refusal lifted | 134-162 | layers 2-3 OTUS9r; demo12_refit and demo12_refit_afc (CI, whole model) |
| 21 | equserco.mod: dynamic user constraints in the RHS direction (UC_DYNDIR 'RHS', uc_pasti.mod) | 80-106 | TIMES-NZ, OTCGEN |
| 22 | uc_*.mod: user-constraint attributes other than GROWTH (CAP, SYNC, ...) | | TIMES-NZ |
| 23 | eqflomrk.mod: EQ(l)_FLOMRK, market-share flow constraints (the export term, L83-88, checked on the crafted case demo12_mrkx, 13 Nov 2026, #68) | | TIMES-NZ; demo12_flomrk, demo12_mrkx (CI) |
| 24 | eqactups.vda: EQ_SLSIFT, load shifting (with the demo12 load-shifting variant) | 131- | layers 2-3 TIMES-NZ (both variants) |
| 25 | eqmain.mod preparation and pp_qack.mod: the coef -> pre-solve step, so the CI chain runs end to end (in M1.3, not M1.5: James, 5 Nov 2026) | | presolve (demo12 in CI) |
| 25-1 | mod_vars.mod L94 (prepret.dsc DECL, its data statements L44-81), eqobj.mod L14-39 (with prepret.dsc EQOBJ L119-131) and eqobjinv.mod L18-274 (with coef_alt.lin INV, L89-118): the investment cases, spreads, corrections and divisors (8 Nov 2026; the step in parts) | 14-39; 18-274 | the probe's coef -> presolve segment: core models, demo12 cases; crafted case demo12_objinv (CI) |
| 25-2 | eqobjfix.mod, eqobjvar.mod, eqobsalv.mod (with coef_alt.lin FIX and prepret.dsc OBJFIX/OBSALV): their data statements (9 Nov 2026) | 19-175; 11-82 | coef -> presolve: core models, demo12 cases (CI) |
| 25-3 | eqmain.mod L41-262 (RVPT, RTP_OFF, the UC maps and the other data statements between the equation includes), equ_ext (eqactups.vda L1-35 and the other VDA preparations), mod_equa.mod, mod_ext (9 Nov 2026) | | coef -> presolve: residual inventory on the core models and demo12 cases |
| 25-4 | bndmain.mod data statements, pp_qack.mod (less the QA log, 25b) and pp_clean.mod (solve.mod L1, the memory clean-up), and the step's scratch; the coef -> pre-solve step joins the M1.3 chain and the CI chain runs end to end (9 Nov 2026). Follow-up, 14 Nov 2026: bnd_cum.mod L12-20 and L27-38 on FLO_CUM, COM_CUM and RC_CUMCOM in full (FX, N, negative and after-horizon records, the -INF default of L38), on the crafted case demo12_cumc | bnd_cum.mod 12-40 | presolve, every symbol: core models, demo12 cases (CI: test_m13_coef_presolve.jl, test_m13_chain.jl end to end; test_bnd_cum.jl on demo12_cumc) |
| 25-5 | The coefficient stage's scratch (follow-up to 25-4, its open gate item): filparam.gms (coef_obj.mod L41) and fillcost.gms (L120-151) leave F, Z, MY_F, DFUNC, LAST_VAL, FIRST_VAL and MY_FYEAR as their last tuple does, taken in GAMS order and carried from call to call; coef_ext.vda L23 leaves Z. scripts/m13_gate.jl chains the coefficient stage and the coef -> pre-solve step (9 Nov 2026) | coef_obj.mod 41, 120-151; coef_ext.vda 23 | coef: every set and parameter (CI: test_m13_chain.jl); the gate from the input dump to presolve |
| 25b | pp_qaput.mod: the QA log (QA_CHECK.LOG) and its scalars PUTOUT, PUTGRP and ERRLEV, at every pp_qaput call translated so far, and the ERRLEV abort of pp_qack.mod L376-386 (ERRLEV 33: the run goes on with an alert; above 33: stop). TIMES.jl checks errors as GAMS does until JuMP-side checks are added in Phase 2 (James, 6 Nov 2026). The harness does not keep QA_CHECK.LOG yet (harness change, then a GAMS rerun) | 1-16; 376-386 | log text and scalars at init, prep, prelv, ppm; crafted demo12 states for the WARNING, ERROR and FATAL paths (CI) |
| 25b-1 | The QA log's machinery (`src/prep/qalog.jl`: QLOG, pp_qaput.mod, GAMS's PUT rules, G53) and every pp_qaput call and PUTGRP reset of preprocessing: ppmain.mod (L35 compile warnings, G54; L213-230, L273-276, L338-340, L465-471, L524-542, L573-585, L723-728, L765, L848, L878-885, L989, the PUTCLOSE of L1356), timslice.mod L67-104, pp_qafs.mod, pp_lvlbr.mod, pp_lvlbd.mod, pp_lvlif.mod, pp_chp.mod, pp_prelv.vda L81-85, ppm_ext.vda L86-94. The harness keeps QA_CHECK.LOG (0.3.2; `keep_qa_log.py` for earlier references, no GAMS rerun) (9 Nov 2026) | | PUTOUT, PUTGRP, ERRLEV at init, prep, prelv, ppm; the log at ppm, where GAMS's goes on with pp_qack.mod's groups (gate; CI on demo12) |
| 25b-2 | pp_qack.mod's checks (L37-372: the QA groups, 'ALL QUALITY CHECKS PASSED') and the ERRLEV abort (L376-386); the log compared whole at presolve (9 Nov 2026; dynslite.vda L25 stays with TS_OFF data, refused) | 37-386 | log text and scalars at presolve; crafted demo12 states for the WARNING, ERROR and FATAL paths (CI) |
| 25b-3 | Crafted cases demo12_qa (warnings, the run goes on) and demo12_qa99 (a FATAL error, the abort of pp_qack.mod L380) (9 Nov 2026) | | the whole QA log from the input dump (CI: test_qalog.jl); the chain on demo12_qa (gate) |
| 25c | The reduced flows of the M1.2 coefficient stage, refused until now: coef_ptr.mod L38-42 (ACT_FLO of the reduced flows from RPCG_PTRAN, COEF_PTRAN zeroed) and coef_ext.vda L62-69, L75 (ACT_FLO of the singleton ACT_EFF flows, RP_DCGG, RTP_FFCX, RPCG_PTRAN cleared), so the as_run chain goes on past ppm | coef_ptr 38-42; coef_ext 62-75 | coef, every symbol, from GAMS's ppm dump: OTCGEN, OTNYC, OTUS9r, TIMES-NZ steady and shift, demo12 cases (as_run); the gate from the input dump (approved and merged 9 Nov 2026, #81) |
| 26 | curex.gms (preppm.mod L27-28): currency conversion from G_CUREX and R_CUREX into each region's currency. JRC-EU-TIMES-cli_ll has G_CUREX data (found 7 Nov 2026 by the nightly run; brought into M1.3 by James, 7 Nov 2026) | 1-84 | prep: JRC-EU-TIMES-cli_ll on James's machine (verdicts only, docs/test-models.md); crafted case demo12_curex, G_CUREX and R_CUREX in a second currency (CI) |
| 27 | powerflo.vda: the power-flow (PTDF) grid extension, %POWERFLO% YES, which init_ext.vda L134-135 sets when PRC_REACT, GR_PTDF or GG_KGF has data. JRC-EU-TIMES-cli_ll has PRC_REACT data (found 7 Nov 2026; brought into M1.3 by James, 7 Nov 2026). In three parts; the switch stays refused until the last: | | JRC-EU-TIMES-cli_ll on James's machine (verdicts only); demo12 variant 6, PTDF power grid (docs/demo12-variants.md; CI) |
| 27a | powerflo.vda main block (pp_prelv.vda L114: the grid topology, GR_* sets and parameters, PRC_REACT, COM_LIM) and PREP (prep_ext.vda L37) in the phase-angle formulation (9 Nov 2026); the PTDF formulation and the allocation of generation and demand to nodes (GR_PTDF, GR_DEMFR, GR_ENDFR, GR_GENFR, GR_GENMAP, GR_GENLEV data) stay refused for 27a-2, with demo12 variant 6 proper | 1-204 | prelv and prep checkpoints: crafted case demo12_pf (CI: variant fixture) |
| 27b | powerflo.vda DECL (mod_vars.mod L95), POWFLO (equ_ext.vda L101, mod_ext.vda L45) and IREAUX (%IREAUXBAL%, L221): the power-flow variables, bounds and equations; CSTBAL and OBJBAL (L372-435) stay refused with COM_CSTBAL data, which neither case has. Done for phase-angle grids (9 Nov 2026): VAR_COMAUX, the reference-node bounds, GR_GRID 'ACT', EQ_GR_POWFLO; EQ_GR_PTDFLO, VIRTCAP, VIRTBND, GENALL, DEMALL (and the IREAUX terms, which need node allocation) come with 27a-2, EQ_GR_XBND with GR_XBND data | 206-370 | layers 2-3: demo12_pf, both variants (CI: public fixture) |
| 27a-2 | powerflo.vda main block, the allocation of generation and sectoral demand to the grid nodes (GR_ENDFR, GR_GENFR, GR_GENMAP, GR_GENLEV data; JRC-EU-TIMES has them): L40-47 (the add-on nodes and their IRE lines) and L109-162 (GR_GENLEV rounded, GR_PRCMAP, GR_ALLMAP, GR_ALGMAP, GR_DEMMAP, GR_ENDC, the sectoral fractions turned into GR_DEMFR and normalised, GR_GENMAP and GR_GENFR normalised, GR_ADO, GR_GNALL). Still refused: GR_PTDF data (the PTDF formulation, L59-64, L172-180) and GR_DEMFR given as data (L107, L131); the equations that use the allocation (EQ_GR_GENALL, EQ_GR_DEMALL, IREAUX terms) are 27b-2 (10 Nov 2026) | 40-47, 109-162 | prelv to coef: crafted case demo12_pfa, both variants (CI: variant fixture); JRC-EU-TIMES-cli_ll locally (verdicts only) |
| 27b-2 | powerflo.vda POWFLO, the rows that use the node allocation: EQ_GR_GENALL (L290-313) and EQ_GR_DEMALL (L314-340), and the IREAUX terms (%IREAUXBAL%, L221, L363-370) that cal_ire.mod L30 adds to EQ_COMBAL's consumption (eqcombal.mod L84, label IREAUXIN, times COM_IE) and EQ_PEAK's net imports (eqpeak.mod L31, IREAUXOUT-, negated); the other cal_ire calls jump to the end of the file (L461-462). The model-stage refusal of node-allocation data is lifted; GR_DEMFR as input data stays refused in the main block. New crafted case demo12_pfd (a second grid node in REG1), since demo12 has one node per region, so GR_DEMFR is emptied and no EQ_GR_DEMALL row exists (13 Nov 2026) | 290-340, 363-370 | layers 2-3: demo12_pfa and demo12_pfd, both variants (CI: demo12_pfd public fixture, demo12_pfa and demo12_pfd variant fixtures); the M1.3 chain to presolve on both |
| 27c | powerflo.vda RPTB (cost_ann.rpt L175): the reporting block, translated with M1.6 and listed here so the file is tracked | 437-462 | M1.6 |
| 28 | eqashar.vda with pp_lvlfc.mod (coef_ext.vda L79): RPCG_ASHAR and the levelling of FLO_ASHAR, refused until now; EQ(l)_ASHAR's exchange branch and storage terms, refused since M1.1 (James, 14 Nov 2026: the refused features are translated now, one change each, each with a crafted demo12 case) | 16-33; 51, 56-65, 75-76 | every checkpoint and layers 2-3 on the crafted case demo12_ashar, both variants (CI: test_ashar.jl) |
| 29 | coef_obj.mod, the control switch ANNCOST LEV, refused since M1.2: ACL takes MINYR, MINYR becomes MIYR_V1, RPT_OPT('OBJ','2') is 1, and MINYR is restored when %CTST% is empty | 31-32 | every checkpoint and layers 2-3 on the crafted cases demo12_lev (OBJ MOD) and demo12_levstd (OBJ AUTO), both variants (CI: test_anncost.jl) |
| 30 | Stepped (myopic) runs, the preparation before solve.stp, refused since M1.2: coef_alt.lin L81 (no RTP_CAPVL under TIMESTEP) and eqobsalv.mod L23-25 (OBJ_SUMS, OBJ_SUMS3, SALV_INV and OBJSCC cleared, the salvage preparation left to the steps). The stepped solve itself (maindrv.mod L38-40 and L109-113, solve.stp) is M1.5: model generation and the bounds still refuse the run | coef_alt.lin 81; eqobsalv.mod 23-25 | every checkpoint to the new `equ` checkpoint (harness 0.3.3), and the pre-solve dump less the 27 symbols the loop of solve.stp assigns, on the crafted case demo12_step, both variants (CI: test_stepped.jl) |
| 31 | EQ(l)_BNDNET and EQ(l)_BNDPRD, refused since M1.1: bounds on the net amount and the production of a commodity at a timeslice above the level it is tracked at, written as equations over the tracked timeslices below | eqbndcom.mod 16-24; eqmain.mod 54-59 | layers 1 to 3 on the crafted case demo12_bndc, both variants, from the DD files (CI: test_eqbndcom.jl, the public and variant fixtures) |
| 32 | EQ(l)_FLOBND, refused since M1.1: bounds on process flows that cannot be bounds of one flow variable (above the flow's timeslice level, a commodity group, a vintaged process, an exchange process, a flow REDUCE replaces), written as equations over the flow variables. Two corrections of `bnd_data!` (bnd_flo.mod L16 and L31) that the crafted case showed | eqflobnd.mod 15-43; eqmain.mod 111-113; bnd_flo.mod 16, 31 | layers 1 to 3 on the crafted case demo12_flobnd, both variants, from the DD files (CI: test_eqflobnd.jl, the public and variant fixtures) |
| 33 | EQ(l)_FLOFR, refused since M1.1: the share of a process flow in a timeslice (FLO_FR), against the flow of the year, of the parent timeslice, or a variable of an aggregate flow (records 'N') | eqflofr.mod 15-27; eqmain.mod 118-120 | layers 1 to 3 on the crafted case demo12_flofr, both variants, from the DD files (CI: test_eqflofr.jl, the public and variant fixtures) |
| 34 | EQ(l)_IREBND, refused since M1.1: limits on the trade of a commodity between a region and one partner region (IRE_BND): imports from an internal region as the partner's exports, imports from and exports to an external region as the region's own flows (the marketplace branch, L46-51, stays refused with RPC_MARKET) | eqirebnd.mod 18-69; eqmain.mod 152-154 | layers 1 to 3 on the crafted case demo12_irebnd, both variants, from the DD files (CI: test_eqirebnd.jl, the public and variant fixtures) |
| 35 | EQ(l)_XBND, refused since M1.1: limits on the total exchange of a commodity of a region (IRE_XBND), whatever the partner: for an internal region its own flows in the direction, for an external region the flows of the internal regions in the other direction through IRE_TSCVT | eqxbnd.mod 17-56; eqmain.mod 241-243 | layers 1 to 3 on the crafted case demo12_xbnd, both variants, from the DD files (CI: test_eqxbnd.jl, the public and variant fixtures) |

## Parity (per change)

Layer 1 at 1e-9 at the change's checkpoint, starting from GAMS's state at
the previous checkpoint, on the core tier (TIMES_Demo demo12, TIMES-NZ
steady, OTCGEN, OTNYC, OTUS9r reference), reduce_off and as_run, and TIM-bau
on James's machine (results stay there). A change is compared on the
symbols it settles that nothing later in its segment changes (the M1.2 rule
for later files); scratch symbols (CNT, F, FIL, FIL2, MY_*, YK1, Z, ...) only
where the GAMS code reads them again. Branches no suite model reaches are
checked against GAMS itself on crafted demo12 states (scripts/gams_replay.jl).
Between them the core models reach the unusual branches: OTNYC the FLO_SHARE
auto-relaxation (pp_qafs.mod L66-89), OTUS9r the dynamic user constraints
(equcrtp.vda), TIMES-NZ the flow marks (eqflomrk.mod), OTCGEN and OTNYC the
plain objective (OBJ AUTO without OBLONG).

The checkpoint dumps of the public models can be made in the cloud workspace
with the PyPI GAMS (no solve: `make_reference.py --only presolve`); James's
workstation stays the reference of record (`run_references.ps1 -Checkpoints`).

## Gate

- Input dump to `ppm/` at 1e-9 on every core model, reduce_off and as_run
  (TIM-bau locally).
- In CI on demo12: input, preprocessing, coefficients and the model, with the
  matrix (layer 2) and the objective (layer 3), REDUCE off and on.
- Preprocessing timed against GAMS (docs/timings.md).
- The QA log and the ERRLEV abort as GAMS (change 25b): QA_CHECK.LOG and
  PUTOUT, PUTGRP, ERRLEV compared at each checkpoint.
- TIM-bau runs on James's machine only; its results stay there (James,
  6 Nov 2026).
- JRC-EU-TIMES-cli_ll (milestone tier), once changes 26-27b merge: the
  chain from the input dump to ppm, reduce_off and as_run, on James's
  machine; only the verdicts are published (`redistribute = "summary"`).
  Agreed by James, 7 Nov 2026.

### Gate checks, 5 Nov 2026 (changes 0-18b and 17b in review)

- The chain from the input dump (`scripts/m13_gate.jl`: TIMES.jl's own
  state carried across the checkpoints; at each, every set and parameter of
  the segment's start dump, less PUTOUT, PUTGRP and ERRLEV): PASS at init,
  prep, prelv and ppm on the five core models, reduce_off and as_run
  (821 symbols, 822 on OTUS9r; at ppm 66,471 GAMS records on demo12 to
  19,186,490 on OTUS9r as_run). TIM-bau: to run on James's machine (local
  log, nothing committed).
- CI on demo12 (`test/unit/test_m13_chain.jl`): the chain from the input
  dump to ppm, then the whole coefficient stage against the coef dump; the
  model from the pre-solve dump with the matrix (layer 2) and the objective
  (layer 3), REDUCE off (`demo12_off`) and on (`demo12_red`, change 17b).
  The step between the coef and pre-solve dumps (eqmain.mod's preparation,
  pp_qack.mod) is not part of M1.3, so the model is generated from the
  pre-solve dump, as in M1.1.
- Preprocessing timed against GAMS (`scripts/m13_timing.jl`,
  docs/timings.md): TIMES.jl warm 3.0x GAMS on demo12 and 4.8x to 5.5x on
  the four large core models.

### Gate close-out, 14 Nov 2026 (changes 0-29)

Each criterion of the gate with its evidence. Every reference was made with
GAMS 54.6.1; the runs are on James's workstation, within the run limits.
The gate is passed when James says so (a rule-level decision, #109).

| Criterion | Evidence | Result |
| --- | --- | --- |
| Input dump to `ppm/` at 1e-9, five core models, reduce_off and as_run | `scripts/m13_gate.jl` with the code of this PR (changes 0-29, M1.4 change 7), 14 Nov: TIMES.jl's own state carried from the input dump; every set and parameter at init, prep, prelv and ppm. 823 symbols (824 on OTUS9r). GAMS records at ppm, reduce_off / as_run: demo12 66,473 / 66,967; TIMES-NZ-steady 3,148,294 / 3,162,804; OTCGEN 11,652,425 / 11,665,748; OTNYC 4,734,976 / 4,749,691; OTUS9r 19,118,669 / 19,186,492. The same chain passed in the batch of 12 Nov (`928ed68`). | PASS, 10 of 10 |
| The same chain beyond the gate: coef, presolve | Same run: every set and parameter at coef (949 to 953 symbols) and presolve. | PASS, 10 of 10 |
| TIM-bau | Checked locally (results stay on James's machine). | local |
| CI on demo12: input, preprocessing, coefficients and the model, layers 2 and 3, REDUCE off and on | `test/unit/test_m13_chain.jl` (input dump to ppm, coef, presolve, then the model against GAMS's matrix and objective, `demo12_off`); `demo12_red` for REDUCE YES; the crafted demo12 cases as fixtures. GitHub CI: Julia 1, Julia lts and the reference harness. | PASS |
| Preprocessing timed against GAMS | docs/timings.md, 13 Nov 2026: TIMES.jl warm 3.4 times GAMS on demo12 and 5.4 to 6.3 times on the four large core models. James, 14 Nov 2026: close enough to pass the gate. | timed; accepted |
| QA log and ERRLEV abort as GAMS (change 25b) | Changes 25b-1 to 25b-3 (#75-#77). In the chain, QA_CHECK.LOG, PUTOUT, PUTGRP and ERRLEV are compared at every checkpoint, and the log text at ppm and at presolve; crafted cases with warnings and a FATAL abort are in CI. | PASS, 10 of 10 |
| JRC-EU-TIMES-cli_ll: input dump to ppm, both variants (verdicts only) | Batches of 12 Nov and 14 Nov (`c04c8ab`): init, prep, prelv, ppm and the QA log at ppm; 850 symbols; chain in 933 s (reduce_off) and 833 s (as_run). | PASS, 2 of 2 |
| OTUS9r layer 3, one way (CLAUDE.md, #61) | Parity report of 12 Nov: the CPLEX optimum of the GAMS run cross-evaluated in TIMES.jl's model. OTUS9r-reference reduce_off: objective 192,206,392,884.7 on both sides, relative difference 0; the largest row violation, 2.5e-4 at EQ_OBJVAR(R5,USD05), is the same in GAMS's own matrix. | PASS |

Not part of the gate, for the record:

- From DD files (M1.4) the same chain passes to the model on OTUS9r,
  OTCGEN, OTNYC and TIMES-NZ-steady in the batch of 14 Nov (`c04c8ab`),
  with layer 2 against GAMS's matrix in both variants (OTUS9r-reference
  reduce_off: 2,174,010 rows, 2,776,359 columns, 9,925,588 nonzeros) and
  HiGHS against CPLEX in both variants on OTCGEN and OTNYC (relative
  difference under 2e-15) and on TIMES-NZ-steady (3.8e-11 and 2.0e-10).
- Features TIMES.jl still refuses stop a run with the GAMS file and lines
  that are missing (docs/gams-julia-map.md, "Untranslated paths that stop
  generation"). No core model reaches one. They are translated one PR
  each, with a crafted demo12 case, after the gate.

## Findings so far

- (27b) powerflo.vda DECL and POWFLO for phase-angle grids (9 Nov 2026).
  DECL (mod_vars.mod L95) runs in the coef -> pre-solve step after
  prepret.dsc DECL: VAR_GRIDIO, VAR_XCAP and the free phase angle
  VAR_COMAUX are declared only under %POWERFLO% (`powerflo_vars!`), the
  reference node of each disjoint grid (the first with the most lines) has
  its phase angle fixed at 0 (`bnd_powerflo!`), and GR_GRID gets an 'ACT'
  record per grid region. EQ_GR_POWFLO (equ_ext.vda L101) equates the flow
  over the lines between two nodes (imports less exports at the importing
  end) with the admittance times the phase-angle difference. On demo12_pf
  the whole model matches GAMS in both variants: the matrix (8,719 rows
  reduce_off, 3,257 as_run) and the objective 23,960,685.74 with CPLEX and
  HiGHS. Generation now refuses only the grid data not translated (PTDF,
  node allocation, gas grids) and EQ_GR_XBND with GR_XBND data.
- (27a) powerflo.vda, phase-angle grids (`src/ext/vda/powerflo.jl`, 9 Nov
  2026). PREP interpolates PRC_REACT and the grid parameters
  (fillparm.gms, filparam.gms); the main block builds the grid from
  TOP_IRE between the electricity nodes of NRG_GMAP: line directions
  (GR_FLOW), GR_TOP, GR_ARC, the reactances made equal at both ends of a
  line between regions, GR_ADMIT, the disjoint grids (GR_GID from EPS,
  GR_GRID), the DAYNITE checks, RC_GRID, GR_GMAPC, GR_ENDC, GR_ADO and COM_LIM
  FX on the nodes. Two GAMS points, checked on GAMS 54.6.1: in
  `gr_sus(rc_grid,rc)` (L103) the two set-indexed groups run independently
  (not as a diagonal), and `option gr_sus < gr_admit` (L102) fills the
  repeated domains from the right (G52), so GR_SUS starts as the transpose
  of GR_ADMIT, which L103-104 then overwrite only in part. Crafted case
  demo12_pf (PRC_REACT on demo12's REG1-REG2 electricity link) passes the
  init -> prep and prep -> prelv segments on every symbol and the gate from
  the input dump to coef (reduce_off); equ_ext.vda L101 and mod_vars.mod L95
  (DECL and POWFLO, the equations) are 27b and refused at the coef ->
  pre-solve step. The probe now skips a start-dump symbol the next dump
  lacks (demo12_pf's coef dump has ADESC, its pre-solve dump has not) and
  the harness's TJL_SOLVEINFO, as the gate does.
- (25b-3) Two crafted cases for the QA log (9 Nov 2026). demo12_qa adds data
  the checks warn about (NCAP_TLIFE beyond AGE, an FX share with an UP one,
  COM_PROJ of a non-DEM commodity, NCAP_CEH on a non-CHP process, NCAP_AF
  with NCAP_AFA); the run goes on and solves (objective 23,960,762.61), and
  the chain from the input dump passes every checkpoint with the QA log
  identical at presolve. demo12_qa99 gives REG2's WD a second parent: a
  FATAL error at timslice.mod L101-104 (ERRLEV 99), on which pp_qack.mod
  L380 aborts; GAMS's run stops there (made with `--only presolve`, its QA
  log from the harness's work folder), and TIMES.jl's chain passes every
  checkpoint to coef, stops at the same point and leaves the same log. The
  case found that pp_qack.mod L339-341 writes UNCD7 rows with the label
  '', which no dump holds when no record uses it (G36): registered now. CI
  runs both from their input dumps (test_qalog.jl). No suite model and no
  DD file reaches ERRLEV 33: phantom topology needs a domain violation and
  an IFQ of 10 or more makes the model infeasible.
- (25b-2) pp_qack.mod's checks (`src/model/qack_log.jl`, 9 Nov 2026): the
  checks every run makes (L62-182: year fractions, the topology, commodity
  types, demands, phantom topology entries, the primary groups, FS_EMIT,
  REFIT hosts, NCAP_AFX) and the extended ones of %VDA% with %XTQA% (L203-
  372), which every core reference runs. Each reads the state where the file
  has it, so `pp_qack_data!` calls them between its data statements. Two
  pairs of loops share a group, as the file sets PUTGRP to 0 only before the
  first ('Commodity in CG ...' with 'No commodities in CG ...'; the IRE
  checks of L216-238). The scratch Z of L82-84 is kept. At the end (L374-
  387): ERRLEV 33 writes the alert and the run goes on, above 33 the run
  stops (an error here, as GAMS's ABORT); with nothing written the log gets
  'ALL QUALITY CHECKS PASSED'; PUTOUT, PUTGRP and ERRLEV are cleared. The
  EXECERROR block (L183-201) is left out: TIMES.jl stops at the first
  execution error. From GAMS's coef dump the lines pp_qack.mod writes match
  GAMS's log on the five core models and the demo12 cases, both variants;
  the gate and the CI chain compare the whole log at presolve.
- (25b-1) The QA log (`src/prep/qalog.jl`, 9 Nov 2026). QA_CHECK.LOG is a
  GAMS PUT file, and its text depends on PUT rules a test on GAMS 54.6.1
  pinned down (G53): `/` ends the current line even when empty, trailing
  blanks are dropped, `@n` moves back and overwrites (the level is written
  as ` *00` then overwritten from column 4 or 3), PUTCLOSE writes only a
  line that is not empty, so the first group after ppmain.mod's PUTCLOSE
  (L1356) follows two blank lines; numbers as C's `%.*f`, labels padded to
  MAX(12, length) by %RL%, %PL% and %CL%. ppmain.mod L35 writes a group
  when compilation raised warnings (TIMES-NZ: 88); no dump records that, so
  the count is an input of the run, read from the reference's listing
  (G54). Every pp_qaput call and PUTGRP reset of preprocessing is
  translated in LOOP order, with the PUTGRP side effects (pp_qafs.mod L19
  and pp_lvlbr.mod L54 test it). The QA log found one condition that has no
  data effect: pp_qafs.mod L71 reads the RTPGIG of L60 (L65 clears RTP_GRP
  only), so the groups whose redundant fixed share was dropped skip the
  FX+UP check. The harness keeps the pre-solve run's QA_CHECK.LOG (0.3.2);
  `reference/python/keep_qa_log.py` copied it into the existing references
  from the work folder, each checked to be the same run by its listing, so
  no GAMS rerun was needed. The gate (`scripts/m13_gate.jl`) and the CI
  chain compare PUTOUT, PUTGRP and ERRLEV at every checkpoint and the log at
  ppm, where GAMS's goes on with pp_qack.mod's groups.
- (25-5) The coefficient stage's scratch (9 Nov 2026), the open gate item
  of 25-4. filparam.gms and fillcost.gms reset only some of their scratch
  scalars per tuple (filparam F, Z, MY_FYEAR; fillcost F and LAST_VAL), so
  what coef_obj.mod leaves depends on the order of the tuples and of the
  calls: `FilScratch` (src/coef/coef_obj.jl) carries F, Z, MY_F, DFUNC,
  LAST_VAL, FIRST_VAL and MY_FYEAR from the G_DRATE call (L41) through
  every fillcost call (L120-151), each looped in GAMS order, and writes
  them back after the last, with the arrays fillcost.gms leaves: MY_ARRAY
  (the last tuple's values at DM_YEAR, over what L113 cleared) and MY_FIL2
  (cleared per tuple, then its interpolated years). CNT is left alone: fillcost.gms L33's
  `FOR(CNT=MY_FYEAR-Z+1 TO -1, ...)` always ends at 0, which coef_nio.mod
  L59 has already cleared. coef_ext.vda L23 (`Z=SMAX(T,PRC_RESID)` in the
  PRC_RCAP loop) leaves Z, found on demo12_refit. From GAMS's ppm dump the
  coefficient stage now matches the coef dump on the eight scratch scalars
  and the two arrays on every reduce_off run: the five core models and the
  demo12 cases (comparing every symbol at coef found the arrays). The
  CI chain compares the coef checkpoint on every set and parameter, and its
  pre-solve check no longer excludes anything. scripts/m13_gate.jl now
  chains on from ppm through the coefficient stage (coef) and the coef ->
  pre-solve step (presolve), as far as TIMES.jl translates them: the gate
  still asks for ppm, and an UnportedError past it ends the chain there.
  The as_run variants stop at the coefficient stage: the M1.2 coefficient
  stage refuses reduced flows (coef_ptr.mod L38-42, coef_ext.vda L62-69),
  which every as_run reference has.
- (25-4) The end of the coef -> pre-solve step (`src/model/qack_prep.jl`,
  9 Nov 2026): bndmain.mod's data statements and its includes' (NCAP_BND,
  CAP_BND, UC_TS_SUM, FLO_BND and TRACKPC in bnd_flo.mod, the storage bounds,
  the UC right-hand sides that bnd_ucv.mod L35 opens with an INF upper bound
  for 'N'), pp_qack.mod's data statements without the QA log (the
  generation control sets of L45-60: RPC_CONLY, RTPCS_VARF, RCS_COMBAL,
  RPG_RED, RTP, RTP_VNTBYR, COEF_VNT, RVP_KMAP; PRC_CG; what the checks
  leave: TS_ARRAY, PRC_YMAX, UNCD7, Z), and pp_clean.mod (solve.mod L1: the
  memory clean-up that zeroes FLO_SUM, FLO_FUNC, NCAP_AF, NCAP_AFA,
  NCAP_AFS and the cost attributes). The steps also leave the scratch
  scalars and arrays as GAMS does (F, Z, MY_F, CNT, OBJ_C, OBJ_D, FIL2,
  MY_ARRAY): the loops run in GAMS order, a FOR loop leaves its variable
  at the first value past the bound (1 when it runs no iteration; checked
  on GAMS 54.6.1), and an EPS NCAP_ILED leaves MY_F at EPS (OTUS9r).
  `OPTION p < q` of two parameters copies q's values when p has q's
  dimension and counts q's records when it has fewer (G31, refined;
  COEF_VNT). Checked from GAMS's coef dump on every set and parameter of
  the pre-solve dump (less PUTOUT, PUTGRP, ERRLEV): all pass on the five
  core models (OTUS9r 821 of 821) and twelve demo12 cases, both variants.
  The probe's coef -> presolve segment ends with an all-symbols step, and
  the CI chain (`test_m13_chain.jl`) now runs end to end on demo12: input
  dump -> preprocessing -> coefficients -> pre-solve (every symbol) ->
  the model from TIMES.jl's own state, whose matrix (layer 2) and
  objective (layer 3) match GAMS. Open for the gate: the coefficient stage
  (M1.2) does not yet leave filparam.gms's scratch FIRST_VAL, LAST_VAL and
  MY_FYEAR as GAMS's last call does (each call writes them before reading
  them); the CI chain excludes those three at the pre-solve checkpoint.
  scripts/m13_gate.jl still chains input -> ppm only; carrying the
  coefficient stage into it waits for that fix.
- (25-3) The rest of eqmain.mod and equ_ext.vda (`src/model/eqmain_prep.jl`,
  9 Nov 2026): AFS (eqcapact.mod L20, the `L` include), eqbndcst.mod's block
  (SUPERYR, YK1; RT_IAN, RTP_IAN and CST_ANNC stay empty without cost-bound
  data, which is refused), RVPT and RTP_OFF (L199-202), the user-constraint
  maps (L211-226, from `uc_setup` and `uc_tmap`, now stored), RP_PL and AFS
  (equ_ext.vda L77-79), and RP_UPR (eqactups.vda L33, which is outside the
  dispatching IF and so empties RP_UPR in a model with ACT_TIME but no
  ACT_CSTRMP). Refused: the dispatching preparation (eqactups.vda L9-32,
  with RP_UPL, RP_PL or ACT_CSTRMP) and REG_BNDCST/REG_CUMCST. A residual
  inventory (every set and parameter of the pre-solve dump after the
  translated steps) on the core models and nine demo12 cases now shows only
  what 25-4 covers: bndmain.mod's data statements (NCAP_BND), pp_qack.mod
  (RTP_VNTBYR, COEF_VNT, PRC_CG, RPG_RED, RXX, RVP_KMAP, RP_XRED, PRC_YMAX,
  UNCD7, TS_ARRAY), pp_clean.mod (solve.mod L1: FLO_SUM, FLO_FUNC, NCAP_AF,
  NCAP_AFA, NCAP_AFS and the cost attributes zeroed to free memory) and the
  scratch scalars and arrays the step leaves (F, Z, MY_F, OBJ_C, OBJ_D,
  FIL2, MY_ARRAY). CI: test_m13_coef_presolve.jl.
- (25-2) eqobjfix.mod L19-175 with coef_alt.lin FIX (L105-131) and
  eqobsalv.mod L11-82 (`src/model/eqobjfix_prep.jl`, 9 Nov 2026; eqobjvar.mod
  and prepret.dsc OBJFIX/OBSALV have no data statements): the fixed-cost
  spreads (OBJ_FCUR, OBJ_YES, OBJ_SUMIV for cases 1a, 1b, 2a, 2b, OBJ_SUMIVS
  for decommissioning surveillance, without past-investment charges where
  NCAP_PASTI is absent), the shape controls RTP_SHAPE/RTP_ISHPR, the
  present-value factors OBJ_LIFE, the spreads KAGE, INVSTEP and INVSPRED, the
  divisors OBJ_DIVIV, and under a non-empty %CTST% OBJ_JD, OBJ_WD and the
  residual-capacity divisors; then the salvage controls and values
  (OBJ_SUMS, OBJ_SUMS3, SALV_INV, OBJ_DCEOH, OBJSCC, OBJ_IAD, COR_SALVD,
  OBJ_CRFD, SALV_DEC). Three GAMS points: `OPTION a <= b` matches repeated
  domains from the left and `OPTION a < b` from the right (G52, checked on
  GAMS 54.6.1; KAGE takes JOT from OBJ_LIFE); in coef_alt.lin L125
  `MAX(1,MIN(IPD(T),ROUND(NCAP_TLIFE))$(OBJ_1B+OBJ_1A))` gives 1 to cases
  2a/2b (the `$` conditions the MIN only); under FIX, `%2` = `*` comments out
  coef_alt.lin L117-118, so INVSTEP is kept and the OBJ_WD lines run, and
  eqobjfix.mod L169 skips the clear of OBJ_YES. The copy of L161 runs in
  GAMS order and sees its own earlier copies. Checked, coef -> presolve on
  the symbols settled (with 25-1: 51; 66 with early retirement): OTCGEN,
  OTNYC, TIMES-NZ and OTUS9r (reduce_off); demo12, demo12_ucattr,
  demo12_ips, demo12_refit, demo12_objinv on both variants; CI:
  test_m13_coef_presolve.jl.
- (25-1) The start of the coef -> pre-solve step (`src/model/eqobjinv_prep.jl`,
  `prepret_decl!` and `prepret_eqobj!` in `src/ext/dsc/prepret.jl`,
  8 Nov 2026). The step from the coef dump to the pre-solve dump changes 53
  symbols on demo12 (the eqobj*.mod preparation, mod_vars, eqmain, bndmain
  and pp_qack); it is translated in four parts (25-1 to 25-4) and probed as
  a fifth segment, coef -> presolve, of `scripts/m13_probe.jl` (the gate
  and the timing script keep to input -> ppm until 25-4). 25-1 covers what
  runs before eqobjfix.mod: prepret.dsc DECL's data statements
  (mod_vars.mod L94: the refit maps, RP_RTF, VNTRT, RVPRL, VN2T and the EPS
  added to NCAP_ILED, which forces the retiring vintages into case 2a),
  eqobj.mod L14-39 (K_EOH, KTYAGE, SUM_OBJ, where `OBV('OBJSAL'),OBV` is one
  controlled index so only (OBJSAL,OBJSAL) is -1) with prepret.dsc EQOBJ's
  data statements (L119-131), and eqobjinv.mod L18-274: RTP without the
  zero past investments, OBJ_ICUR, the lifetime corrections, COR_SALVI,
  OBJ_CRF, OBJ_PASTI, OPYEAR, the cases 1a, 1b (with its FOR loop over
  repeated investments), 2a and 2b, the interest during construction, the
  investment and decommissioning spreads (KAGE, INVSTEP, INVSPRED, UNCD7,
  YKAGE, OBJ_SUMIII), and the divisors, with coef_alt.lin's INV part under
  a non-empty %CTST% (DOINV falls through into DOFIX up to `%2$GOTO
  FINISH`). Checked on the symbols the part settles that nothing later in
  the step changes (26, and 15 more for early retirement): every core
  model, reduce_off (OTCGEN, OTNYC, TIMES-NZ: 26 of 26; OTUS9r with early
  retirement: 41 of 41), demo12, demo12_ucattr, demo12_ips, demo12_refit and
  demo12_refit_afc on both variants, and the crafted case
  TIMES_Demo-demo12_objinv (`reference/dd/demo12_objinv/`: decommissioning
  costs, lifetimes and lag, a technology discount rate, a 6-year life that
  repeats within periods and, in REG2, with a 2-year lead time: case 2b),
  which no suite model reaches; its whole model passes layers 2-3 (33
  checks; objective 23,962,067.34 by CPLEX and HiGHS). CI:
  `test_m13_coef_presolve.jl` on demo12_off, demo12_refit (its coef dump
  is a new fixture) and demo12_objinv. Not translated: %VALIDATE%, %ETL%,
  %STAGES% (refused). RVPT (eqmain.mod L199-201) is empty on OTUS9r because
  its OBJ_2A entries are all past vintages and the loop runs over milestone
  years; it is read from the dump until 25-3.
- (24) eqactups.vda L127-158, EQ_SLSIFT, load shifting
  (`src/ext/vda/eqslsift.jl`, 8 Nov 2026). Rows (R,T,P,COM,S,LNX,L) for
  every RPS_PRCTS slice of an RPC_LS process with LNX = FX and L in {N,
  FX}, and for any LNX with an ACT_TIME window L at the process's own
  slices; the left-hand side is generated only for LNX = FX (the sifting
  balance against STG_SIFT for L = N, the net shifting for L = FX, the
  advance/delay terms for LO/UP with ACT_TIME 'LO') and the right-hand side
  only for LNX = N (the delay balance over the previous slice for UP, the
  advance balance for LO, the time windows for N and FX). `var_sift` is
  VAR_UDP times PRC_CAPACT*RS_STGPRD/8760; the windows compare
  MOD(..., 1/JS_CCL) (sign of the first argument, G43) over RS_UP and
  RJ_SL with ACT_TIME/8760, and `RJ_SL(R,JS,TS(SL--RS_STG(R,SL)))` binds TS
  to the previous slice of SL. ACT_TIME fills RP_UPR only for the
  preprocessing hour map (init_ext.vda L73, timslice.mod L110-121):
  eqactups.vda L33 rebuilds RP_UPR from ACT_CSTRMP before the equations,
  so a load-shifting model with windows brings no EQ_ACTRMPC. The other
  families of eqactups.vda stay refused. Checked: TIMES-NZ steady, the
  8,736 EQ_SLSIFT rows against CONVERT on both variants (86,114 checks),
  and TIMES-NZ's whole model for the first time (changes 21, 23 and 24):
  steady reduce_off layer 2 PASS (1,408,361 rows, 1,299,224 columns,
  5,026,918 nonzeros); demo12 variant 1, the crafted cases
  TIMES_Demo-demo12_ls (`reference/dd/demo12_ls/`: a load-shifting
  process for commercial electricity in both regions, as TIMES-NZ's
  demand-flexibility processes are set up, with STG_SIFT on ACT in REG2)
  and TIMES_Demo-demo12_lst (plus ACT_TIME LO 4, UP 6, N 12 hours in
  REG1, which reach VAR_UDP and the VAR_UPS window terms over the hour
  map): EQ_SLSIFT rows against CONVERT on both variants (120 and 228
  rows), the M1.3 probe 54 of 54 and chain PASS on both variants, the
  whole models 34 of 34 checks each (objective 23,960,685.74 by CPLEX and
  HiGHS); CI fixtures `demo12_ls`, `demo12_lst` and `test_eqslsift.jl`.
- (23) eqflomrk.mod L56-105, EQ(l)_FLOMRK (`src/model/eqflomrk.jl`,
  8 Nov 2026): the market share of a process, or of a group ITEM of
  processes, in the production of a commodity (VAR_COMPRD over the
  commodity group): the standard flows (cal_red, times COM_IE for an
  output), exchange flows (imports with IRE_FLOSUM and COM_IE when
  PRC_MARK >= 0, exports when <= 0; under REDUCE an RPC_AIRE flow is the
  activity times PRC_ACTFLO) and storage output and input, each weighted by
  RS_FR and RTCS_FR, times POWER(PRC_MARK, 1$RX_MARK(R,'0',...)-1), against
  the production times the RX_MARK/LASTLL product of a process ITEM. The
  preparation half (L13-52) came with change 11b. Checked: TIMES-NZ steady,
  the 6,720 EQG_FLOMRK rows against CONVERT on both variants (47,042
  checks; TIMES-NZ now waits only for change 24); the crafted case
  TIMES_Demo-demo12_flomrk (`reference/dd/demo12_flomrk/`: demo12 with the
  oil store of demo12_ips, FLO_MARK on the gas plant, a negative own share
  of a coal plant, so the flows are divided by PRC_MARK and the right-hand
  side is 0, a group ITEM of hydro and wind, FX on coal imports and UP on
  the store): the 23 rows against CONVERT on both variants, the M1.3 probe
  54 of 54 and chain PASS on both variants, and the whole model 38 of 38
  checks (objective 23,960,715.70 by CPLEX and HiGHS); CI fixtures `demo12_flomrk` and `test_eqflomrk.jl`. No exports in
  demo12, so the EXP term is checked only through its code path.
- (22) uc_*.mod, the user-constraint attribute factors (`_uc_perdisc`,
  `_uc_perds`, `_uc_fcost` and the term functions in
  `src/model/equserco.jl`, 8 Nov 2026): PERDISC (several-period terms,
  FPD + (COEF_PVT - FPD) for a cumulative constraint), PERIOD and NEWFLO
  (FPD, and for NEWFLO 1/FPD only for the period's vintage or one RVPT
  commissions in it; on NCAP, PERIOD adds the RVPT investments and
  COEF_RPTI - PROD(RVPT,2)), EFF (XOR the COMNET/COMPRD group type), CAPACT,
  BUILDUP (1/LEAD), and the cost attributes COST, DELIV, TAX and SUB on FLO
  and IRE (OB_FCOS, OB_FDEL, MIN/MAX(0,OB_FTAX) over RDCUR and TS_ANN), ACT
  (OB_ACT), NCAP (OB_ICOST + OB_ITAX - OB_ISUB) and COMPRD/COMNET (OBJ_COMPD,
  OBJ_COMNT per attribute). Still refused: ANNUL with INVCOST, INVTAX,
  INVSUB (uc_ncap.mod L39 reads CST_ANNC of eqbndcst.mod) and ONLINE
  (uc_cap.mod L36-42, the VDA RS family's VAR_UPS terms). RVPT (eqmain.mod
  L199-201) is read from the dump: its loop is over OBJ_2A at milestone
  years, so it is empty on OTUS9r, whose OBJ_2A entries are all past
  vintages. No suite model has these attributes (TIMES-NZ's SYNC came in
  with change 21), so the check is the crafted case TIMES_Demo-demo12_ucattr
  (`reference/dd/demo12_ucattr/`: five constraints with every translated
  attribute, CUMSUM and CUM+ entries of UC_TMAP, and a vintaged nuclear
  plant with a 6-year lead time so that RVPT has a cross-period and three
  same-period entries): the user-constraint rows match CONVERT on both
  variants (39 rows; 1,083 checks reduce_off), the M1.3 probe 54 of 54 and
  chain PASS on both variants, the whole model 35 of 35 checks (objective
  23,981,380.11 by CPLEX and HiGHS); CI fixtures `demo12_ucattr` and
  `test_equserco_attr.jl`. The rewritten term functions leave the core
  models' user-constraint rows as GAMS has them (TIMES-NZ, OTCGEN, OTNYC,
  OTUS9r reduce_off, every UC row against CONVERT).
- (21) equserco.mod L80-106 with uc_pasti.mod, dynamic user constraints in
  the RHS direction (`uc_dyn_rhs!`, `uc_pasti!`, `uc_tmap` in
  `src/model/equserco.jl`, 8 Nov 2026). A dynamic constraint takes the RHS
  direction when SUM(UC_DYNDIR(R,UC_N,'RHS'),1) holds, with R the row's
  region or, for EQE_UCSU and EQE_UCSUS, any region. Its terms come from
  UC_TMAP(T,LL,TT,SIDE,UC_DYNT) (eqmain.mod L211-215, built here and equal
  to GAMS's, in order, on TIMES-NZ, OTCGEN and OTUS9r): an entry is taken
  when LIM(UC_DYNT) xor UC_ATTR(R,UC_N,SIDE,grp,UC_DYNT), so the N entry
  unless the group has the attribute N (ppmain.mod L1168 sets it for an
  RHS SYNC) and the CUMSUM, CUM+ and SYNC entries only with their
  attribute; grp is the name the TSUM macro gets (COMPRD, COMNET for the
  two uc_com includes). The variables are at TT, the coefficients at LL,
  the GROWTH exponent is -LEAD(T)*UC_SIGN(SIDE)-1, and in the first
  period's rows uc_pasti.mod subtracts the past investments' capacity
  times the RHS UC_CAP (and its GROWTH power M(T)-B(T)), a constant that
  GAMS moves to the right-hand side. The UC_DYNT attributes are now
  translated (they only pick UC_TMAP entries); CUMSUM always brings PERIOD
  or ANNUL with it (ppmain.mod L1160-1161), both still refused, so the
  CUMSUM and CUM+ entries wait for change 22. Checked: OTCGEN, the whole
  model for the first time, layers 2-3 PASS on both variants (reduce_off
  1,257,132 rows, 1,507,223 columns, 6,732,783 nonzeros, objective
  734,425,529.71; as_run 512,182, 765,953, 5,200,869, 756,404,387.82; both
  as GAMS with CPLEX); TIMES-NZ steady, every user-constraint row against
  CONVERT on both variants (1,561 rows: 588 EQE_UCRSU and 868 EQE_UCRSUS
  in the RHS direction with GROWTH and SYNC, 17,061 coefficients; 47,861
  checks), the rest of the model waiting for changes 23-24; the crafted
  case TIMES_Demo-demo12_ucdyn (`reference/dd/demo12_ucdyn/`: five dynamic
  constraints, one or two per family, with CAP, NCAP, ACT, FLO, COMPRD,
  COMNET and IRE terms, GROWTH, SYNC, UC_TIME and hydro past investments),
  M1.3 probe 54 of 54 and chain PASS on both variants, the whole model
  37 of 37 checks (objective 54,125,294.455 by CPLEX and HiGHS), CI
  fixtures `demo12_ucdyn`. TIMES-NZ's change-22 item (the LHS SYNC
  attribute) is covered by this change.
- (8 Nov 2026, pp_off.mod scratch) The gate compares every set and
  parameter at each checkpoint, scratch included, but the translation of
  pp_off.mod (changes 4, 5, 7b, 8a) did not keep its scratch: FIL, which
  L17 clears at every call, and the scalars STARTOFF and ENDOFF of the last
  range (L18). A model with OFF ranges (TS_OFF, PRC_NOFF, COM_OFF,
  PRC_AOFF, PRC_FOFF) therefore failed the all-symbols check at prep,
  prelv and ppm on those three symbols alone; in the public core models
  GAMS leaves them empty at every checkpoint, so the check passed. Fixed:
  `PPOffScratch` and `pp_off_keep!` leave them as GAMS does, the PRC_NOFF
  and COM_OFF loops now run in GAMS order, and the crafted OFF-range
  states (timslice, ppmain_rtp, ppmain_tslvl, ppmain_life, pp_prelv)
  compare the three symbols against GAMS (they fail without the fix).
- (26) curex.gms (preppm.mod L27-28; `src/prep/curex.jl`, 8 Nov 2026,
  moved ahead of 21-25b by James): R_CUREX filled from G_CUREX, the
  currency map CURMAP and the reduced RDCUR (L18-26), the two-step chains
  (RXX, L29-32), and the 29 cost attributes converted into the RDCUR
  currencies, with or without a temporary copy (L35-82). Checked against
  GAMS on a crafted demo12 state run through ppmain.mod L1-247, preppm.mod
  L1-212 and curex.gms by GAMS 54.6.1 (`preppm_unit_gams/curex`, 138
  symbols, CI), and on the crafted case TIMES_Demo-demo12_curex (demo12 +
  curex.dd): the M1.3 probe (54 of 54 steps) and chain PASS on both
  variants, and the whole model passes layers 1-3 (33 checks; objective
  23,974,183.74 by CPLEX and HiGHS); CI fixtures. New GAMS semantics: G51
  (a self-referencing assignment reads the values from before it; EPS
  counts in `$=`). coef_obj.mod L99 (`$IF DEFINED R_CUREX`, %TAKE% 1) is
  now read from R_CUREX's data, since curex.gms always gives it records
  (L26), which lifts the refusal there; after curex.gms every investment,
  fixed and decommissioning cost is in an RDCUR currency, so dropping the
  filter changes no record. `gset_opt` and `gparam_opt` now return a set
  or parameter TIMES.jl has computed even when the dump does not declare
  it (CURMAP on demo12, which curex.gms declares only when it runs).
  Refused, with data: the blending costs (L59-60) and the ETL and
  stochastic costs (L66, L68-69).
- (7 Nov 2026, probe) JRC-EU-TIMES-cli_ll in the nightly runs of 5 and
  6 Nov: the chain stopped, as it should, at the curex.gms refusal
  (preppm.mod L27-28), but `m13_probe.jl` showed FAIL on the steps of the
  prep -> prelv segment (preppm_shape, ppmain_life, pp_prelv) where it
  should have shown the POWERFLO refusal. The probe starts each segment from
  a GAMS dump, with the switches of the run file; %POWERFLO% is not in the
  run file but set by init_ext.vda L134-135 from the data (PRC_REACT), and a
  dump does not keep it. So pp_prelv.vda L114 ran without powerflo.vda and
  every symbol powerflo.vda writes differed. Fixed: the TimesModel
  constructor derives the switch from the data (`data_switches!`), so every
  model built from a dump refuses POWERFLO (the probe, and also bndmain and
  model generation from a pre-solve dump); `init_ext!` calls the same
  function. With %POWERFLO% YES the earlier steps leave out the scratch that
  powerflo.vda assigns again (MY_F in preppm_shape, RXX in ppmain_life), as
  preppm already left out RTP and RVP. JRC's two features become changes 26
  (curex.gms) and 27 (powerflo.vda).
- (20b-4) prepret.dsc L134-162, the objective terms of early retirement
  (`objfix_ret!`, `objsalv_ret!`, `src/ext/dsc/prepret.jl`): in EQ_OBJFIX
  the fixed costs avoided by retired capacity (each VAR_SCAP credited with
  the FOM, FTX and FSB of its remaining years, KTYAGE, and the residual
  vintages without RVPRL over PERIODYR); in EQ_OBJSALV the salvage of
  retired capacity, OBJSCC*OBJ_DCEOH*(VAR_SCAP(R,V,'0',P)-VAR_NCAP-NCAP_PASTI)
  unless NCAP_FDR and RVPRL(R,'0',P) both hold (`$` before NOT, G46).
  eqobsalv.mod L26 changes only the salvage sets, which the pre-solve dump
  holds (change 25 will have to compute them). With this part `generate!`
  calls `eq_ret!` and no longer refuses early retirement (EQ_DSCRET and the
  EQL_SCAP IN rows stay refused). Checked, whole model, layers 2-3, both
  variants: demo12_refit (as_run 3,351 rows, 4,627 columns, 19,246
  nonzeros; reduce_off 8,893, 9,891, 32,422; objective 23,926,037.11 by
  CPLEX and HiGHS) and demo12_refit_afc (3,365, 4,635, 19,333; 8,907,
  9,899, 32,509; 23,924,506.51), CI fixtures `demo12_refit` and
  `demo12_refit_afc` (public_fixtures.toml). OTUS9r reference, the first
  time its whole model is generated: layer 2 PASS on both variants
  (reduce_off 2,174,010 rows, 2,776,359 columns, 9,925,588 nonzeros;
  as_run 1,028,923, 1,647,278, 7,163,965; GAMS 54.6.1). Layer 3, the
  cross-evaluation (6 Nov 2026): CPLEX's optimum from the GAMS run, read
  from its end-of-run dump, gives OBJz in TIMES.jl's model equal to GAMS's
  (192,206,507,156.18 as_run, 192,206,392,884.71 reduce_off, relative
  difference 0) and is exactly as feasible there as in GAMS's own CONVERT
  matrix (worst row 2.7e-4 relative, EQ_OBJVAR, identical in both; bounds
  within 1e-13). The other half of layer 3, a HiGHS optimum of TIMES.jl's
  model, is open: HiGHS stopped with OTHER_ERROR on as_run and had not
  finished reduce_off after an hour, and the reference has no GAMS/HiGHS
  solve of OTUS9r to compare (CPLEX only, 310 s).
- (20b-3) prepret.dsc L66-80, the VAR_RCAP and VAR_SCAP bounds of the
  DECL label (`ret_bounds!`, `src/ext/dsc/prepret.jl`, first in
  `bndmain`'s table as mod_vars.mod L94 comes before bndmain.mod). RVP and
  PASTSUM are scratch, empty in both the coef and the pre-solve dumps, so
  RVP is rebuilt as L60-61 make it (RVPRL > 0) and PASTSUM from L67-68;
  PRC_YMAX (L78) is rebuilt too. The LOOP of L69 ends after L72 (TT the
  previous milestone, circularly; Z = 0 in the first period); L80's domain
  RTP_TT(R,T(TT++1),T,P) puts T at both year positions. bndmain.mod L15's
  `$CLEAR %VAR%_SCAP` is compile-time and leaves these bounds: the CONVERT
  export has them. Checked: every VAR_RCAP and VAR_SCAP column's bounds
  against the CONVERT export, both variants, with the columns the
  translated rows create (the same set as GAMS's): OTUS9r reference (4,676
  columns, 3,145 with bounds; RCAP_BND 'N' options, L67 and L76),
  demo12_refit (72, 16; the refit hosts' bound, L80) and demo12_refit_afc,
  to which `afc.dd` now adds RCAP_BND LO and FX in REG1 and a negative 'N'
  option in REG2 (L66, L68, the LO terms of L70 and L73; 80 columns, 23
  with bounds). CI: `test_variants.jl` compares the VAR_RCAP and VAR_SCAP
  column bounds on the demo12_refit and demo12_refit_afc fixtures
  (`partial.bounds`). VAR_DRCAP (L46, %MIP%) is refused with RCAP_BLK.
- (20b-2) prepret.dsc L87-88, %RCAPSUB% and %RCAPSBM% (`rcapsub!`,
  `src/ext/dsc/prepret.jl`): with early retirement on, the capacity of a
  PRC_RCAP process loses its cumulative retirements, -VAR_SCAP(R,V,T,P)
  for VNTRT(V,T), wherever a capacity term is built: EQ(l)_CPT (eqcpt.mod
  L26), EQ(l)_CAPACT (eqcapact.mod L37, L45), EQ_PEAK (eqpeak.mod L24),
  EQ(l)_CAFLAC and EQL_CAPFLO (eqcaflac.vda L32, L57). M1.1 recorded these
  macros as always empty (docs/discrepancies.md D1, now withdrawn: Part II
  was right). In eqcaflac.vda the SUM over RVP_KMAP(R,V,P,MODLYEAR(K))
  controls MODLYEAR with K (G48): the first reading, a sum over every
  vintage, gave twice the coefficients on the crafted case
  TIMES_Demo-demo12_refit_afc (`reference/dd/demo12_refit_afc/`: an
  NCAP_AFC on the coal input of the retiring ELCTECOA00 and a second past
  vintage, so that one EQL_CAPFLO row has two retiring vintages), and was
  corrected before commit. Checked: the rows of the capacity families
  (EQ(l)_CPT, EQ(l)_CAPACT, EQ_PEAK, EQ(l)_CAFLAC, EQL_CAPFLO) against the
  CONVERT export, both variants: OTUS9r reference (462,456 rows and
  3,048,139 coefficients reduce_off, 337,122 and 2,477,660 as_run; 44,176
  VAR_SCAP coefficients), demo12_refit (2,568 rows, 122 VAR_SCAP),
  demo12_refit_afc (2,578 rows, 168 VAR_SCAP, 10 EQL_CAPFLO rows with the
  term); CI on the demo12_refit and demo12_refit_afc fixtures
  (`test_variants.jl`, `partial`), which also runs preprocessing input ->
  ppm on the new case. cal_cap.mod and cal_caps.mod (capacity-related
  flows, which carry VAR_SCAP and VAR_RCAP terms of their own) stay
  refused with their files.
- (20b-1) prepret.dsc L89-117, the retirement and refit rows (`eq_ret!`,
  `src/ext/dsc/prepret.jl`): EQ_CUMRET (cumulative retirements: SCAP(T) =
  RCAP(T) + SCAP(T-1), the row dated T, or T-1 for a process without
  RP_RTF), EQL_SCAP's N rows (cumulative retirement by the end of life
  of the investment, the cap on its salvage) and EQL_REFIT (=E= despite its name: refit and
  life-extension investment against the host's retirements; FX rows, N rows
  only for RP_RTF = 3). Generated from the pre-solve dump, as GAMS
  generates them at the SOLVE from the data after the DECL and EQOBJ
  clean-ups. `$` binds before the comparisons: `RP_RTF$VNT$BD<3` is
  `(RP_RTF$VNT$BD) < 3`, so the VAR_RCAP(R,T,TT,PRC) term is kept unless
  VNT(T,TT), BD(L) and RP_RTF >= 3 all hold (the matrix check agrees on
  every row reached).
  Checked: the rows of the three families against the CONVERT export,
  demo12_refit (17 EQ_CUMRET, 7 EQL_SCAP, 24 EQL_REFIT; 161 coefficients)
  and OTUS9r reference (2,008 EQ_CUMRET, 660 EQL_REFIT, 8,955 coefficients;
  no EQL_SCAP), both
  variants; in CI on the demo12_refit fixture (`test_variants.jl`,
  `partial`). Refused: EQ_DSCRET (RCAP_BLK, cleared unless %MIP%) and the
  EQL_SCAP IN rows (NCAP_OLIFE), which no suite model reaches. Not yet
  called by `generate!`: the family stays refused until 20b-4.
- (20) equcrtp.vda L73-121 (EQU_EXT), dynamic process and commodity
  bounds (`eq_ucrtp!`, `src/ext/vda/equcrtp.jl`): EQN_UCRTP (=L=, LO and
  UP), EQE_UCRTP (=E=, FX) and EQN_UCRTC (=L=, LO and UP; no EQE_UCRTC,
  L101), from equ_ext.vda L105-106. Each row bounds x(T) against
  POWER(LHS(T),LEAD(T)) * x(T-1) plus RHS(T)*LEAD(T), x being VAR_CAP,
  VAR_NCAP, the annual sum of VAR_ACT over RTP_VINTYR and PRC_TS, or
  VAR_COMNET/VAR_COMPRD where RHS_COMBAL/RHS_COMPRD hold; in the first
  period only the -x(T) term. Checked: OTUS9r, the only core model with
  dynamic bounds (8 UC_DYNBND, all on ACT): 15,962 EQN_UCRTP rows match the
  CONVERT export on both variants (31,881 coefficients reduce_off, 31,549
  as_run); its whole model now waits only for change 20b. A crafted case
  for the branches OTUS9r does not reach, TIMES_Demo-demo12_ucrt
  (`reference/dd/demo12_ucrt/`: CAP UP in both regions, NCAP LO, ACT FX,
  GAS COMPRD UP, COA COMNET LO): 21 rows (9 EQN_UCRTP, 4 EQE_UCRTP,
  8 EQN_UCRTC), layers 2-3 PASS on both variants (as_run 3,270 rows,
  4,513 columns, 18,499 nonzeros; reduce_off 8,732, 9,697, 31,515;
  objective 23,962,064.98 by CPLEX and HiGHS) and the M1.3 chain PASS
  (GAMS 54.6.1); CI fixtures `demo12_ucrt` and `demo12_ucrt_off`. Found
  while making the case: EQN_UCRTC is defined at ANNUAL only, so a bound
  on a commodity tracked by timeslice (ELC, DAYNITE) has no VAR_COMNET or
  VAR_COMPRD term; GAMS drops these empty rows and so does TIMES.jl
  (`gconstraint!`). The case uses ANNUAL-level commodities instead.
- (19b) eqstgaux.mod L25-32, the inter-period storage terms of EQ_STGAUX:
  the charging less the discharging of the stored commodities in the
  latter half of the period (each year from M(T) weighted by
  MIN(1,YEARVAL-M(T)+MAX(0,M(T)+D(T)/2-E(T))) and discounted for losses to
  E(T), over PERIODYR(T,Y_EOH)) is taken off the level, and for an STK
  process the bracket is scaled to the level in the middle of the period
  (L32). Checked: EQ_STGAUX and EQ_STGIPS rows on OTCGEN (8,488 rows,
  10,313 coefficients, both variants); a crafted case for CI,
  TIMES_Demo-demo12_ips (`reference/dd/demo12_ips/`: an OIL store
  STKOIL1 in both regions, vintaged in REG2, with STG_CHRG before the first
  period, STG_LOSS 2% and an INDCO2 output tied to the level), which GAMS
  gives 27 EQ_STGIPS rows (with both IN rows) and 25 EQ_STGAUX rows: layers
  2-3 PASS on both variants (as_run 3,310 rows, 4,599 columns, 18,726
  nonzeros; reduce_off 8,772, 9,783, 31,742; objective 23,960,094.02 by
  CPLEX and HiGHS) and the M1.3 chain PASS; CI fixtures `demo12_ips` and
  `demo12_ips_off`. Change 19 found a closure in eq_stgips! writing the
  row counter (the returned count only), fixed here.
- (19) eqstgips.mod, EQ_STGIPS (inter-period storage, `src/model/eqstgips.jl`):
  two kinds of row, as IPS = {IN, N} (setglobs.gms L154) and LIM =
  {LO, FX, UP, N}: N, for every RTP_VINTYR tuple of an STK process with
  PRC_STGIPS, the end-of-period level = the level at the end of T-1 (the
  activity dated LL-LEAD(LL) before the first period) times
  POWER(1-STG_LOSS, D(T)), plus the charging less the discharging, each
  year discounted for losses to E(T); IN, for V = T = the first
  milestone only, the vintages' activity at LL-LEAD(LL) = STG_CHRG there.
  `SUM(IO(IPS), x)` with IPS controlled is x when IPS is in IO (G14). One
  slip found by the check and fixed before commit: the loss sum is over
  PERIODYR(T,Y_EOH), and Y_EOH is a set of its own, so the years PERIODYR
  gives the last period past the horizon are left out (123 vs 3 on
  OTNYC's 2055 rows). Checked: OTNYC layer 2 PASS (reduce_off 504,698
  rows, 858,299 columns, 2,531,196 nonzeros; as_run 236,650 rows, 557,258
  columns, 1,863,168 nonzeros) and layer 3 PASS (HiGHS vs CPLEX:
  9,656,876.73 and 9,657,725.87), the first large core model through
  layers 2-3; EQ_STGIPS rows on OTCGEN (384 rows, 1,504 coefficients,
  both variants), which needs change 21 before its whole model. Not
  translated: eqstgips.lin (OBJ LIN), refused.

- (1) init_ext.dsc, init_ext.vda with equcrtp.vda INIT_EXT (31 Oct 2026):
  the input -> init segment matches GAMS on every set and parameter at the
  init checkpoint (824-825 symbols, nothing excluded) on the five core
  models, reduce_off and as_run (GAMS 54.6.1 checkpoints), and on demo12 in
  CI; TIM-bau was probed locally (results stay on James's machine).
  `prepparm.gms` is not part of this segment: equcrtp.vda calls it in its
  PREP_EXT section (L55), so it moves to change 6. DSC: no core model has
  discrete or semi-continuous capacity data, so no init_ext.dsc statement
  applies and %DSC% becomes NO; such data is refused until crafted cases
  check L12-17 (`T--ORD(T)` on a subset, `OPTION` onto the parameter
  PRC_SEMI). `$IF DEFINED x` is read as "x has records in the input dump"
  (G1, G35): nothing compiled before init_ext.dsc assigns PRC_DSCNCAP,
  NCAP_DISC or RCAP_BLK, so only DD data can define them. The compile-time
  switches the segment sets (%DSC%, %POWERFLO%) go into `tm.switches`.
  Paths no core model reaches are listed in docs/gams-julia-map.md; they
  get crafted demo12 states run through init_ext.vda by GAMS in change 1b.
- (1b) (1 Nov 2026) Two crafted demo12 input states ("flags", "offrange",
  test/unit/init_ext_case.jl) run through init_ext.vda with equcrtp.vda by
  GAMS 54.6.1 match init_ext! on the 55 symbols the files write, nothing
  excluded (CI). GAMS confirms: MOD keeps the sign of its first argument
  (L124 keeps an 'N' bound of YEARVAL-1, and -1 at '0'); a bound above
  %EOTIME% is capped before L123 takes the lead; L117 removes an EPS
  NCAP_START, which L121 may then set again; the FLO_COST clean-up leaves
  UNCD7 with '' labels (G36). At the input checkpoint COM_GMAP holds only
  the user's commodity groups (the TIMES groups such as NRG come in
  preprocessing), which L65 reads. init_ext.dsc stays refused for discrete
  or semi-continuous capacity data (the DSC extension follows core and VDA,
  translation-guide.md, Decisions).
- (2) ppmain.mod L1-137 (1 Nov 2026): matches GAMS at the prep checkpoint
  on the symbols it settles (`ppmain_head_symbols`, 27 on every core model)
  on the five core models, reduce_off and as_run, and on demo12 in CI;
  TIM-bau was probed locally (results stay on James's machine). TIMES-NZ
  reaches the guessed primary group (L59-63) and four core models the
  STG/STK/STS storage defaults. Four crafted demo12 states ("storage",
  "stslim", "nopg", "pasty", test/unit/ppmain_head_case.jl) run through an
  unchanged copy of L1-137 by GAMS 54.6.1 match on the 30 symbols it writes
  (CI). GAMS confirms (G37): `NOT` ranks below `+`, so L61 leaves out ENV and
  FIN outputs; an NCAP_PASTY of 2.5 spreads at lags 1.5 and 0.5, rounded to
  2 and 1; an EPS past investment spreads as EPS. PASTYEAR is not settled in
  L1-137 (L160, L201 change it) and is checked with change 3. L35 writes
  only the QA log (open items).
- (3) ppmain.mod L138-191 with filparam.gms (G_OFFTHD) (1 Nov 2026):
  matches GAMS at the prep checkpoint on the symbols it settles
  (`ppmain_years_symbols`, 20 on every core model: no core model has
  INT_DEFAULT('PASTI'), so B, E, D, M, PASTYEAR and PASTMILE are checked
  here; with it, L200-207 change them and change 5 checks them) on the five
  core models, reduce_off and as_run, and on demo12 in CI; TIM-bau was
  probed locally (results stay on James's machine). demo12 runs with OBJ
  MOD, so it takes the alternative objective's periods (L150-155); the
  other four drop ALTOBJ to 0; demo12, TIMES-NZ and OTUS9r pass the OBLONG
  check. No core model has G_OFFTHD data. Eight crafted demo12 states
  ("altobj", "altobj_mod", "offthd5", "offthd1", "offthd2", "offthd14",
  "offthdneg", "offthdeps", test/unit/ppmain_years_case.jl) run through an
  unchanged copy of L1-191 by GAMS 54.6.1 match on the 20 symbols L138-191
  writes (CI). GAMS confirms (G38): `$` binds before `-` at L154; leads and
  lags on T move along the milestones; `ROUND(EPS)` is 0, so an EPS option
  at G_OFFTHD('0') counts as none (my first version extrapolated both ways
  there; fixed). The OBLONG ABORT (L159) is a Julia error, tested in Julia
  only.
- (4) timslice.mod with pp_off.mod (1 Nov 2026): matches GAMS at the prep
  checkpoint on the 24 symbols it writes (`timslice_symbols`; ppmain.mod
  L199-248, preppm.mod L1-217 with its includes, prep_ext.vda, resloadc.vda
  and powerflo.vda only read them) on the five core models, reduce_off and
  as_run, and on demo12 in CI; TIM-bau was probed locally (results stay on
  James's machine). The core models reach three levels, four (TIMES-NZ:
  WEEKLY), external regions (L18, L43) and season fractions filled from
  their children (L45-46); none has TS_OFF, DYNTS, RP_UPR/RP_UPT, zero
  fractions, fractions to normalise or TS_CYCLE data. Six crafted demo12
  states ("norm", "zerofrac", "tsoff_first", "tsoff_later", "dynts", "uc",
  test/unit/timslice_case.jl) run through an unchanged copy of ppmain.mod
  L1-196 by GAMS 54.6.1 match on the 24 symbols (CI); the replay needs
  `$onMulti` (`gams_replay(...; onmulti=true)`), as L34 declares TS_OFF
  again. GAMS confirms (G39): a LOOP's `$`-condition is read element by
  element (L63: RLUP holds the next coarser level only); `SET TS_OFF //;`
  under `$ONMULTI` keeps the data; RS_UP and JS take the G26 pairing (child
  first, parent last). The `uc` case does not make L118's MOD argument
  negative; MOD's sign rule is from (1b). The ABORTs (L24, L74) are Julia
  errors, tested in Julia only. pp_off.mod is split into `pp_off_fil` and
  `pp_off_periods` for its four later callers.
- (5) ppmain.mod L199-247 (2 Nov 2026): matches GAMS at the prep checkpoint
  on the symbols it settles (`ppmain_rtp_symbols`: PRC_NOFF, RTP_OFF, VNT,
  COEF_RTP and RTP on every core model, RVP on OTCGEN and OTNYC, which have no
  PRC_VINT; fillvint.gms L18 and preppm.mod L61 add vintage years to RVP) on
  the five core models, reduce_off and as_run, and on demo12 in CI; TIM-bau
  was probed locally (results stay on James's machine). PRC_YMAX is not
  compared at prep (prep_ext.vda L48 clears it). Every core model has
  NCAP_START (L215-225); TIMES-NZ, OTNYC and OTUS9r have delayed processes
  with past investment (L227-231); none has INT_DEFAULT('PASTI'), user
  PRC_NOFF ranges or G_OFFTHD data. Three crafted demo12 states ("pasti",
  "noff", "noff_offthd", test/unit/ppmain_rtp_case.jl) run through an
  unchanged copy of ppmain.mod L1-247 by GAMS 54.6.1 match on the 18 symbols
  the block writes, PRC_YMAX, TRACKP, UNCD1 and PASTSUM included (CI); the
  replay needs %RL% (setglobs.gms L317) for the QA line at L230. GAMS
  confirms the known rules: `3+0.1+1-1` at L202 keeps its rounding
  (3.0999999999999996), a non-integer NCAP_START leads by the rounded amount
  (G29: 2012.4 gives the range BOH-2011, 2012.6 BOH-2012), SMAX over nothing
  is -INF (G31) and stays in PRC_YMAX. A delayed process with past investment
  keeps the RTP_OFF of its delayed periods (L224) while L231 puts them back
  in RTP. No new discrepancy entry.
- (6a) preppm.mod L1-212 (2 Nov 2026): matches GAMS at the prep checkpoint on
  the 109 symbols it settles (`preppm_symbols`: every parameter its macro
  calls interpolate but NCAP_TLIFE and NCAP_ILED, which prep_ext.vda L66-67
  changes; the year sets; the merged OBJ_COMNT/OBJ_COMPD and UC_COM; the
  flags and defaults; the prepret.dsc and fillvint.gms sets; RTP and RVP) on
  the five core models, reduce_off and as_run, and on demo12 in CI; TIM-bau
  was probed locally (results stay on James's machine). The core models reach
  options -1, 1, 2, 3, 5 and 15, the bounds' default 10 (years inside a
  period moved to the milestone), cost options (NCAP_COST, NCAP_FOM,
  ACT_COST), FLO_MARK (TIMES-NZ), PRC_VINT (demo12, TIMES-NZ, OTUS9r), the
  COM and UC merges, and prepret.dsc with RCAP_BND and refits (OTUS9r). %PGPRIM%
  is 'ACT' by default, so %RETIRE% is YES in every run (initmty.mod L454).
  Four crafted demo12 states ("fill_opts", "prep_opts", "costs_uc_ret",
  "nointerp", test/unit/preppm_case.jl), run through unchanged copies of
  ppmain.mod L1-247 and preppm.mod L1-212 by GAMS 54.6.1, match on the 125
  symbols the block writes, the macros' scratch (UNCD7, MY_ARRAY, MY_FIL2 and
  the scalars) included (CI); under G_NOINTERP no macro runs, so Z and MY_F
  keep what ppmain.mod L215 and timslice.mod L71-77 left, which changes 4-5 do
  not keep, and are not compared in that case. GAMS confirmed that an empty
  data statement makes a symbol DEFINED (G40: with PRC_REFIT data,
  prepret.dsc runs on without retirement bounds) and that CARD of a string is
  its length (G41); the GAMS replay now declares such symbols without data
  (`bare`). Refused: currency conversion (curex.gms; no core model has
  it, JRC-EU-TIMES-cli_ll does: change 26), %INTEXT_ONLY% and %PREP_ANS% YES, %RETIRE% other than YES. On OTUS9r
  the step takes about 105 s.
- (6b) preppm.mod L213-217 (main_ext.mod prep_ext: prep_ext.dsc exits, then
  prep_ext.vda with equcrtp.vda PREP_EXT) ends the init -> prep segment: from
  GAMS's init dump through every translated step, TIMES.jl matches the prep
  dump on every set and parameter (821 on demo12, TIMES-NZ, OTCGEN and
  OTNYC, 822 on OTUS9r; PUTOUT, PUTGRP and ERRLEV left out, open items) on
  the five core models, reduce_off and as_run, and on demo12 in CI; MY_SUM
  is now kept by `timslice!`. The core models reach the ACT_EFF groups
  (RPG_1ACE on OTUS9r), the VDA fill-ins (NCAP_AFC, VDA_EMCB, VDA_FLOP,
  FLO_EMIS), the PRC_RESID run-down and RTP_CPTYR (every model; PRC_RESID
  options on OTUS9r), COM_LIM 'FX' (TIMES-NZ, OTCGEN, OTUS9r) and the
  dynamic process bounds (OTUS9r). Three crafted demo12 states ("vda_resid",
  "uc_bounds", "dynuc", test/unit/prep_ext_case.jl), run through
  ppmain.mod L1-247, preppm.mod L1-212 and prep_ext.vda by GAMS 54.6.1,
  match on 159 symbols each (CI): PRC_RESID options 5 and 15, a year as the
  '0' value, the G_TLIFE run-down, NCAP_AFAC/NCAP_AFCS, ACT_FLO, the
  unit-commitment parameters, UC_FLOBET, COM_CSTBAL, FLO_ASHAR, RPC_CAPFLO,
  cost-neutral ILEDs (NCAP_BND 'N') and PRC_DYNUC with every side and
  option. GAMS confirmed how `SUM(COM_TYPE(CG(R)),1)` counts (G42, L71).
  Refused: STAGES, POWERFLO, WAVER YES, %VINTOPT% 1, GR_VARGEN data, the
  ECB, MACRO, ETL, CLI, ABS and MCA extensions, and UC_ACTBET data (whether
  UC_FLOBET is DEFINED then depends on the DD files). On OTUS9r the step
  takes about 3 min, OTCGEN 80 s.
- (7a) preppm.mod L218-252 (the twelve preshape.gms calls, PRC_MARK from
  FLO_MARK, DATAYEAR) and ppmain.mod L249-328 (RT_PP, DUR_MAX, EOHYEARS,
  EACHYEAR, PERIODYR, the commodity groups and RC, NRG_GMAP, PRC_CG,
  RPC_CAPFLO, the primary and shadow primary groups) match the prelv dump on
  the 39 symbols they settle (`preppm_shape_symbols`,
  `ppmain_topo_symbols`; DEM, PRC_CG, RPC_PG, UNCD7, RXX and the scratch Z,
  F, TRACKP are changed again later in the segment) on the five core models,
  reduce_off and as_run, and on demo12 in CI. No core model has data for
  the preshape parameters, NCAP_ICOM, NCAP_OCOM or NCAP_COM, a commodity
  group named like a commodity, a user PRC_SPG or a trade process with
  untraded PG commodities; FLO_MARK into PRC_MARK is TIMES-NZ's. Two crafted
  demo12 states ("shapes", "topology", test/unit/ppmain_topo_case.jl), run
  through unchanged copies of ppmain.mod L1-247 and L249-328, preppm.mod
  L1-212 and L218-252 and prep_ext.vda by GAMS 54.6.1, match on 192 symbols
  each (CI): every preshape.gms option (the default intra-period move, 1-5,
  2 without data, 11, 15, 1012, -1), rounding and EPS in the step, the
  group-integrity removal (L272-277), L301, a user and a material shadow
  group, and the capacity-related flows. GAMS confirmed that MOD keeps the
  sign of its first argument (G43). Refused: %VINTOPT% 1 (L245-251). L253
  (`SET SUBT(T) / SET.T /`) is a compile-time data statement, in every dump.
- (7b) ppmain.mod L329-460 (the commodity and process timeslice levels:
  levels a region lacks, COM_TS/COM_TSL, RCS, RCS_COMTS, COM_OFF through
  pp_off.mod, RTC, RTCS_VARC, COM_PEAK/COM_PKTS, PRC_TS/PRC_TSL, storage
  (RP_SGS, PRC_MAP, RP_STG), the shadow levels (RPS_S1, RPS_S2, PRC_SGL),
  RPS_PRCTS, RP_PGFLO, RPC_STG, PRC_NSTTS, RPCS_VAR) matches the prelv dump
  on the 24 symbols it settles (`ppmain_tslvl_symbols`; COM_BNDPRD,
  TS_ARRAY, RXX, PRC_ACT, TRACKP, TRACKPC, F and Z are changed again later in
  the segment) on the five core models, reduce_off and as_run, and on demo12
  in CI. The core models reach WEEKLY levels (TIMES-NZ), peak timeslices
  given (OTCGEN, OTNYC, OTUS9r) and not (demo12), storage (TIMES-NZ, OTCGEN,
  OTNYC, OTUS9r) and SGS storage (OTUS9r). Two crafted demo12 states
  ("levels", "offpeak", test/unit/ppmain_tslvl_case.jl), run through
  unchanged copies of ppmain.mod L1-247 and L249-460, preppm.mod L1-212 and
  L218-252 and prep_ext.vda by GAMS 54.6.1, match on 217 symbols each (CI):
  a level moved up and one kept (the count rule of L336-337), user COM_TS
  and PRC_TS (the first timeslice sets the level, G30; timeslices removed or
  left out, RCS), COM_OFF ranges, COM_PKTS moved up and down, a group
  COM_PEAK, a peak commodity outside RC, and night storage at DAYNITE and
  ANNUAL with SGS and STS. GAMS confirmed how L380's nested loop domain
  matches labels (G44). On OTUS9r the step takes about 50-60 s.
- (8a) ppmain.mod L461-611 (lifetimes and lead times, refits, COEF_RPTI,
  VNT and RTP_CPTYR, capacity bounds, the periods without new capacity,
  RTP_VARA with PRC_AOFF, RTPC, RTPCS_OUT with PRC_FOFF, PRC_SIMV, RPC_PG,
  RP_STD, RPC_ACT, CHP, PRC_CAPACT, PRC_ACTFLO, RP_PGACT) matches the prelv
  dump on the 30 symbols it settles (`ppmain_life_symbols`; NCAP_TLIFE and
  PRC_ACTFLO are changed again by pp_prelv.vda, RVP only with TS_OFF data)
  on the five core models, reduce_off and as_run, and on demo12 in CI. The
  core models reach %CTST% **0 (demo12, TIMES-NZ, OTUS9r: G_ILEDNO -1) and
  empty (OTCGEN, OTNYC, with lead times), ALTOBJ 1 (demo12) and 0,
  lifetimes beyond AGE (TIMES-NZ), refits with PRC_RCAP (OTUS9r), capacity
  bounds (TIMES-NZ, OTCGEN, OTNYC, OTUS9r), STK (OTCGEN, OTNYC) and CHP
  (OTCGEN). Three crafted demo12 states ("life", "altobj", "validate",
  test/unit/ppmain_life_case.jl), run through unchanged copies of ppmain.mod
  L1-247 and L249-611, preppm.mod L1-212 and L218-252 and prep_ext.vda by
  GAMS 54.6.1, match on 233 symbols each (CI): short and EPS lifetimes,
  rounded and dropped lead times, past investment on a milestone (PHYR),
  refit options, every capacity-bound path, NCAP_BND FX EPS, PRC_AOFF,
  PRC_FOFF, a PG commodity flagged non-interpolated, OBJ LIN (the relaxed
  capacity transfer), %VALIDATE% and PRC_SIMV. The replay now sets %OBLONG%
  (OBJ MOD) as initmty.mod L427 does, so ppmain.mod L159 is checked there
  too. IFQ is 1 unless a region is named like a commodity type (prep_ext.vda
  L71), so the `IFQ<10` branch of L528 is the only one data can reach. On
  OTUS9r the step takes about 4 min, OTCGEN 100 s (not profiled).
- (8b) pp_prelv.vda (ppmain.mod L615, with pp_lvlfc.mod for FLO_FR) ends
  the prep -> prelv segment: from GAMS's prep dump through every translated
  step, TIMES.jl matches the prelv dump on every set and parameter (821;
  PUTOUT, PUTGRP and ERRLEV left out, open items) on the five core models,
  reduce_off and as_run, and on demo12 in CI. The core models reach
  NCAP_TLIFE for RESID (every model), the ACT_EFF filter of VDA_FLOP with
  KEEP_FLOF, ACT_FLO, RPC_AFLO and RP_XRED (OTUS9r, OTNYC), the VDA_FLOP
  groups, FLO_EMIS into FLO_SUM, IRE_FLOSUM (TIMES-NZ, OTCGEN) and FLO_EFF
  (OTCGEN's CHP), and the dummy imports out of TOP_IRE (every model). Two
  crafted demo12 states ("flofr", "groups", test/unit/pp_prelv_case.jl), run
  through unchanged copies of ppmain.mod L1-247 and L249-614, preppm.mod
  L1-212 and L218-252, prep_ext.vda and pp_prelv.vda by GAMS 54.6.1, match on
  246 symbols each (CI): FLO_FR copied, aggregated and inherited
  (pp_lvlfc.mod) with its 'N' fractions and RVPCSL, NCAP_CHPR 'N', the 'N'
  defaults of COM_BNDNET and COM_BNDPRD, IRE_BND (NE), FLO_SHAR of a storage
  process, %SHELL% ANSWER and the VDA_FLOP group paths. GAMS showed that
  `OPTION a < b` compares domains as declared, not through aliases (G45,
  refining G26). Refused: TS_OFF data (dynslite.vda, no core model has any)
  and %POWERFLO% YES. On OTCGEN the step takes about 2-2.5 min, OTUS9r
  3-3.5 min (not profiled). The every-symbol check found one slip in 8a's
  code, fixed here: F keeps an EPS (ppmain.mod L526-531).
- (9) ppmain.mod L616-682 starts the prelv -> ppm segment in two probe
  steps: pp_qafs (pp_qafs.mod, the FLO_SHAR checks) and ppmain_dflt (SHAPE
  and MULTI with filshape.gms and filparam.gms, the defaults, the
  capacity-only flows). At the ppm checkpoint they are compared on the 17-19
  symbols nothing later changes, PASS on the five core models, reduce_off
  and as_run, and on demo12 in CI. FLO_SHAR (pp_chp.mod, pp_lvlbr.mod),
  NCAP_CHPR and NCAP_BPME (pp_chp.mod, on CHP models), RTP_GRP, UC_CAPFLO,
  RPC_NOFLO, RPCS_VAR and the scratch change again before ppm, so a new
  replay check (scripts/m13_replay.jl) runs GAMS on ppmain.mod L616-682 from
  each core model's own prelv dump and compares every symbol the lines
  write (34) at L682 (PASS on the five core models, both variants), and
  lists the checks GAMS's QA log shows. The core models reach the sum of
  fixed shares (TIMES-NZ 28 groups, OTUS9r 24), the FX+UP auto-relaxation
  (OTNYC 50, OTUS9r 864), the STG_EFF default (OTCGEN, OTNYC, OTUS9r) and
  the CHP default (OTCGEN); none reaches FX with LO/UP, the FX+LO excess or
  a share outside its group, and none has SHAPE, MULTI, COM_ELASTX,
  NCAP_OCOM, NCAP_ICOM or RPC_NOFLO data. Three crafted demo12 states ("qafs", "dflt",
  "notgrp", test/unit/ppmain_dflt_case.jl) start from the prelv dump, so
  GAMS 54.6.1 runs only ppmain.mod L616-682 on them; they match on 34
  symbols each (CI). GAMS showed that a scalar `$`-condition in a loop
  domain is evaluated per member, so pp_qafs drops only the first share
  above the limit, and that `$` binds before NOT (G46); and that a `$IF`
  with nothing after its condition applies to the next line, as %SHARELAX%
  NO needs (G47). The steps take under a minute on OTUS9r.
- (10) ppmain.mod L683-797 is one probe step, ppmain_tsattr: the commodity
  attributes levelled to COM_TS (pp_lvlfc.mod, `lvlfc!`), COM_IE and
  COM_FR defaulted, COM_FR summed and normalised, RS_FR and RTCS_FR, the
  elastic demand steps, NCAP_AF levelled to PRC_TS (pp_lvlbr.mod,
  `lvlbr!`) and defaulted with PRC_TS, RPCS_VAR and RTPCS_OUT, and
  pp_lvlpk.mod. At the ppm checkpoint it is compared on the 15-18 symbols
  nothing later changes, among them RPCS_VAR, which change 9 left to the
  replay (NCAP_AF and PRC_TS without RP_STS, NCAP_PKCNT without CHP,
  RPC_PKC with %REDUCE% NO and no STG_SIFT): PASS on the five core models,
  reduce_off and as_run, and on demo12 in CI. DEM (L945), FLO_PKCOI (L808,
  L817), RTPCS_OUT (L1062, cleared at L1350) and RPC_PKF (pp_reduce.red
  L185, which follows its REDDONE label and so runs without REDUCE too)
  change again before ppm, so the replay check now runs ppmain.mod L616-797
  and compares every symbol the lines write (65) at L797: PASS on the five
  core models, both variants. GAMS's QA log shows the COM_FR normalisation
  on demo12 (2 commodities) and TIMES-NZ (16); NCAP_AFS (TIMES-NZ),
  OBJ_COMNT (TIMES-NZ, OTUS9r) and storage processes (all but demo12) are
  reached; no core model has an NCAP_AF bound conflict, nor COM_ELAST,
  COM_BPRICE, COM_BQTY, COM_PKFLX, OBJ_COMPD, PRC_PKAF or PRC_PKNO data.
  Three crafted demo12 states ("com", "af", "pk",
  test/unit/ppmain_tsattr_case.jl) cover those paths, 65 symbols each at
  L797 (CI). The replay showed two things the source does not make plain:
  the `IF(Z, ...)` that pp_lvlbr.mod L27 opens closes only at the end of
  L31, so a value below a target timeslice is neither inherited down nor
  levelled from (the indentation suggests otherwise; only the scratch Z
  showed it, as no such value has targets below it); and L729 divides for
  every timeslice, so an ANNUAL COM_FR of 0 stops GAMS even where COM_FR
  has no record (G48): a commodity with COM_FR needs it in every milestone.
  The step takes about 3 minutes on OTUS9r (2.1 million GAMS records
  compared; the gams_sort! of the large symbols dominates, not profiled).
- (11a) ppmain.mod L800-821 is the probe step ppmain_flo: the eight
  pp_lvlfc.mod calls for the flow attributes (FLO_COST, FLO_DELIV, FLO_SUB,
  FLO_TAX with %11 N, FLO_PKCOI, FLO_BDLVL twice, ACT_FLO with %11 0),
  for which `lvlfc!` became the general `pp_lvlfc!` (all its arguments
  but %6 S2; change 10's calls re-checked), the FLO_PKCOI default of 1, and
  pp_chp.mod. Change 11 is split in two (11a, 11b) like 6, 7 and 8. At the
  ppm checkpoint it is compared on the 13-14 symbols nothing later changes
  (NCAP_PKCNT, NCAP_CHPR and NCAP_BPME, which changes 9 and 10 left to the
  replay when CHP has members, are now among them): PASS on the five core
  models, reduce_off and as_run, and on demo12 in CI. The replay check now
  runs ppmain.mod L616-821 and compares 82 symbols at L821: PASS on the five
  core models, both variants. The core models reach FLO_DELIV (TIMES-NZ,
  OTUS9r), ACT_FLO (OTUS9r), the FLO_PKCOI default (all) and CHP with FX
  ratios and no NCAP_CDME (OTCGEN, 8 processes). Three crafted demo12 states
  ("flo", "chp", "chpnrg", test/unit/ppmain_flo_case.jl) cover the rest of
  pp_lvlfc.mod's arguments (the year-'0' flag of %11 N and its deletions, a
  year outside DATAYEAR, the group and commodity calls of FLO_BDLVL) and of
  pp_chp.mod (NCAP_CDME and NCAP_BPME, slopes below and above 1,
  back-pressure units through COM_LIM 'N', FX with LO, FLO_EFF, a
  one-commodity primary group, the share over NRG, NCAP_PKCNT), 82 symbols
  each at L821 (CI). pp_chp.mod L23 replaces PRC_ACT and L71 clears it,
  so PRC_ACT is empty after L821 until pp_reduce.red L10 sets it again.
  The step takes about 4 minutes on OTUS9r and 3 on OTCGEN (copying and
  sorting FLO_SUM and FLO_SHAR, not profiled).
- (11b) ppmain.mod L823-843 is the probe step ppmain_flofs: pp_lvlff.mod
  and pp_lvlfs.mod (FLO_FUNC and FLO_SUM levelled), FLO_SUM and IRE_FLOSUM
  from PRC_ACTFLO for the processes in RPC_ACT, pp_lvlbr.mod for FLO_SHAR
  (its general `lvlbr!` with %2 ',C,CG', %5 1, %6 0, %7 C,) and
  eqflomrk.mod with RPC_NOFLO. At the ppm checkpoint it is compared on the
  8-10 symbols nothing later changes (FLO_SUM only without VDA_EMCB,
  ppm_ext.vda L20; IRE_FLOSUM only without records at %PGPRIM%, ppmain.mod
  L924-926): PASS on the five core models, reduce_off and as_run, and on
  demo12 in CI. The replay check now runs ppmain.mod L616-843 and compares
  101 symbols at L843: PASS on the five core models, both variants. The
  core models reach FLO_FUNC and the FLO_SUM levelling (OTUS9r), the
  PRC_ACTFLO sums (all), FLO_SHAR below and above the flow timeslices (all)
  and PRC_MARK from FLO_MARK (TIMES-NZ). Two crafted demo12 states ("ffs",
  "mark", test/unit/ppmain_flofs_case.jl) cover the rest, 101 symbols each
  at L843 (CI). The replay confirmed that eqflomrk.mod L27's `T--ORD(T)`
  is the last milestone (G49). pp_lvlfs.mod L42 runs after L41 clears
  FSCKS and so does nothing, in GAMS as here. The step is slow on the large
  models: about 11-12 minutes on OTCGEN and 7.5 on OTUS9r (the FLO_SHAR
  and FLO_SUM levelling; to be profiled). Profiled: the time went to
  gams_sort! in the two gput! of FLO_SUM, which ranked the labels at every
  comparison; ranked once per key it gives the same order about 140 times
  faster (PR #35, separate).
- (12) ppmain.mod L846-933 is the probe step ppmain_ire: IRE_PRICE and
  IRE_FLOSUM levelled (pp_lvlfc.mod), IRE_FLO levelled (pp_lvlif.mod), the
  trade indicators, the marketplaces and their import commodities, links
  and IRE_FLO, RPC_EQIRE and RPC_MARKET IMP, RTPC of shut-down periods,
  RP_AIRE, IRE_FLOSUM of the activity moved to the PG commodities and the
  IRE_FLO defaults. At the ppm checkpoint it is compared on the 11 symbols
  nothing later changes: PASS on the five core models, reduce_off and
  as_run, and on demo12 in CI. The replay check now runs ppmain.mod L616-933
  and compares 112 symbols at L933: PASS on the five core models, both
  variants. Two crafted demo12 states ("ire", "dist",
  test/unit/ppmain_ire_case.jl) make REG1 a marketplace (two import
  commodities in REG2) and, in "dist", a distribution process, and level
  the trade attributes, 112 symbols each at L933 (CI). The replay needs
  %PGPRIM% as initmty.mod L138 sets it ("'ACT'", quoted, which COM holds as
  a member, L141), now set in scripts/ppmain_replay.jl.
- (13a) ppmain.mod L936-1001 is the probe step ppmain_bnd: the commodity
  subsets and COM_LIM defaults, the trade timeslice and commodity
  conversions (IRE_TSCVT; IRE_CCVT, its reverse from `OPTION RC_RC <
  IRE_CCVT`, which swaps the region and commodity pairs, G26), the five
  pp_lvlbd.mod calls and FLO_BND and ACT_BND from FLO_BDLVL; TIMES-MACRO and
  TIMES-MICRO (L962-963) refused. Change 13 is split in two (13a, 13b). At
  the ppm checkpoint it is compared on the 16-17 symbols nothing later
  changes (DEM, which change 10 left to the replay, among them; ACT_BND
  only with %REDUCE% NO): PASS on the five core models, reduce_off and
  as_run, and on demo12 in CI. The replay check now runs ppmain.mod
  L616-1001 (under $onMulti, as pp_lvlbd.mod declares BDVAL and TS_BD at
  each of its five inclusions) and compares 126 symbols at L1001: PASS on
  the five core models, both variants. One crafted demo12 state ("bnd",
  test/unit/ppmain_bnd_case.jl) covers the aggregation of pp_lvlbd.mod
  (sums, FX where LO and UP meet, a value at the target and below, an UP
  not covering the target, negative bounds), the rate bounds and the
  reverse conversion, 126 symbols at L1001 (CI). With the faster
  gams_sort! (PR #35) the replayed chain ppmain.mod L616-1001 takes 32 s in
  TIMES.jl on OTUS9r, GAMS 60 s (it took 17 minutes before).
- (13b) ppmain.mod L1003-1056 is the probe step ppmain_cum: the
  cumulative bounds moved from BOH and EOH to the first and last years
  (`BOHYEAR+BEOH(BOHYEAR)` leads along BOHYEAR: BOH is 1960, EOH 2200 in
  the suite), UC_CUMACT and ACT_CUM as flows of %PGPRIM%, RPC_CUMFLO and
  RC_CUMCOM, and the commodities on the RHS of the balance (RC_AGP,
  RTC_NET, RTC_PRD, the COM_CSTNET and COM_CSTPRD flags at year '0' and
  the last timeslice). At the ppm checkpoint it is compared on the 15
  symbols nothing later changes (RHS_COMBAL and RHS_COMPRD are changed
  again at L1067 and L1209-1226): PASS on the five core models, reduce_off
  and as_run, and on demo12 in CI. The replay check now runs ppmain.mod
  L616-1056 and compares 140 symbols at L1056: PASS on the five core
  models, both variants. The core models reach ACT_CUM up to EOH (demo12)
  and COM_AGG; two crafted demo12 states ("cum", "lin",
  test/unit/ppmain_cum_case.jl) cover the other cumulative bounds, the cost
  flags and the bound checks of L1051 and L1055 (CI).
- (14) ppmain.mod L1058-1099 is the probe step ppmain_stg: RTPCS_OUT of the
  storage flows, the demand-sifting storages (TRACKPC from STG_SIFT,
  RPC_SPG, RPC_STGN, RPC_LS, STG_SIFT levelled to the sifting level,
  ACT_TIME), the flexible storages (RPS_STG, RP_STS, PRC_TS, PRC_STGTSS,
  STG_LOSS, RP_STL, NCAP_AF), STG_LOSS and STG_SIFT levelled (pp_lvlfc.mod,
  now with %6 S2) and STG_LOSS converted to year fractions. At the ppm
  checkpoint it is compared on the 12-13 symbols nothing later changes
  (NCAP_AF and PRC_TS, which change 10 compared only without RP_STS, now
  always; RPC_PKC with %REDUCE% NO): PASS on the five core models,
  reduce_off and as_run, and on demo12 in CI. The replay check now runs
  ppmain.mod L616-1099 and compares 151 symbols at L1099: PASS on the five
  core models, both variants. The core models reach demand sifting
  (TIMES-NZ), a flexible storage (OTNYC) and STG_LOSS (OTCGEN); a crafted
  demo12 state ("stg", test/unit/ppmain_stg_case.jl) makes a flexible
  stockpile storage, 151 symbols at L1099 (CI).
- (15a) ppmain.mod L1101-1179 with prepxtra.mod UCINT (L61-77) is the
  probe step ppmain_uc: the year specifications through %DFLBL% (UC_T_SUM
  filled in between, UC_T_EACH/UC_T_SUCC on every milestone, years moved to
  their milestones), UC_RHSRTS levelled to the UC timeslice levels (UC_TSL,
  UC_DS, R_UC), the obsolete UC_RHSS/UC_RHSRS, the UC_R_EACH/UC_R_SUM,
  UC_TS_EACH/UC_TS_SUM and UC_T_EACH/UC_T_SUM defaults, the cumulative and
  dynamic UCs (UC_ATTR, UC_DYNDIR, UC_T_SUCC), RS_PREV and G_UDS. Change 15
  is split in two like 11 and 13: 15b is L1181-1226 with pp_lvlus.mod. At
  the ppm checkpoint 15a is compared on the 13-15 symbols nothing later
  changes (UC_R_EACH and UC_R_SUM only without UC_DYNBND, which equcrtp.vda
  PPM_EXT changes them under; OTUS9r has UC_DYNBND): PASS on the five core
  models, reduce_off and as_run, and on demo12 in CI. The replay check now
  runs ppmain.mod L616-1179 and compares 172 symbols at L1179: PASS on the
  five core models, both variants. The core models reach dynamic UCs
  (TIMES-NZ, OTCGEN, OTNYC), UC_T_SUCC (TIMES-NZ, OTCGEN, OTUS9r) and
  UC_R_SUM (TIMES-NZ, OTUS9r); none has a UC timeslice level (UC_TSL) or a
  %DFLBL% year. A crafted demo12 state ("uc", test/unit/ppmain_uc_case.jl)
  covers those, the obsolete UC_RHSS, the cost-attribute mapping and the
  CUMSUM/SYNC/ANNUL attributes, 172 symbols at L1179 (CI). The UC_T_SUCC
  year given off a milestone (2012) is kept beside the milestone added for
  it (2010), as GAMS keeps it.
- (15b) ppmain.mod L1181-1226 with pp_lvlus.mod is the probe step
  ppmain_ucmap: the UC group maps (UC_MAP_FLO, UC_MAP_IRE, UC_QAFLO for the
  trade processes in UC_FLO and the other processes in UC_IRE, UC_CAPFLO,
  UC_GMAP_C, UC_GMAP_P through UC_JMAP), the dynamic attributes of COMCON
  groups, RTP_VARP for UC capacities, RHS_COMBAL and RHS_COMPRD for UC
  commodities, UC_ACT, UC_FLO, UC_IRE and UC_COM levelled to the process
  and commodity timeslices (pp_lvlus.mod: aggregated where the UC is finer
  than the finest level of the process or commodity, inherited where it is
  coarser, ANNUAL copied down), and RCS_COMBAL/RCS_COMPRD. pp_lvlus.mod
  carries the scalar F from one record to the next and from one call to
  the next (L17 compares with the F the previous record left), so the
  translation keeps F as running state, in GAMS's loop order. UC_JMAP is
  not empty on entry: with UC_DYNBND, equcrtp.vda INIT_EXT L59 left its
  J='1' tuples there, and L1198-1200 add to them, so UC_GMAP_P (L1201) also
  maps the processes of the dynamic UC bounds (OTUS9r: 1,693 tuples; the
  replay found this). At the ppm
  checkpoint it is compared on the 10-17 symbols nothing later changes
  (UC_GMAP_P, UC_ON, UC_ACT and UC_COM only without UC_DYNBND, which
  equcrtp.vda PPM_EXT changes them under; RHS_COMPRD only with %REDUCE% NO,
  pp_reduce.red L161; RHS_COMBAL and RCS_COMBAL only without GR_VARGEN,
  resloadc.vda): PASS on the five core models, reduce_off and as_run, and
  on demo12 in CI. The replay check now runs ppmain.mod L616-1226 and
  compares 185 symbols at L1226: PASS on the five core models, both
  variants. The core models level UC_ACT (TIMES-NZ, OTUS9r), UC_FLO (all),
  UC_IRE (OTNYC, OTUS9r) and UC_COM (OTCGEN, OTNYC, OTUS9r). A crafted
  demo12 state ("ucmap", test/unit/ppmain_ucmap_case.jl) covers
  aggregation, inheritance and the ANNUAL copy for all four attributes, both
  UC_QAFLO checks, a COMCON group and UC_DYNBND, 185 symbols at L1226 (CI).
  Not reached by any model: L17's true branch (a group already marked OUT
  meeting a timeslice finer than F), which needs a timeslice level between
  the UC's and the process's own that no suite model has.
- (16) ppmain.mod L1228-1333 is the probe step ppmain_blend: the blending
  block. No suite model has blending data (BL_TYPE, OPR), so it is refused
  (UnportedError) when BL_TYPE or OPR has data. Without them every statement
  but one acts on an empty set: BLE_SPE comes from BL_TYPE and the other
  BLE_* sets, BL_UNIT, BLE_BAL and RU_CVT follow from it; BLE_INP is only
  declared (its assignments are comments), so PEAKDA_BL is never written;
  RU_FEQ runs over OPR. The one that acts, the REFUNIT default (L1251), is
  translated. At the ppm checkpoint it is compared on the 13 symbols the
  block writes: PASS on the five core models, reduce_off and as_run, and on
  demo12 in CI. The replay check now runs ppmain.mod L616-1333 and compares
  198 symbols at L1333: PASS on the five core models, both variants. A
  crafted demo12 state ("blend") keeps a given REFUNIT (CI).
- (17a) ppmain.mod L1336-1357 with pp_reduce.red is the probe step
  ppmain_reduce: RVP and RTP_VARA, then pp_reduce.red in its three modes
  (%REDUCE% NO stops after L11; any other value, unset included, after L56;
  YES runs it all: PRC_CAP, PRC_ACT, the emission flows substituted, the
  flows substituted by the activity, NO_ACT, the FLO_FUNC/FLO_SUM
  substitution, the processes turned off by zero activity bounds, the
  single producers and consumers, RTP_VARA), then RTPCS_VARF and
  RTP_VINTYR. Change 17 is split like 11, 13 and 15: 17b is cal_red.red,
  checked on the matrix. Refused: %ETL% YES with REDUCE YES (L43, SEG),
  dynslite.vda (L188, as in 8b) and %MACRO% YES (L1354). RP_AFB is a
  parameter, so `OPTION RP_AFB < NCAP_AF` stores the number of NCAP_AF
  records (G31). At the ppm checkpoint it is compared on the 18 symbols
  nothing later changes (ppm_ext.vda, change 18, changes PRC_ACT, RP_AFB,
  FS_EMIS, RPC_EMIS, NO_ACT, RP_XRED, RPCG_PTRAN, RPC_FFUNC, RPCC_FFUNC,
  RTPS_BD and RVP): PASS on the five core models, reduce_off (%REDUCE% NO)
  and as_run (%REDUCE% YES), and on demo12 in CI. RPC_PKF, ACT_BND and
  RHS_COMPRD, which earlier steps compared only without the reduction, are
  now compared in both variants. The replay check now runs ppmain.mod
  L616-1350 and compares 216 symbols at L1350 (L1351-1357 are the refused
  MACRO and the log file): PASS on the five core models, both variants. Two
  crafted demo12 states cover %REDUCE% YES with zero activity bounds
  ("yes") and %REDUCE% unset ("mid"), 216 symbols each (CI). In demo12 the
  dummy imports (IMPNRGZ) produce every commodity, so no commodity has a
  single producer and RTCS_SING ends empty.
- (18a) ppm_ext.dsc and ppm_ext.vda L11-58 with pp_actef.vda LVL are the
  probe step ppm_ext_actef: RP_UPL and RP_PL (ramping, partial loads), the
  FLO_SUMs of the VDA_EMCB emissions, the auxiliary flows that may be
  replaced (TRACKPG, FS_EMIT), ACT_EFF moved from ACT to the shadow group,
  the ACT_EFF groups (RPG_ACE, RPG_PACE, the singleton groups RPG_1ACE),
  ACT_EFF levelled to the process timeslices (UNCD7, the pp_lvlbr.mod
  average) and copied down from ANNUAL. Change 18 is split like 11, 13, 15
  and 17: 18b is ppm_ext.vda L59-169 with equcrtp.vda PPM_EXT, and ends the
  segment with the all-symbols check. ppm_ext.dsc exits (%DSC% NO: discrete
  capacities are refused at init_ext.dsc), and resloadc.vda (GR_VARGEN) is
  refused as at prep_ext.vda L38. `SQRT(ABS(EPS))` is EPS (G50). At the ppm
  checkpoint it is compared on the 20 symbols nothing later changes: PASS
  on the five core models, both variants, and on demo12 in CI. The replay
  check now runs ppmain.mod L616-1357 and ppm_ext.vda L11-58
  (`ppm_ext_replay`: the ppm_ext lines in a second file included as
  `VDA mod`, as main_ext.mod does) and compares 229 symbols at L58: PASS on
  the five core models, both variants (OTNYC has ACT_EFF below ANNUAL and
  on primary-group commodities, so the levelling and RPG_PACE are reached
  on a core model). Two crafted demo12 states ("ace": ACT_EFF below the
  process level, on a primary-group commodity and EPS on a shadow-group
  commodity, a VDA_FLOP record at prelv; "upl": ACT_UPS, ACT_LOSPL and
  NORTS) cover the rest, 229 symbols each (CI). pp_actef.vda L22 (SQRT of
  ACT_EFF on a shadow-group commodity) is unreachable in v4.9.7: it needs an
  RPG_ACE record whose group is a shadow-group commodity, which no line
  writes. NORTS on a milestone also zeroes COM_FR there (ppmain.mod L720),
  so the "upl" case sets it on a past vintage: on a milestone demo12's
  COM_FR stops GAMS with a division by EPS (G48).
- (18b) ppm_ext.vda L59-169 with equcrtp.vda PPM_EXT is the probe step
  ppm_ext, the last of the prelv -> ppm segment: the FLO_FUNCX shape
  indexes of the shadow group (L61-65), the ACT_EFF flows kept from the
  reduction (L67-75), the singleton ACT_EFF flows into RPC_FFUNC
  (L86-101), the commodity availabilities (NCAP_AFC and NCAP_AFCS levelled
  and split, RTPS_BD, RPS_CAFLAC, RPG_AFCX, PRC_SC, RP_STL, L104-142), the
  automatic NCAP_AFCS of ECT CHPs (L145-156), the NCAP_AFX and NCAP_AFM
  options (L159-164) and the dynamic UCs taken out of the standard UCs
  (equcrtp.vda L64-71). Refused: RP_FFSGG (L76-83, the stochastic
  extension) and dynslite.vda (L169, %DYNTS% YES with TS_OFF data).
  `OPTION VDA_CEH < NCAP_CEH` (L156) has the same domains on both sides, so
  it copies the values (G34), not the counts a projection gives (G31). It
  ends the segment, so it is compared on every set and parameter of the
  prelv dump at ppm (the QA scalars PUTOUT, PUTGRP, ERRLEV left out, as at
  the other segment ends): PASS on the five core models, both variants, and
  on demo12 in CI (821 symbols). With it the four segments input -> init ->
  prep -> prelv -> ppm all match GAMS at 1e-9, each from GAMS's state at
  its start. The replay check now runs ppmain.mod L616-1357 and the whole
  of ppm_ext.vda; GAMS runs five crafted demo12 states to the end of
  ppm_ext.vda: "ace" and "upl" (18a), "chp" (an ECT CHP: NCAP_CEH 2 on
  ELCTEGAS00), "afx" (NCAP_AFX and NCAP_AFM options) and "funcx"
  (FLO_FUNCX shape indexes), all PASS (CI).
- (17b) cal_red.red, the flow term of every equation under %REDUCE% YES
  (`cal_red!` in src/model/cal_red.jl; `cal_nored!` hands over to it, so
  every translated equation that takes `%cal_red%` uses it), with
  cal_fflo.mod's REDUCE path (L35-50, the balance and peak equations:
  processes without vintages at V = T, vintaged ones summed over
  RTP_VNTBYR) and bnd_flo.mod L34-39 (the bounds of a flow the activity
  replaces moved to VAR_ACT). %2 = COM is an alias of COM, so the SUM over
  RPC_ACT(R,P,%2) skips the ACTCG members pp_reduce.red L87 adds (G27).
  scripts/m11_probe.jl takes `--variant as_run` and sets REDUCE from the run
  file. Checked on the matrix (layer 2) and the optimum (layer 3): demo12
  as_run (REDUCE YES: 253 flows substituted by the activity, 237 by
  ACT_FLO, 92 emission flows whose source is such a flow, two vintaged
  processes) PASS, 3,233 rows, 4,485 columns, 18,375 nonzeros, the objective
  of CPLEX and HiGHS at 1e-6, now a CI fixture (`demo12_red`). The other
  core models need equation families M1.1 left untranslated (EQ_FLOMRK,
  EQ_STGIPS, the dynamic-RHS and VDA dynamic UCs, EQ_SLSIFT), in both
  variants, so they have no layer 2 yet. Not reached by demo12: the bounds
  moved to VAR_ACT (bnd_flo.mod L37-39, no FLO_BND on a reduced flow) and
  an emission whose source flow the activity replaces; translated as
  written.
- (17c) The two paths demo12 does not reach, on a crafted case (James, 5 Nov
  2026): TIMES_Demo-demo12_red17b (`reference/crafted.toml`, files in
  `reference/dd/demo12_red17b/`) adds VDA_EMCB OIL->INDCO2 and four FLO_BND
  records on REFEOIL00's OIL input, the activity flow of a process without
  vintages. Under REDUCE that gives FS_EMIT(REFEOIL00, INDCO2, INDCO2, OIL)
  with an RPC_ACT source (cal_red.red L37-38) and VAR_ACT bounds by
  bnd_flo.mod L37-39: LO by MAX (9000), UP by MIN below (12000) and above
  (the ACT_BND 19584.21 kept) the bound already set, FX (10436.1); with
  REDUCE off, VAR_FLO bounds (L25-27). Reference made with GAMS 54.6.1
  (CPLEX and HiGHS, both variants, OK); layer 2 PASS (as_run 3,233 rows,
  4,485 columns, 18,387 nonzeros; reduce_off 8,695 rows, 9,669 columns,
  31,403 nonzeros) and layer 3 PASS (CPLEX and HiGHS); the M1.3 chain from
  the input dump PASS on both variants. Now CI fixtures (`demo12_red17b`,
  `demo12_red17b_off`). The case found one bug in M1.1 code: the
  EQ(l)_FLOBND completeness check (`untranslated_families`) used an
  undefined `rtp_vara`, reached for the first time by FLO_BND data; fixed.

- (0) The pre-solve run's dumps lack the report-only symbols (the reports are
  skipped at maindrv.mod L114), so the checkpoint `ppm/` has fewer symbols
  than the solve run's; on demo12 the 824 sets and parameters both hold are
  equal at 1e-9 (GAMS 54.6.1, cloud, against the licensed GAMS 52.1.0
  reference of 21 Oct).
- (0) `execute_unload` without a symbol list writes every symbol of the
  compiled program, so the input dump also holds symbols declared later in
  the source, with their compile-time data.

### Change 27b-2, 13 Nov 2026

- **Where the IREAUX terms go.** powerflo.vda DECL sets %IREAUXBAL% to `$BATINCLUDE powerflo.vda
  IREAUX` (L221); cal_ire.mod L30 appends its own %2 and %5, and powerflo.vda L11 jumps to the
  label `IREAUX%2%5`. Of the five calls, only two reach terms: eqcombal.mod L84 (`EXP IN`, label
  IREAUXIN, `%MX%` = `COM_IE(R,T,C,S)*`, inside the consumption bracket) and eqpeak.mod L31
  (`IMP OUT` with %5 = '-', label IREAUXOUT-, `%MX%` = `-`). IREAUXOUT and IREAUXIN- are labels
  on the file's last lines (L461-462), so eqcombal.mod L39 and eqpeak.mod L32 and L68 add nothing.
- **demo12 cannot reach EQ_GR_DEMALL.** With one grid node per region, the node with the largest
  demand fraction is the only one; L160 removes its GR_DEMFR, L162 then leaves GR_ADO empty, and
  the row's `$GR_DEMFR(R,T,C,S)` holds nowhere. JRC-EU-TIMES has several nodes but its model is not
  generated yet (its chain stops at coef_obj.mod L31-32, ANNCOST LEV). New crafted case
  demo12_pfd: an intra-regional line from ELC to TRAELC in REG1 with a reactance makes TRAELC a
  second node; with sectoral fractions at both nodes, TRAELC gets GR_ADO and 24 EQ_GR_DEMALL rows.
  The 27a-2 preprocessing with two nodes in a region passes the chain from the input dump (both
  variants), its first check.
- **The non-ADO branch of EQ_GR_DEMALL** (L336-338) needs a row whose node is not GR_ADO, that
  is a node that kept GR_DEMFR as the largest: only GR_DEMFR given as data does that (L107, L131),
  which the main block refuses. Translated, not reached; it is checked when GR_DEMFR data is.
- **The model-stage refusal.** `powerflo_model_unported` had reused the main block's test for
  GR_DEMFR data, which after preprocessing holds the computed fractions. It now tests only what
  the equations would need untranslated (PTDF, gas grids).
- Result: demo12_pfa (8,743 and 3,281 rows) and demo12_pfd (8,911 and 3,401 rows) pass layers 2
  and 3 in both variants against GAMS 54.6.1 with CPLEX and HiGHS; demo12_pfd is a public fixture.

### Change 23 follow-up (#68), 13 Nov 2026

- demo12_flomrk reaches only the import term of EQ(l)_FLOMRK. New crafted case demo12_mrkx:
  negative market shares (PRC_MARK <= 0, so %SIGI% holds) on REG1's electricity link to REG2
  (UP) and REG2's electricity export EXPELC1 (LO), and an IRE_FLOSUM input on REG1's exports,
  reach the export term `-(VAR_IRE(...,'EXP')%IRED%)*(1+IRE_FLOSUM(R,T,P,C,S,'EXP',C,'IN'))`
  (eqflomrk.mod L83-88). GAMS 54.6.1 makes 8 rows (4
  EQG on EXPELC1, 4 EQL on the link); TIMES.jl's model passes layers 2 and 3 in both variants
  (8,703 and 3,241 rows) with no code change.

### Change 25-4 follow-up, 14 Nov 2026: bnd_cum.mod L12-20 and L27-38

- bnd_cum.mod changes FLO_CUM, COM_CUM and RC_CUMCOM before it sets the bounds of VAR_CUMFLO
  and VAR_CUMCOM, and the pre-solve dump holds the changed data. `bnd_data!` did not write these
  changes back; it refused FX, N and negative records and left the rest as read. Two statements
  act without any such record: L38 gives a
  range with no lower bound a lower bound of -INF when an annual COM_BNDNET or COM_BNDPRD lower
  bound of the commodity is negative (a range that a UC_CUMCOM user constraint creates has no
  bound at all), and L31 takes a range that starts after the last milestone year out of
  RC_CUMCOM, which `eq_cumcom!` reads. On the chain route such a model lacked COM_CUM records
  at presolve and kept an EQ_CUMNET/EQ_CUMPRD row GAMS does not make.
- Now `bnd_data!` applies L12-20 (`bnd_cum_flo`) and L27-38 (`bnd_cum_com`) and stores
  FLO_CUM, COM_CUM and RC_CUMCOM; the refusal is gone. `bnd_cum!` (bndmain.jl) takes the bounds
  from the tables as stored (L23-24, L39-40) instead of applying the statements again: with an
  N record a second pass is not idempotent. L13 and L27 copy the N value of the range to
  %EOTIME% over the lead kept under 'EOH' (FLO_CUM) or '0' (COM_CUM), and after the first pass
  that value is the factor MIN(0,ABS(MULTI(JJ,MIYR_L))-1), no longer a lead. GAMS's pre-solve
  dump holds the tables after one pass, so the model built from it was affected in the same way.
- New crafted case demo12_cumc (demo12 + cumc.dd): UC_CUMCOM constraints on REG1's and REG2's
  cumulative net TOTCO2, REG1's with a negative annual lower bound (L38: -INF; REG2: none);
  COM_CUMPRD FX (L30); a COM_CUMNET range 2060-2070 (L31: EPS bounds, out of RC_CUMCOM);
  COM_CUMNET and FLO_CUM to EOH with N = 2 and MULTI('2','2050') = 0.8 (L13-14, L19-20, L27-28,
  L34-35: the factor -0.2, so the bounds are scaled by 0.8); FLO_CUM FX (L16) and a negative
  LO (L12: ignored). GAMS 54.6.1 with CPLEX and HiGHS, both variants optimal (8,721 and 3,259
  rows).
- Result: the step probe passes all 70 steps on demo12_cumc; the chain from the DD files
  (`m13_gate.jl --from-dd --solve`) passes every checkpoint, the QA log, layer 2 and the HiGHS
  objective against CPLEX in both variants (relative difference under 1e-14); the model from
  GAMS's pre-solve dump passes layers 2 and 3 with CPLEX and HiGHS in both variants.
  demo12_cumc is a public fixture, a variant fixture (input -> ppm), a DD-file compile case and
  the case of test/unit/test_bnd_cum.jl (ppm -> pre-solve on every symbol, each branch, and the
  model from that state against GAMS's matrix).

### Change 28, 14 Nov 2026: eqashar.vda L16-33 and the exchange and storage branches of EQ(l)_ASHAR

- FLO_ASHAR is an internal parameter (init_ext.vda L43-44): a model gives FLO_SHAR, and GAMS
  moves a record to FLO_ASHAR when its commodity is not in the group or not a flow of the
  process (prep_ext.vda L78), or when the process is an exchange or storage process
  (pp_prelv.vda L96). TIMES.jl made those moves already and then stopped: `coef_ext!` refused
  any model with FLO_ASHAR records (eqashar.vda L16-33 was not translated), and `eq_ashar!`
  refused the rows of exchange and storage processes.
- Now `eqashar_prep!` (src/ext/vda/eqashar.jl, called by `coef_ext!` at coef_ext.vda L79)
  translates L16-33: the EPS FLO_SHAR record at year '0' of each group (L17); a commodity
  against itself (L21-23: RPCG_ASHAR -1, the share moved to the commodity's type, the diagonal
  deleted); RP_PGFLO for standard processes without an activity variable (L24); RPCG_ASHAR at
  the timeslices of the flow variable (L25), of a storage process (L26) and of the commodity's
  level when it is not a flow of the process (L28-30); and the levelling of FLO_ASHAR to the
  RPS_S2 timeslices with pp_lvlfc.mod (L33), with the scratch it leaves (CG_GRP, UNCD7,
  TS_ARRAY, Z).
- `eq_ashar!` now has the exchange branch (L56-65: an ANNUAL share of an exchange process
  against the flows of the reference group in every region, or against all its imports or
  exports with the groups IMP and EXP, or against its activity) and the storage terms (L51: the
  activity times EXP(-|STG_LOSS|/2); L75-76: VAR_SOUT over PRC_ACTFLO). The three refusals are
  gone (`coef_ext_unported`, `eq_ashar!`, and the two notes of `generate!`).
- New crafted case demo12_ashar (demo12 + ashar.dd): shares of a commodity against a commodity
  and against a user group; against the activity with seasonal values on DAYNITE, SEASON and
  ANNUAL processes (levelled down, inherited, left, aggregated) and on an RP_PGFLO process;
  on exchange processes against the activity, against the reference group IMP in both regions
  and against the commodity itself; a commodity that is not a flow of the process; the output
  of a storage process (ASTGELC, added) against its activity. GAMS 54.6.1 with CPLEX and HiGHS,
  both variants optimal (8,807 and 3,321 rows; 64 ASHAR rows in each).
- Not reached by the case: L24 (demo12's only process without an activity variable is an
  exchange process) and a first index 'ACT' (L28-30, L73-74), which FLO_SHAR input cannot give
  (its third index is a commodity). Both are translated as written.
- Result: the step probe passes all 70 steps on demo12_ashar; the chain from the DD files
  (`m13_gate.jl --from-dd --solve`) passes every checkpoint, the QA log, layer 2 and the HiGHS
  objective against CPLEX in both variants (relative difference under 1e-14); the model from
  GAMS's pre-solve dump passes layers 2 and 3 with CPLEX and HiGHS in both variants.
  demo12_ashar is a public fixture, a variant fixture (input -> ppm), a DD-file compile case
  and the case of test/unit/test_ashar.jl (ppm -> pre-solve on every symbol, each branch, and
  the model from that state against GAMS's matrix).

### Change 29, 14 Nov 2026: coef_obj.mod L31-32, ANNCOST LEV

- The two lines: `$IFI '%ANNCOST%'==LEV ACL=MINYR; MINYR=MIYR_V1; RPT_OPT('OBJ','2')=1;` and
  `$IFI '%ANNCOST%%CTST%'==LEV MINYR=ACL;`. The second holds only when %CTST% is empty (OBJ AUTO
  or STD without OBLONG; initmty.mod L426-430), and then puts MINYR back. With OBJ MOD, ALT or
  LIN, or with OBLONG, MINYR stays MIYR_V1: Y_EOH (L33) starts one year later than without the
  switch, and eqobjinv.mod L86 (OBJ_PASTI) reads the new MINYR, so the objective changes.
  ppm_ext.mlf L8 sets MINYR the same way, but only under MACRO MLF, which is refused.
- ACL and RPT_OPT('OBJ','2') are read by the reports only (cost_ann.rpt L16, L26, L90;
  rpt_obj.rpt L127; the levelised annual costs, M1.6). They are state at the coef and pre-solve
  checkpoints, so they are set now. The other ANNCOST lines are reporting (cost_ann.rpt
  L165-167, wrtbprice.mod L30) or MACRO (eqobjann.tm L69).
- `coef_obj!` translates the two lines where they stand, between Y, YK (L29-30, the old MINYR)
  and Y_EOH (L33, the new one), and no longer refuses the switch.
- Two crafted cases, both demo12 with only its run file changed: demo12_lev (ANNCOST LEV; demo12
  runs with OBJ MOD, so %CTST% is '**0') and demo12_levstd (OBJ AUTO and ANNCOST LEV; %CTST% is
  empty). GAMS 54.6.1 with CPLEX and HiGHS, both variants optimal. demo12_lev: MINYR 2005, ACL
  2004, 48 years in Y_EOH (49 without the switch), objective 23,957,430.74 against demo12's
  23,960,685.74. demo12_levstd: MINYR 2004, ACL 2004, 49 years in Y_EOH.
- Result: the step probe passes all 70 steps on both cases; the chain from the DD files
  (`m13_gate.jl --from-dd --solve`) passes every checkpoint, the QA log, layer 2 and the HiGHS
  objective against CPLEX in both variants of both cases (relative difference under 1e-14); the
  model from GAMS's pre-solve dump passes layers 2 and 3 with CPLEX and HiGHS. Both cases are
  public fixtures, variant fixtures (input -> ppm), DD-file compile cases and the cases of
  test/unit/test_anncost.jl (ppm -> pre-solve on every symbol, the two lines, and the model from
  that state against GAMS's matrix).
- JRC-EU-TIMES sets this switch (change 27b-2 above: its chain stopped here), so its chain now
  goes on past coef_obj.mod; how far is for the next local run (verdicts only).

### Change 30, 14 Nov 2026: stepped (myopic) runs before solve.stp

- A stepped run (`$SET TIMESTEP n`; initmty.mod L446 and maindrv.mod L38 set `%STEPPED%` to `+`)
  solves the horizon in steps of n years, each with the earlier periods fixed to their levels.
  TIMES.jl refused it at the coefficient stage (`coef_alt.lin` L81). This change translates what
  such a run does differently before solve.stp starts; the stepped solve itself is M1.5.
- coef_alt.lin L81, `$IF SET TIMESTEP $GOTO DONE`: L83-86 are skipped, so RTP_CAPVL is not
  computed (it stays empty). L65-80 (R_DF, RB, COEF_CPT) run as in any run with a non-empty
  %CTST%. The STP label (L134-158) is called inside each step (solve.stp L124): M1.5.
- eqobsalv.mod L23-25: `$IF SET TIMESTEP OPTION CLEAR=OBJ_SUMS,CLEAR=OBJ_SUMS3,CLEAR=SALV_INV,
  CLEAR=OBJSCC;` and, under `%STEPPED%==+` in the eqmain.mod call, `$GOTO EQUA`: the salvage
  preparation (L26-82) is skipped, since each step runs it (solve.stp L127). `eqobsalv_prep!`
  leaves the four symbols and the ones L13-17 declare (SALV_DEC, OBJ_SALI, OBJ_DCEOH) empty.
- `stepped(tm)` (src/coef/coef_alt.jl) is `$IF SET TIMESTEP`. The refusal moves to where the
  stepped solve starts: `untranslated_families` lists "(stepped run)" (maindrv.mod L38-40: every
  `%R_T%` equation is generated for SUBT, the periods of one step; L109-113: solve.stp), so
  `generate!` refuses the run, and `bounds_unported` refuses the bounds under TIMESTEP.
- **The pre-solve dump of a stepped run is not a pre-solve state.** With SOLVE_NOW=NO, GAMS
  still goes through the loop of solve.stp, every step without a solve (maindrv.mod L113 comes
  before the SOLVE_NOW exit, L114). The dump holds the state after the last step: 27 symbols
  differ from the state before the loop (YR_V1, YR_VL, MY_FYEAR, G_OVERLAP, F, Z, SUBT,
  BACKWARD, RT_PP, NO_RT, RTC_NET, RTC_PRD, RVT, UC_RN, R_UC, RTP_CAPYR, STP_UCT, UNCD1, UC_BND,
  NO_RVP, FIL, PRESOL, YK1, OBJ_SUMS, SALV_INV, OBJSCC, OBJ_DCEOH; each traced to its line of
  solve.stp, clearsol.stp, coef_alt.lin STP or eqobsalv.mod in `STEPPED_LOOP_SYMBOLS`,
  scripts/m13_gate.jl).
- **Harness 0.3.3, the `equ` checkpoint.** `reference/gams/equ_ext.tjlref` dumps every symbol
  after eqmain.mod and the extensions' equ_ext (maindrv.mod L79-80), in stepped runs only
  (`$IF SET STEPPED`), with the other checkpoints (`--only presolve`; no solve, so the demo
  licence is enough). It is the state the stepped solve starts from. The chain
  (`m13_gate.jl`) compares a stepped run at `equ` on every symbol, then at the pre-solve dump
  less the 27 symbols above, and ends before the model. References of other runs do not change.
- GAMS 54.6.1 on demo12_step (TIMESTEP 20, the case of M1.4 change 7), reduce_off, CPLEX, for
  the stepped solve to come: step 1 has 5,921 rows, 6,717 columns and 20,736 nonzeros and ends
  at 12,397,965.9863; step 2 has 2,975, 4,421 and 12,438 and ends at 20,325,417.7629; step 3
  has 1,380, 3,179 and 6,930 and ends at 23,960,685.7370, demo12's own objective. The CONVERT
  export (`matrix/`) is the third step's model.
- Result, both variants of demo12_step, from the input dump and from the DD files: `init/`,
  `prep/`, `prelv/` and `ppm/` PASS (833 symbols), `coef/` PASS (958 symbols from the input
  dump, 833 from the DD files), `equ/` PASS (833
  symbols; 109,899 GAMS records in reduce_off and 103,264 as run), the pre-solve dump PASS (806
  symbols), both QA logs identical. CI: test/unit/test_stepped.jl (ppm -> equ on every symbol,
  the two translated places, the refusal), the variant fixture (input -> ppm; the refusal on
  the `equ` state) and test_coef_alt.jl.

### Change 31, 14 Nov 2026: EQ(l)_BNDNET and EQ(l)_BNDPRD

- The first of the equation families refused since M1.1 (`untranslated_families`), translated
  after the gate close-out, one family per change. eqbndcom.mod L16-24, included six times from
  eqmain.mod L54-59 (NET then PRD; G with LO, E with FX, L with UP): a COM_BNDNET or COM_BNDPRD
  record at a timeslice S that is valid for the commodity (RCS_COMTS) but above the level it is
  tracked at (NOT COM_TS) gives a row, the sum of VAR_COMNET or VAR_COMPRD over the commodity's
  own timeslices at or below S (RTCS_VARC with TS_MAP) against the bound. Records at the
  commodity's own timeslices stay bounds of the variables (bndmain.mod L57-58), and records
  below that level were summed up to it before (pp_lvlbd.mod); both were translated already,
  as were RHS_COMBAL and RHS_COMPRD (ppmain.mod L1051-1056), which put the two variables into
  the commodity balance.
- The conditions of the includes: LO only where the value is not zero, UP only where it is not
  INF, FX with no condition on the value. EPS compares as zero (docs/discrepancies.md G12), so a
  LO record with the value EPS gives no row, and an FX record with the value EPS gives a row
  with a right-hand side of zero. The crafted case has one of each.
- `eq_bndcom!` (src/model/eqbndcom.jl), called in `generate!` after `eq_actbnd!`, in the order
  of mod_equa.mod L63-68. The refusal in `untranslated_families` is removed.
- New crafted case demo12_bndc (demo12 + bndc.dd): ELC is tracked at DAYNITE. COM_BNDPRD at
  ANNUAL, LO in REG1 2020 and UP in REG1 2030 (EQG_BNDPRD, EQL_BNDPRD), and FX at the season S
  in REG2 2030 (EQE_BNDPRD); COM_BNDNET at ANNUAL, LO in REG1 2030 (EQG_BNDNET), UP at the
  season W in REG2 2020 (EQL_BNDNET) and FX EPS at ANNUAL in REG2 2030 (EQE_BNDNET); a
  COM_BNDPRD at WD (a bound of VAR_COMPRD); a LO EPS and an UP INF (no row). GAMS 54.6.1: both
  variants optimal, objective 23,974,265.9168 (demo12: 23,960,685.7370); EQG_BNDPRD, EQL_BNDPRD
  and EQG_BNDNET bind, with marginals 5.82, -101.01 and 148.60.
- Result: the step probe passes all 70 steps in both variants. The chain from the DD files:
  DD files -> input PASS (824 sets and parameters), every checkpoint to the pre-solve dump PASS
  (823 symbols), both QA logs identical, the model against GAMS's matrix PASS (reduce_off 8,701
  rows, 9,669 columns, 31,411 nonzeros; as run 3,239, 4,485 and 18,395), HiGHS against
  GAMS/CPLEX PASS (relative difference 6.4e-15 and 2.5e-15). CI: test/unit/test_eqbndcom.jl
  (layer 2, the six rows term by term, the bound that stays on the variable, the records that
  give no row), the public fixture (layers 2 and 3), the variant fixture (input -> ppm, the
  whole model) and the DD-file compile case.
- The other bound equations still refused follow, each as its own change: EQ(l)_FLOBND
  (eqflobnd.mod), EQ(l)_FLOFR (eqflofr.mod), EQ(l)_IREBND (eqirebnd.mod), EQ(l)_XBND
  (eqxbnd.mod). `untranslated_families` lists every family still refused.

### Change 32, 14 Nov 2026: EQ(l)_FLOBND

- The second of the refused equation families. eqflobnd.mod L15-43, included three times from
  eqmain.mod L111-113 (G with LO, E with FX, L with UP): a FLO_BND record that cannot be a
  bound of one flow variable gives a row, the sum of the process's flow variables of the
  commodity (or of the commodities of the group) at the timeslices at or below the record's,
  over the vintages, against the bound. bnd_flo.mod L16-24 marks such records with an EPS at
  the year '0' (%DFLBL%): every record of a commodity group, and of a single commodity where
  the process is vintaged, is an exchange process, or has the flow replaced under REDUCE (by
  the activity, RPC_FFUNC, or by the emitting flows, RPC_EMIS). The other records are bounds of
  VAR_FLO at the flow's own timeslices (bnd_flo.mod L27-29) or, under REDUCE, of VAR_ACT for
  the activity flow (L34-39); both were translated already (`bnd_flo!`).
- The domain (L17-20): the process is available in the period (RTP_VARA), and some flow
  variable of the commodity or group (RTPCS_VARF) has a timeslice TS at or below the record's S
  (TS_MAP) that is strictly below S (RS_BELOW) or whose record is marked. Three points of GAMS
  semantics, each confirmed against GAMS's matrix on the crafted case:
  - `RS_BELOW(R,S,TS) OR FLO_BND(R,'0',P,CG,S,BD)`: a stored EPS is true in a logical
    expression, so a marked record gives a row at the flow's own timeslice.
  - `$FLO_BND(R,T,P,CG,S,BD)` is true for a stored EPS as well: a LO record with the value EPS
    on an emission flow or on a group gives a row with a right-hand side of zero (the LO include
    has no condition on the value).
  - The condition of the UP include, `FLO_BND NE INF`, is on the body and not on the domain
    (L41): for an UP record with the value INF the body is empty, `0 =L= 0`, and GAMS writes no
    row.
- The body (L24-41): the flows of a standard process (RP_FLO) enter through `%cal_red%`, so
  under REDUCE a replaced flow is the activity times its coefficient (`cal_nored!`, which hands
  to `cal_red!`). The flows of an exchange process (RP_IRE) enter as VAR_IRE, or under REDUCE as
  VAR_ACT * PRC_ACTFLO where the flow is the activity (RPC_AIRE). With a single commodity,
  imports and exports add up; with a commodity group the exports count negative, so the bound
  is on the net import (L37).
- `eq_flobnd!` (src/model/eqflobnd.jl), called in `generate!` after `eq_combal!`, in the order
  of mod_equa.mod L88-90. The refusal in `untranslated_families` is removed.
- **Two corrections of earlier code** (`bnd_data!`, src/model/qack_prep.jl, M1.3 change 25-4),
  both shown by the step probe on the new case, at pp_clean:
  - bnd_flo.mod L16 deletes the LO records with the value zero (an EPS) of flows that are not
    emission flows of a standard process. The statement is controlled by T and C, so it reaches
    only single commodities in milestone years. `bnd_data!` applied it to every record, and so
    deleted the LO EPS record of a commodity group, which GAMS keeps and writes as a row.
  - bnd_flo.mod L31, `OPTION CLEAR=TRACKPC`, was missing. A FLO_BND record that stays a bound
    of VAR_FLO left its (process, commodity) in TRACKPC, pp_qack.mod L51-52 then read it as a
    flow to keep, and one RPG_RED entry too many was left (REDUCE). `bnd_flo!` (bndmain.jl),
    which sets the bounds, had both statements right; only the data path was wrong. No open
    suite model has FLO_BND data in its input, and the earlier crafted cases with FLO_BND data
    (demo12_red17b) pass unchanged.
- New crafted case demo12_flobnd (demo12 + flobnd.dd), 21 FLO_BND records. Rows: gas input of
  ELCTEGAS00 at ANNUAL (above the flow's level); electricity of ELCREHYD00 at the season W, LO;
  gas input of the vintaged ELCTNGAS01 at WD and its electricity at W, FX; oil input of
  ELCTEOIL00 at SD (a row under REDUCE only: without REDUCE a bound of VAR_FLO); the CO2
  emission of ELCTEGAS00 at ANNUAL, and at SD with LO EPS; the output group of REFEOIL00, UP and
  LO EPS; the import IMPELC1 at ANNUAL and at WN; the two-way exchange process
  TB_ELC_REG1_REG2_01, ELC at the season S with interpolation option 5 (rows in 2020, 2030 and
  2050), and the group NRG at W, UP and LO (the net import). Bounds that stay on a variable:
  diesel input of FTE-AGROIL (VAR_FLO) and electricity of ELCREBIO00 at WN (VAR_ACT under
  REDUCE). No row: an UP INF, a LO EPS on a single commodity (deleted by L16), a timeslice
  below the flow's level, a period in which the process is not available.
- GAMS 54.6.1: both variants optimal, objective 23,964,228.0773 (demo12: 23,960,685.7370);
  15 rows without REDUCE (4 G, 1 E, 10 L) and 16 with it (4 G, 1 E, 11 L). Six rows bind, among
  them the gas input of ELCTEGAS00 (marginal -1.379), the import IMPELC1 in REG1 2030 (-23.966)
  and the output group of REFEOIL00 (-4.911).
- Result: the step probe passes all 70 steps (35 in each variant). The chain from the DD
  files: DD files -> input PASS (824 sets and parameters), every checkpoint to the pre-solve
  dump PASS (823 symbols), both QA logs identical, the model against GAMS's matrix PASS
  (reduce_off 8,710 rows, 9,669 columns, 31,452 nonzeros; as run 3,249, 4,485 and 18,437),
  HiGHS against GAMS/CPLEX PASS (relative difference 6.5e-15 and 6.8e-15). CI:
  test/unit/test_eqflobnd.jl (the marks and the deleted and kept LO EPS records, layer 2, the
  sixteen rows term by term, the bounds that stay on a variable, the records that give no
  row), the public fixture (layers 2 and 3), the variant fixture (input -> ppm on every
  symbol, which holds the two corrections; the whole model) and the DD-file compile case.
- Still refused among the bound equations, each to follow as its own change: EQ(l)_FLOFR
  (eqflofr.mod; change 33), EQ(l)_IREBND (eqirebnd.mod), EQ(l)_XBND (eqxbnd.mod).

### Change 33, 14 Nov 2026: EQ(l)_FLOFR

- The third of the refused equation families. eqflofr.mod L15-27, included three times from
  eqmain.mod L118-120 (L with LO, E with LNX = N and FX, G with UP): a FLO_FR record at the
  timeslice S gives a row `fraction * reference flow =l= flow in S`, so a lower bound on the
  share is an =L= row and an upper bound an =G= row. The flows enter through `%cal_red%`,
  summed over the vintages (RTP_VINTYR).
- The domain (L15): a milestone year, RTPC, a standard process (RP_FLO), and a flow variable of
  the commodity (RPCS_VAR) at a timeslice at or below S (TS_MAP). Exchange processes get no
  row.
- The reading of the body, each point confirmed against GAMS's matrix on the crafted case:
  - A value above zero is a share of the flow of the whole year (L19: every timeslice of the
    flow, RTPCS_VARF). A negative value, or an EPS, is a share of the flow of the parent
    timeslice of S (only the timeslices with RS_FR(R,SL,TS)); the fraction is the absolute
    value (L21), and the absolute value of an EPS is an EPS.
  - A record 'N' at S defines a variable for the flow of S: `VAR_FLO(S) * N` equals the sum
    of the flow variables at and below S (L17 with L25-27; IPS = IN, N).
  - Where the parent timeslice SL of S has a record 'N' (an EPS counts as true), the
    reference flow of a bound is that variable: VAR_FLO at SL or at ANNUAL (TS_ANN), each
    where its record 'N' is above zero (L18). An EPS is not above zero, so the EPS records of
    pp_prelv.vda L109 send the reference to the variable of the annual flow.
  - L27, `MIN(0,FLO_FR) -> BD(L)`: `->` is GAMS's logical implication. The right-hand side is
    dropped only for a record 'N' with a negative value or an EPS. An 'N' with the value EPS
    therefore gives the row `EPS * VAR_FLO(S) =E= 0`, which GAMS keeps; in the matrix it has
    no coefficient other than zero.
  - A LO record with the value EPS gives the row `0 =L= flow in S`, with EPS coefficients on
    the flows of the parent timeslice.
- `eq_flofr!` (src/model/eqflofr.jl), called in `generate!` after `eq_flobnd!`, in the order of
  eqmain.mod L118-120. The refusal in `untranslated_families` is removed. No earlier code
  needed a change.
- The data statements were translated before: preppm.mod L191 (interpolation), ppmain.mod L992
  (pp_lvlbd.mod: records below the flow's level are added up to it; an UP only where the UP
  records below cover the whole of the timeslice above) and pp_prelv.vda L99-109 (a record at
  ANNUAL is levelised, L100-103; the records 'N' of the variable of the annual flow, L105-109).
  Until now they were checked on crafted unit states (change 8b, the case "bnd"); the new case
  is the first whole run with FLO_FR data, and they pass on it as they stand.
- New crafted case demo12_flofr (demo12 + flofr.dd), 21 FLO_FR records. Rows: electricity of
  ELCREHYD00 at WD, UP 0.4 (share of the year); gas input of ELCTEGAS00 at SD, LO -0.6 (share
  of the season); electricity of the vintaged ELCTNGAS01 at the season W, FX 0.5, and its CO2
  at SD, UP 0.25 (an emission flow); ELCRNWIN01 at ANNUAL, UP 1.1, levelised into a variable
  for each season and a row in each DAYNITE timeslice; the coal input of the SEASON process
  ELCTECOA00 at ANNUAL, LO 0.9, levelised into a variable for the year and a row in each
  season; FTE-RSDELC and (vintaged) the gas input of ELCTNGAS01 with a record at the year '0'
  and ANNUAL, which gives the variable of the annual flow, the two 'N' EPS rows and bounds
  against that variable; ELCREWIN00 with a record 'N' at W and an UP at WD against the variable
  of W; ELCNENUC00 (SEASON) with UP 0.3 at SD and SN, added up to UP 0.6 at S; ELCTEGAS00 in
  REG2 at WN with interpolation option 5 (a row in 2020, the last period of the process);
  ELCRNWIN01 in REG2 at SN, LO EPS. No row: an UP at WD alone on a SEASON process, a period
  without the process, the import IMPELC1.
- GAMS 54.6.1: both variants optimal, objective 23,960,866.3307 (demo12: 23,960,685.7370); 27
  rows in each variant (6 L, 11 E, 10 G). Two bind: the UP of ELCREWIN00 at WD (marginal
  121.97) and the row of its variable of W (-73.18).
- Result: the step probe passes all 70 steps (35 in each variant). The chain from the DD
  files: DD files -> input PASS (824 sets and parameters), every checkpoint to the pre-solve
  dump PASS (823 symbols), both QA logs identical, the model against GAMS's matrix PASS
  (reduce_off 8,722 rows, 9,688 columns, 31,492 nonzeros; as run 3,260, 4,504 and 18,476),
  HiGHS against GAMS/CPLEX PASS (relative difference 7.2e-15 in both). CI:
  test/unit/test_eqflofr.jl (the levelised and added-up records, layer 2, the twenty-seven
  rows, the records that give no row), the public fixture (layers 2 and 3), the variant
  fixture (input -> ppm on every symbol; the whole model) and the DD-file compile case.
- Still refused among the bound equations, each to follow as its own change: EQ(l)_IREBND
  (eqirebnd.mod; change 34), EQ(l)_XBND (eqxbnd.mod). `untranslated_families` lists every
  family still refused.

### Change 34, 14 Nov 2026: EQ(l)_IREBND

- The fourth of the refused equation families. eqirebnd.mod L18-69, included three times from
  eqmain.mod L152-154 (G with LO where the value is not zero, E with FX, L with UP where the
  value is not INF): an IRE_BND record (region, year, commodity, timeslice, partner region, IMP
  or EXP) gives a row `trade of the commodity with the partner in S =l= IRE_BND`, summed over
  the exchange processes that link the two regions.
- The domain (L18-19): a milestone year, an internal region R, the commodity tracked at S
  (RCS_COMTS), and some exchange process of R with the commodity in that direction (RPC_IRE).
- The body, each point confirmed against GAMS's matrix on the crafted case:
  - Imports from an internal region through a process with an exchange equation
    (RPC_EQIRE(R,P,C,'IMP')), L23-32: the exports of the partner, with the coefficients of
    EQ_IRE (IRE_FLO of the importing timeslice, IRE_CCVT, IRE_TSCVT, RS_FR, RTCS_FR).
    `REG(ALL_REG)` binds the partner of the equation as an internal region.
  - Imports otherwise (from an external region), L35-41: the import flows of R itself through
    the processes with a link from the partner (TOP_IRE).
  - Exports, L56-62: the export flows of R itself through the processes with a link to the
    partner. The marketplace branch (L46-51, RPC_MARKET(R,P,C,'EXP')) stays refused:
    `ire_unported` raises for RPC_MARKET data (eqire.mod L23-38), so it cannot be reached.
  - L30, L39, L60: a flow at a timeslice at or below S counts in full (TS_MAP); a flow at a
    timeslice above S counts with the share G_YRFR(R,S)/G_YRFR(R,TS) (RS_BELOW). So a bound at
    WD takes 0.479 of an import that runs at the season W, and the year's share of WD of the
    dummy import, which runs at ANNUAL.
  - A flow is VAR_IRE, or VAR_ACT * PRC_ACTFLO where the activity is the exchange (RPC_AIRE,
    under REDUCE).
  - An FX with the value EPS gives a row with the right-hand side zero; a LO with the value
    EPS and an UP INF give no row (eqmain.mod L152, L154). A record whose partner has no link
    gives a row without a variable, which GAMS leaves out of the model. A record of an
    external region stays in the data and gives no row.
- `eq_irebnd!` (src/model/eqirebnd.jl), called in `generate!` after `eq_ire!`, in the order of
  eqmain.mod L152-154. The refusal in `untranslated_families` is removed. No earlier code
  needed a change.
- The data statements were translated before: preppm.mod L193 (interpolation), ppmain.mod L995
  (pp_lvlbd.mod: records below the commodity's level are added up to it) and pp_prelv.vda L91
  (NE, the commodities with a trade bound). Until now they were checked on crafted unit
  states; the new case is the first whole run with IRE_BND data, and they pass on it as they
  stand.
- New crafted case demo12_irebnd (demo12 + irebnd.dd): 17 IRE_BND records; a new electricity
  import of REG1 that runs at SEASON (IMPELC2: a bound at a DAYNITE timeslice is finer than
  its flow); IRE_FLO of the electricity trade from REG2 to REG1 below 1 and different in each
  timeslice (0.96, 0.97, 0.95, 0.98). Rows: electricity into REG1 from REG2 at ANNUAL (UP 300)
  and at WD (LO 20); electricity out of REG2 to REG1 at the season S (UP 100); gas into REG1
  from REG2 (LO 10) and out of REG2 to REG1 (UP 400) on the gas link; electricity into REG1
  from the external region IMPEXP at WD (UP 100) and at S (UP 400); coal into REG1 from
  MINRNW (UP 4000 with option 5: rows in 2020, 2030 and 2050, the sum of three mining steps);
  gas out of REG1 to IMPEXP (LO 5); FX EPS on electricity into REG2 at SN; gas into REG1 from
  IMPEXP at SD (LO 50) and WD (LO 100), added up to LO 150 at ANNUAL. No row: LO EPS, UP INF,
  electricity from MINRNW (no link), a record of the external region IMPEXP.
- GAMS 54.6.1: both variants optimal, objective 23,939,060.0779 (demo12: 23,960,685.7370; the
  new import is cheaper); 13 rows in each variant (4 G, 1 E, 8 L). Four bind: the LO on
  electricity from REG2 at WD (the partner exports 20/0.95 = 21.05), the LO on gas from REG2
  (10), the LO on gas exports (5) and the UP on coal in 2020 (4000).
- Result: the step probe passes all 70 steps (35 in each variant). The chain from the DD
  files: DD files -> input PASS (824 sets and parameters), every checkpoint to the pre-solve
  dump PASS (823 symbols), both QA logs identical, the model against GAMS's matrix PASS
  (reduce_off 8,738 rows, 9,699 columns, 31,553 nonzeros; as run 3,252, 4,497 and 18,477),
  HiGHS against GAMS/CPLEX PASS (relative difference 1.4e-15 and 1.6e-16). CI:
  test/unit/test_eqirebnd.jl (the data, layer 2, the thirteen rows term by term, the records
  that give no row), the public fixture (layers 2 and 3), the variant fixture (input -> ppm on
  every symbol; the whole model) and the DD-file compile case.
- Still refused among the bound equations: EQ(l)_XBND (eqxbnd.mod; change 35).
  `untranslated_families` lists every family still refused.

### Change 35, 14 Nov 2026: EQ(l)_XBND

- The fifth and last of the refused bound equations. eqxbnd.mod L17-56, included three times
  from eqmain.mod L241-243 (G with LO where the value is not zero, E with FX, L with UP where
  the value is not INF): an IRE_XBND record (region, year, commodity, timeslice, IMP or EXP)
  gives a row `all imports (or exports) of the commodity of the region in S =l= IRE_XBND`,
  whatever the partner. The region is internal or external (ALL_REG).
- The domain (L17): a milestone year and some exchange process with the commodity in that
  direction, RPC_IRE(ALL_REG,P,C,IE). RPC_IRE is a projection of TOP_IRE (ppmain.mod L44-45)
  and so holds the external regions: their records give rows. Unlike EQ(l)_IREBND there is no
  condition on the commodity's timeslices (no RCS_COMTS), and the data is not added up to the
  commodity's level (no pp_lvlbd.mod; preppm.mod L194 interpolates only).
- The body, each point confirmed against GAMS's matrix on the crafted case:
  - An internal region, L23-32: the flows of every exchange process of the region with the
    commodity in the direction, at the timeslices on the line of S (RS_TREE), times
    RS_FR(REG,S,TS): 1 for a flow at or below S, G_YRFR(S)/G_YRFR(TS) for a flow above S. So
    a bound at WD takes 0.479 of an import that runs at the season W and the year's share of
    WD (0.249) of a flow at ANNUAL; a bound on gas at WD, finer than the commodity's level,
    gives a row all the same.
  - An external region, L39-51 (`$(NOT REG(ALL_REG))`): the flows of the internal regions R
    in the other direction, `IMPEXP(IE--1)` (the circular lag on the two-element set: IMP for
    a bound on EXP and the reverse), through the processes linked to the external region:
    TOP_IRE(ALL_REG,C,R,COM,P) for a bound on its exports, TOP_IRE(R,COM,ALL_REG,C,P) for a
    bound on its imports. The timeslice S of the external region is reached through
    IRE_TSCVT(R,ALL_TS,ALL_REG,S); a flow at TS on the line of ALL_TS counts with
    IRE_TSCVT * RS_FR(R,ALL_TS,TS). By default an external region has IRE_TSCVT from ANNUAL
    to ANNUAL only (ppmain.mod L967-978), so a bound at another timeslice needs IRE_TSCVT
    data; without it the row has no variable and GAMS leaves it out.
  - The dummy import (IMPNRGZ) is in the rows of an internal region (it is an exchange
    process of the region) but not in the rows of the external region IMPEXP: pp_prelv.vda
    L111 removes its link from IMPEXP for every commodity without an IRE_BND (L91). The
    translation reads TOP_IRE as the preprocessing leaves it, so it follows without a
    special case.
  - A flow is VAR_IRE, or VAR_ACT * PRC_ACTFLO where the activity is the exchange (RPC_AIRE,
    under REDUCE).
  - An FX with the value EPS gives a row with the right-hand side zero; a LO with the value
    EPS and an UP INF give no row (eqmain.mod L241, L243).
- `eq_xbnd!` (src/model/eqxbnd.jl), called in `generate!` after `eq_uc!`, in the order of
  eqmain.mod L241-243. The refusal in `untranslated_families` is removed. No earlier code
  needed a change.
- Other places where GAMS uses IRE_XBND, not part of this change: dynslite.vda L36 (clears
  the bounds of turned-off timeslices; TS_OFF data stays refused) and solve.stp L257-263 (the
  stepped run, M1.5).
- New crafted case demo12_xbnd (demo12 + xbnd.dd): 20 IRE_XBND records; the electricity
  import of REG1 that runs at SEASON (IMPELC2, as in demo12_irebnd); an IRE_TSCVT of 0.9
  from REG1's season W to a timeslice W of the external region IMPEXP. Rows of an internal
  region: electricity into REG1 at ANNUAL (UP 500: the imports from IMPEXP, the dummy import
  and the imports from REG2, 11 terms) and at WD (LO 30); electricity out of REG1 at the
  season S (UP 100); gas out of REG2 (LO 10: the export to IMPEXP and the gas link);
  electricity out of REG2 (FX 40); gas into REG1 at WD (UP 5000); coal out of REG1 (UP 600
  with option 5: rows in 2020, 2030 and 2050); FX EPS on electricity into REG2 at SN. Rows of
  an external region: gas into IMPEXP (LO 3: the exports of both regions); electricity out
  of IMPEXP at ANNUAL (UP 300: the imports of both regions) and at W (UP 150: REG1's imports
  in its season W, times 0.9); coal out of MINRNW (UP 9000 with option 5: the mining of both
  regions in 2020, 2030 and 2050); FX EPS on coal into IMPEXP. No row: LO EPS, UP INF, a
  commodity without an exchange process (TOTCO2), electricity out of IMPEXP at WD (no
  IRE_TSCVT), electricity out of MINRNW (no link).
- GAMS 54.6.1: both variants optimal, objective 23,960,860.5847 (demo12: 23,960,685.7370);
  17 rows in each variant (3 G, 3 E, 11 L). At their bound: the FX on electricity out of
  REG2 (40), the LO on gas out of REG2 (10), the UP on electricity out of IMPEXP in 2020
  (300) and at W in 2030 (150), the UP on coal out of REG1 in 2020 and 2050 (600).
- Result: the step probe passes all 70 steps (35 in each variant). The chain from the DD
  files: DD files -> input PASS (824 sets and parameters), every checkpoint to the pre-solve
  dump PASS (823 symbols), both QA logs identical, the model against GAMS's matrix PASS
  (reduce_off 8,742 rows, 9,699 columns, 31,599 nonzeros; as run 3,256, 4,497 and 18,519),
  HiGHS against GAMS/CPLEX PASS (relative difference 1.4e-15 and 9.3e-16). CI:
  test/unit/test_eqxbnd.jl (the data, layer 2, the seventeen rows term by term, the records
  that give no row), the public fixture (layers 2 and 3), the variant fixture (input -> ppm on
  every symbol; the whole model) and the DD-file compile case.
- The bound equations of eqmain.mod are now all translated. `untranslated_families` lists
  every family still refused.

## Open items

- QA log: `pp_qaput` calls write QA_CHECK.LOG and set PUTOUT, PUTGRP and
  ERRLEV (first in ppmain.mod L35, `$IF WARNINGS`, which depends on GAMS
  compile warnings that no dump records; then timslice.mod L81-82, a
  warning when year fractions are normalised, and L101-104, a FATAL line,
  ERRLEV 99, for a timeslice with several parents, which pp_qack.mod L378
  acts on; ppmain.mod L213 resets PUTGRP and L229-230 warn when a delayed
  process has past investment). Closed by change 25b (#75-#77; James,
  6 Nov 2026): TIMES.jl writes the log and checks errors as GAMS does,
  ERRLEV aborts included, and the scalars are compared at every checkpoint.
  The `$IF WARNINGS` line (ppmain.mod L35) takes the number of compile
  warnings as an input of the run (`qa_warnings!`): from the reference's
  listing, or from the DD reader's own count (discrepancies G54).
- Scratch scalars of changes 2-5: ppmain_rtp! and timslice! do not keep Z
  and MY_F (ppmain.mod L215, timslice.mod L67-78). Later loops overwrite
  them in every suite model; only a run with G_NOINTERP and neither a
  PRC_RESID '0' record nor an NCAP_BND 'N' would show the difference. MY_SUM, which nothing overwrites,
  is kept since 6b.
