# Neuro Feature Table (NFTab) Specification

**Version:** 0.1.0
**Status:** Draft
**Date:** 2026-03-06

---

## 1. Scope

NFTab defines a storage-independent contract for row-oriented neuroimaging data.

An NFTab dataset represents a table of observations. Each row corresponds to one
observation at a declared grain — such as one subject-condition image, one
subject-session anatomy, or one subject-run ROI vector. Each row contains:

1. Scalar design metadata (subject, group, condition, session, age, site, etc.)
2. One or more feature values, where each feature resolves to a logical
   neuroimaging object (a 3D volume, an ROI vector, a surface scalar field, etc.)

NFTab standardizes:

- The observation table
- The logical schema of each feature
- How a row resolves to a feature value
- Compatibility rules for concatenation

NFTab distinguishes feature identity from support identity:

- A feature describes what the resolved value type is.
- A support describes the domain the feature lives on (volumetric grid, surface
  topology, etc.).

NFTab does not standardize:

- One required physical backend
- One required container format for large arrays
- One required statistical model matrix
- Backend-specific selector syntax beyond the core contract

The design matrix used for modeling is out of scope. NFTab stores semantic
design columns, not a committed model parameterization.

## 2. Normative Language

The key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
RECOMMENDED, MAY, and OPTIONAL in this document are to be interpreted as
described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

## 3. Abstract Data Model

An NFTab dataset consists of:

- One manifest
- One observation table
- Zero or one resource registry
- Zero or more external resources referenced by rows

Conceptually:

```
Dataset
  = Manifest
  + ObservationTable
  + Optional(ResourceRegistry)

Observation
  = row_id
  + observation_axes values
  + scalar design columns
  + feature encoding columns

Feature
  = logical schema
  + support reference
  + one or more ordered encodings

ResolvedFeature(row, feature)
  = the logical feature value obtained by applying the first
    applicable encoding for that row
```

A row encodes a feature through one of the feature's declared encodings. The
encoding may reference a loose file, a subobject inside a container, or an
ordered set of scalar table columns.

## 4. Manifest

The manifest is the normative description of the dataset.

### 4.1 Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `spec_version` | string | Semantic version of the NFTab spec |
| `dataset_id` | string | Identifier of the dataset within its package |
| `storage_profile` | string | Serialization profile identifier |
| `observation_table` | object | Reference to the observation table |
| `observation_table.path` | string | Path to the observation table file |
| `observation_table.format` | string | Format: `csv`, `tsv`, or `parquet` |
| `row_id` | string | Name of the unique row identifier column |
| `observation_axes` | array of string | Ordered columns defining the observation grain |
| `observation_columns` | object | Map of column name → ScalarColumnSchema |
| `features` | object | Map of feature name → FeatureSchema |

### 4.2 Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `supports` | object | Optional exact support registry (`support_ref -> SupportSchema`); required whenever any feature declares `logical.support_ref` |
| `supports.<ref>` | object | Support descriptor keyed by manifest-local support reference |
| `primary_feature` | string | Optional default feature name for consumers |
| `import_recipe` | object | Optional metadata for regex/glob-derived manifests |
| `resources` | object | Reference to the resource registry table |
| `resources.path` | string | Path to the resource registry file |
| `resources.format` | string | Format: `csv`, `tsv`, or `parquet` |
| `extensions` | object | Extension data (keys MUST begin with `x-`) |

### 4.3 Manifest Constraints

- `spec_version` MUST be a semantic version string (e.g., `"0.1.0"`).
- `dataset_id` MUST identify the dataset within its package.
- `storage_profile` MUST identify the serialization profile. This specification
  defines `table-package`.
- `observation_table` MUST identify a table containing one row per observation.
- `row_id` MUST name a column declared in `observation_columns`.
- `observation_axes` MUST be a non-empty ordered list of column names, each
  declared in `observation_columns`.
- `observation_columns` MUST declare every scalar column that appears in the
  observation table, including columns used by feature encodings.
- `features` MUST contain at least one feature.
- `supports` is optional for datasets with only non-spatial features. A dataset
  with any feature that declares `logical.support_ref` MUST include `supports`.
- Every `logical.support_ref` value in `features` MUST reference a key in
  `supports`.
- Every `volume` or `surface` feature MUST declare `logical.support_ref`.
- If present, `primary_feature` MUST reference a key in `features`.
- `resources`, when present, MUST identify a table containing a resource
  registry.
