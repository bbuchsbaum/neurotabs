# Read an NFTab dataset from a manifest file

Read an NFTab dataset from a manifest file

## Usage

``` r
nf_read(path, validate_schema = TRUE)
```

## Arguments

- path:

  Path to `nftab.yaml` or `nftab.json`.

- validate_schema:

  Whether to validate the manifest against the bundled JSON Schema.
  Default `TRUE`.

## Value

An [nftab](nftab.md) object.
