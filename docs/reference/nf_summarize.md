# Summarize a feature across rows or groups

For character `.f` values in `c("mean", "sum", "var", "sd", "se")`,
`neurotabs` performs an elementwise reduction over resolved feature
values and will batch NIfTI reads when possible. `"se"` computes the
standard error of the mean (`sd / sqrt(n)`). For a function `.f`, each
group receives the list of resolved values for that feature.

## Usage

``` r
nf_summarize(x, feature, by = NULL, .f = "mean", ..., .progress = FALSE)

nf_summarise(x, feature, by = NULL, .f = "mean", ..., .progress = FALSE)
```

## Arguments

- x:

  An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
  object.

- feature:

  Feature name as a string or unquoted symbol.

- by:

  Optional character vector of observation columns defining groups.

- .f:

  Either a function or a fixed reducer name (`"mean"`, `"sum"`, `"var"`,
  `"sd"`, `"se"`).

- ...:

  Additional arguments passed to `.f` when `.f` is a function.

- .progress:

  Show progress during generic resolution. Default `FALSE`.

## Value

If `by = NULL`, a single reduced value. Otherwise an
[nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md) with
one row per group and a summarized feature named `feature`.
