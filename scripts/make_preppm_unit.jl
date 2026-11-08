# Run ppmain.mod L1-247 and preppm.mod L1-212 (TIMES v4.9.7) themselves with
# GAMS on the crafted states of test/unit/preppm_case.jl, one fixture per
# case, so the unit test checks preppm! on the interpolation paths no core
# reference run takes (options, exponential growth, write caches, the
# special-case merges, retirements and refits, G_NOINTERP).
#
#   julia --project=test scripts/make_preppm_unit.jl <TIMES_model dir> [<gams executable>]
#
# The lines are copied unchanged from <TIMES_model dir>/ppmain.mod (L1-247)
# and preppm.mod (L1-212, which ppmain.mod L248 includes) into one work file
# and $BATINCLUDEd with `mod` (scripts/gams_replay.jl); their includes
# (filparam.gms, timslice.mod, pp_off.mod, pp_qaput.mod, curex.gms,
# prepret.dsc, fillvint.gms, prepparm.gms, fillparm.gms) come from
# <TIMES_model dir>. %PRF% (curex.gms L71) is FILE=1 (initmty.mod L417);
# %MX% (curex.gms L81 without a year index) is empty (setglobs.gms L356, L374).
# %DATAGDX% is NO (prepxtra.mod SAVE only renames a file) and %RETIRE% YES
# (initmty.mod L454). No SOLVE, so the PyPI demo GAMS will do (on Windows set
# TJL_PYTHON to the harness venv's python.exe). Writes
# test/fixtures/preppm_unit_gams/<case>/.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "gams_replay.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_head_case.jl"))     # PPMAIN_HEAD_DECLARED
include(joinpath(REPO, "test", "unit", "timslice_case.jl"))        # TIMSLICE_DECLARED
include(joinpath(REPO, "test", "unit", "preppm_case.jl"))

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    fixtures = joinpath(REPO, "test", "fixtures")
    outroot = joinpath(fixtures, "preppm_unit_gams")
    isdir(outroot) && rm(outroot; recursive=true)
    pre = readlines(joinpath(times_dir, "preppm.mod"))[1:212]
    # what preppm.mod declares itself: L47-48 and the write caches of fillparm/prepparm
    declared = union(["OBJ_VFLO", "RPC_CUR", "RP_RTF"], [m.match for l in pre for m in eachmatch(r"\bX_[A-Z]+\b", l)])
    for name in PREPPM_CASES
        tm = preppm_start(fixtures, name)
        work = mktempdir()
        head = joinpath(work, "preppm_head.mod")                     # ppmain.mod L1-247 and preppm.mod L1-212, unchanged
        write(head, join(vcat(first(readlines(joinpath(times_dir, "ppmain.mod")), 247), pre), "\n") * "\n")
        # %OBMAC% is YES on any GAMS from 23.0 (initmty.mod L21); %RL% as setglobs.gms L317 sets it without G2X6 (L230)
        glob = merge(tm.switches, Dict("DFLBL" => "'0'", "PGPRIM" => "\"'ACT'\"", "DATAGDX" => "NO", "G2X6" => "NO", "OBMAC" => "YES",
                                       "RL" => "'R.TL:MAX(12,CARD(R.TL))'", "RETIRE" => "'YES'",
                                       "PRF" => "FILE=1", "MX" => "''"))
        gams_replay(tm, [head => "mod"], preppm_outputs(name); times_dir,
                    also_scan=["filparam.gms", "timslice.mod", "pp_off.mod", "pp_qaput.mod", "prepret.dsc", "fillvint.gms", "prepparm.gms",
                               "fillparm.gms", "curex.gms"],
                    skip=union(PPMAIN_HEAD_DECLARED, ["MINYR"], TIMSLICE_DECLARED, declared), setglobals=glob, workdir=work, onmulti=true,
                    bare=Set(PREPPM_BARE), kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        gdx, label = joinpath(work, "out.gdx"), "<ppmain.mod L1-247, preppm.mod L1-212 on test/unit/preppm_case.jl: $name>"
        # JSON doubles the backslashes of a Windows path
        write(mf, replace(read(mf, String), gdx => label, replace(gdx, "\\" => "\\\\") => label))
        println("wrote ", out)
    end
end

main(ARGS...)
