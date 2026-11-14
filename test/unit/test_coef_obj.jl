# M1.2 (4): coef_obj.mod L1-205 with filparam.gms and fillcost.gms (v4.9.7).
# Layer 1 on TIMES_Demo demo12 against its coef dump, and on a crafted state
# against coef_obj.mod run by GAMS itself (scripts/make_coef_obj_unit.jl):
# several currencies, interpolated discount rates and their options, G_RFRIR,
# G_DYEAR before the first year, NCAP_ISPCT, flow taxes and subsidies,
# storage flow costs, OBJ_COMPD and EPS cost data.

using TIMES: TimesModel, DumpData, coef_obj!, coef_obj_unported, later_overwrites, layer1, gparam, gset, gput!,
             gvalues, iseps, glead, UnportedError
using TIMES.Reference: ispass

isdefined(@__MODULE__, :PPM_DEMO12) || (const PPM_DEMO12 = joinpath(FIXTURES, "demo12_off_ppm"))
isdefined(@__MODULE__, :COEF_DEMO12) || (const COEF_DEMO12 = joinpath(FIXTURES, "demo12_off_coef"))
include("coef_obj_case.jl")

@testset "coef_obj layer 1, TIMES_Demo demo12" begin
    tm = coef_obj_start(PPM_DEMO12)
    @test isempty(coef_obj_unported(tm))
    coef_obj!(tm)
    r = layer1(tm, DumpData(COEF_DEMO12), COEF_OBJ_OUTPUTS; exclude=later_overwrites(tm))
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test all(ispass, r)
    # L45-54: OBJ_DISC is 1 at the base year G_DYEAR = 2005 and 1/1.05 a year later
    disc = gparam(tm, "OBJ_DISC")
    @test disc[("REG1", "2005", "MEuro05")] ≈ 1.0
    @test disc[("REG1", "2006", "MEuro05")] ≈ 1 / 1.05
    # L48 runs one year past FIL (LOOP(FIL(LL-1))) in each region, and that year is not normalised
    for r in ("REG1", "REG2")
        n(p) = count(k -> k[1] == r && k[3] == "MEuro05", keys(gparam(tm, p).values))
        @test n("OBJ_DISC") == n("G_DRATE") + 1
    end
    @test gset(tm, "G_RCUR").keys == [("REG1", "MEuro05"), ("REG2", "MEuro05")]
end

