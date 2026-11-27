"""Limits for local TIMES runs: a machine-wide thread pool (James, 26 Nov 2026).

On James's workstation (48 logical CPUs) runs share a pool of threads, in the
manner of a Slurm scheduler. The rule replaces "at most 12 threads per run and
at most 4 CPU-heavy runs at a time" (James, 29 Oct 2026):

* A run reserves its thread class from its start: 6 threads for the small
  models, 12 for the large ones (``threads`` in ``reference/suite.toml``,
  default 12). Runs that never solve (the pre-solve and CONVERT runs) reserve 1.
* When its barrier ends the run keeps fewer: ``AFTER_BARRIER_THREADS`` while
  crossover runs, then 1 for reporting. A run with several solves (myopic)
  keeps its class until it ends, and so does a run whose solver log is not
  recognised; nothing is ever re-acquired.
* A new run starts only when its class is free: the reserved threads plus its
  own within the pool less ``keep_free`` (48 - 2), the measured load leaving
  ``keep_free`` CPUs idle, and the RAM it needs (its last peak) free, both as
  reserved and as measured. There is no limit on the number of runs.
* Timing runs follow the same rule.

The pool is a ledger of JSON files, one per run, in one directory, changed
only under a lock file (``pool.lock``); an entry whose process no longer exists
is cleared. Lock files of the earlier rule (``slot<k>.lock``) count as
``LEGACY_SLOT_THREADS`` threads each. Runs outside the ledger (Veda, scripts
that do not use this module) are seen only through the measured load and RAM.

``limit_threads`` rewrites the ``threads`` line of a solver option file (CPLEX
``cplex.opt``, GAMS/HiGHS ``highs.opt``, ...). Option files without a
``threads`` line are left alone; the GAMS ``threads=`` command-line option
covers them.

Standard library only.
"""

from __future__ import annotations

import ctypes
import json
import os
import re
import sys
import tempfile
import time
import uuid
from pathlib import Path

DEFAULT_THREADS = 12          # the large-model class, and the class of a model with no ``threads``
SMALL_THREADS = 6             # the small-model class (James, 26 Nov 2026)
AFTER_BARRIER_THREADS = 2     # kept from barrier's end to the solve's end: CPLEX's crossover runs a dual and a
                              # primal simplex side by side, one thread each (James, 27 Nov 2026, #207 d6b)
DEFAULT_POOL = 48             # logical CPUs of James's workstation
DEFAULT_KEEP_FREE = 2         # CPUs kept free (James, 26 Nov 2026)
DEFAULT_MAX_PARALLEL = 0      # no limit on the number of runs (James, 26 Nov 2026); > 0 adds one
DEFAULT_RAM_GB = 16.0         # RAM reserved by a run that has no recorded peak
LEGACY_SLOT_THREADS = 12      # a slot<k>.lock of the earlier rule

_THREADS_LINE = re.compile(r"^(?P<indent>\s*)threads(?:\s*=\s*|\s+)(?P<value>\S+)\s*$", re.IGNORECASE)


def _env_int(name: str, default: int) -> int:
    v = os.environ.get(name, "").strip()
    return int(v) if v else default


def default_threads() -> int:
    """TIMESJL_THREADS if set, else ``DEFAULT_THREADS``."""
    return _env_int("TIMESJL_THREADS", DEFAULT_THREADS)


def threads_override() -> int:
    """TIMESJL_THREADS if set (one thread count for every run), else 0: each model's class."""
    return _env_int("TIMESJL_THREADS", 0)


def default_max_parallel() -> int:
    return _env_int("TIMESJL_MAX_PARALLEL", DEFAULT_MAX_PARALLEL)


def default_pool() -> int:
    return _env_int("TIMESJL_POOL", DEFAULT_POOL)


def default_keep_free() -> int:
    return _env_int("TIMESJL_KEEP_FREE", DEFAULT_KEEP_FREE)


def default_slot_dir() -> Path:
    return Path(os.environ.get("TIMESJL_SLOT_DIR", Path(tempfile.gettempdir()) / "timesjl-run-slots"))


