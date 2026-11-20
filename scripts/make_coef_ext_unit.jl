# Run coef_ext.vda (TIMES v4.9.7) itself with GAMS on the crafted states of
# test/unit/coef_ext_case.jl, one fixture per case, so the unit test checks
# coef_ext! on the paths no reference run takes (PRC_RCAP, storage
# availabilities, IRE_FLOSUM and RPC_NOFLO balances, UCU units, UC_TIME,
# COEF_ILED). eqlducs.vda and eqashar.vda (with pp_lvlfc.mod) are included
# as in TIMES; COM_CSTBAL is left undeclared so that powerflo.vda CSTBAL is
# not included (`$IF DEFINED`, G35), as in a run without that data.
#
#   julia --project=test scripts/make_coef_ext_unit.jl <TIMES_model dir> [<gams executable>]
#
# Uses scripts/gams_replay.jl; no SOLVE, so the PyPI demo GAMS will do.
# Writes test/fixtures/coefext_unit_gams/<case>/.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "gams_replay.jl"))
include(joinpath(REPO, "test", "unit", "coef_ext_case.jl"))
using OpenTIMES: ctst, varcost

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    outroot = joinpath(REPO, "test", "fixtures", "coefext_unit_gams")
    isdir(outroot) && rm(outroot; recursive=true)
    for name in COEF_EXT_CASES
        tm = coef_ext_start(joinpath(REPO, "test", "fixtures", "demo12_off_ppm"), name)
        work = mktempdir()
        glob = merge(tm.switches, Dict("OBMAC" => "YES", "PGPRIM" => "\"'ACT'\"", "CTST" => ctst(tm), "VARCOST" => varcost(tm)))
        gams_replay(tm, ["coef_ext.vda" => "mod"], COEF_EXT_OUTPUTS; times_dir,
                    also_scan=["eqlducs.vda", "eqashar.vda", "pp_lvlfc.mod"],
                    skip=union(COEF_EXT_DECLARED, Set(["COM_CSTBAL"])), setglobals=glob, workdir=work, kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        write(mf, replace(read(mf, String), joinpath(work, "out.gdx") => "<coef_ext.vda on test/unit/coef_ext_case.jl: $name>"))
        println("wrote ", out)
    end
end

main(ARGS...)
