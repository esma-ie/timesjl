# EQG_COMBAL / EQE_COMBAL / EQE_COMPRD: commodity balance (production >=/=
# consumption + demand) and the production-limit equation.
#
# GAMS: eqcombal.mod L19-113, v4.9.7, included from eqmain.mod L98-106 as
#   $BATINCLUDE eqcombal.mod mod G LO BAL
#   $BATINCLUDE eqcombal.mod mod E FX BAL
#   $BATINCLUDE eqcombal.mod mod E FX PRD "* RHS_COMPRD(R,T,C,S)"
# (%2 = equation type, %3 = COM_LIM type, %4 = BAL/PRD, %5 = PRD condition;
# the L UP BAL include at eqmain.mod L101 is commented out), with the
# includes cal_fflo.mod (process flows, OUT/IN), cal_ire.mod (trade,
# IMP OUT IE / EXP IN IE), cal_stgn.mod (storage, L42 and L87) and cal_cap.mod
# (capacity-related flows).
#
# Macro expansions: %EQ% -> EQ, %VAR%/%VARV% -> VAR, %SOW%/%SWT%/%SWS% -> ''
# (setglobs.gms L348); %R_T% -> 'R,T' (maindrv.mod L39); %MX% -> '' so
# COM_FR%MX% is COM_FR (see eqcapact.jl); %STAGES% is not YES (L109 drops).
#
# Not translated yet; data that needs them raises UnportedError:
# - capacity-related flows, cal_cap.mod (NCAP_COM, RPC_CAPFLO), which also
#   carries early retirement (VAR_SCAP/VAR_RCAP);
# - blending, L30-35 and L75-80 (BLE_OPR, BLE_ENV, BLE_TP);
# - elastic demand, L67 and L101 under %TIMESED% (COM_ELAST);
# - non-linear demand VAR_DEM, L110 (RD_NLP);
# - cal_ire.mod L30 when %IREAUXBAL% is set other than by powerflo.vda DECL (whose
#   IREAUX terms, L84, are `ireaux!`: M1.3 change 27b-2).
# The sets these equations read (RCS_COMBAL, RTPCS_VARF, RTP_VNTBYR, ...)
# come from the pre-solve dump: pp_qack.mod changes them after eqmain.

"Includes of eqcombal.mod from eqmain.mod L98-106: (%2, %3, %4)."
const COMBAL_VARIANTS = (("G", "LO", "BAL"), ("E", "FX", "BAL"), ("E", "FX", "PRD"))

function combal_unported(tm::TimesModel)
    d = tm.data
    nonempty_set(name, N) = !isempty(gset_opt(d, name, N))
    nonempty_par(name, N) = !isempty(gparam_opt(d, name, N))
    (nonempty_par("NCAP_COM", 5) || nonempty_set("RPC_CAPFLO", 4)) &&
        throw(UnportedError("cal_cap.mod capacity-related flows in EQ_COMBAL (NCAP_COM / RPC_CAPFLO)"))
    (nonempty_set("BLE_OPR", 3) || nonempty_set("BLE_ENV", 4) || nonempty_set("BLE_TP", 3)) &&
        throw(UnportedError("eqcombal.mod L30-35/L75-80 blending (BLE_OPR / BLE_ENV / BLE_TP)"))
    nonempty_par("COM_ELAST", 5) &&
        throw(UnportedError("eqcombal.mod L67/L101 elastic demand under %TIMESED% (COM_ELAST)"))
    nonempty_par("RD_NLP", 2) && throw(UnportedError("eqcombal.mod L110 non-linear demand VAR_DEM (RD_NLP)"))
    # %IREAUXBAL% comes from powerflo.vda DECL (L221) under %POWERFLO% (`ireaux!`); set any other way, refused
    haskey(tm.switches, "IREAUXBAL") && !powerflo_on(tm) && throw(UnportedError("cal_ire.mod L30 under %IREAUXBAL% without %POWERFLO%"))
    return nothing
end

