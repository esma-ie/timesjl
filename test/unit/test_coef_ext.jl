# M1.2 (7): coef_ext.vda L12-83 (v4.9.7), the last file of the coefficient
# stage. Layer 1 on TIMES_Demo demo12 against its coef dump with nothing
# left to later files (the residual-capacity COEF_CPT records, the singleton
# ACT_EFF groups as COEF_PTRAN, the pruned commodity balances, COEF_PVT and
# VDA_DISC), and on two crafted states against coef_ext.vda run by GAMS
# itself (scripts/make_coef_ext_unit.jl): PRC_RCAP, storage availabilities,
# the ACT_CSTUP annuity, IRE_FLOSUM/RPC_NOFLO/UCU balances, UC_TIME, COEF_ILED.

using TIMES: TimesModel, DumpData, coef_ext!, coef_ext_unported, coef_obj!, coef_alt!, coef_shp!, layer1, gparam, gset,
             gput!, gvalues, iseps, UnportedError
using TIMES.Reference: ispass

isdefined(@__MODULE__, :PPM_DEMO12) || (const PPM_DEMO12 = joinpath(FIXTURES, "demo12_off_ppm"))
isdefined(@__MODULE__, :COEF_DEMO12) || (const COEF_DEMO12 = joinpath(FIXTURES, "demo12_off_coef"))
include("coef_obj_case.jl")
include("coef_ext_case.jl")

@testset "coef_ext layer 1, TIMES_Demo demo12" begin
    tm = coef_obj_start(PPM_DEMO12; switches=COEF_EXT_CASE_SWITCHES)
    coef_obj!(tm); coef_alt!(tm); coef_shp!(tm)
    @test isempty(coef_ext_unported(tm))
    cpt_before, ptran_before = length(gparam(tm, "COEF_CPT")), length(gparam(tm, "COEF_PTRAN"))
    coef_ext!(tm)
    r = layer1(tm, DumpData(COEF_DEMO12), COEF_EXT_OUTPUTS)                   # nothing left to later files
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test all(ispass, r)
    # L24, L27: NCAP_PASTI of the 2004 (PYR_S) vintage is the duration-weighted average residual, and COEF_CPT
    #           at that vintage PRC_RESID(T)/NCAP_PASTI (ELCTECOA00: 74.48 in 2010 over 42.20)
    cpt, pasti = gparam(tm, "COEF_CPT"), gparam(tm, "NCAP_PASTI")
    @test length(cpt) == cpt_before && pasti[("REG1", "2004", "ELCTECOA00")] ≈ 42.203808557415854
    @test cpt[("REG1", "2004", "2010", "ELCTECOA00")] ≈ 74.47730921896915 / 42.203808557415854
    # L42-47: TOTCO2 is nobody's input, export, demand or RPC_NOFLO flow: its balance rows go in both regions
    @test length(gset(tm, "RCS_COMBAL")) == 996 && !any(k -> k[3] == "TOTCO2", gset(tm, "RCS_COMBAL").keys)
    # L60-74: the 237 singleton ACT_EFF groups (RPG_1ACE) become COEF_PTRAN records, join RPCC_FFUNC and lose ACT_EFF
    @test ptran_before == 696 && length(gparam(tm, "COEF_PTRAN")) == 2742
    @test length(gset(tm, "RPCC_FFUNC")) == 237 && length(gparam(tm, "ACT_EFF")) == 96
    # L81-82: COEF_PVT is complete (coef_obj.mod), so FPD fills nothing; VDA_DISC copies it
    @test gparam(tm, "VDA_DISC").values == gparam(tm, "COEF_PVT").values && length(gparam(tm, "VDA_DISC")) == 12
    @test all(isempty(gset(tm, n)) for n in ("TRACKP", "TRACKC", "RCS", "TRACKPC", "RP_GRP", "CG_GRP", "RTP_CAPYR", "RP_CGC"))
end

