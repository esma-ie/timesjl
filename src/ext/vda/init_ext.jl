# M1.3 (1): the VDA extension's initial preprocessing, and the segment
# driver for maindrv.mod L55 (the input -> init checkpoints).
#
# GAMS: init_ext.vda L52-156, v4.9.7, run at maindrv.mod L55 through
# main_ext.mod (init_ext.dsc first when the DSC extension is loaded; DSC
# precedes VDA in %EXTEND%, initmty.mod L467-468), with equcrtp.vda INIT_EXT
# at L128 (equcrtp.jl).
#
# L8-50 declare the extension's sets and parameters, and L74, L133, L138-151
# are compile-time directives ($KILL, $CLEAR, $GDXIN/$LOAD): their data
# effects are already in the input dump, taken after compilation. The
# $GDXIN/$LOAD of an earlier run's trade bounds and prices (GDX_IREBND,
# GDX_IPRIC) is refused, as are CLI YES (L129) and STAGES YES (L133), and
# SPINES or SENSIS YES, which turn STAGES on (maindrv.mod L33-36).
#
# Index sets: R is REG, T is MILESTONYR, LL and YEAR are ALLYEAR, C is COM;
# '%DFLBL%' is '0' (initmty.mod L367), and LL--ORD(LL) is the last ALLYEAR
# element, also '0' (G31). Comparisons treat EPS as 0, `$` as present (G12);
# `$=` assigns where the right side is nonzero or EPS (G24); a statement
# reads the values from before it (G11). GAMS MOD keeps the sign of its
# first argument (`rem`); ROUND rounds halves away from zero.

"The init_ext.vda paths this model would take that are not translated; empty when init_ext_vda! can run."
function init_ext_vda_unported(tm)
    out = String[]
    yes(n) = uppercase(gswitch(tm, n, "")) == "YES"
    yes("CLI") && push!(out, "init_ext.vda L129 (CLI YES: climate extension, outside Phase 1)")
    yes("STAGES") && push!(out, "init_ext.vda L133 (STAGES YES)")
    # SPINES or SENSIS turns the stochastic extension on too (initmty.mod L435-437, maindrv.mod L33-36; `$IFI`,
    # so any case), though the run file does not set STAGES: translated in M1.3 changes 71-76 (docs/m13-plan.md)
    for n in ("SPINES", "SENSIS")
        yes(n) && push!(out, "maindrv.mod L33-36 ($n YES: the stochastic extension)")
    end
    for n in ("GDX_IREBND", "GDX_IPRIC")
        gswitch(tm, n, "") == "" || push!(out, "init_ext.vda L138-151 ($n set: trade bounds/prices loaded from an earlier run)")
    end
    return out
end

"The paths of the init segment (maindrv.mod L55) this model would take that are not translated."
init_ext_unported(tm) = vcat(dsc_loaded(tm) ? init_ext_dsc_unported(tm) : String[], init_ext_vda_unported(tm))

"""
    init_ext!(tm) -> tm

The init segment, maindrv.mod L55 (`main_ext.mod init_ext %EXTEND%`): the
DSC extension's init_ext.dsc when it is loaded, then init_ext.vda. Starts
from the harness's `input/` checkpoint, ends at `init/`.

GAMS: maindrv.mod L55, main_ext.mod, v4.9.7.
"""
function init_ext!(tm)
    u = init_ext_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    readbprice!(tm)                                   # maindrv.mod L28-29 (M1.3 change 69)
    dsc_loaded(tm) && init_ext_dsc!(tm)
    init_ext_vda!(tm)
    return tm
end

# OPTION a < b: the projection of b's keys onto the positions `pos` (G26)
project(keys, pos::NTuple{M,Int}) where {M} = Set{NTuple{M,String}}(ntuple(i -> k[pos[i]], Val(M)) for k in keys)

