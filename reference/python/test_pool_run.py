"""Tests for pool_run.py: the launcher that runs one command inside the run pool.

No GAMS and no Julia: the command is a small Python script that prints what the test asks for, the
marker lines among them, and waits for a file between the steps, so that the test reads the ledger
at a known point. Every test has its own ledger directory; none touches the workstation's.
"""

import io
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import _thread
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import pool_run  # noqa: E402
from runlimits import AFTER_BARRIER_THREADS, PoolRun, pid_alive  # noqa: E402

LAUNCHER = str(HERE / "pool_run.py")
MARK = "[timesjl-pool] phase="

# The command: each argument is one step. say:<text> prints a line; wait:<file> waits for the file;
# env:<name> prints the variable (or "unset"); pid:<file> writes its process id; raw:<hex> writes bytes;
# exit:<n> ends with that code.
CHILD = r"""
import os, sys, time
for step in sys.argv[1:]:
    what, _, arg = step.partition(":")
    if what == "say":
        print(arg, flush=True)
    elif what == "wait":
        while not os.path.exists(arg):
            time.sleep(0.02)
    elif what == "env":
        print(arg + "=" + os.environ.get(arg, "unset"), flush=True)
    elif what == "pid":
        with open(arg, "w") as f:
            f.write(str(os.getpid()))
    elif what == "raw":
        sys.stdout.buffer.write(bytes.fromhex(arg)); sys.stdout.buffer.flush()
    elif what == "exit":
        sys.exit(int(arg))
"""


class LauncherCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.dir = self.tmp / "slots"
        self.child = self.tmp / "child.py"
        self.child.write_text(CHILD)

    def start(self, *steps, opts=("--threads", "12"), env=None, slot=True):
        cmd = [sys.executable, LAUNCHER, *opts, "--no-measure", "--ram-poll-s", "0.05", "--poll-s", "0.05"]
        if slot:
            cmd += ["--slot-dir", str(self.dir)]
        cmd += ["--", sys.executable, str(self.child), *steps]
        e = {k: v for k, v in os.environ.items() if not k.startswith("TIMESJL_")}
        e.update(env or {})
        return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=e)

    def entries(self, folder=None):
        out = []
        for f in sorted((folder or self.dir).glob("run-*.json")):
            try:
                out.append(json.loads(f.read_text()))
            except (OSError, ValueError):
                pass                      # being replaced
        return out

    def until(self, cond, what, folder=None, timeout=30.0):
        """The ledger's entries once ``cond(entries)`` holds (the launcher works on its own clock)."""
        t0 = time.monotonic()
        while True:
            e = self.entries(folder)
            if cond(e):
                return e
            if time.monotonic() - t0 > timeout:
                self.fail(f"{what}: the ledger shows {e}")
            time.sleep(0.02)

    def go(self, name):
        (self.tmp / name).write_text("")

    def w(self, name):
        return f"wait:{self.tmp / name}"

    def finish(self, p):
        out, err = p.communicate(timeout=60)
        return p.returncode, out.decode().splitlines(), err.decode(errors="replace")


