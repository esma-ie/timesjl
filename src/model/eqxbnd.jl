# EQG_XBND / EQE_XBND / EQL_XBND: the bound on the total exchange of a
# commodity of a region (IRE_XBND): all imports of C into ALL_REG, or all
# exports of C from ALL_REG, in the timeslice S, whatever the partner.
# ALL_REG is an internal or an external region.
#
# GAMS: eqxbnd.mod L17-56, v4.9.7, included from eqmain.mod L241-243 as
#   $BATINCLUDE eqxbnd.%1 G LO "(IRE_XBND(ALL_REG,T,C,S,IE,'LO') NE 0)"
#   $BATINCLUDE eqxbnd.%1 E FX YES
#   $BATINCLUDE eqxbnd.%1 L UP "(IRE_XBND(ALL_REG,T,C,S,IE,'UP') NE INF)"
# (%1 = equation type, %2 = bound type, %3 = the qualifier that the bound
# exists); declared eqdeclr.mod L101-103; in the model, mod_equa.mod L111-113.
#
# Macro expansions: %EQ% -> EQ, %VAR% -> VAR, %SOW%/%SWT% -> '' (setglobs.gms
# L348); %TX% -> T (maindrv.mod L39; SUBT(T) in a stepped run, refused).
# T = MILESTONYR; R is an alias of REG (initsys.mod L88), so R is an internal
# region; C is an alias of COM (L99); IE is an alias of the set IMPEXP
# / IMP, EXP / (L62, L66).
#
# The data statement is translated elsewhere: preppm.mod L194 (`preppm.jl`).
# Unlike IRE_BND, the bound is not added up to the commodity's level (no
# pp_lvlbd.mod) and the equation has no condition on the commodity's
# timeslices (no RCS_COMTS).
#
# The body:
# - L23-32, an internal region: the flows of every exchange process of the
#   region with the commodity in the direction IE (RPC_IRE), at the timeslices
#   on the line of S (RS_TREE), times RS_FR(REG,S,TS): 1 for a flow at or
#   below S, G_YRFR(S)/G_YRFR(TS) for a flow above S (ppmain.mod L739).
# - L39-51, an external region: the flows of the internal regions R in the
#   other direction, `IMPEXP(IE--1)` (the circular lag on the two-element set:
#   IMP for a bound on EXP and the reverse), through the processes linked to
#   the external region: TOP_IRE(ALL_REG,C,R,COM,P) for a bound on its exports,
#   TOP_IRE(R,COM,ALL_REG,C,P) for a bound on its imports. The timeslice S of
#   the external region is reached through IRE_TSCVT(R,ALL_TS,ALL_REG,S); the
#   flow at TS on the line of ALL_TS counts with IRE_TSCVT * RS_FR(R,ALL_TS,TS).
#   By default IRE_TSCVT of an external region has ANNUAL to ANNUAL only
#   (ppmain.mod L967-978).
# - Under REDUCE the flow of a process whose activity is the exchange
#   (RPC_AIRE) is VAR_ACT * PRC_ACTFLO.

const XBND_VARIANTS = (("G", "LO"), ("E", "FX"), ("L", "UP"))               # eqmain.mod L241-243

