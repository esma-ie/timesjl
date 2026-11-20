# M1.3 (11b): ppmain.mod L823-843 (v4.9.7): FLO_FUNC and FLO_SUM levelled
# (pp_lvlff.mod, pp_lvlfs.mod), FLO_SUM and IRE_FLOSUM from PRC_ACTFLO,
# FLO_SHAR levelled (pp_lvlbr.mod) and the market shares (eqflomrk.mod).
# Layer 1 on TIMES_Demo demo12 reduce_off from the prelv checkpoint,
# compared at the ppm checkpoint on what these lines settle
# (scripts/m13_probe.jl does the same on the core reference runs), and on
# crafted states against GAMS running ppmain.mod L616-843 itself, every
# symbol written compared at L843 (scripts/m13_replay.jl does the same on
# the core models' own states).

using OpenTIMES: TimesModel, DumpData, layer1, pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_flofs_symbols,
             gset, gparam
using OpenTIMES.Reference: ispass
import TOML

@testset "prelv -> ppm: ppmain.mod L823-843 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prelv"); switches=fx["switches"])
    pp_qafs!(tm)
    ppmain_dflt!(tm)
    ppmain_tsattr!(tm)
    ppmain_flo!(tm)
    ppmain_flofs!(tm)
    names = ppmain_flofs_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_ppm")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    # demo12 has VDA_EMCB data, so FLO_SUM is left to the replay (ppm_ext.vda L20)
    @test length(names) == 9 && all(ispass, r)
end

isdefined(@__MODULE__, :PPMAIN_DFLT_OUTPUTS) || include("ppmain_dflt_case.jl")
isdefined(@__MODULE__, :PPMAIN_TSATTR_NEW) || include("ppmain_tsattr_case.jl")
isdefined(@__MODULE__, :PPMAIN_FLO_NEW) || include("ppmain_flo_case.jl")
include("ppmain_flofs_case.jl")
const PPMAIN_FLOFS_ALL = unique(vcat(PPMAIN_DFLT_OUTPUTS, PPMAIN_TSATTR_NEW, PPMAIN_FLO_NEW, PPMAIN_FLOFS_NEW))

@testset "ppmain.mod L616-843 against GAMS on crafted states" begin
    for name in PPMAIN_FLOFS_CASES
        tm = ppmain_flofs_start(FIXTURES, name)
        pp_qafs!(tm)
        ppmain_dflt!(tm)
        ppmain_tsattr!(tm)
        ppmain_flo!(tm)
        ppmain_flofs!(tm)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "ppmain_flofs_unit_gams", name)), PPMAIN_FLOFS_ALL)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test length(r) == 101 && all(ispass, r)
        v(n) = gparam(tm, n).values
        g(k...) = get(v(k[1]), k[2:end], nothing)
        yr = Dict(k[2] => x for (k, x) in v("G_YRFR") if k[1] == "REG1")
        p = "ELCTEGAS00"
        if name == "ffs"
            # pp_lvlff.mod: ANNUAL copied down (L30-31), S levelled to SD and SN (L21-26)
            @test g("FLO_FUNC", "REG1", "2010", p, "ELCGAS", "ELC", "WN") == 0.45 && g("FLO_FUNC", "REG1", "2015", p, "ELCGAS", "ELC", "SN") == 0.5
            # pp_lvlfs.mod: S and W inherited down (L35-39) and deleted (L33); COTEGAS aggregated to ANNUAL (L23-28)
            @test g("FLO_SUM", "REG1", "2010", p, "ELCGAS", "ELC", "ELCGAS", "SN") == 0.8 && g("FLO_SUM", "REG1", "2010", p, "ELCGAS", "ELC", "ELCGAS", "S") === nothing
            @test g("FLO_SUM", "REG1", "2010", "COTEGAS", "COMGAS", "DCOT", "COMGAS", "ANNUAL") ≈ 0.9 * yr["S"] + 0.7 * yr["W"]
            # L34: a year outside RTP deleted
            @test g("FLO_SUM", "REG1", "2011", "COTEGAS", "COMGAS", "DCOT", "COMGAS", "ANNUAL") === nothing
            # pp_lvlbr.mod with %2 ',C,CG': ANNUAL (UP) and S (LO) inherited down; SD aggregated to S
            @test g("FLO_SHAR", "REG1", "2010", p, "ELC", "ELC", "WN", "UP") == 0.9 && g("FLO_SHAR", "REG1", "2010", p, "ELC", "ELC", "SN", "LO") == 0.2
            @test g("FLO_SHAR", "REG1", "2015", "ELCTECOA00", "ELC", "ELC", "S", "LO") ≈ 0.4 * yr["SD"] / yr["S"]
        else
            rx = Set(gset(tm, "RX_MARK").keys)
            # eqflomrk.mod L26-27: own shares flagged at '0', a negative one at the last milestone (T--ORD(T))
            @test ("REG1", "0", p, "ELC", "UP") in rx && ("REG1", "2050", p, "ELCGAS", "LO") in rx
            # L22: LO dropped under FX; L23: a group share outside RTP_VARA deleted, an own one kept
            @test g("PRC_MARK", "REG1", "2015", p, p, "ELC", "LO") === nothing && g("PRC_MARK", "REG1", "2012", p, p, "ELCGAS", "UP") == 0.4
            @test g("PRC_MARK", "REG1", "2012", p, "ELCTECOA00", "ELCGAS", "UP") === nothing
            # L29-32: the EPS group share bounds the flow with EPS and is removed
            @test g("FLO_BND", "REG1", "2015", p, "ELC", "ANNUAL", "UP") == 0.0 && g("PRC_MARK", "REG1", "2015", p, "ELCTECOA00", "ELC", "UP") === nothing
            # L52, ppmain.mod L843: RMKC holds the market-share commodities
            @test ("REG1", "ELCTECOA00", "ELC") in gset(tm, "RMKC").members
        end
    end
end
