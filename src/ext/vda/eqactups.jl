# Dispatching and unit commitment, the linear formulation (VDA): eqactups.vda
# L9-117 (v4.9.7), included from equ_ext.vda L90 (`$BATINCLUDE eqactups.%1
# %MX%`; %MX% is empty, setglobs.gms L356 and L374).
#
# A process with ACT_UPS data (RP_UPL, ppm_ext.vda L13-14) gets a minimum
# stable load, ramp limits, start-up and shut-down capacity, cycle limits,
# partial-load efficiency losses and ramping costs. The variables are
# VAR_UPS(R,V,T,P,S,L) (capacity started up 'UP', shut down 'LO', off-line
# 'N', the partial-load loss 'FX') and VAR_UDP(R,V,T,P,S,L) (load changes).
# Neither has bounds.
#
# This file holds
#   - the preparation, L9-32, run in the coef -> pre-solve step
#     (`eqactups_prep!`, called by `eqmain_prep!`; L33 is in eqmain_prep.jl);
#   - EQ_CAPLOAD (L39-46), EQ_ACTRAMP (L50-61), EQE_ACTUPS (L65-72),
#     EQL_ACTUPS (L76-82), EQL_ACTUPC (L86-95), EQ_ACTPL (L99-105) and
#     EQ_ACTRMPC (L113-117) (`eq_actups!`); EQL_STGCCL (L121-125, `eql_stgccl!`, M1.3 change 43).
# EQ_SLSIFT (L127-158) is in eqslsift.jl. Not translated: EQL_STGCCL
# (L121-125, STG_MAXCYC; refused by the generation driver) and the last term
# of EQ_ACTPL (L106-109), which needs DP_UNS, a parameter only the discrete
# unit commitment fills (eqlducs.vda L135-137, %DUC% = YES; refused).
#
# Macro expansions: %EQ% -> EQ, %VAR%/%VARV%/%VARM% -> VAR, %SOW%/%SWT%/%SWS%
# -> '' (setglobs.gms L348); %R_V_T% -> 'R,V,T' (maindrv.mod L39); RTS(S) ->
# S (timslice.mod L39); %PGPRIM% -> 'ACT' (initmty.mod L138); COEF_AF%1 ->
# COEF_AF (%1 is the empty %MX% of equ_ext.vda L90). The capacity macros:
#
#   %UPSCAPS% (coef_ext.vda L30)  -SUM(TS_MAP(R,ALL_TS,S)$RPS_UPS(R,P,ALL_TS),VAR_UPS(R,V,T,P,ALL_TS,'N'))
#   %CAPON%   (L34)  (COEF_CPT(R,V,T,P)*(VAR_NCAP(R,V,P)$T(V)+NCAP_PASTI(R,V,P)%RCAPSUB%))$PRC_VINT(R,P)+VAR_CAP(R,T,P)$RP_UX(R,P)
#   %MX%      (L35)  SUM(RVP_KMAP(R,V,P,MODLYEAR(K)),COEF_VNT(R,T,P,K)*(VAR_NCAP(R,K,P)$T(K)+NCAP_PASTI(R,K,P)%RCAPSBM%))
#   %TMP%     (L36)  $(NOT RP_UX(R,P))+VAR_CAP(R,T,P)$RP_UX(R,P)%UPSCAPS%
#
# so `%CAPON%%UPSCAPS%` and `%MX%%TMP%` are both the on-line capacity: the
# capacity (by vintage, or VAR_CAP for the processes of RP_UX) less the
# capacity off-line in the timeslices at or above S. NCAP_PASTI has no
# `$PYR` filter here, unlike eqcapact.mod and eqcaflac.vda. %RCAPSUB% and
# %RCAPSBM% are the early retirements (prepret.dsc L87-88; `rcapsub!`).
#
# Sets: L = LIM = {LO, FX, UP, N} (initsys.mod L70-72), BD = BND_TYPE = {LO,
# FX, UP}, LNX = {N, FX}, IPS = {IN, N} (so IPS(L) is L = 'N'), BDNEQ = {LO,
# UP}, BDLOX = {LO, FX}, BDUPX = {UP, FX} (setglobs.gms L154-157); BDSIG LO
# 1, UP -1 (setglobs.gms L248), zero for FX and N. RLUP(R,TSLVL,TSL) holds
# each timeslice level with the level directly above it.

_ups_bdsig(l) = get(_SLS_BDSIG, l, 0.0)

"""
    afups_from_afs(afs, d) -> Set{NTuple{4,String}}

The (R,T,P,S) that eqactups.vda L11 moves from AFS to AFUPS:

    AFUPS(R,T,P,S)\$((NOT RPS_CAFLAC(R,P,S,'UP'))\$PRC_TS(R,P,S)) \$= AFS(R,T,P,S,'UP')\$RP_UPL(R,P,'FX'); AFS(AFUPS,BD)=NO;

Used by the preparation and by `afs_solve` (eqcapact.jl), which rebuilds
AFS for the SOLVE.

GAMS: eqactups.vda L11, v4.9.7.
"""
function afups_from_afs(afs, d::DumpData)
    out = Set{NTuple{4,String}}()
    rp_upl = gset_opt(d, "RP_UPL", 3)
    isempty(rp_upl) && return out
    prc_ts, caflac, T = gset_opt(d, "PRC_TS", 3), gset_opt(d, "RPS_CAFLAC", 4), gset_opt(d, "MILESTONYR", 1)
    for (r, t, p, s, bd) in afs
        (bd == "UP" && (r, p, "FX") in rp_upl && (t,) in T && (r, p, s) in prc_ts && !((r, p, s, "UP") in caflac)) &&
            push!(out, (r, t, p, s))
    end
    return out
end

"""
    eqactups_dispatching(d) -> Bool

The condition of eqactups.vda L9: `IF(CARD(RP_UPL)+CARD(RP_PL)+CARD(ACT_CSTRMP), ...`.
"""
eqactups_dispatching(d::DumpData) =
    !isempty(gset_opt(d, "RP_UPL", 3)) || !isempty(gset_opt(d, "RP_PL", 3)) || !isempty(gparam_opt(d, "ACT_CSTRMP", 5))

