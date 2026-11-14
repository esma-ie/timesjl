# Parity dashboard

`index.html` is the TIMES.jl parity board: twelve 16:9 slides in the ESMA brand
(DM Sans, Dark Green and Dark Yellow, the ESMA logo). Each slide follows the
usual ESMA slide layout: a title and one-line message, a Dark Yellow accent
line, then the chart, with the source in the footer.

1. at a glance: headline figures and the milestones;
2. translation coverage by stage of the GAMS code;
3. the M1.3 changes, by status;
4. the M1.3 chain from GAMS's input dump to the pre-solve point;
5. the M1.3 probe, step by step;
6. parity by run, CI test cases (layers 1-3);
7. parity by run, public reference models;
8. equation families against GAMS's matrix;
9. objective agreement;
10. coefficient-stage time against GAMS;
11. run time against model size: seconds against the number of variables in
    the LP, both on log scales, in two panels (input files to the LP, and the
    solve), one point per model-scenario pair, variant, language and solver;
12. where the time goes: the seconds of each part of a run (read input,
    preprocessing, coefficients, generation, solve, reports), one row per
    model-scenario pair, language and solver.

## Slides for a deck

Every slide is drawn on a fixed 1280 x 720 canvas and scaled as a whole, so
it fits a Google Slides page (10 x 5.625 in) exactly. Labels are at least
14 px on that canvas.

- One slide alone: open `index.html#slide=N` (add `&theme=dark` for
  dark-green slides).
- All slides as PNGs at 2560 x 1440 (headless Chrome or Edge):

      powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dashboard_png.ps1

  They go to `timesjl-slides`, beside the repository (`-Out` to change). In
  Google Slides: Insert > Image > Upload from computer, and size it to the
  page.
- Print to PDF gives one slide per page.

The ESMA logo is the official RGB artwork ("On White Background" on light
slides, "Primary" on dark ones), embedded unaltered. It is ESMA's mark
(c) ESMA and is not covered by the repository's GPL licence.

## Data

- `demo12.json`: the parity report of the public fixtures
  (`test/fixtures/public_fixtures.toml`), written by
  `scripts/parity_report.jl`. One record per check: layer (1 coefficient file,
  2 equation family or whole matrix, 3 GAMS solver), status (pass, fail,
  refused, skipped), records compared and excluded, mismatches, seconds; plus
  the run (model, variant, licence, matrix size) and the commit. No model
  data.
- The same report is embedded in `index.html` (`--embed`), so the page works
  opened as a file. Refresh both after a change that touches parity:

      julia --project=test scripts/parity_report.jl docs/dashboard/demo12.json --embed

- `suite-public*.json`: parity reports of the reference runs of the public
  suite models (`redistribute = "public"` in `reference/suite.toml`), made on
  James's workstation from `timesjl-reference` and embedded in the page's
  `report-suite*` blocks (the embedding refuses any run that is not
  `redistribute = "public"`). A probe of the core tier's public models
  (`tier = "core"`):

      julia --project=test scripts/parity_report.jl docs/dashboard/suite-public-core.json --embed-as report-suite-core --ref ../timesjl-reference --root otus=../timesjl-sources/OTUS9r --root times_nz_dd=../timesjl-sources/TIMES-NZ --root otcgen=../timesjl-sources/OTCGEN --root otnyc=../timesjl-sources/OTNYC TIMES_Demo-demo12 TIMES-NZ-steady-v308 OTUS9r-reference OTCGEN-gc_ref OTNYC-s1_nyc_ref

  Each probe run gets its own file and block (`suite-public-<name>.json`,
  `report-suite-<name>`, `--embed-as report-suite-<name>`). The page merges
  every `report*` block: where several reports carry a run, the newest
  (`meta.date`) wins, so a run not probed again keeps its last result, and
  the header lists the commits and dates of the reports in use. Before
  committing a report, set `meta.host` to `"workstation"` (the script records
  the machine name). The reports now embedded:

  | File | Block | Runs | Commit, date (UTC) |
  | --- | --- | --- | --- |
  | `suite-public.json` | `report-suite` | demo12, TIMES-NZ steady and shift, OTUS9r reference and tax1_wo_mou | a8c17bd (pre-publication history), 30 Oct 05:51 |
  | `suite-public-core.json` | `report-suite-core` | demo12, TIMES-NZ steady, OTUS9r reference (core tier) | 6f3d91e, 30 Oct 20:03 |
  | `suite-public-otc.json` | `report-suite-otc` | OTCGEN gc_ref, OTNYC s1_nyc_ref (core tier) | 2fde1e3, 31 Oct 00:12 |
  | `suite-public-weekend.json` | `report-suite-weekend` | demo12, TIMES-NZ steady and shift, OTCGEN gc_ref, OTNYC s1_nyc_ref, OTUS9r reference, on the GAMS 54 references (`run_weekend_gams54_v2.ps1`) | a7bff7f, 31 Oct 13:48 |

  | `suite-public-m13.json` | `report-suite-m13` | demo12, TIMES-NZ steady, OTCGEN gc_ref, OTNYC s1_nyc_ref (core tier, after M1.3 changes 17b-20b-4) | 9df68b2, 7 Nov 10:54 |
  | `suite-public-otus.json` | `report-suite-otus` | OTUS9r reference (core tier), layer 3 by cross-evaluation (`--no-solve`) | 9df68b2, 7 Nov 10:54 |

  `src/` is the same at 6f3d91e and 2fde1e3. The weekend report supersedes
  the earlier ones for its six runs, and the 7 Nov reports supersede it for
  the five core models (TIMES-NZ shift keeps its 31 Oct result). OTUS9r
  tax1_wo_mou (milestone tier, paused) shows its 30 Oct 05:51 result until a
  milestone run probes it again.

  `--no-solve` records layer 3 without the HiGHS solve: each GAMS optimum
  cross-evaluated in TIMES.jl's model (objective, and feasibility as in
  GAMS's own matrix), as `scripts/m13_cross_eval.jl` does. It is used for
  OTUS9r, which HiGHS does not solve in reasonable time (docs/m13-plan.md,
  finding 20b-4):

      julia --project=test scripts/parity_report.jl docs/dashboard/suite-public-otus.json --no-solve --ref ../timesjl-reference --root otus=../timesjl-sources/OTUS9r OTUS9r-reference

