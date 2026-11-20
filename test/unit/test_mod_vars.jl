# Tests for src/model/mod_vars.jl (GAMS: mod_vars.mod L12-87, v4.9.7).
#
# Layer-1 check of the MOD_VARS table against the GAMS system's own metadata,
# when a reference run is available: ENV["TIMESJL_REFERENCE"] pointing at a
# <model>/<variant> directory of an openly licensed model (reference/suite.toml).
# The committed metadata fixture came from a DemoS run and was removed on
# 27 Oct 2026 with the DemoS models (docs/test-models.md); a fixture from
# TIMES_Demo demo12 can replace it.

import JSON
import JuMP
using OpenTIMES: MOD_VARS, OBV, VariableStore, VariableSpec, dimension,
             varfamily, has_family, getvar!, var, colname, instance_records
using OpenTIMES.Reference: load_dump, read_symbol, compare_symbol, ispass

# Families declared by the DSC extension, present in any dump made with
# DSCAUTO=YES (initmty.mod L453), not by mod_vars.mod; ported with DSC.
const DSC_FAMILIES = Set(["VAR_DNCAP", "VAR_SNCAP"])

spec_by_name(name) = only(s for s in MOD_VARS if s.name == uppercase(name))

function check_against_metadata(vars::Vector)
    byname = Dict(uppercase(String(v["name"])) => v for v in vars)
    @testset "dump metadata: $(v["name"])" for v in vars
        name = uppercase(String(v["name"]))
        if name in DSC_FAMILIES
            @test !any(s -> s.name == name, MOD_VARS)   # DSC's, not mod_vars.mod's
        else
            s = spec_by_name(name)
            @test dimension(s) == Int(v["dimension"])
            @test s.domain == String.(v["domain"])
            @test s.positive == (v["type"] == "positive")
            s.positive || @test v["type"] == "free"
        end
    end
    # Every mod_vars.mod family is in the dump, except VAS_EXPOBJ: declared
    # (mod_vars.mod L77) but referenced only in STAGES-guarded code
    # (eqobj.mod L106-121), and GAMS leaves it out of the GDX of a
    # non-stochastic run. If this test ever fails with VAS_EXPOBJ present,
    # that observation changed with the GAMS version — update this comment.
    for s in MOD_VARS
        if s.name == "VAS_EXPOBJ"
            @test !haskey(byname, s.name)
        else
            @test haskey(byname, s.name)
        end
    end
end

if haskey(ENV, "TIMESJL_REFERENCE")
    @testset "MOD_VARS table vs GAMS metadata (live reference)" begin
        d = load_dump(joinpath(ENV["TIMESJL_REFERENCE"], "final"))
        vars = [Dict("name" => s.name, "type" => s.type, "dimension" => s.dimension,
                     "domain" => s.domain)
                for s in values(d.symbols) if s.kind == :variable]
        check_against_metadata(vars)
    end
end

@testset "OBV set" begin
    @test OBV == ["OBJINV", "OBJFIX", "OBJSAL", "OBJVAR"]   # mod_vars.mod L12
end

@testset "VariableStore mechanics" begin
    store = VariableStore(JuMP.Model())
    @test has_family(store, "VAR_ACT") && has_family(store, "var_act")
    @test !has_family(store, "VAR_DNCAP")                    # DSC, not mod_vars.mod
    @test length(store.order) == length(MOD_VARS) == 33

    # Lazy creation: declaring creates nothing; first reference creates one.
    @test length(varfamily(store, "VAR_ACT")) == 0
    v = getvar!(store, "VAR_ACT", "REG1", "2005", "2005", "IMPDEMZ", "ANNUAL")
    @test length(varfamily(store, "VAR_ACT")) == 1
    @test getvar!(store, "var_act", "REG1", "2005", "2005", "IMPDEMZ", "ANNUAL") === v
    @test length(varfamily(store, "VAR_ACT")) == 1              # idempotent
    @test var(store, "VAR_ACT", "REG1", "2005", "2005", "IMPDEMZ", "ANNUAL") === v
    @test_throws KeyError var(store, "VAR_ACT", "REG1", "2005", "2005", "OTHER", "ANNUAL")

    # POSITIVE VARIABLES: lower bound 0, no upper; free variables: no bounds.
    @test JuMP.lower_bound(v) == 0.0 && !JuMP.has_upper_bound(v)
    z = getvar!(store, "OBJZ")
    @test !JuMP.has_lower_bound(z) && !JuMP.has_upper_bound(z)
    u = getvar!(store, "VAR_UC", "OBJZ")
    @test !JuMP.has_lower_bound(u)

    # Declared arity is enforced with the GAMS source in the message.
    @test_throws ArgumentError getvar!(store, "VAR_ACT", "REG1", "2005")
    @test_throws KeyError getvar!(store, "NO_SUCH_VAR")

    # GAMS-style column names.
    @test JuMP.name(v) == "VAR_ACT(REG1,2005,2005,IMPDEMZ,ANNUAL)"
    @test colname("OBJZ", ()) == "OBJZ"

    # Creation order is kept (the order GAMS creates columns in).
    getvar!(store, "VAR_NCAP", "REG1", "2005", "PLT1")
    getvar!(store, "VAR_NCAP", "REG1", "2010", "PLT1")
    @test varfamily(store, "VAR_NCAP").keys ==
          [("REG1", "2005", "PLT1"), ("REG1", "2010", "PLT1")]
end

@testset "instance_records vs tiny_dump" begin
    d = load_dump(joinpath(FIXTURES, "tiny_dump"))
    ref = read_symbol(d, "VAR_ACT")
    store = VariableStore(JuMP.Model())
    for k in ref.keys
        getvar!(store, "VAR_ACT", k...)
    end
    mine = instance_records(store, "VAR_ACT")
    @test mine.keys == ref.keys
    # mine carries no value columns, so this compares the key sets alone.
    r = compare_symbol(mine, ref)
    @test ispass(r)
    withvals = instance_records(store, "VAR_ACT"; values=true)
    @test withvals.values["lower"] == zeros(length(ref.keys))
    @test all(isinf, withvals.values["upper"])
end
