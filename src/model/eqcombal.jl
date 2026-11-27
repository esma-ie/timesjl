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
# Elastic demand (L67, L101, %TIMESED% YES) is translated since M1.3 change 69.
# - non-linear demand VAR_DEM, L110 (RD_NLP);
# - cal_ire.mod L30 when %IREAUXBAL% is set other than by powerflo.vda DECL (whose
#   IREAUX terms, L84, are `ireaux!`: M1.3 change 27b-2).
# Blending (L30-35 production, L75-80 consumption; `combal_blend_out!`,
# `combal_blend_in!`) reads the sets and parameters of ppmain.mod L1228-1333
# (ppmain_blend.jl).
# The sets these equations read (RCS_COMBAL, RTPCS_VARF, RTP_VNTBYR, ...)
# come from the pre-solve dump: pp_qack.mod changes them after eqmain.

"Includes of eqcombal.mod from eqmain.mod L98-106: (%2, %3, %4)."
const COMBAL_VARIANTS = (("G", "LO", "BAL"), ("E", "FX", "BAL"), ("E", "FX", "PRD"))

function combal_unported(tm::TimesModel)
    d = tm.data
    nonempty_set(name, N) = !isempty(gset_opt(d, name, N))
    nonempty_par(name, N) = !isempty(gparam_opt(d, name, N))
    nonempty_par("RD_NLP", 2) && throw(UnportedError("eqcombal.mod L110 non-linear demand VAR_DEM (RD_NLP)"))
    # %IREAUXBAL% comes from powerflo.vda DECL (L221) under %POWERFLO% (`ireaux!`); set any other way, refused
    haskey(tm.switches, "IREAUXBAL") && !powerflo_on(tm) && throw(UnportedError("cal_ire.mod L30 under %IREAUXBAL% without %POWERFLO%"))
    return nothing
end

"""
    combal_context(tm) -> NamedTuple

The sets, parameters and incidence maps the commodity balance and its
cal_fflo/cal_ire terms read, built once per model.

`tm.cache` is a `Dict{String,Any}`, so the type of the context is not known where it is fetched.
Each function that reads it therefore fetches it in an outer method and does its work in an inner
method that takes the context as an argument (a function barrier): Julia compiles the inner method
for the context's concrete type, and every `x.field` in it is a typed field access (Phase 2,
change 1; the terms, their arithmetic and their order are those of the outer method's docstring).
"""
function combal_context(tm::TimesModel)
    get!(tm.cache, "combal") do
        top = gset(tm, "TOP")
        rpc_ire = gset(tm, "RPC_IRE")
        com_agg = gparam(tm, "COM_AGG")
        varf_of_rtpc = indexby(gset(tm, "RTPCS_VARF"), (1, 2, 3, 4))
        ire_flosum = gparam(tm, "IRE_FLOSUM")
        (top_of_rcio = indexby(top, (1, 3, 4)),                       # (r,c,io) -> TOP(r,p,c,io)
         rp_flo = gset(tm, "RP_FLO"),
         rpc_emis = gset(tm, "RPC_EMIS"),
         fs_emit_of_rpc = indexby(gset(tm, "FS_EMIT"), (1, 2, 3)),     # (r,p,c) -> (r,p,c,cg3,com2)
         vint_of_rtp = indexby(gset(tm, "RTP_VNTBYR"), (1, 2, 3)),     # (r,t,p) -> (r,t,p,v)
         varf_of_rtpc = varf_of_rtpc,                                  # (r,t,p,c) -> (r,t,p,c,ts)
         rs_fr = gparam(tm, "RS_FR"),
         rtcs_fr = gparam(tm, "RTCS_FR"),
         coef_ptran = gparam(tm, "COEF_PTRAN"),
         rtp_ffcx = gparam(tm, "RTP_FFCX"),
         rtp_ffcs = gparam_opt(tm.data, "RTP_FFCS", 5),
         prc_vint = gset(tm, "PRC_VINT"),
         ire_of_rcie = indexby(rpc_ire, (1, 3, 4)),                    # (r,c,ie) -> RPC_IRE(r,p,c,ie)
         flosum_of_rtcio = ire_flosum_index(indexby(rpc_ire, (1,)), ire_flosum, varf_of_rtpc),   # (r,t,c,io) -> IRE_FLOSUM(r,t,p,com,ts,ie,c,io)
         rpc_aire = gset(tm, "RPC_AIRE"),
         prc_actflo = gparam(tm, "PRC_ACTFLO"),
         ire_flosum = ire_flosum,
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
         stg_eff = gparam(tm, "STG_EFF"),
         # blending (eqcombal.mod L30-35, L75-80)
         ble = gset_opt(tm.data, "BLE", 1),
         opr = gset_opt(tm.data, "OPR", 1),
         ble_opr = gset_opt(tm.data, "BLE_OPR", 3),
         ble_opr_of_rb = indexby(gset_opt(tm.data, "BLE_OPR", 3), (1, 2)),   # (r,ble) -> BLE_OPR(r,ble,opr)
         ble_env_of_rc = indexby(gset_opt(tm.data, "BLE_ENV", 4), (1, 2)),   # (r,c) -> BLE_ENV(r,c,ble,opr)
         ble_tp_of_rt = indexby(gset_opt(tm.data, "BLE_TP", 3), (1, 2)),     # (r,t) -> BLE_TP(r,t,ble)
         ble_tp = gset_opt(tm.data, "BLE_TP", 3),
         ble_inp_of_rc = indexby(gset_opt(tm.data, "BLE_INP", 3), (1, 3)),   # (r,c) -> BLE_INP(r,ble,c)
         ble_bal = gparam_opt(tm.data, "BLE_BAL", 4),
         env_bl = gparam_opt(tm.data, "ENV_BL", 5),
         bl_inp = gparam_opt(tm.data, "BL_INP", 3))
    end