- Run timings (slides 11 and 12): the `run-timing` block of `index.html`,
  written by `scripts/run_timing.jl`. It runs nothing: every number is read
  from output that exists on James's workstation (runs under the local run
  limits, at most 12 threads each).
  - GAMS, one entry per solve run of a GAMS 54 reference: the run's wall time,
    the LP's size, GAMS's generation time (`resgen`) and solver time
    (`etsolver`) from `manifest.json`, and the other parts from the run's
    profile (`raw/tjl_solve_<solver>_profile.txt`, seconds per statement),
    cut at the files of the Include File Summary. Only numbers are read; no
    line of a listing or log is copied.
  - TIMES.jl, one entry per model and variant of a workstation batch
    (`scripts/m13_gate.jl --dd`): the seconds the gate prints for each step
    in the batch's `dd-<model>.log`.
  - Parts: read (GAMS: start-up, compilation and the statements before
    preprocessing; TIMES.jl: reading the DD files), preprocessing (GAMS
    `init_ext` to the end of `ppm_ext`; TIMES.jl input to ppm), coefficients
    (to the SOLVE statement; TIMES.jl ppm to presolve), generation (GAMS
    `resgen`; TIMES.jl `generate!`), solve (GAMS `etsolver`; TIMES.jl
    `optimize!` with HiGHS), reports (GAMS: the statements after the solve).
    The header of `scripts/run_timing.jl` has the detail.
  - A part that was never timed is `null` in the block and reads "not
    measured" on the slide (hover gives the reason); nothing is estimated.
    Today: TIMES.jl's reports (not translated, M1.6), TIMES.jl's whole run,
    and any TIMES.jl run with CPLEX. "not run" marks the OTUS9r solves, which
    are checked by cross-evaluation instead of a HiGHS solve.
  - The first run of each TIMES.jl process also compiles TIMES.jl; it is
    marked `cold` and drawn faint on slide 11. Slide 12 shows the as-run
    variant, which is never the first.
  - Refresh after a new batch (the reference directory, then the batch's log
    folder and its parity report for the commit and date):

        julia --project=test scripts/run_timing.jl ../timesjl-reference ../timesjl-reference/_probes/nightly-parts-<stamp> --meta ../timesjl-reference/_probes/dashboard-public-solve-<stamp>.json --embed

    Only models with `redistribute = "public"` are read, and `--embed`
    refuses anything else. `--all` and `--local` (with `--out <file>`) read
    the other models for a board that stays on the workstation. The output
    holds no path, host name or log line.

- Local runs (TIM, on James's machine) are reported the same way from a
  reference directory and loaded into the open page with its "Load results
  JSON" button; those files hold counts and statuses only and are not
  committed:

      julia --project=test scripts/parity_report.jl tim.json --ref ../timesjl-reference TIM-bau TIM-mitigation_cb2024-300mt TIM-mitigation_cb2024-300mt-myopic

- The pipeline (GAMS files and their status), the milestones, the M1.3
  changes and their probe results, the M1.3 chain (`M13_GATE`, from
  `scripts/m13_gate.jl`), the coefficient-stage timings (M1.2,
  workstation) and the suite's models not yet reported are written into the
  page by hand (`PIPELINE`, `MILESTONES`, `M13_CHANGES`, `M13_NOTE`, `M13_GATE`, `M13_PROBE`,
  `TIMINGS`, `PLANNED_RUNS` in its script); update them when a file is
  translated, a change merges, a gate passes, `scripts/m13_probe.jl` is run
  on the core tier, `docs/timings.md` changes or the suite changes.
  `M13_PROBE` holds the GAMS records each probe step compares (counts only).
  Only open models go in `TIMINGS` and `M13_PROBE`: TIM's results stay on
  James's machine.

## Encoding

Status: green pass, red fail, charcoal refused (an untranslated path: TIMES.jl
stops with a message), striped Dark Yellow in review, dashed outline not run
or not started. Numbers in cells are the records compared at 1e-9 (layers
1-2, and GAMS records per probe step) or the relative objective difference
(layer 3). A Dark Yellow underline marks records left to a later coefficient
file (`later_overwrites`). Objective slide: CPLEX and HiGHS references on a
log axis against the 1e-6 gate. Timing slide: the GAMS profile of the
coefficient stage against TIMES.jl, warm, with the Phase 1 5x target.

Run-time slides (11 and 12): the language is the colour and the shape (GAMS
a blue circle, TIMES.jl a green square), the solver is the fill (CPLEX
filled, HiGHS a ring). A faint square is a first run that also compiles
TIMES.jl; an arrow up marks a solve stopped at its time limit without an
optimum (it took at least that long); a thin line joins the runs of one LP.
The two colours pass the colour-vision checks of the `dataviz` palette
validator on both surfaces (the green is one step darker on dark slides);
the legend and slide 12's table carry the same information without colour.
On slide 12 the shading of a cell is the part's share of the run's measured
time.
