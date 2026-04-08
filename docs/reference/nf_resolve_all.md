# Resolve all rows for a feature

Resolve all rows for a feature

## Usage

``` r
nf_resolve_all(x, feature, .progress = FALSE)
```

## Arguments

- x:

  An [nftab](nftab.md) object.

- feature:

  Character name of the feature.

- .progress:

  Show progress? Default `FALSE`.

## Value

A list of resolved values, one per row. `NULL` entries indicate missing
(nullable) values.
