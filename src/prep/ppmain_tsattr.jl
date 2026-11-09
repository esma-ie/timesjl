# M1.3 (10): ppmain.mod L683-797 (docs/m13-plan.md): the commodity
# attributes levelled to the commodity timeslices (pp_lvlfc.mod: COM_IE,
# COM_FR, COM_PKFLX, OBJ_COMNT, OBJ_COMPD, COM_ELAST, COM_BPRICE, COM_BQTY),
# COM_IE and COM_FR defaulted and COM_FR normalised, RS_FR and RTCS_FR, the
# elastic demand steps, the availability factors levelled to the process
# timeslices (pp_lvlbr.mod) with their defaults, and the peak contributions
# (pp_lvlpk.mod).
#
# GAMS: ppmain.mod L683-797, pp_lvlfc.mod L19-45, pp_lvlbr.mod L15-55,
# pp_lvlpk.mod L12-55, v4.9.7.
#
# Index sets: R is REG, P is PRC, C is COM, CG is COM_GRP, S, TS and SL are
# ALL_TS, T is MILESTONYR, V is MODLYEAR, LL and YEAR are ALLYEAR, J the
# step indexes '1' to '999', BD is BND_TYPE (LO, FX, UP), IO is IN_OUT. A
# controlling alias of a subset filters a set's or a parameter's records
# (G8, G27). `$x` is true for EPS (G3) and `NOT x` false (G25); a numeric
# comparison takes EPS as 0 (G12); `$=` writes only a nonzero or EPS value
# (G24); a right-hand side that names the symbol being assigned reads it as
# it was before the statement (G11); a scalar `$` on a loop domain is read
# again before each member (G30, G46). The QA log (pp_qaput.mod: PUTOUT,
# PUTGRP, ERRLEV) is written in LOOP order (M1.3 change 25b-1): the COM_FR
# normalisation (L723-728) and pp_lvlbr.mod's bound conflicts (L23-24,
# L47-52); within pp_lvlbr.mod PUTGRP also says whether a conflict was found. The
# scratch UNCD7, TS_ARRAY, Z, F and the work sets are left as GAMS leaves them.

"""
    ppmain_tsattr_unported(tm) -> Vector{String}

What ppmain.mod L683-797 meets that is not translated: TIMES-Micro (L749,
pp_micro.mod) and the dynamic timeslice tree (L742: `RTS(S)` is
`S+NORTS(R,T,S)` when %DYNTS% is YES and TS_OFF has data, timslice.mod
L31-33, L39).
"""
function ppmain_tsattr_unported(tm)
    out = String[]
    yes(n) = uppercase(gswitch(tm, n, "")) == "YES"
    # maindrv.mod L25: %MICRO% YES sets %TIMESED% YES unless the run set it otherwise
    (yes("TIMESED") || yes("MICRO")) && push!(out, "ppmain.mod L749 (%TIMESED% YES: pp_micro.mod PRE, TIMES-Micro)")
    (yes("DYNTS") && !isempty(gset_opt(tm.data, "TS_OFF", 4).keys)) &&
        push!(out, "ppmain.mod L742 (%DYNTS% YES with TS_OFF data: RTS(S) is S+NORTS(R,T,S), timslice.mod L33)")
    return out
end

"""
    ppmain_tsattr_symbols(tm) -> Vector{String}

The symbols ppmain.mod L683-797 settles that nothing later in the prelv ->
ppm segment changes (for the layer-1 check at the ppm checkpoint): the
commodity attributes, RS_FR, RTCS_FR, the elastic demand steps, RP_PGFLO and
RPCS_VAR; NCAP_AF and PRC_TS when RP_STS is empty (ppmain.mod L1085-1090);
NCAP_PKCNT when CHP is empty (pp_chp.mod L64); RPC_PKC when %REDUCE% is NO
(otherwise pp_reduce.red L184 drops the processes without capacity) and
STG_SIFT has no data (L1067). Left out: DEM (L945), FLO_PKCOI (L808, L817),
RTPCS_OUT (L1062, L1350), RPC_PKF (pp_reduce.red L185, after its REDDONE
label, so in every run) and the scratch, which the replay checks at L797
(scripts/m13_replay.jl, test/unit/test_m13_ppmain_tsattr.jl).
"""
function ppmain_tsattr_symbols(tm)
    out = ["COM_IE", "COM_FR", "COM_PKFLX", "OBJ_COMNT", "OBJ_COMPD", "COM_ELAST", "COM_BPRICE", "COM_BQTY", "RP_PGFLO",
           "RS_FR", "RTCS_FR", "COM_STEP", "RCJ", "RPCS_VAR"]
    isempty(gset_opt(tm.data, "RP_STS", 2).keys) && append!(out, ["NCAP_AF", "PRC_TS"])
    isempty(gset_opt(tm.data, "CHP", 2).keys) && push!(out, "NCAP_PKCNT")
    # pp_reduce.red L15: $IF %REDUCE% == NO $GOTO REDDONE (a case-sensitive compare)
    (strip(gswitch(tm, "REDUCE", "")) == "NO" && isempty(gparam_opt(tm.data, "STG_SIFT", 5).keys)) && push!(out, "RPC_PKC")
    return out
end

# The timeslice tree as the three macros read it.
struct TsTree
    reg::Set{String}
    all_ts::Vector{String}
    annual::Vector{String}
    below::Dict{NTuple{2,String},Vector{String}}        # (R,A) => S strictly below A (RS_BELOW), GAMS order
    above::Dict{NTuple{2,String},Vector{String}}        # (R,S) => A strictly above S (RS_BELOW), GAMS order
    below1::Dict{NTuple{2,String},Vector{String}}       # (R,A) => S one level below A (RS_BELOW1)
    above1::Dict{NTuple{2,String},Vector{String}}       # (R,S) => A one level above S (RS_BELOW1)
    rs_below::Set{NTuple{3,String}}
    tsmap::Set{NTuple{3,String}}                        # TS_MAP(R,TS,S): TS at or above S
    rs_tree::Set{NTuple{3,String}}
    fin_map::Dict{NTuple{2,String},Vector{String}}      # (R,TS) => finest S with TS_MAP(R,TS,S)
    fin_tree::Dict{NTuple{2,String},Vector{String}}     # (R,TS) => finest S with RS_TREE(R,S,TS)
    group::Dict{NTuple{2,String},Vector{String}}        # (R,TSLVL) => TS_GROUP members
    yrfr::Dict{NTuple{2,String},Float64}
end

function TsTree(tm)
    below, above, below1, above1 = (Dict{NTuple{2,String},Vector{String}}() for _ in 1:4)
    rs_below = gset(tm, "RS_BELOW").members
    for (r, a, s) in gset(tm, "RS_BELOW").keys
        pushat!(below, (r, a), s)
        pushat!(above, (r, s), a)
    end
    for (r, a, s) in gset(tm, "RS_BELOW1").keys
        pushat!(below1, (r, a), s)
        pushat!(above1, (r, s), a)
    end
    finest = gset(tm, "FINEST").members
    fin_map, fin_tree, group = (Dict{NTuple{2,String},Vector{String}}() for _ in 1:3)
    foreach(k -> (k[1], k[3]) in finest && pushat!(fin_map, (k[1], k[2]), k[3]), gset(tm, "TS_MAP").keys)
    foreach(k -> (k[1], k[2]) in finest && pushat!(fin_tree, (k[1], k[3]), k[2]), gset(tm, "RS_TREE").keys)
    foreach(k -> pushat!(group, (k[1], k[2]), k[3]), gset(tm, "TS_GROUP").keys)
    return TsTree(Set(k[1] for k in gset(tm, "REG").keys), [k[1] for k in gset(tm, "ALL_TS").keys],
                  [k[1] for k in gset(tm, "ANNUAL").keys], below, above, below1, above1, rs_below,
                  gset(tm, "TS_MAP").members, gset(tm, "RS_TREE").members, fin_map, fin_tree, group, gvalues(tm, "G_YRFR", 2))
