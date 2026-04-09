# Write an NFTab dataset to disk (table-package profile)

Write an NFTab dataset to disk (table-package profile)

## Usage

``` r
nf_write(x, path, manifest_name = "nftab.yaml")
```

## Arguments

- x:

  An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
  object.

- path:

  Directory to write the dataset into. Created if it doesn't exist.

- manifest_name:

  Manifest filename. Default `"nftab.yaml"`.

## Value

Invisibly, the path written to.
