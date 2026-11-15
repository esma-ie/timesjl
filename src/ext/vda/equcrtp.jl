# M1.3 (1): dynamic process bounds, the INIT_EXT part. User constraints
# listed in UC_DYNBND become annual bounds on a process's development:
# their UC_CAP/UC_NCAP/UC_ACT coefficients move to PRC_DYNUC, their
# UC_COMNET/UC_COMPRD ones to UC_COM at ANNUAL, and missing LHS/RHS
# defaults are filled in.
#
# GAMS: equcrtp.vda L15-38 (the INIT_EXT label), v4.9.7, included from
# init_ext.vda L128 as `$BATINCLUDE equcrtp.vda INIT_EXT`; L40-62 (PREP_EXT,
# M1.3 change 6b), included from prep_ext.vda L39; L73-121 (EQU_EXT, M1.3
# change 20), at the end of this file. The PPM_EXT label (L64-71) is
# ppm_ext.jl (change 18b).
#
# Index sets: UCN is UC_N, R is REG (UC_CAP etc. are over ALL_REG, so R
# filters), C is COM, '0' is LL--ORD(LL), the last ALLYEAR element (G31).
# Every statement reads the values from before it (G11).

"""
    equcrtp_init_ext!(tm) -> tm

equcrtp.vda INIT_EXT on the GAMS state in `tm`: nothing unless UC_DYNBND has
members (L17).

GAMS: equcrtp.vda L15-38, v4.9.7.
"""
function equcrtp_init_ext!(tm)
    dyn = gset_opt(tm.data, "UC_DYNBND", 2)
    isempty(dyn) && return tm                                          # L17: IF(CARD(UC_DYNBND), ...)
    reg = gset(tm, "REG")
    inR(r) = (r,) in reg
    t0 = last(gset(tm, "ALLYEAR").keys)[1]                             # LL--ORD(LL) (G31)
    # L17: OPTION CLEAR=UNCD1; LOOP(UC_DYNBND(UCN,BD),UNCD1(UCN)=YES)
    uncd1 = Set{NTuple{1,String}}((k[1],) for k in dyn.keys)
    gput!(tm, "UNCD1", uncd1)
    bds = Dict{String,Vector{String}}()
    for (u, bd) in dyn.keys
        push!(get!(bds, u, String[]), bd)
    end
    inU(u) = (u,) in uncd1

    # L18-20: PRC_DYNUC(UC_N,SIDE,R,LL,P,'CAP'|'NCAP'|'ACT',BD)$UC_DYNBND(UC_N,BD) $= UC_CAP|UC_NCAP|UC_ACT(...,'ANNUAL')
    dynuc = gvalues(tm, "PRC_DYNUC", 7)
    for (name, gt) in (("UC_CAP", "CAP"), ("UC_NCAP", "NCAP"))
        p = gparam_opt(tm.data, name, 5)
        for (k, _) in p.values
            (u, side, r, y, prc) = k
            inR(r) || continue
            for bd in get(bds, u, String[])
                gassign!(dynuc, (u, side, r, y, prc, gt, bd), gv(p, k))
            end
        end
    end
    uc_act = gparam_opt(tm.data, "UC_ACT", 6)
    for (k, _) in uc_act.values
        (u, side, r, y, prc, s) = k
        (s == "ANNUAL" && inR(r)) || continue
        for bd in get(bds, u, String[])
            gassign!(dynuc, (u, side, r, y, prc, "ACT", bd), gv(uc_act, k))
        end
    end
    gput!(tm, "PRC_DYNUC", dynuc)

    # L21-22: UC_COM(UC_N(UNCD1),'NET'|'PRD',SIDE,R,LL,C,ANNUAL(S),'UCN') $= UC_COMNET|UC_COMPRD(UC_N,SIDE,R,LL,C,S)
    annual = gset(tm, "ANNUAL")
    uccom = gvalues(tm, "UC_COM", 8)
    for (name, cv) in (("UC_COMNET", "NET"), ("UC_COMPRD", "PRD"))
        p = gparam_opt(tm.data, name, 6)
        for (k, _) in p.values
            (u, side, r, y, c, s) = k
            (inU(u) && inR(r) && (s,) in annual) || continue
            gassign!(uccom, (u, cv, side, r, y, c, s, "UCN"), gv(p, k))
        end
    end

    # L23-27: UC_CAP/UC_NCAP/UC_ACT/UC_COMPRD/UC_COMNET(UC_N(UNCD1),SIDE,R,...) = 0
    for (name, N) in (("UC_CAP", 5), ("UC_NCAP", 5), ("UC_ACT", 6), ("UC_COMPRD", 6), ("UC_COMNET", 6))
        p = gparam_opt(tm.data, name, N)
        isempty(p) && continue
        gput!(tm, name, Dict{NTuple{N,String},Float64}(k => v for (k, v) in p.values if !(inU(k[1]) && inR(k[3]))))
    end

    lhs0(k) = (k[1], k[2], "LHS", k[4], t0, k[6], k[7], k[8])
    rhs0(k) = (k[1], k[2], "RHS", k[4], t0, k[6], k[7], k[8])
    ucn(k) = k[8] == "UCN" && inR(k[4])
    lastll = gset(tm, "LASTLL")
    miyr_1 = gset(tm, "MIYR_1")
    # L29: UC_COM(UCN(UNCD1),COM_VAR,'LHS',R,LL--ORD(LL),C,S,'UCN')$((NOT UC_COM(..'LHS',R,'0',..))$UC_COM(..'LHS',R,LL,..)) = 5
    old = copy(uccom)
    for k in keys(old)
        (inU(k[1]) && k[3] == "LHS" && ucn(k) && !haskey(old, lhs0(k))) && gassign!(uccom, lhs0(k), 5.0)
    end
    # L30-31: UC_COM(UCN(UNCD1),COM_VAR,'RHS',R,LL--ORD(LL),C,S,'UCN')$((NOT UC_COM(..'RHS',R,'0',..))$UC_COM(..'RHS',R,LL,..)) =
    #           UC_COM(..'LHS',R,'0',..)+10$(NOT UC_COM(..'LHS',R,'0',..))
    old = copy(uccom)
    for k in keys(old)
        (inU(k[1]) && k[3] == "RHS" && ucn(k) && !haskey(old, rhs0(k))) || continue
        gassign!(uccom, rhs0(k), gv(old, lhs0(k)) + gif(10, !haskey(old, lhs0(k))))
    end
    # L33-34: UC_COM(UCN,COM_VAR,'RHS',R,LL,C,S,'UCN')$((NOT UC_COM(..'RHS',R,'0',..))$UC_COM(..'LHS',R,LL,..)) =
    #           EPS$(NOT MIYR_1(LL))+UC_COM(..'LHS',R,LL,..)$LASTLL(LL)        (every UCN, not only UNCD1)
    old = copy(uccom)
    for k in keys(old)
        (k[3] == "LHS" && ucn(k) && !haskey(old, rhs0(k))) || continue
        y = k[5]
        gassign!(uccom, (k[1], k[2], "RHS", k[4], y, k[6], k[7], k[8]),
                 gif(GEPS, !((y,) in miyr_1)) + gif(gv(old, k), (y,) in lastll))
    end
    # L35-36: UC_COM(UCN,COM_VAR,'LHS',R,LL,C,S,'UCN')$((NOT UC_COM(..'LHS',R,'0',..))$UC_COM(..'RHS',R,LL,..)) =
    #           (1+(UC_COM(..'RHS',R,LL,..)-1)$LASTLL(LL))
    old = copy(uccom)
    one = GNum(1)
    for k in keys(old)
        (k[3] == "RHS" && ucn(k) && !haskey(old, lhs0(k))) || continue
        y = k[5]
        gassign!(uccom, (k[1], k[2], "LHS", k[4], y, k[6], k[7], k[8]), one + gif(gv(old, k) - one, (y,) in lastll))
    end
    gput!(tm, "UC_COM", uccom)
    return tm
