# M1.4 changes 2-4 and 2b: GAMS's compile phase for a TIMES run, the whole program.
#
# GAMS: the .run file, initsys.mod L17-187 (with units.def, maplists.def, globals.def), initmty.mod
# L19-508, main_ext.mod L1-23 and the extension declarations initmty.dsc, initmty.vda; v4.9.7. With
# `full=true` (change 2b) also maindrv.mod and every file it includes, for their declarations and
# compile-time data: GAMS compiles the whole program before it runs any of it, so the input dump
# holds every symbol TIMES declares and the data its later files give at compile time. Their
# executable statements run after the input checkpoint, in TIMES.jl's own translation, so are skipped.
# The run file and the TIMES files are read with src/dd/ddparse.jl; this file does what the GAMS
# compiler does with them, in order: the dollar-control lines ($SET, $IF, $BATINCLUDE, $KILL, $ONEPS,
# ...), the declarations (with $ONMULTI), the data statements (domain checks, $ONEPS, label order),
# and it queues the executable statements, which run when compilation ends, as GAMS runs them, by the
# hand-written Julia in `INIT_EXEC` (each cites its line). The result is what the harness's input
# dump holds (`execute_unload` just before maindrv.mod): every symbol, its records, and the labels;
# `g.trace` is the listing's Include File Summary, checked against GAMS's by scripts/m14_probe.jl.
#
# Known gap: an assignment compiled after maindrv.mod makes its symbol DEFINED for a later
# `$IF DEFINED` (G35); the reader marks only data statements and macros. No open suite model's
# include trace depends on it (every one matches GAMS's); to be closed with a GAMS experiment.
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
    done::Bool                        # reached $BATINCLUDE maindrv.mod (or, with `full`, the end of the run file)
    licencelevel::Int                 # %SYSTEM.LICENSELEVEL% (run option; docs/m14-plan.md, decision 1 of #84)
    full::Bool                        # compile maindrv.mod and what it includes too (change 2b)
    later::Bool                       # past `$BATINCLUDE maindrv.mod`: executable statements are not queued
    pending::String                   # a statement of TIMES code still open at a dollar line
    pendline::Int
    eolcom::String                    # $EOLCOM marker ("" when off)
    trace::Vector{Tuple{Int,String}}  # the files included: level, name (the listing's Include File Summary)
    macros::Set{String}               # $MACRO names (upper case): DECLARED and DEFINED hold for them (VNRET)
    refs::Set{String}                 # names compiled code refers to (G57: GDX leaves out unreferenced variables)
end

function GamsCompile(; dirs=String[], licencelevel::Int=0, full::Bool=false)
    GamsCompile(Dict{String,String}(), GLevel[], Dict{String,GSym}(), 0, LabelTable(),
        false, false, false, false, 0, String[], Tuple{String,Int,String}[], String.(dirs), false, licencelevel,
        full, false, "", 0, "", Tuple{Int,String}[], Set{String}(), Set{String}())
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

