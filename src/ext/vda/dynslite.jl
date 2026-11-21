# M1.3 (63): dynslite.vda, dynamic timeslice trees (%DYNTS% YES with TS_OFF data, so %RTS% is
# S+NORTS(R,T,S): timslice.mod L31-39), "an experimental lite implementation" in its own words.
#
# GAMS (v4.9.7): dynslite.vda L8-89 (PRELEV, pp_prelv.vda L125, with the CLEAR block).
# Not yet translated (refused where they run): REDUCE (pp_reduce.red L188), POSTLEV (ppm_ext.vda
# L169), BOUNDS (bndmain.mod L87) and the RTS(S) domains of the equations.

"Whether %RTS% is S+NORTS(R,T,S): %DYNTS% YES and TS_OFF defined (timslice.mod L32-33; %OBMAC% is YES)."
dynts_on(tm) = uppercase(strip(gswitch(tm, "DYNTS", ""), ['\'', '"'])) == "YES" && !isempty(gset_opt(tm.data, "TS_OFF", 4).keys)

"""
    clear_off!(tm, name, N, ri, ti, si; cond=k -> true) -> nothing

`name(...)\$NORTS(R,T,S) = 0` for the parameter `name` of N dimensions with R, T and S at
positions ri, ti and si: the records of timeslices turned off in a period are removed, where
`cond(k)` (the domain of the statement) holds. A stored NORTS is -INF (timslice.mod L38), so `\$NORTS` is true wherever it has a record.
"""
function clear_off!(tm, name, N, ri, ti, si; cond=k -> true)
    norts = gparam(tm, "NORTS").values
    p = gvalues(tm, name, N)
    n0 = length(p)
    filter!(((k, _),) -> !(cond(k) && haskey(norts, (k[ri], k[ti], k[si]))), p)
    length(p) == n0 || gput!(tm, name, p)
    return nothing
end

