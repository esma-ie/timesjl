# Sets and parameters read from a GAMS reference dump, with GAMS semantics.
#
# M1.1 builds the model from GAMS-dumped data: the pre-solve dump (reference
# harness run with SOLVE_NOW=NO), i.e. every symbol exactly as GAMS has it
# when the SOLVE statement generates the equations, after eqmain, bndmain,
# pp_qack and pp_clean (maindrv.mod L79-113). The coef/ dump is earlier and
# misses changes pp_qack makes to sets the equations use (RTP_VNTBYR,
# RTPCS_VARF, RCS_COMBAL, PRC_CG, ...). Rule for generators: what an eq*.mod
# file computes itself (e.g. AFS in eqcapact.mod) is translated, and checked
# against this dump where it survives; everything else is read from it.
# M1.2-M1.3 later replace the dumped values with computed ones behind the
# same interface.
#
# GAMS semantics kept:
# - A set member either exists or does not; membership drives every
#   $-condition. Record order is GAMS order (ordered-set operations and the
#   order rows are generated in depend on it).
# - A parameter entry with value EPS is an explicit zero: present in
#   $-conditions, 0.0 in arithmetic. An absent entry is 0.0 in arithmetic
#   and false in $-conditions. NA/UNDEF never appear in model data; reading
#   one is an error, never a silent zero.
# - Names are case-insensitive.

"""
    GamsSet{N}

One GAMS set from a dump: members for `in` tests, `keys` in GAMS record
order for iteration.
"""
struct GamsSet{N}
    name::String
    keys::Vector{NTuple{N,String}}
    members::Set{NTuple{N,String}}
end

function GamsSet(r::Reference.SymbolRecords{N}) where {N}
    r.info.kind == :set || throw(ArgumentError("$(r.info.name) is a $(r.info.kind), not a set"))
    return GamsSet{N}(r.info.name, r.keys, Set(r.keys))
end

Base.in(k::NTuple{N,String}, s::GamsSet{N}) where {N} = k in s.members
Base.in(k::Tuple, s::GamsSet{N}) where {N} = NTuple{N,String}(String.(k)) in s.members
Base.length(s::GamsSet) = length(s.keys)
Base.iterate(s::GamsSet, state...) = iterate(s.keys, state...)
Base.eltype(::Type{GamsSet{N}}) where {N} = NTuple{N,String}
Base.isempty(s::GamsSet) = isempty(s.keys)
Base.show(io::IO, s::GamsSet{N}) where {N} =
    print(io, "GamsSet{", N, "}(", s.name, ", ", length(s), " members)")

"""
    GamsParam{N}

One GAMS parameter from a dump. `param[key]` is GAMS arithmetic: 0.0 for an
absent entry, 0.0 for EPS. `haskey` is the `\$`-condition: true for EPS,
false for absent (GAMS confirmed: `x\$p` holds for `p = EPS`). NA or UNDEF
entries are refused at load. `keys` keeps GAMS record order.

A GDX file stores no plain zero for an indexed symbol and the reader drops
the one it writes for a zero scalar, so a present entry whose value is 0.0
is always EPS (`iseps`).
"""
struct GamsParam{N}
    name::String
    keys::Vector{NTuple{N,String}}
    values::Dict{NTuple{N,String},Float64}
end

function GamsParam(r::Reference.SymbolRecords{N}) where {N}
    r.info.kind == :parameter || throw(ArgumentError("$(r.info.name) is a $(r.info.kind), not a parameter"))
    vals = Dict{NTuple{N,String},Float64}()
    v = get(r.values, "value", Float64[])
    sv = get(r.special, "value", Reference.SpecialValue[])
    for (i, k) in enumerate(r.keys)
        s = sv[i]
        s in (Reference.SV_NA, Reference.SV_UNDEF) &&
            throw(ArgumentError("$(r.info.name)$(k) is $(s); NA/UNDEF cannot enter the model"))
        # A plain 0 is absent: GDX writes one only for a scalar (`Scalar a / 0 /`,
        # checked 21 Oct 2026), which must not read as EPS.
        s != Reference.SV_EPS && v[i] == 0.0 && continue
        vals[k] = s == Reference.SV_EPS ? 0.0 : v[i]
    end
    return GamsParam{N}(r.info.name, copy(r.keys), vals)
end

"True when the entry is present with value EPS (an explicit zero)."
iseps(p::GamsParam{N}, k::NTuple{N,String}) where {N} = get(p.values, k, 1.0) == 0.0

