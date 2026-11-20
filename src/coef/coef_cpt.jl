# M1.2 (1): the start of the coefficient stage and the capacity-transfer and
# availability coefficients.
#
# GAMS (v4.9.7): maindrv.mod L70 (DISCSHIFT, a compile-time setting used by
# coef_obj.mod), coefmain.mod L11 (SOW, SW_T), coef_cpt.mod L13-63, and
# pp_shapr.mod L15-46 for its two includes (L48, L59).
#
# Shaped availabilities (M1.3 change 66): pp_shapr.mod shapes an attribute
# for the (R,V,P) with a shape index >= 1.5 in NCAP_AFX/NCAP_AFSX or a
# multiplier index in NCAP_AFM/NCAP_AFSM (L19-20), averaging the SHAPE row
# over the years each vintage still operates in each period, times its MULTI
# row (L22-40, `pp_shapr!`); NCAP_AFX and NCAP_AFM also drive TRACKP
# (coef_cpt.mod L42-47) and NCAP_AFSX and NCAP_AFSM (L55-58). Checked on the
# crafted case demo12_afshp. %STAGES% (L11) and %VALIDATE% (L23) are refused
# as in M1.1.

"""
    ctst(tm) -> String

The value of `%CTST%` (initmty.mod L426-430): `'**EPS'` for OBJ ALT or LIN,
`'**0'` when OBLONG is YES (OBJ MOD sets OBLONG, L427), `''` otherwise; the
last applicable line wins, comparisons case-insensitive (`\$IFI`).
"""
function ctst(tm)
    obj = uppercase(gswitch(tm, "OBJ", ""))
    oblong = uppercase(gswitch(tm, "OBLONG", "")) == "YES" || obj == "MOD"
    c = ""
    obj == "ALT" && (c = "**EPS")
    oblong && (c = "**0")
    obj == "LIN" && (c = "**EPS")
    return c
end

"""
    coef_cpt_unported(tm) -> Vector{String}

The coef_cpt.mod / coefmain.mod paths this model would take that are not
translated (see the file header); empty when coef_cpt! can run.
"""
function coef_cpt_unported(tm)
    out = String[]
    yes(n) = uppercase(gswitch(tm, n, "")) == "YES"
    yes("STAGES") && push!(out, "coefmain.mod L11 (STAGES YES)")
    yes("VALIDATE") && push!(out, "coef_cpt.mod L23 (VALIDATE YES)")
    isempty(gset_opt(tm.data, "RTP_ISHPR", 3)) ||
        push!(out, "pp_shapr.mod L19-40 (RTP_ISHPR not empty on entry)")
    return out
end

