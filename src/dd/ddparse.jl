# M1.4 change 1: a parser for the GAMS data files (.dd) and run files (.run) of TIMES models.
#
# GAMS: no TIMES source file. This reads the subset of GAMS syntax that TIMES DD and run files use
# (docs/m14-plan.md, "The DD files of the suite"): SET and PARAMETER statements with data lists,
# OPTION statements, comment lines, $ONTEXT/$OFFTEXT blocks and dollar-control lines. The GAMS
# compiler rules it follows are those of the GAMS 54 manual (Data Entry: Sets, Parameters; Dollar
# Control Options). Anything outside the subset stops with the file and line (DDSyntaxError), so a
# model that needs more syntax is found, not misread.
#
# The parser only reads: it keeps labels as written (quotes removed) and every statement in file
# order. What GAMS does with them ($ONEPS, $ONMULTI, domain checks, label order) is change 4; the
# run file's $SET/$IF/$BATINCLUDE are change 3.

"A GAMS syntax error, or syntax outside the subset TIMES.jl reads, at `file`:`line`."
struct DDSyntaxError <: Exception
    file::String
    line::Int
    msg::String
end
Base.showerror(io::IO, e::DDSyntaxError) = print(io, "DDSyntaxError: ", e.file, ":", e.line, ": ", e.msg)

"""
One record of a data list: the labels of its key as written (quotes removed), and either the value
(parameters) or the element text (sets). `special` marks a GAMS special value written in the data
(`:eps`, `:inf`, `:minf`, `:na`, `:undf`; `:none` for a plain number).
"""
struct DDRecord
    labels::Vector{String}
    value::Float64
    special::Symbol
    text::String
    line::Int
end

"""
One symbol of a SET or PARAMETER statement: its name, domain (empty when none is written), the
declaration text, and its data list when one is written (`hasdata`; an empty list `/ /` counts).
"""
struct DDSymbol
    kind::Symbol            # :set or :parameter
    name::String
    domain::Vector{String}
    text::String
    hasdata::Bool
    records::Vector{DDRecord}
    file::String
    line::Int
end

"A dollar-control line, without the `\$` and with surrounding blanks removed."
struct DDDirective
    text::String
    file::String
    line::Int
end

"A statement the reader keeps but does not interpret (OPTION), up to its `;`."
struct DDOther
    keyword::String
    text::String
    file::String
    line::Int
end

const DDItem = Union{DDSymbol,DDDirective,DDOther}

# keywords that open a statement; only SET(S) and PARAMETER(S) carry data here, OPTION(S) is kept as
# DDOther, the rest are refused (none occurs in the suite's DD and run files)
const DD_DATA_KEYWORDS = Dict("set" => :set, "sets" => :set, "parameter" => :parameter, "parameters" => :parameter)
const DD_OTHER_KEYWORDS = Set(["option", "options"])
const DD_REFUSED_KEYWORDS = Set(["scalar", "scalars", "table", "alias", "acronym", "acronyms", "singleton",
    "variable", "variables", "positive", "negative", "free", "binary", "integer", "equation", "equations",
    "model", "models", "solve", "display", "loop", "if", "while", "for", "repeat", "abort", "file", "files",
    "put", "putclose", "execute", "execute_unload", "execute_load", "function"])

mutable struct DDCursor
    b::Vector{UInt8}
    i::Int          # next byte
    line::Int       # line of byte i
    file::String
end
DDCursor(s::AbstractString, file) = DDCursor(Vector{UInt8}(codeunits(String(s))), 1, 1, String(file))

@inline ddpeek(c::DDCursor, k=0) = c.i + k <= length(c.b) ? c.b[c.i+k] : 0x00
@inline ddeof(c::DDCursor) = c.i > length(c.b)
@inline ddbol(c::DDCursor) = c.i == 1 || c.b[c.i-1] == UInt8('\n')
ddfail(c::DDCursor, msg) = throw(DDSyntaxError(c.file, c.line, msg))

const DD_BLANK = (UInt8(' '), UInt8('\t'), UInt8('\r'))

# skip to the end of the line (not past the newline)
function ddskipline!(c::DDCursor)
    while !ddeof(c) && ddpeek(c) != UInt8('\n')
        c.i += 1
    end
end
function ddrestofline!(c::DDCursor)
    a = c.i
    ddskipline!(c)
    String(c.b[a:c.i-1])
end

