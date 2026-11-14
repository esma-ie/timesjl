# EQG_BNDNET / EQE_BNDNET / EQL_BNDNET and EQG_BNDPRD / EQE_BNDPRD / EQL_BNDPRD:
# bounds on the net amount (VAR_COMNET) and the production (VAR_COMPRD) of a
# commodity at a timeslice above the level the commodity is tracked at
# (COM_TS), summed over the tracked timeslices below it.
#
# GAMS: eqbndcom.mod L16-24, v4.9.7, included from eqmain.mod L54-59 as
#   $BATINCLUDE eqbndcom.mod G LO "(COM_BNDNET(R,T,C,S,'LO') NE 0)" NET
#   $BATINCLUDE eqbndcom.mod E FX YES NET
#   $BATINCLUDE eqbndcom.mod L UP "(COM_BNDNET(R,T,C,S,'UP') NE INF)" NET
#   $BATINCLUDE eqbndcom.mod G LO "(COM_BNDPRD(R,T,C,S,'LO') NE 0)" PRD
#   $BATINCLUDE eqbndcom.mod E FX YES PRD
#   $BATINCLUDE eqbndcom.mod L UP "(COM_BNDPRD(R,T,C,S,'UP') NE INF)" PRD
# (%1 = equation type, %2 = bound type, %3 = extra condition, %4 = NET or
# PRD); declared eqdeclr.mod L45-50; in the model, mod_equa.mod L63-68. The
# COM_BNDNET and COM_BNDPRD records at the commodity's own timeslices become
# bounds of the variables (bndmain.mod L57-58, bndmain.jl); records below that
# level were summed up to it before (pp_lvlbd.mod, ppmain.mod L993-994).
#
# Macro expansions: %EQ% -> EQ, %VAR% -> VAR, %SOW%/%SWT% -> '' (setglobs.gms
# L348); %R_T% -> 'R,T' (maindrv.mod L39). T = MILESTONYR.
# In the %3 conditions EPS compares as 0 (docs/discrepancies.md G12): a LO
# record with the value EPS gives no row. The FX include has no condition on
# the value (%3 is YES), and `$COM_BND%4(R,T,C,S,'FX')` holds for a stored EPS:
# such a record gives a row with a right-hand side of zero.

const BNDCOM_VARIANTS = (("G", "LO"), ("E", "FX"), ("L", "UP"))

"""
    eq_bndcom!(tm::TimesModel) -> Int

Generate every EQ(l)_BNDNET and EQ(l)_BNDPRD row, in the order of eqmain.mod
L54-59 (NET: G, E, L; then PRD: G, E, L). Returns the number of rows.

    EQ%1_BND%4(RTC(R,T,C),S)\$((RCS_COMTS(R,C,S)\$(NOT COM_TS(R,C,S))\$%3)\$COM_BND%4(R,T,C,S,'%2')) ..
        SUM(RTCS_VARC(R,T,C,TS)\$TS_MAP(R,S,TS), VAR_COM%4(R,T,C,TS))
        =%1= COM_BND%4(R,T,C,S,'%2');

GAMS: eqbndcom.mod L16-24 with eqmain.mod L54-59, v4.9.7.
"""
function eq_bndcom!(tm::TimesModel)
    com_bnd = (("NET", gparam(tm, "COM_BNDNET")), ("PRD", gparam(tm, "COM_BNDPRD")))
    all(isempty(p) for (_, p) in com_bnd) && return 0
    milestonyr = gset(tm, "MILESTONYR")
    rtc, rcs_comts, com_ts = gset(tm, "RTC"), gset(tm, "RCS_COMTS"), gset(tm, "COM_TS")
    ts_map = gset(tm, "TS_MAP")
    varc_of_rtc = indexby(gset(tm, "RTCS_VARC"), (1, 2, 3))  # (r,t,c) -> RTCS_VARC(r,t,c,ts)
    no4 = NTuple{4,String}[]

    n = 0
    for (kind, bnd) in com_bnd, (eqtype, bd) in BNDCOM_VARIANTS
        name = "EQ$(eqtype)_BND$kind"
        rows = NTuple{4,String}[]
        for (r, t, c, s, b) in bnd.keys
            b == bd || continue
            ((t,) in milestonyr && (r, t, c) in rtc) || continue
            ((r, c, s) in rcs_comts && !((r, c, s) in com_ts)) || continue
            v = bnd.values[(r, t, c, s, b)]
            bd == "LO" && v == 0 && continue                 # (COM_BND%4(...,'LO') NE 0)
            bd == "UP" && v == Inf && continue               # (COM_BND%4(...,'UP') NE INF)
            push!(rows, (r, t, c, s))
        end
        gams_sort!(rows, tm.data)
        for (r, t, c, s) in rows
            lhs = JuMP.AffExpr(0.0)
            for (_, _, _, ts) in get(varc_of_rtc, (r, t, c), no4)
                (r, s, ts) in ts_map || continue
                addterm!(lhs, GNum(1.0), tm, "VAR_COM$kind", r, t, c, ts)
            end
            rhs = addconst!(JuMP.AffExpr(0.0), gv(bnd, (r, t, c, s, bd)))
            gconstraint!(tm, name, (r, t, c, s), eqtype, lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end
