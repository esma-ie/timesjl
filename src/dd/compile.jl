# M1.4 changes 2-4: GAMS's compile phase for a TIMES run, from the .run file to `$BATINCLUDE maindrv.mod`.
#
# GAMS: the .run file, initsys.mod L17-187 (with units.def, maplists.def, globals.def), initmty.mod
# L19-508, main_ext.mod L1-23 and the extension declarations initmty.dsc, initmty.vda; v4.9.7.
# The run file and the TIMES files are read with src/dd/ddparse.jl; this file does what the GAMS
# compiler does with them, in order: the dollar-control lines ($SET, $IF, $BATINCLUDE, $KILL, $ONEPS,
# ...), the declarations (with $ONMULTI), the data statements (domain checks, $ONEPS, label order),
# and it queues the executable statements, which run when compilation ends, as GAMS runs them, by the
# hand-written Julia in `INIT_EXEC` (each cites its line). The result is what the harness's input
# dump holds (`execute_unload` just before maindrv.mod): every symbol, its records, and the labels.
#
# GAMS rules followed (GAMS 54 manual: Dollar Control Options; Data Entry; Compile-Time Variables),
# and the checks that confirm each against the input/ dumps are in docs/m14-plan.md. Behaviour not
# confirmed is marked UNCONFIRMED here and refused or flagged, never guessed silently.

"A GAMS symbol as compiled: declaration, then its data."
mutable struct GSym
    name::String                      # spelling of the first declaration
    kind::Symbol                      # :set, :parameter, :scalar, :alias
    domain::Vector{String}            # domain set names ("*" = universe); empty if not written (yet)
    text::String                      # first non-blank declaration text
    order::Int                        # declaration order (the dump's symbol order)
    alias::String                     # :alias: the set it names
    dim::Int                          # -1 until a domain or a record fixes it
    hasdata::Bool
    members::Dict{Vector{String},String}                 # sets: member => element text
    vals::Dict{Vector{String},Tuple{Float64,Symbol}}     # parameters, scalars: value, special (:eps, ...)
end
GSym(name, kind, order) = GSym(name, kind, String[], "", order, "", -1, false,
    Dict{Vector{String},String}(), Dict{Vector{String},Tuple{Float64,Symbol}}())

"One include level: its file, arguments %1..%n, its \$SETLOCAL and \$SET (scoped) variables."
struct GLevel
    file::String
    args::Vector{String}
    locals::Dict{String,String}
    scoped::Dict{String,String}
end

"The state of a GAMS compilation (one TIMES run up to maindrv.mod)."
mutable struct GamsCompile
    globals::Dict{String,String}      # $SETGLOBAL (names upper case)
    stack::Vector{GLevel}
    syms::Dict{String,GSym}           # upper-case name => symbol
    nsym::Int
    labels::LabelTable
    onmulti::Bool
    onempty::Bool
    oneps::Bool
    onwarning::Bool
    warnings::Int                     # compile warnings (domain violations under $ONWARNING; G54)
    warnlog::Vector{String}
    exec::Vector{Tuple{String,Int,String}}    # executable statements queued: file, line, text
    dirs::Vector{String}              # include search path after the including file's folder
    done::Bool                        # reached $BATINCLUDE maindrv.mod
    licencelevel::Int                 # %SYSTEM.LICENSELEVEL% (run option; docs/m14-plan.md, decision 1 of #84)
end

function GamsCompile(; dirs=String[], licencelevel::Int=0)
    GamsCompile(Dict{String,String}(), GLevel[], Dict{String,GSym}(), 0, LabelTable(),
        false, false, false, false, 0, String[], Tuple{String,Int,String}[], String.(dirs), false, licencelevel)
end

compile_error(file, line, msg) = throw(DDSyntaxError(file, line, msg))

# ---- compile-time variables ---------------------------------------------------------------------

