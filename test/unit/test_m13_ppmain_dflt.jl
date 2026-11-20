# M1.3 (9): ppmain.mod L616-682 (v4.9.7), pp_qafs.mod (the FLO_SHAR QA
# checks), SHAPE and MULTI with filshape.gms and filparam.gms, the defaults
# and the capacity-only flows, the start of the prelv -> ppm segment. Layer 1
# on TIMES_Demo demo12 reduce_off from the prelv checkpoint, compared at the
# ppm checkpoint on what these lines settle (scripts/m13_probe.jl does the
# same on the core reference runs), and on crafted states against GAMS
# running ppmain.mod L616-682 itself, every symbol written compared at L682
# (scripts/m13_replay.jl does the same on the core models' own states).

using OpenTIMES: TimesModel, DumpData, layer1, pp_qafs!, pp_qafs_symbols, ppmain_dflt!, ppmain_dflt_symbols, gset, gparam
using OpenTIMES.Reference: ispass
import TOML

@testset "prelv -> ppm: ppmain.mod L616-682 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prelv"); switches=fx["switches"])
    pp_qafs!(tm)
    ppmain_dflt!(tm)
    names = vcat(pp_qafs_symbols(tm), ppmain_dflt_symbols(tm))
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_ppm")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(names) == 19 && all(ispass, r)
    # L629, L634: no SHAPE or MULTI data, so index '1' alone, up to STARTOFF = MAXLIFE+1 and over EACHYEAR
    @test length(gparam(tm, "SHAPE").values) == 61 && length(gparam(tm, "MULTI").values) == 111
end

include("ppmain_dflt_case.jl")

