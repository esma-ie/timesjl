# EQ_STGAUX: auxiliary flows of storage processes, tied to the storage level
# (PRC_ACTFLO of the auxiliary commodity), to the charging flows or to the
# discharging flows (COEF_PTRAN, from FLO_FUNC/FLO_SUM).
#
# GAMS: eqstgaux.mod L14-42, v4.9.7, included from eqmain.mod L170 as
# `$BATINCLUDE eqstgaux.%OBJ%`, with %OBJ% = mod unless the run sets OBJ LIN
# (eqmain.mod L33; eqstgaux.lin differs from eqstgaux.mod only in the
# inter-period storage terms, L25-31: M1.3 change 49); declared eqdeclr.mod L90
# (R,ALLYEAR,ALLYEAR,P,C,S), =E=.
#
#   EQ_STGAUX(RTP_VINTYR(R,V,T,P),C,RTS(S))$((RPCS_VAR(R,P,C,S)*(NOT RPC_STG(R,P,C)+RPC_EMIS(R,P,C)))$RP_STG(R,P))..
#     VAR_FLO(R,V,T,P,C,S)
#     =E=
#     SUM(ANNUAL(SL), PRC_ACTFLO(R,V,P,C) *
#         (SUM(PRC_TS(R,P,TS)$TS_MAP(R,TS,S), VAR_ACT(R,V,T,P,TS)/RS_STGPRD(R,TS)) * G_YRFR(R,S)
#          - SUM(TOP(PRC_STGIPS(R,P,COM),IO),
#              (VAR_SIN(R,V,T,P,COM,SL)$IPS(IO) - VAR_SOUT(R,V,T,P,COM,SL)$(NOT IPS(IO)))/PRC_ACTFLO(R,V,P,COM)) *
#            SUM(PERIODYR(T,Y_EOH)$(YEARVAL(Y_EOH) GE M(T)),
#              MIN(1,YEARVAL(Y_EOH)-M(T)+MAX(0,M(T)+D(T)/2-E(T))) * ((1-STG_LOSS(R,V,P,SL))**(E(T)-YEARVAL(Y_EOH)+0.5)))
#         ) * (1+((1-STG_LOSS(R,V,P,SL))**(M(T)-E(T)-MIN(0.5,MAX(0,M(T)+D(T)/2-E(T))))-1)$PRC_MAP(R,'STK',P)))
#     + SUM((COM_GMAP(R,CG,COM),TOP(RPC_STG(R,P,COM),'IN'),RPCS_VAR(R,P,COM,TS))$COEF_PTRAN(R,V,P,CG,COM,C,TS),
#           (VAR_SIN(R,V,T,P,COM,TS)*COEF_PTRAN(R,V,P,CG,COM,C,TS))$((NOT PRC_MAP(R,'NST',P))+PRC_NSTTS(R,P,TS)) *
#           RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS)))
#     + SUM((COM_GMAP(R,CG,C),TOP(RPC_STG(R,P,COM),'OUT'),RPCS_VAR(R,P,COM,TS))$COEF_PTRAN(R,V,P,CG,C,COM,S),
#           (VAR_SOUT(R,V,T,P,COM,TS)*(1/COEF_PTRAN(R,V,P,CG,C,COM,S)))$(PRC_NSTTS(R,P,TS) EQV RPC_STGN(R,P,COM,'OUT')) *
#           RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS)));
#
# The domain condition reads `NOT (RPC_STG + RPC_EMIS)`: NOT binds more
# loosely than + (docs/discrepancies.md G19), so the auxiliary commodity is
# neither stored nor an RPC_EMIS emission. `SUM(ANNUAL(SL), ...)` is a sum
# over the one element ANNUAL, so the level term is counted once. Macro
# expansions as in eqstgtss.jl.
#
# Inter-period storage (L25-32, M1.3 change 19b): the in- and outflows of
# the stored commodities (PRC_STGIPS) in the latter half of the period are
# subtracted from the level, each year from M(T) weighted by the part of it
# after the middle of the period and discounted for losses to E(T); for a
# STK process the whole bracket is scaled up to the level in the middle of
# the period. Y_EOH is a set of its own (setglobs.gms L146-147), as in
# eqstgips.jl. `IPS(IO)`: IN charges, OUT discharges (IPS = {IN, N}).
#
# Under OBJ LIN (eqstgaux.lin L25-31, M1.3 change 49) the level is the one at
# the milestone year: half a year of the IPS flows is subtracted, discounted
# for half a year's losses, and a STK process's bracket is scaled by
# (1-STG_LOSS)**(-0.5):
#
#   - SUM(TOP(PRC_STGIPS(R,P,COM),IO), 0.5 *
#       (VAR_SIN(R,V,T,P,COM,SL)$IPS(IO) - VAR_SOUT(R,V,T,P,COM,SL)$(NOT IPS(IO))) / PRC_ACTFLO(R,V,P,COM) *
#       ((1-STG_LOSS(R,V,P,SL))**0.5))
#   ) * (1+((1-STG_LOSS(R,V,P,SL))**(-0.5)-1)$PRC_MAP(R,'STK',P))

