# Build a matched reference cohort by exact column matching

Returns the subset of `x` where observation columns exactly match the
provided values. Intended for use as the `.ref` argument in
[nf_compare](https://bbuchsbaum.github.io/neurotabs/reference/nf_compare.md).

## Usage

``` r
nf_matched_cohort(x, match_on)
```

## Arguments

- x:

  An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
  object providing the reference pool.

- match_on:

  Named list: column name -\> one or more allowed values.

## Value

An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
containing only the matching observations.
