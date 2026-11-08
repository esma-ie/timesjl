# Crafted states for preppm.mod L1-212 (v4.9.7): the TIMES_Demo demo12 init
# checkpoint (test/fixtures/demo12_off_init) given the data and options no
# core reference run has, so that the interpolation paths the core models do
# not reach are checked against ppmain.mod L1-247 and preppm.mod L1-212 run
# by GAMS itself (scripts/make_preppm_unit.jl, test/unit/test_m13_preppm.jl).
#
# demo12: milestones 2005 (period 2005-2007), 2010 (2008-2012), 2015
# (2013-2017), 2020 (2018-2025), 2030 (2026-2040), 2050 (2041-2052); DATAYEAR
# 1960, 1980 and every year 2005-2050, PASTYEAR 1960, 1980, 2004, so MODLYEAR
# (V) is the milestones and 1960, 1980, 2004, and PASTMILE is 1960, 1980,
# 2004. The REG1 processes used below (COTE*, CSHE*, FTE-*, ELC*) have RTP in
# every milestone; CSHNOIL1 and the other new technologies start in 2010.

using TIMES: TimesModel, gvalues, gmembers, gput!, register_uel!
import TOML

"""
The cases run by GAMS:

- "fill_opts": fillparm.gms. NCAP_AFA(REG1,..,'LO') (a write cache, RTP)
  with each option: none, -1, 1, 2, 3, 4, 5, 11, 15, exponential beyond
  2020, an EPS first point, a single point, a past year, a process without
  RTP in 2005, an option without data, data only on a year outside DATAYEAR;
  COM_IE (no cache) with none, 2, 5, -2, exponential beyond 2015 and EPS
  only; NCAP_CDME (no cache, RVP) on CAPEELC made vintaged, from 1980.
- "prep_opts": prepparm.gms. ACT_BND(REG1,..,'ANNUAL','LO') with the default
  10 (years inside a period moved to its milestone), 1-5, 12, 13, 15 (the
  MIYR_1 rule), -13, -1, exponential, EPS and 0.4 options, and a process
  without RTP in 2005; NCAP_BND with INT_DEFAULT (CNT 3); COM_BNDNET (no
  cache); FLO_SHAR of the vintaged CAPEELC through L192 and the PASTMILE pass
  of L211 (options none, 2, -1); FLO_MARK (DEF_IEBD 3) and PRC_MARK (11) with
  the L31-32 merge; DAM_COST (%7 EPS) with options none, EPS and 2; the cost
  prepparm on NCAP_COST with options 5, 0.3, 10 (stale scratch), 1 and 2.
- "costs_uc_ret": COM_CSTNET/TAXNET/SUBNET/SUBPRD into OBJ_COMNT/OBJ_COMPD
  (one year outside DATAYEAR), UC_COMPRD/COMCON/COMNET into UC_COM with a
  UC_ATTR NET and an external region, FLO_TAX/FLO_SUB with OBJ_VFLO (the
  default option 3), G_RFRIR and UC_TIME (filparam.gms), PRC_SIMV on
  ELCTNGAS01 (fillvint.gms L15-19), and prepret.dsc: RCAP_BND (option 4),
  PRC_RCAP (the 'N' option), RCAP_BLK, RCAP_OCAP (one deleted at L37),
  PRC_REFIT with a positive and a negative refit (NCAP_ILED made negative,
  TRACKP) and NCAP_OLIFE (NCAP_ELIFE, PRC_CAP cleared).
- "nointerp": G_NOINTERP = 1: fillparm does nothing, prepparm clears
  INT_DEFAULT for its parameter.
- "curex": preppm.mod L27-28 with curex.gms (M1.3 change 26). Currencies
  MUSD, MGBP and MJPY besides MEuro05; REG1 discounts in MEuro05 and MUSD.
  G_CUREX MUSD->MEuro05 0.9, MGBP->MEuro05 1.15 and ->MUSD 1.3, MJPY->MUSD
  0.007, and MEuro05->MEuro05 (L18 clears it); REG2's own MUSD->MEuro05 0.8.
  So in REG1 MUSD goes to MEuro05 and leaves RDCUR, MGBP has two targets and
  none of its own (dropped), MJPY reaches MEuro05 by the chain of L29-32; in
  REG2 MUSD and MGBP go to MEuro05, MJPY nowhere. Costs with a temporary
  attribute (NCAP_COST: an option record carried over, an option -13
  series removed by L77, EPS, a dropped and a chained currency; FLO_COST,
  COM_CSTNET into OBJ_COMNT, DAM_COST) and without one (ACT_CSTUP summed
  with its MEuro05 record and an MGBP record removed by L82, ACT_CSTRMP at
  REG2's own rate, REG_BNDCST).
"""
const PREPPM_CASES = ["fill_opts", "prep_opts", "costs_uc_ret", "nointerp", "curex"]

