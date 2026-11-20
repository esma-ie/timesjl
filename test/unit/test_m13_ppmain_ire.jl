# M1.3 (12): ppmain.mod L846-933 (v4.9.7): the trade attributes levelled
# (pp_lvlfc.mod for IRE_PRICE and IRE_FLOSUM, pp_lvlif.mod for IRE_FLO) and
# the market-based trade. Layer 1 on TIMES_Demo demo12 reduce_off from the
# prelv checkpoint, compared at the ppm checkpoint on what these lines
# settle (scripts/m13_probe.jl does the same on the core reference runs),
# and on crafted states against GAMS running ppmain.mod L616-933 itself,
# every symbol written compared at L933 (scripts/m13_replay.jl does the same
# on the core models' own states).

using OpenTIMES: TimesModel, DumpData, layer1, pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_ire!,
             ppmain_ire_symbols, gset, gparam
using OpenTIMES.Reference: ispass
import TOML

@testset "prelv -> ppm: ppmain.mod L846-933 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prelv"); switches=fx["switches"])
    foreach(f -> f(tm), (pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_ire!))
    names = ppmain_ire_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_ppm")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(names) == 11 && all(ispass, r)
end

isdefined(@__MODULE__, :PPMAIN_DFLT_OUTPUTS) || include("ppmain_dflt_case.jl")
isdefined(@__MODULE__, :PPMAIN_TSATTR_NEW) || include("ppmain_tsattr_case.jl")
isdefined(@__MODULE__, :PPMAIN_FLO_NEW) || include("ppmain_flo_case.jl")
isdefined(@__MODULE__, :PPMAIN_FLOFS_NEW) || include("ppmain_flofs_case.jl")
include("ppmain_ire_case.jl")
const PPMAIN_IRE_ALL = unique(vcat(PPMAIN_DFLT_OUTPUTS, PPMAIN_TSATTR_NEW, PPMAIN_FLO_NEW, PPMAIN_FLOFS_NEW, PPMAIN_IRE_NEW))

@testset "ppmain.mod L616-933 against GAMS on crafted states" begin
    p = "TB_ELC_REG1_REG2_01"
    for name in PPMAIN_IRE_CASES
        tm = ppmain_ire_start(FIXTURES, name)
        foreach(f -> f(tm), (pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_ire!))
        r = layer1(tm, DumpData(joinpath(FIXTURES, "ppmain_ire_unit_gams", name)), PPMAIN_IRE_ALL)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test length(r) == 112 && all(ispass, r)
        v(n) = gparam(tm, n).values
        g(k...) = get(v(k[1]), k[2:end], nothing)
        has(n, k...) = k in gset(tm, n).members
        # pp_lvlfc.mod L850: IRE_FLOSUM at S levelled to the DAYNITE PRC_TS; pp_lvlif.mod: IRE_FLO at S levelled, ANNUAL copied
        @test g("IRE_FLOSUM", "REG1", "2010", p, "ELC", "SN", "IMP", "ELC", "OUT") == 0.1
        @test g("IRE_FLO", "REG2", "2010", p, "ELC", "REG1", "ELC", "SD") == 0.95 && g("IRE_FLO", "REG2", "2010", p, "ELC", "REG1", "ELC", "WD") === nothing
        @test g("IRE_FLO", "REG1", "2015", p, "ELC", "REG2", "ELC", "WN") == 0.9
        # L931-933: the default 1 for a link without IRE_FLO
        @test g("IRE_FLO", "REG1", "2010", p, "ELC", "REG2", "AGRELC", "SD") == 1.0
        # L866: REG1 exports ELC to two commodities of REG2, so it is a marketplace; L889-890 the diagonal link and RC_RC
        @test has("RPC_MARKET", "REG1", p, "ELC", "EXP") && has("RC_RC", "REG1", "ELC", "REG1", "ELC")
        if name == "ire"
            # L898-901: the marketplace's IRE_FLO taken from the REG2 link; L912: RPC_MARKET IMP; L924-926: ACT moved to ELC
            @test g("IRE_FLO", "REG1", "2015", p, "ELC", "REG1", "ELC", "SD") == 0.9 && has("RPC_MARKET", "REG1", p, "ELC", "IMP")
            @test has("TOP_IRE", "REG1", "ELC", "REG1", "ELC", p) && g("IRE_FLOSUM", "REG1", "2015", p, "ELC", "ANNUAL", "EXP", "ELC", "IN") == 0.2
        else
            # distribution: IRE_FLO 1 (L897), EQIRE EXP and the diagonal link dropped (L910-913), RP_AIRE EXP dropped (L921)
            @test has("IRE_DIST", "REG1", p) && g("IRE_FLO", "REG1", "2010", p, "ELC", "REG1", "ELC", "SD") == 1.0
            @test has("RPC_EQIRE", "REG1", p, "ELC", "EXP") && !has("TOP_IRE", "REG1", "ELC", "REG1", "ELC", p) && !has("RP_AIRE", "REG1", p, "EXP")
        end
    end
end
