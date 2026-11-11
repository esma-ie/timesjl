# M1.3 (27a): powerflo.vda, the grid extension of the VDA code (%POWERFLO% YES,
# set by init_ext.vda L134-135 when PRC_REACT is defined or GR_PTDF or GG_KGF
# has data): its PREP block (prep_ext.vda L37) and its main block
# (pp_prelv.vda L114).
#
# GAMS (v4.9.7): powerflo.vda L206-218 (PREP), L11-204 (main block).
#
# Refused: GG_KGF data (the gas grids of gasgrids.vda and the GG_* parameters
# of PREP L213-218; no test model has any).

"The powerflo.vda paths this model would take that are not translated."
function powerflo_unported(tm)
    out = String[]
    hasdata(tm, "GG_KGF", 4) && push!(out, "powerflo.vda L213-218, gasgrids.vda (GG_KGF has data: gas grids)")
    return out
end

"""
    powerflo_prep!(st) -> st

powerflo.vda PREP (prep_ext.vda L37): PRC_REACT, GR_PTDF, GR_DEMFR, GR_ENDFR
and GR_GENFR interpolated over the milestones by fillparm.gms (option test
`GE 0`, no condition), GR_XBND by filparam.gms from the data years. The
interpolation scratch carries on in `st` (`InterpState`).

GAMS: powerflo.vda L206-218, v4.9.7.
"""
function powerflo_prep!(st)
    tm = st.tm
    u = powerflo_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    T = [k[1] for k in gset(tm, "MILESTONYR").keys]
    one = k -> true
    ge0 = (x, k) -> x >= 0                                                   # 'GE 0'
    # L207: $IF NOT DEFINED PRC_REACT $CLEAR PRC_REACT   (compile time: nothing to do)
    fillparm!(st, "PRC_REACT", "R", "P", pd(",'0','0','0','0','0'"), T, one, ge0)            # L208
    fillparm!(st, "GR_PTDF", "R", "P,C,REG,COM", pd(",'0','0'"), T, one, ge0)                 # L209
    fillparm!(st, "GR_DEMFR", "R", "C,S", pd(",'0','0','0','0'"), T, one, ge0)                # L210
    fillparm!(st, "GR_ENDFR", "R", "C,COM", pd(",'0','0','0','0'"), T, one, ge0)              # L211
    fillparm!(st, "GR_GENFR", "R", "C,ITEM", pd(",'0','0','0','0'"), T, one, ge0)             # L212
    # L213: $BATINCLUDE filparam GR_XBND 'R,' '' ",'0','0','0','0','0'" DATAYEAR T
    filparam!(st, "GR_XBND", "R,", "", pd(",'0','0','0','0','0'"), [y for y in st.ax.years if y in st.datayear], T)
    # L214: $IFE CARD(GG_KGF)=0 $EXIT   (GG_KGF data is refused above)
    return st
end

"""
    powerflo_main_unported(tm) -> Vector{String}

The powerflo.vda main-block paths this model would take that are not
translated: the PTDF formulation (GR_PTDF data: L59-64, L172-180) and total
demand fractions given as data (GR_DEMFR: the levelization of L107 and L131),
besides the gas grids. The allocation of generation and sectoral demand to
grid nodes (GR_ENDFR, GR_GENFR, GR_GENMAP, GR_GENLEV: L40-47, L109-162) is
translated (M1.3 change 27a-2).
"""
function powerflo_main_unported(tm)
    out = powerflo_unported(tm)
    hasdata(tm, "GR_PTDF", 6) && push!(out, "powerflo.vda L59-64, L172-180 (GR_PTDF has data: the PTDF formulation)")
    hasdata(tm, "GR_DEMFR", 4) && push!(out, "powerflo.vda L107, L131 (GR_DEMFR has data: levelization of total demand fractions)")
    return out
end

"""
    powerflo_model_unported(tm) -> Vector{String}

The powerflo.vda paths of the model (DECL and the equations) this model would take that are not
translated: those of the main block, and the allocation of supply and demand to grid nodes
(EQ_GR_GENALL, EQ_GR_DEMALL and the IREAUX terms, which come with M1.3 change 27b-2) when the
allocation data exist.
"""
function powerflo_model_unported(tm)
    out = powerflo_main_unported(tm)
    for (n, k) in (("GR_ENDFR", 4), ("GR_GENFR", 4), ("GR_GENMAP", 3), ("GR_GENLEV", 2))
        hasdata(tm, n, k) && push!(out, "powerflo.vda L291-336 and IREAUX ($n has data: EQ_GR_GENALL, EQ_GR_DEMALL, allocation to grid nodes)")
    end
    return out
end

