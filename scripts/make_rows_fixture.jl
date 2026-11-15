# Write the rows of some equation families of GAMS's LP (CONVERT export of a reference run) to a
# small JSON fixture: the row bounds and every coefficient, under canonical names.
#
#   julia --project=test scripts/make_rows_fixture.jl <reference>/<model>/<variant> <out.json> <family> [<family> ...]
#
# For a case whose whole fixtures are not worth their size: a test builds the rows from another
# fixture and compares them with these (test/unit/test_cum_lin.jl: the cumulative equations under
# OBJ LIN, from demo12_cumlin).
#
# Only for cases with redistribute = "public" in reference/suite.toml or reference/crafted.toml.
# The file records the model, the variant and the GAMS version, not the machine or its paths.

import TOML, JSON
using TIMES.Reference: canonical_from_dump

const REPO = dirname(@__DIR__)
function main(refrun, out, families...)
    mf = JSON.parsefile(joinpath(refrun, "manifest.json"))
    model = mf["model"]
    cases = Dict(m["name"] => m for f in ("suite.toml", "crafted.toml")
                 for m in TOML.parsefile(joinpath(REPO, "reference", f))["model"])
    get(get(cases, model, Dict()), "redistribute", "?") == "public" ||
        error("$model is not redistribute = \"public\" in reference/suite.toml or crafted.toml: no fixture")
    gams = strip(first(split(get(get(mf["runs"], "convert", Dict()), "gams_version", "?"), "  ")))
    lp = canonical_from_dump(joinpath(refrun, "matrix"), joinpath(refrun, "matrix_dictmap"))
    fam(r) = first(split(r, "("))
    rows = sort([r for r in keys(lp.rows) if fam(r) in families])
    isempty(rows) && error("no row of $(join(families, ", ")) in $refrun")
    all(r -> isfinite(lp.rows[r].lo) && isfinite(lp.rows[r].hi), rows) || error("a row bound is not finite: JSON cannot hold it")
    coefs = sort([(k[1], k[2], x) for (k, x) in lp.coefs if fam(k[1]) in families])
    doc = Dict("source" => "<$model $(mf["variant"]), CONVERT export, rows of $(join(families, ", ")); $gams>",
               "rows" => [[r, lp.rows[r].lo, lp.rows[r].hi] for r in rows],
               "coefs" => [[r, c, x] for (r, c, x) in coefs])
    write(out, JSON.json(doc, 1))
    println("wrote ", out, ": ", length(rows), " rows, ", length(coefs), " coefficients")
end

main(ARGS...)
