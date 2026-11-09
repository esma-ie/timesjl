# M1.3 (2), (3) and (5): the start of preprocessing, the ppmain.mod blocks of
# the init -> prep segment (docs/m13-plan.md); (3) ppmain_years! and (5)
# ppmain_rtp! are further down.
#
# GAMS: ppmain.mod L1-137, v4.9.7, run at maindrv.mod L56 after the
# extensions' init_ext (the init checkpoint).
#
# L13-29 declare the QA log file, scalars and sets; their data effects are in
# the dumps, taken after compilation. L35 (`$IF WARNINGS`) writes a group
# line to QA_CHECK.LOG when compilation raised warnings, which the dump does
# not record: the count is an input of the run (`qa_warnings!`, qalog.jl,
# M1.3 change 25b-1). Nothing else in L1-137 needs refusing.
#
# Index sets: R is REG, P is PRC, C and COM are COM, CG is COM_GRP, LL is
# ALLYEAR, S is ALL_TS; RPC_IRE, RP_IRE and TOP_IRE run over ALL_REG, so
# external regions stay in them but an index R skips them. `OPTION a < b`
# matches positions right to left and `<=` left to right, by domain (G26); an
# alias of COM at a COM_GRP position runs only over commodities (G27); a
# statement reads the values from before it (G11); `$x` is true for EPS (G12).
# %PGPRIM% is 'ACT' (initmty.mod). PYR is an alias of PASTYEAR
# (setglobs.gms L146).

"""
    ppmain_head_symbols(tm) -> Vector{String}

The symbols ppmain.mod L1-137 settles that nothing later in the init -> prep
segment changes (for the layer-1 check at the prep checkpoint), read on the
state after `ppmain_head!`. Some only on some models: RDCUR unless
G_CUREX/R_CUREX has data (curex.gms), NCAP_PASTI and PHYR unless
INT_DEFAULT('PASTI') (ppmain.mod L200-207 change them; `ppmain_rtp_symbols`
then compares them), INT_DEFAULT unless G_NOINTERP
(prepparm.gms L25), PRC_CAP unless NCAP_OLIFE has data (prepret.dsc L29
clears it; `preppm_symbols` then compares it). PASTYEAR is not settled
(ppmain.mod L160, L201); PASTSUM, TRACKP and the scalars F, MY_F, Z are used
again.
"""
function ppmain_head_symbols(tm)
    d = tm.data
    out = ["PRC_ACTUNT", "RPC_IRE", "RP_IRE", "TOP", "RPC", "RC", "RP", "RP_FLO", "RP_PG", "COM_GMAP", "RP_STS", "PRC_MAP",
           "PRC_STGIPS", "PRC_STGTSS", "PRC_TSL", "RPC_STGN", "PRC_ACT", "RPG_RED", "RPC_AIRE", "CG_GRP", "TRACKC", "TRACKPC"]
    isempty(gparam_opt(d, "NCAP_OLIFE", 3)) && push!(out, "PRC_CAP")
    isempty(gparam_opt(d, "G_CUREX", 2)) && isempty(gparam_opt(d, "R_CUREX", 3)) && push!(out, "RDCUR")
    ("PASTI",) in gset_opt(d, "INT_DEFAULT", 1).members || append!(out, ["NCAP_PASTI", "PHYR"])
    iszero(get(gparam_opt(d, "G_NOINTERP", 0).values, (), 0.0)) && push!(out, "INT_DEFAULT")
    return out
end

