# EQG_ACTBND / EQE_ACTBND / EQL_ACTBND: activity bounds that cannot be
# variable bounds, i.e. on vintaged processes (summed over vintages) or at a
# timeslice above the process's own (summed over the timeslices below).
#
# GAMS: eqactbnd.mod L17-28, v4.9.7, included from eqmain.mod L47-49 as
#   $BATINCLUDE eqactbnd.mod G LO "(ACT_BND(R,T,P,S,'LO') NE 0)"
#   $BATINCLUDE eqactbnd.mod E FX YES
#   $BATINCLUDE eqactbnd.mod L UP "(ACT_BND(R,T,P,S,'UP') NE INF)"
# (%1 = equation type, %2 = bound type, %3 = extra condition); declared
# eqdeclr.mod L40-42. The other ACT_BND records become variable bounds
# (bnd_act.mod, bndmain.jl).
#
# Macro expansions: %EQ% -> EQ, %VAR% -> VAR, %SOW%/%SWT% -> '' (setglobs.gms
# L348); %R_T% -> 'R,T' (maindrv.mod L39). T = MILESTONYR, V = MODLYEAR.
# In the %3 conditions EPS compares as 0 (docs/discrepancies.md G12).

const ACTBND_VARIANTS = (("G", "LO"), ("E", "FX"), ("L", "UP"))

"""
    eq_actbnd!(tm::TimesModel) -> Int

Generate every EQ(l)_ACTBND row. Returns the number of rows.

    EQ%1_ACTBND(RTP_VARA(R,T,P),S)\$((RPS_PRCTS(R,P,S)*(PRC_VINT(R,P)+(NOT PRC_TS(R,P,S)))\$%3)\$ACT_BND(R,T,P,S,'%2')) ..
        SUM(PRC_TS(R,P,TS)\$TS_MAP(R,S,TS), SUM(RTP_VINTYR(R,V,T,P), VAR_ACT(R,V,T,P,TS)))
        =%1= ACT_BND(R,T,P,S,'%2');

The SOW tags (sow_tags.jl): the row is `%EQ%%1_ACTBND(... %SWT%)`
(eqactbnd.mod L17) and the term `%VAR%_ACT(... %SOW%)` (L22).

GAMS: eqactbnd.mod L17-28 with eqmain.mod L47-49, v4.9.7.
"""
function eq_actbnd!(tm::TimesModel)
    act_bnd = gparam(tm, "ACT_BND")
    isempty(act_bnd) && return 0
    modlyear = gset(tm, "MODLYEAR")
    tx = eq_periods(tm)   # %R_T%, %TX%: SUBT in a stepped run (maindrv.mod L38-40)
    rtp_vara = gset(tm, "RTP_VARA")
    rps_prcts = gset(tm, "RPS_PRCTS")
    prc_vint, prc_ts = gset(tm, "PRC_VINT"), gset(tm, "PRC_TS")
    ts_map = gset(tm, "TS_MAP")
    ts_of_rp = indexby(prc_ts, (1, 2))                       # (r,p) -> PRC_TS(r,p,ts)
    v_of_rtp = indexby(gset(tm, "RTP_VINTYR"), (1, 3, 4))    # (r,t,p) -> RTP_VINTYR(r,v,t,p)
    no3, no4 = NTuple{3,String}[], NTuple{4,String}[]

    n = 0
    for (eqtype, bd) in ACTBND_VARIANTS
        name = "EQ$(eqtype)_ACTBND"
        rows = NTuple{4,String}[]
        for (r, t, p, s, b) in act_bnd.keys
            b == bd || continue
            ((t,) in tx && (r, t, p) in rtp_vara && (r, p, s) in rps_prcts) || continue
            ((r, p) in prc_vint || !((r, p, s) in prc_ts)) || continue
            v = act_bnd.values[(r, t, p, s, b)]
            bd == "LO" && v == 0 && continue                 # (ACT_BND(...,'LO') NE 0)
            bd == "UP" && v == Inf && continue               # (ACT_BND(...,'UP') NE INF)
            push!(rows, (r, t, p, s))
        end
        gams_sort!(rows, tm.data)
        for (r, t, p, s) in rows
            for sow in sw_rows(tm, t)   # %SWT% (eqactbnd.mod L17)
                set_sow!(tm, sow)
                lhs = JuMP.AffExpr(0.0)
                for (_, _, ts) in get(ts_of_rp, (r, p), no3)
                    (r, s, ts) in ts_map || continue
                    for (_, v, _, _) in get(v_of_rtp, (r, t, p), no4)
                        (v,) in modlyear || continue
                        addterm!(lhs, GNum(1.0), tm, "VAR_ACT", r, v, t, p, ts)
                    end
                end
                rhs = addconst!(JuMP.AffExpr(0.0), gv(act_bnd, (r, t, p, s, bd)))
                gconstraint!(tm, eqtag(tm, name), swt(tm, (r, t, p, s), t), eqtype, lhs, rhs) === nothing || (n += 1)
            end
        end
    end
    return n
end
