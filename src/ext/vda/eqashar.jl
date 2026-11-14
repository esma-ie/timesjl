# EQE_ASHAR / EQL_ASHAR / EQG_ASHAR (VDA extension): ANNUAL-level ("advanced")
# share constraints. The flows of a commodity group CG are bounded by a share
# of the flows of a reference group CG2 (or of the activity, CG2 = 'ACT').
#
# GAMS: eqashar.vda L38-78 (the EQDEF label), v4.9.7, included from
# equ_ext.vda L94-96 as
#   $BATINCLUDE eqashar.mod E FX
#   $BATINCLUDE eqashar.mod L LO
#   $BATINCLUDE eqashar.mod G UP
# (%1 = equation type, %2 = bound type); declared equ_ext.vda L25-27
# (R,ALLYEAR,ALLYEAR,P,CG,COM_GRP,S); in the model through mod_ext.vda
# L29-31. The share multiplies the reference group, which is on the left, so
# EQL_ASHAR is the LO bound (share*CG2 =L= CG) and EQG_ASHAR the UP bound.
# The preprocessing part (L16-33: RPCG_ASHAR, RP_PGFLO additions, levelling
# FLO_ASHAR) is `eqashar_prep!` below, which coef_ext! calls (coef_ext.vda
# L79, the include with no arguments).
#
# Macro expansions: %EQ% -> EQ, %VAR% -> VAR, %SOW%/%SWT% -> '' (setglobs.gms
# L348); %R_V_T% -> 'R,V,T' (maindrv.mod L39); RTS(S) -> S; %cal_red% is
# cal_nored.red (cal_red.jl) with mode ''. V = MODLYEAR, T = MILESTONYR.
# ACTCG = {'ACT'} (initmty.mod L140, %PGPRIM% = ACT).

