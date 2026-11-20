# Crafted states for preppm.mod L213-217 (v4.9.7), prep_ext.vda with
# equcrtp.vda PREP_EXT: the TIMES_Demo demo12 init checkpoint
# (test/fixtures/demo12_off_init) given the data no core reference run has,
# so that the paths the core models do not reach are checked against
# ppmain.mod L1-247, preppm.mod L1-212 and prep_ext.vda run by GAMS itself
# (scripts/make_prep_ext_unit.jl, test/unit/test_m13_prep_ext.jl).
#
# demo12 (see preppm_case.jl): milestones 2005, 2010, 2015, 2020, 2030, 2050
# (periods 2005-2007, 2008-2012, 2013-2017, 2018-2025, 2026-2040, 2041-2052),
# PYR_S 2004, G_TLIFE 10. The REG1 processes used have RTP from 2004 on, but
# CSHNOIL1 and ELCTNGAS01 from 2010; ELCTNGAS01 is vintaged. Every demo12
# process has a PRC_RESID '0' record, so demo12 itself runs the one-point
# run-down of L59-62.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!, register_uel!
import TOML

"""
The cases run by GAMS:

- "vda_resid": PRC_RESID (L47-69) with several points and no option
  (COTEBIO), option 5 (COTECOA), option 15 on one point (COTEGAS), a year as
  the '0' value (ELCTECOA00: PRC_YMAX), the one-point run-down over
  NCAP_TLIFE (CSHEBIO) and over G_TLIFE (CSHNOIL1, no NCAP_TLIFE at 2004),
  and a '0' record without data (ELCREWIN00); NCAP_AFAC over NCAP_AFC (L13,
  an option -1 on ACT), NCAP_AFCS (L14), an NCAP_AFC option -1 off ACT
  (skipped, L25); ACT_EFF groups with a negative and an EPS value (RPG_1ACE,
  L19) and an option 3 (write cache); VDA_FLOP into ACT_FLO (L21: STOA
  timeslices, the last year wins, a group (NRG) and ANNUAL left out; ACT is a demo12 commodity); FLO_EMIS
  with option 2; FLO_FUNCX of a vintaged and a non-vintaged process and of a group (L44).
- "uc_bounds": ACT_UPS (ANNUAL FX into ACT_MINLD, L74), ACT_LOSPL,
  ACT_LOSSD, ACT_SDTIME, ACT_MAXNON, STG_MAXCYC, UC_FLOBET and COM_CSTBAL
  (L29-36); COM_LIM 'FX' over LO/UP (L72); RCAP_OCAP into RPC_CAPFLO (L76,
  with RCAP_BND so that prepret.dsc defines VNRET); non-standard FLO_SHAR
  into FLO_ASHAR (L78); NCAP_BND 'N' (L80-83): one year in a period, two
  years of one period summed, an INF upper bound removed, NCAP_ILED kept in
  COEF_ILED.
- "dynuc": equcrtp.vda PREP_EXT: PRC_DYNUC with LHS only (CAP), RHS only
  (NCAP, ACT), both with options (RHS 15), the first period of a process
  that starts in 2010 (L57), UC_DYNBND (UC_T_SUCC, L61).
"""
const PREP_EXT_CASES = ["vda_resid", "uc_bounds", "dynuc"]

function prep_ext_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_init"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    prep_ext_case!(tm, name)
    return tm
end

const PE_EPS = 0.0                                                # a stored 0.0 is EPS

