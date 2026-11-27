# Phase 2, change 0: the timing of model generation against the P2-6 target (docs/phase2-notes.md:
# model generation within 5x GAMS, warm). Measurement only: no GAMS statement is translated here and
# nothing in src/ changes.
#
#   julia -t 1 --project=test scripts/p2_timing.jl <reference dir> [--variant as_run] [--root name=path ...]
#         [--from presolve|input] [--repeats 3] [--threads 1] [--warm-on <fixture prefix>]
#         [--no-families] [--no-identity] [--identity-out <file.json>] --out <file.json> <model>
#
# <reference dir>, --variant and --root are those of scripts/m11_probe.jl; one model per call.
#
# TIMES.jl. Warm: the model is built once and that build is thrown away (it holds Julia's compilation),
# then built --repeats times (default 3); the record holds every repeat, the minimum and the median.
# Each repeat starts from a new TimesModel, so it reads the dump again: the dump is read lazily, each
# set or parameter from its Arrow file inside the first step that uses it, and that reading is in the
# step's time. The timed stretch ends at the finished JuMP model (James, 27 Nov 2026, p2-q4): no copy
# into a solver. --warm-on <prefix> warms up on a public fixture (test/fixtures/public_fixtures.toml,
# e.g. demo12_off) instead of the model itself, for a model whose build takes minutes: code that only
# the model reaches is then compiled inside the first repeat, and the record says so.
# Stages, as the code has them:
#   load      TimesModel on the dump (its manifest and label list only)
#   prep      with --from input: TIMES.PRESOLVE_STEPS input -> ppm (preprocessing), step by step
#   coef      with --from input: TIMES.PRESOLVE_STEPS ppm -> presolve (coefficients, equation data)
#   check     untranslated_families (generate! runs it first)
#   generate  generate!(tm) as one call: the figure for P2-6
# and, in one more build (not with --no-families), the statements of generate! one by one
# (src/model/generate.jl is read, so the list is always the code's own): seconds, bytes allocated, rows
# and columns added and the equation families created by each. That build must give the same LP as
# generate! (scripts/p2_identity.jl, bit for bit), or the script stops.
# Every repeat's LP is fingerprinted outside the timed stretch (not with --no-identity): equal hashes
# across the repeats are the record's evidence that generation is deterministic. --identity-out also
# writes the first repeat's whole fingerprint, with its state (read outside the timed stretch), as
# scripts/p2_identity.jl --write does, so that a model whose build takes minutes is built once for both.
# Julia runs on --threads threads (default 1; James's provisional choice, p2-q5): the script stops if
# Julia was started with another number (`julia -t N`).
#
# GAMS. Nothing is run: the figures are read from the reference run's own files, and only from runs
# that time no Restricted Solver of the GAMS EULA (CLAUDE.md "Solver timings"). No file of a
# solve_cplex run (or of any solve run but GAMS/HiGHS) is opened:
#   runs.convert    the CONVERT run (GAMS generates the model and CONVERT writes it out; no solver
#                   solves): the model attribute resGen (GAMS's own time to generate the model), and
#                   from its profile (raw/tjl_convert_profile.txt, profile=1) the seconds of the
#                   "Equation" records, per equation
#   runs.presolve   the pre-solve run (SOLVE_NOW=NO): from its profile and listing, the seconds of
#                   preprocessing (maindrv.mod init_ext to ppm_ext) and of the statements after it
#                   (coefficients and equation data), without the harness's dumps (Unload records)
#   runs.solve_highs  when it ended optimal: resGen of the GAMS/HiGHS run
# The method (James, 27 Nov 2026, p2-q3): GAMS's generation time is resGen of the GAMS/HiGHS run where
# there is one, else resGen of the CONVERT run; GAMS's time before generation is the pre-solve run's.
# What is missing is listed in the record ("missing"), never filled in. Timings of the two sides
# compare only when both ran on the same machine.

include(joinpath(@__DIR__, "p2_identity.jl"))     # p2_model, p2_fixture_model, p2_chain!, lp_record, lp_fingerprint; m11_probe.jl
include(joinpath(@__DIR__, "gams_profile.jl"))    # include_summary, profile_lines, prep_ranges, execution_start, unload_seconds
import Dates, LibGit2, Statistics

