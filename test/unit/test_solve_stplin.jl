# The stepped (myopic) solve with OBJ LIN, change 6 of docs/m15-plan.md (15 Nov 2026):
# demo12_steplin, demo12 with objinv.dd (lead times, decommissioning, repeated investments), OBJ LIN
# and TIMESTEP 20 (reference/dd/demo12_steplin): three steps, 2005-2020, 2020-2030, 2050.
#
# With OBJ LIN (or OBJ ALT without OBLONG) %LINFLO% is 1, and a stepped run then changes the
# divisors of the investment costs in every step: solve.stp L104-107 saves OBJ_DIVI, OBJ_DIVIV and
# OBJ_DIVIII as STP_DIV before the loop, and the STP label of coef_alt.lin (L137-157, included at
# solve.stp L124) sets them to STP_DIV*(1+RTP_CAPVL), where RTP_CAPVL is the correction for the
# capacity that is available beyond the horizon of the step.
#
# As test_solve_stp2.jl does on demo12_step2: from GAMS's ppm dump with TIMES.jl's own state up to
# solve.stp; then for each step the preparation, every set and parameter against GAMS's dump just
# after the SOLVE of that step (layer 1, 1e-9), the LP of the step against the LP GAMS solved
# (layer 2, 1e-9), and GAMS's levels loaded for the next step. Then `solve_stepped!` with HiGHS to
# the end of the run, with GAMS's levels between the steps and on TIMES.jl's own (layer 3 per
# step, 1e-6). Last, OBJ ALT in a stepped run of several steps: GAMS divides by zero at
# coef_alt.lin L51 and skips the solve of the step (docs/discrepancies.md D42); TIMES.jl stops there.

using TIMES: TimesModel, DumpData, layer1, coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!,
             prepret_decl!, eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!, bnd_data!, pp_qack_data!,
             pp_clean!, stp_init!, stp_step_prep!, stp_next!, stp_load_point!, gscalar, gmembers, gvalues, gput_scalar!,
             stp_model, stp_is_step, generate!, untranslated_families, solve_stepped!, stp_unported, stepped, linflo
using TIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, compare_lp, evaluate_point, jump_name_key
import TOML, JSON, JuMP, HiGHS

