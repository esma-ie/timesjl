# M1.3 change 24: EQ_SLSIFT, load shifting (eqactups.vda L127-158, v4.9.7), on the crafted
# cases TIMES_Demo-demo12_ls (demo12 variant 1, no time windows) and demo12_lst (ACT_TIME
# windows, with the hour map of timslice.mod L110-121), as_run: the rows alone against the
# CONVERT export. The whole models are checked against GAMS in test_public_parity.jl.

using TIMES: TimesModel, eq_slsift!
using TIMES.Reference: canonical_from_jump, canonical_from_dump, family
import TOML
isdefined(@__MODULE__, :check_family_parity) || include("parity_helpers.jl")

let vxs = TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
    for (prefix, nrows, fams) in (("demo12_ls", 120, ["VAR_ACT", "VAR_COMPRD", "VAR_SIN", "VAR_SOUT"]),
                                  ("demo12_lst", 228, ["VAR_ACT", "VAR_COMPRD", "VAR_SIN", "VAR_SOUT", "VAR_UDP", "VAR_UPS"]))
        vx = only(v for v in vxs if v["prefix"] == prefix)
        @testset "$prefix" begin
            tm = TimesModel(joinpath(FIXTURES, prefix * "_presolve"); reduce=vx["reduce"], switches=vx["switches"])
            @test eq_slsift!(tm) == nrows
            mine = canonical_from_jump(tm.model)
            ref = canonical_from_dump(joinpath(FIXTURES, prefix * "_matrix", "matrix"),
                                      joinpath(FIXTURES, prefix * "_matrix", "dictmap"))
            @test check_family_parity(mine, ref, "EQ_SLSIFT") == nrows
            # the variable families the rows reach (the time windows bring VAR_UDP and VAR_UPS)
            @test sort(unique(family(j) for (i, j) in keys(mine.coefs) if family(i) == "EQ_SLSIFT")) == fams
        end
    end
end
