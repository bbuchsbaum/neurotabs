# Exploratory Analysis V1

Status: proposed, non-normative design note.

Implementation status:

- initial package implementation is present
- `contrasts = "auto"` and `list(auto_max_order = ...)` are implemented
- `se_feature` is not yet implemented
- the current subject-blocked implementation supports a binary within-subject
  factor only

This document describes a convenience analysis layer inside `neurotabs` for
fast exploratory voxelwise or featurewise testing over aligned NFTab datasets.
It does not amend the NFTab specification and does not turn `neurotabs` into a
general statistical modeling engine.

The core boundary is:

- `neurotabs` MAY provide a fast exploratory analysis helper over NFTab data.
- `neurotabs` MUST NOT claim to implement general mixed models.
- Confirmatory modeling, rich random-effects structures, and full statistical
  workflows remain downstream concerns.

## Goals

- Provide a fast in-package way to test common design terms over an NFTab
  feature.
- Reuse the existing fast `columns` path and batched NIfTI traversal path.
- Return results as an `nftab`, so outputs remain writable, viewable, and
  compatible with the rest of the package.
- Support the common exploratory cases:
  - between-subject fixed effects
  - one within-subject factor with subject blocking
  - two-factor mixed design with one between-subject factor, one
    within-subject factor, and subject blocking

## Non-Goals

- No claim of full `lme4` compatibility.
- No random slopes.
- No crossed or nested random effects beyond a single subject intercept.
- No unbalanced repeated-measures inference in v1.
- No multiple-comparison correction in v1.
- No surface, connectivity, or arbitrary backend analysis in v1.
- No auto-generated simple-effects explosion in v1.

## Proposed API

```r
nf_analyze <- function(
  x,
  feature,
  formula,
  se_feature = NULL,
  contrasts = "auto",
  .progress = FALSE
)
```

Arguments:

- `x`: an `nftab`
- `feature`: numeric feature to analyze
- `formula`: right-hand-side-only formula, for example `~ group * condition`
  or `~ group * condition + (1 | subject)`
- `se_feature`: optional numeric feature containing per-row standard errors;
  v1 supports this only for independent-row fixed-effects mode
- `contrasts`: `"auto"` or a named list of explicit requests
- `.progress`: progress messages for slower generic paths

Notes:

- The formula has no response term; the response is always `feature`.
- The only supported random term syntax in v1 is exactly `(1 | subject_col)`.
- The analysis helper is exploratory. It SHOULD be documented as experimental.
- Subject identity SHOULD be discovered from the random term first, then from an
  observation column with semantic role `subject`, then from a literal column
  named `subject`.

## Supported Inputs

V1 accepts only:

- numeric 1D `columns` features
- volume features resolvable through the current NIfTI path

V1 rejects:

- nullable feature rows
- string or categorical features
- features that resolve to inconsistent shapes
- surface features
- generic `ref` backends without a fast resolver path

For volume analysis, the feature MUST reference a volume support with a declared
`grid_id`. If `alignment` is present, it SHOULD be `same_grid`.

## Analysis Modes

V1 has two estimator families.

### 1. Independent-Row Fixed Effects

Triggered when `formula` contains no random term.

Interpretation:

- each row is treated as an independent observation
- standard OLS is used when `se_feature = NULL`
- inverse-variance WLS is used when `se_feature` is supplied

Supported formula shapes:

- `~ A`
- `~ A + x1 + x2`
- `~ A * B`
- `~ A * B + x1`

where:

- `A`, `B` are factor columns in `nf_design(x)`
- `x1`, `x2` are numeric covariates

This mode is appropriate when rows are already subject-level summaries or are
otherwise independent for exploratory purposes.

Safety rule:

- if repeated subject rows are detected for the analyzed observations and the
  formula omits `(1 | subject)`, `nf_analyze()` SHOULD fail loudly rather than
  silently treating repeated measures as independent rows

### 2. Subject-Blocked Repeated Measures

Triggered when `formula` contains exactly one random term of the form
`(1 | subject)`.

Interpretation:

- the random term is not a general mixed-model fit
- it means: treat repeated rows from the same subject as a balanced
  repeated-measures design and use a fast subject-blocked estimator

Supported formula classes:

1. One-factor repeated measures:

```r
~ condition + (1 | subject)
```

2. Two-factor mixed design:

```r
~ group * condition + (1 | subject)
```

with:

- `group` constant within subject
- `condition` varying within subject

V1 rejects:

- more than one within-subject factor
- more than one between-subject factor in subject-blocked mode
- random slopes
- additional random terms
- missing subject-condition cells
- duplicate subject-condition cells after accounting for fixed factors unless
  they can be collapsed to a unique cell mean

## Formula Semantics

### Accepted Grammar

V1 supports:

- factor main effects
- numeric covariates in independent-row mode
- `*` expansion for supported factor structures
- one optional random intercept term `(1 | subject)`

V1 does not support:

- `/`, `||`, `:`, or custom random-effect structures beyond the single allowed
  `(1 | subject)` term
- offsets
- arbitrary transformation calls inside the formula

### Factor Handling

- unordered factors use their declared level order if present, otherwise the
  observed order
- omnibus term tests are computed at the term level and SHOULD be invariant to
  the full-rank coding choice
- explicit pairwise and treatment-vs-control requests use factor level order
- numeric covariates are allowed only in independent-row mode in v1

## Auto-Contrast Rules

`contrasts = "auto"` means:

- always generate omnibus main-effect tests
- always generate omnibus 2-way interaction tests
- never auto-generate 3-way or higher interaction tests
- never auto-generate all pairwise cell comparisons
- never auto-generate simple effects

Equivalent control:

```r
contrasts = list(auto_max_order = 2L)
```

Examples:

