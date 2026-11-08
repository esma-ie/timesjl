using Test
using TIMES

const FIXTURES = joinpath(@__DIR__, "fixtures")

# Only openly licensed test models (CLAUDE.md "Test-model licences",
# docs/test-models.md). The per-family tests on the DemoS models were removed
# on 27 Oct 2026; whole-model parity now runs in test_public_parity.jl on the
# fixtures listed in test/fixtures/public_fixtures.toml.
@testset "TIMES.jl" begin
    @test TIMES.TIMES_GAMS_VERSION == v"4.9.7"
    @test TIMES.TIMES_GAMS_COMMIT == "d9a6a25"
    @testset "Reference: dump reader" begin
        include("unit/test_dump.jl")
    end
    @testset "Reference: layer 1 comparison" begin
        include("unit/test_compare.jl")
    end
    @testset "Reference: layer 2-3 canonical LP" begin
        include("unit/test_lp.jl")
    end
    @testset "Model: mod_vars (M1.1)" begin
        include("unit/test_mod_vars.jl")
    end
    @testset "Model: GAMS EPS arithmetic" begin
        include("unit/test_gnum.jl")
    end
    @testset "Model: run switches (OBJ, OBLONG, CTST)" begin
        include("unit/test_switches.jl")
    end
    @testset "Coefficients: GAMS assignment semantics (M1.2)" begin
        include("unit/test_coef_state.jl")
    end
    @testset "Parity on openly licensed models (layers 1-3)" begin
        include("unit/test_public_parity.jl")
    end
    @testset "Coefficients: coef_ptr.mod (M1.2)" begin
        include("unit/test_coef_ptr.jl")
    end
    @testset "Coefficients: coef_obj.mod (M1.2)" begin
        include("unit/test_coef_obj.jl")
    end
    @testset "Coefficients: coef_alt.lin (M1.2)" begin
        include("unit/test_coef_alt.jl")
    end
    @testset "Coefficients: coef_shp.mod (M1.2)" begin
        include("unit/test_coef_shp.jl")
    end
    @testset "Coefficients: coef_ext.vda (M1.2)" begin
        include("unit/test_coef_ext.jl")
    end
    @testset "Preprocessing: checkpoint fixtures (M1.3)" begin
        include("unit/test_m13_checkpoints.jl")
    end
    @testset "Preprocessing: init_ext (M1.3)" begin
        include("unit/test_m13_init_ext.jl")
    end
    @testset "Preprocessing: ppmain.mod L1-137 (M1.3)" begin
        include("unit/test_m13_ppmain_head.jl")
    end
    @testset "Preprocessing: ppmain.mod L138-191 (M1.3)" begin
        include("unit/test_m13_ppmain_years.jl")
    end
    @testset "Preprocessing: timslice.mod with pp_off.mod (M1.3)" begin
        include("unit/test_m13_timslice.jl")
    end
    @testset "Preprocessing: ppmain.mod L199-247, RTP_OFF and RTP (M1.3)" begin
        include("unit/test_m13_ppmain_rtp.jl")
    end
    @testset "Preprocessing: preppm.mod L1-212, the interpolation (M1.3)" begin
        include("unit/test_m13_preppm.jl")
    end
    @testset "Preprocessing: preppm.mod L213-217, prep_ext.vda (M1.3)" begin
        include("unit/test_m13_prep_ext.jl")
    end
    @testset "Preprocessing: preppm.mod L218-252, ppmain.mod L249-328 (M1.3)" begin
        include("unit/test_m13_ppmain_topo.jl")
    end
    @testset "Preprocessing: ppmain.mod L329-460, the timeslice levels (M1.3)" begin
        include("unit/test_m13_ppmain_tslvl.jl")
    end
    @testset "Preprocessing: ppmain.mod L461-611, lifetimes and availability (M1.3)" begin
        include("unit/test_m13_ppmain_life.jl")
    end
    @testset "Preprocessing: ppmain.mod L615, pp_prelv.vda (M1.3)" begin
        include("unit/test_m13_pp_prelv.jl")
    end
    @testset "Preprocessing: ppmain.mod L616-682, pp_qafs.mod (M1.3)" begin
        include("unit/test_m13_ppmain_dflt.jl")
    end
    @testset "Preprocessing: ppmain.mod L683-797, pp_lvlfc/br/pk.mod (M1.3)" begin
        include("unit/test_m13_ppmain_tsattr.jl")
    end
    @testset "Preprocessing: ppmain.mod L800-821, pp_chp.mod (M1.3)" begin
        include("unit/test_m13_ppmain_flo.jl")
    end
    @testset "Preprocessing: ppmain.mod L823-843, pp_lvlff/fs.mod, eqflomrk.mod (M1.3)" begin
        include("unit/test_m13_ppmain_flofs.jl")
    end
    @testset "Preprocessing: ppmain.mod L846-933, pp_lvlif.mod (M1.3)" begin
        include("unit/test_m13_ppmain_ire.jl")
    end
    @testset "Preprocessing: ppmain.mod L936-1001, pp_lvlbd.mod (M1.3)" begin
        include("unit/test_m13_ppmain_bnd.jl")
    end
    @testset "Preprocessing: ppmain.mod L1003-1056, cumulative bounds and RHS (M1.3)" begin
        include("unit/test_m13_ppmain_cum.jl")
    end
    @testset "Preprocessing: ppmain.mod L1058-1099, storage (M1.3)" begin
        include("unit/test_m13_ppmain_stg.jl")
    end
    @testset "Preprocessing: ppmain.mod L1101-1179, user constraints (M1.3)" begin
        include("unit/test_m13_ppmain_uc.jl")
    end
    @testset "Preprocessing: ppmain.mod L1181-1226, UC maps and pp_lvlus (M1.3)" begin
        include("unit/test_m13_ppmain_ucmap.jl")
    end
    @testset "Preprocessing: ppmain.mod L1228-1333, blending (M1.3)" begin
        include("unit/test_m13_ppmain_blend.jl")
    end
    @testset "Preprocessing: ppmain.mod L1336-1357, pp_reduce.red (M1.3)" begin
        include("unit/test_m13_ppmain_reduce.jl")
    end
    @testset "Preprocessing: ppm_ext.vda L11-58, pp_actef.vda (M1.3)" begin
        include("unit/test_m13_ppm_ext.jl")
    end
    @testset "Preprocessing: ppm_ext.vda L59-169, the prelv -> ppm segment (M1.3)" begin
        include("unit/test_m13_ppm_ext_end.jl")
    end
    @testset "User constraints: the dynamic RHS direction, equserco.mod L80-106 (M1.3)" begin
        include("unit/test_equserco_dyn.jl")
    end
    @testset "User constraints: the attribute factors of uc_*.mod (M1.3)" begin
        include("unit/test_equserco_attr.jl")
    end
    @testset "demo12 variants: advanced features (docs/demo12-variants.md)" begin
        include("unit/test_variants.jl")
    end
    @testset "M1.3 gate: the chain from the input dump through the coefficients" begin
        include("unit/test_m13_chain.jl")
    end
end