"""
    combal_context(tm) -> NamedTuple

The sets, parameters and incidence maps the commodity balance and its
cal_fflo/cal_ire terms read, built once per model.
"""
function combal_context(tm::TimesModel)
    get!(tm.cache, "combal") do
        top = gset(tm, "TOP")
        rpc_ire = gset(tm, "RPC_IRE")
        com_agg = gparam(tm, "COM_AGG")
        (top_of_rcio = indexby(top, (1, 3, 4)),                       # (r,c,io) -> TOP(r,p,c,io)
         rp_flo = gset(tm, "RP_FLO"),
         rpc_emis = gset(tm, "RPC_EMIS"),
         fs_emit_of_rpc = indexby(gset(tm, "FS_EMIT"), (1, 2, 3)),     # (r,p,c) -> (r,p,c,cg3,com2)
         vint_of_rtp = indexby(gset(tm, "RTP_VNTBYR"), (1, 2, 3)),     # (r,t,p) -> (r,t,p,v)
         varf_of_rtpc = indexby(gset(tm, "RTPCS_VARF"), (1, 2, 3, 4)), # (r,t,p,c) -> (r,t,p,c,ts)
         rs_fr = gparam(tm, "RS_FR"),
         rtcs_fr = gparam(tm, "RTCS_FR"),
         coef_ptran = gparam(tm, "COEF_PTRAN"),
         rtp_ffcx = gparam(tm, "RTP_FFCX"),
         rtp_ffcs = gparam_opt(tm.data, "RTP_FFCS", 5),
         prc_vint = gset(tm, "PRC_VINT"),
         ire_of_rcie = indexby(rpc_ire, (1, 3, 4)),                    # (r,c,ie) -> RPC_IRE(r,p,c,ie)
         ire_of_r = indexby(rpc_ire, (1,)),                            # r -> RPC_IRE(r,p,com,ie)
         rpc_aire = gset(tm, "RPC_AIRE"),
         prc_actflo = gparam(tm, "PRC_ACTFLO"),
         ire_flosum = gparam(tm, "IRE_FLOSUM"),
         agg_of_rtc = indexby(com_agg, (1, 2, 4)),                      # (r,t,c) -> COM_AGG(r,t,com,c)
         com_agg = com_agg,
         varc_of_rtc = indexby(gset(tm, "RTCS_VARC"), (1, 2, 3)),       # (r,t,com) -> (r,t,com,ts)
         rs_tree = gset(tm, "RS_TREE"),
         rc_agp = gset(tm, "RC_AGP"),
         com_ie = gparam(tm, "COM_IE"),
         stg_of_rc = indexby(gset(tm, "RPC_STG"), (1, 3)),              # (r,c) -> RPC_STG(r,p,c)
         top = gset(tm, "TOP"),
         rpc_stgn = gset(tm, "RPC_STGN"),
         rpcs_var_of_rpc = indexby(gset(tm, "RPCS_VAR"), (1, 2, 3)),    # (r,p,c) -> RPCS_VAR(r,p,c,ts)
         stg_eff = gparam(tm, "STG_EFF"))
    end
end

"Per-term multiplier `%3`/`%4` of cal_fflo/cal_ire when the caller passes none: 1."
_pk(pk, p, v, ts) = pk === nothing ? GNum(1.0) : pk(p, v, ts)::GNum

