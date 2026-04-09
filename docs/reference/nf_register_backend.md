# Register a backend adapter

Register a backend adapter

## Usage

``` r
nf_register_backend(
  name,
  resolve_fn,
  detect_fn = NULL,
  write_fn = NULL,
  native_resolve_fn = NULL
)
```

## Arguments

- name:

  Backend identifier (e.g., `"nifti"`, `"hdf5"`).

- resolve_fn:

  Function with signature `function(locator, selector, logical_schema)`
  returning the resolved array/value.

- detect_fn:

  Optional function `function(locator)` returning `TRUE` if this backend
  can handle the given locator.

- write_fn:

  Optional function with signature
  `function(locator, value, logical_schema, template = NULL, source_ref = NULL)`
  that materializes a derived feature value to `locator`.

- native_resolve_fn:

  Optional function with the same signature as `resolve_fn` but
  returning a native R object (e.g., a `NeuroVol`) rather than a plain
  array. Used by
  [`nf_resolve()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_resolve.md)
  when `as_array = FALSE`.
