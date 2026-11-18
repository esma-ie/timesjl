# M1.3 change 47: the VDA "betting" user constraints, ucbet.vda (v4.9.7), included from
# equ_ext.vda L99 as `$IF DEFINED UC_FLOBET $BATINCLUDE UCBET.%1` and put in the model by
# mod_ext.vda L39-40 (EQG_UCMAX, EQG_UCSUMAX).
#
# UC_FLOBET(UC_N,R,T,P,C) weights the cumulative flow of commodity C (or, with C = %PGPRIM%, the
# activity) of process P; init_ext.vda L132 copies UC_ACTBET into it with C = %PGPRIM%
# (`init_ext!`), and prep_ext.vda L35 interpolates it over T (`prep_ext!`). For each user constraint
# UC_N with such weights, the constraint's variable is at least each weighted cumulative flow or
# activity, so its bound (bnd_ucw.mod) limits the largest of them.
#
# `$IF DEFINED UC_FLOBET` is a compile-time test (G35, G40): true when UC_FLOBET has a data
# statement, or when UC_ACTBET does (init_ext.vda L131-132 then compiles an assignment to
# UC_FLOBET). It is taken here as "UC_FLOBET has records after init_ext and prep_ext"
# (`ucbet_included`). The two differ only for a UC_FLOBET or UC_ACTBET DEFINED with no records,
# and then ucbet.vda has no effect: UNCD1 stays empty (L18), so L20 and L40 change nothing; L19's
# UC_GMAXR entries are all removed again by L37, RXX being empty; and there is no UC_GMAX entry, so
# no row. Only the scratch sets UNCD1 and RXX would differ (cleared), and neither is read before
# the next statement that clears it.

