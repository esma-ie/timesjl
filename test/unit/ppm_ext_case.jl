# Crafted states for ppm_ext.vda (v4.9.7): L11-58 with pp_actef.vda LVL,
# the ACT_EFF preparation (18a), and L59-169 (18b). The TIMES_Demo demo12
# prelv checkpoint (test/fixtures/demo12_off_prelv) is given data no core
# reference run has, and GAMS runs ppmain.mod L616-1357 and ppm_ext.vda
# L11-58 or L11-169 itself on it (scripts/make_ppm_ext_unit.jl;
# test/unit/test_m13_ppm_ext.jl, test/unit/test_m13_ppm_ext_end.jl). The
# 18b cases need ppmain_flo_case! (test/unit/ppmain_flo_case.jl).
#
# demo12, REG1: ELCTECOA00 runs at SEASON (PRC_TSL), takes ELCCOA (its
# shadow group NRG) and makes ELC (its primary group) and ELCCO2; it has
# ACT_EFF on ACT at ANNUAL. FTE-AGRELC (DAYNITE) takes ELC (shadow group
# NRG) and makes AGRELC. ELCREHYD00 (DAYNITE) takes ELCHYD (shadow group
# NRG) and makes ELC. RSHEOIL (ANNUAL, vintages from 2004) takes RSDOIL
# (shadow group NRG). Timeslices: ANNUAL; S, W (SEASON); SD, SN, WD, WN
# (DAYNITE).

using OpenTIMES: TimesModel, gvalues, gmembers, gput!
import TOML

"""
The cases run by GAMS:

- "ace": ACT_EFF below the process level (ELCTECOA00 at SD and SN in 2020,
  so ACT_EFF goes to the group NRG at L50, is levelled up to S and W at
  pp_actef.vda L37-42 and dropped at ANNUAL at L45); a VDA_FLOP record of
  RSHEOIL left at the prelv checkpoint (projected into RPC_ACE at L28, so
  RSHEOIL gets an UNCD7 row without ACT_EFF below ANNUAL); ACT_EFF on
  the primary-group commodity AGRELC of FTE-AGRELC (RPG_PACE, L41-43); and
  commodity ACT_EFF on the shadow-group commodity ELCHYD of ELCREHYD00, one
  of them EPS, which the levelling copies (L46). pp_actef.vda L22 (SQRT on a
  shadow-group commodity) needs an RPG_ACE record whose group is such a
  commodity, which L38 and L54 never write (TRACKPC holds RPC_ACE's
  commodities, L35, and L54 writes commodity types): no state reaches it.
- "upl": ramping and partial loads: ACT_UPS on ELCTECOA00 and on a trade
  process (RP_UPL, L13-14), ACT_LOSPL 'FX' on ELCTECOA00 (RP_PL, L15), which
  keeps its NRG group out of the singleton groups (pp_actef.vda L19), with
  ACT_EFF at S and W; ACT_EFF at S and W on RSHEOIL (ANNUAL), with NORTS on
  W for its past vintage 2004 (pp_actef.vda L31). NORTS on a milestone would
  also zero COM_FR there (ppmain.mod L720), and demo12's COM_FR then stops
  GAMS with a division by EPS (L729, G48).
"""
const PPM_EXT_CASES = ["ace", "upl"]

