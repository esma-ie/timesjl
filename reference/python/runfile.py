"""Patch TIMES .run files for the TIMES.jl reference harness.

Pure text manipulation, no GAMS needed, so it is unit-tested in CI.

The harness never edits the TIMES source. It hooks in through the TIMES
extension mechanism instead:

* ``initmty.mod`` appends its arguments %1..%6 to the ``EXTEND`` list
  (initmty.mod L472-473, v4.9.7).
* ``main_ext.mod`` then includes ``<stage>.<ext>`` for every extension in
  ``EXTEND`` if the file exists (main_ext.mod L14-23, v4.9.7), after the
  standard extensions such as VDA.

So passing ``TJLREF`` to ``initmty.mod`` makes TIMES include our
``ppm_ext.tjlref`` right after preprocessing (maindrv.mod L58) and
``coef_ext.tjlref`` right after coefficient calculation (maindrv.mod L73), and,
for the M1.3 checkpoints, ``init_ext.tjlref`` (maindrv.mod L55),
``prep_ext.tjlref`` (preppm.mod L217) and ``pp_prelv.tjlref`` (ppmain.mod L615).
The first checkpoint, the state before preprocessing, has no extension stage:
the patcher puts its dump just before ``$BATINCLUDE maindrv.mod``.
File names are lower-cased by GAMS ``filecase=4``, as in the xl2times run
scripts.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

EXTENSION_TAG = "TJLREF"
MARK = "* [TIMES.jl reference harness]"

_INITMTY = re.compile(r"^(?P<head>\s*\$\s*batinclude\s+initmty(?:\.mod)?)(?P<args>[^*\r\n]*)$", re.IGNORECASE)
_MAINDRV = re.compile(r"^\s*\$\s*batinclude\s+maindrv(?:\.mod)?\b", re.IGNORECASE)
_INITSYS = re.compile(r"^\s*\$\s*batinclude\s+initsys(?:\.mod)?\b", re.IGNORECASE)
_OPTION_LP = re.compile(r"^\s*option\s+lp\s*=\s*[^;]*;\s*$", re.IGNORECASE)
_COMMENT = re.compile(r"^\s*\*")


def _set_line(name: str) -> re.Pattern:
    # Matches "$SET NAME ...", "$ SET NAME ...", "$   SETGLOBAL NAME ..." at line start.
    return re.compile(
        r"^\s*\$\s*set(?:global|local)?\s+" + re.escape(name) + r"(?:\s|$)",
        re.IGNORECASE,
    )


# M1.3 input checkpoint: every symbol as the run file leaves it (DD files read,
# switches set), just before maindrv.mod; only with --TJL_CHECKPOINTS=1.
INPUT_BLOCK = """\
{mark} M1.3 input checkpoint: the state the main driver starts from
$IF SET TJL_CHECKPOINTS execute_unload 'tjl_input.gdx';
"""

SOLVEINFO_BLOCK = """\
{mark} solve information for timing and parity checks
$IF NOT SET MODEL_NAME $SET MODEL_NAME TIMES
PARAMETER TJL_SOLVEINFO(*) 'TIMES.jl reference harness: model attributes after solve';
TJL_SOLVEINFO('modelstat') = %MODEL_NAME%.modelstat;
TJL_SOLVEINFO('solvestat') = %MODEL_NAME%.solvestat;
TJL_SOLVEINFO('objval')    = %MODEL_NAME%.objval;
TJL_SOLVEINFO('numequ')    = %MODEL_NAME%.numequ;
TJL_SOLVEINFO('numvar')    = %MODEL_NAME%.numvar;
TJL_SOLVEINFO('numnz')     = %MODEL_NAME%.numnz;
TJL_SOLVEINFO('resgen')    = %MODEL_NAME%.resgen;
TJL_SOLVEINFO('resusd')    = %MODEL_NAME%.resusd;
TJL_SOLVEINFO('etsolve')   = %MODEL_NAME%.etsolve;
TJL_SOLVEINFO('etsolver')  = %MODEL_NAME%.etsolver;
TJL_SOLVEINFO('iterusd')   = %MODEL_NAME%.iterusd;
execute_unload 'tjl_solveinfo.gdx', TJL_SOLVEINFO;
"""


@dataclass
class PatchReport:
    """What the patcher changed, recorded in the reference manifest."""

    extension_line: str = ""
    overrides: dict = field(default_factory=dict)
    removed_lp_options: list = field(default_factory=list)
    solveinfo_after: str = ""
    input_before: str = ""
    implicit_assign: bool = False


class RunFileError(ValueError):
    pass


def _find_unique(lines, pattern, what):
    hits = [i for i, ln in enumerate(lines) if not _COMMENT.match(ln) and pattern.match(ln)]
    if len(hits) != 1:
        raise RunFileError(f"expected exactly one {what} line, found {len(hits)}")
    return hits[0]


def patch_run(text: str, overrides: dict | None = None, strip_lp_option: bool = True) -> tuple[str, PatchReport]:
    """Return the patched run file text and a report of the changes.

    - adds ``TJLREF`` to the ``$BATINCLUDE initmty.mod`` arguments;
    - applies ``$SET`` overrides (e.g. ``{"REDUCE": "NO"}``): existing ``$SET``
      lines for that name are commented out and a single ``$SET`` is inserted
      just before ``$BATINCLUDE initsys.mod``;
    - comments out ``option LP=...;`` statements so the solver chosen on the
      command line is used (TIMES-NZ hard-codes ``option LP=cplex;``);
    - appends the solve-information block after ``$BATINCLUDE maindrv.mod``;
    - puts the M1.3 input checkpoint (``execute_unload 'tjl_input.gdx'`` under
      ``$IF SET TJL_CHECKPOINTS``) just before ``$BATINCLUDE maindrv.mod``;
    - in the pre-solve run (override ``SOLVE_NOW NO``) of a run that sets SENSIS
      YES, puts ``$ONIMPLICITASSIGN`` just before ``$BATINCLUDE maindrv.mod``:
      SENSIS sets STAGES to ``Yes`` (maindrv.mod L34), so maindrv.mod L110 takes
      solve.stc, whose L7 (case-exact ``$IF NOT %STAGES%==YES``) compiles the
      report file rptlite.rpt; with no SOLVE statement compiled (solve.mod L22)
      its solution levels are never assigned, which GAMS stops on (error 141)
      before any checkpoint is written. The directive only turns that check off.

    Overrides only reach ``$SET`` lines in the run file itself, not in files it
    includes (for example a scenario file).
    """
    overrides = dict(overrides or {})
    report = PatchReport()
    newline = "\r\n" if "\r\n" in text else "\n"
    lines = text.splitlines()

    # 1. extension tag on initmty.mod
    i = _find_unique(lines, _INITMTY, "$BATINCLUDE initmty.mod")
    m = _INITMTY.match(lines[i])
    args = m.group("args").split()
    if EXTENSION_TAG.lower() not in (a.lower() for a in args):
        if len(args) >= 6:
            raise RunFileError("initmty.mod already has 6 extension arguments; cannot add TJLREF")
        args.append(EXTENSION_TAG)
    lines[i] = m.group("head") + " " + " ".join(args)
    report.extension_line = lines[i].strip()

    # 2. switch overrides
    for name, value in overrides.items():
        pat = _set_line(name)
        for j, ln in enumerate(lines):
            if not _COMMENT.match(ln) and pat.match(ln):
                lines[j] = f"{MARK} overridden: {ln.strip()}"
        k = _find_unique(lines, _INITSYS, "$BATINCLUDE initsys.mod")
        lines.insert(k, f"$SET {name} {value}")
        lines.insert(k, f"{MARK} override")
        report.overrides[name] = str(value)

    # 3. hard-coded solver choice
    if strip_lp_option:
        for j, ln in enumerate(lines):
            if _OPTION_LP.match(ln):
                report.removed_lp_options.append(ln.strip())
                lines[j] = f"{MARK} removed: {ln.strip()}"

    # 4. solve information after maindrv
    k = _find_unique(lines, _MAINDRV, "$BATINCLUDE maindrv.mod")
    report.solveinfo_after = lines[k].strip()
    block = SOLVEINFO_BLOCK.format(mark=MARK).splitlines()
    lines[k + 1:k + 1] = block

    # 5. input checkpoint before maindrv
    report.input_before = lines[k].strip()
    lines[k:k] = INPUT_BLOCK.format(mark=MARK).splitlines()

    # 6. the pre-solve run of a SENSIS run: no error 141 for the report's levels (docstring)
    sensis = _set_line("SENSIS")
    if str(overrides.get("SOLVE_NOW", "")).upper() == "NO" and any(
            not _COMMENT.match(ln) and sensis.match(ln) and ln.split()[-1].strip("'\"").upper() == "YES" for ln in lines):
        k = _find_unique(lines, _MAINDRV, "$BATINCLUDE maindrv.mod")
        lines[k:k] = [f"{MARK} pre-solve run of a SENSIS run: rptlite.rpt in solve.stc L7 has no solve", "$ONIMPLICITASSIGN"]
        report.implicit_assign = True

    return newline.join(lines) + newline, report


def build_dd_run(template: str, dd_files: list[str], run_name: str) -> str:
    """Fill the standard DD run template (adapted from xl2times' gams_scaffold).

    ``$BATINCLUDE output.dd`` is replaced by one ``$BATINCLUDE <f>.dd`` per entry
    of ``dd_files``, in order; ``ts.dd`` and ``milestonyr.dd`` are already in
    the template.
    """
    out = []
    found = 0
    for ln in template.splitlines():
        if ln.strip().lower() == "$batinclude output.dd":
            found += 1
            for f in dd_files:
                f = f[:-3] if f.lower().endswith(".dd") else f
                out.append(f"$BATINCLUDE {f}.dd")
        else:
            out.append(ln.replace("{RUN_NAME}", run_name))
    if found != 1:
        raise RunFileError("template must contain exactly one '$BATINCLUDE output.dd' line")
    return "\n".join(out) + "\n"
