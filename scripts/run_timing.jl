# The time each part of a run took, per model-scenario pair, language and solver: the data of
# the dashboard's slides 11 and 12 (docs/dashboard/index.html, block "run-timing").
#
#   julia --project=test scripts/run_timing.jl <reference dir> [<batch log dir> ...]
#         [--meta <parity report .json of the batch>] [--out <file.json>] [--embed [<page>]] [--all | --local | --unpublished]
#
# Nothing is run here: every number is read from output that exists already.
#
# GAMS, one entry per solve run of a reference (<reference dir>/<model>/<variant>):
#   manifest.json                  wall_s of the run, the model's size, GAMS's own generation
#                                  time (resgen) and solver time (etsolver), the thread limit
#   raw/tjl_solve_<solver>.log     the elapsed stamp at the start of execution (only the number)
#   raw/tjl_solve_<solver>.lst     the Include File Summary (which listing lines are which file)
#   raw/tjl_solve_<solver>_profile.txt   seconds per statement (profile=1)
# TIMES.jl, one entry per (model, variant) of a workstation batch (scripts/m13_gate.jl --from-dd,
# log dd-<model>.log in <batch log dir>): the seconds the gate prints for each step, and the wall
# time of the whole run (its line "whole run <s> s"; a batch older than that timer has none). With --all
# or --local, a model without such a log is looked for in the batch's *chain*.log files (the gate
# from GAMS's dump of the input: no reading of DD files, and it may end at an untranslated path).
#
# Parts (seconds; nothing where a part was never measured):
#   read      GAMS: start-up and compilation of the run file, the TIMES source and the DD files,
#             plus the statements before preprocessing. TIMES.jl: reading the DD files.
#   prep      preprocessing: GAMS maindrv.mod from init_ext to the end of ppm_ext;
#             TIMES.jl the steps input -> init -> prep -> prelv -> ppm.
#   coef      coefficients and the preparation of the equations: GAMS from the end of ppm_ext to
#             the SOLVE statement; TIMES.jl the steps ppm -> coef -> presolve.
#   generate  GAMS: resgen. TIMES.jl: generate! (the JuMP model).
#   solve     GAMS: etsolver. TIMES.jl: JuMP.optimize! with HiGHS.
#   reports   GAMS: the statements after the solve. TIMES.jl: not translated yet (M1.6).
# wall is the whole run, and other is what of it is in no part. GAMS: wall_s, which also holds the
# harness's dumps (profile records of type Unload, reported as harness.dumps) and GAMS's start and
# exit. TIMES.jl: the gate's wall timer around the run of one variant; its steps read the harness's
# dump of the input (harness.write is the time to write it), and other is its comparisons with GAMS,
# the reading of GAMS's dumps for them and, in the first run of a Julia process (cold), the loading
# and compilation of TIMES.jl.
#
# Only models with redistribute = "public" in reference/suite.toml are read, unless --all (every
# model) or --local (only the others); both are for a local board, and --embed then refuses.
#
# Timings the public page does not show (rt_public):
#   - every GAMS entry, whatever its solver: GAMS's timings are shown on the local board only
#     (James, 21 Nov 2026; #184);
#   - every entry of a solver in RT_RESTRICTED (CPLEX among them): the GAMS EULA's "Publication of
#     Benchmarks" (C:\GAMS\54\EULA.md L362-376) forbids publishing performance comparisons of its
#     Restricted Solvers without the consent of GAMS and the solver vendor (James, 20 Nov 2026; #182 d6).
# By default they are dropped, and --embed refuses any of them. --unpublished writes only those
# entries, of the public models, for the local board (C:\git\esma\build_dashboard_local.ps1 embeds
# them as the block run-timing-unpublished); --all and --local keep every entry, as they are local already.
# No path, host name or log line goes into the output.

import JSON, TOML
import Dates
include(joinpath(@__DIR__, "gams_profile.jl"))   # include_summary, profile_lines, prep_ranges, solve_line, ...

const RT_REPO = normpath(joinpath(@__DIR__, ".."))
const RT_VARIANTS = ("reduce_off", "as_run")
const RT_GAMS_MAJOR = 54                          # CLAUDE.md: every reference run is made with GAMS 54
# The GAMS EULA's Restricted Solvers (C:\GAMS\54\EULA.md L362-376), ODHCPLEX with CPLEX as its subsolver:
# their timings are kept off the public page (#182 d6; the header above)
const RT_RESTRICTED = ("COPT", "CPLEX", "GUROBI", "KNITRO", "LINDO", "LINDOGLOBAL", "XPRESS", "ODHCPLEX")
"Whether the public page may show a timing entry: not GAMS's (#184) and not a Restricted Solver's (#182 d6)."
rt_public(e) = e.language != "GAMS" && !(e.solver in RT_RESTRICTED)

