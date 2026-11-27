# Phase 2, change 0: the identity gate of the speed work (docs/phase2-notes.md P2-6; CLAUDE.md
# "Phase 2 lane": a speed change must leave the generated LP identical, "with the same rows, columns
# and order"). This script writes a fingerprint of the model TIMES.jl generates and of the state it
# was generated from, and checks a later generation against it bit for bit. It translates no GAMS
# statement and changes nothing in src/. Layer 2 at 1e-9 against GAMS's matrix stays the job of
# scripts/m11_probe.jl, scripts/m13_gate.jl and scripts/parity_report.jl; this check is stricter
# (every bit, and the order) but only compares TIMES.jl with itself.
#
#   julia --project=test scripts/p2_identity.jl <reference dir> [--variant as_run] [--root name=path ...]
#         [--from presolve|input] (--write | --check) <file.json> <model>
#   julia --project=test scripts/p2_identity.jl --fixture <prefix> (--write | --check) <file.json>
#
# <reference dir>, --variant and --root are those of scripts/m11_probe.jl (one model per call).
# --fixture takes an entry of test/fixtures/public_fixtures.toml (its pre-solve dump and switches).
# --from presolve (the default) generates from GAMS's pre-solve dump, as m11_probe.jl does.
# --from input runs TIMES.jl's own preprocessing and coefficient stages first (TIMES.PRESOLVE_STEPS on
# the input dump, no GAMS checkpoint read in between), then generates from TIMES.jl's own state: the
# gate for a speed change to those stages.
# --write writes the fingerprint; --check generates again and compares: exit code 0 when every part is
# identical, 1 otherwise, with the parts that differ named.
#
# What is fingerprinted (SHA-256 over a canonical little-endian byte stream: names as length-prefixed
# UTF-8, every Float64 by its 64 bits, so -0.0 and 0.0 differ and so do two NaNs with other bits):
#
#   state         every set and parameter as TIMES.jl holds it just before generate!: a symbol TIMES.jl
#                 has read or computed by its value there, any other symbol of the dump by its records
#                 (both written the same way, so reading a symbol sooner or later changes nothing):
#                 keys in record order, each parameter entry as absent / EPS / the value's bits. Also
#                 the label order gams_sort! ranks by, the run's switches and %REDUCE%. Not in it: the
#                 harness's TJL_SOLVEINFO, element texts, variables and equations of the dump (not read
#                 by generation).
#   rows          the set of row names (sorted)
#   columns       the set of column names (sorted)
#   row_order     the equation families in generation order and every row name in generation order
#                 (EquationStore: families in order of creation, rows in order of creation), with each
#                 row's kind (E, L, G, interval) and its index in JuMP's backend, which fixes the order
#                 the solver receives the rows of one kind in
#   column_order  every column name in creation order (JuMP.all_variables)
#   term_order    per row in generation order, the columns of its terms as stored (by column position)
#   coefficients  per row in name order, its terms in column-name order: the value bits. Independent of
#                 any order, so a change of order alone leaves it as it is
#   row_bounds    per row in name order: kind, lower and upper right-hand side, the constant
#   column_bounds per column in name order: which of lower/upper/fixed/integer/binary it has, and the values
#   objective     sense, constant and terms (in column-name order)
#   lp            all of the above but the state, in one hash
#
# and per equation family, in generation order, its row count and a hash of its rows as generated
# (names, kinds, right-hand sides, terms in stored order by column position), to say where a
# difference is. The row count is checked against JuMP's own: a row added outside the EquationStore
# stops the script.

import SHA, JSON, TOML, JuMP
using TIMES
using TIMES: TimesModel, generate!, untranslated_families, stepped, EqFamily, GamsSet, GamsParam

isdefined(@__MODULE__, :runfile_of) || include(joinpath(@__DIR__, "m11_probe.jl"))   # run_switches, runfile_of, suite_switches, parse_probe_args

const P2_FORMAT = "timesjl-identity"
const P2_FORMAT_VERSION = 1
const P2MOI = JuMP.MOI
const P2_REPO = dirname(@__DIR__)

# --- the canonical byte stream ----------------------------------------------------------------------

