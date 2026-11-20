using OpenTIMES.Reference
import OpenTIMES.Reference: canonical_key, jump_name_key, canonical_from_moi
using JuMP
import HiGHS

@test canonical_key("eqe_combal", ("reg1", 2020, "elc")) == "EQE_COMBAL(REG1,2020,ELC)"
@test jump_name_key("VAR_ACT[REG1,2020,2020,ELC01,ANNUAL]") == "VAR_ACT(REG1,2020,2020,ELC01,ANNUAL)"
@test jump_name_key("EQ_OBJ") == "EQ_OBJ"
@test jump_name_key("VAR_ACT('REG1','2020')") == "VAR_ACT(REG1,2020)"
@test_throws ArgumentError jump_name_key("")

"A two-region toy LP written the way TIMES.jl will write its models: named containers."
function toy(; cost=2.0, cap=10.0, extra_row=false)
    m = Model()
    R = ["REG1", "REG2"]
    @variable(m, VAR_ACT[r in R] >= 0)
    @variable(m, VAR_NCAP[r in R] >= 0, upper_bound = cap)
    @variable(m, objZ)
    @constraint(m, EQG_COMBAL[r in R], VAR_ACT[r] >= 3.0)
    @constraint(m, EQL_CAPACT[r in R], VAR_ACT[r] - VAR_NCAP[r] <= 0)
    @constraint(m, EQ_OBJ, objZ == sum(cost * VAR_ACT[r] + 1.0 * VAR_NCAP[r] for r in R))
    extra_row && @constraint(m, EXTRA, VAR_ACT["REG1"] <= 100)
    @objective(m, Min, objZ)
    return m
end

a = canonical_from_jump(toy())
@test length(a.rows) == 5 && length(a.cols) == 5
@test a.rows["EQG_COMBAL(REG1)"] == RowData(3.0, Inf)
@test a.coefs[("EQ_OBJ", "VAR_ACT(REG2)")] == -2.0
@test a.cols["VAR_NCAP(REG1)"].ub == 10.0
@test a.cols["OBJZ"].obj == 1.0 && a.objsense == :min

@test ispass(compare_lp(a, canonical_from_jump(toy())))
c = compare_lp(a, canonical_from_jump(toy(; cost=2.0 + 1e-6)))
@test !ispass(c) && c.counts[:coef_value] == 2
c = compare_lp(a, canonical_from_jump(toy(; cap=11.0)))
@test c.counts[:col_bounds] == 2
c = compare_lp(a, canonical_from_jump(toy(; extra_row=true)))
@test c.counts[:row_only_right] == 1
@test c.families["EXTRA"] == (0, 1) && c.families["EQG_COMBAL"] == (2, 2)

# A constant inside a constraint function is moved to the bounds.
m = Model(); @variable(m, x[1:1] >= 0); @constraint(m, c1, x[1] + 5 >= 7); @objective(m, Min, x[1])
@test canonical_from_jump(m).rows["C1"] == RowData(2.0, Inf)

# MPS round trip: the route used for GAMS CONVERT exports.
mktempdir() do dir
    path = joinpath(dir, "toy.mps")
    write_to_file(toy(), path)
    b = canonical_from_mps(path)
    @test ispass(compare_lp(a, b))
end

# Layer 3: an optimum found in one model, evaluated in the other.
m = toy(); set_optimizer(m, HiGHS.Optimizer); set_silent(m); optimize!(m)
@test termination_status(m) == OPTIMAL
x = Dict(jump_name_key(name(v)) => value(v) for v in all_variables(m))
ev = evaluate_point(a, x)
@test ev.feasible && isapprox(ev.objective, objective_value(m); rtol=1e-9)
x["VAR_ACT(REG1)"] = 1.0
ev = evaluate_point(a, x)
@test !ev.feasible
@test Set(first.(ev.worst_rows)) == Set(["EQG_COMBAL(REG1)", "EQ_OBJ"])
