"""Produce GAMS reference dumps for TIMES.jl parity tests.

For each test model and variant this runs TIMES v4.9.8 under GAMS twice and
writes, under ``<out>/<model>/<variant>/``:

    manifest.json   provenance, settings, timings, solve information
    ppm/            all symbols after preprocessing        (layer 1)
    coef/           all symbols after coefficients          (layer 1)
    presolve/       all symbols just before SOLVE          (model input, M1.1)
    input/, init/,  M1.3 checkpoints, from the pre-solve run: the state before
    prep/, prelv/   maindrv.mod, after init_ext (maindrv.mod L55), at prep_ext
                    (preppm.mod L217) and at pp_prelv (ppmain.mod L615)
    postsolve/      all symbols after the SOLVE, before the reports (solve.mod L44):
                    the solution and the state the report code reads (layer 4 input)
    final/          all symbols at the end of the run       (layers 3-4)
    vd/             gdx2veda's files from the end-of-run GDX (.vd, .vde, .vds; layer 4)
    matrix/         CONVERT DumpGDX + DictMap               (layer 2)
    steps/<k>/      stepped (myopic) runs only: final/, matrix/ and
                    matrix_dictmap/ of step k, in place of matrix/
    raw/            CONVERT dictionary and MPS, listings, logs, profile, and
                    each run's patched run file (tjl_<run>.run)

Run 1 solves with the reference solver (CPLEX by default) and dumps through
the TJLREF hooks; a pre-solve run (SOLVE_NOW=NO) dumps the state the equations
are generated from and the M1.3 checkpoints; the last run calls CONVERT to export
the scalar model. Every extra solver in ``--solvers`` adds one more solve run
(final dump only).

A stepped run (TIMESTEP or FIXBOH) solves one model per step in the loop of
solve.stp, each built on the levels of the step before. The first solve run
dumps every symbol and a point file after each step; the CONVERT run exports
each step's model and then loads that step's point, so its next step is the
solve run's (reference/gams/www_in.cgi, www_out.cgi).

postsolve/, final/ and vd/ come from one GAMS process, the first solve run (the
other solvers' runs give final_<solver>/ and vd_<solver>/): layer 4 feeds
postsolve/ to TIMES.jl's report code and compares the result with final/ and the
.vd file, so the three must hold the same optimum. There is no ``--only`` pass
for them; a reference made before harness 0.3.10 gets them by a full rerun.
A stepped, stochastic (STAGES, SENSIS, SPINES) or MACRO run has no postsolve/
(``postsolve_skipped`` in the manifest says why; www_out.cgi), and a stochastic
or MACRO run no vd/ (``vd_skipped``).

``--only presolve`` runs just the pre-solve run and adds its dumps to an existing
reference (the manifest's other runs and dumps are kept); where the reference
has no ppm/ or coef/ yet, the pre-solve run writes those too. It needs no solve,
so it works for every model under the GAMS demo licence.

``--only convert`` runs just the CONVERT run (``matrix/``, ``matrix_dictmap/``
and ``raw/tjl_model.mps.gz``) and adds it to a reference in the same way; it
needs no solve, but CONVERT generates the model, so it needs a licence for the
model's size. ``--only presolve,convert`` runs both.

Example (from the TIMES.jl repository root):

    python reference/python/make_reference.py \\
        --suite reference/suite.toml --out ../timesjl-reference \\
        --root times_source=../TIMES_model --root times_demo=../TIMES_Demo \\
        --model TIMES_Demo-demo12
"""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))

from runfile import build_dd_run, patch_run  # noqa: E402
from runlimits import (DEFAULT_RAM_GB, GamsWatch, PoolRun, default_max_parallel, default_pool,  # noqa: E402
                       default_slot_dir, limit_threads, model_threads, runfile_solves_once, threads_override)
from gdx2arrow import convert_gdx, gams_system_directory  # noqa: E402

