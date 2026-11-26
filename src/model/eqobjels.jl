# Elastic demand in the model (%TIMESED% YES; M1.3 change 69): the cost of the demand changes
# (EQ_OBJELS), the CES demand aggregation rows (EQL_COMCES), and the step bounds with their data
# statements (bnd_elas.mod).
#
# GAMS: eqobjels.mod L12-49 (eqobj.mod L49), mod_equa.mod L30, L80; bnd_elas.mod L10-35 (bndmain.mod
# L21), v4.9.7. Macro expansions: %EQ% -> EQ, %VAR%/%VART% -> VAR, %SOW%/%SWS%/%SWT% -> ''
# (setglobs.gms L348); %R_T% -> R,T; COM_FR%MX% -> COM_FR (%MX% is empty outside stochastic runs).
# Not translated: TIMES-Micro's nonlinear terms (L10, L33-41, %MICRO% YES; refused by
# `ppmain_tsattr_unported`).

"The values of BDSIG (setglobs.gms L248: LO 1, UP -1; FX 0)."
bdsig(b::AbstractString) = b == "LO" ? 1.0 : b == "UP" ? -1.0 : 0.0

"""
    bnd_elas_data!(tm) -> tm

The data statements of bnd_elas.mod, which the elastic demand rows read at the SOLVE: for each
demand aggregate under its CES form, the components' shares (RD_SHAR), their own-price
elasticities (MI_DOPE), lower step limits (COM_VOC) and integral prices (MI_RHO, MI_AGC); the
periods where the components have no elasticity drop them (FIL, COM_ELAST, RCS_COMPRD); the
CES components take the flat shape (COM_ELASTX 1, RTC_SHED cleared).

GAMS: bnd_elas.mod L10-17, L26-35, v4.9.7 (the bound of L19-24 is `bnd_elas!`).
"""
function bnd_elas_data!(tm)
    d = tm.data
    tl = [k[1] for k in gset(tm, "MILESTONYR").keys]
    miyr1 = Set(k[1] for k in gset(tm, "MIYR_1").keys)
    bdset = Set(k[1] for k in gset(tm, "BD").keys)
    bdneq = [k[1] for k in gset(tm, "BDNEQ").keys]
    mi = gams_sort!(collect(gset_opt(d, "MI_DMAS", 3).keys), d)
    rdagg = gset_opt(d, "RD_AGG", 2).members
    rtc = gset(tm, "RTC").members
    shar, agg = gvalues(tm, "RD_SHAR", 4), gvalues(tm, "COM_AGG", 4)
    cel, voc = gvalues(tm, "COM_ELAST", 5), gvalues(tm, "COM_VOC", 4)
    pref, esub = gparam_opt(d, "DDF_PREF", 3), gparam_opt(d, "MI_ESUB", 3)
    # L10: OPTION CLEAR=MI_DOPE
    dope = Dict{NTuple{3,String},Float64}()
    # L11-17: LOOP((ANNUAL(S),MI_DMAS(RD_AGG(R,C),COM)), ...)
    s = "ANNUAL"
    for (r, c, com) in mi
        (r, c) in rdagg || continue
        for t in tl                                                   # L12
            gassign!(shar, (r, t, com, c), gv(agg, (r, t, com, c)) * gv(pref, (r, t, c)))
        end
        for t in tl                                                   # L13
            gv(cel, (r, t, c, s, "N")).v > 0 && delete!(agg, (r, t, com, c))
        end
        foreach(k -> (k[1] == r && k[2] in miyr1 && k[3] == com && k[5] in bdset) && delete!(cel, k), collect(keys(cel)))   # L14 (BD: LO, UP, FX)
        for t in tl                                                   # L15
            ((r, t, com) in rtc && !iszero(gv(esub, (r, t, c)))) || continue
            gassign!(voc, (r, t, com, "LO"), gmin(gv(voc, (r, t, com, "LO")), GNum(1.0) - gpow(GNum(9e9), -gv(cel, (r, t, com, s, "FX")))))
        end
        for t in tl                                                   # L16
            e = gv(esub, (r, t, c))
            iszero(e) && continue
            any(b -> !iszero(gv(cel, (r, t, c, s, b))), bdneq) || (delete!(dope, (r, t, com)); continue)
            x = gv(cel, (r, t, com, s, "FX"))
            gassign!(dope, (r, t, com), gmax(GNum(abs(x.v), x.eps), e))
        end
    end
    # L26: MI_RHO(RTC(R,T,C))$MI_DOPE(RTC) = ROUND(1-1/MI_DOPE(RTC),6)
    rho = gvalues(tm, "MI_RHO", 3)
    for (k, v) in dope
        k in rtc || continue
        gassign!(rho, k, GNum(round(1 - 1 / v; digits=6)))
    end
    # L27: MI_AGC(R,T(TT+1),COM,C,J,BDNEQ(BD))$(RCJ(R,C,J,BD)$MI_DMAS(R,COM,C)$MI_ESUB(R,T,COM)) =
    #        (1-BDSIG(BD)*(ORD(J)-.5)*COM_VOC(R,T,C,BD)/COM_STEP(R,C,BD))**(-1/COM_ELAST(R,T,C,'ANNUAL','FX'))
    agc = gvalues(tm, "MI_AGC", 6)
    jord = Dict(k[1] => i for (i, k) in enumerate(gset(tm, "J").keys))
    step = gparam_opt(d, "COM_STEP", 3)
    rcj_of = Dict{NTuple{2,String},Vector{NTuple{4,String}}}()
    foreach(k -> pushat!(rcj_of, (k[1], k[2]), k), gset_opt(d, "RCJ", 4).keys)
    for (r, com, c) in mi, t in tl[2:end]
        iszero(gv(esub, (r, t, com))) && continue
        for (_, _, j, b) in get(rcj_of, (r, c), NTuple{4,String}[])
            b in bdneq || continue
            base = GNum(1.0) - GNum(bdsig(b) * (jord[j] - 0.5)) * gv(voc, (r, t, c, b)) / gv(step, (r, c, b))
            gassign!(agc, (r, t, com, c, j, b), gpow(base, GNum(-1.0) / gv(cel, (r, t, c, s, "FX"))))
        end
    end
    # L28-30: MI_AGC(R,T,COM,C,J,BD)$((COM_VOC(R,T,C,BD)>0)$MI_AGC(R,T,COM,C,J,BD)$MI_DOPE(R,T,C)) = BDSIG(BD)/(ORD(J)*VOC/STEP) *
    #           (((1-(1-BDSIG(BD)*ORD(J)*VOC/STEP)**MI_RHO(R,T,C))/MI_RHO(R,T,C))$MI_RHO(R,T,C) - LOG(1-BDSIG(BD)*ORD(J)*VOC/STEP)$(MI_RHO(R,T,C)=0))
    for k in collect(keys(agc))
        (r, t, com, c, j, b) = k
        (gv(voc, (r, t, c, b)).v > 0 && haskey(dope, (r, t, c))) || continue
        iszero(gv(agc, k)) && continue
        f = jord[j] * gv(voc, (r, t, c, b)).v / gv(step, (r, c, b)).v
        rh = gv(rho, (r, t, c)).v
        x = 1 - bdsig(b) * f
        gassign!(agc, k, GNum(bdsig(b) / f * (rh != 0 ? (1 - exp(rh * log(x))) / rh : -log(x))))
    end
    # L32-33: LOOP(RD_AGG(R,COM),FIL(T)=NOT PROD(BDNEQ,SUM(COM_TS(R,C,S)$MI_DMAS(R,COM,C),COM_ELAST(R,T,C,S,BDNEQ)));
    #           COM_ELAST(RTCS_VARC(R,T(FIL),C,S),BD)$MI_DMAS(R,COM,C)=0; RCS_COMPRD(R,T(FIL),COM,S,BD)=NO)
    fil = gmembers(tm, "FIL", 1)
    comprd = gmembers(tm, "RCS_COMPRD", 5)
    comts = indexby(gset(tm, "COM_TS"), (1, 2))
    varc = indexby(gset(tm, "RTCS_VARC"), (1, 2, 3))
    bd = [k[1] for k in gset(tm, "BD").keys]
    mi_of = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> pushat!(mi_of, (k[1], k[2]), k[3]), mi)
    for (r, com) in gams_sort!(collect(rdagg), d)
        filter!(k -> !(k[1] in tl), fil)
        for t in tl
            p = GNum(1.0)
            for b in bdneq
                x = GZERO
                for c in get(mi_of, (r, com), String[]), (_, _, ss) in get(comts, (r, c), NTuple{3,String}[])
                    x += gv(cel, (r, t, c, ss, b))
                end
                p *= x
            end
            iszero(p) && push!(fil, (t,))
        end
        for (t,) in fil
            t in tl || continue
            for c in get(mi_of, (r, com), String[]), (_, _, _, ss) in get(varc, (r, t, c), NTuple{4,String}[]), b in bd
                delete!(cel, (r, t, c, ss, b))
            end
            filter!(k -> !(k[1] == r && k[2] == t && k[3] == com), comprd)
        end
    end
    # L34: COM_ELASTX(R,T,C,BDNEQ)$MI_DOPE(R,T,C)=1; L35: RTC_SHED(R,T,C,BD,JJ)$MI_DOPE(R,T,C)=NO
    elx = gvalues(tm, "COM_ELASTX", 4)
    foreach(k -> foreach(b -> gassign!(elx, (k..., b), 1.0), bdneq), keys(dope))
    shed = gmembers(tm, "RTC_SHED", 5)
    filter!(k -> !haskey(dope, (k[1], k[2], k[3])), shed)
    gput!(tm, "MI_DOPE", dope); gput!(tm, "RD_SHAR", shar); gput!(tm, "COM_AGG", agg); gput!(tm, "COM_ELAST", cel)
    gput!(tm, "COM_VOC", voc); gput!(tm, "MI_RHO", rho); gput!(tm, "MI_AGC", agc); gput!(tm, "FIL", fil)
    gput!(tm, "RCS_COMPRD", comprd); gput!(tm, "COM_ELASTX", elx); gput!(tm, "RTC_SHED", shed)
    return tm
