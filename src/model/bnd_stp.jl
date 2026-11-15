# M1.5 change 3: the variable bounds of a stepped (myopic) run and the model of one step.
#
# GAMS (v4.9.7): solve.stp L193 (bnd_ucw.mod), L199-233 (the fixed periods and
# the cumulative variables), L267-281 (the pending periods), L319 (bndmain.mod
# with its second argument 1); maindrv.mod L92 (bndmain.mod with 0).
#
# In GAMS the bounds are attributes of the variables and live through the
# whole run: a statement of one step stays in force in the next unless a
# later statement overwrites it. bndmain.mod's second call (after the SOLVE
# of each step) resets some families to their defaults before it takes the
# bounds from the data again, and leaves the others as they are:
#
#   reset and set again        VAR_ACT, VAR_FLO (bnd_act.mod L13-14, bnd_flo.mod
#                              L12-13), VAR_SIN and VAR_SOUT of storage
#                              processes (bnd_stg.mod L12-13), VAR_NCAP, VAR_CAP,
#                              VAR_COMNET, VAR_COMPRD (bnd_set.mod L20-21), the
#                              slacks of the user constraints (bnd_ucv.mod
#                              L24-25, partly: see `bnd_ucw!`)
#   kept from step to step     VAR_IRE, VAR_UPS, VAR_UPT, VAR_UDP, VAR_SCAP
#                              (bndmain.mod L15 clears them in the first call
#                              only), VAR_BLND, VAR_CUMFLO, VAR_CUMCOM,
#                              VAR_CUMCST (bnd_cum.mod: first call only), VAR_OBJ
#
# So TIMES.jl keeps one `BoundTable` for the run (`tm.cache["STP_BOUNDS"]`)
# and applies the statements to it in GAMS's order:
#
#   stp_bounds_init!   maindrv.mod L92: the table of an ordinary run (SUBT is
#                      every period then, ppmain.mod L253)
#   stp_step_bounds!   solve.stp L193-233 and L267-281, before the SOLVE of a step
#   stp_bndmain!       solve.stp L319, after it
#
# `stp_model` gives the model of one step: a new JuMP model on the run's data,
# with the run's bound table and point store.
#
# V is a control index of the statements over RTP_VINTYR and RTP_CPTYR:
# solve.stp L115 (`V(FORWARD) = NO`) takes the pending periods out of it, so
# those statements do not reach a vintage that is a pending period.
#
# Not translated (the features are refused): VAR_ELAST (L211, L276; elastic
# demand) and VAR_DAM (L212; damage); the REG_FIXT loops (L199, L234, L266,
# L282; FIXBOH); L236-264 (MY_FYEAR, FIXBOH); the %SOW% forms (STAGES).

"The bound table of the stepped run (see `stp_bounds_init!`)."
stp_bounds(tm::TimesModel) = tm.cache["STP_BOUNDS"]::BoundTable

"True for the model of one step of a stepped run ([`stp_model`](@ref)), which is generated; the run itself is not."
stp_is_step(tm::TimesModel) = get(tm.cache, "STP_STEP", false)::Bool

"""
    stp_bounds_init!(tm) -> BoundTable

The bounds a stepped run starts from: bndmain.mod as maindrv.mod L92 includes
it (`\$BATINCLUDE bndmain.%1 %1 0`), before solve.stp. SUBT is every period
at that point (ppmain.mod L253: `SET SUBT(T) / SET.T /`), so `%R_T%` selects
every period and the table is the one of an ordinary run, the bounds of the
early retirements and of the grid's reference angles included
(mod_vars.mod L94-95). `stp_init!` calls it before the first partition.

GAMS: maindrv.mod L92; bndmain.mod L15-87; ppmain.mod L253, v4.9.7.
"""
function stp_bounds_init!(tm::TimesModel)
    delete!(tm.cache, "BOUNDS")
    bt = bndmain(tm)
    delete!(tm.cache, "BOUNDS")          # the run's table is not the cached table of one generation
    tm.cache["STP_BOUNDS"] = bt
    return bt
end

