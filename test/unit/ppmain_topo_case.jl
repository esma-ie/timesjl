# Crafted states for preppm.mod L218-252 (preshape.gms) and ppmain.mod
# L249-328 (v4.9.7): the TIMES_Demo demo12 init checkpoint
# (test/fixtures/demo12_off_init) given the data no core reference run has,
# so that the paths the core models do not reach are checked against GAMS
# running ppmain.mod L1-247, preppm.mod L1-212, prep_ext.vda, preppm.mod
# L218-252 and ppmain.mod L249-328 itself (scripts/make_ppmain_topo_unit.jl,
# test/unit/test_m13_ppmain_topo.jl).
#
# demo12 (see preppm_case.jl): milestones 2005, 2010, 2015, 2020, 2030, 2050
# (periods 2005-2007, 2008-2012, 2013-2017, 2018-2025, 2026-2040, 2041-2052);
# MODLYEAR adds 1960, 1980 and 2004; DATAYEAR holds every year from 2005 to
# 2050. The REG1 processes used have RTP from 2004 on, CSHECOA from 2005,
# CSHNOIL1 and ELCTNGAS01 from 2010; ELCTNGAS01 is the only vintaged one, and
# prep_ext.vda L44 deletes FLO_FUNCX of the others.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!
import TOML

"""
The cases run by GAMS:

- "shapes": every preshape.gms call (preppm.mod L222-233) and its options:
  the default (10) moving data years inside a period to the milestone, the
  earlier year of two winning, a milestone with its own data left alone;
  option 1 (a step between the data years), 3, 4, 5, 2 without data (EPS
  everywhere) and with data, 11 and 15 (one period back and forward first),
  1012 (12), -1 (MOD keeps the sign); a value that rounds to 0 and an EPS
  data year (both restart the step); a process outside RTP in 2005
  (CSHNOIL1); NCAP_AFSX and FLO_FUNCX through UNCD7, COM_ELASTX with its
  default 15 over the milestones; FLO_MARK into PRC_MARK (L237).
- "topology": a commodity group named like a commodity of the topology
  (L272-277: the commodity leaves RC and RPC), a trade process whose primary
  group holds a commodity it does not trade (L301), a user PRC_SPG (L309), a
  material process with a demand PG (L317-318, AGRBIO retyped MAT),
  NCAP_ICOM, NCAP_OCOM (one pair cancelling) and NCAP_COM with a commodity
  outside RC (L291-294: RPC_NOFLO).
"""
const PPMAIN_TOPO_CASES = ["shapes", "topology"]

function ppmain_topo_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_init"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    ppmain_topo_case!(tm, name)
    return tm
end

const PT_EPS = 0.0                                                # a stored 0.0 is EPS