"""
    dynslite_clear!(tm) -> tm

dynslite.vda's CLEAR block (L39-73), run by PRELEV and POSTLEV: the data of timeslices turned off
removed, for non-vintaged processes by period (RVP(RTP(R,T,P)) with NORTS(R,T,S)), for vintaged
processes at the ANNUAL level by vintage (in the first period MIYR_1, with
`%RTS%` = `\$(NORTS(R,V,S)+NORTS(R,T,S)\$PASTMILE(V))`), and the period data of every process,
commodity and user constraint. RVP is cleared after each part.

GAMS: dynslite.vda L39-73, v4.9.7.
"""
function dynslite_clear!(tm)
    d = tm.data
    S(n, k) = gset_opt(d, n, k).members
    norts = gparam(tm, "NORTS").values
    rtp, vint = S("RTP", 3), S("PRC_VINT", 2)
    # L41-51: RVP(RTP(R,T,P))$(NOT PRC_VINT(R,P)) = YES; the vintage-based data at NORTS(R,T,S); OPTION CLEAR=RVP
    T = Set(k[1] for k in gset(tm, "MILESTONYR").keys)
    rvp = Set(k for k in rtp if k[2] in T && !((k[1], k[3]) in vint))
    nv(k) = (k[1], k[2], k[3]) in rvp
    for (name, N, si) in (("ACT_FLO", 5, 5), ("FLO_FUNC", 6, 6), ("FLO_SUM", 7, 7), ("NCAP_AF", 5, 4), ("FLO_SHAR", 7, 6),
                          ("FLO_ASHAR", 7, 6), ("STG_LOSS", 4, 4), ("IRE_FLO", 7, 7), ("ACT_EFF", 5, 5))
        clear_off!(tm, name, N, 1, 2, si; cond=nv)
    end
    # L52-63: the vintaged processes at the ANNUAL level, by vintage, in the first period
    tsl = S("PRC_TSL", 3)
    rvpv = Set(k for k in rtp if (k[1], k[3]) in vint && (k[1], k[3], "ANNUAL") in tsl)
    pastmile = Set(k[1] for k in gset(tm, "PASTMILE").keys)
    rps_s1, rps_s2, rpcs_var = S("RPS_S1", 3), S("RPS_S2", 3), S("RPCS_VAR", 4)
    for (t,) in gset(tm, "MIYR_1").keys
        rts(r, v, s) = haskey(norts, (r, v, s)) || (v in pastmile && haskey(norts, (r, t, s)))
        on(k, si) = (k[1], k[2], k[3]) in rvpv && rts(k[1], k[2], k[si])
        for (name, N, si, extra) in (
                ("ACT_FLO", 5, 5, k -> (k[1], k[3], "ANNUAL") in rps_s1),
                ("FLO_FUNC", 6, 6, k -> true),
                ("FLO_SUM", 7, 7, k -> (k[1], k[3], k[5], "ANNUAL") in rpcs_var),
                ("NCAP_AF", 5, 4, k -> true),
                ("FLO_SHAR", 7, 6, k -> (k[1], k[3], k[4], "ANNUAL") in rpcs_var),
                ("FLO_ASHAR", 7, 6, k -> (k[1], k[3], "ANNUAL") in rps_s2),
                ("STG_LOSS", 4, 4, k -> true),
                ("IRE_FLO", 7, 7, k -> true))
            p = gvalues(tm, name, N)
            n0 = length(p)
            filter!(((k, _),) -> !(on(k, si) && extra(k)), p)
            length(p) == n0 || gput!(tm, name, p)
        end
    end
    gput!(tm, "RVP", Set{NTuple{3,String}}())                              # L63: OPTION CLEAR=RVP
    # L65-73: the period data of every process, commodity and user constraint
    for (name, N, ri, ti, si) in (("COM_IE", 4, 1, 2, 4), ("COM_PKFLX", 4, 1, 2, 4), ("COM_ELAST", 5, 1, 2, 4),
                                  ("FLO_PKCOI", 5, 1, 2, 5), ("STG_SIFT", 5, 1, 2, 5), ("IRE_FLOSUM", 8, 1, 2, 5),
                                  ("UC_ACT", 6, 3, 4, 6), ("UC_FLO", 7, 3, 4, 7), ("UC_IRE", 8, 3, 4, 7),
                                  ("UC_COM", 8, 4, 5, 7), ("UC_RHSRTS", 5, 1, 3, 4))
        clear_off!(tm, name, N, ri, ti, si)
    end
    return tm
end

