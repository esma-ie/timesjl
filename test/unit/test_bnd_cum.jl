# bnd_cum.mod L12-20 and L27-38: the statements that change FLO_CUM, COM_CUM and RC_CUMCOM
# before the bounds of VAR_CUMFLO and VAR_CUMCOM are set (`bnd_cum_flo`, `bnd_cum_com`, applied
# once by `bnd_data!`), on the crafted case demo12_cumc (reference/dd/demo12_cumc; M1.3, 14 Nov
# 2026). From GAMS's ppm dump through the coefficient stage and the coef -> pre-solve step, with
# TIMES.jl's own state; every set and parameter against the pre-solve dump (1e-9), then the model
# from that state against GAMS's matrix (layer 2): `bnd_cum!` takes the bounds from the tables
# as `bnd_data!` stored them.

using TIMES: TimesModel, DumpData, layer1, coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!,
             prepret_decl!, eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!, bnd_data!, pp_qack_data!,
             pp_clean!, generate!, gset, gparam, gv, GZERO
using TIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, compare_lp
import TOML

let vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
              if v["prefix"] == "demo12_cumc")
    tm = TimesModel(joinpath(FIXTURES, "demo12_cumc_ppm"); reduce=vx["reduce"], switches=vx["switches"])
    names = sort([i.name for i in values(tm.data.dump.symbols) if i.kind in (:set, :parameter)])
    coef_cpt!(tm); coef_nio!(tm); coef_ptr!(tm); coef_obj!(tm); coef_alt!(tm); coef_shp!(tm); coef_ext!(tm)
    foreach(f -> f(tm), (prepret_decl!, eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!, bnd_data!,
                         pp_qack_data!, pp_clean!))
    @testset "ppm -> pre-solve, every set and parameter" begin
        ref = DumpData(joinpath(FIXTURES, "demo12_cumc_presolve"))
        r = layer1(tm, ref, filter(n -> haskey(ref.dump.symbols, n) && n != "TJL_SOLVEINFO", names))
        foreach(d -> ispass(d) || println("demo12_cumc ppm -> presolve: ", d, " ", d.examples), r)
        @test length(r) > 800 && all(ispass, r)
    end
    @testset "branches of bnd_cum.mod" begin
        flo, com, rc = gparam(tm, "FLO_CUM"), gparam(tm, "COM_CUM"), gset(tm, "RC_CUMCOM")
        f(k...) = gv(flo, k)
        c(k...) = gv(com, k)
        # L12: a negative bound is ignored
        @test iszero(f("REG2", "MINGAS2", "GAS", "2005", "2050", "LO"))
        # L16: FX becomes LO and UP
        @test f("REG2", "MINOIL2", "OIL", "2005", "2030", "LO").v == 9500 == f("REG2", "MINOIL2", "OIL", "2005", "2030", "UP").v
        @test iszero(f("REG2", "MINOIL2", "OIL", "2005", "2030", "FX"))
        # L13-14, L19-20: the lead stays under 'EOH'; the range to %EOTIME% gets MULTI('2',MIYR_L) - 1
        @test f("REG2", "MINGAS2", "GAS", "2010", "EOH", "N").v == 2
        @test f("REG2", "MINGAS2", "GAS", "2010", "2200", "N").v ≈ -0.2
        # L27-28, L34-35: the same for COM_CUM, the lead under the '0' key
        @test c("REG2", "NET", "2010", "0", "TOTCO2", "N").v == 2
        @test c("REG2", "NET", "2010", "2200", "TOTCO2", "N").v ≈ -0.2
        # L30: FX becomes LO and UP
        @test c("REG2", "PRD", "2010", "2050", "ELCCO2", "LO").v == 1.85e7 == c("REG2", "PRD", "2010", "2050", "ELCCO2", "UP").v
        # L31: a range starting after the last milestone year gets EPS bounds and leaves RC_CUMCOM
        @test all(b -> c("REG1", "NET", "2060", "2070", "TOTCO2", b).eps, ("LO", "FX", "UP"))
        @test !(("REG1", "NET", "2060", "2070", "TOTCO2") in rc)
        # L38: a user-constraint range with no lower bound gets -INF where an annual COM_BNDNET LO is
        # negative (REG1), and nothing where none is (REG2)
        @test c("REG1", "NET", "2010", "2030", "TOTCO2", "LO").v == -Inf
        @test ("REG2", "NET", "2020", "2050", "TOTCO2") in rc && iszero(c("REG2", "NET", "2020", "2050", "TOTCO2", "LO"))
    end
    @testset "the model from that state (layer 2)" begin
        generate!(tm)                               # the bounds from FLO_CUM and COM_CUM as stored
        mine = canonical_from_jump(tm.model)
        ref = canonical_from_dump(joinpath(FIXTURES, "demo12_cumc_matrix", "matrix"),
                                  joinpath(FIXTURES, "demo12_cumc_matrix", "dictmap"))
        cmp = compare_lp(mine, ref)
        ispass(cmp) || foreach(println, cmp.examples)
        @test ispass(cmp)
        col(k) = mine.cols[k]
        # L23-24: bound / %CUFSCAL% * (N + 1)
        @test col("VAR_CUMFLO(REG2,MINOIL2,OIL,2005,2030)").lb ≈ 950 ≈ col("VAR_CUMFLO(REG2,MINOIL2,OIL,2005,2030)").ub
        @test col("VAR_CUMFLO(REG2,MINGAS2,GAS,2010,2200)").ub ≈ 30000 / 10 * 0.8
        # L39-40: bound / %CUCSCAL% * (N + 1)
        @test col("VAR_CUMCOM(REG2,TOTCO2,NET,2010,2200)").ub ≈ 2e8 / 1000 * 0.8
        @test col("VAR_CUMCOM(REG2,ELCCO2,PRD,2010,2050)").lb ≈ 18500 ≈ col("VAR_CUMCOM(REG2,ELCCO2,PRD,2010,2050)").ub
        @test col("VAR_CUMCOM(REG1,TOTCO2,NET,2010,2030)").lb == -Inf
        @test col("VAR_CUMCOM(REG2,TOTCO2,NET,2020,2050)").lb == 0
    end
end
