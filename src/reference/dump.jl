# Reading GAMS reference dumps written by reference/python/gdx2arrow.py.

"""
    SpecialValue

GAMS special value attached to a numeric entry. GAMS distinguishes `EPS`
(an explicit zero that counts as present in `\$`-conditions) from an absent
entry, and keeps `NA` and `UNDEF` apart from ordinary numbers. `+INF`/`-INF`
are ordinary IEEE infinities and carry `SV_NONE`.
"""
@enum SpecialValue::Int8 SV_NONE = 0 SV_EPS = 1 SV_NA = 2 SV_UNDEF = 3

const FORMAT = "timesjl-dump"
const SUPPORTED_FORMAT_VERSIONS = (1,)
const VALUE_COLUMNS = Dict(
    :set => String[],
    :alias => String[],
    :parameter => ["value"],
    :variable => ["level", "marginal", "lower", "upper", "scale"],
    :equation => ["level", "marginal", "lower", "upper", "scale"],
)

"""
    SymbolInfo

Manifest entry for one GAMS symbol in a dump.
"""
struct SymbolInfo
    name::String
    kind::Symbol            # :set, :alias, :parameter, :variable, :equation
    type::String            # GAMS subtype, e.g. "positive" or "eq"
    dimension::Int
    domain::Vector{String}
    description::String
    records::Int
    file::Union{Nothing,String}
    alias_with::Union{Nothing,String}
end

"""
    ReferenceDump

A dump directory: its manifest, symbol table and label universe. Symbol names
are looked up case-insensitively, as in GAMS.
"""
struct ReferenceDump
    dir::String
    manifest::Dict{String,Any}
    symbols::Dict{String,SymbolInfo}   # key: uppercase name
    uels::Vector{String}
end

Base.show(io::IO, d::ReferenceDump) =
    print(io, "ReferenceDump(", repr(d.dir), ", ", length(d.symbols), " symbols)")

"""
    SymbolRecords{N}

Records of one `N`-dimensional symbol, in the record order of the dump (for a
GAMS set this is GAMS ordering, which ordered-set operations depend on).

- `keys[i]`: the labels of record `i`
- `values[col][i]`, `special[col][i]`: numeric columns and their special-value
  codes (`"value"` for parameters; `"level"`, `"marginal"`, `"lower"`,
  `"upper"`, `"scale"` for variables and equations)
- `text[i]`: element text for sets (empty for other kinds)
"""
struct SymbolRecords{N}
    info::SymbolInfo
    keys::Vector{NTuple{N,String}}
    values::Dict{String,Vector{Float64}}
    special::Dict{String,Vector{SpecialValue}}
    text::Vector{String}
end

Base.length(r::SymbolRecords) = length(r.keys)
Base.show(io::IO, r::SymbolRecords{N}) where {N} =
    print(io, "SymbolRecords{", N, "}(", r.info.name, ", ", r.info.kind, ", ", length(r), " records)")

"""
    SymbolRecords(name, kind, keys; values=Dict(), special=Dict(), text=String[])

Build records directly, for example from TIMES.jl data, so they can be
compared with a dump. Missing special-value columns default to `SV_NONE`,
except that a `-0.0` value is read as `EPS`, as in the dump format.
"""
function SymbolRecords(name::AbstractString, kind::Symbol, keys::Vector{NTuple{N,String}};
                       values::AbstractDict=Dict{String,Vector{Float64}}(),
                       special::AbstractDict=Dict{String,Vector{SpecialValue}}(),
                       text::Vector{String}=String[]) where {N}
    vals = Dict{String,Vector{Float64}}(String(k) => Vector{Float64}(v) for (k, v) in values)
    sv = Dict{String,Vector{SpecialValue}}(String(k) => Vector{SpecialValue}(v) for (k, v) in special)
    for (col, v) in vals
        haskey(sv, col) || (sv[col] = [(x == 0 && signbit(x)) ? SV_EPS : SV_NONE for x in v])
        length(v) == length(keys) || throw(ArgumentError("column $col has $(length(v)) values for $(length(keys)) keys"))
    end
    info = SymbolInfo(String(name), kind, "", N, fill("*", N), "", length(keys), nothing, nothing)
    return SymbolRecords{N}(info, keys, vals, sv, text)
end

_str(x) = x === nothing ? "" : string(x)

function _symbolinfo(e::AbstractDict)
    aw = get(e, "alias_with", nothing)
    file = get(e, "file", nothing)
    return SymbolInfo(
        string(e["name"]),
        Symbol(e["kind"]),
        _str(get(e, "type", "")),
        Int(get(e, "dimension", 0)),
        String[string(x) for x in get(e, "domain", Any[])],
        _str(get(e, "description", "")),
        Int(get(e, "records", 0)),
        file === nothing ? nothing : string(file),
        aw === nothing ? nothing : string(aw),
    )