# VAR.FX(key) = VAR.L(key) for a fixed period, = 0 for a pending one (`L === nothing`).
_stp_fix!(bt, tm, var, key, L) =
    setbound!(bt, tm, var, key, :fx, GNum(L === nothing ? 0.0 : get(L, key, 0.0)))

# The process variables of the periods `periods`: fixed at their levels (solve.stp L200-207) when
# `backward`, at zero (L268-272) otherwise. V is the control index of RTP_VINTYR(R,V,T,P).
function _stp_fix_proc!(bt::BoundTable, tm::TimesModel, periods, backward::Bool)
    d = tm.data
    S(name, n) = gset_opt(d, name, n)
    L(name, n) = backward ? stp_level(tm, name, n) : nothing
    V = S("MODLYEAR", 1)
    ts_of_rp = indexby(S("PRC_TS", 3), (1, 2))
    var_of_rp = indexby(S("RPCS_VAR", 4), (1, 2))
    rp_flo, rpc_stg = S("RP_FLO", 2), S("RPC_STG", 3)
    ie_of_rpc = indexby(S("RPC_IRE", 4), (1, 2, 3))
    ups_of_rp = indexby(S("RPS_UPS", 3), (1, 2))
    rp_dp, rp_upr = S("RP_DP", 2), S("RP_UPR", 3)
    bd = [k[1] for k in S("BD", 1).keys]
    upt = [k[1] for k in S("UPT", 1).keys]
    act, flo, ire, sin, sout = L("VAR_ACT", 5), L("VAR_FLO", 6), L("VAR_IRE", 7), L("VAR_SIN", 6), L("VAR_SOUT", 6)
    ups, upty, udp = L("VAR_UPS", 6), L("VAR_UPT", 6), L("VAR_UDP", 6)
    no3, no4 = NTuple{3,String}[], NTuple{4,String}[]
    for (r, v, t, p) in S("RTP_VINTYR", 4).keys
        ((t,) in periods && (v,) in V) || continue
        isflo = (r, p) in rp_flo
        for (_, _, s) in get(ts_of_rp, (r, p), no3)                             # L200 / L268: $PRC_TS(R,P,S)
            _stp_fix!(bt, tm, "VAR_ACT", (r, v, t, p, s), act)
        end
        for (_, _, c, s) in get(var_of_rp, (r, p), no4)                         # $RPCS_VAR(R,P,C,S)
            isflo && _stp_fix!(bt, tm, "VAR_FLO", (r, v, t, p, c, s), flo)      # L201 / L269: *RP_FLO(R,P)
            if (r, p, c) in rpc_stg                                             # L203-204 / L271-272: *RPC_STG(R,P,C)
                _stp_fix!(bt, tm, "VAR_SIN", (r, v, t, p, c, s), sin)
                _stp_fix!(bt, tm, "VAR_SOUT", (r, v, t, p, c, s), sout)
            end
            backward || continue                                                # L270 is a comment: VAR_IRE stays free
            for (_, _, _, ie) in get(ie_of_rpc, (r, p, c), no4)                 # L202: *RPC_IRE(R,P,C,IE)
                _stp_fix!(bt, tm, "VAR_IRE", (r, v, t, p, c, s, ie), ire)
            end
        end
        backward || continue
        for (_, _, s) in get(ups_of_rp, (r, p), no3)                            # L205-206: $RPS_UPS(R,P,S)
            for l in bd
                _stp_fix!(bt, tm, "VAR_UPS", (r, v, t, p, s, l), ups)
            end
            (r, p) in rp_dp || continue
            for u in upt
                _stp_fix!(bt, tm, "VAR_UPT", (r, v, t, p, s, u), upty)
            end
        end
        for l in bd                                                             # L207: $(PRC_TS(R,P,S)$RP_UPR(R,P,BD))
            (r, p, l) in rp_upr || continue
            for (_, _, s) in get(ts_of_rp, (r, p), no3)
                _stp_fix!(bt, tm, "VAR_UDP", (r, v, t, p, s, l), udp)
            end
        end
    end
    return bt
end

