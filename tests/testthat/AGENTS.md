<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-07 | Updated: 2026-04-07 -->

# tests/testthat/

## Purpose
All testthat test files and shared test helpers. Tests are organized one-to-one with source modules. Helper files define shared fixtures and factory functions used across multiple test files.

## Key Files

| File | Description |
|------|-------------|
| `helper-fixtures.R` | Loads conformance fixture datasets from `tests/fixtures/` for use in tests |
| `helper-make-nftab.R` | Factory functions for building minimal valid `nftab` objects in tests |
| `test-nftab-class.R` | Tests for `nftab()`, `nf_manifest()`, `nf_feature()`, accessors, `[.nftab` |
| `test-schema.R` | Tests for `nf_col_schema()`, `nf_logical_schema()`, `nf_support*()`, `nf_schema_fingerprint()` |
| `test-encoding.R` | Tests for `nf_ref_encoding()`, `nf_columns_encoding()`, `encoding_applicable()` |
| `test-resolution.R` | Tests for `nf_resolve()`, `nf_resolve_all()`, checksum validation, dtype coercion |
| `test-io.R` | Tests for `nf_read()`, `nf_write()`, manifest round-trips, dtype coercion edge cases |
| `test-concat.R` | Tests for `nf_concat()`, `nf_compatible()`, resource ID deduplication, dtype promotion |
| `test-validation.R` | Tests for `nf_validate()` at structural and full levels, extension validation |
| `test-grammar.R` | Tests for `nf_filter()`, `nf_select()`, `nf_arrange()`, `nf_collect()`, `nf_group_by()` |
| `test-compute.R` | Tests for compute operations, group summaries, derived feature materialization |
| `test-backend-nifti.R` | Tests for NIfTI backend adapter (3D/4D, neuroim2/RNifti, 0-based selector) |
| `test-conformance-fixtures.R` | Parametric tests over all fixture datasets in `tests/fixtures/` |

## For AI Agents

### Working In This Directory
- `helper-*.R` files are sourced automatically by testthat before test files run.
- Use `helper-make-nftab.R` factories instead of constructing full `nftab` objects inline — keeps tests concise and resilient to constructor changes.
- Conformance fixture tests in `test-conformance-fixtures.R` iterate over `tests/fixtures/` — adding a new fixture directory automatically includes it.
- Do not add `library()` calls inside test files; the package is loaded via `devtools::test()`.

### Testing Requirements
```r
# Run a single test file
Rscript -e 'devtools::test(filter = "grammar")'

# Run all tests
Rscript -e 'devtools::test()'
```

### Common Patterns
- Use `expect_error(..., class = ...)` to test for specific error conditions from constructors.
- NIfTI backend tests may skip if neither `RNifti` nor `neuroim2` is available — use `testthat::skip_if_not_installed()`.
- For I/O tests, use `withr::local_tempdir()` to create ephemeral directories instead of writing to fixed paths.

## Dependencies

### Internal
- `tests/fixtures/` — conformance datasets
- `R/` — all package source

### External
- `testthat` (>= 3.0.0)
- `withr` (for temporary directory helpers)

<!-- MANUAL: -->
