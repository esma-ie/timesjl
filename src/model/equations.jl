# Equation registry and the TimesModel bundle.
#
# Mirrors the variable side (mod_vars.jl): each equation family keeps its
# instances by index tuple, in creation order — the order the GAMS generator
# creates rows in — and every constraint carries its GAMS-style name
# (`EQ_ACTFLO(REG1,2005,2005,DTPSCOA,ANNUAL)`) so layer-2 comparisons match
# rows by name.

"""
    EqFamily{N}

The generated rows of one equation family, by index tuple and in creation
order.
"""
struct EqFamily{N}
    name::String
    keys::Vector{NTuple{N,String}}
    refs::Dict{NTuple{N,String},JuMP.ConstraintRef}
end

EqFamily(name::AbstractString, N::Int) =
    EqFamily{N}(uppercase(name), NTuple{N,String}[], Dict{NTuple{N,String},JuMP.ConstraintRef}())

Base.length(f::EqFamily) = length(f.keys)

"""
    EquationStore

The generated equation families of one model, created as each family's
generator runs.
"""
struct EquationStore
    families::Dict{String,Any}
    order::Vector{String}
end

EquationStore() = EquationStore(Dict{String,Any}(), String[])

eqfamily(eqs::EquationStore, name::AbstractString) = eqs.families[uppercase(name)]
has_eqfamily(eqs::EquationStore, name::AbstractString) = haskey(eqs.families, uppercase(name))

"""
    addeq!(eqs, name, key, con) -> con

Register one generated row under its family and index tuple, name it
GAMS-style, and refuse a duplicate (GAMS defines each equation instance
once).

Once per row, so (Phase 2, change 4) the family is looked up under the name as given before its
upper case is built (the generators pass the family's own, upper-case name), and the row is
registered in a method that takes the family with its type (`families` is a `Dict{String,Any}`).
"""
function addeq!(eqs::EquationStore, name::AbstractString, key::NTuple{N,String},
                con::JuMP.ConstraintRef) where {N}
    f = get(eqs.families, name, nothing)                   # the family's own name: no upper-casing
    if f === nothing
        u = uppercase(name)
        f = get!(eqs.families, u) do
            push!(eqs.order, u)
            EqFamily(u, N)
        end
    end
    return addeq!(f::EqFamily{N}, key, con)
end

# `addeq!` with the family typed; `f.name` is the upper-case name the family is stored under.
function addeq!(f::EqFamily{N}, key::NTuple{N,String}, con::JuMP.ConstraintRef) where {N}
    haskey(f.refs, key) && throw(ArgumentError("$(f.name)$(key) generated twice"))
    f.refs[key] = con
    push!(f.keys, key)
    JuMP.set_name(con, colname(f.name, key))
    return con
end

"""
    addterm!(expr, coef::GNum, tm, name, key...; at=nothing, tagged=true) -> expr

Add `coef * name(key)` to `expr` the way GAMS generates a linear term: an
exact-zero coefficient adds nothing and creates no column; a nonzero or EPS
coefficient adds the term (value 0.0 for EPS), creating the column on first
reference (docs/discrepancies.md G5).

The SOW tags (sow_tags.jl): a term is `%VAR%_X(key %SOW%)` by default, or,
with `at` the period T, V, MODLYEAR or TT, `%VART%`/`%VARV%`/`%VARM%`/`%VARTT%_X(key %SWS%)`;
`tagged=false` is a literal `VAR_X(key)`. In a deterministic run all of them
are `VAR_X(key)`. In a stochastic run (change 74) the tagged forms read
VAS_X(key,SOW), or the sum of VAS_X(key,W) over SW_TSW(SOW,at,W).

`N`, the number of indices, is a parameter of the method so that Julia compiles it for the
caller's index tuple: a `key...` that is only passed on is not specialized, and every term then went
through a dynamic call (Phase 2, change 4; see `getvar!`).

GAMS: setglobs.gms L348; stages.stc L12-13, v4.9.7.
"""
function addterm!(expr::JuMP.AffExpr, coef::GNum, tm, name::AbstractString, key::Vararg{AbstractString,N};
                  at::Union{Nothing,AbstractString}=nothing, tagged::Bool=true) where {N}
    iszero(coef) && return expr
    coef.eps && push!(_eps_exprs(tm), expr)
    if tagged && tm.tags.stochastic
        startswith(name, "VAR_") || throw(ArgumentError("%VAR% tags a name that starts with VAR_, got $name"))
        vas = "VAS_" * name[5:end]
        for w in sw_cols(tm, at)
            JuMP.add_to_expression!(expr, coef.v, getvar!(tm, vas, key..., w))
        end
        return expr
    end
    JuMP.add_to_expression!(expr, coef.v, getvar!(tm, name, key...))
    return expr
