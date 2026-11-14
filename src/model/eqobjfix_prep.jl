# M1.3 change 25-2: the data statements of eqobjfix.mod (with coef_alt.lin's FIX part) and
# eqobsalv.mod, the second part of the coef -> pre-solve step (eqobj.mod L54, L65; eqobjvar.mod
# between them has no data statements; prepret.dsc OBJFIX and OBSALV hold only equation terms).
#
# eqobjfix.mod L19-175 builds the fixed-cost spreads (OBJ_FCUR, OBJ_SUMIV, OBJ_SUMIVS for the
# decommissioning surveillance), the shape controls (RTP_SHAPE, RTP_ISHPR), the present-value
# factors OBJ_LIFE and the divisors OBJ_DIVIV; under a non-empty %CTST% it includes coef_alt.lin
# FIX (L107-131: KAGE, INVSPRED, OBJ_JD, OBJ_WD, OBJ_DIVIV) and jumps past L170-175, so OBJ_YES
# is not cleared. eqobsalv.mod L11-82 builds the salvage controls and values (OBJ_SUMS,
# OBJ_SUMS3, SALV_INV, OBJ_DCEOH, OBJSCC, OBJ_IAD, COR_SALVD, OBJ_CRFD, SALV_DEC).
#
# `OPTION a <= b` matches repeated domains from the left, `OPTION a < b` from the right (G52).
# Not translated: %VALIDATE% (refused by eqobjinv_prep_unported), %ETL% (eqobsalv.mod L65-67),
# stepped runs (L23-25).

"""
    eqobjfix_prep_symbols(tm) -> Vector{String}

The sets and parameters eqobjfix.mod L19-175 (with coef_alt.lin FIX) settle
that nothing later in the coef -> pre-solve step changes.
"""
eqobjfix_prep_symbols(tm) = ["OBJ_FCUR", "OBJ_YES", "OBJ_DIVIV", "RTP_SHAPE", "RTP_ISHPR", "OBJ_SUMIV", "OBJ_SUMIVS",
                             "OBJ_LIFE", "KAGE", "INVSTEP", "INVSPRED", "OBJ_JD", "OBJ_WD", "YKAGE"]

"""
    eqobsalv_prep_symbols(tm) -> Vector{String}

The sets and parameters eqobsalv.mod L11-82 settle.
"""
eqobsalv_prep_symbols(tm) = ["OBJ_SALI", "OBJ_SUMS", "OBJ_SUMS3", "OBJ_SUMSI", "SALV_INV", "OBJ_DCEOH", "OBJSCC",
                             "OBJ_IAD", "COR_SALVD", "OBJ_CRFD", "SALV_DEC"]

