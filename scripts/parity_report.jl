# Parity report: every GAMS-parity check TIMES.jl can run on a reference
# (layer 1 per coefficient file, layer 2 by equation family, layer 3 per GAMS
# solver), written as one JSON file for docs/dashboard (the parity dashboard).
#
#   julia --project=test scripts/parity_report.jl <out.json> [--fixtures] [--embed]   # the public fixtures
#   julia --project=test scripts/parity_report.jl <out.json> --ref <dir> [--root name=path ...] [<model> ...]
#   ... [--no-solve]: layer 3 by cross-evaluating the GAMS optima only, no HiGHS solve
#
# `--embed` also writes the report into docs/dashboard/index.html (the parity
# dashboard), which is how the committed page is refreshed: the public fixtures
# into its `report` block, or with `--embed-as <id>` into another block of the
# page (`report-suite`: the reference runs of the public suite models).
#
# `--fixtures` (the default) reports every entry of test/fixtures/public_fixtures.toml.
# `--ref` reports the reduce_off runs of a reference directory as
# reference/python/make_reference.py writes them
# (<dir>/<model>/reduce_off/{manifest.json,ppm,coef,presolve,matrix,matrix_dictmap,final*}):
# the GAMS optima for layer 3 come from the manifest (each optimal solve_<solver>
# run) and its final dumps, so James can report TIM locally; nothing of a run is
# written but the check results (counts, statuses, objectives, timings): no model data.
# A model TIMES.jl cannot generate yet is recorded as refused (with the families
# it lacks), and an error in one model is recorded as a failed check; the other
# models are still reported.
#
# Record shapes (all in one object):
#   meta:    commit, julia, date, host, threads
#   runs[]:  model, variant, licence, redistribute, rows/cols/nonzeros of the GAMS matrix
#   checks[]: run, layer (1|2|3), unit (file / family / solver), status
#             (pass|fail|refused|skipped), n_compared, n_excluded, n_mismatch,
#             seconds, detail (first examples or the refusal), symbols[] (layer 1)

import JSON, TOML, JuMP, HiGHS, Dates, LibGit2
using TIMES
using TIMES: TimesModel, DumpData, generate!, untranslated_families, layer1, later_overwrites, ctst, UnportedError, stepped,
             coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!
using TIMES.Reference: canonical_from_jump, canonical_from_dump, compare_lp, evaluate_point, ispass, family, jump_name_key,
                       solution_levels

const REPO = dirname(@__DIR__)
# --no-solve: layer 3 by cross-evaluating each GAMS optimum in our LP, without the
# HiGHS solve (for models HiGHS does not solve in reasonable time, e.g. OTUS9r)
const NO_SOLVE = Ref(false)
include(joinpath(@__DIR__, "m12_probe.jl"))        # M12_STEPS; via m11_probe.jl: run_switches, runfile_of,
                                                    # suite_switches, parse_probe_args, as_feasible_as, own_violation

# the suite models and the crafted demo12 cases (reference/crafted.toml), whose fixtures CI also holds
const SUITE = Dict(m["name"] => m for f in ("suite.toml", "crafted.toml")
                   for m in TOML.parsefile(joinpath(REPO, "reference", f))["model"])

function layer1_checks!(checks, run, ppm, coef, switches)
    tm = TimesModel(ppm; switches)
    ref = DumpData(coef)
    for (name, f, syms, extra) in M12_STEPS
        rec = Dict{String,Any}("run" => run, "layer" => 1, "unit" => name)
        try
            t = @elapsed f(tm)
            names = vcat(syms, extra(tm))
            later = later_overwrites(tm; after=name)
            r = layer1(tm, ref, names; exclude=later)
            nleft(n) = !haskey(later, n) ? 0 : ref.dump.symbols[n].kind == :set ?
                       count(later[n], TIMES.gset(ref, n).keys) : count(later[n], keys(TIMES.gparam(ref, n).values))
            rec["status"] = all(ispass, r) ? "pass" : "fail"
            rec["n_compared"] = sum(d -> d.n_ref, r)
            rec["n_excluded"] = sum(nleft, names)
            rec["n_mismatch"] = sum(d -> d.only_mine + d.only_ref + d.values, r)
            rec["seconds"] = round(t; digits=3)
            rec["symbols"] = [Dict("name" => d.name, "n" => d.n_ref, "status" => ispass(d) ? "pass" : "fail",
                                   "mismatch" => d.only_mine + d.only_ref + d.values) for d in r]
            rec["detail"] = first(vcat((d.examples for d in r if !ispass(d))...), 5)
        catch e
            # a refusal (untranslated branch) or an error stops the steps after it
            rec["status"] = e isa UnportedError ? "refused" : "fail"
            rec["detail"] = [(e isa UnportedError ? "" : "error: ") * first(sprint(showerror, e), 600)]
            push!(checks, rec)
            break
        end
        push!(checks, rec)
    end
