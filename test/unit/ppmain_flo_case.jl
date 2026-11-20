# Crafted states for ppmain.mod L800-821 (v4.9.7): the flow attributes
# levelled by pp_lvlfc.mod, the FLO_PKCOI default and pp_chp.mod. The
# TIMES_Demo demo12 prelv checkpoint (test/fixtures/demo12_off_prelv) is
# given data no core reference run has, and GAMS runs ppmain.mod L616-821
# itself on it (scripts/make_ppmain_flo_unit.jl), so the paths the core
# models do not reach are checked against GAMS
# (test/unit/test_m13_ppmain_flo.jl).
#
# demo12 (REG1): ELCTEGAS00 runs at DAYNITE (SD, SN, WD, WN; RPCS_VAR of
# ELCGAS in, ELC and ELCCO2 out at DAYNITE); FTE-AGRELC, FTE-COMELC,
# FTE-INDELC, FTE-RSDELC and FTE-TRAELC take ELC, the peak commodity, in.
# DATAYEAR is 1960, 1980 and 2004-2050; STOA leads S and W back to ANNUAL.
# No FLO_COST, FLO_DELIV, FLO_SUB, FLO_TAX, FLO_PKCOI, FLO_BDLVL or ACT_FLO
# data, no CHP.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!, gset
import TOML

"""
The cases run by GAMS:

- "flo": FLO_DELIV of ELCTEGAS00's ELCGAS at ANNUAL in 2010 and at S in
  2015 (%11 N: the flag at year '0', ANNUAL copied, S inherited, the
  records off RPCS_VAR deleted), FLO_TAX at W in 2051 (outside DATAYEAR:
  flagged and deleted, not levelled), FLO_SUB EPS at S, FLO_COST at ANNUAL
  alone (no flag: left as it is); FLO_PKCOI at ANNUAL; FLO_BDLVL of the ACT
  and NRG groups at ANNUAL and S and of ELC at S (both calls of L809-810);
  ACT_FLO at ANNUAL (filled, %11 0) and at S (levelled, then deleted);
  FTE-AGRELC in PRC_PKNO (no FLO_PKCOI default), FTE-COMELC with its own
  FLO_PKCOI at ANNUAL (levelled, so no default either).
- "chp": REFEOIL00 made a CHP with DSL and ELC as its primary group
  (REFEOIL00_NRGO, OIL its shadow): NCAP_CHPR UP and LO with NCAP_CDME and
  NCAP_BPME (a slope below 1) in 2010, FX with LO (LO dropped) and no
  NCAP_CDME in 2015, with COM_LIM 'N' on DSL (back-pressure: NCAP_CEH
  -0.5, the DSL ACTFLO from the slope) and FLO_EFF (the ACT flows of L60),
  UP with a slope above 1 in 2020, PRC_PKAF (NCAP_PKCNT per unit of
  electricity, L64); ELCTEGAS00 a CHP with a one-commodity primary group
  (UP in 2010, LO in 2015: the heat share of ELCCO2, L58).
- "chpnrg": "chp" with ELCCO2 in the NRG group, so ELCTEGAS00 gets the
  electricity share over NRG instead (L50-56).
"""
const PPMAIN_FLO_CASES = ["flo", "chp", "chpnrg"]

function ppmain_flo_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_prelv"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    ppmain_flo_case!(tm, name)
    return tm
end

const PF_EPS = 0.0                                                # a stored 0.0 is EPS

