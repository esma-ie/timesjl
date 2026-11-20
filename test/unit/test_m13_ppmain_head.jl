# M1.3 (2): ppmain.mod L1-137 (v4.9.7), the start of the init -> prep
# segment. Layer 1 on TIMES_Demo demo12 reduce_off from the init checkpoint,
# compared at the prep checkpoint on the symbols L1-137 settles
# (scripts/m13_probe.jl does the same on the core reference runs), and on
# crafted states against GAMS running L1-137 itself.

using OpenTIMES: TimesModel, DumpData, layer1, ppmain_head!, ppmain_head_symbols, gset, gparam
using OpenTIMES.Reference: ispass
import TOML

@testset "ppmain.mod L1-137 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_init"); switches=fx["switches"])
    ppmain_head!(tm)
    names = ppmain_head_symbols(tm)
    @test issubset(["RDCUR", "NCAP_PASTI", "PHYR", "INT_DEFAULT"], names)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_prep")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(r) == 27 && all(ispass, r)
    # L38: both regions discount in MEuro05; L44-45: the IMP side of a trade link from IMPEXP
    @test Set(gset(tm, "RDCUR").keys) == Set([("REG1", "MEuro05"), ("REG2", "MEuro05")])
    @test ("REG1", "IMPCOA1", "COA", "IMP") in gset(tm, "RPC_IRE") && ("IMPEXP", "IMPGAS1") in gset(tm, "RP_IRE")
end

include("ppmain_head_case.jl")

@testset "ppmain.mod L1-137 against GAMS on crafted states" begin
    for name in PPMAIN_HEAD_CASES
        tm = ppmain_head_start(FIXTURES, name)
        ppmain_head!(tm)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "ppmainhead_unit_gams", name)), PPMAIN_HEAD_OUTPUTS)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        s(n) = gset(tm, n)
        p(n) = gparam(tm, n)
        r1 = "REG1"
        if name == "nopg"
            # L61: NOT ranks below +, so a FIN output is no candidate: ELCTNGAS01 gets ELC; two candidates give no PG
            @test (r1, "ELCTNGAS01", "ELC") in s("RP_PG") && !any(k -> k[1] == r1 && k[2] == "ELCTECOA00", s("RP_PG").keys)
            @test (r1, "COTNCOA1", "DCOT") in s("RP_PG") && !any(k -> k[3] == "ACT", s("PRC_ACTUNT").keys)
            # L50: ENV and trade RPG_RED flows on a process with an activity unit; the group and COTNCOA1's are skipped
            @test (r1, "EXPCOA1", "TOTCO2", "OUT") in s("TOP") && (r1, "EXPCOA1", "GAS", "OUT") in s("TOP")
            @test !((r1, "COTNCOA1", "TOTCO2", "OUT") in s("TOP")) && isempty(s("RPG_RED"))
        elseif name == "storage"
            @test Set(k for k in s("PRC_STGTSS").keys if k[1] == r1) == Set([(r1, "ELCTNGAS01", "ELC"), (r1, "ELCTNGAS01", "ELCGAS")])
            @test (r1, "ELCTECOA00", "ELC") in s("PRC_STGIPS") && (r1, "ELCTECOA00", "ANNUAL") in s("PRC_TSL")
            @test !((r1, "ELCTECOA00", "SEASON") in s("PRC_TSL")) && (r1, "ELCTECOA00", "ELC", "IN") in s("TOP")
            @test (r1, "NST", "COTNCOA1") in s("PRC_MAP") && !((r1, "STK", "COTNCOA1") in s("PRC_MAP"))
        elseif name == "stslim"
            # ELC is a TRACKC commodity: the STS process stores nothing by default; its given IPS keeps its PRC_TSL
            @test !any(k -> k[2] == "ELCTNGAS01", s("PRC_STGTSS").keys) && (r1, "ELCTNGAS01", "DAYNITE") in s("PRC_TSL")
            @test (r1, "ELCTNGAS01", "AGRCOA", "IN") in s("TOP") && (r1, "ELCTNGAS01", "AGRCOA", "OUT") in s("TOP")
            @test s("RPC_STGN").keys == [(r1, "ELCTECOA00", "ELC", "IN")]
        else
            pasti = p("NCAP_PASTI")
            # L125-132: 9 over three years plus the 1 at 1979; 5 over 2.5 years at lags 1.5 and 0.5 (rounded: 2 and 1)
            @test [pasti[(r1, y, "ELCTECOA00")] for y in ("1978", "1979", "1980")] == [3.0, 4.0, 3.0]
            @test [get(pasti.values, (r1, y, "ELCTEGAS00"), nothing) for y in ("1978", "1979", "1980")] == [2.0, 2.0, nothing]
            @test pasti.values[(r1, "1979", "COTNCOA1")] == 0.0 && pasti[(r1, "1960", "ELCREHYD00")] == 7.5   # EPS stays EPS
            # L134-135: PASTYEAR from NCAP_PASTI, '0' left out and flagged
            @test [k[1] for k in s("PASTYEAR").keys] == ["1960", "1978", "1979", "1980", "2004"] && ("PASTI",) in s("INT_DEFAULT")
        end
    end
end
