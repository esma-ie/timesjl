# Unit commitment by start-up type, the linear formulation (VDA): eqlducs.vda
# L9-124 (v4.9.7). The file is included twice:
#   - coef_ext.vda L78 (`$BATINCLUDE eqlducs.vda`): the preparation L12-41, at
#     the coefficient stage (`eqlducs_prep!`, called by `coef_ext!`);
#   - equ_ext.vda L91 (`$BATINCLUDE eqlducs.%1 EQU`), after eqactups.vda (L90):
#     the EQU section L46-51 (`eqlducs_equ!`, called by `eqmain_prep!` after
#     `eqactups_prep!`) and the equations L67-124 (`eq_lducs!`).
# L9 leaves the file unless %OBMAC% is YES, which it always is here.
#
# A process with start-up costs by type (ACT_CSTSD: hot, warm and cold
# starts; UPT = {HOT, WARM, COLD}) and a dispatching load range (RP_UPL 'FX')
# is in RP_DP. Its variables:
#
#   VAR_UDP(R,V,T,P,S,'N')   var_on:  capacity on-line
#   VAR_UDP(R,V,T,P,S,'FX')  var_gap: on-line capacity above the minimum load
#   VAR_UPS(R,V,T,P,S,'N')   var_off: capacity off-line
#   VAR_UPS(R,V,T,P,S,'UP')  capacity started up; 'LO': shut down
#   VAR_UPS(R,V,T,P,S,'FX')  the efficiency loss of the start-up and shut-down phases
#   VAR_UPT(R,V,T,P,S,UPT)   capacity started up, by start-up type
#
# None has bounds. The equations: eq_sdlogic (L67-70), eq_sudupt (L74-77),
# eq_sdslant (L81-90), eq_sdminon (L94-97), eq_sudload (L101-103), eq_sudtime
# (L107-114), eq_sudpll (L118-124). The cost of the start-ups by type is in
# EQ_OBJVAR (eqobjvar.mod L38; eqobj.jl).
#
# Not translated: the discrete unit commitment, L126-175 (%DUC% = YES: the
# binary var_onind, eq_sdind_1/0 and DP_UNS, a MIP; refused by the generation
# driver), and the SPRSV term of eq_sudload (the ABS extension; refused).
#
# Macros (L53-64): sdtol is .001; v_u(x,..) is VAR_&x; SUDHFR(r,s,x,sl) is
# (G_YRFR(r,s) x G_YRFR(r,sl))/2/RS_STGPRD(r,s); %CAPON% is the capacity
# (eqactups.jl); CAPUPS is %CAPON% less the capacity off-line in the
# timeslices strictly above S:
#
#   CAPUPS  (%CAPON%-SUM(rs_below(r,all_ts,s)$rps_ups(r,p,all_ts),var_off(r,v,t,p,all_ts)))
#
# Other expansions as in eqactups.jl: %SOW% and %SWTX% empty, %R_V_T% is
# 'R,V,T', RTS(S) is S, %UPSCAPS% (coef_ext.vda L30). %SWX% is ,'1'
# (setglobs.gms L365; ',SOW' only with stochastic stages, stages.stc L15):
# the seven equations are declared over ALLSOW (equ_ext.vda L47-53), so every
# row carries the last index '1'. JS is (J,ALL_TS):
# RS_UP(R,S,JS) is the cycle S belongs to (its parent timeslice and the
# number of days), RJ_SL(R,JS,SL) the timeslices SL of that cycle, JS_CCL the
# cycles per year. RS_HR is the mid-point of a timeslice in its cycle, in
# years; MOD takes the sign of its first argument (G43; `rem`).

const _SD_TOL = 0.001                                                      # $ macro sdtol .001

