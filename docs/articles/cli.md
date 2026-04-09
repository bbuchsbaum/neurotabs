# Driving neurotabs from the Command Line

This vignette shows how to inspect, validate, materialize, and rewrite
an NFTab dataset from the shell. The goal is not to replace the R API.
It is to make the package usable in scripts, CI checks, and quick
terminal workflows where you want a stable command surface over the core
`nf_*` functions.

The examples use the packaged ROI-only dataset, so every command is
runnable as written and every result can be checked in-code.

## What Does The CLI Expose?

The CLI wraps the same read, validate, resolve, collect, and write paths
that the package exposes in R.

``` r
help_out <- run_cli("help")
stopifnot(help_out$status == 0L)
cat(paste(utils::head(strip_rscript_noise(help_out$output), 15), collapse = "\n"))
#> neurotabs command-line interface
#> 
#> Usage:
#>   neurotabs <command> [options]
#> 
#> Commands:
#>   info <manifest>
#>   validate <manifest> [--level structural|full] [--progress]
#>   features <manifest>
#>   resolve <manifest> <feature> (--row <row_id> | --index <n>)
#>   collect <manifest> <feature> [--out <path>] [--format json|csv|tsv]
#>   copy <manifest> <out_dir> [--manifest-name <name>]
#> 
#> Global conventions:
#>   --no-schema  Skip JSON Schema validation during read
```

The commands in this first pass are:

- `info`
- `validate`
- `features`
- `resolve`
- `collect`
- `copy`

## How Do You Inspect A Dataset Quickly?

Start with `info`. It reads the manifest, loads the observation table,
and prints a compact dataset summary.

``` r
info_out <- run_cli("info", roi_path, "--json")
stopifnot(info_out$status == 0L)
info_payload <- extract_json(info_out$output)
info_payload
#> $dataset_id
#> [1] "roi-only"
#> 
#> $manifest
#> [1] "/Users/bbuchsbaum/code/neurotabs/inst/examples/roi-only/nftab.yaml"
#> 
#> $spec_version
#> [1] "0.1.0"
#> 
#> $storage_profile
#> [1] "table-package"
#> 
#> $n_observations
#> [1] 8
#> 
#> $features
#> [1] "roi_beta"
#> 
#> $axes
#> [1] "subject"   "condition"
#> 
#> $n_supports
#> [1] 0
#> 
#> $n_resources
#> [1] 0
```

That gives you the minimum orientation you need before doing anything
heavier: which dataset you are reading, how many rows it has, which
features it declares, and which observation axes define row identity.

## How Do You Check Conformance?

The `validate` command runs the same structural or full conformance
checks that
[`nf_validate()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_validate.md)
provides in R.

``` r
validate_out <- run_cli("validate", roi_path, "--level", "structural", "--json")
stopifnot(validate_out$status == 0L)
validate_payload <- extract_json(validate_out$output)
validate_payload
#> $valid
#> [1] TRUE
#> 
#> $level
#> [1] "structural"
#> 
#> $dataset_id
#> [1] "roi-only"
#> 
#> $manifest
#> [1] "/Users/bbuchsbaum/code/neurotabs/inst/examples/roi-only/nftab.yaml"
#> 
#> $errors
#> list()
#> 
#> $warnings
#> list()
```

If you want the stronger contract, use `--level full`. That attempts to
resolve every non-missing feature value, so it is the better fit for CI
or release checks.

``` r
full_out <- run_cli("validate", roi_path, "--level", "full", "--json")
stopifnot(full_out$status == 0L)
full_payload <- extract_json(full_out$output)
full_payload[c("valid", "level", "dataset_id")]
#> $valid
#> [1] TRUE
#> 
#> $level
#> [1] "full"
#> 
#> $dataset_id
#> [1] "roi-only"
```

## How Do You Discover The Feature Surface?

Use `features` when you need to know what a dataset can materialize
without opening the manifest by hand.

``` r
features_out <- run_cli("features", roi_path, "--json")
stopifnot(features_out$status == 0L)
features_payload <- extract_json(features_out$output, simplifyVector = FALSE)
features_payload
#> [[1]]
#> [[1]]$name
#> [1] "roi_beta"
#> 
#> [[1]]$kind
#> [1] "vector"
#> 
#> [[1]]$dtype
#> [1] "float32"
#> 
#> [[1]]$axes
#> [1] "roi"
#> 
#> [[1]]$shape
#> [1] 5
#> 
#> [[1]]$nullable
#> [1] FALSE
#> 
#> [[1]]$support_ref
#> NULL
#> 
#> [[1]]$encodings
#> [1] "columns"
```

For command-line work, this is the bridge between “there is a manifest
here” and “I know which feature names are valid arguments to `resolve`
or `collect`”.

## How Do You Materialize One Row?

`resolve` is the CLI equivalent of
[`nf_resolve()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_resolve.md).
You supply a feature plus a row selector, either by `row_id` or by
1-based row index.

