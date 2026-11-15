# The stepped (myopic) solve, change 2 of docs/m15-plan.md (14 Nov 2026): the partition of the
# horizon into steps and the data each step prepares (solve.stp L43-196, L217, L222-227,
# L288-289, L295-319; clearsol.stp; coef_alt.lin STP; eqobsalv.mod STP), on the crafted case
# demo12_step (demo12 with TIMESTEP 20: three steps, 2005-2020, 2020-2030, 2050).
#
# From GAMS's ppm dump with TIMES.jl's own state up to solve.stp, then for each step, in GAMS's
# order: the preparation of the step, pp_clean.mod (solve.mod L12), every set and parameter
# against GAMS's dump just after the SOLVE of that step (harness 0.3.4, steps/<k>/final) at 1e-9,
# GAMS's levels and marginals of that step loaded, and the statements after the SOLVE. The next
# step is so prepared on GAMS's own point: a difference in one step cannot hide in the next.
#
# The fixture of a step holds what differs from the equ fixture and lists the rest
# (scripts/make_step_fixture.jl): those are compared against the equ fixture.
# Not compared: Z (err_stat.mod L56-65 sets it after the SOLVE) and the harness's TJL_ symbols.
#
# Change 3 (the equations over the periods of the step, maindrv.mod L38-40; the bounds of a step,
# solve.stp L193-233, L267-281, L319 with bndmain.mod): in the same loop, the LP of each step
# (`stp_model`, `generate!`) against the LP GAMS solved in that step (steps/<k>/matrix, CONVERT)
# at 1e-9: rows, columns, coefficients, right-hand sides and bounds. The bounds of step k+1 fix
# the periods of step k at GAMS's levels, loaded from the step's fixture. The run as a whole is
# still refused (test_stepped.jl) until the loop with the SOLVE, change 4.

using TIMES: TimesModel, DumpData, layer1, coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!,
             prepret_decl!, eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!, bnd_data!, pp_qack_data!,
             pp_clean!, stp_init!, stp_step_prep!, stp_next!, stp_load_point!, stp_level, stp_marginal, _stp_fx!,
             gscalar, gmembers, gvalues, gput_scalar!, gput!, gset, var_uc, UnportedError,
             stp_model, stp_is_step, stp_bounds, bnd_ucw!, BoundTable, bounds, generate!, untranslated_families
using TIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, compare_lp
import TOML

