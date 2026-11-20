# Crafted states for pp_prelv.vda (v4.9.7, ppmain.mod L615) with pp_lvlfc.mod
# for FLO_FR: the TIMES_Demo demo12 init checkpoint
# (test/fixtures/demo12_off_init) given the data and switches no core
# reference run has, so that the paths the core models do not reach are
# checked against GAMS running ppmain.mod L1-247 and L249-615 (with
# pp_prelv.vda), preppm.mod L1-212 and L218-252 and prep_ext.vda itself
# (scripts/make_pp_prelv_unit.jl, test/unit/test_m13_pp_prelv.jl).
#
# demo12 (see ppmain_tslvl_case.jl): REG1's timeslices are ANNUAL, S, W, SD,
# SN, WD, WN (ALL_TS in that order, STOA the lag to ANNUAL); TS_CYCLE holds
# ANNUAL, S and W; ELCTECOA00 runs at SEASON, ELCTEGAS00 at DAYNITE, both
# with ELC as PG, an ACT_EFF group on ACT and their fuel as shadow group;
# TOP_IRE has dummy imports (IMPNRGZ) from IMPEXP of every energy carrier.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!
import TOML

"""
The cases run by GAMS:

- "flofr": FLO_FR at ANNUAL only on a DAYNITE flow (copied to its
  timeslices, pp_lvlfc.mod L35) and at ANNUAL, SD and SN on a SEASON flow
  with an option record (aggregated to S, inherited to W, L38-42; the 'N'
  fractions, L102, and RVPCSL made and dropped again, L106-107); NCAP_CHPR
  'N' options -1 and EPS (L98);
  COM_BNDNET 'N' -1 and COM_BNDPRD 'N' EPS (L117-122); IRE_BND from IMPEXP
  (NE, L91 and L111); a night storage process with FLO_SHAR (FLO_ASHAR,
  L96-97).
- "groups": %SHELL% ANSWER (L17); VDA_FLOP on a group (RP_GRP, CG_GRP, the
  group FLO_SUM of L59), on a shadow commodity of an ACT_EFF process
  (removed, L16) and on one kept by KEEP_FLOF (L61).
"""
const PP_PRELV_CASES = ["flofr", "groups"]

function pp_prelv_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_init"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    pp_prelv_case!(tm, name)
    return tm
end

const PV_EPS = 0.0                                                # a stored 0.0 is EPS

function pp_prelv_case!(tm, name)
    put!(n, N, kv...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, kv); gput!(tm, n, v))
    add!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> push!(s, k), ks); gput!(tm, n, s))
    drop!(n, N, f) = (s = gmembers(tm, n, N); filter!(k -> !f(k), s); gput!(tm, n, s))
    if name == "flofr"
        fr(y, p, s, bd, x) = ("REG1", y, p, "ELC", s, bd) => x
        put!("FLO_FR", 6, fr("2010", "ELCTEGAS00", "ANNUAL", "LO", 0.3),
             fr("0", "ELCTECOA00", "ANNUAL", "UP", 1.0), fr("2015", "ELCTECOA00", "ANNUAL", "UP", 0.5),
             fr("2015", "ELCTECOA00", "SD", "UP", 0.2), fr("2015", "ELCTECOA00", "SN", "UP", 0.1))
        put!("NCAP_CHPR", 4, ("REG1", "0", "ELCTEGAS00", "N") => -1.0, ("REG1", "0", "ELCTECOA00", "N") => PV_EPS)
        put!("COM_BNDNET", 5, ("REG1", "0", "DCOT", "ANNUAL", "N") => -1.0, ("REG1", "2020", "DCOT", "ANNUAL", "N") => 2.0)
        put!("COM_BNDPRD", 5, ("REG1", "0", "DCAP", "ANNUAL", "N") => PV_EPS)
        put!("IRE_BND", 7, ("REG1", "2010", "ELC", "ANNUAL", "IMPEXP", "IMP", "UP") => 5.0)
        drop!("PRC_TSL", 3, k -> k[1] == "REG1" && k[2] == "COTEGAS")
        add!("PRC_TSL", 3, ("REG1", "COTEGAS", "DAYNITE"))
        add!("PRC_NSTTS", 3, ("REG1", "COTEGAS", "SN"))
        put!("FLO_SHAR", 7, ("REG1", "2010", "COTEGAS", "COMGAS", "NRG", "ANNUAL", "UP") => 0.5)
    elseif name == "groups"
        tm.switches["SHELL"] = "ANSWER"
        put!("VDA_FLOP", 5, ("REG1", "2010", "ELCTEGAS00", "NRG", "ANNUAL") => 0.4, ("REG1", "2010", "ELCTEGAS00", "ELCGAS", "ANNUAL") => 0.6,
             ("REG1", "2010", "ELCTECOA00", "ELCCOA", "S") => 0.7)
        add!("KEEP_FLOF", 3, ("REG1", "ELCTECOA00", "ELCCOA"))
    else
        error("unknown pp_prelv case $name")
    end
    return tm
end

"What pp_prelv.vda and pp_lvlfc.mod write, besides what the steps before them wrote, compared at the end of ppmain.mod L615."
const PP_PRELV_OUTPUTS = unique!(vcat(PPMAIN_LIFE_OUTPUTS,
    ["VDA_FLOP", "KEEP_FLOF", "ACT_FLO", "RPC_AFLO", "RP_GRP", "PRC_ACT", "RP_XRED", "CG_GRP", "RPCC_FFUNC", "FLO_FUNC", "FLO_SUM",
     "IRE_FLOSUM", "RP_CGC", "FLO_EMIS", "RPC_EMIS", "FSCK", "FLO_EFF", "NE", "FLO_ASHAR", "FLO_SHAR", "NCAP_CHPR", "RPC_CONLY",
     "FLO_FR", "RVPCSL", "TOP_IRE", "COM_BNDNET", "COM_BNDPRD", "UNCD7", "TS_ARRAY", "PRC_CG", "Z"]))