"""
    cal_fflo!(expr, tm, mult, io, r, t, c, s; pk=nothing, pcond=nothing) -> expr

Flows of commodity `c` into (`io` = "IN") or out of (`io` = "OUT") processes,
for the balance row (r,t,c,s), each coefficient multiplied by `mult`:

    SUM(TOP(RP_FLO(R,P),C,'%1')\$(NOT RPC_EMIS(R,P,C)),
        SUM((RTP_VNTBYR(R,T,P,V),RTPCS_VARF(R,T,P,C,TS)),
            VAR_FLO(R,V,T,P,C,TS) * RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS)) %3)%4) +
    SUM(TOP(RPC_EMIS(RP_FLO(R,P),C),'%1')%4,
        SUM((FS_EMIT(R,P,C,CG3,COM2),RTPCS_VARF(R,T,P,COM2,TS))\$RS_FR(R,S,TS),
            SUM(RTP_VNTBYR(R,T,P,V), VAR_FLO(R,V,T,P,COM2,TS) * COEF_PTRAN(R,V,P,CG3,COM2,C,TS) %SHP1% %3) *
            RS_FR(R,S,TS)*(1+RTCS_FR(R,T,COM2,S,TS))))

with %SHP1% = `*(1+RTP_FFCX(R,V,T,P,CG3,C)\$PRC_VINT(R,P))` [`*(1+RTP_FFCS(R,V,P,CG3,C))`
when RTP_FFCS is DEFINED]. The caller's arguments:
- %3, the per-term multiplier, is `pk(p, v, ts)` (a `GNum`; TS is the flow
  variable's timeslice, COM2's on the RPC_EMIS branch); `nothing` means
  `%3 = ''` (eqcombal.mod);
- %4, a `\$` condition on (R,P,C), is `pcond(p)`; `nothing` means `%4 = ''`.
eqpeak.mod L44 passes `'*(NCAP_PKCNT(R,V,P,S)**RPC_PKF(R,P,C))' '\$RPC_PKF(R,P,C)'`,
L65 `'*FLO_PKCOI(R,T,P,C,TS)'`.

Under %REDUCE% YES the flows go through cal_red.red instead (L35-50,
`cal_fflo_red!`).

GAMS: cal_fflo.mod L15-50, v4.9.7.
"""
function cal_fflo!(expr::JuMP.AffExpr, tm::TimesModel, mult::GNum, io::String,
                   r::String, t::String, c::String, s::String; pk=nothing, pcond=nothing)
    x = combal_context(tm)
    tm.reduce && return cal_fflo_red!(expr, tm, x, mult, io, r, t, c, s; pk, pcond)
    for (_, p, _, _) in get(x.top_of_rcio, (r, c, io), NTuple{4,String}[])
        (r, p) in x.rp_flo || continue
        pcond === nothing || pcond(p)::Bool || continue          # %4 (both branches, L25 and L28)
        vints = get(x.vint_of_rtp, (r, t, p), NTuple{4,String}[])
        if !((r, p, c) in x.rpc_emis)
            for (_, _, _, v) in vints, (_, _, _, _, ts) in get(x.varf_of_rtpc, (r, t, p, c), NTuple{5,String}[])
                k = mult * (gv(x.rs_fr, (r, s, ts)) * (1 + gv(x.rtcs_fr, (r, t, c, s, ts))) * _pk(pk, p, v, ts))
                addterm!(expr, k, tm, "VAR_FLO", r, v, t, p, c, ts)
            end
        else
            for (_, _, _, cg3, com2) in get(x.fs_emit_of_rpc, (r, p, c), NTuple{5,String}[])
                for (_, _, _, _, ts) in get(x.varf_of_rtpc, (r, t, p, com2), NTuple{5,String}[])
                    haskey(x.rs_fr, (r, s, ts)) || continue
                    w = gv(x.rs_fr, (r, s, ts)) * (1 + gv(x.rtcs_fr, (r, t, com2, s, ts)))
                    for (_, _, _, v) in vints
                        shp1 = (1 + gif(gv(x.rtp_ffcx, (r, v, t, p, cg3, c)), (r, p) in x.prc_vint)) *
                               (1 + gv(x.rtp_ffcs, (r, v, p, cg3, c)))
                        k = mult * (gv(x.coef_ptran, (r, v, p, cg3, com2, c, ts)) * shp1 * _pk(pk, p, v, ts) * w)
                        addterm!(expr, k, tm, "VAR_FLO", r, v, t, p, com2, ts)
                    end
                end
            end
        end
    end
    return expr
end

