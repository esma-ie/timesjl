# coef_obj.mod L31-32, the control switch ANNCOST LEV (M1.3 change 29, 14 Nov 2026), on the crafted
# cases demo12_lev (OBJ MOD: %CTST% is '**0', MINYR stays MIYR_V1) and demo12_levstd (OBJ AUTO:
# %CTST% is empty, L32 restores MINYR). From GAMS's ppm dump through the coefficient stage and the
# coef -> pre-solve step, with TIMES.jl's own state; every set and parameter against the pre-solve
# dump (1e-9), then the model from that state against GAMS's matrix (layer 2).

using TIMES: TimesModel, DumpData, layer1, coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!,
             prepret_decl!, eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!, bnd_data!, pp_qack_data!,
             pp_clean!, generate!, gset, gparam, gv, gscalar
using TIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, compare_lp
import TOML

# (prefix, MINYR after coef_obj.mod, first year of Y_EOH, members of Y_EOH)
@testset "$p" for (p, minyr, first, n) in (("demo12_lev", 2005.0, "2005", 48), ("demo12_levstd", 2004.0, "2004", 49))
    vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"] if v["prefix"] == p)
    @test vx["switches"]["ANNCOST"] == "LEV"
    tm = TimesModel(joinpath(FIXTURES, p * "_ppm"); reduce=vx["reduce"], switches=vx["switches"])
    names = sort([i.name for i in values(tm.data.dump.symbols) if i.kind in (:set, :parameter)])
    @test gscalar(tm, "MINYR") == 2004 && gscalar(tm, "MIYR_V1") == 2005     # before coef_obj.mod
    coef_cpt!(tm); coef_nio!(tm); coef_ptr!(tm); coef_obj!(tm)
    @testset "coef_obj.mod L31-33" begin
        @test gscalar(tm, "ACL") == 2004                                      # L31: ACL = MINYR
        @test gscalar(tm, "MINYR") == minyr                                   # L31, and L32 with %CTST% empty
        @test gv(gparam(tm, "RPT_OPT"), ("OBJ", "2")).v == 1                  # L31
        @test length(gparam(tm, "RPT_OPT").keys) == 1
        y_eoh = [k[1] for k in gset(tm, "Y_EOH").keys]                        # L33, from the new MINYR
        @test length(y_eoh) == n && minimum(y_eoh) == first
    end
    coef_alt!(tm); coef_shp!(tm); coef_ext!(tm)
    foreach(f -> f(tm), (prepret_decl!, eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!, bnd_data!,
                         pp_qack_data!, pp_clean!))
    @testset "ppm -> pre-solve, every set and parameter" begin
        ref = DumpData(joinpath(FIXTURES, p * "_presolve"))
        @test haskey(ref.dump.symbols, "RPT_OPT")
        r = layer1(tm, ref, filter(n -> haskey(ref.dump.symbols, n) && n != "TJL_SOLVEINFO", union(names, ["RPT_OPT"])))
        foreach(d -> ispass(d) || println(p, " ppm -> presolve: ", d, " ", d.examples), r)
        @test length(r) > 800 && all(ispass, r)
    end
    @testset "the model from that state (layer 2)" begin
        generate!(tm)
        cmp = compare_lp(canonical_from_jump(tm.model),
                         canonical_from_dump(joinpath(FIXTURES, p * "_matrix", "matrix"),
                                             joinpath(FIXTURES, p * "_matrix", "dictmap")))
        ispass(cmp) || foreach(println, cmp.examples)
        @test ispass(cmp)
    end
end