end

"""
    ire_flosum_index(ire_of_r, ire_flosum, varf_of_rtpc) -> Dict

For the auxiliary flows of cal_ire.mod (L35-41), the sum

    SUM((RPC_IRE(R,P,COM,IE),RTPCS_VARF(R,T,P,COM,TS))\$(IRE_FLOSUM(R,T,P,COM,TS,IE,C,'%2')\$RS_FR(R,S,TS)), ...)

by the indices the row fixes: (r,t,c,io) -> the entries IRE_FLOSUM(r,t,p,com,ts,ie,c,io) that have
an RPC_IRE(r,p,com,ie) and an RTPCS_VARF(r,t,p,com,ts), in the order the sum reaches them: RPC_IRE
of the region in record order (`ire_of_r`: r -> RPC_IRE(r,p,com,ie)), then TS in the record order of
RTPCS_VARF(r,t,p,com,.). `cal_ire!` then visits only the entries of its row instead of probing
IRE_FLOSUM for every RPC_IRE of the region and every timeslice (Phase 2, change 2). The same terms
in the same order: the index is built by walking that very double loop once per (r,t) that
IRE_FLOSUM has, so a term's position does not depend on IRE_FLOSUM's own record order.

GAMS: cal_ire.mod L35-41, v4.9.7.
"""
function ire_flosum_index(ire_of_r::Dict{NTuple{1,String},Vector{NTuple{4,String}}}, ire_flosum::GamsParam{8},
                          varf_of_rtpc::Dict{NTuple{4,String},Vector{NTuple{5,String}}})
    out = Dict{NTuple{4,String},Vector{NTuple{8,String}}}()
    isempty(ire_flosum) && return out
    # (r,t,p,com,ts,ie) -> the entries with those labels (one per (c,io)); `haskey` reads `.values`
    of_flow = Dict{NTuple{6,String},Vector{NTuple{8,String}}}()
    rts = NTuple{2,String}[]
    seen = Set{NTuple{2,String}}()
    for fs in ire_flosum.keys
        haskey(ire_flosum, fs) || continue
        push!(get!(() -> NTuple{8,String}[], of_flow, (fs[1], fs[2], fs[3], fs[4], fs[5], fs[6])), fs)
        (fs[1], fs[2]) in seen || (push!(seen, (fs[1], fs[2])); push!(rts, (fs[1], fs[2])))
    end
    for (r, t) in rts
        for (_, p, com, iex) in get(ire_of_r, (r,), NO4)
            for (_, _, _, _, ts) in get(varf_of_rtpc, (r, t, p, com), NO5)
                for fs in get(of_flow, (r, t, p, com, ts, iex), NO_FLOSUM)
                    push!(get!(() -> NTuple{8,String}[], out, (r, t, fs[7], fs[8])), fs)
                end
            end
        end
    end
    return out
end

const NO_FLOSUM = NTuple{8,String}[]

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
cal_fflo!(expr::JuMP.AffExpr, tm::TimesModel, mult::GNum, io::String,
          r::String, t::String, c::String, s::String; pk=nothing, pcond=nothing) =
    cal_fflo!(expr, tm, combal_context(tm), mult, io, r, t, c, s, pk, pcond)

