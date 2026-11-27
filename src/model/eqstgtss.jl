# EQ_STGTSS / EQ_STSBAL: timeslice storage (TSS, PRC_MAP 'STG' and 'NST')
# and general timeslice storage (STS). EQ_STGTSS carries the storage level
# (VAR_ACT) from the previous timeslice of the same cycle; EQ_STSBAL
# balances the STS levels of the higher timeslice levels.
#
# GAMS: eqstgtss.mod L13-83, v4.9.7, included from eqmain.mod L175 as
# `$BATINCLUDE eqstgtss.mod mod`; declared eqdeclr.mod L122-123
# (R,ALLYEAR,ALLYEAR,P,S) and (R,ALLYEAR,ALLYEAR,P,TSL,S,L), both =E=.
#
#   EQ_STGTSS(RTP_VINTYR(R,V,T,P),RTS(S))$(RPS_STG(R,P,S)$RP_STG(R,P))..
#     VAR_ACT(R,V,T,P,S)
#     =E=
#     SUM(RPS_STG(R,P,ALL_TS(S--RS_STG(R,S))),
#         VAR_ACT(R,V,T,P,ALL_TS)
#       + (SUM((RPCS_VAR(RPC_STG(R,P,C),TS),TS_MAP(R,TS,ALL_TS)),
#             (VAR_SIN(R,V,T,P,C,TS)$(TOP(R,P,C,'IN')$PRC_NSTTS(R,P,TS)) -
#              VAR_SOUT(R,V,T,P,C,TS)$(TOP(R,P,C,'OUT')$(PRC_NSTTS(R,P,TS) EQV RPC_STGN(R,P,C,'OUT')))) *
#             RS_FR(R,ALL_TS,TS)*(1+RTCS_FR(R,T,C,ALL_TS,TS))/PRC_ACTFLO(R,V,P,C)))$PRC_MAP(R,'NST',P)
#       + SUM(TOP(PRC_STGTSS(R,P,C),'IN'),  VAR_SIN(R,V,T,P,C,ALL_TS)/PRC_ACTFLO(R,V,P,C))
#       - SUM(TOP(PRC_STGTSS(R,P,C),'OUT'), VAR_SOUT(R,V,T,P,C,ALL_TS)/PRC_ACTFLO(R,V,P,C))
#       - SUM(PRC_TS(R,P,TS)$RS_BELOW1(R,TS,S), VAR_SOUT(R,V,T,P,'ACT',TS)*RS_FR(R,ALL_TS,TS))$RP_STS(R,P)
#       - VAR_ACT(R,V,T,P,ALL_TS) * MAX(STG_LOSS/2, 1+STG_LOSS/(1/EXP(STG_LOSS)-1))$STG_LOSS
#       - VAR_ACT(R,V,T,P,S)      * MAX(STG_LOSS/2, STG_LOSS/(EXP(STG_LOSS)-1)-1)$STG_LOSS)
#     + STG_CHRG(R,T,P,S--RS_STG(R,S));
#
# with STG_LOSS = STG_LOSS(R,V,P,ALL_TS) (the previous timeslice's). EQ_STSBAL,
# L53-83, is written out at `eq_stsbal!`.
#
# Macro expansions: %EQ% -> EQ, %VAR% -> VAR, %SOW%/%SWT% -> '' (setglobs.gms
# L348); %R_V_T% -> 'R,V,T' (maindrv.mod L39); %PGPRIM% -> 'ACT' (initmty.mod
# L138); RTS(S) -> S, or S+NORTS(R,T,S) with dynamic timeslices (timslice.mod
# L31-39; M1.3 change 67: the rows at timeslices turned off are skipped).
#
# The previous timeslice of the cycle, S--RS_STG(R,S) (a circular lag on
# ALL_TS by the lead RS_STG, timslice.mod L93-95), is read from RS_PREV
# (ppmain.mod L1178: RS_PREV(R,S,S--RS_STG(R,S)) for every S with a
# timeslice level), which applies the same lag to the same data. Where
# RS_STG(R,S) is zero (ANNUAL, an only child) the lag is S itself.
#
# GAMS semantics used (docs/discrepancies.md): `$STG_LOSS(...)` and
# `$RS_STG(R,S)` are true for EPS and false when absent (G3); MAX treats EPS
# as 0 (G14); SUM over a set whose index is already controlled, as in
# `SUM(ANNUAL(S),x)` and `SUM(RS_BELOW(R,ANNUAL,S),x)` with S the equation's
# index, is the condition `x$ANNUAL(S)` (G18).
#
# Not translated yet; data that needs them raises UnportedError:
# - storage flexibility, %STSFLX% = YES (coef_ext.vda L32 keeps RP_STL entries
#   other than 'N'): the VAR_UDP/VAR_STS and $RP_STL(R,P,TSL,'UP') terms of
#   EQ_STSBAL (L56, L62-63, L73) and EQ_STSLEV (L88-93);
# (The PRC_STGIPS charging terms of EQ_STSBAL at ANNUAL, L78-81, are
#   translated in M1.3 change 45; no row of v4.9.7 reaches them, see eq_stsbal!.)

