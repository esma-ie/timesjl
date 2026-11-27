# Phase 2, change 0: the identity gate (scripts/p2_identity.jl) on the public demo12 fixture
# (TIMES_Demo demo12, CC BY 4.0; test/fixtures/public_fixtures.toml, demo12_off).
#
# The gate must be exact and sensitive: two generations of the same input give the same fingerprint;
# the next Float64 in one coefficient, one right-hand side or one bound, or two rows the other way
# round, give another one, and the check names the part. test/fixtures/demo12_off_identity.json is
# the fingerprint written on James's workstation (Windows, Julia 1.13): the names, the counts and the
# state are compared with it on every machine, the order and the values on the same Julia minor
# version only (a Dict's iteration order and a function such as exp may differ between versions).

isdefined(@__MODULE__, :P2Identity) || @eval module P2Identity
    include(joinpath($(@__DIR__), "..", "..", "scripts", "p2_identity.jl"))
end
import JSON, JuMP
using TIMES: gset, gparam

changed_parts(a, b) = sort!([p for p in keys(a["parts"]) if a["parts"][p] != b["parts"][p]])

@testset "two generations of demo12_off: the same fingerprint" begin
    a = P2Identity.p2_fingerprint!(P2Identity.p2_fixture_model("demo12_off"))
    b = P2Identity.p2_fingerprint!(P2Identity.p2_fixture_model("demo12_off"))
    @test (a["rows"], a["columns"], a["nonzeros"]) == (8695, 9669, 31391)     # public_fixtures.toml
    @test a["lp"] == b["lp"]
    @test a["state"]["sha256"] == b["state"]["sha256"]
    @test a["parts"] == b["parts"]
    @test a["families"] == b["families"]
    @test isempty(P2Identity.p2_compare(a, b))
    @test sum(f["rows"] for f in a["families"]) == a["rows"]

    # the committed fingerprint
    ref = JSON.parsefile(joinpath(FIXTURES, "demo12_off_identity.json"))
    @test ref["format"] == P2Identity.P2_FORMAT
    @test (ref["rows"], ref["columns"], ref["nonzeros"]) == (a["rows"], a["columns"], a["nonzeros"])
    @test ref["parts"]["rows"] == a["parts"]["rows"]
    @test ref["parts"]["columns"] == a["parts"]["columns"]
    @test ref["state"]["sha256"] == a["state"]["sha256"]
    @test ref["state"]["by_symbol"] == a["state"]["by_symbol"]
    diff = P2Identity.p2_compare(ref, a)
    if VersionNumber(ref["julia"]).minor == VERSION.minor && VersionNumber(ref["julia"]).major == VERSION.major
        @test isempty(diff)
    elseif !isempty(diff)
        @info "demo12_off: order or values differ from the fingerprint written with Julia $(ref["julia"]) (not a failure on Julia $VERSION)" diff
    end
end