"""
    eq_stgaux!(tm::TimesModel) -> Int

Generate every EQ_STGAUX row (eqmain.mod L170) from `tm.data`. Returns the
number of rows generated.

The SOW tags (sow_tags.jl): the row is `%EQ%_STGAUX(... %SWT%)` (L14); every
term is `%VAR%_X(... %SOW%)` (L17, L24, L27, L36, L39).

GAMS: eqstgaux.mod L14-42; eqstgaux.lin L25-31 under OBJ LIN; v4.9.7.
"""
function eq_stgaux!(tm::TimesModel)
    x = stg_context(tm)
    isempty(x.rp_stg) && return 0
    one, half = GNum(1.0), GNum(0.5)
    lin = uppercase(gswitch(tm, "OBJ", "")) == "LIN"             # eqmain.mod L170: eqstgaux.%OBJ%
    rpc_emis = gset(tm, "RPC_EMIS")
    com_gmap = gset(tm, "COM_GMAP")
    g_yrfr = gparam(tm, "G_YRFR")
    rs_stgprd = gparam(tm, "RS_STGPRD")
    coef_ptran = gparam(tm, "COEF_PTRAN")
    aux_of_rp = indexby(x.rpcs_var, (1, 2))                       # (r,p) -> RPCS_VAR(r,p,c,s)
    ts_of_rp = indexby(x.prc_ts, (1, 2))                          # (r,p) -> PRC_TS(r,p,ts)
    ts_map = gset(tm, "TS_MAP")
    ptran_in = indexby(coef_ptran, (1, 2, 3, 6))                  # (r,v,p,c) -> COEF_PTRAN(r,v,p,cg,com,c,ts)
    ptran_out = indexby(coef_ptran, (1, 2, 3, 5, 7))              # (r,v,p,c,s) -> COEF_PTRAN(r,v,p,cg,c,com,s)
    varts_of = indexby(x.rpcs_var, (1, 2, 3))                     # (r,p,com) -> RPCS_VAR(r,p,com,ts)
    ipx = (pM = gparam(tm, "M"), pD = gparam(tm, "D"), pE = gparam(tm, "E"), yearval = gparam(tm, "YEARVAL"),
           periodyr_of_t = indexby(gset(tm, "PERIODYR"), (1,)), y_eoh = gset(tm, "Y_EOH"))
    vx, tx = gset(tm, "MODLYEAR"), eq_periods(tm)                 # %R_V_T%: V, and SUBT in a stepped run (maindrv.mod L38-40)
    off = rts_off(tm)                    # RTS(S): S+NORTS(R,T,S) with dynamic timeslices (M1.3 change 67)
    rtp_vintyr = gset(tm, "RTP_VINTYR")
    return eq_stgaux!(tm, x,
        (; one, half, lin, rpc_emis, com_gmap, g_yrfr, rs_stgprd, coef_ptran, aux_of_rp, ts_of_rp, ts_map, ptran_in, ptran_out,
           varts_of, ipx, vx, tx, off, rtp_vintyr))