# `cal_fflo!` with the context `x` as a typed argument (see `combal_context`). GAMS: cal_fflo.mod L15-50, v4.9.7.
function cal_fflo!(expr::JuMP.AffExpr, tm::TimesModel, x::NamedTuple, mult::GNum, io::String,
                   r::String, t::String, c::String, s::String, pk::PK, pcond::PC) where {PK,PC}
    tm.reduce && return cal_fflo_red!(expr, tm, x, mult, io, r, t, c, s; pk, pcond)
    for (_, p, _, _) in get(x.top_of_rcio, (r, c, io), NO4)
        (r, p) in x.rp_flo || continue
        pcond === nothing || pcond(p)::Bool || continue          # %4 (both branches, L25 and L28)
        vints = get(x.vint_of_rtp, (r, t, p), NO4)
        if !((r, p, c) in x.rpc_emis)
            for (_, _, _, v) in vints, (_, _, _, _, ts) in get(x.varf_of_rtpc, (r, t, p, c), NO5)
                k = mult * (gv(x.rs_fr, (r, s, ts)) * (1 + gv(x.rtcs_fr, (r, t, c, s, ts))) * _pk(pk, p, v, ts))
                addterm!(expr, k, tm, "VAR_FLO", r, v, t, p, c, ts)
            end
        else
            for (_, _, _, cg3, com2) in get(x.fs_emit_of_rpc, (r, p, c), NO5)
                for (_, _, _, _, ts) in get(x.varf_of_rtpc, (r, t, p, com2), NO5)
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
    for (_, p, _, _) in get(x.top_of_rcio, (r, c, io), NO4)
        (r, p) in x.rp_flo || continue
        pcond === nothing || pcond(p)::Bool || continue                  # %4
        for (_, _, _, _, ts) in get(x.varf_of_rtpc, (r, t, p, c), NO5)
            haskey(x.rs_fr, (r, s, ts)) || continue                      # RS_FR(R,S,TS) multiplies: no record, no term
            w = mult * (gv(x.rs_fr, (r, s, ts)) * (1 + gv(x.rtcs_fr, (r, t, c, s, ts))))
            if !((r, p) in x.prc_vint)
                cal_red!(expr, tm, w * _pk(pk, p, t, ts), r, t, t, p, c, ts; mode="T")
            else
                for (_, _, _, v) in get(x.vint_of_rtp, (r, t, p), NO4)
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
cal_ire!(expr::JuMP.AffExpr, tm::TimesModel, mult::GNum, ie::String, io::String,
         r::String, t::String, c::String, s::String; pk=nothing, pfilter=nothing) =
    cal_ire!(expr, tm, combal_context(tm), mult, ie, io, r, t, c, s, pk, pfilter)

# `cal_ire!` with the context `x` as a typed argument (see `combal_context`). GAMS: cal_ire.mod L16-41, v4.9.7.
function cal_ire!(expr::JuMP.AffExpr, tm::TimesModel, x::NamedTuple, mult::GNum, ie::String, io::String,
                  r::String, t::String, c::String, s::String, pk::PK, pfilter::PF) where {PK,PF}
    # Actual exchange (L24-28).
    if !((ie, io) in (("EXP", "OUT"), ("IMP", "IN")))
        for (_, p, _, _) in get(x.ire_of_rcie, (r, c, ie), NO4)
            pfilter === nothing || pfilter(p)::Bool || continue       # %6R,P%7
            vints = get(x.vint_of_rtp, (r, t, p), NO4)
            for (_, _, _, v) in vints, (_, _, _, _, ts) in get(x.varf_of_rtpc, (r, t, p, c), NO5)
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
    # Auxiliary flows (L35-41), over every RPC_IRE(R,P,COM,IE) of the region and RTPCS_VARF(R,T,P,COM,TS):
    # only those with an IRE_FLOSUM(R,T,P,COM,TS,IE,C,'%2') add a term, and `flosum_of_rtcio` holds
    # them for the row's (r,t,c,io), in the order of that double sum (`ire_flosum_index`).
    isempty(x.ire_flosum) && return expr
    for fs in get(x.flosum_of_rtcio, (r, t, c, io), NO_FLOSUM)
        (_, _, p, com, ts, iex, _, _) = fs
        pfilter === nothing || pfilter(p)::Bool || continue           # %6R,P%7
        vints = get(x.vint_of_rtp, (r, t, p), NO4)
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
cal_stgn!(expr::JuMP.AffExpr, tm::TimesModel, mult::GNum, io::String,
          r::String, t::String, c::String, s::String; cond, f3, f4, f6) =
    cal_stgn!(expr, tm, combal_context(tm), mult, io, r, t, c, s, cond, f3, f4, f6)

