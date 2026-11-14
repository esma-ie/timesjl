# Copy the dumps a demo12 variant's CI test needs (test/unit/test_variants.jl,
# docs/demo12-variants.md) from one reference run into test/fixtures:
#
#   <prefix>_input/     the state before maindrv.mod (checkpoint input)
#   <prefix>_ppm/       the state after preprocessing (pre-solve run's ppm dump)
#   <prefix>_presolve/  the state the equations are generated from
#
#   julia --project=test scripts/make_variant_fixture.jl <reference>/<model>/<variant> <prefix> [<state>]
#
# <state> (default presolve) names the third dump. A stepped (myopic) run takes equ, the state
# after eqmain.mod (harness 0.3.3): its presolve dump is the state after the loop of solve.stp
# (variant_fixtures.toml: state = "equ").
#
# Only for cases with redistribute = "public" in reference/suite.toml or
# reference/crafted.toml. Manifest source paths are replaced by a short
# description, so fixtures do not record the machine they were made on.

import TOML, JSON

const REPO = dirname(@__DIR__)
function main(refrun, prefix, state="presolve")
    mf = JSON.parsefile(joinpath(refrun, "manifest.json"))
    model = mf["model"]
    cases = Dict(m["name"] => m for f in ("suite.toml", "crafted.toml")
                 for m in TOML.parsefile(joinpath(REPO, "reference", f))["model"])
    get(get(cases, model, Dict()), "redistribute", "?") == "public" ||
        error("$model is not redistribute = \"public\" in reference/suite.toml or crafted.toml: no fixture")
    gams = get(get(mf["runs"], "presolve", Dict()), "gams_version", "?")
    for d in ["input", "ppm", state]
        src = joinpath(refrun, d)
        isdir(src) || error("$src missing: make the reference with harness 0.3.0 or later")
        dst = joinpath(REPO, "test", "fixtures", "$(prefix)_$d")
        isdir(dst) && rm(dst; recursive=true)
        cp(src, dst)
        m = JSON.parsefile(joinpath(dst, "manifest.json"))
        m["source"] = "<$model $(mf["variant"]) pre-solve run, dump $d; $(strip(first(split(gams, "  "))))>"
        write(joinpath(dst, "manifest.json"), JSON.json(m, 1))
        println("wrote ", dst)
    end
end

main(ARGS...)
