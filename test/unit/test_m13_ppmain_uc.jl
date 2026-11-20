# M1.3 (15a): ppmain.mod L1101-1179 (v4.9.7) with prepxtra.mod UCINT: the
# user-constraint defaults. Layer 1 on TIMES_Demo demo12 reduce_off from the
# prelv checkpoint, compared at the ppm checkpoint on what these lines settle
# (scripts/m13_probe.jl does the same on the core reference runs), and on a
# crafted state against GAMS running ppmain.mod L616-1179 itself, every
# symbol written compared at L1179 (scripts/m13_replay.jl does the same on
# the core models' own states).

using OpenTIMES: TimesModel, DumpData, layer1, pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_ire!,
             ppmain_bnd!, ppmain_cum!, ppmain_stg!, ppmain_uc!, ppmain_uc_symbols, gset, gparam
using OpenTIMES.Reference: ispass
import TOML

const PPMAIN_TO_UC = (pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_ire!, ppmain_bnd!, ppmain_cum!,
                      ppmain_stg!, ppmain_uc!)

@testset "prelv -> ppm: ppmain.mod L1101-1179 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prelv"); switches=fx["switches"])
    foreach(f -> f(tm), PPMAIN_TO_UC)
    names = ppmain_uc_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_ppm")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(names) == 15 && all(ispass, r)
end

isdefined(@__MODULE__, :PPMAIN_DFLT_OUTPUTS) || include("ppmain_dflt_case.jl")
isdefined(@__MODULE__, :PPMAIN_TSATTR_NEW) || include("ppmain_tsattr_case.jl")
isdefined(@__MODULE__, :PPMAIN_FLO_NEW) || include("ppmain_flo_case.jl")
isdefined(@__MODULE__, :PPMAIN_FLOFS_NEW) || include("ppmain_flofs_case.jl")
isdefined(@__MODULE__, :PPMAIN_IRE_NEW) || include("ppmain_ire_case.jl")
isdefined(@__MODULE__, :PPMAIN_BND_NEW) || include("ppmain_bnd_case.jl")
isdefined(@__MODULE__, :PPMAIN_CUM_NEW) || include("ppmain_cum_case.jl")
isdefined(@__MODULE__, :PPMAIN_STG_NEW) || include("ppmain_stg_case.jl")
include("ppmain_uc_case.jl")
const PPMAIN_UC_ALL = unique(vcat(PPMAIN_DFLT_OUTPUTS, PPMAIN_TSATTR_NEW, PPMAIN_FLO_NEW, PPMAIN_FLOFS_NEW, PPMAIN_IRE_NEW, PPMAIN_BND_NEW,
                                  PPMAIN_CUM_NEW, PPMAIN_STG_NEW, PPMAIN_UC_NEW))

@testset "ppmain.mod L616-1179 against GAMS on a crafted state" begin
    tm = ppmain_uc_start(FIXTURES, "uc")
    foreach(f -> f(tm), PPMAIN_TO_UC)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "ppmain_uc_unit_gams", "uc")), PPMAIN_UC_ALL)
    foreach(d -> ispass(d) || println("uc: ", d, " ", d.examples), r)
    @test length(r) == 172 && all(ispass, r)
    has(n, k...) = k in gset(tm, n).members
    # prepxtra.mod L64-68: UC_T_SUM by %DFLBL% filled in between 2010 and 2030
    @test has("UC_T_SUM", "REG1", "UC_X1", "2015") && has("UC_T_SUM", "REG1", "UC_X1", "2020")
    # L1110-1114: the ANNUAL RHS levelled to SEASON, kept only on UC_TS_EACH (S, not W)
    @test haskey(gparam(tm, "UC_RHSRTS").values, ("REG1", "UC_RNW-PP_LOW", "2020", "S", "LO")) &&
          !haskey(gparam(tm, "UC_RHSRTS").values, ("REG1", "UC_RNW-PP_LOW", "2020", "W", "LO"))
    # L1116-1132: the obsolete UC_RHSS makes UC_X2 a UC_R_SUM in both regions
    @test has("UC_R_SUM", "REG1", "UC_X2") && has("UC_R_SUM", "REG2", "UC_X2")
    # L1170-1174: the RHS PERIOD attribute makes UC_X2 dynamic, its milestones moved to UC_T_SUCC
    @test has("UC_T_SUCC", "REG1", "UC_X2", "2010") && !has("UC_T_EACH", "REG1", "UC_X2", "2010")
end
