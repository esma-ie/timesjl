# The run pool's phase markers (James, 26 Nov 2026; reference/python/pool_run.py, runlimits.py).
# This file holds no translated GAMS statement and touches no model: it prints one line.
#
# On James's workstation a run reserves its thread class in a machine-wide pool from its start and
# keeps fewer threads once its solve is over. A Julia run joins the pool through the launcher
# `reference/python/pool_run.py`, which reserves the class, starts Julia with TIMESJL_POOL_MARKERS
# set, and lowers the hold when it reads a marker line on Julia's standard output:
#
#     [timesjl-pool] phase=<name>
#
# The phases: `after-barrier` (the interior point method is over, crossover runs) and `reporting`
# (every solve of the process is over). The launcher never raises a hold, so a marker is printed
# only when no solve follows it in the process: after the last solve, or not at all. Without a
# marker the run keeps its class to its end.
#
# Without TIMESJL_POOL_MARKERS (any run not started by the launcher) nothing is printed.

"The environment variable `pool_run.py` sets for the run it starts; unset, empty or 0: no marker."
const POOL_MARKERS_ENV = "TIMESJL_POOL_MARKERS"

"The phases of a run that `pool_run.py` knows."
const POOL_PHASES = ("after-barrier", "reporting")

"""
    pool_phase(phase; io=stdout) -> Bool

Tell the run pool's launcher (`reference/python/pool_run.py`) that the run has reached `phase`
(`"after-barrier"` or `"reporting"`): print the line `[timesjl-pool] phase=<phase>` to `io` and
flush it. Nothing is printed, and `false` returned, unless the launcher started the run
(`TIMESJL_POOL_MARKERS` set and not 0).

Call it with `"reporting"` only after the last solve of the process: the launcher then keeps one
thread for the run, and nothing is re-acquired. `run_model` calls it with `pool_markers=true`.
"""
function pool_phase(phase::AbstractString; io::IO=stdout)
    phase in POOL_PHASES || throw(ArgumentError("pool phase $phase: the phases are " * join(POOL_PHASES, ", ")))
    get(ENV, POOL_MARKERS_ENV, "") in ("", "0") && return false
    print(io, "[timesjl-pool] phase=" * phase * "\n")       # one write: one line
    flush(io)
    return true
end
