# M1.3 (11a): ppmain.mod L800-821 (docs/m13-plan.md): the flow attributes
# levelled to the flow and process timeslices (pp_lvlfc.mod: FLO_COST,
# FLO_DELIV, FLO_SUB, FLO_TAX, FLO_PKCOI, FLO_BDLVL twice, ACT_FLO), the
# FLO_PKCOI default of 1 for the inputs of peak commodities, and the CHP
# attributes (pp_chp.mod: NCAP_CHPR, NCAP_CEH, NCAP_BPME, PRC_ACTFLO,
# FLO_SUM, FLO_SHAR, NCAP_PKCNT).
#
# GAMS: ppmain.mod L800-821, pp_lvlfc.mod L19-45, pp_chp.mod L9-71, v4.9.7.
#
# Index sets: R is REG, P is PRC, C and COM are COM, CG is COM_GRP, S and TS
# are ALL_TS, T is MILESTONYR, V is MODLYEAR, LL is ALLYEAR, BD is BND_TYPE
# (LO, FX, UP), CUR the currencies. RTP(R,T,P) and RTP(R,V,P) run over the
# milestones and the model years, RTP and RVP alone over every record (G8,
# G27). `$x` is true for EPS (G3) and `NOT x` false (G25); a numeric
# comparison takes EPS as 0 (G12); `$=` writes only a nonzero or EPS value
# (G24); a right-hand side that names the symbol being assigned reads it as
# it was before the statement (G11); a guarded expression is not evaluated
# where its guard is false (G14). The QA log (pp_chp.mod L66-70) is written
# in LOOP order (M1.3 change 25b-1).

"""
    ppmain_flo_symbols(tm) -> Vector{String}

The symbols ppmain.mod L800-821 settles that nothing later in the prelv ->
ppm segment changes (for the layer-1 check at the ppm checkpoint): the
flow attributes levelled by pp_lvlfc.mod, CHP_ELC, NCAP_CHPR, NCAP_CEH,
NCAP_BPME, PRC_ACTFLO, NCAP_PKCNT and COEF_RTP (cleared by pp_chp.mod L71);
FLO_BDLVL when FLO_BND and PRC_MARK have no data (ppmain.mod L998;
eqflomrk.mod L31). Left out: FLO_SUM (pp_lvlfs.mod, ppmain.mod L835),
FLO_SHAR (L840), PRC_ACT (pp_reduce.red L10), RVP (L1339), RPC_ACT (L837),
RP_GRP, TRACKPG, RP_PRC, TRACKP, TRACKPC and the scratch, which the replay
checks at L821 (scripts/m13_replay.jl, test/unit/test_m13_ppmain_flo.jl).
"""
function ppmain_flo_symbols(tm)
    out = ["FLO_COST", "FLO_DELIV", "FLO_SUB", "FLO_TAX", "FLO_PKCOI", "ACT_FLO", "CHP_ELC", "NCAP_CHPR", "NCAP_CEH",
           "NCAP_BPME", "PRC_ACTFLO", "NCAP_PKCNT", "COEF_RTP"]
    (isempty(gparam_opt(tm.data, "FLO_BND", 6).keys) && isempty(gparam_opt(tm.data, "PRC_MARK", 6).keys)) && push!(out, "FLO_BDLVL")
    return out
end