Base.getindex(p::GamsParam{N}, k::NTuple{N,String}) where {N} = get(p.values, k, 0.0)
Base.getindex(p::GamsParam{N}, k::AbstractString...) where {N} = p[NTuple{N,String}(String.(k))]
Base.haskey(p::GamsParam{N}, k::NTuple{N,String}) where {N} = haskey(p.values, k)
Base.haskey(p::GamsParam{N}, k::AbstractString...) where {N} = haskey(p.values, NTuple{N,String}(String.(k)))
Base.length(p::GamsParam) = length(p.values)
Base.isempty(p::GamsParam) = isempty(p.values)
Base.show(io::IO, p::GamsParam{N}) where {N} =
    print(io, "GamsParam{", N, "}(", p.name, ", ", length(p), " entries)")

"""
    GNum <: Number

A coefficient value with GAMS extended-range semantics for EPS. GAMS creates
a matrix entry (and its column) when a coefficient evaluates to a nonzero
value or EPS, and none for an exact zero (docs/discrepancies.md G5), so
generators compute coefficients as `GNum` and emit a term unless it is an
exact zero (`iszero`). EPS is carried as value 0.0 with `eps = true`.

Arithmetic, as confirmed on GAMS 54.6.0 (docs/discrepancies.md G6):
`EPS+0 = EPS`, `EPS-EPS = EPS`, `-EPS = EPS`, `EPS*2 = EPS/2 = EPS*EPS =
EPS`, `EPS+3 = 3`, while `EPS*0 = 0`, `1+EPS-1 = 0` and `2-2 = 0` are exact
zeros. Division by zero or EPS is an error, as in GAMS. Plain numbers
promote to non-EPS `GNum`s.
"""
struct GNum <: Number
    v::Float64
    eps::Bool
    GNum(v::Real, eps::Bool) = new(Float64(v), eps && v == 0)
end

GNum(x::Real) = GNum(x, false)
GNum(x::GNum) = x
const GZERO = GNum(0.0, false)
const GEPS = GNum(0.0, true)

Base.convert(::Type{GNum}, x::Real) = GNum(x)
Base.promote_rule(::Type{GNum}, ::Type{<:Real}) = GNum
Base.iszero(a::GNum) = a.v == 0 && !a.eps
Base.Float64(a::GNum) = a.v
Base.zero(::Type{GNum}) = GZERO
Base.one(::Type{GNum}) = GNum(1.0)
Base.:(==)(a::GNum, b::GNum) = a.v == b.v && a.eps == b.eps
Base.isapprox(a::GNum, b::GNum; kw...) = a.eps == b.eps && isapprox(a.v, b.v; kw...)
Base.show(io::IO, a::GNum) = a.eps ? print(io, "EPS") : print(io, a.v)

function Base.:+(a::GNum, b::GNum)
    s = a.v + b.v
    s != 0 && return GNum(s)
    # A zero sum is EPS only when both operands are zero-valued and one is EPS.
    return GNum(0.0, a.v == 0 && b.v == 0 && (a.eps || b.eps))
end
Base.:-(a::GNum) = GNum(-a.v, a.eps)
Base.:-(a::GNum, b::GNum) = a + (-b)
function Base.:*(a::GNum, b::GNum)
    (iszero(a) || iszero(b)) && return GZERO
    p = a.v * b.v
    return p == 0 ? GEPS : GNum(p)
end
function Base.:/(a::GNum, b::GNum)
    b.v == 0 && throw(DomainError(b, "division by $(b) (GAMS: division by zero)"))
    iszero(a) && return GZERO
    # A finite value (or EPS) divided by +-INF is an exact zero (no matrix
    # entry), as confirmed on GAMS 54.6.0 (docs/discrepancies.md G17). A
    # quotient that underflows below the double range is kept as EPS here;
    # GAMS gives UNDF for it (G17), which TIMES data never reaches.
    isinf(b.v) && isfinite(a.v) && return GZERO
    q = a.v / b.v
    return q == 0 ? GEPS : GNum(q)
end
"GAMS `EXP(x)`; never zero, so EPS only maps to exp(0) = 1."
gexp(a::GNum) = GNum(exp(a.v))
"""
    gpower(x, n) -> GNum

GAMS `POWER(x,n)`: `power(0,0) = power(EPS,0) = 1` (docs/discrepancies.md
G4), `power(EPS,2) = EPS`, a negative base is allowed. A zero or EPS base
with `n < 0` is an execution error (FUNC SINGULAR), and so is a non-integer
`n` (FUNC DOMAIN), as confirmed on GAMS 54.6.0 (G16).
"""
function gpower(a::GNum, n::Integer)
    n == 0 && return GNum(1.0)
    n < 0 && a.v == 0 && throw(DomainError(a, "POWER(x,$n) with x = $(a) (GAMS: FUNC SINGULAR)"))
    iszero(a) && return GZERO
    p = a.v^n
    return p == 0 ? GEPS : GNum(p)
