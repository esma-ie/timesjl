# Phase 2 notes

Things learnt in Phase 1 that belong to Phase 2 (performance and numerical
robustness). Phase 1 changes none of them unless a parity check needs it.

## Backlog

| # | Item | Raised | Notes |
| --- | --- | --- | --- |
| P2-1 | Tighter solver and parity tolerances | 21 Oct 2026, James (with K1) | 1e-6 is loose for optimality. Run the GAMS references with tighter CPLEX tolerances (feasibility and optimality, e.g. `eprhs`/`epopt` 1e-9) and HiGHS likewise, then tighten the layer-3 cross-evaluation and retire K1's "as feasible as in its own LP" rule (scripts/m11_probe.jl `as_feasible_as`). |
| P2-2 | Coefficient-stage speed | 31 Oct 2026 (M1.2 timings) | On OTNYC (0.5 M rows) the coefficient stage takes 119 s warm against 0.79 s in GAMS on one machine (docs/timings.md); coef_ext, coef_ptr and coef_cpt lead. The same data access as the slow generators (below): string-tuple keys, per-record dictionaries; integer labels and columnar sets would serve both. |
| P2-3 | Multi-threaded equation generation | 31 Oct 2026, James | A JuMP model is built on one thread, so thread the work around it: index construction and coefficient arithmetic per equation family (or region) on separate tasks, each into its own buffer; then add the rows on one thread, or merge the buffers into one triplet matrix for a single hand-off to the solver. Needs the data fixes first (concrete types, integer labels). Details in "Multi-threaded equation generation (P2-3)" below. |
| P2-4 | GPU solving (NVIDIA cuOpt) | 9 Nov 2026, James | cuOpt 26.10 through cuOpt.jl: PDLP and barrier on the GPU, with crossover. In Phase 1 an informational lane only (`scripts/cuopt/`): layer 3 with pinned methods on the public fixtures, nightly on a GitHub T4 runner (`.github/workflows/nightly-gpu.yml`) and in WSL2 on James's workstation (Quadro RTX 4000, 8 GB). Questions for Phase 2: on which models and with which method cuOpt reaches 1e-6 parity faster than HiGHS (OTUS9r first: HiGHS does not solve it in reasonable time, docs/m13-plan.md finding 20b-4), and whether barrier's factorisation fits in GPU memory on the largest models. |
| P2-5 | Schemas for data and equations (Pandera, mathspec): **provisional** | 10 Nov 2026, James | To be confirmed by James before any work starts. Three small pilots, one PR each, none touching generation before M1.7: (a) a schema for every dump symbol, generated from the GAMS declarations `src/dd/compile.jl` parses, checked with Pandera where `gdx2arrow.py` writes the dump; (b) a format 2 dump with integer-coded labels, read without string-tuple keys (serves P2-2 and P2-3); (c) mathspec YAML for `EQ_ACTFLO` and `EQ_COMBAL`, typeset beside Part II and checked against the rows TIMES.jl generates. Details in "Schemas for data and equations (P2-5)" below. |
| P2-6 | The speed target: model generation within 5x GAMS, warm | 17 Nov 2026, James (moved from M1.7) | Preprocessing to solver hand-off no worse than 5x GAMS on one machine, warm. Where it stood when it moved (the ratios, to GAMS's CPLEX runs, are in `esma-ie/timesjl-unpublished`; #184 d6): preprocessing 13 Nov 2026 (docs/timings.md), model generation on OTCGEN (issue #116); the coefficient stage the furthest off (P2-2). P2-2 and P2-3 are the route to it. James, 26 Nov 2026: Phase 2 is complete when this target is met, aimed for Wednesday 2 Dec 2026, "while aiming for 5x faster than GAMS"; the speed work runs alongside the rest of Phase 1, limited to changes that leave the generated LP identical (CLAUDE.md, "Phase 2 lane"). James, 27 Nov 2026 (p2-q1 to p2-q4): the target holds for every open model, TIMES-NZ steady and OTCGEN first; the timed stretch ends at the finished JuMP model; where a model has no GAMS/HiGHS run, GAMS's generation time is taken from its CONVERT run plus its pre-solve run (no solver timed), the method stated; the work starts with change 0, which changes no LP: a bit-for-bit identity check of the LP and of the pre-solve state, a timing script and a warm profile. James, 27 Nov 2026 (#208 d1 to d3): the target covers preprocessing, coefficients and generation together, each stage also reported alone; it is timed on one thread, with the data already in memory (the read time recorded beside it). The first measurement (below, "Change 0") is of the generation step alone and includes the read. |
| P2-7 | Large high-resolution runs as the test bed for model generation and writing to memory | 26 Nov 2026, James | The OTAI scenarios (local only until the model is published; docs/test-models.md) are larger than the models tested so far. Use them to measure and speed up model generation and the build of the model in memory (P2-2, P2-3; direct mode, "Memory" below). Their figures stay on the local board until publication. |

## Model generation: where the time goes (21 Oct 2026)

Measured on a local-only model of about a million rows (TIM, 21 Oct 2026;
its figures are not recorded in this repository, CLAUDE.md), with GAMS on
James's machine; to be measured again on an open model of that size
(TIMES-NZ, OTUS9r or JRC-EU-TIMES). The findings are about TIMES.jl's own
code and hold for any large model: four generators (eq_combal!,
eq_acteff!, eq_floshr!, eq_capact!) take most of the time, each makes
exactly GAMS's rows, and allocation per row is the clearest symptom.

### Profile of the slow generators (CPU samples)

Two data-handling patterns explain most of the time; neither is in the
equations themselves. Both can be fixed without touching what is generated.

1. **Untyped context caches** (most of eq_combal!'s samples). Each generator
   keeps its index maps in `tm.cache::Dict{String,Any}` (`combal_context`,
   `stg_context`, ...). The value comes back as `Any`, so every field access
   in the inner loops (`x.rs_fr`, `x.varf_of_rtpc`, ... in `cal_fflo!`,
   src/model/eqcombal.jl L121-142) is a dynamic lookup on a NamedTuple of
   about 30 fields, and every result is dynamically dispatched and boxed.
   That is where eq_combal! allocates. Fix: a function barrier or
   a concrete type for each context (a struct, or a typed
   `get!(...)::ContextType`).
2. **Sorting rows into GAMS order** (a large share of eq_acteff!,
   eq_floshr! and eq_capact!).
   `gams_sort!` (src/model/gams_data.jl L333-338) sorts string tuples with
   `by = k -> ntuple(i -> rank(k[i]))`; `sort!` calls `by` on every
   comparison, and `rank` lowercases (allocates) each label and looks it up
   in `Dict{String,Int}`: O(n log n) times N string allocations and hashes.
   Fix: map each key once to integer ranks (a `Vector{NTuple{N,Int32}}`) and
   sort that, or keep labels interned as integers throughout (below).

Smaller, everywhere:

3. **String-tuple keys.** Variables are looked up by `NTuple{6,String}` in
   `getvar!` (src/model/mod_vars.jl L159-172): each lookup hashes six
   strings; every parameter value read (`gv`) and every set test hashes
   tuples of strings too. Interning labels as integers (the GDX UEL index)
   at load would make keys bit-tuples, hashing cheap and sorting trivial.
4. **Names.** Every variable and constraint gets a string name
   (`colname`, `@variable base_name`, `addeq!`) for the parity checks; in
   production runs names can be off (`set_string_names_on_creation`), with
   a name map kept outside JuMP for parity mode.
5. **Per-row temporaries.** `gconstraint!` builds a `Dict{VariableRef,Float64}`
   for every row to apply the GAMS rule that rows whose terms cancel are not
   generated (`_all_cancel`), and `JuMP.@constraint(lhs == rhs)` builds a
   new expression from `lhs - rhs`. A single pass on a canonicalised
   expression would do both.
6. **Lazy dump reads inside generators.** The first generator to use a set
   or parameter reads it from Arrow (`read_symbol`), so read time lands in
   whichever generator comes first (usually eq_combal!). Phase 2 can load once, in columnar form, with integer labels.

## Change 0: the measuring tools and the first profile on open models (27 Nov 2026)

Three scripts, none of which changes the LP (James, 27 Nov 2026, p2-q1):

| Script | What it does |
| --- | --- |
| `scripts/p2_identity.jl` | The identity gate of every speed change. It writes a fingerprint of the generated LP (rows, columns, their order, the order of the terms, every coefficient, bound and right-hand side, bit for bit; one hash per equation family) and of the pre-solve state, and `--check` compares a new build with a stored one and names the part that differs. `test/unit/test_p2_identity.jl` proves it on demo12: one coefficient moved to the next Float64, 0.0 against -0.0, one bound, two rows swapped, each gives another fingerprint. |
| `scripts/p2_timing.jl` | Warm generation time, repeated, on a set number of threads, beside GAMS's generation time: `resGen` of the GAMS/HiGHS run where the reference has one, else of the CONVERT run (p2-q3). It opens the CONVERT, pre-solve and GAMS/HiGHS runs only; no run of CPLEX or another Restricted Solver is read. |
| `scripts/p2_profile.jl` | A warm CPU profile of one build, `generate!` statement by statement. |

**First measurement: the generation step only, one thread, provisional.**
The 5x target covers preprocessing, coefficients and generation together,
on one thread (James, 27 Nov 2026, #208 d1 and d2), so these are not P2-6
results. Conditions: `reduce_off`,
from GAMS's pre-solve dump, Julia 1.13.2 on one thread, warmed on demo12 only
(code only the large model reaches is compiled inside the first repeat), two
repeats on OTCGEN and one on TIMES-NZ, other Julia processes running on the
machine, not started through the run pool. TIMES.jl's time includes reading
the dump from Arrow; GAMS's does not (to be taken out of the timed stretch:
#208 d3). GAMS 54.6.1, TIMES v4.9.7,
reference of 30 Oct 2026, `threads=12`.

| | OTCGEN-gc_ref | TIMES-NZ-steady-v308 |
| --- | --- | --- |
| Rows / columns | 1,257,132 / 1,507,223 | 1,408,361 / 1,299,224 |
| TIMES.jl `generate!`, warm | 686 s (the lower of 709 and 686) | 627 s (one build) |
| GAMS generation (`resGen`) | 20.2 s (CONVERT run) | 11.4 s (GAMS/HiGHS run) |
| Ratio, generation step only | about 34 | about 55 |
| Allocated | 338 GiB | 384 GiB |
| Garbage collection | 207 s | 162 s |
| `eq_combal!` | 59% | 91% |
| `eq_peak!` | 25% | 1.5% |

Preprocessing and coefficients were not timed on these two models (the
script does it with `--from input`).

**Where the time goes.** One function, `cal_ire!` (`src/model/eqcombal.jl`),
holds 59% of the samples on OTCGEN and 78% on TIMES-NZ. Two causes:

1. **An untyped context.** `combal_context` is fetched from
   `tm.cache::Dict{String,Any}`, so the compiler does not know its type and
   every `x.field` in the loops is looked up at run time and allocates:
   `getproperty` alone is 42 to 45% of the samples and most of the memory.
2. **A loop that almost always misses.** For every commodity-balance row the
   auxiliary-flows loop walks every RPC_IRE entry of the region and its
   timeslices and probes IRE_FLOSUM, which has 1,248 records on OTCGEN and
   28 on TIMES-NZ. `eq_combal!` calls it twice per row, `eq_peak!` three
   times.

Smaller shares: Dict and Set lookups on string tuples 10 to 17%, reading the
dump 2 to 8%, building JuMP expressions 4 to 6%, adding columns 3 to 5%,
hashing strings 2 to 4%, row and column names under 1%, sorting under 0.1%.

**Order of the changes** (each one commit, gated by `p2_identity.jl --check`
on demo12, OTCGEN and TIMES-NZ, then timed):

1. Typed contexts (a function barrier): no arithmetic or order can change.
2. An index of IRE_FLOSUM for the auxiliary-flows loop, its hits replayed in
   the present order.
3. The term path (`getvar!` upper-cases the name and builds a key on every
   call; `addterm!` takes its labels as varargs strings).
4. Integer labels (P2-5 pilot b), family by family, if still needed.

The profile's own estimate after changes 1 and 2 is about 10 times GAMS on
both models for the generation step, so integer labels (the largest and
riskiest change) are probably needed to reach 5, and the date of 2 Dec 2026
is at risk. Names stay on for now (p2-q6): they cost under 1% today. Integer
labels are decided when changes 1 and 2 are measured (p2-q7).

Not explained yet: TIMES.jl stores fewer terms than GAMS counts non-zeros on
OTCGEN (6,732,783 against 9,082,086) and TIMES-NZ (5,026,918 against
5,066,303); they are equal on demo12, and layer 2 matched on both models on
23 Nov 2026. The explicit zeros in the CONVERT dump are still to be counted.

## Changes 1 and 2: the commodity balance (27 Nov 2026)

Both in `src/model/eqcombal.jl`, each with the LP bit for bit identical
(`p2_identity.jl --check`) on OTCGEN, TIMES-NZ steady and demo12_off, and
on demo12_mrkx and demo12_bndcst (REDUCE on; demo12_off has no IRE_FLOSUM).

1. **Typed context.** Each user of `combal_context` has an outer method
   that fetches the context and an inner method that takes it as an
   argument, so the compiler knows its type.
2. **An index of IRE_FLOSUM.** `cal_ire!` visits only the entries its row
   can reach. The index is built by walking the original loop once, so the
   order of the terms is the loop's; it was also compared entry by entry
   with the old loop.

Generation step only, one thread, warm, the lower of two repeats;
provisional as above (p2-q5, p2-q8), with other runs on the machine:

| | OTCGEN-gc_ref | TIMES-NZ-steady-v308 |
| --- | --- | --- |
| Before | 686 s, about 34 times GAMS | 627 s, about 55 |
| After change 1 | 216 s, about 10.7 | 102 s, about 8.9 |
| After change 2 | 193 s, about 9.6 | 80 s, about 7.0 |
| Allocated, before and after | 338 and 62 GiB | 384 and 28 GiB |

Nearly all of the gain is change 1. What the profile shows next: the same
untyped access in the objective (`objective_context`) and in `cal_cap!`;
the term path (`getvar!`, `addterm!`), about 30% of the samples; reading
the dump inside generation, 14 to 17%; garbage collection, about a third of
the time.

### The three stages together, after changes 1 and 2 (27 Nov 2026)

The measure of #208 d1 to d3: preprocessing, coefficients and generation,
one thread, from GAMS's input dump with the data in memory
(`p2_timing.jl --from input`), warmed on the model itself, the lower of two
repeats for each stage, through the run pool with other runs on the
machine. Provisional. GAMS's preprocessing and coefficient times are from
the profile of its pre-solve run, the harness's dumps left out.

| Seconds, TIMES.jl / GAMS | OTCGEN-gc_ref | TIMES-NZ-steady-v308 |
| --- | --- | --- |
| Preprocessing | 67.0 / 9.0 | 7.2 / 1.4 |
| Coefficients | 46.2 / 5.2 | 6.3 / 1.3 |
| Generation | 118.9 / 20.2 | 57.6 / 11.4 |
| Together | 232 / 34.4, about 6.7 times | 71 / 14.2, about 5.1 times |

On OTCGEN preprocessing (7.4 times) and the coefficients (8.9 times) are
further from the target than generation (5.9 times): P2-2 is now part of
the route. This path is not `run_model`'s (it starts from GAMS's input
dump, not from DD files).

## Changes 3 to 6: the other generators, the term path, the dump reader (27 Nov 2026)

Sixteen commits, each with the LP bit for bit identical on 65 demo12
fixtures, OTCGEN and TIMES-NZ steady (`p2_identity.jl --check`); the full
suite passes at the end. Stepped and stochastic runs and `demo12_tsoff_disp`
(which the fingerprint script cannot read) rest on the suite alone.

| Change | What |
| --- | --- |
| 3 | The function barrier of change 1 for the objective, `cal_cap!`, `cal_red!`, `eq_ptrans!`, `eq_capact!`, `eq_actflo!`, `eq_peak!`, `eq_stgaux!` and the row loop of the commodity balance |
| 4 | The term path: `addterm!` and `getvar!` specialised on the number of indices, the family looked up typed; a column name built in one allocation; `gset`/`gparam` look the name up as given before upper-casing |
| 5 | Shared empty lists as `get` defaults; the cancellation test `_all_cancel` without a Dict per row |
| 6 | The dump reader (`src/reference/dump.jl`): each Arrow column converted in its own function, and one String kept per distinct label of a symbol. Not in the change's brief; it changes no type or value of the records |

The three stages together, the measure of #208 d1 to d3 (one thread, data
in memory, the lowest of three warm repeats per stage, through the run
pool with the other model's run beside it; GAMS as in the table above):

| Seconds, TIMES.jl / GAMS | OTCGEN-gc_ref | TIMES-NZ-steady-v308 |
| --- | --- | --- |
| Preprocessing | 51.8 / 9.0 | 6.1 / 1.4 |
| Coefficients | 38.1 / 5.2 | 6.8 / 1.3 |
| Generation | 51.6 / 20.2 | 21.6 / 11.4 |
| Together | 141 / 34.4, about 4.1 times | 34 / 14.2, about 2.4 times |
| Whole builds | 144 to 152 s, 4.2 to 4.4 times | about 39 s, 2.7 to 2.8 times |

Both are inside the 5x target on this path, which starts from GAMS's input
dump and is not `run_model`'s. Still to measure: the other open models
(p2-q2: the target holds for every one), and the path from DD files.
On OTCGEN preprocessing (5.7 times) and the coefficients (7.3 times) are
now the stages furthest from GAMS; neither has had a speed change of its
own (P2-2).

What is left in generation, from the profile after the last change:
building the incidence maps (`indexby`, 27% on OTCGEN; the same map is
rebuilt by several generators), loading sets and parameters (18%), hashing
label strings (11%), garbage collection (a third of the time).

## Multi-threaded equation generation (P2-3, 31 Oct 2026)

What can run in parallel:

- **The JuMP model: no.** JuMP models are not thread-safe, and one model
  must be built sequentially on a single thread (JuMP's parallelism
  tutorial, https://jump.dev/JuMP.jl/stable/tutorials/algorithms/parallelism/).
- **Everything before the JuMP call: yes.** Reading sets and parameters,
  building each equation's row domain and term lists, and computing
  coefficients are plain Julia. They can run as separate tasks per equation
  family (eq_combal!, eq_acteff!, eq_floshr!, eq_capact!, ...) or per
  region.
- **The solve: separately.** The solver's own `threads` attribute is set per
  run and is independent of Julia's threads.

Two designs to try:

1. **Parallel prepare, serial add.** Each family fills a typed row buffer
   (row key, column ids, coefficients, sense, right-hand side) on its own
   task. One thread then adds the rows to JuMP in GAMS order. This keeps
   JuMP references and names. The serial add is the floor on the speed-up.
2. **Parallel triplets, one hand-off.** Each task writes (I, J, V) and row
   bounds into its own buffers, using row-id ranges reserved per family.
   The buffers are merged and the whole LP goes to the solver in one call
   (as scripts/m11_large.jl already does with `Highs_passLp`), or is loaded
   through MOI. This removes the serial JuMP add, at the cost of JuMP-level
   modification unless references are rebuilt. It goes with the direct
   mode and triplets items already planned for Phase 2.

Prerequisites:

- Concrete types in the generator contexts and integer labels (above).
  Without them, threads mostly contend on allocation and garbage
  collection.
- Stable column ids before rows are built in parallel. Today `getvar!`
  creates a column on first reference, so column order follows generator
  order. Create all columns first, or reserve id ranges per family, and
  keep the resulting column order identical to today's.
- No shared mutable state across tasks. `tm.cache` and the EPS set
  (`_eps_exprs`) are shared today and would need to become per-task, then
  merged.

Parity and determinism:

- The generated LP must stay identical, so layer-2 matrix parity is the
  gate. The comparison is by name, so row order does not affect it.
  Keep rows in GAMS order (`gams_sort!`) anyway, so solves stay
  reproducible.
- Each coefficient must be computed by the same arithmetic as now. Threads
  change which task computes a coefficient, never the order of operations
  within it: no parallel reductions inside one coefficient.

Measurement:

- Per-stage wall time and allocations at 1, 4, 8 and 12 Julia threads
  (`julia -t N`) on demo12, TIMES-NZ, OTUS9r and JRC-EU-TIMES. The serial
  fraction shows which design pays. Consider `--gcthreads` for the
  allocation-heavy stages.
- Run limits apply (CLAUDE.md): at most 12 threads per run, at most 4 heavy
  runs at a time. Generation and solve run one after the other, so each
  stage can use up to 12.
- Unconfirmed, to check: GAMS appears to generate on one thread. If so, this
  is where TIMES.jl could beat GAMS's generation time rather than only
  match it.

## Schemas for data and equations (P2-5, provisional, 10 Nov 2026)

Provisional: raised by James on 10 Nov 2026 for assessment. No work starts
until he confirms it.

The tools:

- **Pandera** (https://pypi.org/project/pandera/; MIT; Python 3.10+;
  0.35.0, 25 Oct 2026): dataframe schemas (dtypes, value checks, unique
  keys) for pandas, polars and other backends; schemas save to YAML or JSON.
  On polars a LazyFrame gets schema-level checks only, unless
  `PANDERA_VALIDATION_DEPTH=SCHEMA_AND_DATA` is set.
- **mathspec** (https://github.com/energy-models/mathspec; MIT code;
  Python 3.12+; 0.4.0, 22 Oct 2026; alpha, one maintainer, breaking changes
  without deprecation): an LP's dimensions, parameters, variables,
  constraints and objective as YAML, checked for names and dimensions without
  data, and typeset to LaTeX, Typst or Markdown. Fragments compose with
  `merge` and `override` (`adds_to:` adds a term to another fragment's sum).
  It builds no models. Not to be confused with BlockScience's MSML, a
  dynamical-systems tool.
- **Legolas.jl** (https://beacon-biosignals.github.io/Legolas.jl/dev):
  versioned Arrow table schemas in Julia (`name@version` in the file's
  metadata), the Julia counterpart for reading dumps. Licence still to check.

What they are for here:

- **Documentation that fails CI when it drifts.** A generated data
  dictionary of every TIMES set and parameter, and an equation reference per
  family beside Part II, with differences logged in `docs/discrepancies.md`.
- **Speed, indirectly.** Declared types let the loader build concrete,
  columnar containers once, with integer labels: the prerequisites of P2-2
  and P2-3. Production runs will start from DD files (M1.4), not dumps, so
  the gain comes from Julia types generated from the same declarations;
  Pandera guards the reference and parity path only.
- **TIMES-Verify.** A language-neutral contract (data schema plus equation
  spec) that Rust and Python ports, and partners' donated models, can be
  checked against without Julia.

Pilots, one PR each:

1. **Data schemas.** Generate one schema per symbol from the declarations
   (`GSym` in `src/dd/compile.jl`: kind, domain, dimension). Check dumps in
   `gdx2arrow.py` when written and in `src/reference/dump.jl` when read:
   column types; `__sv` codes 0-3, with -0.0 for EPS and NaN for NA/UNDEF;
   every label in `uels.arrow`; domain membership; unique keys; record counts
   against the manifest. CI on public fixtures only. Measure validation time
   on OTUS9r.
2. **Format 2 dump.** `d1`..`dN` as Arrow dictionary-encoded int32 indices
   into `uels.arrow`; the reader keeps the codes and builds no
   `NTuple{N,String}` keys. First check whether UEL index order is the rank
   `gams_sort!` uses. LP-identical: layer 2 at 1e-9 is the gate.
3. **Equation specs.** mathspec YAML for `EQ_ACTFLO` (simple) and
   `EQ_COMBAL` (hard), GAMS names kept; typeset and compared with Part II; a
   CI check that every generated row carries the spec's dimensions and only
   the variables its expression names. Record what mathspec cannot express
   (sets computed in preprocessing, `%VAR%` macros, REDUCE paths, EPS terms).

Rules: every schema is generated from the declarations, never written by
hand, so they stay the single source. No generator reads a schema or spec
before M1.7. Pandera and mathspec are MIT, compatible with
GPL-3.0-or-later. After the pilots: keep, narrow to the data schemas, or
drop.

## Memory

- A million-row model takes several GB of resident memory (the JuMP model
  with named rows and columns, plus the dump caches and index contexts).
- At that size the JuMP model plus HiGHS's own copy did not fit in 6 GB
  (HiGHS was killed in its interior point after presolve). Direct mode
  (Phase 2) builds the model in the solver once instead of in JuMP's cache
  and again in the solver.
- The parity tools hold whole LPs keyed by name strings
  (`Dict{Tuple{String,String},Float64}`, millions of entries per side at
  that size); scripts/m11_large.jl splits the check into processes to fit
  8 GB. Interned integer ids would make million-row parity checks a single
  process.

## Solving

- James's GAMS licence has no GAMS/HiGHS; GAMS-side HiGHS references stop at
  the 2,000-row demo limit.