"""
    dynslite_prelev!(tm) -> tm

dynslite.vda PRELEV (pp_prelv.vda L125), when %RTS% is S+NORTS(R,T,S) and NORTS has records:

    LOOP((R,ANNUAL(S),T), F=0;
     LOOP(RS_BELOW1(R,S,TS)\$(NOT NORTS(R,T,TS)), IF(F, RS_STG(R,TS)=ORD(TS)-Z; Z=ORD(TS); ELSE Z=ORD(TS); F=Z));
     RS_STG(R,S+(F-ORD(S)))\$F = F-Z);
    LOOP((TS_GROUP(R,'SEASON',S),TS(S--RS_STG(R,S)))\$RS_STGPRD(R,S),RS_STGAV(R,S) = (G_YRFR(R,S)+G_YRFR(R,TS))/2/RS_STGPRD(R,S));
    PUTGRP=0;
    LOOP(RT_PP(R,T), Z=SUM((RS_BELOW1(R,ANNUAL,TS),S(TS--RS_STG(R,TS)))\$((NOT NORTS(R,T,TS))\$NORTS(R,T,S)),1);
      IF(Z, ... FATAL ERROR - Timeslice trees have shared branches));
    ACT_BND(R,T,P,S,BD)\$NORTS(R,T,S)=0; ... COM_BPRICE(R,T,C,S,CUR)\$NORTS(R,T,S)=0;

then the CLEAR block (`dynslite_clear!`). The seasons' storage leads RS_STG are recomputed from
the seasons on in each period, the last period's leads remaining; a timeslice tree whose season
cycle reaches a season turned off is a fatal QA error in GAMS (an ArgumentError here). %DUC% YES
aborts (L15). F and Z are left as the loops leave them.

GAMS: dynslite.vda L8-38, v4.9.7.
"""
function dynslite_prelev!(tm)
    dynts_on(tm) || return tm                                               # L8: $IF %RTS%==S $EXIT
    norts = gparam(tm, "NORTS").values
    isempty(norts) && return tm                                             # L10: IF(CARD(NORTS), ...)
    uppercase(gswitch(tm, "DUC", "")) == "YES" && throw(ArgumentError("dynslite.vda L15: TS_OFF cannot be used with DUC"))
    d = tm.data
    ax = OrdAxis(tm, "ALL_TS")
    regs = [k[1] for k in gset(tm, "REG").keys]
    T = [k[1] for k in gset(tm, "MILESTONYR").keys]
    annual = [k[1] for k in gset(tm, "ANNUAL").keys]
    below1 = Dict{NTuple{2,String},Vector{String}}()
    for k in gams_sort!(collect(gset(tm, "RS_BELOW1").keys), d)
        push!(get!(() -> String[], below1, (k[1], k[2])), k[3])
    end
    rs_stg = gvalues(tm, "RS_STG", 2)
    F, Z = gscalar(tm, "F"), gscalar(tm, "Z")
    # L17-19
    for r in regs, s in annual, t in T
        F = 0.0
        for ts in get(below1, (r, s), String[])
            haskey(norts, (r, t, ts)) && continue
            if F != 0
                gassign!(rs_stg, (r, ts), GNum(Float64(ax.pos[ts]) - Z)); Z = Float64(ax.pos[ts])
            else
                Z = Float64(ax.pos[ts]); F = Z
            end
        end
        if F != 0
            el = lead(ax, s, Int(F) - ax.pos[s])
            el === nothing || gassign!(rs_stg, (r, el), GNum(F - Z))
        end
    end
    gput!(tm, "RS_STG", rs_stg)
    lag(r, s) = circlead(ax, s, -Int(round(get(rs_stg, (r, s), 0.0))))      # S--RS_STG(R,S)
    # L21: RS_STGAV for the seasons
    stgav = gvalues(tm, "RS_STGAV", 2)
    stgprd, yrfr = gparam(tm, "RS_STGPRD"), gparam(tm, "G_YRFR")
    for (r, tsl, s) in gset(tm, "TS_GROUP").keys
        (tsl == "SEASON" && !iszero(gv(stgprd, (r, s)))) || continue
        gassign!(stgav, (r, s), (gv(yrfr, (r, s)) + gv(yrfr, (r, lag(r, s)))) / GNum(2.0) / gv(stgprd, (r, s)))
    end
    gput!(tm, "RS_STGAV", stgav)
    # L23-27: the QA check
    gput_scalar!(tm, "PUTGRP", 0.0)
    for (r, t) in gams_sort!(collect(gset(tm, "RT_PP").keys), d)
        Z = 0.0
        for a in annual, ts in get(below1, (r, a), String[])
            (!haskey(norts, (r, t, ts)) && haskey(norts, (r, t, lag(r, ts)))) && (Z += 1)
        end
        Z == 0 || throw(ArgumentError("dynslite.vda L25-27: timeslice trees have shared branches (R.T)=$r.$t (a FATAL QA error in GAMS)"))
    end
    # L30-38: the bounds and costs of the timeslices turned off
    for (name, N, si) in (("ACT_BND", 5, 4), ("COM_BNDNET", 5, 4), ("COM_BNDPRD", 5, 4), ("FLO_BND", 6, 5), ("FLO_FR", 6, 5),
                          ("IRE_BND", 7, 4), ("IRE_XBND", 6, 4), ("STGIN_BND", 6, 5), ("STGOUT_BND", 6, 5), ("COM_BPRICE", 5, 4))
        clear_off!(tm, name, N, 1, 2, si)
    end
    dynslite_clear!(tm)                                                    # L39: $LABEL CLEAR
    gput_scalar!(tm, "F", F); gput_scalar!(tm, "Z", Z)
    return tm