"The runs of a reference whose GAMS timings may be read here: none of them times a Restricted Solver."
const P2_GAMS_RUNS = ("convert", "presolve", "solve_highs")

r3(x) = x === nothing ? nothing : round(Float64(x); digits=3)

"""
    generate_statements() -> Vector{String}

The statements of `generate!` from its first generator to the one before `return n`, read from
src/model/generate.jl: one per line, as the function is written. An error if the function no longer
has that shape (the per-family build is then not possible; the whole-`generate!` timing is unaffected).
"""
function generate_statements()
    src = readlines(joinpath(pkgdir(TIMES), "src", "model", "generate.jl"))
    i0 = findfirst(l -> startswith(l, "function generate!(tm::TimesModel)"), src)
    i0 === nothing && error("p2_timing: generate!(tm::TimesModel) not found in src/model/generate.jl")
    i1 = findnext(==("end"), src, i0)
    body = src[i0+1:i1-1]
    k = findfirst(l -> occursin(r"^\s*n = \w+!\(tm\)", l), body)
    k === nothing && error("p2_timing: generate! has no first generator `n = ...!(tm)`")
    strip(body[end]) == "return n" || error("p2_timing: generate! does not end with `return n`")
    # before the first generator generate! only refuses (untranslated families, a stepped run)
    stmts = String[]
    for l in body[k:end-1]
        s = strip(first(split(l, " #"; limit=2)))
        isempty(s) && continue
        ex = Meta.parse(s; raise=false)
        (ex isa Expr && ex.head in (:incomplete, :error)) && error("p2_timing: a statement of generate! spans lines: $s")
        push!(stmts, s)
    end
    return stmts
end

"""
    generate_by_statement!(tm) -> Vector

`generate!` statement by statement (after its refusals, which the caller runs): per statement the
seconds, bytes allocated, GC seconds, rows and columns added and equation families created.
"""
generate_by_statement!(tm::TimesModel) = generate_by_statement!(tm, statement_functions())

"One function `(tm, n) -> n` per statement of `generate!`, compiled before anything is timed."
function statement_functions()
    fs = Any[]
    for s in generate_statements()
        f = Core.eval(TIMES, :((tm, n) -> begin
            $(Meta.parse(s))
            n
        end))
        Base.invokelatest(precompile, f, (TimesModel, Int))
        push!(fs, (s, f))
    end
    return fs
end

function generate_by_statement!(tm::TimesModel, fs)
    out = Any[]
    for (s, f) in fs
        nf, nc = length(tm.eqs.order), JuMP.num_variables(tm.model)
        r = @timed Base.invokelatest(f, tm, 0)
        push!(out, Dict{String,Any}("statement" => s, "seconds" => r3(r.time), "bytes" => r.bytes, "gc_seconds" => r3(r.gctime),
                                    "rows" => r.value, "columns" => JuMP.num_variables(tm.model) - nc,
                                    "families" => tm.eqs.order[nf+1:end]))
    end
    return out
end

