# M1.4: compile a model's run file with src/dd/compile.jl (no GAMS) and compare the result with the
# harness's input dump: every symbol the compile declares, its records (keys, order, values, EPS,
# set text), and the dump's label order.
#
#   julia --project=test scripts/m14_probe.jl <reference dir> --sources <timesjl-sources> <model> ...
#
# <model> is a reference folder name, e.g. TIMES_Demo-demo12; both variants are compiled. Only open
# models (CLAUDE.md); TIM and JRC-EU-TIMES are refused.
using TIMES, JSON
using TIMES: GamsCompile, gams_compile!, grecords, gdx_uels
using TIMES.Reference: load_dump, read_symbol, SV_EPS

const MODEL_DIRS = Dict(
    "TIMES_Demo-demo12" => "TIMES_Demo/model",
    "TIMES-NZ-steady-v308" => "TIMES-NZ/dd/steady-v308", "TIMES-NZ-shift-v308" => "TIMES-NZ/dd/shift-v308",
    "OTCGEN-gc_ref" => "OTCGEN/dd/gc_ref", "OTNYC-s1_nyc_ref" => "OTNYC/dd/s1_nyc_ref",
    "OTUS9r-reference" => "OTUS9r/dd/reference", "OTUS9r-tax1_wo_mou" => "OTUS9r/dd/tax1_wo_mou")

function probe(ref, sources, model, variant)
    dir = joinpath(ref, model, variant)
    run = joinpath(dir, "raw", "tjl_presolve.run")
    isfile(run) && isdir(joinpath(dir, "input")) || return println("== $model/$variant: no input dump, skipped")
    g = GamsCompile(dirs=[joinpath(sources, "TIMES_model"), joinpath(sources, MODEL_DIRS[model])])
    g.globals["RUN_NAME"] = model          # the harness's --run_name
    t = @elapsed try
        gams_compile!(g, run)
    catch e
        return println("== $model/$variant: compile stops: ", sprint(showerror, e))
    end
    d = load_dump(joinpath(dir, "input"))
    same = 0; diffs = String[]; later = 0
    for s in values(g.syms)
        s.kind in (:set, :parameter, :scalar) || continue
        info = get(d.symbols, uppercase(s.name), nothing)
        info === nothing && (push!(diffs, "$(s.name): not in the dump"); continue)
        ks, vs = grecords(g, s)
        r = read_symbol(d, s.name)
        theirs = [collect(k) for k in r.keys]
        if ks != theirs
            a, b = Set(ks), Set(theirs)
            push!(diffs, a == b ? "$(s.name): record order" :
                "$(s.name): reader only $(length(setdiff(a, b))) $(first(collect(setdiff(a, b)), 2)); GAMS only $(length(setdiff(b, a))) $(first(collect(setdiff(b, a)), 2))")
            continue
        end
        if s.kind === :set
            vs == r.text || (push!(diffs, "$(s.name): element text"); continue)
        else
            v, sp = r.values["value"], r.special["value"]
            bad = findfirst(i -> (vs[i][2] === :eps) != (sp[i] == SV_EPS) || (vs[i][2] !== :eps && !isequal(vs[i][1], v[i]) && abs(vs[i][1] - v[i]) > 1e-9 * max(1, abs(v[i]))), eachindex(vs))
            bad === nothing || (push!(diffs, "$(s.name): value of $(ks[bad]) $(vs[bad]) vs $(v[bad])"); continue)
        end
        same += 1
    end
    ndecl = count(s -> s.kind in (:set, :parameter, :scalar), values(g.syms))
    rest = [n for (k, n) in ((k, i.name) for (k, i) in d.symbols) if !haskey(g.syms, k) && d.symbols[k].kind in (:set, :parameter) && d.symbols[k].records > 0]
    u = gdx_uels(g)
    du = filter(in(Set(u)), d.uels)
    println("== $model/$variant: compiled in $(round(t, digits=1)) s, $(g.warnings) warnings · $same of $ndecl symbols identical",
        " · labels in dump order: $(u == du) ($(length(u)) of $(length(d.uels)))",
        " · declared later in TIMES code, with records: $(length(rest))")
    foreach(x -> println("     ", x), first(sort(diffs), 25))
    length(diffs) > 25 && println("     ... $(length(diffs) - 25) more")
end

function main(args)
    ref = args[1]
    i = findfirst(==("--sources"), args)
    sources = args[i+1]
    models = [a for (j, a) in enumerate(args) if j > 1 && j != i && j != i + 1]
    for m in models
        startswith(m, "TIM-") || startswith(m, "JRC") && error("open models only (CLAUDE.md): $m")
        haskey(MODEL_DIRS, m) || error("unknown model $m")
        for v in ("reduce_off", "as_run")
            probe(ref, sources, m, v)
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
