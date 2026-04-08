# Filter observations by design predicates

Filter observations by design predicates

## Usage

``` r
nf_filter(x, ...)
```

## Arguments

- x:

  An [nftab](nftab.md) object.

- ...:

  Filter expressions evaluated in the context of the observation table.
  Observation column names take precedence over variables in the calling
  environment. Multiple expressions are combined with AND.

## Value

A filtered [nftab](nftab.md) object.