"""
    eqactups_prep!(tm, afs) -> tm

The dispatching preparation, inside `IF(CARD(RP_UPL)+CARD(RP_PL)+CARD(ACT_CSTRMP), ...)`:

    OPTION CLEAR=UNCD7;                                                                                    (L10)
    AFUPS(R,T,P,S)\$((NOT RPS_CAFLAC(R,P,S,'UP'))\$PRC_TS(R,P,S)) \$= AFS(R,T,P,S,'UP')\$RP_UPL(R,P,'FX'); AFS(AFUPS,BD)=NO;   (L11)
    RPS_UPS(R,P,S)\$((STOAL(R,S)<2+1\$RP_UPR(R,P,'N'))\$RP_UPL(R,P,'FX')) = SUM(PRC_TS(R,P,TS)\$RS_BELOW(R,S,TS),RS_BELOW1(R,S,TS) OR STOA(S));   (L12)
    RP_UX(RP)\$(NOT PRC_VINT(RP))\$=RP_UPL(RP,'FX'); RTP_VARP(RTP(R,T,P))\$RP_UX(R,P)=YES;                 (L13)
    COEF_AF(R,T,T,P,S,'UP')\$AFUPS(R,T,P,S) \$= NCAP_AF(R,T,P,S,'UP')\$RP_UX(R,P);                         (L14)
    UNCD7(R,LL--ORD(LL),P,TSL,RDCUR(R,CUR),'UP') \$= ACT_CSTUP(R,LL,P,TSL,CUR);                            (L16)
    UNCD7(R,LL--ORD(LL),P,BD,RDCUR(R,CUR),'N') \$= ACT_CSTRMP(R,LL,P,BD,CUR);                              (L17)
    LOOP(UNCD7(R,LL,P,ITEM,R,CUR,L),RP_UPS(R,P,TSL(ITEM),L)\$(TSLVLNUM(TSL)\$RP_UPL(R,P,'FX')>1)=YES; RPC_CUR(R,P,'ACT',CUR)=YES);   (L18)
    RP_UPS(RP,TSL,L)\$SUM(PRC_TSL(RP,TSLVL)\$(ORD(TSL)>ORD(TSLVL)),1)=NO;                                  (L19)
    RPS_UPS(RP,S)\$SUM(RP_UPS(PRC_TSL(RP,TSL),L),1)=NO;                                                   (L20)
    RPS_UPS(R,P,S) \$= SUM(RP_UPS(R,P,TSL,L)\$TS_GROUP(R,TSL,S),1);                                        (L21)
    RP_UPS(R,P,TSL,LNX(L))\$RP_UPS(R,P,TSL,'UP') = SUM(RP_UPS(R,P,TSLVL,BD),RLUP(R,TSLVL,TSL)\$BD(L)+RLUP(R,TSL,TSLVL)\$IPS(L));   (L22)
    RP_UPS(R,P,TSL,'FX')\$(SUM(RP_UPS(PRC_TSL(R,P,TSLVL),L),RLUP(R,TSLVL,TSL))\$RP_UPR(R,P,'UP'))=YES;     (L23)
    LOOP(UNCD7(R,LL,P,TSL(ANNUAL),R,CUR,L),RP_UPS(R,P,TSL,L)=YES; RP_PL(R,P,'N')=NOT RP_PL(R,P,L));       (L25)
    ACT_LOSPL(RTP(R,V,P),BDNEQ(BD))\$((ACT_LOSPL(RTP,BD)<=0)\$RP_PL(R,P,'N'))=MAX(.1+.5\$BDUPX(BD),ACT_MINLD(RTP));   (L26)
    \$ BATINCLUDE pp_lvlfc.mod ACT_UPS P PRC_TS ',BD' ",'','',''" ALL_TS V RTP(R,V,P) 0 '' N                (L28)
    RTP_PL(RTP(R,V,P))\$((ACT_LOSPL(RTP,'LO')=ACT_MINLD(RTP))\$RP_UPL(R,P,'FX'))\$=RP_PL(R,P,'N');         (L29)
    RP_UPC(R,P,TSL,'N')\$RP_UPR(R,P,'N') \$= SUM(RP_UPS(PRC_TSL(R,P,TSLVL),L),RLUP(R,TSLVL,TSL));          (L31)
    RP_UPC(PRC_TSL(RP,TSL),BDNEQ(BD))\$RP_UPS(RP,TSL,'UP') \$= RP_UPR(RP,BD));                             (L32)

`afs` is AFS as eqmain_prep! has it after equ_ext.vda L79; L11 removes its
AFUPS entries. RP_UPR is still the one of init_ext.vda (from ACT_TIME):
L33 replaces it after the IF. L22 and L23 read RP_UPS as it stood before
the statement (G11, G51). The UNCD7 of L16-17 is needed only for L18 and
L25, whose results do not depend on the loop order, and L28 replaces it.

GAMS: eqactups.vda L9-32, v4.9.7.
"""
function eqactups_prep!(tm::TimesModel, afs::Set{NTuple{5,String}})
    d = tm.data
    eqactups_dispatching(d) || return tm                                   # L9
    S(name, n) = gset_opt(d, name, n)
    P(name, n) = gparam_opt(d, name, n)
    tr = TsTree(tm)
    nostr, no3 = String[], NTuple{3,String}[]
    rp_upl, rp_upr = S("RP_UPL", 3), S("RP_UPR", 3)
    upl_fx = [(k[1], k[2]) for k in rp_upl.keys if k[3] == "FX"]
    is_fx(r, p) = (r, p, "FX") in rp_upl
    rp, rtp, prc_vint, T = S("RP", 2), S("RTP", 3), S("PRC_VINT", 2), S("MILESTONYR", 1)
    ts_of_rp = Dict{NTuple{2,String},Vector{String}}()                     # (R,P) => PRC_TS timeslices
    foreach(k -> pushat!(ts_of_rp, (k[1], k[2]), k[3]), S("PRC_TS", 3).keys)
    prc_tsl = S("PRC_TSL", 3)
    tsl_of_rp = Dict{NTuple{2,String},Vector{String}}()                    # (R,P) => PRC_TSL levels
    foreach(k -> pushat!(tsl_of_rp, (k[1], k[2]), k[3]), prc_tsl.keys)
    tslvl = [k[1] for k in S("TSLVL", 1).keys]
    tsl_ord = Dict(l => i for (i, l) in enumerate(tslvl))
    rlup = S("RLUP", 3)                                                    # (R, level, the level directly above)
    up_of = Dict{NTuple{2,String},Vector{String}}()                        # (R,TSLVL) => TSL with RLUP(R,TSLVL,TSL)
    foreach(k -> pushat!(up_of, (k[1], k[2]), k[3]), rlup.keys)

    # L11
    afups = gmembers(tm, "AFUPS", 4)
    union!(afups, afups_from_afs(afs, d))
    filter!(k -> !((k[1], k[2], k[3], k[4]) in afups), afs)
    # L12
    rps_ups = gmembers(tm, "RPS_UPS", 3)
    stoa, stoal, rs_below1 = P("STOA", 1), P("STOAL", 2), S("RS_BELOW1", 3)
    for (r, p) in upl_fx, s in tr.all_ts
        gv(stoal, (r, s)).v < 2 + ((r, p, "N") in rp_upr ? 1 : 0) || continue
        on = any(ts -> (r, s, ts) in tr.rs_below && ((r, s, ts) in rs_below1 || haskey(stoa, (s,))), get(ts_of_rp, (r, p), nostr))
        on ? push!(rps_ups, (r, p, s)) : delete!(rps_ups, (r, p, s))
    end
    # L13
    rp_ux = gmembers(tm, "RP_UX", 2)
    for k in upl_fx
        (k in rp && !(k in prc_vint)) && push!(rp_ux, k)
    end
    rtp_varp = gmembers(tm, "RTP_VARP", 3)
    for (r, t, p) in rtp.keys
        ((t,) in T && (r, p) in rp_ux) && push!(rtp_varp, (r, t, p))
    end
    # L14
    coef_af, ncap_af = gvalues(tm, "COEF_AF", 6), P("NCAP_AF", 5)
    for (r, t, p, s) in afups
        ((t,) in T && (r, p) in rp_ux && haskey(ncap_af, (r, t, p, s, "UP"))) || continue
        gassign!(coef_af, (r, t, t, p, s, "UP"), gv(ncap_af, (r, t, p, s, "UP")))
    end
    # L16-18: the start-up costs give RP_UPS, both costs RPC_CUR
    rp_ups, rpc_cur = gmembers(tm, "RP_UPS", 4), gmembers(tm, "RPC_CUR", 4)
    rdcur, tslvlnum = S("RDCUR", 2), P("TSLVLNUM", 1)
    annual_up = Set{NTuple{3,String}}()                                    # UNCD7(R,LL,P,TSL(ANNUAL),R,CUR,'UP'), for L25
    for (r, _, p, tsl, cur) in P("ACT_CSTUP", 5).keys
        (r in tr.reg && (r, cur) in rdcur) || continue
        if haskey(tsl_ord, tsl)
            gif(gv(tslvlnum, (tsl,)), is_fx(r, p)).v > 1 && push!(rp_ups, (r, p, tsl, "UP"))
            tsl in tr.annual && push!(annual_up, (r, p, tsl))
        end
        push!(rpc_cur, (r, p, "ACT", cur))
    end
    for (r, _, p, _, cur) in P("ACT_CSTRMP", 5).keys
        (r in tr.reg && (r, cur) in rdcur) && push!(rpc_cur, (r, p, "ACT", cur))
    end
    # L19
    filter!(rp_ups) do (r, p, tsl, _)
        !((r, p) in rp && any(lv -> get(tsl_ord, tsl, 0) > get(tsl_ord, lv, 0), get(tsl_of_rp, (r, p), nostr)))
    end
    # L20
    at_own = Set((k[1], k[2]) for k in rp_ups if (k[1], k[2]) in rp && (k[1], k[2], k[3]) in prc_tsl)
    filter!(k -> !((k[1], k[2]) in at_own), rps_ups)
    # L21
    for (r, p, tsl, _) in rp_ups, s in get(tr.group, (r, tsl), nostr)
        push!(rps_ups, (r, p, s))
    end
    # L22, on RP_UPS as it stood before the statement
    old = copy(rp_ups)
    lv_bd = Dict{NTuple{2,String},Vector{String}}()                        # (R,P) => levels with RP_UPS(R,P,TSLVL,BD)
    foreach(k -> k[4] in _SLS_BD && pushat!(lv_bd, (k[1], k[2]), k[3]), old)
    for (r, p, tsl, l) in old
        l == "UP" || continue
        lvs = get(lv_bd, (r, p), nostr)
        any(lv -> (r, lv, tsl) in rlup, lvs) ? push!(rp_ups, (r, p, tsl, "FX")) : delete!(rp_ups, (r, p, tsl, "FX"))
        any(lv -> (r, tsl, lv) in rlup, lvs) ? push!(rp_ups, (r, p, tsl, "N")) : delete!(rp_ups, (r, p, tsl, "N"))
    end
    # L23, the same
    for (r, p, lv, _) in copy(rp_ups)
        ((r, p, lv) in prc_tsl && (r, p, "UP") in rp_upr) || continue
        foreach(tsl -> push!(rp_ups, (r, p, tsl, "FX")), get(up_of, (r, lv), nostr))
    end
    # L25
    rp_pl = gmembers(tm, "RP_PL", 3)
    for (r, p, tsl) in annual_up
        push!(rp_ups, (r, p, tsl, "UP"))
        (r, p, "UP") in rp_pl ? delete!(rp_pl, (r, p, "N")) : push!(rp_pl, (r, p, "N"))
    end
    # L26
    lospl, minld = gvalues(tm, "ACT_LOSPL", 4), P("ACT_MINLD", 3)
    for (r, v, p) in rtp.keys, bd in ("LO", "UP")
        ((r, p, "N") in rp_pl && gv(lospl, (r, v, p, bd)).v <= 0) || continue
        gassign!(lospl, (r, v, p, bd), gmax(GNum(bd == "UP" ? 0.1 + 0.5 : 0.1), gv(minld, (r, v, p))))
    end
    gput!(tm, "ACT_LOSPL", lospl)
    # L28: $BATINCLUDE pp_lvlfc.mod ACT_UPS P PRC_TS ',BD' ",'','',''" ALL_TS V RTP(R,V,P) 0 '' N
    member(s) = Set(k[1] for k in S(s, 1).keys)
    prc, bds, modl = member("PRC"), member("BD"), member("MODLYEAR")
    uncd7, ts_array = pp_lvlfc!(tm, tr, "ACT_UPS", 5; sp=4, years=modl, keyok=k -> k[3] in prc && k[5] in bds,
                                targets=k -> get(ts_of_rp, (k[1], k[3]), nostr), qual=k -> (k[1], k[2], k[3]) in rtp, p11="N")
    ts_array === nothing || gput!(tm, "TS_ARRAY", Dict{Tuple{String},Float64}((s,) => v for (s, v) in ts_array))
    # %5 is ",'','',''": the last three UNCD7 indexes are the empty label (G36)
    isempty(uncd7) || register_uel!(d, "")
    gput!(tm, "UNCD7", Set{NTuple{7,String}}(NTuple{7,String}((k[1:4]..., "", "", "")) for k in uncd7))
    # L29
    rtp_pl = gmembers(tm, "RTP_PL", 3)
    for (r, v, p) in rtp.keys
        ((r, p, "N") in rp_pl && is_fx(r, p) && gv(lospl, (r, v, p, "LO")).v == gv(minld, (r, v, p)).v) && push!(rtp_pl, (r, v, p))
    end
    # L31-32
    rp_upc = gmembers(tm, "RP_UPC", 4)
    for (r, p, lv, l) in rp_ups
        (r, p, lv) in prc_tsl || continue
        (r, p, "N") in rp_upr && foreach(tsl -> push!(rp_upc, (r, p, tsl, "N")), get(up_of, (r, lv), nostr))
        if l == "UP" && (r, p) in rp
            for bd in ("LO", "UP")
                (r, p, bd) in rp_upr && push!(rp_upc, (r, p, lv, bd))
            end
        end
    end
    gput!(tm, "AFUPS", afups); gput!(tm, "RPS_UPS", rps_ups); gput!(tm, "RP_UX", rp_ux); gput!(tm, "RTP_VARP", rtp_varp)
    gput!(tm, "COEF_AF", coef_af); gput!(tm, "RP_UPS", rp_ups); gput!(tm, "RPC_CUR", rpc_cur); gput!(tm, "RP_PL", rp_pl)
    gput!(tm, "RTP_PL", rtp_pl); gput!(tm, "RP_UPC", rp_upc)
    return tm