function prep_ext_case!(tm, name)
    put!(n, N, kv...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, kv); gput!(tm, n, v))
    add!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> push!(s, k), ks); gput!(tm, n, s))
    drop!(n, N, f) = (v = gvalues(tm, n, N); filter!(((k, _),) -> !f(k), v); gput!(tm, n, v))
    if name == "vda_resid"
        res(p, kv...) = [("REG1", y, p) => x for (y, x) in kv]
        procs = ("COTEBIO", "COTECOA", "COTEGAS", "ELCTECOA00", "CSHEBIO", "CSHNOIL1", "ELCREWIN00")
        drop!("PRC_RESID", 3, k -> k[3] in procs)
        put!("PRC_RESID", 3, res("COTEBIO", "0" => PE_EPS, "2005" => 10.0, "2015" => 6.0, "2030" => 2.0)...,
             res("COTECOA", "0" => 5.0, "2005" => 100.0, "2015" => 80.0)..., res("COTEGAS", "0" => 15.0, "2010" => 40.0)...,
             res("ELCTECOA00", "0" => 2030.0, "2005" => 50.0)..., res("CSHEBIO", "0" => PE_EPS, "2005" => 3.0)...,
             res("CSHNOIL1", "0" => PE_EPS, "2010" => 5.0)..., res("ELCREWIN00", "0" => PE_EPS)...)
        put!("NCAP_AFAC", 4, ("REG1", "2010", "COTEBIO", "ACT") => 0.7, ("REG1", "2030", "COTEBIO", "ACT") => 0.8,
             ("REG1", "0", "COTECOA", "ACT") => -1.0, ("REG1", "2010", "COTECOA", "ACT") => 0.6)
        put!("NCAP_AFC", 5, ("REG1", "2020", "COTEBIO", "ACT", "ANNUAL") => 0.5, ("REG1", "0", "CSHEGAS", "NRG", "ANNUAL") => -1.0,
             ("REG1", "2010", "CSHEGAS", "NRG", "ANNUAL") => 0.9)
        put!("NCAP_AFCS", 5, ("REG1", "2015", "CSHEBIO", "ACT", "S") => 0.6, ("REG1", "2015", "CSHEBIO", "ACT", "W") => 0.4)
        eff(p, c, kv...) = [("REG1", y, p, c, "ANNUAL") => x for (y, x) in kv]
        put!("ACT_EFF", 5, eff("CAPEELC", "COMELC", "2010" => -0.2)..., eff("CSHEELC", "COMELC", "2010" => PE_EPS)...,
             eff("COTEBIO", "COMBIO", "0" => 3.0, "2010" => 1.1, "2030" => 1.3)...)
        put!("VDA_FLOP", 5, ("REG1", "2010", "CSHEELC", "COMELC", "S") => 0.3, ("REG1", "2030", "CSHEELC", "COMELC", "S") => 0.5,
             ("REG1", "2010", "CSHEELC", "COMELC", "ANNUAL") => 0.2, ("REG1", "2010", "CSHEELC", "NRG", "S") => 0.1)
        put!("FLO_EMIS", 6, ("REG1", "0", "COTEGAS", "COMGAS", "COMCO2", "ANNUAL") => 2.0,
             ("REG1", "2010", "COTEGAS", "COMGAS", "COMCO2", "ANNUAL") => 0.05, ("REG1", "2030", "COTEGAS", "COMGAS", "COMCO2", "ANNUAL") => 0.07)
        put!("FLO_FUNCX", 5, ("REG1", "2010", "COTEGAS", "COMGAS", "COMCO2") => 1.0, ("REG1", "2010", "ELCTNGAS01", "ELCGAS", "ELCCO2") => 1.0,
             ("REG1", "2010", "COTEGAS", "NRG", "COMCO2") => 1.0)
    elseif name == "uc_bounds"
        register_uel!(tm.data, "PRD")
        put!("ACT_UPS", 5, ("REG1", "2010", "ELCTEGAS00", "ANNUAL", "FX") => 0.3, ("REG1", "2030", "ELCTEGAS00", "ANNUAL", "FX") => 0.4,
             ("REG1", "0", "ELCTECOA00", "S", "UP") => 2.0, ("REG1", "2015", "ELCTECOA00", "S", "UP") => 0.5)
        put!("ACT_LOSPL", 4, ("REG1", "2010", "ELCTEGAS00", "FX") => 0.2)
        put!("ACT_LOSSD", 5, ("REG1", "2010", "ELCTEGAS00", "COLD", "UP") => 1.5, ("REG1", "2030", "ELCTEGAS00", "COLD", "UP") => 2.5)
        put!("ACT_SDTIME", 5, ("REG1", "2020", "ELCTEGAS00", "HOT", "LO") => 3.0)
        put!("ACT_MAXNON", 4, ("REG1", "2015", "ELCTEGAS00", "WARM") => 10.0)
        put!("STG_MAXCYC", 3, ("REG1", "2010", "ELCTEGAS00") => 100.0)
        put!("UC_FLOBET", 5, ("UC_RNW-PP_LOW", "REG1", "2010", "ELCTEGAS00", "ELC") => 0.5, ("UC_RNW-PP_LOW", "REG1", "2030", "ELCTEGAS00", "ELC") => 0.7)
        put!("COM_CSTBAL", 6, ("REG1", "2010", "ELC", "ANNUAL", "PRD", "MEuro05") => 2.0, ("REG1", "2030", "ELC", "ANNUAL", "PRD", "MEuro05") => 4.0)
        add!("COM_LIM", 3, ("REG1", "DAOT", "FX"), ("REG1", "DAOT", "LO"), ("REG1", "DAOT", "UP"), ("REG1", "ELC", "LO"))
        put!("RCAP_BND", 4, ("REG1", "2010", "COTEBIO", "UP") => 5.0)
        put!("RCAP_OCAP", 4, ("REG1", "2010", "COTEBIO", "COMBIO") => 10.0)
        shar(c, cg, bd, x) = ("REG1", "2010", "COTEGAS", c, cg, "ANNUAL", bd) => x
        put!("FLO_SHAR", 7, shar("COMGAS", "NRG", "UP", 0.6), shar("COMGAS", "DCOT", "LO", 0.3), shar("ELC", "NRG", "UP", 0.2))
        register_uel!(tm.data, "N")
        put!("NCAP_BND", 4, ("REG1", "2012", "COTEGAS", "N") => 2012.0, ("REG1", "2010", "COTEGAS", "UP") => Inf,
             ("REG1", "2014", "COTECOA", "N") => 2016.0, ("REG1", "2016", "COTECOA", "N") => 2016.0)
        put!("NCAP_ILED", 3, ("REG1", "2010", "COTEGAS") => 2.0)
    elseif name == "dynuc"
        dy(u, s, p, g, bd, kv...) = [(u, s, "REG1", y, p, g, bd) => x for (y, x) in kv]
        a, b = "AU_NUC_MaxCAP", "UC_RNW-PP_LOW"
        put!("PRC_DYNUC", 7, dy(a, "LHS", "ELCNENUC00", "CAP", "UP", "2010" => 1.1, "2030" => 1.2)...,
             dy(a, "RHS", "ELCREWIN00", "NCAP", "UP", "2010" => 100.0, "2020" => 150.0)...,
             dy(a, "RHS", "ELCREBIO00", "ACT", "LO", "2015" => 50.0)...,
             dy(b, "LHS", "ELCRESOL00", "CAP", "UP", "0" => 2.0, "2010" => 1.05)...,
             dy(b, "RHS", "ELCRESOL00", "CAP", "UP", "0" => 3.0, "2010" => 20.0, "2030" => 30.0)...,
             dy(b, "LHS", "ELCTEGAS00", "CAP", "UP", "2015" => 1.1)..., dy(b, "RHS", "ELCTEGAS00", "CAP", "UP", "2015" => 5.0)...,
             dy(a, "LHS", "CSHNOIL1", "CAP", "UP", "2010" => 1.1)...,
             dy(b, "RHS", "ELCTECOA00", "ACT", "UP", "0" => 15.0, "2012" => 8.0, "2027" => 9.0)...,
             dy(b, "LHS", "ELCTECOA00", "ACT", "UP", "2012" => 1.02)...)
        add!("UC_DYNBND", 2, (a, "UP"))
    else
        error("unknown prep_ext case $name")
    end
    return tm
