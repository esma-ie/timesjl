# M1.3 change 55: resloadc.vda, the residual load curve constraints of the VDA extension, included
# whenever GR_VARGEN is DEFINED (G35): the default label from prep_ext.vda L38 (the preparation), COEF
# from ppm_ext.vda L12, EQUA from equ_ext.vda L102 (the equations, which mod_ext.vda L48-49 put in the
# model). The compile-time statements of L11-16 (the sets RLDC, ITEM, RLDBD and GR_TP's INF) are in
# every dump from the input on (the DD reader compiles them, M1.4).
#
# GR_VARGEN(R,S,ITEM,BD) gives the variations of the residual load (RL-DISP) and of each type of
# non-dispatchable generation (RL-WIND, RL-SOL, ...): FX constant, LO and UP proportional to capacity
# and to on-line capacity. GR_GENMAP maps processes to the types, GR_THMIN gives thermal minimums, and
# RL-TP the first and last years of the constraints.
#
# Two quirks of v4.9.7 are translated as written: EQ_RL_STCAP and EQ_RL_THMIN read VAR_RLD at the
# label 'RL_THMIN' (an underscore) beside 'RL-THMIN', two different columns (GAMS names the first
# with quotes: no ITEM element is spelled so).

"""
    resloadc_prep!(st, T) -> st

resloadc.vda, the default label (prep_ext.vda L38):

    GR_RLDC(R,'0') \$=SUM((S,RLDC,BD)\$GR_VARGEN(R,S,RLDC,BD),1);                                    (L18)
    GR_TP(R,BD)\$=GR_VARGEN(R,'ANNUAL','RL-TP',BD); GR_TP(R,BD)\$=GR_TP(R,'FX'); GR_VARGEN(R,S,'RL-TP',BD)=0;   (L19)
    OPTION CLEAR=UNCD1; GR_RLDC(R,T(TT+1))\$((YEARVAL(T)>=GR_TP(R,'LO'))\$(YEARVAL(T)<=GR_TP(R,'UP'))) \$= GR_RLDC(R,'0');   (L20)
    LOOP((R,S,ITEM,BD)\$GR_VARGEN(R,S,ITEM,BD),UNCD1(ITEM)=YES); RLDC(UNCD1) = YES;                 (L21)
    RLDBD(BD)\$=NOT RLDC('RL-THMIN'); GR_VARGEN(R,S,'RL-THMIN',BD) = 0;                            (L22)
    \$BATINCLUDE fillparm GR_THMIN R P ",'0','0','0','0','0'" T RTP(R,T,P) 'GE 0'                  (L23)

RLDC holds only RL-DISP at L18 (the compile-time data of L11); T(TT+1) is every milestone but the
first; GR_TP(R,'UP') is INF from the compile-time data of L16.

GAMS: resloadc.vda L8-24, v4.9.7.
"""
function resloadc_prep!(st, T)
    tm = st.tm
    hasdata(tm, "GR_VARGEN", 4) || return st
    d = tm.data
    regs = [k[1] for k in gset(tm, "REG").keys]
    bds = [k[1] for k in gset(tm, "BD").keys]
    vargen = gvalues(tm, "GR_VARGEN", 4)
    rldc = gmembers(tm, "RLDC", 1)
    # L18
    gr_rldc = gmembers(tm, "GR_RLDC", 2)
    for r in regs
        any(k -> k[1] == r && (k[3],) in rldc, keys(vargen)) && push!(gr_rldc, (r, "0"))
    end
    # L19
    gr_tp = gvalues(tm, "GR_TP", 2)
    for (k, x) in vargen
        (k[1] in regs && k[2] == "ANNUAL" && k[3] == "RL-TP" && k[4] in bds) && gassign!(gr_tp, (k[1], k[4]), GNum(x, x == 0))
    end
    for r in regs
        fx = get(gr_tp, (r, "FX"), nothing)
        fx === nothing || foreach(bd -> gassign!(gr_tp, (r, bd), GNum(fx, fx == 0)), bds)
    end
    filter!(((k, _),) -> !(k[1] in regs && k[3] == "RL-TP"), vargen)
    # L20
    yv = gparam(tm, "YEARVAL")
    for r in regs
        (r, "0") in gr_rldc || continue
        lo, up = get(gr_tp, (r, "LO"), 0.0), get(gr_tp, (r, "UP"), 0.0)
        for t in T[2:end]
            y = gv(yv, (t,)).v
            (y >= lo && y <= up) && push!(gr_rldc, (r, t))
        end
    end
    # L21
    uncd1 = Set{Tuple{String}}((k[3],) for k in keys(vargen))
    union!(rldc, uncd1)
    # L22
    rldbd = gmembers(tm, "RLDBD", 1)
    ("RL-THMIN",) in rldc || foreach(bd -> push!(rldbd, (bd,)), bds)
    filter!(((k, _),) -> !(k[1] in regs && k[3] == "RL-THMIN"), vargen)
    gput!(tm, "GR_VARGEN", vargen); gput!(tm, "GR_RLDC", gr_rldc); gput!(tm, "GR_TP", gr_tp)
    gput!(tm, "UNCD1", uncd1); gput!(tm, "RLDC", rldc); gput!(tm, "RLDBD", rldbd)
    # L23
    rtp = gset(tm, "RTP")
    fillparm!(st, "GR_THMIN", "R", "P", pd(",'0','0','0','0','0'"), T, k -> (k[1], k[2], k[3]) in rtp, (x, k) -> x >= 0)
    return st
end