"""
    powerflo_main!(tm) -> tm

powerflo.vda's main block (pp_prelv.vda L114), the DC power-flow grid in the
phase-angle formulation: the electricity nodes (NRGELC), the grid lines
GR_TOP among them from TOP_IRE with their default direction (GR_FLOW), the
line reactances synchronised between regions, the admittance GR_ADMIT
(1/PRC_REACT) and the susceptance matrix GR_SUS, the disjoint grids
(GR_GID, GR_GRID), the timeslice-level checks that drop nodes, RC_GRID, the
grid maps GR_GMAPC and GR_ENDC, the allocation of generation and sectoral
demand to the grid nodes (GR_ENDFR, GR_GENFR, GR_GENMAP, GR_GENLEV
normalised; GR_ALLMAP, GR_ALGMAP, GR_DEMMAP, GR_PRCMAP, GR_GENP, GR_GNALL,
GR_DEMFR from the sectoral fractions: change 27a-2), the reference nodes
GR_ADO, and COM_LIM FX on the grid nodes. Loops run in GAMS order; the scratch (F, Z, CNT, DFUNC,
MY_F, DONE) is left as GAMS leaves it.

GAMS: powerflo.vda L11-204 (without GR_PTDF or GR_DEMFR data), v4.9.7.
"""
function powerflo_main!(tm)
    u = powerflo_main_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    d = tm.data
    S(n, k) = gset_opt(d, n, k).members
    Sk(n, k) = gset_opt(d, n, k).keys
    sorted(x) = gams_sort!(collect(x), d)
    regs = [k[1] for k in Sk("REG", 1)]
    reg = Set(regs)
    T = [k[1] for k in Sk("MILESTONYR", 1)]
    tset = Set(T)
    # L37: NRGELC(RC(R,C))$COM_TMAP(R,'NRG',C) $= NRG_TMAP(R,'ELC',C)
    nrgelc = gmembers(tm, "NRGELC", 2)
    tnrg = Set((k[1], k[3]) for k in Sk("COM_TMAP", 3) if k[2] == "NRG")
    telc = Set((k[1], k[3]) for k in Sk("NRG_TMAP", 3) if k[2] == "ELC")
    foreach(k -> (k[1] in reg && k in tnrg && k in telc) && push!(nrgelc, k), Sk("RC", 2))
    gput!(tm, "NRGELC", nrgelc)
    # L38-39: TRACKP(R,P) $= SUM(RPC_IRE(R,P,C,IE)$NRGELC(R,C),1); PRC_REACT(R,LL,P)$(NOT TRACKP(R,P)) = 0
    trackp = gmembers(tm, "TRACKP", 2)
    rpc_ire = Sk("RPC_IRE", 4)
    foreach(k -> (k[1] in reg && (k[1], k[3]) in nrgelc) && push!(trackp, (k[1], k[2])), rpc_ire)
    react = gvalues(tm, "PRC_REACT", 3)
    filter!(((k, _),) -> !(k[1] in reg && !((k[1], k[3]) in trackp)), react)
    # L40: OPTION TRACKC <= GR_DEMFR (no GR_DEMFR data: powerflo_main_unported), GR_GID <= GR_ENDFR, which projects
    #   GR_ENDFR(R,ALLYEAR,C,CG) on R and C (positions 1 and 3; only nonzero matters until L70 resets GR_GID)
    gid_add = Set{NTuple{2,String}}((k[1], k[3]) for k in keys(gvalues(tm, "GR_ENDFR", 4)))
    # L41: GR_GID(TRACKC)=1 (TRACKC empty); OPTION TRACKC < GG_PRBD (R,YEAR,C,LIM: positions 1 and 3); GR_GID(TRACKC)=1
    foreach(k -> push!(gid_add, (k[1], k[3])), keys(gparam_opt(d, "GG_PRBD", 4).values))
    # L42: LOOP((R,LL,C,ITEM)$GR_GENFR(R,LL,C,ITEM),GR_GID(R,C)=1)
    foreach(k -> push!(gid_add, (k[1], k[3])), keys(gvalues(tm, "GR_GENFR", 4)))
    # L43-44: OPTION CLEAR=TRACKC, TRACKP < PRC_REACT, RP_PRC < GR_PTDF; DFUNC=CARD(RP_PRC); TRACKP(RP_PRC)=YES
    trackp = Set{NTuple{2,String}}((k[1], k[3]) for k in keys(react))
    rp_prc = Set{NTuple{2,String}}()
    dfunc = 0.0
    # L45: TRACKC(R,C) $= SUM(NRG_GMAP(R,NRG_GRID,C),1)
    grids = S("NRG_GRID", 1)
    trackc = Set{NTuple{2,String}}((k[1], k[3]) for k in Sk("NRG_GMAP", 3) if k[1] in reg && (k[2],) in grids)
    # L47: LOOP(RPC_IRE(R,P,C,IE)$GR_GID(R,C),TRACKP(R,P)=YES): IRE between the add-on nodes of L40-42
    foreach(k -> (k[1] in reg && (k[1], k[3]) in gid_add) && push!(trackp, (k[1], k[2])), rpc_ire)
    # L48-49: GR_TOP from TOP_IRE between nodes of TRACKC, the line in TRACKP at the exporting or importing end
    gr_top = gmembers(tm, "GR_TOP", 5)
    for (r, c, r2, c2, p) in Sk("TOP_IRE", 5)
        ((r, c) in trackc && (r2, c2) in trackc) || continue
        ((r, p) in trackp || (r2, p) in trackp) && push!(gr_top, (r, c, r2, c2, p))
    end
    # L50: LOOP(GR_TOP(R,C,REG,COM,P),GR_FLOW(R,P,C)=GR_FLOW(R,P,C)*2+1; GR_FLOW(REG,P,COM)=GR_FLOW(REG,P,COM)*2-1)
    flow = gvalues(tm, "GR_FLOW", 3)
    setf!(k, x) = iszero(x) ? delete!(flow, k) : (flow[k] = x)
    for (r, c, r2, c2, p) in sorted(gr_top)
        setf!((r, p, c), get(flow, (r, p, c), 0.0) * 2 + 1)
        setf!((r2, p, c2), get(flow, (r2, p, c2), 0.0) * 2 - 1)
    end
    gput!(tm, "GR_FLOW", flow)
    # L51: OPTION CLEAR=TRACKP, CLEAR=RP_PRC, RP_GRID < GR_FLOW
    empty!(trackp); empty!(rp_prc)
    rp_grid = Set{NTuple{2,String}}((k[1], k[2]) for k in keys(flow))
    # L52-53: GR_TOP(R,C,REG,COM,P)$(GR_FLOW(R,P,C) < 0) = NO; GR_TOP(R,C,R,C,P) = NO
    filter!(k -> !(get(flow, (k[1], k[5], k[2]), 0.0) < 0) && !(k[1] == k[3] && k[2] == k[4]), gr_top)
    # L54: LOOP(GR_TOP(R,C,R,COM,P)$SUM(RPC_IRE(RPC_PG(R,P,C),IE),RPC_PG(R,P,COM)),PRC_MAP(R,'DISTR',P)=YES)
    rpc_pg = S("RPC_PG", 3)
    ire_rpc = Set((k[1], k[2], k[3]) for k in rpc_ire)
    prc_map = gmembers(tm, "PRC_MAP", 3)
    for (r, c, r2, c2, p) in gr_top
        (r == r2 && (r, p, c) in rpc_pg && (r, p, c) in ire_rpc && (r, p, c2) in rpc_pg) && push!(prc_map, (r, "DISTR", p))
    end
    gput!(tm, "PRC_MAP", prc_map)
    # L56-64: lines between regions: RP_PRC, RTP_VARA only where both ends have it, the larger reactance at both
    #   ends (the PTDF statements L59-64 within a region run on an empty GR_PTDF)
    vara = gmembers(tm, "RTP_VARA", 3)
    rtp = S("RTP", 3)
    F = nothing
    for (r, c, r2, c2, p) in sorted(gr_top)
        F = 1.0
        r == r2 && continue
        push!(rp_prc, (r2, p))
        F = 0.0
        for t in T
            ((r, t, p) in rtp && !((r2, t, p) in vara)) && delete!(vara, (r, t, p))
            x = max(get(react, (r, t, p), 0.0), get(react, (r2, t, p), 0.0))
            x == 0 ? delete!(react, (r, t, p)) : (react[(r, t, p)] = x)
        end
    end
    gput!(tm, "RTP_VARA", vara)
    # L65: PRC_REACT(R,T,P)$((PRC_REACT(R,T,P) LE 0)$PRC_REACT(R,T,P)) = 0
    filter!(((k, x),) -> !(k[2] in tset && x <= 0), react)
    gput!(tm, "PRC_REACT", react)
    # L66-67: GR_ARC from GR_TOP; OPTION TRACKC < GR_FLOW
    gr_arc = Set{NTuple{4,String}}((k[1], k[2], k[3], k[4]) for k in gr_top)
    trackc = Set{NTuple{2,String}}((k[1], k[3]) for k in keys(flow))
    # L70: OPTION GR_GID <= GR_PTDF (empty); L71: GR_ADMIT(R,T,C,REG,COM)$GR_ARC = SUM(GR_TOP$(PRC_REACT$RTP_VARA),1/PRC_REACT)
    admit = gvalues(tm, "GR_ADMIT", 5)
    for (r, c, r2, c2) in gr_arc, t in T
        x = 0.0
        for k in gr_top
            (k[1] == r && k[2] == c && k[3] == r2 && k[4] == c2) || continue
            y = get(react, (r, t, k[5]), 0.0)
            (y != 0 && (r, t, k[5]) in vara) && (x += 1 / y)
        end
        x == 0 ? delete!(admit, (r, t, c, r2, c2)) : (admit[(r, t, c, r2, c2)] = x)
    end
    gput!(tm, "GR_ADMIT", admit)
    # L72: OPTION RREG <= GR_ARC
    rreg = Set{NTuple{2,String}}((k[1], k[3]) for k in gr_arc)
    gput!(tm, "RREG", rreg)
    # L75-82: the disjoint grids: an ID per connected set of nodes, the first EPS
    gid = Dict{NTuple{2,String},GNum}()
    gget(k) = get(gid, k, GZERO)
    cnt = GEPS
    Z, my_f, done = nothing, nothing, nothing
    for (r, c, r2, c2) in sorted(gr_arc)
        f, z = gget((r, c)), gget((r2, c2))
        F, Z = f, z
        if iszero(f + z)
            gid[(r, c)] = cnt; gid[(r2, c2)] = cnt; cnt = cnt + GNum(1.0)
        elseif iszero(f)
            gid[(r, c)] = z
        elseif iszero(z)
            gid[(r2, c2)] = f
        elseif f.v != z.v
            # L80-81: MY_F=MIN(F,Z); DONE=MAX(F,Z); IF(CNT=DONE+1,CNT=DONE); GR_GID(..)$(..=DONE) = MY_F.
            # GAMS MIN keeps EPS (G21): the first grid's ID is EPS, so a grid merged into it gets
            # EPS, not an exact 0 that a later arc would read as "no grid yet" (NOT F).
            my_f, done = gmin(f, z), gmax(f, z)
            cnt.v == done.v + 1 && (cnt = done)
            for k in trackc
                gget(k).v == done.v && (gid[k] = my_f)
            end
        end
    end
    # L84: LOOP(SAMEAS('1',J),GR_GRID(J+GR_GID(R,C),TRACKC(R,C)) = YES)
    js = [k[1] for k in Sk("J", 1)]
    gr_grid = gmembers(tm, "GR_GRID", 3)
    for (r, c) in trackc
        i = 1 + glead(gget((r, c)).v)
        1 <= i <= length(js) && push!(gr_grid, (js[i], r, c))
    end
    gput!(tm, "GR_GRID", gr_grid)
    # L86: OPTION GR_GID <= GR_PTDF; GR_GID(TRACKC) = NOT GR_GID(TRACKC)   (the reactance nodes: 1)
    gid = Dict{NTuple{2,String},GNum}(k => GNum(1.0) for k in trackc)
    # L89: TRACKPC(RP_GRID(R,P),C)$GR_FLOW(R,P,C) $= GR_GID(R,C)
    trackpc = gmembers(tm, "TRACKPC", 3)
    foreach(k -> ((k[1], k[2]) in rp_grid && haskey(gid, (k[1], k[3]))) && push!(trackpc, k), keys(flow))
    # L90-95: LOOP((R,TSL('DAYNITE')), ...): nodes dropped where processes or linked regions are not at DAYNITE alike
    if ("DAYNITE",) in S("TSLVL", 1)
        ptsl, ctsl = S("PRC_TSL", 3), S("COM_TSL", 3)
        tsg = Dict{String,Set{String}}()
        foreach(k -> k[2] == "DAYNITE" && push!(get!(() -> Set{String}(), tsg, k[1]), k[3]), Sk("TS_GROUP", 3))
        drop!(rr) = filter!(k -> !(k[1] == rr && k in nrgelc && haskey(gid, k)), trackc)
        for r in regs
            # (NOT PRC_TSL(R,P,TSL)$COM_TSL(R,C,TSL)): `$` binds tighter than NOT (G46)
            z = any(k -> k[1] == r && !((r, k[2], "DAYNITE") in ptsl && (r, k[3], "DAYNITE") in ctsl), trackpc) ? 1.0 : 0.0
            for (ra, r2) in sorted(rreg)
                ra == r || continue
                isempty(symdiff(get(tsg, r, Set{String}()), get(tsg, r2, Set{String}()))) || (drop!(r2); z = 1.0)
            end
            z == 1 && drop!(r)
            Z = GNum(z)
        end
    end
    # L96: RC_GRID(RTC(R,T,C))$TRACKC(R,C) = YES
    rc_grid = gmembers(tm, "RC_GRID", 3)
    foreach(k -> (k[2] in tset && (k[1], k[3]) in trackc) && push!(rc_grid, k), Sk("RTC", 3))
    gput!(tm, "RC_GRID", rc_grid)
    # L98-99: OPTION TRACKPC <= GR_PTDF (empty); RP_GRID < TRACKPC; CLEAR=TRACKPC, CLEAR=TRACKP
    empty!(trackpc); empty!(rp_grid); empty!(trackp)
    # L102: option gr_sus < gr_admit: the same domains twice, filled from the right (G52), so the transpose
    sus = Dict{NTuple{5,String},Float64}((k[4], k[2], k[5], k[1], k[3]) => x for (k, x) in admit)
    # L103: gr_sus(rc_grid,rc) $= gr_admit(rc_grid,rc)*(-1)   (the two index groups run independently)
    rc = Sk("RC", 2)
    rcset = Set(rc)
    for (r, t, c) in rc_grid, (r2, c2) in rc
        x = get(admit, (r, t, c, r2, c2), 0.0)
        x == 0 || (sus[(r, t, c, r2, c2)] = -x)
    end
    # L104: gr_sus(rc_grid(r,t,c),r,c) = -sum(trackc(rc),gr_sus(rc_grid,rc))
    for (r, t, c) in sorted(rc_grid)
        x = -sum((get(sus, (r, t, c, k[1], k[2]), 0.0) for k in trackc if k in rcset); init=0.0)
        x == 0 ? delete!(sus, (r, t, c, r, c)) : (sus[(r, t, c, r, c)] = x)
    end
    gput!(tm, "GR_SUS", sus)
    # L107: pp_lvlfc.mod GR_DEMFR: no GR_DEMFR data (powerflo_main_unported), so only its OPTION CLEAR=UNCD7
    gput!(tm, "UNCD7", Set{NTuple{7,String}}())
    # --- L109-162: the allocation of generation and sectoral demand to the grid nodes (M1.3 change 27a-2) ------
    # A parameter value is read as GAMS does (absent 0, a stored 0 EPS) and stored back with set!.
    val(p, k) = (x = get(p, k, nothing); x === nothing ? GZERO : x == 0.0 ? GEPS : GNum(x))
    set!(p, k, x::GNum) = iszero(x) ? delete!(p, k) : (p[k] = x.v)
    comset = S("COM", 1)
    iscom(c) = (c,) in comset
    gridl = [g for (g,) in sorted(grids)]
    # L109: GR_GMAPC(NRG_GMAP(R,NRG_GRID,C)) $= TRACKC(R,C)
    gmapc = gmembers(tm, "GR_GMAPC", 3)
    foreach(k -> ((k[2],) in grids && (k[1], k[3]) in trackc) && push!(gmapc, k), Sk("NRG_GMAP", 3))
    gput!(tm, "GR_GMAPC", gmapc)
    nodes_of = Dict{NTuple{2,String},Vector{String}}()                  # (R,NRG_GRID) -> its nodes C, GAMS order
    foreach(k -> push!(get!(() -> String[], nodes_of, (k[1], k[2])), k[3]), sorted(gmapc))
    nodes(r, g) = get(nodes_of, (r, g), String[])
    # L110: GR_ENDFR(R,T,COM,C)$TRACKC(R,C) = 0
    endfr = gvalues(tm, "GR_ENDFR", 4)
    filter!(((k, _),) -> !(k[2] in tset && (k[1], k[4]) in trackc), endfr)
    # L111: GR_GENFR(R,LL--ORD(LL),C,ITEM)$GR_GENFR(R,LL,C,ITEM)=1: LL--ORD(LL) is ALLYEAR's last label, '0' (G31)
    genfr = gvalues(tm, "GR_GENFR", 4)
    lastll = Sk("ALLYEAR", 1)[end][1]
    foreach(k -> (genfr[(k[1], lastll, k[3], k[4])] = 1.0), collect(keys(genfr)))
    # L112: LOOP((RC(R,C),RP(R,P))$GR_GENFR(R,'0',C,P),TRACKP(RP)=YES)   (TRACKP empty since L98-99)
    rp = S("RP", 2)
    foreach(k -> (k[2] == "0" && (k[1], k[3]) in rcset && (k[1], k[4]) in rp) && push!(trackp, (k[1], k[4])), keys(genfr))
    # L113: GR_GENMAP(TRACKP(R,P),P)$(NOT SUM(PRC$GR_GENMAP(R,PRC,P),1))=YES
    genmap = gvalues(tm, "GR_GENMAP", 3)
    typed = Set((k[1], k[3]) for k in keys(genmap))
    foreach(k -> (k in typed) || (genmap[(k[1], k[2], k[2])] = 1.0), trackp)
    # L114: OPTION GR_GENP < GR_GENMAP (R,P), GR_DEMMAP < GR_ENDFR: GR_DEMMAP(R,CG,C) from GR_ENDFR(R,ALLYEAR,C,CG),
    #   matched from the right (G52): CG from position 4, C from position 3
    genp = Set{NTuple{2,String}}((k[1], k[2]) for k in keys(genmap))
    demmap = Set{NTuple{3,String}}((k[1], k[4], k[3]) for k in keys(endfr))
    # L115: LOOP((GR_DEMMAP(R,COM,C),GR_GMAPC(R,NRG_GRID,C)),GR_ENDC(R,NRG_GRID,COM)=YES)
    endc = gmembers(tm, "GR_ENDC", 3)
    for (r, com, c) in demmap, g in gridl
        (iscom(com) && (r, g, c) in gmapc) && push!(endc, (r, g, com))
    end
    # L116-117: GR_GENLEV(TRACKC) = 0; GR_GENLEV(R,C)$GR_GENLEV(R,C) = ROUND(GR_GENLEV(R,C))   (half away from zero)
    genlev = gvalues(tm, "GR_GENLEV", 2)
    filter!(((k, _),) -> !(k in trackc), genlev)
    for (k, x) in collect(genlev)
        x == 0 && continue                                               # EPS stays EPS
        y = round(x, RoundNearestTiesAway)
        y == 0 ? delete!(genlev, k) : (genlev[k] = y)
    end
    # L118: TRACKPC(RPC(GR_GENP(R,P),C))$GR_GENLEV(R,C)=YES   (TRACKPC empty since L98-99)
    trackpc = Set{NTuple{3,String}}(k for k in Sk("RPC", 3) if (k[1], k[2]) in genp && haskey(genlev, (k[1], k[3])))
    # L119-120: GR_PRCMAP(TRACKPC(R,P,C),ITEM)$(TOP(R,P,C,'OUT')$GR_GENMAP(R,P,ITEM))=YES, and the same for RP_IRE
    items_of = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(() -> String[], items_of, (k[1], k[2])), k[3]), keys(genmap))
    top_out = Set((k[1], k[2], k[3]) for k in Sk("TOP", 4) if k[4] == "OUT")
    rp_ire = S("RP_IRE", 2)
    prcmap = gmembers(tm, "GR_PRCMAP", 4)
    for (r, p, c) in trackpc
        ((r, p, c) in top_out || (r, p) in rp_ire) || continue
        foreach(it -> push!(prcmap, (r, p, c, it)), get(items_of, (r, p), String[]))
    end
    # L121: OPTION GR_CMAP < GR_PRCMAP (R,C,ITEM), CLEAR=GR_DEMMAP, CLEAR=RXX
    cmap_of = Dict{String,Set{NTuple{2,String}}}()                     # R -> (COM,ITEM) of GR_CMAP
    foreach(k -> push!(get!(() -> Set{NTuple{2,String}}(), cmap_of, k[1]), (k[3], k[4])), prcmap)
    empty!(demmap)
    rxx = Set{NTuple{3,String}}()
    # L122: LOOP((GR_GMAPC(R,NRG_GRID,C),GR_CMAP(R,COM,ITEM))$GR_GENFR(R,'0',C,ITEM),RXX(R,NRG_GRID,COM)=YES)
    for (r, g, c) in gmapc, (com, it) in get(cmap_of, r, Set{NTuple{2,String}}())
        (iscom(com) && haskey(genfr, (r, "0", c, it))) && push!(rxx, (r, g, com))
    end
    # L123: LOOP(RXX(R,NRG_GRID,COM),GR_ALLMAP(R,C,COM)$GR_GMAPC(R,NRG_GRID,C)=YES)
    allmap = gmembers(tm, "GR_ALLMAP", 3)
    foreach(((r, g, com),) -> foreach(c -> push!(allmap, (r, c, com)), nodes(r, g)), rxx)
    # L124: GR_ALLMAP(TRACKC(R,COM),C)$(PROD(COM1$GR_ALLMAP(R,COM1,C),0)$GR_GENLEV(R,C)) $= SUM(GR_ALLMAP(R,COM,COM2),1):
    #   a generation commodity C that no node maps yet goes to every node COM that maps some; one parallel assignment
    mapped = Set((k[1], k[3]) for k in allmap if iscom(k[2]))           # PROD(...) is 0
    mapping = Set((k[1], k[2]) for k in allmap if iscom(k[3]))          # SUM(...) is nonzero
    for (r, com) in trackc, (r2, c) in keys(genlev)
        (r2 == r && iscom(c) && (r, com) in mapping && !((r, c) in mapped)) && push!(allmap, (r, com, c))
    end
    # L125: LOOP(NRG_GRID,GR_ALLMAP(R,C,COM)$((NOT GR_GMAPC(R,NRG_GRID,C))$NRG_GMAP(R,NRG_GRID,COM)) = NO)
    nrg_gmap = S("NRG_GMAP", 3)
    filter!(k -> !any(g -> (k[1], g, k[3]) in nrg_gmap && !((k[1], g, k[2]) in gmapc), gridl), allmap)
    # L127-128: GR_ALGMAP(R,'NRG',C) where GR_GENLEV(R,C) = 1, GR_ALGMAP(R,C,C) where it is 2
    algmap = gmembers(tm, "GR_ALGMAP", 3)
    for (k, x) in genlev
        x == 1 && push!(algmap, (k[1], "NRG", k[2]))
        x == 2 && push!(algmap, (k[1], k[2], k[2]))
    end
    # L129: GR_ALGMAP(R,COM_TYPE(CG),CG)$(SUM(TRACKC(R,C),1)>1) $= SUM(GR_ALGMAP(R,CG,C),1)   (parallel)
    nnodes = Dict{String,Int}()
    foreach(k -> (nnodes[k[1]] = get(nnodes, k[1], 0) + 1), trackc)
    comtype = S("COM_TYPE", 1)
    add = [(r, cg, cg) for (r, cg, c) in algmap if (cg,) in comtype && iscom(c) && get(nnodes, r, 0) > 1]
    union!(algmap, add)
    # L130: GR_DEMMAP(GR_ALLMAP(R,C,COM))$(GR_GENLEV(R,COM) < 3) = YES
    foreach(k -> (iscom(k[2]) && val(genlev, (k[1], k[3])).v < 3) && push!(demmap, k), allmap)
    # L131: IF(CARD(GR_DEMFR), ...): GR_DEMFR has no data here (powerflo_main_unported)
    demfr = gvalues(tm, "GR_DEMFR", 4)
    # L132: GR_ENDC(R,NRG_GRID,'DEM')$SUM(GR_ENDC(R,NRG_GRID,C),1) = YES
    foreach(k -> iscom(k[3]) && push!(endc, (k[1], k[2], "DEM")), collect(endc))
    # L134-138: LOOP((R,NRG_GRID)$GR_ENDC(R,NRG_GRID,'DEM'), ...): demand fractions from the sectoral ones
    varc_of = indexby(gset(tm, "RTCS_VARC"), (1, 2, 3))
    rcg_sorted = sorted(rc_grid)
    rtc_sorted = sorted(Sk("RTC", 3))
    for r in regs, g in gridl
        (r, g, "DEM") in endc || continue
        sect = [c for (r2, g2, c) in sorted(endc) if r2 == r && g2 == g && iscom(c)]
        # L135: GR_DEMFR(RTCS_VARC(RC_GRID(R,T,COM),S)) = SUM(GR_ENDC(R,NRG_GRID,C),MIN(0.33,GR_ENDFR(R,T,COM,C)))
        for (r2, t, com) in rcg_sorted
            r2 == r || continue
            x = sum((gmin(GNum(0.33), val(endfr, (r, t, com, c))) for c in sect); init=GZERO)
            foreach(k -> set!(demfr, k, x), get(varc_of, (r, t, com), NTuple{4,String}[]))
        end
        # L136: GR_UNITS(RTC(R,T,C))$GR_ENDC(R,NRG_GRID,C) = SUM(RC_GRID(R,T,COM),GR_ENDFR(R,T,COM,C))+1-1
        units = Dict{NTuple{3,String},Float64}()
        for (r2, t, c) in rtc_sorted
            (r2 == r && (r, g, c) in endc) || continue
            x = sum((val(endfr, (r, t, com, c)) for (r3, t2, com) in rcg_sorted if r3 == r && t2 == t); init=GZERO)
            set!(units, (r, t, c), x + GNum(1.0) - GNum(1.0))
        end
        # L137: GR_ENDFR(RC_GRID(R,T,COM),C)$(GR_ENDC(R,NRG_GRID,C)$GR_UNITS(R,T,C)) = GR_ENDFR(R,T,COM,C)/GR_UNITS(R,T,C)
        for (r2, t, com) in rcg_sorted, c in sect
            (r2 == r && haskey(units, (r, t, c))) || continue
            set!(endfr, (r, t, com, c), val(endfr, (r, t, com, c)) / val(units, (r, t, c)))
        end
        # L138: OPTION CLEAR=GR_UNITS
    end
    # L139: LOOP(GR_ALLMAP(R,COM,C),GR_ENDC(R,NRG_GRID,C)$((GR_GENLEV(R,C)>2)$GR_GMAPC(R,NRG_GRID,COM)$GR_GENLEV(R,C)) = YES)
    for (r, com, c) in allmap, g in gridl
        (iscom(com) && haskey(genlev, (r, c)) && genlev[(r, c)] > 2 && (r, g, com) in gmapc) && push!(endc, (r, g, c))
    end
    # L140: GR_ENDC(R,NRG_GRID,'NRG')$(NOT GR_ENDC(R,NRG_GRID,'DEM')) = SUM(GR_GMAPC(R,NRG_GRID,C),1)
    for r in regs, g in gridl
        (r, g, "DEM") in endc && continue
        isempty(nodes(r, g)) ? delete!(endc, (r, g, "NRG")) : push!(endc, (r, g, "NRG"))
    end
    gput!(tm, "GR_ENDC", endc)
    # L142: PRC_YMAX(GR_GENP(R,P)) = SUM(ITEM$GR_GENMAP(R,P,ITEM),GR_GENMAP(R,P,ITEM))+1-1
    ymax = Dict{NTuple{2,String},GNum}()
    for k in sorted(keys(genmap))
        ymax[(k[1], k[2])] = get(ymax, (k[1], k[2]), GZERO) + val(genmap, k)
    end
    foreach(k -> (ymax[k] = ymax[k] + GNum(1.0) - GNum(1.0)), collect(keys(ymax)))
    # L143: GR_GENMAP(GR_GENP(R,P),ITEM)$(PRC_YMAX(R,P)$GR_GENMAP(R,P,ITEM)) = GR_GENMAP(R,P,ITEM)/PRC_YMAX(R,P)
    for k in collect(keys(genmap))
        y = get(ymax, (k[1], k[2]), GZERO)
        iszero(y) || set!(genmap, k, val(genmap, k) / y)
    end
    # L145: LOOP(RC_GRID(R,T,C),GR_UNITS(R,T,ITEM)$GR_GENFR(R,T,C,ITEM)=1)
    genfr_of = Dict{NTuple{3,String},Vector{String}}()                 # (R,T,C) -> ITEM of GR_GENFR
    foreach(k -> push!(get!(() -> String[], genfr_of, (k[1], k[2], k[3])), k[4]), sorted(keys(genfr)))
    units = Dict{NTuple{3,String},Float64}()
    for (r, t, c) in rc_grid, it in get(genfr_of, (r, t, c), String[])
        units[(r, t, it)] = 1.0
    end
    # L146: GR_UNITS(R,T,ITEM)$GR_UNITS(R,T,ITEM) = SUM(TRACKC(R,C),GR_GENFR(R,T,C,ITEM))+1-1
    trackc_sorted = sorted(trackc)
    for (r, t, it) in collect(keys(units))
        x = sum((val(genfr, (r, t, c, it)) for (r2, c) in trackc_sorted if r2 == r); init=GZERO)
        set!(units, (r, t, it), x + GNum(1.0) - GNum(1.0))
    end
    # L147: GR_GENFR(RC_GRID(R,T,C),ITEM)$GR_UNITS(R,T,ITEM) = GR_GENFR(R,T,C,ITEM)/GR_UNITS(R,T,ITEM)
    for (r, t, c) in rc_grid, it in get(genfr_of, (r, t, c), String[])
        haskey(units, (r, t, it)) && set!(genfr, (r, t, c, it), val(genfr, (r, t, c, it)) / val(units, (r, t, it)))
    end
    # L148: OPTION CLEAR=GR_CMAP,CLEAR=PRC_YMAX,CLEAR=GR_UNITS
    gput!(tm, "PRC_YMAX", Dict{NTuple{2,String},Float64}())
    # L150-154: per NRG_GRID, the demand fractions of its nodes normalised to 1 (EPS where a node has none)
    for g in gridl
        # L151: LOOP(RC_GRID(R,T,C)$GR_GMAPC(R,NRG_GRID,C),GR_UNITS(R,T,S)$GR_DEMFR(R,T,C,S)=1)
        units = Dict{NTuple{3,String},Float64}()
        for k in keys(demfr)
            ((k[1], k[2], k[3]) in rc_grid && (k[1], g, k[3]) in gmapc) && (units[(k[1], k[2], k[4])] = 1.0)
        end
        # L152: GR_UNITS(R,T,S)$GR_UNITS(R,T,S) = SUM(GR_GMAPC(R,NRG_GRID,C),GR_DEMFR(R,T,C,S))+1-1
        for (r, t, s) in collect(keys(units))
            x = sum((val(demfr, (r, t, c, s)) for c in nodes(r, g)); init=GZERO)
            set!(units, (r, t, s), x + GNum(1.0) - GNum(1.0))
        end
        # L153: GR_DEMFR(RC_GRID(R,T,C),S)$(GR_GMAPC(R,NRG_GRID,C)$GR_UNITS(R,T,S)) = GR_DEMFR(R,T,C,S)/GR_UNITS(R,T,S)+EPS
        s_of = Dict{NTuple{2,String},Vector{String}}()
        foreach(k -> push!(get!(() -> String[], s_of, (k[1], k[2])), k[3]), keys(units))
        for (r, t, c) in rc_grid, s in get(s_of, (r, t), String[])
            (r, g, c) in gmapc || continue
            set!(demfr, (r, t, c, s), val(demfr, (r, t, c, s)) / val(units, (r, t, s)) + GEPS)
        end
        # L154: OPTION CLEAR=GR_UNITS
    end
    # L156-161: per GR_ENDC(R,NRG_GRID,COM_TYPE(CG)) and period, the first node with the largest demand fraction
    #   into GR_ADO (LOOP ... $Z stops at the first, as Z is then 0); for 'DEM' its fractions are removed
    units = Dict{NTuple{3,String},Float64}()                            # GR_UNITS(R,T,C), left as the block leaves it
    ado = gmembers(tm, "GR_ADO", 3)
    gnall = gmembers(tm, "GR_GNALL", 3)
    comts_of = Dict{NTuple{2,String},Vector{String}}()                 # (R,C) -> S of COM_TS, GAMS order
    foreach(k -> push!(get!(() -> String[], comts_of, (k[1], k[2])), k[3]), Sk("COM_TS", 3))
    allmap_of = Dict{NTuple{2,String},Vector{String}}()                # (R,C) -> COM of GR_ALLMAP(R,C,COM)
    foreach(k -> iscom(k[2]) && push!(get!(() -> String[], allmap_of, (k[1], k[2])), k[3]), allmap)
    for (r, g, cg) in sorted(endc)
        (r in reg && (cg,) in comtype) || continue
        ns = nodes(r, g)
        # L157: GR_UNITS(RC_GRID(R,T,C))$GR_GMAPC(R,NRG_GRID,C) = SUM(COM_TS(R,C,S),GR_DEMFR(R,T,C,S))
        for (r2, t, c) in rcg_sorted
            (r2 == r && (r, g, c) in gmapc) || continue
            set!(units, (r, t, c), sum((val(demfr, (r, t, c, s)) for s in get(comts_of, (r, c), String[])); init=GZERO))
        end
        # L158-159: Z = MAX(EPS,SMAX(GR_GMAPC(R,NRG_GRID,C),GR_UNITS(R,T,C))); the first node equal to Z into GR_ADO
        for t in T
            Z = gmax(GEPS, foldl(gmax, (val(units, (r, t, c)) for c in ns); init=GNum(-Inf)))
            for c in ns
                iszero(Z) && break                                       # $Z
                val(units, (r, t, c)).v == Z.v && (push!(ado, (r, t, c)); Z = GZERO)
            end
        end
        # L160: IF(SAMEAS(CG,'DEM'),GR_DEMFR(GR_ADO(R,T,C),S)$GR_GMAPC(R,NRG_GRID,C)=0)
        cg == "DEM" && filter!(((k, _),) -> !(k[1] == r && (r, k[2], k[3]) in ado && (r, g, k[3]) in gmapc), demfr)
        # L161: GR_GNALL(RC_GRID(R,T,C))$SUM(GR_ALLMAP(R,C,COM),GR_GMAPC(R,NRG_GRID,C)) = YES: a node of this grid
        #   that some generation commodity is mapped to
        for (r2, t, c) in rc_grid
            (r2 == r && (r, g, c) in gmapc && !isempty(get(allmap_of, (r, c), String[]))) && push!(gnall, (r2, t, c))
        end
    end
    # L162: GR_ADO(RTC(RC_GRID)) = NOT GR_ADO(RTC)
    rtc = S("RTC", 3)
    for k in rc_grid
        k in rtc || continue
        k in ado ? delete!(ado, k) : push!(ado, k)
    end
    gput!(tm, "GR_ADO", ado)
    for (n, v) in (("GR_ENDFR", endfr), ("GR_GENFR", genfr), ("GR_GENMAP", genmap), ("GR_GENLEV", genlev), ("GR_DEMFR", demfr),
                   ("GR_UNITS", units), ("GR_GENP", genp), ("GR_DEMMAP", demmap), ("GR_PRCMAP", prcmap), ("GR_ALLMAP", allmap),
                   ("GR_ALGMAP", algmap), ("GR_GNALL", gnall), ("RXX", rxx))
        gput!(tm, n, v)
    end
    gput!(tm, "GR_CMAP", Set{NTuple{3,String}}())
    # L172-178: IF(DFUNC, ... (PTDF) ELSE OPTION CLEAR=RP_GRID)
    gput!(tm, "RP_GRID", Set{NTuple{2,String}}())
    # L181: COM_LIM(TRACKC(RC),'FX')$((NOT SUM(COM_LIM(RC,L),1))$GR_GID(RC)) = YES
    lim = gmembers(tm, "COM_LIM", 3)
    for (r, c) in sorted(trackc)
        ((r, c) in rcset && haskey(gid, (r, c)) && !any(k -> k[1] == r && k[2] == c, lim)) && push!(lim, (r, c, "FX"))
    end
    gput!(tm, "COM_LIM", lim)
    gput!(tm, "GR_GID", Dict{NTuple{2,String},Float64}(k => (x.eps ? 0.0 : x.v) for (k, x) in gid))
    gput!(tm, "GR_TOP", gr_top)
    gput!(tm, "GR_ARC", gr_arc)
    # L182: OPTION CLEAR=TRACKC,CLEAR=RP_PRC,CLEAR=TRACKPC; L183: gasgrids.vda exits without GG_KGF
    gput!(tm, "TRACKC", Set{NTuple{2,String}}()); gput!(tm, "RP_PRC", Set{NTuple{2,String}}())
    gput!(tm, "TRACKPC", Set{NTuple{3,String}}())
    gput!(tm, "TRACKP", trackp)                      # L112's: cleared only in the PTDF branch (L177)
    # the scratch as the block leaves it
    F === nothing || gput_scalar!(tm, "F", F isa GNum ? F : GNum(F))
    Z === nothing || gput_scalar!(tm, "Z", Z)
    gput_scalar!(tm, "CNT", cnt)
    gput_scalar!(tm, "DFUNC", dfunc)
    my_f === nothing || gput_scalar!(tm, "MY_F", my_f)
    done === nothing || gput_scalar!(tm, "DONE", done)
    return tm
