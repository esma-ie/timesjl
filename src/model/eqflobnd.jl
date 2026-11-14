# EQG_FLOBND / EQE_FLOBND / EQL_FLOBND: a bound on the flows of a process
# (FLO_BND) that cannot be a bound of one flow variable: the bound is on a
# timeslice above the flow's own, on a commodity group, on a vintaged process,
# on an exchange process, or on a flow that REDUCE replaced by another
# variable. The equation sums the flow variables at or below the bound's
# timeslice, over the vintages, against the bound.
#
# GAMS: eqflobnd.mod L15-43, v4.9.7, included from eqmain.mod L111-113 as
#   $BATINCLUDE eqflobnd.%1 G LO YES
#   $BATINCLUDE eqflobnd.%1 E FX YES
#   $BATINCLUDE eqflobnd.%1 L UP "(FLO_BND(R,T,P,CG,S,'UP') NE INF)"
# (%1 = equation type, %2 = bound type, %3 = condition on the body); declared
# eqdeclr.mod L79-81; in the model, mod_equa.mod L88-90. The records that stay
# bounds of VAR_FLO (or of VAR_ACT under REDUCE) are set in bnd_flo.mod L27-39
# (`bnd_flo!`, bndmain.jl); bnd_flo.mod L16-24 marks every other record with an
# EPS at the year '%DFLBL%' = '0' (initmty.mod L367), FLO_BND(R,'0',P,CG,S,BD)
# (qack_prep.jl), which the domain below reads.
#
# Macro expansions: %EQ% -> EQ, %VAR% -> VAR, %SOW%/%SWT% -> '' (setglobs.gms
# L348); %R_T% -> 'R,T' (maindrv.mod L39); %cal_red% -> cal_red.red under
# REDUCE YES, cal_nored.red otherwise (pp_reduce.red L58-59). T = MILESTONYR.
#
# Three points of GAMS semantics, each checked on the crafted case
# demo12_flobnd against GAMS's matrix:
# - L19, `RS_BELOW(R,S,TS) OR FLO_BND(R,'0',P,CG,S,'%2')`: a stored EPS is true
#   in a logical expression, so a marked record gives a row at the flow's own
#   timeslice.
# - L20, `$FLO_BND(R,T,P,CG,S,'%2')`: true for a stored EPS as well, so a LO or
#   FX record with the value EPS gives a row with a right-hand side of zero
#   (the LO include has no condition on the value; bnd_flo.mod L16 has already
#   deleted the zero LO records of single commodities that are not emission
#   flows of a standard process).
# - L41, `(...)$%3`: the condition of the UP include is on the body and not on
#   the domain. For an UP record with the value INF the body is empty, `0 =L=
#   0`, and GAMS writes no row.

const FLOBND_VARIANTS = (("G", "LO"), ("E", "FX"), ("L", "UP"))

