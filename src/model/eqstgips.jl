# EQ_STGIPS: inter-period storage (IPS). The storage level at the end of
# period T (VAR_ACT at ANNUAL) is the level at the end of T-1, reduced by the
# storage losses over D(T) years, plus the charging and minus the
# discharging over the period, each discounted for losses from the middle of
# its year to E(T). In the first period the level before it is an activity
# variable dated LEAD(T) years before the first milestone, which a second row
# fixes to the exogenous charge STG_CHRG.
#
# GAMS: eqstgips.mod L13-44, v4.9.7, included from eqmain.mod L169 as
# `$BATINCLUDE eqstgips.%OBJ%`, %OBJ% = mod unless the run sets OBJ LIN
# (eqstgips.lin: `eq_stgips_lin!` below); declared eqdeclr.mod (R,ALLYEAR,ALLYEAR,P,IPS),
# =E=.
#
#   EQ_STGIPS(RTP_VINTYR(R,V,T,P),IPS)$(((MIYR_1(V)*MIYR_1(T)+LIM(IPS))*SUM(PRC_STGIPS(R,P,C),1))$PRC_MAP(R,'STK',P))..
#     VAR_ACT(R,V,T,P,'ANNUAL')$LIM(IPS) +
#     SUM((IO(IPS),MODLYEAR,MIYR_1(LL))$RTP_VINTYR(R,MODLYEAR,T,P), VAR_ACT(R,MODLYEAR,LL-LEAD(LL),P,'ANNUAL'))
#     =E=
#     ((SUM(TT(T-1), (VAR_ACT(R,V,TT,P,'ANNUAL')$RTP_VINTYR(R,V,TT,P))$PRC_VINT(R,P) +
#                    (VAR_ACT(R,TT,TT,P,'ANNUAL')$RTP_VINTYR(R,TT,TT,P))$(NOT PRC_VINT(R,P))) +
#       SUM(MIYR_1(LL), VAR_ACT(R,V,LL-LEAD(LL),P,'ANNUAL'))$MIYR_1(T)) * POWER(1-STG_LOSS(R,V,P,'ANNUAL'),D(T)) +
#      SUM(TOP(PRC_STGIPS(R,P,C),IO),
#        (VAR_SIN(R,V,T,P,C,'ANNUAL')$IPS(IO) - VAR_SOUT(R,V,T,P,C,'ANNUAL')$(NOT IPS(IO))) *
#        SUM(PERIODYR(T,Y_EOH), ((1-STG_LOSS(R,V,P,'ANNUAL'))**(E(T)-YEARVAL(Y_EOH)+0.5))) / PRC_ACTFLO(R,V,P,C))
#     )$LIM(IPS) +
#     SUM((IO(IPS),MIYR_1(LL)), STG_CHRG(R,LL-LEAD(LL),P,'ANNUAL'));
#
# IPS is {IN, N} (setglobs.gms L154) and LIM is {LO, FX, UP, N} (initsys.mod
# L70), so the equation has two kinds of row:
# - IPS = N (in LIM, not in IO): every RTP_VINTYR tuple; the balance above,
#   with neither the IO(IPS) sum on the left nor STG_CHRG on the right.
# - IPS = IN (in IO, not in LIM): only V = T = the first milestone; the sum
#   over the vintages alive at T of VAR_ACT at LL-LEAD(LL) = STG_CHRG there.
# `SUM(IO(IPS), x)` with IPS controlled is x when IPS is in IO, else 0 (G14).
# Inside the flow term `IPS(IO)` tests whether the summed IO is in IPS: IN
# charges (VAR_SIN), OUT discharges (VAR_SOUT). Y_EOH is a set of its own
# (setglobs.gms L146-147, the years to the end of the horizon), so the loss
# sum skips the years PERIODYR gives the last period beyond it. `LL-LEAD(LL)`
# lags the first milestone by LEAD(LL) positions in ALLYEAR (ppmain.mod L162: LEAD of the
# first period is M-B+1 of it); a lag before the first ALLYEAR element gives
# no term. `TT(T-1)` is the previous milestone (none for the first). POWER
# needs an integer D(T) and `**` a positive base (gpower, gpow: G13, G16).
#
# Not translated yet (refused): the stochastic %SOW%/%SWS% indexes (STAGES,
# refused for the whole model).