HARNESS_VERSION = "0.3.10"  # 0.3.10 (27 Nov 2026): M1.6, postsolve/ (the solution before the reports, www_out.cgi) and vd/ (gdx2veda's files); 0.3.9 (26 Nov 2026): the run pool (runlimits.py: thread classes, phases, peak RAM); 0.3.8 (26 Nov 2026): TIMES v4.9.8; a --only pass refuses a reference made with another TIMES commit; 0.3.7 (20 Nov 2026): $ONIMPLICITASSIGN in the pre-solve run of a SENSIS run (runfile.py); 0.3.6 (19 Nov 2026): work_files, files copied into the work folder (the base prices of elastic demand); 0.3.5 (15 Nov 2026): parse_solves reads MODEL STATISTICS with "N projected"; 0.3.4 (14 Nov 2026): steps/<k>/ of stepped runs (www_in.cgi, www_out.cgi); 0.3.3 (14 Nov 2026): equ/, the checkpoint of stepped runs (equ_ext.tjlref); 0.3.2 (9 Nov 2026): raw/tjl_presolve_qa_check.log; 0.3.1 (5 Nov 2026): --only convert; 0.3.0 (31 Oct 2026): M1.3 checkpoints, --only presolve; 0.2.4 (29 Oct 2026): run limits (threads, parallel runs); 0.2.3: model overrides; 0.2.2: raw/tjl_<run>.run; 0.2.1: extra_dd_dirs; 0.2.0: pre-solve run
EXPECTED_TIMES_VERSION = "4.9.8"  # v4.9.7 @ d9a6a25 until 26 Nov 2026 (CLAUDE.md, Baseline)
EXPECTED_TIMES_COMMIT = "7064680"
VARIANTS = {"reduce_off": {"REDUCE": "NO"}, "as_run": {}}
# M1.3 checkpoints in execution order (tjl_<name>.gdx -> <name>/), dumped by the
# pre-solve run with --TJL_CHECKPOINTS=1: runfile.py INPUT_BLOCK (before
# maindrv.mod), reference/gams/init_ext.tjlref, prep_ext.tjlref, pp_prelv.tjlref.
# ppm/ (ppm_ext.tjlref) closes the last segment.
CHECKPOINTS = ["input", "init", "prep", "prelv"]
# A stepped (myopic) run (TIMESTEP or FIXBOH) has one more, equ/ (equ_ext.tjlref: after eqmain.mod
# and the extensions' equ_ext, maindrv.mod L79-80). Its presolve/ is not a pre-solve state: with
# SOLVE_NOW=NO the run still goes through the loop of solve.stp (maindrv.mod L109-113), every step
# without a solve, so the end-of-run dump holds the state after the last step.
STEPPED_CHECKPOINT = "equ"
# The steps of a stepped run (harness 0.3.4). TIMES includes www_in.cgi (maindrv.mod L50) and, after
# every SOLVE, www_out.cgi (solve.mod L44) when GAMS_CGI is WWW; the harness's two files act only
# when %STEPPED% is set, so GAMS decides whether a run is stepped and every other run is unchanged.
# DUMP (the first solve run): after the SOLVE of step k, tjl_step<k>.gdx (every symbol) and the point
# file <model>_p<k>.gdx (OPTION SAVEPOINT=2). LOAD (the CONVERT run): CONVERT returns no solution, so
# after step k the point of that step is loaded, and step k+1 reads its own option file (OPTFILEID).
STEP_DUMP_FLAGS = ["--GAMS_CGI=WWW", "--TJL_STEPS=DUMP"]
STEP_LOAD_FLAGS = ["--GAMS_CGI=WWW", "--TJL_STEPS=LOAD"]
# M1.6 (harness 0.3.10; James, 27 Nov 2026, m16-q2): the solution before GAMS's report code runs.
# The first solve run gets POSTSOLVE_FLAG with --GAMS_CGI=WWW, and www_out.cgi (solve.mod L44: after
# the SOLVE of L37 and its status check of L41; the next statements executed are the reports',
# maindrv.mod L120) writes every symbol to tjl_postsolve.gdx -> postsolve/. GAMS decides when that
# point is not the state the reports read and writes the reason to tjl_postsolve_skip.txt instead:
POSTSOLVE_FLAG = "--TJL_POSTSOLVE=1"
POSTSOLVE_SKIPS = {
    "stepped": "TIMESTEP or FIXBOH: solve.stp changes levels and marginals after its last SOLVE "
               "(L299-301, L325-330); each step's solution is in steps/<k>/final",
    "stages": "STAGES, SENSIS or SPINES: solve.stc has several SOLVEs, and SENSIS reports after each one (L56, L86)",
    "macro": "MACRO (YES, MSA, CSA or MLF): its own solves and reports (rptmain.tm, rpt_ext.msa, rpt_ext.mlf)",
    "ecb": "ECB (BENCOST): rpt_ext.ecb L67 solves again after the reports, which would replace the dump",
}
# The Veda files (m16-q2 b). No file of the TIMES source calls gdx2veda: it is run after GAMS, on the
# end-of-run GDX, with times2veda.vdd of the TIMES source. The harness does that for each solve run's
# tjl_final.gdx. Not for a stochastic run (which of times2veda.vdd and times2veda_stc.vdd applies
# to STAGES, SENSIS and SPINES is not in the TIMES source) or a MACRO run.
VDD_FILE = "times2veda.vdd"
VD_SKIPS = ("stages", "macro")


def optfile_name(solver: str, k: int) -> str:
    """The option file GAMS reads for <model>.optfile = k: <solver>.opt, .op2 to .op9, .o10 to .o99, .100 to .999."""
    if not 1 <= k <= 999:
        raise ValueError(f"no option file number {k}")
    ext = "opt" if k == 1 else f"op{k}" if k < 10 else f"o{k}" if k < 100 else str(k)
    return f"{solver.lower()}.{ext}"


def step_convert_opt(base: str, k: int) -> str:
    """convert.opt for step k of a stepped run: the same options, each output file named for the step
    (tjl_matrix.gdx -> tjl_matrix_step<k>.gdx)."""
    return re.sub(r"\btjl_(\w+)\.(gdx|txt|mps)\b", rf"tjl_\1_step{k}.\2", base)


def numbered_files(folder: Path, pattern: str) -> list[Path]:
    """The files of ``folder`` whose name matches ``pattern`` (one group: the number), for 1, 2, ...
    as far as they go without a gap."""
    found = {}
    if folder.is_dir():
        for f in folder.iterdir():
            m = re.fullmatch(pattern, f.name, flags=re.I)
            if m:
                found[int(m.group(1))] = f
    out = []
    while len(out) + 1 in found:
        out.append(found[len(out) + 1])
    return out


