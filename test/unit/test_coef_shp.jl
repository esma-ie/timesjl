# M1.2 (6): coef_shp.mod L10-37, L43-74 (v4.9.7). Layer 1 on TIMES_Demo
# demo12 against its coef dump (no shaping data there: OPYEAR, Z and the
# cleared work symbols), and on two crafted states against coef_shp.mod run
# by GAMS itself (scripts/make_coef_shp_unit.jl): FLO_FUNCX shapes incl. the
# removed indexes, lead-time rounding, repeated investments and the
# non-vintaged FLO_FUNC ratios; NCAP_CPX shapes rescaling COEF_CPT.

using TIMES: TimesModel, DumpData, coef_shp!, coef_shp_unported, coef_obj!, coef_alt!, later_overwrites, layer1, gparam,
             gset, gput!, gvalues, iseps, UnportedError, ShapeTable, shape
using TIMES.Reference: ispass

isdefined(@__MODULE__, :PPM_DEMO12) || (const PPM_DEMO12 = joinpath(FIXTURES, "demo12_off_ppm"))
isdefined(@__MODULE__, :COEF_DEMO12) || (const COEF_DEMO12 = joinpath(FIXTURES, "demo12_off_coef"))
include("coef_obj_case.jl")
include("coef_shp_case.jl")

@testset "coef_shp layer 1, TIMES_Demo demo12" begin
    tm = coef_obj_start(PPM_DEMO12; switches=COEF_SHP_CASE_SWITCHES)
    coef_obj!(tm); coef_alt!(tm)
    @test isempty(coef_shp_unported(tm))
    coef_shp!(tm)
    r = layer1(tm, DumpData(COEF_DEMO12), COEF_SHP_OUTPUTS; exclude=later_overwrites(tm))
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test all(ispass, r)
    # L12: lifetimes up to the longest period (20 years in demo12): 20*21/2 pairs
    @test length(gset(tm, "OPYEAR")) == 210 && ("20", "20") in gset(tm, "OPYEAR") && !(("21", "1") in gset(tm, "OPYEAR"))
    # L51: Z is left at CARD(J)/2+1
    @test gparam(tm, "Z")[()] == 500.5
    # L74: the work symbols are cleared, PRC_YMIN and PRC_YMAX among them (coef_obj.mod L153 had done so too)
    @test all(isempty(gparam(tm, n)) for n in ("PRC_YMIN", "PRC_YMAX", "RVPRL", "COEF_CAP", "RTP_CPX"))
    @test all(isempty(gset(tm, n)) for n in ("TRACKP", "RP_GRP", "RTP_CGC", "RTP_CAPYR"))
end

