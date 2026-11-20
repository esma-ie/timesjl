# Crafted states for ppmain.mod L683-797 (v4.9.7): the commodity attributes
# levelled to the commodity timeslices (pp_lvlfc.mod), COM_FR completed and
# normalised, the elastic demand steps, the availability factors levelled to
# the process timeslices (pp_lvlbr.mod) and the peak contributions
# (pp_lvlpk.mod). The TIMES_Demo demo12 prelv checkpoint
# (test/fixtures/demo12_off_prelv) is given data no core reference run has,
# and GAMS runs ppmain.mod L616-797 itself on it
# (scripts/make_ppmain_tsattr_unit.jl), so the paths the core models do not
# reach are checked against GAMS (test/unit/test_m13_ppmain_tsattr.jl).
#
# demo12 (REG1): the timeslices ANNUAL, S and W (SEASON), SD, SN, WD and WN
# (DAYNITE). AGRELC, COMELC, ELC, RSDELC and TRAELC are tracked at DAYNITE,
# the other commodities (the demands too) at ANNUAL; COM_FR is given for the
# demands at DAYNITE, COM_IE for ELC at ANNUAL. ELCTECOA00, ELCNENUC00 and
# ELCTNCOA01 run at SEASON, ELCTEGAS00, ELCTNGAS01, ELCTNOIL01 and the
# renewables at DAYNITE, the rest at ANNUAL; NCAP_AF is given for four
# renewables at DAYNITE (UP), NCAP_PKCNT at ANNUAL for 16 power plants; the
# peak commodity is ELC (COM_PKTS at SD, SN, WD, WN). MODLYEAR is 1960, 1980,
# 2004 and the milestones 2005, 2010, 2015, 2020, 2030, 2050. No storage,
# PRC_PKAF, PRC_PKNO, NCAP_AFS or elastic demand data.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!, gset
import TOML

"""
The cases run by GAMS:

- "com": COM_IE of ELC at S and WD (inherited to SD, SN; WN, given in other
  years, so in RCS at L704, gets no default 1), of COA (ANNUAL) at S and an
  EPS at W (aggregated), EPS at ANNUAL; COM_FR of ELC at S and W summing to 1.2 in every milestone but
  2010 (1.0) (weighted inheritance, then normalised), of AGRELC at SD alone
  in every milestone (the other DAYNITE slices filled with G_YRFR, L712), of
  COMELC at ANNUAL (copied by year fraction, then dropped at L708), of DCOT
  at SD alone in 2015 (normalised); COM_PKFLX at ANNUAL and S; OBJ_COMNT and OBJ_COMPD at
  ANNUAL and W, one in a year outside DATAYEAR; COM_ELAST of DCOT at S and
  W (aggregated), with COM_BPRICE and COM_VOC (made negative), without
  COM_BPRICE (dropped), EPS (dropped), FX (kept); COM_BPRICE at S;
  COM_STEP FX for DCOT and DCAP (the LO default MAX(1,FX), RCJ); COM_BQTY
  at S and W (weighted aggregation) and at ANNUAL for ELC.
- "af": NCAP_AF of ELCTECOA00 (SEASON) at ANNUAL (inherited), at SD, SN
  and WD (aggregated to S and W), at S with SD below (warning, SD ignored),
  FX with UP and LO at S (LO and UP removed); of ELCTEGAS00 (DAYNITE) at
  ANNUAL with NCAP_AFS at SD (NCAP_AFS kept), at ANNUAL and S (levelled
  through both); of ELCTNGAS01 at SD (UP) and an EPS FX at WD (SN, WD, WN
  leave PRC_TS and RPCS_VAR for RTPCS_OUT); of ELCTNOIL01 at WD with
  ELCTNOIL01 a storage (EPS at the other slices); of ELCTNCOA01 at S alone
  (W and the DAYNITE slices below it leave); LO alone for COTEGAS (default
  UP 1); a record at a year outside MODLYEAR.
- "pk": NCAP_PKCNT of ELCTEGAS00 at S and W without ANNUAL (levelled from
  the default 1), at ANNUAL and SD; ELCTNGAS01 in PRC_PKAF without
  NCAP_PKCNT (the default from NCAP_AF, RPC_PKF EPS, RPC_PKC through the
  ELC loop); ELCTEOIL00 in PRC_PKNO with FLO_PKCOI (dropped), ELCTECOA00
  with FLO_PKCOI (kept).
"""
const PPMAIN_TSATTR_CASES = ["com", "af", "pk"]

