# M1.3 (8a): ppmain.mod L461-611, the rest of the prep -> prelv segment
# before the extensions' pp_prelv (docs/m13-plan.md): lifetimes and lead
# times, refits, repeated investments and the capacity transfer years,
# capacity bounds, the periods without new capacity, the activity and flow
# availability, and the primary-group activity flows.
#
# GAMS: ppmain.mod L461-611, pp_off.mod L17-22 (L562, L578), v4.9.7.
#
# Index sets: R is REG, P and PRC are PRC, C is COM, T and TT are
# MILESTONYR, V is MODLYEAR, PYR is PASTYEAR, LIFE is an alias of AGE (the
# ages '1' to '200'), BD is BND_TYPE, L is LIM. RTP(R,T,P) and the like run
# over the milestones only (G8, G27; RTP holds past years too). `TT-1` moves
# along the milestones. %CTST% as `ctst` (coef_cpt.jl): `(G_ILEDNO+2)%CTST%-2`
# is -1 unless %CTST% is empty (G13: x**0 = x**EPS = 1). MAPVAL is nonzero
# for the special values (EPS, +-INF, NA, UNDF). `$x` is true for EPS (G12)
# and `NOT x` false (G25); an EPS compares as 0 (G12).
#
# The QA log (L465-472, L524-531, L539-542, L573 and L582-585) is written in
# LOOP order (M1.3 change 25b-1); `RTP.TE(RTP)` of an assigned record is its
# labels joined by '.'. L484 (`SET PRC_RCAP //; PARAMETER PRC_REFIT //;`) is
# a pair of empty data statements under $ONMULTI, compiled before execution,
# which keep the data (G39).

"""
    ppmain_life_symbols(tm) -> Vector{String}

The symbols ppmain.mod L461-611 settles that nothing later in the prep ->
prelv segment changes (for the layer-1 check at the prelv checkpoint). Left
out: NCAP_TLIFE (pp_prelv.vda L11), PRC_ACTFLO (pp_prelv.vda L66), TRACKP,
TRACKPC and the scratch F, Z and PUTGRP (pp_prelv.vda uses them again); RVP
when TS_OFF has data (dynslite.vda, pp_prelv.vda L125); RXX with %POWERFLO%
YES (powerflo.vda L121-122, from pp_prelv.vda L114, clears and fills it).
"""
function ppmain_life_symbols(tm)
    out = ["G_ILEDNO", "COEF_ILED", "NCAP_ILED", "PRC_REFIT", "RTP_OFF", "NCAP_ELIFE", "COEF_RPTI", "VNT", "YKVAL",
           "RTP_CPTYR", "PASTSUM", "COEF_RTP", "CAP_BND", "RCAP_BND", "NCAP_BND", "RTP_VARP", "NO_RVP", "RTP", "RTP_VARA", "MY_FIL",
           "RTPC", "RTPCS_OUT", "RPC_PG", "RP_STD", "RPC_ACT", "CHP", "PRC_CAPACT", "RP_PGACT"]
    isempty(gset_opt(tm.data, "TS_OFF", 4).keys) && push!(out, "RVP")
    uppercase(gswitch(tm, "POWERFLO", "")) == "YES" || pushfirst!(out, "RXX")
    return out
end

"MAPVAL(x) <> 0: EPS (stored as 0.0), +-INF, NA or UNDF (NaN)."
mapval_special(x::Float64) = x == 0.0 || !isfinite(x)

