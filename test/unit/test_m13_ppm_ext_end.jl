# M1.3 (18b): ppm_ext.vda L59-169 with equcrtp.vda PPM_EXT (v4.9.7), the end
# of the prelv -> ppm segment. Layer 1 on TIMES_Demo demo12 reduce_off from
# the prelv checkpoint, every set and parameter compared at the ppm
# checkpoint (scripts/m13_probe.jl does the same on the core reference runs,
# reduce_off and as_run), and on five crafted states against GAMS running
# ppmain.mod L616-1357 and ppm_ext.vda L11-169 itself, every symbol written
# compared at the end of ppm_ext.vda (scripts/m13_replay.jl does the same on
# the core models' own states).

using OpenTIMES: TimesModel, DumpData, layer1, ppm_ext!, ppm_ext_symbols, PPM_EXT_ACTEF_OUTPUTS, PPM_EXT_OUTPUTS, gset, gparam
using OpenTIMES.Reference: ispass
import TOML

isdefined(@__MODULE__, :PPMAIN_TO_PPM_EXT) || include("test_m13_ppm_ext.jl")
isdefined(@__MODULE__, :PPMAIN_FLO_NEW) || include("ppmain_flo_case.jl")
const PPMAIN_TO_PPM = (PPMAIN_TO_PPM_EXT..., ppm_ext!)

@testset "prelv -> ppm: the whole segment, every symbol at ppm, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prelv"); switches=fx["switches"])
    foreach(f -> f(tm), PPMAIN_TO_PPM)
    names = ppm_ext_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_ppm")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(names) > 800 && all(ispass, r)
end

const PPM_EXT_ALL = unique(vcat(PPM_EXT_ACTEF_ALL, PPM_EXT_OUTPUTS))

@testset "ppmain.mod L616-1357, ppm_ext.vda L11-169 against GAMS on crafted states" begin
    for c in vcat(PPM_EXT_CASES, PPM_EXT_CASES_B)
        tm = ppm_ext_start(FIXTURES, c)
        foreach(f -> f(tm), PPMAIN_TO_PPM)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "ppm_ext_end_unit_gams", c)), PPM_EXT_ALL)
        foreach(d -> ispass(d) || println(c, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        p(n, k...) = get(gparam(tm, n).values, k, nothing)
        has(n, k...) = k in gset(tm, n).members
        if c == "chp"
            # ppm_ext.vda L145-155: ELCTEGAS00 an ECT CHP (NCAP_CEH 2): NCAP_AFCS for its electricity, RPS_CAFLAC at ANNUAL
            @test p("NCAP_AFCS", "REG1", "2010", "ELCTEGAS00", "ELC", "ANNUAL") ≈ 1.0588235294117647
            @test has("RPS_CAFLAC", "REG1", "ELCTEGAS00", "ANNUAL", "UP")
            # L156: VDA_CEH < NCAP_CEH copies the values (G34)
            @test p("VDA_CEH", "REG1", "2015", "ELCTEGAS00") == 2.0
        elseif c == "afx"
            # L160-164: the options at '0': 1001 (odd) gives NCAP_AFSX UP/FX, 2000 (even) LO, 5000 RP_AFB -1 and NCAP_AFM dropped
            @test p("NCAP_AFSX", "REG1", "2010", "ELCTECOA00", "UP") == 0.05 && p("NCAP_AFSX", "REG1", "2010", "ELCTECOA00", "LO") === nothing
            @test p("NCAP_AFSX", "REG1", "2015", "FTE-AGRELC", "LO") == 0.03
            @test p("RP_AFB", "REG1", "ELCTEGAS00", "UP") == -1.0 && p("PRC_YMIN", "REG1", "ELCTEGAS00") == 5.0
            @test p("NCAP_AFSM", "REG1", "0", "ELCTECOA00") == 2000.0 && p("NCAP_AFM", "REG1", "2010", "ELCTEGAS00") === nothing
        elseif c == "funcx"
            # L62-65: ACT to the shadow group NRG, the PG commodity of a singleton group, the PG group from ACT
            @test p("FLO_FUNCX", "REG1", "2010", "ELCTECOA00", "NRG", "ELC") == 2.0
            @test p("FLO_FUNCX", "REG1", "2010", "FTE-AGRELC", "NRG", "AGRELC") == 4.0
            @test p("FLO_FUNCX", "REG1", "2015", "ELCTECOA00", "ELC", "ELCCOA") == 3.0
        end
    end
end
