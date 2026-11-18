# M1.3 change 56: eqdamage.mod, damage costs in their linear form, included from eqmain.mod L262 as
# `eqdamage.mod` (%1 = mod, so not the LPDAM entry of L10) whenever DAM_COST is DEFINED: the preparation
# (L11-60), EQ_DAMAGE (L67-73), EQ_OBJDAM (LPDAM, L77-94) and the bounds of VAR_DAM (BOUND, L135-142),
# then FINISH (L157-161). The compile-time statements (L11, L13-17, L62) are in every dump from the
# input on (OBV holds OBJDAM). Not translated: the climate terms (%CLI%, refused for the whole model),
# the stochastic indexes (%STAGES%) and the non-linear form (%DAMAGE% NLP: NLPDAM, BDNLP), refused here.

"Whether eqdamage.mod is included: DAM_COST has data (`\$IF DEFINED DAM_COST`, G35)."
damage_on(tm) = hasdata(tm, "DAM_COST", 4)

function damage_unported(tm)
    damage_on(tm) || return nothing
    sw = uppercase(strip(gswitch(tm, "DAMAGE", ""), ['\'', '"']))
    sw == "NLP" && throw(UnportedError("eqdamage.mod NLPDAM/BDNLP: damage costs under %DAMAGE% NLP (non-linear)"))
    return nothing
end

"""
    dam_tvoc(tm) -> Dict{NTuple{4,String},Float64}

DAM_TVOC(R,T,C,BD) as it stands at the BOUND label (L135-142), for the rows RXX(R,T,C) of RTDAM:

    DAM_TVOC(RXX(R,T,C),BD) \$= DAM_VOC(R,C,BD);                                                    (L29)
    DAM_TVOC(RXX(R,T,C),BD)\$(NOT DAM_TQTY(R,T,C)) = 0;                                             (L34)
    DAM_TVOC(RXX(R,T,C),BD)\$(NOT DAM_TVOC(R,T,C,BD)) \$= (DAM_STEP(R,C,BD)+.5)*DAM_VOC(R,C,'N')*DAM_TQTY(R,T,C);   (L43)
    DAM_TVOC(RXX(R,T,C),'LO') = MIN(DAM_TQTY(R,T,C),DAM_TVOC(R,T,C,'LO')+INF\$(NOT DAM_TVOC(R,T,C,'LO')));          (L44)
    DAM_TVOC(RXX(R,T,C),'UP')\$(NOT DAM_TVOC(R,T,C,'UP')) =
      DAM_TVOC(R,T,C,'LO')*(1+((DAM_STEP(R,C,'UP')+0.5)/(DAM_STEP(R,C,'LO')+0.5)-1)\$DAM_STEP(R,C,'LO'));             (L45-46)

FINISH (L159) clears DAM_TVOC before the pre-solve dump, but the bounds and EQ_OBJDAM (which reads
VAR_DAM.UP) need it, so it is computed again from what the dump keeps: DAM_VOC, the final DAM_TQTY
(L33 already applied), and DAM_STEP at LO and UP (L58 changes only FX, after L43).

GAMS: eqdamage.mod L29, L34, L43-46, v4.9.7.
"""
function dam_tvoc(tm)
    voc, tqty, step = gparam(tm, "DAM_VOC"), gparam(tm, "DAM_TQTY"), gparam(tm, "DAM_STEP")
    out = Dict{NTuple{4,String},Float64}()
    for (r, t, c, _) in gset(tm, "RTDAM").keys
        q = gv(tqty, (r, t, c))
        tv = Dict{String,GNum}()
        for bd in ("LO", "UP", "FX")
            x = iszero(q) ? GZERO : gv(voc, (r, c, bd))
            iszero(x) && (x = (gv(step, (r, c, bd)) + 0.5) * gv(voc, (r, c, "N")) * q)
            tv[bd] = x
        end
        lo = gmin(q, tv["LO"] + (iszero(tv["LO"]) ? GNum(Inf) : GZERO))
        up = iszero(tv["UP"]) ? lo * (1 + gif((gv(step, (r, c, "UP")) + 0.5) / (gv(step, (r, c, "LO")) + 0.5) - 1,
                                              !iszero(gv(step, (r, c, "LO"))))) : tv["UP"]
        gassign!(out, (r, t, c, "LO"), lo); gassign!(out, (r, t, c, "UP"), up)
    end
    return out