end

"""
    bnd_elas!(bt, tm)

The upper bounds of the demand steps (VAR_ELAST): a step's share of the larger of the reference
demand in the timeslice and COM_BQTY, times COM_VOC; INF for a CES component (MI_DOPE).

    VAR_ELAST.UP(RTCS_VARC(R,T,C,S),J,BDNEQ(BD))\$RCJ(R,C,J,BD) = INF\$MI_DOPE(R,T,C) +
      (MAX(DDF_QREF(R,T,C) * COM_FR(R,T,C,S), COM_BQTY(R,C,S)) * COM_VOC(R,T,C,BD)) / COM_STEP(R,C,BD);

The SOW tags (sow_tags.jl): under STAGES the statement runs inside
`LOOP(SW_T(T%SOW%),` (bnd_elas.mod L21) on `%VAR%_ELAST.UP(.. %SOW%)` (L23):
the SOWs of period T (`setbound!` with `sw = t`). COM_FR%MX% (L24) is change
71.

GAMS: bndmain.mod L19, bnd_elas.mod L19-24, v4.9.7.
"""
function bnd_elas!(bt, tm::TimesModel)
    d = tm.data
    bdneq = Set(k[1] for k in gset(tm, "BDNEQ").keys)
    dope, qref = gparam_opt(d, "MI_DOPE", 3), gparam_opt(d, "DDF_QREF", 3)
    cfr, bqty = gparam(tm, "COM_FR"), gparam_opt(d, "COM_BQTY", 3)
    voc, step = gparam_opt(d, "COM_VOC", 4), gparam_opt(d, "COM_STEP", 3)
    rcj_of = indexby(gset_opt(d, "RCJ", 4), (1, 2))
    for (r, t, c, s) in gset(tm, "RTCS_VARC").keys, (_, _, j, b) in get(rcj_of, (r, c), NTuple{4,String}[])
        b in bdneq || continue
        v = gmax(gv(qref, (r, t, c)) * gv(cfr, (r, t, c, s)), gv(bqty, (r, c, s))) * gv(voc, (r, t, c, b)) / gv(step, (r, c, b))
        setbound!(bt, tm, "VAR_ELAST", (r, t, c, s, j, b), :up, haskey(dope.values, (r, t, c)) ? GNum(Inf) + v : v; sw=t)
    end
    return bt
