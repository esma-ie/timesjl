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
| 1 | Tokenizer and parser for the DD subset above. A label table that keeps first-seen order and first spelling. Unsupported syntax stops with the file and line. | (GAMS compiler rules; discrepancies entries as needed) | unit tests on synthetic text and the 16 crafted DD files; parse every suite DD file without error |
| 2 | Declarations and built-in data, translated as Julia: initsys.mod, units.def, maplists.def, globals.def, initmty.mod L19-476, initmty.dsc, initmty.vda | initsys.mod 17-187; initmty.mod 19-476 | symbol names, kinds and domains against `input/manifest.json`; the records of every symbol no DD file writes (107 on demo12) |
| 3 | Run-file interpreter: `$SET`/`$SETGLOBAL` (quoted values), `$IF [NOT] SET/DECLARED`, `$IFI`, `$BATINCLUDE` with the include directories, `SET MILESTONYR`, OPTION lines skipped, and the switches initmty.mod derives (L418-473). Replaces `run_switches` in scripts/m11_probe.jl | initmty.mod 418-473 | the switches against the harness's `raw/tjl_presolve.run` and the dump's symbols, every suite run |
| 4 | Data rules: `$ONEPS` (a 0 becomes EPS), `$ONMULTI` merges (later values win), domain checks against the sets as compiled at that point (a violation drops the record and counts a warning: G32, G54), records in label order | | demo12 and every crafted case: `input/` at 1e-9, label order, 1-D set order, the compile-warning count (`qa_warnings!`) |
| 5 | Scale and wiring: stream the large files; a `DumpData` built from DD files; `m13_gate.jl --from dd` | | the four large models, `input/` at 1e-9; the M1.3 chain from DD files to pre-solve on every core run |

The M1.4 gate: change 5 passes on every core-tier run, both variants, and CI
runs the chain from DD files on demo12 and the crafted cases.

## Open questions (flag, do not guess)

1. **Domain violations.** suite.toml says DATAGDX "filters" 84 records in
   each TIMES-NZ case. G32 says GAMS drops them at compile time. Change 4 checks
   the TIMES-NZ `input/` dump. TIMES-NZ's 88 compile warnings against 84
   dropped records leave 4 unexplained.
2. **`%SYSTEM.LICENSELEVEL%==2` sets VAR_UC** (initmty.mod L448), so a switch
   depends on the GAMS licence of the machine. TIMES.jl has no GAMS licence.
   Proposal: a `licencelevel` run option, default as on James's
   workstation, recorded in known-differences.md.
3. **`$IF DEFINED` on a symbol declared with an empty `//` list (G35):** not
   confirmed whether that counts as defined.
4. **Duplicate keys inside one data statement:** GAMS's behaviour is not
   confirmed. The reader stops on them until a model shows one.
5. **Labels used only by TIMES code** (`ITEM` with an empty `%FIXBOH%`, the
   label `''`): the dump keeps only labels that some record uses (G36), so
   their place in the label order is checked indirectly.

## Parity check

`compare_dumps` (src/reference/compare.jl) between the reader's result and
the `input/` dump of each reference: every symbol at 1e-9, keys
case-sensitive, 1-D set order. The labels the dump keeps must appear in the
reader's label list in the same order. CI fixtures from demo12 and the
crafted cases only (`redistribute = "public"`).
