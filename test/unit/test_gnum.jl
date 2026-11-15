# GAMS extended-range arithmetic for EPS (docs/discrepancies.md G4-G6).
# Expected values are GAMS 54.6.0's own results for the same expressions
# (parameter r(k1..k12) of a check program, 20 Oct 2026).

using TIMES: GNum, GZERO, GEPS, gv, gif, gexp, gpower, gpow, gmax, gparam, DumpData

@testset "GNum arithmetic matches GAMS" begin
    e = GEPS
    z = GZERO
    @test e + 0 == GEPS                       # k1  EPS + 0
    @test e * 0 == GZERO                      # k2  EPS * 0
    @test e * 2 == GEPS                       # k3  EPS * 2
    @test e - e == GEPS                       # k4  EPS - EPS
    @test 1 + e - 1 == GZERO                  # k5  1 + EPS - 1
    @test e + 3 == GNum(3.0)                  # k6  EPS + 3
    @test e / 2 == GEPS                       # k7  EPS / 2
    @test -e == GEPS                          # k8  -EPS
    @test e * e == GEPS                       # k9  EPS * EPS
    @test 1 + (e - gif(1, true)) == GZERO     # k10 1 + (EPS - 1$EPS)
    @test GNum(2) - 2 == GZERO                # k11 2 - 2
    @test (1 + z) * e == GEPS                 # k12 (1+0) * EPS

    @test iszero(GZERO) && !iszero(GEPS) && !iszero(GNum(-0.5))
    # G17 (GAMS 54.6.0, 21 Oct 2026): 1/INF, EPS/INF, -1/INF and 1/-INF are exact
    # zeros (no matrix entry, false in a \$-condition).
    @test GNum(1.0) / GNum(Inf) == GZERO && GEPS / GNum(Inf) == GZERO
    @test GNum(-1.0) / GNum(Inf) == GZERO && GNum(1.0) / GNum(-Inf) == GZERO
    @test gif(5, false) == GZERO && gif(5, true) == GNum(5.0)
    @test gpower(GZERO, 0) == GNum(1.0)       # G4 power(0,0) = 1
    @test gpower(GEPS, 1) == GEPS && gpower(GNum(2.0), 3) == GNum(8.0)
    # G16 (GAMS 54.6.0, 20 Oct 2026): power(EPS,2) = EPS, power(EPS,0) = 1,
    # power(-2,3) = -8, power(2,-2) = 0.25; power(1.01,3.5) is FUNC DOMAIN and
    # power(0,-2), power(EPS,-2) FUNC SINGULAR; abs(EPS) = EPS.
    @test gpower(GEPS, 2) == GEPS && gpower(GEPS, 0) == GNum(1.0)
    @test gpower(GNum(-2.0), 3) == GNum(-8.0) && gpower(GNum(2.0), -2) == GNum(0.25)
    @test gpower(GNum(1.01), GNum(4.0)) == GNum((1.01 * 1.01) * (1.01 * 1.01))
    # G61 (GAMS 54.6.1, 15 Nov 2026): POWER(x,n) to the last bit, the binary method from the lowest
    # bit, the reciprocal for n < 0, 1/x/x for n = -2. Values of GAMS that x^n does not give.
    for (x, n, g) in ((3.61474609375, -12, 2.009400171819468e-7), (2.75341796875, -5, 0.00631886807931012),
                      (1.6904296875, -3, 0.20701826586205585), (-2.1435546875, -2, 0.2176360645700261),
                      (1.451171875, 10, 41.41794316763117), (0.57763671875, 25, 1.0999420575242372e-6))
        @test gpower(GNum(x), n) == GNum(g) && x^n != g
    end
    @test_throws DomainError gpower(GNum(1.01), GNum(3.5))
    @test_throws DomainError gpower(GZERO, -2)
    @test_throws DomainError gpower(GEPS, -2)
    @test abs(GEPS) == GEPS && abs(GNum(-2.0)) == GNum(2.0) && abs(GZERO) == GZERO
    @test gexp(GEPS) == GNum(1.0)
    @test_throws DomainError GNum(1.0) / GEPS
    @test_throws DomainError GNum(1.0) / GZERO
    @test GZERO / GNum(4.0) == GZERO
