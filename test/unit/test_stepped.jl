# The preparation of a stepped (myopic) run before solve.stp (M1.3 change 30, 14 Nov 2026), on the
# crafted case demo12_step (demo12 with the control switch TIMESTEP 20; OBJ MOD, so %CTST% is '**0'):
# - coef_alt.lin L81 (`$IF SET TIMESTEP $GOTO DONE`): no RTP_CAPVL (L83-86 are skipped);
# - eqobsalv.mod L23-25: OBJ_SUMS, OBJ_SUMS3, SALV_INV and OBJSCC are cleared and the salvage
#   preparation (L26-82) is skipped: it runs inside each step (solve.stp L127).
# From GAMS's ppm dump with TIMES.jl's own state through the coefficient stage and the equation
# preparation (mod_vars.mod, eqmain.mod, equ_ext.vda); every set and parameter against the equ
# checkpoint (harness 0.3.3: after eqmain.mod and the extensions' equ_ext, maindrv.mod L79-80) at
# 1e-9. A stepped run's pre-solve dump is no reference for this state: with SOLVE_NOW=NO the run
# still goes through the loop of solve.stp, every step without a solve, so that dump holds the
# state after the last step. The stepped solve itself (solve.stp, the %R_T% restriction of
# maindrv.mod L40) is M1.5: model generation refuses the run.

using TIMES: TimesModel, DumpData, layer1, coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!,
             prepret_decl!, eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!, bnd_data!, pp_qack_data!,
             pp_clean!, generate!, untranslated_families, stepped, gset, gparam, UnportedError
using TIMES.Reference: ispass
import TOML

@testset "demo12_step: TIMESTEP 20" begin
    p = "demo12_step"
    vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"] if v["prefix"] == p)
    @test vx["switches"]["TIMESTEP"] == "20"
    tm = TimesModel(joinpath(FIXTURES, p * "_ppm"); reduce=vx["reduce"], switches=vx["switches"])
    @test stepped(tm)
    @test !stepped(TimesModel(joinpath(FIXTURES, p * "_ppm"); switches=Dict("OBJ" => "MOD")))
    ppm_names = Set(i.name for i in values(tm.data.dump.symbols))
    coef_cpt!(tm); coef_nio!(tm); coef_ptr!(tm); coef_obj!(tm); coef_alt!(tm)
    @testset "coef_alt.lin L80-86" begin
        @test !isempty(gparam(tm, "COEF_CPT"))                       # L65-79 run (%CTST% is '**0')
        @test isempty(gparam(tm, "RTP_CAPVL"))                       # L81: L83-86 are skipped
        @test isempty(gset(tm, "YK1"))                               # L160
    end
    coef_shp!(tm); coef_ext!(tm)
    foreach(f -> f(tm), (prepret_decl!, eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!))
    @testset "eqobsalv.mod L23-25" begin
        @test all(isempty(gset(tm, n)) for n in ("OBJ_SUMS", "OBJ_SUMS3", "OBJ_SALI"))
        @test all(isempty(gparam(tm, n)) for n in ("SALV_INV", "OBJSCC", "OBJ_DCEOH", "SALV_DEC"))
    end
    @testset "ppm -> equ, every set and parameter" begin
        ref = DumpData(joinpath(FIXTURES, p * "_equ"))
        @test all(haskey(ref.dump.symbols, n) for n in ("OBJ_SUMS", "OBJ_SUMS3", "SALV_INV", "OBJSCC", "COEF_CPT"))
        # every symbol of the ppm dump, and every one TIMES.jl wrote since (GAMS declares it after ppm)
        names = sort([i.name for i in values(ref.dump.symbols) if i.kind in (:set, :parameter) && i.name != "TJL_SOLVEINFO" &&
                      (i.name in ppm_names || haskey(tm.data.sets, i.name) || haskey(tm.data.params, i.name))])
        r = layer1(tm, ref, names)
        foreach(d -> ispass(d) || println(p, " ppm -> equ: ", d, " ", d.examples), r)
        @test length(r) > 800 && all(ispass, r)        # 833, as the chain compares at equ
    end
    @testset "the stepped solve is refused (M1.5)" begin
        foreach(f -> f(tm), (bnd_data!, pp_qack_data!, pp_clean!))          # maindrv.mod L92-113 before solve.stp
        @test unique(x.family for x in untranslated_families(tm)) == ["(stepped run)"]
        @test_throws UnportedError generate!(tm)
    end
end
