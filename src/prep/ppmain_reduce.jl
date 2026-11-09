# M1.3 (17a): ppmain.mod L1336-1357 with pp_reduce.red (docs/m13-plan.md):
# the reduction of model size (PRC_CAP, PRC_ACT, the emission flows
# substituted, and with %REDUCE% YES the flows substituted by the activity,
# the processes turned off, RTP_VARA), then RTPCS_VARF and RTP_VINTYR.
#
# GAMS: ppmain.mod L1336-1357, pp_reduce.red L1-188, v4.9.7.
#
# %REDUCE% NO stops pp_reduce.red after L11, any value but NO and YES
# (unset included: nothing sets a default) after L56, YES runs it all.
# Refused (UnportedError): %ETL% YES (L43, SEG), dynslite.vda (L188, with
# %DYNTS% YES and TS_OFF data) and %MACRO% YES (ppmain.mod L1354,
# ppmain.tm). Index sets: R is REG, T and TT MILESTONYR, LL and YEAR
# ALLYEAR, S and TS ALL_TS, C and COM COM, CG CG1 CG2 COM_GRP, IO IN/OUT,
# BDUPX UP/FX. `$x` is true for EPS (G3) and `NOT x` false (G25); `x NE 0`
# and `x EQ 0` take EPS as 0 (G12); `NOT a + b` is `NOT (a + b)`; `OPTION
# a < b` takes for each index of `a` the rightmost unmatched index of `b`
# with the same declared domain, `<=` the leftmost (G26, G34); the circular
# lags `LL--ORD(LL)`, `T--ORD(T)` and `S--ORD(S)` fold onto one element
# (G31), so they only mark the (R,P) pairs the loops then read.

"""
    ppmain_reduce_unported(tm) -> Vector{String}

What ppmain.mod L1336-1357 meets that is not translated.
"""
function ppmain_reduce_unported(tm)
    out = String[]
    yes(n) = uppercase(strip(gswitch(tm, n, ""))) == "YES"
    yes("REDUCE") && yes("ETL") && push!(out, "pp_reduce.red L43 (%ETL% YES: PRC_CAP of SEG)")
    (yes("DYNTS") && !isempty(gset_opt(tm.data, "TS_OFF", 4).keys)) && push!(out, "pp_reduce.red L188 (dynslite.vda REDUCE)")
    yes("MACRO") && push!(out, "ppmain.mod L1354 (%MACRO% YES: ppmain.tm)")
    return out
end

"""
    ppmain_reduce_symbols(tm) -> Vector{String}

The symbols ppmain.mod L1336-1357 settles that nothing later in the prelv
-> ppm segment changes. Left out, as ppm_ext.vda changes them (change 18):
PRC_ACT, RP_AFB, FS_EMIS, RPC_EMIS, NO_ACT, RP_XRED, RPCG_PTRAN, RPC_FFUNC,
RPCC_FFUNC, RTPS_BD, RVP, and the scratch TRACKPC, FSCK, CG_GRP, RP_CGG,
RXX, which the replay checks at L1357.
"""
ppmain_reduce_symbols(tm) = ["RTP_VARA", "PRC_CAP", "RPC_ACT", "RPC_AIRE", "RTPS_OFF", "RTCS_SING", "RHS_COMPRD", "ACT_BND", "PRC_TS2",
                             "RPC_PKC", "RPC_PKF", "RTPCS_VARF", "RTP_VINTYR", "RTPCS_OUT", "R_UC", "OBJ_ICUR", "TRACKC", "RC_IOP"]