def parse_solves(lst: Path) -> list[dict]:
    """One entry per SOLVE of a GAMS listing, in order: rows, columns, nonzeros (MODEL STATISTICS),
    solver status, model status and objective (SOLVE SUMMARY). GAMS adds "N projected" after the
    number of single variables when it moved N starting levels onto their bounds (in a stepped run the
    levels of an earlier step can lie outside a bound by a rounding)."""
    if not lst.exists():
        return []
    text = lst.read_text(errors="replace")
    num = lambda s: int(s.replace(",", ""))  # noqa: E731
    stats = [{"rows": num(r), "columns": num(c), "nonzeros": num(n)} for r, c, n in re.findall(
        r"^MODEL STATISTICS\s+BLOCKS OF EQUATIONS\s+[\d,]+\s+SINGLE EQUATIONS\s+([\d,]+)\s+"
        r"BLOCKS OF VARIABLES\s+[\d,]+\s+SINGLE VARIABLES\s+([\d,]+)(?:[ \t]+[\d,]+[ \t]+projected)?\s+NON ZERO ELEMENTS\s+([\d,]+)", text, flags=re.M)]
    sums = [{"solver_status": int(s), "model_status": int(m), "objective": float(o) if o else None}
            for s, m, o in re.findall(
        r"^\*\*\*\* SOLVER STATUS\s+(\d+)[^\n]*\n\*\*\*\* MODEL STATUS\s+(\d+)[^\n]*\n"
        r"(?:\*\*\*\* OBJECTIVE VALUE\s+(\S+))?", text, flags=re.M)]
    return [{"step": k + 1, **st, **(sums[k] if k < len(sums) else {})} for k, st in enumerate(stats)]


def load_suite(path: Path, roots: dict) -> dict:
    import tomllib

    suite = tomllib.loads(path.read_text())
    merged = {k: str((path.parent / v).resolve()) for k, v in suite.get("roots", {}).items()}
    merged.update(roots)

    def fill(x):
        if isinstance(x, str):
            for k, v in merged.items():
                x = x.replace("{" + k + "}", v)
            if re.search(r"\{[a-z_]+\}", x):
                raise SystemExit(f"unresolved root in '{x}'; pass --root name=path")
            return x
        if isinstance(x, list):
            return [fill(i) for i in x]
        if isinstance(x, dict):
            return {k: fill(v) for k, v in x.items()}
        return x

    models = {m["name"]: m for m in suite["model"]}
    return {"roots": merged, "models": models, "fill": fill}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def check_source(source: Path, allow_other: bool) -> dict:
    first = (source / "initsys.mod").read_text(errors="replace").splitlines()[0]
    m = re.search(r"VERSION\s+([\d.]+)", first)
    version = m.group(1) if m else "?"
    commit = None
    try:
        commit = subprocess.run(["git", "-C", str(source), "rev-parse", "HEAD"], capture_output=True, text=True,
                                check=True).stdout.strip()
    except Exception:
        pass
    ok = version == EXPECTED_TIMES_VERSION and (commit is None or commit.startswith(EXPECTED_TIMES_COMMIT))
    if not ok and not allow_other:
        raise SystemExit(f"TIMES source is v{version} @ {commit}; expected v{EXPECTED_TIMES_VERSION} @ "
                         f"{EXPECTED_TIMES_COMMIT}. Use --allow-other-version to override.")
    return {"version": version, "commit": commit, "path": str(source)}


def check_same_times(out: Path, source_info: dict, label: str) -> None:
    """A reference holds the dumps of one TIMES source. Refuse to extend (--only) or replace
    (a full run) a reference made with another TIMES version or commit: the v4.9.7 references
    stay as they are, and v4.9.8 ones go to another --out folder (harness 0.3.8, 26 Nov 2026)."""
    mf = out / "manifest.json"
    if not mf.exists():
        return
    old = json.loads(mf.read_text()).get("times") or {}
    oc, nc = (old.get("commit") or "")[:7], (source_info.get("commit") or "")[:7]
    same = (oc == nc) if (oc and nc) else (old.get("version") == source_info.get("version"))
    if not same:
        raise SystemExit(f"{label}: the reference in {out} was made with TIMES v{old.get('version')} @ "
                         f"{oc or '?'}; this source is v{source_info.get('version')} @ {nc or '?'}. "
                         f"Write it to another --out folder, or delete that folder first.")


def gams_version_line(lst: Path) -> str:
    if not lst.exists():
        return ""
    for ln in lst.read_text(errors="replace").splitlines()[:5]:
        if "GAMS" in ln:
            return ln.strip()
    return ""


def run_gams(gams: str, workdir: Path, runfile: str, idirs: list[str], solver: str, extra: list[str],
             tag: str, final_gdx: bool, gdx_name: str = "tjl_final", limits: dict | None = None) -> dict:
    limits = limits or {}
    cmd = [gams, runfile]
    cmd += [f"idir{i}={d}" for i, d in enumerate(idirs, start=1)]
    cmd += ["filecase=4", f"LP={solver}", f"o=tjl_{tag}.lst", "lo=2", f"logFile=tjl_{tag}.log",
            "profile=1", f"profileFile=tjl_{tag}_profile.txt", "stepSum=1"]
    if final_gdx:
        cmd.append(f"gdx={gdx_name}")
    if limits.get("threads", 0) > 0:
        cmd.append(f"threads={limits['threads']}")
    cmd += extra
    # The machine-wide run pool (runlimits.py, James, 26 Nov 2026): a run that solves reserves its
    # model's thread class, any other (pre-solve, CONVERT) 1 thread, and the RAM of its last peak.
    # GamsWatch lowers the hold after barrier and records this run's peak RAM. The wait to start is
    # not part of wall_s.
    solves = solver.upper() != "CONVERT" and tag != "presolve"
    hold = limits.get("threads", 0) if solves and limits.get("threads", 0) > 0 else 1
    ram_need = (limits.get("peaks") or {}).get(tag) or DEFAULT_RAM_GB
    single = runfile_solves_once((workdir / runfile).read_text(errors="replace"))
    with PoolRun(f"{workdir.parent.parent.name}/{workdir.parent.name} {tag}", hold, ram_need,
                 pool=limits.get("pool"), max_parallel=limits.get("max_parallel", 0),
                 slot_dir=limits.get("slot_dir")) as run:
        out_f, err_f = workdir / f"tjl_{tag}.stdout", workdir / f"tjl_{tag}.stderr"
        t0 = time.perf_counter()
        with open(out_f, "w") as so, open(err_f, "w") as se:
            proc = subprocess.Popen(cmd, cwd=workdir, stdout=so, stderr=se, text=True)
            watch = GamsWatch(run, workdir / f"tjl_{tag}.log", proc.pid, single_solve=single and solves)
            while proc.poll() is None:
                watch.poll()
                time.sleep(watch.poll_s)
        wall = time.perf_counter() - t0
    tail = lambda f: f.read_text(errors="replace")[-2000:] if f.exists() else ""  # noqa: E731
    return {"command": cmd, "returncode": proc.returncode, "wall_s": round(wall, 3),
            "slot_wait_s": round(run.waited_s, 1), "pool_threads": hold, "pool_phases": watch.phases,
            "peak_ram_gb": round(watch.peak_ram_gb, 2),
            "stdout_tail": tail(out_f), "stderr_tail": tail(err_f)}


