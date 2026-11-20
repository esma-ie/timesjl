# Crafted states for coef_ext.vda (v4.9.7): the TIMES_Demo demo12 ppm dump
# (test/fixtures/demo12_off_ppm) taken through coefmain.mod (coef_cpt to
# coef_shp), then given the data its untaken paths need, so that every
# translated statement is checked against coef_ext.vda run by GAMS itself
# (scripts/make_coef_ext_unit.jl, test/unit/test_coef_ext.jl).
#
# demo12 itself exercises L21-27 (PRC_RESID, NCAP_PASTI, COEF_CPT of the
# 2004 vintage), L42-47 (TOTCO2 loses its balance in both regions), L60-74
# (237 singleton ACT_EFF groups) and L81-82; it has no PRC_RCAP, storage
# availabilities, IRE_FLOSUM, RPC_NOFLO, UCU units, UC_TIME or NCAP_BND 'N'.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!, coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!

const COEF_EXT_CASE_SWITCHES = Dict("OBJ" => "MOD", "VDA" => "YES", "DSCAUTO" => "YES", "VALIDATE" => "NO", "STAGES" => "NO")

"""
The cases, name => description:

- "resid": L21-27 and L42-47. PRC_RCAP on ELCTECOA00 (REG1: Z = its largest
  PRC_RESID, RTFORC at the 2004 vintage with an EPS at 2005, PRC_RESID made
  flat, NCAP_PASTI and COEF_CPT recomputed); PRC_RESID(REG1,'0',ELCTNGAS01)
  with no positive period value (NCAP_PASTI removed, the '0' record removed);
  IRE_FLOSUM on IMPCOA1 with TOTCO2 as the auxiliary commodity (RCS keeps
  REG1's TOTCO2 balance, L45) and RPC_NOFLO(REG2,ELCTECOA00,TOTCO2) (keeps
  REG2's, L46).
- "misc": L32-39, L49-57 and L83. RP_STS on ELCTNGAS01 with RP_STL 'N' and
  'UP' (the 'UP' cleared, the 'N' outside BD kept) and an 'UP' on ELCTECOA00
  (kept); RPS_STG on ELCTNGAS01 at SD, WD and SN with an UP
  CAFLAC at SD, NCAP_AFC('ACT') at SN 2010 (where NCAP_AF is removed) and
  WD 2015 (where it overrides NCAP_AF), and on
  ELCTEOIL00 taken out of PRC_CAP (dropped, L37); STG_MAXCYC at 2010 with
  ACT_CSTUP at ANNUAL (annuity) and DAYNITE (unchanged: TSL(S) is a level
  that is also a timeslice), and ACT_CSTUP alone at 2015 (unchanged); COM_UNIT
  (REG2,TOTCO2,'UCU') with RTC(REG2,2030,TOTCO2) removed and an RTPC record
  added (RTCS_VARC dropped, RPC_CONLY, an 'IMPEXP' TOP_IRE row dropped);
  UC_TIME -13.4 at '0' for AU_NUC_MaxCAP in REG1 with UC_R_SUM in both
  regions (UC_ON off in both, period UC_TIMEs zeroed) and -12 for
  UC_RNW-PP_LOW in REG2 (kept); NCAP_BND 'N' with COEF_ILED 2005.5 + NCAP_ILED
  (5.5), 2000 without (removed), 3000 with (EPS), an 'UP' bound (unchanged)
  and a past vintage (unchanged); ACT_EFF EPS on CAPEELC's COMELC (no
  COEF_PTRAN record, L72).
"""
const COEF_EXT_CASES = ["resid", "misc"]

function coef_ext_start(ppm_dir, name; switches=COEF_EXT_CASE_SWITCHES)
    tm = TimesModel(ppm_dir; switches)
    coef_cpt!(tm); coef_nio!(tm); coef_ptr!(tm); coef_obj!(tm); coef_alt!(tm); coef_shp!(tm)
    coef_ext_case!(tm, name)
    return tm
end

