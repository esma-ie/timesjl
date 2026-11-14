# M1.3 (16): ppmain.mod L1228-1333 (docs/m13-plan.md): the blending block
# (BLE_* control sets, REFUNIT, BL_UNIT, PEAKDA_BL, BLE_BAL, RU_CVT, RU_FEQ),
# translated in full with EQ(l)_BLND (eqblnd.mod, `src/model/eqblnd.jl`).
#
# GAMS: ppmain.mod L1228-1333, v4.9.7.
#
# The user's data (initmty.mod L378-403): the blending products BLE(COM), the
# blending streams OPR(COM), the specifications SPE(*), the unit of the
# refinery streams of a region REFUNIT(R) (1 energy, 2 weight, 3 volume; the
# default 1 is L1251), the stream properties CONVERT(OPR,CVT) with CVT =
# / DENS, WCV, VCV, SLF / (density, energy per weight, energy per volume,
# sulphur), and per region and blend BL_TYPE (the equation type of a
# specification, eqmain.mod L249-252), BL_START (its first year), BL_UNIT
# (the unit the specification is given in: 1 energy, 2 weight, 3 volume; the
# default 1 is L1257), BL_SPEC and BL_COM (the specification of the blend and
# the quality of each stream), BL_INP (other inputs per unit of blend),
# ENV_BL (emissions) and PEAKDA_BL (the peak share of the inputs).
#
# The block:
# - L1246: BLE_SPE(R,COM,SPE), every specification with a BL_TYPE, of any
#   commodity (the later statements control it with BLE).
# - L1254-1256: BLE_TP(R,T,BLE), the periods a blend is under specification:
#   every T at or after the BL_START of one of its specifications (no
#   BL_START counts as 0, so every T).
# - L1264, L1288-1290: BLE_SPEOPR(R,BLE,SPE,OPR), the streams with a BL_COM
#   for a specification, and BLE_OPR(R,BLE,OPR), the streams of a blend.
# - L1273: BLE_SPEINP(R,BLE,SPE,COM) from BLE_INP(R,BLE,COM). TIMES only
#   declares BLE_INP (L1240; the statements that filled it are comments,
#   L1267-1272), so it has the members the model's own data gives it and no
#   others. BLE_SPEINP is used by no equation.
# - L1291-1293: BLE_ENV(R,C,BLE,OPR), the emissions of a stream in a blend:
#   C is in ENV(R,C) (ppmain.mod L946) and ENV_BL summed over T is not zero.
# - L1296: PEAKDA_BL(R,BLE,T) = 1 where not given, for a blend with a BLE_INP
#   input that is a peak commodity (COM_PEAK).
# - L1301-1306: BLE_BAL(R,T,BLE,OPR2) for every BLE_TP and every stream OPR2:
#   1 when the blend is itself a stream (OPR(BLE)), else the factor from the
#   refinery unit of the stream to energy: 1, CONVERT(OPR2,'WCV') or
#   CONVERT(OPR2,'VCV') for REFUNIT 1, 2 or 3.
# - L1310-1332: RU_CVT(R,BLE,SPE,OPR), the factor from the refinery unit to
#   the unit of the specification, and RU_FEQ(R,OPR,T), by REFUNIT:
#
#       REFUNIT   BL_UNIT 3 (volume)   BL_UNIT 2 (weight)   BL_UNIT 1 (energy)   RU_FEQ
#       3         1                    CONVERT(DENS)        CONVERT(VCV)         CONVERT(VCV)
#       2         1/CONVERT(DENS)      1                    CONVERT(WCV)         CONVERT(WCV)
#       1         1/CONVERT(VCV)       1/CONVERT(WCV)       1                    1
#
#   Any other REFUNIT (an EPS one too) assigns nothing; any other BL_UNIT
#   gives 0, so no RU_CVT. `(1/CONVERT)$(...)` is evaluated only where the
#   condition holds (docs/discrepancies.md G14), and a CONVERT of zero or EPS
#   is then a division by zero, an error here as in GAMS.
# - L1333: RU_FEQ = 1 where it is still zero. RU_FEQ is used by no equation.
#
# `NOT x` on a parameter is false for an EPS entry (G25), so the defaults
# (L1251, L1257, L1296, L1333) keep a given EPS; a `$` on a parameter holds
# for an EPS entry.

