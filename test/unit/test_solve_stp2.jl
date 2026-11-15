# The stepped (myopic) solve on a second crafted case, change 5 of docs/m15-plan.md (15 Nov 2026):
# demo12_step2, demo12 with TIMESTEP 20 and what demo12_step does not reach
# (reference/dd/demo12_step2): a given overlap (G_OVERLAP 15, solve.stp L44: three steps, 2005-2020,
# 2015-2030, 2030-2050), bounds on capacity (CAP_BND, L69, L96-98, L190-191, L217-219), cumulative
# and region-summed user constraints (UC_T_SUM, UC_R_SUM; L132-144, L155-181), dynamic user
# constraints (UC_T_SUCC, UC_DYNBND, PRC_DYNUC; L144-151, L183-185), cumulative bounds on flows and
# commodities (bnd_cum.mod in every step, L227) and bounds on cumulative costs (REG_CUMCST, L196).
#
# As test_solve_stp.jl does on demo12_step: from GAMS's ppm dump with TIMES.jl's own state up to
# solve.stp; then for each step the preparation, every set and parameter against GAMS's dump just
# after the SOLVE of that step (layer 1, 1e-9), the LP of the step against the LP GAMS solved
# (layer 2, 1e-9), and GAMS's levels loaded for the next step. Then `solve_stepped!` with HiGHS to
# the end of the run, with GAMS's levels between the steps and on TIMES.jl's own (layer 3 per
# step, 1e-6).

using TIMES: TimesModel, DumpData, layer1, coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!,
             prepret_decl!, eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!, bnd_data!, pp_qack_data!,
             pp_clean!, stp_init!, stp_step_prep!, stp_next!, stp_load_point!, gscalar, gmembers, gvalues,
             stp_model, stp_is_step, generate!, untranslated_families, solve_stepped!, stp_unported, stepped
using TIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, compare_lp, evaluate_point, jump_name_key
import TOML, JSON, JuMP, HiGHS

@testset "solve.stp: the steps of demo12_step2" begin
    p = "demo12_step2"
    vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"] if v["prefix"] == p)
    equ = DumpData(joinpath(FIXTURES, p * "_equ"))
    # the chain to the state solve.stp starts from; `at_equ` sees the state after eqmain.mod
    function chain(at_equ=identity)
        tm = TimesModel(joinpath(FIXTURES, p * "_ppm"); reduce=vx["reduce"], switches=vx["switches"])
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
    @test stepped(tm) && isempty(stp_unported(tm)) && isempty(untranslated_families(tm))
    stp_init!(tm)
    @testset "the first partition, with a given overlap (L43-57)" begin
        @test gscalar(tm, "YR_VL") == 20 && gscalar(tm, "G_OVERLAP") == 15      # L44: given, not FLOOR(20/2)
        @test years(tm, "SUBT") == ["2005", "2010", "2015", "2020"] && years(tm, "FORWARD") == ["2030", "2050"]
        # L69: a FX bound on capacity is a LO and an UP in a stepped run (REG2 solar, FX 3 in 2030)
        cb = gvalues(tm, "CAP_BND", 4)
        @test !any(k[4] == "FX" for k in keys(cb))
        @test cb[("REG2", "2030", "ELCRNSOL01", "LO")] == cb[("REG2", "2030", "ELCRNSOL01", "UP")] == 3
    end

    # SUBT, BACKWARD, MIYR_VL; with 15 years of overlap a step starts two periods back (L305)
    expect = [(["2005", "2010", "2015", "2020"], String[], 2025.0),
              (["2015", "2020", "2030"], ["2005", "2010"], 2040.0),
              (["2030", "2050"], ["2005", "2010", "2015", "2020"], 2052.0)]
    lpsize = [(2299, 3279, 13040), (1800, 2916, 11458), (1149, 2523, 8348)]     # rows, columns, nonzeros (GAMS, as run)
    # what the case reaches, per step (the values are GAMS's: every one is also compared by layer 1)
    reach = [(no_rvp=0, t_sum=20, t_each=24, t_succ=78, cumcst=5, uc_bnd=0),
             (no_rvp=10, t_sum=25, t_each=18, t_succ=61, cumcst=5, uc_bnd=66),
             (no_rvp=9, t_sum=30, t_each=12, t_succ=44, cumcst=3, uc_bnd=66)]
    tolr = 3e-6                                                                 # L173: %TOLR%
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
            r = vcat(layer1(tm, ref, own), layer1(tm, equ, same))
            foreach(d -> ispass(d) || println(p, " step $k: ", d, " ", d.examples), r)
            @test length(r) > 900 && all(ispass, r)                             # every set and parameter of the step's dump
            # --- what demo12_step does not reach ---
            x = reach[k]
            @test length(gmembers(tm, "NO_RVP", 3)) == x.no_rvp                 # L96-98, L218-219: capacity bounds of fixed periods
            @test length(gmembers(tm, "UC_T_SUM", 3)) == x.t_sum                # L132-137: cumulative UCs take the fixed periods
            @test length(gmembers(tm, "UC_T_EACH", 3)) == x.t_each
            @test length(gmembers(tm, "UC_T_SUCC", 3)) == length(gmembers(tm, "UC_RTSUC", 3)) == x.t_succ   # L144-148, L195
            @test length(gvalues(tm, "REG_CUMCST", 6)) == x.cumcst              # L196: an UP over fixed periods is removed
            ub = gvalues(tm, "UC_BND", 6)
            @test length(ub) == x.uc_bnd                                        # L155-171: only once a period is fixed
            @test k == 1 || Set(key[1] for key in keys(ub)) == Set(string.(1:6))    # every kind of RHS, UC_RHS to UC_RHSRTS
            cb = gvalues(tm, "CAP_BND", 4)
            # L190-191, in every step after the first: an UP is at least the level of the capacity
            # times 1+TOLR (new coal REG1 2020 is at its bound of 50 in step 1), a LO is scaled by 1-TOLR
            @test cb[("REG1", "2020", "ELCTNCOA01", "UP")] ≈ (k == 1 ? 50.0 : 50.0 * (1 + tolr)) rtol = 1e-12
            @test cb[("REG1", "2020", "ELCRNSOL01", "LO")] ≈ 2.0 * (1 - tolr)^(k - 1) rtol = 1e-12
            @test cb[("REG1", "2030", "ELCTNCOA01", "UP")] == 80                # above the level: unchanged
            # L173, L176: the RHS of a UC summed over regions and periods, UP relaxed in each step
            @test only(gvalues(tm, "UC_RHS", 2))[1] == ("CUM_GAS", "UP")
            @test gvalues(tm, "UC_RHS", 2)[("CUM_GAS", "UP")] ≈ (k == 1 ? 90.0 : k == 2 ? 90.00027 : 90.00054000081) rtol = 1e-12
            # L227, bnd_cum.mod again in every step (D41): the modifier of the first pass stays under
            # EOH, no modifier is left at the end of time, so the bound is applied unscaled
            fc = gvalues(tm, "FLO_CUM", 6)
            @test fc[("REG2", "MINGAS2", "GAS", "2010", "EOH", "N")] ≈ -0.2
            @test !any(key[5] == "2200" && key[6] == "N" for key in keys(fc))
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
end
