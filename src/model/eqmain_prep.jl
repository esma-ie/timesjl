# M1.3 change 25-3: the data statements of eqmain.mod after the objective (the equation
# includes' own preparation, RVPT, the user-constraint maps) and of equ_ext.vda, the third part
# of the coef -> pre-solve step.
#
# In eqmain.mod order (v4.9.7): eqcapact.mod L18-20 (AFS, in the `L` include, L65), eqbndcst.mod
# L14-77 (L192: SUPERYR, the cumulative cost limits, YK1), L199-202 (RVPT, RTP_OFF), L205-226 (the
# user-constraint maps); then equ_ext.vda L76-79 (RP_PL, AFS) and eqactups.vda L33 (RP_UPR, outside
# the dispatching IF, so in every model). The other includes have no data
# statements that act here: eqflomrk.mod, eqashar.vda and pp_actef.vda jump to their equations
# under the arguments eqmain.mod and equ_ext.vda pass.
#
# Not translated (UnportedError): eqbndcst.mod L41-75 with REG_BNDCST or REG_CUMCST data (the
# cost bounds, refused with EQ_BNDCST); eqactups.vda L9-33, the dispatching preparation, with
# RP_UPL, RP_PL or ACT_CSTRMP data (refused with its equations); VAR_UC not YES (L205-206).

"""
    eqmain_prep_unported(tm) -> Vector{String}

The data that would take eqmain.mod / equ_ext.vda preparation not translated.
"""
function eqmain_prep_unported(tm::TimesModel)
    d = tm.data
    out = String[]
    (!isempty(gparam_opt(d, "REG_BNDCST", 5)) || !isempty(gparam_opt(d, "REG_CUMCST", 6))) &&
        push!(out, "eqbndcst.mod L41-75: REG_BNDCST / REG_CUMCST data")
    (!isempty(gset_opt(d, "RP_UPL", 3)) || !isempty(gset_opt(d, "RP_PL", 3)) ||
     !isempty(gparam_opt(d, "ACT_CSTRMP", 5))) && push!(out, "eqactups.vda L9-33: dispatching (RP_UPL, RP_PL, ACT_CSTRMP)")
    has_uc = !isempty(gparam_opt(d, "UC_RHS", 2)) || !isempty(gparam_opt(d, "UC_RHSR", 3)) ||
             !isempty(gparam_opt(d, "UC_RHST", 3)) || !isempty(gparam_opt(d, "UC_RHSRT", 4)) ||
             !isempty(gparam_opt(d, "UC_RHSTS", 4)) || !isempty(gparam_opt(d, "UC_RHSRTS", 5))
    (has_uc && !var_uc(tm)) && push!(out, "eqmain.mod L205-226: user constraints with VAR_UC not YES")
    return out
end

"""
    eqmain_prep_symbols(tm) -> Vector{String}

The sets and parameters eqmain_prep! settles.
"""
eqmain_prep_symbols(tm) = ["AFS", "SUPERYR", "YK1", "RT_IAN", "RTP_IAN", "CST_ANNC", "RVPT", "RTP_OFF", "UC_TMAP",
                           "UC_RHSMAP", "UC_RTSUC", "UC_UT", "UC_UTS", "UC_RHSTMP", "RUCTS", "RP_PL", "RP_UPR"]