- Extension keys MUST appear only inside the `extensions` object and MUST begin
  with `x-`.
- Readers MUST NOT reject a manifest solely because of unknown `extensions`
  entries whose keys begin with `x-`.
- Unknown top-level manifest keys MUST NOT be present.

## 5. Observation Table

The observation table contains one row per observation.

### 5.1 Required Row Properties

For every row:

- `row_id` MUST be present and non-null.
- `row_id` MUST be unique within the dataset.
- Every column named in `observation_axes` MUST be present and non-null.
- The tuple of values over `observation_axes` MUST be unique within the dataset.

If a provider has repeated measurements at the same apparent grain, the provider
MUST include an additional distinguishing axis (such as `run`, `replicate`, or
`version`) in `observation_axes`.

### 5.2 Column Ordering

The observation table MAY contain columns in any order. Column identity is by
name, not by position.

## 6. Scalar Column Schema

Each entry in `observation_columns` declares the schema of one column.

### 6.1 Fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `dtype` | string | Yes | — | Data type |
| `nullable` | boolean | No | `true` | Whether null values are permitted |
| `semantic_role` | string | No | — | Semantic role hint |
| `levels` | array of string | No | — | Allowed categorical values |
| `unit` | string | No | — | Unit of measurement |
| `description` | string | No | — | Human-readable description |

### 6.2 Allowed `dtype` Values

| Value | Description |
|-------|-------------|
| `string` | UTF-8 text |
| `int32` | 32-bit signed integer |
| `int64` | 64-bit signed integer |
| `float32` | 32-bit IEEE 754 float |
| `float64` | 64-bit IEEE 754 float |
| `bool` | Boolean |
| `date` | Calendar date (ISO 8601) |
| `datetime` | Date and time (ISO 8601) |
| `json` | Arbitrary JSON value stored as text |

### 6.3 Recommended `semantic_role` Values

| Value | Meaning |
|-------|---------|
| `row_id` | Unique row identifier |
| `subject` | Subject/participant identifier |
| `session` | Session identifier |
| `run` | Run/replicate number |
| `group` | Group assignment |
| `condition` | Experimental condition |
| `contrast` | Statistical contrast name |
| `site` | Acquisition site |
| `covariate` | Continuous covariate |

Readers MUST NOT require a controlled vocabulary beyond the roles they
understand. Unknown roles MUST be accepted without error.

## 7. Feature Schema

Each feature is defined independently of storage backend.

### 7.1 Fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `logical` | LogicalFeatureSchema | Yes | — | Logical schema |
| `logical.support_ref` | string | No | — | Reference to exact support descriptor |
| `encodings` | array of FeatureEncoding | Yes | — | Ordered encoding list |
| `nullable` | boolean | No | `false` | Whether missing values are permitted |
| `description` | string | No | — | Human-readable description |

A feature MUST declare one or more encodings in priority order.

A row resolves a feature by evaluating the feature's encodings in order and
selecting the first applicable encoding.

## 8. Logical Feature Schema

The logical schema declares what a resolved feature value IS, independent of
how it is stored.

### 8.1 Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `kind` | string | Yes | Descriptive kind |
| `axes` | array of string | Yes | Semantic axis names |
| `dtype` | string | Yes | Element data type |
| `support_ref` | string | No | Reference to exact support registry entry |
| `shape` | array of int | No | Expected dimensions |
| `axis_domains` | object | No | Axis label metadata |
| `space` | string | No | Named coordinate space |
| `alignment` | string | No | Operational compatibility class |
| `unit` | string | No | Unit of measurement |
| `description` | string | No | Human-readable description |

### 8.2 Constraints

- `axes` MUST be a non-empty array of strings. It defines the semantic
  dimensions of the resolved feature.
- `dtype` MUST be one of: `string`, `int32`, `int64`, `float32`, `float64`,
  `bool`, `uint8`, or `uint16`.
- `shape`, when present, MUST have the same length as `axes`. Every resolved
  value for this feature MUST match the declared shape exactly.
- `kind` is descriptive and MUST NOT contradict `axes`.
- `support_ref` identifies the exact support the feature is defined on.
- `support_ref` MUST be present for `volume` and `surface` logical kinds.
- `alignment` expresses operational compatibility across rows of the feature
  and MUST NOT be used as a support identity token.

### 8.3 Recommended `kind` Values

