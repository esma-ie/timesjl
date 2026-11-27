# Model variables.
#
# GAMS: mod_vars.mod L1-95, v4.9.7 — the declaration of every variable family
# of the TIMES model instance. Macro expansions, from setglobs.gms L348
# (SW_NOTAGS, the non-stochastic case that is Phase 1's scope):
#   %VAR% -> VAR, %SWD% -> '' (no state-of-world index).
# The stochastic expansions (stages.stc L12) are out of Phase 1 scope; the
# data model keeps no SOW slot here, matching SW_NOTAGS exactly.
#
# GAMS semantics kept:
# - Declaring a variable creates no instances. A column exists only once a
#   generated equation (or a bound) references it, which is what
#   `getvar!` reproduces: instances are created one explicit index tuple at
#   a time, never over dense Cartesian products.
# - `POSITIVE VARIABLES` have a default lower bound of 0 and no upper bound;
#   plain `VARIABLES` are free. Bounds beyond that come from the bnd_*
#   files (a later M1.1 slice) and never from this file.
# - GAMS symbol names are case-insensitive ("OBJz" is the symbol OBJZ);
#   lookups here are case-insensitive the same way.
#
# Declared here but out of this slice's scope:
# - VNRET/powerflo hooks (mod_vars.mod L93-94) belong to the DSC and
#   powerflow extensions.
# - VAR_STS (mod_vars.mod L95) is declared as an empty *parameter* when the
#   STS extension is off; it is data, not a variable, and arrives with
#   preprocessing (M1.3).
# - VAR_DNCAP and VAR_SNCAP seen in reference dumps are declared by the DSC
#   extension (loaded whenever DSCAUTO=YES), not by mod_vars.mod.

"""
    VariableSpec

One variable family as declared in `mod_vars.mod`: its GAMS name, declared
domain (the GAMS index sets, `%SWD%` expanded to nothing), whether it was
declared under `POSITIVE VARIABLES`, and the line of `mod_vars.mod` v4.9.7
it comes from.
"""
struct VariableSpec
    name::String
    domain::Vector{String}
    positive::Bool
    description::String
    line::Int
end

dimension(s::VariableSpec) = length(s.domain)

"""
Set of standard objective components.

GAMS: mod_vars.mod L12, v4.9.7: `SET OBV / OBJINV, OBJFIX, OBJSAL, OBJVAR /`.
"""
const OBV = ["OBJINV", "OBJFIX", "OBJSAL", "OBJVAR"]

