# Reading the timing records of one GAMS run of a reference (reference/python/make_reference.py):
# the listing's Include File Summary (raw/tjl_<run>.lst), the profile (raw/tjl_<run>_profile.txt,
# written with profile=1) and the elapsed-time stamps of the log (raw/tjl_<run>.log). Only numbers
# are taken from these files; no line of a listing or log is copied anywhere.
#
# Used by scripts/m12_timing.jl, scripts/m13_timing.jl and scripts/run_timing.jl.

"Include File Summary of a GAMS listing: (seq, global line, parent seq, local line, file) per include."
function include_summary(lst)
    rows = NamedTuple{(:seq, :gline, :parent, :loc, :file),Tuple{Int,Int,Int,Int,String}}[]
    inside = false
    for ln in eachline(lst)
        if occursin("Include File Summary", ln)
            inside = true
            continue
        end
        inside || continue
        f = split(ln)
        if length(f) >= 7 && all(s -> tryparse(Int, s) !== nothing, (f[1], f[2]))
            # SEQ GLOBAL TYPE PARENT LOCAL INCLVL FILENAME (TYPE may be two words: "IF EXIST")
            k = f[3] == "IF" ? 5 : 4
            push!(rows, (seq=parse(Int, f[1]), gline=parse(Int, f[2]), parent=parse(Int, f[k]),
                         loc=parse(Int, f[k+1]), file=String(f[end])))
        elseif !isempty(rows) && !isempty(strip(ln)) && !startswith(strip(ln), "SEQ")
            break
        end
    end
    return rows
end

"""
Seconds per profile record line (global listing line), without the records of the types in
`skip` (Unload: execute_unload, in a reference run the harness's dumps). The Equation records of
a SOLVE statement carry the line of each equation's definition, not the line of the SOLVE.
"""
function profile_lines(path; skip=("Unload",))
    t = Dict{Int,Float64}()
    for ln in eachline(path)
        f = split(ln)
        length(f) >= 5 || continue
        line, s = tryparse(Int, f[1]), tryparse(Float64, f[3])
        (line === nothing || s === nothing || f[5] in skip) && continue
        t[line] = get(t, line, 0.0) + s
    end
    return t
end

"Global line ranges [from, to) of the three preprocessing parts in one run's listing."
function prep_ranges(inc)
    base(x) = lowercase(basename(replace(x, '\\' => '/')))
    md = only(filter(r -> base(r.file) == "maindrv.mod", inc))
    kids = sort(filter(r -> r.parent == md.seq, inc); by=r -> r.loc)       # maindrv.mod's own includes
    pm = first(filter(r -> base(r.file) == "ppmain.mod", kids))
    ie = last(filter(r -> base(r.file) == "main_ext.mod" && r.loc < pm.loc, kids))   # L55: init_ext
    pe = first(filter(r -> base(r.file) == "main_ext.mod" && r.loc > pm.loc, kids))  # L58: ppm_ext
    nx = first(filter(r -> r.loc > pe.loc, kids))
    return Dict("init_ext" => (ie.gline, pm.gline), "ppmain" => (pm.gline, pe.gline), "ppm_ext" => (pe.gline, nx.gline),
                "total" => (ie.gline, nx.gline))
end

"Global listing line of the first SOLVE statement of a run, from its profile; nothing without one."
function solve_line(path)
    for ln in eachline(path)
        f = split(ln)
        length(f) >= 5 && f[5] == "Solve" && tryparse(Int, f[1]) !== nothing && return parse(Int, f[1])
    end
    return nothing
end

"Number of solver calls of a run, from its profile (more than one: a stepped solve)."
solver_calls(path) = count(ln -> (f = split(ln); length(f) >= 5 && f[5] == "Solver"), eachline(path))

"""
Seconds from the start of the GAMS job to the start of execution (GAMS's start-up and the
compilation of the run file, the TIMES source and the DD files), from the log's elapsed stamp;
nothing when the log has none.
"""
function execution_start(log)
    for ln in eachline(log)
        m = match(r"Starting execution: elapsed (\d+):(\d+):(\d+(?:\.\d+)?)", ln)
        m === nothing || return 3600 * parse(Int, m[1]) + 60 * parse(Int, m[2]) + parse(Float64, m[3])
    end
    return nothing
end

"Seconds of the profile's Unload records (execute_unload: in a reference run, the harness's dumps)."
function unload_seconds(path)
    t = 0.0
    for ln in eachline(path)
        f = split(ln)
        length(f) >= 5 && f[5] == "Unload" || continue
        s = tryparse(Float64, f[3])
        s === nothing || (t += s)
    end
    return t
end