end

"""
GAMS optima for layer 3, one per GAMS solver: `(solver, objective, levels, skip)`.
`levels(columns)` returns the column levels of that optimum (or `nothing`);
`skip` is the reason there is no optimum to compare with (or `nothing`).
"""
function points_from_solution(solfile)
    isfile(solfile) || return NamedTuple[]
    sol = JSON.parsefile(solfile)
    return [(; solver, objective=Float64(gobj), skip=nothing,
              levels=haskey(sol, "levels_" * solver) ? (cols -> Dict{String,Float64}(sol["levels_" * solver])) : (cols -> nothing))
            for (solver, gobj) in sol["objval"]]
end

"As `points_from_solution`, from a harness manifest and its final dumps (as m11_probe.jl's layer 3)."
function points_from_manifest(dir, manifest)
    out = NamedTuple[]
    for (tag, run) in sort!(collect(manifest["runs"]); by=first)
        startswith(tag, "solve_") || continue
        s = uppercase(tag[7:end])
        si = get(run, "solveinfo", nothing)
        if run["returncode"] != 0 || si === nothing || isempty(si) || get(si, "modelstat", 0) != 1
            push!(out, (; solver=s, objective=NaN, levels=(cols -> nothing),
                          skip="GAMS/$s: return code $(run["returncode"]), no optimal solution"))
            continue
        end
        fd = isdir(joinpath(dir, "final_" * lowercase(s))) ? joinpath(dir, "final_" * lowercase(s)) : joinpath(dir, "final")
        push!(out, (; solver=s, objective=Float64(si["objval"]), skip=nothing,
                      levels=isdir(fd) ? (cols -> solution_levels(fd; columns=cols)) : (cols -> nothing)))
    end
    return out
end

refused!(checks, run, layer, unit, detail) =
    push!(checks, Dict{String,Any}("run" => run, "layer" => layer, "unit" => unit, "status" => "refused",
                                   "n_compared" => 0, "n_excluded" => 0, "n_mismatch" => 0, "detail" => detail))