def prepare_workdir(work: Path, model: dict, overrides: dict, solver_opts: dict,
                    threads: int = 0) -> tuple[str, dict]:
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    for pattern in ("*.tjlref", "*.cgi"):
        for f in (REPO / "reference" / "gams").glob(pattern):
            shutil.copy(f, work / f.name)
    if model["kind"] == "dd":
        text = build_dd_run((REPO / "reference" / "templates" / "scenario.run").read_text(),
                            model["dd_files"], model["name"])
    else:
        text = Path(model["run_file"]).read_text(errors="replace")
    patched, report = patch_run(text, overrides)
    (work / "tjl_reference.run").write_text(patched)
    # work_files (harness 0.3.6): files a run reads from GAMS's working folder, such as the base prices of
    # elastic demand (com_bprice.gdx, readbprice.mod L8-12), copied in before each run
    for f in model.get("work_files", []):
        shutil.copy(f, work / Path(f).name)
    report = report.__dict__
    for name, path in solver_opts.items():
        opt = Path(path).read_text(errors="replace")
        if threads > 0 and name.lower() != "convert.opt":
            opt, changes = limit_threads(opt, threads)
            if changes:
                report.setdefault("solver_option_changes", {})[name] = changes
        (work / name).write_text(opt)
    return "tjl_reference.run", report


def find_solver_opts(model: dict, solver: str) -> dict:
    opt_dir = model.get("solver_opt_dir")
    if opt_dir:
        p = Path(opt_dir) / f"{solver.lower()}.opt"
        if p.exists():
            return {p.name: p}
    return {}


def convert(gdx: Path, out: Path, sysdir: str | None) -> dict | None:
    if not gdx.exists():
        return None
    m = convert_gdx(gdx, out, system_directory=sysdir)
    return {"symbols": len(m["symbols"]), "dir": out.name}


def read_solveinfo(gdx: Path, sysdir: str | None) -> dict:
    if not gdx.exists():
        return {}
    import gams.transfer as gt

    c = gt.Container(load_from=str(gdx), system_directory=sysdir)
    df = c["TJL_SOLVEINFO"].records
    if df is None:
        return {}
    return {str(r.iloc[0]): float(r["value"]) for _, r in df.iterrows()}