end

# `eq_stgaux!` with the storage context `x` (`stg_context`, untyped out of `tm.cache`) and the sets,
# parameters and incidence maps of the outer method, `d`, as typed arguments: `gset` and `gparam` give
# an abstract `GamsSet` or `GamsParam`, so the outer method does not know their types. Julia compiles
# this method for the concrete types (a function barrier; Phase 2, change 3). The rows, the terms,
# their arithmetic and their order are unchanged. GAMS: eqstgaux.mod L14-42; eqstgaux.lin L25-31, v4.9.7.
function eq_stgaux!(tm::TimesModel, x::NamedTuple, d::NamedTuple)
    (; one, half, lin, rpc_emis, com_gmap, g_yrfr, rs_stgprd, coef_ptran, aux_of_rp, ts_of_rp, ts_map, ptran_in, ptran_out,
       varts_of, ipx, vx, tx, off, rtp_vintyr) = d
    n = 0
    for (r, v, t, p) in rtp_vintyr
        ((v,) in vx && (t,) in tx) || continue
        (r, p) in x.rp_stg || continue
        stk = (r, "STK", p) in x.prc_map
        nst = (r, "NST", p) in x.prc_map
        for (_, _, c, s) in get(aux_of_rp, (r, p), NO4)
            ((r, p, c) in x.rpc_stg_set || (r, p, c) in rpc_emis) && continue
            off(r, t, s) && continue
            for sow in sw_rows(tm, t)   # %SWT% (L14)
                set_sow!(tm, sow)
                lhs = JuMP.AffExpr(0.0)
                addterm!(lhs, one, tm, "VAR_FLO", r, v, t, p, c, s)                              # L17
                rhs = JuMP.AffExpr(0.0)
                # Storage level, L22-24, less the IPS flows L25-30, scaled by L32 for STK.
                af = gv(x.prc_actflo, (r, v, p, c))
                if !iszero(af)
                    base = one - gv(x.stg_loss, (r, v, p, "ANNUAL"))
                    f = !stk ? one : lin ? one + (gpow(base, -half) - one) :                 # .lin L31
                        ips_mid_factor(ipx, x, r, v, t, p)                                      # L32
                    for (_, _, ts) in get(ts_of_rp, (r, p), NO3)
                        (r, ts, s) in ts_map || continue
                        addterm!(rhs, af * (one / gv(rs_stgprd, (r, ts)) * gv(g_yrfr, (r, s))) * f, tm, "VAR_ACT", r, v, t, p, ts)
                    end
                    ips = get(x.stgips_of_rp, (r, p), NO3)
                    if !isempty(ips)
                        w = lin ? GZERO : ips_late_weight(ipx, x, r, v, t, p)                    # L28-30
                        for (_, _, com) in ips, io in ("IN", "OUT")
                            (r, p, com, io) in x.top || continue
                            k = lin ? af * (half / gv(x.prc_actflo, (r, v, p, com)) * gpow(base, half)) * f :   # .lin L26-29
                                      af * (w / gv(x.prc_actflo, (r, v, p, com))) * f
                            io == "IN" ? addterm!(rhs, -k, tm, "VAR_SIN", r, v, t, p, com, "ANNUAL") :
                                         addterm!(rhs, k, tm, "VAR_SOUT", r, v, t, p, com, "ANNUAL")
                        end
                    end
                end
                # Charging flows, L35-37.
                for (_, _, _, cg, com, _, ts) in get(ptran_in, (r, v, p, c), NO7)
                    ((r, cg, com) in com_gmap && (r, p, com, "IN") in x.top && (r, p, com) in x.rpc_stg_set &&
                     (r, p, com, ts) in x.rpcs_var) || continue
                    (!nst || (r, p, ts) in x.prc_nstts) || continue
                    k = gv(coef_ptran, (r, v, p, cg, com, c, ts)) * (gv(x.rs_fr, (r, s, ts)) * (one + gv(x.rtcs_fr, (r, t, c, s, ts))))
                    addterm!(rhs, k, tm, "VAR_SIN", r, v, t, p, com, ts)
                end
                # Discharging flows, L38-40.
                for (_, _, _, cg, _, com, _) in get(ptran_out, (r, v, p, c, s), NO7)
                    ((r, cg, c) in com_gmap && (r, p, com, "OUT") in x.top && (r, p, com) in x.rpc_stg_set) || continue
                    stgn_out = (r, p, com, "OUT") in x.rpc_stgn
                    inv = one / gv(coef_ptran, (r, v, p, cg, c, com, s))
                    for (_, _, _, ts) in get(varts_of, (r, p, com), NO4)
                        ((r, p, ts) in x.prc_nstts) == stgn_out || continue
                        k = inv * (gv(x.rs_fr, (r, s, ts)) * (one + gv(x.rtcs_fr, (r, t, c, s, ts))))
                        addterm!(rhs, k, tm, "VAR_SOUT", r, v, t, p, com, ts)
                    end
                end
                gconstraint!(tm, eqtag(tm, "EQ_STGAUX"), swt(tm, (r, v, t, p, c, s), t), "E", lhs, rhs) === nothing || (n += 1)
            end
        end
    end
    return n