"""
    stg_context(tm) -> NamedTuple

The sets, parameters and incidence maps of the storage equations, built once
per model.
"""
function stg_context(tm::TimesModel)
    get!(tm.cache, "stg") do
        rps_stg = gset(tm, "RPS_STG")
        (rp_stg = gset(tm, "RP_STG"),
         rp_sts = gset(tm, "RP_STS"),
         rps_stg = rps_stg,
         stg_of_rp = indexby(rps_stg, (1, 2)),                          # (r,p) -> RPS_STG(r,p,s)
         prev = Dict((r, s) => sl for (r, s, sl) in gset(tm, "RS_PREV")),
         rs_stg = gparam(tm, "RS_STG"),
         prc_ts = gset(tm, "PRC_TS"),
         parents_of = indexby(gset(tm, "RS_BELOW1"), (1, 3)),           # (r,s) -> RS_BELOW1(r,ts,s)
         above_of = indexby(gset(tm, "TS_MAP"), (1, 3)),                # (r,s) -> TS_MAP(r,ts,s)
         rs_below = gset(tm, "RS_BELOW"),
         rpc_stg_set = gset(tm, "RPC_STG"),
         stgc_of_rp = indexby(gset(tm, "RPC_STG"), (1, 2)),             # (r,p) -> RPC_STG(r,p,c)
         stgtss_of_rp = indexby(gset(tm, "PRC_STGTSS"), (1, 2)),        # (r,p) -> PRC_STGTSS(r,p,c)
         stgips_of_rp = indexby(gset(tm, "PRC_STGIPS"), (1, 2)),        # (r,p) -> PRC_STGIPS(r,p,c)
         rpcs_var = gset(tm, "RPCS_VAR"),
         top = gset(tm, "TOP"),
         prc_nstts = gset(tm, "PRC_NSTTS"),
         rpc_stgn = gset(tm, "RPC_STGN"),
         prc_map = gset(tm, "PRC_MAP"),
         prc_actflo = gparam(tm, "PRC_ACTFLO"),
         rs_fr = gparam(tm, "RS_FR"),
         rtcs_fr = gparam(tm, "RTCS_FR"),
         stg_loss = gparam(tm, "STG_LOSS"),
         stg_chrg = gparam(tm, "STG_CHRG"))
    end
end

"""
    stg_prev(x, r, s) -> String

`S--RS_STG(R,S)`: the previous timeslice of `s` in its storage cycle, from
RS_PREV (ppmain.mod L1178); `s` itself where RS_STG(R,S) is zero.

GAMS: timslice.mod L93-95, ppmain.mod L1178, v4.9.7.
"""
function stg_prev(x, r::String, s::String)
    sl = get(x.prev, (r, s), nothing)
    sl === nothing || return sl
    haskey(x.rs_stg, (r, s)) &&
        throw(ArgumentError("RS_STG$((r, s)) is set but RS_PREV has no entry for ($r, $s)"))
    return s
end

"`MAX(L/2, 1+L/(1/EXP(L)-1))`: the loss factor on the previous level (eqstgtss.mod L40-42, L70-72)."
stg_loss_prev(l::GNum) = gmax(l / GNum(2.0), GNum(1.0) + l / (GNum(1.0) / gexp(l) - GNum(1.0)))

"`MAX(L/2, L/(EXP(L)-1)-1)`: the loss factor on the current level (eqstgtss.mod L43-45, L73-75)."
stg_loss_cur(l::GNum) = gmax(l / GNum(2.0), l / (gexp(l) - GNum(1.0)) - GNum(1.0))

