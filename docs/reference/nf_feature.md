# Declare a feature schema

Declare a feature schema

## Usage

``` r
nf_feature(logical, encodings, nullable = FALSE, description = NULL)
```

## Arguments

- logical:

  An
  [nf_logical_schema](https://bbuchsbaum.github.io/neurotabs/reference/nf_logical_schema.md)
  object.

- encodings:

  A list of encoding objects created by
  [`nf_ref_encoding()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_ref_encoding.md)
  or
  [`nf_columns_encoding()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_columns_encoding.md).

- nullable:

  Whether missing values are permitted. Default `FALSE`.

- description:

  Optional description.

## Value

An `nf_feature` object.
