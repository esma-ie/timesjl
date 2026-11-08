# EQ_SLSIFT, load shifting (VDA): eqactups.vda L127-158 (v4.9.7), included
# from equ_ext.vda L90 (`$BATINCLUDE eqactups.%1 %MX%`; %MX% is empty,
# setglobs.gms L356 and L374).
#
# A load-shifting process is a timeslice storage process whose commodity
# COM is both stored and delivered (RPC_LS, ppmain.mod L1065-1078); STG_SIFT
# limits the shifted share and ACT_TIME (LO/UP/N/FX) the advance, delay or
# balancing time windows. The other families of eqactups.vda (EQ_CAPLOAD,
# EQ_ACTRAMP, EQ(l)_ACTUPS, EQL_ACTUPC, EQ_ACTPL, EQ_ACTRMPC, EQL_STGCCL) are
# not translated and stay refused by the generation driver.
#
# Macro expansions: %EQ% -> EQ, %VAR% -> VAR, %SOW%/%SWT% -> '' (setglobs.gms
# L348); %R_T% -> 'R,T' (maindrv.mod L39); RTS(S) -> S; %PGPRIM% -> 'ACT'
# (initmty.mod L138); `var_sift(v,s,l)` (L127, OBMAC is YES) is
# VAR_UDP(R,v,T,P,s,l)*PRC_CAPACT(R,P)*RS_STGPRD(R,s)/8760. Sets: L = LIM =
# {LO, FX, UP, N} (initsys.mod L70-72), LNX = {N, FX}, IPS = {IN, N} (so
# IPS(L) is L = 'N'), BDNEQ = {LO, UP} (setglobs.gms L154-157), BD =
# {LO, UP, FX}; BDSIG LO 1, UP -1 (setglobs.gms L248). `S--RS_STG(R,S)` is
# the previous slice of the storage cycle, read from RS_PREV (`stg_prev`,
# eqstgtss.jl). MOD takes the sign of its first argument (G43).

const _SLS_BD = ("LO", "UP", "FX")
const _SLS_BDSIG = Dict("LO" => 1.0, "UP" => -1.0)