"""
    coef_cpt!(tm) -> tm

Run maindrv.mod L70, coefmain.mod L11 and coef_cpt.mod L13-63 (with
pp_shapr.mod for L48 and L59) on the GAMS state in `tm` (the ppm dump),
storing every set and parameter they assign: SOW, SW_T, B, E, M, D, FIL,
PASTSUM, COEF_CPT, MY_TS, NCAP_AF, NCAP_AFS, TRACKP, NCAP_AFBX, FIL2,
RTP_ISHPR, COEF_AF, RP_PRC and RTPS_BD.

GAMS: coefmain.mod L11; coef_cpt.mod L13-63; pp_shapr.mod L15-46, v4.9.7.
"""
function coef_cpt!(tm)
    u = coef_cpt_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    S1(name) = gset(tm, name)
    milestonyr, modlyear = S1("MILESTONYR"), S1("MODLYEAR")
    inT(t) = (t,) in milestonyr
    inV(v) = (v,) in modlyear

    # coefmain.mod L11: SOW(ALLSOW)=DIAG(ALLSOW,'1'); SW_T(T,ALLSOW)=SOW(ALLSOW)
    allsow = S1("ALLSOW")
    sow = Set{NTuple{1,String}}(k for k in allsow.keys if k[1] == "1")
    gput!(tm, "SOW", sow)
    sw_t = Set(k for k in gmembers(tm, "SW_T", 2) if !inT(k[1]))
    for (t,) in milestonyr.keys, (w,) in sow
        push!(sw_t, (t, w))
    end
    gput!(tm, "SW_T", sw_t)

    # L13-16: copy the period values into the years within the period
    B, E, M, D = (gvalues(tm, n, 1) for n in ("B", "E", "M", "D"))
    phyr, vnt = S1("PHYR"), S1("VNT")
    for (t, v) in S1("PERIODYR").keys
        (inT(t) && inV(v)) || continue
        (!((v,) in phyr) && (v, t) in vnt) || continue
        for P in (B, E, M, D)
            x = get(P, (t,), nothing)
            x === nothing ? delete!(P, (v,)) : (P[(v,)] = x)
        end
    end
    for (n, P) in zip(("B", "E", "M", "D"), (B, E, M, D))
        gput!(tm, n, P)
    end
    gvB(y) = gv(gparam(tm, "B"), (y,))
    gvE(y) = gv(gparam(tm, "E"), (y,))
    gvD(y) = gv(gparam(tm, "D"), (y,))

    # L18-24: capacity transfer, only when %CTST% is '' (G23: 0**0 = 0**EPS = 1)
    fil = ctst(tm) == "" ? Set{NTuple{1,String}}(modlyear.keys) : Set{NTuple{1,String}}()
    gput!(tm, "FIL", fil)
    pastsum = gvalues(tm, "PASTSUM", 3)
    coef_cpt = gvalues(tm, "COEF_CPT", 4)
    if !isempty(fil)
        prc_cap = S1("PRC_CAP")
        iled, rpti, tlife = gparam(tm, "NCAP_ILED"), gparam(tm, "COEF_RPTI"), gparam(tm, "NCAP_TLIFE")
        for (r, v, p) in S1("RTP").keys                                   # L19
            ((v,) in fil && (r, p) in prc_cap) || continue
            gassign!(pastsum, (r, v, p), gvB(v) + gv(iled, (r, v, p)) + gv(rpti, (r, v, p)) * gv(tlife, (r, v, p)))
        end
        for (r, v, t, p) in S1("RTP_CPTYR").keys                          # L20-21
            ((v,) in fil && inT(t) && haskey(pastsum, (r, v, p))) || continue
            ps = gv(pastsum, (r, v, p))
            x = gmax(GZERO, (gmin(gvE(t) + 1, ps) - gmax(gvB(v) + gv(iled, (r, v, p)), gvB(t))) / gvD(t))
            gassign!(coef_cpt, (r, v, t, p), x)
        end
    end
    gput!(tm, "COEF_CPT", coef_cpt)
    gput!(tm, "PASTSUM", empty!(pastsum))                                  # L24

    # L28-32: NCAP_AF as the minimum of NCAP_AF and NCAP_AFS at the same timeslice
    annual = S1("ANNUAL")
    my_ts = Set{NTuple{1,String}}(k for k in S1("ALL_TS").keys if !(k in annual))
    gput!(tm, "MY_TS", my_ts)
    rtp, prc_ts, rps_prcts = S1("RTP"), S1("PRC_TS"), S1("RPS_PRCTS")
    af, afs = gvalues(tm, "NCAP_AF", 5), gvalues(tm, "NCAP_AFS", 5)
    afs_p = gparam(tm, "NCAP_AFS")
    for k in afs_p.keys                                                    # L29
        (r, v, p, s, bd) = k
        ((r, v, p) in rtp && inV(v) && (s,) in my_ts && (r, p, s) in prc_ts) || continue
        a = gv(af, k)
        gassign!(af, k, gmin(a + gif(Inf, iszero(a)), gv(afs_p, k)))      # NOT a: a is 0, not EPS (G25)
    end
    for (r, v, p, s, bd) in afs_p.keys                                     # L30
        (bd == "FX" && (r, v, p) in rtp && inV(v) && (r, p, s) in prc_ts) || continue
        delete!(af, (r, v, p, s, "LO")); delete!(af, (r, v, p, s, "UP"))
    end
    for (r, v, p, s, bd) in afs_p.keys                                     # L32
        ((r, v, p) in rtp && inV(v) && (s,) in my_ts) || continue
        ((r, p, s) in prc_ts || !((r, p, s) in rps_prcts)) && delete!(afs, (r, v, p, s, bd))
    end
    gput!(tm, "NCAP_AF", af)
    gput!(tm, "NCAP_AFS", afs)

    prc_cap, prc_vint = S1("PRC_CAP"), S1("PRC_VINT")
    ax = YearAxis(tm)
    bds = [k[1] for k in S1("BD").keys]
    # A value as GAMS reads it (absent 0, a stored 0 EPS)
    val(d, k) = (x = get(d, k, nothing); x === nothing ? GZERO : x == 0.0 ? GEPS : GNum(x))
    # L42: NCAP_AFX(R,LL--ORD(LL),P) $= NCAP_AFM(R,LL,P): LL--ORD(LL) lags each LL circularly by its own
    #   position, onto the last element of ALLYEAR ('0', G31), so NCAP_AFX(R,'0',P) takes the NCAP_AFM of
    #   the last LL (in ALLYEAR order) that has one (a record is not 0, so $= writes it, G24): a mark of
    #   the processes with an NCAP_AFM
    afx = gvalues(tm, "NCAP_AFX", 3)
    afm = gvalues(tm, "NCAP_AFM", 3)
    lastll = last(ax.years)
    for k in sort!(collect(keys(afm)); by=k -> ax.pos[k[2]])
        afx[(k[1], lastll, k[3])] = afm[k]
    end
    gput!(tm, "NCAP_AFX", afx)
    # L43: OPTION TRACKP < NCAP_AFX; L44: TRACKP(RP)$(NOT PRC_CAP(RP)) = NO; L45: TRACKP(RP)$RP_UPL(RP,'FX') = NO;
    #   L46: TRACKP(PRC_CAP(PRC_VINT)) = YES
    rp_upl = S1("RP_UPL")
    trackp = Set{NTuple{2,String}}((k[1], k[3]) for k in keys(afx))
    filter!(k -> k in prc_cap && !((k[1], k[2], "FX") in rp_upl), trackp)
    foreach(k -> k in prc_cap && push!(trackp, k), prc_vint.keys)
    gput!(tm, "TRACKP", trackp)
    # L47: NCAP_AFBX(RTP(R,V,P),BD)$(RP_AFB(R,P,BD)>0) $= NCAP_AFX(RTP)
    afb = gparam(tm, "RP_AFB")
    afbx = gvalues(tm, "NCAP_AFBX", 4)
    for (r, v, p) in rtp.keys
        (inV(v) && haskey(afx, (r, v, p))) || continue
        foreach(bd -> gv(afb, (r, p, bd)).v > 0 && (afbx[(r, v, p, bd)] = afx[(r, v, p)]), bds)
    end

    # L48: pp_shapr.mod NCAP_AF (R,V,P,S,BD) "TRACKP*RP_AFB*PRC_TS" COEF_AF(...) NCAP_AFM B
    coef_af = gvalues(tm, "COEF_AF", 6)
    rtp_cptyr = [k for k in S1("RTP_CPTYR").keys if inV(k[2]) && inT(k[3])]
    ts_of_rp = indexby(prc_ts, (1, 2))
    bd_of_rp = indexby(afb, (1, 2))
    af_p = gparam(tm, "NCAP_AF")
    # %3: TRACKP(R,P)*RP_AFB(R,P,BD)*PRC_TS(R,P,S), the (S,BD) each (R,V,P) is assigned at
    cands_af(r, v, p) = (r, p) in trackp ?
        [(s, bd) for (_, _, s) in get(ts_of_rp, (r, p), NTuple{3,String}[]) for (_, _, bd) in get(bd_of_rp, (r, p), NTuple{3,String}[])] :
        NTuple{2,String}[]
    pp_shapr!(tm, coef_af, rtp_cptyr, afbx, afm, af_p, cands_af; ax, bds)
    gput!(tm, "NCAP_AFBX", afbx)

    # L50-52: non-vintaged processes take the period's NCAP_AF; NCAP_AFA at ANNUAL
    trackp = Set{NTuple{2,String}}(k for k in prc_cap.keys if !(k in trackp))   # TRACKP ⊆ PRC_CAP here
    gput!(tm, "TRACKP", trackp)
    af_of_rtp = indexby(af_p, (1, 2, 3))
    afa = gparam(tm, "NCAP_AFA")
    afa_of_rtp = indexby(afa, (1, 2, 3))
    for (r, v, t, p) in rtp_cptyr
        if (r, p) in trackp                                                # L51
            for k in get(af_of_rtp, (r, t, p), NTuple{5,String}[])
                (r, p, k[4]) in prc_ts || continue
                gassign!(coef_af, (r, v, t, p, k[4], k[5]), gv(af_p, k))
            end
        end
        if (r, p) in prc_cap                                               # L52
            for k in get(afa_of_rtp, (r, t, p), NTuple{4,String}[]), (a,) in annual.keys
                gassign!(coef_af, (r, v, t, p, a, k[4]), gv(afa, k))
            end
        end
    end

    # L55: OPTION RP_PRC < NCAP_AFSM; NCAP_AFSM(R,V,P)$(NOT RP_PRC(R,P)) $= NCAP_AFM(R,V,P)
    afsm = gvalues(tm, "NCAP_AFSM", 3)
    rp_prc = Set{NTuple{2,String}}((k[1], k[3]) for k in keys(afsm))
    reg = S1("R")
    for (k, x) in afm
        ((k[1],) in reg && inV(k[2]) && !((k[1], k[3]) in rp_prc)) && (afsm[k] = x)
    end
    gput!(tm, "NCAP_AFSM", afsm)
    # L56: NCAP_AFSX(RTP,BD)$NCAP_AFSM(RTP) = NCAP_AFSX(RTP,BD)+EPS   (an EPS NCAP_AFSM counts, G3)
    afsx = gvalues(tm, "NCAP_AFSX", 4)
    for (r, v, p) in rtp.keys
        (inV(v) && haskey(afsm, (r, v, p))) || continue
        foreach(bd -> gassign!(afsx, (r, v, p, bd), val(afsx, (r, v, p, bd)) + GEPS), bds)
    end
    # L57: RTPS_BD(RTP(R,V,P),S,BD)$((PRC_VINT(R,P)+ANNUAL(S)+YES$NCAP_AFSX(RTP,BD))$NCAP_AFS(RTP,S,BD)) = YES
    afs_p = gparam(tm, "NCAP_AFS")
    rtps_bd = gmembers(tm, "RTPS_BD", 5)
    for k in afs_p.keys
        (r, v, p, s, bd) = k
        ((r, v, p) in rtp && inV(v)) || continue
        ((r, p) in prc_vint || (s,) in annual || haskey(afsx, (r, v, p, bd))) && push!(rtps_bd, k)
    end
    # L58: OPTION RP_PRC<NCAP_AFSX; NCAP_AFSX(R,V,P,BD)$SUM(RTPS_BD(R,V,P,S,BD),1) $= NCAP_AFX(R,V,P)$(NOT RP_PRC(R,P))
    rp_prc = Set{NTuple{2,String}}((k[1], k[3]) for k in keys(afsx))
    gput!(tm, "RP_PRC", rp_prc)
    for (r, v, p, s, bd) in rtps_bd
        ((r,) in reg && !((r, p) in rp_prc) && haskey(afx, (r, v, p))) && (afsx[(r, v, p, bd)] = afx[(r, v, p)])
    end

    # L59: pp_shapr.mod NCAP_AFS (R,V,P,S,BD) "RTPS_BD(R,V,P,S,BD)" COEF_AF(...) NCAP_AFSM
    sbd_of = Dict{NTuple{3,String},Vector{NTuple{2,String}}}()
    for (r, v, p, s, bd) in sort!(collect(rtps_bd))
        push!(get!(() -> NTuple{2,String}[], sbd_of, (r, v, p)), (s, bd))
    end
    pp_shapr!(tm, coef_af, rtp_cptyr, afsx, afsm, afs_p, (r, v, p) -> get(sbd_of, (r, v, p), NTuple{2,String}[]); ax, bds)
    gput!(tm, "NCAP_AFSX", afsx)

    # L61-62
    afs_of_rtp = indexby(afs_p, (1, 2, 3))
    for (r, v, t, p) in rtp_cptyr
        if (r, p) in prc_cap                                               # L61
            for k in get(afs_of_rtp, (r, t, p), NTuple{5,String}[])
                (r, v, p, k[4], k[5]) in rtps_bd && continue
                gassign!(coef_af, (r, v, t, p, k[4], k[5]), gv(afs_p, k))
            end
        end
        if haskey(afa, (r, t, p, "FX"))                                    # L62
            for (a,) in annual.keys
                delete!(coef_af, (r, v, t, p, a, "LO")); delete!(coef_af, (r, v, t, p, a, "UP"))
            end
        end
    end
    gput!(tm, "COEF_AF", coef_af)

    # L63: OPTION CLEAR=TRACKP,CLEAR=RTPS_BD,CLEAR=NCAP_AFBX
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    gput!(tm, "RTPS_BD", Set{NTuple{5,String}}())
    gput!(tm, "NCAP_AFBX", Dict{NTuple{4,String},Float64}())
    return tm
