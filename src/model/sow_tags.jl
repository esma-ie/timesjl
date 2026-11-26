# The SOW tags of the stochastic extension (M1.3 change 73).
#
# TIMES writes every equation and bound file once, for both modes, through
# text macros that maindrv.mod sets after preprocessing:
#
#     $   IF %STAGES%==YES $%SW_TAGS%          (maindrv.mod L66)
#     $   IF NOT %STAGES%==YES $%SW_NOTAGS%    (maindrv.mod L67)
#
# SW_NOTAGS (setglobs.gms L348) and SW_TAGS (stages.stc L12-15), v4.9.7:
#
#     tag      deterministic   stochastic (STAGES YES)
#     %EQ%     EQ              ES
#     %VAR%    VAR             VAS
#     %SOW%    (nothing)       ,SOW
#     %SWT%    (nothing)       ,SW_T(T,SOW)
#     %SWS%    (nothing)       ,W)
#     %VART%   VAR             SUM(SW_TSW(SOW,T,W),VAS
#     %VARV%   VAR             SUM(SW_TSW(SOW,V,W),VAS
#     %VARM%   VAR             SUM(SW_TSW(SOW,MODLYEAR,W),VAS
#     %VARTT%  VAR             SUM(SW_TSW(SOW,TT,W),VAS        (stages.stc L13)
#     %SWX%    ,'1'            ,SOW                            (setglobs.gms L365; stages.stc L15)
#     %SWTX%   (nothing)       SW_T(T,SOW)$                    (stages.stc L15)
#     %SWD%    (nothing)       ,WW                             (stages.stc L12, L14; nothing under SENSIS, L16)
#     %SWTD%   (nothing)       ,T,WW                           (stages.stc L12)
#     %SWSW%   (nothing)       SW_TSW(SOW,T,WW),               (stages.stc L13)
#
# %SWD%, %SWTD% and %SWSW% have no fixed meaning: the files that use them set
# them again for their own purpose (bnd_act.mod L18, bnd_flo.mod L35,
# eqbndcst.mod L83, eqcumflo.mod L16 and L26, eqobjvar.mod L25, equcwrap.mod
# L16-17, equserco.mod L29 and L55), as some do %SOW% and %SWT%. Each builder
# says so where its GAMS file does; the stochastic side of those lines is
# change 74's.
#
# So a row `%EQ%_X(R,T,... %SWT%)` is EQ_X(R,T,...) in a deterministic run and
# ES_X(R,T,...,T,SOW) for every SOW with SW_T(T,SOW) in a stochastic one; a
# term `%VAR%_ACT(R,V,T,P,S %SOW%)` reads VAS_ACT(R,V,T,P,S,SOW), the row's own
# SOW; and `%VARV%_NCAP(R,V,P %SWS%)` reads SUM(SW_TSW(SOW,V,W),VAS_NCAP(R,V,P,W)),
# the column of the SOW whose node SOW shares at period V.
#
# TIMES.jl keeps one `SowTags` per model. The equation and bound builders ask
# it, where their GAMS file has a tag, for the rows' SOWs (`sw_rows` for
# %SWT% and %SWTX%, `sow_rows` for a bare %SOW%), the row's name and index
# (`eqtag`; `swt`, `sowkey`, `swx`), the columns of a term (`addterm!`, with
# `at` for %VART%, %VARV%, %VARM% and %VARTT%) and the columns of a bound
# (`setbound!` with `sw`, through `sw_bnd`). In a
# deterministic run every answer is what the builders used before this change,
# so no deterministic model changes (#35, #54: layer 2 identical, same rows,
# columns and order). The stochastic answers are used from change 74 on;
# until then init_ext refuses a STAGES, SPINES or SENSIS run.