"""
    ppmain_flo!(tm) -> tm

ppmain.mod L800-821 on the state after `ppmain_tsattr!`: FLO_COST,
FLO_DELIV, FLO_SUB and FLO_TAX levelled to RPCS_VAR (flagged at year '0'
and taken off the other timeslices, %11 N), FLO_PKCOI to RPCS_VAR,
FLO_BDLVL to PRC_TS for groups and to RPCS_VAR for commodities, ACT_FLO to
RPS_S1 (filled from ANNUAL, %11 0); FLO_PKCOI 1 for the inputs and exports
of peak commodities without one; then pp_chp.mod.

GAMS: ppmain.mod L800-821, v4.9.7.
"""
function ppmain_flo!(tm)
    tr = TsTree(tm)
    tmem = Set(k[1] for k in gset(tm, "MILESTONYR").keys)
    modl = Set(k[1] for k in gset(tm, "MODLYEAR").keys)
    dyear = Set(k[1] for k in gset(tm, "DATAYEAR").keys)
    member(s) = Set(k[1] for k in gset(tm, s).keys)
    com, cg, cur, bd = member("COM"), member("COM_GRP"), member("CUR"), member("BD")
    rpc, rtp = gset(tm, "RPC").members, gset(tm, "RTP").members
    by3(s) = (d = Dict{NTuple{3,String},Vector{String}}(); foreach(k -> pushat!(d, (k[1], k[2], k[3]), k[4]), gset(tm, s).keys); d)
    by2(s) = (d = Dict{NTuple{2,String},Vector{String}}(); foreach(k -> pushat!(d, (k[1], k[2]), k[3]), gset(tm, s).keys); d)
    rpcs = by3("RPCS_VAR")                                              # (R,P,C) => S
    prcts, rps_s1 = by2("PRC_TS"), by2("RPS_S1")                        # (R,P) => S
    nothing_ = String[]
    ts_array = nothing
    lv(args...; kw...) = ((u7, a) = pp_lvlfc!(tm, tr, args...; kw...); a === nothing || (ts_array = a); u7)
    # L804-807: $BATINCLUDE pp_lvlfc.mod FLO_xxx 'P,C' RPCS_VAR ',CUR' ",'0','0'" ALL_TS DATAYEAR RPC(R,P,C) '' '' N
    for n in ("FLO_COST", "FLO_DELIV", "FLO_SUB", "FLO_TAX")
        lv(n, 6; sp=5, years=dyear, keyok=k -> k[4] in com && k[6] in cur, targets=k -> get(rpcs, (k[1], k[3], k[4]), nothing_),
           qual=k -> (k[1], k[3], k[4]) in rpc, p11="N")
    end
    # L808: $BATINCLUDE pp_lvlfc.mod FLO_PKCOI 'P,C' RPCS_VAR '' ",'0','0','0'" ALL_TS T RTP(R,T,P)
    lv("FLO_PKCOI", 5; sp=5, years=tmem, keyok=k -> k[4] in com, targets=k -> get(rpcs, (k[1], k[3], k[4]), nothing_),
       qual=k -> (k[1], k[2], k[3]) in rtp)
    # L809: $BATINCLUDE pp_lvlfc.mod FLO_BDLVL 'P' PRC_TS ',BD' ",'0','0'" ALL_TS T RTP(R,T,P) 0 ',CG' 1 $(C(CG)->ACTCG(CG))
    actcg = member("ACTCG")
    lv("FLO_BDLVL", 6; sp=5, years=tmem, keyok=k -> k[4] in cg && k[6] in bd, targets=k -> get(prcts, (k[1], k[3]), nothing_),
       qual=k -> (k[1], k[2], k[3]) in rtp, take=k -> !(k[4] in com) || k[4] in actcg, p11="1")
    # L810: $BATINCLUDE pp_lvlfc.mod FLO_BDLVL 'P,C' RPCS_VAR ',BD' ",'0','0'" ALL_TS T RTP(R,T,P) 0 '' 1 $RPC(R,P,C)
    lv("FLO_BDLVL", 6; sp=5, years=tmem, keyok=k -> k[4] in com && k[6] in bd, targets=k -> get(rpcs, (k[1], k[3], k[4]), nothing_),
       qual=k -> (k[1], k[2], k[3]) in rtp, take=k -> (k[1], k[3], k[4]) in rpc, p11="1")
    # L811: $BATINCLUDE pp_lvlfc.mod ACT_FLO 'P' RPS_S1 '' ",'0','0','0'" ALL_TS V RTP(R,V,P) 0 ',C' 0 $STOA(S)
    stoa = gvalues(tm, "STOA", 1)
    uncd7 = lv("ACT_FLO", 5; sp=5, years=modl, keyok=k -> k[4] in com, targets=k -> get(rps_s1, (k[1], k[3]), nothing_),
               qual=k -> (k[1], k[2], k[3]) in rtp, take=k -> !iszero(gv(stoa, (k[5],))), p11="0")

    # --- L814-818: FLO_PKCOI defaults to 1 ------------------------------------------------------------
    # L814-815: LOOP((RPC(R,P,C),COM_GMAP(COM_PEAK(R,CG),C))$(TOP(RPC,'IN')+RPC_IRE(RPC,'EXP')),
    #   IF(NOT SUM((RTP(R,T,P),RPCS_VAR(RPC,TS))$FLO_PKCOI(RTP,C,TS),1),TRACKPC(RPC)=YES))
    pkcoi = gvalues(tm, "FLO_PKCOI", 5)
    top, ire = gset(tm, "TOP").members, gset_opt(tm.data, "RPC_IRE", 4).members
    cpeak = gset_opt(tm.data, "COM_PEAK", 2).members
    peakc = Set((k[1], k[3]) for k in gset(tm, "COM_GMAP").keys if (k[1], k[2]) in cpeak)
    has_pk = Set((k[1], k[3], k[4]) for k in keys(pkcoi) if k[2] in tmem && (k[1], k[2], k[3]) in rtp && k[5] in get(rpcs, (k[1], k[3], k[4]), nothing_))
    trackpc = gmembers(tm, "TRACKPC", 3)
    for (r, p, c) in rpc
        ((r, c) in peakc && ((r, p, c, "IN") in top || (r, p, c, "EXP") in ire) && !((r, p, c) in has_pk)) && push!(trackpc, (r, p, c))
    end
    # L816: TRACKPC(PRC_PKNO(R,P),C)=NO
    pkno = gset_opt(tm.data, "PRC_PKNO", 2).members
    filter!(k -> !((k[1], k[2]) in pkno), trackpc)
    # L817: FLO_PKCOI(RTP(R,T,P),C,S)$(RPCS_VAR(R,P,C,S)$TRACKPC(R,P,C)) = 1.0
    tp_of = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> k[2] in tmem && pushat!(tp_of, (k[1], k[3]), k[2]), gset(tm, "RTP").keys)
    for (r, p, c) in trackpc, t in get(tp_of, (r, p), nothing_), s in get(rpcs, (r, p, c), nothing_)
        pkcoi[(r, t, p, c, s)] = 1.0
    end
    gput!(tm, "FLO_PKCOI", pkcoi)
    # L818: OPTION CLEAR=TRACKPC
    gput!(tm, "TRACKPC", Set{NTuple{3,String}}())

    # --- L821: $BATINCLUDE pp_chp.mod mod ---------------------------------------------------------------
    pp_chp!(tm, tr, modl)

    gput!(tm, "UNCD7", uncd7)
    ts_array === nothing || gput!(tm, "TS_ARRAY", Dict{Tuple{String},Float64}((s,) => v for (s, v) in ts_array))
    return tm
