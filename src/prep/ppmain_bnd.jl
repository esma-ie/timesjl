# M1.3 (13a): ppmain.mod L936-1001 (docs/m13-plan.md): the commodity
# subsets (NRG, MAT, DEM, ENV, FIN) and the COM_LIM defaults of the balance
# type, the trade timeslice and commodity conversions (IRE_TSCVT,
# IRE_CCVT), the bounds given below their level aggregated to it
# (pp_lvlbd.mod for ACT_BND, FLO_FR, COM_BNDNET, COM_BNDPRD, IRE_BND), and
# FLO_BND and ACT_BND from the rate bounds FLO_BDLVL.
#
# GAMS: ppmain.mod L936-1001, pp_lvlbd.mod L22-46, v4.9.7.
#
# Index sets: R is REG, ALL_R and ALL_REG all regions, P is PRC, C is COM, CG
# is COM_GRP, S, TS and SL are ALL_TS, T is MILESTONYR, BD is BND_TYPE (LO,
# FX, UP), LIM the limit types, IE is IMPEXP. RTP, RTC and RTPC with T run
# over the milestones (G8, G27). `$x` is true for EPS (G3) and `NOT x` false
# (G25); a numeric comparison takes EPS as 0 (G12); `$=` writes only a
# nonzero or EPS value (G24); a right-hand side that names the symbol being
# assigned reads it as it was before the statement (G11); `OPTION a < b`
# fills each position of `a` from the rightmost unmatched position of `b` of
# the same domain (G26, G34). The QA log (L989, pp_lvlbd.mod L31-33) is
# written in LOOP order (M1.3 change 25b-1).

"""
    ppmain_bnd_unported(tm) -> Vector{String}

What ppmain.mod L936-1001 meets that is not translated: TIMES-MACRO and
TIMES-MICRO (L962-963).
"""
function ppmain_bnd_unported(tm)
    yes(n) = uppercase(gswitch(tm, n, "")) == "YES"
    out = String[]
    yes("MACRO") && push!(out, "ppmain.mod L962 (%MACRO% YES: TIMES-MACRO)")
    yes("MICRO") && push!(out, "ppmain.mod L963 (%MICRO% YES: TIMES-MICRO)")
    return out
end

"""
    ppmain_bnd_symbols(tm) -> Vector{String}

The symbols ppmain.mod L936-1001 settles that nothing later in the prelv ->
ppm segment changes (for the layer-1 check at the ppm checkpoint): the
commodity subsets (DEM too, which change 10 left to the replay), COM_LIM,
the trade conversions, the aggregated bounds and FLO_BND; ACT_BND when
%REDUCE% is NO (pp_reduce.red L167-168). Left out: RXX (L1165) and the
scratch, which the replay checks at L1001.
"""
function ppmain_bnd_symbols(tm)
    out = ["NRG", "MAT", "DEM", "ENV", "FIN", "COM_LIM", "RREG", "IRE_TSCVT", "IRE_CCVT", "RC_RC", "FLO_FR", "COM_BNDNET",
           "COM_BNDPRD", "IRE_BND", "FLO_BDLVL", "FLO_BND"]
    strip(gswitch(tm, "REDUCE", "")) == "NO" && push!(out, "ACT_BND")
    return out
end

