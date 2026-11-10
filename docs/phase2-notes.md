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