@testset "coef_ext against GAMS on crafted states" begin
    for name in COEF_EXT_CASES
        tm = coef_ext_start(PPM_DEMO12, name)
        @test isempty(coef_ext_unported(tm))
        coef_ext!(tm)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "coefext_unit_gams", name)), COEF_EXT_OUTPUTS)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        if name == "resid"
            # L23: ELCTECOA00 in PRC_RCAP: Z is its 2005 residual; RTFORC = Z - PRC_RESID + EPS (EPS at 2005), PRC_RESID flat
            z = 89.372771062763
            rtf, resid = gparam(tm, "RTFORC"), gparam(tm, "PRC_RESID")
            @test iseps(rtf, ("REG1", "2004", "2005", "ELCTECOA00")) && rtf[("REG1", "2004", "2030", "ELCTECOA00")] ≈ z - 14.895461843793832
            @test all(resid[("REG1", t, "ELCTECOA00")] ≈ z for t in ("2005", "2010", "2015", "2020", "2030"))
            # L24, L27: NCAP_PASTI is then the (flat) average and COEF_CPT 1 at every period of the 2004 vintage
            @test gparam(tm, "NCAP_PASTI")[("REG1", "2004", "ELCTECOA00")] ≈ z
            @test all(gparam(tm, "COEF_CPT")[("REG1", "2004", t, "ELCTECOA00")] == 1.0 for t in ("2005", "2010", "2030"))
            # L24, L26: a '0' residual with no positive period value: NCAP_PASTI and the '0' record removed
            @test !haskey(gparam(tm, "NCAP_PASTI"), ("REG1", "2004", "ELCTNGAS01")) && !haskey(resid, ("REG1", "0", "ELCTNGAS01"))
            # L45-46: TOTCO2 kept as IRE_FLOSUM auxiliary (REG1, the rightmost COM of IRE_FLOSUM, G34) and RPC_NOFLO flow (REG2)
            @test length(gset(tm, "RCS_COMBAL")) == 1008
        else
            # L32: RP_STL 'UP' of the RP_STS process cleared; its 'N' row is outside BD and stays, another process's 'UP' stays
            @test Set(gset(tm, "RP_STL").keys) == Set([("REG1", "ELCTECOA00", "DAYNITE", "UP"), ("REG1", "ELCTNGAS01", "DAYNITE", "N")])
            # L35-37: NCAP_AF UP at WD and SN (not SD: an UP CAFLAC there), NCAP_AFC('ACT') at SN 2010 and over WD 2015;
            #         ELCTEOIL00 outside PRC_CAP dropped
            af = gparam(tm, "COEF_AFUPS")
            @test length(af) == 10 && !any(k -> k[3] == "ELCTEOIL00" || k[4] == "SD", keys(af.values))
            @test af[("REG1", "2010", "ELCTNGAS01", "SN")] == 0.9 && af[("REG1", "2015", "ELCTNGAS01", "WD")] == 0.8 && af[("REG1", "2010", "ELCTNGAS01", "WD")] == 1.0
            # L39: the annuity at ANNUAL (5 * 0.05 / (1 - 1.05^-30)); DAYNITE is not a timeslice, 2015 has no STG_MAXCYC
            cu = gparam(tm, "ACT_CSTUP")
            @test cu[("REG1", "2010", "ELCTNGAS01", "ANNUAL", "MEuro05")] ≈ 5 * 0.05 / (1 - 1.05^-30)
            @test cu[("REG1", "2010", "ELCTNGAS01", "DAYNITE", "MEuro05")] == 5.0 && cu[("REG1", "2015", "ELCTNGAS01", "ANNUAL", "MEuro05")] == 5.0
            # L49-52: REG2's TOTCO2 in UCU and untracked: RTCS_VARC rows go (none in RHS_COMPRD), RPC_CONLY where RTC is missing,
            #         the crafted 'IMPEXP' TOP_IRE row goes
            @test length(gset(tm, "RTCS_VARC")) == 1002 && !any(k -> k[1] == "REG2" && k[3] == "TOTCO2", gset(tm, "RTCS_VARC").keys)
            @test gset(tm, "RPC_CONLY").keys == [("REG2", "2030", "ELCTECOA00", "TOTCO2")]
            @test length(gset(tm, "TOP_IRE")) == 75 && !(("IMPEXP", "COA", "REG2", "TOTCO2", "IMPCOA1") in gset(tm, "TOP_IRE"))
            # L55-57: -13 at '0' switches AU_NUC_MaxCAP off in REG1 and, through UC_R_SUM, REG2; their period UC_TIMEs go
            @test Set(gset(tm, "UC_ON").keys) == Set([("REG1", "UC_RNW-PP_LOW"), ("REG2", "UC_RNW-PP_LOW")])
            ut = gparam(tm, "UC_TIME")
            @test length(ut) == 3 && ut[("AU_NUC_MaxCAP", "REG1", "0")] == -13.4 && ut[("UC_RNW-PP_LOW", "REG2", "2010")] == 1.0
            @test isempty(gset(tm, "R_UC"))
            # L83: MOD(COEF_ILED,1000)+EPS$NCAP_ILED at the milestone vintages with an 'N' bound
            ci = gparam(tm, "COEF_ILED")
            @test ci[("REG1", "2010", "ELCTNGAS01")] == 5.5 && !haskey(ci, ("REG1", "2015", "ELCTNGAS01")) && iseps(ci, ("REG1", "2020", "ELCTNGAS01"))
            @test ci[("REG1", "2030", "ELCTNGAS01")] == 2007.0 && ci[("REG1", "2004", "ELCTECOA00")] == 1003.0
            # L72: an EPS ACT_EFF on the flow gives no COEF_PTRAN record
            @test !any(k -> k[3] == "CAPEELC" && k[1] == "REG1", keys(gparam(tm, "COEF_PTRAN").values))
        end
    end
end

@testset "coef_ext refuses untranslated paths" begin
    tm = coef_ext_start(PPM_DEMO12, "resid")
    gput!(tm, "FLO_ASHAR", Dict(("REG1", "2010", "ELCTNGAS01", "NRG", "ELC", "ANNUAL", "UP") => 0.5))
    @test isempty(coef_ext_unported(tm))                 # FLO_ASHAR (eqashar.vda L16-33) is translated
    tm = coef_ext_start(PPM_DEMO12, "resid")
    gput!(tm, "RPC_FFUNC", Set([("REG1", "ELCTNGAS01", "ELC")]))
    @test isempty(coef_ext_unported(tm))                 # reduced flows (L62-69) are translated
    tm = coef_ext_start(PPM_DEMO12, "resid")
    gput!(tm, "ACT_MINLD", Dict(("REG1", "2010", "ELCTNGAS01") => 0.4))
    @test occursin("eqlducs.vda", only(coef_ext_unported(tm)))
    @test_throws UnportedError coef_ext!(tm)
    tm = TimesModel(PPM_DEMO12; switches=merge(COEF_EXT_CASE_SWITCHES, Dict("WAVER" => "YES")))
    @test occursin("fillwave", only(coef_ext_unported(tm)))
end
