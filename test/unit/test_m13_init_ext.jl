# M1.3 (1): the init segment, maindrv.mod L55 (v4.9.7): init_ext.dsc,
# init_ext.vda with equcrtp.vda INIT_EXT. Layer 1 on TIMES_Demo demo12
# reduce_off from the input checkpoint to the init checkpoint, on every set
# and parameter of the dump (scripts/m13_probe.jl does the same on the core
# reference runs).

using OpenTIMES: TimesModel, DumpData, layer1, init_ext!, init_ext_unported, gset, gparam, gput!, UnportedError
using OpenTIMES.Reference: ispass
import TOML

@testset "init_ext layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_input"); switches=fx["switches"])
    @test isempty(init_ext_unported(tm))
    init_ext!(tm)
    names = [i.name for i in values(tm.data.dump.symbols) if i.kind in (:set, :parameter)]
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_init")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(r) > 800 && all(ispass, r)
    # L57-59: the first milestone and the year before it
    @test gset(tm, "MIYR_1").keys == [("2005",)] && gparam(tm, "MIYR_BOH")[()] == 2004 && gset(tm, "PYR_S").keys == [("2004",)]
    # L92-93: a residual capacity puts PRC_RESID at '0' (EPS when there was none) and NCAP_PASTI at PYR_S
    @test all(k -> haskey(gparam(tm, "NCAP_PASTI"), (k[1], "2004", k[3])), [k for k in gparam(tm, "PRC_RESID").keys if k[2] == "0"])
    # init_ext.dsc (DSCAUTO YES loads it): no discrete data, so %DSC% becomes NO
    @test tm.switches["DSC"] == "NO"
end

include("init_ext_case.jl")

@testset "init_ext against GAMS on crafted states" begin
    for name in sort(collect(keys(INIT_EXT_CASES)))
        tm = init_ext_start(FIXTURES, name)
        @test isempty(init_ext_unported(tm))
        init_ext!(tm)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "initext_unit_gams", name)), INIT_EXT_OUTPUTS)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        p(n) = gparam(tm, n)
        s(n) = gset(tm, n)
        if name == "flags"
            # L53-54: DATAYEAR rebuilt from the milestones and the years 2000-2050 divisible by 5; L57: B(2005) reset
            @test ("2045",) in s("DATAYEAR") && !(("2055",) in s("DATAYEAR")) && p("B")[("2005",)] == 2005
            @test ("REG1", "ELCTNGAS01") in s("PRC_PKNO") && Set(k[2] for k in s("PRC_PKAF").keys if k[1] == "REG1") == Set(["ELCTECOA00", "COTNCOA1"])
            @test Set(s("PRC_STGIPS").keys) == Set([("REG1", "ELCTNGAS01", "ELC"), ("REG1", "COTNCOA1", "AGRCOA")])
            # L69-71: the ANNUAL ACT_CSTUP is replaced by ACT_CSTPL, the DAYNITE one kept; NCAP_COST for TRACKP
            @test p("ACT_CSTUP")[("REG1", "2010", "ELCTECOA00", "ANNUAL", "MEuro05")] == 3.5
            @test p("ACT_CSTUP")[("REG1", "2010", "ELCTECOA00", "DAYNITE", "MEuro05")] == 4.0
            @test p("ACT_CSTUP")[("REG1", "2006", "ELCTNGAS01", "ANNUAL", "MEuro05")] == 750.0 && isempty(s("TRACKP"))
            # L86-87: only the group with a nonzero year survives at the data years; UNCD7 keeps it with '' labels (G36)
            fc = p("FLO_COST")
            @test !any(k -> k[3] == "ELCTNGAS01" && k[4] == "ELCGAS", keys(fc.values)) && length(fc) == 3
            @test s("UNCD7").keys == [("REG1", "0", "ELCTECOA00", "ELCCOA", "ANNUAL", "MEuro05", "")]
            @test ("REG1", "EXPCOA1", "ELCCO2", "OUT") in s("RPG_RED") && !(("REG1", "ELCTNGAS01", "ELCGAS", "OUT") in s("RPG_RED"))
            @test Set(s("KEEP_FLOF").keys) == Set([("REG1", "ELCTNGAS01", "ELC"), ("REG1", "ELCTECOA00", "ELCCOA")])
            @test ("PASTI",) in s("INT_DEFAULT") && ("REG1", "UC_RNW-PP_LOW", "LHS", "SEASON") in s("UC_TSL")
            @test ("REG1", "UC_RNW-PP_LOW", "ACT", "ELCTNGAS01") in s("UC_GMAP_P") && length(p("UC_FLOBET")) == 2
        else
            # L57-59: B(2005) = 2003 is kept: MIYR_BOH 2002, PYR_S 2002
            @test p("MIYR_BOH")[()] == 2002 && s("PYR_S").keys == [("2002",)]
            # L118-124: what is left of the 'N' bounds, and the OFF-ranges they make
            @test Dict(k => v for (k, v) in p("NCAP_BND").values if k[4] == "N") ==
                  Dict(("REG1", "2020", "ELCTNGAS01", "N") => 2019.0, ("REG1", "0", "ELCTNGAS01", "N") => 1.0, ("REG1", "0", "COTNCOA1", "N") => -1.0)
            @test Set(s("PRC_NOFF").keys) == Set([("REG1", "ELCTNGAS01", "2010", "2025"), ("REG1", "ELCTNGAS01", "2015", "2200"),
                                                  ("REG1", "ELCTNGAS01", "2020", "2019"), ("REG1", "ELCTECOA00", "2005", "2010")])
            @test p("NCAP_START")[("REG1", "ELCTECOA00")] == 2031 && !haskey(p("NCAP_START"), ("REG1", "ELCTNGAS01"))
        end
    end
end

@testset "init_ext refusals" begin
    mk(sw) = TimesModel(joinpath(FIXTURES, "demo12_off_input"); switches=sw)
    @test occursin("L129", only(init_ext_unported(mk(Dict("CLI" => "YES")))))
    @test occursin("GDX_IREBND", only(init_ext_unported(mk(Dict("GDX_IREBND" => "prev")))))
    @test_throws UnportedError init_ext!(mk(Dict("STAGES" => "YES")))
    tm = mk(Dict("DSCAUTO" => "YES"))
    gput!(tm, "NCAP_DISC", Dict(("REG1", "2010", "ELCTNGAS01", "1") => 100.0))
    @test occursin("NCAP_DISC", only(init_ext_unported(tm)))
    @test isempty(init_ext_unported(mk(Dict{String,String}())))   # without DSC the extension is not loaded
end
