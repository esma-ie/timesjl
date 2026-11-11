# Decision log

This file lists every question put to James Glynn, the project lead: those in
a pull request's "Decisions for you" list, and those asked in the chat at a
check-in. For each one it records what was decided and how. It is kept
current with each PR: new entries are added when a PR opens, and the outcome
when it merges or James answers. In the "How" column, "James, <date>" means
an explicit answer; "accepted by merge, <date>" means the PR's recommended
answer was already built in and the merge accepted it; "open" means no
answer yet.

## The rule

1. **Default built in: the merge decides.** If the PR already does what it
   recommends, merging the PR accepts it. It is logged as "accepted by merge
   (#PR, date)".
2. **No default: the merge does not decide.** A question with no default, or
   a choice between options of which the PR built only one, goes on the
   "Open decisions" list. It is asked again at each 9:00 check-in until
   James answers. No work that depends on it starts.
3. **Rule-level decisions need an explicit yes.** A known-differences entry,
   a licence or test-data use, or a departure from the Phase 1 rules or the
   approved plan is never approved by a merge. It stays "pending James"
   until he says yes.

## Open decisions

| Asked | Where | Question | Recommended | Status |
| --- | --- | --- | --- | --- |
| 3 Nov 2026 | chat | Keep the "within 5x GAMS, warm" speed target in Phase 1 (M1.7), or move it to Phase 2? | none given | Open. `docs/translation-guide.md` L86 still has it at M1.7. |
| 4 Nov 2026 | #30 | Add `scripts/m13_replay.jl` (needs GAMS, about 7 min) to the nightly run? | none given | Open |
| 5 Nov 2026 | #35 | A speed-up of shared code (`gams_sort!`) during Phase 1, with identical results | merge it | Approved by merge (5 Nov 2026); confirm. Rule-level: Phase 1 does no performance tuning. |
| 6 Nov 2026 | #54 | Allow LP-identical data-structure fixes before M1.7? | none given | Open; rule-level (departure from the Phase 1 rules). |
| 6 Nov 2026 | #61 | Count one-way cross-evaluation (CPLEX's optimum in TIMES.jl) as OTUS9r's layer 3 at the M1.3 gate? | yes; HiGHS on OTUS9r looked at separately | Approved by merge (6 Nov 2026); confirm. Rule-level: layer 3 asks for both directions. |
| 8 Nov 2026 | chat | Harness fix as one small PR: CHECK status for a non-optimal solve; redo `ppm/` and `coef/` made with older GAMS | one small PR | Open; no PR yet. |
| 8 Nov 2026 | #68 | A demo12 variant with trade between regions, to check the EXP term: now, or before the M1.3 gate? | none given | Open |
| 10 Nov 2026 | #89 | Keep P2-5 (data and equation schemas) on the Phase 2 backlog, with its three pilots after M1.7? | keep; all pilots after M1.7 | Open; provisional until James confirms. |
| 10 Nov 2026 | #90 | Which other outcomes turn the cuOpt nightly red? | proposed in the chat | Open |
| 10 Nov 2026 | #90 | Where to test GPU scaling: open core-model reference runs as a release asset, or a sweep on native Linux? | none given | Open |
| 10 Nov 2026 | #90 | Wednesday's full cuOpt suite: set `CUOPT_FIXTURES=all` and `CUOPT_GPU_SHARES=100`? | yes | Open; a GitHub setting only James can make. |
| 10 Nov 2026 | #91 | K2 known difference: the input dump from DD files lists variables and equations without their GAMS type | approve K2 | Approved by merge (10 Nov 2026); confirm. |

## Decisions in the chat (not in a PR list)

| Date | Decision | Where it is recorded |
| --- | --- | --- |
| 11 Nov 2026 | TIMES version: stay on v4.9.7 (`d9a6a25`) until the M1.3 gate closes; then move to v4.9.8 (`7064680`, 5 Nov 2026) as a whole: re-pin the source download (`Artifacts.toml`), translate the v4.9.8 diff (six files), rerun every GAMS reference with v4.9.8. Rule-level; explicit yes. | `CLAUDE.md` Baseline (#96) |
| 11 Nov 2026 | CPLEX solves for the eight new JRC scenarios (#94 decision 2): with REDUCE NO (the harness's reduce_off variant) every scenario is infeasible under TIMES v4.9.7 (one EQL_ACTBND row that REDUCE removes); PSI's own setup (as_run) passes presolve at the size of the 28 Oct v4.8.3 solve. TIMES v4.9.7 is not at fault. Layer-3 solves run on as_run; reduce_off keeps its checkpoints and matrix only. | this log; local logs |
| 3 Nov 2026 | Phase 1 plan approved; work through it and stop only to depart from it. | `CLAUDE.md` (#23) |
| 3 Nov 2026 | M1.4 (the DD reader) is developed alongside M1.3, in a second Claude tab and worktree. | `CLAUDE.md` (#23) |
| 3 Nov 2026 | Nightly GAMS and probe runs start at 23:05. | nightly batch script on James's machine |
| 3 Nov 2026 | GitHub auto-merge: agreed. | chat only |
| 3 Nov 2026 | Two check-ins a day: 9:00 and 16:45 (16:30 from 5 Nov). | `CLAUDE.md` (#23, #44) |
| 3 Nov 2026 | The 5x speed target: not answered. | Open decisions |
| 5 Nov 2026 | M1.3 gate not passed yet; add the chain run to the nightly probes. | #47 |
| 5 Nov 2026 | Add JRC-EU-TIMES-cli_ll and the TIM-bau gate run to the nightly; TIM results stay local. | nightly batch; `docs/m13-plan.md` |
| 5 Nov 2026 | The equation families M1.1 left untranslated become M1.3 changes (19-24). | `docs/m13-plan.md` (#50) |
| 5 Nov 2026 | Make MPS files for every test model and scenario. | #48 |
| 5 Nov 2026 | James prepares DD scenarios for one more model; its licence is checked before any use. | chat only |
| 5 Nov 2026 | demo12 variants approved; built in the order 1, 5, 2, 3, 6, 7, 4. | `docs/demo12-variants.md` |
| 5 Nov 2026 | Change 20b (early retirement, DSC code) comes into M1.3; change 25 (coef -> pre-solve) is done in M1.3, not M1.5. | `docs/m13-plan.md` (#55) |
| 6 Nov 2026 | QA log: TIMES.jl checks errors as GAMS does (change 25b). TIM-bau gate runs stay local. | `docs/m13-plan.md` (#55) |
| 6 Nov 2026 | Import CPLEX's GAMS optimum into TIMES.jl and check feasibility and OBJz (OTUS9r layer 3). | #61 |
| 7 Nov 2026 | JRC-EU-TIMES: clean "not translated" refusals instead of false FAILs (option A), and curex.gms (change 26) and powerflo.vda (27a, 27b) added to M1.3 (option B). | `docs/m13-plan.md` (#62) |
| 8 Nov 2026 | Change 26 first, then 21-25b. | `docs/m13-plan.md` (#64) |
| 8 Nov 2026 | Harness fix (CHECK status, redo old-GAMS dumps): not answered. | Open decisions |
| 8 Nov 2026 | OTUS9r tax1 probe: no rerun needed; delete its backup copy. | chat only |
| 10 Nov 2026 | "Yes to all three": 27a-2 first (it blocks the M1.3 gate); demo12 variants from DD files in CI; the licence-level option, with TIM and JRC tried from their DD files (results local). | #92, #93 |
| 11 Nov 2026 | cuOpt local WSL2 nightly runs until 8 Dec 2026, then stops for a review. | #95 |
| 11 Nov 2026 | JRC-EU-TIMES runs and its parity report run nightly; policy scenarios (TIMES-NZ shift, OTUS9r tax1_wo_mou, TIM's policy cases, local only) join the nightly probes; both dashboards are updated before each 9:00 check-in. | nightly batch on James's machine (no PR) |
| 11 Nov 2026 | Keep this decision log, with its rule. | `docs/decisions.md` |

## Log by pull request

### #94 Suite: the other eight JRC-EU-TIMES WIMBY scenarios (open; both decisions answered)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Add the other eight JRC-EU-TIMES scenarios to the suite? | Yes, all eight; the nightly makes their checkpoints and runs the DD probe. | James, 11 Nov 2026 |
| 2 | CPLEX solves (about 2.4 h each) for layer 3 on the eight? | Yes, all eight, both variants, started 11 Nov 2026 13:16 on the workstation: 3 runs at a time that day only (12 threads each, 12 threads kept free for other work), reduce_off first. Results stay local; verdicts, counts and timings may be published. | James, 11 Nov 2026 |

### #93 M1.3 (27a-2): powerflo.vda, the allocation of generation and demand to grid nodes (merged 2026-11-11)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Merge before the JRC-EU-TIMES verdict, or wait for it? | Merged before the verdict. | James, 11 Nov 2026 |
| 2 | Keep crafted case demo12_pfa in the crafted suite and CI? | Kept. | accepted by merge, 11 Nov 2026 |
| 3 | GAMS's first-match loop at powerflo.vda L158-159: check it in 27b-2's two-node case? | Translation follows GAMS; checked in 27b-2. | accepted by merge, 11 Nov 2026 |

### #92 M1.4 (6): the DD reader on every suite and crafted model (merged 2026-11-11)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Record K3 (GAMS licence level as the `licencelevel` run option) as approved? | Approved. | James, 9 Nov 2026 (#84) |
| 2 | K2 recorded as approved from the merge of #91: right? | Recorded; explicit yes still needed (Open decisions). | accepted by merge, 11 Nov 2026 |
| 3 | Leave issue #87 open only for attributes (`V.UP(i) = 1`)? | Left open for that. | accepted by merge, 11 Nov 2026 |

### #91 M1.4 (5): from DD files to the solved model, with no GAMS state; alias fix (merged 2026-11-10)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Approve K2 in `docs/known-differences.md`? | Recorded as approved from the merge; explicit yes still needed (Open decisions). | accepted by merge, 10 Nov 2026 |
| 2 | Nightly HiGHS solves for demo12, OTCGEN, OTNYC; TIMES-NZ and OTUS9r stop at the matrix? | As proposed; the full TIMES-NZ solve is run by hand. | accepted by merge, 10 Nov 2026 |
| 3 | Alias fix in `gset` (a stale copy of PYR) | Fixed, with a unit test. | accepted by merge, 10 Nov 2026 |

### #90 cuOpt nightly on: GPU-share sweep on GitHub, local nightly in WSL2 (merged 2026-11-10)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Set up the GitHub T4 runner for the nightly | Nightly on a GitHub T4 runner (`CLAUDE.md`, cuOpt lane). | James, 10 Nov 2026 |
| 2 | Wednesday's full suite: set `CUOPT_FIXTURES=all` and `CUOPT_GPU_SHARES=100`? | Not known whether set. | open |
| 3 | Which other outcomes turn the nightly red? | Not decided. | open |
| 4 | GPU scaling: release asset of open core-model references, or native Linux? | Not decided. | open |

### #89 Phase 2 notes: P2-5 schemas for data and equations (merged 2026-11-10)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep P2-5 on the backlog? | Provisional; nothing starts until James confirms. | open |
| 2 | Run all three pilots after M1.7? | Not decided. | open |
| 3 | "MathSpec" read as `energy-models/mathspec` | As proposed. | accepted by merge, 10 Nov 2026 |

### #88 M1.4 (2c): the TIMES source as a pinned download (merged 2026-11-10)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Download GitHub's archives of the pinned commits (SHA-256 checked), not a copy on a TIMES.jl release? | ETSAP's archives, hash-checked. | James, 10 Nov 2026 (pinned download); accepted by merge, 10 Nov 2026 (archive source) |
| 2 | TIMES_Demo (CC BY 4.0) as a second pinned download, fetched on demand | As proposed. | accepted by merge, 10 Nov 2026 |

### #86 M1.4 (2-4, 2b): the whole TIMES program compiles without GAMS (merged 2026-11-10)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | TIMES v4.9.7 source as a pinned, hash-checked download (also in CI)? | Yes; added in #88. | James, 10 Nov 2026 |
| 2 | Changes 2-4 and 2b as one PR? | One PR. | accepted by merge, 10 Nov 2026 |
| 3 | Log the `$IF DEFINED` after-assignment gap as future tests? | Logged as issue #87. | James, 10 Nov 2026 |

### #85 M1.4 (1): the DD and run-file parser (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Read a lone number (`G_DYEAR / 2005 /`) as a scalar's value, as GAMS does? | Yes. | James, 9 Nov 2026 |
| 2 | Generate the ~255 TIMES declarations by a script into a committed Julia file citing GAMS lines? | Yes. | James, 9 Nov 2026 |

### #84 M1.4 (0): the plan for the DD-file reader (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | VAR_UC from the GAMS licence level (initmty.mod L448): a run option with a known-difference note (K3)? | Yes; default as on James's workstation. | James, 9 Nov 2026 |
| 2 | DATAGDX (initmty.mod L489-508) stays refused? | Refused. | accepted by merge, 9 Nov 2026 |
| 3 | M1.4 ahead of 27a-2? | As stated; changed on 10 Nov: 27a-2 first. | accepted by merge, 9 Nov 2026; James, 10 Nov 2026 |

### #83 Dashboard: ten 16:9 slides in the ESMA brand, with the logo (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Publish the ESMA logo in this public repository? | Yes, keep it on the dashboard. | James, 9 Nov 2026 |
| 2 | Logo size: keep about 150 px, or larger? | Kept as is. | James, 9 Nov 2026 |

### #82 cuOpt lane: layer 3 on the GPU, WSL2 setup and a nightly GPU workflow (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Switch the GitHub GPU nightly on? | On, from #90. | James, 10 Nov 2026 (`CLAUDE.md`) |
| 2 | Only barrier + crossover turns the nightly red; PDLP is reported only? | As drafted. | accepted by merge, 9 Nov 2026 |
| 3 | All 17 fixtures nightly, or demo12_off only? | demo12_off by default since #90; all on request. | accepted by merge, 10 Nov 2026 (#90) |
| 4 | `.wslconfig` with `processors=12`? | As drafted. | accepted by merge, 9 Nov 2026 |

### #81 M1.3 (25c, proposed): the reduced flows of the coefficient stage (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Take the reduced flows as change 25c? | Yes. | James, 9 Nov 2026 |

### #79 M1.3 (27b): powerflo.vda DECL and EQ_GR_POWFLO, phase-angle grids (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Declare the power-flow variables only under %POWERFLO%, as mod_vars.mod L95 does? | As proposed. | accepted by merge, 9 Nov 2026 |
| 2 | Split 27b like 27a (PTDF and node-allocation equations later)? | Split. | accepted by merge, 9 Nov 2026 |

### #78 M1.3 (27a): powerflo.vda PREP and main block, phase-angle grids (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | PTDF and node allocation in a 27a-2, before 27b, or 27b first? | Phase-angle 27b came next (#79); 27a-2 first of the rest. | accepted by merge, 9 Nov 2026; James, 10 Nov 2026 |
| 2 | The probe skips symbols missing from the next dump, and TJL_SOLVEINFO | As proposed. | accepted by merge, 9 Nov 2026 |

### #77 M1.3 (25b-3): crafted QA cases, warnings and a FATAL abort (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | demo12_qa99 made with `--only presolve`, fixtures from the work folder? | As proposed. | accepted by merge, 9 Nov 2026 |
| 2 | ERRLEV 33 unit-tested only, or a crafted GDX case? | Unit-tested only. | accepted by merge, 9 Nov 2026 |

### #76 M1.3 (25b-2): pp_qack.mod's QA checks and the ERRLEV abort (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | ERRLEV above 33 stops the run with a Julia error, as GAMS aborts? | As proposed (follows the 6 Nov decision). | accepted by merge, 9 Nov 2026 |
| 2 | Leave out the EXECERROR block (L183-201)? | Left out. | accepted by merge, 9 Nov 2026 |

### #75 M1.3 (25b-1): the QA log, its machinery and the preprocessing checks (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | GAMS's compile-warning count as a run input, set by the M1.4 reader? | As proposed; passed to M1.4. | accepted by merge, 9 Nov 2026 |
| 2 | Copy QA_CHECK.LOG from the work folders, or rerun `--only presolve`? | Copied; no rerun. | accepted by merge, 9 Nov 2026 |
| 3 | `.gitattributes`: `test/fixtures/*.log -text` | Added. | accepted by merge, 9 Nov 2026 |

### #74 M1.3 (25-5): the coefficient stage's scratch; the gate chains on to presolve (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Translate the reduced flows as one change, after 25b and before 27a? | Yes, as change 25c (#81). | James, 9 Nov 2026 |
| 2 | Gate wording: a stop past ppm prints "the chain ends before coef" and passes? | As proposed. | accepted by merge, 9 Nov 2026 |

### #73 M1.3 (25-4): bndmain, pp_qack and pp_clean data; the CI chain end to end (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Fix filparam.gms's scratch (FIRST_VAL, LAST_VAL, MY_FYEAR) as a follow-up before 25b? | Done as 25-5 (#74). | accepted by merge, 9 Nov 2026 |

### #72 M1.3 (25-3): eqmain.mod and equ_ext.vda data statements (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Refuse dispatching preparation (eqactups.vda L9-32) and REG_BNDCST/REG_CUMCST? | Refused. | accepted by merge, 9 Nov 2026 |

### #71 M1.3 (25-2): eqobjfix.mod and eqobsalv.mod data (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | New GAMS rule G52 (`OPTION a <= b` and `a < b` domain matching) | Logged in `docs/discrepancies.md`. | accepted by merge, 9 Nov 2026 |

### #70 M1.3 (25-1): the coef -> pre-solve step begins (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Split change 25 in four parts (25-1 to 25-4)? | Split. | accepted by merge, 9 Nov 2026 |
| 2 | A fifth probe segment, coef -> presolve? | Added. | accepted by merge, 9 Nov 2026 |

### #69 M1.3 (24): eqactups.vda L127-158, EQ_SLSIFT, load shifting (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | demo12 variant 1 (load shifting) as crafted cases demo12_ls and demo12_lst? | Made. | accepted by merge, 9 Nov 2026 |
| 2 | Design taken from the GAMS code and TIMES-NZ's DD (User Note not read)? | As proposed. | accepted by merge, 9 Nov 2026 |

### #68 M1.3 (23): eqflomrk.mod L56-105, market-share constraints (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | A demo12 variant with trade to check the EXP term: now, or before the gate? | Not decided. | open |

### #67 M1.3 (22): uc_*.mod, the user-constraint attribute factors (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Change 22 as every attribute factor but ANNUL and ONLINE, or close 22 at #66? | Merged as change 22. | accepted by merge, 9 Nov 2026 |
| 2 | ANNUL and ONLINE stay refused? | Refused (`UC_ATTR_REFUSED`). | accepted by merge, 9 Nov 2026 |

### #66 M1.3 (21): equserco.mod L80-106, dynamic user constraints (merged 2026-11-09)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | The UC_DYNT attributes come in with change 21? | As proposed. | accepted by merge, 9 Nov 2026 |
| 2 | Change 22's scope: the other UC attributes on a crafted case, ANNUL refused? | As proposed (#67). | accepted by merge, 9 Nov 2026 |
| 3 | Crafted case demo12_ucdyn? | Kept. | accepted by merge, 9 Nov 2026 |

### #65 M1.3: keep pp_off.mod's scratch (FIL, STARTOFF, ENDOFF) (merged 2026-11-08)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep pp_off.mod's scratch as GAMS leaves it (reverses changes 4-5)? | Kept. | James, 8 Nov 2026 |

### #64 M1.3 (26): curex.gms, currency conversion (merged 2026-11-08)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Read `$IF DEFINED R_CUREX` (coef_obj.mod L99) from whether R_CUREX has data? | Confirmed. | James, 8 Nov 2026 |
| 2 | `gset_opt`/`gparam_opt` return computed symbols the dump lacks? | As proposed. | accepted by merge, 8 Nov 2026 |
| 3 | Change 26 ahead of 21-25b? | Yes. | James, 8 Nov 2026 |

### #63 Dashboard, 7 Nov 2026 (merged 2026-11-07)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Show OTUS9r's objective check from cross-evaluation, with a caption saying so? | Shown so. | accepted by merge, 7 Nov 2026 |

### #62 M1.3: POWERFLO derived from the data; plan changes 26-27 (merged 2026-11-07)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | JRC-EU-TIMES-cli_ll joins the M1.3 gate (local runs, verdicts published)? | Yes. | James, 7 Nov 2026 |
| 2 | demo12 variant 6 (PTDF grid) ahead of variants 4, 3 and 7a? | Yes. | James, 7 Nov 2026 |

### #61 OTUS9r layer 3: CPLEX optimum cross-evaluated in TIMES.jl (merged 2026-11-06)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Accept one-way cross-evaluation as OTUS9r's layer 3 for the M1.3 gate? | Counted so; explicit yes still needed (Open decisions). | accepted by merge, 6 Nov 2026 |

### #59 M1.3 (20b-3): prepret.dsc L66-80, VAR_RCAP and VAR_SCAP bounds (merged 2026-11-06)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Extend demo12_refit_afc with retirement bounds rather than add a new case? | Extended; fixtures regenerated. | accepted by merge, 6 Nov 2026 |

### #58 M1.3 (20b-2): prepret.dsc L87-88, -VAR_SCAP capacity terms (merged 2026-11-06)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Mark discrepancy D1 withdrawn rather than delete it? | Withdrawn. | accepted by merge, 6 Nov 2026 |
| 2 | Keep crafted case demo12_refit_afc (about 7 MB of fixtures)? | Kept. | accepted by merge, 6 Nov 2026 |

### #57 M1.3 (20b-1): prepret.dsc L89-117, EQ_CUMRET, EQL_SCAP, EQL_REFIT (merged 2026-11-06)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Split 20b in four parts, the family refused until the last? | Split. | accepted by merge, 6 Nov 2026 |
| 2 | Leave EQ_DSCRET and the IN rows of EQL_SCAP refused? | Refused. | accepted by merge, 6 Nov 2026 |

### #56 M1.3 (20): equcrtp.vda L73-121, dynamic bounds (merged 2026-11-06)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep crafted case demo12_ucrt (about 9 MB of fixtures)? | Kept. | accepted by merge, 6 Nov 2026 |

### #54 docs: P2-3 multi-threaded equation generation (merged 2026-11-06)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Allow LP-identical data-structure fixes before M1.7? | Not decided. | open |

### #53 demo12 variant 5: retrofits and lifetime extensions (merged 2026-11-05)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Fix the silent early-retirement gap (check RP_RTF, not the VNRET macro)? | Fixed. | accepted by merge, 5 Nov 2026 |
| 2 | Bring change 20b (early retirement and refits) into M1.3? | Yes. | James, 5 Nov 2026 |

### #52 demo12 variant 2: dispatching and unit commitment (merged 2026-11-05)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Test variants in CI by preprocessing plus an exact refusal list until translated? | As proposed. | accepted by merge, 5 Nov 2026 |
| 2 | LP only; discrete unit commitment waits for MIP support? | As proposed. | accepted by merge, 5 Nov 2026 |

### #50 M1.3 (19): eqstgips.mod, EQ_STGIPS (merged 2026-11-05)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Changes 19-25 in M1.3, or leave change 25 for M1.5? | All in M1.3, change 25 included. | James, 5 Nov 2026 |

### #49 M1.3 (17c): crafted case demo12_red17b (merged 2026-11-05)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Crafted cases in `reference/crafted.toml`, not `suite.toml`? | As proposed. | accepted by merge, 5 Nov 2026 |

### #48 Reference harness 0.3.1: --only convert (merged 2026-11-05)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Merge before the nightly so CONVERT makes the missing MPS files? | Merged; MPS files for every model and scenario. | James, 5 Nov 2026 |
| 2 | No CPLEX solve for JRC-EU-TIMES-cli_ll yet; a weekend batch before M1.5? | As proposed. | accepted by merge, 5 Nov 2026 |

### #47 M1.3 gate checks: the chain from the input dump, CI on demo12, timings (merged 2026-11-05)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Declare the M1.3 gate passed? | Not yet; the chain run joins the nightly. | James, 5 Nov 2026 |
| 2 | Add TIM-bau's gate run to the nightly as a local log? | Yes; checked on James's machine, results stay there. | James, 5 Nov 2026 |
| 3 | eqmain.mod preparation and pp_qack.mod: M1.5 or M1.3? | M1.3, as change 25. | James, 5 Nov 2026 |

### #46 M1.3 (17b): the model under REDUCE YES (merged 2026-11-05)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | New CI fixture demo12_red (REDUCE YES, 2.6 MB)? | Added. | accepted by merge, 5 Nov 2026 |
| 2 | Make the untranslated equation families their own changes before Phase 1 ends? | Yes, as M1.3 changes 19-24. | James, 5 Nov 2026 |
| 3 | A crafted case for the two 17b branches demo12 does not reach? | Made as demo12_red17b (#49). | James, 5 Nov 2026 |

### #45 M1.3 (18b): ppm_ext.vda L59-169, the end of preprocessing (merged 2026-11-05)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Refuse RP_FFSGG and dynslite.vda? | Refused. | accepted by merge, 5 Nov 2026 |
| 2 | Compare every set and parameter at ppm, less the QA-log scalars? | As proposed. | accepted by merge, 5 Nov 2026 |

### #44 M1.3 (18a): ppm_ext.vda L11-58 with pp_actef.vda (merged 2026-11-05)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Split change 18 into 18a and 18b? | Split. | accepted by merge, 5 Nov 2026 |
| 2 | Refuse GR_VARGEN data and discrete capacities? | Refused. | accepted by merge, 5 Nov 2026 |
| 3 | pp_actef.vda L22 unreachable: translate as written (G50)? | As written. | accepted by merge, 5 Nov 2026 |
| 4 | Check-ins at 9:00 and 16:30 in `CLAUDE.md` | Recorded. | James, 5 Nov 2026 |

### #43 M1.3 (17a): ppmain.mod L1336-1357, pp_reduce.red (merged 2026-11-05)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Split change 17 into 17a and 17b? | Split. | accepted by merge, 5 Nov 2026 |
| 2 | Refuse ETL with REDUCE, dynslite.vda and MACRO? | Refused. | accepted by merge, 5 Nov 2026 |

### #42 M1.3 (16): ppmain.mod L1228-1333, blending refused (merged 2026-11-05)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Refuse blending data and translate only the REFUNIT default, or add a blending test model? | Refused; no blending test model. | accepted by merge, 5 Nov 2026 |

### #40 M1.3 (15a): ppmain.mod L1101-1179, user-constraint defaults (merged 2026-11-05)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Split change 15 into 15a and 15b, or one PR? | Split. | accepted by merge, 5 Nov 2026 |

### #37 M1.3 (13a): ppmain.mod L936-1001, balance types, bounds (merged 2026-11-05)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Split change 13 into 13a and 13b? | Split. | accepted by merge, 5 Nov 2026 |

### #35 gams_sort!: rank each key once (merged 2026-11-05)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | A speed-up in shared code during Phase 1, with the same record order? | Merged; explicit yes still needed (Open decisions). | accepted by merge, 5 Nov 2026 |

### #33 M1.3 (11a): ppmain.mod L800-821, pp_chp.mod (merged 2026-11-05)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Split change 11 into 11a and 11b? | Split. | accepted by merge, 5 Nov 2026 |
| 2 | Generalise `lvlfc!` to `pp_lvlfc!` for the flow calls? | Generalised; change 10 re-checked. | accepted by merge, 5 Nov 2026 |

### #30 M1.3 (9): ppmain.mod L616-682, pp_qafs.mod, SHAPE/MULTI, defaults (merged 2026-11-04)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Two probe steps at ppm, on what nothing later changes? | As proposed. | accepted by merge, 4 Nov 2026 |
| 2 | New check `scripts/m13_replay.jl`, run on James's machine? | Added. | accepted by merge, 4 Nov 2026 |
| 3 | Add `m13_replay.jl` to the nightly run? | Not decided. | open |
| 4 | Crafted cases start from the prelv dump? | As proposed. | accepted by merge, 4 Nov 2026 |
| 5 | New GAMS rules G46 and G47 | Logged. | accepted by merge, 4 Nov 2026 |
| 6 | Leave out pp_qafs.mod's QA-log messages and the DISPLAY of L64? | Left out. | accepted by merge, 4 Nov 2026 |
| 7 | `filparam!` gains `back` and `fwd` arguments? | Added. | accepted by merge, 4 Nov 2026 |

### #28 M1.3 (8b): pp_prelv.vda, the prep -> prelv segment complete (merged 2026-11-04)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Compare every prelv symbol, less the QA-log scalars? | As proposed. | accepted by merge, 4 Nov 2026 |
| 2 | Refuse TS_OFF data and %POWERFLO% YES? | Refused (POWERFLO later translated in change 27). | accepted by merge, 4 Nov 2026 |
| 3 | New GAMS rule G45 (refines G26) | Logged. | accepted by merge, 4 Nov 2026 |
| 4 | Keep pp_off.mod's scratch (FIL, STARTOFF, ENDOFF)? | Kept, in #65. | James, 8 Nov 2026 |
| 5 | Fix to 8a's code: scalar F kept as EPS | Fixed. | accepted by merge, 4 Nov 2026 |
| 6 | About 2-3.5 min per step acceptable in Phase 1? | Accepted; speed-ups in Phase 2. | accepted by merge, 4 Nov 2026 |

### #27 M1.3 (8a): ppmain.mod L461-611 (merged 2026-11-04)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Split change 8 into 8a and 8b? | Split. | accepted by merge, 4 Nov 2026 |
| 2 | Compare 30 symbols; RVP only without TS_OFF data? | As proposed. | accepted by merge, 4 Nov 2026 |
| 3 | Leave out the QA-log lines and L484's empty data statements (G39)? | Left out. | accepted by merge, 4 Nov 2026 |
| 4 | GAMS replay sets %OBLONG% for OBJ MOD, as initmty.mod L427 does? | Set; that crafted state now uses OBJ AUTO. | accepted by merge, 4 Nov 2026 |
| 5 | Branch `IFQ<10` (L528) cannot be reached with data | Translated, not checked. | accepted by merge, 4 Nov 2026 |
| 6 | About 4 min on OTUS9r acceptable in Phase 1? | Accepted; speed-ups in Phase 2. | accepted by merge, 4 Nov 2026 |

### #26 M1.3 (7b): ppmain.mod L329-460, timeslice levels (merged 2026-11-04)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Compare 24 symbols at prelv, 8 more at the segment end? | As proposed. | accepted by merge, 4 Nov 2026 |
| 2 | QA-log warning of L338-340 left to the QA-log item? | As proposed. | accepted by merge, 4 Nov 2026 |
| 3 | New GAMS rule G44 | Logged. | accepted by merge, 4 Nov 2026 |
| 4 | Copy three surprising GAMS behaviours (L336-337, L343, L428-432) as written? | Copied as written. | accepted by merge, 4 Nov 2026 |
| 5 | Crafted cases use demo12's commodity 'ACT' | As proposed. | accepted by merge, 4 Nov 2026 |

### #25 M1.3 (7a): preppm.mod L218-252, preshape.gms, ppmain.mod L249-328 (merged 2026-11-04)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Split change 7 into 7a and 7b? | Split. | accepted by merge, 4 Nov 2026 |
| 2 | Compare 39 symbols at prelv, 8 more at the segment end? | As proposed. | accepted by merge, 4 Nov 2026 |
| 3 | Leave out L253 (`SUBT` data statement) and the QA-log message of L273-277? | Left out. | accepted by merge, 4 Nov 2026 |
| 4 | Refuse %VINTOPT% 1 at preppm.mod L245-251 too? | Refused. | accepted by merge, 4 Nov 2026 |
| 5 | New GAMS rule G43 (MOD sign, preshape rounding) | Logged. | accepted by merge, 4 Nov 2026 |
| 6 | Crafted cases change demo12 in ways a real model would not | Kept. | accepted by merge, 4 Nov 2026 |

### #24 M1.3 (6b): preppm.mod L213-217, prep_ext.vda (merged 2026-11-03)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Compare every prep symbol, less PUTOUT, PUTGRP and ERRLEV? | As proposed; the QA log came later (25b). | accepted by merge, 3 Nov 2026 |
| 2 | `timslice!` keeps MY_SUM? | Kept. | accepted by merge, 3 Nov 2026 |
| 3 | Refuse STAGES, POWERFLO, GR_VARGEN, %VINTOPT% 1, WAVER YES and six extensions? | Refused (POWERFLO later translated in change 27). | accepted by merge, 3 Nov 2026 |
| 4 | Refuse UC_ACTBET data (not in the plan)? | Refused. | accepted by merge, 3 Nov 2026 |
| 5 | IER extension not detected | Noted in `docs/gams-julia-map.md`. | accepted by merge, 3 Nov 2026 |
| 6 | New GAMS rule G42 | Logged. | accepted by merge, 3 Nov 2026 |
| 7 | About 3 min on OTUS9r acceptable in Phase 1? | Accepted; speed-ups in Phase 2. | accepted by merge, 3 Nov 2026 |

### #21 M1.3 (6a): preppm.mod L1-212, the interpolation of user data (merged 2026-11-03)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Split change 6; approve the 6b plan? | Split; 6b done as planned (#24). | accepted by merge, 3 Nov 2026 |
| 2 | Refuse currency conversion (curex.gms)? | Refused at first; translated later as change 26 (#64). | accepted by merge, 3 Nov 2026; reversed by James, 7 Nov 2026 |
| 3 | Leave scratch Z and MY_F out of the `nointerp` test case? | Left out; open item in `docs/m13-plan.md`. | accepted by merge, 3 Nov 2026 |
| 4 | A `bare` option in `scripts/gams_replay.jl` (G40)? | Added. | accepted by merge, 3 Nov 2026 |
| 5 | New GAMS rules G40 and G41 | Logged. | accepted by merge, 3 Nov 2026 |
| 6 | Compare PRC_CAP only without NCAP_OLIFE data? | As proposed. | accepted by merge, 3 Nov 2026 |
| 7 | About 105 s on OTUS9r acceptable in Phase 1? | Accepted; speed-ups in Phase 2. | accepted by merge, 3 Nov 2026 |

### No decisions

No decisions: #23 (it records the decisions of 3 Nov 2026; see the chat
table), #29, #31, #32, #34, #36, #38, #39, #41, #51, #55 (it records the
decisions of 5 and 6 Nov 2026), #60, #80, #95.
