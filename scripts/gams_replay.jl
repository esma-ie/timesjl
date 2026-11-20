# Run TIMES GAMS code itself on a GAMS state held by a TimesModel: the state
# (a dump, possibly modified in Julia) is written back as GAMS declarations and
# data, the TIMES files are $BATINCLUDEd unchanged from the TIMES_model
# checkout, and the symbols they compute are unloaded and read back as a dump.
# Used to check translated code on crafted states that no reference run
# reaches (scripts/make_coef_obj_unit.jl); any GAMS licence will do as long
# as the program has no SOLVE (the PyPI demo system does: gamspy_base).
#
#   include("scripts/gams_replay.jl")
#   ref = gams_replay(tm, ["coef_obj.mod" => "mod"], outputs; times_dir, skip, setglobals)
#
# What is written: every set, parameter and alias of the dump that the
# included files name, with the sets and aliases their domains need, in an
# order GAMS accepts; the dump's unique-element list first, so that set order
# (and ORD, leads, lags) is the one of the reference run. `skip` lists the
# symbols the included files declare themselves.

using OpenTIMES
using OpenTIMES: TimesModel, gset_opt, gparam_opt

const GAMS_STMT_WORDS = r"[A-Za-z_][A-Za-z0-9_]*"

"Upper-case identifiers in GAMS files, comment lines (`*` in column 1) left out."
function gams_identifiers(paths)
    ids = Set{String}()
    for p in paths, ln in eachline(p)
        startswith(ln, "*") && continue
        foreach(m -> push!(ids, uppercase(m.match)), eachmatch(GAMS_STMT_WORDS, ln))
    end
    return ids
end

quote_label(l) = occursin('\'', l) ? "\"$l\"" : "'$l'"
gams_key(k) = join(quote_label.(k), ".")
function gams_value(x::Float64, eps::Bool)
    eps && return "EPS"
    isinf(x) && return x > 0 ? "+INF" : "-INF"
    return repr(x)
end

"""
    replay_state(tm, idents; skip, bare) -> String

GAMS source declaring the dump symbols named in `idents` (and the sets and
aliases their domains use) with the current data of `tm`. A symbol in `bare`
that has no records is declared without a data statement: an empty data
statement (`/ /`) makes `\$IF DEFINED` true (docs/discrepancies.md G40), while
in a TIMES run a symbol the DD files give no data stays undefined.
"""
function replay_state(tm, idents; skip=Set{String}(), bare=Set{String}())
    syms = tm.data.dump.symbols
    want = Set{String}()
    todo = [n for n in idents if haskey(syms, n) && syms[n].kind in (:set, :parameter, :alias) && !(n in skip)]
    while !isempty(todo)
        n = pop!(todo)
        n in want && continue
        push!(want, n)
        info = syms[n]
        deps = String[d for d in info.domain if d != "*"]
        info.kind == :alias && info.alias_with != "*" && push!(deps, info.alias_with)
        for d in deps
            haskey(syms, uppercase(d)) && !(uppercase(d) in want) && push!(todo, uppercase(d))
        end
    end
    # declaration order: a symbol after its domain sets and alias target
    deps_of(n) = (info = syms[n]; Set(uppercase(d) for d in vcat(info.domain, info.kind == :alias ? [info.alias_with] : String[])
                                      if d != "*" && uppercase(d) != n && uppercase(d) in want))
    order = String[]
    placed = Set{String}()
    remaining = sort!(collect(want))
    while !isempty(remaining)
        ready = filter(n -> issubset(deps_of(n), placed), remaining)
        isempty(ready) && error("cyclic domains among ", remaining)
        append!(order, ready)
        union!(placed, ready)
        filter!(n -> !(n in placed), remaining)
    end
    io = IOBuffer()
    println(io, "\$onEmpty")
    println(io, "Set tjl_uels /")
    foreach(u -> println(io, "  ", quote_label(u)), tm.data.dump.uels)
    println(io, "/;")
    for n in order
        info = syms[n]
        dom = isempty(info.domain) ? "" : "(" * join(info.domain, ",") * ")"
        if info.kind == :alias
            println(io, "Alias (", info.alias_with, ", ", n, ");")
        elseif n in bare && isempty((info.kind == :set ? gset_opt(tm.data, n, info.dimension) : gparam_opt(tm.data, n, info.dimension)).keys)
            println(io, info.kind == :set ? "Set " : "Parameter ", n, dom, ";")
        elseif info.kind == :set
            s = gset_opt(tm.data, n, info.dimension)
            println(io, "Set ", n, dom, " /")
            foreach(k -> println(io, "  ", gams_key(k)), s.keys)
            println(io, "/;")
        elseif info.dimension == 0
            p = gparam_opt(tm.data, n, 0)
            v = get(p.values, (), nothing)
            println(io, "Scalar ", n, " / ", v === nothing ? "0" : gams_value(v, v == 0.0), " /;")
        else
            p = gparam_opt(tm.data, n, info.dimension)
            println(io, "Parameter ", n, dom, " /")
            foreach(k -> println(io, "  ", gams_key(k), " ", gams_value(p.values[k], p.values[k] == 0.0)), p.keys)
            println(io, "/;")
        end
    end
    return String(take!(io))
