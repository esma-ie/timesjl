# Crafted states for ppmain.mod L1336-1350 with pp_reduce.red (v4.9.7): the
# reduction of model size. The TIMES_Demo demo12 prelv checkpoint
# (test/fixtures/demo12_off_prelv, run with %REDUCE% NO) is run with the
# other two modes of pp_reduce.red, and GAMS runs ppmain.mod L616-1350
# itself on it (scripts/make_ppmain_reduce_unit.jl;
# test/unit/test_m13_ppmain_reduce.jl).
#
# demo12, REG1: FTE-AGRBIO, FTE-COMSOL and FTE-AGRELC (DAYNITE) are the
# only processes producing AGRBIO, COMSOL and AGRELC through TOP, but the
# dummy imports (IMPNRGZ, RPC_IRE IMP) produce every commodity too, so
# pp_reduce.red L154 leaves no single producer (RTCS_SING ends empty).

using OpenTIMES: TimesModel, gvalues, gput!
import TOML

"""
The cases run by GAMS:

- "yes": %REDUCE% YES (all of pp_reduce.red), with upper/fixed activity
  bounds of EPS on FTE-AGRBIO (2010), FTE-COMSOL (2020, fixed) and
  FTE-AGRELC (2010, at ANNUAL, above its DAYNITE level): RTPS_OFF (L130),
  RTCS_SING and RXX built and emptied again (L143-155), the EPS bounds
  moved to PRC_TS (L165-168), RTP_VARA removed (L173).
- "mid": %REDUCE% unset (pp_reduce.red L1-56 only: PRC_CAP and the emission
  flows).
"""
const PPMAIN_REDUCE_CASES = ["yes", "mid"]

function ppmain_reduce_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    sw = Dict{String,String}(k => string(v) for (k, v) in fx["switches"])
    if name == "yes"
        sw["REDUCE"] = "YES"
    elseif name == "mid"
        delete!(sw, "REDUCE")
    else
        error("unknown ppmain_reduce case $name")
    end
    tm = TimesModel(joinpath(fixtures, "demo12_off_prelv"); switches=sw)
    if name == "yes"
        b = gvalues(tm, "ACT_BND", 5)
        b[("REG1", "2010", "FTE-AGRBIO", "ANNUAL", "UP")] = 0.0         # EPS
        b[("REG1", "2020", "FTE-COMSOL", "ANNUAL", "FX")] = 0.0
        b[("REG1", "2010", "FTE-AGRELC", "ANNUAL", "UP")] = 0.0
        gput!(tm, "ACT_BND", b)
    end
    return tm
end

"What ppmain.mod L1336-1350 writes, on top of ppmain.mod L616-1333, compared at L1350."
const PPMAIN_REDUCE_NEW = ["RVP", "RTP_VARA", "PRC_CAP", "PRC_ACT", "RP_AFB", "OBJ_ICUR", "RTPS_BD", "TRACKPC", "FSCK", "FS_EMIS",
                           "RPC_EMIS", "RPC_ACT", "RPC_AIRE", "NO_ACT", "RP_XRED", "CG_GRP", "RPCG_PTRAN", "RP_CGG", "RPC_FFUNC",
                           "RPCC_FFUNC", "RTPS_OFF", "RXX", "RTCS_SING", "TRACKC", "RC_IOP", "RHS_COMPRD", "ACT_BND", "RTPCS_OUT",
                           "PRC_TS2", "RPC_PKC", "RPC_PKF", "RTPCS_VARF", "RTP_VINTYR", "R_UC"]

"What ppmain.mod L1336-1350 declares itself (none)."
const PPMAIN_REDUCE_DECLARED_NEW = String[]