# `cal_stgn!` with the context `x` as a typed argument (see `combal_context`). GAMS: cal_stgn.mod L17-22, v4.9.7.
function cal_stgn!(expr::JuMP.AffExpr, tm::TimesModel, x::NamedTuple, mult::GNum, io::String,
                   r::String, t::String, c::String, s::String, cond::C, f3::F3, f4::F4, f6::F6) where {C,F3,F4,F6}
    io2 = io == "OUT" ? "IN" : "OUT"
    var1, var2 = "VAR_S$(io)", "VAR_S$(io2)"                    # VAR_S%1, VAR_S%2: the names once, not once per term
    for (_, p, _) in get(x.stg_of_rc, (r, c), NO3)
        (r, p, c, io) in x.top || continue                       # TOP(RPC_STG(R,P,C),'%1')
        (r, p, c, io) in x.rpc_stgn && continue                  # $(NOT RPC_STGN(R,P,C,'%1'))
        stgn2 = (r, p, c, io2) in x.rpc_stgn
        vints = get(x.vint_of_rtp, (r, t, p), NO4)
        for (_, _, _, ts) in get(x.rpcs_var_of_rpc, (r, p, c), NO4)
            cond(p, ts)::Bool || continue                        # %5
            fr = gv(x.rs_fr, (r, s, ts))
            iszero(fr) && continue
            for (_, _, _, v) in vints
                k6 = f6(p, v)::GNum
                addterm!(expr, mult * (f3(p, v)::GNum * k6 * fr), tm, var1, r, v, t, p, c, ts)
                stgn2 && addterm!(expr, mult * (-(f4(p, v)::GNum) * k6 * fr), tm, var2, r, v, t, p, c, ts)
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
combal_aggregation!(expr::JuMP.AffExpr, tm::TimesModel, mult::GNum, r::String, t::String, c::String, s::String) =
    combal_aggregation!(expr, tm, combal_context(tm), mult, r, t, c, s)

# `combal_aggregation!` with the context `x` as a typed argument (see `combal_context`). GAMS: eqcombal.mod L45-47, v4.9.7.
function combal_aggregation!(expr::JuMP.AffExpr, tm::TimesModel, x::NamedTuple, mult::GNum,
                             r::String, t::String, c::String, s::String)
    for (_, _, com, _) in get(x.agg_of_rtc, (r, t, c), NO4)
        a = gv(x.com_agg, (r, t, com, c))
        for (_, _, _, ts) in get(x.varc_of_rtc, (r, t, com), NO4)
            (r, s, ts) in x.rs_tree || continue
            k = mult * (a * (gv(x.rs_fr, (r, s, ts)) * (1 + gv(x.rtcs_fr, (r, t, com, s, ts)))))
            (r, com, "LO") in x.rc_agp && addterm!(expr, k, tm, "VAR_COMNET", r, t, com, ts)
            (r, com, "FX") in x.rc_agp && addterm!(expr, k, tm, "VAR_COMPRD", r, t, com, ts)
        end
    end
    return expr
end

"""
    combal_blend_out!(expr, tm, mult, r, t, c, s) -> expr

Blending on the production side of the balance row (r,t,c,s): the blend `c`
made by its blending streams, and the emissions `c` of blending operations.

    SUM(BLE_OPR(R,C,OPR),
        RS_FR(R,S,'ANNUAL')*(1+RTCS_FR(R,T,C,S,'ANNUAL')) * BLE_BAL(R,T,C,OPR) * VAR_BLND(R,T,C,OPR)) +
    SUM(BLE_ENV(R,C,BLE,OPR), RS_FR(R,S,'ANNUAL') * ENV_BL(R,C,BLE,OPR,T) * VAR_BLND(R,T,BLE,OPR)) +

Neither sum has BLE_TP: a blend made before its start year (BL_START) has
BLE_BAL 0 and adds no term (G5), its emissions are still counted. OPR and
BLE control the sums, so only members of those sets count.

GAMS: eqcombal.mod L30-35, v4.9.7.
"""
combal_blend_out!(expr::JuMP.AffExpr, tm::TimesModel, mult::GNum, r::String, t::String, c::String, s::String) =
    combal_blend_out!(expr, tm, combal_context(tm), mult, r, t, c, s)

# `combal_blend_out!` with the context `x` as a typed argument (see `combal_context`). GAMS: eqcombal.mod L30-35, v4.9.7.
function combal_blend_out!(expr::JuMP.AffExpr, tm::TimesModel, x::NamedTuple, mult::GNum,
                           r::String, t::String, c::String, s::String)
    for (_, _, o) in get(x.ble_opr_of_rb, (r, c), NO3)                    # L30-32
        (o,) in x.opr || continue
        k = gv(x.rs_fr, (r, s, "ANNUAL")) * (1 + gv(x.rtcs_fr, (r, t, c, s, "ANNUAL"))) * gv(x.ble_bal, (r, t, c, o))
        addterm!(expr, mult * k, tm, "VAR_BLND", r, t, c, o)
    end
    for (_, _, b, o) in get(x.ble_env_of_rc, (r, c), NO4)                 # L34-35
        ((b,) in x.ble && (o,) in x.opr) || continue
        k = gv(x.rs_fr, (r, s, "ANNUAL")) * gv(x.env_bl, (r, c, b, o, t))
        addterm!(expr, mult * k, tm, "VAR_BLND", r, t, b, o)
    end
    return expr
end

