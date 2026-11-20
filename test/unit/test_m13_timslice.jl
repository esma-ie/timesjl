# M1.3 (4): timslice.mod (v4.9.7) with pp_off.mod, the timeslice
# preprocessing. Layer 1 on TIMES_Demo demo12 reduce_off from the init
# checkpoint (after ppmain_head! and ppmain_years!), compared at the prep
# checkpoint on the symbols timslice.mod settles (scripts/m13_probe.jl does
# the same on the core reference runs), and on crafted states against GAMS
# running ppmain.mod L1-196 itself.

using OpenTIMES: TimesModel, DumpData, layer1, ppmain_head!, ppmain_years!, timslice!, timslice_symbols, gset, gparam
using OpenTIMES.Reference: ispass
import TOML

@testset "timslice.mod layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_init"); switches=fx["switches"])
    ppmain_head!(tm)
    ppmain_years!(tm)
    timslice!(tm)
    names = timslice_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_prep")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(r) == 24 && all(ispass, r)
    # L18: ANNUAL joins TS_GROUP for the external regions too; L46: the seasons' fractions from their children
    @test ("IMPEXP", "ANNUAL", "ANNUAL") in gset(tm, "TS_GROUP").members
    @test gparam(tm, "G_YRFR")[("REG1", "S")] ≈ 0.249714611872146 + 0.229737442922374
    # L63: each level maps to the next coarser one only (the inner loop stops at Z=9)
    @test sort(collect(gset(tm, "RLUP").members)) ==
          [("REG1", "DAYNITE", "SEASON"), ("REG1", "SEASON", "ANNUAL"), ("REG2", "DAYNITE", "SEASON"), ("REG2", "SEASON", "ANNUAL")]
end

include("timslice_case.jl")

@testset "timslice.mod against GAMS on crafted states" begin
    for name in TIMSLICE_CASES
        tm = timslice_start(FIXTURES, name)
        ppmain_head!(tm)
        ppmain_years!(tm)
        timslice!(tm)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "timslice_unit_gams", name)), TIMSLICE_OUTPUTS)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        g = gparam(tm, "G_YRFR").values
        fr(s) = get(g, ("REG1", s), nothing)
        if name == "norm"
            # L78 at ANNUAL: S (filled from SD, SN) and the given W scaled to the year; at SEASON: their children to them
            @test fr("S") + fr("W") ≈ 1 && fr("SD") + fr("SN") ≈ fr("S") && fr("WD") + fr("WN") ≈ fr("W")
            @test fr("W") ≈ 0.5 / (0.249714611872146 * 1.02 + 0.229737442922374 + 0.5)
        elseif name == "zerofrac"
            # L50-55: SN (no fraction) and WN (negative, its record kept) leave the tree; one child each, so no RS_STG
            @test fr("SN") === nothing && fr("WN") == -0.1 && !any(k -> k[1] == "REG1" && k[3] == "SN", gset(tm, "TS_MAP").keys)
            @test !haskey(gparam(tm, "RS_STG").values, ("REG1", "SD")) && fr("S") + fr("W") ≈ 1
            # L86-87: a leaf's TS_CYCLE cleared, one below 1 reset to 365/G_CYCLE('DAYNITE'), one of 2 kept; WEEKLY kept
            tc = gparam(tm, "TS_CYCLE").values
            @test tc[("REG2", "S")] == 2.0 && tc[("REG2", "W")] == 1.0 && !haskey(tc, ("REG2", "SD"))
            @test gparam(tm, "G_CYCLE")[("WEEKLY",)] == 50.0
        elseif name == "tsoff_first"
            # L37: the first period is off, so W's subtree has no fraction and S takes the year
            @test fr("W") === nothing && fr("WD") === nothing && fr("S") ≈ 1 && isempty(gparam(tm, "NORTS").values)
        elseif name == "tsoff_later"
            # no DYNTS and the first period on: nothing changes (as on demo12 itself)
            @test fr("S") ≈ 0.249714611872146 + 0.229737442922374 && isempty(gparam(tm, "NORTS").values)
        elseif name == "dynts"
            # L38: NORTS -INF for S and below in the periods off; L70-75: W, alone in 2005, takes the year
            n = gparam(tm, "NORTS").values
            @test sort(collect(keys(n))) == sort([("REG1", t, s) for t in ("2005", "2010") for s in ("S", "SD", "SN")])
            @test all(==(-Inf), values(n)) && fr("W") == 1.0 && fr("WD") == 0.5 && fr("S") == 0.5
            @test get(g, ("REG2", "W"), nothing) === nothing
        elseif name == "uc"
            # L114, L119: OPTION < pairs the repeated TS in reverse (G26): RS_UP(R,child,J,parent), JS(J,parent)
            @test ("REG1", "S", "30", "ANNUAL") in gset(tm, "RS_UP").members && ("1", "S") in gset(tm, "JS").members
            @test !(("1", "ANNUAL") in gset(tm, "JS").members) && gparam(tm, "JS_CCL")[("REG1", "1", "S")] == 365.0
        end
    end
    # L24, L74: GAMS ABORTs
    for name in ("twolevels", "dynts_abort")
        tm = timslice_start(FIXTURES, name)
        ppmain_head!(tm)
        ppmain_years!(tm)
        @test_throws ErrorException timslice!(tm)
    end
end