"SHA-256 over a buffered little-endian byte stream."
mutable struct P2Hash
    ctx::SHA.SHA2_256_CTX
    buf::Vector{UInt8}
    n::Int
end
P2Hash() = P2Hash(SHA.SHA2_256_CTX(), Vector{UInt8}(undef, 1 << 16), 0)

function p2flush!(h::P2Hash)
    h.n > 0 && SHA.update!(h.ctx, view(h.buf, 1:h.n))
    h.n = 0
    return h
end
@inline function w8!(h::P2Hash, x::UInt8)
    h.n == length(h.buf) && p2flush!(h)
    @inbounds h.buf[h.n += 1] = x
    return h
end
@inline function w64!(h::P2Hash, x::UInt64)
    h.n + 8 > length(h.buf) && p2flush!(h)
    @inbounds for i in 0:7
        h.buf[h.n + 1 + i] = (x >> (8i)) % UInt8          # little-endian on every machine
    end
    h.n += 8
    return h
end
w64!(h::P2Hash, x::Integer) = w64!(h, UInt64(x))
wf!(h::P2Hash, x::Float64) = w64!(h, reinterpret(UInt64, x))
function ws!(h::P2Hash, s::AbstractString)
    cu = codeunits(String(s))
    w64!(h, length(cu))
    for b in cu
        w8!(h, b)
    end
    return h
end
p2digest!(h::P2Hash) = (p2flush!(h); bytes2hex(SHA.digest!(h.ctx)))

# --- the state ----------------------------------------------------------------------------------------

function p2_set!(h::P2Hash, keys::Vector{NTuple{N,String}}) where {N}
    w8!(h, UInt8('S')); w64!(h, N); w64!(h, length(keys))
    for k in keys, l in k
        ws!(h, l)
    end
    return length(keys)
end

"A parameter TIMES.jl holds: absent (a plain zero the reader dropped), EPS (present, 0.0) or the value."
function p2_param!(h::P2Hash, p::GamsParam{N}) where {N}
    w8!(h, UInt8('P')); w64!(h, N); w64!(h, length(p.keys))
    held = 0
    for k in p.keys
        foreach(l -> ws!(h, l), k)
        v = get(p.values, k, nothing)
        if v === nothing
            w8!(h, 0x00)
        elseif v == 0.0
            held += 1
            w8!(h, 0x01)
        else
            held += 1
            w8!(h, 0x02); wf!(h, v)
        end
    end
    # entries held under a key that is not in the record order (none in a state read from a dump)
    if held != length(p.values)
        inorder = Set(p.keys)
        extra = sort!([k for k in keys(p.values) if !(k in inorder)])
        w8!(h, UInt8('X')); w64!(h, length(extra))
        for k in extra
            foreach(l -> ws!(h, l), k)
            wf!(h, p.values[k])
        end
    end
    return length(p.keys)
end

"A parameter of the dump TIMES.jl has not read: the same bytes as `GamsParam` of it would give."
function p2_param!(h::P2Hash, r::TIMES.Reference.SymbolRecords{N}) where {N}
    w8!(h, UInt8('P')); w64!(h, N); w64!(h, length(r.keys))
    v = get(r.values, "value", Float64[])
    sv = get(r.special, "value", TIMES.Reference.SpecialValue[])
    for (i, k) in enumerate(r.keys)
        foreach(l -> ws!(h, l), k)
        s = sv[i]
        if s == TIMES.Reference.SV_NA || s == TIMES.Reference.SV_UNDEF      # GamsParam refuses these
            w8!(h, s == TIMES.Reference.SV_NA ? 0x03 : 0x04)
        elseif s == TIMES.Reference.SV_EPS
            w8!(h, 0x01)
        elseif v[i] == 0.0
            w8!(h, 0x00)
        else
            w8!(h, 0x02); wf!(h, v[i])
        end
    end
    return length(r.keys)
end

