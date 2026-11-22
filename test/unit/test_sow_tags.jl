# The SOW tags (src/model/sow_tags.jl; M1.3 change 73): SW_NOTAGS gives back
# what the builders used before the change, SW_TAGS the stochastic names and
# indices (setglobs.gms L348; stages.stc L12-15, v4.9.7). The deterministic
# models themselves are checked at layer 2 by every other test.

using TIMES: SowTags, sw_rows, set_sow!, eqtag, swt, swx, sw_cols

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