end

"Symbols tested with `\$IF DEFINED` in ppmain.mod L1-247, preppm.mod L1-212 and prep_ext.vda that a TIMES run declares without data."
const PREP_EXT_BARE = vcat(PREPPM_BARE, ["UC_FLOBET", "COM_CSTBAL", "GR_VARGEN"])

"What ppmain.mod L1-247, preppm.mod L1-212 and prep_ext.vda write, compared after prep_ext.vda (scratch included)."
const PREP_EXT_OUTPUTS = unique!(vcat(PREPPM_OUTPUTS,
    ["NCAP_AFC", "NCAP_AFCS", "RP_GRP", "RPC_ACE", "RPG_1ACE", "ACT_FLO", "VDA_EMCB", "ACT_EFF", "VDA_FLOP", "FLO_EMIS", "ACT_UPS",
     "ACT_LOSPL", "ACT_LOSSD", "ACT_SDTIME", "ACT_MAXNON", "STG_MAXCYC", "UC_FLOBET", "COM_CSTBAL", "PRC_DYNUC", "UC_GMAP_P", "UC_JMAP",
     "UC_T_SUCC", "FLO_FUNCX", "PRC_RESID", "PRC_YMAX", "RTP_CPTYR", "IFQ", "COM_LIM", "ACT_MINLD", "RPC_CAPFLO", "FLO_ASHAR", "RVPRL",
     "COEF_ILED", "MY_SUM"]))