end

"""
    pp_chp!(tm, tr, modl) -> tm

pp_chp.mod: the CHP flow attributes. NCAP_CHPR LO and UP dropped where FX
is given; the slope NCAP_CEH from NCAP_CDME, NCAP_BPME and the largest
NCAP_CHPR; the overall efficiency as FLO_SUM; for CHP processes (when CHP
has members) the electricity outputs CHP_ELC, NCAP_BPME and NCAP_CEH for
back-pressure units, a maximum heat share, PRC_ACTFLO of the PG
commodities, the low-temperature heat FLO_SUM, the electricity and heat
FLO_SHAR, the ACT flows and NCAP_PKCNT per unit of electricity. PRC_ACT,
RVP, TRACKP, TRACKPG, RP_PRC, RP_GRP and COEF_RTP are cleared at the end.

GAMS: pp_chp.mod L9-71, v4.9.7.
"""
function pp_chp!(tm, tr::TsTree, modl)
    rtp = gset(tm, "RTP").members
    rtpV = gams_sort!([k for k in rtp if k[2] in modl], tm.data)
    chp = gset_opt(tm.data, "CHP", 2).members
    bds = [k[1] for k in gset(tm, "BD").keys]
    bdneq = [k[1] for k in gset(tm, "BDNEQ").keys]
    com = Set(k[1] for k in gset(tm, "COM").keys)
    chpr = gvalues(tm, "NCAP_CHPR", 4)
    cdme = gvalues(tm, "NCAP_CDME", 3)
    bpme = gvalues(tm, "NCAP_BPME", 3)
    ceh = gvalues(tm, "NCAP_CEH", 3)
    fsum = gvalues(tm, "FLO_SUM", 7)
    elc = Set((k[1], k[3]) for k in gset(tm, "NRG_TMAP").keys if k[2] == "ELC")
    by(itr, f, g) = (d = Dict{Any,Vector{Any}}(); foreach(k -> pushat!(d, f(k), g(k)), itr); d)
    rpc_pg = gset(tm, "RPC_PG").members
    pg_of = by(gset(tm, "RPC_PG").keys, k -> (k[1], k[2]), k -> k[3])
    none = Any[]
    # L12: NCAP_CHPR(RTP,BDNEQ)$NCAP_CHPR(RTP,'FX') = 0
    for k in collect(keys(chpr))
        (k[4] == "FX" && (k[1], k[2], k[3]) in rtp) && foreach(b -> delete!(chpr, (k[1], k[2], k[3], b)), bdneq)
    end
    # L13: COEF_RTP(RTP(R,V,P))$CHP(R,P) = MAX(0,SMAX(BD,NCAP_CHPR(RTP,BD)))
    coef = gvalues(tm, "COEF_RTP", 3)
    for k in rtpV
        (k[1], k[3]) in chp && gassign!(coef, k, gmax(GZERO, reduce(gmax, (gv(chpr, (k..., b)) for b in bds))))
    end
    # L16: NCAP_CEH(RTP)$((COEF_RTP(RTP)>0)$NCAP_CDME(RTP)) = MAX(.001,(NCAP_CDME(RTP)/NCAP_BPME(RTP)*(1+COEF_RTP(RTP))-1)/COEF_RTP(RTP))
    for k in rtp
        (gv(coef, k).v > 0 && haskey(cdme, k)) || continue
        c = gv(coef, k)
        gassign!(ceh, k, gmax(GNum(0.001), (gv(cdme, k) / gv(bpme, k) * (GNum(1.0) + c) - GNum(1.0)) / c))
    end
    # L18: FLO_SUM(RTP(R,V,P),C,COM,C,ANNUAL)$(RPC_SPG(R,P,COM)$RPC_PG(R,P,C)$NRG_TMAP(R,'ELC',C)) $= NCAP_CDME(RTP)
    spg_of = by(gset(tm, "RPC_SPG").keys, k -> (k[1], k[2]), k -> k[3])
    for k in rtpV
        haskey(cdme, k) || continue
        (r, v, p) = k
        for cm in get(spg_of, (r, p), none), c in get(pg_of, (r, p), none), a in tr.annual
            (cm in com && c in com && (r, c) in elc) && (fsum[(r, v, p, c, cm, c, a)] = cdme[k])
        end
    end
    chp_elc = gmembers(tm, "CHP_ELC", 3)
    rvp = gmembers(tm, "RVP", 3)
    trackp, trackpg = gmembers(tm, "TRACKP", 2), gmembers(tm, "TRACKPG", 3)
    rp_grp, rp_prc = gmembers(tm, "RP_GRP", 3), gmembers(tm, "RP_PRC", 2)
    rp_pgact = gset(tm, "RP_PGACT").members
    rp = gset(tm, "RP").members
    top = gset(tm, "TOP").members
    # L21-35: IF(CARD(CHP), ...)
    if !isempty(chp)
        # L23: OPTION PRC_ACT < NCAP_CHPR
        prc_act = project(keys(chpr), (1, 3))
        # L24: CHP_ELC(RPC_PG(CHP(PRC_ACT(R,P)),C))$NRG_TMAP(R,'ELC',C) = YES
        foreach(k -> ((k[1], k[2]) in chp && (k[1], k[2]) in prc_act && (k[1], k[3]) in elc) && push!(chp_elc, k), rpc_pg)
        # L25: OPTION TRACKP < CHP_ELC; TRACKP(RP_PGACT) = NO
        trackp = project(chp_elc, (1, 2))
        setdiff!(trackp, rp_pgact)
        # L26: RVP(R,V,P)$(COEF_RTP(R,V,P)$TRACKP(R,P)) = YES
        foreach(k -> (k[1] in tr.reg && k[2] in modl && (k[1], k[3]) in trackp) && push!(rvp, k), keys(coef))
        # L27: RP_GRP(RPC_PG(TRACKP(RP),C))$(NOT CHP_ELC(RP,C)) = YES
        foreach(k -> ((k[1], k[2]) in trackp && (k[1], k[2]) in rp && !(k in chp_elc)) && push!(rp_grp, k), rpc_pg)
        # L28: RP_GRP(RP_PGACT(CHP),C)$(TOP(CHP,C,'OUT')$(NOT CHP_ELC(CHP,C))) = YES
        for k in top
            (k[4] == "OUT" && (k[1], k[2]) in chp && (k[1], k[2]) in rp_pgact && !((k[1], k[2], k[3]) in chp_elc)) && push!(rp_grp, (k[1], k[2], k[3]))
        end
        # L29: TRACKPG(RP_GRP(RPC_PG(R,P,C)))$COM_LIM(R,C,'N')=YES; OPTION RP_PRC<TRACKPG
        lim = gset_opt(tm.data, "COM_LIM", 3).members
        foreach(k -> (k in rpc_pg && (k[1], k[3], "N") in lim) && push!(trackpg, k), rp_grp)
        rp_prc = project(trackpg, (1, 2))
        rvpl = gams_sort!(collect(rvp), tm.data)
        # L30: NCAP_CEH(RVP(R,V,P))$(NCAP_CEH(RVP)=0) = -0.5$RP_PRC(R,P)
        foreach(k -> gv(ceh, k).v == 0 && gassign!(ceh, k, GNum((k[1], k[3]) in rp_prc ? -0.5 : 0.0)), rvpl)
        # L31: NCAP_BPME(RVP) = MIN(0,SMIN(BD$NCAP_CHPR(RVP,BD),NCAP_CHPR(RVP,BD))*((NCAP_CEH(RVP)+1)$NCAP_CEH(RVP)-1))
        for k in rvpl
            sm = GNum(Inf)
            foreach(b -> haskey(chpr, (k..., b)) && (sm = gmin(sm, gv(chpr, (k..., b)))), bds)
            e = gv(ceh, k)
            gassign!(bpme, k, gmin(GZERO, sm * (gif(e + GNum(1.0), !iszero(e)) - GNum(1.0))))
        end
        # L32: NCAP_CEH(RVP)$(NCAP_CEH(RVP)<0) = -NCAP_CEH(RVP)
        foreach(k -> gv(ceh, k).v < 0 && gassign!(ceh, k, -gv(ceh, k)), rvpl)
        # L34: NCAP_CHPR(RVP,'FX')$((ABS(NCAP_CEH(RVP)-1)>.01)$(NOT NCAP_CHPR(RVP,'UP'))) = COEF_RTP(RVP)+EPS
        foreach(k -> (abs(gv(ceh, k).v - 1) > 0.01 && !haskey(chpr, (k..., "UP"))) && gassign!(chpr, (k..., "FX"), gv(coef, k) + GEPS), rvpl)
    end
    rvpl = gams_sort!(collect(rvp), tm.data)
    afl = gvalues(tm, "PRC_ACTFLO", 4)
    # L38: PRC_ACTFLO(RVP(R,V,P),C)$RPC_PG(R,P,C) =
    #   1+((PRC_ACTFLO(RVP,C)/COEF_RTP(RVP)+1)/MAX(1E-3,EXP(ABS(LOG(NCAP_CEH(RVP))))-PRC_ACTFLO(RVP,C))-1)$TRACKPG(R,P,C)
    for k in rvpl, c in get(pg_of, (k[1], k[3]), none)
        kc = (k..., c)
        x = GNum(1.0)
        if (k[1], k[3], c) in trackpg
            a = gv(afl, kc)
            e = gv(ceh, k).v
            e > 0 || throw(DomainError(e, "pp_chp.mod L38: LOG(NCAP_CEH$(k)) (GAMS: FUNC DOMAIN)"))
            x += (a / gv(coef, k) + GNum(1.0)) / gmax(GNum(1e-3), GNum(exp(abs(log(e)))) - a) - GNum(1.0)
        end
        gassign!(afl, kc, x)
    end
    # L39-40: PRC_ACTFLO(RVP(R,V,P),C)$((NCAP_CEH(RVP) LE 1)$RPC_PG(R,P,C)) =
    #   POWER(NCAP_CEH(RVP),(1$CHP_ELC(R,P,C)-1)$NCAP_CEH(RVP)) * (1-NCAP_BPME(RVP)) * PRC_ACTFLO(RVP,C)
    for k in rvpl
        e = gv(ceh, k)
        e.v <= 1 || continue
        for c in get(pg_of, (k[1], k[3]), none)
            n = iszero(e) ? 0 : ((k[1], k[3], c) in chp_elc ? 0 : -1)
            gassign!(afl, (k..., c), gpower(e, n) * (GNum(1.0) - gv(bpme, k)) * gv(afl, (k..., c)))
        end
    end
    # L41-42: PRC_ACTFLO(RVP(R,V,P),C)$(((NCAP_CEH(RVP) GT 1)*NCAP_CEH(RVP))$RPC_PG(R,P,C)) =
    #   (1+(1/NCAP_CEH(RVP)-1)/(1+1/COEF_RTP(RVP))) * POWER(NCAP_CEH(RVP),1-1$CHP_ELC(R,P,C)) * PRC_ACTFLO(RVP,C)
    for k in rvpl
        e = gv(ceh, k)
        e.v > 1 || continue
        for c in get(pg_of, (k[1], k[3]), none)
            f = GNum(1.0) + (GNum(1.0) / e - GNum(1.0)) / (GNum(1.0) + GNum(1.0) / gv(coef, k))
            gassign!(afl, (k..., c), f * gpower(e, (k[1], k[3], c) in chp_elc ? 0 : 1) * gv(afl, (k..., c)))
        end
    end
    # L44: FLO_SUM(RTP(R,V,P),C,COM,C,ANNUAL)$(RP_GRP(R,P,COM)$CHP_ELC(R,P,C)$NCAP_CDME(RTP)) = -1/PRC_ACTFLO(RTP,COM)
    grp_of = by(rp_grp, k -> (k[1], k[2]), k -> k[3])
    elc_of = by(chp_elc, k -> (k[1], k[2]), k -> k[3])
    for k in rtpV
        haskey(cdme, k) || continue
        (r, v, p) = k
        for cm in get(grp_of, (r, p), none), c in get(elc_of, (r, p), none), a in tr.annual
            cm in com && gassign!(fsum, (r, v, p, c, cm, c, a), -GNum(1.0) / gv(afl, (r, v, p, cm)))
        end
    end
    # L48: RP_GRP(TRACKPG)=NO; TRACKP(RP_PRC)=NO
    setdiff!(rp_grp, trackpg)
    setdiff!(trackp, rp_prc)
    # L49: OPTION CLEAR=TRACKPG; TRACKPG(RP_PG(TRACKP,CG))=YES
    trackpg = Set{NTuple{3,String}}(k for k in gset(tm, "RP_PG").keys if (k[1], k[2]) in trackp)
    # L50: TRACKPG(RP_PGACT(CHP(R,P)),CG('NRG')) $= SUM(RP_GRP(R,P,C)$COM_GMAP(R,CG,C),1)
    gmap = gset(tm, "COM_GMAP").members
    if ("NRG",) in gset(tm, "COM_GRP").members
        for (r, p) in chp
            ((r, p) in rp_pgact && any(k -> k[1] == r && k[2] == p && (r, "NRG", k[3]) in gmap, rp_grp)) && push!(trackpg, (r, p, "NRG"))
        end
    end
    # L51: RP_GRP(RP_GRP(RP,C))$SUM(TRACKPG(RP,CG),1) = NO
    tpg_rp = Set((k[1], k[2]) for k in trackpg)
    filter!(k -> !((k[1], k[2]) in rp && (k[1], k[2]) in tpg_rp), rp_grp)
    # L52-56: LOOP((CHP_ELC(R,P,C),TRACKPG(R,P,CG)), FLO_SHAR(RTP(R,V,P),C,CG,S,'LO'|'FX'|'UP')$(PRC_TS(R,P,S) *
    #   NCAP_CHPR(RTP,'UP'|'FX'|'LO')) = 1 / (1+NCAP_CHPR(RTP,'UP'|'FX'|'LO')))
    shar = gvalues(tm, "FLO_SHAR", 7)
    pts_of = by(gset(tm, "PRC_TS").keys, k -> (k[1], k[2]), k -> k[3])
    vs_of = by(rtpV, k -> (k[1], k[3]), k -> k[2])
    tpg_of = by(trackpg, k -> (k[1], k[2]), k -> k[3])
    for (r, p, c) in chp_elc, g in get(tpg_of, (r, p), none), v in get(vs_of, (r, p), none)
        for (bdl, bdr) in (("LO", "UP"), ("FX", "FX"), ("UP", "LO"))
            y = gv(chpr, (r, v, p, bdr))
            iszero(y) && continue
            foreach(s -> gassign!(shar, (r, v, p, c, g, s, bdl), GNum(1.0) / (GNum(1.0) + y)), get(pts_of, (r, p), none))
        end
    end
    # L58: FLO_SHAR(RTP(R,V,P),C,CG,S,BD)$(PRC_TS(R,P,S)$RP_PG(R,P,CG)$RP_GRP(R,P,C)) = NCAP_CHPR(RTP,BD)/(NCAP_CHPR(RTP,BD)+1)
    pgg_of = by(gset(tm, "RP_PG").keys, k -> (k[1], k[2]), k -> k[3])
    grp_of = by(rp_grp, k -> (k[1], k[2]), k -> k[3])
    for (r, v, p) in rtpV, c in get(grp_of, (r, p), none)
        c in com || continue
        for g in get(pgg_of, (r, p), none), s in get(pts_of, (r, p), none), b in bds
            y = gv(chpr, (r, v, p, b))
            gassign!(shar, (r, v, p, c, g, s, b), y / (y + GNum(1.0)))
        end
    end
    gput!(tm, "FLO_SHAR", shar)
    # L60: FLO_SUM(RVP,COM,C,COM,S)$((NCAP_BPME(RVP)$NCAP_CEH(RVP)$PRC_ACTFLO(RVP,C)<0)$FLO_EFF(RVP,COM,C,S)) =
    #   FLO_EFF(RVP,COM,C,S)/PRC_ACTFLO(RVP,C)
    if !isempty(rvp)
        for (k, y) in gparam_opt(tm.data, "FLO_EFF", 6).values
            (r, v, p, cm, c, s) = k
            ((r, v, p) in rvp && cm in com && c in com) || continue
            b = haskey(ceh, (r, v, p)) && haskey(afl, (r, v, p, c)) ? gv(bpme, (r, v, p)) : GZERO
            b.v < 0 || continue
            gassign!(fsum, (r, v, p, cm, c, cm, s), (y == 0.0 ? GEPS : GNum(y)) / gv(afl, (r, v, p, c)))
        end
    end
    gput!(tm, "FLO_SUM", fsum)
    # L61: IF(SUM(CHP(RP_XRED),1),PRC_ACTFLO(RVP(R,V,P),C)$RPC_AFLO(R,P,C)=1; RPC_ACT(RPC_AFLO(CHP(RP_XRED),C))=YES)
    xred = gset_opt(tm.data, "RP_XRED", 2).members
    if any(k -> k in xred, chp)
        aflo = gset_opt(tm.data, "RPC_AFLO", 3).members
        rpc_act = gmembers(tm, "RPC_ACT", 3)
        for k in rvpl, c in [a[3] for a in aflo if a[1] == k[1] && a[2] == k[3]]
            afl[(k..., c)] = 1.0
        end
        foreach(a -> ((a[1], a[2]) in chp && (a[1], a[2]) in xred) && push!(rpc_act, a), aflo)
        gput!(tm, "RPC_ACT", rpc_act)
    end
    gput!(tm, "PRC_ACTFLO", afl)
    # L64: LOOP(RPC_PKC(CHP_ELC(R,P,C)),NCAP_PKCNT(RVP(R,V,P),S)$COM_TS(R,C,S)=NCAP_PKCNT(RVP,S)/MAX(1,PRC_ACTFLO(RVP,C)))
    pk = gvalues(tm, "NCAP_PKCNT", 4)
    pkc = gset(tm, "RPC_PKC").members
    cts_of = by(gset(tm, "COM_TS").keys, k -> (k[1], k[2]), k -> k[3])
    rvp_of = by(rvpl, k -> (k[1], k[3]), k -> k[2])
    for (r, p, c) in gams_sort!([k for k in chp_elc if k in pkc], tm.data), v in get(rvp_of, (r, p), none), s in get(cts_of, (r, c), none)
        gassign!(pk, (r, v, p, s), gv(pk, (r, v, p, s)) / gmax(GNum(1.0), gv(afl, (r, v, p, c))))
    end
    gput!(tm, "NCAP_PKCNT", pk)
    # L65: RVP(RVP)$(NCAP_CEH(RVP)+1$NCAP_CHPR(RVP,'FX')+NCAP_CHPR(RVP,'LO')>0) = NO   (RVP is cleared at L71)
    # L66-70: PUTGRP = 0; LOOP(RVP(R,V,P)$(T(V)+PRC_VINT(R,P)), pp_qaput 01 'CHP process with zero CEH but only upper
    #   bound on CHPR.'; PUT QLOG ' WARNING       - Unusual CHP operation: R=',%RL%,' P=',%PL%,' V=',V.TL)
    qa_group!(tm)
    tmem = Set(k[1] for k in gset(tm, "T").keys)
    vint = gset_opt(tm.data, "PRC_VINT", 2).members
    for (r, v, p) in rvpl
        x = Float64(gv(ceh, (r, v, p))) + (haskey(chpr, (r, v, p, "FX")) ? 1.0 : 0.0) + Float64(gv(chpr, (r, v, p, "LO")))
        (x > 0 || !(v in tmem || (r, p) in vint)) && continue
        pp_qaput!(tm, 1, "CHP process with zero CEH but only upper bound on CHPR.")
        qput!(qalog(tm), " WARNING       - Unusual CHP operation: R=" * qlab12(r) * " P=" * qlab12(p) * " V=" * v)
    end
    # L71: OPTION CLEAR=PRC_ACT,CLEAR=RVP,CLEAR=TRACKP,CLEAR=TRACKPG,CLEAR=RP_PRC,CLEAR=RP_GRP,CLEAR=COEF_RTP
    gput!(tm, "NCAP_CHPR", chpr)
    gput!(tm, "NCAP_CEH", ceh)
    gput!(tm, "NCAP_BPME", bpme)
    gput!(tm, "CHP_ELC", chp_elc)
    for (n, N) in (("PRC_ACT", 2), ("RVP", 3), ("TRACKP", 2), ("TRACKPG", 3), ("RP_PRC", 2), ("RP_GRP", 3))
        gput!(tm, n, Set{NTuple{N,String}}())
    end
    gput!(tm, "COEF_RTP", Dict{NTuple{3,String},Float64}())
    return tm
end
