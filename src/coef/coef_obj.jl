# M1.2 (4): the objective-function coefficients.
#
# GAMS (v4.9.7): coef_obj.mod L1-205, with filparam.gms (L41: G_DRATE) and
# fillcost.gms (L120-151: the cost parameters, interpolated over the years).
#
# With GAMS 23 or later `%OBMAC%` is YES (initmty.mod L21), so fillcost.gms
# writes the investment, fixed, variable and flow costs into its caches
# OB_ICOST, OB_ISUB, OB_ITAX, OB_FOM, OB_FSB, OB_FTX, OB_DCC, OB_DLC, OB_ACT,
# OB_FCOS, OB_FDEL and OB_FTAX (the OBJ_ICOST, ... names are macros over
# them, L156-168), while OBJ_COMNT, OBJ_COMPD and OBJ_IPRIC get their
# interpolated years written back (fillcost.gms L41).
#
# `%ANNCOST%` LEV (L31-32; M1.3 change 29): ACL takes MINYR, MINYR becomes
# MIYR_V1 and RPT_OPT('OBJ','2') is set to 1; L32 restores MINYR when `%CTST%`
# is empty (`$IFI '%ANNCOST%%CTST%'==LEV`). With OBJ MOD, ALT or LIN or with
# OBLONG, MINYR therefore stays MIYR_V1 for Y_EOH (L33) and for everything
# that reads it later (eqobjinv.mod L86). ACL and RPT_OPT are read by the
# reports only (cost_ann.rpt L16, L26, L90; rpt_obj.rpt L127).
#
# Not translated (UnportedError): VALIDATE (L114,
# L137, L191-201), elastic demand shapes under TIMESED/MICRO (L184-189) and
# blending (L93-94, BLE_OPR) - no reference run has any of them. `$IF
# DEFINED R_CUREX` (L99) holds exactly when R_CUREX has data at this stage:
# curex.gms runs whenever R_CUREX is defined (preppm.mod L27-28) and sets
# R_CUREX(RDCUR(R,CUR),CUR) = 1 (curex.gms L26), and nothing else assigns it.
# The investment, fixed and decommissioning costs are then taken in every
# currency (%TAKE% 1), not only RDCUR (M1.3 change 26).
#
# GAMS semantics this relies on (docs/discrepancies.md): a lead by a
# non-integer is rounded to the nearest integer (G29); a LOOP's $-condition
# is evaluated again before each iteration (G30); `OPTION p < q` with p and
# q parameters counts q's records (G31); SMIN/SMAX over nothing are +INF/-INF
# (G31); circular `LL--ORD(LL)` is the last ALLYEAR element, '0' (G31).

"The coef_obj.mod paths this model would take that are not translated; empty when coef_obj! can run."
function coef_obj_unported(tm)
    out = String[]
    sw(n) = uppercase(gswitch(tm, n, ""))
    sw("VALIDATE") == "YES" && push!(out, "coef_obj.mod L114, L137, L191-201 (VALIDATE YES)")
    (sw("TIMESED") == "YES" || sw("MICRO") == "YES") &&
        push!(out, "coef_obj.mod L184-189 (elastic demand shapes, TIMESED/MICRO)")
    isempty(gset_opt(tm.data, "BLE_OPR", 3)) || push!(out, "coef_obj.mod L93-94 (blending: BLE_OPR has data)")
    return out
end

"""
    varcost(tm) -> String

`%VARCOST%`: the run's value, or LIN when `%OBLONG%%OBJ%` is YESALT
(initmty.mod L431; OBJ MOD sets OBLONG, L427). Compared case-insensitively.
"""
function varcost(tm)
    obj = uppercase(gswitch(tm, "OBJ", ""))
    oblong = uppercase(gswitch(tm, "OBLONG", "")) == "YES" || obj == "MOD"
    (oblong && obj == "ALT") && return "LIN"
    return uppercase(gswitch(tm, "VARCOST", ""))
end

"GAMS rounds a non-integer lead or lag to the nearest integer, halves away from zero (G29)."
glead(x::Real) = Int(round(x, RoundNearestTiesAway))

"""
    YearAxis

ALLYEAR in GAMS order (`'0'` last, initmty.mod L369) with each label's
position, for leads and lags, and YEARVAL.
"""
struct YearAxis
    years::Vector{String}
    pos::Dict{String,Int}
    yearval::Dict{String,Float64}
end
function YearAxis(tm)
    ys = [k[1] for k in gset(tm, "ALLYEAR").keys]
    yv = gparam(tm, "YEARVAL")
    return YearAxis(ys, Dict(y => i for (i, y) in enumerate(ys)), Dict(y => yv[(y,)] for y in ys))
end
"The element `n` positions after `y` (before, for n < 0), or nothing past either end."
function lead(ax::YearAxis, y::String, n::Integer)
    i = ax.pos[y] + n
    return 1 <= i <= length(ax.years) ? ax.years[i] : nothing
