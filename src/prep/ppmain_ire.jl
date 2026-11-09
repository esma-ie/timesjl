# M1.3 (12): ppmain.mod L846-933 (docs/m13-plan.md): the trade attributes
# levelled to the timeslices (pp_lvlfc.mod for IRE_PRICE and IRE_FLOSUM,
# pp_lvlif.mod for IRE_FLO), the market-based trade (RPC_IREIO, IRE_DIST,
# RPC_MARKET, the marketplace links in TOP_IRE, their IRE_FLO, RPC_EQIRE,
# RTPC of shut-down periods, RP_AIRE), IRE_FLOSUM moved from the activity
# to the PG commodities, and the IRE_FLO defaults of 1.
#
# GAMS: ppmain.mod L846-933, pp_lvlfc.mod L19-45, pp_lvlif.mod L14-37,
# v4.9.7.
#
# Index sets: R and REG are the model regions REG (so TOP_IRE's links with
# an external region, IMPEXP, are left out of the loops), P is PRC, C, COM,
# COM1 and COM2 are COM, S and TS are ALL_TS, T is MILESTONYR, V is
# MODLYEAR, IE is IMPEXP, IO is IN_OUT. RTP(R,T,P) and RTP(R,V,P) run over
# the milestones and the model years (G8, G27). `$x` is true for EPS (G3)
# and `NOT x` false (G25); a numeric comparison takes EPS as 0 (G12); `$=`
# writes only a nonzero or EPS value (G24); a scalar `$` on a loop domain is
# read again before each member (G30, G46). The QA log (ppmain.mod L848,
# L878, L884-885; pp_lvlif.mod L14, L21-23) is written in LOOP order (M1.3
# change 25b-1).

"""
    ppmain_ire_symbols(tm) -> Vector{String}

The symbols ppmain.mod L846-933 settles that nothing later in the prelv ->
ppm segment changes (for the layer-1 check at the ppm checkpoint). Left
out: RC_RC (L981-984), RXX (L969-977) and the scratch, which the replay
checks at L933 (scripts/m13_replay.jl, test/unit/test_m13_ppmain_ire.jl).
"""
function ppmain_ire_symbols(tm)
    return ["IRE_PRICE", "IRE_FLOSUM", "IRE_FLO", "RPC_IREIO", "IRE_DIST", "RPC_MARKET", "TOP_IRE", "RPC_EQIRE", "RTPC",
            "RP_AIRE", "PRC_MAP"]
end

