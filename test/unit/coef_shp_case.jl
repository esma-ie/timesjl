# Crafted states for coef_shp.mod (v4.9.7): the TIMES_Demo demo12 ppm dump
# (test/fixtures/demo12_off_ppm) taken through coef_cpt, coef_nio, coef_ptr,
# coef_obj and coef_alt, then given the shaping data no reference run has,
# so that every translated path of the file is checked against coef_shp.mod
# run by GAMS itself (scripts/make_coef_shp_unit.jl, test/unit/test_coef_shp.jl).
#
# demo12 has no FLO_FUNCX and no NCAP_CPX; its SHAPE table is the default
# row '1' (ppmain.mod L629). ELCTNGAS01 is its one vintaged process
# (PRC_VINT, vintages 2010-2050, life 30), ELCTECOA00 has a past vintage
# 2004 (life 30) and COTNCOA1 (life 15) is a repeated investment at 2050
# (COEF_RPTI 2). Both cases are in REG1; REG2 is left alone.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!, coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!

const COEF_SHP_CASE_SWITCHES = Dict("OBJ" => "MOD", "VDA" => "YES", "DSCAUTO" => "YES", "VALIDATE" => "NO", "STAGES" => "NO")

"""
The cases, name => description:

- "ptran": the shaping of COEF_PTRAN (L10-37, L43-46). FLO_FUNCX 2 on
  ELCTNGAS01 at 2010 with NCAP_ILED 2.4 (rounded to 2 at L25) and -1 at 2015
  (RTP_CGC: L45 ratios from FLO_FUNC 2.0, 2.2, 2.4, 2.6); on ELCTECOA00 a
  'CAPFLO' row at 2005 (TRACKP through RP_GRP, dropped at L43), 3 at 2005,
  2.5 at the past vintage 2004 (the J lead rounds to '3', G29), an 'ACT'
  row at 2010 (removed, L17), 1 and 1000 (removed), and an 'ACT' row at
  year '0' (outside RTP, kept, counted in RP_GRP); on COTNCOA1 2 at 2030
  and 2050 with a 'CAPFLO' row and NCAP_ILED 1 (L34-36: lifetime average
  over OPYEAR(AGE+14,LIFE)); COEF_RPTI 2 on ELCTNGAS01 2030 (life 30:
  RVPRL 29 exceeds Z = 20, so OPYEAR is empty and the factor is -1).
- "cpt": the shaping of COEF_CPT (L51-74). NCAP_CPX 2 on ELCTNGAS01 2010
  (NCAP_ILED 2.4) and 3 at 2015; 2 on the past vintage ELCTECOA00 2004, 1 and
  1000 on its 2005 and 2010 (removed, L52); 2 on COTNCOA1 2050 (COEF_RPTI 2:
  L68-70) and 3 at 2030; COEF_RPTI 2 with NCAP_CPX 2 on ELCTNGAS01 2030
  (OPYEAR empty: COEF_CAP 0, the factor -1 and COEF_CPT removed at L73).
Both cases use the SHAPE rows '2' (1 - (age-1)/100) and '3' (1 + 2(age-1)/100)
over ages 1-40.
"""
const COEF_SHP_CASES = ["ptran", "cpt"]

function coef_shp_start(ppm_dir, name; switches=COEF_SHP_CASE_SWITCHES)
    tm = TimesModel(ppm_dir; switches)
    coef_cpt!(tm); coef_nio!(tm); coef_ptr!(tm); coef_obj!(tm); coef_alt!(tm)
    coef_shp_case!(tm, name)
    return tm
end