"""
    ppmain_head!(tm) -> tm

ppmain.mod L1-137 on the GAMS state in `tm` (the init checkpoint): the
discounted currencies, the trade, process and commodity control sets, the
primary groups, the storage defaults and the spread of past investments.

GAMS: ppmain.mod L1-137, v4.9.7.
"""
function ppmain_head!(tm)
    reg = gset(tm, "REG")
    com = gset(tm, "COM")
    io_set = [k[1] for k in gset(tm, "IO").keys]
    pg = uppercase(strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"']))
    dflbl = "0"                                                       # %DFLBL% (initmty.mod L367)
    # labels the block writes that a dump holds only when some record uses them (G36)
    foreach(l -> register_uel!(tm.data, l), ("IMP", "EXP", "IN", "OUT", "STG", "STK", "STS", "NST", "ANNUAL", "PASTI", pg))
    # L33-35: $IF WARNINGS, the QA log's 'GAMS Warnings Detected' group (qalog.jl)
    qa_compile_warnings!(tm)

    # --- Discounted currencies (L38) --------------------------------------------
    # L38: LOOP((R,LL(BOHYEAR),CUR)$G_DRATE(R,LL,CUR), RDCUR(R,CUR) = YES)
    boh = gset(tm, "BOHYEAR")
    rdcur = gmembers(tm, "RDCUR", 2)
    for k in keys(gparam_opt(tm.data, "G_DRATE", 3).values)          # EPS counts (G12)
        ((k[1],) in reg && (k[2],) in boh) && push!(rdcur, (k[1], k[3]))
    end
    gput!(tm, "RDCUR", rdcur)

    # --- Trade, process and commodity sets (L43-55) -------------------------------
    # L43: PRC_ACTUNT(R,P,%PGPRIM%,UNITS_ACT) = NO
    actunt = filter(k -> !(k[3] == pg && (k[1],) in reg), gmembers(tm, "PRC_ACTUNT", 4))
    gput!(tm, "PRC_ACTUNT", actunt)
    # L44-45: OPTION RPC_AIRE < TOP_IRE; RPC_IRE(RPC_AIRE,'IMP') = YES; OPTION RPC_AIRE <= TOP_IRE; RPC_IRE(RPC_AIRE,'EXP') = YES
    #   TOP_IRE(ALL_REG,COM,ALL_REG,COM,PRC) onto RPC_AIRE(ALL_REG,PRC,COM): `<` takes positions 3, 5, 4, `<=` 1, 5, 2
    top_ire = gset_opt(tm.data, "TOP_IRE", 5).keys
    rpc_ire = gmembers(tm, "RPC_IRE", 4)
    foreach(k -> push!(rpc_ire, (k..., "IMP")), project(top_ire, (3, 5, 4)))
    foreach(k -> push!(rpc_ire, (k..., "EXP")), project(top_ire, (1, 5, 2)))
    gput!(tm, "RPC_IRE", rpc_ire)
    # L46: OPTION CLEAR=RPC_AIRE, PRC_ACT < PRC_ACTUNT
    gput!(tm, "RPC_AIRE", Set{NTuple{3,String}}())
    prc_act = project(actunt, (1, 2))
    # L47: RP_IRE(ALL_R,P)$SUM(RPC_IRE(ALL_R,P,C,IE),1) = YES
    rp_ire = union!(gmembers(tm, "RP_IRE", 2), project(rpc_ire, (1, 2)))
    gput!(tm, "RP_IRE", rp_ire)
    # L48-49: TOP(RP_IRE(R,P),C,'IN')$RPC_IRE(R,P,C,'EXP') = NO; TOP(RP_IRE(R,P),C,'OUT')$RPC_IRE(R,P,C,'IMP') = NO
    top = gmembers(tm, "TOP", 4)
    filter!(k -> !((k[1],) in reg && (k[4] == "IN" ? (k[1], k[2], k[3], "EXP") in rpc_ire :
                                      k[4] == "OUT" && (k[1], k[2], k[3], "IMP") in rpc_ire)), top)
    # L50: TOP(RPG_RED(PRC_ACT(R,P),C,IO))$(COM_TMAP(R,'ENV',C)+RP_IRE(R,P)) = YES
    tmap = gset(tm, "COM_TMAP")
    for (r, p, c, io) in gset_opt(tm.data, "RPG_RED", 4).keys
        ((r, p) in prc_act && (c,) in com) || continue                 # C at the CG position: commodities only (G27)
        ((r, "ENV", c) in tmap || (r, p) in rp_ire) && push!(top, (r, p, c, io))
    end
    # L52: RPC(R,P,C)$(SUM(TOP(R,P,C,IO),1) + SUM(RPC_IRE(R,P,C,IE),1)) = YES
    rpc = gmembers(tm, "RPC", 3)
    foreach(k -> push!(rpc, (k[1], k[2], k[3])), top)
    for k in rpc_ire
        (k[1],) in reg && push!(rpc, (k[1], k[2], k[3]))
    end
    gput!(tm, "RPC", rpc)
    # L53-55: RC(R,C), RP(R,P) from RPC; RP_FLO(RP)$(NOT RP_IRE(RP)) = YES
    gput!(tm, "RC", union!(gmembers(tm, "RC", 2), project(rpc, (1, 3))))
    rp = union!(gmembers(tm, "RP", 2), project(rpc, (1, 2)))
    gput!(tm, "RP", rp)
    gput!(tm, "RP_FLO", union!(gmembers(tm, "RP_FLO", 2), filter(k -> !(k in rp_ire), rp)))

    # --- Primary groups (L58-65) --------------------------------------------------
    # L58: OPTION RP_PG < PRC_ACTUNT, CLEAR=RPG_RED, CLEAR=PRC_ACT
    rp_pg = project(actunt, (1, 2, 3))
    gput!(tm, "RPG_RED", Set{NTuple{4,String}}())
    # L59: PRC_ACT(RP)$(NOT SUM(RP_PG(RP,CG),1)) = YES
    has_pg = project(rp_pg, (1, 2))
    prc_act = Set{NTuple{2,String}}(k for k in rp if !(k in has_pg))
    # L60-63: IF(CARD(PRC_ACT),
    #   TRACKPC(PRC_ACT(R,P),C)$((NOT COM_TMAP(R,'ENV',C)+COM_TMAP(R,'FIN',C))$TOP(R,P,C,'OUT')) = YES;
    #   PRC_ACT(RP)$(SUM(TRACKPC(RP,C),1) NE 1) = NO; RP_PG(TRACKPC(PRC_ACT,C)) = YES; OPTION CLEAR=PRC_ACT,CLEAR=TRACKPC)
    #   NOT ranks below +: NOT (ENV + FIN)
    trackpc = gmembers(tm, "TRACKPC", 3)
    for (r, p, c, io) in top
        (io == "OUT" && (r, p) in prc_act) || continue
        ((r, "ENV", c) in tmap || (r, "FIN", c) in tmap) || push!(trackpc, (r, p, c))
    end
    npc = Dict{NTuple{2,String},Int}()
    foreach(k -> (npc[(k[1], k[2])] = get(npc, (k[1], k[2]), 0) + 1), trackpc)
    filter!(k -> get(npc, k, 0) == 1, prc_act)
    for k in trackpc
        (k[1], k[2]) in prc_act && push!(rp_pg, k)
    end
    gput!(tm, "RP_PG", rp_pg)
    gput!(tm, "PRC_ACT", Set{NTuple{2,String}}())
    empty!(trackpc)
    # L65: COM_GMAP(COM_TMAP) = YES
    gmap = union!(gmembers(tm, "COM_GMAP", 3), tmap.keys)
    gput!(tm, "COM_GMAP", gmap)

    # --- Storage defaults (L71-117) -----------------------------------------------
    # L72-73: TRACKC(R,C)$COM_LIM(R,C,'N') = YES; TRACKC(R,%PGPRIM%) = YES
    trackc = gmembers(tm, "TRACKC", 2)
    for k in gset_opt(tm.data, "COM_LIM", 3).keys
        (k[3] == "N" && (k[1],) in reg) && push!(trackc, (k[1], k[2]))
    end
    foreach(((r,),) -> push!(trackc, (r, pg)), reg.keys)
    # L76: RP_STS(R,P)$PRC_MAP(R,'STS',P) = YES
    prc_map = gmembers(tm, "PRC_MAP", 3)
    rp_sts = gmembers(tm, "RP_STS", 2)
    for (r, g, p) in prc_map
        (g == "STS" && (r,) in reg) && push!(rp_sts, (r, p))
    end
    gput!(tm, "RP_STS", rp_sts)
    # L77-79: TRACKP(R,P)$(PRC_MAP(R,'STG',P)+PRC_MAP(R,'STK',P)+RP_STS(R,P)) = YES;
    #         TRACKP(R,P)$SUM(PRC_STGTSS(R,P,C),1) = NO; TRACKP(R,P)$SUM(PRC_NSTTS(R,P,S),1) = NO
    trackp = gmembers(tm, "TRACKP", 2)
    for (r, g, p) in prc_map
        (g in ("STG", "STK") && (r,) in reg) && push!(trackp, (r, p))
    end
    union!(trackp, rp_sts)
    stgtss = gmembers(tm, "PRC_STGTSS", 3)
    nstts = gset_opt(tm.data, "PRC_NSTTS", 3).keys
    setdiff!(trackp, project(stgtss, (1, 2)))
    setdiff!(trackp, project(nstts, (1, 2)))
    # L80: TRACKPC(TRACKP(R,P),C)$SUM((TOP(R,P,C,IO),RP_PG(R,P,CG))$COM_GMAP(R,CG,C),1) = YES
    pg_by = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(pg_by, (k[1], k[2]), String[]), k[3]), rp_pg)
    for (r, p, c, _) in top
        (r, p) in trackp || continue
        any(cg -> (r, cg, c) in gmap, get(pg_by, (r, p), String[])) && push!(trackpc, (r, p, c))
    end
    # L81: TRACKPC(TRACKP(R,P),C)$SUM(RP_PG(R,P,C)$(NOT TRACKC(R,C)),1) = YES
    for (r, p, c) in rp_pg
        ((r, p) in trackp && (c,) in com && !((r, c) in trackc)) && push!(trackpc, (r, p, c))
    end
    # L83: RPC_STGN(TOP(TRACKP(R,P),C,IO))$SUM((COM_GMAP(R,COM_TYPE(CG),C),TRACKPC(R,P,COM))$COM_GMAP(R,CG,COM),1) = YES
    com_type = gset(tm, "COM_TYPE")
    tracked = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(tracked, (k[1], k[2]), String[]), k[3]), trackpc)
    rpc_stgn = gmembers(tm, "RPC_STGN", 4)
    for (r, p, c, io) in top
        (r, p) in trackp || continue
        coms = get(tracked, (r, p), String[])
        any(((cg,),) -> (r, cg, c) in gmap && any(cm -> (r, cg, cm) in gmap, coms), com_type.keys) && push!(rpc_stgn, (r, p, c, io))
    end
    # L84: OPTION CG_GRP < FLO_FUNC; RPC_STGN(RP,C,IO)$SUM(RPC_STGN(TRACKPC(RP,COM),IO),1) = NO   (G11: the old RPC_STGN)
    cg_grp = project(gparam_opt(tm.data, "FLO_FUNC", 6).keys, (1, 3, 4, 5))
    stored_io = Set{NTuple{3,String}}((r, p, io) for (r, p, c, io) in rpc_stgn if (r, p, c) in trackpc)
    filter!(k -> !((k[1], k[2]) in rp && (k[1], k[2], k[4]) in stored_io), rpc_stgn)
    # L85: LOOP(CG_GRP(TRACKP(RP),C,COM), IF(TRACKPC(RP,C), RPC_STGN(RP,COM,IO)=NO ELSEIF TRACKPC(RP,COM), RPC_STGN(RP,C,IO)=NO))
    for (r, p, c, cm) in cg_grp
        ((r, p) in trackp && (r, p) in rp && (c,) in com && (cm,) in com) || continue
        drop = (r, p, c) in trackpc ? cm : (r, p, cm) in trackpc ? c : nothing
        drop === nothing || foreach(io -> delete!(rpc_stgn, (r, p, drop, io)), io_set)
    end
    # L86: TRACKPC(RPC) $= SUM(RPC_STGN(RPC,IO),1)
    for (r, p, c, _) in rpc_stgn
        (r, p, c) in rpc && push!(trackpc, (r, p, c))
    end
    # L89-93: LOOP(PRC_NSTTS(R,P,S), PRC_MAP(R,'STG',P) = YES; PRC_MAP(R,'NST',P) = YES; PRC_MAP(R,'STK',P) = NO)
    for (r, p, _) in nstts
        push!(prc_map, (r, "STG", p), (r, "NST", p))
        delete!(prc_map, (r, "STK", p))
    end
    # L95: PRC_STGIPS(TRACKPC(R,P,C))$PRC_MAP(R,'STK',P) = YES
    stgips = gmembers(tm, "PRC_STGIPS", 3)
    foreach(k -> (k[1], "STK", k[2]) in prc_map && push!(stgips, k), trackpc)
    # L96-102: LOOP(PRC_STGIPS(R,P,C), PRC_MAP(R,'STG',P) = YES; PRC_MAP(R,'STK',P) = YES; PRC_MAP(R,'NST',P) = NO;
    #   IF(NOT SUM(TOP(R,P,C,IO),1),TOP(R,P,C,IO)=YES); IF(NOT RP_STS(R,P),PRC_TSL(R,P,TSLVL) = SAMEAS(TSLVL,'ANNUAL')))
    prc_tsl = gmembers(tm, "PRC_TSL", 3)
    no_top(r, p, c) = !any(io -> (r, p, c, io) in top, io_set)
    for (r, p, c) in stgips
        push!(prc_map, (r, "STG", p), (r, "STK", p))
        delete!(prc_map, (r, "NST", p))
        no_top(r, p, c) && foreach(io -> push!(top, (r, p, c, io)), io_set)
        if !((r, p) in rp_sts)
            filter!(k -> !(k[1] == r && k[2] == p), prc_tsl)
            push!(prc_tsl, (r, p, "ANNUAL"))
        end
    end
    # L104: PRC_STGTSS(TRACKPC(R,P,C))$(NOT PRC_MAP(R,'STK',P)) = YES
    foreach(k -> (k[1], "STK", k[2]) in prc_map || push!(stgtss, k), trackpc)
    # L105-111: LOOP(PRC_STGTSS(R,P,C), PRC_MAP(R,'STG',P) = YES; PRC_MAP(R,'STS',P) = YES; PRC_MAP(R,'NST',P) = NO;
    #   PRC_MAP(R,'STK',P) = NO; IF(NOT SUM(TOP(R,P,C,IO),1),TOP(R,P,C,IO)=YES))
    for (r, p, c) in stgtss
        push!(prc_map, (r, "STG", p), (r, "STS", p))
        delete!(prc_map, (r, "NST", p))
        delete!(prc_map, (r, "STK", p))
        no_top(r, p, c) && foreach(io -> push!(top, (r, p, c, io)), io_set)
    end
    gput!(tm, "PRC_MAP", prc_map)
    gput!(tm, "PRC_STGIPS", stgips)
    gput!(tm, "PRC_STGTSS", stgtss)
    gput!(tm, "PRC_TSL", prc_tsl)
    # L113: OPTION CLEAR=TRACKC,CLEAR=TRACKP,CLEAR=TRACKPC,CLEAR=CG_GRP,CLEAR=RPC_STGN
    gput!(tm, "TRACKC", Set{NTuple{2,String}}())
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    gput!(tm, "TRACKPC", Set{NTuple{3,String}}())
    gput!(tm, "CG_GRP", Set{NTuple{4,String}}())
    # L115-116: RPC_STGN(PRC_STGTSS(R,P,C),IO)$(NOT SUM(TOP(R,P,COM,IO)$PRC_STGTSS(R,P,COM),1)) = YES; the same for PRC_STGIPS
    rpc_stgn = Set{NTuple{4,String}}()
    for stg in (stgtss, stgips)
        stored = Dict{NTuple{2,String},Vector{String}}()
        foreach(k -> push!(get!(stored, (k[1], k[2]), String[]), k[3]), stg)
        for (r, p, c) in stg, io in io_set
            any(cm -> (r, p, cm, io) in top, stored[(r, p)]) || push!(rpc_stgn, (r, p, c, io))
        end
    end
    gput!(tm, "RPC_STGN", rpc_stgn)
    # L117: TOP(RPC_STGN) = YES
    union!(top, rpc_stgn)
    gput!(tm, "TOP", top)

    # --- Spread of past investments (L122-136) --------------------------------------
    # L124: OPTION PRC_CAP < NCAP_PASTY
    pasty = gparam_opt(tm.data, "NCAP_PASTY", 3)
    prc_cap = project(pasty.keys, (1, 3))
    # L125-130: LOOP((PRC_CAP(RP(R,P)),PASTYEAR(LL))$(NCAP_PASTY(R,PASTYEAR,P) > 1),
    #   F = NCAP_PASTY(R,LL,P); MY_F = NCAP_PASTI(R,LL,P) / F;
    #   FOR(Z = F-1 DOWNTO 0, PASTSUM(R,ALLYEAR(LL-Z),P) = PASTSUM(R,ALLYEAR,P) + MY_F);
    #   NCAP_PASTI(R,LL,P) = 0)
    # In GAMS loop order (R, P, then LL); a lag by a non-integer Z is rounded (G29); a lag before the first year selects nothing.
    allyear = [k[1] for k in gset(tm, "ALLYEAR").keys]
    pos = Dict(y => i for (i, y) in enumerate(allyear))
    pastyear = [k[1] for k in gset(tm, "PASTYEAR").keys]
    pasti = gvalues(tm, "NCAP_PASTI", 3)
    pastsum = Dict{NTuple{3,String},Float64}()
    loop_rp = gams_sort!([k for k in prc_cap if k in rp], tm.data)
    for (r, p) in loop_rp, ll in pastyear
        f = get(pasty.values, (r, ll, p), 0.0)
        f > 1 || continue
        my_f = gv(pasti, (r, ll, p)) / GNum(f)
        z = f - 1
        while z >= 0
            j = pos[ll] - glead(z)
            j >= 1 && gassign!(pastsum, (r, allyear[j], p), gv(pastsum, (r, allyear[j], p)) + my_f)
            z -= 1
        end
        delete!(pasti, (r, ll, p))
    end
    # L132: NCAP_PASTI(R,LL,P)$PASTSUM(R,LL,P) = NCAP_PASTI(R,LL,P) + PASTSUM(R,LL,P)
    for k in keys(pastsum)
        gassign!(pasti, k, gv(pasti, k) + gv(pastsum, k))
    end
    gput!(tm, "NCAP_PASTI", pasti)
    # L134-135: OPTION PASTYEAR < NCAP_PASTI; INT_DEFAULT('PASTI')$PYR('0')=1; PYR('0')=NO
    pyr = project(keys(pasti), (2,))
    if (dflbl,) in pyr
        intd = gmembers(tm, "INT_DEFAULT", 1)
        push!(intd, ("PASTI",))
        gput!(tm, "INT_DEFAULT", intd)
        delete!(pyr, (dflbl,))
    end
    gput!(tm, "PASTYEAR", pyr)
    # L136: OPTION CLEAR=PRC_CAP, CLEAR=PASTSUM
    gput!(tm, "PRC_CAP", Set{NTuple{2,String}}())
    gput!(tm, "PASTSUM", Dict{NTuple{3,String},Float64}())
    return tm