end
function gpower(a::GNum, y::GNum)
    isinteger(y.v) || throw(DomainError(y, "POWER(x,y) with y not an integer (GAMS: FUNC DOMAIN)"))
    return gpower(a, Int(y.v))
end
"GAMS `ABS(x)`; `ABS(EPS) = EPS` (docs/discrepancies.md G16)."
Base.abs(a::GNum) = GNum(abs(a.v), a.eps)

"""
    gpow(x, y) -> GNum

GAMS `x**y` (real power, `rPower`), as confirmed on GAMS 54.6.0
(docs/discrepancies.md G13): an exact-zero or EPS exponent gives 1 for any
base (`0**EPS = EPS**EPS = 0**0 = 2**EPS = 1`); for `y > 0`, `0**y = 0` and
`EPS**y = EPS`; `0**y` with `y < 0` and any negative base are execution
errors. Unlike `POWER(x,n)` ([`gpower`](@ref)) a negative base is never
allowed. Note `\$` binds tighter than `**`: `EPS**1\$c` is `EPS**(1\$c)`.
"""
function gpow(a::GNum, b::GNum)
    b.v == 0 && return GNum(1.0)
    a.v < 0 && throw(DomainError(a, "x**y with x < 0 (GAMS: rPower FUNC DOMAIN)"))
    if a.v == 0
        b.v < 0 && throw(DomainError(a, "x**y with x = 0, y < 0 (GAMS: rPower FUNC DOMAIN)"))
        return a                               # 0**y = 0, EPS**y = EPS
    end
    p = a.v^b.v
    return p == 0 ? GEPS : GNum(p)
end

"""
    gmax(a, b) -> GNum

GAMS `MAX(a,b)`: the larger value; EPS counts as 0 and is returned when it
ties with 0 or is the larger (`MAX(0,EPS) = MAX(EPS,0) = MAX(EPS,-1) = EPS`;
docs/discrepancies.md G14).
"""
function gmax(a::GNum, b::GNum)
    a.v > b.v && return a
    b.v > a.v && return b
    return GNum(a.v, a.eps || b.eps)
end

"""
    gmin(a, b) -> GNum

GAMS `MIN(a,b)`: the smaller value; EPS counts as 0 and is returned when it
ties with 0 or is the smaller (`MIN(0,EPS) = MIN(EPS,0) = MIN(EPS,1) = EPS`,
`MIN(EPS,-1) = -1`; docs/discrepancies.md G21).
"""
function gmin(a::GNum, b::GNum)
    a.v < b.v && return a
    b.v < a.v && return b
    return GNum(a.v, a.eps || b.eps)
end

"GAMS `x\$cond`: `x` when `cond` holds, an exact zero otherwise."
gif(a, cond::Bool) = cond ? GNum(a) : GZERO

"""
    gv(param, key) -> GNum

A parameter entry as a GAMS value: exact zero when absent, EPS when present
with value 0 (a GDX file stores no plain zeros), the value otherwise.
"""
function gv(p::GamsParam{N}, k::NTuple{N,String}) where {N}
    v = get(p.values, k, nothing)
    v === nothing && return GZERO
    return v == 0.0 ? GEPS : GNum(v)
end

"""
    nonzero(param, key) -> Float64

The value of an entry a GAMS expression divides by or requires nonzero:
throws if the entry is absent or an explicit zero, where GAMS would raise an
execution error, instead of silently producing 0.
"""
function nonzero(p::GamsParam{N}, k::NTuple{N,String}) where {N}
    v = get(p.values, k) do
        throw(ArgumentError("$(p.name)$(k) is absent; GAMS would raise a division/execution error here"))
    end
    v == 0.0 && throw(ArgumentError("$(p.name)$(k) is zero; GAMS would raise a division error here"))
    return v
end

"""
    indexby(set, dims) -> Dict

Precomputed incidence map of a set over the index positions `dims`: the
members that share those labels, in GAMS record order. This is how
`\$`-controlled sums are written as explicit sparse lookups instead of
filters inside constraint bodies.
"""
function indexby(s::Union{GamsSet{N},GamsParam{N}}, dims::NTuple{M,Int}) where {N,M}
    out = Dict{NTuple{M,String},Vector{NTuple{N,String}}}()
    for k in s.keys
        push!(get!(() -> NTuple{N,String}[], out, ntuple(i -> k[dims[i]], Val(M))), k)
    end
    return out
end

const NO_MEMBERS = Tuple{}[]

"""
    DumpData

A reference dump with cached typed sets and parameters: `gset(data, name)`
and `gparam(data, name)`, case-insensitive like GAMS.
"""
struct DumpData
    dump::Reference.ReferenceDump
    sets::Dict{String,Any}
    params::Dict{String,Any}
    uelorder::Dict{String,Int}
