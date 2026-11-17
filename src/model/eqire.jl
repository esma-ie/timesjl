# EQ_IRE: inter-regional exchange balance. The imports of a bilateral trade
# process into a region equal the partner regions' exports through the same
# process, converted by IRE_FLO, IRE_CCVT and IRE_TSCVT.
#
# GAMS: eqire.mod L14-52, v4.9.7, included from eqmain.mod L146; declared
# eqdeclr.mod L93 (R,ALLYEAR,P,C,IE,S), type =E=.
#
# Macro expansions: %EQ% -> EQ, %VAR% -> VAR, %SOW%/%SWT% -> '' (setglobs.gms
# L348); %RTPX% -> '' and %TX% -> T (maindrv.mod L39; the STEPPED and
# REG_FIXT variants of L40-41 are refused with the bounds, see bndmain.jl).
# Index sets: REG is the row's region, R (ALIAS(REG,R), initsys.mod L88) the
# partner; T = MILESTONYR, V = MODLYEAR; XPT = {EXP}, IMP = {IMP}
# (initsys.mod L63-64), so (1-2*XPT(IE)) is 1 for imports and -1 for exports.
#
# Translated: the bilateral case, L14-20 (own imports) and L43-50 (partner
# exports, $IMP(IE)); and market-based trade (M1.3 change 51), where a
# marketplace region (ppmain.mod L865-893: RPC_MARKET(R,P,C,'EXP')) is linked
# to itself in TOP_IRE:
# - L23-29, $RPC_MARKET(REG,P,COM,'IMP'): the imports of the other regions
#   that the marketplace's export commodity COM1 reaches, added to its own;
# - L32-38, $XPT(IE): the export-side rows of the marketplace
#   (RPC_EQIRE(R,P,C,'EXP'), ppmain.mod L905-912), its exports equal to the
#   imports of every region it is linked to, itself included, each divided
#   by the IRE_FLO of the link (a zero IRE_FLO is GAMS's division by zero).
# RPC_EQIRE, RPCS_VAR, RTPCS_VARF and TOP_IRE come from the pre-solve dump
# (ppmain.mod L866-918 and pp_qack.mod adjust them).