"""
    eqashar_prep!(tm) -> tm

The preprocessing of the "advanced" flow shares, on the GAMS state in `tm`
at the coefficient stage. FLO_ASHAR is an internal parameter (init_ext.vda
L43-44): it holds the FLO_SHAR records that prep_ext.vda L78 and
pp_prelv.vda L96 moved (the commodity is not in the group or not a flow of
the process; the process is an exchange or storage process).

- L16-17: CG_GRP is FLO_ASHAR's (R,P,C,CG); each group gets an EPS
  FLO_SHAR(R,'0',P,C,CG,ANNUAL,'LO').
- L21-23: a commodity against itself, with the commodity a flow of the
  process (RPC): RPCG_ASHAR(R,P,C,<type of C>,S) = -1 at every S whose
  STOAL equals PRC_SGL(R,P); the FLO_ASHAR records of every diagonal are
  copied to (C, <type of C>) at the RTP vintages and the diagonal is
  deleted; the RPC diagonals leave CG_GRP.
- L24: an RP_FLO process without an activity variable (NO_ACT) with a share
  against the activity joins RP_PGFLO.
- L25-26: RPCG_ASHAR = 1 at the RPCS_VAR timeslices of C; for a storage
  flow against the activity it is RPS_STG(RP,S) + PRC_TSL(RP,'ANNUAL')\$ANNUAL(S)
  at every S (a plain assignment, so 0 removes the L25 value).
- L27-30: for the groups whose first index is not a flow of the process:
  RPCG_ASHAR = 1 at the timeslices of each COM_TSL level of the commodity,
  or at ANNUAL when it has none.
- L31: CG_GRP cleared.
- L33: `\$BATINCLUDE pp_lvlfc.mod FLO_ASHAR P RPS_S2 ',BD' ",''" ALL_TS V 1 0 ',C,CG' N`:
  the rows with a value below ANNUAL are flagged with a 1 at
  (R,'0',...,ANNUAL,BD), levelled to the RPS_S2 timeslices of the process
  (aggregation and inheritance, unweighted) and taken off the other
  timeslices at every year; rows with ANNUAL values only stay as given.
  UNCD7 keeps the levelled rows, (R,V,P,C,CG,BD,''). The scratch Z (L28-30)
  and TS_ARRAY are left as GAMS leaves them.

With no FLO_ASHAR nothing is assigned: CG_GRP stays empty and pp_lvlfc.mod
L19 clears UNCD7.

GAMS: eqashar.vda L16-33 (coef_ext.vda L79) with pp_lvlfc.mod L19-45, v4.9.7.
"""
function eqashar_prep!(tm)
    flo_ashar = gvalues(tm, "FLO_ASHAR", 7)
    if isempty(flo_ashar)
        haskey(tm.data.dump.symbols, "UNCD7") && gput!(tm, "UNCD7", Set{NTuple{7,String}}())
        return tm
    end
    tr = TsTree(tm)
    member(s) = Set(k[1] for k in gset(tm, s).keys)
    com, comtype, actcg, modl = member("COM"), member("COM_TYPE"), member("ACTCG"), member("MODLYEAR")
    rpc, rtp = gset(tm, "RPC").members, gset(tm, "RTP").members
    # L16: OPTION CG_GRP <= FLO_ASHAR
    cg_grp = Set{NTuple{4,String}}((k[1], k[3], k[4], k[5]) for k in keys(flo_ashar))
    # L17: FLO_SHAR(R,'0',P,C,CG,ANNUAL,'LO')$CG_GRP(R,P,C,CG) = EPS
    flo_shar = gvalues(tm, "FLO_SHAR", 7)
    for (r, p, c, cg) in cg_grp
        (r in tr.reg && c in com) || continue
        foreach(a -> gassign!(flo_shar, (r, "0", p, c, cg, a, "LO"), GEPS), tr.annual)
    end
    gput!(tm, "FLO_SHAR", flo_shar)

    # L20: IF(CARD(CG_GRP), ...   (CG_GRP is not empty here)
    rpcg = gvalues(tm, "RPCG_ASHAR", 5)
    tmap = Dict{NTuple{2,String},Vector{String}}()                       # (R,C) => COM_TYPE of C
    foreach(k -> k[2] in comtype && pushat!(tmap, (k[1], k[3]), k[2]), gset(tm, "COM_TMAP").keys)
    nostr = String[]
    # L21: LOOP((CG_GRP(RPC(R,P,C),C),COM_TMAP(R,COM_TYPE(CG),C)),RPCG_ASHAR(R,P,C,CG,S)$(PRC_SGL(R,P)=STOAL(R,S))=-1)
    prc_sgl, stoal = gparam_opt(tm.data, "PRC_SGL", 2), gparam(tm, "STOAL")
    for (r, p, c, cg) in cg_grp
        (c == cg && (r, p, c) in rpc) || continue
        for ct in get(tmap, (r, c), nostr), s in tr.all_ts
            gv(prc_sgl, (r, p)).v == gv(stoal, (r, s)).v && (rpcg[(r, p, c, ct, s)] = -1.0)
        end
    end
    # L22: FLO_ASHAR(RTP(R,V,P),C,COM_TYPE(CG),S,BD)$COM_TMAP(R,COM_TYPE,C) $= FLO_ASHAR(R,V,P,C,C,S,BD)
    put = Pair{NTuple{7,String},Float64}[]
    for ((r, v, p, c, c2, s, b), x) in flo_ashar
        (c == c2 && c in com && v in modl && (r, v, p) in rtp) || continue
        foreach(ct -> push!(put, (r, v, p, c, ct, s, b) => x), get(tmap, (r, c), nostr))
    end
    foreach(((k, x),) -> (flo_ashar[k] = x), put)
    # L23: FLO_ASHAR(R,LL,P,C,C,S,BD) = 0; CG_GRP(RPC(RP,C),C) = NO
    filter!(kv -> !(kv[1][4] == kv[1][5] && kv[1][4] in com && kv[1][1] in tr.reg), flo_ashar)
    filter!(k -> !(k[3] == k[4] && (k[1], k[2], k[3]) in rpc), cg_grp)
    # L24: RP_PGFLO(RP_FLO(RP)) $= SUM(CG_GRP(NO_ACT(RP),C,ACTCG),1)
    rp_flo, no_act = gset(tm, "RP_FLO").members, gset_opt(tm.data, "NO_ACT", 2).members
    rp_pgflo = gmembers(tm, "RP_PGFLO", 2)
    for (r, p, c, cg) in cg_grp
        (c in com && cg in actcg && (r, p) in no_act && (r, p) in rp_flo) && push!(rp_pgflo, (r, p))
    end
    gput!(tm, "RP_PGFLO", rp_pgflo)
    # L25: RPCG_ASHAR(CG_GRP(RPC,CG),S) $= RPCS_VAR(RPC,S)
    rpcs = Dict{NTuple{3,String},Vector{String}}()
    foreach(k -> pushat!(rpcs, (k[1], k[2], k[3]), k[4]), gset(tm, "RPCS_VAR").keys)
    for (r, p, c, cg) in cg_grp
        (r, p, c) in rpc || continue
        foreach(s -> (rpcg[(r, p, c, cg, s)] = 1.0), get(rpcs, (r, p, c), nostr))
    end
    # L26: RPCG_ASHAR(CG_GRP(RPC_STG(RP,C),ACTCG),S) = RPS_STG(RP,S)+PRC_TSL(RP,'ANNUAL')$ANNUAL(S)
    rpc_stg, rps_stg = gset_opt(tm.data, "RPC_STG", 3).members, gset_opt(tm.data, "RPS_STG", 3).members
    prc_tsl = gset(tm, "PRC_TSL").members
    for (r, p, c, cg) in cg_grp
        ((r, p, c) in rpc_stg && cg in actcg) || continue
        for s in tr.all_ts
            x = ((r, p, s) in rps_stg) + ((r, p, "ANNUAL") in prc_tsl && s in tr.annual)
            gassign!(rpcg, (r, p, c, cg, s), GNum(Float64(x)))
        end
    end
    # L27: CG_GRP(RPC,CG) = NO
    filter!(k -> !((k[1], k[2], k[3]) in rpc), cg_grp)
    # L28-30: LOOP(CG_GRP(R,P,CG,CG2), Z=1; LOOP(COM_TSL(R,C(CG),TSL), Z=0; RPCG_ASHAR(R,P,CG,CG2,S)$TS_GROUP(R,TSL,S) = 1);
    #           IF(Z, RPCG_ASHAR(R,P,CG,CG2,ANNUAL) = YES))
    com_tsl = Dict{NTuple{2,String},Vector{String}}()                    # (R,C) => TSL
    foreach(k -> pushat!(com_tsl, (k[1], k[2]), k[3]), gset(tm, "COM_TSL").keys)
    for (r, p, cg, cg2) in gams_sort!(collect(cg_grp), tm.data)          # LOOP order: the scratch Z is the last pass's
        r in tr.reg || continue
        lvls = cg in com ? get(com_tsl, (r, cg), nostr) : nostr
        for tsl in lvls, s in get(tr.group, (r, tsl), nostr)
            rpcg[(r, p, cg, cg2, s)] = 1.0
        end
        isempty(lvls) && foreach(a -> (rpcg[(r, p, cg, cg2, a)] = 1.0), tr.annual)
        gput_scalar!(tm, "Z", isempty(lvls) ? 1.0 : 0.0)
    end
    # L31: OPTION CLEAR=CG_GRP
    gput!(tm, "CG_GRP", Set{NTuple{4,String}}())
    gput!(tm, "RPCG_ASHAR", rpcg)
    gput!(tm, "FLO_ASHAR", flo_ashar)

    # L33: $BATINCLUDE pp_lvlfc.mod FLO_ASHAR P RPS_S2 ',BD' ",''" ALL_TS V 1 0 ',C,CG' N
    s2 = Dict{NTuple{2,String},Vector{String}}()                         # (R,P) => RPS_S2 timeslices
    foreach(k -> pushat!(s2, (k[1], k[2]), k[3]), gset(tm, "RPS_S2").keys)
    prc, cgs, bd = member("PRC"), member("COM_GRP"), member("BD")
    uncd7, ts_array = pp_lvlfc!(tm, tr, "FLO_ASHAR", 7; sp=6, years=modl,
                                keyok=k -> k[3] in prc && k[4] in com && k[5] in cgs && k[7] in bd,
                                targets=k -> get(s2, (k[1], k[3]), nostr), qual=k -> true, p11="N")
    # the scratch TS_ARRAY, as the last levelled row leaves it
    ts_array === nothing || gput!(tm, "TS_ARRAY", Dict{Tuple{String},Float64}((s,) => v for (s, v) in ts_array))
    # %5 is ",''": the seventh UNCD7 index is the empty label (init_ext.vda L78-87 names it; a
    # dump holds it only when a record uses it, G36)
    register_uel!(tm.data, "")
    gput!(tm, "UNCD7", Set{NTuple{7,String}}(NTuple{7,String}((k[1:6]..., "")) for k in uncd7))
    return tm