@testset "ppmain.mod L616-682 against GAMS on crafted states" begin
    for name in PPMAIN_DFLT_CASES
        tm = ppmain_dflt_start(FIXTURES, name)
        pp_qafs!(tm)
        ppmain_dflt!(tm)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "ppmain_dflt_unit_gams", name)), PPMAIN_DFLT_OUTPUTS)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        v(n) = gparam(tm, n).values
        fs = v("FLO_SHAR")
        sh(p, y, cg) = Dict((k[4], k[6], k[7]) => x for (k, x) in fs if k[1] == "REG1" && k[2] == y && k[3] == p && k[5] == cg)
        if name == "qafs"
            # pp_qafs.mod L52-64: 0.8+0.7+EPS+EPS fixed; the limit is MAX(0.5, 1.5/33.5*8-SHARETOL) = 0.5; the loop stops at
            #   the first share above it (HFO before LPG in GAMS order), so LPG stays
            e = sh("FTE-ELCOIL", "2010", "FTE-ELCOIL_NRGI")
            @test !haskey(e, ("HFO", "ANNUAL", "FX")) && e[("LPG", "ANNUAL", "FX")] == 0.8 && length(e) == 3
            # L73-86: FX+UP sum to 0.8; the first UP above -0.2 (DSL) is dropped, the other UP become FX
            i = sh("FTE-INDOIL", "2015", "FTE-INDOIL_NRGI")
            @test !any(k -> k[1] == "DSL", keys(i)) && all(k -> k[3] == "FX", keys(i)) && length(i) == 6
            # L93-107: LO+FX sum to 1.7; DSL (0.9 > 0.7) dropped, LO into FX, the UP of the group removed
            o = sh("REFEOIL00", "2020", "REFEOIL00_NRGO")
            @test !any(k -> k[1] == "DSL", keys(o)) && o[("GSL", "ANNUAL", "FX")] == 0.3 && all(k -> k[3] == "FX", keys(o))
            # L42-44: UP of 1.2 dropped, a share below SHARETOL and a negative FX made EPS, an LO 0.99995 made 1
            a = sh("AOTETOT", "2030", "AOTETOT_NRGI")
            @test !haskey(a, ("AGROIL", "ANNUAL", "UP")) && a[("AGRELC", "ANNUAL", "UP")] == 0.0 && a[("AGRGAS", "ANNUAL", "FX")] == 0.0
            @test a[("AGRBIO", "ANNUAL", "LO")] == 1.0 && a[("AGRCOA", "S", "UP")] == 1.5
            # L32-37: FX overrides the UP of DSL, at S too
            c = sh("FTE-COMOIL", "2010", "FTE-COMOIL_NRGI")
            @test c[("DSL", "ANNUAL", "FX")] == 0.86 && !haskey(c, ("DSL", "ANNUAL", "UP")) && !haskey(c, ("DSL", "S", "UP"))
            # L25-26: the share at S keeps IDM1ETOT_NRGI out of the checks (FX summing to 1.2 kept)
            @test length(sh("IDM1ETOT", "2010", "IDM1ETOT_NRGI")) == 6
            # L16-19: ELC is outside FTE-AGROIL_NRGI, so it is left as it is (L42 needs COM_GMAP)
            @test sh("FTE-AGROIL", "2010", "FTE-AGROIL_NRGI")[("ELC", "ANNUAL", "UP")] == 1.0
        elseif name == "notgrp"
            # L16-19: AGROIL is an output of FTE-AGROIL but outside FTE-AGROIL_NRGI: dropped from RP_CCG, so no output group
            @test !any(k -> k[1] == "REG1" && k[2] == "FTE-AGROIL" && k[4] == "OUT", gset(tm, "RPG_RED").keys)
            @test ("REG1", "FTE-AGROIL", "FTE-AGROIL_NRGI", "IN") in gset(tm, "RPG_RED").members
        else
            # %SHARELAX% NO: the fixed shares summing to 1.5 are all kept
            @test length(sh("FTE-ELCOIL", "2015", "FTE-ELCOIL_NRGI")) == 4
            # STARTOFF = CEIL(MAX(60, 0.85*100))+1; filshape.gms: 1 before the first age, linear between, the last value after
            @test v("STARTOFF")[()] == 86.0
            s = v("SHAPE")
            @test s[("2", "4")] == 1.0 && s[("2", "7")] ≈ 0.68 && s[("2", "20")] ≈ 0.25 && !haskey(s, ("2", "30"))
            @test s[("3", "86")] == 1.1 && !haskey(s, ("3", "87")) && s[("5", "9")] ≈ 0.875 && s[("5", "86")] == 0.6
            # L630: the EPS points and the EPS extrapolated from them are gone
            @test count(k -> k[1] == "4", keys(s)) == 2
            # RTC_SHED: J '1'+MAX(0,x-1) with the lead rounded (2.6 -> '3'); a non-milestone year left out
            @test Set(gset(tm, "RTC_SHED").keys) == Set([("REG1", "2010", "DCOT", "LO", "2"), ("REG1", "2015", "DCAP", "UP", "3"),
                                                        ("REG1", "2020", "DCAP", "LO", "1")])
            # MULTI: forward from the data, back from the first value up to 1; option -1 filled from its first value
            m = v("MULTI")
            @test m[("2", "1960")] == 1.0 && m[("2", "2020")] ≈ 1.35 && m[("2", "2052")] == 1.5
            @test m[("3", "1960")] == 0.5 && m[("3", "0")] == -1.0 && m[("4", "2050")] == 0.0 && m[("6", "2010")] ≈ 0.6
            # defaults
            @test v("NCAP_ELIFE")[("REG1", "2010", "ELCTECOA00")] == 0.0 && v("NCAP_ELIFE")[("REG1", "2015", "ELCTECOA00")] == 25.0
            @test v("NCAP_DLIFE")[("REG1", "2010", "ELCTECOA00")] == 1.0 && !haskey(v("NCAP_DLIFE"), ("REG1", "2004", "ELCTECOA00"))
            @test v("NCAP_DELIF")[("REG1", "2015", "ELCTECOA00")] == 3.0 && v("NCAP_DELIF")[("REG1", "2020", "ELCTECOA00")] == 0.0
            @test v("NCAP_CLED")[("REG1", "2010", "ELCTEGAS00", "COA")] == 2.0 && v("NCAP_CLED")[("REG1", "2020", "ELCTEGAS00", "COA")] == 0.0
            @test v("NCAP_BPME")[("REG1", "2010", "ELCTECOA00")] == 1.0 && v("NCAP_BPME")[("REG1", "2015", "ELCTECOA00")] == 0.9
            @test v("NCAP_CHPR")[("REG1", "2004", "ELCTECOA00", "UP")] == 1.0 && !haskey(v("NCAP_CHPR"), ("REG1", "2010", "ELCTEGAS00", "UP"))
            @test v("STG_EFF")[("REG1", "2004", "ELCTECOA00")] == 1.0 && v("STG_EFF")[("REG1", "2010", "FTE-ELCOIL")] == 0.9
            # capacity-only flows: the PG, the shared, the traded and the actflow commodities lose RPC_NOFLO; UC_CAPFLO kept all
            @test Set(gset(tm, "RPC_NOFLO").keys) == Set([("REG1", "ELCTECOA00", "DCAP"), ("REG1", "ELCTEGAS00", "ELCGAS"), ("REG1", "EXPCOA1", "DSL")])
            @test length(gset(tm, "UC_CAPFLO").keys) == 7 && ("REG1", "ELCTECOA00", "DCAP", "ANNUAL") in gset(tm, "RPCS_VAR").members
            @test isempty(gset(tm, "TRACKPC").keys)
        end
    end
end