"""
The variable families of `mod_vars.mod` L15-87, v4.9.7, in declaration order.

`VAS_EXPOBJ` (L77) is declared but referenced only inside STAGES-guarded
code (eqobj.mod L106-121), and GAMS reference dumps of a non-stochastic run
do not even list it; it is kept here because the declaration is
unconditional, and it creates no column unless the stochastic extension
references it.
"""
const MOD_VARS = VariableSpec[
    # POSITIVE VARIABLES (mod_vars.mod L15-67)
    VariableSpec("VAR_ACT", ["R", "ALLYEAR", "ALLYEAR", "P", "S"], true, "Overall activity of a process", 19),
    VariableSpec("VAR_CAP", ["R", "ALLYEAR", "P"], true, "Installed capacity of a process", 20),
    VariableSpec("VAR_FLO", ["R", "ALLYEAR", "ALLYEAR", "P", "C", "S"], true, "Level of process commodity flow", 21),
    VariableSpec("VAR_IRE", ["R", "ALLYEAR", "ALLYEAR", "P", "C", "S", "IE"], true, "Inter-regional trade flow", 22),
    VariableSpec("VAR_NCAP", ["R", "ALLYEAR", "P"], true, "New capacity of a process", 23),
    VariableSpec("VAR_COMNET", ["R", "ALLYEAR", "C", "S"], true, "Net commodity level", 28),
    VariableSpec("VAR_COMPRD", ["R", "ALLYEAR", "C", "S"], true, "Production of commodity", 29),
    VariableSpec("VAR_ELAST", ["R", "ALLYEAR", "C", "S", "J", "BD"], true, "Demand change due to price elasticity", 30),
    VariableSpec("VAR_DEM", ["R", "MILESTONYR", "C"], true, "Demand variable for MACRO", 31),
    VariableSpec("VAR_CUMCOM", ["R", "C", "COM_VAR", "ALLYEAR", "ALLYEAR"], true, "Cumulative commodity PRD or NET", 36),
    VariableSpec("VAR_CUMFLO", ["R", "P", "C", "ALLYEAR", "ALLYEAR"], true, "Cumulative process flow", 37),
    VariableSpec("VAR_CUMCST", ["R", "ALLYEAR", "ALLYEAR", "COSTAGG", "CUR"], true, "Cumulative regional cost", 38),
    VariableSpec("VAR_SIN", ["R", "ALLYEAR", "ALLYEAR", "P", "C", "S"], true, "Input flow into storage", 43),
    VariableSpec("VAR_SOUT", ["R", "ALLYEAR", "ALLYEAR", "P", "C", "S"], true, "Output flow from storage", 44),
    VariableSpec("VAR_BLND", ["R", "ALLYEAR", "COM", "COM"], true, "Refinery blending", 49),
    VariableSpec("VAR_DAM", ["R", "T", "C", "BD", "J"], true, "Damage variables", 50),
    VariableSpec("VAR_RCAP", ["R", "ALLYEAR", "LL", "P"], true, "New retirements", 51),
    VariableSpec("VAR_SCAP", ["R", "ALLYEAR", "LL", "P"], true, "Cumulative retirements", 52),
    VariableSpec("VAR_UPS", ["R", "ALLYEAR", "ALLYEAR", "P", "S", "L"], true, "Start-ups", 53),
    VariableSpec("VAR_UPT", ["R", "ALLYEAR", "ALLYEAR", "P", "S", "UPT"], true, "Start-ups by type", 54),
    VariableSpec("VAR_UDP", ["R", "ALLYEAR", "ALLYEAR", "P", "S", "L"], true, "Unit dispatching", 55),
    VariableSpec("VAR_RLD", ["R", "T", "S", "ITEM"], true, "Residual loads", 56),
    VariableSpec("VAR_OBJ", ["R", "OBV", "CUR"], true, "Objective costs INV,SAL,FIX,VAR,DAM", 65),
    VariableSpec("VAR_OBJELS", ["R", "BD", "CUR"], true, "Change in Consumer surplus", 66),
    VariableSpec("VAS_UPDEV", ["ALLSOW"], true, "Upside deviation of OBJ", 67),
    # VARIABLES (free; mod_vars.mod L70-87)
    VariableSpec("OBJZ", String[], false, "Total discounted system cost", 76),
    VariableSpec("VAS_EXPOBJ", String[], false, "Expected value of total OBJ", 77),
    VariableSpec("VAR_UC", ["UC_N"], false, "Slacks for UC constraints", 82),
    VariableSpec("VAR_UCR", ["UC_N", "R"], false, "Slacks for UCR constraints", 83),
    VariableSpec("VAR_UCT", ["UC_N", "T"], false, "Slacks for UCT constraints", 84),
    VariableSpec("VAR_UCRT", ["UC_N", "R", "T"], false, "Slacks for UCRT constraints", 85),
    VariableSpec("VAR_UCTS", ["UC_N", "T", "S"], false, "Slacks for UCTS constraints", 86),
    VariableSpec("VAR_UCRTS", ["UC_N", "R", "T", "S"], false, "Slacks for UCRTS constraints", 87),
]

"""
    VarFamily{N}

The live instances of one variable family: its spec and the JuMP variable of
every index tuple referenced so far, in creation order (`keys`), which is the
order GAMS creates columns in — the first reference by a generated equation.
"""
struct VarFamily{N}
    spec::VariableSpec
    keys::Vector{NTuple{N,String}}
    refs::Dict{NTuple{N,String},JuMP.VariableRef}
end

VarFamily(spec::VariableSpec) =
    VarFamily{dimension(spec)}(spec, NTuple{dimension(spec),String}[],
                               Dict{NTuple{dimension(spec),String},JuMP.VariableRef}())

Base.length(f::VarFamily) = length(f.keys)

"""
    VariableStore(model)

All variable families of `mod_vars.mod` over one JuMP model, each starting
empty. Families and instances are case-insensitive by name, as in GAMS.
"""
struct VariableStore
    model::JuMP.Model
    families::Dict{String,Any}          # uppercase name -> VarFamily{N}
    order::Vector{String}               # declaration order, uppercase