def model_threads(model: dict) -> int:
    """A suite model's thread class: its ``threads`` (6 or 12), default ``DEFAULT_THREADS``."""
    t = int(model.get("threads", DEFAULT_THREADS))
    if t not in (SMALL_THREADS, DEFAULT_THREADS):
        raise ValueError(f"{model.get('name', '?')}: threads = {t}; the classes are "
                         f"{SMALL_THREADS} and {DEFAULT_THREADS}")
    return t


def limit_threads(text: str, threads: int) -> tuple[str, list[str]]:
    """Set every non-comment ``threads`` option line to ``threads``.

    Returns the new text and the lines changed (``"old -> new"``). Comment lines
    (starting with ``*``) are kept as they are.
    """
    out, changes = [], []
    for ln in text.splitlines(keepends=True):
        body = ln.rstrip("\r\n")
        eol = ln[len(body):]
        m = _THREADS_LINE.match(body)
        if m and not body.lstrip().startswith("*"):
            new = f"{m.group('indent')}threads {threads}"
            if body != new:
                changes.append(f"{body.strip()} -> {new.strip()}")
            out.append(new + eol)
        else:
            out.append(ln)
    return "".join(out), changes


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    if sys.platform == "win32":
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        handle = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            return ctypes.get_last_error() == 5  # access denied: the process exists
        try:
            code = ctypes.c_ulong()
            kernel32.GetExitCodeProcess(handle, ctypes.byref(code))
            return code.value == 259  # STILL_ACTIVE
        finally:
            kernel32.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


# ---- the machine: measured load and RAM (Windows and Linux)

if sys.platform == "win32":
    class _FILETIME(ctypes.Structure):
        _fields_ = [("lo", ctypes.c_uint32), ("hi", ctypes.c_uint32)]

    class _MEMSTATUS(ctypes.Structure):
        _fields_ = [("dwLength", ctypes.c_uint32), ("dwMemoryLoad", ctypes.c_uint32),
                    ("ullTotalPhys", ctypes.c_uint64), ("ullAvailPhys", ctypes.c_uint64),
                    ("ullTotalPageFile", ctypes.c_uint64), ("ullAvailPageFile", ctypes.c_uint64),
                    ("ullTotalVirtual", ctypes.c_uint64), ("ullAvailVirtual", ctypes.c_uint64),
                    ("ullAvailExtendedVirtual", ctypes.c_uint64)]


def _cpu_times() -> tuple[float, float] | None:
    """(idle, total) CPU time summed over all logical CPUs, in arbitrary units."""
    try:
        if sys.platform == "win32":
            idle, kern, user = _FILETIME(), _FILETIME(), _FILETIME()
            if not ctypes.windll.kernel32.GetSystemTimes(ctypes.byref(idle), ctypes.byref(kern), ctypes.byref(user)):
                return None
            def v(f): return (f.hi << 32) | f.lo
            return float(v(idle)), float(v(kern) + v(user))  # kernel time includes idle time
        with open("/proc/stat") as f:
            parts = [float(x) for x in f.readline().split()[1:]]
        return parts[3] + (parts[4] if len(parts) > 4 else 0.0), sum(parts)
    except (OSError, ValueError, AttributeError):
        return None


def cpus_busy(sample_s: float = 1.0) -> float | None:
    """Logical CPUs busy on average over ``sample_s`` seconds (None if it cannot be measured)."""
    a = _cpu_times()
    if a is None:
        return None
    time.sleep(sample_s)
    b = _cpu_times()
    if b is None or b[1] <= a[1]:
        return None
    return (1.0 - (b[0] - a[0]) / (b[1] - a[1])) * (os.cpu_count() or 1)


def ram_gb() -> tuple[float, float] | None:
    """(total, available) physical RAM in GB (None if it cannot be measured)."""
    try:
        if sys.platform == "win32":
            m = _MEMSTATUS()
            m.dwLength = ctypes.sizeof(_MEMSTATUS)
            if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m)):
                return None
            return m.ullTotalPhys / 1e9, m.ullAvailPhys / 1e9
        info = {}
        with open("/proc/meminfo") as f:
            for ln in f:
                k, v = ln.split(":", 1)
                info[k] = float(v.split()[0]) * 1024
        return info["MemTotal"] / 1e9, info["MemAvailable"] / 1e9
    except (OSError, ValueError, KeyError, AttributeError):
        return None


