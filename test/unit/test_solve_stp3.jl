# The stepped (myopic) solve on a third crafted case, change 7 of docs/m15-plan.md (15 Nov 2026):
# demo12_step3, demo12 with TIMESTEP 20 (the default overlap: three steps, 2005-2020, 2020-2030,
# 2050), the DD files of five other crafted cases and one of its own (reference/dd/demo12_step3),
# for the variables that demo12_step and demo12_step2 do not have:
#   uc.dd     dispatching and unit commitment: VAR_UPS, VAR_UPT, VAR_UDP (solve.stp L205-207)
#   blnd.dd   refinery blending: VAR_BLND (L232-233, L281)
#   ips.dd    an inter-period store; ls.dd  load shifting: VAR_SIN, VAR_SOUT (L203-204, L271-272)
#   step3.dd  costs on the flows of those two storage processes, so that VAR_SIN and VAR_SOUT of the
#             periods already solved are in the objective row of the later steps (eqobjvar.mod L88-91)
#   refit.dd  retirement and refits: VAR_RCAP, VAR_SCAP (L220)
#
# As test_solve_stp2.jl does on demo12_step2: from GAMS's ppm dump with TIMES.jl's own state up to
# solve.stp; then for each step the preparation, every set and parameter against GAMS's dump just
# after the SOLVE of that step (layer 1, 1e-9), the LP of the step against the LP GAMS solved
# (layer 2, 1e-9), and GAMS's levels loaded for the next step. Then `solve_stepped!` with HiGHS to
# the end of the run, with GAMS's levels between the steps and on TIMES.jl's own (layer 3 per
# step, 1e-6).
#
# The case also settles the question U7 of docs/discrepancies.md (now D43): L281 fixes the blending
# variables of the pending periods at zero and no statement lifts that fix, in GAMS itself: in the
# LP GAMS solved in step 2 every VAR_BLND of 2030, a period of that step, is fixed at zero, and in
# step 3 every one of 2050. TIMES.jl follows the code.

using TIMES: TimesModel, DumpData, layer1, coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!,
             prepret_decl!, eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!, bnd_data!, pp_qack_data!,
             pp_clean!, stp_init!, stp_step_prep!, stp_next!, stp_load_point!, gscalar, gmembers,
             stp_model, stp_is_step, generate!, untranslated_families, solve_stepped!, stp_unported, stepped
using TIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, compare_lp, evaluate_point, jump_name_key
import TOML, JSON, JuMP, HiGHS

