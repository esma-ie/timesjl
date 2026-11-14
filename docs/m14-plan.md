# M1.4 DD-file reader: plan (9 Nov 2026)

Source: TIMES v4.9.7, etsap-TIMES/TIMES_model @ d9a6a25. Started on
9 Nov 2026 (James: "go M1.4"), alongside the end of M1.3 as CLAUDE.md
allows. The M1.4 gate still waits for the M1.3 gate. One change per PR, in
the order below; GAMS names kept; every function cites its lines.

## Goal

Run TIMES.jl from a model's own `.run` file and `.dd` files, without GAMS.
The result must equal the harness's `input/` dump: every set and parameter
at 1e-9, the label order (UELs), and the order of 1-D sets. That dump is
taken just before `$BATINCLUDE maindrv.mod`, so it holds everything the M1.3
chain starts from. Once M1.4 passes, `scripts/m13_gate.jl` runs from DD
files instead of the dump: from the input files to the pre-solve point,
with no GAMS.

## Scope: what GAMS does before maindrv.mod

Every suite `.run` file (and the crafted cases, which add `$BATINCLUDE x.dd`
lines) does the same steps in the same order:

1. `$SET` switches and `$ONMULTI`;
2. `<case>_ts.dd`, which declares ALL_TS before initsys, so the timeslice
   labels are the first labels GAMS sees;
3. `$SET BOTIME`;
4. initsys.mod;
5. initmty.mod;
6. the scenario `.dd` files;
7. `SET MILESTONYR / ... /;` and `$SET RUN_NAME`;
8. maindrv.mod.

The harness patches each run file (`reference/python/runfile.py`
`patch_run`, L96-156): it adds TJLREF to initmty.mod, inserts `$SET`
overrides before initsys.mod, comments out `option LP=`, and dumps
`tjl_input.gdx` before maindrv.mod.

The GAMS code to translate:

| File | Lines | What |
| --- | --- | --- |
| initsys.mod | 17-187 | `$ONEMPTY`/`$ONMULTI`, BOTIME/EOTIME defaults (L35-36), built-in sets and data, YEARVAL (L43), `ALLYEAR /0/` (L79) |
| units.def, maplists.def, globals.def | 1-37, 1-121, 1-16 | built-in units, the maps (dotted parenthesised lists such as `DEM.(1.NRG,...)`), globals |
| initmty.mod | 19-476 | the declarations (L24-410) with their domains, scalar data (L360-369), the objective controls (L418-432), `SET ITEM` (L440), the derived switches (L441-473) |
| main_ext.mod via initmty.mod L476 | | initmty.dsc (`UNIT 0*100`), initmty.vda (`STL`, predefined items, L21-22, L72-76) |

Refused (UnportedError), as in M1.1-M1.3:

- the DATAGDX branch, initmty.mod L489-508 (`%RUN_NAME%~data.gdx` or
  `_dd_.gdx`). Change 4 checks whether any suite run takes it.
- `%STAGES%` (initmty.stc);
- MACRO (initmty.tm);
- `INTEXT_ONLY`.

setglobs.gms (the DATAGDX reload) runs inside maindrv.mod, after the input
checkpoint, so it is out of scope.

## The DD files of the suite (survey of 9 Nov 2026, open models only)

| Model | Files | Size | Lines |
| --- | ---: | ---: | ---: |
| demo12 | 11 | 0.2 MB | 6.8k |
| TIMES-NZ steady | 26 | 4 MB | 87k |
| OTCGEN | 20 | 11 MB | 185k |
| OTNYC | 23 | 17 MB | 382k |
| OTUS9r reference | 24 | 50 MB (one file 41 MB) | 1.16M |

- **Statements:** only `SET` and `PARAMETER` blocks. No TABLE, SCALAR, ALIAS
  or `$ONDELIM`.