def make_one(args, suite, model_name: str, variant: str, source_info: dict):
    model = suite["fill"](suite["models"][model_name])
    # Switch overrides: the variant's, then the model's own (suite `overrides`,
    # e.g. OBLONG NO for a crafted case), which may not touch the variant's.
    overrides = dict(VARIANTS[variant])
    for k, v in model.get("overrides", {}).items():
        if k.upper() in (x.upper() for x in overrides):
            raise SystemExit(f"{model_name}: suite override {k} clashes with variant {variant}")
        overrides[k.upper()] = str(v)
    out = args.out / model_name / variant
    only = parse_only(getattr(args, "only", None))     # empty: the full reference
    old_manifest = None
    check_same_times(out, source_info, f"{model_name}/{variant}")
    # The run pool (runlimits.py): this model's thread class (suite `threads`, 6 or 12; TIMESJL_THREADS or
    # --threads sets one count for every model) and the peak RAM of each of its runs last time, plus 10%.
    limits = dict(args.limits)
    limits["threads"] = args.limits["threads"] or model_threads(model)
    prior = json.loads((out / "manifest.json").read_text()) if (out / "manifest.json").exists() else {}
    limits["peaks"] = {t: round(1.1 * r["peak_ram_gb"], 1) for t, r in prior.get("runs", {}).items()
                       if r.get("peak_ram_gb")}
    args = argparse.Namespace(**{**vars(args), "limits": limits})
    if only and (out / "manifest.json").exists():
        old_manifest = json.loads((out / "manifest.json").read_text())
    elif out.exists():
        shutil.rmtree(out)
    (out / "raw").mkdir(parents=True, exist_ok=True)
    work_root = args.work / model_name / variant

    if model["kind"] == "dd":
        # extra_dd_dirs: crafted DD files kept in this repo (reference/dd/), searched
        # after dd_dir, so their names must not clash with files there.
        dd_dirs = [model["dd_dir"], *model.get("extra_dd_dirs", [])]
        idirs = [source_info["path"], *dd_dirs]
        inputs = [next((Path(d) / f"{f}.dd" for d in dd_dirs if (Path(d) / f"{f}.dd").exists()),
                       Path(dd_dirs[0]) / f"{f}.dd") for f in ["ts", *model["dd_files"], "milestonyr"]]
    else:
        idirs = [source_info["path"], *model.get("idirs", [])]
        inputs = [Path(model["run_file"])]
    extra = [f"--run_name={model_name}", *model.get("gams_args", [])]

    manifest = {
        "harness_version": HARNESS_VERSION, "model": model_name, "variant": variant, "overrides": overrides,
        "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "host": {"platform": platform.platform(), "machine": platform.machine(), "cpus": os.cpu_count()},
        "times": source_info, "suite_entry": model, "runs": {}, "dumps": {},
        "inputs": {str(p): sha256(p) for p in inputs if p.exists()},
        "limits": {"threads": args.limits["threads"], "pool": args.limits["pool"],
                   "max_parallel": args.limits["max_parallel"]},
    }

    if old_manifest is not None:
        # keep what the reference already has; this pass adds its runs' dumps
        for key in ("runs", "dumps", "patch", "presolve_pass", "convert_pass", "postsolve_skipped", "vd", "vd_skipped"):
            if key in old_manifest:
                manifest[key] = old_manifest[key]
        manifest["harness_version"] = old_manifest.get("harness_version")
        manifest["created_utc"] = old_manifest.get("created_utc")
        for o in only:
            manifest[f"{o}_pass"] = {"harness_version": HARNESS_VERSION,
                                     "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
                                     "host": manifest["host"], "inputs": manifest["inputs"]}
        manifest["host"] = old_manifest.get("host", manifest["host"])
        manifest["inputs"] = old_manifest.get("inputs", manifest["inputs"])
        if old_manifest.get("overrides", overrides) != overrides:
            raise SystemExit(f"{model_name}/{variant}: the reference was made with overrides "
                             f"{old_manifest.get('overrides')}, not {overrides}; rerun it in full")

    # Run 1..n: solves. The first solver also writes the ppm/coef dumps.
    for k, solver in enumerate([] if only else args.solvers):
        tag = f"solve_{solver.lower()}"
        work = work_root / tag
        runfile, report = prepare_workdir(work, model, overrides, find_solver_opts(model, solver),
                                          args.limits["threads"])
        shutil.copy(work / runfile, out / "raw" / f"tjl_{tag}.run")
        manifest["patch"] = report
        extra_k = [*extra, *STEP_DUMP_FLAGS, POSTSOLVE_FLAG] if k == 0 else [*extra, "--TJL_NODUMP=1"]
        print(f"[{model_name}/{variant}] GAMS solve with {solver} ...", flush=True)
        res = run_gams(args.gams, work, runfile, idirs, solver, extra_k, tag, final_gdx=True, limits=args.limits)
        res["gams_version"] = gams_version_line(work / f"tjl_{tag}.lst")
        res["solveinfo"] = read_solveinfo(work / "tjl_solveinfo.gdx", args.sysdir)
        res["solver_options"] = {n: (work / n).read_text() for n in find_solver_opts(model, solver)}
        manifest["runs"][tag] = res
        if k == 0:
            manifest["dumps"]["ppm"] = convert(work / "tjl_ppm.gdx", out / "ppm", args.sysdir)
            manifest["dumps"]["coef"] = convert(work / "tjl_coef.gdx", out / "coef", args.sysdir)
        final_dir = "final" if k == 0 else f"final_{solver.lower()}"
        manifest["dumps"][final_dir] = convert(work / "tjl_final.gdx", out / final_dir, args.sysdir)
        if k == 0:
            keep_steps(work, out, manifest, tag, args.sysdir)
            keep_postsolve(work, out, manifest, args.sysdir)
        keep_vd(args.sysdir, work, out, manifest, "vd" if k == 0 else f"vd_{solver.lower()}",
                Path(source_info["path"]) / VDD_FILE, model_name, args.limits)
        for f in work.glob(f"tjl_{tag}*"):
            shutil.copy(f, out / "raw" / f.name)
        if res["returncode"] != 0:
            print(f"  GAMS returned {res['returncode']}; see {out / 'raw'}", flush=True)

    # Pre-solve state: SOLVE_NOW=NO makes solve.mod L22 skip the SOLVE
    # statement and maindrv.mod L114 skip reporting, so the end-of-run dump is
    # every symbol exactly as equation generation sees it, after eqmain,
    # bndmain, pp_qack and pp_clean (maindrv.mod L79-113, v4.9.7). pp_qack
    # changes sets the equations use (e.g. RTP_VNTBYR, RTPCS_VARF), so this,
    # not coef/, is the input for building the model from GAMS data. No model
    # is generated, so demo-licence size limits do not apply.
    # The same run writes the M1.3 checkpoints (TJL_CHECKPOINTS, CHECKPOINTS
    # above). In a --only presolve pass it also writes ppm/ and coef/ where the
    # reference has none. A --only pass runs only the runs it names.
    if not only or "presolve" in only:
        presolve_run(args, model, overrides, idirs, extra, out, work_root, manifest, model_name, variant,
                     ppm_coef_here=bool(only) and not ((out / "ppm").is_dir() and (out / "coef").is_dir()))
    if only and "convert" not in only:
        return finish(out, manifest, model_name, variant)
    convert_run(args, model, overrides, idirs, extra, out, work_root, manifest, model_name, variant)
    return finish(out, manifest, model_name, variant)