# %name%: a local of the current level, then a scoped variable of this or an enclosing level, then a
# global (GAMS manual, "Compile-Time Variables": local, scoped and global, searched in that order)
function gvar(g::GamsCompile, name::AbstractString)
    k = uppercase(name)
    isempty(g.stack) || haskey(g.stack[end].locals, k) && return g.stack[end].locals[k]
    for l in Iterators.reverse(g.stack)
        haskey(l.scoped, k) && return l.scoped[k]
    end
    get(g.globals, k, nothing)
end
gisset(g::GamsCompile, name) = gvar(g, name) !== nothing

const G_SYSTEM = Dict("SYSTEM.TITLE" => "TIMES", "SYSTEM.INCPARENT" => "")

# Substitute %name% (defined names only; an undefined one stays as written) and %1..%9 (arguments of
# the current include level; a missing argument is empty, as in GAMS)
function gsubst(g::GamsCompile, s::AbstractString)
    occursin('%', s) || return String(s)
    s = replace(s, r"%([A-Za-z_][A-Za-z0-9_.]*)%" => function (m)
        n = m[2:end-1]
        u = uppercase(n)
        u == "SYSTEM.LICENSELEVEL" && return string(g.licencelevel)
        haskey(G_SYSTEM, u) && return G_SYSTEM[u]
        v = gvar(g, n)
        v === nothing ? m : v
    end)
    replace(s, r"%([1-9])" => function (m)
        i = parse(Int, m[2:end])
        args = isempty(g.stack) ? String[] : g.stack[end].args
        i <= length(args) ? args[i] : ""
    end)
end

# the value of $SET name value: a quoted value loses its quotes, and what follows it on the line is
# another dollar command ($SETGLOBAL RETIRE 'YES' SETGLOBAL DSCAUTO Yes, initmty.mod L454)
function gsetvalue(rest::AbstractString)
    rest = lstrip(rest)
    if !isempty(rest) && (rest[1] == '\'' || rest[1] == '"')
        q = rest[1]
        j = findnext(q, rest, 2)
        j === nothing && return (String(rest[2:end]), "")
        return (String(rest[2:prevind(rest, j)]), String(strip(rest[nextind(rest, j):end])))
    end
    (String(rstrip(rest)), "")
end

# ---- symbols and data ---------------------------------------------------------------------------

# "*", or an alias of it (ITEM, initsys.mod L33): no domain check
guniverse(g::GamsCompile, d::AbstractString) = d == "*" || (x = get(g.syms, uppercase(d), nothing); x !== nothing && x.kind === :alias && x.alias == "*")

function gsym(g::GamsCompile, name::AbstractString)
    s = get(g.syms, uppercase(name), nothing)
    s !== nothing && s.kind === :alias && return gsym(g, s.alias)
    s
end

function gdeclare!(g::GamsCompile, kind::Symbol, name::AbstractString, domain, text, file, line)
    k = uppercase(name)
    s = get(g.syms, k, nothing)
    if s === nothing
        g.nsym += 1
        s = GSym(String(name), kind, g.nsym)
        g.syms[k] = s
    else
        # $ONMULTI lets a symbol be declared again; without it GAMS stops (error 150)
        (s.kind === kind || (kind === :parameter && s.kind === :scalar) || (kind === :scalar && s.kind === :parameter)) ||
            compile_error(file, line, "$name declared again as a $(kind), it is a $(s.kind)")
    end
    if !isempty(domain)
        if isempty(s.domain)
            s.domain = [guniverse(g, d) ? (d == "*" ? "*" : g.syms[uppercase(d)].name) :
                        (x = gsym(g, d); x === nothing ? compile_error(file, line, "unknown domain set $d of $name") : x.name) for d in domain]
            s.dim = length(domain)
        else
            length(domain) == length(s.domain) || compile_error(file, line, "$name declared again with $(length(domain)) dimensions, not $(length(s.domain))")
        end
    end
    kind === :scalar && (s.dim = 0)
    # the first non-blank text is kept (ALL_TS: demo12_ts.dd none, initsys.mod L49; UNIT: initmty.dsc, not .vda)
    isempty(strip(s.text)) && !isempty(strip(text)) && (s.text = String(text))
    s
