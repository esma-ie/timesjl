# M1.3 (14): ppmain.mod L1058-1099 (v4.9.7): the storage processes. Layer 1
# on TIMES_Demo demo12 reduce_off from the prelv checkpoint, compared at the
# ppm checkpoint on what these lines settle (scripts/m13_probe.jl does the
# same on the core reference runs), and on a crafted state against GAMS
# running ppmain.mod L616-1099 itself, every symbol written compared at
# L1099 (scripts/m13_replay.jl does the same on the core models' own states).

using OpenTIMES: TimesModel, DumpData, layer1, pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_ire!,
             ppmain_bnd!, ppmain_cum!, ppmain_stg!, ppmain_stg_symbols, gset, gparam
using OpenTIMES.Reference: ispass
import TOML

const PPMAIN_TO_STG = (pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_ire!, ppmain_bnd!, ppmain_cum!,
                       ppmain_stg!)

@testset "prelv -> ppm: ppmain.mod L1058-1099 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prelv"); switches=fx["switches"])
    foreach(f -> f(tm), PPMAIN_TO_STG)
    names = ppmain_stg_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_ppm")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(names) == 13 && all(ispass, r)
end

isdefined(@__MODULE__, :PPMAIN_DFLT_OUTPUTS) || include("ppmain_dflt_case.jl")
isdefined(@__MODULE__, :PPMAIN_TSATTR_NEW) || include("ppmain_tsattr_case.jl")
isdefined(@__MODULE__, :PPMAIN_FLO_NEW) || include("ppmain_flo_case.jl")
isdefined(@__MODULE__, :PPMAIN_FLOFS_NEW) || include("ppmain_flofs_case.jl")
isdefined(@__MODULE__, :PPMAIN_IRE_NEW) || include("ppmain_ire_case.jl")
isdefined(@__MODULE__, :PPMAIN_BND_NEW) || include("ppmain_bnd_case.jl")
isdefined(@__MODULE__, :PPMAIN_CUM_NEW) || include("ppmain_cum_case.jl")
include("ppmain_stg_case.jl")
const PPMAIN_STG_ALL = unique(vcat(PPMAIN_DFLT_OUTPUTS, PPMAIN_TSATTR_NEW, PPMAIN_FLO_NEW, PPMAIN_FLOFS_NEW, PPMAIN_IRE_NEW, PPMAIN_BND_NEW,
                                   PPMAIN_CUM_NEW, PPMAIN_STG_NEW))

@testset "ppmain.mod L616-1099 against GAMS on a crafted state" begin
    tm = ppmain_stg_start(FIXTURES, "stg")
    foreach(f -> f(tm), PPMAIN_TO_STG)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "ppmain_stg_unit_gams", "stg")), PPMAIN_STG_ALL)
    foreach(d -> ispass(d) || println("stg: ", d, " ", d.examples), r)
    @test length(r) == 151 && all(ispass, r)
    p = "ELCTNOIL01"
    v(n) = gparam(tm, n).values
    has(n, k...) = k in gset(tm, n).members
    # L1084-1086: the flexible stockpile gets PRC_TS above its DAYNITE level, ANNUAL too; L1089: RP_STL up to PRC_SGL
    @test has("PRC_TS", "REG1", p, "ANNUAL") && has("PRC_TS", "REG1", p, "S") && has("RP_STL", "REG1", p, "WEEKLY", "N")
    # L1097: the equilibrium loss at ANNUAL becomes 1-EXP(-1.5)
    @test v("STG_LOSS")[("REG1", "2010", p, "ANNUAL")] ≈ 1 - exp(-1.5)
    # L1090: NCAP_AF from NCAP_AFS outside RPS_STG
    @test v("NCAP_AF")[("REG1", "2010", p, "ANNUAL", "UP")] == 0.8
end