- **Values:** no explicit EPS, INF or NA.
- **Keys:** no `(a,b)` key lists and no `*` ranges. Quoted and unquoted
  labels are mixed in one key (`'NI'.0.'X'.ANNUAL.UP 1`), and year `0` is a
  label.
- **Text:** set records carry explanatory text.
- **Dollar controls:** only `$ONEMPTY`, `$ONEPS`, `$ONWARNING` and `$SET`.
- **Quoted labels** may contain `*`, `.` and `/` (OTNYC: 4,935 labels with
  `*`).
- **Case:** the same label appears in different cases in every model
  (`Mt`/`MT`, `PJa`/`Pja`). GAMS keeps the first spelling it sees, including
  those in units.def.
- **Redeclaration:** under `$ONMULTI`, one symbol may be declared again in up
  to 13 files.
- **Block ends:** demo12 ends some blocks with `/` and no `;`.

## Changes

| # | What | GAMS | Checked at |
| --- | --- | --- | --- |
| 1 | (Done 9 Nov 2026.) Tokenizer and parser for the DD subset above, and scalar parameters (`G_DYEAR / 2005 /`). A label table that keeps first-seen order and first spelling. Unsupported syntax stops with the file and line. | (GAMS compiler rules; discrepancies entries as needed) | unit tests on synthetic text and the 16 crafted DD files; parse every suite DD file without error |
| 2 | Declarations and built-in data, translated as Julia: initsys.mod, units.def, maplists.def, globals.def, initmty.mod L19-476, initmty.dsc, initmty.vda | initsys.mod 17-187; initmty.mod 19-476 | symbol names, kinds and domains against `input/manifest.json`; the records of every symbol no DD file writes (107 on demo12) |
| 3 | Run-file interpreter: `$SET`/`$SETGLOBAL` (quoted values), `$IF [NOT] SET/DECLARED`, `$IFI`, `$BATINCLUDE` with the include directories, `SET MILESTONYR`, OPTION lines skipped, and the switches initmty.mod derives (L418-473). Replaces `run_switches` in scripts/m11_probe.jl | initmty.mod 418-473 | the switches against the harness's `raw/tjl_presolve.run` and the dump's symbols, every suite run |
| 4 | Data rules: `$ONEPS` (a 0 becomes EPS), `$ONMULTI` merges (later values win), domain checks against the sets as compiled at that point (a violation drops the record and counts a warning: G32, G54), records in label order | | demo12 and every crafted case: `input/` at 1e-9, label order, 1-D set order, the compile-warning count (`qa_warnings!`) |
| 5 | Scale and wiring: stream the large files; a `DumpData` built from DD files; `m13_gate.jl --from dd` | | the four large models, `input/` at 1e-9; the M1.3 chain from DD files to pre-solve on every core run |

The M1.4 gate: change 5 passes on every core-tier run, both variants, and CI
runs the chain from DD files on demo12 and the crafted cases.

## Findings of 9 Nov 2026 (evening), and the plan they change

- **Changes 2, 3 and 4 are one piece of code.** The `$IF`/`$SET` logic decides which declarations
  and data GAMS compiles, and the data rules decide the records, so none of the three can be
  checked alone. `src/dd/compile.jl` does GAMS's compile phase for all three: dollar controls,
  declarations with `$ONMULTI`, data statements (domain checks, `$ONEPS`, label order), and the
  executable statements before maindrv.mod (initsys.mod L43, initmty.mod L368-369), run after
  compilation as GAMS runs them. They are reviewed as one PR, in place of three.
- **Result before maindrv.mod:** on every open core model, both variants, every symbol the reader
  compiles (389) equals the input dump (keys, record order, values, EPS, set text), and every label
  is in the dump's order (G55). demo12 compiles in 0.5 s, OTUS9r in 7 s. TIMES-NZ's 84 domain
  violations are dropped with 84 warnings, as in GAMS (G56; open question 1 below, answered).
  (Corrected 14 Nov 2026, change 8: GAMS counts 88 warnings for the 84 records, and keeps some
  kinds of record outside a domain, which the reader refuses.)