"""
    combal_blend_in!(expr, tm, mult, r, t, c, s) -> expr

Blending on the consumption side of the balance row (r,t,c,s): `c` used as
a blending stream, and `c` as another input of blending (BL_INP per unit of
blend).

    SUM(BLE_TP(R,T,BLE)\$BLE_OPR(R,BLE,C),
        RS_FR(R,S,'ANNUAL')*(1+RTCS_FR(R,T,C,S,'ANNUAL')) * VAR_BLND(R,T,BLE,C)) +
    SUM(BLE_OPR(R,BLE,OPR)\$(BLE_INP(R,BLE,C) * BLE_TP(R,T,BLE)),
        RS_FR(R,S,'ANNUAL')*(1+RTCS_FR(R,T,C,S,'ANNUAL')) * BL_INP(R,BLE,C) * VAR_BLND(R,T,BLE,OPR)) +

GAMS: eqcombal.mod L75-80, v4.9.7.
"""
combal_blend_in!(expr::JuMP.AffExpr, tm::TimesModel, mult::GNum, r::String, t::String, c::String, s::String) =
    combal_blend_in!(expr, tm, combal_context(tm), mult, r, t, c, s)

# `combal_blend_in!` with the context `x` as a typed argument (see `combal_context`). GAMS: eqcombal.mod L75-80, v4.9.7.
function combal_blend_in!(expr::JuMP.AffExpr, tm::TimesModel, x::NamedTuple, mult::GNum,
                          r::String, t::String, c::String, s::String)
    isempty(x.ble_tp) && return expr
    fr = gv(x.rs_fr, (r, s, "ANNUAL")) * (1 + gv(x.rtcs_fr, (r, t, c, s, "ANNUAL")))
    for (_, _, b) in get(x.ble_tp_of_rt, (r, t), NO3)                     # L76-77
        ((b,) in x.ble && (r, b, c) in x.ble_opr) || continue
        addterm!(expr, mult * fr, tm, "VAR_BLND", r, t, b, c)
    end
    for (_, b, _) in get(x.ble_inp_of_rc, (r, c), NO3)                    # L78-80
        (r, t, b) in x.ble_tp || continue
        k = fr * gv(x.bl_inp, (r, b, c))
        for (_, _, o) in get(x.ble_opr_of_rb, (r, b), NO3)
            ((b,) in x.ble && (o,) in x.opr) || continue
            addterm!(expr, mult * k, tm, "VAR_BLND", r, t, b, o)
        end
    end
    return expr
end

"""
    eq_combal!(tm::TimesModel) -> Int

Generate every EQG_COMBAL, EQE_COMBAL and EQE_COMPRD row (eqmain.mod
L98-106) from `tm.data`. Returns the number of rows generated.

GAMS: eqcombal.mod L19-113, v4.9.7, with cal_fflo.mod L15-33,
cal_ire.mod L16-41 and cal_stgn.mod L17-22; blending L30-35 and L75-80.
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
      ( ([cal_fflo OUT] + [blending L30-35] + [cal_ire IMP OUT IE] + [cal_stgn OUT IN] + [aggregation]) * COM_IE(R,T,C,S)
      )\$(NOT RHS_COMPRD(R,T,C,S)) + VAR_COMPRD(R,T,C,S)\$RHS_COMPRD(R,T,C,S)   [BAL; PRD: no \$/VAR_COMPRD]
      - ([cal_fflo IN] + [blending L75-80] + [cal_ire EXP IN IE] + [cal_stgn IN OUT])  [BAL only]
      =%2=
      PRD: VAR_COMPRD(R,T,C,S)\$RHS_COMPRD(R,T,C,S)
      BAL: [VAR_COMNET(R,T,C,S)\$RHS_COMBAL(R,T,C,S) +   (FX only)]
           ((COM_PROJ(R,T,C)\$(NOT RD_NLP(R,C)) +
             SUM(MI_DMAS(RD_AGG(R,COM),C), RD_SHAR(R,T,COM,C)*VAR_COMPRD(R,T,COM,'ANNUAL'))
            ) * COM_FR(R,T,C,S))\$DEM(R,C);

GAMS: eqcombal.mod L19-113, v4.9.7.
"""
eq_combal!(tm::TimesModel, eqtype::String, lim::String, kind::String) =
    eq_combal!(tm, combal_context(tm), eqtype, lim, kind)

# One include of eqcombal.mod with the context `x` as a typed argument (see `combal_context`): the
# closures given to `cal_stgn!` read `x.stg_eff`. GAMS: eqcombal.mod L19-113, v4.9.7.
function eq_combal!(tm::TimesModel, x::NamedTuple, eqtype::String, lim::String, kind::String)
    kind in ("BAL", "PRD") || throw(ArgumentError("kind (%4) must be BAL or PRD, got $kind"))
    name = "EQ$(eqtype)_COM$(kind)"
    rcs = gset(tm, "RCS_COM$(kind)")
    tx = eq_periods(tm)   # %R_T%, %TX%: SUBT in a stepped run (maindrv.mod L38-40)
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
    # elastic demand (L67, L101; %TIMESED% YES, M1.3 change 69)
    ted = timesed_on(tm)
    com_elast = gparam_opt(tm.data, "COM_ELAST", 5)
    rcj_of = indexby(gset_opt(tm.data, "RCJ", 4), (1, 2))
    bdneq = Set(k[1] for k in gset(tm, "BDNEQ").keys)
    pref, agc = gparam_opt(tm.data, "DDF_PREF", 3), gparam_opt(tm.data, "MI_AGC", 6)
    dmas_by_agg = indexby(gset(tm, "MI_DMAS"), (1, 2))   # (r,c) -> MI_DMAS(r,c,com)
    varc_of = indexby(gset(tm, "RTCS_VARC"), (1, 2, 3))

    return eq_combal!(tm, x,
        (; name, rcs, tx, rhs_comprd, rhs_combal, dem, com_proj, com_fr, rd_nlp, rd_agg, rd_shar, dmas_of_rc, nstts, prc_map, one,
           ted, com_elast, rcj_of, bdneq, pref, agc, dmas_by_agg, varc_of),
        eqtype, lim, kind)
