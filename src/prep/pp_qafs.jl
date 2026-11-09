# M1.3 (9): ppmain.mod L617, pp_qafs.mod, the QA checks of FLO_SHAR, at the
# start of the prelv -> ppm segment (docs/m13-plan.md): shares of commodities
# outside their group dropped, the groups of RPG_RED, FX with LO/UP, very
# small shares, the sums of fixed, FX+UP and FX+LO shares of a group, with
# the auto-relaxation (%SHARELAX%) of the share that makes a group
# infeasible.
#
# GAMS: ppmain.mod L617, pp_qafs.mod L1-110, v4.9.7.
#
# Index sets: R is REG, P is PRC, C is COM, CG is COM_GRP, V is MODLYEAR, S
# is ALL_TS, IO is IN_OUT, BD is BND_TYPE. RTP(R,V,P) and the shares at V
# run over MODLYEAR only (G8, G27). `S(TSL)` keeps the timeslices whose label
# is a timeslice level, 'ANNUAL' (G44). The circular lags `LL--ORD(LL)` and
# `S--ORD(S)` are the last elements of ALLYEAR ('0', G31) and ALL_TS. `$`
# binds tighter than NOT, so `NOT RPC(R,P,C)$COM_GMAP(R,CG,C)` is "not in
# RPC or not in the group" (G46). A loop with a `$`-condition on a scalar
# the loop body sets (`LOOP(RP_GIC(...)$Z, ...)`) stops at the first member
# that sets it to 0 (G46). Loops run in GAMS order. %SHARETOL% is 9E-5
# unless set; %SHARELAX% is on unless NO, and the `$IF` of L59 applies to
# L60 (G47).
#
# The QA log (L15-18, L31-34, L51-57, L72-80, L92-100, L109) is written in
# LOOP order (M1.3 change 25b-1). `1-%SHARETOL%$(NOT Z)` (L77) is 1 less
# the tolerance only where a share was relaxed: `$` binds to the operand
# before it. Not translated: the DISPLAY of L64, which goes to the listing.

"""
    pp_qafs_symbols(tm) -> Vector{String}

The symbols pp_qafs.mod settles that nothing later in the prelv -> ppm
segment changes (for the layer-1 check at the ppm checkpoint): RPG_RED and
the work sets it clears. Left out: FLO_SHAR (pp_chp.mod L53-58, pp_lvlbr.mod
at ppmain.mod L840), RTP_GRP (pp_lvlpk.mod L23), UNCD7 and the scratch Z, F,
MY_F (used again at once). Their values at L682 are checked by replay
(test/unit/test_m13_ppmain_dflt.jl, scripts/m13_replay.jl).
"""
pp_qafs_symbols(tm) = ["RPG_RED", "RP_CCG", "RTP_CGC", "RTPGIG", "RTP_CG", "RP_GIC"]

"The members of a set, in GAMS order."
gordered(tm, s::AbstractSet) = gams_sort!(collect(s), tm.data)

# a Dict of vectors: push! into the vector at `k`
pushat!(d::Dict, k, x) = push!(get!(() -> valtype(d)(), d, k), x)

