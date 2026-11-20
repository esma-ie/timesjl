# M1.3 inventory: which sets and parameters each preprocessing segment creates
# or changes, from the checkpoint dumps of one reference run (harness 0.3.0:
# input/, init/, prep/, prelv/ from the pre-solve run, then ppm/).
#
#   julia --project=test scripts/m13_inventory.jl <reference dir> <model> [<variant>] [--json out.json]
#
# Segments (TIMES v4.9.7):
#   input -> init   maindrv.mod L55: the extensions' init_ext (init_ext.dsc, init_ext.vda)
#   init  -> prep   ppmain.mod L1-248 and preppm.mod L1-217 (with prep_ext.vda)
#   prep  -> prelv  preppm.mod L218-253 and ppmain.mod L249-615 (with pp_prelv.vda)
#   prelv -> ppm    ppmain.mod L616-1357 and the extensions' ppm_ext (maindrv.mod L58)
#
# A symbol counts as changed in a segment when its records differ between the
# two dumps at 1e-9 (record order ignored), or it appears or disappears. The
# output names symbols and counts only, so it can be run on any model; for a
# model that is not redistribute = "public" (reference/suite.toml) keep it on
# the machine that holds the reference.

using OpenTIMES
using OpenTIMES.Reference: load_dump, compare_dumps, n_mismatches
import JSON

const SEGMENTS = [("input", "init"), ("init", "prep"), ("prep", "prelv"), ("prelv", "ppm")]

function inventory(dir)
    have = filter(c -> isdir(joinpath(dir, c)), ["input", "init", "prep", "prelv", "ppm"])
    length(have) == 5 || error("$dir: checkpoint dumps missing ($(join(setdiff(["input", "init", "prep", "prelv", "ppm"], have), ", "))); " *
                               "make them with make_reference.py --only presolve (harness 0.3.0)")
    dumps = Dict(c => load_dump(joinpath(dir, c)) for c in have)
    out = Dict{String,Any}()
    for (a, b) in SEGMENTS
        r = compare_dumps(dumps[a], dumps[b]; kinds=(:set, :parameter), check_order=false, max_examples=0)
        rows = Any[]
        for c in r.symbols
            n_mismatches(c) == 0 && continue
            push!(rows, Dict("symbol" => c.name, "kind" => String(c.kind), "before" => c.n_left, "after" => c.n_right,
                             "changed" => n_mismatches(c)))
        end
        for n in r.only_right
            info = dumps[b].symbols[uppercase(n)]
            push!(rows, Dict("symbol" => n, "kind" => String(info.kind), "before" => nothing, "after" => info.records,
                             "changed" => info.records))
        end
        for n in r.only_left
            info = dumps[a].symbols[uppercase(n)]
            push!(rows, Dict("symbol" => n, "kind" => String(info.kind), "before" => info.records, "after" => nothing,
                             "changed" => info.records))
        end
        sort!(rows; by=x -> x["symbol"])
        out["$a->$b"] = rows
    end
    return out
end

function print_inventory(io, inv)
    for (a, b) in SEGMENTS
        rows = inv["$a->$b"]
        println(io, "\n## $a -> $b: ", length(rows), " symbols\n")
        println(io, "| Symbol | Kind | Records before | Records after | Records changed |")
        println(io, "| --- | --- | ---: | ---: | ---: |")
        for x in rows
            f(v) = v === nothing ? "—" : string(v)
            println(io, "| ", x["symbol"], " | ", x["kind"], " | ", f(x["before"]), " | ", f(x["after"]), " | ", x["changed"], " |")
        end
    end
end

function main(args)
    i = findfirst(==("--json"), args)
    jsonout = i === nothing ? nothing : args[i+1]
    rest = i === nothing ? args : vcat(args[1:i-1], args[i+2:end])
    refdir, model = rest[1], rest[2]
    variant = length(rest) >= 3 ? rest[3] : "reduce_off"
    inv = inventory(joinpath(refdir, model, variant))
    println("# M1.3 inventory: ", model, " / ", variant)
    print_inventory(stdout, inv)
    jsonout === nothing || write(jsonout, JSON.json(Dict("model" => model, "variant" => variant, "segments" => inv), 1))
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
