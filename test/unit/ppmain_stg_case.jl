# Crafted states for ppmain.mod L1058-1099 (v4.9.7): the storage processes.
# The TIMES_Demo demo12 prelv checkpoint (test/fixtures/demo12_off_prelv)
# is given data no core reference run has, and GAMS runs ppmain.mod
# L616-1099 itself on it (scripts/make_ppmain_stg_unit.jl), so the paths the
# core models do not reach are checked against GAMS
# (test/unit/test_m13_ppmain_stg.jl). The core models reach demand sifting
# (TIMES-NZ), a flexible storage (OTNYC) and STG_LOSS (OTCGEN).
#
# demo12 (REG1): ELCTNOIL01 runs at DAYNITE (PRC_TS SD, SN, WD, WN), with
# ELC out; no storage process.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!, gset
import TOML

"""
The case run by GAMS:

- "stg": ELCTNOIL01 made a flexible stockpile storage (RP_STG, RP_STS,
  PRC_MAP STK, RPC_STG and PRC_STGIPS of ELC, PRC_SGL 2): RPS_STG and
  PRC_TS at ANNUAL (L1081-1086), STG_LOSS at ANNUAL (an equilibrium loss
  above 1, L1097) and at S (levelled with %6 S2, L1094, then made negative
  and converted by year fraction, L1088, L1098), RP_STL (L1089), NCAP_AF
  from NCAP_AFS outside RPS_STG (L1090).
"""
const PPMAIN_STG_CASES = ["stg"]

function ppmain_stg_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_prelv"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    ppmain_stg_case!(tm, name)
    return tm
end

function ppmain_stg_case!(tm, name)
    put!(n, N, kv...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, kv); gput!(tm, n, v))
    add!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> push!(s, k), ks); gput!(tm, n, s))
    name == "stg" || error("unknown ppmain_stg case $name")
    r, p = "REG1", "ELCTNOIL01"
    add!("RP_STG", 2, (r, p)); add!("RP_STS", 2, (r, p)); add!("PRC_MAP", 3, (r, "STK", p))
    add!("RPC_STG", 3, (r, p, "ELC")); add!("PRC_STGIPS", 3, (r, p, "ELC"))
    put!("PRC_SGL", 2, (r, p) => 2.0)
    put!("STG_LOSS", 4, (r, "2010", p, "ANNUAL") => 1.5, (r, "2015", p, "S") => 0.1)
    put!("NCAP_AFS", 5, (r, "2010", p, "ANNUAL", "UP") => 0.8)
    return tm
end

"What ppmain.mod L1058-1099 writes, on top of ppmain.mod L616-1056, compared at L1099."
const PPMAIN_STG_NEW = ["RPC_SPG", "RPC_STGN", "RPC_LS", "STG_SIFT", "ACT_TIME", "RPS_STG", "RP_STS", "RP_STG", "PRC_STGTSS",
                        "STG_LOSS", "RP_STL"]

"What ppmain.mod L1058-1099 declares itself (none)."
const PPMAIN_STG_DECLARED_NEW = String[]