end

"""
    eq_actups!(tm::TimesModel) -> Int

Generate the dispatching rows (the macros are in the file header; ON is the
on-line capacity `%CAPON%%UPSCAPS%` or `%MX%%TMP%`):

    EQ_CAPLOAD(RTP_VINTYR(R,V,T,P),S,BDNEQ(BD))\$AFUPS(R,T,P,S)..
      VAR_ACT(R,V,T,P,S)*BDSIG(BD)  =G=  VAR_UPS(R,V,T,P,S,'FX')\$RTP_PL(R,V,P)\$BDLOX(BD) +
      (%CAPON%%UPSCAPS%) * MIN(COEF_AF(R,V,T,P,S,'UP')*BDSIG(BD),SUM(TS_ANN(S,TS)\$(NOT RTP_PL(R,V,P)),ACT_UPS(R,V,P,TS,'FX'))\$BDLOX(BD)) *
      PRC_CAPACT(R,P) * G_YRFR(R,S);

    EQ_ACTRAMP(RTP_VINTYR(R,V,T,P),S,BDNEQ(BD))\$(SUM(TS_ANN(S,TS)\$ACT_UPS(R,V,P,TS,BD),1)\$PRC_TS(R,P,S)\$RP_UPL(R,P,BD))..
      SUM(RS_PREV(R,S,TS)\$PRC_TS(R,P,TS),PRC_CAPACT(R,P)*SUM(TS_ANN(S,SL),ACT_UPS(R,V,P,SL,BD)) *
        (%MX%%TMP% + ((VAR_UPS(R,V,T,P,S,'N')-VAR_UPS(R,V,T,P,TS,'N'))\$BDLOX(BD))\$RPS_UPS(R,P,S)) +
        RS_STGPRD(R,S)*2/(G_YRFR(R,S)+G_YRFR(R,TS))/8760 *
        (VAR_ACT(R,V,T,P,S)/G_YRFR(R,S)-VAR_ACT(R,V,T,P,TS)/G_YRFR(R,TS) +
         ((VAR_UPS(R,V,T,P,S,'N')-VAR_UPS(R,V,T,P,TS,'N'))*PRC_CAPACT(R,P)*ACT_MINLD(R,V,P))\$RPS_UPS(R,P,S))*BDSIG(BD))
      =G= 0;

    EQE_ACTUPS(RTP_VINTYR(R,V,T,P),TSL,L(BND_TYPE),S)\$(TS_GROUP(R,TSL,S)\$RP_UPS(R,P,TSL,L))..
      (SUM(RS_PREV(R,S,TS),VAR_UPS(R,V,T,P,S,'N')-VAR_UPS(R,V,T,P,TS,'N')-SUM(BD,VAR_UPS(R,V,T,P,S,BD)*BDSIG(BD)))\$STOA(S) +
       SUM(ANNUAL(S)\$RP_PL(R,P,'N'),VAR_UPS(R,V,T,P,S,L)-SUM(PRC_TS(R,P,TS),VAR_UPS(R,V,T,P,TS,'FX'))))\$(BDSIG(L)<0) +
      SUM(BDLOX(BD(L)),%MX%%TMP%-VAR_UDP(R,V,T,P,S,'FX')-VAR_UPS(R,V,T,P,S,'FX')\$RP_UPL(R,P,'FX'))
      =E= 0;

    EQL_ACTUPS(RTP_VINTYR(R,V,T,P),TSL,LNX(L),S)\$(TS_GROUP(R,TSL,S)\$RP_UPS(R,P,TSL,L))..
      (VAR_UPS(R,V,T,P,S,L)-SUM(RS_BELOW1(R,TS,S),VAR_UPS(R,V,T,P,TS,'FX')))\$IPS(L) +
      (VAR_UPS(R,V,T,P,S,L)-SUM(RS_BELOW1(R,S,TS),VAR_UPS(R,V,T,P,TS,'UP')))\$BD(L)
      =L= 0;

    EQL_ACTUPC(RTP_VINTYR(R,V,T,P),TSL,L,S)\$(TS_GROUP(R,TSL,S)\$RP_UPC(R,P,TSL,L))..
      (SUM(RS_BELOW1(R,S,SL),VAR_UPS(R,V,T,P,SL,'UP')) - (%CAPON%%UPSCAPS%)*ACT_TIME(R,T,P,L))\$IPS(L) +
      SUM(BD(L),
        SUM((RS_UP(R,S,JS),RJ_SL(R,JS,SL)),VAR_UPS(R,V,T,P,SL,L)\$(RS_MODUS(R,S,JS,SL) < ACT_TIME(R,T,P,L)/8760)) -
        SUM(RS_UP(R,S,J,TS),VAR_UPS(R,V,T,P,TS,'FX'))\$BDUPX(BD)-VAR_UPS(R,V,T,P,S,'N')*BDSIG(L))
      =L= 0;

    EQ_ACTPL(RTP_VINTYR(R,V,T,P),S)\$(PRC_TS(R,P,S)\$RP_PL(R,P,'N'))..
      VAR_UPS(R,V,T,P,S,'FX')  =G=
      ((%MX%%TMP%)*PRC_CAPACT(R,P)*G_YRFR(R,S) * (ACT_LOSPL(R,V,P,'UP')+ACT_LOSPL(R,V,P,'LO')*(1-ACT_LOSPL(R,V,P,'UP'))) -
       VAR_ACT(R,V,T,P,S)) / (ACT_LOSPL(R,V,P,'UP')*(1/ACT_LOSPL(R,V,P,'LO')-1))
      [+ the start-up and shut-down loads of the discrete unit commitment, L106-109: DP_UNS, refused];

    EQ_ACTRMPC(RTP_VINTYR(R,V,T,P),TS(S--RS_STG(R,S)))\$(PRC_TS(R,P,S)\$RP_STD(R,P)\$SUM(RP_UPR(R,P,BD),1))..
      (VAR_ACT(R,V,T,P,TS)/G_YRFR(R,TS)-VAR_ACT(R,V,T,P,S)/G_YRFR(R,S))/PRC_CAPACT(R,P) =E=
      SUM(BDNEQ(BD),VAR_UDP(R,V,T,P,S,BD)*BDSIG(BD))-ACT_MINLD(R,V,P)*(VAR_UPS(R,V,T,P,TS,'N')-VAR_UPS(R,V,T,P,S,'N'))\$RPS_UPS(R,P,S);

In EQ_ACTRMPC S runs over the process's timeslices and TS is the slice
before S in its cycle (`stg_prev`); the row carries the label of TS. Returns
the number of rows.

GAMS: eqactups.vda L34-117, v4.9.7.
"""
function eq_actups!(tm::TimesModel)
    d = tm.data
    S(name, n) = gset_opt(d, name, n)
    P(name, n) = gparam_opt(d, name, n)
    afups, rp_ups, rp_upc = S("AFUPS", 4), S("RP_UPS", 4), S("RP_UPC", 4)
    rp_upl, rp_pl, rp_upr = S("RP_UPL", 3), S("RP_PL", 3), S("RP_UPR", 3)
    (isempty(afups) && isempty(rp_ups) && isempty(rp_upc) && isempty(rp_upl) && isempty(rp_pl) && isempty(rp_upr)) && return 0
    modlyear, T = S("MODLYEAR", 1), S("MILESTONYR", 1)
    tx = eq_periods(tm)   # %R_V_T%: SUBT in a stepped run (maindrv.mod L38-40)
    vint = gset(tm, "RTP_VINTYR")
    vt_ok(v, t) = (v,) in modlyear && (t,) in tx
    vt_of_rp = indexby(vint, (1, 4))                                       # (r,p) -> RTP_VINTYR(r,v,t,p)
    vint_of_rtp = indexby(vint, (1, 3, 4))                                 # (r,t,p) -> RTP_VINTYR(r,v,t,p)
    prc_ts = S("PRC_TS", 3)
    ts_of_rp = indexby(prc_ts, (1, 2))                                     # (r,p) -> PRC_TS(r,p,ts)
    prc_vint, rp_ux, rtp_pl, rps_ups = S("PRC_VINT", 2), S("RP_UX", 2), S("RTP_PL", 3), S("RPS_UPS", 3)
    ups_of_rp = indexby(rps_ups, (1, 2))                                   # (r,p) -> RPS_UPS(r,p,ts)
    tsmap = S("TS_MAP", 3)                                                 # (r,ts,s): ts at or above s
    kmap = get!(() -> indexby(gset_opt(d, "RVP_KMAP", 4), (1, 2, 3)), tm.cache, "RVP_KMAP/rvp")
    coef_cpt, coef_vnt, coef_af, pasti = P("COEF_CPT", 4), P("COEF_VNT", 4), P("COEF_AF", 6), P("NCAP_PASTI", 3)
    capact, yrfr, stgprd = P("PRC_CAPACT", 2), P("G_YRFR", 2), P("RS_STGPRD", 2)
    act_ups, minld, lospl, act_time = P("ACT_UPS", 5), P("ACT_MINLD", 3), P("ACT_LOSPL", 4), P("ACT_TIME", 4)
    tsann_of_s = indexby(S("TS_ANN", 2), (1,))                             # (s,) -> TS_ANN(s,ts)
    prev_of_rs = indexby(S("RS_PREV", 3), (1, 2))                          # (r,s) -> RS_PREV(r,s,ts)
    below1 = S("RS_BELOW1", 3)
    child_of = indexby(below1, (1, 2))                                     # (r,s) -> RS_BELOW1(r,s,ts)
    parent_of = indexby(below1, (1, 3))                                    # (r,s) -> RS_BELOW1(r,ts,s)
    group_of = indexby(S("TS_GROUP", 3), (1, 2))                           # (r,tsl) -> TS_GROUP(r,tsl,s)
    stoa, annual, rp_std = P("STOA", 1), S("ANNUAL", 1), S("RP_STD", 2)
    rsup_of_rs = indexby(S("RS_UP", 4), (1, 2))                            # (r,s) -> RS_UP(r,s,j,s')
    rjsl_of_rjs = indexby(S("RJ_SL", 4), (1, 2, 3))                        # (r,j,s') -> RJ_SL(r,j,s',sl)
    modus = P("RS_MODUS", 5)
    x = (prev = Dict((k[1], k[2]) => k[3] for k in S("RS_PREV", 3)), rs_stg = P("RS_STG", 2))
    no2, no3, no4 = NTuple{2,String}[], NTuple{3,String}[], NTuple{4,String}[]
    one = GNum(1.0)
    ups!(e, c, r, v, t, p, s, l) = addterm!(e, GNum(c), tm, "VAR_UPS", r, v, t, p, s, l)
    act!(e, c, r, v, t, p, s) = addterm!(e, GNum(c), tm, "VAR_ACT", r, v, t, p, s)
    # c * %UPSCAPS%
    function upscaps!(e, c::GNum, r, v, t, p, s)
        for (_, _, ts) in get(ups_of_rp, (r, p), no3)
            (r, ts, s) in tsmap && ups!(e, -c, r, v, t, p, ts, "N")
        end
        return e
    end
    # c * %CAPON%
    function capon!(e, c::GNum, r, v, t, p)
        if (r, p) in prc_vint
            k = c * gv(coef_cpt, (r, v, t, p))
            (v,) in T && addterm!(e, k, tm, "VAR_NCAP", r, v, p)
            addconst!(e, k * gv(pasti, (r, v, p)))
            rcapsub!(e, k, tm, r, v, t, p)                                  # %RCAPSUB%
        end
        (r, p) in rp_ux && addterm!(e, c, tm, "VAR_CAP", r, t, p)
        return e
    end
    # c * (%MX%%TMP%)
    function mxtmp!(e, c::GNum, r, v, t, p, s)
        if (r, p) in rp_ux
            addterm!(e, c, tm, "VAR_CAP", r, t, p)
        else
            for (_, _, _, k) in get(kmap, (r, v, p), no4)
                (k,) in modlyear || continue                                # MODLYEAR(K)
                ck = c * gv(coef_vnt, (r, t, p, k))
                (k,) in T && addterm!(e, ck, tm, "VAR_NCAP", r, k, p)
                addconst!(e, ck * gv(pasti, (r, k, p)))
                rcapsub!(e, ck, tm, r, k, t, p)                             # %RCAPSBM%, MODLYEAR = K (G48)
            end
        end
        return upscaps!(e, c, r, v, t, p, s)
    end
    n = 0

    # EQ_CAPLOAD, L39-46
    rows6 = NTuple{6,String}[]
    for (r, t, p, s) in afups, (_, v, _, _) in get(vint_of_rtp, (r, t, p), no4), bd in ("LO", "UP")
        vt_ok(v, t) && push!(rows6, (r, v, t, p, s, bd))
    end
    for (r, v, t, p, s, bd) in gams_sort!(rows6, d)
        lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
        sig = _ups_bdsig(bd)
        act!(lhs, sig, r, v, t, p, s)
        pl = (r, v, p) in rtp_pl
        (pl && bd == "LO") && ups!(rhs, one, r, v, t, p, s, "FX")
        minl = GZERO                                                       # SUM(TS_ANN(S,TS)$(NOT RTP_PL), ACT_UPS(..,'FX'))$BDLOX(BD)
        if bd == "LO" && !pl
            for (_, ts) in get(tsann_of_s, (s,), no2)
                minl = minl + gv(act_ups, (r, v, p, ts, "FX"))
            end
        end
        m = gmin(gv(coef_af, (r, v, t, p, s, "UP")) * sig, minl) * gv(capact, (r, p)) * gv(yrfr, (r, s))
        capon!(rhs, m, r, v, t, p)
        upscaps!(rhs, m, r, v, t, p, s)
        gconstraint!(tm, "EQ_CAPLOAD", (r, v, t, p, s, bd), "G", lhs, rhs) === nothing || (n += 1)
    end

    # EQ_ACTRAMP, L50-61
    empty!(rows6)
    for (r, p, bd) in rp_upl
        bd in ("LO", "UP") || continue
        for (_, _, s) in get(ts_of_rp, (r, p), no3), (_, v, t, _) in get(vt_of_rp, (r, p), no4)
            vt_ok(v, t) || continue
            any(k -> haskey(act_ups, (r, v, p, k[2], bd)), get(tsann_of_s, (s,), no2)) && push!(rows6, (r, v, t, p, s, bd))
        end
    end
    for (r, v, t, p, s, bd) in gams_sort!(rows6, d)
        lhs = JuMP.AffExpr(0.0)
        sig = _ups_bdsig(bd)
        ups_s = (r, p, s) in rps_ups
        for (_, _, ts) in get(prev_of_rs, (r, s), no3)
            (r, p, ts) in prc_ts || continue
            a = GZERO
            for (_, sl) in get(tsann_of_s, (s,), no2)
                a = a + gv(act_ups, (r, v, p, sl, bd))
            end
            a = gv(capact, (r, p)) * a
            mxtmp!(lhs, a, r, v, t, p, s)
            if ups_s && bd == "LO"                                         # $BDLOX(BD)
                ups!(lhs, a, r, v, t, p, s, "N")
                ups!(lhs, -a, r, v, t, p, ts, "N")
            end
            c = gv(stgprd, (r, s)) * 2 / (gv(yrfr, (r, s)) + gv(yrfr, (r, ts))) / 8760 * sig
            act!(lhs, c / gv(yrfr, (r, s)), r, v, t, p, s)
            act!(lhs, -(c / gv(yrfr, (r, ts))), r, v, t, p, ts)
            if ups_s
                k = c * gv(capact, (r, p)) * gv(minld, (r, v, p))
                ups!(lhs, k, r, v, t, p, s, "N")
                ups!(lhs, -k, r, v, t, p, ts, "N")
            end
        end
        gconstraint!(tm, "EQ_ACTRAMP", (r, v, t, p, s, bd), "G", lhs, JuMP.AffExpr(0.0)) === nothing || (n += 1)
    end

    # EQE_ACTUPS, L65-72, and EQL_ACTUPS, L76-82
    rows_e, rows_l = NTuple{7,String}[], NTuple{7,String}[]
    for (r, p, tsl, l) in rp_ups, (_, _, s) in get(group_of, (r, tsl), no3), (_, v, t, _) in get(vt_of_rp, (r, p), no4)
        vt_ok(v, t) || continue
        l in _SLS_BD && push!(rows_e, (r, v, t, p, tsl, l, s))             # L(BND_TYPE)
        l in ("FX", "N") && push!(rows_l, (r, v, t, p, tsl, l, s))         # LNX(L)
    end
    for (r, v, t, p, tsl, l, s) in gams_sort!(rows_e, d)
        lhs = JuMP.AffExpr(0.0)
        if l == "UP"                                                       # $(BDSIG(L)<0)
            if haskey(stoa, (s,))
                for (_, _, ts) in get(prev_of_rs, (r, s), no3)
                    ups!(lhs, one, r, v, t, p, s, "N")
                    ups!(lhs, -one, r, v, t, p, ts, "N")
                    ups!(lhs, -one, r, v, t, p, s, "LO")                   # -SUM(BD, VAR_UPS(..,BD)*BDSIG(BD))
                    ups!(lhs, one, r, v, t, p, s, "UP")
                end
            end
            if (s,) in annual && (r, p, "N") in rp_pl
                ups!(lhs, one, r, v, t, p, s, l)
                for (_, _, ts) in get(ts_of_rp, (r, p), no3)
                    ups!(lhs, -one, r, v, t, p, ts, "FX")
                end
            end
        else                                                               # SUM(BDLOX(BD(L)), ...)
            mxtmp!(lhs, one, r, v, t, p, s)
            addterm!(lhs, -one, tm, "VAR_UDP", r, v, t, p, s, "FX")
            (r, p, "FX") in rp_upl && ups!(lhs, -one, r, v, t, p, s, "FX")
        end
        gconstraint!(tm, "EQE_ACTUPS", (r, v, t, p, tsl, l, s), "E", lhs, JuMP.AffExpr(0.0)) === nothing || (n += 1)
    end
    for (r, v, t, p, tsl, l, s) in gams_sort!(rows_l, d)
        lhs = JuMP.AffExpr(0.0)
        ups!(lhs, one, r, v, t, p, s, l)
        if l == "N"                                                        # $IPS(L)
            for (_, ts, _) in get(parent_of, (r, s), no3)
                ups!(lhs, -one, r, v, t, p, ts, "FX")
            end
        else                                                               # $BD(L)
            for (_, _, ts) in get(child_of, (r, s), no3)
                ups!(lhs, -one, r, v, t, p, ts, "UP")
            end
        end
        gconstraint!(tm, "EQL_ACTUPS", (r, v, t, p, tsl, l, s), "L", lhs, JuMP.AffExpr(0.0)) === nothing || (n += 1)
    end

    # EQL_ACTUPC, L86-95
    rows7 = NTuple{7,String}[]
    for (r, p, tsl, l) in rp_upc, (_, _, s) in get(group_of, (r, tsl), no3), (_, v, t, _) in get(vt_of_rp, (r, p), no4)
        vt_ok(v, t) && push!(rows7, (r, v, t, p, tsl, l, s))
    end
    for (r, v, t, p, tsl, l, s) in gams_sort!(rows7, d)
        lhs = JuMP.AffExpr(0.0)
        at = gv(act_time, (r, t, p, l))
        if l == "N"                                                        # $IPS(L): the maximum number of cycles
            for (_, _, sl) in get(child_of, (r, s), no3)
                ups!(lhs, one, r, v, t, p, sl, "UP")
            end
            capon!(lhs, -at, r, v, t, p)
            upscaps!(lhs, -at, r, v, t, p, s)
        else                                                               # SUM(BD(L), ...): the minimum on-line and off-line hours
            for (_, _, j, s2) in get(rsup_of_rs, (r, s), no4)
                for (_, _, _, sl) in get(rjsl_of_rjs, (r, j, s2), no4)
                    gv(modus, (r, s, j, s2, sl)).v < at.v / 8760 && ups!(lhs, one, r, v, t, p, sl, l)
                end
                l in ("UP", "FX") && ups!(lhs, -one, r, v, t, p, s2, "FX")  # $BDUPX(BD)
            end
            ups!(lhs, -_ups_bdsig(l), r, v, t, p, s, "N")
        end
        gconstraint!(tm, "EQL_ACTUPC", (r, v, t, p, tsl, l, s), "L", lhs, JuMP.AffExpr(0.0)) === nothing || (n += 1)
    end

    # EQ_ACTPL, L99-105 (without the DP_UNS term of L106-109)
    rows5 = NTuple{5,String}[]
    for (r, p, l) in rp_pl
        l == "N" || continue
        for (_, _, s) in get(ts_of_rp, (r, p), no3), (_, v, t, _) in get(vt_of_rp, (r, p), no4)
            vt_ok(v, t) && push!(rows5, (r, v, t, p, s))
        end
    end
    for (r, v, t, p, s) in gams_sort!(rows5, d)
        lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
        ups!(lhs, one, r, v, t, p, s, "FX")
        up, lo = gv(lospl, (r, v, p, "UP")), gv(lospl, (r, v, p, "LO"))
        den = up * (1 / lo - 1)                                            # division by zero is a GAMS error too
        mxtmp!(rhs, gv(capact, (r, p)) * gv(yrfr, (r, s)) * (up + lo * (1 - up)) / den, r, v, t, p, s)
        act!(rhs, -(one / den), r, v, t, p, s)
        gconstraint!(tm, "EQ_ACTPL", (r, v, t, p, s), "G", lhs, rhs) === nothing || (n += 1)
    end

    # EQ_ACTRMPC, L113-117
    empty!(rows5)
    slice_of = Dict{NTuple{5,String},String}()                             # the row (.., TS) -> its S
    for (r, p) in unique((k[1], k[2]) for k in rp_upr.keys if k[3] in _SLS_BD)
        (r, p) in rp_std || continue
        for (_, _, s) in get(ts_of_rp, (r, p), no3), (_, v, t, _) in get(vt_of_rp, (r, p), no4)
            vt_ok(v, t) || continue
            row = (r, v, t, p, stg_prev(x, r, s))
            push!(rows5, row)
            slice_of[row] = s
        end
    end
    for row in gams_sort!(rows5, d)
        r, v, t, p, ts = row
        s = slice_of[row]
        lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
        act!(lhs, one / gv(yrfr, (r, ts)) / gv(capact, (r, p)), r, v, t, p, ts)
        act!(lhs, -(one / gv(yrfr, (r, s)) / gv(capact, (r, p))), r, v, t, p, s)
        addterm!(rhs, one, tm, "VAR_UDP", r, v, t, p, s, "LO")
        addterm!(rhs, -one, tm, "VAR_UDP", r, v, t, p, s, "UP")
        if (r, p, s) in rps_ups
            k = gv(minld, (r, v, p))
            ups!(rhs, -k, r, v, t, p, ts, "N")
            ups!(rhs, k, r, v, t, p, s, "N")
        end
        gconstraint!(tm, "EQ_ACTRMPC", (r, v, t, p, ts), "E", lhs, rhs) === nothing || (n += 1)
    end
    return n