| Value | Typical `axes` | Description |
|-------|---------------|-------------|
| `volume` | `[x, y, z]` | 3D volumetric image |
| `vector` | `[roi]` or `[feature]` | 1D feature vector |
| `matrix` | `[i, j]` | 2D matrix (e.g., connectivity) |
| `surface` | `[vertex]` | Surface scalar field |
| `array` | any | Generic N-D array |

### 8.4 Axis Domains

`axis_domains` MAY describe the identity and labeling of each axis. Each entry
is keyed by axis name and MAY contain:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier for the label set (e.g., `"desikan68"`) |
| `labels` | string | Relative path to a label table (TSV with at least `index` and `label` columns) |
| `size` | integer | Expected axis length |
| `description` | string | Human-readable description |

Sparse volumetric data represented as a vector over a `voxel` axis MAY use an
extension to declare how vector positions map back to a 3D grid. See Appendix
C for the common `x-masked-volume` extension.

### 8.5 Alignment

`alignment` MAY be one of:

| Value | Meaning |
|-------|---------|
| `same_grid` | Volume values share the same `grid_id`. Direct voxelwise operations are valid. |
| `same_space` | Values are in the same named coordinate space but are not guaranteed to share the same grid or topology. |
| `same_topology` | Surface values share the same `topology_id`. Direct vertexwise operations are valid. |
| `loose` | Features are of the same logical kind but no direct spatial set operation is guaranteed. |
| `none` | Non-spatial feature, or no alignment claim. |

`alignment` is an operational compatibility class, not an exact support
identity. Exact support equality is expressed through `support_id` in the
referenced support entry.

If `alignment` is `same_grid`, then `shape` SHOULD be present and the referenced
support SHOULD be a volume support with a declared `grid_id`.

If `alignment` is `same_topology`, the referenced support SHOULD be a surface
support with a declared `topology_id`.

#### 8.6 Supports

`supports` is an optional top-level object keyed by manifest-local support
references. It becomes required whenever any feature declares
`logical.support_ref`. Because `volume` and `surface` features require
`logical.support_ref`, any dataset containing those feature kinds also requires
`supports`.

Each support has:

- `support_type` (volume, surface, generic)
- `support_id`
- optional `description`

`support_id` denotes exact support equality across manifests. Two features are
defined on the same exact support if and only if their referenced supports have
the same `support_id`.

Volume support MUST provide:

- `space`
- `grid_id`
- optional `affine_id`

For volumes:

- `space` identifies the named reference frame
- `grid_id` identifies the voxel lattice used for direct voxelwise operations
- `affine_id`, when present, names the transform convention if it is not
  already baked into `grid_id`

Surface support MUST provide:

- `template`
- `mesh_id`
- `topology_id`
- `hemisphere`

For surfaces:

- `template` identifies the surface family
- `mesh_id` identifies the coordinate embedding
- `topology_id` identifies the node order and adjacency used for direct
  vertexwise operations
- `hemisphere` identifies side-specific support

Examples:

```yaml
supports:
  fsavg-lh-ico4:
    support_type: surface
    support_id: fsaverage-ico4-left
    template: fsaverage
    mesh_id: fsaverage-ico4
    topology_id: fsaverage-ico4-164k
    hemisphere: left
  mni-152-2mm:
    support_type: volume
    support_id: mni152-2mm-grid-91x109x91
    space: MNI152NLin2009cAsym
    grid_id: mni152-2mm-voxel-grid
    affine_id: mni152-2mm-affine
```

## 9. Feature Encodings

A feature encoding maps a row to the logical feature value.

This specification defines two encoding types: `ref` and `columns`.

### 9.1 Value Sources

Some encoding fields may be given as literal values or as references to
observation table columns.

This specification uses two field-specific source forms:

- **StringValueSource**: either a literal string or an object
  `{"column": "<column_name>"}` that references an observation column whose
  row value is interpreted as a string.
- **JsonValueSource**: either a JSON literal value or an object
  `{"column": "<column_name>"}` that references an observation column whose
  row value is interpreted according to the column's declared `dtype`.

For `JsonValueSource`, the exact object form `{"column": "<column_name>"}` is
reserved for column reference. A literal JSON object with that exact shape is
therefore not representable inline and SHOULD instead be supplied through a
column.

### 9.2 `ref` Encoding

A `ref` encoding resolves a feature from an external or containerized resource.

