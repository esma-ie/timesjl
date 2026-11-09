# M1.3 (6b): the end of the init -> prep segment, preppm.mod L213-217: the
# extensions' prep_ext files (main_ext.mod prep_ext %EXTEND%), the VDA
# extension's interpolation (prep_ext.vda) with equcrtp.vda PREP_EXT
# (equcrtp.jl). The prep checkpoint follows (the harness's prep_ext.tjlref,
# last in %EXTEND%).
#
# GAMS: preppm.mod L213-217, main_ext.mod, prep_ext.dsc L12, prep_ext.vda
# L1-83, v4.9.7.
#
# Index sets: R is REG, P is PRC, C is COM, CG is COM_GRP, S and TS are
# ALL_TS, BD is BND_TYPE, LL is ALLYEAR, T is MILESTONYR, V is MODLYEAR, PYR is
# PASTYEAR. `LL--ORD(LL)` is '0' and `S--ORD(S)` the last ALL_TS element (a
# circular lag by the element's own position, G31). Comparisons treat EPS as
# 0, `$` as present (G12); `$=` assigns where the right side is nonzero or EPS
# (G24); a statement reads the values from before it (G11). The macros'
# scratch (UNCD7, MY_ARRAY and the scalars) carries over from preppm.mod in
# `InterpState` and is stored when the segment ends, as GAMS leaves it.
#
# %EXTEND% holds VDA always, DSC with %DSC% YES (initmty.mod L453-468), and the
# harness's TJLREF. prep_ext.dsc exits unless %DSC% is YES (L12), which
# init_ext.dsc leaves YES only with discrete-capacity data (refused there,
# init_ext.jl). The other extensions (ECB, MACRO, ETL, CLI, ABS, MCA, and
# STAGES at preppm.mod L214) are refused, as are gas grids under %POWERFLO%
# YES (L37, powerflo.vda PREP: `powerflo_prep!`, M1.3 change 27a), GR_VARGEN
# data (L38, resloadc.vda), %VINTOPT% 1 (L42-43,
# fillvint.gms with arguments) and %WAVER% YES (L63). L63 is compiled only
# with %WAVER% YES (`$IFI` takes the rest of the line), so without it the line
# does nothing. L75 (`$IF NOT DEFINED VNRET $CLEAR RCAP_OCAP`) is a
# compile-time directive: its effect is already in the dumps (G2).

"The paths of preppm.mod L213-217 this model would take that are not translated."
function prep_ext_unported(tm)
    out = String[]
    yes(n) = uppercase(strip(gswitch(tm, n, ""), ['\'', '"'])) == "YES"
    yes("STAGES") && push!(out, "preppm.mod L214 (STAGES YES: prep_ext.stc)")
    for n in ("ECB", "ETL", "CLI", "ABS", "MCA")
        yes(n) && push!(out, "main_ext.mod prep_ext ($n YES: the $n extension)")
    end
    gswitch(tm, "MACRO", "") == "" || push!(out, "prep_ext.tm/.mlf (MACRO set)")
    dsc_loaded(tm) && append!(out, init_ext_dsc_unported(tm))
    yes("POWERFLO") && append!(out, powerflo_unported(tm))
    hasdata(tm, "GR_VARGEN", 4) && push!(out, "prep_ext.vda L38 (GR_VARGEN has data: resloadc.vda)")
    # init_ext.vda L132 fills UC_FLOBET from UC_ACTBET at run time: whether UC_FLOBET is DEFINED (L35) then
    # depends on the DD files, which the dumps do not show
    hasdata(tm, "UC_ACTBET", 4) && push!(out, "prep_ext.vda L35 (UC_ACTBET has data: \$IF DEFINED UC_FLOBET undecidable from the dump)")
    strip(gswitch(tm, "VINTOPT", "")) == "1" && push!(out, "prep_ext.vda L42-43 (VINTOPT 1: fillvint.gms with arguments)")
    yes("WAVER") && push!(out, "prep_ext.vda L63 (WAVER YES)")
    return out