class PhaseTests(LauncherCase):
    def test_class_then_lower_then_removed(self):
        self.assertLess(AFTER_BARRIER_THREADS, 12)
        rec = self.tmp / "rec" / "run.json"
        p = self.start("env:TIMESJL_THREADS", "env:TIMESJL_POOL_MARKERS", "env:TIMESJL_POOL", self.w("a"),
                       "say:" + MARK + "after-barrier", self.w("b"), "say:" + MARK + "reporting", self.w("c"), "say:done",
                       opts=("--threads", "12", "--label", "a run", "--ram-gb", "3", "--record", str(rec)))
        e = self.until(lambda e: len(e) == 1, "the reservation")[0]
        self.assertEqual((e["label"], e["threads"], e["phase"], e["ram_gb"]), ("a run", 12, "start", 3.0))
        self.assertTrue(pid_alive(e["pid"]))
        self.go("a")
        e = self.until(lambda e: len(e) == 1 and e[0]["threads"] < 12, "after barrier")[0]
        self.assertEqual((e["threads"], e["phase"]), (AFTER_BARRIER_THREADS, "after-barrier"))
        self.go("b")
        e = self.until(lambda e: len(e) == 1 and e[0]["threads"] < AFTER_BARRIER_THREADS, "reporting")[0]
        self.assertEqual((e["threads"], e["phase"]), (1, "reporting"))
        self.go("c")
        rc, out, err = self.finish(p)
        self.assertEqual(rc, 0)
        self.assertEqual(self.entries(), [])                       # released
        # the command's output, every line and nothing else; the command got its class and the marker switch,
        # and TIMESJL_POOL (the size of the pool) is not touched
        self.assertEqual(out, ["TIMESJL_THREADS=12", "TIMESJL_POOL_MARKERS=1", "TIMESJL_POOL=unset",
                               MARK + "after-barrier", MARK + "reporting", "done"])
        self.assertIn("[pool_run] a run: 12 threads reserved", err)
        self.assertIn(f"held 12 threads, then after-barrier {AFTER_BARRIER_THREADS} at", err)
        r = json.loads(rec.read_text())
        self.assertEqual((r["returncode"], r["pool_threads"], [x[1:] for x in r["pool_phases"]]),
                         (0, 12, [["after-barrier", AFTER_BARRIER_THREADS], ["reporting", 1]]))
        self.assertGreater(r["peak_ram_gb"], 0.0)

    def test_no_marker_keeps_the_class_to_the_end(self):
        p = self.start("say:solving", self.w("a"), "say:solved again", self.w("b"), opts=("--threads", "6"))
        self.until(lambda e: len(e) == 1, "the reservation")
        self.go("a")
        time.sleep(0.3)                                             # nothing to wait for: it must not change
        self.assertEqual([x["threads"] for x in self.entries()], [6])
        self.go("b")
        rc, out, err = self.finish(p)
        self.assertEqual((rc, out, self.entries()), (0, ["solving", "solved again"], []))
        self.assertNotIn("then", err)

    def test_a_marker_never_raises_the_hold(self):
        p = self.start("say:" + MARK + "reporting", "say:" + MARK + "after-barrier", "say:" + MARK + "reporting", "say:x",
                       self.w("a"), opts=("--threads", "6"))
        self.until(lambda e: len(e) == 1 and e[0]["threads"] == 1, "reporting")
        self.go("a")
        rc, out, err = self.finish(p)
        self.assertEqual(rc, 0)
        self.assertIn("then reporting 1 at", err)
        self.assertNotIn("after-barrier", err)                      # ignored: 4 threads would be more than 1

    def test_a_run_of_one_thread_stays_at_one(self):
        p = self.start("say:" + MARK + "after-barrier", self.w("a"), opts=("--threads", "1"))
        self.until(lambda e: len(e) == 1, "the reservation")
        self.go("a")
        rc, out, err = self.finish(p)
        self.assertEqual(rc, 0)
        self.assertIn("held 1 threads; peak RAM", err)

    def test_other_lines_change_nothing(self):
        lines = [MARK + "warp",                                     # not a phase
                 "note " + MARK + "reporting",                      # not at the start of the line
                 MARK + "reporting now",                            # more on the line
                 MARK.upper() + "reporting", "phase=reporting", MARK, ""]
        p = self.start(*["say:" + ln for ln in lines], "raw:ff5b74696d65736a6c0a",   # bytes that are not UTF-8
                       "say:" + MARK + "after-barrier", self.w("a"), opts=("--threads", "12"))
        # the lines above came first: had one of them counted, the hold would be 1 and stay there
        e = self.until(lambda e: len(e) == 1 and e[0]["threads"] < 12, "after barrier")[0]
        self.assertEqual((e["threads"], e["phase"]), (AFTER_BARRIER_THREADS, "after-barrier"))
        self.go("a")
        out, err = p.communicate(timeout=60)
        self.assertEqual(p.returncode, 0)
        self.assertEqual(out.replace(b"\r\n", b"\n"),
                         "".join(ln + "\n" for ln in lines).encode() + b"\xff[timesjl\n" + (MARK + "after-barrier\n").encode())