"""
    cal_fflo_red!(expr, tm, x, mult, io, r, t, c, s; pk, pcond) -> expr

cal_fflo.mod's REDUCE path (%REDUCE% YES), the flows of `cal_fflo!` through
cal_red.red (`cal_red!`):

    SUM(TOP(RP_FLO(R,P),C,'%1')\$(NOT PRC_VINT(R,P)),
        SUM(RTPCS_VARF(R,V(T),P,C,TS),
            [cal_red.red C COM TS P T '' T] * RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS)) %3)%4) +
    SUM((TOP(PRC_VINT(RP_FLO(R,P)),C,'%1'),RTPCS_VARF(R,T,P,C,TS))%4,
        [cal_red.red C COM TS P T '' V SUM 'RTP_VNTBYR(R,T,P,V),' %3] * RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS))) +

A process without vintages takes its flows at V = T (`V(T)`), with the shape
factors of %7 = T; a vintaged one sums cal_red.red over RTP_VNTBYR, %3
multiplying each term (%10), with those of %7 = V. %3 is `pk(p, v, ts)`
(TS the flow's own timeslice, V = T for the first sum), %4 `pcond(p)`.

GAMS: cal_fflo.mod L35-50, cal_red.red L15-56, v4.9.7.
"""
function cal_fflo_red!(expr::JuMP.AffExpr, tm::TimesModel, x, mult::GNum, io::String,
                       r::String, t::String, c::String, s::String; pk=nothing, pcond=nothing)
    for (_, p, _, _) in get(x.top_of_rcio, (r, c, io), NTuple{4,String}[])
        (r, p) in x.rp_flo || continue
        pcond === nothing || pcond(p)::Bool || continue                  # %4
        for (_, _, _, _, ts) in get(x.varf_of_rtpc, (r, t, p, c), NTuple{5,String}[])
            haskey(x.rs_fr, (r, s, ts)) || continue                      # RS_FR(R,S,TS) multiplies: no record, no term
            w = mult * (gv(x.rs_fr, (r, s, ts)) * (1 + gv(x.rtcs_fr, (r, t, c, s, ts))))
            if !((r, p) in x.prc_vint)
                cal_red!(expr, tm, w * _pk(pk, p, t, ts), r, t, t, p, c, ts; mode="T")
            else
                for (_, _, _, v) in get(x.vint_of_rtp, (r, t, p), NTuple{4,String}[])
                    cal_red!(expr, tm, w * _pk(pk, p, v, ts), r, v, t, p, c, ts; mode="V")
                end
            end
        end
    end
    return expr
end

