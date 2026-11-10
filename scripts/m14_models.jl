# The open suite models the M1.4 scripts compile from their DD files: the folder of each model's DD
# files under timesjl-sources (`--sources`), and the harness's .tjlref files (reference/gams), which
# its patched run files include. Only open models (CLAUDE.md); TIM and JRC-EU-TIMES are refused.
const REFGAMS = joinpath(@__DIR__, "..", "reference", "gams")
const MODEL_DIRS = Dict(
    "TIMES_Demo-demo12" => "TIMES_Demo/model",
    "TIMES-NZ-steady-v308" => "TIMES-NZ/dd/steady-v308", "TIMES-NZ-shift-v308" => "TIMES-NZ/dd/shift-v308",
    "OTCGEN-gc_ref" => "OTCGEN/dd/gc_ref", "OTNYC-s1_nyc_ref" => "OTNYC/dd/s1_nyc_ref",
    "OTUS9r-reference" => "OTUS9r/dd/reference", "OTUS9r-tax1_wo_mou" => "OTUS9r/dd/tax1_wo_mou")

function dd_model_dir(sources, model)
    (startswith(model, "TIM-") || startswith(model, "JRC")) && error("open models only (CLAUDE.md): $model")
    haskey(MODEL_DIRS, model) || error("no DD folder known for $model (scripts/m14_models.jl)")
    joinpath(sources, MODEL_DIRS[model])
end
