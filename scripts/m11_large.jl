# Layers 2 and 3 for models too large to check in one process of an 8 GB
# machine (a million rows or more), in three stages, each its own process,
# sharing files in <work dir>:
#
#   julia --project=test scripts/m11_large.jl build <reference dir> <model> <work dir> [--root name=path ...]
#   julia --project=test scripts/m11_large.jl solve <reference dir> <model> <work dir> [--root name=path ...]
#   julia --project=test scripts/m11_large.jl check <reference dir> <model> <work dir>
#
# build: generate the model from the pre-solve dump, save its canonical LP
#        (compact: names once, coefficients as index triplets), then compare
#        it with the CONVERT export (layer 2, 1e-9).
# solve: solve the saved TIMES.jl LP with HiGHS (C API; log in
#        <work dir>/highs.log); save status, objective and column values.
# check: layer 3 as in m11_probe.jl: the HiGHS objective against each GAMS
#        objective (1e-6), the HiGHS optimum feasible in the GAMS model and
#        each GAMS optimum feasible, with its objective, in the TIMES.jl model.
# Same checks as m11_probe.jl (reduce_off), split so that no process holds
# the model, both canonical LPs and the solver at once.

include(joinpath(@__DIR__, "m11_probe.jl"))   # run_switches, runfile_of, suite_switches
using TIMES.Reference: CanonicalLP, RowData, ColData
using Serialization, SparseArrays

"The TimesModel of a reference run, generated, with its data caches released."
function build_model(refdir, model, roots; variant="reduce_off")
    dir = joinpath(refdir, model, variant)
    m = JSON.parsefile(joinpath(dir, "manifest.json"))
    rf = runfile_of(refdir, model, variant)
    sw = rf === nothing ? suite_switches(model, m, roots) : run_switches(rf)
    tm = TimesModel(joinpath(dir, "presolve"); switches=sw)
    t = @elapsed generate!(tm)
    println("   generated in $(round(t; digits=1)) s"); flush(stdout)
    empty!(tm.cache); empty!(tm.data.sets); empty!(tm.data.params)
    GC.gc(true)
    return tm, dir, m
end

"Canonical LP as plain arrays: row and column names once, coefficients as (row, column, value)."
function save_compact(path, lp::CanonicalLP)
    rnames = collect(keys(lp.rows)); cnames = collect(keys(lp.cols))
    ri = Dict(k => Int32(i) for (i, k) in enumerate(rnames)); ci = Dict(k => Int32(i) for (i, k) in enumerate(cnames))
    I = Vector{Int32}(undef, length(lp.coefs)); J = similar(I); V = Vector{Float64}(undef, length(lp.coefs))
    for (n, ((r, c), v)) in enumerate(lp.coefs)
        I[n] = ri[r]; J[n] = ci[c]; V[n] = v
    end
    rows = [(lp.rows[k].lo, lp.rows[k].hi) for k in rnames]
    cols = [(lp.cols[k].lb, lp.cols[k].ub, lp.cols[k].obj, lp.cols[k].integer) for k in cnames]
    serialize(path, (; rnames, cnames, rows, cols, I, J, V, objsense=lp.objsense, objconstant=lp.objconstant))
end

function load_compact(path)
    s = deserialize(path)
    rows = Dict(k => RowData(b...) for (k, b) in zip(s.rnames, s.rows))
    cols = Dict(k => ColData(b...) for (k, b) in zip(s.cnames, s.cols))
    coefs = Dict{Tuple{String,String},Float64}()
    sizehint!(coefs, length(s.V))
    for n in eachindex(s.V)
        coefs[(s.rnames[s.I[n]], s.cnames[s.J[n]])] = s.V[n]
    end
    return CanonicalLP(rows, cols, coefs, s.objsense, s.objconstant)
end

function stage_build(refdir, model, work, roots)
    tm, dir, _ = build_model(refdir, model, roots)
    mine = canonical_from_jump(tm.model)
    tm = nothing
    save_compact(joinpath(work, "mine.jls"), mine)
    GC.gc(true)
    ref = canonical_from_dump(joinpath(dir, "matrix"), joinpath(dir, "matrix_dictmap"))
    r = compare_lp(mine, ref)
    sz = "$(length(ref.rows)) rows, $(length(ref.cols)) cols, $(length(ref.coefs)) nz"
    println("== ", model, ": layer 2 ", ispass(r) ? "PASS" : "MISMATCH", " ($sz)")
    ispass(r) || (println(r); foreach(e -> println("     ", e), r.examples))
end