function ppmain_topo_case!(tm, name)
    put!(n, N, kv...) = (v = gvalues(tm, n, N); foreach(((k, x),) -> v[k] = x, kv); gput!(tm, n, v))
    add!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> push!(s, k), ks); gput!(tm, n, s))
    drop!(n, N, ks...) = (s = gmembers(tm, n, N); foreach(k -> delete!(s, k), ks); gput!(tm, n, s))
    if name == "shapes"
        x(p, kv...) = [("REG1", y, p) => v for (y, v) in kv]
        put!("NCAP_AFX", 3,
             x("COTEBIO", "2008" => 2.0, "2012" => 3.0, "2027" => 4.0, "2014" => 5.0, "2015" => 6.0)...,  # default: moved to 2010, 2030
             x("COTECOA", "0" => 1.0, "2005" => 1.0, "2020" => 3.0, "2050" => 2.0)...,      # 1: a step, no extrapolation
             x("COTEGAS", "0" => 3.0, "2010" => 2.0, "2030" => 5.4)...,                    # 3: both ways
             x("ELCTECOA00", "0" => 4.0, "2015" => 2.0)...,                                # 4: not forward
             x("ELCTEGAS00", "0" => 5.0, "2015" => 3.3)...,                                # 5: not backward
             x("ELCTEOIL00", "0" => 2.0)...,                                               # 2 without data: EPS
             x("CSHEBIO", "0" => 2.0, "2020" => 2.0)...,                                   # 2 with data: both ways
             x("CAPEELC", "0" => 15.0, "2016" => 2.0, "2027" => 4.0)...,                   # 15: one period each way, then 5
             x("CSHEELC", "0" => 11.0, "2016" => 1.6)...,                                  # 11: one period each way, then 1
             x("COTEELC", "0" => -1.0, "2005" => 1.0, "2020" => 2.0)...,                   # -1: MOD(-1,1000) = -1
             x("COTEOIL", "0" => 1012.0, "2016" => 3.0)...,                                # 1012: 12
             x("CSHEGAS", "0" => 1.0, "2005" => 0.4, "2015" => 2.6, "2030" => PT_EPS, "2050" => 5.0)...,  # rounding to 0, EPS
             x("CSHNOIL1", "0" => 3.0, "2015" => 2.0)...)                                  # no RTP in 2005
        put!("NCAP_AFM", 3, x("CSHEOIL", "2012" => 2.0)...)
        put!("NCAP_FOMX", 3, x("CSHECOA", "2006" => 3.0, "2026" => 4.0)...)
        put!("NCAP_FSUBX", 3, x("CSHEOIL", "0" => 3.0, "2015" => 2.0)...)
        put!("NCAP_FTAXX", 3, x("CSHEOIL", "2018" => 2.0)...)
        put!("NCAP_FOMM", 3, x("COTEBIO", "0" => 1.0, "2005" => 1.0, "2030" => 2.0)...)
        put!("NCAP_FSUBM", 3, x("COTEGAS", "2013" => 2.0)...)
        put!("NCAP_FTAXM", 3, x("COTECOA", "0" => 3.0, "2020" => 1.0)...)
        put!("NCAP_CPX", 3, x("CAPEELC", "2009" => 2.0)..., x("CSHEBIO", "0" => 5.0, "2015" => 3.0)...)
        put!("NCAP_AFSX", 4, ("REG1", "0", "COTEBIO", "UP") => 3.0, ("REG1", "2010", "COTEBIO", "UP") => 1.5,
             ("REG1", "2012", "COTEBIO", "LO") => 1.0)
        put!("FLO_FUNCX", 5, ("REG1", "0", "ELCTNGAS01", "ELCGAS", "ELCCO2") => 3.0, ("REG1", "2015", "ELCTNGAS01", "ELCGAS", "ELCCO2") => 2.0,
             ("REG1", "2022", "ELCTNGAS01", "ACT", "ELCCO2") => 2.0)
        put!("COM_ELASTX", 4, ("REG1", "2016", "DCOT", "UP") => 2.0, ("REG1", "0", "DCAP", "LO") => 4.0, ("REG1", "2020", "DCAP", "LO") => 3.0)
        put!("FLO_MARK", 5, ("REG1", "2010", "ELCTEGAS00", "ELC", "UP") => 0.5, ("REG1", "2030", "ELCTEGAS00", "ELC", "UP") => PT_EPS)
    elseif name == "topology"
        # L272-277: AGRELC named as a group of REG1 (a commodity of RC): it leaves RC and RPC
        add!("COM_GMAP", 3, ("REG1", "AGRELC", "AGRBIO"))
        # L301: IMPELC1's primary group NRG holds COMBIO, an input it does not trade
        drop!("PRC_ACTUNT", 4, ("REG1", "IMPELC1", "ELC", "PJ"))
        add!("PRC_ACTUNT", 4, ("REG1", "IMPELC1", "NRG", "PJ"))
        add!("TOP", 4, ("REG1", "IMPELC1", "COMBIO", "IN"))
        # L309: a user shadow group, not the one L310-323 would guess (NRG)
        add!("PRC_SPG", 3, ("REG1", "ELCTECOA00", "ELCCOA"))
        # L317-318: COTEBIO a material process (PRV) with a MAT input and a demand PG
        drop!("COM_TMAP", 3, ("REG1", "NRG", "AGRBIO"))
        add!("COM_TMAP", 3, ("REG1", "MAT", "AGRBIO"))
        add!("TOP", 4, ("REG1", "COTEBIO", "AGRBIO", "IN"))
        add!("PRC_MAP", 3, ("REG1", "PRV", "COTEBIO"))
        # L291-294: capacity-related flows; CSHEBIO's ICOM and OCOM cancel; ACT is not in RC (demo12 has it as a commodity)
        put!("NCAP_ICOM", 4, ("REG1", "2010", "COTEGAS", "COMGAS") => 0.1, ("REG1", "2015", "CSHEBIO", "COMBIO") => 1.0)
        put!("NCAP_OCOM", 4, ("REG1", "2010", "COTECOA", "COMCO2") => 2.0, ("REG1", "2015", "CSHEBIO", "COMBIO") => -1.0)
        put!("NCAP_COM", 5, ("REG1", "2010", "CAPEELC", "ACT", "IN") => 0.5)
    else
        error("unknown ppmain_topo case $name")
    end
    return tm
end

"What preppm.mod L218-252 and ppmain.mod L249-328 write, besides what prep_ext.vda wrote, compared after ppmain.mod L328 (scratch included)."
const PPMAIN_TOPO_OUTPUTS = unique!(vcat(PREP_EXT_OUTPUTS,
    ["NCAP_AFX", "NCAP_AFSX", "NCAP_AFM", "NCAP_FOMX", "NCAP_FSUBX", "NCAP_FTAXX", "COM_ELASTX", "NCAP_FOMM", "NCAP_FSUBM",
     "NCAP_FTAXM", "NCAP_CPX", "PRC_MARK", "RXX", "UNCD7", "SUBT", "RT_PP", "DUR_MAX", "EOHYEARS", "EACHYEAR", "PERIODYR", "MI_DMAS",
     "DEM", "FIN", "RC", "RPC", "COM_GMAP", "NRG_GMAP", "PRC_CG", "RPC_CAPFLO", "RPC_NOFLO", "RPC_PG", "RP_PGTYPE", "RP_AIRE",
     "RP_INOUT", "TRACKP", "PRC_SPG", "RPC_SPG", "Z", "F"]))