"""
    state_fingerprint(tm; by_symbol=true) -> Dict

The state `tm` would be generated from, as it is now (call it before `generate!`): see the header.
`by_symbol` keeps one short hash per symbol (the first 16 hex digits), so that a check can name the
symbols that differ.
"""
function state_fingerprint(tm::TimesModel; by_symbol::Bool=true)
    d = tm.data
    names = Set{String}(uppercase(i.name) for i in values(d.dump.symbols) if i.kind in (:set, :parameter))
    union!(names, keys(d.sets)); union!(names, keys(d.params))
    delete!(names, "TJL_SOLVEINFO")                       # the harness's own (scripts/m13_gate.jl gate_symbols)
    all = P2Hash()
    sym = Dict{String,String}()
    records = 0
    function one!(name, f)
        h = P2Hash()
        ws!(h, name)
        n = f(h)
        dg = p2digest!(h)
        ws!(all, name); ws!(all, dg)
        by_symbol && (sym[name] = string(n, ":", first(dg, 16)))
        records += n
    end
    for name in sort!(collect(names))
        if haskey(d.sets, name)
            one!(name, h -> p2_set!(h, (d.sets[name]::GamsSet).keys))
        elseif haskey(d.params, name)
            one!(name, h -> p2_param!(h, d.params[name]::GamsParam))
        else
            r = TIMES.Reference.read_symbol(d.dump, name)
            one!(name, h -> r.info.kind == :set ? p2_set!(h, r.keys) : p2_param!(h, r))
        end
    end
    # the label order gams_sort! ranks by, the switches and %REDUCE%
    one!("(label order)", h -> begin
        for (l, i) in sort!(collect(d.uelorder); by=last)
            ws!(h, l); w64!(h, i)
        end
        length(d.uelorder)
    end)
    one!("(switches)", h -> begin
        for k in sort!(collect(keys(tm.switches)))
            ws!(h, k); ws!(h, tm.switches[k])
        end
        w8!(h, tm.reduce ? 0x01 : 0x00)
        length(tm.switches)
    end)
    out = Dict{String,Any}("sha256" => p2digest!(all), "symbols" => length(names), "records" => records)
    by_symbol && (out["by_symbol"] = sym)
    return out
end

# --- the LP as a plain record ---------------------------------------------------------------------------

"""
    LPRecord

The generated LP as plain vectors, in generation order: rows as the EquationStore lists them (families
in order of creation, rows in order of creation), columns as `JuMP.all_variables` does, the terms of
row `i` at `rowptr[i]:rowptr[i+1]-1` in the order JuMP's backend stores them, by column position.
`lp_fingerprint` hashes it; a test can change it.
"""
struct LPRecord
    families::Vector{String}          # equation families, in generation order
    famrows::Vector{Int}              # rows per family
    rownames::Vector{String}
    rowkind::Vector{UInt8}            # 'E', 'L', 'G', 'I' (interval; a free =N= row is [-Inf, Inf])
    rowlo::Vector{Float64}
    rowhi::Vector{Float64}
    rowconst::Vector{Float64}         # the constant of the row's function (0.0 from JuMP)
    rowindex::Vector{Int64}           # the row's index among the rows of its kind in JuMP's backend
    rowptr::Vector{Int}
    termcol::Vector{Int32}
    termval::Vector{Float64}
    colnames::Vector{String}
    colflags::Vector{UInt8}           # 1 lower, 2 upper, 4 fixed, 8 integer, 16 binary
    collb::Vector{Float64}
    colub::Vector{Float64}
    colfix::Vector{Float64}
    objsense::Int                     # 0 none, 1 min, 2 max
    objconst::Float64
    objcol::Vector{Int32}
    objval::Vector{Float64}
end

_kind(s::P2MOI.EqualTo{Float64}) = (UInt8('E'), s.value, s.value)
_kind(s::P2MOI.LessThan{Float64}) = (UInt8('L'), -Inf, s.upper)
_kind(s::P2MOI.GreaterThan{Float64}) = (UInt8('G'), s.lower, Inf)
_kind(s::P2MOI.Interval{Float64}) = (UInt8('I'), s.lower, s.upper)
_kind(s) = throw(ArgumentError("p2_identity: a row in $(typeof(s)) is not fingerprinted"))