end

"""
    load_dump(dir) -> ReferenceDump

Open a dump directory written by `gdx2arrow.py`. Only the manifest and label
universe are read here; symbol records are read on demand by
[`read_symbol`](@ref).
"""
function load_dump(dir::AbstractString)
    mpath = joinpath(dir, "manifest.json")
    isfile(mpath) || throw(ArgumentError("no manifest.json in $(repr(dir))"))
    manifest = JSON.parsefile(mpath; dicttype=Dict{String,Any})
    get(manifest, "format", nothing) == FORMAT ||
        throw(ArgumentError("$(repr(mpath)) is not a $FORMAT manifest"))
    v = Int(manifest["format_version"])
    v in SUPPORTED_FORMAT_VERSIONS || throw(ArgumentError("unsupported dump format version $v"))
    symbols = Dict{String,SymbolInfo}()
    for e in manifest["symbols"]
        info = _symbolinfo(e)
        symbols[uppercase(info.name)] = info
    end
    uels = String[]
    ufile = get(manifest, "uels", nothing)
    if ufile !== nothing && isfile(joinpath(dir, ufile))
        t = Arrow.Table(joinpath(dir, ufile))
        uels = String[string(x) for x in Tables.getcolumn(t, :uel)]
    end
    return ReferenceDump(String(dir), manifest, symbols, uels)
end

"Names of all symbols in the dump, sorted."
symbol_names(d::ReferenceDump) = sort!([s.name for s in values(d.symbols)])

"Whether the dump contains a symbol (case-insensitive)."
has_symbol(d::ReferenceDump, name::AbstractString) = haskey(d.symbols, uppercase(name))

function _info(d::ReferenceDump, name::AbstractString)
    info = get(d.symbols, uppercase(name), nothing)
    info === nothing && throw(KeyError(name))
    return info
end

"""
    read_symbol(dump, name) -> SymbolRecords

Read the records of one symbol. An alias is resolved to the set it aliases.
A symbol with no records gives an empty `SymbolRecords`.
"""
function read_symbol(d::ReferenceDump, name::AbstractString)
    info = _info(d, name)
    if info.kind == :alias
        target = info.alias_with
        (target === nothing || target == "*") &&
            throw(ArgumentError("$(info.name) aliases the universe; read the universe with dump.uels"))
        return read_symbol(d, target)
    end
    return _read_records(d, info, Val(info.dimension))
end

function _read_records(d::ReferenceDump, info::SymbolInfo, ::Val{N}) where {N}
    keys = NTuple{N,String}[]
    values = Dict{String,Vector{Float64}}()
    special = Dict{String,Vector{SpecialValue}}()
    text = String[]
    if info.file === nothing
        for col in VALUE_COLUMNS[info.kind]
            values[col] = Float64[]
            special[col] = SpecialValue[]
        end
        return SymbolRecords{N}(info, keys, values, special, text)
    end
    t = Arrow.Table(joinpath(d.dir, info.file))
    cols = [Tables.getcolumn(t, Symbol("d", i)) for i in 1:N]
    n = N == 0 ? length(Tables.getcolumn(t, Tables.columnnames(t)[1])) : length(cols[1])
    resize!(keys, n)
    _key_columns!(keys, cols)
    names = Set(Tables.columnnames(t))
    for col in VALUE_COLUMNS[info.kind]
        s = Symbol(col)
        s in names || continue
        values[col] = _float_column(Tables.getcolumn(t, s))
        svs = Symbol(col, "__sv")
        special[col] = svs in names ? _special_column(Tables.getcolumn(t, svs)) : fill(SV_NONE, n)
    end
    if info.kind == :set && :element_text in names
        text = _text_column(Tables.getcolumn(t, :element_text))
    end
    return SymbolRecords{N}(info, keys, values, special, text)
end

# A column of an Arrow table has a type `_read_records` cannot know (the table holds its columns
# untyped), so a loop over one there is a dynamic call per record. Each column is therefore converted
# in a function of its own, which Julia compiles for the column's type (a function barrier; Phase 2,
# change 6). The vectors hold the same values in the same order.
function _key_columns!(keys::Vector{NTuple{N,String}}, cols::Vector) where {N}
    @inbounds for r in 1:length(keys)
        keys[r] = ntuple(i -> String(cols[i][r]), Val(N))
    end
    return keys
end
_float_column(col) = Float64[Float64(x) for x in col]
_special_column(col) = SpecialValue[SpecialValue(Int8(x)) for x in col]
_text_column(col) = String[string(x) for x in col]
