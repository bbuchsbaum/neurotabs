# Group observations by design columns

Group observations by design columns

## Usage

``` r
nf_group_by(x, ..., .by = NULL)
```

## Arguments

- x:

  An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
  object.

- ...:

  Grouping columns (unquoted or character).

- .by:

  Optional character vector of column names; use instead of `...` for
  programmatic grouping.

## Value

A `grouped_nftab` object.