end

# One include of eqcombal.mod with the context `x` and the sets, parameters and incidence maps of the
# method above, `d`, as typed arguments: `gset` and `gparam` give an abstract `GamsSet` or
# `GamsParam`, so that method does not know their types, nor do the closures it would hand to
# `cal_stgn!` (a function barrier; Phase 2, change 3). The rows, the terms, their arithmetic and their
# order are unchanged. GAMS: eqcombal.mod L19-113, v4.9.7.
function eq_combal!(tm::TimesModel, x::NamedTuple, d::NamedTuple, eqtype::String, lim::String, kind::String)
    (; name, rcs, tx, rhs_comprd, rhs_combal, dem, com_proj, com_fr, rd_nlp, rd_agg, rd_shar, dmas_of_rc, nstts, prc_map, one,
       ted, com_elast, rcj_of, bdneq, pref, agc, dmas_by_agg, varc_of) = d

    n = 0
    for (r, t, c, s, l) in rcs
        l == lim || continue
        (t,) in tx || continue                           # %R_T% = R,T (R,SUBT(T) in a stepped run): T controls
        kind == "PRD" && !((r, t, c, s) in rhs_comprd) && continue
        for sow in sw_rows(tm, t)                        # %SWT% (L19): SW_T(T,SOW) in a stochastic run
            set_sow!(tm, sow)

            lhs = JuMP.AffExpr(0.0)
            # Production (L23-58).
            if kind == "BAL" && (r, t, c, s) in rhs_comprd
                addterm!(lhs, GNum(1.0), tm, "VAR_COMPRD", r, t, c, s)
            else
                ie = gv(x.com_ie, (r, t, c, s))
                cal_fflo!(lhs, tm, ie, "OUT", r, t, c, s)
                combal_blend_out!(lhs, tm, ie, r, t, c, s)                                    # L30-35
                cal_ire!(lhs, tm, ie, "IMP", "OUT", r, t, c, s)
                cal_stgn!(lhs, tm, ie, "OUT", r, t, c, s;                                     # L42
                          cond=(p, ts) -> !((r, p, ts) in nstts), f3=(p, v) -> gv(x.stg_eff, (r, v, p)),
                          f4=(p, v) -> one, f6=(p, v) -> one)
                combal_aggregation!(lhs, tm, ie, r, t, c, s)
                cal_cap!(lhs, tm, ie, "OUT", r, t, c, s)                                       # L51: cal_cap.mod OUT O
            end
            # L67: + SUM(RCJ(R,C,J,BDNEQ(BD))$COM_ELAST(R,T,C,S,BD),BDSIG(BD)*VAR_ELAST(R,T,C,S,J,BD)), BAL only
            if ted && kind == "BAL"
                for (_, _, j, b) in get(rcj_of, (r, c), NO4)
                    (b in bdneq && !iszero(gv(com_elast, (r, t, c, s, b)))) || continue
                    addterm!(lhs, GNum(bdsig(b)), tm, "VAR_ELAST", r, t, c, s, j, b)
                end
            end
            # Consumption (L69-93), BAL only.
            if kind == "BAL"
                cal_fflo!(lhs, tm, GNum(-1.0), "IN", r, t, c, s)
                combal_blend_in!(lhs, tm, GNum(-1.0), r, t, c, s)                             # L75-80
                cal_ire!(lhs, tm, GNum(-1.0), "EXP", "IN", r, t, c, s)
                ireaux!(lhs, tm, -gv(x.com_ie, (r, t, c, s)), r, t, c, s)                    # L84: cal_ire.mod L30, IREAUXIN
                cal_stgn!(lhs, tm, GNum(-1.0), "IN", r, t, c, s;                              # L87
                          cond=(p, ts) -> !((r, "NST", p) in prc_map) || (r, p, ts) in nstts,
                          f3=(p, v) -> one, f4=(p, v) -> gv(x.stg_eff, (r, v, p)), f6=(p, v) -> one)
                cal_cap!(lhs, tm, GNum(-1.0), "IN", r, t, c, s)                                # L91: cal_cap.mod IN I
            end

            rhs = JuMP.AffExpr(0.0)
            if kind == "PRD"
                addterm!(rhs, GNum(1.0), tm, "VAR_COMPRD", r, t, c, s)    # L100, row exists only under RHS_COMPRD
                # L101: +(SUM(RCJ(R,COM,J,BD)$MI_DMAS(R,C,COM),(DDF_PREF(R,T,COM)*(MI_AGC(R,T,C,COM,J,BD)-1)+RD_SHAR(R,T,COM,C))*
                #   BDSIG(BD)*SUM(RTCS_VARC(R,T,COM,TS),VAR_ELAST(R,T,COM,TS,J,BD)))-VAR_COMPRD(R,T,C,S))$(COM_ELAST(R,T,C,S,'N')>0)$RD_AGG(R,C)
                if ted && gv(com_elast, (r, t, c, s, "N")).v > 0 && (r, c) in rd_agg
                    for (_, _, com) in get(dmas_by_agg, (r, c), NO3), (_, _, j, b) in get(rcj_of, (r, com), NO4)
                        k = (gv(pref, (r, t, com)) * (gv(agc, (r, t, c, com, j, b)) - one) + gv(rd_shar, (r, t, com, c))) * GNum(bdsig(b))
                        for (_, _, _, ts) in get(varc_of, (r, t, com), NO4)
                            addterm!(rhs, k, tm, "VAR_ELAST", r, t, com, ts, j, b)
                        end
                    end
                    addterm!(rhs, GNum(-1.0), tm, "VAR_COMPRD", r, t, c, s)
                end
            else
                if lim == "FX" && (r, t, c, s) in rhs_combal              # L106
                    addterm!(rhs, GNum(1.0), tm, "VAR_COMNET", r, t, c, s)
                end
                if (r, c) in dem                                          # L110
                    fr = gv(com_fr, (r, t, c, s))
                    haskey(rd_nlp, (r, c)) || addconst!(rhs, gv(com_proj, (r, t, c)) * fr)
                    for (_, com, _) in get(dmas_of_rc, (r, c), NO3)
                        (r, com) in rd_agg || continue
                        addterm!(rhs, gv(rd_shar, (r, t, com, c)) * fr, tm, "VAR_COMPRD", r, t, com, "ANNUAL")
                    end
                end
            end

            gconstraint!(tm, eqtag(tm, name), swt(tm, (r, t, c, s), t), eqtype, lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end

"""
    cal_cap!(expr, tm, mult, io, r, t, c, s; pf=p -> GNum(1.0)) -> expr

cal_cap.mod, the capacity-related flows of commodity C in EQ(l)_COMBAL (eqcombal.mod L51 with
`OUT O`, L91 with `IN I`) and EQ_PEAK (eqpeak.mod L72, `IN I` with %3 = `1\$(NOT PRC_PKNO(R,P))*`,
`pf`); `mult` is the caller's factor (COM_IE on the production side, -1 on consumption):

    SUM(RTP_CPTYR(R,V,T,P)\$NCAP_COM(R,V,P,C,'%1'),
        COEF_CPT(R,V,T,P) * NCAP_COM(R,V,P,C,'%1') * G_YRFR(R,S) * %3
        (VAR_NCAP(R,V,P)\$T(V) + NCAP_PASTI(R,V,P)\$PYR(V) %RCAPSUB%) * (1 + COEF_CIO(R,V,T,P,C,'%1'))) +
    SUM(RPC_CAPFLO(R,V(LL),P,C)\$COEF_%2COM(R,V,T,P,C), G_YRFR(R,S) * %3
        (COEF_%2COM(R,V,T,P,C)*(VAR_NCAP(R,V,P)\$T(V)+NCAP_PASTI(R,V,P)\$PYR(V)) +
         SUM(VNTRT(V,T),COEF_%2COM(R,V,T,P,C)*SUM(TT(LL+MIN(VN2T(V,T),RVPRL(R,V,P))),-VAR_SCAP(R,V,TT,P)) +
             VAR_RCAP(R,V,T,P)*COEF_RCOM(R,V,T,P,C))\$((IPS('%1')->0)\$RCAP_OCAP(R,V,P,C))))

The first sum is the flows over the lifetime of the capacity (NCAP_COM, M1.3 change 54), shaped or
lagged by COEF_CIO; %RCAPSUB% takes off the capacity retired early (`rcapsub!`). The second is the
flows tied to investment (IN: COEF_ICOM) or decommissioning (OUT: COEF_OCOM; change 53), and, on the
OUT side only (`IPS('OUT')` is false, so `->0` holds), those of early retirements (RCAP_OCAP): the
release of the retired capacity in the period it retires, VAR_SCAP at the milestone MIN(VN2T,RVPRL)
positions after V along ALLYEAR (V(LL) binds LL to V), and VAR_RCAP times COEF_RCOM. V(LL) is
MODLYEAR; PYR the past years.

GAMS: cal_cap.mod L14-27, v4.9.7.
"""
cal_cap!(expr::JuMP.AffExpr, tm::TimesModel, mult::GNum, io::String, r, t, c, s; pf=p -> GNum(1.0)) =
    cal_cap!(expr, tm, cal_cap_context(tm), mult, io, r, t, c, s, pf)

"The sets and parameters `cal_cap!` reads, built once per model (untyped out of `tm.cache`, see `combal_context`)."
function cal_cap_context(tm::TimesModel)
    get!(tm.cache, "CAL_CAP") do
        ncom = gparam(tm, "NCAP_COM")
        allyear = [k[1] for k in gset(tm, "ALLYEAR").keys]
        (capflo_of_rc = indexby(gset(tm, "RPC_CAPFLO"), (1, 4)),           # (r,c) -> RPC_CAPFLO(r,v,p,c)
         ncom = ncom, ncom_of_rc = indexby(ncom, (1, 4)),                  # (r,c) -> NCAP_COM(r,v,p,c,io)
         cptyr = gset(tm, "RTP_CPTYR"), coef_cpt = gparam(tm, "COEF_CPT"), coef_cio = gparam(tm, "COEF_CIO"),
         icom = gparam(tm, "COEF_ICOM"), ocom = gparam(tm, "COEF_OCOM"), rcom = gparam(tm, "COEF_RCOM"),
         rcap_ocap = gparam(tm, "RCAP_OCAP"), vntrt = gset_opt(tm.data, "VNTRT", 2), vn2t = gparam_opt(tm.data, "VN2T", 2),
         rvprl = gparam_opt(tm.data, "RVPRL", 3), allyear = allyear, ord = Dict(y => i for (i, y) in enumerate(allyear)),
         g_yrfr = gparam(tm, "G_YRFR"), pasti = gparam(tm, "NCAP_PASTI"),
         modlyear = gset(tm, "MODLYEAR"), milestonyr = gset(tm, "MILESTONYR"), pyr = gset(tm, "PYR"))
    end
end

# `cal_cap!` with the context `x` as a typed argument (a function barrier, see `combal_context`; Phase 2,
# change 3) and %3, `pf`, as a type parameter. GAMS: cal_cap.mod L14-27, v4.9.7.
function cal_cap!(expr::JuMP.AffExpr, tm::TimesModel, x::NamedTuple, mult::GNum, io::String, r, t, c, s, pf::PF) where {PF}
    yrfr = gv(x.g_yrfr, (r, s))
    # first term: the flows over the lifetime (NCAP_COM)
    for (_, v, p, _, i) in get(x.ncom_of_rc, (r, c), NO5)
        (i == io && (r, v, t, p) in x.cptyr) || continue
        k = mult * (gv(x.coef_cpt, (r, v, t, p)) * gv(x.ncom, (r, v, p, c, io)) * yrfr * pf(p)) *
            (1 + gv(x.coef_cio, (r, v, t, p, c, io)))
        (v,) in x.milestonyr && addterm!(expr, k, tm, "VAR_NCAP", r, v, p; at=v)   # %VARV% (L18)
        (v,) in x.pyr && addconst!(expr, k * gv(x.pasti, (r, v, p)))
        rcapsub!(expr, k, tm, r, v, t, p)                                   # %RCAPSUB%
    end
    # second term: the flows tied to investment or decommissioning
    coef = io == "IN" ? x.icom : x.ocom
    for (_, v, p, _) in get(x.capflo_of_rc, (r, c), NO4)
        (v,) in x.modlyear || continue
        haskey(coef.values, (r, v, t, p, c)) || continue                    # $COEF_%2COM(R,V,T,P,C)
        k = mult * (yrfr * pf(p))
        kc = k * gv(coef, (r, v, t, p, c))
        (v,) in x.milestonyr && addterm!(expr, kc, tm, "VAR_NCAP", r, v, p; at=v)  # %VARV% (L24)
        (v,) in x.pyr && addconst!(expr, kc * gv(x.pasti, (r, v, p)))
        if io == "OUT" && haskey(x.rcap_ocap.values, (r, v, p, c)) && (v, t) in x.vntrt
            n = gmin(gv(x.vn2t, (v, t)), gv(x.rvprl, (r, v, p)))
            i = x.ord[v] + glead(n.v)                                      # TT(LL+MIN(VN2T(V,T),RVPRL(R,V,P)))
            if 1 <= i <= length(x.allyear) && (x.allyear[i],) in x.milestonyr
                addterm!(expr, -kc, tm, "VAR_SCAP", r, v, x.allyear[i], p; at=x.allyear[i])   # %VARTT% (L25)
            end
            addterm!(expr, k * gv(x.rcom, (r, v, t, p, c)), tm, "VAR_RCAP", r, v, t, p; at=t)  # %VART% (L26)
        end
    end
    return expr
end