"""
    resloadc_coef!(tm) -> tm

resloadc.vda COEF (ppm_ext.vda L12), the preprocessing of the generation types, the thermal minimums
and the variations:

    TRACKPC(RPC_PG(RP_STD(R,P),C))\$(TOP(R,P,C,'OUT')\$NRG_TMAP(R,'ELC',C)) = YES;                       (L29)
    OPTION TRACKP<TRACKPC; GR_THMIN(R,LL,P)\$(NOT TRACKP(R,P))=0;                                    (L30)
    GR_RLGT(TRACKP(RP),RLDC)\$=GR_GENMAP(RP,RLDC);                                                   (L32)
    OPTION RP_UPL < ACT_UPS, RP_PRC < GR_THMIN;                                                      (L33)
    GR_RLGT(RP_PRC(RP),'RL-DISP')=YES;                                                               (L34)
    LOOP(RLDC\$(NOT SAMEAS('RL-NDIS',RLDC)),GR_RLGT(RP,'RL-NDIS')\$GR_RLGT(RP,RLDC)=NO);               (L35)
    RP_PRC(RP)\$GR_RLGT(RP,'RL-DISP')\$=RP_UPL(RP,'FX');                                               (L36)
    GR_RLGT(RP_PRC(RP),'RL-THMIN')=YES;                                                              (L37)
    GR_GENMAP(RP_PRC,'RL-DISP')=NOT RLDC('RL-THMIN'); OPTION CLEAR=RP_PRC;                           (L38)
    RP_PRC(TRACKP(R,P))\$SUM(TOP(R,P,C,'IN')\$NRG_TMAP(R,'ELC',C),1) = YES;                             (L39)
    RP_PRC(CHP)=NO; TRACKP(RP_PRC)=NO;                                                              (L40)
    GR_RLGT(TRACKP(RP),'RL-NDIS')\$(NOT SUM(RLDC\$GR_RLGT(RP,RLDC),1)) = YES;                          (L41)
    OPTION CLEAR=TRACKP,CLEAR=TRACKPC,CLEAR=RP_PRC;                                                 (L42)
    GR_THBND(RTP,'FX')\$((GR_THMIN(RTP)<0)\$GR_THMIN(RTP)) = -GR_THMIN(RTP);                           (L44)
    GR_THBND(RTP,'LO')\$((GR_THMIN(RTP)<1)\$GR_THMIN(RTP)) = MAX(0,GR_THMIN(RTP)+1-1);                 (L45)
    GR_THBND(RTP,'UP')\$((GR_THMIN(RTP)>=1)\$GR_THMIN(RTP)) = 1/GR_THMIN(RTP);                        (L46)
    FOR(Z=CARD(TSLVL)-2 DOWNTO 0, LOOP((ANNUAL(TS(TSL-Z)),TS_GROUP(R,TSL,SL)),                        (L47-49)
      GR_VARGEN(FINEST(R,S),RLDC,BDNEQ(BD))\$((NOT GR_VARGEN(R,S,RLDC,BD))\$RS_BELOW(R,SL,S)) \$= GR_VARGEN(R,SL,RLDC,BD)));
    GR_RLDC(R,'0')\$GR_VARGEN(R,'ANNUAL','RL-DISP','FX') = NO;                                        (L51)
    LOOP(R\$GR_RLDC(R,'0'), RHS_COMBAL(RTCS_VARC(GR_RLDC(R,T),C,S))\$(COM_LIM(R,C,'LO')\$NRG_TMAP(R,'ELC',C)) = YES;
      RCS_COMBAL(RHS_COMBAL(GR_RLDC(R,T),C,S),'FX')\$NRG_TMAP(R,'ELC',C) = YES);                        (L52-55)
    GR_VARGEN(R,ANNUAL,RLDC,'FX') = 1-DIAG('RL-DISP',RLDC);                                           (L56)
    LOOP(RLDBD(BDNEQ(BD)),ACT_UPS(RTP,ANNUAL(S),'FX')\$GR_THBND(RTP,BD)=MAX(GR_THBND(RTP,BD),ACT_UPS(RTP,S,'FX'));
      GR_THBND(R,LL,P,BD)\$RP_UPL(R,P,'FX')=0)                                                         (L58-59)
    IF(RLDBD('FX'),FLO_BND(RTP(R,T,P),C,S,'LO')\$(RPC_PG(R,P,C)\$NRG_TMAP(R,'ELC',C)\$PRC_TS(R,P,S)\$GR_THBND(RTP,'FX')) =
       MAX(FLO_BND(RTP,C,S,'LO'),GR_THBND(RTP,'FX')*PRC_CAPACT(R,P)*G_YRFR(R,S)));                     (L60-61)
    OPTION GR_THMIN < GR_THBND;                                                                      (L62)

`ANNUAL(TS(TSL-Z))` holds for the level Z positions after ANNUAL, so the variations are levelled from
WEEKLY, then SEASON, then ANNUAL down to the finest timeslices without a value of their own (BDNEQ:
LO and UP). `OPTION GR_THMIN < GR_THBND` counts the bound types of each (R,LL,P) (as coef_shp.mod L53).

GAMS: resloadc.vda L27-63, v4.9.7.
"""
function resloadc_coef!(tm)
    Reference.has_symbol(tm.data.dump, "GR_RLGT") || return tm      # declared by L14 when included
    d = tm.data
    # labels the code names itself, which the dump it starts from may not hold (G36)
    foreach(l -> register_uel!(d, l), ("RL-NDIS", "RL-DISP", "RL-THMIN", "FX", "LO", "UP"))
    S(n) = gset(tm, n)
    regs = [k[1] for k in S("REG").keys]
    rldc = gmembers(tm, "RLDC", 1)
    nrg_elc = Set((k[1], k[3]) for k in S("NRG_TMAP").keys if k[2] == "ELC")      # NRG_TMAP(R,'ELC',C)
    top = S("TOP").members
    rp_std, rp_set = S("RP_STD").members, S("RP").members
    # L29-30
    trackpc = gmembers(tm, "TRACKPC", 3)
    for (r, p, c) in S("RPC_PG").keys
        ((r, p) in rp_std && (r, p, c, "OUT") in top && (r, c) in nrg_elc) && push!(trackpc, (r, p, c))
    end
    trackp = Set((k[1], k[2]) for k in trackpc)
    thmin = gvalues(tm, "GR_THMIN", 3)
    filter!(((k, _),) -> (k[1], k[3]) in trackp, thmin)
    # L32
    genmap = gvalues(tm, "GR_GENMAP", 3)
    gr_rlgt = gmembers(tm, "GR_RLGT", 3)
    for (r, p) in trackp, (item,) in rldc
        haskey(genmap, (r, p, item)) && push!(gr_rlgt, (r, p, item))
    end
    # L33
    act_ups = gvalues(tm, "ACT_UPS", 5)
    rp_upl = Set((k[1], k[3], k[5]) for k in keys(act_ups))
    rp_prc = Set((k[1], k[3]) for k in keys(thmin))
    # L34-35
    foreach(rp -> push!(gr_rlgt, (rp..., "RL-DISP")), rp_prc)
    for (item,) in rldc
        item == "RL-NDIS" && continue
        for (r, p) in rp_set
            (r, p, item) in gr_rlgt && delete!(gr_rlgt, (r, p, "RL-NDIS"))
        end
    end
    # L36-38
    for (r, p) in rp_set
        ((r, p, "RL-DISP") in gr_rlgt && (r, p, "FX") in rp_upl) && push!(rp_prc, (r, p))
    end
    foreach(rp -> push!(gr_rlgt, (rp..., "RL-THMIN")), rp_prc)
    gm = ("RL-THMIN",) in rldc ? GZERO : GNum(1.0)
    foreach(rp -> gassign!(genmap, (rp..., "RL-DISP"), gm), rp_prc)
    # L39-42
    rp_prc = Set((r, p) for (r, p) in trackp if any(k -> k[1] == r && k[2] == p && k[4] == "IN" && (r, k[3]) in nrg_elc, top))
    setdiff!(rp_prc, gset_opt(d, "CHP", 2).members)
    setdiff!(trackp, rp_prc)
    for (r, p) in trackp
        any(k -> (r, p, k[1]) in gr_rlgt, rldc) || push!(gr_rlgt, (r, p, "RL-NDIS"))
    end
    gput!(tm, "TRACKP", Set{NTuple{2,String}}()); gput!(tm, "TRACKPC", Set{NTuple{3,String}}())
    gput!(tm, "RP_PRC", Set{NTuple{2,String}}())
    # L44-46
    rtp = S("RTP")
    thbnd = gvalues(tm, "GR_THBND", 4)
    for (r, v, p) in rtp.keys
        x = get(thmin, (r, v, p), nothing)
        x === nothing && continue
        x < 0 && gassign!(thbnd, (r, v, p, "FX"), GNum(-x))
        x < 1 && gassign!(thbnd, (r, v, p, "LO"), GNum(max(0.0, x + 1 - 1)))
        x >= 1 && x != 0 && gassign!(thbnd, (r, v, p, "UP"), GNum(1 / x))
    end
    # L47-49: levelling of the variations
    vargen = gvalues(tm, "GR_VARGEN", 4)
    tslvl = [k[1] for k in S("TSLVL").keys]
    finest, rs_below = S("FINEST").members, S("RS_BELOW").members
    group_of = indexby(S("TS_GROUP"), (2,))                                   # tsl -> TS_GROUP(r,tsl,sl)
    below_of = Dict{NTuple{2,String},Vector{String}}()                       # (r,sl) -> S below
    foreach(k -> push!(get!(below_of, (k[1], k[2]), String[]), k[3]), S("RS_BELOW").keys)
    for z in (length(tslvl) - 2):-1:0
        tsl = tslvl[1 + z]                                                    # TSL-Z is ANNUAL
        for (r, _, sl) in get(group_of, (tsl,), NTuple{3,String}[])
            for s in get(below_of, (r, sl), String[])
                (r, s) in finest || continue
                for (item,) in rldc, bd in ("LO", "UP")
                    haskey(vargen, (r, s, item, bd)) && continue
                    x = get(vargen, (r, sl, item, bd), nothing)
                    x === nothing || (vargen[(r, s, item, bd)] = x)
                end
            end
        end
    end
    # the FOR loop leaves Z one step past its last value: -1 after DOWNTO 0 (GAMS FOR semantics)
    z0 = length(tslvl) - 2
    gput_scalar!(tm, "Z", z0 >= 0 ? -1.0 : Float64(z0))
    # L51-55
    gr_rldc = gmembers(tm, "GR_RLDC", 2)
    for r in regs
        haskey(vargen, (r, "ANNUAL", "RL-DISP", "FX")) && delete!(gr_rldc, (r, "0"))
    end
    rhs_combal, rcs_combal = gmembers(tm, "RHS_COMBAL", 4), gmembers(tm, "RCS_COMBAL", 5)
    com_lim = S("COM_LIM").members
    for r in regs
        (r, "0") in gr_rldc || continue
        for (rr, t, c, s) in S("RTCS_VARC").keys
            (rr == r && (r, t) in gr_rldc && (r, c, "LO") in com_lim && (r, c) in nrg_elc) && push!(rhs_combal, (r, t, c, s))
        end
        for (rr, t, c, s) in collect(rhs_combal)
            (rr == r && (r, t) in gr_rldc && (r, c) in nrg_elc) && push!(rcs_combal, (r, t, c, s, "FX"))
        end
    end
    # L56
    for r in regs, (item,) in rldc
        gassign!(vargen, (r, "ANNUAL", item, "FX"), GNum(item == "RL-DISP" ? 0.0 : 1.0))
    end
    # L58-59
    rldbd = gmembers(tm, "RLDBD", 1)
    for bd in ("LO", "UP")
        (bd,) in rldbd || continue
        for (k, x) in collect(thbnd)
            k[4] == bd || continue
            (k[1], k[2], k[3]) in rtp || continue
            ku = (k[1], k[2], k[3], "ANNUAL", "FX")
            gassign!(act_ups, ku, gmax(GNum(x, x == 0), gv(act_ups, ku)))
        end
        filter!(((k, _),) -> !(k[4] == bd && (k[1], k[3], "FX") in rp_upl), thbnd)
    end
    gput!(tm, "ACT_UPS", act_ups)
    # L60-61
    if ("FX",) in rldbd
        flo_bnd = gvalues(tm, "FLO_BND", 6)
        capact, g_yrfr = gparam(tm, "PRC_CAPACT"), gparam(tm, "G_YRFR")
        prc_ts_of = indexby(S("PRC_TS"), (1, 2))
        for (r, p, c) in S("RPC_PG").keys
            (r, c) in nrg_elc || continue
            for (rr, t, pp) in rtp.keys
                (rr == r && pp == p) || continue
                fx = get(thbnd, (r, t, p, "FX"), nothing)
                fx === nothing && continue
                for (_, _, s) in get(prc_ts_of, (r, p), NTuple{3,String}[])
                    k = (r, t, p, c, s, "LO")
                    gassign!(flo_bnd, k, gmax(gv(flo_bnd, k), GNum(fx) * gv(capact, (r, p)) * gv(g_yrfr, (r, s))))
                end
            end
        end
        gput!(tm, "FLO_BND", flo_bnd)
    end
    # L62: OPTION GR_THMIN < GR_THBND (a count per R,LL,P)
    thmin = Dict{NTuple{3,String},Float64}()
    foreach(k -> (thmin[(k[1], k[2], k[3])] = get(thmin, (k[1], k[2], k[3]), 0.0) + 1), keys(thbnd))
    gput!(tm, "GR_THMIN", thmin); gput!(tm, "GR_THBND", thbnd); gput!(tm, "GR_RLGT", gr_rlgt)
    gput!(tm, "GR_GENMAP", genmap); gput!(tm, "GR_VARGEN", vargen); gput!(tm, "GR_RLDC", gr_rldc)
    gput!(tm, "RHS_COMBAL", rhs_combal); gput!(tm, "RCS_COMBAL", rcs_combal)
    gput!(tm, "RP_UPL", rp_upl)
    return tm