end

"The expressions `addterm!` gave an EPS term, by identity (see `gconstraint!`)."
_eps_exprs(tm) = get!(() -> Base.IdSet{JuMP.AffExpr}(), tm.cache, "EPS_EXPRS")::Base.IdSet{JuMP.AffExpr}

"""
Whether every coefficient of `lhs - rhs` is an exact zero (no term, or terms that cancel).

The coefficient of a variable is `(0.0 + its coefficient in lhs, if it has one) - (its coefficient in
rhs, if it has one)`. An expression holds each variable once, so the two are read from the
expressions themselves and the test stops at the first coefficient that is not zero, which in
nearly every row is the first one looked at; a Dict of all of them was built for every row before
(Phase 2, change 5). The same arithmetic and the same answer.
"""
function _all_cancel(lhs::JuMP.AffExpr, rhs::JuMP.AffExpr)
    lt, rt = lhs.terms, rhs.terms
    for (v, c) in lt                                  # in lhs: (0.0 + c) - its coefficient in rhs, or (0.0 + c)
        c2 = get(rt, v, nothing)
        iszero(c2 === nothing ? 0.0 + c : (0.0 + c) - c2) || return false
    end
    for (v, c) in rt                                  # in rhs only: 0.0 - c
        haskey(lt, v) || iszero(0.0 - c) || return false
    end
    return true
end

"Add a constant (data) term to `expr`; GAMS moves it to the right-hand side."
addconst!(expr::JuMP.AffExpr, c::GNum) = (JuMP.add_to_expression!(expr, c.v); expr)

"""
    gconstraint!(tm, name, key, eqtype, lhs, rhs) -> Union{ConstraintRef,Nothing}

Create and register one row `lhs =eqtype= rhs`, `eqtype` being GAMS's E, L,
G or N. An N row is a free row (GAMS's =N=, "no relationship": it is in the
matrix with bounds -INF and +INF; eqblnd.mod with BL_TYPE 4), written as
`lhs - rhs in [-Inf, Inf]`. Like GAMS, generate no row when no variable is left with a nonzero
coefficient, once terms of the same variable are combined (none were added,
every coefficient was an exact zero, or they cancel, as in `x =E= x`), unless
an EPS coefficient was added, which keeps the row (docs/discrepancies.md G5):
return `nothing` then, after checking the constant row as GAMS does (an
infeasible one is an error). Confirmed on GAMS 54.6.0 (G22).
"""
function gconstraint!(tm, name::AbstractString, key::NTuple{N,String}, eqtype::AbstractString,
                      lhs::JuMP.AffExpr, rhs::JuMP.AffExpr) where {N}
    eps = _eps_exprs(tm)
    has_eps = lhs in eps || rhs in eps
    delete!(eps, lhs); delete!(eps, rhs)
    if !has_eps && _all_cancel(lhs, rhs)
        a, b = lhs.constant, rhs.constant
        ok = eqtype == "E" ? a == b : eqtype == "L" ? a <= b : eqtype == "G" ? a >= b : eqtype == "N" ? true :
             throw(ArgumentError("equation type must be E, L, G or N, got $eqtype"))
        ok || throw(ArgumentError("$(colname(uppercase(name), key)) has no variables and is infeasible ($a =$(eqtype)= $b)"))
        return nothing
    end
    con = if eqtype == "E"
        JuMP.@constraint(tm.model, lhs == rhs)
    elseif eqtype == "L"
        JuMP.@constraint(tm.model, lhs <= rhs)
    elseif eqtype == "G"
        JuMP.@constraint(tm.model, lhs >= rhs)
    elseif eqtype == "N"
        JuMP.@constraint(tm.model, lhs - rhs in JuMP.MOI.Interval(-Inf, Inf))
    else
        throw(ArgumentError("equation type must be E, L, G or N, got $eqtype"))
    end
    return addeq!(tm.eqs, name, key, con)
end