"""
    eqlducs_prep!(tm) -> tm

The unit-commitment preparation at the coefficient stage (coef_ext.vda L78):

    OPTION RP_UPT<ACT_CSTSD, TRACKP<RP_UPT;                                                                (L15)
    RP_DP(TRACKP(RP))\$=RP_UPL(RP,'FX');                                                                   (L16)
    RP_DP(RP)\$SUM(RPS_CAFLAC(PRC_TS(RP,S),BD),1)=NO;                                                      (L17)
    RP_DPL(PRC_TSL(RP_DP,TSL)) = YES;                                                                     (L18)
    RP_DPL(RP_DP(R,P),TSL)\$(RLUP(R,'DAYNITE',TSL)\$PRC_TSL(R,P,'DAYNITE')) = ORD(TSL)>1;                   (L19)
    ACT_CSTUP(RTP(R,V,P),TSL,CUR)\$RP_DP(R,P) = 0;                                                         (L20)
    ACT_CSTSD(RTP(R,V,P),UPT,'FX',CUR)\$(RDCUR(R,CUR)\$RP_DP(R,P)) = ACT_CSTSD(RTP,UPT,'UP',CUR)+ACT_CSTSD(RTP,'HOT','LO',CUR);   (L21)
    ACT_CSTUP(RTP(R,V,P),TSL,CUR)\$RP_DPL(R,P,TSL) \$=SUM(UPT\$ACT_CSTSD(RTP,UPT,'FX',CUR),EPS);            (L22)
    RP_UPT(RP_DP,UPT,'LO')=DIAG('HOT',UPT); LOOP(V,RP_UPT(R,P,UPT,BD('UP'))\$ACT_SDTIME(R,V,P,UPT,BD)=YES);   (L23)
    ACT_MAXNON(R,V,P,UPT)\$((NOT ACT_MAXNON(R,V,P,UPT))\$RP_DP(R,P)) = EPS;                                 (L26)
    DP_NON(RTP(R,V,P),UPT,TSL,'UP')\$((ACT_MAXNON(RTP,UPT)<8760/G_CYCLE(TSL))\$RP_DPL(R,P,TSL)) = ACT_MAXNON(RTP,UPT)/8760;   (L27)
    DP_NON(RTP(R,V,P),'WARM',TSL,'LO')\$RP_DP(R,P) = DP_NON(RTP,'HOT',TSL,'UP');                           (L28)
    DP_NON(RTP(R,V,P),UPT,TSL,'LO')\$RP_DP(R,P) = MAX(DP_NON(RTP,UPT,TSL,'LO'),ACT_TIME(RTP,'LO')/8760);   (L29)
    DP_NON(RTP(R,V,P),UPT,TSL,BDNEQ(BD))\$RP_DP(R,P) = DP_NON(RTP,UPT,TSL,BD)+(ACT_SDTIME(RTP,UPT,'UP')+ACT_SDTIME(RTP,'HOT','LO'))/8760;   (L30)
    DP_NON(RTP(R,V,P),UPT,TSL,'UP')\$(DP_NON(RTP,UPT,TSL,'UP')\$RP_DP(R,P)) = DP_NON(RTP,UPT,TSL,'UP')-DP_NON(RTP,UPT,TSL,'LO');   (L31)
    DP_NON(RTP,'COLD',TSL,'UP') = 0;                                                                      (L32)
    ACT_SDTIME(RTP(R,V,P),UPT,BD)\$(NOT RP_UPT(R,P,UPT,BD)) = 0;                                           (L35)
    DP_PSUD(RTP,UPT,BDNEQ(BD))\$((ACT_SDTIME(RTP,UPT,BD)>0)\$ACT_SDTIME(RTP,UPT,BD)) = ACT_MINLD(RTP)/ACT_SDTIME(RTP,UPT,BD);   (L36)
    ACT_LOSSD(RTP,UPT,BD)\$(ACT_MINLD(RTP)\$DP_PSUD(RTP,UPT,BD)<=DP_PSUD(RTP,UPT,BD)) = 0;                  (L37)
    OPTION CLEAR=TRACKP,DP_LOSD<ACT_LOSSD; DP_LOSD(RTP(R,V,P))\$RP_PL(R,P,'N')\$=RP_PL(R,P,'FX');           (L38)
    ACT_LOSPL(DP_LOSD(RTP(R,V,P)),'FX')\$(ACT_LOSPL(RTP,'FX')=0) = .01**(1\$RP_PL(R,P,'N'));               (L39)
    ACT_LOSSD(RTP,UPT,BD)\$((ACT_LOSSD(RTP,UPT,BD)<ACT_LOSPL(RTP,'FX'))\$ACT_LOSSD(RTP,UPT,BD)) = 0;       (L40)
    DP_PSUD(DP_LOSD(RTP(R,V,P)),UPT,BDNEQ(BD)) = (DP_PSUD(RTP,UPT,BD)*(ACT_LOSSD(RTP,UPT,BD)/ACT_LOSPL(RTP,'FX')-1\$RP_PL(R,P,'N'))/(ACT_MINLD(RTP)-DP_PSUD(RTP,UPT,BD)))\$ACT_LOSSD(RTP,UPT,BD);   (L41)

Notes on the GAMS semantics kept here:

- An EPS counts as a value in a `\$` condition and in `\$=`, and is zero in
  arithmetic and comparisons: L26 stores EPS for every missing ACT_MAXNON, so
  L27 (EPS < 8760/G_CYCLE) stores an EPS DP_NON 'UP', which L31 then turns
  into minus the 'LO' value. L22 stores EPS start-up costs, which give the
  process its RP_UPS and RPC_CUR in eqactups.vda L16-18.
- L23, L32 and L35-41 are not limited to RP_DP: they act on any process with
  ACT_SDTIME or ACT_LOSSD data. V of L23 and L26 is MODLYEAR.
- L37: `\$` binds tighter than `<=`, so the test is
  (ACT_MINLD\$DP_PSUD) <= DP_PSUD, true wherever DP_PSUD is zero.
- L38: DP_LOSD takes every year of ACT_LOSSD (years outside RTP too), then
  the RTP of processes with partial-load losses given both ways.
- L39: `.01**1` is GAMS's real power (0.010000000000000004, `gpow`); the
  exponent is 0 for a DP_LOSD member without RP_PL 'N', giving 1.
- L41 is evaluated left to right, as GAMS does.

With no ACT_CSTSD, ACT_SDTIME or ACT_LOSSD only L15 and L38-39 act: RP_UPT
and TRACKP are emptied, DP_LOSD and the ACT_LOSPL 'FX' default are set.

GAMS: eqlducs.vda L12-41, v4.9.7.
"""
function eqlducs_prep!(tm)
    d = tm.data
    S(name, n) = gset_opt(d, name, n)
    rp, rtp, rp_pl, rp_upl = S("RP", 2), S("RTP", 3), S("RP_PL", 3), S("RP_UPL", 3)
    upts = [k[1] for k in S("UPT", 1).keys]
    tsls = [k[1] for k in S("TSLVL", 1).keys]
    cstsd, sdtime, lossd = gvalues(tm, "ACT_CSTSD", 6), gvalues(tm, "ACT_SDTIME", 5), gvalues(tm, "ACT_LOSSD", 5)
    minld, act_time = gparam_opt(d, "ACT_MINLD", 3), gparam_opt(d, "ACT_TIME", 4)
    # L15
    rp_upt = Set{NTuple{4,String}}((k[1], k[3], k[4], k[5]) for k in keys(cstsd))
    trackp = Set{NTuple{2,String}}((k[1], k[2]) for k in rp_upt)
    # L16-17
    rp_dp = gmembers(tm, "RP_DP", 2)
    for k in trackp
        (k in rp && (k[1], k[2], "FX") in rp_upl) && push!(rp_dp, k)
    end
    if !isempty(rp_dp)
        prc_ts = S("PRC_TS", 3)
        for (r, p, s, _) in S("RPS_CAFLAC", 4).keys
            ((r, p) in rp && (r, p, s) in prc_ts) && delete!(rp_dp, (r, p))
        end
    end
    isdp(r, p) = (r, p) in rp_dp
    rtp_dp = isempty(rp_dp) ? NTuple{3,String}[] : [k for k in rtp.keys if isdp(k[1], k[3])]
    # L18-19
    rp_dpl = gmembers(tm, "RP_DPL", 3)
    prc_tsl, rlup = S("PRC_TSL", 3), S("RLUP", 3)
    if !isempty(rp_dp)
        for (r, p, tsl) in prc_tsl.keys
            isdp(r, p) && push!(rp_dpl, (r, p, tsl))
        end
        for (r, p) in rp_dp, tsl in tsls
            ((r, p, "DAYNITE") in prc_tsl && (r, "DAYNITE", tsl) in rlup) || continue
            tsl != first(tsls) ? push!(rp_dpl, (r, p, tsl)) : delete!(rp_dpl, (r, p, tsl))    # ORD(TSL)>1
        end
    end
    dpl_of_rp = Dict{NTuple{2,String},Vector{String}}()                    # (R,P) => TSL with RP_DPL
    foreach(k -> pushat!(dpl_of_rp, (k[1], k[2]), k[3]), rp_dpl)
    nostr = String[]
    # L20
    cstup = gvalues(tm, "ACT_CSTUP", 5)
    isempty(rp_dp) || filter!(kv -> !((kv[1][1], kv[1][2], kv[1][3]) in rtp && isdp(kv[1][1], kv[1][3])), cstup)
    # L21
    cur_of_r = Dict{String,Vector{String}}()
    foreach(k -> pushat!(cur_of_r, k[1], k[2]), S("RDCUR", 2).keys)
    for (r, v, p) in rtp_dp, upt in upts, cur in get(cur_of_r, r, nostr)
        gassign!(cstsd, (r, v, p, upt, "FX", cur), gv(cstsd, (r, v, p, upt, "UP", cur)) + gv(cstsd, (r, v, p, "HOT", "LO", cur)))
    end
    # L22: every CUR with an ACT_CSTSD entry
    curs = unique!([k[6] for k in keys(cstsd)])
    for (r, v, p) in rtp_dp, tsl in get(dpl_of_rp, (r, p), nostr), cur in curs
        any(upt -> !iszero(gv(cstsd, (r, v, p, upt, "FX", cur))), upts) && gassign!(cstup, (r, v, p, tsl, cur), GEPS)
    end
    # L23
    modlyear = S("MODLYEAR", 1)
    for (r, p) in rp_dp, upt in upts
        upt == "HOT" ? push!(rp_upt, (r, p, upt, "LO")) : delete!(rp_upt, (r, p, upt, "LO"))
    end
    for (r, v, p, upt, bd) in keys(sdtime)
        (bd == "UP" && (v,) in modlyear) && push!(rp_upt, (r, p, upt, "UP"))
    end
    # L26
    maxnon = gvalues(tm, "ACT_MAXNON", 4)
    for (r, p) in rp_dp, (v,) in modlyear.keys, upt in upts
        haskey(maxnon, (r, v, p, upt)) || gassign!(maxnon, (r, v, p, upt), GEPS)
    end
    # L27-32
    dp_non = gvalues(tm, "DP_NON", 6)
    g_cycle = gparam_opt(d, "G_CYCLE", 1)
    for (r, v, p) in rtp_dp, upt in upts, tsl in get(dpl_of_rp, (r, p), nostr)                   # L27
        mx = gv(maxnon, (r, v, p, upt))
        mx.v < 8760 / gv(g_cycle, (tsl,)).v && gassign!(dp_non, (r, v, p, upt, tsl, "UP"), mx / 8760)
    end
    for (r, v, p) in rtp_dp, tsl in tsls                                                        # L28
        gassign!(dp_non, (r, v, p, "WARM", tsl, "LO"), gv(dp_non, (r, v, p, "HOT", tsl, "UP")))
    end
    for (r, v, p) in rtp_dp, upt in upts, tsl in tsls                                           # L29
        gassign!(dp_non, (r, v, p, upt, tsl, "LO"), gmax(gv(dp_non, (r, v, p, upt, tsl, "LO")), gv(act_time, (r, v, p, "LO")) / 8760))
    end
    for (r, v, p) in rtp_dp, upt in upts, tsl in tsls, bd in ("LO", "UP")                       # L30
        gassign!(dp_non, (r, v, p, upt, tsl, bd),
                 gv(dp_non, (r, v, p, upt, tsl, bd)) + (gv(sdtime, (r, v, p, upt, "UP")) + gv(sdtime, (r, v, p, "HOT", "LO"))) / 8760)
    end
    for (r, v, p) in rtp_dp, upt in upts, tsl in tsls                                           # L31
        up = gv(dp_non, (r, v, p, upt, tsl, "UP"))
        iszero(up) || gassign!(dp_non, (r, v, p, upt, tsl, "UP"), up - gv(dp_non, (r, v, p, upt, tsl, "LO")))
    end
    filter!(kv -> !(kv[1][4] == "COLD" && kv[1][6] == "UP" && (kv[1][1], kv[1][2], kv[1][3]) in rtp), dp_non)   # L32
    # L35
    filter!(kv -> !((kv[1][1], kv[1][2], kv[1][3]) in rtp && !((kv[1][1], kv[1][3], kv[1][4], kv[1][5]) in rp_upt)), sdtime)
    # L36
    psud = gvalues(tm, "DP_PSUD", 5)
    for (k, x) in sdtime
        ((k[1], k[2], k[3]) in rtp && k[5] in ("LO", "UP") && x > 0) || continue
        gassign!(psud, k, gv(minld, (k[1], k[2], k[3])) / x)
    end
    # L37
    for k in collect(keys(lossd))
        (k[1], k[2], k[3]) in rtp || continue
        ps = gv(psud, k)
        (iszero(ps) ? 0.0 : gv(minld, (k[1], k[2], k[3])).v) <= ps.v && delete!(lossd, k)
    end
    # L38
    empty!(trackp)
    dp_losd = Set{NTuple{3,String}}((k[1], k[2], k[3]) for k in keys(lossd))
    for (r, v, p) in rtp.keys
        ((r, p, "N") in rp_pl && (r, p, "FX") in rp_pl) && push!(dp_losd, (r, v, p))
    end
    # L39
    lospl = gvalues(tm, "ACT_LOSPL", 4)
    for (r, v, p) in dp_losd
        ((r, v, p) in rtp && gv(lospl, (r, v, p, "FX")).v == 0) || continue
        gassign!(lospl, (r, v, p, "FX"), gpow(GNum(0.01), GNum((r, p, "N") in rp_pl ? 1.0 : 0.0)))
    end
    # L40
    for (k, x) in collect(lossd)
        ((k[1], k[2], k[3]) in rtp && x < gv(lospl, (k[1], k[2], k[3], "FX")).v) && delete!(lossd, k)
    end
    # L41
    for (r, v, p) in dp_losd
        (r, v, p) in rtp || continue
        isn = (r, p, "N") in rp_pl ? 1 : 0
        for upt in upts, bd in ("LO", "UP")
            k = (r, v, p, upt, bd)
            ls = gv(lossd, k)
            if iszero(ls)
                delete!(psud, k)
            else
                ps = gv(psud, k)
                gassign!(psud, k, ps * (ls / gv(lospl, (r, v, p, "FX")) - isn) / (gv(minld, (r, v, p)) - ps))
            end
        end
    end
    gput!(tm, "RP_UPT", rp_upt); gput!(tm, "TRACKP", trackp); gput!(tm, "RP_DP", rp_dp); gput!(tm, "RP_DPL", rp_dpl)
    gput!(tm, "ACT_CSTUP", cstup); gput!(tm, "ACT_CSTSD", cstsd); gput!(tm, "ACT_MAXNON", maxnon); gput!(tm, "DP_NON", dp_non)
    gput!(tm, "ACT_SDTIME", sdtime); gput!(tm, "DP_PSUD", psud); gput!(tm, "ACT_LOSSD", lossd); gput!(tm, "DP_LOSD", dp_losd)
    gput!(tm, "ACT_LOSPL", lospl)
    return tm
