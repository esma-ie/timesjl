# M1.3 (11a): ppmain.mod L800-821 (v4.9.7): the flow attributes levelled by
# pp_lvlfc.mod, the FLO_PKCOI default and pp_chp.mod. Layer 1 on TIMES_Demo
# demo12 reduce_off from the prelv checkpoint, compared at the ppm
# checkpoint on what these lines settle (scripts/m13_probe.jl does the same
# on the core reference runs), and on crafted states against GAMS running
# ppmain.mod L616-821 itself, every symbol written compared at L821
# (scripts/m13_replay.jl does the same on the core models' own states).

using OpenTIMES: TimesModel, DumpData, layer1, pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flo_symbols, gset, gparam
using OpenTIMES.Reference: ispass
import TOML

@testset "prelv -> ppm: ppmain.mod L800-821 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prelv"); switches=fx["switches"])
    pp_qafs!(tm)
    ppmain_dflt!(tm)
    ppmain_tsattr!(tm)
    ppmain_flo!(tm)
    names = ppmain_flo_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_ppm")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(names) == 14 && all(ispass, r)
    # L814-817: FLO_PKCOI 1 for the ELC inputs of the FTE processes, at their RPCS_VAR timeslices
    @test length(gparam(tm, "FLO_PKCOI").values) == 168 && all(==(1.0), values(gparam(tm, "FLO_PKCOI").values))
end

isdefined(@__MODULE__, :PPMAIN_DFLT_OUTPUTS) || include("ppmain_dflt_case.jl")
isdefined(@__MODULE__, :PPMAIN_TSATTR_NEW) || include("ppmain_tsattr_case.jl")
include("ppmain_flo_case.jl")
const PPMAIN_FLO_ALL = unique(vcat(PPMAIN_DFLT_OUTPUTS, PPMAIN_TSATTR_NEW, PPMAIN_FLO_NEW))

@testset "ppmain.mod L616-821 against GAMS on crafted states" begin
    for name in PPMAIN_FLO_CASES
        tm = ppmain_flo_start(FIXTURES, name)
        pp_qafs!(tm)
        ppmain_dflt!(tm)
        ppmain_tsattr!(tm)
        ppmain_flo!(tm)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "ppmain_flo_unit_gams", name)), PPMAIN_FLO_ALL)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test length(r) == 82 && all(ispass, r)
        v(n) = gparam(tm, n).values
        g(k...) = get(v(k[1]), k[2:end], nothing)
        if name == "flo"
            p, cur = "ELCTEGAS00", "MEuro05"
            # %11 N: ANNUAL copied (once flagged by S in 2015), S inherited, the records off RPCS_VAR and the flag deleted
            d = v("FLO_DELIV")
            @test length(d) == 6 && d[("REG1", "2010", p, "ELCGAS", "WN", cur)] == 2.0 && d[("REG1", "2015", p, "ELCGAS", "SN", cur)] == 3.0
            @test isempty(v("FLO_TAX")) && collect(keys(v("FLO_COST"))) == [("REG1", "2010", p, "ELCCO2", "ANNUAL", cur)]
            # L809-810: the group values at PRC_TS, ELC at RPCS_VAR, the originals deleted
            @test g("FLO_BDLVL", "REG1", "2010", p, "ACT", "WD", "UP") == 0.5 && g("FLO_BDLVL", "REG1", "2010", p, "ACT", "ANNUAL", "UP") === nothing
            @test g("FLO_BDLVL", "REG1", "2015", p, "ELC", "SN", "LO") == 0.3 && g("FLO_BDLVL", "REG1", "2015", p, "ELC", "S", "LO") === nothing
            # L811 (%11 0): ANNUAL kept and filled down; S levelled, then deleted
            @test g("ACT_FLO", "REG1", "2010", p, "ELC", "ANNUAL") == 1.2 && g("ACT_FLO", "REG1", "2010", p, "ELC", "WN") == 1.2
            @test g("ACT_FLO", "REG1", "2015", p, "ELC", "SD") == 1.4 && g("ACT_FLO", "REG1", "2015", p, "ELC", "S") === nothing
            # L814-817: no default for PRC_PKNO, nor for a process with a FLO_PKCOI of its own in any milestone
            @test !any(k -> k[3] in ("FTE-AGRELC", "FTE-COMELC") && k[2] != "2010", keys(v("FLO_PKCOI")))
        else
            q = "REFEOIL00"
            # pp_chp.mod L12: LO dropped where FX is given; L16: the slopes; L30-32: back-pressure units at 0.5
            @test g("NCAP_CHPR", "REG1", "2015", q, "LO") === nothing
            @test g("NCAP_CEH", "REG1", "2010", q) ≈ (0.4 / 0.9 * 3 - 1) / 2 && g("NCAP_CEH", "REG1", "2020", q) ≈ 1.5
            @test g("NCAP_CEH", "REG1", "2015", q) == 0.5 && g("NCAP_BPME", "REG1", "2015", q) ≈ -0.75
            # L39-42: PRC_ACTFLO of the PG from the slope: (1-BPME) below 1, (1+(1/CEH-1)/(1+1/CHPR)) above
            @test g("PRC_ACTFLO", "REG1", "2015", q, "ELC") ≈ 1.75 && g("PRC_ACTFLO", "REG1", "2020", q, "ELC") ≈ 1 + (1 / 1.5 - 1) / 2
            # L18, L44, L60: the overall efficiency, the heat FLO_SUM, the ACT flows
            @test g("FLO_SUM", "REG1", "2010", q, "ELC", "OIL", "ELC", "ANNUAL") == 0.4
            @test g("FLO_SUM", "REG1", "2015", q, "OIL", "ELC", "OIL", "ANNUAL") ≈ 0.3 / 1.75
            # L58 or L50-56: ELCTEGAS00's heat share of ELCCO2, or its ELC share over NRG
            s = g("FLO_SHAR", "REG1", "2010", "ELCTEGAS00", "ELCCO2", "ELC", "SD", "UP")
            e = g("FLO_SHAR", "REG1", "2010", "ELCTEGAS00", "ELC", "NRG", "SD", "LO")
            @test name == "chp" ? (s ≈ 0.6 / 1.6 && e === nothing) : (s === nothing && e ≈ 1 / 1.6)
            # L64: NCAP_PKCNT per unit of electricity; L71: the work sets cleared
            @test g("NCAP_PKCNT", "REG1", "2015", q, "SD") ≈ 1 / 1.75
            @test isempty(gset(tm, "RVP").keys) && isempty(gset(tm, "PRC_ACT").keys) && length(gset(tm, "CHP_ELC").keys) == 2
        end
    end
end
