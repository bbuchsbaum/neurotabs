# Collect (resolve) a feature for all rows

Resolves all rows for the named feature and returns results as a list.

## Usage

``` r
nf_collect(x, feature, simplify = TRUE, .progress = FALSE)
```

## Arguments

- x:

  An [nftab](nftab.md) object.

- feature:

  Character name of the feature.

- simplify:

  If `TRUE` and the feature is 1D with fixed shape, return a matrix
  instead of a list.

- .progress:

  Show progress? Default `FALSE`.

## Value

A named list of resolved values, or a matrix if simplified.
