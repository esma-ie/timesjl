# M1.3 (25b-1): the quality-assurance log QA_CHECK.LOG (the PUT file QLOG)
# and its scalars PUTOUT, PUTGRP and ERRLEV.
#
# GAMS (v4.9.7): ppmain.mod L12-14 (FILE QLOG, the scalars), L33-35 (the
# compile-warnings line), L1356-1357 (PUTCLOSE, append from then on);
# pp_qaput.mod L1-16 (the header, a group's first line, a message's level);
# pp_qack.mod L37-41 (reopened in append mode, NW=10, ND=2, PW=150).
#
# The log is kept in `tm.cache["QLOG"]` as the lines GAMS has written and the
# line being built. GAMS PUT rules it follows (checked on GAMS 54.6.1,
# docs/discrepancies.md G53):
# - `/` ends the current line, even an empty one; trailing blanks are not
#   written (a line of blanks only is written as one blank); lines end CRLF.
# - `@n` moves the cursor to column n; what is put there overwrites.
# - PUTCLOSE writes the current line only when it is not empty.
# - Labels are left-justified, numbers right-justified in their width;
#   width 0 means no padding. `:<>w` centres (the extra blank on the right).
# - Numbers: `ND` decimals, as C's `%.*f` (0.5 to 0 decimals gives 0); EPS is
#   0; +INF, -INF and NA as words; a number wider than its width (not 0) in
#   E format with 6 decimals (1.000000E+15).
#
# `$IF WARNINGS` (ppmain.mod L35) is a compile-time fact the dumps do not
# record: the count of GAMS compilation warnings is an input of the run
# (`qa_warnings!`), set from the reference listing by the scripts and, from
# M1.4, by the DD reader.

"The QA log as GAMS has written it: finished lines, the current line and the cursor; QLOG.NW, ND, PW."
mutable struct QaLog
    lines::Vector{String}
    cur::Vector{Char}
    cc::Int
    nw::Int
    nd::Int
    pw::Int
end
QaLog() = QaLog(String[], Char[], 1, 12, 2, 255)

"The model's QA log (created empty: the FILE statement of ppmain.mod L13)."
qalog(tm) = get!(QaLog, tm.cache, "QLOG")::QaLog

"""
    qa_warnings!(tm, n) -> tm

Record the number of GAMS compilation warnings of the run (`\$IF WARNINGS`,
ppmain.mod L35): from the reference listing for the parity checks
(`gams_warnings`), from the DD reader from M1.4.
"""
qa_warnings!(tm, n::Integer) = (tm.cache["GAMS_WARNINGS"] = Int(n); tm)
qa_warnings(tm) = get(tm.cache, "GAMS_WARNINGS", 0)::Int

"""
    gams_warnings(lst) -> Int

The compilation warnings of a GAMS listing: the first `**** n ERROR(S)
m WARNING(S)` line (the compilation summary), 0 when there is none.
"""
function gams_warnings(lst::AbstractString)
    isfile(lst) || return 0
    for ln in eachline(lst)
        m = match(r"^\*\*\*\* +\d+ ERROR\(S\) +(\d+) WARNING\(S\)", ln)
        m === nothing || return parse(Int, m[1])
    end
    return 0
end

"PUT a string at the cursor (overwriting what is there)."
function qput!(q::QaLog, s::AbstractString)
    for ch in s
        while length(q.cur) < q.cc - 1
            push!(q.cur, ' ')
        end
        q.cc <= length(q.cur) ? (q.cur[q.cc] = ch) : push!(q.cur, ch)
        q.cc += 1
    end
    return q
end
"`@col`: move the cursor."
qat!(q::QaLog, col::Integer) = (q.cc = Int(col); q)
"`/`: end the current line."
function qnl!(q::QaLog)
    s = rstrip(String(q.cur))
    push!(q.lines, isempty(s) && !isempty(q.cur) ? " " : s)
    empty!(q.cur)
    q.cc = 1
    return q
end
"PUTCLOSE: write the current line if it is not empty."
qclose!(q::QaLog) = (isempty(q.cur) || qnl!(q); q)

"The log text as the file holds it once GAMS closes it (CRLF line ends)."
function qa_text(q::QaLog)
    ls = copy(q.lines)
    isempty(q.cur) || push!(ls, rstrip(String(q.cur)))
    return join((l * "\r\n" for l in ls))