- **Scope: GAMS compiles the whole program before running any of it.** So the input dump holds
  every symbol of TIMES (1,023 for demo12, 602 of them declared after maindrv.mod), and the
  compile-time data of the later files: 30 symbols with records, 4 more members of UC_NUMBER,
  3 labels. The M1.3 chain reads them. A GAMS-free run needs them too, so the reader must also
  compile maindrv.mod and the files it includes, for their declarations and compile-time data
  only (their executable statements run after the input checkpoint and are already translated).
  TIMES's code uses about 45 kinds of dollar control; the later files add `$MACRO` (127),
  `$EOLCOM`, `$SHIFT`, `$EXIT`, `$IFE`, `$CLEAR` and others to what initsys and initmty use. New
  change 2b. This is the main risk to the M1.4 timetable.
- **Where the TIMES source comes from.** Compiling the whole program needs the TIMES v4.9.7 files
  at run time, in CI and for users. Change 2 was to generate Julia from initsys and initmty; that
  does not scale to the whole program (about 250 files). Proposal (decision for James): a pinned
  Julia Artifact of `etsap-TIMES/TIMES_model` @ d9a6a25, downloaded on first use and checked by
  hash; CI uses the same artifact. Until then the scripts take `--sources`. (James, 10 Nov 2026: approved, a pinned
  download of `etsap-TIMES/TIMES_model`.) He also asked that the run from DD files to the matrix and
  the solution join the existing chain and the probe set (change 5).