"One build of the model: the stages' times; the model is returned generated (`families`: statement by statement)."
function p2_build(make; from="presolve", families=false, state=nothing)
    rec = Dict{String,Any}()
    r = @timed make()
    tm = r.value
    rec["load_s"] = r3(r.time)
    if from == "input"
        steps = Any[]
        p2_chain!(tm; each=(a, name, f) -> begin
            t = @timed f()
            push!(steps, Dict{String,Any}("after" => a, "step" => name, "seconds" => r3(t.time), "bytes" => t.bytes))
        end)
        rec["steps"] = steps
        rec["prep_s"] = r3(sum(s["seconds"] for s in steps if s["after"] in ("input", "init", "prep", "prelv")))
        rec["coef_s"] = r3(sum(s["seconds"] for s in steps if s["after"] in ("ppm", "coef")))
    end
    r = @timed untranslated_families(tm)
    isempty(r.value) || error("p2_timing: not generated, needs " * join(unique(x.family for x in r.value), ", "))
    stepped(tm) && error("p2_timing: a stepped run has one model per step; not timed here")
    rec["check_s"] = r3(r.time)
    state === nothing || (state[] = state_fingerprint(tm))      # not timed; the dump's records are not read into tm
    if families
        st = generate_by_statement!(tm)
        rec["statements"] = st
        rec["generate_s"] = r3(sum(s["seconds"] for s in st))
        rec["generate_bytes"] = sum(s["bytes"] for s in st)
        rec["generate_gc_s"] = r3(sum(s["gc_seconds"] for s in st))
    else
        r = @timed generate!(tm)
        rec["generate_s"] = r3(r.time)
        rec["generate_bytes"] = r.bytes
        rec["generate_gc_s"] = r3(r.gctime)
    end
    rec["rows"] = JuMP.num_constraints(tm.model; count_variable_in_set_constraints=false)
    rec["columns"] = JuMP.num_variables(tm.model)
    return tm, rec
end

"Seconds and rows per equation, from the Equation records of a GAMS profile (a run that generates the model)."
function gams_equation_records(path)
    eq = Dict{String,Any}()
    for ln in eachline(path)
        f = split(ln)
        (length(f) >= 6 && f[5] == "Equation") || continue
        t, n = tryparse(Float64, f[3]), tryparse(Int, f[2])
        (t === nothing || n === nothing) && continue
        e = get!(() -> Dict{String,Any}("seconds" => 0.0, "rows" => 0), eq, String(f[6]))
        e["seconds"] = round(e["seconds"] + t; digits=3); e["rows"] += n
    end
    return eq
end

