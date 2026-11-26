# EQ_CUMFLO: cumulative flow or activity of a process over a year range,
# defining VAR_CUMFLO (bounded elsewhere by FLO_CUM).
#
# GAMS: eqcumflo.mod L14-45, v4.9.7, included from eqmain.mod L92 as
# `$BATINCLUDE eqcumflo.mod E`. Macro expansions:
# - %EQ% -> EQ, %VAR%/%VARTT% -> VAR, %SOW%/%SWT%/%SWS% -> '' (setglobs.gms
#   L348); %STAGES% is not YES, so the L16, L26 and L31 lines drop out and
#   %SW1%/%SW2% are '' (L15).
# - %PGPRIM% -> 'ACT' (initmty.mod L138, unless the run sets it).
# - %CUFSCAL% -> 10 (eqmain.mod L16, unless the run sets it).
# - %OBJ%: the run's objective switch. `$IFI %OBJ%==LIN` (case-insensitive)
#   selects the TPULSE weights (L21, L24, L35); any other value, including
#   the AUTO of reference/templates/scenario.run, the year-overlap weights
#   (L20, L23, L34).
# - %cal_red% with arguments C COM TS P T: cal_nored!, see cal_red.jl.
# MAPVAL(x) = 8 means x is EPS, so VAR_CUMFLO is left out of a row only when
# FLO_CUM(R,P,C,Y1,Y2,'UP') is EPS (L44).

