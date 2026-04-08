# Getting Started with neurotabs

`neurotabs` is the reference R implementation of the NFTab
specification. You use it to read an NFTab manifest, validate the
dataset contract, and resolve feature values without hard-coding storage
details into your analysis.

## What Problem Does neurotabs Solve?

Neuroimaging projects often end up as a directory of map files plus one
or more spreadsheets that describe subjects, conditions, runs, and
derived features. That works until you need to answer questions like:

- Which rows belong to the patient cohort?
- Which file or selector encodes the statistical map for this row?
- Are two study outputs compatible enough to concatenate safely?
- Can another tool read the dataset without re-implementing your
  file-discovery logic?

`neurotabs` addresses that problem by separating the logical dataset
contract from the physical storage. An NFTab manifest says what each row
means, what each feature is, and how a feature value resolves for that
row.

## When Should You Use It?

The package is most useful when your dataset is row-oriented and each
row has both design metadata and one or more neuroimaging features.

Typical Phase 1 use cases are:

1.  Read a collection of ROI vectors or statistical maps together with
    subject and condition metadata.
2.  Validate that the dataset is structurally well-formed before
    analysis or handoff to another tool.
3.  Resolve one feature across many rows without hard-coding column
    bundles, file paths, or selector logic.
4.  Concatenate compatible datasets from different studies or storage
    layouts.

## What Does An NFTab Dataset Look Like?

The package ships with a small ROI-only example that uses `columns`
encoding.

``` r
roi_path <- system.file("examples/roi-only/nftab.yaml", package = "neurotabs")
stopifnot(nzchar(roi_path))

roi_ds <- nf_read(roi_path)
roi_ds
#> <nftab> roi-only 
#>   8 observations x 1 features
#>   axes: subject, condition 
#>   features: roi_beta 
#>   subject: sub-01, sub-02, sub-03, sub-04
#>   condition: faces, houses
```

An `nftab` object keeps the parsed manifest, the observation table, and
any optional resource registry together. The manifest defines the
observation axes and the feature schemas:

``` r
nf_axes(roi_ds)
#> [1] "subject"   "condition"
nf_feature_names(roi_ds)
#> [1] "roi_beta"
```

## What Happens When You Read A Dataset?

[`nf_read()`](../reference/nf_read.md) does more than parse YAML. It
validates the manifest against the bundled JSON Schema, reads the
observation table, and coerces columns to the declared NFTab dtypes.

``` r
vapply(
  roi_ds$observations[c("row_id", "subject", "age", "roi_1")],
  function(x) paste(class(x), collapse = "/"),
  character(1)
)
#>      row_id     subject         age       roi_1 
#> "character" "character"   "numeric"   "numeric"
```

That type coercion is part of the package contract. If a manifest says a
column is `float64` or `date`, [`nf_read()`](../reference/nf_read.md)
normalizes the loaded table to match.

## How Do You Check Conformance?

Structural conformance answers the question “is this dataset
well-formed?”. Full conformance goes further and tries to resolve every
non-missing feature.

``` r
structural <- nf_validate(roi_ds, level = "structural")
stopifnot(structural$valid)

structural$valid
#> [1] TRUE
```

For the ROI-only example, full conformance is also straightforward
because every feature value lives directly in observation-table columns.

``` r
full <- nf_validate(roi_ds, level = "full")
stopifnot(full$valid)

full$valid
#> [1] TRUE
```

## How Do Feature Values Resolve?

The ROI example stores one logical feature, `roi_beta`, as an ordered
set of scalar columns. You can resolve one row at a time or collect the
feature across all rows.

``` r
nf_resolve(roi_ds, 1L, "roi_beta")
#> [1] 0.31 0.44 0.29 0.18 0.22
```

``` r
roi_mat <- nf_collect(roi_ds, "roi_beta")
stopifnot(is.matrix(roi_mat), ncol(roi_mat) == 5L)

dim(roi_mat)
#> [1] 8 5
```

The package also ships a mixed example with both `columns` and `ref`
encodings. The ROI feature still resolves immediately even though the
dataset also declares a volume feature.

``` r
faces_path <- system.file("examples/faces-demo/nftab.yaml", package = "neurotabs")
stopifnot(nzchar(faces_path))

faces_ds <- nf_read(faces_path)
nf_feature_names(faces_ds)
#> [1] "statmap"  "roi_beta"
nf_resolve(faces_ds, 1L, "roi_beta")
#> [1] 0.31 0.44 0.29
```

## How Do You Encode ROI Names And Atlas Identity?

For `columns` encodings, the physical column names are just storage. The
semantic metadata belongs to the feature axis. In practice that means:

- `binding.columns` defines the storage order of the ROI vector.
- `nf_axis_info(..., "roi")$id` identifies the atlas or parcellation.
- `nf_axis_info(..., "roi")$labels` points to a label table that names
  each ROI.