```yaml
type: ref
binding:
  resource_id: StringValueSource   # optional
  backend: StringValueSource       # required unless resource_id is used
  locator: StringValueSource       # required unless resource_id is used
  selector: JsonValueSource        # optional
  checksum: StringValueSource      # optional
```

#### 9.2.1 `ref` Constraints

- A `ref` encoding MUST provide either:
  1. `resource_id`, OR
  2. Both `backend` and `locator`.
- If `resource_id` is used, a resource registry MUST be present, and that
  resource ID MUST resolve to a registered resource.
- `backend` identifies the adapter used to interpret the resource. Standard
  backend identifiers SHOULD be lowercase tokens (e.g., `nifti`, `hdf5`,
  `zarr`). Private backend identifiers SHOULD begin with `x-`.
- `locator` identifies the physical resource. It MAY be a relative path,
  absolute path, or URI. Relative paths MUST be resolved against the dataset
  root directory.
- `selector` is optional. When present, it MUST be JSON-compatible. It narrows
  the resource to the logical feature. A selector MAY reduce rank (e.g.,
  selecting one 3D frame from a 4D NIfTI).
- The selector syntax is backend-defined. It MUST be pure data and MUST NOT
  require code execution.
- The value obtained after applying `selector`, if present, MUST conform to
  the feature's logical schema.
- `checksum`, when present, MUST be a string-valued checksum token. Its
  algorithm is profile- or implementation-defined unless further constrained by
  a backend convention.

### 9.3 `columns` Encoding

A `columns` encoding resolves a feature from scalar observation table columns.

```yaml
type: columns
binding:
  columns: [string, ...]
```

#### 9.3.1 `columns` Constraints

In version 0.1, `columns` encoding is defined only for 1D logical features.

- The logical schema MUST have exactly one axis.
- `binding.columns` MUST be an ordered, non-empty array of column names.
- If logical `shape` is present, its single dimension MUST equal the number
  of bound columns.
- If logical `shape` is omitted, it is inferred as `[len(binding.columns)]`.
- For a row to use a `columns` encoding, all bound columns MUST be present
  and non-null. Partial nulls are not permitted.

This encoding is intended for fixed-length vectors such as ROI feature vectors.

## 10. Resource Registry

A dataset MAY provide a resource registry.

### 10.1 Registry Columns

In the `table-package` profile, the resource registry is a table with at least
these columns:

| Column | Required | Description |
|--------|----------|-------------|
| `resource_id` | Yes | Unique identifier |
| `backend` | Yes | Backend adapter identifier |
| `locator` | Yes | Path or URI to the resource |
| `checksum` | No | Integrity checksum |
| `media_type` | No | MIME type |
| `description` | No | Human-readable description |
| `metadata` | No | Additional metadata (JSON) |

### 10.2 Registry Constraints

- `resource_id` MUST be unique within the registry.
- `backend` and `locator` have the same meanings as in `ref` encoding
  (Section 9.2).
- If both the registry and a `ref` binding specify a `checksum` for the same
  resource, they MUST agree.

## 11. Resolution Algorithm

For a given dataset D, row r, and feature f, resolution proceeds as follows:

1. Let E₁ ... Eₙ be the ordered encodings of f.
2. For each encoding Eᵢ in order, determine whether it is **applicable** to
   row r:
   - Evaluate every bound source against row r.
   - For `ref`: the encoding is applicable if either:
     1. `resource_id` resolves to a non-null string, OR
     2. both `backend` and `locator` resolve to non-null strings.
     Optional fields such as `selector` and `checksum` MAY resolve to null and
     are then treated as absent.
   - For `columns`: all bound columns MUST be available and non-null.
3. Select the first applicable encoding.
4. If no encoding is applicable:
   - If `f.nullable` is `true`, the feature value is **missing**.
   - Otherwise, the dataset is **nonconformant**.
5. Resolve the encoding:
   - For `ref`: load the referenced resource and apply the `selector` if
     present.
   - For `columns`: construct the ordered vector from the listed columns.
6. Validate that the resolved value conforms to `f.logical`.
7. Return the resolved value.

If more than one encoding is applicable for the same row, the first applicable
encoding wins. Providers SHOULD populate at most one encoding per row. If
multiple encodings are populated, they SHOULD resolve to equivalent values.

## 12. Storage Profile: `table-package`

This specification defines one normative serialization profile: `table-package`.

### 12.1 Contents

A conforming `table-package` dataset MUST contain:

- One manifest file
- One observation table file
- Optionally, one resource registry file
- Zero or more referenced resource files

