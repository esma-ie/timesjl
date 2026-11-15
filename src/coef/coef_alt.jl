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
# solve.stp L124 calls the file again inside each step (`coef_alt.lin STP`,
# only under a non-empty %CTST%): L27 clears PERDINV, TPULSE and TPULSEYR,
# L31-58 run again on the step's Y_EOH, L63 jumps to the STP label (L134-158),
# which changes the divisors under LINFLO only (L136), and L160 clears PASTSUM
# and YK1. `coef_alt!(tm; stp=true)` is that call; its LINFLO block (L137-157)
# is `coef_alt_stp!` (M1.5 change 6, docs/m15-plan.md).
# ALTOBJ is read from the state (initmty.mod L420-432, changed by ppmain.mod
# L146).

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

"""
    eq_periods(tm) -> GamsSet{1}

The periods the equations and bounds written with `%R_T%`, `%TX%` or
`%R_V_T%` are generated for:

    \$ SET R_T 'R,T' SET TX 'T' SET R_V_T 'R,V,T' SET RTPX ''
    \$ IF SET STEPPED \$SET R_T 'R,SUBT(T)' SET TX 'SUBT(T)' SET R_V_T 'R,V,SUBT(T)'

T (MILESTONYR) in an ordinary run; in a stepped run SUBT, the periods of the
step being solved (every period until solve.stp starts, ppmain.mod L253).
Only the control period of the equation takes it: a sum inside the equation
that runs over T keeps MILESTONYR. The REG_FIXT form of L41 (RT_PP, RVT) is
refused with FIXBOH.

GAMS: maindrv.mod L38-41; ppmain.mod L253, v4.9.7.
"""
eq_periods(tm) = gset(tm, stepped(tm) ? "SUBT" : "MILESTONYR")

"GAMS `LOG(x)`: a non-positive argument is an execution error."
function glog(x::GNum)
    x.v > 0 || throw(DomainError(x, "LOG of a non-positive value (GAMS: FUNC DOMAIN)"))
    return GNum(log(x.v))
end