function layer23_checks!(checks, runrec, run, presolve, matrix, dictmap, points, switches, reduce; pool_last::Bool=false)
    tm = TimesModel(presolve; reduce, switches)
    # a model with switches or families TIMES.jl does not generate yet (m11_probe.jl's work list)
    u = untranslated_families(tm)
    if !isempty(u)
        refused!(checks, run, 2, "matrix", ["needs $(x.family): $(x.gams) [$(x.why)]" for x in u])
        return
    end
    # A stepped (myopic) run has no single LP (one per step, solve.stp), and its pre-solve dump is the
    # state after the loop: its steps are checked one by one by scripts/m13_gate.jl and in CI
    # (test/unit/test_solve_stp.jl), not here.
    if stepped(tm)
        push!(checks, Dict{String,Any}("run" => run, "layer" => 2, "unit" => "matrix", "status" => "skipped",
                                       "n_compared" => 0, "n_excluded" => 0, "n_mismatch" => 0,
                                       "detail" => ["stepped run: one LP per step, checked by scripts/m13_gate.jl"]))
        return
    end
    t = try
        @elapsed generate!(tm)
    catch e
        e isa UnportedError || rethrow()
        refused!(checks, run, 2, "matrix", [first(sprint(showerror, e), 600)])
        return
    end
    mine = canonical_from_jump(tm.model)
    ref = canonical_from_dump(matrix, dictmap)
    runrec["rows"], runrec["cols"], runrec["nonzeros"] = length(ref.rows), length(ref.cols), length(ref.coefs)
    runrec["generate_seconds"] = round(t; digits=3)
    cmp = compare_lp(mine, ref)
    # one check per equation family (rows GAMS vs ours), plus the whole-matrix entry check
    fams = sort!(unique(vcat([family(k) for k in keys(ref.rows)], [family(k) for k in keys(mine.rows)])))
    badfam = Dict{String,Int}()
    for ex in cmp.examples
        m = match(r"^[a-z_]+: ([A-Za-z_]+)", ex)
        m === nothing || (badfam[family(m[1])] = get(badfam, family(m[1]), 0) + 1)
    end
    for fam in fams
        nm = count(k -> family(k) == fam, keys(mine.rows)); nr = count(k -> family(k) == fam, keys(ref.rows))
        push!(checks, Dict{String,Any}("run" => run, "layer" => 2, "unit" => fam, "status" => (nm == nr && !haskey(badfam, fam)) ? "pass" : "fail",
                           "n_compared" => nr, "n_excluded" => 0, "n_mismatch" => abs(nm - nr) + get(badfam, fam, 0),
                           "detail" => nm == nr ? String[] : ["rows $nm vs $nr"]))
    end
    push!(checks, Dict{String,Any}("run" => run, "layer" => 2, "unit" => "matrix", "status" => ispass(cmp) ? "pass" : "fail",
                       "n_compared" => length(ref.coefs) + length(ref.rows) + length(ref.cols), "n_excluded" => 0,
                       "n_mismatch" => sum(values(cmp.counts); init=0), "detail" => first(cmp.examples, 5),
                       "counts" => Dict(string(k) => v for (k, v) in cmp.counts)))
    # layer 3: GAMS solvers without an optimum are recorded as skipped (e.g. GAMS/HiGHS
    # above the licence limits); the HiGHS solve runs only when there is something to compare
    for p in points
        p.skip === nothing && continue
        push!(checks, Dict{String,Any}("run" => run, "layer" => 3, "unit" => p.solver, "status" => "skipped",
                                       "n_compared" => 0, "n_excluded" => 0, "n_mismatch" => 0, "detail" => [p.skip]))
    end
    live = [p for p in points if p.skip === nothing]
    isempty(live) && return
    # each GAMS optimum in our LP first (then the data caches go, before the solve, as in m11_probe.jl)
    gpts = Dict{String,Any}()
    for p in live
        x = p.levels(keys(mine.cols))
        x === nothing && continue
        g = evaluate_point(mine, x; nworst=typemax(Int))
        gref = g.feasible ? g : evaluate_point(ref, x; nworst=typemax(Int))
        gpts[p.solver] = (; g, gref, ok=as_feasible_as(g, gref) && isapprox(g.objective, p.objective; rtol=1e-6))
    end
    if NO_SOLVE[]
        # --no-solve: layer 3 by cross-evaluation only (scripts/m13_cross_eval.jl; OTUS9r, PR #61):
        # each GAMS optimum's objective in our LP against GAMS's, and its feasibility here
        # as in GAMS's own matrix. No HiGHS solve, so no "ours in GAMS's matrix" check.
        for p in live
            rec = Dict{String,Any}("run" => run, "layer" => 3, "unit" => p.solver, "gams_objective" => p.objective,
                                   "julia_solver" => "none (GAMS optimum cross-evaluated, --no-solve)",
                                   "n_excluded" => 0, "n_compared" => 1)
            if haskey(gpts, p.solver)
                gp = gpts[p.solver]
                rec["julia_objective"] = gp.g.objective
                rec["rel_diff"] = abs(gp.g.objective - p.objective) / abs(p.objective)
                rec["gams_in_mine_violation"] = max(gp.g.max_row_violation, gp.g.max_bound_violation)
                rec["gams_in_mine_ok"] = gp.ok
                rec["status"] = gp.ok ? "pass" : "fail"
                rec["detail"] = ["cross-evaluation only (no HiGHS solve)"]
                gp.ok && !gp.g.feasible && push!(rec["detail"], own_violation(gp.gref))
            else
                rec["status"] = "fail"
                rec["detail"] = ["cross-evaluation only: no GAMS levels for $(p.solver)"]
            end
            rec["n_mismatch"] = rec["status"] == "pass" ? 0 : 1
            push!(checks, rec)
        end
        return
    end
    mine = nothing
    empty!(tm.cache); empty!(tm.data.sets); empty!(tm.data.params)
    GC.gc(true)
    JuMP.set_optimizer(tm.model, HiGHS.Optimizer); JuMP.set_silent(tm.model)
    # local run limit (James, 29 Oct 2026): at most 12 threads per run
    JuMP.set_attribute(tm.model, "threads", parse(Int, get(ENV, "TIMESJL_THREADS", "12")))
    # interior point (then crossover) for large models, as m11_probe.jl; HiGHS's default below
    length(ref.rows) > 100_000 && JuMP.set_attribute(tm.model, "solver", "ipm")
    ts = @elapsed JuMP.optimize!(tm.model)
    # the run pool (reference/python/pool_run.py): after the last solve of the process the run keeps 1 thread
    pool_last && TIMES.pool_phase("reporting")
    ok = JuMP.termination_status(tm.model) == JuMP.OPTIMAL
    obj = ok ? JuMP.objective_value(tm.model) : NaN
    x = ok ? Dict(jump_name_key(JuMP.name(v)) => JuMP.value(v) for v in JuMP.all_variables(tm.model)) : Dict{String,Float64}()
    mine_in_gams = ok ? evaluate_point(ref, x) : nothing
    for p in live
        gobj = p.objective
        rec = Dict{String,Any}("run" => run, "layer" => 3, "unit" => p.solver, "gams_objective" => gobj, "julia_objective" => obj,
                   "julia_solver" => "HiGHS", "solve_seconds" => round(ts; digits=2),
                   "rel_diff" => ok ? abs(obj - gobj) / abs(gobj) : NaN, "n_excluded" => 0, "n_compared" => 1)
        feas = Bool[]
        detail = String[]
        if mine_in_gams !== nothing
            rec["mine_in_gams_violation"] = max(mine_in_gams.max_row_violation, mine_in_gams.max_bound_violation)
            push!(feas, mine_in_gams.feasible && isempty(mine_in_gams.missing_columns))
        end
        if haskey(gpts, p.solver)
            gp = gpts[p.solver]
            rec["gams_in_mine_violation"] = max(gp.g.max_row_violation, gp.g.max_bound_violation)
            rec["gams_point_objective_in_mine"] = gp.g.objective
            rec["gams_in_mine_ok"] = gp.ok
            push!(feas, gp.ok)
            # a GAMS optimum outside its own model's tolerance, violated identically here (known-differences.md K1)
            gp.ok && !gp.g.feasible && push!(detail, own_violation(gp.gref))
        end
        rec["status"] = ok && isapprox(obj, gobj; rtol=1e-6) && all(feas) ? "pass" : "fail"
        rec["n_mismatch"] = rec["status"] == "pass" ? 0 : 1
        ok || push!(detail, "HiGHS: $(JuMP.termination_status(tm.model))")
        rec["detail"] = detail
        push!(checks, rec)
    end
