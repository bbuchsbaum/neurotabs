# Declare a feature schema

Declare a feature schema

## Usage

``` r
nf_feature(logical, encodings, nullable = FALSE, description = NULL)
```

## Arguments

- logical:

  An [nf_logical_schema](nf_logical_schema.md) object.

- encodings:

  A list of encoding objects created by
  [`nf_ref_encoding()`](nf_ref_encoding.md) or
  [`nf_columns_encoding()`](nf_columns_encoding.md).

- nullable:

  Whether missing values are permitted. Default `FALSE`.

- description:

  Optional description.

## Value

An `nf_feature` object.
