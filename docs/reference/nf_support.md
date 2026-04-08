# Declare a generic support descriptor

Declare a generic support descriptor

## Usage

``` r
nf_support(support_type, support_id, description = NULL, metadata = NULL, ...)
```

## Arguments

- support_type:

  Support class: `"volume"`, `"surface"`, or `"generic"`.

- support_id:

  Stable exact identifier for the support.

- description:

  Optional human-readable description.

- metadata:

  Optional named list of extra support metadata.

- ...:

  Additional support-type-specific fields.

## Value

An `nf_support_schema` object.