end

# --- M1.3 (27b): DECL (mod_vars.mod L95) and POWFLO (equ_ext.vda L101) ---------------------------

"""
The variables powerflo.vda DECL declares (L196-199), only under %POWERFLO% (as
`\$IF DEFINED PRC_REACT` at mod_vars.mod L95): VAR_GRIDIO and VAR_XCAP
positive, the phase angle VAR_COMAUX free.
"""
const POWERFLO_VARS = VariableSpec[
    VariableSpec("VAR_GRIDIO", ["R", "YEAR", "C", "C", "S", "IO"], true, "Flows between grid nodes and their commodity (powerflo.vda L197)", 95),
    VariableSpec("VAR_XCAP", ["R", "YEAR", "ITEM"], true, "Virtual capacity of a candidate line (powerflo.vda L198)", 95),
    VariableSpec("VAR_COMAUX", ["R", "T", "C", "S"], false, "Phase angle of a grid node (powerflo.vda L199)", 95),
]

"Declare powerflo.vda's variables in the model's variable store (once)."
function powerflo_vars!(tm)
    for spec in POWERFLO_VARS
        n = uppercase(spec.name)
        haskey(tm.vars.families, n) && continue
        tm.vars.families[n] = VarFamily(spec)
        push!(tm.vars.order, n)
    end
    return tm
