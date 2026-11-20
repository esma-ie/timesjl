# Crafted states for init_ext.vda (v4.9.7): the TIMES_Demo demo12 input
# checkpoint (test/fixtures/demo12_off_input) given the data no core
# reference run has, so that the paths of init_ext.vda L52-156 the core
# models do not reach are checked against init_ext.vda run by GAMS itself
# (scripts/make_init_ext_unit.jl, test/unit/test_m13_init_ext.jl).
#
# demo12: REG1 and REG2 (ALL_REG adds IMPEXP and MINRNW), milestones
# 2005-2050 (B(2005) = 2005), currency MEuro05. ELCTNGAS01 (ELCGAS in, ELC
# out; activity unit PJ on ELC), ELCTECOA00 (ELCCOA in), COTNCOA1 (COMCOA
# in, DCOT out), EXPCOA1 an IRE process. Every case is in REG1.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!
import TOML

"""
The cases, name => (extra switches, description):

- "flags" (WAVER YES, SHELL ANSWER): DATAYEAR emptied (L53-54 rebuild it)
  and B(2005) = 1990 (L57 resets it to 2005); NCAP_PKCNT at '0'/ANNUAL of
  12 (PRC_PKNO), EPS and -1 (PRC_PKAF), 5 (neither), and 20 at 2010
  (ignored); PRC_STGIPS kept by an activity unit on the commodity itself,
  kept through COM_GMAP (the group AOTETOT_NRGI holds AGRCOA; at this
  checkpoint COM_GMAP has only the user's groups), removed (L65); STG_MAXCYC, ACT_CSTPL (with
  an EPS), a cleared ANNUAL and a kept DAYNITE ACT_CSTUP, ACT_MINLD,
  ACT_TIME, ACT_CSTSD (L67-73); FLO_COST with an EPS-only group at data
  years (removed), a group with a nonzero year (kept) and an EPS outside
  the data years (kept) - UNCD7 keeps that group with '' labels (G36);
  VDA_CEH (L89); FLO_EFF (L96; an emission flow on an input, so no RPG_RED);
  IRE_FLOSUM on EXPCOA1 (L107); a COM_AGG diagonal (L110); PRC_ACTFLO at
  '0' on a commodity and on a group (L113); ACT_FLO at '0' (L111, L114);
  UC_ACTBET in REG1 and in IMPEXP (L131-132); UC_ATTR naming a timeslice
  level and another name (L130).
- "offrange": B(2005) = 2003 (kept: MIYR_BOH 2002); NCAP_START of 2000 and
  EPS (removed, L117); NCAP_BND 'N' (L118-124): 2025 at 2010 (a 15-year
  lead), 2300 at 2015 (capped at %EOTIME%), 2019 at 2020 (a lead of -1;
  L124 keeps YEARVAL-1 = 2019, GAMS MOD keeping the sign), 1, 2030 (> 999:
  NCAP_START 2031) and -1 at '0', EPS at 2030; PRC_NOFF records at EOH
  years (removed, L122) and of a process without 'N' bounds (kept).
"""
const INIT_EXT_CASES = Dict("flags" => Dict("WAVER" => "YES", "SHELL" => "ANSWER"), "offrange" => Dict{String,String}())

function init_ext_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    sw = merge(Dict{String,String}(k => string(v) for (k, v) in fx["switches"]), INIT_EXT_CASES[name])
    tm = TimesModel(joinpath(fixtures, "demo12_off_input"); switches=sw)
    init_ext_case!(tm, name)
    return tm
end