"""
    ppmain_ire!(tm) -> tm

ppmain.mod L846-933 on the state after `ppmain_flofs!`.

GAMS: ppmain.mod L846-933, v4.9.7.
"""
function ppmain_ire!(tm)
    tr = TsTree(tm)
    reg = tr.reg
    tlist = [k[1] for k in gset(tm, "MILESTONYR").keys]
    tmem = Set(tlist)
    modl = Set(k[1] for k in gset(tm, "MODLYEAR").keys)
    dyear = Set(k[1] for k in gset(tm, "DATAYEAR").keys)
    member(s) = Set(k[1] for k in gset(tm, s).keys)
    com, cur, ie_set, io_set, allreg = member("COM"), member("CUR"), member("IE"), member("IO"), member("ALL_REG")
    rtp = gset(tm, "RTP").members
    rpc_ire = gset_opt(tm.data, "RPC_IRE", 4).members
    by(itr, f, g) = (d = Dict{Any,Vector{Any}}(); foreach(k -> pushat!(d, f(k), g(k)), itr); d)
    none = Any[]
    rpcs_of = by(gset(tm, "RPCS_VAR").keys, k -> (k[1], k[2], k[3]), k -> k[4])
    pts_of = by(gset(tm, "PRC_TS").keys, k -> (k[1], k[2]), k -> k[3])
    prc_ts = gset(tm, "PRC_TS").members
    Z, F = gscal(tm, "Z"), gscal(tm, "F")
    ts_array = nothing
    lv(args...; kw...) = ((u7, a) = pp_lvlfc!(tm, tr, args...; kw...); a === nothing || (ts_array = a); u7)
    qa_group!(tm)                                                      # L848: PUTGRP = 0
    # L849: $BATINCLUDE pp_lvlfc.mod IRE_PRICE 'P,C' RPCS_VAR ',ALL_REG,IE,CUR' '' ALL_TS DATAYEAR 'RPC_IRE(R,P,C,IE)'
    lv("IRE_PRICE", 8; sp=5, years=dyear, keyok=k -> k[4] in com && k[6] in allreg && k[7] in ie_set && k[8] in cur,
       targets=k -> get(rpcs_of, (k[1], k[3], k[4]), none), qual=k -> (k[1], k[3], k[4], k[7]) in rpc_ire)
    # L850: $BATINCLUDE pp_lvlfc.mod IRE_FLOSUM P PRC_TS ',IE,COM,IO' '' ALL_TS T 'RTP(R,T,P)' 0 ',C'
    lv("IRE_FLOSUM", 8; sp=5, years=tmem, keyok=k -> k[4] in com && k[6] in ie_set && k[7] in com && k[8] in io_set,
       targets=k -> get(pts_of, (k[1], k[3]), none), qual=k -> (k[1], k[2], k[3]) in rtp)
    # L852: $BATINCLUDE pp_lvlif.mod mod
    flo = gvalues(tm, "IRE_FLO", 7)                                    # (REG,V,P,COM,R,C,S): from REG to R
    stoa = gvalues(tm, "STOA", 1)
    rpcsv = gset(tm, "RPCS_VAR").members
    # pp_lvlif.mod L14-20: LOOP((REG,V,P,COM,R,C,S)$IRE_FLO(REG,V,P,COM,R,C,S), IF((NOT RPCS_VAR(R,P,C,S))$STOA(S),
    #   IF(NOT UNCD7(REG,V,P,COM,R,C,'N'), IF(NOT RPC_IRE(R,P,C,'IMP'), TRACKPC(R,P,C)=YES; ELSE UNCD7(...,'N') = YES))))
    qa_group!(tm)                                                      # pp_lvlif.mod L14: PUTGRP = 0
    rows = Set{NTuple{6,String}}()
    trackpc = NTuple{3,String}[]
    for k in keys(flo)
        (k[1] in reg && k[2] in modl && k[4] in com && k[5] in reg && k[6] in com) || continue
        (!((k[5], k[3], k[6], k[7]) in rpcsv) && !iszero(gv(stoa, (k[7],)))) || continue
        (k[5], k[3], k[6], "IMP") in rpc_ire ? push!(rows, k[1:6]) : push!(trackpc, (k[5], k[3], k[6]))
    end
    # pp_lvlif.mod L21-23: LOOP(TRACKPC(R,P,C), pp_qaput 02 'IRE_FLO import commodity not in TOP_IRE';
    #   PUT QLOG ' WARNING        -    R=',%RL%,' P=',%PL%,' C=',C.TL); TRACKPC is cleared at L36
    for (r, p, c) in gams_sort!(unique(trackpc), tm.data)
        pp_qaput!(tm, 2, "IRE_FLO import commodity not in TOP_IRE")
        qput!(qalog(tm), " WARNING        -    R=" * qlab12(r) * " P=" * qlab12(p) * " C=" * c)
    end
    # L27-33: LOOP(UNCD7(REG,V,P,COM,R,C,L), TS_ARRAY(S) = IRE_FLO(REG,V,P,COM,R,C,S);
    #   IRE_FLO(REG,V,P,COM,R,C,TS)$((NOT TS_ARRAY(TS))$PRC_TS(R,P,TS)) $= SUM(RS_TREE(FINEST(R,S),TS), ...)/G_YRFR(R,TS))
    for row in gams_sort!(collect(rows), tm.data)
        key(s) = (row..., s)
        arr = Dict{String,Float64}(s => flo[key(s)] for s in tr.all_ts if haskey(flo, key(s)))
        for ts in get(pts_of, (row[5], row[3]), none)
            haskey(arr, ts) && continue
            y = level_br(tr, arr, row[5], ts)
            iszero(y) || gassign!(flo, key(ts), y)
        end
        ts_array = arr
    end
    # L36: IRE_FLO(RTP(REG,V,P),COM,R,C,S)$((NOT IRE_FLO(REG,V,P,COM,R,C,S))$PRC_TS(R,P,S)) $= IRE_FLO(REG,V,P,COM,R,C,'ANNUAL')
    put = Pair{NTuple{7,String},Float64}[]
    for (k, x) in flo
        (k[7] == "ANNUAL" && k[2] in modl && (k[1], k[2], k[3]) in rtp && k[4] in com && k[5] in reg && k[6] in com) || continue
        foreach(s -> haskey(flo, (k[1:6]..., s)) || push!(put, (k[1:6]..., s) => x), get(pts_of, (k[5], k[3]), none))
    end
    foreach(((k, x),) -> (flo[k] = x), put)
    # L37: OPTION CLEAR=TRACKPC, CLEAR=UNCD7
    uncd7 = Set{NTuple{7,String}}()

    # --- L858-863: endogenous trade indicators --------------------------------------------------------
    top_ire = gmembers(tm, "TOP_IRE", 5)                                # (R,C,REG,COM,P): C of R to COM of REG
    ireio = gmembers(tm, "RPC_IREIO", 5)
    # L858-859: OPTION CLEAR=RXX; LOOP(TOP_IRE(R,C,REG,COM,P),RXX(R,C,P) = YES; RPC_IREIO(REG,P,COM,'IMP','IN') = YES)
    rxx = Set{NTuple{3,String}}()
    for k in top_ire
        (k[1] in reg && k[2] in com && k[3] in reg && k[4] in com) || continue
        push!(rxx, (k[1], k[2], k[5]))
        push!(ireio, (k[3], k[5], k[4], "IMP", "IN"))
    end
    # L860: RPC_IREIO(R,P,C,'EXP','IN')$RXX(R,C,P) = YES
    foreach(k -> push!(ireio, (k[1], k[3], k[2], "EXP", "IN")), rxx)
    # L861: RPC_IREIO(RPC_IRE(R,P,C,IE),'OUT')$(NOT RPC_IREIO(R,P,C,IE,'IN')) = YES
    foreach(k -> (k[1] in reg && !((k..., "IN") in ireio)) && push!(ireio, (k..., "OUT")), rpc_ire)
    gput!(tm, "RPC_IREIO", ireio)
    # L862: PRC_MAP(R,'DISTR',P)$PRC_MAP(R,'CORR',P) = YES; L863: IRE_DIST(RP_IRE(R,P))$PRC_MAP(R,'DISTR',P) = YES
    pmap = gmembers(tm, "PRC_MAP", 3)
    foreach(k -> (k[2] == "CORR" && k[1] in reg) && push!(pmap, (k[1], "DISTR", k[3])), collect(pmap))
    gput!(tm, "PRC_MAP", pmap)
    dist = gmembers(tm, "IRE_DIST", 2)
    foreach(k -> (k[1], "DISTR", k[2]) in pmap && push!(dist, k), gset_opt(tm.data, "RP_IRE", 2).keys)
    gput!(tm, "IRE_DIST", dist)

    # --- L866-876: the marketplaces ---------------------------------------------------------------------
    market = gmembers(tm, "RPC_MARKET", 4)
    regtop = [k for k in top_ire if k[1] in reg && k[2] in com && k[3] in reg && k[4] in com]
    out_of = by(regtop, k -> (k[1], k[2], k[5]), k -> (k[3], k[4]))      # (R,C,P) => (REG,COM)
    # L866: LOOP(RXX(R,C,P)$(SUM(TOP_IRE(R,C,REG,COM,P),1) GT 1),RPC_MARKET(R,P,C,'EXP') = YES)
    foreach(k -> length(get(out_of, k, none)) > 1 && push!(market, (k[1], k[3], k[2], "EXP")), rxx)
    # L867: RXX(R,C,P)$IRE_DIST(R,P) = NO
    filter!(k -> !((k[1], k[3]) in dist), rxx)
    # L868: LOOP(TOP_IRE(REG,COM,RXX(R,C,P))$(NOT SUM(COM1$TOP_IRE(R,C,REG,COM1,P),1)),RPC_MARKET(R,P,C,'EXP') = YES)
    for k in regtop
        (k[3], k[4], k[5]) in rxx || continue
        any(o -> o[1] == k[1], get(out_of, (k[3], k[4], k[5]), none)) || push!(market, (k[3], k[5], k[4], "EXP"))
    end
    # L871: TRACKPC(IRE_DIST(R,P),C)$RPC_MARKET(R,P,C,'EXP') = YES
    trackpc = Set{NTuple{3,String}}((k[1], k[2], k[3]) for k in market if k[4] == "EXP" && (k[1], k[2]) in dist && k[1] in reg)
    # L872-876: WHILE(CARD(TRACKPC), OPTION CLEAR=RXX;
    #   LOOP((TRACKPC(R,P,C),TOP_IRE(R,C,REG,COM,P),RPC_IRE(REG,P,COM1,'EXP')),
    #     IF(NOT SUM(COM2$TOP_IRE(REG,COM1,R,COM2,P),1),RXX(REG,P,COM1)=YES));
    #   OPTION CLEAR=TRACKPC; TRACKPC(RXX(R,P,C))$(NOT RPC_MARKET(R,P,C,'EXP')) = YES; RPC_MARKET(TRACKPC,'EXP') = YES)
    exp_of = by([k for k in rpc_ire if k[4] == "EXP" && k[1] in reg && k[3] in com], k -> (k[1], k[2]), k -> k[3])
    while !isempty(trackpc)
        rxx = Set{NTuple{3,String}}()
        for (r, p, c) in trackpc, (g, cm) in get(out_of, (r, c, p), none), c1 in get(exp_of, (g, p), none)
            any(o -> o[1] == r, get(out_of, (g, c1, p), none)) || push!(rxx, (g, p, c1))
        end
        trackpc = Set{NTuple{3,String}}(k for k in rxx if !((k..., "EXP") in market))
        foreach(k -> push!(market, (k..., "EXP")), trackpc)
    end
    gput!(tm, "RXX", rxx)

    # --- L878-891: the import commodities of the marketplaces --------------------------------------------
    # L880-888: LOOP(RPC_MARKET(R,P,C,IE)$(NOT SUM(TOP_IRE(R,C,R,COM,P),1)), Z=SUM(RPC_IRE(R,P,COM,'IMP'),1)+EPS;
    #   IF(IRE_DIST(R,P),IF(Z GT 1, <warning>) ELSEIF Z=1, Z=SUM(COM$RPC_MARKET(R,P,COM,'EXP'),1));
    #   IF(Z EQ 1, LOOP(RPC_IRE(R,P,COM,'IMP'), Z=0; CG_GRP(R,P,C,COM) = YES)); IF(Z,CG_GRP(R,P,C,C) = YES))
    imp_of = by([k for k in rpc_ire if k[4] == "IMP" && k[3] in com], k -> (k[1], k[2]), k -> k[3])
    cg_grp = Set{NTuple{4,String}}()
    qa_group!(tm)                                                      # L878: PUTGRP=0
    for (r, p, c, ie) in gams_sort!([k for k in market if k[1] in reg && k[3] in com && k[4] in ie_set], tm.data)
        any(o -> o[1] == r, get(out_of, (r, c, p), none)) && continue
        Z = GNum(Float64(length(get(imp_of, (r, p), none)))) + GEPS
        if (r, p) in dist
            # L883-885: IF(Z GT 1, pp_qaput 01 'Unsupported diverging trade topology';
            #   PUT QLOG ' WARNING       - Too complex topology:  R=',%RL%,' P=',P.TL)
            if Z.v > 1
                pp_qaput!(tm, 1, "Unsupported diverging trade topology")
                qput!(qalog(tm), " WARNING       - Too complex topology:  R=" * qlab12(r) * " P=" * p)
            end
        elseif Z.v == 1
            Z = GNum(Float64(count(k -> k[1] == r && k[2] == p && k[4] == "EXP" && k[3] in com, market)))
        end
        if Z.v == 1
            for cm in get(imp_of, (r, p), none)
                Z = GZERO
                push!(cg_grp, (r, p, c, cm))
            end
        end
        iszero(Z) || push!(cg_grp, (r, p, c, c))
    end
    # L889: LOOP(CG_GRP(R,P,C,COM),RC_RC(R,C,R,COM) = YES); L890: TOP_IRE(RC_RC(R,C,R,COM),P)$CG_GRP(R,P,C,COM) = YES
    rc_rc = gmembers(tm, "RC_RC", 4)
    foreach(k -> push!(rc_rc, (k[1], k[3], k[1], k[4])), cg_grp)
    gput!(tm, "RC_RC", rc_rc)
    foreach(k -> push!(top_ire, (k[1], k[3], k[1], k[4], k[2])), cg_grp)
    # L891: OPTION CLEAR=CG_GRP
    gput!(tm, "CG_GRP", Set{NTuple{4,String}}())

    # --- L894-901: IRE_FLO of the marketplaces -----------------------------------------------------------
    # LOOP(TOP_IRE(R,C,R,COM,P), IF(IRE_DIST(R,P), IRE_FLO(RTP(R,V,P),C,R,COM,S)$((IRE_FLO(R,V,P,C,R,COM,S) EQ 0)$RPCS_VAR(R,P,COM,S)) = 1;
    #   ELSE F = SUM((RTP(R,T,P),S)$IRE_FLO(R,T,P,C,R,COM,S),1);
    #     LOOP((REG,COM1)$(TOP_IRE(R,C,REG,COM1,P)$(NOT F)), F = SUM((RTP(R,T,P),S)$IRE_FLO(R,T,P,C,REG,COM1,S),1);
    #       IF(F, IRE_FLO(RTP(R,V,P),C,R,COM,S)$RPCS_VAR(R,P,COM,S) = IRE_FLO(R,V,P,C,REG,COM1,S)))))
    vs_of = by([k for k in rtp if k[2] in modl], k -> (k[1], k[3]), k -> k[2])
    ts_of_rtp = by([k for k in rtp if k[2] in tmem], k -> (k[1], k[3]), k -> k[2])
    cnt(r, p, c, g, cm) = (n = 0; for t in get(ts_of_rtp, (r, p), none), s in tr.all_ts
                               haskey(flo, (r, t, p, c, g, cm, s)) && (n += 1)
                           end; n)
    for (r, c, g0, cm, p) in gams_sort!([k for k in top_ire if k[1] in reg && k[1] == k[3] && k[2] in com && k[4] in com], tm.data)
        if (r, p) in dist
            for v in get(vs_of, (r, p), none), s in get(rpcs_of, (r, p, cm), none)
                gv(flo, (r, v, p, c, r, cm, s)).v == 0 && (flo[(r, v, p, c, r, cm, s)] = 1.0)
            end
        else
            F = GNum(Float64(cnt(r, p, c, r, cm)))
            for (g, c1) in gams_sort!([(k[3], k[4]) for k in top_ire if k[1] == r && k[2] == c && k[5] == p && k[3] in reg && k[4] in com], tm.data)
                iszero(F) || break
                F = GNum(Float64(cnt(r, p, c, g, c1)))
                iszero(F) && continue
                for v in get(vs_of, (r, p), none), s in get(rpcs_of, (r, p, cm), none)
                    gassign!(flo, (r, v, p, c, r, cm, s), gv(flo, (r, v, p, c, g, c1, s)))
                end
            end
        end
    end

    # --- L904-918: EQIRE and MARKET controls, shut-down periods ------------------------------------------
    # L904: LOOP(TOP_IRE(R,C,REG,COM,P)$RPC_MARKET(R,P,C,'EXP'),IF(NOT SAMEAS(R,REG),TRACKPC(REG,P,COM) = YES))
    trackpc = Set{NTuple{3,String}}()
    for k in top_ire
        (k[1] in reg && k[3] in reg && k[2] in com && k[4] in com && (k[1], k[5], k[2], "EXP") in market && k[1] != k[3]) && push!(trackpc, (k[3], k[5], k[4]))
    end
    # L905: RPC_EQIRE(RPC_IRE(R,P,C,'IMP'))$((NOT TRACKPC(R,P,C))$RPC_IREIO(R,P,C,'IMP','IN')) = YES
    eqire = gmembers(tm, "RPC_EQIRE", 4)
    foreach(k -> (k[4] == "IMP" && k[1] in reg && !((k[1], k[2], k[3]) in trackpc) && (k..., "IN") in ireio) && push!(eqire, k), rpc_ire)
    # L909-912: LOOP(TOP_IRE(R,C,R,COM,P), IF(NOT RPC_EQIRE(R,P,COM,'IMP'), RPC_EQIRE(R,P,C,'EXP') = YES;
    #   ELSEIF RPC_MARKET(R,P,C,'EXP'), IF(IRE_DIST(R,P), RPC_EQIRE(R,P,C,'EXP') = YES; ELSE RPC_MARKET(R,P,COM,'IMP') = YES)))
    diag = [k for k in top_ire if k[1] in reg && k[1] == k[3] && k[2] in com && k[4] in com]
    for (r, c, _, cm, p) in diag
        if !((r, p, cm, "IMP") in eqire)
            push!(eqire, (r, p, c, "EXP"))
        elseif (r, p, c, "EXP") in market
            (r, p) in dist ? push!(eqire, (r, p, c, "EXP")) : push!(market, (r, p, cm, "IMP"))
        end
    end
    gput!(tm, "RPC_EQIRE", eqire)
    gput!(tm, "RPC_MARKET", market)
    # L913: TOP_IRE(R,C,R,COM,P)$RPC_EQIRE(R,P,C,'EXP') = NO
    filter!(k -> !(k[1] == k[3] && k[1] in reg && k[2] in com && k[4] in com && (k[1], k[5], k[2], "EXP") in eqire), top_ire)
    gput!(tm, "TOP_IRE", top_ire)
    # L916: LOOP(RPC_MARKET(R,P,C,'EXP'),RTPC(REG,T,P,COM)$(TOP_IRE(R,C,REG,COM,P)$(NOT RTP_VARA(R,T,P))) = NO)
    # L918: LOOP(TOP_IRE(REG,C,R,COM,P)$RPC_EQIRE(R,P,COM,'IMP'),RTPC(REG,T,P,C)$(NOT RTP_VARA(R,T,P)) = NO)
    rtpc = gmembers(tm, "RTPC", 4)
    vara = gset(tm, "RTP_VARA").members
    for k in top_ire
        (k[1] in reg && k[3] in reg && k[2] in com && k[4] in com) || continue
        (r, c, g, cm, p) = k
        if (r, p, c, "EXP") in market
            foreach(t -> (r, t, p) in vara || delete!(rtpc, (g, t, p, cm)), tlist)
        end
        if (g, p, cm, "IMP") in eqire
            foreach(t -> (g, t, p) in vara || delete!(rtpc, (r, t, p, c)), tlist)
        end
    end
    gput!(tm, "RTPC", rtpc)
    # L921: RP_AIRE(RP_IRE(R,P),'EXP')$(RP_AIRE(R,P,'IMP')$IRE_DIST(R,P)) = NO
    aire = gmembers(tm, "RP_AIRE", 3)
    filter!(k -> !(k[3] == "EXP" && (k[1], k[2], "IMP") in aire && (k[1], k[2]) in dist && (k[1], k[2]) in gset_opt(tm.data, "RP_IRE", 2).members), aire)
    gput!(tm, "RP_AIRE", aire)

    # --- L924-926: IRE_FLOSUM of the activity moved to the PG commodities ---------------------------------
    # L924-925: IRE_FLOSUM(RTP(R,T,P),C,S,IE,COM,IO)$(RPC_PG(R,P,C)$RP_AIRE(R,P,IE)$IRE_FLOSUM(RTP,%PGPRIM%,S,IE,COM,IO)) =
    #   IRE_FLOSUM(RTP,%PGPRIM%,S,IE,COM,IO)*(1/PRC_ACTFLO(RTP,C)); L926: IRE_FLOSUM(R,T,P,%PGPRIM%,S,IE,COM,IO) = 0
    pg = uppercase(strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"']))
    ifs = gvalues(tm, "IRE_FLOSUM", 8)
    afl = gparam_opt(tm.data, "PRC_ACTFLO", 4).values
    pg_of = by(gset(tm, "RPC_PG").keys, k -> (k[1], k[2]), k -> k[3])
    old = [(k, x) for (k, x) in ifs if uppercase(k[4]) == pg && k[2] in tmem]
    for (k, x) in old
        ((k[1], k[2], k[3]) in rtp && (k[1], k[3], k[6]) in aire) || continue
        for c in get(pg_of, (k[1], k[3]), none)
            c in com && gassign!(ifs, (k[1], k[2], k[3], c, k[5:8]...), (x == 0.0 ? GEPS : GNum(x)) * (GNum(1.0) / gv(afl, (k[1], k[2], k[3], c))))
        end
    end
    filter!(((k, _),) -> !(uppercase(k[4]) == pg && k[2] in tmem && k[1] in reg), ifs)
    gput!(tm, "IRE_FLOSUM", ifs)

    # --- L931-933: IRE_FLO defaults ----------------------------------------------------------------------
    # LOOP(TOP_IRE(R,C,REG,COM,P), IF(NOT SUM((RTP(R,T,P),S)$IRE_FLO(R,T,P,C,REG,COM,S),1),
    #   IRE_FLO(RTP(R,V,P),C,REG,COM,S)$PRC_TS(REG,P,S) = 1))
    for (r, c, g, cm, p) in gams_sort!([k for k in top_ire if k[1] in reg && k[3] in reg && k[2] in com && k[4] in com], tm.data)
        cnt(r, p, c, g, cm) == 0 || continue
        for v in get(vs_of, (r, p), none), s in get(pts_of, (g, p), none)
            flo[(r, v, p, c, g, cm, s)] = 1.0
        end
    end
    gput!(tm, "IRE_FLO", flo)

    gput!(tm, "TRACKPC", Set{NTuple{3,String}}())
    gput!(tm, "UNCD7", uncd7)
    ts_array === nothing || gput!(tm, "TS_ARRAY", Dict{Tuple{String},Float64}((s,) => v for (s, v) in ts_array))
    gput_gnum!(tm, "Z", Z)
    gput_gnum!(tm, "F", F)
    return tm
end