end

tsa_at(arr::Dict{String,Float64}, s) = (v = get(arr, s, nothing); v === nothing ? GZERO : v == 0.0 ? GEPS : GNum(v))
yrfr_at(tr::TsTree, r, s) = gv(tr.yrfr, (r, s))

# SUM(SL$RS_BELOW(R,A,SL), TS_MAP(R,SL,S)*TS_ARRAY(SL)): the values between A (left out) and S (included)
midsum(tr::TsTree, arr, r, a, s) =
    reduce(+, (tsa_at(arr, sl) for sl in get(tr.below, (r, a), String[]) if (r, sl, s) in tr.tsmap); init=GZERO)

# SUM(RS_BELOW(R,A,S)$(TS_ARRAY(A) AND NOT midsum), TS_ARRAY(A) IWGT): the nearest values above S
function inherit(tr::TsTree, arr, r, s, weighted)
    x = GZERO
    for a in get(tr.above, (r, s), String[])
        haskey(arr, a) && iszero(midsum(tr, arr, r, a, s)) || continue
        x += weighted ? tsa_at(arr, a) * yrfr_at(tr, r, s) / yrfr_at(tr, r, a) : tsa_at(arr, a)
    end
    return x
end

"""
    level_fc(tr, arr, r, ts, weighted) -> GNum

pp_lvlfc.mod L40-42 (and pp_lvlpk.mod L36-38, unweighted): the value for
target timeslice `ts` from TS_ARRAY `arr`, summed over the finest timeslices
below it of their own value plus the nearest values above them, weighted by
`G_YRFR(R,S)/G_YRFR(R,TS)`; weighted inheritance (%9 = 1) weights the
inherited values by `G_YRFR(R,S)/G_YRFR(R,A)` instead.

GAMS: pp_lvlfc.mod L40-42, pp_lvlpk.mod L36-38, v4.9.7.
"""
function level_fc(tr::TsTree, arr, r, ts, weighted)
    x = GZERO
    for s in get(tr.fin_map, (r, ts), String[])
        w = weighted ? GNum(1.0) : yrfr_at(tr, r, s) / yrfr_at(tr, r, ts)
        x += w * (tsa_at(arr, s) + inherit(tr, arr, r, s, weighted))
    end
    return x
end

"""
    level_br(tr, arr, r, ts) -> GNum

pp_lvlbr.mod L39-42: the year-fraction weighted average over the finest
timeslices of the subtree of `ts` of their own value plus the nearest values
above them.

GAMS: pp_lvlbr.mod L39-42, v4.9.7.
"""
function level_br(tr::TsTree, arr, r, ts)
    x = GZERO
    foreach(s -> (x += yrfr_at(tr, r, s) * (tsa_at(arr, s) + inherit(tr, arr, r, s, false))), get(tr.fin_tree, (r, ts), String[]))
    return x / yrfr_at(tr, r, ts)
end

"""
    pp_lvlfc!(tm, tr, name, N; sp, years, keyok, targets, qual, take=k->true, weighted=false, p11="") -> (UNCD7, TS_ARRAY or nothing)

pp_lvlfc.mod: the records of attribute `name` (N indexes: R, the year of %7
unless `years` is `nothing`, the %2 and %10 indexes, S at position `sp`, the
%4 indexes) at timeslices outside the targets (%3: `targets(key)` lists them
for the record's R and %2 indexes) are levelled to the targets, for the rows
(the record without S) that `qual` (%8) and `take` (%12) admit. An ANNUAL
value alone is copied to them (weighted by year fraction when `weighted`,
%9 = 1); otherwise each target without a value of its own takes
[`level_fc`](@ref). `keyok` holds the domain filters of the controlling
indexes other than R and the year (G8, G27). `p11` is %11: "N" flags the
rows with values below ANNUAL at year '0' (L25-26) and takes them only;
"0" fills the targets without a value from ANNUAL (L44); any non-empty
value deletes the records off the targets that `take` admits (L45). `s2`
is %6 = S2: the rows of L29 are taken at the targets too (L23). Returns
UNCD7 (L19, L29) and the TS_ARRAY of the last row.

GAMS: pp_lvlfc.mod L19-45, v4.9.7.
"""
function pp_lvlfc!(tm, tr::TsTree, name, N; sp, years, keyok, targets, qual, take=k -> true, weighted=false, p11="", s2=false)
    x = gvalues(tm, name, N)
    yrok(k) = years === nothing || k[2] in years
    rowof(k) = (k[1:sp-1]..., k[sp+1:end]...)
    keyat(row, s) = (row[1:sp-1]..., s, row[sp:end]...)
    istgt(k, s) = s in targets(k)
    if p11 == "N"
        # L26: %1(R,LL--ORD(LL),%2%10,S+STOA(S)%4)$(STOAL(R,S)$%1(R,LL,%2%10,S%4)) = 1
        stoa, stoal = gvalues(tm, "STOA", 1), gvalues(tm, "STOAL", 2)
        tsax = OrdAxis(tr.all_ts)
        lastll = last(gset(tm, "ALLYEAR").keys)[1]                            # LL--ORD(LL) (G31)
        put = Set{NTuple{N,String}}()
        for k in keys(x)
            (k[1] in tr.reg && keyok(k) && !iszero(gv(stoal, (k[1], k[sp])))) || continue
            t = lead(tsax, k[sp], glead(Float64(gv(stoa, (k[sp],)))))
            t === nothing || push!(put, NTuple{N,String}((k[1], lastll, k[3:sp-1]..., t, k[sp+1:end]...)))
        end
        foreach(k -> (x[k] = 1.0), put)
        # L25: TAKE = $%1(R,'0',%2%10,'ANNUAL'%4)
        take = k -> haskey(x, NTuple{N,String}((k[1], "0", k[3:sp-1]..., "ANNUAL", k[sp+1:end]...)))
    end
    # L19: OPTION CLEAR=UNCD7; L29: LOOP((REGY,%2%10,S%4)$((NOT %3(R,%2,S))$%1(REGY,%2%10,S%4)), UNCD7(REGY,%2%10%4%5)$(%8%TAKE%) = YES)
    #   (with %6 = S2, L23 leaves out the (NOT %3(R,%2,S))$)
    rows = Set{NTuple{N - 1,String}}()
    for k in keys(x)
        (k[1] in tr.reg && yrok(k) && keyok(k)) || continue
        ((!s2 && istgt(k, k[sp])) || !qual(k) || !take(k)) && continue
        push!(rows, rowof(k))
    end
    uncd7 = Set{NTuple{7,String}}(NTuple{7,String}((r..., ntuple(_ -> "0", 8 - N)...)) for r in rows)
    arr = nothing
    # L33: LOOP(UNCD7(REGY,%2%10%4%5), TS_ARRAY(S) = %1(REGY,%2%10,S%4); ...)   in GAMS order
    for row in gams_sort!(collect(rows), tm.data)
        r = row[1]
        arr = Dict{String,Float64}(s => x[keyat(row, s)] for s in tr.all_ts if haskey(x, keyat(row, s)))
        tg = targets(keyat(row, "ANNUAL"))
        # L34: IF((NOT SUM(RS_BELOW(R,'ANNUAL',S)$TS_ARRAY(S),1))$TS_ARRAY('ANNUAL'), ...
        if !any(s -> haskey(arr, s), get(tr.below, (r, "ANNUAL"), String[])) && haskey(arr, "ANNUAL")
            # L35: %1(REGY,%2%10,S%4)$%3(R,%2,S) = SUM(ANNUAL(%6),TS_ARRAY(%6)%IWGT%)
            for s in tg
                v = reduce(+, (weighted ? tsa_at(arr, a) * yrfr_at(tr, r, s) / yrfr_at(tr, r, a) : tsa_at(arr, a) for a in tr.annual); init=GZERO)
                gassign!(x, keyat(row, s), v)
            end
        else
            # L38-42: LOOP(%3(R,%2,TS)$(NOT TS_ARRAY(TS)), %1(REGY,%2%10,TS%4) $= ...)
            for ts in tg
                haskey(arr, ts) && continue
                v = level_fc(tr, arr, r, ts, weighted)
                iszero(v) || gassign!(x, keyat(row, ts), v)
            end
        end
    end
    if p11 == "0"
        # L44: %1(REGY,%2%10,S%4)$((NOT %1(REGY,%2%10,S%4))$%3(R,%2,S)) $= %1(REGY,%2%10,'ANNUAL'%4)
        put = Pair{NTuple{N,String},Float64}[]
        for (k, v) in x
            (k[sp] == "ANNUAL" && k[1] in tr.reg && yrok(k) && keyok(k)) || continue
            foreach(s -> haskey(x, keyat(rowof(k), s)) || push!(put, keyat(rowof(k), s) => v), targets(k))
        end
        foreach(((k, v),) -> (x[k] = v), put)
    end
    if p11 != ""
        # L45: %1(R,LL,%2%10,S%4)$((NOT %3(R,%2,S))%TAKE%) = 0   (TAKE read before the statement, G11)
        del = [k for k in keys(x) if k[1] in tr.reg && keyok(k) && !istgt(k, k[sp]) && take(k)]
        foreach(k -> delete!(x, k), del)
    end
    gput!(tm, name, x)
    return uncd7, arr
