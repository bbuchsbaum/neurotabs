# Declare a parcel support descriptor

Describes a brain parcellation — a set of named ROIs, each comprising
one or more voxels. The `parcel_map` TSV (columns: `index`, `label`,
`n_voxels`, `x_centroid`, `y_centroid`, `z_centroid`) provides the
lightweight spatial summary used by downstream tools. Full voxel
membership lives in the source file and can be referenced via
`membership_ref`.

## Usage

``` r
nf_support_parcel(
  support_id,
  space,
  n_parcels,
  parcel_map = NULL,
  membership_ref = NULL,
  description = NULL,
  metadata = NULL
)
```

## Arguments

- support_id:

  Stable identifier for this parcellation version.

- space:

  Named reference space (e.g., `"MNI152NLin2009cAsym"`).

- n_parcels:

  Number of parcels (integer).

- parcel_map:

  Optional relative path to a TSV with columns `index`, `label`,
  `n_voxels`, `x_centroid`, `y_centroid`, `z_centroid`.

- membership_ref:

  Optional path to an HDF5 file containing full voxel membership (e.g.,
  the source fmristore file).

- description:

  Optional human-readable description.

- metadata:

  Optional named list of extra metadata.

## Value

An `nf_support_schema` object with `support_type = "parcel"`.
