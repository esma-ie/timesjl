# M1.3 (7a): the start of the prep -> prelv segment (docs/m13-plan.md):
# ppmain.mod L249-328, after preppm.mod (the preshape calls, preppm_shape!):
# the timestep control, the horizon (DUR_MAX, EACHYEAR), the commodity groups
# and RC, and the primary and shadow primary groups. (7b) ppmain_tslvl! is
# further down.
#
# GAMS: ppmain.mod L249-328, v4.9.7.
#
# Index sets: R is REG, P is PRC, C and COM are COM, CG is COM_GRP, T is
# MILESTONYR, PYR is PASTYEAR, IO is IN_OUT, IE is IMPEXP, TSL is TSLVL
# (initmty.mod L98). `OPTION a < b` matches positions right to left and `<=`
# left to right, by domain (G26); NOT ranks below + (G19); a LOOP's
# `$`-condition is read before each iteration (G30); `$x` is true for EPS
# (G12); SMAX over nothing is -INF (G31).
#
# Not translated: L249 (%INTEXT_ONLY% YES, refused at preppm.mod L10); L253
# (`SET SUBT(T) / SET.T /`, a data statement, compiled before execution: SUBT
# holds T's members in every dump). The QA log of L273-276 (a commodity
# group that is also a commodity in the topology) is written (M1.3 change
# 25b-1).

"""
    ppmain_topo_symbols(tm) -> Vector{String}

The symbols ppmain.mod L249-328 settles that nothing later in the prep ->
prelv segment changes (for the layer-1 check at the prelv checkpoint). Left
out: DEM (L417 sets it again), PRC_CG (pp_prelv.vda L33 adds to it), RPC_PG
(ppmain.mod L593, L595), and the scratch TRACKP and Z, used again.
"""
ppmain_topo_symbols(tm) = ["SUBT", "RT_PP", "DUR_MAX", "EOHYEARS", "EACHYEAR", "PERIODYR", "MI_DMAS", "FIN", "RC", "RPC",
                           "COM_GMAP", "NRG_GMAP", "RPC_CAPFLO", "RPC_NOFLO", "RP_PGTYPE", "RP_AIRE", "RP_INOUT", "PRC_SPG",
                           "RPC_SPG"]

