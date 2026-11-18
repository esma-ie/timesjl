# M1.3 layer 1: the translated preprocessing steps on the checkpoint dumps of
# reference runs (harness 0.3.0; docs/m13-plan.md).
#
#   julia --project=test scripts/m13_probe.jl <reference dir> [--root name=path ...] [<model> ...]
#
# Each segment starts from GAMS's own state at its first checkpoint and is
# checked at the next one, so a segment can be translated and checked on its
# own (the whole chain is tested at the M1.3 gate):
#
#   input -> init   maindrv.mod L55 (init_ext.dsc, init_ext.vda)
#   init  -> prep   ppmain.mod L1-248, preppm.mod L1-217 (with prep_ext.vda)
#   prep  -> prelv  preppm.mod L218-253, ppmain.mod L249-615 (with pp_prelv.vda)
#   prelv -> ppm    ppmain.mod L616-1357, maindrv.mod L58 (ppm_ext.dsc, ppm_ext.vda)
#   coef -> presolve  maindrv.mod L76-98: mod_vars.mod, eqmain.mod (with the
#                   eqobj*.mod preparation), equ_ext, bndmain.mod, pp_qack.mod
#                   (M1.3 change 25, in parts; the coef dump comes after the
#                   M1.2 coefficient stage)
#
# A step is compared on the symbols it settles that nothing later in its
# segment changes (`symbols`, plus `extra(tm)` for those that depend on the
# model's switches or data). A step that ends its segment is compared on
# every set and parameter of the dump (`all_symbols`), so a side effect on a
# symbol it should leave alone shows too. Both variants (reduce_off, as_run)
# are probed.

include(joinpath(@__DIR__, "m11_probe.jl"))      # run_switches, runfile_of, suite_switches, parse_probe_args
using TIMES: DumpData, layer1, init_ext!, ppmain_head!, ppmain_head_symbols, ppmain_years!, ppmain_years_symbols,
             timslice!, timslice_symbols, ppmain_rtp!, ppmain_rtp_symbols, preppm!, preppm_symbols,
             prep_ext!, prep_ext_symbols, preppm_shape!, preppm_shape_symbols, ppmain_topo!, ppmain_topo_symbols,
             ppmain_tslvl!, ppmain_tslvl_symbols, ppmain_life!, ppmain_life_symbols,
             pp_prelv!, pp_prelv_symbols, pp_qafs!, pp_qafs_symbols, ppmain_dflt!, ppmain_dflt_symbols,
             ppmain_tsattr!, ppmain_tsattr_symbols, ppmain_flo!, ppmain_flo_symbols,
             ppmain_flofs!, ppmain_flofs_symbols, ppmain_ire!, ppmain_ire_symbols,
             ppmain_bnd!, ppmain_bnd_symbols, ppmain_cum!, ppmain_cum_symbols,
             ppmain_stg!, ppmain_stg_symbols, ppmain_uc!, ppmain_uc_symbols,
             ppmain_ucmap!, ppmain_ucmap_symbols, ppmain_blend!, ppmain_blend_symbols,
             ppmain_reduce!, ppmain_reduce_symbols, ppm_ext_actef!, ppm_ext_actef_symbols, ppm_ext!, ppm_ext_symbols,
             prepret_decl!, prepret_decl_symbols, eqobjinv_prep!, eqobjinv_prep_symbols,
             eqobjfix_prep!, eqobjfix_prep_symbols, eqobsalv_prep!, eqobsalv_prep_symbols,
             eqmain_prep!, eqmain_prep_symbols, bnd_data!, pp_qack_data!, pp_clean!, qack_prep_symbols
using TIMES.Reference: ispass

"The segments: (first checkpoint, next checkpoint)."
const M13_SEGMENTS = [("input", "init"), ("init", "prep"), ("prep", "prelv"), ("prelv", "ppm"), ("coef", "presolve")]

"Every set and parameter of the dump `tm` started from."
all_symbols(tm) = sort([i.name for i in values(tm.data.dump.symbols) if i.kind in (:set, :parameter) && i.name != "TJL_SOLVEINFO"])