"""
    eq_ire!(tm::TimesModel) -> Int

Generate every EQ_IRE row from `tm.data`. Returns the number of rows.

    EQ_IRE(RTP(REG,T,P),COM,IE,S)\$(RPCS_VAR(REG,P,COM,S)\$RPC_EQIRE(REG,P,COM,IE)) ..
      SUM(RTP_VNTBYR(REG,T,P,V)\$RTPCS_VARF(REG,T,P,COM,S),
          VAR_IRE(REG,V,T,P,COM,S,IE)\$(NOT RPC_AIRE(REG,P,COM)) +
          (VAR_ACT(REG,V,T,P,S)*PRC_ACTFLO(REG,V,P,COM))\$RPC_AIRE(REG,P,COM)) * (1-2*XPT(IE))
      +
      SUM(TOP_IRE(REG,COM1,R,C,P)\$((NOT SAMEAS(REG,R))\$RPC_MARKET(REG,P,COM1,'EXP')),
        SUM((RTP_VNTBYR(R,T,P,V),RTPCS_VARF(R,T,P,C,TS),RS_TREE(R,ALL_TS,TS))\$IRE_TSCVT(R,ALL_TS,REG,S),
            (VAR_IRE(R,V,T,P,C,TS,'IMP')\$(NOT RPC_AIRE(R,P,C))+(VAR_ACT(R,V,T,P,TS)*PRC_ACTFLO(R,V,P,C))\$RPC_AIRE(R,P,C))
             * IRE_CCVT(R,C,REG,COM1) * IRE_TSCVT(R,ALL_TS,REG,S) * RS_FR(R,ALL_TS,TS)*(1+RTCS_FR(R,T,C,ALL_TS,TS))
           ) * IRE_CCVT(REG,COM1,REG,COM)
         )\$RPC_MARKET(REG,P,COM,'IMP')
      +
      SUM(TOP_IRE(REG,COM,R,C,P),
        SUM((RTP_VNTBYR(R,T,P,V),RTPCS_VARF(R,T,P,C,TS),RS_TREE(R,ALL_TS,TS))\$IRE_TSCVT(R,ALL_TS,REG,S),
            (VAR_IRE(R,V,T,P,C,TS,'IMP')\$(NOT RPC_AIRE(R,P,C))+(VAR_ACT(R,V,T,P,TS)*PRC_ACTFLO(R,V,P,C))\$RPC_AIRE(R,P,C))
             / IRE_FLO(REG,V,P,COM,R,C,TS) * IRE_TSCVT(R,ALL_TS,REG,S) * RS_FR(R,ALL_TS,TS)*(1+RTCS_FR(R,T,C,ALL_TS,TS))
           ) * IRE_CCVT(R,C,REG,COM)
         )\$XPT(IE)
      =E=
      SUM((TOP_IRE(R,C,REG,COM,P),ALL_TS)\$IRE_TSCVT(R,ALL_TS,REG,S),
        SUM((RTP_VNTBYR(R,T,P,V),RTPCS_VARF(R,T,P,C,TS))\$RS_FR(R,ALL_TS,TS),
            (VAR_IRE(R,V,T,P,C,TS,'EXP')\$(NOT RPC_AIRE(R,P,C)) +
             (VAR_ACT(R,V,T,P,TS)*PRC_ACTFLO(R,V,P,C))\$RPC_AIRE(R,P,C))
            * IRE_FLO(R,V,P,C,REG,COM,S) * IRE_TSCVT(R,ALL_TS,REG,S)
            * RS_FR(R,ALL_TS,TS)*(1+RTCS_FR(R,T,C,ALL_TS,TS))
        ) * IRE_CCVT(R,C,REG,COM))\$IMP(IE);

GAMS: eqire.mod L14-52, v4.9.7.
"""
function eq_ire!(tm::TimesModel)
    rpc_eqire = gset(tm, "RPC_EQIRE")
    isempty(rpc_eqire) && return 0
    name = "EQ_IRE"

    reg = gset(tm, "REG")
    tx = eq_periods(tm)   # %R_T%, %TX%: SUBT in a stepped run (maindrv.mod L38-40)
    rtp = gset(tm, "RTP")
    xpt = gset(tm, "XPT")
    imp = gset(tm, "IMP")
    rtpcs_varf = gset(tm, "RTPCS_VARF")
    rpc_aire = gset(tm, "RPC_AIRE")
    prc_actflo = gparam(tm, "PRC_ACTFLO")
    rs_fr = gparam(tm, "RS_FR")
    rtcs_fr = gparam(tm, "RTCS_FR")
    ire_flo = gparam(tm, "IRE_FLO")
    ire_tscvt = gparam(tm, "IRE_TSCVT")
    ire_ccvt = gparam(tm, "IRE_CCVT")

    # Precomputed incidence maps.
    s_of_rpc = indexby(gset(tm, "RPCS_VAR"), (1, 2, 3))            # (reg,p,com) -> RPCS_VAR(reg,p,com,s)
    t_of_rp = indexby(rtp, (1, 3))                                  # (reg,p) -> RTP(reg,t,p)
    vint_of_rtp = indexby(gset(tm, "RTP_VNTBYR"), (1, 2, 3))        # (r,t,p) -> RTP_VNTBYR(r,t,p,v)
    varf_of_rtpc = indexby(rtpcs_varf, (1, 2, 3, 4))                # (r,t,p,c) -> RTPCS_VARF(r,t,p,c,ts)
    top_of_regcomp = indexby(gset(tm, "TOP_IRE"), (3, 4, 5))        # (reg,com,p) -> TOP_IRE(r,c,reg,com,p)
    tscvt_of_rregs = indexby(ire_tscvt, (1, 3, 4))                  # (r,reg,s) -> IRE_TSCVT(r,all_ts,reg,s)
    top_from_regp = indexby(gset(tm, "TOP_IRE"), (1, 5))            # (reg,p) -> TOP_IRE(reg,com1,r,c,p)
    rpc_market, rs_tree = gset(tm, "RPC_MARKET"), gset(tm, "RS_TREE")
    # The imports of region r through p, at the timeslices TS of their flows, onto the timeslice S
    # of region reg (L24-27, L33-36): SUM((RTP_VNTBYR(R,T,P,V),RTPCS_VARF(R,T,P,C,TS),
    # RS_TREE(R,ALL_TS,TS))$IRE_TSCVT(R,ALL_TS,REG,S), flow * w(v,ts) * IRE_TSCVT * RS_FR * (1+RTCS_FR)).
    function imports_of!(expr, k, r, t, p, c, reg, s, w)
        for (_, all_ts, _, _) in get(tscvt_of_rregs, (r, reg, s), NTuple{4,String}[])
            tscvt = gv(ire_tscvt, (r, all_ts, reg, s))
            for (_, _, _, v) in get(vint_of_rtp, (r, t, p), NTuple{4,String}[]),
                (_, _, _, _, ts) in get(varf_of_rtpc, (r, t, p, c), NTuple{5,String}[])
                (r, all_ts, ts) in rs_tree || continue
                f = w(v, ts) * tscvt * gv(rs_fr, (r, all_ts, ts)) * (1 + gv(rtcs_fr, (r, t, c, all_ts, ts))) * k
                if !((r, p, c) in rpc_aire)
                    addterm!(expr, f, tm, "VAR_IRE", r, v, t, p, c, ts, "IMP")
                else
                    addterm!(expr, gv(prc_actflo, (r, v, p, c)) * f, tm, "VAR_ACT", r, v, t, p, ts)
                end
            end
        end
    end
    no3 = NTuple{3,String}[]
    no4 = NTuple{4,String}[]
    no5 = NTuple{5,String}[]

    # The domain, in GAMS order (REG, T, P, COM, IE, S).
    rows = NTuple{6,String}[]
    for (r, p, c, ie) in rpc_eqire
        (r,) in reg || continue
        for (_, t, _) in get(t_of_rp, (r, p), no3)
            (t,) in tx || continue
            for (_, _, _, s) in get(s_of_rpc, (r, p, c), no4)
                push!(rows, (r, t, p, c, ie, s))
            end
        end
    end
    gams_sort!(rows, tm.data)

    n = 0
    for (rg, t, p, com, ie, s) in rows
        # LHS, L18-20: own trade flow, signed by (1-2*XPT(IE)).
        sign = GNum(1.0) - 2 * GNum((ie,) in xpt ? 1.0 : 0.0)
        lhs = JuMP.AffExpr(0.0)
        if (rg, t, p, com, s) in rtpcs_varf
            for (_, _, _, v) in get(vint_of_rtp, (rg, t, p), no4)
                if !((rg, p, com) in rpc_aire)
                    addterm!(lhs, sign, tm, "VAR_IRE", rg, v, t, p, com, s, ie)
                else
                    addterm!(lhs, gv(prc_actflo, (rg, v, p, com)) * sign, tm, "VAR_ACT", rg, v, t, p, s)
                end
            end
        end

        # L23-29: the imports of the regions the marketplace's export commodities reach.
        if (rg, p, com, "IMP") in rpc_market
            for (_, com1, r, c, _) in get(top_from_regp, (rg, p), no5)
                (r != rg && (rg, p, com1, "EXP") in rpc_market) || continue
                ccvt1 = gv(ire_ccvt, (r, c, rg, com1))
                imports_of!(lhs, gv(ire_ccvt, (rg, com1, rg, com)), r, t, p, c, rg, s, (v, ts) -> ccvt1)
            end
        end
        # L32-38: the export rows of a marketplace, the imports of every region it is linked to.
        if (ie,) in xpt
            for (_, cc, r, c, _) in get(top_from_regp, (rg, p), no5)
                cc == com || continue
                function wflo(v, ts)
                    fl = gv(ire_flo, (rg, v, p, com, r, c, ts))
                    iszero(fl) && throw(DomainError((rg, v, p, com, r, c, ts),
                        "eqire.mod L35: IRE_FLO is zero, GAMS divides by zero in EQ_IRE"))
                    return GNum(1.0) / fl
                end
                imports_of!(lhs, gv(ire_ccvt, (r, c, rg, com)), r, t, p, c, rg, s, wflo)
            end
        end

        # RHS, L43-50: the partner regions' exports, imports rows only.
        rhs = JuMP.AffExpr(0.0)
        if (ie,) in imp
            for (r, c, _, _, _) in get(top_of_regcomp, (rg, com, p), no5)
                (r,) in reg || continue                                    # R: ALIAS(REG,R)
                ccvt = gv(ire_ccvt, (r, c, rg, com))
                for (_, all_ts, _, _) in get(tscvt_of_rregs, (r, rg, s), no4)
                    tscvt = gv(ire_tscvt, (r, all_ts, rg, s))
                    for (_, _, _, v) in get(vint_of_rtp, (r, t, p), no4),
                        (_, _, _, _, ts) in get(varf_of_rtpc, (r, t, p, c), no5)
                        haskey(rs_fr, (r, all_ts, ts)) || continue
                        w = gv(ire_flo, (r, v, p, c, rg, com, s)) * tscvt *
                            gv(rs_fr, (r, all_ts, ts)) * (1 + gv(rtcs_fr, (r, t, c, all_ts, ts)))
                        if !((r, p, c) in rpc_aire)
                            addterm!(rhs, w * ccvt, tm, "VAR_IRE", r, v, t, p, c, ts, "EXP")
                        else
                            addterm!(rhs, gv(prc_actflo, (r, v, p, c)) * w * ccvt, tm, "VAR_ACT", r, v, t, p, ts)
                        end
                    end
                end
            end
        end

        gconstraint!(tm, name, (rg, t, p, com, ie, s), "E", lhs, rhs) === nothing || (n += 1)
    end
    return n
end
