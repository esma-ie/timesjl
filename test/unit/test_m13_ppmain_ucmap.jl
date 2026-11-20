# M1.3 (15b): ppmain.mod L1181-1226 (v4.9.7) with pp_lvlus.mod: the UC
# group maps and UC attributes levelled. Layer 1 on TIMES_Demo demo12 reduce_off from the
# prelv checkpoint, compared at the ppm checkpoint on what these lines settle
# (scripts/m13_probe.jl does the same on the core reference runs), and on a
# crafted state against GAMS running ppmain.mod L616-1226 itself, every
# symbol written compared at L1226 (scripts/m13_replay.jl does the same on
# the core models' own states).

using OpenTIMES: TimesModel, DumpData, layer1, pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_ire!,
             ppmain_bnd!, ppmain_cum!, ppmain_stg!, ppmain_uc!, ppmain_ucmap!, ppmain_ucmap_symbols, gset, gparam
using OpenTIMES.Reference: ispass
import TOML

const PPMAIN_TO_UCMAP = (pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_ire!, ppmain_bnd!, ppmain_cum!,
                      ppmain_stg!, ppmain_uc!, ppmain_ucmap!)

@testset "prelv -> ppm: ppmain.mod L1181-1226 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prelv"); switches=fx["switches"])
    foreach(f -> f(tm), PPMAIN_TO_UCMAP)
    names = ppmain_ucmap_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_ppm")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(names) == 17 && all(ispass, r)
end

isdefined(@__MODULE__, :PPMAIN_DFLT_OUTPUTS) || include("ppmain_dflt_case.jl")
isdefined(@__MODULE__, :PPMAIN_TSATTR_NEW) || include("ppmain_tsattr_case.jl")
isdefined(@__MODULE__, :PPMAIN_FLO_NEW) || include("ppmain_flo_case.jl")
isdefined(@__MODULE__, :PPMAIN_FLOFS_NEW) || include("ppmain_flofs_case.jl")
isdefined(@__MODULE__, :PPMAIN_IRE_NEW) || include("ppmain_ire_case.jl")
isdefined(@__MODULE__, :PPMAIN_BND_NEW) || include("ppmain_bnd_case.jl")
isdefined(@__MODULE__, :PPMAIN_CUM_NEW) || include("ppmain_cum_case.jl")
isdefined(@__MODULE__, :PPMAIN_STG_NEW) || include("ppmain_stg_case.jl")
isdefined(@__MODULE__, :PPMAIN_UC_NEW) || include("ppmain_uc_case.jl")
include("ppmain_ucmap_case.jl")
const PPMAIN_UCMAP_ALL = unique(vcat(PPMAIN_DFLT_OUTPUTS, PPMAIN_TSATTR_NEW, PPMAIN_FLO_NEW, PPMAIN_FLOFS_NEW, PPMAIN_IRE_NEW, PPMAIN_BND_NEW,
                                     PPMAIN_CUM_NEW, PPMAIN_STG_NEW, PPMAIN_UC_NEW, PPMAIN_UCMAP_NEW))

@testset "ppmain.mod L616-1226 against GAMS on a crafted state" begin
    tm = ppmain_ucmap_start(FIXTURES, "ucmap")
    foreach(f -> f(tm), PPMAIN_TO_UCMAP)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "ppmain_ucmap_unit_gams", "ucmap")), PPMAIN_UCMAP_ALL)
    foreach(d -> ispass(d) || println("ucmap: ", d, " ", d.examples), r)
    @test length(r) == 185 && all(ispass, r)
    act = gparam(tm, "UC_ACT").values
    has(n, k...) = k in gset(tm, n).members
    # pp_lvlus.mod L24-30: a SEASON process's UC_ACT given at DAYNITE aggregated to its seasons
    @test haskey(act, ("UC_X3", "LHS", "REG1", "2010", "ELCTECOA00", "S")) && haskey(act, ("UC_X3", "LHS", "REG1", "2010", "ELCTECOA00", "W"))
    # L31-36: a DAYNITE process's UC_ACT given at S inherited by S's day-nights only
    @test act[("UC_X3", "LHS", "REG1", "2010", "ELCTEGAS00", "SD")] == 3.0 && !haskey(act, ("UC_X3", "LHS", "REG1", "2010", "ELCTEGAS00", "WD"))
    # ppmain.mod L1188, L1192: UC_FLO of a trade process and UC_IRE of a non-trade process flagged
    @test has("UC_QAFLO", "1", "UC_X3", "LHS", "REG1", "IMPELC1", "ELC") && has("UC_QAFLO", "2", "UC_X3", "LHS", "REG1", "ELCTECOA00", "ELC")
    # L1195: the COMCON group's dynamic attribute passed on to COMNET
    @test has("UC_ATTR", "REG1", "UC_X3", "LHS", "COMNET", "N")
    # L1207-1209: UC_X4 on by UC_DYNBND, its UC_COM PRD puts VAR_COMPRD on ELC in REG2
    @test has("UC_ON", "REG2", "UC_X4") && has("RHS_COMPRD", "REG2", "2010", "ELC", "SD")
end
