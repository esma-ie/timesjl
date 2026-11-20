# M1.3 (8a): ppmain.mod L461-611 (v4.9.7), lifetimes, capacity transfer,
# capacity bounds and availability. Layer 1 on TIMES_Demo demo12 reduce_off
# from the prep checkpoint, compared at the prelv checkpoint on the symbols
# the step settles (scripts/m13_probe.jl does the same on the core reference
# runs), and on crafted states against GAMS running ppmain.mod L1-247 and
# L249-611, preppm.mod L1-212 and L218-252 and prep_ext.vda itself.

using OpenTIMES: TimesModel, DumpData, layer1, ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, prep_ext!, preppm_shape!,
             ppmain_topo!, ppmain_tslvl!, ppmain_life!, ppmain_life_symbols, gset, gparam
using OpenTIMES.Reference: ispass
import TOML

@testset "prep -> prelv: ppmain.mod L461-611 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prep"); switches=fx["switches"])
    foreach(f -> f(tm), (preppm_shape!, ppmain_topo!, ppmain_tslvl!, ppmain_life!))
    names = ppmain_life_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_prelv")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(r) == 30 && all(ispass, r)
    # OBJ MOD: %CTST% is **0, so G_ILEDNO is -1; RVP is cleared (L524, L552)
    @test gparam(tm, "G_ILEDNO").values[()] == -1.0 && isempty(gset(tm, "RVP").keys)
end

include("preppm_case.jl")
include("prep_ext_case.jl")
include("ppmain_topo_case.jl")
include("ppmain_tslvl_case.jl")
include("ppmain_life_case.jl")

@testset "ppmain.mod L461-611 against GAMS on crafted states" begin
    for name in PPMAIN_LIFE_CASES
        tm = ppmain_life_start(FIXTURES, name)
        foreach(f -> f(tm), (ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, prep_ext!, preppm_shape!, ppmain_topo!,
                             ppmain_tslvl!, ppmain_life!))
        r = layer1(tm, DumpData(joinpath(FIXTURES, "ppmain_life_unit_gams", name)), PPMAIN_LIFE_OUTPUTS)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        v(n) = gparam(tm, n).values
        m(n) = gset(tm, n).members
        k(y, p) = ("REG1", y, p)
        if name == "life"
            # L465-476: a lifetime below 0.5 or EPS is set to 1; 0.7 is kept
            tl = v("NCAP_TLIFE")
            @test tl[k("2015", "COTEBIO")] == 1.0 && tl[k("2015", "COTECOA")] == 0.7 && tl[k("2020", "COTEELC")] == 1.0
            # L485: a host's own option 2 lifts a refit's 3 to 4 and is itself removed; L487: ELIFE from TLIFE for option -5
            @test v("PRC_REFIT") == Dict(("REG1", "COTEBIO", "CSHEBIO") => -5.0, ("REG1", "COTECOA", "CSHECOA") => 4.0,
                                        ("REG1", "COTEGAS", "CSHEGAS") => 1.0)
            @test v("NCAP_ELIFE")[k("2015", "CSHEBIO")] == 15.0
            # L526-531: an upper bound below the residual capacity becomes RCAP_BND 'N'; L536: an INF lower bound is removed
            @test haskey(v("RCAP_BND"), ("REG1", "2015", "ELCTECOA00", "N")) && !haskey(v("CAP_BND"), ("REG1", "2015", "ELCTECOA00", "UP"))
            @test !haskey(v("CAP_BND"), ("REG1", "2030", "CAPEELC", "LO")) && k("2030", "CSHEGAS") in m("RTP_VARP")
            # L546-550: FX EPS on every milestone takes the later periods out of RTP; L558-565: PRC_AOFF
            @test !(k("2030", "COTEOIL") in m("RTP")) && !(k("2015", "COTEGAS") in m("RTP_VARA")) && k("2010", "COTEGAS") in m("RTP_VARA")
            # L575-581: PRC_FOFF at ANNUAL and at S; L593: a flow flagged non-interpolated leaves the PG
            @test ("REG1", "2030", "ELCTECOA00", "ELC", "S") in m("RTPCS_OUT") && !(("REG1", "2030", "ELCTECOA00", "ELC", "W") in m("RTPCS_OUT"))
            @test !(("REG1", "ELCTEGAS00", "ELCGAS") in m("RPC_PG")) && ("REG1", "ELCTEGAS00", "ELC") in m("RPC_PG")
        elseif name == "altobj"
            # L500-501: no lead time, TLIFE 3 in a period of 5: two investments
            @test v("COEF_RPTI")[k("2015", "COTEGAS")] == 2.0
        else
            # %CTST% empty: G_ILEDNO 10; a lead time below a tenth of the period is dropped, 1.4 is rounded
            @test gparam(tm, "G_ILEDNO").values[()] == 10.0 && v("NCAP_ILED")[k("2010", "CSHEBIO")] == 1.0 && !haskey(v("NCAP_ILED"), k("2015", "COTECOA"))
            # L518 (VALIDATE): every vintage transfers to its own period; L590: the milestone before a simulated vintage
            @test count(x -> x[2] == x[3], m("RTP_CPTYR")) > 1000 && m("NO_RVP") == Set([("REG1", "2005", "ELCTNGAS01")])
        end
    end
end
