# Crafted states for timslice.mod (v4.9.7, with pp_off.mod): the TIMES_Demo
# demo12 init checkpoint (test/fixtures/demo12_off_init) given the data no core
# reference run has, so that the paths of timslice.mod the core models do not
# reach are checked against ppmain.mod L1-196 run by GAMS itself
# (scripts/make_timslice_unit.jl, test/unit/test_m13_timslice.jl).
#
# demo12 has regions REG1 and REG2 (and the external IMPEXP and MINRNW), the
# seasons S and W below ANNUAL, and the DAYNITE slices SD, SN below S and WD,
# WN below W; only the DAYNITE fractions are given. MILESTONYR is 2005, 2010,
# 2015, 2020, 2030, 2050 (D(2005) = 1); BOHYEAR runs 'BOH', 1960, ..., 2200.

using TIMES: TimesModel, gvalues, gmembers, gput!, gset
import TOML

"""
The cases run by GAMS:

- "norm": G_YRFR(REG1,SD) 2% too high and G_YRFR(REG1,W) = 0.5 given (its
  children sum to 0.52): L77-78 scale S and W at the ANNUAL step, then the
  children of each at the SEASON step, which read the new S and W.
- "zerofrac": G_YRFR(REG1,SN) missing and G_YRFR(REG1,WN) = -0.1, so L46
  fills W from WD-0.1 and L50-55 remove SN and WN (S and W keep one child each:
  L95 gives RS_STG 0, no record); TS_CYCLE(REG2) 2 at S (kept), 3 at SD (a
  finest slice: cleared at L86) and 0.5 at W (below 1: L87 sets 365/365);
  G_CYCLE('WEEKLY') = 50 (kept by L86).
- "tsoff_first": TS_OFF(REG1,W,BOH,2005), without DYNTS: the first period is
  off, so L37 clears the fractions of W, WD, WN; they are removed (L50-55) and
  S is normalised to the whole year.
- "tsoff_later": TS_OFF(REG1,S,2030,EOH) and TS_OFF(REG1,WD,2010,2020), without
  DYNTS: the first period is on (nothing changes), and L35 skips WD (not right
  below ANNUAL).
- "dynts": %DYNTS% YES, the REG1 DAYNITE fractions 0.25 each (exact in
  binary), TS_OFF(REG1,S,BOH,2010) and TS_OFF(REG2,W,BOH,EOH): NORTS -INF for
  S, SD, SN of REG1 in 2005 and 2010; W of REG2 off in every period (L37,
  removed); the ANNUAL step with NORTS (L70-75) gives W of REG1, the only
  slice on in 2005, the whole year.
- "uc": one RP_UPR record (a ramping cost), so L110-123 build the hour maps.

And two for Julia only (GAMS ABORTs): "twolevels", SD also a SEASON slice
(L24); "dynts_abort", %DYNTS% YES and TS_OFF(REG1,S,2030,EOH): in 2030 the
fraction left for S cannot be given to a slice that is on (L74).
"""
const TIMSLICE_CASES = ["norm", "zerofrac", "tsoff_first", "tsoff_later", "dynts", "uc"]

function timslice_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_init"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    timslice_case!(tm, name)
    return tm
end

function timslice_case!(tm, name)
    put!(n, N, kv...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, kv); gput!(tm, n, v))
    add!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> push!(s, k), ks); gput!(tm, n, s))
    if name == "norm"
        put!("G_YRFR", 2, ("REG1", "SD") => 0.249714611872146 * 1.02, ("REG1", "W") => 0.5)
    elseif name == "zerofrac"
        v = gvalues(tm, "G_YRFR", 2)
        delete!(v, ("REG1", "SN"))
        v[("REG1", "WN")] = -0.1
        gput!(tm, "G_YRFR", v)
        put!("TS_CYCLE", 2, ("REG2", "S") => 2.0, ("REG2", "SD") => 3.0, ("REG2", "W") => 0.5)
        put!("G_CYCLE", 1, ("WEEKLY",) => 50.0)
    elseif name == "tsoff_first"
        add!("TS_OFF", 4, ("REG1", "W", "BOH", "2005"))
    elseif name == "tsoff_later"
        add!("TS_OFF", 4, ("REG1", "S", "2030", "EOH"), ("REG1", "WD", "2010", "2020"))
    elseif name == "dynts"
        tm.switches["DYNTS"] = "YES"
        put!("G_YRFR", 2, (("REG1", s) => 0.25 for s in ("SD", "SN", "WD", "WN"))...)
        add!("TS_OFF", 4, ("REG1", "S", "BOH", "2010"), ("REG2", "W", "BOH", "EOH"))
    elseif name == "uc"
        p = first(k[1] for k in gset(tm, "PRC").keys)
        add!("RP_UPR", 3, ("REG1", p, "UP"))
    elseif name == "twolevels"
        add!("TS_GROUP", 3, ("REG1", "SEASON", "SD"))
    elseif name == "dynts_abort"
        tm.switches["DYNTS"] = "YES"
        add!("TS_OFF", 4, ("REG1", "S", "2030", "EOH"))
    else
        error("unknown timslice case $name")
    end
    return tm
end

"What timslice.mod writes, compared after it."
const TIMSLICE_OUTPUTS = ["FIL", "STARTOFF", "ENDOFF", "TS_GROUP", "TS_MAP", "STOAL", "RS_BELOW", "RS_BELOW1", "NORTS", "G_YRFR", "FINEST", "RS_TREE", "RJLVL",
                          "RLUP", "G_CYCLE", "TS_CYCLE", "RS_STGPRD", "RS_TSLVL", "RS_STG", "RS_STGAV", "STOA", "RS_HR", "JS",
                          "RJ_SL", "RS_UP", "JS_CCL", "RS_MODUS"]

"The symbols timslice.mod L13-16 declares itself (not written into the replayed state)."
const TIMSLICE_DECLARED = ["RJLVL", "RLUP", "RS_HR", "MY_SUM", "NORTS", "RS_UP", "RJ_SL", "JS", "RS_MODUS"]