end

"""
    powerflo_reference_nodes(tm) -> Set{NTuple{2,String}}

powerflo.vda L222-223: in each disjoint grid J (GR_GRID with GR_GID), the
first node (GAMS order) with the most lines (GR_FLOW records) is the
reference node, whose phase angle VAR_COMAUX is fixed at 0 (EPS).
"""
function powerflo_reference_nodes(tm)
    d = tm.data
    gid = gparam_opt(d, "GR_GID", 2)
    flow = gparam_opt(d, "GR_FLOW", 3)
    nlines = Dict{NTuple{2,String},Int}()
    foreach(k -> (nlines[(k[1], k[3])] = get(nlines, (k[1], k[3]), 0) + 1), keys(flow.values))
    grid = gams_sort!(collect(gset_opt(d, "GR_GRID", 3).keys), d)
    out = Set{NTuple{2,String}}()
    for j in unique(k[1] for k in grid)
        nodes = [(k[2], k[3]) for k in grid if k[1] == j]
        any(n -> haskey(gid, n), nodes) || continue              # LOOP(J$SUM(GR_GRID(J,R,C)$GR_GID(R,C),1), ...)
        z = maximum((get(nlines, n, 0) for n in nodes); init=0)
        z == 0 && continue                                       # LOOP(GR_GRID(J,R,C)$Z, ...)
        i = findfirst(n -> get(nlines, n, 0) == z, nodes)
        push!(out, nodes[i])
    end
    return out
