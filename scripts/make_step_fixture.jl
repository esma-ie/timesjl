# Copy what the CI test of a stepped (myopic) run needs from the per-step dumps of one reference
# run (harness 0.3.4: steps/<k>/final, every symbol just after the SOLVE of step k) into
# test/fixtures (test/unit/test_solve_stp.jl, docs/m15-plan.md):
#
#   <prefix>_step<k>/   of steps/<k>/final: the sets and parameters that differ from the equ dump
#                       (the state after eqmain.mod, already a fixture: <prefix>_equ), and the
#                       variables whose levels or marginals solve.stp reads (STP_POINT_VARS)
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
        m["source"] = "<$model $(mf["variant"]) solve run, after the SOLVE of step $k: what differs from the equ dump, " *
                      "and the variables solve.stp reads; $(strip(first(split(gams, "  "))))>"
        write(joinpath(dst, "manifest.json"), JSON.json(m, 1))
        println("wrote ", dst, ": ", length(keep), " symbols kept, ", length(unchanged), " as in the equ dump")
    end
end

main(ARGS...)
