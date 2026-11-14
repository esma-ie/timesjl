# M1.3 change 25-3: the data statements of eqmain.mod after the objective (the equation
# includes' own preparation, RVPT, the user-constraint maps) and of equ_ext.vda, the third part
# of the coef -> pre-solve step.
#
# In eqmain.mod order (v4.9.7): eqcapact.mod L18-20 (AFS, in the `L` include, L65), coef_csv.mod
# L24-74 (L67, when PRC_SIMV is DEFINED: the simulated vintages, `coef_csv!` in coef_csv.jl), eqbndcst.mod
# L14-77 (L192: SUPERYR, the cost bounds REG_CUMCST, RT_IAN and the annual investment coefficients
# CST_ANNC, YK1; the equation EQ_BNDCST is in eqbndcst.jl), L199-202 (RVPT, RTP_OFF), L205-226 (the
# user-constraint maps); then equ_ext.vda L76-79 (RP_PL, AFS), eqactups.vda L9-32 (the dispatching
# preparation, `eqactups_prep!` in ext/vda/eqactups.jl) and L33 (RP_UPR, outside the dispatching
# IF, so in every model), eqlducs.vda L46-51 (the unit-commitment processes, `eqlducs_equ!` in
# ext/vda/eqlducs.jl). The other includes have no data
# statements that act here: eqflomrk.mod, eqashar.vda and pp_actef.vda jump to their equations
# under the arguments eqmain.mod and equ_ext.vda pass.
#
# Not translated (UnportedError): VAR_UC not YES (L205-206).

"""
    eqmain_prep_unported(tm) -> Vector{String}

The data that would take eqmain.mod / equ_ext.vda preparation not translated.
"""
function eqmain_prep_unported(tm::TimesModel)
    d = tm.data
    out = String[]
    has_uc = !isempty(gparam_opt(d, "UC_RHS", 2)) || !isempty(gparam_opt(d, "UC_RHSR", 3)) ||
             !isempty(gparam_opt(d, "UC_RHST", 3)) || !isempty(gparam_opt(d, "UC_RHSRT", 4)) ||
             !isempty(gparam_opt(d, "UC_RHSTS", 4)) || !isempty(gparam_opt(d, "UC_RHSRTS", 5))
    (has_uc && !var_uc(tm)) && push!(out, "eqmain.mod L205-226: user constraints with VAR_UC not YES")
    return out
end

"""
    eqmain_prep_symbols(tm) -> Vector{String}

The sets and parameters eqmain_prep! settles. The scratch set UNCD7 is one of
them only with dispatching data: eqactups.vda L10 and L28 write it inside the
dispatching IF (L9). Without it eqmain.mod leaves UNCD7 as eqobjinv.mod
L245-247 filled it (the decommissioning spreads), and pp_qack.mod L258 and
L339-342 replace that later when the extended checks run (`pp_qack_data!`,
which compares UNCD7 itself).
"""
eqmain_prep_symbols(tm) = vcat(["AFS", "SUPERYR", "REG_CUMCST", "YK1", "RT_IAN", "RTP_IAN", "CST_ANNC", "YKK", "RVPT", "RTP_OFF", "UC_TMAP",
                                "UC_RHSMAP", "UC_RTSUC", "UC_UT", "UC_UTS", "UC_RHSTMP", "RUCTS", "RP_PL", "RP_UPR",
                                # eqactups.vda L9-32
                                "AFUPS", "RPS_UPS", "RP_UX", "RTP_VARP", "COEF_AF", "RP_UPS", "RPC_CUR", "ACT_LOSPL",
                                "ACT_UPS", "RTP_PL", "RP_UPC"],   # TS_ARRAY (L28) is cleared later (pp_clean)
                               eqactups_dispatching(tm.data) ? ["UNCD7"] : String[],   # eqactups.vda L10, L28
                               simv_defined(tm) ? coef_csv_symbols(tm) : String[])

