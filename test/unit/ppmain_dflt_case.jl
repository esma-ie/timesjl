# Crafted states for ppmain.mod L616-682 (v4.9.7): pp_qafs.mod, SHAPE and
# MULTI (filshape.gms, filparam.gms), the defaults and the commodities
# involved only with capacity. The TIMES_Demo demo12 prelv checkpoint
# (test/fixtures/demo12_off_prelv) is given the data and switches no core
# reference run has, and GAMS runs ppmain.mod L616-682 itself on it
# (scripts/make_ppmain_dflt_unit.jl), so the paths the core models do not
# reach are checked against GAMS (test/unit/test_m13_ppmain_dflt.jl).
#
# demo12 (REG1): the input share groups FTE-ELCOIL_NRGI (DSL, HFO, LPG, OPP),
# FTE-INDOIL_NRGI (DSL, GSL, HFO, KER, LPG, NAP, OPP), FTE-COMOIL_NRGI,
# IDM1ETOT_NRGI (INDBIO, INDCOA, INDELC, INDGAS, INDOIL) and AOTETOT_NRGI,
# and the output group REFEOIL00_NRGO (DSL, GSL, HFO, KER, LPG, NAP, OPP),
# each with UP shares at ANNUAL in every model year. MODLYEAR is 1960,
# 1980, 2004, 2005, 2010, 2015, 2020, 2030, 2050 (the milestones from 2005).
# No CHP, storage, SHAPE or MULTI data; the NCAP_TLIFE are at most 60.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!, gset
import TOML

"""
The cases run by GAMS:

- "qafs" (%SHARELAX% unset, so on): a share of a commodity outside its
  group (L16-19); FX with UP (L30-37); UP of 1 or more, a share below
  %SHARETOL%, a negative FX and an LO within it of 1 (L42-44); a group with
  all shares fixed summing to 1.5, two of them above the limit (L52-64:
  only the first is dropped); a group whose FX and UP shares sum to 0.8
  (L73-86); a group whose LO and FX shares sum to 1.7 (L93-107); a group
  with a non-ANNUAL share (L25-26: not checked).
- "dflt" (%SHARELAX% NO): SHAPE with interpolation, a single point and EPS
  points (filshape.gms); COM_ELASTX and COM_VOC (RTC_SHED, STARTOFF above
  MAXLIFE); MULTI with interpolation, an option -1, an EPS point and index
  '1' (filparam.gms, L632-634); NCAP_ELIFE EPS; NCAP_OCOM, NCAP_DLIFE,
  NCAP_DELIF; NCAP_ICOM with COEF_ILED; CHP with NCAP_CDME and NCAP_CHPR
  'N' EPS; storage without STG_EFF; RPC_NOFLO with UC_ATTR CAPFLO, a PG,
  a commodity outside RPC, shares, an actflow and trade processes with and
  without RPC_IRE; TRACKPC and RTP_CGC holding members already; a group
  with all shares fixed summing to 1.5 (no share dropped with %SHARELAX% NO).
- "notgrp": a share of a commodity of the process (in RPC) outside its group,
  the only one of L16: `NOT RPC(R,P,C)\$COM_GMAP(R,CG,C)` is true for it
  (`\$` binds before NOT), so RP_CCG loses it (L19) and RPG_RED gets no
  output group of FTE-AGROIL.
"""
const PPMAIN_DFLT_CASES = ["qafs", "dflt", "notgrp"]

function ppmain_dflt_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_prelv"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    ppmain_dflt_case!(tm, name)
    return tm
end

const PD_EPS = 0.0                                                # a stored 0.0 is EPS

