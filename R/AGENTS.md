<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-07 | Updated: 2026-04-07 -->

# R/

## Purpose
All R source code for the neurotabs package. Organized by architectural layer: core data model, encoding/schema constructors, resolution engine, backend adapters, I/O, grammar verbs, concatenation, and validation. Every exported symbol is prefixed `nf_`.

## Key Files

| File | Description |
|------|-------------|
| `nftab-class.R` | Core S3 constructors: `nftab()`, `nf_manifest()`, `nf_feature()`, and accessors (`nf_nobs`, `nf_feature_names`, `nf_axes`, `nf_design`, `[.nftab`, etc.) |
| `schema.R` | Type-level constructors: `nf_col_schema()`, `nf_logical_schema()`, `nf_axis_domain()`, `nf_support()`, `nf_support_volume()`, `nf_support_surface()`, `nf_schema_fingerprint()` |
| `encoding.R` | Encoding constructors: `nf_ref_encoding()`, `nf_columns_encoding()`, `nf_col()` (column reference); `encoding_applicable()` predicate |
| `resolution.R` | Feature resolution engine: `nf_resolve()`, `nf_resolve_all()`, checksum validation, dtype validation, backend dispatch |
| `io.R` | Disk I/O: `nf_read()`, `nf_write()`, manifest parsing/serialization, table coercion to schema dtypes |
| `concat.R` | Dataset concatenation: `nf_concat()`, `nf_compatible()`, schema fingerprinting, dtype promotion, resource ID deduplication |
| `validation.R` | Conformance checking: `nf_validate()` at structural and full levels; `x-masked-volume` extension validation |
| `grammar.R` | dplyr-style verbs: `nf_filter()`, `nf_select()`, `nf_arrange()`, `nf_collect()`, `nf_group_by()`, `nf_ungroup()` |
| `compute.R` | Compute operations: group summaries, derived feature materialization, `nf_summarise()`, `nf_compare()` |
| `backend-registry.R` | Backend adapter registry: `nf_register_backend()`, `nf_backends()`, internal dispatch helpers |
| `backend-nifti.R` | NIfTI backend adapter; registered via `.onLoad`; supports neuroim2 and RNifti, 3D/4D with 0-based `index.t` selector |
| `neurotabs-package.R` | Package-level documentation and `%||%` null-coalescing helper |
| `RcppExports.R` | Auto-generated Rcpp bindings — **do not edit** |

## For AI Agents

### Working In This Directory
- **Never edit** `RcppExports.R` by hand. After changing `src/*.cpp`, run `Rscript -e 'Rcpp::compileAttributes()'`.
- After adding/changing roxygen2 comments, run `Rscript -e 'devtools::document()'` to regenerate `man/` and `NAMESPACE`.
- All public functions need roxygen2 `@export` tags. Internal helpers use `.` prefix and `@keywords internal`.
- The `%||%` null-coalescing helper is defined in `neurotabs-package.R` and available package-wide.

### Layer Dependency Order
```
schema.R + encoding.R         (no internal deps)
       ↓
nftab-class.R                 (uses schema + encoding constructors)
       ↓
backend-registry.R            (standalone registry)
backend-nifti.R               (uses registry)
       ↓
resolution.R                  (uses encoding, registry, nftab-class)
       ↓
io.R                          (uses all above + manifest parsing)
concat.R                      (uses nftab-class, schema, encoding)
validation.R                  (uses resolution + all above)
grammar.R + compute.R         (use all above)
```

### Testing Requirements
```r
Rscript -e 'devtools::test(filter = "nftab-class")'
Rscript -e 'devtools::test(filter = "schema")'
Rscript -e 'devtools::test(filter = "encoding")'
Rscript -e 'devtools::test(filter = "resolution")'
Rscript -e 'devtools::test(filter = "io")'
Rscript -e 'devtools::test(filter = "concat")'
Rscript -e 'devtools::test(filter = "validation")'
Rscript -e 'devtools::test(filter = "grammar")'
Rscript -e 'devtools::test(filter = "compute")'
```

### Common Patterns
- All S3 constructors validate their arguments eagerly with `stopifnot()` and explicit `stop()` calls (no early-return silencing).
- `nf_col()` returns an `nf_column_ref` object to distinguish "get value from this observation table column" from a literal value in encoding bindings.
- `ValueSource` fields in encodings can be either a literal or an `nf_column_ref` — always resolve with `resolve_value_source()`.
- `columns` encoding is only valid for 1D logical features (spec v0.1 constraint enforced in `nf_feature()`).
- NIfTI selector `index.t` is **0-based** per spec; neuroim2/RNifti are 1-based — always add `+1L` when dispatching.

## Dependencies

### Internal
- `src/` — C++ helpers via Rcpp (nifti operations)

### External
- **Imports**: `yaml` (manifest parsing), `jsonlite` (JSON, selector parsing), `data.table` (fast table I/O), `digest` (checksums and fingerprints), `Rcpp`
- **Suggests**: `RNifti` (NIfTI backend fallback), `neuroim2` (preferred NIfTI backend), `jsonvalidate` (manifest schema validation), `arrow` (Parquet support)

<!-- MANUAL: -->
