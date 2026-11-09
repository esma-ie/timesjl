# Records that a later coefficient file overwrites, left out of the layer-1
# comparison of a translated file until that later file is translated too
# (docs/m12-plan.md, "Parity"). Each predicate copies the later statement's
# domain from its source; the state it reads (RPG_1ACE, RPC_PG, RPCS_VAR,
# ...) is not changed by any coefficient file before that statement.

"""
    later_overwrites(tm; after="coef_shp") -> Dict{String,Function}

Per symbol, a predicate on a record's key: true when a coefficient file run
after `after` (the last file that has run on `tm`, in coefmain.mod order)
assigns that record, so the coef dump holds the later value. A file's layer-1
check leaves those records out; the later file's own check compares them.

- COEF_CPT at the PYR_S vintages of processes with a positive PRC_RESID
  (coef_ext.vda L21-27).
- COEF_CPT at the (R,V,P) with a capacity shape NCAP_CPX that coef_shp.mod
  L52 keeps (|NCAP_CPX - Z| <= Z - 1.5, Z = CARD(J)/2 + 1), which L73
  rescales, when `after` comes before coef_shp (coef_cpt to coef_alt).
- RTP_CAPYR everywhere (coef_ext.vda L76 clears it) and RTP_FFCX where
  coef_ext.vda L68-69 rewrite it: the activity-group rows (ACTCG) of
  processes with a reduced flow, and the (CG,C) rows that RP_DCGG names
  (L67: C an activity flow, CG a group of a TRACKPC commodity; L66 needs
  RPCG_PTRAN, which coef_ptr! refuses).
- COEF_PTRAN(RTP(R,V,P),CG,C,COM,S) for RPCS_VAR(R,P,C,S), RPC_PG(R,P,COM)
  and RP_CGC(R,P,CG,C), where RP_CGC gains RPG_1ACE and loses the flows in
  TRACKPC (coef_ext.vda L60-62, L71-72).
- ACT_FLO(RTP(R,V,P),C,S) for RPCS_VAR(R,P,C,S) and TRACKPC(R,P,C)
  (coef_ext.vda L63).
- RPCC_FFUNC(R,P,CG,COM) for RP_GRP(R,P,CG) (`OPTION RP_GRP < RP_CGC`, the
  group position, G26) and RPC_PG(R,P,COM) (coef_ext.vda L74).
- the scratch Z, which coef_ext.vda L23 sets in its PRC_RCAP loop when a
  refitted process has a positive PRC_RESID at a milestone (M1.3 change 25-5).
- COEF_PVT(R,T) where coef_obj.mod left it zero: FPD(T) (coef_ext.vda L81);
  and OBJ_PVT, COEF_PVT everywhere when `%CTST%` is `**EPS` (coef_alt.lin
  L47, LINFLO).

GAMS: coef_ext.vda L21-27, L60-76, L81; coef_alt.lin L42-47; coef_shp.mod L51-52, L73, v4.9.7.
"""
function later_overwrites(tm; after::AbstractString="coef_shp")
    order = ("coef_cpt", "coef_nio", "coef_ptr", "coef_obj", "coef_alt", "coef_shp", "coef_ext")
    k_after = findfirst(==(after), order)
    k_after === nothing && throw(ArgumentError("after = \"$after\": not a coefficient file ($(join(order, ", ")))"))
    after == "coef_ext" && return Dict{String,Function}()       # the last file: nothing comes later
    # coef_shp.mod L51-52: the NCAP_CPX that survive the clean-up; L73 rescales their COEF_CPT
    cpx = if k_after < findfirst(==("coef_shp"), order)
        z = length(gset(tm, "J").keys) / 2 + 1
        Set((k[1], k[2], k[3]) for (k, x) in gparam_opt(tm.data, "NCAP_CPX", 3).values if abs(x - z) <= z - 1.5)
    else
        Set{NTuple{3,String}}()
    end
    pyr = Set(k[1] for k in gset(tm, "PYR_S").keys)
    resid = Set((r, p) for ((r, t, p), v) in gparam(tm, "PRC_RESID").values if v > 0)
    # coef_ext.vda L21-23: TRACKP from PRC_RESID > 0 at the milestones; LOOP(PYR_S, LOOP(PRC_RCAP(TRACKP(R,P)), Z = ...))
    tmem = Set(k[1] for k in gset(tm, "MILESTONYR").keys)
    trackp_resid = Set((r, p) for ((r, t, p), v) in gparam(tm, "PRC_RESID").values if v > 0 && t in tmem)
    z_later = !isempty(pyr) && any(k -> k in trackp_resid, gset_opt(tm.data, "PRC_RCAP", 2).keys)

    # coef_ext.vda L60: RP_CGC(RPG_1ACE) = YES; OPTION TRACKPC < RPG_1ACE (positions 1, 2, 4)
    rpg_1ace = gset_opt(tm.data, "RPG_1ACE", 4)
    rp_cgc = union(Set(gset_opt(tm.data, "RP_CGC", 4).keys), rpg_1ace.keys)
    # L62: TRACKPC(TRACKPC) = RPC_FFUNC(TRACKPC)
    rpc_ffunc = gset_opt(tm.data, "RPC_FFUNC", 3)
    trackpc = Set((k[1], k[2], k[4]) for k in rpg_1ace.keys if (k[1], k[2], k[4]) in rpc_ffunc)
    # L71: RP_CGC(R,P,CG,C)$TRACKPC(R,P,C) = NO
    filter!(k -> !((k[1], k[2], k[4]) in trackpc), rp_cgc)
    # L74: OPTION RP_GRP < RP_CGC
    rp_grp = Set((k[1], k[2], k[3]) for k in rp_cgc)

    rtp, rpcs_var, rpc_pg = gset(tm, "RTP"), gset(tm, "RPCS_VAR"), gset(tm, "RPC_PG")
    modlyear, com = gset(tm, "MODLYEAR"), gset(tm, "COM")
    rtpv(r, v, p) = (v,) in modlyear && (r, v, p) in rtp
    actcg = Set(k[1] for k in gset(tm, "ACTCG").keys)
    rpc_act = gset_opt(tm.data, "RPC_ACT", 3)
    # coef_ext.vda L67: RP_DCGG(TRACKPC(RP,COM),CG,C,'UP')$(RP_CGC(RP,CG,COM)$RPC_ACT(RP,C)) $= CG_GRP(RP,CG,C)
    dcgg_cg = Set((k[1], k[2], k[3]) for k in rp_cgc if (k[1], k[2], k[4]) in trackpc)      # (R,P,CG)
    coef_pvt = gparam_opt(tm.data, "COEF_PVT", 2)
    linflo = ctst(tm) == "**EPS"
    return Dict{String,Function}(
        "COEF_CPT" => k -> (k[2] in pyr && (k[1], k[4]) in resid) || (k[1], k[2], k[4]) in cpx,
        "RTP_CAPYR" => k -> true,
        "Z" => k -> z_later,
        "RTP_FFCX" => k -> (k[5] in actcg && (k[1], k[4], k[6]) in rpc_ffunc) ||
                           ((k[1], k[4], k[5]) in dcgg_cg && (k[1], k[4], k[6]) in rpc_act),
        "COEF_PVT" => k -> linflo || !haskey(coef_pvt, k),
        "OBJ_PVT" => k -> linflo,
        "COEF_PTRAN" => k -> (k[1], k[3], k[4], k[5]) in rp_cgc && (k[1], k[3], k[6]) in rpc_pg &&
                             (k[1], k[3], k[5], k[7]) in rpcs_var && rtpv(k[1], k[2], k[3]),
        "ACT_FLO" => k -> (k[1], k[3], k[4]) in trackpc && (k[1], k[3], k[4], k[5]) in rpcs_var &&
                          rtpv(k[1], k[2], k[3]),
        "RPCC_FFUNC" => k -> (k[1], k[2], k[3]) in rp_grp && (k[4],) in com && (k[1], k[2], k[4]) in rpc_pg)
end