"""
    stp_step_bounds!(tm) -> BoundTable

The bound statements of one step before its SOLVE, on the run's table. BACKWARD
holds the periods solved in earlier steps, FORWARD the pending ones.

    \$ BATINCLUDE bnd_ucw.%1                                                      (L193)
    VAR_ACT.FX(RTP_VINTYR(R,V,BACKWARD(T),P),S)\$(PRC_TS(R,P,S)) = VAR_ACT.L(R,V,T,P,S);              (L200)
    VAR_FLO.FX(RTP_VINTYR(R,V,BACKWARD(T),P),C,S)\$(RPCS_VAR(R,P,C,S)*RP_FLO(R,P)) = VAR_FLO.L(...);  (L201)
    VAR_IRE.FX(RTP_VINTYR(R,V,BACKWARD(T),P),C,S,IE)\$(RPCS_VAR(R,P,C,S)*RPC_IRE(R,P,C,IE)) = VAR_IRE.L(...);
    VAR_SIN.FX(RTP_VINTYR(R,V,BACKWARD(T),P),C,S)\$(RPCS_VAR(R,P,C,S)*RPC_STG(R,P,C)) = VAR_SIN.L(...);   (VAR_SOUT alike)
    VAR_UPS.FX(RTP_VINTYR(R,V,BACKWARD(T),P),S,BD(L))\$RPS_UPS(R,P,S) = VAR_UPS.L(R,V,T,P,S,L);
    VAR_UPT.FX(RTP_VINTYR(R,V,BACKWARD(T),P),S,UPT)\$(RPS_UPS(R,P,S)\$RP_DP(R,P)) = VAR_UPT.L(...);
    VAR_UDP.FX(RTP_VINTYR(R,V,BACKWARD(T),P),S,BD(L))\$(PRC_TS(R,P,S)\$RP_UPR(R,P,BD)) = VAR_UDP.L(...);   (L207)
    VAR_COMNET.FX(RTC_NET(R,BACKWARD(T),C),S)\$COM_TS(R,C,S) = VAR_COMNET.L(R,T,C,S);                  (L209)
    VAR_COMPRD.FX(RTC_PRD(R,BACKWARD(T),C),S)\$COM_TS(R,C,S) = VAR_COMPRD.L(R,T,C,S);                  (L210)
    VAR_NCAP.FX(R,BACKWARD(T),P)\$RP(R,P) = MAX(EPS,VAR_NCAP.L(R,T,P));                                (L214)
    VAR_CAP.UP(RTP(R,BACKWARD(T),P)) = INF;  VAR_CAP.LO(RTP(R,BACKWARD(T),P)) = 0;                    (L215-216)
    VAR_CAP.UP(NO_RVP(R,T,P))\$CAP_BND(R,T,P,'UP') = CAP_BND(R,T,P,'UP');   (.LO alike)               (L218-219)
    VAR_SCAP.FX(RTP_CPTYR(R,V,BACKWARD(T),P))\$PRC_RCAP(R,P) = VAR_SCAP.L(R,V,T,P);                    (L220)
    \$ BATINCLUDE bnd_cum.mod COM_VAR                                                                  (L227)
    VAR_CUMFLO.LO(R,P,C,YEAR,FIL)\$(NOT FLO_CUM(R,P,C,YEAR,FIL,'N')) = 0;                              (L229)
    VAR_CUMCOM.LO(R,C,COM_VAR,YEAR,FIL)\$(NOT COM_CUM(R,COM_VAR,YEAR,FIL,C,'N')) = 0;                  (L230)
    VAR_BLND.L(RT_PP,BLE,OPR)=0;                                                                      (L232)
    VAR_BLND.FX(R,BACKWARD(T),BLE,OPR)\$BLE_OPR(R,BLE,OPR) = VAR_BLND.L(R,T,BLE,OPR);                  (L233)

    VAR_ACT.FX(RTP_VINTYR(R,V,FORWARD(T),P),S)\$(PRC_TS(R,P,S)) = 0;                                   (L268)
    VAR_FLO.FX(RTP_VINTYR(R,V,FORWARD(T),P),C,S)\$(RPCS_VAR(R,P,C,S)*RP_FLO(R,P)) = 0;                 (L269)
    VAR_SIN.FX(RTP_VINTYR(R,V,FORWARD(T),P),C,S)\$(RPCS_VAR(R,P,C,S)*RPC_STG(R,P,C)) = 0;   (VAR_SOUT alike)
    VAR_COMNET.FX(RTCS_VARC(R,FORWARD(T),C,S)) = 0;  VAR_COMPRD.FX(RTCS_VARC(R,FORWARD(T),C,S)) = 0;  (L274-275)
    VAR_CAP.LO(RTP(R,FORWARD(T),P)) = 0;  VAR_CAP.UP(RTP(R,FORWARD(T),P)) \$= CAP_BND(RTP,'UP');       (L278-279)
    VAR_BLND.FX(R,FORWARD(T),BLE,OPR)\$BLE_OPR(R,BLE,OPR) = 0;                                         (L281)

`stp_step_prep!` calls it last: the data these statements read (the relaxed
right-hand sides, CAP_BND, NO_RVP, FIL, FLO_CUM, COM_CUM) are then as the
statements before them leave them, and no later data statement of the step
changes them.

Notes.
- A level is read from the point store (`StpPoint`): a record it does not
  hold has the level 0. MAX(EPS,x) of L214 is the bound 0 at x = 0 (EPS is a
  zero bound, G10).
- V is the control index of RTP_VINTYR and RTP_CPTYR, without the pending
  periods in a step (solve.stp L115). So L268-272 fix what earlier vintages
  do in a pending period and leave a pending vintage's own records alone;
  the equations do not reach those (their sums run over the same V).
- L215-216 and L278 give VAR_CAP its declared default. L218-219 take the
  bounds of the capacity of a step's period that holds a vintage of a fixed
  period (NO_RVP) from CAP_BND as L186-191 relaxed it.
- L229-230: VAR_CUMFLO and VAR_CUMCOM are positive, so only a record that
  has a lower bound changes.
- L232 sets the blending levels of the step's own periods to zero (RT_PP
  is SUBT without NO_RT in a step, L114): a starting point, no bound. L233
  fixes the blending of the periods already solved at their levels.
- L281 fixes the blending of the pending periods at zero, and no statement
  resets a bound of VAR_BLND: it stays fixed when those periods become the
  periods of a later step. Translated as written and flagged
  (docs/m15-plan.md, "Change 3 as built").

GAMS: solve.stp L193, L199-233, L267-281; bnd_ucw.mod with bnd_ucv.mod;
bnd_cum.mod L23-24, L39-40, L44-48, v4.9.7.
"""
function stp_step_bounds!(tm::TimesModel)
    bt = stp_bounds(tm)
    d = tm.data
    S(name, n) = gset_opt(d, name, n)
    backward, forward = S("BACKWARD", 1), S("FORWARD", 1)
    V = S("MODLYEAR", 1)
    bnd_ucw!(bt, tm; reset=true)                                                # L193
    # --- the periods of earlier steps ----------------------------------------------------------------
    _stp_fix_proc!(bt, tm, backward, true)                                      # L200-207
    ts_of_rc = indexby(S("COM_TS", 3), (1, 2))
    no3 = NTuple{3,String}[]
    for (var, set) in (("VAR_COMNET", "RTC_NET"), ("VAR_COMPRD", "RTC_PRD"))    # L209-210
        lev = stp_level(tm, var, 4)
        for (r, t, c) in S(set, 3).keys
            (t,) in backward || continue
            for (_, _, s) in get(ts_of_rc, (r, c), no3)
                _stp_fix!(bt, tm, var, (r, t, c, s), lev)
            end
        end
    end
    ncap_l = stp_level(tm, "VAR_NCAP", 3)
    for (r, p) in S("RP", 2).keys, (t,) in backward.keys                        # L214
        setbound!(bt, tm, "VAR_NCAP", (r, t, p), :fx, GNum(max(0.0, get(ncap_l, (r, t, p), 0.0))))
    end
    rtp = S("RTP", 3)
    for k in rtp.keys                                                           # L215-216
        (k[2],) in backward || continue
        setbound!(bt, tm, "VAR_CAP", k, :up, GNum(Inf))
        setbound!(bt, tm, "VAR_CAP", k, :lo, GNum(0.0))
    end
    cap_bnd = gparam_opt(d, "CAP_BND", 4)
    for k in S("NO_RVP", 3).keys                                                # L218-219
        setbound_if!(bt, tm, "VAR_CAP", k, :up, gv(cap_bnd, (k..., "UP")))
        setbound_if!(bt, tm, "VAR_CAP", k, :lo, gv(cap_bnd, (k..., "LO")))
    end
    prc_rcap = S("PRC_RCAP", 2)
    if !isempty(prc_rcap)                                                       # L220
        scap_l = stp_level(tm, "VAR_SCAP", 4)
        for (r, v, t, p) in S("RTP_CPTYR", 4).keys
            ((t,) in backward && (v,) in V && (r, p) in prc_rcap) || continue
            _stp_fix!(bt, tm, "VAR_SCAP", (r, v, t, p), scap_l)
        end
    end
    # --- the cumulative variables --------------------------------------------------------------------
    bnd_cum!(bt, tm)                                                            # L227 (its data: bnd_cum_data!)
    fil = S("FIL", 1)
    flo_cum, com_cum = gparam_opt(d, "FLO_CUM", 6), gparam_opt(d, "COM_CUM", 6)
    for (var, isn) in (("VAR_CUMFLO", k -> haskey(flo_cum, (k[1], k[2], k[3], k[4], k[5], "N"))),      # L229
                       ("VAR_CUMCOM", k -> haskey(com_cum, (k[1], k[3], k[4], k[5], k[2], "N"))))      # L230
        recs = get(bt.recs, var, nothing)
        recs === nothing && continue
        for (k, (lo, up)) in collect(recs)
            ((k[5],) in fil && lo != 0 && !isn(k)) && (recs[k] = (0.0, up))
        end
    end
    # --- blending ------------------------------------------------------------------------------------
    ble_opr = S("BLE_OPR", 3)
    if !isempty(ble_opr)
        blnd_l = stp_level(tm, "VAR_BLND", 4)
        rt_pp = S("RT_PP", 2)
        filter!(kv -> !((kv.first[1], kv.first[2]) in rt_pp), blnd_l)           # L232
        for (r, ble, opr) in ble_opr.keys, (t,) in backward.keys                # L233
            _stp_fix!(bt, tm, "VAR_BLND", (r, t, ble, opr), blnd_l)
        end
    end
    # --- the pending periods -------------------------------------------------------------------------
    _stp_fix_proc!(bt, tm, forward, false)                                      # L268-272
    for k in S("RTCS_VARC", 4).keys                                             # L274-275
        (k[2],) in forward || continue
        _stp_fix!(bt, tm, "VAR_COMNET", k, nothing)
        _stp_fix!(bt, tm, "VAR_COMPRD", k, nothing)
    end
    for k in rtp.keys                                                           # L278-279
        (k[2],) in forward || continue
        setbound!(bt, tm, "VAR_CAP", k, :lo, GNum(0.0))
        setbound_if!(bt, tm, "VAR_CAP", k, :up, gv(cap_bnd, (k..., "UP")))
    end
    for (r, ble, opr) in ble_opr.keys, (t,) in forward.keys                     # L281
        _stp_fix!(bt, tm, "VAR_BLND", (r, t, ble, opr), nothing)
    end
    return bt
