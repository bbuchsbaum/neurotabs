# Create an nftab from a table and external feature files

The most common entry point for building an nftab from existing data.
Supports two patterns:

## Usage

``` r
nf_from_table(
  observations,
  feature = "statmap",
  locator_col = NULL,
  locator = NULL,
  row_id = "row_id",
  axes = NULL,
  backend = NULL,
  space = NULL,
  dataset_id = "dataset",
  root = NULL
)
```

## Arguments

- observations:

  A data.frame or path to a CSV/TSV file. Each row is one observation
  with design metadata columns.

- feature:

  Name to give the feature (e.g. `"statmap"`).

- locator_col:

  Column name in `observations` containing per-row file paths. Use this
  for the one-file-per-row pattern. Mutually exclusive with `locator`.

- locator:

  A single file path shared by all rows (4D file). Row `i` maps to
  volume `i-1` (0-based). Mutually exclusive with `locator_col`.

- row_id:

  Name of the row ID column. If the column does not exist, one is
  generated automatically. Default `"row_id"`.

- axes:

  Character vector of observation axis column names. If `NULL`,
  auto-detected as all string columns except `row_id`, `locator_col`,
  and any selector column.

- backend:

  Backend identifier. Default `NULL` (auto-detect from file extension).

- space:

  Named reference space (e.g. `"MNI152NLin2009cAsym"`).

- dataset_id:

  Dataset identifier for the manifest.

- root:

  Base directory for resolving relative paths. If `NULL` and
  `observations` is a file path, uses its parent directory.

## Value

An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
object.

## Details

- **One file per row**: each row has a column pointing to a separate 3D
  file.

- **Shared file**: all rows map to successive volumes in a single 4D
  file.

The backend is inferred from file extension (`.nii`, `.nii.gz` -\>
`"nifti"`) or can be set explicitly.
