# Layer 3 with NVIDIA cuOpt on the GPU: the model TIMES.jl generates for a
# reference run, solved by cuOpt with one pinned method at a time, against
# every GAMS optimum of that run (objective, rtol 1e-6, and our optimum
# feasible in GAMS's matrix, 1e-6: the layer-3 tolerances of
# docs/translation-guide.md).
#
# An informational lane (scripts/cuopt/README.md): no pull request waits on it,
# and it never changes what TIMES.jl generates. Layer 2 runs first, and a run
# whose matrix differs from GAMS's is reported as skipped, so a cuOpt result
# is never read against a translation error.
#
#   julia --project=scripts/cuopt scripts/cuopt/cuopt_layer3.jl <out.json> [--fixtures] [--only p1,p2 | all]
#   julia --project=scripts/cuopt scripts/cuopt/cuopt_layer3.jl <out.json> --ref <dir> [--root name=path ...] <model> ...
#
# Options:
#   --method m       barrier, pdlp or dual_simplex; repeat for several (default: barrier, pdlp).
#                    cuOpt's default "concurrent" is not offered: it returns whichever
#                    method finishes first, so two nights would not be comparable.
#   --gate m1,m2     methods whose failures set the exit code (default: barrier)
#   --pdlp-tol x     PDLP's six stopping tolerances (default 1e-6; cuOpt's own is 1e-4)
#   --time-limit s   per solve (default 3600)
#   --summary f.md   also write a Markdown table (the nightly workflow's job summary)
#   --quiet          no cuOpt log
#
# Barrier and PDLP run with crossover, so the point compared is a vertex.
# CPU threads follow the local run limits (CLAUDE.md): TIMESJL_THREADS, default 12.
# They bound cuOpt's CPU-side work only (presolve, the host side of barrier's
# factorisation, crossover); the GPU is never limited by them. A share of the
# GPU is set from outside the process by scripts/cuopt/sweep.sh (NVIDIA MPS),
# which passes it here in TIMESJL_GPU_SHARE (percent) and TIMESJL_MPS (on/off)
# for the report.
#
# Writes check results only (counts, statuses, objectives, timings), in the
# record shape of scripts/parity_report.jl. A run of a model that is not
# `redistribute = "public"` (TIM) stays on James's machine: never commit,
# attach or publish its JSON.

import cuOpt, Printf
include(joinpath(@__DIR__, "..", "parity_report.jl"))   # REPO, SUITE, points_from_solution, points_from_manifest,
                                                          # runfile_of, run_switches, suite_switches, parse_probe_args
const MOI = JuMP.MOI

# cuOpt's method codes (cuopt_c.h, via cuOpt.jl)
const METHODS = Dict("barrier" => cuOpt.CUOPT_METHOD_BARRIER, "pdlp" => cuOpt.CUOPT_METHOD_PDLP,
                     "dual_simplex" => cuOpt.CUOPT_METHOD_DUAL_SIMPLEX)

Base.@kwdef struct Settings
    methods::Vector{String} = ["barrier", "pdlp"]
    gate::Set{String} = Set(["barrier"])
    pdlp_tol::Float64 = 1e-6
    time_limit::Float64 = 3600.0
    threads::Int = parse(Int, get(ENV, "TIMESJL_THREADS", "12"))
    quiet::Bool = false
end

label(m) = m == "dual_simplex" ? "dual simplex" : m * " + crossover"

"""
The cuOpt parameters of one method, by their C API names (cuOpt 26.10,
`solver_settings.cu`). Everything not set here keeps cuOpt's default,
including its LP presolve.
"""
function cuopt_parameters(method, s::Settings)
    p = Dict{String,Any}(cuOpt.CUOPT_METHOD => METHODS[method],
                         cuOpt.CUOPT_CROSSOVER => method != "dual_simplex",
                         cuOpt.CUOPT_NUM_CPU_THREADS => s.threads)
    if method == "pdlp"
        for t in (cuOpt.CUOPT_ABSOLUTE_PRIMAL_TOLERANCE, cuOpt.CUOPT_RELATIVE_PRIMAL_TOLERANCE,
                  cuOpt.CUOPT_ABSOLUTE_DUAL_TOLERANCE, cuOpt.CUOPT_RELATIVE_DUAL_TOLERANCE,
                  cuOpt.CUOPT_ABSOLUTE_GAP_TOLERANCE, cuOpt.CUOPT_RELATIVE_GAP_TOLERANCE)
            p[t] = s.pdlp_tol
        end
    end
    # the same factorisation every night (cuDSS's deterministic mode)
    method == "barrier" && (p[cuOpt.CUOPT_CUDSS_DETERMINISTIC] = true)
    return p