"""
    eq_flobnd!(tm::TimesModel) -> Int

Generate every EQ(l)_FLOBND row, in the order of eqmain.mod L111-113 (G with
LO, E with FX, L with UP). Returns the number of rows.

    EQ%1_FLOBND(RTP_VARA(R,T,P),CG,S)\$(
        SUM(RTPCS_VARF(R,T,P,C,TS)\$(TS_MAP(R,S,TS)*COM_GMAP(R,CG,C)),
            RS_BELOW(R,S,TS) OR FLO_BND(R,'0',P,CG,S,'%2'))\$FLO_BND(R,T,P,CG,S,'%2')) ..
       (SUM((COM_GMAP(R,CG,C),RTPCS_VARF(R,T,P,C,TS))\$TS_MAP(R,S,TS),
           SUM(RTP_VINTYR(R,V,T,P),
            ( %cal_red% C COM TS P T )\$RP_FLO(R,P) +
            SUM(RPC_IRE(R,P,C,IE),(VAR_IRE(R,V,T,P,C,TS,IE)
    \$IF %REDUCE% == 'YES'   \$(NOT RPC_AIRE(R,P,C))+(VAR_ACT(R,V,T,P,TS)*PRC_ACTFLO(R,V,P,C))\$RPC_AIRE(R,P,C)
            )*(1-2\$XPT(IE)\$(NOT COM(CG))))\$RP_IRE(R,P)))
        - FLO_BND(R,T,P,CG,S,'%2'))\$%3
     =%1= 0;

The flows of a standard process (RP_FLO) enter through `cal_nored!`, which
under REDUCE replaces a flow variable by what stands for it (`cal_red!`). The
flows of an exchange process (RP_IRE) enter as VAR_IRE, or under REDUCE as
VAR_ACT * PRC_ACTFLO where the flow is the activity (RPC_AIRE); with a
commodity group (CG not a commodity) the exports count negative, so the bound
is on the net import, and with a single commodity imports and exports add up
(L36-37).

GAMS: eqflobnd.mod L15-43 with eqmain.mod L111-113, v4.9.7.
"""
function eq_flobnd!(tm::TimesModel)
    flo_bnd = gparam(tm, "FLO_BND")
    isempty(flo_bnd) && return 0
    milestonyr, rtp_vara = gset(tm, "MILESTONYR"), gset(tm, "RTP_VARA")
    ts_map, com_gmap, rs_below = gset(tm, "TS_MAP"), gset(tm, "COM_GMAP"), gset(tm, "RS_BELOW")
    rp_flo, rp_ire, rpc_aire = gset(tm, "RP_FLO"), gset(tm, "RP_IRE"), gset(tm, "RPC_AIRE")
    xpt, com = gset(tm, "XPT"), gset(tm, "COM")
    prc_actflo = gparam(tm, "PRC_ACTFLO")
    varf_of_rtp = indexby(gset(tm, "RTPCS_VARF"), (1, 2, 3))    # (r,t,p) -> RTPCS_VARF(r,t,p,c,ts)
    vint_of_rtp = indexby(gset(tm, "RTP_VINTYR"), (1, 3, 4))    # (r,t,p) -> RTP_VINTYR(r,v,t,p)
    ire_of_rpc = indexby(gset(tm, "RPC_IRE"), (1, 2, 3))        # (r,p,c) -> RPC_IRE(r,p,c,ie)
    dflbl = "0"                                                 # %DFLBL%, initmty.mod L367
    no4, no5 = NTuple{4,String}[], NTuple{5,String}[]

    n = 0
    for (eqtype, bd) in FLOBND_VARIANTS
        name = "EQ$(eqtype)_FLOBND"
        rows = NTuple{5,String}[]
        for (r, t, p, cg, s, b) in flo_bnd.keys
            b == bd || continue
            ((t,) in milestonyr && (r, t, p) in rtp_vara) || continue
            marked = haskey(flo_bnd, (r, dflbl, p, cg, s, bd))                      # L19
            any(get(varf_of_rtp, (r, t, p), no5)) do (_, _, _, c, ts)                 # L18-20
                (r, s, ts) in ts_map && (r, cg, c) in com_gmap && (marked || (r, s, ts) in rs_below)
            end || continue
            push!(rows, (r, t, p, cg, s))
        end
        gams_sort!(rows, tm.data)
        for (r, t, p, cg, s) in rows
            bd == "UP" && flo_bnd.values[(r, t, p, cg, s, bd)] == Inf && continue   # L41 with eqmain.mod L113: an empty body
            std, ire = (r, p) in rp_flo, (r, p) in rp_ire
            group = !((cg,) in com)                                                 # NOT COM(CG), L37
            vints = get(vint_of_rtp, (r, t, p), no4)
            lhs = JuMP.AffExpr(0.0)
            for (_, _, _, c, ts) in get(varf_of_rtp, (r, t, p), no5)                # L24
                ((r, cg, c) in com_gmap && (r, s, ts) in ts_map) || continue
                for (_, v, _, _) in vints                                           # L26
                    std && cal_nored!(lhs, tm, GNum(1.0), r, v, t, p, c, ts)        # L28-30
                    ire || continue
                    for (_, _, _, ie) in get(ire_of_rpc, (r, p, c), no4)            # L33-37
                        sign = GNum(group && (ie,) in xpt ? -1.0 : 1.0)
                        if tm.reduce && (r, p, c) in rpc_aire                       # L34-35
                            addterm!(lhs, sign * gv(prc_actflo, (r, v, p, c)), tm, "VAR_ACT", r, v, t, p, ts)
                        else
                            addterm!(lhs, sign, tm, "VAR_IRE", r, v, t, p, c, ts, ie)
                        end
                    end
                end
            end
            rhs = addconst!(JuMP.AffExpr(0.0), gv(flo_bnd, (r, t, p, cg, s, bd)))   # L41
            gconstraint!(tm, name, (r, t, p, cg, s), eqtype, lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end
