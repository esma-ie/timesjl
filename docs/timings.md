# Model-generation timings, TIMES.jl against GAMS

The translation guide's definition of done asks for timings logged against
GAMS; the Phase 1 target is model generation (preprocessing to solver
hand-off) no worse than 5x GAMS, warm, at M1.7, measured on one machine.
Produced with `scripts/m11_timing.jl` (see its header for what each column
means).

From 29 Oct 2026 local runs on James's workstation keep to the run limits in
`CLAUDE.md` (at most 12 threads per run, at most 4 heavy runs at a time).
Timings made before then used each solver's own setting (GAMS default: one
solver thread) and are not directly comparable with later ones.

## M1.3 preprocessing, 13 Nov 2026, same machine (James's workstation)

The figures the M1.3 gate closes on, taken after the last translation change
of the M1.3 plan (27b-2, #103). Same script and method as the 5 Nov section
below (`scripts/m13_timing.jl`, warm, one thread, against the GAMS profile of
each model's CPLEX reference solve; GAMS 54.6.1, Julia 1.13.2).

| Model (reduce_off) | init_ext | ppmain | ppm_ext | Total, TIMES.jl warm | Total, GAMS | Ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| TIMES_Demo-demo12 | 0.014 | 0.181 | 0.016 | 0.21 s | 0.062 s | 3.4 |
| TIMES-NZ-steady-v308 | 0.034 | 7.149 | 0.568 | 7.8 s | 1.39 s | 5.6 |
| OTCGEN-gc_ref | 0.251 | 48.90 | 8.230 | 57.4 s | 9.11 s | 6.3 |
| OTNYC-s1_nyc_ref | 0.422 | 17.66 | 1.911 | 20.0 s | 3.69 s | 5.4 |
| OTUS9r-reference | 2.683 | 105.2 | 9.434 | 117.3 s | 20.8 s | 5.6 |

TIMES.jl seconds per part (warm). The GAMS column is the same profile as on
5 Nov; the TIMES.jl totals are 8% to 16% higher. Two things differ from
5 Nov and the run does not separate them: the code now writes the QA log and
makes its checks (change 25b), and the workstation batch was running beside
the timing run (within the run limits). The slowest steps are the same as on
5 Nov: pp_prelv (OTUS9r 24.1 s, OTCGEN 9.8 s), ppmain_flofs (OTCGEN 14.9 s),
ppmain_reduce, ppmain_life and ppm_ext_actef; on TIMES-NZ ppmain_tsattr
(3.3 s).

Gate decision (James, 14 Nov 2026): 3.4 to 6.3 times GAMS is close enough to
pass the M1.3 gate. The gate asks for preprocessing to be timed against
GAMS; the 5x target is for the whole of model generation at M1.7, and no
performance work has been done on preprocessing.

## M1.3 preprocessing, 5 Nov 2026, same machine (James's workstation)

The M1.3 gate figures of 5 Nov (changes 0-18b). `scripts/m13_timing.jl`: the preprocessing chain from
the input dump (TIMES.jl's state carried across the checkpoints, the
carrying not timed), first pass with compilation, then warm, against the GAMS
profile of the same lines in each model's CPLEX reference solve
(`raw/tjl_solve_cplex_profile.txt`; the harness's checkpoint unloads left
out): init_ext (maindrv.mod L55), ppmain.mod with prep_ext.vda and
pp_prelv.vda (L56), ppm_ext (L58). James's workstation (2x Intel Xeon Gold
6256, Windows 11 Pro for Workstations), under the run limits; GAMS 54.6.1,
Julia 1.13.2, one thread; the 17b/gate branch (changes 0-18b).

| Model (reduce_off) | init_ext | ppmain | ppm_ext | Total, TIMES.jl warm | Total, GAMS | Ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| TIMES_Demo-demo12 | 0.010 | 0.162 | 0.014 | 0.19 s | 0.062 s | 3.0 |
| TIMES-NZ-steady-v308 | 0.029 | 6.567 | 0.568 | 7.2 s | 1.39 s | 5.2 |
| OTCGEN-gc_ref | 0.224 | 43.44 | 6.261 | 49.9 s | 9.11 s | 5.5 |
| OTNYC-s1_nyc_ref | 0.435 | 16.38 | 1.250 | 18.1 s | 3.69 s | 4.9 |
| OTUS9r-reference | 2.539 | 90.60 | 7.745 | 100.9 s | 20.8 s | 4.8 |

TIMES.jl seconds per part (warm). The slowest steps (warm): pp_prelv
(OTUS9r 23.3 s, OTCGEN 9.0 s), ppmain_flofs (OTCGEN 13.6 s), ppmain_life,
ppmain_reduce and ppm_ext_actef; on TIMES-NZ ppmain_tsattr (3.1 s). On the
large models the first pass and the warm pass take about the same time. The
GAMS profile counts in steps of 1/64 s, so demo12's ratio is rough. Unlike
the coefficient stage (75x to 359x, below), preprocessing is near the
Phase 1 target of 5x without any performance work.

## M1.2 coefficient stage, 31 Oct 2026, same machine (James's workstation)

The M1.2 figures of record. `scripts/m12_timing.jl` as in the section below,
both sides on James's workstation (2x Intel Xeon Gold 6256, Windows 11 Pro
for Workstations), under the run limits:

- GAMS: GAMS 54.6.1 (licensed), the profile of each model's CPLEX reference
  solve (`raw/tjl_solve_cplex_profile.txt`, written 30 Oct 12:13 to 31 Oct
  00:04 and kept by the weekend batch's `-Resume`, being GAMS 54 already).
  TIMES.jl was timed on 31 Oct by `run_weekend_gams54_v2.ps1`.
- TIMES.jl: Julia 1.13.2, one thread (`JULIA_NUM_THREADS` unset; the log's
  "48 threads" is `Sys.CPU_THREADS`, the machine's logical cpus), main at
  a7bff7f.
- Log: `C:\git\esma\timesjl-reference\_probes\weekend-m12timing-public-2026-10-31-1128.log`.

| Model (reduce_off) | Rows | coef_cpt | coef_ptr | coef_obj | coef_alt | coef_shp | coef_ext | Stage, TIMES.jl warm | Stage, GAMS | Ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| TIMES_Demo-demo12 | 8,695 | 0.251 | 0.039 | 0.415 | 0.103 | 0.086 | 0.236 | 1.13 s | 0.015 s | 75 |
| TIMES-NZ-steady-v308 | 1,408,361 | 90.61 | 1.721 | 2.950 | 6.588 | 5.929 | 57.40 | 165.2 s | 0.98 s | 168 |
| OTCGEN-gc_ref | 1,257,132 | 114.0 | 433.5 | 77.22 | 0.116 | 39.58 | 541.9 | 1,206.3 s | 3.36 s | 359 |
| OTNYC-s1_nyc_ref | 504,698 | 28.30 | 41.70 | 18.71 | 0.008 | 7.734 | 78.63 | 175.1 s | 1.02 s | 172 |
| OTUS9r-reference | 2,174,010 | 216.0 | 325.5 | 67.95 | 69.87 | 70.00 | 413.4 | 1,162.7 s | 5.44 s | 214 |

TIMES.jl seconds per file (warm; coef_nio is 0.001 s or less, and 0 in
GAMS). The GAMS profile on Windows counts in steps of 1/64 s (15.6 ms, the
system timer): demo12's whole stage is one step, so its ratio is rough; the
large models span 60 to 350 steps. On the large models the first pass and
the warm pass take about the same time (compilation is small next to the
data handling), and coef_ext, coef_ptr and coef_cpt lead, as on the cloud
workspace below. TIMES-NZ shift (milestone tier) was not timed.

## M1.2 coefficient stage, 31 Oct 2026 (indicative: same machine, the cloud workspace; superseded by the section above)

`scripts/m12_timing.jl`: each coefficient file of TIMES.jl on the ppm dump
(first pass with compilation, then warm), against the GAMS profile of the
same coefficient stage summed over each file's listing lines (nested
includes with their file; the harness's dumps left out). Both sides on one
machine, the cloud workspace (Linux, 2 cpus, 8 GB): GAMS 54.6.1 from PyPI
(the pre-solve run of `make_reference.py --only presolve`, demo licence: no
solve needed), Julia 1.13.3, main at 6ac29e4. Both sides run this stage on
one thread. The workstation measurement (the M1.2 gate's) is the section
above.

| Model (reduce_off) | coef_cpt | coef_ptr | coef_obj | coef_alt | coef_shp | coef_ext | Stage, TIMES.jl warm | Stage, GAMS | Ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| TIMES_Demo-demo12 | 0.165 | 0.023 | 0.282 | 0.044 | 0.055 | 0.151 | 0.72 s | 0.016 s | 45 |
| OTNYC-s1_nyc_ref | 17.95 | 30.61 | 13.50 | 0.004 | 5.05 | 51.98 | 119.1 s | 0.79 s | 152 |

TIMES.jl seconds per file (warm; coef_nio is 0 on both). On OTNYC
(504,698 rows) the stage takes two minutes against under a second in GAMS:
coef_ext (52 s against 0.15 s), coef_ptr (31 s against 0.22 s) and
coef_cpt (18 s against 0.22 s) lead. It is the same data-handling cost as
the M1.1 generators (docs/phase2-notes.md: string-tuple keys, untyped
caches, per-record dictionaries), at a larger scale: against the Phase 1
target (generation incl. preprocessing within 5x GAMS) the coefficient stage
alone is 30 times over. Phase 2 work; nothing in Phase 1 changes for it.
OTCGEN (1.26 M rows) does not fit the workspace's 8 GB.

## M1.1, 21 Oct 2026, same machine (James's workstation)

Both sides on one machine: 2x Intel Xeon Gold 6256 (24 cores, 48 threads,
3.6 GHz), 767 GB, Windows 11 Pro for Workstations.

- GAMS: GAMS 52.1.0, the licensed reference runs of 21 Oct (CPLEX solve:
  profile and log), as in the indicative section below.
- TIMES.jl: Julia 1.13.2 (juliaup, one thread), JuMP 1.32.1,
  MathOptInterface 1.54.0, HiGHS 1.26.1, a pre-publication commit of 21 Oct 2026 (the public history starts on 30 Oct); warm = second build
  in the same process. Built from the GAMS pre-solve dump, so preprocessing
  is not included on this side (M1.3).
- Logs: `C:\timesjl-work\m11_timing.log`; the same run's
  `m11_probe.log` passes layers 2 and 3 on demo12.

| Model (reduce_off) | Rows | GAMS compile | GAMS execution to hand-off | GAMS equations + Solve Fini | TIMES.jl generation incl. bounds, warm | Ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| TIMES_Demo-demo12 | 8,695 | 0.32 s | 0.21 s | 0.07 s | 0.43 s | 6.8 |

Large-model timings (a generator-by-generator breakdown on a model of about
a million rows) were measured on TIM, which is local to James's machine; its
figures are not recorded in this repository (CLAUDE.md, Test-model licences)
and are to be measured again on an open model of that size (TIMES-NZ, OTUS9r
or JRC-EU-TIMES). On demo12, generation alone is 2.0x GAMS's whole execution
to hand-off.

## M1.1, 21 Oct 2026 (indicative: two machines; superseded by the section above)

- GAMS: James's machine (Windows 11, 48 cpus), GAMS 52.1.0, the licensed
  reference runs of 21 Oct (CPLEX solve: profile and log).
- TIMES.jl: the cloud workspace (Linux, 2 cpus Xeon 2.8 GHz, 8 GB), Julia
  1.13.2, JuMP 1.32.1, MathOptInterface 1.54.0; warm = second build in the
  same process. Built from the GAMS pre-solve dump, so preprocessing is not
  included on this side (M1.3).

| Model (reduce_off) | Rows | GAMS compile | GAMS execution to hand-off | GAMS equations + Solve Fini | TIMES.jl generation incl. bounds, warm | Ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| TIMES_Demo-demo12 | 8,695 | 0.32 s | 0.21 s | 0.07 s | 0.51 s | 8.1 |

The same-machine measurement above replaces these figures.