function init_ext_case!(tm, name)
    r, cur = "REG1", "MEuro05"
    ng, coa, cot = "ELCTNGAS01", "ELCTECOA00", "COTNCOA1"
    put!(n, N, pairs...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, pairs); gput!(tm, n, v))
    putset!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> push!(s, k), ks); gput!(tm, n, s))
    if name == "flags"
        gput!(tm, "DATAYEAR", Set{NTuple{1,String}}())
        put!("B", 1, ("2005",) => 1990.0)
        put!("NCAP_PKCNT", 4, (r, "0", ng, "ANNUAL") => 12.0, (r, "0", coa, "ANNUAL") => 0.0, (r, "0", cot, "ANNUAL") => -1.0,
             (r, "0", "IMPCOA1", "ANNUAL") => 5.0, (r, "2010", "EXPCOA1", "ANNUAL") => 20.0)
        putset!("PRC_ACTUNT", 4, (r, cot, "AOTETOT_NRGI", "PJ"))
        putset!("PRC_STGIPS", 3, (r, ng, "ELC"), (r, ng, "ELCGAS"), (r, cot, "AGRCOA"))
        put!("STG_MAXCYC", 3, (r, "2010", ng) => 300.0)
        put!("ACT_CSTPL", 4, (r, "2010", coa, cur) => 3.5, (r, "2010", ng, cur) => 2.0, (r, "2015", coa, cur) => 0.0)
        put!("ACT_CSTUP", 5, (r, "2010", coa, "ANNUAL", cur) => 9.0, (r, "2010", coa, "DAYNITE", cur) => 4.0)
        put!("ACT_MINLD", 3, (r, "2010", ng) => 0.4)
        put!("ACT_TIME", 4, (r, "2010", ng, "LO") => 2.0)
        put!("ACT_CSTSD", 6, (r, "2010", ng, "COLD", "UP", cur) => 1.0)
        put!("FLO_COST", 6, (r, "2010", ng, "ELCGAS", "ANNUAL", cur) => 0.0, (r, "2015", ng, "ELCGAS", "ANNUAL", cur) => 0.0,
             (r, "2010", coa, "ELCCOA", "ANNUAL", cur) => 0.0, (r, "2020", coa, "ELCCOA", "ANNUAL", cur) => 1.5,
             (r, "2012", ng, "ELC", "ANNUAL", cur) => 0.0)
        put!("VDA_CEH", 3, (r, "2010", ng) => 1.2)
        put!("FLO_EFF", 6, (r, "2010", ng, "ELCCO2", "ELCGAS", "ANNUAL") => 0.05)
        put!("IRE_FLOSUM", 8, (r, "2010", "EXPCOA1", "COA", "ANNUAL", "EXP", "ELCCO2", "OUT") => 0.1)
        put!("COM_AGG", 4, (r, "2005", "TOTCO2", "TOTCO2") => 1.0)
        put!("PRC_ACTFLO", 4, (r, "0", ng, "ELC") => 1.0, (r, "0", ng, "NRG") => 1.0)
        put!("ACT_FLO", 5, (r, "0", coa, "ELCCOA", "ANNUAL") => 0.9)
        put!("UC_ACTBET", 4, ("UC_RNW-PP_LOW", r, "2010", ng) => 0.5, ("UC_RNW-PP_LOW", "IMPEXP", "2010", ng) => 0.3)
        putset!("UC_ATTR", 5, (r, "UC_RNW-PP_LOW", "LHS", "ACT", "SEASON"), (r, "UC_RNW-PP_LOW", "LHS", "ACT", "GROWTH"))
    elseif name == "offrange"
        put!("B", 1, ("2005",) => 2003.0)
        put!("NCAP_START", 2, (r, ng) => 2000.0, (r, coa) => 0.0)
        put!("NCAP_BND", 4, (r, "2010", ng, "N") => 2025.0, (r, "2015", ng, "N") => 2300.0, (r, "2020", ng, "N") => 2019.0,
             (r, "0", ng, "N") => 1.0, (r, "0", coa, "N") => 2030.0, (r, "0", cot, "N") => -1.0, (r, "2030", cot, "N") => 0.0)
        putset!("PRC_NOFF", 4, (r, ng, "2010", "2200"), (r, ng, "2010", "2050"), (r, coa, "2005", "2010"))
    else
        error("unknown init_ext case $name")
    end
    return tm
end

"What init_ext.vda (with equcrtp.vda INIT_EXT) writes, compared after it."
const INIT_EXT_OUTPUTS = ["DATAYEAR", "B", "MIYR_1", "MIYR_BOH", "PYR_S", "INT_DEFAULT", "PRC_PKNO", "PRC_PKAF", "PRC_STGIPS",
                          "TRACKP", "RP_PL", "ACT_CSTUP", "ACT_UPS", "RP_UPR", "RP_UPT", "UNCD7", "VDA_EMCB", "IRE_PRICE",
                          "ACT_COST", "FLO_DELIV", "FLO_COST", "NCAP_CEH", "PRC_RESID", "NCAP_PASTI", "FLO_EMIS", "RXX",
                          "FLO_EFF", "FS_EMCB", "TRACKPC", "TOP", "RPC_EMIS", "RPG_RED", "COM_AGG", "VDA_FLOP", "KEEP_FLOF",
                          "RP_XRED", "ACT_FLO", "NCAP_START", "RVP", "NCAP_BND", "PRC_NOFF", "UNCD1", "PRC_DYNUC", "UC_COM",
                          "UC_CAP", "UC_NCAP", "UC_ACT", "UC_COMPRD", "UC_COMNET", "UC_TSL", "UC_FLOBET", "UC_GMAP_P",
                          "PAR_IRE", "PAR_IPRIC", "RPC_IREIN"]

"Symbols init_ext.vda declares itself (L9-50, L138)."
const INIT_EXT_DECLARED = Set(["RP_UX", "RP_PL", "RTP_PL", "RPS_UPS", "RP_UPC", "AFUPS", "RP_DP", "DP_LOSD", "FS_EMCB", "RP_DCGG",
                               "RP_CGC", "RPC_IREIN", "RVPS", "RPS_CAFLAC", "RVPCSL", "RPG_ACE", "RPG_PACE", "RPG_1ACE", "RPC_ACE",
                               "RVP_KMAP", "DUMIMP", "NRGELC", "MIYR_BOH", "REG_FIXT", "VN2T", "RTFORC", "COEF_RCOM", "PRC_DYNUC",
                               "RPCG_ASHAR", "FLO_ASHAR", "PAR_IPRIC", "DP_PSUD", "COEF_AFUPS", "PREMILE"])