end
qa_text(tm) = qa_text(qalog(tm))

"A label left-justified in width `w` (0: as it is)."
qlabel(s::AbstractString, w::Integer=0) = w > 0 ? rpad(s, w) : String(s)
"`%RL%`, `%PL%`, `%CL%` (setglobs.gms L316-317): the label in MAX(12, its length)."
qlab12(s::AbstractString) = rpad(s, max(12, length(s)))
"`:<>w`: centred in width `w` (the extra blank on the right)."
function qcenter(s::AbstractString, w::Integer)
    n = length(s)
    n >= w && return String(s)
    l = div(w - n, 2)
    return " "^l * s * " "^(w - n - l)
end

"""
    qfixed(v, d) -> String

`v` with `d` decimals as C's `%.*f`: the exact binary value rounded half to
even (0.5 to 0 decimals gives 0, 2.675 to 2 gives 2.67).
"""
function qfixed(v::Float64, d::Integer)
    r = setprecision(BigFloat, 2048) do
        round(BigInt, BigFloat(v) * BigFloat(10)^d, RoundNearest)
    end
    neg = v < 0 || (iszero(v) && signbit(v))
    digs = string(abs(r))
    if d > 0
        digs = lpad(digs, d + 1, '0')
        digs = digs[1:end-d] * "." * digs[end-d+1:end]
    end
    return (neg ? "-" : "") * digs
end

"`v` as C's `%.6E` (the E format PUT falls back to)."
function qexp(v::Float64)
    iszero(v) && return "0.000000E+00"
    e = floor(Int, log10(abs(v)))
    m = qfixed(v / 10.0^e, 6)
    if startswith(lstrip(m, '-'), "10")              # rounding carried into a new digit
        e += 1
        m = qfixed(v / 10.0^e, 6)
    end
    return m * "E" * (e < 0 ? "-" : "+") * lpad(string(abs(e)), 2, '0')
end

"""
    qnum(x, w, d; left=false) -> String

A number as PUT writes it in width `w` (0: no padding) with `d` decimals:
EPS as 0, +INF, -INF and NA as words, E format (6 decimals) when it does not
fit a nonzero width.
"""
function qnum(x::Real, w::Integer, d::Integer; left::Bool=false)
    v = Float64(x)
    s = isnan(v) ? "NA" : v == Inf ? "+INF" : v == -Inf ? "-INF" : qfixed(v, d)
    (w > 0 && length(s) > w && isfinite(v)) && (s = qexp(v))
    w > 0 || return s
    return left ? rpad(s, w) : lpad(s, w)
end
qnum(x::GNum, w::Integer, d::Integer; left::Bool=false) = qnum(x.eps ? 0.0 : x.v, w, d; left)
"A number in QLOG's default width and decimals (QLOG.NW, QLOG.ND)."
qnum(q::QaLog, x) = qnum(x, q.nw, q.nd)

"The run title, %SYSTEM.TITLE% (initsys.mod L1 and L19)."
function qa_title(tm)
    t = "TIMES -- VERSION " * string(TIMES_GAMS_VERSION)
    rt = gswitch(tm, "RUNTIMES", "")
    isempty(rt) || (t *= " -- Restart (v" * rt * ")")
    return t
end

gscal_qa(tm, n) = gscalar(tm, n)
"Assign a QA scalar (an exact zero removes the record, as GAMS stores it)."
put_qa_scalar!(tm, n, x::Real) = gput_scalar!(tm, n, x)