"""
    cal_ire!(expr, tm, mult, ie, io, r, t, c, s; pk=nothing, pfilter=nothing) -> expr

Trade flows of commodity `c` for the balance row (r,t,c,s): the actual
exchange in direction `ie` (IMP for production, EXP for consumption) and the
auxiliary flows (IRE_FLOSUM) of side `io`, each coefficient multiplied by
`mult`. eqcombal.mod includes it as `cal_ire.mod IMP OUT IE` and `EXP IN IE`:

    SUM((RPC_IRE(%6R,P%7,C,'%1'),RTP_VNTBYR(R,T,P,V)),
        SUM(RTPCS_VARF(R,T,P,C,TS)\$RS_FR(R,S,TS),
            (VAR_IRE(R,V,T,P,C,TS,'%1')\$(NOT RPC_AIRE(R,P,C)) +
             (VAR_ACT(R,V,T,P,TS)*PRC_ACTFLO(R,V,P,C))\$RPC_AIRE(R,P,C))%4 * RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS)))) +
    SUM((RPC_IRE(%6R,P%7,COM,IE),RTPCS_VARF(R,T,P,COM,TS))\$(IRE_FLOSUM(R,T,P,COM,TS,IE,C,'%2')\$RS_FR(R,S,TS)),
        IRE_FLOSUM(R,T,P,COM,TS,IE,C,'%2') *
        SUM(RTP_VNTBYR(R,T,P,V), %MX% (VAR_IRE(R,V,T,P,COM,TS,IE)\$(NOT RPC_AIRE(R,P,COM)) +
                                     (VAR_ACT(R,V,T,P,TS)*PRC_ACTFLO(R,V,P,COM))\$RPC_AIRE(R,P,COM))%4) *
        RS_FR(R,S,TS)*(1+RTCS_FR(R,T,COM,S,TS)))

%IE% is the summation index IE because %3 = IE (L18-19); the actual
exchange is skipped only for EXP OUT and IMP IN (L20-21), which no caller
passes; %MX% = `(1+RTP_FFCS(R,V,P,C,C))*` when RTP_FFCS is DEFINED (L16),
otherwise empty. The caller's arguments:
- %4, the per-term multiplier, is `pk(p, v, ts)` (TS is the trade variable's
  timeslice); `nothing` means `%4 = ''` (eqcombal.mod);
- %6/%7 wrap the process index in a set, `RPC_IRE(%6R,P%7,...)`, which
  restricts both sums; `pfilter(p)` tests membership; `nothing` means none.
  eqpeak.mod L32 passes `PRC_PKNO(` `)`;
- %5 is only used by %IREAUXBAL% (L30): the callers add powerflo.vda's
  IREAUX terms with `ireaux!` (M1.3 change 27b-2).

GAMS: cal_ire.mod L16-41, v4.9.7.
"""
function cal_ire!(expr::JuMP.AffExpr, tm::TimesModel, mult::GNum, ie::String, io::String,
                  r::String, t::String, c::String, s::String; pk=nothing, pfilter=nothing)
    x = combal_context(tm)
    # Actual exchange (L24-28).
    if !((ie, io) in (("EXP", "OUT"), ("IMP", "IN")))
        for (_, p, _, _) in get(x.ire_of_rcie, (r, c, ie), NTuple{4,String}[])
            pfilter === nothing || pfilter(p)::Bool || continue       # %6R,P%7
            vints = get(x.vint_of_rtp, (r, t, p), NTuple{4,String}[])
            for (_, _, _, v) in vints, (_, _, _, _, ts) in get(x.varf_of_rtpc, (r, t, p, c), NTuple{5,String}[])
                haskey(x.rs_fr, (r, s, ts)) || continue
                w = mult * (gv(x.rs_fr, (r, s, ts)) * (1 + gv(x.rtcs_fr, (r, t, c, s, ts))) * _pk(pk, p, v, ts))
                if !((r, p, c) in x.rpc_aire)
                    addterm!(expr, w, tm, "VAR_IRE", r, v, t, p, c, ts, ie)
                else
                    addterm!(expr, w * gv(x.prc_actflo, (r, v, p, c)), tm, "VAR_ACT", r, v, t, p, ts)
                end
            end
        end
    end
    # Auxiliary flows (L35-41), over every RPC_IRE(R,P,COM,IE) of the region.
    isempty(x.ire_flosum) && return expr
    for (_, p, com, iex) in get(x.ire_of_r, (r,), NTuple{4,String}[])
        pfilter === nothing || pfilter(p)::Bool || continue           # %6R,P%7
        vints = get(x.vint_of_rtp, (r, t, p), NTuple{4,String}[])
        for (_, _, _, _, ts) in get(x.varf_of_rtpc, (r, t, p, com), NTuple{5,String}[])
            fs = (r, t, p, com, ts, iex, c, io)
            (haskey(x.ire_flosum, fs) && haskey(x.rs_fr, (r, s, ts))) || continue
            w = gv(x.ire_flosum, fs)
            tail = gv(x.rs_fr, (r, s, ts)) * (1 + gv(x.rtcs_fr, (r, t, com, s, ts)))
            for (_, _, _, v) in vints
                mx = 1 + gv(x.rtp_ffcs, (r, v, p, c, c))
                k = mult * (w * mx * _pk(pk, p, v, ts) * tail)
                if !((r, p, com) in x.rpc_aire)
                    addterm!(expr, k, tm, "VAR_IRE", r, v, t, p, com, ts, iex)
                else
                    addterm!(expr, k * gv(x.prc_actflo, (r, v, p, com)), tm, "VAR_ACT", r, v, t, p, ts)
                end
            end
        end
    end
    return expr
