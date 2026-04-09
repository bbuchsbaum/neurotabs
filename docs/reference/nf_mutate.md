# Mutate observation columns

Expressions are evaluated in the observation-table context. Inside
`nf_mutate()`, the helper `nf_apply_feature(feature, .f, ...)` is
available for deriving scalar columns from NFTab features, including
fast fixed operations over NIfTI-backed features.

## Usage

``` r
nf_mutate(x, ...)
```

## Arguments

- x:

  An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
  object.

- ...:

  Named expressions yielding one scalar value per row (or a length-1
  value that can be recycled).

## Value

An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
object with additional or replaced observation columns.
