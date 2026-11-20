using OpenTIMES.Reference

d = load_dump(joinpath(FIXTURES, "tiny_dump"))

# M1.0 gate in miniature: a dump compared with itself has no differences.
r = compare_dumps(d, d; kinds=(:set, :parameter, :variable, :equation))
@test ispass(r)
@test length(r.symbols) == 7          # the alias is not compared separately

nc = read_symbol(d, "NCAP_COST")
k = nc.keys

# Value outside 1e-9 relative is caught; inside is not.
c = compare_symbol(nc, SymbolRecords("NCAP_COST", :parameter, k; values=Dict("value" => [1200.5 * (1 + 2e-9), -0.0, Inf, 1e-12])))
@test !ispass(c) && c.counts[:value] == 1
c = compare_symbol(nc, SymbolRecords("NCAP_COST", :parameter, k; values=Dict("value" => [1200.5 * (1 + 5e-10), -0.0, Inf, 1e-12])))
@test ispass(c)

# EPS is not the same as an absent entry or an ordinary zero.
c = compare_symbol(nc, SymbolRecords("NCAP_COST", :parameter, k[[1, 3, 4]]; values=Dict("value" => [1200.5, Inf, 1e-12])))
@test c.counts == Dict(:missing_right => 1)     # EPS on the left, absent on the right
c = compare_symbol(nc, SymbolRecords("NCAP_COST", :parameter, k; values=Dict("value" => [1200.5, 0.0, Inf, 1e-12])))
@test c.counts[:special] == 1

# An explicit ordinary zero on one side equals an absent entry on the other (GAMS stores no zeros).
extra = [k; [("REG3", "2020", "ELC01", "EUR")]]
c = compare_symbol(nc, SymbolRecords("NCAP_COST", :parameter, extra; values=Dict("value" => [1200.5, -0.0, Inf, 1e-12, 0.0])))
@test ispass(c)

# Infinity must match exactly; tiny values have no absolute slack by default.
c = compare_symbol(nc, SymbolRecords("NCAP_COST", :parameter, k; values=Dict("value" => [1200.5, -0.0, 1e300, 0.0])))
@test c.counts[:value] == 2
c = compare_symbol(nc, SymbolRecords("NCAP_COST", :parameter, k; values=Dict("value" => [1200.5, -0.0, Inf, 0.0])); atol=1e-11)
@test ispass(c)

# Sets: membership and, for one-dimensional sets, order.
reg = read_symbol(d, "REG")
@test ispass(compare_symbol(reg, SymbolRecords("REG", :set, [("REG2",), ("REG1",)])))
c = compare_symbol(reg, SymbolRecords("REG", :set, [("REG1",), ("REG2",)]); check_order=true)
@test c.counts[:order] == 1
@test ispass(compare_symbol(reg, SymbolRecords("REG", :set, [("REG1",), ("REG2",)]); check_order=false))
c = compare_symbol(reg, SymbolRecords("REG", :set, [("REG1",), ("REG9",)]))
@test c.counts[:missing_right] == 1 && c.counts[:missing_left] == 1

# Variables: records must exist on both sides; columns can be restricted.
va = read_symbol(d, "VAR_ACT")
other = SymbolRecords("VAR_ACT", :variable, va.keys;
                      values=Dict("level" => [9.0], "marginal" => [-0.0], "lower" => [0.0], "upper" => [Inf], "scale" => [1.0]))
@test compare_symbol(va, other).counts[:value] == 1
@test ispass(compare_symbol(va, other; columns=["lower", "upper"]))
@test compare_symbol(va, SymbolRecords("VAR_ACT", :variable, NTuple{5,String}[]; values=Dict("level" => Float64[]))).counts[:missing_right] == 1

# Dimension mismatch is reported, not thrown.
@test compare_symbol(nc, SymbolRecords("NCAP_COST", :parameter, [("REG1",)]; values=Dict("value" => [1.0]))).counts[:dimension] == 1

# Report text names the failing symbol.
@test occursin("PASS", summary_table(r))