"""
    eq_slsift!(tm::TimesModel) -> Int

Generate the EQ_SLSIFT rows:

    EQ_SLSIFT(RTP(R,T,P),COM,S,LNX,L)\$((PRC_TS(R,P,S)\$ACT_TIME(RTP,L)+BD(LNX)\$LNX(L))\$RPS_PRCTS(R,P,S)\$RPC_LS(R,P,COM))..
      SUM(RTP_VINTYR(R,V,T,P),
        SUM(IPS(L)\$(PRC_TS(R,P,S)+YES\$STG_SIFT(RTP,'ACT',S)+ANNUAL(S)\$ACTCG(COM)),
          SUM(PRC_TS(R,P,TS)\$RS_BELOW1(R,S,TS),VAR_ACT(R,V,T,P,TS))\$STG_SIFT(RTP,'ACT',S) +
          SUM((TOP(RPC_STG(R,P,C),'OUT'),RPCS_VAR(R,P,C,TS)),VAR_SOUT(R,V,T,P,C,TS))\$ANNUAL(S)\$ACTCG(COM) +
          (VAR_SIN(R,V,T,P,COM,S) + VAR_ACT(R,V,T,P,S))\$PRC_TS(R,P,S) + VAR_SOUT(R,T,T,P,'ACT',S) -
          SUM((TOP(RPC_STG(R,P,C),'OUT'),RTCS_VARC(RTC(R,T,C),TS))\$RS_FR(R,S,TS),
            (STG_SIFT(RTP,C,TS)\$(PRC_TS(R,P,S)+ANNUAL(S)\$ACTCG(COM))+STG_SIFT(RTP,'ACT',S)) *
            VAR_COMPRD(R,T,C,TS)/COM_IE(RTC,TS)*RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS)))) -
        SUM(BD(L)\$LNX(L),
          (SUM((TOP(RPC_STG(R,P,C),'OUT'),RPCS_VAR(R,P,C,TS))\$RS_FR(R,S,TS),VAR_SOUT(R,V,T,P,C,TS)*RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS))) -
           SUM(TOP(RPC_STG(R,P,C),'IN'),VAR_SIN(R,V,T,P,C,S)) - (VAR_ACT(R,V,T,P,S)-VAR_SIN(R,V,T,P,COM,S)))\$PRC_TS(R,P,S) +
          SUM(PRC_TS(R,P,TS)\$RS_BELOW1(R,S,TS),VAR_SIN(R,V,T,P,COM,TS)-VAR_ACT(R,V,T,P,TS))\$(SUM(LIM\$ACT_TIME(RTP,LIM),1)=0)) +
        SUM(BDNEQ(BD(L))\$ACT_TIME(RTP,'LO'),VAR_SIFT(V,S,L)+VAR_SIFT('0',S,L) -
          SUM((RS_UP(R,S,JS),RJ_SL(R,JS,SL)),VAR_UPS(R,V,T,P,SL,L)\$(MOD((RS_HR(R,S)-RS_HR(R,SL)+G_YRFR(R,S)/RS_STGPRD(R,S)/9)*BDSIG(L)+1/JS_CCL(R,JS),1/JS_CCL(R,JS))<ACT_TIME(RTP,L)/8760))))\$BD(LNX)
      =E=
      SUM(RTP_VINTYR(R,V,T,P),
        SUM(TS(S--RS_STG(R,S)),SUM(BDNEQ(BD),(VAR_SIFT(V,TS,BD)-VAR_SIFT(V,S,BD))*BDSIG(BD))+VAR_SIN(R,V,T,P,COM,S)-VAR_ACT(R,V,T,P,S))\$(BDSIG(L)<0) +
        (SUM(BDNEQ(BD),VAR_UPS(R,V,T,P,S,BD))-VAR_SIN(R,V,T,P,COM,S))\$(BDSIG(L)>0) +
        SUM(LASTLL\$LNX(L),SUM(LIM\$(IPS(L) XOR BD(LIM)),VAR_SIFT(V,S,LIM)) +
          SUM((RS_UP(R,S,JS),RJ_SL(R,JS,TS(SL--RS_STG(R,SL)))),
            (VAR_ACT(R,V,T,P,SL)\$IPS(L)-VAR_SIN(R,V,T,P,COM,SL)-(VAR_SIFT(V,SL,'UP')-VAR_SIFT(V,TS,'UP'))\$BD(L))
            \$(MOD(RS_HR(R,S)-RS_HR(R,SL)+G_YRFR(R,S)/RS_STGPRD(R,S)/9+1/JS_CCL(R,JS),1/JS_CCL(R,JS))<ACT_TIME(RTP,L)/8760))))\$IPS(LNX);

So the left-hand side is generated only for LNX = FX and the right-hand
side only for LNX = N. Rows exist for LNX = FX and L in {N, FX} at every
slice of the process's level, and for any LNX and an L with ACT_TIME at the
process's own slices. In the last sum, `TS(SL--RS_STG(R,SL))` binds TS to
the previous slice of SL, so each SL whose previous slice is in RJ_SL is
taken once. RS_UP(R,S,JS) and RJ_SL(R,JS,SL) carry JS = (J, S') as two
indices (timslice.mod L110-121). Returns the number of rows.

GAMS: eqactups.vda L127-158, v4.9.7.
"""
function eq_slsift!(tm::TimesModel)
    rpc_ls = gset(tm, "RPC_LS")
    isempty(rpc_ls) && return 0
    d = tm.data
    t_of_rp = indexby(gset(tm, "RTP"), (1, 3))                         # (r,p) -> RTP(r,t,p)
    prc_ts = gset(tm, "PRC_TS")
    rps_prcts_of_rp = indexby(gset(tm, "RPS_PRCTS"), (1, 2))           # (r,p) -> RPS_PRCTS(r,p,s)
    act_time = gparam_opt(d, "ACT_TIME", 4)                            # (r,t,p,l)
    stg_sift = gparam(tm, "STG_SIFT")                                  # (r,t,p,c,s)
    vint_of_rtp = indexby(gset(tm, "RTP_VINTYR"), (1, 3, 4))           # (r,t,p) -> RTP_VINTYR(r,v,t,p)
    prcts_of_rp = indexby(prc_ts, (1, 2))                              # (r,p) -> PRC_TS(r,p,ts)
    rs_below1 = gset(tm, "RS_BELOW1")
    top = gset(tm, "TOP")
    rpc_stg = gset(tm, "RPC_STG")
    stgc_out = Dict{Tuple{String,String},Vector{String}}()              # (r,p) -> C with TOP(RPC_STG(R,P,C),'OUT')
    stgc_in = Dict{Tuple{String,String},Vector{String}}()
    for (r, p, c, io) in top
        (r, p, c) in rpc_stg || continue
        io == "OUT" && push!(get!(() -> String[], stgc_out, (r, p)), c)
        io == "IN" && push!(get!(() -> String[], stgc_in, (r, p)), c)
    end
    rpcs_var_of_rpc = indexby(gset(tm, "RPCS_VAR"), (1, 2, 3))          # (r,p,c) -> RPCS_VAR(r,p,c,ts)
    varc_of_rtc = indexby(gset(tm, "RTCS_VARC"), (1, 2, 3))             # (r,t,c) -> RTCS_VARC(r,t,c,ts)
    rtc = gset(tm, "RTC")
    rs_fr, rtcs_fr, com_ie = gparam(tm, "RS_FR"), gparam(tm, "RTCS_FR"), gparam(tm, "COM_IE")
    prc_capact, rs_stgprd, g_yrfr = gparam(tm, "PRC_CAPACT"), gparam(tm, "RS_STGPRD"), gparam(tm, "G_YRFR")
    rs_hr, js_ccl = gparam_opt(d, "RS_HR", 2), gparam_opt(d, "JS_CCL", 3)
    rsup_of_rs = indexby(gset_opt(d, "RS_UP", 4), (1, 2))               # (r,s) -> RS_UP(r,s,j,s')
    rjsl_of_rjs = indexby(gset_opt(d, "RJ_SL", 4), (1, 2, 3))           # (r,j,s') -> RJ_SL(r,j,s',sl)
    nlastll = length(gset(tm, "LASTLL"))
    actcg = gset(tm, "ACTCG")
    # S--RS_STG(R,S) (stg_prev) and its inverse over ALL_TS for the last sum
    x = (prev = Dict((k[1], k[2]) => k[3] for k in gset(tm, "RS_PREV")), rs_stg = gparam(tm, "RS_STG"))
    all_ts = [k[1] for k in gset(tm, "ALL_TS").keys]
    next_of = Dict{Tuple{String,String},Vector{String}}()               # (r, ts) -> SL with SL--RS_STG(R,SL) = ts
    for r in unique(k[1] for k in keys(rjsl_of_rjs)), sl in all_ts
        push!(get!(() -> String[], next_of, (r, stg_prev(x, r, sl))), sl)
    end
    no2, no3, no4 = NTuple{2,String}[], NTuple{3,String}[], NTuple{4,String}[]
    w(r, t, c, s, ts) = gv(rs_fr, (r, s, ts)) * (1 + gv(rtcs_fr, (r, t, c, s, ts)))
    gmod(a, b) = rem(a, b)                                              # MOD takes the sign of a (G43)
    # var_sift(v,s,l): VAR_UDP(R,v,T,P,s,l)*PRC_CAPACT(R,P)*RS_STGPRD(R,s)/8760
    sift!(e, k, r, v, t, p, s, l) =
        addterm!(e, k * (gv(prc_capact, (r, p)) * gv(rs_stgprd, (r, s)) / 8760), tm, "VAR_UDP", r, v, t, p, s, l)
    has_at(r, t, p, l) = haskey(act_time, (r, t, p, l))
    at(r, t, p, l) = gv(act_time, (r, t, p, l)).v

    rows = NTuple{7,String}[]
    for (r, p, com) in rpc_ls, (_, _, s) in get(rps_prcts_of_rp, (r, p), no3)
        for (_, t, _) in get(t_of_rp, (r, p), no3)
            for lnx in ("N", "FX"), l in ("LO", "FX", "UP", "N")
                ((r, p, s) in prc_ts && has_at(r, t, p, l)) || (lnx == "FX" && l in ("N", "FX")) || continue
                push!(rows, (r, t, p, com, s, lnx, l))
            end
        end
    end
    gams_sort!(rows, d)

    n = 0
    for (r, t, p, com, s, lnx, l) in rows
        lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
        prcts = (r, p, s) in prc_ts
        annact = s == "ANNUAL" && (com,) in actcg
        sift_act = haskey(stg_sift, (r, t, p, "ACT", s))
        no_at = !any(lim -> has_at(r, t, p, lim), ("LO", "FX", "UP", "N"))
        for (_, v, _, _) in get(vint_of_rtp, (r, t, p), no4)
            if lnx in _SLS_BD                                          # $BD(LNX): the left-hand side
                if l == "N" && (prcts || sift_act || annact)           # SUM(IPS(L)$(...), ...)
                    if sift_act
                        for (_, _, ts) in get(prcts_of_rp, (r, p), no3)
                            (r, s, ts) in rs_below1 && addterm!(lhs, GNum(1.0), tm, "VAR_ACT", r, v, t, p, ts)
                        end
                    end
                    if annact
                        for c in get(stgc_out, (r, p), String[]), (_, _, _, ts) in get(rpcs_var_of_rpc, (r, p, c), no4)
                            addterm!(lhs, GNum(1.0), tm, "VAR_SOUT", r, v, t, p, c, ts)
                        end
                    end
                    if prcts
                        addterm!(lhs, GNum(1.0), tm, "VAR_SIN", r, v, t, p, com, s)
                        addterm!(lhs, GNum(1.0), tm, "VAR_ACT", r, v, t, p, s)
                    end
                    addterm!(lhs, GNum(1.0), tm, "VAR_SOUT", r, t, t, p, "ACT", s)
                    for c in get(stgc_out, (r, p), String[])
                        (r, t, c) in rtc || continue
                        for (_, _, _, ts) in get(varc_of_rtc, (r, t, c), no4)
                            haskey(rs_fr, (r, s, ts)) || continue
                            f = gif(gv(stg_sift, (r, t, p, c, ts)), prcts || annact) + gv(stg_sift, (r, t, p, "ACT", s))
                            k = f / gv(com_ie, (r, t, c, ts)) * w(r, t, c, s, ts)
                            addterm!(lhs, -k, tm, "VAR_COMPRD", r, t, c, ts)
                        end
                    end
                end
                if l == "FX"                                           # - SUM(BD(L)$LNX(L), ...)
                    if prcts
                        for c in get(stgc_out, (r, p), String[]), (_, _, _, ts) in get(rpcs_var_of_rpc, (r, p, c), no4)
                            haskey(rs_fr, (r, s, ts)) || continue
                            addterm!(lhs, -w(r, t, c, s, ts), tm, "VAR_SOUT", r, v, t, p, c, ts)
                        end
                        for c in get(stgc_in, (r, p), String[])
                            addterm!(lhs, GNum(1.0), tm, "VAR_SIN", r, v, t, p, c, s)
                        end
                        addterm!(lhs, GNum(1.0), tm, "VAR_ACT", r, v, t, p, s)
                        addterm!(lhs, GNum(-1.0), tm, "VAR_SIN", r, v, t, p, com, s)
                    end
                    if no_at
                        for (_, _, ts) in get(prcts_of_rp, (r, p), no3)
                            (r, s, ts) in rs_below1 || continue
                            addterm!(lhs, GNum(-1.0), tm, "VAR_SIN", r, v, t, p, com, ts)
                            addterm!(lhs, GNum(1.0), tm, "VAR_ACT", r, v, t, p, ts)
                        end
                    end
                end
                if l in ("LO", "UP") && has_at(r, t, p, "LO")         # SUM(BDNEQ(BD(L))$ACT_TIME(RTP,'LO'), ...)
                    sift!(lhs, GNum(1.0), r, v, t, p, s, l)
                    sift!(lhs, GNum(1.0), r, "0", t, p, s, l)
                    for (_, _, j, s2) in get(rsup_of_rs, (r, s), no4), (_, _, _, sl) in get(rjsl_of_rjs, (r, j, s2), no4)
                        ccl = 1 / gv(js_ccl, (r, j, s2)).v
                        m = gmod((gv(rs_hr, (r, s)).v - gv(rs_hr, (r, sl)).v + gv(g_yrfr, (r, s)).v / gv(rs_stgprd, (r, s)).v / 9) *
                                 _SLS_BDSIG[l] + ccl, ccl)
                        m < at(r, t, p, l) / 8760 && addterm!(lhs, GNum(-1.0), tm, "VAR_UPS", r, v, t, p, sl, l)
                    end
                end
            end
            if lnx == "N"                                              # $IPS(LNX): the right-hand side
                if l == "UP"                                           # $(BDSIG(L)<0)
                    ts = stg_prev(x, r, s)
                    for bd in ("LO", "UP")
                        sift!(rhs, GNum(_SLS_BDSIG[bd]), r, v, t, p, ts, bd)
                        sift!(rhs, GNum(-_SLS_BDSIG[bd]), r, v, t, p, s, bd)
                    end
                    addterm!(rhs, GNum(1.0), tm, "VAR_SIN", r, v, t, p, com, s)
                    addterm!(rhs, GNum(-1.0), tm, "VAR_ACT", r, v, t, p, s)
                end
                if l == "LO"                                           # $(BDSIG(L)>0)
                    for bd in ("LO", "UP")
                        addterm!(rhs, GNum(1.0), tm, "VAR_UPS", r, v, t, p, s, bd)
                    end
                    addterm!(rhs, GNum(-1.0), tm, "VAR_SIN", r, v, t, p, com, s)
                end
                if l in ("N", "FX")                                    # SUM(LASTLL$LNX(L), ...)
                    for _ in 1:nlastll
                        for lim in ("LO", "FX", "UP", "N")             # LIM$(IPS(L) XOR BD(LIM))
                            ((l == "N") ⊻ (lim in _SLS_BD)) && sift!(rhs, GNum(1.0), r, v, t, p, s, lim)
                        end
                        for (_, _, j, s2) in get(rsup_of_rs, (r, s), no4), (_, _, _, ts) in get(rjsl_of_rjs, (r, j, s2), no4)
                            ccl = 1 / gv(js_ccl, (r, j, s2)).v
                            for sl in get(next_of, (r, ts), String[])
                                m = gmod(gv(rs_hr, (r, s)).v - gv(rs_hr, (r, sl)).v +
                                         gv(g_yrfr, (r, s)).v / gv(rs_stgprd, (r, s)).v / 9 + ccl, ccl)
                                m < at(r, t, p, l) / 8760 || continue
                                l == "N" && addterm!(rhs, GNum(1.0), tm, "VAR_ACT", r, v, t, p, sl)
                                addterm!(rhs, GNum(-1.0), tm, "VAR_SIN", r, v, t, p, com, sl)
                                if l in _SLS_BD
                                    sift!(rhs, GNum(-1.0), r, v, t, p, sl, "UP")
                                    sift!(rhs, GNum(1.0), r, v, t, p, ts, "UP")
                                end
                            end
                        end
                    end
                end
            end
        end
        gconstraint!(tm, "EQ_SLSIFT", (r, t, p, com, s, lnx, l), "E", lhs, rhs) === nothing || (n += 1)
    end
    return n
end