end

gscalar(tm, name) = Float64(gv(gparam_opt(tm.data, name, 0), ()))
gput_scalar!(tm, name, x::Real) = gput!(tm, name, iszero(x) ? Dict{Tuple{},Float64}() : Dict{Tuple{},Float64}(() => Float64(x)))
"A scalar assignment of a GNum: EPS is kept as an EPS record (0.0), an exact zero removes it."
gput_scalar!(tm, name, x::GNum) = gput!(tm, name, x.eps ? Dict{Tuple{},Float64}(() => 0.0) : iszero(x.v) ? Dict{Tuple{},Float64}() :
                                                      Dict{Tuple{},Float64}(() => x.v))

"The scratch scalars filparam.gms and fillcost.gms write."
const FIL_SCRATCH = ("F", "Z", "MY_F", "DFUNC", "LAST_VAL", "FIRST_VAL", "MY_FYEAR")

"""
    FilScratch(tm)

The scratch scalars of filparam.gms (L23-40) and fillcost.gms (L27-35),
carried from tuple to tuple and from call to call as GAMS does: each call
resets only some of them per tuple (filparam F, Z, MY_FYEAR; fillcost F,
LAST_VAL), so what the last call leaves depends on the earlier tuples and
calls too. Read from `tm` at the start of coef_obj.mod and written back by
`put_fil_scratch!` after its last fillcost call (L151). fillcost.gms also
leaves the arrays MY_ARRAY (L29: the tuple's values at DM_YEAR, over what
coef_obj.mod L113 cleared) and MY_FIL2 (cleared per tuple at L28, then the
tuple's interpolated years). CNT is not kept:
fillcost.gms L33's `FOR(CNT=MY_FYEAR-Z+1 TO -1, ...)` starts at 0 or below
for data years at least one apart, so it always leaves CNT at 0, which
coef_nio.mod L59 has already cleared.
"""
mutable struct FilScratch
    F::GNum
    Z::GNum
    MY_F::GNum
    DFUNC::GNum
    LAST_VAL::GNum
    FIRST_VAL::GNum
    MY_FYEAR::GNum
    MY_ARRAY::Dict{Tuple{String},Float64}
    MY_FIL2::Dict{Tuple{String},Float64}
end
FilScratch(tm) = FilScratch((gv(gparam_opt(tm.data, n, 0), ()) for n in FIL_SCRATCH)..., gvalues(tm, "MY_ARRAY", 1),
                            gvalues(tm, "MY_FIL2", 1))
FilScratch() = FilScratch(GZERO, GZERO, GZERO, GZERO, GZERO, GZERO, GZERO, Dict{Tuple{String},Float64}(), Dict{Tuple{String},Float64}())
"Write the scratch back to `tm`, as the last filparam/fillcost call leaves it (EPS kept)."
function put_fil_scratch!(tm, s::FilScratch)
    foreach(n -> gput_scalar!(tm, n, getfield(s, Symbol(n))), FIL_SCRATCH)
    gput!(tm, "MY_ARRAY", s.MY_ARRAY)
    gput!(tm, "MY_FIL2", s.MY_FIL2)
    return tm
end

