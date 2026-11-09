# M1.3 (18a, 18b): maindrv.mod L58, the extensions' ppm_ext
# (docs/m13-plan.md): ppm_ext.dsc, which exits at once, then ppm_ext.vda.
# 18a (`ppm_ext_actef!`): L11-58 with pp_actef.vda L9-48 (LVL): the
# dispatching and partial-load sets, the VDA_EMCB emission sums, the flows
# that may be reduced, and ACT_EFF prepared, inherited and levelled. 18b
# (`ppm_ext!`): L59-169 with equcrtp.vda PPM_EXT: the shape indexes of the
# shadow group, the ACT_EFF flows kept from the reduction, the singleton
# ACT_EFF flows, the commodity and CHP availabilities, the NCAP_AFX/AFM
# options, the dynamic UCs out of the standard UCs. 18b ends the prelv ->
# ppm segment.
#
# GAMS: maindrv.mod L58, main_ext.mod L13-24, ppm_ext.dsc L1-16,
# ppm_ext.vda L11-169, pp_actef.vda L9-48, equcrtp.vda L64-71, v4.9.7.
#
# main_ext.mod includes ppm_ext.<ext> for each extension in %EXTEND% order;
# ppm_ext.dsc exits at L12 (%DSC% is NO, init_ext.dsc L15-23: discrete
# capacities are refused there), and ppm_ext.vda is included as
# `ppm_ext.vda VDA mod`, so `pp_actef.%1` is pp_actef.vda. Refused
# (UnportedError): GR_VARGEN data (L12, resloadc.vda; refused at prep_ext.vda
# L38 already), discrete capacities (ppm_ext.dsc L16), RP_FFSGG (L76-83, the
# stochastic extension), dynslite.vda (L169, %DYNTS% YES with TS_OFF data).
# Index sets: R is REG, V MODLYEAR (without '0', so a condition on a '0'
# record stays put while V runs), LL ALLYEAR, T MILESTONYR, S TS SL ALL_TS,
# C COM COM, CG COM_GRP, IO IN_OUT, L LIM, LNX {N, FX}, BD {LO, FX, UP}, J
# 1*999, ITEM the universe, TSL TSLVL, STL the ALL_TS and TSLVL labels
# (initmty.vda L22), so `TSL(STL)` runs over the levels and `S(STL)` over
# the timeslices (G44). `$x` is true for EPS (G3), `NOT x` false (G25),
# `x = 0` true (G12); `NOT a + b` is `NOT (a + b)` (G37); `$=` writes
# nonzero or EPS values (G24, G41); `OPTION a < b` takes for each index of
# `a` the rightmost unmatched index of `b` with the same declared domain,
# `<=` the leftmost (G26, G34, G45), and between parameters gives counts
# (G31) unless no index is projected away, when the values are copied
# (G34); `MOD` takes the sign of the dividend (G43); the circular lags
# `LL--ORD(LL)` and `S--ORD(S)` fold onto one element (G31), so VDA_FLOP at
# pp_actef.vda L28 only marks the (R,P,CG) that RPC_ACE projects;
# `S+STOA(S)` leads S by STOA(S) along ALL_TS (STOA is the lag to ANNUAL, so
# it is ANNUAL), rounded as G29 and dropped past the ends; `SQRT(ABS(EPS))`
# is EPS (G50).

"""
    ppm_ext_unported(tm) -> Vector{String}

What ppm_ext.dsc and ppm_ext.vda L11-58 meet that is not translated.
"""
function ppm_ext_unported(tm)
    out = String[]
    append!(out, init_ext_dsc_unported(tm))
    isempty(gparam_opt(tm.data, "GR_VARGEN", 4).keys) || push!(out, "ppm_ext.vda L12 (GR_VARGEN has data: resloadc.vda COEF)")
    return out
end

"""
    ppm_ext_actef_symbols(tm) -> Vector{String}

The symbols ppm_ext.vda L11-58 settles that nothing later in the prelv ->
ppm segment changes. Left out, as ppm_ext.vda L59-169 changes them (18b):
TRACKPG, TRACKPC, TRACKP, KEEP_FLOF, RPG_1ACE, RP_GRP, RPC_EMIS,
RPCC_FFUNC, RPC_FFUNC, RPC_NOFLO, which the replay checks at L58.
"""
ppm_ext_actef_symbols(tm) = ["RP_UPL", "RP_PL", "FS_EMCB", "FSCK", "FLO_SUM", "VDA_EMCB", "CG_GRP", "FS_EMIS", "FS_EMIT", "RXX",
                             "RPG_ACE", "RPG_PACE", "ACT_EFF", "UNCD7", "VDA_FLOP", "RPC_ACE", "MY_TS", "TS_ARRAY", "FSCKS", "FFCKS"]

"The symbols ppm_ext.vda L11-58 writes, for the replay at L58."
const PPM_EXT_ACTEF_OUTPUTS = ["RP_UPL", "RP_PL", "FS_EMCB", "FSCK", "FLO_SUM", "VDA_EMCB", "CG_GRP", "TRACKPG", "FS_EMIS", "FS_EMIT",
                               "TRACKPC", "RXX", "RPG_ACE", "TRACKP", "RPG_PACE", "ACT_EFF", "UNCD7", "KEEP_FLOF", "RPG_1ACE",
                               "RP_GRP", "VDA_FLOP", "RPC_ACE", "MY_TS", "TS_ARRAY", "FSCKS", "FFCKS"]

# S+n along ALL_TS: the label n places on (n rounded as G29), nothing past the ends
function ts_lead(pos::Dict{String,Int}, all_ts::Vector{String}, s, n::Float64)
    j = pos[s] + Int(round(n, RoundNearestTiesAway))
    return 1 <= j <= length(all_ts) ? all_ts[j] : nothing
end