class RunTests(LauncherCase):
    def test_exit_code_passes_through_and_the_hold_is_released(self):
        p = self.start("say:failing", "exit:7", opts=("--threads", "6"))
        rc, out, err = self.finish(p)
        self.assertEqual((rc, out, self.entries()), (7, ["failing"], []))
        self.assertIn("exit code 7", err)

    def test_quiet(self):
        rc, out, err = self.finish(self.start("say:x", opts=("--threads", "6", "--quiet")))
        self.assertEqual((rc, out, err), (0, ["x"], ""))

    def test_pool_off_runs_and_reserves_nothing(self):
        # --pool 0 (or TIMESJL_POOL=0), as for make_reference.py: the command starts at once
        p = self.start("env:TIMESJL_THREADS", "say:" + MARK + "reporting", "exit:5", opts=("--threads", "6", "--pool", "0"))
        rc, out, err = self.finish(p)
        self.assertEqual((rc, out), (5, ["TIMESJL_THREADS=6", MARK + "reporting"]))
        self.assertFalse(self.dir.exists())
        self.assertIn("the run pool is off", err)
        p = self.start("say:x", opts=("--threads", "6"), env={"TIMESJL_POOL": "0"})
        self.assertEqual(self.finish(p)[0], 0)
        self.assertFalse(self.dir.exists())

    def test_no_ledger_directory_named_uses_the_default_one(self):
        # neither --slot-dir nor TIMESJL_SLOT_DIR: <temp>/timesjl-run-slots (runlimits.default_slot_dir)
        temp = self.tmp / "temp"
        temp.mkdir()
        p = self.start(self.w("a"), opts=("--threads", "6"), slot=False,
                       env={"TEMP": str(temp), "TMP": str(temp), "TMPDIR": str(temp)})
        e = self.until(lambda e: len(e) == 1, "the reservation", folder=temp / "timesjl-run-slots")
        self.assertEqual(e[0]["threads"], 6)
        self.go("a")
        self.assertEqual(self.finish(p)[0], 0)
        self.assertEqual(self.entries(temp / "timesjl-run-slots"), [])
        p = self.start(self.w("b"), opts=("--threads", "6"), slot=False, env={"TIMESJL_SLOT_DIR": str(self.dir)})
        self.until(lambda e: len(e) == 1, "the reservation")
        self.go("b")
        self.assertEqual(self.finish(p)[0], 0)

    def test_waits_for_room_and_gives_up_after_the_timeout(self):
        started = self.tmp / "started"
        with PoolRun("others", 46, 1.0, slot_dir=self.dir, pool=48, keep_free=2, measure=False):
            p = self.start(f"pid:{started}", opts=("--threads", "6", "--timeout-hours", "0.0001"))
            rc, out, err = self.finish(p)
            self.assertEqual((rc, out), (3, []))
            self.assertIn("no room in the run pool", err)
            self.assertIn("waiting for the run pool", err)          # on the error output, not the command's
            self.assertFalse(started.exists())                      # the command never started
            self.assertEqual([x["label"] for x in self.entries()], ["others"])

    def test_starts_once_another_run_lowers_its_hold(self):
        with PoolRun("other", 46, 1.0, slot_dir=self.dir, pool=48, keep_free=2, measure=False) as other:
            p = self.start("say:in", opts=("--threads", "6"))
            time.sleep(0.5)
            self.assertIsNone(p.poll())                             # waiting
            other.set(1, "reporting")
            rc, out, err = self.finish(p)
            self.assertEqual((rc, out), (0, ["in"]))

    def test_class_of_a_suite_model(self):
        self.assertEqual(pool_run.suite_threads("TIMES_Demo-demo12"), 6)             # suite.toml
        self.assertEqual(pool_run.suite_threads("TIMES_Demo-demo12_red17b"), 6)      # crafted.toml
        self.assertEqual(pool_run.suite_threads("OTUS9r-reference"), 12)             # no `threads`: the large class
        with self.assertRaises(ValueError):
            pool_run.suite_threads("no-such-model")
        rc, out, err = self.finish(self.start("env:TIMESJL_THREADS", opts=("--model", "TIMES_Demo-demo12")))
        self.assertEqual((rc, out), (0, ["TIMESJL_THREADS=6"]))
        self.assertIn("[pool_run] TIMES_Demo-demo12: 6 threads reserved", err)
        # as in make_reference.py: --threads, or TIMESJL_THREADS, is one count for every model
        rc, out, _ = self.finish(self.start("env:TIMESJL_THREADS", opts=("--model", "TIMES_Demo-demo12", "--threads", "12")))
        self.assertEqual(out, ["TIMESJL_THREADS=12"])
        rc, out, _ = self.finish(self.start("env:TIMESJL_THREADS", opts=("--model", "TIMES_Demo-demo12"),
                                            env={"TIMESJL_THREADS": "4"}))
        self.assertEqual(out, ["TIMESJL_THREADS=4"])

    def test_wrong_arguments(self):
        for opts in ((), ("--model", "no-such-model")):
            rc, out, err = self.finish(self.start("say:x", opts=opts))
            self.assertEqual((rc, out), (2, []))
        p = subprocess.run([sys.executable, LAUNCHER, "--threads", "6", "--slot-dir", str(self.dir)], capture_output=True)
        self.assertEqual(p.returncode, 2)                           # no command
        p = subprocess.run([sys.executable, LAUNCHER, "--threads", "6", "--slot-dir", str(self.dir), "--no-measure",
                            "--", "no-such-program-timesjl"], capture_output=True)
        self.assertEqual(p.returncode, 2)
        self.assertEqual(self.entries(), [])