@testset "coef_shp against GAMS on crafted states" begin
    # SHAPE(J+(x-1),AGE+(a)) from AGEJ ('1','1'): row x at age a+1, 0 outside the table, leads rounded (G29)
    tm = coef_shp_start(PPM_DEMO12, "ptran")
    tab = ShapeTable(tm)
    sh(x, a) = Float64(shape(tab, x, a))
    @test sh(2, 0) == 1.0 && sh(2, 9) ≈ 0.91 && sh(2.5, 1) ≈ 1.02 && sh(3, 1) ≈ 1.02
    @test iszero(shape(tab, 2, 40)) && iszero(shape(tab, 2, -1)) && iszero(shape(tab, 1000, 0)) && iszero(shape(tab, 0, 0))
    for name in COEF_SHP_CASES
        tm = coef_shp_start(PPM_DEMO12, name)
        @test isempty(coef_shp_unported(tm))
        cpt0 = copy(gparam(tm, "COEF_CPT").values)
        coef_shp!(tm)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "coefshp_unit_gams", name)), COEF_SHP_OUTPUTS)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        k(v, t, p) = ("REG1", v, t, p)
        kf(v, t, p) = ("REG1", v, t, p, "NRG", "ELC")
        if name == "ptran"
            ffx = gparam(tm, "FLO_FUNCX")
            # L17: 1, 1000, -1 and the 'ACT' row at a vintage removed; the year-'0' row (outside RTP) kept
            @test length(ffx) == 9 && haskey(ffx, ("REG1", "0", "ELCTECOA00", "ACT", "ELC"))
            @test !any(x -> x[3] == "ELCTECOA00" && x[5] == "ELCCO2", keys(ffx.values)) && !haskey(ffx, ("REG1", "2015", "ELCTNGAS01", "NRG", "ELC"))
            # L19-20: TRACKP through PRC_VINT (ELCTNGAS01) or a 'CAPFLO' row (ELCTECOA00, COTNCOA1); RTP_CAPYR = their RTP_CPTYR
            capyr = gset(tm, "RTP_CAPYR")
            @test Set(x[4] for x in capyr.keys) == Set(["ELCTNGAS01", "ELCTECOA00", "COTNCOA1"])
            @test Set(capyr.keys) == Set(x for x in gset(tm, "RTP_CPTYR").keys if x[1] == "REG1" && x[4] in ("ELCTNGAS01", "ELCTECOA00", "COTNCOA1"))
            fx = gparam(tm, "RTP_FFCX")
            @test length(fx) == 16 && !any(x -> x[5] == "CAPFLO", keys(fx.values))              # L43
            # L25-31: ELCTNGAS01 2010 with NCAP_ILED 2.4 starts in B(2010)+2 = 2010 (rounded lead): over the
            # period 2008-2012 the years before the start read age 0 and below (no shape, 0), 2010-2012 read
            # ages 1-3 of row '2' (1, 0.99, 0.98), divided by the 3 operating years: 0.99 - 1
            @test fx[kf("2010", "2010", "ELCTNGAS01")] ≈ -0.01
            @test fx[kf("2010", "2015", "ELCTNGAS01")] ≈ -0.05 && fx[kf("2010", "2030", "ELCTNGAS01")] ≈ -0.225
            # the past vintage 2004 of ELCTECOA00 with index 2.5 reads row '3' (rising): positive factors
            @test fx[kf("2004", "2005", "ELCTECOA00")] ≈ 0.04 && fx[kf("2004", "2030", "ELCTECOA00")] ≈ 0.51
            # L34-36: COTNCOA1 (life 15, COEF_RPTI 2 at 2050): the lifetime average of row '2' is 0.93
            @test fx[kf("2050", "2050", "COTNCOA1")] ≈ -0.07
            # ELCTNGAS01 2030 with COEF_RPTI forced to 2 and life 30: RVPRL 29 + 1 exceeds Z = 20, OPYEAR is empty, factor -1
            @test fx[kf("2030", "2030", "ELCTNGAS01")] == -1.0 && fx[kf("2030", "2050", "ELCTNGAS01")] == -1.0
            # L45: the non-vintaged option on the -1 row: FLO_FUNC(T)/FLO_FUNC(V) - 1 at the RTP_VINTYR years; 0 at V itself
            @test fx[kf("2015", "2020", "ELCTNGAS01")] ≈ 0.1 && fx[kf("2015", "2050", "ELCTNGAS01")] ≈ 0.3
            @test !haskey(fx, kf("2015", "2015", "ELCTNGAS01"))
            @test gparam(tm, "COEF_CPT").values == cpt0                        # no NCAP_CPX: COEF_CPT untouched
        else
            cpx = gparam(tm, "NCAP_CPX")
            @test length(cpx) == 6 && !haskey(cpx, ("REG1", "2005", "ELCTECOA00")) && !haskey(cpx, ("REG1", "2010", "ELCTECOA00"))
            rcpx, cpt = gparam(tm, "RTP_CPX"), gparam(tm, "COEF_CPT")
            # L71-74: RTP_CPX(R,V,P,T) holds the factor COEF_CPT was multiplied by, plus one, minus one
            @test length(rcpx) == 12
            for (x, f) in rcpx.values
                kk = (x[1], x[2], x[4], x[3])
                @test isapprox(get(cpt.values, kk, 0.0), cpt0[kk] * (f + 1); atol=1e-12)
            end
            # a declining shape (row '2') lowers COEF_CPT; a rising one (row '3', ELCTNGAS01 2015, COTNCOA1 2030) is clipped at 1 and leaves no record
            @test rcpx[("REG1", "2010", "ELCTNGAS01", "2010")] ≈ -0.43499668024354694 && cpt[k("2010", "2010", "ELCTNGAS01")] ≈ 0.5650033197564531
            @test !any(x -> (x[2], x[3]) in (("2015", "ELCTNGAS01"), ("2030", "COTNCOA1")), keys(rcpx.values))
            # L68-70: COTNCOA1 2050, a repeated investment: the lifetime average 0.93
            @test rcpx[("REG1", "2050", "COTNCOA1", "2050")] ≈ -0.07
            # the forced COEF_RPTI 2 on a 30-year life: OPYEAR empty, COEF_CAP 0, factor -1, COEF_CPT removed (L73)
            @test rcpx[("REG1", "2030", "ELCTNGAS01", "2030")] == -1.0 && !haskey(cpt, k("2030", "2030", "ELCTNGAS01"))
            @test length(cpt) == length(cpt0) - 2
        end
    end
