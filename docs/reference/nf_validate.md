# Validate an NFTab dataset

Checks structural or full conformance.

## Usage

``` r
nf_validate(x, level = c("structural", "full"), .progress = FALSE)
```

## Arguments

- x:

  An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
  object.

- level:

  `"structural"` or `"full"`. Full conformance additionally attempts to
  resolve every non-missing feature value.

- .progress:

  If `TRUE`, emit progress messages during full validation. Default
  `FALSE`.

## Value

A list with `valid` (logical), `errors` (character vector), and
`warnings` (character vector). Returned invisibly.
