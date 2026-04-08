<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-07 | Updated: 2026-04-07 -->

# tests/

## Purpose
Test suite for the neurotabs package. Contains the testthat unit/integration tests and conformance fixture datasets used to verify structural and full conformance validation.

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `testthat/` | All test files and test helpers (see `testthat/AGENTS.md`) |
| `fixtures/` | Minimal NFTab datasets (valid and intentionally invalid) for conformance testing (see `fixtures/AGENTS.md`) |

## For AI Agents

### Working In This Directory
- All tests use testthat edition 3 (`Config/testthat/edition: 3` in DESCRIPTION).
- Run with: `Rscript -e 'devtools::test()'`
- Use filters for targeted runs: `Rscript -e 'devtools::test(filter = "<name>")'`

### Testing Requirements
| Filter | What it covers |
|--------|---------------|
| `nftab-class` | Core constructors and accessors |
| `schema` | `nf_col_schema`, `nf_logical_schema`, `nf_support`, fingerprinting |
| `encoding` | `nf_ref_encoding`, `nf_columns_encoding`, applicability |
| `resolution` | `nf_resolve`, `nf_resolve_all`, checksum validation |
| `io` | `nf_read`, `nf_write`, manifest parsing, dtype coercion |
| `concat` | `nf_concat`, `nf_compatible`, resource deduplication |
| `validation` | `nf_validate` structural + full, extensions |
| `grammar` | `nf_filter`, `nf_select`, `nf_arrange`, `nf_collect`, `nf_group_by` |
| `compute` | Group summaries, derived features |
| `backend-nifti` | NIfTI backend adapter |
| `conformance-fixtures` | Round-trip validation of all fixture datasets |

## Dependencies

### Internal
- `fixtures/` — fixture datasets read by conformance tests
- `R/` — all package source under test

### External
- `testthat` (>= 3.0.0)

<!-- MANUAL: -->
