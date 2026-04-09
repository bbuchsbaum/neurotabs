# Arrange (sort) observations

Arrange (sort) observations

## Usage

``` r
nf_arrange(x, ..., .by = NULL)
```

## Arguments

- x:

  An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
  object.

- ...:

  Column names to sort by. Prefix with `-` for descending.

- .by:

  Optional character vector of sort column names; use instead of `...`
  for programmatic sorting.

## Value

A reordered
[nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md).