function ppmain_flo_case!(tm, name)
    put!(n, N, kv...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, kv); gput!(tm, n, v))
    add!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> push!(s, k), ks); gput!(tm, n, s))
    r, p, cur = "REG1", "ELCTEGAS00", "MEuro05"
    if name == "flo"
        put!("FLO_DELIV", 6, (r, "2010", p, "ELCGAS", "ANNUAL", cur) => 2.0, (r, "2015", p, "ELCGAS", "S", cur) => 3.0)
        put!("FLO_TAX", 6, (r, "2051", p, "ELC", "W", cur) => 1.5)
        put!("FLO_SUB", 6, (r, "2010", p, "ELC", "S", cur) => PF_EPS)
        put!("FLO_COST", 6, (r, "2010", p, "ELCCO2", "ANNUAL", cur) => 0.7)
        put!("FLO_PKCOI", 5, (r, "2010", p, "ELC", "ANNUAL") => 1.1, (r, "2010", "FTE-COMELC", "ELC", "ANNUAL") => 0.9)
        put!("FLO_BDLVL", 6, (r, "2010", p, "ACT", "ANNUAL", "UP") => 0.5, (r, "2015", p, "NRG", "S", "LO") => 0.2,
             (r, "2015", p, "ELC", "S", "LO") => 0.3)
        put!("ACT_FLO", 5, (r, "2010", p, "ELC", "ANNUAL") => 1.2, (r, "2015", p, "ELC", "S") => 1.4)
        add!("PRC_PKNO", 2, (r, "FTE-AGRELC"))
    elseif name in ("chp", "chpnrg")
        q, g = "REFEOIL00", "REFEOIL00_NRGO"
        del!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> delete!(s, k), ks); gput!(tm, n, s))
        del!("RPC_PG", 3, (r, q, "OIL")); add!("RPC_PG", 3, (r, q, "DSL"), (r, q, "ELC"))
        del!("RP_PG", 3, (r, q, "REFEOIL00_NRGI")); add!("RP_PG", 3, (r, q, g))
        del!("RPC_SPG", 3, ((r, q, c) for c in ("DSL", "GSL", "HFO", "KER", "LPG", "NAP", "OPP"))...); add!("RPC_SPG", 3, (r, q, "OIL"))
        del!("RP_PGACT", 2, (r, q)); del!("RPC_ACT", 3, (r, q, "OIL"))
        add!("TOP", 4, (r, q, "ELC", "OUT")); add!("RPC", 3, (r, q, "ELC")); add!("COM_GMAP", 3, (r, g, "ELC"))
        add!("CHP", 2, (r, q), (r, p)); add!("PRC_PKAF", 2, (r, q)); add!("COM_LIM", 3, (r, "DSL", "N"))
        put!("NCAP_CHPR", 4, (r, "2010", q, "UP") => 2.0, (r, "2010", q, "LO") => 0.5, (r, "2015", q, "FX") => 1.5,
             (r, "2015", q, "LO") => 0.3, (r, "2020", q, "UP") => 1.0, (r, "2010", p, "UP") => 0.6, (r, "2015", p, "LO") => 0.2)
        put!("NCAP_CDME", 3, (r, "2010", q) => 0.4, (r, "2020", q) => 0.5)
        put!("NCAP_BPME", 3, (r, "2010", q) => 0.9, (r, "2020", q) => 0.4)
        put!("FLO_EFF", 6, (r, "2015", q, "OIL", "ELC", "ANNUAL") => 0.3)
        name == "chpnrg" && add!("COM_GMAP", 3, (r, "NRG", "ELCCO2"))
    else
        error("unknown ppmain_flo case $name")
    end
    return tm
end

"What ppmain.mod L800-821 writes, on top of ppmain.mod L616-797, compared at L821, scratch included."
const PPMAIN_FLO_NEW = ["FLO_COST", "FLO_DELIV", "FLO_SUB", "FLO_TAX", "FLO_BDLVL", "ACT_FLO", "CHP_ELC", "COEF_RTP", "NCAP_CEH",
                        "FLO_SUM", "PRC_ACT", "RVP", "RP_GRP", "TRACKPG", "RP_PRC", "PRC_ACTFLO", "RPC_ACT"]

"What ppmain.mod L800-821 and the files it includes declare themselves (pp_chp.mod L9)."
const PPMAIN_FLO_DECLARED_NEW = ["CHP_ELC"]