@testset "solve.stp: the steps of demo12_step" begin
    p = "demo12_step"
    vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"] if v["prefix"] == p)
    function chain(switches)
        tm = TimesModel(joinpath(FIXTURES, p * "_ppm"); reduce=vx["reduce"], switches=switches)
        foreach(f -> f(tm), (coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!, prepret_decl!,
                             eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!, bnd_data!, pp_qack_data!))
        return tm
    end
    years(tm, name) = sort!([k[1] for k in gmembers(tm, name, 1)])

    @testset "controls" begin
        sw = Dict{String,String}(vx["switches"])
        plain = TimesModel(joinpath(FIXTURES, p * "_ppm"); switches=Dict("OBJ" => "MOD"))
        @test_throws ArgumentError stp_init!(plain)                             # not a stepped run
        @test_throws ArgumentError stp_model(plain)
        @test_throws ArgumentError stp_model(chain(sw))                         # no step prepared yet
        # initmty.mod L446-447: a stepped run sets VAR_UC to YES
        @test var_uc(TimesModel(joinpath(FIXTURES, p * "_ppm"); switches=Dict("OBJ" => "MOD", "TIMESTEP" => "20")))
        for extra in ("FIXBOH" => "2010", "STAGES" => "YES", "SPINES" => "YES", "SENSIS" => "YES", "CLI" => "YES")
            tmx = TimesModel(joinpath(FIXTURES, p * "_ppm"); reduce=vx["reduce"], switches=merge(sw, Dict(extra)))
            @test_throws UnportedError stp_init!(tmx)
        end
    end

    @testset "FX bounds copied to LO and UP (solve.stp L69-75)" begin
        bd, bdneq = ["LO", "FX", "UP"], Set(["LO", "UP"])
        v = Dict(("A", "FX") => 2.0, ("A", "UP") => 9.0, ("B", "LO") => 1.0, ("C", "FX") => 0.0, ("D", "FX") => 5.0,
                 ("B", "N") => 3.0)
        _stp_fx!(k -> k[1] != "D", v, bd, bdneq)
        # an EPS is copied as an EPS; D is outside the domain; N is not in BD
        @test v == Dict(("A", "LO") => 2.0, ("A", "UP") => 2.0, ("B", "LO") => 1.0, ("C", "LO") => 0.0, ("C", "UP") => 0.0,
                        ("D", "FX") => 5.0, ("B", "N") => 3.0)
    end

    tm = chain(vx["switches"])
    equ = DumpData(joinpath(FIXTURES, p * "_equ"))
    stp_init!(tm)
    @testset "the first partition (L43-57)" begin
        @test gscalar(tm, "YR_VL") == 20 && gscalar(tm, "G_OVERLAP") == 10      # FLOOR(20/2)
        @test gscalar(tm, "YR_V1") == 2005 && gscalar(tm, "PRESOL") == 1 && gscalar(tm, "MY_FYEAR") == 0
        @test years(tm, "SUBT") == ["2005", "2010", "2015", "2020"]
        @test isempty(gmembers(tm, "BACKWARD", 1)) && years(tm, "FORWARD") == ["2030", "2050"]
        @test isempty(gvalues(tm, "NO_RT", 2)) && isempty(gvalues(tm, "REG_FIXT", 1))
        @test length(gvalues(tm, "STP_UCT", 4)) == 24                           # L103: UC_T_EACH saved
        @test ("UC_RNW-PP_LOW", "IMPEXP") in gmembers(tm, "UC_RN", 2)           # L78-92: a negative coefficient
        @test isempty(stp_level(tm, "VAR_NCAP", 3))                             # the run starts from no point
        @test stp_bounds(tm) isa BoundTable && !haskey(tm.cache, "BOUNDS")      # maindrv.mod L92: the run's table
    end

    expect = [(["2005", "2010", "2015", "2020"], String[], 2025.0),
              (["2020", "2030"], ["2005", "2010", "2015"], 2040.0),
              (["2050"], ["2005", "2010", "2015", "2020", "2030"], 2052.0)]
    lpsize = [(2201, 3183, 12216), (1133, 2305, 7782), (540, 1949, 4756)]      # rows, columns, nonzeros (GAMS, as run)
    nstep = 0
    while !isempty(gmembers(tm, "SUBT", 1)) && nstep < length(expect)
        nstep += 1
        k = nstep
        @testset "step $k" begin
            stp_step_prep!(tm)
            pp_clean!(tm)                                                       # solve.mod L12, inside the step
            @test years(tm, "SUBT") == expect[k][1] && years(tm, "BACKWARD") == expect[k][2]
            @test gscalar(tm, "MIYR_VL") == expect[k][3]
            ref = DumpData(joinpath(FIXTURES, p * "_step$k"))
            skip(n) = startswith(n, "TJL_") || n == "Z"
            own = sort!([i.name for i in values(ref.dump.symbols) if i.kind in (:set, :parameter) && !skip(i.name)])
            same = [String(n) for n in ref.dump.manifest["tjl_same_as_equ"] if !skip(n)]
            @test isempty(intersect(own, same)) && all(n -> haskey(equ.dump.symbols, uppercase(n)), same)
            r = vcat(layer1(tm, ref, own), layer1(tm, equ, same))
            foreach(d -> ispass(d) || println(p, " step $k: ", d, " ", d.examples), r)
            @test length(r) > 900 && all(ispass, r)                             # 957: every set and parameter of the step's dump
            @test (k == 1) == isempty(gvalues(tm, "UC_BND", 6))                 # L155: only once a period is fixed
            # --- change 3: the LP of the step, layer 2 ---
            st = stp_model(tm)
            @test stp_is_step(st) && !stp_is_step(tm) && st.data === tm.data
            @test isempty(untranslated_families(st)) && !isempty(untranslated_families(tm))
            generate!(st)
            mdir = joinpath(FIXTURES, p * "_step$(k)_matrix")
            lp = canonical_from_jump(st.model)
            c = compare_lp(lp, canonical_from_dump(joinpath(mdir, "matrix"), joinpath(mdir, "dictmap")))
            ispass(c) || (println(p, " step $k, layer 2: ", c); foreach(e -> println("   ", e), c.examples))
            @test ispass(c)
            @test (length(lp.rows), length(lp.cols), length(lp.coefs)) == lpsize[k]
            bt = stp_bounds(tm)
            fwd, bwd = Set(years(tm, "FORWARD")), Set(years(tm, "BACKWARD"))
            act = bt.recs["VAR_ACT"]
            fixed0(x) = x == (0.0, 0.0)
            # L268 with L115: what an earlier vintage does in a pending period is fixed at zero; V holds no
            # pending period, so a pending vintage's own records are not reached
            @test all(fixed0(b) for (key, b) in act if key[3] in fwd && !(key[2] in fwd))
            @test (k < 3) == any(key[3] in fwd && !(key[2] in fwd) for key in keys(act))
            # L270 is a comment: no trade of a pending period is fixed
            @test !any(key[3] in fwd for key in keys(get(bt.recs, "VAR_IRE", Dict())))
            # L200, L214: the periods of the steps before are fixed at the levels GAMS found
            ncap, actl = stp_level(tm, "VAR_NCAP", 3), stp_level(tm, "VAR_ACT", 5)
            @test all(b[1] == b[2] == max(0.0, get(ncap, key, 0.0)) for (key, b) in bt.recs["VAR_NCAP"] if key[2] in bwd)
            @test all(b[1] == b[2] == get(actl, key, 0.0) for (key, b) in act if key[3] in bwd)
            @test (k == 1) || any(b[1] > 0 for (key, b) in act if key[3] in bwd)
            @test (k == 1) || count(key -> key[2] in bwd, keys(bt.recs["VAR_NCAP"])) == length(bwd) * length(gset(tm, "RP"))
            # L215-216: the capacity of a fixed period is free again
            @test !any(key[2] in bwd && b != (0.0, Inf) && !(key in gset(tm, "NO_RVP")) for (key, b) in get(bt.recs, "VAR_CAP", Dict()))
            stp_load_point!(tm, ref)
            @test !isempty(stp_level(tm, "VAR_NCAP", 3)) && !isempty(stp_marginal(tm, "VAR_CUMFLO", 5))
            # (the fixture is the run with REDUCE: GAMS's levels of VAR_IRE are all zero in it, so the
            # store holds none; the reference without REDUCE has them, and its LPs are compared by hand)
            @test !isempty(stp_level(tm, "VAR_ACT", 5)) && !isempty(stp_level(tm, "VAR_FLO", 6))
            nire = length(get(bt.recs, "VAR_IRE", Dict()))
            stp_next!(tm)
            @test gscalar(tm, "PRESOL") == 0
            # L319, bndmain.mod with 1: VAR_ACT starts again from the bounds of the data (no fix at a
            # level is left), VAR_IRE keeps its fixes
            @test !any(b[1] == b[2] != 0 for b in values(get(bt.recs, "VAR_ACT", Dict())))
            @test length(get(bt.recs, "VAR_IRE", Dict())) == nire && (k == 1 || nire > 0)
        end
    end
    @testset "after the last step (L303-314)" begin
        @test nstep == 3 && isempty(gmembers(tm, "SUBT", 1))                    # WHILE(CARD(SUBT), ...) ends
        @test gscalar(tm, "YR_V1") == Inf                                       # SMIN over nothing
        @test length(gmembers(tm, "UC_T_EACH", 3)) == 24                        # L314: restored from STP_UCT
        @test issetequal(gmembers(tm, "MODLYEAR", 1), gset(equ, "MODLYEAR").keys)   # L311: V(T) = YES
        @test_throws ArgumentError stp_step_prep!(tm)                           # no step is left
    end

    @testset "a given overlap (L44, L305)" begin
        tm2 = chain(vx["switches"])
        gput_scalar!(tm2, "G_OVERLAP", 5.0)
        stp_init!(tm2)
        @test gscalar(tm2, "G_OVERLAP") == 5
        stp_step_prep!(tm2); stp_next!(tm2)
        # Z = B(2030) = 2026; YR_V1 = the first of 2010, 2015, 2020, 2030 at or after 2021 = 2030; Z = 2050
        @test gscalar(tm2, "YR_V1") == 2030 && years(tm2, "SUBT") == ["2030"]
    end

    @testset "the resets of bnd_ucv.mod L24-25" begin
        tm3 = chain(vx["switches"])
        bt = BoundTable()
        rec(var) = get!(() -> Dict{Tuple,Tuple{Float64,Float64}}(), bt.recs, var)
        rec("VAR_UC")[("NOUC",)] = (1.0, 5.0)                   # no %12: both bounds reset
        rec("VAR_UCR")[("NOUC", "REG1")] = (1.0, 5.0)           # $UC_R_EACH(R,UC_N) on the lower bound: not a member
        rec("VAR_UCRT")[("NOUC", "REG1", "2005")] = (1.0, 5.0)  # $UC_T_EACH(R,UC_N,TT): not a member
        rec("VAR_UCRT")[("UC_RNW-PP_LOW", "REG1", "2005")] = (1.0, 5.0)
        @test ("REG1", "UC_RNW-PP_LOW", "2005") in gset(tm3, "UC_T_EACH")
        bnd_ucw!(bt, tm3)                                       # an ordinary run: no reset
        @test bt.recs["VAR_UC"][("NOUC",)] == (1.0, 5.0)
        bnd_ucw!(bt, tm3; reset=true)
        @test bt.recs["VAR_UC"][("NOUC",)] == (-Inf, Inf)
        @test bt.recs["VAR_UCR"][("NOUC", "REG1")] == (1.0, Inf)
        @test bt.recs["VAR_UCRT"][("NOUC", "REG1", "2005")] == (1.0, Inf)
        b = bt.recs["VAR_UCRT"][("UC_RNW-PP_LOW", "REG1", "2005")]
        @test b != (1.0, 5.0) && b[1] != 1.0                    # reset, then the bounds of UC_RHSRT
    end

    # Translated as GAMS writes it, not checked against GAMS (no case with blending is stepped):
    # L232 sets the levels of the step's own periods (RT_PP, L114) to zero, L233 fixes the periods
    # already solved at their levels, and the fix of the pending periods at zero (L281) is not
    # lifted when they become a step's own (no other statement sets a bound of VAR_BLND).
    @testset "blending in a stepped run (L232-233, L281), as written" begin
        tm4 = chain(vx["switches"])
        gput!(tm4, "BLE_OPR", Set([("REG1", "BLEX", "OPRX")]))
        stp_init!(tm4)
        stp_step_prep!(tm4)
        bt = stp_bounds(tm4)
        @test bt.recs["VAR_BLND"] == Dict(("REG1", "2030", "BLEX", "OPRX") => (0.0, 0.0),
                                          ("REG1", "2050", "BLEX", "OPRX") => (0.0, 0.0))
        stp_level(tm4, "VAR_BLND", 4)[("REG1", "2005", "BLEX", "OPRX")] = 7.0
        stp_level(tm4, "VAR_BLND", 4)[("REG1", "2020", "BLEX", "OPRX")] = 3.0
        stp_next!(tm4)
        stp_step_prep!(tm4)
        @test years(tm4, "SUBT") == ["2020", "2030"]
        @test stp_level(tm4, "VAR_BLND", 4) == Dict(("REG1", "2005", "BLEX", "OPRX") => 7.0)   # L232: 2020 is the step's own
        @test bt.recs["VAR_BLND"][("REG1", "2005", "BLEX", "OPRX")] == (7.0, 7.0)       # L233: at the level
        @test bt.recs["VAR_BLND"][("REG1", "2030", "BLEX", "OPRX")] == (0.0, 0.0)       # L281 of step 1 stays
        @test !haskey(bt.recs["VAR_BLND"], ("REG1", "2020", "BLEX", "OPRX"))
    end
end
