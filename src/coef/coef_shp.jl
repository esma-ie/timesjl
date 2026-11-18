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
# Refused: capacity-related commodity flows (L39-42 COEF_CIO from NCAP_COM
# and NCAP_CLAG; L77-94 the COEF_OCOM/COEF_RCOM override for NCAP_OCOM with
# FLO_FUNCX(R,'0',P,'CAPFLO',C) = 3; L96 the RCAP_OCAP age filter). NCAP_OCOM
# itself is translated (coef_nio.mod L37-56, M1.3 change 53): without the
# override and without RCAP_OCAP, L77-97 change nothing.

"The coef_shp.mod paths this model would take that are not translated; empty when coef_shp! can run."
function coef_shp_unported(tm)
    out = String[]
    for (s, n, lines) in (("NCAP_COM", 5, "L39"), ("NCAP_CLAG", 5, "L40-42"), ("RCAP_OCAP", 4, "L96"))
        isempty(gparam_opt(tm.data, s, n)) ||
            push!(out, "coef_shp.mod $lines (capacity-related commodity flows: $s has data)")
    end
    # L77: RPC_CONLY(RTP(R,V,P),C)$((FLO_FUNCX(R,'0',P,'CAPFLO',C)=3)$NCAP_OCOM(RTP,C))
    ocom = gparam_opt(tm.data, "NCAP_OCOM", 4)
    funcx = gparam_opt(tm.data, "FLO_FUNCX", 5)
    any(k -> haskey(funcx.values, (k[1], "0", k[3], "CAPFLO", k[4])) && funcx.values[(k[1], "0", k[3], "CAPFLO", k[4])] == 3,
        ocom.keys) && push!(out, "coef_shp.mod L77-94 (NCAP_OCOM with FLO_FUNCX(R,'0',P,'CAPFLO',C) = 3: the capacity transfer)")
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
    # L39-42: COEF_CIO from NCAP_COM and NCAP_CLAG - refused above (none here)
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
    return tm
end