end

"""
    pp_shapr!(tm, coef_af, rtp_cptyr, X, M, base, cands; ax, bds)

pp_shapr.mod, as coef_cpt.mod L48 and L59 include it: %1%6X is `X`
(NCAP_AFBX or NCAP_AFSX, by (R,V,P,BD); L27 removes its records in place),
%5 is `M` (NCAP_AFM or NCAP_AFSM, by (R,V,P)), %1%2 is `base` (NCAP_AF or
NCAP_AFS at the vintage, by (R,V,P,S,BD)), %4 is COEF_AF over RTP_CPTYR
(`rtp_cptyr`: the (R,V,T,P) of the model's vintages and periods) and `cands`
gives, for each (R,V,P), the (S,BD) that %3 admits.

The (R,V,P) with a shape index >= 1.5 in X (any BD) or M are shaped
(RTP_ISHPR, L19-20). For them PASTSUM is the last year of operation less
YEARVAL(V) (L24); the shape index is dropped when the vintage operates
within its own period only (L27); RTP_SHAPI holds, for each BD, the SHAPE
row J+MAX(0,X-1), the MULTI row J+MAX(0,M-1), and the first and last years
of operation as leads from V (L30-32; a lead past either end of its set
gives no entry). COEF_AF of a shaped (R,V,P) in period T is then `base`
times, over its RTP_SHAPI entry for the BD, EPS + MULTI(JJ,T) times the
SHAPE row summed over the years of T up to MAX(B(T), the last year), each at
the age it has then (or at the last year), divided by the years of T it
operates in, at least 1 (L34-40). The others take `base` (L43-44).
FIL2(V) = B(V)-YEARVAL(V) (L23); RTP_ISHPR, RTP_SHAPI and PASTSUM end
cleared (L46).

GAMS: pp_shapr.mod L15-46, v4.9.7.
"""
function pp_shapr!(tm, coef_af, rtp_cptyr, X, M, base, cands; ax, bds)
    B, E, D = gparam(tm, "B"), gparam(tm, "E"), gparam(tm, "D")
    rtp = gset(tm, "RTP")
    # L19: LOOP(BD,RTP_ISHPR(RTP(R,V,P))$((X(RTP,BD) GE 1.5)$X(RTP,BD)) = YES); L20: the same for %5 = M
    ishpr = Set{NTuple{3,String}}()
    foreach(((k, x),) -> (x >= 1.5 && (k[1], k[2], k[3]) in rtp) && push!(ishpr, (k[1], k[2], k[3])), X)
    foreach(((k, x),) -> (x >= 1.5 && k in rtp) && push!(ishpr, k), M)
    # L23: OPTION CLEAR=FIL2; FIL2(V) = B(V)-YEARVAL(V)
    fil2 = Dict{NTuple{1,String},Float64}()
    for (v,) in gset(tm, "MODLYEAR").keys
        gassign!(fil2, (v,), gv(B, (v,)) - GNum(ax.yearval[v]))
    end
    gput!(tm, "FIL2", fil2)
    isempty(ishpr) || shape_avail!(tm, coef_af, rtp_cptyr, X, M, base, cands, ishpr, fil2; ax, bds, B, E, D)
    # L43: RTP_ISHPR(RTP(R,V,P)) = (NOT RTP_ISHPR(RTP)); L44: %4$(RTP_ISHPR(R,V,P)$(%3)) = %1%2
    for (r, v, t, p) in rtp_cptyr
        ((r, v, p) in rtp && !((r, v, p) in ishpr)) || continue
        foreach(((s, bd),) -> gassign!(coef_af, (r, v, t, p, s, bd), gv(base, (r, v, p, s, bd))), cands(r, v, p))
    end
    # L46: OPTION CLEAR=RTP_SHAPI,CLEAR=RTP_ISHPR,CLEAR=PASTSUM
    gput!(tm, "RTP_SHAPI", Set{NTuple{8,String}}())
    gput!(tm, "RTP_ISHPR", Set{NTuple{3,String}}())
    gput!(tm, "PASTSUM", Dict{NTuple{3,String},Float64}())
    return tm