function _row!(rec::LPRecord, b, pos::Dict{Int64,Int32}, ci::P2MOI.ConstraintIndex{F,S}, name::String) where {F,S}
    F === P2MOI.ScalarAffineFunction{Float64} || throw(ArgumentError("p2_identity: $name is a $F row, not a linear one"))
    f = P2MOI.get(b, P2MOI.ConstraintFunction(), ci)::P2MOI.ScalarAffineFunction{Float64}
    k, lo, hi = _kind(P2MOI.get(b, P2MOI.ConstraintSet(), ci)::S)
    push!(rec.rownames, name); push!(rec.rowkind, k); push!(rec.rowlo, lo); push!(rec.rowhi, hi)
    push!(rec.rowconst, f.constant); push!(rec.rowindex, ci.value)
    for t in f.terms
        push!(rec.termcol, pos[t.variable.value]); push!(rec.termval, t.coefficient)
    end
    push!(rec.rowptr, length(rec.termcol) + 1)
    return rec
end

function _family!(rec::LPRecord, b, pos, f::EqFamily)
    for k in f.keys
        ref = f.refs[k]
        _row!(rec, b, pos, JuMP.index(ref), JuMP.name(ref))
    end
    return length(f.keys)
end

"""
    lp_record(tm) -> LPRecord

Read the generated model of `tm` (after `generate!`) into a plain record. Stops if the EquationStore
does not hold every row of the JuMP model.
"""
function lp_record(tm::TimesModel)
    model = tm.model
    b = JuMP.backend(model)
    vars = JuMP.all_variables(model)
    rec = LPRecord(String[], Int[], String[], UInt8[], Float64[], Float64[], Float64[], Int64[], Int[1], Int32[], Float64[],
                   String[], UInt8[], Float64[], Float64[], Float64[], 0, 0.0, Int32[], Float64[])
    pos = Dict{Int64,Int32}()
    sizehint!(pos, length(vars))
    for (j, v) in enumerate(vars)
        pos[JuMP.index(v).value] = Int32(j)
        fl = 0x00
        lb, ub, fx = -Inf, Inf, NaN
        JuMP.has_lower_bound(v) && (fl |= 0x01; lb = JuMP.lower_bound(v))
        JuMP.has_upper_bound(v) && (fl |= 0x02; ub = JuMP.upper_bound(v))
        JuMP.is_fixed(v) && (fl |= 0x04; fx = JuMP.fix_value(v))
        JuMP.is_integer(v) && (fl |= 0x08)
        JuMP.is_binary(v) && (fl |= 0x10)
        push!(rec.colnames, JuMP.name(v)); push!(rec.colflags, fl)
        push!(rec.collb, lb); push!(rec.colub, ub); push!(rec.colfix, fl & 0x04 == 0 ? 0.0 : fx)
    end
    for fam in tm.eqs.order
        push!(rec.families, fam)
        push!(rec.famrows, _family!(rec, b, pos, tm.eqs.families[fam]))
    end
    nj = JuMP.num_constraints(model; count_variable_in_set_constraints=false)
    length(rec.rownames) == nj ||
        error("p2_identity: the EquationStore holds $(length(rec.rownames)) rows, the JuMP model $nj: a row was added outside addeq!")
    sense = JuMP.objective_sense(model)
    osense = sense == P2MOI.MIN_SENSE ? 1 : sense == P2MOI.MAX_SENSE ? 2 : 0
    oconst, ocol, oval = 0.0, Int32[], Float64[]
    if osense != 0
        f = JuMP.objective_function(model)
        if f isa JuMP.VariableRef
            push!(ocol, pos[JuMP.index(f).value]); push!(oval, 1.0)
        elseif f isa JuMP.AffExpr
            oconst = f.constant
            for (v, c) in f.terms
                push!(ocol, pos[JuMP.index(v).value]); push!(oval, c)
            end
        else
            throw(ArgumentError("p2_identity: an objective of type $(typeof(f)) is not fingerprinted"))
        end
    end
    return LPRecord(rec.families, rec.famrows, rec.rownames, rec.rowkind, rec.rowlo, rec.rowhi, rec.rowconst, rec.rowindex,
                    rec.rowptr, rec.termcol, rec.termval, rec.colnames, rec.colflags, rec.collb, rec.colub, rec.colfix,
                    osense, oconst, ocol, oval)