"""
    ppmain_blend_symbols(tm) -> Vector{String}

The symbols ppmain.mod L1228-1333 settles (nothing later in the prelv ->
ppm segment writes them).
"""
ppmain_blend_symbols(tm) = ["REFUNIT", "BLE_SPE", "BLE_TP", "BLE_SPEOPR", "BLE_OPR", "BLE_INP", "BLE_SPEINP", "BLE_ENV", "BLE_BAL",
                            "BL_UNIT", "PEAKDA_BL", "RU_CVT", "RU_FEQ"]

"""
    ppmain_blend!(tm) -> tm

ppmain.mod L1228-1333 on the state after `ppmain_ucmap!`: the blending
control sets, the defaults of REFUNIT, BL_UNIT and PEAKDA_BL, and the unit
factors BLE_BAL, RU_CVT and RU_FEQ.

GAMS: ppmain.mod L1228-1333, v4.9.7.
"""
function ppmain_blend!(tm)
    d = tm.data
    reg = [k[1] for k in gset(tm, "REG").keys]
    tlist = [k[1] for k in gset(tm, "MILESTONYR").keys]
    tmem = Set(tlist)
    ble = Set(k[1] for k in gset_opt(d, "BLE", 1).keys)
    opr = [k[1] for k in gset_opt(d, "OPR", 1).keys]
    oprmem = Set(opr)
    yearval = gparam(tm, "YEARVAL")
    cvt_of = gparam_opt(d, "CONVERT", 2)
    bl_start, bl_com, env_bl = gparam_opt(d, "BL_START", 3), gparam_opt(d, "BL_COM", 4), gparam_opt(d, "ENV_BL", 5)

    # L1236-1243: SET BLE_SPE(R,COM,SPE), BLE_TP(R,ALLYEAR,*), BLE_SPEOPR(R,COM,SPE,OPR), BLE_OPR(R,COM,COM),
    #   BLE_INP(R,COM,COM), BLE_SPEINP(R,COM,SPE,COM), BLE_ENV(R,COM,COM,OPR) //; PARAMETER BLE_BAL(R,YEAR,C,C) //;
    #   declared empty; each keeps what the model's data gives it (nothing else fills BLE_INP)
    ble_spe, ble_tp, ble_speopr = gmembers(tm, "BLE_SPE", 3), gmembers(tm, "BLE_TP", 3), gmembers(tm, "BLE_SPEOPR", 4)
    ble_opr, ble_inp, ble_speinp = gmembers(tm, "BLE_OPR", 3), gmembers(tm, "BLE_INP", 3), gmembers(tm, "BLE_SPEINP", 4)
    ble_env, ble_bal = gmembers(tm, "BLE_ENV", 4), gvalues(tm, "BLE_BAL", 4)

    # L1246: BLE_SPE(R,COM,SPE)$BL_TYPE(R,COM,SPE) = YES
    union!(ble_spe, keys(gparam_opt(d, "BL_TYPE", 3).values))
    # L1251: REFUNIT(R)$(NOT REFUNIT(R)) = 1  (an EPS REFUNIT is kept, G25)
    refunit = gvalues(tm, "REFUNIT", 1)
    for r in reg
        haskey(refunit, (r,)) || (refunit[(r,)] = 1.0)
    end
    # L1254-1256: LOOP(BLE_SPE(R,BLE,SPE), BLE_TP(R,T,BLE)$(YEARVAL(T) >= BL_START(R,BLE,SPE)) = YES)
    # L1257: BL_UNIT(BLE_SPE(R,BLE,SPE))$(NOT BL_UNIT(R,BLE,SPE)) = 1
    bl_unit = gvalues(tm, "BL_UNIT", 3)
    for (r, b, spe) in ble_spe
        b in ble || continue
        start = gv(bl_start, (r, b, spe)).v
        for t in tlist
            yearval[(t,)] >= start && push!(ble_tp, (r, t, b))
        end
        haskey(bl_unit, (r, b, spe)) || (bl_unit[(r, b, spe)] = 1.0)
    end
    # L1264: BLE_SPEOPR(BLE_SPE(R,BLE,SPE),OPR)$BL_COM(R,BLE,OPR,SPE) = YES
    for (r, b, o, spe) in bl_com.keys
        (b in ble && o in oprmem && (r, b, spe) in ble_spe) && push!(ble_speopr, (r, b, spe, o))
    end
    # L1273: BLE_SPEINP(R,BLE,SPE,COM)$(BLE_SPE(R,BLE,SPE) * BLE_INP(R,BLE,COM)) = YES
    spe_of = Dict{NTuple{2,String},Vector{String}}()                       # (r,ble) -> SPE of BLE_SPE
    for (r, b, spe) in ble_spe
        b in ble && push!(get!(spe_of, (r, b), String[]), spe)
    end
    for (r, b, c) in ble_inp, spe in get(spe_of, (r, b), String[])
        push!(ble_speinp, (r, b, spe, c))
    end
    # L1288-1290: LOOP(BLE_SPEOPR(R,BLE,SPE,OPR), BLE_OPR(R,BLE,OPR) = YES)
    for (r, b, _, o) in ble_speopr
        b in ble && push!(ble_opr, (r, b, o))
    end
    # L1291-1293: LOOP(BLE_OPR(R,BLE,OPR), BLE_ENV(R,C,BLE,OPR)$(ENV(R,C) * SUM(T, ENV_BL(R,C,BLE,OPR,T))) = YES)
    env = gset_opt(d, "ENV", 2).members
    envsum = Dict{NTuple{4,String},GNum}()
    for (r, c, b, o, t) in env_bl.keys
        (t in tmem && (r, c) in env && b in ble && (r, b, o) in ble_opr) || continue
        envsum[(r, c, b, o)] = get(envsum, (r, c, b, o), GZERO) + gv(env_bl, (r, c, b, o, t))
    end
    for (k, x) in envsum
        iszero(x) || push!(ble_env, k)
    end
    # L1296: PEAKDA_BL(R,BLE,T)$((NOT PEAKDA_BL(R,BLE,T))$SUM(COM_PEAK(R,C)$BLE_INP(R,BLE,C),1)) = 1
    peakda_bl = gvalues(tm, "PEAKDA_BL", 3)
    com_peak = gset_opt(d, "COM_PEAK", 2).members
    for (r, b, c) in ble_inp
        (b in ble && (r, c) in com_peak) || continue
        for t in tlist
            haskey(peakda_bl, (r, b, t)) || (peakda_bl[(r, b, t)] = 1.0)
        end
    end
    # L1301: ALIAS(OPR,OPR2)
    # L1303: BLE_BAL(BLE_TP(R,T,BLE),OPR2)$OPR(BLE) = 1
    # L1304-1306: BLE_BAL(BLE_TP(R,T,BLE),OPR2)$(NOT OPR(BLE)) = 1$(REFUNIT(R)=1) +
    #   CONVERT(OPR2,'WCV')$(REFUNIT(R)=2) + CONVERT(OPR2,'VCV')$(REFUNIT(R)=3)
    ru(r) = gv(refunit, (r,)).v
    for (r, t, b) in ble_tp, o2 in opr
        (b in ble && t in tmem) || continue
        x = b in oprmem ? GNum(1.0) :
            gif(1.0, ru(r) == 1) + gif(gv(cvt_of, (o2, "WCV")), ru(r) == 2) + gif(gv(cvt_of, (o2, "VCV")), ru(r) == 3)
        gassign!(ble_bal, (r, t, b, o2), x)
    end
    # L1310-1332: LOOP(R, IF(REFUNIT(R) = 3, ...); IF(REFUNIT(R) = 2, ...); IF(REFUNIT(R) = 1, ...))
    ru_cvt, ru_feq = gvalues(tm, "RU_CVT", 4), gvalues(tm, "RU_FEQ", 3)
    speopr_of = Dict{String,Vector{NTuple{4,String}}}()                    # r -> BLE_SPEOPR(r,ble,spe,opr)
    for k in ble_speopr
        k[2] in ble && push!(get!(speopr_of, k[1], NTuple{4,String}[]), k)
    end
    recip(o, cvt) = GNum(1.0) / gv(cvt_of, (o, cvt))                      # 1/CONVERT(OPR,CVT)
    for r in reg
        u = ru(r)
        (u == 3 || u == 2 || u == 1) || continue
        for k in get(speopr_of, r, NTuple{4,String}[])
            (_, b, spe, o) = k
            bu = gv(bl_unit, (r, b, spe)).v
            x = if u == 3
                # L1312-1314: RU_CVT(BLE_SPEOPR(R,BLE,SPE,OPR)) = 1$(BL_UNIT(R,BLE,SPE) = 3) +
                #   CONVERT(OPR,'DENS')$(BL_UNIT(R,BLE,SPE) = 2) + CONVERT(OPR,'VCV')$(BL_UNIT(R,BLE,SPE) = 1)
                gif(1.0, bu == 3) + gif(gv(cvt_of, (o, "DENS")), bu == 2) + gif(gv(cvt_of, (o, "VCV")), bu == 1)
            elseif u == 2
                # L1319-1321: (1/CONVERT(OPR,'DENS'))$(BL_UNIT = 3) + 1$(BL_UNIT = 2) + CONVERT(OPR,'WCV')$(BL_UNIT = 1)
                (bu == 3 ? recip(o, "DENS") : GZERO) + gif(1.0, bu == 2) + gif(gv(cvt_of, (o, "WCV")), bu == 1)
            else
                # L1326-1328: (1/CONVERT(OPR,'VCV'))$(BL_UNIT = 3) + (1/CONVERT(OPR,'WCV'))$(BL_UNIT = 2) + 1$(BL_UNIT = 1)
                (bu == 3 ? recip(o, "VCV") : GZERO) + (bu == 2 ? recip(o, "WCV") : GZERO) + gif(1.0, bu == 1)
            end
            gassign!(ru_cvt, k, x)
        end
        # L1315, L1322, L1329: RU_FEQ(R,OPR,T) = CONVERT(OPR,'VCV') | CONVERT(OPR,'WCV') | 1
        for o in opr, t in tlist
            gassign!(ru_feq, (r, o, t), u == 3 ? gv(cvt_of, (o, "VCV")) : u == 2 ? gv(cvt_of, (o, "WCV")) : GNum(1.0))
        end
    end
    # L1333: RU_FEQ(R,OPR,T)$(NOT RU_FEQ(R,OPR,T)) = 1
    for r in reg, o in opr, t in tlist
        haskey(ru_feq, (r, o, t)) || (ru_feq[(r, o, t)] = 1.0)
    end

    gput!(tm, "BLE_SPE", ble_spe); gput!(tm, "BLE_TP", ble_tp); gput!(tm, "BLE_SPEOPR", ble_speopr)
    gput!(tm, "BLE_OPR", ble_opr); gput!(tm, "BLE_INP", ble_inp); gput!(tm, "BLE_SPEINP", ble_speinp)
    gput!(tm, "BLE_ENV", ble_env); gput!(tm, "BLE_BAL", ble_bal)
    gput!(tm, "REFUNIT", refunit); gput!(tm, "BL_UNIT", bl_unit); gput!(tm, "PEAKDA_BL", peakda_bl)
    gput!(tm, "RU_CVT", ru_cvt); gput!(tm, "RU_FEQ", ru_feq)
    return tm
end