# Skip blanks; with `newlines`, also newlines, comment lines (`*` in column 1) and $ONTEXT/$OFFTEXT
# blocks. Stops at a `$` in column 1 (a dollar-control line, for the caller) and returns true there.
function ddskip!(c::DDCursor; newlines::Bool=true)
    while !ddeof(c)
        ch = ddpeek(c)
        if ch in DD_BLANK
            c.i += 1
        elseif ch == UInt8('\n')
            newlines || return false
            c.i += 1
            c.line += 1
        elseif ddbol(c) && ch == UInt8('*')
            ddskipline!(c)
        elseif ddbol(c) && ch == UInt8('$')
            # $ONTEXT ... $OFFTEXT is a comment block; any other dollar line goes to the caller
            a = c.i
            t = lowercase(strip(ddrestofline!(c)[2:end]))
            if t == "ontext" || startswith(t, "ontext ")
                ddskipblock!(c)
            else
                c.i = a
                return true
            end
        else
            return false
        end
    end
    false
end

function ddskipblock!(c::DDCursor)
    start = c.line
    while !ddeof(c)
        if ddpeek(c) == UInt8('\n')
            c.i += 1
            c.line += 1
            if ddpeek(c) == UInt8('$')
                t = lowercase(strip(ddrestofline!(c)[2:end]))
                (t == "offtext" || startswith(t, "offtext ")) && return
            end
        else
            c.i += 1
        end
    end
    throw(DDSyntaxError(c.file, start, "\$ONTEXT without \$OFFTEXT"))
end

ddidentchar(ch::UInt8) = (UInt8('a') <= ch <= UInt8('z')) || (UInt8('A') <= ch <= UInt8('Z')) ||
                         (UInt8('0') <= ch <= UInt8('9')) || ch == UInt8('_')
# an unquoted label: letters, digits and _ + - (GAMS: starts with a letter or digit; other characters
# need quotes). A leading + or - is refused: in a data list it would be read as a sign.
ddlabelchar(ch::UInt8) = ddidentchar(ch) || ch == UInt8('+') || ch == UInt8('-')

function ddident!(c::DDCursor)
    a = c.i
    while !ddeof(c) && ddidentchar(ddpeek(c))
        c.i += 1
    end
    a == c.i && ddfail(c, "expected a name, found $(repr(Char(ddpeek(c))))")
    String(c.b[a:c.i-1])
end

# a quoted string ('...' or "..."): no escapes, must close on the same line
function ddquoted!(c::DDCursor)
    q = ddpeek(c)
    c.i += 1
    a = c.i
    while !ddeof(c) && ddpeek(c) != q
        ddpeek(c) == UInt8('\n') && ddfail(c, "quote not closed on its line")
        c.i += 1
    end
    ddeof(c) && ddfail(c, "quote not closed")
    s = String(c.b[a:c.i-1])
    c.i += 1
    s
end

# one label of a key: quoted, or unquoted
function ddlabel!(c::DDCursor)
    ch = ddpeek(c)
    (ch == UInt8('\'') || ch == UInt8('"')) && return ddquoted!(c)
    (ddidentchar(ch) && ch != UInt8('_')) || ddfail(c, "expected a label, found $(ch == 0 ? "the end of the file" : repr(Char(ch)))")
    a = c.i
    while !ddeof(c) && ddlabelchar(ddpeek(c))
        c.i += 1
    end
    String(c.b[a:c.i-1])
end

# a key: labels joined by '.', no blanks between them; `(a,b)` lists and `*` ranges are refused
function ddkey!(c::DDCursor)
    ddpeek(c) == UInt8('(') && ddfail(c, "a parenthesised label list is outside the syntax TIMES.jl reads")
    labels = String[ddlabel!(c)]
    while ddpeek(c) == UInt8('.')
        c.i += 1
        ddpeek(c) == UInt8('(') && ddfail(c, "a parenthesised label list is outside the syntax TIMES.jl reads")
        push!(labels, ddlabel!(c))
    end
    ddpeek(c) == UInt8('*') && ddfail(c, "a label range (*) is outside the syntax TIMES.jl reads")
    labels
end

const DD_SPECIAL = Dict("eps" => (:eps, 0.0), "inf" => (:inf, Inf), "+inf" => (:inf, Inf), "-inf" => (:minf, -Inf),
    "na" => (:na, NaN), "undf" => (:undf, NaN))