r3(x) = x === nothing ? nothing : round(Float64(x); digits=3)
int(x) = x === nothing ? nothing : round(Int, x)

"Text of a batch log (PowerShell writes UTF-16 with a byte-order mark; plain UTF-8 otherwise)."
function log_text(path)
    b = read(path)
    s = length(b) >= 2 && b[1] == 0xff && b[2] == 0xfe ?
        transcode(String, reinterpret(UInt16, b[3:end-isodd(length(b))])) : String(b)
    return replace(s, '\ufeff' => "", '\r' => "")
end

"GAMS version and run date from a manifest's version line: (\"54.6.1\", \"2026-10-30\")."
function gams_stamp(s)
    v = match(r"GAMS (\d+)\.(\d+)\.(\d+)", s)
    d = match(r"(\d\d)/(\d\d)/(\d\d) \d\d:\d\d:\d\d", s)
    return (version=v === nothing ? nothing : join(v.captures, "."), major=v === nothing ? nothing : parse(Int, v[1]),
            date=d === nothing ? nothing : "20$(d[3])-$(d[1])-$(d[2])")
end

"The timing entry of one GAMS solve run of a reference, or nothing when the run cannot be used."
function gams_entry(dir, man, key)
    run = man["runs"][key]
    si = get(run, "solveinfo", nothing)
    (si isa AbstractDict && get(run, "returncode", 1) == 0) || return nothing
    st = gams_stamp(get(run, "gams_version", ""))
    if st.major != RT_GAMS_MAJOR
        println("   skipped $key: made with GAMS $(st.version), not GAMS $RT_GAMS_MAJOR")
        return nothing
    end
    raw(ext) = joinpath(dir, "raw", "tjl_$key$ext")
    parts = Dict{Symbol,Any}(k => nothing for k in (:read, :prep, :coef, :generate, :solve, :reports))
    dumps = nothing
    src = ["manifest.json"]
    calls = isfile(raw("_profile.txt")) ? solver_calls(raw("_profile.txt")) : 1
    if all(isfile, (raw(".lst"), raw("_profile.txt"), raw(".log")))
        pr = prep_ranges(include_summary(raw(".lst")))
        # without the harness's dumps, the generation of the equations (resgen has it) and GAMS's exit
        prof = profile_lines(raw("_profile.txt"); skip=("Unload", "Equation", "GAMS"))
        sl = solve_line(raw("_profile.txt"))
        t0 = execution_start(raw(".log"))
        between(a, b) = sum((s for (l, s) in prof if a <= l < b); init=0.0)
        from, to = pr["total"]
        if sl !== nothing && t0 !== nothing
            parts[:read] = t0 + between(0, from)
            parts[:prep] = between(from, to)
            parts[:coef] = between(to, sl)
            parts[:reports] = between(sl + 1, typemax(Int))
            dumps = unload_seconds(raw("_profile.txt"))
            append!(src, ["raw/tjl_$key.log", "raw/tjl_$key.lst", "raw/tjl_$(key)_profile.txt"])
        end
    end
    parts[:generate] = get(si, "resgen", nothing)
    parts[:solve] = get(si, "etsolver", nothing)
    ms, ss = get(si, "modelstat", 0), get(si, "solvestat", 0)
    status = ms == 1 ? "optimal" : ss == 3 ? "time limit" : "not optimal"
    if calls > 1
        # a stepped solve: resgen and etsolver are those of the last SOLVE only, and the statements
        # between the SOLVEs are neither coefficients nor reports. Only read and prep are kept.
        for k in (:coef, :generate, :solve, :reports)
            parts[k] = nothing
        end
        status = "$calls solves in steps"
    end
    wall = run["wall_s"]
    measured = [v for v in values(parts) if v !== nothing]
    return (language="GAMS", solver=uppercase(replace(key, "solve_" => "")), status=status, cold=false, decimals=3,
            date=something(st.date, first(get(man, "created_utc", ""), 10)), version="GAMS $(st.version)",
            commit="TIMES v$(man["times"]["version"]) $(first(man["times"]["commit"], 7))",
            threads=get(get(man, "limits", Dict()), "threads", nothing),
            parts=(read=r3(parts[:read]), prep=r3(parts[:prep]), coef=r3(parts[:coef]), generate=r3(parts[:generate]),
                   solve=r3(parts[:solve]), reports=r3(parts[:reports])),
            wall=r3(wall), other=length(measured) == 6 ? r3(wall - sum(measured)) : nothing,
            harness=(dumps=r3(dumps),), source=src)
end

