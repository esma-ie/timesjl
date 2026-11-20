# M1.3 (16): ppmain.mod L1228-1333 (v4.9.7): the blending block. Layer 1 on
# TIMES_Demo demo12 reduce_off (no blending data) from the prelv checkpoint,
# compared at the ppm checkpoint on what these lines settle
# (scripts/m13_probe.jl does the same on the core reference runs), and on a
# crafted state against GAMS running ppmain.mod L616-1333 itself, every
# symbol written compared at L1333 (scripts/m13_replay.jl does the same on
# the core models' own states). With blending data: the crafted case
# demo12_blnd (test/unit/test_eqblnd.jl, test/unit/test_variants.jl).

using OpenTIMES: TimesModel, DumpData, layer1, pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!,
             ppmain_ire!, ppmain_bnd!, ppmain_cum!, ppmain_stg!, ppmain_uc!, ppmain_ucmap!, ppmain_blend!, ppmain_blend_symbols,
             gparam, gset, gput!
using OpenTIMES.Reference: ispass
import TOML

const PPMAIN_TO_BLEND = (pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_ire!, ppmain_bnd!, ppmain_cum!,
                         ppmain_stg!, ppmain_uc!, ppmain_ucmap!, ppmain_blend!)

@testset "prelv -> ppm: ppmain.mod L1228-1333 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prelv"); switches=fx["switches"])
    foreach(f -> f(tm), PPMAIN_TO_BLEND)
    names = ppmain_blend_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_ppm")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(names) == 13 && all(ispass, r)
    # L1246: a BL_TYPE gives BLE_SPE for any commodity; L1254-1257: only a blend (BLE) gets
    # periods and a default unit
    tb = TimesModel(joinpath(FIXTURES, "demo12_off_prelv"); switches=fx["switches"])
    push!(tb.data.dump.uels, "OCT"); tb.data.uelorder["oct"] = length(tb.data.dump.uels)      # a new label
    gput!(tb, "BL_TYPE", Dict{NTuple{3,String},Float64}(("REG1", "GSL", "OCT") => 1.0))
    ppmain_blend!(tb)
    @test gset(tb, "BLE_SPE").members == Set([("REG1", "GSL", "OCT")])
    @test isempty(gset(tb, "BLE_TP").members) && isempty(gparam(tb, "BL_UNIT").values)
    gput!(tb, "BLE", Set([("GSL",)]))
    ppmain_blend!(tb)
    @test length(gset(tb, "BLE_TP").members) == 6 && gparam(tb, "BL_UNIT").values == Dict(("REG1", "GSL", "OCT") => 1.0)
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
include("ppmain_blend_case.jl")
const PPMAIN_BLEND_ALL = unique(vcat(PPMAIN_DFLT_OUTPUTS, PPMAIN_TSATTR_NEW, PPMAIN_FLO_NEW, PPMAIN_FLOFS_NEW, PPMAIN_IRE_NEW, PPMAIN_BND_NEW,
                                     PPMAIN_CUM_NEW, PPMAIN_STG_NEW, PPMAIN_UC_NEW, PPMAIN_UCMAP_NEW, PPMAIN_BLEND_NEW))

@testset "ppmain.mod L616-1333 against GAMS on a crafted state" begin
    tm = ppmain_blend_start(FIXTURES, "blend")
    foreach(f -> f(tm), PPMAIN_TO_BLEND)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "ppmain_blend_unit_gams", "blend")), PPMAIN_BLEND_ALL)
    foreach(d -> ispass(d) || println("blend: ", d, " ", d.examples), r)
    @test length(r) == 198 && all(ispass, r)
    # L1251: a given REFUNIT is kept, a missing one set to 1
    @test gparam(tm, "REFUNIT").values == Dict(("REG1",) => 2.0, ("REG2",) => 1.0)
end
