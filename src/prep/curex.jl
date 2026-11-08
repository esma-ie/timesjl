# M1.3 (26): curex.gms, the currency conversions, included at preppm.mod
# L27-28 before any interpolation.
#
# GAMS: preppm.mod L27-28 and curex.gms L1-84, v4.9.7.
#
# preppm.mod L27 (`$IF DEFINED G_CUREX`) fills R_CUREX from G_CUREX where the
# region has no rate of its own, and its `R_CUREX(R,CURR,CUR)$NO=0` makes
# R_CUREX defined, so L28 includes curex.gms whenever G_CUREX or R_CUREX has
# DD data (`$IF DEFINED`, G35). curex.gms then:
#
# - L18-26: maps each currency CURR of a region to the one currency CUR of
#   RDCUR (the currencies with a discount rate, ppmain.mod L38) it has a rate
#   to (CURMAP(R,CUR,CURR)), or to itself when it is in RDCUR and has no such
#   single target; a currency with a target leaves RDCUR, and every currency
#   left in RDCUR gets the rate 1 to itself.
# - L29-32: a two-step chain CRU -> CURR -> CUR (CURR no longer in RDCUR)
#   without a direct rate gets the product of the two rates, and CRU is mapped
#   to CUR instead of CURR (RXX keeps the chains; the loops run in GAMS order).
# - L35-69: converts each cost attribute through its SUBR call (L75-82):
#   first every time series whose option record ('0') is below -12 is removed
#   (L77), then each record in a source currency is multiplied by the rate to
#   its target, the rate raised to `1$YEARVAL(LL)` so that the option records
#   ('0', YEARVAL 0) are carried over unchanged (L78, L81), and the records of
#   one target are summed. With a temporary attribute (RYPM, RYPCSM, RYPCSRXM,
#   RYCSM; L80) the attribute is cleared first, so records in a currency
#   without a target are dropped; without one (%1 = %2) the converted records
#   are assigned where the sum is not zero (`$=`) and then every record outside
#   RDCUR is removed (L82).
#
# A self-referencing assignment reads the values from before the statement
# (L77, L81 without a temporary attribute, L31-32 within one loop pass), and
# EPS counts as data in `$` and `$=` (docs/discrepancies.md G51).
#
# Refused (`curex_unported`): blending costs BL_VAROMC and BL_DELIVC (L59-60,
# called without a year index, so `%MX%` is the empty global of setglobs.gms
# L356 and L374 and the full rate applies; blending is refused anyway) and the
# ETL and stochastic attributes TL_CT_COST, S_DAM_COST and S_COM_TAX (L66,
# L68-69) when they have data.

"Whether preppm.mod L28 includes curex.gms: G_CUREX or R_CUREX has data (`\$IF DEFINED`, G35)."
curex_runs(tm) = hasdata(tm, "G_CUREX", 2) || hasdata(tm, "R_CUREX", 3)

"""
The cost attributes curex.gms L35-67 converts: name, dimension, position of
CUR, and whether the call uses a temporary attribute (%2 not %1). Every call
has the year index at position 2 (%4 LL). DAM_COST only with data (L67).
"""
const CUREX_ATTRS = [
    ("NCAP_COST", 4, 4, true), ("NCAP_ITAX", 4, 4, true), ("NCAP_ISUB", 4, 4, true), ("NCAP_DCOST", 4, 4, true),
    ("NCAP_DLAGC", 4, 4, true), ("NCAP_FOM", 4, 4, true), ("NCAP_FSUB", 4, 4, true), ("NCAP_FTAX", 4, 4, true),
    ("ACT_COST", 4, 4, true), ("FLO_COST", 6, 6, true), ("FLO_DELIV", 6, 6, true), ("FLO_TAX", 6, 6, true),
    ("FLO_SUB", 6, 6, true), ("NCAP_VALU", 5, 5, true), ("IRE_PRICE", 8, 8, true), ("COM_BPRICE", 5, 5, true),
    ("COM_CSTNET", 5, 5, true), ("COM_TAXNET", 5, 5, true), ("COM_SUBNET", 5, 5, true), ("COM_CSTPRD", 5, 5, true),
    ("COM_TAXPRD", 5, 5, true), ("COM_SUBPRD", 5, 5, true), ("REG_BNDCST", 5, 4, false), ("REG_CUMCST", 6, 5, false),
    ("ACT_CSTUP", 5, 5, false), ("ACT_CSTSD", 6, 6, false), ("ACT_CSTRMP", 5, 5, false), ("ACT_CSTPL", 4, 4, true),
    ("DAM_COST", 4, 4, true)]

