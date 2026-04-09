# Create an NFTab dataset object

The primary user-facing object. Holds a manifest, the observation table,
and an optional resource registry.

## Usage

``` r
nftab(manifest, observations, resources = NULL, .root = NULL)
```

## Arguments

- manifest:

  An
  [nf_manifest](https://bbuchsbaum.github.io/neurotabs/reference/nf_manifest.md)
  object.

- observations:

  A data.frame with one row per observation.

- resources:

  Optional data.frame with resource registry entries.

- .root:

  Directory root for resolving relative paths.

## Value

An `nftab` object.
