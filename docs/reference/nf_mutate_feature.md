# Mutate a derived feature

Applies `.f` row-by-row to an existing feature and materializes the
result as a new NFTab feature. By default, the derived feature preserves
the source logical schema and uses storage selected from that schema:

## Usage

``` r
nf_mutate_feature(
  x,
  name,
  feature,
  .f,
  ...,
  logical = NULL,
  storage = c("auto", "columns", "nifti"),
  description = NULL,
  .progress = FALSE
)
```

## Arguments

- x:

  An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
  object or `grouped_nftab`.

- name:

  Name of the derived feature to create, as a string or unquoted symbol.

- feature:

  Source feature name as a string or unquoted symbol.

- .f:

  Function applied to each resolved feature value.

- ...:

  Additional arguments passed to `.f`.

- logical:

  Optional
  [nf_logical_schema](https://bbuchsbaum.github.io/neurotabs/reference/nf_logical_schema.md)
  describing the derived feature. If omitted, the source logical schema
  is reused and outputs must conform to it.

- storage:

  Storage strategy: `"auto"`, `"columns"`, or `"nifti"`.

- description:

  Optional description for the new feature.

- .progress:

  Show progress during generic row-wise resolution. Default `FALSE`.

  Rows where `.f` returns `NULL` are encoded as missing values, and the
  derived feature is marked nullable.

## Value

An updated
[nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
object, or `grouped_nftab` when input is grouped.

## Details

- 1D features use `columns` encoding

- volumetric features use temporary NIfTI resources
