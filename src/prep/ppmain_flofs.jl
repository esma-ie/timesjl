# M1.3 (11b): ppmain.mod L823-843 (docs/m13-plan.md): FLO_FUNC and FLO_SUM
# levelled to the process and flow timeslices (pp_lvlff.mod, pp_lvlfs.mod),
# the FLO_SUM and IRE_FLOSUM of the processes whose activity is one
# commodity (from PRC_ACTFLO), FLO_SHAR levelled to the flow timeslices
# (pp_lvlbr.mod) and the market shares (eqflomrk.mod: PRC_MARK, RX_MARK,
# RTX_MARK, RMKC).
#
# GAMS: ppmain.mod L823-843, pp_lvlff.mod L13-39, pp_lvlfs.mod L13-42,
# pp_lvlbr.mod L15-55, eqflomrk.mod L13-54, v4.9.7.
#
# Index sets: R is REG, P is PRC, C and COM are COM, CG and COM_GRP are
# COM_GRP, S, TS and SL are ALL_TS, T and TT are MILESTONYR, V is MODLYEAR,
# LL is ALLYEAR, BD is BND_TYPE (LO, FX, UP), ITEM any label. RTP(R,V,P) runs
# over the model years (G8, G27). `$x` is true for EPS (G3) and `NOT x` false
# (G25); a numeric comparison takes EPS as 0 (G12); `$=` writes only a
# nonzero or EPS value (G24); a right-hand side that names the symbol being
# assigned reads it as it was before the statement (G11); `OPTION a <= b`
# matches the positions by declared domain, left to right (G26, G45).

