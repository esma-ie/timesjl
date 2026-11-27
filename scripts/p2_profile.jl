# Phase 2, change 0: a warm CPU profile of model generation, to choose the speed changes from
# (docs/phase2-notes.md P2-2, P2-3, P2-6). Measurement only: nothing in src/ changes.
#
#   julia -t 1 --project=test scripts/p2_profile.jl <reference dir> [--variant as_run] [--root name=path ...]
#         [--warm-on <fixture prefix>] [--top 40] [--delay 0.01] [--no-identity] --out <folder> <model>
#
# One process: a warm-up build that is thrown away (the model itself, or with --warm-on a public
# fixture such as demo12_off, for a model whose build takes minutes: the code only the model reaches
# is then compiled inside the profiled build, and the summary shows how many samples that was), then
# one build under Julia's sampling profiler (Profile, one sample every --delay seconds), generate!
# statement by statement as scripts/p2_timing.jl does it, so that the same build also gives the time,
# the bytes allocated and the rows of each statement. Written to <folder> (large; not for the
# repository):
#   <model>-<variant>.summary.txt   the totals, the statements, the top functions and lines, the shares
#   <model>-<variant>.summary.json  the same as data
#   <model>-<variant>.flat.txt      Profile.print(format=:flat), every line with 0.05% of the samples
#   <model>-<variant>.tree.txt      Profile.print(format=:tree), branches with 0.5% of the samples
#   <model>-<variant>.identity.json the fingerprint of the generated LP (scripts/p2_identity.jl), not with --no-identity
#
# How the samples are counted. A sample is one stack. "self" counts it for the innermost Julia frame
# (time inside C code, such as the garbage collector or memory allocation, goes to the Julia function
# that called it); "total" counts it once for every function (or line) on the stack. The shares
# (memory, names, string labels, ...) are of all samples, by what is on the stack; a sample can be in
# several (an allocation inside a name being built counts in both). The memory share is the allocator
# and the collector together; the seconds of collection alone are in the build's totals (@timed).

include(joinpath(@__DIR__, "p2_timing.jl"))       # generate_by_statement!, p2_model, p2_fixture_model, lp_record, lp_fingerprint
import Profile, Printf

"The stacks of the profile buffer: per sample, its frames from the innermost outwards."
function p2_samples(data, lidict)
    Profile.has_meta(data) || error("p2_profile: this Julia's profile buffer has no per-sample metadata; not read")
    out = Vector{Vector{Base.StackTraces.StackFrame}}()
    i = length(data)
    while i > 0
        # a sample ends with threadid, taskid, cpu clock, sleep state, 0, 0 (Profile.nmeta entries and two zeros)
        (data[i] == 0 && data[i-1] == 0) || error("p2_profile: unexpected profile buffer layout")
        j = i - 2 - Profile.nmeta
        k = j
        while k > 0 && data[k] != 0
            k -= 1
        end
        frames = Base.StackTraces.StackFrame[]
        for ip in view(data, k+1:j)
            append!(frames, lidict[ip])                   # innermost first, inlined callees before their caller
        end
        push!(out, frames)
        i = k
    end
    return out
end

p2_file(f) = replace(string(f.file), '\\' => '/')
function p2_shortfile(f)
    p = p2_file(f)
    root = replace(pkgdir(TIMES), '\\' => '/') * "/"
    startswith(lowercase(p), lowercase(root)) && return "TIMES/" * p[length(root)+1:end]
    for mark in ("/src/", "/base/", "/stdlib/")
        i = findlast(mark, p)
        i === nothing && continue
        pkg = mark == "/src/" ? basename(p[1:first(i)-1]) * "/src/" : mark[2:end]
        return pkg * p[last(i)+1:end]
    end
    return basename(p)
end
p2_func(f) = string(f.func)