"""
    pp_qaput!(tm, level, desc; grp=true) -> QaLog

pp_qaput.mod: the log's header when PUTOUT is 0 (then PUTOUT = 1); the
group's first line ` *** desc` when its flag is 0 (`grp=false`: the literal
0 of ppmain.mod L35); then, unless `level` is `nothing` (`*`), a new line
` *NN` with the level, PUTGRP = its number of digits and ERRLEV = MAX(ERRLEV,
level). The caller puts the message text after it.

GAMS: pp_qaput.mod L9-16, v4.9.7.
"""
function pp_qaput!(tm, level::Union{Nothing,Real}, desc::AbstractString; grp::Bool=true)
    q = qalog(tm)
    if iszero(gscal_qa(tm, "PUTOUT"))                                         # L9-12
        put_qa_scalar!(tm, "PUTOUT", 1)
        qat!(q, 15)
        while q.cc < 67
            qput!(q, "*****")
        end
        qat!(q, 21); qput!(q, qcenter(qa_title(tm), 43)); qnl!(q); qat!(q, 15)
        while q.cc < 67
            qput!(q, "*****")
        end
        qat!(q, 29); qput!(q, qcenter("QUALITY ASSURANCE LOG", 27))
    end
    if !grp || iszero(gscal_qa(tm, "PUTGRP"))                                 # L13
        qnl!(q); qnl!(q); qput!(q, " *** " * desc * " ")
    end
    level === nothing && return q
    # L16: %2=1+1$(ROUND(%3)>9); PUT QLOG / ' *00'@(5-%2) MIN(99,%3):%2:0; ERRLEV$(%3>ERRLEV)=%3
    pg = 1 + (round(level, RoundNearestTiesAway) > 9)
    grp && put_qa_scalar!(tm, "PUTGRP", pg)
    qnl!(q); qput!(q, " *00"); qat!(q, 5 - pg); qput!(q, qnum(min(99, level), pg, 0))
    level > gscal_qa(tm, "ERRLEV") && put_qa_scalar!(tm, "ERRLEV", level)
    return q
end

"`PUTGRP = 0`: a new group of messages."
qa_group!(tm) = put_qa_scalar!(tm, "PUTGRP", 0)

"""
    qa_compile_warnings!(tm) -> tm

ppmain.mod L33-35: with GAMS compilation warnings (`qa_warnings`), the
group line 'GAMS Warnings Detected' (with '; Input Data have been filtered
via GDX' when %DATAGDX% is YES), no level.

GAMS: ppmain.mod L33-35, v4.9.7.
"""
function qa_compile_warnings!(tm)
    qa_warnings(tm) > 0 || return tm
    # %G2X6% is YES on GAMS 23.6 and later (initmty.mod L22); `$IF` compares case-sensitively
    gdx = strip(gswitch(tm, "DATAGDX", "")) == "YES"
    pp_qaput!(tm, nothing, "GAMS Warnings Detected" * (gdx ? "; Input Data have been filtered via GDX" : "."); grp=false)
    return tm
end

"""
    qa_close!(tm) -> tm

ppmain.mod L1356-1357: PUTCLOSE QLOG; the later PUTs append (QLOG.AP = 1
when PUTOUT), which leaves the text as it is.

GAMS: ppmain.mod L1356-1357, v4.9.7.
"""
qa_close!(tm) = (qclose!(qalog(tm)); tm)

"Carry the QA log and the run's warning count from `tm` into `nt` (a TimesModel of the next checkpoint)."
function qa_carry!(nt, tm)
    for k in ("QLOG", "GAMS_WARNINGS")
        haskey(tm.cache, k) && (nt.cache[k] = deepcopy(tm.cache[k]))
    end
    return nt
end

"""
    qa_compare(ours, ref; complete=false) -> (ok, note)

The QA log TIMES.jl wrote (`qa_text`) against GAMS's QA_CHECK.LOG `ref`.
With `complete` the two must be equal. Otherwise `ref` may go on after
`ours`, which must then end at a line end, with a new group (a blank line,
or two after PUTCLOSE, then ` *** `), or `ours` is empty and `ref` starts
with the log's header (pp_qack.mod's checks write the rest).
"""
function qa_compare(ours::AbstractString, ref::AbstractString; complete::Bool=false)
    ours == ref && return (true, "identical")
    if !complete
        if isempty(ours)
            (isempty(ref) || occursin(r"^ {14}\*{6} ", ref)) && return (true, "GAMS's log goes on")
        elseif startswith(ref, ours) && endswith(ours, "\r\n")
            rest = ref[ncodeunits(ours)+1:end]
            (startswith(rest, "\r\n *** ") || startswith(rest, "\r\n\r\n *** ")) && return (true, "GAMS's log goes on")
        end
    end
    a, b = split(ours, "\r\n"), split(ref, "\r\n")
    i = something(findfirst(k -> k > length(a) || k > length(b) || a[k] != b[k], 1:max(length(a), length(b))), 1)
    return (false, "line $i: TIMES.jl " * repr(get(a, i, "<end>")) * ", GAMS " * repr(get(b, i, "<end>")))
end