"""
    eqobjfix_prep!(tm) -> tm

eqobjfix.mod L19-175 with coef_alt.lin L107-131 (FIX) under a non-empty
%CTST%, statement by statement; see the comments for each line.

GAMS: eqobjfix.mod L19-175, coef_alt.lin L105-131, v4.9.7.
"""
function eqobjfix_prep!(tm::TimesModel)
    d = tm.data
    yax = YearAxis(tm)
    ageax = OrdAxis(tm, "AGE")
    jax = OrdAxis(tm, "J")
    a1 = ageax.labels[1]
    yv(y) = yax.yearval[y]
    S(name, n) = gset_opt(d, name, n)
    P(name, n) = gparam_opt(d, name, n)
    sc(name) = gscalar(tm, name)
    K, T = S("EACHYEAR", 1), S("MILESTONYR", 1)
    agelead(a, n) = lead(ageax, a, glead(n))
    ylead(y, n) = lead(yax, y, glead(n))
    rnd(x) = round(x, RoundNearestTiesAway)
    B, E = P("B", 1), P("E", 1)
    ipd = P("IPD", 1)
    ct = ctst(tm)
    nz(x::GNum) = x.v != 0 || x.eps
    rtp = gset(tm, "RTP")
    rtp_sorted = collect(rtp); gams_sort!(rtp_sorted, d)
    curs = [k[1] for k in S("CUR", 1).keys]
    tlife, iled, rpti, dlag = P("NCAP_TLIFE", 3), P("NCAP_ILED", 3), P("COEF_RPTI", 3), P("NCAP_DLAG", 3)
    ncap_pasti = P("NCAP_PASTI", 3)
    tl(k) = gv(tlife, k).v
    ob_fom, ob_ftx, ob_fsb, ob_dlc = P("OB_FOM", 4), P("OB_FTX", 4), P("OB_FSB", 4), P("OB_DLC", 4)

    # L33, L35: OBJ_FCUR(RTP(R,V,P),CUR)$(OBJ_FOM+OBJ_FTX+OBJ_FSB) = YES; ...$OBJ_DLAGC = YES
    obj_fcur = Set{NTuple{4,String}}()
    for (r, v, p) in rtp_sorted, cur in curs
        k = (r, p, cur, v)
        (nz(gv(ob_fom, k) + gv(ob_ftx, k) + gv(ob_fsb, k)) || nz(gv(ob_dlc, k))) && push!(obj_fcur, (r, v, p, cur))
    end
    gput!(tm, "OBJ_FCUR", obj_fcur)
    # L36-37: OPTION OBJ_YES < OBJ_FCUR; OBJ_YES(RTP_OFF(R,T,P))$(NOT NCAP_PASTI(R,T,P)) = NO
    rtp_off = S("RTP_OFF", 3)
    obj_yes = Set((k[1], k[2], k[3]) for k in obj_fcur)
    filter!(k -> !((k[2],) in T && k in rtp_off && !nz(gv(ncap_pasti, k))), obj_yes)
    # L40-41: OBJ_DIVIV
    nage = length(ageax.labels)
    obj_diviv = Dict{NTuple{3,String},Float64}()
    for k in obj_yes
        gassign!(obj_diviv, k, max(1.0, min(nage, ceil(tl(k) - 0.5))))
    end
    pyr_s, resid = S("PYR_S", 1), P("PRC_RESID", 3)
    miyr_v1 = sc("MIYR_V1")
    for (r, v, p) in obj_yes
        ((v,) in pyr_s && haskey(resid, (r, "0", p))) || continue
        sm = maximum((gv(E, (t,)).v for (t,) in T if gv(resid, (r, t, p)).v > 0); init=-Inf)
        gassign!(obj_diviv, (r, v, p), max(2.0, sm - miyr_v1 + 2))
    end
    # L45-52: RTP_SHAPE, RTP_ISHPR
    j1 = jax.labels[1]
    rtp_shape = Set{NTuple{6,String}}()
    for k in obj_yes
        for (g, x, m, extra) in (("1", "NCAP_FOMX", "NCAP_FOMM", "NCAP_CPX"), ("2", "NCAP_FTAXX", "NCAP_FTAXM", ""),
                                 ("3", "NCAP_FSUBX", "NCAP_FSUBM", ""))
            xv, mv = gv(P(x, 3), k), gv(P(m, 3), k)
            cond = xv + mv + (extra == "" ? GZERO : gv(P(extra, 3), k))
            nz(cond) || continue
            jx, jm = lead(jax, j1, glead(max(0.0, xv.v - 1))), lead(jax, j1, glead(max(0.0, mv.v - 1)))
            (jx === nothing || jm === nothing) || push!(rtp_shape, (k..., g, jx, jm))
        end
    end
    rtp_ishpr = Set((k[1], k[2], k[3]) for k in rtp_shape)                                   # L51
    cpx = P("NCAP_CPX", 3)
    filter!(k -> !(k[5] == j1 && k[6] == j1 && !nz(gv(cpx, (k[1], k[2], k[3])))), rtp_shape)  # L52
    gput!(tm, "RTP_SHAPE", rtp_shape); gput!(tm, "RTP_ISHPR", rtp_ishpr)

    # L61-78: case 1a
    obj_1a, obj_1b = S("OBJ_1A", 3), S("OBJ_1B", 3)
    obj_2a, obj_2b = S("OBJ_2A", 3), S("OBJ_2B", 3)
    modlyear = S("MODLYEAR", 1)
    fil2 = Dict(v => ((v,) in T ? gv(ipd, (v,)).v - 1 : 0.0) for (v,) in modlyear)
    my_array = Dict(v => gv(B, (v,)).v - yv(v) + ((v,) in T ? gv(P("M", 1), (v,)).v - gv(B, (v,)).v - fil2[v] : 0.0)
                    for (v,) in modlyear)
    gput!(tm, "FIL2", Dict((v,) => x for (v, x) in fil2 if x != 0))            # L66-67: the scratch as GAMS leaves it
    gput!(tm, "MY_ARRAY", Dict((v,) => x for (v, x) in my_array if x != 0))
    obj_sumiv = Set{NTuple{6,String}}()
    for k in obj_yes
        (k in obj_1a && haskey(my_array, k[2])) || continue
        (r, v, p) = k
        y = ylead(v, my_array[v])
        a, l = agelead(a1, fil2[v]), agelead(a1, gv(obj_diviv, k).v - 1)
        (y === nothing || a === nothing || l === nothing) || push!(obj_sumiv, (y, r, v, p, a, l))
    end
    # L84-105: case 1b
    ipdc(t) = ct == "" ? gv(ipd, (t,)).v : 1.0
    zhalf(zz) = ct == "" ? ceil(zz / 2 - 0.5) : floor(rnd(zz) / 2)
    istep(t, zz) = ct == "" ? gv(ipd, (t,)).v : min(gv(ipd, (t,)).v, rnd(zz))
    function sumiv!(y0, n, r, t, p, a, l)
        y = ylead(y0, n)
        (y === nothing || a === nothing || l === nothing) || push!(obj_sumiv, (y, r, t, p, a, l))
    end
    scal = Dict{String,Float64}()          # scratch scalars as the statements leave them (F, Z, MY_F, CNT, OBJ_C, OBJ_D)
    yes_sorted = collect(obj_yes); gams_sort!(yes_sorted, d)                  # LOOP order
    for k in yes_sorted
        (k in obj_1b && (k[2],) in T) || continue
        (r, t, p) = k
        zz = tl(k)
        if rnd(zz) - ipdc(t) <= 0
            my_f = gv(obj_diviv, k).v - 1
            f = gv(B, (t,)).v - zhalf(zz) - yv(t)
            zz = rnd(gv(rpti, k).v * zz) - 1
            sumiv!(t, f, r, t, p, agelead(a1, zz), agelead(a1, my_f))
            scal["MY_F"] = my_f; scal["F"] = f; scal["Z"] = zz
        else
            cnt = istep(t, zz)
            obj_d = cnt - 1
            my_f = gv(B, (t,)).v - yv(t) - floor(cnt / 2)
            c, n = 1.0, gv(rpti, k).v
            scal["Z"] = zz; scal["OBJ_D"] = obj_d; scal["CNT"] = cnt; scal["MY_F"] = my_f
            while c <= n
                f = my_f; my_f = f + zz; cnt = rnd(my_f) - rnd(f) - 1
                sumiv!(t, f, r, t, p, agelead(a1, obj_d), agelead(a1, cnt))
                scal["F"] = f; scal["MY_F"] = my_f; scal["CNT"] = cnt
                c += 1
            end
            scal["OBJ_C"] = c                                                  # FOR leaves the first value past n
        end
    end
    # L111-114: case 2a
    for k in obj_yes
        k in obj_2a || continue
        (r, v, p) = k
        sumiv!(v, gv(B, (v,)).v + gv(iled, k).v - yv(v), r, v, p, a1, agelead(a1, gv(obj_diviv, k).v - 1))
    end
    # L119-123: surveillance, case 2a
    ydom = S("Y", 1)
    obj_sumivs = Set{NTuple{5,String}}()
    function sumivs!(r, v, p, y0, n, f, z)
        kk = ylead(y0, n)
        kk === nothing && return
        for (y,) in ydom
            (yv(y) >= f && yv(y) < z) && push!(obj_sumivs, (r, v, p, kk, y))
        end
    end
    obj_2a_sorted = collect(obj_2a.keys)
    for k in obj_2a_sorted, cur in curs
        nz(gv(ob_dlc, (k[1], k[3], cur, k[2]))) || continue
        (r, v, p) = k
        my_f = gv(B, (v,)).v + gv(iled, k).v
        f = rnd(my_f + tl(k)); z = f + gv(dlag, k).v; my_f -= yv(v)
        sumivs!(r, v, p, v, my_f, f, z)
        scal["MY_F"] = my_f; scal["F"] = f; scal["Z"] = z
    end
    # L129-138: case 2b
    for k in yes_sorted
        (k in obj_2b && (k[2],) in T) || continue
        (r, t, p) = k
        zz = tl(k); my_f = rnd(gv(B, (t,)).v + gv(iled, k).v) - yv(t)
        scal["Z"] = zz; scal["MY_F"] = my_f
        c, n = 1.0, gv(rpti, k).v
        while c <= n
            f = my_f; my_f = f + zz; cnt = rnd(my_f) - rnd(f) - 1
            sumiv!(t, f, r, t, p, a1, agelead(a1, cnt))
            scal["F"] = f; scal["MY_F"] = my_f; scal["CNT"] = cnt
            c += 1
        end
        scal["OBJ_C"] = c
    end
    # L143-149: surveillance, case 2b
    obj_2b_sorted = collect(obj_2b.keys)
    for k in obj_2b_sorted, cur in curs
        ((k[2],) in T && nz(gv(ob_dlc, (k[1], k[3], cur, k[2])))) || continue
        (r, t, p) = k
        c, n = 1.0, gv(rpti, k).v
        while c <= n
            my_f = gv(B, (t,)).v + gv(iled, k).v + (c - 1) * tl(k)
            f = rnd(my_f + tl(k)); z = f + gv(dlag, k).v; my_f -= yv(t)
            sumivs!(r, t, p, t, my_f, f, z)
            scal["MY_F"] = my_f; scal["F"] = f; scal["Z"] = z
            c += 1
        end
        scal["OBJ_C"] = c
    end
    # L154-155: forget past investment charges without NCAP_PASTI
    k_eoh, pastmile = S("K_EOH", 1), S("PASTMILE", 1)
    filter!(k -> !((k[1],) in k_eoh && (k[3],) in pastmile && !nz(gv(ncap_pasti, (k[2], k[3], k[4])))), obj_sumiv)
    filter!(k -> !((k[2],) in pastmile && (k[4],) in K && !nz(gv(ncap_pasti, (k[1], k[2], k[3])))), obj_sumivs)
    gput!(tm, "OBJ_SUMIV", obj_sumiv); gput!(tm, "OBJ_SUMIVS", obj_sumivs)

    # L158-162: OBJ_LIFE, KAGE, INVSTEP
    rdcur = S("RDCUR", 2)
    curs_of_r = indexby(rdcur, (1,))
    life_tmp = Set{NTuple{5,String}}()                                       # OBJ_LIFE(K,R,JOT,LIFE,CUR) = YES
    for (kk, r, v, p, jot, l) in obj_sumiv
        (kk,) in K || continue
        for (_, cur) in get(curs_of_r, (r,), NTuple{2,String}[])
            push!(life_tmp, (kk, r, jot, l, cur))
        end
    end
    kage = Set((k[1], k[3]) for k in life_tmp)                                # L159: OPTION KAGE <= OBJ_LIFE (from the left, G52)
    opyear = S("OPYEAR", 2)
    opy_of = indexby(opyear, (1,))
    invstep = Set{NTuple{4,String}}()
    for (ll, jot) in kage, (_, a) in get(opy_of, (jot,), NTuple{2,String}[])  # L160
        y = lead(yax, ll, ageax.pos[a] - 1)
        y === nothing || push!(invstep, (ll, jot, y, jot))
    end
    step_of = indexby(_gset_from("INVSTEP", collect(invstep), d), (1, 2))
    # L161: LOOP(KAGE(K,JOT),OBJ_LIFE(LL,R,JOT,LIFE,CUR)$INVSTEP(K,JOT,LL,JOT) $= OBJ_LIFE(K,R,JOT,LIFE,CUR)),
    # in GAMS order, each pass reading what the earlier ones copied (all values are 1 here)
    live = Dict{NTuple{2,String},Vector{NTuple{3,String}}}()                   # (k, jot) -> (r, life, cur)
    for (kk, r, jot, l, cur) in life_tmp
        push!(get!(() -> NTuple{3,String}[], live, (kk, jot)), (r, l, cur))
    end
    kage_sorted = collect(kage); gams_sort!(kage_sorted, d)
    for (kk, jot) in kage_sorted
        (kk,) in K || continue
        src = copy(get(live, (kk, jot), NTuple{3,String}[]))
        for (_, _, ll, _) in get(step_of, (kk, jot), NTuple{4,String}[]), (r, l, cur) in src
            if !((ll, r, jot, l, cur) in life_tmp)
                push!(life_tmp, (ll, r, jot, l, cur))
                push!(get!(() -> NTuple{3,String}[], live, (ll, jot)), (r, l, cur))
            end
        end
    end
    obj_disc, y_eoh = P("OBJ_DISC", 3), S("Y_EOH", 1)
    obj_life = Dict{NTuple{5,String},Float64}()
    for (ll, r, jot, l, cur) in life_tmp                                      # L162 (K(LL) only)
        (ll,) in K || continue
        s = GZERO
        for (_, a) in get(opy_of, (l,), NTuple{2,String}[])
            y = lead(yax, ll, ageax.pos[a] - 1)
            (y !== nothing && (y,) in y_eoh) && (s = s + gv(obj_disc, (r, y, cur)))
        end
        gassign!(obj_life, (ll, r, jot, l, cur), s)
    end
    for k in life_tmp                                                         # entries outside K keep the YES (1)
        (k[1],) in K || gassign!(obj_life, k, 1.0)
    end

    invspred = gmembers(tm, "INVSPRED", 4)
    obj_jd, obj_wd = gvalues(tm, "OBJ_JD", 4), Dict{NTuple{5,String},Float64}()
    obj_yes_keep = !isempty(ct)
    if !isempty(ct)                                                           # L164: coef_alt.lin FIX
        fil = Set{Tuple{String}}()
        for (t,) in T
            y = ylead(t, gv(B, (t,)).v - yv(t))
            y === nothing || push!(fil, (y,))
        end
        gput!(tm, "FIL", fil)
        kage = Set((k, jot) for (k, jot, k2, jot2) in invstep if k == k2 && jot == jot2 && (k,) in K && !((k,) in fil))   # L111
        for (ll,) in fil, jot in ageax.labels                                 # L112
            ageax.pos[jot] > 1 || continue
            x = lead(yax, ll, -floor(Int, ageax.pos[jot] / 2))
            (x !== nothing && (x,) in fil && (x, jot, x, jot) in invstep) && push!(kage, (x, jot))
        end
        for (ll, jot, kk, jot2) in invstep                                    # L114-115
            (jot2 == jot && (kk,) in K) || continue
            if !((ll, jot) in kage)
                push!(invspred, (ll, jot, kk, kk))
            else
                y = lead(yax, ll, floor(Int, ageax.pos[jot] / 2))
                y === nothing || push!(invspred, (ll, jot, y, kk))
            end
        end
        isp_of = indexby(_gset_from("INVSPRED", collect(invspred), d), (1, 2))
        for (r, cur) in rdcur, (ll, jot) in kage                              # L116
            s = GZERO
            for (_, _, y, kk) in get(isp_of, (ll, jot), NTuple{4,String}[])
                s = s + gv(obj_disc, (r, kk, cur)) / gv(obj_disc, (r, y, cur))
            end
            gassign!(obj_jd, (r, cur, ll, jot), GNum(Float64(ageax.pos[jot])) / s)
        end
        for (r, cur) in rdcur, (ll, jot, kk, jot2) in invstep                 # L120
            (jot2 == jot && (kk,) in K && !((ll, jot) in kage)) && gassign!(obj_wd, (r, cur, ll, jot, kk), 1.0)
        end
        for (r, cur) in rdcur, (ll, jot) in kage                              # L121
            for (_, _, y, kk) in get(isp_of, (ll, jot), NTuple{4,String}[])
                (kk,) in K || continue
                s = GZERO
                for (_, _, y2, kk2) in get(isp_of, (ll, jot), NTuple{4,String}[])
                    kk2 == kk && (s = s + gv(obj_disc, (r, kk, cur)) / gv(obj_disc, (r, y2, cur)))
                end
                x = s * gv(obj_jd, (r, cur, ll, jot))
                nz(x) && gassign!(obj_wd, (r, cur, ll, jot, kk), x)
            end
        end
        empty!(kage)                                                          # L122
        rtp_capvl = P("RTP_CAPVL", 3)
        for k in obj_yes                                                      # L124-126
            (k[2],) in pastmile && gassign!(obj_diviv, k, 1.0)
        end
        for k in obj_yes
            (k[2],) in T || continue
            # MAX(1,MIN(IPD(T),ROUND(NCAP_TLIFE))$(OBJ_1B+OBJ_1A)): the $ conditions the MIN only, so cases 2a/2b get 1
            gassign!(obj_diviv, k, max(1.0, (k in obj_1b || k in obj_1a) ? min(gv(ipd, (k[2],)).v, rnd(tl(k))) : 0.0))
        end
        for k in obj_yes
            ((k[2],) in T && nz(gv(rtp_capvl, k))) && gassign!(obj_diviv, k, gv(obj_diviv, k) / (1 + gv(rtp_capvl, k)))
        end
        # L128-131: residual capacities
        g_rcur, vnt, obj_pvt = S("G_RCUR", 2), S("VNT", 2), P("OBJ_PVT", 3)
        vnt_of = indexby(vnt, (1,))
        for (kk, r, v, p, jot, l) in sort!(collect(obj_sumiv))
            (kk == v && (v,) in pyr_s && haskey(resid, (r, "0", p))) || continue
            for (rr, cur) in g_rcur
                rr == r || continue
                s = GZERO
                for (_, t) in get(vnt_of, (v,), NTuple{2,String}[])
                    haskey(resid, (r, t, p)) && (s = s + gv(resid, (r, t, p)) * gv(obj_pvt, (r, t, cur)))
                end
                gassign!(obj_diviv, (r, v, p), gv(ncap_pasti, (r, v, p)) * gv(obj_life, (v, r, jot, l, cur)) / s)
            end
        end
    end
    if isempty(ct)
        for (ll, jot) in kage, (_, _, kk, jot2) in get(step_of, (ll, jot), NTuple{4,String}[])  # L165
            (jot2 == jot && (kk,) in K) && push!(invspred, (ll, jot, kk, kk))
        end
        for k in obj_yes                                                      # L170-172
            (k[2],) in pastmile && gassign!(obj_diviv, k, 1.0)
        end
        for k in obj_yes
            ((k[2],) in T && !(k in obj_1b)) && gassign!(obj_diviv, k, 1 + (k in obj_1a ? gv(ipd, (k[2],)).v - 1 : 0.0))
        end
        if sc("ALTOBJ") != 0
            for k in obj_yes
                ((k[2],) in T && k in obj_1b && rnd(tl(k)) - ipdc(k[2]) > 0) && gassign!(obj_diviv, k, gv(ipd, (k[2],)))
            end
        end
    end
    gput!(tm, "OBJ_LIFE", obj_life)
    gput!(tm, "KAGE", kage)
    gput!(tm, "INVSPRED", invspred)
    gput!(tm, "OBJ_DIVIV", obj_diviv)
    if !isempty(ct)
        gput!(tm, "OBJ_JD", obj_jd); gput!(tm, "OBJ_WD", obj_wd)
        gput!(tm, "OBJ_YES", obj_yes)                                         # L169 jumps past the clear of L175
    else
        gput!(tm, "OBJ_YES", Set{NTuple{3,String}}()); gput!(tm, "YKAGE", Set{NTuple{3,String}}())   # L175
    end
    gput!(tm, "INVSTEP", invstep)                                             # coef_alt.lin L117 is commented out under FIX
    foreach(((n, x),) -> gput_scalar!(tm, n, x), scal)
    return tm