# a value: a number, or EPS, INF, -INF, NA, UNDF (any case)
function ddvalue!(c::DDCursor)
    a = c.i
    while !ddeof(c) && !(ddpeek(c) in DD_BLANK) && !(ddpeek(c) in (UInt8('\n'), UInt8(','), UInt8('/'), UInt8(';')))
        c.i += 1
    end
    t = String(c.b[a:c.i-1])
    isempty(t) && ddfail(c, "a parameter record without a value")
    sp = get(DD_SPECIAL, lowercase(t), nothing)
    sp === nothing || return (sp[2], sp[1])
    v = tryparse(Float64, t)
    (v === nothing || !occursin(r"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$", t)) && ddfail(c, "not a number: $(repr(t))")
    (v, :none)
end

# Is the record at the cursor a scalar's value: one unquoted number (or special value) with nothing
# after it on its line but the end of the list? A keyed record always has a value after its key, so
# a lone number can only be the value of a 0-dimensional parameter (GAMS refuses it otherwise).
function ddscalar(c::DDCursor)
    a = c.i
    while a <= length(c.b) && !(c.b[a] in DD_BLANK) && !(c.b[a] in (UInt8('\n'), UInt8(','), UInt8('/'), UInt8(';')))
        a += 1
    end
    t = String(c.b[c.i:a-1])
    (haskey(DD_SPECIAL, lowercase(t)) || occursin(r"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$", t)) || return false
    while a <= length(c.b) && c.b[a] in DD_BLANK
        a += 1
    end
    a > length(c.b) || c.b[a] in (UInt8('\n'), UInt8(','), UInt8('/'))
end

# element text after a set record's key: quoted, or unquoted up to a comma, a '/' or the end of the line
function ddtext!(c::DDCursor)
    ddskip!(c; newlines=false)
    ch = ddpeek(c)
    (ch == UInt8('\'') || ch == UInt8('"')) && return ddquoted!(c)
    (ddeof(c) || ch in (UInt8('\n'), UInt8(','), UInt8('/'), UInt8(';'))) && return ""
    a = c.i
    while !ddeof(c) && !(ddpeek(c) in (UInt8('\n'), UInt8(','), UInt8('/'), UInt8(';')))
        c.i += 1
    end
    String(rstrip(String(c.b[a:c.i-1])))
end

# the data list between '/' and '/'; records separated by commas or newlines
function dddata!(c::DDCursor, kind::Symbol)
    recs = DDRecord[]
    c.i += 1  # opening '/'
    while true
        ddskip!(c) && ddfail(c, "a dollar-control line inside a data list is outside the syntax TIMES.jl reads")
        ddeof(c) && ddfail(c, "data list not closed with '/'")
        ch = ddpeek(c)
        if ch == UInt8('/')
            c.i += 1
            return recs
        elseif ch == UInt8(',')
            c.i += 1
            continue
        end
        line = c.line
        if kind === :parameter && ddscalar(c)
            # a scalar parameter's list holds only its value (G_DYEAR / 2005 /): no key
            v, sp = ddvalue!(c)
            push!(recs, DDRecord(String[], v, sp, "", line))
        elseif kind === :parameter
            labels = ddkey!(c)
            ddskip!(c; newlines=false)
            v, sp = ddvalue!(c)
            push!(recs, DDRecord(labels, v, sp, "", line))
        else
            labels = ddkey!(c)
            push!(recs, DDRecord(labels, NaN, :none, ddtext!(c), line))
        end
        ddskip!(c; newlines=false)
        ch = ddpeek(c)
        ch in (UInt8('\n'), UInt8(','), UInt8('/'), 0x00) || ddfail(c, "unexpected $(repr(Char(ch))) after a record")
    end
end

# one symbol of a SET or PARAMETER statement: NAME [(domain)] [text] [/ data /]
function ddsymbol!(c::DDCursor, kind::Symbol)
    line = c.line
    name = ddident!(c)
    domain = String[]
    ddskip!(c; newlines=false)
    if ddpeek(c) == UInt8('(')
        c.i += 1
        while true
            ddskip!(c)
            push!(domain, ddpeek(c) == UInt8('*') ? (c.i += 1; "*") : ddident!(c))
            ddskip!(c)
            ch = ddpeek(c)
            c.i += 1
            ch == UInt8(')') && break
            ch == UInt8(',') || ddfail(c, "expected ',' or ')' in the domain of $name")
        end
        ddskip!(c; newlines=false)
    end
    text = ""
    ch = ddpeek(c)
    if ch == UInt8('\'') || ch == UInt8('"')
        text = ddquoted!(c)
    elseif !(ddeof(c) || ch in (UInt8('\n'), UInt8('/'), UInt8(','), UInt8(';')))
        a = c.i
        while !ddeof(c) && !(ddpeek(c) in (UInt8('\n'), UInt8('/'), UInt8(','), UInt8(';')))
            c.i += 1
        end
        text = String(rstrip(String(c.b[a:c.i-1])))
    end
    # the data list may start on a later line (Veda writes the '/' on its own line)
    ddskip!(c) && return DDSymbol(kind, name, domain, text, false, DDRecord[], c.file, line)
    ddpeek(c) == UInt8('/') || return DDSymbol(kind, name, domain, text, false, DDRecord[], c.file, line)
    DDSymbol(kind, name, domain, text, true, dddata!(c, kind), c.file, line)
