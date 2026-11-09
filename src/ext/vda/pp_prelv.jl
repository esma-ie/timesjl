# M1.3 (8b): the end of the prep -> prelv segment, ppmain.mod L615: the
# extensions' pp_prelv files (main_ext.mod pp_prelv %EXTEND%), here the VDA
# extension's pp_prelv.vda, with pp_lvlfc.mod for FLO_FR (L101). The prelv
# checkpoint follows (the harness's pp_prelv.tjlref, last in %EXTEND%).
#
# GAMS: ppmain.mod L615, pp_prelv.vda L1-125, pp_lvlfc.mod L19-42 (as L101
# calls it), v4.9.7.
#
# Index sets: R is REG, P is PRC, C and COM are COM, CG and CG2 are COM_GRP,
# S, TS and SL are ALL_TS, BD is BND_TYPE, L is LIM, LL is ALLYEAR, T is
# MILESTONYR, V is MODLYEAR. An alias of COM at a COM_GRP position runs over
# the commodities only (G27). `OPTION a < b` takes for each index of `a` the
# rightmost unused index of `b` with the same domain, `<=` the leftmost (G26):
# `CG_GRP < RPCC_FFUNC` swaps the two groups; the domains are compared as
# declared, so `NE < IRE_BND` takes the region (ALL_R), not the partner
# (ALL_REG), though ALL_R is an alias of ALL_REG (G45). `$`
# binds before `=` and `-` (G38); NOT ranks below + (G19); `a->b` is the
# implication. An assignment (`=`) over a domain sets every element, so a
# zero removes a record; `$=` writes only nonzero or EPS (G24); a statement
# reads the values from before it (G11).
#
# Refused: GR_PTDF, node-allocation and gas-grid data under %POWERFLO% YES (L114,
# powerflo.vda: `powerflo_main!`, M1.3 change 27a) and TS_OFF data (L125:
# dynslite.vda PRELEV runs when %RTS% is not S, that is with TS_OFF data,
# timslice.mod L33; no core model has any). Not translated: the DISPLAY of
# L18. The QA log of L81-85 is written (M1.3 change 25b-1). %SHELL% ANSWER
# (L17) is translated.

"The pp_prelv.vda paths this model would take that are not translated."
function pp_prelv_unported(tm)
    out = String[]
    uppercase(strip(gswitch(tm, "POWERFLO", ""), ['\'', '"'])) == "YES" && append!(out, powerflo_main_unported(tm))
    isempty(gset_opt(tm.data, "TS_OFF", 4).keys) || push!(out, "pp_prelv.vda L125 (TS_OFF data: dynslite.vda PRELEV)")
    return out
end

"""
    pp_prelv_symbols(tm) -> Vector{String}

Every set and parameter of the dump `tm` started from, the QA-log scalars
PUTOUT, PUTGRP and ERRLEV too (M1.3 change 25b-1): pp_prelv.vda ends the
prep -> prelv segment.
"""
pp_prelv_symbols(tm) = sort([i.name for i in values(tm.data.dump.symbols) if i.kind in (:set, :parameter)])