end

const ASHAR_VARIANTS = (("E", "FX"), ("L", "LO"), ("G", "UP"))

"""
    eq_ashar!(tm::TimesModel) -> Int

Generate every EQE/EQL/EQG_ASHAR row. Returns the number of rows.

    EQ%1_ASHAR(RTP_VINTYR(R,V,T,P),CG,CG2,S)\$(SUM(RS_TREE(R,S,TS)\$FLO_ASHAR(R,V,P,CG,CG2,TS,'%2'),1)\$RPCG_ASHAR(R,P,CG,CG2,S)) ..
      SUM(RPS_S2(RP_FLO(R,P),SL)\$TS_MAP(R,S,SL),
          SUM(TS_ANN(SL,TS),FLO_ASHAR(R,V,P,CG,CG2,TS,'%2')) *
          (SUM((RTPCS_VARF(R,T,P,COM,TS),RS_TREE(R,SL,TS))\$COM_GMAP(R,CG2,COM),
               [cal_red COM COM1 TS P T] *
               MAX(RPCG_ASHAR(R,P,CG,CG2,S),1\$SUM(TOP(R,P,C(CG),IO),TOP(R,P,COM,IO))\$COM_TYPE(CG2)) *
               RS_FR(R,SL,TS)*(1+RTCS_FR(R,T,COM,SL,TS))) +
           SUM((PRC_TS(R,P,TS),RTP_VARA(R,T,P))\$RS_FR(R,SL,TS),
               RS_FR(R,SL,TS)*(VAR_ACT(R,V,T,P,TS)*EXP((-ABS(STG_LOSS(R,V,P,TS))/2)\$RP_STG(R,P)))\$(NOT RP_PGFLO(R,P)) +
               SUM(RPC_PG(RP_STD(R,P),COM),(VAR_ACT(R,V,T,P,TS)\$RP_PGACT(R,P)+(VAR_FLO(R,V,T,P,COM,TS)/PRC_ACTFLO(R,V,P,COM))\$(NOT RP_PGACT(R,P))) *
                   RS_FR(R,SL,TS)*(1+RTCS_FR(R,T,COM,SL,TS)))\$RP_PGFLO(R,P))\$ACTCG(CG2)))
      + SUM(ANNUAL(S),
          SUM(RPC_IRE(R,P,COM,IE)\$(COM_GMAP(R,CG,COM)*((NOT IMPEXP(CG2))+SAMEAS(IE,CG2))),
            FLO_ASHAR(R,V,P,CG,CG2,S,'%2') *
            (SUM(RTPCS_VARF(REG,T,P,C,TS)\$((COM_GMAP(REG,CG2,C)+IMPEXP(CG2))\$RPC_IRE(REG,P,C,IE)),
               VAR_IRE(REG,V,T,P,C,TS,IE)\$(NOT RPC_AIRE(REG,P,C))+(VAR_ACT(REG,V,T,P,TS)*PRC_ACTFLO(REG,V,P,C))\$RPC_AIRE(REG,P,C)) +
             SUM(PRC_TS(R,P,TS),VAR_ACT(R,V,T,P,TS))\$ACTCG(CG2)) -
            SUM(RTPCS_VARF(R,T,P,COM,TS),
               VAR_IRE(R,V,T,P,COM,TS,IE)\$(NOT RPC_AIRE(R,P,COM))+(VAR_ACT(R,V,T,P,TS)*PRC_ACTFLO(R,V,P,COM))\$RPC_AIRE(R,P,COM))))\$RP_IRE(R,P)
      =%1=
      SUM((RTPCS_VARF(R,T,P,COM,TS),COM_GMAP(R,CG,COM))\$TS_MAP(R,S,TS), [cal_red COM COM1 TS P T])\$RP_FLO(R,P) +
      SUM(PRC_TS(R,P,TS)\$TS_MAP(R,S,TS),VAR_ACT(R,V,T,P,TS)\$(NOT NO_ACT(R,P))+
          SUM(RPC_PG(NO_ACT(R,P),C),VAR_FLO(R,V,T,P,C,TS)/PRC_ACTFLO(R,V,P,C)))\$ACTCG(CG)
      + SUM((TOP(RPC_STG(R,P,C(CG)),'OUT'),RPCS_VAR(R,P,C,TS)),RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS))*
            VAR_SOUT(R,V,T,P,C,TS)/PRC_ACTFLO(R,V,P,C))\$ACTCG(CG2);

In the activity part `RS_FR(R,SL,TS)` multiplies only the non-RP_PGFLO term
(`*` binds tighter than `+`); the RP_PGFLO term carries its own. The
right-hand side's VAR_ACT has no RTP_VARA condition. The exchange branch
(L56-65) applies to the ANNUAL row only; its reference sum runs over every
region of the process (REG is not the row's R), so an import share can be
taken against the imports of all regions through the process.

GAMS: eqashar.vda L38-78 with equ_ext.vda L94-96, v4.9.7.
"""
function eq_ashar!(tm::TimesModel)
    d = tm.data
    flo_ashar = gparam_opt(d, "FLO_ASHAR", 7)                     # init_ext.vda L44
    rpcg_ashar = gparam_opt(d, "RPCG_ASHAR", 5)
    (isempty(flo_ashar) || isempty(rpcg_ashar)) && return 0
    modlyear, milestonyr = gset(tm, "MODLYEAR"), gset(tm, "MILESTONYR")
    rp_flo, rp_ire, rp_stg = gset(tm, "RP_FLO"), gset(tm, "RP_IRE"), gset(tm, "RP_STG")
    rp_pgflo, rp_pgact, rp_std = gset(tm, "RP_PGFLO"), gset(tm, "RP_PGACT"), gset(tm, "RP_STD")
    no_act = gset(tm, "NO_ACT")
    annual, impexp = gset(tm, "ANNUAL"), gset(tm, "IMPEXP")
    rpc_ire, rpc_aire, rpc_stg = gset(tm, "RPC_IRE"), gset(tm, "RPC_AIRE"), gset(tm, "RPC_STG")
    stg_loss = gparam_opt(d, "STG_LOSS", 4)
    ire_of_rp = indexby(rpc_ire, (1, 2))                         # (r,p) -> RPC_IRE(r,p,com,ie)
    varf_of_tp = indexby(gset(tm, "RTPCS_VARF"), (2, 3))        # (t,p) -> RTPCS_VARF(reg,t,p,c,ts)
    rpcs_of_rpc = indexby(gset(tm, "RPCS_VAR"), (1, 2, 3))      # (r,p,c) -> RPCS_VAR(r,p,c,ts)
    rtp_vara, ts_map, com_gmap = gset(tm, "RTP_VARA"), gset(tm, "TS_MAP"), gset(tm, "COM_GMAP")
    com_type, top = gset(tm, "COM_TYPE"), gset(tm, "TOP")
    rs_fr, rtcs_fr, prc_actflo = gparam(tm, "RS_FR"), gparam(tm, "RTCS_FR"), gparam(tm, "PRC_ACTFLO")
    tree_of_rts = indexby(gset(tm, "RS_TREE"), (1, 3))          # (r,ts) -> RS_TREE(r,s,ts)
    rs_tree = gset(tm, "RS_TREE")
    vt_of_rvp = indexby(gset(tm, "RTP_VINTYR"), (1, 2, 4))     # (r,v,p) -> RTP_VINTYR(r,v,t,p)
    s2_of_rp = indexby(gset(tm, "RPS_S2"), (1, 2))              # (r,p) -> RPS_S2(r,p,sl)
    tsann_of_s = indexby(gset(tm, "TS_ANN"), (1,))              # sl -> TS_ANN(sl,ts)
    varf_of_rtp = indexby(gset(tm, "RTPCS_VARF"), (1, 2, 3))   # (r,t,p) -> RTPCS_VARF(r,t,p,c,ts)
    ts_of_rp = indexby(gset(tm, "PRC_TS"), (1, 2))              # (r,p) -> PRC_TS(r,p,ts)
    pg_of_rp = indexby(gset(tm, "RPC_PG"), (1, 2))              # (r,p) -> RPC_PG(r,p,c)
    io_of_rpc = indexby(top, (1, 2, 3))                         # (r,p,c) -> TOP(r,p,c,io)
    no3, no4, no5 = NTuple{3,String}[], NTuple{4,String}[], NTuple{5,String}[]
    rpcg_on(k) = haskey(rpcg_ashar.values, k)                  # $RPCG_ASHAR: present (EPS counts)

    n = 0
    for (eqtype, bd) in ASHAR_VARIANTS
        name = "EQ$(eqtype)_ASHAR"
        rows = Set{NTuple{7,String}}()
        for (r, v, p, cg, cg2, ts, b) in flo_ashar.keys
            b == bd || continue
            (v,) in modlyear || continue
            for (_, s, _) in get(tree_of_rts, (r, ts), no3)      # SUM(RS_TREE(R,S,TS)$FLO_ASHAR(...,TS,'%2'),1)
                rpcg_on((r, p, cg, cg2, s)) || continue
                for (_, _, t, _) in get(vt_of_rvp, (r, v, p), no4)
                    (t,) in milestonyr && push!(rows, (r, v, t, p, cg, cg2, s))
                end
            end
        end
        rows = collect(rows)
        gams_sort!(rows, d)
        for (r, v, t, p, cg, cg2, s) in rows
            rpcg = gv(rpcg_ashar, (r, p, cg, cg2, s))
            lhs = JuMP.AffExpr(0.0)
            if (r, p) in rp_flo
                for (_, _, sl) in get(s2_of_rp, (r, p), no3)
                    (r, s, sl) in ts_map || continue
                    share = GZERO
                    for (_, ts) in get(tsann_of_s, (sl,), Tuple{String,String}[])
                        share += gv(flo_ashar, (r, v, p, cg, cg2, ts, bd))
                    end
                    # Reference-group flows.
                    for (_, _, _, com, ts) in get(varf_of_rtp, (r, t, p), no5)
                        ((r, sl, ts) in rs_tree && (r, cg2, com) in com_gmap) || continue
                        same_side = any(k -> (r, p, com, k[4]) in top, get(io_of_rpc, (r, p, cg), no4))
                        f = gmax(rpcg, gif(gif(1, same_side), (cg2,) in com_type))
                        k = share * f * gv(rs_fr, (r, sl, ts)) * (1 + gv(rtcs_fr, (r, t, com, sl, ts)))
                        cal_nored!(lhs, tm, k, r, v, t, p, com, ts)
                    end
                    # Activity as the reference (ACTCG(CG2)).
                    cg2 == "ACT" || continue
                    (r, t, p) in rtp_vara || continue
                    for (_, _, ts) in get(ts_of_rp, (r, p), no3)
                        haskey(rs_fr, (r, sl, ts)) || continue
                        if !((r, p) in rp_pgflo)
                            # EXP((-ABS(STG_LOSS(R,V,P,TS))/2)$RP_STG(R,P))
                            loss = (r, p) in rp_stg ? GNum(exp(-abs(gv(stg_loss, (r, v, p, ts)).v) / 2)) : GNum(1.0)
                            addterm!(lhs, share * gv(rs_fr, (r, sl, ts)) * loss, tm, "VAR_ACT", r, v, t, p, ts)
                        elseif (r, p) in rp_std
                            for (_, _, com) in get(pg_of_rp, (r, p), no3)
                                w = share * gv(rs_fr, (r, sl, ts)) * (1 + gv(rtcs_fr, (r, t, com, sl, ts)))
                                if (r, p) in rp_pgact
                                    addterm!(lhs, w, tm, "VAR_ACT", r, v, t, p, ts)
                                else
                                    addterm!(lhs, w / gv(prc_actflo, (r, v, p, com)), tm, "VAR_FLO", r, v, t, p, com, ts)
                                end
                            end
                        end
                    end
                end
            end
            # L56-65: the ANNUAL share of an exchange process
            if (r, p) in rp_ire && (s,) in annual
                share = gv(flo_ashar, (r, v, p, cg, cg2, s, bd))
                isimpexp = (cg2,) in impexp
                for (_, _, com, ie) in get(ire_of_rp, (r, p), no4)
                    ((r, cg, com) in com_gmap && (!isimpexp || ie == cg2)) || continue
                    for (reg, _, _, c, ts) in get(varf_of_tp, (t, p), no5)
                        (((reg, cg2, c) in com_gmap || isimpexp) && (reg, p, c, ie) in rpc_ire) || continue
                        if (reg, p, c) in rpc_aire
                            addterm!(lhs, share * gv(prc_actflo, (reg, v, p, c)), tm, "VAR_ACT", reg, v, t, p, ts)
                        else
                            addterm!(lhs, share, tm, "VAR_IRE", reg, v, t, p, c, ts, ie)
                        end
                    end
                    if cg2 == "ACT"
                        for (_, _, ts) in get(ts_of_rp, (r, p), no3)
                            addterm!(lhs, share, tm, "VAR_ACT", r, v, t, p, ts)
                        end
                    end
                    for (_, _, _, c, ts) in get(varf_of_rtp, (r, t, p), no5)
                        c == com || continue
                        if (r, p, com) in rpc_aire
                            addterm!(lhs, -gv(prc_actflo, (r, v, p, com)), tm, "VAR_ACT", r, v, t, p, ts)
                        else
                            addterm!(lhs, GNum(-1.0), tm, "VAR_IRE", r, v, t, p, com, ts, ie)
                        end
                    end
                end
            end
            rhs = JuMP.AffExpr(0.0)
            if (r, p) in rp_flo
                for (_, _, _, com, ts) in get(varf_of_rtp, (r, t, p), no5)
                    ((r, cg, com) in com_gmap && (r, s, ts) in ts_map) || continue
                    cal_nored!(rhs, tm, GNum(1.0), r, v, t, p, com, ts)
                end
            end
            if cg == "ACT"
                for (_, _, ts) in get(ts_of_rp, (r, p), no3)
                    (r, s, ts) in ts_map || continue
                    if !((r, p) in no_act)
                        addterm!(rhs, GNum(1.0), tm, "VAR_ACT", r, v, t, p, ts)
                    else
                        for (_, _, c) in get(pg_of_rp, (r, p), no3)
                            addterm!(rhs, GNum(1.0) / gv(prc_actflo, (r, v, p, c)), tm, "VAR_FLO", r, v, t, p, c, ts)
                        end
                    end
                end
            end
            # L75-76: the output of a storage process against its activity
            if cg2 == "ACT" && (r, p, cg) in rpc_stg && (r, p, cg, "OUT") in top
                for (_, _, _, ts) in get(rpcs_of_rpc, (r, p, cg), no4)
                    w = gv(rs_fr, (r, s, ts)) * (1 + gv(rtcs_fr, (r, t, cg, s, ts)))
                    addterm!(rhs, w / gv(prc_actflo, (r, v, p, cg)), tm, "VAR_SOUT", r, v, t, p, cg, ts)
                end
            end
            gconstraint!(tm, name, (r, v, t, p, cg, cg2, s), eqtype, lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end