"""
    ppmain_bnd!(tm) -> tm

ppmain.mod L936-1001 on the state after `ppmain_ire!`.

GAMS: ppmain.mod L936-1001, v4.9.7.
"""
function ppmain_bnd!(tm)
    u = ppmain_bnd_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    tr = TsTree(tm)
    reg = tr.reg
    tmem = Set(k[1] for k in gset(tm, "MILESTONYR").keys)
    rc = gset(tm, "RC").members
    member(s) = Set(k[1] for k in gset(tm, s).keys)
    com = member("COM")
    Z, F = gscal(tm, "Z"), gscal(tm, "F")
    # L943-947: NRG|MAT|DEM|ENV|FIN(RC(R,C))$COM_TMAP(R,'NRG'|...,C) = YES
    tmap = gset(tm, "COM_TMAP").members
    sub = Dict{String,Set{NTuple{2,String}}}()
    for n in ("NRG", "MAT", "DEM", "ENV", "FIN")
        s = gmembers(tm, n, 2)
        foreach(k -> (k[1], n, k[2]) in tmap && push!(s, k), rc)
        gput!(tm, n, s)
        sub[n] = s
    end
    # L950-959: the COM_LIM defaults
    lim = gmembers(tm, "COM_LIM", 3)
    trackc = Set{NTuple{2,String}}(rc)                                  # L950
    limset = member("LIM")
    foreach(k -> k[3] in limset && delete!(trackc, (k[1], k[2])), lim)  # L951
    ntmap = gset(tm, "NRG_TMAP").members
    for (r, c) in trackc                                                # L952
        ((r, c) in sub["NRG"] && ((r, "CONSRV", c) in ntmap || (r, "FRERENEW", c) in ntmap)) && push!(lim, (r, c, "UP"))
    end
    filter!(k -> !((k..., "UP") in lim), trackc)                        # L954
    foreach(k -> (k in sub["MAT"] || k in sub["FIN"]) && push!(lim, (k..., "FX")), trackc)   # L955-956
    filter!(k -> !((k..., "FX") in lim), trackc)                        # L957
    foreach(k -> push!(lim, (k..., "LO")), trackc)                      # L958
    gput!(tm, "COM_LIM", lim)

    # --- L969-984: inter-regional conversions ----------------------------------------------------------
    top_ire = gset(tm, "TOP_IRE").members
    # L969: OPTION RREG <= TOP_IRE; OPTION CLEAR=RXX
    rreg = project(top_ire, (1, 3))
    gput!(tm, "RREG", rreg)
    grp = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> pushat!(grp, (k[1], k[2]), k[3]), gset(tm, "TS_GROUP").keys)
    tsg = gset(tm, "TS_GROUP").members
    tslvl = [k[1] for k in gset(tm, "TSLVL").keys]
    # L970-976: LOOP(RREG(ALL_R,ALL_REG), Z=1; LOOP(TSLVL$Z, Z$Z = PROD(TS_GROUP(ALL_R,TSLVL,S),TS_GROUP(ALL_REG,TSLVL,S));
    #   Z$Z = PROD(TS_GROUP(ALL_REG,TSLVL,S),TS_GROUP(ALL_R,TSLVL,S)); IF(Z, RXX(ALL_R,S,ALL_REG)$TS_GROUP(ALL_R,TSLVL,S) = YES)))
    rxx = Set{NTuple{3,String}}()
    for (a, b) in gams_sort!(collect(rreg), tm.data)
        Z = GNum(1.0)
        for l in tslvl
            iszero(Z) && break
            all(s -> (b, l, s) in tsg, get(grp, (a, l), String[])) || (Z = GZERO)
            iszero(Z) || all(s -> (a, l, s) in tsg, get(grp, (b, l), String[])) || (Z = GZERO)
            iszero(Z) || foreach(s -> push!(rxx, (a, s, b)), get(grp, (a, l), String[]))
        end
    end
    # L977: RXX(ALL_R,S,ALL_REG)$RXX(ALL_REG,S,ALL_R) = YES
    union!(rxx, Set((k[3], k[2], k[1]) for k in rxx))
    gput!(tm, "RXX", rxx)
    # L978: IRE_TSCVT(RXX(ALL_R,S,ALL_REG),S)$(NOT IRE_TSCVT(ALL_R,S,ALL_REG,S)) = 1
    tscvt = gvalues(tm, "IRE_TSCVT", 4)
    foreach(k -> haskey(tscvt, (k..., k[2])) || (tscvt[(k..., k[2])] = 1.0), rxx)
    gput!(tm, "IRE_TSCVT", tscvt)
    # L981-982: OPTION RC_RC < IRE_CCVT; IRE_CCVT(RC_RC(RC,R,C))$(NOT IRE_CCVT(RC_RC)) = 1/IRE_CCVT(R,C,RC)
    ccvt = gvalues(tm, "IRE_CCVT", 4)
    rc_rc = project(keys(ccvt), (3, 4, 1, 2))
    for k in rc_rc
        ((k[1], k[2]) in rc && k[3] in reg && k[4] in com && !haskey(ccvt, k)) || continue
        gassign!(ccvt, k, GNum(1.0) / gv(ccvt, (k[3], k[4], k[1], k[2])))
    end
    # L983: OPTION RC_RC <= TOP_IRE; IRE_CCVT(RC_RC)$(NOT IRE_CCVT(RC_RC)) = 1; L984: the same with <
    for pos in ((1, 2, 3, 4), (3, 4, 1, 2))
        rc_rc = project(top_ire, pos)
        foreach(k -> haskey(ccvt, k) || (ccvt[k] = 1.0), rc_rc)
    end
    gput!(tm, "IRE_CCVT", ccvt)
    gput!(tm, "RC_RC", rc_rc)

    # --- L989-995: bounds below their level aggregated (pp_lvlbd.mod) ---------------------------------
    qa_group!(tm)                                                      # L989: PUTGRP = 0
    by(itr, f, g) = (d = Dict{Any,Vector{Any}}(); foreach(k -> pushat!(d, f(k), g(k)), itr); d)
    rtp, rtc = gset(tm, "RTP").members, gset(tm, "RTC").members
    pts_of = by(gset(tm, "PRC_TS").keys, k -> (k[1], k[2]), k -> k[3])
    rpcs_of = by(gset(tm, "RPCS_VAR").keys, k -> (k[1], k[2], k[3]), k -> k[4])
    cts_of = by(gset(tm, "COM_TS").keys, k -> (k[1], k[2]), k -> k[3])
    rps_prcts, rpcsv, rcs_comts = gset(tm, "RPS_PRCTS").members, gset(tm, "RPCS_VAR").members, gset(tm, "RCS_COMTS").members
    ie_set, allreg, prc = member("IE"), member("ALL_REG"), member("PRC")
    #   ACT_BND    P '' '' ''          PRC_TS RPS_PRCTS RTPS_BD EPS
    Z, F = pp_lvlbd!(tm, tr, "ACT_BND", 5, 4, Z, F; domok=k -> k[2] in tmem && k[3] in prc, rt=k -> (k[1], k[2], k[3]) in rtp,
                     targets=k -> get(pts_of, (k[1], k[3]), String[]), valid=(k, s) -> (k[1], k[3], s) in rps_prcts, neg=GEPS,
                     tsname="PRC_TS", idx="P")
    #   FLO_FR     P C, '' ",''"       RPCS_VAR RPCS_VAR UNCD7 0
    Z, F = pp_lvlbd!(tm, tr, "FLO_FR", 6, 5, Z, F; domok=k -> k[2] in tmem && k[3] in prc && k[4] in com, rt=k -> (k[1], k[2], k[3]) in rtp,
                     targets=k -> get(rpcs_of, (k[1], k[3], k[4]), String[]), valid=(k, s) -> (k[1], k[3], k[4], s) in rpcsv, neg=GZERO,
                     tsname="RPCS_VAR", idx="P")
    #   COM_BNDNET C '' '' ",'',''"    COM_TS RCS_COMTS UNCD7;  COM_BNDPRD the same
    for n in ("COM_BNDNET", "COM_BNDPRD")
        Z, F = pp_lvlbd!(tm, tr, n, 5, 4, Z, F; domok=k -> k[2] in tmem && k[3] in com, rt=k -> (k[1], k[2], k[3]) in rtc,
                         targets=k -> get(cts_of, (k[1], k[3]), String[]), valid=(k, s) -> (k[1], k[3], s) in rcs_comts, neg=nothing,
                         tsname="COM_TS", idx="C")
    end
    #   IRE_BND    C '' 'ALL_R,IE,' '' COM_TS RCS_COMTS UNCD7 EPS
    Z, F = pp_lvlbd!(tm, tr, "IRE_BND", 7, 4, Z, F; domok=k -> k[2] in tmem && k[3] in com && k[5] in allreg && k[6] in ie_set, rt=k -> (k[1], k[2], k[3]) in rtc,
                     targets=k -> get(cts_of, (k[1], k[3]), String[]), valid=(k, s) -> (k[1], k[3], s) in rcs_comts, neg=GEPS,
                     tsname="COM_TS", idx="C")

    # --- L998-1001: bounds from the rate levels ----------------------------------------------------------
    bdl = gvalues(tm, "FLO_BDLVL", 6)
    fbnd = gvalues(tm, "FLO_BND", 6)
    # L998: FLO_BDLVL(RTP,CG,S,BD)$FLO_BND(RTP,CG,S,BD) = 0
    filter!(((k, _),) -> !((k[1], k[2], k[3]) in rtp && haskey(fbnd, k)), bdl)
    gput!(tm, "FLO_BDLVL", bdl)
    bdset = member("BD")
    rtpc = gset(tm, "RTPC").members
    ctype = member("COM_TYPE")
    rp_ire, rp_stg = gset_opt(tm.data, "RP_IRE", 2).members, gset_opt(tm.data, "RP_STG", 2).members
    pg = uppercase(strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"']))
    abnd = gvalues(tm, "ACT_BND", 5)
    rate(k, x) = (x == 0.0 ? GEPS : GNum(x)) * gv(tr.yrfr, (k[1], k[5])) * GNum(8760.0)
    for (k, x) in bdl
        (k[2] in tmem && k[6] in bdset && (k[1], k[2], k[3]) in rtp) || continue
        (r, t, p, g, s, b) = k
        # L999: FLO_BND(RTPC(R,T,P,C),S,BD)$(RPCS_VAR(R,P,C,S)$FLO_BDLVL(RTPC,S,BD)) = FLO_BDLVL(RTPC,S,BD)*G_YRFR(R,S)*8760
        ((r, t, p, g) in rtpc && (r, p, g, s) in rpcsv) && gassign!(fbnd, k, rate(k, x))
        # L1000: FLO_BND(RTP(R,T,P),CG(COM_TYPE),S,BD)$(PRC_TS(R,P,S)$RP_IRE(R,P)$FLO_BDLVL(RTP,CG,S,BD)) = ...
        (g in ctype && s in get(pts_of, (r, p), String[]) && (r, p) in rp_ire) && gassign!(fbnd, k, rate(k, x))
        # L1001: ACT_BND(RTP(R,T,P),S,BD)$((RP_STG(R,P)->0)$PRC_TS(R,P,S)$FLO_BDLVL(RTP,%PGPRIM%,S,BD)) = ...
        (uppercase(g) == pg && !((r, p) in rp_stg) && s in get(pts_of, (r, p), String[])) && gassign!(abnd, (r, t, p, s, b), rate(k, x))
    end
    gput!(tm, "FLO_BND", fbnd)
    gput!(tm, "ACT_BND", abnd)
    gput_gnum!(tm, "Z", Z)
    gput_gnum!(tm, "F", F)
    return tm
end

"""
    pp_lvlbd!(tm, tr, name, N, sp, Z, F; domok, rt, targets, valid, neg, tsname, idx) -> (Z, F)

pp_lvlbd.mod: the bound attribute `name` (N indexes, S at `sp` and BD last)
given at timeslices outside the valid levels (%7, `valid(key, s)`) is
aggregated to each target timeslice (%6, `targets(key)`) that has no value
of its own: LO/UP from FX, the values under a higher one cleared, an UP
kept only when the values below cover the whole target, the sums set as the
target's bounds (FX when they meet). A conflict with a value at the target
leaves the lower ones. `neg` (%9) replaces negative LO/UP below (EPS, 0, or
`nothing` for none). LO and UP are then dropped where FX is given. `domok`
holds the domains of the controlling indexes (T a milestone, %2-%4), `rt`
the RTP or RTC membership the flags of L24 need. The
scratch TS_BD and BDVAL are stored as GAMS leaves them. A conflict is
written to the QA log (L31-33): `tsname` is %6, `idx` %2 ('P' or 'C').

GAMS: pp_lvlbd.mod L22-46, v4.9.7.
"""
function pp_lvlbd!(tm, tr::TsTree, name, N, sp, Z, F; domok, rt, targets, valid, neg, tsname::String, idx::String)
    x = gvalues(tm, name, N)
    bds = [k[1] for k in gset(tm, "BD").keys]
    bdneq = Set(k[1] for k in gset(tm, "BDNEQ").keys)
    rowof(k) = (k[1:sp-1]..., k[sp+1:N-1]...)
    keyat(row, s, b) = (row[1:sp-1]..., s, row[sp:end]..., b)
    # L24: %8(RT%2(R,T,%2),%3S--ORD(S),%4'FX'%5) $= SUM(BD$%1(RT%2,%3S,%4BD),1)$(NOT %7(R,%2,%3S))
    rows = Set{NTuple{N - 2,String}}()
    for k in keys(x)
        (k[N] in bds && k[1] in tr.reg && domok(k) && rt(k) && !valid(k, k[sp])) && push!(rows, rowof(k))
    end
    ts_bd = gvalues(tm, "TS_BD", 2)
    bdval = gmembers(tm, "BDVAL", 1)
    # L27: LOOP((%8(R,T,%2,%3ALL_TS,%4'FX'%5),%6(R,%2,%3TS)), ...)
    for row in gams_sort!(collect(rows), tm.data)
        r = row[1]
        k0 = keyat(row, "ANNUAL", "FX")
        for ts in targets(k0)
            # L28: TS_BD(S,BD) = %1(R,T,%2,%3S,%4BD)$TS_MAP(R,TS,S)
            ts_bd = Dict{NTuple{2,String},Float64}()
            for s in tr.all_ts, b in bds
                (r, ts, s) in tr.tsmap || continue
                y = get(x, keyat(row, s, b), nothing)
                y === nothing || (ts_bd[(s, b)] = y)
            end
            # L29: TS_BD(S,BDNEQ) $= TS_BD(S,'FX'); Z=SUM(BD$TS_BD(TS,BD),1); F=CARD(TS_BD)-Z
            for ((s, b), y) in collect(ts_bd)
                b == "FX" && foreach(n -> (ts_bd[(s, n)] = y), bdneq)
            end
            nts = count(b -> haskey(ts_bd, (ts, b)), bds)
            Z = GNum(Float64(nts))
            F = GNum(Float64(length(ts_bd) - nts))
            # L30: IF(Z>1,Z=F; ELSE Z=SUM((RS_BELOW(R,TS,S),BDNEQ(BD))$(TS_BD(S,BD)$TS_BD(TS,BD)),1)$F)
            if Z.v > 1
                Z = F
            else
                n = 0
                for s in get(tr.below, (r, ts), String[]), b in bdneq
                    (haskey(ts_bd, (s, b)) && haskey(ts_bd, (ts, b))) && (n += 1)
                end
                Z = iszero(F) ? GZERO : GNum(Float64(n))
            end
            # L31-33: IF(Z, F=(F>Z); pp_qaput 01 '%1 Bounds conflict: Value at %6 level and below, latter ignored';
            #   PUT QLOG ' WARNING       -     %1:  R=',%RL%,' Y=',T.TL,' %2=',%2.TL,' S=',TS.TL)
            if !iszero(Z)
                F = GNum(F.v > Z.v ? 1.0 : 0.0)
                pp_qaput!(tm, 1, name * " Bounds conflict: Value at " * tsname * " level and below, latter ignored")
                qput!(qalog(tm), " WARNING       -     " * name * ":  R=" * qlab12(r) * " Y=" * row[2] * " " * idx * "=" * row[3] *
                                 " S=" * ts)
            end
            iszero(F) && continue
            # L34: BDVAL(BD)=(NOT TS_BD(TS,BD))$BDNEQ(BD)
            bdval = Set{Tuple{String}}((b,) for b in bds if b in bdneq && !haskey(ts_bd, (ts, b)))
            # L36: TS_BD(S,BDNEQ)$(TS_BD(S,BDNEQ)<0) = %9
            if neg !== nothing
                for ((s, b), y) in collect(ts_bd)
                    (b in bdneq && y < 0) && gassign!(ts_bd, (s, b), neg)
                end
            end
            # L37: TS_BD(S,BDVAL(BD))$SUM(RS_BELOW(R,SL,S)$TS_BD(SL,BD),1)=0   (read before the statement)
            old = copy(ts_bd)
            for ((s, b), _) in old
                (b,) in bdval || continue
                any(sl -> haskey(old, (sl, b)), get(tr.above, (r, s), String[])) && delete!(ts_bd, (s, b))
            end
            # L39: BDVAL(BDVAL('UP')) = (G_YRFR(R,TS)-SUM(RS_BELOW(R,TS,S)$TS_BD(S,'UP'),G_YRFR(R,S))) < 1E-5
            if ("UP",) in bdval
                cov = reduce(+, (yrfr_at(tr, r, s) for s in get(tr.below, (r, ts), String[]) if haskey(ts_bd, (s, "UP"))); init=GZERO)
                (yrfr_at(tr, r, ts) - cov).v < 1e-5 || delete!(bdval, ("UP",))
            end
            # L40: TS_BD(TS,BDVAL)=SUM(RS_BELOW(R,TS,S),TS_BD(S,BDVAL))
            for (b,) in bdval
                gassign!(ts_bd, (ts, b), reduce(+, (gv(ts_bd, (s, b)) for s in get(tr.below, (r, ts), String[])); init=GZERO))
            end
            # L41-43: IF((TS_BD(TS,'UP')-TS_BD(TS,'LO') < 1E-7)$(SUM(BD$TS_BD(TS,BD),1)=2), %1(R,T,%2,%3TS,%4'FX') = TS_BD(TS,'LO');
            #   ELSE %1(R,T,%2,%3TS,%4BDVAL) $= TS_BD(TS,BDVAL))
            if count(b -> haskey(ts_bd, (ts, b)), bds) == 2 && (gv(ts_bd, (ts, "UP")) - gv(ts_bd, (ts, "LO"))).v < 1e-7
                gassign!(x, keyat(row, ts, "FX"), gv(ts_bd, (ts, "LO")))
            else
                for (b,) in bdval
                    haskey(ts_bd, (ts, b)) && (x[keyat(row, ts, b)] = ts_bd[(ts, b)])
                end
            end
        end
    end
    # L45: %1(R,T,%2,%3S,%4BDNEQ)$%1(R,T,%2,%3S,%4'FX') = 0
    for k in collect(keys(x))
        (k[N] == "FX" && k[1] in tr.reg && domok(k)) && foreach(b -> delete!(x, (k[1:N-1]..., b)), bdneq)
    end
    gput!(tm, name, x)
    gput!(tm, "TS_BD", ts_bd)
    gput!(tm, "BDVAL", bdval)
    return Z, F
end