"""
    var_sts!(expr, coef, tm, r, v, t, p, ts, bd) -> expr

`coef * VAR_STS(R,V,T,P,TS,BD)`, the VDA macro of coef_ext.vda L31:

    \$ macro var_sts(r,v,t,p,ts,bd) sum(rp_stl(r,p,tsl,bd)\$ts_group(r,tsl,ts),%var%_udp(r,v,t,p,ts,bd%sow%))

VAR_UDP at TS for each RP_STL entry of type BD whose level holds TS (a timeslice is in one level
only, so one term at most). GAMS counts the macro as DEFINED, so mod_vars.mod L96's empty parameter
is never declared (G2). RP_STL has entries other than 'N' only under %STSFLX% (coef_ext.vda L32).

The SOW tags (sow_tags.jl): the macro reads `%var%_udp(... %sow%)`, the row's
own SOW (`addterm!`).

GAMS: coef_ext.vda L31, v4.9.7.
"""
function var_sts!(expr::JuMP.AffExpr, coef::GNum, tm, r, v, t, p, ts, bd)
    stl = get!(() -> indexby(gset(tm, "RP_STL"), (1, 2)), tm.cache, "RP_STL_OF_RP")::Dict
    tsg = gset(tm, "TS_GROUP")
    for (_, _, tsl, b) in get(stl, (r, p), NTuple{4,String}[])
        (b == bd && (r, tsl, ts) in tsg) && addterm!(expr, coef, tm, "VAR_UDP", r, v, t, p, ts, bd)
    end
    return expr
end

function stgtss_unported(tm::TimesModel)
    return nothing                       # dynamic timeslices: RTS(S) rows translated (M1.3 change 67)
end

"""
    eq_stgtss!(tm::TimesModel) -> Int

Generate every EQ_STGTSS and EQ_STSBAL row (eqmain.mod L175) from `tm.data`.
Returns the number of rows generated.

GAMS: eqstgtss.mod L13-83, v4.9.7.
"""
function eq_stgtss!(tm::TimesModel)
    gset(tm, "RP_STG") |> isempty && return 0
    stgtss_unported(tm)
    return eq_stgtss_rows!(tm) + eq_stsbal!(tm) + eq_stslev!(tm)   # L13-48, L53-83, L86-93
end