end

"""
    powerflo_decl!(tm) -> tm

powerflo.vda DECL (mod_vars.mod L95) on the state after the coefficient
stage: the variables (`powerflo_vars!`), the scratch Z of the reference-node
loop (L222-223; the fixed phase angles are bounds, `bnd_powerflo!`) and
GR_GRID(J,R,'ACT') for every grid with an electricity node (L224). The
candidate lines (L229-249) come only with the PTDF formulation, refused.

GAMS: powerflo.vda L194-226, v4.9.7.
"""
function powerflo_decl!(tm)
    u = powerflo_model_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    powerflo_vars!(tm)
    d = tm.data
    # L222-223: Z = SMAX(...) per grid, set to 0 at its reference node
    grid = gset_opt(d, "GR_GRID", 3).keys
    gid = gparam_opt(d, "GR_GID", 2)
    any(k -> haskey(gid, (k[2], k[3])), grid) && gput_scalar!(tm, "Z", 0.0)
    # L224: GR_GRID(J,R,'ACT') $= SUM(GR_GRID(J,NRGELC(R,C)),1)
    nrgelc = gset_opt(d, "NRGELC", 2).members
    g = gmembers(tm, "GR_GRID", 3)
    foreach(k -> (k[2], k[3]) in nrgelc && push!(g, (k[1], k[2], "ACT")), collect(g))
    gput!(tm, "GR_GRID", g)
    return tm
