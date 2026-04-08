# Declare a volume support descriptor

Declare a volume support descriptor

## Usage

``` r
nf_support_volume(
  support_id,
  space,
  grid_id,
  affine_id = NULL,
  description = NULL,
  metadata = NULL
)
```

## Arguments

- support_id:

  Stable exact identifier for the volume support.

- space:

  Named reference space.

- grid_id:

  Stable identifier for the voxel lattice.

- affine_id:

  Optional stable identifier for the affine or transform.

- description:

  Optional human-readable description.

- metadata:

  Optional named list of extra support metadata.

## Value

An `nf_support_schema` object with `support_type = "volume"`.