end

function galias!(g::GamsCompile, names, file, line)
    target = names[1]
    t = target == "*" ? nothing : gsym(g, target)
    target == "*" || t !== nothing || compile_error(file, line, "ALIAS of an unknown set $target")
    for n in names[2:end]
        k = uppercase(n)
        haskey(g.syms, k) && (g.syms[k].kind === :alias || compile_error(file, line, "ALIAS $n: already a $(g.syms[k].kind)"))
        haskey(g.syms, k) && continue
        g.nsym += 1
        s = GSym(String(n), :alias, g.nsym)
        s.alias = target == "*" ? "*" : t.name
        s.dim = 1
        s.domain = target == "*" ? ["*"] : t.domain
        g.syms[k] = s
    end
end

# members of a 1-dimensional set, as canonical labels (for domain checks)
gmembers1(s::GSym) = Set(k[1] for k in keys(s.members) if length(k) == 1)

# Apply one data statement. Labels enter the label list in the order they are read; a record whose
# label is outside a domain set is dropped with a warning under $ONWARNING (GAMS error 170 as a
# warning), and is an error without it (G32). The domain sets are taken as they stand at this point.
function gdata!(g::GamsCompile, s::GSym, recs::Vector{DDRecord}, file, line)
    s.hasdata && !g.onmulti && !isempty(recs) && compile_error(file, line, "data for $(s.name) given twice without \$ONMULTI")
    s.hasdata = true
    doms = [guniverse(g, d) ? nothing : gmembers1(gsym(g, d)) for d in s.domain]
    for r in recs
        if r.special === :setref
            src = gsym(g, r.labels[1])
            src === nothing && compile_error(file, r.line, "SET.$(r.labels[1]): unknown set")
            for (k, t) in sort!(collect(src.members); by=x -> [labelpos(g.labels, l) for l in x[1]])
                gput!(g, s, k, t, (NaN, :none), doms, file, r.line)
            end
            continue
        end
        key = [intern!(g.labels, l) for l in r.labels]
        gput!(g, s, key, r.text, (r.value, r.special), doms, file, r.line)
    end
end

function gput!(g::GamsCompile, s::GSym, key::Vector{String}, text, val, doms, file, line)
    if s.dim < 0
        s.dim = length(key)
    elseif length(key) != s.dim
        compile_error(file, line, "$(s.name) has $(s.dim) dimensions, a record has $(length(key))")
    end
    for (i, d) in enumerate(doms)
        d === nothing && continue
        if !(key[i] in d)
            g.onwarning || compile_error(file, line, "domain violation for $(s.name): $(join(key, '.'))")
            g.warnings += 1
            push!(g.warnlog, "$file:$line: domain violation for $(s.name): $(join(key, '.'))")
            return
        end
    end
    if s.kind === :set
        # a member given again takes its new text (OTNYC COM_DESC: base.dd, then techelc.dd, whose text
        # GAMS keeps); a blank new text keeps the old one (UNCONFIRMED: no suite model shows that case)
        old = get(s.members, key, nothing)
        s.members[key] = old === nothing || !isempty(strip(text)) ? String(text) : old
    else
        v, sp = val
        if sp === :none && v == 0.0
            # a zero in data: EPS under $ONEPS; otherwise not stored (and an earlier value removed:
            # UNCONFIRMED for a data statement under $ONMULTI)
            g.oneps ? (s.vals[key] = (0.0, :eps)) : delete!(s.vals, key)
        else
            s.vals[key] = (v, sp)
        end
    end
end

# ---- statements ---------------------------------------------------------------------------------