end

"""
    parse_dd(text; file="<string>") -> Vector{DDItem}
    parse_dd_file(path) -> Vector{DDItem}

Read a TIMES DD or run file into its statements, in file order: `DDSymbol` (one per symbol of a SET
or PARAMETER statement), `DDDirective` (a dollar-control line) and `DDOther` (an OPTION statement).
A statement ends at its `;`, at the next keyword (GAMS lets Veda's DD files leave the `;` out) or
at the end of the file. Syntax outside the subset of docs/m14-plan.md throws a `DDSyntaxError`.
"""
function parse_dd(text::AbstractString; file::AbstractString="<string>")
    c = DDCursor(text, file)
    # a UTF-8 byte-order mark is not part of the text
    length(c.b) >= 3 && c.b[1:3] == [0xef, 0xbb, 0xbf] && (c.i = 4)
    items = DDItem[]
    while true
        if ddskip!(c)
            line = c.line
            push!(items, DDDirective(String(strip(ddrestofline!(c)[2:end])), c.file, line))
            continue
        end
        ddeof(c) && return items
        ch = ddpeek(c)
        if ch == UInt8(';')
            c.i += 1
            continue
        end
        ddidentchar(ch) || ddfail(c, "expected a statement, found $(repr(Char(ch)))")
        line = c.line
        word = ddident!(c)
        kw = lowercase(word)
        if haskey(DD_DATA_KEYWORDS, kw)
            kind = DD_DATA_KEYWORDS[kw]
            while true
                ddskip!(c) && break                      # a dollar line ends the statement
                ddeof(c) && break
                ch = ddpeek(c)
                ch == UInt8(';') && (c.i += 1; break)
                ch == UInt8(',') && (c.i += 1; continue)
                ddidentchar(ch) || ddfail(c, "expected a symbol name in a $word statement, found $(repr(Char(ch)))")
                # the next keyword starts a new statement
                a, l = c.i, c.line
                nxt = lowercase(ddident!(c))
                c.i, c.line = a, l
                (haskey(DD_DATA_KEYWORDS, nxt) || nxt in DD_OTHER_KEYWORDS || nxt in DD_REFUSED_KEYWORDS) && break
                push!(items, ddsymbol!(c, kind))
            end
        elseif kw in DD_OTHER_KEYWORDS
            a = c.i
            while !ddeof(c) && ddpeek(c) != UInt8(';')
                ddpeek(c) == UInt8('\n') && (c.line += 1)
                c.i += 1
            end
            ddeof(c) && ddfail(c, "$word statement without ';'")
            push!(items, DDOther(word, String(strip(String(c.b[a:c.i-1]))), c.file, line))
            c.i += 1
        elseif kw in DD_REFUSED_KEYWORDS
            throw(DDSyntaxError(c.file, line, "a $(uppercase(word)) statement is outside the syntax TIMES.jl reads"))
        else
            throw(DDSyntaxError(c.file, line, "unknown statement $(repr(word))"))
        end
    end
end

parse_dd_file(path::AbstractString) = parse_dd(read(path, String); file=path)

"""
    LabelTable()

GAMS's label (UEL) list: labels are case-insensitive, the first spelling seen is the one kept, and
the order is the order of first use during compilation (GAMS manual, "Ordered sets"; the dump's
`uels`). Trailing blanks are not part of a label. `intern!(t, s)` returns the kept spelling.
"""
struct LabelTable
    index::Dict{String,Int}     # lowercase label => position
    labels::Vector{String}      # first spelling, in order of first use
end
LabelTable() = LabelTable(Dict{String,Int}(), String[])

function intern!(t::LabelTable, s::AbstractString)
    s = rstrip(s)
    k = lowercase(s)
    i = get(t.index, k, 0)
    i > 0 && return t.labels[i]
    push!(t.labels, String(s))
    t.index[k] = length(t.labels)
    t.labels[end]
end
labelpos(t::LabelTable, s::AbstractString) = get(t.index, lowercase(rstrip(s)), 0)
Base.length(t::LabelTable) = length(t.labels)
