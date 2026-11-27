# M1.1 work list: for each reference run, what TIMES.jl still lacks to
# generate it, and (when the run has a CONVERT export) whether the part it
# can generate already matches GAMS.
#
#   julia --project=. scripts/m11_probe.jl <reference dir> [--variant as_run] [--root name=path ...] [<model> ...]
#
# <reference dir> holds <model>/<variant>/ runs from make_reference.py. The
# reduce_off runs are probed, or the as_run ones with `--variant as_run`
# (%REDUCE% YES in the suite: cal_red.red, M1.3 change 17b). Switches are
# read from the run file the harness generated (raw/ or _work/), so they
# match the GAMS run; for zips from harness < 0.2.2, which hold no run file,
# they are rebuilt from reference/suite.toml (--root fills the placeholders of
# run-file models, e.g. --root times_demo=../TIMES_Demo).

using TIMES
using TIMES: TimesModel, untranslated_families, generate!, UnportedError, stepped
using TIMES.Reference: canonical_from_dump, canonical_from_jump, compare_lp, ispass, evaluate_point,
                       solution_levels, jump_name_key
import JSON, JuMP, HiGHS, TOML

"Values of `\$SET` switches in a TIMES run file: `TIMES.run_switches` (src/run.jl)."
run_switches(path) = TIMES.run_switches(path)

function runfile_of(refdir, model, variant)
    for p in (joinpath(refdir, model, variant, "raw", "tjl_convert.run"),        # harness >= 0.2.2
              joinpath(refdir, "_work", model, variant, "convert", "tjl_reference.run"),
              joinpath(refdir, "_work", model, variant, "presolve", "tjl_reference.run"))
        isfile(p) && return p
    end
    return nothing
end

"""
Switches for a run whose run file was not kept (zips from harness < 0.2.2):
the `\$SET` lines of the file make_reference.prepare_workdir patches (the DD
template, or the suite's run file with `--root name=path` filled in), then the
manifest's overrides, as runfile.patch_run applies them. Not for runs whose
switches are set in an included file (a scenario file the run file includes).
"""
function suite_switches(model, manifest, roots)
    repo = dirname(@__DIR__)
    entry = manifest["suite_entry"]
    path = if entry["kind"] == "dd"
        joinpath(repo, "reference", "templates", "scenario.run")
    else
        suite = TOML.parsefile(joinpath(repo, "reference", "suite.toml"))
        e = only(filter(m -> m["name"] == model, suite["model"]))
        p = e["run_file"]
        for (k, v) in roots
            p = replace(p, "{$k}" => v)
        end
        occursin('{', p) && error("$model: pass --root for $(p) to rebuild its switches")
        p
    end
    sw = run_switches(path)
    for (k, v) in manifest["overrides"]
        sw[uppercase(k)] = string(v)
    end
    return sw
end