end

"""
    resloadc_equa!(tm) -> tm

resloadc.vda EQUA, its data statement (equ_ext.vda L102): `RPS_UPS(R,P,S)\$SUM(RTP(R,V,P)\$GR_THBND(RTP,'LO'),1)=NO`
(L67): no cycling for a process whose thermal minimum is a share of its nominal capacity. The bound
`VAR_RLD.LO(R,T,S,'RL-DISP') = -INF` (L69) is `bnd_rld!`.

GAMS: resloadc.vda L65-69, v4.9.7.
"""
function resloadc_equa!(tm)
    Reference.has_symbol(tm.data.dump, "GR_THBND") || return tm
    thbnd = gparam(tm, "GR_THBND")
    lo = Set((k[1], k[3]) for k in thbnd.keys if k[4] == "LO" && (k[1], k[2], k[3]) in gset(tm, "RTP"))
    isempty(lo) && return tm
    rps_ups = gmembers(tm, "RPS_UPS", 3)
    filter!(k -> !((k[1], k[2]) in lo), rps_ups)
    gput!(tm, "RPS_UPS", rps_ups)
    return tm
end

"""
    bnd_rld!(bt, tm) -> bt

resloadc.vda L69: `VAR_RLD.LO(R,T,S,'RL-DISP') = -INF`, for the columns the equations created.

GAMS: resloadc.vda L69, v4.9.7.
"""
function bnd_rld!(bt, tm)
    var = vartag(tm, "VAR_RLD")       # %VAS%_RLD.LO(R,T,S,'RL-DISP'%SOW%), %VAS% being %VAR% (equ_ext.vda L73): every SOW
    haskey(tm.vars.families, var) || return bt
    recs = get!(() -> Dict{Tuple,Tuple{Float64,Float64}}(), bt.recs, var)
    for k in tm.vars.families[var].keys
        k[4] == "RL-DISP" && (recs[k] = (-Inf, Inf))
    end
    return bt
