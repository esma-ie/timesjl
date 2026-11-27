# Run a TIMES model from its own run file and DD files with TIMES.jl alone, no GAMS:
#
#   julia --project=test scripts/run_dd.jl <run file> [--dd <folder> ...] [--solve] [--out <folder>] [--licence-level n] [--optfile <file> | --no-optfile]
#
# The run file is the one VEDA writes (or one edited by hand). --dd gives the folders its DD files are
# in, searched in order; without it, the run file's own folder. The TIMES source is the pinned
# download (times_source(); TIMESJL_TIMES_SOURCE names a local clone instead). --licence-level is GAMS's
# %SYSTEM.LICENSELEVEL%: 0 by default, as a full licence; 2 gives a demo licence's model (VAR_UC YES,
# initmty.mod L448; docs/known-differences.md K3). --optfile names the solver option file; without it,
# highs.opt in the run file's folder is read if there is one, as GAMS reads <solver>.opt there
# (solve.mod L14-15); --no-optfile reads none. The file has GAMS's option-file form (`solver ipm`,
# `run_crossover=off`, `*` comments) with HiGHS's option names; a line HiGHS does not take is left
# out with a note, and the threads limit stays (src/solver_options.jl). VEDA's cplex.opt is not
# read: the run says so.
#
# Steps, each reported on a line starting `==`:
#   1. compile the run file and its DD files as GAMS's compile phase does (src/dd/compile.jl) and
#      write the result as an input dump (write_dump) to --out (a temporary folder by default);
#   2. preprocess: the M1.3 chain and the M1.2 coefficients, to the pre-solve state;
#   3. generate the model (rows, columns, nonzeros);
#   4. with --solve, solve it with HiGHS (TIMESJL_THREADS threads, 12 by default), print the objective and
#      write the solution (levels and marginals of every variable and equation) to <out>/solution/ in the
#      harness's dump layout (write_solution, issue #97; reference/python/gdx2arrow.py, format version 1).
# A stepped (myopic) run (TIMESTEP) has no single model: step 3 is skipped, and with --solve the run
# is solved step by step (`solve_stepped!`, solve.stp; one line per step). Its solution is not written
# to <out>/solution/ yet (M1.6).
# The QA log TIMES writes (QA_CHECK.LOG) goes to the --out folder. A TIMES feature that TIMES.jl does
# not translate yet stops the run with "not translated" and the GAMS lines it would need.
#
# Since 18 Nov 2026 the run itself is `TIMES.run_model` (src/run.jl), so it can be used without this
# script: `using TIMES; run_model("<run file>")`. This script reads the arguments and calls it.
#
# Results come with no comparison: to check them against GAMS, use scripts/m13_gate.jl --from-dd on a
# suite reference. Licences: CLAUDE.md, "Test-model licences" (this script runs any model, but what it
# shows about a model without an open licence must not enter the repository).

using TIMES

function run_dd(args; pool_markers::Bool=false)
    args = collect(args)
    solve = "--solve" in args
    optfile = "--no-optfile" in args ? false : nothing
    filter!(a -> !(a in ("--solve", "--no-optfile")), args)
    dd, out, level = String[], nothing, 0
    while (i = findfirst(a -> a in ("--dd", "--out", "--licence-level", "--optfile"), args)) !== nothing
        a, v = args[i], args[i+1]
        a == "--dd" ? push!(dd, v) : a == "--out" ? (out = v) : a == "--optfile" ? (optfile = v) : (level = parse(Int, v))
        deleteat!(args, i:i+1)
    end
    length(args) == 1 || error("usage: julia --project=test scripts/run_dd.jl <run file> [--dd <folder> ...] [--solve] [--out <folder>] [--licence-level n] [--optfile <file> | --no-optfile]")
    return run_model(args[1]; dd=dd, out=out, solve=solve, optfile=optfile, licence_level=level, pool_markers=pool_markers).ok
end

if abspath(PROGRAM_FILE) == @__FILE__
    # one run, one solve: under the run pool's launcher (reference/python/pool_run.py) the run keeps one
    # thread once the solve is over (TIMES.pool_phase); without the launcher nothing changes
    run_dd(ARGS; pool_markers=true)
end