function ppmain_tsattr_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_prelv"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    ppmain_tsattr_case!(tm, name)
    return tm
end

const PT_EPS = 0.0                                                # a stored 0.0 is EPS

function ppmain_tsattr_case!(tm, name)
    put!(n, N, kv...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, kv); gput!(tm, n, v))
    del!(n, N, ks...) = (v = gvalues(tm, n, N); foreach(k -> delete!(v, k), ks); gput!(tm, n, v))
    add!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> push!(s, k), ks); gput!(tm, n, s))
    T = ["2005", "2010", "2015", "2020", "2030", "2050"]
    r = "REG1"
    if name == "com"
        # COM_IE (L694, L705)
        del!("COM_IE", 4, (r, "2015", "ELC", "ANNUAL"), (r, "2030", "ELC", "ANNUAL"))
        put!("COM_IE", 4, (r, "2015", "ELC", "S") => 0.8, (r, "2015", "ELC", "WD") => 0.95, (r, "2020", "COA", "S") => 0.9,
             (r, "2020", "COA", "W") => PT_EPS, (r, "2030", "ELC", "ANNUAL") => PT_EPS)
        # COM_FR (L695, L708-742)
        # (a COM_FR commodity needs data in every milestone: an ANNUAL sum of 0 stops GAMS at L729, G48)
        put!("COM_FR", 4, ((r, t, "ELC", "S") => 0.6 for t in T)..., ((r, t, "ELC", "W") => 0.6 for t in T)...,
             ((r, t, "COMELC", "ANNUAL") => 1.0 for t in T)..., ((r, t, "AGRELC", "SD") => 0.2 for t in T)...)
        put!("COM_FR", 4, (r, "2010", "ELC", "W") => 0.4)
        del!("COM_FR", 4, (r, "2015", "DCOT", "SN"), (r, "2015", "DCOT", "WD"), (r, "2015", "DCOT", "WN"))
        put!("COM_FR", 4, (r, "2015", "DCOT", "SD") => 0.3)
        # COM_PKFLX (L696)
        put!("COM_PKFLX", 4, (r, "2010", "ELC", "ANNUAL") => 0.1, (r, "2015", "ELC", "S") => 0.2)
        # OBJ_COMNT, OBJ_COMPD (L697-698): 2011 is outside DATAYEAR
        put!("OBJ_COMNT", 6, (r, "2010", "ELC", "ANNUAL", "TAX", "MEuro05") => 5.0, (r, "2011", "ELC", "ANNUAL", "TAX", "MEuro05") => 4.0)
        put!("OBJ_COMPD", 6, (r, "2010", "ELC", "W", "COST", "MEuro05") => 3.0)
        # elastic demands (L699-700, L747-754)
        put!("COM_ELAST", 5, (r, "2010", "DCOT", "S", "LO") => 0.5, (r, "2010", "DCOT", "W", "LO") => 0.7,
             (r, "2015", "DCOT", "ANNUAL", "UP") => 0.4, (r, "2020", "DCOT", "ANNUAL", "LO") => PT_EPS,
             (r, "2010", "DCAP", "ANNUAL", "FX") => 0.2, (r, "2020", "DCAP", "ANNUAL", "LO") => 0.6)
        put!("COM_BPRICE", 5, (r, "2010", "DCOT", "ANNUAL", "MEuro05") => 10.0, (r, "2020", "DCOT", "ANNUAL", "MEuro05") => 11.0,
             (r, "2015", "DCOT", "S", "MEuro05") => 12.0, (r, "2020", "DCAP", "ANNUAL", "MEuro05") => 9.0)
        put!("COM_VOC", 4, (r, "2010", "DCOT", "LO") => 0.3, (r, "2020", "DCOT", "LO") => 0.3, (r, "2020", "DCAP", "LO") => 0.2)
        put!("COM_STEP", 3, (r, "DCOT", "FX") => 3.0, (r, "DCAP", "FX") => 2.0)
        # COM_BQTY (L701)
        put!("COM_BQTY", 3, (r, "DCOT", "S") => 100.0, (r, "DCOT", "W") => 50.0, (r, "ELC", "ANNUAL") => 80.0)
    elseif name == "af"
        af(v, p, s, bd, x) = (r, v, p, s, bd) => x
        put!("NCAP_AF", 5, af("2010", "ELCTECOA00", "ANNUAL", "UP", 0.8),
             af("2015", "ELCTECOA00", "SD", "UP", 0.9), af("2015", "ELCTECOA00", "SN", "UP", 0.7), af("2015", "ELCTECOA00", "WD", "UP", 0.6),
             af("2020", "ELCTECOA00", "S", "UP", 0.85), af("2020", "ELCTECOA00", "SD", "UP", 0.5),
             af("2030", "ELCTECOA00", "S", "FX", 0.7), af("2030", "ELCTECOA00", "S", "UP", 0.9), af("2030", "ELCTECOA00", "S", "LO", 0.2),
             af("2010", "ELCTEGAS00", "ANNUAL", "UP", 0.9),
             af("2015", "ELCTEGAS00", "ANNUAL", "UP", 0.9), af("2015", "ELCTEGAS00", "S", "UP", 0.8),
             af("2010", "ELCTNGAS01", "SD", "UP", 0.9), af("2015", "ELCTNGAS01", "WD", "FX", PT_EPS),
             af("2010", "ELCTNOIL01", "WD", "UP", 0.5),
             af("2020", "ELCTNCOA01", "S", "UP", 0.9),
             af("2010", "COTEGAS", "ANNUAL", "LO", 0.3),
             af("2012", "ELCTECOA00", "ANNUAL", "UP", 0.4))
        put!("NCAP_AFS", 5, (r, "2010", "ELCTEGAS00", "SD", "UP") => 0.5)
        add!("RP_STG", 2, (r, "ELCTNOIL01"))
    elseif name == "pk"
        pk(v, p, s, x) = (r, v, p, s) => x
        del!("NCAP_PKCNT", 4, (r, "2010", "ELCTEGAS00", "ANNUAL"), (r, "2015", "ELCTEGAS00", "ANNUAL"))
        put!("NCAP_PKCNT", 4, pk("2010", "ELCTEGAS00", "S", 0.7), pk("2010", "ELCTEGAS00", "W", 0.5),
             pk("2015", "ELCTEGAS00", "ANNUAL", 0.8), pk("2015", "ELCTEGAS00", "SD", 0.6))
        v = gvalues(tm, "NCAP_PKCNT", 4)
        filter!(((k, _),) -> k[3] != "ELCTNGAS01", v)
        gput!(tm, "NCAP_PKCNT", v)
        add!("PRC_PKAF", 2, (r, "ELCTNGAS01"))
        put!("NCAP_AF", 5, (r, "2010", "ELCTNGAS01", "ANNUAL", "UP") => 0.85, (r, "2015", "ELCTNGAS01", "WD", "FX") => 0.95)
        add!("PRC_PKNO", 2, (r, "ELCTEOIL00"))
        put!("FLO_PKCOI", 5, (r, "2010", "ELCTEOIL00", "ELC", "ANNUAL") => 1.2, (r, "2010", "ELCTECOA00", "ELC", "ANNUAL") => 1.1)
    else
        error("unknown ppmain_tsattr case $name")
    end
    return tm
end

"What ppmain.mod L683-797 writes, on top of ppmain.mod L616-682 (PPMAIN_DFLT_OUTPUTS), compared at L797, scratch included."
const PPMAIN_TSATTR_NEW = ["RTC_NET", "COM_IE", "COM_FR", "COM_PKFLX", "OBJ_COMNT", "OBJ_COMPD", "COM_ELAST", "COM_BPRICE", "COM_BQTY",
                           "TS_ARRAY", "RCS", "RP_PGFLO", "TRACKC", "RS_FR", "RTCS_FR", "DEM", "COM_STEP", "RC_AGP", "RCJ", "RTPS_BD",
                           "NCAP_AF", "RXX", "TRACKP", "PRC_TS2", "PRC_TS", "RTPCS_OUT", "RPC_PKC", "RPC_PKF", "RTP_ISHPR",
                           "FLO_PKCOI", "NCAP_PKCNT"]

"What ppmain.mod L683-797 and the files it includes declare themselves (L737; pp_lvlpk.mod L12-13)."
const PPMAIN_TSATTR_DECLARED_NEW = ["RTCS_FR", "RPC_PKC", "RPC_PKF"]