"""
    eqmain_prep!(tm) -> tm

    AFS: LOOP(V,AFS(RTP_VARA(R,T,P),S,BD)\$COEF_AF(R,V,T,P,S,BD)=YES); AFS(RTPS_OFF,BD) = NO;   (eqcapact.mod L20)
    SUPERYR(PERIODYR(T,LL))\$(YEARVAL(LL) LE YEARVAL(T)) = YES;                                (eqbndcst.mod L38)
    SUPERYR(T+1,LL)\$((YEARVAL(LL) GT YEARVAL(T))\$PERIODYR(T,LL)) = YES;                       (L39)
    LOOP(MIYR_1(T++1),SUPERYR(T,LL)\$(YEARVAL(LL) GT M(T)) = YES);                            (L40)
    [L41-75 without cost-bound data: RT_IAN, RTP_IAN, CST_ANNC stay empty;
     OPTION CLEAR=YK1; YK1(TT,T)\$YK(T,TT) = YES (L50); TRACKP cleared (L62, L75)]
    LOOP(OBJ_2A(R,T,P)\$(NOT RTP_OFF(R,T,P)),F=B(T)+NCAP_ILED(R,T,P); Z=SUM(VNT(T,TT)\$(F>E(TT)+0.5),1);
      RVPT(R,T,P,T+Z) = YES);                                                                 (eqmain.mod L200-201)
    RTP_OFF(OBJ_2A(R,T,P))\$(NOT SUM(RVPT(R,T,P,TT),1)) = YES;                               (L202)
    [UC_TMAP, UC_RHSMAP, UC_RTSUC, UC_UT, UC_UTS: `uc_tmap`, `uc_setup`; UC_RHSTMP, RUCTS cleared] (L211-226)
    RP_PL(RP,BD)\$SUM(RPG_PACE(RP,CG),1) = NO;                                                (equ_ext.vda L77)
    AFS(RTP(R,T,P),S,BDUPX)\$NCAP_AFCS(RTP,'ACT',S) = NO;                                      (L79)
    OPTION RP_UPR < ACT_CSTRMP;                                                               (eqactups.vda L33)

GAMS: eqcapact.mod L18-20, eqbndcst.mod L14-77, eqmain.mod L197-226, equ_ext.vda L76-79, v4.9.7.
"""
function eqmain_prep!(tm::TimesModel)
    u = eqmain_prep_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    d = tm.data
    S(name, n) = gset_opt(d, name, n)
    P(name, n) = gparam_opt(d, name, n)
    yv = gparam(tm, "YEARVAL")
    yval(y) = gv(yv, (y,)).v
    T = S("MILESTONYR", 1)
    tlist = [k[1] for k in T.keys]
    tpos = Dict(t => i for (i, t) in enumerate(tlist))

    # eqcapact.mod L20 (the L include): AFS
    rtp_vara = S("RTP_VARA", 3)
    afs = Set{NTuple{5,String}}()
    for (r, v, t, p, s, bd) in P("COEF_AF", 6).keys
        (r, t, p) in rtp_vara && push!(afs, (r, t, p, s, bd))
    end
    rtps_off = S("RTPS_OFF", 4)
    filter!(k -> !((k[1], k[2], k[3], k[4]) in rtps_off), afs)

    # eqbndcst.mod L38-40: SUPERYR
    superyr = gmembers(tm, "SUPERYR", 2)
    periodyr = S("PERIODYR", 2)
    for (t, ll) in periodyr
        haskey(tpos, t) || continue
        yval(ll) <= yval(t) && push!(superyr, (t, ll))
        i = tpos[t]
        (yval(ll) > yval(t) && i < length(tlist)) && push!(superyr, (tlist[i+1], ll))
    end
    M = P("M", 1)
    miyr_1 = S("MIYR_1", 1)
    for (i, t) in enumerate(tlist)                                         # LOOP(MIYR_1(T++1), ...)
        (tlist[mod1(i + 1, length(tlist))],) in miyr_1 || continue
        for y in (k[1] for k in S("ALLYEAR", 1).keys)
            yval(y) > gv(M, (t,)).v && push!(superyr, (t, y))
        end
    end
    gput!(tm, "SUPERYR", superyr)
    # L50: OPTION CLEAR=YK1; YK1(TT,T)$YK(T,TT) = YES (T, TT milestone years)
    yk1 = Set((tt, t) for (t, tt) in S("YK", 2) if haskey(tpos, t) && haskey(tpos, tt))
    gput!(tm, "YK1", yk1)
    gput!(tm, "RT_IAN", Set{NTuple{5,String}}()); gput!(tm, "RTP_IAN", Set{NTuple{4,String}}())
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())

    # eqmain.mod L199-202: RVPT, RTP_OFF
    B, E = P("B", 1), P("E", 1)
    iled = P("NCAP_ILED", 3)
    rtp_off = gmembers(tm, "RTP_OFF", 3)
    vnt_of = indexby(S("VNT", 2), (1,))
    rvpt = Set{NTuple{4,String}}()
    obj_2a = collect(S("OBJ_2A", 3).keys)
    for (r, t, p) in obj_2a
        (haskey(tpos, t) && !((r, t, p) in rtp_off)) || continue
        f = gv(B, (t,)).v + gv(iled, (r, t, p)).v
        z = count(((_, tt),) -> haskey(tpos, tt) && f > gv(E, (tt,)).v + 0.5, get(vnt_of, (t,), NTuple{2,String}[]))
        j = tpos[t] + z
        j <= length(tlist) && push!(rvpt, (r, t, p, tlist[j]))
    end
    has_rvpt = Set((k[1], k[2], k[3]) for k in rvpt)
    for (r, t, p) in obj_2a
        (haskey(tpos, t) && !((r, t, p) in has_rvpt)) && push!(rtp_off, (r, t, p))
    end
    gput!(tm, "RVPT", rvpt); gput!(tm, "RTP_OFF", rtp_off)

    # eqmain.mod L211-226: the user-constraint maps
    delete!(tm.cache, "UC_SETUP"); delete!(tm.cache, "UC_TMAP"); delete!(tm.cache, "UC_TMAP/t")
    gput!(tm, "UC_TMAP", Set(uc_tmap(tm).keys))
    setup = uc_setup(tm)
    gput!(tm, "UC_RHSMAP", Set(setup.rhsmap.keys)); gput!(tm, "UC_RTSUC", Set(setup.rtsuc.keys))
    gput!(tm, "UC_UT", Set(setup.ut.keys)); gput!(tm, "UC_UTS", Set(setup.uts.keys))
    gput!(tm, "UC_RHSTMP", Set{NTuple{5,String}}()); gput!(tm, "RUCTS", Set{NTuple{4,String}}())
    if !isempty(P("UC_RHSRT", 4))                                           # L219, inside the IF
        gput!(tm, "R_UC", Set{NTuple{2,String}}()); gput!(tm, "R_UCT", Set{NTuple{3,String}}())
    end

    # equ_ext.vda L77, L79
    pace = Set((k[1], k[2]) for k in S("RPG_PACE", 3))
    rp_pl = filter(k -> !((k[1], k[2]) in pace), gmembers(tm, "RP_PL", 3))
    gput!(tm, "RP_PL", rp_pl)
    afcs, rtp = P("NCAP_AFCS", 5), S("RTP", 3)
    filter!(k -> !(k[5] in ("UP", "FX") && (k[1], k[2], k[3]) in rtp && haskey(afcs, (k[1], k[2], k[3], "ACT", k[4]))), afs)
    gput!(tm, "AFS", afs)
    # eqactups.vda L33 (equ_ext.vda L90), outside the dispatching IF of L9-32: OPTION RP_UPR < ACT_CSTRMP
    gput!(tm, "RP_UPR", Set((k[1], k[3], k[4]) for k in P("ACT_CSTRMP", 5).keys))
    return tm
end
