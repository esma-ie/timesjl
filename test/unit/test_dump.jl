using OpenTIMES.Reference

d = load_dump(joinpath(FIXTURES, "tiny_dump"))

@test length(symbol_names(d)) == 8
@test has_symbol(d, "ncap_cost")            # case-insensitive, as in GAMS
@test !has_symbol(d, "VAR_FLO")
@test first(d.uels) == "REG2"
@test_throws KeyError read_symbol(d, "VAR_FLO")

# Ordered set: record order is GAMS order, not sorted order.
reg = read_symbol(d, "REG")
@test reg isa SymbolRecords{1}
@test reg.keys == [("REG2",), ("REG1",)]
@test reg.text == ["second", "first"]

# Alias resolves to its set.
@test read_symbol(d, "ALL_R").keys == reg.keys

top = read_symbol(d, "TOP")
@test top isa SymbolRecords{4}
@test top.keys[2] == ("REG1", "ELC01", "ELC", "OUT")

# Special values survive the Python -> Arrow -> Julia round trip.
nc = read_symbol(d, "NCAP_COST")
@test nc.special["value"] == [SV_NONE, SV_EPS, SV_NONE, SV_NONE]
@test nc.values["value"][1] == 1200.5
@test signbit(nc.values["value"][2]) && nc.values["value"][2] == 0
@test nc.values["value"][3] == Inf

# Scalar (0-dimensional) parameter.
g = read_symbol(d, "G_DYEAR")
@test g isa SymbolRecords{0}
@test g.keys == [()]
@test g.values["value"] == [2005.0]

# Variables and equations carry all five attributes.
va = read_symbol(d, "VAR_ACT")
@test va.info.type == "positive"
@test sort(collect(keys(va.values))) == ["level", "lower", "marginal", "scale", "upper"]
@test va.special["marginal"] == [SV_EPS]
@test va.values["upper"] == [Inf]

# Symbol with no records.
e = read_symbol(d, "EMPTYPAR")
@test e isa SymbolRecords{2}
@test length(e) == 0

@test_throws ArgumentError load_dump(FIXTURES)