end

# M1.3 (3): ppmain.mod L138-191, the years and periods.
#
# T and TT are aliases of MILESTONYR (initmty.mod L94), so `T++1`, `T--1`,
# `TT-1` and `TT+1` move along the milestones (circularly for ++ and --); LL
# and YEAR are aliases of ALLYEAR (initsys.mod L59), so `LL-n` and
# `ALLYEAR+n` move along ALLYEAR, whose last element is '0' (`YearAxis`).
# %OBLONG% is YES when the run sets it or %OBJ% is MOD (initmty.mod L427).
# The filparam.gms scratch (Z, F, MY_F, MY_FYEAR, DFUNC, FIRST_VAL, LAST_VAL,
# MY_ARRAY, UNCD7) is not kept: every later use assigns it first.

"""
    ppmain_years_symbols(tm) -> Vector{String}

The symbols ppmain.mod L138-191 settles that nothing later in the init -> prep
segment changes (for the layer-1 check at the prep checkpoint), read on the
state after `ppmain_years!`. B, E, D, M, PASTYEAR and PASTMILE only without
INT_DEFAULT('PASTI'), which migrates past investments at ppmain.mod L200-207
(`ppmain_rtp_symbols` then compares them).
"""
function ppmain_years_symbols(tm)
    out = ["ALTOBJ", "MIYR_1", "MIYR_V1", "MIYR_VL", "MIYR_L", "LEAD", "LAGT", "IPD", "FPD", "MINYR", "PYR_V1", "EOHYEARS",
           "PERIODYR", "G_OFFTHD"]
    ("PASTI",) in gset_opt(tm.data, "INT_DEFAULT", 1).members || append!(out, ["B", "E", "D", "M", "PASTYEAR", "PASTMILE"])
    return out
