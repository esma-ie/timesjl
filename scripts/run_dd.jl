# Run a TIMES model from its own run file and DD files with TIMES.jl alone, no GAMS:
#
#   julia --project=test scripts/run_dd.jl <run file> [--dd <folder> ...] [--solve] [--out <folder>] [--licence-level n]
#
# The run file is the one VEDA writes (or one edited by hand). --dd gives the folders its DD files are
# in, searched in order; without it, the run file's own folder. The TIMES source is the pinned
# download (times_source(); TIMESJL_TIMES_SOURCE names a local clone instead). --licence-level is GAMS's
# %SYSTEM.LICENSELEVEL%: 0 by default, as a full licence; 2 gives a demo licence's model (VAR_UC YES,
# initmty.mod L448; docs/known-differences.md K3).
#
# Steps, each reported on a line starting `==`:
#   1. compile the run file and its DD files as GAMS's compile phase does (src/dd/compile.jl) and
#      write the result as an input dump (write_dump) to --out (a temporary folder by default);
#   2. preprocess: the M1.3 chain and the M1.2 coefficients, to the pre-solve state;
#   3. generate the model (rows, columns, nonzeros);
#   4. with --solve, solve it with HiGHS (TIMESJL_THREADS threads, 12 by default) and print the objective.
# The QA log TIMES writes (QA_CHECK.LOG) goes to the --out folder. A TIMES feature that TIMES.jl does
# not translate yet stops the run with "not translated" and the GAMS lines it would need.
#
# Results come with no comparison: to check them against GAMS, use scripts/m13_gate.jl --from-dd on a
# suite reference. Licences: CLAUDE.md, "Test-model licences" (this script runs any model, but what it
# shows about a model without an open licence must not enter the repository).

include(joinpath(@__DIR__, "m13_gate.jl"))     # compile_run, write_dump, GATE_SEGMENTS, gate_steps, run_switches, ...

function run_dd(args)
    args = collect(args)
    solve = "--solve" in args
    filter!(!=("--solve"), args)
    dd, out, level = String[], nothing, 0
    while (i = findfirst(a -> a in ("--dd", "--out", "--licence-level"), args)) !== nothing
        a, v = args[i], args[i+1]
        a == "--dd" ? push!(dd, abspath(v)) : a == "--out" ? (out = abspath(v)) : (level = parse(Int, v))
        deleteat!(args, i:i+1)
    end
    length(args) == 1 || error("usage: julia --project=test scripts/run_dd.jl <run file> [--dd <folder> ...] [--solve] [--out <folder>] [--licence-level n]")
    run = abspath(args[1])
    isfile(run) || error("no run file $run")
    isempty(dd) && push!(dd, dirname(run))
    out = something(out, mktempdir())
    name = splitext(basename(run))[1]

    # As the reference harness does (make_reference.py, runfile.py): a copy of the run file with
    # SOLVE_NOW NO just before maindrv.mod, so that GAMS's solve and report files (solve.mod L22,
    # maindrv.mod L114) are not compiled; TIMES.jl solves the model itself. The original is untouched.
    lines = readlines(run)
    i = findlast(l -> occursin(r"^\s*\$\s*batinclude\s+maindrv\.mod"i, l), lines)
    i === nothing && error("$run has no \$BATINCLUDE maindrv.mod line")
    insert!(lines, i, "\$SET SOLVE_NOW NO")
    mkpath(out)
    run2 = joinpath(out, basename(run))
    write(run2, join(lines, "\n") * "\n")
    t = @elapsed g = compile_run(run2; dirs=dd, licencelevel=level, globals=Dict("RUN_NAME" => name))
    tw = @elapsed write_dump(g, out; source="$name: compiled from its DD files by TIMES.jl")
    println("== $name: compiled in $(round(t; digits=1)) s ($(g.warnings) compile warnings), input written to $out in ",
            round(tw; digits=1), " s")
    sw = run_switches(run)
    tm = TimesModel(out; switches=sw, reduce=uppercase(get(sw, "REDUCE", "NO")) == "YES")
    qa_warnings!(tm, g.warnings)                  # $IF WARNINGS (ppmain.mod L35)

    tp = 0.0
    for (a, b) in GATE_SEGMENTS
        try
            tp += @elapsed foreach(f -> f(tm), gate_steps(a))
        catch e
            e isa TIMES.UnportedError || rethrow()
            println("== $name: not translated, in $a -> $b: ", sprint(showerror, e))
            return false
        end
    end
    write(joinpath(out, "QA_CHECK.LOG"), qa_text(tm))
    println("== $name: preprocessed in $(round(tp; digits=1)) s; QA log in ", joinpath(out, "QA_CHECK.LOG"))

    tg = @elapsed generate!(tm)
    m = tm.model
    println("== $name: model generated in $(round(tg; digits=1)) s: ", JuMP.num_constraints(m; count_variable_in_set_constraints=false),
            " rows, ", JuMP.num_variables(m), " columns")
    solve || return true
    JuMP.set_optimizer(m, HiGHS.Optimizer)
    JuMP.set_silent(m)
    JuMP.set_attribute(m, "threads", parse(Int, get(ENV, "TIMESJL_THREADS", "12")))
    ts = @elapsed JuMP.optimize!(m)
    st = JuMP.termination_status(m)
    println("== $name: HiGHS ", st, " in ", round(ts; digits=1), " s",
            st == JuMP.OPTIMAL ? ", objective $(JuMP.objective_value(m))" : "")
    return st == JuMP.OPTIMAL
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_dd(ARGS)
end