"""
    coef_alt_stp!(tm) -> tm

The divisors of a step of a stepped (myopic) run under LINFLO (OBJ ALT
without OBLONG, or OBJ LIN), the STP label of coef_alt.lin:

    OPTION CLEAR=RTP_CAPVL;
    LOOP(T\$(E(T) EQ MIYR_VL),
     PASTSUM(RTP(R,TT,P))\$((COEF_CPT(R,TT,T,P) GT 0)\$PRC_CAP(R,P)) = B(TT)+NCAP_ILED(R,TT,P)+COEF_RPTI(R,TT,P)*NCAP_TLIFE(R,TT,P);
     LOOP(G_RCUR(R,CUR), F = RB(R,T);
      MY_F = R_DF(R,T); Z = 1-MY_F**(MIYR_VL-F+1);
      RTP_CAPVL(R,TT(V),P)\$PASTSUM(R,V,P) = COEF_PVT(R,T) *
        ((MIN(Z, 1-MY_F**(PASTSUM(R,V,P)-F)) - (1-MY_F**MAX(0,B(V)+NCAP_ILED(R,V,P)-F))%ILED%) / Z - COEF_CPT(R,V,T,P))));
    RTP_CAPVL(R,TT,P)\$RTP_CAPVL(R,TT,P) = RTP_CAPVL(R,TT,P)/SUM(VNT(TT,Y_EOH(T)),COEF_PVT(R,T)*MAX(0,COEF_CPT(R,TT,T,P)));
    OPTION CLEAR=PASTSUM;
    \$IFI '%OBLONG%'==YES \$GOTO UPDATE
    LOOP(G_RCUR(R,CUR),
      FIL2(T) = R_DF(R,T);
      PASTSUM(RTP(R,Y_EOH(T),P))\$((NOT NCAP_ILED(R,T,P))\$PRC_CAP(R,P)) = (FIL2(T)**(RB(R,T)-B(T))-1) / (1-FIL2(T)**MIN(MIYR_VL+1-B(T),COEF_RPTI(R,T,P)*NCAP_TLIFE(R,T,P))));
    RTP_CAPVL(R,T,P)\$PASTSUM(R,T,P) = (1+RTP_CAPVL(R,T,P)) / (1+PASTSUM(R,T,P)) - 1;
    \$LABEL UPDATE
    OBJ_DIVI(RTP(R,T,P)) = STP_DIV('1',R,T,P)*(1+RTP_CAPVL(R,T,P));
    OBJ_DIVIV(RTP(R,T,P)) = STP_DIV('2',R,T,P)*(1+RTP_CAPVL(R,T,P));
    OBJ_DIVIII(RTP(R,T,P)) = STP_DIV('3',R,T,P)*(1+RTP_CAPVL(R,T,P));

The period T of the first loop is the last of the step (MIYR_VL is the end
of the step's horizon, solve.stp L117). RTP_CAPVL is, for a capacity of a
milestone vintage that is available in that period, the change of its
discounted availability because the last period ends at MIYR_VL, relative
to its availability over the step's horizon (L140-146); without OBLONG it
is combined with the correction for trapezoidal periods (L150-153), which
the call of coefmain.mod leaves out in a stepped run (L81). The divisors of
the investment, fixed and decommissioning costs are the ones saved before
the loop (STP_DIV, solve.stp L104-107: ALTOBJ > 1, which LINFLO implies,
initmty.mod L420-432) times 1+RTP_CAPVL. `%ILED%` is `\$NCAP_ILED(R,V,P)`
(L28), or empty with OBLONG (L44).

As GAMS runs it: PASTSUM is not cleared before L141, so it starts from the
state; V is MODLYEAR without the step's FORWARD periods (solve.stp L115);
FIL2 keeps the values of the last region in G_RCUR; a T in MILESTONYR with
no record in STP_DIV loses its divisor (the product is zero). RB, R_DF and
COEF_CPT are the ones of the coefmain.mod call; COEF_PVT is the step's (L47).

GAMS: coef_alt.lin L137-157 (solve.stp L124), v4.9.7.
"""
function coef_alt_stp!(tm)
    S1(n) = gset(tm, n)
    t_list = [k[1] for k in S1("MILESTONYR").keys]                     # T (and TT) in order
    tset = Set(t_list)
    y_eoh = Set(k[1] for k in S1("Y_EOH").keys)
    V = Set(k[1] for k in S1("MODLYEAR").keys)
    B, E = gparam(tm, "B"), gparam(tm, "E")
    one = GNum(1)
    miyr_vl = gscalar(tm, "MIYR_VL")
    rtp, prc_cap, g_rcur, vnt = S1("RTP"), S1("PRC_CAP"), S1("G_RCUR"), S1("VNT")
    iled, rpti, tlife = gparam(tm, "NCAP_ILED"), gparam(tm, "COEF_RPTI"), gparam(tm, "NCAP_TLIFE")
    coef_cpt, coef_pvt = gparam(tm, "COEF_CPT"), gparam(tm, "COEF_PVT")
    rb, r_df = gparam(tm, "RB"), gparam(tm, "R_DF")
    oblong = uppercase(gswitch(tm, "OBLONG", "")) == "YES"            # L44 (LINFLO is 1 here): %ILED% empty; L148
    rtp_t = [k for k in rtp.keys if k[2] in tset]                     # RTP(R,T,P), T in MILESTONYR
    # L139: OPTION CLEAR=RTP_CAPVL
    rtp_capvl = Dict{NTuple{3,String},Float64}()
    pastsum = gvalues(tm, "PASTSUM", 3)
    # L140: LOOP(T$(E(T) EQ MIYR_VL),
    for t in t_list
        Float64(gv(E, (t,))) == miyr_vl || continue
        # L141
        for (r, tt, p) in rtp_t
            ((r, p) in prc_cap && gv(coef_cpt, (r, tt, t, p)).v > 0) || continue
            gassign!(pastsum, (r, tt, p), gv(B, (tt,)) + gv(iled, (r, tt, p)) + gv(rpti, (r, tt, p)) * gv(tlife, (r, tt, p)))
        end
        # L142-145
        for (r, _) in g_rcur.keys
            f, my_f = gv(rb, (r, t)), gv(r_df, (r, t))
            z = one - gpow(my_f, GNum(miyr_vl) - f + one)
            gput_scalar!(tm, "F", f); gput_scalar!(tm, "MY_F", my_f); gput_scalar!(tm, "Z", z)   # scratch, as the last pass leaves it
            for (r2, v, p) in collect(keys(pastsum))
                (r2 == r && v in tset && v in V) || continue
                il = gv(iled, (r, v, p))
                term = one - gpow(my_f, gmax(GZERO, gv(B, (v,)) + il - f))
                x = gv(coef_pvt, (r, t)) *
                    ((gmin(z, one - gpow(my_f, gv(pastsum, (r, v, p)) - f)) - (oblong ? term : gif(term, !iszero(il)))) / z -
                     gv(coef_cpt, (r, v, t, p)))
                gassign!(rtp_capvl, (r, v, p), x)
            end
        end
    end
    # L146
    for (r, tt, p) in collect(keys(rtp_capvl))
        tt in tset || continue
        den = GZERO
        for t in t_list
            (t in y_eoh && (tt, t) in vnt) || continue
            den += gv(coef_pvt, (r, t)) * gmax(GZERO, gv(coef_cpt, (r, tt, t, p)))
        end
        gassign!(rtp_capvl, (r, tt, p), gv(rtp_capvl, (r, tt, p)) / den)
    end
    # L147: OPTION CLEAR=PASTSUM
    empty!(pastsum)
    # L148: $IFI '%OBLONG%'==YES $GOTO UPDATE
    if !oblong
        # L150-152
        fil2 = gvalues(tm, "FIL2", 1)
        for (r, _) in g_rcur.keys
            for t in t_list
                gassign!(fil2, (t,), gv(r_df, (r, t)))
            end
            for (r2, t, p) in rtp_t
                (r2 == r && t in y_eoh && iszero(gv(iled, (r, t, p))) && (r, p) in prc_cap) || continue
                f2, b = gv(fil2, (t,)), gv(B, (t,))
                x = (gpow(f2, gv(rb, (r, t)) - b) - one) /
                    (one - gpow(f2, gmin(GNum(miyr_vl) + one - b, gv(rpti, (r, t, p)) * gv(tlife, (r, t, p)))))
                gassign!(pastsum, (r, t, p), x)
            end
        end
        gput!(tm, "FIL2", fil2)
        # L153
        for (r, t, p) in collect(keys(pastsum))
            t in tset || continue
            gassign!(rtp_capvl, (r, t, p), (one + gv(rtp_capvl, (r, t, p))) / (one + gv(pastsum, (r, t, p))) - one)
        end
    end
    gput!(tm, "RTP_CAPVL", rtp_capvl)
    gput!(tm, "PASTSUM", pastsum)
    # L155-157 (UPDATE)
    stp_div = gvalues(tm, "STP_DIV", 4)
    for (j, name) in (("1", "OBJ_DIVI"), ("2", "OBJ_DIVIV"), ("3", "OBJ_DIVIII"))
        d = gvalues(tm, name, 3)
        for (r, t, p) in rtp_t
            gassign!(d, (r, t, p), gv(stp_div, (j, r, t, p)) * (one + gv(rtp_capvl, (r, t, p))))
        end
        gput!(tm, name, d)
    end
    return tm
