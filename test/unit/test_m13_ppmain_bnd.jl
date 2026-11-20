# M1.3 (13a): ppmain.mod L936-1001 (v4.9.7): the commodity subsets and
# COM_LIM defaults, the trade conversions, the bounds aggregated by
# pp_lvlbd.mod and FLO_BND and ACT_BND from FLO_BDLVL. Layer 1 on TIMES_Demo
# demo12 reduce_off from the prelv checkpoint, compared at the ppm
# checkpoint on what these lines settle (scripts/m13_probe.jl does the same
# on the core reference runs), and on a crafted state against GAMS running
# ppmain.mod L616-1001 itself, every symbol written compared at L1001
# (scripts/m13_replay.jl does the same on the core models' own states).

using OpenTIMES: TimesModel, DumpData, layer1, pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_ire!,
             ppmain_bnd!, ppmain_bnd_symbols, gset, gparam, UnportedError
using OpenTIMES.Reference: ispass
import TOML

const PPMAIN_TO_BND = (pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_ire!, ppmain_bnd!)

@testset "prelv -> ppm: ppmain.mod L936-1001 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prelv"); switches=fx["switches"])
    foreach(f -> f(tm), PPMAIN_TO_BND)
    names = ppmain_bnd_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_ppm")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(names) == 17 && all(ispass, r)
    # L962-963: TIMES-MACRO and TIMES-MICRO are refused
    tm2 = TimesModel(joinpath(FIXTURES, "demo12_off_prelv"); switches=merge(Dict{String,String}(k => string(v) for (k, v) in fx["switches"]),
                                                                            Dict("MACRO" => "YES")))
    @test_throws UnportedError ppmain_bnd!(tm2)
end

isdefined(@__MODULE__, :PPMAIN_DFLT_OUTPUTS) || include("ppmain_dflt_case.jl")
isdefined(@__MODULE__, :PPMAIN_TSATTR_NEW) || include("ppmain_tsattr_case.jl")
isdefined(@__MODULE__, :PPMAIN_FLO_NEW) || include("ppmain_flo_case.jl")
isdefined(@__MODULE__, :PPMAIN_FLOFS_NEW) || include("ppmain_flofs_case.jl")
isdefined(@__MODULE__, :PPMAIN_IRE_NEW) || include("ppmain_ire_case.jl")
include("ppmain_bnd_case.jl")
const PPMAIN_BND_ALL = unique(vcat(PPMAIN_DFLT_OUTPUTS, PPMAIN_TSATTR_NEW, PPMAIN_FLO_NEW, PPMAIN_FLOFS_NEW, PPMAIN_IRE_NEW, PPMAIN_BND_NEW))

@testset "ppmain.mod L616-1001 against GAMS on a crafted state" begin
    tm = ppmain_bnd_start(FIXTURES, "bnd")
    foreach(f -> f(tm), PPMAIN_TO_BND)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "ppmain_bnd_unit_gams", "bnd")), PPMAIN_BND_ALL)
    foreach(d -> ispass(d) || println("bnd: ", d, " ", d.examples), r)
    @test length(r) == 126 && all(ispass, r)
    v(n) = gparam(tm, n).values
    g(k...) = get(v(k[1]), k[2:end], nothing)
    yr = Dict(k[2] => x for (k, x) in v("G_YRFR") if k[1] == "REG1")
    p = "ELCTECOA00"
    # pp_lvlbd.mod: UP at SD and SN summed to S, the negative LO below made EPS; FX at WD and WN summed to an FX at W
    @test g("ACT_BND", "REG1", "2010", p, "S", "UP") == 22.0 && g("ACT_BND", "REG1", "2010", p, "S", "LO") == 0.0
    @test g("ACT_BND", "REG1", "2015", p, "W", "FX") == 11.0
    # a value at S and below: the lower one ignored; an UP not covering S: none
    @test g("ACT_BND", "REG1", "2020", p, "S", "UP") == 30.0 && g("ACT_BND", "REG1", "2030", p, "S", "UP") === nothing
    # COA (ANNUAL): COM_BNDNET summed, COM_BNDPRD's negative LO kept (%9 empty), IRE_BND summed
    @test g("COM_BNDNET", "REG1", "2010", "COA", "ANNUAL", "UP") == 150.0 && g("COM_BNDPRD", "REG1", "2010", "COA", "ANNUAL", "LO") == -3.0
    @test g("IRE_BND", "REG1", "2010", "COA", "ANNUAL", "IMPEXP", "IMP", "UP") == 30.0
    # FLO_FR: the negative LO made 0 (%9 0)
    @test g("FLO_FR", "REG1", "2010", p, "ELC", "S", "LO") ≈ 0.1
    # L998-1001: FLO_BND and ACT_BND from FLO_BDLVL (x G_YRFR x 8760); one under a FLO_BND dropped
    @test g("FLO_BND", "REG1", "2010", "ELCTEGAS00", "ELC", "SD", "UP") ≈ 0.5 * yr["SD"] * 8760
    @test g("ACT_BND", "REG1", "2010", "ELCTEGAS00", "SN", "UP") ≈ 0.7 * yr["SN"] * 8760
    @test g("FLO_BDLVL", "REG1", "2015", "ELCTEGAS00", "ELC", "WN", "UP") === nothing
    # L981-984: the reverse conversion; L952: COA a CONSRV energy gets COM_LIM UP
    @test g("IRE_CCVT", "REG2", "ELC", "REG1", "ELC") ≈ 1 / 0.9 && ("REG1", "COA", "UP") in gset(tm, "COM_LIM").members
end