"""
    gams_generation(dir, manifest) -> Dict

GAMS's generation time for the reference run in `dir`, from the runs in `P2_GAMS_RUNS` only (see the
header), with every figure's source, and what is missing.
"""
function gams_generation(dir, man)
    out = Dict{String,Any}("missing" => String[], "sources" => String[],
        "method" => "p2-q3 (James, 27 Nov 2026): nothing run here; read from the reference run's files. " *
                    "generate_s is the GAMS model attribute resGen of the GAMS/HiGHS run when the reference has one " *
                    "that ended optimal, else of the CONVERT run (GAMS generates the model, CONVERT writes it out, " *
                    "no solver solves). prep_s and coef_s are the profile seconds (profile=1) of the pre-solve run " *
                    "(SOLVE_NOW=NO): maindrv.mod from init_ext to the end of ppm_ext, and the statements after it, " *
                    "without the harness's dumps (Unload records). No run of CPLEX or another Restricted Solver is read.")
    runs = man["runs"]
    raw(tag, ext) = joinpath(dir, "raw", "tjl_$tag$ext")
    stamp(run) = (v = match(r"GAMS (\d+\.\d+\.\d+)", get(run, "gams_version", "")); v === nothing ? nothing : v[1])
    out["times"] = string("TIMES v", man["times"]["version"], " ", first(man["times"]["commit"], 7))
    out["reference_created"] = first(get(man, "created_utc", ""), 10)
    out["gams_threads_option"] = get(get(man, "limits", Dict()), "threads", nothing)
    gen = Dict{String,Any}()
    # the CONVERT run
    c = get(runs, "convert", nothing)
    if c !== nothing && get(c, "returncode", 1) == 0 && get(get(c, "solveinfo", Dict()), "resgen", nothing) !== nothing
        si = c["solveinfo"]
        gen["convert"] = r3(si["resgen"])
        out["gams_version"] = stamp(c)
        out["rows"], out["columns"], out["nonzeros"] = Int(si["numequ"]), Int(si["numvar"]), Int(si["numnz"])
        out["convert_wall_s"] = r3(c["wall_s"])
        push!(out["sources"], "manifest.json runs.convert.solveinfo.resgen")
        if isfile(raw("convert", "_profile.txt"))
            eq = gams_equation_records(raw("convert", "_profile.txt"))
            out["equations"] = eq
            out["equation_records_s"] = r3(sum((e["seconds"] for e in values(eq)); init=0.0))
            push!(out["sources"], "raw/tjl_convert_profile.txt (Equation records)")
        else
            push!(out["missing"], "raw/tjl_convert_profile.txt: no per-equation seconds")
        end
    else
        push!(out["missing"], "runs.convert with return code 0 and solveinfo.resgen: no CONVERT-run generation time")
    end
    # the GAMS/HiGHS run
    hs = get(runs, "solve_highs", nothing)
    hsi = hs === nothing ? nothing : get(hs, "solveinfo", nothing)
    if hs !== nothing && get(hs, "returncode", 1) == 0 && hsi isa AbstractDict && get(hsi, "modelstat", 0) == 1 &&
       get(hsi, "resgen", nothing) !== nothing
        gen["highs"] = r3(hsi["resgen"])
        push!(out["sources"], "manifest.json runs.solve_highs.solveinfo.resgen")
    else
        push!(out["missing"], "runs.solve_highs ended optimal: no GAMS/HiGHS run to take resGen from (the CONVERT run's is used)")
    end
    out["resgen_s"] = gen
    out["generate_s"] = get(gen, "highs", get(gen, "convert", nothing))
    out["generate_source"] = haskey(gen, "highs") ? "resGen of the GAMS/HiGHS run" : haskey(gen, "convert") ? "resGen of the CONVERT run" : nothing
    # the pre-solve run
    p = get(runs, "presolve", nothing)
    if p !== nothing && get(p, "returncode", 1) == 0 && all(isfile, (raw("presolve", ".lst"), raw("presolve", "_profile.txt"), raw("presolve", ".log")))
        pr = prep_ranges(include_summary(raw("presolve", ".lst")))
        prof = profile_lines(raw("presolve", "_profile.txt"); skip=("Unload", "GAMS"))
        between(a, b) = sum((s for (l, s) in prof if a <= l < b); init=0.0)
        from, to = pr["total"]
        t0 = execution_start(raw("presolve", ".log"))
        out["prep_s"] = r3(between(from, to))
        out["coef_s"] = r3(between(to, typemax(Int)))
        out["read_s"] = t0 === nothing ? nothing : r3(t0 + between(0, from))
        out["presolve_wall_s"] = r3(p["wall_s"])
        out["presolve_dumps_s"] = r3(unload_seconds(raw("presolve", "_profile.txt")))
        push!(out["sources"], "raw/tjl_presolve.lst, raw/tjl_presolve_profile.txt, raw/tjl_presolve.log")
    else
        push!(out["missing"], "runs.presolve with its listing, profile and log in raw/: no GAMS time before generation")
    end
    return out
end

function p2_commit()
    try
        repo = LibGit2.GitRepo(P2_REPO)
        string(LibGit2.head_oid(repo))[1:9] * (LibGit2.isdirty(repo) ? "+changes" : "")
    catch
        "unknown"
    end
end