function gstatements!(g::GamsCompile, text::AbstractString, file, firstline; source::Bool)
    items = parse_dd(text; file, source, firstline)
    for it in items
        if it isa DDSymbol && it.kind === :set && guniverse(g, it.name)
            # data for an alias of the universe (SET ITEM / "%FIXBOH%", ... /, initmty.mod L440;
            # SET ITEM / OBJ /, initmty.vda L72): the labels enter the label list, nothing else
            for r in it.records, l in r.labels
                intern!(g.labels, l)
            end
        elseif it isa DDSymbol
            s = gdeclare!(g, it.kind, it.name, it.domain, it.text, it.file, it.line)
            it.hasdata && gdata!(g, s, it.records, it.file, it.line)
        elseif it isa DDAlias
            galias!(g, it.names, it.file, it.line)
        elseif it isa DDOther
            it.keyword == "EXEC" && push!(g.exec, (basename(it.file), it.line, it.text))
            # OPTION statements do not change data
        else
            compile_error(it.file, it.line, "a dollar line inside a statement block")   # not reached
        end
    end
end

# ---- files and dollar lines ---------------------------------------------------------------------

function gfind(g::GamsCompile, name::AbstractString, from::AbstractString)
    for d in [dirname(from); g.dirs]
        p = joinpath(d, name)
        isfile(p) && return p
    end
    nothing
end

"""
    gams_compile!(g, runfile) -> g

Compile a TIMES run file as GAMS does, up to `\$BATINCLUDE maindrv.mod`, then run the queued
executable statements. `g.dirs` must hold the TIMES source folder (GAMS's `idir`).
"""
function gams_compile!(g::GamsCompile, runfile::AbstractString)
    ginclude!(g, runfile, String[])
    g.done || compile_error(runfile, 0, "the run file does not reach \$BATINCLUDE maindrv.mod")
    run_exec!(g)
    g
end

function ginclude!(g::GamsCompile, path::AbstractString, args::Vector{String})
    push!(g.stack, GLevel(String(path), args, Dict{String,String}(), Dict{String,String}()))
    lines = split(read(path, String), '\n')
    i = 1
    n = length(lines)
    block = IOBuffer()
    bstart = 1
    flush!() = begin
        t = String(take!(block))
        isempty(strip(t)) || gstatements!(g, gsubst(g, t), path, bstart; source=gsource(path))
    end
    while i <= n && !g.done
        l = lines[i]
        # a line that starts with %1 (err_stat.mod L41) may become a dollar line once substituted
        startswith(l, '%') && (l = gsubst(g, l))
        if startswith(l, '$')
            flush!()
            # options without arguments may share a line ($ onlisting ontext, initsys.mod L5);
            # $ONTEXT starts a comment block that ends at $OFFTEXT
            rest = String(rstrip(l[2:end], '\r'))
            ontext = false
            while (m = match(r"^\s*(\w+)\s*(.*)$"s, rest)) !== nothing && uppercase(m[1]) in G_NOARG
                u = uppercase(m[1])
                u == "ONTEXT" ? (ontext = true) : gdollar!(g, u, path, i)
                rest = m[2]
            end
            if ontext
                i += 1
                while i <= n && !occursin(r"^\$\s*offtext"i, lines[i])
                    i += 1
                end
                i += 1
                bstart = i
                continue
            end
            jump = gdollar!(g, gsubst(g, rest), path, i)
            if jump !== nothing
                # $GOTO: forward to $LABEL name
                j = findnext(x -> occursin(Regex("^\\\$\\s*label\\s+" * jump * "\\s*\$", "i"), rstrip(x, '\r')), lines, i + 1)
                j === nothing && compile_error(path, i, "\$GOTO $jump: no \$LABEL")
                i = j
            end
            i += 1
            bstart = i
        else
            write(block, l, '\n')
            i += 1
        end
    end
    g.done || flush!()
    pop!(g.stack)
end

# TIMES's own files are read in source mode; the model's DD files in DD mode
gsource(path) = lowercase(splitext(path)[2]) in (".mod", ".def", ".dsc", ".vda", ".gms")

