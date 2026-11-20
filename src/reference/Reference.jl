"""
    OpenTIMES.Reference

Tools for checking TIMES.jl against GAMS reference runs (milestone M1.0):

- [`load_dump`](@ref), [`read_symbol`](@ref): read a dump written by
  `reference/python/gdx2arrow.py` (Arrow IPC, format version 1).
- [`compare_symbol`](@ref), [`compare_dumps`](@ref): layer 1 (data) parity.
- [`CanonicalLP`](@ref), [`canonical_from_jump`](@ref),
  [`canonical_from_mps`](@ref), [`compare_lp`](@ref): layer 2 (matrix) parity.
- [`evaluate_point`](@ref): layer 3 cross-evaluation of an optimum in the
  other model.

This is test tooling: it favours clarity over speed and is not used when a
model is built or solved.
"""
module Reference

import Arrow
import JSON
import JuMP
import MathOptInterface as MOI
import Tables

export SpecialValue, SV_NONE, SV_EPS, SV_NA, SV_UNDEF
export ReferenceDump, SymbolInfo, SymbolRecords, load_dump, read_symbol, symbol_names, has_symbol
export Mismatch, ComparisonReport, compare_symbol, compare_dumps, ispass, summary_table
export CanonicalLP, RowData, ColData, canonical_from_jump, canonical_from_mps, canonical_from_dump,
       convert_name_map, compare_lp, evaluate_point, solution_levels

include("dump.jl")
include("compare.jl")
include("lp.jl")

end # module Reference
