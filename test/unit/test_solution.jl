# Issue #97: write_solution writes the solution in the harness's dump layout (format version 1),
# and the harness's own reader reads it back. demo12 (CC BY 4.0), REDUCE off, solved with HiGHS.
import JSON, JuMP, HiGHS, TOML
using TIMES: TimesModel, generate!, write_solution
using TIMES.Reference: load_dump, read_symbol, SV_NONE

let fx = joinpath(@__DIR__, "..", "fixtures")
    spec = only(f for f in TOML.parsefile(joinpath(fx, "public_fixtures.toml"))["fixture"] if f["prefix"] == "demo12_off")
    tm = TimesModel(joinpath(fx, "demo12_off_presolve"); reduce=spec["reduce"],
                    switches=Dict{String,String}(k => string(v) for (k, v) in spec["switches"]))
    generate!(tm)
    m = tm.model
    JuMP.set_optimizer(m, HiGHS.Optimizer)
    JuMP.set_silent(m)
    JuMP.optimize!(m)
    @test JuMP.termination_status(m) == JuMP.OPTIMAL

    dir = mktempdir()
    write_solution(tm, dir; source="demo12_off", solver="HiGHS")
    d = load_dump(dir)
    man = JSON.parsefile(joinpath(dir, "manifest.json"))
    @test man["content"] == "solution"
    @test man["objective"] ≈ JuMP.objective_value(m)
    @test man["duals"] == true
    gams = JSON.parsefile(joinpath(fx, "demo12_off_solution.json"))["objval"]
    @test all(isapprox(man["objective"], v; rtol=1e-6) for v in values(gams))

    # every generated column and row is written, in creation order, with GAMS's domains and types
    ncol = sum(length(tm.vars.families[u].keys) for u in tm.vars.order)
    nrow = sum(length(tm.eqs.families[u].keys) for u in tm.eqs.order)
    @test sum(s.records for s in values(d.symbols) if s.kind === :variable) == ncol == JuMP.num_variables(m)
    @test sum(s.records for s in values(d.symbols) if s.kind === :equation) == nrow
    @test d.symbols["VAR_ACT"].domain == ["R", "ALLYEAR", "ALLYEAR", "P", "S"]
    @test d.symbols["VAR_ACT"].type == "positive"
    @test d.symbols["EQG_COMBAL"].type == "geq"

    # values read back equal the JuMP solution
    obj = read_symbol(d, "OBJZ")
    @test only(obj.values["level"]) ≈ JuMP.objective_value(m)
    act = read_symbol(d, "VAR_ACT")
    f = tm.vars.families["VAR_ACT"]
    @test act.keys == f.keys
    @test act.values["level"] == [JuMP.value(f.refs[k]) for k in f.keys]
    @test act.values["marginal"] == [JuMP.reduced_cost(f.refs[k]) for k in f.keys]
    @test all(act.values["lower"] .<= act.values["upper"])
    bal = read_symbol(d, "EQG_COMBAL")
    e = tm.eqs.families["EQG_COMBAL"]
    @test bal.keys == e.keys
    @test bal.values["marginal"] == [JuMP.dual(e.refs[k]) for k in e.keys]
    @test all(==(Inf), bal.values["upper"])
    # a minimisation: a >= row's dual (GAMS marginal) is never negative
    @test all(>=(-1e-9), bal.values["marginal"])
    @test all(==(SV_NONE), bal.special["level"])
end