end

"""
    ppmain_years!(tm) -> tm

ppmain.mod L138-191 on the state after `ppmain_head!`: period lengths and
middle years (and, for the alternative objective, the periods themselves), the
first and last years, LEAD/LAGT, IPD/FPD, MINYR, the past years treated as
periods (PASTMILE), EOHYEARS, PERIODYR and the interpolation of G_OFFTHD.

GAMS: ppmain.mod L138-191, filparam.gms L19-42, v4.9.7.
"""
function ppmain_years!(tm)
    ax = YearAxis(tm)
    yv(y) = ax.yearval[y]
    tset = [k[1] for k in gset(tm, "MILESTONYR").keys]
    n = length(tset)
    obj = uppercase(gswitch(tm, "OBJ", ""))
    oblong = uppercase(gswitch(tm, "OBLONG", "")) == "YES" || obj == "MOD"
    B, E, D, M = (gvalues(tm, s, 1) for s in ("B", "E", "D", "M"))
    val(p, y) = Float64(gv(p, (y,)))

    # --- Period lengths and middle years (L143-146) ---------------------------------
    # L143-144: D(MILESTONYR) = E-B+1; M(MILESTONYR) = FLOOR(B+(D-1)/2)
    foreach(t -> gassign!(D, (t,), val(E, t) - val(B, t) + 1), tset)
    foreach(t -> gassign!(M, (t,), floor(val(B, t) + (val(D, t) - 1) / 2)), tset)
    # L145: $IFI %OBJ%==MOD M(T) = 0
    obj == "MOD" && foreach(t -> delete!(M, (t,)), tset)
    # L146: IF(ALTOBJ=1, ALTOBJ=1$SUM(T,M(T) NE YEARVAL(T)))
    altobj = gscalar(tm, "ALTOBJ")
    altobj == 1 && (altobj = any(t -> val(M, t) != yv(t), tset) ? 1.0 : 0.0)

    # --- First and last years, the alternative objective's periods (L149-160) -------
    # L149: MIYR_1(T)$(ORD(T) = 1) = YES
    miyr_1 = gmembers(tm, "MIYR_1", 1)
    n > 0 && push!(miyr_1, (tset[1],))
    if altobj != 0
        # L152: E(T(TT-1)) = FLOOR((YEARVAL(T)+YEARVAL(TT))/2); B(T(TT+1)) = E(TT)+1   (B reads the new E, G11)
        foreach(i -> gassign!(E, (tset[i-1],), floor((yv(tset[i-1]) + yv(tset[i])) / 2)), 2:n)
        foreach(i -> gassign!(B, (tset[i+1],), val(E, tset[i]) + 1), 1:n-1)
        # L153: B(MIYR_1(T))$(ABS(B(T)-(YEARVAL(T)-5)) GT 5) = YEARVAL(T)
        for t in tset
            ((t,) in miyr_1 && abs(val(B, t) - (yv(t) - 5)) > 5) && gassign!(B, (t,), yv(t))
        end
        # L154: E(T)$((ABS(E(T)-(YEARVAL(T)+15)) GT 15)$(ORD(T)=CARD(T))) = 2*YEARVAL(T)-B(T)+1-1$MOD(YEARVAL(T)-B(T)+1,5)
        if n > 0
            t = tset[n]
            if abs(val(E, t) - (yv(t) + 15)) > 15
                gassign!(E, (t,), 2 * yv(t) - val(B, t) + 1 - (rem(yv(t) - val(B, t) + 1, 5) != 0 ? 1 : 0))
            end
        end
        # L155: D(T) = E(T)-B(T)+1; M(T) = YEARVAL(T)
        foreach(t -> gassign!(D, (t,), val(E, t) - val(B, t) + 1), tset)
        foreach(t -> gassign!(M, (t,), yv(t)), tset)
    end
    # L157-158: MIYR_V1 = SMIN(MIYR_1, B(MIYR_1)); MIYR_VL = SMAX(T$(ORD(T) = CARD(T)), E(T))   (over nothing: +INF, -INF)
    miyr_v1 = minimum((val(B, y) for (y,) in miyr_1); init=Inf)
    miyr_vl = n > 0 ? val(E, tset[n]) : -Inf
    # L159: $IFI '%OBLONG%'==YES IF(MIYR_V1+SUM(T,E(T)+1-B(T))-MIYR_VL NE 1, ABORT "Inconsistent periods - cannot use OBLONG.")
    if oblong && miyr_v1 + sum((val(E, t) + 1 - val(B, t) for t in tset); init=0.0) - miyr_vl != 1
        error("ppmain.mod L159: ABORT \"Inconsistent periods - cannot use OBLONG.\"")
    end
    # L160: LOOP(MIYR_1(LL), PASTYEAR(LL-(YEARVAL(LL)-MIYR_V1+1)) = YES)
    pastyear = gmembers(tm, "PASTYEAR", 1)
    for (ll,) in miyr_1
        y = lead(ax, ll, -glead(yv(ll) - miyr_v1 + 1))
        y === nothing || push!(pastyear, (y,))
    end

    # --- LEAD, LAGT, IPD, FPD, MINYR, PYR_V1 (L162-169) ------------------------------
    # L162: LEAD(TT(T++1)) = MAX(M(TT)-M(T),M(TT)-B(TT)+1); L163: LAGT(TT(T--1)) = MAX(M(T)-M(TT),E(TT)-M(TT)+1)
    LEAD, LAGT = gvalues(tm, "LEAD", 1), gvalues(tm, "LAGT", 1)
    for i in 1:n
        t, nx, pv = tset[i], tset[mod1(i + 1, n)], tset[mod1(i - 1, n)]
        gassign!(LEAD, (nx,), max(val(M, nx) - val(M, t), val(M, nx) - val(B, nx) + 1))
        gassign!(LAGT, (pv,), max(val(M, t) - val(M, pv), val(E, pv) - val(M, pv) + 1))
    end
    # L164-165: IF(ALTOBJ, IPD(T) = LEAD(T)+MIN(E(T)-M(T),LEAD(T)-1)$MIYR_1(T); ELSE IPD(T) = D(T)); FPD(T) = D(T)
    IPD, FPD = gvalues(tm, "IPD", 1), gvalues(tm, "FPD", 1)
    for t in tset
        ld = val(LEAD, t)
        gassign!(IPD, (t,), altobj != 0 ? ld + ((t,) in miyr_1 ? min(val(E, t) - val(M, t), ld - 1) : 0.0) : val(D, t))
        gassign!(FPD, (t,), val(D, t))
    end
    # L168: MINYR = MIN(MIYR_V1-1, SMIN(T,M(T)-IPD(T))+1)
    minyr = min(miyr_v1 - 1, minimum((val(M, t) - val(IPD, t) for t in tset); init=Inf) + 1)
    # L169: PYR_V1 = MIN(SMIN(PASTYEAR,YEARVAL(PASTYEAR)),MINYR)
    pyr_v1 = min(minimum((yv(y) for (y,) in pastyear); init=Inf), minyr)

    # --- MIYR_L, PASTMILE (L171-180) -------------------------------------------------
    # L171: LOOP(MIYR_1(ALLYEAR), Z=MIYR_VL-YEARVAL(ALLYEAR); MIYR_L(ALLYEAR+Z) = YES)
    miyr_l = gmembers(tm, "MIYR_L", 1)
    for (y,) in miyr_1
        l = lead(ax, y, glead(miyr_vl - yv(y)))
        l === nothing || push!(miyr_l, (l,))
    end
    # L176: PASTMILE(PASTYEAR)$((YEARVAL(PASTYEAR) LE MIYR_VL)$(NOT T(PASTYEAR))) = YES
    tmem = Set(tset)
    pastmile = gmembers(tm, "PASTMILE", 1)
    for (y,) in pastyear
        (yv(y) <= miyr_vl && !(y in tmem)) && push!(pastmile, (y,))
    end
    # L177-180: M(PASTMILE) = YEARVAL(PASTMILE); B(PASTMILE) = M(PASTMILE); E(PASTMILE) = M(PASTMILE); D(PASTMILE) = 1
    for (y,) in pastmile
        gassign!(M, (y,), yv(y))
        gassign!(B, (y,), val(M, y))
        gassign!(E, (y,), val(M, y))
        gassign!(D, (y,), 1.0)
    end

    # --- EOHYEARS, PERIODYR (L184-186) ----------------------------------------------
    # L184: EOHYEARS(ALLYEAR)$((YEARVAL(ALLYEAR) >= MINYR) * (YEARVAL(ALLYEAR) <= MIYR_VL)) = YES
    eohyears = gmembers(tm, "EOHYEARS", 1)
    foreach(y -> (minyr <= yv(y) <= miyr_vl) && push!(eohyears, (y,)), ax.years)
    # L186: PERIODYR(T,EOHYEARS)$((YEARVAL(EOHYEARS) >= B(T)) * (YEARVAL(EOHYEARS) <= E(T))) = YES
    periodyr = gmembers(tm, "PERIODYR", 2)
    for t in tset, (y,) in eohyears
        (val(B, t) <= yv(y) <= val(E, t)) && push!(periodyr, (t, y))
    end

    # --- G_OFFTHD (L189-190) -----------------------------------------------------------
    # L189: $IF DEFINED G_OFFTHD $BATINCLUDE filparam G_OFFTHD '' '' ",'','','','','',''" YEAR T '' '' 5
    #   DEFINED is decided at compile time from the DD data; with no records filparam does nothing either way
    g_offthd = filparam_g_offthd(gvalues(tm, "G_OFFTHD", 1), ax, tset)
    # L190: G_OFFTHD('0') = 0
    delete!(g_offthd, ("0",))

    for (s, v) in (("B", B), ("E", E), ("D", D), ("M", M), ("LEAD", LEAD), ("LAGT", LAGT), ("IPD", IPD), ("FPD", FPD),
                   ("G_OFFTHD", g_offthd))
        gput!(tm, s, v)
    end
    for (s, v) in (("MIYR_1", miyr_1), ("PASTYEAR", pastyear), ("MIYR_L", miyr_l), ("PASTMILE", pastmile),
                   ("EOHYEARS", eohyears), ("PERIODYR", periodyr))
        gput!(tm, s, v)
    end
    for (s, v) in (("ALTOBJ", altobj), ("MIYR_V1", miyr_v1), ("MIYR_VL", miyr_vl), ("MINYR", minyr), ("PYR_V1", pyr_v1))
        gput_scalar!(tm, s, v)
    end
    return tm
