# Issue #97 (M1.6, started before M1.6 opens, as an experiment: James, 12 Nov 2026): the solution
# of a solved model written as a TIMES.jl dump, in the layout the reference harness writes from
# GAMS's GDX files (reference/python/gdx2arrow.py, format version 1). Downstream tools then read
# results from GAMS (the harness's `final/` dump: GAMS's `execute_unload` after the SOLVE) and
# from TIMES.jl with one reader, and compare them with no conversion step.
#
# This is not a translation of GAMS code: GAMS writes its solution to a GDX file, which TIMES.jl
# does not write. The report parameters of rpt*.mod (PAR_*, CST_*) come with M1.6 proper.

"""
    write_solution(tm, dir; source="", solver="") -> String

Write the solution of the solved model `tm` to `dir` as a TIMES.jl dump (`manifest.json`,
`uels.arrow`, one `<symbol>.arrow` per variable and equation family with rows), and return `dir`.

Every variable and equation instance TIMES.jl generated is written, family by family in
declaration and creation order, with the columns of a GAMS GDX solution:

- `level`: the value of the variable; for an equation, the value of its variable terms (the
  row activity: GAMS moves the constants to the right-hand side, as JuMP does);
- `marginal`: for a variable its reduced cost (`JuMP.reduced_cost`), for an equation its dual
  (`JuMP.dual`). For a minimisation, both are the change in the objective per unit of the bound
  or right-hand side, GAMS's sign convention. `NaN` (special value NA) when the solver gave no
  duals;
- `lower`, `upper`: the bounds (for an equation, its right-hand side: `=E=` both, `=G=` the
  lower, `=L=` the upper), `±Inf` where there is none;
- `scale`: 1 (TIMES.jl does not scale).

Domains, GAMS types and descriptions come from the model's input dump (`tm.data`), so the
column names match GAMS's. The manifest adds `content = "solution"`, the objective, the
termination status and `solver`.

Not written, unlike GAMS's GDX: instances that no row references (GAMS keeps records with
non-default values), and EPS marginals (GAMS writes EPS for a zero marginal of a non-basic
column; TIMES.jl writes 0). Under REDUCE the flows that cal_red.red substitutes are not
columns, as in GAMS's model; their levels come with the report (M1.6).
"""
function write_solution(tm::TimesModel, dir::AbstractString; source::AbstractString="", solver::AbstractString="")
    m = tm.model
    JuMP.has_values(m) || throw(ArgumentError("write_solution: the model has no solution; solve it first"))
    duals = JuMP.has_duals(m)
    mkpath(dir)
    uels, seen = String[], Set{String}()
    addlabels!(k) = for x in k
        x in seen || (push!(seen, x); push!(uels, x))
    end
    sv(x) = isnan(x) ? Int8(2) : Int8(0)
    entries = Any[]

    function entry!(name, kind, N, rows, dflt_type)
        info = get(tm.data.dump.symbols, uppercase(name), nothing)
        dom = info !== nothing && length(info.domain) == N ? copy(info.domain) : fill("*", N)
        typ = info !== nothing && !isempty(info.type) ? info.type : dflt_type
        e = Dict{String,Any}("name" => info === nothing ? name : info.name, "kind" => kind, "type" => typ,
                             "dimension" => N, "domain" => dom,
                             "description" => info === nothing ? "" : info.description,
                             "records" => 0, "file" => nothing)
        if !isempty(rows.keys)
            ks = rows.keys
            foreach(addlabels!, ks)
            cols = Pair{Symbol,Any}[Symbol("d", i) => String[k[i] for k in ks] for i in 1:N]
            for c in (:level, :marginal, :lower, :upper, :scale)
                v = getfield(rows, c)
                push!(cols, c => v)
                push!(cols, Symbol(c, "__sv") => Int8[sv(x) for x in v])
            end
            file = e["name"] * ".arrow"
            Arrow.write(joinpath(dir, file), NamedTuple(cols))
            e["records"] = length(ks)
            e["file"] = file
        end
        push!(entries, e)
    end

    for u in tm.vars.order
        f = tm.vars.families[u]
        N = dimension(f.spec)
        n = length(f.keys)
        lv, mg, lo, up = Vector{Float64}(undef, n), Vector{Float64}(undef, n), Vector{Float64}(undef, n), Vector{Float64}(undef, n)
        for (i, k) in enumerate(f.keys)
            v = f.refs[k]
            lv[i] = JuMP.value(v)
            mg[i] = duals ? JuMP.reduced_cost(v) : NaN
            if JuMP.is_fixed(v)
                lo[i] = up[i] = JuMP.fix_value(v)
            else
                lo[i] = JuMP.has_lower_bound(v) ? JuMP.lower_bound(v) : -Inf
                up[i] = JuMP.has_upper_bound(v) ? JuMP.upper_bound(v) : Inf
            end
        end
        entry!(f.spec.name, "variable", N, (keys=f.keys, level=lv, marginal=mg, lower=lo, upper=up, scale=ones(n)),
               f.spec.positive ? "positive" : "free")
    end

    for u in tm.eqs.order
        f = tm.eqs.families[u]
        N = length(first(f.keys))
        n = length(f.keys)
        lv, mg, lo, up = Vector{Float64}(undef, n), Vector{Float64}(undef, n), Vector{Float64}(undef, n), Vector{Float64}(undef, n)
        typ = ""
        for (i, k) in enumerate(f.keys)
            c = f.refs[k]
            lv[i] = JuMP.value(c)
            mg[i] = duals ? JuMP.dual(c) : NaN
            s = JuMP.constraint_object(c).set
            lo[i], up[i], t = _rowbounds(s)
            i == 1 && (typ = t)
        end
        entry!(f.name, "equation", N, (keys=f.keys, level=lv, marginal=mg, lower=lo, upper=up, scale=ones(n)), typ)
    end

    Arrow.write(joinpath(dir, "uels.arrow"), (uel=uels,))
    st = JuMP.termination_status(m)
    manifest = Dict{String,Any}("format" => Reference.FORMAT, "format_version" => 1, "content" => "solution",
                                "source" => source, "solver" => solver, "termination" => string(st),
                                "objective" => JuMP.objective_value(m), "duals" => duals,
                                "times_version" => "$(TIMES_GAMS_VERSION) @ $(TIMES_GAMS_COMMIT)",
                                "uels" => "uels.arrow", "symbols" => entries)
    open(joinpath(dir, "manifest.json"), "w") do io
        JSON.print(io, manifest, 1)
    end
    return String(dir)
end

# the bounds of a row from its JuMP set, and GAMS's equation type
_rowbounds(s::JuMP.MOI.EqualTo) = (s.value, s.value, "eq")
_rowbounds(s::JuMP.MOI.GreaterThan) = (s.lower, Inf, "geq")
_rowbounds(s::JuMP.MOI.LessThan) = (-Inf, s.upper, "leq")
_rowbounds(s::JuMP.MOI.Interval) = (s.lower, s.upper, "range")
_rowbounds(s) = (-Inf, Inf, "")