end

"""
    dam_prep!(tm) -> tm

The data statements of eqdamage.mod (eqmain.mod L262), in order:

    OPTION CLEAR=RXX;                                                                               (L19)
    \$BATINCLUDE filparam DAM_TQTY 'R,' C ",'0','0','0','0'" DATAYEAR T '' '' '' "YEAR,"            (L20)
    DAM_TQTY(R,T,C)\$(NOT DAM_TQTY(R,T,C)) \$= DAM_BQTY(R,C);                                        (L21)
    DAM_COST(R,T,C,CUR)\$((DAM_COST(R,T,C,CUR) EQ 0)\$DAM_COST(R,T,C,CUR)) = 0;                      (L25)
    LOOP(RDCUR(R,CUR), RXX(RTC)\$DAM_COST(RTC,CUR) = YES); LOOP(T,TRACKC(R,C)\$RXX(R,T,C) = YES);    (L27-28)
    DAM_TVOC(RXX(R,T,C),BD) \$= DAM_VOC(R,C,BD);                                                    (L29)
    RHS_COMBAL(RTCS_VARC(RXX(R,T,C),S))\$(NOT DAM_ELAST(R,C,'N')) = YES;                             (L30)
    RCS_COMBAL(RHS_COMBAL(RXX(R,T,C),S),'FX') = YES;                                               (L31)
    DAM_TQTY(RXX(R,T,C))\$(DAM_TQTY(R,T,C) LE 0) = MAX(0,DAM_TVOC(R,T,C,'LO'));                     (L33)
    DAM_TVOC(RXX(R,T,C),BD)\$(NOT DAM_TQTY(R,T,C)) = 0;                                             (L34)
    LOOP(T,DAM_ELAST(R,C,BD)\$((NOT DAM_TQTY(R,T,C))\$RXX(R,T,C)) = 0);                              (L35)
    DAM_STEP(TRACKC(R,C),'FX') = 0; Z = 100;                                                       (L36)
    DAM_STEP(TRACKC(R,C),BD)\$((NOT DAM_STEP(R,C,BD))\$DAM_ELAST(R,C,BD)) = 1;                       (L37)
    DAM_STEP(TRACKC(R,C),BD)\$DAM_STEP(R,C,BD) = MIN(Z,ABS(ROUND(DAM_STEP(R,C,BD))));                (L38)
    DAM_ELAST(TRACKC(R,C),'LO') = ABS(DAM_ELAST(R,C,'UP')\$(NOT DAM_ELAST(R,C,'LO'))+DAM_ELAST(R,C,'LO'));   (L40)
    DAM_ELAST(TRACKC(R,C),'UP') = ABS(DAM_ELAST(R,C,'LO')\$(NOT DAM_ELAST(R,C,'UP'))+DAM_ELAST(R,C,'UP'));   (L41)
    [L43-46: DAM_TVOC, `dam_tvoc`]
    LOOP(RXX(R,T,C), F = DAM_STEP(R,C,'LO'); Z = DAM_STEP(R,C,'UP');
      FIRST_VAL = DAM_TVOC(R,T,C,'LO'); LAST_VAL = DAM_TVOC(R,T,C,'UP');
      IF(F, DAM_SIZE(R,T,C,'FX') = 2*(FIRST_VAL-(FIRST_VAL*(4*Z+1)-LAST_VAL)/(1+Z*(4+1/F)));
      ELSE  DAM_SIZE(R,T,C,'FX') = FIRST_VAL+0.5*LAST_VAL/(Z+0.5)));                              (L47-51)
    DAM_SIZE(RXX(R,T,C),BDNEQ(BD))\$DAM_STEP(R,C,BD) = MAX(0,(DAM_TVOC(R,T,C,BD)-0.5*DAM_SIZE(R,T,C,'FX')))/DAM_STEP(R,C,BD);   (L52)
    DAM_SIZE(RXX(R,T,C),'UP')\$(NOT DAM_STEP(R,C,'LO')) = MAX(0,DAM_TVOC(R,T,C,'UP')/(DAM_STEP(R,C,'UP')+0.5));    (L53)
    DAM_SIZE(RXX(R,T,C),'N') = DAM_TQTY(R,T,C)-DAM_TVOC(R,T,C,'LO')+0.5*DAM_SIZE(R,T,C,'LO')\$DAM_ELAST(R,C,'N');   (L54)
    DAM_COEF(RTCS_VARC(R,T,C,S))\$((NOT DAM_COEF(R,T,C,S))\$TRACKC(R,C)) = 1;                        (L55)
    JSUBJ(JJ,J)\$((ORD(J) LE ORD(JJ))\$(ORD(JJ)<=100)) = YES;                                        (L56)
    DAM_STEP(TRACKC(R,C),'FX')\$(DAM_STEP(R,C,'N') EQ 0) = 1+1\$SUM(T\$(DAM_SIZE(R,T,C,'N') GT 0),YES);  (L58)
    IF(CARD(DAM_COST)=0,SUM_OBJ('OBJDAM',ITEM)=0);                                                  (L59)
    RTDAM(RXX(R,T,C),'1') = YES;                                                                   (L60, %SWX% = ,'1')
    LOOP(SAMEAS(J,'1'),DAM_NUM(TRACKC(R,C),J+(DAM_STEP(R,C,BD)-1),BD) = YES);                       (L137)
    OPTION CLEAR=TRACKC,CLEAR=RXX,CLEAR=DAM_TVOC;                                                  (L159)
    DAM_TVOC(R,T,C,'N')\$DAM_SIZE(R,T,C,'N') = ((DAM_SIZE(R,T,C,'N')/DAM_TQTY(R,T,C))**DAM_ELAST(R,C,'LO'))\$DAM_ELAST(R,C,'N');   (L161)

BD is LO, UP and FX (BND_TYPE), BDNEQ LO and UP. The bounds of VAR_DAM (L138-142) are `bnd_dam!`.

GAMS: eqdamage.mod L11-60, L135-142, L157-161, v4.9.7.
"""
function dam_prep!(tm)
    damage_on(tm) || return tm
    damage_unported(tm)
    d = tm.data
    S(n) = gset(tm, n)
    tlist = [k[1] for k in S("MILESTONYR").keys]
    bds = ("LO", "UP", "FX")
    # L20: filparam DAM_TQTY over the milestone years
    st = InterpState(tm)
    filparam!(st, "DAM_TQTY", "R,", "C", pd(",'0','0','0','0'"), [y for y in st.ax.years if y in st.datayear], tlist;
              year_in_uncd7=true)
    put_interp_scratch!(st)
    tqty = gvalues(tm, "DAM_TQTY", 3)
    # L21
    regs, coms = [k[1] for k in S("REG").keys], S("COM").members
    for ((r, c), x) in gvalues(tm, "DAM_BQTY", 2)
        (r in regs && (c,) in coms) || continue
        for t in tlist
            haskey(tqty, (r, t, c)) || gassign!(tqty, (r, t, c), GNum(x, x == 0))
        end
    end
    # L25
    cost = gvalues(tm, "DAM_COST", 4)
    filter!(((_, x),) -> x != 0, cost)
    gput!(tm, "DAM_COST", cost)
    # L27-28
    rtc = S("RTC")
    rdcur = S("RDCUR").members
    rxx = Set{NTuple{3,String}}()
    for (r, t, c, cur) in keys(cost)
        ((r, cur) in rdcur && (r, t, c) in rtc) && push!(rxx, (r, t, c))
    end
    trackc = Set((k[1], k[3]) for k in rxx)
    voc = gparam(tm, "DAM_VOC")
    elast = gvalues(tm, "DAM_ELAST", 3)
    # L29
    tvoc = Dict{NTuple{4,String},Float64}()
    for (r, t, c) in rxx, bd in bds
        x = gv(voc, (r, c, bd))
        iszero(x) || gassign!(tvoc, (r, t, c, bd), x)
    end
    # L30-31
    rhs_combal, rcs_combal = gmembers(tm, "RHS_COMBAL", 4), gmembers(tm, "RCS_COMBAL", 5)
    for (r, t, c, s) in S("RTCS_VARC").keys
        ((r, t, c) in rxx && !haskey(elast, (r, c, "N"))) && push!(rhs_combal, (r, t, c, s))
    end
    foreach(k -> (k[1], k[2], k[3]) in rxx && push!(rcs_combal, (k..., "FX")), rhs_combal)
    gput!(tm, "RHS_COMBAL", rhs_combal); gput!(tm, "RCS_COMBAL", rcs_combal)
    # L33-35
    for k in rxx
        gv(tqty, k).v <= 0 && gassign!(tqty, k, gmax(GZERO, gv(tvoc, (k..., "LO"))))
    end
    for k in rxx, bd in bds
        haskey(tqty, k) || delete!(tvoc, (k..., bd))
    end
    for (r, t, c) in rxx
        haskey(tqty, (r, t, c)) || foreach(bd -> delete!(elast, (r, c, bd)), bds)
    end
    gput!(tm, "DAM_TQTY", tqty)
    # L36-38
    step = gvalues(tm, "DAM_STEP", 3)
    foreach(rc -> delete!(step, (rc..., "FX")), trackc)
    for (r, c) in trackc, bd in bds
        (!haskey(step, (r, c, bd)) && haskey(elast, (r, c, bd))) && (step[(r, c, bd)] = 1.0)
    end
    for (r, c) in trackc, bd in bds
        haskey(step, (r, c, bd)) && gassign!(step, (r, c, bd), GNum(min(100.0, abs(round(step[(r, c, bd)], RoundNearestTiesAway)))))
    end
    # L40-41
    for (r, c) in trackc
        lo, up = gv(elast, (r, c, "LO")), gv(elast, (r, c, "UP"))
        gassign!(elast, (r, c, "LO"), GNum(abs((gif(up, iszero(lo)) + lo).v)))
        lo = gv(elast, (r, c, "LO"))
        gassign!(elast, (r, c, "UP"), GNum(abs((gif(lo, iszero(up)) + up).v)))
    end
    gput!(tm, "DAM_ELAST", elast); gput!(tm, "DAM_STEP", step)
    # L43-46
    stepv(r, c, bd) = gv(step, (r, c, bd))
    for (r, t, c) in rxx, bd in bds
        haskey(tvoc, (r, t, c, bd)) && continue
        x = (stepv(r, c, bd) + 0.5) * gv(voc, (r, c, "N")) * gv(tqty, (r, t, c))
        iszero(x) || gassign!(tvoc, (r, t, c, bd), x)
    end
    for (r, t, c) in rxx
        lo = gv(tvoc, (r, t, c, "LO"))
        gassign!(tvoc, (r, t, c, "LO"), gmin(gv(tqty, (r, t, c)), lo + (iszero(lo) ? GNum(Inf) : GZERO)))
        if !haskey(tvoc, (r, t, c, "UP"))
            lo = gv(tvoc, (r, t, c, "LO"))
            f = gif((stepv(r, c, "UP") + 0.5) / (stepv(r, c, "LO") + 0.5) - 1, !iszero(stepv(r, c, "LO")))
            gassign!(tvoc, (r, t, c, "UP"), lo * (1 + f))
        end
    end
    # L47-51
    size = gvalues(tm, "DAM_SIZE", 4)
    F = Z = FV = LV = GZERO
    for (r, t, c) in gams_sort!(collect(rxx), d)
        F, Z = stepv(r, c, "LO"), stepv(r, c, "UP")
        FV, LV = gv(tvoc, (r, t, c, "LO")), gv(tvoc, (r, t, c, "UP"))
        x = !iszero(F) ? 2 * (FV - (FV * (4 * Z + 1) - LV) / (1 + Z * (4 + 1 / F))) : FV + 0.5 * LV / (Z + 0.5)
        gassign!(size, (r, t, c, "FX"), x)
    end
    isempty(rxx) || (gput_scalar!(tm, "F", F); gput_scalar!(tm, "Z", Z); gput_scalar!(tm, "FIRST_VAL", FV); gput_scalar!(tm, "LAST_VAL", LV))
    isempty(rxx) && gput_scalar!(tm, "Z", 100.0)
    # L52-54
    for (r, t, c) in rxx
        for bd in ("LO", "UP")
            iszero(stepv(r, c, bd)) && continue
            gassign!(size, (r, t, c, bd), gmax(GZERO, gv(tvoc, (r, t, c, bd)) - 0.5 * gv(size, (r, t, c, "FX"))) / stepv(r, c, bd))
        end
        iszero(stepv(r, c, "LO")) &&
            gassign!(size, (r, t, c, "UP"), gmax(GZERO, gv(tvoc, (r, t, c, "UP")) / (stepv(r, c, "UP") + 0.5)))
        gassign!(size, (r, t, c, "N"), gv(tqty, (r, t, c)) - gv(tvoc, (r, t, c, "LO")) +
                                       gif(0.5 * gv(size, (r, t, c, "LO")), haskey(elast, (r, c, "N"))))
    end
    gput!(tm, "DAM_SIZE", size)
    # L55
    coef = gvalues(tm, "DAM_COEF", 4)
    for (r, t, c, s) in S("RTCS_VARC").keys
        ((r, c) in trackc && !haskey(coef, (r, t, c, s))) && (coef[(r, t, c, s)] = 1.0)
    end
    gput!(tm, "DAM_COEF", coef)
    # L56
    jl = [k[1] for k in S("J").keys]
    jsubj = Set{NTuple{2,String}}()
    for (a, jj) in enumerate(jl), (b, j) in enumerate(jl)
        (b <= a && a <= 100) && push!(jsubj, (jj, j))
    end
    gput!(tm, "JSUBJ", jsubj)
    # L58
    for (r, c) in trackc
        iszero(gv(step, (r, c, "N"))) || continue
        any(t -> gv(size, (r, t, c, "N")).v > 0, tlist) ? (step[(r, c, "FX")] = 2.0) : (step[(r, c, "FX")] = 1.0)
    end
    gput!(tm, "DAM_STEP", step)
    # L60: RTDAM
    gput!(tm, "RTDAM", Set((k..., "1") for k in rxx))
    # L137: DAM_NUM(TRACKC(R,C),J+(DAM_STEP(R,C,BD)-1),BD)
    dam_num = gmembers(tm, "DAM_NUM", 4)
    for (r, c) in trackc, bd in bds
        n = round(Int, stepv(r, c, bd).v)
        1 <= n <= length(jl) && push!(dam_num, (r, c, jl[n], bd))
    end
    gput!(tm, "DAM_NUM", dam_num)
    # L159-161
    gput!(tm, "TRACKC", Set{NTuple{2,String}}()); gput!(tm, "RXX", Set{NTuple{3,String}}())
    tv = Dict{NTuple{4,String},Float64}()
    for ((r, t, c, b), x) in size
        b == "N" || continue
        haskey(elast, (r, c, "N")) || continue
        gassign!(tv, (r, t, c, "N"), gpow(GNum(x) / gv(tqty, (r, t, c)), gv(elast, (r, c, "LO"))))
    end
    gput!(tm, "DAM_TVOC", tv)
    return tm