end

"""
    filparam_g_offthd(g, ax, tset) -> Dict

filparam.gms with ppmain.mod L189's arguments: G_OFFTHD(YEAR) interpolated
between its data years over the milestones `tset` and extrapolated over them,
by the option DFUNC = ROUND(G_OFFTHD('0')), 5 when that is zero or EPS (< 0 none;
1 interpolation only; 2 EPS outside the data; 4 no forward, 5 no backward
extrapolation; above 1 by its last digit). Data years are YEAR (an alias of
ALLYEAR) in GAMS order without '0'; EPS counts as data (G12). Returns `g`
with the new values.

GAMS: filparam.gms L19-42 (ppmain.mod L189), v4.9.7.
"""
function filparam_g_offthd(g::Dict{Tuple{String},Float64}, ax::YearAxis, tset::Vector{String})
    # L21: UNCD7 holds the one tuple when G_OFFTHD has a record in any YEAR ('0' and EPS included)
    isempty(g) && return g
    # L23-25: F=0; Z=INF; MY_FYEAR=9999; DFUNC = ROUND(G_OFFTHD('0')); IF(NOT DFUNC, DFUNC = 5)
    F, Z, my_fyear = 0.0, Inf, 9999.0
    dfunc = round(Float64(gv(g, ("0",))), RoundNearestTiesAway)   # ROUND(EPS) is a plain 0 (G38)
    dfunc == 0 && (dfunc = 5.0)
    dfunc >= 0 || return g                                      # L26
    # L27: MY_ARRAY(YEAR) = G_OFFTHD(YEAR); MY_ARRAY('0') = 0
    my_array = [(y, gv(g, (y,))) for y in ax.years if y != "0" && haskey(g, (y,))]
    first_val, last_val = GZERO, GZERO                          # only read once a data year has set them
    # L29-35: data years in GAMS order; linear interpolation over T between consecutive data years
    for (y, my_f) in my_array
        Zy = ax.yearval[y]
        if Zy > my_fyear + 1
            for t in tset
                yt = ax.yearval[t]
                (Zy > yt && yt > my_fyear) || continue
                gassign!(g, (t,), last_val + (my_f - last_val) / GNum(Zy - my_fyear) * GNum(yt - my_fyear))
            end
        elseif Zy < my_fyear
            F, first_val = Zy, my_f
        end
        last_val, my_fyear, Z = my_f, Zy, Zy
    end
    # L37-40: IF(DFUNC GT 1, DFUNC=MOD(DFUNC,10); 2: EPS both ways; 4: Z=INF; 5: F=0); IF(DFUNC NE 1, G_OFFTHD(T) $= ...)
    if dfunc > 1
        dfunc = rem(dfunc, 10)
        if dfunc == 2
            first_val, last_val = GEPS, GEPS
        elseif dfunc == 4
            Z = Inf
        elseif dfunc == 5
            F = 0.0
        end
    end
    dfunc != 1 || return g
    for t in tset
        yt = ax.yearval[t]
        x = gif(first_val, yt < F) + gif(last_val, yt > Z)
        iszero(x) || gassign!(g, (t,), x)                       # $= (G24)
    end
    return g