"""
    eq_cumflo!(tm::TimesModel) -> Int

Generate every EQ_CUMFLO row from `tm.data`, creating the VAR_FLO, VAR_IRE,
VAR_ACT and VAR_CUMFLO columns it references. Returns the number of rows.

    EQ_CUMFLO(RPC_CUMFLO(RP(R,P),C,ALLYEAR,LL)) ..
      SUM(TT(T)\$[period T overlaps ALLYEAR..LL],
          SUM((RTP_VINTYR(R,V,T,P),RTPCS_VARF(R,T,P,C,TS)), W(T) * (
              [cal_red C COM TS P T]\$RP_STD(R,P) +
              (SUM(RPC_IRE(R,P,C,IE),VAR_IRE(R,V,T,P,C,TS,IE))\$(NOT RPC_AIRE(R,P,C)) +
               (VAR_ACT(R,V,T,P,TS)*PRC_ACTFLO(R,V,P,C))\$RPC_AIRE(R,P,C))\$RP_IRE(R,P)
          ))\$RPC(R,P,C) +
          SUM((RTP_VINTYR(R,V,T,P),RTP_VARA(R,T,P),PRC_TS(R,P,TS)), W(T) * VAR_ACT(R,V,T,P,TS))
          \$SAMEAS(%PGPRIM%,C)
      ) / %CUFSCAL%
      =E=
      VAR_CUMFLO(R,P,C,ALLYEAR,LL)\$(MAPVAL(FLO_CUM(R,P,C,ALLYEAR,LL,'UP')) NE 8);

with, unless %OBJ% is LIN (L20, L23):
  overlap: E(T) >= YEARVAL(ALLYEAR) and B(T) <= YEARVAL(LL);
  W(T) = MAX(0, MIN(E(T),YEARVAL(LL)) - MAX(B(T),YEARVAL(ALLYEAR)) + 1);
and when %OBJ% is LIN (L21, L24):
  overlap: M(T)+LAGT(T) > YEARVAL(ALLYEAR) and M(T)-LEAD(T) < YEARVAL(LL);
  W(T) = SUM(TPULSEYR(T,YEAR)\$(ORD(YEAR) >= ORD(ALLYEAR) and ORD(YEAR) <= ORD(LL)), TPULSE(T,YEAR)).

The SOW tags (sow_tags.jl): the row is `%EQ%_CUMFLO(... %SOW%)` (L14), one per
SOW. With STAGES and no %SCUM%, L16 sets %SOW% to `,WW` and %SWT% to `,SOW`:
the flow terms are summed over SW_TSW(SOW,T,WW) (%SWSW%, L26-31) and the
activity is `%VARTT%_ACT(... %SWS%)` with TT(T) (L36), both `at = t`; the
right-hand side `%VAR%_CUMFLO(... %SWT%)` is the row's own SOW (L44). The
%SCUM% form (SPINES, recurrin.stc) and S_FLO_CUM in the L44 test are changes
74 and 75.

GAMS: eqcumflo.mod L14-45, v4.9.7. The LIN branch is checked on the crafted
case demo12_cumlin (layer 2; test/unit/test_cum_lin.jl).
"""
function eq_cumflo!(tm::TimesModel)
    lin = uppercase(gswitch(tm, "OBJ", "")) == "LIN"
    pgprim = uppercase(strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"']))
    cufscal = parse(Float64, gswitch(tm, "CUFSCAL", "10"))

    rpc_cumflo = gset(tm, "RPC_CUMFLO")
    rp = gset(tm, "RP")
    milestonyr = gset(tm, "MILESTONYR")       # TT(T): both aliases of MILESTONYR (initmty.mod L94)
    modlyear = gset(tm, "MODLYEAR")
    rtp_vintyr = gset(tm, "RTP_VINTYR")
    rtpcs_varf = gset(tm, "RTPCS_VARF")
    rtp_vara = gset(tm, "RTP_VARA")
    prc_ts = gset(tm, "PRC_TS")
    rpc = gset(tm, "RPC")
    rp_std = gset(tm, "RP_STD")
    rp_ire = gset(tm, "RP_IRE")
    rpc_ire = gset(tm, "RPC_IRE")
    rpc_aire = gset(tm, "RPC_AIRE")
    prc_actflo = gparam(tm, "PRC_ACTFLO")
    flo_cum = gparam(tm, "FLO_CUM")
    yearval = gparam(tm, "YEARVAL")
    pB, pE, pM = gparam(tm, "B"), gparam(tm, "E"), gparam(tm, "M")
    lagt, lead = gparam(tm, "LAGT"), gparam(tm, "LEAD")

    vint_of_rtp = indexby(rtp_vintyr, (1, 3, 4))       # (r,t,p) -> (r,v,t,p)
    varf_of_rtpc = indexby(rtpcs_varf, (1, 2, 3, 4))    # (r,t,p,c) -> (r,t,p,c,ts)
    ts_of_rp = indexby(prc_ts, (1, 2))
    ire_of_rpc = indexby(rpc_ire, (1, 2, 3))
    # LIN weights: ORD over ALLYEAR and the pulse years of each period.
    ordyear = Dict(k[1] => i for (i, k) in enumerate(gset(tm, "ALLYEAR").keys))
    pulse_of_t = lin ? indexby(gset(tm, "TPULSEYR"), (1,)) : Dict{Tuple{String},Vector{NTuple{2,String}}}()
    tpulse = lin ? gparam(tm, "TPULSE") : nothing

    yv(y) = yearval[(y,)]
    function weight(t, y1, y2)::Union{Nothing,GNum}
        if lin
            (pM[(t,)] + lagt[(t,)] > yv(y1) && pM[(t,)] - lead[(t,)] < yv(y2)) || return nothing
            w = GZERO
            for (_, year) in get(pulse_of_t, (t,), NTuple{2,String}[])
                (ordyear[year] >= ordyear[y1] && ordyear[year] <= ordyear[y2]) || continue
                w = w + gv(tpulse, (t, year))
            end
            return w
        else
            (pE[(t,)] >= yv(y1) && pB[(t,)] <= yv(y2)) || return nothing
            return GNum(max(0.0, min(pE[(t,)], yv(y2)) - max(pB[(t,)], yv(y1)) + 1))
        end
    end

    n = 0
    for (r, p, c, y1, y2) in rpc_cumflo
        (r, p) in rp || continue
        for sow in sow_rows(tm)   # %SOW% (L14)
            set_sow!(tm, sow)
            lhs = JuMP.AffExpr(0.0)
            for (t,) in milestonyr
                w = weight(t, y1, y2)
                w === nothing && continue
                ws = w / cufscal
                vints = get(vint_of_rtp, (r, t, p), NTuple{4,String}[])
                if (r, p, c) in rpc
                    for (_, v, _, _) in vints
                        (v,) in modlyear || continue
                        for (_, _, _, _, ts) in get(varf_of_rtpc, (r, t, p, c), NTuple{5,String}[])
                            # L26-31: SUM(%SWSW% (...)) with %SOW% set to ,WW (L16): the sum over SW_TSW(SOW,T,WW), `at=t`
                            (r, p) in rp_std && cal_nored!(lhs, tm, ws, r, v, t, p, c, ts; at=t)
                            if (r, p) in rp_ire
                                if !((r, p, c) in rpc_aire)
                                    for (_, _, _, ie) in get(ire_of_rpc, (r, p, c), NTuple{4,String}[])
                                        addterm!(lhs, ws, tm, "VAR_IRE", r, v, t, p, c, ts, ie; at=t)
                                    end
                                else
                                    addterm!(lhs, ws * gv(prc_actflo, (r, v, p, c)), tm, "VAR_ACT", r, v, t, p, ts; at=t)
                                end
                            end
                        end
                    end
                end
                if uppercase(c) == pgprim && (r, t, p) in rtp_vara
                    for (_, v, _, _) in vints
                        (v,) in modlyear || continue
                        for (_, _, ts) in get(ts_of_rp, (r, p), NTuple{3,String}[])
                            addterm!(lhs, ws, tm, "VAR_ACT", r, v, t, p, ts; at=t)   # %VARTT%_ACT(R,V,T,P,TS %SWS%), TT(T) (L36)
                        end
                    end
                end
            end

            rhs = JuMP.AffExpr(0.0)
            if !iseps(flo_cum, (r, p, c, y1, y2, "UP"))
                addterm!(rhs, GNum(1.0), tm, "VAR_CUMFLO", r, p, c, y1, y2)   # %VAR%_CUMFLO(... %SWT%), %SWT% set to ,SOW (L16, L44)
            end
            gconstraint!(tm, eqtag(tm, "EQ_CUMFLO"), sowkey(tm, (r, p, c, y1, y2)), "E", lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end