"The curex.gms paths this model would take that are not translated."
function curex_unported(tm)
    out = String[]
    curex_runs(tm) || return out
    (hasdata(tm, "BL_VAROMC", 3) || hasdata(tm, "BL_DELIVC", 4)) &&
        push!(out, "curex.gms L59-60 (blending costs BL_VAROMC/BL_DELIVC)")
    for (n, N, l) in (("TL_CT_COST", 4, "L66"), ("S_DAM_COST", 6, "L68"), ("S_COM_TAX", 8, "L69"))
        hasdata(tm, n, N) && push!(out, "curex.gms $l ($n: ETL or stochastic costs)")
    end
    return out
end

"""
    curex_symbols(tm) -> Vector{String}

What preppm.mod L27-28 settles when curex.gms runs, beyond the interpolated
attributes `preppm_symbols` already lists: R_CUREX, RDCUR, CURMAP, RXX (next
cleared by preshape.gms, after the prep checkpoint) and the converted
attributes nothing later in the segment changes.
"""
curex_symbols(tm) = curex_runs(tm) ?
    ["R_CUREX", "RDCUR", "CURMAP", "RXX", "COM_BPRICE", "COM_CSTNET", "COM_TAXNET", "COM_SUBNET", "COM_CSTPRD", "COM_TAXPRD",
     "COM_SUBPRD", "REG_CUMCST", "ACT_CSTPL"] : String[]

"""
    curex!(tm) -> tm

preppm.mod L27-28 with curex.gms on the state after `ppmain_rtp!`: R_CUREX
from G_CUREX, the currency map and RDCUR, the chained rates, and every cost
attribute converted into the currencies of RDCUR. Does nothing when neither
G_CUREX nor R_CUREX has data.

GAMS: preppm.mod L27-28, curex.gms L1-84, v4.9.7.
"""
function curex!(tm)
    curex_runs(tm) || return tm
    u = curex_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    reg = [k[1] for k in gset(tm, "REG").keys]
    cur = [k[1] for k in gset(tm, "CUR").keys]
    rcx = gvalues(tm, "R_CUREX", 3)
    # preppm.mod L27: R_CUREX(R,CURR,CUR)$(NOT R_CUREX(R,CURR,CUR))$=G_CUREX(CURR,CUR); an EPS rate counts (G51)
    for ((a, b), x) in gparam_opt(tm.data, "G_CUREX", 2).values, r in reg
        haskey(rcx, (r, a, b)) || (rcx[(r, a, b)] = x)
    end
    # L18: R_CUREX(R,CUR,CUR) = 0
    for r in reg, c in cur
        delete!(rcx, (r, c, c))
    end
    rate(r, a, b) = haskey(rcx, (r, a, b))
    rdcur0 = gset(tm, "RDCUR").members
    # L21-24: LOOP((R,CURR), IF(SUM(RDCUR(R,CUR)$R_CUREX(R,CURR,CUR),1) EQ 1,
    #   CURMAP(RDCUR(R,CUR),CURR)$R_CUREX(R,CURR,CUR) = YES; ELSE CURMAP(RDCUR(R,CURR),CURR) = YES))
    curmap = Set{NTuple{3,String}}()
    for r in reg, cc in cur
        tg = [c for c in cur if (r, c) in rdcur0 && rate(r, cc, c)]
        if length(tg) == 1
            push!(curmap, (r, tg[1], cc))
        elseif (r, cc) in rdcur0
            push!(curmap, (r, cc, cc))
        end
    end
    # L25: LOOP(CURMAP(R,CUR,CURR)$(NOT SAMEAS(CUR,CURR)), RDCUR(R,CURR) = NO)
    rdcur = copy(rdcur0)
    foreach(((r, c, cc),) -> c != cc && delete!(rdcur, (r, cc)), curmap)
    # L26: R_CUREX(RDCUR(R,CUR),CUR) = 1
    foreach(((r, c),) -> (rcx[(r, c, c)] = 1.0), rdcur)
    # L29-30: OPTION CLEAR=RXX; LOOP((CURMAP(RDCUR(R,CUR),CURR),CRU)$((NOT RDCUR(R,CURR))$CURMAP(R,CURR,CRU)),
    #   RXX(R,CURR,CRU)$(NOT R_CUREX(R,CRU,CUR)) = YES)
    rxx = Set{NTuple{3,String}}()
    for (r, c, cr) in curmap
        ((r, c) in rdcur && !((r, cr) in rdcur)) || continue
        for cru in cur
            (r, cr, cru) in curmap && !rate(r, cru, c) && push!(rxx, (r, cr, cru))
        end
    end
    rxx_sorted = gams_sort!(collect(rxx), tm.data)
    # L31: LOOP(RXX(R,CURR,CRU), R_CUREX(R,CRU,CUR)$CURMAP(R,CUR,CURR) = R_CUREX(R,CRU,CURR)*R_CUREX(R,CURR,CUR))
    for (r, cr, cru) in rxx_sorted
        new = [(c, gv(rcx, (r, cru, cr)) * gv(rcx, (r, cr, c))) for c in cur if (r, c, cr) in curmap]
        foreach(((c, x),) -> gassign!(rcx, (r, cru, c), x), new)
    end
    # L32: LOOP(RXX(R,CURR,CRU), CURMAP(R,CURR,CRU)=NO; CURMAP(R,CUR,CRU)$CURMAP(R,CUR,CURR)=YES)
    for (r, cr, cru) in rxx_sorted
        delete!(curmap, (r, cr, cru))
        foreach(c -> push!(curmap, (r, c, cru)), [c for c in cur if (r, c, cr) in curmap])
    end
    gput!(tm, "R_CUREX", rcx)
    gput!(tm, "RDCUR", rdcur)
    gput!(tm, "CURMAP", curmap)
    gput!(tm, "RXX", rxx)

    # L35-67: the cost attributes, each through SUBR (L75-82)
    targets = Dict{NTuple{2,String},Vector{String}}()           # (R,CURR) => every CUR with CURMAP(R,CUR,CURR)
    for (r, c, cc) in gams_sort!(collect(curmap), tm.data)
        push!(get!(targets, (r, cc), String[]), c)
    end
    yearval = YearAxis(tm).yearval
    regs = Set(reg)
    for (name, N, ci, temp) in CUREX_ATTRS
        name == "DAM_COST" && !hasdata(tm, name, N) && continue     # L67: $IF DEFINED DAM_COST
        Reference.has_symbol(tm.data.dump, name) || continue
        vals = gvalues(tm, name, N)
        isempty(vals) && continue
        curex_subr!(vals, Val(N), ci, temp, regs, targets, rcx, rdcur, yearval)
        gput!(tm, name, vals)
    end
    return tm
