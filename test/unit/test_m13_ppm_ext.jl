# M1.3 (18a): maindrv.mod L58, ppm_ext.dsc and ppm_ext.vda L11-58 with
# pp_actef.vda LVL (v4.9.7): the ACT_EFF preparation. Layer 1 on TIMES_Demo
# demo12 reduce_off from the prelv checkpoint, compared at the ppm checkpoint
# on what these lines settle (scripts/m13_probe.jl does the same on the core
# reference runs, reduce_off and as_run), and on two crafted states against
# GAMS running ppmain.mod L616-1357 and ppm_ext.vda L11-58 itself, every
# symbol written compared at ppm_ext.vda L58 (scripts/m13_replay.jl does the
# same on the core models' own states).

using OpenTIMES: TimesModel, DumpData, layer1, ppm_ext_actef!, ppm_ext_actef_symbols, PPM_EXT_ACTEF_OUTPUTS, gset, gparam
using OpenTIMES.Reference: ispass
import TOML

isdefined(@__MODULE__, :PPMAIN_TO_REDUCE) || include("test_m13_ppmain_reduce.jl")
const PPMAIN_TO_PPM_EXT = (PPMAIN_TO_REDUCE..., ppm_ext_actef!)

@testset "prelv -> ppm: ppm_ext.vda L11-58 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prelv"); switches=fx["switches"])
    foreach(f -> f(tm), PPMAIN_TO_PPM_EXT)
    names = ppm_ext_actef_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_ppm")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(names) == 20 && all(ispass, r)
end

include("ppm_ext_case.jl")
const PPM_EXT_ACTEF_ALL = unique(vcat(PPMAIN_REDUCE_ALL, PPM_EXT_ACTEF_OUTPUTS))

@testset "ppmain.mod L616-1357, ppm_ext.vda L11-58 against GAMS on crafted states" begin
    for c in PPM_EXT_CASES
        tm = ppm_ext_start(FIXTURES, c)
        foreach(f -> f(tm), PPMAIN_TO_PPM_EXT)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "ppm_ext_unit_gams", c)), PPM_EXT_ACTEF_ALL)
        foreach(d -> ispass(d) || println(c, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        has(n, k...) = k in gset(tm, n).members
        ae(k...) = get(gparam(tm, "ACT_EFF").values, k, nothing)
        if c == "ace"
            # ppm_ext.vda L41-47: ACT_EFF on the primary-group commodity AGRELC marks FTE-AGRELC's NRG group
            @test has("RPG_PACE", "REG1", "FTE-AGRELC", "NRG")
            # L50, pp_actef.vda L37-45: SD and SN levelled up to S (by year fraction), W inherits ANNUAL, ANNUAL dropped
            @test ae("REG1", "2020", "ELCTECOA00", "NRG", "S") ≈ 0.3520833333333334 && ae("REG1", "2020", "ELCTECOA00", "NRG", "W") ≈ 0.384
            @test ae("REG1", "2020", "ELCTECOA00", "NRG", "ANNUAL") === nothing
            # L28: the VDA_FLOP record gives RSHEOIL an UNCD7 row
            @test has("UNCD7", "1", "REG1", "RSHEOIL", "NRG", "RSDOIL", "ANNUAL", "ANNUAL")
            # L21, L46: the EPS ACT_EFF on ELCHYD is kept and copied to the DAYNITE slices
            @test ae("REG2", "2010", "ELCREHYD00", "ELCHYD", "SD") == 0.0
        else
            # L13-15: ramping on ELCTECOA00 only (not on the trade process IMPNRGZ), partial loads 'FX' and 'N'
            @test sort(gset(tm, "RP_UPL").keys) == [("REG1", "ELCTECOA00", "FX")]
            @test has("RP_PL", "REG1", "ELCTECOA00", "FX") && has("RP_PL", "REG1", "ELCTECOA00", "N")
            # pp_actef.vda L19: RP_PL 'FX' keeps ELCTECOA00's NRG group out of the singletons
            @test has("RPG_ACE", "REG1", "ELCTECOA00", "NRG", "IN") && !has("RP_GRP", "REG1", "ELCTECOA00", "NRG")
            # pp_actef.vda L31: NORTS removes RSHEOIL's W value of the past vintage 2004
            @test ae("REG1", "2004", "RSHEOIL", "NRG", "S") == 0.8 && ae("REG1", "2004", "RSHEOIL", "NRG", "W") === nothing
        end
    end
end
