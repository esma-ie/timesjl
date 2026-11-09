# M1.2 (3): coef_ptr.mod L9-54 (v4.9.7) on two crafted TIMES_Demo demo12
# states against coef_ptr.mod run by GAMS itself (scripts/make_coef_ptr_unit.jl):
# the FLO_FUNC paths (forward, reverse, both directions, the single-commodity
# group of L23, L51) and the FLO_SUM edge cases (EPS at L27 and L34, a record
# outside the model years kept by L16). demo12 itself has FLO_SUM only; its
# layer 1 is in test_public_parity.jl.

using TIMES: DumpData, coef_ptr!, coef_ptr_unported, layer1, gparam, gset, gput!, iseps, UnportedError
using TIMES.Reference: ispass

isdefined(@__MODULE__, :PPM_DEMO12) || (const PPM_DEMO12 = joinpath(FIXTURES, "demo12_off_ppm"))
include("coef_ptr_case.jl")

@testset "coef_ptr against GAMS on crafted states" begin
    for name in COEF_PTR_CASES
        tm = coef_ptr_start(PPM_DEMO12, name)
        @test isempty(coef_ptr_unported(tm))
        coef_ptr!(tm)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "coefptr_unit_gams", name)), COEF_PTR_OUTPUTS)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        cp = gparam(tm, "COEF_PTRAN")
        ffunc = gset(tm, "RPCC_FFUNC")
        k(v, p, cg1, c, cg2, s) = ("REG1", v, p, cg1, c, cg2, s)
        if name == "flofunc"
            # L21-22: forward FLO_FUNC(ELCGAS,ELC) at the DAYNITE timeslices; none at WN gives 1;
            # the ANNUAL record (9) is not in TS_GROUP(DAYNITE) and is left out of the L31 sum
            @test [cp[k("2010", "ELCTNGAS01", "ELCGAS", "ELCGAS", "ELC", s)] for s in ("SD", "SN", "WD", "WN")] == [0.5, 0.55, 0.6, 1.0]
            # L23: FLO_SUM(ELCGAS,ELCCO2,ELC) puts ELCCO2 into the group ELCGAS: 0.5 * 2 at SD, 0.55 * 1 at SN
            @test cp[k("2010", "ELCTNGAS01", "ELCGAS", "ELCCO2", "ELC", "SD")] == 1.0
            @test cp[k("2010", "ELCTNGAS01", "ELCGAS", "ELCCO2", "ELC", "SN")] == 0.55
            # L18-19, L32: reverse FLO_FUNC(ELC,NRG) 0.4 -> 1/0.4, times FLO_SUM 1.5 for ELCGAS
            @test cp[k("2015", "ELCTNGAS01", "NRG", "ELC", "ELC", "SD")] ≈ 2.5
            @test cp[k("2015", "ELCTNGAS01", "NRG", "ELCGAS", "ELC", "SD")] ≈ 3.75
            # L19 builds CGTES2 at every vintage of the process: 1 at 2010, where nothing was given
            @test cp[k("2010", "ELCTNGAS01", "NRG", "ELC", "ELC", "SD")] == 1.0
            # both directions at 2020: L32 takes the forward 3 (not 1/0.25); L27 drops (ELC,NRG),
            # whose reverse group (NRG,ELC) has a FLO_SUM
            @test cp[k("2020", "ELCTNGAS01", "NRG", "ELC", "ELC", "SD")] == 3.0
            @test !any(x -> x[3] == "ELCTNGAS01" && x[4] == "ELC" && x[6] == "NRG", keys(cp.values))
            # reverse on COTNCOA1: 1/0.8 * 1.25
            @test cp[k("2030", "COTNCOA1", "NRG", "COMCOA", "DCOT", "ANNUAL")] ≈ 1.5625
            # L51: ELCCOA is a REG1 commodity outside ELCTNGAS01: no RPCC_FFUNC record, but L50 adds it to PRC_CG
            @test cp[k("2030", "ELCTNGAS01", "ELCGAS", "ELCGAS", "ELCCOA", "SD")] == 0.7
            @test !(("REG1", "ELCTNGAS01", "ELCGAS", "ELCCOA") in ffunc)
            @test ("REG1", "ELCTNGAS01", "ELCCOA") in gset(tm, "PRC_CG")
        else
            # L27: an EPS FLO_SUM counts as given (YES$EPS) and the coefficient is EPS (G6, G25)
            @test iseps(cp, k("2010", "ELCTNGAS01", "ELCGAS", "ELCGAS", "ELC", "SN"))
            # L34: $= stores the EPS (G24)
            @test iseps(cp, k("2015", "ELCTECOA00", "ELCCO2", "ELCCOA", "ELCCO2", "W"))
            # L16: the record at 2012 (not a model year) is kept and projected into RPCC_FFUNC;
            # the one at the model year 2010 on COTNCOA1 is removed (ELCGAS is not an RPC)
            @test ("REG1", "ELCTECOA00", "NRG", "ELC") in ffunc
            @test !(("REG1", "COTNCOA1", "NRG", "DCOT") in ffunc)
            @test !any(x -> x[2] == "2012", keys(cp.values))
        end
    end
end

@testset "coef_ptr translates reduced flows (L38-42)" begin
    tm = coef_ptr_start(PPM_DEMO12, "flosum")
    gput!(tm, "RPCG_PTRAN", Set([("REG1", "ELCTNGAS01", "ELCGAS", "ELC", "NRG", "ELC")]))
    @test isempty(coef_ptr_unported(tm))           # checked on every as_run reference against GAMS's coef dump
end
