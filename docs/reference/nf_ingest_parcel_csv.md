# Ingest a parcel-signal CSV into an nftab

Reads a CSV file where rows are observations and columns are parcel
signals, and wraps it into an
[nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md) using
a `columns` encoding (data stored inline in the observation table).

## Usage

``` r
nf_ingest_parcel_csv(
  path,
  design,
  parcel_cols = NULL,
  parcel_map = NULL,
  space = "unknown",
  feature = "parcel_signal",
  dataset_id = NULL
)
```

## Arguments

- path:

  Path to the CSV file. Every column not present in `design` (or matched
  by `parcel_cols`) is treated as a parcel signal column.

- design:

  A data.frame with one row per observation.

- parcel_cols:

  Optional character vector of column names to use as parcel signals. If
  `NULL` (default), all CSV columns absent from `design` are used.

- parcel_map:

  Optional path to a TSV (or data.frame) with columns `index`, `label`,
  `n_voxels`, `x_centroid`, `y_centroid`, `z_centroid`. When provided,
  an
  [`nf_support_parcel()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_support_parcel.md)
  is attached.

- space:

  Named reference space. Used only when `parcel_map` is provided.
  Default `"unknown"`.

- feature:

  Name to give the parcel-signal feature. Default `"parcel_signal"`.

- dataset_id:

  Dataset identifier for the manifest.

## Value

An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
object with a `columns` encoding (data inline).
