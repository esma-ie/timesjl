# M1.3 (8b): ppmain.mod L615 (v4.9.7), pp_prelv.vda with pp_lvlfc.mod for
# FLO_FR, the end of the prep -> prelv segment. Layer 1 on TIMES_Demo demo12
# reduce_off from the prep checkpoint through every translated step, compared
# at the prelv checkpoint on every set and parameter (scripts/m13_probe.jl
# does the same on the core reference runs), and on crafted states against
# GAMS running ppmain.mod L1-247 and L249-615, preppm.mod L1-212 and L218-252,
# prep_ext.vda and pp_prelv.vda itself.

using TIMES: TimesModel, DumpData, layer1, ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, prep_ext!, preppm_shape!,
             ppmain_topo!, ppmain_tslvl!, ppmain_life!, pp_prelv!, pp_prelv_symbols, pp_prelv_unported, gset, gparam
using TIMES.Reference: ispass
import TOML

const PRELV_STEPS = (preppm_shape!, ppmain_topo!, ppmain_tslvl!, ppmain_life!, pp_prelv!)

@testset "prep -> prelv segment layer 1 (every symbol), TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prep"); switches=fx["switches"])
    foreach(f -> f(tm), PRELV_STEPS)
    names = pp_prelv_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_prelv")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(names) == 824 && all(ispass, r)
    @test "PUTOUT" in names && "TOP_IRE" in names                 # the QA-log scalars too (M1.3 change 25b-1)
    # L111: without IRE_BND every dummy import from IMPEXP goes
    @test !any(k -> k[1] == "IMPEXP" && k[5] == "IMPNRGZ", gset(tm, "TOP_IRE").keys)
end

include("preppm_case.jl")
include("prep_ext_case.jl")
include("ppmain_topo_case.jl")
include("ppmain_tslvl_case.jl")
include("ppmain_life_case.jl")
include("pp_prelv_case.jl")

@testset "pp_prelv.vda against GAMS on crafted states" begin
    for name in PP_PRELV_CASES
        tm = pp_prelv_start(FIXTURES, name)
        foreach(f -> f(tm), (ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, prep_ext!, PRELV_STEPS...))
        r = layer1(tm, DumpData(joinpath(FIXTURES, "pp_prelv_unit_gams", name)), PP_PRELV_OUTPUTS)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        v(n) = gparam(tm, n).values
        if name == "flofr"
            fr = v("FLO_FR")
            k(y, p, s, b) = ("REG1", y, p, "ELC", s, b)
            # pp_lvlfc.mod L35: an ANNUAL fraction alone copied to the DAYNITE timeslices, then weighted (L103)
            @test fr[k("2010", "ELCTEGAS00", "SD", "LO")] ≈ 0.3 * 0.249714611872146 && !haskey(fr, k("2010", "ELCTEGAS00", "ANNUAL", "LO"))
            # L38-42: S aggregated from SD and SN, W inherited from ANNUAL
            @test fr[k("2015", "ELCTECOA00", "S", "UP")] ≈ 0.2 * 0.249714611872146 + 0.1 * 0.229737442922374
            @test fr[k("2015", "ELCTECOA00", "W", "UP")] ≈ 0.5 * 0.520547945205479
            # L102: the ANNUAL 'N' fraction (TS_CYCLE) is the share of the SEASON timeslices below it; L107 then drops
            #   the RVPCSL of L106 (the option record at ANNUAL), so L109 leaves it
            @test fr[k("2015", "ELCTECOA00", "ANNUAL", "N")] ≈ 0.47945205479452 + 0.520547945205479
            # L117-122: an 'N' option -1 gives LO -INF, EPS gives FX EPS
            @test v("COM_BNDNET")[("REG1", "2010", "DCOT", "ANNUAL", "LO")] == -Inf && v("COM_BNDPRD")[("REG1", "2010", "DCAP", "ANNUAL", "FX")] == 0.0
            # L91, L111 (G45): the region's own import bound keeps its dummy import
            @test ("IMPEXP", "ELC", "REG1", "ELC", "IMPNRGZ") in gset(tm, "TOP_IRE").members
        else
            # L59, L61: FLO_SUM from a group and from a kept shadow commodity
            fs = v("FLO_SUM")
            @test fs[("REG1", "2010", "ELCTEGAS00", "ELC", "ELC", "NRG", "ANNUAL")] == 0.4
            @test fs[("REG1", "2010", "ELCTECOA00", "ELC", "ELC", "ELCCOA", "S")] == 0.7
            # L15-18: Z counts the VDA_FLOP records removed
            @test v("Z")[()] == 6.0
        end
    end
end

@testset "pp_prelv.vda: refused paths" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prep"); switches=merge(fx["switches"], Dict("POWERFLO" => "YES")))
    @test isempty(pp_prelv_unported(tm))                              # phase-angle grids: M1.3 change 27a
    TIMES.gput!(tm, "GR_PTDF", Dict{NTuple{6,String},Float64}(("REG1", "2005", "ELCTECOA00", "ELC", "REG2", "ELC") => 0.5))
    @test any(s -> occursin("GR_PTDF", s), pp_prelv_unported(tm))   # the PTDF formulation stays refused (27a-2)
end

# init_ext.vda L134-135: %POWERFLO% YES comes from the data, not the run file, and a
# dump does not keep it; a model built from a later checkpoint must derive it again
# (m13-plan.md finding of 7 Nov 2026: JRC-EU-TIMES-cli_ll's probe showed FAIL instead
# of the POWERFLO refusal).
@testset "POWERFLO derived from the data (init_ext.vda L134-135)" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prep"); switches=fx["switches"])
    @test TIMES.gswitch(tm, "POWERFLO", "") == ""                    # demo12 has no PRC_REACT, GR_PTDF or GG_KGF
    @test "MY_F" in TIMES.preppm_shape_symbols(tm)
    @test "RXX" in TIMES.ppmain_life_symbols(tm)
    TIMES.gput!(tm, "PRC_REACT", Dict{NTuple{3,String},Float64}(("REG1", "2005", "ELCTECOA00") => 0.1))
    TIMES.data_switches!(tm)
    @test TIMES.gswitch(tm, "POWERFLO", "") == "YES"
    @test isempty(pp_prelv_unported(tm))                              # phase-angle grids are translated (27a)
    @test !("MY_F" in TIMES.preppm_shape_symbols(tm))               # powerflo.vda L80 assigns it again
    @test !("RXX" in TIMES.ppmain_life_symbols(tm))                 # powerflo.vda L121-122
end
