# The SOW tags (src/model/sow_tags.jl; M1.3 change 73): SW_NOTAGS gives back
# what the builders used before the change, SW_TAGS the stochastic names and
# indices (setglobs.gms L348; stages.stc L12-15, v4.9.7). The deterministic
# models themselves are checked at layer 2 by every other test.

using TIMES: SowTags, sw_rows, set_sow!, eqtag, swt, swx, sw_cols, sow_rows, sowkey, vartag, sw_bnd
import TOML

@testset "SW_NOTAGS: a deterministic run" begin
    tm = (tags = SowTags(),)
    @test sw_rows(tm, "2020") == [""]
    @test eqtag(tm, "EQE_COMBAL") == "EQE_COMBAL"
    @test swt(tm, ("REG1", "2020", "ELC", "ANNUAL"), "2020") == ("REG1", "2020", "ELC", "ANNUAL")
    @test swx(tm) == "1"
end

@testset "SW_TAGS: a stochastic run" begin
    # two SOWs from 2020; 2010 is the shared first stage, whose node SOW is 1
    sw_t = Dict("2010" => ["1"], "2020" => ["1", "2"])
    sw_tsw = Dict(("1", "2010") => ["1"], ("2", "2010") => ["1"], ("1", "2020") => ["1"], ("2", "2020") => ["2"])
    tm = (tags = SowTags(true, "", sw_t, sw_tsw),)
    @test sw_rows(tm, "2020") == ["1", "2"]
    @test sw_rows(tm, "2030") == String[]                  # no SW_T(T,SOW): no row
    set_sow!(tm, "2")
    @test eqtag(tm, "EQE_COMBAL") == "ESE_COMBAL"
    @test_throws ArgumentError eqtag(tm, "OBJ")
    @test swt(tm, ("REG1", "2020", "ELC", "ANNUAL"), "2020") == ("REG1", "2020", "ELC", "ANNUAL", "2020", "2")
    @test swx(tm) == "2"
    @test sw_cols(tm, nothing) == ["2"]                    # %SOW%: the row's own SOW
    @test sw_cols(tm, "2010") == ["1"]                     # %VARV% at V = 2010: the node SOW 1
    @test sw_cols(tm, "2020") == ["2"]
end

@testset "sow_tags: STAGES YES as written (maindrv.mod L66)" begin
    # a deterministic dump: SW_T(T,'1') (initmty.mod L130, coefmain.mod L11), no SW_TSW (initmty.stc)
    d = TIMES.DumpData(joinpath(FIXTURES, "demo12_cumc_presolve"))
    @test !TIMES.sow_tags(d, Dict("STAGES" => "Yes")).stochastic    # SENSIS (maindrv.mod L34): SW_NOTAGS
    @test !TIMES.sow_tags(d, Dict{String,String}()).stochastic
    tg = TIMES.sow_tags(d, Dict("STAGES" => "YES"))
    @test tg.stochastic && isempty(tg.sw_tsw)
    @test !isempty(tg.sw_t) && all(==(["1"]), values(tg.sw_t))
end

@testset "The other row heads and the bounds (change 73, part 2)" begin
    # SW_NOTAGS: a bare %SOW% head is one row with the index as given; a bound is the variable itself
    det = (tags = SowTags(),)
    @test sow_rows(det) == [""]
    @test sowkey(det, ("REG1", "USD")) == ("REG1", "USD")
    @test vartag(det, "VAR_ACT") == "VAR_ACT"
    @test sw_bnd(det, "VAR_NCAP", ("REG1", "2020", "P1"), "2020") == [("VAR_NCAP", ("REG1", "2020", "P1"))]
    @test sw_bnd(det, "VAR_CUMFLO", ("REG1", "P1", "C1", "2010", "2030"), :sow) ==
          [("VAR_CUMFLO", ("REG1", "P1", "C1", "2010", "2030"))]
    # SW_TAGS: the set SOW runs a bare %SOW%; SW_T(T,SOW) the statements under it
    sw_t = Dict("2010" => ["1"], "2020" => ["1", "2"])
    sw_tsw = Dict(("1", "2010") => ["1"], ("2", "2010") => ["1"], ("1", "2020") => ["1"], ("2", "2020") => ["2"])
    tm = (tags = SowTags(true, "", sw_t, sw_tsw, ["1", "2"]),)
    @test sow_rows(tm) == ["1", "2"]
    set_sow!(tm, "2")
    @test sowkey(tm, ("REG1", "USD")) == ("REG1", "USD", "2")
    @test vartag(tm, "VAR_ACT") == "VAS_ACT"
    @test_throws ArgumentError vartag(tm, "OBJZ")
    @test sw_bnd(tm, "VAR_NCAP", ("REG1", "2010", "P1"), "2010") == [("VAS_NCAP", ("REG1", "2010", "P1", "1"))]
    @test sw_bnd(tm, "VAR_NCAP", ("REG1", "2020", "P1"), "2020") ==
          [("VAS_NCAP", ("REG1", "2020", "P1", "1")), ("VAS_NCAP", ("REG1", "2020", "P1", "2"))]
    @test sw_bnd(tm, "VAR_CUMFLO", ("REG1", "P1", "C1", "2010", "2030"), :sow) ==
          [("VAS_CUMFLO", ("REG1", "P1", "C1", "2010", "2030", "1")), ("VAS_CUMFLO", ("REG1", "P1", "C1", "2010", "2030", "2"))]
    @test isempty(sw_bnd(tm, "VAR_NCAP", ("REG1", "2030", "P1"), "2030"))      # no SW_T(T,SOW): no bound
    @test_throws ArgumentError sw_bnd(tm, "VAR_NCAP", ("REG1", "2030", "P1"), :all)
    # the four-argument form of part 1 keeps an empty set SOW
    @test isempty(SowTags(true, "", sw_t, sw_tsw).sows)
end

@testset "A deterministic model reads no tag (demo12_cumc)" begin
    # no ES_ row and no VAS_ column: every name is the EQ.../VAR... name the builders used before the tags
    vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
              if v["prefix"] == "demo12_cumc")
    tm = TIMES.TimesModel(joinpath(FIXTURES, "demo12_cumc_presolve"); reduce=vx["reduce"], switches=vx["switches"])
    @test !tm.tags.stochastic
    @test TIMES.generate!(tm) > 0
    @test !any(startswith("ES"), tm.eqs.order)
    @test !any(n -> startswith(n, "VAS_") && !isempty(tm.vars.families[n].keys), tm.vars.order)
    @test tm.tags.sow == ""
end