end

"The record with its rows in the order `perm` (for tests: the same LP, another row order)."
function permute_rows(r::LPRecord, perm::AbstractVector{<:Integer})
    ptr, tc, tv = Int[1], Int32[], Float64[]
    for i in perm
        rg = r.rowptr[i]:r.rowptr[i+1]-1
        append!(tc, view(r.termcol, rg)); append!(tv, view(r.termval, rg))
        push!(ptr, length(tc) + 1)
    end
    # a selection of the rows is no longer the families' rows: one family of all of them
    fams, famrows = length(perm) == length(r.rownames) ? (r.families, r.famrows) : (["(rows selected)"], [length(perm)])
    return LPRecord(fams, famrows, r.rownames[perm], r.rowkind[perm], r.rowlo[perm], r.rowhi[perm], r.rowconst[perm],
                    r.rowindex[perm], ptr, tc, tv, r.colnames, r.colflags, r.collb, r.colub, r.colfix,
                    r.objsense, r.objconst, r.objcol, r.objval)
end

const P2_LP_PARTS = ("rows", "columns", "row_order", "column_order", "term_order", "coefficients", "row_bounds",
                     "column_bounds", "objective")

"""
    lp_fingerprint(rec) -> Dict

The hashes of an `LPRecord` (see the header): `parts` by name, `lp` over all of them, the counts, and
per equation family its rows and a hash of them as generated.
"""
function lp_fingerprint(r::LPRecord)
    nrow, ncol, nnz = length(r.rownames), length(r.colnames), length(r.termval)
    allunique(r.rownames) || error("p2_identity: two rows have the same name")
    allunique(r.colnames) || error("p2_identity: two columns have the same name")
    rperm, cperm = sortperm(r.rownames), sortperm(r.colnames)
    crank = invperm(cperm)                                 # column position -> rank of its name
    parts = Dict{String,String}()

    h = P2Hash(); w64!(h, nrow); foreach(i -> ws!(h, r.rownames[i]), rperm); parts["rows"] = p2digest!(h)
    h = P2Hash(); w64!(h, ncol); foreach(j -> ws!(h, r.colnames[j]), cperm); parts["columns"] = p2digest!(h)

    h = P2Hash(); w64!(h, length(r.families))
    for (f, n) in zip(r.families, r.famrows)
        ws!(h, f); w64!(h, n)
    end
    for i in 1:nrow
        ws!(h, r.rownames[i]); w8!(h, r.rowkind[i]); w64!(h, r.rowindex[i])
    end
    parts["row_order"] = p2digest!(h)

    h = P2Hash(); w64!(h, ncol); foreach(n -> ws!(h, n), r.colnames); parts["column_order"] = p2digest!(h)

    h = P2Hash()
    for i in 1:nrow
        w64!(h, r.rowptr[i+1] - r.rowptr[i])
        for t in r.rowptr[i]:r.rowptr[i+1]-1
            w64!(h, r.termcol[t])
        end
    end
    parts["term_order"] = p2digest!(h)

    h = P2Hash()
    tmp = Tuple{Int,Int}[]                                 # (rank of the column's name, term position)
    for i in rperm
        empty!(tmp)
        for t in r.rowptr[i]:r.rowptr[i+1]-1
            push!(tmp, (crank[r.termcol[t]], t))
        end
        sort!(tmp)
        w64!(h, length(tmp))
        for (c, t) in tmp
            w64!(h, c); wf!(h, r.termval[t])
        end
    end
    parts["coefficients"] = p2digest!(h)

    h = P2Hash()
    for i in rperm
        w8!(h, r.rowkind[i]); wf!(h, r.rowlo[i]); wf!(h, r.rowhi[i]); wf!(h, r.rowconst[i])
    end
    parts["row_bounds"] = p2digest!(h)

    h = P2Hash()
    for j in cperm
        w8!(h, r.colflags[j]); wf!(h, r.collb[j]); wf!(h, r.colub[j]); wf!(h, r.colfix[j])
    end
    parts["column_bounds"] = p2digest!(h)

    h = P2Hash(); w64!(h, r.objsense); wf!(h, r.objconst); w64!(h, length(r.objcol))
    for (c, t) in sort!([(crank[c], t) for (t, c) in enumerate(r.objcol)])
        w64!(h, c); wf!(h, r.objval[t])
    end
    parts["objective"] = p2digest!(h)

    h = P2Hash(); foreach(p -> (ws!(h, p); ws!(h, parts[p])), P2_LP_PARTS)
    lp = p2digest!(h)

    fams = Any[]
    i = 0
    for (f, n) in zip(r.families, r.famrows)
        h = P2Hash()
        for _ in 1:n
            i += 1
            ws!(h, r.rownames[i]); w8!(h, r.rowkind[i]); wf!(h, r.rowlo[i]); wf!(h, r.rowhi[i]); wf!(h, r.rowconst[i])
            w64!(h, r.rowptr[i+1] - r.rowptr[i])
            for t in r.rowptr[i]:r.rowptr[i+1]-1
                w64!(h, r.termcol[t]); wf!(h, r.termval[t])
            end
        end
        push!(fams, Dict{String,Any}("name" => f, "rows" => n, "sha256" => first(p2digest!(h), 16)))
    end
    return Dict{String,Any}("lp" => lp, "parts" => parts, "rows" => nrow, "columns" => ncol, "nonzeros" => nnz,
                            "families" => fams)