end

"""
    lvlfc!(tm, tr, name, N, years, qual, comts; extra=[], weighted=false) -> (UNCD7, TS_ARRAY or nothing)

[`pp_lvlfc!`](@ref) with %2 = C and %3 = COM_TS, for the commodity
attributes at ppmain.mod L694-701 (N indexes: R, the year when `years` is
given, C, S, then the `extra` indexes, %4); `qual` is %8.

GAMS: pp_lvlfc.mod L19-42 (%10-%12 empty, %6 = ALL_TS), v4.9.7.
"""
function lvlfc!(tm, tr::TsTree, name, N, years, qual, comts; extra=Set{String}[], weighted=false)
    sp = years === nothing ? 3 : 4
    keyok(k) = all(i -> k[sp+i] in extra[i], eachindex(extra))
    targets(k) = get(comts.of, (k[1], k[sp-1]), String[])
    return pp_lvlfc!(tm, tr, name, N; sp, years, keyok, targets, qual, weighted)
end

"""
    lvlbr!(tm, tr, x, tgt, rtpv, Z, F; name, tsname, mid=0, pad=2, p5=false, p6=true) -> (Z, F, TS_ARRAY or nothing)

pp_lvlbr.mod: the bound attribute `x` (keys R, V, P, `mid` more indexes
(%2), S, BD) levelled to the target timeslices `tgt(key, s)` (%3): a value
above the targets with nothing at or below them is inherited down to them;
a value below a target without one is aggregated to it, with any value
above filling the rest of its subtree; a value both at a target and below
it gives a warning and the lower one is ignored. With `p6` (%6 = 1), LO and
UP at a target that has an FX too are removed. `rtpv` is RTP(R,V,P) at the
model years; `pad` the '0' labels of %4 in UNCD7; `p5` is %5. `x` is
changed in place; Z and F are the scratch scalars as GAMS leaves them.
`name` (%1) and `tsname` (%3) are the attribute's and the target set's
names, for the QA log's group lines.

GAMS: pp_lvlbr.mod L15-55, v4.9.7.
"""
function lvlbr!(tm, tr::TsTree, x::Dict{NTuple{K,String},Float64}, tgt, rtpv, Z, F; name::String, tsname::String,
                mid=0, pad=2, p5=false, p6=true) where {K}
    sp, bp = 4 + mid, 5 + mid
    bdset = Set(k[1] for k in gset(tm, "BD").keys)
    modl = Set(k[1] for k in gset(tm, "MODLYEAR").keys)
    pd = ntuple(_ -> "0", pad)
    urow(k, v, s, b) = NTuple{7,String}((k[1], v, k[3:sp-1]..., s, b, pd...))      # UNCD7(R,V,P%2,S,BD%4)
    kat(k, s) = (k[1:sp-1]..., s, k[bp])
    # L15: OPTION CLEAR=UNCD7
    uncd7 = Set{NTuple{7,String}}()
    # L17: LOOP((RTP(R,V,P)%2,S,BD)$((NOT %3(R,P,%7S))$%1(R,V,P%2,S,BD)), ...)   in GAMS order
    src = gams_sort!([k for k in keys(x) if (k[1], k[2], k[3]) in rtpv && k[bp] in bdset && !tgt(k, k[sp])], tm.data)
    for k in src
        r, v, s, b = k[1], k[2], k[sp], k[bp]
        F, Z = GZERO, GNum(1.0)                                          # L18
        for ts in get(tr.above, (r, s), String[])                       # L19: LOOP(RS_BELOW(R,TS,S)$Z, ...)
            iszero(Z) && break
            if haskey(x, kat(k, ts))                                     # L21-25: a value above, at a target: warning
                F = GNum(1.0)
                if tgt(k, ts)
                    Z = GZERO
                    # L22-25: IF(NOT UNCD7(R,TS,P%2,TS,BD%4), pp_qaput 01 '%1 Bounds conflict: Bound at %3 level and
                    #   below, lower ignored'; PUT QLOG ' WARNING       -     R=',%RL%,' P=',%PL%,' TS=',TS.TL; UNCD7(...) = YES)
                    if !(urow(k, ts, ts, b) in uncd7)
                        pp_qaput!(tm, 1, name * " Bounds conflict: Bound at " * tsname * " level and below, lower ignored")
                        qput!(qalog(tm), " WARNING       -     R=" * qlab12(r) * " P=" * qlab12(k[3]) * " TS=" * ts)
                        push!(uncd7, urow(k, ts, ts, b))
                    end
                end
            elseif tgt(k, ts)                                            # L26: a target above without a value
                Z = GZERO
                push!(uncd7, urow(k, v, ts, b))
            end
        end
        # L27-31: IF(Z, Z = SUM(RS_BELOW(R,S,TS)$%1(..TS..), EPS+(%1(..TS..) > EPS)$%3(R,P,%7TS));
        #   IF(NOT (F+Z), UNCD7(R,V,P%2,S,BD%4) = YES; ELSE Z=Z<1; UNCD7(R,V,P%2,TS,BD%4)$(...) = YES))
        # The IF(Z, ...) opened at L27 closes only at the end of L31 (whatever the indentation says), so
        # a value with a target above it (Z = 0 from L22 or L26) is neither inherited down nor leveled
        # from here (confirmed by replay, crafted case "af": ELCTECOA00 at SD, SN, WD in 2015).
        iszero(Z) && continue
        z = GZERO
        for ts in get(tr.below, (r, s), String[])
            y = get(x, kat(k, ts), nothing)
            y === nothing || (z += GEPS + GNum(y > 0 && tgt(k, ts) ? 1.0 : 0.0))
        end
        Z = z
        if iszero(F + Z)                                                 # L29: inherit down from S
            push!(uncd7, urow(k, v, s, b))
        else                                                             # L31: level the targets below S
            Z = GNum(Z.v < 1 ? 1.0 : 0.0)
            for ts in get(tr.below, (r, s), String[])
                (tgt(k, ts) && (!iszero(Z) || (p5 && !haskey(x, kat(k, ts))))) && push!(uncd7, urow(k, v, ts, b))
            end
        end
    end
    # L35: LOOP(UNCD7(R,V,P%2,TS,BD%4), ...)   (V and BD filter the rows: the warning marks carry a timeslice as V)
    arr = nothing
    rows = gams_sort!([u for u in uncd7 if u[2] in modl && u[bp] in bdset && all(==("0"), u[bp+1:end])], tm.data)
    for u in rows
        k = NTuple{K,String}(u[1:bp])
        ts = k[sp]
        if tgt(k, ts)
            # L38-42: TS_ARRAY(ALL_TS) = %1(R,V,P%2,ALL_TS,BD); %1(R,V,P%2,TS,BD) $= SUM(RS_TREE(FINEST(R,S),TS), ...)/G_YRFR(R,TS)
            arr = Dict{String,Float64}(s => x[kat(k, s)] for s in tr.all_ts if haskey(x, kat(k, s)))
            y = level_br(tr, arr, k[1], ts)
            iszero(y) || gassign!(x, k, y)
        else
            # L44: ELSE Z = %1(R,V,P%2,TS,BD); %1(R,V,P%2,S,BD)$(RS_BELOW(R,TS,S)$%3(R,P,%7S)) = Z
            Z = gv(x, k)
            foreach(s -> tgt(k, s) && gassign!(x, kat(k, s), Z), get(tr.below, (k[1], ts), String[]))
        end
    end
    # L46-55: OPTION CLEAR=UNCD7; IF(%6, PUTGRP = 0; LOOP((R,V,P%2,S)$%1(R,V,P%2,S,'FX'),
    #   IF(%3(R,P,%7S) AND (%1(..,'UP') + %1(..,'LO')), <warning>; UNCD7(R,V,P%2,S,'0'%4) = YES));
    #   IF(PUTGRP, %1(R,V,P%2,S,BDNEQ)$UNCD7(R,V,P%2,S,'0'%4) = 0; OPTION CLEAR=UNCD7))
    if p6
        qa_group!(tm)                                                    # L47: PUTGRP = 0
        conflict = NTuple{K - 1,String}[]
        for k in keys(x)
            (k[bp] == "FX" && k[1] in tr.reg && k[2] in modl && tgt(k, k[sp])) || continue
            g = k[1:sp]
            iszero(gv(x, (g..., "UP")) + gv(x, (g..., "LO"))) || push!(conflict, g)
        end
        # L48-52: in LOOP order, pp_qaput 01 '%1 Bounds conflict: FX + LO/UP at same TS-level, latter ignored';
        #   PUT QLOG ' WARNING       -     R=',%RL%,' Y=',V.TL,' P=',%PL%,' S=',S.TL
        for g in gams_sort!(conflict, tm.data)
            pp_qaput!(tm, 1, name * " Bounds conflict: FX + LO/UP at same TS-level, latter ignored")
            qput!(qalog(tm), " WARNING       -     R=" * qlab12(g[1]) * " Y=" * g[2] * " P=" * qlab12(g[3]) * " S=" * g[sp])
        end
        bdneq = [k[1] for k in gset(tm, "BDNEQ").keys]
        foreach(g -> foreach(b -> delete!(x, (g..., b)), bdneq), conflict)
    end
    return Z, F, arr