"""
    filparam_gdrate!(tm, ax, fil) -> Dict

filparam.gms with coef_obj.mod L41's arguments: G_DRATE(R,LL,CUR)
interpolated between its data years over every ALLYEAR element and
extrapolated over FIL, by the option in G_DRATE(R,'0',CUR) (DFUNC: < 0 none;
1 interpolation only; 2 EPS outside the data; 4 no forward, 5 no backward
extrapolation; above 10 by its last digit). Returns the new G_DRATE values.

The tuples are taken in GAMS order and the scratch scalars carried in
`scratch` (`FilScratch`), which is left as the last tuple leaves it.

GAMS: filparam.gms L19-42 (coef_obj.mod L41), v4.9.7.
"""
function filparam_gdrate!(tm, ax::YearAxis, fil::Set{String}; scratch::FilScratch=FilScratch(tm))
    gd = gvalues(tm, "G_DRATE", 3)
    # L21: UNCD7(R,CUR,...) for every (R,CUR) with a record in any year, looped in GAMS order
    tuples = collect(Set((k[1], k[3]) for k in keys(gd)))
    gams_sort!(tuples, tm.data)
    byrc = Dict{Tuple{String,String},Dict{String,Float64}}()
    for ((r, y, c), v) in gd
        get!(() -> Dict{String,Float64}(), byrc, (r, c))[y] = v
    end
    s = scratch
    first_val, last_val, my_f = s.FIRST_VAL, s.LAST_VAL, s.MY_F   # scalars keep their values across tuples
    F, Z, my_fyear, dfunc = s.F.v, s.Z.v, s.MY_FYEAR.v, Float64(s.DFUNC)
    for (r, c) in tuples
        F, Z, my_fyear = 0.0, Inf, 9999.0                  # L23
        recs = byrc[(r, c)]
        dfunc = round(Float64(gv(gd, (r, "0", c))), RoundNearestTiesAway)   # L24: ROUND(G_DRATE(R,'0',CUR))
        dfunc >= 0 || continue                             # L26
        # L27-35: data years in ALLYEAR order ('0' excluded), interpolate between them over ALLYEAR
        for y in ax.years
            y == "0" && continue
            v = get(recs, y, nothing)
            v === nothing && continue
            my_f = v == 0.0 ? GEPS : GNum(v)
            Zy = ax.yearval[y]
            if Zy > my_fyear + 1
                for ll in ax.years
                    yl = ax.yearval[ll]
                    (Zy > yl && yl > my_fyear) || continue
                    gassign!(gd, (r, ll, c), last_val + (my_f - last_val) / GNum(Zy - my_fyear) * GNum(yl - my_fyear))
                end
            elseif Zy < my_fyear
                F, first_val = Zy, my_f
            end
            last_val, my_fyear, Z = my_f, Zy, Zy
        end
        # L37-40
        if dfunc > 1
            dfunc = mod(dfunc, 10)
            if dfunc == 2
                first_val, last_val = GEPS, GEPS
            elseif dfunc == 4
                Z = Inf
            elseif dfunc == 5
                F = 0.0
            end
        end
        dfunc != 1 || continue
        for ll in ax.years
            ll in fil || continue
            yl = ax.yearval[ll]
            x = gif(first_val, yl < F) + gif(last_val, yl > Z)
            iszero(x) || gassign!(gd, (r, ll, c), x)     # $=
        end
    end
    s.F, s.Z, s.MY_F, s.DFUNC = GNum(F), GNum(Z), my_f, GNum(dfunc)
    s.LAST_VAL, s.FIRST_VAL, s.MY_FYEAR = last_val, first_val, GNum(my_fyear)
    return gd
end

"""
    fillcost(src, take, ax, fil, dm_year; bext, fext, data_years) -> Dict

fillcost.gms for one cost parameter `src` whose year is its second index:
for each tuple of the other indices with a record in any year (and `take`),
the values at the DM_YEAR years are interpolated linearly over the FIL years
between them and extrapolated (first value backward where `bext(t, year)`,
last value forward where `fext(t, year)`). Returns the cache keyed by the
other indices then the year: with `%OBMAC%` YES (`data_years = true`, L37)
it holds the data years too; otherwise only the filled years, which
fillcost.gms L41 writes back into the source parameter. With `scratch`
(a `FilScratch`) and `data` (the model's DumpData, for the GAMS order of the
tuples), the scratch scalars are carried in and left as the last tuple of
the UNCD7 loop leaves them.

GAMS: fillcost.gms L19-42, v4.9.7.
"""
function fillcost(src::Dict{NTuple{N,String},Float64}, take, ax::YearAxis, fil::Vector{String}, dm_year::Vector{String};
                  bext=(t, y) -> true, fext=(t, y) -> true, data_years::Bool,
                  scratch::Union{Nothing,FilScratch}=nothing, data=nothing) where {N}
    filset = Set(fil)
    dm = Set(dm_year)
    # L26: UNCD7(R,'0',rest)$take $= SRC(R,LL,rest), every year
    bucket = Dict{NTuple{N - 1,String},Dict{String,Float64}}()
    for (k, v) in src
        t = (k[1], k[3:end]...)
        take(t) || continue
        b = get!(() -> Dict{String,Float64}(), bucket, t)
        k[2] in dm && (b[k[2]] = v)
    end
    cache = Dict{NTuple{N,String},Float64}()
    # L27: LOOP(UNCD7(R,YEAR,rest), ...) in GAMS order (YEAR is the one label '0', so the order of (R,rest))
    tuples = collect(keys(bucket))
    data === nothing || gams_sort!(tuples, data)
    s = scratch === nothing ? FilScratch() : scratch
    first_val, my_fyear, Z, my_f = s.FIRST_VAL, s.MY_FYEAR.v, s.Z.v, s.MY_F   # kept across tuples
    F, last_val = s.F.v, s.LAST_VAL                        # L27 resets these two
    for t in tuples
        b = bucket[t]
        F, last_val = 0.0, GZERO
        my_fil2 = Dict{String,GNum}()
        if scratch !== nothing                                     # L28-29: MY_ARRAY(DM_YEAR) = SRC(t,DM_YEAR)
            for y in dm_year
                v = get(b, y, nothing)
                v === nothing ? delete!(s.MY_ARRAY, (y,)) : (s.MY_ARRAY[(y,)] = v)
            end
        end
        # L30-35: the data years in DM_YEAR order
        for y in dm_year
            v = get(b, y, nothing)
            v === nothing && continue
            my_f = v == 0.0 ? GEPS : GNum(v)
            Zy = ax.yearval[y]
            if !iszero(last_val)                           # IF(LAST_VAL, ...): EPS is true
                # GAMS sets LAST_VAL to the slope here (L33); L35 sets it to MY_F again, so only the end shows
                slope = (my_f - last_val) / GNum(Zy - my_fyear)
                for cnt in Int(my_fyear - Zy + 1):-1
                    yt = lead(ax, y, cnt)
                    (yt !== nothing && yt in filset) || continue
                    x = my_f + slope * GNum(cnt)
                    iszero(x) ? delete!(my_fil2, yt) : (my_fil2[yt] = x)
                end
            else
                F, first_val = Zy, my_f
            end
            last_val, my_fyear, Z = my_f, Zy, Zy
        end
        # L37 (%OBMAC% YES): MY_FIL2(FIL) $= MY_ARRAY(FIL), the data years
        if data_years
            for y in fil
                v = get(b, y, nothing)
                v === nothing || (my_fil2[y] = v == 0.0 ? GEPS : GNum(v))
            end
        end
        # L38: DATA(t,FIL) $= FIRST_VAL$(bext(YEARVAL(FIL) LT F)) + MY_FIL2(FIL) + LAST_VAL$(fext(YEARVAL(FIL) GT Z))
        for y in fil
            yv = ax.yearval[y]
            x = gif(first_val, bext(t, yv) && yv < F) + get(my_fil2, y, GZERO) + gif(last_val, fext(t, yv) && yv > Z)
            iszero(x) || (cache[(t..., y)] = x.eps ? 0.0 : x.v)
        end
        if scratch !== nothing                                     # MY_FIL2 as the tuple leaves it (cleared at L28)
            s.MY_FIL2 = Dict{Tuple{String},Float64}((y,) => (x.eps ? 0.0 : x.v) for (y, x) in my_fil2)
        end
    end
    if scratch !== nothing
        s.F, s.Z, s.MY_F, s.LAST_VAL, s.FIRST_VAL, s.MY_FYEAR = GNum(F), GNum(Z), my_f, last_val, first_val, GNum(my_fyear)
    end
    return cache