end

"""
    bnd_powerflo!(bt, tm) -> bt

powerflo.vda L223: `VAR_COMAUX.FX(R,T,C,S) = EPS` at each grid's reference
node (`powerflo_reference_nodes`), for the columns the equations created.

GAMS: powerflo.vda L222-223, v4.9.7.
"""
function bnd_powerflo!(bt, tm)
    haskey(tm.vars.families, "VAR_COMAUX") || return bt
    ref = powerflo_reference_nodes(tm)
    recs = get!(() -> Dict{Tuple,Tuple{Float64,Float64}}(), bt.recs, "VAR_COMAUX")
    for k in tm.vars.families["VAR_COMAUX"].keys
        (k[1], k[3]) in ref && (recs[k] = (0.0, 0.0))
    end
    return bt
end

"""
    eq_gr_powflo!(tm) -> Int

EQ_GR_POWFLO, the DC power flow in the phase-angle formulation (equ_ext.vda
L101): for each grid node C of region R (RC_GRID) at its commodity
timeslices S and each node COM of region REG it is linked to (GR_ADMIT),
the flow over the lines GR_TOP(R,C,REG,COM,P) with a reactance, as REG's
imports less its exports of COM, equals the admittance times the
difference of the phase angles VAR_COMAUX of the two nodes. Returns the
number of rows.

GAMS: powerflo.vda L250-258, v4.9.7.
"""
function eq_gr_powflo!(tm)
    uppercase(strip(gswitch(tm, "POWERFLO", ""), ['\'', '"'])) == "YES" || return 0
    powerflo_vars!(tm)
    admit = gparam(tm, "GR_ADMIT")
    isempty(admit) && return 0
    d = tm.data
    rc_grid = gset(tm, "RC_GRID").members
    varc_of = indexby(gset(tm, "RTCS_VARC"), (1, 2, 3))              # (r,t,c) -> RTCS_VARC(r,t,c,s)
    top_of = indexby(gset(tm, "GR_TOP"), (1, 2, 3, 4))                # (r,c,reg,com) -> GR_TOP(...,p)
    vint_of = indexby(gset(tm, "RTP_VINTYR"), (1, 3, 4))              # (r,t,p) -> RTP_VINTYR(r,v,t,p)
    varf = gset(tm, "RTPCS_VARF").members
    ire_of = indexby(gset(tm, "RPC_IRE"), (1, 2, 3))                  # (r,p,c) -> RPC_IRE(r,p,c,ie)
    react = gparam(tm, "PRC_REACT")
    no4, no5 = NTuple{4,String}[], NTuple{5,String}[]
    n = 0
    for ((r, t, c, reg, com), a) in sort(collect(admit.values); by=first)
        (r, t, c) in rc_grid || continue
        for (_, _, _, s) in get(varc_of, (r, t, c), no4)
            lhs = JuMP.AffExpr(0.0)
            for (_, _, _, _, p) in get(top_of, (r, c, reg, com), no5)
                iszero(gv(react, (r, t, p))) && continue                 # $PRC_REACT(R,T,P)
                (reg, t, p, com, s) in varf || continue                  # $RTPCS_VARF(REG,T,P,COM,S)
                for (_, v, _, _) in get(vint_of, (reg, t, p), no4), (_, _, _, ie) in get(ire_of, (reg, p, com), no4)
                    addterm!(lhs, GNum(ie == "EXP" ? -1.0 : 1.0), tm, "VAR_IRE", reg, v, t, p, com, s, ie)   # (1-2*XPT(IE))
                end
            end
            rhs = JuMP.AffExpr(0.0)
            addterm!(rhs, GNum(a), tm, "VAR_COMAUX", r, t, c, s)
            addterm!(rhs, GNum(-a), tm, "VAR_COMAUX", reg, t, com, s)
            gconstraint!(tm, "EQ_GR_POWFLO", (r, t, c, s, reg, com), "E", lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end
