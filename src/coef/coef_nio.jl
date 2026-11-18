# M1.2 (2): commodity flows tied to new capacity and to decommissioning.
#
# GAMS (v4.9.7): coef_nio.mod L13-71.
#
# M1.3 change 53 translates the flows tied to investment (NCAP_ICOM, with its
# lead NCAP_CLED) and to decommissioning (NCAP_OCOM): the loops L17-33 and
# L37-56 that spread them over the periods into COEF_ICOM and COEF_OCOM, the
# filter of RPC_CAPFLO (L15), the swap of negative coefficients (L64-67) and
# the clean-up of NCAP_CLED (L71). Change 54 adds the flows tied to early
# retirements (RCAP_OCAP: L35, L58) and the lag of the flows over the
# lifetime (NCAP_CLAG from NCAP_CLED, L70), which coef_shp.mod L39-42 turns
# into COEF_CIO.

"The coef_nio.mod paths this model would take that are not translated; empty when coef_nio! can run."
coef_nio_unported(tm) = String[]

"""
    coef_nio!(tm) -> tm

coef_nio.mod on the GAMS state in `tm`:

    RPC_CAPFLO(R,V,P,C)\$(NOT RTP(R,V,P)) = 0;                                        (L15)
    FIL(V) = YEARVAL(V) GE MIYR_V1;                                                   (L16)
    LOOP(RPC_CAPFLO(R,FIL(V),P,C)\$NCAP_ICOM(R,V,P,C), DFUNC = COEF_RPTI(R,V,P);       (L18-33)
      MY_F = NCAP_ILED(R,V,P); F = COEF_ILED(R,V,P); CNT = ABS(NCAP_CLED(R,V,P,C));
      Z = B(V)+MAX(1\$(CNT\$MY_F=0),MY_F); F = Z-MAX(1,MIN(CNT,F));
      IF(DFUNC > 1, COEF_ICOM(R,T(V),T,P,C) = (DFUNC * NCAP_ICOM(R,V,P,C) / FPD(T))
      ELSE LOOP(T\$((E(T) >= F) * (B(T) < Z)),
        COEF_ICOM(R,V,T,P,C) = MAX(0,((MIN(Z-1,E(T))-MAX(F,B(T)) + 1) / FPD(T))) * NCAP_ICOM(R,V,P,C) / (Z-F))));
    FIL2(T) = E(T)+(1+MAX(1,D(T+1))-B(T)-E(T))/2;                                     (L36)
    LOOP(RPC_CAPFLO(R,V,P,C)\$NCAP_OCOM(R,V,P,C),                                      (L37-56)
      F = NCAP_ILED(R,V,P)+NCAP_DLAG(R,V,P); MY_F = NCAP_TLIFE(R,V,P); DFUNC = COEF_RPTI(R,V,P);
      Z = B(V)+F+DFUNC*MY_F;
      Z = MAX(1,NCAP_DLIFE(R,V,P),SUM(VNT(V,T)\$((Z>=B(T))*(E(T)+1>Z)),(E(T)-Z+1)/(1-(Z-(B(T)+E(T))/2)/FIL2(T))));
      IF(DFUNC > 1, FOR(CNT = 1 TO CEIL(DFUNC), COEF_OCOM(R,VNT(V,T),P,C) = COEF_OCOM(R,V,T,P,C) +
          MIN(1,DFUNC-CNT+1) * MAX(0,(MIN(B(V)+F+(CNT*MY_F)+Z,E(T)+1) - MAX(B(V)+F+(CNT*MY_F),B(T)))/FPD(T)) * (NCAP_OCOM(R,V,P,C)/Z))
      ELSE MY_F = B(V)+F+MY_F;
        COEF_OCOM(R,V,T,P,C)\$(E(T)+1 > MY_F) = MAX(0,(MIN(MY_F+Z,E(T)+1) - MAX(MY_F,B(T)))/FPD(T)) * (NCAP_OCOM(R,V,P,C)/Z)));
    OPTION CLEAR=CNT;                                                                 (L59)
    NCAP_OCOM(RTP,C)\$((NOT NCAP_OCOM(RTP,C))\$RCAP_OCAP(RTP,C)) = 1;                  (L35, before L37)
    COEF_RCOM(RTP_CPTYR(R,V,T,P),C)\$RCAP_OCAP(R,V,P,C) = COEF_CPT(R,V,T,P) * NCAP_OCOM(R,V,P,C) / FPD(T);   (L58)
    [L64-67: a negative COEF_ICOM moves to COEF_OCOM and a negative COEF_OCOM to COEF_ICOM]
    NCAP_CLAG(RTP,C,IO)\$((NOT NCAP_ICOM(RTP,C))\$NCAP_COM(RTP,C,IO)) \$= NCAP_CLED(RTP,C);  (L70)
    NCAP_CLED(R,V,P,C)\$(NOT NCAP_ICOM(R,V,P,C)) = 0;                                  (L71)

The loops run in GAMS order over RPC_CAPFLO. `1\$(CNT\$MY_F=0)`: `\$` binds before `=` (G13), so the
lead of the flow is 1 year unless there is a construction lead NCAP_ILED and an NCAP_CLED. The
scratch scalars DFUNC, MY_F, F and Z are left as later files set them (coef_shp.mod, coef_obj.mod).
T is MILESTONYR; T+1 the next milestone year (none after the last, whose D is then 0).

GAMS: coef_nio.mod L13-71, v4.9.7.
"""
function coef_nio!(tm)
    u = coef_nio_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    yearval = gparam(tm, "YEARVAL")
    B, E, D, FPD = gparam(tm, "B"), gparam(tm, "E"), gparam(tm, "D"), gparam(tm, "FPD")
    tl = [k[1] for k in gset(tm, "MILESTONYR").keys]
    tset = Set(tl)
    one, zero = GNum(1.0), GZERO
    # L15: RPC_CAPFLO(R,V,P,C)$(NOT RTP(R,V,P)) = 0
    rtp = gset(tm, "RTP")
    capflo = [k for k in gset(tm, "RPC_CAPFLO").keys if (k[1], k[2], k[3]) in rtp]
    gput!(tm, "RPC_CAPFLO", Set(capflo))
    # L16: FIL(V) over MODLYEAR (V's domain); members outside V are kept
    miyr_v1 = gv(gparam(tm, "MIYR_V1"), ())
    fil = Set(k for k in gmembers(tm, "FIL", 1) if !(k in gset(tm, "MODLYEAR")))
    for (v,) in gset(tm, "MODLYEAR").keys
        Float64(gv(yearval, (v,))) >= Float64(miyr_v1) && push!(fil, (v,))
    end
    gput!(tm, "FIL", fil)

    icom = gparam(tm, "NCAP_ICOM")
    rcap_ocap = gparam_opt(tm.data, "RCAP_OCAP", 4)
    # L35: NCAP_OCOM(RTP,C)$((NOT NCAP_OCOM(RTP,C))$RCAP_OCAP(RTP,C)) = 1   (no statement between it and L18
    # reads NCAP_OCOM, so it is applied here)
    if !isempty(rcap_ocap.values)
        ocomv = gvalues(tm, "NCAP_OCOM", 4)
        for k in rcap_ocap.keys
            ((k[1], k[2], k[3]) in rtp && !haskey(ocomv, k)) && gassign!(ocomv, k, GNum(1.0))
        end
        gput!(tm, "NCAP_OCOM", ocomv)
    end
    ocom = gparam(tm, "NCAP_OCOM")
    coef_icom, coef_ocom = gvalues(tm, "COEF_ICOM", 5), gvalues(tm, "COEF_OCOM", 5)
    rpti, iled, ciled = gparam(tm, "COEF_RPTI"), gparam(tm, "NCAP_ILED"), gparam(tm, "COEF_ILED")
    cled = gvalues(tm, "NCAP_CLED", 4)
    b(y) = gv(B, (y,)); e(y) = gv(E, (y,)); fpd(y) = gv(FPD, (y,))

    # L18-33: flows tied to investment
    if !isempty(icom.values)
        for (r, v, p, c) in capflo
            ((v,) in fil && haskey(icom.values, (r, v, p, c))) || continue
            dfunc = gv(rpti, (r, v, p))
            my_f = gv(iled, (r, v, p)); f = gv(ciled, (r, v, p)); cl = gv(cled, (r, v, p, c)); cnt = GNum(abs(cl.v), cl.eps)
            z = b(v) + gmax(gif(one, (iszero(my_f) ? zero : cnt).v == 0), my_f)
            f = z - gmax(one, gmin(cnt, f))
            ic = gv(icom, (r, v, p, c))
            if dfunc.v > 1
                v in tset && gassign!(coef_icom, (r, v, v, p, c), dfunc * ic / fpd(v))
            else
                for t in tl
                    (e(t).v >= f.v && b(t).v < z.v) || continue
                    x = gmax(zero, (gmin(z - one, e(t)) - gmax(f, b(t)) + one) / fpd(t)) * ic / (z - f)
                    gassign!(coef_icom, (r, v, t, p, c), x)
                end
            end
        end
    end
    # L36: FIL2
    fil2 = gvalues(tm, "FIL2", 1)
    for (i, ti) in enumerate(tl)
        dnext = i < length(tl) ? gv(D, (tl[i+1],)) : GZERO
        gassign!(fil2, (ti,), e(ti) + (1 + gmax(GNum(1), dnext) - b(ti) - e(ti)) / 2)
    end
    gput!(tm, "FIL2", fil2)
    # L37-56: flows tied to decommissioning
    if !isempty(ocom.values)
        dlag, tlife, dlife = gparam(tm, "NCAP_DLAG"), gparam(tm, "NCAP_TLIFE"), gparam(tm, "NCAP_DLIFE")
        vnt_of = indexby(gset(tm, "VNT"), (1,))                       # v -> VNT(v,t)
        for (r, v, p, c) in capflo
            haskey(ocom.values, (r, v, p, c)) || continue
            f = gv(iled, (r, v, p)) + gv(dlag, (r, v, p)); my_f = gv(tlife, (r, v, p)); dfunc = gv(rpti, (r, v, p))
            z = b(v) + f + dfunc * my_f
            s = GZERO
            for (_, t) in get(vnt_of, (v,), NTuple{2,String}[])
                (z.v >= b(t).v && (e(t) + 1).v > z.v) || continue
                s = s + (e(t) - z + one) / (one - (z - (b(t) + e(t)) / 2) / gv(fil2, (t,)))
            end
            z = gmax(gmax(one, gv(dlife, (r, v, p))), s)
            oc = gv(ocom, (r, v, p, c))
            if dfunc.v > 1
                for k in 1:ceil(Int, dfunc.v)
                    cntk = GNum(k)
                    for (_, t) in get(vnt_of, (v,), NTuple{2,String}[])
                        st = b(v) + f + cntk * my_f
                        x = gv(coef_ocom, (r, v, t, p, c)) + gmin(one, dfunc - cntk + one) *
                            gmax(zero, (gmin(st + z, e(t) + one) - gmax(st, b(t))) / fpd(t)) * (oc / z)
                        gassign!(coef_ocom, (r, v, t, p, c), x)
                    end
                end
            else
                my_f = b(v) + f + my_f
                for t in tl
                    (e(t) + one).v > my_f.v || continue
                    x = gmax(zero, (gmin(my_f + z, e(t) + one) - gmax(my_f, b(t))) / fpd(t)) * (oc / z)
                    gassign!(coef_ocom, (r, v, t, p, c), x)
                end
            end
        end
    end
    # L58: COEF_RCOM(RTP_CPTYR(R,V,T,P),C)$RCAP_OCAP(R,V,P,C) = COEF_CPT(R,V,T,P)*NCAP_OCOM(R,V,P,C)/FPD(T)
    if !isempty(rcap_ocap.values)
        coef_rcom = gvalues(tm, "COEF_RCOM", 5)
        coef_cpt = gparam(tm, "COEF_CPT")
        cptyr_of = indexby(gset(tm, "RTP_CPTYR"), (1, 2, 4))         # (r,v,p) -> RTP_CPTYR(r,v,t,p)
        for (r, v, p, c) in rcap_ocap.keys
            for (_, _, t, _) in get(cptyr_of, (r, v, p), NTuple{4,String}[])
                gassign!(coef_rcom, (r, v, t, p, c), gv(coef_cpt, (r, v, t, p)) * gv(ocom, (r, v, p, c)) / fpd(t))
            end
        end
        gput!(tm, "COEF_RCOM", coef_rcom)
    end
    # L59: OPTION CLEAR=CNT
    gput!(tm, "CNT", Dict{Tuple{},Float64}())
    # L64-67: a negative COEF_ICOM becomes a COEF_OCOM, and a negative COEF_OCOM a COEF_ICOM
    for (k, x) in collect(coef_icom)                                 # L64-65
        x < 0 || continue
        gassign!(coef_ocom, k, gv(coef_ocom, k) - GNum(x))
        delete!(coef_icom, k)
    end
    for (k, x) in collect(coef_ocom)                                 # L66-67
        x < 0 || continue
        gassign!(coef_icom, k, gv(coef_icom, k) - GNum(x))
        delete!(coef_ocom, k)
    end
    gput!(tm, "COEF_ICOM", coef_icom)
    gput!(tm, "COEF_OCOM", coef_ocom)
    # L70: NCAP_CLAG(RTP,C,IO)$((NOT NCAP_ICOM(RTP,C))$NCAP_COM(RTP,C,IO)) $= NCAP_CLED(RTP,C)
    ncom = gparam_opt(tm.data, "NCAP_COM", 5)
    if !isempty(ncom.values) && !isempty(cled)
        clag = gvalues(tm, "NCAP_CLAG", 5)
        for (r, v, p, c, io) in ncom.keys
            ((r, v, p) in rtp && !haskey(icom.values, (r, v, p, c)) && haskey(cled, (r, v, p, c))) || continue
            gassign!(clag, (r, v, p, c, io), gv(cled, (r, v, p, c)))
        end
        gput!(tm, "NCAP_CLAG", clag)
    end
    # L71: NCAP_CLED(R,V,P,C)$(NOT NCAP_ICOM(R,V,P,C)) = 0
    if Reference.has_symbol(tm.data.dump, "NCAP_CLED")
        filter!(((k, _),) -> haskey(icom.values, k), cled)
        gput!(tm, "NCAP_CLED", cled)
    end
    return tm
end