"""
    ppmain_flofs_symbols(tm) -> Vector{String}

The symbols ppmain.mod L823-843 settles that nothing later in the prelv ->
ppm segment changes (for the layer-1 check at the ppm checkpoint): FLO_FUNC,
FLO_SHAR and the market shares (PRC_MARK, RX_MARK, RTX_MARK, RMKC, COM_TSL,
YK1); FLO_SUM when VDA_EMCB has no data (ppm_ext.vda L20); IRE_FLOSUM when
it has no record at the %PGPRIM% label (ppmain.mod L924-926). Left out:
RPC_NOFLO (ppm_ext.vda L71, L86), RHS_COMPRD (ppmain.mod L1035-1067),
FLO_BND (L999-1001), RXX (L858) and the scratch, which the replay checks at
L843 (scripts/m13_replay.jl, test/unit/test_m13_ppmain_flofs.jl).
"""
function ppmain_flofs_symbols(tm)
    out = ["FLO_FUNC", "FLO_SHAR", "PRC_MARK", "RX_MARK", "RTX_MARK", "RMKC", "COM_TSL", "YK1"]
    isempty(gparam_opt(tm.data, "VDA_EMCB", 4).keys) && push!(out, "FLO_SUM")
    pg = uppercase(strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"']))
    any(k -> uppercase(k[4]) == pg, gparam_opt(tm.data, "IRE_FLOSUM", 8).keys) || push!(out, "IRE_FLOSUM")
    return out
end

"""
    ppmain_flofs!(tm) -> tm

ppmain.mod L823-843 on the state after `ppmain_flo!`: pp_lvlff.mod and
pp_lvlfs.mod; IRE_FLOSUM and FLO_SUM from PRC_ACTFLO for the processes in
RPC_ACT (L833-837); pp_lvlbr.mod for FLO_SHAR (L840); eqflomrk.mod (L842);
RPC_NOFLO without the market-share commodities (L843).

GAMS: ppmain.mod L823-843, v4.9.7.
"""
function ppmain_flofs!(tm)
    tr = TsTree(tm)
    tmem = Set(k[1] for k in gset(tm, "MILESTONYR").keys)
    modl = Set(k[1] for k in gset(tm, "MODLYEAR").keys)
    Z, F = gscal(tm, "Z"), gscal(tm, "F")
    ts_array = nothing
    rtpV = gams_sort!([k for k in gset(tm, "RTP").members if k[2] in modl], tm.data)
    vs_of = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> pushat!(vs_of, (k[1], k[3]), k[2]), rtpV)
    # L829: $BATINCLUDE pp_lvlff.mod
    a = pp_lvlff!(tm, tr, modl, vs_of)
    a === nothing || (ts_array = a)
    # L830: $BATINCLUDE pp_lvlfs.mod
    a, Z = pp_lvlfs!(tm, tr, modl, vs_of, Z)
    a === nothing || (ts_array = a)

    # --- L832-837: FLO_SUM and IRE_FLOSUM from PRC_ACTFLO --------------------------------------------
    afl = gparam_opt(tm.data, "PRC_ACTFLO", 4).values
    rpc_act = gset_opt(tm.data, "RPC_ACT", 3).members
    com = Set(k[1] for k in gset(tm, "COM").keys)
    by(itr, f, g) = (d = Dict{Any,Vector{Any}}(); foreach(k -> pushat!(d, f(k), g(k)), itr); d)
    none = Any[]
    act_of = by(rpc_act, k -> (k[1], k[2]), k -> k[3])
    pg_of = by(gset(tm, "RPC_PG").keys, k -> (k[1], k[2]), k -> k[3])
    rpcs_of = by(gset(tm, "RPCS_VAR").keys, k -> (k[1], k[2], k[3]), k -> k[4])
    # actflo(com)/actflo(c): PRC_ACTFLO(R,V,P,COM)*(1/PRC_ACTFLO(R,V,P,C)), 1/0 a division error as in GAMS
    ratio(r, v, p, cm, c) = gv(afl, (r, v, p, cm)) * (GNum(1.0) / gv(afl, (r, v, p, c)))
    # L833-834: IRE_FLOSUM(RTP(R,V,P),C,S,IE,COM,IO)$(RPC_PG(R,P,C)*RPC_IRE(R,P,C,IE)*RPCS_VAR(R,P,C,S)*TOP(R,P,COM,IO)) $=
    #   SUM(RPC_ACT(RP_IRE(R,P),COM),PRC_ACTFLO(R,V,P,COM)*(1/PRC_ACTFLO(R,V,P,C)))
    ifs = gvalues(tm, "IRE_FLOSUM", 8)
    rp_ire = gset_opt(tm.data, "RP_IRE", 2).members
    ie_of = by(gset_opt(tm.data, "RPC_IRE", 4).keys, k -> (k[1], k[2], k[3]), k -> k[4])
    top_of = by(gset(tm, "TOP").keys, k -> (k[1], k[2]), k -> (k[3], k[4]))
    for (r, v, p) in rtpV
        (r, p) in rp_ire || continue
        acts = get(act_of, (r, p), none)
        isempty(acts) && continue
        for c in get(pg_of, (r, p), none), ie in get(ie_of, (r, p, c), none), s in get(rpcs_of, (r, p, c), none), (cm, io) in get(top_of, (r, p), none)
            cm in acts || continue
            x = ratio(r, v, p, cm, c)
            iszero(x) || gassign!(ifs, (r, v, p, c, s, ie, cm, io), x)
        end
    end
    gput!(tm, "IRE_FLOSUM", ifs)
    # L835-836: FLO_SUM(RTP(R,V,P),CG,C,COM,S)$(RP_PG(R,P,CG)*RPC_PG(R,P,C)*PRC_TS(R,P,S)) $=
    #   SUM(RPC_ACT(RP_FLO(R,P),COM),PRC_ACTFLO(R,V,P,COM)*(1/PRC_ACTFLO(R,V,P,C)))
    fsum = gvalues(tm, "FLO_SUM", 7)
    rp_flo = gset(tm, "RP_FLO").members
    rpg_of = by(gset(tm, "RP_PG").keys, k -> (k[1], k[2]), k -> k[3])
    pts_of = by(gset(tm, "PRC_TS").keys, k -> (k[1], k[2]), k -> k[3])
    for (r, v, p) in rtpV
        (r, p) in rp_flo || continue
        for cm in get(act_of, (r, p), none)
            cm in com || continue
            for g in get(rpg_of, (r, p), none), c in get(pg_of, (r, p), none), s in get(pts_of, (r, p), none)
                x = ratio(r, v, p, cm, c)
                iszero(x) || gassign!(fsum, (r, v, p, g, c, cm, s), x)
            end
        end
    end
    gput!(tm, "FLO_SUM", fsum)
    # L837: OPTION CLEAR=RPC_ACT
    gput!(tm, "RPC_ACT", Set{NTuple{3,String}}())

    # --- L840: $BATINCLUDE pp_lvlbr.mod FLO_SHAR ',C,CG' RPCS_VAR "" 1 0 C, -------------------------
    shar = gvalues(tm, "FLO_SHAR", 7)
    rpcsv = gset(tm, "RPCS_VAR").members
    Z, F, a = lvlbr!(tm, tr, shar, (k, s) -> (k[1], k[3], k[4], s) in rpcsv, Set(rtpV), Z, F; name="FLO_SHAR",
                     tsname="RPCS_VAR", mid=2, pad=0, p5=true, p6=false)
    a === nothing || (ts_array = a)
    gput!(tm, "FLO_SHAR", shar)

    # --- L842: $BATINCLUDE eqflomrk.mod mod; L843: RPC_NOFLO(RMKC(RPC)) = NO ---------------------------
    rmkc = eqflomrk!(tm, tmem)
    noflo = gmembers(tm, "RPC_NOFLO", 3)
    rpc = gset(tm, "RPC").members
    filter!(k -> !(k in rmkc && k in rpc), noflo)
    gput!(tm, "RPC_NOFLO", noflo)

    gput!(tm, "UNCD7", Set{NTuple{7,String}}())                      # pp_lvlbr.mod L46
    ts_array === nothing || gput!(tm, "TS_ARRAY", Dict{Tuple{String},Float64}((s,) => v for (s, v) in ts_array))
    gput_gnum!(tm, "Z", Z)
    gput_gnum!(tm, "F", F)
    return tm