The shipped `faces-demo` uses that pattern for its three-region ROI
feature.

``` r
roi_schema <- nf_feature_schema(faces_ds, "roi_beta")
stopifnot(identical(roi_schema$axes, "roi"))

roi_axis <- nf_axis_info(faces_ds, "roi_beta", "roi")
stopifnot(identical(roi_axis$id, "desikan3-demo"))

roi_axis
#> <nf_axis_domain>
#>   id: desikan3-demo 
#>   labels: roi_labels.tsv
```

``` r
roi_labels <- nf_axis_labels(faces_ds, "roi_beta", "roi")
roi_values <- nf_resolve(faces_ds, 1L, "roi_beta")
stopifnot(nrow(roi_labels) == length(roi_values))

data.frame(
  atlas = roi_axis$id,
  label = roi_labels$label,
  value = roi_values,
  row.names = NULL
)
#>           atlas                label value
#> 1 desikan3-demo        left_fusiform  0.31
#> 2 desikan3-demo       right_fusiform  0.44
#> 3 desikan3-demo left_parahippocampal  0.29
```

This is the intended encoding for parcel-wise vectors. The atlas
identity lives with the logical axis, not in the storage column names,
so the same logical ROI feature can be stored under different physical
column bundles and still mean the same thing.

## What Does Full Conformance Mean For External Resources?

For `ref` encodings, full conformance requires successful
materialization through a registered backend. The package also validates
resource checksums before backend dispatch when a checksum is present.

``` r
stopifnot(isTRUE(checksum_detected))

checksum_detected
#> [1] TRUE
```

A `TRUE` result here means the resolver rejected the resource before it
reached backend dispatch because the checksum token did not match the
file on disk.

## How Do You Create a Dataset?

### The Quick Way: `nf_from_table()`

If you have a table (CSV or data.frame) and a set of NIfTI files, one
per row:

``` r
ds <- nf_from_table(
  "participants.csv",          # table with subject, condition, etc.
  feature     = "statmap",     # name for the feature
  locator_col = "nifti_path",  # column pointing to .nii.gz files
  space       = "MNI152NLin2009cAsym",
  root        = "/data/study"
)
```

Or if all rows map to successive volumes in a single 4D NIfTI:

``` r
ds <- nf_from_table(
  design_table,                      # data.frame with subject, condition, etc.
  feature = "bold",
  locator = "results/group_stats.nii.gz",  # shared 4D file
  space   = "MNI152NLin2009cAsym",
  root    = "/data/study"
)
# Row 1 -> volume 0, row 2 -> volume 1, etc.
```

### The Manual Way: Full Control

Every observation column needs a declared dtype and nullability:

``` r
obs_cols <- list(
  row_id    = nf_col_schema("string",  nullable = FALSE),
  subject   = nf_col_schema("string",  nullable = FALSE),
  condition = nf_col_schema("string",  nullable = FALSE),
  roi_1     = nf_col_schema("float32"),
  roi_2     = nf_col_schema("float32")
)
```

### Step 2: Define Features

A feature has a logical schema (what the resolved value IS) and one or
more encodings (how to find it). For a 2-element ROI vector stored in
columns:

``` r
roi_feature <- nf_feature(
  logical = nf_logical_schema(
    kind  = "vector",
    axes  = "roi",
    dtype = "float32",
    shape = 2L
  ),
  encodings = list(
    nf_columns_encoding(c("roi_1", "roi_2"))
  )
)
```

### Step 3: Build the Manifest and Dataset

The manifest ties columns, features, and axes together:

``` r
manifest <- nf_manifest(
  dataset_id          = "my-study",
  row_id              = "row_id",
  observation_axes    = c("subject", "condition"),
  observation_columns = obs_cols,
  features            = list(roi = roi_feature)
)
```

Then combine the manifest with an observation table:

``` r
observations <- data.frame(
  row_id    = c("r1", "r2", "r3", "r4"),
  subject   = c("s01", "s01", "s02", "s02"),
  condition = c("faces", "houses", "faces", "houses"),
  roi_1     = c(0.5, 0.2, 0.6, 0.3),
  roi_2     = c(0.4, 0.1, 0.5, 0.2),
  stringsAsFactors = FALSE
)

my_ds <- nftab(manifest, observations)
my_ds
#> <nftab> my-study 
#>   4 observations x 1 features
#>   axes: subject, condition 
#>   features: roi 
#>   subject: s01, s02
#>   condition: faces, houses
```

### Step 4: Write to Disk

[`nf_write()`](../reference/nf_write.md) produces a portable NFTab
directory with a YAML manifest and CSV observation table:

``` r
out_dir <- tempfile("my-study-")
nf_write(my_ds, out_dir)

list.files(out_dir)
#> [1] "nftab.yaml"       "observations.csv"
```