end

"""
    coef_alt!(tm; stp=false) -> tm

coef_alt.lin on the GAMS state in `tm`, as coefmain.mod L26 calls it:
PERDINV, TPULSEYR, TPULSE, OBJ_LINT (and OBJ_ALTV, FPD, OBJ_PVT, COEF_PVT
when the switches ask); then, unless `%CTST%` is empty, R_DF, RB, COEF_CPT
(replacing coef_cpt.mod's, which computed none in that case) and, without
OBLONG and outside a stepped run (L80-81), RTP_CAPVL. PASTSUM and YK1 are
left cleared.

With `stp` it is the call of a step of a stepped run (solve.stp L124,
`coef_alt.lin STP`): PERDINV, TPULSE and TPULSEYR are cleared (L27) and built
again with OBJ_LINT (and OBJ_ALTV) on the step's Y_EOH (L31-58); L63 then
jumps to the STP label, which without LINFLO (L136) only clears PASTSUM and
YK1 (L160). With LINFLO the divisors' block (L137-157) runs first
([`coef_alt_stp!`](@ref)).

GAMS: coef_alt.lin L11-87, L159-161 (coefmain.mod L26); L27, L31-63, L134-160
(solve.stp L124), v4.9.7.
"""
function coef_alt!(tm; stp::Bool=false)
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
            # In a step of a stepped run, a period with no year (L51) or no pulse year (L52) in the
            # step's horizon has an empty sum: GAMS divides by zero, skips the solve of the step
            # and goes on to the next one (docs/discrepancies.md, D42). TIMES.jl stops here.
            stp && iszero(den) && throw(DomainError((r, t), "coef_alt.lin L$(lf ? 51 : 52): OBJ ALT in a stepped run, " *
                "period $t has no year in the horizon of this step; GAMS divides by zero here and skips the solve of the step"))
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

    if stp
        # solve.stp L124 includes the file only under a non-empty %CTST%; L63: $IFI %1==STP $GOTO STP
        ctst(tm) == "" && throw(ArgumentError("coef_alt.lin STP is called only under a non-empty %CTST% (solve.stp L124)"))
        # L136: $IF NOT %LINFLO%==1 $GOTO DONE
        lf && coef_alt_stp!(tm)                                                   # L137-157
        # L160: OPTION CLEAR=PASTSUM,CLEAR=YK1
        gput!(tm, "PASTSUM", Dict{NTuple{3,String},Float64}())
        gput!(tm, "YK1", Set{NTuple{2,String}}())
        return tm
    end
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
