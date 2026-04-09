# Brainflow / NFTab Implementation Plan

**Status:** Ready for implementation planning **Date:** 2026-03-07

## Goal

Turn the cleaned NFTab support model into a consistent implementation
across the reference R package, bundled schema assets, examples, tests,
and the Brainflow consumer contract.

The model is now:

- exact support equality via `support_ref` -\> support entry -\>
  `support_id`
- operational compatibility via `alignment`
- volume direct-op boundary via `grid_id`
- surface direct-op boundary via `topology_id`

This plan assumes the schema is stable enough to implement and that
additional schema churn should be avoided unless implementation exposes
a real defect.

## Current State

The codebase is already partially aligned with the new model.

- `R/schema.R` already defines
  [`nf_support()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_support.md),
  [`nf_support_volume()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_support_volume.md),
  [`nf_support_surface()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_support_surface.md),
  `nf_logical_schema(support_ref = ...)`, and
  `nf_schema_fingerprint(..., support_id = ...)`.
- `R/nftab-class.R` already enforces support presence when features
  declare `support_ref`.
- `R/validation.R` already validates `volume` / `surface` support
  requirements and invalid `alignment` / `kind` combinations.
- `R/io.R` already parses and serializes `support_id` and `support_ref`.
- `R/concat.R` already fingerprints logical schemas with exact
  `support_id`.

The remaining work is mostly synchronization, fixture refresh, test
hardening, and Brainflow-facing implementation planning.

## Workstreams

### 1. Bundle And Ship The New Schema

Objective: make the package validator use the same manifest schema that
now lives in `spec/`.

Files:

- `spec/nftab-manifest.schema.json`
- `inst/schema/nftab-manifest.schema.json`
- `R/io.R`

Tasks:

- Copy the updated schema in `spec/` to `inst/schema/`.
- Confirm the bundled schema still validates manifests through
  [`nf_read()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_read.md).
- Keep `spec/` as the editable source of truth and `inst/schema/` as the
  packaged runtime copy.

Acceptance:

- `nf_read(validate_schema = TRUE)` validates against the shipped
  schema.
- No divergence remains between `spec/nftab-manifest.schema.json` and
  `inst/schema/nftab-manifest.schema.json`.

### 2. Refresh Example Manifests And Fixtures

Objective: make all shipped examples and test fixtures speak the new
support language.

Files:

- `inst/examples/faces-demo/nftab.yaml`
- `inst/examples/roi-only/nftab.yaml`
- `tests/fixtures/**/nftab.yaml`
- `tests/testthat/helper-make-nftab.R`

Tasks:

- Update the volume example to declare `supports`, `support_ref`,
  `support_id`, and `grid_id`.
- Leave ROI-only examples support-free to preserve the “optional for
  non-spatial datasets” path.
- Add or refresh invalid fixtures for:
  - missing `supports` when `support_ref` is present
  - missing `grid_id` for volume support
  - unknown `support_ref`
  - invalid `same_topology` on volume features
  - invalid `same_grid` on surface features

Acceptance:

- Every shipped example is internally consistent with the current spec.
- Fixture names map directly to one structural rule each.

### 3. Harden Compatibility Tests

Objective: lock in the identity-vs-compatibility split so it cannot
regress.

Files:

- `R/concat.R`
- `tests/testthat/test-concat.R`
- `tests/testthat/test-schema.R`
- `tests/testthat/test-validation.R`

Tasks:

- Add tests showing that exact support equality is driven by
  `support_id`.
- Add tests showing that operational compatibility is not the same as
  exact equality.
- Add tests for volume features on different `support_id` values but
  identical logical shape and `alignment`; these must remain
  incompatible for strict concatenation.
- Add tests for same-grid and same-topology invalid kind combinations.
- Improve
  [`nf_compatible()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_compatible.md)
  failure reasons where needed so support mismatches are obvious.

Acceptance:

- Support identity changes alter the schema fingerprint.
- [`nf_compatible()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_compatible.md)
  reports support-aware incompatibilities clearly.
- Strict concatenation cannot silently merge spatial features with
  different exact supports.

### 4. Sync Public Documentation And Man Pages

Objective: remove the drift between the code, the spec, and generated
package docs.

Files:

- `R/schema.R`
- `R/nftab-class.R`
- `man/nf_logical_schema.Rd`
- `man/nf_support*.Rd`
- `man/nf_manifest.Rd`
- `man/nf_schema_fingerprint.Rd`
- `docs/reference/*.md`
- `PRD.md`

Tasks:

- Regenerate man pages from the current roxygen comments.
- Regenerate reference docs so they show `support_ref`, `support_id`,
  `same_topology`, and the new support constructors accurately.
- Update `PRD.md` so the feature-schema section reflects the
  post-cleanup model.
- Keep `same_space` described as “shared frame, direct ops not
  guaranteed.”

Acceptance:

- Public docs match the current exported function signatures.
- The PRD no longer describes the old alignment-only model.

### 5. Brainflow Consumer Contract

Objective: give Brainflow a small, stable interpretation layer for
ingestion and Set Studio operations.

Deliverable:

- one short markdown contract, ideally checked into the repo, that says
  how a consumer should interpret NFTab support metadata

Required rules:

- exact support equality: compare `support_id`
- direct voxelwise operations: require volume support with identical
  `grid_id`
- direct vertexwise operations: require surface support with identical
  `topology_id`
- `same_space`: treat as shared frame only; resampling or projection may
  still be required
- non-spatial datasets may omit `supports`

Acceptance:

- Brainflow ingestion can be implemented without inventing a parallel
  manifest model.
- Set Studio fast paths can be gated from NFTab data alone.

## Suggested Bead Decomposition

### Bead 1: Schema Runtime Sync

Scope:

- sync `spec/` schema into `inst/schema/`
- verify
  [`nf_read()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_read.md)
  uses the updated bundle

Outputs:

- updated bundled schema asset
- one smoke test for schema-backed read

### Bead 2: Example And Fixture Refresh

Scope:

- update example manifests
- add invalid fixtures for support rules

Outputs:

- refreshed `inst/examples/`
- refreshed `tests/fixtures/`

### Bead 3: Support-Aware Compatibility Tests

Scope:

- exact support equality tests
- operational compatibility tests
- clearer incompatibility reasons

Outputs:

- updated `test-concat.R`
- updated `test-schema.R`
- updated `test-validation.R`

### Bead 4: Doc / PRD Sync

Scope:

- roxygen/man regeneration
- reference doc refresh
- PRD wording update

Outputs:

- current man pages
- current reference docs
- current `PRD.md`

### Bead 5: Brainflow Ingestion Contract

Scope:

- write the consumer-side interpretation rules
- keep it shorter than the full spec

Outputs:

- one markdown contract for Brainflow / Set Studio implementers

## Recommended Execution Order

1.  Bead 1
2.  Bead 2
3.  Bead 3
4.  Bead 4
5.  Bead 5

This order locks the runtime contract first, then examples and tests,
then docs, then the Brainflow-facing handoff.

## Definition Of Done

Implementation planning is complete when:

- the packaged schema matches the spec
- examples and fixtures all encode the current support model
- compatibility tests cover exact equality vs operational compatibility
- public docs no longer describe the old model
- Brainflow has a short ingestion contract that does not require a
  parallel manifest format