| # | What | Status |
| --- | --- | --- |
| 2-4 | `src/dd/compile.jl`: the compile phase to maindrv.mod | done for the open core models (draft PR) |
| 2b | the compile phase of maindrv.mod and its includes: declarations and compile-time data | done for the open core models (9 Nov, draft PR #86) |
| 2c | the TIMES source as a Julia Artifact (approved by James, 10 Nov 2026) | done (10 Nov): `Artifacts.toml`, `times_source()`; CI compiles demo12 from its DD files |
| 5 | scale, wiring, `m13_gate.jl --from-dd` | done (10 Nov): `write_dump`; the chain, the matrix and the HiGHS solve from DD files with no GAMS state; CI on demo12; nightly on the open models |
| 7 | the controls of restart and stepped (myopic) runs, initmty.mod L442-444 | done (14 Nov): a run file with SPOINT, TIMESTEP or FIXBOH compiles; crafted case demo12_step (TIMESTEP 20) from its DD files to `ppm/` in both variants; CI compiles it. The stepped solve (solve.stp) is M1.5 |
| 6 | the M1.4 gate's remaining items: the demo12 variants in CI, TIM and JRC-EU-TIMES (local), the licence level, a runner for any run file | done (10 Nov): `scripts/m14_models.jl` reads the DD folders from `reference/suite.toml` and `reference/crafted.toml` (`--local` for TIM and JRC-EU-TIMES); CI compiles demo12 and 11 variants from their DD files; `licencelevel` (K3); `scripts/run_dd.jl` and `run_dd.cmd` |
| 8 | compile warnings as GAMS counts them; TIMES's GDX filter of records outside their domain sets (setglobs.gms L13-24, gdxfilter.gms L4-19); a key given twice in one data statement | done (14 Nov): 88 warnings on TIMES-NZ as GAMS; the three cases where GAMS keeps such a record stop the run; a key given twice stops as GAMS error 172 (G56, G59) |
| gate | the evidence for each criterion | "Gate close-out, 14 Nov 2026" below; the gate waits for the M1.3 gate and for James's yes |

### Change 2b, 9 Nov 2026 (late evening)

The whole program compiles without GAMS. On every open suite model (demo12, TIMES-NZ steady and
shift, OTCGEN, OTNYC, OTUS9r reference and tax1_wo_mou), both variants, `scripts/m14_probe.jl`
finds:

- the files included, in order and by level, equal the Include File Summary of GAMS's listing
  (643 to 678 inclusions);
- every symbol of the input dump declared, and no other (GDX leaves out unreferenced variables, G57);
- every set and parameter identical (824, or 825 for OTUS9r): keys, record order, values, EPS,
  element text;
- every label in the dump's order (1,709 for demo12 to 10,441 for OTCGEN).

The compile takes 1 s (demo12) to 8 s (OTUS9r). The GAMS rules this needed are G55 to G58 and the
addition to G35. Next: the TIMES source as an Artifact (2c, James's decision), then change 5: a
`DumpData` from the compile, and `m13_gate.jl` from DD files.

### Change 5, 10 Nov 2026

`write_dump` (`src/dd/writedump.jl`) writes the compile as the harness's dump format, so everything
that reads `input/` runs from DD files. `scripts/m13_gate.jl --from-dd <timesjl-sources> [--solve]`:

1. compiles the run's own run file and DD files, writes the dump and compares it with GAMS's
   `input/` (every set and parameter at 1e-9, the label list);
2. runs the chain on TIMES.jl's state alone: no checkpoint dump is read into it, unlike the M1.3
   gate's carry, so a step that TIMES.jl does not do exactly would show at the next checkpoint;
3. generates the model and compares it with GAMS's CONVERT matrix (layer 2);
4. with `--solve`, solves it with HiGHS and compares the objective with GAMS/CPLEX's (layer 3).

CI does the same on demo12 (`test/unit/test_m13_chain.jl`), and `run_overnight.ps1` on the open
core models. Variables and equations are written without their type (K2, proposed).

The first run without carry found a bug that the M1.3 gate's carry had hidden. `gset` read an alias
(`PYR`, `ALIAS(PASTYEAR,PYR)`) as its target's records in the dump and cached them, so after
TIMES.jl had computed `PASTYEAR` (one more year by prelv), `PYR` was stale. With carry the dump was
the last checkpoint's, which had the new `PASTYEAR`; from DD files it is the input dump. Under
REDUCE YES (`as_run`), pp_reduce.red L25 (`PRC_CAP` of a process with past investments) then
missed processes. TIMES-NZ, OTCGEN and OTUS9r showed it from ppm on, though HiGHS still found
GAMS's objective. Fixed: an alias is now its target as TIMES.jl holds it (`gset`,
`src/model/gams_data.jl`), with a unit test.

### Change 6, 10 Nov 2026

- **DD folders from the suite.** `scripts/m14_models.jl` takes each model's include directories
  (`idirs`) from `reference/suite.toml` or `reference/crafted.toml`, with every `{root}` a folder of
  `timesjl-sources`, so the gate and the probe run on any suite or crafted model. A model whose
  `redistribute` is not `"public"` (TIM, JRC-EU-TIMES) needs `--local`: it runs on James's
  workstation and its logs stay there (CLAUDE.md).
- **The demo12 variants in CI.** `test/unit/test_ddsource.jl` compiles demo12 and the 11 variants
  that have an input fixture from their DD files (TIMES_Demo's and their own in `reference/dd/`)
  and compares the result with the fixture: the symbols, every set and parameter, the labels, the
  warning count. Their patched run files are fixtures (`test/fixtures/<prefix>_run`). The 15
  variants with a reference run all compile to GAMS's input dump (`scripts/m14_probe.jl`, both
  variants); demo12_qa99 has no reference run on the reference machine.
- **Licence level.** `compile_run(...; licencelevel)`, 0 by default as the reference workstation's
  full licence; 2 gives the demo licence's VAR_UC (K3, answering open question 2).
- **Any run file.** `scripts/run_dd.jl <run file> [--dd <folder> ...] [--solve]` compiles a run file
  and its DD files, preprocesses, generates the model and solves it with HiGHS, with no GAMS and no
  reference to compare with. It compiles a copy of the run file with `SOLVE_NOW NO` before
  maindrv.mod, as the harness does, so that GAMS's solve and report files are not compiled.
  `scripts/run_dd.cmd` runs it on a run file dragged onto it in Windows Explorer. On TIMES_Demo's
  own `demo12.run` (REDUCE YES) it gives 3,233 rows and HiGHS's objective 23,960,685.737007916,
  GAMS/CPLEX's within 4e-15.

### Change 7, 14 Nov 2026: the controls of restart and stepped runs

- **What stopped.** initmty.mod L440-447 handle three controls a run file may set: SPOINT (a
  restart from a saved solution), TIMESTEP (a stepped, or myopic, run: the horizon is solved in
  steps of that many years) and FIXBOH (the first periods fixed to an earlier solution). L442-444
  check each one that is set with an executable statement, for example
  `IF(NOT AGE('%TIMESTEP%'), ABORT 'Invalid Control: TIMESTEP');`. The DD reader runs the few
  executable statements before maindrv.mod by hand (`INIT_EXEC`) and had no entry for these
  three, so any run file with one of the controls stopped at "executable statement at
  initmty.mod".
- **Translation.** One entry per line: SPOINT must be a member of J (1*999) or YES, TIMESTEP a
  member of AGE (1*200), FIXBOH a member of ALLYEAR; otherwise the compile stops with GAMS's
  abort text. The dollar lines around them (L440 `SET ITEM`, L441 `RPOINT NO`, L445-447
  `STEPPED -` under FIXBOH, `STEPPED +` under TIMESTEP, `VAR_UC YES` under STEPPED) were already
  compiled as written.
- **Labels.** The checks name labels and add none. GAMS wants a label named in an executable
  statement to be known already (compile error 116, "Label is unknown", otherwise): that is what
  `SET ITEM / "%FIXBOH%", "%TIMESTEP%", "%SPOINT%" /` at L440 is for, and YES is known from
  initsys.mod L124 (checked with two small programs on GAMS 54.6.1). So the entries only look the
  label up, and the label order of the input dump is unchanged.
- **The case.** `reference/dd/demo12_step/demo12_step.run`: demo12's run file with
  `$SET TIMESTEP 20` (OBJ MOD kept). GAMS 54.6.1, CPLEX and HiGHS, both variants: three stepped
  solves, the last with demo12's objective 23,960,685.737 (the steps before it end at
  12,397,965.986 and 20,325,417.763).
