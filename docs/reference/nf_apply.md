# Apply a function or fixed operation to a feature row-by-row

For character `.f` values in
`c("mean", "sum", "sd", "min", "max", "nnz", "l2")`, `neurotabs` uses a
fixed-operation path and will batch NIfTI reads when possible. For a
function `.f`, values are resolved row-by-row and passed to that
function.

## Usage

``` r
nf_apply(x, feature, .f, ..., .progress = FALSE)
```

## Arguments

- x:

  An [nftab](nftab.md) object.

- feature:

  Feature name.

- .f:

  Either a function or a character fixed operation.

- ...:

  Additional arguments passed to `.f` when `.f` is a function.

- .progress:

  Show progress during generic row-wise resolution. Default `FALSE`.

## Value

A named vector or list with one result per row.

## Parallelism

For NIfTI-backed features with fixed operations, batch reads can be
parallelized across files using
`options(neurotabs.compute.workers = 4L)`. This uses
[`parallel::mclapply()`](https://rdrr.io/r/parallel/mclapply.html) and
is disabled on Windows. The default is 1 (sequential).