The written dataset can be read back with
[`nf_read()`](../reference/nf_read.md):

``` r
my_ds2 <- nf_read(file.path(out_dir, "nftab.yaml"))
nf_resolve(my_ds2, "r1", "roi")
#> [1] 0.5 0.4
```

## How Do You Filter, Group, and Summarize?

`neurotabs` provides dplyr-style grammar verbs that operate directly on
`nftab` objects. These verbs work with both columns-encoded and
NIfTI-backed features.

### Filtering Rows

[`nf_filter()`](../reference/nf_filter.md) selects observations matching
a predicate. Observation column names are available directly in the
expression:

``` r
ctrl_ds <- nf_filter(roi_ds, group == "ctrl")
nf_nobs(ctrl_ds)
#> [1] 0
```

### Selecting and Arranging

[`nf_select()`](../reference/nf_select.md) keeps named design columns
(encoding-required columns are always retained).
[`nf_arrange()`](../reference/nf_arrange.md) sorts rows:

``` r
sorted <- nf_arrange(roi_ds, subject)
nf_design(sorted)[, c("row_id", "subject", "condition")]
#>   row_id subject condition
#> 1    r01  sub-01     faces
#> 2    r02  sub-01    houses
#> 3    r03  sub-02     faces
#> 4    r04  sub-02    houses
#> 5    r05  sub-03     faces
#> 6    r06  sub-03    houses
#> 7    r07  sub-04     faces
#> 8    r08  sub-04    houses
```

### Applying Functions Across Rows

[`nf_apply()`](../reference/nf_apply.md) runs a function or fixed
operation on each row’s feature value. For character operations like
`"mean"`, `"sum"`, `"sd"`, the package uses optimized batch paths:

``` r
means <- nf_apply(roi_ds, "roi_beta", "mean")
means
#>   r01   r02   r03   r04   r05   r06   r07   r08 
#> 0.288 0.130 0.292 0.098 0.418 0.200 0.360 0.144
```

### Grouping and Summarizing

[`nf_group_by()`](../reference/nf_group_by.md) +
[`nf_summarize()`](../reference/nf_summarize.md) computes group-level
feature summaries. The result is a new `nftab` with one row per group:

``` r
grouped <- nf_group_by(roi_ds, group)
summary_ds <- nf_summarize(grouped, "roi_beta", .f = "mean")
summary_ds
#> <nftab> roi-only-summary 
#>   2 observations x 1 features
#>   axes: group 
#>   features: roi_beta 
#>   group: control, patient
```

You can resolve the summarized feature to see the group-level average:

``` r
nf_resolve(summary_ds, 1L, "roi_beta")
#> [1] 0.2000 0.2875 0.2200 0.1375 0.1650
```

### Adding Derived Columns

[`nf_mutate()`](../reference/nf_mutate.md) adds new observation columns.
Inside [`nf_mutate()`](../reference/nf_mutate.md), the helper
`nf_apply_feature()` derives scalar values from features:

``` r
ds_with_mean <- nf_mutate(roi_ds, roi_mean = nf_apply_feature("roi_beta", "mean"))
ds_with_mean$observations[, c("row_id", "subject", "roi_mean")]
#>   row_id subject roi_mean
#> 1    r01  sub-01    0.288
#> 2    r02  sub-01    0.130
#> 3    r03  sub-02    0.292
#> 4    r04  sub-02    0.098
#> 5    r05  sub-03    0.418
#> 6    r06  sub-03    0.200
#> 7    r07  sub-04    0.360
#> 8    r08  sub-04    0.144
```

## Where Should You Go Next?

The full workflow is:

1.  Read a manifest with [`nf_read()`](../reference/nf_read.md).
2.  Check structural or full conformance with
    [`nf_validate()`](../reference/nf_validate.md).
3.  Filter, arrange, and select with
    [`nf_filter()`](../reference/nf_filter.md),
    [`nf_arrange()`](../reference/nf_arrange.md),
    [`nf_select()`](../reference/nf_select.md).
4.  Resolve features with [`nf_resolve()`](../reference/nf_resolve.md)
    or [`nf_collect()`](../reference/nf_collect.md).
5.  Apply row-wise operations with
    [`nf_apply()`](../reference/nf_apply.md).
6.  Group and summarize with
    [`nf_group_by()`](../reference/nf_group_by.md) +
    [`nf_summarize()`](../reference/nf_summarize.md).
7.  Compare groups with [`nf_compare()`](../reference/nf_compare.md).
8.  Combine compatible datasets with
    [`nf_concat()`](../reference/nf_concat.md).

For NIfTI-backed features, set `options(neurotabs.compute.workers = 4L)`
to enable parallel file reads on multi-core systems.
