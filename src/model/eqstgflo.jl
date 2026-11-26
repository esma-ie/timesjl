# EQG/EQE/EQL_STGIN and EQG/EQE/EQL_STGOUT: bounds on the charging and
# discharging flows of storage processes that cannot be variable bounds, i.e.
# on vintaged processes (summed over vintages) or at a timeslice above the
# flow's own (summed over the timeslices below).
#
# GAMS: eqstgflo.mod L16-30, v4.9.7, included from eqmain.mod L180-185 as
#   $BATINCLUDE eqstgflo.mod IN  G LO 0
#   $BATINCLUDE eqstgflo.mod IN  E FX NA
#   $BATINCLUDE eqstgflo.mod IN  L UP INF
#   $BATINCLUDE eqstgflo.mod OUT G LO 0
#   $BATINCLUDE eqstgflo.mod OUT E FX NA
#   $BATINCLUDE eqstgflo.mod OUT L UP INF
# (%1 = IN/OUT, %2 = equation type, %3 = bound type, %4 = the value for which
# no row is generated); declared eqdeclr.mod L127-132 (R,ALLYEAR,P,C,S).
#
#   EQ%2_STG%1(RTPC(R,T,P,C),S)$((STG%1_BND(R,T,P,C,S,'%3') NE %4)$(PRC_VINT(R,P)+(NOT RPCS_VAR(R,P,C,S)))
#                                 $RPS_PRCTS(R,P,S)$RPC_STG(R,P,C)$STG%1_BND(R,T,P,C,S,'%3')) ..
#     SUM(RPCS_VAR(R,P,C,TS)$(RS_FR(R,S,TS) * (%TMP% PRC_NSTTS(R,P,TS))),
#         SUM(RTP_VINTYR(R,V,T,P), VAR_S%1(R,V,T,P,C,TS)*RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS))))
#     =%2= STG%1_BND(R,T,P,C,S,'%3');
#
# with %TMP% = `(NOT PRC_MAP(R,'NST',P))+` for IN and `NOT` for OUT (L16-17):
# a night-storage device charges only in its PRC_NSTTS slices and
# discharges only outside them. In the %4 conditions EPS compares as 0
# (G12), so an EPS lower bound gives no row; any value but NA differs from
# NA (G20). V in the inner sum is MODLYEAR (setglobs.gms L147; G8). Macro
# expansions as in eqstgtss.jl. The other STGIN_BND and
# STGOUT_BND records are variable bounds (bnd_stg.mod).

"Includes of eqstgflo.mod from eqmain.mod L180-185: (%1, %2, %3)."
const STGFLO_VARIANTS = (("IN", "G", "LO"), ("IN", "E", "FX"), ("IN", "L", "UP"),
                         ("OUT", "G", "LO"), ("OUT", "E", "FX"), ("OUT", "L", "UP"))

"""
    eq_stgflo!(tm::TimesModel) -> Int

Generate every EQ(l)_STGIN and EQ(l)_STGOUT row (eqmain.mod L180-185).
Returns the number of rows.

The SOW tags (sow_tags.jl): the row is `%EQ%%2_STG%1(... %SWT%)` (L20); the
term is `%VAR%_S%1(... %SOW%)` (L25).

GAMS: eqstgflo.mod L16-30, v4.9.7.
"""
function eq_stgflo!(tm::TimesModel)
    n = 0
    for (io, eqtype, bd) in STGFLO_VARIANTS
        n += eq_stgflo!(tm, io, eqtype, bd)
    end
    return n
end

function eq_stgflo!(tm::TimesModel, io::String, eqtype::String, bd::String)
    bnd = gparam(tm, "STG$(io)_BND")
    isempty(bnd) && return 0
    x = stg_context(tm)
    one = GNum(1.0)
    modlyear, rtpc = gset(tm, "MODLYEAR"), gset(tm, "RTPC")
    tx = eq_periods(tm)   # %R_T%, %TX%: SUBT in a stepped run (maindrv.mod L38-40)
    prc_vint, rps_prcts = gset(tm, "PRC_VINT"), gset(tm, "RPS_PRCTS")
    varts_of = indexby(x.rpcs_var, (1, 2, 3))                     # (r,p,c) -> RPCS_VAR(r,p,c,ts)
    v_of_rtp = indexby(gset(tm, "RTP_VINTYR"), (1, 3, 4))         # (r,t,p) -> RTP_VINTYR(r,v,t,p)
    name = "EQ$(eqtype)_STG$(io)"

    rows = NTuple{5,String}[]
    for (r, t, p, c, s, b) in bnd.keys
        b == bd || continue
        ((t,) in tx && (r, t, p, c) in rtpc) || continue
        v = bnd.values[(r, t, p, c, s, b)]
        bd == "LO" && v == 0 && continue                          # NE 0 (EPS is 0, G12)
        bd == "UP" && v == Inf && continue                        # NE INF
        bd == "FX" && isnan(v) && continue                        # NE NA (G20)
        ((r, p) in prc_vint || !((r, p, c, s) in x.rpcs_var)) || continue
        ((r, p, s) in rps_prcts && (r, p, c) in x.rpc_stg_set) || continue
        push!(rows, (r, t, p, c, s))
    end
    gams_sort!(rows, tm.data)
    n = 0
    for (r, t, p, c, s) in rows
        nst = (r, "NST", p) in x.prc_map
        for sow in sw_rows(tm, t)   # %SWT% (L20)
            set_sow!(tm, sow)
            lhs = JuMP.AffExpr(0.0)
            for (_, _, _, ts) in get(varts_of, (r, p, c), NTuple{4,String}[])
                nstts = (r, p, ts) in x.prc_nstts
                (io == "IN" ? (!nst || nstts) : !nstts) || continue                         # %TMP% PRC_NSTTS
                haskey(x.rs_fr, (r, s, ts)) || continue                                     # $RS_FR(R,S,TS)
                w = gv(x.rs_fr, (r, s, ts)) * (one + gv(x.rtcs_fr, (r, t, c, s, ts)))
                for (_, vv, _, _) in get(v_of_rtp, (r, t, p), NTuple{4,String}[])
                    (vv,) in modlyear || continue                                           # V = MODLYEAR (G8)
                    addterm!(lhs, w, tm, "VAR_S$(io)", r, vv, t, p, c, ts)
                end
            end
            rhs = addconst!(JuMP.AffExpr(0.0), gv(bnd, (r, t, p, c, s, bd)))
            gconstraint!(tm, eqtag(tm, name), swt(tm, (r, t, p, c, s), t), eqtype, lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end
