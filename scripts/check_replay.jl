# Validate scripts/gams_replay.jl: replaying the UNMODIFIED state of a public
# fixture through a TIMES coefficient file must reproduce that fixture's own
# coef dump for every symbol the file writes. Run it when gams_replay.jl or a
# replayed file's argument list changes.
#
#   julia --project=test scripts/check_replay.jl <TIMES_model dir> [<gams executable>]
#
# Uses test/fixtures/demo12_off_{ppm,coef} (TIMES_Demo demo12, CC BY 4.0) and
# the switches of its public_fixtures.toml entry.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "gams_replay.jl"))
include(joinpath(REPO, "test", "unit", "coef_obj_case.jl"))
using OpenTIMES: DumpData, layer1, ctst, varcost
using OpenTIMES.Reference: ispass

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    tm = coef_obj_start(joinpath(REPO, "test", "fixtures", "demo12_off_ppm"))
    glob = merge(tm.switches, Dict("OBMAC" => "YES", "DFLBL" => "0", "CTST" => ctst(tm), "VARCOST" => varcost(tm),
                                   "TIMESED" => "0"))
    g = gams_replay(tm, ["coef_obj.mod" => "mod"], COEF_OBJ_OUTPUTS; times_dir, also_scan=["filparam.gms", "fillcost.gms"],
                    skip=COEF_OBJ_DECLARED, setglobals=glob, kw...)
    r = layer1(TimesModel(g), DumpData(joinpath(REPO, "test", "fixtures", "demo12_off_coef")), COEF_OBJ_OUTPUTS)
    foreach(d -> println("  ", d, ispass(d) ? "" : string(" ", d.examples)), r)
    ok = all(ispass, r)
    println(ok ? "PASS" : "FAIL", ": coef_obj.mod replayed on demo12 vs its coef dump (", length(r), " symbols)")
    ok || exit(1)
end

main(ARGS...)