"""
    eqmain_prep!(tm) -> tm

    AFS: LOOP(V,AFS(RTP_VARA(R,T,P),S,BD)\$COEF_AF(R,V,T,P,S,BD)=YES); AFS(RTPS_OFF,BD) = NO;   (eqcapact.mod L20)
    [\$IF DEFINED PRC_SIMV: coef_csv.mod L24-74, `coef_csv!`]                                  (eqmain.mod L67)
    SUPERYR(PERIODYR(T,LL))\$(YEARVAL(LL) LE YEARVAL(T)) = YES;                                (eqbndcst.mod L38)
    SUPERYR(T+1,LL)\$((YEARVAL(LL) GT YEARVAL(T))\$PERIODYR(T,LL)) = YES;                       (L39)
    LOOP(MIYR_1(T++1),SUPERYR(T,LL)\$(YEARVAL(LL) GT M(T)) = YES);                            (L40)
    REG_CUMCST(R,T,T,COSTAGG,CUR,BD) \$= REG_BNDCST(R,T,COSTAGG,CUR,BD);                       (L42)
    [L44-47: the upper bound INF for the components of a bounded aggregate (COST_GMAP) and for a
     lower or fixed bound alone]
    [L50-52, L66-69: TRACKP from UC_ATTR, RT_IAN (the bounds of single periods on INV and on
     INVTAX/INVSUB), RTP_IAN]
    OPTION CLEAR=YK1; YK1(TT,T)\$YK(T,TT) = YES;                                               (L54)
    [L55-64, L70-76: CST_ANNC 'INVCOST', 'INVTAX', 'INVSUB', the annual investment cost, tax and
     subsidy of a unit of capacity; YKK and the scalars F, Z are scratch]
    OPTION CLEAR=TRACKP, CLEAR=RTP_IAN;                                                       (L77)
    LOOP(OBJ_2A(R,T,P)\$(NOT RTP_OFF(R,T,P)),F=B(T)+NCAP_ILED(R,T,P); Z=SUM(VNT(T,TT)\$(F>E(TT)+0.5),1);
      RVPT(R,T,P,T+Z) = YES);                                                                 (eqmain.mod L200-201)
    RTP_OFF(OBJ_2A(R,T,P))\$(NOT SUM(RVPT(R,T,P,TT),1)) = YES;                               (L202)
    [UC_TMAP, UC_RHSMAP, UC_RTSUC, UC_UT, UC_UTS: `uc_tmap`, `uc_setup`; UC_RHSTMP, RUCTS cleared] (L211-226)
    RP_PL(RP,BD)\$SUM(RPG_PACE(RP,CG),1) = NO;                                                (equ_ext.vda L77)
    AFS(RTP(R,T,P),S,BDUPX)\$NCAP_AFCS(RTP,'ACT',S) = NO;                                      (L79)
    [the dispatching preparation: `eqactups_prep!`]                                           (eqactups.vda L9-32)
    OPTION RP_UPR < ACT_CSTRMP;                                                               (L33)
    [the unit-commitment processes: `eqlducs_equ!`]                                           (eqlducs.vda L46-51)

GAMS: eqcapact.mod L18-20, coef_csv.mod L24-74, eqbndcst.mod L14-77, eqmain.mod L197-226, equ_ext.vda L76-79,
eqactups.vda L9-33, eqlducs.vda L46-51, v4.9.7.
"""
function eqmain_prep!(tm::TimesModel)
    u = eqmain_prep_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    d = tm.data
    S(name, n) = gset_opt(d, name, n)
    P(name, n) = gparam_opt(d, name, n)
    yv = gparam(tm, "YEARVAL")
    yval(y) = gv(yv, (y,)).v
    T = S("MILESTONYR", 1)
    tlist = [k[1] for k in T.keys]
    tpos = Dict(t => i for (i, t) in enumerate(tlist))

    # eqcapact.mod L20 (the L include): AFS
    rtp_vara = S("RTP_VARA", 3)
    afs = Set{NTuple{5,String}}()
    for (r, v, t, p, s, bd) in P("COEF_AF", 6).keys
        (r, t, p) in rtp_vara && push!(afs, (r, t, p, s, bd))
    end
    rtps_off = S("RTPS_OFF", 4)
    filter!(k -> !((k[1], k[2], k[3], k[4]) in rtps_off), afs)
    # eqmain.mod L67: $IF DEFINED PRC_SIMV $INCLUDE coef_csv.mod (the AFS entries of PRC_SIMV go to AFSV)
    simv_defined(tm) && coef_csv!(tm, afs)

    # eqbndcst.mod L38-40: SUPERYR
    superyr = gmembers(tm, "SUPERYR", 2)
    periodyr = S("PERIODYR", 2)
    for (t, ll) in periodyr
        haskey(tpos, t) || continue
        yval(ll) <= yval(t) && push!(superyr, (t, ll))
        i = tpos[t]
        (yval(ll) > yval(t) && i < length(tlist)) && push!(superyr, (tlist[i+1], ll))
    end
    M = P("M", 1)
    miyr_1 = S("MIYR_1", 1)
    for (i, t) in enumerate(tlist)                                         # LOOP(MIYR_1(T++1), ...)
        (tlist[mod1(i + 1, length(tlist))],) in miyr_1 || continue
        for y in (k[1] for k in S("ALLYEAR", 1).keys)
            yval(y) > gv(M, (t,)).v && push!(superyr, (t, y))
        end
    end
    gput!(tm, "SUPERYR", superyr)
    # L54: OPTION CLEAR=YK1; YK1(TT,T)$YK(T,TT) = YES (T, TT milestone years)
    yk = S("YK", 2)
    yk1 = Set((tt, t) for (t, tt) in yk if haskey(tpos, t) && haskey(tpos, tt))
    gput!(tm, "YK1", yk1)

    # eqbndcst.mod L42-77: the cost bounds of a region (REG_BNDCST, REG_CUMCST) and the annual
    # investment coefficients CST_ANNC. Without cost-bound data and without UC_ATTR on NCAP with an
    # annual cost attribute, every statement is empty.
    reg, costagg = S("REG", 1), S("COSTAGG", 1)
    ord = Dict(k[1] => i for (i, k) in enumerate(S("ALLYEAR", 1).keys))          # ORD(YEAR), ORD(LL), ORD(ALLYEAR)
    aord = Dict(k[1] => i for (i, k) in enumerate(S("LIFE", 1).keys))            # ORD(AGE), ORD(JOT), ORD(LIFE)
    # L42: REG_CUMCST(R,T,T,COSTAGG,CUR,BD) $= REG_BNDCST(R,T,COSTAGG,CUR,BD)
    cumcst = gvalues(tm, "REG_CUMCST", 6)
    bndcst = P("REG_BNDCST", 5)
    for k in bndcst.keys
        (r, t, agg, cur, bd) = k
        ((r,) in reg && haskey(tpos, t) && (agg,) in costagg) || continue
        gassign!(cumcst, (r, t, t, agg, cur, bd), gv(bndcst, k))
    end
    # L44-45: LOOP((COST_GMAP(COSTCAT,COSTAGG,COSTYPE),BD), REG_CUMCST(R,YEAR,LL,COSTAGG,CUR,'UP')$((NOT
    #   REG_CUMCST(R,YEAR,LL,COSTAGG,CUR,'UP'))$REG_CUMCST(R,YEAR,LL,COSTCAT,CUR,BD)) = INF): a bound on an
    #   aggregate gives each of its components without an upper bound the upper bound INF. An entry
    #   that holds EPS is an entry (the `$` and the NOT see it).
    parts_of = indexby(S("COST_GMAP", 3), (1,))                                # aggregate -> COST_GMAP(aggregate,component,type)
    bds = Set(k[1] for k in S("BD", 1).keys)
    for (r, y, ll, cat, cur, bd) in collect(keys(cumcst))
        ((r,) in reg && bd in bds) || continue
        for (_, agg, _) in get(parts_of, (cat,), NTuple{3,String}[])
            haskey(cumcst, (r, y, ll, agg, cur, "UP")) || (cumcst[(r, y, ll, agg, cur, "UP")] = Inf)
        end
    end
    # L46-47: LOOP(BDLOX(BD), REG_CUMCST(R,YEAR,LL,COSTCAT,CUR,'UP')$((NOT REG_CUMCST(R,YEAR,LL,COSTCAT,CUR,'UP'))
    #   $REG_CUMCST(R,YEAR,LL,COSTCAT,CUR,BD)) = INF): a lower or fixed bound alone gets the upper bound INF.
    bdlox = Set(k[1] for k in S("BDLOX", 1).keys)
    for (r, y, ll, cat, cur, bd) in collect(keys(cumcst))
        ((r,) in reg && bd in bdlox && (cat,) in costagg) || continue
        haskey(cumcst, (r, y, ll, cat, cur, "UP")) || (cumcst[(r, y, ll, cat, cur, "UP")] = Inf)
    end
    gput!(tm, "REG_CUMCST", cumcst)

    # L50: LOOP(UC_ATTR(R,UC_N,SIDE,'NCAP','INVCOST'),LOOP(T,TRACKP(R,P)$UC_NCAP(UC_N,SIDE,R,T,P)=YES));
    # TRACKP is not cleared first; the last statements before it leave it empty (coef_shp.mod L74,
    # coef_cpt.mod L63), so the state's value is the start.
    trackp = gmembers(tm, "TRACKP", 2)
    uc_attr = S("UC_ATTR", 5)
    ncap_of_uc = indexby(P("UC_NCAP", 5), (1, 2, 3))                           # (uc_n,side,r) -> UC_NCAP(uc_n,side,r,t,p)
    function track!(names)
        for (r, uc_n, side, grp, name) in uc_attr
            (grp == "NCAP" && name in names && (r,) in reg) || continue
            for (_, _, _, t, p) in get(ncap_of_uc, (uc_n, side, r), NTuple{5,String}[])
                haskey(tpos, t) && push!(trackp, (r, p))
            end
        end
    end
    track!(("INVCOST",))
    # L51: RT_IAN(R,T,T,CUR,'INV')$REG_CUMCST(R,T,T,'INV',CUR,'UP') = YES
    rt_ian = Set{NTuple{5,String}}()
    for (r, y, ll, cat, cur, bd) in keys(cumcst)
        (cat == "INV" && bd == "UP" && y == ll && haskey(tpos, y) && (r,) in reg) && push!(rt_ian, (r, y, y, cur, "INV"))
    end
    # L52: RTP_IAN(OBJ_ICUR(R,T,P,CUR))$(RT_IAN(R,T,T,CUR,'INV')+TRACKP(R,P)) = YES
    obj_icur = S("OBJ_ICUR", 4)
    rtp_ian = Set{NTuple{4,String}}()
    for (r, t, p, cur) in obj_icur
        (haskey(tpos, t) && ((r, t, t, cur, "INV") in rt_ian || (r, p) in trackp)) && push!(rtp_ian, (r, t, p, cur))
    end
    # L55-58: the annual, undiscounted investment cost of a unit of capacity of vintage TT in the
    # milestone year T (YK1(TT,T): T at or after TT)
    #   CST_ANNC(R,TT,P,T(YEAR),'INVCOST',CUR)$(YK1(TT,T)$RTP_IAN(R,TT,P,CUR)) =
    #     SUM(OBJ_SUMII(R,TT,P,AGE,K_EOH(LL),JOT)$((ORD(LL)+ORD(AGE)+ORD(JOT)-1 > ORD(YEAR))$YK(T,LL)),
    #       SUM(INVSPRED(K_EOH,JOT,ALLYEAR,K)$((ORD(ALLYEAR)+ORD(AGE) > ORD(YEAR))$YK(T,ALLYEAR)),
    #         OBJ_ICOST(R,K,P,CUR)) * OBJ_CRF(R,TT,P,CUR) / OBJ_DIVI(R,TT,P));
    # K_EOH(LL) binds LL to the K_EOH index of OBJ_SUMII, and T(YEAR) binds YEAR to T.
    cst_annc = gvalues(tm, "CST_ANNC", 6)
    k_eoh, eachyear = S("K_EOH", 1), S("EACHYEAR", 1)
    sumii_of = indexby(S("OBJ_SUMII", 6), (1, 2, 3))                           # (r,v,p) -> OBJ_SUMII(r,v,p,age,k_eoh,jot)
    spred_of = indexby(S("INVSPRED", 4), (1, 2))                               # (k_eoh,jot) -> INVSPRED(k_eoh,jot,allyear,k)
    ob_icost, ob_itax, ob_isub, ob_dcc = P("OB_ICOST", 4), P("OB_ITAX", 4), P("OB_ISUB", 4), P("OB_DCC", 4)
    obj_crf, obj_divi = P("OBJ_CRF", 4), P("OBJ_DIVI", 3)
    for (r, tt, p, cur) in rtp_ian
        crf, divi = gv(obj_crf, (r, tt, p, cur)), gv(obj_divi, (r, tt, p))
        for t in tlist
            (tt, t) in yk1 || continue
            val = GZERO
            for (_, _, _, age, ll, jot) in get(sumii_of, (r, tt, p), NO6)
                ((ll,) in k_eoh && ord[ll] + aord[age] + aord[jot] - 1 > ord[t] && (t, ll) in yk) || continue
                s = GZERO
                for (_, _, a, k) in get(spred_of, (ll, jot), NO4)
                    ((k,) in eachyear && ord[a] + aord[age] > ord[t] && (t, a) in yk) || continue
                    s = s + obmac(ob_icost, r, k, p, cur)
                end
                val = val + s * crf / divi
            end
            gassign!(cst_annc, (r, tt, p, t, "INVCOST", cur), val)
        end
    end
    # L60-64: the decommissioning costs, added where the vintage has any (%DECLIF% is DELIF, eqobjinv.mod L24)
    #   LOOP(RTP_IAN(R,TT,P,CUR)$OBJ_DCOST(R,TT,P,CUR),
    #     CST_ANNC(R,TT,P,T(YEAR),'INVCOST',CUR)$YK1(TT,T) = CST_ANNC(R,TT,P,T,'INVCOST',CUR) +
    #       OBJ_CRFD(R,TT,P,CUR) / OBJ_DIVIII(R,TT,P) *
    #       SUM(OBJ_SUMIII(R,TT,P,K_EOH,K,LL)$((ORD(LL)+ROUND(NCAP_DELIF(R,TT,P)) > ORD(YEAR))$YK(T,LL)), OBJ_DCOST(R,K,P,CUR)));
    sumiii_of = indexby(S("OBJ_SUMIII", 6), (1, 2, 3))                         # (r,v,p) -> OBJ_SUMIII(r,v,p,k_eoh,k,ll)
    obj_crfd, obj_diviii, delif = P("OBJ_CRFD", 4), P("OBJ_DIVIII", 3), P("NCAP_DELIF", 3)
    for (r, tt, p, cur) in rtp_ian
        iszero(obmac(ob_dcc, r, tt, p, cur)) && continue
        ratio = gv(obj_crfd, (r, tt, p, cur)) / gv(obj_diviii, (r, tt, p))
        dl = glead(gv(delif, (r, tt, p)).v)
        for t in tlist
            (tt, t) in yk1 || continue
            s = GZERO
            for (_, _, _, ke, k, ll) in get(sumiii_of, (r, tt, p), NO6)
                ((ke,) in k_eoh && (k,) in eachyear && ord[ll] + dl > ord[t] && (t, ll) in yk) || continue
                s = s + obmac(ob_dcc, r, k, p, cur)
            end
            key = (r, tt, p, t, "INVCOST", cur)
            gassign!(cst_annc, key, gv(cst_annc, key) + ratio * s)
        end
    end
    # L66-67: OPTION CLEAR=TRACKP, CLEAR=RTP_IAN;
    #   LOOP(UC_ATTR(R,UC_N,SIDE,'NCAP',UC_ANNUL(UC_NAME(COSTCAT))),LOOP(T,TRACKP(R,P)$UC_NCAP(UC_N,SIDE,R,T,P)=YES));
    # the attribute is in UC_ANNUL, UC_NAME and COSTCAT at once: INVTAX or INVSUB.
    empty!(trackp); empty!(rtp_ian)
    uc_annul, uc_name = S("UC_ANNUL", 1), S("UC_NAME", 1)
    track!(Tuple(k[1] for k in costagg.keys if k in uc_annul && k in uc_name))
    # L68: RT_IAN(R,T,T,CUR,'INVTAXSUB')$(REG_CUMCST(R,T,T,'INVTAX',CUR,'UP')+REG_CUMCST(R,T,T,'INVSUB',CUR,'UP')) = YES
    for (r, y, ll, cat, cur, bd) in keys(cumcst)
        (cat in ("INVTAX", "INVSUB") && bd == "UP" && y == ll && haskey(tpos, y) && (r,) in reg) || continue
        iszero(gv(cumcst, (r, y, y, "INVTAX", cur, "UP")) + gv(cumcst, (r, y, y, "INVSUB", cur, "UP"))) ||
            push!(rt_ian, (r, y, y, cur, "INVTAXSUB"))
    end
    # L69: RTP_IAN(OBJ_ICUR(R,T,P,CUR))$(RT_IAN(R,T,T,CUR,'INVTAXSUB')+TRACKP(R,P)) = YES
    for (r, t, p, cur) in obj_icur
        (haskey(tpos, t) && ((r, t, t, cur, "INVTAXSUB") in rt_ian || (r, p) in trackp)) && push!(rtp_ian, (r, t, p, cur))
    end
    # L70-76: the annual investment taxes and subsidies (the subsidy stored with a minus sign)
    #   LOOP(RTP_IAN(R,TT,P,CUR)$(OBJ_ITAX(R,TT,P,CUR)+OBJ_ISUB(R,TT,P,CUR)),
    #     OPTION CLEAR=YKK; F = OBJ_CRF(R,TT,P,CUR)/OBJ_DIVI(R,TT,P);
    #     LOOP(OBJ_SUMII(R,TT,P,LIFE,K_EOH,JOT), Z=ORD(LIFE);
    #       YKK(YK(T(YEAR),LL),K)$((ORD(YEAR) < ORD(LL)+Z)$INVSPRED(K_EOH,JOT,LL,K)) = YES);
    #     CST_ANNC(R,TT,P,T,'INVTAX',CUR)$YK1(TT,T) = SUM(YKK(T,LL,K), F * OBJ_ITAX(R,K,P,CUR));
    #     CST_ANNC(R,TT,P,T,'INVSUB',CUR)$YK1(TT,T) = SUM(YKK(T,LL,K),-F * OBJ_ISUB(R,K,P,CUR)); );
    # YKK and the scalars F and Z stay as the last pass leaves them.
    ykk = gmembers(tm, "YKK", 3)
    passes = [k for k in rtp_ian if !iszero(obmac(ob_itax, k[1], k[2], k[3], k[4]) + obmac(ob_isub, k[1], k[2], k[3], k[4]))]
    gams_sort!(passes, d)
    for (r, tt, p, cur) in passes
        empty!(ykk)
        f = gv(obj_crf, (r, tt, p, cur)) / gv(obj_divi, (r, tt, p))
        gput_scalar!(tm, "F", f)
        for (_, _, _, life, ke, jot) in get(sumii_of, (r, tt, p), NO6)
            (ke,) in k_eoh || continue
            z = aord[life]
            gput_scalar!(tm, "Z", z)
            for (_, _, ll, k) in get(spred_of, (ke, jot), NO4), t in tlist
                ((k,) in eachyear && (t, ll) in yk && ord[t] < ord[ll] + z) && push!(ykk, (t, ll, k))
            end
        end
        members = gams_sort!(collect(ykk), d)
        for t in tlist
            (tt, t) in yk1 || continue
            tax, sub = GZERO, GZERO
            for (t2, _, k) in members
                t2 == t || continue
                tax = tax + f * obmac(ob_itax, r, k, p, cur)
                sub = sub + (-f) * obmac(ob_isub, r, k, p, cur)
            end
            gassign!(cst_annc, (r, tt, p, t, "INVTAX", cur), tax)
            gassign!(cst_annc, (r, tt, p, t, "INVSUB", cur), sub)
        end
    end
    # L77: OPTION CLEAR=TRACKP, CLEAR=RTP_IAN
    gput!(tm, "RT_IAN", rt_ian); gput!(tm, "RTP_IAN", Set{NTuple{4,String}}())
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    gput!(tm, "CST_ANNC", cst_annc); gput!(tm, "YKK", ykk)

    # eqmain.mod L199-202: RVPT, RTP_OFF
    B, E = P("B", 1), P("E", 1)
    iled = P("NCAP_ILED", 3)
    rtp_off = gmembers(tm, "RTP_OFF", 3)
    vnt_of = indexby(S("VNT", 2), (1,))
    rvpt = Set{NTuple{4,String}}()
    obj_2a = collect(S("OBJ_2A", 3).keys)
    for (r, t, p) in obj_2a
        (haskey(tpos, t) && !((r, t, p) in rtp_off)) || continue
        f = gv(B, (t,)).v + gv(iled, (r, t, p)).v
        z = count(((_, tt),) -> haskey(tpos, tt) && f > gv(E, (tt,)).v + 0.5, get(vnt_of, (t,), NTuple{2,String}[]))
        gput_scalar!(tm, "F", f); gput_scalar!(tm, "Z", z)                     # scratch, as the last pass leaves it
        j = tpos[t] + z
        j <= length(tlist) && push!(rvpt, (r, t, p, tlist[j]))
    end
    has_rvpt = Set((k[1], k[2], k[3]) for k in rvpt)
    for (r, t, p) in obj_2a
        (haskey(tpos, t) && !((r, t, p) in has_rvpt)) && push!(rtp_off, (r, t, p))
    end
    gput!(tm, "RVPT", rvpt); gput!(tm, "RTP_OFF", rtp_off)

    # eqmain.mod L211-226: the user-constraint maps
    delete!(tm.cache, "UC_SETUP"); delete!(tm.cache, "UC_TMAP"); delete!(tm.cache, "UC_TMAP/t")
    gput!(tm, "UC_TMAP", Set(uc_tmap(tm).keys))
    setup = uc_setup(tm)
    gput!(tm, "UC_RHSMAP", Set(setup.rhsmap.keys)); gput!(tm, "UC_RTSUC", Set(setup.rtsuc.keys))
    gput!(tm, "UC_UT", Set(setup.ut.keys)); gput!(tm, "UC_UTS", Set(setup.uts.keys))
    gput!(tm, "UC_RHSTMP", Set{NTuple{5,String}}()); gput!(tm, "RUCTS", Set{NTuple{4,String}}())
    if !isempty(P("UC_RHSRT", 4))                                           # L219, inside the IF
        gput!(tm, "R_UC", Set{NTuple{2,String}}()); gput!(tm, "R_UCT", Set{NTuple{3,String}}())
    end

    # equ_ext.vda L77, L79
    pace = Set((k[1], k[2]) for k in S("RPG_PACE", 3))
    rp_pl = filter(k -> !((k[1], k[2]) in pace), gmembers(tm, "RP_PL", 3))
    gput!(tm, "RP_PL", rp_pl)
    afcs, rtp = P("NCAP_AFCS", 5), S("RTP", 3)
    filter!(k -> !(k[5] in ("UP", "FX") && (k[1], k[2], k[3]) in rtp && haskey(afcs, (k[1], k[2], k[3], "ACT", k[4]))), afs)
    # eqactups.vda L9-32 (equ_ext.vda L90): the dispatching preparation; L11 takes its entries out of AFS
    eqactups_prep!(tm, afs)
    gput!(tm, "AFS", afs)
    # eqactups.vda L33, outside the dispatching IF of L9-32: OPTION RP_UPR < ACT_CSTRMP
    gput!(tm, "RP_UPR", Set((k[1], k[3], k[4]) for k in P("ACT_CSTRMP", 5).keys))
    # eqlducs.vda L46-51 (equ_ext.vda L91): the unit-commitment processes leave the linear dispatching sets
    eqlducs_equ!(tm)
    return tm
end