end

function gpu_info()
    for q in ("name,driver_version,memory.total,compute_cap", "name,driver_version,memory.total")
        try
            return strip(readchomp(pipeline(`nvidia-smi --query-gpu=$q --format=csv,noheader`; stderr=devnull)))
        catch
        end
    end
    return "unknown (nvidia-smi failed)"
end

function cuopt_version()
    try
        return MOI.get(cuOpt.Optimizer(), MOI.SolverVersion())
    catch e
        return "unknown: " * first(sprint(showerror, e), 200)
    end
end

function skipped!(checks, run, points, methods, why)
    for p in points, m in methods
        push!(checks, Dict{String,Any}("run" => run, "layer" => 3, "unit" => "$(p.solver) vs cuOpt $m", "method" => m,
                                       "gams_solver" => p.solver, "status" => "skipped", "gate" => false,
                                       "n_compared" => 0, "n_excluded" => 0, "n_mismatch" => 0, "detail" => [why]))
    end
end

"""
One reference run: generate, check the matrix (layer 2, as the precondition),
then one cuOpt solve per method, each compared with every GAMS optimum.
"""
function cuopt_checks!(checks, runrec, run, presolve, matrix, dictmap, points, switches, reduce, s::Settings, version)
    live = [p for p in points if p.skip === nothing]
    for p in points
        p.skip === nothing && continue
        skipped!(checks, run, [p], s.methods, p.skip)
    end
    isempty(live) && return
    tm = TimesModel(presolve; reduce, switches)
    u = untranslated_families(tm)
    if !isempty(u)
        skipped!(checks, run, live, s.methods, "TIMES.jl does not generate this model yet: " *
                 join(unique(x.family for x in u), ", "))
        return
    end
    tg = try
        @elapsed generate!(tm)
    catch e
        e isa UnportedError || rethrow()
        skipped!(checks, run, live, s.methods, "TIMES.jl refuses this model: " * first(sprint(showerror, e), 400))
        return
    end
    mine = canonical_from_jump(tm.model)
    ref = canonical_from_dump(matrix, dictmap)
    runrec["rows"], runrec["cols"], runrec["nonzeros"] = length(ref.rows), length(ref.cols), length(ref.coefs)
    runrec["generate_seconds"] = round(tg; digits=3)
    cmp = compare_lp(mine, ref)
    runrec["layer2"] = ispass(cmp) ? "pass" : "fail"
    if !ispass(cmp)
        skipped!(checks, run, live, s.methods, "layer 2 fails (the matrix differs from GAMS's): " *
                 join(first(cmp.examples, 3), "; "))
        return
    end
    # free what the solve does not need, as parity_report.jl does
    mine = nothing
    empty!(tm.cache); empty!(tm.data.sets); empty!(tm.data.params)
    GC.gc(true)
    for method in s.methods
        JuMP.set_optimizer(tm.model, cuOpt.Optimizer)
        for (k, v) in cuopt_parameters(method, s)
            JuMP.set_attribute(tm.model, k, v)
        end
        JuMP.set_time_limit_sec(tm.model, s.time_limit)
        s.quiet && JuMP.set_silent(tm.model)
        println("   cuOpt ", label(method), " ..."); flush(stdout)
        err, wall, tsolver = nothing, NaN, NaN
        try
            wall = @elapsed JuMP.optimize!(tm.model)
            tsolver = JuMP.solve_time(tm.model)
        catch e
            err = first(sprint(showerror, e), 600)
        end
        term = err === nothing ? JuMP.termination_status(tm.model) : nothing
        ok = term == JuMP.OPTIMAL && JuMP.primal_status(tm.model) == JuMP.FEASIBLE_POINT
        obj = ok ? JuMP.objective_value(tm.model) : NaN
        x = ok ? Dict(jump_name_key(JuMP.name(v)) => JuMP.value(v) for v in JuMP.all_variables(tm.model)) :
                 Dict{String,Float64}()
        mine_in_gams = ok ? evaluate_point(ref, x) : nothing
        for p in live
            rec = Dict{String,Any}("run" => run, "layer" => 3, "unit" => "$(p.solver) vs cuOpt $method",
                                   "gams_solver" => p.solver, "method" => method, "gate" => method in s.gate,
                                   "julia_solver" => "cuOpt $version, $(label(method))",
                                   "gams_objective" => p.objective, "julia_objective" => obj,
                                   "rel_diff" => ok ? abs(obj - p.objective) / abs(p.objective) : NaN,
                                   "solve_seconds" => round(wall; digits=2), "cuopt_seconds" => round(tsolver; digits=2),
                                   "termination" => term === nothing ? "error" : string(term),
                                   "n_compared" => 1, "n_excluded" => 0)
            detail = String[]
            err === nothing || push!(detail, "error: " * err)
            err === nothing && !ok && push!(detail, "cuOpt: $(term), primal $(JuMP.primal_status(tm.model)) " *
                                                    "($(JuMP.raw_status(tm.model)))")
            feasible = false
            if mine_in_gams !== nothing
                rec["mine_in_gams_violation"] = max(mine_in_gams.max_row_violation, mine_in_gams.max_bound_violation)
                feasible = mine_in_gams.feasible && isempty(mine_in_gams.missing_columns)
                feasible || push!(detail, "cuOpt's optimum violates the GAMS LP by " *
                                          "$(round(rec["mine_in_gams_violation"]; sigdigits=3))" *
                                          (isempty(mine_in_gams.worst_rows) ? "" : " at $(mine_in_gams.worst_rows[1][1])"))
            end
            rec["status"] = ok && isapprox(obj, p.objective; rtol=1e-6) && feasible ? "pass" : "fail"
            rec["n_mismatch"] = rec["status"] == "pass" ? 0 : 1
            rec["detail"] = detail
            push!(checks, rec)
        end
    end
