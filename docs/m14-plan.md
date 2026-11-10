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
| 5 | scale, wiring, `m13_gate.jl --from dd` | as planned |

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

## Open questions (flag, do not guess)

1. **Domain violations.** (Answered 9 Nov 2026: dropped at compile time, G56.) suite.toml says DATAGDX "filters" 84 records in
   each TIMES-NZ case. G32 says GAMS drops them at compile time. Change 4 checks
   the TIMES-NZ `input/` dump. TIMES-NZ's 88 compile warnings against 84
   dropped records leave 4 unexplained.
2. **`%SYSTEM.LICENSELEVEL%==2` sets VAR_UC** (initmty.mod L448), so a switch
   depends on the GAMS licence of the machine. TIMES.jl has no GAMS licence.
   Proposal: a `licencelevel` run option, default as on James's
   workstation, recorded in known-differences.md.
3. **`$IF DEFINED` on a symbol declared with an empty `//` list (G35):** answered
   9 Nov 2026: it counts as defined (GAMS experiment), and so does a `$MACRO` name. Still open: an
   assignment compiled after maindrv.mod also makes a symbol DEFINED, which the reader does not track
   (no open suite model's include trace depends on it). The tests to add are logged in issue #87
   (James, 10 Nov 2026).
4. **Duplicate keys inside one data statement:** GAMS's behaviour is not
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
