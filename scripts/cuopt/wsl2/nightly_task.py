"""Windows side of the local cuOpt nightly (James's workstation).

Run by the scheduled task that register_nightly.ps1 creates:

    python scripts\\cuopt\\wsl2\\nightly_task.py [--distro Ubuntu-26.04] [--dir ~/git/TIMESjl]

It reserves threads in the workstation's run pool (reference/python/runlimits.py,
the pool make_reference.py uses): 12 for the whole night, the cap on cuOpt's
CPU side (CLAUDE.md), and waits until they are free. Holding them, it runs
scripts/cuopt/wsl2/nightly_local.sh inside WSL2 and appends
everything to %LOCALAPPDATA%\\timesjl\\cuopt-nightly.log.

The reservation is made on the Windows side because WSL processes cannot
hold one: the pool's ledger records a Windows process id. Standard library only.
"""

from __future__ import annotations

import argparse
import datetime
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "reference" / "python"))
from runlimits import PoolRun  # noqa: E402


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--distro", default="Ubuntu-26.04", help="WSL distribution (default Ubuntu-26.04)")
    ap.add_argument("--dir", default="~/git/TIMESjl", help="the TIMESjl checkout inside WSL (default ~/git/TIMESjl)")
    ap.add_argument("--wsl", default="wsl.exe", help=argparse.SUPPRESS)  # tests pass a stand-in
    ap.add_argument("--log", default=None, help="log file (default %%LOCALAPPDATA%%\\timesjl\\cuopt-nightly.log)")
    ap.add_argument("--threads", type=int, default=12,
                    help="threads reserved in the run pool for the night (default 12, cuOpt's CPU-side cap)")
    ap.add_argument("--ram-gb", type=float, default=16.0, help="RAM reserved for the night (default 16 GB)")
    ap.add_argument("--slot-timeout-hours", type=float, default=6.0,
                    help="give up if the run pool has no room in this time (default 6)")
    a = ap.parse_args(argv)

    log = Path(a.log) if a.log else Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "timesjl" / "cuopt-nightly.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    script = f"bash {a.dir.rstrip('/')}/scripts/cuopt/wsl2/nightly_local.sh"
    cmd = [a.wsl, "-d", a.distro, "--", "bash", "-lc", script]

    with log.open("a", encoding="utf-8") as f:
        def say(msg: str) -> None:
            f.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M:%S} [task] {msg}\n")
            f.flush()

        try:
            with PoolRun("cuOpt nightly (WSL2)", a.threads, a.ram_gb, timeout_s=a.slot_timeout_hours * 3600) as slot:
                where = f"run pool {slot.path.name}, {a.threads} threads" if slot.path else "no run pool"
                say(f"{where} (waited {slot.waited_s:.0f} s); running {' '.join(cmd)}")
                env = dict(os.environ, WSL_UTF8="1")
                try:
                    p = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, env=env)
                except OSError as e:
                    say(f"could not start WSL: {e}")
                    return 2
                say(f"exit code {p.returncode}")
                return p.returncode
        except TimeoutError as e:
            say(str(e))
            return 3


if __name__ == "__main__":
    sys.exit(main())
