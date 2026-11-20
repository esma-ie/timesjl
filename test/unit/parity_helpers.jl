# Shared layer-2 parity check: one equation family of a TIMES.jl model
# against the CONVERT export of the GAMS run (matched by GAMS-style names).

using OpenTIMES.Reference: family, sense

_same_bound(a, b; rtol) = (isinf(a) || isinf(b)) ? a == b : isapprox(a, b; rtol=rtol, atol=0.0)

"""
    check_family_parity(mine, ref, fam; rtol=1e-9)

Row set, senses, right-hand sides and every coefficient of equation family
`fam`, at relative tolerance `rtol` (translation guide, layer 2).
"""
function check_family_parity(mine, ref, fam::AbstractString; rtol=1e-9)
    ref_rows = Dict(k => r for (k, r) in ref.rows if family(k) == fam)
    my_rows = Dict(k => r for (k, r) in mine.rows if family(k) == fam)
    ref_coefs = Dict(ij => v for (ij, v) in ref.coefs if family(ij[1]) == fam)
    my_coefs = Dict(ij => v for (ij, v) in mine.coefs if family(ij[1]) == fam)
    @testset "$fam parity" begin
        @test sort(collect(keys(my_rows))) == sort(collect(keys(ref_rows)))
        for (k, r) in my_rows
            haskey(ref_rows, k) || continue
            @test sense(r) == sense(ref_rows[k])
            @test _same_bound(r.lo, ref_rows[k].lo; rtol)
            @test _same_bound(r.hi, ref_rows[k].hi; rtol)
        end
        @test length(my_coefs) == length(ref_coefs)
        for (ij, v) in ref_coefs
            @test haskey(my_coefs, ij)
            haskey(my_coefs, ij) && @test isapprox(my_coefs[ij], v; rtol=rtol, atol=0.0)
        end
    end
    return length(my_rows)
end
