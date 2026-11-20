# Crafted states for ppmain.mod L823-843 (v4.9.7): FLO_FUNC and FLO_SUM
# levelled (pp_lvlff.mod, pp_lvlfs.mod), FLO_SUM and IRE_FLOSUM from
# PRC_ACTFLO, FLO_SHAR levelled (pp_lvlbr.mod) and the market shares
# (eqflomrk.mod). The TIMES_Demo demo12 prelv checkpoint
# (test/fixtures/demo12_off_prelv) is given data no core reference run has,
# and GAMS runs ppmain.mod L616-843 itself on it
# (scripts/make_ppmain_flofs_unit.jl), so the paths the core models do not
# reach are checked against GAMS (test/unit/test_m13_ppmain_flofs.jl).
#
# demo12 (REG1): ELCTEGAS00 runs at DAYNITE (ELCGAS in, ELC and ELCCO2 out),
# COTEGAS at ANNUAL (COMGAS in, DCOT out); the timeslices are ANNUAL, S and W,
# SD, SN, WD and WN; the milestones 2005, 2010, 2015, 2020, 2030, 2050. No
# FLO_FUNC, FLO_SUM or PRC_MARK data.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!, gset
import TOML

"""
The cases run by GAMS:

- "ffs": FLO_FUNC of ELCTEGAS00 at ANNUAL (copied down, L30-31) and at S
  (levelled for every model year, L21-26); FLO_SUM of ELCTEGAS00 at S and
  W (inherited down from the SEASON level, L35-39, and deleted), of COTEGAS
  at S and W in 2010 (aggregated to ANNUAL, L23-28), in a year outside RTP
  (deleted, L34); FLO_SHAR of ELCTEGAS00 at ANNUAL (UP) and S (LO), the
  share at S keeping the group from pp_qafs.mod's checks (both inherited
  down, %2 ',C,CG'), and of ELCTECOA00 at SD below its SEASON level
  (aggregated).
- "mark": PRC_MARK of ELCTEGAS00's own flows (ITEM = P): UP for ELC, a
  negative LO for ELCGAS (RX_MARK at the last milestone, L27), FX with LO
  (LO dropped), EPS (no FLO_BND: the own-flow flag drops it, L30); a group
  share with ITEM another process, and an EPS one (a FLO_BND of EPS, L31); a
  share in a year outside RTP_VARA (kept with ITEM = P, else deleted, L23); extrapolated forward
  over the milestones (L37) and cut back to the years of RTX_MRK (L39).
"""
const PPMAIN_FLOFS_CASES = ["ffs", "mark"]

function ppmain_flofs_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_prelv"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    ppmain_flofs_case!(tm, name)
    return tm
end

const PS_EPS = 0.0                                                # a stored 0.0 is EPS

function ppmain_flofs_case!(tm, name)
    put!(n, N, kv...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, kv); gput!(tm, n, v))
    r, p = "REG1", "ELCTEGAS00"
    if name == "ffs"
        put!("FLO_FUNC", 6, (r, "2010", p, "ELCGAS", "ELC", "ANNUAL") => 0.45, (r, "2015", p, "ELCGAS", "ELC", "S") => 0.5)
        put!("FLO_SUM", 7, (r, "2010", p, "ELCGAS", "ELC", "ELCGAS", "S") => 0.8, (r, "2010", p, "ELCGAS", "ELC", "ELCGAS", "W") => 0.6,
             (r, "2010", "COTEGAS", "COMGAS", "DCOT", "COMGAS", "S") => 0.9, (r, "2010", "COTEGAS", "COMGAS", "DCOT", "COMGAS", "W") => 0.7,
             (r, "2011", "COTEGAS", "COMGAS", "DCOT", "COMGAS", "ANNUAL") => 0.5)
        put!("FLO_SHAR", 7, (r, "2010", p, "ELC", "ELC", "ANNUAL", "UP") => 0.9, (r, "2010", p, "ELC", "ELC", "S", "LO") => 0.2,
             (r, "2015", "ELCTECOA00", "ELC", "ELC", "SD", "LO") => 0.4)
    elseif name == "mark"
        pm(y, item, c, bd, x) = (r, y, p, item, c, bd) => x
        put!("PRC_MARK", 6, pm("2010", p, "ELC", "UP", 0.3), pm("2010", p, "ELCGAS", "LO", -0.2), pm("2015", p, "ELC", "FX", 0.25),
             pm("2015", p, "ELC", "LO", 0.1), pm("2020", p, "ELCCO2", "UP", PS_EPS), pm("2015", "ELCTECOA00", "ELC", "UP", PS_EPS),
             pm("2010", "ELCTECOA00", "ELC", "UP", 0.6), pm("2012", p, "ELCGAS", "UP", 0.4), pm("2012", "ELCTECOA00", "ELCGAS", "UP", 0.5))
    else
        error("unknown ppmain_flofs case $name")
    end
    return tm
end

"What ppmain.mod L823-843 writes, on top of ppmain.mod L616-821, compared at L843, scratch included."
const PPMAIN_FLOFS_NEW = ["FLO_FUNC", "FFCKS", "CG_GRP", "COEF_PTRAN", "FSCKS", "FSCK", "FSTSL", "IRE_FLOSUM", "PRC_MARK", "RX_MARK",
                          "RTP_MRK", "RTX_MRK", "RMKC", "FIN", "YK1", "RTX_MARK", "RHS_COMPRD", "COM_TSL", "FLO_BND", "RPC_NOFLO", "RXX"]

"What ppmain.mod L823-843 and the files it includes declare themselves (pp_lvlff.mod L13, pp_lvlfs.mod L13, eqflomrk.mod L15-19)."
const PPMAIN_FLOFS_DECLARED_NEW = ["FFCKS", "FSTSL", "RTX_MARK", "RX_MARK", "RTP_MRK", "RTX_MRK", "RMKC"]