def keep_steps(work: Path, out: Path, manifest: dict, tag: str, sysdir: str | None) -> int:
    """The steps of a stepped run, after its first solve run: steps/<k>/final (every symbol after the
    SOLVE of step k, tjl_step<k>.gdx) and raw/tjl_point<k>.gdx (GAMS's point file of that SOLVE, which
    the CONVERT run loads). Nothing for a run that is not stepped."""
    dumps = numbered_files(work, r"tjl_step(\d+)\.gdx")
    points = numbered_files(work, r"(?!tjl_).+_p(\d+)\.gdx")
    if not dumps:
        return 0
    if len(points) != len(dumps):
        raise SystemExit(f"{work}: {len(dumps)} step dumps but {len(points)} point files")
    for k, (d, p) in enumerate(zip(dumps, points), start=1):
        manifest["dumps"][f"steps/{k}/final"] = convert(d, out / "steps" / str(k) / "final", sysdir)
        shutil.copy(p, out / "raw" / f"tjl_point{k}.gdx")
    manifest["steps"] = len(dumps)
    manifest["runs"][tag]["steps"] = parse_solves(work / f"tjl_{tag}.lst")
    return len(dumps)


def keep_postsolve(work: Path, out: Path, manifest: dict, sysdir: str | None) -> str | None:
    """postsolve/ after the first solve run: every symbol at solve.mod L44 (tjl_postsolve.gdx, written
    by www_out.cgi), or, where GAMS wrote tjl_postsolve_skip.txt instead, ``postsolve_skipped`` in the
    manifest with the reason (POSTSOLVE_SKIPS) and no dump. Returns the reason, None for a dump. A run
    with neither (it ended before its SOLVE) has a missing dump, so the reference ends with CHECK."""
    note = work / "tjl_postsolve_skip.txt"
    if note.exists():
        reason = note.read_text(errors="replace").strip().lower()
        manifest["postsolve_skipped"] = {"reason": reason, "why": POSTSOLVE_SKIPS.get(reason, "")}
        return reason
    manifest["dumps"]["postsolve"] = convert(work / "tjl_postsolve.gdx", out / "postsolve", sysdir)
    return None


def vd_records(path: Path) -> int:
    """The records of one of gdx2veda's files: its lines, less the empty ones and the header lines
    (``*`` first) of a .vd file."""
    with open(path, errors="replace") as f:
        return sum(1 for ln in f if ln.strip() and not ln.startswith("*"))


def keep_vd(sysdir: str | None, work: Path, out: Path, manifest: dict, name: str, vdd: Path, run_name: str,
            limits: dict | None = None) -> dict | None:
    """<name>/ (vd/, vd_<solver>/): the files gdx2veda writes from a solve run's end-of-run GDX:
    ``gdx2veda tjl_final.gdx <TIMES source>/times2veda.vdd <run name>`` (its usage text), run in its own
    folder and kept whole (<run name>.vd the values, .vde the descriptions of the elements, .vds the
    set memberships). The manifest's ``vd.<name>`` records the command, the return code, the SHA-256
    of the .vdd file and each file's size and records. Nothing for a run whose ``postsolve_skipped``
    reason is in VD_SKIPS (``vd_skipped``). A run without tjl_final.gdx, a return code other than 0
    or no .vd file ends the reference with CHECK (finish)."""
    reason = (manifest.get("postsolve_skipped") or {}).get("reason")
    if reason in VD_SKIPS:
        manifest["vd_skipped"] = {"reason": reason, "why": "times2veda.vdd is the deterministic layout"}
        return None
    limits = limits or {}
    rec = {"dir": name, "run": run_name, "vdd": vdd.name, "returncode": None, "files": {}}
    manifest.setdefault("vd", {})[name] = rec
    gdx = work / "tjl_final.gdx"
    exe = shutil.which("gdx2veda", path=sysdir) if sysdir else shutil.which("gdx2veda")
    if not gdx.exists() or not vdd.exists() or exe is None:
        rec["error"] = "no tjl_final.gdx" if not gdx.exists() else f"no {vdd}" if not vdd.exists() else "gdx2veda not found"
        return rec
    rec["vdd_sha256"] = sha256(vdd)
    folder = work / name
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir()
    cmd = [exe, str(gdx), str(vdd), run_name]
    # one thread of the run pool: gdx2veda reads the GDX and writes text, without a solver
    with PoolRun(f"{work.parent.parent.name}/{work.parent.name} {name}", 1, 1.0, pool=limits.get("pool"),
                 max_parallel=limits.get("max_parallel", 0), slot_dir=limits.get("slot_dir")):
        proc = subprocess.run(cmd, cwd=folder, capture_output=True, text=True, errors="replace")
    rec.update(command=cmd, returncode=proc.returncode, stdout_tail=proc.stdout[-2000:], stderr_tail=proc.stderr[-2000:])
    dest = out / name
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    for f in sorted(folder.iterdir()):
        shutil.copy(f, dest / f.name)
        rec["files"][f.name] = {"bytes": f.stat().st_size, "records": vd_records(f)}
    return rec