"""
    init_ext_vda!(tm) -> tm

init_ext.vda L52-156 on the GAMS state in `tm`.

GAMS: init_ext.vda L52-156, v4.9.7.
"""
function init_ext_vda!(tm)
    u = init_ext_vda_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    dflbl = "0"                                                       # %DFLBL% (initmty.mod L367)
    allyear = [k[1] for k in gset(tm, "ALLYEAR").keys]
    t0 = last(allyear)                                                # LL--ORD(LL) (G31)
    yearval = gparam(tm, "YEARVAL")
    yv(y) = yearval[(y,)]
    com = gset(tm, "COM")
    reg = gset(tm, "REG")
    # labels the file writes that a dump holds only when some record uses them (G36)
    foreach(l -> register_uel!(tm.data, l), ("", "PASTI", "UP", "FX", "OUT", "ACT", "UCN", "NET", "PRD", "ANNUAL", dflbl))

    # --- Basic years (L52-60) ------------------------------------------------
    # L53-54: IF(CARD(DATAYEAR)=0, DATAYEAR(T)=YES; DATAYEAR(LL)$(MOD(MAX(1999,MIN(2051,YEARVAL(LL))),5)=0)=YES)
    datayear = gmembers(tm, "DATAYEAR", 1)
    if isempty(datayear)
        union!(datayear, gset(tm, "MILESTONYR").keys)
        for y in allyear
            rem(max(1999, min(2051, yv(y))), 5) == 0 && push!(datayear, (y,))
        end
    end
    union!(datayear, gset(tm, "PASTYEAR").keys)                       # L55: DATAYEAR(PASTYEAR) = YES
    delete!(datayear, (dflbl,))                                       # L56: DATAYEAR('%DFLBL%') = NO
    gput!(tm, "DATAYEAR", datayear)
    # L57-58: LOOP(T$(ORD(T)=1), IF(ABS(B(T)-YEARVAL(T)+5)>5, B(T)=YEARVAL(T)); MIYR_1(T)=YES; MIYR_BOH=B(T)-1)
    t1 = first(gset(tm, "MILESTONYR").keys)[1]
    b = gvalues(tm, "B", 1)
    abs(get(b, (t1,), 0.0) - yv(t1) + 5) > 5 && gassign!(b, (t1,), yv(t1))
    gput!(tm, "B", b)
    miyr_1 = gmembers(tm, "MIYR_1", 1)
    push!(miyr_1, (t1,))
    gput!(tm, "MIYR_1", miyr_1)
    miyr_boh = get(b, (t1,), 0.0) - 1
    gput!(tm, "MIYR_BOH", gassign!(Dict{Tuple{},Float64}(), (), miyr_boh))
    # L59: PYR_S(LL) = YEARVAL(LL)=MIYR_BOH
    gput!(tm, "PYR_S", Set{NTuple{1,String}}((y,) for y in allyear if yv(y) == miyr_boh))
    # L60: $IFI %WAVER%==YES INT_DEFAULT('PASTI')=1
    if uppercase(gswitch(tm, "WAVER", "")) == "YES"
        intd = gmembers(tm, "INT_DEFAULT", 1)
        push!(intd, ("PASTI",))
        gput!(tm, "INT_DEFAULT", intd)
    end

    # --- Peaking and storage (L62-74) -----------------------------------------
    # L63: PRC_PKNO(R,P)$((NCAP_PKCNT(R,'0',P,'ANNUAL')>=10)$NCAP_PKCNT(R,'0',P,'ANNUAL')) = YES
    # L64: PRC_PKAF(R,P)$((NCAP_PKCNT(R,'0',P,'ANNUAL')<= 0)$NCAP_PKCNT(R,'0',P,'ANNUAL')) = YES
    pkcnt = gparam_opt(tm.data, "NCAP_PKCNT", 4)
    pkno, pkaf = gmembers(tm, "PRC_PKNO", 2), gmembers(tm, "PRC_PKAF", 2)
    npk = (length(pkno), length(pkaf))
    for (k, v) in pkcnt.values
        (k[2] == dflbl && k[4] == "ANNUAL" && (k[1],) in reg) || continue
        v >= 10 && push!(pkno, (k[1], k[3]))
        v <= 0 && push!(pkaf, (k[1], k[3]))                          # EPS <= 0 (G12)
    end
    length(pkno) == npk[1] || gput!(tm, "PRC_PKNO", pkno)
    length(pkaf) == npk[2] || gput!(tm, "PRC_PKAF", pkaf)
    # L65: PRC_STGIPS(R,P,C)$(NOT SUM(PRC_ACTUNT(R,P,CG,UNITS_ACT)$(COM_GMAP(R,CG,C)+SAMEAS(CG,C)),1)) = NO
    stgips = gmembers(tm, "PRC_STGIPS", 3)
    if !isempty(stgips)
        actunt = indexby(gset(tm, "PRC_ACTUNT"), (1, 2))
        gmap = gset(tm, "COM_GMAP")
        filter!(k -> any(a -> (k[1], a[3], k[3]) in gmap || a[3] == k[3], get(actunt, (k[1], k[2]), NTuple{4,String}[])), stgips)
        gput!(tm, "PRC_STGIPS", stgips)
    end
    # L67: OPTION TRACKP<STG_MAXCYC; RP_PL(TRACKP,'UP')=YES
    trackp = project(gparam_opt(tm.data, "STG_MAXCYC", 3).keys, (1, 3))
    if !isempty(trackp)
        rp_pl = gmembers(tm, "RP_PL", 3)
        foreach(k -> push!(rp_pl, (k..., "UP")), trackp)
        gput!(tm, "RP_PL", rp_pl)
    end
    # L68-72: LOOP(TSL(S(ANNUAL)), ACT_CSTUP(R,LL,P,TSL,CUR)=0; ACT_CSTUP(R,LL,P,TSL,CUR)$=ACT_CSTPL(R,LL,P,CUR);
    #           ACT_CSTUP(R,LL,P,TSL,CUR)$TRACKP(R,P) $= NCAP_COST(R,LL,P,CUR); ACT_UPS(R,LL,P,S,'FX') $= ACT_MINLD(R,LL,P))
    tslvl = gset_opt(tm.data, "TSLVL", 1)
    for (s,) in gset(tm, "ANNUAL").keys
        (s,) in tslvl || continue
        cstup = Dict(k => v for (k, v) in gvalues(tm, "ACT_CSTUP", 5) if k[4] != s)
        cstpl = gparam_opt(tm.data, "ACT_CSTPL", 4)
        for (k, _) in cstpl.values
            gassign!(cstup, (k[1], k[2], k[3], s, k[4]), gv(cstpl, k))
        end
        if !isempty(trackp)
            cost = gparam(tm, "NCAP_COST")
            for (k, _) in cost.values
                (k[1], k[3]) in trackp && gassign!(cstup, (k[1], k[2], k[3], s, k[4]), gv(cost, k))
            end
        end
        gput!(tm, "ACT_CSTUP", cstup)
        minld = gparam_opt(tm.data, "ACT_MINLD", 3)
        if !isempty(minld)
            ups = gvalues(tm, "ACT_UPS", 5)
            for (k, _) in minld.values
                gassign!(ups, (k..., s, "FX"), gv(minld, k))
            end
            gput!(tm, "ACT_UPS", ups)
        end
    end
    # L73: OPTION CLEAR=TRACKP, RP_UPR<ACT_TIME, RP_UPT<ACT_CSTSD
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    gput!(tm, "RP_UPR", project(gparam_opt(tm.data, "ACT_TIME", 4).keys, (1, 3, 4)))
    gput!(tm, "RP_UPT", project(gparam_opt(tm.data, "ACT_CSTSD", 6).keys, (1, 3, 4, 5)))

    # --- Clean-up (L76-89) ----------------------------------------------------
    # L77-88: LOOP(LASTLL(YEAR), per parameter: OPTION CLEAR=UNCD7; UNCD7(R,LL--ORD(LL),<rest>,'',..) $= (X(R,LL,..) NE 0);
    #           X(R,DATAYEAR,..)$(NOT UNCD7(R,YEAR,<rest>,'',..)) = 0)
    # The groups are the records with a nonzero (not EPS, G12) value in some year (and, for IRE_PRICE, some IE);
    # records at a DATAYEAR outside every group are removed. UNCD7 keeps the last parameter's groups.
    uncd7 = Set{NTuple{7,String}}()
    had_uncd7 = !isempty(gset_opt(tm.data, "UNCD7", 7))
    for (y,) in gset(tm, "LASTLL").keys
        for (name, N, grp) in (("VDA_EMCB", 4, k -> (k[1], t0, k[3], k[4], "", "", "")),
                               ("IRE_PRICE", 8, k -> (k[1], t0, k[3], k[4], k[5], k[6], k[8])),
                               ("ACT_COST", 4, k -> (k[1], t0, k[3], k[4], "", "", "")),
                               ("FLO_DELIV", 6, k -> (k[1], t0, k[3], k[4], k[5], k[6], "")),
                               ("FLO_COST", 6, k -> (k[1], t0, k[3], k[4], k[5], k[6], "")))
            p = gparam_opt(tm.data, name, N)
            uncd7 = Set{NTuple{7,String}}(grp(k) for (k, v) in p.values if v != 0.0 && (k[1],) in reg)
            isempty(p) && continue
            # the test reads UNCD7 at YEAR (the LASTLL element); the groups were stored at LL--ORD(LL)
            drop(k) = (k[1],) in reg && (k[2],) in datayear && !(Base.setindex(grp(k), y, 2) in uncd7)
            vals = Dict{NTuple{N,String},Float64}(k => v for (k, v) in p.values if !drop(k))
            length(vals) == length(p) || gput!(tm, name, vals)
        end
    end
    (had_uncd7 || !isempty(uncd7)) && gput!(tm, "UNCD7", uncd7)
    # L89: NCAP_CEH(R,LL,P) $= VDA_CEH(R,LL,P)
    ceh = gparam_opt(tm.data, "VDA_CEH", 3)
    if !isempty(ceh)
        nc = gvalues(tm, "NCAP_CEH", 3)
        foreach(k -> gassign!(nc, k, gv(ceh, k)), keys(ceh.values))
        gput!(tm, "NCAP_CEH", nc)
    end

    # --- PRC_RESID and NCAP_PASTI (L91-93) -----------------------------------
    # L92: PRC_RESID(R,LL--ORD(LL),P)$((PRC_RESID(R,LL,P)>0)$PRC_RESID(R,LL,P)) = PRC_RESID(R,'0',P)+EPS
    old = gparam(tm, "PRC_RESID")
    resid = copy(old.values)
    for (k, v) in old.values
        (v > 0 && (k[1],) in reg) || continue
        gassign!(resid, (k[1], t0, k[3]), gv(old, (k[1], dflbl, k[3])) + GEPS)
    end
    gput!(tm, "PRC_RESID", resid)
    # L93: NCAP_PASTI(R,PYR_S,P)$PRC_RESID(R,'0',P) = 1
    pyr_s = gset(tm, "PYR_S")
    pasti = gvalues(tm, "NCAP_PASTI", 3)
    for k in keys(resid)
        (k[2] == dflbl && (k[1],) in reg) || continue
        foreach(((y,),) -> gassign!(pasti, (k[1], y, k[3]), 1.0), pyr_s.keys)
    end
    gput!(tm, "NCAP_PASTI", pasti)

    # --- VDA_EMCB, FLO_EMIS and IRE_FLOSUM (L95-107) --------------------------
    # L96: FLO_EMIS(R,LL,P,CG,C,S) $= FLO_EFF(R,LL,P,CG,C,S); L97: OPTION CLEAR=RXX, CLEAR=FLO_EFF
    eff = gparam_opt(tm.data, "FLO_EFF", 6)
    if !isempty(eff)
        emis = gvalues(tm, "FLO_EMIS", 6)
        foreach(k -> gassign!(emis, k, gv(eff, k)), keys(eff.values))
        gput!(tm, "FLO_EMIS", emis)
        gput!(tm, "FLO_EFF", Dict{NTuple{6,String},Float64}())
    end
    # L98: VDA_EMCB(R,YEAR,C,COM)$COM_TMAP(R,'ENV',C) = 0
    tmap = gset(tm, "COM_TMAP")
    emcb = gparam_opt(tm.data, "VDA_EMCB", 4)
    if !isempty(emcb)
        vals = Dict{NTuple{4,String},Float64}(k => v for (k, v) in emcb.values if !((k[1], "ENV", k[3]) in tmap && (k[1],) in reg))
        length(vals) == length(emcb) || (emcb = gput!(tm, "VDA_EMCB", vals))
    end
    # L99: LOOP((R,DATAYEAR,C,COM)$VDA_EMCB(R,DATAYEAR,C,COM),RXX(R,C,COM) = YES)
    # L100: RXX(R,C,COM)$(NOT COM_TMAP(R,'ENV',COM)) = NO
    rxx = Set{NTuple{3,String}}((k[1], k[3], k[4]) for k in keys(emcb.values) if (k[2],) in datayear && (k[1],) in reg)
    filter!(k -> (k[1], "ENV", k[3]) in tmap, rxx)
    # L101: LOOP((TOP(R,P,C,'IN'),RXX(R,C,COM)),FS_EMCB(R,P,COM,C)=YES)
    # L102: FS_EMCB(R,P,COM,C)$TOP(R,P,COM,'IN') = NO
    top = gmembers(tm, "TOP", 4)
    fs = gmembers(tm, "FS_EMCB", 4)
    if !isempty(rxx)
        rxx_by = Dict{NTuple{2,String},Vector{String}}()
        foreach(k -> push!(get!(rxx_by, (k[1], k[2]), String[]), k[3]), rxx)
        for (r, p, c, io) in top
            io == "IN" || continue
            foreach(cm -> push!(fs, (r, p, cm, c)), get(rxx_by, (r, c), String[]))
        end
        filter!(k -> !((k[1], k[2], k[3], "IN") in top), fs)
        gput!(tm, "FS_EMCB", fs)
        # L103: OPTION TRACKPC <= FS_EMCB; TOP(TRACKPC,'OUT') = YES
        foreach(k -> push!(top, (k[1], k[2], k[3], "OUT")), project(fs, (1, 2, 3)))
        gput!(tm, "TOP", top)
    end
    # L104: OPTION CLEAR=RXX, CLEAR=TRACKPC   (both end empty)
    gput!(tm, "RXX", Set{NTuple{3,String}}())
    gput!(tm, "TRACKPC", Set{NTuple{3,String}}())
    # L105: LOOP((R,DATAYEAR,P,CG,C,S)$FLO_EMIS(R,DATAYEAR,P,CG,C,S),RPC_EMIS(R,P,C) = YES)
    rpc_emis = gmembers(tm, "RPC_EMIS", 3)
    for k in keys(gparam_opt(tm.data, "FLO_EMIS", 6).values)
        ((k[2],) in datayear && (k[1],) in reg) && push!(rpc_emis, (k[1], k[3], k[5]))
    end
    gput!(tm, "RPC_EMIS", rpc_emis)
    # L106: RPG_RED(RPC_EMIS(R,P,C),'OUT')$(NOT TOP(R,P,C,'IN')) = YES
    rpg_red = gmembers(tm, "RPG_RED", 4)
    for (r, p, c) in rpc_emis
        (r, p, c, "IN") in top || push!(rpg_red, (r, p, c, "OUT"))
    end
    # L107: LOOP((R,DATAYEAR,P,C,S,IE,COM,IO)$(PRC_MAP(R,'IRE',P)$IRE_FLOSUM(R,DATAYEAR,P,C,S,IE,COM,IO)),RPG_RED(R,P,COM,IO) = YES)
    prc_map = gset(tm, "PRC_MAP")
    for k in keys(gparam_opt(tm.data, "IRE_FLOSUM", 8).values)
        ((k[2],) in datayear && (k[1], "IRE", k[3]) in prc_map && (k[1],) in reg) && push!(rpg_red, (k[1], k[3], k[7], k[8]))
    end
    gput!(tm, "RPG_RED", rpg_red)

    # --- COM_AGG and VDA_FLOP (L109-114) --------------------------------------
    # L110: COM_AGG(R,LL,C,C)$COM_AGG(R,LL,C,C) = 0
    agg = gparam_opt(tm.data, "COM_AGG", 4)
    any(k -> k[3] == k[4], keys(agg.values)) &&
        gput!(tm, "COM_AGG", Dict{NTuple{4,String},Float64}(k => v for (k, v) in agg.values if k[3] != k[4]))
    # L111: VDA_FLOP(R,LL,P,CG,S) $= ACT_FLO(R,LL,P,CG,S)
    act_flo = gparam_opt(tm.data, "ACT_FLO", 5)
    flop = gparam_opt(tm.data, "VDA_FLOP", 5)
    if !isempty(act_flo)
        vals = copy(flop.values)
        foreach(k -> gassign!(vals, k, gv(act_flo, k)), keys(act_flo.values))
        flop = gput!(tm, "VDA_FLOP", vals)
    end
    # L112: KEEP_FLOF(R,P,C)$VDA_FLOP(R,'%DFLBL%',P,C,'ANNUAL') = YES
    keep_flof = gmembers(tm, "KEEP_FLOF", 3)
    for k in keys(flop.values)
        (k[2] == dflbl && k[5] == "ANNUAL" && (k[4],) in com && (k[1],) in reg) && push!(keep_flof, (k[1], k[3], k[4]))
    end
    # L113: $IFI %SHELL%==ANSWER KEEP_FLOF(R,P,C)$PRC_ACTFLO(R,'%DFLBL%',P,C) = YES
    if uppercase(gswitch(tm, "SHELL", "")) == "ANSWER"
        for k in keys(gparam_opt(tm.data, "PRC_ACTFLO", 4).values)
            (k[2] == dflbl && (k[4],) in com && (k[1],) in reg) && push!(keep_flof, (k[1], k[3], k[4]))
        end
    end
    gput!(tm, "KEEP_FLOF", keep_flof)
    # L114: OPTION RP_XRED<ACT_FLO, CLEAR=ACT_FLO
    gput!(tm, "RP_XRED", project(act_flo.keys, (1, 3)))
    isempty(act_flo) || gput!(tm, "ACT_FLO", Dict{NTuple{5,String},Float64}())

    # --- Updatable OFF-ranges (L116-125) ---------------------------------------
    # L117: NCAP_START(R,P)$(NCAP_START(R,P)<=MIYR_BOH)=0
    start = gvalues(tm, "NCAP_START", 2)
    filter!(((k, v),) -> !(v <= miyr_boh), start)
    # L118: RVP(R,LL,P) $= NCAP_BND(R,LL,P,'N')
    bnd = gvalues(tm, "NCAP_BND", 4)
    rvp = gmembers(tm, "RVP", 3)
    for k in keys(bnd)
        (k[4] == "N" && (k[1],) in reg) && push!(rvp, (k[1], k[2], k[3]))
    end
    if !isempty(rvp)                                                  # L119: IF(CARD(RVP), ...
        eotime = parse(Float64, gswitch(tm, "EOTIME", "2200"))       # initsys.mod L36
        # L120: NCAP_BND(RVP,'N')$(NCAP_BND(RVP,'N')>%EOTIME%) = %EOTIME%
        for (r, y, p) in rvp
            get(bnd, (r, y, p, "N"), 0.0) > eotime && gassign!(bnd, (r, y, p, "N"), eotime)
        end
        # L121: NCAP_START(R,P)$((ABS(NCAP_BND(R,'0',P,'N'))>999)$RVP(R,'0',P)) = ABS(NCAP_BND(R,'0',P,'N'))+1
        for (r, y, p) in rvp
            a = abs(get(bnd, (r, dflbl, p, "N"), 0.0))
            (y == dflbl && a > 999) && gassign!(start, (r, p), a + 1)
        end
        # L122: PRC_NOFF(R,P,LL,EOHYEAR)$RVP(R,LL,P) = NO
        eoh = gset(tm, "EOHYEAR")
        noff = filter(k -> !((k[1], k[3], k[2]) in rvp && (k[4],) in eoh), gmembers(tm, "PRC_NOFF", 4))
        # L123: PRC_NOFF(R,P,BOHYEAR(LL),LL+(NCAP_BND(R,LL,P,'N')-YEARVAL(LL)))$RVP(R,LL,P) = YES
        boh = gset(tm, "BOHYEAR")
        pos = Dict(y => i for (i, y) in enumerate(allyear))
        for (r, y, p) in rvp
            (y,) in boh || continue
            d = get(bnd, (r, y, p, "N"), 0.0) - yv(y)
            isinteger(d) || throw(ArgumentError("init_ext.vda L123: lead NCAP_BND-YEARVAL = $d at $((r, y, p)) is not an integer"))
            j = pos[y] + Int(d)
            1 <= j <= length(allyear) && push!(noff, (r, p, y, allyear[j]))   # a lead past either end selects nothing
        end
        gput!(tm, "PRC_NOFF", noff)
    end
    # L124: NCAP_BND(RVP(R,LL,P),L('N')) = MOD(MIN(2,ROUND(MAX(NCAP_BND(RVP,L),-1))),2)$LASTLL(LL)
    #         +(YEARVAL(LL)-1)$(ROUND(MOD(NCAP_BND(RVP,L)-YEARVAL(LL),MAX(1,YEARVAL(LL))))=-1)
    lastll = gset(tm, "LASTLL")
    gr(x) = round(x, RoundNearestTiesAway)
    for (r, y, p) in rvp
        v = get(bnd, (r, y, p, "N"), 0.0)
        x = ((y,) in lastll ? rem(min(2, gr(max(v, -1))), 2) : 0.0) +
            (gr(rem(v - yv(y), max(1, yv(y)))) == -1 ? yv(y) - 1 : 0.0)
        gassign!(bnd, (r, y, p, "N"), x)
    end
    isempty(rvp) || gput!(tm, "NCAP_BND", bnd)
    gput!(tm, "NCAP_START", start)
    # L125: OPTION CLEAR=RVP
    gput!(tm, "RVP", Set{NTuple{3,String}}())

    # --- UC_CLI, UC_DYNBND and UC_ACTBET (L127-135) ----------------------------
    equcrtp_init_ext!(tm)                                             # L128: $BATINCLUDE equcrtp.vda INIT_EXT
    # L130: LOOP(UC_ATTR(R,UC_N,SIDE,UC_GRPTYPE,UC_NAME(TSL)),UC_TSL(R,UC_N,SIDE,TSL)=YES)
    attr = gset_opt(tm.data, "UC_ATTR", 5)
    if !isempty(attr)
        ucname = gset(tm, "UC_NAME")
        uctsl = gmembers(tm, "UC_TSL", 4)
        for k in attr.keys
            ((k[1],) in reg && (k[5],) in ucname && (k[5],) in tslvl) && push!(uctsl, (k[1], k[2], k[3], k[5]))
        end
        gput!(tm, "UC_TSL", uctsl)
    end
    # L131-132: $IF DEFINED UC_ACTBET UC_FLOBET(UC_N,ALL_R,YEAR,P,%PGPRIM%) $= UC_ACTBET(UC_N,ALL_R,YEAR,P);
    #             LOOP((UC_N,R,YEAR,P)$UC_ACTBET(UC_N,R,YEAR,P),UC_GMAP_P(R,UC_N,'ACT',P)=YES)
    actbet = gparam_opt(tm.data, "UC_ACTBET", 4)
    if !isempty(actbet)                                               # DEFINED: has records (G35)
        pg = uppercase(strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"']))
        flobet = gvalues(tm, "UC_FLOBET", 5)
        gmap_p = gmembers(tm, "UC_GMAP_P", 4)
        for k in keys(actbet.values)
            gassign!(flobet, (k..., pg), gv(actbet, k))
            (k[2],) in reg && push!(gmap_p, (k[2], k[1], "ACT", k[4]))
        end
        gput!(tm, "UC_FLOBET", flobet)
        gput!(tm, "UC_GMAP_P", gmap_p)
    end
    # L134-135: $IF DEFINED PRC_REACT / $IFE CARD(GR_PTDF)+CARD(GG_KGF): $SETGLOBAL POWERFLO YES
    # (the TimesModel constructor has already applied it; repeated here where GAMS has it)
    data_switches!(tm)

    # --- Exogenous trade from an earlier run (L137-156) -------------------------
    # L153-156: remove the originally exogenous trade flows (RPC_IREIN holds data only with GDX_IREBND/GDX_IPRIC, refused)
    irein = gset_opt(tm.data, "RPC_IREIN", 5)
    if !isempty(irein)
        out = Set{NTuple{4,String}}((k[1], k[2], k[3], k[4]) for k in irein.keys if k[5] == "OUT")
        pire = gparam_opt(tm.data, "PAR_IRE", 7)
        gput!(tm, "PAR_IRE", Dict{NTuple{7,String},Float64}(k => v for (k, v) in pire.values if !((k[1], k[4], k[5], k[7]) in out)))
        pipr = gparam_opt(tm.data, "PAR_IPRIC", 6)
        gput!(tm, "PAR_IPRIC", Dict{NTuple{6,String},Float64}(k => v for (k, v) in pipr.values if !((k[1], k[3], k[4], k[6]) in out)))
        gput!(tm, "RPC_IREIN", Set{NTuple{5,String}}(k for k in irein.keys if k[5] != "OUT"))
    end
    return tm
end
