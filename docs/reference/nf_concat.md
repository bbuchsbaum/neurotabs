# Concatenate NFTab datasets (strict row-wise)

Concatenate NFTab datasets (strict row-wise)

## Usage

``` r
nf_concat(..., provenance_col = "source_dataset")
```

## Arguments

- ...:

  [nftab](nftab.md) objects to concatenate.

- provenance_col:

  Name of provenance column to add. Default `"source_dataset"`. Set to
  `NULL` to skip.

## Value

A new [nftab](nftab.md) object with rows from all inputs.
