# M1.2 (5): the linearised-objective coefficients, and COEF_CPT under
# OBLONG / OBJ MOD / ALT / LIN.
#
# GAMS (v4.9.7): coef_alt.lin L11-87 and L159-161, as coefmain.mod L26
# includes it: `$BATINCLUDE coef_alt.lin VAR%CTST%`, so %1 is VAR, VAR**0 or
# VAR**EPS. The INV, FIX and STP calls (eqobjinv.mod L239, eqobjfix.mod L164,
# solve.stp L124) run during equation generation and stepped solves and are
# not part of the coefficient stage.
#
# Paths:
# - L13-22: declarations (first call).
# - L31-37: PERDINV, TPULSEYR, TPULSE (always).
# - L40-44: LINFLO = 1 when %CTST% is **EPS (OBJ ALT or LIN); LINACC = 1 for
#   OBJ LIN, or OBLONG with OBJ ALT; ILED is dropped from L78 when OBLONG and
#   LINFLO.
# - L46-47 (LINFLO): FPD, OBJ_PVT, COEF_PVT from the pulses.
# - L49-53: OBJ_ALTV for |ALTOBJ| = 2 (OBJ ALT); L55-58: OBJ_LINT.
# - L59: with %CTST% empty (%1 = VAR: OBJ AUTO or STD without OBLONG) the
#   include ends here: COEF_CPT then comes from coef_cpt.mod L19-21, and YK1
#   keeps the pairs L32 set (L66 and L160, which clear it, are not reached).
# - L65-79: PASTSUM, R_DF, RB (L74 with LINFLO), COEF_CPT; L80: OBLONG ends
#   it; L81: a stepped solve (TIMESTEP) ends it; L83-86: RTP_CAPVL otherwise.
# - L160: PASTSUM and YK1 cleared.
#
# L81 (`$IF SET TIMESTEP $GOTO DONE`): a stepped (myopic) run skips L83-86 here;
# solve.stp L124 calls the STP label (L134-158) inside each step, which is part
# of the stepped solve (M1.5) and refused at model generation. ALTOBJ is read
# from the state (initmty.mod L420-432, changed by ppmain.mod L146).

"""
    linflo(tm), linacc(tm)

`%LINFLO%` and `%LINACC%` of coef_alt.lin L40-43 (case-insensitive, like
`\$IFI`): LINFLO when `%CTST%` is `**EPS`; LINACC for OBJ LIN or for OBLONG
with OBJ ALT.
"""
linflo(tm) = ctst(tm) == "**EPS"
function linacc(tm)
    obj = uppercase(gswitch(tm, "OBJ", ""))
    oblong = uppercase(gswitch(tm, "OBLONG", "")) == "YES" || obj == "MOD"
    return obj == "LIN" || (oblong && obj == "ALT")
end

"""
    stepped(tm) -> Bool

`\$IF SET TIMESTEP`: a stepped (myopic) run, for which `%STEPPED%` is `+`
(initmty.mod L446, maindrv.mod L38). A TIMESTEP that is set is a member of AGE
(initmty.mod L443), so never empty.
"""
stepped(tm) = gswitch(tm, "TIMESTEP", "") != ""

"GAMS `LOG(x)`: a non-positive argument is an execution error."
function glog(x::GNum)
    x.v > 0 || throw(DomainError(x, "LOG of a non-positive value (GAMS: FUNC DOMAIN)"))
    return GNum(log(x.v))
end