@testset "solve.stp: the steps of demo12_step3" begin
    p = "demo12_step3"
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
    fam(n) = String(first(split(n, '(')))
    # the columns of one variable in an LP: how many, how many fixed at zero, how many fixed at another value
    function kinds(lp, f)
        cs = [d for (c, d) in lp.cols if fam(c) == f]
        return (length(cs), count(d -> d.lb == d.ub == 0, cs), count(d -> d.lb == d.ub != 0, cs))
    end
    nrows(lp, f) = count(r -> fam(r) == f, keys(lp.rows))
    blnd(lp, year) = [d for (c, d) in lp.cols if fam(c) == "VAR_BLND" && split(c, ',')[2] == year]

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
    @test gscalar(tm, "YR_VL") == 20 && gscalar(tm, "G_OVERLAP") == 10          # L44: FLOOR(20/2)

    # SUBT, BACKWARD, MIYR_VL
    expect = [(["2005", "2010", "2015", "2020"], String[], 2025.0),
              (["2020", "2030"], ["2005", "2010", "2015"], 2040.0),
              (["2050"], ["2005", "2010", "2015", "2020", "2030"], 2052.0)]
    lpsize = [(2867, 3927, 15165), (1415, 2857, 9424), (649, 2435, 5620)]       # rows, columns, nonzeros (GAMS, as run)
    # What the case reaches, per step, counted in the LP GAMS solved (as run): the columns of each
    # variable, those fixed at zero and those fixed at another value. Layer 2 compares every one.
    reach = [(blnd=(36, 0, 0), ups=(168, 0, 0), upt=(72, 0, 0), udp=(88, 0, 0), scap=(27, 1, 0), sin=(46, 0, 0),
              sout=(78, 0, 0), rcap=(29, 1, 0)),
             (blnd=(36, 26, 1), ups=(54, 11, 1), upt=(72, 54, 0), udp=(46, 24, 0), scap=(30, 4, 4), sin=(60, 33, 0),
              sout=(76, 31, 2), rcap=(30, 1, 0)),
             (blnd=(39, 38, 1), ups=(16, 15, 1), upt=(72, 72, 0), udp=(32, 32, 0), scap=(31, 13, 8), sin=(73, 60, 0),
              sout=(81, 58, 2), rcap=(22, 2, 0))]
    # the rows of the equation families the first two stepped cases have none of
    rows = [(lblnd=7, gblnd=8, eblnd=3, stgips=16, stgaux=14, slsift=80, refit=12, cumret=17, lscap=6),
            (lblnd=4, gblnd=6, eblnd=2, stgips=11, stgaux=11, slsift=40, refit=13, cumret=17, lscap=7),
            (lblnd=2, gblnd=3, eblnd=1, stgips=5, stgaux=5, slsift=20, refit=5, cumret=17, lscap=7)]
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
            # --- the LP of the step, layer 2 ---
            st = stp_model(tm)
            @test stp_is_step(st) && isempty(untranslated_families(st))
            generate!(st)
            mdir = joinpath(FIXTURES, p * "_step$(k)_matrix")
            lp = canonical_from_jump(st.model)
            glp = canonical_from_dump(joinpath(mdir, "matrix"), joinpath(mdir, "dictmap"))
            c = compare_lp(lp, glp)
            ispass(c) || (println(p, " step $k, layer 2: ", c); foreach(e -> println("   ", e), c.examples))
            @test ispass(c)
            @test (length(lp.rows), length(lp.cols), length(lp.coefs)) == lpsize[k]
            # --- what demo12_step and demo12_step2 do not reach, in TIMES.jl's LP and in GAMS's ---
            x, y = reach[k], rows[k]
            for l in (lp, glp)
                @test kinds(l, "VAR_UPS") == x.ups && kinds(l, "VAR_UPT") == x.upt && kinds(l, "VAR_UDP") == x.udp   # L205-207
                @test kinds(l, "VAR_SCAP") == x.scap && kinds(l, "VAR_RCAP") == x.rcap                               # L220
                @test kinds(l, "VAR_SIN") == x.sin && kinds(l, "VAR_SOUT") == x.sout                                 # L203-204, L271-272
                @test kinds(l, "VAR_BLND") == x.blnd                                                                 # L232-233, L281
                if k > 1                    # L204: a storage flow of a period already solved, fixed at its level
                    s = l.cols["VAR_SOUT(REG1,2005,2005,STKOIL1,OIL,ANNUAL)"]
                    @test s.lb == s.ub
                    @test s.lb ≈ 16.166975474632434 rtol = 1e-12
                end
                @test (nrows(l, "EQL_BLND"), nrows(l, "EQG_BLND"), nrows(l, "EQE_BLND")) == (y.lblnd, y.gblnd, y.eblnd)
                @test (nrows(l, "EQ_STGIPS"), nrows(l, "EQ_STGAUX"), nrows(l, "EQ_SLSIFT")) == (y.stgips, y.stgaux, y.slsift)
                @test (nrows(l, "EQL_REFIT"), nrows(l, "EQ_CUMRET"), nrows(l, "EQL_SCAP")) == (y.refit, y.cumret, y.lscap)
                # D43: blending. Step 1: every column is free. Step 2: the columns of 2020, solved again,
                # are free; those of 2030, the step's new period, are still fixed at zero (L281 of step 1,
                # never lifted); the periods already solved are fixed at their levels (L233), one of them
                # not zero. Step 3: every column of 2050, the step's only period, is fixed at zero.
                free(d) = d.lb == 0 && d.ub == Inf
                zero(d) = d.lb == d.ub == 0
                if k == 1
                    @test all(free, blnd(l, "2005")) && all(free, blnd(l, "2020")) && isempty(blnd(l, "2030"))
                elseif k == 2
                    @test length(blnd(l, "2020")) == length(blnd(l, "2030")) == 9
                    @test all(free, blnd(l, "2020")) && all(zero, blnd(l, "2030"))
                    b = l.cols["VAR_BLND(REG1,2010,TRAGSL,BIO)"]
                    @test b.lb == b.ub
                    @test b.lb ≈ 1209.0790800000007 rtol = 1e-12
                else
                    @test length(blnd(l, "2050")) == 9 && all(zero, blnd(l, "2050"))
                    @test all(zero, blnd(l, "2020")) && all(zero, blnd(l, "2030"))
                end
            end
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
