# EQE_CAFLAC / EQL_CAFLAC / EQL_CAPFLO (VDA extension): commodity-based
# availability factors (NCAP_AFC / NCAP_AFCS).
#
# GAMS: eqcaflac.vda L15-60, v4.9.7, included from equ_ext.vda L88-89 as
#   $BATINCLUDE eqcaflac.mod E "'FX'" $ %MX%
#   $BATINCLUDE eqcaflac.mod L "'UP'" * %MX%
# (%1 = equation type, %2 = bound type, %3 = '$' or '*', %4 = %MX%); declared
# equ_ext.vda L20-22 (R,ALLYEAR,ALLYEAR,P,S) and (R,ALLYEAR,ALLYEAR,P,CG,S);
# in the model through mod_ext.vda L11-13.
#
# - EQ%1_CAFLAC (L15-35): the flows of the primary group, each divided by its
#   commodity availability NCAP_AFCS (or by that of its commodity type, or by
#   1), against the available capacity, for the (process, timeslice, bound)
#   tuples in RPS_CAFLAC.
# - EQL_CAPFLO (L40-60): a flow not in the primary group (or a commodity
#   group of them) against NCAP_AFC times the capacity. L37 `%3 EXIT` is
#   `$ EXIT` in the E include, so EQL_CAPFLO is only defined by the L include.
#
# Macro expansions: %EQ% -> EQ, %VAR%/%VARM% -> VAR, %SOW%/%SWT%/%SWS% -> ''
# (setglobs.gms L348); %R_V_T% -> 'R,V,T' (maindrv.mod L39); %4 = %MX% ->
# '' (see eqcapact.jl), so COEF_AF%4 is COEF_AF; %RCAPSBM% is the -VAR_SCAP
# term of early retirement (prepret.dsc L88): RVP_KMAP(R,V,P,MODLYEAR(K))
# controls MODLYEAR together with K, so it is -VAR_SCAP(R,K,T,P) for
# VNTRT(K,T) in each K term (docs/discrepancies.md G48; `rcapsub!`, M1.3
# change 20b-2); %RTS% ->
# S (timslice.mod L31; S+NORTS(R,T,S) only with dynamic timeslices, refused);
# %UPSCAP0% -> (%UPSCAPS%$PRC_TS(R,P,S))$RP_UPL(R,P,'FX') (equ_ext.vda L75), the
# capacity of a dispatched process that is off-line (`upscap0!`; %UPSCAPS%:
# eqactups.jl header). No test case reaches it yet: it is translated, not
# parity-checked. %cal_red% is cal_nored.red (cal_red.jl), with C COM TS P T.
# XPT = {EXP} (initsys.mod L64), IPS = {IN, N} (setglobs.gms L154), ACTCG =
# {'ACT'} (initmty.mod L140), STL = all timeslices plus the level names
# (initmty.vda L21-22).
#
# AFS is the set as it stands at the SOLVE (afs_solve in eqcapact.jl), i.e.
# after equ_ext.vda L79 removes the UP/FX entries where NCAP_AFCS(R,T,P,'ACT',S)
# is given.
#
# The preprocessing that builds RPS_CAFLAC, NCAP_AFCS, NCAP_AFC, RPG_AFCX and
# RVP_KMAP (ppm_ext.vda L103-139, pp_qack.mod L56-59) is M1.3; their values
# are read from the pre-solve dump. COEF_VNT is COEF_CPT with its indexes
# permuted (pp_qack.mod L56, setglobs.gms L197).
#
# Storage processes (RP_STG): EQ(l)_CAFLAC counts their charging flow (times
# own/type NCAP_AFCS for RPG_AFCX, ppm_ext.vda L137) and their discharging
# flow times STG_EFF (L22-24); EQL_CAPFLO their storage level times the
# storage cycles (the ACT group, L48) and their flows in a group of the stored
# commodity (L49-51).
#
# Not translated; data that needs it raises UnportedError:
# - VAR_STS(R,V,T,P,TS,'UP') in EQL_CAPFLO (L48): RP_STL entries of type UP
#   exist only with %STSFLX% = YES (coef_ext.vda L32; `var_sts!` in
#   eqstgtss.jl, M1.3 change 52).

"Equation variants of eqcaflac.vda as included from equ_ext.vda L88-89: (%1, %2)."
const CAFLAC_VARIANTS = (("E", "FX"), ("L", "UP"))