"""
The TIMES.jl timing entries of `model` in one batch log (scripts/m13_gate.jl): variant => entry.
The first (model, variant) of a log ran first in its Julia process, so its times include Julia's
compilation of TIMES.jl (cold).
"""
function julia_entries(log, model, meta, logname)
    out = Dict{String,Any}()
    order = String[]
    seen = Dict{String,Dict{String,Any}}()
    first_run = nothing
    for ln in split(log_text(log), '\n')
        m = match(r"^== (\S+?)/(\w+):? (.*)$", ln)
        m === nothing && continue
        first_run === nothing && (first_run = (String(m[1]), String(m[2])))
        m[1] != model && continue
        v, rest = String(m[2]), m[3]
        d = get!(() -> (push!(order, v); Dict{String,Any}()), seen, v)
        num(re) = (x = match(re, rest); x === nothing ? nothing : parse(Float64, x[1]))
        if startswith(rest, "DD files -> input: PASS")
            d["read"], d["write"] = num(r"compiled in ([\d.]+) s"), num(r"written in ([\d.]+) s")
        elseif (s = match(r"^input -> (\w+): PASS .*; \w+ -> \w+ in ([\d.]+) s\)", rest)) !== nothing
            d[String(s[1])] = parse(Float64, s[2])
        elseif startswith(rest, "model vs GAMS's matrix: PASS")
            d["generate"] = num(r"generated in ([\d.]+) s")
            d["rows"], d["cols"] = num(r"\((\d+) rows"), num(r", (\d+) columns")
        elseif startswith(rest, "HiGHS solve vs GAMS/CPLEX: PASS")
            d["solve"], d["status"] = num(r"solved in ([\d.]+) s"), "optimal"
        elseif startswith(rest, "HiGHS solve: FAIL (TIME_LIMIT")
            d["solve"], d["status"] = num(r"after ([\d.]+) s"), "time limit"
        elseif (s = match(r"^the chain ends before (\w+)", rest)) !== nothing
            d["ends"] = String(s[1])                   # an untranslated path: nothing after it is run
        elseif (s = match(r"^whole run ([\d.]+) s", rest)) !== nothing
            d["wall"] = parse(Float64, s[1])           # the gate's wall timer around this variant
        elseif occursin("FAIL", rest)
            d["failed"] = true
        end
    end
    for v in order
        d = seen[v]
        (haskey(d, "read") || haskey(d, "ppm")) || continue
        stages(ks) = all(k -> haskey(d, k), ks) ? sum(d[k] for k in ks) : nothing
        parts = (read=r3(get(d, "read", nothing)), prep=r3(stages(("init", "prep", "prelv", "ppm"))),
                 coef=r3(stages(("coef", "presolve"))), generate=r3(get(d, "generate", nothing)),
                 solve=r3(get(d, "solve", nothing)), reports=nothing)
        wall = get(d, "wall", nothing)
        out[v] = (language="TIMES.jl", solver="HIGHS",
                  status=get(d, "failed", false) ? "stopped" : haskey(d, "ends") ? "ends before $(d["ends"])" :
                         get(d, "status", "not run"), cold=(model, v) == first_run,
                  decimals=1,                           # the gate prints seconds with one decimal
                  date=first(get(meta, "date", ""), 10), version="Julia $(get(meta, "julia", "?"))",
                  commit="TIMES.jl $(get(meta, "commit", "?"))", threads=get(meta, "threads", nothing),
                  parts=parts,
                  # other: the whole run less the parts that were timed (never below zero: the parts
                  # are printed with one decimal each)
                  wall=r3(wall), other=wall === nothing ? nothing : r3(max(wall - sum(x for x in parts if x !== nothing; init=0.0), 0.0)),
                  harness=(write=r3(get(d, "write", nothing)),),
                  rows=int(get(d, "rows", nothing)), cols=int(get(d, "cols", nothing)), source=[logname])
    end
    return out
end