end

function DumpData(dir::AbstractString)
    dump = Reference.load_dump(dir)
    ord = Dict{String,Int}(lowercase(u) => i for (i, u) in enumerate(dump.uels))
    return DumpData(dump, Dict{String,Any}(), Dict{String,Any}(), ord)
end

"""
The set `name` from the dump (cached). An alias (`ALIAS(PASTYEAR,PYR)`) is its target as it is now:
the set TIMES.jl holds for the target once it has computed it, not the target's records in the dump,
and it is never cached under its own name, so that it follows the target as GAMS's alias does.
"""
function gset(d::DumpData, name::AbstractString)::GamsSet
    s = get(d.sets, uppercase(name), nothing)
    s === nothing || return s
    info = get(d.dump.symbols, uppercase(name), nothing)
    if info !== nothing && info.kind === :alias && info.alias_with !== nothing && info.alias_with != "*"
        return gset(d, info.alias_with)
    end
    return get!(() -> GamsSet(Reference.read_symbol(d.dump, name)), d.sets, uppercase(name))
end

"The parameter `name` from the dump (cached)."
gparam(d::DumpData, name::AbstractString)::GamsParam =
    get!(() -> GamsParam(Reference.read_symbol(d.dump, name)), d.params, uppercase(name))

"""
    gset_opt(data, name, N) -> GamsSet{N}

A set that only exists when an extension is loaded (e.g. VDA's
`RPS_CAFLAC`, declared in init_ext.vda L23): the dumped set if the run
declared it, otherwise an empty set. GAMS code that refers to such a set is
only compiled with the extension, so an undeclared set has no effect, which
an empty set reproduces. A set TIMES.jl has computed (`gput!`) is returned
even when the dump does not declare it (curex.gms declares CURMAP only when
it is included; a crafted state can switch it on).
"""
function gset_opt(d::DumpData, name::AbstractString, N::Int)
    (haskey(d.sets, uppercase(name)) || Reference.has_symbol(d.dump, name)) && return gset(d, name)
    return GamsSet{N}(uppercase(name), NTuple{N,String}[], Set{NTuple{N,String}}())
end

"""
    gparam_opt(data, name, N) -> GamsParam{N}

A parameter that only exists when an extension or option declares it (e.g.
`RTP_FFCS`, tested with `\$IF DEFINED`): the dumped parameter if the run
declared it, otherwise an empty one, which reads as zero everywhere. A
parameter TIMES.jl has computed (`gput!`) is returned as for `gset_opt`.
"""
function gparam_opt(d::DumpData, name::AbstractString, N::Int)
    (haskey(d.params, uppercase(name)) || Reference.has_symbol(d.dump, name)) && return gparam(d, name)
    return GamsParam{N}(uppercase(name), NTuple{N,String}[], Dict{NTuple{N,String},Float64}())
end

"""
    gams_sort!(keys, data) -> keys

Sort index tuples into GAMS order: lexicographic by each label's position in
the GAMS unique-element list (the order sets and parameters are stored and
iterated in, which is entry order, not alphabetical). Used for sets that
TIMES.jl computes itself, so that rows are generated in GAMS order.
"""
function gams_sort!(keys::Vector{NTuple{N,String}}, d::DumpData) where {N}
    # Each label is ranked once (labels repeat across keys), and each key once, before sorting:
    # ranking inside `by` would redo it at every comparison. As before, a vector of 0 or 1 keys is
    # left as it is, unranked (sort! never compared, so a label outside the list passed).
    length(keys) <= 1 && return keys
    cache = Dict{String,Int}()
    rank(l) = get!(cache, l) do
        get(d.uelorder, lowercase(l)) do
            throw(ArgumentError("label '$l' is not in the dump's unique-element list"))
        end
    end
    rk = [ntuple(i -> rank(k[i]), Val(N)) for k in keys]
    return permute!(keys, sortperm(rk))
end

"""
    register_uel!(data, label) -> data

Add a label that the TIMES source names itself (e.g. the empty label `''`
of init_ext.vda L78-87) to the unique-element order when no record of the
dump uses it: a GDX file holds only the labels some record uses
(docs/discrepancies.md G36), so such a label is missing from the dump it
starts from. It is placed after every known label; its position in the GAMS
order cannot be read from the dump, which only matters for the iteration
order of sets that hold it.
"""
function register_uel!(d::DumpData, label::AbstractString)
    haskey(d.uelorder, lowercase(label)) || (d.uelorder[lowercase(label)] = length(d.uelorder) + 1)
    return d
end