"What a sample is spent on, by the frames on its stack (it can be several)."
const P2_SHARES = [
    # the collector and the allocator together (the time in collection alone is the build's "garbage collection" seconds)
    ("memory: allocation and garbage collection", f -> f.from_c && occursin(r"gc_collect|gc_mark|gc_sweep|jl_gc_|gc_alloc"i, p2_func(f))),
    ("compilation (not warm)", f -> occursin(r"typeinf|jl_compile|jl_type_infer|emit_function|_jl_compile|codegen"i, p2_func(f))),
    ("dynamic dispatch (jl_apply_generic)", f -> f.from_c && occursin("apply_generic", p2_func(f))),
    ("row and column names (colname, set_name, name strings)", f -> p2_func(f) in ("colname", "set_name") ||
        (p2_func(f) == "set" && occursin(r"Name", string(f.linfo)))),
    ("building strings (string, join, print_to_string)", f -> p2_func(f) in ("string", "join", "print_to_string", "sprint", "repr", "_string")),
    ("upper/lower case of labels", f -> p2_func(f) in ("uppercase", "lowercase", "map") && occursin("strings/", p2_file(f))),
    ("hashing (hash of strings and tuples)", f -> p2_func(f) in ("hash", "memhash", "hash_bytes", "ijl_memhash", "jl_memhash") ||
        occursin("hashing.jl", p2_file(f))),
    ("comparing strings (==, isequal, cmp)", f -> (p2_func(f) in ("==", "isequal", "cmp", "isless", "_memcmp") && occursin("strings/", p2_file(f))) ||
        p2_func(f) == "memcmp"),
    ("Dict and Set lookups (dict.jl, set.jl)", f -> occursin(r"/(dict|set|iddict)\.jl$", p2_file(f))),
    ("sorting (sort.jl; gams_sort!)", f -> occursin(r"/sort\.jl$", p2_file(f)) || p2_func(f) == "gams_sort!"),
    ("reading the dump (Arrow, read_symbol)", f -> p2_func(f) in ("read_symbol", "_read_records") || occursin("/Arrow/", p2_file(f))),
    ("JuMP/MOI: adding rows (add_constraint)", f -> p2_func(f) in ("add_constraint", "add_constraints", "gconstraint!")),
    ("JuMP/MOI: adding columns (add_variable, getvar!)", f -> p2_func(f) in ("add_variable", "getvar!")),
    ("JuMP expressions (add_to_expression!, addterm!)", f -> p2_func(f) in ("add_to_expression!", "addterm!", "_add_or_set!")),
    ("the cancellation test of gconstraint! (_all_cancel)", f -> p2_func(f) == "_all_cancel"),
    ("applying bounds (apply_bounds!)", f -> p2_func(f) == "apply_bounds!"),
]

function p2_profile_summary(samples; top=40)
    n = length(samples)
    selff, totf = Dict{Tuple{String,String},Int}(), Dict{Tuple{String,String},Int}()
    selfl, totl = Dict{Tuple{String,String,Int},Int}(), Dict{Tuple{String,String,Int},Int}()
    shares = zeros(Int, length(P2_SHARES))
    gen = Dict{String,Int}()                               # samples under each generator (TIMES function called from the statement)
    seenf, seenl = Set{Tuple{String,String}}(), Set{Tuple{String,String,Int}}()
    for fr in samples
        empty!(seenf); empty!(seenl)
        first_julia = true
        for f in fr
            f.from_c && continue
            kf = (p2_func(f), p2_shortfile(f)); kl = (kf[1], kf[2], Int(f.line))
            if first_julia
                selff[kf] = get(selff, kf, 0) + 1; selfl[kl] = get(selfl, kl, 0) + 1
                first_julia = false
            end
            kf in seenf || (push!(seenf, kf); totf[kf] = get(totf, kf, 0) + 1)
            kl in seenl || (push!(seenl, kl); totl[kl] = get(totl, kl, 0) + 1)
        end
        for (i, (_, test)) in enumerate(P2_SHARES)
            any(test, fr) && (shares[i] += 1)
        end
    end
    pct(c) = n == 0 ? 0.0 : round(100c / n; digits=2)
    topn(d) = first(sort!(collect(d); by=x -> (-x[2], x[1])), top)
    return Dict{String,Any}(
        "samples" => n,
        "by_function_self" => [Dict("function" => k[1], "file" => k[2], "samples" => c, "percent" => pct(c), "total_percent" => pct(get(totf, k, 0))) for (k, c) in topn(selff)],
        "by_function_total" => [Dict("function" => k[1], "file" => k[2], "samples" => c, "percent" => pct(c), "self_percent" => pct(get(selff, k, 0))) for (k, c) in topn(totf)],
        "by_line_self" => [Dict("function" => k[1], "file" => k[2], "line" => k[3], "samples" => c, "percent" => pct(c), "total_percent" => pct(get(totl, k, 0))) for (k, c) in topn(selfl)],
        "by_line_total" => [Dict("function" => k[1], "file" => k[2], "line" => k[3], "samples" => c, "percent" => pct(c), "self_percent" => pct(get(selfl, k, 0))) for (k, c) in topn(totl)],
        "shares" => [Dict("what" => P2_SHARES[i][1], "samples" => shares[i], "percent" => pct(shares[i])) for i in eachindex(P2_SHARES)])