"""
    ppmain_topo!(tm) -> tm

ppmain.mod L249-328 on the state after `preppm_shape!`: RT_PP; DUR_MAX, the
longest lifetime with its lead and lags; EOHYEARS and EACHYEAR to the end of
the longest lifetime, PERIODYR for the years after the last period; the
commodity groups of single commodities, NRG_GMAP, PRC_CG; aggregated
commodities and capacity-related flows into RC; the primary group
commodities (RPC_PG), their types and sides; the shadow primary groups
(PRC_SPG, guessed for the processes that have none) and their commodities.

GAMS: ppmain.mod L249-328, v4.9.7.
"""
function ppmain_topo!(tm)
    d = tm.data
    ax = YearAxis(tm)
    yv(y) = ax.yearval[y]
    reg = gset(tm, "REG").members
    inreg(r) = (r,) in reg
    tset = [k[1] for k in gset(tm, "MILESTONYR").keys]
    tmem = Set(tset)
    io_set = [k[1] for k in gset(tm, "IO").keys]
    com = gset(tm, "COM").members

    # --- Timestep control, horizon (L253-266) -------------------------------------------
    # L254: RT_PP(R,T) = YES
    rt_pp = gmembers(tm, "RT_PP", 2)
    for (r,) in gset(tm, "REG").keys, t in tset
        push!(rt_pp, (r, t))
    end
    gput!(tm, "RT_PP", rt_pp)
    # L257: DUR_MAX=MAX(G_TLIFE,SMAX(RVP(R,T,P),NCAP_ILED(RVP)+NCAP_TLIFE(RVP)+NCAP_DLAG(RVP)+NCAP_DLIFE(RVP)+NCAP_DELIF(RVP)))
    life = [gvalues(tm, n, 3) for n in ("NCAP_ILED", "NCAP_TLIFE", "NCAP_DLAG", "NCAP_DLIFE", "NCAP_DELIF")]
    smax = GNum(-Inf)
    for k in gset_opt(d, "RVP", 3).keys
        (inreg(k[1]) && k[2] in tmem) || continue
        x = reduce(+, (gv(p, k) for p in life); init=GZERO)
        smax = gmax(smax, x)
    end
    dur_max = gmax(GNum(gscalar(tm, "G_TLIFE")), smax)
    gput!(tm, "DUR_MAX", gassign!(Dict{Tuple{},Float64}(), (), dur_max))
    minyr, miyr_vl = gscalar(tm, "MINYR"), gscalar(tm, "MIYR_VL")
    # L260: EOHYEARS(PYR)$(YEARVAL(PYR)<MINYR) = YES
    eohyears = gmembers(tm, "EOHYEARS", 1)
    foreach(k -> yv(k[1]) < minyr && push!(eohyears, k), gset(tm, "PASTYEAR").keys)
    gput!(tm, "EOHYEARS", eohyears)
    # L262-263: EACHYEAR(PASTYEAR) = YES; EACHYEAR(ALLYEAR)$((YEARVAL >= MINYR) * (YEARVAL <= (MIYR_VL+DUR_MAX))) = YES
    eachyear = union!(gmembers(tm, "EACHYEAR", 1), gset(tm, "PASTYEAR").members)
    foreach(y -> minyr <= yv(y) <= miyr_vl + dur_max.v && push!(eachyear, (y,)), ax.years)
    gput!(tm, "EACHYEAR", eachyear)
    # L266: PERIODYR(T,EACHYEAR)$((E(T)=MIYR_VL)*(YEARVAL(EACHYEAR) >= MIYR_VL)) = YES
    E = gvalues(tm, "E", 1)
    periodyr = gmembers(tm, "PERIODYR", 2)
    for t in tset
        gv(E, (t,)).v == miyr_vl || continue
        foreach(k -> yv(k[1]) >= miyr_vl && push!(periodyr, (t, k[1])), eachyear)
    end
    gput!(tm, "PERIODYR", periodyr)

    # --- Commodity groups, RC (L272-294) --------------------------------------------------
    rc, rpc = gmembers(tm, "RC", 2), gmembers(tm, "RPC", 3)
    gmap = gmembers(tm, "COM_GMAP", 3)
    # L272: MI_DMAS(COM_GMAP(RC,C)) = YES; MI_DMAS(R,C,C) = NO   (a group whose label is a commodity of RC)
    mi_dmas = Set{NTuple{3,String}}(k for k in gmap if (k[1], k[2]) in rc && k[2] != k[3])
    # L273-277: IF(CARD(MI_DMAS), OPTION DEM<TOP; <QA log>; OPTION DEM<=MI_DMAS; RC(DEM)=NO;
    #   RPC(R,P,C)$DEM(R,C)=NO; OPTION CLEAR=MI_DMAS,CLEAR=DEM)
    if !isempty(mi_dmas)
        # L273-276: OPTION DEM<TOP; PUTGRP=0; LOOP(MI_DMAS(DEM(R,C),COM), pp_qaput 09
        #   'Commodity group found in topology violating its integrity';
        #   PUT QLOG ' SEVERE ERROR  - Group removed from topology:   R=',%RL%,' CG=',C.TL)
        qa_group!(tm)
        top_rc = Set((k[1], k[3]) for k in gset(tm, "TOP").keys)
        for (r, c, _) in gams_sort!([k for k in mi_dmas if (k[1], k[2]) in top_rc], tm.data)
            pp_qaput!(tm, 9, "Commodity group found in topology violating its integrity")
            qput!(qalog(tm), " SEVERE ERROR  - Group removed from topology:   R=" * qlab12(r) * " CG=" * c)
        end
        dem = project(mi_dmas, (1, 2))
        setdiff!(rc, dem)
        filter!(k -> !((k[1], k[3]) in dem), rpc)
        gput!(tm, "DEM", Set{NTuple{2,String}}())
        gput!(tm, "RPC", rpc)
    end
    # L278: COM_GMAP(RC(R,C),C) = YES
    foreach(((r, c),) -> push!(gmap, (r, c, c)), rc)
    gput!(tm, "COM_GMAP", gmap)
    # L279: NRG_GMAP(R,NRG_GRID(NRG_TYPE),C) $= NRG_TMAP(R,NRG_TYPE,C)
    grid = gset(tm, "NRG_GRID").members
    nrg_gmap = gmembers(tm, "NRG_GMAP", 3)
    for k in gset_opt(d, "NRG_TMAP", 3).keys
        (inreg(k[1]) && (k[2],) in grid && (k[3],) in com) && push!(nrg_gmap, k)
    end
    gput!(tm, "NRG_GMAP", nrg_gmap)
    # L282-283: PRC_CG(RPC) = YES; PRC_CG(RP_PG) = YES
    rp_pg = gset(tm, "RP_PG").members
    prc_cg = union!(gmembers(tm, "PRC_CG", 3), rpc, rp_pg)
    # L286-288: OPTION MI_DMAS<=COM_AGG,FIN<COM_TMAP; LOOP(MI_DMAS(R,COM,C)$(FIN(R,COM)$FIN(R,C)),RC(R,C)=YES);
    #   OPTION CLEAR=FIN,CLEAR=MI_DMAS   (COM_AGG(REG,ALLYEAR,COM,COM): positions 1, 3, 4; COM_TMAP(REG,COM_TYPE,COM): 1, 3)
    tmap = gset(tm, "COM_TMAP")
    fin = project(tmap.keys, (1, 3))
    for (r, cm, c) in project(gparam_opt(d, "COM_AGG", 4).keys, (1, 3, 4))
        (inreg(r) && (r, cm) in fin && (r, c) in fin) && push!(rc, (r, c))
    end
    gput!(tm, "MI_DMAS", Set{NTuple{3,String}}())
    gput!(tm, "FIN", Set{NTuple{2,String}}())
    # L291: RPC_CAPFLO(RTP,C)$(NCAP_ICOM(RTP,C)+NCAP_OCOM(RTP,C)) = YES
    rtp = gset(tm, "RTP").members
    icom, ocom = gvalues(tm, "NCAP_ICOM", 4), gvalues(tm, "NCAP_OCOM", 4)
    capflo = gmembers(tm, "RPC_CAPFLO", 4)
    for k in union(keys(icom), keys(ocom))
        ((k[1], k[2], k[3]) in rtp && !iszero(gv(icom, k) + gv(ocom, k))) && push!(capflo, k)
    end
    # L292: RPC_CAPFLO(RTP,C) $= SUM(IO$NCAP_COM(RTP,C,IO),1)
    for k in gparam_opt(d, "NCAP_COM", 5).keys
        (k[1], k[2], k[3]) in rtp && push!(capflo, (k[1], k[2], k[3], k[4]))
    end
    gput!(tm, "RPC_CAPFLO", capflo)
    # L293: OPTION RPC_NOFLO < RPC_CAPFLO   (RPC_CAPFLO(R,ALLYEAR,P,C): positions 1, 3, 4)
    noflo = project(capflo, (1, 3, 4))
    gput!(tm, "RPC_NOFLO", noflo)
    # L294: LOOP(RPC_NOFLO(R,P,C)$(NOT RC(R,C)),RC(R,C)=YES)
    foreach(k -> push!(rc, (k[1], k[3])), noflo)
    gput!(tm, "RC", rc)

    # --- Primary groups (L300-307) ---------------------------------------------------------
    rp = gset(tm, "RP").members
    pg_by = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(pg_by, (k[1], k[2]), String[]), k[3]), rp_pg)
    # L300: RPC_PG(RPC(R,P,C))$SUM(RP_PG(R,P,CG)$COM_GMAP(R,CG,C),1) = YES
    rpc_pg = gmembers(tm, "RPC_PG", 3)
    for (r, p, c) in rpc
        inreg(r) || continue
        any(cg -> (r, cg, c) in gmap, get(pg_by, (r, p), String[])) && push!(rpc_pg, (r, p, c))
    end
    # L301: RPC_PG(RP_IRE(R,P),C)$(NOT RPC_IRE(R,P,C,'IMP')+RPC_IRE(R,P,C,'EXP')) = NO
    rp_ire, rpc_ire = gset(tm, "RP_IRE").members, gset(tm, "RPC_IRE").members
    filter!(k -> !((k[1], k[2]) in rp_ire && !((k..., "IMP") in rpc_ire || (k..., "EXP") in rpc_ire)), rpc_pg)
    # L303: RPC_PG(PRC_STGTSS(RP,C))$SUM(PRC_TSL(RP,TSL)$(ORD(TSL)>1),1)=YES
    tslord = Dict(k[1] => i for (i, k) in enumerate(gset(tm, "TSLVL").keys))
    finer = Set{NTuple{2,String}}((k[1], k[2]) for k in gset(tm, "PRC_TSL").keys if get(tslord, k[3], 0) > 1)
    for k in gset_opt(d, "PRC_STGTSS", 3).keys
        ((k[1], k[2]) in rp && (k[1], k[2]) in finer) && push!(rpc_pg, k)
    end
    gput!(tm, "RPC_PG", rpc_pg)
    # L304: RP_PGTYPE(RP(R,P),COM_TYPE)$SUM(RPC_PG(R,P,C)$COM_TMAP(R,COM_TYPE,C),1) = YES
    com_type = gset(tm, "COM_TYPE").members
    types_of = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> (k[2],) in com_type && push!(get!(types_of, (k[1], k[3]), String[]), k[2]), tmap.keys)
    rp_pgtype = gmembers(tm, "RP_PGTYPE", 3)
    for (r, p, c) in rpc_pg
        (r, p) in rp || continue
        foreach(ct -> push!(rp_pgtype, (r, p, ct)), get(types_of, (r, c), String[]))
    end
    gput!(tm, "RP_PGTYPE", rp_pgtype)
    # L305: RP_AIRE(RP_IRE(RP),IE)$SUM(RPC_IRE(RPC_PG(RP,C),IE),1) = YES
    rp_aire = gmembers(tm, "RP_AIRE", 3)
    for (r, p, c, ie) in rpc_ire
        ((r, p) in rp && (r, p) in rp_ire && (r, p, c) in rpc_pg) && push!(rp_aire, (r, p, ie))
    end
    gput!(tm, "RP_AIRE", rp_aire)
    # L307: RP_INOUT(RP,IO)$SUM(TOP(RPC_PG(RP,C),IO),1) = YES
    top = gset(tm, "TOP")
    rp_inout = gmembers(tm, "RP_INOUT", 3)
    for (r, p, c, io) in top.keys
        ((r, p) in rp && (r, p, c) in rpc_pg) && push!(rp_inout, (r, p, io))
    end
    gput!(tm, "RP_INOUT", rp_inout)

    # --- Shadow primary groups (L309-327) ---------------------------------------------------
    top_by = Dict{NTuple{3,String},Vector{String}}()
    foreach(k -> push!(get!(top_by, (k[1], k[2], k[4]), String[]), k[3]), top.keys)
    prc_spg = gmembers(tm, "PRC_SPG", 3)
    rp_flo = gset(tm, "RP_FLO").members
    # L309: TRACKP(RP_FLO(RP))$(NOT SUM(PRC_SPG(RP,COM_GRP),1)) = YES
    has_spg = project(prc_spg, (1, 2))
    trackp = Set{NTuple{2,String}}(k for k in rp_flo if k in rp && !(k in has_spg))
    # L317: (SUM(RPC(R,P,C)$COM_TMAP(R,'MAT',C),1)$SUM(PRC_MAP(R,MATPRC,P),1))$RP_PGTYPE(R,P,'DEM')
    matprc = gset(tm, "MATPRC").members
    matmap = Set{NTuple{2,String}}((k[1], k[3]) for k in gset(tm, "PRC_MAP").keys if (k[2],) in matprc)
    has_mat = Set{NTuple{2,String}}((r, p) for (r, p, c) in rpc if (r, "MAT", c) in tmap.members)
    pg_smap = gset(tm, "PG_SMAP").keys                        # (CG,J,COM_TYPE) in GAMS order
    z = nothing
    # L310-323: LOOP((RP_PGTYPE(RP_FLO(R,P),CG),IO)$(NOT RP_INOUT(R,P,IO)), IF(TRACKP(R,P), ...))   in GAMS order
    for (r, p, cg) in gams_sort!([k for k in rp_pgtype if (k[1], k[2]) in rp_flo], d), io in io_set
        ((r, p, io) in rp_inout || !((r, p) in trackp)) && continue
        side = get(top_by, (r, p, io), String[])
        if any(c -> (r, cg, c) in gmap, side)
            # L313: same type as the PG on the other side
            push!(prc_spg, (r, p, cg))
        elseif (r, p) in has_mat && (r, p) in matmap && (r, p, "DEM") in rp_pgtype
            # L317-318: a material process with a demand PG
            push!(prc_spg, (r, p, "MAT"))
        else
            # L319-320: Z=1; LOOP(PG_SMAP(CG,J,COM_TYPE)$Z, IF(SUM(TOP(R,P,C,IO)$COM_TMAP(R,COM_TYPE,C),1), Z=0; PRC_SPG(R,P,COM_TYPE) = YES))
            z = 1.0
            for (g, _, ct) in pg_smap
                (g == cg && z != 0) || continue
                if any(c -> (r, ct, c) in tmap.members, side)
                    z = 0.0
                    push!(prc_spg, (r, p, ct))
                end
            end
        end
    end
    z === nothing || gput_scalar!(tm, "Z", z)
    gput!(tm, "PRC_SPG", prc_spg)
    # L325: LOOP((PRC_SPG(R,P,CG),IO)$(NOT RP_INOUT(R,P,IO)),RPC_SPG(R,P,C)$(TOP(R,P,C,IO)$COM_GMAP(R,CG,C)) = YES)
    rpc_spg = gmembers(tm, "RPC_SPG", 3)
    for (r, p, cg) in prc_spg, io in io_set
        (inreg(r) && !((r, p, io) in rp_inout)) || continue
        foreach(c -> (r, cg, c) in gmap && push!(rpc_spg, (r, p, c)), get(top_by, (r, p, io), String[]))
    end
    gput!(tm, "RPC_SPG", rpc_spg)
    # L326: PRC_CG(PRC_SPG) = YES
    union!(prc_cg, prc_spg)
    gput!(tm, "PRC_CG", prc_cg)
    # L327: OPTION CLEAR=TRACKP
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    return tm
end