end

"""
    dam_ub(tm) -> Dict{NTuple{5,String},Float64}

The upper bounds of VAR_DAM(R,T,C,BD,J) that the BOUND label sets (L138-142), %SWX% = ,'1':

    VAR_DAM.UP(R,T,C,BD,J) = INF;
    VAR_DAM.UP(RTC(R,T,C),'LO',J)\$((ORD(J) LE DAM_STEP(R,C,'LO'))\$RTDAM(RTC,'1')) = DAM_SIZE(RTC,'LO');
    VAR_DAM.UP(RTC(R,T,C),'LO','1')\$(DAM_ELAST(R,C,'N')\$RTDAM(RTC,'1')) = DAM_SIZE(RTC,'LO')+DAM_TQTY(RTC)-DAM_TVOC(RTC,'LO');
    VAR_DAM.UP(RTC(R,T,C),'UP',J)\$((ORD(J) LT DAM_STEP(R,C,'UP'))\$RTDAM(RTC,'1')) = DAM_SIZE(RTC,'UP');
    VAR_DAM.UP(RTC(R,T,C),'FX','1')\$(DAM_TVOC(RTC,'UP')\$RTDAM(RTC,'1')) = DAM_SIZE(RTC,'FX');
    VAR_DAM.UP(RTC(R,T,C),'FX','2')\$RTDAM(RTC,'1') = DAM_SIZE(RTC,'N')\$(NOT DAM_ELAST(R,C,'N'));

DAM_TVOC as it stands there (`dam_tvoc`). Keys not listed are INF.

GAMS: eqdamage.mod L138-142, v4.9.7.
"""
function dam_ub(tm)
    get!(tm.cache, "DAM_UB") do
        out = Dict{NTuple{5,String},Float64}()
        size, step, elast, tqty = gparam(tm, "DAM_SIZE"), gparam(tm, "DAM_STEP"), gparam(tm, "DAM_ELAST"), gparam(tm, "DAM_TQTY")
        tvoc = dam_tvoc(tm)
        jl = [k[1] for k in gset(tm, "J").keys]
        rtc = gset(tm, "RTC")
        for (r, t, c, _) in gset(tm, "RTDAM").keys
            (r, t, c) in rtc || continue
            nlo, nup = gv(step, (r, c, "LO")).v, gv(step, (r, c, "UP")).v
            for (o, j) in enumerate(jl)
                o <= nlo && (out[(r, t, c, "LO", j)] = gv(size, (r, t, c, "LO")).v)
                o < nup && (out[(r, t, c, "UP", j)] = gv(size, (r, t, c, "UP")).v)
                (o > nlo && o >= nup) && break
            end
            haskey(elast.values, (r, c, "N")) &&
                (out[(r, t, c, "LO", "1")] = (gv(size, (r, t, c, "LO")) + gv(tqty, (r, t, c)) - GNum(get(tvoc, (r, t, c, "LO"), 0.0))).v)
            iszero(get(tvoc, (r, t, c, "UP"), 0.0)) || (out[(r, t, c, "FX", "1")] = gv(size, (r, t, c, "FX")).v)
            out[(r, t, c, "FX", "2")] = haskey(elast.values, (r, c, "N")) ? 0.0 : gv(size, (r, t, c, "N")).v
        end
        out
    end::Dict{NTuple{5,String},Float64}
