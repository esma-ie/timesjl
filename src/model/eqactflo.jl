# EQ_ACTFLO: relationship between process activity and the flows of its
# primary commodity group.
#
# GAMS: eqactflo.mod L15-29, v4.9.7, included from eqmain.mod L41; declared
# EQ_ACTFLO(R,ALLYEAR,ALLYEAR,P,S) in eqdeclr.mod L37. Macro expansions per
# setglobs.gms L348 (%EQ%->EQ, %VAR%->VAR, %SWT%/%SOW%->'') and maindrv.mod
# L39 (%R_V_T% -> 'R,V,T'; the STEPPED/REG_FIXT variants L40-41 are out of
# Phase 1 scope).
#
#   EQ_ACTFLO(RTP_VINTYR(R,V,T,P),S)$(PRC_TS(R,P,S) *
#     [REDUCE: (NOT RTPS_OFF(R,T,P,S)) *]
#                                      PRC_ACT(R,P)) ..
#     VAR_ACT(R,V,T,P,S)$RTP_VARA(R,T,P)
#   =E=
#     SUM(RPC_PG(R,P,C)$RTPCS_VARF(R,T,P,C,S),
#         (VAR_FLO(R,V,T,P,C,S)$RP_FLO(R,P) +
#          SUM(RPC_IRE(R,P,C,IE)$RP_AIRE(R,P,IE),
#              VAR_IRE(R,V,T,P,C,S,IE))$RP_IRE(R,P)
#         ) / PRC_ACTFLO(R,V,P,C));
#
# The `(NOT RTPS_OFF)` factor exists only when %REDUCE%==YES (eqactflo.mod
# L16), which `tm.reduce` reproduces. The division by PRC_ACTFLO(R,V,P,C) is
# evaluated for every commodity the outer sum reaches, so an absent or zero
# entry is an error here exactly where GAMS would raise one.

"""
    eq_actflo!(tm::TimesModel)

Generate every EQ_ACTFLO row from `tm.data`, creating the VAR_ACT, VAR_FLO
and VAR_IRE columns it references. Returns the number of rows generated.

GAMS: eqactflo.mod L15-29, v4.9.7.
"""
function eq_actflo!(tm::TimesModel)
    rtp_vintyr = gset(tm, "RTP_VINTYR")
    prc_ts = gset(tm, "PRC_TS")
    prc_act = gset(tm, "PRC_ACT")
    rtps_off = gset(tm, "RTPS_OFF")
    rtp_vara = gset(tm, "RTP_VARA")
    rpc_pg = gset(tm, "RPC_PG")
    rtpcs_varf = gset(tm, "RTPCS_VARF")
    rp_flo = gset(tm, "RP_FLO")
    rp_ire = gset(tm, "RP_IRE")
    rpc_ire = gset(tm, "RPC_IRE")
    rp_aire = gset(tm, "RP_AIRE")
    prc_actflo = gparam(tm, "PRC_ACTFLO")

    # Precomputed incidence maps; never filters inside the row loop.
    ts_of_rp = indexby(prc_ts, (1, 2))       # (r,p) -> PRC_TS members
    pg_of_rp = indexby(rpc_pg, (1, 2))       # (r,p) -> RPC_PG members
    ire_of_rpc = indexby(rpc_ire, (1, 2, 3)) # (r,p,c) -> RPC_IRE members

    vx, tx = gset(tm, "MODLYEAR"), eq_periods(tm)                 # %R_V_T%: V, and SUBT in a stepped run (maindrv.mod L38-40)
    n = 0
    for (r, v, t, p) in rtp_vintyr
        ((v,) in vx && (t,) in tx) || continue
        (r, p) in prc_act || continue
        for (_, _, s) in get(ts_of_rp, (r, p), NTuple{3,String}[])
            tm.reduce && (r, t, p, s) in rtps_off && continue

            lhs = JuMP.AffExpr(0.0)
            if (r, t, p) in rtp_vara
                JuMP.add_to_expression!(lhs, 1.0, getvar!(tm, "VAR_ACT", r, v, t, p, s))
            end

            rhs = JuMP.AffExpr(0.0)
            for (_, _, c) in get(pg_of_rp, (r, p), NTuple{3,String}[])
                (r, t, p, c, s) in rtpcs_varf || continue
                coef = 1.0 / nonzero(prc_actflo, (r, v, p, c))
                if (r, p) in rp_flo
                    JuMP.add_to_expression!(rhs, coef, getvar!(tm, "VAR_FLO", r, v, t, p, c, s))
                end
                if (r, p) in rp_ire
                    for (_, _, _, ie) in get(ire_of_rpc, (r, p, c), NTuple{4,String}[])
                        (r, p, ie) in rp_aire || continue
                        JuMP.add_to_expression!(rhs, coef, getvar!(tm, "VAR_IRE", r, v, t, p, c, s, ie))
                    end
                end
            end

            gconstraint!(tm, "EQ_ACTFLO", (r, v, t, p, s), "E", lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end
