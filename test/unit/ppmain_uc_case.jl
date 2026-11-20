# Crafted states for ppmain.mod L1101-1179 (v4.9.7): the user-constraint
# defaults. The TIMES_Demo demo12 prelv checkpoint
# (test/fixtures/demo12_off_prelv) is given data no core reference run has,
# and GAMS runs ppmain.mod L616-1179 itself on it
# (scripts/make_ppmain_uc_unit.jl), so the paths the core models do not
# reach are checked against GAMS (test/unit/test_m13_ppmain_uc.jl).
#
# demo12: the UCs AU_NUC_MaxCAP (UC_RHSRT UP, every milestone from 2015) and
# UC_RNW-PP_LOW (UC_RHSRTS LO EPS at ANNUAL from 2020), both UC_R_EACH in
# REG1 and REG2; the period of 2010 spans 2008-2012. Two UCs are added here,
# UC_X1 and UC_X2.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!, gset, register_uel!
import TOML

"""
The case run by GAMS:

- "uc": UC_T_SUM of UC_X1 by %DFLBL% between 2010 and 2030 (filled in
  between, prepxtra.mod L64-68), UC_T_EACH of UC_X2 by %DFLBL% (every
  milestone, L71), UC_T_SUCC of AU_NUC_MaxCAP in 2012 (its milestone 2010
  added, 2012 kept, L72-76); UC_RNW-PP_LOW at SEASON level in REG1 (UC_TSL:
  UC_DS, R_UC, the ANNUAL RHS levelled down and cut to UC_TS_EACH S,
  L1108-1114) with a dynamic RHS (N: UC_DYNDIR, UC_TSL RHS, G_UDS,
  L1167-1179); UC_RHSS of UC_X2 (the obsolete form, L1116, so UC_R_SUM in
  both regions and the UC_TS_EACH default); UC_ATTR GROWTH (LHS dynamic),
  CUMSUM with SYNC (CUM+, N), FLO_COST (COST through UC_MAPCOST), NCAP ANNUL
  (CUMSUM) and RHS PERIOD, which makes UC_X2 dynamic (RXX) so that its
  milestones move from UC_T_EACH to UC_T_SUCC (L1170-1174).
"""
const PPMAIN_UC_CASES = ["uc"]

function ppmain_uc_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_prelv"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    ppmain_uc_case!(tm, name)
    return tm
end

function ppmain_uc_case!(tm, name)
    put!(n, N, kv...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, kv); gput!(tm, n, v))
    add!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> push!(s, k), ks); gput!(tm, n, s))
    name == "uc" || error("unknown ppmain_uc case $name")
    r, a, w, x1, x2 = "REG1", "AU_NUC_MaxCAP", "UC_RNW-PP_LOW", "UC_X1", "UC_X2"
    foreach(l -> register_uel!(tm.data, l), (x1, x2))
    add!("UC_N", 1, (x1,), (x2,))
    add!("UC_T_SUM", 3, (r, x1, "0"), (r, x1, "2010"), (r, x1, "2030"))
    put!("UC_RHSRT", 4, (r, x1, "2010", "UP") => 5.0)
    add!("UC_T_EACH", 3, (r, x2, "0"))
    add!("UC_T_SUCC", 3, (r, a, "2012"))
    add!("UC_TSL", 4, (r, w, "LHS", "SEASON"))
    add!("UC_TS_EACH", 3, (r, w, "S"))
    put!("UC_RHSS", 3, (x2, "ANNUAL", "LO") => 3.0)
    add!("UC_ATTR", 5, (r, w, "LHS", "FLO", "SEASON"), (r, w, "RHS", "ACT", "N"), (r, a, "LHS", "CAP", "GROWTH"),
         (r, x1, "RHS", "ACT", "CUMSUM"), (r, x1, "RHS", "ACT", "SYNC"), (r, x1, "LHS", "FLO", "FLO_COST"),
         (r, x2, "LHS", "NCAP", "ANNUL"), (r, x2, "RHS", "ACT", "PERIOD"))
    return tm
end

"What ppmain.mod L1101-1179 writes, on top of ppmain.mod L616-1099, compared at L1179."
const PPMAIN_UC_NEW = ["UC_T_SUM", "UC_T_SUCC", "UC_T_EACH", "UC_TSL", "UC_DS", "R_UC", "MREG", "UC_RHSRTS", "UC_TS_EACH",
                       "UC_TS_SUM", "UC_ATTR", "UC_RHS", "UC_RHSR", "UNCD1", "UC_R_EACH", "UC_R_SUM", "UC_ON", "UC_DT", "UC_DYNDIR",
                       "RS_PREV", "G_UDS"]

"What ppmain.mod L1101-1179 declares itself (none)."
const PPMAIN_UC_DECLARED_NEW = String[]
