# M1.3 (4), (5): the OFF-range macro, $BATINCLUDEd by timslice.mod L36
# (TS_OFF) and ppmain.mod L237 (PRC_NOFF; `ppmain_rtp!`), and later by
# ppmain.mod L360 (COM_OFF), L562 (PRC_AOFF) and L578 (PRC_FOFF).
#
# GAMS: pp_off.mod L1-23, v4.9.7. The macro's arguments are the OFF set (%1),
# its index (%2), a control condition (%3), the statement it opens (%4) and
# the value it assigns (%5); TIMES.jl splits it into the years switched off
# (`pp_off_fil`, L17-20) and the periods that L22's condition selects
# (`pp_off_periods`), and each caller makes its own assignment. The macro's
# scratch is left as GAMS leaves it (`PPOffScratch`, `pp_off_keep!`): FIL of
# the last call and STARTOFF, ENDOFF of the last range, the callers looping
# in GAMS order; a checkpoint dump holds them.

"""
    PPOffScratch()

What pp_off.mod leaves in its scratch over one caller's loop: FIL of the last
call (L17 clears it at every call) and STARTOFF, ENDOFF of the last range any
call went through (L18), `nothing` until one did.
"""
mutable struct PPOffScratch
    called::Bool
    fil::Set{Tuple{String}}
    startoff::Union{Nothing,Int}
    endoff::Union{Nothing,Int}
end
PPOffScratch() = PPOffScratch(false, Set{Tuple{String}}(), nothing, nothing)

"""
    pp_off_keep!(tm, sc::PPOffScratch) -> tm

Store the scratch a caller's loop left: FIL if pp_off.mod ran at all, and
STARTOFF, ENDOFF if it went through a range.

GAMS: pp_off.mod L17-20, v4.9.7.
"""
function pp_off_keep!(tm, sc::PPOffScratch)
    sc.called && gput!(tm, "FIL", sc.fil)
    sc.startoff === nothing || gput_gnum!(tm, "STARTOFF", GNum(sc.startoff))
    sc.endoff === nothing || gput_gnum!(tm, "ENDOFF", GNum(sc.endoff))
    return tm
end

"""
    pp_off_fil(tm, ranges[, sc::PPOffScratch]) -> Set{Tuple{String}}

FIL for the OFF ranges `ranges`, pairs (BOHYEAR, EOHYEAR) of one
`%1(R,%2,BOHYEAR,EOHYEAR)` record each: the EOHYEARS from the start year to
the end year inclusive, 'BOH' and 'EOH' open-ended. The orders are those of
the BOHYEAR and EOHYEAR sets ('BOH' first, then the years; EOHYEAR adds
'EOH' last), against ORD on ALLYEAR, as the source comment says ("BOHYEAR/
EOHYEAR being ordered 1 higher than ALLYEAR"). With `sc`, the call's FIL and
its last range's STARTOFF and ENDOFF are noted there (`pp_off_keep!`); the
ranges are then in GAMS order.

GAMS: pp_off.mod L17-20, v4.9.7.
"""
function pp_off_fil(tm, ranges, sc::Union{Nothing,PPOffScratch}=nothing)
    boh, eoh, ally = OrdAxis(tm, "BOHYEAR"), OrdAxis(tm, "EOHYEAR"), OrdAxis(tm, "ALLYEAR")
    eohyears = [k[1] for k in gset(tm, "EOHYEARS").keys]
    # L17: OPTION CLEAR=FIL
    fil = Set{Tuple{String}}()
    for (b, e) in ranges
        # L18: STARTOFF=ORD(BOHYEAR)-2; ENDOFF=ORD(EOHYEAR)
        startoff, endoff = boh.pos[b] - 2, eoh.pos[e]
        # L20: FIL(EOHYEARS(LL))$((ORD(LL) > STARTOFF)$(ORD(LL) < ENDOFF)) = YES
        foreach(ll -> startoff < ally.pos[ll] < endoff && push!(fil, (ll,)), eohyears)
        sc === nothing || (sc.startoff = startoff; sc.endoff = endoff)
    end
    sc === nothing || (sc.called = true; sc.fil = fil)
    return fil
end

"""
    pp_off_periods(tm, fil, tlist) -> Vector{String}

The periods of `tlist` (T, or the subset the caller's statement runs over)
that L22's condition selects: FIL(T) and
`SUM(PERIODYR(T,FIL),1)/D(T) GE G_OFFTHD(T)` (EPS and a missing G_OFFTHD are 0).

GAMS: pp_off.mod L22, v4.9.7.
"""
function pp_off_periods(tm, fil, tlist)
    D, offthd = gparam(tm, "D"), gparam_opt(tm.data, "G_OFFTHD", 1)
    years = Dict{String,Int}()
    foreach(((t, y),) -> (y,) in fil && (years[t] = get(years, t, 0) + 1), gset(tm, "PERIODYR").keys)
    return [t for t in tlist if (t,) in fil && get(years, t, 0) / Float64(gv(D, (t,))) >= Float64(gv(offthd, (t,)))]
end