"""
    coef_alt!(tm) -> tm

coef_alt.lin on the GAMS state in `tm`, as coefmain.mod L26 calls it:
PERDINV, TPULSEYR, TPULSE, OBJ_LINT (and OBJ_ALTV, FPD, OBJ_PVT, COEF_PVT
when the switches ask); then, unless `%CTST%` is empty, R_DF, RB, COEF_CPT
(replacing coef_cpt.mod's, which computed none in that case) and, without
OBLONG and outside a stepped run (L80-81), RTP_CAPVL. PASTSUM and YK1 are
left cleared.

GAMS: coef_alt.lin L11-87, L159-161 (coefmain.mod L26), v4.9.7.
"""
function coef_alt!(tm)
    ax = YearAxis(tm)
    yv(y) = ax.yearval[y]
    S1(n) = gset(tm, n)
    t_list = [k[1] for k in S1("MILESTONYR").keys]                    # T in order
    tpos = Dict(t => i for (i, t) in enumerate(t_list))
    tnext(t) = (i = tpos[t] + 1; i <= length(t_list) ? t_list[i] : nothing)    # T+1 within MILESTONYR
    tprev(t) = (i = tpos[t] - 1; i >= 1 ? t_list[i] : nothing)
    y_eoh = Set(k[1] for k in S1("Y_EOH").keys)
    miyr_1 = Set(k[1] for k in S1("MIYR_1").keys)
    M, B, E, LEAD, LAGT = (gparam(tm, n) for n in ("M", "B", "E", "LEAD", "LAGT"))
    one = GNum(1)

    # L31: PERDINV(YK(T,K))$(YEARVAL(K) > M(T)-LEAD(T)) = YES
    perdinv = Set{NTuple{2,String}}()
    for (t, k) in S1("YK").keys
        haskey(tpos, t) || continue
        yv(k) > Float64(gv(M, (t,)) - gv(LEAD, (t,))) && push!(perdinv, (t, k))
    end
    gput!(tm, "PERDINV", perdinv)
    # L32: YK1(T,Y_EOH)$(YEARVAL(T)<=YEARVAL(Y_EOH)) = YES
    yk1 = Set((t, y) for t in t_list for y in y_eoh if yv(t) <= yv(y))
    gput!(tm, "YK1", yk1)                 # GAMS state from here on: the L59 exit leaves it so
    # L34-35
    tpulseyr = Set((t, y) for (t, y) in perdinv if y in y_eoh)
    tpulse = Dict{NTuple{2,String},Float64}()
    for (t, y) in tpulseyr
        x = one - gif((gv(M, (t,)) - GNum(yv(y))) / gv(LEAD, (t,)), !(t in miyr_1))
        gassign!(tpulse, (t, y), x)
    end
    # L36: TPULSEYR(YK1(T,Y_EOH))$(YEARVAL(Y_EOH) < M(T)+LAGT(T)) = YES
    for (t, y) in yk1
        yv(y) < Float64(gv(M, (t,)) + gv(LAGT, (t,))) && push!(tpulseyr, (t, y))
    end
    # L37: TPULSE(TPULSEYR(YK1(T,LL))) = 1-TPULSE(T+1,LL)   (RHS from before the statement, G11)
    before = copy(tpulse)
    for (t, ll) in tpulseyr
        (t, ll) in yk1 || continue
        n = tnext(t)
        gassign!(tpulse, (t, ll), one - (n === nothing ? GZERO : gv(before, (n, ll))))
    end
    gput!(tm, "TPULSEYR", tpulseyr)
    gput!(tm, "TPULSE", tpulse)
    gv_tp(t, y) = gv(tpulse, (t, y))

    rdcur, g_rcur = S1("RDCUR"), S1("G_RCUR")
    disc = gparam(tm, "OBJ_DISC")
    periodyr = indexby(S1("PERIODYR"), (1,))
    tp_by_t = Dict{String,Vector{String}}()
    for (t, y) in tpulseyr
        push!(get!(() -> String[], tp_by_t, t), y)
    end
    peri(t) = (k[2] for k in get(periodyr, (t,), NTuple{2,String}[]) if k[2] in y_eoh)
    lf, la = linflo(tm), linacc(tm)

    # L46-47 (LINFLO): FPD, OBJ_PVT, COEF_PVT from the pulses
    if lf
        fpd = gvalues(tm, "FPD", 1)
        for t in t_list
            gassign!(fpd, (t,), sum((gv_tp(t, y) for y in get(tp_by_t, t, String[])); init=GZERO))
        end
        gput!(tm, "FPD", fpd)
        obj_pvt = gvalues(tm, "OBJ_PVT", 3)
        for (r, c) in rdcur.keys, t in t_list
            gassign!(obj_pvt, (r, t, c), sum((gv_tp(t, y) * gv(disc, (r, y, c)) for y in get(tp_by_t, t, String[])); init=GZERO))
        end
        gput!(tm, "OBJ_PVT", obj_pvt)
        coef_pvt = gvalues(tm, "COEF_PVT", 2)
        for r in (k[1] for k in S1("REG").keys), t in t_list
            gassign!(coef_pvt, (r, t), sum((gv(obj_pvt, (r, t, k[2])) for k in g_rcur.keys if k[1] == r); init=GZERO))
        end
        gput!(tm, "COEF_PVT", coef_pvt)
        disc = gparam(tm, "OBJ_DISC")
    end
    obj_pvt_now, coef_pvt_now = gparam(tm, "OBJ_PVT"), gparam(tm, "COEF_PVT")

    # L49-53: OBJ_ALTV when |ALTOBJ| = 2
    altobj = gscalar(tm, "ALTOBJ")
    obj_altv = gvalues(tm, "OBJ_ALTV", 2)
    if abs(altobj) == 2
        for (r, c) in g_rcur.keys, t in t_list
            den = lf ? sum((gv(disc, (r, y, c)) for y in peri(t)); init=GZERO) :
                       sum((gv_tp(t, y) * gv(disc, (r, y, c)) for y in get(tp_by_t, t, String[])); init=GZERO)
            gassign!(obj_altv, (r, t), gv(coef_pvt_now, (r, t)) / den)
        end
    end
    gput!(tm, "OBJ_ALTV", obj_altv)
    # L55-58: OBJ_LINT
    isalt = uppercase(gswitch(tm, "OBJ", "")) == "ALT"
    obj_lint = gvalues(tm, "OBJ_LINT", 4)
    for (r, c) in rdcur.keys, t in t_list, tt in t_list
        yrs_tt = Set(get(tp_by_t, tt, String[]))
        x = if la
            sum((gv_tp(t, y) * gv_tp(tt, y) * gv(disc, (r, y, c)) for y in get(tp_by_t, t, String[]) if y in yrs_tt); init=GZERO)
        else
            sum((gv_tp(tt, y) * gv(disc, (r, y, c)) for y in peri(t) if y in yrs_tt); init=GZERO)
        end
        isalt && (x = gv(obj_altv, (r, t)) * x)
        gassign!(obj_lint, (r, t, tt, c), x)
    end
    gput!(tm, "OBJ_LINT", obj_lint)

    # L59: with %CTST% empty the include ends here
    ctst(tm) == "" && return tm

    # L65: PASTSUM(RTP(R,V,P))$PRC_CAP(R,P) = B(V)+NCAP_ILED(R,V,P)+COEF_RPTI(R,V,P)*NCAP_TLIFE(R,V,P)
    modlyear = Set(k[1] for k in S1("MODLYEAR").keys)
    prc_cap = S1("PRC_CAP")
    iled_vals = gvalues(tm, "NCAP_ILED", 3)
    rpti, tlife = gparam(tm, "COEF_RPTI"), gparam(tm, "NCAP_TLIFE")
    pastsum = Dict{NTuple{3,String},Float64}()
    rtp = S1("RTP")
    for (r, v, p) in rtp.keys
        (v in modlyear && (r, p) in prc_cap) || continue
        gassign!(pastsum, (r, v, p), gv(B, (v,)) + gv(iled_vals, (r, v, p)) + gv(rpti, (r, v, p)) * gv(tlife, (r, v, p)))
    end
    # L66: FIL2, MY_ARRAY, YK1 cleared
    # L67: LOOP(G_RCUR(R,CUR), R_DF(R,V) = 1/(1+G_DRATE(R,V,CUR)))
    gd = gparam(tm, "G_DRATE")
    r_df = gvalues(tm, "R_DF", 2)
    for (r, c) in g_rcur.keys, v in modlyear
        gassign!(r_df, (r, v), one / (one + gv(gd, (r, v, c))))
    end
    gput!(tm, "R_DF", r_df)
    # L68-69: with INT_DEFAULT('PASTI'), shorten past lead times by the discounting
    if ("PASTI",) in gset_opt(tm.data, "INT_DEFAULT", 1)
        phyr = Set(k[1] for k in S1("PHYR").keys)
        coef_iled = gparam(tm, "COEF_ILED")
        for ((r, v, p), x) in collect(iled_vals)
            (v in phyr && v in modlyear && x > coef_iled[(r, v, p)]) || continue
            rdf = gv(r_df, (r, v))
            gassign!(iled_vals, (r, v, p), glog(one - (one - rdf) * (GNum(x) - gv(coef_iled, (r, v, p)))) / glog(rdf))
        end
        gput!(tm, "NCAP_ILED", iled_vals)
    end
    # L70: RB(R,T) = B(T)
    rb = gvalues(tm, "RB", 2)
    regs = [k[1] for k in S1("REG").keys]
    for r in regs, t in t_list
        gassign!(rb, (r, t), gv(B, (t,)))
    end
    # L71 (LINFLO): YK1(T(LL),LL-FLOOR((LEAD(T)-1)/2)) = NOT MIYR_1(T)
    yk1 = Set{NTuple{2,String}}()
    if lf
        for t in t_list
            t in miyr_1 && continue
            y = lead(ax, t, -Int(floor((Float64(gv(LEAD, (t,))) - 1) / 2)))
            y === nothing || push!(yk1, (t, y))
        end
    end
    # L72-79
    coef_cpt = gvalues(tm, "COEF_CPT", 4)
    rtp_cptyr = S1("RTP_CPTYR")
    cptyr_by_r = indexby(rtp_cptyr, (1,))
    fil2 = Dict{NTuple{1,String},Float64}()
    my_array = Dict{NTuple{1,String},Float64}()
    drop_iled = uppercase(gswitch(tm, "OBLONG", "")) == "YES" && lf              # L44: %ILED% empty
    oblong = uppercase(gswitch(tm, "OBLONG", "")) == "YES" || uppercase(gswitch(tm, "OBJ", "")) == "MOD"
    for (r, c) in g_rcur.keys
        for t in t_list                                                           # L73
            gassign!(fil2, (t,), gv(r_df, (r, t)))
        end
        if lf                                                                     # L74
            for (t, year) in yk1
                den = sum((gv(disc, (r, ll, c)) for (tt, ll) in perdinv if tt == t); init=GZERO)
                z = gv(disc, (r, year, c)) / den * gv(LEAD, (t,))
                gassign!(rb, (r, t), gv(B, (t,)) - glog(z) / glog(gv(fil2, (t,))))
            end
        end
        # L75: MY_ARRAY(T) = E(T)+1; MY_ARRAY(TT(T-1)) = RB(R,T)
        for t in t_list
            gassign!(my_array, (t,), gv(E, (t,)) + one)
        end
        for t in t_list
            pt = tprev(t)
            pt === nothing || gassign!(my_array, (pt,), gv(rb, (r, t)))
        end
        # L76: MY_ARRAY(T) = 1-FIL2(T)**(MY_ARRAY(T)-RB(R,T)-1e-8)
        for t in t_list
            gassign!(my_array, (t,), one - gpow(gv(fil2, (t,)), gv(my_array, (t,)) - gv(rb, (r, t)) - GNum(1e-8)))
        end
        # L77-78
        for (_, v, t, p) in get(cptyr_by_r, (r,), NTuple{4,String}[])
            (v in modlyear && haskey(tpos, t) && haskey(pastsum, (r, v, p))) || continue
            f2, rbt, ma = gv(fil2, (t,)), gv(rb, (r, t)), gv(my_array, (t,))
            x = gmin(one, (one - gpow(f2, gv(pastsum, (r, v, p)) - rbt)) / ma)
            il = gv(iled_vals, (r, v, p))
            term = (one - gpow(f2, gmax(GZERO, gv(B, (v,)) + il - rbt))) / ma
            x -= drop_iled ? term : gif(term, !iszero(il))
            gassign!(coef_cpt, (r, v, t, p), x)
        end
        # L79: COEF_CPT(R,T,TT,P)$((COEF_CPT LT 1/512)$COEF_CPT) = 0 - both year indices are
        # MILESTONYR aliases, so a past vintage's record (which can be negative) is left alone
        for (k, x) in collect(coef_cpt)
            (k[1] == r && haskey(tpos, k[2]) && haskey(tpos, k[3]) && x < 1 / 512) && delete!(coef_cpt, k)
        end
    end
    gput!(tm, "RB", rb)
    gput!(tm, "FIL2", fil2)
    gput!(tm, "MY_ARRAY", my_array)
    gput!(tm, "COEF_CPT", coef_cpt)
    # L80-86: without OBLONG and outside a stepped run (L81: `$IF SET TIMESTEP $GOTO DONE`), the
    # trapezoidal-period capacity value
    if !oblong && !stepped(tm)
        rtp_capvl = gvalues(tm, "RTP_CAPVL", 3)
        filter!(kv -> !(kv[1][2] in Set(t_list) && haskey(iled_vals, kv[1])), pastsum)     # L83 (T in MILESTONYR)
        miyr_vl = gscalar(tm, "MIYR_VL")
        for (r, c) in g_rcur.keys
            for t in t_list
                gassign!(fil2, (t,), gv(r_df, (r, t)))
            end
            for ((rr, t, p), ps) in pastsum
                (rr == r && haskey(tpos, t)) || continue
                f2 = gv(fil2, (t,))
                x = (gpow(f2, gv(rb, (r, t)) - gv(B, (t,))) - one) /
                    (one - gpow(f2, gmin(GNum(miyr_vl + 1), GNum(ps)) - gv(B, (t,))))
                gassign!(rtp_capvl, (r, t, p), x)
            end
        end
        gput!(tm, "RTP_CAPVL", rtp_capvl)
        gput!(tm, "FIL2", fil2)
    end
    # L160: OPTION CLEAR=PASTSUM, CLEAR=YK1
    gput!(tm, "PASTSUM", Dict{NTuple{3,String},Float64}())
    gput!(tm, "YK1", Set{NTuple{2,String}}())
    return tm
end