end

"""
    eq_objels!(tm) -> Int

    EQ_OBJELS(R,BD,CUR)\$(RDCUR(R,CUR)\$SUM_OBJ(R,'OBJELS')) ..
      SUM(RTCS_VARC(R,T,C,S)\$(COM_ELAST(R,T,C,S,BD)\$COM_STEP(R,C,BD)),
        COEF_PVT(R,T) * COM_BPRICE(R,T,C,S,CUR) *
        (SUM(RCJ(R,C,J,BD), VAR_ELAST(R,T,C,S,J,BD) *
           (1-BDSIG(BD)*(ORD(J)-.5)*COM_VOC(R,T,C,BD)/COM_STEP(R,C,BD))**(1/COM_ELAST(R,T,C,S,BD)))\$(NOT COM_ELASTX(R,T,C,BD)) +
         SUM(RTC_SHED(R,T,C,BD,JJ(AGE)),
           SUM((RCJ(R,C,J,BD),SPAN(AGE+CEIL((ORD(J)-.5)*COM_VOC(R,T,C,BD)/COM_STEP(R,C,BD)*100-ORD(AGE)))),
             (SHAPED(BD,JJ,SPAN) * ((1-BDSIG(BD)*(ORD(J)-.5)*COM_VOC(R,T,C,BD)/COM_STEP(R,C,BD))/SHAPED(BD,'1',SPAN))
               **(1/MAX(1E-3,SHAPE(JJ,SPAN))))**(1/COM_ELAST(R,T,C,S,BD)) * VAR_ELAST(R,T,C,S,J,BD))) +
         SUM(MI_DMAS(R,COM,C)\$MI_DOPE(R,T,C),SUM(RCJ(R,C,J,BD),VAR_ELAST(R,T,C,S,J,BD) * MI_AGC(R,T,COM,C,J,BD)))
        ))\$BDNEQ(BD)
      =E= VAR_OBJELS(R,BD,CUR);

`JJ(AGE)` gives AGE the label of the shape index JJ, so SPAN is the age at position
CEIL((ORD(J)-.5)*COM_VOC/COM_STEP*100), none beyond the last age (initsys.mod L80: 200).

The SOW tags (sow_tags.jl): the row is `%EQ%_OBJELS(R,BD,CUR %SOW%)` (L12),
one per SOW; the steps are `%VART%_ELAST(R,T,C,S,J,BD %SWS%)` (L20, L27, L28;
`at = t`) and the right-hand side `%VAR%_OBJELS(R,BD,CUR %SOW%)` (L44).

GAMS: eqobjels.mod L12-49, v4.9.7 (L33-41, %MICRO% YES, refused).
"""
function eq_objels!(tm::TimesModel)
    d = tm.data
    so = sum_obj(tm)
    regs = Set(r for ((r, i), _) in so if i == "OBJELS")
    isempty(regs) && return 0
    bdneq = Set(k[1] for k in gset(tm, "BDNEQ").keys)
    bd = [k[1] for k in gset(tm, "BD").keys]
    cel, step, voc = gparam(tm, "COM_ELAST"), gparam(tm, "COM_STEP"), gparam(tm, "COM_VOC")
    pvt, bprice = gparam(tm, "COEF_PVT"), gparam(tm, "COM_BPRICE")
    elx, shaped, shape = gparam_opt(d, "COM_ELASTX", 4), gparam_opt(d, "SHAPED", 3), gparam_opt(d, "SHAPE", 2)
    dope, agc = gparam_opt(d, "MI_DOPE", 3), gparam_opt(d, "MI_AGC", 6)
    jord = Dict(k[1] => i for (i, k) in enumerate(gset(tm, "J").keys))
    ages = [k[1] for k in gset(tm, "AGE").keys]
    rcj_of = indexby(gset_opt(d, "RCJ", 4), (1, 2, 4))                    # (r,c,bd) -> RCJ(r,c,j,bd)
    shed_of = indexby(gset_opt(d, "RTC_SHED", 5), (1, 2, 3, 4))           # (r,t,c,bd) -> RTC_SHED(r,t,c,bd,jj)
    dmas_of = indexby(gset_opt(d, "MI_DMAS", 3), (1, 3))                  # (r,c) -> MI_DMAS(r,com,c)
    varc_of = indexby(gset(tm, "RTCS_VARC"), (1,))
    n = 0
    for (r, cur) in gset(tm, "RDCUR").keys
        r in regs || continue
        for b in bd
            for sow in sow_rows(tm)   # %SOW% (eqobjels.mod L12)
                set_sow!(tm, sow)
                lhs = JuMP.AffExpr(0.0)
                if b in bdneq
                    for (_, t, c, s) in get(varc_of, (r,), NTuple{4,String}[])
                        e = gv(cel, (r, t, c, s, b))
                        (iszero(e) || iszero(gv(step, (r, c, b)))) && continue
                        k0 = gv(pvt, (r, t)) * gv(bprice, (r, t, c, s, cur))
                        rcj = get(rcj_of, (r, c, b), NTuple{4,String}[])
                        x(j) = GNum(1.0) - GNum(bdsig(b) * (jord[j] - 0.5)) * gv(voc, (r, t, c, b)) / gv(step, (r, c, b))
                        if iszero(gv(elx, (r, t, c, b)))
                            for (_, _, j, _) in rcj
                                addterm!(lhs, k0 * gpow(x(j), GNum(1.0) / e), tm, "VAR_ELAST", r, t, c, s, j, b; at=t)
                            end
                        end
                        for (_, _, _, _, jj) in get(shed_of, (r, t, c, b), NTuple{5,String}[])
                            jj in ages || continue                                           # JJ(AGE)
                            for (_, _, j, _) in rcj
                                pos = ceil(Int, (jord[j] - 0.5) * gv(voc, (r, t, c, b)).v / gv(step, (r, c, b)).v * 100)
                                1 <= pos <= length(ages) || continue
                                sp = ages[pos]
                                f = gpow(gv(shaped, (b, jj, sp)) * gpow(x(j) / gv(shaped, (b, "1", sp)), GNum(1.0) / gmax(GNum(1e-3), gv(shape, (jj, sp)))), GNum(1.0) / e)
                                addterm!(lhs, k0 * f, tm, "VAR_ELAST", r, t, c, s, j, b; at=t)
                            end
                        end
                        if haskey(dope.values, (r, t, c))
                            for (_, com, _) in get(dmas_of, (r, c), NTuple{3,String}[]), (_, _, j, _) in rcj
                                addterm!(lhs, k0 * gv(agc, (r, t, com, c, j, b)), tm, "VAR_ELAST", r, t, c, s, j, b; at=t)
                            end
                        end
                    end
                end
                rhs = JuMP.AffExpr(0.0)
                addterm!(rhs, GNum(1.0), tm, "VAR_OBJELS", r, b, cur)
                gconstraint!(tm, eqtag(tm, "EQ_OBJELS"), sowkey(tm, (r, b, cur)), "E", lhs, rhs) === nothing || (n += 1)
            end
        end
    end
    return n
