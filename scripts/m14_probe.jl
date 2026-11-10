# M1.4: compile a model's run file with src/dd/compile.jl (no GAMS) and compare the result with the
# harness's input dump:
#   - the files included, in order and by level, against the Include File Summary of GAMS's listing;
#   - the symbols declared (sets, parameters, variables, equations, aliases);
#   - every set and parameter: keys, record order, values, EPS, element text;
#   - the dump's label order (G55).
#
#   julia --project=test scripts/m14_probe.jl <reference dir> --sources <timesjl-sources> [--pre] <model> ...
#
# <model> is a reference folder name, e.g. TIMES_Demo-demo12; both variants are compiled. --pre stops
# at `$BATINCLUDE maindrv.mod` (changes 2-4) instead of compiling the whole program (change 2b).
# Only open models (CLAUDE.md); TIM and JRC-EU-TIMES are refused.
using TIMES
using TIMES: GamsCompile, gams_compile!, grecords, gdx_uels, gdx_symbols
using TIMES.Reference: load_dump, read_symbol, SV_EPS

const MODEL_DIRS = Dict(
    "TIMES_Demo-demo12" => "TIMES_Demo/model",
    "TIMES-NZ-steady-v308" => "TIMES-NZ/dd/steady-v308", "TIMES-NZ-shift-v308" => "TIMES-NZ/dd/shift-v308",
    "OTCGEN-gc_ref" => "OTCGEN/dd/gc_ref", "OTNYC-s1_nyc_ref" => "OTNYC/dd/s1_nyc_ref",
    "OTUS9r-reference" => "OTUS9r/dd/reference", "OTUS9r-tax1_wo_mou" => "OTUS9r/dd/tax1_wo_mou")

# GAMS's Include File Summary (level, file name), less the run file and the harness's .tjlref files
function gams_includes(lst)
    lines = readlines(lst)
    i0 = findfirst(l -> occursin("Include File Summary", l), lines)
    i0 === nothing && return nothing
    out = Tuple{Int,String}[]
    for l in lines[i0:end]
        m = match(r"^\s+\d+\s+\d+\s+(INPUT|BATINCLUDE|INCLUDE)\s+\d+\s+\d+\s+(\d+)\s+(.*)$", l)
        m === nothing && continue
        push!(out, (parse(Int, m[2]), lowercase(basename(replace(m[3], "\\" => "/")))))
    end
    filter(x -> !endswith(x[2], ".tjlref"), out)[2:end]
end

function probe(ref, sources, model, variant; full=true)
    dir = joinpath(ref, model, variant)
    run = joinpath(dir, "raw", "tjl_presolve.run")
    isfile(run) && isdir(joinpath(dir, "input")) || return println("== $model/$variant: no input dump, skipped")
    g = GamsCompile(dirs=[joinpath(sources, "TIMES_model"), joinpath(sources, MODEL_DIRS[model])]; full)
    g.globals["RUN_NAME"] = model          # the harness's --run_name
    t = @elapsed try
        gams_compile!(g, run)
    catch e
        return println("== $model/$variant: compile stops: ", sprint(showerror, e))
    end
    d = load_dump(joinpath(dir, "input"))
    notes = String[]
    # the files included
    if full
        gi = gams_includes(joinpath(dir, "raw", "tjl_presolve.lst"))
        mi = [(a, lowercase(b)) for (a, b) in filter(x -> !endswith(lowercase(x[2]), ".tjlref"), g.trace)[2:end]]
        k = gi === nothing ? nothing : findfirst(i -> i > length(mi) || gi[i] != mi[i], 1:length(gi))
        tr = gi === nothing ? "no listing" : k === nothing && length(mi) == length(gi) ? "$(length(gi)) of $(length(gi)) as GAMS" :
             "differs at $(something(k, length(gi) + 1)): GAMS $(gi[something(k, length(gi)):min(end, something(k, 0) + 2)]), reader $(mi[min(end, something(k, length(mi))):min(end, something(k, 0) + 2)])"
    else
        tr = "to maindrv.mod"
    end
    # the symbols declared
    miss = sort([i.name for (k, i) in d.symbols if !haskey(g.syms, k)])
    written = full ? gdx_symbols(g) : collect(values(g.syms))
    extra = sort([s.name for s in written if !haskey(d.symbols, uppercase(s.name))])
    full && !isempty(miss) && push!(notes, "declared by GAMS only: $(length(miss)) $(first(miss, 8))")
    !isempty(extra) && push!(notes, "declared by the reader only: $(join(extra, ", "))")
    # every set and parameter
    same = 0; n = 0
    for s in values(g.syms)
        s.kind in (:set, :parameter, :scalar) || continue
        info = get(d.symbols, uppercase(s.name), nothing)
        info === nothing && continue
        n += 1
        ks, vs = grecords(g, s)
        r = read_symbol(d, s.name)
        theirs = [collect(k) for k in r.keys]
        if ks != theirs
            a, b = Set(ks), Set(theirs)
            push!(notes, a == b ? "$(s.name): record order" :
                "$(s.name): reader only $(length(setdiff(a, b))) $(first(collect(setdiff(a, b)), 2)); GAMS only $(length(setdiff(b, a))) $(first(collect(setdiff(b, a)), 2))")
            continue
        end
        if s.kind === :set
            vs == r.text || (push!(notes, "$(s.name): element text"); continue)
        else
            v, sp = r.values["value"], r.special["value"]
            bad = findfirst(i -> (vs[i][2] === :eps) != (sp[i] == SV_EPS) || (vs[i][2] !== :eps && !isequal(vs[i][1], v[i]) && abs(vs[i][1] - v[i]) > 1e-9 * max(1, abs(v[i]))), eachindex(vs))
            bad === nothing || (push!(notes, "$(s.name): value of $(ks[bad]) $(vs[bad]) vs $(v[bad])"); continue)
        end
        same += 1
    end
    u = gdx_uels(g)
    lab = full ? (u == d.uels ? "all $(length(u)) in the dump's order" : "differ ($(length(u)) vs $(length(d.uels)); same order where shared: $(u == filter(in(Set(d.uels)), u) && filter(in(Set(u)), d.uels) == filter(in(Set(d.uels)), u)))") :
                 (u == filter(in(Set(u)), d.uels) ? "$(length(u)) in the dump's order" : "order differs")
    println("== $model/$variant: compiled in $(round(t, digits=1)) s, $(g.warnings) warnings · files: $tr · ",
        "sets and parameters identical: $same of $n · labels: $lab")
    foreach(x -> println("     ", x), first(sort(notes), 25))
    length(notes) > 25 && println("     ... $(length(notes) - 25) more")
end

function main(args)
    ref = args[1]
    i = findfirst(==("--sources"), args)
    sources = args[i+1]
    full = !("--pre" in args)
    models = [a for (j, a) in enumerate(args) if j > 1 && j != i && j != i + 1 && a != "--pre"]
    for m in models
        (startswith(m, "TIM-") || startswith(m, "JRC")) && error("open models only (CLAUDE.md): $m")
        haskey(MODEL_DIRS, m) || error("unknown model $m")
        for v in ("reduce_off", "as_run")
            probe(ref, sources, m, v; full)
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