"""
    eq_stgtss_rows!(tm) -> Int

The EQ_STGTSS rows (formula in the file header).

The SOW tags (sow_tags.jl): the row is `%EQ%_STGTSS(... %SWT%)` (L13); every
term is `%VAR%_X(... %SOW%)` (L16-43).

GAMS: eqstgtss.mod L13-48, v4.9.7.
"""
function eq_stgtss_rows!(tm::TimesModel)
    x = stg_context(tm)
    off = rts_off(tm)
    one = GNum(1.0)
    vx, tx = gset(tm, "MODLYEAR"), eq_periods(tm)                 # %R_V_T%: V, and SUBT in a stepped run (maindrv.mod L38-40)
    n = 0
    for (r, v, t, p) in gset(tm, "RTP_VINTYR")
        ((v,) in vx && (t,) in tx) || continue
        (r, p) in x.rp_stg || continue
        nst = (r, "NST", p) in x.prc_map
        sts = (r, p) in x.rp_sts
        for (_, _, s) in get(x.stg_of_rp, (r, p), NTuple{3,String}[])
            off(r, t, s) && continue     # RTS(S): S+NORTS(R,T,S) with dynamic timeslices (M1.3 change 67)
            for sow in sw_rows(tm, t)   # %SWT% (L13)
                set_sow!(tm, sow)
                lhs = JuMP.AffExpr(0.0)
                addterm!(lhs, one, tm, "VAR_ACT", r, v, t, p, s)                                 # L16
                rhs = JuMP.AffExpr(0.0)
                sl = stg_prev(x, r, s)                                                           # ALL_TS(S--RS_STG(R,S))
                if (r, p, sl) in x.rps_stg                                                       # L20
                    addterm!(rhs, one, tm, "VAR_ACT", r, v, t, p, sl)                            # L22
                    if nst                                                                       # L25-30
                        for (_, _, c) in get(x.stgc_of_rp, (r, p), NTuple{3,String}[])
                            tin, tout = (r, p, c, "IN") in x.top, (r, p, c, "OUT") in x.top
                            stgn_out = (r, p, c, "OUT") in x.rpc_stgn
                            for (_, ts, _) in get(x.above_of, (r, sl), NTuple{3,String}[])      # TS_MAP(R,TS,ALL_TS)
                                (r, p, c, ts) in x.rpcs_var || continue
                                nstts = (r, p, ts) in x.prc_nstts
                                sin, sout = tin && nstts, tout && (nstts == stgn_out)          # L27-28 (EQV)
                                (sin || sout) || continue
                                w = gv(x.rs_fr, (r, sl, ts)) * (one + gv(x.rtcs_fr, (r, t, c, sl, ts))) /
                                    gv(x.prc_actflo, (r, v, p, c))                                # L29
                                sin && addterm!(rhs, w, tm, "VAR_SIN", r, v, t, p, c, ts)
                                sout && addterm!(rhs, -w, tm, "VAR_SOUT", r, v, t, p, c, ts)
                            end
                        end
                    end
                    stgtss = get(x.stgtss_of_rp, (r, p), NTuple{3,String}[])
                    for (_, _, c) in stgtss                                                      # L33
                        (r, p, c, "IN") in x.top &&
                            addterm!(rhs, one / gv(x.prc_actflo, (r, v, p, c)), tm, "VAR_SIN", r, v, t, p, c, sl)
                    end
                    for (_, _, c) in stgtss                                                      # L34
                        (r, p, c, "OUT") in x.top &&
                            addterm!(rhs, -(one / gv(x.prc_actflo, (r, v, p, c))), tm, "VAR_SOUT", r, v, t, p, c, sl)
                    end
                    if sts                                                                       # L37
                        for (_, ts, _) in get(x.parents_of, (r, s), NTuple{3,String}[])
                            (r, p, ts) in x.prc_ts || continue
                            addterm!(rhs, -gv(x.rs_fr, (r, sl, ts)), tm, "VAR_SOUT", r, v, t, p, "ACT", ts)
                        end
                    end
                    if haskey(x.stg_loss, (r, v, p, sl))                                         # L40-45
                        l = gv(x.stg_loss, (r, v, p, sl))
                        addterm!(rhs, -stg_loss_prev(l), tm, "VAR_ACT", r, v, t, p, sl)
                        addterm!(rhs, -stg_loss_cur(l), tm, "VAR_ACT", r, v, t, p, s)
                    end
                end
                addconst!(rhs, gv(x.stg_chrg, (r, t, p, sl)))                                    # L48
                gconstraint!(tm, eqtag(tm, "EQ_STGTSS"), swt(tm, (r, v, t, p, s), t), "E", lhs, rhs) === nothing || (n += 1)
            end
        end
    end
    return n
end

