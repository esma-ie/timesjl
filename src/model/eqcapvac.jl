# EQE_CAPVAC / EQL_CAPVAC / EQG_CAPVAC: the capacity-activity equation of the processes with
# simulated vintages (PRC_SIMV), in place of EQ(l)_CAPACT and EQ(l)_CAFLAC.
#
# GAMS: eqcapvac.mod L14-28, v4.9.7, included from coef_csv.mod L75-77 as
#   $ BATINCLUDE eqcapvac.mod E FX N
#   $ BATINCLUDE eqcapvac.mod L UP N
#   $ BATINCLUDE eqcapvac.mod G LO LO
# (%1 = equation type, %2 = bound type; %3 is not used by the file). coef_csv.mod is included
# from eqmain.mod L67 when PRC_SIMV is DEFINED (`simv_defined`, coef_csv.jl). Declared
# coef_csv.mod L16-19 over (R,ALLYEAR,T,P,S,ALLSOW); in the model through mod_equa.mod L74.
#
# Macro expansions: %VAR%/%VARM% -> VAR, %SOW%/%SWTX%/%SWS% -> '' (setglobs.gms L348, L363);
# %SWX% -> ,'1' (setglobs.gms L365; ',SOW' only with stochastic stages, stages.stc L15), so
# every row carries the ALLSOW element '1' as its sixth index: EQ%1_CAPVAC(R,V,T,P,S,'1').
# %R_V_T% -> 'R,V,T' (maindrv.mod L39). XPT = {EXP} (initsys.mod L64).
#
# The rows are over RTP_VINTYR, which coef_csv.mod L70-71 rewrites to the simulated vintages V
# of each period T, and over AFSV, the AFS entries coef_csv.mod L74 takes from the simulated
# processes (afsv_solve in eqcapact.jl). COEF_CSV(R,K,T,P,V) is the part of the capacity of
# the true vintage K that the simulated vintage V carries in T (coef_csv.jl).
#
# As GAMS has the file (docs/discrepancies.md, D36):
# - L27, the capacity: `COEF_CSV*COEF_AF*VAR_NCAP(R,K,P)\$T(K)+NCAP_PASTI(R,K,P)` adds the past
#   investment of K as it is, without COEF_CSV, COEF_AF or a PASTYEAR condition, so a past
#   investment counts in full in every period of its simulated vintage.
# - L19-22, the flows of a process with commodity availabilities (RPS_CAFLAC): 1/PRC_ACTFLO
#   without ABS, TS_MAP (not RS_FR) on the flows, no storage flows; and no %RCAPSBM% term
#   (early retirement) on the capacity.

"Equation variants of eqcapvac.mod as included from coef_csv.mod L75-77: (%1, %2)."
const CAPVAC_VARIANTS = (("E", "FX"), ("L", "UP"), ("G", "LO"))

"""
    eq_capvac!(tm::TimesModel) -> Int

Generate every EQE_CAPVAC, EQL_CAPVAC and EQG_CAPVAC row (coef_csv.mod L75-77), when PRC_SIMV
is DEFINED (eqmain.mod L67). Returns the number of rows generated.

GAMS: eqcapvac.mod L14-28, v4.9.7.
"""
function eq_capvac!(tm::TimesModel)
    simv_defined(tm) || return 0
    afsv = afsv_solve(tm)
    n = 0
    for (eqtype, bd) in CAPVAC_VARIANTS
        n += eq_capvac!(tm, eqtype, bd, afsv)
    end
    return n
end

