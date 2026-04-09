# Sample feature values at spatial coordinates across all observations

Extracts feature values at a fixed set of spatial coordinates for every
observation, returning an `[n_obs x n_coords]` matrix. This is the core
spatial query primitive — it maps directly to the `series_fun` contract
expected by tools like cluster.explorer.

## Usage

``` r
nf_sample(
  x,
  feature,
  coords,
  coord_type = c("voxel", "mm"),
  rows = NULL,
  .progress = FALSE
)
```

## Arguments

- x:

  An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
  object.

- feature:

  Feature name as a string or unquoted symbol.

- coords:

  An `n_coords x 3` integer matrix of voxel grid coordinates (1-based)
  when `coord_type = "voxel"`, or an `n_coords x 3` numeric matrix of mm
  world coordinates when `coord_type = "mm"`.

- coord_type:

  `"voxel"` (default) or `"mm"`. mm conversion requires neuroim2 and
  native backend resolution.

- rows:

  Integer vector of row indices to include. Defaults to all rows.

- .progress:

  Show progress messages every 10 rows? Default `FALSE`.

## Value

A numeric matrix with `length(rows)` rows and `nrow(coords)` columns.
Row names are set to the corresponding `row_id` values.