end

"pp_shapr.mod L24-40 for the shaped (R,V,P) `ishpr` (see [`pp_shapr!`](@ref))."
function shape_avail!(tm, coef_af, rtp_cptyr, X, M, base, cands, ishpr, fil2; ax, bds, B, E, D)
    tab = ShapeTable(tm)
    iled, tlife = gparam(tm, "NCAP_ILED"), gparam(tm, "NCAP_TLIFE")
    multi = gparam(tm, "MULTI")
    yv(y) = ax.yearval[y]
    # L24: PASTSUM(RTP_ISHPR(R,V,P)) = FIL2(V)+NCAP_ILED(R,V,P)+NCAP_TLIFE(R,V,P)-1
    pastsum = Dict{NTuple{3,String},Float64}()
    for k in ishpr
        gassign!(pastsum, k, gv(fil2, (k[2],)) + gv(iled, k) + gv(tlife, k) - GNum(1.0))
    end
    # L27: X(RTP_ISHPR(R,V,P),BD)$(PASTSUM(R,V,P)-FIL2(V)+1 < D(V)) = 0
    for k in ishpr
        (gv(pastsum, k) - gv(fil2, (k[2],)) + GNum(1.0)).v < gv(D, (k[2],)).v || continue
        foreach(bd -> delete!(X, (k..., bd)), bds)
    end
    # L30-32: LOOP(SAMEAS(J,'1'), RTP_SHAPI(RTP_ISHPR(R,V(LL),P),BD,J+MAX(0,X(R,V,P,BD)-1),J+MAX(0,%5-1),
    #   LL+(FIL2(V)+NCAP_ILED(R,V,P)),LL+PASTSUM(R,V,P)) = YES)   (non-integer leads rounded, G29)
    j1 = tab.jpos[AGEJ_1[1]]
    jlab(x) = (i = j1 + glead(max(0.0, x - 1)); 1 <= i <= length(tab.j) ? tab.j[i] : nothing)
    shapi = Dict{NTuple{4,String},NTuple{4,String}}()                     # (R,V,P,BD) -> (J,JJ,LL,YEAR)
    for (r, v, p) in ishpr
        jj = jlab(gv(M, (r, v, p)).v)
        y0 = lead(ax, v, glead((gv(fil2, (v,)) + gv(iled, (r, v, p))).v))
        y1 = lead(ax, v, glead(gv(pastsum, (r, v, p)).v))
        (jj === nothing || y0 === nothing || y1 === nothing) && continue
        for bd in bds
            j = jlab(gv(X, (r, v, p, bd)).v)
            j === nothing || (shapi[(r, v, p, bd)] = (j, jj, y0, y1))
        end
    end
    gput!(tm, "PASTSUM", pastsum)
    gput!(tm, "RTP_SHAPI", Set{NTuple{8,String}}((k..., e...) for (k, e) in shapi))
    # L34-40: LOOP(SAMEAS(AGE,'1'), %4$((%3)$RTP_ISHPR(R,V,P)) = %1%2 * SUM(RTP_SHAPI(R,V,P,BD,J,JJ,LL,YEAR),
    #   EPS+MULTI(JJ,T) * SUM(PERIODYR(T,EOHYEARS)$(YEARVAL(EOHYEARS) LE MAX(B(T),YEARVAL(YEAR))),
    #   SHAPE(J,AGE+(MIN(YEARVAL(EOHYEARS),YEARVAL(YEAR))-YEARVAL(LL)))) /
    #   (MAX(1,MIN(E(T),YEARVAL(YEAR))-MAX(B(T),YEARVAL(LL))+1))))
    eoh = Set(k[1] for k in gset(tm, "EOHYEARS").keys)
    yrs_of = Dict{String,Vector{String}}()
    for (t, y) in gset(tm, "PERIODYR").keys
        y in eoh && push!(get!(() -> String[], yrs_of, t), y)
    end
    foreach(ys -> sort!(ys; by=y -> ax.pos[y]), values(yrs_of))
    for (r, v, t, p) in rtp_cptyr
        (r, v, p) in ishpr || continue
        bt, et = gv(B, (t,)).v, gv(E, (t,)).v
        for (s, bd) in cands(r, v, p)
            e = get(shapi, (r, v, p, bd), nothing)
            total = GZERO
            if e !== nothing
                (j, jj, y0, y1) = e
                x = tab.jpos[j] - j1 + 1                                   # SHAPE(J,...) is shape(tab, x, ...)
                a0, a1 = yv(y0), yv(y1)
                sh = GZERO
                for y in get(yrs_of, t, String[])
                    yv(y) <= max(bt, a1) || continue
                    sh += shape(tab, x, min(yv(y), a1) - a0)
                end
                total = GEPS + gv(multi, (jj, t)) * sh / GNum(max(1.0, min(et, a1) - max(bt, a0) + 1))
            end
            gassign!(coef_af, (r, v, t, p, s, bd), gv(base, (r, v, p, s, bd)) * total)
        end
    end
    return nothing
end
