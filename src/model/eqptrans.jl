# EQ_PTRANS: flow-to-flow transformation between two commodity groups of a
# process (e.g. efficiency between input and output groups).
#
# GAMS: eqptrans.mod L14-39, v4.9.7, included from eqmain.mod L164; declared
# in eqdeclr.mod. Macro expansions:
# - %EQ% -> EQ, %VAR% -> VAR, %SWT%/%SOW% -> '' (setglobs.gms L348);
#   %R_V_T% -> 'R,V,T' (maindrv.mod L39).
# - RTS(S): OBMAC is YES on any GAMS >= 23.0 (initmty.mod L21), so RTS is the
#   macro of timslice.mod L39, which expands to %RTS% = S (L31). It becomes
#   S+NORTS(R,T,S) only with dynamic timeslices (L32-33); NORTS data raises
#   UnportedError.
# - %SHP1% (L14-16): `*(1+RTP_FFCX(R,V,T,P,COM_GRP,CG)$PRC_VINT(R,P))`, then
#   `*(1+RTP_FFCS(R,V,P,COM_GRP,CG))` only when RTP_FFCS is DEFINED
#   (%SHFF% -> 1+RTP_FFC, setglobs.gms L353).
# - %cal_red% (L27, L37) with arguments C COM TS P T: cal_nored!, see
#   cal_red.jl.
# Coefficients are GNum; terms are emitted with addterm! (GAMS rules for
# zero and EPS, docs/discrepancies.md G5-G6).