@testset "coef_obj against GAMS on a crafted state" begin
    tm = coef_obj_start(PPM_DEMO12)
    coef_obj_case!(tm)
    @test isempty(coef_obj_unported(tm))
    coef_obj!(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "coefobj_unit_gams")), COEF_OBJ_OUTPUTS)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test all(ispass, r)
    gd = gparam(tm, "G_DRATE")
    k(y, c) = ("REG1", y, c)
    # filparam options: 5 no backward extrapolation (then L56 floors V years at 1e-11);
    # 2 EPS outside the data; 14 (= 4) no forward extrapolation; -1 nothing
    @test !haskey(gd, k("2009", "TJLA")) && gd[k("2005", "TJLA")] == 1e-11 && gd[k("2020", "TJLA")] == 1e-11
    @test gd[k("2019", "TJLA")] ≈ -0.004
    # 2030 is a model year here, so L56 floors it to 1e-11; 2040 keeps the EPS of option 2
    @test iseps(gd, k("2040", "TJLB")) && gd[k("2030", "TJLB")] == 1e-11 && gd[k("2020", "TJLB")] == 1e-11
    @test gd[k("2010", "TJLB")] ≈ 0.015
    @test gd[k("2005", "TJLC")] == 0.07 && !haskey(gd, k("2016", "TJLC"))
    @test !haskey(gd, k("2011", "TJLD"))
    @test gd[k("2007", "MEuro05")] ≈ 0.046 && gd[k("2040", "MEuro05")] == 0.06
    # L59-62: per region, the reporting currency with the largest present value of
    # the periods; REG2 has no crafted currencies and keeps MEuro05
    @test gset(tm, "G_RCUR").keys == [("REG1", "TJLA"), ("REG2", "MEuro05")]
    # L28: a lead of -1.5 is rounded away from zero
    @test glead(-1.5) == -2 && glead(2.5) == 3 && ("2002",) in gset(tm, "EACHYEAR")
    # L66: G_RFRIR for every currency of RDCUR; L90, L123-124: NCAP_ISPCT
    @test gparam(tm, "OBJ_RFR")[k("2010", "TJLB")] == 0.02 && iseps(gparam(tm, "OBJ_RFR"), k("2015", "MEuro05"))
    @test collect(keys(gparam(tm, "NCAP_ISPCT").values)) == [("REG1", "2010", "COTNCOA1")]
    ic, isb = gparam(tm, "OB_ICOST"), gparam(tm, "OB_ISUB")
    kc = ("REG1", "COTNCOA1", "MEuro05", "2010")
    @test isb[kc] ≈ 0.2 * ic[kc]
    # L80-81: storage flow costs; L82-88: OBJ_FSUB and OBJ_VFLO
    @test collect(keys(gparam(tm, "FLO_COST").values)) == [("REG1", "2005", "ELCTECOA00", "ELCCOA", "ANNUAL", "MEuro05")]
    @test collect(keys(gparam(tm, "FLO_DELIV").values)) == [("REG1", "2005", "ELCTECOA00", "ELC", "ANNUAL", "MEuro05")]
    # the net tax is -0.5 in every year of FIL (2005-2052 on demo12)
    @test all(==(-0.5), values(gparam(tm, "OB_FTAX").values)) && length(gparam(tm, "OB_FTAX")) == length(gset(tm, "FIL"))
    @test ("REG1", "ELCTECOA00", "ELC", "MEuro05", "TAX") in gset(tm, "OBJ_VFLO")
    # L70 and fillcost.gms L41: commodity costs written back over FIL
    comnt = gparam(tm, "OBJ_COMNT")
    @test !haskey(comnt, ("REG1", "2005", "ELC", "ANNUAL", "COST", "MEuro05"))
    @test comnt[("REG1", "2020", "DCOT", "ANNUAL", "TAX", "MEuro05")] == 1.0
    @test isempty(gparam(tm, "OB_COM")) && isempty(gparam(tm, "OBJ_FSUB"))
    # fillcost.gms with an EPS first value: interpolated from 0 (EPS) to 12
    fom = gparam(tm, "OB_FOM")
    @test iseps(fom, ("REG1", "CSHNGAS1", "MEuro05", "2005")) && fom[("REG1", "CSHNGAS1", "MEuro05", "2010")] ≈ 4.0
end

@testset "coef_obj refuses untranslated paths" begin
    mk(sw) = TimesModel(PPM_DEMO12; switches=merge(COEF_OBJ_CASE_SWITCHES, sw))
    @test isempty(coef_obj_unported(mk(Dict("ANNCOST" => "lev"))))      # translated: M1.3 change 29
    @test occursin("VALIDATE", only(coef_obj_unported(mk(Dict("VALIDATE" => "YES")))))
    @test occursin("TIMESED", only(coef_obj_unported(mk(Dict("MICRO" => "YES")))))
    tm = mk(Dict{String,String}())
    gput!(tm, "BLE_OPR", Set([("REG1", "ELC", "ELC")]))
    @test occursin("blending", only(coef_obj_unported(tm)))
    @test_throws UnportedError coef_obj!(tm)
    tm = mk(Dict{String,String}())
    add_uels!(tm, "TJLX")
    cost = gvalues(tm, "NCAP_COST", 4); cost[("REG1", "2010", "CSHNOIL1", "TJLX")] = 1.0; gput!(tm, "NCAP_COST", cost)
    # L96-99: $IF DEFINED R_CUREX is read from R_CUREX's data (M1.3 change 26): without it %TAKE% is
    # RDCUR(R,CUR) and a cost outside RDCUR is not taken; with it (curex.gms ran) %TAKE% is 1
    @test isempty(coef_obj_unported(tm))
    coef_obj!(tm)
    @test !any(k -> k[3] == "TJLX", keys(gparam(tm, "OB_ICOST").values))
    tm = mk(Dict{String,String}())
    add_uels!(tm, "TJLX")
    gput!(tm, "NCAP_COST", cost)
    gput!(tm, "R_CUREX", Dict(("REG1", "MEuro05", "MEuro05") => 1.0))
    coef_obj!(tm)
    @test any(k -> k[3] == "TJLX", keys(gparam(tm, "OB_ICOST").values))
end