end

# M1.3 (5): ppmain.mod L199-247, the migration of past investments on
# milestones, NCAP_START, the periods without new capacity (RTP_OFF) and the
# process/period sets RTP and RVP.
#
# T is MILESTONYR, LL and YEAR are ALLYEAR, PYR is PASTYEAR, R is REG, P is
# PRC. `LL-1` and the lead at L217 move along ALLYEAR, whose last element is
# '0' (LASTLL, initmty.mod L369); a non-integer lead is rounded (G29). ORD on
# BOHYEAR and EOHYEAR is each set's own order: BOHYEAR is 'BOH' and the years,
# EOHYEAR adds 'EOH' (initsys.mod L40-44), so `ORD(EOHYEAR)+%BOTIME%-2` is the
# year itself. %BOTIME% is 1850 unless the run sets it (initsys.mod L35).
#
# The QA log (M1.3 change 25b-1): L213 starts a group, L229-230 warn when a
# delayed process has past investment (in LOOP order). The scratch Z is not
# kept: every later use assigns it first. FIL, STARTOFF and ENDOFF are, as
# pp_off.mod leaves them (`pp_off_keep!`): a checkpoint dump holds them.

"""
    ppmain_rtp_symbols(tm) -> Vector{String}

The symbols ppmain.mod L199-247 settles that nothing later in the init -> prep
segment changes (for the layer-1 check at the prep checkpoint), read on the
state after `ppmain_rtp!`. RTP unless fillvint.gms L15-19 (PRC_SIMV data, or
%VINTOPT% 2) or powerflo.vda can change it; RVP also only without PRC_VINT
(fillvint.gms L18 and preppm.mod L61 add vintage years). With
INT_DEFAULT('PASTI'), the symbols L200-207 change that ppmain_head_symbols and
ppmain_years_symbols leave out. PRC_YMAX is cleared by prep_ext.vda L48;
TRACKP, UNCD1 and PASTSUM are scratch, used again.
"""
function ppmain_rtp_symbols(tm)
    d = tm.data
    out = ["PRC_NOFF", "RTP_OFF", "VNT", "COEF_RTP"]
    simv = !isempty(gset_opt(d, "PRC_SIMV", 2).keys) || strip(gswitch(tm, "VINTOPT", "")) == "2" ||
           uppercase(gswitch(tm, "POWERFLO", "")) == "YES"
    simv || push!(out, "RTP")
    (simv || !isempty(gset_opt(d, "PRC_VINT", 2).keys)) || push!(out, "RVP")
    ("PASTI",) in gset_opt(d, "INT_DEFAULT", 1).members &&
        append!(out, ["B", "E", "D", "M", "PASTYEAR", "PASTMILE", "NCAP_PASTI", "PHYR"])
    return out