end

"""
    cal_stgn!(expr, tm, mult, io, r, t, c, s; cond, f3, f4, f6) -> expr

Storage flows of commodity `c` for the balance row (r,t,c,s), each
coefficient multiplied by `mult`; `io` is %1 (OUT for production, IN for
consumption) and %2 is the other direction:

    SUM((TOP(RPC_STG(R,P,C),'%1'),RPCS_VAR(R,P,C,TS))\$%5,
        SUM(RTP_VNTBYR(R,T,P,V),
            (VAR_S%1(R,V,T,P,C,TS)%3 - %4VAR_S%2(R,V,T,P,C,TS)\$RPC_STGN(R,P,C,'%2'))%6)\$(NOT RPC_STGN(R,P,C,'%1')) *
        RS_FR(R,S,TS))

The caller's arguments:
- %5, a condition on (P,TS), is `cond(p, ts)`;
- %3, the factor on VAR_S%1, is `f3(p, v)` (`*STG_EFF(R,V,P)` or '' = 1);
- %4, the factor on VAR_S%2, is `f4(p, v)` ('' = 1, `STG_EFF(R,V,P)*`, ...);
- %6, the factor on the whole difference, is `f6(p, v)` ('' = 1).

eqcombal.mod L42 passes `OUT IN '*STG_EFF(R,V,P)' '' "(NOT PRC_NSTTS(R,P,TS))"`,
L87 `IN OUT '' 'STG_EFF(R,V,P)*' "((NOT PRC_MAP(R,'NST',P))+PRC_NSTTS(R,P,TS))"`;
eqpeak.mod L41 and L75 add the NCAP_PKCNT/RPC_PKF factors (eqpeak.jl). There
is no RTCS_FR factor here, unlike cal_fflo. With RPC_STGN (a stored
commodity on one side of the topology only, ppmain.mod L115) the other
direction's flow is netted (%4) and the process's own direction is left out.

GAMS: cal_stgn.mod L17-22, v4.9.7.
"""
function cal_stgn!(expr::JuMP.AffExpr, tm::TimesModel, mult::GNum, io::String,
                   r::String, t::String, c::String, s::String; cond, f3, f4, f6)
    x = combal_context(tm)
    io2 = io == "OUT" ? "IN" : "OUT"
    for (_, p, _) in get(x.stg_of_rc, (r, c), NTuple{3,String}[])
        (r, p, c, io) in x.top || continue                       # TOP(RPC_STG(R,P,C),'%1')
        (r, p, c, io) in x.rpc_stgn && continue                  # $(NOT RPC_STGN(R,P,C,'%1'))
        stgn2 = (r, p, c, io2) in x.rpc_stgn
        vints = get(x.vint_of_rtp, (r, t, p), NTuple{4,String}[])
        for (_, _, _, ts) in get(x.rpcs_var_of_rpc, (r, p, c), NTuple{4,String}[])
            cond(p, ts)::Bool || continue                        # %5
            fr = gv(x.rs_fr, (r, s, ts))
            iszero(fr) && continue
            for (_, _, _, v) in vints
                k6 = f6(p, v)::GNum
                addterm!(expr, mult * (f3(p, v)::GNum * k6 * fr), tm, "VAR_S$(io)", r, v, t, p, c, ts)
                stgn2 && addterm!(expr, mult * (-(f4(p, v)::GNum) * k6 * fr), tm, "VAR_S$(io2)", r, v, t, p, c, ts)
            end
        end
    end
    return expr
end

