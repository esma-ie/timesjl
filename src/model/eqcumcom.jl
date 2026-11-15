# EQ_CUMNET / EQ_CUMPRD: cumulative net or production of a commodity over a
# year range, defining VAR_CUMCOM (bounded by COM_CUM, bnd_cum.mod L27-40,
# and used by user constraints through UC_CUMCOM).
#
# GAMS: eqcumcom.mod L15-32, v4.9.7, included from eqmain.mod L89-90 as
#   $BATINCLUDE eqcumcom.mod E NET
#   $BATINCLUDE eqcumcom.mod E PRD
# (%1 = equation type, %2 = NET or PRD); declared eqdeclr.mod L69-70
# (R,C,ALLYEAR,ALLYEAR).
#
#   EQ_CUM%2(RC(R,C),ALLYEAR,LL)$RC_CUMCOM(R,'%2',ALLYEAR,LL,C) ..
#     SUM(RTC_%2(R,TT(T),C)$[period T overlaps ALLYEAR..LL],
#         SUM(RTCS_VARC(R,T,C,S), W(T) * VAR_COM%2(R,T,C,S))) / %CUCSCAL%
#     =E= VAR_CUMCOM(R,C,'%2',ALLYEAR,LL);
#
# with the overlap and the weight W(T) of eqcumflo.jl (year overlap unless
# %OBJ% is LIN, then TPULSE). Macro expansions: %EQ% -> EQ, %VAR%/%VARTT% ->
# VAR, %SOW%/%SWS% -> '' (setglobs.gms L348); %CUCSCAL% -> 1000 unless the
# run sets it (eqmain.mod L17); %OBJ% is the run's switch (eqmain.mod L33's
# $SETLOCAL does not reach the included file, docs/discrepancies.md G7).
# RC_CUMCOM is read as it stands at the SOLVE: bnd_cum.mod L31 drops ranges
# that start after the horizon, after eqmain.

"""
    cum_weight(tm, t, y1, y2) -> Union{Nothing,GNum}

`nothing` when period `t` does not overlap the year range `y1..y2`;
otherwise the number of its years in the range (or, with %OBJ% LIN, the sum
of its TPULSE weights there).

GAMS: eqcumcom.mod L18-23 = eqcumflo.mod L19-24, v4.9.7.
"""
function cum_weight(tm::TimesModel, t::String, y1::String, y2::String)
    x = get!(tm.cache, "CUM_WEIGHT") do
        lin = uppercase(gswitch(tm, "OBJ", "")) == "LIN"
        (lin = lin, yearval = gparam(tm, "YEARVAL"), pB = gparam(tm, "B"), pE = gparam(tm, "E"), pM = gparam(tm, "M"),
         lagt = gparam(tm, "LAGT"), lead = gparam(tm, "LEAD"),
         ordyear = Dict(k[1] => i for (i, k) in enumerate(gset(tm, "ALLYEAR").keys)),
         pulse_of_t = lin ? indexby(gset(tm, "TPULSEYR"), (1,)) : Dict{Tuple{String},Vector{NTuple{2,String}}}(),
         tpulse = lin ? gparam(tm, "TPULSE") : nothing)
    end
    yv(y) = x.yearval[(y,)]
    if x.lin
        (x.pM[(t,)] + x.lagt[(t,)] > yv(y1) && x.pM[(t,)] - x.lead[(t,)] < yv(y2)) || return nothing
        w = GZERO
        for (_, year) in get(x.pulse_of_t, (t,), NTuple{2,String}[])
            (x.ordyear[year] >= x.ordyear[y1] && x.ordyear[year] <= x.ordyear[y2]) || continue
            w = w + gv(x.tpulse, (t, year))
        end
        return w
    end
    (x.pE[(t,)] >= yv(y1) && x.pB[(t,)] <= yv(y2)) || return nothing
    return GNum(max(0.0, min(x.pE[(t,)], yv(y2)) - max(x.pB[(t,)], yv(y1)) + 1))
end

"""
    eq_cumcom!(tm::TimesModel) -> Int

Generate every EQ_CUMNET and EQ_CUMPRD row (eqmain.mod L89-90). Returns the
number of rows.

GAMS: eqcumcom.mod L15-32, v4.9.7. The %OBJ% LIN weights are checked on the
crafted case demo12_cumlin (layer 2; test/unit/test_cum_lin.jl).
"""
function eq_cumcom!(tm::TimesModel)
    rc_cumcom = gset(tm, "RC_CUMCOM")
    isempty(rc_cumcom) && return 0
    cucscal = parse(Float64, gswitch(tm, "CUCSCAL", "1000"))
    rc, milestonyr = gset(tm, "RC"), gset(tm, "MILESTONYR")     # TT(T): MILESTONYR (initmty.mod L94)
    varc_of_rtc = indexby(gset(tm, "RTCS_VARC"), (1, 2, 3))    # (r,t,c) -> RTCS_VARC(r,t,c,s)
    n = 0
    for kind in ("NET", "PRD")                                  # eqmain.mod L89-90
        rtc_kind = gset(tm, "RTC_$(kind)")
        for (r, k, y1, y2, c) in rc_cumcom
            (k == kind && (r, c) in rc) || continue
            lhs = JuMP.AffExpr(0.0)
            for (t,) in milestonyr
                (r, t, c) in rtc_kind || continue
                w = cum_weight(tm, t, y1, y2)
                w === nothing && continue
                for (_, _, _, s) in get(varc_of_rtc, (r, t, c), NTuple{4,String}[])
                    addterm!(lhs, w / cucscal, tm, "VAR_COM$(kind)", r, t, c, s)
                end
            end
            rhs = JuMP.AffExpr(0.0)
            addterm!(rhs, GNum(1.0), tm, "VAR_CUMCOM", r, c, kind, y1, y2)
            gconstraint!(tm, "EQ_CUM$(kind)", (r, c, y1, y2), "E", lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end
