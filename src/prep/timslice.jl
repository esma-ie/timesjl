# M1.3 (4): timeslice preprocessing, included at ppmain.mod L196.
#
# GAMS: timslice.mod L1-123, v4.9.7, with pp_off.mod (L36; pp_off.jl).
#
# Index sets: R is REG and ALL_R is ALL_REG (initsys.mod L87-88), so L18 and
# L43 reach external regions and the other statements do not; S, TS and SL are
# aliases of ALL_TS (initmty.mod L89), TSL of TSLVL (L98), JJ of J (initsys.mod
# L82). Leads and lags on ALL_TS and J move along the set's order (`OrdAxis`).
# `OPTION a < b` pairs a domain that `b` repeats in reverse order (G26) and,
# onto a parameter, counts records (G31). A statement reads the values from
# before it (G11); `x $= y` keeps x where y is 0 (G24); EPS compares as 0 (G12).
# %OBMAC% is YES on any GAMS from 23.0 (initmty.mod L21).
#
# Not translated: the QA log (L81-82, a warning when year fractions are
# normalised; L101-104, a FATAL line, ERRLEV 99, for timeslices with several
# parents, acted on by pp_qack.mod), m13-plan.md open items. The scratch
# scalars Z, F, MY_F, PUTGRP and pp_off's FIL are not kept: every later use
# assigns them first. MY_SUM is kept: nothing later in the init -> prep
# segment assigns it, so the prep checkpoint holds what L72/L77 leave.

"""
    OrdAxis(labels)

A GAMS set in its order (the dump's record order, which is ORD's: GAMS allows
ORD only on ordered sets), for ORD, leads and lags on ALL_TS and J.
"""
struct OrdAxis
    labels::Vector{String}
    pos::Dict{String,Int}
end
OrdAxis(labels::Vector{String}) = OrdAxis(labels, Dict(l => i for (i, l) in enumerate(labels)))
OrdAxis(tm, set::AbstractString) = OrdAxis([k[1] for k in gset(tm, set).keys])
"`l+n` on the set (nothing past either end)."
lead(ax::OrdAxis, l::String, n::Integer) = (i = ax.pos[l] + n; 1 <= i <= length(ax.labels) ? ax.labels[i] : nothing)
"`l++n` on the set (circular)."
circlead(ax::OrdAxis, l::String, n::Integer) = ax.labels[mod1(ax.pos[l] + n, length(ax.labels))]

"""
    timslice_symbols(tm) -> Vector{String}

The symbols timslice.mod settles that nothing later in the init -> prep segment
changes (for the layer-1 check at the prep checkpoint): ppmain.mod L199-248,
preppm.mod L1-217 with its includes and prep_ext.vda only read them.
"""
timslice_symbols(tm) =
    ["TS_GROUP", "TS_MAP", "STOAL", "RS_BELOW", "RS_BELOW1", "NORTS", "G_YRFR", "FINEST", "RS_TREE", "RJLVL", "RLUP",
     "G_CYCLE", "TS_CYCLE", "RS_STGPRD", "RS_TSLVL", "RS_STG", "RS_STGAV", "STOA", "RS_HR", "JS", "RJ_SL", "RS_UP",
     "JS_CCL", "RS_MODUS"]