"""
HiGHS on the TIMES.jl model as the build stage saved it (the canonical LP read
from the JuMP backend: every row, column, coefficient, bound and the
objective), passed through the HiGHS C API. Solving the JuMP model itself
needs the model and HiGHS's copy in one process, which does not fit a model
of that size in 8 GB.
"""
function stage_solve(model, work)
    s = deserialize(joinpath(work, "mine.jls"))
    any(c -> c[4], s.cols) && error("integer columns: not an LP")
    nr, nc = length(s.rnames), length(s.cnames)
    A = sparse(s.I, s.J, s.V, nr, nc)                 # a canonical LP has no repeated (row, column)
    nnz(A) == length(s.V) || error("repeated or zero coefficients in the saved LP")
    HI = HiGHS.HighsInt
    h = HiGHS.Highs_create()
    try
        HiGHS.Highs_setBoolOptionValue(h, "log_to_console", 0)
        # local run limit (James, 29 Oct 2026): at most 12 threads per run
        HiGHS.Highs_setIntOptionValue(h, "threads", parse(Int, get(ENV, "TIMESJL_THREADS", "12")))
        HiGHS.Highs_setStringOptionValue(h, "log_file", joinpath(work, "highs.log"))
        HiGHS.Highs_setStringOptionValue(h, "solver", "ipm")    # interior point, then crossover
        sense = s.objsense == :min ? HiGHS.kHighsObjSenseMinimize : HiGHS.kHighsObjSenseMaximize
        st = HiGHS.Highs_passLp(h, HI(nc), HI(nr), HI(nnz(A)), HiGHS.kHighsMatrixFormatColwise, sense,
                                s.objconstant, [c[3] for c in s.cols], [c[1] for c in s.cols], [c[2] for c in s.cols],
                                [r[1] for r in s.rows], [r[2] for r in s.rows],
                                HI.(A.colptr[1:end-1] .- 1), HI.(A.rowval .- 1), A.nzval)
        st == HiGHS.kHighsStatusError && error("Highs_passLp failed")
        A = nothing; GC.gc(true)
        t = @elapsed HiGHS.Highs_run(h)
        TIMES.pool_phase("reporting")     # the run pool (reference/python/pool_run.py): the one solve of this process is over
        ms = HiGHS.Highs_getModelStatus(h)
        ok = ms == HiGHS.kHighsModelStatusOptimal
        obj = ok ? HiGHS.Highs_getObjectiveValue(h) : NaN
        x, xd, rv, rd = zeros(nc), zeros(nc), zeros(nr), zeros(nr)
        ok && HiGHS.Highs_getSolution(h, x, xd, rv, rd)
        status = ok ? "OPTIMAL" : "HiGHS model status $ms"
        serialize(joinpath(work, "highs.jls"), (; status, obj, seconds=t, names=s.cnames, vals=x))
        println("== ", model, ": HiGHS ", status, " in ", round(Int, t), " s, objective ", obj)
    finally
        HiGHS.Highs_destroy(h)
    end
end

function stage_check(refdir, model, work)
    dir = joinpath(refdir, model, "reduce_off")
    m = JSON.parsefile(joinpath(dir, "manifest.json"))
    sol = deserialize(joinpath(work, "highs.jls"))
    sol.status == "OPTIMAL" || (println("== ", model, ": layer 3 FAIL (HiGHS ", sol.status, ")"); return)
    mine = load_compact(joinpath(work, "mine.jls"))
    parts = ["obj " * string(round(sol.obj; sigdigits=12)) * " in $(round(Int, sol.seconds)) s"]
    ok = true
    # GAMS optima: evaluated in the TIMES.jl LP now, in the GAMS LP once it is loaded.
    pending = []
    for (tag, run) in sort!(collect(m["runs"]); by=first)
        startswith(tag, "solve_") || continue
        s = uppercase(tag[7:end])
        si = get(run, "solveinfo", nothing)
        if run["returncode"] != 0 || si === nothing || get(si, "modelstat", 0) != 1
            push!(parts, "no GAMS optimum from $s"); continue
        end
        gobj = Float64(si["objval"])
        fd = isdir(joinpath(dir, "final_" * lowercase(s))) ? "final_" * lowercase(s) : "final"
        x = solution_levels(joinpath(dir, fd); columns=keys(mine.cols))
        push!(pending, (s, gobj, x, evaluate_point(mine, x; nworst=typemax(Int))))
    end
    mine = nothing
    GC.gc(true)
    ref = canonical_from_dump(joinpath(dir, "matrix"), joinpath(dir, "matrix_dictmap"))
    for (s, gobj, x, g) in pending
        gref = g.feasible ? g : evaluate_point(ref, x; nworst=typemax(Int))
        same = isapprox(sol.obj, gobj; rtol=1e-6)
        cross = as_feasible_as(g, gref) && isapprox(g.objective, gobj; rtol=1e-6)
        ok &= same && cross
        push!(parts, "$s " * (same ? "=" : "≠ $(gobj)") *
                     (!cross ? " (GAMS optimum not feasible/optimal here: $(g.max_row_violation), $(g.max_bound_violation))" :
                      g.feasible ? "" : " (" * own_violation(gref) * ")"))
    end
    pending = nothing
    e = evaluate_point(ref, Dict(zip(sol.names, sol.vals)))
    feas = e.feasible && isempty(e.missing_columns)
    ok &= feas
    feas || push!(parts, "HiGHS optimum not feasible in GAMS model: rows $(e.max_row_violation), bounds $(e.max_bound_violation), missing $(length(e.missing_columns))")
    println("== ", model, ": layer 3 ", ok ? "PASS" : "FAIL", " (", join(parts, ", "), ")")
end

function main_large(args)
    stage, refdir, model, work = args[1:4]
    roots = Dict{String,String}()
    for i in 5:2:length(args)
        args[i] == "--root" || error("unexpected argument $(args[i])")
        k, v = split(args[i+1], "="; limit=2)
        roots[k] = abspath(v)
    end
    mkpath(work)
    stage == "build" ? stage_build(refdir, model, work, roots) :
    stage == "solve" ? stage_solve(model, work) :
    stage == "check" ? stage_check(refdir, model, work) : error("stage must be build, solve or check")
end

main_large(ARGS)