end

"""
    pp_lvlff!(tm, tr, modl, vs_of) -> TS_ARRAY or nothing

pp_lvlff.mod: FLO_FUNC of the groups given at timeslices outside PRC_TS
(other than ACT) levelled to PRC_TS, for every model year of the process,
where FLO_FUNC has no value; an ANNUAL value outside PRC_TS copied down to
the PRC_TS timeslices without a value.

GAMS: pp_lvlff.mod L13-39, v4.9.7.
"""
function pp_lvlff!(tm, tr::TsTree, modl, vs_of)
    ff = gvalues(tm, "FLO_FUNC", 6)
    prc_ts = gset(tm, "PRC_TS").members
    pts_of = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> pushat!(pts_of, (k[1], k[2]), k[3]), gset(tm, "PRC_TS").keys)
    actcg = Set(k[1] for k in gset(tm, "ACTCG").keys)
    stoa = gvalues(tm, "STOA", 1)
    # L16: OPTION FFCKS <= FLO_FUNC; FFCKS(R,P,CG,CG2,S)$(PRC_TS(R,P,S)+ACTCG(CG))=NO
    ffcks = project(keys(ff), (1, 3, 4, 5, 6))
    filter!(k -> !((k[1], k[2], k[5]) in prc_ts || k[3] in actcg), ffcks)
    # L17: LOOP(FFCKS(R,P,CG,COM_GRP,S)$STOA(S),CG_GRP(R,P,CG,COM_GRP) = YES)
    cg_grp = gmembers(tm, "CG_GRP", 4)
    foreach(k -> (k[1] in tr.reg && !iszero(gv(stoa, (k[5],)))) && push!(cg_grp, (k[1], k[2], k[3], k[4])), ffcks)
    # L21-26: LOOP((CG_GRP(R,P,CG,COM_GRP),RTP(R,V,P)), TS_ARRAY(ALL_TS) = FLO_FUNC(R,V,P,CG,COM_GRP,ALL_TS);
    #   FLO_FUNC(R,V,P,CG,COM_GRP,TS)$((NOT TS_ARRAY(TS))$PRC_TS(R,P,TS)) = SUM(RS_TREE(FINEST(R,S),TS), ...)/G_YRFR(R,TS))
    arr = nothing
    for g in gams_sort!(collect(cg_grp), tm.data), v in get(vs_of, (g[1], g[2]), String[])
        key(s) = (g[1], v, g[2], g[3], g[4], s)
        arr = Dict{String,Float64}(s => ff[key(s)] for s in tr.all_ts if haskey(ff, key(s)))
        for ts in get(pts_of, (g[1], g[2]), String[])
            haskey(arr, ts) || gassign!(ff, key(ts), level_br(tr, arr, g[1], ts))
        end
    end
    # L30-31: FLO_FUNC(R,V,P,CG,COM_GRP,TS)$(NOT FLO_FUNC(R,V,P,CG,COM_GRP,TS)) $=
    #   SUM(FFCKS(R,P,CG,COM_GRP,ANNUAL)$PRC_TS(R,P,TS),FLO_FUNC(R,V,P,CG,COM_GRP,ANNUAL))
    annual = Set(tr.annual)
    put = Pair{NTuple{6,String},Float64}[]
    for (k, x) in ff
        (k[6] in annual && k[1] in tr.reg && k[2] in modl && (k[1], k[3], k[4], k[5], k[6]) in ffcks) || continue
        foreach(ts -> haskey(ff, (k[1:5]..., ts)) || push!(put, (k[1:5]..., ts) => x), get(pts_of, (k[1], k[3]), String[]))
    end
    foreach(((k, x),) -> (ff[k] = x), put)
    gput!(tm, "FLO_FUNC", ff)
    # L39: OPTION CLEAR = FFCKS, CLEAR = CG_GRP
    gput!(tm, "FFCKS", Set{NTuple{5,String}}())
    gput!(tm, "CG_GRP", Set{NTuple{4,String}}())
    return arr
