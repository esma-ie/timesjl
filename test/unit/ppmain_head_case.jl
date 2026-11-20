# Crafted states for ppmain.mod L1-137 (v4.9.7): the TIMES_Demo demo12 init
# checkpoint (test/fixtures/demo12_off_init) given the data no core reference
# run has, so that the paths of L1-137 the core models do not reach are
# checked against those lines run by GAMS itself
# (scripts/make_ppmain_head_unit.jl, test/unit/test_m13_ppmain_head.jl).
#
# demo12 in REG1: ELCTNGAS01 (ELCGAS in; ELC, ELCCO2 out; PG ELC),
# ELCTECOA00 (ELCCOA in; ELC, ELCCO2 out; PG ELC), COTNCOA1 (COMCOA in;
# COMCO2, DCOT out; PG DCOT), EXPCOA1 and IMPCOA1 (IRE, PG COA). PASTYEAR is
# 1960 and 1980 at this checkpoint.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!, register_uel!
import TOML

"""
The cases:

- "storage": ELCTNGAS01 a STG process (L77) whose tracked PG ELC drops the
  generated OUT flows (L84), keeping ELCGAS IN, so both become timeslice
  storage (L86, L104); ELCTECOA00 an STK process with a FLO_FUNC from
  ELCCOA to ELC (CG_GRP, L85), so inter-period storage of ELC (L95) with
  PRC_TSL reset to ANNUAL (L101) and an ELC IN flow added (L116-117);
  COTNCOA1 night storage (PRC_NSTTS, L89-93: STK removed, NST set).
- "stslim": COM_LIM(ELC,'N') makes ELC a TRACKC commodity (L72), so the STS
  process ELCTNGAS01 (L76) tracks nothing (L81); it also has a given
  PRC_STGIPS on AGRCOA without flows (L100: both added; RP_STS keeps its
  PRC_TSL, L101); ELCTECOA00 a given PRC_STGTSS on ELC (L78, L105-110),
  which gets an ELC IN flow (L115).
- "nopg": no PRC_ACTUNT for ELCTNGAS01, ELCTECOA00 and COTNCOA1 (L59-62):
  ELCTNGAS01 has outputs ELC, ELCCO2 (ENV) and AGRGAS made FIN, so one
  candidate, ELC, only if L61 reads `NOT (ENV + FIN)`; ELCTECOA00 gets a
  second non-ENV output AGRELC (two candidates: no PG); COTNCOA1 keeps DCOT.
  An activity unit on 'ACT' for IMPCOA1 (L43, removed). RPG_RED (L50):
  an ENV commodity on a process with an activity unit (EXPCOA1, an IRE
  process, also gets a non-ENV one), a group label (skipped, G27), and one
  on COTNCOA1, which has no activity unit here (skipped).
- "pasty": NCAP_PASTY (L124-130) of 3 at 1980 (with an unspread PASTI at
  1979 to add to, L132), 2.5 at 1980 (lags 1.5 and 0.5, rounded, G29), 2 on
  an EPS PASTI, 2 at 1960 (the lag to 1959 is outside ALLYEAR), 1 (not
  spread), 3 at 2004 (not a PASTYEAR at this checkpoint: not spread); a
  PASTI at '0' (L135: INT_DEFAULT('PASTI'), '0' left out of PASTYEAR).
"""
const PPMAIN_HEAD_CASES = ["nopg", "pasty", "storage", "stslim"]

function ppmain_head_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_init"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    ppmain_head_case!(tm, name)
    return tm
end

function ppmain_head_case!(tm, name)
    r = "REG1"
    ng, coa, cot = "ELCTNGAS01", "ELCTECOA00", "COTNCOA1"
    put!(n, N, pairs...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, pairs); gput!(tm, n, v))
    putset!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> push!(s, k), ks); gput!(tm, n, s))
    delset!(n, N, f) = gput!(tm, n, filter(!f, gmembers(tm, n, N)))
    foreach(l -> register_uel!(tm.data, l), ("STG", "STK", "STS", "NST", "N", "FIN", "ACT"))
    if name == "storage"
        putset!("PRC_MAP", 3, (r, "STG", ng), (r, "STK", coa), (r, "STK", cot))
        put!("FLO_FUNC", 6, (r, "2010", coa, "ELCCOA", "ELC", "ANNUAL") => 0.4)
        putset!("PRC_NSTTS", 3, (r, cot, "WD"))
    elseif name == "stslim"
        putset!("COM_LIM", 3, (r, "ELC", "N"))
        putset!("PRC_MAP", 3, (r, "STS", ng))
        putset!("PRC_STGIPS", 3, (r, ng, "AGRCOA"))
        putset!("PRC_STGTSS", 3, (r, coa, "ELC"))
    elseif name == "nopg"
        delset!("PRC_ACTUNT", 4, k -> k[1] == r && k[2] in (ng, coa, cot))
        putset!("PRC_ACTUNT", 4, (r, "IMPCOA1", "ACT", "PJ"))
        putset!("TOP", 4, (r, ng, "AGRGAS", "OUT"), (r, coa, "AGRELC", "OUT"))
        putset!("COM_TMAP", 3, (r, "FIN", "AGRGAS"))
        putset!("RPG_RED", 4, (r, "EXPCOA1", "TOTCO2", "OUT"), (r, "EXPCOA1", "GAS", "OUT"), (r, "EXPCOA1", "AOTETOT_NRGI", "OUT"),
                (r, cot, "TOTCO2", "OUT"))
    elseif name == "pasty"
        put!("NCAP_PASTY", 3, (r, "1980", coa) => 3.0, (r, "1980", "ELCTEGAS00") => 2.5, (r, "1980", cot) => 2.0,
             (r, "1960", "ELCREHYD00") => 2.0, (r, "1980", ng) => 1.0, (r, "2004", "COTECOA") => 3.0)
        put!("NCAP_PASTI", 3, (r, "1980", coa) => 9.0, (r, "1979", coa) => 1.0, (r, "1980", "ELCTEGAS00") => 5.0,
             (r, "1980", cot) => 0.0, (r, "1980", ng) => 4.0, (r, "0", cot) => 2.0)
    else
        error("unknown ppmain_head case $name")
    end
    return tm
end

"What ppmain.mod L1-137 writes, compared after it."
const PPMAIN_HEAD_OUTPUTS = ["RDCUR", "PRC_ACTUNT", "RPC_AIRE", "RPC_IRE", "PRC_ACT", "RP_IRE", "TOP", "RPG_RED", "RPC", "RC", "RP",
                             "RP_FLO", "RP_PG", "TRACKPC", "COM_GMAP", "TRACKC", "RP_STS", "TRACKP", "RPC_STGN", "CG_GRP",
                             "PRC_MAP", "PRC_STGIPS", "PRC_TSL", "PRC_STGTSS", "PHYR", "PASTSUM", "PRC_CAP", "NCAP_PASTI",
                             "PASTYEAR", "INT_DEFAULT"]

"Symbols ppmain.mod L1-137 declares itself (L13-29, L122-123)."
const PPMAIN_HEAD_DECLARED = Set(["PUTOUT", "PUTGRP", "ERRLEV", "STARTOFF", "ENDOFF", "MATPRC", "NO_RVP", "IRE_DIST", "RP_SGS",
                                  "RP_STS", "RP_STL", "RPS_STG", "RPC_STG", "RPC_STGN", "UC_DT", "RCS", "RC_RC", "PHYR", "PASTSUM"])