"""
    ppm_ext_actef!(tm) -> tm

maindrv.mod L58 up to ppm_ext.vda L58, on the state after `ppmain_reduce!`:
ppm_ext.dsc (exits), then ppm_ext.vda L11-58 with pp_actef.vda LVL.

GAMS: ppm_ext.dsc L12, ppm_ext.vda L11-58, pp_actef.vda L9-48, v4.9.7.
"""
function ppm_ext_actef!(tm)
    u = ppm_ext_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    # ppm_ext.dsc L12: $IFI NOT %DSC%==YES $EXIT
    d = tm.data
    S2 = Dict{NTuple{2,String},Vector{String}}
    S3 = Dict{NTuple{3,String},Vector{String}}
    reg = Set(k[1] for k in gset(tm, "REG").keys)
    comset = Set(k[1] for k in gset(tm, "COM").keys)
    modl = Set(k[1] for k in gset(tm, "MODLYEAR").keys)
    iolab = [k[1] for k in gset(tm, "IN_OUT").keys]
    annual = gset(tm, "ANNUAL").keys[1][1]
    pgu = uppercase(strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"']))
    ispg(cg) = uppercase(cg) == pgu
    rp, rp_std, rp_ire = gset(tm, "RP").members, gset(tm, "RP_STD").members, gset(tm, "RP_IRE").members
    rp_flo, rp_pgact, prc_cap = gset(tm, "RP_FLO").members, gset(tm, "RP_PGACT").members, gset(tm, "PRC_CAP").members
    rpc, rpc_pg, rpc_spg = gset(tm, "RPC").members, gset(tm, "RPC_PG").members, gset(tm, "RPC_SPG").members
    rpc_ffunc, rpc_emis = gset(tm, "RPC_FFUNC").members, gset(tm, "RPC_EMIS").members
    rp_inout, gmap = gset(tm, "RP_INOUT").members, gset(tm, "COM_GMAP").members
    top = gset(tm, "TOP").members
    top_of = S3()                                   # (R,P,IO) => C, TOP order
    foreach(k -> pushat!(top_of, (k[1], k[2], k[4]), k[3]), gset(tm, "TOP").keys)
    vs_of = S2()                                    # (R,P) => V of RTP(R,V,P), GAMS order
    foreach(k -> pushat!(vs_of, (k[1], k[3]), k[2]), gset(tm, "RTP").keys)
    vs(r, p) = get(vs_of, (r, p), String[])
    rpcs_of = S3()                                  # (R,P,C) => S of RPCS_VAR
    foreach(k -> pushat!(rpcs_of, (k[1], k[2], k[3]), k[4]), gset(tm, "RPCS_VAR").keys)
    gmap_of = S2()                                  # (R,CG) => C of COM_GMAP
    foreach(k -> pushat!(gmap_of, (k[1], k[2]), k[3]), gset(tm, "COM_GMAP").keys)
    ingrp(r, p, cg, io) = [c for c in get(top_of, (r, p, io), String[]) if (r, cg, c) in gmap]

    # --- ppm_ext.vda L12-15: dispatching and partial loads -----------------------------------------------
    # L12: $IF DEFINED GR_VARGEN $BATINCLUDE resloadc.vda COEF   (no data: ppm_ext_unported)
    # L13: OPTION RP_UPL < ACT_UPS  (ACT_UPS(R,ALLYEAR,P,S,L) -> RP_UPL(R,P,L))
    rp_upl = project(keys(gvalues(tm, "ACT_UPS", 5)), (1, 3, 5))
    # L14: RP_UPL(RP,L)$(NOT PRC_CAP(RP)*RP_STD(RP)) = NO
    filter!(k -> !((k[1], k[2]) in rp && !((k[1], k[2]) in prc_cap && (k[1], k[2]) in rp_std)), rp_upl)
    # L15: RP_PL(R,P,LNX) $= SUM(V$ACT_LOSPL(R,V,P,'FX'),1)
    rp_pl = gmembers(tm, "RP_PL", 3)
    lnx = [k[1] for k in gset(tm, "LNX").keys]
    for k in keys(gvalues(tm, "ACT_LOSPL", 4))
        (k[1] in reg && k[2] in modl && uppercase(k[4]) == "FX") && foreach(l -> push!(rp_pl, (k[1], k[3], l)), lnx)
    end

    # --- L18-21: FLO_SUMs for the VDA_EMCB emissions ---------------------------------------------------
    # L18: FS_EMCB(RP_IRE(R,P),COM,C) = NO
    fs_emcb = gmembers(tm, "FS_EMCB", 4)
    filter!(k -> !((k[1], k[2]) in rp_ire), fs_emcb)
    # L19: OPTION FSCK <= FLO_SUM  (FLO_SUM(REG,ALLYEAR,PRC,CG,C,CG,TS) -> FSCK(REG,PRC,CG,C,CG))
    flo_sum = gvalues(tm, "FLO_SUM", 7)
    fsck = project(keys(flo_sum), (1, 3, 4, 5, 6))
    # L20: FLO_SUM(RTP(R,V,P),COM,C,COM,S)$((NOT FLO_SUM(RTP,COM,C,COM,S))$RPCS_VAR(R,P,C,S)$FS_EMCB(R,P,COM,C)) = VDA_EMCB(R,V,C,COM)
    emcb = gvalues(tm, "VDA_EMCB", 4)
    for (r, p, cm, c) in fs_emcb, v in vs(r, p)
        x = get(emcb, (r, v, c, cm), nothing)
        x === nothing && continue                   # = 0: no record where FLO_SUM has none
        for s in get(rpcs_of, (r, p, c), String[])
            k = (r, v, p, cm, c, cm, s)
            haskey(flo_sum, k) || (flo_sum[k] = x)
        end
    end
    # L21: VDA_EMCB(R,ALLYEAR,C,COM) = 0
    empty!(emcb)

    # --- L24-32: auxiliary flows replaced by source flow x coefficient -----------------------------------
    # L24: CG_GRP(R,P,C,COM)$FSCK(R,P,C,COM,C) = YES   (C and COM run over COM: G27)
    cg_grp = gmembers(tm, "CG_GRP", 4)
    foreach(k -> (k[3] == k[5] && k[3] in comset && k[4] in comset) && push!(cg_grp, k[1:4]), fsck)
    # L25: CG_GRP(FS_EMCB) = YES
    union!(cg_grp, fs_emcb)
    iscc(k) = k[3] in comset && k[4] in comset      # CG_GRP(R,P,C,COM)
    # L26: TRACKPG(RPC(RP_FLO,C)) $= SUM(CG_GRP(RPC,COM),1)
    trackpg = gmembers(tm, "TRACKPG", 3)
    has_cg = Set(k[1:3] for k in cg_grp if iscc(k))
    foreach(k -> ((k[1], k[2]) in rp_flo && k in has_cg) && push!(trackpg, k), rpc)
    # L27: TRACKPG(RPC_PG) = NO; TRACKPG(RPC_FFUNC) = NO; TRACKPG(RPC_EMIS) = NO
    setdiff!(trackpg, rpc_pg); setdiff!(trackpg, rpc_ffunc); setdiff!(trackpg, rpc_emis)
    # L28: LOOP(CG_GRP(R,P,C,COM)$RPC_EMIS(R,P,COM),TRACKPG(R,P,C)=NO)
    foreach(k -> (iscc(k) && (k[1], k[2], k[4]) in rpc_emis) && delete!(trackpg, k[1:3]), cg_grp)
    # L29: FS_EMIS(CG_GRP(TRACKPG(R,P,C),COM),C) = YES
    fs_emis = gmembers(tm, "FS_EMIS", 5)
    foreach(k -> (iscc(k) && k[1:3] in trackpg) && push!(fs_emis, (k..., k[3])), cg_grp)
    # L31: OPTION FS_EMIT < FS_EMIS, TRACKPC < FS_EMIS   (FS_EMIS(R,P,COM_GRP,C,COM) -> FS_EMIT(R,P,COM,COM_GRP,C), TRACKPC(R,P,C))
    fs_emit = project(fs_emis, (1, 2, 5, 3, 4))
    trackpc = project(fs_emis, (1, 2, 4))
    #      TRACKPG(TRACKPC) = NO
    setdiff!(trackpg, trackpc)
    # L32: OPTION CLEAR=CG_GRP, CLEAR=TRACKPC, CLEAR=FS_EMIS, CLEAR=FS_EMCB, CLEAR=FSCK
    empty!(cg_grp); empty!(trackpc); empty!(fs_emis); empty!(fs_emcb); empty!(fsck)

    # --- L35-56: ACT_EFF preparation, inheritance and aggregation -----------------------------------------
    rpc_ace = gmembers(tm, "RPC_ACE", 3)
    # L35: TRACKPC(RPC_ACE(RPC)) = YES
    foreach(k -> k in rpc && push!(trackpc, k), rpc_ace)
    # L36: TRACKPC(RPC_SPG(RP,C))$RPC_ACE(RP,%PGPRIM%) = YES
    ace_pg = Set((k[1], k[2]) for k in rpc_ace if ispg(k[3]))
    foreach(k -> (k[1], k[2]) in ace_pg && push!(trackpc, k), rpc_spg)
    # L37: OPTION CLEAR=RXX; RXX(RPC_ACE) = YES; RXX(TRACKPC) = NO
    rxx = Set(k for k in rpc_ace if !(k in trackpc))
    # L38: RPG_ACE(RXX(R,P,CG),IO)$(SUM(TOP(R,P,C,IO)$COM_GMAP(R,CG,C),1)$(NOT RP_INOUT(R,P,IO))) = YES
    rpg_ace = gmembers(tm, "RPG_ACE", 4)
    for (r, p, cg) in rxx, io in iolab
        (r, p, io) in rp_inout || isempty(ingrp(r, p, cg, io)) || push!(rpg_ace, (r, p, cg, io))
    end
    # L39: OPTION CLEAR=RXX
    empty!(rxx)
    # L41: LOOP(TRACKPC(RPC_PG(R,P,C)), TRACKP(R,P) = YES)
    trackp = gmembers(tm, "TRACKP", 2)
    foreach(k -> k in rpc_pg && push!(trackp, (k[1], k[2])), trackpc)
    # L42: LOOP(RPG_ACE(TRACKP(R,P),CG,IO)$(NOT SUM(TOP(R,P,C,IO)$(COM_GMAP(R,CG,C)*(NOT RPC_SPG(R,P,C))),1)),RPG_PACE(R,P,CG) = YES)
    rpg_pace = gmembers(tm, "RPG_PACE", 3)
    for (r, p, cg, io) in rpg_ace
        (r, p) in trackp || continue
        any(c -> !((r, p, c) in rpc_spg), ingrp(r, p, cg, io)) || push!(rpg_pace, (r, p, cg))
    end
    # L43: LOOP(RPG_PACE(R,P,CG), TRACKP(R,P) = NO)
    foreach(k -> delete!(trackp, (k[1], k[2])), rpg_pace)
    # L45: LOOP(RPG_ACE(R,P,CG,IO),TRACKPC(R,P,C)$COM_GMAP(R,CG,C) = NO)
    foreach(k -> foreach(c -> delete!(trackpc, (k[1], k[2], c)), get(gmap_of, (k[1], k[3]), String[])), rpg_ace)
    # L46: RXX(PRC_SPG(R,P,CG))$(TRACKP(R,P)+SUM(TRACKPC(RPC_SPG(R,P,C)),YES)) = YES
    spg_tpc = Set((k[1], k[2]) for k in trackpc if k in rpc_spg)
    foreach(k -> ((k[1], k[2]) in trackp || (k[1], k[2]) in spg_tpc) && push!(rxx, k), gset(tm, "PRC_SPG").keys)
    # L47: RPG_PACE(RXX(TRACKP,CG)) = YES
    foreach(k -> (k[1], k[2]) in trackp && push!(rpg_pace, k), rxx)
    # L48: TRACKPC(RPC_SPG) = NO
    setdiff!(trackpc, rpc_spg)
    # L50: ACT_EFF(RTP(R,V,P),CG,S)$RXX(R,P,CG) $= ACT_EFF(RTP,%PGPRIM%,S)
    act_eff = gvalues(tm, "ACT_EFF", 5)
    rtp = gset(tm, "RTP").members
    rxx_of = S2()
    foreach(k -> pushat!(rxx_of, (k[1], k[2]), k[3]), rxx)
    for (k, x) in collect(act_eff)
        (ispg(k[4]) && (k[1], k[2], k[3]) in rtp) || continue
        foreach(cg -> act_eff[(k[1], k[2], k[3], cg, k[5])] = x, get(rxx_of, (k[1], k[3]), String[]))
    end
    # L51: ACT_EFF(R,LL,P,%PGPRIM%,S) = 0
    filter!(((k, _),) -> !ispg(k[4]), act_eff)
    # L53: LOOP((TOP(TRACKPC(R,P,C),IO),COM_TMAP(R,COM_TYPE,C))$(NOT RP_INOUT(R,P,IO)),RXX(R,P,COM_TYPE) = YES)
    tmap_of = S2()                                  # (R,C) => COM_TYPE
    foreach(k -> pushat!(tmap_of, (k[1], k[3]), k[2]), gset(tm, "COM_TMAP").keys)
    for (r, p, c) in trackpc, io in iolab
        ((r, p, c, io) in top && !((r, p, io) in rp_inout)) || continue
        foreach(ct -> push!(rxx, (r, p, ct)), get(tmap_of, (r, c), String[]))
    end
    # L54: RPG_ACE(RXX(R,P,CG),IO--1)$RP_INOUT(R,P,IO) = YES   (IO--1: the other of IN, OUT)
    for (r, p, cg) in rxx, (i, io) in enumerate(iolab)
        (r, p, io) in rp_inout && push!(rpg_ace, (r, p, cg, iolab[mod1(i - 1, length(iolab))]))
    end
    # L56: LOOP(IO,ACT_EFF(RTP(R,V,P),CG,ANNUAL)$((ACT_EFF(RTP,CG,ANNUAL)=0)$RPG_ACE(R,P,CG,IO)) = 1)
    for (r, p, cg, _) in rpg_ace, v in vs(r, p)
        get(act_eff, (r, v, p, cg, annual), 0.0) == 0.0 && (act_eff[(r, v, p, cg, annual)] = 1.0)
    end

    # --- pp_actef.vda L11-48 (LVL) -----------------------------------------------------------------------
    # L11: SCALAR MICRO / 1E-6 /  (compile-time data); L12: OPTION CLEAR=UNCD7
    uncd7 = Set{NTuple{7,String}}()
    # L15: CG_GRP(RPC_ACE(RPC(R,P,C)),C) = YES
    foreach(k -> k in rpc && push!(cg_grp, (k..., k[3])), rpc_ace)
    # L16: OPTION KEEP_FLOF<RPG_1ACE, CLEAR=RPG_1ACE   (RPG_1ACE(R,P,CG,C) -> KEEP_FLOF(R,P,C))
    rpg_1ace = gmembers(tm, "RPG_1ACE", 4)
    keep_flof = project(rpg_1ace, (1, 2, 4))
    empty!(rpg_1ace)
    # L18-19: LOOP(RPG_ACE(RP_PGACT(R,P),CG,IO)$(SUM(TOP(R,P,C,IO)$COM_GMAP(R,CG,C),1) LE 1),
    #           IF(NOT RPG_PACE(R,P,CG)+RP_PL(R,P,'FX'),RP_GRP(R,P,CG)=YES; RPG_1ACE(RP_GRP(R,P,CG),C)$(TOP(R,P,C,IO)$COM_GMAP(R,CG,C)) = YES))
    rp_grp = gmembers(tm, "RP_GRP", 3)
    fx = [l for l in lnx if uppercase(l) == "FX"]
    for (r, p, cg, io) in rpg_ace
        (r, p) in rp_pgact || continue
        cs = ingrp(r, p, cg, io)
        length(cs) <= 1 || continue
        ((r, p, cg) in rpg_pace || any(l -> (r, p, l) in rp_pl, fx)) && continue
        push!(rp_grp, (r, p, cg))
        foreach(c -> push!(rpg_1ace, (r, p, cg, c)), cs)
    end
    # L21: ACT_EFF(R,LL,P,C,S)$((RPC_PG(R,P,C)+KEEP_FLOF(R,P,C))$(ACT_EFF(R,LL,P,C,S)=0)$ACT_EFF(R,LL,P,C,S)) = 0   (EPS dropped)
    filter!(((k, x),) -> !(x == 0.0 && k[4] in comset && ((k[1], k[3], k[4]) in rpc_pg || (k[1], k[3], k[4]) in keep_flof)), act_eff)
    # L22: LOOP(RPG_ACE(RPC_SPG(R,P,C),IO),ACT_EFF(RTP(R,V,P),C,S)$ACT_EFF(RTP,C,S)=SQRT(ABS(ACT_EFF(RTP,C,S))))
    #      (once for each IO the group has; SQRT(ABS(EPS)) is EPS)
    nsq = Dict{NTuple{3,String},Int}()
    foreach(k -> k[1:3] in rpc_spg && (nsq[k[1:3]] = get(nsq, k[1:3], 0) + 1), rpg_ace)
    if !isempty(nsq)
        for (k, x) in collect(act_eff)
            n = get(nsq, (k[1], k[3], k[4]), 0)
            (n > 0 && x != 0.0 && (k[1], k[2], k[3]) in rtp) || continue
            for _ in 1:n
                x = sqrt(abs(x))
            end
            act_eff[k] = x
        end
    end
    # L24: CG_GRP(RPG_1ACE) = YES; L25: RPG_ACE(RP_GRP,IO) = NO
    union!(cg_grp, rpg_1ace)
    filter!(k -> !(k[1:3] in rp_grp), rpg_ace)
    # L28: VDA_FLOP(R,LL--ORD(LL),P,CG,S--ORD(S))$STOAL(R,S) $= ACT_EFF(R,LL,P,CG,S); OPTION RPC_ACE<VDA_FLOP, CLEAR=VDA_FLOP
    stoal = gvalues(tm, "STOAL", 2)
    rpc_ace = project(keys(gvalues(tm, "VDA_FLOP", 5)), (1, 3, 4))
    foreach(k -> (k[1] in reg && haskey(stoal, (k[1], k[5]))) && push!(rpc_ace, (k[1], k[3], k[4])), keys(act_eff))
    # L29: UNCD7('1',CG_GRP(RPC_ACE(R,P,CG),C),TSL,S+STOA(S))$TS_GROUP(R,TSL,S) $= RPCS_VAR(R,P,C,S)
    tr = TsTree(tm)
    all_ts = tr.all_ts
    tspos = Dict(s => i for (i, s) in enumerate(all_ts))
    stoa = gvalues(tm, "STOA", 1)
    tsl_of = S2()                                   # (R,S) => TSL of TS_GROUP(R,TSL,S)
    foreach(k -> pushat!(tsl_of, (k[1], k[3]), k[2]), gset(tm, "TS_GROUP").keys)
    toann(s) = ts_lead(tspos, all_ts, s, get(stoa, (s,), 0.0))
    for (r, p, cg, c) in cg_grp
        ((r, p, cg) in rpc_ace && c in comset) || continue
        for s in get(rpcs_of, (r, p, c), String[]), tsl in get(tsl_of, (r, s), String[])
            a = toann(s)
            a === nothing || push!(uncd7, ("1", r, p, cg, c, tsl, a))
        end
    end
    # L30: UNCD7('2',RPG_ACE(RPC_ACE(R,P,CG),IO),TSL,S+STOA(S))$TS_GROUP(R,TSL,S) $= RPS_S1(R,P,S)
    s1_of = S2()
    foreach(k -> pushat!(s1_of, (k[1], k[2]), k[3]), gset(tm, "RPS_S1").keys)
    for (r, p, cg, io) in rpg_ace
        (r, p, cg) in rpc_ace || continue
        for s in get(s1_of, (r, p), String[]), tsl in get(tsl_of, (r, s), String[])
            a = toann(s)
            a === nothing || push!(uncd7, ("2", r, p, cg, io, tsl, a))
        end
    end
    #      CG_GRP(RPC_ACE,C) = NO
    filter!(k -> !(k[1:3] in rpc_ace && k[4] in comset), cg_grp)
    # L31: IF(CARD(NORTS),LOOP((MIYR_1(T),UNCD7(J,R,P,CG,ITEM,TS,TS)),ACT_EFF(RTP(R,V,P),CG,S)$(NORTS(R,V,S)+NORTS(R,T,S)$PASTMILE(V))=0))
    norts = Set(keys(gvalues(tm, "NORTS", 3)))
    if !isempty(norts)
        miyr1 = [k[1] for k in gset(tm, "MIYR_1").keys]
        pastmile = Set(k[1] for k in gset(tm, "PASTMILE").keys)
        rows = Set((u[2], u[3], u[4]) for u in uncd7 if u[6] == u[7])
        isempty(miyr1) && empty!(rows)
        filter!(((k, _),) -> !((k[1], k[3], k[4]) in rows && (k[1], k[2], k[3]) in rtp &&
                                ((k[1], k[2], k[5]) in norts || (k[2] in pastmile && any(t -> (k[1], t, k[5]) in norts, miyr1)))), act_eff)
    end
    # L32: OPTION CLEAR=RPC_ACE; L33: LOOP(RPG_ACE(R,P,CG,IO),RPC_ACE(R,P,C)$(TOP(R,P,C,IO)$COM_GMAP(R,CG,C)) = YES)
    empty!(rpc_ace)
    foreach(k -> foreach(c -> push!(rpc_ace, (k[1], k[2], c)), ingrp(k[1], k[2], k[3], k[4])), rpg_ace)
    # L34: RPC_ACE(KEEP_FLOF) = NO
    setdiff!(rpc_ace, keep_flof)

    # L37-42: LOOP(UNCD7(J,R,P,CG,ITEM,TSL,STL), MY_TS(S) = TS_GROUP(R,TSL,S);
    #          LOOP(RTP(R,V,P), TS_ARRAY(S) = ACT_EFF(R,V,P,CG,S);
    #           ACT_EFF(R,V,P,CG,MY_TS)$(NOT TS_ARRAY(MY_TS)) = (pp_lvlbr.mod's levelling: level_br)))
    sl = Dict{NTuple{4,String},Dict{String,Float64}}()   # ACT_EFF by (R,V,P,CG) => S => value
    for (k, x) in act_eff
        get!(() -> Dict{String,Float64}(), sl, (k[1], k[2], k[3], k[4]))[k[5]] = x
    end
    slice(r, v, p, cg) = get!(() -> Dict{String,Float64}(), sl, (r, v, p, cg))
    order = collect(uncd7)
    gams_sort!(order, d)
    my_ts, ts_array = nothing, nothing
    for (_, r, p, cg, _, tsl, _) in order
        my_ts = get(tr.group, (r, tsl), String[])
        for v in vs(r, p)
            arr = slice(r, v, p, cg)
            ts_array = copy(arr)
            for ts in my_ts
                haskey(ts_array, ts) && continue
                x = level_br(tr, ts_array, r, ts)
                iszero(x) ? delete!(arr, ts) : (arr[ts] = x.eps ? 0.0 : x.v)
            end
        end
    end
    # L44: FSCKS(CG_GRP(R,P,CG,C),CG,S)$RPCS_VAR(R,P,C,S) = YES; OPTION FFCKS <= FSCKS
    fscks = gmembers(tm, "FSCKS", 6)
    for (r, p, cg, c) in cg_grp
        c in comset && foreach(s -> push!(fscks, (r, p, cg, c, cg, s)), get(rpcs_of, (r, p, c), String[]))
    end
    ffcks = project(fscks, (1, 2, 3, 5, 6))
    # L45: ACT_EFF(RTP(R,V,P),CG,S+STOA(S))$(RPS_S1(R,P,S)$STOA(S)$ACT_EFF(RTP,CG,S)) = 0
    rps_s1 = gset(tm, "RPS_S1").members
    for ((r, v, p, cg), arr) in sl
        (r, v, p) in rtp || continue
        drop = String[]
        for s in keys(arr)
            (haskey(stoa, (s,)) && (r, p, s) in rps_s1) || continue
            a = toann(s)
            a === nothing || push!(drop, a)
        end
        foreach(a -> delete!(arr, a), drop)
    end
    # L46: ACT_EFF(RTP(R,V,P),CG,S)$(NOT ACT_EFF(RTP,CG,S)) $= SUM(FFCKS(R,P,CG,CG,S),ACT_EFF(R,V,P,CG,'ANNUAL'))
    for (r, p, cg, cg2, s) in ffcks
        cg == cg2 || continue
        for v in vs(r, p)
            arr = get(sl, (r, v, p, cg), nothing)
            (arr === nothing || haskey(arr, s)) && continue
            x = get(arr, annual, nothing)
            x === nothing || (arr[s] = x)
        end
    end
    # L47: OPTION CLEAR=FFCKS,CLEAR=FSCKS,CLEAR=CG_GRP
    empty!(ffcks); empty!(fscks); empty!(cg_grp)

    act_eff = Dict{NTuple{5,String},Float64}((k..., s) => x for (k, arr) in sl for (s, x) in arr)
    gput!(tm, "ACT_EFF", act_eff)
    for (n, x) in (("RP_UPL", rp_upl), ("RP_PL", rp_pl), ("FS_EMCB", fs_emcb), ("FSCK", fsck), ("CG_GRP", cg_grp),
                   ("TRACKPG", trackpg), ("FS_EMIS", fs_emis), ("FS_EMIT", fs_emit), ("TRACKPC", trackpc), ("RXX", rxx),
                   ("RPG_ACE", rpg_ace), ("TRACKP", trackp), ("RPG_PACE", rpg_pace), ("UNCD7", uncd7), ("KEEP_FLOF", keep_flof),
                   ("RPG_1ACE", rpg_1ace), ("RP_GRP", rp_grp), ("RPC_ACE", rpc_ace), ("FSCKS", fscks), ("FFCKS", ffcks))
        gput!(tm, n, x)
    end
    gput!(tm, "FLO_SUM", flo_sum)
    gput!(tm, "VDA_EMCB", emcb)
    gput!(tm, "VDA_FLOP", Dict{NTuple{5,String},Float64}())
    my_ts === nothing || gput!(tm, "MY_TS", Set{Tuple{String}}((s,) for s in my_ts))
    ts_array === nothing || gput!(tm, "TS_ARRAY", Dict{Tuple{String},Float64}((s,) => x for (s, x) in ts_array))
    return tm
end

"""
    ppm_ext_symbols(tm) -> Vector{String}

Every set and parameter of the dump `tm` started from, the QA-log scalars
PUTOUT, PUTGRP and ERRLEV too (M1.3 change 25b-1): ppm_ext.vda ends the
prelv -> ppm segment.
"""
ppm_ext_symbols(tm) = sort([i.name for i in values(tm.data.dump.symbols) if i.kind in (:set, :parameter)])

"The symbols ppm_ext.vda L59-169 writes, for the replay at L169."
const PPM_EXT_OUTPUTS = ["FLO_FUNCX", "TRACKP", "RPCC_FFUNC", "RPCG_PTRAN", "RPC_FFUNC", "RPC_NOFLO", "PRC_ACT", "NO_ACT", "TRACKPC",
                         "RPG_1ACE", "TRACKPG", "RPC_EMIS", "KEEP_FLOF", "RP_GRP", "RPG_AFCX", "RP_XRED", "PRC_SC", "NCAP_AFCS",
                         "NCAP_AFC", "RVPS", "RTPS_BD", "NCAP_AFS", "RPS_CAFLAC", "RP_STL", "RVP", "VDA_CEH", "FIL", "PRC_YMIN",
                         "NCAP_AFSX", "RP_AFB", "NCAP_AFSM", "NCAP_AFM", "UC_ON", "UC_R_SUM", "UC_R_EACH"]

"""
    ppm_ext!(tm) -> tm

ppm_ext.vda L59-169 (with equcrtp.vda PPM_EXT) on the state after
`ppm_ext_actef!`: the shape indexes of the shadow group, the ACT_EFF flows
kept from the reduction, the singleton ACT_EFF flows, the commodity
availabilities (NCAP_AFC, NCAP_AFCS, RTPS_BD, RPS_CAFLAC, RPG_AFCX, RP_STL),
the CHP availabilities, the NCAP_AFX/NCAP_AFM options, the dynamic UCs out
of the standard UCs. Ends the prelv -> ppm segment.

GAMS: ppm_ext.vda L59-169, equcrtp.vda L64-71, v4.9.7.
"""
function ppm_ext!(tm)
    u = ppm_ext_unported(tm)
    yes(n) = uppercase(strip(gswitch(tm, n, ""))) == "YES"
    (yes("DYNTS") && !isempty(gset_opt(tm.data, "TS_OFF", 4).keys)) && push!(u, "ppm_ext.vda L169 (dynslite.vda POSTLEV)")
    isempty(gset_opt(tm.data, "RP_FFSGG", 4).keys) || push!(u, "ppm_ext.vda L76-83 (RP_FFSGG: stochastic extension)")
    isempty(u) || throw(UnportedError(join(u, "; ")))
    S2 = Dict{NTuple{2,String},Vector{String}}
    reg = Set(k[1] for k in gset(tm, "REG").keys)
    comset = Set(k[1] for k in gset(tm, "COM").keys)
    modl = Set(k[1] for k in gset(tm, "MODLYEAR").keys)
    allts = Set(k[1] for k in gset(tm, "ALL_TS").keys)
    annual = gset(tm, "ANNUAL").keys[1][1]
    dflbl = "0"                                     # %DFLBL% (initmty.mod L367)
    pgu = uppercase(strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"']))
    ispg(cg) = uppercase(cg) == pgu
    cgk = gset(tm, "COM_GRP").keys
    ipg = findfirst(k -> ispg(k[1]), cgk)
    pgl = ipg === nothing ? pgu : cgk[ipg][1]          # the %PGPRIM% label as the dump spells it
    actcg = Set(k[1] for k in gset(tm, "ACTCG").keys)
    bdupx = Set(k[1] for k in gset(tm, "BDUPX").keys)
    bds = [k[1] for k in gset(tm, "BD").keys]
    rp, rp_std, rp_flo, rp_stg = gset(tm, "RP").members, gset(tm, "RP_STD").members, gset(tm, "RP_FLO").members, gset(tm, "RP_STG").members
    rp_pgact, rp_pgflo, prc_cap = gset(tm, "RP_PGACT").members, gset(tm, "RP_PGFLO").members, gset(tm, "PRC_CAP").members
    rpc_pg, rp_pg, rp_pgtype = gset(tm, "RPC_PG").members, gset(tm, "RP_PG").members, gset(tm, "RP_PGTYPE").members
    rtp = gset(tm, "RTP").members
    by2(keys) = (d = S2(); foreach(k -> pushat!(d, (k[1], k[2]), k[end]), keys); d)
    rpcpg_of = by2(gset(tm, "RPC_PG").keys)
    rpg_ace, rpc_ace = gset(tm, "RPG_ACE").members, gset(tm, "RPC_ACE").members
    rp_grp = gmembers(tm, "RP_GRP", 3)

    # --- L61-65: shape indexes for the shadow group --------------------------------------------------
    ffx = gvalues(tm, "FLO_FUNCX", 5)
    if !isempty(ffx)
        spg_of = by2(gset(tm, "PRC_SPG").keys)
        pg_of = by2(gset(tm, "RP_PG").keys)
        # L62: FLO_FUNCX(R,V,P,CG1,ACTCG(CG))$PRC_SPG(R,P,CG1) $= FLO_FUNCX(R,V,P,CG,CG)
        for (k, x) in collect(ffx)
            (k[1] in reg && k[2] in modl && k[4] == k[5] && k[4] in actcg) || continue
            foreach(cg1 -> ffx[(k[1], k[2], k[3], cg1, k[4])] = x, get(spg_of, (k[1], k[3]), String[]))
        end
        # L63: FLO_FUNCX(R,V,P,CG,COM)$(RPC_PG(R,P,COM)$RP_GRP(R,P,CG)) $= FLO_FUNCX(R,V,P,CG,%PGPRIM%)
        for (k, x) in collect(ffx)
            (k[1] in reg && k[2] in modl && ispg(k[5]) && (k[1], k[3], k[4]) in rp_grp) || continue
            foreach(c -> ffx[(k[1], k[2], k[3], k[4], c)] = x, get(rpcpg_of, (k[1], k[3]), String[]))
        end
        # L64: FLO_FUNCX(R,V,P,CG,ACTCG)$(ACTCG(CG)+RP_GRP(R,P,CG)) = 0
        filter!(((k, _),) -> !(k[1] in reg && k[2] in modl && k[5] in actcg && (k[4] in actcg || (k[1], k[3], k[4]) in rp_grp)), ffx)
        # L65: FLO_FUNCX(R,V,P,CG,CG2)$RP_PG(R,P,CG) $= FLO_FUNCX(R,V,P,%PGPRIM%,CG2)
        for (k, x) in collect(ffx)
            (k[1] in reg && k[2] in modl && ispg(k[4])) || continue
            foreach(cg -> ffx[(k[1], k[2], k[3], cg, k[5])] = x, get(pg_of, (k[1], k[3]), String[]))
        end
    end

    # --- L67-75: ACT_EFF flows are not reduced ------------------------------------------------------------
    # L67: OPTION TRACKP < RPG_ACE
    trackp = project(rpg_ace, (1, 2))
    # L68: LOOP(RPCG_PTRAN(TRACKP(R,P),C,COM,CG,CG2)$(RPC_ACE(R,P,C)+RPC_ACE(R,P,COM)),RPCC_FFUNC(R,P,CG,CG2) = NO)
    ptran, ccffunc = gmembers(tm, "RPCG_PTRAN", 6), gmembers(tm, "RPCC_FFUNC", 4)
    for k in ptran
        ((k[1], k[2]) in trackp && ((k[1], k[2], k[3]) in rpc_ace || (k[1], k[2], k[4]) in rpc_ace)) && delete!(ccffunc, (k[1], k[2], k[5], k[6]))
    end
    # L69: RPCG_PTRAN(TRACKP,C,COM,CG,CG2)$(NOT RPCC_FFUNC(TRACKP,CG,CG2)) = NO
    filter!(k -> !((k[1], k[2]) in trackp && !((k[1], k[2], k[5], k[6]) in ccffunc)), ptran)
    # L70: RPC_FFUNC(RPC_ACE(R,P,C)) = NO; L71: RPC_NOFLO(RPC_ACE(R,P,C)) = NO
    ffunc, noflo = gmembers(tm, "RPC_FFUNC", 3), gmembers(tm, "RPC_NOFLO", 3)
    ace_c = Set(k for k in rpc_ace if k[3] in comset)
    setdiff!(ffunc, ace_c); setdiff!(noflo, ace_c)
    # L72: TRACKP(RP_PGFLO) = NO; L73: PRC_ACT(NO_ACT(TRACKP)) = YES; L74: NO_ACT(TRACKP) = NO; L75: OPTION CLEAR=TRACKP
    setdiff!(trackp, rp_pgflo)
    prc_act, no_act = gmembers(tm, "PRC_ACT", 2), gmembers(tm, "NO_ACT", 2)
    foreach(k -> k in no_act && push!(prc_act, k), trackp)
    setdiff!(no_act, trackp)
    empty!(trackp)
    # L76-83: $IF NOT DEFINED RP_FFSGG $GOTO DONEFUNC   (the stochastic extension only: ppm_ext! refuses it)

    # --- L86-101: singleton ACT_EFFs to RPC_FFUNC ---------------------------------------------------------
    # L86: OPTION TRACKPC < RPG_1ACE; RPC_NOFLO(TRACKPC) = NO; PUTGRP=0   (RPG_1ACE(R,P,CG,C) -> TRACKPC(R,P,C))
    rpg_1ace = gmembers(tm, "RPG_1ACE", 4)
    trackpc = project(rpg_1ace, (1, 2, 4))
    setdiff!(noflo, trackpc)
    qa_group!(tm)
    # L87-90: LOOP(TRACKPC(KEEP_FLOF(R,P,C)), IF(RPC_FFUNC(R,P,C)+TRACKPG(R,P,C),RPG_1ACE(R,P,CG,C) = NO; ELSE
    #   pp_qaput 01 'ACT_EFF shadow group contains only an auxiliary flow';
    #   PUT ' WARNING       - ACT_EFF is applied to the auxiliary flow: R.P.C= 'TRACKPC.TE(TRACKPC)))
    keep_flof, trackpg = gmembers(tm, "KEEP_FLOF", 3), gmembers(tm, "TRACKPG", 3)
    drop1 = Set(k for k in trackpc if k in keep_flof && (k in ffunc || k in trackpg))
    filter!(k -> !((k[1], k[2], k[4]) in drop1), rpg_1ace)
    for k in gams_sort!([k for k in trackpc if k in keep_flof && !(k in drop1)], tm.data)
        pp_qaput!(tm, 1, "ACT_EFF shadow group contains only an auxiliary flow")
        qput!(qalog(tm), " WARNING       - ACT_EFF is applied to the auxiliary flow: R.P.C= " * join(k, "."))
    end
    # L91: TRACKPC(KEEP_FLOF) = NO; PUTGRP=0; L92-94: LOOP(RPC_FFUNC(TRACKPC), pp_qaput 09 'Inconsistent/spurious
    #   process transformation parameters'; PUT ' SEVERE ERROR  - Same process flow definitions in conflict: R.P.C= ',TRACKPC.TE(TRACKPC))
    setdiff!(trackpc, keep_flof)
    qa_group!(tm)
    for k in gams_sort!([k for k in trackpc if k in ffunc], tm.data)
        pp_qaput!(tm, 9, "Inconsistent/spurious process transformation parameters")
        qput!(qalog(tm), " SEVERE ERROR  - Same process flow definitions in conflict: R.P.C= " * join(k, "."))
    end
    # L96: TRACKPG(RPC_ACE) = NO; TRACKPG(TRACKPC) = NO
    setdiff!(trackpg, rpc_ace); setdiff!(trackpg, trackpc)
    # L97: RPC_EMIS(TRACKPG) = YES; RPCC_FFUNC(TRACKPG(RP,C),C) = YES
    rpc_emis = gmembers(tm, "RPC_EMIS", 3)
    for k in trackpg
        k[3] in comset || continue
        push!(rpc_emis, k)
        (k[1], k[2]) in rp && push!(ccffunc, (k..., k[3]))
    end
    # L98: $IF NOT %REDUCE%==YES OPTION CLEAR=TRACKPC   ($IF compares case-sensitively)
    strip(gswitch(tm, "REDUCE", "")) == "YES" || empty!(trackpc)
    # L99: OPTION KEEP_FLOF < RPC_FFUNC; TRACKPC(RP_SGS,C) = NO
    keep_flof = copy(ffunc)
    rp_sgs = gset(tm, "RP_SGS").members
    filter!(k -> !((k[1], k[2]) in rp_sgs), trackpc)
    # L100: RPC_FFUNC(TRACKPC)$(NOT RPC_ACE(TRACKPC)) = YES
    foreach(k -> k in rpc_ace || push!(ffunc, k), trackpc)
    # L101: OPTION CLEAR=RP_GRP,CLEAR=TRACKPC,CLEAR=TRACKPG
    empty!(rp_grp); empty!(trackpc); empty!(trackpg)

    # --- L104-142: commodity-specific availability factors ------------------------------------------------
    # L104: SET RPG_AFCX(R,P,C,IE); OPTION RP_GRP<NCAP_AFC, RP_XRED<RP_GRP   (NCAP_AFC(REG,ALLYEAR,PRC,CG,STL))
    ncap_afc = gvalues(tm, "NCAP_AFC", 5)
    rp_grp = project(keys(ncap_afc), (1, 3, 4))
    rp_xred = project(rp_grp, (1, 2))
    # L105: RP_GRP(RP_PG(R,P,CG))$(NOT C(CG)+COM_TYPE(CG)) = NO
    com_type = Set(k[1] for k in gset(tm, "COM_TYPE").keys)
    filter!(k -> !(k in rp_pg && !(k[3] in comset || k[3] in com_type)), rp_grp)
    # L106: PRC_SC(RP_STG(RP_XRED(RP)))=SUM(PRC_TSL(RP,TSL),LOG(G_CYCLE(TSL)))
    prc_sc, gcyc = gvalues(tm, "PRC_SC", 2), gvalues(tm, "G_CYCLE", 1)
    tsl_of = by2(gset(tm, "PRC_TSL").keys)
    for k in rp_xred
        (k in rp && k in rp_stg) || continue
        gassign!(prc_sc, k, sum((log(get(gcyc, (t,), 0.0)) for t in get(tsl_of, k, String[])); init=0.0))
    end
    # L107: LOOP(TSL(STL),NCAP_AFCS(R,LL,P,CG,S)$TS_GROUP(R,TSL,S) $= NCAP_AFC(R,LL,P,CG,STL)$RP_GRP(R,P,CG))
    #       (TSL(STL): the TSLVL labels that are STL labels, G44)
    afcs = gvalues(tm, "NCAP_AFCS", 5)
    stl = Set(k[1] for k in gset(tm, "STL").keys)
    tsls = [k[1] for k in gset(tm, "TSLVL").keys if k[1] in stl]
    grp_of = by2(gset(tm, "TS_GROUP").keys)          # (R,TSL) => S
    for t in tsls, (k, x) in ncap_afc
        (k[5] == t && k[1] in reg && (k[1], k[3], k[4]) in rp_grp) || continue
        foreach(s -> afcs[(k[1], k[2], k[3], k[4], s)] = x, get(grp_of, (k[1], t), String[]))
    end
    # L108: NCAP_AFCS(R,LL,P,CG,S(STL))$RP_GRP(R,P,CG) $= NCAP_AFC(R,LL,P,CG,STL); OPTION CLEAR=NCAP_AFC
    for (k, x) in ncap_afc
        (k[5] in allts && k[1] in reg && (k[1], k[3], k[4]) in rp_grp) && (afcs[k] = x)
    end
    empty!(ncap_afc)
    # L109: NCAP_AFCS(R,LL,P,CG,S)$(NOT PRC_CAP(R,P))=0
    filter!(((k, _),) -> !(k[1] in reg && !((k[1], k[3]) in prc_cap)), afcs)
    # L111: LOOP(RP_GRP(RP_FLO(R,P),CG),IF(SUM(RC(R,C(CG))$(NOT RPC_PG(R,P,C)),1)+1$(NOT RP_PGTYPE(R,P,CG)+C(CG)),TRACKPG(R,P,CG)=YES))
    rc = gset(tm, "RC").members
    for (r, p, cg) in rp_grp
        (r, p) in rp_flo || continue
        a = cg in comset && (r, cg) in rc && !((r, p, cg) in rpc_pg)
        b = !((r, p, cg) in rp_pgtype || cg in comset)
        (a || b) && push!(trackpg, (r, p, cg))
    end
    # L112: TRACKPG(RP_GRP(RP_STG,%PGPRIM%))=YES
    foreach(k -> (ispg(k[3]) && (k[1], k[2]) in rp_stg) && push!(trackpg, k), rp_grp)
    # L113: NCAP_AFC(R,V,P,CG,STL(S))$TRACKPG(R,P,CG) $= NCAP_AFCS(R,V,P,CG,S)
    for (k, x) in afcs
        (k[1] in reg && k[2] in modl && k[5] in stl && (k[1], k[3], k[4]) in trackpg) && (ncap_afc[k] = x)
    end
    # L114: NCAP_AFC(R,V,P,C,STL(S))$(RC(R,C)$NCAP_AFCS(R,'0',P,%PGPRIM%,S)) $= NCAP_AFCS(R,V,P,C,S)
    for (k, x) in afcs
        (k[1] in reg && k[2] in modl && k[4] in comset && k[5] in stl && (k[1], k[4]) in rc && haskey(afcs, (k[1], dflbl, k[3], pgl, k[5]))) || continue
        ncap_afc[k] = x
    end
    # L115: NCAP_AFCS(R,V,P,CG,S)$(RP_FLO(R,P)$TRACKPG(R,P,CG)) = 0
    # L116: NCAP_AFCS(R,V,P,CG,S)$(NCAP_AFCS(R,'0',P,%PGPRIM%,S)$RP_FLO(R,P)) = 0   ('0' is not a MODLYEAR: the condition stays put)
    filter!(((k, _),) -> !(k[1] in reg && k[2] in modl && (k[1], k[3]) in rp_flo &&
                           ((k[1], k[3], k[4]) in trackpg || haskey(afcs, (k[1], dflbl, k[3], pgl, k[5])))), afcs)
    # L117: NCAP_AFCS(R,V,P,CG,S)$((NOT RP_STG(R,P))$RP_PGTYPE(R,P,CG)) $= NCAP_AFCS(R,V,P,%PGPRIM%,S)
    pgtype_of = by2(gset(tm, "RP_PGTYPE").keys)
    for (k, x) in collect(afcs)
        (k[1] in reg && k[2] in modl && ispg(k[4]) && !((k[1], k[3]) in rp_stg)) || continue
        foreach(cg -> afcs[(k[1], k[2], k[3], cg, k[5])] = x, get(pgtype_of, (k[1], k[3]), String[]))
    end
    # L119: OPTION RVPS < NCAP_AFCS   (NCAP_AFCS(REG,ALLYEAR,PRC,CG,TS) -> RVPS(REG,ALLYEAR,PRC,TS))
    rvps = project(keys(afcs), (1, 2, 3, 5))
    # L121: NCAP_AFCS(RTP(R,V,P),ACTCG,S(STL))$((NOT RVPS(RTP,S))$RP_STG(R,P)) $= NCAP_AFC(RTP,ACTCG,STL)
    for (k, x) in collect(ncap_afc)
        (k[4] in actcg && k[5] in allts && (k[1], k[2], k[3]) in rtp && (k[1], k[3]) in rp_stg && !((k[1], k[2], k[3], k[5]) in rvps)) || continue
        afcs[k] = x
    end
    # L123: RVPS(R,V,P,S)$(RTP(R,V,P)->RP_STD(R,P)$RP_PGACT(R,P)) = NO
    filter!(k -> !(k[1] in reg && k[2] in modl && (!((k[1], k[2], k[3]) in rtp) || ((k[1], k[3]) in rp_std && (k[1], k[3]) in rp_pgact))), rvps)
    # L125-127: RTPS_BD(RVPS(R,V,P,S),BDUPX(BD))$(PRC_TS(R,P,S)*NCAP_AF(R,V,P,S,BD) | NCAP_AFS(R,V,P,S,BD)) = YES;
    #           RTPS_BD(RVPS(R,V,P,ANNUAL),BDUPX(BD))$NCAP_AFA(R,V,P,BD) = YES
    rtps_bd = gmembers(tm, "RTPS_BD", 5)
    prc_ts = gset(tm, "PRC_TS").members
    ncap_af, ncap_afs, ncap_afa = gvalues(tm, "NCAP_AF", 5), gvalues(tm, "NCAP_AFS", 5), gvalues(tm, "NCAP_AFA", 4)
    for (r, v, p, s) in rvps, bd in bdupx
        (r in reg && v in modl) || continue
        k = (r, v, p, s, bd)
        (((r, p, s) in prc_ts && haskey(ncap_af, k)) || haskey(ncap_afs, k) || (s == annual && haskey(ncap_afa, (r, v, p, bd)))) && push!(rtps_bd, k)
    end
    # L129: LOOP(BDUPX,RVPS(R,V,P,S)$RTPS_BD(R,V,P,S,BDUPX) = NO)
    filter!(k -> !(k[1] in reg && k[2] in modl && any(bd -> (k..., bd) in rtps_bd, bdupx)), rvps)
    # L131: RTPS_BD(RVPS,'UP') = YES; L132: NCAP_AFS(RVPS,'UP') = 1
    foreach(k -> (push!(rtps_bd, (k..., "UP")); ncap_afs[(k..., "UP")] = 1.0), rvps)
    # L133: OPTION RPS_CAFLAC < RTPS_BD   (RTPS_BD(R,ALLYEAR,P,S,BD) -> RPS_CAFLAC(R,P,S,BD))
    rps_caflac = project(rtps_bd, (1, 3, 4, 5))
    # L134: NCAP_AFC(RTP,C,STL(S))$(NCAP_AFCS(RTP,C,S)=0) $= NCAP_AFCS(RTP,C,S)   (the EPS records)
    for (k, x) in afcs
        (x == 0.0 && k[4] in comset && k[5] in stl && (k[1], k[2], k[3]) in rtp) && (ncap_afc[k] = 0.0)
    end
    # L135: NCAP_AFCS(R,V,P,CG,S)$((NCAP_AFCS(R,V,P,CG,S)<=0)$NCAP_AFCS(R,V,P,CG,S)) = 1+INF$(RP_STD(R,P) OR (NOT C(CG)))
    for (k, x) in collect(afcs)
        (x <= 0.0 && k[1] in reg && k[2] in modl) || continue
        afcs[k] = ((k[1], k[3]) in rp_std || !(k[4] in comset)) ? Inf : 1.0
    end
    # L137: RPG_AFCX(RPC_IRE(RP,C,IE('EXP')))$(RPC_IRE(RP,C,'IMP')+(NOT RP_AIRE(RP,IE)))=YES
    rpg_afcx = gmembers(tm, "RPG_AFCX", 4)
    rpc_ire, rp_aire = gset(tm, "RPC_IRE").members, gset(tm, "RP_AIRE").members
    for k in rpc_ire
        (k[4] == "EXP" && (k[1], k[2]) in rp) || continue
        ((k[1], k[2], k[3], "IMP") in rpc_ire || !((k[1], k[2], "EXP") in rp_aire)) && push!(rpg_afcx, k)
    end
    # L138: RPG_AFCX(RPC_STG,IE(XPT)) $= TOP(RPC_STG,'OUT')
    top = gset(tm, "TOP").members
    xpt = [k[1] for k in gset(tm, "XPT").keys]
    for k in gset(tm, "RPC_STG").keys
        (k..., "OUT") in top && foreach(ie -> push!(rpg_afcx, (k..., ie)), xpt)
    end
    # L140: TRACKP(RP_STS(RP)) $= SUM(RPS_CAFLAC(RPS_STG(RP,S),BD),1); OPTION RP_GRP<NCAP_AFC
    rps_stg = gset(tm, "RPS_STG").members
    caf_stg = Set((k[1], k[2]) for k in rps_caflac if (k[1], k[2], k[3]) in rps_stg)
    foreach(k -> (k in rp && k in caf_stg) && push!(trackp, k), gset(tm, "RP_STS").keys)
    rp_grp = project(keys(ncap_afc), (1, 3, 4))
    # L141: RP_STL(PRC_CAP(RP_STS(RP)),TSL,'UP')$(TRACKP(RP)->RP_GRP(RP,%PGPRIM%)) $= RP_STL(RP,TSL,'N')
    rp_stl = gmembers(tm, "RP_STL", 4)
    rp_sts = gset(tm, "RP_STS").members
    stl_n = [k for k in rp_stl if k[4] == "N"]
    for (r, p, t, _) in stl_n
        ((r, p) in rp && (r, p) in prc_cap && (r, p) in rp_sts) || continue
        (!((r, p) in trackp) || (r, p, pgl) in rp_grp) && push!(rp_stl, (r, p, t, "UP"))
    end
    # L142: OPTION CLEAR=TRACKP,CLEAR=RP_GRP,CLEAR=TRACKPG,CLEAR=RVPS,CLEAR=RTPS_BD
    empty!(trackp); empty!(rp_grp); empty!(trackpg); empty!(rvps); empty!(rtps_bd)

    # --- L145-156: automatic NCAP_AFC for ECT CHP ---------------------------------------------------------
    rvp = gmembers(tm, "RVP", 3)
    chp, chp_elc = gset(tm, "CHP").members, gset(tm, "CHP_ELC").keys
    chpr, ceh = gvalues(tm, "NCAP_CHPR", 4), gvalues(tm, "NCAP_CEH", 3)
    # L145: RVP(RTP(R,V,P))$((NOT RPS_CAFLAC(R,P,'ANNUAL','UP'))$(NCAP_CHPR(RTP,'UP')*NCAP_AFA(RTP,'UP')>0)$CHP(R,P))=YES
    for k in rtp
        ((k[1], k[3]) in chp && !((k[1], k[3], annual, "UP") in rps_caflac)) || continue
        get(chpr, (k..., "UP"), 0.0) * get(ncap_afa, (k..., "UP"), 0.0) > 0 && push!(rvp, k)
    end
    # L146: RVP(RTP)$(NCAP_CEH(RTP)<1.5) = NO
    filter!(k -> !(k in rtp && get(ceh, k, 0.0) < 1.5), rvp)
    # L148: VDA_CEH(RVP(R,V,P)) = MAX(0,SMAX((PRC_TS(R,P,S),CHP_ELC(R,P,C)),NCAP_AF(RVP,S,'UP')*PRC_ACTFLO(RVP,C)))
    vda_ceh = gvalues(tm, "VDA_CEH", 3)
    actflo = gvalues(tm, "PRC_ACTFLO", 4)
    ts_of = by2(gset(tm, "PRC_TS").keys)
    elc_of = by2(chp_elc)
    for (r, v, p) in rvp
        m = -Inf
        for s in get(ts_of, (r, p), String[]), c in get(elc_of, (r, p), String[])
            m = max(m, get(ncap_af, (r, v, p, s, "UP"), 0.0) * get(actflo, (r, v, p, c), 0.0))
        end
        gassign!(vda_ceh, (r, v, p), max(0.0, m))
    end
    # L149: RVP(RTP)$(VDA_CEH(RTP)<=0) = NO
    filter!(k -> !(k in rtp && get(vda_ceh, k, 0.0) <= 0), rvp)
    # L150: RPS_CAFLAC(R,P,ANNUAL,'UP') $= SUM(RVP(R,V,P)$VDA_CEH(RVP),1)
    foreach(k -> haskey(vda_ceh, k) && push!(rps_caflac, (k[1], k[3], annual, "UP")), rvp)
    # L152-155: NCAP_AFCS(RVP(R,V,P),C,ANNUAL) for the PG (heat) and CHP_ELC (electricity) commodities
    for (r, v, p) in rvp
        cr, afa, e = chpr[(r, v, p, "UP")], ncap_afa[(r, v, p, "UP")], vda_ceh[(r, v, p)]
        hs = 1 / (1 + 1 / cr)
        for c in get(rpcpg_of, (r, p), String[])
            gassign!(afcs, (r, v, p, c, annual), hs / afa / get(actflo, (r, v, p, c), 0.0) / (1 / afa - (1 - hs) / e))
        end
        for c in get(elc_of, (r, p), String[])
            gassign!(afcs, (r, v, p, c, annual), e / afa / get(actflo, (r, v, p, c), 0.0))
        end
    end
    # L156: OPTION CLEAR=RVP, VDA_CEH<NCAP_CEH   (the same domains, no index projected away: the values are
    #       copied, G34; a projection would count records, G31)
    empty!(rvp)
    vda_ceh = copy(ceh)

    # --- L159-164: NCAP_AFSX / NCAP_AFSM by control option ------------------------------------------------
    # L159: FIL(LL)=V(LL)+LASTLL(LL)
    fil = Set{Tuple{String}}((k[1],) for k in gset(tm, "ALLYEAR").keys if k[1] in modl || (k[1],) in gset(tm, "LASTLL").members)
    filset = Set(k[1] for k in fil)
    # L160: PRC_YMIN(R,P)$NCAP_AFX(R,'0',P) = FLOOR(NCAP_AFX(R,'0',P)/1000)
    ymin = gvalues(tm, "PRC_YMIN", 2)
    afx = gvalues(tm, "NCAP_AFX", 3)
    foreach(((k, x),) -> (k[1] in reg && k[2] == dflbl) && gassign!(ymin, (k[1], k[3]), floor(x / 1000)), collect(afx))
    y(r, p) = get(ymin, (r, p), 0.0)
    c2(r, p, bd) = (rem(y(r, p), 2) * 2 - 1) * (1 - 2 * (bd in bdupx)) < 0      # MOD takes the sign of the dividend (G43)
    # L161: NCAP_AFSX(R,FIL(LL),P,BD)$((NCAP_AFSX(R,LL,P,BD)=0)$(c2)$MOD(PRC_YMIN(R,P),7-4$V(LL))) $= NCAP_AFX(R,LL,P)
    afsx = gvalues(tm, "NCAP_AFSX", 4)
    for (k, x) in afx, bd in bds
        (r, ll, p) = k
        (r in reg && ll in filset && get(afsx, (r, ll, p, bd), 0.0) == 0.0 && c2(r, p, bd) && rem(y(r, p), ll in modl ? 3 : 7) != 0) || continue
        afsx[(r, ll, p, bd)] = x
    end
    # L162: RP_AFB(R,P,BD)$((MOD(PRC_YMIN(R,P)$(c2),5)=0)$PRC_YMIN(R,P)) = -1
    rp_afb = gvalues(tm, "RP_AFB", 3)
    for ((r, p), x) in ymin, bd in bds              # $PRC_YMIN(R,P): every record, EPS too (G3)
        r in reg || continue
        rem(c2(r, p, bd) ? x : 0.0, 5) == 0 && (rp_afb[(r, p, bd)] = -1.0)
    end
    # L163: NCAP_AFSM(R,FIL(LL),P)$MOD(FLOOR(NCAP_AFM(R,LL,P)/1000),7-4$V(LL)) $= NCAP_AFM(R,LL,P)
    afm, afsm = gvalues(tm, "NCAP_AFM", 3), gvalues(tm, "NCAP_AFSM", 3)
    for (k, x) in afm
        (k[1] in reg && k[2] in filset && rem(floor(x / 1000), k[2] in modl ? 3 : 7) != 0) && (afsm[k] = x)
    end
    # L164: NCAP_AFM(RTP(R,V,P))$((MOD(MAX(1,FLOOR(NCAP_AFM(R,'0',P)/1000)),5)=0)$NCAP_AFM(RTP)) = 0
    filter!(((k, _),) -> !(k in rtp && rem(max(1.0, floor(get(afm, (k[1], dflbl, k[3]), 0.0) / 1000)), 5) == 0), afm)

    # --- L167: equcrtp.vda PPM_EXT (L64-71): the dynamic UCs are not standard UCs -------------------------
    uc_on, uc_rs, uc_re = gmembers(tm, "UC_ON", 2), gmembers(tm, "UC_R_SUM", 2), gmembers(tm, "UC_R_EACH", 2)
    dyn = Set(k[1] for k in gset_opt(tm.data, "UC_DYNBND", 2).keys)
    for s in (uc_on, uc_rs, uc_re)
        filter!(k -> !(k[1] in reg && k[2] in dyn), s)
    end
    # L169: $IF NOT %RTS%==S $BATINCLUDE dynslite.vda POSTLEV   (%RTS% is S: ppm_ext! refuses DYNTS with TS_OFF)

    gput!(tm, "FLO_FUNCX", ffx)
    for (n, x) in (("TRACKP", trackp), ("RPCC_FFUNC", ccffunc), ("RPCG_PTRAN", ptran), ("RPC_FFUNC", ffunc), ("RPC_NOFLO", noflo),
                   ("PRC_ACT", prc_act), ("NO_ACT", no_act), ("TRACKPC", trackpc), ("RPG_1ACE", rpg_1ace), ("TRACKPG", trackpg),
                   ("RPC_EMIS", rpc_emis), ("KEEP_FLOF", keep_flof), ("RP_GRP", rp_grp), ("RPG_AFCX", rpg_afcx), ("RP_XRED", rp_xred),
                   ("RVPS", rvps), ("RTPS_BD", rtps_bd), ("RPS_CAFLAC", rps_caflac), ("RP_STL", rp_stl), ("RVP", rvp), ("FIL", fil),
                   ("UC_ON", uc_on), ("UC_R_SUM", uc_rs), ("UC_R_EACH", uc_re))
        gput!(tm, n, x)
    end
    for (n, x) in (("PRC_SC", prc_sc), ("NCAP_AFCS", afcs), ("NCAP_AFC", ncap_afc), ("NCAP_AFS", ncap_afs), ("VDA_CEH", vda_ceh),
                   ("PRC_YMIN", ymin), ("NCAP_AFSX", afsx), ("RP_AFB", rp_afb), ("NCAP_AFSM", afsm), ("NCAP_AFM", afm))
        gput!(tm, n, x)
    end
    return tm
end