end


"""
    dynslite_reduce!(tm, rtps_off, rtpcs_out, rhs_comprd) -> nothing

dynslite.vda REDUCE (pp_reduce.red L188), on pp_reduce's sets in progress (passed) and the others in
`tm`: the timeslices turned off leave the model's sets.

    RTPS_OFF(RTP(R,T,P),S)\$PRC_TS(R,P,S) \$= NORTS(R,T,S);
    RTPCS_OUT(RTP(R,T,P),C,S)\$RPCS_VAR(R,P,C,S) \$= NORTS(R,T,S);
    RTCS_VARC(R,T,C,S)\$NORTS(R,T,S) = NO; RCS_COMBAL(R,T,C,S,BD)\$NORTS(R,T,S) = NO; RCS_COMPRD(...) = NO;
    RHS_COMBAL(R,T,C,S)\$NORTS(R,T,S) = NO; RHS_COMPRD(...) = NO; RTX_MARK(R,T,ITEM,C,BD,S)\$NORTS(R,T,S) = NO;

GAMS: dynslite.vda L76-86, v4.9.7.
"""
function dynslite_reduce!(tm, rtps_off, rtpcs_out, rhs_comprd)
    dynts_on(tm) || return nothing
    norts = gparam(tm, "NORTS").values
    isempty(norts) && return nothing
    off(r, t, s) = haskey(norts, (r, t, s))
    prc_ts = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(() -> String[], prc_ts, (k[1], k[2])), k[3]), gset(tm, "PRC_TS").keys)
    rpcs = Dict{NTuple{2,String},Vector{NTuple{2,String}}}()
    foreach(k -> push!(get!(() -> NTuple{2,String}[], rpcs, (k[1], k[2])), (k[3], k[4])), gset(tm, "RPCS_VAR").keys)
    for (r, t, p) in gset(tm, "RTP").keys
        foreach(s -> off(r, t, s) && push!(rtps_off, (r, t, p, s)), get(prc_ts, (r, p), String[]))
        foreach(((c, s),) -> off(r, t, s) && push!(rtpcs_out, (r, t, p, c, s)), get(rpcs, (r, p), NTuple{2,String}[]))
    end
    for (name, N, si) in (("RTCS_VARC", 4, 4), ("RCS_COMBAL", 5, 4), ("RCS_COMPRD", 5, 4), ("RHS_COMBAL", 4, 4), ("RTX_MARK", 6, 6))
        m = gmembers(tm, name, N)
        n0 = length(m)
        filter!(k -> !off(k[1], k[2], k[si]), m)
        length(m) == n0 || gput!(tm, name, m)
    end
    filter!(k -> !off(k[1], k[2], k[4]), rhs_comprd)
    return nothing
end