function p2_timing(refdir, model; variant="reduce_off", roots=Dict{String,String}(), from="presolve", repeats=3, threads=1,
                   warm_on=nothing, families=true, identity=true, identity_out=nothing)
    Threads.nthreads() == threads ||
        error("p2_timing: Julia runs on $(Threads.nthreads()) threads, --threads is $threads; start it with `julia -t $threads`")
    identity_out === nothing || identity || error("--identity-out needs the fingerprints (not with --no-identity)")
    dir = joinpath(refdir, model, variant)
    man = JSON.parsefile(joinpath(dir, "manifest.json"))
    suite = Dict(m["name"] => m for m in TOML.parsefile(joinpath(P2_REPO, "reference", "suite.toml"))["model"])
    make() = p2_model(refdir, model; variant, roots, from)
    say(x...) = (println(x...); flush(stdout))
    lphash(tm) = identity ? lp_fingerprint(lp_record(tm))["lp"] : nothing

    # the build that is thrown away
    t = @elapsed begin
        if warm_on === nothing
            p2_build(make; from)
            families && p2_build(make; from, families=true)
        else
            from == "presolve" || error("--warm-on warms up generation only; not with --from input")
            p2_build(() -> p2_fixture_model(warm_on))
            families && p2_build(() -> p2_fixture_model(warm_on); families=true)
            identity && lphash(p2_build(() -> p2_fixture_model(warm_on))[1])
        end
    end
    say("== ", model, "/", variant, ": warmed up on ", warm_on === nothing ? "the model itself" : "fixture $warm_on", " in ", round(t; digits=1), " s (thrown away)")
    GC.gc(true)

    reps = Any[]
    for i in 1:repeats
        if i == 1 && identity_out !== nothing
            st = Ref{Any}()
            tm, rec = p2_build(make; from, state=st)
            fp = lp_fingerprint(lp_record(tm))
            merge!(fp, Dict("state" => st[], "format" => P2_FORMAT, "format_version" => P2_FORMAT_VERSION, "from" => from,
                            "times_version" => string(TIMES.TIMES_GAMS_VERSION, " @ ", TIMES.TIMES_GAMS_COMMIT), "julia" => string(VERSION)))
            say("== ", model, "/", variant, ": fingerprint written to ", p2_write(identity_out, fp))
            rec["lp"] = fp["lp"]
        else
            tm, rec = p2_build(make; from)
            rec["lp"] = lphash(tm)
        end
        push!(reps, rec)
        say("== ", model, "/", variant, ": repeat ", i, ": generate! ", rec["generate_s"], " s, ", round(rec["generate_bytes"] / 2^30; digits=2),
            " GiB allocated, GC ", rec["generate_gc_s"], " s; ", rec["rows"], " rows, ", rec["columns"], " columns",
            from == "input" ? "; prep $(rec["prep_s"]) s, coef $(rec["coef_s"]) s" : "")
        tm = nothing
        GC.gc(true)
    end
    stat(k) = (v = [Float64(r[k]) for r in reps]; Dict("min" => r3(minimum(v)), "median" => r3(Statistics.median(v))))
    julia = Dict{String,Any}("repeats" => reps, "generate_s" => stat("generate_s"), "load_s" => stat("load_s"), "check_s" => stat("check_s"),
                             "rows" => reps[1]["rows"], "columns" => reps[1]["columns"])
    from == "input" && (julia["prep_s"] = stat("prep_s"); julia["coef_s"] = stat("coef_s"))
    if identity
        julia["deterministic"] = length(unique(r["lp"] for r in reps)) == 1
        julia["deterministic"] || say("== ", model, "/", variant, ": the repeats did NOT give the same LP (hashes in the record)")
    end
    if families
        tm, rec = p2_build(make; from, families=true)
        h = lphash(tm)
        identity && h != reps[1]["lp"] && error("p2_timing: generate! statement by statement gave another LP than generate! ($h, $(reps[1]["lp"]))")
        (rec["rows"], rec["columns"]) == (julia["rows"], julia["columns"]) || error("p2_timing: generate! statement by statement gave another size")
        julia["by_statement"] = Dict{String,Any}("statements" => rec["statements"], "generate_s" => rec["generate_s"],
            "same_lp_as_generate" => identity ? true : nothing,
            "note" => "one build, generate! statement by statement; a set or parameter is read from the dump inside the first statement that uses it")
        tm = nothing
        GC.gc(true)
    end

    gams = gams_generation(dir, man)
    notes = String[]
    ratio = Dict{String,Any}()
    if gams["generate_s"] !== nothing && gams["generate_s"] > 0
        ratio["generate"] = round(julia["generate_s"]["min"] / gams["generate_s"]; digits=1)
        ratio["generate_definition"] = "TIMES.jl generate! (minimum of the warm repeats) / GAMS " * gams["generate_source"]
    end
    if from == "input" && get(gams, "prep_s", nothing) !== nothing && gams["generate_s"] !== nothing
        j = julia["prep_s"]["min"] + julia["coef_s"]["min"] + julia["generate_s"]["min"]
        g = gams["prep_s"] + gams["coef_s"] + gams["generate_s"]
        ratio["prep_to_model"] = round(j / g; digits=1)
        ratio["prep_to_model_definition"] = "TIMES.jl prep + coef + generate! (minimum of each) / GAMS prep_s + coef_s + generate_s"
    end
    haskey(gams, "rows") && (gams["rows"], gams["columns"]) != (julia["rows"], julia["columns"]) &&
        push!(notes, "TIMES.jl's model has $(julia["rows"]) rows and $(julia["columns"]) columns, GAMS's $(gams["rows"]) and $(gams["columns"])")
    string(TIMES.TIMES_GAMS_VERSION) == string(man["times"]["version"]) ||
        push!(notes, "TIMES.jl translates TIMES v$(TIMES.TIMES_GAMS_VERSION), the reference was run with v$(man["times"]["version"])")
    warm_on === nothing || push!(notes, "warm-up on fixture $warm_on, not on the model: code only this model reaches is compiled inside the first repeat")
    repeats < 3 && push!(notes, "$repeats repeat(s), fewer than the default 3")
    push!(notes, "GAMS ran with threads=$(gams["gams_threads_option"]) (its generation is not known to use more than one); TIMES.jl on $threads Julia thread(s)")
    red = get(get(suite, model, Dict()), "redistribute", "?")
    red == "public" || push!(notes, "redistribute = \"$red\" in reference/suite.toml: this record stays local")
    return Dict{String,Any}(
        "meta" => Dict{String,Any}("model" => model, "variant" => variant, "from" => from, "commit" => p2_commit(), "julia" => string(VERSION),
                                   "threads" => threads, "date" => string(Dates.now(Dates.UTC)), "repeats" => repeats,
                                   "warm_up" => warm_on === nothing ? "one build of the model itself, thrown away" : "fixture $warm_on",
                                   "timed_stretch" => "ends at the finished JuMP model (p2-q4)", "redistribute" => red,
                                   "units" => "seconds; bytes allocated"),
        "julia" => julia, "gams" => gams, "ratio" => ratio, "notes" => notes)
