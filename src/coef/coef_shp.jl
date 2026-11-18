# M1.2 (6): shaped coefficients for process transformation (RTP_FFCX from
# FLO_FUNCX) and capacity transfer (COEF_CPT rescaled by NCAP_CPX).
#
# GAMS (v4.9.7): coef_shp.mod L10-74, as coefmain.mod L29 includes it after
# coef_alt.lin. The shaping table SHAPE(J,AGE) is read at a lead from the
# single AGEJ member ('1','1'): SHAPE(J+(x-1), AGE+(a)) is the row of the
# shape index x at age a+1, zero outside the table (a lead past either end
# of J or AGE is no element), non-integer leads rounded as in G29.
#
# Paths:
# - L10-13: RTP_FFCX and AGEJ declared; OPYEAR(LIFE,AGE) for lifetimes up to
#   the longest period or investment period (Z = SMAX(T, MAX(IPD(T),D(T))));
#   RTP_CGC for non-positive FLO_FUNCX of vintaged processes.
# - L16-20: FLO_FUNCX indexes below 1.5 or above CARD(J)+0.5, and those on an
#   activity group (ACTCG), removed at the RTP vintages; RP_GRP, PRC_YMIN (a
#   count), TRACKP, RTP_CAPYR.
# - L22-37 (TRACKP not empty): per vintage, the average shape over each
#   period a plant still operates in; for repeated investments (COEF_RPTI >
#   1 at a milestone vintage) the lifetime average through OPYEAR.
# - L43: the 'CAPFLO' rows are dropped; L45: FLO_FUNC ratios for the
#   non-vintaged option (RTP_CGC); L46: work sets cleared.
# - L51-53: NCAP_CPX indexes outside [1.5, CARD(J)+0.5] removed; PRC_YMIN a
#   count, PRC_YMAX cleared.
# - L55-72 (NCAP_CPX not empty): COEF_CAP, the discounted shape average over
#   the operating years of each period divided by COEF_PVT, or the lifetime
#   average for repeated investments; then the rescaling factor
#   1/MAX(1, COEF_CPT/COEF_CAP) - 1.
# - L73-74: COEF_CPT rescaled; RTP_CPX(R,V,P,T), the factors with the year
#   positions swapped (G26, positions matched by domain); PRC_YMIN, PRC_YMAX, TRACKP, RVPRL,
#   COEF_CAP cleared.
#
# M1.3 change 54: L39-42, COEF_CIO from the CAPFLO shapes (FLO_FUNCX) and
# from NCAP_CLAG, for the flows over the lifetime (NCAP_COM); L96, the age
# filter of RCAP_OCAP on COEF_OCOM. M1.3 change 59: L77-94, the COEF_OCOM and
# COEF_RCOM override for NCAP_OCOM with FLO_FUNCX(R,'0',P,'CAPFLO',C) = 3 (the
# capacity transfer, `capacity_transfer!`).

"The coef_shp.mod paths this model would take that are not translated; empty when coef_shp! can run."
function coef_shp_unported(tm)
    out = String[]
    return out
end

"""
    ShapeTable

SHAPE(J,AGE) read at leads from AGEJ's ('1','1') (coef_shp.mod L22, L55):
`shape(tab, x, a)` is `SHAPE(J+(x-1), AGE+(a))`, zero when either lead
leaves its set (J is 1*999, AGE 1*200, initsys.mod L80-81); non-integer
leads round half away from zero (G29).
"""
struct ShapeTable
    j::Vector{String}
    age::Vector{String}
    jpos::Dict{String,Int}
    agepos::Dict{String,Int}
    values::GamsParam{2}
end
function ShapeTable(tm)
    j = [k[1] for k in gset(tm, "J").keys]
    age = [k[1] for k in gset(tm, "AGE").keys]
    agej = gset(tm, "AGEJ")
    length(agej) == 1 || throw(UnportedError("coef_shp.mod L11: AGEJ has $(length(agej)) members, not the declared ('1','1')"))
    return ShapeTable(j, age, Dict(l => i for (i, l) in enumerate(j)), Dict(l => i for (i, l) in enumerate(age)),
                      gparam(tm, "SHAPE"))
end
const AGEJ_1 = ("1", "1")
function shape(tab::ShapeTable, x::Real, a::Real)
    ji = tab.jpos[AGEJ_1[1]] + glead(x - 1)
    ai = tab.agepos[AGEJ_1[2]] + glead(a)
    (1 <= ji <= length(tab.j) && 1 <= ai <= length(tab.age)) || return GZERO
    return gv(tab.values, (tab.j[ji], tab.age[ai]))
end
"`SHAPE(J+(x-1), LIFE)` for a LIFE element (L36, L70): zero when the J lead leaves the set."
function shape_row(tab::ShapeTable, x::Real, life::String)
    ji = tab.jpos[AGEJ_1[1]] + glead(x - 1)
    1 <= ji <= length(tab.j) || return GZERO
    return gv(tab.values, (tab.j[ji], life))
