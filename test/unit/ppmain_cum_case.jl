# Crafted states for ppmain.mod L1003-1056 (v4.9.7): the cumulative bounds
# moved from BOH and EOH to the first and last years, and the commodities
# whose VAR_COMNET or VAR_COMPRD goes on the RHS of the balance. The
# TIMES_Demo demo12 prelv checkpoint (test/fixtures/demo12_off_prelv) is
# given data no core reference run has, and GAMS runs ppmain.mod L616-1056
# itself on it (scripts/make_ppmain_cum_unit.jl), so the paths the core
# models do not reach are checked against GAMS
# (test/unit/test_m13_ppmain_cum.jl).
#
# demo12 (REG1): BOHYEAR is BOH and 1960-2200, EOHYEAR adds EOH (BEOH moves
# BOH to 1960 and EOH to 2200); ACT_CUM is given for the MINOIL processes
# up to EOH; COM_AGG sums the CO2 commodities into TOTCO2; COA is tracked at
# ANNUAL, ELC at DAYNITE (RTCS_VARC at SD, SN, WD, WN). OBJ is MOD.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!, gset
import TOML

"""
The cases run by GAMS:

- "cum": UC_CUMFLO from BOH to EOH and between two years, UC_CUMACT up to
  EOH (a flow of ACT), FLO_CUM from BOH, UC_CUMCOM up to EOH and between
  two years, COM_CUMNET from BOH to EOH and COM_CUMPRD
  between years (RC_CUMCOM, RTC_NET, RTC_PRD, RHS_COMBAL, RHS_COMPRD);
  COM_CSTNET of COA and COM_TAXPRD of DCOT (the flags at year '0', the RHS
  of every milestone); COM_BNDNET of ELC at S (UP), of COA at ANNUAL (an EPS
  LO, ignored, and an INF UP, ignored) and COM_BNDPRD of COA (FX).
- "lin": "cum" with %OBJ% LIN (L1041, L1045: the milestones overlapping by
  M, LAGT and LEAD too; demo12's periods are contiguous, so the sets come
  out as in "cum").
"""
const PPMAIN_CUM_CASES = ["cum", "lin"]

function ppmain_cum_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_prelv"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    ppmain_cum_case!(tm, name)
    return tm
end

const PC_EPS = 0.0                                                # a stored 0.0 is EPS

function ppmain_cum_case!(tm, name)
    put!(n, N, kv...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, kv); gput!(tm, n, v))
    name in ("cum", "lin") || error("unknown ppmain_cum case $name")
    u, r, cur = "UC_RNW-PP_LOW", "REG1", "MEuro05"
    put!("UC_CUMFLO", 6, (u, r, "ELCTEGAS00", "ELC", "BOH", "EOH") => 100.0, (u, r, "ELCTEGAS00", "ELC", "2010", "2030") => 50.0)
    put!("UC_CUMACT", 5, (u, r, "ELCTECOA00", "2010", "EOH") => 200.0)
    put!("FLO_CUM", 6, (r, "ELCTEGAS00", "ELC", "BOH", "2030", "UP") => 500.0)
    put!("UC_CUMCOM", 6, (u, r, "NET", "COA", "2010", "EOH") => 10.0, (u, r, "PRD", "TOTCO2", "2015", "2030") => 7.0)
    put!("COM_CUMNET", 5, (r, "BOH", "EOH", "ELCCO2", "UP") => 1000.0)
    put!("COM_CUMPRD", 5, (r, "2010", "2030", "COA", "LO") => 5.0)
    put!("COM_CSTNET", 5, (r, "2010", "COA", "ANNUAL", cur) => 2.0)
    put!("COM_TAXPRD", 5, (r, "2015", "DCOT", "ANNUAL", cur) => 1.0)
    put!("COM_BNDNET", 5, (r, "2015", "ELC", "S", "UP") => 50.0, (r, "2010", "COA", "ANNUAL", "LO") => PC_EPS,
         (r, "2020", "COA", "ANNUAL", "UP") => Inf)
    put!("COM_BNDPRD", 5, (r, "2010", "COA", "ANNUAL", "FX") => 3.0)
    name == "lin" && (tm.switches["OBJ"] = "LIN")
    return tm
end

"What ppmain.mod L1003-1056 writes, on top of ppmain.mod L616-1001, compared at L1056."
const PPMAIN_CUM_NEW = ["UC_CUMFLO", "UC_CUMACT", "FLO_CUM", "ACT_CUM", "RPC_CUMFLO", "UC_CUMCOM", "RC_CUMCOM", "COM_CUM", "COM_CUMNET",
                        "COM_CUMPRD", "RTC_PRD", "RHS_COMBAL", "COM_CSTNET", "COM_CSTPRD"]

"What ppmain.mod L1003-1056 declares itself (none)."
const PPMAIN_CUM_DECLARED_NEW = String[]
