"""Start one command inside the machine-wide run pool (James, 26 Nov 2026; runlimits.py).

For the runs that do not go through make_reference.py: TIMES.jl's Julia scripts first of all.

    python reference/python/pool_run.py --threads 6 --label "demo12 from DD" -- julia --project=. scripts/run_dd.jl <run file> --solve
    python reference/python/pool_run.py --model TIMES_Demo-demo12 -- julia --project=. scripts/m13_gate.jl <refdir> TIMES_Demo-demo12 --solve

What it does, in the order of the rule:

* It reserves the run's thread class in the pool before the command starts, so the reservation
  covers model generation too: ``--threads``, or the class of ``--model`` (``threads`` in
  reference/suite.toml or reference/crafted.toml, 6 or 12). It waits until the class fits (reserved
  threads, measured load and RAM, as for any run of the pool).
* It starts the command with ``TIMESJL_THREADS`` set to the class (the Julia scripts give it to
  HiGHS) and ``TIMESJL_POOL_MARKERS=1``, and passes its standard output on, line by line and
  unchanged; the error output and the input are the command's own.
* It lowers the hold when the command prints a marker line on its standard output:

      [timesjl-pool] phase=after-barrier     ->  AFTER_BARRIER_THREADS threads
      [timesjl-pool] phase=reporting         ->  1 thread

  A marker never raises the hold, and any other line changes nothing. A command that prints no
  marker (several solves, a stepped run, a solve whose phases it cannot tell) keeps its class to
  its end. TIMES.jl prints the markers only under this launcher (``TIMES.pool_phase``, src/pool.jl).
* It releases the reservation when the command ends, also after Ctrl-C, and returns the command's
  exit code. Its own exit codes: 2 (wrong arguments, or the command could not be started) and 3
  (no room in the pool within ``--timeout-hours``).

Its own messages go to the error output, starting ``[pool_run]``: the reservation, and at the end
the exit code, the phases and the peak RAM of the command and its child processes (``--quiet``
leaves them out; ``--record`` writes them to a JSON file with make_reference.py's manifest keys).

``TIMESJL_POOL`` is the size of the pool (runlimits.default_pool), which is why the markers have
their own variable.

Standard library only.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from runlimits import (AFTER_BARRIER_THREADS, DEFAULT_RAM_GB, PoolRun, default_max_parallel,  # noqa: E402
                       default_pool, default_slot_dir, model_threads, process_tree_ram_gb, threads_override)

MARKERS_ENV = "TIMESJL_POOL_MARKERS"                      # set for the command; TIMES.pool_phase reads it
MARKER = re.compile(rb"^\[timesjl-pool\] phase=([A-Za-z0-9_-]+)\s*$")
PHASES = {"after-barrier": AFTER_BARRIER_THREADS, "reporting": 1}
SUITES = (HERE.parent / "suite.toml", HERE.parent / "crafted.toml")


def suite_threads(name: str, suites=SUITES) -> int:
    """The thread class of a suite model (reference/suite.toml, then reference/crafted.toml)."""
    import tomllib

    for path in suites:
        if not Path(path).exists():
            continue
        with open(path, "rb") as f:
            for m in tomllib.load(f).get("model", []):
                if m.get("name") == name:
                    return model_threads(m)
    raise ValueError(f"no model {name} in {', '.join(Path(p).name for p in suites)}")


def _kill_tree(proc: subprocess.Popen) -> None:
    """Stop the command and its child processes (juliaup's `julia` starts the real one as a child)."""
    if proc.poll() is not None:
        return
    if sys.platform == "win32":
        subprocess.run(["taskkill", "/T", "/F", "/PID", str(proc.pid)], capture_output=True)
    else:
        proc.kill()


def launch(cmd: list[str], threads: int, label: str, ram_gb: float = DEFAULT_RAM_GB, *, pool: int | None = None,
           max_parallel: int | None = None, slot_dir: Path | None = None, timeout_s: float | None = None,
           measure: bool = True, poll_s: float = 30.0, ram_poll_s: float = 2.0, grace_s: float = 10.0,
           out=None, quiet: bool = False, record: Path | None = None) -> int:
    """Run ``cmd`` holding ``threads`` of the run pool; see the module text. Returns the exit code."""
    out = sys.stdout.buffer if out is None else out

    def say(msg: str) -> None:
        if not quiet:
            print(f"[pool_run] {label}: {msg}", file=sys.stderr, flush=True)

    exe = shutil.which(cmd[0])
    if exe is None:
        say(f"could not start: no program {cmd[0]}")
        return 2
    run = PoolRun(label, threads, ram_gb, pool=pool, max_parallel=max_parallel, slot_dir=slot_dir,
                  poll_s=poll_s, timeout_s=timeout_s, measure=measure)
    try:
        with contextlib.redirect_stdout(sys.stderr):      # "waiting for the run pool": not on the command's output
            run.__enter__()
    except TimeoutError as e:
        say(str(e))
        return 3
    hold = run.threads
    phases: list[tuple[float, str, int]] = []
    peak, proc, rc = 0.0, None, None
    t0 = time.monotonic()
    try:
        say(f"{hold} threads reserved in {run.path}" if run.path else "the run pool is off: nothing reserved")
        if run.waited_s >= 3:                           # the measured load takes a second by itself
            say(f"waited {run.waited_s:.0f} s for the run pool")
        env = dict(os.environ, TIMESJL_THREADS=str(hold))
        env[MARKERS_ENV] = "1"
        try:
            proc = subprocess.Popen([exe, *cmd[1:]], stdout=subprocess.PIPE, env=env)
        except OSError as e:
            say(f"could not start: {e}")
            return 2

        def pump() -> None:
            for line in iter(proc.stdout.readline, b""):
                try:
                    out.write(line)
                    out.flush()
                except (OSError, ValueError):
                    pass                                   # the reader of our output is gone: keep draining
                m = MARKER.match(line)
                keep = PHASES.get(m.group(1).decode()) if m else None
                if keep is None or keep >= run.threads:    # not a phase, or it would not lower the hold
                    continue
                name, why = m.group(1).decode(), None
                for _ in range(50):
                    # On Windows the entry cannot be replaced while another program has it open (one that
                    # reads the ledger without its lock): try again for a few seconds.
                    try:
                        run.set(keep, name)
                        why = None
                        break
                    except TimeoutError as e:              # the ledger's lock, after its own long wait
                        why = e
                        break
                    except OSError as e:
                        why = e
                        time.sleep(0.1)
                if why is None:
                    phases.append((round(time.monotonic() - t0, 1), run.phase, run.threads))
                else:                                      # the ledger still shows the higher hold: the safe side
                    say(f"phase {name} not written to the ledger ({why})")

        reader = threading.Thread(target=pump, daemon=True)
        reader.start()
        try:
            while True:
                r = process_tree_ram_gb(proc.pid)
                if r is not None:
                    peak = max(peak, r)
                try:
                    rc = proc.wait(timeout=ram_poll_s)
                    break
                except subprocess.TimeoutExpired:
                    pass
        except KeyboardInterrupt:
            # Ctrl-C in a terminal reaches the command too: give it time to end by itself, then stop it
            say("interrupted; stopping the command")
            try:
                rc = proc.wait(timeout=grace_s)
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                _kill_tree(proc)
                rc = proc.wait()
            rc = rc or 130
        reader.join(timeout=5.0)                           # a child process left behind may hold the pipe open
        if not reader.is_alive():
            proc.stdout.close()
    finally:
        if proc is not None and proc.poll() is None:       # an error of our own: do not leave the command running
            _kill_tree(proc)
        run.__exit__(None, None, None)
    wall = time.monotonic() - t0
    steps = "".join(f", then {p} {n} at {t:.1f} s" for t, p, n in phases)
    say(f"exit code {rc} after {wall:.1f} s; held {hold} threads{steps}; peak RAM {peak:.2f} GB")
    if record is not None:
        Path(record).parent.mkdir(parents=True, exist_ok=True)
        Path(record).write_text(json.dumps({
            "label": label, "command": cmd, "returncode": rc, "wall_s": round(wall, 3),
            "slot_wait_s": round(run.waited_s, 1), "pool_threads": hold, "pool_phases": phases,
            "peak_ram_gb": round(peak, 2)}, indent=1))
    return rc


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if "--" in argv:
        i = argv.index("--")
        argv, cmd = argv[:i], argv[i + 1:]
    else:
        cmd = []
    p = argparse.ArgumentParser(
        prog="pool_run.py", description="Start one command inside the machine-wide run pool (runlimits.py).",
        usage="pool_run.py (--threads N | --model NAME) [--label TEXT] [--ram-gb N] [--timeout-hours H] -- command ...")
    p.add_argument("--threads", type=int, default=threads_override(),
                   help="the threads to reserve, given to the command as TIMESJL_THREADS: 6 for a small model, "
                        "12 for a large one, 1 for a run that does not solve (default: the class of --model; or "
                        "TIMESJL_THREADS)")
    p.add_argument("--model", default=None,
                   help="a model of reference/suite.toml or reference/crafted.toml: its `threads` is the class")
    p.add_argument("--label", default=None, help="the run's name in the pool's ledger (default: --model, or the command)")
    p.add_argument("--ram-gb", type=float, default=DEFAULT_RAM_GB,
                   help=f"RAM the run needs, in GB (default {DEFAULT_RAM_GB:g}); it starts when that much is free")
    p.add_argument("--timeout-hours", type=float, default=None,
                   help="give up (exit code 3) if the pool has no room in this time (default: wait)")
    p.add_argument("--pool", type=int, default=default_pool(),
                   help="threads of the run pool, 2 of them kept free (default 48, or TIMESJL_POOL; 0 turns the pool "
                        "off: the command starts at once and nothing is reserved)")
    p.add_argument("--max-parallel", type=int, default=default_max_parallel(),
                   help="an optional limit on the number of runs at a time (default 0: none; or TIMESJL_MAX_PARALLEL)")
    p.add_argument("--slot-dir", type=Path, default=default_slot_dir(),
                   help="directory of the pool's ledger files (default <temp>/timesjl-run-slots, or TIMESJL_SLOT_DIR)")
    p.add_argument("--record", type=Path, default=None,
                   help="write the exit code, wall time, phases and peak RAM to this JSON file")
    p.add_argument("--quiet", action="store_true", help="none of the launcher's own [pool_run] lines")
    # for the tests: no measured load or RAM, and shorter waits
    p.add_argument("--no-measure", action="store_true", help=argparse.SUPPRESS)
    p.add_argument("--poll-s", type=float, default=30.0, help=argparse.SUPPRESS)
    p.add_argument("--ram-poll-s", type=float, default=2.0, help=argparse.SUPPRESS)
    p.add_argument("--grace-s", type=float, default=10.0, help=argparse.SUPPRESS)
    a = p.parse_args(argv)
    if not cmd:
        p.error("no command: put it after `--`")
    threads = a.threads
    if threads <= 0:
        if not a.model:
            p.error("give --threads or --model")
        try:
            threads = suite_threads(a.model)
        except ValueError as e:
            p.error(str(e))
    label = a.label or a.model or " ".join(cmd)[:80]
    return launch(cmd, threads, label, a.ram_gb, pool=a.pool, max_parallel=a.max_parallel, slot_dir=a.slot_dir,
                  timeout_s=None if a.timeout_hours is None else a.timeout_hours * 3600, measure=not a.no_measure,
                  poll_s=a.poll_s, ram_poll_s=a.ram_poll_s, grace_s=a.grace_s, quiet=a.quiet, record=a.record)


if __name__ == "__main__":
    sys.exit(main())
