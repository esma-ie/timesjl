"""Summary of a cuOpt GPU-share sweep (scripts/cuopt/sweep.sh).

    python3 scripts/cuopt/sweep_summary.py DIR

Reads DIR/share<p>.json (cuopt_layer3.jl), .gpu.csv and .apps.csv (nvidia-smi
samples), .rc, .seconds and .skipped for every level, and writes:

* DIR/sweep.md: cuOpt's own solve time per run and method at each share, the
  speed-up of the full GPU over each smaller share, whether the objective is
  the same at every share, and what the GPU did during each level;
* DIR/sweep.json: the same numbers, one record per level.

Exit code 1 if no level ran. Standard library only.
"""

from __future__ import annotations

import csv
import json
import re
import statistics
import sys
from pathlib import Path

ICON = {"pass": "✅", "fail": "❌", "skipped": "➖"}
SAME_OBJECTIVE_RTOL = 1e-9


def num(x: str):
    try:
        v = float(x.strip())
    except (ValueError, AttributeError):
        return None  # "[N/A]", "[Not Supported]" (WSL), empty
    return v


def telemetry(stem: Path) -> dict:
    t: dict = {}
    rows = []
    gpu = stem.with_suffix(".gpu.csv")
    if gpu.exists():
        with gpu.open(newline="") as f:
            rows = [r for r in csv.reader(f) if len(r) >= 7]
    cols = {"util": 1, "mem": 2, "mem_total": 3, "sm_clock": 4, "power": 5, "temp": 6}
    vals = {k: [v for v in (num(r[i]) for r in rows) if v is not None] for k, i in cols.items()}
    t["samples"] = len(rows)
    t["util_mean"] = statistics.fmean(vals["util"]) if vals["util"] else None
    t["util_max"] = max(vals["util"]) if vals["util"] else None
    t["mem_peak_mib"] = max(vals["mem"]) if vals["mem"] else None
    t["mem_total_mib"] = max(vals["mem_total"]) if vals["mem_total"] else None
    t["sm_clock_mean"] = statistics.fmean(vals["sm_clock"]) if vals["sm_clock"] else None
    t["sm_clock_min"] = min(vals["sm_clock"]) if vals["sm_clock"] else None
    t["power_mean"] = statistics.fmean(vals["power"]) if vals["power"] else None
    t["temp_max"] = max(vals["temp"]) if vals["temp"] else None
    apps = stem.with_suffix(".apps.csv")
    text = apps.read_text(errors="replace") if apps.exists() else ""
    t["mps_server_seen"] = "nvidia-cuda-mps-server" in text
    return t


def level(stem: Path, share: int) -> dict:
    rec: dict = {"share": share}
    skipped = stem.with_suffix(".skipped")
    if skipped.exists():
        rec["skipped"] = skipped.read_text().strip()
        return rec
    rc = stem.with_suffix(".rc")
    rec["rc"] = int(rc.read_text().strip()) if rc.exists() else None
    sec = stem.with_suffix(".seconds")
    rec["level_seconds"] = num(sec.read_text()) if sec.exists() else None
    js = stem.with_suffix(".json")
    if js.exists():
        d = json.loads(js.read_text())
        rec["meta"] = d.get("meta", {})
        rec["checks"] = d.get("checks", [])
    else:
        rec["meta"], rec["checks"] = {}, []
        rec["error"] = "no report written (see the job log)"
    rec["telemetry"] = telemetry(stem)
    return rec


def per_method(checks: list) -> dict:
    """(run, method) -> one cuOpt solve: time, objective and the worst status over the GAMS optima."""
    out: dict = {}
    for c in checks:
        m = c.get("method")
        if not m:
            continue
        key = (c["run"], m)
        e = out.setdefault(key, {"status": "pass", "seconds": c.get("cuopt_seconds"),
                                 "objective": c.get("julia_objective"), "statuses": []})
        e["statuses"].append(c.get("status"))
    for e in out.values():
        s = e["statuses"]
        e["status"] = "fail" if "fail" in s else "skipped" if all(x == "skipped" for x in s) else "pass"
    return out


def fmt_s(x) -> str:
    return "–" if x is None else f"{x:.2f}" if x < 100 else f"{x:.0f}"


def fmt(x, unit="", nd=0) -> str:
    return "–" if x is None else f"{x:.{nd}f}{unit}"