"""
    eq_capvac!(tm, eqtype, bd, afsv) -> Int

One include of eqcapvac.mod: `eqtype` is %1 (E, L or G), `bd` is %2 (FX, UP or LO).

    EQ%1_CAPVAC(RTP_VINTYR(R,V,T,P),S,'1')\$(AFSV(R,T,P,S,'%2'))..
      SUM(PRC_TS(R,P,TS)\$TS_MAP(R,S,TS),VAR_ACT(R,V,T,P,TS))\$(NOT RPS_CAFLAC(R,P,S,'%2')) +
      SUM((RPC_PG(R,P,C),COM_TMAP(R,COM_TYPE(CG),C)), (1/PRC_ACTFLO(R,V,P,C)) /
          (NCAP_AFCS(R,V,P,C,S)+PROD(XPT\$NCAP_AFCS(R,V,P,CG,S),NCAP_AFCS(R,V,P,CG,S))\$(NOT NCAP_AFCS(R,V,P,C,S))) *
          SUM(RPCS_VAR(R,P,C,TS)\$TS_MAP(R,S,TS),VAR_FLO(R,V,T,P,C,TS)\$RP_STD(R,P) +
            SUM(RPC_IRE(R,P,C,IE),VAR_IRE(R,V,T,P,C,TS,IE))))\$RPS_CAFLAC(R,P,S,'%2')
      =%1=
      SUM(MODLYEAR(K)\$COEF_CSV(R,K,T,P,V),
          COEF_CSV(R,K,T,P,V)*COEF_AF(R,K,T,P,S,'%2')*VAR_NCAP(R,K,P)\$T(K)+NCAP_PASTI(R,K,P))*PRC_CAPACT(R,P)*G_YRFR(R,S);

- `\$T(K)` binds to VAR_NCAP alone, and NCAP_PASTI(R,K,P) is a term of its own in the sum
  (file header).
- `PROD(XPT\$cond, x)` over the one-member set XPT is `x` when `cond` holds and 1 otherwise, so a
  commodity with no NCAP_AFCS of its own is divided by its type's value, or by 1, as in
  EQ(l)_CAFLAC (eqcaflac.jl).

GAMS: eqcapvac.mod L14-28, v4.9.7.
"""
function eq_capvac!(tm::TimesModel, eqtype::AbstractString, bd::AbstractString, afsv::GamsSet{5})
    d = tm.data
    name = "EQ$(eqtype)_CAPVAC"
    modlyear, milestonyr = gset(tm, "MODLYEAR"), gset(tm, "MILESTONYR")   # V, K; T
    rps_caflac = gset_opt(d, "RPS_CAFLAC", 4)
    ts_map, rp_std, com_type = gset(tm, "TS_MAP"), gset(tm, "RP_STD"), gset(tm, "COM_TYPE")
    ncap_afcs = gparam_opt(d, "NCAP_AFCS", 5)
    prc_actflo = gparam(tm, "PRC_ACTFLO")
    coef_csv = gparam_opt(d, "COEF_CSV", 5)
    coef_af, prc_capact, g_yrfr = gparam(tm, "COEF_AF"), gparam(tm, "PRC_CAPACT"), gparam(tm, "G_YRFR")
    ncap_pasti = gparam(tm, "NCAP_PASTI")

    s_of_rtpbd = indexby(afsv, (1, 2, 3, 5))                    # (r,t,p,bd) -> AFSV members
    ts_of_rp = indexby(gset(tm, "PRC_TS"), (1, 2))              # (r,p) -> PRC_TS(r,p,ts)
    pg_of_rp = indexby(gset(tm, "RPC_PG"), (1, 2))              # (r,p) -> RPC_PG(r,p,c)
    tmap_of_rc = indexby(gset(tm, "COM_TMAP"), (1, 3))          # (r,c) -> COM_TMAP(r,cg,c)
    ts_of_rpc = indexby(gset(tm, "RPCS_VAR"), (1, 2, 3))        # (r,p,c) -> RPCS_VAR(r,p,c,ts)
    ire_of_rpc = indexby(gset(tm, "RPC_IRE"), (1, 2, 3))        # (r,p,c) -> RPC_IRE(r,p,c,ie)
    k_of_rtpv = indexby(coef_csv, (1, 3, 4, 5))                 # (r,t,p,v) -> COEF_CSV(r,k,t,p,v)
    no3, no4, no5 = NTuple{3,String}[], NTuple{4,String}[], NTuple{5,String}[]

    n = 0
    for (r, v, t, p) in gset(tm, "RTP_VINTYR")
        # The domain RTP_VINTYR(R,V,T,P) is controlled by V (MODLYEAR) and T (MILESTONYR).
        ((v,) in modlyear && (t,) in milestonyr) || continue
        for (_, _, _, s, _) in get(s_of_rtpbd, (r, t, p, bd), no5)
            lhs = JuMP.AffExpr(0.0)
            if !((r, p, s, bd) in rps_caflac)
                # L17: activity in the timeslices at or below S.
                for (_, _, ts) in get(ts_of_rp, (r, p), no3)
                    (r, s, ts) in ts_map || continue
                    addterm!(lhs, GNum(1.0), tm, "VAR_ACT", r, v, t, p, ts)
                end
            else
                # L19-22: the flows of the primary group, each divided by its commodity availability.
                std = (r, p) in rp_std
                for (_, _, c) in get(pg_of_rp, (r, p), no3)
                    afcs_c = (r, v, p, c, s)
                    for (_, cg, _) in get(tmap_of_rc, (r, c), no3)
                        (cg,) in com_type || continue               # COM_TMAP(R,COM_TYPE(CG),C)
                        afcs_cg = (r, v, p, cg, s)
                        divisor = haskey(ncap_afcs, afcs_c) ? gv(ncap_afcs, afcs_c) :
                                  (haskey(ncap_afcs, afcs_cg) ? gv(ncap_afcs, afcs_cg) : GNum(1.0))
                        w = (GNum(1.0) / gv(prc_actflo, (r, v, p, c))) / divisor
                        for (_, _, _, ts) in get(ts_of_rpc, (r, p, c), no4)
                            (r, s, ts) in ts_map || continue
                            std && addterm!(lhs, w, tm, "VAR_FLO", r, v, t, p, c, ts)
                            for (_, _, _, ie) in get(ire_of_rpc, (r, p, c), no4)
                                addterm!(lhs, w, tm, "VAR_IRE", r, v, t, p, c, ts, ie)
                            end
                        end
                    end
                end
            end

            # L27: the capacity of the true vintages K that the simulated vintage V carries.
            capact, yrfr = gv(prc_capact, (r, p)), gv(g_yrfr, (r, s))
            rhs = JuMP.AffExpr(0.0)
            pasti = GZERO
            for kk in get(k_of_rtpv, (r, t, p, v), no5)
                k = kk[2]
                (k,) in modlyear || continue
                if (k,) in milestonyr
                    c = gv(coef_csv, kk) * gv(coef_af, (r, k, t, p, s, bd))
                    addterm!(rhs, c * capact * yrfr, tm, "VAR_NCAP", r, k, p)
                end
                pasti = pasti + gv(ncap_pasti, (r, k, p))
            end
            addconst!(rhs, pasti * capact * yrfr)
            gconstraint!(tm, name, (r, v, t, p, s, "1"), eqtype, lhs, rhs) === nothing || (n += 1)   # %SWX%
        end
    end
    return n
end