end

"""
    ppmain_rtp!(tm) -> tm

ppmain.mod L199-247 on the state after `timslice!`: with INT_DEFAULT('PASTI'),
past investments on milestones moved to the year before (L200-207); NCAP_START
as PRC_NOFF ranges (L215-217); the periods without new capacity of delayed
processes and of the later PRC_NOFF ranges (RTP_OFF, L219-238, the latter with
pp_off.mod); RTP and RVP (L239-241). A division by zero (a period of length 0
at L224) raises an error, as it stops a GAMS run.

GAMS: ppmain.mod L199-247, pp_off.mod L17-22 (L237), v4.9.7.
"""
function ppmain_rtp!(tm)
    d = tm.data
    ax = YearAxis(tm)
    yv(y) = ax.yearval[y]
    tset = [k[1] for k in gset(tm, "MILESTONYR").keys]
    tmem = Set(tset)
    reg = gset(tm, "REG")
    rp = gset(tm, "RP").members
    val(p, y) = Float64(gv(p, (y,)))
    pasti = gvalues(tm, "NCAP_PASTI", 3)
    pastyear = gmembers(tm, "PASTYEAR", 1)
    dflbl = "0"                                                       # %DFLBL%, LASTLL (initmty.mod L367-369)

    # --- Past investments on milestones (L200-207) -----------------------------------
    if ("PASTI",) in gset_opt(d, "INT_DEFAULT", 1).members
        B, E, D, M = (gvalues(tm, s, 1) for s in ("B", "E", "D", "M"))
        pastmile, vnt = gmembers(tm, "PASTMILE", 1), gmembers(tm, "VNT", 2)
        coef_rtp = gvalues(tm, "COEF_RTP", 3)
        # L200: LOOP(PYR(T(LL))$(M(T)>B(T)), VNT(LL-1,T)=YES)
        for t in tset
            ((t,) in pastyear && val(M, t) > val(B, t)) || continue
            ll = lead(ax, t, -1)
            ll === nothing || push!(vnt, (ll, t))
        end
        # L201-205: LOOP(VNT(LL,T), B(LL)=M(T)-1; E(LL)=M(T); M(LL)=B(LL); D(LL)=2; PASTYEAR(T)=NO;
        #   PASTSUM(R,T,P)$NCAP_PASTI(R,T,P) = NCAP_PASTI(R,LL,P)+NCAP_PASTI(R,T,P)+1-1;
        #   COEF_RTP(R,LL,P)$PASTSUM(R,T,P) = NCAP_PASTI(R,T,P) / PASTSUM(R,T,P);
        #   NCAP_PASTI(R,LL,P)$=PASTSUM(R,T,P); NCAP_PASTI(R,T,P)=0; OPTION CLEAR=PASTSUM)
        #   in GAMS order: a pair reads what the pairs before it wrote
        for (ll, t) in gams_sort!(collect(vnt), d)
            gassign!(B, (ll,), gv(M, (t,)) - GNum(1))
            gassign!(E, (ll,), gv(M, (t,)))
            gassign!(M, (ll,), gv(B, (ll,)))                         # the new B (G11)
            gassign!(D, (ll,), 2.0)
            delete!(pastyear, (t,))
            pastsum = Dict{NTuple{2,String},GNum}()
            for k in keys(pasti)                                      # $NCAP_PASTI: EPS counts (G12)
                (k[2] == t && (k[1],) in reg) || continue
                s = gv(pasti, (k[1], ll, k[3])) + gv(pasti, k) + GNum(1) - GNum(1)   # left to right, as GAMS
                iszero(s) || (pastsum[(k[1], k[3])] = s)
            end
            foreach((((r, p), s),) -> gassign!(coef_rtp, (r, ll, p), gv(pasti, (r, t, p)) / s), pastsum)
            foreach((((r, p), s),) -> gassign!(pasti, (r, ll, p), s), pastsum)
            filter!(((k, _),) -> !(k[2] == t && (k[1],) in reg), pasti)
        end
        # L206: VNT(PASTMILE,T)$PERIODYR(T,PASTMILE)=YES
        for (t, y) in gset(tm, "PERIODYR").keys
            (t in tmem && (y,) in pastmile) && push!(vnt, (y, t))
        end
        # L207: OPTION PHYR<=VNT; PYR(PHYR)=YES; PASTMILE(PHYR)=YES   (`<=` matches left to right, G26)
        phyr = Set{Tuple{String}}((k[1],) for k in vnt)
        union!(pastyear, phyr)
        union!(pastmile, phyr)
        for (s, v) in (("B", B), ("E", E), ("D", D), ("M", M), ("COEF_RTP", coef_rtp), ("NCAP_PASTI", pasti))
            gput!(tm, s, v)
        end
        for (s, v) in (("PASTYEAR", pastyear), ("PASTMILE", pastmile), ("VNT", vnt), ("PHYR", phyr))
            gput!(tm, s, v)
        end
        gput!(tm, "PASTSUM", Dict{NTuple{3,String},Float64}())
    end

    # L213: PUTGRP = 0
    qa_group!(tm)

    # --- NCAP_START as PRC_NOFF (L215-217) ---------------------------------------------
    # L215-217: LOOP(LASTLL(LL)$CARD(NCAP_START), Z=CARD(LL)+%BOTIME%;
    #   PRC_NOFF(RP,'BOH',EOHYEAR)$NCAP_START(RP) = NO;
    #   PRC_NOFF(RP,'BOH',LL+MIN(-1,NCAP_START(RP)-Z))$NCAP_START(RP) = YES)
    botime = parse(Float64, gswitch(tm, "BOTIME", "1850"))
    boh, eoh = OrdAxis(tm, "BOHYEAR"), OrdAxis(tm, "EOHYEAR")
    prc_noff = gmembers(tm, "PRC_NOFF", 4)
    ncap_start = gparam_opt(d, "NCAP_START", 2).values
    if !isempty(ncap_start)
        z = length(ax.years) + botime
        starts = [(k, v) for (k, v) in ncap_start if k in rp]          # EPS counts (G12)
        started = Set(k for (k, _) in starts)
        filter!(k -> !(k[3] == "BOH" && haskey(eoh.pos, k[4]) && (k[1], k[2]) in started), prc_noff)
        for ((r, p), v) in starts
            y = lead(ax, dflbl, glead(min(-1.0, v - z)))
            y === nothing || push!(prc_noff, (r, p, "BOH", y))
        end
    end
    gput!(tm, "PRC_NOFF", prc_noff)
    # ranges of the processes in RP, by process, BOHYEAR to EOHYEAR
    ranges = Dict{NTuple{2,String},Vector{NTuple{2,String}}}()
    for (r, p, b, e) in gams_sort!(collect(prc_noff), d)
        ((r, p) in rp && haskey(boh.pos, b) && haskey(eoh.pos, e)) && push!(get!(ranges, (r, p), NTuple{2,String}[]), (b, e))
    end

    # --- Delayed processes (L219-232) ----------------------------------------------------
    # L219-220: OPTION CLEAR=PRC_YMAX, CLEAR=UNCD1; UNCD1('BOH') = YES; UNCD1(YEAR)$(YEARVAL(YEAR) LE MIYR_V1) = YES
    miyr_v1 = gscalar(tm, "MIYR_V1")
    uncd1 = Set{Tuple{String}}([("BOH",)])
    foreach(y -> yv(y) <= miyr_v1 && push!(uncd1, (y,)), ax.years)
    # L221: PRC_YMAX(RP(R,P)) = MAX(0,SMAX(PRC_NOFF(R,P,BOHYEAR(UNCD1),EOHYEAR),ORD(EOHYEAR)+%BOTIME%-2))
    prc_ymax = Dict{NTuple{2,String},Float64}()
    for (k, rs) in ranges
        x = maximum((Float64(eoh.pos[e]) + botime - 2 for (b, e) in rs if (b,) in uncd1); init=-Inf)
        gassign!(prc_ymax, k, max(0.0, x))
    end
    ymax(k) = Float64(gv(prc_ymax, k))
    # L223: TRACKP(RP) $= PRC_YMAX(RP)
    trackp = Set{NTuple{2,String}}(k for k in keys(prc_ymax) if k in rp)
    # L224: RTP_OFF(R,T,P)$((YEARVAL(T) LE PRC_YMAX(R,P))$TRACKP(R,P)) = ((PRC_YMAX(R,P)-B(T)+1)/D(T) GE G_OFFTHD(T))
    B, D = gvalues(tm, "B", 1), gvalues(tm, "D", 1)
    offthd = gvalues(tm, "G_OFFTHD", 1)
    rtp_off = gmembers(tm, "RTP_OFF", 3)
    for (r, p) in trackp, t in tset
        y = ymax((r, p))
        yv(t) <= y || continue
        dt = val(D, t)
        dt == 0 && error("ppmain.mod L224: division by zero (D('$t') = 0)")
        ((y - val(B, t) + 1) / dt >= val(offthd, t)) ? push!(rtp_off, (r, t, p)) : delete!(rtp_off, (r, t, p))
    end
    # L225: PRC_YMAX(TRACKP(R,P)) = SMAX(RTP_OFF(R,T,P),E(T))   (over none: -INF)
    E = gvalues(tm, "E", 1)
    offmax = Dict{NTuple{2,String},Float64}()
    for (r, t, p) in rtp_off
        t in tmem && (offmax[(r, p)] = max(get(offmax, (r, p), -Inf), val(E, t)))
    end
    foreach(k -> gassign!(prc_ymax, k, get(offmax, k, -Inf)), trackp)
    # L227-231: LOOP(TRACKP(R,P)$SUM(PYR$NCAP_PASTI(R,PYR,P),1), IF(PRC_YMAX(R,P) GT 0, <QA warning>; PRC_YMAX(R,P) = 0))
    with_pasti = Set{NTuple{2,String}}((k[1], k[3]) for k in keys(pasti) if (k[2],) in pastyear)   # EPS counts (G12)
    delayed = [k for k in trackp if k in with_pasti && ymax(k) > 0]
    gams_sort!(delayed, tm.data)                                     # LOOP order, for the QA log
    for k in delayed
        # L229-230: pp_qaput 01 'Delayed Process but PASTInvestment'; ' WARNING       - Delay is ignored:   R=',%RL%,' P=',P.TL
        pp_qaput!(tm, 1, "Delayed Process but PASTInvestment")
        qput!(qalog(tm), " WARNING       - Delay is ignored:   R=" * qlab12(k[1]) * " P=" * k[2])
        delete!(prc_ymax, k)
    end
    # L232: OPTION CLEAR=TRACKP

    # --- The later PRC_NOFF ranges (L234-238) ----------------------------------------------
    # L234: UNCD1(BOHYEAR) = NOT UNCD1(BOHYEAR)
    foreach(b -> (b,) in uncd1 ? delete!(uncd1, (b,)) : push!(uncd1, (b,)), boh.labels)
    # L235: LOOP(PRC_NOFF(RP(R,P),BOHYEAR(UNCD1),EOHYEAR),TRACKP(R,P) = YES)
    trackp = Set{NTuple{2,String}}(k for (k, rs) in ranges if any(((b, _),) -> (b,) in uncd1, rs))
    # L236-238: LOOP(TRACKP(R,P), $BATINCLUDE pp_off.mod PRC_NOFF P "" "RTP_OFF(R,T,P)$(" YES)
    #   over all the process's ranges
    #   in GAMS order (the scratch FIL, STARTOFF and ENDOFF are the last call's)
    offsc = PPOffScratch()
    for (r, p) in gams_sort!(collect(trackp), d)
        fil = pp_off_fil(tm, ranges[(r, p)], offsc)
        foreach(t -> push!(rtp_off, (r, t, p)), pp_off_periods(tm, fil, tset))
    end
    pp_off_keep!(tm, offsc)
    gput!(tm, "RTP_OFF", rtp_off)
    gput!(tm, "PRC_YMAX", prc_ymax)
    gput!(tm, "UNCD1", uncd1)

    # --- RTP, RVP (L239-242) ------------------------------------------------------------------
    # L239: RTP(R,T,P)$RP(R,P) = YES$(YEARVAL(T) GT PRC_YMAX(R,P))
    rtp = gmembers(tm, "RTP", 3)
    for (r, p) in rp, t in tset
        yv(t) > ymax((r, p)) ? push!(rtp, (r, t, p)) : delete!(rtp, (r, t, p))
    end
    # L240: RTP(R,PYR,P)$(RP(R,P)$(NCAP_PASTI(R,PYR,P)>0)$NCAP_PASTI(R,PYR,P)) = YES
    for ((r, y, p), v) in pasti
        ((r, p) in rp && (y,) in pastyear && v > 0) && push!(rtp, (r, y, p))
    end
    # L241: RVP(RTP(R,T,P)) = YES   (the milestones of RTP)
    rvp = gmembers(tm, "RVP", 3)
    foreach(k -> k[2] in tmem && push!(rvp, k), rtp)
    gput!(tm, "RTP", rtp)
    gput!(tm, "RVP", rvp)
    # L242: OPTION CLEAR=TRACKP
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    return tm
end