- `~ group * condition` produces:
  - `group`
  - `condition`
  - `group:condition`
- `~ A * B * C` produces:
  - `A`
  - `B`
  - `C`
  - `A:B`
  - `A:C`
  - `B:C`

### Explicit Contrast Requests

V1 SHOULD support a narrow explicit interface:

```r
contrasts = list(
  group = "pairwise",
  condition = "trt.vs.ctrl"
)
```

Supported values in v1:

- `"omnibus"`
- `"pairwise"` for a main-effect factor
- `"trt.vs.ctrl"` for an ordered main-effect factor

Deferred beyond v1:

- `"simple"`
- arbitrary user-written symbolic contrast DSLs
- 3-way interaction decomposition helpers

## Estimator Definitions

### Independent-Row OLS

For each voxel or feature element, fit:

```text
y = X b + e
```

where:

- `X` is shared across all voxels or feature elements
- `y` changes across voxels or elements

Implementation target:

- `columns` features: BLAS-backed matrix algebra
- volume features: streamed sufficient statistics without materializing the full
  `n_obs x n_voxels` matrix when avoidable

Term tests:

- rank-1 term: `t` test
- rank > 1 term: omnibus `F` test

### Independent-Row WLS

When `se_feature` is supplied, weights are:

```text
w = 1 / se^2
```

Rules:

- `se_feature` must resolve to the same logical shape as `feature`
- all `se` values must be finite and strictly positive
- WLS is supported only in independent-row mode in v1

### Subject-Blocked Repeated Measures

Subject-blocked mode uses a constrained repeated-measures estimator, not a full
mixed-model optimizer.

Algorithm sketch:

1. Collapse repeated rows to one mean map per unique repeated-measures cell.
2. Partition fixed factors into:
   - between-subject factors: constant within subject
   - within-subject factor: varies within subject
3. Build subject-level summaries:
   - between-subject tests use subject-level means across within-subject cells
   - within-subject and interaction tests use subject-level contrast-score maps
     derived from the within-subject factor levels
4. Fit shared-design OLS on those subject-level derived maps.

Interpretation by supported case:

- `~ condition + (1 | subject)`:
  - test whether subject-level condition contrast scores differ from zero
- `~ group * condition + (1 | subject)`:
  - `group`: test group effect on subject-level means
  - `condition`: test condition effect on subject-level contrast scores
  - `group:condition`: test group effect on subject-level contrast scores

This gives a fast exploratory subject-aware analysis for the common repeated
measures cases without claiming general random-effects support.

## Output Contract

`nf_analyze()` returns an `nftab`.

### Rows

Each row represents one test.

Required observation columns:

- `.row_id`
- `test_id`
- `term`
- `test_type`
- `stat_kind`
- `df_num`
- `df_den`
- `mode`
- `weighted`
- `contrast_spec`

Recommended values:

- `test_type`: `omnibus` or `contrast`
- `stat_kind`: `t` or `f`
- `mode`: `fixed` or `subject_block`
- `contrast_spec`: JSON string describing the generated or requested contrast

### Features

The result dataset SHOULD include:

- `stat`
- `p_value`

and MAY include:

- `estimate` for 1-df tests only
- `stderr` for 1-df tests in independent-row mode

Rules:

- omnibus tests with rank > 1 do not have a single signed effect estimate
- `estimate` MUST be omitted or set nullable for those rows
- result features preserve the same logical kind, shape, and support as the
  analyzed feature

Examples:

- volume input -> volume `stat` and `p_value` maps
- ROI-vector input -> 1D `columns`-encoded `stat` and `p_value`

## Validation Rules

`nf_analyze()` MUST fail with a clear error when:

- `feature` is unknown
- `feature` is non-numeric
- `formula` references unknown design columns
- unsupported random-effects syntax is present
- repeated subject rows are detected in independent-row mode
- subject-block mode is requested without a balanced complete repeated-measures
  structure
- a supposed between-subject factor varies within subject
- more than one within-subject factor is detected
- `se_feature` is supplied in subject-block mode
- `se_feature` shape does not match `feature`
- any resolved `se` value is non-finite or non-positive
- rows required for the design resolve to `NULL`
- the analysis would require direct spatial operations on an unsupported
  backend or incompatible shape

## Performance Expectations

V1 SHOULD preserve the current fast paths:

- use the `columns` matrix path when available
- reuse batched NIfTI traversal keyed by locator and selector
- avoid row-by-row `nf_resolve()` in fast paths
- stream sufficient statistics for volume features when possible

For large NIfTI datasets, the implementation SHOULD prefer accumulating
term-level sufficient statistics over materializing a dense
`n_obs x n_voxels` response matrix in memory.

## Implementation Notes

The current package already provides reusable pieces:

- `nf_design()` for the observation table
- `nf_collect()` for fast 1D collection
- `.nf_columns_plan()` for numeric `columns` features
- `.nf_eval_nifti_tasks()` for grouped NIfTI reads
- summary materialization back into `nftab`

The analysis implementation SHOULD build on those pieces rather than creating a
separate resolution engine.

## Deferred Work

Explicitly deferred beyond v1:

- full mixed-model fitting
- subject-block mode with `se_feature`
- Satterthwaite or Kenward-Roger approximations
- multiple within-subject factors
- random slopes
- surface analysis
- corrected `p` maps
- clusterwise inference
- arbitrary custom contrast languages

## Suggested User-Facing Positioning

Suggested wording for documentation:

> `nf_analyze()` provides fast exploratory term tests over aligned NFTab
> features. It supports fixed-effects models and a narrow subject-blocked
> repeated-measures mode via `(1 | subject)`. It is not a general mixed-model
> engine and should not be treated as a replacement for confirmatory modeling
> tools.
