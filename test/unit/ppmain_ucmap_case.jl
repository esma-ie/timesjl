# Crafted states for ppmain.mod L1181-1226 (v4.9.7): the UC group maps and
# pp_lvlus.mod. The TIMES_Demo demo12 prelv checkpoint
# (test/fixtures/demo12_off_prelv) is given data no core reference run has,
# and GAMS runs ppmain.mod L616-1226 itself on it
# (scripts/make_ppmain_ucmap_unit.jl), so the paths the core models do not
# reach are checked against GAMS (test/unit/test_m13_ppmain_ucmap.jl).
#
# demo12, REG1: ELCTECOA00 and ELCTNCOA01 at SEASON level, ELCTEGAS00 at
# DAYNITE, most others ANNUAL; ELC at DAYNITE, GAS at ANNUAL; IMPELC1 and
# IMPGAS1 trade processes; S and W the seasons, SD SN WD WN the day-nights.
# Two UCs are added, UC_X3 and UC_X4.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!, register_uel!
import TOML

"""
The case run by GAMS:

- "ucmap": UC_X3 (RHS by UC_RHSRT in REG1) with UC_ACT of a SEASON process
  at DAYNITE (aggregated, pp_lvlus.mod L24-30) and at ANNUAL (copied down,
  L39), UC_ACT of a DAYNITE process at SEASON (inherited, L31-36), UC_FLO
  of a SEASON process's ELC at DAYNITE (aggregated, %9 PRC_SGL) and of a
  trade process (UC_QAFLO '1', ppmain.mod L1188-1190), UC_IRE of a trade
  process at SEASON (aggregated) and of a non-trade process (UC_QAFLO '2',
  L1192-1193), UC_COM NET of GAS at SEASON (aggregated) and PRD of ELC at
  ANNUAL (copied down), a COMCON group with a dynamic attribute (L1195), and
  UC_CAP (RTP_VARP, L1204-1205); UC_X4 by UC_DYNBND only (UC_ON, L1207) with
  UC_COM PRD of ELC in REG2 (RXX, RHS_COMPRD, RHS_COMBAL, L1208-1212).
"""
const PPMAIN_UCMAP_CASES = ["ucmap"]

function ppmain_ucmap_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_prelv"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    ppmain_ucmap_case!(tm, name)
    return tm
end

function ppmain_ucmap_case!(tm, name)
    put!(n, N, kv...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, kv); gput!(tm, n, v))
    add!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> push!(s, k), ks); gput!(tm, n, s))
    name == "ucmap" || error("unknown ppmain_ucmap case $name")
    r, x3, x4 = "REG1", "UC_X3", "UC_X4"
    foreach(l -> register_uel!(tm.data, l), (x3, x4))
    add!("UC_N", 1, (x3,), (x4,))
    put!("UC_RHSRT", 4, (r, x3, "2010", "UP") => 10.0)
    put!("UC_ACT", 6, (x3, "LHS", r, "2010", "ELCTECOA00", "SD") => 2.0, (x3, "LHS", r, "2010", "ELCTECOA00", "WD") => 4.0,
         (x3, "LHS", r, "2020", "ELCTECOA00", "ANNUAL") => 1.5, (x3, "LHS", r, "2010", "ELCTEGAS00", "S") => 3.0)
    put!("UC_FLO", 7, (x3, "LHS", r, "2010", "ELCTNCOA01", "ELC", "SD") => 1.0, (x3, "LHS", r, "2010", "IMPELC1", "ELC", "ANNUAL") => 1.0)
    put!("UC_IRE", 8, (x3, "LHS", r, "2010", "IMPGAS1", "GAS", "S", "IMP") => 1.0,
         (x3, "LHS", r, "2010", "ELCTECOA00", "ELC", "ANNUAL", "EXP") => 1.0)
    put!("UC_COM", 8, (x3, "NET", "LHS", r, "2010", "GAS", "S", "COMNET") => 2.0, (x3, "PRD", "RHS", r, "2010", "ELC", "ANNUAL", "COMPRD") => 0.5,
         (x3, "NET", "LHS", r, "2010", "GAS", "ANNUAL", "COMCON") => 1.0, (x4, "PRD", "LHS", "REG2", "2010", "ELC", "ANNUAL", "COMPRD") => 1.0)
    add!("UC_ATTR", 5, (r, x3, "LHS", "COMCON", "N"))
    put!("UC_CAP", 5, (x3, "LHS", r, "2010", "ELCTEGAS00") => 1.0)
    add!("UC_DYNBND", 2, (x4, "UP"))
    return tm
end

"What ppmain.mod L1181-1226 writes, on top of ppmain.mod L616-1179, compared at L1226."
const PPMAIN_UCMAP_NEW = ["UC_MAP_FLO", "UC_MAP_IRE", "UC_QAFLO", "UC_CAPFLO", "UC_GMAP_C", "UC_ATTR", "UC_JMAP", "UC_GMAP_P", "TRACKP",
                          "RTP_VARP", "RXX", "UC_ON", "RHS_COMPRD", "RHS_COMBAL", "UC_ACT", "UC_FLO", "UC_IRE", "UC_COM", "UNCD7",
                          "TS_ARRAY", "Z", "F", "RCS_COMBAL", "RCS_COMPRD"]

"What ppmain.mod L1181-1226 declares itself (L1183-1184)."
const PPMAIN_UCMAP_DECLARED_NEW = ["UC_MAP_FLO", "UC_MAP_IRE"]
