# neurotabs — Product Requirements Document

**Version:** 0.1.0-draft **Date:** 2026-03-06 **Status:** Draft

------------------------------------------------------------------------

## 1. Problem Statement

Neuroimaging research produces collections of derived maps (statistical
maps, anatomical scans, ROI vectors) across subjects, conditions,
sessions, and sites. Today these collections exist as ad-hoc directories
of files with metadata scattered across spreadsheets, BIDS sidecars, and
in-memory data frames. There is no standard way to:

1.  Declare what a collection contains at the logical level (independent
    of file format)
2.  Query, group, and compare members using design metadata
3.  Concatenate collections from different studies or storage backends
4.  Hand a collection to downstream tools (viewers, statistical engines,
    ML pipelines) with a machine-readable contract

This forces every tool to re-invent file discovery, metadata joining,
and format detection.

## 2. Vision

**neurotabs** is two things:

1.  **NFTab** — a cross-language specification for row-oriented
    neuroimaging datasets, defining how observations, design metadata,
    and logical features relate, independent of storage backend.

2.  **neurotabs** (R package) — the reference implementation: read,
    write, validate, query, and manipulate NFTab datasets with a
    dplyr-like grammar.

The one-sentence version: *A row is an observation with design metadata
and one or more feature values; each feature value resolves, through a
declared representation, to a logical array with known semantics.*

## 3. Users and Use Cases

### Primary Users

| User | Need |
|----|----|
| **Neuroimaging researcher** | Organize multi-subject results, query by design variables, compute group summaries |
| **Tool developer** (R, Python, Rust) | Consume a declared dataset without writing format-specific glue |
| **Viewer / app** (Brainflow) | Receive a queryable set with alignment guarantees and provenance |
| **Data curator** | Validate, concatenate, and publish datasets with machine-checkable contracts |

### Core Use Cases

**UC-1: Import and browse.** Load a directory of NIfTI stat maps + a CSV
design table. Browse by subject, condition, group. Flip through members.

**UC-2: Cohort query.** Filter to `group == "patient" & age > 40`,
compute mean map, compare to matched controls.

**UC-3: Concatenate studies.** Two labs ran the same paradigm with
different scanners. Concatenate their NFTab datasets after verifying
logical schema compatibility.

**UC-4: Cross-language handoff.** An R script prepares an NFTab dataset.
A Rust viewer (Brainflow) reads the same `nftab.yaml` manifest, resolves
features, and renders them — no R dependency needed.

**UC-5: Feed a statistical engine.** Select a feature from an NFTab
dataset, resolve all rows to arrays, and hand the aligned set to fmrigds
for group-level meta-analysis.

**UC-6: Publish with provenance.** Export a self-contained NFTab package
(manifest + observation table + resources) that another researcher can
validate and reproduce.

## 4. Product Scope

### In Scope (v0.1)

| Component | Description |
|----|----|
| **NFTab specification** | Cross-language, normative document defining manifest, observation table, feature schema, encodings, resource registry, resolution algorithm, concatenation rules, and conformance levels |
| **R reference package** | Read, write, validate NFTab datasets; core data model; backend adapters; dplyr-style grammar |
| **table-package storage profile** | YAML/JSON manifest + CSV/TSV/Parquet observation table + external files |
| **Two encoding types** | `ref` (external resource + selector) and `columns` (inline scalar columns) |
| **NIfTI backend adapter** | Resolve `ref` encodings with `backend: nifti` to 3D/4D arrays via neuroim2 |
| **Concatenation** | Strict row-wise concatenation with schema compatibility checking |
| **Validation** | Structural and full conformance checking |

### Out of Scope (v0.1)

- HDF5, Zarr, Arrow backend adapters (future)
- Surface and connectivity feature kinds (spec allows them; adapters
  come later)
- Statistical reduction engine (lives in fmrigds)
- Viewer integration (Brainflow reads the spec directly)
- `inline` encoding type (future)
- Model matrix / design matrix construction

## 5. The NFTab Specification

