# Run the neurotabs command-line interface

`nf_cli()` exposes core NFTab operations from the shell without
requiring users to write an R script first.

## Usage

``` r
nf_cli(args = commandArgs(trailingOnly = TRUE))
```

## Arguments

- args:

  Character vector of command-line arguments. Defaults to
  [`commandArgs()`](https://rdrr.io/r/base/commandArgs.html) trailing
  arguments.

## Value

Invisibly, an integer exit status.

## Details

Installed usage:

    Rscript -e 'neurotabs::nf_cli()' -- info path/to/nftab.yaml
    Rscript -e 'neurotabs::nf_cli()' -- validate path/to/nftab.yaml --level full

In a source checkout, you can also run:

    Rscript exec/neurotabs info inst/examples/roi-only/nftab.yaml

Available commands:

- `info`: summarize a dataset

- `validate`: run structural or full conformance checks

- `features`: list feature schemas

- `resolve`: materialize one feature value for one row

- `collect`: materialize one feature across all rows

- `copy`: read a dataset and write a normalized copy

Exit codes:

- `0`: success

- `1`: validation failed

- `2`: command usage or runtime error