"""
    eq_xbnd!(tm::TimesModel) -> Int

Generate every EQ(l)_XBND row, in the order of eqmain.mod L241-243 (G with
LO, E with FX, L with UP). Returns the number of rows.

    EQ%1_XBND(ALL_REG,T,C,S,IE)\$((SUM(RPC_IRE(ALL_REG,P,C,IE),1)*%3)\$IRE_XBND(ALL_REG,T,C,S,IE,'%2')) ..
       SUM((RPC_IRE(REG(ALL_REG),P,C,IE),RTPCS_VARF(REG,T,P,C,TS))\$RS_TREE(REG,S,TS),
            SUM(RTP_VNTBYR(REG,T,P,V),
              (VAR_IRE(REG,V,T,P,C,TS,IE)\$(NOT RPC_AIRE(REG,P,C)) +
               (VAR_ACT(REG,V,T,P,TS)*PRC_ACTFLO(REG,V,P,C))\$RPC_AIRE(REG,P,C)) *
              RS_FR(REG,S,TS)
            )
       ) +
       SUM(RPC_IRE(R,P,COM,IMPEXP(IE--1))\$((TOP_IRE(ALL_REG,C,R,COM,P)\$XPT(IE)) +
                                           (TOP_IRE(R,COM,ALL_REG,C,P)\$IMP(IE))),
            SUM(RS_TREE(R,ALL_TS,TS)\$(RTPCS_VARF(R,T,P,COM,TS)*IRE_TSCVT(R,ALL_TS,ALL_REG,S)),
                SUM(RTP_VNTBYR(R,T,P,V),
                  (VAR_IRE(R,V,T,P,COM,TS,IMPEXP)\$(NOT RPC_AIRE(R,P,COM)) +
                   (VAR_ACT(R,V,T,P,TS)*PRC_ACTFLO(R,V,P,COM))\$RPC_AIRE(R,P,COM)) *
                  IRE_TSCVT(R,ALL_TS,ALL_REG,S) * RS_FR(R,ALL_TS,TS)
                )
            )
       )\$(NOT REG(ALL_REG))
      =%1=
       IRE_XBND(ALL_REG,T,C,S,IE,'%2');

GAMS: eqxbnd.mod L17-56 with eqmain.mod L241-243, v4.9.7.
"""
function eq_xbnd!(tm::TimesModel)
    ire_xbnd = gparam(tm, "IRE_XBND")
    isempty(ire_xbnd) && return 0
    reg, milestonyr = gset(tm, "REG"), gset(tm, "MILESTONYR")
    imp, xpt = gset(tm, "IMP"), gset(tm, "XPT")
    rpc_ire, rpc_aire, rs_tree = gset(tm, "RPC_IRE"), gset(tm, "RPC_AIRE"), gset(tm, "RS_TREE")
    prc_actflo, rs_fr, ire_tscvt = gparam(tm, "PRC_ACTFLO"), gparam(tm, "RS_FR"), gparam(tm, "IRE_TSCVT")
    ire_of_rc = indexby(rpc_ire, (1, 3, 4))                         # (r,c,ie)       -> RPC_IRE(r,p,c,ie)
    vint_of_rtp = indexby(gset(tm, "RTP_VNTBYR"), (1, 2, 3))        # (r,t,p)        -> RTP_VNTBYR(r,t,p,v)
    varf_of_rtpc = indexby(gset(tm, "RTPCS_VARF"), (1, 2, 3, 4))    # (r,t,p,c)      -> RTPCS_VARF(r,t,p,c,ts)
    top_from = indexby(gset(tm, "TOP_IRE"), (1, 2))                 # (all_reg,c)    -> TOP_IRE(all_reg,c,r,com,p)
    top_into = indexby(gset(tm, "TOP_IRE"), (3, 4))                 # (all_reg,c)    -> TOP_IRE(r,com,all_reg,c,p)
    tscvt_of = indexby(ire_tscvt, (1, 3, 4))                        # (r,all_reg,s)  -> IRE_TSCVT(r,all_ts,all_reg,s)
    no4, no5 = NTuple{4,String}[], NTuple{5,String}[]
    # the flow of an exchange process: the variable, or the activity times PRC_ACTFLO (RPC_AIRE)
    function flow!(expr, w, r, v, t, p, c, ts, ie)
        if (r, p, c) in rpc_aire
            addterm!(expr, gv(prc_actflo, (r, v, p, c)) * w, tm, "VAR_ACT", r, v, t, p, ts)
        else
            addterm!(expr, w, tm, "VAR_IRE", r, v, t, p, c, ts, ie)
        end
    end

    n = 0
    for (eqtype, bd) in XBND_VARIANTS
        name = "EQ$(eqtype)_XBND"
        rows = NTuple{5,String}[]
        for (all_reg, t, c, s, ie, b) in ire_xbnd.keys                              # L17
            b == bd || continue
            ((t,) in milestonyr && haskey(ire_of_rc, (all_reg, c, ie))) || continue
            val = ire_xbnd.values[(all_reg, t, c, s, ie, b)]
            (bd == "FX" || (bd == "LO" && val != 0) || (bd == "UP" && val != Inf)) || continue      # %3
            push!(rows, (all_reg, t, c, s, ie))
        end
        gams_sort!(rows, tm.data)
        for (all_reg, t, c, s, ie) in rows
            lhs = JuMP.AffExpr(0.0)
            if (all_reg,) in reg                                                    # L23-32
                for (_, p, _, _) in get(ire_of_rc, (all_reg, c, ie), no4)
                    for (_, _, _, v) in get(vint_of_rtp, (all_reg, t, p), no4),
                        (_, _, _, _, ts) in get(varf_of_rtpc, (all_reg, t, p, c), no5)
                        (all_reg, s, ts) in rs_tree || continue
                        flow!(lhs, gv(rs_fr, (all_reg, s, ts)), all_reg, v, t, p, c, ts, ie)        # L27-30
                    end
                end
            else                                                                    # L39-51
                other = ie == "IMP" ? "EXP" : "IMP"                                 # IMPEXP(IE--1)
                links = Tuple{String,String,String}[]                               # (r,com,p) of L39-40
                if (ie,) in xpt
                    for (_, _, r, com, p) in get(top_from, (all_reg, c), no5)
                        push!(links, (r, com, p))
                    end
                end
                if (ie,) in imp
                    for (r, com, _, _, p) in get(top_into, (all_reg, c), no5)
                        push!(links, (r, com, p))
                    end
                end
                for (r, com, p) in links
                    ((r,) in reg && (r, p, com, other) in rpc_ire) || continue
                    for (_, all_ts, _, _) in get(tscvt_of, (r, all_reg, s), no4)    # L42
                        tscvt = gv(ire_tscvt, (r, all_ts, all_reg, s))
                        for (_, _, _, v) in get(vint_of_rtp, (r, t, p), no4),
                            (_, _, _, _, ts) in get(varf_of_rtpc, (r, t, p, com), no5)
                            (r, all_ts, ts) in rs_tree || continue
                            flow!(lhs, tscvt * gv(rs_fr, (r, all_ts, ts)), r, v, t, p, com, ts, other)   # L45-48
                        end
                    end
                end
            end
            rhs = addconst!(JuMP.AffExpr(0.0), gv(ire_xbnd, (all_reg, t, c, s, ie, bd)))    # L55
            gconstraint!(tm, name, (all_reg, t, c, s, ie), eqtype, lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end
