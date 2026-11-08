# M1.3 (6a): preppm.mod L1-212 (v4.9.7), the interpolation of user data.
# Layer 1 on TIMES_Demo demo12 reduce_off from the init checkpoint (after
# ppmain_head!, ppmain_years!, timslice! and ppmain_rtp!), compared at the prep
# checkpoint on the symbols the block settles (scripts/m13_probe.jl does the
# same on the core reference runs), and on crafted states against GAMS
# running ppmain.mod L1-247 and preppm.mod L1-212 itself.

using TIMES: TimesModel, DumpData, layer1, ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, preppm_symbols, gset, gparam
using TIMES.Reference: ispass
import TOML

@testset "preppm.mod L1-212 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_init"); switches=fx["switches"])
    foreach(f -> f(tm), (ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!))
    names = preppm_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_prep")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(names) == 109 && all(ispass, r)
    # L192: FLO_SHAR's default option is 10 (no interpolation); fillvint.gms L18 and L61: RVP of the vintaged ELCTNGAS01
    @test ("REG1", "2005", "ELCTNGAS01") in gset(tm, "RVP").members
end

include("preppm_case.jl")

@testset "preppm.mod L1-212 against GAMS on crafted states" begin
    for name in PREPPM_CASES
        tm = preppm_start(FIXTURES, name)
        foreach(f -> f(tm), (ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!))
        # with G_NOINTERP no macro runs, so Z and MY_F keep what ppmain.mod L215 and timslice.mod L71-77 left,
        # scratch that ppmain_rtp! and timslice! do not keep
        outs = name == "nointerp" ? filter(n -> !(n in ("Z", "MY_F")), PREPPM_OUTPUTS) : preppm_outputs(name)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "preppm_unit_gams", name)), outs)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        v(n) = gparam(tm, n).values
        if name == "fill_opts"
            a = v("NCAP_AFA")
            ka(y, p) = ("REG1", y, p, "LO")
            # default: linear between 2008 and 2025, constant outside, on RTP years only (2004 is a past year of COTEBIO)
            @test a[ka("2010", "COTEBIO")] == 0.2 + (0.6 - 0.2) / (2025 - 2008) * (2010 - 2008)
            @test a[ka("2004", "COTEBIO")] == 0.2 && a[ka("2050", "COTEBIO")] == 0.6 && !haskey(a, ka("1980", "COTEBIO"))
            # exponential beyond 2020: data after it are growth rates, overwritten with the levels they give
            g = 0.6 * 1.02^15
            @test a[ka("2010", "CSHEOIL")] ≈ 0.55 && a[ka("2030", "CSHEOIL")] ≈ g && a[ka("2050", "CSHEOIL")] ≈ g * 1.01^15
            # option 2 without data: EPS on every RTP year; option -1: left alone and kept, other options reset
            @test a[ka("2010", "ELCRESOL00")] == 0.0 && a[ka("0", "COTECOA")] == -1 && !haskey(a, ka("2015", "COTECOA"))
            @test !haskey(a, ka("0", "COTEOIL")) && !haskey(a, ka("2010", "ELCREWIN00"))
        elseif name == "prep_opts"
            b = v("ACT_BND")
            kb(y, p) = ("REG1", y, p, "ANNUAL", "LO")
            # default 10: 2008 and 2012 lie in the period of 2010, 2027 in that of 2030; 2050 has its own data
            @test b[kb("2010", "FTE-AGRBIO")] == 2.0 && b[kb("2030", "FTE-AGRBIO")] == 5.0 && b[kb("2050", "FTE-AGRBIO")] == 8.0
            @test !haskey(b, kb("2015", "FTE-AGRBIO"))
            # 15: the first period takes the first value (MIYR_1 rule), forward extrapolation only
            @test b[kb("2005", "FTE-COMCOA")] == 2.0 && b[kb("2030", "FTE-COMCOA")] == 4.0 && b[kb("2050", "FTE-COMCOA")] == 4.0
            # -13: the milestones' data deleted, an EPS one too (`UNCD7 $= %1` counts EPS, G24)
            @test !haskey(b, kb("2010", "FTE-COMGAS")) && !haskey(b, kb("2020", "FTE-COMGAS")) && b[kb("2012", "FTE-COMGAS")] == 3.0
            # L211: the PASTMILE pass interpolates 2004 between 1980 and the 2010 value L192 moved there
            @test v("FLO_SHAR")[("REG1", "2004", "CAPEELC", "COMELC", "COMELC", "ANNUAL", "LO")] ≈ 0.3 + 0.2 / 30 * 24
            # L32: the diagonal PRC_MARK goes when FLO_MARK has an option above 1; L31: FLO_MARK without the flow goes
            pm = v("PRC_MARK")
            @test !haskey(pm, ("REG1", "2015", "ELCTNOIL01", "ELCTNOIL01", "ELC", "LO")) && haskey(pm, ("REG1", "2015", "ELCTNOIL01", "ELCTNOIL01", "ELC", "UP"))
            @test !any(k -> k[3] == "CSHEELC", keys(v("FLO_MARK")))
            # DAM_COST (%7 EPS): interpolated and extrapolated; its EPS and 2 options reset
            d = v("DAM_COST")
            @test d[("REG1", "2020", "TOTCO2", "MEuro05")] == 15.0 && !haskey(d, ("REG1", "0", "ELCCO2", "MEuro05"))
            # cost option 5: forward extrapolation, EPS before the first data year (L68)
            c = v("NCAP_COST")
            @test c[("REG1", "2050", "COTEBIO", "MEuro05")] == 200.0 && c[("REG1", "2005", "COTEBIO", "MEuro05")] == 0.0
        elseif name == "costs_uc_ret"
            @test v("OBJ_COMNT")[("REG1", "2010", "DAOT", "ANNUAL", "SUB", "MEuro05")] == -2.0
            @test !haskey(v("OBJ_COMNT"), ("REG1", "2003", "DAOT", "ANNUAL", "COST", "MEuro05"))
            uc = v("UC_COM")
            @test uc[("UC_RNW-PP_LOW", "NET", "LHS", "REG1", "2020", "ELC", "ANNUAL", "COMCON")] == -0.5
            @test haskey(uc, ("UC_RNW-PP_LOW", "NET", "LHS", "REG1", "2020", "ELC", "ANNUAL", "COMPRD")) &&
                  !haskey(uc, ("UC_RNW-PP_LOW", "PRD", "LHS", "REG1", "2020", "ELC", "ANNUAL", "COMPRD"))
            # L51-52: tax and subsidy on one flow get the option 3, reset after the interpolation
            ft = v("FLO_TAX")
            @test ft[("REG1", "2015", "ELCTNOIL01", "ELC", "ANNUAL", "MEuro05")] == 1.25 && !haskey(ft, ("REG1", "0", "ELCTNOIL01", "ELC", "ANNUAL", "MEuro05"))
            # prepret.dsc: PRC_RCAP from RCAP_BND, the 'N' option, the refit host and the negative refit
            rc = gset(tm, "PRC_RCAP").members
            @test all(p -> ("REG1", p) in rc, ["COTEBIO", "COTECOA", "COTEELC", "COTNOIL1"])
            @test v("NCAP_ILED")[("REG1", "2015", "COTNELC1")] == -1.0 && isempty(gset(tm, "PRC_CAP").keys)
            @test !any(k -> k[3] == "COTEGAS", keys(v("RCAP_OCAP")))
        elseif name == "curex"
            # curex.gms L21-26: MUSD (one target) leaves RDCUR, MGBP (two targets in REG1) is mapped nowhere there
            @test gset(tm, "RDCUR").members == Set([("REG1", "MEuro05"), ("REG2", "MEuro05")])
            cm = gset(tm, "CURMAP").members
            @test ("REG1", "MEuro05", "MUSD") in cm && !any(k -> k[1] == "REG1" && "MGBP" in k, cm) && ("REG2", "MEuro05", "MGBP") in cm
            # L29-32: MJPY -> MUSD -> MEuro05 chained in REG1 (RXX), not in REG2 (MUSD has no discount rate there)
            rx = v("R_CUREX")
            @test gset(tm, "RXX").members == Set([("REG1", "MUSD", "MJPY")]) && rx[("REG1", "MJPY", "MEuro05")] ≈ 0.007 * 0.9
            @test ("REG1", "MEuro05", "MJPY") in cm && !(("REG1", "MUSD", "MJPY") in cm) && rx[("REG1", "MEuro05", "MEuro05")] == 1.0
            # L77-81 (temporary attribute): summed per target, the option record carried over, an option -13 series gone,
            #   EPS kept, MGBP dropped in REG1; REG2's own rate (preppm.mod L27 leaves it); only RDCUR currencies remain
            c = v("NCAP_COST")
            @test c[("REG1", "2010", "COTEBIO", "MEuro05")] ≈ 100 + 50 * 0.9 && c[("REG1", "2010", "COTEGAS", "MEuro05")] ≈ 1000 * 0.0063
            @test !any(k -> k[3] in ("COTECOA", "COTEELC"), keys(c)) && c[("REG1", "2010", "COTEOIL", "MEuro05")] == 0.0
            @test c[("REG2", "2010", "ELCTEGAS00", "MEuro05")] ≈ 20 * 1.15 && c[("REG2", "2020", "ELCTEGAS00", "MEuro05")] ≈ 10 * 0.8
            @test all(k -> k[4] == "MEuro05", keys(c))
            # L81-82 (no temporary attribute): the MEuro05 record plus the converted one; MGBP outside RDCUR removed
            @test v("ACT_CSTUP")[("REG1", "2010", "ELCTEGAS00", "DAYNITE", "MEuro05")] ≈ 1 + 10 * 0.9
            @test !any(k -> k[5] != "MEuro05", keys(v("ACT_CSTUP"))) && v("REG_BNDCST")[("REG2", "2020", "INV", "MEuro05", "UP")] ≈ 50 + 100 * 1.15
            # preppm.mod L34 reads the converted COM_CSTNET
            @test v("OBJ_COMNT")[("REG1", "2010", "DAOT", "ANNUAL", "COST", "MEuro05")] ≈ 1 + 10 * 0.9
        else
            # G_NOINTERP: no interpolation, no option reset; prepparm clears its parameter from INT_DEFAULT
            @test v("NCAP_AFA")[("REG1", "0", "COTEGAS", "LO")] == 2.0 && !haskey(v("NCAP_AFA"), ("REG1", "2015", "COTEGAS", "LO"))
            @test !(("ACT_BND",) in gset(tm, "INT_DEFAULT").members)
        end
    end
end
