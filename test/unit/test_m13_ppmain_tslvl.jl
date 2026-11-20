# M1.3 (7b): ppmain.mod L329-460 (v4.9.7), the commodity and process
# timeslice levels. Layer 1 on TIMES_Demo demo12 reduce_off from the prep
# checkpoint, compared at the prelv checkpoint on the symbols the step
# settles (scripts/m13_probe.jl does the same on the core reference runs), and
# on crafted states against GAMS running ppmain.mod L1-247 and L249-460,
# preppm.mod L1-212 and L218-252 and prep_ext.vda itself.

using OpenTIMES: TimesModel, DumpData, layer1, ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, prep_ext!, preppm_shape!,
             ppmain_topo!, ppmain_tslvl!, ppmain_tslvl_symbols, gset, gparam
using OpenTIMES.Reference: ispass
import TOML

@testset "prep -> prelv: ppmain.mod L329-460 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prep"); switches=fx["switches"])
    foreach(f -> f(tm), (preppm_shape!, ppmain_topo!, ppmain_tslvl!))
    names = ppmain_tslvl_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_prelv")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(r) == 24 && all(ispass, r)
    # L385-388: COM_PEAK of ELC without COM_PKTS takes the DAYNITE timeslices
    @test Set(k[3] for k in gset(tm, "COM_PKTS").keys if k[1] == "REG1") == Set(["SD", "SN", "WD", "WN"])
end

include("preppm_case.jl")
include("prep_ext_case.jl")
include("ppmain_topo_case.jl")
include("ppmain_tslvl_case.jl")

@testset "ppmain.mod L329-460 against GAMS on crafted states" begin
    for name in PPMAIN_TSLVL_CASES
        tm = ppmain_tslvl_start(FIXTURES, name)
        foreach(f -> f(tm), (ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, prep_ext!, preppm_shape!, ppmain_topo!,
                             ppmain_tslvl!))
        r = layer1(tm, DumpData(joinpath(FIXTURES, "ppmain_tslvl_unit_gams", name)), PPMAIN_TSLVL_OUTPUTS)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        m(n) = gset(tm, n).members
        if name == "levels"
            # L336: WEEKLY (not a REG1 level) moved to SEASON; L337: ELCNENUC00 already at SEASON, nothing added, so WEEKLY stays
            @test ("REG1", "COMGAS", "SEASON") in m("COM_TSL") && !(("REG1", "COMGAS", "WEEKLY") in m("COM_TSL"))
            @test ("REG1", "ELCNENUC00", "WEEKLY") in m("PRC_TSL") && gparam(tm, "F").values[()] == 1.0
            # L343 (G30): the first timeslice sets the level; L346: a timeslice off the level is removed
            @test ("REG1", "COMCOA", "SEASON") in m("COM_TSL") && ("REG1", "COMCOA", "SD") in m("COM_TS") && !(("REG1", "AGRELC", "S") in m("COM_TS"))
            # L347, L458: timeslices left out of COM_TS get no flow variables
            @test !any(k -> k[1] == "REG1" && k[3] == "RSDELC" && k[4] in ("SN", "W", "WD", "WN"), m("RPCS_VAR"))
            # L394-395: PRC_TS sets the level; no level is ANNUAL
            @test ("REG1", "COTEGAS", "SEASON") in m("PRC_TSL") && ("REG1", "COTECOA", "ANNUAL") in m("PRC_TSL")
        else
            # L358-363: COM_OFF switches off 2015, 2020 and 2050 for COMGAS, with EPS FX bounds on its timeslices
            @test !(("REG1", "2020", "COMGAS") in m("RTC")) && ("REG1", "2030", "COMGAS") in m("RTC")
            @test gparam(tm, "COM_BNDPRD").values[("REG1", "2015", "COMGAS", "S", "FX")] == 0.0
            # L383: COM_PKTS moved to the commodity's level, up and down; L380: a commodity outside RC gets a level
            @test Set(k[3] for k in m("COM_PKTS") if k[2] == "ELC" && k[1] == "REG1") == Set(["SD", "SN"])
            @test ("REG1", "COMGAS", "S") in m("COM_PKTS") && ("REG1", "ACT", "DAYNITE") in m("COM_TSL")
            # L448: an ANNUAL storage flow; L449-450: an ANNUAL night-storage record replaced by the shadow-level timeslices
            @test ("REG1", "COTEBIO", "DCOT", "ANNUAL") in m("RPCS_VAR")
            @test !(("REG1", "CAPEELC", "ANNUAL") in m("PRC_NSTTS")) && ("REG1", "CAPEELC", "SN") in m("PRC_NSTTS")
            @test ("REG1", "CSHEELC") in m("RP_SGS") && !(("REG1", "CSHEBIO") in m("RP_STG"))
        end
    end
end