end

"""
    eql_stgccl!(tm) -> Int

EQL_STGCCL, the limit on the number of storage cycles over a storage
process's lifetime (STG_MAXCYC), with the extra on-line capacity
VAR_UPS(R,V,T,P,'ANNUAL','UP') that relaxes it at the start-up cost
ACT_CSTUP (annualised by coef_ext.vda L39):

    EQL_STGCCL(RTP_VINTYR(%R_V_T%,P),'1')\$(SUM(RPS_STG(R,P,S)\$COEF_AFUPS(R,V,P,S),1)\$STG_MAXCYC(R,V,P)\$RP_STG(R,P))..
      (%MX%+VAR_UPS(R,V,T,P,'ANNUAL','UP'))/EXP(PRC_SC(R,P))*SMAX(RPS_STG(R,P,S),COEF_AFUPS(R,V,P,S))*PRC_CAPACT(R,P) =G=
      SUM((TOP(RPC_STG(R,P,C),'OUT'),RPCS_VAR(R,P,C,S)),VAR_SOUT(R,V,T,P,C,S)/PRC_ACTFLO(R,V,P,C))*NCAP_TLIFE(R,V,P)/STG_MAXCYC(R,V,P);

%MX% is the macro of L35, with no %TMP%: the capacity of vintage V in
period T, SUM(RVP_KMAP(R,V,P,MODLYEAR(K)),COEF_VNT(R,T,P,K)*(VAR_NCAP(R,K,P)\$T(K)+NCAP_PASTI(R,K,P)%RCAPSBM%)),
also for a process in RP_UX. %SWTX% is empty and %SWX% is ,'1' (setglobs.gms L363-365):
every row has the last index '1'. The row is =G= although its name is EQL_.

The start-up variable's cost term (eqobjvar.mod L37, RP_UPS(R,P,'ANNUAL','UP')
from eqactups.vda L25 with RP_PL(R,P,'UP') of init_ext.vda L67) is in `eq_obj!`.

# GAMS: eqactups.vda L121-125 (with L35, %MX%), v4.9.7
"""
function eql_stgccl!(tm::TimesModel)
    d = tm.data
    maxcyc = gparam_opt(d, "STG_MAXCYC", 3)
    isempty(maxcyc) && return 0
    S(name, n) = gset_opt(d, name, n)
    P(name, n) = gparam_opt(d, name, n)
    modlyear, T = S("MODLYEAR", 1), S("MILESTONYR", 1)
    tx = eq_periods(tm)                                                    # %R_V_T%
    rp_stg = S("RP_STG", 2)
    stg_of_rp = indexby(S("RPS_STG", 3), (1, 2))                           # (r,p) -> RPS_STG(r,p,s)
    afups, capact, prc_sc = P("COEF_AFUPS", 4), P("PRC_CAPACT", 2), P("PRC_SC", 2)
    coef_vnt, pasti, actflo, tlife = P("COEF_VNT", 4), P("NCAP_PASTI", 3), P("PRC_ACTFLO", 4), P("NCAP_TLIFE", 3)
    kmap = get!(() -> indexby(gset_opt(d, "RVP_KMAP", 4), (1, 2, 3)), tm.cache, "RVP_KMAP/rvp")
    top = S("TOP", 4)
    rpc_stg = indexby(S("RPC_STG", 3), (1, 2))                             # (r,p) -> RPC_STG(r,p,c)
    rpcs_var = indexby(S("RPCS_VAR", 4), (1, 2, 3))                        # (r,p,c) -> RPCS_VAR(r,p,c,s)
    no3, no4 = NTuple{3,String}[], NTuple{4,String}[]
    rows = NTuple{4,String}[]
    for (r, v, t, p) in gset(tm, "RTP_VINTYR")
        ((v,) in modlyear && (t,) in tx && (r, p) in rp_stg) || continue
        iszero(gv(maxcyc, (r, v, p))) && continue
        any(k -> !iszero(gv(afups, (r, v, p, k[3]))), get(stg_of_rp, (r, p), no3)) || continue
        push!(rows, (r, v, t, p))
    end
    n = 0
    for (r, v, t, p) in gams_sort!(rows, d)
        lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
        smax = nothing                                                     # SMAX over a non-empty RPS_STG(R,P,S)
        for (_, _, s) in get(stg_of_rp, (r, p), no3)
            a = gv(afups, (r, v, p, s))
            smax = smax === nothing ? a : gmax(smax, a)
        end
        c = GNum(1.0) / gexp(gv(prc_sc, (r, p))) * smax * gv(capact, (r, p))
        for (_, _, _, k) in get(kmap, (r, v, p), no4)                      # %MX%
            (k,) in modlyear || continue
            ck = c * gv(coef_vnt, (r, t, p, k))
            (k,) in T && addterm!(lhs, ck, tm, "VAR_NCAP", r, k, p)
            addconst!(lhs, ck * gv(pasti, (r, k, p)))
            rcapsub!(lhs, ck, tm, r, k, t, p)                              # %RCAPSBM%
        end
        addterm!(lhs, c, tm, "VAR_UPS", r, v, t, p, "ANNUAL", "UP")
        f = gv(tlife, (r, v, p)) / gv(maxcyc, (r, v, p))
        for (_, _, com) in get(rpc_stg, (r, p), no3)
            (r, p, com, "OUT") in top || continue
            for (_, _, _, s) in get(rpcs_var, (r, p, com), no4)
                addterm!(rhs, GNum(1.0) / gv(actflo, (r, v, p, com)) * f, tm, "VAR_SOUT", r, v, t, p, com, s)
            end
        end
        gconstraint!(tm, "EQL_STGCCL", (r, v, t, p, "1"), "G", lhs, rhs) === nothing || (n += 1)
    end
    return n
end