end

"fillcost.gms L41 without `%OBMAC%`: SRC(R,FIL,rest) \$= the cache (keyed rest then year)."
function fillcost_writeback!(src::Dict{NTuple{N,String},Float64}, cache::Dict{NTuple{N,String},Float64}) where {N}
    for (k, v) in cache
        src[(k[1], k[N], k[2:N-1]...)] = v
    end
    return src
end

"""
    coef_obj!(tm) -> tm

coef_obj.mod on the GAMS state in `tm`: the year sets Y, Y_EOH, YK and
TS_ANN (and EACHYEAR, L28), G_DRATE interpolated (L41, filparam.gms) and
floored at 1e-11 (L56), the discount factors OBJ_DISC, the reporting currency
G_RCUR, OBJ_PVT, COEF_PVT and OBJ_RFR, the cleaned commodity, trade and flow
cost data and OBJ_VFLO (L70-88), and the cost caches OB_* filled over the
years by fillcost.gms (L102-151); the work symbols it clears are left empty.

GAMS: coef_obj.mod L1-205, filparam.gms L19-42, fillcost.gms L19-42, v4.9.7.
"""
function coef_obj!(tm)
    u = coef_obj_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    ax = YearAxis(tm)
    S1(n) = gset(tm, n)
    mem(n) = Set(k[1] for k in S1(n).keys)
    modlyear, milestonyr = mem("MODLYEAR"), mem("MILESTONYR")
    rdcur = S1("RDCUR")
    reg = mem("REG")
    yv(y) = ax.yearval[y]

    # L16-18: TS_ANN(S,S) = YES; TS_ANN(S,ANNUAL) = YES
    ts_ann = Set{NTuple{2,String}}()
    for (s,) in S1("ALL_TS").keys
        push!(ts_ann, (s, s))
        foreach(a -> push!(ts_ann, (s, a[1])), S1("ANNUAL").keys)
    end
    gput!(tm, "TS_ANN", ts_ann)

    # L27-30: YR_VL; K(LL+NCAP_ILED) for past milestones with a lead time; Y, YK
    minyr = gscalar(tm, "MINYR")
    yr_vl = gscalar(tm, "MIYR_VL") + gscalar(tm, "DUR_MAX")
    eachyear = gmembers(tm, "EACHYEAR", 1)
    pastmile = mem("PASTMILE")
    iled = gparam(tm, "NCAP_ILED")
    for (r, ll, p) in S1("RTP").keys
        (ll in pastmile && haskey(iled, (r, ll, p))) || continue
        y = lead(ax, ll, glead(iled[(r, ll, p)]))
        y === nothing || push!(eachyear, (y,))
    end
    gput!(tm, "EACHYEAR", eachyear)
    ks = [k[1] for k in gset(tm, "EACHYEAR").keys]
    y_set = [k for k in ks if minyr <= yv(k) <= yr_vl]
    gput!(tm, "Y", Set((k,) for k in y_set))
    gput!(tm, "YK", Set((y, k) for y in y_set for k in ks if yv(k) <= yv(y)))
    # L31-32: %ANNCOST% LEV. ACL = MINYR; MINYR = MIYR_V1; RPT_OPT('OBJ','2') = 1; then
    # MINYR = ACL when %CTST% is empty (the $IFI compares '%ANNCOST%%CTST%' with LEV)
    acl = 0.0
    if uppercase(gswitch(tm, "ANNCOST", "")) == "LEV"
        acl = minyr
        minyr = gscalar(tm, "MIYR_V1")
        rpt_opt = gvalues(tm, "RPT_OPT", 2)
        foreach(l -> register_uel!(tm.data, l), ("OBJ", "2"))
        rpt_opt[("OBJ", "2")] = 1.0
        gput!(tm, "RPT_OPT", rpt_opt)
        ctst(tm) == "" && (minyr = acl)
        gput_scalar!(tm, "MINYR", minyr)
    end
    # L33
    y_eoh = [e[1] for e in S1("EOHYEARS").keys if yv(e[1]) >= minyr]
    gput!(tm, "Y_EOH", Set((e,) for e in y_eoh))

    # L35-38: FIL over YR_V1..YR_VL
    datayear = mem("DATAYEAR")
    yr_v1 = min(minimum((yv(d) for d in datayear); init=Inf), gscalar(tm, "PYR_V1"))
    yr_vl = max(maximum((yv(d) for d in datayear); init=-Inf), yr_vl)
    fil = Set(y for y in ax.years if yr_v1 <= yv(y) <= yr_vl)
    gput_scalar!(tm, "YR_V1", yr_v1)
    gput_scalar!(tm, "YR_VL", yr_vl)
    gput_scalar!(tm, "ACL", acl)                # L19 declares it 0; L31 sets it

    # L41: interpolate the discount rates
    scratch = FilScratch(tm)                    # filparam.gms and fillcost.gms scratch, carried call to call
    gd = filparam_gdrate!(tm, ax, fil; scratch)
    gdv(r, y, c) = gv(gd, (r, y, c))

    # L45-54: OBJ_DISC, cumulative from YR_V1, normalised to the base year
    disc = gvalues(tm, "OBJ_DISC", 3)
    for (r, c) in rdcur.keys, y in ax.years
        yv(y) == yr_v1 && (disc[(r, y, c)] = 1.0)
    end
    g_dyear = gscalar(tm, "G_DYEAR")
    if g_dyear == 0                                                    # L46
        g_dyear = sum((yv(k[1]) for k in S1("MIYR_1").keys if k[1] in milestonyr); init=0.0)
        gput_scalar!(tm, "G_DYEAR", g_dyear)
    end
    # GAMS divides for every (R,CUR), so a G_DRATE of -1 there is an error even where OBJ_DISC is zero (G9)
    curs_all = mem("CUR")
    minus1 = Set(k[2] for (k, x) in gd if x == -1.0 && k[1] in reg && k[3] in curs_all)
    pairs_rc = unique((k[1], k[3]) for k in keys(disc))
    for i in 2:length(ax.years)                                        # L48: LOOP(FIL(LL-1), ...), sequential
        prev, ll = ax.years[i-1], ax.years[i]
        prev in fil || continue
        ll in minus1 && throw(DomainError(-1.0, "G_DRATE(R,'$ll',CUR) = -1: coef_obj.mod L48 divides by 1+G_DRATE (GAMS: division by zero)"))
        for (r, c) in pairs_rc                                         # OBJ_DISC(R,LL-1,CUR) is zero elsewhere
            gassign!(disc, (r, ll, c), gv(disc, (r, prev, c)) / (GNum(1) + gdv(r, ll, c)))
        end
    end
    miyr_1 = [k[1] for k in S1("MIYR_1").keys]
    F = sum((yv(m) - max(min(yr_vl, g_dyear), yr_v1) for m in miyr_1); init=0.0)   # L50
    for (r, c) in rdcur.keys                                           # L52-54
        z = GZERO
        for m in miyr_1
            ll = lead(ax, m, -glead(F))                                # MIYR_1(LL+F)
            ll === nothing && continue
            z += gv(disc, (r, ll, c)) * gpow(GNum(1) + gdv(r, ll, c), GNum(-(g_dyear - yv(ll))))
        end
        for ll in ax.years
            ll in fil || continue
            gassign!(disc, (r, ll, c), gv(disc, (r, ll, c)) / z)
        end
    end
    gput!(tm, "OBJ_DISC", disc)
    # L56: G_DRATE(R,V,CUR)$((G_DRATE(R,V,CUR) LE 0)$RDCUR(R,CUR)) = 1E-11
    for (r, c) in rdcur.keys, v in modlyear
        Float64(gdv(r, v, c)) <= 0 && (gd[(r, v, c)] = 1e-11)
    end
    gput!(tm, "G_DRATE", gd)

    # L59-62: the reporting currency of each region without one: the first
    # with the largest present value of the periods
    g_rcur = gmembers(tm, "G_RCUR", 2)
    d = gparam(tm, "D")
    pv(r, c) = sum((gv(d, (t,)) * gv(disc, (r, t, c)) for t in ax.years if t in milestonyr); init=GZERO)
    for r in (k[1] for k in S1("REG").keys)
        any(k -> k[1] == r && k in g_rcur, rdcur.keys) && continue
        curs = [k[2] for k in rdcur.keys if k[1] == r]
        Z = isempty(curs) ? -Inf : maximum(Float64(pv(r, c)) for c in curs)
        for c in curs
            Z == 0 && break                                            # the $Z is evaluated each iteration (G30)
            abs(Float64(pv(r, c)) - Z) < 1e-7 && (push!(g_rcur, (r, c)); Z = 0.0)
        end
    end
    gput!(tm, "G_RCUR", g_rcur)
    # L63-66
    periodyr = indexby(S1("PERIODYR"), (1,))
    y_eoh_set = Set(y_eoh)
    obj_pvt = gvalues(tm, "OBJ_PVT", 3)
    for (r, c) in rdcur.keys, t in ax.years
        t in milestonyr || continue
        x = sum((gv(disc, (r, k[2], c)) for k in get(periodyr, (t,), NTuple{2,String}[]) if k[2] in y_eoh_set); init=GZERO)
        gassign!(obj_pvt, (r, t, c), x)
    end
    gput!(tm, "OBJ_PVT", obj_pvt)
    coef_pvt = gvalues(tm, "COEF_PVT", 2)
    for r in reg, t in milestonyr
        x = sum((gv(obj_pvt, (r, t, k[2])) for k in g_rcur if k[1] == r); init=GZERO)
        gassign!(coef_pvt, (r, t), x)
    end
    gput!(tm, "COEF_PVT", coef_pvt)
    obj_rfr = gvalues(tm, "OBJ_RFR", 3)
    for ((r, v, c), x) in gd                                           # L65: $= G_DRATE(R,V,CUR)
        v in modlyear && (obj_rfr[(r, v, c)] = x)
    end
    g_rfrir = gparam_opt(tm.data, "G_RFRIR", 2)
    for (r, c) in rdcur.keys, ((r2, v), x) in g_rfrir.values         # L66
        (r2 == r && v in modlyear) && (obj_rfr[(r, v, c)] = x)
    end
    gput!(tm, "OBJ_RFR", obj_rfr)

    # L70-71: commodity costs outside the commodity's timeslices
    com_ts = S1("COM_TS")
    for n in ("OBJ_COMNT", "OBJ_COMPD")
        p = gvalues(tm, n, 6)
        filter!(kv -> !(kv[1][2] in datayear && !((kv[1][1], kv[1][3], kv[1][4]) in com_ts)), p)
        gput!(tm, n, p)
    end
    # L76-78: IRE_PRICE of exogenous trade into OBJ_IPRIC, exports negative
    ipric = gvalues(tm, "OBJ_IPRIC", 7)
    ireio = S1("RPC_IREIO")
    xpt = mem("XPT")
    ire_price = gparam_opt(tm.data, "IRE_PRICE", 8)
    xsign(ie) = GNum(1) - gif(GNum(2), ie in xpt)
    function ipric_from!(allr_of)
        for (k, x) in ire_price.values
            (r, y, p, c, s, allr, ie, cur) = k
            (allr_of(r, allr) && y in datayear && (r, p, c, ie, "OUT") in ireio) || continue
            val = (x == 0.0 ? GEPS : GNum(x)) * xsign(ie)
            iszero(val) || (ipric[(r, y, p, c, s, ie, cur)] = val.eps ? 0.0 : val.v)
        end
    end
    for (allr,) in S1("ALL_REG").keys                                 # L76-77, in ALL_REG order
        allr in reg && continue
        ipric_from!((r, a) -> a == allr)
    end
    ipric_from!((r, a) -> a == r)                                      # L78
    # L80-81: no FLO_COST on storage output nor FLO_DELIV on storage input
    top = S1("TOP")
    rpc_stg = S1("RPC_STG")
    flo_cost, flo_deliv = gvalues(tm, "FLO_COST", 6), gvalues(tm, "FLO_DELIV", 6)
    filter!(kv -> !((kv[1][1], kv[1][3], kv[1][4]) in rpc_stg && !((kv[1][1], kv[1][3], kv[1][4], "IN") in top)), flo_cost)
    filter!(kv -> !((kv[1][1], kv[1][3], kv[1][4]) in rpc_stg && !((kv[1][1], kv[1][3], kv[1][4], "OUT") in top)), flo_deliv)
    gput!(tm, "FLO_COST", flo_cost)
    gput!(tm, "FLO_DELIV", flo_deliv)
    # L82-84: OBJ_FSUB = FLO_TAX - FLO_SUB
    flo_tax, flo_sub = gparam_opt(tm.data, "FLO_TAX", 6), gparam_opt(tm.data, "FLO_SUB", 6)
    fsub = gvalues(tm, "OBJ_FSUB", 6)
    for (k, x) in flo_tax.values
        fsub[k] = x
    end
    for (k, x) in flo_sub.values
        gassign!(fsub, k, gv(fsub, k) - (x == 0.0 ? GEPS : GNum(x)))
    end
    vflo = gmembers(tm, "OBJ_VFLO", 5)
    filter!(kv -> !(!(kv[1][2] in modlyear) && (kv[1][1], kv[1][3], kv[1][4], kv[1][6], "SUB") in vflo), fsub)
    # L85-88: OBJ_VFLO from the cost data present, by type
    for (p, tag) in ((flo_cost, "COST"), (flo_deliv, "COST"), (flo_tax.values, "TAX"), (flo_sub.values, "SUB"))
        for k in keys(p)
            push!(vflo, (k[1], k[3], k[4], k[6], tag))
        end
    end
    gput!(tm, "OBJ_VFLO", vflo)
    # L90: no proportional investment subsidy where an absolute one is given
    ispct = gvalues(tm, "NCAP_ISPCT", 3)
    prc_ymax = gvalues(tm, "PRC_YMAX", 2)
    if !isempty(ispct)
        prc_ymax = Dict{NTuple{2,String},Float64}()
        for k in keys(gparam_opt(tm.data, "NCAP_ISUB", 4).values)      # OPTION PRC_YMAX < NCAP_ISUB: record counts (G31)
            prc_ymax[(k[1], k[3])] = get(prc_ymax, (k[1], k[3]), 0.0) + 1
        end
        filter!(kv -> !haskey(prc_ymax, (kv[1][1], kv[1][3])), ispct)
        gput!(tm, "NCAP_ISPCT", ispct)
    end

    # L102-107: each process's first and last relevant year
    B, M, E, IPD, LAGT = (gparam(tm, n) for n in ("B", "M", "E", "IPD", "LAGT"))
    my_array(v) = gmin(gv(B, (v,)), gv(M, (v,)) - gv(IPD, (v,)))
    rtp = S1("RTP")
    rtp_by_rp = indexby(rtp, (1, 3))
    pastyear = mem("PASTYEAR")
    prc_ymin = gvalues(tm, "PRC_YMIN", 2)
    tlife, rpti = gparam(tm, "NCAP_TLIFE"), gparam(tm, "COEF_RPTI")
    rps = S1("RP").keys
    for (r, p) in rps
        ks_rp = get(rtp_by_rp, (r, p), NTuple{3,String}[])
        prc_ymin[(r, p)] = minimum((Float64(my_array(k[2])) for k in ks_rp if k[2] in modlyear); init=Inf)
        prc_ymax[(r, p)] = maximum((yv(k[2]) for k in ks_rp if k[2] in pastyear); init=-Inf)
    end
    for t in ax.years                                                  # L106-107, T in order
        t in milestonyr || continue
        z = gv(M, (t,)) - gv(E, (t,)) + gv(LAGT, (t,))
        for (r, p) in rps
            (r, t, p) in rtp || continue
            x = gv(E, (t,)) + gv(iled, (r, t, p)) + gif(gmax(z, gv(tlife, (r, t, p))), Float64(gv(rpti, (r, t, p))) > 1)
            prc_ymax[(r, p)] = Float64(gmax(GNum(prc_ymax[(r, p)]), x))
        end
    end
    pymin(r, p) = get(prc_ymin, (r, p), 0.0)
    pymax(r, p) = get(prc_ymax, (r, p), 0.0)

    # L112-113: FIL = EACHYEAR up to the last year any process needs
    zmax = maximum((pymax(r, p) for (r, p) in rps); init=-Inf)
    fil_inv = [k for k in ks if yv(k) <= zmax]
    dm_year = [k[1] for k in S1("DM_YEAR").keys]
    empty!(scratch.MY_ARRAY)                                           # L113: OPTION CLEAR=MY_ARRAY (after L102's use)

    # L120-133: investment, fixed and decommissioning costs into the OB_* caches
    # L96-99: %TAKE% is RDCUR(R,CUR), or 1 with $IF DEFINED R_CUREX (R_CUREX has data here, see the header)
    curex = !isempty(gparam_opt(tm.data, "R_CUREX", 3).keys)
    take_rd(t) = curex || (t[1], t[3]) in rdcur
    bext(t, y) = y >= pymin(t[1], t[2])
    fext(t, y) = y <= pymax(t[1], t[2])
    for (n, cache) in (("NCAP_COST", "OB_ICOST"), ("NCAP_ISUB", "OB_ISUB"), ("NCAP_ITAX", "OB_ITAX"))
        gput!(tm, cache, fillcost(gvalues(tm, n, 4), take_rd, ax, fil_inv, dm_year; bext, fext, data_years=true,
                                  scratch, data=tm.data))
    end
    # L123-124: NCAP_ISPCT into X_RP, then OB_ISUB(RP,CUR,YEAR)$X_RP $= OB_ICOST*X_RP
    x_rp = fillcost(ispct, t -> true, ax, fil_inv, dm_year; bext, fext, data_years=true, scratch, data=tm.data)
    if !isempty(x_rp)
        ob_isub = gvalues(tm, "OB_ISUB", 4)
        ob_icost = gparam(tm, "OB_ICOST")
        rpset = S1("RP")
        for ((r, p, y), xr) in x_rp, (c,) in S1("CUR").keys
            (r, p) in rpset || continue
            x = gv(ob_icost, (r, p, c, y)) * (xr == 0.0 ? GEPS : GNum(xr))
            iszero(x) || (ob_isub[(r, p, c, y)] = x.eps ? 0.0 : x.v)
        end
        gput!(tm, "OB_ISUB", ob_isub)
    end
    gput!(tm, "X_RP", Dict{NTuple{3,String},Float64}())
    for (n, cache) in (("NCAP_FOM", "OB_FOM"), ("NCAP_FSUB", "OB_FSB"), ("NCAP_FTAX", "OB_FTX"),
                       ("NCAP_DCOST", "OB_DCC"), ("NCAP_DLAGC", "OB_DLC"))
        gput!(tm, cache, fillcost(gvalues(tm, n, 4), take_rd, ax, fil_inv, dm_year; bext, fext, data_years=true,
                                  scratch, data=tm.data))
    end

    # L135-136: FIL for the variable costs: the milestones with VARCOST LIN, else Y_EOH from MIYR_V1
    miyr_v1 = gscalar(tm, "MIYR_V1")
    fil_var = varcost(tm) == "LIN" ? [y for y in ax.years if y in milestonyr] :
              [y for y in ax.years if y in y_eoh_set && yv(y) >= miyr_v1]
    gput!(tm, "FIL", Set((y,) for y in fil_var))
    fil_var_sorted = [k[1] for k in gset(tm, "FIL").keys]

    # L140: activity costs
    rpset = S1("RP")
    gput!(tm, "OB_ACT", fillcost(gvalues(tm, "ACT_COST", 4), t -> (t[1], t[2]) in rpset, ax, fil_var_sorted, dm_year;
                                 data_years=true, scratch, data=tm.data))
    # L143-145: commodity and trade costs, filled years written back (no cache)
    for n in ("OBJ_COMNT", "OBJ_COMPD")
        p = gvalues(tm, n, 6)
        fillcost_writeback!(p, fillcost(p, t -> (t[1], t[2], t[3]) in com_ts, ax, fil_var_sorted, dm_year; data_years=false,
                                        scratch, data=tm.data))
        gput!(tm, n, p)
    end
    rpcs_var = S1("RPCS_VAR")
    fillcost_writeback!(ipric, fillcost(ipric, t -> (t[1], t[2], t[3], t[4]) in rpcs_var, ax, fil_var_sorted, dm_year;
                                        data_years=false, scratch, data=tm.data))
    gput!(tm, "OBJ_IPRIC", ipric)
    gput!(tm, "OB_COM", Dict{NTuple{6,String},Float64}())
    gput!(tm, "OB_IRE", Dict{NTuple{7,String},Float64}())
    # L148-151: flow costs, taxes and subsidies
    annual = mem("ANNUAL")
    take_flo(t) = (t[1], t[2], t[3], t[4]) in rpcs_var || t[4] in annual
    for (p, cache) in ((flo_cost, "OB_FCOS"), (flo_deliv, "OB_FDEL"), (fsub, "OB_FTAX"))
        gput!(tm, cache, fillcost(p, take_flo, ax, fil_var_sorted, dm_year; data_years=true, scratch, data=tm.data))
    end
    put_fil_scratch!(tm, scratch)               # as the last fillcost call (L151) leaves them

    # L153-154: OPTION CLEAR=PRC_YMIN, PRC_YMAX, RPC_CUR, OBJ_FSUB
    gput!(tm, "PRC_YMIN", Dict{NTuple{2,String},Float64}())
    gput!(tm, "PRC_YMAX", Dict{NTuple{2,String},Float64}())
    gput!(tm, "RPC_CUR", Set{NTuple{4,String}}())
    gput!(tm, "OBJ_FSUB", Dict{NTuple{6,String},Float64}())
    return tm
end