The spec is the cross-language contract. It must be implementable by any
language that can parse YAML/JSON and read tabular data. The R package
is a reference implementation, not the canonical form.

### 5.1 Specification Deliverables

| Deliverable | Format | Audience |
|----|----|----|
| `spec/nftab-spec.md` | Prose with normative language (MUST/SHOULD/MAY) | Humans |
| `spec/nftab-manifest.schema.json` | JSON Schema for the manifest | Machines / validators |
| `spec/nftab-manifest.schema.yaml` | YAML rendering of the same schema | Readability |
| `spec/examples/` | Complete minimal examples (faces-demo, roi-only, multi-encoding) | Both |
| `spec/backends/` | Non-normative conventions for `nifti`, `hdf5`, `zarr` selector syntax | Adapter implementers |

### 5.2 Specification Structure

The spec has seven normative sections:

#### S1. Abstract Data Model

    Dataset = Manifest + ObservationTable + Optional(ResourceRegistry)
    Observation = row_id + observation_axes + design columns + feature encoding columns
    Feature = logical schema + ordered encodings
    ResolvedFeature(row, feature) = first applicable encoding → logical value

#### S2. Manifest

Required fields: `spec_version`, `dataset_id`, `storage_profile`,
`observation_table`, `row_id`, `observation_axes`,
`observation_columns`, `features`.

Optional: `resources`, `extensions` (keys prefixed `x-`).

#### S3. Observation Table

- One row per observation.
- `row_id` MUST be unique.
- Tuple over `observation_axes` MUST be unique.
- If repeated measurements exist at the same grain, provider MUST add a
  distinguishing axis.

#### S4. Scalar Column Schema

Each design column declares: `dtype`, `nullable`, `semantic_role`
(optional), `levels` (optional), `unit` (optional).

Allowed dtypes: `string`, `int32`, `int64`, `float32`, `float64`,
`bool`, `date`, `datetime`, `json`.

Recommended semantic roles: `row_id`, `subject`, `session`, `run`,
`group`, `condition`, `contrast`, `site`, `covariate`.

#### S5. Feature Schema

Each feature declares:

- **Logical schema**: `kind`, `axes`, `dtype`, `shape`, `axis_domains`,
  `space`, `alignment`, `unit`
- **Encodings**: ordered list; first applicable wins per row

Logical kinds (descriptive, must not contradict axes): `array`,
`volume`, `vector`, `matrix`, `surface`.

Alignment levels: `same_grid`, `same_space`, `loose`, `none`.

Key constraint: `shape`, when present, must match `len(axes)`. Every
resolved value must conform to the logical schema.

#### S6. Feature Encodings

**ref encoding**: resolves from an external resource.

``` yaml
type: ref
binding:
  resource_id: <literal or {column: "col_name"}>
  backend: <literal or {column: "col_name"}>
  locator: <literal or {column: "col_name"}>
  selector: <literal or {column: "col_name"}>  # optional, JSON-compatible
  checksum: <literal or {column: "col_name"}>  # optional
```

Must provide either `resource_id` (looked up in registry) or both
`backend` + `locator`.

Selector syntax is backend-defined, must be pure data (no code
execution).

**columns encoding**: resolves from scalar observation table columns.

``` yaml
type: columns
binding:
  columns: ["roi_1", "roi_2", ..., "roi_68"]
```

Draft 0.1: columns encoding only for 1D logical features.

#### S7. Concatenation

Two datasets are strict-concatenation-compatible iff: - Same major
`spec_version` - Identical `observation_axes` (content and order) -
Identical feature name sets - Identical logical feature schemas
(excluding descriptive fields) - Compatible scalar column types (same
dtype or safe numeric promotion)

Concatenation is defined over logical schema, not physical encoding. Two
datasets using different backends for the same feature are compatible.

### 5.3 Resolution Algorithm

    for each encoding in feature.encodings (in order):
        if encoding is applicable to row:
            value = materialize(encoding, row, registry)
            validate(value, feature.logical)
            return value
    if feature.nullable: return MISSING
    else: ERROR nonconformant

