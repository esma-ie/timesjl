# eqashar.vda L16-33 with pp_lvlfc.mod (`eqashar_prep!`, called by coef_ext!: RPCG_ASHAR and the
# levelling of FLO_ASHAR) and EQ(l)_ASHAR with its exchange branch (L56-65) and storage terms
# (L51, L75-76), on the crafted case demo12_ashar (reference/dd/demo12_ashar; M1.3, 14 Nov 2026).
# From GAMS's ppm dump through the coefficient stage and the coef -> pre-solve step, with
# TIMES.jl's own state; every set and parameter against the pre-solve dump (1e-9), then the model
# from that state against GAMS's matrix (layer 2).

using TIMES: TimesModel, DumpData, layer1, coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!,
             prepret_decl!, eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!, bnd_data!, pp_qack_data!,
             pp_clean!, generate!, gset, gparam, gv
using TIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, compare_lp
import TOML

let vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
              if v["prefix"] == "demo12_ashar")
    tm = TimesModel(joinpath(FIXTURES, "demo12_ashar_ppm"); reduce=vx["reduce"], switches=vx["switches"])
    names = sort([i.name for i in values(tm.data.dump.symbols) if i.kind in (:set, :parameter)])
    coef_cpt!(tm); coef_nio!(tm); coef_ptr!(tm); coef_obj!(tm); coef_alt!(tm); coef_shp!(tm); coef_ext!(tm)
    foreach(f -> f(tm), (prepret_decl!, eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!, bnd_data!,
                         pp_qack_data!, pp_clean!))
    @testset "ppm -> pre-solve, every set and parameter" begin
        ref = DumpData(joinpath(FIXTURES, "demo12_ashar_presolve"))
        r = layer1(tm, ref, filter(n -> haskey(ref.dump.symbols, n) && n != "TJL_SOLVEINFO", names))
        foreach(d -> ispass(d) || println("demo12_ashar ppm -> presolve: ", d, " ", d.examples), r)
        @test length(r) > 800 && all(ispass, r)
    end
    @testset "branches of eqashar.vda L16-33" begin
        ashar, shar, rpcg = gparam(tm, "FLO_ASHAR"), gparam(tm, "FLO_SHAR"), gparam(tm, "RPCG_ASHAR")
        a(k...) = gv(ashar, k)
        g(k...) = gv(rpcg, k).v
        tu = "TU_GAS_REG2_REG1_01"
        # L17: an EPS FLO_SHAR record at year '0' for each group as given (before L22 moves the
        # diagonal to the commodity's type)
        @test gv(shar, ("REG1", "0", "ELCTNGAS01", "ELCGAS", "ACT", "ANNUAL", "LO")).eps
        @test gv(shar, ("REG2", "0", tu, "GAS", "GAS", "ANNUAL", "LO")).eps
        @test iszero(gv(shar, ("REG2", "0", tu, "GAS", "NRG", "ANNUAL", "LO")))
        # L21: a commodity against itself, on an exchange process whose flow is at the process level: -1
        @test g("REG2", tu, "GAS", "NRG", "ANNUAL") == -1
        # L22-23: the diagonal is copied to the commodity's type and deleted
        @test a("REG2", "2010", tu, "GAS", "NRG", "ANNUAL", "UP").v == 1.5 == a("REG2", "2050", tu, "GAS", "NRG", "ANNUAL", "UP").v
        @test iszero(a("REG2", "2010", tu, "GAS", "GAS", "ANNUAL", "UP"))
        @test a("REG1", "2030", "RSHNGAS1", "ELC", "NRG", "ANNUAL", "UP").v == 1
        @test iszero(a("REG1", "2030", "RSHNGAS1", "ELC", "ELC", "ANNUAL", "UP"))
        # L25: a flow of the process, at the timeslices of its flow variable
        @test all(s -> g("REG1", "ELCTNGAS01", "ELCGAS", "ACT", s) == 1, ("SD", "SN", "WD", "WN"))
        @test g("REG1", "RSHNGAS1", "RSDGAS", "ACT", "ANNUAL") == 1
        @test all(s -> g("REG1", "ELCTNCOA01", "ELCCOA", "ACT", s) == 1, ("S", "W"))
        # L26: a storage process, at the timeslices of its storage level
        @test all(s -> g("REG1", "ASTGELC", "ELC", "ACT", s) == 1, ("SD", "SN", "WD", "WN"))
        # L28-30: a commodity that is not a flow of the process, at the timeslices of its level
        @test all(s -> g("REG1", "RSHNGAS1", "ELC", "RSDGAS", s) == 1, ("SD", "SN", "WD", "WN"))
        @test all(s -> g("REG1", "RSHNGAS1", "ELC", "ELC", s) == 1, ("SD", "SN", "WD", "WN"))
        # exchange processes against a reference group: ANNUAL
        @test g("REG1", "IMPGAS1", "GAS", "IMP", "ANNUAL") == 1 == g("REG2", "IMPGAS1", "GAS", "IMP", "ANNUAL")
        # L31: the scratch set is cleared
        @test isempty(gset(tm, "CG_GRP").keys)
        # L33 (pp_lvlfc.mod): seasonal shares levelled to the DAYNITE timeslices of the flow variable;
        # an ANNUAL share of a process at a finer level stays at ANNUAL; the '0' marker of the
        # interpolation option stays
        @test [a("REG1", "2010", "ELCTNGAS01", "ELCGAS", "ACT", s, "UP").v for s in ("SD", "SN", "WD", "WN")] == [4, 4, 5, 5]
        @test [a("REG1", "2050", "ELCTNOIL01", "ELCOIL", "ACT", s, "UP").v for s in ("SD", "SN", "WD", "WN")] == [5, 5, 4, 4]
        @test iszero(a("REG1", "2010", "ELCTNGAS01", "ELCGAS", "ACT", "S", "UP"))
        @test a("REG1", "2010", "ELCTNCOA01", "ELCCOA", "ACT", "ANNUAL", "UP").v == 4
        @test a("REG1", "2010", "RSHNGAS1", "RSDGAS", "ACT", "ANNUAL", "UP").v ≈ 2.4794520547945176
        @test a("REG1", "0", "RSHNGAS1", "RSDGAS", "ACT", "ANNUAL", "UP").v == 1
        # bounds of exchange processes against the reference group IMP, one per region
        @test a("REG1", "2010", "IMPGAS1", "GAS", "IMP", "ANNUAL", "UP").v == 0.8
        @test a("REG2", "2010", "IMPGAS1", "GAS", "IMP", "ANNUAL", "LO").v == 0.1
    end
    @testset "the model from that state (layer 2)" begin
        generate!(tm)
        mine = canonical_from_jump(tm.model)
        ref = canonical_from_dump(joinpath(FIXTURES, "demo12_ashar_matrix", "matrix"),
                                  joinpath(FIXTURES, "demo12_ashar_matrix", "dictmap"))
        cmp = compare_lp(mine, ref)
        ispass(cmp) || foreach(println, cmp.examples)
        @test ispass(cmp)
        @test count(r -> occursin("_ASHAR(", r), keys(mine.rows)) == 64
        co(r, c) = get(mine.coefs, (r, c), 0.0)
        # L51 and L75-76: a storage process, its output against its activity
        row = "EQG_ASHAR(REG1,2010,2010,ASTGELC,ELC,ACT,SD)"
        @test co(row, "VAR_ACT(REG1,2010,2010,ASTGELC,SD)") ≈ 2 && co(row, "VAR_SOUT(REG1,2010,2010,ASTGELC,ELC,SD)") ≈ -1
        # L56-65: an exchange process against the reference group IMP, summed over the regions
        # (as_run: the flows through VAR_ACT, RPC_AIRE)
        row = "EQG_ASHAR(REG1,2010,2010,IMPGAS1,GAS,IMP,ANNUAL)"
        @test co(row, "VAR_ACT(REG1,2010,2010,IMPGAS1,ANNUAL)") ≈ -0.2 && co(row, "VAR_ACT(REG2,2010,2010,IMPGAS1,ANNUAL)") ≈ 0.8
        row = "EQL_ASHAR(REG2,2010,2010,IMPGAS1,GAS,IMP,ANNUAL)"
        @test co(row, "VAR_ACT(REG1,2010,2010,IMPGAS1,ANNUAL)") ≈ 0.1 && co(row, "VAR_ACT(REG2,2010,2010,IMPGAS1,ANNUAL)") ≈ -0.9
        # the commodity against its own type (L21-22), and against the activity
        tu = "TU_GAS_REG2_REG1_01"
        @test co("EQG_ASHAR(REG2,2010,2010,$tu,GAS,NRG,ANNUAL)", "VAR_ACT(REG2,2010,2010,$tu,ANNUAL)") ≈ 0.5
        @test co("EQG_ASHAR(REG1,2010,2010,$tu,GAS,ACT,ANNUAL)", "VAR_ACT(REG1,2010,2010,$tu,ANNUAL)") ≈ 0.5
        @test mine.rows["EQG_ASHAR(REG1,2010,2010,IMPGAS1,GAS,IMP,ANNUAL)"].lo == 0
    end
end
