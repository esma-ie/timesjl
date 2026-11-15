# The cumulative equations under OBJ LIN: EQ_CUMFLO (eqcumflo.mod L21, L24) and EQ_CUMNET and
# EQ_CUMPRD (eqcumcom.mod L20, L23). With OBJ LIN a period counts in a year range when
# M(T)+LAGT(T) > the first year and M(T)-LEAD(T) < the last, and its weight is the sum of its
# TPULSE over the years of the range, not the number of its years in the range.
#
# GAMS's rows are those of the crafted case demo12_cumlin (reference/dd/demo12_cumlin: the run
# file of demo12_cumc with OBJ LIN; GAMS 54.6.1, as run), kept in demo12_cumlin_cumrows.json
# (scripts/make_rows_fixture.jl). TIMES.jl's rows come from the pre-solve fixture of demo12_cumc
# with the switch OBJ set to LIN: the sets and parameters these rows read (TPULSE, TPULSEYR,
# LAGT, LEAD, the cumulative ranges) are the same in the two runs. The whole case, layers 1 to
# 3, is checked on the workstation (scripts/m13_gate.jl, scripts/m11_probe.jl).

using TIMES: TimesModel, generate!
using TIMES.Reference: canonical_from_jump, canonical_from_dump
import TOML, JSON

let vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
              if v["prefix"] == "demo12_cumc")
    fams = ("EQ_CUMFLO", "EQ_CUMNET", "EQ_CUMPRD")
    fam(r) = first(split(r, "("))
    rows_of(lp) = Dict(r => (x.lo, x.hi) for (r, x) in lp.rows if fam(r) in fams)
    coefs_of(lp) = Dict(k => x for (k, x) in lp.coefs if fam(k[1]) in fams)
    doc = JSON.parsefile(joinpath(FIXTURES, "demo12_cumlin_cumrows.json"))
    grows = Dict(String(r[1]) => (Float64(r[2]), Float64(r[3])) for r in doc["rows"])
    gcoefs = Dict((String(c[1]), String(c[2])) => Float64(c[3]) for c in doc["coefs"])

    tm = TimesModel(joinpath(FIXTURES, "demo12_cumc_presolve"); reduce=vx["reduce"],
                    switches=merge(vx["switches"], Dict("OBJ" => "LIN")))
    generate!(tm)
    lin = canonical_from_jump(tm.model)
    @testset "OBJ LIN: the rows equal GAMS's of demo12_cumlin" begin
        @test length(grows) == 23 && length(gcoefs) == 152
        @test count(r -> fam(r) == "EQ_CUMFLO", keys(grows)) == 19
        @test count(r -> fam(r) == "EQ_CUMNET", keys(grows)) == 3
        @test count(r -> fam(r) == "EQ_CUMPRD", keys(grows)) == 1
        @test rows_of(lin) == grows
        mine = coefs_of(lin)
        @test keys(mine) == keys(gcoefs)
        @test all(k -> isapprox(mine[k], gcoefs[k]; rtol=1e-9), keys(gcoefs))
    end
    @testset "the weights differ from those of OBJ MOD" begin
        # demo12_cumc itself (OBJ MOD): the same rows and columns, other weights where the two rules
        # count differently
        mod = canonical_from_dump(joinpath(FIXTURES, "demo12_cumc_matrix", "matrix"),
                                  joinpath(FIXTURES, "demo12_cumc_matrix", "dictmap"))
        cmod = coefs_of(mod)
        @test keys(cmod) == keys(gcoefs)
        @test count(k -> !isapprox(cmod[k], gcoefs[k]; rtol=1e-9), keys(gcoefs)) == 46
        w(row, col) = gcoefs[(row, col)]
        ts = ("2010", "2015", "2020", "2030", "2050")
        r = "EQ_CUMNET(REG2,TOTCO2,2010,2200)"
        v(t) = "VAR_COMNET(REG2,$t,TOTCO2,ANNUAL)"
        # divided by %CUCSCAL% (1000). OBJ LIN: the pulses of each period from 2010 on (the pulse of
        # 2020 runs from 2016 to 2029, of 2030 from 2021 to 2049, of 2050 from 2031 to 2052).
        # OBJ MOD: the years of each period from 2010 on (2020 is 2018-2025, 2030 is 2026-2040,
        # 2050 is 2041-2052)
        @test [w(r, v(t)) for t in ts] ≈ [0.003, 0.005, 0.0075, 0.015, 0.0125]
        @test [cmod[(r, v(t))] for t in ts] ≈ [0.003, 0.005, 0.008, 0.015, 0.012]
        # a range that ends in the milestone year 2030: the rising half of its pulse and the year
        # itself (5.5), against the five years 2026-2030 of the period
        r2 = "EQ_CUMNET(REG1,TOTCO2,2010,2030)"
        @test w(r2, "VAR_COMNET(REG1,2030,TOTCO2,ANNUAL)") ≈ 0.0055
        @test cmod[(r2, "VAR_COMNET(REG1,2030,TOTCO2,ANNUAL)")] ≈ 0.005
        # a range that starts in the milestone year 2020: the year and the falling half of its pulse
        # (5.5), against the six years 2020-2025
        r3 = "EQ_CUMNET(REG2,TOTCO2,2020,2050)"
        @test w(r3, v("2020")) ≈ 0.0055
        @test cmod[(r3, v("2020"))] ≈ 0.006
    end
end
