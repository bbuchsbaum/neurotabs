# Summary Profile draft fixtures

The normative draft is [spec/summary/README.md](../../spec/summary/README.md).
`cases.json` is language-neutral: `valid` contains canonical rows and reference
English labels; `invalid` contains rejected canonical rows; `imports` pairs
legacy inputs and source contexts with canonical outputs or an expected error.
`mixed_rows` identifies one mixed-kind/level frame. `roundtrip_rows` identifies
the stored rows to preserve, including unavailable and constant cases.
`roundtrip.csv` encodes the valid rows with a shared header, empty null cells,
full-precision numbers, and text identifiers. Omitted optional JSON fields and
explicit nulls are equivalent when comparing this CSV with the JSON rows.

Run the artifact/reference-adapter checks in neurotabs:

```sh
python3 conformance/summary/sync.py --check
Rscript -e 'devtools::test(filter = "summary-contract")'
```

After changing the authoritative files, run `sync.py` without `--check` to
regenerate the compatibility manifest and installed artifact. Commit both.
The manifest lists SHA-256 digests of artifact files; a downstream consumer pins
the manifest digest too. This is a draft artifact, not a published release.

R reads the installed registry with:

```r
jsonlite::fromJSON(system.file("schema", "summary", "interval-kinds.json",
                             package = "neurotabs"))
```

R writers can use `jsonlite::toJSON(..., digits = I(17), null = "null")` for
round-trip-safe JSON numbers. For CSV, format numeric cells with `sprintf("%.17g",
value)` before writing; default formatting can lose significant digits.

Downstream suites should run these fixtures against their own production
readers, writers, and renderers. The R test adapter is deliberately separate
from those implementations and does not establish their conformance. No 0.1
fixture claims calculator accuracy. The sample CSV is a standalone descriptor
example, not a complete NFTab dataset.