### 12.2 Rules

- The manifest SHOULD be named `nftab.yaml` or `nftab.json`.
- The observation table format MUST be one of: `csv`, `tsv`, `parquet`.
- The resource registry, if present, MUST use one of the same formats.
- Relative paths MUST be resolved against the directory containing the
  manifest.
- For CSV and TSV:
  - `json`-typed cells MUST contain valid JSON text.
  - The empty field denotes null.
  - Zero-length string values are not representable and SHOULD be avoided.
- Large arrays SHOULD be stored through `ref` encoding rather than as inline
  table cells.

### 12.3 Import recipe metadata

Regex/glob-assisted ingestion should emit an NFTab manifest and MAY persist
non-normative import metadata in `import_recipe`.

`import_recipe` SHOULD be used to record:

- `mode` (`glob` or `regex`)
- `pattern`
- `group_columns`

This keeps ad-hoc ingestion and durable manifests in the same conceptual path.

## 13. Compatibility and Concatenation

NFTab defines **strict row-wise concatenation**.

### 13.1 Compatibility Requirements

Two datasets A and B are strict-concatenation-compatible if and only if ALL
of the following hold:

1. A and B have the same major `spec_version`.
2. `A.observation_axes` and `B.observation_axes` are identical in content
   and order.
3. A and B define the same set of feature names.
4. For each shared feature name, the logical feature schemas are identical,
   except that descriptive fields (e.g., `description`) MAY differ.
   For spatial features, exact support equality is also required.
5. For each shared observation column name, scalar schemas are compatible.
6. Output rows can be assigned unique `row_id` values.
7. All resource locators in the concatenated output remain valid after
   rebasing or copying.

### 13.2 Scalar Column Compatibility

Shared scalar columns are compatible if:

- They have the same `dtype`, OR
- Both are numeric and promotable to a common numeric type
  (`int32` → `int64` → `float32` → `float64`).

### 13.3 Feature Compatibility

Feature compatibility is determined by the **logical schema only**, not by
physical encoding. Two datasets may use different encodings for the same
feature and still be compatible.

Exact support equality and operational compatibility are distinct:

- Exact support equality means the referenced supports have the same
  `support_id`.
- Operational compatibility describes what can be done directly without
  resampling or projection and is expressed through `alignment` together with
  support-type-specific fields such as `grid_id` and `topology_id`.

Operational compatibility classes are interpreted as follows:

- `same_grid`: direct voxelwise operations are valid when the features are
  volume features on supports with the same `grid_id`
- `same_topology`: direct vertexwise operations are valid when the features are
  surface features on supports with the same `topology_id`
- `same_space`: features share a coordinate frame but may still require
  resampling or projection before direct comparison or reduction

Strict row-wise concatenation requires exact support equality, not merely an
operationally compatible class.

The logical schema fingerprint consists of: `kind`, `axes`, `dtype`, `shape`,
`space`, `alignment`, `axis_domains`, `unit`, and the referenced exact
`support_id`. Two fingerprints MUST be identical for compatibility (excluding
`description`).

### 13.4 Concatenation Result

The concatenation result MUST:

- Append rows from A and B.
- Preserve or rewrite `row_id` values so they are unique.
- Union the observation columns (columns present in only one dataset are
  filled with null in the other).
- Union the encodings for each feature in declared order.
- Merge the resource registries.
- Preserve feature logical schemas unchanged.

If a `resource_id` collision occurs and the resources are not identical, the
writer MUST rename at least one `resource_id` and update all referencing rows.

Writers performing concatenation SHOULD add a provenance column such as
`source_dataset`.

Datasets with different feature name sets are not strict-concatenation-compatible
under version 0.1.

## 14. Conformance

### 14.1 Dataset Conformance

A dataset is **structurally conformant** if:

- Its manifest is valid according to this specification.
- Required tables are present and parseable.
- Row uniqueness constraints hold (`row_id` unique, `observation_axes` tuple
  unique).
- Feature schemas and encodings satisfy this specification.
- Cross-field semantic constraints not expressible in JSON Schema also hold,
  including:
  - `row_id` and every entry of `observation_axes` name declared observation
    columns.
  - Every observation-table column referenced from an encoding is declared in
    `observation_columns`.
  - `shape`, when present, has the same length as logical `axes`.
  - A feature using `columns` encoding has exactly one logical axis.
  - Every `volume` and `surface` feature declares `logical.support_ref`.
  - Every `logical.support_ref` resolves to a key in `supports`.
  - Every volume support declares `grid_id`.