"""
    eq_caflac!(tm::TimesModel) -> Int

Generate every EQE_CAFLAC, EQL_CAFLAC and EQL_CAPFLO row. Returns the number of
rows.

GAMS: eqcaflac.vda L15-60 with equ_ext.vda L75-79 and L88-89, v4.9.7.
"""
function eq_caflac!(tm::TimesModel)
    d = tm.data
    rps_caflac = gset_opt(d, "RPS_CAFLAC", 4)
    ncap_afc = gparam_opt(d, "NCAP_AFC", 5)
    (isempty(rps_caflac) && isempty(ncap_afc)) && return 0
    isempty(gparam_opt(d, "NORTS", 3)) || throw(UnportedError(
        "dynamic timeslices: %RTS% = S+NORTS(R,T,S) in eqcaflac.vda L40 (timslice.mod L31-39)"))
    capact_unported_afs_changes(tm)   # AFS changes not translated
    n = 0
    for (eqtype, bd) in CAFLAC_VARIANTS
        n += eq_caflac!(tm, eqtype, bd, rps_caflac)
    end
    n += eq_capflo!(tm, ncap_afc)       # L37-60, the L include only
    return n
end

"""
    caflac_capacity!(rhs, tm, r, v, t, p, f) -> rhs

The capacity part of both equations, without the final factors:

    SUM(RVP_KMAP(R,V,P,MODLYEAR(K)), COEF_VNT(R,T,P,K) * f(K) *
        (VAR_NCAP(R,K,P)\$T(K) + NCAP_PASTI(R,K,P)\$PYR(K)))

with `f(K)` the rest of the coefficient (COEF_AF(R,K,T,P,S,%2) times
PRC_CAPACT and G_YRFR for EQ(l)_CAFLAC, NCAP_AFC(R,V,P,CG,S) times PRC_CAPACT
and G_YRFR for EQL_CAPFLO). %UPSCAP0% is added by `upscap0!`.

GAMS: eqcaflac.vda L31-32 and L56-57, v4.9.7.
"""
function caflac_capacity!(rhs::JuMP.AffExpr, tm::TimesModel, r, v, t, p, f)
    kmap = get!(() -> indexby(gset_opt(tm.data, "RVP_KMAP", 4), (1, 2, 3)), tm.cache, "RVP_KMAP/rvp")
    modlyear, milestonyr, pastyear = gset(tm, "MODLYEAR"), gset(tm, "MILESTONYR"), gset(tm, "PASTYEAR")
    coef_vnt, ncap_pasti = gparam(tm, "COEF_VNT"), gparam(tm, "NCAP_PASTI")
    for (_, _, _, k) in get(kmap, (r, v, p), NTuple{4,String}[])
        (k,) in modlyear || continue                                # MODLYEAR(K)
        c = gv(coef_vnt, (r, t, p, k)) * f(k)
        (k,) in milestonyr && addterm!(rhs, c, tm, "VAR_NCAP", r, k, p)
        (k,) in pastyear && addconst!(rhs, c * gv(ncap_pasti, (r, k, p)))
        rcapsub!(rhs, c, tm, r, k, t, p)                        # %RCAPSBM%, MODLYEAR = K (G48; prepret.jl)
    end
    return rhs
end

"""
    upscap0!(rhs, c, tm, r, v, t, p, s) -> rhs

Add `c * %UPSCAP0%`:

    (-SUM(TS_MAP(R,ALL_TS,S)\$RPS_UPS(R,P,ALL_TS),VAR_UPS(R,V,T,P,ALL_TS,'N'))\$PRC_TS(R,P,S))\$RP_UPL(R,P,'FX')

the capacity of a dispatched process that is off-line in S. No test case
reaches it yet: translated, not parity-checked.

GAMS: equ_ext.vda L75, coef_ext.vda L30, v4.9.7.
"""
function upscap0!(rhs::JuMP.AffExpr, c::GNum, tm::TimesModel, r, v, t, p, s)
    d = tm.data
    (r, p, "FX") in gset_opt(d, "RP_UPL", 3) || return rhs
    (r, p, s) in gset(tm, "PRC_TS") || return rhs
    ups_of_rp = get!(() -> indexby(gset_opt(d, "RPS_UPS", 3), (1, 2)), tm.cache, "RPS_UPS/rp")
    tsmap = gset(tm, "TS_MAP")
    for (_, _, ts) in get(ups_of_rp, (r, p), NTuple{3,String}[])
        (r, ts, s) in tsmap && addterm!(rhs, -c, tm, "VAR_UPS", r, v, t, p, ts, "N")
    end
    return rhs
