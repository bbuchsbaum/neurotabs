# Compare summarized feature values to a reference group

If `x` is a `grouped_nftab`, `nf_compare()` first summarizes `feature`
within each group using `.reduce`, then compares every group to the
reference group `.ref`. If `x` is already a summarized `data.frame`, it
must contain a list-column named `feature`.

## Usage

``` r
nf_compare(x, feature, .ref, .f = c("subtract", "ratio"), .reduce = "mean")
```

## Arguments

- x:

  A `grouped_nftab` or summarized `data.frame`.

- feature:

  Feature name / list-column name.

- .ref:

  Reference group. If there is exactly one grouping column, this may be
  a scalar value. Otherwise provide a named list of grouping values.

- .f:

  Comparison operation: `"subtract"` or `"ratio"`.

- .reduce:

  Reducer used when `x` is grouped. Default `"mean"`.

## Value

A `data.frame` with the same grouping columns and a compared list-column
named after `feature`.