A dataset is **fully conformant** if it is structurally conformant AND every
non-missing feature value can be resolved and validated against its logical
schema.

### 14.2 Reader Conformance

A reader is **core-conformant** if it can:

- Parse the manifest.
- Parse the observation table.
- Evaluate encoding applicability.
- Resolve `columns` encodings.
- Report unsupported `ref` backends explicitly (rather than failing silently).

A reader is NOT required to support every backend. Backend support is
reader-specific.

## 15. Security Considerations

- `selector` values MUST be pure data. Implementations MUST NOT evaluate
  selectors as code.
- `locator` values that are URIs SHOULD be validated before network access.
  Implementations SHOULD support a policy for restricting locator schemes
  (e.g., allowing only `file://` and relative paths).
- Implementations SHOULD validate checksums when available.

## 16. Future Extensions

The following are anticipated but not defined in version 0.1:

- `inline` encoding type for nested arrays in Parquet/Arrow/JSON.
- Additional storage profiles (e.g., `hdf5-package`, `zarr-package`).
- Feature-level transformations and derived feature declarations.
- Streaming / chunked resolution for very large datasets.

---

## Appendix A: Minimal Example

### Manifest (`nftab.yaml`)

```yaml
spec_version: "0.1.0"
dataset_id: "faces-demo"
storage_profile: "table-package"

observation_table:
  path: "observations.csv"
  format: "csv"

row_id: "row_id"
observation_axes: ["subject", "condition", "run"]
primary_feature: "statmap"

supports:
  mni-2mm:
    support_type: volume
    support_id: "mni152-2mm-grid-91x109x91"
    space: "MNI152NLin2009cAsym"
    grid_id: "mni-152-2mm-grid"
    affine_id: "mni-152-2mm-affine"

import_recipe:
  mode: glob
  pattern: "sub-{subject}/ses-{session}/stat-{run}.nii.gz"
  group_columns:
    - subject
    - session
    - run

observation_columns:
  row_id:
    dtype: string
    nullable: false
    semantic_role: row_id
  subject:
    dtype: string
    nullable: false
    semantic_role: subject
  group:
    dtype: string
    nullable: false
    semantic_role: group
  condition:
    dtype: string
    nullable: false
    semantic_role: condition
  run:
    dtype: int32
    nullable: false
    semantic_role: run
  stat_res:
    dtype: string
    nullable: true
  stat_sel:
    dtype: json
    nullable: true
  roi_1:
    dtype: float32
    nullable: true
  roi_2:
    dtype: float32
    nullable: true
  roi_3:
    dtype: float32
    nullable: true

features:
  statmap:
    description: "3D statistical map"
    logical:
      kind: volume
      axes: ["x", "y", "z"]
      dtype: float32
      shape: [91, 109, 91]
      space: "MNI152NLin2009cAsym"
      support_ref: "mni-2mm"
      alignment: same_grid
    encodings:
      - type: ref
        binding:
          resource_id: { column: "stat_res" }
          selector: { column: "stat_sel" }

  roi_beta:
    description: "ROI feature vector"
    logical:
      kind: vector
      axes: ["roi"]
      dtype: float32
      shape: [3]
      axis_domains:
        roi:
          id: "desikan3-demo"
          labels: "roi_labels.tsv"
    encodings:
      - type: columns
        binding:
          columns: ["roi_1", "roi_2", "roi_3"]

resources:
  path: "resources.csv"
  format: "csv"
```

### Observation Table (`observations.csv`)

```csv
row_id,subject,group,condition,run,stat_res,stat_sel,roi_1,roi_2,roi_3
r001,sub-01,control,faces,1,group4d,"{""index"":{""t"":12}}",0.31,0.44,0.29
r002,sub-02,control,faces,1,group4d,"{""index"":{""t"":13}}",0.28,0.39,0.33
```

### Resource Registry (`resources.csv`)

```csv
resource_id,backend,locator
group4d,nifti,maps/group_stats.nii.gz
```

Here, `statmap` is logically a 3D volume even though physically it is selected
from a 4D NIfTI.

## Appendix B: Backend Selector Conventions

These conventions are non-normative. They provide interoperability guidance for
common backends.

### B.1 NIfTI (`nifti`)

The NIfTI backend reads 3D or 4D NIfTI files (`.nii`, `.nii.gz`).