"""
    SowTags

The SOW tags of one model (sow_tags.jl, header). `stochastic` is
`%STAGES%==YES` (case-exact, maindrv.mod L66); `sow` the SOW of the row being
generated (the `SOW` of `%SOW%`), set by `set_sow!`; `sw_t` the SOWs of each
period (SW_T(T,SOW)) and `sw_tsw` the node SOW W of each (SOW,T)
(SW_TSW(SOW,T,W)), both empty in a deterministic run; `sows` the set SOW
(initmty.mod L129; filled by stages.stc L46), which a bare `%SOW%` in a row
head or a bound runs over.

GAMS: setglobs.gms L345-348 and L363-365; stages.stc L12-15; maindrv.mod L65-67, v4.9.7.
"""
mutable struct SowTags
    stochastic::Bool
    sow::String
    sw_t::Dict{String,Vector{String}}
    sw_tsw::Dict{Tuple{String,String},Vector{String}}
    sows::Vector{String}
end

SowTags(stochastic::Bool, sow::AbstractString, sw_t, sw_tsw) = SowTags(stochastic, sow, sw_t, sw_tsw, String[])

"The tags of a deterministic run: SW_NOTAGS (setglobs.gms L348, v4.9.7)."
SowTags() = SowTags(false, "", Dict{String,Vector{String}}(), Dict{Tuple{String,String},Vector{String}}(), String[])

"""
    sow_tags(data, switches) -> SowTags

SW_TAGS when the run's `%STAGES%` is `YES`, as written (maindrv.mod L66 is a
case-exact `\$IF`: SENSIS sets STAGES to `Yes`, maindrv.mod L34, and keeps
SW_NOTAGS), else SW_NOTAGS. SW_T(ALLYEAR,ALLSOW) (initmty.mod L130; set to
SOW '1' in a deterministic run, coefmain.mod L11) and
SW_TSW(ALLSOW,ALLYEAR,ALLSOW) (initmty.stc L36) are read from the data when
declared, as is the set SOW (initmty.mod L129); in a stochastic run
stages.stc builds them (change 72).

GAMS: maindrv.mod L65-67; stages.stc L12-15, v4.9.7.
"""
function sow_tags(data, switches::AbstractDict)
    get(switches, "STAGES", "") == "YES" || return SowTags()
    sw_t = Dict{String,Vector{String}}()
    for (t, w) in gset_opt(data, "SW_T", 2).keys
        push!(get!(() -> String[], sw_t, t), w)
    end
    sw_tsw = Dict{Tuple{String,String},Vector{String}}()
    for (s, t, w) in gset_opt(data, "SW_TSW", 3).keys
        push!(get!(() -> String[], sw_tsw, (s, t)), w)
    end
    sows = String[w for (w,) in gset_opt(data, "SOW", 1).keys]
    return SowTags(true, "", sw_t, sw_tsw, sows)
end

const _DET_SOWS = [""]

"""
    sw_rows(tm, t) -> Vector{String}

The SOWs a row of period `t` is generated for: `%SWT%`'s SW_T(T,SOW) in a
stochastic run; one pass with no SOW (`""`) in a deterministic one. A builder
loops over them and calls `set_sow!` before generating the row.

GAMS: stages.stc L12 (%SWT%), v4.9.7.
"""
sw_rows(tm, t::AbstractString) = tm.tags.stochastic ? get(tm.tags.sw_t, t, String[]) : _DET_SOWS

"""
    sow_rows(tm) -> Vector{String}

The SOWs a row is generated for when its head ends in a bare `%SOW%`, with no
SW_T(T,SOW) (EQ_CUMFLO, EQ_CUMNET/CUMPRD, EQ_BNDCST, the objective
components, EQ_DAMAGE, the user constraints without a period): every member
of the set SOW in a stochastic run; one pass with no SOW (`""`) in a
deterministic one. A builder loops over them and calls `set_sow!`, as with
`sw_rows`.

GAMS: stages.stc L12 (%SOW% is `,SOW`, the set controlling the row), v4.9.7.
"""
sow_rows(tm) = tm.tags.stochastic ? tm.tags.sows : _DET_SOWS

"""
    sowkey(tm, key) -> Tuple

`%SOW%` at the end of a row's index: the index as given in a deterministic
run, with the row's SOW appended (`,SOW`) in a stochastic one.
GAMS: stages.stc L12, v4.9.7.
"""
sowkey(tm, key::Tuple) = tm.tags.stochastic ? (key..., tm.tags.sow) : key