end

function fixture_runs!(out, s, version; only=nothing)
    fxdir = joinpath(REPO, "test", "fixtures")
    for fx in TOML.parsefile(joinpath(fxdir, "public_fixtures.toml"))["fixture"]
        run = fx["prefix"]
        only === nothing || run in only || continue
        p(part) = joinpath(fxdir, run * "_" * part)
        (isdir(p("presolve")) && isdir(p("matrix")) && isfile(p("solution.json"))) || continue
        m = SUITE[fx["model"]]
        runrec = Dict{String,Any}("id" => run, "model" => fx["model"], "variant" => get(fx, "variant", ""),
                                  "licence" => m["licence"], "redistribute" => m["redistribute"], "source" => "test/fixtures (CI)")
        println("== ", run); flush(stdout)
        sw = Dict{String,String}(k => string(v) for (k, v) in get(fx, "switches", Dict()))
        guarded!(out["checks"], run, s) do
            cuopt_checks!(out["checks"], runrec, run, p("presolve"), joinpath(p("matrix"), "matrix"),
                          joinpath(p("matrix"), "dictmap"), points_from_solution(p("solution.json")), sw,
                          get(fx, "reduce", false), s, version)
        end
        push!(out["runs"], runrec)
        GC.gc(true)
    end
end

function reference_runs!(out, s, version, refdir, models, roots)
    for model in models
        variant = "reduce_off"
        dir = joinpath(refdir, model, variant)
        isfile(joinpath(dir, "manifest.json")) || (println("   ", model, ": no reduce_off reference; skipped"); continue)
        man = JSON.parsefile(joinpath(dir, "manifest.json"))
        m = get(SUITE, model, Dict("licence" => "?", "redistribute" => "?"))
        m["redistribute"] == "public" ||
            println("   ", model, ": not redistribute = \"public\"; keep this report on this machine (CLAUDE.md)")
        run = "$(model)-$(variant)"
        runrec = Dict{String,Any}("id" => run, "model" => model, "variant" => variant, "licence" => m["licence"],
                                  "redistribute" => m["redistribute"], "source" => "reference run (local)")
        println("== ", model); flush(stdout)
        guarded!(out["checks"], run, s) do
            rf = runfile_of(refdir, model, variant)
            sw = rf === nothing ? suite_switches(model, man, roots) : run_switches(rf)
            cuopt_checks!(out["checks"], runrec, run, joinpath(dir, "presolve"), joinpath(dir, "matrix"),
                          joinpath(dir, "matrix_dictmap"), points_from_manifest(dir, man), sw, false, s, version)
        end
        push!(out["runs"], runrec)
        GC.gc(true)
    end
