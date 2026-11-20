# M1.3 (5): ppmain.mod L199-247 (v4.9.7), past investments on milestones,
# NCAP_START, RTP_OFF, RTP and RVP. Layer 1 on TIMES_Demo demo12 reduce_off
# from the init checkpoint (after ppmain_head!, ppmain_years! and timslice!),
# compared at the prep checkpoint on the symbols the block settles
# (scripts/m13_probe.jl does the same on the core reference runs), and on
# crafted states against GAMS running ppmain.mod L1-247 itself.

using OpenTIMES: TimesModel, DumpData, layer1, ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, ppmain_rtp_symbols, gset, gparam
using OpenTIMES.Reference: ispass
import TOML

@testset "ppmain.mod L199-247 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_init"); switches=fx["switches"])
    ppmain_head!(tm)
    ppmain_years!(tm)
    timslice!(tm)
    ppmain_rtp!(tm)
    names = ppmain_rtp_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_prep")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    # PRC_VINT data: RVP is left to preppm.mod (fillvint.gms L18, preppm.mod L61)
    @test names == ["PRC_NOFF", "RTP_OFF", "VNT", "COEF_RTP", "RTP"] && all(ispass, r)
    # L217: NCAP_START 2006 gives the range BOH-2005 (%BOTIME% 1960), so the process is off in 2005 only
    @test ("REG1", "CAPNELC1", "BOH", "2005") in gset(tm, "PRC_NOFF").members
    @test ("REG1", "2005", "CAPNELC1") in gset(tm, "RTP_OFF").members && !(("REG1", "2005", "CAPNELC1") in gset(tm, "RTP").members)
end

include("ppmain_rtp_case.jl")

@testset "ppmain.mod L199-247 against GAMS on crafted states" begin
    for name in PPMAIN_RTP_CASES
        tm = ppmain_rtp_start(FIXTURES, name)
        ppmain_head!(tm)
        ppmain_years!(tm)
        timslice!(tm)
        ppmain_rtp!(tm)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "ppmain_rtp_unit_gams", name)), PPMAIN_RTP_OUTPUTS)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        off(r, p) = sort([k[2] for k in gset(tm, "RTP_OFF").keys if k[1] == r && k[3] == p])
        rtp(r, p) = sort([k[2] for k in gset(tm, "RTP").keys if k[1] == r && k[3] == p])
        ymax = gparam(tm, "PRC_YMAX").values
        if name == "pasti"
            # L200, L206: 2010 and 2015 move to the year before; 2012 lies in the period of 2010; 2005 (B = M) stays
            @test sort(collect(gset(tm, "VNT").members)) == [("2009", "2010"), ("2012", "2010"), ("2014", "2015")]
            p = gparam(tm, "NCAP_PASTI").values
            # L202: 3+0.1+1-1 rounds as GAMS's; L203: the share of the milestone's investment
            @test p[("REG1", "2009", "COTEBIO")] == 3 + 0.1 + 1 - 1 && p[("REG1", "2005", "CSHEBIO")] == 1.5
            @test gparam(tm, "COEF_RTP")[("REG1", "2009", "COTEBIO")] == 0.1 / (3 + 0.1 + 1 - 1)
            # L204: the milestones' records go, the EPS one with them
            @test !any(k -> k[2] in ("2010", "2015"), keys(p))
            # L201: the moved year's period
            @test [gparam(tm, s)[("2009",)] for s in ("B", "E", "M", "D")] == [2009.0, 2010.0, 2009.0, 2.0]
            @test !(("2010",) in gset(tm, "PASTYEAR").members) && ("2005",) in gset(tm, "PASTYEAR").members
        else
            # L235-238: the later ranges of EXPCOA1 through pp_off.mod; G_OFFTHD leaves only 2050 off
            @test off("REG1", "EXPCOA1") == (name == "noff" ? ["2015", "2020", "2030", "2050"] : ["2050"])
            # L221-225: delayed to 2012 (a range from the past), then pp_off over both ranges
            @test off("REG1", "EXPELC1") == ["2005", "2010"] && rtp("REG1", "EXPELC1") == ["2015", "2020", "2030", "2050"]
            # L225: a range ending before the first period, SMAX over nothing
            @test ymax[("REG1", "EXPDSL1")] == -Inf && length(rtp("REG1", "EXPDSL1")) == 6
            # L215-217: START before %BOTIME% (user range cleared, none set), after %EOTIME%+1, non-integer leads rounded
            @test !any(k -> k[1] == "REG1" && k[2] == "CAPNELC1", gset(tm, "PRC_NOFF").keys)
            noff = gset(tm, "PRC_NOFF").members
            @test all(k -> k in noff, [("REG1", "COTNBIO1", "BOH", "2200"), ("REG1", "COTNCOA1", "BOH", "2011"), ("REG1", "COTNELC1", "BOH", "2012")])
            @test isempty(rtp("REG1", "COTNBIO1")) && isempty(rtp("REG1", "ELCRNHYD01"))
            # L227-231: past investment, so the delay is ignored (RTP_OFF stays); with G_OFFTHD nothing is off, PRC_YMAX -INF
            @test "2005" in rtp("REG1", "COTNGAS1") && "1980" in rtp("REG1", "COTNGAS1")
            @test off("REG1", "COTNGAS1") == (name == "noff" ? ["2005"] : String[])
            name == "noff_offthd" && @test ymax[("REG1", "COTNOIL1")] == -Inf && "2005" in rtp("REG1", "COTNOIL1")
        end
    end
end
