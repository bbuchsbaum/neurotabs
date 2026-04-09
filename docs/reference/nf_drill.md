# Drill from a summary nftab back to contributing member rows

Returns the original observations that contributed to one or more
summary rows. The summary must have been produced by
[nf_summarize](https://bbuchsbaum.github.io/neurotabs/reference/nf_summarize.md),
which stores contributing row IDs in a `.members` list-column as JSON
arrays.

## Usage

``` r
nf_drill(summary, source, row_index = NULL)
```

## Arguments

- summary:

  A summarized
  [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
  with a `.members` observation column.

- source:

  The original
  [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
  that was summarized.

- row_index:

  Integer row position(s) or character row_id value(s) into `summary`.
  If `NULL` (default), all summary rows are drilled.

## Value

An [nftab](https://bbuchsbaum.github.io/neurotabs/reference/nftab.md)
containing the contributing rows from `source`.
