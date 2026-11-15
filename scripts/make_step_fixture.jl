# Copy what the CI test of a stepped (myopic) run needs from the per-step dumps of one reference
# run (harness 0.3.4: steps/<k>/final, every symbol just after the SOLVE of step k) into
# test/fixtures (test/unit/test_solve_stp.jl, docs/m15-plan.md):
#
#   <prefix>_step<k>/   of steps/<k>/final: the sets and parameters that differ from the equ dump
#                       (the state after eqmain.mod, already a fixture: <prefix>_equ), and the
#                       variables whose levels or marginals solve.stp reads (STP_POINT_VARS).
#                       Its manifest also holds, under "tjl_step_solve", what GAMS/CPLEX's SOLVE of
#                       the step returned (the reference manifest's runs.solve_cplex.steps[k]:
#                       objective, sizes, statuses) and, for the last step, the final objective of
#                       every GAMS solver of the reference ("final_objective"), for layer 3
#   <prefix>_step<k>_matrix/matrix, /dictmap
#                       the LP GAMS solved in step k (steps/<k>/matrix: the CONVERT DumpGDX export
#                       made just before that SOLVE) and its dictionary (steps/<k>/matrix_dictmap),
#                       for layer 2 of the step (test/unit/test_bnd_stp.jl)
#
#   julia --project=test scripts/make_step_fixture.jl <reference>/<model>/<variant> <prefix>
#
# A step's dump is about 3 MB and nearly all of it is the equ dump again, so the fixture keeps the
# difference. Its manifest lists, under "tjl_same_as_equ", the sets and parameters of the step's
# dump that are the same in the equ dump, record for record (rtol 0): the test compares those
# against <prefix>_equ, and so still covers every set and parameter of the step.
#
# Only for cases with redistribute = "public" in reference/suite.toml or reference/crafted.toml.
# The manifest's source is a short description, so fixtures do not record the machine they were
# made on.

import TOML, JSON
using TIMES: STP_POINT_VARS
using TIMES.Reference: load_dump, compare_dumps, ispass

const REPO = dirname(@__DIR__)
function main(refrun, prefix)
    mf = JSON.parsefile(joinpath(refrun, "manifest.json"))
    model = mf["model"]
    cases = Dict(m["name"] => m for f in ("suite.toml", "crafted.toml")
                 for m in TOML.parsefile(joinpath(REPO, "reference", f))["model"])
    get(get(cases, model, Dict()), "redistribute", "?") == "public" ||
        error("$model is not redistribute = \"public\" in reference/suite.toml or crafted.toml: no fixture")
    gams = get(get(mf["runs"], "presolve", Dict()), "gams_version", "?")
    equdir = joinpath(refrun, "equ")
    isdir(equdir) || error("$equdir missing: make the reference with harness 0.3.3 or later")
    equ = load_dump(equdir)
    steps = sort!([parse(Int, s) for s in readdir(joinpath(refrun, "steps")) if isdir(joinpath(refrun, "steps", s, "final"))])
    isempty(steps) && error("$refrun has no steps/<k>/final: not a stepped reference (harness 0.3.4)")
    for k in steps
        src = joinpath(refrun, "steps", string(k), "final")
        step = load_dump(src)
        cmp = compare_dumps(equ, step; rtol=0.0, atol=0.0)
        same = Set(uppercase(s.name) for s in cmp.symbols if ispass(s))
        m = JSON.parsefile(joinpath(src, "manifest.json"))
        keep, unchanged = Any[], String[]
        for e in m["symbols"]
            n = uppercase(e["name"])
            if e["kind"] == "variable"
                e["name"] in STP_POINT_VARS && push!(keep, e)
            elseif e["kind"] in ("set", "parameter")
                n in same ? push!(unchanged, e["name"]) : push!(keep, e)
            end
        end
        dst = joinpath(REPO, "test", "fixtures", "$(prefix)_step$k")
        isdir(dst) && rm(dst; recursive=true)
        mkpath(dst)
        for e in keep
            f = get(e, "file", nothing)
            (f !== nothing && isfile(joinpath(src, f))) && cp(joinpath(src, f), joinpath(dst, f))
        end
        u = get(m, "uels", nothing)
        (u !== nothing && isfile(joinpath(src, u))) && cp(joinpath(src, u), joinpath(dst, u))
        m["symbols"] = keep
        m["tjl_same_as_equ"] = sort!(unchanged)
        gs = [s for s in get(get(mf["runs"], "solve_cplex", Dict()), "steps", Any[]) if s["step"] == k]
        length(gs) == 1 || error("$refrun: no record of step $k in runs.solve_cplex.steps of the manifest")
        solve = Dict{String,Any}(gs[1])
        solve["solver"] = "CPLEX"
        if k == last(steps)
            solve["final_objective"] = Dict(uppercase(tag[7:end]) => run["solveinfo"]["objval"] for (tag, run) in mf["runs"]
                                            if startswith(tag, "solve_") && get(get(run, "solveinfo", Dict()), "modelstat", 0) == 1)
        end
        m["tjl_step_solve"] = solve
        m["source"] = "<$model $(mf["variant"]) solve run, after the SOLVE of step $k: what differs from the equ dump, " *
                      "and the variables solve.stp reads; $(strip(first(split(gams, "  "))))>"
        write(joinpath(dst, "manifest.json"), JSON.json(m, 1))
        println("wrote ", dst, ": ", length(keep), " symbols kept, ", length(unchanged), " as in the equ dump")
        mdst = joinpath(REPO, "test", "fixtures", "$(prefix)_step$(k)_matrix")
        isdir(mdst) && rm(mdst; recursive=true)
        for (from, to, what) in (("matrix", "matrix", "the LP"), ("matrix_dictmap", "dictmap", "the dictionary of the LP"))
            msrc = joinpath(refrun, "steps", string(k), from)
            isdir(msrc) || error("$msrc missing: make the reference with harness 0.3.4 or later")
            mkpath(joinpath(mdst, to))
            for f in readdir(msrc)
                cp(joinpath(msrc, f), joinpath(mdst, to, f))
            end
            mm = JSON.parsefile(joinpath(mdst, to, "manifest.json"))
            mm["source"] = "<$model $(mf["variant"]) solve run, $what of step $k (CONVERT); $(strip(first(split(gams, "  "))))>"
            write(joinpath(mdst, to, "manifest.json"), JSON.json(mm, 1))
        end
        println("wrote ", mdst)
    end
end

main(ARGS...)