"%PGPRIM% as initmty.mod L138 leaves it (default 'ACT'), as the label GAMS stores."
function _ucbet_pgprim(tm)
    pg = uppercase(strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"']))
    i = findfirst(k -> uppercase(k[1]) == pg, gset(tm, "COM").keys)
    return i === nothing ? pg : gset(tm, "COM").keys[i][1]
end

"""
    ucbet_included(tm) -> Bool

Whether equ_ext.vda L99 includes ucbet.vda (`\$IF DEFINED UC_FLOBET`), read as UC_FLOBET
having records (see the note at the top of this file).

GAMS: equ_ext.vda L99, mod_ext.vda L39, v4.9.7.
"""
ucbet_included(tm) = hasdata(tm, "UC_FLOBET", 5)

"The sets ucbet.vda L13-40 settles, compared after `eqmain_prep!` when it is included."
ucbet_symbols(tm) = ucbet_included(tm) ? ["UNCD1", "UC_R_SUM", "UC_GMAX", "UC_GMAXR", "RXX", "UC_TS_SUM"] : String[]

"""
    ucbet_prep!(tm) -> tm

The preparation part of ucbet.vda, run after eqlducs.vda (equ_ext.vda L91) and before the
bounds (bndmain.mod, maindrv.mod L80-93):

    SET UC_GMAX(UC_N,ALL_R,ITEM,C,ITEM); SET UC_GMAXR(ALL_R,UC_N);
    OPTION CLEAR=UNCD1;
    LOOP((UC_N,R,T,P,C)\$UC_FLOBET(UC_N,R,T,P,C),UNCD1(UC_N)=YES);                (L17-18)
    UC_GMAXR(UC_R_EACH) = YES;                                                    (L19)
    UC_R_SUM(R,UC_N(UNCD1)) = YES;                                                (L20)
    LOOP((UC_N,R,T,P,C)\$UC_FLOBET(UC_N,R,T,P,C),
     IF(SAMEAS(%PGPRIM%,C),
       IF(UC_ATTR(R,UC_N,'LHS','ACT','N'), UC_GMAX(UC_N,'IMPEXP',P,C,'EACH') = YES;
       ELSE UC_GMAX(UC_N,R,P,C,'EACH') = YES);
     ELSE
       IF(UC_GMAXR(R,UC_N), UC_GMAX(UC_N,R,'N',C,'N') = YES;
       ELSE UC_GMAX(UC_N,'IMPEXP','N',C,'N') = YES)));                             (L23-31)
    LOOP(R,UC_GMAXR('IMPEXP',UC_N)\$UC_GMAXR(R,UC_N) = YES);                       (L34)
    OPTION CLEAR=RXX;
    LOOP(UC_GMAX(UC_N,ALL_R,ITEM,C,NAME),RXX('IMPEXP',UC_N,ALL_R) = YES);          (L36-37)
    UC_GMAXR(ALL_R,UC_N)\$(NOT RXX('IMPEXP',UC_N,ALL_R)) = NO;                      (L38)
    UC_TS_SUM(R,UC_N(UNCD1),S) = NO;                                              (L40)

The LOOPs run over the domain sets (UC_N, R = REG, T = MILESTONYR, P = PRC, C = COM, which
holds %PGPRIM%: initmty.mod L141), so a UC_FLOBET record outside them is skipped; an EPS weight
counts as present. The UC_GMAXR test of L28 sees L19's entries only. L40 takes the constraints
out of the core user-constraint equations (equcwrap.mod L22-40 need UC_TS_SUM), which run at the
SOLVE, after this; UC_RHSMAP and the other maps of eqmain.mod L211-226 were built before it
(`uc_setup`).

GAMS: ucbet.vda L11-40, v4.9.7.
"""
function ucbet_prep!(tm::TimesModel)
    ucbet_included(tm) || return tm
    flobet = gparam(tm, "UC_FLOBET")
    ucn, reg, milestonyr = gset(tm, "UC_N"), gset(tm, "REG"), gset(tm, "MILESTONYR")
    prc, com, uc_attr = gset(tm, "PRC"), gset(tm, "COM"), gset(tm, "UC_ATTR")
    pg = _ucbet_pgprim(tm)
    loop = [k for k in flobet.keys if (k[1],) in ucn && (k[2],) in reg && (k[3],) in milestonyr &&
                                      (k[4],) in prc && (k[5],) in com]
    uncd1 = Set{NTuple{1,String}}((k[1],) for k in loop)                                   # L18
    gmaxr = Set{NTuple{2,String}}(gset(tm, "UC_R_EACH").keys)                              # L19
    r_sum = Set{NTuple{2,String}}(gset(tm, "UC_R_SUM").keys)
    for (r,) in reg, (n,) in uncd1                                                         # L20
        push!(r_sum, (r, n))
    end
    gmax = Set{NTuple{5,String}}()
    for (n, r, _, p, c) in loop                                                            # L23-31
        if c == pg
            push!(gmax, (r, n, "LHS", "ACT", "N") in uc_attr ? (n, "IMPEXP", p, c, "EACH") : (n, r, p, c, "EACH"))
        else
            push!(gmax, (r, n) in gmaxr ? (n, r, "N", c, "N") : (n, "IMPEXP", "N", c, "N"))
        end
    end
    for (r, n) in collect(gmaxr)                                                           # L34
        (r,) in reg && push!(gmaxr, ("IMPEXP", n))
    end
    rxx = Set{NTuple{3,String}}(("IMPEXP", k[1], k[2]) for k in gmax)                       # L36-37
    filter!(k -> ("IMPEXP", k[2], k[1]) in rxx, gmaxr)                                     # L38
    ts_sum = filter(k -> !((k[1],) in reg && (k[2],) in uncd1), Set(gset(tm, "UC_TS_SUM").keys))   # L40
    gput!(tm, "UNCD1", uncd1); gput!(tm, "UC_R_SUM", r_sum); gput!(tm, "UC_GMAX", gmax)
    gput!(tm, "UC_GMAXR", gmaxr); gput!(tm, "RXX", rxx); gput!(tm, "UC_TS_SUM", ts_sum)
    return tm
end

"""
    eq_ucbet!(tm) -> Int

Generate every EQG_UCMAX and EQG_UCSUMAX row (ucbet.vda L46-125; the model has them when
UC_FLOBET is DEFINED, mod_ext.vda L39-40). Returns the number of rows.

    EQG_UCMAX(UC_GMAX(UC_N,ALL_R,ITEM,C,NAME)) ..
      VAR_UC(UC_N)\$(NOT UC_GMAXR(ALL_R,UC_N)) + SUM(R(ALL_R),VAR_UCR(UC_N,R)\$UC_GMAXR(ALL_R,UC_N))
      =G=
      SUM(UC_T_SUM(UC_GMAXR(R(ALL_R),UC_N),T), M(R,T) * [FLOWS])\$LIM(NAME) +                 (L57-71)
      SUM(UC_T_SUM(R,UC_N,T)\$(NOT UC_GMAXR(R,UC_N)), M(R,T) * [FLOWS])\$((NOT REG(ALL_R))\$LIM(NAME)) +   (L73-87)
      SUM(UC_T_SUM(R(ALL_R),UC_N,T), M(R,T) * [ACTIVITY])\$UC_NUMBER(NAME) +                    (L89-103)
      SUM(UC_T_SUM(R,UC_N,T)\$(NOT REG(ALL_R)), M(R,T) * [ACTIVITY])\$((NOT REG(ALL_R))\$UC_NUMBER(NAME));   (L105-119)

    M(R,T) = FPD(T)+(COEF_PVT(R,T)-FPD(T))\$UC_ATTR(R,UC_N,'LHS','ACT','PERDISC')
    [FLOWS] = SUM(RTPCS_VARF(R,T,P,COM,S)\$(COM_GMAP(R,C,COM)\$UC_FLOBET(UC_N,R,T,P,C)),
                UC_FLOBET(UC_N,R,T,P,C) * SUM(RTP_VINTYR(R,V,T,P),
                  ([cal_red COM COM1 S P T])\$RP_STD(R,P) +
                  SUM(RPC_IRE(R,P,COM,IE('IMP')),
                    VAR_IRE(R,V,T,P,COM,S,IE)\$(NOT RPC_AIRE(R,P,COM)) +
                    (VAR_ACT(R,V,T,P,S)*PRC_ACTFLO(R,V,P,COM))\$RPC_AIRE(R,P,COM))\$RP_IRE(R,P)))
    [ACTIVITY] = SUM(RTP_VINTYR(R,V,T,P(ITEM))\$UC_FLOBET(UC_N,R,T,P,%PGPRIM%),
                   UC_FLOBET(UC_N,R,T,P,%PGPRIM%) *
                   (SUM((RTP_VARA(R,T,P),PRC_TS(R,P,S)), VAR_ACT(R,V,T,P,S))\$RP_STD(R,P) +
                    SUM((RPC_IRE(R,P,COM,IE('IMP')),RTPCS_VARF(R,T,P,COM,S)),
                      VAR_IRE(R,V,T,P,COM,S,IE)\$(NOT RPC_AIRE(R,P,COM)) +
                      (VAR_ACT(R,V,T,P,S)*PRC_ACTFLO(R,V,P,COM))\$RPC_AIRE(R,P,COM))\$RP_IRE(R,P)))

    EQG_UCSUMAX(UC_N)\$SUM(UC_GMAXR(ALL_R,UC_N),1) ..
      VAR_UC(UC_N) =G= SUM(UC_GMAXR(R,UC_N),VAR_UCR(UC_N,R));                                  (L123-125)

The flow branches sum over every process P with a weight on C (P is free there; ITEM is 'N'),
the activity branches over P = ITEM. The regional activity branch (L89) has no UC_GMAXR test.
NAME is 'N' (in LIM) for a flow entry and 'EACH' (in UC_NUMBER) for an activity entry (L25-31).
In the flow branches V comes from RTP_VINTYR inside the RTPCS_VARF sum, and the %cal_red% term
is the general case (%7 empty: vintage V). PERDISC is read under the group 'ACT' for flows and
activities alike. Under %STAGES% (not translated) the sums would run over SW_TSW.

GAMS: ucbet.vda L46-125, v4.9.7.
"""
function eq_ucbet!(tm::TimesModel)
    ucbet_included(tm) || return 0
    flobet = gparam(tm, "UC_FLOBET")
    gmax, gmaxr = gset(tm, "UC_GMAX"), gset(tm, "UC_GMAXR")
    reg, lim, uc_number = gset(tm, "REG"), gset(tm, "LIM"), gset(tm, "UC_NUMBER")
    uc_attr, fpd, coef_pvt = gset(tm, "UC_ATTR"), gparam(tm, "FPD"), gparam(tm, "COEF_PVT")
    rp_std, rp_ire, rpc_aire = gset(tm, "RP_STD"), gset(tm, "RP_IRE"), gset(tm, "RPC_AIRE")
    rtp_vara, com_gmap, prc_actflo = gset(tm, "RTP_VARA"), gset(tm, "COM_GMAP"), gparam(tm, "PRC_ACTFLO")
    pg = _ucbet_pgprim(tm)
    tsum_of_rn = indexby(gset(tm, "UC_T_SUM"), (1, 2))         # (r,n) -> UC_T_SUM(r,n,t)
    tsum_of_n = indexby(gset(tm, "UC_T_SUM"), (2,))            # n -> UC_T_SUM(r,n,t)
    varf_of_rtp = indexby(gset(tm, "RTPCS_VARF"), (1, 2, 3))   # (r,t,p) -> RTPCS_VARF(r,t,p,com,s)
    v_of_rtp = indexby(gset(tm, "RTP_VINTYR"), (1, 3, 4))      # (r,t,p) -> RTP_VINTYR(r,v,t,p)
    ts_of_rp = indexby(gset(tm, "PRC_TS"), (1, 2))             # (r,p) -> PRC_TS(r,p,s)
    imp_of_rp = Dict{NTuple{2,String},Vector{NTuple{4,String}}}()   # (r,p) -> RPC_IRE(r,p,com,'IMP')
    for k in gset(tm, "RPC_IRE").keys
        k[4] == "IMP" && push!(get!(() -> NTuple{4,String}[], imp_of_rp, (k[1], k[2])), k)
    end
    flo_of_nrtc = Dict{NTuple{4,String},Vector{String}}()      # (n,r,t,c) -> P with UC_FLOBET(n,r,t,p,c)
    for k in flobet.keys
        push!(get!(() -> String[], flo_of_nrtc, (k[1], k[2], k[3], k[5])), k[4])
    end
    no3, no4, no5 = NTuple{3,String}[], NTuple{4,String}[], NTuple{5,String}[]
    mult(n, r, t) = (f = gv(fpd, (t,)); f + gif(gv(coef_pvt, (r, t)) - f, (r, n, "LHS", "ACT", "PERDISC") in uc_attr))

    # VAR_IRE(R,V,T,P,COM,S,'IMP')$(NOT RPC_AIRE(R,P,COM)) + (VAR_ACT(R,V,T,P,S)*PRC_ACTFLO(R,V,P,COM))$RPC_AIRE(R,P,COM)
    function imports!(e, w, r, v, t, p, com, s)
        if (r, p, com) in rpc_aire
            addterm!(e, w * gv(prc_actflo, (r, v, p, com)), tm, "VAR_ACT", r, v, t, p, s)
        else
            addterm!(e, w, tm, "VAR_IRE", r, v, t, p, com, s, "IMP")
        end
    end
    # M(R,T) * [FLOWS] for one (R,T)
    function flows!(e, n, r, t, c)
        m = mult(n, r, t)
        for p in get(flo_of_nrtc, (n, r, t, c), String[])
            w = m * gv(flobet, (n, r, t, p, c))
            for (_, _, _, com, s) in get(varf_of_rtp, (r, t, p), no5)
                (r, c, com) in com_gmap || continue
                for (_, v, _, _) in get(v_of_rtp, (r, t, p), no4)
                    (r, p) in rp_std && cal_nored!(e, tm, w, r, v, t, p, com, s)
                    if (r, p) in rp_ire
                        for (_, _, cm, _) in get(imp_of_rp, (r, p), no4)
                            cm == com && imports!(e, w, r, v, t, p, com, s)
                        end
                    end
                end
            end
        end
    end
    # M(R,T) * [ACTIVITY] for one (R,T), P = ITEM
    function activity!(e, n, r, t, p)
        haskey(flobet, (n, r, t, p, pg)) || return
        w = mult(n, r, t) * gv(flobet, (n, r, t, p, pg))
        for (_, v, _, _) in get(v_of_rtp, (r, t, p), no4)
            if (r, p) in rp_std && (r, t, p) in rtp_vara
                for (_, _, s) in get(ts_of_rp, (r, p), no3)
                    addterm!(e, w, tm, "VAR_ACT", r, v, t, p, s)
                end
            end
            if (r, p) in rp_ire
                for (_, _, com, _) in get(imp_of_rp, (r, p), no4)
                    for (_, _, _, cm, s) in get(varf_of_rtp, (r, t, p), no5)
                        cm == com && imports!(e, w, r, v, t, p, com, s)
                    end
                end
            end
        end
    end

    nrows = 0
    for (n, allr, item, c, name) in gmax.keys
        lhs = JuMP.AffExpr(0.0)
        ingmaxr = (allr, n) in gmaxr
        ingmaxr || addterm!(lhs, GNum(1.0), tm, "VAR_UC", n)
        ((allr,) in reg && ingmaxr) && addterm!(lhs, GNum(1.0), tm, "VAR_UCR", n, allr)
        rhs = JuMP.AffExpr(0.0)
        isreg = (allr,) in reg
        if (name,) in lim
            if isreg && ingmaxr                                                  # L57-71
                for (_, _, t) in get(tsum_of_rn, (allr, n), no3)
                    flows!(rhs, n, allr, t, c)
                end
            end
            if !isreg                                                            # L73-87
                for (r, _, t) in get(tsum_of_n, (n,), no3)
                    (r, n) in gmaxr || flows!(rhs, n, r, t, c)
                end
            end
        end
        if (name,) in uc_number
            if isreg                                                             # L89-103
                for (_, _, t) in get(tsum_of_rn, (allr, n), no3)
                    activity!(rhs, n, allr, t, item)
                end
            else                                                                 # L105-119
                for (r, _, t) in get(tsum_of_n, (n,), no3)
                    activity!(rhs, n, r, t, item)
                end
            end
        end
        gconstraint!(tm, "EQG_UCMAX", (n, allr, item, c, name), "G", lhs, rhs) === nothing || (nrows += 1)
    end
    # L123-125
    sumax = unique(k[2] for k in gmaxr.keys)
    for n in sort!(sumax; by = x -> findfirst(k -> k[1] == x, gset(tm, "UC_N").keys))
        lhs = JuMP.AffExpr(0.0); addterm!(lhs, GNum(1.0), tm, "VAR_UC", n)
        rhs = JuMP.AffExpr(0.0)
        for (r, m) in gmaxr.keys
            (m == n && (r,) in reg) && addterm!(rhs, GNum(1.0), tm, "VAR_UCR", n, r)
        end
        gconstraint!(tm, "EQG_UCSUMAX", (n,), "G", lhs, rhs) === nothing || (nrows += 1)
    end
    return nrows
end