# One dollar line (without the '$', switches substituted). Returns a label name for $GOTO, else nothing.
function gdollar!(g::GamsCompile, s::AbstractString, file, line)
    s = strip(s)
    isempty(s) && return nothing
    m = match(r"^(\S+)\s*(.*)$"s, s)
    cmd, rest = uppercase(m[1]), m[2]
    if cmd in ("SET", "SETGLOBAL", "SETLOCAL")
        nm = match(r"^(\S+)\s*(.*)$"s, rest)
        nm === nothing && compile_error(file, line, "\$$cmd without a name")
        v, more = gsetvalue(nm[2])
        k = uppercase(nm[1])
        target = cmd == "SETGLOBAL" ? g.globals : cmd == "SETLOCAL" ? g.stack[end].locals : g.stack[end].scoped
        target[k] = v
        # a global of the same name hides no longer behind a scoped one, and vice versa: GAMS keeps one
        # name in one scope (UNCONFIRMED for a name set in two scopes; none of the TIMES files does)
        isempty(more) || return gdollar!(g, more, file, line)
    elseif cmd in ("IF", "IFI", "IFE")
        ok, tail = gcondition(g, rest, cmd == "IFI", file, line)
        ok || return nothing
        tail = strip(tail)
        isempty(tail) && return nothing
        if startswith(tail, '$')
            return gdollar!(g, tail[2:end], file, line)
        end
        gstatements!(g, tail, file, line; source=true)
    elseif cmd in ("BATINCLUDE", "INCLUDE")
        parts = gargs(rest)
        isempty(parts) && compile_error(file, line, "\$$cmd without a file")
        f = parts[1]
        if lowercase(basename(f)) == "maindrv.mod"
            g.done = true
            return nothing
        end
        lowercase(basename(f)) == "main_ext.mod" && return (main_ext!(g, parts[2:end], file, line); nothing)
        p = gfind(g, f, file)
        p === nothing && compile_error(file, line, "\$$cmd: $f not found")
        lowercase(basename(f)) in G_REFUSED_INCLUDES && throw(UnportedError("$(basename(f)) (\$$cmd at $(basename(file)) L$line)"))
        ginclude!(g, p, cmd == "BATINCLUDE" ? String.(parts[2:end]) : String[])
    elseif cmd == "KILL"
        for n in split(rest, r"[\s,]+"; keepempty=false)
            x = gsym(g, n)
            x === nothing && continue
            empty!(x.members); empty!(x.vals)
        end
    elseif cmd in ("ONMULTI", "OFFMULTI")
        g.onmulti = cmd == "ONMULTI"
    elseif cmd in ("ONEMPTY", "OFFEMPTY")
        g.onempty = cmd == "ONEMPTY"
    elseif cmd in ("ONEPS", "OFFEPS")
        g.oneps = cmd == "ONEPS"
    elseif cmd in ("ONWARNING", "OFFWARNING")
        g.onwarning = cmd == "ONWARNING"
    elseif cmd in ("OFFLISTING", "ONLISTING", "TITLE", "STITLE", "PHANTOM", "ONSYMLIST", "OFFSYMLIST", "ONUELLIST", "OFFUELLIST", "LABEL")
        # listing and layout only
    elseif cmd == "GOTO"
        return String(strip(rest))
    elseif cmd == "ABORT"
        compile_error(file, line, "\$ABORT $(strip(rest))")
    else
        compile_error(file, line, "the dollar control \$$cmd is outside what TIMES.jl reads")
    end
    nothing
end

# dollar options without arguments (several may share a line)
const G_NOARG = Set(["ONTEXT", "ONLISTING", "OFFLISTING", "ONMULTI", "OFFMULTI", "ONEMPTY", "OFFEMPTY", "ONEPS",
    "OFFEPS", "ONWARNING", "OFFWARNING", "ONSYMLIST", "OFFSYMLIST", "ONUELLIST", "OFFUELLIST"])

# the files GAMS would include here that TIMES.jl refuses (docs/m14-plan.md)
const G_REFUSED_INCLUDES = Set(["initmty.stc", "initmty.tm"])