function coef_shp_case!(tm, name)
    r = "REG1"
    sh = gvalues(tm, "SHAPE", 2)
    for a in 1:40
        sh[("2", string(a))] = 1 - (a - 1) / 100
        sh[("3", string(a))] = 1 + 2 * (a - 1) / 100
    end
    gput!(tm, "SHAPE", sh)
    iled = gvalues(tm, "NCAP_ILED", 3)
    iled[(r, "2010", "ELCTNGAS01")] = 2.4
    iled[(r, "2050", "COTNCOA1")] = 1.0
    gput!(tm, "NCAP_ILED", iled)
    rpti = gvalues(tm, "COEF_RPTI", 3)
    rpti[(r, "2030", "ELCTNGAS01")] = 2.0
    gput!(tm, "COEF_RPTI", rpti)
    if name == "ptran"
        ffx = gvalues(tm, "FLO_FUNCX", 5)
        ffx[(r, "2010", "ELCTNGAS01", "NRG", "ELC")] = 2.0
        ffx[(r, "2015", "ELCTNGAS01", "NRG", "ELC")] = -1.0
        ffx[(r, "2030", "ELCTNGAS01", "NRG", "ELC")] = 2.0
        ffx[(r, "2005", "ELCTECOA00", "CAPFLO", "ELCCOA")] = 2.0
        ffx[(r, "2005", "ELCTECOA00", "NRG", "ELC")] = 3.0
        ffx[(r, "2004", "ELCTECOA00", "NRG", "ELC")] = 2.5
        ffx[(r, "2010", "ELCTECOA00", "ACT", "ELC")] = 2.0
        ffx[(r, "2010", "ELCTECOA00", "NRG", "ELCCO2")] = 1.0
        ffx[(r, "2015", "ELCTECOA00", "NRG", "ELCCO2")] = 1000.0
        ffx[(r, "0", "ELCTECOA00", "ACT", "ELC")] = 2.0
        ffx[(r, "2030", "COTNCOA1", "NRG", "ELC")] = 2.0
        ffx[(r, "2050", "COTNCOA1", "NRG", "ELC")] = 2.0
        ffx[(r, "2030", "COTNCOA1", "CAPFLO", "NRG")] = 2.0
        gput!(tm, "FLO_FUNCX", ffx)
        ff = gvalues(tm, "FLO_FUNC", 6)
        for (y, x) in (("2015", 2.0), ("2020", 2.2), ("2030", 2.4), ("2050", 2.6))
            ff[(r, y, "ELCTNGAS01", "NRG", "ELC", "ANNUAL")] = x
        end
        gput!(tm, "FLO_FUNC", ff)
    elseif name == "cpt"
        cpx = gvalues(tm, "NCAP_CPX", 3)
        cpx[(r, "2010", "ELCTNGAS01")] = 2.0
        cpx[(r, "2015", "ELCTNGAS01")] = 3.0
        cpx[(r, "2030", "ELCTNGAS01")] = 2.0
        cpx[(r, "2004", "ELCTECOA00")] = 2.0
        cpx[(r, "2005", "ELCTECOA00")] = 1.0
        cpx[(r, "2010", "ELCTECOA00")] = 1000.0
        cpx[(r, "2050", "COTNCOA1")] = 2.0
        cpx[(r, "2030", "COTNCOA1")] = 3.0
        gput!(tm, "NCAP_CPX", cpx)
    else
        error("unknown coef_shp case $name")
    end
    return tm
end

"What coef_shp.mod writes, compared after it (scripts/m12_probe.jl)."
const COEF_SHP_OUTPUTS = ["OPYEAR", "AGEJ", "Z", "FLO_FUNCX", "NCAP_CPX", "RTP_CAPYR", "RTP_FFCX", "RTP_CPX", "COEF_CPT",
                          "PRC_YMIN", "PRC_YMAX", "TRACKP", "RVPRL", "RP_GRP", "RTP_CGC", "COEF_CAP", "COEF_CIO",
                          "RPC_CONLY", "PASTSUM", "FIL2", "COEF_OCOM", "COEF_RCOM"]

"Symbols coef_shp.mod declares itself (L10-11)."
const COEF_SHP_DECLARED = Set(["RTP_FFCX", "AGEJ"])
