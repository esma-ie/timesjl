# Crafted states for ppmain.mod L846-933 (v4.9.7): the trade attributes
# levelled (pp_lvlfc.mod for IRE_PRICE and IRE_FLOSUM, pp_lvlif.mod for
# IRE_FLO) and the market-based trade. The TIMES_Demo demo12 prelv
# checkpoint (test/fixtures/demo12_off_prelv) is given data no core
# reference run has, and GAMS runs ppmain.mod L616-933 itself on it
# (scripts/make_ppmain_ire_unit.jl), so the paths the core models do not
# reach are checked against GAMS (test/unit/test_m13_ppmain_ire.jl).
#
# demo12: TB_ELC_REG1_REG2_01 trades ELC both ways between REG1 and REG2 at
# DAYNITE (RPC_IRE IMP and EXP in both regions, RP_AIRE IMP and EXP, PG
# ELC); TU_GAS_REG2_REG1_01 brings GAS from REG2 to REG1; the IMP* processes
# import from IMPEXP. No IRE_FLO, IRE_PRICE or IRE_FLOSUM data, no
# marketplace, no CORR or DISTR process.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!, gset
import TOML

"""
The cases run by GAMS:

- "ire": IRE_PRICE of TB_ELC_REG1_REG2_01 at ANNUAL (IMP) and S (EXP),
  levelled to RPCS_VAR; IRE_FLOSUM at S (levelled to PRC_TS) and at the
  activity (%PGPRIM% ACT, moved to ELC by L924-926); IRE_FLO at S
  (levelled, pp_lvlif.mod), at ANNUAL (copied down) and for an import of a
  commodity the process does not import (the QA log only); the ELC exports
  of REG1 linked to ELC and AGRELC of REG2, so REG1 becomes a marketplace
  (L866, L880-913: CG_GRP, RC_RC, the diagonal TOP_IRE, its IRE_FLO taken
  from the REG2 link, RPC_EQIRE, RPC_MARKET IMP).
- "dist": "ire" with TB_ELC_REG1_REG2_01 a CORR process of REG1, so a
  distribution process (IRE_DIST: L867, L871-876, L883, L897, L912, L921).
"""
const PPMAIN_IRE_CASES = ["ire", "dist"]

function ppmain_ire_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_prelv"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    ppmain_ire_case!(tm, name)
    return tm
end

function ppmain_ire_case!(tm, name)
    put!(n, N, kv...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, kv); gput!(tm, n, v))
    add!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> push!(s, k), ks); gput!(tm, n, s))
    p, cur = "TB_ELC_REG1_REG2_01", "MEuro05"
    name in ("ire", "dist") || error("unknown ppmain_ire case $name")
    put!("IRE_PRICE", 8, ("REG1", "2010", p, "ELC", "ANNUAL", "REG2", "IMP", cur) => 5.0,
         ("REG1", "2015", p, "ELC", "S", "REG2", "EXP", cur) => 6.0)
    put!("IRE_FLOSUM", 8, ("REG1", "2010", p, "ELC", "S", "IMP", "ELC", "OUT") => 0.1,
         ("REG1", "2015", p, "ACT", "ANNUAL", "EXP", "ELC", "IN") => 0.2)
    put!("IRE_FLO", 7, ("REG2", "2010", p, "ELC", "REG1", "ELC", "S") => 0.95, ("REG1", "2015", p, "ELC", "REG2", "ELC", "ANNUAL") => 0.9,
         ("REG1", "2010", p, "ELC", "REG2", "GAS", "S") => 0.8)
    add!("TOP_IRE", 5, ("REG1", "ELC", "REG2", "AGRELC", p))
    add!("RPC_IRE", 4, ("REG2", p, "AGRELC", "IMP"))
    name == "dist" && add!("PRC_MAP", 3, ("REG1", "CORR", p))
    return tm
end

"What ppmain.mod L846-933 writes, on top of ppmain.mod L616-843, compared at L933, scratch included."
const PPMAIN_IRE_NEW = ["IRE_PRICE", "IRE_FLO", "RPC_IREIO", "IRE_DIST", "RPC_MARKET", "RC_RC", "TOP_IRE", "RPC_EQIRE", "RTPC",
                        "RP_AIRE", "PRC_MAP"]

"What ppmain.mod L846-933 and the files it includes declare themselves (none)."
const PPMAIN_IRE_DECLARED_NEW = String[]
