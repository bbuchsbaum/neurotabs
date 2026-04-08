# Declare a generic support descriptor

Declare a generic support descriptor

## Usage

``` r
nf_support_generic(support_id, description = NULL, metadata = NULL)
```

## Arguments

- support_id:

  Stable exact identifier for the support.

- description:

  Optional human-readable description.

- metadata:

  Optional named list of extra support metadata.

## Value

An `nf_support_schema` object with `support_type = "generic"`.