end

"""
    stp_bndmain!(tm) -> BoundTable

The bound statements of bndmain.mod as solve.stp L319 includes it after the
SOLVE of a step (`\$BATINCLUDE bndmain.%1 %1 1`), on the run's table.
`stp_next!` calls it last: SUBT then holds the periods of the next step, V
every period again (L311), and the user constraints' period sets are
restored (L312-314).

    VAR_ACT.LO(R,V,T,P,S) = 0;  VAR_ACT.UP(R,V,T,P,S) = INF;         (bnd_act.mod L13-14, then L20-24)
    VAR_FLO.LO(R,V,T,P,C,S) = 0;  VAR_FLO.UP(R,V,T,P,C,S) = INF;     (bnd_flo.mod L12-13, then L27-39)
    VAR_SIN.LO(R,V,T,P,C,S)\$PRC_MAP(R,'STG',P) = 0;  .UP = INF;      (bnd_stg.mod L12-13, then L14-24; VAR_SOUT alike)
    VAR_NCAP.LO(R,T,P) = 0;  VAR_NCAP.UP(R,T,P) = INF;               (bnd_set.mod L20-21, then L23-25; VAR_CAP,
                                                                      VAR_COMNET and VAR_COMPRD alike)
    \$ BATINCLUDE bnd_ucw.%1                                          (bndmain.mod L69: resets as in `bnd_ucw!`)
    VAR_OBJ.LO/UP                                                    (bndmain.mod L74-79: no reset)

So the fixes of the step just solved are lifted for these families, and the
bounds of the data are taken again, the three statements written with
`%R_T%` for the periods of the next step. The two parts of bndmain.mod's
first call only (`\$IF %2==0`) are not repeated: the clearing of VAR_IRE,
VAR_UPS, VAR_UDP, VAR_UPT and VAR_SCAP (L15) and bnd_cum.mod (L64). Nor are
the bounds the declarations set (mod_vars.mod L94-95).

GAMS: solve.stp L319; bndmain.mod L15-87 with %2 = 1; bnd_act.mod; bnd_flo.mod;
bnd_stg.mod; bnd_set.mod; bnd_ucw.mod, v4.9.7.
"""
function stp_bndmain!(tm::TimesModel)
    bt = stp_bounds(tm)
    for var in ("VAR_ACT", "VAR_FLO", "VAR_NCAP", "VAR_CAP", "VAR_COMNET", "VAR_COMPRD")
        delete!(bt.recs, var)                                                   # every record at its default
    end
    stg = Set((r, p) for (r, m, p) in gset(tm, "PRC_MAP") if m == "STG")
    for var in ("VAR_SIN", "VAR_SOUT")                                          # bnd_stg.mod L12-13
        recs = get(bt.recs, var, nothing)
        recs === nothing || filter!(kv -> !((kv.first[1], kv.first[4]) in stg), recs)
    end
    bnd_act!(bt, tm)                                                            # bndmain.mod L26
    bnd_flo!(bt, tm)                                                            # L31
    bnd_stg!(bt, tm, "VAR_SIN", "IN", GNum(0.0))                                # L36
    bnd_stg!(bt, tm, "VAR_SOUT", "OUT", GNum(-Inf))                             # L37
    bnd_ncap_cap!(bt, tm)                                                       # L44-52
    bnd_com!(bt, tm)                                                            # L57-59
    bnd_ucw!(bt, tm; reset=true)                                                # L69
    bnd_obj!(bt, tm)                                                            # L73-79
    return bt