end

function VariableStore(model::JuMP.Model)
    families = Dict{String,Any}()
    order = String[]
    for spec in MOD_VARS
        families[uppercase(spec.name)] = VarFamily(spec)
        push!(order, uppercase(spec.name))
    end
    return VariableStore(model, families, order)
end

varfamily(store::VariableStore, name::AbstractString) = store.families[uppercase(name)]
has_family(store::VariableStore, name::AbstractString) = haskey(store.families, uppercase(name))

"GAMS-style column name, e.g. `VAR_ACT(REG1,2005,2005,IMPDEMZ,ANNUAL)`."
colname(name::AbstractString, key::Tuple) =
    isempty(key) ? String(name) : string(name, "(", join(key, ","), ")")

"""
    getvar!(store, name, key...) -> JuMP.VariableRef

The variable of one index tuple, created on first reference — the JuMP
equivalent of a GAMS column coming into existence when a generated equation
first references it. `POSITIVE VARIABLES` get lower bound 0 (GAMS default);
free variables get no bounds. Later bounds (bnd_* files) are applied on top
of this, as in GAMS.

This is on the path of every term of every row, so it is written for the compiler (Phase 2,
change 4): the number of indices `N` is a parameter of the method (Julia does not specialize a
`key...` that is only passed on, and a family is a `VarFamily{N}` only for the caller's `N`), the
family is looked up under the name as given before its upper case is built (the generators pass
the declared, upper-case name), and the lookup of the index tuple is in a method that takes the
family with its type (`families` is a `Dict{String,Any}`). The columns, their names and their
order are unchanged.
"""
function getvar!(store::VariableStore, name::AbstractString, key::Vararg{AbstractString,N}) where {N}
    f = get(store.families, name, nothing)                 # the declared name: no upper-casing
    f === nothing && (f = varfamily(store, name))          # any other case; KeyError for an unknown family
    f isa VarFamily{N} || throw(ArgumentError(
        "$(f.spec.name) takes $(dimension(f.spec)) indices (GAMS: mod_vars.mod L$(f.spec.line)), got $N"))
    return getvar!(store.model, f, map(String, key))
end

# The instance `k` of the family `f`, created on first reference: `getvar!` with the family typed.
function getvar!(model::JuMP.Model, f::VarFamily{N}, k::NTuple{N,String}) where {N}
    get!(f.refs, k) do
        v = JuMP.@variable(model, base_name = colname(f.spec.name, k))
        f.spec.positive && JuMP.set_lower_bound(v, 0.0)
        push!(f.keys, k)
        v
    end
end

"""
    var(store, name, key...) -> JuMP.VariableRef

An instance that must already exist (throws `KeyError` otherwise); for
reporting and tests, never for generation.
"""
function var(store::VariableStore, name::AbstractString, key::AbstractString...)
    f = varfamily(store, name)
    N = dimension(f.spec)
    return (f::VarFamily{N}).refs[NTuple{N,String}(String.(key))]
end

"""
    instance_records(store, name; values=false) -> Reference.SymbolRecords

The created instances of one family as `SymbolRecords` for comparison with a
GAMS dump: keys in creation order, with `level`/`lower`/`upper` filled from
the JuMP solution and bounds when `values=true` (GAMS convention: a missing
upper bound is `+INF`, a missing lower bound `-INF`).
"""
function instance_records(store::VariableStore, name::AbstractString; values::Bool=false)
    f = varfamily(store, name)
    N = dimension(f.spec)
    f2 = f::VarFamily{N}
    vals = Dict{String,Vector{Float64}}()
    if values
        lo = Float64[]; up = Float64[]; lv = Float64[]
        for k in f2.keys
            v = f2.refs[k]
            push!(lo, JuMP.has_lower_bound(v) ? JuMP.lower_bound(v) : -Inf)
            push!(up, JuMP.has_upper_bound(v) ? JuMP.upper_bound(v) : Inf)
            push!(lv, JuMP.is_solved_and_feasible(store.model) ? JuMP.value(v) : 0.0)
        end
        vals["lower"] = lo; vals["upper"] = up; vals["level"] = lv
    end
    return Reference.SymbolRecords(f2.spec.name, :variable, copy(f2.keys); values=vals)
end
