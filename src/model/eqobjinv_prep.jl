# M1.3 change 25-1: the data statements of eqobj.mod and eqobjinv.mod, the
# start of the coef -> pre-solve step (maindrv.mod L76-79: mod_vars.mod, then
# eqmain.mod L34, `$BATINCLUDE eqobj.mod`, v4.9.7).
#
# eqobj.mod L14-39 builds K_EOH, KTYAGE and SUM_OBJ and declares the case
# sets; eqobjinv.mod L18-274 classifies the investment cases (OBJ_1A, OBJ_1B,
# OBJ_2A, OBJ_2B), builds the investment and decommissioning spreads
# (OBJ_SUMII, INVSTEP, INVSPRED, OBJ_SUMIII), the correction factors
# (COR_SALVI, OBJ_CRF, OBJ_PASTI) and the divisors (OBJ_DIVI, OBJ_DIVIII),
# with coef_alt.lin's INV part (L89-118, the DOINV block falling through into
# DOFIX up to `%2$GOTO FINISH`) when %CTST% is not empty (OBJ MOD, ALT, LIN).
# The equations themselves (EQ_OBJINV, eqobjinv.mod L280-321) are generated
# by `eqobj.jl` from the state this leaves.
#
# Not translated (UnportedError): %VALIDATE% YES (L115, L144, L266, L270),
# %ETL% YES (L55), %STAGES% (L296). %DISCSHIFT% is 0.5 when MID_YEAR is YES
# (maindrv.mod L70), else the run's DISCSHIFT, else 0 (L19).

"""
    eqobjinv_prep_unported(tm) -> Vector{String}

The switches eqobjinv.mod has branches for that are not translated.
"""
function eqobjinv_prep_unported(tm::TimesModel)
    out = String[]
    uppercase(gswitch(tm, "VALIDATE", "")) == "YES" && push!(out, "eqobjinv.mod L115, L144, L266: %VALIDATE% YES")
    uppercase(gswitch(tm, "ETL", "")) == "YES" && push!(out, "eqobjinv.mod L55: %ETL% YES")
    uppercase(gswitch(tm, "STAGES", "")) == "YES" && push!(out, "eqobjinv.mod L296: %STAGES% YES")
    return out
end

"%DISCSHIFT%: 0.5 under MID_YEAR (maindrv.mod L70), else the run's value, else 0 (eqobjinv.mod L19)."
discshift(tm) = uppercase(gswitch(tm, "MID_YEAR", "")) == "YES" ? 0.5 : parse(Float64, gswitch(tm, "DISCSHIFT", "0"))

"""
    eqobjinv_prep_symbols(tm) -> Vector{String}

The sets and parameters eqobj.mod L14-39 and eqobjinv.mod L18-274 settle
that nothing later in the coef -> pre-solve step changes (eqobjfix.mod and
coef_alt.lin FIX rebuild KAGE, INVSTEP, INVSPRED, OBJ_JD and OBJ_YES, and the
salvage step OBJ_SUMS3).
"""
eqobjinv_prep_symbols(tm) = ["K_EOH", "KTYAGE", "SUM_OBJ", "RTP", "OBJ_ICUR", "NCAP_TLIFE", "NCAP_ELIFE",
                             "NCAP_DLIFE", "NCAP_DELIF", "COR_SALVI", "OBJ_CRF", "OBJ_PASTI", "OPYEAR", "MAXLIFE",
                             "OBJ_1A", "OBJ_1B", "OBJ_2A", "OBJ_2B", "OBJ_SUMII", "OBJ_SUMIII", "OBJ_DIVI",
                             "OBJ_DIVIII", "OBJ_IDC", "OBJ_I2", "OBJ_SPRED", "YKAGE"]