end

"""
    stp_model(tm) -> TimesModel

The model of the step `stp_step_prep!` has prepared: a new JuMP model with
its own variables and equations, on the run's data and switches. Its bounds
are the run's table (`stp_bounds`), and it shares the point store.
`generate!` builds it: the equations written with `%R_T%`, `%TX%` or
`%R_V_T%` for the periods of the step (`eq_periods`), the others for every
period; the variables of the other periods that these reach are columns,
fixed as `stp_step_bounds!` left them.

GAMS solves the same model object in every step and regenerates it from
the current sets and bounds; a model built anew gives the same LP.

GAMS: solve.stp L109-294; maindrv.mod L38-40, v4.9.7.
"""
function stp_model(tm::TimesModel)
    stepped(tm) || throw(ArgumentError("stp_model: not a stepped run (TIMESTEP is not set)"))
    haskey(tm.cache, "STP_BOUNDS") || throw(ArgumentError("stp_model: call stp_init! and stp_step_prep! first"))
    model = JuMP.Model()
    cache = Dict{String,Any}("STP_STEP" => true, "STP_POINT" => stp_point(tm), "BOUNDS" => stp_bounds(tm))
    for k in ("QLOG", "GAMS_WARNINGS")
        haskey(tm.cache, k) && (cache[k] = tm.cache[k])
    end
    return TimesModel(model, VariableStore(model), EquationStore(), tm.data, tm.reduce, tm.switches, cache)
end