"""
    combal_aggregation!(expr, tm, mult, r, t, c, s) -> expr

Commodity aggregation on the production side (eqcombal.mod L45-47):

    SUM(COM\$COM_AGG(R,T,COM,C), COM_AGG(R,T,COM,C) *
        SUM(RTCS_VARC(R,T,COM,TS)\$RS_TREE(R,S,TS), RS_FR(R,S,TS)*(1+RTCS_FR(R,T,COM,S,TS)) *
            (VAR_COMNET(R,T,COM,TS)\$RC_AGP(R,COM,'LO') + VAR_COMPRD(R,T,COM,TS)\$RC_AGP(R,COM,'FX'))))
"""
function combal_aggregation!(expr::JuMP.AffExpr, tm::TimesModel, mult::GNum,
                             r::String, t::String, c::String, s::String)
    x = combal_context(tm)
    for (_, _, com, _) in get(x.agg_of_rtc, (r, t, c), NTuple{4,String}[])
        a = gv(x.com_agg, (r, t, com, c))
        for (_, _, _, ts) in get(x.varc_of_rtc, (r, t, com), NTuple{4,String}[])
            (r, s, ts) in x.rs_tree || continue
            k = mult * (a * (gv(x.rs_fr, (r, s, ts)) * (1 + gv(x.rtcs_fr, (r, t, com, s, ts)))))
            (r, com, "LO") in x.rc_agp && addterm!(expr, k, tm, "VAR_COMNET", r, t, com, ts)
            (r, com, "FX") in x.rc_agp && addterm!(expr, k, tm, "VAR_COMPRD", r, t, com, ts)
        end
    end
    return expr
end

"""
    eq_combal!(tm::TimesModel) -> Int

Generate every EQG_COMBAL, EQE_COMBAL and EQE_COMPRD row (eqmain.mod
L98-106) from `tm.data`. Returns the number of rows generated.

GAMS: eqcombal.mod L19-113, v4.9.7, with cal_fflo.mod L15-33,
cal_ire.mod L16-41 and cal_stgn.mod L17-22.
"""
function eq_combal!(tm::TimesModel)
    combal_unported(tm)
    n = 0
    for (eqtype, lim, kind) in COMBAL_VARIANTS
        n += eq_combal!(tm, eqtype, lim, kind)
    end
    return n
end

