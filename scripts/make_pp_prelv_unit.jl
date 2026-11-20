# Run ppmain.mod L1-247, preppm.mod L1-212, prep_ext.vda, preppm.mod L218-252,
# ppmain.mod L249-614 and pp_prelv.vda (TIMES v4.9.7) themselves with GAMS on
# the crafted states of test/unit/pp_prelv_case.jl, one fixture per case, so
# the unit test checks pp_prelv! on the paths no core reference run takes
# (FLO_FR levelling, NCAP_CHPR and COM_BNDNET/COM_BNDPRD 'N', IRE_BND, the
# shares of storage, %SHELL% ANSWER, VDA_FLOP groups).
#
#   julia --project=test scripts/make_pp_prelv_unit.jl <TIMES_model dir> [<gams executable>]
#
# The work files are those of make_ppmain_life_unit.jl, with ppmain.mod
# L249-614 in place of L249-611 and then `$BATINCLUDE pp_prelv.vda VDA`, as
# main_ext.mod includes it for the VDA extension at ppmain.mod L615; the rest
# copied unchanged and $BATINCLUDEd with `mod` (scripts/gams_replay.jl). %CTST% and %OBLONG% as initmty.mod L426-430
# set them from the case's switches (`ctst`; OBJ MOD sets OBLONG), %VALIDATE%
# from the switches (NO unless set).
# %DATAGDX% is NO and %RETIRE% YES as in make_preppm_unit.jl. No SOLVE, so the
# PyPI demo GAMS will do (on Windows set TJL_PYTHON to the harness venv's
# python.exe). Writes test/fixtures/pp_prelv_unit_gams/<case>/.

const REPO = dirname(@__DIR__)
include(joinpath(@__DIR__, "gams_replay.jl"))
include(joinpath(REPO, "test", "unit", "ppmain_head_case.jl"))     # PPMAIN_HEAD_DECLARED
include(joinpath(REPO, "test", "unit", "timslice_case.jl"))        # TIMSLICE_DECLARED
include(joinpath(REPO, "test", "unit", "preppm_case.jl"))          # PREPPM_BARE, PREPPM_OUTPUTS
include(joinpath(REPO, "test", "unit", "prep_ext_case.jl"))        # PREP_EXT_BARE, PREP_EXT_OUTPUTS
include(joinpath(REPO, "test", "unit", "ppmain_topo_case.jl"))     # PPMAIN_TOPO_OUTPUTS
include(joinpath(REPO, "test", "unit", "ppmain_tslvl_case.jl"))    # PPMAIN_TSLVL_OUTPUTS
include(joinpath(REPO, "test", "unit", "ppmain_life_case.jl"))     # PPMAIN_LIFE_OUTPUTS
include(joinpath(REPO, "test", "unit", "pp_prelv_case.jl"))
using OpenTIMES: ctst

function main(times_dir, gams...)
    kw = isempty(gams) ? (;) : (; gams=gams[1])
    fixtures = joinpath(REPO, "test", "fixtures")
    outroot = joinpath(fixtures, "pp_prelv_unit_gams")
    isdir(outroot) && rm(outroot; recursive=true)
    ppm = readlines(joinpath(times_dir, "ppmain.mod"))
    pre = readlines(joinpath(times_dir, "preppm.mod"))
    vda = readlines(joinpath(times_dir, "prep_ext.vda"))
    # what preppm.mod declares itself: L47-48 and the write caches of fillparm/prepparm (prep_ext.vda's too); SUBT (ppmain.mod L253)
    declared = union(["OBJ_VFLO", "RPC_CUR", "RP_RTF", "SUBT"], [m.match for l in vcat(pre, vda) for m in eachmatch(r"\bX_[A-Z]+\b", l)])
    for name in PP_PRELV_CASES
        tm = pp_prelv_start(fixtures, name)
        work = mktempdir()
        head = joinpath(work, "prelv_head.mod")                       # ppmain.mod L1-247, preppm.mod L1-212, unchanged; then prep_ext.vda
        write(head, join(vcat(ppm[1:247], pre[1:212], ["\$BATINCLUDE prep_ext.vda mod"]), "\n") * "\n")
        shape = joinpath(work, "prelv_shape.mod")                     # preppm.mod L218-252, unchanged (L245 $EXITs it)
        write(shape, join(pre[218:end], "\n") * "\n")
        main_ = joinpath(work, "prelv_main.mod")                     # ppmain.mod L249-614, unchanged; then pp_prelv.vda (L615)
        write(main_, join(vcat(ppm[249:614], ["\$BATINCLUDE pp_prelv.vda VDA"]), "\n") * "\n")
        # %OBMAC% is YES on any GAMS from 23.0 (initmty.mod L21); %RL%, %PL%, %CL% as setglobs.gms L317 sets them without G2X6 (L230)
        glob = merge(tm.switches, Dict("DFLBL" => "'0'", "PGPRIM" => "\"'ACT'\"", "DATAGDX" => "NO", "G2X6" => "NO", "OBMAC" => "YES",
                                       "RL" => "'R.TL:MAX(12,CARD(R.TL))'", "PL" => "'P.TL:MAX(12,CARD(P.TL))'",
                                       "CL" => "C.TL:MAX(12,CARD(C.TL))", "RETIRE" => "'YES'", "CTST" => ctst(tm),
                                       "VALIDATE" => get(tm.switches, "VALIDATE", "NO"),
                                       "OBLONG" => uppercase(get(tm.switches, "OBJ", "")) == "MOD" ? "YES" : get(tm.switches, "OBLONG", "NO")))
        gams_replay(tm, [head => "mod", shape => "mod", main_ => "mod"], PP_PRELV_OUTPUTS; times_dir,
                    also_scan=["filparam.gms", "timslice.mod", "pp_off.mod", "pp_qaput.mod", "prepret.dsc", "fillvint.gms", "prepparm.gms",
                               "fillparm.gms", "prep_ext.vda", "equcrtp.vda", "preshape.gms", "pp_prelv.vda", "pp_lvlfc.mod",
                               "dynslite.vda"],
                    skip=union(PPMAIN_HEAD_DECLARED, ["MINYR"], TIMSLICE_DECLARED, declared), setglobals=glob, workdir=work, onmulti=true,
                    bare=Set(PREP_EXT_BARE), kw...)
        out = joinpath(outroot, name)
        mkpath(outroot)
        cp(joinpath(work, "out"), out)
        mf = joinpath(out, "manifest.json")
        gdx, label = joinpath(work, "out.gdx"), "<ppmain.mod L1-247 and L249-615, preppm.mod L1-212 and L218-252, prep_ext.vda, pp_prelv.vda on test/unit/pp_prelv_case.jl: $name>"
        # JSON doubles the backslashes of a Windows path
        write(mf, replace(read(mf, String), gdx => label, replace(gdx, "\\" => "\\\\") => label))
        println("wrote ", out)
    end
end

main(ARGS...)
