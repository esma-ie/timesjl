# M1.3 (3): ppmain.mod L138-191 (v4.9.7), the years and periods. Layer 1 on
# TIMES_Demo demo12 reduce_off from the init checkpoint (after ppmain_head!),
# compared at the prep checkpoint on the symbols L138-191 settles
# (scripts/m13_probe.jl does the same on the core reference runs), and on
# crafted states against GAMS running L1-191 itself.

using OpenTIMES: TimesModel, DumpData, layer1, ppmain_head!, ppmain_years!, ppmain_years_symbols, gset, gparam
using OpenTIMES.Reference: ispass
import TOML

@testset "ppmain.mod L138-191 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_init"); switches=fx["switches"])
    ppmain_head!(tm)
    ppmain_years!(tm)
    names = ppmain_years_symbols(tm)
    @test issubset(["B", "E", "PASTYEAR", "PASTMILE"], names)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_prep")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(r) == 20 && all(ispass, r)
    # OBJ MOD: ALTOBJ stays 1 and the periods run between the milestones' midpoints (L152)
    @test gparam(tm, "ALTOBJ")[()] == 1.0 && gparam(tm, "E")[("2020",)] == 2025.0 && gparam(tm, "B")[("2030",)] == 2026.0
end

include("ppmain_years_case.jl")

@testset "ppmain.mod L138-191 against GAMS on crafted states" begin
    for name in PPMAIN_YEARS_CASES
        tm = ppmain_years_start(FIXTURES, name)
        ppmain_head!(tm)
        ppmain_years!(tm)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "ppmainyears_unit_gams", name)), PPMAIN_YEARS_OUTPUTS)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        B, E, g = gparam(tm, "B"), gparam(tm, "E"), gparam(tm, "G_OFFTHD").values
        offthd(ys...) = sort([k[1] for k in keys(g)]) == sort(["2010", "2012", "2015", "2020", "2030", ys...])
        if name == "altobj"
            # L153: B(2005) = 1990 is reset; L154: 1$MOD(...) binds first, so MOD = 0 gives 2*2050-2041+1
            @test B[("2005",)] == 2005.0 && B[("2050",)] == 2041.0 && E[("2050",)] == 2060.0
            # L162: the lead of the first period is circular, MAX(M(2005)-M(2050), 1)
            @test gparam(tm, "LEAD")[("2005",)] == 1.0 && gparam(tm, "LEAD")[("2030",)] == 15.0
        elseif name == "altobj_mod"
            @test B[("2050",)] == 2033.0 && E[("2050",)] == 2067.0
        elseif name in ("offthd5", "offthdeps")
            # L33: EPS + (0.8-EPS)/18*3 at 2015; forward to 2050 only (an EPS option counts as none: ROUND(EPS) = 0)
            @test g[("2012",)] == 0.0 && g[("2015",)] ≈ 0.8 * 3 / 18 && g[("2050",)] == 0.8 && offthd("2050")
        elseif name == "offthd1"
            @test offthd()
        elseif name == "offthd2"
            @test offthd("2005", "2050") && g[("2005",)] == 0.0 && g[("2050",)] == 0.0
        elseif name == "offthd14"
            @test offthd("2005") && g[("2005",)] == 0.4
        else
            @test sort([k[1] for k in keys(g)]) == ["2010", "2012", "2030"]
        end
    end
    # L159: with OBLONG the periods must be contiguous (GAMS ABORTs)
    tm = ppmain_years_start(FIXTURES, "oblong_gap")
    ppmain_head!(tm)
    @test_throws ErrorException ppmain_years!(tm)
end