end

"""
    equcrtp_prep_ext!(st) -> st

equcrtp.vda PREP_EXT on the state of `st.tm`: the default options of the
dynamic process bounds (LHS 5, RHS 10 or the LHS option), the missing side
filled in (RHS EPS, LHS 1, the last year's value at LASTLL), PRC_DYNUC
inter-/extrapolated by prepparm.gms with %RESET% 1, the growth equation of a
process's first period of availability dropped when no constant is given,
and the maps UC_GMAP_P, UC_JMAP and UC_T_SUCC.

GAMS: equcrtp.vda L40-62, v4.9.7.
"""
function equcrtp_prep_ext!(st)
    tm = st.tm
    t0 = last(gset(tm, "ALLYEAR").keys)[1]                            # LL--ORD(LL) (G31)
    reg = [k[1] for k in gset(tm, "REG").keys]
    dynuc = gvalues(tm, "PRC_DYNUC", 7)
    if !isempty(dynuc)                                                # L41: IF(CARD(PRC_DYNUC), ...)
        lastll = gset(tm, "LASTLL").members
        lhs0(k) = (k[1], "LHS", k[3], t0, k[5], k[6], k[7])
        rhs0(k) = (k[1], "RHS", k[3], t0, k[5], k[6], k[7])
        # L43: PRC_DYNUC(UC_N,'LHS',R,LL--ORD(LL),P,G,BD)$((NOT PRC_DYNUC(UC_N,'LHS',R,'0',P,G,BD))$PRC_DYNUC(UC_N,'LHS',R,LL,P,G,BD))=5
        old = copy(dynuc)
        for k in keys(old)
            (k[2] == "LHS" && !haskey(old, lhs0(k))) && gassign!(dynuc, lhs0(k), 5.0)
        end
        # L44-45: PRC_DYNUC(UC_N,'RHS',R,LL--ORD(LL),P,G,BD)$((NOT ..'RHS',R,'0'..)$PRC_DYNUC(UC_N,'RHS',R,LL,P,G,BD)) =
        #           PRC_DYNUC(UC_N,'LHS',R,'0',P,G,BD)+10$(NOT PRC_DYNUC(UC_N,'LHS',R,'0',P,G,BD))
        old = copy(dynuc)
        for k in keys(old)
            (k[2] == "RHS" && !haskey(old, rhs0(k))) || continue
            gassign!(dynuc, rhs0(k), gv(old, lhs0(k)) + gif(10, !haskey(old, lhs0(k))))
        end
        # L46: LOOP(BD, UC_GMAP_P(R,UC_N,G,P)$PRC_DYNUC(UC_N,'RHS',R,'0',P,G,BD) = YES)
        gmap_p = gmembers(tm, "UC_GMAP_P", 4)
        for k in keys(dynuc)
            (k[2] == "RHS" && k[4] == t0) && push!(gmap_p, (k[3], k[1], k[6], k[5]))
        end
        gput!(tm, "UC_GMAP_P", gmap_p)
        # L48-49: PRC_DYNUC(UC_N,'RHS',R,LL,P,G,BD)$((NOT ..'RHS',R,'0'..)$PRC_DYNUC(UC_N,'LHS',R,LL,P,G,BD)) =
        #           EPS+PRC_DYNUC(UC_N,'LHS',R,LL,P,G,BD)$LASTLL(LL)
        old = copy(dynuc)
        for k in keys(old)
            (k[2] == "LHS" && !haskey(old, rhs0(k))) || continue
            gassign!(dynuc, (k[1], "RHS", k[3], k[4], k[5], k[6], k[7]), GEPS + gif(gv(old, k), (k[4],) in lastll))
        end
        # L51-52: PRC_DYNUC(UC_N,'LHS',R,LL,P,G,BD)$((NOT ..'LHS',R,'0'..)$PRC_DYNUC(UC_N,'RHS',R,LL,P,G,BD)) =
        #           (1+(PRC_DYNUC(UC_N,'RHS',R,LL,P,G,BD)-1)$LASTLL(LL))$(NOT SAMEAS('NCAP',G))
        old = copy(dynuc)
        one = GNum(1.0)
        for k in keys(old)
            (k[2] == "RHS" && !haskey(old, lhs0(k))) || continue
            x = (one + gif(gv(old, k) - one, (k[4],) in lastll)) * gif(1, k[6] != "NCAP")
            gassign!(dynuc, (k[1], "LHS", k[3], k[4], k[5], k[6], k[7]), x)
        end
        gput!(tm, "PRC_DYNUC", dynuc)
        # L54-55: $SET RESET 1; $BATINCLUDE prepparm PRC_DYNUC 'UC_N,SIDE,R' 'P,UC_GRPTYPE,BD' "" T 1 1
        T = [k[1] for k in gset(tm, "MILESTONYR").keys]
        reset = st.reset
        st.reset = 1.0
        prepparm!(st, "PRC_DYNUC", "UC_N,SIDE,R", "P,UC_GRPTYPE,BD", pd(""), T, k -> true, GNum(1.0))
        st.reset = reset
        dynuc = gvalues(tm, "PRC_DYNUC", 7)
        # L57: PRC_DYNUC(UCN,RHS,RTP(R,TT(T+1),P),G,BD)$((RTP(R,T,P)->MIYR_1(TT))$(NOT UC_GMAP_P(R,UCN,G,P))
        #        $PRC_DYNUC(UCN,'LHS',R,'0',P,G,BD)) = 0
        rhs = Set(k[1] for k in gset(tm, "RHS").keys)
        rtp = gset(tm, "RTP").members
        miyr_1 = gset(tm, "MIYR_1").members
        prev = Dict(T[i+1] => T[i] for i in 1:length(T)-1)
        for k in collect(keys(dynuc))
            (k[2] in rhs && haskey(prev, k[4]) && (k[3], k[4], k[5]) in rtp) || continue
            imp = !((k[3], prev[k[4]], k[5]) in rtp) || (k[4],) in miyr_1
            (imp && !((k[3], k[1], k[6], k[5]) in gmap_p) && haskey(dynuc, lhs0(k))) && delete!(dynuc, k)
        end
        gput!(tm, "PRC_DYNUC", dynuc)
        # L59: LOOP(BD,UC_JMAP('1',UCN,RHS,R,T(MIYR_1),P,G)$PRC_DYNUC(UCN,RHS,R,'0',P,G,BD) = YES)
        register_uel!(tm.data, "1")
        jmap = gmembers(tm, "UC_JMAP", 7)
        t1 = [t for t in T if (t,) in miyr_1]
        for k in keys(dynuc), t in t1
            (k[2] in rhs && k[4] == t0) && push!(jmap, ("1", k[1], k[2], k[3], t, k[5], k[6]))
        end
        gput!(tm, "UC_JMAP", jmap)
    end
    # L61: LOOP(UC_DYNBND(UCN,BD),UC_T_SUCC(R,UCN,'0') = YES)
    dyn = gset_opt(tm.data, "UC_DYNBND", 2)
    if !isempty(dyn)
        succ = gmembers(tm, "UC_T_SUCC", 3)
        for (u, _) in dyn.keys, r in reg
            push!(succ, (r, u, t0))
        end
        gput!(tm, "UC_T_SUCC", succ)
    end
    return st