- **Result.** Both variants: DD files to `input/` (834 sets and parameters, 1,709 labels, no
  compile warning), then `init/`, `prep/`, `prelv/` and `ppm/` (833 symbols) and the QA log, all
  PASS. The chain ends before the coefficient stage with "not translated: coef_alt.lin L81
  (TIMESTEP set: stepped solve, M1.5)".
- **What is left for stepped runs** (not in this change): coef_alt.lin L81 and its STP call,
  eqobsalv.mod L23-25 (the salvage preparation moves into the steps), maindrv.mod L38-41 and
  L109-113 and solve.stp (the loop over steps, with the earlier periods fixed to their levels),
  and the STEPPED, FIXBOH and SPOINT branches of bndmain.mod. They are run options, M1.5.
  (coef_alt.lin L81 and eqobsalv.mod L23-25 followed the same day as M1.3 change 30,
  docs/m13-plan.md.)
- **CI.** `test/unit/test_ddsource.jl`: demo12_step from its DD files against its input fixture
  (`demo12_step_run`, `demo12_step_input`), STEPPED and VAR_UC as GAMS sets them, and demo12 with
  the controls given from outside: valid values pass, invalid ones stop with GAMS's abort text.

### Change 8, 14 Nov 2026: warnings as GAMS counts them, TIMES's GDX filter, a key given twice