# M1.3 (7b): ppmain.mod L329-460, the commodity and process timeslice levels.
#
# S, TS are ALL_TS; TSL is TSLVL; ANNUAL is the set {ANNUAL} (initsys.mod
# L48). `LOOP(ANNUAL(TS(TSL)), ...)` (L380) runs once, with TSL = 'ANNUAL',
# the one label in TSLVL, ALL_TS and ANNUAL; `TSL-1` and `TSL+n` move along
# TSLVL. A LOOP's `$`-condition is read before each iteration (G30), so L343
# and L394 take the level of the first timeslice only. In `TS_ARRAY(S) =
# PRC_YMAX(R,P)` (L428, L432) S runs over ALL_TS, so a level 0 matches every
# timeslice outside the region (and EPS is 0, G12).
#
# The QA log of L338-340 (a warning when levels are moved) is written (M1.3
# change 25b-1). L360 is pp_off.mod (`pp_off_fil`, `pp_off_periods`).

"""
    ppmain_tslvl_symbols(tm) -> Vector{String}

The symbols ppmain.mod L329-460 settles that nothing later in the prep ->
prelv segment changes (for the layer-1 check at the prelv checkpoint). Left
out: COM_BNDPRD (pp_prelv.vda L120-122), TS_ARRAY (pp_lvlfc.mod), RXX
(ppmain.mod L465), PRC_ACT, TRACKP and TRACKPC (used again by ppmain.mod
L558-586 and pp_prelv.vda), and the scratch F and Z.
"""
ppmain_tslvl_symbols(tm) = ["DEM", "COM_TSL", "PRC_TSL", "TRACKC", "COM_TS", "RCS", "RCS_COMTS", "RTC", "RTCS_VARC", "COM_PEAK",
                            "COM_PKTS", "PRC_TS", "RP_SGS", "PRC_MAP", "RP_STG", "PRC_YMAX", "RPS_S1", "RPS_S2", "PRC_SGL",
                            "RPS_PRCTS", "RP_PGFLO", "RPC_STG", "RPCS_VAR", "PRC_NSTTS"]