end

"""
    prep_ext_symbols(tm) -> Vector{String}

Every set and parameter of the prep dump, compared after `prep_ext!` (the
step ends the init -> prep segment), the QA-log scalars PUTOUT, PUTGRP and
ERRLEV too (M1.3 change 25b-1).
"""
prep_ext_symbols(tm) = sort([i.name for i in values(tm.data.dump.symbols) if i.kind in (:set, :parameter)])

"""
    prep_ext!(tm) -> tm

preppm.mod L213-217 on the state after `preppm!`: the extensions' prep_ext
files, in %EXTEND% order (DSC, which exits, then VDA). Ends at the prep
checkpoint, with the macros' scratch as GAMS leaves it.

GAMS: preppm.mod L213-217, main_ext.mod, v4.9.7.
"""
function prep_ext!(tm)
    u = prep_ext_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    st = InterpState(tm)
    # prep_ext.dsc L12: $IFI NOT %DSC%==YES $EXIT   (%DSC% is NO here: init_ext.dsc, init_ext.jl)
    prep_ext_vda!(st)
    put_interp_scratch!(st)
    return tm
end

"""
    prep_ext_vda!(st) -> st

prep_ext.vda on the state of `st.tm`: commodity-specific availabilities
(NCAP_AFAC, NCAP_AFCS), the ACT_EFF groups (RPC_ACE, RPG_1ACE), ACT_FLO, the
VDA parameters interpolated, dynamic process bounds (equcrtp.vda PREP_EXT),
FLO_FUNCX of non-vintaged processes, the residual capacities PRC_RESID
interpolated over their lifetimes (RTP_CPTYR), and the QA overrides
(IFQ, COM_LIM, ACT_MINLD, RPC_CAPFLO, FLO_ASHAR, cost-neutral ILEDs).

GAMS: prep_ext.vda L11-83, v4.9.7.
"""
function prep_ext_vda!(st::InterpState)
    tm = st.tm
    d = tm.data
    ax = st.ax
    yv(y) = ax.yearval[y]
    dfl = "0"                                                         # LL--ORD(LL), %DFLBL%
    foreach(l -> register_uel!(d, l), ("", dfl, "ANNUAL", "FX", "N"))
    reg = Set(k[1] for k in gset(tm, "REG").keys)
    com = Set(k[1] for k in gset(tm, "COM").keys)
    ts_last = last(gset(tm, "ALL_TS").keys)[1]                        # S--ORD(S)
    rtp = gset(tm, "RTP").members
    rvp = gset(tm, "RVP").members
    V = [k[1] for k in gset(tm, "MODLYEAR").keys]
    T = [k[1] for k in gset(tm, "MILESTONYR").keys]
    M, B = gvalues(tm, "M", 1), gvalues(tm, "B", 1)
    Mv(t) = gv(M, (t,)).v
    Bv(t) = gv(B, (t,)).v

    # --- L11-14: commodity-specific availabilities; NCAP_AFAC overrides NCAP_AFC ---------
    afac, afcs, afc = gvalues(tm, "NCAP_AFAC", 4), gvalues(tm, "NCAP_AFCS", 5), gvalues(tm, "NCAP_AFC", 5)
    # L12: OPTION RP_GRP < NCAP_AFAC
    rp_grp = project(keys(afac), (1, 3, 4))
    # L13: NCAP_AFC(R,DATAYEAR,P,CG,'ANNUAL')$RP_GRP(R,P,CG) = NCAP_AFAC(R,DATAYEAR,P,CG)
    for (r, p, cg) in rp_grp, y in st.datayear
        r in reg && gassign!(afc, (r, y, p, cg, "ANNUAL"), gv(afac, (r, y, p, cg)))
    end
    # L14: NCAP_AFC(R,LL,P,CG,STL(S)) $= NCAP_AFCS(R,LL,P,CG,S); OPTION CLEAR=NCAP_AFCS
    stl = gset(tm, "STL").members
    for (k, x) in afcs
        (k[1] in reg && (k[5],) in stl) && gassign!(afc, k, x == 0.0 ? GEPS : GNum(x))
    end
    gput!(tm, "NCAP_AFC", afc)
    gput!(tm, "NCAP_AFCS", Dict{NTuple{5,String},Float64}())

    # --- L15-21: ACT_EFF groups ---------------------------------------------------------
    act_eff = gvalues(tm, "ACT_EFF", 5)
    # L16: OPTION RP_GRP < ACT_EFF, CLEAR=UNCD7
    rp_grp = project(keys(act_eff), (1, 3, 4))
    # L17: UNCD7(R,LL--ORD(LL),P,CG,S--ORD(S),'','')$BOHYEAR(LL) $= (ACT_EFF(R,LL,P,CG,S) GT 0)$ACT_EFF(R,LL,P,CG,S)
    bohyear = gset(tm, "BOHYEAR").members
    st.uncd7 = Set{NTuple{7,String}}((k[1], dfl, k[3], k[4], ts_last, "", "")
                                     for (k, x) in act_eff if (k[2],) in bohyear && x > 0)
    # L18: LOOP(UNCD7(R,LL,P,CG,S,'',''),RPC_ACE(R,P,CG) = YES)
    rpc_ace = gmembers(tm, "RPC_ACE", 3)
    foreach(k -> push!(rpc_ace, (k[1], k[3], k[4])), st.uncd7)
    gput!(tm, "RPC_ACE", rpc_ace)
    # L19: RPG_1ACE(RP_GRP(RPC(R,P,C)),C)$(NOT RPC_ACE(RPC)) = YES
    rpc = gset(tm, "RPC").members
    rpg_1ace = gmembers(tm, "RPG_1ACE", 4)
    for k in rp_grp
        (k in rpc && !(k in rpc_ace)) && push!(rpg_1ace, (k[1], k[2], k[3], k[3]))
    end
    gput!(tm, "RPG_1ACE", rpg_1ace)
    # L20: OPTION CLEAR=RP_GRP
    gput!(tm, "RP_GRP", Set{NTuple{3,String}}())
    # L21: ACT_FLO(R,LL--ORD(LL),P,C,S)$STOA(S) $= VDA_FLOP(R,LL,P,C,S)   (over LL in order: the last nonzero wins)
    stoa = gparam_opt(d, "STOA", 1)
    flop = gvalues(tm, "VDA_FLOP", 5)
    act_flo = gvalues(tm, "ACT_FLO", 5)
    for k in gams_sort!(collect(keys(flop)), d)
        (k[1] in reg && k[4] in com && !iszero(gv(stoa, (k[5],)))) || continue
        gassign!(act_flo, (k[1], dfl, k[3], k[4], k[5]), gv(flop, k))
    end
    gput!(tm, "ACT_FLO", act_flo)

    # --- L23-36: interpolation of the VDA parameters --------------------------------------
    one = k -> true
    rtpk = k -> (k[1], k[2], k[3]) in rtp                           # 'RTP(R,V,P)'
    rvpk = k -> (k[1], k[2], k[3]) in rvp                           # 'RVP(R,V,P)'
    ge0 = (x, k) -> x >= 0                                          # 'GE 0'
    actcg = Set(k[1] for k in gset(tm, "ACTCG").keys)
    fillparm!(st, "VDA_EMCB", "R", "C,COM", pd(",'0','0','0','0'"), V, one, ge0)
    # L25: 'GE -1$ACTCG(CG)' on the row (R,'0',P,CG,STL)
    fillparm!(st, "NCAP_AFC", "R", "P,CG,STL", pd(",'0','0','0'"), V, rtpk, (x, k) -> x >= (k[4] in actcg ? -1 : 0))
    fillparm!(st, "ACT_EFF", "R", "P,CG,TS", pd(",'0','0','0'"), V, rvpk, ge0; cache=true)
    fillparm!(st, "VDA_FLOP", "R", "P,CG,TS", pd(",'0','0','0'"), V, rvpk, ge0; cache=true)
    fillparm!(st, "FLO_EMIS", "R", "P,CG,COM,S", pd(",'0','0'"), V, rvpk, ge0; cache=true)
    fillparm!(st, "ACT_UPS", "R", "P,S,BD", pd(",'0','0','0'"), V, rvpk, ge0)
    fillparm!(st, "ACT_LOSPL", "R", "P,L", pd(",'0','0','0','0'"), V, rvpk, ge0)
    fillparm!(st, "ACT_LOSSD", "R", "P,UPT,BD", pd(",'0','0','0'"), V, rvpk, ge0)
    fillparm!(st, "ACT_SDTIME", "R", "P,UPT,BD", pd(",'0','0','0'"), V, rvpk, ge0)
    fillparm!(st, "ACT_MAXNON", "R", "P,UPT", pd(",'0','0','0','0'"), V, rvpk, ge0)
    fillparm!(st, "STG_MAXCYC", "R", "P", pd(",'0','0','0','0','0'"), V, rtpk, ge0)
    # L35-36: $IF DEFINED UC_FLOBET / COM_CSTBAL (G35, G40)
    hasdata(tm, "UC_FLOBET", 5) && fillparm!(st, "UC_FLOBET", "UC_N,R", "P,C", pd(",'0','0','0'"), T, one, ge0)
    hasdata(tm, "COM_CSTBAL", 6) && fillparm!(st, "COM_CSTBAL", "R", "C,S,ITEM,CUR", pd(",'0','0'"), T, one, ge0)
    # L37: $IFI %POWERFLO%==YES $BATINCLUDE powerflo.vda PREP (M1.3 change 27a)
    uppercase(strip(gswitch(tm, "POWERFLO", ""), ['\'', '"'])) == "YES" && powerflo_prep!(st)
    # L39: $BATINCLUDE equcrtp.vda PREP_EXT
    equcrtp_prep_ext!(st)

    # --- L44: FLO_FUNCX(R,LL,P,C,CG)$(NOT PRC_VINT(R,P)) = 0 ----------------------------------
    vint = gset(tm, "PRC_VINT").members
    funcx = gvalues(tm, "FLO_FUNCX", 5)
    filter!(((k, _),) -> !(k[1] in reg && k[4] in com && !((k[1], k[3]) in vint)), funcx)
    gput!(tm, "FLO_FUNCX", funcx)

    # --- L47-69: the tailored interpolation of PRC_RESID ----------------------------------------
    prc_resid_vda!(st, reg, T, Mv, Bv)

    # --- L70-83: QA overrides ------------------------------------------------------------------
    # L71: IFQ$SUM(COM_TYPE(CG(R)),1)=0   (the regions whose label is also a commodity type)
    ctype = gset(tm, "COM_TYPE").members
    any(r -> (r,) in ctype, reg) && gput!(tm, "IFQ", Dict{Tuple{},Float64}())
    # L72: COM_LIM(RC,BDNEQ)$COM_LIM(RC,'FX')=NO
    com_lim = gmembers(tm, "COM_LIM", 3)
    rc = gset(tm, "RC").members
    bdneq = [k[1] for k in gset(tm, "BDNEQ").keys]
    for k in collect(com_lim)
        (k[3] == "FX" && (k[1], k[2]) in rc) || continue
        foreach(bd -> delete!(com_lim, (k[1], k[2], bd)), bdneq)
    end
    gput!(tm, "COM_LIM", com_lim)
    # L74: ACT_MINLD(RTP) $= ACT_UPS(RTP,'ANNUAL','FX')
    act_ups = gvalues(tm, "ACT_UPS", 5)
    act_minld = gvalues(tm, "ACT_MINLD", 3)
    for (k, x) in act_ups
        (k[4] == "ANNUAL" && k[5] == "FX" && (k[1], k[2], k[3]) in rtp) && gassign!(act_minld, (k[1], k[2], k[3]), x == 0.0 ? GEPS : GNum(x))
    end
    gput!(tm, "ACT_MINLD", act_minld)
    # L76: RPC_CAPFLO(RTP,C) $= RCAP_OCAP(RTP,C)
    rpc_capflo = gmembers(tm, "RPC_CAPFLO", 4)
    for k in keys(gparam_opt(d, "RCAP_OCAP", 4).values)
        ((k[1], k[2], k[3]) in rtp && k[4] in com) && push!(rpc_capflo, k)
    end
    gput!(tm, "RPC_CAPFLO", rpc_capflo)
    # L78: FLO_ASHAR(R,DM_YEAR,P,C,CG,S,BD) $= FLO_SHAR(R,DM_YEAR,P,C,CG,S,BD)$(NOT COM_GMAP(R,CG,C)*RPC(R,P,C))
    gmap = gset(tm, "COM_GMAP").members
    ashar = gvalues(tm, "FLO_ASHAR", 7)
    for (k, x) in gparam_opt(d, "FLO_SHAR", 7).values
        (k[1] in reg && k[2] in st.dm_set && k[4] in com) || continue
        ((k[1], k[5], k[4]) in gmap && (k[1], k[3], k[4]) in rpc) && continue
        gassign!(ashar, k, x == 0.0 ? GEPS : GNum(x))
    end
    gput!(tm, "FLO_ASHAR", ashar)
    # L80-83: cost-neutral ILEDs
    rvprl_ileds!(st, reg, T, Mv, Bv)
    return st