"""
    ppmain_reduce!(tm) -> tm

ppmain.mod L1336-1357 (with pp_reduce.red) on the state after
`ppmain_blend!`.

GAMS: ppmain.mod L1336-1357, pp_reduce.red L1-188, v4.9.7.
"""
function ppmain_reduce!(tm)
    u = ppmain_reduce_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    red = uppercase(strip(gswitch(tm, "REDUCE", "")))
    reg = Set(k[1] for k in gset(tm, "REG").keys)
    tmem = Set(k[1] for k in gset(tm, "MILESTONYR").keys)
    S2 = Dict{NTuple{2,String},Vector{String}}
    by2(keys, f=k -> true) = (d = S2(); foreach(k -> f(k) && pushat!(d, (k[1], k[2]), k[3]), keys); d)
    rp = gset(tm, "RP").members
    rp_std, rp_ire = gset(tm, "RP_STD").members, gset(tm, "RP_IRE").members
    rtp = gset(tm, "RTP").members
    top = gset(tm, "TOP").members
    rpc = gset(tm, "RPC").members
    rpc_of = by2(rpc)

    # --- ppmain.mod L1339-1340 ----------------------------------------------------------------------------
    # L1339: OPTION RVP < RTP_CPTYR  (RVP(R,ALLYEAR,P) from RTP_CPTYR(R,ALLYEAR,ALLYEAR,P): the rightmost year, T)
    rvp = project(gset(tm, "RTP_CPTYR").keys, (1, 3, 4))
    # L1340: RTP_VARA(R,T,P)$(NOT RVP(R,T,P)) = NO
    vara = gmembers(tm, "RTP_VARA", 3)
    filter!(k -> !(k[1] in reg && k[2] in tmem && !(k in rvp)), vara)

    # --- pp_reduce.red L9-11 ------------------------------------------------------------------------------
    # L9: PRC_CAP(RP) = YES; L10: PRC_ACT(RP) = RP_STD(RP)+RP_IRE(RP)
    prc_cap, prc_act = gmembers(tm, "PRC_CAP", 2), gmembers(tm, "PRC_ACT", 2)
    union!(prc_cap, rp)
    foreach(k -> (k in rp_std || k in rp_ire) ? push!(prc_act, k) : delete!(prc_act, k), rp)
    # L11: OPTION RP_AFB < NCAP_AF  (NCAP_AF(REG,ALLYEAR,PRC,TS,BD)); RP_AFB is a parameter: the number of records (G31)
    rp_afb = Dict{NTuple{3,String},Float64}()
    foreach(k -> (rp_afb[(k[1], k[3], k[5])] = get(rp_afb, (k[1], k[3], k[5]), 0.0) + 1), keys(gvalues(tm, "NCAP_AF", 5)))
    trackpc, fsck = gmembers(tm, "TRACKPC", 3), gmembers(tm, "FSCK", 5)
    fs_emis, rpc_emis = gmembers(tm, "FS_EMIS", 5), gmembers(tm, "RPC_EMIS", 3)
    obj_icur, rtps_bd = gmembers(tm, "OBJ_ICUR", 4), gmembers(tm, "RTPS_BD", 5)
    rpc_act, rpc_aire, no_act = gmembers(tm, "RPC_ACT", 3), gmembers(tm, "RPC_AIRE", 3), gmembers(tm, "NO_ACT", 2)
    rp_xred, cg_grp, ptran = gmembers(tm, "RP_XRED", 2), gmembers(tm, "CG_GRP", 4), gmembers(tm, "RPCG_PTRAN", 6)
    rp_cgg, ffunc, ccffunc = gmembers(tm, "RP_CGG", 5), gmembers(tm, "RPC_FFUNC", 3), gmembers(tm, "RPCC_FFUNC", 4)
    rtps_off, rxx, sing = gmembers(tm, "RTPS_OFF", 4), gmembers(tm, "RXX", 3), gmembers(tm, "RTCS_SING", 5)
    trackc, rc_iop = gmembers(tm, "TRACKC", 2), gmembers(tm, "RC_IOP", 4)
    rhs_prd, act_bnd, rtpcs_out = gmembers(tm, "RHS_COMPRD", 4), gvalues(tm, "ACT_BND", 5), gmembers(tm, "RTPCS_OUT", 5)

    if red != "NO"
        # --- L21-42: the processes that need a capacity variable ------------------------------------------
        # L21: PRC_CAP(RP) = NO; L22: $IF DEFINED PRC_DSCNCAP PRC_CAP(PRC_DSCNCAP) = YES
        setdiff!(prc_cap, rp)
        union!(prc_cap, gset_opt(tm.data, "PRC_DSCNCAP", 2).members)
        # L23-24: LOOP((R,UC_N,P)$UC_GMAP_P(R,UC_N,'CAP'|'NCAP',P), PRC_CAP(R,P) = YES)
        foreach(k -> k[3] in ("CAP", "NCAP") && push!(prc_cap, (k[1], k[4])), gset(tm, "UC_GMAP_P").keys)
        # L25: LOOP((RTP(R,PYR,P))$NCAP_PASTI(R,PYR,P), PRC_CAP(R,P) = YES)
        pyr = Set(k[1] for k in gset(tm, "PYR").keys)
        foreach(k -> (k[2] in pyr && k in rtp) && push!(prc_cap, (k[1], k[3])), keys(gvalues(tm, "NCAP_PASTI", 3)))
        # L26-27: LOOP((RTP(R,T,P),BD)$CAP_BND|NCAP_BND(R,T,P,BD), PRC_CAP(R,P) = YES)
        for n in ("CAP_BND", "NCAP_BND")
            foreach(k -> (k[2] in tmem && k[1:3] in rtp) && push!(prc_cap, (k[1], k[3])), keys(gvalues(tm, n, 4)))
        end
        # L28-35: OBJ_ICUR(R,LL--ORD(LL),P,CUR)$DM_YEAR(LL) $= (NCAP_xxx(R,LL,P,CUR) NE 0); LL--ORD(LL) is '0' (G31)
        dm = Set(k[1] for k in gset(tm, "DM_YEAR").keys)
        lastll = gset(tm, "ALLYEAR").keys[end][1]
        for n in ("NCAP_COST", "NCAP_FOM", "NCAP_ISUB", "NCAP_ITAX", "NCAP_FSUB", "NCAP_FTAX", "NCAP_DCOST", "NCAP_DLAGC")
            foreach(((k, v),) -> (k[1] in reg && k[2] in dm && v != 0) && push!(obj_icur, (k[1], lastll, k[3], k[4])), gvalues(tm, n, 4))
        end
        # L36: LOOP(OBJ_ICUR(R,LL,P,CUR), PRC_CAP(R,P) = YES)
        foreach(k -> push!(prc_cap, (k[1], k[3])), obj_icur)
        # L38: PRC_CAP(RP(R,P)) $= RP_AFB(RP,'FX')
        foreach(k -> haskey(rp_afb, (k[1], k[2], "FX")) && push!(prc_cap, k), rp)
        # L39-40: RTPS_BD(R,T--ORD(T),P,S--ORD(S)|ANNUAL,'FX') $= NCAP_AFS(R,T,P,S,'FX') | NCAP_AFA(R,T,P,'FX')
        lastt, lasts = gset(tm, "MILESTONYR").keys[end][1], gset(tm, "ALL_TS").keys[end][1]
        foreach(k -> (k[1] in reg && k[2] in tmem && k[5] == "FX") && push!(rtps_bd, (k[1], lastt, k[3], lasts, "FX")), keys(gvalues(tm, "NCAP_AFS", 5)))
        for k in keys(gvalues(tm, "NCAP_AFA", 4)), a in (k[1] in reg && k[2] in tmem && k[4] == "FX" ? gset(tm, "ANNUAL").keys : ())
            push!(rtps_bd, (k[1], lastt, k[3], a[1], "FX"))
        end
        # L41: LOOP(RTPS_BD(R,T,P,S,BD), PRC_CAP(R,P) = YES); L42: OPTION CLEAR=OBJ_ICUR,CLEAR=RTPS_BD
        foreach(k -> push!(prc_cap, (k[1], k[3])), rtps_bd)
        empty!(obj_icur); empty!(rtps_bd)

        # --- L48-56: emission flows substituted ----------------------------------------------------------
        # L48: OPTION CLEAR=TRACKPC; L50: TRACKPC(RP_STD(R,P),C)$(TOP(R,P,C,'OUT')$ENV(R,C)) = YES
        env = gset(tm, "ENV").members
        empty!(trackpc)
        foreach(k -> (k[4] == "OUT" && (k[1], k[2]) in rp_std && (k[1], k[3]) in env) && push!(trackpc, k[1:3]), top)
        # L51: TRACKPC(R,P,C)$(RPC_PG(R,P,C)+RPC_AFLO(R,P,C)) = NO
        rpc_pg, rpc_aflo = gset(tm, "RPC_PG").members, gset(tm, "RPC_AFLO").members
        filter!(k -> !(k in rpc_pg || k in rpc_aflo), trackpc)
        # L54: OPTION FSCK <= FLO_SUM  (FLO_SUM(REG,ALLYEAR,PRC,CG,C,CG,TS) -> FSCK(REG,PRC,CG,C,CG))
        fsck = project(keys(gvalues(tm, "FLO_SUM", 7)), (1, 3, 4, 5, 6))
        # L55: FS_EMIS(FSCK(R,P,CG,C,COM))$((COM_GMAP(R,CG,C)$TOP(R,P,C,'IN'))$TRACKPC(R,P,COM)) = YES
        gmap = gset(tm, "COM_GMAP").members
        foreach(k -> ((k[1], k[3], k[4]) in gmap && (k[1], k[2], k[4], "IN") in top && (k[1], k[2], k[5]) in trackpc) && push!(fs_emis, k), fsck)
        # L56: LOOP(FS_EMIS(R,P,CG,C,COM), RPC_EMIS(R,P,COM) = YES)
        foreach(k -> push!(rpc_emis, (k[1], k[2], k[5])), fs_emis)
    end

    if red == "YES"
        rp_pgact, rp_flo = gset(tm, "RP_PGACT").members, gset(tm, "RP_FLO").members
        # --- L65-87: flows substituted by the activity, processes without activity variables -------------
        # L65: RPC_ACT(RPC_PG(RP_PGACT(RP_STD),C)) = YES; L68: RPC_AIRE(RPC_PG(RP_IRE(RP_PGACT),C)) = YES
        for k in rpc_pg
            (k[1], k[2]) in rp_pgact || continue
            (k[1], k[2]) in rp_std && push!(rpc_act, k)
            (k[1], k[2]) in rp_ire && push!(rpc_aire, k)
        end
        # L71: PRC_ACT(RP_PGACT) = NO; L76: NO_ACT(PRC_ACT(R,P))$(NOT PRC_CAP(R,P)) = YES
        setdiff!(prc_act, rp_pgact)
        foreach(k -> k in prc_cap || push!(no_act, k), prc_act)
        # L77: LOOP((RTP(R,T,P),S,BD)$((ACT_BND(RTP,S,BD)>-INF$BDUPX(BD))$ACT_BND(RTP,S,BD)), NO_ACT(R,P) = NO)
        bdupx = Set(k[1] for k in gset(tm, "BDUPX").keys)
        foreach(((k, v),) -> (k[2] in tmem && k[1:3] in rtp && v > (k[5] in bdupx ? -Inf : 0.0)) && delete!(no_act, (k[1], k[3])), act_bnd)
        # L78: LOOP((R,DM_YEAR,P,CUR)$ACT_COST(R,DM_YEAR,P,CUR), NO_ACT(R,P) = NO)
        foreach(k -> (k[1] in reg && k[2] in dm) && delete!(no_act, (k[1], k[3])), keys(gvalues(tm, "ACT_COST", 4)))
        # L79: LOOP((R,UC_N,P)$UC_GMAP_P(R,UC_N,'ACT',P), NO_ACT(R,P) = NO)
        foreach(k -> k[3] == "ACT" && delete!(no_act, (k[1], k[4])), gset(tm, "UC_GMAP_P").keys)
        # L80: NO_ACT(R,P)$SUM(RPC_CUMFLO(R,P,%PGPRIM%,YEAR,LL),1) = NO
        pg = uppercase(strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"']))
        foreach(k -> uppercase(k[3]) == pg && delete!(no_act, (k[1], k[2])), gset_opt(tm.data, "RPC_CUMFLO", 5).keys)
        # L83: PRC_ACT(NO_ACT) = NO; L86: RP_XRED(RP_PGFLO) = NO
        setdiff!(prc_act, no_act)
        setdiff!(rp_xred, gset(tm, "RP_PGFLO").members)
        # L87: RPC_ACT(RP_XRED(RP_STD(PRC_ACT)),ACTCG) = YES
        actcg = [k[1] for k in gset(tm, "ACTCG").keys]
        foreach(k -> (k in rp_std && k in prc_act) && foreach(cg -> push!(rpc_act, (k..., cg)), actcg), rp_xred)

        # --- L96-123: FLO_FUNC / FLO_SUM substitution --------------------------------------------------------
        # L96: OPTION CG_GRP <= FLO_FUNC, RP_XRED < CG_GRP; CG_GRP(R,P,CG,CG) = NO
        cg_grp = project(keys(gvalues(tm, "FLO_FUNC", 6)), (1, 3, 4, 5))
        rp_xred = project(cg_grp, (1, 2))
        filter!(k -> k[3] != k[4], cg_grp)
        # L97: CG_GRP(R,P,CG,CG2)$(SUM(RPC(R,P,C)$COM_GMAP(R,CG,C),1) NE 1) = NO
        ncg(r, p, cg) = count(c -> (r, cg, c) in gmap, get(rpc_of, (r, p), String[]))
        filter!(k -> ncg(k[1], k[2], k[3]) == 1, cg_grp)
        # L98: CG_GRP(R,P,CG1,CG)$(SUM(RPC(RP_PGACT(R,P),C)$COM_GMAP(R,CG,C),1) NE 1) = NO
        filter!(k -> (k[1], k[2]) in rp_pgact && ncg(k[1], k[2], k[4]) == 1, cg_grp)
        # L99: RPCG_PTRAN(RPC(R,P,C),COM,CG1,CG2)$((COM_GMAP(R,CG1,C)*RPC(R,P,COM)*COM_GMAP(R,CG2,COM))$CG_GRP(R,P,CG1,CG2)) = YES
        for (r, p, g1, g2) in cg_grp, c in get(rpc_of, (r, p), String[]), cm in get(rpc_of, (r, p), String[])
            ((r, g1, c) in gmap && (r, g2, cm) in gmap) && push!(ptran, (r, p, c, cm, g1, g2))
        end
        # L101: LOOP(FSCK(R,P,CG1,C,CG2)$CG_GRP(R,P,CG2,CG1),RPCG_PTRAN(R,P,C,COM,CG1,CG2)$COM_GMAP(R,CG2,COM) = YES)
        gmap_of = by2(gset(tm, "COM_GMAP").keys)
        for (r, p, g1, c, g2) in fsck
            (r, p, g2, g1) in cg_grp || continue
            foreach(cm -> push!(ptran, (r, p, c, cm, g1, g2)), get(gmap_of, (r, g2), String[]))
        end
        # L102: RPCG_PTRAN(R,P,C,COM,CG1,CG2)$(NOT (RPC_ACT(R,P,C)+RPC_ACT(R,P,COM))) = NO
        filter!(k -> (k[1], k[2], k[3]) in rpc_act || (k[1], k[2], k[4]) in rpc_act, ptran)
        # L103: OPTION TRACKPC < RPCG_PTRAN  (RPCG_PTRAN(R,P,COM,C,CG,CG) -> TRACKPC(R,P,C): position 4)
        trackpc = project(ptran, (1, 2, 4))
        # L106: OPTION RP_CGG < FSCK  (FSCK(REG,PRC,CG,C,CG) -> RP_CGG(REG,PRC,C,CG,CG): positions 1,2,4,5,3)
        rp_cgg = project(fsck, (1, 2, 4, 5, 3))
        rp_pg = gset(tm, "RP_PG").members
        # L107: RPCG_PTRAN(RP_CGG(RPC_ACT(R,P,COM),C,CG),C)$(RP_PG(R,P,CG)+RPC_ACT(R,P,CG)) = YES
        foreach(k -> ((k[1], k[2], k[3]) in rpc_act && ((k[1], k[2], k[5]) in rp_pg || (k[1], k[2], k[5]) in rpc_act)) && push!(ptran, (k..., k[4])), rp_cgg)
        # L108: RPCG_PTRAN(RP_CGG(RPC(R,P,COM),C,COM),C)$RPC_ACT(R,P,C) = YES
        foreach(k -> (k[3] == k[5] && (k[1], k[2], k[3]) in rpc && (k[1], k[2], k[4]) in rpc_act) && push!(ptran, (k..., k[4])), rp_cgg)
        # L109: RPCG_PTRAN(RPC_ACT(RP,%PGPRIM%),C,CG,C)$(RP_PG(RP,CG)$RPC_AFLO(RP,C)) = YES
        aflo_of, pg_of = by2(gset(tm, "RPC_AFLO").keys), by2(gset(tm, "RP_PG").keys)
        for (r, p, a) in collect(rpc_act)
            (uppercase(a) == pg && (r, p) in rp) || continue
            for c in get(aflo_of, (r, p), String[]), cg in get(pg_of, (r, p), String[])
                push!(ptran, (r, p, a, c, cg, c))
            end
        end
        # L111: RPCG_PTRAN(RP_SGS,C,COM,CG,CG2) = NO
        rp_sgs = gset(tm, "RP_SGS").members
        filter!(k -> !((k[1], k[2]) in rp_sgs), ptran)
        # L112-114: LOOP(RPCG_PTRAN(RP_FLO(R,P),C,COM,CG,CG2), IF(RPC_ACT(R,P,C), RPC_FFUNC(R,P,COM) = YES; ELSE RPC_FFUNC(R,P,C) = YES))
        for k in ptran
            (k[1], k[2]) in rp_flo || continue
            push!(ffunc, (k[1], k[2], (k[1], k[2], k[3]) in rpc_act ? k[4] : k[3]))
        end
        # L116: RPC_FFUNC(RPC)$(RPC_ACT(RPC)+RPC_EMIS(RPC)) = NO
        filter!(k -> !(k in rpc && (k in rpc_act || k in rpc_emis)), ffunc)
        # L117: RPC_FFUNC(RPC_AFLO(RP_XRED(RP),C))$(RP_PGACT(RP)->TRACKPC(RP,C)) = NO
        filter!(k -> !(k in rpc_aflo && (k[1], k[2]) in rp_xred && (k[1], k[2]) in rp && (!((k[1], k[2]) in rp_pgact) || k in trackpc)), ffunc)
        # L120: RPCG_PTRAN(R,P,C,COM,CG,CG2)$(NOT RPC_FFUNC(R,P,C)+RPC_FFUNC(R,P,COM)) = NO
        filter!(k -> (k[1], k[2], k[3]) in ffunc || (k[1], k[2], k[4]) in ffunc, ptran)
        # L121: LOOP(RPCG_PTRAN(R,P,C,COM,CG,CG2), RPCC_FFUNC(R,P,CG,CG2) = YES)
        foreach(k -> push!(ccffunc, (k[1], k[2], k[5], k[6])), ptran)
        # L123: OPTION CLEAR=CG_GRP,RP_XRED<RPC_ACT,CLEAR=RP_CGG
        empty!(cg_grp)
        rp_xred = project(rpc_act, (1, 2))
        empty!(rp_cgg)

        # --- L130-136: processes turned off by zero activity bounds ------------------------------------------
        rps_prcts = gset(tm, "RPS_PRCTS").members
        # L130-131: LOOP((R,T,P,S,BDUPX)$((ACT_BND(R,T,P,S,BDUPX) EQ 0)$ACT_BND(R,T,P,S,BDUPX)), RTPS_OFF(R,T,P,S)$RPS_PRCTS(R,P,S) = YES)
        foreach(((k, v),) -> (k[1] in reg && k[2] in tmem && k[5] in bdupx && v == 0.0 && (k[1], k[3], k[4]) in rps_prcts) && push!(rtps_off, k[1:4]), act_bnd)
        # L134-136: LOOP((RTPCS_OUT(R,T,P,C,S),RPCS_VAR(RP_STD(R,P),C,S)), IF(RPC_FFUNC(R,P,C),
        #   RTPS_OFF(R,T,P,TS)$(PRC_TS(R,P,TS)*RS_TREE(R,S,TS)) = YES; ELSEIF RPC_ACT(R,P,C), RTPS_OFF(R,T,P,S) = YES))
        rpcs_var, prc_ts, rs_tree = gset(tm, "RPCS_VAR").members, gset(tm, "PRC_TS"), gset(tm, "RS_TREE").members
        pts_of = by2(prc_ts.keys)
        for (r, t, p, c, s) in collect(rtpcs_out)
            ((r, p, c, s) in rpcs_var && (r, p) in rp_std) || continue
            if (r, p, c) in ffunc
                foreach(ts -> (r, s, ts) in rs_tree && push!(rtps_off, (r, t, p, ts)), get(pts_of, (r, p), String[]))
            elseif (r, p, c) in rpc_act
                push!(rtps_off, (r, t, p, s))
            end
        end

        # --- L141-162: commodities with a single producer or consumer turned off ----------------------------
        # L141: OPTION CLEAR=RXX; L143-144: LOOP(RTPS_OFF(R,T,P,S),IF(RP_STD(R,P),RTCS_SING(R,T,C,S,IO)$TOP(R,P,C,IO) = YES;
        #   ELSE RTCS_SING(R,T,C,S,'OUT')$RPC_IRE(R,P,C,'IMP') = YES))
        empty!(rxx)
        top_of = Dict{NTuple{2,String},Vector{NTuple{2,String}}}()
        foreach(k -> pushat!(top_of, (k[1], k[2]), (k[3], k[4])), gset(tm, "TOP").keys)
        rpc_ire = gset(tm, "RPC_IRE").members
        ire_of = Dict{NTuple{2,String},Vector{NTuple{2,String}}}()
        foreach(k -> pushat!(ire_of, (k[1], k[2]), (k[3], k[4])), gset(tm, "RPC_IRE").keys)
        for (r, t, p, s) in rtps_off
            if (r, p) in rp_std
                foreach(ci -> push!(sing, (r, t, ci[1], s, ci[2])), get(top_of, (r, p), NTuple{2,String}[]))
            else
                foreach(ci -> ci[2] == "IMP" && push!(sing, (r, t, ci[1], s, "OUT")), get(ire_of, (r, p), NTuple{2,String}[]))
            end
        end
        # L146: LOOP(RTCS_SING(R,T,C,S,IO),RXX(R,C,IO) = YES)
        foreach(k -> push!(rxx, (k[1], k[3], k[5])), sing)
        # L147: RXX(ENV,'IN') = NO; RXX(DEM,'IN') = NO; RXX(R,C,'IN')$RC_AGP(R,C,'LO') = NO
        dem, rc_agp = gset(tm, "DEM").members, gset(tm, "RC_AGP").members
        filter!(k -> !(k[3] == "IN" && ((k[1], k[2]) in env || (k[1], k[2]) in dem || (k[1] in reg && (k[1], k[2], "LO") in rc_agp))), rxx)
        # L148: LOOP((R,T,COM,C)$(RXX(R,C,'OUT')$COM_AGG(R,T,COM,C)),TRACKC(R,C) = YES); L149: RXX(TRACKC,'OUT') = NO
        foreach(k -> (k[1] in reg && k[2] in tmem && (k[1], k[4], "OUT") in rxx) && push!(trackc, (k[1], k[4])), keys(gvalues(tm, "COM_AGG", 4)))
        filter!(k -> !(k[3] == "OUT" && (k[1], k[2]) in trackc), rxx)
        # L150-152: RC_IOP(RXX(R,C,IO),P)$TOP(R,P,C,IO); RC_IOP(RXX(R,C,'IN'),P)$RPC_IRE(R,P,C,'EXP'); RC_IOP(RXX(R,C,'OUT'),P)$RPC_IRE(R,P,C,'IMP')
        foreach(k -> (k[1], k[3], k[4]) in rxx && push!(rc_iop, (k[1], k[3], k[4], k[2])), top)
        for k in rpc_ire
            k[4] == "EXP" && (k[1], k[3], "IN") in rxx && push!(rc_iop, (k[1], k[3], "IN", k[2]))
            k[4] == "IMP" && (k[1], k[3], "OUT") in rxx && push!(rc_iop, (k[1], k[3], "OUT", k[2]))
        end
        # L154: RXX(RXX(R,C,IO))$(SUM(RC_IOP(R,C,IO,P),1) NE 1) = NO
        niop = Dict{NTuple{3,String},Int}()
        foreach(k -> (niop[k[1:3]] = get(niop, k[1:3], 0) + 1), rc_iop)
        filter!(k -> !(k[1] in reg && get(niop, k, 0) != 1), rxx)
        # L155: RTCS_SING(R,T,C,S,IO)$(NOT RXX(R,C,IO)) = NO
        filter!(k -> !(k[1] in reg && k[2] in tmem && !((k[1], k[3], k[5]) in rxx)), sing)
        # L158-159: LOOP(RTCS_SING(R,T,C,S,IO--1), LOOP(TOP(R,P,C,IO)$(SUM(COM$TOP(R,P,COM,IO),1)=1), RTPS_OFF(R,T,P,S)$RPS_PRCTS(R,P,S) = YES))
        ios = [k[1] for k in gset(tm, "IO").keys]
        other = Dict(ios[i] => ios[mod(i, length(ios)) + 1] for i in eachindex(ios))     # IO with IO--1 = io
        ntop = Dict{NTuple{3,String},Int}()
        foreach(k -> (ntop[(k[1], k[2], k[4])] = get(ntop, (k[1], k[2], k[4]), 0) + 1), top)
        pc_of = Dict{NTuple{3,String},Vector{String}}()                                # (R,C,IO) -> P of TOP
        foreach(k -> pushat!(pc_of, (k[1], k[3], k[4]), k[2]), top)
        for (r, t, c, s, io1) in collect(sing)
            io = other[io1]
            for p in get(pc_of, (r, c, io), String[])
                get(ntop, (r, p, io), 0) == 1 && (r, p, s) in rps_prcts && push!(rtps_off, (r, t, p, s))
            end
        end
        # L161: RHS_COMPRD(R,T,C,S)$RTCS_SING(R,T,C,S,'OUT') = NO; L162: OPTION CLEAR=TRACKC,CLEAR=RC_IOP
        filter!(k -> !((k..., "OUT") in sing), rhs_prd)
        empty!(trackc); empty!(rc_iop)

        # --- L164-173: the processes turned off -------------------------------------------------------------
        # L164: RTPS_OFF(RTPS_OFF(R,T,P,S))$PRC_MAP(R,'STG',P) = NO
        prc_map = gset(tm, "PRC_MAP").members
        filter!(k -> !((k[1], "STG", k[3]) in prc_map), rtps_off)
        # L165: RTPS_OFF(R,T,P,TS) $= SUM(RS_BELOW(R,S,TS)$RTPS_OFF(R,T,P,S),YES)
        below = by2(gset(tm, "RS_BELOW").keys)
        add = [(k[1], k[2], k[3], ts) for k in rtps_off for ts in get(below, (k[1], k[4]), String[])]
        union!(rtps_off, add)
        # L167: ACT_BND(RTPS_OFF(RTP_VARA(R,T,P),S),'UP')$PRC_TS(R,P,S) = EPS
        foreach(k -> (k[1:3] in vara && (k[1], k[3], k[4]) in prc_ts.members) && (act_bnd[(k..., "UP")] = 0.0), rtps_off)
        # L168: ACT_BND(RTPS_OFF(R,T,P,S),BD)$(NOT PRC_TS(R,P,S)) = 0
        filter!(((k, _),) -> !(k[1:4] in rtps_off && !((k[1], k[3], k[4]) in prc_ts.members)), act_bnd)
        # L172: RTPCS_OUT(RTPC(RTP(R,T,P),C),S)$RTPS_OFF(R,T,P,S) = YES
        rtpc_of = Dict{NTuple{3,String},Vector{String}}()
        foreach(k -> pushat!(rtpc_of, k[1:3], k[4]), gset(tm, "RTPC").keys)
        foreach(k -> k[1:3] in rtp && foreach(c -> push!(rtpcs_out, (k[1], k[2], k[3], c, k[4])), get(rtpc_of, k[1:3], String[])), rtps_off)
        # L173: RTP_VARA(R,T,P)$(SUM(PRC_TS(R,P,TS)$(NOT RTPS_OFF(R,T,P,TS)),1) EQ 0) = NO
        filter!(k -> !(k[1] in reg && k[2] in tmem && !any(ts -> !((k..., ts) in rtps_off), get(pts_of, (k[1], k[3]), String[]))), vara)
    end

    # --- L177-188: REDDONE ------------------------------------------------------------------------------------
    # L181: LOOP(FS_EMIS(R,P,CG,C,COM), RPCC_FFUNC(R,P,CG,COM) = YES); L182: OPTION CLEAR=TRACKPC,CLEAR=FSCK
    foreach(k -> push!(ccffunc, (k[1], k[2], k[3], k[5])), fs_emis)
    empty!(trackpc); empty!(fsck)
    # L183: PRC_TS2(PRC_TS(RP_XRED(R,P),S)) = YES
    prc_ts2 = gmembers(tm, "PRC_TS2", 3)
    foreach(k -> (k[1], k[2]) in rp_xred && push!(prc_ts2, k), gset(tm, "PRC_TS").keys)
    # L184: RPC_PKC(RP,C)$(NOT PRC_CAP(RP)) = NO; L185: RPC_PKF(RPC_PKC) = 0
    pkc = gmembers(tm, "RPC_PKC", 3)
    filter!(k -> !((k[1], k[2]) in rp && !((k[1], k[2]) in prc_cap)), pkc)
    pkf = gvalues(tm, "RPC_PKF", 3)
    filter!(((k, _),) -> !(k in pkc), pkf)

    # --- ppmain.mod L1342-1350 ------------------------------------------------------------------------------
    # L1342: RTPCS_VARF(RTPC(RTP_VARA(R,T,P),C),S)$((NOT RTPCS_OUT(R,T,P,C,S))$RPCS_VAR(R,P,C,S)) = YES
    varf = gmembers(tm, "RTPCS_VARF", 5)
    rpcs_s = Dict{NTuple{3,String},Vector{String}}()
    foreach(k -> pushat!(rpcs_s, k[1:3], k[4]), gset(tm, "RPCS_VAR").keys)
    for k in gset(tm, "RTPC").keys
        k[1:3] in vara || continue
        foreach(s -> (k..., s) in rtpcs_out || push!(varf, (k..., s)), get(rpcs_s, (k[1], k[3], k[4]), String[]))
    end
    # L1347: RTP_VINTYR(RTP_CPTYR(R,V,T,P))$PRC_VINT(R,P) = YES
    vintyr = gmembers(tm, "RTP_VINTYR", 4)
    vint = gset(tm, "PRC_VINT").members
    foreach(k -> (k[1], k[4]) in vint && push!(vintyr, k), gset(tm, "RTP_CPTYR").keys)
    # L1348: RTP_VINTYR(R,T,T,P)$((NOT PRC_VINT(R,P))*RTP(R,T,P)$RVP(R,T,P)) = YES
    foreach(k -> (k[2] in tmem && k in rvp && !((k[1], k[3]) in vint)) && push!(vintyr, (k[1], k[2], k[2], k[3])), rtp)
    # L1350: OPTION CLEAR=R_UC,CLEAR=RVP,CLEAR=RTPCS_OUT
    gput!(tm, "RP_AFB", rp_afb)
    for (n, v) in (("RTP_VARA", vara), ("PRC_CAP", prc_cap), ("PRC_ACT", prc_act), ("OBJ_ICUR", obj_icur),
                   ("RTPS_BD", rtps_bd), ("TRACKPC", trackpc), ("FSCK", fsck), ("FS_EMIS", fs_emis), ("RPC_EMIS", rpc_emis),
                   ("RPC_ACT", rpc_act), ("RPC_AIRE", rpc_aire), ("NO_ACT", no_act), ("RP_XRED", rp_xred), ("CG_GRP", cg_grp),
                   ("RPCG_PTRAN", ptran), ("RP_CGG", rp_cgg), ("RPC_FFUNC", ffunc), ("RPCC_FFUNC", ccffunc), ("RTPS_OFF", rtps_off),
                   ("RXX", rxx), ("RTCS_SING", sing), ("TRACKC", trackc), ("RC_IOP", rc_iop), ("RHS_COMPRD", rhs_prd),
                   ("PRC_TS2", prc_ts2), ("RPC_PKC", pkc), ("RTPCS_VARF", varf), ("RTP_VINTYR", vintyr))
        gput!(tm, n, v)
    end
    gput!(tm, "ACT_BND", act_bnd)
    gput!(tm, "RPC_PKF", pkf)
    gput!(tm, "R_UC", Set{NTuple{2,String}}())
    gput!(tm, "RVP", Set{NTuple{3,String}}())
    gput!(tm, "RTPCS_OUT", Set{NTuple{5,String}}())
    # L1356-1357: PUTCLOSE QLOG; IF(PUTOUT, QLOG.AP = 1)   (the QA log, qalog.jl)
    qa_close!(tm)
    return tm
end
