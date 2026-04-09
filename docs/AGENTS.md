# neurotabs

## Purpose

Reference R implementation of the NFTab specification: a
storage-independent, row-oriented contract for neuroimaging datasets.
Each row is an observation with design metadata and one or more feature
values that resolve to logical arrays (volumes, ROI vectors, surfaces)
independent of physical storage backend. Think “dplyr for neuroimaging.”

## Key Files

| File | Description |
|----|----|
| `DESCRIPTION` | R package metadata; declares Imports (yaml, jsonlite, data.table, digest, Rcpp) and Suggests |
| `NAMESPACE` | Auto-generated exports — do not edit by hand |
| `PRD.md` | Product Requirements Document: use cases, spec structure, R architecture, and phasing |
| `IMPLEMENTATION_PLAN.md` | Implementation roadmap with phase details |
| `_pkgdown.yml` | pkgdown site configuration |
| `LICENSE` | MIT license |

## Subdirectories

| Directory | Purpose |
|----|----|
| `R/` | All R source files — core classes, grammar, backends, I/O (see `R/AGENTS.md`) |
| `src/` | C++ source via Rcpp — NIfTI operations (see `src/AGENTS.md`) |
| `tests/` | testthat suite and conformance fixtures (see `tests/AGENTS.md`) |
| `inst/` | Installed data: examples and bundled JSON Schema (see `inst/AGENTS.md`) |
| `spec/` | Normative NFTab specification prose and JSON Schema (see `spec/AGENTS.md`) |
| `vignettes/` | R Markdown vignettes (see `vignettes/AGENTS.md`) |
| `man/` | Auto-generated roxygen2 documentation — do not edit by hand |
| `docs/` | Auto-generated pkgdown site — do not edit by hand |
| `pkgdown/` | pkgdown customization files (CSS/JS) (see `pkgdown/AGENTS.md`) |

## For AI Agents

### Working In This Directory

- `neurotabs` is the reference implementation of the NFTab spec. Changes
  must stay aligned with both `PRD.md` and `spec/nftab-spec.md`.
- Prefer preserving logical-schema semantics over convenience. If code
  and spec diverge, fix the code or tighten the spec — do not paper over
  the mismatch.
- **Do not edit** `R/RcppExports.R`, `src/RcppExports.cpp`, `NAMESPACE`,
  or `man/*.Rd` by hand.
- After changing `src/*.cpp`: `Rscript -e 'Rcpp::compileAttributes()'`
- After changing roxygen comments in `R/*.R`:
  `Rscript -e 'devtools::document()'`

### Testing Requirements

- Targeted: `Rscript -e 'devtools::test(filter = "compute")'`
- Full suite before closing a substantive change:
  `Rscript -e 'devtools::test()'`
- See `AGENTS.md` in `tests/` for filter patterns.

### Architecture Overview

    Grammar Layer     nf_select · nf_filter · nf_group_by · nf_summarise · nf_collect
          ↓
    Core Data Model   nftab · nf_manifest · nf_feature · nf_resolve · nf_validate
          ↓
    Backend Adapters  nifti · (hdf5) · (zarr) · columns (inline)
          ↓
    I/O Layer         nf_read · nf_write · nf_concat · nf_validate_dataset

### Common Patterns

- All user-facing functions are prefixed `nf_` to avoid dplyr conflicts.
- S3 classes: `nftab`, `nf_manifest`, `nf_feature`, `nf_logical_schema`,
  `nf_encoding`, `nf_col_schema`, `nf_support_schema`, `grouped_nftab`.
- `columns` encoding is only valid for 1D logical features.
- `ref` encodings must validate against the declared logical schema
  after resolution.

## Dependencies

### Internal

All layers are defined in `R/`. C++ helpers live in `src/`.

### External

- **Imports**: `Rcpp`, `yaml`, `jsonlite`, `data.table`, `digest`
- **Suggests**: `testthat`, `RNifti`, `neuroim2`, `jsonvalidate`,
  `arrow`, `fmrigds`, `knitr`, `rmarkdown`

## Project focus

- Changes should stay aligned with both `PRD.md` and
  `spec/nftab-spec.md`.
- Prefer preserving logical-schema semantics over convenience. If code
  and spec diverge, fix the code or tighten the spec explicitly rather
  than papering over the mismatch.

## Compute layer expectations

- Keep the fast paths fast. For `columns` features, avoid row-by-row
  [`nf_resolve()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_resolve.md)
  when a direct matrix path is possible.
- For NIfTI-backed compute, preserve batching by file, cached slice
  extraction, and checksum validation once per unique locator.
- Nullable derived features are part of the contract. If a transform can
  yield `NULL`, materialization and resolution must preserve row
  alignment rather than dropping entries.

## Storage and backend rules

- `columns` encoding is only for 1D logical features.
- `ref` features must continue to validate against the declared logical
  schema after resolution or derived-feature materialization.
- Checksums are part of conformance. New resource-writing paths should
  populate checksums and keep locators resolvable from `.root`.

## Documentation and examples

- If user-facing behavior changes, update the relevant vignette or spec
  text in the same pass when practical.
- Packaged examples under `inst/examples` are part of the contract
  surface; keep them schema-valid and runnable.
