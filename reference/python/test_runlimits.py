"""Tests for runlimits.py: the threads rewrite, the machine-wide run pool and the GAMS phase watch."""

import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from runlimits import (AFTER_BARRIER_THREADS, GamsWatch, PoolRun, _Lock, ledger, limit_threads,  # noqa: E402
                       model_threads, pid_alive, runfile_solves_once)

NL = chr(10)

PSI_CPLEX = "preind 1\r\naggind 50\r\nlpmethod 4 \r\nthreads -1\r\npredual -1\r\n*  threads 2\r\nsolutiontype 2"


class LimitThreadsTests(unittest.TestCase):
    def test_rewrites_threads_line_keeps_comments_and_line_ends(self):
        text, changes = limit_threads(PSI_CPLEX, 12)
        self.assertIn("\r\nthreads 12\r\n", text)
        self.assertIn("*  threads 2", text)       # comment untouched
        self.assertTrue(text.endswith("solutiontype 2"))
        self.assertEqual(changes, ["threads -1 -> threads 12"])

    def test_equals_form_and_case(self):
        text, changes = limit_threads("Threads = 48\nsolver ipm\n", 12)
        self.assertEqual(text, "threads 12\nsolver ipm\n")
        self.assertEqual(len(changes), 1)

    def test_no_threads_line(self):
        text, changes = limit_threads("lpmethod 4\n", 12)
        self.assertEqual((text, changes), ("lpmethod 4\n", []))

    def test_already_at_limit(self):
        self.assertEqual(limit_threads("threads 12\n", 12), ("threads 12\n", []))


def dead_pid() -> int:
    p = subprocess.run([sys.executable, "-c", "import os; print(os.getpid())"], capture_output=True, text=True)
    pid = int(p.stdout.strip())
    assert not pid_alive(pid)
    return pid


def pool(label, threads, folder, **kw):
    kw.setdefault("pool", 48)
    kw.setdefault("keep_free", 2)
    kw.setdefault("measure", False)
    return PoolRun(label, threads, 1.0, slot_dir=folder, **kw)


class PoolTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())

    def held(self):
        return sum(r["threads"] for r in ledger(self.dir))

    def test_reserve_and_release(self):
        with pool("a", 12, self.dir) as r:
            info = json.loads(r.path.read_text())
            self.assertEqual((info["label"], info["threads"], info["phase"]), ("a", 12, "start"))
            self.assertEqual(self.held(), 12)
        self.assertEqual(list(self.dir.glob("run-*.json")), [])

    def test_no_run_count_limit_only_threads(self):
        # 46 threads (48 less 2 kept free): seven runs of 6, then 4 left: a run of 6 waits, nothing else counts
        runs = [pool(str(k), 6, self.dir).__enter__() for k in range(7)]
        self.assertEqual(self.held(), 42)
        with self.assertRaises(TimeoutError):
            with pool("x", 6, self.dir, poll_s=0.05, timeout_s=0.2):
                pass
        with pool("y", 4, self.dir) as y:   # 4 fits
            self.assertIsNotNone(y.path)
        for r in runs:
            r.__exit__()

    def test_lowering_frees_threads_for_a_waiting_run(self):
        a = pool("a", 12, self.dir).__enter__()
        b = pool("b", 12, self.dir).__enter__()
        c = pool("c", 12, self.dir).__enter__()       # 36 held, 10 free: a fourth 12 waits
        threading.Timer(0.3, lambda: a.set(1, "reporting")).start()
        t0 = time.monotonic()
        with pool("d", 12, self.dir, poll_s=0.05, timeout_s=5) as d:
            self.assertGreaterEqual(time.monotonic() - t0, 0.25)
            self.assertGreater(d.waited_s, 0.2)
            self.assertEqual(self.held(), 1 + 12 + 12 + 12)
        for r in (a, b, c):
            r.__exit__()

    def test_set_never_raises_the_hold(self):
        with pool("a", 6, self.dir) as a:
            a.set(4, "crossover")
            a.set(12, "barrier again")
            self.assertEqual(json.loads(a.path.read_text())["threads"], 4)

    def test_clears_entries_of_finished_processes_and_counts_old_slots(self):
        dead = dead_pid()
        (self.dir / f"run-{dead}-00000000.json").write_text(json.dumps({"pid": dead, "threads": 12}))
        (self.dir / "slot0.lock").write_text(json.dumps({"pid": os.getpid(), "label": "earlier rule"}))
        runs = ledger(self.dir)
        self.assertEqual([r["threads"] for r in runs], [12])          # the old slot, as 12 threads
        self.assertFalse((self.dir / f"run-{dead}-00000000.json").exists())

    def test_stale_lock_of_a_finished_process(self):
        (self.dir / "pool.lock").write_text(str(dead_pid()))
        with pool("a", 6, self.dir, timeout_s=2) as a:
            self.assertIsNotNone(a.path)

    def test_lock_is_removed_although_a_reader_has_it_open(self):
        # Windows: a file open in another program cannot be removed; left behind, the lock of a process
        # that lives on would stop every other run. (Elsewhere the file is removed at once.)
        with pool("a", 6, self.dir) as a:
            reader = []
            threading.Timer(0.3, lambda: reader.pop().close()).start()
            with _Lock(self.dir) as lock:
                reader.append(open(lock.path))
            self.assertFalse(lock.path.exists())
            a.set(1, "reporting")                       # the lock is free again
            self.assertEqual(self.held(), 1)

    def test_optional_run_count_limit(self):
        with pool("a", 1, self.dir, max_parallel=1):
            with self.assertRaises(TimeoutError):
                with pool("b", 1, self.dir, max_parallel=1, poll_s=0.05, timeout_s=0.2):
                    pass

    def test_disabled(self):
        with pool("a", 12, self.dir, pool=0) as a:
            self.assertIsNone(a.path)

    def test_waits_for_ram(self):
        # a run that needs more RAM than the machine has never starts (measured RAM, as on the workstation)
        with self.assertRaises(TimeoutError) as e:
            with PoolRun("big", 1, 1e9, slot_dir=self.dir, pool=48, poll_s=0.05, timeout_s=0.2):
                pass
        self.assertIn("RAM", str(e.exception))

    def test_measured_checks_run(self):
        # with measure=True the run starts on an idle-enough machine; the message names what is short otherwise
        r = PoolRun("m", 1, 0.0, slot_dir=self.dir, pool=48)
        why = r._fits([])
        self.assertTrue(why == "" or "busy" in why or "RAM" in why)


