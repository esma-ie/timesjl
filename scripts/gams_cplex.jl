# CPLEX for TIMES.jl's own LP, run inside GAMS through GAMS.jl (James, 22 Nov 2026: "2, go ahead";
# #182 d5 option (b), which reverses "(c) HiGHS only for now"). Used by scripts/m13_gate.jl --solver cplex.
#
# Why through GAMS: the only CPLEX on James's workstation is the one in GAMS 54, licensed "for use
# within GAMS/Base" only (GAMS EULA, Exhibit A; C:\GAMS\54\EULA.md L491). GAMS.jl writes the JuMP
# model as a GAMS model (moi.gms), runs gams.exe on it with solver=CPLEX, and reads the solution back,
# so CPLEX is called by GAMS as in any GAMS run. CPLEX.jl, which calls CPLEX directly, is not used.
#
# The LP CPLEX solves is TIMES.jl's (the model generate! built, checked against GAMS's CONVERT matrix
# at layer 2 just before); GAMS only passes it on. Its rows and columns are in TIMES.jl's order and
# carry GAMS.jl's own names (x1, eq1, ...), so CPLEX may take another path than on GAMS's LP.
#
# Options as in the GAMS/CPLEX reference run (reference/python/make_reference.py, find_solver_opts and
# prepare_workdir): the model's own cplex.opt (suite.toml `solver_opt_dir`), every `threads` line set
# to the run limit (runlimits.py, limit_threads), and GAMS's own threads= at the same limit.
#
# Times: GAMS reports the solver's own time as the model attribute etSolver, the measure of the
# GAMS/CPLEX reference runs (manifest.json, solveinfo etsolver; dashboard slide 12, "solve"). GAMS.jl
# writes the model attributes to <job>_stats.gdx in its work folder; it keeps only resUsd for
# MOI.SolveTimeSec, so etSolver is read from that file here, with GAMS.jl's own GDX reader (GAMS.jl
# internals, hence compat "0.5" in test/Project.toml). The rest of the wall time of optimize! is the
# handover: JuMP to GAMS.jl, writing moi.gms, GAMS's compilation and generation of it, and reading
# the solution back. It is not CPLEX's and not TIMES.jl's own work, so it is reported apart.

import GAMS, JuMP

"""
GAMS's system folder for GAMS.jl: `TIMESJL_GAMS_SYSDIR`, else the folder of `gams` on PATH, else
`C:\\GAMS\\54` (CLAUDE.md: every reference run is made with GAMS 54).
"""
function gams_sysdir()
    d = get(ENV, "TIMESJL_GAMS_SYSDIR", "")
    isempty(d) || return d
    g = Sys.which("gams")
    return g === nothing ? raw"C:\GAMS\54" : dirname(g)
end

"""
    gams_model_stats(work) -> Dict{String,Float64}

The model attributes GAMS.jl's job wrote to `<job>_stats.gdx` in the work folder `work` (etSolver,
etSolve, resUsd, modelStat, ...), read as GAMS.jl reads them itself (GAMS.jl 0.5, src/GAMS.jl `run`).
"""
function gams_model_stats(work)
    files = filter(endswith("_stats.gdx"), readdir(work; join=true))
    length(files) == 1 || error("GAMS.jl's work folder $work has $(length(files)) *_stats.gdx files, not one")
    stats = Dict{String,Float64}()
    gdx = GAMS.GDXHandle()
    GAMS.gdx_create(gdx)
    try
        GAMS.gdx_open_read(gdx, files[1])
        idx = Vector{Int}(undef, 1)
        vals = Vector{Float64}(undef, max(GAMS.GAMS_VALUE_LEVEL, GAMS.GAMS_VALUE_MARGINAL))
        n = GAMS.gdx_data_read_raw_start(gdx, 2)        # symbol 2: the parameter stats(attr)
        for _ in 1:n
            GAMS.gdx_data_read_raw(gdx, idx, vals)
            stats[GAMS.GAMS_MODEL_ATTRIBUTES[idx[1]]] = GAMS.parse_gdx_value(vals[GAMS.GAMS_VALUE_LEVEL])
        end
        GAMS.gdx_data_read_done(gdx)
        GAMS.gdx_close(gdx)
    finally
        GAMS.gdx_free(gdx)
    end
    return stats
end

"""
    solve_cplex_in_gams!(m; optfile, threads, time_limit) -> NamedTuple

Solve the JuMP model `m` with CPLEX inside GAMS (GAMS.jl). `optfile` is the model's cplex.opt or
`nothing`; each of its options goes to CPLEX as written, but a `threads` line, which takes the run
limit `threads` (as the reference harness's limit_threads does). `time_limit` is GAMS's reslim, in
seconds.

Returns `(status, wall, solver, handover, options)`: the termination status, the wall time of
`optimize!`, CPLEX's own time as GAMS reports it (etSolver; `nothing` if GAMS wrote none), the
handover (`wall - solver`) and the options given to CPLEX. GAMS.jl's work folder is removed after.
"""
function solve_cplex_in_gams!(m::JuMP.Model; optfile=nothing, threads::Integer, time_limit::Real)
    # GAMS.jl makes its own work folder (gams_jl_*) at optimize!. It is not set here: GAMS.jl 0.5.4
    # swaps the system and work folders when both are given (src/MOI_wrapper.jl L161 against
    # src/GAMS.jl L243), so the folder is asked for after the solve.
    work = nothing
    try
        JuMP.set_optimizer(m, GAMS.Optimizer)
        JuMP.set_attribute(m, GAMS.SysDir(), gams_sysdir())
        JuMP.set_attribute(m, "Solver", "CPLEX")
        JuMP.set_silent(m)
        JuMP.set_time_limit_sec(m, Float64(time_limit))
        JuMP.set_attribute(m, "threads", Int(threads))        # GAMS's threads= (make_reference.py)
        given = Pair{String,String}[]
        for (k, v) in (optfile === nothing ? Pair{String,String}[] : TIMES.read_optfile(optfile))
            k == "threads" && continue                       # replaced by the run limit, below
            # an option GAMS.jl takes for GAMS's command line (reslim, optcr, ...) goes there; the
            # others go into the cplex.opt GAMS.jl writes (GAMS.jl 0.5, src/moi/options.jl)
            JuMP.set_attribute(m, k, v)
            push!(given, k => v)
        end
        if optfile !== nothing
            # the threads line of the file, at the run limit (runlimits.py limit_threads); GAMS.jl
            # routes the name "threads" to GAMS's command line, which CPLEX takes as its default
            push!(given, "threads" => string(threads))
        end
        wall = @elapsed JuMP.optimize!(m)
        work = JuMP.get_attribute(m, GAMS.WorkDir())
        st = gams_model_stats(work)
        es = get(st, "etSolver", NaN)
        solver = isfinite(es) ? es : nothing
        return (status=JuMP.termination_status(m), wall=wall, solver=solver,
                handover=solver === nothing ? nothing : max(wall - solver, 0.0), options=given)
    finally
        # also after a failed solve, so that no large moi.gms stays in the temporary folder
        work === nothing && (work = try JuMP.get_attribute(m, GAMS.WorkDir()) catch; nothing end)
        work === nothing || rm(work; recursive=true, force=true)
    end
end