"""
    ppmain_life!(tm) -> tm

ppmain.mod L461-611 on the state after `ppmain_tslvl!`: NCAP_TLIFE checked
and defaulted, the lead times adjusted (G_ILEDNO, COEF_ILED, NCAP_ILED),
the refits (PRC_REFIT, RTP_OFF, NCAP_ELIFE, NCAP_TLIFE); COEF_RPTI, VNT and
RTP_CPTYR; CAP_BND moved into RCAP_BND and NCAP_BND, RTP_VARP; the periods
without new capacity taken out of RTP; RTP_VARA with PRC_AOFF, RTPC,
RTPCS_OUT with PRC_FOFF (both through pp_off.mod); the simulated vintages
(PRC_SIMV); RPC_PG, RP_STD, RPC_ACT, CHP, PRC_CAPACT, the PG commodities'
PRC_ACTFLO and RP_PGACT.

GAMS: ppmain.mod L461-611, v4.9.7.
"""
function ppmain_life!(tm)
    d = tm.data
    reg = Set(k[1] for k in gset(tm, "REG").keys)
    tset = [k[1] for k in gset(tm, "MILESTONYR").keys]
    tmem = Set(tset)
    tax = OrdAxis(tset)
    modl = gset(tm, "MODLYEAR").members
    rtp = gmembers(tm, "RTP", 3)
    rp = gset(tm, "RP").members
    tlife, iled = gvalues(tm, "NCAP_TLIFE", 3), gvalues(tm, "NCAP_ILED", 3)
    pasti = gvalues(tm, "NCAP_PASTI", 3)
    D, B, E, M, IPD = (gvalues(tm, s, 1) for s in ("D", "B", "E", "M", "IPD"))
    val(p, y) = Float64(gv(p, (y,)))
    onT(k) = k[2] in tmem                                        # RTP(R,T,P): the milestones

    # --- Lifetimes and lead times (L465-482) --------------------------------------------
    # L465-473: LOOP(SAMEAS(AGE,'1'), OPTION CLEAR=RXX; LOOP(RTP(R,T,P)$((NOT LIFE(AGE+(NCAP_TLIFE(RTP)-.999)))$NCAP_TLIFE(RTP)),
    #   <QA>; IF(NCAP_TLIFE(RTP) < 1, RXX(RTP) = YES)); NCAP_TLIFE(RXX(R,V,P)) = 1)   (a lead rounds, G29)
    age = OrdAxis(tm, "AGE")
    rxx = Set{NTuple{3,String}}()
    if haskey(age.pos, "1")
        qa_group!(tm)                                             # L465: PUTGRP = 0
        cand = [k for k in rtp if onT(k) && haskey(tlife, k) && lead(age, "1", glead(tlife[k] - 0.999)) === nothing]
        for k in gams_sort!(cand, d)
            x = tlife[k]                                          # EPS is 0.0
            # L467-471: pp_qaput 01 'NCAP_TLIFE out of feasible range'; then 'Too short, set to 1' (and RXX)
            #   or 'No FOM beyond year ',CARD(AGE):<3:0
            pp_qaput!(tm, 1, "NCAP_TLIFE out of feasible range")
            msg = x < 1 ? " WARNING       - Too short, set to 1,   R=" :
                  " WARNING       - No FOM beyond year " * qnum(length(age.labels), 3, 0; left=true) * ",  R="
            qput!(qalog(tm), msg * qlab12(k[1]) * " P=" * qlab12(k[3]) * " V=" * k[2])
            x < 1 && push!(rxx, k)
        end
        foreach(k -> (k[2],) in modl && (tlife[k] = 1.0), rxx)
    end
    gput!(tm, "RXX", rxx)
    # L476: NCAP_TLIFE(RTP)$(NOT NCAP_TLIFE(RTP)) = G_TLIFE
    gtlife = gscalar(tm, "G_TLIFE")
    foreach(k -> haskey(tlife, k) || gassign!(tlife, k, gtlife), rtp)
    # L478: G_ILEDNO = (G_ILEDNO+2)%CTST%-2
    iledno = gscalar(tm, "G_ILEDNO")
    if ctst(tm) != ""
        iledno + 2 < 0 && throw(DomainError(iledno + 2, "ppmain.mod L478: x**y with x < 0 (GAMS: rPower FUNC DOMAIN)"))
        iledno = -1.0
    end
    gput_scalar!(tm, "G_ILEDNO", iledno)
    # L480: COEF_ILED(RTP)$NCAP_ILED(RTP) = MAX(ABS(NCAP_ILED(RTP)),COEF_ILED(RTP))
    coef_iled = gvalues(tm, "COEF_ILED", 3)
    foreach(k -> haskey(iled, k) && gassign!(coef_iled, k, gmax(abs(gv(iled, k)), gv(coef_iled, k))), rtp)
    gput!(tm, "COEF_ILED", coef_iled)
    # L481: NCAP_ILED(RTP(R,V,P))$NCAP_ILED(RTP) = MAX(EPS,CEIL(NCAP_ILED(RTP)-0.5))$(COEF_ILED(RTP) > MIN(D(V),NCAP_TLIFE(RTP))/G_ILEDNO)
    for k in rtp
        ((k[2],) in modl && haskey(iled, k)) || continue
        iledno == 0 && throw(DomainError(iledno, "ppmain.mod L481: division by zero (G_ILEDNO)"))
        if gv(coef_iled, k).v > min(val(D, k[2]), Float64(gv(tlife, k))) / iledno
            gassign!(iled, k, gmax(GEPS, GNum(ceil(iled[k] - 0.5))))
        else
            delete!(iled, k)
        end
    end
    # L482: NCAP_ILED(RTP(R,PHYR,P)) = NCAP_ILED(RTP)+COEF_RTP(RTP)+EPS
    phyr = gset_opt(d, "PHYR", 1).members
    coef_rtp = gvalues(tm, "COEF_RTP", 3)
    foreach(k -> (k[2],) in phyr && gassign!(iled, k, gv(iled, k) + gv(coef_rtp, k) + GEPS), rtp)
    gput!(tm, "NCAP_ILED", iled)

    # --- Refits (L485-488) -------------------------------------------------------------------
    # L485: PRC_REFIT(R,P,PRC)$PRC_REFIT(R,P,PRC)=MAX(ABS(ROUND(PRC_REFIT(R,P,PRC))),MIN(6,ABS(MAX(ROUND(PRC_REFIT(R,P,P)),-1)*2)))
    #   *MOD(ROUND(PRC_REFIT(R,P,PRC)),2)   (the old values, G11; ROUND(EPS) is 0, G38; MOD keeps the sign, G43)
    refit = gvalues(tm, "PRC_REFIT", 3)
    old = copy(refit)
    rnd(x) = round(x, RoundNearestTiesAway)
    for (k, x) in old
        k[1] in reg || continue
        y = max(abs(rnd(x)), min(6.0, abs(max(rnd(get(old, (k[1], k[2], k[2]), 0.0)), -1.0) * 2))) * rem(rnd(x), 2)
        gassign!(refit, k, y)
    end
    gput!(tm, "PRC_REFIT", refit)
    # L486-488: LOOP((RP(R,PRC),P)$PRC_REFIT(RP,P), IF(NOT PRC_RCAP(RP),RTP_OFF(R,T,P)=YES);
    #   IF(PRC_REFIT(RP,P)<-4,NCAP_ELIFE(RTP(R,T,P))$(NCAP_ELIFE(RTP)<1)=NCAP_TLIFE(RTP);
    #     NCAP_TLIFE(RTP(R,T,P))=MAX(NCAP_TLIFE(R,T,PRC)+NCAP_ILED(R,T,PRC)-1,NCAP_TLIFE(RTP))))   in GAMS order
    rcap = gset_opt(d, "PRC_RCAP", 2).members
    rtp_off = gmembers(tm, "RTP_OFF", 3)
    elife = gvalues(tm, "NCAP_ELIFE", 3)
    for (r, h, p) in gams_sort!([k for k in keys(refit) if (k[1], k[2]) in rp], d)
        (r, h) in rcap || foreach(t -> push!(rtp_off, (r, t, p)), tset)
        refit[(r, h, p)] < -4 || continue
        for t in tset
            k = (r, t, p)
            k in rtp || continue
            gv(elife, k).v < 1 && gassign!(elife, k, gv(tlife, k))
            gassign!(tlife, k, gmax(gv(tlife, (r, t, h)) + gv(iled, (r, t, h)) - GNum(1.0), gv(tlife, k)))
        end
    end
    gput!(tm, "NCAP_ELIFE", elife)

    # --- Repeated investments, capacity transfer (L495-519) ------------------------------------
    # L495: NCAP_TLIFE(RVP)$((NCAP_PASTI(RVP)=0)$RTP_OFF(RVP)) = 1
    for k in gset(tm, "RVP").keys
        (k[1] in reg && gv(pasti, k).v == 0 && k in rtp_off) && (tlife[k] = 1.0)
    end
    gput!(tm, "NCAP_TLIFE", tlife)
    # L496: COEF_RPTI(RTP(R,PASTMILE,P))$NCAP_PASTI(R,PASTMILE,P) = 1
    pastmile = gset(tm, "PASTMILE").members
    rpti = gvalues(tm, "COEF_RPTI", 3)
    foreach(k -> ((k[2],) in pastmile && haskey(pasti, k)) && (rpti[k] = 1.0), rtp)
    # L498-503: the number of repeated investments of each milestone vintage
    altobj = gscalar(tm, "ALTOBJ")
    g1 = GNum(1.0)
    Dg(t) = gv(D, (t,))
    if altobj != 0
        ipdc(t) = ctst(tm) == "" ? val(IPD, t) : 1.0              # IPD(T)%CTST%
        for k in rtp
            # L498-499: COEF_RPTI(RTP(R,T,P))$NCAP_ILED(R,T,P) = MAX(1,CEIL((D(T)-NCAP_ILED(R,T,P))/NCAP_TLIFE(R,T,P)))
            (onT(k) && haskey(iled, k)) || continue
            gassign!(rpti, k, gmax(g1, GNum(ceil(((Dg(k[2]) - gv(iled, k)) / gv(tlife, k)).v))))
        end
        for k in rtp
            # L500-501: ...$(((ROUND(NCAP_TLIFE(R,T,P))-IPD(T)%CTST%) > 0)$(NOT NCAP_ILED(R,T,P))) = MAX(1,CEIL(MAX(D(T),IPD(T))/NCAP_TLIFE(R,T,P)))
            (onT(k) && !haskey(iled, k) && rnd(Float64(gv(tlife, k))) - ipdc(k[2]) > 0) || continue
            gassign!(rpti, k, gmax(g1, GNum(ceil((gmax(Dg(k[2]), gv(IPD, (k[2],))) / gv(tlife, k)).v))))
        end
        for k in rtp
            # L502: COEF_RPTI(RTP(R,T,P))$(NOT COEF_RPTI(R,T,P)) = MAX(1,MAX(D(T),IPD(T))/NCAP_TLIFE(R,T,P))
            (onT(k) && !haskey(rpti, k)) || continue
            gassign!(rpti, k, gmax(g1, gmax(Dg(k[2]), gv(IPD, (k[2],))) / gv(tlife, k)))
        end
    else
        for k in rtp
            # L503: COEF_RPTI(RTP(R,T,P)) = MAX(1,CEIL((D(T)-NCAP_ILED(R,T,P))/NCAP_TLIFE(R,T,P)))
            onT(k) || continue
            gassign!(rpti, k, gmax(g1, GNum(ceil(((Dg(k[2]) - gv(iled, k)) / gv(tlife, k)).v))))
        end
    end
    gput!(tm, "COEF_RPTI", rpti)
    # L505: VNT(V,T)$(M(T) GE M(V)) = YES; YKVAL(VNT(V,T)) = B(T)-B(V)
    vnt = gmembers(tm, "VNT", 2)
    vlist = [k[1] for k in gset(tm, "MODLYEAR").keys]
    for v in vlist, t in tset
        val(M, t) >= val(M, v) && push!(vnt, (v, t))
    end
    gput!(tm, "VNT", vnt)
    ykval = Dict{NTuple{2,String},Float64}()
    vnt_vt = [k for k in vnt if (k[1],) in modl && k[2] in tmem]
    foreach(k -> gassign!(ykval, k, gv(B, (k[2],)) - gv(B, (k[1],))), vnt_vt)
    cptyr = gmembers(tm, "RTP_CPTYR", 4)
    succ = Dict{String,Vector{String}}()
    foreach(((v, t),) -> push!(get!(succ, v, String[]), t), vnt_vt)
    F = nothing
    if altobj < 2
        # L507-508: RTP_CPTYR(R,VNT(V,T),P)$((B(V)+NCAP_ILED(R,V,P)<(E(T)+1))
        #   $(NCAP_ILED(R,V,P)+COEF_RPTI(R,V,P)*NCAP_TLIFE(R,V,P)>YKVAL(V,T))$RTP(R,V,P)) = YES
        for (r, v, p) in rtp
            (v,) in modl || continue
            il, life = gv(iled, (r, v, p)), gv(rpti, (r, v, p)) * gv(tlife, (r, v, p))
            for t in get(succ, v, String[])
                ((gv(B, (v,)) + il).v < val(E, t) + 1 && (il + life).v > Float64(gv(ykval, (v, t)))) && push!(cptyr, (r, v, t, p))
            end
        end
    else
        # L511: YKVAL(VNT(TT,T)) = B(T)-B(TT)-(1-MOD(IPD(T),2)+(IPD(T)-1)/9)/2; F=0
        for (v, t) in vnt_vt
            v in tmem || continue
            ip = val(IPD, t)
            gassign!(ykval, (v, t), val(B, t) - val(B, v) - (1 - rem(ip, 2) + (ip - 1) / 9) / 2)
        end
        F = 0.0
        # L512: PASTSUM(RTP(R,V,P)) = (NCAP_ILED(R,V,P)+F)$NCAP_ILED(R,V,P)+COEF_RPTI(R,V,P)*NCAP_TLIFE(R,V,P)
        # L513: RTP_CPTYR(R,VNT(V,T),P)$((PASTSUM(R,V,P) > YKVAL(V,T))$(B(V)+NCAP_ILED(R,V,P) < E(T)+1)$RTP(R,V,P)) = YES
        for (r, v, p) in rtp
            (v,) in modl || continue
            k = (r, v, p)
            il = gv(iled, k)
            ps = gif(il + GNum(F), haskey(iled, k)) + gv(rpti, k) * gv(tlife, k)
            for t in get(succ, v, String[])
                (ps.v > Float64(gv(ykval, (v, t))) && (gv(B, (v,)) + il).v < val(E, t) + 1) && push!(cptyr, (r, v, t, p))
            end
        end
        # L514: OPTION CLEAR=PASTSUM
    end
    gput!(tm, "PASTSUM", Dict{NTuple{3,String},Float64}())
    # L516: OPTION CLEAR=YKVAL,CLEAR=COEF_RTP
    gput!(tm, "YKVAL", Dict{NTuple{2,String},Float64}())
    gput!(tm, "COEF_RTP", Dict{NTuple{3,String},Float64}())
    # L518: $IF %VALIDATE% == YES RTP_CPTYR(R,T,T,P)$RTP(R,T,P) = YES
    uppercase(gswitch(tm, "VALIDATE", "")) == "YES" && foreach(k -> onT(k) && push!(cptyr, (k[1], k[2], k[2], k[3])), rtp)
    # L519: RTP_CPTYR(R,MIYR_1(T),T,P)$(RTP(R,T,P)$PRC_MAP(R,'STK',P)) = YES   (one index T twice: the first milestone with itself)
    prc_map = gset(tm, "PRC_MAP").members
    miyr_1 = gset(tm, "MIYR_1").members
    for k in rtp
        ((k[2],) in miyr_1 && onT(k) && (k[1], "STK", k[3]) in prc_map) && push!(cptyr, (k[1], k[2], k[2], k[3]))
    end

    # --- Capacity bounds (L524-542) -------------------------------------------------------------
    # L524: OPTION CLEAR=RVP; PUTGRP=0
    rvp = Set{NTuple{3,String}}()
    qa_group!(tm)
    cap = gvalues(tm, "CAP_BND", 4)
    bdneq = [k[1] for k in gset(tm, "BDNEQ").keys]
    # L525: CAP_BND(RTP,BDNEQ) $= CAP_BND(RTP,'FX')
    for k in rtp
        fx = (k..., "FX")
        haskey(cap, fx) && foreach(b -> gassign!(cap, (k..., b), gv(cap, fx)), bdneq)
    end
    # L526-531: LOOP((RTP(R,T,P),L('UP'))$((CAP_BND(RTP,L)<=PRC_RESID(RTP))$CAP_BND(RTP,L)),
    #   IF(PRC_RCAP(R,P), Z=0; ELSE Z=PRC_RESID(RTP)); IF(Z, F=CAP_BND(RTP,L); CAP_BND(RTP,L)$(IFQ<10)=EPS;
    #   F$(0**(IFQ+F+1$RP_FLO(R,P)))=Z; IF(F<Z, RCAP_BND(RTP,'N')=Z; <QA>)))   in GAMS order
    resid = gvalues(tm, "PRC_RESID", 3)
    ifq = GNum(gscalar(tm, "IFQ"))
    rp_flo = gset(tm, "RP_FLO").members
    rcap_bnd = gvalues(tm, "RCAP_BND", 4)
    Z = nothing
    for k in gams_sort!([k for k in rtp if onT(k)], d)
        up = (k..., "UP")
        (haskey(cap, up) && cap[up] <= Float64(gv(resid, k))) || continue
        z = (k[1], k[3]) in rcap ? GZERO : gv(resid, k)
        Z = z
        iszero(z) && continue                                     # IF(Z, ...): EPS is true (G41)
        f = gv(cap, up)
        ifq.v < 10 && gassign!(cap, up, GEPS)
        iszero(gpow(GZERO, ifq + f + GNum((k[1], k[3]) in rp_flo ? 1.0 : 0.0))) || (f = z)
        F = f                                                     # an EPS bound leaves F EPS
        if f.v < z.v
            gassign!(rcap_bnd, (k..., "N"), z)
            # L530-531: pp_qaput IFQ 'Inconsistent CAP_BND(UP/FX) defined for process capacity';
            #   PUT ' WARNING       - Bound converted to NCAP_BND,   R.T.P= ',RTP.TE(RTP); PUT$(IFQ>9)@28 'infeasibility detected,'
            pp_qaput!(tm, ifq.v, "Inconsistent CAP_BND(UP/FX) defined for process capacity")
            q = qalog(tm)
            qput!(q, " WARNING       - Bound converted to NCAP_BND,   R.T.P= " * join(k, "."))
            ifq.v > 9 && (qat!(q, 28); qput!(q, "infeasibility detected,"))
        end
    end
    gput!(tm, "RCAP_BND", rcap_bnd)
    # L533: RVP(RTP)$((CAP_BND(RTP,'UP')=0)$CAP_BND(RTP,'UP')) = YES   (an EPS upper bound)
    foreach(k -> get(cap, (k..., "UP"), 1.0) == 0.0 && push!(rvp, k), rtp)
    # L534: LOOP(T, NCAP_BND(R,TT,P,'UP')$(RTP_CPTYR(R,TT,T,P)$RVP(R,T,P)) = EPS)
    nbnd = gvalues(tm, "NCAP_BND", 4)
    for (r, tt, t, p) in cptyr
        (t in tmem && tt in tmem && (r, t, p) in rvp) && (nbnd[(r, tt, p, "UP")] = 0.0)
    end
    # L535: RVP(RTP_VARP)=NO; CAP_BND(RVP,BD) = 0
    varp = gmembers(tm, "RTP_VARP", 3)
    setdiff!(rvp, varp)
    bds = [k[1] for k in gset(tm, "BD").keys]
    foreach(k -> foreach(b -> delete!(cap, (k..., b)), bds), rvp)
    # L536: CAP_BND(RTP,BDLOX)$MAPVAL(CAP_BND(RTP,BDLOX)) = 0
    bdlox = [k[1] for k in gset(tm, "BDLOX").keys]
    for k in rtp, b in bdlox
        x = get(cap, (k..., b), nothing)
        (x !== nothing && mapval_special(x)) && delete!(cap, (k..., b))
    end
    gput!(tm, "CAP_BND", cap)
    # L538: RTP_VARP(RTP(R,T,P))$(CAP_BND(RTP,'UP')*CAP_BND(RTP,'LO')) = YES   (EPS*x is EPS, G6)
    foreach(k -> (onT(k) && !iszero(gv(cap, (k..., "UP")) * gv(cap, (k..., "LO")))) && push!(varp, k), rtp)
    gput!(tm, "RTP_VARP", varp)
    # L539-542: PUTGRP=0; LOOP(RTP(RTP_VARP)$((CAP_BND(RTP,'LO')>CAP_BND(RTP,'UP'))$CAP_BND(RTP,'UP')),
    #   pp_qaput 1 'Inconsistent CAP_BND(UP/LO/FX) defined for process capacity';
    #   PUT ' WARNING       - Lower bound set equal to upper bound,   R.T.P= ',RTP.TE(RTP))   (a message only)
    qa_group!(tm)
    lo_up = [k for k in rtp if k in varp && haskey(cap, (k..., "UP")) && get(cap, (k..., "LO"), 0.0) > cap[(k..., "UP")]]
    for k in gams_sort!(lo_up, d)
        pp_qaput!(tm, 1, "Inconsistent CAP_BND(UP/LO/FX) defined for process capacity")
        qput!(qalog(tm), " WARNING       - Lower bound set equal to upper bound,   R.T.P= " * join(k, "."))
    end

    # --- Periods without new capacity (L546-552) -------------------------------------------------
    # L546: LOOP(BDUPX(BD),RTP_OFF(RTP)$((NCAP_BND(RTP,BD)=0)$NCAP_BND(RTP,BD)) = YES)
    bdupx = [k[1] for k in gset(tm, "BDUPX").keys]
    foreach(k -> any(b -> get(nbnd, (k..., b), 1.0) == 0.0, bdupx) && push!(rtp_off, k), rtp)
    gput!(tm, "NCAP_BND", nbnd)
    gput!(tm, "RTP_OFF", rtp_off)
    # L547: NO_RVP(RTP_OFF(R,T,P))$(NOT NCAP_PASTI(R,T,P)) = YES
    no_rvp = Set{NTuple{3,String}}(k for k in rtp_off if k[1] in reg && onT(k) && !haskey(pasti, k))
    # L548: LOOP(T, NO_RVP(R,TT,P)$(RTP_CPTYR(R,T,TT,P)$(NOT RTP_OFF(R,T,P))) = NO)
    # L549: LOOP(PYR(V), NO_RVP(R,T,P)$(RTP_CPTYR(R,V,T,P)$NCAP_PASTI(R,V,P)) = NO)
    pyr = gset(tm, "PASTYEAR").members
    for (r, v, t, p) in cptyr
        t in tmem || continue
        (v in tmem && !((r, v, p) in rtp_off)) && delete!(no_rvp, (r, t, p))                   # L548
        ((v,) in pyr && (v,) in modl && haskey(pasti, (r, v, p))) && delete!(no_rvp, (r, t, p))  # L549
    end
    # L550: RTP(NO_RVP) = NO
    setdiff!(rtp, no_rvp)
    # L551: RTP_CPTYR(R,T,TT,P)$((NOT NCAP_PASTI(R,T,P))$RTP_OFF(R,T,P)) = NO
    filter!(k -> !(k[2] in tmem && k[3] in tmem && !haskey(pasti, (k[1], k[2], k[4])) && (k[1], k[2], k[4]) in rtp_off), cptyr)
    gput!(tm, "RTP_CPTYR", cptyr)
    # L552: OPTION CLEAR=RVP, CLEAR=NO_RVP
    gput!(tm, "RVP", Set{NTuple{3,String}}())
    no_rvp = Set{NTuple{3,String}}()

    # --- Activity and flow availability (L558-586) -------------------------------------------------
    boh, eoh = OrdAxis(tm, "BOHYEAR"), OrdAxis(tm, "EOHYEAR")
    my_fil = gmembers(tm, "MY_FIL", 1)
    # L558: LOOP(PRC_AOFF(RP(R,P),BOHYEAR,EOHYEAR),TRACKP(R,P) = YES)
    aoff = Dict{NTuple{2,String},Vector{NTuple{2,String}}}()
    for (r, p, b, e) in gams_sort!(collect(gset_opt(d, "PRC_AOFF", 4).keys), d)
        ((r, p) in rp && haskey(boh.pos, b) && haskey(eoh.pos, e)) && push!(get!(aoff, (r, p), NTuple{2,String}[]), (b, e))
    end
    # L559: RTP_VARA(RTP(R,T,P))$(NOT TRACKP(R,P)) = YES
    vara = gmembers(tm, "RTP_VARA", 3)
    foreach(k -> (onT(k) && !haskey(aoff, (k[1], k[3]))) && push!(vara, k), rtp)
    # L560-565: LOOP(TRACKP(R,P), MY_FIL(T) = YES; $BATINCLUDE pp_off.mod PRC_AOFF P "" "MY_FIL(T)$(" NO;
    #   RTP_VARA(RTP(R,MY_FIL(T),P)) = YES)   in GAMS order
    offsc = PPOffScratch()                                              # pp_off.mod's scratch over L560-581
    for (r, p) in gams_sort!(collect(keys(aoff)), d)
        foreach(t -> push!(my_fil, (t,)), tset)
        foreach(t -> delete!(my_fil, (t,)), pp_off_periods(tm, pp_off_fil(tm, aoff[(r, p)], offsc), tset))
        for t in tset
            ((t,) in my_fil && (r, t, p) in rtp) && push!(vara, (r, t, p))
        end
    end
    gput!(tm, "RTP_VARA", vara)
    # L572: RTPC(RTP(R,T,P),C) $= RPC(R,P,C)
    rpc = gset(tm, "RPC").members
    coms = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(coms, (k[1], k[2]), String[]), k[3]), rpc)
    rtpc = gmembers(tm, "RTPC", 4)
    for k in rtp
        onT(k) && foreach(c -> push!(rtpc, (k..., c)), get(coms, (k[1], k[3]), String[]))
    end
    gput!(tm, "RTPC", rtpc)
    # L573: PUTGRP = 0
    qa_group!(tm)
    # L575: LOOP(PRC_FOFF(R,P,C,TS,BOHYEAR,EOHYEAR),TRACKPC(R,P,C) = YES)
    foff = Dict{NTuple{3,String},Vector{NTuple{3,String}}}()            # (R,P,C) => (TS, BOHYEAR, EOHYEAR)
    for (r, p, c, ts, b, e) in gams_sort!(collect(gset_opt(d, "PRC_FOFF", 6).keys), d)
        (r in reg && haskey(boh.pos, b) && haskey(eoh.pos, e)) && push!(get!(foff, (r, p, c), NTuple{3,String}[]), (ts, b, e))
    end
    # L576-581: LOOP(RPCS_VAR(TRACKPC(R,P,C),S), MY_FIL(T) = NO;
    #   $BATINCLUDE pp_off.mod PRC_FOFF 'P,C,TS' '$TS_MAP(R,TS,S)' "MY_FIL(T)$(" YES; RTPCS_OUT(RTP_VARA(R,MY_FIL(T),P),C,S) = YES)
    outs = gmembers(tm, "RTPCS_OUT", 5)
    if !isempty(foff)
        tsmap = gset(tm, "TS_MAP").members
        for (r, p, c, s) in gams_sort!([k for k in gset(tm, "RPCS_VAR").keys if haskey(foff, (k[1], k[2], k[3]))], d)
            foreach(t -> delete!(my_fil, (t,)), tset)
            ranges = [(b, e) for (ts, b, e) in foff[(r, p, c)] if (r, ts, s) in tsmap]
            foreach(t -> push!(my_fil, (t,)), pp_off_periods(tm, pp_off_fil(tm, ranges, offsc), tset))
            for t in tset
                ((t,) in my_fil && (r, t, p) in vara) && push!(outs, (r, t, p, c, s))
            end
        end
    end
    gput!(tm, "RTPCS_OUT", outs)
    # L582-585: LOOP(PRC_FOFF(RPC(R,P,C),TS,BOHYEAR,EOHYEAR)$SUM(RPCS_VAR(R,P,C,S)$RS_BELOW(R,S,TS),1),
    #   pp_qaput 01 'Flow OFF TS level below VARiable TS level';
    #   PUT QLOG ' WARNING       - OFF is ignored:  R=',%RL%,' P=',%PL%,' C=',%CL%,' S=',TS.TL)
    if !isempty(foff)
        below = gset(tm, "RS_BELOW").members
        varts = Dict{NTuple{3,String},Vector{String}}()
        foreach(k -> push!(get!(varts, (k[1], k[2], k[3]), String[]), k[4]), gset(tm, "RPCS_VAR").keys)
        for (r, p, c, ts, b, e) in gams_sort!(collect(gset_opt(d, "PRC_FOFF", 6).keys), d)
            (r in reg && haskey(boh.pos, b) && haskey(eoh.pos, e) && (r, p, c) in rpc) || continue
            any(s -> (r, s, ts) in below, get(varts, (r, p, c), String[])) || continue
            pp_qaput!(tm, 1, "Flow OFF TS level below VARiable TS level")
            qput!(qalog(tm), " WARNING       - OFF is ignored:  R=" * qlab12(r) * " P=" * qlab12(p) * " C=" * qlab12(c) * " S=" * ts)
        end
    end
    gput!(tm, "MY_FIL", my_fil)
    pp_off_keep!(tm, offsc)

    # --- Simulated vintages (L590) -------------------------------------------------------------------
    # $IF DEFINED PRC_SIMV LOOP(T,NO_RVP(R,TT-1,P)$(RTP_CPTYR(R,TT,T,P)$PRC_SIMV(R,P))=YES); NO_RVP(RTP(R,T,P))=NO; RTP(NO_RVP)=YES
    simv = gset_opt(d, "PRC_SIMV", 2).members
    if !isempty(simv) || strip(gswitch(tm, "VINTOPT", "")) == "2"
        for (r, tt, t, p) in cptyr
            (t in tmem && tt in tmem && (r, p) in simv) || continue
            pv = lead(tax, tt, -1)
            pv === nothing || push!(no_rvp, (r, pv, p))
        end
        filter!(k -> !(k in rtp), no_rvp)
        union!(rtp, no_rvp)
    end
    gput!(tm, "NO_RVP", no_rvp)
    gput!(tm, "RTP", rtp)

    # --- PG activity flows (L593-611) --------------------------------------------------------------
    rp_pg = gset(tm, "RP_PG").members
    actflo = gvalues(tm, "PRC_ACTFLO", 4)
    # L593: RPC_PG(R,P,C)$((NOT RP_PG(R,P,C))$(ROUND(PRC_ACTFLO(R,'0',P,C)<0))) = NO
    rpc_pg = gmembers(tm, "RPC_PG", 3)
    filter!(k -> !(!(k in rp_pg) && get(actflo, (k[1], "0", k[2], k[3]), 0.0) < 0), rpc_pg)
    # L595: RPC_PG(RPC_STG) = YES
    union!(rpc_pg, gset(tm, "RPC_STG").members)
    gput!(tm, "RPC_PG", rpc_pg)
    # L596: RP_STD(RP_FLO(RP))$(NOT RP_STG(RP)) = YES
    rp_stg = gset(tm, "RP_STG").members
    rp_std = gmembers(tm, "RP_STD", 2)
    foreach(k -> (k in rp && !(k in rp_stg)) && push!(rp_std, k), rp_flo)
    gput!(tm, "RP_STD", rp_std)
    # L597: OPTION RPC_ACT <= PRC_ACTFLO   (PRC_ACTFLO(REG,ALLYEAR,PRC,CG) onto RPC_ACT(REG,PRC,CG): positions 1, 3, 4)
    rpc_act = project(keys(actflo), (1, 3, 4))
    # L598: RPC_ACT(R,P,C)$(RPC_PG(R,P,C)+(NOT RPC(R,P,C)$RP_STD(R,P))) = NO   (C at the CG position: commodities only, G27)
    com = gset(tm, "COM").members
    filter!(k -> !((k[3],) in com && k[1] in reg && (k in rpc_pg || !(k in rpc && (k[1], k[2]) in rp_std))), rpc_act)
    gput!(tm, "RPC_ACT", rpc_act)
    # L599: CHP(RP(R,P)) $= PRC_MAP(R,'CHP',P)
    chp = gmembers(tm, "CHP", 2)
    foreach(k -> (k[1], "CHP", k[2]) in prc_map && push!(chp, k), rp)
    gput!(tm, "CHP", chp)
    # L604: PRC_CAPACT(RP)$(NOT PRC_CAPACT(RP)) = 1
    capact = gvalues(tm, "PRC_CAPACT", 2)
    foreach(k -> haskey(capact, k) || (capact[k] = 1.0), rp)
    gput!(tm, "PRC_CAPACT", capact)
    # L606-608: PRC_ACTFLO(RTP(R,V,P),C)$((NOT PRC_ACTFLO(RTP,C))$RPC_PG(R,P,C)) $= SUM(RP_PG(R,P,CG),PRC_ACTFLO(R,V,P,CG));
    #   the same $= PRC_ACTFLO(RTP,%PGPRIM%); then = 1   (each statement reads the values from before it, G11)
    pg = uppercase(strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"']))
    pgs = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(pgs, (k[1], k[2]), String[]), k[3]), rp_pg)
    pgc = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(pgc, (k[1], k[2]), String[]), k[3]), rpc_pg)
    targets = [(k..., c) for k in rtp if (k[2],) in modl for c in get(pgc, (k[1], k[3]), String[])]
    for stmt in 1:3
        new = Dict{NTuple{4,String},GNum}()
        for (r, v, p, c) in targets
            haskey(actflo, (r, v, p, c)) && continue
            x = stmt == 1 ? reduce(+, (gv(actflo, (r, v, p, cg)) for cg in get(pgs, (r, p), String[])); init=GZERO) :
                stmt == 2 ? gv(actflo, (r, v, p, pg)) : GNum(1.0)
            iszero(x) || (new[(r, v, p, c)] = x)
        end
        foreach(((k, x),) -> gassign!(actflo, k, x), new)
    end
    gput!(tm, "PRC_ACTFLO", actflo)
    # L610: RP_PGACT(RP_FLO(R,P))$(SUM(RPC_PG(R,P,C),1) EQ 1) = YES
    rp_pgact = gmembers(tm, "RP_PGACT", 2)
    foreach(k -> (k[1] in reg && length(get(pgc, k, String[])) == 1) && push!(rp_pgact, k), rp_flo)
    # L611: RP_PGACT(RP_IRE(R,P))$(SUM(RPC_IRE(RPC_PG(R,P,C),IE),1) EQ 1) = YES
    nire = Dict{NTuple{2,String},Int}()
    for (r, p, c, ie) in gset(tm, "RPC_IRE").keys
        (r, p, c) in rpc_pg && (nire[(r, p)] = get(nire, (r, p), 0) + 1)
    end
    foreach(k -> (k[1] in reg && get(nire, k, 0) == 1) && push!(rp_pgact, k), gset(tm, "RP_IRE").keys)
    gput!(tm, "RP_PGACT", rp_pgact)
    # L566, L586: OPTION CLEAR=TRACKP, CLEAR=TRACKPC
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    gput!(tm, "TRACKPC", Set{NTuple{3,String}}())
    F === nothing || gput!(tm, "F", gassign!(Dict{Tuple{},Float64}(), (), GNum(F)))
    Z === nothing || gput!(tm, "Z", gassign!(Dict{Tuple{},Float64}(), (), Z))
    return tm
end
