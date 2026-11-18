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

  Set `meta.host` to `"workstation"` in both copies before committing. Now:
  37 fixture runs, 1048 checks, all pass (16 Nov 2026). With more than 20 CI
  runs, slide 6 shows them in two panels and the seven coefficient files of
  layer 1 in one cell per run (the tooltip lists the files).

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
  the five core models.

  The workstation batch writes two reports of the seven public runs at each
  pass, `dashboard-public-solve-<stamp>.json` (demo12, OTCGEN gc_ref, OTNYC
  s1_nyc_ref, solved with HiGHS) and `dashboard-public-nosolve-<stamp>.json`
  (TIMES-NZ steady and shift, OTUS9r reference and tax1_wo_mou, layer 3 by
  cross-evaluation), in `timesjl-reference/_probes`. The morning's dashboard
  update embeds the newest finished pass as `report-suite-<mmdd>-solve` and
  `report-suite-<mmdd>-nosolve`, in place of the blocks of the pass before,
  with `meta.host` set to `"workstation"`; the files themselves are not
  committed. Now embedded: `report-suite-1117-solve` and
  `report-suite-1117-nosolve`, the pass of 17 Nov 2026 on main 3114b67
  (to #145): 281 checks, all pass. They supersede the reports above for all
  seven runs.

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
    (`scripts/m13_gate.jl --from-dd`): the seconds the gate prints for each
    step in the batch's `dd-<model>.log`, and the wall time of the whole run
    (its line `whole run <seconds> s`; James, 14 Nov 2026).
  - Whole run (slide 12): wall time, for both languages. GAMS: the wall time
    of the GAMS job, which also holds the harness's dumps. TIMES.jl: the
    gate's wall timer around the run of one variant, from the end of the run
    before it to its own end. It also holds what is in no part: the checks
    against GAMS at every step, the reading of GAMS's dumps for them and the
    writing and reading of the harness's copy of the input. In the first run
    of a process it also holds the loading and compilation of TIMES.jl. A
    batch made before the timer has no whole-run time for TIMES.jl.
  - Parts: read (GAMS: start-up, compilation and the statements before
    preprocessing; TIMES.jl: reading the DD files), preprocessing (GAMS
    `init_ext` to the end of `ppm_ext`; TIMES.jl input to ppm), coefficients
    (to the SOLVE statement; TIMES.jl ppm to presolve), generation (GAMS
    `resgen`; TIMES.jl `generate!`), solve (GAMS `etsolver`; TIMES.jl
    `optimize!` with HiGHS), reports (GAMS: the statements after the solve).
    The header of `scripts/run_timing.jl` has the detail.
  - A part that was never timed is `null` in the block and reads "not
    measured" on the slide (hover gives the reason); nothing is estimated.
    Today: TIMES.jl's reports (not translated, M1.6), TIMES.jl's whole run
    in a batch made before the gate's wall timer, and any TIMES.jl run with
    CPLEX (Phase 2). "not run" marks the OTUS9r solves, which are checked by
    cross-evaluation instead of a HiGHS solve.
  - GAMS with HiGHS: demo12 and TIMES-NZ steady have the run today. OTCGEN
    and OTNYC get it at the next reference run (`solvers` in
    `reference/suite.toml`; James, 14 Nov 2026), the batch that moves the
    baseline to v4.9.8; their points then appear on slide 11 at the next
    refresh. OTUS9r is left out for now.
  - The first run of each TIMES.jl process also compiles TIMES.jl; it is
    marked `cold` and drawn faint on slide 11. Slide 12 shows the as-run
    variant, which is never the first.
  - Refresh after each nightly batch, before the 9:00 check-in (James,
    14 Nov 2026): a step of the morning's dashboard update, in the same pull
    request as the other blocks of the page. From the repository's folder,
    with `<stamp>` the newest finished pass in `timesjl-reference/_probes`
    (the folder `nightly-parts-<stamp>` and the parity report
    `dashboard-public-solve-<stamp>.json` carry the same stamp; the report
    gives the commit and date):

        julia --project=test scripts/run_timing.jl ../timesjl-reference ../timesjl-reference/_probes/nightly-parts-<stamp> --meta ../timesjl-reference/_probes/dashboard-public-solve-<stamp>.json --embed

    It prints the table of slide 12 and rewrites the `run-timing` block of
    `docs/dashboard/index.html`; nothing else in the page changes. Only
    models with `redistribute = "public"` are read, and `--embed` refuses
    anything else. `--all` and `--local` (with `--out <file>`) read the other
    models for a board that stays on the workstation; the batch refreshes
    that board itself at the end of each pass. The output holds no path, host
    name or log line.

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

Languages and solvers (James, 14 and 15 Nov 2026): the colour is the
language and the shape is the solver, wherever a slide draws them.

- GAMS is orange, `#e06000`, on light and dark slides. TIMES.jl is ESMA
  Dark green `#004539` on light slides and ESMA Dark yellow `#eaaa00`
  ("sunshine yellow") on dark slides (James, 15 Nov 2026: "ESMA orange for
  GAMS and ESMA sunshine yellow for the TIMES.jl on a green background and
  ESMA green if on a light background"). The brand book has no orange.
  ESMA's technology palette has one, `#ff6a1f`, but beside the yellow on the
  dark slides it falls under the normal-vision floor, so the board keeps
  `#e06000`. The hex values are on the Open decisions list until James
  confirms them (`docs/decisions.md`). Slides 10, 11 and 12 use the colours;
  slide 10's 5x target line is Dark yellow on light slides and white on
  dark slides, so that it is never read as a TIMES.jl mark.
- CPLEX is a circle; HiGHS is an isosceles triangle pointing up. Slides 9,
  11 and 12 use the two shapes. Every mark is filled.
- Slide 9 (objective) keeps its own colours, the CPLEX blue and the HiGHS
  dark green (white on dark slides): its marks are TIMES.jl's difference
  from a GAMS solve, so they belong to neither language. On light slides
  its HiGHS dark green is TIMES.jl's colour on slides 10 to 12; the two
  never share a slide. Its fail red is close to the orange (colour
  difference 6.5, under the validator's floor of 15), and the two never
  share a slide either.
- Slides 11 and 12: a faint mark is a first run that also compiles TIMES.jl;
  an arrow up marks a solve stopped at its time limit without an optimum (it
  took at least that long); a thin line joins the runs of one LP. On slide
  11 a callout label names each model-scenario pair, with a leader line to
  the top mark of each of its two LPs (James, 15 Nov 2026); the as-run LP
  has fewer columns, so it is the left one. The labels are stacked in the
  widest empty band of the x axis, in the order of their marks' height. On slide
  11's left panel each language has the mark of the run its time comes from
  (GAMS its CPLEX run, TIMES.jl its HiGHS run). On slide 12 the shading of a
  cell is the part's share of the run's measured time.
- The checks of the `dataviz` palette validator, computed for the pair on
  15 Nov 2026 (OKLab difference x100, Machado simulation):
  - Light slides (white), orange and Dark green: normal vision 37.0;
    protanopia 21.7, deuteranopia 33.8, tritanopia 40.4 (target 8);
    contrast with white 3.59:1 and 10.99:1 (at least 3:1).
  - Dark slides (Dark green), orange and Dark yellow: normal vision 17.2
    (floor 15); protanopia 18.5, deuteranopia 13.5, tritanopia 16.4;
    contrast with the surface 3.06:1 and 5.36:1. With `#ff6a1f` instead:
    normal vision 14.6 (under the floor) and deuteranopia 7.3.
  - The legends and slide 12's table name the language as well, so no
    reading depends on colour alone.
