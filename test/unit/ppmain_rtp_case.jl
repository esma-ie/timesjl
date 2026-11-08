# Crafted states for ppmain.mod L199-247 (v4.9.7): the TIMES_Demo demo12 init
# checkpoint (test/fixtures/demo12_off_init) given the data no core reference
# run has, so that the paths of L199-247 the core models do not reach are
# checked against ppmain.mod L1-247 run by GAMS itself
# (scripts/make_ppmain_rtp_unit.jl, test/unit/test_m13_ppmain_rtp.jl).
#
# demo12 runs with %BOTIME% 1960 (ALLYEAR 1960-2200 and '0', 242 labels, so
# Z = 2202 at L215). After L1-196 the milestones' periods are 2005: 2005-2007,
# 2010: 2008-2012, 2015: 2013-2017, 2020: 2018-2025, 2030: 2026-2040, 2050:
# 2041-2052, with M(T) = T; MIYR_V1 = 2005. Its past investments are on 2004,
# and its NCAP_START values are 2006 to 2015 (none with past investment).

using TIMES: TimesModel, gvalues, gmembers, gput!
import TOML

"""
The cases run by GAMS:

- "pasti": NCAP_PASTI(REG1,'0',CAPEELC) = 1, so L134 sets INT_DEFAULT('PASTI');
  past investment of COTEBIO in REG1 on 2009 (3) and on the milestone 2010
  (0.1: `3+0.1+1-1` rounds), of COTECOA in REG2 on 2010 only (2), of COTEELC
  in REG1 on 2015 (0.5), of COTEOIL in REG1 on 2010 as EPS (PASTSUM 0: only
  removed), of CSHEBIO in REG1 on 2005 (B = M: not moved), and of COTEGAS in
  REG1 on 2012, a past year inside the period of 2010 (L206: VNT(2012,2010)).
- "noff": user PRC_NOFF in REG1: EXPCOA1 2015-2020 and 2030-EOH (two later
  ranges, L235-238), EXPDSL1 BOH-2000 (ends before the first period: L225's
  SMAX over nothing, -INF), EXPELC1 1990-2012 (starts in the past: delayed to
  2012) and 2040-2045 (later: pp_off over both), ELCRNHYD01 2015-2020 (a REG2
  process only: not in RP, ignored); in REG2 EXPGAS1 BOH-EOH (off in every
  period).
  NCAP_START in REG1: CAPNELC1 1955 (before %BOTIME%: its user range BOH-2010
  cleared, none set), COTNBIO1 2300 (capped at %EOTIME%), COTNCOA1 2012.4 and
  COTNELC1 2012.6 (the lead -189.6 rounds to -190, -189.4 to -189), and
  COTNGAS1 2006 with past investment on 1980 (L227-231: the delay is ignored).
- "noff_offthd": "noff" with G_OFFTHD 0.5 on 2005 and 0.9 on 2030 (interpolated
  by ppmain.mod L189), so the thresholds at L224 and pp_off.mod L22 leave some
  periods on: a process starting 2006 is on in 2005 (1/3 of the period), and
  SMAX at L225 has nothing to take.
"""
const PPMAIN_RTP_CASES = ["pasti", "noff", "noff_offthd"]

function ppmain_rtp_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_init"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    ppmain_rtp_case!(tm, name)
    return tm
end

function ppmain_rtp_case!(tm, name)
    put!(n, N, kv...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, kv); gput!(tm, n, v))
    add!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> push!(s, k), ks); gput!(tm, n, s))
    if name == "pasti"
        put!("NCAP_PASTI", 3, ("REG1", "0", "CAPEELC") => 1.0, ("REG1", "2009", "COTEBIO") => 3.0, ("REG1", "2010", "COTEBIO") => 0.1,
             ("REG2", "2010", "COTECOA") => 2.0, ("REG1", "2015", "COTEELC") => 0.5, ("REG1", "2010", "COTEOIL") => 0.0,   # 0.0 is EPS
             ("REG1", "2005", "CSHEBIO") => 1.5, ("REG1", "2012", "COTEGAS") => 1.0)
    elseif name in ("noff", "noff_offthd")
        add!("PRC_NOFF", 4, ("REG1", "EXPCOA1", "2015", "2020"), ("REG1", "EXPCOA1", "2030", "EOH"), ("REG1", "EXPDSL1", "BOH", "2000"),
             ("REG1", "EXPELC1", "1990", "2012"), ("REG1", "EXPELC1", "2040", "2045"), ("REG2", "EXPGAS1", "BOH", "EOH"),
             ("REG1", "ELCRNHYD01", "2015", "2020"), ("REG1", "CAPNELC1", "BOH", "2010"))
        put!("NCAP_START", 2, ("REG1", "CAPNELC1") => 1955.0, ("REG1", "COTNBIO1") => 2300.0, ("REG1", "COTNCOA1") => 2012.4,
             ("REG1", "COTNELC1") => 2012.6)
        put!("NCAP_PASTI", 3, ("REG1", "1980", "COTNGAS1") => 1.0)
        name == "noff_offthd" && put!("G_OFFTHD", 1, ("2005",) => 0.5, ("2030",) => 0.9)
    else
        error("unknown ppmain_rtp case $name")
    end
    return tm
end

"What ppmain.mod L199-247 writes, compared after it."
const PPMAIN_RTP_OUTPUTS = ["FIL", "STARTOFF", "ENDOFF", "B", "E", "D", "M", "PASTYEAR", "PASTMILE", "NCAP_PASTI", "COEF_RTP", "VNT", "PHYR", "PASTSUM", "PRC_NOFF",
                            "UNCD1", "PRC_YMAX", "TRACKP", "RTP_OFF", "RTP", "RVP"]
