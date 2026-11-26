"""Pack open reference runs for the cuOpt lane on the GitHub GPU runner.

The GitHub runner has no GAMS and cannot see the workstation's reference
folder, so `.github/workflows/nightly-gpu.yml` (manual run, input
`ref_release`) downloads the reference runs it solves from a release of this
repository. This script makes those release assets: one zip per run, holding
only what `scripts/cuopt/cuopt_layer3.jl --ref` reads.

    python scripts/cuopt/make_ref_bundle.py --ref C:\\git\\esma\\timesjl-reference \\
        --sources C:\\git\\esma\\timesjl-sources --out D:\\workspace\\timesjl-cuopt-bundle \\
        OTNYC-s1_nyc_ref OTCGEN-gc_ref ...
    # then, to publish (James's yes for each new set of models: test data, CLAUDE.md):
    python scripts/cuopt/make_ref_bundle.py ... --release cuopt-ref-2026-11-22

Each zip `<model>-reduce_off.zip` holds `<model>/reduce_off/` with
- `presolve/`, `matrix/`, `matrix_dictmap/`, `final/` and any `final_<solver>/`
  (the Arrow dumps the harness wrote);
- `raw/tjl_convert.run` (the run's switches);
- `manifest.json`, cut down to what the cuOpt lane reads: each GAMS run's return
  code and model status, objective and size. Paths, the host, commands and every
  GAMS or solver time are left out (GAMS timings are for the local board only,
  #184 d5);
- `LICENSE` (the model's own licence text) and `NOTICE.md` (source, licence,
  what was derived and how).
A `SHA256SUMS` file lists every zip.

Only models with `redistribute = "public"` in `reference/suite.toml` are
packed; any other model is refused (CLAUDE.md, "Test-model licences").
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tomllib
import urllib.request
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
VARIANT = "reduce_off"
DUMPS = ("presolve", "matrix", "matrix_dictmap")
# {root} of a suite run file -> folder of timesjl-sources (scripts/m14_models.jl SOURCE_DIRS)
SOURCE_DIRS = {"times_demo": "TIMES_Demo", "times_nz_dd": "TIMES-NZ", "otus": "OTUS9r",
               "otcgen": "OTCGEN", "otnyc": "OTNYC"}
KEEP_SOLVEINFO = ("modelstat", "solvestat", "objval", "numequ", "numvar", "numnz")
KEEP_SUITE = ("name", "tier", "source_repo", "licence", "licence_url", "licence_checked", "redistribute", "kind")


def suite_models() -> dict[str, dict]:
    with open(REPO / "reference" / "suite.toml", "rb") as f:
        return {m["name"]: m for m in tomllib.load(f)["model"]}


def lean_manifest(man: dict) -> dict:
    """The manifest without paths, host, commands or timings."""
    runs = {}
    for tag, run in man.get("runs", {}).items():
        r = {"returncode": run.get("returncode")}
        si = run.get("solveinfo")
        if si:
            r["solveinfo"] = {k: si[k] for k in KEEP_SOLVEINFO if k in si}
        if "gams_version" in run:   # "GAMS 54.6.1  20a39885 Oct 24, 2026 ..." -> "GAMS 54.6.1"
            r["gams_version"] = " ".join(run["gams_version"].split()[:2])
        runs[tag] = r
    entry = {k: man["suite_entry"][k] for k in KEEP_SUITE if k in man.get("suite_entry", {})}
    times = {k: man["times"][k] for k in ("version", "commit") if k in man.get("times", {})}
    return {"harness_version": man.get("harness_version"), "model": man["model"], "variant": man["variant"],
            "overrides": man.get("overrides", {}), "times": times, "suite_entry": entry, "runs": runs,
            "note": "cut down by scripts/cuopt/make_ref_bundle.py: no paths, host, commands or timings"}


def licence_text(model: dict, sources: Path) -> str:
    """The model's LICENSE from its timesjl-sources clone, else from the repository named in licence_url."""
    m = re.match(r"\{(\w+)\}", model.get("run_file", ""))
    if m and m.group(1) in SOURCE_DIRS:
        for name in ("LICENSE", "LICENSE.md", "LICENSE.txt"):
            p = sources / SOURCE_DIRS[m.group(1)] / name
            if p.is_file():
                return p.read_text(encoding="utf-8")
    url = model["licence_url"]
    raw = re.sub(r"^https://github\.com/([^/]+/[^/]+)/blob/", r"https://raw.githubusercontent.com/\1/", url)
    if raw == url:
        sys.exit(f"{model['name']}: no LICENSE in its source clone and {url} is not a GitHub file")
    with urllib.request.urlopen(raw, timeout=60) as r:
        return r.read().decode("utf-8")


def notice(model: dict, man: dict) -> str:
    t = man.get("times", {})
    return f"""# {model['name']} ({VARIANT}): GAMS reference dumps for the TIMES.jl cuOpt lane

- Model: {model['source_repo']}
- Licence: {model['licence']} ({model['licence_url']}); the full text is in `LICENSE`.
  These files are derived from the model's data and are shared under the same licence.
- What was derived: the GAMS TIMES model generator (IEA-ETSAP TIMES v{t.get('version', '?')},
  commit {t.get('commit', '?')[:7]}, GPL-3.0) was run on the model's DD files with `$SET REDUCE NO`,
  and its data, LP matrix (GAMS CONVERT) and optimum were written as Arrow files by the
  TIMES.jl reference harness (`reference/README.md` in esma-ie/TIMESjl). Nothing in the model's
  data was changed.
- Used by: `scripts/cuopt/cuopt_layer3.jl --ref` in esma-ie/TIMESjl, run by
  `.github/workflows/nightly-gpu.yml`.
"""