end

"""
    eql_comces!(tm) -> Int

    EQL_COMCES(RTC(R,T,COM),C,S)\$(RTCS_VARC(R,T,C,S)\$MI_DOPE(R,T,C)\$MI_DMAS(R,COM,C)) ..
      SUM(RCJ(R,C,J,BDNEQ(BD))\$COM_ELAST(R,T,C,S,BD),
          VAR_ELAST(R,T,C,S,J,BD)*COM_STEP(R,C,BD)/ORD(J)/(DDF_QREF(R,T,C)*COM_FR(R,T,C,S)*COM_VOC(R,T,C,BD)))
      =L= VAR_COMPRD(R,T,COM,'ANNUAL')/DDF_QREF(R,T,COM);

The SOW tags (sow_tags.jl): the row is `%EQ%L_COMCES(... %SWT%)` (L49) and the
terms `%VAR%_ELAST(... %SOW%)` and `%VAR%_COMPRD(... %SOW%)` (L50-51);
COM_FR%MX% (L50) is change 71.

GAMS: eqobjels.mod L46-49 (mod_equa.mod L80), v4.9.7.
"""
function eql_comces!(tm::TimesModel)
    d = tm.data
    dope = gparam_opt(d, "MI_DOPE", 3)
    isempty(dope.keys) && return 0
    rtc = gset(tm, "RTC").members
    bdneq = Set(k[1] for k in gset(tm, "BDNEQ").keys)
    cel, step, voc, cfr = gparam(tm, "COM_ELAST"), gparam(tm, "COM_STEP"), gparam(tm, "COM_VOC"), gparam(tm, "COM_FR")
    qref = gparam_opt(d, "DDF_QREF", 3)
    jord = Dict(k[1] => i for (i, k) in enumerate(gset(tm, "J").keys))
    rcj_of = indexby(gset_opt(d, "RCJ", 4), (1, 2))
    varc_of = indexby(gset(tm, "RTCS_VARC"), (1, 2, 3))
    n = 0
    for (r, com, c) in gset_opt(d, "MI_DMAS", 3).keys, (t,) in gset(tm, "MILESTONYR").keys
        ((r, t, com) in rtc && haskey(dope.values, (r, t, c))) || continue
        for (_, _, _, s) in get(varc_of, (r, t, c), NTuple{4,String}[])
            for sow in sw_rows(tm, t)   # %SWT% (eqobjels.mod L49)
                set_sow!(tm, sow)
                lhs = JuMP.AffExpr(0.0)
                for (_, _, j, b) in get(rcj_of, (r, c), NTuple{4,String}[])
                    (b in bdneq && !iszero(gv(cel, (r, t, c, s, b)))) || continue
                    coef = gv(step, (r, c, b)) / GNum(jord[j]) / (gv(qref, (r, t, c)) * gv(cfr, (r, t, c, s)) * gv(voc, (r, t, c, b)))
                    addterm!(lhs, coef, tm, "VAR_ELAST", r, t, c, s, j, b)
                end
                rhs = JuMP.AffExpr(0.0)
                addterm!(rhs, GNum(1.0) / gv(qref, (r, t, com)), tm, "VAR_COMPRD", r, t, com, "ANNUAL")
                gconstraint!(tm, eqtag(tm, "EQL_COMCES"), swt(tm, (r, t, com, c, s), t), "L", lhs, rhs) === nothing || (n += 1)
            end
        end
    end
    return n
end