def process_tree_ram_gb(root_pid: int) -> float | None:
    """Resident memory of a process and all its descendants, in GB (None if it cannot be measured)."""
    try:
        if sys.platform == "win32":
            return _win_tree_ram(root_pid)
        pids, todo = set(), [root_pid]
        while todo:
            p = todo.pop()
            if p in pids:
                continue
            pids.add(p)
            for t in Path(f"/proc/{p}/task").glob("*/children"):
                todo += [int(c) for c in t.read_text().split()]
        tot = 0
        for p in pids:
            try:
                tot += int(Path(f"/proc/{p}/statm").read_text().split()[1]) * os.sysconf("SC_PAGE_SIZE")
            except OSError:
                pass
        return tot / 1e9
    except (OSError, ValueError):
        return None


def _win_tree_ram(root_pid: int) -> float | None:
    from ctypes import wintypes

    class PROCESSENTRY32(ctypes.Structure):
        _fields_ = [("dwSize", wintypes.DWORD), ("cntUsage", wintypes.DWORD), ("th32ProcessID", wintypes.DWORD),
                    ("th32DefaultHeapID", ctypes.c_size_t), ("th32ModuleID", wintypes.DWORD),
                    ("cntThreads", wintypes.DWORD), ("th32ParentProcessID", wintypes.DWORD),
                    ("pcPriClassBase", ctypes.c_long), ("dwFlags", wintypes.DWORD), ("szExeFile", ctypes.c_char * 260)]

    class PMC(ctypes.Structure):
        _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                    ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                    ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                    ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t)]

    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    psapi = ctypes.WinDLL("psapi", use_last_error=True)
    k32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    k32.OpenProcess.restype = wintypes.HANDLE
    psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD]
    k32.CloseHandle.argtypes = [wintypes.HANDLE]
    snap = k32.CreateToolhelp32Snapshot(0x2, 0)  # TH32CS_SNAPPROCESS
    if not snap or snap == ctypes.c_void_p(-1).value:
        return None
    children: dict[int, list[int]] = {}
    try:
        e = PROCESSENTRY32()
        e.dwSize = ctypes.sizeof(PROCESSENTRY32)
        ok = k32.Process32First(wintypes.HANDLE(snap), ctypes.byref(e))
        while ok:
            children.setdefault(e.th32ParentProcessID, []).append(e.th32ProcessID)
            ok = k32.Process32Next(wintypes.HANDLE(snap), ctypes.byref(e))
    finally:
        k32.CloseHandle(snap)
    pids, todo = set(), [root_pid]
    while todo:
        p = todo.pop()
        if p in pids:
            continue
        pids.add(p)
        todo += children.get(p, [])
    tot = 0
    for p in pids:
        h = k32.OpenProcess(0x1000 | 0x0010, False, p)  # QUERY_LIMITED_INFORMATION | VM_READ
        if not h:
            continue
        try:
            c = PMC()
            c.cb = ctypes.sizeof(PMC)
            if psapi.GetProcessMemoryInfo(h, ctypes.byref(c), c.cb):
                tot += c.WorkingSetSize
        finally:
            k32.CloseHandle(h)
    return tot / 1e9


# ---- the pool

