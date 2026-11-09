# M1.3 (6b): preppm.mod L213-217 (v4.9.7), prep_ext.vda with equcrtp.vda
# PREP_EXT, the end of the init -> prep segment. Layer 1 on TIMES_Demo demo12
# reduce_off from the init checkpoint through every translated step, compared
# at the prep checkpoint on every set and parameter (scripts/m13_probe.jl does
# the same on the core reference runs), and on crafted states against GAMS
# running ppmain.mod L1-247, preppm.mod L1-212 and prep_ext.vda itself.

using TIMES: TimesModel, DumpData, layer1, ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, prep_ext!, prep_ext_symbols,
             prep_ext_unported, gset, gparam
using TIMES.Reference: ispass
import TOML

const PREP_STEPS = (ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, prep_ext!)

@testset "init -> prep segment layer 1 (every symbol), TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_init"); switches=fx["switches"])
    foreach(f -> f(tm), PREP_STEPS)
    names = prep_ext_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_prep")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(names) == 824 && all(ispass, r)
    @test "PUTOUT" in names && "MY_SUM" in names                  # the QA-log scalars too (M1.3 change 25b-1)
    # L49-68: every demo12 process has a '0' record and one data year: the one-point run-down over its lifetime
    @test ("REG1", "2004", "2005", "CAPEELC") in gset(tm, "RTP_CPTYR").members && isempty(gset(tm, "TRACKP").keys)
end

include("preppm_case.jl")
include("prep_ext_case.jl")

@testset "prep_ext.vda against GAMS on crafted states" begin
    for name in PREP_EXT_CASES
        tm = prep_ext_start(FIXTURES, name)
        foreach(f -> f(tm), PREP_STEPS)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "prep_ext_unit_gams", name)), PREP_EXT_OUTPUTS)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        v(n) = gparam(tm, n).values
        m(n) = gset(tm, n).members
        if name == "vda_resid"
            res = v("PRC_RESID")
            kr(y, p) = ("REG1", y, p)
            # several points, no option: interpolated, nothing past the last data year
            @test res[kr("2020", "COTEBIO")] ≈ 6 - 4 / 15 * 5 && !haskey(res, kr("2050", "COTEBIO"))
            # option 5: constant to the end of the lifetime from the first year (2005+10), then run down from the last (2015)
            @test res[kr("2020", "COTECOA")] == 40.0 && !haskey(res, kr("2030", "COTECOA")) && v("PRC_YMAX")[("REG1", "COTECOA")] == 5.0
            # one point, no NCAP_TLIFE at PYR_S: run down over G_TLIFE (10); the '0' record becomes the lifetime
            @test res[kr("2015", "CSHNOIL1")] == 2.5 && res[kr("0", "CSHNOIL1")] == 10.0
            # a year as the '0' value: RTP_CPTYR up to it without residual capacity there
            @test ("REG1", "2004", "2030", "ELCTECOA00") in m("RTP_CPTYR") && !haskey(res, kr("2030", "ELCTECOA00"))
            # L13: NCAP_AFAC replaces NCAP_AFC('ANNUAL') on DATAYEAR; L25: an option -1 off ACT is skipped
            afc = v("NCAP_AFC")
            @test afc[("REG1", "2015", "COTEBIO", "ACT", "ANNUAL")] ≈ 0.725 && isempty(gparam(tm, "NCAP_AFCS").keys)
            @test !haskey(afc, ("REG1", "2015", "CSHEGAS", "NRG", "ANNUAL"))
            # L19: a group without a positive ACT_EFF in BOHYEAR is a single-flow ACT_EFF group
            @test ("REG1", "CAPEELC", "COMELC", "COMELC") in m("RPG_1ACE") && ("REG1", "CSHEELC", "COMELC", "COMELC") in m("RPG_1ACE")
            # L21: the last year of VDA_FLOP on a STOA timeslice; a group and ANNUAL left out
            @test v("ACT_FLO") == Dict(("REG1", "0", "CSHEELC", "COMELC", "S") => 0.5)
            # L44: FLO_FUNCX kept only for vintaged processes and groups
            fx_ = v("FLO_FUNCX")
            @test !haskey(fx_, ("REG1", "2010", "COTEGAS", "COMGAS", "COMCO2")) && haskey(fx_, ("REG1", "2010", "ELCTNGAS01", "ELCGAS", "ELCCO2")) &&
                  haskey(fx_, ("REG1", "2010", "COTEGAS", "NRG", "COMCO2"))
        elseif name == "uc_bounds"
            @test v("ACT_MINLD")[("REG1", "2015", "ELCTEGAS00")] == 0.325
            cl = m("COM_LIM")
            @test ("REG1", "DAOT", "FX") in cl && !(("REG1", "DAOT", "LO") in cl) && ("REG1", "ELC", "LO") in cl
            @test ("REG1", "2010", "COTEBIO", "COMBIO") in m("RPC_CAPFLO")
            @test length(v("FLO_ASHAR")) == 2 && haskey(v("FLO_ASHAR"), ("REG1", "2010", "COTEGAS", "COMGAS", "DCOT", "ANNUAL", "LO"))
            # L80-83: the 'N' year sets the lead time from B(T); two years of one period are summed and rounded back
            @test v("NCAP_ILED")[("REG1", "2010", "COTEGAS")] == 5.0 && v("COEF_ILED")[("REG1", "2010", "COTEGAS")] == 1002.0
            @test v("NCAP_BND")[("REG1", "2015", "COTECOA", "N")] == 2016.0 && v("NCAP_ILED")[("REG1", "2015", "COTECOA")] == 4.0
            @test !haskey(v("NCAP_BND"), ("REG1", "2010", "COTEGAS", "UP"))
        else
            dy = v("PRC_DYNUC")
            k(u, s, y, p, g, bd) = (u, s, "REG1", y, p, g, bd)
            a, b = "AU_NUC_MaxCAP", "UC_RNW-PP_LOW"
            # L57: no growth equation in the first period of a process that starts in 2010
            @test !haskey(dy, k(a, "RHS", "2010", "CSHNOIL1", "CAP", "UP")) && haskey(dy, k(a, "RHS", "2010", "ELCNENUC00", "CAP", "UP"))
            # L51-52: an RHS-only NCAP bound gets no LHS; an ACT one gets 1
            @test !any(x -> x[1] == a && x[2] == "LHS" && x[5] == "ELCREWIN00", keys(dy)) && dy[k(a, "LHS", "2015", "ELCREBIO00", "ACT", "LO")] == 1.0
            # option 15 on the RHS: interpolated between 2012 and 2027
            @test dy[k(b, "RHS", "2020", "ELCTECOA00", "ACT", "UP")] ≈ 8 + 8 / 15
            @test m("UC_T_SUCC") == Set([("REG1", a, "0"), ("REG2", a, "0")])
        end
    end
end

@testset "preppm.mod L213-217: refused paths" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_init"); switches=fx["switches"])
    @test isempty(prep_ext_unported(tm))
    for (sw, line) in (("STAGES", "L214"), ("POWERFLO", "L37"), ("WAVER", "L63"), ("ETL", "ETL"))
        t = TimesModel(joinpath(FIXTURES, "demo12_off_init"); switches=merge(fx["switches"], Dict(sw => "YES")))
        @test any(s -> occursin(line, s), prep_ext_unported(t))
    end
    t = TimesModel(joinpath(FIXTURES, "demo12_off_init"); switches=merge(fx["switches"], Dict("VINTOPT" => "1")))
    @test any(s -> occursin("L42-43", s), prep_ext_unported(t))
end