"""
    dynslite_postlev!(tm) -> tm

dynslite.vda POSTLEV (ppm_ext.vda L169), when %RTS% is S+NORTS(R,T,S) and NORTS has records:

    RVP(RTP(R,V,P))\$PRC_VINT(R,P)\$=PRC_TSL(R,P,'ANNUAL');
    OPTION FIL<DATAYEAR; DATAYEAR(LL)=LASTLL(LL);
    FLO_FUNC(R,LL--ORD(LL),P,CG,CG2,ANNUAL)\$(FLO_FUNC(R,LL,P,CG,CG2,ANNUAL)\$RVP(R,LL,P))=3;
    \$BATINCLUDE fillparm FLO_FUNC ...;  RVP(R,V,P)\$(NOT RPS_S1(R,P,'ANNUAL')) = NO;
    ACT_EFF, ACT_FLO, FLO_SUM likewise, and fillparm on each;
    OPTION DATAYEAR<FIL;

then the CLEAR block (`dynslite_clear!`). The re-interpolation of the ANNUAL data of vintaged
processes at the ANNUAL level (M1.3 change 68): each such row of FLO_FUNC, ACT_EFF, ACT_FLO and
FLO_SUM gets option 3 at year '0' and is interpolated and extrapolated again over the vintages of
RVP by fillparm.gms with a write cache; L54 then resets the options (MIN(0,3), so they go). With
no such row the fillparm calls leave UNCD7 empty; FIL keeps the data years.

GAMS: dynslite.vda L88-104, L39-73; fillparm.gms L20-56, v4.9.7.
"""
function dynslite_postlev!(tm)
    dynts_on(tm) || return tm
    isempty(gparam(tm, "NORTS").values) && return tm
    vint, tsl = gset(tm, "PRC_VINT").members, gset(tm, "PRC_TSL").members
    # L92: RVP(RTP(R,V,P))$PRC_VINT(R,P)$=PRC_TSL(R,P,'ANNUAL')
    rvp = Set{NTuple{3,String}}(k for k in gset(tm, "RTP").keys if (k[1], k[3]) in vint && (k[1], k[3], "ANNUAL") in tsl)
    # L93: OPTION FIL<DATAYEAR; DATAYEAR(LL)=LASTLL(LL): the macros below take as rows only the records at the
    #   last ALLYEAR element ('0', initmty.mod L369), the options the lines L94, L97-99 set
    datayear = Set{String}(k[1] for k in gset(tm, "DATAYEAR").keys)
    gput!(tm, "FIL", Set{Tuple{String}}((y,) for y in datayear))
    st = InterpState(tm; reset=0.0)                                                      # $SET RESET 0 (L91)
    lastll = last(st.ax.years)
    st.datayear = Set([lastll])
    V = [k[1] for k in gset(tm, "MODLYEAR").keys]
    cond(k) = (k[1], k[2], k[3]) in rvp                                                  # %6: RVP(R,V,P)
    pos = (d, k) -> d > 0                                                                # %7: '>0'
    # X(R,LL--ORD(LL),P,...,ANNUAL)$(X(R,LL,P,...,ANNUAL)$RVP(R,LL,P)) = 3: option 3 (interpolation and
    #   extrapolation, fillparm.gms L45-50) on each row with ANNUAL data at a vintage of RVP
    function mark!(name, N)
        P = gvalues(tm, name, N)
        put = [Base.setindex(k, lastll, 2) for k in keys(P) if k[N] == "ANNUAL" && (k[1], k[2], k[3]) in rvp]
        isempty(put) && return
        foreach(k -> (P[k] = 3.0), put)
        gput!(tm, name, P)
    end
    # L94-95: FLO_FUNC, then fillparm with the write cache X_RPGGS
    mark!("FLO_FUNC", 6)
    fillparm!(st, "FLO_FUNC", "R", "P,CG,CG2,ANNUAL", ["", ""], V, cond, pos; cache=true)
    # L96: RVP(R,V,P)$(NOT RPS_S1(R,P,'ANNUAL')) = NO
    rps_s1 = gset(tm, "RPS_S1").members
    filter!(k -> (k[1], k[3], "ANNUAL") in rps_s1, rvp)
    # L97-99: the options of ACT_EFF, ACT_FLO and FLO_SUM; L100-102: fillparm on each (X_RPGS, X_RPGCGS)
    mark!("ACT_EFF", 5); mark!("ACT_FLO", 5); mark!("FLO_SUM", 7)
    fillparm!(st, "ACT_EFF", "R", "P,CG,ANNUAL", ["", "", ""], V, cond, pos; cache=true)
    fillparm!(st, "ACT_FLO", "R", "P,CG,ANNUAL", ["", "", ""], V, cond, pos; cache=true)
    fillparm!(st, "FLO_SUM", "R", "P,CG1,C,CG2,ANNUAL", [""], V, cond, pos; cache=true)
    put_interp_scratch!(st)
    # L103: OPTION DATAYEAR<FIL (DATAYEAR as it was; FIL keeps it)
    dynslite_clear!(tm)                                                                  # $GOTO CLEAR
    return tm
end