### 5.4 Conformance Levels

**Dataset conformance:** - *Structurally conformant*: manifest valid,
tables present, uniqueness holds, schemas consistent. - *Fully
conformant*: structurally conformant AND every non-missing feature
resolves and validates.

**Reader conformance:** - *Core-conformant*: can parse manifest and
observation table, evaluate encoding applicability, resolve `columns`
encodings, report unsupported `ref` backends explicitly. - Readers are
NOT required to support every backend.

### 5.5 Versioning and Evolution

- Spec uses semantic versioning.
- Major version bumps indicate breaking changes to the abstract data
  model.
- Minor versions may add new optional fields, new encoding types, or new
  storage profiles.
- New `kind` values and `alignment` values may be added in minor
  versions.
- Backend-specific selector conventions are non-normative and versioned
  independently.

## 6. R Package Architecture

### 6.1 Package Identity

    Package: neurotabs
    Title: Neuro Feature Tables — Storage-Independent Neuroimaging Datasets
    Description: Reference implementation of the NFTab specification. Read, write,
        validate, and query row-oriented neuroimaging datasets with a dplyr-like
        grammar. Features resolve to logical arrays (volumes, ROI vectors, surfaces)
        independent of physical storage backend.
    License: MIT

### 6.2 Layer Diagram

    ┌─────────────────────────────────────────────────┐
    │  Grammar Layer                                  │
    │  nf_select() · nf_filter() · nf_group_by()     │
    │  nf_summarise() · nf_compare() · nf_collect()  │
    │  nf_mutate() · nf_arrange() · nf_drill()       │
    └───────────────┬─────────────────────────────────┘
                    │
    ┌───────────────▼─────────────────────────────────┐
    │  Core Data Model                                │
    │  nftab() · nf_manifest() · nf_feature()         │
    │  nf_observation_table() · nf_resource_registry() │
    │  nf_resolve() · nf_validate()                   │
    └───────────────┬─────────────────────────────────┘
                    │
    ┌───────────────▼─────────────────────────────────┐
    │  Backend Adapters                               │
    │  nifti · (hdf5) · (zarr) · columns             │
    └───────────────┬─────────────────────────────────┘
                    │
    ┌───────────────▼─────────────────────────────────┐
    │  I/O Layer                                      │
    │  nf_read() · nf_write() · nf_concat()           │
    │  nf_validate_dataset()                          │
    └─────────────────────────────────────────────────┘

### 6.3 Core Classes (S3)

#### `nftab` — the dataset object

``` r
nftab(
  manifest,            # nf_manifest object
  observations,        # data.frame / tibble
  resources = NULL,    # data.frame or NULL
  .root = NULL         # directory root for path resolution
)
```

This is the primary user-facing object. It prints a summary, supports
`[` subsetting, and flows into grammar verbs.

#### `nf_manifest` — parsed manifest

``` r
nf_manifest(
  spec_version,
  dataset_id,
  storage_profile = "table-package",
  row_id,
  observation_axes,
  observation_columns,  # named list of nf_col_schema
  features,             # named list of nf_feature
  resources = NULL
)
```

#### `nf_feature` — feature declaration

``` r
nf_feature(
  logical,     # nf_logical_schema
  encodings,   # list of nf_encoding
  nullable = FALSE
)
```

#### `nf_logical_schema` — what the feature IS

``` r
nf_logical_schema(
  kind,        # "volume", "vector", "matrix", "surface", "array"
  axes,        # character vector
  dtype,       # "float32", "float64", "int32", etc.
  shape = NULL,
  axis_domains = NULL,
  space = NULL,
  alignment = NULL
)
```

#### `nf_encoding` — how the feature is STORED

``` r
nf_ref_encoding(backend, locator, selector = NULL, resource_id = NULL, checksum = NULL)
nf_columns_encoding(columns)
```

### 6.4 Core Functions