end

# M1.3 (20): the EQU_EXT label, the dynamic bound rows. Each bound limits the
# development of a process (CAP, NCAP or ACT) or a commodity (COMNET or
# COMPRD) from the previous period T-1 to T: with g = the LHS growth factor
# at T and L = LEAD(T),
#   (g^L * x(T-1) - x(T)) * s  =%3=  RHS(T) * L * (-s),   s = 1 for LO, -1 for UP/FX,
# so LO gives x(T) >= g^L*x(T-1) + RHS*L, UP gives x(T) <= g^L*x(T-1) + RHS*L
# and FX the equality.
#
# GAMS: equcrtp.vda L73-121, v4.9.7, included from equ_ext.vda L105-106 as
#   $BATINCLUDE equcrtp.vda EQU_EXT N L BDNEQ
#   $BATINCLUDE equcrtp.vda EQU_EXT E E "'FX'"
# (%2 = declaration type, %3 = definition type, %4 = bound set); declared
# equ_ext.vda L30-32, in the model through mod_ext.vda L25-27:
#   EQN_UCRTP(UC_N,R,T,P,UC_GRPTYPE,BD), =L=, BD in BDNEQ = {LO, UP};
#   EQE_UCRTP(UC_N,R,T,P,UC_GRPTYPE,BD), =E=, BD = FX;
#   EQN_UCRTC(UC_N,COM_VAR,R,T,C,S,BD),  =L=, BD in BDNEQ (L101: no EQE_UCRTC).
#
#   EQ%2_UCRTP(UC_N,RTP(R,T,P),UC_GRPTYPE,BD(%4))$(PRC_DYNUC(UC_N,'RHS',R,T,P,UC_GRPTYPE,BD))..
#     (SUM(SAMEAS(T-1,V(TT))$RTP(R,V,P), POWER(PRC_DYNUC(UC_N,'LHS',R,T,P,UC_GRPTYPE,BD),LEAD(T)) *
#        VAR_CAP(R,V,P))*(1-2$BDUPX(BD)) - VAR_CAP(R,T,P)*(1-2$BDUPX(BD)))$SAMEAS('CAP',UC_GRPTYPE)
#     + (same with VAR_NCAP)$SAMEAS('NCAP',UC_GRPTYPE)
#     + (SUM(SAMEAS(T-1,V(TT))$RTP_VARA(R,V,P), POWER(...,LEAD(T)) *
#          SUM((RTP_VINTYR(R,MODLYEAR,V,P),PRC_TS(R,P,S)), VAR_ACT(R,MODLYEAR,V,P,S)))*(1-2$BDUPX(BD))
#        - SUM((RTP_VINTYR(R,MODLYEAR,T,P),PRC_TS(R,P,S)), VAR_ACT(R,MODLYEAR,T,P,S))*(1-2$BDUPX(BD)))$SAMEAS('ACT',UC_GRPTYPE)
#     =%3=  PRC_DYNUC(UC_N,'RHS',R,T,P,UC_GRPTYPE,BD)*LEAD(T)*(-1+2$BDUPX(BD));
#
#   EQN_UCRTC(UC_N,COM_VAR,RTC(R,T,C),ANNUAL(S),BD(BDNEQ))$(UC_COM(UC_N,COM_VAR,'RHS',RTC,S,'UCN')$UC_DYNBND(UC_N,BD))..
#     (SUM(SAMEAS(T-1,Y(TT))$RTC(R,Y,C), POWER(UC_COM(UC_N,COM_VAR,'LHS',RTC,S,'UCN'),LEAD(T)) *
#        SUM(RHS_COMBAL(R,Y,C,S), VAR_COMNET(R,Y,C,S)))*(1-2$BDUPX(BD))
#      - SUM(RHS_COMBAL(R,T,C,S), VAR_COMNET(R,T,C,S))*(1-2$BDUPX(BD)))$SAMEAS('NET',COM_VAR)
#     + (same with RHS_COMPRD, VAR_COMPRD)$SAMEAS('PRD',COM_VAR)
#     =L=  UC_COM(UC_N,COM_VAR,'RHS',R,T,C,S,'UCN')*LEAD(T)*(-1+2$BDUPX(BD));
#
# Macro expansions: %EQ% -> EQ, %VAR%/%VARV%/%VARTT% -> VAR, %SOW%/%SWS%/
# %SWT% -> '' (setglobs.gms L348); %MX% -> '' (setglobs.gms L356, maindrv.mod
# L30); %R_T% -> 'R,T' (maindrv.mod L39; STEPPED and REG_FIXT are refused in
# bndmain.jl). BDUPX = {UP, FX}, BDNEQ = {LO, UP} (setglobs.gms L155-157).
# `RTC` used as an index inside the definition is the controlled (R,T,C), so
# the LHS factor is read at T in both families. `SAMEAS(T-1,V(TT))` is the
# previous milestone (none in the first period, which keeps only the -x(T)
# term). The domain condition holds for any stored value, EPS included.
# POWER needs an integer LEAD(T) (gpower, G13).