end

# --- one model: its state, then its LP -------------------------------------------------------------------

"""
    p2_chain!(tm) -> tm

TIMES.jl's own stages from the input dump to the pre-solve state (`TIMES.PRESOLVE_STEPS`, as
`run_model` runs them; no GAMS checkpoint is read in between).
"""
function p2_chain!(tm::TimesModel; each=nothing)
    stp = stepped(tm)
    for (a, name, f) in TIMES.PRESOLVE_STEPS
        stp && f === TIMES.pp_clean! && continue           # as run_model: pp_clean.mod runs inside each step
        each === nothing ? f(tm) : each(a, name, () -> f(tm))
    end
    return tm
end

"""
    p2_model(refdir, model; variant="reduce_off", roots=Dict(), from="presolve") -> TimesModel

The model of one reference run, not generated yet: on its pre-solve dump (`from="presolve"`, as
scripts/m11_probe.jl), or on its input dump (`from="input"`; `p2_chain!` then computes the pre-solve
state). Switches as m11_probe.jl reads them.
"""
function p2_model(refdir, model; variant="reduce_off", roots=Dict{String,String}(), from="presolve")
    from in ("presolve", "input") || error("--from is presolve or input, not $from")
    dir = joinpath(refdir, model, variant)
    isfile(joinpath(dir, "manifest.json")) || error("no reference run in $dir")
    m = JSON.parsefile(joinpath(dir, "manifest.json"))
    isdir(joinpath(dir, from)) || error("$dir has no $from dump")
    rf = runfile_of(refdir, model, variant)
    sw = rf === nothing ? suite_switches(model, m, roots) : run_switches(rf)
    return TimesModel(joinpath(dir, from); reduce=strip(get(sw, "REDUCE", "")) == "YES", switches=sw)
end