| Function | Purpose |
|----|----|
| `nf_read(path)` | Read an NFTab dataset from a manifest file |
| `nf_write(x, path)` | Write an NFTab dataset to disk |
| `nf_validate(x, level = "structural")` | Validate conformance |
| `nf_resolve(x, row, feature)` | Resolve one feature value for one row |
| `nf_resolve_all(x, feature)` | Resolve all rows for a feature (returns list or array) |
| `nf_concat(a, b, ...)` | Strict row-wise concatenation |
| `nf_schema_fingerprint(feature)` | Hash of logical schema for compatibility checking |
| `nf_compatible(a, b)` | Check concatenation compatibility |

### 6.5 Grammar Verbs

The grammar operates on `nftab` objects and returns `nftab` objects (or
resolved arrays). Verbs are prefixed `nf_` to avoid conflicts with
dplyr.

| Verb | Operates on | Returns |
|----|----|----|
| `nf_select(x, ...)` | observation columns | nftab with fewer columns |
| `nf_filter(x, ...)` | rows via design predicates | nftab with fewer rows |
| `nf_group_by(x, ...)` | design columns | grouped_nftab |
| `nf_summarise(x, feature, .fn)` | grouped rows × feature | nftab with summary features |
| `nf_mutate(x, ...)` | design columns or derived features | nftab with new columns/features |
| `nf_arrange(x, ...)` | row order | reordered nftab |
| `nf_compare(x, feature, .ref, .fn)` | member vs reference | nftab with comparison features |
| `nf_collect(x, feature)` | resolve all rows for a feature | list of arrays or stacked array |
| `nf_drill(x, summary_row)` | summary back to members | nftab of contributing rows |

#### Grammar examples

``` r
# Filter and collect
nf_filter(ds, group == "control", age > 30) |>
  nf_collect("statmap")

# Group, reduce, compare
nf_group_by(ds, diagnosis) |>
  nf_summarise("statmap", .fn = "mean") |>
  nf_compare("statmap", .ref = "control", .fn = "subtract")

# Cohort relative view
nf_compare(ds, "statmap",
  .ref = nf_matched_cohort(ds, match_on = c("site", "sex", "age_band")),
  .fn = "zscore"
)

# Pivot-style matrix
nf_group_by(ds, diagnosis, contrast) |>
  nf_summarise("statmap", .fn = "mean")
# → one row per diagnosis × contrast cell, each with a mean volume
```

### 6.6 Backend Adapter Interface

Adapters are registered functions that know how to materialize a `ref`
encoding.

``` r
nf_register_backend(
  name,           # e.g., "nifti"
  resolve_fn,     # function(locator, selector, logical_schema) → array
  detect_fn = NULL  # optional: can this backend handle a given locator?
)
```

The package ships with: - `nifti` backend (via RNifti or neuroim2) -
`columns` encoding is handled directly (no backend needed)

Future backends (separate packages or later versions): `hdf5`, `zarr`,
`arrow`.

### 6.7 Interop with fmrigds

``` r
# NFTab → GDS plan
as_gds.nftab <- function(x, feature = NULL, ...) {

  # Select a volume feature with same_grid alignment

  # Resolve observation_axes to GDS axes (subject, contrast)
  # Return a gds_plan that reads from the NFTab
}

# GDS → NFTab
as_nftab.gds <- function(x, ...) {
  # Each assay becomes a feature column
  # GDS axes become observation_axes
  # Returns an nftab object
}
```

This is a soft dependency — neurotabs Suggests fmrigds, not Imports.

### 6.8 Dependencies

**Imports:** yaml, jsonlite, data.table (or tibble) **Suggests:**
RNifti, neuroim2, jsonvalidate, arrow, fmrigds, testthat, knitr

Kept minimal so the core is lightweight.