"""
    pp_prelv!(tm) -> tm

ppmain.mod L615 on the state after `ppmain_life!`: pp_prelv.vda, the VDA
extension's preprocessing before the levelising. NCAP_TLIFE restored for the
residual capacity; VDA_FLOP filtered by the ACT_EFF groups, ACT_FLO and
RPC_AFLO for the reduced flows (RP_XRED); the VDA_FLOP groups into PRC_CG,
FLO_FUNC and FLO_SUM; FLO_EMIS into PRC_ACTFLO, IRE_FLOSUM, FLO_SUM and
FLO_EFF; the non-standard shares into FLO_ASHAR; NCAP_CHPR 'N'; FLO_FR
levelised (pp_lvlfc.mod) with its 'N' fractions and RVPCSL; the dummy
imports without bounds out of TOP_IRE; the 'N' defaults of COM_BNDNET and
COM_BNDPRD.

GAMS: pp_prelv.vda L1-125, pp_lvlfc.mod L19-42, v4.9.7.
"""
function pp_prelv!(tm)
    u = pp_prelv_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    d = tm.data
    reg = Set(k[1] for k in gset(tm, "REG").keys)
    com = gset(tm, "COM").members
    iscom(c) = (c,) in com
    modl = gset(tm, "MODLYEAR").members
    tset = [k[1] for k in gset(tm, "MILESTONYR").keys]
    tmem = Set(tset)
    all_ts = [k[1] for k in gset(tm, "ALL_TS").keys]
    annual = Set(k[1] for k in gset(tm, "ANNUAL").keys)
    pg = uppercase(strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"']))   # %PGPRIM%
    rtp = gset(tm, "RTP").members
    rtpv(k) = (k[2],) in modl && k in rtp                               # RTP(R,V,P)
    rpc = gset(tm, "RPC").members
    rpc_pg, rpc_spg = gset(tm, "RPC_PG").members, gset(tm, "RPC_SPG").members
    rp_pg = gset(tm, "RP_PG").members
    gmap = gset(tm, "COM_GMAP").members
    actflo = gvalues(tm, "PRC_ACTFLO", 4)
    by3(s) = (m = Dict{NTuple{2,String},Vector{String}}(); foreach(k -> push!(get!(m, (k[1], k[2]), String[]), k[3]), s); m)

    # --- L11: NCAP_TLIFE for RESID ---------------------------------------------------------------
    # LOOP(PYR_S(V),NCAP_TLIFE(R,V,P)$PRC_RESID(R,'%DFLBL%',P) = PRC_RESID(R,'%DFLBL%',P))
    tlife = gvalues(tm, "NCAP_TLIFE", 3)
    resid = gvalues(tm, "PRC_RESID", 3)
    for (v,) in gset(tm, "PYR_S").keys
        (v,) in modl || continue
        for (k, x) in resid
            (k[2] == "0" && k[1] in reg) && (tlife[(k[1], v, k[3])] = x)
        end
    end
    gput!(tm, "NCAP_TLIFE", tlife)

    # --- L14-27: VDA_FLOP, ACT_FLO, RPC_AFLO --------------------------------------------------------
    vflop = gvalues(tm, "VDA_FLOP", 5)
    keep = gset_opt(d, "KEEP_FLOF", 3).members
    # L14: TRACKPC(RPC_SPG(R,P,C))$((NOT RPG_1ACE(R,P,C,C))$RPC_ACE(R,P,%PGPRIM%)) = YES
    g1ace, ace = gset_opt(d, "RPG_1ACE", 4).members, gset_opt(d, "RPC_ACE", 3).members
    trackpc = Set{NTuple{3,String}}(k for k in rpc_spg if !((k..., k[3]) in g1ace) && (k[1], k[2], pg) in ace)
    # L15-18: Z = CARD(VDA_FLOP); VDA_FLOP(R,LL,P,C,S)$((NOT KEEP_FLOF(R,P,C))$TRACKPC(R,P,C)) = 0;
    #   $IFI %SHELL%==ANSWER PRC_ACTFLO(R,V,P,C)$(...) = 0; Z = Z-CARD(VDA_FLOP)   (the DISPLAY not translated)
    z = Float64(length(vflop))
    drop(r, p, c) = iscom(c) && (r, p, c) in trackpc && !((r, p, c) in keep)
    filter!(((k, _),) -> !drop(k[1], k[3], k[4]), vflop)
    uppercase(gswitch(tm, "SHELL", "")) == "ANSWER" && filter!(((k, _),) -> !((k[2],) in modl && drop(k[1], k[3], k[4])), actflo)
    z -= length(vflop)
    # L20: ACT_FLO(R,LL,P,C,S)$RPS_PRCTS(R,P,S) = 0
    aflo = gvalues(tm, "ACT_FLO", 5)
    prcts = gset(tm, "RPS_PRCTS").members
    filter!(((k, _),) -> !(iscom(k[4]) && (k[1], k[3], k[5]) in prcts), aflo)
    # L21: OPTION RPC_AFLO < ACT_FLO, RP_GRP < VDA_FLOP, PRC_ACT < RP_GRP, CLEAR=ACT_FLO,CLEAR=KEEP_FLOF,CLEAR=TRACKPC
    rpc_aflo = project(keys(aflo), (1, 3, 4))
    rp_grp = project(keys(vflop), (1, 3, 4))
    prc_act = project(rp_grp, (1, 2))
    aflo = Dict{NTuple{5,String},Float64}()
    gput!(tm, "KEEP_FLOF", Set{NTuple{3,String}}())
    # L22: TRACKPC(RP_GRP(RPC)) = YES; RP_GRP(TRACKPC) = NO
    trackpc = Set{NTuple{3,String}}(k for k in rp_grp if k in rpc)
    setdiff!(rp_grp, trackpc)
    # L23: RP_XRED(PRC_ACT(R,P)) = (NOT RP_PGFLO(R,P)+RP_PGACT(R,P)+RP_SGS(R,P))$(CHP(R,P)->RP_XRED(R,P))
    xred = gmembers(tm, "RP_XRED", 2)
    pgflo, pgact, sgs, chp = (gset(tm, s).members for s in ("RP_PGFLO", "RP_PGACT", "RP_SGS", "CHP"))
    old_xred = copy(xred)
    for k in prc_act
        ok = !(k in pgflo || k in pgact || k in sgs) && (!(k in chp) || k in old_xred)
        ok ? push!(xred, k) : delete!(xred, k)
    end
    gput!(tm, "RP_XRED", xred)
    # L24: RPC_AFLO(TRACKPC(RP_STD(RP_XRED),C)) = YES
    rp_std = gset(tm, "RP_STD").members
    foreach(k -> ((k[1], k[2]) in rp_std && (k[1], k[2]) in xred) && push!(rpc_aflo, k), trackpc)
    # L25: RPC_AFLO(R,P,C)$(TRACKPC(R,P,C)->RPC_PG(R,P,C)) = NO   (C at the CG position: commodities only)
    filter!(k -> !(iscom(k[3]) && (!(k in trackpc) || k in rpc_pg)), rpc_aflo)
    gput!(tm, "RPC_AFLO", rpc_aflo)
    # L26: ACT_FLO(R,V,P,C,S)$RPC_AFLO(R,P,C) $= VDA_FLOP(R,V,P,C,S)
    for (k, x) in vflop
        ((k[2],) in modl && iscom(k[4]) && (k[1], k[3], k[4]) in rpc_aflo) && (aflo[k] = x)
    end
    gput!(tm, "ACT_FLO", aflo)
    # L27: VDA_FLOP(RTP,C,S)$ACT_FLO(RTP,C,S) = 1
    foreach(k -> (k[1], k[2], k[3]) in rtp && (vflop[k] = 1.0), keys(aflo))

    # --- L31-63: the VDA_FLOP groups ---------------------------------------------------------------
    # L31: RP_GRP(R,P,CG)$(NOT SUM(RPC(R,P,C)$COM_GMAP(R,CG,C),1)) = NO
    rpc_c = by3(rpc)
    filter!(k -> any(c -> (k[1], k[3], c) in gmap, get(rpc_c, (k[1], k[2]), String[])), rp_grp)
    # L33: PRC_CG(RP_GRP) = YES
    prc_cg = gmembers(tm, "PRC_CG", 3)
    union!(prc_cg, rp_grp)
    gput!(tm, "PRC_CG", prc_cg)
    # L35: LOOP(TRACKPC(RPC_PG(R,P,C)),TRACKP(R,P)=YES)
    trackp = Set{NTuple{2,String}}((k[1], k[2]) for k in trackpc if k in rpc_pg)
    # L37: VDA_FLOP(RTP(R,V,P),C,ANNUAL)$((RPC_PG(R,P,C)*(NOT TRACKPC(R,P,C)))$TRACKP(R,P)) = 1
    pg_c = by3(rpc_pg)
    for k in rtp
        ((k[2],) in modl && (k[1], k[3]) in trackp) || continue
        for c in get(pg_c, (k[1], k[3]), String[]), s in annual
            (k[1], k[3], c) in trackpc || (vflop[(k..., c, s)] = 1.0)
        end
    end
    # L39: TRACKPC(RPC_PG) = NO
    setdiff!(trackpc, rpc_pg)
    # L42: CG_GRP(RP_PG(R,P,CG2),CG)$RP_GRP(R,P,CG) = YES
    grp_of = by3(rp_grp)
    cg_grp = gmembers(tm, "CG_GRP", 4)
    for (r, p, cg2) in rp_pg
        foreach(cg -> push!(cg_grp, (r, p, cg2, cg)), get(grp_of, (r, p), String[]))
    end
    # L43: RPCC_FFUNC(CG_GRP(TRACKP(R,P),CG2,CG))$SUM(RPC_SPG(R,P,C)$COM_GMAP(R,CG,C),1) = YES
    spg_c = by3(rpc_spg)
    ffunc = gmembers(tm, "RPCC_FFUNC", 4)
    for k in cg_grp
        ((k[1], k[2]) in trackp && any(c -> (k[1], k[4], c) in gmap, get(spg_c, (k[1], k[2]), String[]))) && push!(ffunc, k)
    end
    # L44: CG_GRP(RPCC_FFUNC) = NO; OPTION CLEAR=RP_GRP,CLEAR=PRC_ACT
    setdiff!(cg_grp, ffunc)
    # L47: LOOP(RPCC_FFUNC(R,P,CG2,CG),TRACKP(R,P) = NO)
    foreach(k -> delete!(trackp, (k[1], k[2])), ffunc)
    # L49: TRACKP(RP)$(SUM(RPC_SPG(TRACKPC(RP,C)),1)<>1) = NO
    nspg = Dict{NTuple{2,String},Int}()
    foreach(k -> k in rpc_spg && (nspg[(k[1], k[2])] = get(nspg, (k[1], k[2]), 0) + 1), trackpc)
    rp = gset(tm, "RP").members
    filter!(k -> !(k in rp && get(nspg, k, 0) != 1), trackp)
    # L50: RPCC_FFUNC(RP_PG(TRACKP(RP),CG),C) $= SUM(RPC_SPG(TRACKPC(RP,C)),1)
    for (r, p, cg) in rp_pg
        (r, p) in trackp || continue
        foreach(k -> (k[1] == r && k[2] == p && k in rpc_spg) && push!(ffunc, (r, p, cg, k[3])), trackpc)
    end
    # L51: TRACKPC(RPC_SPG(TRACKP,C)) = NO
    filter!(k -> !(k in rpc_spg && (k[1], k[2]) in trackp), trackpc)
    # L54: FLO_FUNC(RTP(R,V,P),CG2,CG,S)$RPCC_FFUNC(R,P,CG2,CG) = VDA_FLOP(RTP,CG,S)   (every S: the old records go)
    ffun = gvalues(tm, "FLO_FUNC", 6)
    vf_by = Dict{NTuple{4,String},Vector{Tuple{String,Float64}}}()
    foreach(((k, x),) -> push!(get!(vf_by, (k[1], k[2], k[3], k[4]), Tuple{String,Float64}[]), (k[5], x)), vflop)
    ff_by = Dict{NTuple{2,String},Vector{NTuple{2,String}}}()
    foreach(k -> push!(get!(ff_by, (k[1], k[2]), NTuple{2,String}[]), (k[3], k[4])), ffunc)
    rtp_by = Dict{NTuple{2,String},Vector{String}}()                    # (R,P) => the V of RTP(R,V,P)
    foreach(k -> (k[2],) in modl && push!(get!(rtp_by, (k[1], k[3]), String[]), k[2]), rtp)
    ts = Set(k[1] for k in gset(tm, "TS").keys)
    ffs = Dict{NTuple{5,String},Vector{String}}()                       # FLO_FUNC by all but S
    foreach(k -> push!(get!(ffs, k[1:5], String[]), k[6]), keys(ffun))
    for ((r, p), pairs) in ff_by, v in get(rtp_by, (r, p), String[]), (cg2, cg) in pairs
        foreach(s -> delete!(ffun, (r, v, p, cg2, cg, s)), get(ffs, (r, v, p, cg2, cg), String[]))
        for (s, x) in get(vf_by, (r, v, p, cg), Tuple{String,Float64}[])
            s in ts && (ffun[(r, v, p, cg2, cg, s)] = x)
        end
    end
    # L57, L59, L61: FLO_SUM from VDA_FLOP divided by the PG commodity's PRC_ACTFLO
    fsum = gvalues(tm, "FLO_SUM", 7)
    fs_by = Dict{NTuple{6,String},Vector{String}}()                      # FLO_SUM by all but S
    foreach(k -> push!(get!(fs_by, k[1:6], String[]), k[7]), keys(fsum))
    function set_all_s!(key6, src)                                         # FLO_SUM(key6,S) = src(S) for every S
        foreach(s -> delete!(fsum, (key6..., s)), get(fs_by, key6, String[]))
        for s in all_ts
            x = src(s)
            iszero(x) || gassign!(fsum, (key6..., s), x)
        end
        fs_by[key6] = [s for s in all_ts if haskey(fsum, (key6..., s))]
    end
    vf(r, v, p, c, s) = gv(vflop, (r, v, p, c, s))
    inv_af(r, v, p, c) = GNum(1.0) / gv(actflo, (r, v, p, c))
    for ((r, p), pairs) in ff_by, v in get(rtp_by, (r, p), String[]), (cg2, cg) in pairs, c in get(pg_c, (r, p), String[])
        # L57: FLO_SUM(RTP(R,V,P),CG2,C,CG,S)$(RPC_PG(R,P,C)$RPCC_FFUNC(R,P,CG2,CG)) = VDA_FLOP(RTP,C,S)*(1/PRC_ACTFLO(RTP,C))
        a = inv_af(r, v, p, c)
        set_all_s!((r, v, p, cg2, c, cg), s -> vf(r, v, p, c, s) * a)
    end
    cgg_by = Dict{NTuple{2,String},Vector{NTuple{2,String}}}()
    foreach(k -> push!(get!(cgg_by, (k[1], k[2]), NTuple{2,String}[]), (k[3], k[4])), cg_grp)
    for ((r, p), pairs) in cgg_by, v in get(rtp_by, (r, p), String[]), (cg2, cg) in pairs, c in get(pg_c, (r, p), String[])
        # L59: FLO_SUM(RTP(R,V,P),CG2,C,CG,S)$(RPC_PG(R,P,C)$CG_GRP(R,P,CG2,CG)) = VDA_FLOP(RTP,CG,S)*(1/PRC_ACTFLO(RTP,C))
        a = inv_af(r, v, p, c)
        set_all_s!((r, v, p, cg2, c, cg), s -> vf(r, v, p, cg, s) * a)
    end
    tpc_by = by3(trackpc)
    for (r, p, cg) in rp_pg, v in get(rtp_by, (r, p), String[]), c in get(pg_c, (r, p), String[]), cm in get(tpc_by, (r, p), String[])
        # L61: FLO_SUM(RTP(R,V,P),CG,C,COM,S)$(RP_PG(R,P,CG)*RPC_PG(R,P,C)*TRACKPC(R,P,COM)) $= VDA_FLOP(RTP,COM,S)*(1/PRC_ACTFLO(RTP,C))
        a = inv_af(r, v, p, c)
        for s in all_ts
            x = vf(r, v, p, cm, s) * a
            iszero(x) || gassign!(fsum, (r, v, p, cg, c, cm, s), x)
        end
    end
    # L62: FLO_FUNC(RTP(R,V,P),ACTCG,C,ANNUAL(S))$((FLO_FUNCX(RTP,ACTCG,C)<0)$TRACKPC(R,P,C)) $= VDA_FLOP(RTP,C,S)
    funcx = gvalues(tm, "FLO_FUNCX", 5)
    actcg = Set(k[1] for k in gset(tm, "ACTCG").keys)
    for (k, x) in funcx
        (x < 0 && k[4] in actcg && iscom(k[5]) && rtpv((k[1], k[2], k[3])) && (k[1], k[3], k[5]) in trackpc) || continue
        for s in annual
            y = vf(k[1], k[2], k[3], k[5], s)
            iszero(y) || gassign!(ffun, (k..., s), y)
        end
    end
    gput!(tm, "FLO_FUNC", ffun)
    # L63: OPTION CLEAR=TRACKP,CLEAR=TRACKPC,CLEAR=VDA_FLOP,CLEAR=CG_GRP,CLEAR=RPCC_FFUNC
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    gput!(tm, "TRACKPC", Set{NTuple{3,String}}())
    gput!(tm, "VDA_FLOP", Dict{NTuple{5,String},Float64}())
    gput!(tm, "RP_GRP", Set{NTuple{3,String}}())
    gput!(tm, "PRC_ACT", Set{NTuple{2,String}}())

    # --- L66-91: FLO_EMIS ---------------------------------------------------------------------------
    emis = gvalues(tm, "FLO_EMIS", 6)
    prc_map = gset(tm, "PRC_MAP").members
    # L66: PRC_ACTFLO(R,V,P,C) $= FLO_EMIS(R,V,P,%PGPRIM%,C,'ANNUAL')$PRC_MAP(R,'STG',P)
    for (k, x) in emis
        (k[4] == pg && k[6] == "ANNUAL" && (k[2],) in modl && k[1] in reg && iscom(k[5]) && (k[1], "STG", k[3]) in prc_map) &&
            (actflo[(k[1], k[2], k[3], k[5])] = x)
    end
    gput!(tm, "PRC_ACTFLO", actflo)
    # L67: IRE_FLOSUM(R,V,P,C(ACTCG),S,IE,COM,'OUT') $= FLO_EMIS(R,V,P,C,COM,S)$RP_AIRE(R,P,IE)
    flosum = gvalues(tm, "IRE_FLOSUM", 8)
    aire = by3(gset(tm, "RP_AIRE").keys)
    for (k, x) in emis
        (k[4] in actcg && iscom(k[4]) && (k[2],) in modl && k[1] in reg && iscom(k[5])) || continue
        foreach(ie -> (flosum[(k[1], k[2], k[3], k[4], k[6], ie, k[5], "OUT")] = x), get(aire, (k[1], k[3]), String[]))
    end
    gput!(tm, "IRE_FLOSUM", flosum)
    # L69: OPTION RP_CGC <= FLO_EMIS   (positions 1, 3, 4, 5)
    rp_cgc = project(keys(emis), (1, 3, 4, 5))
    # L70: FLO_EMIS(RTP(R,V,P),C,C,S)$(RP_CGC(R,P,C,C)$RPC_PG(R,P,C)) = 1+(FLO_EMIS(RTP,C,C,S)-1)/PRC_ACTFLO(RTP,C)   (every S)
    for (r, p, cg, cm) in collect(rp_cgc)
        (cg == cm && iscom(cg) && (r, p, cg) in rpc_pg) || continue
        for v in get(rtp_by, (r, p), String[])
            a = gv(actflo, (r, v, p, cg))
            new = [(s, GNum(1.0) + (gv(emis, (r, v, p, cg, cg, s)) - GNum(1.0)) / a) for s in all_ts]
            foreach(((s, x),) -> gassign!(emis, (r, v, p, cg, cg, s), x), new)
        end
    end
    # L71: RP_CGC(RP_IRE(R,P),CG,C)=NO; RP_CGC(RPC_STG,C)=NO
    rp_ire, rpc_stg = gset(tm, "RP_IRE").members, gset(tm, "RPC_STG").members
    filter!(k -> !(((k[1], k[2]) in rp_ire && k[1] in reg && iscom(k[4])) || (k[1], k[2], k[3]) in rpc_stg), rp_cgc)
    # L72-73: RPCC_FFUNC(RP_CGC(RPC,COM)) = YES; RP_CGC(RPCC_FFUNC(RPC,COM)) = NO
    ffunc = Set{NTuple{4,String}}(k for k in rp_cgc if (k[1], k[2], k[3]) in rpc)
    setdiff!(rp_cgc, ffunc)
    # L74: RPC_EMIS(R,P,C)$SUM(RPCC_FFUNC(R,P,COM,C),1) = NO
    rpc_emis = gmembers(tm, "RPC_EMIS", 3)
    emitted = Set((k[1], k[2], k[4]) for k in ffunc)
    filter!(k -> !(iscom(k[3]) && k in emitted), rpc_emis)
    # L76: FSCK(RP_CGC(R,P,CG,COM),C)$(COM_GMAP(R,CG,C)$RPC(R,P,C)) = YES
    fsck = Set{NTuple{5,String}}()
    for (r, p, cg, cm) in rp_cgc
        foreach(c -> (r, cg, c) in gmap && push!(fsck, (r, p, cg, cm, c)), get(rpc_c, (r, p), String[]))
    end
    # L77: LOOP(FSCK(R,P,CG,COM,C), FLO_SUM(R,V,P,COM,C,COM,S) $= FLO_EMIS(R,V,P,CG,COM,S))   in GAMS order
    em_by = Dict{NTuple{4,String},Vector{Tuple{String,String,Float64}}}()   # (R,P,CG,COM) => (V,S,value)
    foreach(((k, x),) -> push!(get!(em_by, (k[1], k[3], k[4], k[5]), Tuple{String,String,Float64}[]), (k[2], k[6], x)), emis)
    for (r, p, cg, cm, c) in gams_sort!(collect(fsck), d)
        for (v, s, x) in get(em_by, (r, p, cg, cm), Tuple{String,String,Float64}[])
            (v,) in modl && (fsum[(r, v, p, cm, c, cm, s)] = x)
        end
    end
    # L78: RPC_EMIS(R,P,COM)$SUM(FSCK(R,P,CG,COM,C),1) = NO
    setdiff!(rpc_emis, Set((k[1], k[2], k[4]) for k in fsck))
    # L80: FLO_SUM(RTP(R,V,P),COM,C,COM,S)$(RPC_PG(R,P,C)$RP_CGC(R,P,%PGPRIM%,COM)) = FLO_EMIS(RTP,%PGPRIM%,COM,S)/PRC_ACTFLO(RTP,C)
    for (r, p, cg, cm) in rp_cgc
        (cg == pg && iscom(cm)) || continue
        for v in get(rtp_by, (r, p), String[]), c in get(pg_c, (r, p), String[])
            a = gv(actflo, (r, v, p, c))
            key6 = (r, v, p, cm, c, cm)
            foreach(s -> delete!(fsum, (key6..., s)), all_ts)
            for s in all_ts
                x = gv(emis, (r, v, p, pg, cm, s)) / a
                iszero(x) || gassign!(fsum, (key6..., s), x)
            end
        end
    end
    # L81: RP_CGC(R,P,%PGPRIM%,C) = NO; PUTGRP=0
    filter!(k -> !(k[3] == pg && iscom(k[4]) && k[1] in reg), rp_cgc)
    qa_group!(tm)
    # L82-85: LOOP(RP_CGC(R,P,CG,COM)$RPC_EMIS(R,P,COM), pp_qaput 01 'FLO_EMIS with no members of source group in
    #   process - ignored'; PUT QLOG ' WARNING       -     R=',%RL%,' P=',%PL%,' CG=',CG.TL,' COM=',COM.TL)
    for (r, p, cg, cm) in gams_sort!([k for k in rp_cgc if k[1] in reg && iscom(k[4]) && (k[1], k[2], k[4]) in rpc_emis], tm.data)
        pp_qaput!(tm, 1, "FLO_EMIS with no members of source group in process - ignored")
        qput!(qalog(tm), " WARNING       -     R=" * qlab12(r) * " P=" * qlab12(p) * " CG=" * cg * " COM=" * cm)
    end
    # L86: FLO_SUM(RTP(R,V,P),COM,C,COM,ANNUAL)$RPC_PG(R,P,C) $= SUM(RP_CGC(R,P,CG,COM)$RPC_EMIS(R,P,COM),EPS)
    for (r, p, cg, cm) in rp_cgc
        (iscom(cm) && (r, p, cm) in rpc_emis) || continue
        for v in get(rtp_by, (r, p), String[]), c in get(pg_c, (r, p), String[]), s in annual
            fsum[(r, v, p, cm, c, cm, s)] = 0.0                           # EPS
        end
    end
    # L88: OPTION CLEAR=RP_CGC, CLEAR=FSCK, CLEAR=RPC_EMIS, CG_GRP < RPCC_FFUNC   (the two groups swapped, G26)
    gput!(tm, "RPC_EMIS", Set{NTuple{3,String}}())
    cg_grp = Set{NTuple{4,String}}((k[1], k[2], k[4], k[3]) for k in ffunc)
    # L89: FLO_SUM(RTP(R,V,P),C,COM,C,S)$CG_GRP(R,P,C,COM) = FLO_EMIS(RTP,COM,C,S)   (every S)
    for (r, p, c, cm) in cg_grp
        (iscom(c) && iscom(cm)) || continue
        for v in get(rtp_by, (r, p), String[])
            key6 = (r, v, p, c, cm, c)
            foreach(s -> delete!(fsum, (key6..., s)), all_ts)
            for s in all_ts
                x = gv(emis, (r, v, p, cm, c, s))
                iszero(x) || gassign!(fsum, (key6..., s), x)
            end
        end
    end
    gput!(tm, "FLO_SUM", fsum)
    # L90: FLO_EFF(RTP(R,V,P),C,COM,S)$((NOT CG_GRP(R,P,C,COM))$RPC_PG(R,P,COM)$CHP(R,P)) $= FLO_EMIS(RTP,%PGPRIM%,C,S)
    feff = gvalues(tm, "FLO_EFF", 6)
    for (k, x) in emis
        (k[4] == pg && iscom(k[5]) && rtpv((k[1], k[2], k[3])) && (k[1], k[3]) in chp) || continue
        for cm in get(pg_c, (k[1], k[3]), String[])
            (k[1], k[3], k[5], cm) in cg_grp || (feff[(k[1], k[2], k[3], k[5], cm, k[6])] = x)
        end
    end
    gput!(tm, "FLO_EFF", feff)
    # L91: OPTION NE<IRE_BND, CLEAR=CG_GRP, CLEAR=RPCC_FFUNC, CLEAR=FLO_EMIS
    #   IRE_BND(ALL_R,ALLYEAR,COM,TS,ALL_REG,IE,BD) onto NE(ALL_R,COM): the region (ALL_R, not ALL_REG) and COM (G45)
    ne = project(gparam_opt(d, "IRE_BND", 7).keys, (1, 3))
    gput!(tm, "CG_GRP", Set{NTuple{4,String}}())
    gput!(tm, "RPCC_FFUNC", Set{NTuple{4,String}}())
    gput!(tm, "FLO_EMIS", Dict{NTuple{6,String},Float64}())
    gput!(tm, "RP_CGC", Set{NTuple{4,String}}())
    gput!(tm, "FSCK", Set{NTuple{5,String}}())

    # --- L96-98: shares, CHP ratios --------------------------------------------------------------------
    # L96: FLO_ASHAR(R,DM_YEAR,P,C,CG,S,BD) $= FLO_SHAR(R,DM_YEAR,P,C,CG,S,BD)$(NOT RP_STD(R,P))
    shar = gvalues(tm, "FLO_SHAR", 7)
    ashar = gvalues(tm, "FLO_ASHAR", 7)
    dm = gset(tm, "DM_YEAR").members
    for (k, x) in shar
        ((k[2],) in dm && k[1] in reg && !((k[1], k[3]) in rp_std)) && (ashar[k] = x)
    end
    gput!(tm, "FLO_ASHAR", ashar)
    # L97: FLO_SHAR(R,LL,P,C,CG,S,BD)$FLO_ASHAR(R,LL,P,C,CG,S,BD) = 0
    filter!(((k, _),) -> !haskey(ashar, k), shar)
    gput!(tm, "FLO_SHAR", shar)
    # L98: NCAP_CHPR(RTP(R,V,P),'N') $= NCAP_CHPR(R,'0',P,'N')
    chpr = gvalues(tm, "NCAP_CHPR", 4)
    for (k, x) in collect(chpr)
        (k[2] == "0" && k[4] == "N") || continue
        foreach(v -> (chpr[(k[1], v, k[3], "N")] = x), get(rtp_by, (k[1], k[3]), String[]))
    end
    gput!(tm, "NCAP_CHPR", chpr)

    # --- L100-112: FLO_FR, TOP_IRE ------------------------------------------------------------------------
    flo_fr = gvalues(tm, "FLO_FR", 6)
    # L100: RPC_CONLY(RTP,C) $= SUM(L$FLO_FR(RTP,C,'ANNUAL',L),1)
    conly = Set{NTuple{4,String}}((k[1], k[2], k[3], k[4]) for k in keys(flo_fr) if k[5] == "ANNUAL" && (k[1], k[2], k[3]) in rtp)
    # L101: $BATINCLUDE pp_lvlfc.mod FLO_FR 'P,C' RPCS_VAR ',BD' ",'0','0'" ALL_TS T RPC_CONLY(R,T,P,C)
    uncd7, ts_array = lvlfc_flo_fr!(tm, flo_fr, conly)
    st_uncd7 = uncd7
    # L102: FLO_FR(RPC_CONLY(R,T,P,C),S,'N')=MIN(1,SUM(RS_BELOW1(R,S,TS)$RPCS_VAR(R,P,C,TS),G_YRFR(R,TS)))$TS_CYCLE(R,S)
    rpcs_var = gset(tm, "RPCS_VAR").members
    below1 = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(below1, (k[1], k[2]), String[]), k[3]), gset(tm, "RS_BELOW1").keys)
    yrfr = gvalues(tm, "G_YRFR", 2)
    cycle = gvalues(tm, "TS_CYCLE", 2)
    allts_set = Set(k[1] for k in gset(tm, "TS").keys)
    tconly = [k for k in conly if k[2] in tmem]
    for (r, t, p, c) in tconly, s in allts_set
        x = haskey(cycle, (r, s)) ? gmin(GNum(1.0), reduce(+, (gv(yrfr, (r, ts)) for ts in get(below1, (r, s), String[]) if (r, p, c, ts) in rpcs_var);
                                                         init=GZERO)) : GZERO
        gassign!(flo_fr, (r, t, p, c, s, "N"), x)
    end
    # L103: FLO_FR(RPC_CONLY(R,T,P,C),S,BD)$FLO_FR(R,T,P,C,S,BD) = FLO_FR(R,T,P,C,S,BD)*G_YRFR(R,S)$RPCS_VAR(R,P,C,S)
    bd = Set(k[1] for k in gset(tm, "BD").keys)
    tcset = Set(tconly)
    for (k, x) in collect(flo_fr)
        ((k[1], k[2], k[3], k[4]) in tcset && k[6] in bd) || continue
        gassign!(flo_fr, k, GNum(x == 0.0 ? 0.0 : x, x == 0.0) * gif(gv(yrfr, (k[1], k[5])), (k[1], k[3], k[4], k[5]) in rpcs_var))
    end
    # L105-108: IF(CARD(FLO_FR), RVPCSL ...)
    rvpcsl = Set{NTuple{6,String}}()
    if !isempty(flo_fr)
        stoa = gvalues(tm, "STOA", 1)
        tsax = OrdAxis(all_ts)
        rtpc = gset(tm, "RTPC").members
        up(s) = lead(tsax, s, glead(Float64(gv(stoa, (s,)))))           # S+STOA(S)
        # L106: RVPCSL(RTPC(R,T,P,C),TS(S+STOA(S)),BD)$(FLO_FR(R,'0',P,C,TS,BD)$FLO_FR(RTPC,S,BD)) = YES
        for k in keys(flo_fr)
            ((k[1], k[2], k[3], k[4]) in rtpc && k[2] in tmem && k[6] in bd) || continue
            t = up(k[5])
            (t !== nothing && haskey(flo_fr, (k[1], "0", k[3], k[4], t, k[6]))) && push!(rvpcsl, (k[1], k[2], k[3], k[4], t, k[6]))
        end
        # L107: RVPCSL(RTPC(R,T,P,C),S+STOA(S),BD)$FLO_FR(RTPC,S,'N') = NO
        for k in keys(flo_fr)
            ((k[1], k[2], k[3], k[4]) in rtpc && k[2] in tmem && k[6] == "N") || continue
            t = up(k[5])
            t === nothing || foreach(b -> delete!(rvpcsl, (k[1], k[2], k[3], k[4], t, b)), bd)
        end
        # L108: RVPCSL(RTPC(R,T,P,C),S,'N')$TS_CYCLE(R,S) $= SUM(RVPCSL(RTPC,TS,BD),1)
        has = Set((k[1], k[2], k[3], k[4]) for k in rvpcsl)
        for k in has, s in allts_set
            haskey(cycle, (k[1], s)) && push!(rvpcsl, (k..., s, "N"))
        end
    end
    # L109: FLO_FR(RVPCSL(R,T,P,C,S,'N'))$(NOT RPCS_VAR(R,P,C,S)) = EPS+1$ANNUAL(S)
    for k in rvpcsl
        (k[6] == "N" && !((k[1], k[3], k[4], k[5]) in rpcs_var)) || continue
        gassign!(flo_fr, k, GEPS + GNum(k[5] in annual ? 1.0 : 0.0))
    end
    gput!(tm, "FLO_FR", flo_fr)
    # L111: TOP_IRE('IMPEXP',C,R,C,P(DUMIMP))$(NOT NE(R,C)) = NO
    top_ire = gmembers(tm, "TOP_IRE", 5)
    dumimp = Set(k[1] for k in gset(tm, "DUMIMP").keys)
    filter!(k -> !(k[1] == "IMPEXP" && k[2] == k[4] && k[3] in reg && k[5] in dumimp && !((k[3], k[2]) in ne)), top_ire)
    gput!(tm, "TOP_IRE", top_ire)
    # L112: OPTION CLEAR=NE,CLEAR=RVPCSL,CLEAR=RPC_CONLY
    gput!(tm, "NE", Set{NTuple{2,String}}())
    gput!(tm, "RVPCSL", Set{NTuple{6,String}}())
    gput!(tm, "RPC_CONLY", Set{NTuple{4,String}}())
    # L114: $IFI %POWERFLO%==YES $include powerflo.vda (M1.3 change 27a)
    uppercase(strip(gswitch(tm, "POWERFLO", ""), ['\'', '"'])) == "YES" && powerflo_main!(tm)

    # --- L117-122: COM_VAR default bounds -------------------------------------------------------------------
    rtcs = gset(tm, "RTCS_VARC").keys
    bdlox, bdneq = Set(k[1] for k in gset(tm, "BDLOX").keys), Set(k[1] for k in gset(tm, "BDNEQ").keys)
    for name in ("COM_BNDNET", "COM_BNDPRD")
        b = gvalues(tm, name, 5)
        # L117/L120: X(R,T,C,ANNUAL(S),'N')$(NOT X(R,T,C,S,'N')) $= X(R,'0',C,S,'N')
        for (k, x) in collect(b)
            (k[2] == "0" && k[4] in annual && k[5] == "N" && k[1] in reg) || continue
            foreach(t -> haskey(b, (k[1], t, k[3], k[4], "N")) || (b[(k[1], t, k[3], k[4], "N")] = x), tset)
        end
        # L118-119/L121-122: X(RTCS_VARC(RTC,S),BDLOX(BD))$((NOT X(RTC,S,BD))$X(RTC,'ANNUAL','N')) =
        #   (EPS-INF$BDNEQ(BD))$(-SIGN(X(RTC,'ANNUAL','N'))=1$BDNEQ(BD))   (the 'ANNUAL','N' read from before, G11)
        old = copy(b)
        for (r, t, c, s) in rtcs, bdx in bdlox
            haskey(old, (r, t, c, s, bdx)) && continue
            n = get(old, (r, t, c, "ANNUAL", "N"), nothing)
            n === nothing && continue
            ne_ = bdx in bdneq
            -sign(n) == (ne_ ? 1.0 : 0.0) || continue
            gassign!(b, (r, t, c, s, bdx), GEPS - GNum(ne_ ? Inf : 0.0))
        end
        gput!(tm, name, b)
    end

    # the scratch as GAMS leaves it
    gput!(tm, "UNCD7", st_uncd7)
    ts_array === nothing || gput!(tm, "TS_ARRAY", ts_array)
    gput!(tm, "Z", gassign!(Dict{Tuple{},Float64}(), (), GNum(z)))
    return tm
