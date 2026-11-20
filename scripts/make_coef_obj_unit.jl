# Run coef_obj.mod (TIMES v4.9.7) itself with GAMS on the crafted state of
# test/unit/coef_obj_case.jl and store what it computes as a fixture, so the
# unit test checks coef_obj! against GAMS on the paths no reference run takes.
#
#   julia --project=test scripts/make_coef_obj_unit.jl <TIMES_model dir> [<gams executable>]
#
# Uses scripts/gams_replay.jl (needs gamsapi[transfer] and pyarrow for the
# GDX conversion; no SOLVE, so the PyPI demo GAMS will do). The same replay
# of the unmodified demo12 state reproduces that run's coef dump exactly for
# every symbol compared (scripts/check_replay.jl).
# Writes test/fixtures/coefobj_unit_gams/.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "gams_replay.jl"))
include(joinpath(REPO, "test", "unit", "coef_obj_case.jl"))
using OpenTIMES: ctst, varcost

function main(times_dir, gams...)
    tm = coef_obj_start(joinpath(REPO, "test", "fixtures", "demo12_off_ppm"))
    coef_obj_case!(tm)
    glob = merge(tm.switches, Dict("OBMAC" => "YES", "DFLBL" => "0", "CTST" => ctst(tm), "VARCOST" => varcost(tm),
                                   "TIMESED" => "0"))
    work = mktempdir()
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    gams_replay(tm, ["coef_obj.mod" => "mod"], COEF_OBJ_OUTPUTS; times_dir, also_scan=["filparam.gms", "fillcost.gms"],
                skip=COEF_OBJ_DECLARED, setglobals=glob, workdir=work, kw...)
    out = joinpath(REPO, "test", "fixtures", "coefobj_unit_gams")
    isdir(out) && rm(out; recursive=true)
    cp(joinpath(work, "out"), out)
    mf = joinpath(out, "manifest.json")
    write(mf, replace(read(mf, String), joinpath(work, "out.gdx") => "<coef_obj.mod on test/unit/coef_obj_case.jl>"))
    println("wrote ", out, " (GAMS work directory ", work, ")")
end

main(ARGS...)