function ppm_ext_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    sw = Dict{String,String}(k => string(v) for (k, v) in fx["switches"])
    tm = TimesModel(joinpath(fixtures, "demo12_off_prelv"); switches=sw)
    name in PPM_EXT_CASES_B && return ppm_ext_case_b!(tm, name)
    ae = gvalues(tm, "ACT_EFF", 5)
    ace = gmembers(tm, "RPC_ACE", 3)
    if name == "ace"
        ae[("REG1", "2020", "ELCTECOA00", "ACT", "SD")] = 0.40
        ae[("REG1", "2020", "ELCTECOA00", "ACT", "SN")] = 0.30
        gput!(tm, "VDA_FLOP", Dict(("REG1", "2010", "RSHEOIL", "NRG", "ANNUAL") => 1.1))
        ae[("REG1", "2010", "FTE-AGRELC", "AGRELC", "ANNUAL")] = 0.9
        push!(ace, ("REG1", "FTE-AGRELC", "AGRELC"))
        ae[("REG2", "2030", "ELCREHYD00", "ELCHYD", "ANNUAL")] = 0.81
        ae[("REG2", "2010", "ELCREHYD00", "ELCHYD", "ANNUAL")] = 0.0      # EPS
        push!(ace, ("REG2", "ELCREHYD00", "ELCHYD"))
    elseif name == "upl"
        gput!(tm, "ACT_UPS", Dict(("REG1", "2010", "ELCTECOA00", "ANNUAL", "FX") => 0.3,
                                  ("REG1", "2010", "IMPNRGZ", "ANNUAL", "UP") => 0.5))
        gput!(tm, "ACT_LOSPL", Dict(("REG1", "2010", "ELCTECOA00", "FX") => 0.1))
        ae[("REG1", "2010", "ELCTECOA00", "ACT", "S")] = 0.41
        ae[("REG1", "2010", "ELCTECOA00", "ACT", "W")] = 0.37
        ae[("REG1", "2004", "RSHEOIL", "ACT", "S")] = 0.8
        ae[("REG1", "2004", "RSHEOIL", "ACT", "W")] = 0.7
        ae[("REG1", "2010", "RSHEOIL", "ACT", "S")] = 0.85
        gput!(tm, "NORTS", Dict(("REG1", "2004", "W") => -Inf))   # a past vintage: ppmain.mod L720 (COM_FR) reads milestones only
    else
        error("unknown ppm_ext case $name")
    end
    gput!(tm, "ACT_EFF", ae)
    gput!(tm, "RPC_ACE", ace)
    return tm
end

"""
The cases of ppm_ext.vda L59-169 run by GAMS (18b), on top of PPM_EXT_CASES:

- "chp": test/unit/ppmain_flo_case.jl's "chp" state (REFEOIL00 and
  ELCTEGAS00 made CHPs), with NCAP_CEH 2 on ELCTEGAS00 in 2010 and 2015
  (an ECT CHP: the automatic NCAP_AFCS of ppm_ext.vda L145-156) and an
  NCAP_AF 'UP' at ANNUAL in 2010.
- "afx": the NCAP_AFX and NCAP_AFM options at '0' (L159-164): ELCTECOA00
  1001 (odd: NCAP_AFSX for UP and FX), ELCTEGAS00 5000 (RP_AFB -1),
  FTE-AGRELC 2000 (even: LO); NCAP_AFM 2000 on ELCTECOA00 (NCAP_AFSM) and
  5000 on ELCTEGAS00 (its NCAP_AFM at the model years dropped).
- "funcx": FLO_FUNCX shape indexes (L61-65) on ELCTECOA00 (ACT to its
  shadow group NRG, ACT to the primary group ELC) and FTE-AGRELC.
"""
const PPM_EXT_CASES_B = ["chp", "afx", "funcx"]

function ppm_ext_case_b!(tm, name)
    put!(n, N, kv...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, kv); gput!(tm, n, v))
    r = "REG1"
    if name == "chp"
        ppmain_flo_case!(tm, "chp")
        put!("NCAP_CEH", 3, (r, "2010", "ELCTEGAS00") => 2.0, (r, "2015", "ELCTEGAS00") => 2.0)
        put!("NCAP_AF", 5, (r, "2010", "ELCTEGAS00", "ANNUAL", "UP") => 0.9)
    elseif name == "afx"
        put!("NCAP_AFX", 3, (r, "0", "ELCTECOA00") => 1001.0, (r, "2010", "ELCTECOA00") => 0.05, (r, "2020", "ELCTECOA00") => -0.1,
             (r, "0", "ELCTEGAS00") => 5000.0, (r, "2010", "ELCTEGAS00") => 0.02,
             (r, "0", "FTE-AGRELC") => 2000.0, (r, "2015", "FTE-AGRELC") => 0.03)
        put!("NCAP_AFM", 3, (r, "0", "ELCTECOA00") => 2000.0, (r, "2010", "ELCTECOA00") => 2.0,
             (r, "0", "ELCTEGAS00") => 5000.0, (r, "2010", "ELCTEGAS00") => 3.0, (r, "2015", "ELCTEGAS00") => 3.0)
    elseif name == "funcx"
        put!("FLO_FUNCX", 5, (r, "2010", "ELCTECOA00", "ACT", "ACT") => 2.0, (r, "2015", "ELCTECOA00", "ACT", "ELCCOA") => 3.0,
             (r, "2010", "FTE-AGRELC", "NRG", "ACT") => 4.0, (r, "2020", "FTE-AGRELC", "ACT", "ACT") => 5.0)
    else
        error("unknown ppm_ext case $name")
    end
    return tm
end
