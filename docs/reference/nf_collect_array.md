# Collect a volumetric feature as a stacked array with spatial metadata

Resolves all observations for a 3D (volumetric) feature and stacks them
into a 4D array `[x, y, z, n_obs]`, preserving the `NeuroSpace` from the
first resolved volume.

## Usage

``` r
nf_collect_array(x, feature, .progress = FALSE)
```

## Arguments

- x:

  An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
  object.

- feature:

  Feature name as a string or unquoted symbol.

- .progress:

  Show progress messages every 10 rows? Default `FALSE`.

## Value

A named list with two elements:

- `data`:

  A 4D numeric array with dimensions `c(x, y, z, n_obs)`.

- `space`:

  The `NeuroSpace` object from the first resolved volume, or `NULL` if
  neuroim2 is not available or native resolution is not supported by the
  backend.
