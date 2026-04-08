# Create an NFTab manifest

Create an NFTab manifest

## Usage

``` r
nf_manifest(
  spec_version = "0.1.0",
  dataset_id,
  row_id,
  observation_axes,
  observation_columns,
  features,
  storage_profile = "table-package",
  observation_table_path = "observations.csv",
  observation_table_format = "csv",
  resources_path = NULL,
  resources_format = NULL,
  supports = NULL,
  primary_feature = NULL,
  import_recipe = NULL,
  extensions = NULL
)
```

## Arguments

- spec_version:

  Semantic version string.

- dataset_id:

  Dataset identifier.

- row_id:

  Name of the row ID column.

- observation_axes:

  Character vector of axis column names.

- observation_columns:

  Named list of [nf_col_schema](nf_col_schema.md) objects.

- features:

  Named list of [nf_feature](nf_feature.md) objects.

- storage_profile:

  Storage profile (default `"table-package"`).

- observation_table_path:

  Path to observation table file.

- observation_table_format:

  Format (`"csv"`, `"tsv"`, or `"parquet"`).

- resources_path:

  Optional path to resource registry file.

- resources_format:

  Optional format of resource registry.

- supports:

  Optional named list of support descriptors created by
  [`nf_support()`](nf_support.md), keyed by manifest-local support
  reference.

- primary_feature:

  Optional default feature name for consumers.

- import_recipe:

  Optional non-normative import metadata.

- extensions:

  Optional named list of extension data.

## Value

An `nf_manifest` object.