end

"""
    lvlfc_flo_fr!(tm, flo_fr, conly) -> (UNCD7, TS_ARRAY or nothing)

pp_lvlfc.mod with pp_prelv.vda L101's arguments (`FLO_FR 'P,C' RPCS_VAR ',BD'
",'0','0'" ALL_TS T RPC_CONLY(R,T,P,C)`): the FLO_FR records of a milestone,
process and commodity of RPC_CONLY at timeslices outside RPCS_VAR are
levelised to the RPCS_VAR timeslices: an ANNUAL value alone is copied to
them; otherwise each takes the sum over the finest timeslices below it of
their value, or of their nearest ancestor's, weighted by the year fractions,
unless it has a value of its own. `flo_fr` is changed in place.

GAMS: pp_lvlfc.mod L19-42, v4.9.7.
"""
function lvlfc_flo_fr!(tm, flo_fr, conly)
    tset = Set(k[1] for k in gset(tm, "MILESTONYR").keys)
    rpcs_var = gset(tm, "RPCS_VAR").members
    bd = Set(k[1] for k in gset(tm, "BD").keys)
    # L19, L29: OPTION CLEAR=UNCD7; LOOP((R,T,P,C,S,BD)$((NOT RPCS_VAR(R,P,C,S))$FLO_FR(R,T,P,C,S,BD)),
    #   UNCD7(R,T,P,C,BD,'0','0')$(RPC_CONLY(R,T,P,C)) = YES)
    rows = Set{NTuple{5,String}}()
    for k in keys(flo_fr)
        (k[2] in tset && k[6] in bd && (k[1], k[2], k[3], k[4]) in conly && !((k[1], k[3], k[4], k[5]) in rpcs_var)) &&
            push!(rows, (k[1], k[2], k[3], k[4], k[6]))
    end
    uncd7 = Set{NTuple{7,String}}((r..., "0", "0") for r in rows)
    isempty(rows) && return uncd7, nothing
    all_ts = [k[1] for k in gset(tm, "ALL_TS").keys]
    annual = Set(k[1] for k in gset(tm, "ANNUAL").keys)
    below = Dict{NTuple{2,String},Vector{String}}()                      # RS_BELOW(R,A,S): S strictly below A
    above = Dict{NTuple{2,String},Vector{String}}()                      # (R,S) => the A strictly above S
    for (r, a, s) in gset(tm, "RS_BELOW").keys
        push!(get!(below, (r, a), String[]), s)
        push!(get!(above, (r, s), String[]), a)
    end
    tsmap = gset(tm, "TS_MAP").members                                   # TS_MAP(R,TS,S): TS at or above S
    finest = gset(tm, "FINEST").members
    under = Dict{NTuple{2,String},Vector{String}}()                      # (R,TS) => the finest S with TS_MAP(R,TS,S)
    foreach(k -> (k[1], k[3]) in finest && push!(get!(under, (k[1], k[2]), String[]), k[3]), gset(tm, "TS_MAP").keys)
    yrfr = gvalues(tm, "G_YRFR", 2)
    vars = Dict{NTuple{3,String},Vector{String}}()
    foreach(k -> push!(get!(vars, (k[1], k[2], k[3]), String[]), k[4]), rpcs_var)
    ts_array = Dict{Tuple{String},Float64}()
    # L33: LOOP(UNCD7(R,T,P,C,BD,'0','0'), TS_ARRAY(S) = FLO_FR(R,T,P,C,S,BD); ...)   in GAMS order
    for (r, t, p, c, b) in gams_sort!(collect(rows), tm.data)
        ts_array = Dict{Tuple{String},Float64}((s,) => flo_fr[(r, t, p, c, s, b)] for s in all_ts if haskey(flo_fr, (r, t, p, c, s, b)))
        arr(s) = gv(ts_array, (s,))
        targets = get(vars, (r, p, c), String[])
        # L34: IF((NOT SUM(RS_BELOW(R,'ANNUAL',S)$TS_ARRAY(S),1))$TS_ARRAY('ANNUAL'), ...
        if !any(s -> haskey(ts_array, (s,)), get(below, (r, "ANNUAL"), String[])) && haskey(ts_array, ("ANNUAL",))
            # L35: FLO_FR(R,T,P,C,S,BD)$RPCS_VAR(R,P,C,S) = SUM(ANNUAL(ALL_TS),TS_ARRAY(ALL_TS))
            x = reduce(+, (arr(a) for a in annual); init=GZERO)
            foreach(s -> gassign!(flo_fr, (r, t, p, c, s, b), x), targets)
        else
            # L38-42: LOOP(RPCS_VAR(R,P,C,TS)$(NOT TS_ARRAY(TS)), FLO_FR(R,T,P,C,TS,BD) $= SUM(TS_MAP(R,TS,S)$FINEST(R,S),
            #   G_YRFR(R,S)/G_YRFR(R,TS) * (TS_ARRAY(S) + SUM(RS_BELOW(R,ALL_TS,S)$(TS_ARRAY(ALL_TS) AND
            #   NOT SUM(SL$RS_BELOW(R,ALL_TS,SL),TS_MAP(R,SL,S)*TS_ARRAY(SL))),TS_ARRAY(ALL_TS)))))
            for ts in targets
                haskey(ts_array, (ts,)) && continue
                x = GZERO
                for s in get(under, (r, ts), String[])
                    inh = GZERO
                    for a in get(above, (r, s), String[])
                        haskey(ts_array, (a,)) || continue
                        # NOT SUM(SL$RS_BELOW(R,A,SL), TS_MAP(R,SL,S)*TS_ARRAY(SL)): no value between A and S (S included)
                        mid = reduce(+, (arr(sl) for sl in get(below, (r, a), String[]) if (r, sl, s) in tsmap); init=GZERO)
                        iszero(mid) && (inh += arr(a))
                    end
                    x += gv(yrfr, (r, s)) / gv(yrfr, (r, ts)) * (arr(s) + inh)
                end
                iszero(x) || gassign!(flo_fr, (r, t, p, c, ts, b), x)
            end
        end
    end
    return uncd7, ts_array
end
