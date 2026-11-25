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
| 4 Nov 2026 | #30 | Add `scripts/m13_replay.jl` (needs GAMS, about 7 min) to the nightly run? | none given | Open (#30, decision 3). Checked 14 Nov 2026: the workstation batch does not run it. |
| 8 Nov 2026 | chat | Harness fix as one small PR: CHECK status for a non-optimal solve; redo `ppm/` and `coef/` made with older GAMS | one small PR | Open; no PR yet. Checked 14 Nov 2026: `make_reference.py` still reports OK for a run that GAMS ends without an optimum. |
| 10 Nov 2026 | #89 | Keep P2-5 (data and equation schemas) on the Phase 2 backlog, with its three pilots after M1.7? | keep; all pilots after M1.7 | Open (#89, decisions 1 and 2); provisional until James confirms. |
| 10 Nov 2026 | #90 | Which other outcomes turn the cuOpt nightly red? | proposed in the chat | Open (#90, decision 3) |
| 10 Nov 2026 | #90 | Wednesday's full cuOpt suite: set `CUOPT_FIXTURES=all` and `CUOPT_GPU_SHARES=100`? | yes | Open (#90, decision 2); a GitHub setting only James can make. Checked 14 Nov 2026: the repository has no Actions variable set, so the nightly runs demo12_off at 25, 50 and 100%. Since 22 Nov 2026 it also waits for the rule "no GPU runner test until it passes locally" (below, Decisions in the chat): in the local nightly, `all` fails barrier on most demo12 variants (1.0e-6 to 2.3e-6 against 1e-6) and outright on flomrk and ashar. |
| 14 Nov 2026 | chat (issue #97) | After #101 (the early part of #97: the solution of a solve written for downstream tools): may more of #97 start before M1.5 closes, beyond the levels and marginals approved on 12 Nov 2026? Rule-level (milestone order). | no; the rest waits for M1.6 in its order | Open; added to the list at the review of 14 Nov 2026. |
| 14 Nov 2026 | chat | Remove the unused git worktree `TIMESjl-m14` on the workstation? M1.4 has been developed in the main working copy; the worktree is 213 commits behind `main` and has no commits of its own. | yes | Open; added to the list at the review of 14 Nov 2026. Nothing is removed without James's word. |
| 14 Nov 2026 | chat | The commit trailer Claude Code supplies no longer names the model (`Co-Authored-By: Claude`), while the README points readers to that line to see which model wrote each commit. Keep the trailer as supplied and reword the README, or write the model's name in each commit message? | keep the trailer as supplied; reword the README | Open; added to the list at the review of 14 Nov 2026. Commits keep the supplied line meanwhile (`CLAUDE.md`). |
| 14 Nov 2026 | chat | Workstation batch: count jobs by threads (up to 8 jobs within 36 threads, since most checks use one core) instead of "at most 4 CPU-heavy runs"? Rule-level (the run limits in `CLAUDE.md`). | yes | Open; the batch keeps to 4 runs (3 while development runs use the fourth slot). |
| 14 Nov 2026 | chat (issue #100) | cuOpt lane: switch its check to PDLP with crossover, and report the barrier-with-crossover behaviour of issue #100 to the cuOpt project with the open demo12 case? | yes to both; reviewed with the cuOpt results on 8 Dec 2026 | Open; added to the list at the review of 14 Nov 2026. A report to another project is James's to approve. More evidence, 22 Nov 2026: on the six open reference runs (reduce_off), cuOpt barrier with crossover found no optimum on any of them, on the GitHub T4 (cuOpt 26.10.1, [run 45055717888](https://github.com/esma-ie/TIMESjl/actions/runs/45055717888)) and, for OTNYC and OTCGEN, on the workstation's Quadro (cuOpt 26.10.0, local nightly): a numerical error or the 1800 s limit; PDLP neither (one point 1.5e-4 off). Layer 2 passed on all six. On the local fixtures, barrier misses 1e-6 by a little (1.0e-6 to 2.3e-6) on most demo12 variants. Asked again at the 9:00 check-in of 23 Nov 2026 as q1 (James, 22 Nov 2026). |
| 14 Nov 2026 | chat (issue #17) | The DD reader as a separate package (issue #17): decide after the M1.4 gate? | keep it in this repository until Phase 1 ends, and answer on the issue then | Open; added to the list at the review of 14 Nov 2026. |
| 14 Nov 2026 | #109 | Is the M1.3 gate passed? Rule-level (a milestone gate). The evidence for each criterion is in docs/m13-plan.md, "Gate close-out, 14 Nov 2026". | yes | James, 14 Nov 2026: not passed yet (#109, decision 1); every remaining refused feature is translated first (linear dispatching is #120; unit commitment next, then the others in the order of the 16:30 check-in). Stays here: asked again when they are translated and tested. Asked again on 22 Nov 2026 ("now can we close M1.3 and M1.4?"), with the stochastic extension out of the gate: evidence in docs/m13-plan.md, "Gate audit, 22 Nov 2026"; recommended yes once a batch pass and the timing rerun pass on the merged stack (the DAM_ELAST question was answered on 22 Nov 2026: out of the gate, #192 d1). |
| 14 Nov 2026 | #117 | Is the M1.4 gate passed? Rule-level (a milestone gate); it waits for the M1.3 gate (#109). The evidence for each criterion is in docs/m14-plan.md, "Gate close-out, 14 Nov 2026". | yes, once the M1.3 gate is passed and the batch has rerun the chain from DD files on the merged stack | Open (#117, decision 1); needs James's explicit yes. Its CI criterion is met: #124 merged on 14 Nov 2026, so the unit commitment is translated and demo12_uc runs in the chain from DD files (#118, decision 2; #124, decision 6). Asked again on 22 Nov 2026 with #109: evidence in docs/m13-plan.md, "Gate audit, 22 Nov 2026". |
| 14 Nov 2026 | #121 | REFUNIT 3 (ppmain.mod L1301-1316) and the blending costs in another currency (curex.gms L59-60) were checked against GAMS only on a scratch case that is not in the repository (demo12_blndx). Add it as a second crafted case (about 7.5 MB of fixtures), or leave the check as a note in docs/m13-plan.md? | leave it as a note | Open (#121, decision 5); nothing is built in beyond the note. |
| 14 Nov 2026 | #122 | eqcapvac.mod L27 adds NCAP_PASTI without COEF_CSV or COEF_AF, so a past investment counts in full, with availability 1, in every period of its simulated vintage (D36). Translated as written. Report it to ETSAP together with coef_csv.mod L48? Rule-level (a report to ETSAP). | yes | Open (#122, decision 4); needs James's explicit yes. |
| 15 Nov 2026 | #129 | solve.stp L281 fixes the blending variables (VAR_BLND) of the pending periods of a stepped run at zero, and no statement of v4.9.7 lifts that fix when those periods become a step's own, so blending would stay at zero for the rest of the run. Translated as written. (a) Check it with a stepped variant of the blending case? Done in #134: the LPs GAMS solved for demo12_step3 show that GAMS keeps the fix, and blending is free only in the periods of the first step (docs/discrepancies.md, D43). (b) Report D43 to ETSAP as a likely fault of v4.9.7? Rule-level (a report to ETSAP). | (b) yes, with the other reports | Open (#129, decision 4; #134, decision 1); (a) is done, (b) needs James's explicit yes. |
| 15 Nov 2026 | #131 | bnd_cum.mod is not idempotent, and a stepped run includes it again in every step (solve.stp L227). From its first step on, GAMS 54.6.1 applies a cumulative bound to EOH (FLO_CUM, COM_CUMNET, COM_CUMPRD) without the modifier of its N record: the run that is not stepped scales the bound, the stepped run does not (docs/discrepancies.md, D41; seen in GAMS's dumps of every step of demo12_step2). TIMES.jl follows GAMS as it runs (layers 1 and 2 identical per step). Report it to ETSAP as a likely fault of v4.9.7? Rule-level (a report to ETSAP). | yes, with the other reports | Open (#131, decision 2); needs James's explicit yes, a merge does not answer it. |
| 15 Nov 2026 | #132 | OBJ ALT in a stepped run of more than one step fails in GAMS 54.6.1 itself: coef_alt.lin L51 (L52 with OBLONG) divides by zero for a period beyond the step's horizon, GAMS skips the solve of that step, clears the error and goes on, and the run ends with "Normal completion" and a result in which the skipped steps fixed nothing (docs/discrepancies.md, D42). TIMES.jl stops at the first such step with an error that names the line; with one step it equals GAMS (demo12_stepalt1). (a) Accept that TIMES.jl stops there instead of copying the skipped steps? (b) Report D42 to ETSAP as a likely fault of v4.9.7? Rule-level (a result of GAMS that is not copied; a report to ETSAP). | (a) yes; (b) yes, with the other reports | Open (#132, decision 2); needs James's explicit yes. |
| 15 Nov 2026 | #137 | D44: the grid note's N-1 bound (TIMES-Grid-Features §2.4) uses only a region's own line capacity; the code also takes the capacity in the other internal region when the line has none in the region, and under REDUCE a line without capacity data adds nothing (powerflo.vda L349-358). TIMES.jl follows the code. Report D44 to ETSAP as a documentation gap? Rule-level (a report to ETSAP). | yes, with the other reports | Open (#137, decision 1); needs James's explicit yes. |
| 15 Nov 2026 | #139 | The colours James chose on 15 Nov 2026 (#127 d2), as hex values (#139 d1): TIMES.jl in ESMA Dark yellow `#eaaa00` ("sunshine yellow"; the brand book's one yellow, Pantone 124 C) on dark slides and in Dark green `#004539` (Pantone 3308 C) on light slides; GAMS stays `#e06000`, since the brand book has no orange and the ESMA palette's orange `#ff6a1f` (geothermal) falls under the normal-vision floor beside the yellow on dark slides (14.6 against 15; deuteranopia 7.3), where `#e06000` gives 17.2 and 13.5. Are these the colours meant? | as used | Open; a choice #139 made for James, so it stays here until he answers. |
| 15 Nov 2026 | chat | Discrepancies are "dp" in the chat (James, 15 Nov 2026), while docs/discrepancies.md and the code comments write D1 to D44. Rename them to DP1 to DP44 in the repository too, in one pull request, so the chat and the files agree? | yes | Open; nothing is renamed until James answers. |
| 15 Nov 2026 | chat | The workstation batch's DD-file stage: the HiGHS solve of TIMES-NZ shift with REDUCE off hit its one-hour limit on 14 Nov 2026 (3,625.7 s; with REDUCE on it solved in 2,658 s). Solve TIMES-NZ in that stage with REDUCE on only, its REDUCE-off model still compared with GAMS's matrix and cross-evaluated? | yes | Open; the batch keeps its one-hour limit meanwhile. |
| 17 Nov 2026 | #155 | coef_nio.mod L58 computes COEF_RCOM from COEF_CPT before coef_alt.lin L77 fills COEF_CPT (coefmain.mod order), so COEF_RCOM is empty outside the capacity transfer and the VAR_RCAP term of cal_cap.mod is never reached; TIMES.jl does the same. Report it to the TIMES maintainers (ETSAP) as a possible ordering issue? | yes, as a note to ETSAP | Open (#155, decision 2). Nothing in TIMES.jl depends on it. |
| 17 Nov 2026 | #156 | resloadc.vda L111 and L144 read VAR_RLD at 'RL_THMIN' (an underscore) beside 'RL-THMIN': two columns, likely a typo (D45). TIMES.jl follows the code. Report it to ETSAP, in one note with #155 d2 (COEF_RCOM)? | yes, in the same note | Open (#156, decision 3). Nothing in TIMES.jl depends on it. |
| 22 Nov 2026 | #195 | Issue #116 (open) shows GAMS/CPLEX timings in its title and body (GAMS's seconds per step on OTCGEN and OTNYC, and the ratios 10.5x and 4.6x). GitHub keeps every edit of an issue visible, so an edit only takes them out of view. (a) Edit the title and body to drop GAMS's figures (kept in `esma-ie/timesjl-unpublished`), or (b) leave the issue as it is, as the git history (#184 d4)? Rule-level (what the public repository shows). | (a) | Open (#195, decision 5) |
| 22 Nov 2026 | #195 | Keep `esma-ie/timesjl-unpublished` current from the nightly: `build_dashboard_local.ps1` copies `run-timing-unpublished.json` into its clone and commits and pushes it (open models only)? | yes, in a change to the local script | Open (#195, decision 6) |

Reviewed on 14 Nov 2026 against pull requests #1 to #120 (108 merged, six open: #114, #115, #117 to #120). Four questions that James had answered left this list for the log of their pull requests: the demo12 trade case (#68, #104); refused features before v4.9.8 (#109, decision 3); the stepped solve before the gates (#108, decision 3); the M1.4 CI criterion with demo12_uc refused (#118, decision 2). Five questions asked in the chat and never listed were added (issues #97, #100 and #17, the commit trailer, the unused worktree). Every row of the log that is still "open" is either on this list or is a built-in default of an open pull request, which its merge decides. Later the same evening James merged #114 to #125 (eleven pull requests): their built-in defaults are accepted by merge, and his answers on #120 (decision 5), #121 (decision 2) and #125 (decisions 6, 8, 9 and 10) are in the log of those pull requests. Two more pull requests were opened later that evening, #127 (the dashboard changes James asked for on #125) and #128 (M1.5 change 2); #127's choice of the green and the orange joined this list.

On 15 Nov 2026 James merged #126 to #137 (twelve pull requests): their built-in defaults are accepted by merge. The same morning he answered #122 decision 3, #123 decisions 4 and 5, #124 decision 7, #127 decision 2 and #130 decision 2 (in the log of those pull requests), and the scope of the extensions (below); those rows left this list. Four questions joined it: MACRO with IPOPT, the hex values of the colours (#139), the dp prefix in the repository, and the TIMES-NZ solve in the batch.

On 17 Nov 2026 James answered three questions of the list in the chat (below, under Decisions in the chat): the scope of the M1.3 gate (q5, with ETL added), MACRO with IPOPT, and the 5x speed target. Those rows left this list.

On 18 Nov 2026 James merged #147 to #168 (22 pull requests): their built-in defaults are accepted by merge. The same evening he answered q1 and q2 of the M1.3 gate audit (below, under Decisions in the chat): the VAR_UC question of 17 Nov and #150 decision 3 left this list.

On 22 Nov 2026 James answered #192 decisions 1 and 2 (in the log of that pull request): damage costs as elastic supply curves from a base run leave the M1.3 gate and are listed for completion before Phase 1 closes; changes 71-76 of the stochastic extension resume after the move to v4.9.8. Those two rows left this list.

On 25 Nov 2026 James answered the question of 22 Nov 2026 on the cuOpt pause: "keep the nightly on" (below, Decisions in the chat). That row left this list.

## Decisions in the chat (not in a PR list)

| Date | Decision | Where it is recorded |
| --- | --- | --- |
| 25 Nov 2026 | "keep the nightly on", answering the open question of 22 Nov 2026: the pause on GPU runner tests ("until they pass locally") does not include the scheduled GitHub nightly. It keeps running demo12_off at 25, 50 and 100% with barrier and PDLP; `CUOPT_NIGHTLY` stays unset. | this log; `scripts/cuopt/README.md`; `.github/workflows/nightly-gpu.yml` (header) |
| 22 Nov 2026 | "yes, add it to the 9:00 check-in. cancel any further GPU runner tests until they pass locally" (after the first full run of the six open reference runs on the GitHub GPU runner, run 45055717888: no model solved). No manual run of `nightly-gpu.yml` (input `ref_release`, or any model or fixture beyond the nightly's) starts until the same models pass in the local WSL2 nightly. Nothing was running or queued. The scheduled nightly (demo12_off, which passes locally) stays on (James, 25 Nov 2026, above). Issue #100 is asked again at the 9:00 check-in of 23 Nov 2026. | this log; `scripts/cuopt/README.md`; `.github/workflows/nightly-gpu.yml` (header) |
| 22 Nov 2026 | The M1.3 audit of 22 Nov in the chat, options 1 (finish changes 71-76, then the gate) and 2 (the stochastic extension out of the gate): "option 2, move stochastics out of the gate, but do not start tests with v4.9.8 until Monday's nightly's not todays". Rule-level (the gate's scope, a departure from the plan approved on 20 Nov 2026); James's explicit yes. The stochastic extension leaves the M1.3 gate: change 70 (#185) is merged, changes 71-76 come after the gate, and STAGES, SPINES and SENSIS runs stay refused at init_ext. The baseline's move to TIMES v4.9.8 follows the gate, with no v4.9.8 test before the nightly of Monday 23 Nov 2026; the nightly of Sunday 22 Nov runs on v4.9.7. Then asked: "now can we close M1.3 and M1.4?" (the gate questions #109 and #117, Open decisions). | docs/m13-plan.md ("Gate", "Gate audit, 22 Nov 2026", "Plan: the stochastic extension"); this log |
| 22 Nov 2026 | #184 d6, answered in the chat after the reading of the GAMS EULA's "Publication of Benchmarks": "only move CPLEX timings out of the public repo & dashboard and into the local dashboard and a private repo [...] The GAMS data that does not relate to proprietry solvers, like cplex, can stay, such as GAMS-HiGHS runs", and "use esma-ie/timesjl-unpublished and build the follow-up PR". Only the timings of CPLEX and the EULA's other Restricted Solvers (and figures taken from their runs) leave the public repository; GAMS/HiGHS timings come back to the public board, which reverses #184 d5. The private repository `esma-ie/timesjl-unpublished` holds them, open models only. Rule-level; explicit yes. A question to GAMS on the clause (what counts as publication, timings from runs that call no solver, CPLEX figures apart from other solvers' ones) is drafted for James to send. | #195; this log; `docs/dashboard/README.md`; `scripts/run_timing.jl` |
| 22 Nov 2026 | "Put all the timings from all the solver into the local dashboard": the local board (not in this repository) shows TIMES.jl·HiGHS, GAMS·HiGHS, GAMS·CPLEX and cuOpt on the workstation's GPU and on the GitHub T4, on its run-time chart and on a solve-time table of its own. | `C:\git\esma\build_dashboard_local.ps1` (local) |
| 22 Nov 2026 | q1 and q2 of the 22 Nov chat (asked as "d1" and "d2"): "d1 yes, d2 100% only first". q1, rule-level (test data): the reduce_off reference runs of the six open probe runs (TIMES-NZ steady and shift, OTCGEN, OTNYC, OTUS9r reference and tax1_wo_mou) are published as assets of a pre-release of this repository, so the GitHub GPU runner can solve them with cuOpt; each zip carries its model's licence and a notice, and no paths, host, commands or GAMS timings. q2: the first pass runs at 100% of the GPU only, barrier and PDLP; the GPU-share sweep follows on the models that solve. This answers #90 decision 4 (release asset of open core-model references), which leaves the open list. TIM and JRC-EU-TIMES stay off the runner. | #189; `scripts/cuopt/make_ref_bundle.py`; `.github/workflows/nightly-gpu.yml` (input `ref_release`); `scripts/cuopt/README.md` |
| 21 Nov 2026 | q1 of the 21 Nov check-in (review of the M1.3 close-out): "q1 yes". Change 73 of the stochastic plan (the SOW tags, a pure restructuring checked by layer 2) is built in parallel with changes 71 and 72, in a second tab and its own worktree; change 74 starts once 72 and 73 are both merged. A departure from the order of the approved plan; explicit yes. | this log; `docs/m13-plan.md` (Plan: the stochastic extension) |
| 21 Nov 2026 | q2 of the 21 Nov check-in: "q2 yes". The preprocessing timings against GAMS (`scripts/m13_timing.jl`, `docs/timings.md`, last of 13 Nov 2026) are rerun on the final stack after change 76 merges, as evidence for the M1.3 gate (on James's workstation, within the run limits). | this log; `docs/m13-plan.md` (Gate) |
| 21 Nov 2026 | "close #183 and delete the merge": #183 (rename the package, module and repository to OpenTIMES, opened 20 Nov 2026) is closed unmerged. The decision of 18 Nov 2026 stands: no rename and no General-registry registration until the December 2026 ETSAP ExCo in Paris has chosen the name; the rename is then redone in one PR. | this log; #183 (closed) |
| 21 Nov 2026 | #176 (merged 21 Nov 2026): "pr#176 q2 dp46 - yes log this discrepancy" and "yes, build in the other changes from pr#176". D46 (timslice.mod L121, division by zero with different timeslice trees and ramping or start-up data) is reported to ETSAP with the other reports (#176 d2, rule-level, explicit yes); the twelve demo12_tsoff_* cases (d1) and the prepret.dsc L75 fix (d3) are confirmed. | this log (#176); `docs/discrepancies.md` (D46) |
| 21 Nov 2026 | q2 of the 21 Nov evening chat: "lets keep both the github gpu runner and local gpu test." Both cuOpt lanes stay: the GitHub GPU nightly (`nightly-gpu.yml`, larger runner `gpu-t4`) and the local WSL2 nightly (until 8 Dec 2026). The GitHub nightly had never run (11-20 Nov: every job cancelled after 24 hours in the queue): the runner is in the org's Default runner group, which does not allow public repositories, and the org's Actions budget is $0 with usage stopped, while larger runners are always billed. Fixed the same evening, at James's choice: runner group `gpu` (TIMESjl only, workflow `nightly-gpu.yml` on main only, public repositories allowed) holds `gpu-t4`, and the org's Actions budget is $100 a month (usage stops there; alert to James). The queued nightly of 21 Nov started on `gpu-t4` at 21:20. | this log; `.github/workflows/nightly-gpu.yml`; `scripts/cuopt/README.md` |
| 21 Nov 2026 | #184 d1 and d4: "#184 d1 as built, d4 leave history", and #184 d5: "keep all gams timings only on the local dashboard". Every GAMS timing, whatever the solver, leaves the public board (slide 10 with them) and is shown on the local board only. Rule-level (what the public repository shows); James's explicit instruction. Whether other public files with GAMS timings follow is #184 d6 (Open decisions). | #184; `scripts/run_timing.jl`; `docs/dashboard/README.md` |
| 20 Nov 2026 | q1 (solver option files): "q1 yes". `run_model` and `scripts/run_dd.jl` read the solver option file, as GAMS TIMES reads `<solver>.opt` (solve.mod L14-15): `highs.opt` from the run file's folder by default, another file with `optfile=` (`--optfile`), none with `optfile=false` (`--no-optfile`); HiGHS option names, the run's thread limit kept. A departure from the M1.5 plan, which had listed the option file as not reproduced (#130 d3). | #182; `src/solver_options.jl`; README (Tips) |
| 20 Nov 2026 | #182 d6: "can we move the cplex timings out of the public dashboard and only show it in the local dashboard?" The public board's run timings (slides 11 and 12) leave out every run with CPLEX (the GAMS EULA's Restricted Solvers); the local board shows them. | #184; `scripts/run_timing.jl`; `docs/dashboard/README.md` |
| 20 Nov 2026 | #182 d5: "d5 (c) HiGHS only for now". Option files are read for HiGHS only; no CPLEX.jl and no GAMS.jl route is built. Asked because q2 (CPLEX.jl) could not be built: the CPLEX in GAMS is licensed for use within GAMS only (GAMS EULA, Exhibit A). | #182; `src/solver_options.jl` |
| 20 Nov 2026 | q2 (CPLEX.jl as an optional solver, so `cplex.opt` files apply directly): "q2 yes". Not built: the only CPLEX on the workstation is the one in GAMS 54 (`C:\GAMS\54\cplex2220.dll`), and the GAMS EULA licenses GAMS/CPLEX "for use within GAMS/Base" only (Exhibit A; `C:\GAMS\54\EULA.md` L491). Asked again with the ways forward as #182 d5; James chose HiGHS only for now (above). | this log; #182 d5 |
| 20 Nov 2026 | #179 d1, d2 and d3: "d1 yes, d2 yes, d3 yes". The crafted cases and fixtures of elastic demand, harness 0.3.6 (`work_files`), and known difference K4 (the base prices as Arrow folders; no record for a zero marginal where GAMS writes EPS). K4 is rule-level (a known difference); explicit yes. | this log (#179); `docs/known-differences.md` (K4) |
| 20 Nov 2026 | #178 d1 (q2 of 19 Nov): "q2-stochastics, yes plan approved". The plan for the stochastic extension (`docs/m13-plan.md`, "Plan: the stochastic extension"; changes 70 to 76, one pull request each, eight crafted demo12 cases) is approved, and its changes start in its order. Rule-level (a plan for major work); explicit yes. | this log (#178); `docs/m13-plan.md` |
| 19 Nov 2026 | q1 of the 19 Nov check-in: "id go with option b, reading the base prices from the arrow database." Elastic demand (%TIMESED%) reads the base prices of the earlier run from TIMES.jl's own Arrow file, not from a GDX file (readbprice.mod `$GDXIN`/`$LOAD`); TIMES.jl writes that file after a solve, as wrtbprice.mod writes `com_bprice.gdx`. For the checks against GAMS the reference harness converts GAMS's `com_bprice.gdx` to Arrow. No GDX reader is added; one can follow if users need it. The case design is #165 d3. | this log; `docs/m13-plan.md` (gate audit, change 69) |
| 19 Nov 2026 | q2 of the 19 Nov check-in: "yes show me the plan". The plan for the stochastic extension is in `docs/m13-plan.md` ("Plan: the stochastic extension"); nothing of it starts until James approves it (Open decisions). | this log; `docs/m13-plan.md` |
| 19 Nov 2026 | "yes, leave IREAUXBAL refused": %IREAUXBAL% set by the run without %POWERFLO% (cal_ire.mod L30) leaves the M1.3 gate. GAMS pastes the run's own text into the balance there, so there is no GAMS code to translate (#149 d1); TIMES.jl keeps refusing it with its message (eqcombal.jl, eqpeak.jl). Narrows q1 of 18 Nov 2026. Rule-level (the milestone scope); explicit yes. | this log; `docs/m13-plan.md` (Gate, and Gate audit, 18 Nov 2026) |
| 18 Nov 2026 | q1 of the M1.3 gate audit: yes, as recommended. Still refused linear features count for the M1.3 gate: shaped availability (NCAP_AFM, NCAP_AFX, NCAP_AFSM, NCAP_AFSX; coef_cpt.mod L42-58, pp_shapr.mod L19-40); the rest of dynamic timeslices (the re-interpolation of dynslite.vda L94-102, and the RTS(S) rows of the storage, dispatching, EQ(l)_ASHAR, EQL_CAPFLO, unit commitment, residual load curve and power-flow families); GR_DEMFR as input data (powerflo.vda L107, L131); %IREAUXBAL% set by the run without %POWERFLO% (cal_ire.mod L30). Moved to M1.5 as run options: %OBJANN% YES (eqobjann.tm), %VALIDATE% YES, %VINTOPT% 1 (fillvint.gms), %WAVER% YES (fillwave.gms), %INTEXT_ONLY% YES and %PREP_ANS% YES. Elastic demand (%TIMESED%, its linear form) and the stochastic extension stay in the gate. Rule-level (the milestone scope); explicit yes. | this log; `docs/m13-plan.md` (Gate, and Gate audit, 18 Nov 2026); `docs/m15-plan.md`; `docs/translation-guide.md` (Decisions) |
| 18 Nov 2026 | q2 of the M1.3 gate audit: move both to M1.5: user constraints with VAR_UC not YES (eqmain.mod L204-207, L229-232; equcwrap.mod L13), and the VDA trade bounds and prices from an earlier run (bnd_ire.vda, equ_ext.vda L67; GDX_IREBND and GDX_IPRIC, init_ext.vda L137-151). The M1.3 gate closes without them; they stay refused with their message until M1.5. Answers the VAR_UC question of 17 Nov 2026 and #150 decision 3. Rule-level (the milestone scope); explicit yes. | this log; `docs/m13-plan.md` (Gate); `docs/m15-plan.md` |
| 17 Nov 2026 | q8: James is in Athens until Saturday 21 Nov 2026. Until then the check-ins are at 07:00 and 20:00 Athens time (05:00 and 18:00 on the workstation, GMT), and both dashboards are refreshed before 07:00 Athens. The nightly loop runs without an end time, so its start needs no change. From Sunday 22 Nov the check-ins are again at 9:00 and 16:30. | this log; the workstation's notes |
| 17 Nov 2026 | q7: "lets stay on times v4.9.7 until the planned update to newer TIMES." No v4.9.8 reference batch before the plan's move (#109 d3: after every remaining feature is translated and tested; then the whole baseline moves at the M1.3 gate); the nightlies stay on v4.9.7. | this log; CLAUDE.md (Baseline) unchanged |
| 17 Nov 2026 | q6: "bring all work back to local workstation." Every remaining M1.3 change, and its GAMS layer 2-3 run, is made in the Claude Code session on James's workstation; the cloud session that opened #143 to #147 takes no more translation work. | this log; the workstation's notes |
| 18 Nov 2026 | "sure, do step 1": the run from a run file and DD files becomes a function of the package, `run_model`, so TIMES.jl can be added with `Pkg.add(url=...)` and used without cloning the repository (step 1 of the ways to make TIMES.jl easy to use on any platform, asked in the chat after #166). The later steps (precompiling a demo12 run, registration after the Dec 2026 ExCo, standalone apps at M1.7) are not decided. | `src/run.jl`; README (Quick start); #167 |
| 18 Nov 2026 | ETSAP-TIAM stays out of the nightly probes and the TIMES.jl reference harness. It confirms the rule in `CLAUDE.md` (Test-model licences: TIAM is removed and is not re-added without a stated open licence); the rule is unchanged. | this log; `CLAUDE.md`; `docs/test-models.md` |
| 18 Nov 2026 | ETSAP-TIAM is not used in the 23 Nov 2026 webinar demo. It confirms the same rule; the rule is unchanged. | this log |
| 17 Nov 2026 | q5 (asked 16 Nov 2026): yes. The M1.3 gate covers the linear features only. The mixed-integer and nonlinear features move after the gate, as the discrete unit commitment did (#120 d5): the lumpy investments and block retirements of the DSC options (`NCAP_SEMI`, `PRC_DSCNCAP`), the discrete unit commitment (`DUC` YES), TIMES-Micro (`RD_NLP`, `MICRO` YES) and, added by Claude and agreed by James, ETL (`mod_vars.etl` L18 declares binary variables, so an ETL run is a MIP). They stay refused with a message until then. Rule-level (the milestone scope); explicit yes. | `docs/translation-guide.md` (Decisions); `docs/m13-plan.md` (Gate); `docs/demo12-variants.md`; this log |
| 17 Nov 2026 | MACRO (with MSA) is checked with IPOPT on both sides (GAMS/IPOPT and TIMES.jl with Ipopt.jl) while CONOPT is not in the workstation's GAMS licence: layers 1 and 2 as for every change, layer 3 at 1e-6 with IPOPT. It is translated after the M1.3 gate, not before it. Rule-level (the reference solver; the milestone scope); explicit yes. | `docs/translation-guide.md` (Decisions); this log |
| 17 Nov 2026 | The speed target "model generation no worse than 5x GAMS, warm" moves from M1.7 to Phase 2 (asked 3 Nov 2026). Phase 1 keeps timing each stage against GAMS and logging it (definition of done); M1.7's baseline benchmarks record where TIMES.jl stands, with no target to meet. LP-identical speed-ups of shared code stay allowed in Phase 1 (#35, #54). Rule-level (the plan); explicit yes. | `docs/translation-guide.md` (Decisions); `docs/timings.md`; `docs/phase2-notes.md` (P2-6); issue #116 |
| 15 Nov 2026 | Extensions translated before the M1.3 gate: the stochastic extension, ETL, MACRO with MSA, and damage costs, the smaller ones first; all other extensions (ECB, CLI, ABS, IER, MLF, MCA, ...) after M1.7. Rule-level (the extension scope of 17 Oct 2026; the plan); explicit yes. The core features still refused (the marketplace of eqire.mod, elastic demand, TS_OFF, ...) stay in the order of 14 Nov 2026. | `docs/translation-guide.md` (Decisions); `docs/demo12-variants.md`; this log |
| 15 Nov 2026 | MACRO is skipped while CONOPT is not in the workstation's GAMS licence (probed 15 Nov 2026: not included; IPOPT is). Whether to check it with IPOPT instead is on the Open decisions list. | this log (Open decisions) |
| 15 Nov 2026 | In the chat, decisions are "d" (always with their pull request: "#123 d4") and discrepancies "dp" ("dp44" is D44 in docs/discrepancies.md); questions in a check-in message are q1, q2, ...; no prefix stands for two things. | this log; the repository's IDs are on the Open decisions list |
| 14 Nov 2026 | "pr#125 - 6 - make the GAMS icons Orange and the TIMES.jl icons green (ESMA HEx Green). Make HiGHS icon an isoceles triangle pointing up, -8 yes, build in a wall timer [...] -9 yes, update after each nightly and refresh before our 9am check in. -10 yes solve OTCGEN and OTNYC with Highs. Omit OTUS9r for now." | #125 (decisions 6, 8, 9, 10); built in a follow-up pull request to #125 |
| 14 Nov 2026 | "pr#121 -2 yes, it is built in": the refusal of blending data (#42, 5 Nov 2026) is reversed; blending is translated and checked on the crafted case demo12_blnd. | #121 (decision 2), #42 |
| 14 Nov 2026 | "pr#120 ok to leave discrete unit commitment until after M1.3": the discrete unit commitment (`$SET DUC YES`, a MIP) stays refused while the M1.3 gate closes, and is taken up after it. | #120 (decision 5), #124 (decision 5); `docs/m13-plan.md` |
| 14 Nov 2026 | The dashboards compare run times on a chart with seconds on a log scale against the number of variables, also on a log scale. Slide 10 stays; a timing slide is added that breaks each run's time into its parts, per model and scenario, solver and language. | #125 (`docs/dashboard/`, `scripts/run_timing.jl`) |
| 14 Nov 2026 | Review the Open decisions list against every pull request and move the resolved ones into the log of their pull request. | this log (Open decisions, and #68, #104, #108, #109, #118, #119) |
| 14 Nov 2026 | The M1.3 gate is not passed yet: keep going until every remaining refused feature is translated, and report back the same day. Rule-level (a milestone gate); James's answer to #109. | Open decisions; `docs/m13-plan.md`, change 36 |
| 14 Nov 2026 | The refused features are translated in the order given at the 16:30 check-in (unit commitment, the stepped solve, MACRO, the extensions, then the remaining equation families). A feature with no model to verify it is flagged and listed; a demo12 variant is made where one can be, otherwise the feature is noted as a TODO for a later release. | `docs/m13-plan.md` as each lands; this log |
| 14 Nov 2026 | The unit commitment is translated before the M1.4 gate's CI criterion ("CI runs the chain from DD files on the crafted cases") counts as met. | #118, decision 2; #120 and #124 |
| 14 Nov 2026 | v4.9.8: the GAMS reference batch may be started into a separate folder after all remaining features are translated and tested (the nightly runs and probes move to v4.9.8 with it). Rule-level; explicit yes. | #109, decision 3; the batch script on James's machine |
| 14 Nov 2026 | The myopic (stepped) run tests may start before the M1.3 and M1.4 gates close. Rule-level (milestone order); explicit yes. | #108, decision 3; the stepped-solve PR |
| 14 Nov 2026 | M1.3 gate, preprocessing timed against GAMS: the 13 Nov timings on the five core models (the ratios, to CPLEX runs, in `esma-ie/timesjl-unpublished`; #184 d6) are close enough to pass the gate. | `docs/timings.md` (the M1.3 gate PR); this log |
| 14 Nov 2026 | The M1.3 gate PR is reviewed the same morning; the HiGHS solve of TIMES-NZ joins the batch's DD-file stage. | the M1.3 gate PR; batch script on James's machine |
| 14 Nov 2026 | The features TIMES.jl still refuses: push on them now, one PR each, each with an open crafted demo12 case and a GAMS reference. | this log; `docs/m13-plan.md` as each lands |
| 14 Nov 2026 | Failures seen only on local runs are fixed without waiting: each defect is reproduced with an open crafted case first, and only that case enters the repository. | this log |
| 14 Nov 2026 | Workstation batch: the rewrite as a job queue is a go; checks run as rolling passes from 18:00 to 09:00, and continuously while work remains, instead of one nightly at 23:05; "solve once" (the parity report reuses the DD stage's solves) and "one chain" (the DD chain replaces the input-dump chain once the gates close) are agreed. | batch script on James's machine; a PR for `scripts/parity_report.jl` to follow |
| 13 Nov 2026 | cuOpt local nightly: OTUS9r is dropped from its reference runs for now (OTNYC and OTCGEN stay). | `~/.config/timesjl/cuopt-nightly.conf` in WSL2 (REF_MODELS); this log |
| 13 Nov 2026 | #90: the cuOpt nightly also solves the open reference runs OTNYC, OTCGEN and OTUS9r (reduce_off), besides the CI fixtures; a test run the same morning, then the local board updated. Rule-level for the cuOpt lane (informational; still never a merge gate); explicit yes. | `~/.config/timesjl/cuopt-nightly.conf` in WSL2 (REF_MODELS); this log |
| 13 Nov 2026 | M1.3 order: 27b-2 (the grid allocation rows), then the #68 trade case, then the gate PRs for M1.3 and M1.4 ("ok, go" to each). | this log; #103, the #68 PR |
| 12 Nov 2026 | #68: keep the demo12 trade test case and get it working soon (before the M1.3 gate). | crafted case demo12_mrkx (the #68 PR) |
| 12 Nov 2026 | Start the solution export of #97 (levels and marginals in Arrow format v1; no report translation) now, before M1.6 opens, as an experiment: results from TIMES.jl in a downstream results view for the 23 Nov webinar, reviewed on 20 Nov. Rule-level (departs from the milestone order); explicit yes. M1.3 and M1.4 keep priority for the gates. | #97; this log |
| 12 Nov 2026 | M1.6 reporting, order of outputs: results for downstream tools first, in Arrow format v1 (#97): the solution (levels and marginals), then the translated report parameters, as the default output of every solve; Veda `.vd` files second. The M1.6 gate is unchanged (report parameters and `.vd` against GAMS at 1e-6). Rule-level (a change to the plan); explicit yes. | `docs/translation-guide.md` (M1.6) when the M1.6 plan is written |
| 12 Nov 2026 | MPS run files for each open model in its own repository: the GAMS `CONVERT` LP of each scenario, "as run" only, named `<model>+<scenario>+as_run` (`.mps.gz` and `.dict.txt.gz`), described in `mpsrunfiles/README.md` and attached to a release per TIMES version (`mps-times-v4.9.7`), not Git LFS (esma-ie's LFS quota is in use elsewhere and blocked; release assets have no quota). OTUS9r, OTCGEN, OTNYC and an esma-ie fork of TIMES_Demo; not TIMES-NZ (not ESMA's to share). | esma-ie/OTUS9r#1, OTCGEN#1, OTNYC#1, TIMES_Demo#1 (draft releases for James to publish) |
| 12 Nov 2026 | GAMSPy (TIMES-2-GAMSPy) comparison: on the webinar list only, not in the core probes. | `_handoff` (local) |
| 12 Nov 2026 | cuOpt results stay on the local dashboard for now and go onto the public dashboard on 23 Nov (#102 decision 1: no to the public slide until then). | #102 (slide removed; kept in commit 920b00b) |
| 12 Nov 2026 | The M1.3 chain slide shows the open scenarios only; the crafted demo12 cases' last pass (9 Nov) stays in its note (#102 decision 2): yes. | #102 |
| 11 Nov 2026 | The decision-log rule (#96 decision 1): yes. | `CLAUDE.md` (#96) |
| 11 Nov 2026 | The four rule-level questions approved only by merge (#96 decision 2): yes to all four. #35 and #54: changes to internal code or data structures are allowed in Phase 1 when the generated LP stays identical (layer 2 at 1e-9, same rows, columns and order). #61: one-way cross-evaluation counts as OTUS9r's layer 3 at the M1.3 gate. #91: K2 approved. The other open decisions are to be reviewed with James. | `CLAUDE.md` (#96); `docs/known-differences.md` K2 |
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

### #197 cuOpt lane: no GPU runner test until it passes locally; issue #100 to the 9:00 check-in (open)

No new decisions: it records James's two answers of 22 Nov 2026 (above, Decisions in the chat). The open question of the same day (whether the pause includes the scheduled nightly) was answered on 25 Nov 2026: "keep the nightly on".

### #195 Timings: only CPLEX's off the public repository; GAMS/HiGHS back on the board (#184 d6) (merged 23 Nov 2026)

Asked for by James on 22 Nov 2026, answering #184 d6: "only move CPLEX timings out of the public repo & dashboard and into the local dashboard and a private repo", "The GAMS data that does not relate to proprietry solvers, like cplex, can stay, such as GAMS-HiGHS runs", and "use esma-ie/timesjl-unpublished".

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | GAMS/HiGHS timings return to the public board (demo12 and TIMES-NZ steady, both variants), and GAMS's times from runs that use no Restricted Solver stay in the public files: the cloud section of the coefficient stage in `docs/timings.md` (pre-solve runs, no solve), P2-2's 0.79 s (the same run) and the GAMS replay in `docs/m13-plan.md` (13b; no solve). Rule-level. | Asked for by James. Built in. | James, 22 Nov 2026 (#184 d6, in the chat) |
| 2 | Every GAMS figure taken from a run with CPLEX leaves the public files, the parts before the solve included (preprocessing, coefficients, generation: they involve no CPLEX, but come from its run), with TIMES.jl's ratios to them; as #184 d1. They return if GAMS answers that they may be published, or once they are measured in runs without a Restricted Solver. | Recommended: yes. Built in. | open |
| 3 | Slide 10 (the coefficient stage against GAMS) stays on the local board only: its GAMS times come from CPLEX runs. | Recommended: yes. Built in. | open |
| 4 | `docs/phase2-notes.md` P2-6 quoted a model-generation ratio measured on TIM (21 Oct 2026): a figure derived from TIM, which CLAUDE.md keeps out of this repository, and from a CPLEX run. It is removed; it stays in the git history (as #184 d4). | Recommended: yes. Built in. | open |
| 5 | Issue #116 shows GAMS/CPLEX timings in its title and body. (a) Edit them out (GitHub keeps the edit history visible), or (b) leave the issue as it is? Not searched: the bodies of other issues and pull requests. | none built; recommended: (a) | open (Open decisions) |
| 6 | Keep `esma-ie/timesjl-unpublished` current from the nightly (the local script commits `run-timing-unpublished.json` to its clone)? Today it holds a snapshot of 22 Nov 2026. | none built; recommended: yes | open (Open decisions) |
| 7 | CLAUDE.md (Repository) gains the rule: no timing of CPLEX or another Restricted Solver, nor a figure taken from such a run, in the public repository; they go to the local board and `esma-ie/timesjl-unpublished`. Rule-level. | Built in, from James's instruction of 22 Nov 2026. | open |

### #192 M1.3 gate: the stochastic extension out of the gate; gate audit of 22 Nov 2026 (merged 25 Nov 2026)

| # | Decision | Default | Outcome |
| --- | --- | --- | --- |
| 1 | Damage costs as elastic supply curves from a base run (DAM_ELAST 'N'; wrtbprice.mod L21-25, readbprice.mod L24-25 and L37-45): translate before the gate (change 69b) or move out with the stochastic extension? Rule-level. | Recommended: move them out. Not built in. | James, 22 Nov 2026: "move them out of the gate and list them for completion before phase 1 close". Rule-level; explicit yes. Out of the M1.3 gate, refused with their message until then; listed in docs/m13-plan.md ("After the gate, before Phase 1 closes") and docs/translation-guide.md. Confirmed 23 Nov 2026: "#192 d1 yes, move it out". |
| 2 | Changes 71-76 resume after the move to v4.9.8; change 73 finishes and merges first | Recommended: yes. Not built in. | James, 22 Nov 2026: "yes, after move to v4.9.8". docs/m13-plan.md ("Plan: the stochastic extension"). |
| 3 | The timing rerun of q2 (21 Nov 2026) moves to now, on the merged stack, figures on the local board only (#184 d5) | Recommended: yes. Built in. | accepted by merge, 25 Nov 2026 |

### #191 cuOpt lane: download the reference runs with curl (the GPU image has no gh) (merged 22 Nov 2026)

No decisions: a fix to #189, whose first run (22 Nov 2026, run 45015140242) stopped in every job at the download (`gh: command not found`).

### #189 cuOpt lane: the open reference runs on the GitHub GPU runner, from a release (merged 22 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Each solve on the runner is capped at 1800 s (input `time_limit`), and at most 3 model jobs run at once (each on its own runner, so timings do not share a GPU). | Recommended: yes. Built in. | accepted by merge, 22 Nov 2026 |
| 2 | Keep the pre-release `cuopt-ref-2026-11-22` and its assets until the cuOpt review of 8 Dec 2026, then decide whether to keep refreshing it. | Recommended: yes. Built in (nothing deletes it). | accepted by merge, 22 Nov 2026 |

### #185 M1.3 (70): the stochastic extension's DD reader (initmty.stc); eight crafted cases (merged 22 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the eight crafted cases of the stochastic plan (demo12_stc, demo12_stc3, demo12_stcmx, demo12_stclam, demo12_stcext, demo12_spines, demo12_sensis, demo12_tradeoff; demo12 with DD files of their own or of earlier crafted cases, CC BY 4.0), each with an input and a run fixture (about 1.2 MB each, 10 MB together); their model fixtures come with changes 71-76. demo12_tradeoff follows Example 1c of the TIMES stochastics user note (Example 1b drove the CO2 to zero in phase 1, so its three points were one solve). | Recommended: yes. Built in. | accepted by merge, 22 Nov 2026 |
| 2 | Harness 0.3.7: in the pre-solve run of a SENSIS run only, `$ONIMPLICITASSIGN` before maindrv.mod. Without it GAMS stops on error 141 (solve.stc L7 compiles the report writer, whose solution levels nothing assigns when there is no SOLVE) before any checkpoint. It turns off that check and nothing else; the solve runs are unchanged. | Recommended: yes. Built in. | accepted by merge, 22 Nov 2026 |
| 3 | A run with SPINES or SENSIS YES is refused at init_ext (maindrv.mod L33-36), as one with STAGES YES is, until changes 71-76 translate them; until now the compile refused all three at initmty.stc. | Recommended: yes. Built in. | accepted by merge, 22 Nov 2026 |

### #184 Dashboard: GAMS timings on the local board only (merged 22 Nov 2026)

Asked for by James on 20 Nov 2026, in answer to #182 d6: "can we move the cplex timings out of the public dashboard and only show it in the local dashboard?"; widened on 21 Nov 2026: "keep all gams timings only on the local dashboard" (d5).

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Every timing entry of a run with CPLEX leaves the public board, GAMS's parts before the solve included (they involve no CPLEX): OTCGEN, OTNYC and OTUS9r show no GAMS time there until they have GAMS/HiGHS reference runs. The alternative keeps GAMS's times up to the LP from the CPLEX runs. | Recommended: as built. Built in. Since d5 every GAMS entry leaves, so the question no longer arises. | answered by James, 21 Nov 2026: as built ("#184 d1 as built") |
| 2 | All of the EULA's Restricted Solvers are left out (COPT, CPLEX, Gurobi, KNITRO, LINDO/LindoGlobal, Xpress; ODHCPLEX), not CPLEX alone, for TIMES.jl's entries too (today HiGHS only, #182 d5). | Recommended: yes. Built in. | accepted by merge, 22 Nov 2026 |
| 3 | The public run-time slides say "GAMS's run times are not published on this board" (before d5: "runs with CPLEX: times not published (GAMS EULA, Publication of Benchmarks)"). | Recommended: yes. Built in. | accepted by merge, 22 Nov 2026 |
| 4 | Flag: git history keeps the earlier GAMS and CPLEX timings (older versions of `docs/dashboard/index.html`); removing them would rewrite the public repository's history. | Recommended: leave the history as it is. Nothing built. | answered by James, 21 Nov 2026: leave the history ("d4 leave history") |
| 5 | Every GAMS timing leaves the public board, whatever the solver: GAMS/HiGHS too (demo12 and TIMES-NZ steady), and slide 10 (the coefficient stage against GAMS), which the public page drops; its slides 11 and 12 become 10 and 11. The local board shows them all: `run_timing.jl --unpublished` (block `run-timing-unpublished`) and a `timing-coef` block for slide 10, both added by `build_dashboard_local.ps1`. Rule-level (what the public repository shows). | Asked for by James. Built in. | answered by James, 21 Nov 2026: "keep all gams timings only on the local dashboard"; reversed by James, 22 Nov 2026, with d6: only CPLEX's (and the other Restricted Solvers') timings stay off the public board (#195) |
| 6 | Other public files hold GAMS timings: `docs/timings.md` (GAMS's seconds and TIMES.jl's ratio to them), and ratios to GAMS in `docs/translation-guide.md` and `docs/m13-plan.md`. Do they move off the public repository too (to a local file, in their own PR), with the 5x speed target (P2-6) then reported without GAMS's figures? Rule-level. | none built; recommended: yes, one follow-up PR | answered by James, 22 Nov 2026: only the CPLEX timings move, to the local board and the private repository `esma-ie/timesjl-unpublished`; GAMS's other timings (GAMS/HiGHS) stay public (#195) |

### #182 run_model: the solver option file (highs.opt), as GAMS reads <solver>.opt (merged 21 Nov 2026)

Asked for by James on 20 Nov 2026 (q1 and q2 of that day, above).

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Option files are read for HiGHS only. Another solver's file in the run folder (VEDA's `cplex.opt`) is not read and its settings are not turned into HiGHS options; the run prints a note naming it. | Recommended: yes. Built in. | accepted by merge, 21 Nov 2026 |
| 2 | A line HiGHS does not take (an unknown name, a wrong type, a value out of range) is left out with a note and the solve goes on, as GAMS's solvers do (GAMS 54 documentation, "The Solver Option File"); the run is not stopped. | Recommended: yes. Built in. | accepted by merge, 21 Nov 2026 |
| 3 | The run's thread limit (`threads`, `TIMESJL_THREADS`, 12 by default) stays: a file may ask for fewer threads, and a file asking for more, or for HiGHS's own choice (`threads 0`), gets the limit. | Recommended: yes. Built in. | accepted by merge, 21 Nov 2026 |
| 4 | `highs.opt` is looked for in the run file's folder (GAMS's working folder), not in the `dd` folders. | Recommended: yes. Built in. | accepted by merge, 21 Nov 2026 |
| 5 | CPLEX (q2 of 20 Nov): which way, given the GAMS licence? (a) an IBM CPLEX licence and CPLEX.jl; (b) GAMS.jl, CPLEX within GAMS; (c) HiGHS only for now. | (c) HiGHS only for now | James, 20 Nov 2026 |
| 6 | The benchmark clause of the GAMS EULA and the CPLEX times in the public repository. Rule-level. | CPLEX timings off the public dashboard, on the local dashboard only (#184) | James, 20 Nov 2026 |

### #179 M1.3 (69): elastic demand, the linear form (%TIMESED%); crafted cases demo12_edbase, demo12_ed, demo12_edagg (merged 21 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the crafted cases demo12_edbase, demo12_ed and demo12_edagg (demo12 with the base prices of demo12_edbase as a GDX file and its Arrow form, CC BY 4.0), with public CI fixtures of demo12_ed and demo12_edagg, the run fixtures included (about 7 MB each). | Recommended: yes. Built in. | answered by James, 20 Nov 2026: yes ("d1 yes") |
| 2 | Known difference K4: TIMES.jl reads and writes the base prices as Arrow folders, not GDX files (q1, option b), looking for them in the run file's folder and along the include path; a zero marginal is written as no record where GAMS writes EPS. Rule-level (a known difference). | Recommended: yes. Built in; needs your explicit yes. | answered by James, 20 Nov 2026: yes ("d2 yes"; the explicit yes for K4); confirmed 21 Nov 2026: "pr#179 d2 yes" |
| 3 | Harness 0.3.6: `work_files`, files the harness copies into GAMS's work folder before each run (here the base prices). | Recommended: yes. Built in. | answered by James, 20 Nov 2026: yes ("d3 yes"); confirmed 21 Nov 2026: "d3 yes" |

### #181 run_model: reset HiGHS's thread scheduler around its solve (merged 21 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | `run_model` (src/run.jl) calls `Highs_resetGlobalScheduler(1)` before and after its HiGHS solve (HiGHS.jl README, Threads). Without it, a later HiGHS solve in the same process that asks for more threads than `run_model`'s 12 stops with OTHER_ERROR; on the workstation (48 CPUs, HiGHS's default 24 threads) the full test suite failed in every solve after `test_run_model.jl` (#167) since 18 Nov 2026, while GitHub's runners have too few CPUs to show it. Run code, not translated GAMS code; the LP is unchanged. | Recommended: yes. Built in. | accepted by merge, 21 Nov 2026 |

### #178 Plan for the stochastic extension; q1 and q2 of 19 Nov 2026 (merged 21 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Approve the plan for the stochastic extension (changes 70 to 76, eight crafted cases, about four to five working days). | Approved. | answered by James, 20 Nov 2026: "q2-stochastics, yes plan approved"; confirmed 21 Nov 2026: "pr#178 d=yes" |

### #177 M1.3 (68): dynamic timeslices, the re-interpolation of dynslite.vda POSTLEV; crafted case demo12_tsoff_rint (merged 21 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the crafted case demo12_tsoff_rint (demo12_tsoff + rint.dd, CC BY 4.0) with its public CI fixtures, the run fixture included so that CI runs it from the DD files (about 7 MB). | Recommended: yes. Built in. | accepted by merge, 21 Nov 2026 |

### #175 M1.3 (66): shaped availability, NCAP_AFX/AFM/AFSX/AFSM (coef_cpt.mod L42-58, pp_shapr.mod L19-40); crafted case demo12_afshp (merged 20 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the crafted case demo12_afshp (demo12 + afshp.dd, CC BY 4.0) with one public CI fixture (as run, about 8.5 MB with the coefficient files, so that CI runs the new code). | Recommended: yes. Built in. | accepted by merge, 20 Nov 2026 |

### #174 M1.3 (65): total demand fractions given as data, GR_DEMFR (powerflo.vda L40, L107, L131); crafted case demo12_pfdf (merged 20 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the crafted case demo12_pfdf (demo12 + pf.dd and pfdf.dd, CC BY 4.0) with one public CI fixture (as run, about 4 MB). | Recommended: yes. Built in. | accepted by merge, 20 Nov 2026 |

### #176 M1.3 (67): dynamic timeslices, the RTS(S) rows of the other families; twelve crafted cases demo12_tsoff_* (merged 21 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the twelve crafted cases demo12_tsoff_* and tsoff2.dd (run files only, CC BY 4.0), with three public CI fixtures (demo12_tsoff_disp, _ptdf, _gg2; as run, about 13 MB together); the other nine are checked by the gate from their DD files. | Recommended: yes. Built in. | James, 21 Nov 2026: yes ("yes, build in the other changes from pr#176"); merged 21 Nov 2026 |
| 2 | D46 (timslice.mod L121 divides by zero when the regions have different timeslice trees and there is ramping or start-up data): report it to ETSAP, with the other notes? Rule-level (a report to ETSAP). | yes, with the other reports | James, 21 Nov 2026: yes ("pr#176 q2 dp46 - yes log this discrepancy"); D46 goes to ETSAP with the other reports |
| 3 | prepret.dsc L75 keeps an EPS upper bound EPS (MIN of the VAR_RCAP and VAR_SCAP bounds); only visible under HOLDFIXED. Fixed in this change rather than in its own PR, as the case that shows it is this change's. | Recommended: yes. Built in. | James, 21 Nov 2026: yes ("yes, build in the other changes from pr#176"); merged 21 Nov 2026 |

### #173 m13_gate.jl: 24 hours for every HiGHS solve (merged 19 Nov 2026)

Asked for by James on 19 Nov 2026 ("allow TIMES-NZ runs on HiGHS 24 hours run time", corrected the same hour to "allow all HiGHS runs 24 hours runtime").

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | The layer-3 HiGHS solve of `scripts/m13_gate.jl` (the nightly's `dd-<model>` jobs) gets 24 hours on every model (`HIGHS_TIME_LIMIT = 86400`), up from one hour. | Recommended: yes. Built in. | accepted by merge, 19 Nov 2026 |
| 2 | A nightly pass can now run much longer: the TIMES-NZ shift job solves two variants, up to 48 hours on 12 threads in the worst case, and the loop starts no new pass until every job ends. `STOP-nightly` still stops a pass. | Recommended: accept. Built in. | accepted by merge, 19 Nov 2026 |
| 3 | The GAMS reference solves keep `RESLIM=50000` (about 14 hours) from each model's own run file (model input); the CI unit tests keep 600 s; the cuOpt lane is not HiGHS. | Recommended: leave as is. Built in. | accepted by merge, 19 Nov 2026 |

### #171 README: status without the pre-MVP label; probes of the 18-19 Nov nightly (merged 19 Nov 2026)

Asked for by James on 19 Nov 2026 ("update the read.me for update probe status. remove the pre MPV status of TIMES.jl. the model now runs well from city, national, multi-regional models.").

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | The status box drops "pre-MVP", "Not ready for modelling use" and "For analysis, use TIMES in GAMS"; it keeps the facts: no release, no report parameters or VEDA files yet (M1.6), a few features refused, interfaces may change. | Recommended: yes. Built in. | accepted by merge, 19 Nov 2026 |
| 2 | OTNYC and OTCGEN (both New York City) are named as city models, TIMES-NZ as national, OTUS9r as multi-regional, with a Scale column in the probe table; JRC-EU-TIMES is named as multi-regional for preprocessing only (its matrix and optimum are not compared yet). | Recommended: yes. Built in. | accepted by merge, 19 Nov 2026 |
| 3 | JRC-EU-TIMES verdicts: 850 of 850 sets and parameters match to the end of preprocessing (cli_ll, REDUCE off and as run), QA log identical, DD files compile as GAMS in all nine scenarios; verdicts only (`redistribute = "summary"`). | Recommended: yes. Built in. | accepted by merge, 19 Nov 2026 |
| 4 | TIMES-NZ shift REDUCE off: HiGHS reaches the one-hour limit in most batches (also 18-19 Nov); the 3e-9 kept in the table is from the daytime batch of 18 Nov, explained in a note. | Nothing to answer. | logged |

### #148 M1.3 (47): the VDA betting constraints EQG_UCMAX, EQG_UCSUMAX (ucbet.vda L11-125); crafted case demo12_ucbet (merged 18 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | `$IF DEFINED UC_FLOBET` (equ_ext.vda L99, mod_ext.vda L39) is read as "UC_FLOBET has records after init_ext and prep_ext". GAMS also includes ucbet.vda for a UC_FLOBET or UC_ACTBET given with no records; then the file changes nothing that is read later (no UC_GMAX entry, so no row; UC_GMAXR emptied again by L38; only the scratch sets UNCD1 and RXX are cleared). The refusal of UC_ACTBET data at prep_ext.vda L35 goes with it. | Recommended: yes. Built in. | answered by James, 17 Nov 2026: yes |
| 2 | Keep the crafted case demo12_ucbet (demo12 + ucbet.dd, CC BY 4.0) with one public CI fixture (as run, about 4 MB). | Recommended: yes. Built in. | answered by James, 17 Nov 2026: yes |

### #149 M1.3 (48): the IN rows of EQL_SCAP, salvage limited by activity (prepret.dsc L105-107); crafted case demo12_scapin (merged 18 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | `%IREAUXBAL%` set by the run itself, not by powerflo.vda DECL (L221): GAMS pastes the run's own text into the balance at cal_ire.mod L30, so there is no GAMS code to translate. It stays refused with its message (eqcombal.jl, eqpeak.jl), as a run that supplies its own GAMS code, and leaves the list of features left before the M1.3 gate. | Recommended: yes. Built in (no code change). | accepted by merge, 18 Nov 2026 |
| 2 | Keep the crafted case demo12_scapin (demo12 + olife.dd, CC BY 4.0) with one public CI fixture (as run, about 4 MB). | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |

### #150 M1.3 (49): inter-period storage under OBJ LIN (eqstgips.lin L12-66, eqstgaux.lin L25-31); crafted case demo12_ipslin (merged 18 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the crafted case demo12_ipslin (demo12_ips under OBJ LIN, CC BY 4.0, no DD file of its own) with one public CI fixture (as run, about 4 MB). | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 2 | Translate eqstgips.lin and the IPS terms of eqstgaux.lin in one change: the second is only reached with the first (both are OBJ LIN's inter-period storage), and one crafted case checks both. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 3 | `bnd_ire.vda` (item (f) of 17 Nov 2026) is a run option: it acts only when GDX_IREBND or GDX_IPRIC load an earlier run's trade flows and prices (init_ext.vda L137-151). Move it to M1.5, out of the M1.3 gate? Rule-level (the milestone scope). | Recommended: move to M1.5. Not built in: the refusal stays either way. | James, 18 Nov 2026: moved to M1.5 (q2 of the gate audit) |

### #151 M1.3 (50): costs on the components of a commodity's balance, COM_CSTBAL (powerflo.vda L372-434); crafted cases demo12_cstbal and demo12_pfcst (merged 18 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Two new crafted cases, each with a public CI fixture (as run, about 4 MB each): demo12_cstbal (demo12 + cstbal.dd, the branches without a grid) and demo12_pfcst (demo12_pfd + pfcst.dd, the grid branches). One case cannot reach both: a commodity that is a grid node allocation is never TRACKC. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 2 | The labels the CSTBAL code names itself (PRD, IMP, EXP, GEN, NTX, NPG, FIN, FX and the empty label) are added to the label order when the dump it starts from lacks them, after every known label (G36). Their place there only orders OBJ_COMBAL's records, which every compare matches by key. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |

### #152 M1.3 (51): market-based trade (eqire.mod L23-38, eqirebnd.mod L46-51); crafted case demo12_mkt (merged 18 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | A new crafted case, demo12_mkt, with one public CI fixture (as run, about 4 MB): demo12 with a third internal region REG3, since a marketplace needs a region between two others or an exporter to two regions (ppmain.mod L865-868), which two regions cannot give. REG3 copies demo12's timeslices, year fractions and discount rate and holds only GAS. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 2 | EQ(l)_IREBND's plain export term (eqirebnd.mod L56) now tests NOT RPC_MARKET(R,P,C,'EXP'), as GAMS does; before this change no marketplace could exist, so the test changes no earlier row. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |

### #153 M1.3 (52): storage flexibility, %STSFLX% YES (eqstgtss.mod L53-93, EQ_STSLEV; coef_ext.vda L31); crafted case demo12_stsflx (merged 18 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | A new crafted case, demo12_stsflx, with one public CI fixture (as run, about 4 MB): demo12 with a general timeslice storage STSELC (PRC_MAP STS) and $SET STSFLX YES. demo12_stgccl's battery cannot serve: it is not an STS storage, so it has no RP_STL entries. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |

### #159 M1.3 (58): capacity-related flows in user constraints (UC_CAPFLO, cal_caps.mod); crafted case demo12_uccf (merged 18 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | A new crafted case, demo12_uccf (demo12 plus `capflo.dd`, `capcom.dd` and `uccf.dd`, CC BY 4.0), with one public CI fixture. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 2 | Stacked on #155 (base `m13-capcom`), as it needs the coefficients of changes 53 and 54; retargeted to `main` once #154 and #155 merge. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |

### #160 M1.3 (59): the capacity transfer of decommissioning flows (coef_shp.mod L77-94); crafted case demo12_ctrn (merged 18 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | A new crafted case, demo12_ctrn (demo12 plus `capcom.dd` and `ctrn.dd`, CC BY 4.0), with one public CI fixture. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 2 | Stacked on #155 (base `m13-capcom`), like #159; retargeted to `main` once #154 and #155 merge. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |

### #155 M1.3 (54): commodity flows over the lifetime of capacity and of early retirements (NCAP_COM, COEF_CIO, RCAP_OCAP); crafted case demo12_capcom (merged 18 Nov 2026)

Stacked on #154 (branch m13-capflo).

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | A new crafted case, demo12_capcom, with one public CI fixture (as run, about 4 MB). | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 2 | COEF_RCOM (coef_nio.mod L58) is empty in every run without the capacity transfer: it reads COEF_CPT, which coef_alt.lin L77 fills only later (coefmain.mod order), so the VAR_RCAP term of cal_cap.mod is never reached. TIMES.jl does the same. Report it to the TIMES maintainers as a possible ordering issue? | Recommended: yes, as a note to ETSAP; nothing changes here. | open (no default built in) |

### #154 M1.3 (53): commodity flows tied to investment and decommissioning (coef_nio.mod L13-71, cal_cap.mod, cal_caps.mod); crafted case demo12_capflo (merged 18 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | A new crafted case, demo12_capflo, with one public CI fixture (as run, about 4 MB). | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 2 | Capacity-related flows are split into two changes: this one (investment and decommissioning, NCAP_ICOM, NCAP_CLED, NCAP_OCOM) and a second for the flows over the lifetime (NCAP_COM, NCAP_CLAG, COEF_CIO), early retirements (RCAP_OCAP), the capacity transfer (FLO_FUNCX CAPFLO = 3) and UC_CAPFLO. Each part stays refused with its own message until then. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |

### #156 M1.3 (55): the residual load curve constraints (resloadc.vda, EQ_RL_*); crafted case demo12_rldc (merged 18 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | A new crafted case, demo12_rldc, with one public CI fixture (as run, about 4 MB). | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 2 | The DD reader (M1.4 code) changes in this M1.3 change: it reads `(SET.name)` in a record key (resloadc.vda L16) and lists the dump's labels dimension by dimension, as the harness does (G55 refined). The label lists of demo12_rldc, five other demo12 cases, OTNYC, OTCGEN, TIMES-NZ and OTUS9r stay identical to GAMS's. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 3 | 'RL_THMIN' (resloadc.vda L111, L144) is translated as GAMS spells it, a second VAR_RLD column beside 'RL-THMIN' (D45). Report it to ETSAP with the COEF_RCOM note (#155 d2)? | Recommended: yes, in the same note. | open (no default built in) |

### #157 M1.3 (56): damage costs in their linear form (eqdamage.mod); crafted case demo12_dam (merged 18 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | A new crafted case, demo12_dam, with one public CI fixture (as run, about 4 MB). | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 2 | %DAMAGE% NLP (eqdamage.mod NLPDAM, BDNLP) stays refused with a message: it is non-linear, so it goes with the features after the M1.3 gate (q5 of 17 Nov 2026), checked with IPOPT like MACRO. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |

### #162 M1.3 (62): two-way gas pipelines (gasgrids.vda); crafted case demo12_gg2 (merged 18 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | A new crafted case, demo12_gg2 (demo12 plus `gg.dd` and `gg2.dd`, CC BY 4.0), with one public CI fixture. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 2 | Stacked on #161 (base `m13-gasgrid`), which is stacked on #158. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |

### #161 M1.3 (61): the gas grids (gasgrids.vda) in the LP formulation; crafted case demo12_gg (merged 18 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | A new crafted case, demo12_gg (demo12 plus `gg.dd`, CC BY 4.0), with one public CI fixture. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 2 | Two-way gas pipelines (EQ_GG_PDIF1, EQ_GG_PDIF2, EQ_GG_STEP, the FX rows of EQ_GG_MBND) stay refused with a message until a crafted case has one; pressure points (GG_PP) and %SOLMIP% YES are MIP features, after the gate (q5 of 17 Nov 2026). | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 3 | gasgrids.vda L35 (`LOOP(GR_GRID(J,TRACKC), GG_DENS(R,C)$(...) = GG_DENS(TRACKC))`) changes nothing as written: TRACKC in the loop domain controls R and C, so each node gets its own density. It reads as meant to give nodes without a density that of their grid. Translated as written; report to ETSAP? | Recommended: translate as written; send the note with the other ETSAP notes. Built in. | accepted by merge, 18 Nov 2026 |
| 4 | Stacked on #158 (base `m13-ptdf`): both change powerflo.vda's code. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |

### #158 M1.3 (57): the PTDF formulation of powerflo.vda; crafted case demo12_ptdf (merged 18 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | A new crafted case, demo12_ptdf (demo12_pfd plus `ptdf.dd`, CC BY 4.0), with one public CI fixture. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 2 | The discrete candidate lines (GR_PTDF with %DSC% and %SOLMIP% YES: GR_DUNIT, GR_DNCAP, VAR_PTDNCAP, a MIP) stay refused with a message, with the other MIP features after the M1.3 gate (q5 of 17 Nov 2026). | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 3 | At a node of a PTDF grid, VAR_COMAUX appears only in EQ_GR_PTDFLO in v4.9.7: no GAMS statement ties it to the node's net injection. Translated as written; to be checked against the TIMES grid user note, and logged as a discrepancy or asked of ETSAP if the note says otherwise. | Recommended: translate as written; check the note. Built in. | accepted by merge, 18 Nov 2026 |

### #163 M1.3 (63): dynamic timeslice trees (dynslite.vda); crafted case demo12_tsoff (merged 18 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | A new crafted case, demo12_tsoff (demo12 plus `tsoff.dd`, CC BY 4.0), with one public CI fixture. GAMS only accepts complementary trees (timslice.mod L70-75; dynslite.vda L25-27; ppmain.mod L729 divides by a demand's annual share), so the case gives REG1 a second tree (season A) rather than turning one season off. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 2 | With timeslices turned off, the RTS(S) families the case does not reach (storage, dispatching, ASHAR, CAFLAC, unit commitment by start-up type, residual load, power-flow grids) stay refused with a message, though the change in each is the same skip as in EQ_PEAK. | Recommended: yes; extend the case when a model needs one. Built in. | accepted by merge, 18 Nov 2026 |
| 3 | The bound table now records which bounds are EPS (internal; the LP of every other model is unchanged), as GAMS's HOLDFIXED does not count a variable between 0 and EPS as fixed. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |

### #165 M1.3 (64): PRC_RCAP outside RP and interest during construction for an EPS lead time; crafted case demo12_iled (merged 18 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | A new crafted case, demo12_iled (demo12 plus `iled.dd`, CC BY 4.0), with one public CI fixture; it declares TJL_NOPRC, a process of no region, to hold a PRC_RCAP record outside RP. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 2 | Registering TIMES.jl in the Julia General registry (and renaming the repository to `<Name>.jl`) waits until after the December 2026 ETSAP ExCo in Paris, which decides the package name. | Waits for the ExCo. | James, 18 Nov 2026 |
| 3 | Elastic demand is checked with a two-run case: demo12 reference as the base run (its prices), and demo12 with an additional constraint as the variant run with elastic demand. | Yes. | James, 18 Nov 2026 |

### #168 README: the probes against GAMS, model by model (merged 18 Nov 2026)

Asked for by James on 18 Nov 2026 ("describe the status of the probes and that TIMES.jl is now capable to solve TIMES models from demo to global models"). Stacked on #167.

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | The README does not say TIMES.jl solves global models: no global model is in the test suite (none has an open licence), so no probe has run one. It says "from the demo to national and multi-region models of up to 2.5 million rows" (OTUS9r) and that no global model has been run yet. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 2 | JRC-EU-TIMES named in the README with its verdicts only (matches up to the coefficients; 3 of 850 sets and parameters differ at the end of preprocessing), as its `redistribute = "summary"` allows. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 3 | The figures are from the workstation batches of 17 and 18 Nov 2026 and are updated by hand with each README status update. | Nothing to answer. | logged |

### #167 run_model: run a TIMES model with the package alone, no clone needed (merged 18 Nov 2026)

Asked for by James on 18 Nov 2026 ("sure, do step 1"). Stacked on #166.

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | HiGHS a dependency of the package (not optional), the default solver of `run_model`. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 2 | `run_model` the package's first exported name; `PRESOLVE_STEPS` and `run_switches` not exported. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 3 | One list of the steps (`TIMES.PRESOLVE_STEPS`); the probe and the gate take their steps from it; new steps go there, with their symbols in `STEP_SYMBOLS`. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 4 | `run_model`'s return value may change before the release. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 5 | Two line references corrected in the step comments (pp_qack.mod at maindrv.mod L97, solve.mod at L113). | Nothing to answer. | logged |

### #166 README: a quick start for new users; log the 18 Nov TIAM outcomes (merged 18 Nov 2026)

Asked for by James on 18 Nov 2026.

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | The quick start runs from a clone, in the `test` environment (where HiGHS is a dependency). | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 2 | Julia 1.11 or later for the quick start; a one-line workaround for 1.10 (`[sources]` in `test/Project.toml`). | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 3 | macOS described as "should work, not tested yet". | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |
| 4 | The two TIAM outcomes of 18 Nov 2026 logged under Decisions in the chat. | Nothing to answer. | logged |

### #147 M1.3 (46): nested user constraints (equserco.mod L75-76, L98-99; pp_qack.mod L53); crafted case demo12_ucn (merged 18 Nov 2026)

Logged here because #147 does not touch this file.

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Merge only after the workstation step: the crafted case's licensed reference (CONVERT, CPLEX, HiGHS), `scripts/m13_gate.jl --from-dd --solve`, the public fixture. Layer 1 passed in the cloud with the PyPI GAMS. | Recommended: yes. Built in. | accepted by merge, 18 Nov 2026 |

### #146 M1.3 (44): the UC_ATTR attribute ONLINE (uc_cap.mod L36-43); crafted case demo12_uconl (merged 17 Nov 2026)

Logged here because #146 does not touch this file.

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Merge only after the workstation step (as #147). | Recommended: yes. Built in. | accepted by merge, 17 Nov 2026 |
| 2 | The EPS constant of uc_cap.mod L40 adds nothing in TIMES.jl: it creates no column and keeps no row (every RS row has its VAR_UCRTS with VAR_UC YES). | Recommended: yes. Built in. | accepted by merge, 17 Nov 2026 |

### #145 M1.3 (43): EQL_STGCCL, the lifetime cycle limit of a storage (eqactups.vda L121-125); crafted case demo12_stgccl (merged 17 Nov 2026)

Logged here because #145 does not touch this file.

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Merge only after the workstation step (as #147). | Recommended: yes. Built in. | accepted by merge, 17 Nov 2026 |
| 2 | demo12_stgccl bounds the annual discharge from below (STGOUT_BND), since demo12's electricity has one price in every DAYNITE timeslice and an unbounded storage stays idle, leaving the limit slack. | Recommended: yes. Built in. | accepted by merge, 17 Nov 2026 |

### #144 M1.3 (45): the PRC_STGIPS charging terms of EQ_STSBAL at ANNUAL (eqstgtss.mod L78-83) (merged 17 Nov 2026)

Logged here because #144 does not touch this file.

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | No row of v4.9.7 reaches the term (RP_STL's levels are TSL+1, ppmain.mod L1089; RP_STL is declared after the DD files, L23), so it has no GAMS reference and is checked on a constructed state only. Translate it so the refusal goes, or leave the refusal as dead code? | Recommended: translate. Built in. | accepted by merge, 17 Nov 2026 |

### #143 Decision log: James's answers of 17 Nov 2026 (merged 17 Nov 2026)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | The three answers are recorded where they apply: the gate scope in `docs/m13-plan.md` (Gate) and the translation guide; MACRO's solver in the translation guide; the speed target in the translation guide, `docs/timings.md` and `docs/phase2-notes.md` (P2-6). Dashboard slide 10 keeps its 5x line, now read as the Phase 2 target, until the next dashboard refresh relabels it. | Recommended: yes. Built in. | accepted by merge, 17 Nov 2026 |
| 2 | With the MIP and nonlinear features, ETL and MACRO out of the gate's scope, the extensions still to translate before the M1.3 gate are the stochastic extension and damage costs (`eqdamage.mod`), each checked first from the source to be linear. | Recommended: yes. Built in. | accepted by merge, 17 Nov 2026 |

### #142 Dashboard 16 Nov: the pass of 15 Nov, M1.3 changes 41 and 42 (merged 16 Nov 2026)

The morning refresh before the 9:00 check-in (James, 11 and 14 Nov 2026), made at 06:10 before the workstation was switched off for the day.

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | The batch was stopped at 06:07 for the shutdown, before the M1.3 probe of demo12 ran; slide 5 shows the other six runs from the pass of 15 Nov (420 of 420 steps) and demo12 from the pass before (15 Nov, main 5b0e1c2, 70 of 70), and says so in its note. | Recommended: yes. Built in. | accepted by merge, 16 Nov 2026 |

### #141 Dashboard: callout labels on slide 11 (merged 2026-11-15)

Asked for by James on 15 Nov 2026 ("add callout labels identifying each CPLEX (orange) HiGHS (green) pair of model+scenario run").

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | One label per model-scenario pair (seven per panel), with a leader line to the top mark of each of its two LPs, rather than one label per LP (fourteen, whose leader lines crossed in the cluster of the large models). The variant is read from position: the as-run LP has fewer columns, so it is the left one (the legend says so; the tooltip of a label gives both LPs' sizes). | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 2 | The labels stand in the widest empty band of the x axis (between demo12 and the large models), in the order of their marks' height; demo12's label is left-aligned on the band's left side. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |

### #140 M1.3 (42): the user-constraint attributes ANNUL, INVCOST, INVTAX, INVSUB (uc_ncap.mod L39); crafted case demo12_ucann (merged 2026-11-15)

Built from James's answer to #123, decision 4 (15 Nov 2026). Logged here because #140 does not touch this file.

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the new crafted case demo12_ucann (demo12 + ucann.dd, CC BY 4.0) with one public CI fixture (as run: the pre-solve dump, the CONVERT matrix, the solutions; about 4 MB), no variant or DD-compile fixture? | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 2 | The CST_ANNC term is compiled in only where uc_ncap.mod's %3 and %6 are written differently (`$IF NOT %3==%6`): the RHS direction of a dynamic constraint (equserco.mod L87). Elsewhere the attributes add nothing, whatever the values of the two periods. Translated as written. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 3 | ONLINE (uc_cap.mod L36-42) stays refused, the last refused UC_ATTR attribute; its own change. | Nothing to answer. | logged |

### #139 Dashboard: TIMES.jl in Dark green on light slides and Dark yellow on dark slides; GAMS orange (merged 2026-11-15)

Built from James's answer to #127, decision 2 (15 Nov 2026). Its list is logged here because the dashboard branch does not touch this file.

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | The hex values: TIMES.jl `#eaaa00` on dark slides and `#004539` on light slides; GAMS `#e06000` (not the ESMA palette's `#ff6a1f`, which is too close to the yellow on dark slides). | Recommended: as used. A choice the pull request made. | open; on the Open decisions list until James answers |
| 2 | Slide 10's 5x target line: Dark yellow on light slides, white on dark slides, so that it is never read as a TIMES.jl mark. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 3 | Slide 9's HiGHS dark green on light slides is TIMES.jl's colour on slides 10 to 12; the two never share a slide. | Nothing to answer. | logged |

### #138 Decision log: James's answers of 15 Nov 2026; merges of #126 to #137; extension scope (merged 2026-11-15)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | James's scope answer in the plan: the stochastic extension, ETL, MACRO with MSA and damage costs before the M1.3 gate, smaller ones first; all other extensions after M1.7. "All other remaining extensions" is read as the extension modules: the core features still refused stay in the order of 14 Nov 2026. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 2 | Four new rows on the Open decisions list (MACRO with IPOPT, the colour hex values, the dp prefix in the repository, TIMES-NZ in the batch's DD stage). | Nothing to answer here; each is asked on the list. | logged |

### #137 M1.3 (41): EQ_GR_XBND, the bound on a grid's net imports and exports; crafted case demo12_pfx (merged 2026-11-15)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | D44: the grid note (TIMES-Grid-Features §2.4) bounds a region's net grid flow by the capacity of its own lines; the code also takes a line's capacity in the other internal region when the line has no capacity variable in the region (powerflo.vda L352-353, L357-358), and under REDUCE a line without capacity data adds nothing, so with no such data the bound holds the net grid flow at zero. TIMES.jl follows the code. Report D44 to ETSAP with the other reports? Rule-level (a report to ETSAP). | Recommended: yes, as a documentation gap. Needs James's explicit yes. | open; on the Open decisions list |
| 2 | One public CI fixture for demo12_pfx (as run: the pre-solve dump, the CONVERT matrix, the solutions; about 4 MB), no variant or DD-compile fixture: the preprocessing of GR_XBND (filparam) is checked by the gate from the DD files on the workstation. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 3 | Stacked on #134: a stepped run needs the period filter of %R_T% (`eq_periods`, #129). No stepped grid case checks it; translated as written. | Nothing to answer. | logged |

### #136 README: status and progress as of 15 Nov 2026 (merged 2026-11-15)

Asked for by James on 15 Nov 2026.

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | The figures are those of the workstation batch of 14 Nov 2026 (main to #104): 490 of 490 preprocessing steps, 14 of 14 chains, 281 of 281 matrix and objective checks on the seven open model runs. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 2 | Only merged work is described: the stepped (myopic) runs (#126 to #134) are shown as in review. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 3 | The sentence on the model named in each commit's `Co-Authored-By` line is unchanged; whether to reword it is on the Open decisions list (the commit trailer). | Nothing to answer. | logged |

### #135 Dashboard 15 Nov: the 14 Nov pass, changes 28 to 40, the stepped solve in review (merged 2026-11-15)

Stacked on #127. Its list is logged here because the dashboard branches do not touch this file.

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Slide 6 with 35 CI runs (18 before): two panels, layer 1 (the seven coefficient files) one cell per run, the files in the tooltip. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 2 | Slide 3: ten tiles across (nine before), so the 68 changes fit. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 3 | Slide 2: the Solve stage counts `solve.stp` (377 lines with `solve.mod`) and shows "in review" while the stepped solve (#126 to #134) is open; the slide reads 10,521 of 11,534 lines (91%). | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 4 | The batch figures are from the 14 Nov pass on main c04c8ab (to #104); the pass on main 5b0e1c2 goes into the next refresh. The M1.3 gate is not shown as passed. | Nothing to answer. | logged |

### #134 M1.5 (7): a third stepped case, demo12_step3 (unit commitment, blending, storage, retirement); layers 1 to 3 per step (merged 2026-11-15)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | D43: GAMS itself keeps blending fixed at zero from the second step of a stepped run on (solve.stp L281, never lifted; seen in the LPs GAMS solved for demo12_step3). TIMES.jl follows the code, so there is no known difference. Report D43 to ETSAP as a likely fault of v4.9.7? This is part (b) of #129's decision 4; part (a), the check with a stepped blending case, is done here. | Recommended: yes, with the other reports. Rule-level: needs James's explicit yes. | open; on the Open decisions list (the row of #129) |
| 2 | CI fixtures for demo12_step3 as the other stepped cases have (the input, ppm and equ dumps and one data and one matrix fixture per step, as run; about 10 MB). | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 3 | No change to the translation: RVPRL (solve.stp L128) and the fixes of VAR_SIN, VAR_SOUT, VAR_UPS, VAR_UPT, VAR_UDP, VAR_SCAP and VAR_BLND (L203-207, L220, L233, L281), written in change 3, equal GAMS in every step. Each fix switched off in turn makes layer 2 fail, so the case does check them. | Nothing to answer. | logged |
| 4 | Still reached by no open stepped case, translated as written: solve.stp L177, L180-181 and L186-189 (REG_FIXT), L178-179 (a user constraint summed over the regions with a UC_CAP coefficient), EQE_UCRS, and L271-272 (the storage flows of pending periods fixed at zero), which no LP shows. A case for L178-179 and EQE_UCRS is a TODO for a later release. | Nothing to answer. | logged |

### #133 M1.5: the cumulative equations under OBJ LIN, checked on demo12_cumlin (merged 2026-11-15)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | CI checks only the cumulative rows of demo12_cumlin: GAMS's rows of EQ_CUMFLO, EQ_CUMNET and EQ_CUMPRD in a JSON file of 18 KB, compared with the rows TIMES.jl builds from the fixture of demo12_cumc with OBJ set to LIN. The whole case (layers 1 to 3) is checked on the workstation. The other way is a full set of fixtures (about 7 MB). | Recommended: the small file. Built in. | accepted by merge, 15 Nov 2026 |
| 2 | No change to the translation: the OBJ LIN weights of M1.1 were right. The notes "not parity-checked" are removed. | Nothing to answer. | logged |

### #132 M1.5 (6): OBJ LIN and OBJ ALT in a stepped (myopic) run; layers 1 to 3 per step on demo12_steplin (merged 2026-11-15)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Shared code: `gpow` (`x**y`) and `gpower` (`POWER(x,n)`) now round as GAMS 54.6.1 does (`exp(y*log(x))`; the product by repeated squaring), not as Julia's `^` (docs/discrepancies.md, G61). The divisor corrections of a stepped OBJ LIN run need it (values of 1e-10 left by cancellation, compared at 1e-9 relative). Every other fixture and reference case stays within the tolerances, and the generated LPs are unchanged at 1e-9 (the full test suite). | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 2 | D42: OBJ ALT in a stepped run of more than one step divides by zero in GAMS itself (coef_alt.lin L51 or L52), which skips the step and goes on. TIMES.jl stops with an error naming the line. (a) Accept the stop? (b) Report D42 to ETSAP? | Recommended: (a) yes; (b) yes, with the other reports. Rule-level: needs James's explicit yes. | open; on the Open decisions list |
| 3 | CI fixtures for demo12_steplin only (about 9.6 MB, as the other stepped cases have). demo12_steplino, demo12_stepalt1, demo12_lin and demo12_alt are in `reference/crafted.toml` and are checked with `scripts/m13_gate.jl` on the workstation, without fixtures. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 4 | The DD reader now translates the statements that set ALTOBJ (initmty.mod L421-423, L432); until now a run with OBJ STD, ALT or LIN stopped there when started from DD files. L422 (ALT) and L423 (LIN) are checked against GAMS's input dumps; L421 (OBJ STD) and L432 (OBLONG with OBJ ALT) follow the source, with no reference run from DD files. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 5 | Not checked yet under OBJ LIN: the weights of EQ_CUMFLO, EQ_CUMNET and EQ_CUMPRD (the new cases have no cumulative bound). A crafted case with the cumulative bounds of demo12_cumc and OBJ LIN follows as a small change of its own. EQ_STGIPS under OBJ LIN stays refused. | Nothing to answer. | logged |
| 6 | The gate script compares 11 more symbols per step instead of at the pre-solve checkpoint of a stepped run (57 in all). | Nothing to answer. | logged |

### #131 M1.5 (5): a second stepped case, demo12_step2; layers 1 to 3 per step (merged 2026-11-15)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | The second stepped case gets CI fixtures of its own (about 10 MB: input, ppm, equ, the run file, a data and a matrix fixture per step), as demo12_step has, so CI checks layers 1 to 3 of each of its steps. The other way is to check it with the gate script on the workstation only. | Recommended: fixtures. Built in. | accepted by merge, 15 Nov 2026 |
| 2 | D41: a stepped run applies a cumulative bound to EOH without the modifier of its N record, because bnd_cum.mod is not idempotent and solve.stp L227 includes it in every step. Followed as GAMS runs. Report it to ETSAP? | Recommended: yes, with the other reports. Rule-level: needs James's explicit yes. | open; on the Open decisions list |
| 3 | The plan had OBJ ALT or LIN in a stepped run (the divisors of coef_alt.lin L137-157) in this change. It is another GAMS file with a case of its own (demo12_steplin), so it becomes change 6; the stepped variants of the blending and the unit commitment cases (#129, decision 4a) become change 7. A stepped run with OBJ ALT or LIN stays refused until change 6 (#130, decision 6, said change 5). | Recommended: yes. Built in (docs/m15-plan.md). | accepted by merge, 15 Nov 2026 |
| 4 | A lead of the N record that is not an integer is now rounded as GAMS does (G29) instead of stopping the run, also in a run that is not stepped (bnd_cum.mod L19, L34). | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 5 | Harness 0.3.5 reads MODEL STATISTICS with "N projected"; references made with 0.3.4 stay valid. The gate script compares 19 more symbols per step instead of at the pre-solve checkpoint of a stepped run (46 in all). | Nothing to answer. | logged |
| 6 | Still reached by no open stepped case, translated as written: the copy-backs of solve.stp L177-181, L186-189 (REG_FIXT), the fixes of storage flows, VAR_UPS, VAR_UPT, VAR_UDP and VAR_SCAP, RVPRL, blending (U7), EQE_UCRS (docs/m15-plan.md, "Change 5 as built"). | Nothing to answer. | logged |

### #130 M1.5 (4): solve_stepped!, a stepped (myopic) run solved to its end; layer 3 per step on demo12_step (merged 2026-11-15)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | A step that does not end optimal stops the run with GAMS's message. GAMS also goes on after model status 2, 7 or 8 (locally optimal, feasible solution, integer solution) and, under `ERR_ABORT=NO`, after any status (err_stat.mod L63-69). | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 2 | A later step depends on which optimum an earlier step took, so on TIMES.jl's own levels the later steps' LPs need not be GAMS's (they are not on demo12_step; the objectives agree there to 1e-12). If the later objectives differ on another model for that reason alone, is the pass on GAMS's levels the parity check and the difference a known difference? | Recommended: yes. Rule-level; needs James's explicit yes. | James, 15 Nov 2026: yes ("a numerical stability issue with optimisation math and not TIMES.jl"): the pass on GAMS's levels is the parity check, and a difference in the later objectives for that reason alone goes into docs/known-differences.md |
| 3 | Not reproduced, none changing an LP or its optimum value: the advanced basis between the steps (`BRATIO=1`, solve.stp L285), the solver option file and PRIOROPT (solve.mod L14-15), TOLPROJ (L18); and GAMS's EPS for the marginal of a nonbasic variable with a zero reduced cost (zero here). | Recommended: yes. Built in (flagged). | accepted by merge, 15 Nov 2026 |
| 4 | The levels and marginals of the equations of a step are not kept, and `scripts/run_dd.jl --solve` solves a stepped run without writing its solution: both come with the reports of a stepped run (M1.6). | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 5 | `scripts/m11_probe.jl`, `scripts/parity_report.jl` and the cuOpt lane compare one LP per run; they now record a stepped run as skipped, with the reason (its steps are checked by `scripts/m13_gate.jl` and in CI), instead of refused. A line per step on the boards can come with M1.6. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 6 | A stepped run with OBJ ALT or LIN is refused until change 5 (the divisors of coef_alt.lin L137-157 need a crafted case); FIXBOH, STAGES, SPINES, SENSIS, CLI and TM_HSX with a stepped run stay refused (#126, decision 6). solve.stp L330 (MY_FYEAR, FIXBOH) is not translated. | Nothing to answer. | logged |

### #129 M1.5 (3): the equations and the bounds of one step of a stepped run; layer 2 per step on demo12_step (merged 2026-11-15)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | The bounds of a stepped run are kept in one table for the whole run, changed in GAMS's order (maindrv.mod L92, then solve.stp L193-233 and L267-281 before each SOLVE and bndmain.mod with 1 after it), because in GAMS a bound stays on a variable from step to step unless a statement resets it. The JuMP model is built anew for each step (`stp_model`) and takes its bounds from that table. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 2 | Three more CI fixtures, `test/fixtures/demo12_step_step<k>_matrix` (the LP GAMS solved in each step, written by CONVERT, with its dictionary; about 1.3 MB in all; demo12, CC BY 4.0), and the three step fixtures of #128 grow to about 1.4 MB in all: they now hold the levels of the variables a later step fixes. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 3 | Branches demo12_step does not reach are translated as GAMS writes them and listed as not checked against GAMS (docs/m15-plan.md, "Change 3 as built": the fixes of storage flows, of VAR_UPS, VAR_UPT and VAR_UDP, of VAR_SCAP and of VAR_BLND; CAP_BND on VAR_CAP; VAR_CUMCOM; the resets of four of the six slack variables; the period test of the equation families demo12_step has no row of). Flagged and listed, as James said on 14 Nov 2026. | Built in (flagged). | accepted by merge, 15 Nov 2026 |
| 4 | solve.stp L281 fixes blending in the pending periods at zero and nothing lifts the fix (discrepancies.md U7). Translated as written. (a) Check it with a stepped blending case in change 5? (b) If GAMS keeps the fix, report it to ETSAP? | Recommended: yes to both. (b) is rule-level and needs James's explicit yes. | (a) done in #134 (dp43, written D43 in docs/discrepancies.md); (b) open, on the Open decisions list |
| 5 | The statements of solve.stp on VAR_ELAST (L211, L276) and VAR_DAM (L212) are not translated: elastic demand and damage are still refused, and their stepped statements come with those features. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 6 | A stepped run as a whole is still refused until change 4 (the loop with the SOLVE); only the model of one step is generated. | Nothing to answer. | logged |

### #128 M1.5 (2): solve.stp, the partition and the preparation of each step of a stepped run (merged 2026-11-15)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | The levels and marginals GAMS reads between two steps (`VAR_CAP.L`, the slack levels of the user constraints, `VAR_CUMFLO.M`, ...) are kept in a point store of their own (`StpPoint`), apart from the JuMP model, which is built anew in each step. The check of a step loads GAMS's point of the step before into it; the driver of change 4 will merge each solution into it, as SOLVEOPT=MERGE does. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 2 | Three more CI fixtures, `test/fixtures/demo12_step_step<k>` (about 1 MB in all; demo12, CC BY 4.0): each holds only what differs from the `equ` fixture after the SOLVE of step k, the variables the point store reads, and the list of the symbols equal to the `equ` fixture's, so every set and parameter of each step is still compared. Made by `scripts/make_step_fixture.jl`. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 3 | The divisors of coef_alt.lin STP under OBJ ALT or LIN (L137-157) are refused in a stepped run until the second crafted case of change 5 can check them, instead of being translated unchecked now. demo12_step runs with OBJ MOD and does not reach them. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 4 | Refused in a stepped run, with the usual message: STAGES, SPINES and SENSIS (the stochastic extension), CLI and UC_CLI data (the climate extension), TM_HSX; FIXBOH as #126, decision 6 (REG_FIXT is emptied without it, as setglobs.gms L11 does). | Built in. | accepted by merge, 15 Nov 2026 |
| 5 | Branches of solve.stp that demo12_step does not reach are translated as GAMS writes them and listed as not checked against GAMS (docs/m15-plan.md, "Change 2 as built": a given G_OVERLAP, STP_DIV, CAP_BND, user constraints summed over periods or regions and dynamic ones, PRC_DYNUC, REG_CUMCST, RVPRL, COM_CUM). The second crafted case (#126, decision 5) is to reach them. Flagged and listed, as James said on 14 Nov 2026. | Built in (flagged). | accepted by merge, 15 Nov 2026 |
| 6 | The decision log records #127's list (below); its decision 2 is on the Open decisions list. | Nothing to answer. | logged |

### #127 Dashboard: orange GAMS, ESMA-green TIMES.jl, HiGHS as a triangle; wall timer; GAMS/HiGHS for OTCGEN and OTNYC (merged 2026-11-15)

Built from James's answers of 14 Nov 2026 on #125 (decisions 6, 8, 9 and 10).

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Colour is the language, shape is the solver: GAMS orange and TIMES.jl green on slides 10 to 12; CPLEX a circle and HiGHS an isosceles triangle pointing up on slides 9, 11 and 12. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 2 | Which green and which orange? Used: Green `#00c463` (Pantone 2420 C) and `#e06000`; the brand book also has Dark green `#004539` and has no orange. | Recommended: as used. A choice the pull request made. | James, 15 Nov 2026: GAMS in ESMA orange; TIMES.jl in ESMA sunshine yellow on the dark green slides and in ESMA green on light slides. Built in a follow-up pull request; the hex values it uses are on the Open decisions list until James confirms them |
| 3 | Keep the brand green on both surfaces despite two notes of the palette validator (light slides: contrast with white 2.31:1, under 3:1; dark slides: the lightness band fails, 0.718 against 0.67)? The darker `#00ae55` would come too close to the orange under colour-vision deficiency. | Recommended: keep. Built in. | accepted by merge, 15 Nov 2026; superseded by James's answer to decision 2 (15 Nov 2026) |
| 4 | Slide 9 keeps its own colours (its marks are TIMES.jl's difference from a GAMS solve); only its HiGHS diamond becomes the triangle. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 5 | What TIMES.jl's whole-run time holds: the parts, the checks against GAMS at every step, the harness's copy of the input, and in the first run of a process the loading and compiling. It is not the same measure as GAMS's whole-run time; the slide's footer and tooltips say so. | Recommended: accept. Built in. | accepted by merge, 15 Nov 2026 |
| 6 | The timings are refreshed after each nightly as a step of the 9:00 dashboard update (the command is in `docs/dashboard/README.md`), not inside the nightly batch. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 7 | A model in `reference/suite.toml` can list its own `solvers`: OTCGEN and OTNYC list CPLEX and HiGHS, the OTUS9r cases CPLEX alone (`run_references.ps1` 0.1.20). The next full `-Resume` run reruns OTCGEN and OTNYC. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |

### #126 M1.5 (1): the per-step reference of stepped (myopic) runs, harness 0.3.4; the plan of the stepped solve (merged 2026-11-15)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep every step of a stepped GAMS run in the reference (`steps/<k>/`: the dump after each SOLVE, and CONVERT's export of each step's model), through the two hooks TIMES has for a web front end (`www_in.cgi`, `www_out.cgi`), so that TIMES is not edited? | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 2 | The first solve run of every model is started with two more flags (`--GAMS_CGI=WWW --TJL_STEPS=DUMP`). They do nothing unless GAMS itself says the run is stepped (checked on demo12: every symbol of every dump identical, but for the harness's own record of run times). Existing references are not rerun for it. | Recommended: yes. Built in. | accepted by merge, 15 Nov 2026 |
| 3 | A stepped reference has no `matrix/` of its own, only `steps/<k>/matrix/`: a stepped run has no single model. The gate and probe scripts accept that. | Built in. | accepted by merge, 15 Nov 2026 |
| 4 | The plan of the stepped solve, `docs/m15-plan.md` (part 1 of M1.5): the partition and the preparation of a step (layer 1 per step), the equations over SUBT and the bounds (layer 2 per step), the driver with the solve (layer 3 per step), then a second crafted case. Layers 1 and 2 are checked on GAMS's levels of the step before, layer 3 on TIMES.jl's own. | Recommended: yes. Built in (the plan). | accepted by merge, 15 Nov 2026 |
| 5 | A second crafted case for the branches demo12_step does not reach (OBJ LIN, a given G_OVERLAP, CAP_BND, a cumulative and a dynamic user constraint, COM_CUM), as change 5 of the plan? | Recommended: yes. In the plan; not built yet. | accepted by merge, 15 Nov 2026; built as M1.5 change 5 (demo12_step2, #131) |
| 6 | FIXBOH and REG_FIXT stay refused in a stepped run until the restart points (SPOINT, LPOINT) are translated, part 2 of the M1.5 plan: they take their levels from a restart point and no open model has one. Flagged and listed, as James said on 14 Nov 2026. | Built in (the plan). | accepted by merge, 15 Nov 2026 |
| 7 | The decision log records the merges of #114 to #125 and James's answers of 14 Nov 2026 on #120 (decision 5), #121 (decision 2) and #125 (decisions 6, 8, 9, 10). | Nothing to answer. | logged |

### #125 Dashboard: timing slides, run time against model size and where the time goes (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Two new slides (11: the scatter; 12: the break-out) instead of one; slide 10 unchanged. | Recommended: keep two. Built in. | accepted by merge, 14 Nov 2026 |
| 2 | Slide 11 has two panels (from the input files to the LP; the solve) and not one point for the whole run. | Recommended: keep. Built in. | accepted by merge, 14 Nov 2026 |
| 3 | Slide 12 shows the as-run variant only; slide 11 shows both variants. | Recommended: keep. Built in. | accepted by merge, 14 Nov 2026 |
| 4 | First runs of a Julia process (they include the compilation) are drawn faint, not dropped; the ratios in the subtitle use warm runs only. | Recommended: keep. Built in. | accepted by merge, 14 Nov 2026 |
| 5 | The crafted demo12 cases are left off: they have no TIMES.jl timings from the workstation. | Recommended: leave them off until a workstation batch times them. Built in. | accepted by merge, 14 Nov 2026 |
| 6 | Colours and shapes: GAMS a blue circle, TIMES.jl a green square, as on slide 10; CPLEX filled, HiGHS a ring. | Recommended: keep. Built in. | accepted by merge, 14 Nov 2026; changed by James the same evening: GAMS marks orange, TIMES.jl marks in ESMA's green, HiGHS an isosceles triangle pointing up (a follow-up pull request) |
| 7 | A new script `scripts/run_timing.jl` that only reads existing output; the readers of GAMS's profile move to `scripts/gams_profile.jl`, shared with the M1.2 and M1.3 timing scripts. | Recommended: keep. Built in. | accepted by merge, 14 Nov 2026 |
| 8 | Fill the "not measured" cells (TIMES.jl's whole run; TIMES.jl with CPLEX)? | Recommended: a wall-clock timer in the batch now, TIMES.jl with CPLEX in Phase 2. Not built in. | James, 14 Nov 2026: yes, build in a wall timer (a follow-up pull request); TIMES.jl with CPLEX stays for Phase 2 |
| 9 | Refresh the timings after each batch? | Recommended: yes, once James is happy with the slides. Not built in. | James, 14 Nov 2026: yes, updated after each nightly and refreshed before the 9:00 check-in |
| 10 | GAMS/HiGHS solves for OTCGEN and OTNYC at the next reference run? | Recommended: yes; not OTUS9r. Not built in. | James, 14 Nov 2026: yes, OTCGEN and OTNYC with HiGHS at the next reference run; OTUS9r omitted for now |

### #124 M1.3 (40): eqlducs.vda L12-124, unit commitment by start-up type, crafted cases demo12_uc and demo12_ucv (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the new crafted case demo12_ucv (demo12 + ucv.dd, CC BY 4.0; a public fixture, a variant fixture and a DD-file compile case, about 7.6 MB), and make demo12_uc a public fixture too (its matrix and solution, about 1.4 MB)? | Recommended: yes. Built in. | accepted by merge, 14 Nov 2026 |
| 2 | The refusal of unit commitment by start-up type (ACT_CSTSD, ACT_SDTIME, ACT_LOSSD data) is lifted, following James's instruction of 14 Nov 2026: the preparation, the seven equation families with VAR_UPT and the cost term in EQ_OBJVAR are translated and checked on demo12_uc and demo12_ucv, layers 1 to 3 in both variants. | Built in. | accepted by merge, 14 Nov 2026 |
| 3 | Branches translated as GAMS has them but reached by no case, since no open model has the data (docs/m13-plan.md, change 40): a process with EQ(l)_CAFLAC (eqlducs.vda L17); ACT_TIME 'FX'; a user-given ACT_CSTSD 'FX'; a missing ACT_MAXNON for HOT or WARM; a WEEKLY level; a cycle with more than two timeslices; a neighbour term at SEASON; a HOT start-up in the windows of eq_sdslant and eq_sudpll across timeslices. Leave them translated and flagged, or refuse them? | Recommended: leave translated and flagged (James, 14 Nov 2026: flag and list what cannot be verified). Built in. | accepted by merge, 14 Nov 2026 |
| 4 | Layer 3 says little about the unit commitment on both cases: the objective of demo12_uc equals demo12_disp's and the objective of demo12_ucv equals demo12's, so GAMS's optimum pays no start-up cost by type. Layer 2 checks every coefficient of the 200 and 800 rows and of the cost term. Accept the cases as they are, or change the data until the unit commitment binds? | Recommended: accept; layer 2 is the check of the translation. Built in. | accepted by merge, 14 Nov 2026 |
| 5 | The discrete unit commitment (`$SET DUC YES`, eqlducs.vda L126-175, a MIP) and the SPRSV term of eq_sudload (the ABS extension) are not translated. The first is the question of #120, decision 5. | Recommended: a later release. | James, 14 Nov 2026: yes, left until after M1.3 (#120, decision 5) |
| 6 | The M1.4 gate's CI criterion ("CI runs the chain from DD files on the crafted cases"): demo12_uc now runs to the end in that chain (30 cases), so the criterion is met once this merges (James, 14 Nov 2026: the unit commitment first). Whether the M1.4 gate is passed stays James's decision (#117, decision 1). | Built in. | accepted by merge, 14 Nov 2026 |
| 7 | Part II has no formulation of these equations ("see separate documentation", which is not in the documentation repository; D40). (a) Does James have that document? (b) Tell ETSAP it is missing from the repository? (b) is rule-level. | Recommended: (a) the GAMS source alone for Phase 1 (built in), compared when the document is at hand; (b) yes. | James, 15 Nov 2026: (b) yes, tell ETSAP with the other reports; (a) the GAMS source alone, as built in |

### #123 M1.3 (39): EQ_BNDCST, eqbndcst.mod L42-77 and L81-213, crafted case demo12_bndcst (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the new crafted case demo12_bndcst (demo12 + bndcst.dd, CC BY 4.0; a public fixture, a variant fixture and a DD-file compile case, about 7.5 MB)? | Recommended: yes. Built in. | accepted by merge, 14 Nov 2026 |
| 2 | The refusal of REG_BNDCST/REG_CUMCST data (#72, decision 1) is lifted: eqbndcst.mod L42-77, the equation EQ_BNDCST and the bounds of VAR_CUMCST (bnd_cum.mod L44-48) are translated and checked on demo12_bndcst, layers 1 to 3 in both variants. | Built in. | accepted by merge, 14 Nov 2026 |
| 3 | Branches no case reaches, translated from the source as written and listed as TODO for a later release (docs/m13-plan.md, change 39): OBJ LIN and VARCOST LIN in the commodity and flow terms (eqbndcst.mod L85-87); CST_ANNC for the processes of a user constraint (L50, L67), whose term in uc_ncap.mod L39 (UC_ATTR ANNUL, INVCOST, INVTAX, INVSUB) stays refused; a first year before the horizon that YK holds a pair for; a currency other than the region's. Accept them as unverified until a case reaches them? | Recommended: yes; a crafted case with OBJ LIN can follow when M1.5 covers the objective variants. Built in: translated, flagged, listed. | accepted by merge, 14 Nov 2026 |
| 4 | Lift the refusal of UC_ATTR ANNUL/INVCOST/INVTAX/INVSUB (uc_ncap.mod L39) as its own change, now that CST_ANNC exists? It needs a crafted case with a user constraint on VAR_NCAP. It is a remaining refused feature under James's instruction of 14 Nov 2026. | Recommended: yes, as its own change after the unit commitment. No default built in: it is not in this change. | James, 15 Nov 2026: yes; its own change (M1.3 change 42) |
| 5 | Three differences from Part II §6.3.13 (D37 to D39 in docs/discrepancies.md), all followed as GAMS writes them and all in GAMS's own matrix: a single-period INV row holds the decommissioning costs twice (D37); a flow with a tax and a subsidy counts with the net of the two (D38); a single-period row of INV, INVTAX or INVSUB holds only the vintages of periods that have such a bound themselves (D39). D37 and D39 look like mistakes in TIMES v4.9.7. Report them to ETSAP with the other D-entries? Rule-level (a report to ETSAP). | Recommended: yes. Nothing is sent until James says so. | James, 15 Nov 2026: yes, report dp37 to dp39 (D37 to D39 in docs/discrepancies.md) to ETSAP |
| 6 | The step probe compares the scratch set UNCD7 at the eqmain step only in a model with dispatching data (change 36, #120, put it on that step's list for every model). eqmain.mod writes UNCD7 only inside the dispatching IF (eqactups.vda L10, L28); in demo12_bndcst the decommissioning data leave 11 entries in it (eqobjinv.mod L245-247) that pp_qack.mod replaces later, and the probe failed there on the rebase onto #120. UNCD7 is still compared at the pp_qack step in every model, and at the eqmain step on demo12_disp. | Built in. | accepted by merge, 14 Nov 2026 |

### #122 M1.3 (38): EQ(l)_CAPVAC, coef_csv.mod L11-77 and eqcapvac.mod L14-28, crafted case demo12_capvac (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the new crafted case demo12_capvac (demo12 + capvac.dd, CC BY 4.0; a public fixture, a variant fixture and a DD-file compile case, about 7 MB)? | Recommended: yes. Built in. | accepted by merge, 14 Nov 2026 |
| 2 | The refusal of PRC_SIMV data is lifted: coef_csv.mod (the simulated vintages) and the three EQ(l)_CAPVAC equations are translated and checked on demo12_capvac, layers 1 to 3 in both variants. | Built in. | accepted by merge, 14 Nov 2026 |
| 3 | GAMS 54.6.1 runs coef_csv.mod L48 `OPTION FIL < T` (T an alias of MILESTONYR) as an assignment of the empty set, so FIL holds one year (2004 in demo12), L52-63 share no capacity, and L65 puts COEF_CPT only into the simulated vintage of the past investments. The effect in the model: new capacity counts in a period only where its own year is a simulated vintage of that period; in the other periods of its life it is in no CAPVAC row (in demo12_capvac the gas plant built in 2015 has no capacity in 2020). TIMES.jl follows GAMS as it runs, and the matrix is identical. This looks like a fault in TIMES v4.9.7 (or a change in GAMS since the line was written), not an intended result. Accept GAMS 54.6.1's result as the translation, and report it to ETSAP? Rule-level: a result that looks unintended is kept, and a report goes to ETSAP. | Recommended: yes to both: keep the translation as GAMS runs (built in), and report it. | James, 15 Nov 2026: yes to both: GAMS's result is the translation, and coef_csv.mod L48 is reported to ETSAP |
| 4 | eqcapvac.mod L27 adds NCAP_PASTI(R,K,P) as it is, without COEF_CSV or COEF_AF: `...*VAR_NCAP(R,K,P)$T(K)+NCAP_PASTI(R,K,P)`. A past investment counts with availability 1 and in full until the last period of its life, when its COEF_CPT is below 1 (REG1 ELCREHYD00 in 2010: 31 GW in the row where COEF_CPT gives 22.4). Translated as written; confirmed on GAMS's rows (D36). Report it to ETSAP with item 3? Rule-level (a report to ETSAP). | Recommended: yes. Nothing is sent until James says so. | open; needs James's explicit yes (Open decisions) |
| 5 | Translated as written but reached by no case, no demo12 data reaches them (TODO for a later release; docs/m13-plan.md, change 38; U6): the VAR_FLO part of the flow term (a standard process with several commodities in its primary group and NCAP_AFC; demo12 has none, and ppm_ext.vda L123 keeps the activity term for a process with one); EQL_CAPFLO and EQ(l)_CAFLAC beside PRC_SIMV; %VINTOPT% 2 (fillvint.gms L15 fills PRC_SIMV); %TRIVINT% other than 6; coef_csv.mod L27 with RP_UPL 'FX' (a simulated process with dispatching data; no case has both); a stochastic run (`%SWX%` = ',SOW'). | Built in: translated, flagged, listed. | accepted by merge, 14 Nov 2026 |
| 6 | The pre-solve comparison of RTP at the eqobjinv step is skipped when NO_RVP has entries (only with PRC_SIMV, ppmain.mod L590): pp_qack.mod L54 takes those entries out of RTP later, so the step's RTP differs from the dump by design. RTP is still compared at the earlier checkpoints and at the last step. | Built in. | accepted by merge, 14 Nov 2026 |

### #121 M1.3 (37): EQ(l)_BLND, eqblnd.mod L67-71, crafted case demo12_blnd (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the new crafted case demo12_blnd (demo12 + blnd.dd, CC BY 4.0; a public fixture, a variant fixture and a DD-file compile case, about 7.5 MB)? | Recommended: yes. Built in. | accepted by merge, 14 Nov 2026 |
| 2 | The refusal of blending data is lifted everywhere: the four equations, the blending preparation (ppmain.mod L1246-1333), the blending terms of the commodity balance, the peak equation and the objective, and the blending costs in the currency conversion (curex.gms L59-60). This reverses #42 (5 Nov 2026: "Refused; no blending test model"), following James's instruction of 14 Nov 2026 that every remaining refused feature is translated. Rule-level (a logged decision reversed; test data). | Recommended: yes. Built in. | James, 14 Nov 2026: "yes, it is built in". #42 is reversed. |
| 3 | A type 4 specification (=N=) is a free row in GAMS's matrix (bounds -INF, +INF). `gconstraint!` takes a new type "N" and writes it as `lhs - rhs in [-Inf, Inf]`, so the row count and order match GAMS. Shared code, but no existing row changes. | Built in. | accepted by merge, 14 Nov 2026 |
| 4 | TIMES only declares BLE_INP (the statements that filled it are comments, ppmain.mod L1267-1272), so BL_INP, BL_DELIVC and PEAKDA_BL act only when the model's own data fills BLE_INP. The case declares and fills it in blnd.dd under the run's `$ONMULTI`. Keep that in the case? | Recommended: yes (it is the only way to reach eqcombal.mod L78-80 and eqpeak.mod L78). Built in. | accepted by merge, 14 Nov 2026 |
| 5 | Two paths are translated and were checked against GAMS, but only on a scratch case that is not in the repository (demo12_blndx: demo12_blnd + REFUNIT 3 for REG1 + three more currencies with blending costs in them): the REFUNIT 3 branch of ppmain.mod L1301-1316 and curex.gms L59-60. Add it as a second crafted case (about 7.5 MB more), or leave the check as a note in docs/m13-plan.md? | Recommended: leave it as a note (flagged and listed, as for the branches of #120). No default built in beyond that: the branch holds only demo12_blnd. | open (Open decisions) |
| 6 | Not part of this change, with the features they belong to: the blending costs in the reports (eqobjvar.rpt L103-104 and L174-175, M1.6), the IER market equation (eqmrkcom.ier L33-66), the stochastic and stepped files (clearsol.stc L18, pextlevs.stc L25, recurrin.stc L135, rptmain.stc L39, solve.stp L232-233 and L281), spoint.mod L34. | Built in. | accepted by merge, 14 Nov 2026 |
| 7 | Three differences between the GAMS code and Part II on blending are logged as D33 to D35 in docs/discrepancies.md (a fourth type and the start year; the unit of VAR_BLND and where BLE_BAL acts; the terms Part II does not show). The code is followed. | Logged; not reported to ETSAP. | accepted by merge, 14 Nov 2026 |

### #120 M1.3 (36): eqactups.vda L9-117, dispatching in the linear formulation, crafted case demo12_disp (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the new crafted case demo12_disp (demo12 + disp.dd, CC BY 4.0; a public fixture, a variant fixture and a DD-file compile case, about 7 MB)? | Recommended: yes. Built in. | accepted by merge, 14 Nov 2026 |
| 2 | The refusal of dispatching data (ACT_UPS, ACT_LOSPL, ACT_CSTPL, ACT_CSTRMP: the sets RP_UPL and RP_PL) is lifted: the preparation, the seven equation families and their terms in EQ_OBJVAR, EQE_ACTEFF and EQ(l)_CAPACT are translated and checked on demo12_disp. | Built in. | accepted by merge, 14 Nov 2026 |
| 3 | Six branches are translated as GAMS has them but reached by no case, since no open model has the data (docs/m13-plan.md, change 36): `%UPSCAP0%` in EQ(l)_CAFLAC and EQL_CAPFLO; ACT_UPS below ANNUAL; a WEEKLY level or a dispatched process at ANNUAL; a start-up cost at ANNUAL without RP_UPL 'FX' or with RP_PL 'UP'; EPS in eqactups.vda L12; the cycle limit of a vintaged process. Leave them translated and flagged, or refuse them? | Recommended: leave translated and flagged (James, 14 Nov 2026: flag it, list it, move on). Built in. | accepted by merge, 14 Nov 2026 |
| 4 | Layer 3 on demo12_disp exercises the costs of REG1 only: the dispatching variables of REG2 are all zero in GAMS's optimum (the objective equals demo12_uc's). Layer 2 checks every coefficient of both plants. Accept the case as it is, or change REG2's data until its dispatching binds? | Recommended: accept; layer 2 is the check of the translation. Built in. | accepted by merge, 14 Nov 2026 |
| 5 | The discrete unit commitment (`$SET DUC YES`, a MIP) is not translated: the switch is refused with a message, and it is noted as a TODO for a later release. Rule-level if the M1.3 gate closes without it. | Recommended: yes, a later release. | James, 14 Nov 2026: "ok to leave discrete unit commitment until after M1.3". It stays refused while the M1.3 gate closes and is taken up after it. |
| 6 | demo12_uc still stops at the unit commitment by start-up type (eqlducs.vda L12-124). It is the next change (#124); the M1.4 CI criterion counts as met only after it (James, 14 Nov 2026). | Following James's instruction. | accepted by merge, 14 Nov 2026 |

### #119 M1.4 (9b): the four older crafted cases in the one run from DD files (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the eight new fixtures: a run file and an input dump for demo12_red17b, demo12_ips, demo12_ucrt and demo12_objinv (CC BY 4.0, about 4.4 MB together), so that 24 crafted cases go from their DD files to the model in CI? | Recommended: yes. Built in. | accepted by merge, 14 Nov 2026 |
| 2 | With these four, 24 of the 25 crafted cases of the time run from their DD files in CI; demo12_uc is the one left (#118, decision 2). | James, 14 Nov 2026: the criterion is not met until the unit commitment is translated. | answered by James, 14 Nov 2026 (#118, decision 2) |

### #118 M1.4 (9): CI runs every crafted case from its DD files to the model (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Add the one run to CI: 20 crafted cases from their DD files to the model, against GAMS's matrix and objective, with no GAMS state (about a minute and a half more test time on the workstation)? Decision 2 of #117. | Recommended: yes. Built in. | accepted by merge, 14 Nov 2026 |
| 2 | Does the gate's CI criterion count as met while demo12_uc stops at unit commitment (eqlducs.vda, not translated) and four older crafted cases (demo12_red17b, demo12_ips, demo12_ucrt, demo12_objinv) have no run file or input fixture in the repository? | Recommended: yes; the four cases get their fixtures in a small PR, and unit commitment is translated by priority with the other refused families. | answered by James, 14 Nov 2026: not met until the unit commitment is translated, and demo12_uc joins the run; the dispatching half is #120, the unit commitment the change after it. Moved from Open decisions, 14 Nov 2026. The four cases are added in #119. |

### #117 M1.4 (8) and gate close-out: warnings as GAMS counts them, TIMES's GDX filter, a key given twice (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Is the M1.4 gate passed? Every criterion of docs/m14-plan.md has its evidence in "Gate close-out, 14 Nov 2026". Rule-level (a milestone gate); it waits for the M1.3 gate (#109). | Recommended: yes, once the M1.3 gate is passed and the batch has rerun the chain from DD files on the merged stack. | open; needs James's explicit yes, a merge does not answer it (Open decisions) |
| 2 | "CI runs the chain from DD files on the crafted cases": CI does it in pieces that meet at GAMS's dumps; only demo12 goes from DD files to the model in one run. Accept this, or add the one run for every crafted case? | Recommended: add the one run, as the next PR: each crafted case from its DD files to the model, against GAMS's matrix and objective, with the fixtures CI already has. | the one run: accepted by merge of #118, 14 Nov 2026; the criterion is met with #124 merged (the unit commitment translated, demo12_uc in the run): #118, decision 2 |
| 3 | The reader counts compile warnings as GAMS does, one for each label outside its domain set: 88 on TIMES-NZ, not 84. | Built in. | accepted by merge, 14 Nov 2026 |
| 4 | The three cases where GAMS keeps a record outside its domain set (no DATAGDX YES; a one-dimensional set or parameter; a label that joins the set later) stop the run with a message; they are translated when a model needs them. No suite model has one. | Built in. | accepted by merge, 14 Nov 2026 |
| 5 | A key given twice in one data statement stops the run, as GAMS's compile error 172; before, the later record won. No suite model has one. | Built in. | accepted by merge, 14 Nov 2026 |

### #115 M1.3 (35): EQ(l)_XBND, eqxbnd.mod L17-56, crafted case demo12_xbnd (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the new crafted case demo12_xbnd (demo12 + xbnd.dd, CC BY 4.0; a public fixture, a variant fixture and a DD-file compile case, about 7 MB)? | Recommended: yes. Built in. | accepted by merge, 14 Nov 2026 |
| 2 | The refusal of IRE_XBND data is lifted: the three equations are translated, for internal and external regions, and checked on demo12_xbnd. No earlier code needed a change. With this the bound equations of eqmain.mod are all translated. | Built in. | accepted by merge, 14 Nov 2026 |
| 3 | Two other uses of IRE_XBND in GAMS are not part of this change: dynslite.vda L36 (turned-off timeslices) and solve.stp L257-263 (the stepped run, M1.5). Both stay with the features they belong to, which are still refused (TS_OFF data with DYNTS; a stepped run). | Built in. | accepted by merge, 14 Nov 2026 |

### #114 M1.3 (34): EQ(l)_IREBND, eqirebnd.mod L18-69, crafted case demo12_irebnd (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the new crafted case demo12_irebnd (demo12 + irebnd.dd, CC BY 4.0; a public fixture, a variant fixture and a DD-file compile case, about 7 MB)? | Recommended: yes. Built in. | accepted by merge, 14 Nov 2026 |
| 2 | The refusal of IRE_BND data is lifted: the three equations are translated and checked on demo12_irebnd. No earlier code needed a change. | Built in. | accepted by merge, 14 Nov 2026 |
| 3 | One branch of the equation stays refused: exports from a marketplace region (eqirebnd.mod L46-51), with the market-based trade it belongs to (RPC_MARKET, eqire.mod L23-38, refused since M1.1). The suite models that generate today have no such data. | Built in; it follows with market-based trade. | accepted by merge, 14 Nov 2026 |

### #113 M1.3 (33): EQ(l)_FLOFR, eqflofr.mod L15-27, crafted case demo12_flofr (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the new crafted case demo12_flofr (demo12 + flofr.dd, CC BY 4.0; a public fixture, a variant fixture and a DD-file compile case, about 7 MB)? | Recommended: yes. Built in. | accepted by merge, 14 Nov 2026 |
| 2 | The refusal of FLO_FR data is lifted: the three equations are translated and checked on demo12_flofr. No earlier code needed a change. | Built in. | accepted by merge, 14 Nov 2026 |

### #112 M1.3 (32): EQ(l)_FLOBND, eqflobnd.mod L15-43, crafted case demo12_flobnd (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the new crafted case demo12_flobnd (demo12 + flobnd.dd, CC BY 4.0; a public fixture, a variant fixture and a DD-file compile case, about 7 MB)? | Recommended: yes. Built in. | accepted by merge, 14 Nov 2026 |
| 2 | The refusal of FLO_BND records that are not bounds of one flow variable is lifted: the three equations are translated and checked on demo12_flobnd. | Built in. | accepted by merge, 14 Nov 2026 |
| 3 | Two corrections of `bnd_data!` (M1.3 change 25-4), shown by the new case: bnd_flo.mod L16 reaches only single commodities in milestone years, and L31 clears TRACKPC. Both follow GAMS as written. No open suite model has FLO_BND data in its input, and the earlier cases with FLO_BND data pass unchanged. | Built in. | accepted by merge, 14 Nov 2026 |

### #111 M1.3 (31): EQ(l)_BNDNET and EQ(l)_BNDPRD, eqbndcom.mod L16-24, crafted case demo12_bndc (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the new crafted case demo12_bndc (demo12 + bndc.dd, CC BY 4.0; a public fixture, a variant fixture and a DD-file compile case, about 7 MB)? | Recommended: yes. Built in. | accepted by merge, 14 Nov 2026 |
| 2 | The refusal of COM_BNDNET and COM_BNDPRD records above the commodity's tracked timeslice level is lifted: the six equations are translated and checked on demo12_bndc. | Built in. | accepted by merge, 14 Nov 2026 |
| 3 | The refused equation families are translated before the M1.3 gate is declared passed and before the move to v4.9.8 (James, 14 Nov: "lets push on these last features today"); next the other bound equations, EQ(l)_FLOBND, EQ(l)_FLOFR, EQ(l)_IREBND and EQ(l)_XBND, one PR each; the remaining refused families (`untranslated_families`) after them, by what the suite models need. | Following James's instruction. | accepted by merge, 14 Nov 2026; the order against v4.9.8 was answered by James the same day (#109, decision 3) |

### #110 M1.3 (30): stepped runs before solve.stp, coef_alt.lin L81 and eqobsalv.mod L23-25; harness 0.3.3 (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Harness 0.3.3: a new checkpoint `equ/` (after eqmain.mod, maindrv.mod L79-80), written for stepped runs only; other references do not change and need no rerun. | Recommended: yes. Built in. | accepted by merge, 14 Nov 2026 |
| 2 | The pre-solve dump of a stepped run holds the state after the loop of solve.stp, so the chain compares it less the 27 symbols that loop assigns (each traced to its GAMS line); all 27 are compared at `equ/`, before the loop. Not logged as a known difference: GAMS and TIMES.jl agree on every symbol at the state both hold. | Recommended: yes. Built in. | accepted by merge, 14 Nov 2026 |
| 3 | Keep two more fixtures of demo12_step (`ppm`, 2.2 MB; `equ`, 2.6 MB; CC BY 4.0)? | Recommended: yes. Built in. | accepted by merge, 14 Nov 2026 |
| 4 | The stepped solve (solve.stp, M1.5) before the M1.3 and M1.4 gates close: asked in #108 and on the Open decisions list. This change stops where it starts. | Recommended: yes, after the M1.3 gate. | answered by James, 14 Nov 2026: yes (#108, decision 3) |

### #109 M1.3 gate close-out: the evidence for each criterion, 13 Nov timings (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Is the M1.3 gate passed? Every criterion of docs/m13-plan.md "Gate" has its evidence in "Gate close-out, 14 Nov 2026". Rule-level (a milestone gate). | Recommended: yes. | answered by James, 14 Nov 2026: not passed yet; the remaining refused features are translated first (Open decisions) |
| 2 | Preprocessing timed against GAMS (13 Nov; the ratios in `esma-ie/timesjl-unpublished`) passes the gate. | Yes (James, 14 Nov 2026). | answered in the chat before the PR |
| 3 | After the gate: refused features and the stepped solve on v4.9.7 first, then the move to v4.9.8? Rule-level (`CLAUDE.md` Baseline). | Recommended: features first, then v4.9.8. | answered by James, 14 Nov 2026: features first; the v4.9.8 reference batch after they are translated and tested. Moved from Open decisions, 14 Nov 2026 (also under Decisions in the chat) |
| 4 | Two stale rows leave the list of untranslated paths in docs/gams-julia-map.md (`bnd_flo.mod` L34-39 under REDUCE, translated in change 17b; POWERFLO, translated in changes 27a-27b-2), and the QA-log open item of docs/m13-plan.md is closed. | Built in. | accepted by merge, 14 Nov 2026 |

### #108 M1.4 (7): initmty.mod L442-444, the controls of restart and stepped runs, crafted case demo12_step (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the new crafted case demo12_step (demo12 with TIMESTEP 20; CC BY 4.0; an input fixture of about 1 MB, no matrix or solution fixture yet)? | Recommended: yes; it is the open case for the stepped solve too. | accepted by merge, 14 Nov 2026 |
| 2 | The DD reader no longer stops on a run file that sets SPOINT, TIMESTEP or FIXBOH: the three checks of L442-444 are translated. | Built in. | accepted by merge, 14 Nov 2026 |
| 3 | Start the stepped solve (solve.stp, M1.5) before the M1.3 and M1.4 gates close? Rule-level (milestone order). | Recommended: yes, after the M1.3 gate PR. | answered by James, 14 Nov 2026: yes, the myopic run tests may start before the M1.3 and M1.4 gates close. Moved from Open decisions, 14 Nov 2026 (also under Decisions in the chat) |

### #107 M1.3 (29): coef_obj.mod L31-32, the control switch ANNCOST LEV, crafted cases demo12_lev and demo12_levstd (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the two new crafted cases demo12_lev and demo12_levstd (CC BY 4.0, public fixtures, about 7 MB each)? | Recommended: yes, both; one case cannot reach both branches of L32. | accepted by merge, 14 Nov 2026 |
| 2 | The refusal of ANNCOST LEV is lifted: the two lines are translated and checked on the two cases. | Built in. | accepted by merge, 14 Nov 2026 |
| 3 | ACL and RPT_OPT('OBJ','2') are set now although only the reports (M1.6) read them: they are state at the coef and pre-solve checkpoints. | Built in. | accepted by merge, 14 Nov 2026 |

### #106 M1.3 (28): eqashar.vda L16-33 and the exchange and storage branches of EQ(l)_ASHAR, crafted case demo12_ashar (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the new crafted case demo12_ashar (CC BY 4.0, a public fixture)? | Recommended: yes. | accepted by merge, 14 Nov 2026 |
| 2 | The refusals of FLO_ASHAR data and of ASHAR rows of exchange and storage processes are lifted: the statements are translated and checked on demo12_ashar. | Built in. | accepted by merge, 14 Nov 2026 |
| 3 | eqashar.vda L24 and the first index 'ACT' (L73-74) are translated but reached by no case (demo12 has no standard process without an activity variable; FLO_SHAR input cannot give the index): refuse them instead? | Recommended: leave translated. | accepted by merge, 14 Nov 2026 |

### #105 M1.3 (25-4 follow-up): bnd_cum.mod L12-38 in full, crafted case demo12_cumc (merged 2026-11-14)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the new crafted case demo12_cumc (CC BY 4.0, a public fixture)? | Recommended: yes. | accepted by merge, 14 Nov 2026 |
| 2 | The refusal of FLO_CUM/COM_CUM records with FX, N or negative values is lifted: the statements are translated and checked on demo12_cumc. | Built in. | accepted by merge, 14 Nov 2026 |

### #104 M1.3 (23, #68): crafted case demo12_mrkx, the export term of EQ(l)_FLOMRK (merged 2026-11-13)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the new crafted case demo12_mrkx (CC BY 4.0, a public fixture)? | Kept. | accepted by merge, 13 Nov 2026 |
| 2 | From #68 (asked 8 Nov 2026): a demo12 variant with trade between regions, to check the export term of EQ(l)_FLOMRK: now, or before the M1.3 gate? | Before the gate: this case. | answered by James, 12 and 13 Nov 2026 (chat); accepted by merge, 13 Nov 2026 |

### #103 M1.3 (27b-2): powerflo.vda EQ_GR_GENALL, EQ_GR_DEMALL and the IREAUX terms (merged 2026-11-13)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Keep the new crafted case demo12_pfd (a second grid node in REG1; CC BY 4.0, a public fixture)? | Kept. | accepted by merge, 13 Nov 2026 |
| 2 | The "aggregate for withdrawals" branch of EQ_GR_DEMALL (L336-338) is translated but never reached (GR_DEMFR input data is still refused): refuse it instead? | Left translated; checked when that data is translated. | accepted by merge, 13 Nov 2026 |

### #102 Dashboard 12 Nov: cuOpt slide, key dates, chain 14/14, probe 490/490 (merged 2026-11-12)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | cuOpt results on the public board? | No: on the local board until 23 Nov 2026 (the slide is kept in commit 920b00b). | James, 12 Nov 2026 |
| 2 | The chain slide shows the open scenarios only? | Yes. | James, 12 Nov 2026 |

### #101 M1.6 (#97, early): write_solution, the solution as a TIMES.jl dump (merged 2026-11-12)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Merge the early start of #97, so `run_dd.jl --solve` writes the solution for downstream tools? | Merged; the early start itself was approved on 12 Nov 2026. | James, 12 Nov 2026 (chat); accepted by merge, 12 Nov 2026 |
| 2 | A zero marginal is written as 0, not as GAMS's EPS (outputs are not a parity layer until M1.6 proper). | As built. | accepted by merge, 12 Nov 2026 |

### #99 M1.3 (27a-2 fix): powerflo.vda L80-81 keeps EPS in the grid merge (merged 2026-11-12)

No decisions: a parity fix inside 27a-2 (#93).

### #96 Decision log: docs/decisions.md, backfilled from #21-#95; the rule in CLAUDE.md (merged 2026-11-13)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | The decision-log rule in `CLAUDE.md` | Yes. | James, 11 Nov 2026 |
| 2 | The open decisions: four rule-level ones approved only by merge (#35, #54, #61, #91) and nine never answered | Yes to the four; the rest to be reviewed with James (Open decisions). | James, 11 Nov 2026 |

### #94 Suite: the other eight JRC-EU-TIMES WIMBY scenarios (merged 2026-11-11)

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
| 2 | K2 recorded as approved from the merge of #91: right? | Approved explicitly. | James, 11 Nov 2026 (#96) |
| 3 | Leave issue #87 open only for attributes (`V.UP(i) = 1`)? | Left open for that. | accepted by merge, 11 Nov 2026 |

### #91 M1.4 (5): from DD files to the solved model, with no GAMS state; alias fix (merged 2026-11-10)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Approve K2 in `docs/known-differences.md`? | Approved. | James, 11 Nov 2026 (#96) |
| 2 | Nightly HiGHS solves for demo12, OTCGEN, OTNYC; TIMES-NZ and OTUS9r stop at the matrix? | As proposed; the full TIMES-NZ solve is run by hand. | accepted by merge, 10 Nov 2026 |
| 3 | Alias fix in `gset` (a stale copy of PYR) | Fixed, with a unit test. | accepted by merge, 10 Nov 2026 |

### #90 cuOpt nightly on: GPU-share sweep on GitHub, local nightly in WSL2 (merged 2026-11-10)

| # | Question | Decided | How |
| --- | --- | --- | --- |
| 1 | Set up the GitHub T4 runner for the nightly | Nightly on a GitHub T4 runner (`CLAUDE.md`, cuOpt lane). | James, 10 Nov 2026 |
| 2 | Wednesday's full suite: set `CUOPT_FIXTURES=all` and `CUOPT_GPU_SHARES=100`? | Not known whether set. | open |
| 3 | Which other outcomes turn the nightly red? | Not decided. | open |
| 4 | GPU scaling: release asset of open core-model references, or native Linux? | Release asset: the open reference runs as pre-release assets, solved on the GitHub GPU runner, at 100% first (#189). | James, 22 Nov 2026 (chat, q1 and q2) |

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
| 1 | A demo12 variant with trade to check the EXP term: now, or before the gate? | Keep the test case and get it working soon (James, 12 Nov 2026), before the M1.3 gate (13 Nov 2026): crafted case demo12_mrkx. | answered by James in the chat, 12 Nov 2026; the case came in #104 (merged 13 Nov 2026). Moved from Open decisions, 14 Nov 2026 |

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
| 1 | Accept one-way cross-evaluation as OTUS9r's layer 3 for the M1.3 gate? | Yes (`CLAUDE.md`, Validation). | James, 11 Nov 2026 (#96) |

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
| 1 | Allow LP-identical data-structure fixes before M1.7? | Yes: allowed when the generated LP stays identical (`CLAUDE.md`, Phase 1 rules). | James, 11 Nov 2026 (#96) |

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
| 1 | Refuse blending data and translate only the REFUNIT default, or add a blending test model? | Refused; no blending test model. | accepted by merge, 5 Nov 2026; reversed by James on 14 Nov 2026 (#121, decision 2): the refusal is lifted, with the crafted case demo12_blnd |

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
| 1 | A speed-up in shared code during Phase 1, with the same record order? | Yes: allowed when the generated LP stays identical (`CLAUDE.md`, Phase 1 rules). | James, 11 Nov 2026 (#96) |

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