function preppm_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_init"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    preppm_case!(tm, name)
    return tm
end

const E0 = 0.0                                                   # a stored 0.0 is EPS

function preppm_case!(tm, name)
    put!(n, N, kv...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, kv); gput!(tm, n, v))
    add!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> push!(s, k), ks); gput!(tm, n, s))
    afa(p, kv...) = [("REG1", y, p, "LO") => x for (y, x) in kv]
    bnd(p, kv...) = [("REG1", y, p, "ANNUAL", "LO") => x for (y, x) in kv]
    if name == "fill_opts"
        put!("NCAP_AFA", 4, afa("COTEBIO", "2008" => 0.2, "2025" => 0.6)..., afa("COTECOA", "0" => -1.0, "2010" => 0.5)...,
             afa("COTEELC", "0" => 1.0, "2012" => 0.1, "2031" => 0.4)..., afa("COTEGAS", "0" => 2.0, "2012" => 0.1, "2031" => 0.4)...,
             afa("COTEOIL", "0" => 3.0, "2008" => 0.3, "2040" => 0.6)..., afa("CSHEBIO", "0" => 4.0, "2008" => 0.3, "2040" => 0.6)...,
             afa("CSHECOA", "0" => 5.0, "2008" => 0.3, "2040" => 0.6)..., afa("CSHEELC", "0" => 11.0, "2008" => 0.3, "2040" => 0.6)...,
             afa("CSHEGAS", "0" => 15.0, "2008" => 0.3, "2040" => 0.6)...,
             afa("CSHEOIL", "0" => 2020.0, "2005" => 0.5, "2015" => 0.6, "2030" => 0.02, "2045" => 0.01)...,
             afa("CSHESOL", "2010" => E0, "2030" => 0.5)..., afa("ELCNENUC00", "2015" => 0.7)...,
             afa("ELCREBIO00", "1980" => 0.3, "2020" => 0.5)..., afa("CSHNOIL1", "2015" => 0.4)...,
             afa("ELCRESOL00", "0" => 2.0)..., afa("ELCREWIN00", "2003" => 0.9)...)
        ie(c, kv...) = [("REG1", y, c, "ANNUAL") => x for (y, x) in kv]
        put!("COM_IE", 4, ie("DAOT", "2008" => 0.9, "2040" => 0.95)..., ie("DCAP", "0" => 2.0, "2012" => 0.8)...,
             ie("DCOT", "0" => 5.0, "2007" => 0.7, "2022" => 0.8)..., ie("DCSH", "0" => 2015.0, "2005" => 0.5, "2010" => 0.6, "2030" => 0.01)...,
             ie("DIDM1", "2010" => E0)..., ie("DRAP", "0" => -2.0, "2012" => 0.3)...)
        add!("PRC_VINT", 2, ("REG1", "CAPEELC"))
        put!("NCAP_CDME", 3, ("REG1", "1980", "CAPEELC") => 1.0, ("REG1", "2020", "CAPEELC") => 2.0)
    elseif name == "prep_opts"
        put!("ACT_BND", 5, bnd("FTE-AGRBIO", "2008" => 1.0, "2012" => 3.0, "2027" => 5.0, "2043" => 7.0, "2050" => 8.0)...,
             bnd("FTE-AGRCOA", "0" => 1.0, "2008" => 1.0, "2027" => 4.0)..., bnd("FTE-AGRELC", "0" => 2.0, "2008" => 1.0, "2027" => 4.0)...,
             bnd("FTE-AGRGAS", "0" => 3.0, "2008" => 1.0, "2027" => 4.0)..., bnd("FTE-AGROIL", "0" => 4.0, "2008" => 1.0, "2027" => 4.0)...,
             bnd("FTE-COMBIO", "0" => 5.0, "2008" => 1.0, "2027" => 4.0)..., bnd("FTE-COMCOA", "0" => 15.0, "2006" => 2.0, "2027" => 4.0)...,
             bnd("FTE-COMELC", "0" => 13.0, "2006" => 2.0, "2027" => 4.0)..., bnd("FTE-AGRBIO", "0" => E0)...,
             bnd("FTE-COMGAS", "0" => -13.0, "2010" => 1.0, "2015" => 2.0, "2020" => E0, "2012" => 3.0)...,
             bnd("FTE-COMOIL", "0" => -1.0, "2012" => 3.0)..., bnd("FTE-COMSOL", "0" => 2020.0, "2010" => 1.0, "2015" => 2.0, "2030" => 0.05)...,
             bnd("FTE-ELCBIO", "0" => E0, "2012" => 3.0)..., bnd("FTE-ELCCOA", "0" => 0.4, "2012" => 3.0, "2033" => 1.0)...,
             bnd("FTE-ELCGAS", "0" => 12.0, "2006" => 2.0, "2027" => 4.0)..., bnd("CSHNOIL1", "0" => 3.0, "2010" => 1.0, "2020" => 2.0)...)
        add!("INT_DEFAULT", 1, ("NCAP_BND",))
        put!("NCAP_BND", 4, ("REG1", "2012", "COTEBIO", "LO") => 1.0, ("REG1", "2027", "COTEBIO", "LO") => 2.0)
        put!("COM_BNDNET", 5, ("REG1", "2006", "DAOT", "ANNUAL", "LO") => 1.0, ("REG1", "2033", "DAOT", "ANNUAL", "LO") => 2.0)
        add!("PRC_VINT", 2, ("REG1", "CAPEELC"))
        shar(bd, kv...) = [("REG1", y, "CAPEELC", "COMELC", "COMELC", "ANNUAL", bd) => x for (y, x) in kv]
        put!("FLO_SHAR", 7, shar("LO", "1980" => 0.3, "2012" => 0.5)..., shar("UP", "0" => 2.0, "1980" => 0.6, "2015" => 0.7)...,
             shar("FX", "0" => -1.0, "2012" => 0.4)...)
        mark(p, c, bd, kv...) = [("REG1", y, p, c, bd) => x for (y, x) in kv]
        put!("FLO_MARK", 5, mark("ELCTNOIL01", "ELC", "UP", "2010" => 0.3, "2020" => 0.5)..., mark("CSHEELC", "ELC", "UP", "2010" => 0.3)...,
             mark("ELCTNOIL01", "ELC", "LO", "0" => 5.0, "2015" => 0.2)...)
        pmark(i, bd, kv...) = [("REG1", y, "ELCTNOIL01", i, "ELC", bd) => x for (y, x) in kv]
        put!("PRC_MARK", 6, pmark("ELCTNOIL01", "LO", "2015" => 0.4)..., pmark("ELCTNOIL01", "UP", "2015" => 0.4)...,
             pmark("ELCTEGAS00", "UP", "2006" => 0.1, "2027" => 0.3)...)
        dam(c, kv...) = [("REG1", y, c, "MEuro05") => x for (y, x) in kv]
        put!("DAM_COST", 4, dam("TOTCO2", "2010" => 10.0, "2030" => 20.0)..., dam("ELCCO2", "0" => E0, "2015" => 5.0)...,
             dam("COMCO2", "0" => 2.0, "2020" => 3.0)...)
        cost(p, kv...) = [("REG1", y, p, "MEuro05") => x for (y, x) in kv]
        put!("NCAP_COST", 4, cost("COTEBIO", "0" => 5.0, "2010" => 100.0, "2030" => 200.0)...,
             cost("COTECOA", "0" => 0.3, "2010" => 1.0, "2030" => 2.0)..., cost("COTEELC", "0" => 10.0, "2015" => 7.0)...,
             cost("COTEGAS", "0" => 1.0, "2010" => 5.0, "2030" => 6.0)..., cost("COTEOIL", "0" => 2.0, "2010" => 5.0, "2030" => 6.0)...)
    elseif name == "costs_uc_ret"
        cs(c, ct...) = [("REG1", y, c, "ANNUAL", "MEuro05") => x for (y, x) in ct]
        put!("COM_CSTNET", 5, cs("DAOT", "2010" => 5.0, "2003" => 7.0)...)
        put!("COM_TAXNET", 5, cs("DAOT", "0" => 5.0, "2010" => 1.0, "2030" => 2.0)...)
        put!("COM_SUBNET", 5, cs("DAOT", "2010" => 2.0)...)
        put!("COM_SUBPRD", 5, cs("DCAP", "2020" => E0)...)
        put!("UC_COMCON", 6, ("UC_RNW-PP_LOW", "LHS", "REG1", "2020", "ELC", "ANNUAL") => 0.5)
        put!("UC_COMNET", 6, ("AU_NUC_MaxCAP", "RHS", "REG2", "2030", "ELC", "ANNUAL") => 4.0)
        put!("UC_COMPRD", 6, ("UC_RNW-PP_LOW", "LHS", "IMPEXP", "2020", "ELC", "ANNUAL") => 1.0)
        register_uel!(tm.data, "NET")
        add!("UC_ATTR", 5, ("REG1", "UC_RNW-PP_LOW", "LHS", "COMPRD", "NET"))
        put!("FLO_TAX", 6, ("REG1", "2010", "ELCTNOIL01", "ELC", "ANNUAL", "MEuro05") => 1.0,
             ("REG1", "2030", "ELCTNOIL01", "ELC", "ANNUAL", "MEuro05") => 2.0, ("REG1", "2010", "ELCTNOIL01", "ELCOIL", "ANNUAL", "MEuro05") => 3.0)
        put!("FLO_SUB", 6, ("REG1", "2015", "ELCTNOIL01", "ELC", "ANNUAL", "MEuro05") => 0.5)
        put!("G_RFRIR", 2, ("REG1", "2010") => 0.03, ("REG1", "2030") => 0.05, ("REG2", "0") => 1.0, ("REG2", "2005") => 0.02,
             ("REG2", "2020") => 0.04)
        put!("UC_TIME", 3, ("AU_NUC_MaxCAP", "REG1", "2010") => 1.0, ("AU_NUC_MaxCAP", "REG1", "2030") => 3.0,
             ("UC_RNW-PP_LOW", "REG2", "0") => 2.0, ("UC_RNW-PP_LOW", "REG2", "2015") => 5.0)
        add!("PRC_SIMV", 2, ("REG1", "ELCTNGAS01"))
        register_uel!(tm.data, "N")
        put!("RCAP_BND", 4, ("REG1", "0", "COTEBIO", "UP") => 4.0, ("REG1", "2010", "COTEBIO", "UP") => 5.0,
             ("REG1", "2030", "COTEBIO", "UP") => 7.0)
        add!("PRC_RCAP", 2, ("REG1", "COTECOA"))
        put!("RCAP_BLK", 3, ("REG1", "2015", "COTEBIO") => 2.0)
        put!("RCAP_OCAP", 4, ("REG1", "2010", "COTEBIO", "COMELC") => 10.0, ("REG1", "2010", "COTEGAS", "COMGAS") => 10.0)
        put!("PRC_REFIT", 3, ("REG1", "COTEELC", "COTNELC1") => 1.0, ("REG1", "COTEOIL", "COTNOIL1") => -2.0)
        put!("NCAP_ILED", 3, ("REG1", "2015", "COTNELC1") => 1.0)
        put!("NCAP_OLIFE", 3, ("REG1", "2010", "CSHEBIO") => 20.0)
    elseif name == "curex"
        foreach(c -> register_uel!(tm.data, c), ("MUSD", "MGBP", "MJPY"))
        add!("CUR", 1, ("MUSD",), ("MGBP",), ("MJPY",))
        put!("G_DRATE", 3, ("REG1", "2005", "MUSD") => 0.05)
        put!("G_CUREX", 2, ("MUSD", "MEuro05") => 0.9, ("MGBP", "MEuro05") => 1.15, ("MGBP", "MUSD") => 1.3,
             ("MJPY", "MUSD") => 0.007, ("MEuro05", "MEuro05") => 2.0)
        put!("R_CUREX", 3, ("REG2", "MUSD", "MEuro05") => 0.8)
        nc(p, c, kv...) = [("REG1", y, p, c) => x for (y, x) in kv]
        put!("NCAP_COST", 4, nc("COTEBIO", "MEuro05", "2010" => 100.0, "2030" => 200.0)..., nc("COTEBIO", "MUSD", "0" => 5.0, "2010" => 50.0)...,
             nc("COTECOA", "MUSD", "0" => -13.0, "2010" => 1.0, "2030" => 2.0)..., nc("COTEELC", "MGBP", "2015" => 7.0)...,
             nc("COTEGAS", "MJPY", "2010" => 1000.0)..., nc("COTEOIL", "MUSD", "2010" => E0)...,
             ("REG2", "2010", "ELCTEGAS00", "MGBP") => 20.0, ("REG2", "2020", "ELCTEGAS00", "MUSD") => 10.0)
        put!("FLO_COST", 6, ("REG1", "2010", "ELCTNOIL01", "ELC", "ANNUAL", "MUSD") => 2.0)
        put!("COM_CSTNET", 5, ("REG1", "2010", "DAOT", "ANNUAL", "MUSD") => 10.0, ("REG1", "2010", "DAOT", "ANNUAL", "MEuro05") => 1.0)
        put!("DAM_COST", 4, ("REG1", "2010", "TOTCO2", "MUSD") => 10.0)
        put!("ACT_CSTUP", 5, ("REG1", "2010", "ELCTEGAS00", "DAYNITE", "MUSD") => 10.0,
             ("REG1", "2010", "ELCTEGAS00", "DAYNITE", "MEuro05") => 1.0, ("REG1", "2020", "ELCTEGAS00", "DAYNITE", "MGBP") => 3.0)
        put!("ACT_CSTRMP", 5, ("REG2", "2010", "ELCTEGAS00", "UP", "MUSD") => 4.0)
        put!("REG_BNDCST", 5, ("REG2", "2020", "INV", "MGBP", "UP") => 100.0, ("REG2", "2020", "INV", "MEuro05", "UP") => 50.0)
    elseif name == "nointerp"
        put!("G_NOINTERP", 0, () => 1.0)
        put!("NCAP_AFA", 4, afa("COTEGAS", "0" => 2.0, "2012" => 0.1, "2031" => 0.4)...)
        add!("INT_DEFAULT", 1, ("ACT_BND",))
        put!("ACT_BND", 5, bnd("FTE-AGRELC", "0" => 2.0, "2008" => 1.0, "2027" => 4.0)...)
    else
        error("unknown preppm case $name")
    end
    return tm