end

function p2_profile_text(io, s)
    m, t, p = s["meta"], s["build"], s["profile"]
    println(io, m["model"], "/", m["variant"], ": warm profile of model generation (generate!, from the ", m["from"], " dump)")
    println(io, "TIMES.jl ", m["commit"], ", Julia ", m["julia"], ", ", m["threads"], " thread, ", m["date"], "; warm-up: ", m["warm_up"])
    println(io, "one build, generate! statement by statement, under Profile (one sample every ", m["delay"], " s)")
    println(io)
    Printf.@printf(io, "generation      %10.2f s   (of which garbage collection %.2f s)\n", t["generate_s"], t["generate_gc_s"])
    Printf.@printf(io, "allocated       %10.2f GiB (%.0f bytes per row)\n", t["generate_bytes"] / 2^30, t["generate_bytes"] / max(t["rows"], 1))
    Printf.@printf(io, "model           %10d rows, %d columns, %d terms\n", t["rows"], t["columns"], get(t, "nonzeros", 0))
    Printf.@printf(io, "samples         %10d\n\n", p["samples"])
    println(io, "Statements of generate!, slowest first (seconds, share, GiB allocated, rows, columns created)")
    tot = max(t["generate_s"], 1e-9)
    for st in sort(t["statements"]; by=x -> -x["seconds"])
        st["seconds"] < 0.0005 * tot && st["rows"] == 0 && continue
        Printf.@printf(io, "  %9.2f s %5.1f%% %8.2f GiB %9d rows %9d cols  %s\n", st["seconds"], 100 * st["seconds"] / tot, st["bytes"] / 2^30,
                       st["rows"], st["columns"], st["statement"])
    end
    println(io, "\nWhat the samples are spent on (share of all samples; a sample can be in several)")
    for sh in p["shares"]
        Printf.@printf(io, "  %6.2f%%  %s\n", sh["percent"], sh["what"])
    end
    for (key, title, other) in (("by_function_self", "Functions by self time (innermost Julia frame)", "total_percent"),
                                ("by_function_total", "Functions by total time (anywhere on the stack)", "self_percent"),
                                ("by_line_self", "Lines by self time", "total_percent"),
                                ("by_line_total", "Lines by total time", "self_percent"))
        println(io, "\n", title, ": share, (", replace(other, "_percent" => ""), " share), function, file", occursin("line", key) ? ":line" : "")
        for r in p[key]
            Printf.@printf(io, "  %6.2f%% (%6.2f%%)  %-40s %s%s\n", r["percent"], r[other], r["function"], r["file"],
                           haskey(r, "line") ? ":" * string(r["line"]) : "")
        end
    end
end