end

"""
    eq_caflac!(tm, eqtype, bd, rps_caflac) -> Int

One include of eqcaflac.vda L15-35: `eqtype` is %1 (E or L), `bd` is %2 (FX
or UP).

    EQ%1_CAFLAC(RTP_VINTYR(R,V,T,P),S)\$(AFS(R,T,P,S,%2)\$RPS_CAFLAC(R,P,S,%2)) ..
      SUM((RPC_PG(R,P,C),COM_TMAP(R,COM_TYPE(CG),C)),
          (1/ABS(PRC_ACTFLO(R,V,P,C))) /
          (NCAP_AFCS(R,V,P,C,S)+PROD(XPT\$NCAP_AFCS(R,V,P,CG,S),NCAP_AFCS(R,V,P,CG,S))\$(NOT NCAP_AFCS(R,V,P,C,S))) *
          SUM(RPCS_VAR(R,P,C,TS)\$RS_FR(R,S,TS), RS_FR(R,S,TS) * (VAR_FLO(R,V,T,P,C,TS)\$RP_STD(R,P) +
              ( SUM(TOP(RPC_STG(R,P,C),IO)\$(NCAP_AFCS(R,V,P,C,S)+NCAP_AFCS(R,V,P,CG,S)),
                    (VAR_SIN(R,V,T,P,C,TS)*PROD(RPG_AFCX(R,P,C,IE)\$NCAP_AFCS(R,V,P,C,S),
                         (NCAP_AFCS(R,V,P,C,S)/NCAP_AFCS(R,V,P,CG,S))\$NCAP_AFCS(R,V,P,CG,S)))\$IPS(IO) +
                    (VAR_SOUT(R,V,T,P,C,TS)*STG_EFF(R,V,P)*(1+RTCS_FR(R,T,C,S,TS)))\$(NOT IPS(IO))) +
                SUM(RPC_IRE(R,P,C,IE), VAR_IRE(R,V,T,P,C,TS,IE) *
                    PROD(RPG_AFCX(R,P,C,IE)\$((NCAP_AFCS(R,V,P,C,S)\$NCAP_AFCS(R,V,P,CG,S))**1\$RP_AIRE(R,P,IE)),
                         (NCAP_AFCS(R,V,P,C,S)/NCAP_AFCS(R,V,P,CG,S))\$NCAP_AFCS(R,V,P,CG,S)) + 1\$0)
              )\$(NOT RP_STD(R,P)))))
      =%1=
      (SUM(RVP_KMAP(R,V,P,MODLYEAR(K)), COEF_VNT(R,T,P,K) * COEF_AF(R,K,T,P,S,%2) *
           (VAR_NCAP(R,K,P)\$T(K) + NCAP_PASTI(R,K,P)\$PYR(K))) + COEF_AF(R,V,T,P,S,%2)*%UPSCAP0%) *
      PRC_CAPACT(R,P) * G_YRFR(R,S);

`PROD(XPT\$cond, x)` over the one-member set XPT is `x` when `cond` holds and
1 otherwise, so a commodity with no NCAP_AFCS of its own is divided by its
type's value, or by 1. An NCAP_AFCS of INF (an availability <= 0 for a
standard process, ppm_ext.vda L135) gives the flow an exact-zero coefficient
(GAMS: x/INF = 0, docs/discrepancies.md G17), so it leaves the row. In the
trade term `\$` binds tighter than `**` (G13): the exponent is `1\$RP_AIRE`,
so without RP_AIRE the condition is `x**0 = 1` and the factor applies
wherever RPG_AFCX holds; `+1\$0` adds nothing. For a storage process
RPG_AFCX(R,P,C,'EXP') marks a stored commodity with an output side
(ppm_ext.vda L137), whose charging flow is then multiplied by own/type
NCAP_AFCS, or by 0 when the type has none.

GAMS: eqcaflac.vda L15-35, v4.9.7.
"""
function eq_caflac!(tm::TimesModel, eqtype::AbstractString, bd::AbstractString, rps_caflac::GamsSet{4})
    d = tm.data
    name = "EQ$(eqtype)_CAFLAC"
    afs = afs_solve(tm)
    modlyear, tx = gset(tm, "MODLYEAR"), eq_periods(tm)   # %R_V_T%: SUBT in a stepped run (maindrv.mod L38-40)
    rp_std, rpc_stg = gset(tm, "RP_STD"), gset_opt(d, "RPC_STG", 3)
    rp_aire, rpg_afcx = gset(tm, "RP_AIRE"), gset_opt(d, "RPG_AFCX", 4)
    afcx_of_rpc = indexby(rpg_afcx, (1, 2, 3))                  # (r,p,c) -> RPG_AFCX(r,p,c,ie)
    top, ips = gset(tm, "TOP"), gset(tm, "IPS")
    io_set = [k[1] for k in gset(tm, "IN_OUT")]
    stg_eff, rtcs_fr = gparam(tm, "STG_EFF"), gparam(tm, "RTCS_FR")
    com_type = gset(tm, "COM_TYPE")
    ncap_afcs = gparam_opt(d, "NCAP_AFCS", 5)
    prc_actflo, rs_fr = gparam(tm, "PRC_ACTFLO"), gparam(tm, "RS_FR")
    coef_af, prc_capact, g_yrfr = gparam(tm, "COEF_AF"), gparam(tm, "PRC_CAPACT"), gparam(tm, "G_YRFR")

    s_of_rtpbd = indexby(afs, (1, 2, 3, 5))                     # (r,t,p,bd) -> AFS members
    pg_of_rp = indexby(gset(tm, "RPC_PG"), (1, 2))              # (r,p) -> RPC_PG(r,p,c)
    tmap_of_rc = indexby(gset(tm, "COM_TMAP"), (1, 3))          # (r,c) -> COM_TMAP(r,cg,c)
    ts_of_rpc = indexby(gset(tm, "RPCS_VAR"), (1, 2, 3))        # (r,p,c) -> RPCS_VAR(r,p,c,ts)
    ire_of_rpc = indexby(gset(tm, "RPC_IRE"), (1, 2, 3))        # (r,p,c) -> RPC_IRE(r,p,c,ie)
    no3, no4, no5 = NTuple{3,String}[], NTuple{4,String}[], NTuple{5,String}[]

    n = 0
    for (r, v, t, p) in gset(tm, "RTP_VINTYR")
        ((v,) in modlyear && (t,) in tx) || continue
        for (_, _, _, s, _) in get(s_of_rtpbd, (r, t, p, bd), no5)
            (r, p, s, bd) in rps_caflac || continue
            std = (r, p) in rp_std
            lhs = JuMP.AffExpr(0.0)
            for (_, _, c) in get(pg_of_rp, (r, p), no3)
                afcs_c = (r, v, p, c, s)
                for (_, cg, _) in get(tmap_of_rc, (r, c), no3)
                    (cg,) in com_type || continue                   # COM_TMAP(R,COM_TYPE(CG),C)
                    afcs_cg = (r, v, p, cg, s)
                    divisor = haskey(ncap_afcs, afcs_c) ? gv(ncap_afcs, afcs_c) :
                              (haskey(ncap_afcs, afcs_cg) ? gv(ncap_afcs, afcs_cg) : GNum(1.0))
                    base = (GNum(1.0) / abs(gv(prc_actflo, (r, v, p, c)))) / divisor
                    # Storage (L22-24): only where C or its type has an NCAP_AFCS.
                    stg = !std && (r, p, c) in rpc_stg && !iszero(gv(ncap_afcs, afcs_c) + gv(ncap_afcs, afcs_cg))
                    sin_f = GNum(1.0)                                # PROD(RPG_AFCX(R,P,C,IE)$NCAP_AFCS(C), ...)
                    if stg && haskey(ncap_afcs, afcs_c)
                        for _ in get(afcx_of_rpc, (r, p, c), no4)
                            sin_f = sin_f * (haskey(ncap_afcs, afcs_cg) ? gv(ncap_afcs, afcs_c) / gv(ncap_afcs, afcs_cg) : GZERO)
                        end
                    end
                    for (_, _, _, ts) in get(ts_of_rpc, (r, p, c), no4)
                        haskey(rs_fr, (r, s, ts)) || continue
                        w = base * gv(rs_fr, (r, s, ts))
                        if std
                            addterm!(lhs, w, tm, "VAR_FLO", r, v, t, p, c, ts)
                            continue
                        end
                        if stg
                            for io in io_set
                                (r, p, c, io) in top || continue
                                if (io,) in ips
                                    addterm!(lhs, w * sin_f, tm, "VAR_SIN", r, v, t, p, c, ts)
                                else
                                    addterm!(lhs, w * (gv(stg_eff, (r, v, p)) * (1 + gv(rtcs_fr, (r, t, c, s, ts)))),
                                             tm, "VAR_SOUT", r, v, t, p, c, ts)
                                end
                            end
                        end
                        for (_, _, _, ie) in get(ire_of_rpc, (r, p, c), no4)
                            factor = GNum(1.0)
                            if (r, p, c, ie) in rpg_afcx
                                x = gpow(gif(gv(ncap_afcs, afcs_c), haskey(ncap_afcs, afcs_cg)),
                                         gif(GNum(1.0), (r, p, ie) in rp_aire))
                                if !iszero(x)
                                    factor = haskey(ncap_afcs, afcs_cg) ?
                                             gv(ncap_afcs, afcs_c) / gv(ncap_afcs, afcs_cg) : GZERO
                                end
                            end
                            addterm!(lhs, w * factor, tm, "VAR_IRE", r, v, t, p, c, ts, ie)
                        end
                    end
                end
            end
            tail = gv(prc_capact, (r, p)) * gv(g_yrfr, (r, s))
            rhs = caflac_capacity!(JuMP.AffExpr(0.0), tm, r, v, t, p,
                                   k -> gv(coef_af, (r, k, t, p, s, bd)) * tail)
            upscap0!(rhs, gv(coef_af, (r, v, t, p, s, bd)) * tail, tm, r, v, t, p, s)
            gconstraint!(tm, name, (r, v, t, p, s), eqtype, lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end

"""
    eq_capflo!(tm, ncap_afc) -> Int

EQL_CAPFLO, eqcaflac.vda L40-60 (L include only):

    EQL_CAPFLO(RTP_VINTYR(R,V,T,P),CG,SL(STL(S)))\$(RS_TSLVL(R,S)\$NCAP_AFC(R,V,P,CG,STL)) ..
      SUM(RPC(RP_FLO(R,P),C)\$COM_GMAP(R,CG,C),
          SUM(RTPCS_VARF(R,T,P,C,TS)\$RS_FR(R,S,TS), RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS)) *
              [cal_red C COM TS P T])) +
      SUM(PRC_TS(RP_STG(R,P),TS)\$RS_FR(R,TS,S),
          (VAR_ACT(R,V,T,P,TS)+VAR_STS(R,V,T,P,TS,'UP'))*RS_FR(R,TS,S)*EXP(PRC_SC(R,P))/RS_STGPRD(R,TS)*G_YRFR(R,S))\$ACTCG(CG) +
      SUM(RPC_STG(R,P,C)\$COM_GMAP(R,CG,C),
          SUM((TOP(R,P,C,IO),RPCS_VAR(R,P,C,TS))\$RS_FR(R,S,TS), RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS)) *
              (VAR_SIN(R,V,T,P,C,TS)\$(NOT TOP(R,P,C,'OUT'))\$IPS(IO) + VAR_SOUT(R,V,T,P,C,TS)*STG_EFF(R,V,P)*DIAG(IO,'OUT'))))
      =L=
      (SUM(RVP_KMAP(R,V,P,MODLYEAR(K)), COEF_VNT(R,T,P,K) *
           (VAR_NCAP(R,K,P)\$T(K) + NCAP_PASTI(R,K,P)\$PYR(K))) + %UPSCAP0%) *
      NCAP_AFC(R,V,P,CG,STL) * PRC_CAPACT(R,P) * G_YRFR(R,S);

The domain's STL index is S itself. An NCAP_AFC entry of EPS (an
availability <= 0 for a commodity of the group, ppm_ext.vda L134) gives the
row with EPS capacity coefficients (the columns exist, docs/discrepancies.md G5).
VAR_STS has terms only with %STSFLX% (`var_sts!`).

GAMS: eqcaflac.vda L40-60, v4.9.7.
"""
function eq_capflo!(tm::TimesModel, ncap_afc::GamsParam{5})
    isempty(ncap_afc) && return 0
    d = tm.data
    modlyear, tx = gset(tm, "MODLYEAR"), eq_periods(tm)   # %R_V_T%: SUBT in a stepped run (maindrv.mod L38-40)
    rp_flo, rp_stg, rpc = gset(tm, "RP_FLO"), gset(tm, "RP_STG"), gset(tm, "RPC")
    rpc_stg = gset_opt(d, "RPC_STG", 3)
    rs_tslvl, rs_fr, rtcs_fr = gparam(tm, "RS_TSLVL"), gparam(tm, "RS_FR"), gparam(tm, "RTCS_FR")
    prc_capact, g_yrfr = gparam(tm, "PRC_CAPACT"), gparam(tm, "G_YRFR")
    prc_sc, rs_stgprd, stg_eff = gparam(tm, "PRC_SC"), gparam(tm, "RS_STGPRD"), gparam(tm, "STG_EFF")
    top, ips = gset(tm, "TOP"), gset(tm, "IPS")
    io_set = [k[1] for k in gset(tm, "IN_OUT")]
    ts_of_rp = indexby(gset(tm, "PRC_TS"), (1, 2))                # (r,p) -> PRC_TS(r,p,ts)
    varts_of_rpc = indexby(gset(tm, "RPCS_VAR"), (1, 2, 3))      # (r,p,c) -> RPCS_VAR(r,p,c,ts)
    stl_up = Set((k[1], k[2]) for k in gset(tm, "RP_STL") if k[4] == "UP")

    afc_of_rvp = indexby(ncap_afc, (1, 2, 3))                     # (r,v,p) -> NCAP_AFC(r,v,p,cg,s)
    gmap_of_rcg = indexby(gset(tm, "COM_GMAP"), (1, 2))          # (r,cg) -> COM_GMAP(r,cg,c)
    varf_of_rtpc = indexby(gset(tm, "RTPCS_VARF"), (1, 2, 3, 4))  # (r,t,p,c) -> RTPCS_VARF(r,t,p,c,ts)
    no3, no5 = NTuple{3,String}[], NTuple{5,String}[]

    n = 0
    for (r, v, t, p) in gset(tm, "RTP_VINTYR")
        ((v,) in modlyear && (t,) in tx) || continue
        for (_, _, _, cg, s) in get(afc_of_rvp, (r, v, p), no5)
            haskey(rs_tslvl, (r, s)) || continue                   # RS_TSLVL(R,S); S in STL
            lhs = JuMP.AffExpr(0.0)
            if (r, p) in rp_flo
                for (_, _, c) in get(gmap_of_rcg, (r, cg), no3)
                    (r, p, c) in rpc || continue
                    for (_, _, _, _, ts) in get(varf_of_rtpc, (r, t, p, c), no5)
                        haskey(rs_fr, (r, s, ts)) || continue
                        k = gv(rs_fr, (r, s, ts)) * (1 + gv(rtcs_fr, (r, t, c, s, ts)))
                        cal_nored!(lhs, tm, k, r, v, t, p, c, ts)
                    end
                end
            end
            if (r, p) in rp_stg
                # Storage level, L48: ACTCG(CG).
                if uppercase(cg) == "ACT"
                    cyc = gexp(gv(prc_sc, (r, p)))
                    for (_, _, ts) in get(ts_of_rp, (r, p), no3)
                        haskey(rs_fr, (r, ts, s)) || continue
                        k = gv(rs_fr, (r, ts, s)) * cyc / gv(rs_stgprd, (r, ts)) * gv(g_yrfr, (r, s))
                        addterm!(lhs, k, tm, "VAR_ACT", r, v, t, p, ts)
                        (r, p) in stl_up && var_sts!(lhs, k, tm, r, v, t, p, ts, "UP")    # + VAR_STS(R,V,T,P,TS,'UP')
                    end
                end
                # Storage flows of a stored commodity in CG, L49-51.
                for (_, _, c) in get(gmap_of_rcg, (r, cg), no3)
                    (r, p, c) in rpc_stg || continue
                    out_top = (r, p, c, "OUT") in top
                    for io in io_set
                        (r, p, c, io) in top || continue
                        for (_, _, _, ts) in get(varts_of_rpc, (r, p, c), NTuple{4,String}[])
                            haskey(rs_fr, (r, s, ts)) || continue
                            k = gv(rs_fr, (r, s, ts)) * (1 + gv(rtcs_fr, (r, t, c, s, ts)))
                            (!out_top && (io,) in ips) && addterm!(lhs, k, tm, "VAR_SIN", r, v, t, p, c, ts)
                            io == "OUT" && addterm!(lhs, k * gv(stg_eff, (r, v, p)), tm, "VAR_SOUT", r, v, t, p, c, ts)
                        end
                    end
                end
            end
            tail = gv(ncap_afc, (r, v, p, cg, s)) * gv(prc_capact, (r, p)) * gv(g_yrfr, (r, s))
            rhs = caflac_capacity!(JuMP.AffExpr(0.0), tm, r, v, t, p, k -> tail)
            upscap0!(rhs, tail, tm, r, v, t, p, s)
            gconstraint!(tm, "EQL_CAPFLO", (r, v, t, p, cg, s), "L", lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end