def presolve_run(args, model, overrides, idirs, extra, out, work_root, manifest, model_name, variant, ppm_coef_here):
    """The pre-solve run (comment in make_one): presolve/ and the M1.3 checkpoints, and ppm/, coef/ if asked."""
    tag = "presolve"
    work = work_root / tag
    runfile, _ = prepare_workdir(work, model, {**overrides, "SOLVE_NOW": "NO"}, {})
    shutil.copy(work / runfile, out / "raw" / f"tjl_{tag}.run")
    flags = ["--TJL_CHECKPOINTS=1", *([] if ppm_coef_here else ["--TJL_NODUMP=1"])]
    print(f"[{model_name}/{variant}] GAMS pre-solve state and M1.3 checkpoints ...", flush=True)
    res = run_gams(args.gams, work, runfile, idirs, args.solvers[0], [*extra, *flags], tag,
                   final_gdx=True, gdx_name="tjl_presolve", limits=args.limits)
    res["gams_version"] = gams_version_line(work / f"tjl_{tag}.lst")
    manifest["runs"][tag] = res
    manifest["dumps"]["presolve"] = convert(work / "tjl_presolve.gdx", out / "presolve", args.sysdir)
    for name in CHECKPOINTS:
        manifest["dumps"][name] = convert(work / f"tjl_{name}.gdx", out / name, args.sysdir)
    if (work / f"tjl_{STEPPED_CHECKPOINT}.gdx").exists():
        manifest["dumps"][STEPPED_CHECKPOINT] = convert(work / f"tjl_{STEPPED_CHECKPOINT}.gdx", out / STEPPED_CHECKPOINT,
                                                        args.sysdir)
    if ppm_coef_here:
        manifest["dumps"]["ppm"] = convert(work / "tjl_ppm.gdx", out / "ppm", args.sysdir)
        manifest["dumps"]["coef"] = convert(work / "tjl_coef.gdx", out / "coef", args.sysdir)
    for f in work.glob(f"tjl_{tag}*"):
        shutil.copy(f, out / "raw" / f.name)
    keep_qa_log(work, out / "raw" / f"tjl_{tag}_qa_check.log")


def keep_qa_log(work: Path, dest: Path) -> bool:
    """The QA log (QA_CHECK.LOG, written by pp_qaput.mod) of a run, as GAMS left it: M1.3 change 25b
    compares TIMES.jl's log with it. GAMS writes it lower case under filecase=4."""
    qa = next((f for f in work.iterdir() if f.name.lower() == "qa_check.log"), None)
    if qa is None:
        return False
    shutil.copy(qa, dest)
    return True


def convert_run(args, model, overrides, idirs, extra, out, work_root, manifest, model_name, variant):
    """Last run: CONVERT for the matrix (matrix/, matrix_dictmap/) and the MPS file (raw/tjl_model.mps.gz).

    A stepped run (raw/tjl_point<k>.gdx from its solve run, keep_steps) gets them per step instead:
    steps/<k>/matrix, steps/<k>/matrix_dictmap, raw/tjl_model_step<k>.mps.gz, raw/tjl_dict_step<k>.txt.
    One CONVERT run goes through the loop of solve.stp; each step writes through its own option file
    and then loads the levels GAMS found at that step (www_out.cgi), so the next step's model is the
    solve run's. It has no matrix/ of its own: a stepped run has no single model."""
    tag = "convert"
    work = work_root / tag
    base_opt = REPO / "reference" / "gams" / "convert.opt"
    points = numbered_files(out / "raw", r"tjl_point(\d+)\.gdx")
    runfile, _ = prepare_workdir(work, model, overrides, {} if points else {"convert.opt": base_opt})
    for k, p in enumerate(points, start=1):
        shutil.copy(p, work / p.name)
        (work / optfile_name("convert", k)).write_text(step_convert_opt(base_opt.read_text(), k))
    if points:
        extra = [*extra, *STEP_LOAD_FLAGS]
    shutil.copy(work / runfile, out / "raw" / f"tjl_{tag}.run")
    print(f"[{model_name}/{variant}] GAMS CONVERT ..." + (f" ({len(points)} steps)" if points else ""), flush=True)
    # CONVERT returns model status 14 (no solution), which err_stat.mod L63-69
    # (v4.9.7) turns into an ABORT unless ERR_ABORT=NO (default YES at
    # initsys.mod L174). The matrix dump is written by CONVERT before that
    # check, so disabling the abort only lets the run end cleanly; the model
    # generated is unchanged.
    res = run_gams(args.gams, work, runfile, idirs, "CONVERT", [*extra, "--TJL_NODUMP=1", "--ERR_ABORT=NO"], tag,
                   final_gdx=False, limits=args.limits)
    res["gams_version"] = gams_version_line(work / f"tjl_{tag}.lst")
    res["solveinfo"] = read_solveinfo(work / "tjl_solveinfo.gdx", args.sysdir)
    manifest["runs"][tag] = res
    if points:
        # each step's model must have the size it had in the solve run: the check that the loaded
        # levels gave CONVERT the solve run's models
        res["steps"] = parse_solves(work / f"tjl_{tag}.lst")
        solved = next((r["steps"] for t, r in manifest["runs"].items() if t.startswith("solve_") and r.get("steps")), [])
        size = lambda steps: [(s["rows"], s["columns"], s["nonzeros"]) for s in steps]  # noqa: E731
        res["steps_match_solve"] = bool(solved) and size(solved) == size(res["steps"])
    # (suffix of the work files, folder of the dumps): one pair, or one per step
    for sfx, dest in ([(f"_step{k}", f"steps/{k}/") for k in range(1, len(points) + 1)] if points else [("", "")]):
        manifest["dumps"][f"{dest}matrix"] = convert(work / f"tjl_matrix{sfx}.gdx", out / f"{dest}matrix", args.sysdir)
        manifest["dumps"][f"{dest}matrix_dictmap"] = convert(work / f"tjl_dictmap{sfx}.gdx",
                                                             out / f"{dest}matrix_dictmap", args.sysdir)
        if (work / f"tjl_dict{sfx}.txt").exists():
            shutil.copy(work / f"tjl_dict{sfx}.txt", out / "raw" / f"tjl_dict{sfx}.txt")
        if (work / f"tjl_model{sfx}.mps").exists():
            with open(work / f"tjl_model{sfx}.mps", "rb") as fi, \
                    gzip.open(out / "raw" / f"tjl_model{sfx}.mps.gz", "wb") as fo:
                shutil.copyfileobj(fi, fo)
    for f in work.glob(f"tjl_{tag}*"):
        shutil.copy(f, out / "raw" / f.name)