function ppmain_dflt_case!(tm, name)
    put!(n, N, kv...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, kv); gput!(tm, n, v))
    add!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> push!(s, k), ks); gput!(tm, n, s))
    # the shares of a group at year y replaced
    function shares!(p, cg, y, kv...)
        v = gvalues(tm, "FLO_SHAR", 7)
        filter!(e -> !(e[1][1] == "REG1" && e[1][2] == y && e[1][3] == p && e[1][5] == cg), v)
        foreach(((c, s, bd, x),) -> v[("REG1", y, p, c, cg, s, bd)] = x, kv)
        gput!(tm, "FLO_SHAR", v)
    end
    fixed15!(y) = shares!("FTE-ELCOIL", "FTE-ELCOIL_NRGI", y, ("LPG", "ANNUAL", "FX", 0.8), ("HFO", "ANNUAL", "FX", 0.7),
                          ("DSL", "ANNUAL", "FX", 0.0), ("OPP", "ANNUAL", "FX", 0.0))
    if name == "qafs"
        # L16-19: ELC is neither an input of FTE-AGROIL nor in its group
        put!("FLO_SHAR", 7, ("REG1", "2010", "FTE-AGROIL", "ELC", "FTE-AGROIL_NRGI", "ANNUAL", "UP") => 1.0)
        # L30-37: FX with UP on DSL
        put!("FLO_SHAR", 7, ("REG1", "2010", "FTE-COMOIL", "DSL", "FTE-COMOIL_NRGI", "ANNUAL", "FX") => 0.86,
             ("REG1", "2010", "FTE-COMOIL", "DSL", "FTE-COMOIL_NRGI", "S", "UP") => 0.9)
        # L42-44 on AOTETOT in 2030
        aot(c, s, bd, x) = ("REG1", "2030", "AOTETOT", c, "AOTETOT_NRGI", s, bd) => x
        put!("FLO_SHAR", 7, aot("AGROIL", "ANNUAL", "UP", 1.2), aot("AGRELC", "ANNUAL", "UP", 0.00001), aot("AGRGAS", "ANNUAL", "FX", -0.5),
             aot("AGRBIO", "ANNUAL", "LO", 0.99995), aot("AGRCOA", "S", "UP", 1.5))
        # L52-64: all fixed, 0.8 + 0.7 + EPS + EPS
        fixed15!("2010")
        # L73-86: FX + UP summing to 0.8
        shares!("FTE-INDOIL", "FTE-INDOIL_NRGI", "2015", ("GSL", "ANNUAL", "UP", 0.1), ("DSL", "ANNUAL", "UP", 0.2), ("KER", "ANNUAL", "UP", 0.1),
                ("LPG", "ANNUAL", "UP", 0.1), ("NAP", "ANNUAL", "FX", 0.1), ("HFO", "ANNUAL", "UP", 0.1), ("OPP", "ANNUAL", "UP", 0.1))
        # L93-107: LO + FX summing to 1.7, the existing UP shares in 2020 kept
        v = gvalues(tm, "FLO_SHAR", 7)
        for (c, bd, x) in (("DSL", "LO", 0.9), ("GSL", "LO", 0.3), ("NAP", "FX", 0.1), ("KER", "LO", 0.1), ("OPP", "LO", 0.1),
                           ("HFO", "LO", 0.1), ("LPG", "LO", 0.1))
            v[("REG1", "2020", "REFEOIL00", c, "REFEOIL00_NRGO", "ANNUAL", bd)] = x
        end
        gput!(tm, "FLO_SHAR", v)
        # L25-26: a share at S keeps IDM1ETOT_NRGI from the checks; its FX sum to 1.2
        shares!("IDM1ETOT", "IDM1ETOT_NRGI", "2010", ("INDOIL", "ANNUAL", "FX", 0.3), ("INDELC", "ANNUAL", "FX", 0.3),
                ("INDGAS", "ANNUAL", "FX", 0.2), ("INDCOA", "ANNUAL", "FX", 0.2), ("INDBIO", "ANNUAL", "FX", 0.2),
                ("INDELC", "S", "UP", 0.3))
    elseif name == "dflt"
        tm.switches["SHARELAX"] = "NO"
        fixed15!("2015")
        # SHAPE and its limit
        put!("SHAPE", 2, ("2", "5") => 0.8, ("2", "10") => 0.5, ("2", "30") => PD_EPS, ("3", "1") => 1.1, ("4", "3") => PD_EPS,
             ("5", "20") => 0.6, ("5", "8") => 0.9)
        put!("COM_ELASTX", 4, ("REG1", "2010", "DCOT", "LO") => 2.0, ("REG1", "2015", "DCAP", "UP") => 2.6, ("REG1", "2020", "DCAP", "LO") => PD_EPS,
             ("REG1", "2004", "DCOT", "UP") => 5.0)
        put!("COM_VOC", 4, ("REG1", "2010", "DCOT", "LO") => 0.85, ("REG1", "2015", "DCAP", "UP") => 0.4, ("REG1", "2004", "DCOT", "UP") => 3.0)
        # MULTI
        put!("MULTI", 2, ("2", "2010") => 1.2, ("2", "2030") => 1.5, ("3", "0") => -1.0, ("3", "2020") => 0.5, ("4", "2015") => PD_EPS,
             ("5", "2010") => 2.0, ("5", "0") => 1.0, ("1", "2010") => 3.0, ("6", "2008") => 0.4, ("6", "2012") => 0.8)
        # the defaults
        put!("NCAP_ELIFE", 3, ("REG1", "2010", "ELCTECOA00") => PD_EPS, ("REG1", "2015", "ELCTECOA00") => 25.0)
        put!("NCAP_OCOM", 4, ("REG1", "2010", "ELCTECOA00", "ELCCOA") => 0.5, ("REG1", "2015", "ELCTECOA00", "ELCCOA") => 0.5,
             ("REG1", "2020", "ELCTECOA00", "ELCCOA") => 0.5, ("REG1", "2010", "ELCTEGAS00", "DCOT") => 0.5,
             ("REG1", "2004", "ELCTECOA00", "ELCCOA") => 0.5)
        put!("NCAP_DLIFE", 3, ("REG1", "2015", "ELCTECOA00") => 3.0)
        put!("NCAP_DELIF", 3, ("REG1", "2020", "ELCTECOA00") => PD_EPS)
        put!("NCAP_ICOM", 4, ("REG1", "2010", "ELCTEGAS00", "COA") => 0.2, ("REG1", "2015", "ELCTEGAS00", "COA") => 0.2,
             ("REG1", "2020", "ELCTEGAS00", "COA") => 0.2)
        put!("COEF_ILED", 3, ("REG1", "2010", "ELCTEGAS00") => 2.0, ("REG1", "2020", "ELCTEGAS00") => PD_EPS)
        put!("NCAP_CLED", 4, ("REG1", "2015", "ELCTEGAS00", "COA") => 4.0)
        add!("CHP", 2, ("REG1", "ELCTECOA00"), ("REG1", "ELCTEGAS00"))
        put!("NCAP_CDME", 3, ("REG1", "2010", "ELCTECOA00") => 0.4, ("REG1", "2015", "ELCTECOA00") => 0.4)
        put!("NCAP_BPME", 3, ("REG1", "2015", "ELCTECOA00") => 0.9)
        put!("NCAP_CHPR", 4, ("REG1", "2010", "ELCTEGAS00", "N") => PD_EPS)
        add!("RP_STG", 2, ("REG1", "COTEGAS"), ("REG1", "ELCTECOA00"), ("REG1", "FTE-ELCOIL"))
        put!("STG_EFF", 3, ("REG1", "2004", "ELCTECOA00") => 0.8, ("REG1", "2010", "FTE-ELCOIL") => 0.9)
        # capacity-only flows
        add!("RPC_NOFLO", 3, ("REG1", "ELCTECOA00", "ELC"), ("REG1", "ELCTECOA00", "DCAP"), ("REG1", "FTE-ELCOIL", "HFO"),
             ("REG1", "ELCTEGAS00", "ELCGAS"), ("REG1", "EXPCOA1", "COA"), ("REG1", "EXPCOA1", "DSL"), ("REG1", "COTEGAS", "DCOT"))
        add!("UC_ATTR", 5, ("REG1", "UC_RNW-PP_LOW", "LHS", "FLO", "CAPFLO"))
        add!("TRACKPC", 3, ("REG1", "ELCTEGAS00", "ELC"))
        add!("RTP_CGC", 5, ("REG1", "2050", "FTE-INDOIL", "DSL", "FTE-INDOIL_NRGI"))
    elseif name == "notgrp"
        put!("FLO_SHAR", 7, ("REG1", "2010", "FTE-AGROIL", "AGROIL", "FTE-AGROIL_NRGI", "ANNUAL", "UP") => 0.5)
    else
        error("unknown ppmain_dflt case $name")
    end
    return tm
end

"What ppmain.mod L616-682 writes (compared at L682, scratch included)."
const PPMAIN_DFLT_OUTPUTS = ["FLO_SHAR", "RP_CCG", "RPG_RED", "RTP_CGC", "RTPGIG", "RTP_CG", "RTP_GRP", "RP_GIC", "UNCD7",
                             "Z", "F", "MY_F", "MAXLIFE", "RTC_SHED", "STARTOFF", "SHAPE", "AGEFIL", "LAST_VAL", "MY_FYEAR",
                             "FIRST_VAL", "DFUNC", "MY_ARRAY", "MULTI", "NCAP_ELIFE", "NCAP_DLIFE", "NCAP_DELIF", "NCAP_CLED",
                             "NCAP_BPME", "NCAP_CHPR", "STG_EFF", "UC_CAPFLO", "RPC_NOFLO", "RPCS_VAR", "TRACKPC"]

"What ppmain.mod L616-682 and the files it includes declare themselves (not written into the replayed state)."
const PPMAIN_DFLT_DECLARED = ["MAXLIFE", "UC_CAPFLO", "RTPGIG", "RTP_CG", "RTP_GRP", "RP_GIC", "AGEFIL"]