@testset "one bit in the model, or two rows swapped: another fingerprint, and the part named" begin
    tm = P2Identity.p2_fixture_model("demo12_off")
    P2Identity.generate!(tm)
    rec = P2Identity.lp_record(tm)
    base = P2Identity.lp_fingerprint(rec)
    @test P2Identity.lp_fingerprint(P2Identity.lp_record(tm)) == base         # reading twice changes nothing
    fp(x) = merge(x, Dict("state" => Dict("sha256" => "", "symbols" => 0, "records" => 0), "format_version" => 1))
    lines(x) = P2Identity.p2_compare(fp(base), fp(x))

    # one coefficient to the next Float64
    fam = tm.eqs.families["EQ_ACTFLO"]
    row = fam.refs[fam.keys[1]]
    v, c = first(JuMP.constraint_object(row).func.terms)
    JuMP.set_normalized_coefficient(row, v, nextfloat(c))
    x = P2Identity.lp_fingerprint(P2Identity.lp_record(tm))
    @test changed_parts(base, x) == ["coefficients"]
    @test x["lp"] != base["lp"]
    @test startswith(lines(x)[1], "coefficients:")
    @test any(l -> occursin("EQ_ACTFLO", l), lines(x))
    JuMP.set_normalized_coefficient(row, v, c)
    @test P2Identity.lp_fingerprint(P2Identity.lp_record(tm)) == base

    # 0.0 and -0.0 are not the same bits
    rhs = JuMP.normalized_rhs(row)
    @test rhs == 0.0
    JuMP.set_normalized_rhs(row, -0.0)
    x = P2Identity.lp_fingerprint(P2Identity.lp_record(tm))
    @test changed_parts(base, x) == ["row_bounds"]
    @test startswith(lines(x)[1], "bounds:")
    JuMP.set_normalized_rhs(row, rhs)

    # one column bound
    JuMP.set_lower_bound(v, nextfloat(0.0))
    x = P2Identity.lp_fingerprint(P2Identity.lp_record(tm))
    @test changed_parts(base, x) == ["column_bounds"]
    @test startswith(lines(x)[1], "bounds:")
    JuMP.set_lower_bound(v, 0.0)
    @test P2Identity.lp_fingerprint(P2Identity.lp_record(tm)) == base

    # the same rows, two of them the other way round: only the order
    n = length(rec.rownames)
    perm = collect(1:n); perm[1], perm[n] = n, 1
    x = P2Identity.lp_fingerprint(P2Identity.permute_rows(rec, perm))
    @test changed_parts(base, x) == ["row_order", "term_order"]
    @test all(l -> startswith(l, "order:") || startswith(l, "   families"), lines(x))
    perm = collect(1:n); perm[2], perm[3] = 3, 2              # two neighbours of one family
    x = P2Identity.lp_fingerprint(P2Identity.permute_rows(rec, perm))
    @test "row_order" in changed_parts(base, x)
    @test !("coefficients" in changed_parts(base, x)) && !("rows" in changed_parts(base, x))

    # one row less: the rows
    x = P2Identity.lp_fingerprint(P2Identity.permute_rows(rec, 1:n-1))
    @test "rows" in changed_parts(base, x) && !("columns" in changed_parts(base, x))
    @test startswith(lines(x)[1], "rows:")

    # the objective
    JuMP.set_objective_sense(tm.model, JuMP.MAX_SENSE)
    x = P2Identity.lp_fingerprint(P2Identity.lp_record(tm))
    @test changed_parts(base, x) == ["objective"]
    @test startswith(lines(x)[1], "objective:")
end

@testset "the state: read or not, the same; one bit, another" begin
    tm = P2Identity.p2_fixture_model("demo12_off")
    s0 = P2Identity.state_fingerprint(tm)
    # every symbol read into TIMES.jl's own containers: the same bytes as the dump's records
    for info in values(tm.data.dump.symbols)
        info.kind == :set && gset(tm, info.name)
        info.kind == :parameter && info.name != "TJL_SOLVEINFO" && gparam(tm, info.name)
    end
    s1 = P2Identity.state_fingerprint(tm)
    @test s1 == s0
    # one value to the next Float64
    name = first(sort!([n for (n, p) in tm.data.params if !isempty(p.values)]))
    p = tm.data.params[name]
    k = first(k for k in p.keys if get(p.values, k, 0.0) != 0.0)
    old = p.values[k]
    p.values[k] = nextfloat(old)
    s2 = P2Identity.state_fingerprint(tm)
    @test s2["sha256"] != s0["sha256"]
    @test [n for n in keys(s0["by_symbol"]) if s0["by_symbol"][n] != s2["by_symbol"][n]] == [name]
    a = Dict("state" => s0, "parts" => Dict(p => "" for p in P2Identity.P2_LP_PARTS), "lp" => "", "families" => [],
             "rows" => 0, "columns" => 0, "nonzeros" => 0, "format_version" => 1)
    d = P2Identity.p2_compare(a, merge(a, Dict("state" => s2)))
    @test length(d) == 1 && startswith(d[1], "state:") && occursin(name, d[1])
    p.values[k] = old
    # a switch
    tm.switches["OBJ"] = "ALT"
    s3 = P2Identity.state_fingerprint(tm)
    @test [n for n in keys(s0["by_symbol"]) if s0["by_symbol"][n] != s3["by_symbol"][n]] == ["(switches)"]
end