end

function report_fixtures!(out)
    fixtures = TOML.parsefile(joinpath(REPO, "test", "fixtures", "public_fixtures.toml"))["fixture"]
    fxdir = joinpath(REPO, "test", "fixtures")
    for (k, fx) in enumerate(fixtures)
        m = SUITE[fx["model"]]
        run = fx["prefix"]
        sw = Dict{String,String}(k => string(v) for (k, v) in get(fx, "switches", Dict()))
        runrec = Dict{String,Any}("id" => run, "model" => fx["model"], "variant" => get(fx, "variant", ""), "licence" => m["licence"],
                      "redistribute" => m["redistribute"], "source" => "test/fixtures (CI)")
        p(part) = joinpath(fxdir, run * "_" * part)
        isdir(p("presolve")) && isdir(p("matrix")) &&
            layer23_checks!(out["checks"], runrec, run, p("presolve"), joinpath(p("matrix"), "matrix"), joinpath(p("matrix"), "dictmap"),
                            points_from_solution(p("solution.json")), sw, get(fx, "reduce", false); pool_last=k == length(fixtures))
        isdir(p("ppm")) && isdir(p("coef")) && layer1_checks!(out["checks"], run, p("ppm"), p("coef"), sw)
        push!(out["runs"], runrec)
    end
end

