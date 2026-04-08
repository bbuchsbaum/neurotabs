# Declare a surface support descriptor

Declare a surface support descriptor

## Usage

``` r
nf_support_surface(
  support_id,
  template,
  mesh_id,
  topology_id,
  hemisphere,
  description = NULL,
  metadata = NULL
)
```

## Arguments

- support_id:

  Stable exact identifier for the surface support.

- template:

  Surface template family.

- mesh_id:

  Stable identifier for the surface mesh embedding.

- topology_id:

  Stable identifier for the topology basis.

- hemisphere:

  Hemisphere identity.

- description:

  Optional human-readable description.

- metadata:

  Optional named list of extra support metadata.

## Value

An `nf_support_schema` object with `support_type = "surface"`.