end

"""
    ppmain_tsattr!(tm) -> tm

ppmain.mod L683-797 on the state after `ppmain_dflt!`: the commodity
attributes levelled to COM_TS (pp_lvlfc.mod), COM_IE defaulted to 1, COM_FR
completed with the year fractions, summed up the tree and normalised to 1,
RS_FR and RTCS_FR, DEM, the elastic demand signs, steps (COM_STEP) and RCJ;
NCAP_AF levelled to PRC_TS (pp_lvlbr.mod) and defaulted, the timeslices
without one removed from PRC_TS and RPCS_VAR (into RTPCS_OUT); NCAP_PKCNT
levelled and defaulted, RPC_PKF and RPC_PKC (pp_lvlpk.mod).

GAMS: ppmain.mod L683-797, v4.9.7.
"""
function ppmain_tsattr!(tm)
    u = ppmain_tsattr_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    tr = TsTree(tm)
    reg = tr.reg
    tlist = [k[1] for k in gset(tm, "MILESTONYR").keys]
    tmem = Set(tlist)
    modl = Set(k[1] for k in gset(tm, "MODLYEAR").keys)
    dyear = Set(k[1] for k in gset(tm, "DATAYEAR").keys)
    Z, F = gscal(tm, "Z"), gscal(tm, "F")
    rtc = gset(tm, "RTC").members
    rtcT = gams_sort!([k for k in rtc if k[2] in tmem], tm.data)
    rcset = gset(tm, "RC").members
    comts = (set=gset(tm, "COM_TS").members, of=Dict{NTuple{2,String},Vector{String}}())
    foreach(k -> pushat!(comts.of, (k[1], k[2]), k[3]), gset(tm, "COM_TS").keys)
    member(s) = Set(k[1] for k in gset(tm, s).keys)
    costype, cur, bd = member("COSTYPE"), member("CUR"), member("BD")

    # --- L693-701: the commodity attributes levelled to COM_TS --------------------------------------
    # L693: RTC_NET(RTC(R,T,C))$(NOT COM_TSL(R,C,'ANNUAL')) = YES
    comtsl = gset(tm, "COM_TSL").members
    rtc_net = gmembers(tm, "RTC_NET", 3)
    foreach(k -> ((k[1], k[3], "ANNUAL") in comtsl) || push!(rtc_net, k), rtcT)
    ts_array = nothing
    lv(args...; kw...) = ((u7, a) = lvlfc!(tm, tr, args..., comts; kw...); a === nothing || (ts_array = a); u7)
    lv("COM_IE", 4, tmem, k -> (k[1], k[2], k[3]) in rtc)                                   # L694
    lv("COM_FR", 4, tmem, k -> (k[1], k[2], k[3]) in rtc_net; weighted=true)                # L695
    lv("COM_PKFLX", 4, tmem, k -> true)                                                      # L696
    lv("OBJ_COMNT", 6, dyear, k -> (k[1], k[3]) in rcset; extra=[costype, cur])              # L697
    lv("OBJ_COMPD", 6, dyear, k -> (k[1], k[3]) in rcset; extra=[costype, cur])              # L698
    lv("COM_ELAST", 5, dyear, k -> (k[1], k[3]) in rcset; extra=[bd])                        # L699
    lv("COM_BPRICE", 5, dyear, k -> (k[1], k[3]) in rcset; extra=[cur])                      # L700
    uncd7 = lv("COM_BQTY", 3, nothing, k -> (k[1], k[2]) in rcset; weighted=true)           # L701

    # --- L704-732: COM_IE and COM_FR defaults, COM_FR normalised ------------------------------------
    # L704: OPTION RCS < COM_IE, CLEAR=RTC_NET, CLEAR=RP_PGFLO
    cie = gvalues(tm, "COM_IE", 4)
    rcs = project(keys(cie), (1, 3, 4))
    empty!(rtc_net)
    # L705: COM_IE(RTCS_VARC(R,T,C,S))$(NOT RCS(R,C,S)) = 1
    for k in gset(tm, "RTCS_VARC").keys
        (k[1] in reg && k[2] in tmem && !((k[1], k[3], k[4]) in rcs)) && (cie[k] = 1.0)
    end
    gput!(tm, "COM_IE", cie)
    # L708: COM_FR(R,LL,C,ANNUAL)=0; OPTION RCS<COM_FR
    cfr = gvalues(tm, "COM_FR", 4)
    annual = Set(tr.annual)
    filter!(((k, _),) -> !(k[1] in reg && k[4] in annual), cfr)
    rcs = project(keys(cfr), (1, 3, 4))
    # L709: TRACKC(R,C) $= SUM(RCS(R,C,S),1)
    trackc = union(gmembers(tm, "TRACKC", 2), Set((k[1], k[2]) for k in rcs))
    # L710: RCS(TRACKC(R,C),S)$G_YRFR(R,S) = (NOT RCS(R,C,S))
    yr_s = Dict{String,Vector{String}}()
    foreach(k -> pushat!(yr_s, k[1], k[2]), keys(tr.yrfr))
    for (r, c) in trackc, s in get(yr_s, r, String[])
        k = (r, c, s)
        k in rcs ? delete!(rcs, k) : push!(rcs, k)
    end
    # L712: COM_FR(RTC(R,T,C),S)$(RCS(R,C,S)*COM_TS(R,C,S)) = G_YRFR(R,S)
    for (r, t, c) in rtcT, s in get(comts.of, (r, c), String[])
        (r, c, s) in rcs && gassign!(cfr, (r, t, c, s), yrfr_at(tr, r, s))
    end
    # L713-716: COM_FR(RTC(R,T,C),TS)$(RCS(R,C,TS)*TS_GROUP(R,'WEEKLY'|'DAYNITE',TS)) $=
    #   SUM(RS_BELOW1(R,S,TS),COM_FR(R,T,C,S)*(G_YRFR(R,TS)/G_YRFR(R,S)))
    for lvl in ("WEEKLY", "DAYNITE")
        put = Pair{NTuple{4,String},GNum}[]
        for (r, t, c) in rtcT, ts in get(tr.group, (r, lvl), String[])
            (r, c, ts) in rcs || continue
            v = GZERO
            for s in get(tr.above1, (r, ts), String[])
                haskey(cfr, (r, t, c, s)) && (v += gv(cfr, (r, t, c, s)) * (yrfr_at(tr, r, ts) / yrfr_at(tr, r, s)))
            end
            iszero(v) || push!(put, (r, t, c, ts) => v)
        end
        foreach(((k, v),) -> gassign!(cfr, k, v), put)
    end
    # L718-719: COM_FR(R,T,C,TS)$(TRACKC(R,C)$TS_GROUP(R,'WEEKLY'|'SEASON',TS)) $= SUM(RS_BELOW1(R,TS,S),COM_FR(R,T,C,S))
    for lvl in ("WEEKLY", "SEASON")
        put = Pair{NTuple{4,String},GNum}[]
        for (r, c) in trackc, t in tlist, ts in get(tr.group, (r, lvl), String[])
            v = reduce(+, (gv(cfr, (r, t, c, s)) for s in get(tr.below1, (r, ts), String[])); init=GZERO)
            iszero(v) || push!(put, (r, t, c, ts) => v)
        end
        foreach(((k, v),) -> gassign!(cfr, k, v), put)
    end
    # L720: COM_FR(R,T,C,S)$NORTS(R,T,S)=0
    norts = gparam_opt(tm.data, "NORTS", 3).values
    isempty(norts) || filter!(((k, _),) -> !(k[2] in tmem && haskey(norts, (k[1], k[2], k[4]))), cfr)
    # L721: COM_FR(R,T,C,ANNUAL)$TRACKC(R,C) = SUM(RS_BELOW1(R,ANNUAL,S),COM_FR(R,T,C,S))
    for (r, c) in trackc, t in tlist, a in tr.annual
        gassign!(cfr, (r, t, c, a), reduce(+, (gv(cfr, (r, t, c, s)) for s in get(tr.below1, (r, a), String[])); init=GZERO))
    end
    # L723-728: LOOP(TRACKC(R,C), Z=1; LOOP(RTC(R,T,C)$((COM_FR(R,T,C,'ANNUAL') NE 1)$Z),
    #   IF(ABS(COM_FR(R,T,C,'ANNUAL')-1) GT 1E-5, Z=0; <warning>)))
    rtc_by = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> pushat!(rtc_by, (k[1], k[3]), k[2]), rtcT)
    qa_group!(tm)                                                        # L723: PUTGRP = 0
    for (r, c) in gordered(tm, trackc)
        Z = GNum(1.0)
        for t in get(rtc_by, (r, c), String[])
            iszero(Z) && break
            a = gv(cfr, (r, t, c, "ANNUAL")).v
            if a != 1 && abs(a - 1) > 1e-5
                Z = GZERO
                # L726-728: pp_qaput 01 'COM_FR does not sum to unity (T=first year)';
                #   PUT QLOG ' WARNING       - Normalized to 1,   R=',%RL%,' C=',%CL%,' (T=',T.TL:0,')'
                pp_qaput!(tm, 1, "COM_FR does not sum to unity (T=first year)")
                qput!(qalog(tm), " WARNING       - Normalized to 1,   R=" * qlab12(r) * " C=" * qlab12(c) * " (T=" * t * ")")
            end
        end
    end
    # L729: COM_FR(RTC(R,T,C),S)$((COM_FR(RTC,'ANNUAL') NE 1)$TRACKC(R,C)) = COM_FR(RTC,S) / COM_FR(RTC,'ANNUAL')
    by_rtc = Dict{NTuple{3,String},Vector{String}}()
    foreach(k -> pushat!(by_rtc, (k[1], k[2], k[3]), k[4]), keys(cfr))
    for (r, t, c) in rtcT
        (r, c) in trackc || continue
        a = gv(cfr, (r, t, c, "ANNUAL"))
        a.v == 1 && continue
        # GAMS divides for every S, records or not, so an ANNUAL of 0 (or EPS) stops the run (G48)
        a.v == 0 && throw(DomainError(a, "ppmain.mod L729: COM_FR($r,$t,$c,'ANNUAL') is $a (GAMS: division by zero)"))
        foreach(s -> gassign!(cfr, (r, t, c, s), gv(cfr, (r, t, c, s)) / a), get(by_rtc, (r, t, c), String[]))
    end
    # L730-731: RP_PGFLO(RP(R,P))$=SUM(RPC_PG(RP,C)$TRACKC(R,C),1); RP_PGFLO(RP)$SUM(RPS_S1(PRC_TS(RP,S)),1)=NO
    rp = gset(tm, "RP").members
    prc_ts = gmembers(tm, "PRC_TS", 3)
    rp_pgflo = Set{NTuple{2,String}}((k[1], k[2]) for k in gset(tm, "RPC_PG").keys if (k[1], k[2]) in rp && (k[1], k[3]) in trackc)
    for k in gset(tm, "RPS_S1").keys
        (k in prc_ts && (k[1], k[2]) in rp) && delete!(rp_pgflo, (k[1], k[2]))
    end
    gput!(tm, "RP_PGFLO", rp_pgflo)
    # L732: OPTION CLEAR=RCS, CLEAR=TRACKC

    # --- L737-742: RS_FR, RTCS_FR, COM_FR at the commodity levels ----------------------------------
    # L739: RS_FR(RS_TREE(R,S,TS)) = 1$TS_MAP(R,S,TS) + (G_YRFR(R,S)/G_YRFR(R,TS))$RS_BELOW(R,TS,S)
    rsfr = gvalues(tm, "RS_FR", 3)
    for (r, s, ts) in gset(tm, "RS_TREE").keys
        r in reg || continue
        v = GNum((r, s, ts) in tr.tsmap ? 1.0 : 0.0)
        (r, ts, s) in tr.rs_below && (v += yrfr_at(tr, r, s) / yrfr_at(tr, r, ts))
        gassign!(rsfr, (r, s, ts), v)
    end
    gput!(tm, "RS_FR", rsfr)
    # L740-741: RTCS_FR(RTC(R,T,C),S,TS)$(RS_BELOW(R,TS,S)$COM_FR(RTC,TS)) =
    #   ((COM_FR(RTC,S)/COM_FR(RTC,TS))$(COM_FR(RTC,TS)>0))/RS_FR(R,S,TS)-1      (%MX% is empty)
    rtcsfr = gvalues(tm, "RTCS_FR", 5)
    by_rtc = Dict{NTuple{3,String},Vector{String}}()
    foreach(k -> pushat!(by_rtc, (k[1], k[2], k[3]), k[4]), keys(cfr))
    for (r, t, c) in rtcT, ts in get(by_rtc, (r, t, c), String[])
        a = gv(cfr, (r, t, c, ts))
        for s in get(tr.below, (r, ts), String[])
            q = a.v > 0 ? gv(cfr, (r, t, c, s)) / a : GZERO
            gassign!(rtcsfr, (r, t, c, s, ts), q / gv(rsfr, (r, s, ts)) - GNum(1.0))
        end
    end
    gput!(tm, "RTCS_FR", rtcsfr)
    # L742: COM_FR(RTC(R,T,C),RTS(S))$((NOT COM_FR(RTC,S))$RCS_COMTS(R,C,S)) = G_YRFR(R,S)    (RTS(S) is S)
    rcs_comts = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> pushat!(rcs_comts, (k[1], k[2]), k[3]), gset(tm, "RCS_COMTS").keys)
    for (r, t, c) in rtcT, s in get(rcs_comts, (r, c), String[])
        haskey(cfr, (r, t, c, s)) || gassign!(cfr, (r, t, c, s), yrfr_at(tr, r, s))
    end
    gput!(tm, "COM_FR", cfr)

    # --- L747-754: elastic demands ------------------------------------------------------------------
    # L747: OPTION DEM < COM_PROJ
    gput!(tm, "DEM", project(gparam_opt(tm.data, "COM_PROJ", 3).keys, (1, 3)))
    # L751-752: COM_ELAST(R,T,C,S,BDNEQ(BD))$COM_ELAST(R,T,C,S,BD) =
    #   -ABS(COM_ELAST(R,T,C,S,BD)-1+1)$SUM(RDCUR(R,CUR),COM_BPRICE(R,T,C,S,CUR)*COM_VOC(R,T,C,BD)>0)
    cel = gvalues(tm, "COM_ELAST", 5)
    bdneq = Set(k[1] for k in gset(tm, "BDNEQ").keys)
    bprice, voc = gparam_opt(tm.data, "COM_BPRICE", 5), gparam_opt(tm.data, "COM_VOC", 4)
    rdcur = Dict{String,Vector{String}}()
    foreach(k -> pushat!(rdcur, k[1], k[2]), gset(tm, "RDCUR").keys)
    for k in collect(keys(cel))
        (k[1] in reg && k[2] in tmem && k[5] in bdneq) || continue
        (r, t, c, s, b) = k
        ok = any(cu -> (gv(bprice, (r, t, c, s, cu)) * gv(voc, (r, t, c, b))).v > 0, get(rdcur, r, String[]))
        gassign!(cel, k, ok ? -abs(gv(cel, k) - GNum(1.0) + GNum(1.0)) : GZERO)
    end
    gput!(tm, "COM_ELAST", cel)
    # L753: OPTION RC_AGP < COM_ELAST; COM_STEP(RC_AGP(RC,BDNEQ))$(NOT COM_STEP(RC,BDNEQ)) = MAX(1,COM_STEP(RC,'FX'))
    rc_agp = project(keys(cel), (1, 3, 5))
    cstep = gvalues(tm, "COM_STEP", 3)
    for (r, c, l) in rc_agp
        ((r, c) in rcset && l in bdneq && !haskey(cstep, (r, c, l))) || continue
        gassign!(cstep, (r, c, l), gmax(GNum(1.0), gv(cstep, (r, c, "FX"))))
    end
    gput!(tm, "COM_STEP", cstep)
    # L754: RCJ(RC,J,BD)$((ORD(J) <= COM_STEP(RC,BD))$RC_AGP(RC,BD)) = 1; OPTION CLEAR=RC_AGP
    rcj = gmembers(tm, "RCJ", 4)
    jlab = [k[1] for k in gset(tm, "J").keys]
    for (r, c, l) in rc_agp
        ((r, c) in rcset && l in bd) || continue
        n = gv(cstep, (r, c, l)).v
        for (i, j) in enumerate(jlab)
            i <= n || break
            push!(rcj, (r, c, j, l))
        end
    end
    gput!(tm, "RCJ", rcj)

    # --- L765-785: availability factors -------------------------------------------------------------
    rtpV = gams_sort!([k for k in gset(tm, "RTP").members if k[2] in modl], tm.data)
    rtpv = Set(rtpV)
    naf = gvalues(tm, "NCAP_AF", 5)
    afs = gparam_opt(tm.data, "NCAP_AFS", 5).values
    # L766: RTPS_BD(RTP(R,V,P),S,BD)$PRC_TS(R,P,S) $= NCAP_AFS(RTP,S,BD)$(NOT NCAP_AF(RTP,S,BD))
    rtps_bd = gmembers(tm, "RTPS_BD", 5)
    for k in keys(afs)
        ((k[1], k[2], k[3]) in rtpv && k[5] in bd && (k[1], k[3], k[4]) in prc_ts && !haskey(naf, k)) && push!(rtps_bd, k)
    end
    # L767: $BATINCLUDE pp_lvlbr.mod NCAP_AF '' PRC_TS ",'0','0'" 0 1
    Z, F, arr_br = lvlbr!(tm, tr, naf, (k, s) -> (k[1], k[3], s) in prc_ts, rtpv, Z, F; name="NCAP_AF", tsname="PRC_TS")
    arr_br === nothing || (ts_array = arr_br)
    uncd7 = Set{NTuple{7,String}}()
    # L768: NCAP_AF(RTPS_BD)$NCAP_AF(RTPS_BD) $= NCAP_AFS(RTPS_BD)
    foreach(k -> (haskey(naf, k) && haskey(afs, k)) && (naf[k] = afs[k]), rtps_bd)
    # L771-772: OPTION CLEAR=RXX,CLEAR=RTPS_BD;
    #   RTPS_BD(R,LL--(ORD(LL)*(NCAP_AF(R,LL,P,S,BD) GT 0)),P,S,BDUPX(BD))$(V(LL)$NCAP_AF(R,LL,P,S,BD))=YES
    lastll = last(gset(tm, "ALLYEAR").keys)[1]                          # LL--ORD(LL) (G31)
    bdupx = Set(k[1] for k in gset(tm, "BDUPX").keys)
    rtps_bd = Set{NTuple{5,String}}()
    for (k, y) in naf
        (k[1] in reg && k[2] in modl && k[5] in bdupx) && push!(rtps_bd, (k[1], y > 0 ? lastll : k[2], k[3], k[4], k[5]))
    end
    # L773: OPTION TRACKP < RTPS_BD; RXX(PRC_TS(TRACKP(R,P),S))$=SUM(RTPS_BD(R,LASTLL,P,S,BDUPX),1)
    trackp = project(rtps_bd, (1, 3))
    lastset = Set(k[1] for k in gset(tm, "LASTLL").keys)
    pos = Set((k[1], k[3], k[4]) for k in rtps_bd if k[2] in lastset && k[5] in bdupx)
    rxx = Set{NTuple{3,String}}(k for k in prc_ts if (k[1], k[2]) in trackp && k in pos)
    # L775: NCAP_AF(RTP(R,V,P),S,'UP')$(PRC_TS(R,P,S)$(NOT TRACKP(R,P))) = 1.0
    ts_of = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> pushat!(ts_of, (k[1], k[2]), k[3]), gams_sort!(collect(prc_ts), tm.data))
    for (r, v, p) in rtpV
        (r, p) in trackp && continue
        foreach(s -> (naf[(r, v, p, s, "UP")] = 1.0), get(ts_of, (r, p), String[]))
    end
    # L776: PRC_TS2(PRC_TS(TRACKP(R,P),S)) = (NOT RXX(R,P,S))
    prc_ts2 = gmembers(tm, "PRC_TS2", 3)
    for k in prc_ts
        (k[1], k[2]) in trackp || continue
        k in rxx ? delete!(prc_ts2, k) : push!(prc_ts2, k)
    end
    # L777: NCAP_AF(RTP(R,V,P),S,'UP')$(PRC_TS2(R,P,S)$RP_STG(R,P)) = EPS; L778: PRC_TS2(RP_STG,S) = NO
    rp_stg = gset_opt(tm.data, "RP_STG", 2).members
    ts2_of = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> pushat!(ts2_of, (k[1], k[2]), k[3]), prc_ts2)
    for (r, v, p) in rtpV
        (r, p) in rp_stg && foreach(s -> (naf[(r, v, p, s, "UP")] = 0.0), get(ts2_of, (r, p), String[]))
    end
    filter!(k -> !((k[1], k[2]) in rp_stg), prc_ts2)
    gput!(tm, "NCAP_AF", naf)
    # L781: PRC_TS2(RP(R,P),S) $= SUM(RS_BELOW(R,TS,S)$PRC_TS2(RP,TS),1)
    add = [(k[1], k[2], s) for k in prc_ts2 if (k[1], k[2]) in rp for s in get(tr.below, (k[1], k[3]), String[])]
    union!(prc_ts2, add)
    # L782-784: PRC_TS(PRC_TS2) = NO; RPCS_VAR(RPCS_VAR(R,P,C,S))$PRC_TS2(R,P,S) = NO;
    #   RTPCS_OUT(RTPC(R,T,P,C),S)$PRC_TS2(R,P,S) = YES
    setdiff!(prc_ts, prc_ts2)
    gput!(tm, "PRC_TS", prc_ts)
    rpcs_var = gmembers(tm, "RPCS_VAR", 4)
    filter!(k -> !((k[1], k[2], k[4]) in prc_ts2), rpcs_var)
    gput!(tm, "RPCS_VAR", rpcs_var)
    rtpcs_out = gmembers(tm, "RTPCS_OUT", 5)
    ts2_of = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> pushat!(ts2_of, (k[1], k[2]), k[3]), prc_ts2)
    for (r, t, p, c) in gset(tm, "RTPC").keys
        t in tmem && foreach(s -> push!(rtpcs_out, (r, t, p, c, s)), get(ts2_of, (r, p), String[]))
    end
    gput!(tm, "RTPCS_OUT", rtpcs_out)
    # L785: OPTION CLEAR=PRC_TS2,CLEAR=TRACKP,CLEAR=RTPS_BD
    gput!(tm, "RXX", rxx)

    # --- L797: $BATINCLUDE pp_lvlpk.mod 1.0 ---------------------------------------------------------
    F, arr_pk = lvlpk!(tm, tr, 1.0, F, rtpV, tmem, modl)
    arr_pk === nothing || (ts_array = arr_pk)

    # the work sets as GAMS leaves them (cleared at L704, L732, L754, L785 and pp_lvlpk.mod L55)
    for (n, N) in (("RTC_NET", 3), ("RCS", 3), ("TRACKC", 2), ("RC_AGP", 3), ("PRC_TS2", 3), ("TRACKP", 2), ("RTPS_BD", 5),
                   ("TRACKPC", 3), ("RTP_GRP", 5), ("RTP_ISHPR", 3))
        gput!(tm, n, Set{NTuple{N,String}}())
    end
    gput!(tm, "UNCD7", uncd7)
    ts_array === nothing || gput!(tm, "TS_ARRAY", Dict{Tuple{String},Float64}((s,) => v for (s, v) in ts_array))
    gput_gnum!(tm, "Z", Z)
    gput_gnum!(tm, "F", F)
    return tm