# unpublished: :drop (the public page: only entries for which rt_public holds), :only (only the others,
# for the local board) or :keep (every entry; --all and --local)
function run_timing(refdir, logdirs; meta=Dict{String,Any}(), all_models=false, only_local=false, unpublished=:drop)
    unpublished in (:drop, :only, :keep) || error("unpublished is :drop, :only or :keep, not $unpublished")
    suite = TOML.parsefile(joinpath(RT_REPO, "reference", "suite.toml"))["model"]
    runs = Any[]
    for m in suite
        red = get(m, "redistribute", "?")
        (only_local ? red != "public" : (all_models || red == "public")) || continue
        name = m["name"]
        jl = Dict{String,Any}()
        for ld in logdirs
            logs = isfile(joinpath(ld, "dd-$name.log")) ? ["dd-$name.log"] : !(all_models || only_local) ? String[] :
                   sort!(filter(f -> endswith(f, ".log") && occursin("chain", f), readdir(ld)))
            for f in logs
                merge!(jl, julia_entries(joinpath(ld, f), name, meta, "$(basename(normpath(ld)))/$f"))
            end
        end
        for v in RT_VARIANTS
            dir = joinpath(refdir, name, v)
            isfile(joinpath(dir, "manifest.json")) || continue
            man = JSON.parsefile(joinpath(dir, "manifest.json"))
            get(get(man, "suite_entry", Dict()), "redistribute", red) == red ||
                error("$name/$v: the reference was made under another redistribute setting than reference/suite.toml has")
            println("== $name/$v")
            timing, used = Any[], String[]
            for key in sort!(collect(filter(startswith("solve_"), keys(man["runs"]))))
                e = gams_entry(dir, man, key)
                e === nothing || (push!(timing, e); push!(used, key))
            end
            isempty(timing) && continue
            si = man["runs"][first(used)]["solveinfo"]   # the LP's size, as GAMS counts it
            rows, cols = int(si["numequ"]), int(si["numvar"])
            if haskey(jl, v)
                e = jl[v]
                (e.rows === nothing || (e.rows, e.cols) == (rows, cols)) ||
                    error("$name/$v: TIMES.jl's model has $(e.rows) rows and $(e.cols) columns, GAMS's $rows and $cols")
                push!(timing, Base.structdiff(e, NamedTuple{(:rows, :cols)}))
            end
            unpublished === :drop && filter!(rt_public, timing)
            unpublished === :only && filter!(!rt_public, timing)
            isempty(timing) && continue
            push!(runs, (run="$name/$v", model=name, variant=v, redistribute=red, rows=rows, cols=cols,
                         nonzeros=int(si["numnz"]), timing=timing))
        end
    end
    return (meta=(built=string(Dates.today()), host="workstation", threads=12,
                  units="seconds; null = not measured"), runs=runs)
end

"Put the timing data into the page's block `<script id=\"run-timing\" type=\"application/json\">`."
function embed_timing!(page, data; id="run-timing")
    all(r -> r.redistribute == "public", data.runs) ||
        error("only models with redistribute = \"public\" go into the page")
    all(r -> all(rt_public, r.timing), data.runs) ||
        error("no GAMS timing (#184) and no timing of a solver in RT_RESTRICTED (#182 d6) goes into the page")
    html = read(page, String)
    open_tag = "<script id=\"$id\" type=\"application/json\">"
    a = findfirst(open_tag, html)
    a === nothing && error("$page has no block $id")
    b = findnext("</script>", html, last(a))
    write(page, html[1:last(a)] * replace(JSON.json(data), "</" => "<\\/") * html[first(b):end])
    return page
end

function main_run_timing(args)
    pos, opt = String[], Dict{String,Any}()
    i = 1
    while i <= length(args)
        a = args[i]
        if a in ("--all", "--local", "--unpublished")
            opt[a[3:end]] = true
        elseif a == "--embed"
            opt["embed"] = i < length(args) && !startswith(args[i+1], "--") ? args[i+=1] :
                           joinpath(RT_REPO, "docs", "dashboard", "index.html")
        elseif a in ("--meta", "--out")
            opt[a[3:end]] = args[i+=1]
        else
            push!(pos, a)
        end
        i += 1
    end
    isempty(pos) && error("usage: run_timing.jl <reference dir> [<batch log dir> ...] [--meta <report.json>] [--out <file>] [--embed [<page>]] [--all | --local | --unpublished]")
    meta = haskey(opt, "meta") ? JSON.parsefile(opt["meta"])["meta"] : Dict{String,Any}()
    count(k -> haskey(opt, k), ("all", "local", "unpublished")) <= 1 || error("--all, --local and --unpublished go alone")
    haskey(opt, "unpublished") && haskey(opt, "embed") && error("--unpublished is for the local board; --embed refuses it")
    unpublished = haskey(opt, "unpublished") ? :only : (haskey(opt, "all") || haskey(opt, "local")) ? :keep : :drop
    data = run_timing(pos[1], pos[2:end]; meta, all_models=get(opt, "all", false), only_local=get(opt, "local", false), unpublished)
    for r in data.runs, e in r.timing
        p = e.parts
        f(x) = x === nothing ? "      -" : lpad(string(round(x; digits=1)), 7)
        println(rpad(r.run, 36), rpad(e.language, 9), rpad(e.solver, 6), lpad(r.cols, 8), " ", f(p.read), f(p.prep), f(p.coef),
                f(p.generate), f(p.solve), f(p.reports), f(e.other), f(e.wall), "  ", e.status, e.cold ? " (cold)" : "")
    end
    haskey(opt, "out") && open(io -> JSON.print(io, data, 1), opt["out"], "w")
    haskey(opt, "embed") && println("embedded in ", embed_timing!(opt["embed"], data))
    return data
end

abspath(PROGRAM_FILE) == @__FILE__() && main_run_timing(ARGS)
