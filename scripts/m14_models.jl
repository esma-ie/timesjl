# The models the M1.4 scripts compile from their DD files: each model's include directories (`idirs`)
# from reference/suite.toml or reference/crafted.toml, with every {root} a folder of timesjl-sources
# (the same folders scripts/run_references.ps1 clones or checks), {crafted} reference/dd, and the
# harness's .tjlref files (reference/gams), which its patched run files include.
#
# A model whose `redistribute` is not "public" (TIM, JRC-EU-TIMES) runs only with `--local`
# (LOCAL_OK[] = true): on James's workstation, its logs kept there (CLAUDE.md, docs/test-models.md).
using TOML

const REFGAMS = joinpath(@__DIR__, "..", "reference", "gams")
const SUITE_FILES = [joinpath(@__DIR__, "..", "reference", "suite.toml"), joinpath(@__DIR__, "..", "reference", "crafted.toml")]
# {root} -> folder of timesjl-sources (scripts/run_references.ps1, $Sources and $LocalSources)
const SOURCE_DIRS = Dict("times_source" => "TIMES_model", "times_demo" => "TIMES_Demo", "times_nz_dd" => "TIMES-NZ",
                         "otus" => "OTUS9r", "otcgen" => "OTCGEN", "otnyc" => "OTNYC", "tim" => "TIM",
                         "jrc_eu_times" => "JRC-EU-TIMES")
const LOCAL_OK = Ref(false)

"The suite entry of `model` (a reference folder name), from suite.toml or crafted.toml."
function suite_model(model)
    for f in SUITE_FILES, e in get(TOML.parsefile(f), "model", [])
        e["name"] == model && return e
    end
    error("$model is in neither reference/suite.toml nor reference/crafted.toml")
end

function resolve_root(path, sources)
    m = match(r"^\{(\w+)\}(.*)$", path)
    m === nothing && return path
    root = m[1]
    base = root == "crafted" ? joinpath(@__DIR__, "..", "reference", "dd") :
           haskey(SOURCE_DIRS, root) ? joinpath(sources, SOURCE_DIRS[root]) : error("unknown root {$root}")
    return normpath(base * m[2])
end

"""
    dd_model_dirs(sources, model) -> Vector{String}

The folders the compile searches for `model`'s DD files, in the suite's order. Refuses a model that
is not openly redistributable unless `--local` was given (LOCAL_OK[]).
"""
function dd_model_dirs(sources, model)
    e = suite_model(model)
    red = get(e, "redistribute", "")
    red == "public" || LOCAL_OK[] ||
        error("$model has redistribute = \"$red\": it runs on James's workstation only, with --local (CLAUDE.md)")
    return [resolve_root(d, sources) for d in get(e, "idirs", String[])]
end

"Remove `--local` from `args` and set LOCAL_OK[]."
function take_local!(args)
    LOCAL_OK[] = "--local" in args
    filter!(!=("--local"), args)
end
