# Run coef_alt.lin (TIMES v4.9.7) itself with GAMS on the crafted states of
# test/unit/coef_alt_case.jl, one fixture per case, so the unit test checks
# coef_alt! on the switch paths no reference run takes (OBJ ALT, OBJ LIN,
# OBLONG with ALT, INT_DEFAULT PASTI).
#
#   julia --project=test scripts/make_coef_alt_unit.jl <TIMES_model dir> [<gams executable>]
#
# TJL_CASES=plain,alt (environment) remakes only those cases and keeps the others.
#
# Uses scripts/gams_replay.jl; no SOLVE, so the PyPI demo GAMS will do.
# Writes test/fixtures/coefalt_unit_gams/<case>/.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "gams_replay.jl"))
include(joinpath(REPO, "test", "unit", "coef_alt_case.jl"))
using OpenTIMES: ctst, varcost

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    outroot = joinpath(REPO, "test", "fixtures", "coefalt_unit_gams")
    only = filter(!isempty, split(get(ENV, "TJL_CASES", ""), ','))
    isempty(only) && isdir(outroot) && rm(outroot; recursive=true)
    for (name, _) in COEF_ALT_CASES
        isempty(only) || name in only || continue
        tm = coef_alt_start(joinpath(REPO, "test", "fixtures", "demo12_off_ppm"), name)
        c = ctst(tm)
        glob = merge(tm.switches, Dict("OBMAC" => "YES", "DFLBL" => "0", "CTST" => c, "VARCOST" => varcost(tm), "TIMESED" => "0"))
        work = mktempdir()
        gams_replay(tm, ["coef_alt.lin" => "VAR" * c], COEF_ALT_OUTPUTS; times_dir, skip=COEF_ALT_DECLARED,
                    setglobals=glob, workdir=work, kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        isdir(out) && rm(out; recursive=true)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        write(mf, replace(read(mf, String), joinpath(work, "out.gdx") => "<coef_alt.lin VAR$c on test/unit/coef_alt_case.jl: $name>"))
        println("wrote ", out)
    end
end

main(ARGS...)