"""
    eq_ucrtp!(tm::TimesModel) -> Int

Generate every EQN_UCRTP, EQE_UCRTP and EQN_UCRTC row (equ_ext.vda
L105-106) from `tm.data`. Returns the number of rows generated.

GAMS: equcrtp.vda L73-121, v4.9.7.
"""
function eq_ucrtp!(tm::TimesModel)
    d = tm.data
    dynuc = gparam_opt(d, "PRC_DYNUC", 7)
    dynbnd = gset_opt(d, "UC_DYNBND", 2)
    (isempty(dynuc) && isempty(dynbnd)) && return 0
    one = GNum(1.0)
    sgn(bd) = bd in ("UP", "FX") ? GNum(-1.0) : one               # 1-2$BDUPX(BD)
    lead = gparam(tm, "LEAD")
    t_set = gset(tm, "MILESTONYR")
    tx = eq_periods(tm)   # %R_T%, %TX%: SUBT in a stepped run (maindrv.mod L38-40)
    t_list = [k[1] for k in t_set.keys]                             # T in order
    t_prev = Dict(t_list[i] => t_list[i-1] for i in 2:length(t_list))   # SAMEAS(T-1,V(TT))
    n = 0

    # EQN_UCRTP / EQE_UCRTP (L75-99)
    if !isempty(dynuc)
        rtp, rtp_vara, rtp_vintyr = gset(tm, "RTP"), gset(tm, "RTP_VARA"), gset(tm, "RTP_VINTYR")
        prc_ts_of = indexby(gset(tm, "PRC_TS"), (1, 2))                   # (r,p) -> PRC_TS(r,p,s)
        vint_of_rtp = indexby(rtp_vintyr, (1, 3, 4))                      # (r,t,p) -> RTP_VINTYR(r,m,t,p)
        # SUM((RTP_VINTYR(R,MODLYEAR,Y,P),PRC_TS(R,P,S)), VAR_ACT(R,MODLYEAR,Y,P,S)) with coefficient k
        function act_terms!(expr, k, r, y, p)
            for (_, m, _, _) in get(vint_of_rtp, (r, y, p), NTuple{4,String}[]),
                (_, _, s) in get(prc_ts_of, (r, p), NTuple{3,String}[])
                addterm!(expr, k, tm, "VAR_ACT", r, m, y, p, s)
            end
        end
        for (u, side, r, t, p, grp, bd) in dynuc.keys
            side == "RHS" || continue
            ((t,) in tx && (r, t, p) in rtp) || continue              # RTP(%R_T%,P)
            name, eqtype = bd == "FX" ? ("EQE_UCRTP", "E") : bd in ("LO", "UP") ? ("EQN_UCRTP", "L") : continue
            s = sgn(bd)
            lt = gv(lead, (t,))
            lhs = JuMP.AffExpr(0.0)
            g = gpower(gv(dynuc, (u, "LHS", r, t, p, grp, bd)), lt)  # POWER(PRC_DYNUC(..'LHS'..),LEAD(T))
            v = get(t_prev, t, nothing)
            if grp == "CAP" || grp == "NCAP"                         # L79-81, L85-87
                var = "VAR_" * grp
                v !== nothing && (r, v, p) in rtp && addterm!(lhs, g * s, tm, var, r, v, p)
                addterm!(lhs, -s, tm, var, r, t, p)
            elseif grp == "ACT"                                       # L91-93
                v !== nothing && (r, v, p) in rtp_vara && act_terms!(lhs, g * s, r, v, p)
                act_terms!(lhs, -s, r, t, p)
            end
            rhs = JuMP.AffExpr(0.0)
            addconst!(rhs, gv(dynuc, (u, side, r, t, p, grp, bd)) * lt * (-s))    # L98
            gconstraint!(tm, name, (u, r, t, p, grp, bd), eqtype, lhs, rhs) === nothing || (n += 1)
        end
    end

    # EQN_UCRTC (L103-121)
    if !isempty(dynbnd)
        uc_com = gparam(tm, "UC_COM")
        rtc = gset(tm, "RTC")
        rhs_combal, rhs_comprd = gset(tm, "RHS_COMBAL"), gset(tm, "RHS_COMPRD")
        bds_of = indexby(dynbnd, (1,))                                    # UC_N -> UC_DYNBND(UC_N,BD)
        for (u, cv, side, r, t, c, s, tag) in uc_com.keys
            (side == "RHS" && tag == "UCN" && s == "ANNUAL") || continue  # ANNUAL(S), 'UCN'
            ((t,) in tx && (r, t, c) in rtc) || continue                   # RTC(%R_T%,C)
            for (_, bd) in get(bds_of, (u,), NTuple{2,String}[])
                bd in ("LO", "UP") || continue                             # BD(BDNEQ)
                sg = sgn(bd)
                lt = gv(lead, (t,))
                lhs = JuMP.AffExpr(0.0)
                g = gpower(gv(uc_com, (u, cv, "LHS", r, t, c, s, "UCN")), lt)
                y = get(t_prev, t, nothing)
                if cv == "NET" || cv == "PRD"                              # L107-109, L113-115
                    rhsset, var = cv == "NET" ? (rhs_combal, "VAR_COMNET") : (rhs_comprd, "VAR_COMPRD")
                    y !== nothing && (r, y, c) in rtc && (r, y, c, s) in rhsset && addterm!(lhs, g * sg, tm, var, r, y, c, s)
                    (r, t, c, s) in rhsset && addterm!(lhs, -sg, tm, var, r, t, c, s)
                end
                rhs = JuMP.AffExpr(0.0)
                addconst!(rhs, gv(uc_com, (u, cv, side, r, t, c, s, tag)) * lt * (-sg))  # L120
                gconstraint!(tm, "EQN_UCRTC", (u, cv, r, t, c, s, bd), "L", lhs, rhs) === nothing || (n += 1)
            end
        end
    end
    return n
end