function probe(refdir, model; variant="reduce_off", roots=Dict{String,String}(), pool_last::Bool=false)
    dir = joinpath(refdir, model, variant)
    isfile(joinpath(dir, "manifest.json")) || return (; model, status="no reference")
    m = JSON.parsefile(joinpath(dir, "manifest.json"))
    dumps = m["dumps"]
    get(dumps, "presolve", nothing) === nothing && return (; model, status="no presolve dump")
    rc = get(get(m["runs"], "presolve", Dict()), "returncode", 0)
    rc == 0 || return (; model, status="GAMS pre-solve run failed (return code $rc; see raw/tjl_presolve.lst)")
    rf = runfile_of(refdir, model, variant)
    sw = rf === nothing ? suite_switches(model, m, roots) : run_switches(rf)
    # %REDUCE% YES selects cal_red.red (pp_reduce.red L58-59; `$IF %REDUCE%==YES` compares case-sensitively)
    tm = TimesModel(joinpath(dir, "presolve"); reduce=strip(get(sw, "REDUCE", "")) == "YES", switches=sw)
    u = untranslated_families(tm)
    size = get(get(get(m["runs"], "convert", Dict()), "solveinfo", Dict()), "numequ", nothing)
    hasmatrix = get(dumps, "matrix", nothing) !== nothing
    if !isempty(u)
        return (; model, status="needs", families=unique(x.family for x in u), why=u, hasmatrix)
    end
    # A stepped (myopic) run has no single LP, and its pre-solve dump is the state after the loop of
    # solve.stp: solve_stepped! solves it step by step, and scripts/m13_gate.jl checks each step.
    stepped(tm) && return (; model, status="stepped run: one LP per step, checked by scripts/m13_gate.jl", hasmatrix)
    try
        generate!(tm)
    catch e
        e isa UnportedError || rethrow()
        return (; model, status="unported path", detail=sprint(showerror, e), hasmatrix)
    end
    hasmatrix || return (; model, status="generates; no CONVERT export to check (licence)", hasmatrix)
    # The model is built: drop the data caches before the two canonical LPs (large models).
    empty!(tm.cache); empty!(tm.data.sets); empty!(tm.data.params)
    GC.gc(true)
    mine = canonical_from_jump(tm.model)
    GC.gc(true)
    ref = canonical_from_dump(joinpath(dir, "matrix"), joinpath(dir, "matrix_dictmap"))
    GC.gc(true)
    r = compare_lp(mine, ref)
    sz = "$(length(ref.rows)) rows, $(length(ref.cols)) cols, $(length(ref.coefs)) nz"
    ispass(r) || return (; model, status="MISMATCH ($sz)", report=r, hasmatrix)
    println("   ", model, ": layer 2 PASS ($sz)"); flush(stdout)       # before the (long) solve
    mref = Ref{Any}(mine)
    mine = nothing
    return (; model, status="PASS layer 2 ($sz); " * layer3(tm, mref, ref, dir, m; pool_last), report=r, hasmatrix)
end

"""
    as_feasible_as(g, gref; tol=1e-6) -> Bool

Cross-evaluation of a GAMS optimum: `g` is its evaluation in the TIMES.jl LP,
`gref` in the GAMS LP itself (CONVERT export), both from `evaluate_point`
with every violated row listed. Passes when the point is feasible at `tol`
here, or when every row it violates here by more than `tol` it violates at
least as much in the GAMS LP, and no bound more than there. The second case
is a reference optimum outside its own model's tolerance (CPLEX;
docs/known-differences.md K1), which no translation can
make feasible.
"""
function as_feasible_as(g, gref; tol=1e-6)
    g.feasible && return true
    vref = Dict(gref.worst_rows)
    return all(((k, v),) -> v <= tol || v <= get(vref, k, 0.0) + 1e-12, g.worst_rows) &&
           g.max_bound_violation <= max(tol, gref.max_bound_violation) + 1e-12
end

"Text for a GAMS optimum that violates its own model by more than 1e-6 (see as_feasible_as)."
own_violation(gref) = "its optimum violates the GAMS LP by $(round(gref.max_row_violation; sigdigits=3))" *
                      (isempty(gref.worst_rows) ? "" : " at $(gref.worst_rows[1][1])") * ", identically here"

