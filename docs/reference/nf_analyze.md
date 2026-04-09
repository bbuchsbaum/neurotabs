# Exploratory term tests over an NFTab feature

Fits fast exploratory term tests over a numeric NFTab feature and
returns the result as a new
[nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md). Rows
in the output represent generated tests, while result features hold the
corresponding statistic maps or vectors.

## Usage

``` r
nf_analyze(
  x,
  feature,
  formula,
  se_feature = NULL,
  contrasts = "auto",
  .progress = FALSE
)
```

## Arguments

- x:

  An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
  object.

- feature:

  Feature name to analyze, as a string or unquoted symbol.

- formula:

  Right-hand-side-only formula, for example `~ group * condition` or
  `~ group * condition + (1 | subject)`.

- se_feature:

  Optional standard-error feature. Currently not supported.

- contrasts:

  `"auto"` or `list(auto_max_order = 1L/2L)`.

- .progress:

  Show progress while materializing feature values. Default `FALSE`.

## Value

An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
with one row per generated test and feature maps/vectors named `stat`,
`p_value`, and `estimate` when a 1-df test has a signed contrast
estimate.

## Details

This helper is intentionally narrow. It supports independent-row fixed
effects, plus a constrained repeated-measures mode via a single random
term of the form `(1 | subject)`. It is not a general mixed-model
engine.