"Whether dynslite.vda BOUNDS runs (bndmain.mod L87): %RTS% is S+NORTS(R,T,S) and NORTS has records."
dynslite_bounds_on(tm) = dynts_on(tm) && !isempty(gparam(tm, "NORTS").values)

"""
    dynslite_bounds_data!(tm) -> tm

The data statements of dynslite.vda BOUNDS (bndmain.mod L87):

    OPTION RTC_NET<RHS_COMBAL,RTC_PRD<RHS_COMPRD;
    \$IF %VAR_UC%==YES UC_RHSMAP(R,T,UCN,UC_NUMBER,S)\$NORTS(R,T,S) = NO;

GAMS: dynslite.vda L108, L120, v4.9.7.
"""
function dynslite_bounds_data!(tm)
    dynslite_bounds_on(tm) || return tm
    gput!(tm, "RTC_NET", Set{NTuple{3,String}}((k[1], k[2], k[3]) for k in gset(tm, "RHS_COMBAL").keys))
    gput!(tm, "RTC_PRD", Set{NTuple{3,String}}((k[1], k[2], k[3]) for k in gset(tm, "RHS_COMPRD").keys))
    if var_uc(tm)
        norts = gparam(tm, "NORTS").values
        m = gmembers(tm, "UC_RHSMAP", 5)
        n0 = length(m)
        filter!(k -> !haskey(norts, (k[1], k[2], k[5])), m)
        length(m) == n0 || gput!(tm, "UC_RHSMAP", m)
    end
    return tm
end

"""
    bnd_dynslite!(bt, tm) -> bt

The bounds of dynslite.vda BOUNDS (bndmain.mod L87): every activity, flow, trade, storage,
dispatching and commodity-net variable of a timeslice turned off in a period of RT_PP is fixed at 0:

    VAR_ACT.FX(RTP_VINTYR(R,V,T,P),S)\$(RT_PP(R,T)\$NORTS(R,T,S)\$PRC_TS(R,P,S)) = 0;
    VAR_FLO, VAR_IRE, VAR_SIN, VAR_SOUT (\$RPCS_VAR(R,P,C,S)); VAR_UPS (\$RPS_UPS(R,P,S));
    VAR_UPT (\$RPS_UPS(R,P,S)\$RP_DP(R,P)); VAR_UDP (\$PRC_TS(R,P,S)\$RP_UPR(R,P,BD));
    VAR_COMNET.FX(RTC_NET(R,T,C),S)\$(...\$COM_TS(R,C,S)) = 0; VAR_COMPRD likewise with RTC_PRD;

with `%MODEL_NAME%.HOLDFIXED=1` (`holdfixed!`). Set on the columns the rows made.

GAMS: dynslite.vda L106-119, v4.9.7.
"""
function bnd_dynslite!(bt, tm)
    dynslite_bounds_on(tm) || return bt
    S(n) = gset(tm, n).members
    norts = gparam(tm, "NORTS").values
    rt_pp = S("RT_PP")
    off(r, t, s) = (r, t) in rt_pp && haskey(norts, (r, t, s))
    prc_ts, rpcs_var, rps_ups, rp_dp, rp_upr = S("PRC_TS"), S("RPCS_VAR"), S("RPS_UPS"), S("RP_DP"), S("RP_UPR")
    rtc_net, rtc_prd, com_ts = S("RTC_NET"), S("RTC_PRD"), S("COM_TS")
    function fx(name, cond)
        haskey(tm.vars.families, name) || return
        for k in tm.vars.families[name].keys
            cond(k) || continue
            get!(() -> Dict{Tuple,Tuple{Float64,Float64}}(), bt.recs, name)[k] = (0.0, 0.0)
            delete!(get(bt.eps, name, Dict{Tuple,Tuple{Bool,Bool}}()), k)          # .FX = 0, not EPS
        end
    end
    fx("VAR_ACT", k -> off(k[1], k[3], k[5]) && (k[1], k[4], k[5]) in prc_ts)
    for n in ("VAR_FLO", "VAR_SIN", "VAR_SOUT")
        fx(n, k -> off(k[1], k[3], k[6]) && (k[1], k[4], k[5], k[6]) in rpcs_var)
    end
    fx("VAR_IRE", k -> off(k[1], k[3], k[6]) && (k[1], k[4], k[5], k[6]) in rpcs_var)
    fx("VAR_UPS", k -> off(k[1], k[3], k[5]) && (k[1], k[4], k[5]) in rps_ups)
    fx("VAR_UPT", k -> off(k[1], k[3], k[5]) && (k[1], k[4], k[5]) in rps_ups && (k[1], k[4]) in rp_dp)
    fx("VAR_UDP", k -> off(k[1], k[3], k[5]) && (k[1], k[4], k[5]) in prc_ts && (k[1], k[4], k[6]) in rp_upr)
    fx("VAR_COMNET", k -> off(k[1], k[2], k[4]) && (k[1], k[2], k[3]) in rtc_net && (k[1], k[3], k[4]) in com_ts)
    fx("VAR_COMPRD", k -> off(k[1], k[2], k[4]) && (k[1], k[2], k[3]) in rtc_prd && (k[1], k[3], k[4]) in com_ts)
    return bt