def pack(name: str, model: dict, ref: Path, sources: Path, out: Path) -> Path:
    src = ref / name / VARIANT
    if not (src / "manifest.json").is_file():
        sys.exit(f"{name}: no {src / 'manifest.json'}")
    man = json.loads((src / "manifest.json").read_text(encoding="utf-8"))
    runfile = src / "raw" / "tjl_convert.run"
    if not runfile.is_file():
        sys.exit(f"{name}: no {runfile}")
    if re.search(r"[A-Za-z]:\\", runfile.read_text(encoding="utf-8", errors="replace")):
        sys.exit(f"{name}: {runfile} holds a local path; not packed")
    dumps = list(DUMPS) + sorted(p.name for p in src.iterdir() if p.is_dir() and re.fullmatch(r"final(_\w+)?", p.name))
    for d in dumps:
        if not (src / d).is_dir():
            sys.exit(f"{name}: no {src / d}")
    zpath = out / f"{name}-{VARIANT}.zip"
    tmp = zpath.with_suffix(".zip.part")
    base = f"{name}/{VARIANT}"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        z.writestr(f"{base}/manifest.json", json.dumps(lean_manifest(man), indent=1))
        z.writestr(f"{base}/LICENSE", licence_text(model, sources))
        z.writestr(f"{base}/NOTICE.md", notice(model, man))
        z.write(runfile, f"{base}/raw/tjl_convert.run")
        for d in dumps:
            for f in sorted((src / d).rglob("*")):
                if not f.is_file():
                    continue
                arc = f"{base}/{f.relative_to(src).as_posix()}"
                if f.name == "manifest.json":   # a dump's manifest names the GDX it came from: keep the file name only
                    dm = json.loads(f.read_text(encoding="utf-8"))
                    if "source" in dm:
                        dm["source"] = re.split(r"[\\/]", str(dm["source"]))[-1]
                    z.writestr(arc, json.dumps(dm, indent=1))
                else:
                    z.write(f, arc)
    leaks = private_strings(tmp)
    if leaks:
        tmp.unlink()
        sys.exit(f"{name}: a local path or name is still in {', '.join(leaks[:5])}; not packed")
    tmp.replace(zpath)
    return zpath


PRIVATE = re.compile(rb"(?<![A-Za-z])[A-Za-z]:[\\/]+(git[\\/]|Users|workspace)|\\Users\\|/home/|james", re.IGNORECASE)


def private_strings(zpath: Path) -> list[str]:
    """Members of the zip that hold a local path or the user's name (LICENSE and NOTICE.md are ours)."""
    with zipfile.ZipFile(zpath) as z:
        return [n for n in z.namelist() if not n.endswith(("/LICENSE", "/NOTICE.md")) and PRIVATE.search(z.read(n))]


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 22), b""):
            h.update(b)
    return h.hexdigest()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ref", type=Path, required=True, help="the reference folder (timesjl-reference)")
    ap.add_argument("--sources", type=Path, required=True, help="the pinned model clones (timesjl-sources)")
    ap.add_argument("--out", type=Path, required=True, help="where the zips go")
    ap.add_argument("--release", help="also publish the zips as a pre-release with this tag (gh)")
    ap.add_argument("models", nargs="+")
    a = ap.parse_args()
    suite = suite_models()
    for name in a.models:
        m = suite.get(name)
        if m is None:
            sys.exit(f"{name} is not in reference/suite.toml")
        if m.get("redistribute") != "public":
            sys.exit(f"{name}: redistribute = {m.get('redistribute')!r}, not \"public\"; never packed (CLAUDE.md)")
    a.out.mkdir(parents=True, exist_ok=True)
    zips = []
    for name in a.models:
        z = pack(name, suite[name], a.ref, a.sources, a.out)
        print(f"{z.name}: {z.stat().st_size / 2**20:.0f} MiB", flush=True)
        zips.append(z)
    sums = a.out / "SHA256SUMS"
    old = {}
    if sums.is_file():   # keep the lines of zips made earlier into the same folder
        for line in sums.read_text().splitlines():
            h, f = line.split(maxsplit=1)
            old[f.lstrip("*")] = h
    old.update({z.name: sha256(z) for z in zips})
    sums.write_text("".join(f"{h}  {f}\n" for f, h in sorted(old.items())))
    print(f"wrote {sums}")
    if a.release:
        gh = shutil.which("gh") or sys.exit("gh not found")
        title = f"cuOpt lane: open reference runs ({a.release})"
        body = ("GAMS reference dumps (reduce_off) of the open test models, for the cuOpt lane on the GitHub "
                "GPU runner (`.github/workflows/nightly-gpu.yml`, input `ref_release`). Made by "
                "`scripts/cuopt/make_ref_bundle.py`. Each zip carries its model's licence (`LICENSE`) and a "
                "`NOTICE.md`. Not a TIMES.jl release.")
        exists = subprocess.run([gh, "release", "view", a.release], capture_output=True).returncode == 0
        if not exists:
            subprocess.run([gh, "release", "create", a.release, "--prerelease", "--latest=false", "--title", title,
                            "--notes", body, "--target", "main"], check=True)
        subprocess.run([gh, "release", "upload", a.release, "--clobber", *map(str, zips), str(sums)], check=True)
        print(f"uploaded to release {a.release}")


if __name__ == "__main__":
    main()