# Substitute %name% (defined names only; an undefined one stays as written) and %1, %2, ..., %12
# (arguments of the current include level, any number of digits: uc_flo.mod L27 has %11 and %12; a
# missing argument is empty, as in GAMS)
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
    replace(s, r"%([1-9][0-9]*)" => function (m)
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
    # the set is the name that exists (or *), in any position: ALIAS(LIFE,AGE), setglobs.gms L283
    ti = findfirst(n -> n == "*" || (x = get(g.syms, uppercase(n), nothing); x !== nothing && x.kind !== :alias), names)
    ti === nothing && (ti = findfirst(n -> haskey(g.syms, uppercase(n)), names))
    ti === nothing && compile_error(file, line, "ALIAS of unknown sets $(join(names, ", "))")
    target = names[ti]
    t = target == "*" ? nothing : gsym(g, target)
    for (j, n) in enumerate(names)
        j == ti && continue
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
        if sp === :none && v == 0.0 && isempty(key)
            # a scalar's 0 stays 0 under $ONEPS (ACL, ERRLEV, ... in the input dumps)
            s.vals[key] = (0.0, :none)
        elseif sp === :none && v == 0.0
            # a zero in data: EPS under $ONEPS; otherwise not stored (and an earlier value removed:
            # UNCONFIRMED for a data statement under $ONMULTI)
            g.oneps ? (s.vals[key] = (0.0, :eps)) : delete!(s.vals, key)
        else
            s.vals[key] = (v, sp)
        end
    end
end

# ---- statements ---------------------------------------------------------------------------------

function gstatements!(g::GamsCompile, text::AbstractString, file, firstline; source::Bool, final::Bool=false)
    # TIMES code: a statement still open at the end (it goes on after a dollar line) waits in g.pending
    if source
        text = g.pending * text
        firstline = isempty(g.pending) ? firstline : g.pendline
        g.pending = ""
    end
    rest = source && !final ? Ref(("", 0)) : nothing
    items = parse_dd(text; file, source, firstline, rest)
    if source && !isempty(first(rest[]))
        g.pending, g.pendline = rest[]
    end
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
            # a MODEL statement does not count as naming its equations (G57)
            it.keyword in ("MODEL", "MODELS") || gnoterefs!(g, it.text)
            # executable statements before maindrv.mod run after compilation (INIT_EXEC); those after it
            # run after the input checkpoint, in TIMES.jl's own translation (M1.1-M1.3), so are skipped
            it.keyword == "EXEC" && !g.later && push!(g.exec, (basename(it.file), it.line, it.text))
            # OPTION, MODEL, FILE statements do not change data
        else
            compile_error(it.file, it.line, "a dollar line inside a statement block")   # not reached
        end
    end
end

# ---- files and dollar lines ---------------------------------------------------------------------

function gfind(g::GamsCompile, name::AbstractString, from::AbstractString)
    # a file named without an extension is looked for as `name.gms` (GAMS's default; setglobs, maindrv.mod L23)
    names = isempty(splitext(name)[2]) ? [name * ".gms", name] : [name]
    for d in [dirname(from); g.dirs], n in names
        p = joinpath(d, n)
        isfile(p) && return p
    end
    # GAMS on Windows, where the references run, finds a file whatever the case of its name; so does
    # the reader on any system, so a run file written on Windows compiles on Linux (M1.4 change 2c)
    for d in [dirname(from); g.dirs], n in names
        dir = joinpath(d, dirname(n))
        isdir(dir) || continue
        m = findfirst(f -> lowercase(f) == lowercase(basename(n)), readdir(dir))
        m === nothing || return joinpath(dir, readdir(dir)[m])
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
    g.full ? (g.done = true) : (g.done || compile_error(runfile, 0, "the run file does not reach \$BATINCLUDE maindrv.mod"))
    # a declaration still open at the end of the program is complete (no ';' needed before the end)
    isempty(strip(g.pending)) || gstatements!(g, "", runfile, g.pendline; source=true, final=true)
    run_exec!(g)
    g
end

function ginclude!(g::GamsCompile, path::AbstractString, args::Vector{String})
    push!(g.stack, GLevel(String(path), args, Dict{String,String}(), Dict{String,String}()))
    push!(g.trace, (length(g.stack) - 1, basename(path)))
    eolcom = g.eolcom                 # $EOLCOM holds for the file that sets it and what it includes
    lines = split(read(path, String), '\n')
    i = 1
    n = length(lines)
    block = IOBuffer()
    bstart = 1
    flush!() = begin
        t = String(take!(block))
        # after maindrv.mod the run file is TIMES code too (the harness's TJL_SOLVEINFO statements)
        isempty(strip(t)) || gstatements!(g, gsubst(g, t), path, bstart; source=gsource(path) || g.later)
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
            jump === :exit && break       # $EXIT: the rest of this file is not read
            if jump isa Tuple
                # code from a $IF line: the start of the next block
                i += 1
                bstart = i - 1
                write(block, isempty(g.eolcom) ? jump[2] : gstripeol(jump[2], g.eolcom), '\n')
                continue
            end
            if jump === :skipnext
                i += 2
                bstart = i
                continue
            end
            if jump !== nothing
                # $GOTO: to $LABEL name, forward first, then from the top (main_ext.mod's loop goes back)
                # the label name may be followed by more text ($LABEL EQUA %2, eqobjfix.mod L178)
                isl(x) = occursin(Regex("^\\\$\\s*label\\s+" * jump * "(\\s|\$)", "i"), rstrip(x, '\r'))
                j = something(findnext(isl, lines, i + 1), findfirst(isl, lines), 0)
                j == 0 && compile_error(path, i, "\$GOTO $jump: no \$LABEL")
                i = j
            end
            i += 1
            bstart = i
        else
            write(block, isempty(g.eolcom) ? l : gstripeol(l, g.eolcom), '\n')
            i += 1
        end
    end
    g.done || flush!()
    pop!(g.stack)
    g.eolcom = eolcom
end

# a code line without its end-of-line comment ($EOLCOM marker outside quotes)
function gstripeol(l::AbstractString, m::AbstractString)
    occursin(m, l) || return l
    q = '\0'
    i = firstindex(l)
    while i <= lastindex(l)
        c = l[i]
        if q != '\0'
            c == q && (q = '\0')
        elseif c == '\'' || c == '"'
            q = c
        elseif startswith(SubString(l, i), m)
            return l[firstindex(l):prevind(l, i)]
        end
        i = nextind(l, i)
    end
    l
end

# TIMES's own files are read in source mode; the model's DD files in DD mode
gsource(path) = !(lowercase(splitext(path)[2]) in (".dd", ".run"))

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
    elseif cmd in ("IF", "IFI")
        ok, tail = gcondition(g, rest, cmd == "IFI", file, line)
        return gtail!(g, ok, tail, file, line)
    elseif cmd == "IFE"
        ok, tail = gife(g, rest, file, line)
        return gtail!(g, ok, tail, file, line)
    elseif cmd in ("BATINCLUDE", "INCLUDE")
        parts = gargs(rest)
        isempty(parts) && compile_error(file, line, "\$$cmd without a file")
        f = parts[1]
        if lowercase(basename(f)) == "maindrv.mod"
            if !g.full
                # stop here; a declaration still open before maindrv.mod is complete
                isempty(strip(g.pending)) || gstatements!(g, "", file, g.pendline; source=true, final=true)
                g.done = true
                return nothing
            end
            g.later = true
        end
        lowercase(basename(f)) == "main_ext.mod" && return (main_ext!(g, parts[2:end], file, line); nothing)
        if lowercase(splitext(basename(f))[1]) == "gdxfilter" && !isempty(parts) && length(parts) >= 2 && uppercase(parts[2]) == "MAIN"
            # setglobs.gms L13 (%DATAGDX% YES and compile warnings): gdxfilter.gms MAIN reloads all data
            # from the _dd_.gdx it wrote (L12-14), with $onFiltered, so the reload drops the records
            # outside their domains, which the compile has dropped already (G56; the TIMES-NZ input dumps
            # match without it). Its includes are traced as GAMS lists them: itself, then _dd_.dd (L12);
            # the listing shows no second gdxfilter.gms for the $ONRECURSE line (L11).
            lv = length(g.stack)
            append!(g.trace, [(lv, "gdxfilter.gms"), (lv + 1, "_dd_.dd")])
            return nothing
        end
        p = gfind(g, f, file)
        p === nothing && compile_error(file, line, "\$$cmd: $f not found")
        lowercase(basename(f)) in G_REFUSED_INCLUDES && throw(UnportedError("$(basename(f)) (\$$cmd at $(basename(file)) L$line)"))
        ginclude!(g, p, cmd == "BATINCLUDE" ? String.(parts[2:end]) : String[])
    elseif cmd in ("KILL", "CLEAR")
        # compile-time removal of a symbol's data ($KILL also allows a new data statement; $CLEAR
        # resets to the defaults, which for sets and parameters is no records)
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
    elseif cmd in G_NOEFFECT
        # listing, layout, environment and compiler settings with no effect on the data
    elseif cmd == "EOLCOM"
        g.eolcom = String(strip(rest))
    elseif cmd == "MACRO"
        # a macro is expanded in executable code only, which TIMES.jl does not compile; its name counts
        # for $IF DECLARED and DEFINED (prepret.dsc L41 VNRET, tested at mod_vars.mod L94, eqobj.mod L39)
        mm = match(r"^\s*([A-Za-z_][A-Za-z0-9_]*)", rest)
        mm === nothing || push!(g.macros, uppercase(mm[1]))
        gnoterefs!(g, rest)
    elseif cmd == "SHIFT"
        isempty(g.stack[end].args) || popfirst!(g.stack[end].args)
        r = strip(rest)
        isempty(r) || return gdollar!(g, r, file, line)
    elseif cmd == "EXIT"
        return :exit
    elseif cmd == "SETNAMES"
        # $SETNAMES file pathvar namevar extvar ('.' = not set), as locals
        a = gargs(rest)
        length(a) == 4 || compile_error(file, line, "\$SETNAMES needs four arguments")
        f = a[1]
        for (v, x) in zip(a[2:4], (dirname(f), splitext(basename(f))[1], splitext(f)[2]))
            v == "." || (g.stack[end].locals[uppercase(v)] = x)
        end
    elseif cmd == "SETARGS"
        # names for the arguments; a name with no argument is set empty (setglobs.gms L13 is called
        # with one argument and tests '%X2%'=='' at L342)
        for (i, v) in enumerate(split(rest))
            g.stack[end].locals[uppercase(v)] = i <= length(g.stack[end].args) ? g.stack[end].args[i] : ""
        end
    elseif cmd == "GOTO"
        return String(strip(rest))
    elseif cmd == "ABORT" || cmd == "ERROR"
        compile_error(file, line, "\$$cmd $(strip(rest))")
    elseif cmd in ("GDXOUT", "UNLOAD") || (cmd == "GDXIN" && isempty(strip(rest)))
        # writing a GDX file at compile time (setglobs.gms L9-13) changes no data; $GDXIN alone closes one
    elseif cmd in ("EVAL", "EVALGLOBAL", "EVALLOCAL")
        nm = match(r"^(\S+)\s*(.*)$"s, rest)
        nm === nothing && compile_error(file, line, "\$$cmd without a name")
        expr, more = gsetvalue(nm[2])
        v = gevalnum(expr, file, line)
        target = cmd == "EVALGLOBAL" ? g.globals : cmd == "EVALLOCAL" ? g.stack[end].locals : g.stack[end].scoped
        target[uppercase(nm[1])] = isinteger(v) ? string(Int(v)) : string(v)
        isempty(more) || return gdollar!(g, more, file, line)
    elseif cmd == "HIDDENCALL"
        # a shell command (prepxtra.mod L91: renaming the saved GDX file): no data effect by itself; data
        # could only come back through $INCLUDE or $LOAD, which are read or refused on their own
    elseif cmd in ("GDXIN", "LOAD", "LOADDC", "LOADM", "LOADR", "CALL", "EXECUTE", "SETCOMPS")
        throw(UnportedError("\$$cmd ($(basename(file)) L$line)"))
    elseif startswith(cmd, "%")
        # a dollar line whose command is an undefined switch (maindrv.mod: `$ %MX% SETGLOBAL MX`):
        # no effect (UNCONFIRMED: GAMS compiles such lines without error in every suite run)
    else
        compile_error(file, line, "the dollar control \$$cmd is outside what TIMES.jl reads")
    end
    nothing
end

const G_NOEFFECT = Set(["OFFLISTING", "ONLISTING", "TITLE", "STITLE", "PHANTOM", "ONSYMLIST", "OFFSYMLIST",
    "ONUELLIST", "OFFUELLIST", "LABEL", "ONMIXED", "USE999", "SETENV", "ECHO", "ECHON", "ONRECURSE",
    "OFFRECURSE", "ONUNI", "OFFUNI", "HIDDEN", "OFFINCLUDE", "ONINCLUDE", "OFFUPPER", "ONUPPER", "LOG", "SHOW",
    "STARS", "SINGLE", "DOUBLE", "EJECT", "LINES", "ONDOLLAR", "OFFDOLLAR", "ONGLOBAL", "OFFGLOBAL", "DROP",
    "DROPLOCAL", "DROPGLOBAL", "ONVERBATIM", "OFFVERBATIM", "ONECHO", "OFFECHO"])

# what follows a true $IF condition: nothing, another dollar command, or TIMES code
function gtail!(g::GamsCompile, ok::Bool, tail, file, line)
    tail = strip(tail)
    # nothing after the condition: the condition governs the next line (eqobjfix.mod L205-207,
    # main_ext.mod L13-14, maindrv.mod L35-36); a false one skips it
    isempty(tail) && return ok ? nothing : :skipnext
    ok || return nothing
    startswith(tail, '$') && return gdollar!(g, tail[2:end], file, line)
    # TIMES code: it joins the code that follows, as a line in its place (prepret.dsc L45, `$ IF %MIP%
    # INTEGER`, puts INTEGER in front of the VARIABLE statement of L46)
    (:code, String(tail))
end

# $IFE [NOT] expression rest: a compile-time numeric test. The expressions TIMES writes use numbers,
# CARD(symbol) (its records at this point of compilation), + - * /, comparisons (= > < >= <= <>),
# NOT, AND, OR, and parentheses (eqmain.mod L197, init_ext.vda L135, gasgrids.vda, powerflo.vda L198)
function gife(g::GamsCompile, s::AbstractString, file, line)
    # the expression ends at the first blank outside parentheses that is followed by '$' or by text
    # not part of an expression; TIMES always writes it without inner blanks except after NOT
    s = lstrip(s)
    neg = false
    if (m = match(r"^not\s+"i, s)) !== nothing
        neg = true
        s = s[length(m.match)+1:end]
    end
    depth = 0
    j = lastindex(s) + 1
    for (k, c) in pairs(s)
        c == '(' && (depth += 1)
        c == ')' && (depth -= 1)
        if depth == 0 && isspace(c)
            j = k
            break
        end
    end
    expr, tail = s[firstindex(s):prevind(s, j)], j > lastindex(s) ? "" : s[j:end]
    v = gevalexpr(g, expr, file, line)
    (xor(v != 0, neg), tail)
end

function gevalexpr(g::GamsCompile, e::AbstractString, file, line)
    x = replace(e, r"CARD\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)"i => m -> begin
        n = match(r"\(\s*([A-Za-z_][A-Za-z0-9_]*)"i, m)[1]
        s = gsym(g, n)
        string(s === nothing ? 0 : s.kind === :set ? length(s.members) : (s.dim == 0 ? 1 : length(s.vals)))
    end)
    occursin(r"^[0-9+\-*/().<>=\s]*$", x) || compile_error(file, line, "an \$IFE expression outside what TIMES.jl reads: $e")
    x = replace(x, "<>" => "!=", ">=" => "≥", "<=" => "≤")
    x = replace(x, r"(?<![<>!≥≤=])=(?!=)" => "==")
    x = replace(x, "≥" => ">=", "≤" => "<=")
    v = eval(Meta.parse(x))
    v isa Bool ? Int(v) : v
end

# $EVAL expressions (prepxtra.mod L88-89: a timestamp for a file name): numbers, + - * / **, MOD,
# TRUNC, LOG10, and GYEAR/GMONTH/GDAY/GHOUR/GMINUTE/GSECOND of JSTART (now)
function gevalnum(e::AbstractString, file, line)
    tm = Libc.TmStruct(time())
    now = Dict("YEAR" => tm.year + 1900, "MONTH" => tm.month + 1, "DAY" => tm.mday, "HOUR" => tm.hour,
        "MINUTE" => tm.min, "SECOND" => tm.sec)
    x = replace(e, r"G(YEAR|MONTH|DAY|HOUR|MINUTE|SECOND)\(\s*JSTART\s*\)"i => m -> string(now[uppercase(match(r"^G([A-Za-z]+)"i, m)[1])]))
    x = replace(x, "**" => "^")
    x = replace(x, r"\bMOD\("i => "mod(", r"\bTRUNC\("i => "trunc(", r"\bLOG10\("i => "log10(")
    # only numbers, operators, parentheses and the three functions may remain
    occursin(r"^([0-9+\-*/^().,\s]|mod|trunc|log10)*$", x) ||
        compile_error(file, line, "an \$EVAL expression outside what TIMES.jl reads: $e")
    v = eval(Meta.parse(isempty(strip(x)) ? "0" : x))
    Float64(v)
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
        ok = uppercase(m[2]) in g.macros || (x !== nothing && (lowercase(m[1]) == "declared" || x.kind === :alias || x.hasdata))
        return (ok, m[3])
    elseif (m = match(r"^exist\s+(\S+)\s*(.*)$"is, s)) !== nothing
        return (gfind(g, m[1], file) !== nothing, m[2])
    elseif (m = match(r"^gamsversion\s+(\d+)\s*(.*)$"is, s)) !== nothing
        return (true, m[2])          # GAMS 54 (CLAUDE.md): later than every version TIMES tests
    elseif (m = match(r"^funtype\s+\S+\s*(.*)$"is, s)) !== nothing
        return (true, m[1])
    elseif (m = match(r"^dimension\s+(\d+)\s+(\S+)\s*(.*)$"is, s)) !== nothing
        x = gsym(g, m[2])
        return (x !== nothing && x.dim == parse(Int, m[1]), m[3])
    elseif (m = match(r"^(settype|partype|vartype|equtype|pretype)\s+(\S+)\s*(.*)$"is, s)) !== nothing
        # the symbol's type: a set, a parameter (scalars too), a variable, an equation, undeclared
        x = gsym(g, m[2])
        w = lowercase(m[1])
        k = x === nothing ? :none : x.kind
        ok = w == "settype" ? k === :set : w == "partype" ? k in (:parameter, :scalar) :
             w == "vartype" ? k === :variable : w == "equtype" ? k === :equation : k === :none
        return (ok, m[3])
    elseif (m = match(r"^warnings\s*(.*)$"is, s)) !== nothing
        return (g.warnings > 0, m[1])     # compile warnings so far (G54)
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

# main_ext.mod L1-23: include `<stage>.<ext>` (when the file exists) for each extension named after the
# stage, with the extension and the calling file's name as arguments, once each: L13 (`$IF NOT
# SETLOCAL %1`, nothing after it) governs the next line, the include.
function main_ext!(g::GamsCompile, args, file, line)
    isempty(args) && return
    stage = args[1]
    parent = splitext(basename(file))[1]
    push!(g.trace, (length(g.stack), "main_ext.mod"))
    push!(g.stack, GLevel(String(file), String[], Dict{String,String}(), Dict{String,String}()))
    seen = Set{String}()
    for ext in args[2:end]
        isempty(ext) && continue
        uppercase(ext) in seen && continue
        p = gfind(g, "$(stage).$(lowercase(ext))", file)
        p === nothing || ginclude!(g, p, [String(ext), parent])
        push!(seen, uppercase(ext))
    end
    pop!(g.stack)
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

# the names a statement (or a macro body) refers to
gnoterefs!(g::GamsCompile, text::AbstractString) =
    foreach(m -> push!(g.refs, uppercase(m.match)), eachmatch(r"[A-Za-z_][A-Za-z0-9_]*", text))

# ---- the result, as the input dump holds it -----------------------------------------------------

"""
    gdx_symbols(g) -> Vector{GSym}

The symbols `execute_unload` writes, in declaration order: every set, parameter and alias, every
variable and equation with a domain, and the scalar variables and equations that compiled code
refers to. GAMS leaves out a scalar variable or equation that no compiled statement names (VAS_EXPOBJ,
named only after eqobj.mod's `\$EXIT`); a MODEL statement does not count (G57, checked with
GAMS 54.6.1 on 9 and 10 Nov 2026).
"""
gdx_symbols(g::GamsCompile) =
    sort!([s for s in values(g.syms) if !(s.kind in (:variable, :equation)) || s.dim > 0 || uppercase(s.name) in g.refs];
          by=x -> x.order)

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