"""
    eqobjinv_prep!(tm) -> tm

eqobj.mod L14-39 and eqobjinv.mod L18-274 (with coef_alt.lin L89-118 under a
non-empty %CTST%), statement by statement; see the comments for each line.
Leads and lags by a real amount are rounded half away from zero (G29); `LL--n`
is a circular lag on ALLYEAR, whose last element is '0'.

GAMS: eqobj.mod L14-39, eqobjinv.mod L18-274, coef_alt.lin L89-118, v4.9.7.
"""
function eqobjinv_prep!(tm::TimesModel)
    u = eqobjinv_prep_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    d = tm.data
    yax = YearAxis(tm)
    ageax = OrdAxis(tm, "AGE")
    a1 = ageax.labels[1]                                               # SAMEAS(AGE,'1')
    yv(y) = yax.yearval[y]
    S(name, n) = gset_opt(d, name, n)
    P(name, n) = gparam_opt(d, name, n)
    sc(name) = gscalar(tm, name)
    K = S("EACHYEAR", 1)
    T = S("MILESTONYR", 1)
    agelead(a, n) = lead(ageax, a, glead(n))
    ylead(y, n) = lead(yax, y, glead(n))
    ord(ax, l) = ax isa YearAxis ? ax.pos[l] : ax.pos[l]
    B, E, D, M = P("B", 1), P("E", 1), P("D", 1), P("M", 1)
    ipd = P("IPD", 1)
    ct = ctst(tm)
    scal = Dict{String,Union{Float64,GNum}}()   # scratch scalars as the statements leave them (F, Z, MY_F, CNT, OBJ_C)

    # ---- eqobj.mod L14-28 -------------------------------------------------------
    # L17: K_EOH(EACHYEAR)$((YEARVAL(EACHYEAR) >= PYR_V1) * (YEARVAL(EACHYEAR) <= MIYR_VL)) = YES
    pyr_v1, miyr_vl = sc("PYR_V1"), sc("MIYR_VL")
    k_eoh = Set((k,) for (k,) in K if yv(k) >= pyr_v1 && yv(k) <= miyr_vl)
    gput!(tm, "K_EOH", k_eoh)
    # L21-23: LOOP(SAMEAS('1',AGE), KTYAGE(K(LL),PERIODYR(T,Y_EOH(YEAR)),AGE+(ORD(YEAR)-ORD(LL)))$YK(YEAR,LL)=YES;
    #                              KTYAGE(K(LL),YK(PYR_S,Y_EOH(YEAR)),AGE+(ORD(YEAR)-ORD(LL)))$YK(YEAR,LL)=YES)
    yk, y_eoh = S("YK", 2), S("Y_EOH", 1)
    ktyage = Set{NTuple{4,String}}()
    pyr_s = S("PYR_S", 1)
    for (ll,) in K
        for (t, y) in S("PERIODYR", 2)
            ((y,) in y_eoh && (y, ll) in yk) || continue
            a = lead(ageax, a1, yax.pos[y] - yax.pos[ll])
            a === nothing || push!(ktyage, (ll, t, y, a))
        end
        for (ps, y) in yk
            ((ps,) in pyr_s && (y,) in y_eoh && (y, ll) in yk) || continue
            a = lead(ageax, a1, yax.pos[y] - yax.pos[ll])
            a === nothing || push!(ktyage, (ll, ps, y, a))
        end
    end
    gput!(tm, "KTYAGE", ktyage)
    # L26-28: SUM_OBJ(OBV,ITEM) = DIAG(OBV,ITEM); SUM_OBJ(OBV('OBJSAL'),OBV) = -1;
    #         SUM_OBJ(R,'OBJELS') = 1$SUM(RCJ(R,C,J,BD),1)
    obv = [k[1] for k in S("OBV", 1).keys]
    sum_obj = Dict{NTuple{2,String},Float64}()
    foreach(o -> gassign!(sum_obj, (o, o), 1.0), obv)
    # OBV('OBJSAL') and the second OBV are the same controlled index: only (OBJSAL,OBJSAL)
    "OBJSAL" in obv && gassign!(sum_obj, ("OBJSAL", "OBJSAL"), -1.0)
    rcj_r = Set(k[1] for k in S("RCJ", 4))
    for (r,) in S("REG", 1)
        gassign!(sum_obj, (r, "OBJELS"), r in rcj_r ? 1.0 : 0.0)
    end
    gput!(tm, "SUM_OBJ", sum_obj)
    # L39: $IF DECLARED VNRET $BATINCLUDE prepret.dsc EQOBJ (its data statements)
    prepret_eqobj!(tm)

    # ---- eqobjinv.mod L52-72 ----------------------------------------------------------
    rtp = gmembers(tm, "RTP", 3)
    ncap_pasti = P("NCAP_PASTI", 3)
    pastmile = S("PASTMILE", 1)
    # L52: RTP(R,PASTMILE,P)$(NCAP_PASTI(R,PASTMILE,P)=0) = NO
    filter!(k -> !((k[2],) in pastmile && gv(ncap_pasti, k).v == 0), rtp)
    gput!(tm, "RTP", rtp)
    rtp_sorted = collect(rtp); gams_sort!(rtp_sorted, d)
    curs = [k[1] for k in S("CUR", 1).keys]
    ob(name) = P(name, 4)                                              # OBJ_xxx(r,y,p,m) = OB_xxx(r,p,m,y)
    ob_icost, ob_isub, ob_itax, ob_dcc = ob("OB_ICOST"), ob("OB_ISUB"), ob("OB_ITAX"), ob("OB_DCC")
    nz(x::GNum) = x.v != 0 || x.eps                                    # $x: nonzero or EPS
    # L53: OBJ_ICUR(RTP(R,V,P),CUR)$(OBJ_ICOST+OBJ_ISUB+OBJ_ITAX) = YES; L57: ...$OBJ_DCOST = YES
    obj_icur = Set{NTuple{4,String}}()
    obj_sums3 = Set{NTuple{3,String}}()
    for (r, v, p) in rtp_sorted, cur in curs
        k = (r, p, cur, v)
        nz(gv(ob_icost, k) + gv(ob_isub, k) + gv(ob_itax, k)) && push!(obj_icur, (r, v, p, cur))
        if nz(gv(ob_dcc, k))
            push!(obj_icur, (r, v, p, cur))                            # L57
            push!(obj_sums3, (r, v, p))                                # L58
        end
    end
    # L59: LOOP((RTP,COM)$NCAP_OCOM(RTP,COM),OBJ_SUMS3(RTP) = YES)
    for k in P("NCAP_OCOM", 4).keys
        (k[1], k[2], k[3]) in rtp && push!(obj_sums3, (k[1], k[2], k[3]))
    end
    # L61-62: OBJ_ICUR(RTP_OFF,CUR)$(NOT NCAP_PASTI(RTP_OFF)) = NO; OBJ_ICUR(R,LL,P,CUR)$(NOT RDCUR(R,CUR)) = NO
    rtp_off, rdcur = S("RTP_OFF", 3), S("RDCUR", 2)
    filter!(k -> !((k[1], k[2], k[3]) in rtp_off && !nz(gv(ncap_pasti, (k[1], k[2], k[3])))) && (k[1], k[4]) in rdcur, obj_icur)
    gput!(tm, "OBJ_ICUR", obj_icur)
    # L63: OPTION OBJ_YES < OBJ_ICUR; OBJ_YES(OBJ_SUMS3) = YES
    obj_yes = Set((k[1], k[2], k[3]) for k in obj_icur)
    union!(obj_yes, obj_sums3)
    # L66-69: TLIFE, ELIFE (OBJ_YES), DLIFE (OBJ_SUMS3) rounded to <= 0 become 1; DELIF = MAX(1,DELIF)
    tlife, elife = gvalues(tm, "NCAP_TLIFE", 3), gvalues(tm, "NCAP_ELIFE", 3)
    dlife, delif = gvalues(tm, "NCAP_DLIFE", 3), gvalues(tm, "NCAP_DELIF", 3)
    rnd(x) = round(x, RoundNearestTiesAway)
    for k in obj_yes
        rnd(gv(tlife, k).v) <= 0 && gassign!(tlife, k, 1.0)
        rnd(gv(elife, k).v) <= 0 && gassign!(elife, k, 1.0)
    end
    for k in obj_sums3
        rnd(gv(dlife, k).v) <= 0 && gassign!(dlife, k, 1.0)
        gassign!(delif, k, gmax(GNum(1.0), gv(delif, k)))
    end
    gput!(tm, "NCAP_TLIFE", tlife); gput!(tm, "NCAP_ELIFE", elife)
    gput!(tm, "NCAP_DLIFE", dlife); gput!(tm, "NCAP_DELIF", delif)
    # L71: OBJ_I2(RTP)$NCAP_ILED(RTP) = YES
    iled = P("NCAP_ILED", 3)
    obj_i2 = Set(k for k in rtp if nz(gv(iled, k)))
    # L72: LOOP(SAMEAS(LIFE,'1'),OBJ_SPRED(OBJ_YES(R,V,P),LIFE+MAX(0,MIN(CARD(AGE),NCAP_ELIFE(R,V,P))-1))=YES)
    nage = length(ageax.labels)
    obj_spred = Set{NTuple{4,String}}()
    for k in obj_yes
        l = agelead(a1, max(0.0, min(nage, gv(elife, k).v) - 1))
        l === nothing || push!(obj_spred, (k..., l))
    end
    spred_of = indexby(_gset_from("OBJ_SPRED", collect(obj_spred), d), (1, 2, 3))

    # ---- L76-87: COR_SALVI, OBJ_CRF, OBJ_PASTI ------------------------------------------
    ds = discshift(tm)
    drate, rfr, g_drate = P("NCAP_DRATE", 3), P("OBJ_RFR", 3), P("G_DRATE", 3)
    one = GNum(1.0)
    cor_salvi = Dict{NTuple{4,String},Float64}()
    obj_crf = Dict{NTuple{4,String},Float64}()
    obj_pasti = Dict{NTuple{4,String},Float64}()
    icur_sorted = collect(obj_icur); gams_sort!(icur_sorted, d)
    pastyear = S("PASTYEAR", 1)
    minyr = sc("MINYR")
    for (r, v, p, cur) in icur_sorted
        dr, rf, gd, el = gv(drate, (r, v, p)), gv(rfr, (r, v, cur)), gv(g_drate, (r, v, cur)), gv(elife, (r, v, p))
        # L76-79
        x = dr.v > 0 ?
            (gpow((one + dr) / (one + rf), GNum(ds)) * ((one - one / (one + dr)) * (one - gpow(one + rf, -el))) /
             ((one - one / (one + rf)) * (one - gpow(one + dr, -el))) - one) : GZERO
        cs = (x + one) * gpow(one + gd, GNum(ds))
        # L80: OBJ_I2 divides the shift back out
        (r, v, p) in obj_i2 && (cs = cs / gpow(one + gd, GNum(ds)))
        gassign!(cor_salvi, (r, v, p, cur), cs)
        # L82: OBJ_CRF = COR_SALVI*(1-(1/(1+G_DRATE)))/(1-(1+G_DRATE)**(-ROUND(ELIFE)))
        gassign!(obj_crf, (r, v, p, cur), cs * (one - one / (one + gd)) / (one - gpow(one + gd, GNum(-rnd(el.v)))))
        # L85-87: OBJ_PASTI for past vintages
        if (v,) in pastyear
            num = gpow(one + gd, GNum(yv(v) + rnd(gv(iled, (r, v, p)).v) - minyr) + el) - one
            den = gpow(one + gd, el) - one
            gassign!(obj_pasti, (r, v, p, cur), gv(ncap_pasti, (r, v, p)) * gmax(GZERO, gmin(one, num / den)))
        end
    end

    # ---- L90-92: OPYEAR -----------------------------------------------------------
    resid = P("PRC_RESID", 3)
    zmax = -Inf
    for (r, v, p) in rtp, (t,) in T
        ((v,) in pyr_s && nz(gv(resid, (r, t, p)))) || continue
        zmax = max(zmax, gv(E, (t,)).v)
    end
    z = zmax - sc("MIYR_V1") + 2
    scal["Z"] = z
    maxlife = max(maximum((2 * gv(D, (t,)).v for (t,) in T); init=-Inf), z, ceil(sc("MAXLIFE")))
    gput_scalar!(tm, "MAXLIFE", maxlife)
    opyear = gmembers(tm, "OPYEAR", 2)
    for l in ageax.labels, a in ageax.labels
        (ageax.pos[a] <= ageax.pos[l] && ageax.pos[l] <= maxlife) && push!(opyear, (l, a))
    end
    gput!(tm, "OPYEAR", opyear)
    opyear_of_jot = indexby(_gset_from("OPYEAR", collect(opyear), d), (1,))

    # ---- L99-158: cases 1a, 1b -----------------------------------------------------
    rpti = P("COEF_RPTI", 3)
    tl(k) = gv(tlife, k).v
    obj_1a = Set(k for k in rtp if !(k in obj_i2) && gv(rpti, k).v < 1.01)                    # L99
    obj_sumii = Set{NTuple{6,String}}()
    modlyear = S("MODLYEAR", 1)
    fil2 = Dict(v => ((v,) in T ? gv(ipd, (v,)).v - 1 : 0.0) for (v,) in modlyear)            # L118
    my_array = Dict(v => gv(B, (v,)).v - yv(v) + ((v,) in T ? gv(M, (v,)).v - gv(B, (v,)).v - fil2[v] : 0.0)
                    for (v,) in modlyear)                                                    # L119
    for k in sort!(collect(obj_1a); by=k -> (yax.pos[k[2]],))                                  # L120-123
        (r, v, p) = k
        haskey(my_array, v) || continue
        kk = ylead(v, my_array[v])
        (kk === nothing || !((kk,) in K)) && continue
        a = agelead(a1, fil2[v])
        a === nothing && continue
        for (_, _, _, l) in get(spred_of, k, NTuple{4,String}[])
            push!(obj_sumii, (r, v, p, l, kk, a))
        end
    end
    obj_1b = Set(k for k in rtp if (k[2],) in T && !(k in obj_i2) && !(k in obj_1a))         # L135
    zhalf(zz) = ct == "" ? ceil(zz / 2 - 0.5) : floor(rnd(zz) / 2)                            # L94-95
    istep(t, zz) = ct == "" ? gv(ipd, (t,)).v : min(gv(ipd, (t,)).v, rnd(zz))
    ipdc(t) = ct == "" ? gv(ipd, (t,)).v : 1.0                                                 # IPD(T)%CTST% (**0, **EPS: 1, G13)
    spred_1b = [s4 for k in obj_1b for s4 in get(spred_of, k, NTuple{4,String}[])]
    gams_sort!(spred_1b, d)                                                                   # LOOP order
    for (r, t, p, l) in spred_1b                                                              # L145-158
        k = (r, t, p)
        zz = tl(k)
        if rnd(zz) - ipdc(t) <= 0
            f = gv(B, (t,)).v - zhalf(zz) - yv(t)
            zz = rnd(gv(rpti, k).v * zz) - 1
            kk, a = ylead(t, f), agelead(a1, zz)
            (kk !== nothing && (kk,) in K && a !== nothing) && push!(obj_sumii, (r, t, p, l, kk, a))
            scal["F"] = f; scal["Z"] = zz
        else
            cnt = istep(t, zz)
            f = gv(B, (t,)).v - yv(t) - floor(cnt / 2)
            cnt -= 1
            n = gv(rpti, k).v
            obj_c = 1.0
            while obj_c <= n
                kk, a = ylead(t, f), agelead(a1, cnt)
                (kk !== nothing && (kk,) in K && a !== nothing) && push!(obj_sumii, (r, t, p, l, kk, a))
                f += zz
                obj_c += 1
            end
            scal["Z"] = zz; scal["F"] = f; scal["CNT"] = cnt; scal["OBJ_C"] = obj_c     # FOR leaves the first value past n
        end
    end

    # ---- L174-214: cases 2a, 2b (OBJ_IDC) ------------------------------------------------
    obj_2a = Set(k for k in obj_i2 if gv(rpti, k).v <= 1)                                     # L174
    obj_idc = Set{NTuple{6,String}}()
    spred_2a = [s4 for k in obj_2a for s4 in get(spred_of, k, NTuple{4,String}[])]
    gams_sort!(spred_2a, d)
    for (r, v, p, l) in spred_2a                                                              # L188-193
        k = (r, v, p)
        zz = gv(iled, k).v
        my_f = gv(B, (v,)).v - yv(v) + zz
        # an EPS NCAP_ILED (prepret.dsc L62) leaves Z and MY_F at EPS when B(V) = YEARVAL(V)
        scal["Z"] = gv(iled, k); scal["MY_F"] = GNum(gv(B, (v,)).v - yv(v)) + gv(iled, k)
        kk, a = ylead(v, my_f), agelead(a1, max(0.0, zz - 1))
        (kk !== nothing && a !== nothing) && push!(obj_idc, (r, v, p, l, kk, a))
    end
    obj_2b = Set(k for k in obj_i2 if (k[2],) in T && !(k in obj_2a))                         # L198
    spred_2b = [s4 for k in obj_2b for s4 in get(spred_of, k, NTuple{4,String}[])]
    gams_sort!(spred_2b, d)
    for (r, t, p, l) in spred_2b                                                              # L207-214
        k = (r, t, p)
        n = gv(rpti, k).v
        c = 1.0
        while c <= n
            zz = gv(iled, k).v
            my_f = rnd(gv(B, (t,)).v + (c - 1) * tl(k)) - yv(t) + zz
            kk, a = ylead(t, my_f), agelead(a1, max(0.0, zz - 1))
            (kk !== nothing && a !== nothing) && push!(obj_idc, (r, t, p, l, kk, a))
            scal["Z"] = zz; scal["MY_F"] = my_f
            c += 1
        end
        scal["OBJ_C"] = c
    end
    # L219-229: OBJ_DIVI of OBJ_I2 from the interest during construction
    obj_divi = Dict{NTuple{3,String},Float64}()
    obj_disc = P("OBJ_DISC", 3)
    coef_iled = P("COEF_ILED", 3)
    idc_sorted = collect(obj_idc); gams_sort!(idc_sorted, d)
    idc_of = indexby(_gset_from("OBJ_IDC", idc_sorted, d), (1, 2, 3))
    my_fs = 0.0
    for (r, v, p, cur) in icur_sorted
        (r, v, p) in obj_i2 || continue
        zz = gv(coef_iled, (r, v, p)).v
        scal["Z"] = zz
        if zz != 0
            oc = 1 + gv(g_drate, (r, v, cur)).v
            scal["OBJ_C"] = oc
            my_fs, f, cnt = 0.0, 0.0, 0.0
            for (_, _, _, _, ll, jot) in get(idc_of, (r, v, p), NTuple{6,String}[])
                cnt = ageax.pos[jot]
                for (_, a) in get(opyear_of_jot, (jot,), NTuple{2,String}[])
                    y = lead(yax, ll, -ageax.pos[a])
                    y === nothing || (my_fs += gv(obj_disc, (r, y, cur)).v)
                end
                f += gv(obj_disc, (r, ll, cur)).v
            end
            my_fs = my_fs / f / cnt - 1
            f = (oc^cnt - 1) / (1 - 1 / oc) / cnt - 1
            cnt = max(1.0e-5, zz)
            zz = (oc^cnt - 1) / (1 - 1 / oc) / cnt - 1
            scal["MY_F"] = my_fs; scal["CNT"] = cnt; scal["Z"] = zz
        else
            f = 1.0
        end
        scal["F"] = f
        gassign!(obj_divi, (r, v, p), 1 / (1 + (zz == 0 ? 0.0 : zz * my_fs / f)))
    end
    # L231: OBJ_SUMII(R,V,P,LIFE,LL,JOT+(1-ORD(JOT)))$OBJ_IDC(R,V,P,LIFE,LL,JOT) = YES; L232: OPTION CLEAR=OBJ_IDC
    for (r, v, p, l, ll, _) in obj_idc
        push!(obj_sumii, (r, v, p, l, ll, a1))
    end

    # ---- L237-240: INVSTEP, INVSPRED (and coef_alt.lin INV) -------------------------------
    kage = Set((k[5], k[6]) for k in obj_sumii)                                                 # L237
    invstep = Set{NTuple{4,String}}()
    for (ll, jot) in kage, (_, a) in get(opyear_of_jot, (jot,), NTuple{2,String}[])           # L238
        y = lead(yax, ll, ageax.pos[a] - 1)
        y === nothing || push!(invstep, (ll, jot, y, jot))
    end
    invspred = Set{NTuple{4,String}}()
    obj_jd = Dict{NTuple{4,String},Float64}()
    obj_divi_alt = !isempty(ct)
    rtp_capvl = P("RTP_CAPVL", 3)
    if obj_divi_alt                                                                             # L239: coef_alt.lin INV
        # L92: OBJ_JD(RDCUR(R,CUR),K,JOT)$KAGE(K,JOT) = 1
        for (r, cur) in rdcur, (k, jot) in kage
            (k,) in K && gassign!(obj_jd, (r, cur, k, jot), 1.0)
        end
        # L94-96: the investment divisors
        for k in obj_yes
            (r, v, p) = k
            k in obj_i2 && continue
            gassign!(obj_divi, k, 1 + ((v,) in T ? min(gv(ipd, (v,)).v - 1, rnd(tl(k)) - 1) : 0.0))
        end
        for k in obj_yes
            (k in obj_1b && rnd(tl(k)) == 1) && gassign!(obj_divi, k, gv(tlife, k))
        end
        for k in obj_yes
            ((k[2],) in T && nz(gv(rtp_capvl, k))) || continue
            gassign!(obj_divi, k, gv(obj_divi, k) / (one + gv(rtp_capvl, k)))
        end
    end
    # L98-99 (coef_alt.lin) or L268-269 (eqobjinv.mod): the decommissioning divisors
    obj_diviii = Dict{NTuple{3,String},Float64}()
    function diviii!()
        for k in obj_sums3
            gassign!(obj_diviii, k, gv(obj_divi, k))
        end
        for k in obj_sums3
            k in obj_i2 && gassign!(obj_diviii, k, rnd(gv(dlife, k).v))
        end
    end
    if obj_divi_alt
        diviii!()
        # L101-103: past-milestone investments: OBJ_CRFD, then OBJ_PASTI, then OPTION CLEAR=OBJ_CRFD
        crfd = Dict{NTuple{4,String},Float64}()
        sumii_of = indexby(_gset_from("OBJ_SUMII", collect(obj_sumii), d), (1, 2, 3))
        for (k4, _) in obj_pasti
            (r, v, p, cur) = k4
            (v,) in pastmile || continue
            s = GZERO
            for (_, _, _, _, kk, _) in get(sumii_of, (r, v, p), NTuple{6,String}[])
                s = s + gv(ncap_pasti, (r, v, p)) * gv(obj_crf, k4) / gv(obj_disc, (r, kk, cur))
            end
            gassign!(crfd, k4, s)
        end
        vnt_of_v = indexby(S("VNT", 2), (1,))
        coef_cpt, obj_pvt = P("COEF_CPT", 4), P("OBJ_PVT", 3)
        for (k4, _) in crfd
            (r, v, p, cur) = k4
            s = GZERO
            for (_, t) in get(vnt_of_v, (v,), NTuple{2,String}[])
                s = s + gv(coef_cpt, (r, v, t, p)) * gv(obj_pvt, (r, t, cur))
            end
            gassign!(obj_pasti, k4, s * gv(crfd, k4) / gv(cor_salvi, k4))
        end
        # coef_alt.lin L110-117 (DOFIX, reached from DOINV): FIL, KAGE, INVSPRED, OBJ_JD; then CLEAR INVSTEP
        fil = Set{Tuple{String}}()
        for (t,) in T
            y = ylead(t, gv(B, (t,)).v - yv(t))
            y === nothing || push!(fil, (y,))
        end
        gput!(tm, "FIL", fil)
        kage = Set((k, jot) for (k, jot, k2, jot2) in invstep if k == k2 && jot == jot2 && (k,) in K && !((k,) in fil))
        for (ll,) in fil, jot in ageax.labels
            ageax.pos[jot] > 1 || continue
            x = lead(yax, ll, -floor(Int, ageax.pos[jot] / 2))
            (x !== nothing && (x,) in fil && (x, jot, x, jot) in invstep) && push!(kage, (x, jot))
        end
        for (ll, jot, kk, jot2) in invstep
            (jot2 == jot && (kk,) in K) || continue
            if !((ll, jot) in kage)
                push!(invspred, (ll, jot, kk, kk))                                            # L114
            else
                y = lead(yax, ll, floor(Int, ageax.pos[jot] / 2))
                y === nothing || push!(invspred, (ll, jot, y, kk))                             # L115
            end
        end
        isp_of = indexby(_gset_from("INVSPRED", collect(invspred), d), (1, 2))
        for (r, cur) in rdcur, (ll, jot) in kage                                               # L116
            s = GZERO
            for (_, _, y, kk) in get(isp_of, (ll, jot), NTuple{4,String}[])
                s = s + gv(obj_disc, (r, kk, cur)) / gv(obj_disc, (r, y, cur))
            end
            gassign!(obj_jd, (r, cur, ll, jot), GNum(Float64(ageax.pos[jot])) / s)
        end
        empty!(invstep)                                                                        # L117
    end
    for (ll, jot, kk, jot2) in invstep                                                          # L240
        (jot2 == jot && (kk,) in K) && push!(invspred, (ll, jot, kk, kk))
    end

    # ---- L245-258: decommissioning spreads --------------------------------------------------
    dlag = P("NCAP_DLAG", 3)
    lastll = S("LASTLL", 1)
    uncd7 = Set{NTuple{7,String}}()
    for (r, v, p, l, ll, jot) in obj_sumii                                                       # L247
        (r, v, p) in obj_sums3 || continue
        l2 = agelead(l, gv(dlife, (r, v, p)).v - ageax.pos[l])
        l2 === nothing && continue
        ll2 = (r, v, p) in obj_i2 ? yax.years[mod1(yax.pos[ll] - yax.pos[ll], length(yax.years))] : ll
        push!(uncd7, (r, v, p, l2, ll2, ll, jot))
    end
    ykage = Set{NTuple{3,String}}()
    for (r, v, p, l, ll, kk, jot) in uncd7                                                       # L251
        ((ll,) in lastll && (kk,) in K) && push!(ykage, (ll, kk, l))
    end
    for (y, ll, jot) in ykage, (_, a) in get(opyear_of_jot, (jot,), NTuple{2,String}[])         # L252
        (ll,) in K || continue
        y2 = lead(yax, ll, ageax.pos[a] - 1)
        y2 === nothing || push!(invspred, (y, jot, y2, ll))
    end
    isp4 = indexby(_gset_from("INVSPRED", collect(invspred), d), (1, 2))                      # (year,jot) -> INVSPRED
    isp_k = indexby(_gset_from("INVSPRED", collect(invspred), d), (1, 2, 4))                  # (year,life,k_eoh)
    obj_sumiii = Set{NTuple{6,String}}()
    uncd7_sorted = collect(uncd7); gams_sort!(uncd7_sorted, d)
    for (r, v, p, l, y, ke, jot) in uncd7_sorted                                                  # L253-257
        (ke,) in k_eoh || continue
        f = ceil(tl((r, v, p)) + gv(dlag, (r, v, p)).v)
        scal["F"] = f
        if (y,) in lastll
            (ke,) in K || continue
            for (_, _, ll, _) in get(isp_k, (y, l, ke), NTuple{4,String}[])
                y2 = ylead(ll, f)
                y2 === nothing || push!(obj_sumiii, (r, v, p, ke, ke, y2))
            end
        else
            for (_, _, ll, kk) in get(isp4, (ke, jot), NTuple{4,String}[])
                (kk,) in K || continue
                y2 = ylead(ll, f)
                y2 === nothing || push!(obj_sumiii, (r, v, p, ll, kk, y2))
            end
        end
    end
    filter!(k -> k[1] != "0", invspred)                                                           # L258

    # ---- L262-269: the divisors without %CTST% ----------------------------------------------
    if !obj_divi_alt
        for k in obj_yes
            k in obj_1a && gassign!(obj_divi, k, 1 + ((k[2],) in S("MILESTONYR", 1) ? gv(ipd, (k[2],)).v - 1 : 0.0))
        end
        for k in obj_yes
            k in obj_1b && gassign!(obj_divi, k, gv(tlife, k))
        end
        if sc("ALTOBJ") != 0                                                                       # L265
            for k in obj_yes
                (k in obj_1b && rnd(tl(k)) - ipdc(k[2]) > 0) &&
                    gassign!(obj_divi, k, gv(ipd, (k[2],)).v * min(1.0, tl(k)))
            end
        end
        diviii!()
    end

    # ---- L273-274: CLEAR OBJ_YES, OBJ_SUMS3, YKAGE, INVSTEP, OBJ_SPRED, OBJ_I2 ------------------
    for (name, set) in (("OBJ_1A", obj_1a), ("OBJ_1B", obj_1b), ("OBJ_2A", obj_2a), ("OBJ_2B", obj_2b),
                        ("OBJ_SUMII", obj_sumii), ("OBJ_SUMIII", obj_sumiii), ("KAGE", kage), ("INVSPRED", invspred))
        gput!(tm, name, set)
    end
    for name in ("OBJ_YES", "OBJ_SUMS3", "OBJ_I2", "OBJ_IDC")
        gput!(tm, name, Set{NTuple{3,String}}())
    end
    gput!(tm, "OBJ_IDC", Set{NTuple{6,String}}())
    gput!(tm, "OBJ_SPRED", Set{NTuple{4,String}}())
    gput!(tm, "YKAGE", Set{NTuple{3,String}}())
    gput!(tm, "INVSTEP", Set{NTuple{4,String}}())
    gput!(tm, "UNCD7", uncd7)
    gput!(tm, "COR_SALVI", cor_salvi); gput!(tm, "OBJ_CRF", obj_crf); gput!(tm, "OBJ_PASTI", obj_pasti)
    gput!(tm, "OBJ_DIVI", obj_divi); gput!(tm, "OBJ_DIVIII", obj_diviii)
    gput!(tm, "FIL2", Dict((v,) => x for (v, x) in fil2 if x != 0))            # L118-119, scratch
    gput!(tm, "MY_ARRAY", Dict((v,) => x for (v, x) in my_array if x != 0))
    foreach(((n, x),) -> gput_scalar!(tm, n, x isa GNum ? x : GNum(x)), scal)
    obj_divi_alt && gput!(tm, "OBJ_JD", obj_jd)
    return tm
end