function coef_ext_case!(tm, name)
    r = "REG1"
    if name == "resid"
        gput!(tm, "PRC_RCAP", Set([(r, "ELCTECOA00")]))
        resid = gvalues(tm, "PRC_RESID", 3); resid[(r, "0", "ELCTNGAS01")] = 5.0; gput!(tm, "PRC_RESID", resid)
        pasti = gvalues(tm, "NCAP_PASTI", 3); pasti[(r, "2004", "ELCTNGAS01")] = 7.0; gput!(tm, "NCAP_PASTI", pasti)
        gput!(tm, "IRE_FLOSUM", Dict((r, "2010", "IMPCOA1", "COA", "ANNUAL", "IMP", "TOTCO2", "OUT") => 0.1))
        gput!(tm, "RPC_NOFLO", Set([("REG2", "ELCTECOA00", "TOTCO2")]))
    elseif name == "misc"
        gput!(tm, "RP_STS", Set([(r, "ELCTNGAS01")]))
        gput!(tm, "RP_STL", Set([(r, "ELCTNGAS01", "DAYNITE", "N"), (r, "ELCTNGAS01", "DAYNITE", "UP"),
                                 (r, "ELCTECOA00", "DAYNITE", "UP")]))
        gput!(tm, "RPS_STG", Set([(r, "ELCTNGAS01", "SD"), (r, "ELCTNGAS01", "WD"), (r, "ELCTNGAS01", "SN"),
                                  (r, "ELCTEOIL00", "SD")]))
        gput!(tm, "RPS_CAFLAC", Set([(r, "ELCTNGAS01", "SD", "UP")]))
        gput!(tm, "NCAP_AFC", Dict((r, "2010", "ELCTNGAS01", "ACT", "SN") => 0.9, (r, "2015", "ELCTNGAS01", "ACT", "WD") => 0.8))
        af = gvalues(tm, "NCAP_AF", 5); delete!(af, (r, "2010", "ELCTNGAS01", "SN", "UP")); gput!(tm, "NCAP_AF", af)
        pc = gmembers(tm, "PRC_CAP", 2); delete!(pc, (r, "ELCTEOIL00")); gput!(tm, "PRC_CAP", pc)
        gput!(tm, "STG_MAXCYC", Dict((r, "2010", "ELCTNGAS01") => 100.0))
        gput!(tm, "ACT_CSTUP", Dict((r, "2010", "ELCTNGAS01", "ANNUAL", "MEuro05") => 5.0,
                                    (r, "2010", "ELCTNGAS01", "DAYNITE", "MEuro05") => 5.0,
                                    (r, "2015", "ELCTNGAS01", "ANNUAL", "MEuro05") => 5.0))
        cu = gmembers(tm, "COM_UNIT", 3); push!(cu, ("REG2", "TOTCO2", "UCU")); gput!(tm, "COM_UNIT", cu)
        rtc = gmembers(tm, "RTC", 3); delete!(rtc, ("REG2", "2030", "TOTCO2")); gput!(tm, "RTC", rtc)
        rtpc = gmembers(tm, "RTPC", 4); push!(rtpc, ("REG2", "2030", "ELCTECOA00", "TOTCO2")); gput!(tm, "RTPC", rtpc)
        ti = gmembers(tm, "TOP_IRE", 5); push!(ti, ("IMPEXP", "COA", "REG2", "TOTCO2", "IMPCOA1")); gput!(tm, "TOP_IRE", ti)
        gput!(tm, "UC_TIME", Dict(("AU_NUC_MaxCAP", r, "0") => -13.4, ("AU_NUC_MaxCAP", r, "2010") => 1.0,
                                  ("AU_NUC_MaxCAP", r, "2020") => 1.0, ("AU_NUC_MaxCAP", "REG2", "2010") => 1.0,
                                  ("UC_RNW-PP_LOW", "REG2", "0") => -12.0, ("UC_RNW-PP_LOW", "REG2", "2010") => 1.0))
        gput!(tm, "UC_R_SUM", Set([(r, "AU_NUC_MaxCAP"), ("REG2", "AU_NUC_MaxCAP")]))
        bnd = gvalues(tm, "NCAP_BND", 4)
        bnd[(r, "2010", "ELCTNGAS01", "N")] = 5.0; bnd[(r, "2015", "ELCTNGAS01", "N")] = 1.0
        bnd[(r, "2020", "ELCTNGAS01", "N")] = 0.0; bnd[(r, "2030", "ELCTNGAS01", "UP")] = 7.0
        bnd[(r, "2004", "ELCTECOA00", "N")] = 1.0
        gput!(tm, "NCAP_BND", bnd)
        gput!(tm, "COEF_ILED", Dict((r, "2010", "ELCTNGAS01") => 2005.5, (r, "2015", "ELCTNGAS01") => 2000.0,
                                    (r, "2020", "ELCTNGAS01") => 3000.0, (r, "2030", "ELCTNGAS01") => 2007.0,
                                    (r, "2004", "ELCTECOA00") => 1003.0))
        iled = gvalues(tm, "NCAP_ILED", 3); iled[(r, "2010", "ELCTNGAS01")] = 2.4; iled[(r, "2020", "ELCTNGAS01")] = 1.0
        gput!(tm, "NCAP_ILED", iled)
        ae = gvalues(tm, "ACT_EFF", 5)
        for v in ("2004", "2005"), s in ("SD", "SN", "WD", "WN")
            ae[(r, v, "CAPEELC", "COMELC", s)] = 0.0
        end
        gput!(tm, "ACT_EFF", ae)
    else
        error("unknown coef_ext case $name")
    end
    return tm
end

"What coef_ext.vda writes, compared after it (scripts/m12_probe.jl)."
const COEF_EXT_OUTPUTS = ["COEF_CPT", "NCAP_PASTI", "PRC_RESID", "RTFORC", "RP_STL", "COEF_AFUPS", "ACT_CSTUP", "RCS_COMBAL",
                          "RTCS_VARC", "RPC_CONLY", "TOP_IRE", "TRACKC", "TRACKP", "RCS", "UC_TIME", "UC_ON", "R_UC",
                          "COEF_PTRAN", "ACT_EFF", "RPCC_FFUNC", "RP_CGC", "TRACKPC", "RP_GRP", "CG_GRP", "RP_DCGG",
                          "RTP_CAPYR", "RPCG_PTRAN", "UNCD7", "COEF_PVT", "VDA_DISC", "COEF_ILED", "ACT_FLO", "RTP_FFCX"]

"Symbols coef_ext.vda and its includes declare themselves (coef_ext.vda L12, eqlducs.vda L12)."
const COEF_EXT_DECLARED = Set(["VDA_DISC", "DP_NON"])
