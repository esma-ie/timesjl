# M1.2 (5): coef_alt.lin L11-87, L159-161 (v4.9.7), as coefmain.mod L26
# calls it. Layer 1 on TIMES_Demo demo12 (OBJ MOD: %CTST% **0) against its
# coef dump, and on five crafted switch settings against coef_alt.lin run by
# GAMS itself (scripts/make_coef_alt_unit.jl): OBJ AUTO without OBLONG (the
# L59 exit, as OTCGEN and OTNYC take it), OBJ ALT, OBJ LIN, OBLONG with ALT,
# and INT_DEFAULT('PASTI') with past lead times (L69 recomputes a past lead
# time from the discount factor: 3 becomes 3.159 at 5%).

using TIMES: TimesModel, DumpData, coef_alt!, stepped, later_overwrites, layer1, linflo, linacc, gparam, gset
using TIMES.Reference: ispass

isdefined(@__MODULE__, :PPM_DEMO12) || (const PPM_DEMO12 = joinpath(FIXTURES, "demo12_off_ppm"))
isdefined(@__MODULE__, :COEF_DEMO12) || (const COEF_DEMO12 = joinpath(FIXTURES, "demo12_off_coef"))
include("coef_obj_case.jl")
include("coef_alt_case.jl")

@testset "coef_alt switches (L40-44)" begin
    mk(sw) = TimesModel(PPM_DEMO12; switches=sw)
    @test !linflo(mk(Dict("OBJ" => "AUTO", "OBLONG" => "YES"))) && !linacc(mk(Dict("OBJ" => "AUTO", "OBLONG" => "YES")))
    @test linflo(mk(Dict("OBJ" => "ALT"))) && !linacc(mk(Dict("OBJ" => "ALT")))
    @test linflo(mk(Dict("OBJ" => "LIN"))) && linacc(mk(Dict("OBJ" => "LIN")))
    @test !linflo(mk(Dict("OBJ" => "ALT", "OBLONG" => "YES"))) && linacc(mk(Dict("OBJ" => "ALT", "OBLONG" => "YES")))
    # L81 ($IF SET TIMESTEP): a stepped run; its coefficient stage is checked in test_stepped.jl
    @test stepped(mk(Dict("TIMESTEP" => "20"))) && !stepped(mk(Dict("OBJ" => "ALT")))
end

@testset "coef_alt layer 1, TIMES_Demo demo12 (OBJ MOD)" begin
    tm = coef_obj_start(PPM_DEMO12)                  # coef_cpt, coef_nio, coef_ptr, coef_obj
    coef_obj!(tm)
    @test isempty(gparam(tm, "COEF_CPT"))           # coef_cpt.mod computes none under %CTST% **0
    coef_alt!(tm)
    r = layer1(tm, DumpData(COEF_DEMO12), COEF_ALT_OUTPUTS; exclude=later_overwrites(tm))
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test all(ispass, r)
    @test length(gparam(tm, "COEF_CPT")) == 3650
    # L35, L37: 1 at the milestone year, every pulse in [0, 1], and the pulses of
    # neighbouring periods are complementary in the years they share
    tp = gparam(tm, "TPULSE")
    @test all(0 <= v <= 1 for v in values(tp.values))
    @test tp[("2005", "2005")] == 1.0 && tp[("2010", "2010")] == 1.0
    @test all(tp[("2005", y)] + tp[("2010", y)] ≈ 1.0 for y in ("2006", "2007", "2008", "2009"))
    # L67, L70: R_DF = 1/(1+G_DRATE) at the model years, RB = B
    @test gparam(tm, "R_DF")[("REG1", "2010")] ≈ 1 / 1.05
    @test gparam(tm, "RB")[("REG1", "2010")] == gparam(tm, "B")[("2010",)]
    @test isempty(gparam(tm, "PASTSUM")) && isempty(gset(tm, "YK1")) && isempty(gparam(tm, "RTP_CAPVL"))
end

@testset "coef_alt against GAMS on crafted switch settings" begin
    for (name, _) in COEF_ALT_CASES
        tm = coef_alt_start(PPM_DEMO12, name)
        coef_alt!(tm)
        # "plain" ends at L59, before L66 clears MY_ARRAY: there MY_ARRAY is coef_obj.mod's (fillcost.gms's,
        # M1.3 change 25-5), which the fixture's GAMS state took from TIMES.jl before that change
        outs = name == "plain" ? filter(!=("MY_ARRAY"), COEF_ALT_OUTPUTS) : COEF_ALT_OUTPUTS
        r = layer1(tm, DumpData(joinpath(FIXTURES, "coefalt_unit_gams", name)), outs)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        if name == "alt"
            @test !isempty(gparam(tm, "OBJ_ALTV")) && !isempty(gparam(tm, "RTP_CAPVL"))     # L49-53, L83-86
            @test gparam(tm, "FPD")[("2005",)] > 0                                            # L46 (LINFLO)
        elseif name == "lin"
            @test isempty(gparam(tm, "OBJ_ALTV"))
        elseif name == "pasti"
            @test gparam(tm, "NCAP_ILED")[("REG1", "2004", "ELCTECOA00")] ≈ 3.1594622082423074   # L69 recomputes it
        elseif name == "plain"
            # L59 exit: YK1 stays as L32 sets it (T <= Y_EOH); nothing of L65-87 runs
            yk1 = gset(tm, "YK1").keys
            @test !isempty(yk1) && all(parse(Int, t) <= parse(Int, y) for (t, y) in yk1)
            @test isempty(gparam(tm, "RTP_CAPVL")) && isempty(gparam(tm, "R_DF")) && isempty(gparam(tm, "RB"))
            continue                                     # COEF_CPT is coef_cpt.mod's (L19-21)
        end
        # L79 clears small values only at milestone vintages: a past vintage's record may be negative
        @test any(v -> v < 0, values(gparam(tm, "COEF_CPT").values))
        @test all(v >= 1 / 512 for (k, v) in gparam(tm, "COEF_CPT").values if (k[2],) in gset(tm, "MILESTONYR"))
    end
end