"""
What each step is compared on (`symbols(tm)`: the symbols it settles that nothing later in its segment
changes; `all_symbols` for a step that ends its segment). The steps themselves and their order are
`TIMES.PRESOLVE_STEPS` (src/run.jl), the list `run_model` runs; a step with no entry here stops this
script with a KeyError.
"""
const STEP_SYMBOLS = Dict{String,Function}(
    "init_ext" => all_symbols,
    "ppmain_head" => ppmain_head_symbols,
    "ppmain_years" => ppmain_years_symbols,
    "timslice" => timslice_symbols,
    "ppmain_rtp" => ppmain_rtp_symbols,
    "preppm" => preppm_symbols,
    "prep_ext" => prep_ext_symbols,
    "preppm_shape" => preppm_shape_symbols,
    "ppmain_topo" => ppmain_topo_symbols,
    "ppmain_tslvl" => ppmain_tslvl_symbols,
    "ppmain_life" => ppmain_life_symbols,
    "pp_prelv" => pp_prelv_symbols,
    "pp_qafs" => pp_qafs_symbols,
    "ppmain_dflt" => ppmain_dflt_symbols,
    "ppmain_tsattr" => ppmain_tsattr_symbols,
    "ppmain_flo" => ppmain_flo_symbols,
    "ppmain_flofs" => ppmain_flofs_symbols,
    "ppmain_ire" => ppmain_ire_symbols,
    "ppmain_bnd" => ppmain_bnd_symbols,
    "ppmain_cum" => ppmain_cum_symbols,
    "ppmain_stg" => ppmain_stg_symbols,
    "ppmain_uc" => ppmain_uc_symbols,
    "ppmain_ucmap" => ppmain_ucmap_symbols,
    "ppmain_blend" => ppmain_blend_symbols,
    "ppmain_reduce" => ppmain_reduce_symbols,
    "ppm_ext_actef" => ppm_ext_actef_symbols,
    "ppm_ext" => ppm_ext_symbols,
    "prepret_decl" => prepret_decl_symbols,
    "eqobjinv_prep" => eqobjinv_prep_symbols,
    "eqobjfix_prep" => eqobjfix_prep_symbols,
    "eqobsalv_prep" => eqobsalv_prep_symbols,
    "eqmain_prep" => eqmain_prep_symbols,
    "bnd_data" => (tm -> String[]),
    "pp_qack_data" => (tm -> String[]),
    "pp_clean" => all_symbols,
)

"Translated steps in execution order: (segment start, name, function, symbols, symbols by model); the M1.2 coefficient stage (ppm -> coef) is left out."
const M13_STEPS = Tuple{String,String,Function,Vector{String},Function}[
    (a, n, f, String[], STEP_SYMBOLS[n]) for (a, n, f) in TIMES.PRESOLVE_STEPS if a != "ppm"]

function probe13(refdir, model; roots=Dict{String,String}(), variant="reduce_off", steps=M13_STEPS)
    dir = joinpath(refdir, model, variant)
    isfile(joinpath(dir, "manifest.json")) || return println("== ", model, ": no reference")
    m = JSON.parsefile(joinpath(dir, "manifest.json"))
    missing_cp = filter(c -> !isdir(joinpath(dir, c)), ["input", "init", "prep", "prelv", "ppm"])
    isempty(missing_cp) || return println("== ", model, ": no checkpoint dump ", join(missing_cp, ", "),
                                          " (make_reference.py --only presolve, harness 0.3.0)")
    rf = runfile_of(refdir, model, variant)
    sw = rf === nothing ? suite_switches(model, m, roots) : run_switches(rf)
    model = string(model, "/", variant)
    for (a, b) in M13_SEGMENTS
        seg = filter(s -> s[1] == a, steps)
        if isempty(seg)
            println("== ", model, " ", a, " -> ", b, ": nothing translated yet")
            continue
        end
        tm = TimesModel(joinpath(dir, a); switches=sw)
        TIMES.qa_warnings!(tm, TIMES.gams_warnings(joinpath(dir, "raw", "tjl_presolve.lst")))   # ppmain.mod L35
        ref = DumpData(joinpath(dir, b))
        for (_, name, f, syms, extra) in seg
            try
                t = @elapsed f(tm)
                # a symbol of the start dump the next dump lacks (declared in another run, e.g. ADESC under %POWERFLO%) is skipped
                r = layer1(tm, ref, filter(n -> haskey(ref.dump.symbols, uppercase(n)), vcat(syms, extra(tm))))
                bad = filter(!ispass, r)
                println("== ", model, " ", name, ": ", isempty(bad) ? "PASS" : "FAIL", " (", length(r), " symbols, ",
                        sum(d -> d.n_ref, r; init=0), " GAMS records at ", b, ", ", round(t; digits=2), " s)")
                for d in bad
                    println("     ", d)
                    foreach(e -> println("        ", e), d.examples)
                end
            catch e
                e isa TIMES.UnportedError || rethrow()
                println("== ", model, " ", name, ": not translated: ", sprint(showerror, e))
                break
            end
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    refdir, roots, models = parse_probe_args(ARGS)
    for model in models, variant in ("reduce_off", "as_run")
        probe13(refdir, model; roots, variant)
    end
end