"`set_sow!(tm, sow)`: the SOW of the row being generated, read by `%SOW%` terms (sow_tags.jl)."
set_sow!(tm, sow::AbstractString) = (tm.tags.sow = sow; tm)

"""
    eqtag(tm, name) -> String

`%EQ%` in a row name: `EQ...` as given in a deterministic run, `ES...` in a
stochastic one (`EQE_COMBAL` -> `ESE_COMBAL`). GAMS: stages.stc L12, v4.9.7.
"""
function eqtag(tm, name::AbstractString)
    tm.tags.stochastic || return String(name)
    startswith(name, "EQ") || throw(ArgumentError("%EQ% tags a name that starts with EQ, got $name"))
    return "ES" * name[3:end]
end

"""
    swt(tm, key, t) -> Tuple

`%SWT%` at the end of a row's index: the index as given in a deterministic
run, with `t` and the row's SOW appended (`,SW_T(T,SOW)`) in a stochastic one.
GAMS: stages.stc L12, v4.9.7.
"""
swt(tm, key::Tuple, t::AbstractString) = tm.tags.stochastic ? (key..., String(t), tm.tags.sow) : key

"""
    swx(tm) -> String

`%SWX%`, the SOW position of the families declared over ALLSOW in both modes
(EQ(l)_BLND, EQ(l)_CAPVAC, EQL_STGCCL, ...): `'1'` in a deterministic run
(setglobs.gms L365), the row's SOW in a stochastic one (stages.stc L15).
"""
swx(tm) = tm.tags.stochastic ? tm.tags.sow : "1"

"""
    sw_cols(tm, at) -> Vector{String}

The SOW indices a term reads: `%SOW%` (`at === nothing`) is the row's own SOW;
`%VART%`, `%VARV%`, `%VARM%`, `%VARTT%` (`at` the period T, V, MODLYEAR or TT)
are the W of SW_TSW(SOW,at,W). Stochastic runs only. GAMS: stages.stc L12-13, v4.9.7.
"""
function sw_cols(tm, at::Union{Nothing,AbstractString})
    tg = tm.tags
    at === nothing && return [tg.sow]
    return get(tg.sw_tsw, (tg.sow, String(at)), String[])
end

"""
    vartag(tm, name) -> String

`%VAR%` in a variable name: `VAR_X` as given in a deterministic run, `VAS_X`
in a stochastic one. GAMS: stages.stc L12, v4.9.7.
"""
function vartag(tm, name::AbstractString)
    tm.tags.stochastic || return String(name)
    startswith(name, "VAR_") || throw(ArgumentError("%VAR% tags a name that starts with VAR_, got $name"))
    return "VAS_" * name[5:end]
end

"""
    sw_bnd(tm, name, key, sw) -> Vector{Tuple{String,Tuple}}

The variable records a bound statement `%VAR%_X.LO(key %SOW%)` assigns:
`(name, key)` itself in a deterministic run. In a stochastic run VAS_X(key,SOW)
for every SOW of the set SOW (`sw = :sow`: a bare `%SOW%`, which the
assignment controls), or for the SOWs of period `sw` where the statement
tests SW_T(T,SOW) (the local `%SWT%` of bndmain.mod L42, bnd_act.mod L18 and
bnd_flo.mod L35; the loops of bnd_elas.mod L21, bnd_flo.mod L26 and
bnd_stg.mod L20).

GAMS: stages.stc L12; bnd_set.mod L23-25; bndmain.mod L42, v4.9.7.
"""
function sw_bnd(tm, name::AbstractString, key::Tuple, sw::Union{Symbol,AbstractString})
    tm.tags.stochastic || return Tuple{String,Tuple}[(String(name), key)]
    vas = vartag(tm, name)
    sw isa Symbol && sw !== :sow && throw(ArgumentError("sw is :sow or a period, got :$sw"))
    ws = sw === :sow ? tm.tags.sows : get(tm.tags.sw_t, String(sw), String[])
    return Tuple{String,Tuple}[(vas, (key..., w)) for w in ws]
end
