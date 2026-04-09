# Resolve a single feature value for one row

Evaluates the feature's encodings in priority order and returns the
first applicable result.

## Usage

``` r
nf_resolve(x, row_index, feature, as_array = TRUE)
```

## Arguments

- x:

  An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
  object.

- row_index:

  Integer row index, or a character `row_id` value.

- feature:

  Feature name as a string or unquoted symbol.

- as_array:

  If `TRUE` (default), the resolved value is returned as a plain R
  array. If `FALSE`, the backend's native object is returned when
  available (e.g., a `NeuroVol` for the `"nifti"` backend with
  neuroim2), preserving spatial metadata such as voxel spacing and
  orientation. Falls back to array resolution when the backend has no
  native resolver.

## Value

The resolved feature value, or `NULL` if the feature is nullable and no
encoding is applicable.