end

"`MAX(0,M(T)+D(T)/2-E(T))`: how far the middle of period T lies past its end year less half a period (eqstgaux.mod L30, L32)."
ips_shift(ipx, t) = gmax(GZERO, gv(ipx.pM, (t,)) + gv(ipx.pD, (t,)) / GNum(2.0) - gv(ipx.pE, (t,)))

"""
    ips_late_weight(ipx, x, r, v, t, p) -> GNum

`SUM(PERIODYR(T,Y_EOH)\$(YEARVAL(Y_EOH) GE M(T)), MIN(1,YEARVAL(Y_EOH)-M(T)+MAX(0,M(T)+D(T)/2-E(T))) *
((1-STG_LOSS(R,V,P,'ANNUAL'))**(E(T)-YEARVAL(Y_EOH)+0.5)))`: the IPS flows of the
latter half of period T, discounted for losses to its end.

GAMS: eqstgaux.mod L28-30, v4.9.7.
"""
function ips_late_weight(ipx, x, r, v, t, p)
    one, half = GNum(1.0), GNum(0.5)
    m, e = gv(ipx.pM, (t,)), gv(ipx.pE, (t,))
    sh = ips_shift(ipx, t)
    base = one - gv(x.stg_loss, (r, v, p, "ANNUAL"))
    w = GZERO
    for (_, y) in get(ipx.periodyr_of_t, (t,), NO2)
        (y,) in ipx.y_eoh || continue
        yv = gv(ipx.yearval, (y,))
        yv.v >= m.v || continue
        w = w + gmin(one, yv - m + sh) * gpow(base, e - yv + half)
    end
    return w
end

"""
    ips_mid_factor(ipx, x, r, v, t, p) -> GNum

`1+((1-STG_LOSS(R,V,P,'ANNUAL'))**(M(T)-E(T)-MIN(0.5,MAX(0,M(T)+D(T)/2-E(T))))-1)`: for a STK
process, the level in the middle of period T relative to the level at its end.

GAMS: eqstgaux.mod L32, v4.9.7.
"""
function ips_mid_factor(ipx, x, r, v, t, p)
    one = GNum(1.0)
    base = one - gv(x.stg_loss, (r, v, p, "ANNUAL"))
    ex = gv(ipx.pM, (t,)) - gv(ipx.pE, (t,)) - gmin(GNum(0.5), ips_shift(ipx, t))
    return one + (gpow(base, ex) - one)
end