- **88 against 84 (open question 1).** GAMS's listing of TIMES-NZ ends with 88 warnings; the reader
  dropped 84 records and counted 84. All of them name one label, a commodity that is not in COM, in
  records of a five-dimensional set in base.dd. GAMS gives one warning for each label outside its
  domain set (`$170`), and 4 of the 84 records have the label in two positions: 80 + 2 x 4 = 88.
  The reader now counts as GAMS does and prints 88. The count itself changes nothing: TIMES only
  tests whether there are warnings (`$IF WARNINGS`, setglobs.gms L22 and ppmain.mod L35, G54).
- **What GAMS does with such a record** (G56, corrected). Under `$ONWARNING` GAMS keeps it in
  memory. TIMES removes it before its own code runs: setglobs.gms L13-24 (the first file
  maindrv.mod includes, L23), when DATAGDX is YES and the compile has warnings, unloads the data to
  a GDX file and calls gdxfilter.gms MAIN, which loads it again under `$onFiltered` (L12-16).
  Checked on GAMS 54.6.1 with demo12 plus a DD file of such records, displayed before maindrv.mod:
  - a record of a symbol with two or more dimensions is removed;
  - a record of a one-dimensional set or parameter stays, because gdxfilter.gms L11 deletes the
    load lines of one-dimensional symbols. TIMES's code then uses it: a member of REG outside
    ALL_REG is one more region for every later statement, and later records naming it get no
    warning;
  - a record whose label joins the domain set later in the data stays: the filter checks against
    the sets as they stand when it runs;
  - without `$SET DATAGDX YES` there is no filter, and every such record stays.
  GAMS's dumps do not show this: an `execute_unload` of all symbols writes no record outside its
  domain, kept or not. So the input dump cannot check these cases; only the later checkpoints
  would.
- **Translation.** `gput!` drops the record where it is read, which equals the filter for symbols
  of two or more dimensions, and notes it. `gdomain_filter!`, called where maindrv.mod starts
  (the place of setglobs.gms), stops the run with "not yet translated" in the three cases where
  GAMS keeps a record: no `DATAGDX YES`; a one-dimensional set or parameter; a label that is in
  the domain set by the end of the data. No suite model has one: only TIMES-NZ has records outside
  a domain, all of a five-dimensional set, with DATAGDX YES. Keeping the records as GAMS does
  would mean carrying them through the reader and the dump format; it is left until a model
  needs it.
- **A key given twice in one data statement (open question 4).** GAMS stops with compile error
  172, "Element is redefined", with or without `$ONMULTI` (G59). The reader let the later record
  win; it now stops with the file and line. Without `$ONEPS` a zero is not a record, so a zero
  beside a value of the same key is no error and the value stays; a zero in a later statement
  still removes the earlier value. No suite model has such a key.
- **Result.** `scripts/m14_probe.jl`, both variants: TIMES-NZ steady and shift compile with 88
  warnings, as GAMS's listing, and all 824 sets and parameters and 3,633 (3,713) labels equal the
  input dump; demo12, OTCGEN, OTNYC and OTUS9r reference and tax1_wo_mou are unchanged (no
  warning, every set and parameter identical). `test/unit/test_ddcompile.jl`: 70 tests, among
  them each of the cases above.

### Gate close-out, 14 Nov 2026