## 7. File Layout

    neurotabs/
    ├── DESCRIPTION
    ├── NAMESPACE
    ├── R/
    │   ├── nftab-class.R          # nftab, nf_manifest, nf_feature constructors
    │   ├── schema.R               # nf_logical_schema, nf_col_schema
    │   ├── encoding.R             # nf_ref_encoding, nf_columns_encoding
    │   ├── resolution.R           # nf_resolve, nf_resolve_all
    │   ├── validation.R           # nf_validate, conformance checks
    │   ├── io.R                   # nf_read, nf_write
    │   ├── concat.R               # nf_concat, nf_compatible, nf_schema_fingerprint
    │   ├── grammar.R              # nf_filter, nf_group_by, nf_summarise, etc.
    │   ├── compare.R              # nf_compare, nf_matched_cohort
    │   ├── backend-registry.R     # nf_register_backend, adapter dispatch
    │   ├── backend-nifti.R        # NIfTI adapter
    │   ├── interop-fmrigds.R      # as_gds.nftab, as_nftab.gds
    │   └── print.R                # print/format methods
    ├── inst/
    │   └── examples/
    │       ├── faces-demo/
    │       │   ├── nftab.yaml
    │       │   ├── observations.csv
    │       │   ├── resources.csv
    │       │   └── roi_labels.tsv
    │       └── roi-only/
    │           ├── nftab.yaml
    │           └── observations.csv
    ├── spec/
    │   ├── nftab-spec.md                 # prose specification
    │   ├── nftab-manifest.schema.json    # JSON Schema
    │   ├── nftab-manifest.schema.yaml    # YAML rendering
    │   ├── backends/
    │   │   ├── nifti.md                  # NIfTI selector conventions
    │   │   ├── hdf5.md                   # HDF5 selector conventions
    │   │   └── zarr.md                   # Zarr selector conventions
    │   └── examples/
    │       ├── faces-demo.yaml
    │       ├── roi-only.yaml
    │       └── multi-encoding.yaml
    ├── tests/
    │   └── testthat/
    │       ├── test-manifest.R
    │       ├── test-schema.R
    │       ├── test-encoding.R
    │       ├── test-resolution.R
    │       ├── test-validation.R
    │       ├── test-io.R
    │       ├── test-concat.R
    │       ├── test-grammar.R
    │       └── test-backend-nifti.R
    └── vignettes/
        ├── introduction.Rmd
        ├── nftab-spec-guide.Rmd
        └── grammar.Rmd

## 8. Phasing

### Phase 1: Core (MVP)

Spec + data model + I/O + validation + NIfTI backend.

Deliverables: - `spec/nftab-spec.md` — complete prose spec -
`spec/nftab-manifest.schema.json` — JSON Schema - Core R classes:
`nftab`, `nf_manifest`, `nf_feature`, `nf_logical_schema`,
`nf_encoding` -
[`nf_read()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_read.md)
/
[`nf_write()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_write.md)
for table-package profile -
[`nf_resolve()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_resolve.md)
/
[`nf_resolve_all()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_resolve_all.md)
with NIfTI backend -
[`nf_validate()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_validate.md)
at structural and full conformance levels -
[`nf_concat()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_concat.md)
with compatibility checking - Basic
[`nf_filter()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_filter.md)
and
[`nf_collect()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_collect.md) -
Tests and one vignette

Exit criteria: can round-trip a faces-demo dataset, resolve NIfTI
volumes and CSV-column ROI vectors, validate conformance, concatenate
two compatible datasets.

### Phase 2: Grammar

Full dplyr-style verbs.

