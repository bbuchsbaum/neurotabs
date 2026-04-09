# Resolve all rows for a feature

Resolve all rows for a feature

## Usage

``` r
nf_resolve_all(x, feature, .progress = FALSE)
```

## Arguments

- x:

  An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
  object.

- feature:

  Feature name as a string or unquoted symbol.

- .progress:

  Show progress? Default `FALSE`.

## Value

A list of resolved values, one per row. `NULL` entries indicate missing
(nullable) values.