**Selector fields:**

| Field | Type | Description |
|-------|------|-------------|
| `index.t` | integer | Zero-based time/volume index into a 4D NIfTI |

When no selector is provided, the resource MUST be a 3D NIfTI matching the
logical schema.

**Example:** `{"index": {"t": 12}}` selects the 13th volume (0-indexed) from
a 4D NIfTI.

### B.2 HDF5 (`hdf5`)

**Selector fields:**

| Field | Type | Description |
|-------|------|-------------|
| `dataset` | string | HDF5 dataset path (e.g., `/data/beta`) |
| `slice` | object | Axis-keyed slice specifications |

**Example:** `{"dataset": "/subjects/sub-01/beta", "slice": {"t": 3}}`

### B.3 Zarr (`zarr`)

**Selector fields:**

| Field | Type | Description |
|-------|------|-------------|
| `array` | string | Zarr array path |
| `slice` | object | Axis-keyed slice specifications |

**Example:** `{"array": "beta", "slice": {"t": 3}}`

## Appendix C: Common Extension `x-masked-volume`

This appendix defines a common extension for sparse volumetric features whose
resolved value is a vector of in-mask voxels rather than a dense 3D array.

This extension is appropriate when:

- the logical feature is stored or resolved as a 1D vector over voxels
- all rows of that feature share the same covered voxel set
- readers need an explicit mapping from vector position back to 3D grid
  coordinates

It is **not** appropriate when each row has a different voxel support. In that
case, providers SHOULD model the support as a separate mask feature or use a
future row-varying extension.

### C.1 Placement

The extension lives in the manifest `extensions` object:

```yaml
extensions:
  x-masked-volume:
    features:
      <feature_name>: ...
```

### C.2 Intended Feature Shape

The referenced feature SHOULD have:

- `logical.kind: vector`
- `logical.axes: ["voxel"]`
- `logical.shape: [N]`, where `N` is the number of covered voxels

The feature MAY still declare `logical.space` and `logical.alignment` to state
the spatial frame in which those voxel coordinates live.

### C.3 Extension Fields

Each entry under `extensions.x-masked-volume.features` is keyed by feature name
and MAY contain:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `grid_axes` | array of string | Yes | Names of the underlying spatial axes, typically `["x", "y", "z"]` |
| `grid_shape` | array of int | Yes | Shape of the underlying dense voxel grid |
| `grid_index_base` | int | No | Either `0` or `1`; default `0` |
| `index_map` | object | Yes | Table reference describing which voxels are covered |
| `description` | string | No | Human-readable description |

`index_map` uses the same shape as a table reference:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | string | Yes | Relative path to the index map table |
| `format` | string | Yes | `csv`, `tsv`, or `parquet` |

### C.4 Index Map Requirements

The index map table MUST contain at least these columns:

| Column | Type | Meaning |
|--------|------|---------|
| `index` | integer | 1-based position in the resolved feature vector |
| `x` | integer | Voxel coordinate along `grid_axes[1]` |
| `y` | integer | Voxel coordinate along `grid_axes[2]` |
| `z` | integer | Voxel coordinate along `grid_axes[3]` |

Constraints:

- `index` MUST be unique and MUST cover `1..N` with no gaps.
- `N` MUST equal the feature's logical vector length when `logical.shape` is
  present.
- `x`, `y`, and `z` MUST lie within the declared `grid_shape`, interpreted
  according to `grid_index_base`.
- Extra columns MAY be present, for example anatomical labels or atlas parcel
  membership.

### C.5 Example

```yaml
features:
  statvec:
    logical:
      kind: vector
      axes: ["voxel"]
      dtype: float32
      shape: [3]
      space: "MNI152NLin2009cAsym"
      alignment: same_grid
    encodings:
      - type: columns
        binding:
          columns: ["v1", "v2", "v3"]

extensions:
  x-masked-volume:
    features:
      statvec:
        grid_axes: ["x", "y", "z"]
        grid_shape: [91, 109, 91]
        grid_index_base: 0
        index_map:
          path: "voxel_index.tsv"
          format: "tsv"
```

Example `voxel_index.tsv`:

```text
index	x	y	z
1	45	54	31
2	45	55	31
3	46	55	31
```

This extension says that `statvec[1]` corresponds to voxel `(45, 54, 31)`,
`statvec[2]` to `(45, 55, 31)`, and so on, in the declared spatial grid.
