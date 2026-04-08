# Compute a schema fingerprint for compatibility checking

Two features are concatenation-compatible iff their fingerprints are
identical.

## Usage

``` r
nf_schema_fingerprint(x, support_id = NULL)
```

## Arguments

- x:

  An [nf_logical_schema](nf_logical_schema.md) object.

- support_id:

  Optional exact support identifier used for compatibility fingerprints.

## Value

A character string (hex digest).