"The model of an entry of test/fixtures/public_fixtures.toml, on its pre-solve dump, not generated yet."
function p2_fixture_model(prefix; fixtures=joinpath(P2_REPO, "test", "fixtures"))
    fx = only(filter(f -> f["prefix"] == prefix, TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    return TimesModel(joinpath(fixtures, prefix * "_presolve"); reduce=get(fx, "reduce", false),
                      switches=Dict{String,String}(k => string(v) for (k, v) in get(fx, "switches", Dict())))
end

"""
    p2_fingerprint!(tm; from="presolve", by_symbol=true, generate=generate!) -> Dict

Fingerprint the state of `tm` (after `p2_chain!` with `from="input"`), generate its model with
`generate` and fingerprint the LP. A model TIMES.jl cannot generate, or a stepped run (one LP per
step), is an error.
"""
function p2_fingerprint!(tm::TimesModel; from="presolve", by_symbol::Bool=true, generate=generate!)
    from == "input" && p2_chain!(tm)
    u = untranslated_families(tm)
    isempty(u) || error("p2_identity: not generated, needs " * join(unique(x.family for x in u), ", "))
    stepped(tm) && error("p2_identity: a stepped run has one LP per step; not fingerprinted")
    state = state_fingerprint(tm; by_symbol)
    generate(tm)
    fp = lp_fingerprint(lp_record(tm))
    fp["state"] = state
    fp["format"] = P2_FORMAT
    fp["format_version"] = P2_FORMAT_VERSION
    fp["from"] = from
    fp["times_version"] = string(TIMES.TIMES_GAMS_VERSION, " @ ", TIMES.TIMES_GAMS_COMMIT)
    fp["julia"] = string(VERSION)                          # for the reader; not compared
    return fp
end

"""
    p2_compare(old, new) -> Vector{String}

The differences between two fingerprints, one line each, the cause first; empty when they are
identical. Each line starts with the part that differs: rows, columns, order, coefficients, bounds,
objective or state.
"""
function p2_compare(old::AbstractDict, new::AbstractDict)
    out = String[]
    get(old, "format_version", nothing) == get(new, "format_version", nothing) ||
        return ["format: version $(get(old, "format_version", "?")) against $(get(new, "format_version", "?")); write the fingerprint again"]
    get(old, "from", "presolve") == get(new, "from", "presolve") ||
        push!(out, "state: generated from $(new["from"]), the fingerprint from $(old["from"])")
    so, sn = old["state"], new["state"]
    if so["sha256"] != sn["sha256"]
        msg = "state: differs ($(so["symbols"]) symbols, $(so["records"]) records against $(sn["symbols"]), $(sn["records"]))"
        if haskey(so, "by_symbol") && haskey(sn, "by_symbol")
            a, b = so["by_symbol"], sn["by_symbol"]
            diff = sort!([k for k in union(keys(a), keys(b)) if get(a, k, nothing) != get(b, k, nothing)])
            msg *= ": " * join(first(diff, 12), ", ") * (length(diff) > 12 ? " and $(length(diff) - 12) more" : "")
        end
        push!(out, msg)
    end
    po, pn = old["parts"], new["parts"]
    d(p) = po[p] != pn[p]
    d("rows") && push!(out, "rows: the set of rows differs ($(old["rows"]) rows against $(new["rows"]))")
    d("columns") && push!(out, "columns: the set of columns differs ($(old["columns"]) columns against $(new["columns"]))")
    sameset = !d("rows") && !d("columns")
    note = sameset ? "" : " (to be expected when the rows or columns differ)"
    d("row_order") && push!(out, "order: the order of the rows differs" * note)
    d("column_order") && push!(out, "order: the order of the columns differs" * note)
    d("term_order") && push!(out, "order: the order of the terms within rows differs" *
                                   (d("row_order") || d("column_order") ? " (to be expected when the rows or columns are in another order)" : note))
    d("coefficients") && push!(out, "coefficients: values differ ($(old["nonzeros"]) terms against $(new["nonzeros"]))" * note)
    d("row_bounds") && push!(out, "bounds: row kinds or right-hand sides differ" * note)
    d("column_bounds") && push!(out, "bounds: column bounds differ" * note)
    d("objective") && push!(out, "objective: differs" * note)
    if old["lp"] != new["lp"] || !isempty(out)
        fo = [(f["name"], f["rows"], f["sha256"]) for f in old["families"]]
        fn = [(f["name"], f["rows"], f["sha256"]) for f in new["families"]]
        if first.(fo) != first.(fn)
            push!(out, "order: the equation families are generated in another order, or are not the same")
        end
        mo, mn = Dict(f[1] => f for f in fo), Dict(f[1] => f for f in fn)
        bad = [k for k in first.(fn) if haskey(mo, k) && mo[k] != mn[k]]
        only_old, only_new = setdiff(first.(fo), first.(fn)), setdiff(first.(fn), first.(fo))
        isempty(bad) || push!(out, "   families whose rows differ as generated (names, order, values or the columns' positions): " *
                                   join(("$k ($(mo[k][2]) rows against $(mn[k][2]))" for k in first(bad, 12)), ", ") *
                                   (length(bad) > 12 ? " and $(length(bad) - 12) more" : ""))
        isempty(only_old) || push!(out, "   families no longer generated: " * join(only_old, ", "))
        isempty(only_new) || push!(out, "   families not in the fingerprint: " * join(only_new, ", "))
    end
    old["lp"] != new["lp"] && isempty(out) && push!(out, "lp: the whole-LP hash differs although no part does (a damaged file?)")
    return out
end

"Write a fingerprint as JSON with its keys sorted, so that the same fingerprint gives the same file."
function p2_write(path, fp)
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        _json(io, fp, 0)
        println(io)
    end
    return path
end
function _json(io, x::AbstractDict, ind)
    ks = sort!(collect(keys(x)))
    println(io, "{")
    for (n, k) in enumerate(ks)
        print(io, " "^(ind + 1), JSON.json(k), ": ")
        _json(io, x[k], ind + 1)
        println(io, n < length(ks) ? "," : "")
    end
    print(io, " "^ind, "}")
end
function _json(io, x::AbstractVector, ind)
    println(io, "[")
    for (n, v) in enumerate(x)
        print(io, " "^(ind + 1))
        _json(io, v, ind + 1)
        println(io, n < length(x) ? "," : "")
    end
    print(io, " "^ind, "]")
end
_json(io, x, ind) = print(io, JSON.json(x))

function p2_summary(fp)
    return string(fp["rows"], " rows, ", fp["columns"], " columns, ", fp["nonzeros"], " terms, ", length(fp["families"]),
                  " equation families; state of ", fp["state"]["symbols"], " symbols; lp ", first(fp["lp"], 16),
                  ", state ", first(fp["state"]["sha256"], 16))
end

function p2_identity_main(args)
    args = collect(args)
    opt = Dict{String,String}()
    for o in ("--variant", "--from", "--write", "--check", "--fixture")
        i = findfirst(==(o), args)
        i === nothing && continue
        i < length(args) || error("$o needs a value")
        opt[o] = args[i+1]
        deleteat!(args, i:i+1)
    end
    haskey(opt, "--write") != haskey(opt, "--check") || error("give one of --write <file.json> and --check <file.json>")
    from = get(opt, "--from", "presolve")
    label, tm = if haskey(opt, "--fixture")
        isempty(args) || error("--fixture takes no reference dir or model")
        from == "presolve" || error("--fixture generates from the fixture's pre-solve dump only")
        "fixture " * opt["--fixture"], p2_fixture_model(opt["--fixture"])
    else
        isempty(args) && error("usage: p2_identity.jl <reference dir> [--variant v] [--root n=p ...] [--from presolve|input] (--write|--check) <file.json> <model>")
        refdir, roots, models = parse_probe_args(args)
        length(models) == 1 || error("one model per call (one fingerprint file), got $(length(models))")
        variant = get(opt, "--variant", "reduce_off")
        models[1] * "/" * variant, p2_model(refdir, models[1]; variant, roots, from)
    end
    t = @elapsed fp = p2_fingerprint!(tm; from)
    println("== ", label, " (from ", from, "): ", p2_summary(fp), " (", round(t; digits=1), " s)")
    if haskey(opt, "--write")
        println("== ", label, ": fingerprint written to ", p2_write(opt["--write"], fp))
        return 0
    end
    old = JSON.parsefile(opt["--check"])
    get(old, "format", nothing) == P2_FORMAT || error("$(opt["--check"]) is not a $P2_FORMAT file")
    diff = p2_compare(old, fp)
    if isempty(diff)
        println("== ", label, ": IDENTICAL to ", opt["--check"], " (state, rows, columns, order, coefficients, bounds, objective)")
        return 0
    end
    println("== ", label, ": DIFFERENT from ", opt["--check"])
    foreach(l -> println("     ", l), diff)
    return 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(p2_identity_main(ARGS))
end