``` r
resolve_out <- run_cli("resolve", roi_path, "roi_beta", "--row", "r01")
stopifnot(resolve_out$status == 0L)
resolve_payload <- extract_json(resolve_out$output)
resolve_payload
#> $dataset_id
#> [1] "roi-only"
#> 
#> $feature
#> [1] "roi_beta"
#> 
#> $row_id
#> [1] "r01"
#> 
#> $row_index
#> [1] 1
#> 
#> $value
#> [1] 0.31 0.44 0.29 0.18 0.22
```

This is the right tool when you are debugging one bad row, inspecting a
single feature binding, or spot-checking data before a larger job.

## How Do You Materialize A Feature Across All Rows?

`collect` resolves one feature across the full dataset. For fixed-size
1D features, it can emit a tabular result directly.

``` r
collect_file <- tempfile(fileext = ".csv")
collect_status <- run_cli("collect", roi_path, "roi_beta", "--out", collect_file, "--format", "csv")
stopifnot(collect_status$status == 0L, file.exists(collect_file))
collect_tbl <- utils::read.csv(collect_file, stringsAsFactors = FALSE)
collect_tbl
#>   row_id value_1 value_2 value_3 value_4 value_5
#> 1    r01    0.31    0.44    0.29    0.18    0.22
#> 2    r02    0.12    0.18    0.15    0.09    0.11
#> 3    r03    0.28    0.39    0.33    0.21    0.25
#> 4    r04    0.09    0.14    0.11    0.07    0.08
#> 5    r05    0.45    0.52    0.41    0.33    0.38
#> 6    r06    0.22    0.28    0.19    0.14    0.17
#> 7    r07    0.38    0.48    0.36    0.27    0.31
#> 8    r08    0.15    0.21    0.14    0.10    0.12
```

That output is intentionally simple: one row per observation, one
leading `row_id` column, and one column per resolved element.

## How Do You Rewrite A Dataset Cleanly?

`copy` is a read-and-write round trip. It is useful when you want to
normalize an existing dataset layout, rewrite checksums, or stage a
portable copy for another tool.

``` r
copy_dir <- tempfile("neurotabs-cli-copy-")
copy_out <- run_cli("copy", roi_path, copy_dir, "--json")
stopifnot(copy_out$status == 0L)
copy_payload <- extract_json(copy_out$output)
copy_payload
#> $dataset_id
#> [1] "roi-only"
#> 
#> $output_dir
#> [1] "/private/var/folders/9h/nkjq6vss7mqdl4ck7q1hd8ph0000gp/T/Rtmp4IEAfF/neurotabs-cli-copy-18957f2a7008"
#> 
#> $manifest
#> [1] "/private/var/folders/9h/nkjq6vss7mqdl4ck7q1hd8ph0000gp/T/Rtmp4IEAfF/neurotabs-cli-copy-18957f2a7008/nftab.yaml"
```

Because the command goes through
[`nf_read()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_read.md)
and
[`nf_write()`](https://bbuchsbaum.github.io/neurotabs/reference/nf_write.md),
it follows the same manifest parsing, dtype coercion, and
checksum-writing rules as the R API.

## When Should You Use The CLI Versus The R API?

Use the CLI when you need:

- a stable shell command in CI or Make targets
- a fast conformance check before handing data to another tool
- a quick summary or one-off materialization without writing R code

Use the R API when you need:

- filtering, grouping, and compute verbs
- integration with downstream analysis code
- custom control flow around errors, grouping, or feature
  transformations

The command-line layer is deliberately small. It covers the package’s
core dataset lifecycle without trying to reproduce the full interactive
grammar in shell flags.

## What Should You Read Next?

For the end-to-end R workflow, start with
[`vignette("neurotabs")`](https://bbuchsbaum.github.io/neurotabs/articles/neurotabs.md).
For the manifest contract itself, use
[`vignette("specification")`](https://bbuchsbaum.github.io/neurotabs/articles/specification.md).