"""
    eq_stgips!(tm::TimesModel) -> Int

Generate every EQ_STGIPS row (eqmain.mod L169) from `tm.data`. Returns the
number of rows generated.

GAMS: eqstgips.mod L13-44, v4.9.7.
"""
function eq_stgips!(tm::TimesModel)
    x = stg_context(tm)
    stk = Set((r, p) for (r, m, p) in x.prc_map if m == "STK")
    rps = [(r, p) for (r, p) in stk if !isempty(get(x.stgips_of_rp, (r, p), NTuple{3,String}[]))]
    isempty(rps) && return 0
    uppercase(gswitch(tm, "OBJ", "")) == "LIN" && return eq_stgips_lin!(tm, x, rps)   # eqmain.mod L169: eqstgips.%OBJ%
    one, half = GNum(1.0), GNum(0.5)
    pD, pE, yearval, lead = gparam(tm, "D"), gparam(tm, "E"), gparam(tm, "YEARVAL"), gparam(tm, "LEAD")
    prc_vint, rtp_vintyr = gset(tm, "PRC_VINT"), gset(tm, "RTP_VINTYR")
    periodyr_of_t = indexby(gset(tm, "PERIODYR"), (1,))                  # t -> PERIODYR(t,y)
    # Y_EOH is a set of its own (setglobs.gms L146-147, as in eqobj.jl): PERIODYR of
    # the last period runs on past the horizon, the sum stops at its end.
    y_eoh = gset(tm, "Y_EOH")
    t_list = [k[1] for k in gset(tm, "MILESTONYR").keys]                 # T in order
    t_prev = Dict(t_list[i] => t_list[i-1] for i in 2:length(t_list))   # TT(T-1)
    miyr1 = Set(k[1] for k in gset(tm, "MIYR_1").keys)
    allyear = [k[1] for k in gset(tm, "ALLYEAR").keys]
    ord = Dict(y => i for (i, y) in enumerate(allyear))
    # LL-LEAD(LL) for the first milestone LL (MIYR_1 has one element, ppmain.mod L149)
    function before_first(ll)
        lag = gv(lead, (ll,)).v
        isinteger(lag) || throw(ArgumentError("LEAD($ll) = $lag is not an integer: the lag LL-LEAD(LL) needs one"))
        i = ord[ll] - Int(lag)
        return 1 <= i <= length(allyear) ? allyear[i] : nothing
    end
    vint_of_rtp = indexby(rtp_vintyr, (1, 3, 4))                          # (r,t,p) -> RTP_VINTYR(r,v,t,p)
    rps_set = Set(rps)
    vx, tx = gset(tm, "MODLYEAR"), eq_periods(tm)                 # %R_V_T%: V, and SUBT in a stepped run (maindrv.mod L38-40)
    n = 0
    for (r, v, t, p) in rtp_vintyr
        ((v,) in vx && (t,) in tx) || continue
        (r, p) in rps_set || continue
        first_vt = v in miyr1 && t in miyr1
        for ips in ("IN", "N")                                          # IPS / IN, N / (setglobs.gms L154)
            lim = ips == "N"                                            # LIM(IPS)
            (first_vt || lim) || continue
            lhs = JuMP.AffExpr(0.0)
            rhs = JuMP.AffExpr(0.0)
            if lim
                addterm!(lhs, one, tm, "VAR_ACT", r, v, t, p, "ANNUAL")                       # L15
                # Level at the end of T-1, or the charge before the first period (L21-27).
                keep = gpower(one - gv(x.stg_loss, (r, v, p, "ANNUAL")), gv(pD, (t,)))     # L30
                tt = get(t_prev, t, nothing)
                if tt !== nothing
                    if (r, p) in prc_vint
                        (r, v, tt, p) in rtp_vintyr && addterm!(rhs, keep, tm, "VAR_ACT", r, v, tt, p, "ANNUAL")
                    else
                        (r, tt, tt, p) in rtp_vintyr && addterm!(rhs, keep, tm, "VAR_ACT", r, tt, tt, p, "ANNUAL")
                    end
                end
                if t in miyr1
                    for ll in miyr1
                        y0 = before_first(ll)
                        y0 === nothing || addterm!(rhs, keep, tm, "VAR_ACT", r, v, y0, p, "ANNUAL")
                    end
                end
                # Charging and discharging over the period (L34-39).
                base = one - gv(x.stg_loss, (r, v, p, "ANNUAL"))
                w = GZERO
                for (_, y) in get(periodyr_of_t, (t,), NTuple{2,String}[])
                    (y,) in y_eoh || continue                                  # PERIODYR(T,Y_EOH)
                    w = w + gpow(base, gv(pE, (t,)) - gv(yearval, (y,)) + half)
                end
                for (_, _, c) in x.stgips_of_rp[(r, p)], io in ("IN", "OUT")
                    (r, p, c, io) in x.top || continue
                    k = w / gv(x.prc_actflo, (r, v, p, c))
                    io == "IN" ? addterm!(rhs, k, tm, "VAR_SIN", r, v, t, p, c, "ANNUAL") :
                                 addterm!(rhs, -k, tm, "VAR_SOUT", r, v, t, p, c, "ANNUAL")
                end
            else
                # IPS = IN is in IO: the level before the first period = STG_CHRG (L16-17, L43).
                for ll in miyr1
                    y0 = before_first(ll)
                    y0 === nothing && continue
                    for (_, m, _, _) in get(vint_of_rtp, (r, t, p), NTuple{4,String}[])
                        addterm!(lhs, one, tm, "VAR_ACT", r, m, y0, p, "ANNUAL")
                    end
                    addconst!(rhs, gv(x.stg_chrg, (r, y0, p, "ANNUAL")))
                end
            end
            gconstraint!(tm, "EQ_STGIPS", (r, v, t, p, ips), "E", lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end

# EQ_STGIPS under OBJ LIN (M1.3 change 49): the storage level is measured at
# the milestone year M(T), not at the end of the period, and the flows of
# each year are weighted by TPULSE over PERDINV (coef_alt.lin), as the
# activity is. The rows are indexed by RTP_EQSTK(R,V,T,P,ITEM) (L12-18):
#
#   RTP_EQSTK(R,MIYR_1(T),T,P,'IN')$(RTP(R,T,P)$PRC_MAP(R,'STK',P)) = YES;
#   RTP_EQSTK(RTP_VINTYR(R,V,T,P),'N')$PRC_MAP(R,'STK',P) = YES;
#   RTP_EQSTK(RTP_VINTYR(R,V,T,P),'1')$((E(T) GT M(T))$PRC_MAP(R,'STK',P)) = YES;
#
#   EQ_STGIPS(RTP_EQSTK(R,V,T,P,ITEM))$(SUM(PRC_STGIPS(R,P,C),1)$PRC_MAP(R,'STK',P))..
#     VAR_ACT(R,V,T,P,'ANNUAL')$LIM(ITEM) +
#     SUM((IO(ITEM),MODLYEAR,MIYR_1(LL))$RTP_VINTYR(R,MODLYEAR,T,P), VAR_ACT(R,MODLYEAR,LL-LEAD(LL),P,'ANNUAL'))
#     =E=
#     SUM(TOP(PRC_STGIPS(R,P,C),IO),
#       SUM(TT(T-1),
#         (VAR_ACT(R,V,TT,P,'ANNUAL')*POWER(1-STG_LOSS(R,V,P,'ANNUAL'),LEAD(T))$IPS(IO) +
#          SUM(PERDINV(T,Y_EOH),TPULSE(TT,Y_EOH)*((1-STG_LOSS(R,V,P,'ANNUAL'))**(M(T)-YEARVAL(Y_EOH)+0.5)))/PRC_ACTFLO(R,V,P,C) *
#          (VAR_SIN(R,V,TT,P,C,'ANNUAL')$IPS(IO) - VAR_SOUT(R,V,TT,P,C,'ANNUAL')$(NOT IPS(IO))))$(RTP_VINTYR(R,V,TT,P)$PRC_VINT(R,P)) +
#         (the same with V = TT and PRC_ACTFLO(R,TT,P,C))$(RTP_VINTYR(R,TT,TT,P)$(NOT PRC_VINT(R,P)))) +
#       SUM(PERDINV(T,Y_EOH),TPULSE(T,Y_EOH)*((1-STG_LOSS(R,V,P,'ANNUAL'))**(M(T)-YEARVAL(Y_EOH)+0.5)))$RTP_VINTYR(R,V,T,P) *
#       (VAR_SIN(R,V,T,P,C,'ANNUAL')$IPS(IO) - VAR_SOUT(R,V,T,P,C,'ANNUAL')$(NOT IPS(IO))) / PRC_ACTFLO(R,V,P,C)
#     )$LIM(ITEM) +
#     SUM(VNT(T,MIYR_1(LL)), VAR_ACT(R,V,LL-LEAD(LL),P,'ANNUAL') * POWER(1-STG_LOSS(R,V,P,'ANNUAL'),LEAD(T)))$LIM(ITEM) +
#     SUM((IO(ITEM),MIYR_1(LL)), STG_CHRG(R,LL-LEAD(LL),P,'ANNUAL')) +
#     (VAR_ACT(R,V,T,P,'ANNUAL') * POWER(1-STG_LOSS(R,V,P,'ANNUAL'),E(T)-M(T)) -
#      SUM((MIYR_1(LL),Y_EOH(LL+(E(T)-YEARVAL(LL)))), VAR_ACT(R,V,Y_EOH,P,'ANNUAL')) +
#      SUM(TOP(PRC_STGIPS(R,P,C),IO),
#        SUM(PERIODYR(T,Y_EOH)$(YEARVAL(Y_EOH) GT M(T)), ((1-STG_LOSS(R,V,P,'ANNUAL'))**(E(T)-YEARVAL(Y_EOH)+0.5))) *
#        (1+((LAGT(T)-1)/2/(E(T)-M(T))-1)$(E(T) < MIYR_VL)) / PRC_ACTFLO(R,V,P,C) *
#        (VAR_SIN(R,V,T,P,C,'ANNUAL')$IPS(IO) - VAR_SOUT(R,V,T,P,C,'ANNUAL')$(NOT IPS(IO)))))$J(ITEM);
#
# ITEM 'N' is in LIM, 'IN' in IO and '1' in J, so the three kinds of row are:
# - 'N': the level at M(T) is the level at M(T-1) after LEAD(T) years of
#   losses, plus the flows of the years of T-1 and of T weighted by their
#   TPULSE, each discounted from the middle of its year to M(T); in the
#   first period the level before it (VAR_ACT at LL-LEAD(LL)) instead.
#   Inside SUM(TOP(...)) the level of T-1 is counted once per stored
#   commodity charged (IO = IN), as the GAMS sum is written.
# - 'IN': the level before the first period is the charge STG_CHRG, as in
#   eqstgips.mod.
# - '1', for the periods whose end year is past their milestone: 0 = the
#   level at M(T) after the losses to E(T), less VAR_ACT(R,V,E(T),P,'ANNUAL')
#   (a column of its own, so >= 0: the level at the end of the period is not
#   negative), plus the flows of the years after M(T); before the last
#   period the factor is (LAGT(T)-1)/2/(E(T)-M(T)) instead of 1.
# `$` binds before `-`, so `(x-1)$c` is x-1 when c holds and 0 otherwise
# (G13). `LL+(E(T)-YEARVAL(LL))` leads the first milestone along ALLYEAR to
# the year E(T). POWER takes an integer exponent (gpower), `**` a positive
# base (gpow: G13, G16).
#
# GAMS: eqstgips.lin L12-66, v4.9.7, included from eqmain.mod L169 under OBJ LIN.

"""
    eq_stgips_lin!(tm, x, rps) -> Int

Generate every EQ_STGIPS row under OBJ LIN (eqstgips.lin L12-66) for the STK
processes `rps` that have PRC_STGIPS commodities. Returns the number of rows.

GAMS: eqstgips.lin L12-66, v4.9.7.
"""
function eq_stgips_lin!(tm::TimesModel, x, rps)
    one, half, two = GNum(1.0), GNum(0.5), GNum(2.0)
    pM, pE, yearval, lead, lagt = (gparam(tm, n) for n in ("M", "E", "YEARVAL", "LEAD", "LAGT"))
    tpulse = gparam(tm, "TPULSE")
    miyr_vl = gscalar(tm, "MIYR_VL")
    prc_vint, rtp_vintyr, vnt = gset(tm, "PRC_VINT"), gset(tm, "RTP_VINTYR"), gset(tm, "VNT")
    perdinv_of_t = indexby(gset(tm, "PERDINV"), (1,))                    # t -> PERDINV(t,y)
    periodyr_of_t = indexby(gset(tm, "PERIODYR"), (1,))                  # t -> PERIODYR(t,y)
    y_eoh = gset(tm, "Y_EOH")
    t_list = [k[1] for k in gset(tm, "MILESTONYR").keys]
    t_prev = Dict(t_list[i] => t_list[i-1] for i in 2:length(t_list))   # TT(T-1)
    miyr1 = [k[1] for k in gset(tm, "MIYR_1").keys]
    allyear = [k[1] for k in gset(tm, "ALLYEAR").keys]
    ord = Dict(y => i for (i, y) in enumerate(allyear))
    shift(y, k) = (i = ord[y] + k; 1 <= i <= length(allyear) ? allyear[i] : nothing)
    function before_first(ll)                                           # LL-LEAD(LL)
        lag = gv(lead, (ll,)).v
        isinteger(lag) || throw(ArgumentError("LEAD($ll) = $lag is not an integer: the lag LL-LEAD(LL) needs one"))
        return shift(ll, -Int(lag))
    end
    vint_of_rtp = indexby(rtp_vintyr, (1, 3, 4))                        # (r,t,p) -> RTP_VINTYR(r,v,t,p)
    rps_set = Set(rps)
    vx, tx = gset(tm, "MODLYEAR"), eq_periods(tm)                       # %R_V_T% (maindrv.mod L38-40)
    # SUM(PERDINV(T,Y_EOH), TPULSE(TT,Y_EOH)*base**(M(T)-YEARVAL(Y_EOH)+0.5))
    function pulse_weight(t, tt, base)
        w = GZERO
        for (_, y) in get(perdinv_of_t, (t,), NTuple{2,String}[])
            (y,) in y_eoh || continue
            w = w + gv(tpulse, (tt, y)) * gpow(base, gv(pM, (t,)) - gv(yearval, (y,)) + half)
        end
        return w
    end
    # (VAR_SIN$IPS(IO) - VAR_SOUT$(NOT IPS(IO))) * k
    flows!(e, k, sin, r, v, t, p, c) = sin ? addterm!(e, k, tm, "VAR_SIN", r, v, t, p, c, "ANNUAL") :
                                             addterm!(e, -k, tm, "VAR_SOUT", r, v, t, p, c, "ANNUAL")
    tops(r, p) = [(c, io) for (_, _, c) in x.stgips_of_rp[(r, p)] for io in ("IN", "OUT") if (r, p, c, io) in x.top]
    n = 0

    # 'IN' rows: RTP_EQSTK(R,MIYR_1(T),T,P,'IN')$RTP(R,T,P) (L14)
    for (r, t, p) in gset(tm, "RTP")
        ((r, p) in rps_set && t in miyr1 && (t,) in vx && (t,) in tx) || continue
        lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
        for ll in miyr1
            y0 = before_first(ll)
            y0 === nothing && continue
            for (_, m, _, _) in get(vint_of_rtp, (r, t, p), NTuple{4,String}[])
                addterm!(lhs, one, tm, "VAR_ACT", r, m, y0, p, "ANNUAL")                 # L25-26
            end
            addconst!(rhs, gv(x.stg_chrg, (r, y0, p, "ANNUAL")))                         # L56
        end
        gconstraint!(tm, "EQ_STGIPS", (r, t, t, p, "IN"), "E", lhs, rhs) === nothing || (n += 1)
    end

    # 'N' and '1' rows over RTP_VINTYR (L16, L18)
    for (r, v, t, p) in rtp_vintyr
        ((v,) in vx && (t,) in tx && (r, p) in rps_set) || continue
        base = one - gv(x.stg_loss, (r, v, p, "ANNUAL"))
        lt = gv(lead, (t,))
        # 'N' (L24, L30-54)
        lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
        addterm!(lhs, one, tm, "VAR_ACT", r, v, t, p, "ANNUAL")
        tt = get(t_prev, t, nothing)
        wt = pulse_weight(t, t, base)
        for (c, io) in tops(r, p)
            sin = io == "IN"                                            # IPS(IO)
            if tt !== nothing
                vv = (r, p) in prc_vint ? ((r, v, tt, p) in rtp_vintyr ? v : nothing) :
                                          ((r, tt, tt, p) in rtp_vintyr ? tt : nothing)
                if vv !== nothing
                    sin && addterm!(rhs, gpower(base, lt), tm, "VAR_ACT", r, vv, tt, p, "ANNUAL")
                    flows!(rhs, pulse_weight(t, tt, base) / gv(x.prc_actflo, (r, vv, p, c)), sin, r, vv, tt, p, c)
                end
            end
            flows!(rhs, wt / gv(x.prc_actflo, (r, v, p, c)), sin, r, v, t, p, c)
        end
        for ll in miyr1                                                 # L51-52: VNT(T,MIYR_1(LL))
            (t, ll) in vnt || continue
            y0 = before_first(ll)
            y0 === nothing || addterm!(rhs, gpower(base, lt), tm, "VAR_ACT", r, v, y0, p, "ANNUAL")
        end
        gconstraint!(tm, "EQ_STGIPS", (r, v, t, p, "N"), "E", lhs, rhs) === nothing || (n += 1)
        # '1' (L18, L57-65)
        e, m = gv(pE, (t,)), gv(pM, (t,))
        e.v > m.v || continue
        lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
        addterm!(rhs, gpower(base, e - m), tm, "VAR_ACT", r, v, t, p, "ANNUAL")
        for ll in miyr1
            d = (e - gv(yearval, (ll,))).v
            isinteger(d) || throw(ArgumentError("E($t)-YEARVAL($ll) = $d is not an integer: the lead needs one"))
            ye = shift(ll, Int(d))
            (ye !== nothing && (ye,) in y_eoh) && addterm!(rhs, -one, tm, "VAR_ACT", r, v, ye, p, "ANNUAL")
        end
        w1 = GZERO
        for (_, y) in get(periodyr_of_t, (t,), NTuple{2,String}[])
            ((y,) in y_eoh && gv(yearval, (y,)).v > m.v) || continue
            w1 = w1 + gpow(base, e - gv(yearval, (y,)) + half)
        end
        fac = one + gif((gv(lagt, (t,)) - one) / two / (e - m) - one, e.v < miyr_vl)
        for (c, io) in tops(r, p)
            flows!(rhs, w1 * fac / gv(x.prc_actflo, (r, v, p, c)), io == "IN", r, v, t, p, c)
        end
        gconstraint!(tm, "EQ_STGIPS", (r, v, t, p, "1"), "E", lhs, rhs) === nothing || (n += 1)
    end
    return n
end