"""
    eq_combal!(tm, eqtype, lim, kind) -> Int

One include of eqcombal.mod: %2 = `eqtype`, %3 = `lim`, %4 = `kind`
(BAL or PRD; PRD adds the condition `* RHS_COMPRD(R,T,C,S)`).

    EQ%2_COM%4(R,T,C,S)\$(RCS_COM%4(R,T,C,S,'%3') %5) ..
      ( ([cal_fflo OUT] + [cal_ire IMP OUT IE] + [cal_stgn OUT IN] + [aggregation]) * COM_IE(R,T,C,S)
      )\$(NOT RHS_COMPRD(R,T,C,S)) + VAR_COMPRD(R,T,C,S)\$RHS_COMPRD(R,T,C,S)   [BAL; PRD: no \$/VAR_COMPRD]
      - ([cal_fflo IN] + [cal_ire EXP IN IE] + [cal_stgn IN OUT])                   [BAL only]
      =%2=
      PRD: VAR_COMPRD(R,T,C,S)\$RHS_COMPRD(R,T,C,S)
      BAL: [VAR_COMNET(R,T,C,S)\$RHS_COMBAL(R,T,C,S) +   (FX only)]
           ((COM_PROJ(R,T,C)\$(NOT RD_NLP(R,C)) +
             SUM(MI_DMAS(RD_AGG(R,COM),C), RD_SHAR(R,T,COM,C)*VAR_COMPRD(R,T,COM,'ANNUAL'))
            ) * COM_FR(R,T,C,S))\$DEM(R,C);

GAMS: eqcombal.mod L19-113, v4.9.7.
"""
function eq_combal!(tm::TimesModel, eqtype::String, lim::String, kind::String)
    kind in ("BAL", "PRD") || throw(ArgumentError("kind (%4) must be BAL or PRD, got $kind"))
    name = "EQ$(eqtype)_COM$(kind)"
    x = combal_context(tm)
    rcs = gset(tm, "RCS_COM$(kind)")
    milestonyr = gset(tm, "MILESTONYR")
    rhs_comprd = gset(tm, "RHS_COMPRD")
    rhs_combal = gset(tm, "RHS_COMBAL")
    dem = gset(tm, "DEM")
    com_proj = gparam(tm, "COM_PROJ")
    com_fr = gparam(tm, "COM_FR")
    rd_nlp = gparam(tm, "RD_NLP")
    rd_agg = gset(tm, "RD_AGG")
    rd_shar = gparam(tm, "RD_SHAR")
    dmas_of_rc = indexby(gset(tm, "MI_DMAS"), (1, 3))   # (r,c) -> MI_DMAS(r,com,c)
    nstts, prc_map = gset(tm, "PRC_NSTTS"), gset(tm, "PRC_MAP")
    one = GNum(1.0)

    n = 0
    for (r, t, c, s, l) in rcs
        l == lim || continue
        (t,) in milestonyr || continue                   # %R_T% = R,T: T controls
        kind == "PRD" && !((r, t, c, s) in rhs_comprd) && continue

        lhs = JuMP.AffExpr(0.0)
        # Production (L23-58).
        if kind == "BAL" && (r, t, c, s) in rhs_comprd
            addterm!(lhs, GNum(1.0), tm, "VAR_COMPRD", r, t, c, s)
        else
            ie = gv(x.com_ie, (r, t, c, s))
            cal_fflo!(lhs, tm, ie, "OUT", r, t, c, s)
            cal_ire!(lhs, tm, ie, "IMP", "OUT", r, t, c, s)
            cal_stgn!(lhs, tm, ie, "OUT", r, t, c, s;                                     # L42
                      cond=(p, ts) -> !((r, p, ts) in nstts), f3=(p, v) -> gv(x.stg_eff, (r, v, p)),
                      f4=(p, v) -> one, f6=(p, v) -> one)
            combal_aggregation!(lhs, tm, ie, r, t, c, s)
        end
        # Consumption (L69-93), BAL only.
        if kind == "BAL"
            cal_fflo!(lhs, tm, GNum(-1.0), "IN", r, t, c, s)
            cal_ire!(lhs, tm, GNum(-1.0), "EXP", "IN", r, t, c, s)
            ireaux!(lhs, tm, -gv(x.com_ie, (r, t, c, s)), r, t, c, s)                    # L84: cal_ire.mod L30, IREAUXIN
            cal_stgn!(lhs, tm, GNum(-1.0), "IN", r, t, c, s;                              # L87
                      cond=(p, ts) -> !((r, "NST", p) in prc_map) || (r, p, ts) in nstts,
                      f3=(p, v) -> one, f4=(p, v) -> gv(x.stg_eff, (r, v, p)), f6=(p, v) -> one)
        end

        rhs = JuMP.AffExpr(0.0)
        if kind == "PRD"
            addterm!(rhs, GNum(1.0), tm, "VAR_COMPRD", r, t, c, s)    # L100, row exists only under RHS_COMPRD
        else
            if lim == "FX" && (r, t, c, s) in rhs_combal              # L106
                addterm!(rhs, GNum(1.0), tm, "VAR_COMNET", r, t, c, s)
            end
            if (r, c) in dem                                          # L110
                fr = gv(com_fr, (r, t, c, s))
                haskey(rd_nlp, (r, c)) || addconst!(rhs, gv(com_proj, (r, t, c)) * fr)
                for (_, com, _) in get(dmas_of_rc, (r, c), NTuple{3,String}[])
                    (r, com) in rd_agg || continue
                    addterm!(rhs, gv(rd_shar, (r, t, com, c)) * fr, tm, "VAR_COMPRD", r, t, com, "ANNUAL")
                end
            end
        end

        gconstraint!(tm, name, (r, t, c, s), eqtype, lhs, rhs) === nothing || (n += 1)
    end
    return n
end