"""
    eq_stsbal!(tm) -> Int

The EQ_STSBAL rows: for each STS level TSL of RP_STL(R,P,TSL,L) and each S of
that level in PRC_TS,

    EQ_STSBAL(RTP_VINTYR(R,V,T,P),TSL,RTS(S),L)\$(TS_GROUP(R,TSL,S)\$PRC_TS(R,P,S)\$RP_STL(R,P,TSL,L))..
      SUM(RS_BELOW(R,ANNUAL,S), VAR_ACT(R,V,T,P,S) + (VAR_SIN(R,V,T,P,'ACT',S)+VAR_STS(R,V,T,P,S,'N'))\$RP_STL(R,P,TSL,'UP'))
      =E=
      SUM(RS_BELOW(R,ANNUAL,SL(S--RS_STG(R,S))),
          VAR_ACT(R,V,T,P,SL)\$IPS(L) + VAR_UDP(R,V,T,P,SL,'LO')\$BD(L) +
          (VAR_SIN(R,V,T,P,'ACT',SL)+VAR_STS(R,V,T,P,SL,L))\$RP_STL(R,P,TSL,'UP') +
          (VAR_SOUT(R,V,T,P,'ACT',SL)
           - SUM(PRC_TS(R,P,TS)\$RS_BELOW1(R,TS,S), VAR_SOUT(R,V,T,P,'ACT',TS)*RS_FR(R,SL,TS))
           - (VAR_ACT(R,V,T,P,SL)\$RS_STG(R,S)) * MAX(STG_LOSS/2, 1+STG_LOSS/(1/EXP(STG_LOSS)-1))\$STG_LOSS
           - (VAR_ACT(R,V,T,P,S)\$RS_STG(R,S) + (VAR_SIN(R,V,T,P,'ACT',S)-VAR_SIN(R,V,T,P,'ACT',SL))\$RP_STL(R,P,TSL,'UP')) *
               MAX(STG_LOSS/2, STG_LOSS/(EXP(STG_LOSS)-1)-1)\$STG_LOSS
          )\$IPS(L))
      + SUM(ANNUAL(S), [PRC_STGIPS charging] - VAR_SOUT(R,V,T,P,'ACT',S));

with STG_LOSS = STG_LOSS(R,V,P,SL). Storage flexibility (%STSFLX% YES, M1.3
change 52): coef_ext.vda L32 then keeps the RP_STL entries of the bound types,
and ppm_ext.vda L141 gives a storage with capacity the type 'UP' at its 'N'
levels. A row with L in BD has the VAR_UDP term and none of the IPS(L)
terms; the 'UP' entry of its level adds the charging VAR_SIN at S and SL
(and to the losses) and VAR_STS at S ('N') and at SL (L), the VAR_UDP of
coef_ext.vda L31's macro (`var_sts!`). Without
%STSFLX%, RP_STL only has L = 'N' (ppmain.mod L1089), so IPS(L) holds and
BD(L) does not; the S = ANNUAL term (L78-83) is reached by no such row: RP_STL's levels
are TSL+1 (ppmain.mod L1089, SEASON and below; ppm_ext.vda L141 adds 'UP'
at the same levels) and RP_STL is declared after the DD files are read
(ppmain.mod L23), so no data can give it ANNUAL. The term, with the
PRC_STGIPS charging of L80-81 (M1.3 change 45), is written as GAMS has it
and checked on a constructed state only (test_eqstgtss_ips.jl), with no
GAMS reference: GAMS cannot reach it either.

    SUM(ANNUAL(S), SUM(TOP(PRC_STGIPS(R,P,C),IO), 1/PRC_ACTFLO(R,V,P,C) *
        VAR_SIN(R,V,T,P,C,S)\$IPS(IO) - VAR_SOUT(R,V,T,P,C,S)\$(NOT IPS(IO))) -
        VAR_SOUT(R,V,T,P,%PGPRIM%,S))

The 1/PRC_ACTFLO factor binds to the VAR_SIN term only (GAMS precedence).

The SOW tags (sow_tags.jl): the row is `%EQ%_STSBAL(... %SWT%)` (L53); every
term is `%VAR%_X(... %SOW%)` (L56-83), VAR_STS being the macro `%var%_udp(...
%sow%)` (coef_ext.vda L31).

GAMS: eqstgtss.mod L53-83, v4.9.7.
"""
function eq_stsbal!(tm::TimesModel)
    x = stg_context(tm)
    off = rts_off(tm)
    one = GNum(1.0)
    rp_stl = gset(tm, "RP_STL")
    stl_of_rp = indexby(rp_stl, (1, 2))                     # (r,p) -> RP_STL(r,p,tsl,l)
    group_of = indexby(gset(tm, "TS_GROUP"), (1, 2))        # (r,tsl) -> TS_GROUP(r,tsl,s)
    ips, bd = gset(tm, "IPS"), gset(tm, "BD")
    top, actflo = gset(tm, "TOP"), gparam_opt(tm.data, "PRC_ACTFLO", 4)
    vx, tx = gset(tm, "MODLYEAR"), eq_periods(tm)                 # %R_V_T%: V, and SUBT in a stepped run (maindrv.mod L38-40)
    n = 0
    for (r, v, t, p) in gset(tm, "RTP_VINTYR")
        ((v,) in vx && (t,) in tx) || continue
        stls = get(stl_of_rp, (r, p), NTuple{4,String}[])
        isempty(stls) && continue
        for (_, _, tsl, l) in stls, (_, _, s) in get(group_of, (r, tsl), NTuple{3,String}[])
            (r, p, s) in x.prc_ts || continue
            off(r, t, s) && continue     # RTS(S) (M1.3 change 67)
            up = (r, p, tsl, "UP") in rp_stl                                                 # $RP_STL(R,P,TSL,'UP')
            for sow in sw_rows(tm, t)   # %SWT% (L53)
                set_sow!(tm, sow)
                lhs = JuMP.AffExpr(0.0)
                if (r, "ANNUAL", s) in x.rs_below                                                # L56
                    addterm!(lhs, one, tm, "VAR_ACT", r, v, t, p, s)
                    if up
                        addterm!(lhs, one, tm, "VAR_SIN", r, v, t, p, "ACT", s)
                        var_sts!(lhs, one, tm, r, v, t, p, s, "N")
                    end
                end
                rhs = JuMP.AffExpr(0.0)
                sl = stg_prev(x, r, s)
                if (r, "ANNUAL", sl) in x.rs_below                                               # L60-76
                    (l,) in ips && addterm!(rhs, one, tm, "VAR_ACT", r, v, t, p, sl)            # L62
                    (l,) in bd && addterm!(rhs, one, tm, "VAR_UDP", r, v, t, p, sl, "LO")       # L62
                    if up                                                                        # L63
                        addterm!(rhs, one, tm, "VAR_SIN", r, v, t, p, "ACT", sl)
                        var_sts!(rhs, one, tm, r, v, t, p, sl, l)
                    end
                    if (l,) in ips
                        addterm!(rhs, one, tm, "VAR_SOUT", r, v, t, p, "ACT", sl)                # L66
                        for (_, ts, _) in get(x.parents_of, (r, s), NTuple{3,String}[])          # L67
                            (r, p, ts) in x.prc_ts || continue
                            addterm!(rhs, -gv(x.rs_fr, (r, sl, ts)), tm, "VAR_SOUT", r, v, t, p, "ACT", ts)
                        end
                        if haskey(x.stg_loss, (r, v, p, sl))                                     # L70-75
                            lv = gv(x.stg_loss, (r, v, p, sl))
                            if haskey(x.rs_stg, (r, s))
                                addterm!(rhs, -stg_loss_prev(lv), tm, "VAR_ACT", r, v, t, p, sl)
                                addterm!(rhs, -stg_loss_cur(lv), tm, "VAR_ACT", r, v, t, p, s)
                            end
                            if up && sl != s                                                     # (SIN(S)-SIN(SL))$RP_STL(..,'UP')
                                addterm!(rhs, -stg_loss_cur(lv), tm, "VAR_SIN", r, v, t, p, "ACT", s)
                                addterm!(rhs, stg_loss_cur(lv), tm, "VAR_SIN", r, v, t, p, "ACT", sl)
                            end
                        end
                    end
                end
                if s == "ANNUAL"                                                                 # L78-83
                    for (_, _, c) in get(x.stgips_of_rp, (r, p), NTuple{3,String}[])            # L80-81
                        for io in ("IN", "OUT")
                            (r, p, c, io) in top || continue
                            if (io,) in ips
                                addterm!(rhs, one / gv(actflo, (r, v, p, c)), tm, "VAR_SIN", r, v, t, p, c, s)
                            else
                                addterm!(rhs, -one, tm, "VAR_SOUT", r, v, t, p, c, s)
                            end
                        end
                    end
                    addterm!(rhs, -one, tm, "VAR_SOUT", r, v, t, p, "ACT", s)
                end
                gconstraint!(tm, eqtag(tm, "EQ_STSBAL"), swt(tm, (r, v, t, p, tsl, s, l), t), "E", lhs, rhs) === nothing || (n += 1)
            end
        end
    end
    return n