end

"""
    pp_lvlfs!(tm, tr, modl, vs_of, Z) -> (TS_ARRAY or nothing, Z)

pp_lvlfs.mod: FLO_SUM given at timeslices outside RPCS_VAR levelled to the
RPCS_VAR timeslices of the commodity for every model year (when some of
them lie outside RPS_PRCTS), the values outside RPCS_VAR and the records of
years outside RTP removed, then the RPCS_VAR timeslices still without a
value take the original values at the levels from WEEKLY up to ANNUAL
above them.

GAMS: pp_lvlfs.mod L13-42, v4.9.7.
"""
function pp_lvlfs!(tm, tr::TsTree, modl, vs_of, Z)
    fs = gvalues(tm, "FLO_SUM", 7)
    com = Set(k[1] for k in gset(tm, "COM").keys)
    rpcsv = gset(tm, "RPCS_VAR").members
    rpcs_of = Dict{NTuple{3,String},Vector{String}}()
    foreach(k -> pushat!(rpcs_of, (k[1], k[2], k[3]), k[4]), gset(tm, "RPCS_VAR").keys)
    # L16: COEF_PTRAN(R,LL,P,CG,C,COM_GRP,S) $= FLO_SUM(R,LL,P,CG,C,COM_GRP,S)$(NOT RPCS_VAR(R,P,C,S))
    cp = gvalues(tm, "COEF_PTRAN", 7)
    for (k, x) in fs
        (k[1] in tr.reg && k[5] in com && !((k[1], k[3], k[5], k[7]) in rpcsv)) && (cp[k] = x)
    end
    # L17: OPTION FSCKS <= COEF_PTRAN
    fscks = project(keys(cp), (1, 3, 4, 5, 6, 7))
    # L18: FSCK(R,P,CG,C,COM_GRP) $= SUM(FSCKS(R,P,CG,C,COM_GRP,S)$(NOT RPS_PRCTS(R,P,S)),1)
    fsck = gmembers(tm, "FSCK", 5)
    rps_prcts = gset(tm, "RPS_PRCTS").members
    foreach(k -> (k[1] in tr.reg && k[4] in com && !((k[1], k[2], k[6]) in rps_prcts)) && push!(fsck, k[1:5]), fscks)
    # L19: LOOP(ANNUAL(TS(TSLVL)),FSTSL(TSLVL+STOAL(R,S),FSCKS(R,P,CG,C,COM_GRP,S)) = YES)   (once, TSLVL 'ANNUAL', G44)
    tslvl = [k[1] for k in gset(tm, "TSLVL").keys]
    lax = OrdAxis(tslvl)
    stoal = gvalues(tm, "STOAL", 2)
    fstsl = gmembers(tm, "FSTSL", 7)
    if "ANNUAL" in tslvl && "ANNUAL" in tr.annual
        for k in fscks
            (k[1] in tr.reg && k[4] in com) || continue
            l = lead(lax, "ANNUAL", glead(Float64(gv(stoal, (k[1], k[6])))))
            l === nothing || push!(fstsl, (l, k...))
        end
    end
    # L23-28: LOOP((FSCK(R,P,CG,C,COM_GRP),RTP(R,V,P)), TS_ARRAY(ALL_TS) = FLO_SUM(R,V,P,CG,C,COM_GRP,ALL_TS);
    #   FLO_SUM(R,V,P,CG,C,COM_GRP,TS)$RPCS_VAR(R,P,C,TS) = SUM(RS_TREE(FINEST(R,S),TS), ...)/G_YRFR(R,TS))
    arr = nothing
    for g in gams_sort!([k for k in fsck if k[1] in tr.reg && k[4] in com], tm.data), v in get(vs_of, (g[1], g[2]), String[])
        key(s) = (g[1], v, g[2], g[3], g[4], g[5], s)
        arr = Dict{String,Float64}(s => fs[key(s)] for s in tr.all_ts if haskey(fs, key(s)))
        a = arr
        foreach(ts -> gassign!(fs, key(ts), level_br(tr, a, g[1], ts)), get(rpcs_of, (g[1], g[2], g[4]), String[]))
    end
    # L33: FLO_SUM(R,LL,P,CG,C,COM_GRP,S)$COEF_PTRAN(R,LL,P,CG,C,COM_GRP,S) = 0
    foreach(k -> (k[1] in tr.reg && k[5] in com) && delete!(fs, k), keys(cp))
    # L34: FLO_SUM(R,LL,P,CG,C,COM_GRP,S)$(NOT RTP(R,LL,P)) = 0
    rtp = gset(tm, "RTP").members
    filter!(((k, _),) -> !(k[1] in tr.reg && k[5] in com && !((k[1], k[2], k[3]) in rtp)), fs)
    # L35-39: FOR(Z=CARD(TSLVL)-2 DOWNTO 0, LOOP(SAMEAS(TSLVL-Z,'ANNUAL'),
    #   FLO_SUM(RTP(R,V,P),CG,C,COM_GRP,TS)$((NOT FLO_SUM(R,V,P,CG,C,COM_GRP,TS))$RPCS_VAR(R,P,C,TS)) $=
    #     SUM(FSTSL(TSLVL,R,P,CG,C,COM_GRP,S)$RS_BELOW(R,S,TS),COEF_PTRAN(R,V,P,CG,C,COM_GRP,S))))
    ia = findfirst(==("ANNUAL"), tslvl)
    for z in (length(tslvl) - 2):-1:0
        Z = GNum(Float64(z))
        (ia === nothing || ia + z > length(tslvl)) && continue
        lvl = tslvl[ia+z]
        acc = Dict{NTuple{7,String},GNum}()
        for (l, r, p, g, c, g2, s) in fstsl
            (l == lvl && r in tr.reg && c in com) || continue
            for v in get(vs_of, (r, p), String[])
                y = get(cp, (r, v, p, g, c, g2, s), nothing)
                y === nothing && continue
                for ts in get(tr.below, (r, s), String[])
                    k = (r, v, p, g, c, g2, ts)
                    ((r, p, c, ts) in rpcsv && !haskey(fs, k)) || continue
                    acc[k] = get(acc, k, GZERO) + (y == 0.0 ? GEPS : GNum(y))
                end
            end
        end
        foreach(((k, x),) -> iszero(x) || gassign!(fs, k, x), acc)
    end
    gput!(tm, "FLO_SUM", fs)
    # L41: OPTION CLEAR=COEF_PTRAN, CLEAR = FSCK, CLEAR = FSCKS, CLEAR=FSTSL; L42 then finds FSCKS empty
    gput!(tm, "COEF_PTRAN", Dict{NTuple{7,String},Float64}())
    gput!(tm, "FSCK", Set{NTuple{5,String}}())
    gput!(tm, "FSCKS", Set{NTuple{6,String}}())
    gput!(tm, "FSTSL", Set{NTuple{7,String}}())
    return arr, Z
