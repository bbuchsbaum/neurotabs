# Declare a scalar column schema

Declare a scalar column schema

## Usage

``` r
nf_col_schema(
  dtype,
  nullable = TRUE,
  semantic_role = NULL,
  levels = NULL,
  unit = NULL,
  description = NULL
)
```

## Arguments

- dtype:

  Data type. One of `"string"`, `"int32"`, `"int64"`, `"float32"`,
  `"float64"`, `"bool"`, `"date"`, `"datetime"`, `"json"`.

- nullable:

  Whether null values are permitted. Default `TRUE`.

- semantic_role:

  Optional semantic role hint (e.g., `"subject"`, `"group"`,
  `"condition"`).

- levels:

  Optional character vector of allowed categorical values.

- unit:

  Optional unit of measurement.

- description:

  Optional human-readable description.

## Value

An `nf_col_schema` object.