end

"""
    eq_stslev!(tm) -> Int

EQ_STSLEV, the levelizer of a flexible timeslice storage (%STSFLX% YES, M1.3 change 52), one row for
each vintage, level TSL with an 'UP' entry of RP_STL and timeslice S of that level at the storage's
own level (STOAL(R,S) = PRC_SGL(R,P)); %SWX% is ,'1' and %SWTX% empty outside stochastic runs
(setglobs.gms L363-365):

    EQ_STSLEV(RTP_VINTYR(R,V,T,P),TSL,RTS(S),'1')\$((STOAL(R,S)=PRC_SGL(R,P))\$TS_GROUP(R,TSL,S)\$RP_STL(R,P,TSL,'UP'))..
      SUM(TS_MAP(R,TS,S)\$STOA(TS),(VAR_SIN(R,V,T,P,'ACT',TS)+VAR_UDP(R,V,T,P,TS,'LO')+VAR_STS(R,V,T,P,TS,'N'))/RS_STGPRD(R,TS))
      =L=
      SUM(RS_BELOW1(R,S,TS)\$RS_FR(R,TS,S),VAR_ACT(R,V,T,P,TS)/RS_STGPRD(R,TS)*RS_FR(R,TS,S));

`STOAL(R,S)=PRC_SGL(R,P)` compares numbers, so a missing value is 0 on either side. VAR_STS is the
VAR_UDP of coef_ext.vda L31's macro (`var_sts!`). Returns the number of rows.

The SOW tags (sow_tags.jl): the row is `EQ_STSLEV(... %SWX%)\$(%SWTX% ...)`
(L88), with no %EQ%: the name stays and the last index is `swx`; every term is
`%VAR%_X(... %SOW%)` (L91, L93).

GAMS: eqstgtss.mod L86-93, v4.9.7.
"""
function eq_stslev!(tm::TimesModel)
    rp_stl = gset(tm, "RP_STL")
    any(k -> k[4] == "UP", rp_stl) || return 0
    x = stg_context(tm)
    off = rts_off(tm)
    one = GNum(1.0)
    stoal, prc_sgl, stoa = gparam(tm, "STOAL"), gparam(tm, "PRC_SGL"), gparam(tm, "STOA")
    rs_stgprd = gparam(tm, "RS_STGPRD")
    group_of = indexby(gset(tm, "TS_GROUP"), (1, 2))        # (r,tsl) -> TS_GROUP(r,tsl,s)
    up_of_rp = Dict{NTuple{2,String},Vector{String}}()      # (r,p) -> TSL with RP_STL(r,p,tsl,'UP')
    foreach(k -> k[4] == "UP" && push!(get!(up_of_rp, (k[1], k[2]), String[]), k[3]), rp_stl.keys)
    tsmap_to = indexby(gset(tm, "TS_MAP"), (1, 3))          # (r,s) -> TS_MAP(r,ts,s)
    below1_of = indexby(gset(tm, "RS_BELOW1"), (1, 2))      # (r,s) -> RS_BELOW1(r,s,ts)
    vx, tx = gset(tm, "MODLYEAR"), eq_periods(tm)           # %R_V_T% (maindrv.mod L38-40)
    n = 0
    for (r, v, t, p) in gset(tm, "RTP_VINTYR")
        ((v,) in vx && (t,) in tx) || continue
        tsls = get(up_of_rp, (r, p), String[])
        isempty(tsls) && continue
        sgl = gv(prc_sgl, (r, p)).v
        for tsl in tsls, (_, _, s) in get(group_of, (r, tsl), NTuple{3,String}[])
            gv(stoal, (r, s)).v == sgl || continue
            off(r, t, s) && continue     # RTS(S) (M1.3 change 67)
            for sow in sw_rows(tm, t)   # %SWTX% (L88): SW_T(T,SOW)
                set_sow!(tm, sow)
                lhs = JuMP.AffExpr(0.0)
                for (_, ts, _) in get(tsmap_to, (r, s), NTuple{3,String}[])
                    haskey(stoa.values, (ts,)) || continue                                   # $STOA(TS)
                    k = one / gv(rs_stgprd, (r, ts))
                    addterm!(lhs, k, tm, "VAR_SIN", r, v, t, p, "ACT", ts)
                    addterm!(lhs, k, tm, "VAR_UDP", r, v, t, p, ts, "LO")
                    var_sts!(lhs, k, tm, r, v, t, p, ts, "N")
                end
                rhs = JuMP.AffExpr(0.0)
                for (_, _, ts) in get(below1_of, (r, s), NTuple{3,String}[])
                    haskey(x.rs_fr, (r, ts, s)) || continue                                  # $RS_FR(R,TS,S)
                    addterm!(rhs, one / gv(rs_stgprd, (r, ts)) * gv(x.rs_fr, (r, ts, s)), tm, "VAR_ACT", r, v, t, p, ts)
                end
                gconstraint!(tm, "EQ_STSLEV", (r, v, t, p, tsl, s, swx(tm)), "L", lhs, rhs) === nothing || (n += 1)
            end
        end
    end
    return n
end
