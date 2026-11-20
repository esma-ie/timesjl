# M1.3 (17a): ppmain.mod L1336-1357 with pp_reduce.red (v4.9.7): the
# reduction of model size, RTPCS_VARF and RTP_VINTYR. Layer 1 on TIMES_Demo
# demo12 reduce_off (%REDUCE% NO) from the prelv checkpoint, compared at the
# ppm checkpoint on what these lines settle (scripts/m13_probe.jl does the
# same on the core reference runs, reduce_off and as_run, %REDUCE% YES), and
# on two crafted states (%REDUCE% YES and unset) against GAMS running
# ppmain.mod L616-1350 itself, every symbol written compared at L1350
# (scripts/m13_replay.jl does the same on the core models' own states).

using OpenTIMES: TimesModel, DumpData, layer1, pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_ire!,
             ppmain_bnd!, ppmain_cum!, ppmain_stg!, ppmain_uc!, ppmain_ucmap!, ppmain_blend!, ppmain_reduce!, ppmain_reduce_symbols,
             gset, gparam
using OpenTIMES.Reference: ispass
import TOML

const PPMAIN_TO_REDUCE = (pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_ire!, ppmain_bnd!, ppmain_cum!,
                          ppmain_stg!, ppmain_uc!, ppmain_ucmap!, ppmain_blend!, ppmain_reduce!)

@testset "prelv -> ppm: ppmain.mod L1336-1357 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prelv"); switches=fx["switches"])
    foreach(f -> f(tm), PPMAIN_TO_REDUCE)
    names = ppmain_reduce_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_ppm")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(names) == 18 && all(ispass, r)
end

isdefined(@__MODULE__, :PPMAIN_DFLT_OUTPUTS) || include("ppmain_dflt_case.jl")
isdefined(@__MODULE__, :PPMAIN_TSATTR_NEW) || include("ppmain_tsattr_case.jl")
isdefined(@__MODULE__, :PPMAIN_FLO_NEW) || include("ppmain_flo_case.jl")
isdefined(@__MODULE__, :PPMAIN_FLOFS_NEW) || include("ppmain_flofs_case.jl")
isdefined(@__MODULE__, :PPMAIN_IRE_NEW) || include("ppmain_ire_case.jl")
isdefined(@__MODULE__, :PPMAIN_BND_NEW) || include("ppmain_bnd_case.jl")
isdefined(@__MODULE__, :PPMAIN_CUM_NEW) || include("ppmain_cum_case.jl")
isdefined(@__MODULE__, :PPMAIN_STG_NEW) || include("ppmain_stg_case.jl")
isdefined(@__MODULE__, :PPMAIN_UC_NEW) || include("ppmain_uc_case.jl")
isdefined(@__MODULE__, :PPMAIN_UCMAP_NEW) || include("ppmain_ucmap_case.jl")
isdefined(@__MODULE__, :PPMAIN_BLEND_NEW) || include("ppmain_blend_case.jl")
include("ppmain_reduce_case.jl")
const PPMAIN_REDUCE_ALL = unique(vcat(PPMAIN_DFLT_OUTPUTS, PPMAIN_TSATTR_NEW, PPMAIN_FLO_NEW, PPMAIN_FLOFS_NEW, PPMAIN_IRE_NEW, PPMAIN_BND_NEW,
                                      PPMAIN_CUM_NEW, PPMAIN_STG_NEW, PPMAIN_UC_NEW, PPMAIN_UCMAP_NEW, PPMAIN_BLEND_NEW, PPMAIN_REDUCE_NEW))

@testset "ppmain.mod L616-1350 against GAMS on crafted states" begin
    for c in PPMAIN_REDUCE_CASES
        tm = ppmain_reduce_start(FIXTURES, c)
        foreach(f -> f(tm), PPMAIN_TO_REDUCE)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "ppmain_reduce_unit_gams", c)), PPMAIN_REDUCE_ALL)
        foreach(d -> ispass(d) || println(c, ": ", d, " ", d.examples), r)
        @test all(ispass, r)
        if c == "yes"
            has(n, k...) = k in gset(tm, n).members
            # pp_reduce.red L130-131, L165-168: FTE-AGRELC off at ANNUAL in 2010, the EPS bound moved to its DAYNITE slices
            @test has("RTPS_OFF", "REG1", "2010", "FTE-AGRELC", "SD") && !has("RTP_VARA", "REG1", "2010", "FTE-AGRELC")
            @test gparam(tm, "ACT_BND").values[("REG1", "2010", "FTE-AGRELC", "SD", "UP")] == 0.0
            @test !haskey(gparam(tm, "ACT_BND").values, ("REG1", "2010", "FTE-AGRELC", "ANNUAL", "UP"))
            # L165: FTE-AGRBIO off at ANNUAL, so below it too; L143-155: no single producer is left, as demo12's dummy
            # imports (IMPNRGZ) are a second producer of every commodity
            @test has("RTPS_OFF", "REG1", "2010", "FTE-AGRBIO", "SD") && isempty(gset(tm, "RTCS_SING").keys)
        end
    end
end