"""
    UnportedError(what)

Raised when the data would send generation down a GAMS code path that has
not been translated yet. Phase 1 never produces silently partial rows: if a
model needs an untranslated branch, generation stops and names the GAMS
lines to translate next.
"""
struct UnportedError <: Exception
    what::String
end

Base.showerror(io::IO, e::UnportedError) = print(io, "not yet translated: ", e.what)

"""
    TimesModel

One model instance being generated: the JuMP model, its variables, its
equations, the GAMS data it is built from, and the run switches that matter
to generation. In M1.1 `data` is a GAMS pre-solve dump (see gams_data.jl); later milestones put
computed data behind the same interface.

`reduce` is the `%REDUCE%` switch (`\$SET REDUCE YES/NO` in the run file):
the reference harness's `reduce_off` variant corresponds to `reduce=false`,
the suite's `as_run` variants to `reduce=true` (cal_red.red, M1.3 change 17b).

`switches` holds the other GAMS compile-time switches the run sets
(`\$SET OBJ AUTO`, ...), by upper-case name, as strings; `gswitch` reads them
with the default the GAMS source applies when the run sets nothing. The run
file reader (M1.5) fills them; until then tests pass the reference run's
values. The constructor also sets the switches TIMES derives from the data
rather than the run file (`data_switches!`), because a dump keeps the data
but not the compile-time switches set from it.

`cache` holds incidence maps shared by several generators (e.g. the flow
expression of cal_red.jl), built once per model on first use.
"""
struct TimesModel
    model::JuMP.Model
    vars::VariableStore
    eqs::EquationStore
    data::DumpData
    reduce::Bool
    switches::Dict{String,String}
    cache::Dict{String,Any}
    tags::SowTags          # the SOW tags (sow_tags.jl; M1.3 change 73)
end

function TimesModel(data::DumpData; reduce::Bool=false, switches=Dict{String,String}())
    model = JuMP.Model()
    sw = Dict{String,String}(uppercase(String(k)) => String(v) for (k, v) in switches)
    tm = TimesModel(model, VariableStore(model), EquationStore(), data, reduce, sw, Dict{String,Any}(), sow_tags(data, sw))
    return data_switches!(tm)
end

"""
    data_switches!(tm) -> tm

Set the compile-time switches TIMES derives from the model's data, not from
the run file:

    \$ IF DEFINED PRC_REACT           \$SETGLOBAL POWERFLO YES
    \$ IFE CARD(GR_PTDF)+CARD(GG_KGF) \$SETGLOBAL POWERFLO YES

GAMS: init_ext.vda L134-135, v4.9.7. `\$IF DEFINED` is true only when the
symbol has data (G35). GAMS sets the switch while compiling init_ext.vda,
before any code that reads %POWERFLO% (prep_ext.vda L37, pp_prelv.vda L114,
mod_ext.vda L45, equ_ext.vda L101). A dump keeps the data but not the
switch, so a model built from any checkpoint (`input` to `presolve`) must
derive it again, or the POWERFLO refusals would not fire. `init_ext!` calls
this too. Not confirmed for every model: powerflo.vda zeroes PRC_REACT
entries (L40: processes outside the grid; L65: values <= 0), so a model
whose PRC_REACT it emptied would lose the switch in the dumps after
`prelv` (JRC-EU-TIMES-cli_ll keeps some there).
"""
function data_switches!(tm)
    any(n -> !isempty(gparam_opt(tm.data, n[1], n[2])), (("PRC_REACT", 3), ("GR_PTDF", 6), ("GG_KGF", 4))) &&
        (tm.switches["POWERFLO"] = "YES")
    return tm
end

"""
    gswitch(tm, name, default) -> String

The value of GAMS switch `%name%` as the run set it, or `default`: the
value the GAMS source gives it when unset (cite the defining line where
this is called).
"""
gswitch(tm::TimesModel, name::AbstractString, default::AbstractString) =
    get(tm.switches, uppercase(name), String(default))

TimesModel(dir::AbstractString; kwargs...) = TimesModel(DumpData(dir); kwargs...)

getvar!(tm::TimesModel, name::AbstractString, key::Vararg{AbstractString,N}) where {N} = getvar!(tm.vars, name, key...)
gset(tm::TimesModel, name::AbstractString) = gset(tm.data, name)
gparam(tm::TimesModel, name::AbstractString) = gparam(tm.data, name)