"""
    ppmain_tslvl!(tm) -> tm

ppmain.mod L329-460 on the state after `ppmain_topo!`: levels a region does
not have moved one level up; the commodity timeslices (COM_TS) and levels
(COM_TSL) completed from each other, RCS and RCS_COMTS; the periods of the
commodities (RTC, COM_OFF through pp_off.mod) and RTCS_VARC; the peak
timeslices (COM_PEAK, COM_PKTS); the process timeslices and levels; storage
(RP_SGS, PRC_MAP, RP_STG); the shadow-group levels (RPS_S1, RPS_S2,
PRC_SGL), RPS_PRCTS and RP_PGFLO; RPC_STG, PRC_NSTTS and RPCS_VAR, the
timeslices of the flow variables.

GAMS: ppmain.mod L329-460, pp_off.mod L17-22 (L360), v4.9.7.
"""
function ppmain_tslvl!(tm)
    d = tm.data
    regs = [k[1] for k in gset(tm, "REG").keys]
    reg = Set(regs)
    tset = [k[1] for k in gset(tm, "MILESTONYR").keys]
    tslvl = [k[1] for k in gset(tm, "TSLVL").keys]
    tord = Dict(l => i for (i, l) in enumerate(tslvl))
    tsnum = gvalues(tm, "TSLVLNUM", 1)
    num(l) = Float64(gv(tsnum, (l,)))
    all_ts = [k[1] for k in gset(tm, "ALL_TS").keys]
    annual = Set(k[1] for k in gset(tm, "ANNUAL").keys)
    rc = gset(tm, "RC").members
    rp, rp_flo = gset(tm, "RP").members, gset(tm, "RP_FLO").members
    rpc = gset(tm, "RPC").members
    # TS_GROUP(R,TSL,S): the timeslices of a level, and the levels of a timeslice
    group = Dict{NTuple{2,String},Vector{String}}()
    levels_of = Dict{NTuple{2,String},Vector{String}}()
    for (r, l, s) in gset(tm, "TS_GROUP").keys
        push!(get!(group, (r, l), String[]), s)
        push!(get!(levels_of, (r, s), String[]), l)
    end
    grp(r, l) = get(group, (r, l), String[])
    # a 3-dimensional set as (a,b) => its third indices
    byab(keys) = (m = Dict{NTuple{2,String},Set{String}}(); foreach(k -> push!(get!(m, (k[1], k[2]), Set{String}()), k[3]), keys); m)

    # --- Levels a region does not have (L335-340) -------------------------------------
    # L335: OPTION CLEAR=RXX; RXX(R,TSL,R)$(NOT SUM(RJLVL(J,R,TSL),1))=YES; F=CARD(COM_TSL); Z=CARD(PRC_TSL)
    has_lvl = Set((k[2], k[3]) for k in gset(tm, "RJLVL").keys)
    rxx = Set{NTuple{3,String}}((r, l, r) for r in regs, l in tslvl if !((r, l) in has_lvl))
    gput!(tm, "RXX", rxx)
    missing_lvl(r, l) = (r, l, r) in rxx
    com_tsl, prc_tsl = gmembers(tm, "COM_TSL", 3), gmembers(tm, "PRC_TSL", 3)
    # L336-337: X_TSL(R,C,TSL-1)$RXX(R,TSL,R) $= X_TSL(R,C,TSL); n=CARD(X_TSL)-n; X_TSL(R,C,TSL)$(RXX(R,TSL,R)$n)=NO
    #   (the new records read the old set, G11; a level is moved up one step only)
    function coarser!(s)
        n0 = length(s)
        up = [(k[1], k[2], tslvl[tord[k[3]]-1]) for k in s if k[1] in reg && missing_lvl(k[1], k[3]) && tord[k[3]] > 1]
        union!(s, up)
        n = length(s) - n0
        n == 0 || filter!(k -> !(k[1] in reg && missing_lvl(k[1], k[3])), s)
        return n
    end
    F = coarser!(com_tsl)
    Z = coarser!(prc_tsl)
    # L338-340: IF(F+Z, PUTGRP=0; pp_qaput 01 'Commodities/processes defined at non-existing TSLVL';
    #   PUT QLOG ' WARNING       - Number of COM/PRC resetted to coarser level: ',F:0:0 '/' Z:0:0/)
    if F + Z != 0
        qa_group!(tm)
        pp_qaput!(tm, 1, "Commodities/processes defined at non-existing TSLVL")
        q = qalog(tm)
        qput!(q, " WARNING       - Number of COM/PRC resetted to coarser level: " * qnum(F, 0, 0) * "/" * qnum(Z, 0, 0))
        qnl!(q)
    end

    # --- Commodity timeslices and levels (L342-352) -------------------------------------
    com_ts = gmembers(tm, "COM_TS", 3)
    # L342: TRACKC(RC) $= SUM(COM_TS(RC,S),1)
    trackc = Set{NTuple{2,String}}((k[1], k[2]) for k in com_ts if (k[1], k[2]) in rc)
    # L343: LOOP(COM_TS(RC(R,C),S)$(NOT SUM(COM_TSL(RC,TSL),1)),COM_TSL(RC,TSL)$TS_GROUP(R,TSL,S) = YES)   (G30)
    tsl_of = byab(com_tsl)
    for (r, c, s) in gams_sort!([k for k in com_ts if (k[1], k[2]) in rc], d)
        isempty(get(tsl_of, (r, c), ())) || continue
        for l in get(levels_of, (r, s), String[])
            push!(com_tsl, (r, c, l))
            push!(get!(tsl_of, (r, c), Set{String}()), l)
        end
    end
    # L345-347: LOOP(COM_TSL(TRACKC(R,C),TSLVL)$(SUM(TS_GROUP(R,TSLVL,S),1) NE SUM(COM_TS(R,C,S),1)),
    #   COM_TS(R,C,S)$(NOT TS_GROUP(R,TSLVL,S)) = NO; RCS(R,C,S)$((NOT SUM(COM_TS(R,C,TS)$RS_TREE(R,S,TS),1))$G_YRFR(R,S))=YES)
    rcs = gmembers(tm, "RCS", 3)
    rs_tree = byab(gset(tm, "RS_TREE").keys)
    yrfr_ts = Dict{String,Vector{String}}()
    foreach(k -> push!(get!(yrfr_ts, k[1], String[]), k[2]), gparam_opt(d, "G_YRFR", 2).keys)   # $G_YRFR: EPS counts (G12)
    ts_of = byab(com_ts)
    for (r, c, l) in gams_sort!([k for k in com_tsl if (k[1], k[2]) in trackc], d)
        cur = get!(ts_of, (r, c), Set{String}())
        length(grp(r, l)) == length(cur) && continue
        g = Set(grp(r, l))
        for s in collect(cur)
            s in g && continue
            delete!(cur, s)
            delete!(com_ts, (r, c, s))
        end
        for s in get(yrfr_ts, r, String[])
            any(ts -> ts in cur, get(rs_tree, (r, s), ())) || push!(rcs, (r, c, s))
        end
    end
    # L348: COM_TSL(RC,'ANNUAL')$(NOT SUM(COM_TSL(RC,TSL),1)) = YES
    for (r, c) in rc
        isempty(get(tsl_of, (r, c), ())) || continue
        push!(com_tsl, (r, c, "ANNUAL"))
        push!(get!(tsl_of, (r, c), Set{String}()), "ANNUAL")
    end
    # L350: LOOP(COM_TSL(RC(R,C),TSL)$(NOT TRACKC(RC)),COM_TS(RC,S)$TS_GROUP(R,TSL,S) = YES)
    for (r, c, l) in com_tsl
        ((r, c) in rc && !((r, c) in trackc)) || continue
        foreach(s -> push!(com_ts, (r, c, s)), grp(r, l))
    end
    ts_of = byab(com_ts)
    # L352: RCS_COMTS(RC(R,C),S)$SUM(TS_MAP(R,S,TS)$COM_TS(RC,TS),1) = YES   (TS_MAP(R,S,TS): S at or above TS)
    above = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(above, (k[1], k[3]), String[]), k[2]), gset(tm, "TS_MAP").keys)
    rcs_comts = gmembers(tm, "RCS_COMTS", 3)
    for (r, c, ts) in com_ts
        (r, c) in rc || continue
        foreach(s -> push!(rcs_comts, (r, c, s)), get(above, (r, ts), String[]))
    end

    # --- The periods of the commodities (L355-365) ----------------------------------------
    # L355-356: OPTION CLEAR=TRACKC; LOOP(COM_OFF(RC,BOHYEAR,EOHYEAR),TRACKC(RC) = YES)
    boh, eoh = OrdAxis(tm, "BOHYEAR"), OrdAxis(tm, "EOHYEAR")
    ranges = Dict{NTuple{2,String},Vector{NTuple{2,String}}}()
    for (r, c, b, e) in gams_sort!(collect(gset_opt(d, "COM_OFF", 4).keys), d)
        ((r, c) in rc && haskey(boh.pos, b) && haskey(eoh.pos, e)) && push!(get!(ranges, (r, c), NTuple{2,String}[]), (b, e))
    end
    # L357: RTC(R,T,C)$RC(R,C) = YES
    rtc = gmembers(tm, "RTC", 3)
    for (r, c) in rc, t in tset
        r in reg && push!(rtc, (r, t, c))
    end
    # L358-363: LOOP(TRACKC(R,C), $BATINCLUDE pp_off.mod COM_OFF C "" "RTC(R,T,C)$(" NO;
    #   COM_BNDPRD(R,T,C,S,'FX')$(COM_TS(R,C,S)$(NOT RTC(R,T,C))) = EPS)
    bndprd = gvalues(tm, "COM_BNDPRD", 5)
    offsc = PPOffScratch()
    for (r, c) in gams_sort!(collect(keys(ranges)), d)                 # in GAMS order (pp_off.mod's scratch)
        rs = ranges[(r, c)]
        foreach(t -> delete!(rtc, (r, t, c)), pp_off_periods(tm, pp_off_fil(tm, rs, offsc), tset))
        for t in tset, s in get(ts_of, (r, c), ())
            (r, t, c) in rtc || (bndprd[(r, t, c, s, "FX")] = 0.0)        # a stored 0.0 is EPS
        end
    end
    isempty(ranges) || gput!(tm, "COM_BNDPRD", bndprd)
    pp_off_keep!(tm, offsc)
    # L364: RTCS_VARC(RTC(R,T,C),S)$COM_TS(R,C,S) = YES
    rtcs_varc = gmembers(tm, "RTCS_VARC", 4)
    for (r, t, c) in rtc
        foreach(s -> push!(rtcs_varc, (r, t, c, s)), get(ts_of, (r, c), ()))
    end
    # L365: OPTION CLEAR=TRACKC

    # --- Peaking (L378-388) -------------------------------------------------------------------
    pkts = gmembers(tm, "COM_PKTS", 3)
    com = gset(tm, "COM").members
    # L378: COM_PEAK(R,CG)$SUM(COM_PKTS(R,CG,S),1) = 1
    peak = gmembers(tm, "COM_PEAK", 2)
    foreach(k -> k[1] in reg && push!(peak, (k[1], k[2])), pkts)
    # L379: TRACKC(COM_PEAK(R,C))$(NOT SUM(COM_TSL(R,C,TSL),1)) = YES   (C at the COM_GRP position: commodities only, G27)
    trackc = Set{NTuple{2,String}}(k for k in peak if (k[2],) in com && isempty(get(tsl_of, k, ())))
    # L380: LOOP(ANNUAL(TS(TSL)),COM_TSL(TRACKC(R,C),TSL+SMAX(COM_PKTS(R,C,S),STOAL(R,S)))=YES)
    stoal = gvalues(tm, "STOAL", 2)
    if haskey(tord, "ANNUAL") && "ANNUAL" in annual
        for (r, c) in trackc
            m = maximum((Float64(gv(stoal, (r, k[3]))) for k in pkts if k[1] == r && k[2] == c); init=-Inf)
            isfinite(m) || continue
            i = tord["ANNUAL"] + glead(m)
            if 1 <= i <= length(tslvl)
                push!(com_tsl, (r, c, tslvl[i]))
                push!(get!(tsl_of, (r, c), Set{String}()), tslvl[i])
            end
        end
    end
    # L383: COM_PKTS(COM_PEAK(R,C),S)$SUM(COM_PKTS(R,C,TS)$RS_TREE(R,S,TS),1) = SUM(COM_TSL(R,C,TSL),ORD(TSL)=STOAL(R,S)+1)
    #   (the condition reads the COM_PKTS from before the statement, G11)
    tree_by_ts = Dict{NTuple{2,String},Vector{String}}()             # (R,TS) => the S with RS_TREE(R,S,TS)
    foreach(k -> push!(get!(tree_by_ts, (k[1], k[3]), String[]), k[2]), gset(tm, "RS_TREE").keys)
    old = byab(pkts)
    for (r, c) in peak
        ((c,) in com && r in reg) || continue
        cand = Set{String}()
        foreach(ts -> union!(cand, get(tree_by_ts, (r, ts), String[])), get(old, (r, c), ()))
        lv = get(tsl_of, (r, c), Set{String}())
        for s in cand
            any(l -> tord[l] == Float64(gv(stoal, (r, s))) + 1, lv) ? push!(pkts, (r, c, s)) : delete!(pkts, (r, c, s))
        end
    end
    # L385-388: LOOP(COM_PEAK(R,CG)$(NOT SUM(COM_PKTS(R,CG,S),1)), Z = SMAX(COM_TSL(R,C,TSL)$COM_GMAP(R,CG,C),TSLVLNUM(TSL));
    #   LOOP(TSL$(TSLVLNUM(TSL)=Z),COM_PKTS(R,CG,S)$TS_GROUP(R,TSL,S) = YES))
    members = byab(gset(tm, "COM_GMAP").keys)
    has_pkts = Set((k[1], k[2]) for k in pkts)
    for (r, cg) in gams_sort!(collect(peak), d)
        (r in reg && !((r, cg) in has_pkts)) || continue
        Z = maximum((num(l) for c in get(members, (r, cg), ()) for l in get(tsl_of, (r, c), ())); init=-Inf)
        for l in tslvl
            num(l) == Z || continue
            for s in grp(r, l)
                push!(pkts, (r, cg, s))
                push!(has_pkts, (r, cg))
            end
        end
    end
    gput!(tm, "COM_PEAK", peak)
    gput!(tm, "COM_PKTS", pkts)

    # --- Process timeslices and levels (L394-399) -------------------------------------------
    prc_ts = gmembers(tm, "PRC_TS", 3)
    ptsl_of = byab(prc_tsl)
    # L394: LOOP(PRC_TS(RP(R,P),S)$(NOT SUM(PRC_TSL(RP,TSL),1)),PRC_TSL(RP,TSL)$TS_GROUP(R,TSL,S) = YES)   (G30)
    for (r, p, s) in gams_sort!([k for k in prc_ts if (k[1], k[2]) in rp], d)
        isempty(get(ptsl_of, (r, p), ())) || continue
        for l in get(levels_of, (r, s), String[])
            push!(prc_tsl, (r, p, l))
            push!(get!(ptsl_of, (r, p), Set{String}()), l)
        end
    end
    # L395: PRC_TSL(RP,'ANNUAL')$(NOT SUM(PRC_TSL(RP,TSL),1)) = YES
    for (r, p) in rp
        isempty(get(ptsl_of, (r, p), ())) || continue
        push!(prc_tsl, (r, p, "ANNUAL"))
        push!(get!(ptsl_of, (r, p), Set{String}()), "ANNUAL")
    end
    # L397-398: TRACKP(RP)$(NOT SUM(PRC_TS(RP,S),1)) = YES; LOOP(TSL,PRC_TS(TRACKP(R,P),S)$(TS_GROUP(R,TSL,S)$PRC_TSL(R,P,TSL)) = YES)
    with_ts = Set((k[1], k[2]) for k in prc_ts)
    for (r, p) in rp
        (r, p) in with_ts && continue
        for l in get(ptsl_of, (r, p), ())
            foreach(s -> push!(prc_ts, (r, p, s)), grp(r, l))
        end
    end
    pts_of = byab(prc_ts)
    gput!(tm, "PRC_TSL", prc_tsl)
    gput!(tm, "PRC_TS", prc_ts)

    # --- Storage, shadow-group levels (L408-437) ------------------------------------------------
    prc_map = gmembers(tm, "PRC_MAP", 3)
    pmap(r, g, p) = (r, g, p) in prc_map
    has_annual(r, p) = "ANNUAL" in get(ptsl_of, (r, p), ())
    # L408-409: RP_SGS(RP_FLO(R,P))$(PRC_TSL(R,P,'ANNUAL')$(PRC_MAP(R,'STS',P)+PRC_MAP(R,'NST',P))) = YES; RP_SGS(RP_FLO(R,P))$=PRC_MAP(R,'SGS',P)
    rp_sgs = gmembers(tm, "RP_SGS", 2)
    for (r, p) in rp_flo
        r in reg || continue
        ((has_annual(r, p) && (pmap(r, "STS", p) || pmap(r, "NST", p))) || pmap(r, "SGS", p)) && push!(rp_sgs, (r, p))
    end
    # L410: PRC_MAP(R,'STG',P)$((NOT SUM(TOP(RPC_PG(R,P,C),'IN'),1))$RP_SGS(R,P)) = NO
    rpc_pg, rpc_spg = gset(tm, "RPC_PG").members, gset(tm, "RPC_SPG").members
    top = gset(tm, "TOP").members
    pg_in = Set((k[1], k[2]) for k in top if k[4] == "IN" && (k[1], k[2], k[3]) in rpc_pg)
    for (r, p) in rp_sgs
        (r in reg && !((r, p) in pg_in)) && delete!(prc_map, (r, "STG", p))
    end
    # L412: PRC_MAP(R,'STG',P)$((NOT PRC_TSL(R,P,'ANNUAL'))$PRC_MAP(R,'NST',P)) = YES
    for (r, g, p) in collect(prc_map)
        (g == "NST" && r in reg && !((r, p, "ANNUAL") in prc_tsl)) && push!(prc_map, (r, "STG", p))
    end
    gput!(tm, "PRC_MAP", prc_map)
    # L413: RP_STG(RP(R,P)) $= PRC_MAP(R,'STG',P)
    rp_stg = gmembers(tm, "RP_STG", 2)
    foreach(k -> pmap(k[1], "STG", k[2]) && push!(rp_stg, k), rp)
    gput!(tm, "RP_STG", rp_stg)
    gput!(tm, "RP_SGS", rp_sgs)
    # L417: OPTION DEM < COM_FR   (COM_FR(REG,ALLYEAR,COM,TS): positions 1, 3)
    dem = project(gparam_opt(d, "COM_FR", 4).keys, (1, 3))
    gput!(tm, "DEM", dem)
    # L418: LOOP(COM_TSL(DEM(R,C),'ANNUAL'),TRACKP(RP_FLO(R,P))$RPC_PG(R,P,C) = YES)
    pg_procs = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(pg_procs, (k[1], k[3]), String[]), k[2]), rpc_pg)
    trackp = gmembers(tm, "TRACKP", 2)
    for (r, c) in dem
        (r in reg && (r, c, "ANNUAL") in com_tsl) || continue
        foreach(p -> (r, p) in rp_flo && push!(trackp, (r, p)), get(pg_procs, (r, c), String[]))
    end
    # L419-422: PRC_YMAX, the finest level of the shadow group (of all the commodities for TRACKP), 0 for storage,
    #   and at least the process's own (SMAX over nothing is -INF, G31)
    clvl(r, c) = maximum((num(l) for l in get(tsl_of, (r, c), ())); init=-Inf)
    coms_of(s) = (m = Dict{NTuple{2,String},Vector{String}}(); foreach(k -> push!(get!(m, (k[1], k[2]), String[]), k[3]), s); m)
    spg_c, rpc_c = coms_of(rpc_spg), coms_of(rpc)
    ymax = Dict{NTuple{2,String},Float64}()
    for k in rp
        ymax[k] = maximum((clvl(k[1], c) for c in get(spg_c, k, String[])); init=-Inf)                  # L419
    end
    for k in trackp
        k in rp && (ymax[k] = maximum((clvl(k[1], c) for c in get(rpc_c, k, String[])); init=-Inf))      # L420
    end
    foreach(k -> k in rp && (ymax[k] = 0.0), rp_stg)                                                     # L421
    for k in rp
        ymax[k] = max(ymax[k], maximum((num(l) for l in get(ptsl_of, k, ())); init=-Inf))                # L422
    end
    # L424-434: LOOP(R, ...): TS_ARRAY, Z, RPS_S2 of RP_SGS, PRC_SGL, PRC_YMAX of RP_SGS, RPS_S1, RPS_S2
    rs_tslvl = gvalues(tm, "RS_TSLVL", 2)
    rlup = gset(tm, "RLUP").keys
    rps_s1, rps_s2 = gmembers(tm, "RPS_S1", 3), gmembers(tm, "RPS_S2", 3)
    prc_sgl = gvalues(tm, "PRC_SGL", 2)
    ts_array = Dict{Tuple{String},Float64}()
    rp_by_r = Dict{String,Vector{NTuple{2,String}}}()
    foreach(k -> push!(get!(rp_by_r, k[1], NTuple{2,String}[]), k), rp)
    for r in regs
        # L425: OPTION CLEAR=TS_ARRAY; TS_ARRAY(S) $= RS_TSLVL(R,S)
        ts_array = Dict{Tuple{String},Float64}((k[2],) => v for (k, v) in rs_tslvl if k[1] == r)
        # L426: Z = MAX(1,SMAX(RLUP(R,TSLVL,TSL),TSLVLNUM(TSL)))
        Z = max(1.0, maximum((num(k[3]) for k in rlup if k[1] == r); init=-Inf))
        # the timeslices by TS_ARRAY value: 0 for those without one (EPS is 0, G12)
        at = Dict{Float64,Vector{String}}()
        foreach(s -> push!(get!(at, get(ts_array, (s,), 0.0), String[]), s), all_ts)
        procs = get(rp_by_r, r, NTuple{2,String}[])
        # L428: RPS_S2(RP_SGS(R,P),S)$(TS_ARRAY(S) = PRC_YMAX(R,P)) = YES
        for k in procs
            k in rp_sgs && foreach(s -> push!(rps_s2, (k..., s)), get(at, ymax[k], String[]))
        end
        # L429: PRC_SGL(RP_FLO(R,P)) = MIN(PRC_YMAX(R,P)-1$RP_STG(R,P),Z)-1
        for k in procs
            k in rp_flo && gassign!(prc_sgl, k, min(ymax[k] - (k in rp_stg ? 1 : 0), Z) - 1)
        end
        # L430: PRC_YMAX(RP_SGS(R,P)) = PRC_SGL(R,P)+1
        foreach(k -> k in rp_sgs && (ymax[k] = Float64(gv(prc_sgl, k)) + 1), procs)
        # L432-433: RPS_S1(RP(R,P),S)$(TS_ARRAY(S) = PRC_YMAX(R,P)) = YES; RPS_S2(RPS_S1(R,P,S))$(NOT RP_SGS(R,P)) = YES
        for k in procs, s in get(at, ymax[k], String[])
            push!(rps_s1, (k..., s))
            k in rp_sgs || push!(rps_s2, (k..., s))
        end
    end
    gput!(tm, "TS_ARRAY", ts_array)
    gput!(tm, "PRC_SGL", prc_sgl)
    # L436: LOOP((TSLVL,TSL)$(ORD(TSL)>ORD(TSLVL)),IF(ORD(TSL)=2,RPS_PRCTS(PRC_TS(RP,S))=1);
    #   RPS_PRCTS(RP(R,P),S)$(TS_GROUP(R,TSLVL,S)$PRC_TSL(RP,TSL))=YES)
    rps_prcts = gmembers(tm, "RPS_PRCTS", 3)
    length(tslvl) >= 2 && foreach(k -> (k[1], k[2]) in rp && push!(rps_prcts, k), prc_ts)
    for (r, p) in rp, l in get(ptsl_of, (r, p), ()), l0 in tslvl
        tord[l0] < tord[l] && foreach(s -> push!(rps_prcts, (r, p, s)), grp(r, l0))
    end
    gput!(tm, "RPS_PRCTS", rps_prcts)
    # L437: RP_PGFLO(TRACKP)$(PRC_YMAX(TRACKP)>1) = YES
    rp_pgflo = gmembers(tm, "RP_PGFLO", 2)
    foreach(k -> get(ymax, k, 0.0) > 1 && push!(rp_pgflo, k), trackp)
    gput!(tm, "RP_PGFLO", rp_pgflo)

    # --- The timeslices of the flow variables (L446-459) ------------------------------------------
    stgtss, stgips = gset_opt(d, "PRC_STGTSS", 3).members, gset_opt(d, "PRC_STGIPS", 3).members
    nstts = gmembers(tm, "PRC_NSTTS", 3)
    # L446: RPC_STG(RPC(RP_STG(R,P),C))$(PRC_STGTSS(RPC)+PRC_STGIPS(RPC)+(RPC_PG(RPC)+RPC_SPG(RPC))$PRC_MAP(R,'NST',P)) = YES
    rpc_stg = gmembers(tm, "RPC_STG", 3)
    for k in rpc
        ((k[1], k[2]) in rp_stg && k[1] in reg) || continue
        (k in stgtss || k in stgips || ((k in rpc_pg || k in rpc_spg) && pmap(k[1], "NST", k[2]))) && push!(rpc_stg, k)
    end
    gput!(tm, "RPC_STG", rpc_stg)
    # L447: TRACKPC(RPC_STG(R,P,C))$((TOP(R,P,C,'OUT')+PRC_NSTTS(R,P,'ANNUAL'))$COM_TS(R,C,'ANNUAL')$PRC_MAP(R,'NST',P)) = YES
    trackpc = gmembers(tm, "TRACKPC", 3)
    for (r, p, c) in rpc_stg
        (((r, p, c, "OUT") in top || (r, p, "ANNUAL") in nstts) && (r, c, "ANNUAL") in com_ts && pmap(r, "NST", p)) &&
            push!(trackpc, (r, p, c))
    end
    # L448: RPCS_VAR(RPC(RP_STG(R,P),C),S)$(PRC_TS(R,P,S)$(NOT TRACKPC(RPC))+ANNUAL(S)$TRACKPC(RPC)) = YES
    rpcs_var = gmembers(tm, "RPCS_VAR", 4)
    for k in rpc
        ((k[1], k[2]) in rp_stg && k[1] in reg) || continue
        foreach(s -> push!(rpcs_var, (k..., s)), k in trackpc ? annual : get(pts_of, (k[1], k[2]), ()))
    end
    # L449: PRC_NSTTS(RP_STG(R,P),ANNUAL)$(NOT SUM(TOP(TRACKPC(R,P,C),'IN'),1))=NO; OPTION PRC_ACT<PRC_NSTTS
    tpc_in = Set((r, p) for (r, p, c) in trackpc if (r, p, c, "IN") in top)
    for (r, p) in rp_stg
        (r, p) in tpc_in || foreach(s -> delete!(nstts, (r, p, s)), annual)
    end
    prc_act = project(nstts, (1, 2))
    # L450: PRC_NSTTS(RPS_S2(R,P,S))$(NOT PRC_ACT(R,P)) $= PRC_MAP(R,'NST',P)
    for (r, p, s) in rps_s2
        (r in reg && !((r, p) in prc_act) && pmap(r, "NST", p)) && push!(nstts, (r, p, s))
    end
    gput!(tm, "PRC_NSTTS", nstts)
    # L452: TRACKP(RP) = NOT RP_STG(RP)
    foreach(k -> k in rp_stg ? delete!(trackp, k) : push!(trackp, k), rp)
    s1_of, s2_of = byab(rps_s1), byab(rps_s2)
    # L453: RPCS_VAR(RPC_PG(TRACKP(R,P),C),S)$PRC_TS(R,P,S) = YES
    for k in rpc_pg
        (k[1], k[2]) in trackp && foreach(s -> push!(rpcs_var, (k..., s)), get(pts_of, (k[1], k[2]), ()))
    end
    # L455: RPCS_VAR(RPC_SPG(TRACKP(R,P),C),S)$RPS_S2(R,P,S) = YES
    for k in rpc_spg
        ((k[1], k[2]) in trackp && k[1] in reg) && foreach(s -> push!(rpcs_var, (k..., s)), get(s2_of, (k[1], k[2]), ()))
    end
    # L456: RPCS_VAR(RPC(TRACKP(R,P),C),S)$(RPS_S1(R,P,S)$(NOT RPC_PG(R,P,C)+RPC_SPG(R,P,C))) = YES   (NOT (a+b), G19)
    for k in rpc
        ((k[1], k[2]) in trackp && k[1] in reg && !(k in rpc_pg || k in rpc_spg)) || continue
        foreach(s -> push!(rpcs_var, (k..., s)), get(s1_of, (k[1], k[2]), ()))
    end
    # L458: RPCS_VAR(R,P,C,S)$RCS(R,C,S) = NO
    isempty(rcs) || filter!(k -> !((k[1], k[3], k[4]) in rcs), rpcs_var)
    gput!(tm, "RPCS_VAR", rpcs_var)
    gput!(tm, "RPS_S1", rps_s1)
    gput!(tm, "RPS_S2", rps_s2)
    for (s, v) in (("COM_TSL", com_tsl), ("COM_TS", com_ts), ("RCS_COMTS", rcs_comts), ("RTC", rtc), ("RTCS_VARC", rtcs_varc))
        gput!(tm, s, v)
    end
    # L459: OPTION CLEAR=PRC_YMAX,CLEAR=RCS,CLEAR=PRC_ACT,CLEAR=TRACKP,CLEAR=TRACKPC (TRACKC is cleared at L381)
    gput!(tm, "PRC_YMAX", Dict{NTuple{2,String},Float64}())
    for (s, N) in (("RCS", 3), ("PRC_ACT", 2), ("TRACKP", 2), ("TRACKPC", 3), ("TRACKC", 2))
        gput!(tm, s, Set{NTuple{N,String}}())
    end
    gput_scalar!(tm, "F", F)
    gput_scalar!(tm, "Z", Z)
    return tm
end