end

@testset "coef_shp refuses only the capacity transfer of capacity-related flows" begin
    # M1.3 changes 53-54: NCAP_COM (L39-42) and RCAP_OCAP (L96) are translated; the capacity
    # transfer, NCAP_OCOM with FLO_FUNCX(R,'0',P,'CAPFLO',C) = 3 (L77-94), stays refused.
    tm = coef_shp_start(PPM_DEMO12, "cpt")
    gput!(tm, "NCAP_COM", Dict(("REG1", "2010", "ELCTNGAS01", "ELC", "OUT") => 1.0))
    @test isempty(coef_shp_unported(tm))
    tm = coef_shp_start(PPM_DEMO12, "cpt")
    gput!(tm, "RCAP_OCAP", Dict(("REG1", "2010", "ELCTNGAS01", "ELC") => 5.0))
    @test isempty(coef_shp_unported(tm))
    tm = coef_shp_start(PPM_DEMO12, "cpt")
    gput!(tm, "NCAP_OCOM", Dict(("REG1", "2010", "ELCTNGAS01", "ELC") => 1.0))
    gput!(tm, "FLO_FUNCX", Dict(("REG1", "0", "ELCTNGAS01", "CAPFLO", "ELC") => 3.0))
    @test occursin("L77-94", only(coef_shp_unported(tm)))
    @test_throws UnportedError coef_shp!(tm)
end

@testset "later_overwrites: COEF_CPT that coef_shp.mod L73 rescales" begin
    # The layer-1 check of a file before coef_shp compares COEF_CPT with the coef dump, which
    # holds coef_shp.mod's rescaled values (L73) for the NCAP_CPX processes that L52 keeps:
    # those records are left out until coef_shp's own check (scripts/m12_probe.jl).
    tm = coef_shp_start(PPM_DEMO12, "cpt")                      # the state coef_alt leaves, plus NCAP_CPX
    ref = DumpData(joinpath(FIXTURES, "coefshp_unit_gams", "cpt"))   # coef_shp.mod run by GAMS on it
    @test !all(ispass, layer1(tm, ref, ["COEF_CPT"]))
    lo = later_overwrites(tm; after="coef_alt")
    @test all(ispass, layer1(tm, ref, ["COEF_CPT"]; exclude=lo))
    @test lo["COEF_CPT"](("REG1", "2010", "2015", "ELCTNGAS01")) && !lo["COEF_CPT"](("REG1", "2010", "2015", "ELCTECOA00"))
    # from coef_shp on, the shaped records are compared (only coef_ext.vda's rules remain)
    @test !later_overwrites(tm; after="coef_shp")["COEF_CPT"](("REG1", "2010", "2015", "ELCTNGAS01"))
    @test isempty(later_overwrites(tm; after="coef_ext"))
    @test_throws ArgumentError later_overwrites(tm; after="coef_xyz")
end
