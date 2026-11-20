# A crafted GAMS state for coef_obj.mod (v4.9.7): the TIMES_Demo demo12 ppm
# dump (test/fixtures/demo12_off_ppm, CC BY 4.0) taken through coef_cpt,
# coef_nio and coef_ptr, plus data for the paths no reference run takes
# (every reference run has one currency per region, one discount-rate year,
# no G_RFRIR, flow taxes or subsidies, NCAP_ISPCT or OBJ_COMPD, and no
# storage flow costs to remove). Shared by
# scripts/make_coef_obj_unit.jl, which runs coef_obj.mod itself on it with
# GAMS, and test/unit/test_coef_obj.jl, which checks coef_obj! against that.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!, coef_cpt!, coef_nio!, coef_ptr!

"Add labels to a model's unique-element list, after the dump's (as GAMS enters new labels)."
function add_uels!(tm, labels...)
    for l in labels
        haskey(tm.data.uelorder, lowercase(l)) && continue
        push!(tm.data.dump.uels, l)
        tm.data.uelorder[lowercase(l)] = length(tm.data.dump.uels)
    end
    return tm
end

# demo12's run file (test/fixtures/public_fixtures.toml): OBJ MOD sets OBLONG and %CTST% **0
const COEF_OBJ_CASE_SWITCHES = Dict("OBJ" => "MOD", "VDA" => "YES", "DSCAUTO" => "YES", "VALIDATE" => "NO",
                                    "STAGES" => "NO")

"The demo12 state at the start of coef_obj.mod (maindrv.mod L72, coefmain.mod L23)."
function coef_obj_start(ppm_dir; switches=COEF_OBJ_CASE_SWITCHES)
    tm = TimesModel(ppm_dir; switches)
    coef_cpt!(tm); coef_nio!(tm); coef_ptr!(tm)
    return tm
end