class InProcessTests(LauncherCase):
    def launch(self, *steps, **kw):
        out = io.BytesIO()
        rc = pool_run.launch([sys.executable, str(self.child), *steps], 6, "t", 1.0, slot_dir=self.dir, pool=48,
                             measure=False, ram_poll_s=0.05, out=out, quiet=True, **kw)
        return rc, out.getvalue().decode().splitlines()

    def test_the_launcher_keeps_its_own_environment(self):
        before = dict(os.environ)
        rc, out = self.launch("env:TIMESJL_POOL_MARKERS", "say:" + MARK + "reporting")
        self.assertEqual((rc, out), (0, ["TIMESJL_POOL_MARKERS=1", MARK + "reporting"]))
        self.assertEqual(dict(os.environ), before)
        self.assertEqual(self.entries(), [])

    def test_a_ledger_entry_in_use_is_written_again(self):
        # Windows: the entry cannot be replaced while a program that reads the ledger has it open
        class Busy(PoolRun):
            left = 2

            def _write(self):
                if self.phase != "start" and Busy.left > 0:
                    Busy.left -= 1
                    raise PermissionError("in use")
                super()._write()

        seen = []

        def release():
            seen.extend(self.until(lambda e: len(e) == 1 and e[0]["threads"] == 1, "reporting"))
            self.go("a")

        real, pool_run.PoolRun = pool_run.PoolRun, Busy
        try:
            t = threading.Thread(target=release, daemon=True)
            t.start()
            rc, out = self.launch("say:" + MARK + "reporting", self.w("a"))
            t.join(timeout=5)
        finally:
            pool_run.PoolRun = real
        self.assertEqual((rc, Busy.left, [x["phase"] for x in seen]), (0, 0, ["reporting"]))

    def test_interrupt_stops_the_command_and_releases(self):
        pidfile = self.tmp / "pid"
        seen = []

        def interrupt():
            t0 = time.monotonic()
            while not (pidfile.exists() and pidfile.read_text() and self.entries()) and time.monotonic() - t0 < 30:
                time.sleep(0.02)
            seen.extend(self.entries())
            _thread.interrupt_main()                                # Ctrl-C, for this process only

        threading.Thread(target=interrupt, daemon=True).start()
        rc, out = self.launch(f"pid:{pidfile}", "say:running", self.w("never"), grace_s=0.2)
        self.assertEqual([x["threads"] for x in seen], [6])
        self.assertNotEqual(rc, 0)
        self.assertEqual(self.entries(), [])
        pid = int(pidfile.read_text())
        t0 = time.monotonic()
        while pid_alive(pid) and time.monotonic() - t0 < 10:
            time.sleep(0.05)
        self.assertFalse(pid_alive(pid))


if __name__ == "__main__":
    unittest.main()