end

"""
    eqlducs_equ!(tm) -> tm

The EQU section of eqlducs.vda, run by equ_ext.vda L91 after the dispatching
preparation of eqactups.vda (L90; `eqactups_prep!`):

    RP_UPS(RP_DP,TSL,L)=NO;                                                                 (L46)
    RP_UPC(RP_DP,TSL,BD)=NO;                                                                (L47)
    AFUPS(R,T,P,S)\$RP_DP(R,P)=NO;                                                           (L48)
    RPS_UPS(PRC_TS(RP_DP,S))=YES;                                                           (L49)
    RP_UX(RP)\$(NOT PRC_VINT(RP))\$=RP_DP(RP); RTP_VARP(RTP(R,T,P))\$RP_UX(R,P)=YES;          (L50)
    RP_UPS(RP_DP(R,P),TSL,'FX')\$=SUM(RLUP(R,TSLVL,TSL)\$PRC_TSL(R,P,TSLVL),1);              (L51)

A unit-commitment process loses the linear dispatching features that do not
fit it: its start-up levels, cycling constraints and the availability rows
EQ_CAPLOAD. It keeps the timeslices of the levels above its own that
eqactups.vda L21 gave RPS_UPS, and gets RP_UPS 'FX' at the level directly
above its own (EQE_ACTUPS and EQL_ACTUPS for that level). L47 removes the
'LO', 'FX' and 'UP' entries of RP_UPC; an 'N' entry stays. The AFUPS entries
taken out by L48 are not given back to AFS, in GAMS either.

GAMS: eqlducs.vda L44-51, v4.9.7.
"""
function eqlducs_equ!(tm::TimesModel)
    d = tm.data
    rp_dp = gset_opt(d, "RP_DP", 2)
    isempty(rp_dp) && return tm
    S(name, n) = gset_opt(d, name, n)
    isdp(r, p) = (r, p) in rp_dp
    rp_ups = filter!(k -> !isdp(k[1], k[2]), gmembers(tm, "RP_UPS", 4))                       # L46
    rp_upc = filter!(k -> !(isdp(k[1], k[2]) && k[4] in _SLS_BD), gmembers(tm, "RP_UPC", 4))  # L47
    afups = filter!(k -> !isdp(k[1], k[3]), gmembers(tm, "AFUPS", 4))                         # L48
    rps_ups = gmembers(tm, "RPS_UPS", 3)                                                      # L49
    for k in S("PRC_TS", 3).keys
        isdp(k[1], k[2]) && push!(rps_ups, k)
    end
    rp, prc_vint, T = S("RP", 2), S("PRC_VINT", 2), S("MILESTONYR", 1)                        # L50
    rp_ux = gmembers(tm, "RP_UX", 2)
    for k in rp_dp.keys
        (k in rp && !(k in prc_vint)) && push!(rp_ux, k)
    end
    rtp_varp = gmembers(tm, "RTP_VARP", 3)
    for (r, t, p) in S("RTP", 3).keys
        ((t,) in T && (r, p) in rp_ux) && push!(rtp_varp, (r, t, p))
    end
    prc_tsl = S("PRC_TSL", 3)                                                                 # L51
    for (r, lv, tsl) in S("RLUP", 3).keys, (rr, p) in rp_dp.keys
        (rr == r && (r, p, lv) in prc_tsl) && push!(rp_ups, (r, p, tsl, "FX"))
    end
    gput!(tm, "RP_UPS", rp_ups); gput!(tm, "RP_UPC", rp_upc); gput!(tm, "AFUPS", afups); gput!(tm, "RPS_UPS", rps_ups)
    gput!(tm, "RP_UX", rp_ux); gput!(tm, "RTP_VARP", rtp_varp)
    return tm