end

"""
    eqobsalv_prep!(tm) -> tm

eqobsalv.mod L11-82, the salvage controls and values:

    OBJ_SALI(OBJ_SUMII(R,V%PFT%,P,AGE,K_EOH,JOT),K,LL--ORD(LL))\$((YEARVAL(K)+NCAP_TLIFE(R,V,P)-1>MIYR_VL)
        \$INVSPRED(K_EOH,JOT,K,LL))=YES;                                                                   (L31)
    OPTION OBJ_SUMSI <= OBJ_SALI, CLEAR=OBJ_SALI;                                                          (L32)
    LOOP((RP(R,PRC),P)\$PRC_REFIT(RP,P),IF(PRC_REFIT(RP,P)<0, OBJ_SUMSI(R,T,P,K)=NO));                     (L35)
    OPTION OBJ_SUMS <= OBJ_SUMSI;                                                                          (L36)
    LOOP(OBJ_SUMIII(OBJ_SUMS(R,V,P),LL,K,Y), OBJ_SUMS3(R,V,P) = YES);                                     (L39)
    LOOP(OBJ_SUMIVS(R,V,P,K,Y)\$(YEARVAL(K)+NCAP_TLIFE(R,V,P)-1 GT MIYR_VL),
      OBJ_SUMS3(R,V,P) = YES; OBJ_SUMSI(R,V,P,K) = YES);                                                  (L41-42)
    LOOP(RDCUR(R,CUR), SALV_INV(OBJ_SUMSI(R,V,P,K))\$OBJ_ICUR(R,V,P,CUR) =
      MIN(1,(((1+G_DRATE)*EXP(NCAP_FDR))**(NCAP_TLIFE+YEARVAL(K)-MIYR_VL-1)-1) /
            (((1+G_DRATE)*EXP(NCAP_FDR))**NCAP_TLIFE-1)));                                              (L45-50)
    LOOP(MIYR_1(LL), F = MIYR_VL+1-YEARVAL(MIYR_1); OBJ_DCEOH(RDCUR(R,CUR)) = OBJ_DISC(R,LL+F,CUR));       (L52)
    Z = SMAX(T\$(B(T)<=MIYR_VL+1),ORD(T)-1);
    LOOP(MIYR_1(T-Z), SALV_INV(OBJ_SUMSI(RTP,K))\$NCAP_CPX(RTP) = SALV_INV(RTP,K)*(1+RTP_CPX(RTP,T)));      (L54-55)
    OPTION CLEAR = OBJ_SUMSI;                                                                              (L57)
    OBJSCC(OBJ_ICUR(OBJ_SUMS(R,V,P),CUR)) = COR_SALVI/OBJ_DCEOH/OBJ_DIVI *
      SUM((OBJ_SUMII(R,V,P,AGE,K_EOH,JOT),INVSPRED(K_EOH,JOT,LL,K))\$SALV_INV(R,V,P,LL),
          %CAPJD% (OBJ_ICOST+OBJ_ITAX-OBJ_ISUB)(R,K,P,CUR) * SALV_INV(R,V,P,LL) * OBJ_DISC(R,K,CUR));       (L61-63)
    OBJ_IAD(RDCUR(R,CUR)) = SUM(OBJ_ICUR(OBJ_SUMS(R,PASTMILE(V),P),CUR)\$((OBJ_PASTI(R,V,P,CUR)=0)+0%CTST%),
                                OBJSCC*NCAP_PASTI*OBJ_DCEOH);                                              (L70)
    COR_SALVD(RTP(R,V,P),CUR)\$OBJ_DCOST = (((1-1/(1+DR))*(1-1/(1+RFR)**DELIF))/
      ((1-1/(1+RFR))*(1-1/(1+DR)**DELIF)))\$(DR GT 0) + 1\$(DR EQ 0);                                    (L73-76)
    OBJ_CRFD(RTP(R,V,P),CUR)\$OBJ_DCOST = COR_SALVD*(1-(1/(1+G_DRATE)))/(1-(1+G_DRATE)**(-ROUND(NCAP_DELIF)));   (L77)
    SALV_DEC(OBJ_SUMS3(R,V,P),CUR)\$COR_SALVD = COR_SALVD/OBJ_DIVIII/OBJ_DCEOH *
      SUM(OBJ_SUMIII(R,V,P,LL,K,Y)\$SALV_INV(R,V,P,LL),SALV_INV(R,V,P,LL)*OBJ_DCOST(R,K,P,CUR)*OBJ_DISC(R,Y,CUR));   (L81-82)

%PFT% is (T) without early retirement (VNRET not declared) under a non-empty
%CTST% (L26-27), '' otherwise; %CAPJD% is OBJ_JD(R,CUR,K_EOH,JOT)* under a
non-empty %CTST% (coef_alt.lin L91); `0%CTST%` is 0**0 = 1 or 0**EPS = 1
then, 0 otherwise. `OPTION a <= b` matches from the left (G52).

In a stepped (myopic) run (`\$IF SET TIMESTEP`) L23 clears OBJ_SUMS, OBJ_SUMS3,
SALV_INV and OBJSCC and L24-25 jump to the equation: L26-82 run inside each
step instead (solve.stp L127), which is part of the stepped solve.

GAMS: eqobsalv.mod L11-82, v4.9.7.
"""
function eqobsalv_prep!(tm::TimesModel)
    uppercase(gswitch(tm, "ETL", "")) == "YES" && throw(UnportedError("eqobsalv.mod L65-67: %ETL% YES"))
    if stepped(tm)
        # L23: $IF SET TIMESTEP OPTION CLEAR=OBJ_SUMS,CLEAR=OBJ_SUMS3,CLEAR=SALV_INV,CLEAR=OBJSCC;
        # L24-25: %STEPPED% is '+' and %1 is mod, so $GOTO EQUA: L26-82 are skipped. The symbols declared at
        # L13-17 stay empty; solve.stp L127 runs L26-82 inside each step (`eqobsalv.mod STP EXIT`).
        gput!(tm, "OBJ_SUMS", Set{NTuple{3,String}}()); gput!(tm, "OBJ_SUMS3", Set{NTuple{3,String}}())
        gput!(tm, "SALV_INV", Dict{NTuple{4,String},Float64}()); gput!(tm, "OBJSCC", Dict{NTuple{4,String},Float64}())
        gput!(tm, "OBJ_SALI", Set{NTuple{8,String}}()); gput!(tm, "OBJ_DCEOH", Dict{NTuple{2,String},Float64}())
        gput!(tm, "SALV_DEC", Dict{NTuple{4,String},Float64}())
        return tm
    end
    d = tm.data
    yax = YearAxis(tm)
    yv(y) = yax.yearval[y]
    S(name, n) = gset_opt(d, name, n)
    P(name, n) = gparam_opt(d, name, n)
    sc(name) = gscalar(tm, name)
    K, T = S("EACHYEAR", 1), S("MILESTONYR", 1)
    nz(x::GNum) = x.v != 0 || x.eps
    ct = ctst(tm)
    miyr_vl = sc("MIYR_VL")
    tlife = P("NCAP_TLIFE", 3)
    tl(k) = gv(tlife, k).v
    k_eoh = S("K_EOH", 1)
    pft_t = !Reference.has_symbol(d.dump, "RP_RTF") && !isempty(ct)             # L26-27
    obj_sumii = S("OBJ_SUMII", 6)
    invspred = S("INVSPRED", 4)
    isp_of = indexby(invspred, (1, 2))                                          # (k_eoh, jot) -> INVSPRED
    obj_sumsi = Set{NTuple{4,String}}()
    for (r, v, p, a, ke, jot) in obj_sumii                                      # L31-32
        ((ke,) in k_eoh && (!pft_t || (v,) in T)) || continue
        for (_, _, kk, _) in get(isp_of, (ke, jot), NTuple{4,String}[])
            ((kk,) in K && yv(kk) + tl((r, v, p)) - 1 > miyr_vl) && push!(obj_sumsi, (r, v, p, kk))
        end
    end
    gput!(tm, "OBJ_SALI", Set{NTuple{8,String}}())
    refit = P("PRC_REFIT", 3)                                                   # L35
    rp = S("RP", 2)
    neg = Set((k[1], k[3]) for (k, x) in refit.values if (k[1], k[2]) in rp && x < 0)
    filter!(k -> !((k[2],) in T && (k[1], k[3]) in neg), obj_sumsi)
    obj_sums = Set((k[1], k[2], k[3]) for k in obj_sumsi)                       # L36
    obj_sums3 = gmembers(tm, "OBJ_SUMS3", 3)
    for k in S("OBJ_SUMIII", 6)                                                 # L39
        (k[1], k[2], k[3]) in obj_sums && push!(obj_sums3, (k[1], k[2], k[3]))
    end
    ydom = S("Y", 1)
    for (r, v, p, kk, y) in S("OBJ_SUMIVS", 5)                                  # L41-42
        ((kk,) in K && (y,) in ydom && yv(kk) + tl((r, v, p)) - 1 > miyr_vl) || continue
        push!(obj_sums3, (r, v, p)); push!(obj_sumsi, (r, v, p, kk))
    end
    gput!(tm, "OBJ_SUMS", obj_sums); gput!(tm, "OBJ_SUMS3", obj_sums3)
    rdcur = S("RDCUR", 2)
    rdcur_sorted = collect(rdcur.keys)
    obj_icur = S("OBJ_ICUR", 4)
    g_drate, fdr = P("G_DRATE", 3), P("NCAP_FDR", 3)
    salv_inv = Dict{NTuple{4,String},Float64}()
    sumsi_of_r = indexby(_gset_from("OBJ_SUMSI", collect(obj_sumsi), d), (1,))
    one = GNum(1.0)
    for (r, cur) in rdcur_sorted                                                # L45-50
        for (_, v, p, kk) in get(sumsi_of_r, (r,), NTuple{4,String}[])
            (r, v, p, cur) in obj_icur || continue
            b = (one + gv(g_drate, (r, v, cur))) * gexp(gv(fdr, (r, v, p)))
            x = (gpow(b, GNum(tl((r, v, p)) + yv(kk) - miyr_vl - 1)) - one) / (gpow(b, gv(tlife, (r, v, p))) - one)
            gassign!(salv_inv, (r, v, p, kk), gmin(one, x))
        end
    end
    obj_disc = P("OBJ_DISC", 3)
    obj_dceoh = Dict{NTuple{2,String},Float64}()
    for (ll,) in S("MIYR_1", 1)                                                 # L52
        gput_scalar!(tm, "F", miyr_vl + 1 - yv(ll))
        y = lead(yax, ll, glead(miyr_vl + 1 - yv(ll)))
        for (r, cur) in rdcur_sorted
            gassign!(obj_dceoh, (r, cur), y === nothing ? GZERO : gv(obj_disc, (r, y, cur)))
        end
    end
    gput!(tm, "OBJ_DCEOH", obj_dceoh)
    tlist = [k[1] for k in T.keys]                                              # L54-55
    B = P("B", 1)
    z = maximum((i - 1 for (i, t) in enumerate(tlist) if gv(B, (t,)).v <= miyr_vl + 1); init=-Inf)
    gput_scalar!(tm, "Z", z)
    miyr_1 = S("MIYR_1", 1)
    cpx, rtp_cpx = P("NCAP_CPX", 3), P("RTP_CPX", 4)
    rtp = S("RTP", 3)
    for (i, t) in enumerate(tlist)
        isfinite(z) || continue
        j = i - Int(z)
        (1 <= j <= length(tlist) && (tlist[j],) in miyr_1) || continue
        for (r, v, p, kk) in obj_sumsi
            ((r, v, p) in rtp && nz(gv(cpx, (r, v, p)))) || continue
            gassign!(salv_inv, (r, v, p, kk), gv(salv_inv, (r, v, p, kk)) * (one + gv(rtp_cpx, (r, v, p, t))))
        end
    end
    gput!(tm, "SALV_INV", salv_inv)
    gput!(tm, "OBJ_SUMSI", Set{NTuple{4,String}}())                            # L57
    # L61-63: OBJSCC
    cor_salvi, obj_divi = P("COR_SALVI", 4), P("OBJ_DIVI", 3)
    obj_jd = P("OBJ_JD", 4)
    ob_icost, ob_itax, ob_isub = P("OB_ICOST", 4), P("OB_ITAX", 4), P("OB_ISUB", 4)
    sumii_of = indexby(obj_sumii, (1, 2, 3))
    objscc = Dict{NTuple{4,String},Float64}()
    icur_keys = obj_icur.keys
    for (r, v, p, cur) in icur_keys
        (r, v, p) in obj_sums || continue
        s = GZERO
        for (_, _, _, a, ke, jot) in get(sumii_of, (r, v, p), NTuple{6,String}[])
            (ke,) in k_eoh || continue
            for (_, _, ll, kk) in get(isp_of, (ke, jot), NTuple{4,String}[])
                (kk,) in K || continue
                si = gv(salv_inv, (r, v, p, ll))
                nz(si) || continue
                c = gv(ob_icost, (r, p, cur, kk)) + gv(ob_itax, (r, p, cur, kk)) - gv(ob_isub, (r, p, cur, kk))
                term = c * si * gv(obj_disc, (r, kk, cur))
                isempty(ct) || (term = gv(obj_jd, (r, cur, ke, jot)) * term)
                s = s + term
            end
        end
        gassign!(objscc, (r, v, p, cur), gv(cor_salvi, (r, v, p, cur)) / gv(obj_dceoh, (r, cur)) / gv(obj_divi, (r, v, p)) * s)
    end
    gput!(tm, "OBJSCC", objscc)
    # L70: OBJ_IAD
    pastmile, ncap_pasti, obj_pasti = S("PASTMILE", 1), P("NCAP_PASTI", 3), P("OBJ_PASTI", 4)
    obj_iad = Dict{NTuple{2,String},Float64}()
    for (r, cur) in rdcur_sorted
        s = GZERO
        for (rr, v, p, c) in icur_keys
            (rr == r && c == cur && (v,) in pastmile && (r, v, p) in obj_sums) || continue
            (isempty(ct) && gv(obj_pasti, (r, v, p, cur)).v != 0) && continue
            s = s + gv(objscc, (r, v, p, cur)) * gv(ncap_pasti, (r, v, p)) * gv(obj_dceoh, (r, cur))
        end
        gassign!(obj_iad, (r, cur), s)
    end
    gput!(tm, "OBJ_IAD", obj_iad)
    # L73-77: COR_SALVD, OBJ_CRFD
    ob_dcc = P("OB_DCC", 4)
    drate, rfr, delif = P("NCAP_DRATE", 3), P("OBJ_RFR", 3), P("NCAP_DELIF", 3)
    cor_salvd = Dict{NTuple{4,String},Float64}()
    obj_crfd = gvalues(tm, "OBJ_CRFD", 4)
    curs = [k[1] for k in S("CUR", 1).keys]
    for (r, v, p) in rtp, cur in curs
        nz(gv(ob_dcc, (r, p, cur, v))) || continue
        dr, rf, de = gv(drate, (r, v, p)), gv(rfr, (r, v, cur)), gv(delif, (r, v, p))
        x = dr.v > 0 ? ((one - one / (one + dr)) * (one - one / gpow(one + rf, de))) /
                       ((one - one / (one + rf)) * (one - one / gpow(one + dr, de))) : GZERO
        x = x + (dr.v == 0 ? one : GZERO)
        gassign!(cor_salvd, (r, v, p, cur), x)
        gd = gv(g_drate, (r, v, cur))
        gassign!(obj_crfd, (r, v, p, cur),
                 x * (one - one / (one + gd)) / (one - gpow(one + gd, GNum(-round(de.v, RoundNearestTiesAway)))))
    end
    gput!(tm, "COR_SALVD", cor_salvd); gput!(tm, "OBJ_CRFD", obj_crfd)
    # L81-82: SALV_DEC
    obj_diviii = P("OBJ_DIVIII", 3)
    sumiii_of = indexby(S("OBJ_SUMIII", 6), (1, 2, 3))
    salv_dec = Dict{NTuple{4,String},Float64}()
    for ((r, v, p, cur), _) in cor_salvd
        (r, v, p) in obj_sums3 || continue
        s = GZERO
        for (_, _, _, ll, kk, y) in get(sumiii_of, (r, v, p), NTuple{6,String}[])
            si = gv(salv_inv, (r, v, p, ll))
            nz(si) || continue
            s = s + si * gv(ob_dcc, (r, p, cur, kk)) * gv(obj_disc, (r, y, cur))
        end
        gassign!(salv_dec, (r, v, p, cur),
                 gv(cor_salvd, (r, v, p, cur)) / gv(obj_diviii, (r, v, p)) / gv(obj_dceoh, (r, cur)) * s)
    end
    gput!(tm, "SALV_DEC", salv_dec)
    return tm
end