end

@testset "x**y and MAX match GAMS (G13, G14)" begin
    # GAMS 54.6.0 results of the same expressions (check programs, 20 Oct 2026).
    e, z, one = GEPS, GZERO, GNum(1.0)
    @test gpow(e, gif(1, false)) == one          # EPS**1$no = EPS**0 = 1 ($ binds tighter than **)
    @test gpow(e, one) == GEPS                   # EPS**1
    @test gpow(GNum(0.5), e) == one              # 0.5**EPS
    @test gpow(z, e) == one                      # 0**EPS
    @test gpow(e, e) == one                      # EPS**EPS
    @test gpow(z, z) == one                      # 0**0
    @test gpow(GNum(2.0), e) == one              # 2**EPS
    @test gpow(z, one) == GZERO                  # 0**1
    @test gpow(z, GNum(2.0)) == GZERO            # 0**2
    @test gpow(e, GNum(2.0)) == GEPS             # EPS**2
    @test gpow(e, GNum(0.5)) == GEPS             # EPS**0.5
    @test gpow(GNum(0.5), one) == GNum(0.5) && gpow(GNum(4.0), GNum(0.5)) == GNum(2.0)
    @test_throws DomainError gpow(GNum(-0.5), one)        # rPower: x < 0
    # G61 (GAMS 54.6.1, 15 Nov 2026): x**y is exp(y*log(x)). Values of GAMS that the correctly
    # rounded power x^y does not give; the last five are powers of a discount factor 1/(1+r).
    for (x, y, g) in ((0.5595703125, -2.390625, 4.006682606424645), (1.4462890625, -37.625, 9.34118109498544e-7),
                      (3.9609375, 23.921875, 1.997325213924779e14), (3.912109375, 0.5, 1.9779052998058326),
                      (3.6943359375, 26.984375, 2.0635482575504642e15), (0.6455078125, 10.0, 0.012560734284896171),
                      (1.2109375, -4.625, 0.41263114555274166), (3.1396484375, 37.890625, 6.71633611391785e18),
                      (0.9147962032384143, 52.0, 0.009746897056821996), (0.9409386414279478, 23.0625, 0.2456165201469827),
                      (0.9456308438185386, 5.0, 0.7561503302343168), (0.9226679881963372, 30.515625, 0.08577093705558125),
                      (0.9300002270508366, -25.984375, 6.590951692874547))
        @test gpow(GNum(x), GNum(y)) == GNum(g) && x^y != g
    end
    @test_throws DomainError gpow(z, GNum(-1.0))          # rPower: x = 0, y < 0
    m1 = GNum(-1.0)
    @test gmax(z, e) == GEPS && gmax(e, z) == GEPS        # MAX(0,EPS), MAX(EPS,0)
    @test gmax(e, m1) == GEPS && gmax(m1, e) == GEPS      # MAX(EPS,-1), MAX(-1,EPS)
    @test gmax(z, m1) == GZERO && gmax(GNum(0.1), GNum(0.3)) == GNum(0.3)
    @test 1 + gmax(e, m1) == one
end

@testset "gv reads parameters as GAMS values" begin
    # test/fixtures/tiny_dump is synthetic (reference/python/make_test_fixture.py).
    data = DumpData(joinpath(FIXTURES, "tiny_dump"))
    cost = gparam(data, "NCAP_COST")
    @test gv(cost, ("REG1", "2020", "ELC01", "EUR")) == GNum(1200.5)
    @test gv(cost, ("REG1", "2020", "NOSUCH", "EUR")) == GZERO
    eps_entry = TIMES.GamsParam{1}("X", [("a",)], Dict(("a",) => 0.0))
    @test gv(eps_entry, ("a",)) == GEPS
end