"""
    timslice!(tm) -> tm

timslice.mod on the state after `ppmain_years!`: the timeslice levels and
tree, the year fractions (filled in, cleaned of zero fractions, normalised),
the timeslices turned off (TS_OFF, NORTS), the storage cycles and lags, and,
for processes with ramping or start-up costs, the hour maps of unit
commitment. The ABORTs at L24 and L74 raise an error with GAMS's message, and
so does a division by zero, which stops a GAMS run.

GAMS: timslice.mod L1-123, pp_off.mod L17-22, v4.9.7.
"""
function timslice!(tm)
    d = tm.data
    reg = [k[1] for k in gset(tm, "REG").keys]
    allr = [k[1] for k in gset(tm, "ALL_REG").keys]
    tsax, jax = OrdAxis(tm, "ALL_TS"), OrdAxis(tm, "J")
    tslvl = [k[1] for k in gset(tm, "TSLVL").keys]
    tslord = Dict(l => i for (i, l) in enumerate(tslvl))
    ann = only(k[1] for k in gset(tm, "ANNUAL").keys)               # SET ANNUAL(ALL_TS) / ANNUAL / (initsys.mod L48)
    tset = [k[1] for k in gset(tm, "MILESTONYR").keys]
    regset = Set(reg)
    sorted(x) = gams_sort!(collect(x), d)
    num(p, k) = (v = get(p, k, nothing); v === nothing ? 0.0 : v)  # the numeric value (EPS is 0, G12)
    divide(a, b, line) = b == 0 ? error("timslice.mod $line: division by zero") : a / b

    TS_GROUP, TS_MAP = gmembers(tm, "TS_GROUP", 3), gmembers(tm, "TS_MAP", 3)
    RS_BELOW, RS_BELOW1, RS_TREE = gmembers(tm, "RS_BELOW", 3), gmembers(tm, "RS_BELOW1", 3), gmembers(tm, "RS_TREE", 3)
    FINEST, RJLVL, RLUP = gmembers(tm, "FINEST", 2), gmembers(tm, "RJLVL", 3), gmembers(tm, "RLUP", 3)
    G_YRFR, NORTS, RS_HR = gvalues(tm, "G_YRFR", 2), gvalues(tm, "NORTS", 3), gvalues(tm, "RS_HR", 2)

    # --- Levels and tree (L18-28) ----------------------------------------------------
    # L18: TS_GROUP(ALL_R,'ANNUAL',S) = ANNUAL(S)
    filter!(k -> !(k[2] == "ANNUAL" && k[1] in allr), TS_GROUP)
    foreach(r -> push!(TS_GROUP, (r, "ANNUAL", ann)), allr)
    # L19: OPTION STOAL < TS_GROUP   (the number of levels of each (ALL_R,S))
    STOAL = Dict{NTuple{2,String},Float64}()
    foreach(((r, _, s),) -> STOAL[(r, s)] = get(STOAL, (r, s), 0.0) + 1, TS_GROUP)
    # L20: TS_MAP(R,ANNUAL,S) = STOAL(R,S)
    filter!(k -> !(k[1] in regset && k[2] == ann), TS_MAP)
    for r in reg, s in tsax.labels
        haskey(STOAL, (r, s)) && push!(TS_MAP, (r, ann, s))
    end
    # L21: TS_MAP(R,ALL_TS,TS)$SUM(TS_MAP(R,ALL_TS,S),TS_MAP(R,S,TS)) = YES   (one step, from the map before it)
    below = Dict{NTuple{2,String},Vector{String}}()
    foreach(((r, s, ts),) -> push!(get!(below, (r, s), String[]), ts), TS_MAP)
    for (r, a, s) in collect(TS_MAP)
        r in regset || continue
        foreach(ts -> push!(TS_MAP, (r, a, ts)), get(below, (r, s), String[]))
    end
    # L22: TS_MAP(R,S,S) = STOAL(R,S)
    for r in reg, s in tsax.labels
        haskey(STOAL, (r, s)) ? push!(TS_MAP, (r, s, s)) : delete!(TS_MAP, (r, s, s))
    end
    # L23: STOAL(ALL_R,S)$STOAL(ALL_R,S) = STOAL(ALL_R,S)-1;  L24: IF(CARD(STOAL),ABORT "Error: Timeslice on several levels.")
    foreach(k -> gassign!(STOAL, k, STOAL[k] - 1), collect(keys(STOAL)))
    isempty(STOAL) || error("timslice.mod L24: ABORT \"Error: Timeslice on several levels.\"")
    # L26: RS_BELOW(TS_MAP(R,S,TS))$(NOT TS_MAP(R,TS,S)) = YES
    for (r, s, ts) in TS_MAP
        (r in regset && !((r, ts, s) in TS_MAP)) && push!(RS_BELOW, (r, s, ts))
    end
    # L28: RS_BELOW1(RS_BELOW(R,S,TS))$(SUM(TS_MAP(R,S,ALL_TS)$RS_BELOW(R,ALL_TS,TS),1)=1) = YES
    rs_map = below_of(TS_MAP)
    for (r, s, ts) in RS_BELOW
        r in regset || continue
        count(a -> (r, a, ts) in RS_BELOW, get(rs_map, (r, s), String[])) == 1 && push!(RS_BELOW1, (r, s, ts))
    end

    # --- Timeslices turned off (L31-40) ------------------------------------------------
    # L31-33: MX is '' when %DYNTS% is YES and TS_OFF has data ($IF DEFINED, G35), else '(MIYR_1)'
    TS_OFF = gset_opt(d, "TS_OFF", 4)
    dynts = uppercase(gswitch(tm, "DYNTS", "")) == "YES" && !isempty(TS_OFF)
    miyr_1 = Set(k[1] for k in gset(tm, "MIYR_1").keys)
    tmx = dynts ? tset : filter(t -> t in miyr_1, tset)              # T%MX%
    # L35: LOOP(RS_BELOW1(R,ANNUAL,S)$SUM(TS_OFF(R,S,BOHYEAR,EOHYEAR),1), ...)   (TS_MAP is as after L22)
    offsc = PPOffScratch()
    for (r, a, s) in sorted(RS_BELOW1)
        (r in regset && a == ann) || continue
        ranges = [(b, e) for (r2, s2, b, e) in TS_OFF.keys if r2 == r && s2 == s]
        isempty(ranges) && continue
        # L36: $BATINCLUDE pp_off.mod TS_OFF S "" "NORTS(R,T%MX%,S)$(" 1
        fil = pp_off_fil(tm, ranges, offsc)
        foreach(t -> gassign!(NORTS, (r, t, s), 1.0), pp_off_periods(tm, fil, tmx))
        # L37-38: IF(PROD(T%MX%,FIL(T)), G_YRFR(R,TS)$TS_MAP(R,S,TS) = 0; ELSE NORTS(R,T(FIL%MX%),TS)$TS_MAP(R,S,TS) = -INF)
        if all(t -> (t,) in fil, tmx)
            foreach(ts -> delete!(G_YRFR, (r, ts)), get(rs_map, (r, s), String[]))
        else
            for t in tmx, ts in get(rs_map, (r, s), String[])
                (t,) in fil && gassign!(NORTS, (r, t, ts), -Inf)
            end
        end
    end
    pp_off_keep!(tm, offsc)

    # --- Year fractions (L43-46) -------------------------------------------------------
    # L43: G_YRFR(ALL_R,ANNUAL) = 1
    foreach(r -> gassign!(G_YRFR, (r, ann), 1.0), allr)
    # L45-46: G_YRFR(R,S)$((G_YRFR(R,S)<=0)$TS_GROUP(R,'WEEKLY',S)) $= SUM(RS_BELOW1(R,S,TS),G_YRFR(R,TS)); then 'SEASON'
    kids = below_of(RS_BELOW1, d)                                     # sums in GAMS order, as GAMS adds them
    for lvl in ("WEEKLY", "SEASON")
        for (r, l, s) in sorted(TS_GROUP)
            (r in regset && l == lvl && num(G_YRFR, (r, s)) <= 0) || continue
            x = sum((gv(G_YRFR, (r, ts)) for ts in get(kids, (r, s), String[])); init=GZERO)
            iszero(x) || gassign!(G_YRFR, (r, s), x)
        end
    end

    # --- Zero fractions removed; subtrees, finest, level maps (L50-63) --------------------
    # L50: LOOP(TSL,FINEST(R,S)$((G_YRFR(R,S)<=0)$TS_GROUP(R,TSL,S)) = YES)   (FINEST as scratch: zero fractions)
    zero = Set((r, s) for (r, _, s) in TS_GROUP if r in regset && num(G_YRFR, (r, s)) <= 0)
    union!(FINEST, zero)
    # L51-55: TS_GROUP, TS_MAP, RS_BELOW, RS_BELOW1 (with the slice last) and NORTS lose them
    filter!(k -> !(k[1] in regset && (k[1], k[3]) in FINEST), TS_GROUP)
    for x in (TS_MAP, RS_BELOW, RS_BELOW1)
        filter!(k -> !(k[1] in regset && (k[1], k[3]) in FINEST), x)
    end
    filter!(((k, _),) -> !((k[1], k[3]) in FINEST), NORTS)
    # L56: OPTION CLEAR=FINEST
    empty!(FINEST)
    # L58: RS_TREE(R,S,TS)$(TS_MAP(R,TS,S) OR RS_BELOW(R,S,TS)) = YES
    foreach(((r, ts, s),) -> r in regset && push!(RS_TREE, (r, s, ts)), TS_MAP)
    foreach(((r, s, ts),) -> r in regset && push!(RS_TREE, (r, s, ts)), RS_BELOW)
    # L60: FINEST(R,S)$(SUM(TS_MAP(R,S,TS),1)=1) = YES
    rs_map = below_of(TS_MAP)
    for ((r, s), v) in rs_map
        (r in regset && length(v) == 1) && push!(FINEST, (r, s))
    end
    # L61: LOOP(SAMEAS('5',J),RJLVL(J-ORD(TSL),R,TSL)=SUM(TS_GROUP(R,TSL,S),1))
    for r in reg, l in tslvl
        j = lead(jax, "5", -tslord[l])
        j === nothing && continue
        any(k -> k[1] == r && k[2] == l, TS_GROUP) ? push!(RJLVL, (j, r, l)) : delete!(RJLVL, (j, r, l))
    end
    # L63: LOOP((J,R,TSL)$RJLVL(J,R,TSL),Z=ORD(J);LOOP(RJLVL(JJ,R,TSLVL)$(ORD(JJ)>Z),RLUP(R,TSL,TSLVL)=1;Z=9))
    #   the inner condition is read for each element in turn, so Z=9 stops it after the first (the next coarser level)
    rjlvl = sorted(RJLVL)
    for (j, r, l) in rjlvl
        z = jax.pos[j]
        for (jj, r2, l2) in rjlvl
            (r2 == r && jax.pos[jj] > z) || continue
            push!(RLUP, (r, l, l2))
            z = 9
        end
    end

    # --- Normalising the year fractions (L67-83) -------------------------------------
    # L67: Z = 8760*3600 (one second)
    Z = 8760 * 3600.0
    MY_SUM = nothing                                                 # the scratch scalar, as the loop leaves it
    kids = below_of(RS_BELOW1, d)
    for (r, l, s) in sorted(TS_GROUP)                                # L69: LOOP(TS_GROUP(R,TSL,S)$(NOT FINEST(R,S)), ...)
        (r in regset && !((r, s) in FINEST)) || continue
        ch = get(kids, (r, s), String[])
        if s == ann && !isempty(NORTS)
            # L70-75: the ANNUAL step with timeslices turned off, over the periods
            F = 0.0
            for t in tset
                my_f = 1 - sum((num(RS_HR, (r, ts)) for ts in ch if haskey(RS_HR, (r, ts)) && num(NORTS, (r, t, ts)) == 0); init=0.0)
                my_sum = sum((num(G_YRFR, (r, ts)) for ts in ch if !haskey(RS_HR, (r, ts)) && num(NORTS, (r, t, ts)) == 0); init=0.0)
                MY_SUM = my_sum
                if my_sum * my_f > 0
                    for ts in ch
                        (num(NORTS, (r, t, ts)) == 0 && !haskey(RS_HR, (r, ts))) || continue
                        gassign!(RS_HR, (r, ts), my_f / my_sum * gv(G_YRFR, (r, ts)))
                    end
                elseif abs(my_f) > 99 / Z
                    error("timslice.mod L74: ABORT 'Invalid dynamic Timeslice configuration'")
                end
                F = max(F, abs(my_f - my_sum))
            end
            # L75: G_YRFR(R,TS) $= RS_HR(R,TS)
            for (k, v) in RS_HR
                k[1] in regset && gassign!(G_YRFR, k, v == 0.0 ? GEPS : GNum(v))
            end
        else
            # L77-78: MY_F=G_YRFR(R,S); MY_SUM=SUM(RS_BELOW1(R,S,TS),G_YRFR(R,TS)); F=ABS(MY_F-MY_SUM);
            #         IF(F*Z>1,G_YRFR(R,TS)$RS_BELOW1(R,S,TS)=MY_F/MY_SUM*G_YRFR(R,TS))
            my_f = num(G_YRFR, (r, s))
            my_sum = sum((num(G_YRFR, (r, ts)) for ts in ch); init=0.0)
            MY_SUM = my_sum
            F = abs(my_f - my_sum)
            if F * Z > 1
                q = divide(my_f, my_sum, "L78")
                foreach(ts -> gassign!(G_YRFR, (r, ts), q * gv(G_YRFR, (r, ts))), ch)
            end
        end
        # L80-83: IF(F*Z > 1, ...) writes a warning to the QA log only (not translated)
    end
    # MY_SUM as the last L72 or L77 leaves it: nothing later in the init -> prep segment assigns it
    MY_SUM === nothing || gput!(tm, "MY_SUM", iszero(MY_SUM) ? Dict{Tuple{},Float64}() : Dict{Tuple{},Float64}(() => MY_SUM))

    # --- Storage cycles and lags (L86-98) ----------------------------------------------
    # L86: G_CYCLE(TSL('WEEKLY'))$(G_CYCLE(TSL)=0)=8760/(24*7); TS_CYCLE(FINEST)=0
    G_CYCLE, TS_CYCLE = gvalues(tm, "G_CYCLE", 1), gvalues(tm, "TS_CYCLE", 2)
    num(G_CYCLE, ("WEEKLY",)) == 0 && gassign!(G_CYCLE, ("WEEKLY",), 8760 / (24 * 7))
    foreach(k -> delete!(TS_CYCLE, k), FINEST)
    # L87: LOOP(RLUP(R,TSLVL,TSL),TS_CYCLE(R,S)$((TS_CYCLE(R,S)<1)$TS_GROUP(R,TSL,S)) = 365/G_CYCLE(TSLVL))
    tsgroup = sorted(TS_GROUP)
    for (r, fine, coarse) in sorted(RLUP), (r2, l, s) in tsgroup
        (r2 == r && l == coarse && num(TS_CYCLE, (r, s)) < 1) || continue
        gassign!(TS_CYCLE, (r, s), divide(365, num(G_CYCLE, (fine,)), "L87"))
    end
    # L88: LOOP(TSL,RS_STGPRD(R,S)$TS_GROUP(R,TSL,S) = MAX(1,SUM(RS_BELOW1(R,TS,S),G_YRFR(R,TS)*365/TS_CYCLE(R,TS))))
    RS_STGPRD, RS_TSLVL = gvalues(tm, "RS_STGPRD", 2), gvalues(tm, "RS_TSLVL", 2)
    parents = Dict{NTuple{2,String},Vector{String}}()
    foreach(((r, ts, s),) -> push!(get!(parents, (r, s), String[]), ts), sorted(RS_BELOW1))
    tslnum = gparam(tm, "TSLVLNUM")
    for (r, l, s) in TS_GROUP
        r in regset || continue
        x = sum((num(G_YRFR, (r, ts)) * divide(365, num(TS_CYCLE, (r, ts)), "L88") for ts in get(parents, (r, s), String[]));
                init=0.0)
        gassign!(RS_STGPRD, (r, s), max(1.0, x))
        # L91: LOOP(TSL, RS_TSLVL(R,S)$TS_GROUP(R,TSL,S) = TSLVLNUM(TSL))
        gassign!(RS_TSLVL, (r, s), gv(tslnum, (l,)))
    end
    # L93-95: LOOP(TS_MAP(R,ANNUAL,S), F=0; LOOP(RS_BELOW1(R,S,TS), IF(F, RS_STG(R,TS)=ORD(TS)-Z; Z=ORD(TS);
    #         ELSE Z=ORD(TS); F=Z)); RS_STG(R,S+(F-ORD(S)))$F = F-Z)   (each child's lead from the previous one; the first wraps)
    RS_STG = gvalues(tm, "RS_STG", 2)
    zs = 0
    for (r, a, s) in sorted(TS_MAP)
        (r in regset && a == ann) || continue
        F = 0
        for ts in get(kids, (r, s), String[])
            if F != 0
                gassign!(RS_STG, (r, ts), tsax.pos[ts] - zs)
                zs = tsax.pos[ts]
            else
                zs = tsax.pos[ts]
                F = zs
            end
        end
        if F != 0
            first_child = lead(tsax, s, F - tsax.pos[s])
            first_child === nothing || gassign!(RS_STG, (r, first_child), F - zs)
        end
    end
    # L97: LOOP((R,S,TS(S--RS_STG(R,S)))$RS_STGPRD(R,S),RS_STGAV(R,S) = (G_YRFR(R,S)+G_YRFR(R,TS))/2/RS_STGPRD(R,S))
    RS_STGAV = gvalues(tm, "RS_STGAV", 2)
    for ((r, s), p) in RS_STGPRD
        (r in regset && haskey(tsax.pos, s)) || continue
        ts = circlead(tsax, s, -glead(num(RS_STG, (r, s))))
        gassign!(RS_STGAV, (r, s), (gv(G_YRFR, (r, s)) + gv(G_YRFR, (r, ts))) / 2 / GNum(p))
    end
    # L98: RS_STGAV(R,ANNUAL) = 1
    foreach(r -> gassign!(RS_STGAV, (r, ann), 1.0), reg)

    # --- Parents, lags to ANNUAL (L100-107) --------------------------------------------
    # L100: OPTION STOAL<RS_BELOW1,CLEAR=RS_HR; STOAL(R,S)$(STOAL(R,S)=1)=0   (parents of each child, G26)
    STOAL = Dict{NTuple{2,String},Float64}()
    foreach(((r, _, s),) -> STOAL[(r, s)] = get(STOAL, (r, s), 0.0) + 1, RS_BELOW1)
    empty!(RS_HR)
    filter!(((k, v),) -> !(k[1] in regset && v == 1), STOAL)
    # L101-104: IF(CARD(STOAL), ...) writes FATAL lines to the QA log only (not translated)
    # L106: LOOP(ANNUAL(TS), STOA(S) = ORD(TS)-ORD(S))
    STOA = Dict{Tuple{String},Float64}()
    foreach(s -> gassign!(STOA, (s,), tsax.pos[ann] - tsax.pos[s]), tsax.labels)
    # L107: LOOP(TSL,STOAL(R,S)$TS_GROUP(R,TSL,S) = ORD(TSL)-1)
    foreach(((r, l, s),) -> r in regset && gassign!(STOAL, (r, s), tslord[l] - 1), TS_GROUP)

    # --- Unit commitment: hours and cycles (L110-123) ------------------------------------
    JS, RJ_SL, RS_UP = gmembers(tm, "JS", 2), gmembers(tm, "RJ_SL", 4), gmembers(tm, "RS_UP", 4)
    JS_CCL, RS_MODUS = gvalues(tm, "JS_CCL", 3), gvalues(tm, "RS_MODUS", 5)
    if !isempty(gset_opt(d, "RP_UPR", 3)) || !isempty(gset_opt(d, "RP_UPT", 4))
        # L110: LOOP(TS_MAP(R,ANNUAL,TS),F=0;Z=0;LOOP(RS_BELOW1(R,TS,S),F=G_YRFR(R,S)/RS_STGPRD(R,S);RS_HR(R,S)=MOD(Z+F/2,1);Z=Z+F))
        for (r, a, ts) in sorted(TS_MAP)
            (r in regset && a == ann) || continue
            zh = 0.0
            for s in get(kids, (r, ts), String[])
                f = divide(num(G_YRFR, (r, s)), num(RS_STGPRD, (r, s)), "L110")
                gassign!(RS_HR, (r, s), rem(zh + f / 2, 1))
                zh += f
            end
        end
        # L111-115: LOOP(JS(J,ANNUAL), RJ_SL(R,J+(...),S,TS)$RS_BELOW1(R,S,TS) = YES (twice); OPTION RS_UP < RJ_SL)
        for (j, a) in sorted(JS)
            a == ann || continue
            for (r, s, ts) in RS_BELOW1
                r in regset || continue
                hr = num(RS_HR, (r, ts))
                for k in (rem(round(hr * 8760 / 146, RoundNearestTiesAway), 60) * 2,
                          rem(round((hr * 8760 - 73) / 146 + 60, RoundNearestTiesAway), 60) * 2 + 1)
                    jk = lead(jax, j, Int(k))
                    jk === nothing || push!(RJ_SL, (r, jk, s, ts))
                end
            end
            # RS_UP(R,TS,J,TS) < RJ_SL(R,J,TS,TS): the repeated TS paired in reverse order (G26), so RS_UP(R,child,J,parent)
            empty!(RS_UP)
            foreach(((r, jj, s, ts),) -> push!(RS_UP, (r, ts, jj, s)), RJ_SL)
        end
    end
    if !isempty(RS_UP)
        # L118: RS_UP(R,TS,J,S)$((MOD(RS_HR(R,TS)-(ORD(J)-2)*73/8760+1,1)<48/8760) OR (MOD(ORD(J)*73/8760-RS_HR(R,TS)+1,1)<25/8760)) = NO
        filter!(RS_UP) do (r, ts, j, s)
            hr, oj = num(RS_HR, (r, ts)), jax.pos[j]
            !(rem(hr - (oj - 2) * 73 / 8760 + 1, 1) < 48 / 8760 || rem(oj * 73 / 8760 - hr + 1, 1) < 25 / 8760)
        end
        # L119: OPTION JS < RS_UP; RJ_SL(R,J,S,TS)$(NOT JS(J,S)) = NO   (JS(J,parent), G26)
        JS = Set{NTuple{2,String}}((j, s) for (_, _, j, s) in RS_UP)
        filter!(((_, j, s, _),) -> (j, s) in JS, RJ_SL)
        # L121: JS_CCL(R,JS(J,S)) = MAX(1/G_YRFR(R,S),365/TS_CYCLE(R,S))
        for r in reg, (j, s) in JS
            gassign!(JS_CCL, (r, j, s), max(divide(1, num(G_YRFR, (r, s)), "L121"), divide(365, num(TS_CYCLE, (r, s)), "L121")))
        end
        # L122: RS_MODUS(RS_UP(R,S,JS),SL)$RJ_SL(R,JS,SL) =
        #       MOD(RS_HR(R,S)-RS_HR(R,SL)+G_YRFR(R,S)/RS_STGPRD(R,S)/2+2/JS_CCL(R,JS),1/JS_CCL(R,JS))
        slots = Dict{NTuple{3,String},Vector{String}}()
        foreach(((r, j, ts, sl),) -> push!(get!(slots, (r, j, ts), String[]), sl), RJ_SL)
        for (r, s, j, ts) in RS_UP, sl in get(slots, (r, j, ts), String[])
            (j, ts) in JS || continue
            ccl = num(JS_CCL, (r, j, ts))
            x = num(RS_HR, (r, s)) - num(RS_HR, (r, sl)) + divide(num(G_YRFR, (r, s)), num(RS_STGPRD, (r, s)), "L122") / 2 +
                divide(2, ccl, "L122")
            gassign!(RS_MODUS, (r, s, j, ts, sl), rem(x, divide(1, ccl, "L122")))
        end
    end

    for (s, v) in (("TS_GROUP", TS_GROUP), ("TS_MAP", TS_MAP), ("RS_BELOW", RS_BELOW), ("RS_BELOW1", RS_BELOW1),
                   ("FINEST", FINEST), ("RS_TREE", RS_TREE), ("RJLVL", RJLVL), ("RLUP", RLUP), ("JS", JS),
                   ("RJ_SL", RJ_SL), ("RS_UP", RS_UP))
        gput!(tm, s, v)
    end
    for (s, v) in (("STOAL", STOAL), ("NORTS", NORTS), ("G_YRFR", G_YRFR), ("G_CYCLE", G_CYCLE), ("TS_CYCLE", TS_CYCLE),
                   ("RS_STGPRD", RS_STGPRD), ("RS_TSLVL", RS_TSLVL), ("RS_STG", RS_STG), ("RS_STGAV", RS_STGAV),
                   ("STOA", STOA), ("RS_HR", RS_HR), ("JS_CCL", JS_CCL), ("RS_MODUS", RS_MODUS))
        gput!(tm, s, v)
    end
    return tm
end

"""
    below_of(x, data=nothing) -> Dict

The third labels of a 3-dimensional set `x` by its first two, e.g. the
children of each `(R,S)` in RS_BELOW1, in GAMS order when `data` is given
(the order a LOOP over `x(R,S,TS)` takes).
"""
function below_of(x, data=nothing)
    out = Dict{NTuple{2,String},Vector{String}}()
    keys = data === nothing ? collect(x) : gams_sort!(collect(x), data)
    foreach(((a, b, c),) -> push!(get!(out, (a, b), String[]), c), keys)
    return out
end
