# demo12 variants for advanced TIMES features (docs/demo12-variants.md): for each
# variant in test/fixtures/variant_fixtures.toml,
# - preprocessing (M1.3) from the input dump to the ppm dump, TIMES.jl's own state
#   throughout, compared with GAMS at 1e-9 on every set and parameter that is in the
#   input dump or that TIMES.jl wrote (the constant tables GAMS declares after the
#   input checkpoint, e.g. ADESC and SYSUC, TIMES.jl never computes);
# - model generation refuses exactly the equation families the variant lists, so a
#   feature not yet translated can never give a model without its rows.

using TIMES: TimesModel, DumpData, layer1, untranslated_families, generate!, UnportedError,
             init_ext!, ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, prep_ext!, preppm_shape!,
             ppmain_topo!, ppmain_tslvl!, ppmain_life!, pp_prelv!, pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!,
             ppmain_flofs!, ppmain_ire!, ppmain_bnd!, ppmain_cum!, ppmain_stg!, ppmain_uc!, ppmain_ucmap!, ppmain_blend!,
             ppmain_reduce!, ppm_ext_actef!, ppm_ext!
using TIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, family
import TOML
isdefined(@__MODULE__, :check_family_parity) || include("parity_helpers.jl")

"Every preprocessing step, maindrv.mod L55-58 order (test_m13_chain.jl, M13_CHAIN)."
const VARIANT_STEPS = (init_ext!, ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, prep_ext!, preppm_shape!,
                       ppmain_topo!, ppmain_tslvl!, ppmain_life!, pp_prelv!, pp_qafs!, ppmain_dflt!, ppmain_tsattr!,
                       ppmain_flo!, ppmain_flofs!, ppmain_ire!, ppmain_bnd!, ppmain_cum!, ppmain_stg!, ppmain_uc!,
                       ppmain_ucmap!, ppmain_blend!, ppmain_reduce!, ppm_ext_actef!, ppm_ext!)

const VARIANTS = get(TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml")), "variant", Any[])
const CASES = Dict(m["name"] => m for f in ("suite.toml", "crafted.toml")
                   for m in TOML.parsefile(joinpath(@__DIR__, "..", "..", "reference", f))["model"])

for vx in VARIANTS
    @testset "$(vx["model"]) $(vx["variant"])" begin
        @test get(get(CASES, vx["model"], Dict()), "redistribute", "") == "public"
        fx(part) = joinpath(FIXTURES, vx["prefix"] * "_" * part)
        @testset "preprocessing, input -> ppm" begin
            tm = TimesModel(fx("input"); switches=vx["switches"])
            input_names = Set(i.name for i in values(tm.data.dump.symbols))
            foreach(f -> f(tm), VARIANT_STEPS)
            ref = DumpData(fx("ppm"))
            names = sort([i.name for i in values(ref.dump.symbols) if i.kind in (:set, :parameter) &&
                          (i.name in input_names || haskey(tm.data.sets, i.name) || haskey(tm.data.params, i.name))])
            r = layer1(tm, ref, names)
            foreach(d -> ispass(d) || println("$(vx["prefix"]) input -> ppm: ", d, " ", d.examples), r)
            @test length(r) > 800 && all(ispass, r)        # 821 on demo12_uc, as the M1.3 gate compares
        end
        @testset "refuses exactly the untranslated families" begin
            tm = TimesModel(fx("presolve"); reduce=get(vx, "reduce", false), switches=vx["switches"])
            fams = unique(x.family for x in untranslated_families(tm))
            @test Set(fams) == Set(vx["untranslated"])
            isempty(vx["untranslated"]) || @test_throws UnportedError generate!(tm)
        end
        # Families translated while the model is still refused (a change in parts, such as
        # 20b): their rows alone against the CONVERT export (layer 2, 1e-9).
        if haskey(vx, "partial")
            @testset "rows of $(join(vx["partial"]["families"], ", "))" begin
                tm = TimesModel(fx("presolve"); reduce=get(vx, "reduce", false), switches=vx["switches"])
                foreach(g -> getfield(TIMES, Symbol(g))(tm), vx["partial"]["generators"])
                mine = canonical_from_jump(tm.model)
                ref = canonical_from_dump(joinpath(fx("matrix"), "matrix"), joinpath(fx("matrix"), "dictmap"))
                for fam in vx["partial"]["families"]
                    @test check_family_parity(mine, ref, fam) > 0
                end
                # Column bounds of the listed variable families (bndmain.jl with ret_bounds!).
                if haskey(vx["partial"], "bounds")
                    TIMES.apply_bounds!(tm)
                    mine = canonical_from_jump(tm.model)
                    for vf in vx["partial"]["bounds"]
                        ka = sort([k for k in keys(mine.cols) if family(k) == vf])
                        kb = sort([k for k in keys(ref.cols) if family(k) == vf])
                        @test !isempty(kb) && ka == kb
                        for k in intersect(ka, kb)
                            @test _same_bound(mine.cols[k].lb, ref.cols[k].lb; rtol=1e-9)
                            @test _same_bound(mine.cols[k].ub, ref.cols[k].ub; rtol=1e-9)
                        end
                    end
                end
            end
        end
    end
end