class _Lock:
    """A machine-wide mutex: ``pool.lock`` created exclusively, cleared if its process is gone."""

    def __init__(self, folder: Path, timeout_s: float = 120.0):
        self.path = folder / "pool.lock"
        self.timeout_s = timeout_s

    def __enter__(self) -> "_Lock":
        t0 = time.monotonic()
        while True:
            try:
                fd = os.open(self.path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                with os.fdopen(fd, "w") as f:
                    f.write(str(os.getpid()))
                return self
            except FileExistsError:
                try:
                    pid = int(self.path.read_text().strip() or 0)
                except (OSError, ValueError):
                    pid = 0  # being written
                if pid > 0 and not pid_alive(pid):
                    try:
                        self.path.unlink()
                    except OSError:
                        pass
                    continue
                if time.monotonic() - t0 > self.timeout_s:
                    raise TimeoutError(f"{self.path} held for over {self.timeout_s} s")
                time.sleep(0.05)

    def __exit__(self, *exc) -> None:
        try:
            self.path.unlink()
        except OSError:
            pass


def _read_json(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def ledger(folder: Path) -> list[dict]:
    """The runs holding threads now; entries of finished processes are removed. Call under the lock."""
    out = []
    for path in sorted(folder.glob("run-*.json")) + sorted(folder.glob("slot*.lock")):
        info = _read_json(path)
        if info is None:
            continue
        if not pid_alive(int(info.get("pid", 0))):
            try:
                path.unlink()
            except OSError:
                pass
            continue
        if path.name.startswith("slot"):
            info = {**info, "threads": LEGACY_SLOT_THREADS, "ram_gb": 0.0, "phase": "slot of the earlier rule"}
        out.append({**info, "file": path.name})
    return out


class PoolRun:
    """Hold threads (and RAM) of the machine-wide pool while a run lasts.

    ``threads`` is the run's class (``model_threads``), or 1 for a run that does not solve.
    ``ram_gb`` is the RAM it needs: its last recorded peak, or ``DEFAULT_RAM_GB``.
    ``set(threads, phase)`` lowers what the run holds (after barrier, for reporting).
    ``pool <= 0`` disables the pool: the run starts at once and holds nothing.
    ``waited_s`` is the time spent waiting to start (not part of the run's wall time).
    ``measure=False`` leaves out the measured load and RAM (tests).
    """

    def __init__(self, label: str, threads: int, ram_gb: float = DEFAULT_RAM_GB, *, pool: int | None = None,
                 keep_free: int | None = None, max_parallel: int | None = None, slot_dir: Path | None = None,
                 poll_s: float = 30.0, timeout_s: float | None = None, measure: bool = True):
        self.label = label
        self.threads = max(1, int(threads))
        self.ram_gb = max(0.0, float(ram_gb))
        self.pool = default_pool() if pool is None else pool
        self.keep_free = default_keep_free() if keep_free is None else keep_free
        self.max_parallel = default_max_parallel() if max_parallel is None else max_parallel
        self.slot_dir = Path(slot_dir) if slot_dir else default_slot_dir()
        self.poll_s = poll_s
        self.timeout_s = timeout_s
        self.measure = measure
        self.path: Path | None = None
        self.waited_s = 0.0
        self.phase = "start"

    def _fits(self, runs: list[dict]) -> str:
        """Empty if the run can start now, else why not."""
        held = sum(int(r.get("threads", 0)) for r in runs)
        if held + self.threads > self.pool - self.keep_free:
            return f"{held} of {self.pool - self.keep_free} threads reserved, {self.threads} needed"
        if self.max_parallel > 0 and len(runs) >= self.max_parallel:
            return f"{len(runs)} runs (limit {self.max_parallel})"
        if not self.measure:
            return ""
        mem = ram_gb()
        if mem is not None:
            reserved = sum(float(r.get("ram_gb", 0.0)) for r in runs)
            if reserved + self.ram_gb > 0.9 * mem[0]:
                return f"{reserved:.0f} of {0.9 * mem[0]:.0f} GB RAM reserved, {self.ram_gb:.0f} GB needed"
            if mem[1] < self.ram_gb:
                return f"{mem[1]:.0f} GB RAM free, {self.ram_gb:.0f} GB needed"
        busy = cpus_busy(1.0)
        n = os.cpu_count() or self.pool
        if busy is not None and busy + self.threads + self.keep_free > n:
            return f"{busy:.0f} of {n} CPUs busy (measured), {self.threads} + {self.keep_free} needed"
        return ""

    def _write(self) -> None:
        info = {"pid": os.getpid(), "label": self.label, "threads": self.threads, "ram_gb": round(self.ram_gb, 1),
                "phase": self.phase, "since": time.strftime("%Y-%m-%dT%H:%M:%S")}
        tmp = self.path.with_name(self.path.stem + ".tmp")
        tmp.write_text(json.dumps(info))
        os.replace(tmp, self.path)

    def __enter__(self) -> "PoolRun":
        if self.pool <= 0:
            return self
        self.slot_dir.mkdir(parents=True, exist_ok=True)
        t0 = time.monotonic()
        announced = ""
        while True:
            with _Lock(self.slot_dir):
                why = self._fits(ledger(self.slot_dir))
                if not why:
                    self.path = self.slot_dir / f"run-{os.getpid()}-{uuid.uuid4().hex[:8]}.json"
                    self._write()
                    self.waited_s = time.monotonic() - t0
                    return self
            if self.timeout_s is not None and time.monotonic() - t0 > self.timeout_s:
                raise TimeoutError(f"{self.label}: no room in the run pool after {self.timeout_s} s ({why})")
            if why != announced:
                print(f"  waiting for the run pool: {why} ({self.slot_dir})", flush=True)
                announced = why
            time.sleep(self.poll_s)

    def set(self, threads: int, phase: str) -> None:
        """Lower what the run holds; it never rises (under the rule a run does not re-acquire)."""
        self.threads, self.phase = max(1, min(int(threads), self.threads)), phase
        if self.path is not None:
            with _Lock(self.slot_dir):
                self._write()

    def __exit__(self, *exc) -> None:
        if self.path is not None:
            try:
                self.path.unlink()
            except OSError:
                pass
            self.path = None


# ---- GAMS runs: the phase from the log

_BARRIER_END = re.compile(r"^\s*Barrier time\s*=", re.IGNORECASE)                 # CPLEX
_SOLVE_END = re.compile(r"^--- (Reading solution|Executing after solve|Restarting execution)", re.IGNORECASE)
_STEPPED = re.compile(r"^\s*\$\s*SET\s+(TIMESTEP|FIXBOH)\s+'?(\d+)", re.IGNORECASE | re.MULTILINE)


def runfile_solves_once(text: str) -> bool:
    """False for a stepped run, which solves once per step: ``$SET TIMESTEP <n>`` or ``$SET FIXBOH <n>``
    with n > 0 (the stepped runs of make_reference.py)."""
    return not any(int(m.group(2)) > 0 for m in _STEPPED.finditer(text))


class GamsWatch:
    """Follows a GAMS run: lowers the pool hold at the phases the log shows, and records the peak RAM.

    For a run with one SOLVE and CPLEX's log: at "Barrier time =" the run keeps
    ``AFTER_BARRIER_THREADS``, and when GAMS reads the solution back it keeps 1.
    Any other run (several SOLVEs, another solver) keeps its class to the end.
    """

    def __init__(self, run: PoolRun, log: Path, pid: int, single_solve: bool, poll_s: float = 2.0):
        self.run, self.log, self.pid = run, log, pid
        self.single_solve, self.poll_s = single_solve, poll_s
        self.peak_ram_gb = 0.0
        self.phases: list[tuple[float, str, int]] = []
        self._pos = 0
        self._after_barrier = False
        self._t0 = time.monotonic()

    def _mark(self, threads: int, phase: str) -> None:
        self.run.set(threads, phase)
        self.phases.append((round(time.monotonic() - self._t0, 1), phase, self.run.threads))

    def poll(self) -> None:
        r = process_tree_ram_gb(self.pid)
        if r is not None:
            self.peak_ram_gb = max(self.peak_ram_gb, r)
        if not self.single_solve or not self.log.exists():
            return
        try:
            with open(self.log, "r", errors="replace") as f:
                f.seek(self._pos)
                chunk = f.read()
                self._pos = f.tell()
        except OSError:
            return
        for ln in chunk.splitlines():
            if not self._after_barrier and _BARRIER_END.match(ln):
                self._after_barrier = True
                self._mark(AFTER_BARRIER_THREADS, "crossover")
            elif self._after_barrier and _SOLVE_END.match(ln) and self.run.phase != "reporting":
                self._mark(1, "reporting")
