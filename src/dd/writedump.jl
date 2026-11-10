# M1.4 change 5: the compile's result written as a TIMES.jl dump, so that everything that reads the
# harness's `input/` dump (DumpData, TimesModel, the M1.3 chain) runs from a model's DD files.
#
# The layout is the harness's (reference/python/gdx2arrow.py, format version 1): manifest.json,
# uels.arrow, one <symbol>.arrow per symbol with records. The symbols are those GAMS's
# `execute_unload` writes (`gdx_symbols`, G57), in declaration order; the labels are `gdx_uels` (G55).

# special values as gdx2arrow.py writes them: EPS -0.0 (code 1), NA and UNDF NaN (2, 3), +-INF as numbers
const DUMP_SV = Dict(:eps => Int8(1), :na => Int8(2), :undf => Int8(3))
dump_value(x::Float64, sp::Symbol) = sp === :eps ? -0.0 : sp in (:na, :undf) ? NaN : sp === :inf ? Inf : sp === :minf ? -Inf : x

"""
    write_dump(g, dir; source="") -> String

Write the compiled state `g` (`gams_compile!`, `compile_run`) to `dir` as a TIMES.jl dump, the form
of the harness's `input/` dump (the state just before `\$BATINCLUDE maindrv.mod`), and return `dir`.

Every set, parameter and alias is written with its records in GAMS order: keys, values with EPS as
`-0.0` and special-value code 1, element text. Variables and equations are written as symbols
without records or type: GAMS gives them a type and, for a scalar, one record, from statements
(`VARIABLE` subtypes, `=E=` in a definition) the reader does not keep. Nothing in TIMES.jl reads
them from the input dump; known-differences.md records it.
"""
function write_dump(g::GamsCompile, dir::AbstractString; source::AbstractString="")
    mkpath(dir)
    entries = Any[]
    for s in gdx_symbols(g)
        kind = s.kind === :scalar ? :parameter : s.kind
        e = Dict{String,Any}("name" => s.name, "kind" => String(kind), "dimension" => max(s.dim, 0),
                             "domain" => copy(s.domain), "description" => s.text, "records" => 0, "file" => nothing)
        if kind === :alias
            t = get(g.syms, uppercase(s.alias), nothing)
            e["alias_with"] = s.alias == "*" ? "*" : (t === nothing ? s.alias : t.name)
            e["dimension"] = 1
            e["domain"] = ["*"]
            e["description"] = ""
            push!(entries, e)
            continue
        end
        e["type"] = ""
        if kind in (:set, :parameter)
            isempty(e["domain"]) && s.dim > 0 && (e["domain"] = fill("*", s.dim))
            ks, vs = grecords(g, s)
            if !isempty(ks)
                n = length(ks)
                cols = Pair{Symbol,Any}[Symbol("d", i) => String[k[i] for k in ks] for i in 1:max(s.dim, 0)]
                if kind === :set
                    push!(cols, :element_text => String[v for v in vs])
                else
                    push!(cols, :value => Float64[dump_value(v...) for v in vs])
                    push!(cols, :value__sv => Int8[get(DUMP_SV, v[2], 0) for v in vs])
                end
                file = s.name * ".arrow"
                Arrow.write(joinpath(dir, file), NamedTuple(cols))
                e["records"] = n
                e["file"] = file
            end
        end
        push!(entries, e)
    end
    Arrow.write(joinpath(dir, "uels.arrow"), (uel=gdx_uels(g),))
    manifest = Dict{String,Any}("format" => Reference.FORMAT, "format_version" => 1, "source" => source,
                                "uels" => "uels.arrow", "symbols" => entries)
    open(joinpath(dir, "manifest.json"), "w") do io
        JSON.print(io, manifest, 1)
    end
    return String(dir)
end