ONLY_RUNS = ("presolve", "convert")


def parse_only(only: str | None) -> tuple[str, ...]:
    """``--only`` as a tuple of run names (``presolve``, ``convert``); empty for a full reference."""
    if not only:
        return ()
    runs = tuple(dict.fromkeys(x.strip().lower() for x in only.split(",") if x.strip()))
    bad = [x for x in runs if x not in ONLY_RUNS]
    if bad or not runs:
        raise SystemExit(f"--only takes {', '.join(ONLY_RUNS)} or both, comma-separated; not '{only}'")
    return runs


def finish(out: Path, manifest: dict, model_name: str, variant: str) -> str:
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1, default=str))
    missing = [k for k, v in manifest["dumps"].items() if v is None]
    runs = manifest["runs"].values()
    # gdx2veda (harness 0.3.10): each solve run it was called for must have given a .vd file
    missing += [k for k, v in manifest.get("vd", {}).items()
                if v.get("returncode") != 0 or not any(f.lower().endswith(".vd") for f in v.get("files", {}))]
    status = "OK" if (not missing and all(r["returncode"] == 0 for r in runs)
                      and all(r.get("steps_match_solve", True) for r in runs)) else "CHECK"
    print(f"[{model_name}/{variant}] {status}" + (f" (missing: {', '.join(missing)})" if missing else ""), flush=True)
    return status


def check_roots(suite: dict, models: list[str]) -> None:
    """Fail before any GAMS run if a requested model is unknown or needs a --root
    that was not given, so a long batch never stops halfway through."""
    problems = []
    for m in models:
        if m not in suite["models"]:
            problems.append(f"unknown model '{m}'")
            continue
        try:
            suite["fill"](suite["models"][m])
        except SystemExit as e:
            problems.append(f"{m}: {e}")
    if problems:
        raise SystemExit("cannot start:\n  " + "\n  ".join(problems))


def main(argv=None):
    p = argparse.ArgumentParser(description="Produce GAMS reference dumps for TIMES.jl")
    p.add_argument("--suite", type=Path, default=REPO / "reference" / "suite.toml")
    p.add_argument("--out", type=Path, required=True, help="reference output directory")
    p.add_argument("--work", type=Path, default=None, help="scratch directory for GAMS runs (default <out>/_work)")
    p.add_argument("--root", action="append", default=[], help="name=path for {name} placeholders in the suite")
    p.add_argument("--model", action="append", default=[], help="model name(s) from the suite; default all")
    p.add_argument("--tier", choices=["core", "milestone"], default=None,
                   help="without --model: only the models of this suite tier (default: every model)")
    p.add_argument("--variant", action="append", choices=list(VARIANTS), default=[])
    p.add_argument("--solvers", default="CPLEX", help="comma-separated; the first is the reference solver")
    p.add_argument("--gams", default="gams", help="GAMS executable")
    p.add_argument("--allow-other-version", action="store_true")
    p.add_argument("--only", default=None,
                   help="presolve: only the pre-solve run (M1.3 checkpoints, pre-solve dump; ppm/coef where "
                        "missing); convert: only the CONVERT run (matrix, dictionary, MPS); presolve,convert: "
                        "both. Added to an existing reference; no solve")
    # Local run limits: the machine-wide run pool (James, 26 Nov 2026; runlimits.py).
    p.add_argument("--threads", type=int, default=threads_override(),
                   help="solver threads per run, for every model: GAMS threads= and the threads line of solver "
                        "option files (default: each model's class, suite `threads`, 6 or 12; or TIMESJL_THREADS)")
    p.add_argument("--pool", type=int, default=default_pool(),
                   help="threads of the machine-wide run pool, 2 of them kept free (default 48, or TIMESJL_POOL; "
                        "0 disables the pool)")
    p.add_argument("--max-parallel", type=int, default=default_max_parallel(),
                   help="an optional limit on the number of GAMS runs at a time (default 0: none; or "
                        "TIMESJL_MAX_PARALLEL)")
    p.add_argument("--slot-dir", type=Path, default=default_slot_dir(),
                   help="directory of the run pool's ledger files (default <temp>/timesjl-run-slots, or "
                        "TIMESJL_SLOT_DIR)")
    a = p.parse_args(argv)
    parse_only(a.only)
    a.solvers = [s.strip().upper() for s in a.solvers.split(",") if s.strip()]
    a.work = a.work or (a.out / "_work")
    a.limits = {"threads": a.threads, "pool": a.pool, "max_parallel": a.max_parallel, "slot_dir": a.slot_dir}
    a.sysdir = gams_system_directory(a.gams)
    if a.sysdir is None:
        raise SystemExit(f"GAMS executable '{a.gams}' not found; pass --gams <path to gams>")
    roots = dict(r.split("=", 1) for r in a.root)
    roots = {k: str(Path(v).resolve()) for k, v in roots.items()}
    suite = load_suite(a.suite, roots)
    if "times_source" not in suite["roots"]:
        raise SystemExit("pass --root times_source=<path to TIMES_model @ 7064680>")
    source_info = check_source(Path(suite["roots"]["times_source"]), a.allow_other_version)
    models = a.model or [n for n, m in suite["models"].items() if a.tier is None or m.get("tier", "core") == a.tier]
    variants = a.variant or list(VARIANTS)
    check_roots(suite, models)
    results = {}
    for m in models:
        for v in variants:
            results[f"{m}/{v}"] = make_one(a, suite, m, v, source_info)
    print(json.dumps(results, indent=1))
    return 0 if all(s == "OK" for s in results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