end

"An error in one run (before any solve) is recorded as a gate failure, and the next run goes on."
function guarded!(f, checks, run, s)
    try
        f()
    catch e
        push!(checks, Dict{String,Any}("run" => run, "layer" => 3, "unit" => "run", "status" => "fail", "gate" => true,
                                       "n_compared" => 0, "n_excluded" => 0, "n_mismatch" => 1,
                                       "detail" => ["error: " * first(sprint(showerror, e), 600)]))
    end
end

"JSON has no NaN: a value that was not computed (no optimum) is written as null."
finite(x::AbstractDict) = Dict{String,Any}(string(k) => finite(v) for (k, v) in x)
finite(x::AbstractVector) = Any[finite(v) for v in x]
finite(x::AbstractFloat) = isfinite(x) ? x : nothing
finite(x) = x

fmt(x) = x isa Real && isfinite(x) ? Printf.@sprintf("%.2e", x) : "–"
secs(x) = x isa Real && isfinite(x) ? string(round(x; digits=1)) : "–"

function write_summary(io, out)
    m = out["meta"]
    println(io, "## cuOpt layer 3\n")
    println(io, "cuOpt ", m["cuopt_version"], " on ", m["gpu"], " (GPU share ", m["gpu_share"], "%, MPS ", m["mps"],
            "; ", m["threads"], " CPU threads); commit `", m["commit"], "`, Julia ", m["julia"], ", ",
            m["date"], " UTC. Methods: ", join(label.(m["methods"]), ", "), "; gating: ",
            isempty(m["gate"]) ? "none" : join(m["gate"], ", "), ". Pass = objective within 1e-6 of GAMS's and ",
            "cuOpt's optimum feasible in GAMS's matrix (1e-6).\n")
    println(io, "| Run | GAMS | cuOpt method | Status | Rel. diff | Ours in GAMS | cuOpt s | Wall s |")
    println(io, "| --- | --- | --- | --- | --- | --- | --- | --- |")
    for c in out["checks"]
        st = c["status"] == "pass" ? "✅ pass" : c["status"] == "fail" ? (get(c, "gate", false) ? "❌ fail" : "⚠️ fail") : "➖ " * c["status"]
        println(io, "| ", c["run"], " | ", get(c, "gams_solver", "–"), " | ", get(c, "method", "–"), " | ", st, " | ",
                fmt(get(c, "rel_diff", NaN)), " | ", fmt(get(c, "mine_in_gams_violation", NaN)), " | ",
                secs(get(c, "cuopt_seconds", NaN)), " | ", secs(get(c, "solve_seconds", NaN)), " |")
    end
    notes = [(c["run"], get(c, "method", ""), d) for c in out["checks"] if c["status"] != "pass" for d in c["detail"]]
    isempty(notes) && return
    println(io, "\n<details><summary>Details</summary>\n")
    for (r, mth, d) in notes
        println(io, "- ", r, " ", mth, ": ", replace(d, "|" => "\\|"))
    end
    println(io, "\n</details>")