end
"The AGE element `AGE+(n)` from AGEJ's age, or nothing past the end (L36, L70)."
function age_lead(tab::ShapeTable, n::Real)
    ai = tab.agepos[AGEJ_1[2]] + glead(n)
    return 1 <= ai <= length(tab.age) ? tab.age[ai] : nothing
end

"""
    coef_shp!(tm) -> tm

coef_shp.mod on the GAMS state in `tm`, as coefmain.mod L29 calls it:
OPYEAR; FLO_FUNCX and NCAP_CPX with the ineffective indexes removed;
RTP_CAPYR and RTP_FFCX, the age-shaped FLO_FUNC multipliers; COEF_CPT
rescaled by the NCAP_CPX shapes and RTP_CPX holding the factors with the
year positions swapped;
PRC_YMIN, PRC_YMAX, TRACKP, RVPRL, RP_GRP, RTP_CGC and COEF_CAP left
cleared; Z left at CARD(J)/2+1.

GAMS: coef_shp.mod L10-37, L43-74 (coefmain.mod L29), v4.9.7.
"""
function coef_shp!(tm)
    u = coef_shp_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    ax = YearAxis(tm)
    yv(y) = ax.yearval[y]
    S1(n) = gset(tm, n)
    tab = ShapeTable(tm)
    one = GNum(1)
    modlyear = Set(k[1] for k in S1("MODLYEAR").keys)
    milestones = Set(k[1] for k in S1("MILESTONYR").keys)
    rtp = S1("RTP")
    B, E, D, IPD = (gparam(tm, n) for n in ("B", "E", "D", "IPD"))
    iled, tlife, rpti = (gparam(tm, n) for n in ("NCAP_ILED", "NCAP_TLIFE", "COEF_RPTI"))
    rtp_cptyr = S1("RTP_CPTYR")
    cptyr_by_rvp = indexby(rtp_cptyr, (1, 2, 4))
    periodyr = indexby(S1("PERIODYR"), (1,))
    eohyears = Set(k[1] for k in S1("EOHYEARS").keys)
    y_eoh = Set(k[1] for k in S1("Y_EOH").keys)

    # L11: AGEJ / 1.1 / (declared with its data; the dump already holds it)
    gput!(tm, "AGEJ", Set([AGEJ_1]))
    # L12: Z = SMAX(T, MAX(IPD(T),D(T))); OPYEAR(LIFE,AGE)$((ORD(AGE)<=ORD(LIFE))$(ORD(LIFE)<=Z)) = YES
    z = maximum((max(Float64(gv(IPD, (t,))), Float64(gv(D, (t,)))) for t in milestones); init=-Inf)
    opyear = gmembers(tm, "OPYEAR", 2)
    for (li, life) in enumerate(tab.age), (ai, age) in enumerate(tab.age)
        (ai <= li && li <= z) && push!(opyear, (life, age))
    end
    gput!(tm, "OPYEAR", opyear)
    opyear_by_first = indexby(gset(tm, "OPYEAR"), (1,))
    "The LIFE elements of OPYEAR(AGE+(n), LIFE), in set order (L36, L70)."
    function opyear_lives(n)
        a = age_lead(tab, n)
        a === nothing && return String[]
        return [k[2] for k in get(opyear_by_first, (a,), NTuple{2,String}[])]
    end

    # L13: RTP_CGC(RTP(R,V,P),CG,CG2)$((FLO_FUNCX(RTP,CG,CG2)<=0)$FLO_FUNCX(RTP,CG,CG2)) = PRC_VINT(R,P)
    ffx = gvalues(tm, "FLO_FUNCX", 5)
    prc_vint = S1("PRC_VINT")
    rtp_cgc = gmembers(tm, "RTP_CGC", 5)
    for ((r, v, p, cg, cg2), x) in ffx
        ((r, v, p) in rtp && x <= 0) || continue
        (r, p) in prc_vint ? push!(rtp_cgc, (r, v, p, cg, cg2)) : delete!(rtp_cgc, (r, v, p, cg, cg2))
    end
    # L16-17: Z = CARD(J)/2+1; FLO_FUNCX(RTP,CG,CG2)$(ABS(FLO_FUNCX-Z) > Z-1.5-INF$ACTCG(CG)) = 0
    z = length(tab.j) / 2 + 1
    actcg = Set(k[1] for k in S1("ACTCG").keys)
    for ((r, v, p, cg, cg2), x) in collect(ffx)
        (r, v, p) in rtp || continue
        (cg in actcg || abs(x - z) > z - 1.5) && delete!(ffx, (r, v, p, cg, cg2))
    end
    gput!(tm, "FLO_FUNCX", ffx)
    # L18: OPTION RP_GRP <= FLO_FUNCX (R, P and the first CG, G26), PRC_YMIN < RP_GRP (a count), CLEAR=PRC_YMAX
    rp_grp = Set((k[1], k[3], k[4]) for k in keys(ffx))
    prc_ymin = Dict{NTuple{2,String},Float64}()
    for (r, p, _) in rp_grp
        prc_ymin[(r, p)] = get(prc_ymin, (r, p), 0.0) + 1
    end
    # L19: TRACKP(RP)$PRC_YMIN(RP) $= PRC_VINT(RP)+RP_GRP(RP,'CAPFLO')
    trackp = gmembers(tm, "TRACKP", 2)
    for rp in keys(prc_ymin)
        (rp in prc_vint || (rp[1], rp[2], "CAPFLO") in rp_grp) && push!(trackp, rp)
    end
    # L20: RTP_CAPYR(RTP_CPTYR(R,V,T,P)) $= TRACKP(R,P)
    rtp_capyr = gmembers(tm, "RTP_CAPYR", 4)
    for k in rtp_cptyr.keys
        (k[1], k[4]) in trackp && push!(rtp_capyr, k)
    end
    gput!(tm, "RTP_CAPYR", rtp_capyr)
    capyr_by_rvp = indexby(gset(tm, "RTP_CAPYR"), (1, 2, 4))
    ffx_by_rvp = Dict{NTuple{3,String},Vector{NTuple{5,String}}}()
    for k in keys(ffx)
        push!(get!(() -> NTuple{5,String}[], ffx_by_rvp, (k[1], k[2], k[3])), k)
    end

    rtp_ffcx = gvalues(tm, "RTP_FFCX", 6)
    rvprl = gvalues(tm, "RVPRL", 3)
    # L22-37: LOOP(AGEJ(J,AGE)$CARD(TRACKP), LOOP(V, ...))
    if !isempty(trackp)
        for ((r, v, p), caps) in capyr_by_rvp
            v in modlyear || continue
            # L25-26 for this V: PRC_YMIN(TRACKP) = B(V)+ROUND(NCAP_ILED(R,V,P)); PRC_YMAX = PRC_YMIN+ROUND(NCAP_TLIFE(R,V,P))-1
            ymin = Float64(gv(B, (v,))) + glead(Float64(gv(iled, (r, v, p))))
            ymax = ymin + glead(Float64(gv(tlife, (r, v, p)))) - 1
            # L28-31: the average SHAPE over the years of T a plant of vintage V still operates in
            for k in get(ffx_by_rvp, (r, v, p), NTuple{5,String}[]), (_, _, t, _) in caps
                x = ffx[k]
                bt, et = Float64(gv(B, (t,))), Float64(gv(E, (t,)))
                s = GZERO
                for (_, y) in get(periodyr, (t,), NTuple{2,String}[])
                    (y in eohyears && yv(y) <= max(bt, ymax)) || continue
                    s += shape(tab, x, min(yv(y), ymax) - ymin)
                end
                den = max(1.0, min(et, ymax) - max(bt, ymin) + 1)
                gassign!(rtp_ffcx, (r, v, t, p, k[4], k[5]), s / GNum(den) - one)
            end
        end
        # L34: RVPRL(RTP(R,T,P))$((COEF_RPTI(RTP)>1)$TRACKP(R,P)) = ROUND(NCAP_TLIFE(RTP)-1)+EPS
        for (r, t, p) in rtp.keys
            (t in milestones && (r, p) in trackp && Float64(gv(rpti, (r, t, p))) > 1) || continue
            gassign!(rvprl, (r, t, p), GNum(glead(Float64(gv(tlife, (r, t, p))) - 1)) + GEPS)
        end
        # L35-36: for repeated investments, the average SHAPE over the lifetime
        for ((r, tt, p), caps) in capyr_by_rvp
            haskey(rvprl, (r, tt, p)) || continue
            rv = gv(rvprl, (r, tt, p))
            lives = opyear_lives(Float64(rv))
            for k in get(ffx_by_rvp, (r, tt, p), NTuple{5,String}[]), (_, _, t, _) in caps
                x = ffx[k]
                s = sum((shape_row(tab, x, life) for life in lives); init=GZERO)
                gassign!(rtp_ffcx, (r, tt, t, p, k[4], k[5]), s / (rv + one) - one)
            end
        end
    end
    # L39: COEF_CIO(RTP_CAPYR(R,V,T,P),C,IO)$NCAP_COM(R,V,P,C,IO) $= RTP_FFCX(R,V,T,P,'CAPFLO',C)
    # L40-42: COEF_CIO(RTP_CPTYR(R,V,T,P),C,IO)$NCAP_CLAG(R,V,P,C,IO) = SIGN(NCAP_CLAG(R,V,P,C,IO)) *
    #   (MAX(0, E(T)+1-MAX(B(V)+NCAP_ILED(R,V,P)+ABS(NCAP_CLAG(R,V,P,C,IO)),B(T))) /
    #    MAX(.1,E(T)+1-MAX(B(V)+NCAP_ILED(R,V,P),B(T)))-1)-1$(NCAP_CLAG(R,V,P,C,IO)<0)      (M1.3 change 54)
    ncom = gparam_opt(tm.data, "NCAP_COM", 5)
    if !isempty(ncom.values)
        coef_cio = gvalues(tm, "COEF_CIO", 6)
        capyr_of = Dict{NTuple{3,String},Vector{NTuple{4,String}}}()   # (r,v,p) -> RTP_CAPYR(r,v,t,p)
        foreach(k -> push!(get!(capyr_of, (k[1], k[2], k[4]), NTuple{4,String}[]), k), rtp_capyr)
        for (r, v, p, c, io) in ncom.keys, (_, _, t, _) in get(capyr_of, (r, v, p), NTuple{4,String}[])
            ff = get(rtp_ffcx, (r, v, t, p, "CAPFLO", c), nothing)
            ff === nothing || gassign!(coef_cio, (r, v, t, p, c, io), GNum(ff, ff == 0))   # $=
        end
        clag = gparam_opt(tm.data, "NCAP_CLAG", 5)
        if !isempty(clag.values)
            Bp, Ep, iled = gparam(tm, "B"), gparam(tm, "E"), gparam(tm, "NCAP_ILED")
            cptyr_of = indexby(S1("RTP_CPTYR"), (1, 2, 4))            # (r,v,p) -> RTP_CPTYR(r,v,t,p)
            for (r, v, p, c, io) in clag.keys, (_, _, t, _) in get(cptyr_of, (r, v, p), NTuple{4,String}[])
                cl = gv(clag, (r, v, p, c, io))
                bv, bt, et1 = gv(Bp, (v,)) + gv(iled, (r, v, p)), gv(Bp, (t,)), gv(Ep, (t,)) + one
                num = gmax(GZERO, et1 - gmax(bv + GNum(abs(cl.v)), bt))
                den = gmax(GNum(0.1), et1 - gmax(bv, bt))
                gassign!(coef_cio, (r, v, t, p, c, io), GNum(sign(cl.v)) * (num / den - one) - gif(one, cl.v < 0))
            end
        end
        gput!(tm, "COEF_CIO", coef_cio)
    end
    # L43: RTP_FFCX(RTP_CAPYR,'CAPFLO',CG) = 0
    for k in collect(keys(rtp_ffcx))
        (k[5] == "CAPFLO" && (k[1], k[2], k[3], k[4]) in rtp_capyr) && delete!(rtp_ffcx, k)
    end
    # L45: RTP_FFCX(RTP_VINTYR(R,V,T,P),CG,CG2)$((FLO_FUNC(R,V,P,CG,CG2,'ANNUAL')>0)$RTP_CGC(R,V,P,CG,CG2))
    #        = FLO_FUNC(R,T,P,CG,CG2,'ANNUAL')/FLO_FUNC(R,V,P,CG,CG2,'ANNUAL')-1
    flo_func = gparam(tm, "FLO_FUNC")
    vintyr_by_rvp = indexby(S1("RTP_VINTYR"), (1, 2, 4))
    for (r, v, p, cg, cg2) in rtp_cgc
        fv = gv(flo_func, (r, v, p, cg, cg2, "ANNUAL"))
        Float64(fv) > 0 || continue
        for (_, _, t, _) in get(vintyr_by_rvp, (r, v, p), NTuple{4,String}[])
            gassign!(rtp_ffcx, (r, v, t, p, cg, cg2), gv(flo_func, (r, t, p, cg, cg2, "ANNUAL")) / fv - one)
        end
    end
    gput!(tm, "RTP_FFCX", rtp_ffcx)
    # L46: OPTION CLEAR=TRACKP,CLEAR=RVPRL,CLEAR=RP_GRP,CLEAR=RTP_CGC
    empty!(trackp); empty!(rvprl)
    gput!(tm, "RP_GRP", Set{NTuple{3,String}}())
    gput!(tm, "RTP_CGC", Set{NTuple{5,String}}())

    # L51-52: Z = CARD(J)/2+1; NCAP_CPX(RTP)$(ABS(NCAP_CPX(RTP)-Z)>Z-1.5) = 0
    cpx = gvalues(tm, "NCAP_CPX", 3)
    for (k, x) in collect(cpx)
        (k in rtp && abs(x - z) > z - 1.5) && delete!(cpx, k)
    end
    gput!(tm, "NCAP_CPX", cpx)
    gput_scalar!(tm, "Z", z)
    # L53: OPTION PRC_YMIN < NCAP_CPX (a count per R,P), CLEAR=PRC_YMAX
    empty!(prc_ymin)
    for (r, _, p) in keys(cpx)
        prc_ymin[(r, p)] = get(prc_ymin, (r, p), 0.0) + 1
    end
    coef_cap = gvalues(tm, "COEF_CAP", 4)
    coef_cpt = gvalues(tm, "COEF_CPT", 4)
    # L55-72: LOOP(AGEJ(J,AGE)$CARD(NCAP_CPX), ...)
    if !isempty(cpx)
        # L56: TRACKP(RP) $= PRC_YMIN(RP)
        union!(trackp, keys(prc_ymin))
        g_rcur = S1("G_RCUR")
        disc, coef_pvt = gparam(tm, "OBJ_DISC"), gparam(tm, "COEF_PVT")
        for ((r, v, p), x) in cpx
            (v in modlyear && (r, v, p) in rtp) || continue
            # L59-60 for this V: PRC_YMIN(TRACKP) = B(V)+ROUND(NCAP_ILED); PRC_YMAX = PRC_YMIN+NCAP_TLIFE (not rounded)
            ymin = Float64(gv(B, (v,))) + glead(Float64(gv(iled, (r, v, p))))
            ymax = ymin + Float64(gv(tlife, (r, v, p)))
            # L62-66: LOOP(G_RCUR(R,CUR), COEF_CAP(RTP_CPTYR(R,V,T,P))$NCAP_CPX(R,V,P) = SUM(PERIODYR(T,Y_EOH)$(YEARVAL(Y_EOH)<PRC_YMAX),
            #   MIN(1,PRC_YMAX-YEARVAL(Y_EOH))*OBJ_DISC(R,Y_EOH,CUR)*SHAPE(J+(NCAP_CPX-1),AGE+(YEARVAL(Y_EOH)-PRC_YMIN))) / COEF_PVT(R,T))
            for (rr, cur) in g_rcur.keys
                rr == r || continue
                for (_, _, t, _) in get(cptyr_by_rvp, (r, v, p), NTuple{4,String}[])
                    s = GZERO
                    for (_, y) in get(periodyr, (t,), NTuple{2,String}[])
                        (y in y_eoh && yv(y) < ymax) || continue
                        s += GNum(min(1.0, ymax - yv(y))) * gv(disc, (r, y, cur)) * shape(tab, x, yv(y) - ymin)
                    end
                    gassign!(coef_cap, (r, v, t, p), s / gv(coef_pvt, (r, t)))
                end
            end
        end
        # L68: RVPRL(RTP)$((COEF_RPTI(RTP)>1)$NCAP_CPX(RTP)) = ROUND(NCAP_TLIFE(RTP)-1)+EPS
        for (r, v, p) in rtp.keys
            (haskey(cpx, (r, v, p)) && Float64(gv(rpti, (r, v, p))) > 1) || continue
            gassign!(rvprl, (r, v, p), GNum(glead(Float64(gv(tlife, (r, v, p))) - 1)) + GEPS)
        end
        # L69-70: COEF_CAP(RTP_CPTYR(R,V(TT),T,P))$RVPRL(R,V,P) = SUM(OPYEAR(AGE+RVPRL,LIFE),SHAPE(J+(NCAP_CPX-1),LIFE)) / (RVPRL+1)
        for (r, v, p) in keys(rvprl)
            v in milestones || continue
            rv = gv(rvprl, (r, v, p))
            x = cpx[(r, v, p)]
            s = sum((shape_row(tab, x, life) for life in opyear_lives(Float64(rv))); init=GZERO)
            for (_, _, t, _) in get(cptyr_by_rvp, (r, v, p), NTuple{4,String}[])
                gassign!(coef_cap, (r, v, t, p), s / (rv + one))
            end
        end
        # L71: COEF_CAP(RTP_CPTYR(R,V,T,P))$NCAP_CPX(R,V,P) = (1/MAX(1,COEF_CPT/COEF_CAP))$COEF_CAP - 1
        for (r, v, p) in keys(cpx)
            for (_, _, t, _) in get(cptyr_by_rvp, (r, v, p), NTuple{4,String}[])
                cc = gv(coef_cap, (r, v, t, p))
                ratio = iszero(cc) ? GZERO : one / gmax(one, gv(coef_cpt, (r, v, t, p)) / cc)
                gassign!(coef_cap, (r, v, t, p), ratio - one)
            end
        end
    end
    # L73: COEF_CPT(R,V,T,P)$COEF_CAP(R,V,T,P) = COEF_CPT(R,V,T,P)*(COEF_CAP(R,V,T,P)+1)
    for (k, _) in coef_cap
        gassign!(coef_cpt, k, gv(coef_cpt, k) * (gv(coef_cap, k) + one))
    end
    gput!(tm, "COEF_CPT", coef_cpt)
    # L74: OPTION CLEAR=PRC_YMIN,CLEAR=PRC_YMAX,CLEAR=TRACKP,CLEAR=RVPRL, RTP_CPX <= COEF_CAP, CLEAR=COEF_CAP
    gput!(tm, "PRC_YMIN", Dict{NTuple{2,String},Float64}())
    gput!(tm, "PRC_YMAX", Dict{NTuple{2,String},Float64}())
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    gput!(tm, "RVPRL", Dict{NTuple{3,String},Float64}())
    # RTP_CPX(R,ALLYEAR,P,LL), a parameter, from COEF_CAP(R,ALLYEAR,LL,P): each position to the one of
    # the same domain, values (EPS included) copied (G26)
    gput!(tm, "RTP_CPX", Dict((k[1], k[2], k[4], k[3]) => x for (k, x) in coef_cap))
    gput!(tm, "COEF_CAP", Dict{NTuple{4,String},Float64}())
    # L77-94 (M1.3 change 59): the capacity transfer of decommissioning flows (`capacity_transfer!`)
    capacity_transfer!(tm, tab, cpx)
    # L96 (M1.3 change 54): COEF_OCOM(R,VNT(V,T),P,C)$RCAP_OCAP(R,V,P,C) =
    #   (COEF_OCOM(R,V,T,P,C)+EPS$COEF_RCOM(R,V,T,P,C))$(SIGN(RCAP_OCAP(R,V,P,C))*(B(T)-(B(V)+NCAP_ILED(R,V,P)+1/PI**9))<RCAP_OCAP(R,V,P,C))
    rcap_ocap = gparam_opt(tm.data, "RCAP_OCAP", 4)
    if !isempty(rcap_ocap.values)
        coef_ocom, coef_rcom = gvalues(tm, "COEF_OCOM", 5), gparam(tm, "COEF_RCOM")
        Bp, iled = gparam(tm, "B"), gparam(tm, "NCAP_ILED")
        vnt_of = indexby(S1("VNT"), (1,))                            # v -> VNT(v,t)
        for (r, v, p, c) in rcap_ocap.keys
            ro = gv(rcap_ocap, (r, v, p, c))
            for (_, t) in get(vnt_of, (v,), NTuple{2,String}[])
                k = (r, v, t, p, c)
                age = gv(Bp, (t,)) - (gv(Bp, (v,)) + gv(iled, (r, v, p)) + GNum(1 / pi^9))
                if sign(ro.v) * age.v < ro.v
                    x = gv(coef_ocom, k)
                    haskey(coef_rcom.values, k) && (x = x + GEPS)
                    gassign!(coef_ocom, k, x)
                else
                    delete!(coef_ocom, k)
                end
            end
        end
        gput!(tm, "COEF_OCOM", coef_ocom)
    end
    return tm
