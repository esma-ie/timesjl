# EQG_IREBND / EQE_IREBND / EQL_IREBND: the bound on the exchange of a
# commodity between a region and one partner region (IRE_BND): the imports of
# C into R from ALL_REG, or the exports of C from R to ALL_REG, in the
# timeslice S, summed over the exchange processes.
#
# GAMS: eqirebnd.mod L18-69, v4.9.7, included from eqmain.mod L152-154 as
#   $BATINCLUDE eqirebnd.%1 G LO "(IRE_BND(R,T,C,S,ALL_REG,IE,'LO') NE 0)"
#   $BATINCLUDE eqirebnd.%1 E FX YES
#   $BATINCLUDE eqirebnd.%1 L UP "(IRE_BND(R,T,C,S,ALL_REG,IE,'UP') NE INF)"
# (%1 = equation type, %2 = bound type, %3 = the qualifier that the bound
# exists); declared eqdeclr.mod L96-98; in the model, mod_equa.mod L106-108.
#
# Macro expansions: %EQ% -> EQ, %VAR% -> VAR, %SOW%/%SWT% -> '' (setglobs.gms
# L348); %TX% -> T (maindrv.mod L39; SUBT(T) in a stepped run, refused).
# T = MILESTONYR; R is an alias of REG, so R is an internal region.
#
# The data statements are translated elsewhere: preppm.mod L193 (`preppm.jl`)
# and ppmain.mod L995 (pp_lvlbd.mod, `ppmain_bnd.jl`).
#
# The body:
# - imports ($IMP(IE)):
#   - L23-32, from an internal region ALL_REG through a process with an
#     exchange equation (RPC_EQIRE(R,P,C,'IMP')): the exports of the partner
#     region, with the coefficients of EQ_IRE (IRE_FLO, IRE_CCVT, IRE_TSCVT,
#     RS_FR, RTCS_FR), for each timeslice SL of the import flow on the line of
#     S (RS_TREE);
#   - L35-41, otherwise (from an external region): the import flows of R.
# - exports ($XPT(IE)):
#   - L46-51, from a marketplace region (RPC_MARKET(R,P,C,'EXP')): the imports
#     of the partner region. Refused: RPC_MARKET data raises in `ire_unported`
#     (eqire.mod L23-38), so this branch cannot be reached;
#   - L56-62, otherwise: the export flows of R.
# - L30, L39, L60: a flow at a timeslice at or below S counts in full
#   (TS_MAP(R,S,TS)); a flow at a timeslice above S counts with the share
#   G_YRFR(R,S) / G_YRFR(R,TS) (RS_BELOW(R,TS,S)).
# - Under REDUCE the flow of a process whose activity is the exchange
#   (RPC_AIRE) is VAR_ACT * PRC_ACTFLO.

const IREBND_VARIANTS = (("G", "LO"), ("E", "FX"), ("L", "UP"))             # eqmain.mod L152-154

