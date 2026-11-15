# EQL_BLND / EQG_BLND / EQE_BLND / EQN_BLND: the blending equation by type
# (refinery blending). A blend BLE is made of blending streams OPR; for each
# specification SPE of the blend (octane, sulphur, ...) the quality of the
# mix, BL_COM of each stream, is held against the blend's specification
# BL_SPEC: at most (type 1), at least (2), equal (3), or not at all (4).
#
# GAMS: eqblnd.mod L67-71, v4.9.7, included from eqmain.mod L249-252 as
#   $BATINCLUDE eqblnd.mod L 1
#   $BATINCLUDE eqblnd.mod G 2
#   $BATINCLUDE eqblnd.mod E 3
#   $BATINCLUDE eqblnd.mod N 4
# (%1 = equation type, %2 = the value of BL_TYPE); declared eqdeclr.mod
# L182-185 as EQ?_BLND(R,YEAR,BLE,SPE,ALLSOW); in the model, mod_equa.mod
# L201-204. L1-63 of eqblnd.mod are comments (the MARKAL terms the blending
# variable has in the other equations: these are eqobjvar.mod L105-107,
# eqcombal.mod L30-35 and L75-80, eqpeak.mod L78).
#
# Macro expansions: %VAR% -> VAR, %SOW% -> '' (setglobs.gms L348); %R_T% ->
# 'R,T' (maindrv.mod L39); %SWTX% -> '' and %SWX% -> ",'1'" (setglobs.gms
# L363-365, not a stochastic run): the equation has the index ALLSOW, which
# is the label 1, so a row is EQL_BLND(REG1,2010,TRAGSL,SUL,1). T = MILESTONYR;
# R is an alias of REG (initsys.mod L88). BLE and OPR are subsets of COM, SPE
# is a set of its own (initmty.mod L378-380).
#
# The sets and parameters read are those of ppmain.mod L1228-1333
# (ppmain_blend.jl): BLE_TP (the blend in the periods from BL_START on),
# BLE_OPR (the streams of a blend, from BL_COM) and RU_CVT (the conversion of
# the stream's unit to the unit of the specification, by REFUNIT and BL_UNIT).
#
# =N= (type 4) is GAMS's "no relationship": the row is in the matrix as a
# free row (bounds -INF, +INF), `gconstraint!` with "N".

"Includes of eqblnd.mod from eqmain.mod L249-252: (%1, %2)."
const BLND_VARIANTS = (("L", 1), ("G", 2), ("E", 3), ("N", 4))

"""
    eq_blnd!(tm::TimesModel) -> Int

Generate every EQ(l)_BLND row, in the order of eqmain.mod L249-252 (L with
BL_TYPE 1, G with 2, E with 3, N with 4). Returns the number of rows.

    EQ%1_BLND(BLE_TP(R,T,BLE),SPE,'1')\$(BL_TYPE(R,BLE,SPE)=%2) ..
      SUM(OPR\$BLE_OPR(R,BLE,OPR), (BL_COM(R,BLE,OPR,SPE) - BL_SPEC(R,BLE,SPE)) *
                                  RU_CVT(R,BLE,SPE,OPR) * VAR_BLND(R,T,BLE,OPR))
      =%1=
      0;

A stream whose BL_COM equals BL_SPEC, or with RU_CVT 0, has no term (G5);
a row left without a variable is not generated (G22). A BL_TYPE other than
1 to 4 gives no row.

GAMS: eqblnd.mod L67-71 with eqmain.mod L249-252, v4.9.7.
"""
function eq_blnd!(tm::TimesModel)
    d = tm.data
    ble_tp = gset_opt(d, "BLE_TP", 3)
    isempty(ble_tp) && return 0
    tx = eq_periods(tm)   # %R_T%, %TX%: SUBT in a stepped run (maindrv.mod L38-40)
    ble, opr, spe = gset_opt(d, "BLE", 1), gset_opt(d, "OPR", 1), gset_opt(d, "SPE", 1)
    bl_type, bl_com, bl_spec = gparam_opt(d, "BL_TYPE", 3), gparam_opt(d, "BL_COM", 4), gparam_opt(d, "BL_SPEC", 3)
    ru_cvt = gparam_opt(d, "RU_CVT", 4)
    type_of_rb = indexby(bl_type, (1, 2))                              # (r,ble) -> BL_TYPE(r,ble,spe)
    opr_of_rb = indexby(gset_opt(d, "BLE_OPR", 3), (1, 2))             # (r,ble) -> BLE_OPR(r,ble,opr)
    no3 = NTuple{3,String}[]

    n = 0
    for (eqtype, code) in BLND_VARIANTS
        name = "EQ$(eqtype)_BLND"
        rows = NTuple{4,String}[]
        for (r, t, b) in ble_tp                                        # L67
            ((t,) in tx && (b,) in ble) || continue
            for k in get(type_of_rb, (r, b), no3)
                ((k[3],) in spe && bl_type.values[k] == code) || continue
                push!(rows, (r, t, b, k[3]))
            end
        end
        gams_sort!(rows, d)
        for (r, t, b, s) in rows
            lhs = JuMP.AffExpr(0.0)
            spec = gv(bl_spec, (r, b, s))
            for (_, _, o) in get(opr_of_rb, (r, b), no3)               # L68-69
                (o,) in opr || continue
                addterm!(lhs, (gv(bl_com, (r, b, o, s)) - spec) * gv(ru_cvt, (r, b, s, o)), tm, "VAR_BLND", r, t, b, o)
            end
            gconstraint!(tm, name, (r, t, b, s, "1"), eqtype, lhs, JuMP.AffExpr(0.0)) === nothing || (n += 1)
        end
    end
    return n
end