end

"""
    prc_resid_vda!(st, reg, T, Mv, Bv)

prep_ext.vda L47-69: PRC_RESID of the processes with a '0' record (TRACKP)
interpolated between its data years and, from the last one (or with options
5 and 15 from the first), run down to EPS over the lifetime the '0' record
is then set to; NCAP_TLIFE 1 and NCAP_ILED 0 at the PYR_S year, RTP_CPTYR of
the periods with residual capacity or before PRC_YMAX.

GAMS: prep_ext.vda L47-69, v4.9.7.
"""
function prc_resid_vda!(st::InterpState, reg, T, Mv, Bv)
    tm = st.tm
    d = tm.data
    yv(y) = st.ax.yearval[y]
    dfl = "0"
    resid = gvalues(tm, "PRC_RESID", 3)
    # L48: OPTION CLEAR=PRC_YMAX,CLEAR=MY_ARRAY
    ymax = Dict{NTuple{2,String},Float64}()
    empty!(st.my_array)
    # L49: TRACKP(R,P)$=PRC_RESID(R,'0',P); PRC_YMAX(TRACKP(R,P))=ROUND(PRC_RESID(R,'0',P))
    trackp = gmembers(tm, "TRACKP", 2)
    for k in keys(resid)
        (k[1] in reg && k[2] == dfl) && push!(trackp, (k[1], k[3]))
    end
    tracked = gams_sort!(collect(trackp), d)
    foreach(((r, p),) -> gassign!(ymax, (r, p), grnd(gv(resid, (r, dfl, p)))), tracked)
    tlife, iled = gvalues(tm, "NCAP_TLIFE", 3), gvalues(tm, "NCAP_ILED", 3)
    cptyr = gmembers(tm, "RTP_CPTYR", 4)
    g_tlife = GNum(gscalar(tm, "G_TLIFE"))
    pyr = gset(tm, "PASTYEAR").members
    pyr_s = [y for y in st.ax.years if (y,) in gset(tm, "PYR_S").members && (y,) in pyr]
    for ll in pyr_s                                                # L50: LOOP(PYR_S(PYR(LL)), ...)
        # L51: PRC_RESID(R,'0',P)$TRACKP(R,P) = MAX(1,NCAP_TLIFE(R,LL,P)+G_TLIFE$(NOT NCAP_TLIFE(R,LL,P)))
        for (r, p) in tracked
            tl = gv(tlife, (r, ll, p))
            gassign!(resid, (r, dfl, p), max(1.0, (tl + gif(g_tlife, iszero(tl))).v))
        end
        # L52: LOOP(TRACKP(R,P), DFUNC=PRC_YMAX(R,P);
        for (r, p) in tracked
            st.DFUNC = gv(ymax, (r, p))
            # L53: MY_ARRAY(DM_YEAR)=PRC_RESID(R,DM_YEAR,P); MY_F=0; F=0; Z=0
            arr = row_array(st, resid, (r, dfl, p), 2)
            set_my_array!(st, arr)
            st.MY_F, st.F, st.Z = GZERO, GZERO, GZERO
            # L55-58: LOOP(DM_YEAR$MY_ARRAY(DM_YEAR), LAST_VAL=MY_F; MY_F=MY_ARRAY(DM_YEAR); Z=YEARVAL(DM_YEAR);
            #   IF(LAST_VAL, PRC_RESID(R,T,P)$((Z>M(T))$(M(T)>MY_FYEAR)) = MY_F-(MY_F-LAST_VAL)/(Z-MY_FYEAR)*(Z-M(T));
            #   ELSE F=Z); MY_FYEAR=Z; CNT$(LAST_VAL+MY_F>0)=Z)
            for (y, x) in arr
                st.LAST_VAL = st.MY_F
                st.MY_F = x
                st.Z = gyear(yv(y))
                if !iszero(st.LAST_VAL)
                    for t in T
                        (st.Z.v > Mv(t) && Mv(t) > st.MY_FYEAR.v) || continue
                        gassign!(resid, (r, t, p),
                                 st.MY_F - (st.MY_F - st.LAST_VAL) / (st.Z - st.MY_FYEAR) * (st.Z - gyear(Mv(t))))
                    end
                else
                    st.F = st.Z
                end
                st.MY_FYEAR = st.Z
                (st.LAST_VAL + st.MY_F).v > 0 && (st.CNT = st.Z)
            end
            # L60: IF(ABS(DFUNC-10)=5, DFUNC=F; F=Z; ELSE F$DFUNC=0)
            if abs(st.DFUNC.v - 10) == 5
                st.DFUNC = st.F
                st.F = st.Z
            elseif !iszero(st.DFUNC)
                st.F = GZERO
            end
            # L61-62: IF(Z=F,CNT=PRC_RESID(R,'0',P); Z=F+CNT; DFUNC=DFUNC+CNT;
            #   PRC_RESID(R,T,P)$(M(T)>F)=MY_F*MAX(0,1-(M(T)-F)$(M(T)>=DFUNC)/CNT); MY_F=0; ELSE Z=CNT)
            if st.Z.v == st.F.v
                st.CNT = gv(resid, (r, dfl, p))
                st.Z = st.F + st.CNT
                st.DFUNC = st.DFUNC + st.CNT
                for t in T
                    m = Mv(t)
                    m > st.F.v || continue
                    gassign!(resid, (r, t, p), st.MY_F * GNum(max(0.0, 1 - (m >= st.DFUNC.v ? m - st.F.v : 0.0) / st.CNT.v)))
                end
                st.MY_F = GZERO
            else
                st.Z = st.CNT
            end
            # L63: compiled only with %WAVER% YES (refused)
        end
        # L66-67: NCAP_TLIFE(R,LL,P)$TRACKP(R,P) = 1; NCAP_ILED(R,LL,P)$TRACKP(R,P) = 0
        foreach(((r, p),) -> gassign!(tlife, (r, ll, p), 1.0), tracked)
        foreach(((r, p),) -> delete!(iled, (r, ll, p)), tracked)
        # L68: RTP_CPTYR(R,LL,T,P)$(((PRC_RESID(R,T,P)>0)+(B(T)<PRC_YMAX(R,P)))$TRACKP(R,P)) = YES
        for (r, p) in tracked, t in T
            (gv(resid, (r, t, p)).v > 0 || Bv(t) < gv(ymax, (r, p)).v) && push!(cptyr, (r, ll, t, p))
        end
    end
    gput!(tm, "PRC_RESID", resid)
    gput!(tm, "PRC_YMAX", ymax)
    gput!(tm, "NCAP_TLIFE", tlife)
    gput!(tm, "NCAP_ILED", iled)
    gput!(tm, "RTP_CPTYR", cptyr)
    # L69: OPTION CLEAR=TRACKP
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    return st
end