"""
    eq_ptrans!(tm::TimesModel) -> Int

Generate every EQ_PTRANS row from `tm.data`, creating the VAR_FLO columns
it references. Returns the number of rows generated.

    EQ_PTRANS(RTP_VINTYR(R,V,T,P),COM_GRP,CG,S)\$((RPS_S1(R,P,S) * RP_STD(R,P) *
        SUM((RPC(R,P,C),RS_TREE(R,S,TS))\$COEF_PTRAN(R,V,P,COM_GRP,C,CG,TS),1))\$RPCC_FFUNC(R,P,COM_GRP,CG)) ..
      SUM((COM_GMAP(R,CG,C),RS_TREE(R,S,TS))\$RTPCS_VARF(R,T,P,C,TS),
          RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS)) * [cal_red C COM TS P T])
      =E=
      SUM((RTPCS_VARF(R,T,P,C,TS),RS_TREE(R,S,TS))\$COEF_PTRAN(R,V,P,COM_GRP,C,CG,TS),
          COEF_PTRAN(R,V,P,COM_GRP,C,CG,TS) * RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS)) * [cal_red C COM TS P T])
      %SHP1% * (1+(ACT_FLO(R,V,P,CG,S)-1\$ACT_FLO(R,V,P,CG,S))\$PRC_CG(R,P,COM_GRP));

GAMS: eqptrans.mod L14-39, v4.9.7.
"""
function eq_ptrans!(tm::TimesModel)
    off = rts_off(tm)                    # RTS(S): S+NORTS(R,T,S) with dynamic timeslices (M1.3 change 63)

    rtp_vintyr = gset(tm, "RTP_VINTYR")
    modlyear = gset(tm, "MODLYEAR")
    tx = eq_periods(tm)   # %R_T%, %TX%: SUBT in a stepped run (maindrv.mod L38-40)
    rps_s1 = gset(tm, "RPS_S1")
    rp_std = gset(tm, "RP_STD")
    rpc = gset(tm, "RPC")
    rs_tree = gset(tm, "RS_TREE")
    rpcc_ffunc = gset(tm, "RPCC_FFUNC")
    com_gmap = gset(tm, "COM_GMAP")
    rtpcs_varf = gset(tm, "RTPCS_VARF")
    prc_vint = gset(tm, "PRC_VINT")
    prc_cg = gset(tm, "PRC_CG")
    coef_ptran = gparam(tm, "COEF_PTRAN")
    rs_fr = gparam(tm, "RS_FR")
    rtcs_fr = gparam(tm, "RTCS_FR")
    rtp_ffcx = gparam(tm, "RTP_FFCX")
    rtp_ffcs = gparam_opt(tm.data, "RTP_FFCS", 5)
    act_flo = gparam(tm, "ACT_FLO")

    # Precomputed incidence maps.
    ffunc_of_rp = indexby(rpcc_ffunc, (1, 2))           # (r,p) -> (r,p,cg1,cg2)
    s1_of_rp = indexby(rps_s1, (1, 2))                  # (r,p) -> (r,p,s)
    tree_of_rs = indexby(rs_tree, (1, 2))               # (r,s) -> (r,s,ts)
    gmap_of_rcg = indexby(com_gmap, (1, 2))             # (r,cg) -> (r,cg,c)
    varf_of_rtp = indexby(rtpcs_varf, (1, 2, 3))        # (r,t,p) -> (r,t,p,c,ts)
    ptran_of = indexby(coef_ptran, (1, 2, 3, 4, 6))     # (r,v,p,cg1,cg2) -> keys

    n = 0
    for (r, v, t, p) in rtp_vintyr
        ((v,) in modlyear && (t,) in tx) || continue
        (r, p) in rp_std || continue
        for (_, _, cg1, cg2) in get(ffunc_of_rp, (r, p), NTuple{4,String}[])
            ptran = get(ptran_of, (r, v, p, cg1, cg2), NTuple{7,String}[])
            isempty(ptran) && continue
            for (_, _, s) in get(s1_of_rp, (r, p), NTuple{3,String}[])
                off(r, t, s) && continue
                # SUM((RPC(R,P,C),RS_TREE(R,S,TS))$COEF_PTRAN(R,V,P,COM_GRP,C,CG,TS),1) > 0
                any(k -> (r, p, k[5]) in rpc && (r, s, k[7]) in rs_tree, ptran) || continue

                # LHS: dependent commodities of group CG.
                lhs = JuMP.AffExpr(0.0)
                for (_, _, c) in get(gmap_of_rcg, (r, cg2), NTuple{3,String}[])
                    for (_, _, ts) in get(tree_of_rs, (r, s), NTuple{3,String}[])
                        (r, t, p, c, ts) in rtpcs_varf || continue
                        k = gv(rs_fr, (r, s, ts)) * (1 + gv(rtcs_fr, (r, t, c, s, ts)))
                        cal_nored!(lhs, tm, k, r, v, t, p, c, ts)
                    end
                end

                # RHS: control commodities, times %SHP1% and the ACT_FLO factor.
                shp1 = (1 + gif(gv(rtp_ffcx, (r, v, t, p, cg1, cg2)), (r, p) in prc_vint)) *
                       (1 + gv(rtp_ffcs, (r, v, p, cg1, cg2)))
                af = gv(act_flo, (r, v, p, cg2, s))
                actf = 1 + gif(af - gif(1, haskey(act_flo, (r, v, p, cg2, s))), (r, p, cg1) in prc_cg)
                outer = shp1 * actf
                rhs = JuMP.AffExpr(0.0)
                for (_, _, _, c, ts) in get(varf_of_rtp, (r, t, p), NTuple{5,String}[])
                    (r, s, ts) in rs_tree || continue
                    haskey(coef_ptran, (r, v, p, cg1, c, cg2, ts)) || continue
                    k = gv(coef_ptran, (r, v, p, cg1, c, cg2, ts)) * gv(rs_fr, (r, s, ts)) *
                        (1 + gv(rtcs_fr, (r, t, c, s, ts)))
                    cal_nored!(rhs, tm, k * outer, r, v, t, p, c, ts)
                end

                gconstraint!(tm, "EQ_PTRANS", (r, v, t, p, cg1, cg2, s), "E", lhs, rhs) === nothing || (n += 1)
            end
        end
    end
    return n
end