@testset "solve.stp with OBJ LIN: the steps of demo12_steplin" begin
    p = "demo12_steplin"
    vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"] if v["prefix"] == p)
    equ = DumpData(joinpath(FIXTURES, p * "_equ"))
    # the chain to the state solve.stp starts from; `at_equ` sees the state after eqmain.mod
    function chain(at_equ=identity; switches=vx["switches"], before=identity)
        tm = TimesModel(joinpath(FIXTURES, p * "_ppm"); reduce=vx["reduce"], switches=switches)
        before(tm)
        foreach(f -> f(tm), (coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!, prepret_decl!,
                             eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!))
        at_equ(tm)
        foreach(f -> f(tm), (bnd_data!, pp_qack_data!))
        return tm
    end
    years(tm, name) = sort!([k[1] for k in gmembers(tm, name, 1)])
    skip(n) = startswith(n, "TJL_") || n == "Z"

    tm = chain() do tm
        @testset "ppm -> equ, every set and parameter" begin
            ppm_names = Set(i.name for i in values(tm.data.dump.symbols))
            names = sort([i.name for i in values(equ.dump.symbols) if i.kind in (:set, :parameter) && !skip(i.name) &&
                          (i.name in ppm_names || haskey(tm.data.sets, i.name) || haskey(tm.data.params, i.name))])
            r = layer1(tm, equ, names)
            foreach(d -> ispass(d) || println(p, " ppm -> equ: ", d, " ", d.examples), r)
            @test length(r) > 800 && all(ispass, r)
        end
    end
    @test stepped(tm) && linflo(tm) && isempty(stp_unported(tm)) && isempty(untranslated_families(tm))
    @test gscalar(tm, "ALTOBJ") == 3                                            # initmty.mod L423: OBJ LIN
    divs = ("OBJ_DIVI", "OBJ_DIVIV", "OBJ_DIVIII")
    before = Dict(n => copy(gvalues(tm, n, 3)) for n in divs)                   # as eqobjinv.mod and eqobjfix.mod leave them
    stp_init!(tm)
    @testset "the divisors saved before the loop (solve.stp L104-107)" begin
        sd = gvalues(tm, "STP_DIV", 4)
        # saved over T, the milestone years, only: the divisors of past years (42 records) are not saved
        ms = Set(years(tm, "MILESTONYR"))
        @test length(sd) == 780 && Set(k[1] for k in keys(sd)) == Set(["1", "2", "3"])
        @test sum(length, values(before)) == 822
        @test all(sd[(string(j), k...)] == x for (j, n) in enumerate(divs) for (k, x) in before[n] if k[2] in ms)
        @test sum(count(k -> k[2] in ms, keys(before[n])) for n in divs) == length(sd)
    end

    # SUBT, BACKWARD, MIYR_VL (the default overlap, TIMESTEP/2: a step starts where the one before ended)
    expect = [(["2005", "2010", "2015", "2020"], String[], 2025.0),
              (["2020", "2030"], ["2005", "2010", "2015"], 2040.0),
              (["2050"], ["2005", "2010", "2015", "2020", "2030"], 2052.0)]
    lpsize = [(2201, 3215, 12253), (1133, 2339, 7808), (540, 1959, 4808)]       # rows, columns, nonzeros (GAMS, as run)
    ncapvl = [396, 498, 586]                                                    # records of RTP_CAPVL (GAMS)
    # GAMS's RTP_CAPVL and OBJ_DIVI of REG2's gas pipeline, in the last period of each step
    gas = [("2015", -0.035973607429328425, 4.820131962853358),
           ("2030", -0.06281737871504045, 9.371826212849596),
           ("2050", -0.12916357433612002, 8.7083642566388)]
    # ... and of REG2's solar plant, the one process whose correction is positive (it raises the divisor)
    sol = [("2020", 0.03337284070342162), ("2030", 0.0184948641907179), ("2050", 2.419397968527626e-10)]
    for k in 1:3
        @testset "step $k" begin
            stp_step_prep!(tm)
            pp_clean!(tm)                                                       # solve.mod L12, inside the step
            @test years(tm, "SUBT") == expect[k][1] && years(tm, "BACKWARD") == expect[k][2]
            @test gscalar(tm, "MIYR_VL") == expect[k][3]
            ref = DumpData(joinpath(FIXTURES, p * "_step$k"))
            own = sort!([i.name for i in values(ref.dump.symbols) if i.kind in (:set, :parameter) && !skip(i.name)])
            same = [String(n) for n in ref.dump.manifest["tjl_same_as_equ"] if !skip(n)]
            @test isempty(intersect(own, same)) && all(n -> haskey(equ.dump.symbols, uppercase(n)), same)
            # the divisors and the correction are the step's own: compared against the dump of the step
            @test issubset(["RTP_CAPVL", "OBJ_DIVI", "OBJ_DIVIV", "OBJ_DIVIII"], own)
            r = vcat(layer1(tm, ref, own), layer1(tm, equ, same))
            foreach(d -> ispass(d) || println(p, " step $k: ", d, " ", d.examples), r)
            @test length(r) > 900 && all(ispass, r)                             # every set and parameter of the step's dump
            # --- coef_alt.lin L137-157 ---
            cv, sd = gvalues(tm, "RTP_CAPVL", 3), gvalues(tm, "STP_DIV", 4)
            @test length(cv) == ncapvl[k] && length(sd) == 780                  # STP_DIV stays as saved
            @test isempty(gvalues(tm, "PASTSUM", 3))                            # L160
            # L155-157, over RTP: each divisor of a milestone year is the saved one times 1+RTP_CAPVL, in
            # every step from the saved value; the divisors of past years stay as they were
            for (j, n) in enumerate(divs)
                d = gvalues(tm, n, 3)
                @test length(d) == length(before[n])
                @test all(haskey(sd, (string(j), key...)) ?
                          isapprox(x, sd[(string(j), key...)] * (1 + get(cv, key, 0.0)); rtol=1e-13) :
                          x == before[n][key] for (key, x) in d)
            end
            (t, c, d) = gas[k]
            key = ("REG2", t, "TU_GAS_REG2_REG1_01")
            @test cv[key] ≈ c rtol = 1e-12
            @test gvalues(tm, "OBJ_DIVI", 3)[key] ≈ d rtol = 1e-12
            @test cv[("REG2", sol[k][1], "ELCRNSOL01")] ≈ sol[k][2] rtol = 1e-9
            @test count(>(0), values(cv)) == 1
            # --- the LP of the step, layer 2 ---
            st = stp_model(tm)
            @test stp_is_step(st) && isempty(untranslated_families(st))
            generate!(st)
            mdir = joinpath(FIXTURES, p * "_step$(k)_matrix")
            lp = canonical_from_jump(st.model)
            c = compare_lp(lp, canonical_from_dump(joinpath(mdir, "matrix"), joinpath(mdir, "dictmap")))
            ispass(c) || (println(p, " step $k, layer 2: ", c); foreach(e -> println("   ", e), c.examples))
            @test ispass(c)
            @test (length(lp.rows), length(lp.cols), length(lp.coefs)) == lpsize[k]
            stp_load_point!(tm, ref)
            stp_next!(tm)
        end
    end
    @test isempty(gmembers(tm, "SUBT", 1))                                      # WHILE(CARD(SUBT), ...) ends

    @testset "solve_stepped!: the run to its end, HiGHS ($(own ? "TIMES.jl's own levels" : "GAMS's levels") between the steps)" for own in (false, true)
        gams = [JSON.parsefile(joinpath(FIXTURES, p * "_step$k", "manifest.json"))["tjl_step_solve"] for k in 1:3]
        rel(a, b) = abs(a - b) / max(1.0, abs(b))
        tmx = chain()
        hook = function (tmx, st, info)
            own && return
            k = info.step
            # GAMS's levels between the steps: the LP of each step is the LP GAMS solved (layer 2) ...
            mdir = joinpath(FIXTURES, p * "_step$(k)_matrix")
            ref = canonical_from_dump(joinpath(mdir, "matrix"), joinpath(mdir, "dictmap"))
            c = compare_lp(canonical_from_jump(st.model), ref)
            ispass(c) || (println(p, " step $k, layer 2 in the run: ", c); foreach(e -> println("   ", e), c.examples))
            @test ispass(c)
            # ... and HiGHS's optimum is feasible in it at 1e-6, with GAMS/CPLEX's objective (layer 3)
            e = evaluate_point(ref, Dict(jump_name_key(JuMP.name(v)) => JuMP.value(v) for v in JuMP.all_variables(st.model)))
            @test e.feasible && isempty(e.missing_columns) && rel(e.objective, gams[k]["objective"]) <= 1e-6
            stp_load_point!(tmx, DumpData(joinpath(FIXTURES, p * "_step$k")))
        end
        # no "threads" attribute: HiGHS fixes its thread count at the first solve of a process
        steps = solve_stepped!(tmx, HiGHS.Optimizer; attributes=("time_limit" => 600.0,), step_hook=hook)
        @test [s.periods for s in steps] == [x[1] for x in expect]
        @test [(s.rows, s.columns) for s in steps] == [(g["rows"], g["columns"]) for g in gams]
        @test all(s.status == "OPTIMAL" for s in steps) && [g["model_status"] for g in gams] == [1, 1, 1]
        # layer 3 per step, 1e-6: the objective of each step against GAMS/CPLEX's of that step
        for k in 1:3
            rel(steps[k].objective, gams[k]["objective"]) <= 1e-6 ||
                println(p, " step $k, objective: ", steps[k].objective, " vs GAMS/CPLEX ", gams[k]["objective"])
            @test rel(steps[k].objective, gams[k]["objective"]) <= 1e-6
        end
        # ... and at the end, against the final objective of every GAMS solver (CPLEX, HiGHS)
        fin = gams[3]["final_objective"]
        @test Set(keys(fin)) == Set(["CPLEX", "HIGHS"]) && all(rel(steps[3].objective, x) <= 1e-6 for x in values(fin))
    end

    # OBJ ALT without OBLONG is LINFLO too, with OBJ_ALTV (coef_alt.lin L49-53, |ALTOBJ| = 2) on top.
    # In a stepped run the STP call computes OBJ_ALTV again with Y_EOH cut to the horizon of the step:
    # for a period beyond it the sum of L51 is empty, GAMS 54.6.1 reports "division by zero" and skips
    # the SOLVE of the step (seen on demo12 with objinv.dd, OBJ ALT and TIMESTEP 20: steps 1 and 2;
    # docs/discrepancies.md D42). TIMES.jl stops at the same statement. The state before solve.stp is
    # the one of OBJ LIN but for ALTOBJ (2, initmty.mod L422; ppmain.mod tests ALTOBJ only for
    # nonzero and for < 2), so the fixture of OBJ LIN serves, with the switch and the scalar set.
    @testset "OBJ ALT in a stepped run of several steps: GAMS's division by zero (coef_alt.lin L51)" begin
        tma = chain(; switches=merge(vx["switches"], Dict("OBJ" => "ALT")), before=tm -> gput_scalar!(tm, "ALTOBJ", 2.0))
        @test stepped(tma) && linflo(tma) && isempty(stp_unported(tma))
        @test length(gvalues(tma, "OBJ_ALTV", 2)) == 12                         # before the loop: every period has years in the horizon
        stp_init!(tma)
        err = try
            stp_step_prep!(tma)
            nothing
        catch e
            e
        end
        @test err isa DomainError && occursin("coef_alt.lin L51", sprint(showerror, err))
    end
end