"""
    rvprl_ileds!(st, reg, T, Mv, Bv)

prep_ext.vda L80-83: an NCAP_BND 'N' value in the years of a period makes
the period's new capacity cost-neutral: the value, rounded to a whole
number of steps of M(T), becomes NCAP_BND(R,T,P,'N'), the lead time
NCAP_ILED its offset from B(T) (old NCAP_ILED kept in COEF_ILED, plus 1000),
and special-value upper bounds of those processes are removed.

GAMS: prep_ext.vda L80-83, v4.9.7.
"""
function rvprl_ileds!(st::InterpState, reg, T, Mv, Bv)
    tm = st.tm
    rtp = gset(tm, "RTP").members
    bnd = gvalues(tm, "NCAP_BND", 4)
    tset = Set(T)
    periodyr = Dict{String,Vector{String}}()
    foreach(((t, y),) -> push!(get!(periodyr, t, String[]), y), gset(tm, "PERIODYR").keys)
    # L80: RVPRL(RTP(R,T,P)) $= SUM(PERIODYR(T,YEAR)$NCAP_BND(R,YEAR,P,'N'),NCAP_BND(R,YEAR,P,'N'))
    rvprl = gvalues(tm, "RVPRL", 3)
    for k in gset(tm, "RTP").keys
        k[2] in tset || continue
        ys = [y for y in get(periodyr, k[2], String[]) if haskey(bnd, (k[1], y, k[3], "N"))]
        isempty(ys) && continue
        gassign!(rvprl, k, reduce(+, (gv(bnd, (k[1], y, k[3], "N")) for y in ys); init=GZERO))
    end
    # L81-83: IF(CARD(RVPRL), LOOP(RTP(R,T,P)$RVPRL(RTP), Z=RVPRL(RTP); Z=Z/ROUND(Z/M(T)); NCAP_BND(RTP,'N')=Z;
    #   COEF_ILED(RTP) = ABS(NCAP_ILED(RTP))+1000; NCAP_ILED(RTP) = MAX(EPS,Z+1-B(T)));
    #   NCAP_BND(RTP,BDUPX)$(MAPVAL(NCAP_BND(RTP,BDUPX))$RVPRL(RTP))=0; OPTION CLEAR=RVPRL)
    isempty(rvprl) && return st
    iled, coef_iled = gvalues(tm, "NCAP_ILED", 3), gvalues(tm, "COEF_ILED", 3)
    for k in gset(tm, "RTP").keys
        haskey(rvprl, k) || continue
        t = k[2]
        z = gv(rvprl, k)
        q = grnd(z / gyear(Mv(t)))
        iszero(q) && error("prep_ext.vda L81: division by zero")
        z = z / q
        st.Z = z
        gassign!(bnd, (k..., "N"), z)
        gassign!(coef_iled, k, GNum(abs(gv(iled, k).v)) + GNum(1000.0))
        x = z + GNum(1.0) - gyear(Bv(t))
        gassign!(iled, k, x.v > 0 ? x : GEPS)
    end
    bdupx = [k[1] for k in gset(tm, "BDUPX").keys]
    for k in keys(rvprl), bd in bdupx
        v = get(bnd, (k..., bd), nothing)
        (v !== nothing && (v == 0.0 || !isfinite(v))) && delete!(bnd, (k..., bd))   # MAPVAL: EPS, +-INF, NA
    end
    gput!(tm, "NCAP_BND", bnd)
    gput!(tm, "NCAP_ILED", iled)
    gput!(tm, "COEF_ILED", coef_iled)
    gput!(tm, "RVPRL", Dict{NTuple{3,String},Float64}())
    return st
end
