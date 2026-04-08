# Ingest a parcellated fmristore HDF5 file into an nftab

Builds an [nftab](nftab.md) from an `H5ParcellatedScanSummary`,
`H5ParcellatedScan`, or `H5ParcellatedMultiScan` file. One nftab row is
created per observation (timepoint / volume), with a ref encoding that
reads a single row of the `T × K` summary matrix via the
`"fmristore-parcel"` backend.

## Usage

``` r
nf_ingest_parcel_h5(
  path,
  design,
  scan_name = NULL,
  feature = "parcel_signal",
  dataset_id = NULL,
  space = "unknown",
  output_dir = NULL
)
```

## Arguments

- path:

  Path to the HDF5 file.

- design:

  A data.frame with one row per observation (T rows). Any columns whose
  names match `"subject"`, `"session"`, `"run"`, or `"condition"` are
  used as observation axes.

- scan_name:

  For multi-scan files: which scan to use. Defaults to the first scan.
  Ignored for single-scan files.

- feature:

  Name to give the parcel-signal feature. Default `"parcel_signal"`.

- dataset_id:

  Dataset identifier for the manifest. Derived from the filename by
  default.

- space:

  Named reference space (e.g. `"MNI152NLin2009cAsym"`). Default
  `"unknown"`.

- output_dir:

  Optional directory where the `parcel_map.tsv` will be written. If
  `NULL`, parcel metadata is embedded as in-memory only (not written to
  disk).

## Value

An [nftab](nftab.md) object with ref encodings pointing to `path`.