end

"""
    lvlpk!(tm, tr, dflt, F, rtpV, tmem, modl) -> (F, TS_ARRAY or nothing)

pp_lvlpk.mod with %1 = `dflt`: NCAP_PKCNT of the processes producing (or
importing) a peak commodity levelled to that commodity's timeslices
(default `dflt` at ANNUAL), FLO_PKCOI cleared for PRC_PKNO, RPC_PKF (EPS
for PRC_PKAF, else 1), NCAP_PKCNT defaulted to 1 or, for PRC_PKAF, to the
largest NCAP_AF, and RPC_PKC (the peak contribution by capacity).

GAMS: pp_lvlpk.mod L12-55, v4.9.7.
"""
function lvlpk!(tm, tr::TsTree, dflt, F, rtpV, tmem, modl)
    reg = tr.reg
    rtpv = Set(rtpV)
    by(itr, f, g) = (d = Dict{Any,Vector{Any}}(); foreach(k -> pushat!(d, f(k), g(k)), itr); d)
    # L16: LOOP(COM_PKTS(R,CG,S), RCS(COM_TS(R,C,TS))$(RS_TREE(R,S,TS)$COM_GMAP(R,CG,C)) = YES)
    gmap = by(gset(tm, "COM_GMAP").keys, k -> (k[1], k[2]), k -> k[3])
    comts_of = by(gset(tm, "COM_TS").keys, k -> (k[1], k[2]), k -> k[3])
    rcs = Set{NTuple{3,String}}()
    for (r, cg, s) in gset_opt(tm.data, "COM_PKTS", 3).keys
        r in reg || continue
        for c in get(gmap, (r, cg), Any[]), ts in get(comts_of, (r, c), Any[])
            (r, s, ts) in tr.rs_tree && push!(rcs, (r, c, ts))
        end
    end
    # L17: TRACKC(R,C) $= SUM(RCS(R,C,S),1)
    trackc = Set((k[1], k[2]) for k in rcs)
    rcs_of = by(gams_sort!(collect(rcs), tm.data), k -> (k[1], k[2]), k -> k[3])
    # L20: OPTION RTP_ISHPR < NCAP_PKCNT
    pk = gvalues(tm, "NCAP_PKCNT", 4)
    ishpr = project(keys(pk), (1, 2, 3))
    # L21: FLO_PKCOI(RTP(R,T,P),C,S)$(TRACKC(R,C)$PRC_PKNO(R,P)) = 0
    pkno = gset_opt(tm.data, "PRC_PKNO", 2).members
    rtp = gset(tm, "RTP").members
    pkcoi = gvalues(tm, "FLO_PKCOI", 5)
    filter!(((k, _),) -> !((k[1], k[2], k[3]) in rtp && k[2] in tmem && (k[1], k[4]) in trackc && (k[1], k[3]) in pkno), pkcoi)
    gput!(tm, "FLO_PKCOI", pkcoi)
    # L22: TRACKPC(RPC(R,P,C))$((TOP(RPC,'OUT')+RPC_IRE(RPC,'IMP'))$TRACKC(R,C)) = YES
    top, ire = gset(tm, "TOP").members, gset_opt(tm.data, "RPC_IRE", 4).members
    rpc = gset(tm, "RPC").keys
    trackpc = gmembers(tm, "TRACKPC", 3)
    for (r, p, c) in rpc
        ((r, c) in trackc && ((r, p, c, "OUT") in top || (r, p, c, "IMP") in ire)) && push!(trackpc, (r, p, c))
    end
    # L23: RTP_GRP(RTP_ISHPR(RTP(R,V,P)),C,IO(IPS))$(SUM(RCS(R,C,S)$(NOT NCAP_PKCNT(R,V,P,S)),1)$TRACKPC(R,P,C)) = YES
    ios = [k[1] for k in gset(tm, "IO").keys if (k[1],) in gset(tm, "IPS").members]
    tpc_of = by(trackpc, k -> (k[1], k[2]), k -> k[3])
    rtp_grp = gmembers(tm, "RTP_GRP", 5)
    for (r, v, p) in ishpr
        (r, v, p) in rtpv || continue
        for c in get(tpc_of, (r, p), Any[])
            any(s -> !haskey(pk, (r, v, p, s)), get(rcs_of, (r, c), Any[])) || continue
            foreach(io -> push!(rtp_grp, (r, v, p, c, io)), ios)
        end
    end
    # L27-38: LOOP(RTP_GRP(R,V,P,C,IO), TS_ARRAY(S) = NCAP_PKCNT(R,V,P,S); F = TS_ARRAY('ANNUAL'); ...)   in GAMS order
    com = Set(k[1] for k in gset(tm, "COM").keys)
    ioset = Set(k[1] for k in gset(tm, "IO").keys)
    arr = nothing
    for (r, v, p, c, io) in gams_sort!([k for k in rtp_grp if k[1] in reg && k[2] in modl && k[4] in com && k[5] in ioset], tm.data)
        arr = Dict{String,Float64}(s => pk[(r, v, p, s)] for s in tr.all_ts if haskey(pk, (r, v, p, s)))
        F = tsa_at(arr, "ANNUAL")
        if !any(a -> any(s -> haskey(arr, s), get(tr.below, (r, a), String[])), tr.annual) && !iszero(F)
            # L29: NCAP_PKCNT(R,V,P,S)$RCS(R,C,S) = F
            foreach(s -> gassign!(pk, (r, v, p, s), F), get(rcs_of, (r, c), Any[]))
        else
            # L32: IF(NOT F,TS_ARRAY(ANNUAL) = %1); L34-38: LOOP(RCS(R,C,TS)$(NOT TS_ARRAY(TS)), NCAP_PKCNT(R,V,P,TS) $= ...)
            iszero(F) && foreach(a -> (arr[a] = Float64(dflt)), tr.annual)
            for ts in get(rcs_of, (r, c), Any[])
                haskey(arr, ts) && continue
                y = level_fc(tr, arr, r, ts, false)
                iszero(y) || gassign!(pk, (r, v, p, ts), y)
            end
        end
    end
    # L42: TRACKP(PRC_PKAF(RP))=NOT PRC_PKNO(RP); TRACKPC(PRC_PKNO(RP),C) = NO
    rp = gset(tm, "RP").members
    pkaf = gset_opt(tm.data, "PRC_PKAF", 2).members
    trackp = Set{NTuple{2,String}}(k for k in pkaf if k in rp && !(k in pkno))
    filter!(k -> !((k[1], k[2]) in pkno && (k[1], k[2]) in rp), trackpc)
    # L43: RPC_PKF(RPC(RP_FLO(R,P),C))$TRACKC(R,C) = EPS**1$TRACKP(R,P)
    rp_flo = gset(tm, "RP_FLO").members
    pkf = gvalues(tm, "RPC_PKF", 3)
    for (r, p, c) in rpc
        ((r, p) in rp_flo && (r, c) in trackc) && gassign!(pkf, (r, p, c), gpow(GEPS, GNum((r, p) in trackp ? 1.0 : 0.0)))
    end
    gput!(tm, "RPC_PKF", pkf)
    # L45: LOOP(TRACKPC(R,P,C),PRC_TS2(R,P,S)$((NOT SUM(RTP(R,V,P),NCAP_PKCNT(RTP,S)))$RCS(R,C,S)) = YES)
    vs_of = by(rtpV, k -> (k[1], k[3]), k -> k[2])
    prc_ts2 = Set{NTuple{3,String}}()
    for (r, p, c) in trackpc, s in get(rcs_of, (r, c), Any[])
        iszero(reduce(+, (gv(pk, (r, v, p, s)) for v in get(vs_of, (r, p), Any[])); init=GZERO)) && push!(prc_ts2, (r, p, s))
    end
    # L46: NCAP_PKCNT(R,YEAR,P,S)$(NCAP_PKCNT(R,YEAR,P,S)=0) = 0
    filter!(((k, y),) -> !(k[1] in reg && y == 0.0), pk)
    # L47-48: NCAP_PKCNT(RTP(R,V,P),S)$PRC_TS2(R,P,S) = 1$(NOT PRC_PKAF(R,P)) +
    #   SUM(PRC_TS(R,P,TS)$RS_TREE(R,S,TS),SMAX(BD,NCAP_AF(RTP,TS,BD))*(1+(G_YRFR(R,TS)/G_YRFR(R,S)-1)$RS_BELOW(R,S,TS)))$PRC_PKAF(R,P)
    naf = gparam(tm, "NCAP_AF").values
    bds = [k[1] for k in gset(tm, "BD").keys]
    pts_of = by(gset(tm, "PRC_TS").keys, k -> (k[1], k[2]), k -> k[3])
    ts2_of = by(prc_ts2, k -> (k[1], k[2]), k -> k[3])
    for (r, v, p) in rtpV, s in get(ts2_of, (r, p), Any[])
        y = GNum((r, p) in pkaf ? 0.0 : 1.0)
        if (r, p) in pkaf
            sm = GZERO
            for ts in get(pts_of, (r, p), Any[])
                (r, s, ts) in tr.rs_tree || continue
                mx = reduce(gmax, (gv(naf, (r, v, p, ts, b)) for b in bds))
                w = (r, s, ts) in tr.rs_below ? yrfr_at(tr, r, ts) / yrfr_at(tr, r, s) - GNum(1.0) : GZERO
                sm += mx * (GNum(1.0) + w)
            end
            y += sm
        end
        gassign!(pk, (r, v, p, s), y)
    end
    gput!(tm, "NCAP_PKCNT", pk)
    # L51: RPC_PKC(TRACKPC(RPC_ACT(TRACKP(RP_STD),C)))=YES
    pkc = gmembers(tm, "RPC_PKC", 3)
    rpc_act, rp_std = gset(tm, "RPC_ACT").members, gset(tm, "RP_STD").members
    foreach(k -> (k in rpc_act && (k[1], k[2]) in trackp && (k[1], k[2]) in rp_std) && push!(pkc, k), trackpc)
    # L52: TRACKPC(RP,C)$(NOT RPC_PG(RP,C)*RP_FLO(RP))=NO
    rpc_pg = gset(tm, "RPC_PG").members
    filter!(k -> !((k[1], k[2]) in rp) || (k in rpc_pg && (k[1], k[2]) in rp_flo), trackpc)
    # L53: RPC_PKC(TRACKPC(RP_PGACT(RP),C))$(RP_PG(RP,C)+TRACKP(RP))=YES
    pgact, rp_pg = gset(tm, "RP_PGACT").members, gset(tm, "RP_PG").members
    foreach(k -> ((k[1], k[2]) in pgact && (k[1], k[2]) in rp && (k in rp_pg || (k[1], k[2]) in trackp)) && push!(pkc, k), trackpc)
    # L54: LOOP(NRG_TMAP(R,'ELC',C)$TRACKC(R,C),RPC_PKC(TRACKPC(TRACKP(R,P),C))=YES;TRACKP(R,P)$TRACKPC(R,P,C)=NO)
    for (r, typ, c) in gset(tm, "NRG_TMAP").keys
        (r in reg && typ == "ELC" && (r, c) in trackc) || continue
        ps = [p for (r2, p) in trackp if r2 == r && (r, p, c) in trackpc]
        foreach(p -> push!(pkc, (r, p, c)), ps)
        foreach(p -> delete!(trackp, (r, p)), ps)
    end
    gput!(tm, "RPC_PKC", pkc)
    # L55: OPTION CLEAR=TRACKP,CLEAR=TRACKC,CLEAR=TRACKPC,CLEAR=RTP_GRP,CLEAR=RCS,CLEAR=RTP_ISHPR,CLEAR=PRC_TS2  (by the caller)
    return F, arr
end