end

"""
    holdfixed!(tm) -> Int

`%MODEL_NAME%.HOLDFIXED=1` (dynslite.vda L111): GAMS generates the model with every fixed variable
(lower bound = upper bound, at any value; an EPS bound is not equal to a 0 bound there, so a variable
between 0 and EPS stays: the bound table's `eps`) as a constant. Each such column's terms move to the
right-hand side of its rows, and the column leaves the model; a row left with no column is not
generated (its constant must hold). Returns the number of columns held.

GAMS: dynslite.vda L111, v4.9.7.
"""
function holdfixed!(tm)
    m = tm.model
    bt = bndmain(tm)
    fixed = Dict{JuMP.VariableRef,Float64}()
    for (name, f) in tm.vars.families
        ef = get(bt.eps, name, Dict{Tuple,Tuple{Bool,Bool}}())
        for (k, v) in f.refs
            (JuMP.has_lower_bound(v) && JuMP.has_upper_bound(v)) || continue
            lo, up = JuMP.lower_bound(v), JuMP.upper_bound(v)
            le, ue = get(ef, k, (false, false))
            (lo == up && le == ue) && (fixed[v] = lo)
        end
    end
    isempty(fixed) && return 0
    empty = JuMP.ConstraintRef[]
    for (F, Sx) in JuMP.list_of_constraint_types(m)
        F <: JuMP.GenericAffExpr || continue
        for con in JuMP.all_constraints(m, F, Sx)
            f = JuMP.constraint_object(con).func
            shift = 0.0
            for (v, a) in f.terms
                haskey(fixed, v) && (shift += a * fixed[v])
            end
            shift == 0 || JuMP.set_normalized_rhs(con, JuMP.normalized_rhs(con) - shift)
            all(v -> haskey(fixed, v), keys(f.terms)) && push!(empty, con)
        end
    end
    foreach(c -> JuMP.delete(m, c), empty)
    for f in values(tm.vars.families)
        filter!(k -> !haskey(fixed, f.refs[k]), f.keys)
        filter!(((k, v),) -> !haskey(fixed, v), f.refs)
    end
    JuMP.delete(m, collect(keys(fixed)))
    return length(fixed)
end


"""
    rts_off(tm) -> Function

`(r, t, s) -> Bool`: whether RTS(S), that is S+NORTS(R,T,S) with dynamic timeslices (timslice.mod
L33), has no element: NORTS(R,T,S) is -INF. An equation over RTS(S) has no row there. Always false
when %RTS% is S.
"""
function rts_off(tm)
    norts = gparam_opt(tm.data, "NORTS", 3).values
    (dynts_on(tm) && !isempty(norts)) || return (r, t, s) -> false
    return (r, t, s) -> haskey(norts, (r, t, s))
end