end

"""
    eqflomrk!(tm, tmem) -> RMKC

eqflomrk.mod with %2 empty (ppmain.mod L842): PRC_MARK cleaned (LO and UP
under FX, processes without activity), RX_MARK flags the shares of a
process's own flows (ITEM = P), the zero shares bound the flow with EPS,
the shares extrapolated forward over the milestones, the commodities of the
groups prepared for VAR_COMPRD, RTX_MARK set at the commodity timeslices
(or ANNUAL) and RMKC kept for ppmain.mod L843.

GAMS: eqflomrk.mod L13-54, v4.9.7.
"""
function eqflomrk!(tm, tmem)
    pm = gvalues(tm, "PRC_MARK", 6)                                     # (R,LL,P,ITEM,C,BD)
    member(s) = Set(k[1] for k in gset(tm, s).keys)
    bdset, bdneq, bdupx = member("BD"), member("BDNEQ"), member("BDUPX")
    prc = member("PRC")
    tlist = [k[1] for k in gset(tm, "MILESTONYR").keys]
    vara = gset(tm, "RTP_VARA").members
    rp_std = gset(tm, "RP_STD").members
    rx_mark = gmembers(tm, "RX_MARK", 5)
    rtx_mark = gmembers(tm, "RTX_MARK", 6)
    # L22: PRC_MARK(R,LL,P,ITEM,C,BDNEQ)$PRC_MARK(R,LL,P,ITEM,C,'FX') = NO
    for k in collect(keys(pm))
        k[6] == "FX" && foreach(b -> delete!(pm, (k[1:5]..., b)), bdneq)
    end
    # L23: PRC_MARK(R,LL,P,ITEM,C,BD)$((NOT RTP_VARA(R,LL,P))$(NOT SAMEAS(P,ITEM))$PRC_MARK(R,LL,P,ITEM,C,BD)) = NO
    filter!(((k, _),) -> !(k[6] in bdset && !((k[1], k[2], k[3]) in vara) && k[3] != k[4]), pm)
    # L26: LOOP(T,RX_MARK(R,'0',P,C,BD)$((PRC_MARK(R,T,P,P,C,BD)$RP_STD(R,P)>=0)$PRC_MARK(R,T,P,P,C,BD)) = YES)
    for (k, x) in pm
        (k[2] in tmem && k[3] == k[4] && k[6] in bdset) || continue
        ((k[1], k[3]) in rp_std ? x : 0.0) >= 0 && push!(rx_mark, (k[1], "0", k[3], k[5], k[6]))
    end
    # L27: RX_MARK(R,T--ORD(T),P,C,BD) $= PRC_MARK(R,T,P,P,C,BD)$(NOT RX_MARK(R,'0',P,C,BD))
    #   T--ORD(T): the circular lag along the milestones (G38) by the milestone's position, so the last milestone
    lastt = isempty(tlist) ? nothing : last(tlist)
    rx0 = copy(rx_mark)
    for k in keys(pm)
        (k[2] in tmem && k[3] == k[4] && k[6] in bdset && !((k[1], "0", k[3], k[5], k[6]) in rx0)) && push!(rx_mark, (k[1], lastt, k[3], k[5], k[6]))
    end
    # L29: RTP_MRK(RTP_VARA(R,T,P),ITEM,C,BD)$((PRC_MARK(R,T,P,ITEM,C,BD)=0)$PRC_MARK(R,T,P,ITEM,C,BD)) = YES
    rtp_mrk = gmembers(tm, "RTP_MRK", 6)
    for (k, x) in pm
        (k[2] in tmem && (k[1], k[2], k[3]) in vara && k[6] in bdset && x == 0.0) && push!(rtp_mrk, k)
    end
    # L30: RTP_MRK(RTP_VARA(R,T,P),PRC,C,BD)$(PRC_MARK(R,T,PRC,PRC,C,BD)$RX_MARK(R,'0',PRC,C,BD)) = NO
    filter!(k -> !((k[1], k[2], k[3]) in vara && k[4] in prc && haskey(pm, (k[1], k[2], k[4], k[4], k[5], k[6])) &&
                   (k[1], "0", k[4], k[5], k[6]) in rx_mark), rtp_mrk)
    # L31: LOOP(RTP_MRK(R,T,P,ITEM,C,BDUPX(BD))$RP_STD(R,P),FLO_BND(R,T,P,C,ANNUAL,BD) = EPS)
    fbnd = gvalues(tm, "FLO_BND", 6)
    annual = [k[1] for k in gset(tm, "ANNUAL").keys]
    for k in rtp_mrk
        (k[6] in bdupx && (k[1], k[3]) in rp_std) && foreach(a -> (fbnd[(k[1], k[2], k[3], k[5], a, k[6])] = 0.0), annual)
    end
    gput!(tm, "FLO_BND", fbnd)
    # L32: PRC_MARK(RTP_MRK) = 0
    foreach(k -> delete!(pm, k), rtp_mrk)
    # L34: OPTION CLEAR=RXX, CLEAR=YK1, CLEAR=RTP_MRK; L35: RTP_MRK(RTP_VARA(R,T,P),ITEM,C,BD)$PRC_MARK(R,T,P,ITEM,C,BD) = YES
    rtp_mrk = Set{NTuple{6,String}}(k for k in keys(pm) if k[2] in tmem && (k[1], k[2], k[3]) in vara && k[6] in bdset)
    # L36: YK1(T,TT(T+1)) = YES
    yk1 = Set{NTuple{2,String}}((tlist[i], tlist[i+1]) for i in 1:length(tlist)-1)
    # L37: LOOP(YK1(TT,T),PRC_MARK(RTP_VARA(R,T,P),ITEM,C,BD)$(NOT PRC_MARK(R,T,P,ITEM,C,BD)) $= PRC_MARK(R,TT,P,ITEM,C,BD))
    for (tt, t) in gams_sort!(collect(yk1), tm.data)
        put = Pair{NTuple{6,String},Float64}[]
        for (k, x) in pm
            (k[2] == tt && k[6] in bdset) || continue
            kt = (k[1], t, k[3:6]...)
            ((k[1], t, k[3]) in vara && !haskey(pm, kt)) && push!(put, kt => x)
        end
        foreach(((k, x),) -> (pm[k] = x), put)
    end
    gput!(tm, "YK1", yk1)
    # L38: OPTION RTX_MRK <= RTP_MRK, RMKC <= RTX_MRK, FIN <= RMKC
    rtx_mrk = project(rtp_mrk, (1, 2, 4, 5, 6))
    rmkc = project(rtx_mrk, (1, 3, 4))
    fin = project(rmkc, (1, 3))
    # L39: PRC_MARK(R,T,P,ITEM,C,BD)$(NOT RTX_MRK(R,T,ITEM,C,BD)) = 0
    filter!(((k, _),) -> !(k[2] in tmem && k[6] in bdset && !((k[1], k[2], k[4], k[5], k[6]) in rtx_mrk)), pm)
    gput!(tm, "PRC_MARK", pm)
    # L42: FIN(RC) = NO; COM_TSL(FIN,'ANNUAL')$(NOT SUM(COM_TSL(FIN,TSL),1)) = YES
    rc = gset(tm, "RC").members
    setdiff!(fin, rc)
    comtsl = gmembers(tm, "COM_TSL", 3)
    hastsl = Set((k[1], k[2]) for k in comtsl)
    foreach(f -> f in hastsl || push!(comtsl, (f..., "ANNUAL")), fin)
    gput!(tm, "COM_TSL", comtsl)
    # L44: LOOP(RMKC(R,ITEM,C),TRACKC(RC(R,COM))$COM_GMAP(R,C,COM) = YES)
    trackc = gmembers(tm, "TRACKC", 2)
    gmap = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> pushat!(gmap, (k[1], k[2]), k[3]), gset(tm, "COM_GMAP").keys)
    foreach(m -> foreach(c -> (m[1], c) in rc && push!(trackc, (m[1], c)), get(gmap, (m[1], m[3]), String[])), rmkc)
    # L45: RHS_COMPRD(RTCS_VARC(R,T,C,S))$TRACKC(R,C) = YES
    rhs = gmembers(tm, "RHS_COMPRD", 4)
    foreach(k -> (k[2] in tmem && (k[1], k[3]) in trackc) && push!(rhs, k), gset(tm, "RTCS_VARC").keys)
    gput!(tm, "RHS_COMPRD", rhs)
    # L46: RXX(RMKC)=YES; OPTION CLEAR=TRACKC,CLEAR=RMKC
    rxx = Set{NTuple{3,String}}(rmkc)
    gput!(tm, "RXX", rxx)
    gput!(tm, "TRACKC", Set{NTuple{2,String}}())
    # L48: RMKC(RXX(RPC)) = YES; RMKC(RXX(R,ITEM,C)) $= FIN(R,C)
    rpc = gset(tm, "RPC").members
    rmkc = Set{NTuple{3,String}}(k for k in rxx if k in rpc || (k[1], k[3]) in fin)
    # L49: RMKC(R,ITEM,C)$COM_TSL(R,C,'ANNUAL') = NO; OPTION FIN <= RMKC
    filter!(k -> !((k[1], k[3], "ANNUAL") in comtsl), rmkc)
    fin = project(rmkc, (1, 3))
    # L50: LOOP(COM_TSL(FIN(R,C),TSL),RTX_MARK(RTX_MRK(R,T,ITEM,C,BD),S)$(RMKC(R,ITEM,C)$TS_GROUP(R,TSL,S)) = YES)
    grp = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> pushat!(grp, (k[1], k[2]), k[3]), gset(tm, "TS_GROUP").keys)
    for (r, c, tsl) in comtsl
        (r, c) in fin || continue
        for m in rtx_mrk
            (m[1] == r && m[4] == c && (r, m[3], c) in rmkc) || continue
            foreach(s -> push!(rtx_mark, (m..., s)), get(grp, (r, tsl), String[]))
        end
    end
    # L51: RTX_MARK(RTX_MRK(R,T,ITEM,C,BD),ANNUAL)$(NOT RMKC(R,ITEM,C))=YES
    foreach(m -> (m[1], m[3], m[4]) in rmkc || foreach(a -> push!(rtx_mark, (m..., a)), annual), rtx_mrk)
    # L52: RMKC(RXX(R,ITEM,C))=YES; OPTION CLEAR=FIN,CLEAR=RTX_MRK,CLEAR=RTP_MRK
    union!(rmkc, rxx)
    gput!(tm, "RX_MARK", rx_mark)
    gput!(tm, "RTX_MARK", rtx_mark)
    gput!(tm, "RMKC", rmkc)
    gput!(tm, "FIN", Set{NTuple{2,String}}())
    gput!(tm, "RTX_MRK", Set{NTuple{5,String}}())
    gput!(tm, "RTP_MRK", Set{NTuple{6,String}}())
    return rmkc
end