end

"""
    curex_subr!(vals, Val(N), ci, temp, regs, targets, rcx, rdcur, yearval) -> vals

curex.gms L75-82 on one attribute's records `vals` (EPS as 0.0), CUR at
position `ci`, the year at position 2: the L77 filter, then the conversion
of L80-81 with a temporary attribute (`temp`) or L81-82 without.
"""
function curex_subr!(vals::Dict{NTuple{N,String},Float64}, ::Val{N}, ci, temp, regs, targets, rcx, rdcur, yearval) where {N}
    # L77: %1(R,LL%5,CUR%7)$((%1(R,'0'%5,CUR%7)<-12)$%1(R,'0'%5,CUR%7)) = 0, from the values before it (G51)
    gone = Set(Base.setindex(k, "0", 2) for (k, x) in vals if k[2] == "0" && k[1] in regs && x < -12)
    isempty(gone) || filter!(((k, _),) -> !(k[1] in regs && Base.setindex(k, "0", 2) in gone), vals)
    # L81: SUM(CURMAP(R,CUR,CURR)$%2(R,LL%5%6,CURR%7), %2(R,LL%5%6,CURR%7)*POWER(R_CUREX(R,CURR,CUR),1$YEARVAL(LL)))
    sums = Dict{NTuple{N,String},GNum}()
    order = sort!(collect(keys(vals)); by=k -> k[ci])             # the sum over CURR, in any order (1e-9)
    for k in order
        k[1] in regs || continue
        x = vals[k] == 0 ? GEPS : GNum(vals[k])
        for c in get(targets, (k[1], k[ci]), String[])
            f = yearval[k[2]] != 0 ? gpower(gv(rcx, (k[1], k[ci], c)), 1) : GNum(1.0)
            nk = Base.setindex(k, c, ci)
            sums[nk] = get(sums, nk, GZERO) + x * f
        end
    end
    # L80: with a temporary attribute, %1 is cleared before L81
    temp && empty!(vals)
    # L81: %1(R,LL%5,CUR%7) $= SUM(...)
    for (k, s) in sums
        iszero(s) || gassign!(vals, k, s)
    end
    # L82: without one, %1(R,LL%5,CUR%7)$(NOT RDCUR(R,CUR)) = 0
    temp || filter!(((k, _),) -> !(k[1] in regs) || (k[1], k[ci]) in rdcur, vals)
    return vals
end