function p2_profile(refdir, model, outdir; variant="reduce_off", roots=Dict{String,String}(), warm_on=nothing, top=40, delay=0.01,
                    threads=1, identity=true)
    Threads.nthreads() == threads || error("p2_profile: Julia runs on $(Threads.nthreads()) threads; start it with `julia -t $threads`")
    say(x...) = (println(x...); flush(stdout))
    make() = p2_model(refdir, model; variant, roots, from="presolve")
    t = @elapsed begin
        if warm_on === nothing
            tmw, _ = p2_build(make; families=true)
            identity && lp_fingerprint(lp_record(tmw))
            tmw = nothing
        else
            tmw, _ = p2_build(() -> p2_fixture_model(warm_on); families=true)
            lp_fingerprint(lp_record(tmw))
            tmw = nothing
        end
    end
    say("== ", model, "/", variant, ": warmed up on ", warm_on === nothing ? "the model itself" : "fixture $warm_on", " in ", round(t; digits=1), " s (thrown away)")
    GC.gc(true)
    Profile.init(n=2^27, delay=delay)
    Profile.clear()
    tm = make()
    u = untranslated_families(tm)
    isempty(u) || error("p2_profile: not generated, needs " * join(unique(x.family for x in u), ", "))
    stepped(tm) && error("p2_profile: a stepped run has one model per step")
    fs = statement_functions()
    st = Profile.@profile generate_by_statement!(tm, fs)
    build = Dict{String,Any}("statements" => st, "generate_s" => r3(sum(s["seconds"] for s in st)),
                             "generate_bytes" => sum(s["bytes"] for s in st), "generate_gc_s" => r3(sum(s["gc_seconds"] for s in st)),
                             "rows" => JuMP.num_constraints(tm.model; count_variable_in_set_constraints=false),
                             "columns" => JuMP.num_variables(tm.model))
    say("== ", model, "/", variant, ": generated under the profiler in ", build["generate_s"], " s, ", round(build["generate_bytes"] / 2^30; digits=2),
        " GiB allocated, GC ", build["generate_gc_s"], " s; ", build["rows"], " rows, ", build["columns"], " columns")
    mkpath(outdir)
    base = joinpath(outdir, "$model-$variant")
    data, lidict = Profile.retrieve()
    Profile.is_buffer_full() && say("== ", model, "/", variant, ": the profile buffer filled up: the last part of the build has no samples")
    samples = p2_samples(data, lidict)
    prof = p2_profile_summary(samples; top)
    prof["buffer_full"] = Profile.is_buffer_full()
    n = length(samples)
    open(base * ".flat.txt", "w") do io
        Profile.print(IOContext(io, :displaysize => (100000, 250)), data, lidict; format=:flat, sortedby=:count, C=false, mincount=max(1, n ÷ 2000))
    end
    open(base * ".tree.txt", "w") do io
        Profile.print(IOContext(io, :displaysize => (100000, 400)), data, lidict; format=:tree, C=false, mincount=max(1, n ÷ 200), maxdepth=60)
    end
    samples = nothing; data = nothing; lidict = nothing
    Profile.clear()
    if identity
        fp = lp_fingerprint(lp_record(tm))
        build["nonzeros"] = fp["nonzeros"]
        build["lp"] = fp["lp"]
        fp["format"] = P2_FORMAT; fp["note"] = "LP only (no state): written by scripts/p2_profile.jl"
        p2_write(base * ".identity.json", fp)
    end
    red = get(get(Dict(m["name"] => m for m in TOML.parsefile(joinpath(P2_REPO, "reference", "suite.toml"))["model"]), model, Dict()), "redistribute", "?")
    s = Dict{String,Any}(
        "meta" => Dict{String,Any}("model" => model, "variant" => variant, "from" => "presolve", "commit" => p2_commit(), "julia" => string(VERSION),
                                   "threads" => threads, "date" => string(Dates.now(Dates.UTC)), "delay" => delay, "redistribute" => red,
                                   "warm_up" => warm_on === nothing ? "one build of the model itself, thrown away" :
                                                "fixture $warm_on (code only this model reaches is compiled inside the profiled build)"),
        "build" => build, "profile" => prof)
    p2_write(base * ".summary.json", s)
    open(io -> p2_profile_text(io, s), base * ".summary.txt", "w")
    say("== ", model, "/", variant, ": ", n, " samples; written ", base, ".summary.txt, .summary.json, .flat.txt, .tree.txt", identity ? ", .identity.json" : "")
    return s
end

function p2_profile_main(args)
    args = collect(args)
    opt = Dict{String,String}()
    for o in ("--variant", "--warm-on", "--top", "--delay", "--out", "--threads")
        i = findfirst(==(o), args)
        i === nothing && continue
        opt[o] = args[i+1]
        deleteat!(args, i:i+1)
    end
    identity = !("--no-identity" in args)
    filter!(!=("--no-identity"), args)
    haskey(opt, "--out") || error("usage: p2_profile.jl <reference dir> [--variant v] [--root n=p ...] [--warm-on <fixture>] [--top 40] [--delay 0.01] [--no-identity] --out <folder> <model>")
    refdir, roots, models = parse_probe_args(args)
    length(models) == 1 || error("one model per call, got $(length(models))")
    p2_profile(refdir, models[1], opt["--out"]; variant=get(opt, "--variant", "reduce_off"), roots, warm_on=get(opt, "--warm-on", nothing),
               top=parse(Int, get(opt, "--top", "40")), delay=parse(Float64, get(opt, "--delay", "0.01")),
               threads=parse(Int, get(opt, "--threads", "1")), identity)
end

if abspath(PROGRAM_FILE) == @__FILE__
    p2_profile_main(ARGS)
end