"""
Layer 3: HiGHS optimum of the TIMES.jl model against each GAMS objective, and
each optimum feasible and optimal in the other model (rtol 1e-6). The GAMS
optima are evaluated first; then the canonical TIMES.jl LP (`mref[]`) and
the dump caches are released before the solve, to keep memory down.
"""
function layer3(tm, mref, ref, dir, manifest; pool_last::Bool=false)
    runs = manifest["runs"]
    gams = Dict{String,Tuple{Float64,String}}()
    skipped = String[]
    for (tag, run) in runs
        startswith(tag, "solve_") || continue
        s = uppercase(tag[7:end])
        # A solve that did not finish optimal (e.g. GAMS/HiGHS without a licence
        # above the demo limits: return code 3, no solveinfo) is no reference.
        si = get(run, "solveinfo", nothing)
        if run["returncode"] != 0 || si === nothing || get(si, "modelstat", 0) != 1
            push!(skipped, s)
            continue
        end
        fd = isdir(joinpath(dir, "final_" * lowercase(s))) ? "final_" * lowercase(s) : "final"
        gams[s] = (Float64(run["solveinfo"]["objval"]), joinpath(dir, fd))
    end
    cross = Dict{String,Bool}()
    note = Dict{String,String}()
    for (s, (gobj, fd)) in gams
        mine = mref[]
        x = solution_levels(fd; columns=keys(mine.cols))
        g = evaluate_point(mine, x; nworst=typemax(Int))
        gref = g.feasible ? g : evaluate_point(ref, x; nworst=typemax(Int))
        cross[s] = as_feasible_as(g, gref) && isapprox(g.objective, gobj; rtol=1e-6)
        cross[s] && !g.feasible && (note[s] = " (" * own_violation(gref) * ")")
    end
    mref[] = nothing
    empty!(tm.cache); empty!(tm.data.sets); empty!(tm.data.params)
    GC.gc(true)
    JuMP.set_optimizer(tm.model, HiGHS.Optimizer)
    # local run limit (James, 29 Oct 2026): at most 12 threads per run
    JuMP.set_attribute(tm.model, "threads", parse(Int, get(ENV, "TIMESJL_THREADS", "12")))
    JuMP.set_silent(tm.model)
    # Interior point (then crossover) above 100,000 rows; HiGHS's default below.
    length(ref.rows) > 100_000 && JuMP.set_attribute(tm.model, "solver", "ipm")
    t = @elapsed JuMP.optimize!(tm.model)
    # the run pool (reference/python/pool_run.py): after the last solve of the process the run keeps 1 thread
    pool_last && TIMES.pool_phase("reporting")
    JuMP.termination_status(tm.model) == JuMP.OPTIMAL || return "layer 3 FAIL: HiGHS " * string(JuMP.termination_status(tm.model))
    obj = JuMP.objective_value(tm.model)
    x = Dict(jump_name_key(JuMP.name(v)) => JuMP.value(v) for v in JuMP.all_variables(tm.model))
    e = evaluate_point(ref, x)
    ok = e.feasible && isempty(e.missing_columns)
    parts = ["obj " * string(round(obj; sigdigits=12)) * (t > 60 ? " in $(round(Int, t)) s" : "")]
    for (s, (gobj, fd)) in sort!(collect(gams))
        same = isapprox(obj, gobj; rtol=1e-6)
        ok &= same && cross[s]
        push!(parts, "$s " * (same ? "=" : "≠ $(gobj)") * (cross[s] ? get(note, s, "") : " (GAMS optimum not feasible/optimal here)"))
    end
    isempty(skipped) || push!(parts, "no GAMS optimum from " * join(skipped, ", "))
    length(parts) > 1 + !isempty(skipped) || (ok = false)
    return (ok ? "layer 3 PASS (" : "layer 3 FAIL (") * join(parts, ", ") * ")"
end

"Split `<refdir> [--root name=path ...] [<model> ...]`; no model = every model in refdir."
function parse_probe_args(args)
    refdir = args[1]
    roots, rest = Dict{String,String}(), String[]
    i = 2
    while i <= length(args)
        if args[i] == "--root"
            k, v = split(args[i+1], "="; limit=2)
            roots[k] = abspath(v)
            i += 2
        else
            push!(rest, args[i])
            i += 1
        end
    end
    models = isempty(rest) ? sort(filter(d -> isdir(joinpath(refdir, d)) && !startswith(d, "_"), readdir(refdir))) : rest
    return refdir, roots, models
end

function main(args)
    args = collect(args)
    variant = "reduce_off"
    i = findfirst(==("--variant"), args)
    i === nothing || (variant = args[i+1]; deleteat!(args, i:i+1))
    refdir, roots, models = parse_probe_args(args)
    for (k, model) in enumerate(models)
        res = try
            probe(refdir, model; roots, variant, pool_last=k == length(models))
        catch e
            (; model, status="error", detail=sprint(showerror, e))
        end
        println("== ", model, ": ", res.status)
        if hasproperty(res, :why)
            for x in res.why
                println("     ", rpad(x.family, 44), " ", x.gams, "  [", x.why, "]")
            end
        end
        hasproperty(res, :detail) && println("     ", first(res.detail, 600))
        hasproperty(res, :report) && startswith(res.status, "MISMATCH") && (println(res.report); foreach(e -> println("     ", e), res.report.examples))
    end
end

# Run only as a script; scripts/m11_timing.jl includes this file for its helpers.
if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
