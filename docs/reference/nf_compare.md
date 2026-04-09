# Compare summarized feature values to a reference group

If `x` is a `grouped_nftab`, `nf_compare()` first summarizes `feature`
within each group using `.reduce`, then compares every group to the
reference group `.ref`. If `x` is already a summary
[nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md), the
comparison is applied directly to its feature values. If `x` is a
summarized `data.frame`, it must contain a list-column named `feature`.

## Usage

``` r
nf_compare(x, feature, .ref, .f = c("subtract", "ratio"), .reduce = "mean")
```

## Arguments

- x:

  A `grouped_nftab`, summary
  [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md), or
  summarized `data.frame`.

- feature:

  Feature name / list-column name as a string or unquoted symbol.

- .ref:

  Reference group. If there is exactly one grouping column, this may be
  a scalar value. Otherwise provide a named list of grouping values.

- .f:

  Comparison operation: `"subtract"` or `"ratio"`.

- .reduce:

  Reducer used when `x` is grouped. Default `"mean"`.

## Value

An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
when `x` is a `grouped_nftab` or
[nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md). A
summarized `data.frame` when `x` is already a summarized `data.frame`.