end

"Symbols tested with `\$IF DEFINED` in ppmain.mod L1-247 and preppm.mod L1-212 that a TIMES run declares without data."
const PREPPM_BARE = ["G_CUREX", "R_CUREX", "DAM_COST", "PRC_SIMV", "PRC_REFIT", "NCAP_OLIFE", "RCAP_BND", "PRC_RCAP", "G_OFFTHD"]

"What preppm.mod L1-212 writes, compared after it (scratch included)."
const PREPPM_OUTPUTS = vcat(["MODLYEAR", "DATAYEAR", "DM_YEAR", "FIL2", "MY_FIL", "OBJ_VFLO", "RPC_CUR", "IE_DEFAULT", "PRC_YMIN", "PASTSUM",
                             "PRC_SIMV", "PRC_VINT", "G_RFRIR", "UC_TIME", "RCAP_BND", "PRC_RCAP", "RCAP_BLK", "RCAP_OCAP", "NCAP_OLIFE",
                             "RTP_VARP", "PRC_CAP", "INT_DEFAULT", "RTP", "RVP", "TRACKP", "UNCD7", "MY_ARRAY", "MY_FIL2",
                             "CNT", "DFUNC", "MY_F", "F", "Z", "LAST_VAL", "FIRST_VAL", "MY_FYEAR"], TIMES.PREPPM_PARAMS)

"What curex.gms (preppm.mod L27-28) writes besides `PREPPM_OUTPUTS`, compared in the \"curex\" case only."
const CUREX_OUTPUTS = ["R_CUREX", "RDCUR", "CURMAP", "RXX", "COM_BPRICE", "COM_CSTNET", "COM_TAXNET", "COM_SUBNET", "COM_CSTPRD",
                       "COM_TAXPRD", "COM_SUBPRD", "REG_CUMCST", "ACT_CSTPL"]

"The outputs compared for a crafted case."
preppm_outputs(name) = name == "curex" ? vcat(PREPPM_OUTPUTS, CUREX_OUTPUTS) : PREPPM_OUTPUTS
