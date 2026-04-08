# Declare a logical feature schema

Describes what a resolved feature value IS, independent of how it is
stored.

## Usage

``` r
nf_logical_schema(
  kind,
  axes,
  dtype,
  support_ref = NULL,
  shape = NULL,
  axis_domains = NULL,
  space = NULL,
  alignment = NULL,
  unit = NULL,
  description = NULL
)
```

## Arguments

- kind:

  Descriptive kind: `"volume"`, `"vector"`, `"matrix"`, `"surface"`, or
  `"array"`.

- axes:

  Character vector of semantic axis names (e.g., `c("x","y","z")`).

- dtype:

  Element data type.

- support_ref:

  Optional manifest-local reference to an exact support descriptor.

- shape:

  Optional integer vector of expected dimensions.

- axis_domains:

  Optional named list of [nf_axis_domain](nf_axis_domain.md) objects.

- space:

  Optional named coordinate space (e.g., `"MNI152NLin2009cAsym"`).

- alignment:

  Optional alignment guarantee: `"same_grid"`, `"same_space"`,
  `"loose"`, or `"none"`.

- unit:

  Optional unit of measurement.

- description:

  Optional human-readable description.

## Value

An `nf_logical_schema` object.