Deliverables: -
[`nf_group_by()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_group_by.md),
[`nf_summarise()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_summarize.md),
[`nf_compare()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_compare.md),
[`nf_mutate()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_mutate.md),
[`nf_arrange()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_arrange.md),
[`nf_drill()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_drill.md) -
[`nf_matched_cohort()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_matched_cohort.md)
for dynamic reference groups - Reducer functions: mean, variance,
median, prevalence, sign consistency - Derived feature caching - Grammar
vignette

Exit criteria: can express `select → group → reduce → compare → drill`
pipeline.

### Phase 3: Interop and Ecosystem

Deliverables: - `as_gds()` / `as_nftab()` bridge to fmrigds - HDF5
backend adapter - Zarr backend adapter - `nf_explain_region()` — rank
design variables by spatial variability - Tidy export:
`as.data.frame.nftab()`, `as_tibble.nftab()` - Additional vignettes

### Phase 4: Advanced

- Surface feature resolution
- Connectivity matrix features
- Similarity / embedding lens
- Model lens (coefficient maps, partial residuals)
- Brainflow integration helpers (export for Rust/WASM consumption)

## 9. Cross-Language Implementability

The spec is designed so that any language can implement a
core-conformant reader:

| Requirement | Why it’s achievable |
|----|----|
| Parse YAML/JSON manifest | Every language has YAML/JSON parsers |
| Parse CSV/TSV/Parquet observation table | Universal tabular formats |
| Evaluate encoding applicability | Simple null-checking logic |
| Resolve `columns` encoding | Index into table columns |
| Resolve `ref` encoding | Backend-specific; only need to support backends you care about |
| Check concatenation compatibility | Compare schema fingerprints |

A Rust implementation (for Brainflow) needs only: YAML parser, CSV
reader, NIfTI reader. No R dependency.

A Python implementation needs only: PyYAML, pandas, nibabel.

The JSON Schema (`nftab-manifest.schema.json`) enables validation in any
language with a JSON Schema library.

## 10. Relationship to Existing Standards

| Standard | Relationship |
|----|----|
| **BIDS** | NFTab can describe BIDS derivatives. observation_axes might be `[subject, session, run, contrast]`. Locators can be BIDS-relative paths. NFTab does not replace BIDS; it provides a queryable, typed overlay. |
| **BIDS Stats Model** | NFTab stores semantic design columns, not a committed statistical model. A BIDS Stats Model produces outputs that NFTab can describe. |
| **NIfTI** | One of several backends. NFTab adds the logical layer above it. |
| **HDF5 / Zarr** | Future backends. NFTab doesn’t compete with them; it indexes into them. |
| **AnnData / SummarizedExperiment** | Similar philosophy (observations × features with metadata). NFTab is specialized for neuroimaging features that resolve to spatial arrays, not flat matrices. |
| **fmrigds (GDS)** | NFTab is more general; GDS is more statistical. They compose: NFTab feeds GDS. |

## 11. Success Metrics

| Metric | Target |
|----|----|
| Can round-trip a 50-subject NFTab dataset (read → query → write) | Phase 1 |
| Can concatenate datasets from two different storage backends | Phase 1 |
| Brainflow can read an NFTab manifest without R | Phase 1 (spec + examples) |
| Grammar pipeline feels as natural as dplyr for 5 common workflows | Phase 2 |
| fmrigds can consume an NFTab dataset via `as_gds()` | Phase 3 |
| A Python reader exists (community or first-party) | Phase 3+ |

## 12. Open Questions

1.  **Verb prefix**: `nf_` vs `nt_` vs bare names with `.nftab` methods?
    Using `nf_` for now to avoid dplyr conflicts.

2.  **Grouped summaries that produce volumes**: When
    [`nf_summarise()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_summarize.md)
    computes a mean volume per group, the result is a new nftab where
    each row is a group and the feature is a derived volume. Should
    derived volumes be materialized to disk or held in memory? (Answer:
    tiered — small results in memory, large results cached to temp
    files.)

3.  **Column-name stability**: Should
    [`nf_filter()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_filter.md)
    use tidy evaluation (NSE) or explicit column references? (Leaning
    toward tidy eval for ergonomics, with a `.data` pronoun for safety.)

4.  **Parquet as primary?**: CSV is the simplest on-ramp, but Parquet
    handles typed columns and nested arrays better. Should Phase 1
    support both? (Answer: yes, Parquet via arrow Suggests.)

5.  **How opinionated about neuroim2?**: The NIfTI backend could use
    RNifti (lighter) or neuroim2 (richer spatial metadata). (Answer:
    support both; prefer neuroim2 when available for richer
    NeuroVol/NeuroSpace objects.)