end

"""
    capacity_transfer!(tm, tab, cpx) -> tm

coef_shp.mod L77-94, the capacity transfer of decommissioning flows: for a
process with NCAP_OCOM on a commodity C and FLO_FUNCX(R,'0',P,'CAPFLO',C) = 3
(RPC_CONLY), the decommissioning flows follow the decline of the capacity
over its life, by its capacity shape NCAP_CPX, instead of coming at its end:

    RPC_CONLY(RTP(R,V,P),C)\$((FLO_FUNCX(R,'0',P,'CAPFLO',C)=3)\$NCAP_OCOM(RTP,C)) = YES;
    LOOP(AGEJ(J,AGE)\$CARD(RPC_CONLY),
      OPTION PASTSUM < RPC_CONLY;
      PASTSUM(RTP(R,V,P))\$PASTSUM(RTP) = B(V)+ROUND(NCAP_ILED(RTP))+ROUND(NCAP_DLAG(RTP)+NCAP_DLIFE(RTP)/2);
      RVPRL(RTP)\$PASTSUM(RTP) = PASTSUM(RTP)+ROUND(COEF_RPTI(RTP)*NCAP_TLIFE(RTP));
      LOOP(G_RCUR(R,CUR),
        FIL2(T)=COEF_PVT(R,T)*D(T)/SUM(PERIODYR(T,Y_EOH),(YEARVAL(Y_EOH)-B(T)+1)*OBJ_DISC(R,Y_EOH,CUR));
        COEF_CAP(R,VNT(V,T),P)\$((MIN(M(T)+1,E(T))<RVPRL(R,V,P))\$RVPRL(R,V,P)) = 1/COEF_RPTI(R,V,P) *
          MAX(POWER(SH(B(T)-PASTSUM-1),B(T)-PASTSUM-1>=0)*(1-FIL2(T)) +
              SUM(PERIODYR(T,Y_EOH)\$(YEARVAL(Y_EOH)<RVPRL),OBJ_DISC(R,Y_EOH,CUR)*
                POWER(SH(MOD(YEARVAL(Y_EOH)-PASTSUM,ROUND(NCAP_TLIFE))),YEARVAL(Y_EOH)-PASTSUM>=0))/COEF_PVT(R,T)*FIL2(T),
              SH(MAX(0,E(T)-PASTSUM))\$(E(T)<RVPRL)));
      COEF_OCOM(R,VNT(V,T),P,C)\$RPC_CONLY(R,V,P,C) = COEF_RPTI(R,V,P) *
        (MAX(0,POWER(SH(B(T)-PASTSUM-1),B(T)-PASTSUM-1>=0)-COEF_CAP(R,V,T,P))*NCAP_OCOM(R,V,P,C)/FPD(T))\$(B(T)<RVPRL(R,V,P));
      COEF_OCOM(R,V,T(TT+1),P,C)\$((B(T)>PASTSUM(R,V,P))\$VNT(V,TT)\$RPC_CONLY(R,V,P,C)) =
        COEF_RPTI(R,V,P) * MAX(0,COEF_CAP(R,V,TT,P)-COEF_CAP(R,V,T,P))*NCAP_OCOM(R,V,P,C)/FPD(T);
      COEF_RCOM(RTP_CPTYR(R,V,T(TT+1),P),C)\$(RPC_CONLY(R,V,P,C)\$RCAP_OCAP(R,V,P,C)) = COEF_CAP(R,V,TT,P)*NCAP_OCOM(R,V,P,C)/FPD(T));

SH(a) is SHAPE(J+(NCAP_CPX(R,V,P)-1),AGE+(a)) (`shape`): zero without a
capacity shape, as the J lead then leaves the set; POWER(x,0) is 1 even for
x = 0 (G23). COEF_CAP is computed inside the currency loop, so for each
region in its G_RCUR iterations (the last currency wins); the COEF_OCOM and
COEF_RCOM overrides run over all regions after it. MOD takes the sign of
its first argument (G43); ROUND rounds half away from zero. FIL2 keeps the
values of the last region; RPC_CONLY, COEF_CAP, PASTSUM and RVPRL are
cleared after L96 (L97), so they are left empty here.

GAMS: coef_shp.mod L77-94, v4.9.7.
"""
function capacity_transfer!(tm, tab::ShapeTable, cpx)
    rtp = gset(tm, "RTP")
    ocom = gparam_opt(tm.data, "NCAP_OCOM", 4)
    ffx = gparam_opt(tm.data, "FLO_FUNCX", 5)
    # L77
    conly = Set{NTuple{4,String}}()
    for (k, x) in ocom.values
        (k[1], k[2], k[3]) in rtp || continue
        get(ffx.values, (k[1], "0", k[3], "CAPFLO", k[4]), 0.0) == 3 && push!(conly, k)
    end
    isempty(conly) && return tm                                         # LOOP(AGEJ(J,AGE)$CARD(RPC_CONLY), ...)
    ax = YearAxis(tm)
    yv(y) = ax.yearval[y]
    rnd(x) = round(x, RoundNearestTiesAway)
    B, E, M, D, FPD = (gparam(tm, n) for n in ("B", "E", "M", "D", "FPD"))
    f(p, k) = Float64(gv(p, k))
    iled, dlag, dlife = gparam(tm, "NCAP_ILED"), gparam_opt(tm.data, "NCAP_DLAG", 3), gparam_opt(tm.data, "NCAP_DLIFE", 3)
    tlife, rpti = gparam(tm, "NCAP_TLIFE"), gparam(tm, "COEF_RPTI")
    disc, coef_pvt = gparam(tm, "OBJ_DISC"), gparam(tm, "COEF_PVT")
    T = [k[1] for k in gset(tm, "MILESTONYR").keys]
    periodyr = indexby(gset(tm, "PERIODYR"), (1,))
    y_eoh = Set(k[1] for k in gset(tm, "Y_EOH").keys)
    vnt = gset(tm, "VNT")
    vnt_of = indexby(vnt, (1,))                                         # v -> VNT(v,t)
    # L79-81: PASTSUM and RVPRL of the (R,V,P) of RPC_CONLY
    pastsum, rvprl = Dict{NTuple{3,String},Float64}(), Dict{NTuple{3,String},Float64}()
    for (r, v, p, _) in conly
        haskey(pastsum, (r, v, p)) && continue
        ps = f(B, (v,)) + rnd(f(iled, (r, v, p))) + rnd(f(dlag, (r, v, p)) + f(dlife, (r, v, p)) / 2)
        pastsum[(r, v, p)] = ps
        rvprl[(r, v, p)] = ps + rnd(f(rpti, (r, v, p)) * f(tlife, (r, v, p)))
    end
    sh(r, v, p, a) = Float64(shape(tab, get(cpx, (r, v, p), 0.0), a))
    pw(x, b) = b ? x : 1.0                                               # POWER(x, 1 or 0), 0**0 = 1 (G23)
    # L82-88: per G_RCUR(R,CUR), FIL2(T) and COEF_CAP
    fil2 = gvalues(tm, "FIL2", 1)
    coef_cap = Dict{NTuple{4,String},Float64}()
    for (r, cur) in gams_sort!(collect(gset(tm, "G_RCUR").keys), tm.data)
        fl = Dict{String,Float64}()
        for t in T
            s = sum(((yv(y) - f(B, (t,)) + 1) * f(disc, (r, y, cur)) for (_, y) in get(periodyr, (t,), NTuple{2,String}[]) if y in y_eoh); init=0.0)
            fl[t] = f(coef_pvt, (r, t)) * f(D, (t,)) / s
            fl[t] == 0 ? delete!(fil2, (t,)) : (fil2[(t,)] = fl[t])
        end
        for ((rr, v, p), rv) in rvprl
            rr == r || continue
            ps = pastsum[(r, v, p)]
            for (_, t) in get(vnt_of, (v,), NTuple{2,String}[])
                min(f(M, (t,)) + 1, f(E, (t,))) < rv || continue
                bt = f(B, (t,))
                a1 = pw(sh(r, v, p, bt - ps - 1), bt - ps - 1 >= 0) * (1 - fl[t])
                s = 0.0
                for (_, y) in get(periodyr, (t,), NTuple{2,String}[])
                    (y in y_eoh && yv(y) < rv) || continue
                    s += f(disc, (r, y, cur)) * pw(sh(r, v, p, rem(yv(y) - ps, rnd(f(tlife, (r, v, p))))), yv(y) - ps >= 0)
                end
                a1 += s / f(coef_pvt, (r, t)) * fl[t]
                a2 = f(E, (t,)) < rv ? sh(r, v, p, max(0.0, f(E, (t,)) - ps)) : 0.0
                x = 1 / f(rpti, (r, v, p)) * max(a1, a2)
                x == 0 ? delete!(coef_cap, (r, v, t, p)) : (coef_cap[(r, v, t, p)] = x)
            end
        end
    end
    gput!(tm, "FIL2", fil2)
    cap(k) = get(coef_cap, k, 0.0)
    coef_ocom = gvalues(tm, "COEF_OCOM", 5)
    put!(d, k, x) = x == 0 ? delete!(d, k) : (d[k] = x)
    # L90-91: COEF_OCOM(R,VNT(V,T),P,C)$RPC_CONLY(R,V,P,C) = ...$(B(T)<RVPRL(R,V,P))
    for (r, v, p, c) in conly, (_, t) in get(vnt_of, (v,), NTuple{2,String}[])
        ps, rv, bt = pastsum[(r, v, p)], rvprl[(r, v, p)], f(B, (t,))
        x = bt < rv ? f(rpti, (r, v, p)) * (max(0.0, pw(sh(r, v, p, bt - ps - 1), bt - ps - 1 >= 0) - cap((r, v, t, p))) *
                                         f(ocom, (r, v, p, c)) / f(FPD, (t,))) : 0.0
        put!(coef_ocom, (r, v, t, p, c), x)
    end
    # L92: COEF_OCOM(R,V,T(TT+1),P,C)$((B(T)>PASTSUM(R,V,P))$VNT(V,TT)$RPC_CONLY(R,V,P,C)) =
    #   COEF_RPTI(R,V,P)*MAX(0,COEF_CAP(R,V,TT,P)-COEF_CAP(R,V,T,P))*NCAP_OCOM(R,V,P,C)/FPD(T)
    for (r, v, p, c) in conly, i in 1:length(T)-1
        tt, t = T[i], T[i+1]
        ((v, tt) in vnt && f(B, (t,)) > pastsum[(r, v, p)]) || continue
        put!(coef_ocom, (r, v, t, p, c),
             f(rpti, (r, v, p)) * max(0.0, cap((r, v, tt, p)) - cap((r, v, t, p))) * f(ocom, (r, v, p, c)) / f(FPD, (t,)))
    end
    gput!(tm, "COEF_OCOM", coef_ocom)
    # L93: COEF_RCOM(RTP_CPTYR(R,V,T(TT+1),P),C)$(RPC_CONLY(R,V,P,C)$RCAP_OCAP(R,V,P,C)) = COEF_CAP(R,V,TT,P)*NCAP_OCOM(R,V,P,C)/FPD(T)
    rcap_ocap = gparam_opt(tm.data, "RCAP_OCAP", 4)
    cptyr = gset(tm, "RTP_CPTYR")
    coef_rcom = gvalues(tm, "COEF_RCOM", 5)
    for (r, v, p, c) in conly
        haskey(rcap_ocap.values, (r, v, p, c)) || continue
        for i in 1:length(T)-1
            tt, t = T[i], T[i+1]
            (r, v, t, p) in cptyr || continue
            put!(coef_rcom, (r, v, t, p, c), cap((r, v, tt, p)) * f(ocom, (r, v, p, c)) / f(FPD, (t,)))
        end
    end
    gput!(tm, "COEF_RCOM", coef_rcom)
    # L97: OPTION CLEAR=RPC_CONLY, CLEAR=COEF_CAP, CLEAR=PASTSUM, CLEAR=RVPRL (all left empty)
    return tm
end
