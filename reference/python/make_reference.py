"""Produce GAMS reference dumps for TIMES.jl parity tests.

For each test model and variant this runs TIMES v4.9.7 under GAMS twice and
writes, under ``<out>/<model>/<variant>/``:

    manifest.json   provenance, settings, timings, solve information
    ppm/            all symbols after preprocessing        (layer 1)
    coef/           all symbols after coefficients          (layer 1)
    presolve/       all symbols just before SOLVE          (model input, M1.1)
    input/, init/,  M1.3 checkpoints, from the pre-solve run: the state before
    prep/, prelv/   maindrv.mod, after init_ext (maindrv.mod L55), at prep_ext
                    (preppm.mod L217) and at pp_prelv (ppmain.mod L615)
    final/          all symbols at the end of the run       (layers 3-4)
    matrix/         CONVERT DumpGDX + DictMap               (layer 2)
    raw/            CONVERT dictionary and MPS, listings, logs, profile, and
                    each run's patched run file (tjl_<run>.run)

Run 1 solves with the reference solver (CPLEX by default) and dumps through
the TJLREF hooks; a pre-solve run (SOLVE_NOW=NO) dumps the state the equations
are generated from and the M1.3 checkpoints; the last run calls CONVERT to export
the scalar model. Every extra solver in ``--solvers`` adds one more solve run
(final dump only).

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
from runlimits import RunSlot, default_max_parallel, default_slot_dir, default_threads, limit_threads  # noqa: E402
from gdx2arrow import convert_gdx, gams_system_directory  # noqa: E402

HARNESS_VERSION = "0.3.2"  # 0.3.2 (9 Nov 2026): raw/tjl_presolve_qa_check.log; 0.3.1 (5 Nov 2026): --only convert; 0.3.0 (31 Oct 2026): M1.3 checkpoints, --only presolve; 0.2.4 (29 Oct 2026): run limits (threads, parallel runs); 0.2.3: model overrides; 0.2.2: raw/tjl_<run>.run; 0.2.1: extra_dd_dirs; 0.2.0: pre-solve run
EXPECTED_TIMES_VERSION = "4.9.7"
EXPECTED_TIMES_COMMIT = "d9a6a25"
VARIANTS = {"reduce_off": {"REDUCE": "NO"}, "as_run": {}}
# M1.3 checkpoints in execution order (tjl_<name>.gdx -> <name>/), dumped by the
# pre-solve run with --TJL_CHECKPOINTS=1: runfile.py INPUT_BLOCK (before
# maindrv.mod), reference/gams/init_ext.tjlref, prep_ext.tjlref, pp_prelv.tjlref.
# ppm/ (ppm_ext.tjlref) closes the last segment.
CHECKPOINTS = ["input", "init", "prep", "prelv"]


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
    # one machine-wide run slot per GAMS run (runlimits.py); the wait is not part of wall_s
    with RunSlot(f"{workdir.name} {runfile}", limits.get("max_parallel", 0), limits.get("slot_dir")) as slot:
        t0 = time.perf_counter()
        proc = subprocess.run(cmd, cwd=workdir, capture_output=True, text=True)
        wall = time.perf_counter() - t0
    return {"command": cmd, "returncode": proc.returncode, "wall_s": round(wall, 3),
            "slot_wait_s": round(slot.waited_s, 1),
            "stdout_tail": proc.stdout[-2000:], "stderr_tail": proc.stderr[-2000:]}


def prepare_workdir(work: Path, model: dict, overrides: dict, solver_opts: dict,
                    threads: int = 0) -> tuple[str, dict]:
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    for f in (REPO / "reference" / "gams").glob("*.tjlref"):
        shutil.copy(f, work / f.name)
    if model["kind"] == "dd":
        text = build_dd_run((REPO / "reference" / "templates" / "scenario.run").read_text(),
                            model["dd_files"], model["name"])
    else:
        text = Path(model["run_file"]).read_text(errors="replace")
    patched, report = patch_run(text, overrides)
    (work / "tjl_reference.run").write_text(patched)
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
        "limits": {"threads": args.limits["threads"], "max_parallel": args.limits["max_parallel"]},
    }

    if old_manifest is not None:
        # keep what the reference already has; this pass adds its runs' dumps
        for key in ("runs", "dumps", "patch", "presolve_pass", "convert_pass"):
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
        extra_k = extra if k == 0 else [*extra, "--TJL_NODUMP=1"]
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
    """Last run: CONVERT for the matrix (matrix/, matrix_dictmap/) and the MPS file (raw/tjl_model.mps.gz)."""
    tag = "convert"
    work = work_root / tag
    runfile, _ = prepare_workdir(work, model, overrides, {"convert.opt": REPO / "reference" / "gams" / "convert.opt"})
    shutil.copy(work / runfile, out / "raw" / f"tjl_{tag}.run")
    print(f"[{model_name}/{variant}] GAMS CONVERT ...", flush=True)
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
    manifest["dumps"]["matrix"] = convert(work / "tjl_matrix.gdx", out / "matrix", args.sysdir)
    manifest["dumps"]["matrix_dictmap"] = convert(work / "tjl_dictmap.gdx", out / "matrix_dictmap", args.sysdir)
    if (work / "tjl_dict.txt").exists():
        shutil.copy(work / "tjl_dict.txt", out / "raw" / "tjl_dict.txt")
    if (work / "tjl_model.mps").exists():
        with open(work / "tjl_model.mps", "rb") as fi, gzip.open(out / "raw" / "tjl_model.mps.gz", "wb") as fo:
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
    status = "OK" if not missing and all(r["returncode"] == 0 for r in manifest["runs"].values()) else "CHECK"
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
    # Local run limits (James, 29 Oct 2026; runlimits.py). 0 disables a limit.
    p.add_argument("--threads", type=int, default=default_threads(),
                   help="solver threads per run: GAMS threads= and the threads line of solver option files "
                        "(default 12, or TIMESJL_THREADS)")
    p.add_argument("--max-parallel", type=int, default=default_max_parallel(),
                   help="GAMS runs at a time on this machine, across harness processes (default 4, or "
                        "TIMESJL_MAX_PARALLEL)")
    p.add_argument("--slot-dir", type=Path, default=default_slot_dir(),
                   help="directory of the shared run-slot files (default <temp>/timesjl-run-slots, or "
                        "TIMESJL_SLOT_DIR)")
    a = p.parse_args(argv)
    parse_only(a.only)
    a.solvers = [s.strip().upper() for s in a.solvers.split(",") if s.strip()]
    a.work = a.work or (a.out / "_work")
    a.limits = {"threads": a.threads, "max_parallel": a.max_parallel, "slot_dir": a.slot_dir}
    a.sysdir = gams_system_directory(a.gams)
    if a.sysdir is None:
        raise SystemExit(f"GAMS executable '{a.gams}' not found; pass --gams <path to gams>")
    roots = dict(r.split("=", 1) for r in a.root)
    roots = {k: str(Path(v).resolve()) for k, v in roots.items()}
    suite = load_suite(a.suite, roots)
    if "times_source" not in suite["roots"]:
        raise SystemExit("pass --root times_source=<path to TIMES_model @ d9a6a25>")
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
