# Create a columns encoding

Declares that a 1D feature is stored as an ordered set of scalar columns
in the observation table.

## Usage

``` r
nf_columns_encoding(columns)
```

## Arguments

- columns:

  Character vector of column names, in order.

## Value

An `nf_encoding` object with `type = "columns"`.