end

"""
    eq_rl!(tm) -> Int

The residual load curve equations of resloadc.vda EQUA (equ_ext.vda L102), for each region and period
of GR_RLDC(R,T) and each finest timeslice S:

    EQ_RL_LOAD(GR_RLDC(R,T),S)\$FINEST(R,S)..                                                       (L72-88)
      SUM(TOP(R,P,C,'OUT')\$(NRG_TMAP(R,'ELC',C)\$GR_GENMAP(R,P,'RL-DISP')),
        SUM((RTP_VINTYR(R,V,T,P),RTPCS_VARF(R,T,P,C,TS))\$RS_FR(R,S,TS), [cal_red C COM TS P T] * RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS)))) +
      SUM(RLDC('RL-THMIN'),VAR_RLD(R,T,S,RLDC)*G_YRFR(R,S)) -
      SUM(TOP(RPC_STG(R,P,C),IO)\$NRG_TMAP(R,'ELC',C),
        SUM((RTP_VINTYR(R,V,T,P),RPCS_VAR(R,P,C,TS))\$RS_FR(R,S,TS),
         (VAR_SIN(R,V,T,P,C,TS)\$IPS(IO)-VAR_SOUT(R,V,T,P,C,TS)*STG_EFF(R,V,P)\$(NOT IPS(IO)))*RS_FR(R,S,TS))) -
      SUM(RHS_COMBAL(R,T,C,TS)\$(RS_FR(R,S,TS)\$NRG_TMAP(R,'ELC',C)\$GR_RLDC(R,'0')),
        (VAR_COMNET(R,T,C,TS)/COM_IE(R,T,C,TS)*RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS)))\$(NOT SUM(COM\$COM_AGG(R,T,C,COM),1)))
      =E= VAR_RLD(R,T,S,'RL-DISP')*G_YRFR(R,S);
    EQ_RL_NDIS(GR_RLDC(R,T),S,RLDC)\$(FINEST(R,S)\$GR_VARGEN(R,'ANNUAL',RLDC,'FX'))..                   (L92-97)
      SUM(TOP(R,P,C,'OUT')\$(NRG_TMAP(R,'ELC',C)\$GR_RLGT(R,P,RLDC)), [as the production of EQ_RL_LOAD])
      =E= VAR_RLD(R,T,S,RLDC)*G_YRFR(R,S);
    EQ_RL_STCAP(GR_RLDC(R,T),S)\$FINEST(R,S)..                                                     (L101-116)
      SUM(TOP(RPC_STG(PRC_CAP(R,P),C),'OUT')\$(PRC_TS(R,P,S)\$NRG_TMAP(R,'ELC',C)), PRC_CAPACT(R,P) * RS_STGPRD(R,S) *
        SUM(RTP_CPTYR(R,V,T,P), COEF_CPT(R,V,T,P) * PRC_ACTFLO(R,V,P,C) *
          SMIN(TS_MAP(R,TS,S)\$COEF_AF(R,V,T,P,TS,'UP'),COEF_AF(R,V,T,P,TS,'UP') / RS_FR(R,S,TS) *
            PROD(TS_GROUP(R,TSL,TS)\$RPS_CAFLAC(R,P,TS,'UP'), 1 / RS_STGPRD(R,S) / STG_EFF(R,V,P) * [AFCS(C,TS)])) *
          (VAR_NCAP(R,V,P)\$MILESTONYR(V) + NCAP_PASTI(R,V,P)\$PASTYEAR(V)%RCAPSUB%)))
      =G= VAR_RLD(R,T,S,'RL_THMIN') - VAR_RLD(R,T,S,'RL-DISP') +
          SUM((RLDC,BDNEQ(BD))\$(DIAG('RL-DISP',RLDC)=DIAG('LO',BD)), VAR_RLD(R,T,S,RLDC) * GR_VARGEN(R,S,RLDC,BD));
    EQ_RL_PKCAP(GR_RLDC(R,T),S)\$FINEST(R,S)..                                                     (L120-138)
      SUM(GR_RLGT(PRC_CAP(R,P),'RL-DISP'), PRC_CAPACT(R,P) *
        SUM(V\$COEF_CPT(R,V,T,P), COEF_CPT(R,V,T,P) * SMAX(RPC_PG(R,P,C)\$NRG_TMAP(R,'ELC',C),PRC_ACTFLO(R,V,P,C)) *
          SUM(PRC_TS(R,P,TS)\$RS_FR(R,S,TS),COEF_AF(R,V,T,P,S,'UP')) * (VAR_NCAP(R,V,P)\$TT(V) + NCAP_PASTI(R,V,P)\$PYR(V)%RCAPSUB%))) +
      SUM(TOP(RPC_STG(PRC_CAP(R,P),C),'OUT')\$(PRC_TS(R,P,S)\$NRG_TMAP(R,'ELC',C)), PRC_CAPACT(R,P) * RS_STGPRD(R,S) *
        SUM(RTP_CPTYR(R,V,T,P), COEF_CPT(R,V,T,P) * COEF_AF(R,V,T,P,S,'UP') * PRC_ACTFLO(R,V,P,C) * STG_EFF(R,V,P) *
          PROD(L('N'), PROD(TS_GROUP(R,TSL,S)\$RPS_CAFLAC(R,P,S,'UP'), 1 / RS_STGPRD(R,S) / STG_EFF(R,V,P) * [AFCS(C,S)])) *
          (VAR_NCAP(R,V,P)\$TT(V) + NCAP_PASTI(R,V,P)\$PYR(V)%RCAPSUB%)))
      =G= VAR_RLD(R,T,S,'RL-DISP') +
          SUM((RLDC,BDNEQ(BD))\$(DIAG('RL-DISP',RLDC)=DIAG('UP',BD)), VAR_RLD(R,T,S,RLDC) * GR_VARGEN(R,S,RLDC,BD));
    EQ_RL_THMIN(GR_RLDC(R,T),TS,BDNEQ)\$((BDLOX(BDNEQ)+RLDC('RL-THMIN'))\$FINEST(R,TS))..               (L142-153)
      VAR_RLD(R,T,TS,'RL_THMIN')*BDSIG(BDNEQ) + VAR_RLD(R,T,TS,'RL-THMIN')*BDUPX(BDNEQ)
      =G=
      SUM(GR_RLGT(PRC_CAP(R,P),'RL-THMIN'), PRC_CAPACT(R,P) * (GR_THBND(R,T,P,'FX') +
        SUM((RTP_VINTYR(R,V,T,P),PRC_TS(R,P,S))\$RS_FR(R,TS,S),SMAX(RPC_PG(R,P,C)\$NRG_TMAP(R,'ELC',C),PRC_ACTFLO(R,V,P,C)) *
          (SUM(BD\$BDNEQ(BD),GR_THBND(R,T,P,BD))+SUM(TS_ANN(S,SL),ACT_UPS(R,V,P,SL,'FX'))\$(NOT GR_THMIN(R,T,P))) *
          (SUM(MODLYEAR(K)\$(COEF_CPT(R,K,T,P)\$(DIAG(V,K)>=1\$PRC_VINT(R,P))),COEF_CPT(R,MODLYEAR,T,P) *
            (VAR_NCAP(R,K,P)\$TT(K)+NCAP_PASTI(R,K,P)\$PYR(K)%RCAPSBM%))%UPSCAPS%))))\$BDLOX(BDNEQ);

[AFCS(C,TS)] is `NCAP_AFCS(R,V,P,C,TS)+PROD(COM_TMAP(R,COM_TYPE(CG),C)\$NCAP_AFCS(R,V,P,CG,TS),NCAP_AFCS(R,V,P,CG,TS))\$(NOT NCAP_AFCS(R,V,P,C,TS))`.
SMIN over no element is +INF in GAMS; a storage without a COEF_AF 'UP' raises instead. `\$` binds
before `>=` (G13): `DIAG(V,K)>=1\$PRC_VINT(R,P)` is K = V for a vintaged process and every K otherwise.
%RCAPSUB%/%RCAPSBM% take off the capacity retired early (`rcapsub!`), %UPSCAPS% the off-line capacity
of dispatching (VAR_UPS 'N' at the timeslices above S with RPS_UPS, coef_ext.vda L30). 'RL_THMIN'
(underscore) is its own column (see the file header). Returns the number of rows.

The SOW tags (sow_tags.jl): every row is `%EQ%_RL_x(... %SWT%)` (L72, L92,
L101, L120, L142) and every term `%VAR%_X(... %SOW%)`, but for the capacity:
`%VARV%_NCAP(R,V,P %SWS%)` (L109, L125, L132; `at = v`) with %RCAPSUB%, and
`%VARM%_NCAP(R,K,P %SWS%)` (L154; `at = k`) with %RCAPSBM%.

GAMS: resloadc.vda L72-153, v4.9.7.
"""
function eq_rl!(tm::TimesModel)
    Reference.has_symbol(tm.data.dump, "GR_RLGT") || return 0
    d = tm.data
    gr_rldc = gset(tm, "GR_RLDC")
    isempty(gr_rldc) && return 0
    register_uel!(d, "RL_THMIN")
    S(n) = gset(tm, n)
    P(n) = gparam(tm, n)
    one = GNum(1.0)
    no3, no4, no5 = NTuple{3,String}[], NTuple{4,String}[], NTuple{5,String}[]
    rldc = [k[1] for k in S("RLDC").keys]
    nrg_elc = Set((k[1], k[3]) for k in S("NRG_TMAP").keys if k[2] == "ELC")
    top = S("TOP")
    out_of_r = Dict{String,Vector{NTuple{2,String}}}()                   # r -> (p,c) of TOP OUT
    foreach(k -> k[4] == "OUT" && push!(get!(out_of_r, k[1], NTuple{2,String}[]), (k[2], k[3])), top.keys)
    genmap, gr_rlgt = P("GR_GENMAP"), S("GR_RLGT")
    vint_of = indexby(S("RTP_VINTYR"), (1, 3, 4))                        # (r,t,p) -> RTP_VINTYR(r,v,t,p)
    varf_of = indexby(S("RTPCS_VARF"), (1, 2, 3, 4))                     # (r,t,p,c) -> RTPCS_VARF(r,t,p,c,ts)
    rpcs_of = indexby(S("RPCS_VAR"), (1, 2, 3))                          # (r,p,c) -> RPCS_VAR(r,p,c,ts)
    rs_fr, rtcs_fr, g_yrfr = P("RS_FR"), P("RTCS_FR"), P("G_YRFR")
    rpc_stg, stg_eff, ips = S("RPC_STG"), P("STG_EFF"), S("IPS")
    combal_of = indexby(S("RHS_COMBAL"), (1, 2))                         # (r,t) -> RHS_COMBAL(r,t,c,ts)
    com_ie = P("COM_IE")
    agg = Set((k[1], k[2], k[3]) for k in P("COM_AGG").keys)            # COM_AGG(R,T,C,COM)
    vargen = P("GR_VARGEN")
    prc_cap, prc_ts, capact = S("PRC_CAP"), S("PRC_TS"), P("PRC_CAPACT")
    ts_of_rp = indexby(prc_ts, (1, 2))                                   # (r,p) -> PRC_TS(r,p,s)
    rs_stgprd, coef_cpt, actflo = P("RS_STGPRD"), P("COEF_CPT"), P("PRC_ACTFLO")
    coef_af, ncap_afcs, rps_caflac = P("COEF_AF"), P("NCAP_AFCS"), S("RPS_CAFLAC")
    ts_group_of = indexby(S("TS_GROUP"), (1, 3))                         # (r,ts) -> TS_GROUP(r,tsl,ts)
    tsmap_to = indexby(S("TS_MAP"), (1, 3))                              # (r,s) -> TS_MAP(r,ts,s)
    cptyr_of = indexby(S("RTP_CPTYR"), (1, 3, 4))                        # (r,t,p) -> RTP_CPTYR(r,v,t,p)
    cpt_of = indexby(coef_cpt, (1, 3, 4))                                # (r,t,p) -> COEF_CPT(r,v,t,p)
    com_tmap_of = indexby(S("COM_TMAP"), (1, 3))                         # (r,c) -> COM_TMAP(r,type,c)
    com_type = S("COM_TYPE")
    milestonyr, pastyear, pyr, modlyear = S("MILESTONYR"), S("PASTYEAR"), S("PYR"), S("MODLYEAR")
    pasti = P("NCAP_PASTI")
    pg_of = indexby(S("RPC_PG"), (1, 2))                                 # (r,p) -> RPC_PG(r,p,c)
    thbnd, thmin, act_ups = P("GR_THBND"), P("GR_THMIN"), P("ACT_UPS")
    ts_ann_of = indexby(S("TS_ANN"), (1,))                               # s -> TS_ANN(s,sl)
    prc_vint, bdsig = S("PRC_VINT"), P("BDSIG")
    rps_ups = gset_opt(d, "RPS_UPS", 3)
    tx = eq_periods(tm)
    # SMAX(RPC_PG(R,P,C)$NRG_TMAP(R,'ELC',C),PRC_ACTFLO(R,V,P,C)); -INF over no element
    function smaxflo(r, v, p)
        m = nothing
        for (_, _, c) in get(pg_of, (r, p), no3)
            (r, c) in nrg_elc || continue
            x = gv(actflo, (r, v, p, c))
            m = m === nothing ? x : gmax(m, x)
        end
        return m === nothing ? GNum(-Inf) : m
    end
    # [AFCS(C,TS)]
    function afcs(r, v, p, c, ts)
        haskey(ncap_afcs.values, (r, v, p, c, ts)) && return gv(ncap_afcs, (r, v, p, c, ts))
        pr = one
        for (_, cg, _) in get(com_tmap_of, (r, c), no3)
            ((cg,) in com_type && haskey(ncap_afcs.values, (r, v, p, cg, ts))) || continue
            pr = pr * gv(ncap_afcs, (r, v, p, cg, ts))
        end
        return pr
    end
    # PROD(TS_GROUP(R,TSL,TS)$RPS_CAFLAC(R,P,TS,'UP'), 1/RS_STGPRD(R,S)/STG_EFF(R,V,P)*[AFCS(C,TS)])
    function cafprod(r, v, p, c, s, ts)
        pr = one
        (r, p, ts, "UP") in rps_caflac || return pr
        for _ in get(ts_group_of, (r, ts), no3)
            pr = pr * (one / gv(rs_stgprd, (r, s)) / gv(stg_eff, (r, v, p)) * afcs(r, v, p, c, ts))
        end
        return pr
    end
    function capterm!(e, k, r, v, t, p, ms, ps)
        (v,) in ms && addterm!(e, k, tm, "VAR_NCAP", r, v, p; at=v)   # %VARV%_NCAP(R,V,P %SWS%) (L109, L125, L132)
        (v,) in ps && addconst!(e, k * gv(pasti, (r, v, p)))
        rcapsub!(e, k, tm, r, v, t, p)
    end
    # the production of the ELC outputs of the processes for which `ok(p)` holds
    function production!(e, r, t, s, ok)
        for (p, c) in get(out_of_r, r, NTuple{2,String}[])
            ((r, c) in nrg_elc && ok(p)) || continue
            for (_, v, _, _) in get(vint_of, (r, t, p), no4), (_, _, _, _, ts) in get(varf_of, (r, t, p, c), no5)
                haskey(rs_fr.values, (r, s, ts)) || continue
                cal_nored!(e, tm, gv(rs_fr, (r, s, ts)) * (1 + gv(rtcs_fr, (r, t, c, s, ts))), r, v, t, p, c, ts)
            end
        end
    end
    rld!(e, k, r, t, s, item) = addterm!(e, k, tm, "VAR_RLD", r, t, s, item)
    # SUM((RLDC,BDNEQ(BD))$(DIAG('RL-DISP',RLDC)=DIAG(side,BD)), VAR_RLD(R,T,S,RLDC)*GR_VARGEN(R,S,RLDC,BD))
    function variations!(e, r, t, s, side)
        for item in rldc, bd in ("LO", "UP")
            ((item == "RL-DISP") == (bd == side)) || continue
            haskey(vargen.values, (r, s, item, bd)) || continue
            rld!(e, gv(vargen, (r, s, item, bd)), r, t, s, item)
        end
    end
    stg_out = [(k[2], k[3]) for k in top.keys if k[4] == "OUT" && (k[1], k[2], k[3]) in rpc_stg && (k[1], k[3]) in nrg_elc]
    stg_out_of = Dict{String,Vector{NTuple{2,String}}}()
    foreach(k -> (k[4] == "OUT" && (k[1], k[2], k[3]) in rpc_stg && (k[1], k[3]) in nrg_elc) &&
                 push!(get!(stg_out_of, k[1], NTuple{2,String}[]), (k[2], k[3])), top.keys)
    rows = [(r, t) for (r, t) in gr_rldc.keys if (t,) in milestonyr && (t,) in tx]
    off = rts_off(tm)                    # RTS(S): S+NORTS(R,T,S) with dynamic timeslices (M1.3 change 67)
    fin_of = Dict{String,Vector{String}}()
    foreach(k -> push!(get!(fin_of, k[1], String[]), k[2]), S("FINEST").keys)
    n = 0
    # EQ_RL_LOAD
    for (r, t) in rows, s in get(fin_of, r, String[])
        off(r, t, s) && continue         # RTS(S) (M1.3 change 67)
        yr = gv(g_yrfr, (r, s))
        for sow in sw_rows(tm, t)   # %SWT% (L72)
            set_sow!(tm, sow)
            lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
            production!(lhs, r, t, s, p -> haskey(genmap.values, (r, p, "RL-DISP")))
            "RL-THMIN" in rldc && rld!(lhs, yr, r, t, s, "RL-THMIN")
            for k in top.keys
                (k[1] == r && (r, k[2], k[3]) in rpc_stg && (r, k[3]) in nrg_elc) || continue
                p, c, io = k[2], k[3], k[4]
                for (_, v, _, _) in get(vint_of, (r, t, p), no4), (_, _, _, ts) in get(rpcs_of, (r, p, c), no4)
                    haskey(rs_fr.values, (r, s, ts)) || continue
                    f = gv(rs_fr, (r, s, ts))
                    if (io,) in ips
                        addterm!(lhs, -f, tm, "VAR_SIN", r, v, t, p, c, ts)
                    else
                        addterm!(lhs, gv(stg_eff, (r, v, p)) * f, tm, "VAR_SOUT", r, v, t, p, c, ts)
                    end
                end
            end
            if (r, "0") in gr_rldc
                for (_, _, c, ts) in get(combal_of, (r, t), no4)
                    (haskey(rs_fr.values, (r, s, ts)) && (r, c) in nrg_elc && !((r, t, c) in agg)) || continue
                    k = one / gv(com_ie, (r, t, c, ts)) * gv(rs_fr, (r, s, ts)) * (1 + gv(rtcs_fr, (r, t, c, s, ts)))
                    addterm!(lhs, -k, tm, "VAR_COMNET", r, t, c, ts)
                end
            end
            rld!(rhs, yr, r, t, s, "RL-DISP")
            gconstraint!(tm, eqtag(tm, "EQ_RL_LOAD"), swt(tm, (r, t, s), t), "E", lhs, rhs) === nothing || (n += 1)
        end
    end
    # EQ_RL_NDIS
    for (r, t) in rows, s in get(fin_of, r, String[]), item in rldc
        off(r, t, s) && continue         # RTS(S) (M1.3 change 67)
        haskey(vargen.values, (r, "ANNUAL", item, "FX")) || continue
        for sow in sw_rows(tm, t)   # %SWT% (L92)
            set_sow!(tm, sow)
            lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
            production!(lhs, r, t, s, p -> (r, p, item) in gr_rlgt)
            rld!(rhs, gv(g_yrfr, (r, s)), r, t, s, item)
            gconstraint!(tm, eqtag(tm, "EQ_RL_NDIS"), swt(tm, (r, t, s, item), t), "E", lhs, rhs) === nothing || (n += 1)
        end
    end
    # EQ_RL_STCAP
    for (r, t) in rows, s in get(fin_of, r, String[])
        off(r, t, s) && continue         # RTS(S) (M1.3 change 67)
        for sow in sw_rows(tm, t)   # %SWT% (L101)
            set_sow!(tm, sow)
            lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
            for (p, c) in get(stg_out_of, r, NTuple{2,String}[])
                ((r, p) in prc_cap && (r, p, s) in prc_ts) || continue
                base = gv(capact, (r, p)) * gv(rs_stgprd, (r, s))
                for (_, v, _, _) in get(cptyr_of, (r, t, p), no4)
                    sm = nothing
                    for (_, ts, _) in get(tsmap_to, (r, s), no3)
                        haskey(coef_af.values, (r, v, t, p, ts, "UP")) || continue
                        x = gv(coef_af, (r, v, t, p, ts, "UP")) / gv(rs_fr, (r, s, ts)) * cafprod(r, v, p, c, s, ts)
                        sm = sm === nothing ? x : gmin(sm, x)
                    end
                    sm === nothing && throw(DomainError((r, v, t, p, s), "resloadc.vda L105: SMIN over no COEF_AF 'UP' (+INF)"))
                    capterm!(lhs, base * (gv(coef_cpt, (r, v, t, p)) * gv(actflo, (r, v, p, c)) * sm), r, v, t, p, milestonyr, pastyear)
                end
            end
            rld!(rhs, one, r, t, s, "RL_THMIN")
            rld!(rhs, -one, r, t, s, "RL-DISP")
            variations!(rhs, r, t, s, "LO")
            gconstraint!(tm, eqtag(tm, "EQ_RL_STCAP"), swt(tm, (r, t, s), t), "G", lhs, rhs) === nothing || (n += 1)
        end
    end
    # EQ_RL_PKCAP
    for (r, t) in rows, s in get(fin_of, r, String[])
        off(r, t, s) && continue         # RTS(S) (M1.3 change 67)
        for sow in sw_rows(tm, t)   # %SWT% (L120)
            set_sow!(tm, sow)
            lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
            for (rr, p, item) in gr_rlgt.keys
                (rr == r && item == "RL-DISP" && (r, p) in prc_cap) || continue
                ca = gv(capact, (r, p))
                nts = count(k -> haskey(rs_fr.values, (r, s, k[3])), get(ts_of_rp, (r, p), no3))
                for (_, v, _, _) in get(cpt_of, (r, t, p), no4)
                    af = gv(coef_af, (r, v, t, p, s, "UP")) * GNum(nts)
                    capterm!(lhs, ca * (gv(coef_cpt, (r, v, t, p)) * smaxflo(r, v, p) * af), r, v, t, p, milestonyr, pyr)
                end
            end
            for (p, c) in get(stg_out_of, r, NTuple{2,String}[])
                ((r, p) in prc_cap && (r, p, s) in prc_ts) || continue
                base = gv(capact, (r, p)) * gv(rs_stgprd, (r, s))
                for (_, v, _, _) in get(cptyr_of, (r, t, p), no4)
                    k = gv(coef_cpt, (r, v, t, p)) * gv(coef_af, (r, v, t, p, s, "UP")) * gv(actflo, (r, v, p, c)) *
                        gv(stg_eff, (r, v, p)) * cafprod(r, v, p, c, s, s)
                    capterm!(lhs, base * k, r, v, t, p, milestonyr, pyr)
                end
            end
            rld!(rhs, one, r, t, s, "RL-DISP")
            variations!(rhs, r, t, s, "UP")
            gconstraint!(tm, eqtag(tm, "EQ_RL_PKCAP"), swt(tm, (r, t, s), t), "G", lhs, rhs) === nothing || (n += 1)
        end
    end
    # EQ_RL_THMIN
    for (r, t) in rows, ts in get(fin_of, r, String[]), bd in ("LO", "UP")
        off(r, t, ts) && continue        # RTS(TS) (M1.3 change 67)
        (bd == "LO" || "RL-THMIN" in rldc) || continue                    # BDLOX(BDNEQ)+RLDC('RL-THMIN')
        for sow in sw_rows(tm, t)   # %SWT% (L142)
            set_sow!(tm, sow)
            lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
            rld!(lhs, gv(bdsig, (bd,)), r, t, ts, "RL_THMIN")
            bd == "UP" && rld!(lhs, one, r, t, ts, "RL-THMIN")               # BDUPX(BDNEQ)
            if bd == "LO"                                                    # $BDLOX(BDNEQ)
                for (rr, p, item) in gr_rlgt.keys
                    (rr == r && item == "RL-THMIN" && (r, p) in prc_cap) || continue
                    ca = gv(capact, (r, p))
                    addconst!(rhs, ca * gv(thbnd, (r, t, p, "FX")))
                    vint = (r, p) in prc_vint
                    for (_, v, _, _) in get(vint_of, (r, t, p), no4)
                        sf = smaxflo(r, v, p)
                        for (_, _, s) in get(ts_of_rp, (r, p), no3)
                            haskey(rs_fr.values, (r, ts, s)) || continue
                            b = gv(thbnd, (r, t, p, "LO")) + gv(thbnd, (r, t, p, "UP"))
                            if !haskey(thmin.values, (r, t, p))
                                for (_, sl) in get(ts_ann_of, (s,), NTuple{2,String}[])
                                    b = b + gv(act_ups, (r, v, p, sl, "FX"))
                                end
                            end
                            w = ca * (sf * b)
                            for (_, kv, _, _) in get(cpt_of, (r, t, p), no4)
                                ((kv,) in modlyear && (!vint || kv == v)) || continue
                                c = w * gv(coef_cpt, (r, kv, t, p))
                                (kv,) in milestonyr && addterm!(rhs, c, tm, "VAR_NCAP", r, kv, p; at=kv)   # %VARM%_NCAP(R,K,P %SWS%) (L154)
                                (kv,) in pyr && addconst!(rhs, c * gv(pasti, (r, kv, p)))
                                rcapsub!(rhs, c, tm, r, kv, t, p)                    # %RCAPSBM%
                            end
                            for (_, a, _) in get(tsmap_to, (r, s), no3)               # %UPSCAPS%
                                (r, p, a) in rps_ups || continue
                                addterm!(rhs, -w, tm, "VAR_UPS", r, v, t, p, a, "N")
                            end
                        end
                    end
                end
            end
            gconstraint!(tm, eqtag(tm, "EQ_RL_THMIN"), swt(tm, (r, t, ts, bd), t), "G", lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end
