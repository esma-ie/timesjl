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
translated: the PTDF formulation (GR_PTDF data: L59-64, L159-170) and the
allocation of generation and demand to grid nodes (GR_DEMFR, GR_ENDFR,
GR_GENFR, GR_GENMAP, GR_GENLEV data: L40-42, L106-161), besides the gas
grids. Without that data those lines run on empty sets, which is translated.
"""
function powerflo_main_unported(tm)
    out = powerflo_unported(tm)
    hasdata(tm, "GR_PTDF", 6) && push!(out, "powerflo.vda L59-64, L159-170 (GR_PTDF has data: the PTDF formulation)")
    for (n, k) in (("GR_DEMFR", 4), ("GR_ENDFR", 4), ("GR_GENFR", 4), ("GR_GENMAP", 3), ("GR_GENLEV", 2))
        hasdata(tm, n, k) && push!(out, "powerflo.vda L40-42, L106-161 ($n has data: allocation to grid nodes)")
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
grid maps GR_GMAPC and GR_ENDC, the reference nodes GR_ADO, and COM_LIM FX
on the grid nodes. Loops run in GAMS order; the scratch (F, Z, CNT, DFUNC,
MY_F, DONE) is left as GAMS leaves it.

GAMS: powerflo.vda L11-204 (without GR_PTDF and allocation data), v4.9.7.
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
    # L40-42: TRACKC <= GR_DEMFR, GR_GID <= GR_ENDFR, GG_PRBD, GR_GENFR: no such data (powerflo_main_unported)
    # L43-44: OPTION CLEAR=TRACKC, TRACKP < PRC_REACT, RP_PRC < GR_PTDF; DFUNC=CARD(RP_PRC); TRACKP(RP_PRC)=YES
    trackp = Set{NTuple{2,String}}((k[1], k[3]) for k in keys(react))
    rp_prc = Set{NTuple{2,String}}()
    dfunc = 0.0
    # L45: TRACKC(R,C) $= SUM(NRG_GMAP(R,NRG_GRID,C),1)
    grids = S("NRG_GRID", 1)
    trackc = Set{NTuple{2,String}}((k[1], k[3]) for k in Sk("NRG_GMAP", 3) if k[1] in reg && (k[2],) in grids)
    # L47: LOOP(RPC_IRE(R,P,C,IE)$GR_GID(R,C),TRACKP(R,P)=YES)   (GR_GID empty)
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
            my_f, done = min(f.v, z.v), max(f.v, z.v)
            cnt.v == done + 1 && (cnt = GNum(done))
            for k in trackc
                gget(k).v == done && (gid[k] = GNum(my_f))
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
    # L107: pp_lvlfc.mod GR_DEMFR (no data): OPTION CLEAR=UNCD7
    gput!(tm, "UNCD7", Set{NTuple{7,String}}())
    # L108: GR_GMAPC(NRG_GMAP(R,NRG_GRID,C)) $= TRACKC(R,C)
    gmapc = gmembers(tm, "GR_GMAPC", 3)
    foreach(k -> ((k[2],) in grids && (k[1], k[3]) in trackc) && push!(gmapc, k), Sk("NRG_GMAP", 3))
    gput!(tm, "GR_GMAPC", gmapc)
    # L109-138 run on empty allocation data; L120: OPTION CLEAR=RXX
    gput!(tm, "RXX", Set{NTuple{3,String}}())
    # L139: GR_ENDC(R,NRG_GRID,'NRG')$(NOT GR_ENDC(R,NRG_GRID,'DEM')) = SUM(GR_GMAPC(R,NRG_GRID,C),1)
    endc = gmembers(tm, "GR_ENDC", 3)
    for r in regs, (g,) in sorted(grids)
        (r, g, "DEM") in endc && continue
        any(k -> k[1] == r && k[2] == g, gmapc) ? push!(endc, (r, g, "NRG")) : delete!(endc, (r, g, "NRG"))
    end
    gput!(tm, "GR_ENDC", endc)
    # L148: OPTION CLEAR=GR_CMAP,CLEAR=PRC_YMAX,CLEAR=GR_UNITS
    gput!(tm, "PRC_YMAX", Dict{NTuple{2,String},Float64}())
    # L156-162: per GR_ENDC(R,NRG_GRID,COM_TYPE(CG)) and period, the first node with the largest demand fraction into
    #   GR_ADO (all 0 without GR_DEMFR: Z = MAX(EPS,0) = EPS, which the first node's 0 equals); then flipped (L163)
    ado = gmembers(tm, "GR_ADO", 3)
    comtype = S("COM_TYPE", 1)
    for (r, g, cg) in sorted(endc)
        (r in reg && (cg,) in comtype) || continue
        nodes = [k[3] for k in sorted(gmapc) if k[1] == r && k[2] == g]
        for t in T
            Z = GEPS
            for c in nodes
                (r, t, c) in rc_grid || continue
                push!(ado, (r, t, c)); Z = GZERO
                break
            end
        end
    end
    rtc = S("RTC", 3)
    for k in rc_grid
        k in rtc || continue
        k in ado ? delete!(ado, k) : push!(ado, k)
    end
    gput!(tm, "GR_ADO", ado)
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
    gput!(tm, "TRACKPC", Set{NTuple{3,String}}()); gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    # the scratch as the block leaves it
    F === nothing || gput_scalar!(tm, "F", F isa GNum ? F : GNum(F))
    Z === nothing || gput_scalar!(tm, "Z", Z)
    gput_scalar!(tm, "CNT", cnt)
    gput_scalar!(tm, "DFUNC", dfunc)
    my_f === nothing || gput_scalar!(tm, "MY_F", my_f)
    done === nothing || gput_scalar!(tm, "DONE", done)
    return tm
end