# the arguments of $BATINCLUDE: blank-separated, quoted ones kept whole
gargs(s) = [m[1] !== nothing ? m[1] : m[2] !== nothing ? m[2] : m[3] for m in eachmatch(r"'([^']*)'|\"([^\"]*)\"|(\S+)", s)]

# $IF [NOT] condition rest: SET name, EXIST file, a==b (IFI: case-insensitive), gamsversion n,
# FUNTYPE name, ERRORFREE, WARNINGS (G54). Returns (true/false, the rest of the line).
function gcondition(g::GamsCompile, s::AbstractString, ci::Bool, file, line)
    s = lstrip(s)
    neg = false
    if (m = match(r"^not\s+"i, s)) !== nothing
        neg = true
        s = s[length(m.match)+1:end]
    end
    ok, rest = gcondition1(g, s, ci, file, line)
    (xor(ok, neg), rest)
end

function gcondition1(g::GamsCompile, s::AbstractString, ci::Bool, file, line)
    if (m = match(r"^(set|setglobal|setlocal)\s+(\S+)\s*(.*)$"is, s)) !== nothing
        w = lowercase(m[1])
        k = uppercase(m[2])
        ok = w == "set" ? gisset(g, m[2]) : w == "setglobal" ? haskey(g.globals, k) : haskey(g.stack[end].locals, k)
        return (ok, m[3])
    elseif (m = match(r"^(declared|defined)\s+(\S+)\s*(.*)$"is, s)) !== nothing
        # DECLARED: the symbol exists; DEFINED: it also has a data statement (G35: whether an empty
        # list // counts is UNCONFIRMED; it counts here, as a data statement)
        x = get(g.syms, uppercase(m[2]), nothing)
        ok = x !== nothing && (lowercase(m[1]) == "declared" || x.kind === :alias || x.hasdata)
        return (ok, m[3])
    elseif (m = match(r"^exist\s+(\S+)\s*(.*)$"is, s)) !== nothing
        return (gfind(g, m[1], file) !== nothing, m[2])
    elseif (m = match(r"^gamsversion\s+(\d+)\s*(.*)$"is, s)) !== nothing
        return (true, m[2])          # GAMS 54 (CLAUDE.md): later than every version TIMES tests
    elseif (m = match(r"^funtype\s+\S+\s*(.*)$"is, s)) !== nothing
        return (true, m[1])
    elseif (m = match(r"^errorfree\s*(.*)$"is, s)) !== nothing
        return (true, m[1])
    end
    # a == b: each side quoted, or a run of non-blank characters
    tok = r"^\s*('([^']*)'|\"([^\"]*)\"|([^\s=]*))\s*==\s*('([^']*)'|\"([^\"]*)\"|(\S*))\s*(.*)$"s
    m = match(tok, s)
    m === nothing && compile_error(file, line, "a \$IF condition outside what TIMES.jl reads: $s")
    a = something(m[2], m[3], m[4], "")
    b = something(m[6], m[7], m[8], "")
    ok = ci ? lowercase(a) == lowercase(b) : a == b
    (ok, m[9])
end

# main_ext.mod L1-23: include `<stage>.<ext>` for each extension named after the stage (once each),
# with the extension and the calling file's name as arguments
function main_ext!(g::GamsCompile, args, file, line)
    isempty(args) && return
    stage = args[1]
    parent = splitext(basename(file))[1]
    seen = Set{String}()
    for ext in args[2:end]
        isempty(ext) && continue
        u = uppercase(ext)
        u in seen && continue
        p = gfind(g, "$(stage).$(lowercase(ext))", file)
        p === nothing || ginclude!(g, p, [String(ext), parent])
        push!(seen, u)
    end
end

# ---- the executable statements before maindrv.mod -----------------------------------------------

"""
The executable statements GAMS compiles before maindrv.mod, translated by hand, keyed by file and
line. They run after compilation, in program order, as GAMS runs them.
"""
const INIT_EXEC = Dict{Tuple{String,Int},Function}()

# err_stat.mod L51: IF(execerror, PUT END_GAMS ...; PUTCLOSE): no data effect (execerror is 0 here)
INIT_EXEC[("err_stat.mod", 51)] = (g, text) -> nothing

