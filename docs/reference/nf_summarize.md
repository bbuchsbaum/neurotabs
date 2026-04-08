# Summarize a feature across rows or groups

For character `.f` values in `c("mean", "sum")`, `neurotabs` performs an
elementwise reduction over resolved feature values and will batch NIfTI
reads when possible. For a function `.f`, each group receives the list
of resolved values for that feature.

## Usage

``` r
nf_summarize(x, feature, by = NULL, .f = "mean", ..., .progress = FALSE)

nf_summarise(x, feature, by = NULL, .f = "mean", ..., .progress = FALSE)
```

## Arguments

- x:

  An [nftab](nftab.md) object.

- feature:

  Feature name.

- by:

  Optional character vector of observation columns defining groups.

- .f:

  Either a function or a fixed reducer name.

- ...:

  Additional arguments passed to `.f` when `.f` is a function.

- .progress:

  Show progress during generic resolution. Default `FALSE`.

## Value

If `by = NULL`, a single reduced value. Otherwise a `data.frame` with
grouping columns and a list-column named after `feature`.
