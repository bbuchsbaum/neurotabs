# Select observation columns

Keeps only the named design columns (plus any columns required by
feature encodings, which are always retained).

## Usage

``` r
nf_select(x, ..., .cols = NULL)
```

## Arguments

- x:

  An [nftab](nftab.md) object.

- ...:

  Column names (unquoted or character).

- .cols:

  Optional character vector of column names; use instead of `...` for
  programmatic selection.

## Value

An [nftab](nftab.md) with fewer observation columns.