"""
    pp_qafs!(tm) -> tm

pp_qafs.mod (ppmain.mod L617) on the state after `pp_prelv!`: RP_CCG and
RPG_RED, the groups RTP_CG with only ANNUAL shares; FX overriding LO/UP;
UP shares of 1 or more dropped, shares below %SHARETOL% made EPS and within
it of 1 made 1; groups whose fixed shares do not sum to 1, whose FX+UP
shares sum below 1 (UP turned into FX) or whose FX+LO shares sum to 1 or
more (LO turned into FX), each with one share dropped when %SHARELAX% is
on. The work sets are left as GAMS leaves them: cleared, but RPG_RED and
UNCD7.

GAMS: pp_qafs.mod L9-110, v4.9.7.
"""
function pp_qafs!(tm)
    tol = parse(Float64, strip(get(tm.switches, "SHARETOL", "9E-5")))                 # L41
    lax = uppercase(strip(get(tm.switches, "SHARELAX", ""))) != "NO"                 # L59, L76, L100
    fs = gvalues(tm, "FLO_SHAR", 7)
    modl = Set(k[1] for k in gset(tm, "MODLYEAR").keys)
    rtp = gset(tm, "RTP").members
    rpc = gset(tm, "RPC").members
    gmap = gset(tm, "COM_GMAP").members
    top = gset(tm, "TOP").members
    ios = [k[1] for k in gset(tm, "IN_OUT").keys]
    bdupx = [k[1] for k in gset(tm, "BDUPX").keys]
    bdlox = [k[1] for k in gset(tm, "BDLOX").keys]
    bdneq = Set(k[1] for k in gset(tm, "BDNEQ").keys)
    annual = Set(k[1] for k in gset(tm, "ANNUAL").keys)
    tsl = Set(k[1] for k in gset(tm, "TSLVL").keys)
    lastyear = gset(tm, "ALLYEAR").keys[end][1]
    lastts = gset(tm, "ALL_TS").keys[end][1]
    sh(r, v, p, c, cg, bd) = gv(fs, (r, v, p, c, cg, "ANNUAL", bd))
    topc = Dict{NTuple{3,String},Vector{String}}()                                # TOP(R,P,C,IO) by (R,P,IO)
    foreach(k -> pushat!(topc, (k[1], k[2], k[4]), k[3]), gordered(tm, top))

    # --- L15-27: the groups ----------------------------------------------------------------
    # L15: OPTION RP_CCG <= FLO_SHAR; PUTGRP=0   (RP_CCG(REG,PRC,C,CG): positions 1, 3, 4, 5, G26/G45)
    rp_ccg = Set{NTuple{4,String}}((k[1], k[3], k[4], k[5]) for k in keys(fs))
    qa_group!(tm)
    # L16-18: LOOP(RP_CCG(R,P,C,CG)$(NOT RPC(R,P,C)$COM_GMAP(R,CG,C)), pp_qaput 07 'Unsupported FLO_SHARE: C not in RPC or CG';
    #   PUT QLOG ' SEVERE ERROR  -     R=',%RL%,' P=',%PL%,' C=',C.TL,' CG=',CG.TL)
    bad = [k for k in rp_ccg if !((k[1], k[2], k[3]) in rpc && (k[1], k[4], k[3]) in gmap)]
    for (r, p, c, cg) in gams_sort!(bad, tm.data)
        pp_qaput!(tm, 7, "Unsupported FLO_SHARE: C not in RPC or CG")
        qput!(qalog(tm), " SEVERE ERROR  -     R=" * qlab12(r) * " P=" * qlab12(p) * " C=" * c * " CG=" * cg)
    end
    # L19: IF(PUTGRP, RP_CCG(R,P,C,CG)$(NOT COM_GMAP(R,CG,C)) = NO)
    isempty(bad) || filter!(k -> (k[1], k[4], k[3]) in gmap, rp_ccg)
    # L20-21: RTPGIG(R,'0',P,C,IO,CG)$(TOP(R,P,C,IO)$RP_CCG(R,P,C,CG)) = YES; then RPG_RED(R,P,CG,IO)
    rpg_red = gmembers(tm, "RPG_RED", 4)
    for (r, p, c, cg) in rp_ccg, io in ios
        (r, p, c, io) in top && push!(rpg_red, (r, p, cg, io))
    end
    # L22: RTP_CGC(R,V,P,C,CG) $= SUM(BD$FLO_SHAR(R,V,P,C,CG,'ANNUAL',BD),1)
    rtp_cgc = gmembers(tm, "RTP_CGC", 5)
    for k in keys(fs)
        (k[6] == "ANNUAL" && k[2] in modl) && push!(rtp_cgc, (k[1], k[2], k[3], k[4], k[5]))
    end
    # L23: RP_GIC(RPG_RED(R,P,CG,IO),C)$(TOP(R,P,C,IO)$COM_GMAP(R,CG,C)) = YES
    rp_gic = Set{NTuple{5,String}}()
    gic = Dict{NTuple{4,String},Vector{String}}()                                 # RP_GIC(R,P,CG,IO,C) by (R,P,CG,IO), C in GAMS order
    for (r, p, cg, io) in rpg_red, c in get(topc, (r, p, io), String[])
        (r, cg, c) in gmap && push!(rp_gic, (r, p, cg, io, c))
    end
    foreach(k -> pushat!(gic, k[1:4], k[5]), gordered(tm, rp_gic))
    gicio = Dict{NTuple{4,String},Vector{String}}()                               # RP_GIC by (R,P,CG,C): the IO
    foreach(k -> pushat!(gicio, (k[1], k[2], k[3], k[5]), k[4]), gordered(tm, rp_gic))
    # L24: RTP_CG(RTP(R,V,P),CG,IO) $= SUM(RTP_CGC(R,V,P,C,CG)$RP_GIC(R,P,CG,IO,C),1)
    rtp_cg = Set{NTuple{5,String}}()
    for (r, v, p, c, cg) in rtp_cgc
        (v in modl && (r, v, p) in rtp) || continue
        foreach(io -> push!(rtp_cg, (r, v, p, cg, io)), get(gicio, (r, p, cg, c), String[]))
    end
    # L25: OPTION CLEAR=UNCD7; UNCD7(R,LL--ORD(LL),P,C,CG,S--ORD(S),BD) $= FLO_SHAR(R,LL,P,C,CG,S,BD)$(NOT ANNUAL(S))
    uncd7 = Set{NTuple{7,String}}((k[1], lastyear, k[3], k[4], k[5], lastts, k[7]) for k in keys(fs) if !(k[6] in annual))
    # L26: LOOP((UNCD7(R,LL,P,C,CG,S,BD),RP_GIC(R,P,CG,IO,C)), RTP_CG(R,V,P,CG,IO) = NO)
    nonann = Set{NTuple{4,String}}()
    for u in uncd7, io in get(gicio, (u[1], u[3], u[5], u[4]), String[])
        push!(nonann, (u[1], u[3], u[5], io))
    end
    filter!(k -> !((k[1], k[3], k[4], k[5]) in nonann), rtp_cg)
    # L27: OPTION CLEAR=RTP_CGC, CLEAR=RTPGIG, CLEAR=RP_CCG
    empty!(rtp_cgc); empty!(rp_ccg)

    # --- L30-38: FX with LO/UP ----------------------------------------------------------------
    # L30: RTP_CGC(R,V,P,C,CG) $= FLO_SHAR(R,V,P,C,CG,'ANNUAL','FX')
    for k in keys(fs)
        (k[6] == "ANNUAL" && k[7] == "FX" && k[2] in modl) && push!(rtp_cgc, (k[1], k[2], k[3], k[4], k[5]))
    end
    # L32-37: RTPGIG(R,V,P,C,'OUT',CG) where LO+UP is nonzero (EPS too); FLO_SHAR(R,V,P,C,CG,S,BDNEQ)$RTPGIG(...) = 0
    conflict = Set{NTuple{5,String}}(k for k in rtp_cgc if !iszero(sh(k..., "LO") + sh(k..., "UP")))
    # L31-34: PUTGRP = 0; in LOOP order, pp_qaput 01 'FLO_SHAR conflict: Both FX + LO/UP specified, latter ignored';
    #   PUT QLOG ' WARNING       -     R=',%RL%,' Y=',V.TL,' P=',%PL%,' CG=',CG.TL,' C=',C.TL
    qa_group!(tm)
    for (r, v, p, c, cg) in gordered(tm, conflict)
        pp_qaput!(tm, 1, "FLO_SHAR conflict: Both FX + LO/UP specified, latter ignored")
        qput!(qalog(tm), " WARNING       -     R=" * qlab12(r) * " Y=" * v * " P=" * qlab12(p) * " CG=" * cg * " C=" * c)
    end
    filter!(kv -> !(kv[1][7] in bdneq && kv[1][1:5] in conflict), fs)

    # --- L42-44: the very small shares --------------------------------------------------------
    # L42: FLO_SHAR(RTP(R,V,P),C,CG,S(TSL),BD('UP'))$((FLO_SHAR(...)$COM_GMAP(R,CG,C) GE 1)$FLO_SHAR(...)) = 0
    filter!(fs) do (k, x)
        !(k[7] == "UP" && k[6] in tsl && k[2] in modl && (k[1], k[2], k[3]) in rtp && (k[1], k[5], k[4]) in gmap && x >= 1)
    end
    # L43: FLO_SHAR(R,V,P,C,CG,S,BDUPX(BD))$((FLO_SHAR LT %SHARETOL%)$FLO_SHAR) = EPS
    for (k, x) in fs
        (k[7] in bdupx && k[2] in modl && x < tol) && (fs[k] = 0.0)
    end
    # L44: FLO_SHAR(R,V,P,C,CG,S,BDLOX(BD))$((ABS(FLO_SHAR-1) LT %SHARETOL%)$FLO_SHAR) = 1
    for (k, x) in fs
        (k[7] in bdlox && k[2] in modl && abs(x - 1) < tol) && (fs[k] = 1.0)
    end

    # the groups RTP_CG with a member not in `inset` (RTP_GRP of L49-50, L70-71)
    function free_groups(inset)
        grp = Set{NTuple{5,String}}()
        for g in rtp_cg
            (r, v, p, cg, io) = g
            any(c -> !((r, v, p, c, cg) in inset), get(gic, (r, p, cg, io), String[])) && push!(grp, g)
        end
        return grp
    end
    scal(n) = gv(gparam_opt(tm.data, n, 0), ())
    Zg, Fg, MY_Fg = scal("Z"), scal("F"), scal("MY_F")                               # the scratch as the state leaves it

    # --- L49-65: the sums of fixed shares ---------------------------------------------------
    # L49-50: RTP_GRP: the groups with a member without FX (RTP_CGC of L30)
    rtp_grp = free_groups(rtp_cgc)
    # L52-61: the groups with all members fixed
    rtpgig = Set{NTuple{6,String}}()
    qa_group!(tm)                                                                     # L51: PUTGRP=0
    for g in gordered(tm, setdiff(rtp_cg, rtp_grp))
        (r, v, p, cg, io) = g
        cs = get(gic, (r, p, cg, io), String[])
        Zg = GZERO
        foreach(c -> (Zg += sh(r, v, p, c, cg, "FX") + GNum(8.0)), cs)                # L53
        Fg = GNum(rem(Zg.v, 8.0))                                                     # L54 (MOD keeps the sign, G43)
        # L55-57: IF(ABS(F-1) GT .001, pp_qaput 07 'Inconsistent sum of fixed FLO_SHAREs in Group';
        #   PUT QLOG ' SEVERE ERROR  -     R=',%RL%,' P=',%PL%,' V=',V.TL,' CG=',CG.TL,' SUM=',F:0:5)
        if abs(Fg.v - 1) > 0.001
            pp_qaput!(tm, 7, "Inconsistent sum of fixed FLO_SHAREs in Group")
            qput!(qalog(tm), " SEVERE ERROR  -     R=" * qlab12(r) * " P=" * qlab12(p) * " V=" * v * " CG=" * cg * " SUM=" * qnum(Fg, 0, 5))
        end
        Fg = gmax(Fg - GNum(1.0), Fg / Zg * GNum(8.0) - GNum(tol))                    # L58
        if lax                                                                        # L60
            for c in cs
                iszero(Zg) && break
                if sh(r, v, p, c, cg, "FX").v > Fg.v
                    Zg = GZERO
                    push!(rtpgig, (r, v, p, cg, io, c))
                end
            end
        end
    end
    # L62-64: IF(CARD(RTPGIG), LOOP(IO, FLO_SHAR(R,V,P,C,CG,S,BD)$RTPGIG(R,V,P,CG,IO,C) = 0); F=CARD(RTPGIG))
    if !isempty(rtpgig)
        drop = Set{NTuple{5,String}}((k[1], k[2], k[3], k[6], k[4]) for k in rtpgig)
        filter!(kv -> !((kv[1][1], kv[1][2], kv[1][3], kv[1][4], kv[1][5]) in drop), fs)
        Fg = GNum(Float64(length(rtpgig)))
    end
    # L65: OPTION CLEAR=RTP_GRP

    # (L82-87, L103-108) the members RTP_CGC(R,V,P,CG,C) of the groups with a dropped share
    function relaxed_members(rtpgig)
        grp = Set{NTuple{5,String}}()
        for io in ios, k in rtpgig                                                    # L82
            (r, v, p, cg, _, c) = k
            io in get(gicio, (r, p, cg, c), String[]) && push!(grp, (r, v, p, cg, io))
        end
        cgc = Set{NTuple{5,String}}()                                                 # L83
        for (r, v, p, cg, io) in grp, c in get(gic, (r, p, cg, io), String[])
            push!(cgc, (r, v, p, cg, c))
        end
        return cgc
    end

    # --- L68-87: FX+UP shares summing below 1 ------------------------------------------------
    # L68: RTP_CGC(R,V,P,C,CG) $= FLO_SHAR(R,V,P,C,CG,'ANNUAL','UP')   (adds to the FX members of L30)
    for k in keys(fs)
        (k[6] == "ANNUAL" && k[7] == "UP" && k[2] in modl) && push!(rtp_cgc, (k[1], k[2], k[3], k[4], k[5]))
    end
    rtp_grp = free_groups(rtp_cgc)                                                    # L70-71
    empty!(rtpgig)                                                                    # L72
    qa_group!(tm)                                                                     # L72: PUTGRP=0
    for g in gordered(tm, setdiff(rtp_cg, rtp_grp))                                   # L73
        (r, v, p, cg, io) = g
        cs = get(gic, (r, p, cg, io), String[])
        Fg = GZERO
        for c in cs, bd in bdupx                                                      # L74
            Fg += sh(r, v, p, c, cg, bd)
        end
        if Fg.v < 1 + tol                                                             # L75
            Zg = GNum(1.0)
            if lax                                                                    # L76
                for c in cs
                    iszero(Zg) && break
                    MY_Fg = sh(r, v, p, c, cg, "UP")
                    if MY_Fg.v > Fg.v - 1 && !iszero(MY_Fg)
                        Zg = GZERO
                        push!(rtpgig, (r, v, p, cg, "OUT", c))
                    end
                end
            end
            # L77-80: IF(F LT 1-%SHARETOL%$(NOT Z), pp_qaput 07 'Defective sum of FX and UP FLO_SHAREs in Group';
            #   PUT QLOG ' SEVERE ERROR  -     R=',%RL%,' P=',%PL%,' V=',V.TL,' CG=',CG.TL,' SUM=',F:0:5;
            #   IF(NOT Z,PUT QLOG ' (Auto-relaxed)'))
            if Fg.v < 1 - (iszero(Zg) ? tol : 0.0)
                pp_qaput!(tm, 7, "Defective sum of FX and UP FLO_SHAREs in Group")
                q = qalog(tm)
                qput!(q, " SEVERE ERROR  -     R=" * qlab12(r) * " P=" * qlab12(p) * " V=" * v * " CG=" * cg * " SUM=" * qnum(Fg, 0, 5))
                iszero(Zg) && qput!(q, " (Auto-relaxed)")
            end
        end
    end
    # L81-86: UP becomes FX in the groups with a dropped share, but for the dropped share; LO and UP removed
    cgc = relaxed_members(rtpgig)
    for k in collect(keys(fs))
        (k[6] == "ANNUAL" && k[7] == "UP" && k[2] in modl) || continue
        (r, v, p, c, cg) = (k[1], k[2], k[3], k[4], k[5])
        ((r, v, p, cg, c) in cgc && !((r, v, p, cg, "OUT", c) in rtpgig)) && (fs[(r, v, p, c, cg, "ANNUAL", "FX")] = fs[k])   # L84
    end
    filter!(kv -> !(kv[1][6] == "ANNUAL" && kv[1][7] in bdneq && (kv[1][1], kv[1][2], kv[1][3], kv[1][5], kv[1][4]) in cgc), fs)  # L86
    empty!(rtp_cgc)                                                                   # L87

    # --- L90-108: FX+LO shares summing to 1 or more -------------------------------------------
    # L90: RTP_CGC(R,V,P,C,CG) $= SUM(BDLOX$FLO_SHAR(R,V,P,C,CG,'ANNUAL',BDLOX),1)
    for k in keys(fs)
        (k[6] == "ANNUAL" && k[7] in bdlox && k[2] in modl) && push!(rtp_cgc, (k[1], k[2], k[3], k[4], k[5]))
    end
    # L91: LOOP((RP_GIC(R,P,CG,IO,C),RTP_CGC(R,V,P,C,CG)),RTP_GRP(R,V,P,CG,IO) = YES)
    rtp_grp = Set{NTuple{5,String}}()
    for (r, v, p, c, cg) in rtp_cgc, io in get(gicio, (r, p, cg, c), String[])
        push!(rtp_grp, (r, v, p, cg, io))
    end
    empty!(rtpgig)                                                                    # L92
    qa_group!(tm)                                                                     # L92: PUTGRP=0
    for g in gordered(tm, intersect(rtp_grp, rtp_cg))                                 # L93: LOOP(RTP_GRP(RTP_CG(R,V,P,CG,IO)), ...)
        (r, v, p, cg, io) = g
        cs = get(gic, (r, p, cg, io), String[])
        Fg = GZERO
        for c in cs, bd in bdlox                                                      # L94
            Fg += sh(r, v, p, c, cg, bd)
        end
        if Fg.v > 1 - tol                                                             # L95-101
            Zg, MY_Fg = GNum(1.0), GZERO
            if Fg.v > 1 + tol
                # L97-98: MY_F = 1; pp_qaput 07 'Excessive sum of FX and LO FLO_SHAREs in Group';
                #   PUT QLOG ' SEVERE ERROR  -     R=',%RL%,' P=',%PL%,' V=',V.TL,' CG=',CG.TL,' SUM=',F:0:5
                MY_Fg = GNum(1.0)
                pp_qaput!(tm, 7, "Excessive sum of FX and LO FLO_SHAREs in Group")
                qput!(qalog(tm), " SEVERE ERROR  -     R=" * qlab12(r) * " P=" * qlab12(p) * " V=" * v * " CG=" * cg * " SUM=" * qnum(Fg, 0, 5))
            end
            Fg = gmax(GZERO, Fg - GNum(1.0))
            for c in cs, bd in bdlox
                iszero(Zg) && break
                if sh(r, v, p, c, cg, bd).v > Fg.v
                    Zg = GZERO
                    # L100: $IF NOT %SHARELAX%==NO  RTPGIG(R,V,P,CG,'OUT',C) = YES; IF(MY_F,PUT QLOG ' (Auto-relaxed)')
                    if lax
                        push!(rtpgig, (r, v, p, cg, "OUT", c))
                        iszero(MY_Fg) || qput!(qalog(tm), " (Auto-relaxed)")
                    end
                end
            end
        end
    end
    # L102-107: FX = LO+FX+EPS in the groups with a dropped share; LO, UP and the dropped share removed
    cgc = relaxed_members(rtpgig)
    for (r, v, p, cg, c) in cgc                                                       # L105
        x = sh(r, v, p, c, cg, "LO") + sh(r, v, p, c, cg, "FX") + GEPS
        gassign!(fs, (r, v, p, c, cg, "ANNUAL", "FX"), x)
    end
    filter!(fs) do (k, x)                                                             # L107
        !(k[6] == "ANNUAL" && (k[1], k[2], k[3], k[5], k[4]) in cgc && (k[7] in bdneq || (k[1], k[2], k[3], k[5], "OUT", k[4]) in rtpgig))
    end

    # L108: OPTION CLEAR=RP_GIC, CLEAR=RTP_CGC, CLEAR=RTPGIG, CLEAR=RTP_CG, CLEAR=RTP_GRP; L109: PUTGRP=0
    qa_group!(tm)
    gput!(tm, "FLO_SHAR", fs)
    gput!(tm, "RPG_RED", rpg_red)
    gput!(tm, "UNCD7", uncd7)
    for (n, N) in (("RP_CCG", 4), ("RTP_CGC", 5), ("RTPGIG", 6), ("RTP_CG", 5), ("RTP_GRP", 5), ("RP_GIC", 5))
        gput!(tm, n, Set{NTuple{N,String}}())
    end
    for (n, x) in (("Z", Zg), ("F", Fg), ("MY_F", MY_Fg))
        gput!(tm, n, iszero(x) ? Dict{Tuple{},Float64}() : Dict{Tuple{},Float64}(() => x.v))
    end
    return tm
end