end

"""
    eq_lducs!(tm) -> Int

The seven equation families of unit commitment by start-up type (macros
expanded; see the head of this file):

    eq_sdlogic(RTP_VINTYR(R,V,T,P),TSL,S,LNX(L))\$(TS_GROUP(R,TSL,S)\$RP_DPL(R,P,TSL))..
      (SUM(TS(S--RS_STG(R,S)),VAR_UDP(R,V,T,P,TS,'N')-VAR_UDP(R,V,T,P,S,'N')) - SUM(BD,VAR_UPS(R,V,T,P,S,BD)*BDSIG(BD)))\$IPS(L) +
      (VAR_UPS(R,V,T,P,S,'UP') - SUM(RP_UPT(R,P,UPT,'UP'),VAR_UPT(R,V,T,P,S,UPT)))\$BD(L)
      =E= 0;

    eq_sudupt(RTP_VINTYR(R,V,T,P),TSL,S,UPT)\$(DP_NON(R,V,P,UPT,TSL,'UP')\$TS_GROUP(R,TSL,S)\$RP_DPL(R,P,TSL))..
      VAR_UPT(R,V,T,P,S,UPT) =L=
      SUM((RS_UP(R,S,JS),RJ_SL(R,JS,SL))\$(ORD(S)<>ORD(SL)),
        VAR_UPS(R,V,T,P,SL,'LO')\$(MOD(RS_HR(R,S)-RS_HR(R,SL)-DP_NON(R,V,P,UPT,TSL,'LO')+(G_YRFR(R,SL)/4+G_YRFR(R,S))/RS_STGPRD(R,S)+2/JS_CCL(R,JS),1/JS_CCL(R,JS))
                                  <DP_NON(R,V,P,UPT,TSL,'UP')*(1+sdtol)+G_YRFR(R,S)/RS_STGPRD(R,S)/2));

    eq_sdslant(RTP_VINTYR(R,V,T,P),TSL,S)\$(TS_GROUP(R,TSL,S)\$RP_DPL(R,P,TSL))..
      VAR_UDP(R,V,T,P,S,'N') =E= SUM(RS_BELOW1(R,TS,S),VAR_UPS(R,V,T,P,TS,'FX')-CAPUPS)\$PRC_TS(R,P,S) + (CAPUPS) - VAR_UPS(R,V,T,P,S,'N') -
      SUM(RP_UPT(R,P,UPT,BD),
        SUM((RS_UP(R,S,JS),RJ_SL(R,JS,SL))\$(RS_MODUS(R,SL,JS,S)<ACT_SDTIME(R,V,P,UPT,BD)/8760*(1+sdtol)),
          VAR_UPT(R,V,T,P,SL,UPT)*(0\$DIAG(S,SL) +
            MAX(0,1-MOD(RS_HR(R,SL)-RS_HR(R,S)+SUDHFR(R,SL,-,S)+2/JS_CCL(R,JS),1/JS_CCL(R,JS))/(ACT_SDTIME(R,V,P,UPT,BD)/8760))*(1-DIAG(S,SL))))\$BDUPX(BD) +
        SUM((RS_UP(R,S,JS),RJ_SL(R,JS,SL))\$(RS_MODUS(R,S,JS,SL)<ACT_SDTIME(R,V,P,UPT,BD)/8760*(1+sdtol)),
          VAR_UPS(R,V,T,P,SL,BD)*(1\$DIAG(S,SL) +
            MAX(0,1-MOD(RS_HR(R,S)-RS_HR(R,SL)+SUDHFR(R,SL,-,S)+2/JS_CCL(R,JS),1/JS_CCL(R,JS))/(ACT_SDTIME(R,V,P,UPT,BD)/8760))*(1-DIAG(S,SL))))\$BDLOX(BD));

    eq_sdminon(RTP_VINTYR(R,V,T,P),S)\$(PRC_TS(R,P,S)\$RP_DP(R,P))..
      VAR_UDP(R,V,T,P,S,'N')+SUM(RS_BELOW1(R,TS,S),VAR_UDP(R,V,T,P,TS,'FX')) =G= VAR_UDP(R,V,T,P,S,'FX')+VAR_UPS(R,V,T,P,S,'UP')+
      (SUM(RP_UPT(R,P,UPT,'UP')\$(G_YRFR(R,S)/RS_STGPRD(R,S)/2<=ACT_SDTIME(R,V,P,UPT,'UP')/8760),VAR_UPT(R,V,T,P,S,UPT))-VAR_UPS(R,V,T,P,S,'UP'))
        \$(SMIN(RP_UPT(R,P,UPT,'UP'),ACT_SDTIME(R,V,P,UPT,'UP')/8760)<G_YRFR(R,S)/RS_STGPRD(R,S)/2);

    eq_sudload(RTP_VINTYR(R,V,T,P),S)\$(PRC_TS(R,P,S)\$RP_DP(R,P))..
      VAR_ACT(R,V,T,P,S)/G_YRFR(R,S)/PRC_CAPACT(R,P) =E=
      (%CAPON%%UPSCAPS%)*ACT_MINLD(R,V,P) + VAR_UDP(R,V,T,P,S,'FX')*(COEF_AF(R,V,T,P,S,'UP')-ACT_MINLD(R,V,P)) [SPRSV: ABS, refused];

    eq_sudtime(RTP_VINTYR(R,V,T,P),TSL,S,BD)\$(PRC_TSL(R,P,TSL)\$TS_GROUP(R,TSL,S)\$ACT_TIME(R,V,P,BD)\$RP_DP(R,P))..
      SUM(BDLOX(BD), VAR_UPS(R,V,T,P,S,'N') - SUM((RS_UP(R,S,JS),RJ_SL(R,JS,SL)),
        VAR_UPS(R,V,T,P,SL,BD)\$(MOD(RS_HR(R,S)-RS_HR(R,SL)-ACT_SDTIME(R,V,P,'HOT','LO')/8760+G_YRFR(R,S)/RS_STGPRD(R,S)/2+2/JS_CCL(R,JS),1/JS_CCL(R,JS))<ACT_TIME(R,V,P,BD)/8760))) +
      SUM(BDUPX(BD), VAR_UDP(R,V,T,P,S,'N') - SUM((RS_UP(R,S,JS),RJ_SL(R,JS,SL)), SUM(RP_UPT(R,P,UPT,BD),
        VAR_UPT(R,V,T,P,SL,UPT)\$(MOD(RS_HR(R,S)-RS_HR(R,SL)+1/JS_CCL(R,JS),1/JS_CCL(R,JS))
                                 <(ACT_TIME(R,V,P,BD)-ACT_SDTIME(R,V,P,'HOT','LO')-ACT_SDTIME(R,V,P,UPT,BD))/8760+G_YRFR(R,SL)/RS_STGPRD(R,S)/2))))
      =G= 0;

    eq_sudpll(RTP_VINTYR(R,V,T,P),TSL,S)\$(TS_GROUP(R,TSL,S)\$PRC_TSL(R,P,TSL)\$DP_LOSD(R,V,P)\$RP_DP(R,P))..
      VAR_UPS(R,V,T,P,S,'FX') =G=
      SUM(RP_UPT(R,P,UPT,BD),
        SUM((RS_UP(R,S,JS),RJ_SL(R,JS,SL))\$(MOD((RS_HR(R,S)-RS_HR(R,SL))*BDSIG(BD)+G_YRFR(R,SL)/RS_STGPRD(R,S)/2+2/JS_CCL(R,JS),1/JS_CCL(R,JS))<ACT_SDTIME(R,V,P,UPT,BD)/8760*(1+sdtol)),
          (1+MIN(1,MOD((RS_HR(R,S)-RS_HR(R,SL))*BDSIG(BD)+SUDHFR(R,SL,-,S)+2/JS_CCL(R,JS),1/JS_CCL(R,JS))/(ACT_SDTIME(R,V,P,UPT,BD)/8760))*(DP_PSUD(R,V,P,UPT,BD)-1)) *
          (VAR_UPT(R,V,T,P,SL,UPT)\$BDUPX(BD) + VAR_UPS(R,V,T,P,SL,BD)\$BDLOX(BD)))) * PRC_CAPACT(R,P)*G_YRFR(R,S)*ACT_MINLD(R,V,P);

How they are read:

- eq_sdlogic has two rows per timeslice: L = 'N' (IPS) balances the on-line
  capacity with the start-ups and shut-downs between the timeslice before S
  in its cycle (`stg_prev`) and S; L = 'FX' (BD) splits the start-ups by type.
- The timeslice tests are made in Float64 in GAMS's order of operations; a
  term whose test fails, or whose coefficient is zero, is not in the row
  (the VAR_UPT of S itself in eq_sdslant has the coefficient 0). A row whose
  sums are empty is still generated (eq_sudupt: VAR_UPT =L= 0).
- eq_sdslant adds and subtracts CAPUPS for a timeslice of the process with a
  parent; the terms cancel as they do in GAMS.
- eq_sdminon: SMIN over no start-up type is +INF, so the condition fails;
  when it holds, VAR_UPS(S,'UP') cancels.
- ACT_TIME and ACT_SDTIME are read at the vintage V.
- Every row has the last index '1' (%SWX%), left out of the statements above.

Returns the number of rows.

GAMS: eqlducs.vda L53-124, v4.9.7.
"""
function eq_lducs!(tm::TimesModel)
    d = tm.data
    S(name, n) = gset_opt(d, name, n)
    P(name, n) = gparam_opt(d, name, n)
    rp_dp, rp_dpl = S("RP_DP", 2), S("RP_DPL", 3)
    (isempty(rp_dp) && isempty(rp_dpl)) && return 0
    modlyear, T = S("MODLYEAR", 1), S("MILESTONYR", 1)
    tx = eq_periods(tm)   # %R_V_T%: SUBT in a stepped run (maindrv.mod L38-40)
    vt_ok(v, t) = (v,) in modlyear && (t,) in tx
    off = rts_off(tm)                    # RTS(s): S+NORTS(R,T,S) with dynamic timeslices (M1.3 change 67)
    vt_of_rp = indexby(gset(tm, "RTP_VINTYR"), (1, 4))                     # (r,p) -> RTP_VINTYR(r,v,t,p)
    prc_ts, prc_tsl = S("PRC_TS", 3), S("PRC_TSL", 3)
    ts_of_rp = indexby(prc_ts, (1, 2))                                     # (r,p) -> PRC_TS(r,p,ts)
    tsl_of_rp = indexby(prc_tsl, (1, 2))                                   # (r,p) -> PRC_TSL(r,p,tsl)
    prc_vint, rp_ux, rps_ups, dp_losd = S("PRC_VINT", 2), S("RP_UX", 2), S("RPS_UPS", 3), S("DP_LOSD", 3)
    ups_of_rp = indexby(rps_ups, (1, 2))                                   # (r,p) -> RPS_UPS(r,p,ts)
    upt_of_rp = indexby(S("RP_UPT", 4), (1, 2))                            # (r,p) -> RP_UPT(r,p,upt,bd)
    tsmap = S("TS_MAP", 3)                                                 # (r,ts,s): ts at or above s
    above_of = indexby(S("RS_BELOW", 3), (1, 3))                           # (r,s) -> RS_BELOW(r,all_ts,s)
    parent_of = indexby(S("RS_BELOW1", 3), (1, 3))                         # (r,s) -> RS_BELOW1(r,ts,s)
    group_of = indexby(S("TS_GROUP", 3), (1, 2))                           # (r,tsl) -> TS_GROUP(r,tsl,s)
    rsup_of_rs = indexby(S("RS_UP", 4), (1, 2))                            # (r,s) -> RS_UP(r,s,j,s')
    rjsl_of_rjs = indexby(S("RJ_SL", 4), (1, 2, 3))                        # (r,j,s') -> RJ_SL(r,j,s',sl)
    upts = [k[1] for k in S("UPT", 1).keys]
    coef_cpt, coef_af, pasti = P("COEF_CPT", 4), P("COEF_AF", 6), P("NCAP_PASTI", 3)
    capact, yrfr, stgprd = P("PRC_CAPACT", 2), P("G_YRFR", 2), P("RS_STGPRD", 2)
    minld, act_time, sdtime = P("ACT_MINLD", 3), P("ACT_TIME", 4), P("ACT_SDTIME", 5)
    dp_non, dp_psud = P("DP_NON", 6), P("DP_PSUD", 5)
    rs_hr, js_ccl, modus = P("RS_HR", 2), P("JS_CCL", 3), P("RS_MODUS", 5)
    x = (prev = Dict((k[1], k[2]) => k[3] for k in S("RS_PREV", 3)), rs_stg = P("RS_STG", 2))
    no3, no4 = NTuple{3,String}[], NTuple{4,String}[]
    one = GNum(1.0)
    ups!(e, c, r, v, t, p, s, l) = addterm!(e, GNum(c), tm, "VAR_UPS", r, v, t, p, s, l)
    udp!(e, c, r, v, t, p, s, l) = addterm!(e, GNum(c), tm, "VAR_UDP", r, v, t, p, s, l)
    upt!(e, c, r, v, t, p, s, u) = addterm!(e, GNum(c), tm, "VAR_UPT", r, v, t, p, s, u)
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
    # c * CAPUPS
    function capups!(e, c::GNum, r, v, t, p, s)
        capon!(e, c, r, v, t, p)
        for (_, a, _) in get(above_of, (r, s), no3)
            (r, p, a) in rps_ups && ups!(e, -c, r, v, t, p, a, "N")
        end
        return e
    end
    hr(r, s) = gv(rs_hr, (r, s)).v
    yf(r, s) = gv(yrfr, (r, s)).v
    sp(r, s) = gv(stgprd, (r, s)).v
    sudhfr(r, a, b) = (yf(r, a) - yf(r, b)) / 2 / sp(r, a)                 # SUDHFR(r,a,-,b)
    sd(r, v, p, u, bd) = gv(sdtime, (r, v, p, u, bd)).v
    # (RS_UP(R,S,JS),RJ_SL(R,JS,SL)): the timeslices SL of the cycle of S, with 1/JS_CCL and 2/JS_CCL
    cycle_cache = Dict{NTuple{2,String},Vector{Tuple{String,String,String,Float64,Float64}}}()
    function cycle(r, s)
        get!(cycle_cache, (r, s)) do
            out = Tuple{String,String,String,Float64,Float64}[]
            for (_, _, j, s2) in get(rsup_of_rs, (r, s), no4)
                ccl = gv(js_ccl, (r, j, s2)).v
                for (_, _, _, sl) in get(rjsl_of_rjs, (r, j, s2), no4)
                    push!(out, (j, s2, sl, 1 / ccl, 2 / ccl))
                end
            end
            out
        end
    end
    n = 0

    # the rows by timeslice level: (r,v,t,p,tsl,s) with RP_DPL(r,p,tsl) and TS_GROUP(r,tsl,s)
    lvl_rows = NTuple{6,String}[]
    for (r, p, tsl) in rp_dpl, (_, _, s) in get(group_of, (r, tsl), no3), (_, v, t, _) in get(vt_of_rp, (r, p), no4)
        vt_ok(v, t) && !off(r, t, s) && push!(lvl_rows, (r, v, t, p, tsl, s))
    end

    # eq_sdlogic, L67-70
    rows7 = NTuple{7,String}[(k..., l) for k in lvl_rows for l in ("N", "FX")]                 # LNX(L)
    for (r, v, t, p, tsl, s, l) in gams_sort!(rows7, d)
        lhs = JuMP.AffExpr(0.0)
        if l == "N"                                                        # $IPS(L)
            udp!(lhs, one, r, v, t, p, stg_prev(x, r, s), "N")
            udp!(lhs, -one, r, v, t, p, s, "N")
            ups!(lhs, -one, r, v, t, p, s, "LO")                           # -SUM(BD, VAR_UPS(..,BD)*BDSIG(BD))
            ups!(lhs, one, r, v, t, p, s, "UP")
        else                                                               # $BD(L)
            ups!(lhs, one, r, v, t, p, s, "UP")
            for (_, _, u, bd) in get(upt_of_rp, (r, p), no4)
                bd == "UP" && upt!(lhs, -one, r, v, t, p, s, u)
            end
        end
        gconstraint!(tm, "eq_sdlogic", (r, v, t, p, tsl, s, l, "1"), "E", lhs, JuMP.AffExpr(0.0)) === nothing || (n += 1)
    end

    # eq_sudupt, L74-77
    empty!(rows7)
    for (r, v, t, p, tsl, s) in lvl_rows, u in upts
        iszero(gv(dp_non, (r, v, p, u, tsl, "UP"))) || push!(rows7, (r, v, t, p, tsl, s, u))
    end
    for (r, v, t, p, tsl, s, u) in gams_sort!(rows7, d)
        lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
        upt!(lhs, one, r, v, t, p, s, u)
        lo, up = gv(dp_non, (r, v, p, u, tsl, "LO")).v, gv(dp_non, (r, v, p, u, tsl, "UP")).v
        for (_, _, sl, c1, c2) in cycle(r, s)
            sl == s && continue                                            # $(ORD(S)<>ORD(SL))
            m = rem(hr(r, s) - hr(r, sl) - lo + (yf(r, sl) / 4 + yf(r, s)) / sp(r, s) + c2, c1)
            m < up * (1 + _SD_TOL) + yf(r, s) / sp(r, s) / 2 && ups!(rhs, one, r, v, t, p, sl, "LO")
        end
        gconstraint!(tm, "eq_sudupt", (r, v, t, p, tsl, s, u, "1"), "L", lhs, rhs) === nothing || (n += 1)
    end

    # eq_sdslant, L81-90
    for (r, v, t, p, tsl, s) in gams_sort!(copy(lvl_rows), d)
        lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
        udp!(lhs, one, r, v, t, p, s, "N")
        if (r, p, s) in prc_ts
            for (_, ts, _) in get(parent_of, (r, s), no3)
                ups!(rhs, one, r, v, t, p, ts, "FX")
                capups!(rhs, -one, r, v, t, p, s)
            end
        end
        capups!(rhs, one, r, v, t, p, s)
        ups!(rhs, -one, r, v, t, p, s, "N")
        for (_, _, u, bd) in get(upt_of_rp, (r, p), no4)
            h = sd(r, v, p, u, bd) / 8760
            lim = h * (1 + _SD_TOL)
            for (j, s2, sl, c1, c2) in cycle(r, s)
                if bd in ("UP", "FX") && gv(modus, (r, sl, j, s2, s)).v < lim              # $BDUPX(BD)
                    k = sl == s ? 0.0 : max(0.0, 1 - rem(hr(r, sl) - hr(r, s) + sudhfr(r, sl, s) + c2, c1) / h)
                    upt!(rhs, -k, r, v, t, p, sl, u)
                end
                if bd in ("LO", "FX") && gv(modus, (r, s, j, s2, sl)).v < lim              # $BDLOX(BD)
                    k = sl == s ? 1.0 : max(0.0, 1 - rem(hr(r, s) - hr(r, sl) + sudhfr(r, sl, s) + c2, c1) / h)
                    ups!(rhs, -k, r, v, t, p, sl, bd)
                end
            end
        end
        gconstraint!(tm, "eq_sdslant", (r, v, t, p, tsl, s, "1"), "E", lhs, rhs) === nothing || (n += 1)
    end

    # the rows by timeslice of the process: (r,v,t,p,s) with PRC_TS(r,p,s) and RP_DP(r,p)
    ts_rows = NTuple{5,String}[]
    for (r, p) in rp_dp, (_, _, s) in get(ts_of_rp, (r, p), no3), (_, v, t, _) in get(vt_of_rp, (r, p), no4)
        vt_ok(v, t) && !off(r, t, s) && push!(ts_rows, (r, v, t, p, s))
    end
    gams_sort!(ts_rows, d)

    # eq_sdminon, L94-97
    for (r, v, t, p, s) in ts_rows
        lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
        udp!(lhs, one, r, v, t, p, s, "N")
        for (_, ts, _) in get(parent_of, (r, s), no3)
            udp!(lhs, one, r, v, t, p, ts, "FX")
        end
        udp!(rhs, one, r, v, t, p, s, "FX")
        ups!(rhs, one, r, v, t, p, s, "UP")
        half = yf(r, s) / sp(r, s) / 2
        starts = [u for (_, _, u, bd) in get(upt_of_rp, (r, p), no4) if bd == "UP"]
        if minimum(u -> sd(r, v, p, u, "UP") / 8760, starts; init=Inf) < half             # SMIN of nothing is +INF
            for u in starts
                half <= sd(r, v, p, u, "UP") / 8760 && upt!(rhs, one, r, v, t, p, s, u)
            end
            ups!(rhs, -one, r, v, t, p, s, "UP")
        end
        gconstraint!(tm, "eq_sdminon", (r, v, t, p, s, "1"), "G", lhs, rhs) === nothing || (n += 1)
    end

    # eq_sudload, L101-103
    for (r, v, t, p, s) in ts_rows
        lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
        addterm!(lhs, one / gv(yrfr, (r, s)) / gv(capact, (r, p)), tm, "VAR_ACT", r, v, t, p, s)
        ml = gv(minld, (r, v, p))
        capon!(rhs, ml, r, v, t, p)
        upscaps!(rhs, ml, r, v, t, p, s)
        udp!(rhs, gv(coef_af, (r, v, t, p, s, "UP")) - ml, r, v, t, p, s, "FX")
        gconstraint!(tm, "eq_sudload", (r, v, t, p, s, "1"), "E", lhs, rhs) === nothing || (n += 1)
    end

    # the rows at the level of the process: (r,v,t,p,tsl,s) with PRC_TSL(r,p,tsl), TS_GROUP(r,tsl,s) and RP_DP(r,p)
    own_rows = NTuple{6,String}[]
    for (r, p) in rp_dp, (_, _, tsl) in get(tsl_of_rp, (r, p), no3), (_, _, s) in get(group_of, (r, tsl), no3),
        (_, v, t, _) in get(vt_of_rp, (r, p), no4)

        vt_ok(v, t) && !off(r, t, s) && push!(own_rows, (r, v, t, p, tsl, s))
    end

    # eq_sudtime, L107-114
    empty!(rows7)
    for (r, v, t, p, tsl, s) in own_rows, bd in _SLS_BD
        iszero(gv(act_time, (r, v, p, bd))) || push!(rows7, (r, v, t, p, tsl, s, bd))
    end
    for (r, v, t, p, tsl, s, bd) in gams_sort!(rows7, d)
        lhs = JuMP.AffExpr(0.0)
        at, hotlo = gv(act_time, (r, v, p, bd)).v, sd(r, v, p, "HOT", "LO")
        if bd in ("LO", "FX")                                              # SUM(BDLOX(BD), ...): the minimum off-line time
            ups!(lhs, one, r, v, t, p, s, "N")
            for (_, _, sl, c1, c2) in cycle(r, s)
                rem(hr(r, s) - hr(r, sl) - hotlo / 8760 + yf(r, s) / sp(r, s) / 2 + c2, c1) < at / 8760 &&
                    ups!(lhs, -one, r, v, t, p, sl, bd)
            end
        end
        if bd in ("UP", "FX")                                              # SUM(BDUPX(BD), ...): the minimum on-line time
            udp!(lhs, one, r, v, t, p, s, "N")
            for (_, _, sl, c1, _) in cycle(r, s), (_, _, u, b) in get(upt_of_rp, (r, p), no4)
                b == bd || continue
                rem(hr(r, s) - hr(r, sl) + c1, c1) < (at - hotlo - sd(r, v, p, u, bd)) / 8760 + yf(r, sl) / sp(r, s) / 2 &&
                    upt!(lhs, -one, r, v, t, p, sl, u)
            end
        end
        gconstraint!(tm, "eq_sudtime", (r, v, t, p, tsl, s, bd, "1"), "G", lhs, JuMP.AffExpr(0.0)) === nothing || (n += 1)
    end

    # eq_sudpll, L118-124
    for (r, v, t, p, tsl, s) in gams_sort!(filter!(k -> (k[1], k[2], k[4]) in dp_losd, own_rows), d)
        lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
        ups!(lhs, one, r, v, t, p, s, "FX")
        scale = gv(capact, (r, p)) * gv(yrfr, (r, s)) * gv(minld, (r, v, p))
        for (_, _, u, bd) in get(upt_of_rp, (r, p), no4)
            h, sig, ps = sd(r, v, p, u, bd) / 8760, _ups_bdsig(bd), gv(dp_psud, (r, v, p, u, bd)).v
            for (_, _, sl, c1, c2) in cycle(r, s)
                rem((hr(r, s) - hr(r, sl)) * sig + yf(r, sl) / sp(r, s) / 2 + c2, c1) < h * (1 + _SD_TOL) || continue
                w = 1 + min(1.0, rem((hr(r, s) - hr(r, sl)) * sig + sudhfr(r, sl, s) + c2, c1) / h) * (ps - 1)
                bd in ("UP", "FX") && upt!(rhs, w * scale, r, v, t, p, sl, u)                  # $BDUPX(BD)
                bd in ("LO", "FX") && ups!(rhs, w * scale, r, v, t, p, sl, bd)                 # $BDLOX(BD)
            end
        end
        gconstraint!(tm, "eq_sudpll", (r, v, t, p, tsl, s, "1"), "G", lhs, rhs) === nothing || (n += 1)
    end
    return n
end