end

function parse_args(args)
    isempty(args) && error("usage: cuopt_layer3.jl <out.json> [--fixtures [--only p1,p2] | --ref <dir> [--root n=p ...] <model> ...] " *
                           "[--method m ...] [--gate m1,m2] [--pdlp-tol x] [--time-limit s] [--summary f.md] [--quiet]")
    outfile, rest = args[1], String[]
    methods, gate, kw = String[], nothing, Dict{Symbol,Any}()
    summary, only = nothing, nothing
    i = 2
    while i <= length(args)
        a = args[i]
        val() = (i < length(args) || error("$a needs a value"); args[i+1])
        if a == "--method"
            m = val(); haskey(METHODS, m) || error("--method: one of $(join(sort!(collect(keys(METHODS))), ", ")) " *
                                                   "(concurrent is not offered)")
            push!(methods, m); i += 2
        elseif a == "--gate"
            gate = Set(filter(!isempty, split(val(), ","))); i += 2
        elseif a == "--pdlp-tol"
            kw[:pdlp_tol] = parse(Float64, val()); i += 2
        elseif a == "--time-limit"
            kw[:time_limit] = parse(Float64, val()); i += 2
        elseif a == "--summary"
            summary = val(); i += 2
        elseif a == "--only"
            o = val(); only = o == "all" ? nothing : Set(split(o, ",")); i += 2
        elseif a == "--quiet"
            kw[:quiet] = true; i += 1
        else
            push!(rest, a); i += 1
        end
    end
    isempty(methods) || (kw[:methods] = unique(methods))
    gate === nothing || (kw[:gate] = Set{String}(gate))
    s = Settings(; kw...)
    all(g -> haskey(METHODS, g), s.gate) || error("--gate: unknown method in $(join(s.gate, ","))")
    return outfile, rest, s, summary, only
end

function cuopt_main(args)
    outfile, rest, s, summary, only = parse_args(args)
    version = cuopt_version()
    commit = try string(LibGit2.head_oid(LibGit2.GitRepo(REPO)))[1:9] catch; "unknown" end
    out = Dict{String,Any}("meta" => Dict{String,Any}("lane" => "cuopt", "commit" => commit, "julia" => string(VERSION),
                                                      "date" => string(Dates.now(Dates.UTC)), "host" => gethostname(),
                                                      "times_version" => "4.9.7 @ d9a6a25", "threads" => s.threads,
                                                      "cuopt_version" => version, "gpu" => gpu_info(),
                                                      "methods" => s.methods, "gate" => sort!(collect(s.gate)),
                                                      "pdlp_tol" => s.pdlp_tol, "time_limit" => s.time_limit,
                                                      "gpu_share" => parse(Int, get(ENV, "TIMESJL_GPU_SHARE", "100")),
                                                      "mps" => get(ENV, "TIMESJL_MPS", "off"),
                                                      "parameters" => Dict(m => cuopt_parameters(m, s) for m in s.methods)),
                           "runs" => Any[], "checks" => Any[])
    println("cuOpt ", version, " on ", out["meta"]["gpu"])
    if isempty(rest) || rest[1] == "--fixtures"
        fixture_runs!(out, s, version; only)
    elseif rest[1] == "--ref"
        refdir, roots, models = parse_probe_args(rest[2:end])
        reference_runs!(out, s, version, refdir, models, roots)
    else
        error("unknown option $(rest[1])")
    end
    open(io -> JSON.print(io, finite(out), 1), outfile, "w")
    summary === nothing || open(io -> write_summary(io, out), summary, "w")
    write_summary(stdout, out)
    bad = [c for c in out["checks"] if c["status"] == "fail" && get(c, "gate", false)]
    npass = count(c -> c["status"] == "pass", out["checks"])
    println("wrote ", outfile, ": ", length(out["runs"]), " runs, ", npass, " of ", length(out["checks"]), " checks pass, ",
            length(bad), " gating failures")
    return isempty(bad) && !isempty(out["checks"]) ? 0 : 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(cuopt_main(ARGS))
end
