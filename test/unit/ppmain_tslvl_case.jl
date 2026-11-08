# Crafted states for ppmain.mod L329-460 (v4.9.7), the commodity and process
# timeslice levels: the TIMES_Demo demo12 init checkpoint
# (test/fixtures/demo12_off_init) given the data no core reference run has,
# so that the paths the core models do not reach are checked against GAMS
# running ppmain.mod L1-247 and L249-460, preppm.mod L1-212 and L218-252 and
# prep_ext.vda itself (scripts/make_ppmain_tslvl_unit.jl,
# test/unit/test_m13_ppmain_tslvl.jl).
#
# demo12 (see ppmain_topo_case.jl): REG1 has the levels ANNUAL, SEASON (S, W)
# and DAYNITE (SD, SN, WD, WN), not WEEKLY; ELC and the electricity
# end-use commodities are at DAYNITE, the rest ANNUAL; every process has a
# PRC_TSL; COM_PEAK holds REG1.ELC without COM_PKTS; no storage.

using TIMES: TimesModel, gvalues, gmembers, gput!
import TOML

"""
The cases run by GAMS:

- "levels": a commodity level the region does not have (COMGAS at WEEKLY,
  moved to SEASON, L336) and a process level likewise whose coarser level
  the process already has (ELCNENUC00: the count does not change, so WEEKLY
  stays, L337); user COM_TS that set the level from the first timeslice
  (COMOIL; COMCOA, where the second timeslice is at another level and is
  kept, L343), that leave timeslices out (RSDELC: RCS, L347, and RPCS_VAR
  without them, L458) or that hold one at another level (AGRELC: removed,
  L346); user PRC_TS that set the level (COTEGAS, L394) or that are kept
  as given (CAPEELC); a process without level (COTECOA: ANNUAL, L395).
- "offpeak": COM_OFF with two ranges (COMGAS) and an open one (DCOT): RTC,
  COM_BNDPRD 'FX' EPS (L358-363); COM_PKTS above the level (ELC, L383),
  below it (COMGAS at SEASON), a group COM_PEAK without COM_PKTS (NRG,
  L385-388) and a commodity outside RC (ACT, L379-380); night storage
  (PRC_NSTTS) at DAYNITE with an ANNUAL record (COTEBIO: ANNUAL flow
  variables, L447-448), at ANNUAL only (ELCTEGAS00; CSHEBIO: RP_SGS,
  L408-410; CAPEELC, a DAYNITE process with an ANNUAL input: its ANNUAL
  record is removed and the shadow-level timeslices taken, L449-450), SGS
  (CSHEELC, L409) and STS at ANNUAL (CSHECOA).
"""
const PPMAIN_TSLVL_CASES = ["levels", "offpeak"]

function ppmain_tslvl_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_init"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    ppmain_tslvl_case!(tm, name)
    return tm
end

function ppmain_tslvl_case!(tm, name)
    add!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> push!(s, k), ks); gput!(tm, n, s))
    drop!(n, N, f) = (s = gmembers(tm, n, N); filter!(k -> !f(k), s); gput!(tm, n, s))
    if name == "levels"
        add!("COM_TSL", 3, ("REG1", "COMGAS", "WEEKLY"))
        add!("PRC_TSL", 3, ("REG1", "ELCNENUC00", "WEEKLY"))
        add!("COM_TS", 3, ("REG1", "COMOIL", "S"), ("REG1", "COMOIL", "W"), ("REG1", "COMCOA", "SD"), ("REG1", "COMCOA", "S"),
             ("REG1", "RSDELC", "SD"), ("REG1", "AGRELC", "S"), ("REG1", "AGRELC", "SD"))
        drop!("PRC_TSL", 3, k -> k[1] == "REG1" && k[2] in ("COTEGAS", "COTECOA"))
        add!("PRC_TS", 3, ("REG1", "COTEGAS", "S"), ("REG1", "COTEGAS", "W"), ("REG1", "CAPEELC", "S"))
    elseif name == "offpeak"
        add!("COM_OFF", 4, ("REG1", "COMGAS", "2012", "2022"), ("REG1", "COMGAS", "2045", "EOH"), ("REG1", "DCOT", "BOH", "2006"))
        add!("COM_PKTS", 3, ("REG1", "ELC", "S"), ("REG1", "COMGAS", "SD"), ("REG1", "ACT", "SD"))
        add!("COM_TSL", 3, ("REG1", "COMGAS", "SEASON"))
        add!("COM_PEAK", 2, ("REG1", "NRG"))
        drop!("PRC_TSL", 3, k -> k[1] == "REG1" && k[2] in ("COTEBIO", "CAPEELC"))
        add!("PRC_TSL", 3, ("REG1", "COTEBIO", "DAYNITE"), ("REG1", "CAPEELC", "DAYNITE"))
        add!("PRC_NSTTS", 3, ("REG1", "COTEBIO", "SN"), ("REG1", "COTEBIO", "ANNUAL"), ("REG1", "ELCTEGAS00", "ANNUAL"),
             ("REG1", "CSHEBIO", "ANNUAL"), ("REG1", "CAPEELC", "ANNUAL"))
        add!("PRC_MAP", 3, ("REG1", "SGS", "CSHEELC"), ("REG1", "STS", "CSHECOA"))
    else
        error("unknown ppmain_tslvl case $name")
    end
    return tm
end

"What ppmain.mod L329-460 writes, besides what the steps before it wrote, compared after ppmain.mod L460 (scratch included)."
const PPMAIN_TSLVL_OUTPUTS = unique!(vcat(PPMAIN_TOPO_OUTPUTS,
    ["COM_TSL", "PRC_TSL", "TRACKC", "COM_TS", "RCS", "RCS_COMTS", "RTC", "COM_BNDPRD", "RTCS_VARC", "COM_PEAK", "COM_PKTS",
     "PRC_TS", "RP_SGS", "PRC_MAP", "RP_STG", "PRC_YMAX", "TS_ARRAY", "RPS_S1", "RPS_S2", "PRC_SGL", "RPS_PRCTS", "RP_PGFLO",
     "RPC_STG", "TRACKPC", "RPCS_VAR", "PRC_NSTTS", "PRC_ACT", "FIL", "STARTOFF", "ENDOFF"]))