class ClassAndStepTests(unittest.TestCase):
    def test_model_threads(self):
        self.assertEqual(model_threads({}), 12)
        self.assertEqual(model_threads({"threads": 6}), 6)
        with self.assertRaises(ValueError):
            model_threads({"name": "m", "threads": 8})

    def test_runfile_solves_once(self):
        self.assertTrue(runfile_solves_once("$SET REDUCE YES" + NL))
        self.assertTrue(runfile_solves_once("$ SET TIMESTEP 0" + NL))
        self.assertFalse(runfile_solves_once("$ SET TIMESTEP 1" + NL))
        self.assertFalse(runfile_solves_once("$SET FIXBOH 2030" + NL))


class GamsWatchTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.log = self.dir / "run.log"

    def test_phases_of_a_cplex_barrier_run(self):
        with pool("a", 12, self.dir) as run:
            w = GamsWatch(run, self.log, os.getpid(), single_solve=True)
            self.log.write_text(NL.join(["--- Generating LP model TIMES", "  3   1.3e+09", ""]))
            w.poll()
            self.assertEqual(run.threads, 12)
            with self.log.open("a") as f:
                f.write(NL.join(["Barrier time = 30.19 sec. (39870.99 ticks)", "Dual crossover.", ""]))
            w.poll()
            self.assertEqual((run.threads, run.phase), (AFTER_BARRIER_THREADS, "crossover"))
            with self.log.open("a") as f:
                f.write("--- Reading solution for model TIMES" + NL)
            w.poll()
            self.assertEqual((run.threads, run.phase), (1, "reporting"))
            self.assertGreater(w.peak_ram_gb, 0.0)
            self.assertEqual([p[1] for p in w.phases], ["crossover", "reporting"])

    def test_stepped_run_keeps_its_class(self):
        with pool("a", 12, self.dir) as run:
            w = GamsWatch(run, self.log, os.getpid(), single_solve=False)
            self.log.write_text(NL.join(["Barrier time = 1 sec.", "--- Reading solution for model TIMES", ""]))
            w.poll()
            self.assertEqual(run.threads, 12)

    def test_unrecognised_solver_log_keeps_its_class(self):
        with pool("a", 6, self.dir) as run:
            w = GamsWatch(run, self.log, os.getpid(), single_solve=True)
            self.log.write_text(NL.join(["Running IPX", "--- Reading solution for model TIMES", ""]))
            w.poll()
            self.assertEqual(run.threads, 6)


if __name__ == "__main__":
    unittest.main()