"""
    eq_irebnd!(tm::TimesModel) -> Int

Generate every EQ(l)_IREBND row, in the order of eqmain.mod L152-154 (G with
LO, E with FX, L with UP). Returns the number of rows.

    EQ%1_IREBND(R,T,C,S,ALL_REG,IE)\$((RCS_COMTS(R,C,S) * SUM(RPC_IRE(R,P,C,IE),1) AND %3
                                  )\$IRE_BND(R,T,C,S,ALL_REG,IE,'%2')) ..
      (
       SUM(TOP_IRE(REG(ALL_REG),COM,R,C,P)\$RPC_EQIRE(R,P,C,'IMP'),
         SUM(SL\$(RTPCS_VARF(R,T,P,C,SL)*RS_TREE(R,S,SL)),
           SUM((RTP_VNTBYR(REG,T,P,V),RTPCS_VARF(REG,T,P,COM,TS),RS_TREE(REG,ALL_TS,TS))\$IRE_TSCVT(REG,ALL_TS,R,SL),
             (VAR_IRE(REG,V,T,P,COM,TS,'EXP')\$(NOT RPC_AIRE(REG,P,COM))+(VAR_ACT(REG,V,T,P,TS)*PRC_ACTFLO(REG,V,P,COM))\$RPC_AIRE(REG,P,COM))
                  * IRE_FLO(REG,V,P,COM,R,C,SL) * IRE_CCVT(REG,COM,R,C) * IRE_TSCVT(REG,ALL_TS,R,SL)
                  * RS_FR(REG,ALL_TS,TS)*(1+RTCS_FR(REG,T,COM,ALL_TS,TS))
              ) * (1\$TS_MAP(R,S,SL) + (G_YRFR(R,S)/G_YRFR(R,SL))\$RS_BELOW(R,SL,S))
            )
          )
       +
       SUM(RPC_IRE(R,P,C,IE)\$((NOT RPC_EQIRE(R,P,C,'IMP'))*SUM(TOP_IRE(ALL_REG,COM,R,C,P),1)),
         SUM((RTP_VNTBYR(R,T,P,V),RTPCS_VARF(R,T,P,C,TS))\$RS_TREE(R,S,TS),
           (VAR_IRE(R,V,T,P,C,TS,IE)\$(NOT RPC_AIRE(R,P,C))+(VAR_ACT(R,V,T,P,TS)*PRC_ACTFLO(R,V,P,C))\$RPC_AIRE(R,P,C))
                  * (1\$TS_MAP(R,S,TS) + (G_YRFR(R,S)/G_YRFR(R,TS))\$RS_BELOW(R,TS,S))
            )
          )
      )\$IMP(IE)
      +
      (
       [L46-51: RPC_MARKET(R,P,C,'EXP'), refused]
      +
       SUM(RPC_IRE(R,P,C,IE)\$((NOT RPC_MARKET(R,P,C,'EXP'))*SUM(TOP_IRE(R,C,ALL_REG,COM,P),1)),
         SUM((RTP_VNTBYR(R,T,P,V),RTPCS_VARF(R,T,P,C,TS))\$RS_TREE(R,S,TS),
           (VAR_IRE(R,V,T,P,C,TS,IE)\$(NOT RPC_AIRE(R,P,C))+(VAR_ACT(R,V,T,P,TS)*PRC_ACTFLO(R,V,P,C))\$RPC_AIRE(R,P,C))
                  * (1\$TS_MAP(R,S,TS) + (G_YRFR(R,S)/G_YRFR(R,TS))\$RS_BELOW(R,TS,S))
            )
          )
      )\$XPT(IE)
      =%1=
      IRE_BND(R,T,C,S,ALL_REG,IE,'%2');

GAMS: eqirebnd.mod L18-69 with eqmain.mod L152-154, v4.9.7 (L46-51 refused).
"""
function eq_irebnd!(tm::TimesModel)
    ire_bnd = gparam(tm, "IRE_BND")
    isempty(ire_bnd) && return 0
    ire_unported(tm)                                                # RPC_MARKET: L46-51 cannot be reached
    reg, milestonyr, rcs_comts = gset(tm, "REG"), gset(tm, "MILESTONYR"), gset(tm, "RCS_COMTS")
    imp, xpt = gset(tm, "IMP"), gset(tm, "XPT")
    rpc_eqire, rpc_aire = gset(tm, "RPC_EQIRE"), gset(tm, "RPC_AIRE")
    rs_tree, ts_map, rs_below = gset(tm, "RS_TREE"), gset(tm, "TS_MAP"), gset(tm, "RS_BELOW")
    prc_actflo, g_yrfr = gparam(tm, "PRC_ACTFLO"), gparam(tm, "G_YRFR")
    rs_fr, rtcs_fr = gparam(tm, "RS_FR"), gparam(tm, "RTCS_FR")
    ire_flo, ire_tscvt, ire_ccvt = gparam(tm, "IRE_FLO"), gparam(tm, "IRE_TSCVT"), gparam(tm, "IRE_CCVT")
    ire_of_rc = indexby(gset(tm, "RPC_IRE"), (1, 3, 4))             # (r,c,ie)   -> RPC_IRE(r,p,c,ie)
    vint_of_rtp = indexby(gset(tm, "RTP_VNTBYR"), (1, 2, 3))        # (r,t,p)    -> RTP_VNTBYR(r,t,p,v)
    varf_of_rtpc = indexby(gset(tm, "RTPCS_VARF"), (1, 2, 3, 4))    # (r,t,p,c)  -> RTPCS_VARF(r,t,p,c,ts)
    top_into = indexby(gset(tm, "TOP_IRE"), (1, 3, 4))              # (reg,r,c)  -> TOP_IRE(reg,com,r,c,p)
    top_from = indexby(gset(tm, "TOP_IRE"), (1, 2, 3))              # (r,c,reg)  -> TOP_IRE(r,c,reg,com,p)
    tscvt_of = indexby(ire_tscvt, (1, 3, 4))                        # (reg,r,sl) -> IRE_TSCVT(reg,all_ts,r,sl)
    no4, no5 = NTuple{4,String}[], NTuple{5,String}[]
    # the flow of an exchange process: the variable, or the activity times PRC_ACTFLO (RPC_AIRE)
    function flow!(expr, w, r, v, t, p, c, ts, ie)
        if (r, p, c) in rpc_aire
            addterm!(expr, gv(prc_actflo, (r, v, p, c)) * w, tm, "VAR_ACT", r, v, t, p, ts)
        else
            addterm!(expr, w, tm, "VAR_IRE", r, v, t, p, c, ts, ie)
        end
    end
    # L30, L39, L60: 1$TS_MAP(R,S,TS) + (G_YRFR(R,S)/G_YRFR(R,TS))$RS_BELOW(R,TS,S)
    function level(r, s, ts)
        w = GNum((r, s, ts) in ts_map ? 1.0 : 0.0)
        (r, ts, s) in rs_below && (w += gv(g_yrfr, (r, s)) / gv(g_yrfr, (r, ts)))
        return w
    end

    n = 0
    for (eqtype, bd) in IREBND_VARIANTS
        name = "EQ$(eqtype)_IREBND"
        rows = NTuple{6,String}[]
        for (r, t, c, s, all_reg, ie, b) in ire_bnd.keys                            # L18-19
            b == bd || continue
            ((r,) in reg && (t,) in milestonyr && (r, c, s) in rcs_comts && haskey(ire_of_rc, (r, c, ie))) || continue
            val = ire_bnd.values[(r, t, c, s, all_reg, ie, b)]
            (bd == "FX" || (bd == "LO" && val != 0) || (bd == "UP" && val != Inf)) || continue      # %3
            push!(rows, (r, t, c, s, all_reg, ie))
        end
        gams_sort!(rows, tm.data)
        for (r, t, c, s, all_reg, ie) in rows
            lhs = JuMP.AffExpr(0.0)
            if (ie,) in imp
                if (all_reg,) in reg                                                # L23-32
                    for (_, com, _, _, p) in get(top_into, (all_reg, r, c), no5)
                        (r, p, c, "IMP") in rpc_eqire || continue
                        ccvt = gv(ire_ccvt, (all_reg, com, r, c))
                        for (_, _, _, _, sl) in get(varf_of_rtpc, (r, t, p, c), no5)  # L24
                            (r, s, sl) in rs_tree || continue
                            lvl = level(r, s, sl)                                   # L30
                            for (_, all_ts, _, _) in get(tscvt_of, (all_reg, r, sl), no4)
                                tscvt = gv(ire_tscvt, (all_reg, all_ts, r, sl))
                                for (_, _, _, v) in get(vint_of_rtp, (all_reg, t, p), no4),
                                    (_, _, _, _, ts) in get(varf_of_rtpc, (all_reg, t, p, com), no5)
                                    (all_reg, all_ts, ts) in rs_tree || continue    # L25
                                    w = gv(ire_flo, (all_reg, v, p, com, r, c, sl)) * ccvt * tscvt *
                                        gv(rs_fr, (all_reg, all_ts, ts)) * (1 + gv(rtcs_fr, (all_reg, t, com, all_ts, ts)))
                                    flow!(lhs, w * lvl, all_reg, v, t, p, com, ts, "EXP")   # L26-28
                                end
                            end
                        end
                    end
                end
                for (_, p, _, _) in get(ire_of_rc, (r, c, ie), no4)                 # L35-41
                    (r, p, c, "IMP") in rpc_eqire && continue
                    any(k -> k[5] == p, get(top_into, (all_reg, r, c), no5)) || continue
                    for (_, _, _, v) in get(vint_of_rtp, (r, t, p), no4), (_, _, _, _, ts) in get(varf_of_rtpc, (r, t, p, c), no5)
                        (r, s, ts) in rs_tree || continue
                        flow!(lhs, level(r, s, ts), r, v, t, p, c, ts, ie)
                    end
                end
            end
            if (ie,) in xpt                                                         # L56-62 (L46-51 refused)
                for (_, p, _, _) in get(ire_of_rc, (r, c, ie), no4)
                    any(k -> k[5] == p, get(top_from, (r, c, all_reg), no5)) || continue
                    for (_, _, _, v) in get(vint_of_rtp, (r, t, p), no4), (_, _, _, _, ts) in get(varf_of_rtpc, (r, t, p, c), no5)
                        (r, s, ts) in rs_tree || continue
                        flow!(lhs, level(r, s, ts), r, v, t, p, c, ts, ie)
                    end
                end
            end
            rhs = addconst!(JuMP.AffExpr(0.0), gv(ire_bnd, (r, t, c, s, all_reg, ie, bd)))   # L68
            gconstraint!(tm, name, (r, t, c, s, all_reg, ie), eqtype, lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end
