# Create a ref encoding

Declares that a feature is stored in an external resource, resolved via
a backend adapter.

## Usage

``` r
nf_ref_encoding(
  backend = NULL,
  locator = NULL,
  selector = NULL,
  resource_id = NULL,
  checksum = NULL
)
```

## Arguments

- backend:

  Backend identifier or [nf_col](nf_col.md) reference.

- locator:

  Path/URI or [nf_col](nf_col.md) reference.

- selector:

  Optional selector (literal or [nf_col](nf_col.md) reference).

- resource_id:

  Optional resource registry ID (literal or [nf_col](nf_col.md)
  reference).

- checksum:

  Optional checksum (literal or [nf_col](nf_col.md) reference).

## Value

An `nf_encoding` object with `type = "ref"`.