end

"""
    gams_replay(tm, includes, outputs; times_dir, skip, setglobals, gams, workdir) -> DumpData

Write the state of `tm` that the GAMS files `includes` (pairs file =>
batinclude arguments, files in `times_dir`) and the files they include
(`also_scan`) name, run them with `\$SETGLOBAL`s
`setglobals`, unload `outputs` and return them as a dump (converted with
reference/python/gdx2arrow.py). The Python is `python3`, or the one named by
the environment variable `TJL_PYTHON` (on Windows the harness venv's
`python.exe`, which has the GAMS Python API). `onmulti` switches on
`\$onMulti` after the state, as TIMES does (initsys.mod L22), for included
code that declares a state symbol again (timslice.mod L34, `SET TS_OFF //;`).
`bare` names the symbols to declare without data when they have none, so
that `\$IF DEFINED` on them is false as in a TIMES run (`replay_state`).
"""
function gams_replay(tm, includes, outputs; times_dir, also_scan=String[], skip=Set{String}(), setglobals=Dict{String,String}(),
                     gams=joinpath(readchomp(`$(replay_python()) -c "import gamspy_base;print(gamspy_base.directory)"`), "gams"),
                     workdir=mktempdir(), onmulti::Bool=false, bare=Set{String}())
    files = [joinpath(times_dir, f) for f in vcat([f for (f, _) in includes], also_scan)]
    write(joinpath(workdir, "state.gms"), replay_state(tm, gams_identifiers(files); skip, bare))
    io = IOBuffer()
    for (k, v) in setglobals
        println(io, "\$setglobal ", k, " ", v)
    end
    println(io, "\$include state.gms")
    # Veda/xl2times DD files switch these on and they stay on for the TIMES code
    # compiled after them (e.g. fillcost.gms L42 writes the label 'EMPTY')
    println(io, "\$onEps")
    println(io, "\$onWarning")
    onmulti && println(io, "\$onMulti")
    for (f, args) in includes
        println(io, "\$batinclude ", f, " ", args)
    end
    println(io, "execute_unload 'out.gdx', ", join(outputs, ", "), ";")
    write(joinpath(workdir, "run.gms"), String(take!(io)))
    rc = run(ignorestatus(Cmd(`$gams run.gms lo=2 idir1=$(abspath(times_dir))`; dir=workdir)))
    rc.exitcode == 0 || error("GAMS failed (", rc.exitcode, "); see ", joinpath(workdir, "run.lst"))
    out = joinpath(workdir, "out")
    run(`$(replay_python()) $(joinpath(dirname(@__DIR__), "reference", "python", "gdx2arrow.py")) $(joinpath(workdir, "out.gdx")) $out`)
    return OpenTIMES.DumpData(out)
end

replay_python() = get(ENV, "TJL_PYTHON", "python3")