# initsys.mod L43: YEARVAL(ALLYEAR) = %BOTIME% + ORD(ALLYEAR)-1, over ALLYEAR as it stands at execution
# (with the year 0 that L79 adds last)
INIT_EXEC[("initsys.mod", 43)] = function (g, text)
    m = match(r"=\s*(-?\d+)\s*\+", text)
    m === nothing && error("initsys.mod L43: unexpected text $(repr(text))")
    bo = parse(Int, m[1])
    ay, yv = gsym(g, "ALLYEAR"), gsym(g, "YEARVAL")
    for (i, k) in enumerate(gsorted(g, ay))
        v = Float64(bo + i - 1)
        v == 0 ? delete!(yv.vals, k) : (yv.vals[k] = (v, :none))
    end
end
# initmty.mod L368: YEARVAL('%DFLBL%') = 0;
INIT_EXEC[("initmty.mod", 368)] = function (g, text)
    m = match(r"YEARVAL\('([^']*)'\)\s*=\s*0"i, text)
    m === nothing && error("initmty.mod L368: unexpected text $(repr(text))")
    delete!(gsym(g, "YEARVAL").vals, [intern!(g.labels, m[1])])
end
# initmty.mod L369: Z=SUM(LASTLL(LL),ORD(LL)); ABORT$(Z NE CARD(LL)) 'FATAL';
INIT_EXEC[("initmty.mod", 369)] = function (g, text)
    if startswith(uppercase(strip(text)), "Z")
        ll = gsorted(g, gsym(g, "ALLYEAR"))
        last = collect(keys(gsym(g, "LASTLL").members))
        z = sum((findfirst(==(k), ll) for k in last); init=0)
        gsym(g, "Z").vals[String[]] = (Float64(z), :none)
    else
        z = first(gsym(g, "Z").vals[String[]])
        z == length(gsym(g, "ALLYEAR").members) || error("initmty.mod L369: ABORT 'FATAL' (the last year is not last)")
    end
end

# a set's members in GAMS order (by label positions)
gsorted(g::GamsCompile, s::GSym) = sort!(collect(keys(s.members)); by=k -> [labelpos(g.labels, l) for l in k])

function run_exec!(g::GamsCompile)
    for (f, l, t) in g.exec
        fn = get(INIT_EXEC, (f, l), nothing)
        fn === nothing && throw(UnportedError("executable statement at $f L$l: $(first(replace(t, r"\s+" => " "), 80))"))
        fn(g, t)
    end
end

# ---- the result, as the input dump holds it -----------------------------------------------------

"A compiled symbol's records in GAMS order: keys, and the values (parameters) or element text (sets)."
function grecords(g::GamsCompile, s::GSym)
    lp(k) = [labelpos(g.labels, l) for l in k]
    if s.kind === :set
        ks = sort!(collect(keys(s.members)); by=lp)
        return ks, [s.members[k] for k in ks]
    end
    # a scalar (0 dimensions) always has its record, 0 when no value was given
    s.dim == 0 && return [String[]], [get(s.vals, String[], (0.0, :none))]
    ks = sort!(collect(keys(s.vals)); by=lp)
    ks, [s.vals[k] for k in ks]
end

"""
    gdx_uels(g) -> Vector{String}

The label list of the input dump: GDX lists a label where `execute_unload` first writes it, going
through the symbols in declaration order and each symbol's records in GAMS order. That is not GAMS's
own label order (initsys.mod: GAMS has EOH before 0, the dump 0 before EOH; docs/discrepancies.md).
"""
function gdx_uels(g::GamsCompile)
    seen = Set{String}()
    out = String[]
    for s in sort!([s for s in values(g.syms) if s.kind in (:set, :parameter, :scalar)]; by=x -> x.order)
        ks, _ = grecords(g, s)
        for k in ks, l in k
            l in seen || (push!(seen, l); push!(out, l))
        end
    end
    out
end