end

"bnd_dam!(bt, tm): the VAR_DAM upper bounds of eqdamage.mod L138-142 (`dam_ub`), for the columns the equations created."
function bnd_dam!(bt, tm)
    (damage_on(tm) && haskey(tm.vars.families, "VAR_DAM")) || return bt
    ub = dam_ub(tm)
    recs = get!(() -> Dict{Tuple,Tuple{Float64,Float64}}(), bt.recs, "VAR_DAM")
    for k in tm.vars.families["VAR_DAM"].keys
        recs[k] = (0.0, get(ub, k, Inf))
    end
    return bt
end

"""
    eq_damage!(tm) -> Int

EQ_DAMAGE and EQ_OBJDAM (eqmain.mod L262; mod_equa.mod L210 with %DAMAGE% not NO):

    EQ_DAMAGE(RTC(R,T,C))\$(SUM(RDCUR(R,CUR)\$DAM_COST(R,T,C,CUR),1)\$RTDAM(RTC,'1'))..             (L67-73)
      SUM(DAM_NUM(R,C,JJ,BD),SUM(JSUBJ(JJ,J),VAR_DAM(R,T,C,BD,J))) =E=
      (SUM(COM_TS(RC(R,C),S),DAM_COEF(R,T,C,S)*VAR_COMNET(R,T,C,S)\$(NOT DAM_ELAST(R,C,'N')) +
                             DAM_COEF(R,T,C,S)*VAR_COMPRD(R,T,C,S)\$DAM_ELAST(R,C,'N')))\$DAM_STEP(R,C,'FX');
    EQ_OBJDAM(RDCUR(R,CUR))..                                                                       (L77-94)
      SUM(RTC(R,T,C)\$(DAM_STEP(R,C,'FX')\$DAM_COST(R,T,C,CUR)),
        (SUM((DAM_NUM(R,C,JJ,'LO'),JSUBJ(JJ,J)),
           (VAR_DAM(R,T,C,'LO',J) + DAM_ELAST(R,C,'N')*VAR_DAM.UP(R,T,C,'LO',J)) *
           ((DAM_TQTY(R,T,C)-DAM_SIZE(R,T,C,'FX')/2-DAM_SIZE(R,T,C,'LO')*(ORD(JJ)-ORD(J)+.5))**DAM_ELAST(R,C,'LO') /
            DAM_TQTY(R,T,C)**DAM_ELAST(R,C,'LO') + DAM_ELAST(R,C,'N')))\$DAM_TQTY(R,T,C) +
         VAR_DAM(R,T,C,'FX','1') * (1 + DAM_ELAST(R,C,'N')) +
         SUM((DAM_NUM(R,C,JJ,'UP'),JSUBJ(JJ,J)), VAR_DAM(R,T,C,'UP',J) *
           ((DAM_TQTY(R,T,C)+DAM_SIZE(R,T,C,'FX')/2+DAM_SIZE(R,T,C,'UP')*(ORD(J)-.5))**DAM_ELAST(R,C,'UP') /
            DAM_TQTY(R,T,C)**DAM_ELAST(R,C,'UP') + DAM_ELAST(R,C,'N')))\$DAM_TQTY(R,T,C)
        ) * OBJ_PVT(R,T,CUR) * DAM_COST(R,T,C,CUR))
      =E= SUM(OBV,SUM_OBJ('OBJDAM',OBV)*VAR_OBJ(R,OBV,CUR));

`VAR_DAM.UP` in EQ_OBJDAM is the bound's value, a constant (`dam_ub`; INF where no bound is set, which
GAMS would refuse, so it raises). ORD is the position in J. Returns the number of rows.

GAMS: eqdamage.mod L67-94, v4.9.7.
"""
function eq_damage!(tm::TimesModel)
    damage_on(tm) || return 0
    S(n) = gset(tm, n)
    P(n) = gparam(tm, n)
    cost, rtdam, rdcur, rtc = P("DAM_COST"), S("RTDAM"), S("RDCUR"), S("RTC")
    elast, step, size, tqty, coef = P("DAM_ELAST"), P("DAM_STEP"), P("DAM_SIZE"), P("DAM_TQTY"), P("DAM_COEF")
    dam_num = S("DAM_NUM")
    jl = [k[1] for k in S("J").keys]
    ordj = Dict(j => i for (i, j) in enumerate(jl))
    num_of = indexby(dam_num, (1, 2, 4))                                  # (r,c,bd) -> DAM_NUM(r,c,jj,bd)
    comts_of = indexby(S("COM_TS"), (1, 2))
    rc = S("RC")
    obj_pvt = P("OBJ_PVT")
    ub = dam_ub(tm)
    tx = eq_periods(tm)
    n = 0
    # EQ_DAMAGE
    for (r, t, c) in rtc.keys
        (t,) in tx || continue
        ((r, t, c, "1") in rtdam && any(k -> k[1] == r && haskey(cost.values, (r, t, c, k[2])), rdcur.keys)) || continue
        lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
        for bd in ("LO", "UP", "FX"), (_, _, jj, _) in get(num_of, (r, c, bd), NTuple{4,String}[])
            for j in jl
                ordj[j] <= ordj[jj] <= 100 || continue                   # JSUBJ(JJ,J)
                addterm!(lhs, GNum(1.0), tm, "VAR_DAM", r, t, c, bd, j)
            end
        end
        if !iszero(gv(step, (r, c, "FX"))) && (r, c) in rc
            en = haskey(elast.values, (r, c, "N"))
            for (_, _, s) in get(comts_of, (r, c), NTuple{3,String}[])
                addterm!(rhs, gv(coef, (r, t, c, s)), tm, en ? "VAR_COMPRD" : "VAR_COMNET", r, t, c, s)
            end
        end
        gconstraint!(tm, "EQ_DAMAGE", (r, t, c), "E", lhs, rhs) === nothing || (n += 1)
    end
    # EQ_OBJDAM
    for (r, cur) in rdcur.keys
        lhs = JuMP.AffExpr(0.0)
        for (rr, t, c) in rtc.keys
            rr == r || continue
            (!iszero(gv(step, (r, c, "FX"))) && haskey(cost.values, (r, t, c, cur))) || continue
            w = gv(obj_pvt, (r, t, cur)) * gv(cost, (r, t, c, cur))
            en = gv(elast, (r, c, "N"))
            q = gv(tqty, (r, t, c))
            if !iszero(q)
                el = gv(elast, (r, c, "LO"))
                for (_, _, jj, _) in get(num_of, (r, c, "LO"), NTuple{4,String}[]), j in jl
                    ordj[j] <= ordj[jj] <= 100 || continue
                    base = q - gv(size, (r, t, c, "FX")) / 2 - gv(size, (r, t, c, "LO")) * (ordj[jj] - ordj[j] + 0.5)
                    k = gpow(base, el) / gpow(q, el) + en
                    addterm!(lhs, k * w, tm, "VAR_DAM", r, t, c, "LO", j)
                    if !iszero(en)
                        u = get(ub, (r, t, c, "LO", j), Inf)
                        isfinite(u) || throw(DomainError((r, t, c, "LO", j), "eqdamage.mod L82: VAR_DAM.UP is INF in EQ_OBJDAM"))
                        addconst!(lhs, en * GNum(u) * k * w)
                    end
                end
            end
            addterm!(lhs, (1 + en) * w, tm, "VAR_DAM", r, t, c, "FX", "1")
            if !iszero(q)
                eu = gv(elast, (r, c, "UP"))
                for (_, _, jj, _) in get(num_of, (r, c, "UP"), NTuple{4,String}[]), j in jl
                    ordj[j] <= ordj[jj] <= 100 || continue
                    base = q + gv(size, (r, t, c, "FX")) / 2 + gv(size, (r, t, c, "UP")) * (ordj[j] - 0.5)
                    addterm!(lhs, (gpow(base, eu) / gpow(q, eu) + en) * w, tm, "VAR_DAM", r, t, c, "UP", j)
                end
            end
        end
        rhs = obj_component_rhs(tm, objective_context(tm), r, cur, "OBJDAM")
        gconstraint!(tm, "EQ_OBJDAM", (r, cur), "E", lhs, rhs) === nothing || (n += 1)
    end
    return n
end
