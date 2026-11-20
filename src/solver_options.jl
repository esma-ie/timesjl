# Solver option files for run_model (James, 20 Nov 2026, q1): a run reads its solver's option file,
# as a GAMS TIMES run does. This file holds no translated equation and changes no LP: it reproduces
# what GAMS does with the model's OPTFILE attribute.
#
# GAMS: initsys.mod L168 (`SCALAR OPTFILEID /1/`) and solve.mod L14-15 (`%MODEL_NAME%.OPTFILE =
# OPTFILEID`), v4.9.7: with OPTFILE = 1 the solver reads `<solver>.opt` from GAMS's working folder,
# the folder of the run file (VEDA writes `cplex.opt` there, beside the run and DD files).
# OPTFILEID = 2 (eqlducs.vda L152-154: `<solver>.op2`, the option file with CPLEX's or XPRESS's
# `indic` lines, and PRIOROPT) comes only with eq_sdind_0/1, which the model generation refuses
# (src/model/generate.jl), so a TIMES.jl run never reaches it.
#
# Option files are read for HiGHS only. CPLEX (q2 of 20 Nov 2026) waits for James's answer: the
# CPLEX in GAMS is licensed for use within GAMS only (GAMS EULA, Exhibit A), and this machine has
# no other CPLEX (docs/decisions.md).

"""
    read_optfile(path) -> Vector{Pair{String,String}}

The options in a GAMS solver option file, in file order, as `name => value` text. The rules are
GAMS's (GAMS 54 documentation, "The Solver Option File"):

- blank lines are ignored, and a line with `*` in its first column is a comment;
- each other line is one option, `keyword [value]`; the keyword is not case sensitive (it is
  lower-cased here). An `=` may stand between keyword and value, as in `THREADS=7`, a form the
  suite's VEDA-written `cplex.opt` files use;
- a value in double or single quotes is unquoted; a keyword with no value gets `""`.

The file is not checked against any solver here: `highs_options` does that for HiGHS.
"""
function read_optfile(path::AbstractString)
    opts = Pair{String,String}[]
    for ln in eachline(path)
        startswith(ln, "*") && continue
        s = strip(ln)
        isempty(s) && continue
        m = match(r"^([^\s=]+)\s*=?\s*(.*)$", s)
        k, v = lowercase(m[1]), String(strip(m[2]))
        if length(v) >= 2 && v[1] == v[end] && v[1] in ('"', '\'')
            v = v[2:end-1]
        end
        push!(opts, k => v)
    end
    return opts
end

# The value of a HiGHS option of type `t` (HiGHS's kHighsOptionType*) from its text, or nothing.
# A boolean takes 1/0, true/false, yes/no or on/off; an integer may be written as a whole real (1e3).
function _highs_value(t::Integer, v::AbstractString)
    if t == HiGHS.kHighsOptionTypeBool
        w = lowercase(v)
        return w in ("1", "true", "yes", "on") ? true : w in ("0", "false", "no", "off") ? false : nothing
    elseif t == HiGHS.kHighsOptionTypeInt
        x = tryparse(Int, v)
        x === nothing || return x
        y = tryparse(Float64, v)
        return y !== nothing && isinteger(y) && abs(y) <= typemax(Cint) ? Int(y) : nothing
    elseif t == HiGHS.kHighsOptionTypeDouble
        return tryparse(Float64, v)
    else
        return String(v)
    end
end

"""
    highs_options(opts; threads) -> (options, notes)

The options of an option file (`read_optfile`) that HiGHS takes, as `name => value` pairs of the
type HiGHS wants, and a note on each line not used. Each option is checked on a scratch HiGHS
instance: a name HiGHS does not know, or a value it refuses (a wrong type, or out of range), is
left out with a note, so the solve itself never stops on the option file. GAMS's solvers report
such lines in their log and carry on in the same way (GAMS 54 documentation, "The Solver Option
File": errors "are either ignored or pushed to a default or limiting value").

`threads` is the run's limit (`run_model`'s `threads`): a file that asks for more threads, or for
HiGHS's own choice (`threads 0`, half the machine's CPUs), gets `threads` (CLAUDE.md, run limits).
An `echo on` or `echo off` line (GAMS's, for the solver's log) is skipped without a note.
"""
function highs_options(opts; threads::Integer)
    out = Pair{String,Any}[]
    notes = String[]
    h = HiGHS.Highs_create()
    try
        HiGHS.Highs_setBoolOptionValue(h, "output_flag", false)
        t = Ref{Cint}(0)
        for (k, v) in opts
            k == "echo" && continue
            if HiGHS.Highs_getOptionType(h, k, t) != HiGHS.kHighsStatusOk
                push!(notes, "$k: not a HiGHS option, not used")
                continue
            end
            x = _highs_value(t[], v)
            if k == "threads" && x isa Integer && (x <= 0 || x > threads)
                push!(notes, "threads: $x in the file; $threads used, the run's limit")
                x = Int(threads)
            end
            ok = x !== nothing && (
                x isa Bool ? HiGHS.Highs_setBoolOptionValue(h, k, x) :
                x isa Integer ? HiGHS.Highs_setIntOptionValue(h, k, x) :
                x isa Float64 ? HiGHS.Highs_setDoubleOptionValue(h, k, x) :
                HiGHS.Highs_setStringOptionValue(h, k, x)) == HiGHS.kHighsStatusOk
            if !ok
                push!(notes, "$k: \"$v\" is not a value HiGHS takes for it, not used")
                continue
            end
            filter!(p -> p.first != k, out)         # a later line for the same option wins
            push!(out, k => x)
        end
    finally
        HiGHS.Highs_destroy(h)
    end
    return out, notes
end

"""
    find_optfile(dir, solver) -> (path or nothing, notes)

The option file a GAMS run in `dir` would give `solver` (OPTFILE = 1): `<solver>.opt`, lower case,
or `nothing`. The notes name every other solver's option file in `dir` (`cplex.opt`, ...), which the
run does not read; `convert.opt` (the reference harness's) is passed over in silence.
"""
function find_optfile(dir::AbstractString, solver::AbstractString)
    want = lowercase(solver) * ".opt"
    path = nothing
    notes = String[]
    for f in sort(readdir(dir))
        lf = lowercase(f)
        endswith(lf, ".opt") && isfile(joinpath(dir, f)) || continue
        if lf == want
            path = joinpath(dir, f)
        elseif lf != "convert.opt"
            push!(notes, "$f not read: an option file for $(uppercase(lf[1:end-4])), and this run solves with $solver")
        end
    end
    return path, notes
end
