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
# The variable bounds and the equations of a step are change 3; model generation still refuses
# the run (test_stepped.jl).

using TIMES: TimesModel, DumpData, layer1, coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!,
             prepret_decl!, eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!, bnd_data!, pp_qack_data!,
             pp_clean!, stp_init!, stp_step_prep!, stp_next!, stp_load_point!, stp_level, stp_marginal, _stp_fx!,
             gscalar, gmembers, gvalues, gput_scalar!, gset, var_uc, UnportedError
using TIMES.Reference: ispass
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
    end

    expect = [(["2005", "2010", "2015", "2020"], String[], 2025.0),
              (["2020", "2030"], ["2005", "2010", "2015"], 2040.0),
              (["2050"], ["2005", "2010", "2015", "2020", "2030"], 2052.0)]
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
            stp_load_point!(tm, ref)
            @test !isempty(stp_level(tm, "VAR_NCAP", 3)) && !isempty(stp_marginal(tm, "VAR_CUMFLO", 5))
            stp_next!(tm)
            @test gscalar(tm, "PRESOL") == 0
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
end
