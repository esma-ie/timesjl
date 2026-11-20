# M1.3 (7a): preppm.mod L218-252 (v4.9.7) with preshape.gms, and ppmain.mod
# L249-328, the start of the prep -> prelv segment. Layer 1 on TIMES_Demo
# demo12 reduce_off from the prep checkpoint, compared at the prelv checkpoint
# on the symbols the two steps settle (scripts/m13_probe.jl does the same on
# the core reference runs), and on crafted states against GAMS running
# ppmain.mod L1-247 and L249-328, preppm.mod L1-212 and L218-252 and
# prep_ext.vda itself.

using OpenTIMES: TimesModel, DumpData, layer1, ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, prep_ext!, preppm_shape!,
             preppm_shape_symbols, preppm_shape_unported, ppmain_topo!, ppmain_topo_symbols, gset, gparam
using OpenTIMES.Reference: ispass
import TOML

@testset "prep -> prelv: preppm.mod L218-252, ppmain.mod L249-328 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prep"); switches=fx["switches"])
    preppm_shape!(tm)
    ppmain_topo!(tm)
    names = vcat(preppm_shape_symbols(tm), ppmain_topo_symbols(tm))
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_prelv")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(r) == 39 && all(ispass, r)
    # L263: EACHYEAR runs to MIYR_VL+DUR_MAX; L266: PERIODYR of the last period takes the years after it
    @test ("2052",) in gset(tm, "EACHYEAR").members && ("2050", "2060") in gset(tm, "PERIODYR").members
end

include("preppm_case.jl")
include("prep_ext_case.jl")
include("ppmain_topo_case.jl")

const TOPO_STEPS = (ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, prep_ext!, preppm_shape!, ppmain_topo!)

@testset "preshape.gms and ppmain.mod L249-328 against GAMS on crafted states" begin
    for name in PPMAIN_TOPO_CASES
        tm = ppmain_topo_start(FIXTURES, name)
        foreach(f -> f(tm), TOPO_STEPS)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "ppmain_topo_unit_gams", name)), PPMAIN_TOPO_OUTPUTS)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        v(n) = gparam(tm, n).values
        m(n) = gset(tm, n).members
        if name == "shapes"
            afx = v("NCAP_AFX")
            k(y, p) = ("REG1", y, p)
            # default 10: the earlier of two data years in a period wins; a milestone with data keeps it
            @test afx[k("2010", "COTEBIO")] == 2.0 && afx[k("2015", "COTEBIO")] == 6.0 && afx[k("2030", "COTEBIO")] == 4.0
            # option 1: a step, no extrapolation; -1 (MOD keeps the sign, G43) the same
            @test afx[k("2030", "COTECOA")] == 3.0 && afx[k("2015", "COTEELC")] == 1.0 && !haskey(afx, k("2030", "COTEELC"))
            # option 3: the first value back as given, the last forward rounded
            @test afx[k("2004", "COTEGAS")] == 2.0 && afx[k("2050", "COTEGAS")] == 5.0
            # option 2 without data: EPS over RTP; 15: one period back (2015 from 2016) and on to the end
            @test afx[k("2004", "ELCTEOIL00")] == 0.0 && afx[k("2015", "CAPEELC")] == 2.0 && afx[k("2050", "CAPEELC")] == 4.0
            # a value that rounds to 0 and an EPS data year restart the step; no RTP, no extrapolation
            @test afx[k("2020", "CSHEGAS")] == 3.0 && !haskey(afx, k("2010", "CSHEGAS")) && !haskey(afx, k("2005", "CSHNOIL1"))
            @test m("RXX") == Set([("REG1", "0", "CAPEELC"), ("REG1", "0", "CSHEBIO")]) && isempty(gset(tm, "UNCD7").keys)
            @test v("PRC_MARK")[("REG1", "2030", "ELCTEGAS00", "ELCTEGAS00", "ELC", "UP")] == 0.0
        else
            # L272-277: a group named like a commodity of RC takes the commodity out of RC and RPC
            @test !(("REG1", "AGRELC") in m("RC")) && !any(x -> x[1] == "REG1" && x[3] == "AGRELC", m("RPC"))
            # L301: a trade process keeps in its PG only what it trades
            @test ("REG1", "IMPELC1", "COMBIO") in m("RPC") && !(("REG1", "IMPELC1", "COMBIO") in m("RPC_PG"))
            # L309, L317-318: a user shadow group is kept; a material process with a demand PG gets MAT
            @test ("REG1", "ELCTECOA00", "ELCCOA") in m("RPC_SPG") && !(("REG1", "ELCTECOA00", "NRG") in m("PRC_SPG"))
            @test ("REG1", "COTEBIO", "MAT") in m("PRC_SPG") && ("REG1", "COTEBIO", "AGRBIO") in m("RPC_SPG")
            # L291-294: cancelling NCAP_ICOM and NCAP_OCOM give no capacity flow; a flow outside RC adds it
            @test !any(x -> x[3] == "CSHEBIO", m("RPC_CAPFLO")) && ("REG1", "ACT") in m("RC") && ("REG1", "CAPEELC", "ACT") in m("RPC_NOFLO")
        end
    end
end

@testset "preppm.mod L218-252: refused paths" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prep"); switches=fx["switches"])
    @test isempty(preppm_shape_unported(tm))
    t = TimesModel(joinpath(FIXTURES, "demo12_off_prep"); switches=merge(fx["switches"], Dict("VINTOPT" => "1")))
    @test any(s -> occursin("L245-251", s), preppm_shape_unported(t))
end