"""
    coef_obj_case!(tm) -> tm

On REG1 of TIMES_Demo demo12 (model years 2005-2050; ALLYEAR from 1960,
so a G_DYEAR before YR_V1 is given as a number):

1. Currencies TJLA and TJLB join MEuro05 in RDCUR; TJLC and TJLD have
   discount rates but are not in RDCUR. No G_RCUR is given (L59-62 picks).
2. G_DRATE: MEuro05 at 2005, 2010 and 2020 (interpolation); TJLA at 2010 and
   2020 = -0.01 with option 5 (no backward extrapolation; V years <= 0 become
   1e-11, L56); TJLB at 2005 and 2015 = EPS with option 2 (EPS outside the
   data); TJLC option 14 (no forward extrapolation); TJLD option -1 (nothing).
3. G_DYEAR 1950, before YR_V1 = 1960 (L50-53: clamped, discounted by the power).
4. G_RFRIR at 2010 and EPS at 2015 (L66).
5. NCAP_ILED -1.5 at the past year 2004 of ELCTECOA00: EACHYEAR gains 2002
   (L28; the lead is rounded away from zero).
6. NCAP_ISPCT for COTNCOA1 (into OB_ISUB through X_RP, L123-124) and for
   CAPNELC1, which has an NCAP_ISUB and so loses it (L90).
7. NCAP_COST of CSHNOIL1 in TJLA at 2010 and 2030; NCAP_FOM of ELCTECOA00
   EPS at 2015 after 40 at 2005, and of CSHNGAS1 EPS at 2005 (replacing 7.5)
   then 12 at 2020 (EPS end points, `IF(LAST_VAL)` with EPS).
8. FLO_TAX and FLO_SUB of ELCTECOA00/ELC (OBJ_FSUB, a tax cancelled by a
   subsidy, a non-model year dropped for an OBJ_VFLO 'SUB' given, L82-88).
9. ELC and ELCCOA of ELCTECOA00 made storage commodities: FLO_COST on the
   output and FLO_DELIV on the input are removed (L80-81).
10. OBJ_COMPD of ELC at SD (filled and written back, L144); an OBJ_COMNT of
   ELC at ANNUAL, not a timeslice of ELC (removed, L70); an OBJ_COMNT TAX of
   DCOT at ANNUAL (filled).
"""
function coef_obj_case!(tm)
    r = "REG1"
    add_uels!(tm, "TJLA", "TJLB", "TJLC", "TJLD")
    cur = gmembers(tm, "CUR", 1); foreach(c -> push!(cur, (c,)), ("TJLA", "TJLB", "TJLC", "TJLD")); gput!(tm, "CUR", cur)
    rdcur = gmembers(tm, "RDCUR", 2); push!(rdcur, (r, "TJLA"), (r, "TJLB")); gput!(tm, "RDCUR", rdcur)
    gd = gvalues(tm, "G_DRATE", 3)
    gd[(r, "2010", "MEuro05")] = 0.04; gd[(r, "2020", "MEuro05")] = 0.06
    gd[(r, "0", "TJLA")] = 5.0; gd[(r, "2010", "TJLA")] = 0.05; gd[(r, "2020", "TJLA")] = -0.01
    gd[(r, "0", "TJLB")] = 2.0; gd[(r, "2005", "TJLB")] = 0.03; gd[(r, "2015", "TJLB")] = 0.0      # EPS
    gd[(r, "0", "TJLC")] = 14.0; gd[(r, "2010", "TJLC")] = 0.07; gd[(r, "2015", "TJLC")] = 0.08
    gd[(r, "0", "TJLD")] = -1.0; gd[(r, "2010", "TJLD")] = 0.1
    gput!(tm, "G_DRATE", gd)
    gput!(tm, "G_DYEAR", Dict{Tuple{},Float64}(() => 1950.0))
    gput!(tm, "G_RFRIR", Dict((r, "2010") => 0.02, (r, "2015") => 0.0))
    iled = gvalues(tm, "NCAP_ILED", 3); iled[(r, "2004", "ELCTECOA00")] = -1.5; gput!(tm, "NCAP_ILED", iled)
    gput!(tm, "NCAP_ISPCT", Dict((r, "2010", "COTNCOA1") => 0.2, (r, "2010", "CAPNELC1") => 0.1))
    gput!(tm, "NCAP_ISUB", Dict((r, "2010", "CAPNELC1", "MEuro05") => 0.05))
    cost = gvalues(tm, "NCAP_COST", 4)
    cost[(r, "2010", "CSHNOIL1", "TJLA")] = 100.0; cost[(r, "2030", "CSHNOIL1", "TJLA")] = 80.0
    gput!(tm, "NCAP_COST", cost)
    fom = gvalues(tm, "NCAP_FOM", 4)
    fom[(r, "2015", "ELCTECOA00", "MEuro05")] = 0.0                                              # EPS
    fom[(r, "2005", "CSHNGAS1", "MEuro05")] = 0.0; fom[(r, "2020", "CSHNGAS1", "MEuro05")] = 12.0
    gput!(tm, "NCAP_FOM", fom)
    p = "ELCTECOA00"
    gput!(tm, "FLO_TAX", Dict((r, "2010", p, "ELC", "ANNUAL", "MEuro05") => 1.0, (r, "2012", p, "ELC", "ANNUAL", "MEuro05") => 2.0))
    gput!(tm, "FLO_SUB", Dict((r, "2020", p, "ELC", "ANNUAL", "MEuro05") => 0.5, (r, "2010", p, "ELC", "ANNUAL", "MEuro05") => 1.0))
    gput!(tm, "OBJ_VFLO", Set([(r, p, "ELC", "MEuro05", "SUB")]))
    stg = gmembers(tm, "RPC_STG", 3); push!(stg, (r, p, "ELC"), (r, p, "ELCCOA")); gput!(tm, "RPC_STG", stg)
    gput!(tm, "FLO_COST", Dict((r, "2005", p, "ELC", "ANNUAL", "MEuro05") => 3.0, (r, "2005", p, "ELCCOA", "ANNUAL", "MEuro05") => 5.0))
    gput!(tm, "FLO_DELIV", Dict((r, "2005", p, "ELC", "ANNUAL", "MEuro05") => 4.0, (r, "2005", p, "ELCCOA", "ANNUAL", "MEuro05") => 6.0))
    gput!(tm, "OBJ_COMPD", Dict((r, "2005", "ELC", "SD", "COST", "MEuro05") => 2.0, (r, "2020", "ELC", "SD", "COST", "MEuro05") => 4.0))
    comnt = gvalues(tm, "OBJ_COMNT", 6)
    comnt[(r, "2005", "ELC", "ANNUAL", "COST", "MEuro05")] = 9.0
    comnt[(r, "2010", "DCOT", "ANNUAL", "TAX", "MEuro05")] = 1.0
    gput!(tm, "OBJ_COMNT", comnt)
    return tm
end

"What coef_obj.mod writes, compared after it (scripts/m12_probe.jl)."
const COEF_OBJ_OUTPUTS = ["TS_ANN", "EACHYEAR", "Y", "YK", "Y_EOH", "YR_V1", "YR_VL", "ACL", "G_DRATE", "OBJ_DISC",
    "G_DYEAR", "G_RCUR", "OBJ_PVT", "COEF_PVT", "OBJ_RFR", "OBJ_COMNT", "OBJ_COMPD", "OBJ_IPRIC", "FLO_COST",
    "FLO_DELIV", "OBJ_VFLO", "NCAP_ISPCT", "OB_ICOST", "OB_ISUB", "OB_ITAX", "OB_FOM", "OB_FSB", "OB_FTX", "OB_DCC",
    "OB_DLC", "OB_ACT", "OB_FCOS", "OB_FDEL", "OB_FTAX", "OBJ_FSUB", "RPC_CUR", "X_RP", "OB_COM", "OB_IRE", "SHEDJ",
    "SHAPED", "FIL"]

"Symbols coef_obj.mod and fillcost.gms declare themselves (not written into a replayed state)."
const COEF_OBJ_DECLARED = Set(["Y", "Y_EOH", "YK", "TS_ANN", "YR_V1", "YR_VL", "ACL", "SHEDJ", "SHAPED", "SPAN", "K",
    "OB_ICOST", "OB_ISUB", "OB_ITAX", "X_RP", "OB_FOM", "OB_FSB", "OB_FTX", "OB_DCC", "OB_DLC", "OB_ACT", "OB_COM",
    "OB_IRE", "OB_FCOS", "OB_FDEL", "OB_FTAX"])
