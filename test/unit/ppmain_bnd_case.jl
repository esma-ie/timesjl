# Crafted states for ppmain.mod L936-1001 (v4.9.7): the commodity subsets
# and COM_LIM defaults, the trade conversions, the bounds aggregated by
# pp_lvlbd.mod and FLO_BND and ACT_BND from FLO_BDLVL. The TIMES_Demo
# demo12 prelv checkpoint (test/fixtures/demo12_off_prelv) is given data no
# core reference run has, and GAMS runs ppmain.mod L616-1001 itself on it
# (scripts/make_ppmain_bnd_unit.jl), so the paths the core models do not
# reach are checked against GAMS (test/unit/test_m13_ppmain_bnd.jl).
#
# demo12 (REG1): ELCTECOA00 runs at SEASON (S, W; RPS_PRCTS ANNUAL, S, W),
# ELCTEGAS00 at DAYNITE; COA is tracked at ANNUAL, ELC at DAYNITE;
# TB_ELC_REG1_REG2_01 trades ELC between REG1 and REG2. No bounds below
# their level, no IRE_CCVT, no FLO_BDLVL, no CONSRV energy.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!, gset
import TOML

"""
The case run by GAMS:

- "bnd": ACT_BND of ELCTECOA00 below its SEASON level: UP at SD and SN
  (summed to S), a negative LO at SD (EPS, %9), FX at WD and WN (summed to
  an FX at W), UP at S and SD (the lower one ignored), UP at SD alone (not
  covering S: no UP); COM_BNDNET and COM_BNDPRD of COA at S and W (summed to
  ANNUAL; a negative LO kept, %9 empty); IRE_BND of COA at S and W; FLO_FR
  of ELCTECOA00's ELC at SD and SN (a negative one made 0, %9 0); FLO_BDLVL
  of ELCTEGAS00 (ELC, ACT) and of TB_ELC_REG1_REG2_01 (NRG) at DAYNITE
  (FLO_BND and ACT_BND, L999-1001), and one under a FLO_BND (dropped,
  L998); IRE_CCVT of REG1's ELC to REG2 (the reverse 1/x, L982); COA a
  CONSRV energy (COM_LIM UP, L952).
"""
const PPMAIN_BND_CASES = ["bnd"]

function ppmain_bnd_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_prelv"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    ppmain_bnd_case!(tm, name)
    return tm
end

function ppmain_bnd_case!(tm, name)
    put!(n, N, kv...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, kv); gput!(tm, n, v))
    add!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> push!(s, k), ks); gput!(tm, n, s))
    name == "bnd" || error("unknown ppmain_bnd case $name")
    r, p, q = "REG1", "ELCTECOA00", "ELCTEGAS00"
    ab(y, s, b, x) = (r, y, p, s, b) => x
    put!("ACT_BND", 5, ab("2010", "SD", "UP", 10.0), ab("2010", "SN", "UP", 12.0), ab("2010", "SD", "LO", -3.0),
         ab("2015", "WD", "FX", 5.0), ab("2015", "WN", "FX", 6.0), ab("2020", "S", "UP", 30.0), ab("2020", "SD", "UP", 10.0),
         ab("2030", "SD", "UP", 10.0))
    put!("COM_BNDNET", 5, (r, "2010", "COA", "S", "UP") => 100.0, (r, "2010", "COA", "W", "UP") => 50.0)
    put!("COM_BNDPRD", 5, (r, "2010", "COA", "S", "LO") => -5.0, (r, "2010", "COA", "W", "LO") => 2.0)
    put!("IRE_BND", 7, (r, "2010", "COA", "S", "IMPEXP", "IMP", "UP") => 20.0, (r, "2010", "COA", "W", "IMPEXP", "IMP", "UP") => 10.0)
    put!("FLO_FR", 6, (r, "2010", p, "ELC", "SD", "LO") => 0.1, (r, "2010", p, "ELC", "SN", "LO") => -0.2)
    put!("FLO_BDLVL", 6, (r, "2010", q, "ELC", "SD", "UP") => 0.5, (r, "2010", q, "ACT", "SN", "UP") => 0.7,
         (r, "2010", "TB_ELC_REG1_REG2_01", "NRG", "WD", "UP") => 0.3, (r, "2015", q, "ELC", "WN", "UP") => 0.4)
    put!("FLO_BND", 6, (r, "2015", q, "ELC", "WN", "UP") => 100.0)
    put!("IRE_CCVT", 4, (r, "ELC", "REG2", "ELC") => 0.9)
    add!("NRG_TMAP", 3, (r, "CONSRV", "COA"))
    return tm
end

"What ppmain.mod L936-1001 writes, on top of ppmain.mod L616-933, compared at L1001, scratch included."
const PPMAIN_BND_NEW = ["NRG", "MAT", "ENV", "COM_LIM", "RREG", "IRE_TSCVT", "IRE_CCVT", "ACT_BND", "COM_BNDNET", "COM_BNDPRD",
                        "IRE_BND", "FLO_FR", "TS_BD", "BDVAL"]

"What ppmain.mod L936-1001 and the files it includes declare themselves (pp_lvlbd.mod L22-23)."
const PPMAIN_BND_DECLARED_NEW = ["TS_BD", "BDVAL"]