function report_reference!(out, refdir, models, roots)
    for (k, model) in enumerate(models), variant in ("reduce_off",)
        dir = joinpath(refdir, model, variant)
        isfile(joinpath(dir, "manifest.json")) || (println("   ", model, ": no reduce_off reference; skipped"); continue)
        man = JSON.parsefile(joinpath(dir, "manifest.json"))
        m = get(SUITE, model, Dict("licence" => "?", "redistribute" => "?"))
        run = "$(model)-$(variant)"
        runrec = Dict{String,Any}("id" => run, "model" => model, "variant" => variant, "licence" => m["licence"],
                      "redistribute" => m["redistribute"], "source" => "reference run (local)",
                      "harness" => get(man, "harness_version", "?"), "reference_created" => get(man, "created_utc", "?"))
        si = get(get(man["runs"], "convert", Dict()), "solveinfo", Dict())
        haskey(si, "numequ") && (runrec["rows"] = Int(si["numequ"]))
        haskey(si, "numvar") && (runrec["cols"] = Int(si["numvar"]))
        println("== ", model); flush(stdout)
        try
            rf = runfile_of(refdir, model, variant)
            sw = rf === nothing ? suite_switches(model, man, roots) : run_switches(rf)
            if isdir(joinpath(dir, "presolve")) && isdir(joinpath(dir, "matrix")) && isdir(joinpath(dir, "matrix_dictmap"))
                try
                    layer23_checks!(out["checks"], runrec, run, joinpath(dir, "presolve"), joinpath(dir, "matrix"),
                                    joinpath(dir, "matrix_dictmap"), points_from_manifest(dir, man), sw, false;
                                    pool_last=k == length(models))
                catch e
                    push!(out["checks"], Dict{String,Any}("run" => run, "layer" => 2, "unit" => "matrix", "status" => "fail",
                          "n_compared" => 0, "n_excluded" => 0, "n_mismatch" => 0, "detail" => ["error: " * first(sprint(showerror, e), 600)]))
                end
                GC.gc(true)
            end
            isdir(joinpath(dir, "ppm")) && isdir(joinpath(dir, "coef")) &&
                layer1_checks!(out["checks"], run, joinpath(dir, "ppm"), joinpath(dir, "coef"), sw)
        catch e
            push!(out["checks"], Dict{String,Any}("run" => run, "layer" => 2, "unit" => "matrix", "status" => "fail",
                  "n_compared" => 0, "n_excluded" => 0, "n_mismatch" => 0, "detail" => ["error: " * first(sprint(showerror, e), 600)]))
        end
        push!(out["runs"], runrec)
        n = count(c -> c["run"] == run, out["checks"]); np = count(c -> c["run"] == run && c["status"] == "pass", out["checks"])
        println("   ", np, " of ", n, " checks pass"); flush(stdout)
    end
end

function main(args)
    isempty(args) && error("usage: parity_report.jl <out.json> [--fixtures | --ref <dir> [--root n=p ...] [models...]]")
    outfile = args[1]
    rest = args[2:end]
    embed_id = nothing
    if "--embed" in rest
        embed_id = "report"
        rest = filter(!=("--embed"), rest)
    end
    if "--no-solve" in rest
        NO_SOLVE[] = true
        rest = filter(!=("--no-solve"), rest)
    end
    i = findfirst(==("--embed-as"), rest)
    if i !== nothing
        i < length(rest) || error("--embed-as needs a block id")
        embed_id = rest[i+1]
        rest = vcat(rest[1:i-1], rest[i+2:end])
    end
    commit = try string(LibGit2.head_oid(LibGit2.GitRepo(REPO)))[1:9] catch; "unknown" end
    out = Dict{String,Any}("meta" => Dict{String,Any}("commit" => commit, "julia" => string(VERSION), "date" => string(Dates.now(Dates.UTC)), "host" => gethostname(),
                              "times_version" => "4.9.7 @ d9a6a25", "threads" => parse(Int, get(ENV, "TIMESJL_THREADS", "12"))),
               "runs" => Any[], "checks" => Any[])
    if isempty(rest) || rest[1] == "--fixtures"
        report_fixtures!(out)
    elseif rest[1] == "--ref"
        refdir, roots, models = parse_probe_args(rest[2:end])
        report_reference!(out, refdir, models, roots)
    else
        error("unknown option $(rest[1])")
    end
    open(outfile, "w") do io
        JSON.print(io, out, 1)
    end
    println("wrote ", outfile, ": ", length(out["runs"]), " runs, ", length(out["checks"]), " checks")
    embed_id === nothing || embed_report!(joinpath(REPO, "docs", "dashboard", "index.html"), out; id=embed_id)
end

"""
    embed_report!(page, report; id="report")

Replace a report embedded in docs/dashboard/index.html (the JSON inside
`<script id="<id>" type="application/json">`), so the page opened from the
repository (file://, no fetch) shows the latest public runs: `report` holds the
public fixtures (CI), `report-suite` the reference runs of the public suite
models. Only reports of models with `redistribute = "public"` are embedded;
other reports (TIM on James's machine) are loaded into the page by its file
button.
"""
function embed_report!(page, report; id="report")
    bad = [r["model"] for r in report["runs"] if get(r, "redistribute", "?") != "public"]
    isempty(bad) || error("not embedding: $(join(unique(bad), ", ")) not redistribute = \"public\" (reference/suite.toml)")
    html = read(page, String)
    open_tag = "<script id=\"$id\" type=\"application/json\">"
    a = findfirst(open_tag, html)
    a === nothing && error("no report block in $page")
    b = findnext("</script>", html, last(a))
    json = replace(sprint(JSON.print, report), "</" => "<\\/")
    write(page, html[1:last(a)] * json * html[first(b):end])
    println("embedded the report in ", page)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