end

function p2_timing_main(args)
    args = collect(args)
    opt = Dict{String,String}()
    for o in ("--variant", "--from", "--repeats", "--threads", "--warm-on", "--out", "--identity-out")
        i = findfirst(==(o), args)
        i === nothing && continue
        opt[o] = args[i+1]
        deleteat!(args, i:i+1)
    end
    flags = Set(filter(a -> a in ("--no-families", "--no-identity"), args))
    filter!(a -> !(a in flags), args)
    haskey(opt, "--out") || error("usage: p2_timing.jl <reference dir> [--variant v] [--root n=p ...] [--from presolve|input] [--repeats 3] [--threads 1] [--warm-on <fixture>] [--no-families] [--no-identity] [--identity-out <file.json>] --out <file.json> <model>")
    refdir, roots, models = parse_probe_args(args)
    length(models) == 1 || error("one model per call, got $(length(models))")
    rec = p2_timing(refdir, models[1]; variant=get(opt, "--variant", "reduce_off"), roots, from=get(opt, "--from", "presolve"),
                    repeats=parse(Int, get(opt, "--repeats", "3")), threads=parse(Int, get(opt, "--threads", "1")),
                    warm_on=get(opt, "--warm-on", nothing), families=!("--no-families" in flags), identity=!("--no-identity" in flags), identity_out=get(opt, "--identity-out", nothing))
    p2_write(opt["--out"], rec)
    j, g = rec["julia"], rec["gams"]
    println("== ", models[1], ": TIMES.jl generate! min ", j["generate_s"]["min"], " s, median ", j["generate_s"]["median"], " s (",
            rec["meta"]["repeats"], " warm repeats, ", rec["meta"]["threads"], " thread); GAMS ",
            g["generate_s"] === nothing ? "generation time not recorded" : "$(g["generate_s"]) s ($(g["generate_source"]))",
            haskey(rec["ratio"], "generate") ? "; ratio $(rec["ratio"]["generate"])" : "")
    isempty(g["missing"]) || foreach(m -> println("     not recorded: ", m), g["missing"])
    println("== ", models[1], ": record written to ", opt["--out"])
end

if abspath(PROGRAM_FILE) == @__FILE__
    p2_timing_main(ARGS)
end
