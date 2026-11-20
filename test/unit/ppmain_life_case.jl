# Crafted states for ppmain.mod L461-611 (v4.9.7): the TIMES_Demo demo12 init
# checkpoint (test/fixtures/demo12_off_init) given the data and switches no
# core reference run has, so that the paths the core models do not reach are
# checked against GAMS running ppmain.mod L1-247 and L249-611, preppm.mod
# L1-212 and L218-252 and prep_ext.vda itself
# (scripts/make_ppmain_life_unit.jl, test/unit/test_m13_ppmain_life.jl).
#
# demo12 (see ppmain_topo_case.jl) runs with OBJ MOD: %CTST% is **0, so
# G_ILEDNO becomes -1 and every lead time is rounded (L478-481), and ALTOBJ is
# 1 (L498-502). Every process has a PRC_RESID and no NCAP_PASTI.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!, gput_scalar!
import TOML

"""
The cases run by GAMS:

- "life": NCAP_TLIFE below 0.5 (set to 1), 0.7 (kept), EPS (set to 1) and
  250 (beyond AGE: QA only) (L465-476); fractional and negative NCAP_ILED
  (L480-481) and past investment on a milestone (PHYR, L482); refits with
  option -5 (NCAP_ELIFE, NCAP_TLIFE of the refit), with option 3 on a host
  with its own option 2 (L485) and on a host in PRC_RCAP (L486-488); CAP_BND
  EPS (RVP: NCAP_BND 'UP' EPS, L533-535), below PRC_RESID (RCAP_BND 'N',
  L526-531), FX (L525), LO INF (MAPVAL, L536) and LO with UP (RTP_VARP,
  L538); NCAP_BND FX EPS on every milestone (RTP_OFF, NO_RVP, RTP,
  L546-551); PRC_AOFF with two ranges (L558-565); PRC_FOFF at ANNUAL and at
  a SEASON timeslice (RTPCS_OUT, L575-581); a PG group with a commodity
  flagged by PRC_ACTFLO '0' < 0 (L593).
- "altobj": OBJ LIN (%CTST% **EPS, ALTOBJ 3): COEF_RPTI with and without
  NCAP_ILED (L498-502) and the relaxed capacity transfer (L511-513).
- "validate": OBJ AUTO (%CTST% empty: G_ILEDNO stays 10, so a lead time
  below a tenth of the period is dropped, L481) with %VALIDATE% YES
  (ALTOBJ 0: L503, L518), and PRC_SIMV (L590). (OBJ MOD with ALTOBJ 0 would
  stop at ppmain.mod L159, as a real run does.)
"""
const PPMAIN_LIFE_CASES = ["life", "altobj", "validate"]

function ppmain_life_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_init"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    ppmain_life_case!(tm, name)
    return tm
end

const PL_EPS = 0.0                                                # a stored 0.0 is EPS

function ppmain_life_case!(tm, name)
    put!(n, N, kv...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, kv); gput!(tm, n, v))
    add!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> push!(s, k), ks); gput!(tm, n, s))
    drop!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> delete!(s, k), ks); gput!(tm, n, s))
    if name == "life"
        put!("NCAP_TLIFE", 3, ("REG1", "2015", "COTEBIO") => 0.3, ("REG1", "2015", "COTECOA") => 0.7, ("REG1", "2015", "COTEGAS") => 250.0,
             ("REG1", "0", "COTEELC") => -1.0, ("REG1", "2020", "COTEELC") => PL_EPS)
        put!("NCAP_ILED", 3, ("REG1", "2010", "CSHEBIO") => 1.4, ("REG1", "2015", "CSHECOA") => -2.0)
        put!("NCAP_PASTI", 3, ("REG1", "0", "CAPEELC") => 1.0, ("REG1", "2009", "COTEBIO") => 3.0, ("REG1", "2010", "COTEBIO") => 0.1)
        put!("PRC_REFIT", 3, ("REG1", "COTEBIO", "CSHEBIO") => -5.0, ("REG1", "COTECOA", "CSHECOA") => 3.0,
             ("REG1", "COTECOA", "COTECOA") => 2.0, ("REG1", "COTEGAS", "CSHEGAS") => 1.0)
        add!("PRC_RCAP", 2, ("REG1", "COTEGAS"))
        put!("CAP_BND", 4, ("REG1", "2010", "COTEGAS", "UP") => PL_EPS, ("REG1", "2015", "ELCTECOA00", "UP") => 0.001,
             ("REG1", "2020", "CSHEOIL", "FX") => 5.0, ("REG1", "2030", "CAPEELC", "LO") => Inf, ("REG1", "2030", "CAPEELC", "UP") => 7.0,
             ("REG1", "2030", "CSHEGAS", "LO") => 1.0, ("REG1", "2030", "CSHEGAS", "UP") => 2.0)
        put!("NCAP_BND", 4, ("REG1", "0", "COTEOIL", "FX") => 3.0, ("REG1", "2005", "COTEOIL", "FX") => PL_EPS)
        add!("PRC_AOFF", 4, ("REG1", "COTEGAS", "2012", "2022"), ("REG1", "COTEGAS", "2045", "EOH"))
        add!("PRC_FOFF", 6, ("REG1", "ELCTECOA00", "ELC", "ANNUAL", "2012", "2016"), ("REG1", "ELCTECOA00", "ELC", "S", "2028", "2032"))
        drop!("PRC_ACTUNT", 4, ("REG1", "ELCTEGAS00", "ELC", "PJ"))
        add!("PRC_ACTUNT", 4, ("REG1", "ELCTEGAS00", "NRG", "PJ"))
        put!("PRC_ACTFLO", 4, ("REG1", "0", "ELCTEGAS00", "ELCGAS") => -1.0)
    elseif name == "altobj"
        tm.switches["OBJ"] = "LIN"
        gput_scalar!(tm, "ALTOBJ", 3.0)
        put!("NCAP_ILED", 3, ("REG1", "2010", "CSHEBIO") => 2.0, ("REG1", "2015", "COTECOA") => 1.0)
        put!("NCAP_TLIFE", 3, ("REG1", "2015", "COTEGAS") => 3.0)
    elseif name == "validate"
        tm.switches["OBJ"] = "AUTO"
        tm.switches["VALIDATE"] = "YES"
        gput_scalar!(tm, "ALTOBJ", 0.0)
        put!("NCAP_ILED", 3, ("REG1", "2010", "CSHEBIO") => 1.4, ("REG1", "2015", "COTECOA") => 0.3)
        add!("PRC_SIMV", 2, ("REG1", "ELCTNGAS01"))
    else
        error("unknown ppmain_life case $name")
    end
    return tm
end

"What ppmain.mod L461-611 writes, besides what the steps before it wrote, compared after ppmain.mod L611 (scratch included)."
const PPMAIN_LIFE_OUTPUTS = unique!(vcat(PPMAIN_TSLVL_OUTPUTS,
    ["NCAP_TLIFE", "G_ILEDNO", "COEF_ILED", "NCAP_ILED", "PRC_REFIT", "RTP_OFF", "NCAP_ELIFE", "COEF_RPTI", "VNT", "YKVAL", "RTP_CPTYR",
     "PASTSUM", "COEF_RTP", "CAP_BND", "RCAP_BND", "NCAP_BND", "RTP_VARP", "RVP", "NO_RVP", "RTP", "RTP_VARA", "MY_FIL", "RTPC",
     "RTPCS_OUT", "RPC_PG", "RP_STD", "RPC_ACT", "CHP", "PRC_CAPACT", "PRC_ACTFLO", "RP_PGACT", "TRACKP", "TRACKPC"]))