def main(d: Path) -> int:
    stems = sorted(d.glob("share*.json")) + sorted(d.glob("share*.skipped")) + sorted(d.glob("share*.rc"))
    shares = sorted({int(re.match(r"share(\d+)", p.name).group(1)) for p in stems})
    levels = [level(d / f"share{p}", p) for p in shares]
    ran = [lv for lv in levels if "skipped" not in lv]
    meta = next((lv["meta"] for lv in ran if lv.get("meta")), {})
    full = next((lv for lv in ran if lv["share"] == 100), None)

    tables = {lv["share"]: per_method(lv.get("checks", [])) for lv in ran}
    keys = sorted({k for t in tables.values() for k in t})
    smaller = [p for p in shares if p < 100 and p in tables]

    md = ["## cuOpt GPU-share sweep\n"]
    md.append(f"GPU: {meta.get('gpu', 'unknown')}. cuOpt {meta.get('cuopt_version', '?')}, commit "
              f"`{meta.get('commit', '?')}`, {meta.get('threads', '?')} CPU threads. Levels "
              f"{', '.join(f'{p}%' for p in shares)}, run one at a time. Times are cuOpt's own solve time "
              "(no Julia start-up or model generation).\n")
    if keys:
        head = ["Run", "Method"] + [f"{p}%" for p in shares] + [f"Speed-up {p}%→100%" for p in smaller] + ["Same objective at every share"]
        md.append("| " + " | ".join(head) + " |")
        md.append("|" + " --- |" * len(head))
        for k in keys:
            cells = [k[0], k[1]]
            for p in shares:
                e = tables.get(p, {}).get(k)
                cells.append("skipped" if p not in tables else "–" if e is None else
                             ("–" if e["seconds"] is None else f"{fmt_s(e['seconds'])} s") + f" {ICON.get(e['status'], '')}")
            t100 = (tables.get(100, {}).get(k) or {}).get("seconds")
            for p in smaller:
                tp = (tables[p].get(k) or {}).get("seconds")
                cells.append(f"{tp / t100:.2f}×" if tp and t100 else "–")
            objs = [tables[p][k]["objective"] for p in tables if k in tables[p] and tables[p][k]["objective"] is not None]
            if len(objs) < 2:
                cells.append("–")
            else:
                ref = objs[0]
                dev = max(abs(o - ref) / max(abs(ref), 1e-300) for o in objs)
                cells.append("yes" if dev <= SAME_OBJECTIVE_RTOL else f"no ({dev:.1e})")
            md.append("| " + " | ".join(cells) + " |")
        md.append("\nSpeed-up = time at that share ÷ time at 100%; above 1× means the full GPU is faster.\n")
    else:
        md.append("No solve was recorded.\n")

    md.append("### The GPU during each level\n")
    md.append("| Share | MPS | Level wall s | GPU busy mean / max | GPU memory peak | SM clock mean (min) | Power mean | Temp max | Exit |")
    md.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for lv in levels:
        if "skipped" in lv:
            md.append(f"| {lv['share']}% | skipped: {lv['skipped']} | | | | | | | |")
            continue
        t = lv["telemetry"]
        mps = lv.get("meta", {}).get("mps", "?")
        if mps == "on":
            mps = "on, server seen" if t["mps_server_seen"] else "on, **server not seen**"
        mem = "–" if t["mem_peak_mib"] is None else f"{t['mem_peak_mib']:.0f} of {fmt(t['mem_total_mib'])} MiB"
        busy = "–" if t["util_mean"] is None else f"{t['util_mean']:.0f}% / {t['util_max']:.0f}%"
        clk = "–" if t["sm_clock_mean"] is None else f"{t['sm_clock_mean']:.0f} ({t['sm_clock_min']:.0f}) MHz"
        md.append(f"| {lv['share']}% | {mps} | {fmt(lv.get('level_seconds'), nd=1)} | {busy} | {mem} | {clk} | "
                  f"{fmt(t['power_mean'], ' W')} | {fmt(t['temp_max'], ' °C')} | {lv.get('rc', '–')} |")
    md.append("\n\"GPU busy\" is nvidia-smi's utilisation: the share of time a kernel was running, not the share "
              "of the GPU's SMs in use, so a capped level can still read near 100%. A falling SM clock means "
              "the GPU throttled (heat or power). WSL2 reports no utilisation.\n")

    for lv in ran:
        rep = d / f"share{lv['share']}.md"
        if rep.exists():
            md.append(f"<details><summary>Report at {lv['share']}%</summary>\n")
            md.append(rep.read_text())
            md.append("\n</details>\n")

    (d / "sweep.md").write_text("\n".join(md))
    summary = {"meta": meta, "shares": shares,
               "levels": [{k: v for k, v in lv.items() if k != "checks"} | {"solves": [
                   {"run": k[0], "method": k[1], **{x: e[x] for x in ("status", "seconds", "objective")}}
                   for k, e in sorted(tables.get(lv["share"], {}).items())]} for lv in levels]}
    (d / "sweep.json").write_text(json.dumps(summary, indent=1, default=str))
    if full is None and ran:
        print("note: no 100% level, so no speed-up", file=sys.stderr)
    return 0 if ran else 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: sweep_summary.py DIR")
    sys.exit(main(Path(sys.argv[1])))