The gate: change 5 passes on every core-tier run, both variants, and CI runs the chain from DD
files on demo12 and the crafted cases. Each criterion with its evidence follows. Every reference
was made with GAMS 54.6.1; the runs are on James's workstation, within the run limits. The gate
waits for the M1.3 gate (#109) and is passed when James says so (a rule-level decision).

The core-model evidence is the workstation batch of 14 Nov on `main` at `c04c8ab`:
`scripts/m13_gate.jl --from-dd --solve` compiles each run's own run file and DD files with no
GAMS, compares the result with GAMS's `input/` dump, runs the M1.3 chain on TIMES.jl's state
alone to the pre-solve dump, generates the model and compares it with GAMS's matrix, and solves
it with HiGHS. The changes since `c04c8ab` (#105 to #115 and change 8) add features that no core
model uses, and change 8 changes only the warning count of TIMES-NZ; the first step was run again
with this code (change 8, Result). The batch runs the whole chain again once they are merged.

| Criterion | Evidence | Result |
| --- | --- | --- |
| DD files to `input/` at 1e-9, five open core models, reduce_off and as_run | Every set and parameter (824; 825 on OTUS9r) and every label in the dump's order: demo12 1,709 labels; TIMES-NZ-steady 3,633; OTCGEN 10,441; OTNYC 7,736; OTUS9r 10,203. Again with change 8 (`scripts/m14_probe.jl`). | PASS, 10 of 10 |
| The M1.3 chain from DD files to the pre-solve dump, no GAMS state | Same runs: init, prep, prelv, ppm, coef and presolve, every set and parameter at each, with the QA log. | PASS, 10 of 10 |
| TIM-bau | Checked locally (results stay on James's machine). | local |
| CI runs the chain from DD files on demo12 | `test/unit/test_m13_chain.jl`, "M1.4: DD files -> input -> pre-solve -> model": compile, `write_dump`, the input fixture, the chain to presolve, the QA log, the model against GAMS's matrix and objective. | PASS |
| CI runs the chain from DD files on the crafted cases | In pieces, each starting from a GAMS dump of the case, not in one run. `test/unit/test_ddsource.jl` compiles demo12, 22 crafted cases and demo12_step from their DD files and compares each with its input fixture (symbols, every set and parameter, labels, warning count). `test/unit/test_variants.jl` runs 24 crafted cases from the input fixture to `ppm/` on TIMES.jl's own state. `test/unit/test_public_parity.jl` generates the model of each public fixture from GAMS's pre-solve dump (layers 2 and 3), and runs the coefficient stage from GAMS's `ppm/` dump where the fixture has one. Only demo12 goes from DD files to the model in one run in CI. On the workstation the crafted cases of #105 to #115 did so in their own PRs (`m13_gate.jl --from-dd --solve`, both variants); demo12_xbnd and demo12_pf again with this code (all PASS, a few seconds for each run once Julia is warm). Proposed: the one run for every crafted case in CI, as the next PR. | in pieces (decision for James) |

Beyond the gate, from the same batch (James, 10 Nov 2026: the matrix and the solution join the
chain from DD files):

| Run | Rows, columns, nonzeros (reduce_off; as_run) | Layer 2 against GAMS's matrix | HiGHS against GAMS/CPLEX (reduce_off; as_run) |
| --- | --- | --- | --- |
| TIMES_Demo-demo12 | 8,695, 9,669, 31,391; 3,233, 4,485, 18,375 | PASS, both | 4.2e-15; 3.7e-15 |
| TIMES-NZ-steady-v308 | 1,408,361, 1,299,224, 5,026,918; 622,043, 523,095, 3,375,383 | PASS, both | 3.8e-11; 2.0e-10 |
| OTCGEN-gc_ref | 1,257,132, 1,507,223, 6,732,783; 512,182, 765,953, 5,200,869 | PASS, both | 8.1e-16; 1.7e-15 |
| OTNYC-s1_nyc_ref | 504,698, 858,299, 2,531,196; 236,650, 557,258, 1,863,168 | PASS, both | 9.6e-16; 3.9e-16 |
| OTUS9r-reference | 2,174,010, 2,776,359, 9,925,588; 1,028,923, 1,647,278, 7,163,965 | PASS, both | not solved with HiGHS (layer 3 on OTUS9r is one way, CLAUDE.md) |

Not part of the gate, for the record:

- Milestone tier, same batch. OTUS9r-tax1_wo_mou: DD files to the model, layer 2 PASS in both
  variants (2,528,996 rows reduce_off, 1,199,533 as_run). TIMES-NZ-shift-v308: layer 2 PASS in
  both variants (1,483,415 and 630,987 rows); HiGHS reaches GAMS/CPLEX's objective as_run
  (4.1e-11) and stops at the script's 3,600 s time limit reduce_off, so that one run has no
  objective to compare. The limit is to be raised for it.
- `scripts/m14_probe.jl` (the compile against the input dump, with the include trace against
  GAMS's listing): identical on all 50 runs of the open models in the batch: the seven open suite
  runs and 18 crafted demo12 cases, both variants.
- JRC-EU-TIMES (verdicts only): the compile equals the input dump on all nine scenarios. The
  chain from DD files on JRC-EU-TIMES-cli_ll passes init, prep, prelv and ppm (850 symbols) on
  `c04c8ab` and ends there at ANNCOST LEV, translated since (M1.3 change 29).
- What stays open in the reader: the attributes of `$IF DEFINED` (#87, open question 3); the
  labels used only by TIMES code (open question 5); the three cases of change 8 where GAMS keeps
  a record outside its domain; DATAGDX loading, initmty.stc, initmty.tm and `$LOAD`/`$GDXIN` with
  a file, all refused with a message. No suite model reaches one. The stepped solve of a run
  with TIMESTEP (solve.stp) is M1.5.

## Open questions (flag, do not guess)

1. **Domain violations.** (Answered 14 Nov 2026, change 8 and G56: GAMS keeps the records and
   TIMES's GDX filter removes them, as suite.toml says; 88 warnings for 84 records because GAMS
   warns once for each label and 4 records have two. The 9 Nov answer, "dropped at compile time",
   was right in effect for TIMES-NZ only.) suite.toml says DATAGDX "filters" 84 records in
   each TIMES-NZ case. G32 says GAMS drops them at compile time. Change 4 checks
   the TIMES-NZ `input/` dump. TIMES-NZ's 88 compile warnings against 84
   dropped records leave 4 unexplained.
2. (Answered 10 Nov 2026: the `licencelevel` run option, default 0 as the full licence of the reference workstation; K3 in known-differences.md.) **`%SYSTEM.LICENSELEVEL%==2` sets VAR_UC** (initmty.mod L448), so a switch
   depends on the GAMS licence of the machine. TIMES.jl has no GAMS licence.
   Proposal: a `licencelevel` run option, default as on James's
   workstation, recorded in known-differences.md.
3. **`$IF DEFINED` on a symbol declared with an empty `//` list (G35):** answered
   9 Nov 2026: it counts as defined (GAMS experiment), and so does a `$MACRO` name. Still open: an
   assignment compiled after maindrv.mod also makes a symbol DEFINED, which the reader does not track
   (no open suite model's include trace depends on it). The tests to add are logged in issue #87
   (James, 10 Nov 2026). Answered for plain assignments on 10 Nov 2026: JRC-EU-TIMES reaches preppm.mod
   L27-28, where an assignment that never runs (`$NO`) makes R_CUREX defined; the reader now
   counts compiled assignments (`gassigned!`, G35). Attributes stay open (#87).
4. **Duplicate keys inside one data statement:** (Answered 14 Nov 2026, change 8 and G59: compile
   error 172 in GAMS, with or without `$ONMULTI`; the reader stops in the same way.) GAMS's behaviour is not
   confirmed. The reader lets the later record win, as `$ONMULTI` merges do; every open suite model
   matches the input dumps, so none depends on it either way.
5. **Labels used only by TIMES code** (`ITEM` with an empty `%FIXBOH%`, the
   label `''`): the dump keeps only labels that some record uses (G36), so
   their place in the label order is checked indirectly.

## Parity check

`compare_dumps` (src/reference/compare.jl) between the reader's result and
the `input/` dump of each reference: every symbol at 1e-9, keys
case-sensitive, 1-D set order. The labels the dump keeps must appear in the
reader's label list in the same order. CI fixtures from demo12 and the
crafted cases only (`redistribute = "public"`).
