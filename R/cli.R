# Command-line interface for neurotabs

#' Run the neurotabs command-line interface
#'
#' `nf_cli()` exposes core NFTab operations from the shell without requiring
#' users to write an R script first.
#'
#' Installed usage:
#'
#' ```sh
#' Rscript -e 'neurotabs::nf_cli()' -- info path/to/nftab.yaml
#' Rscript -e 'neurotabs::nf_cli()' -- validate path/to/nftab.yaml --level full
#' ```
#'
#' In a source checkout, you can also run:
#'
#' ```sh
#' Rscript exec/neurotabs info inst/examples/roi-only/nftab.yaml
#' ```
#'
#' Available commands:
#' - `info`: summarize a dataset
#' - `validate`: run structural or full conformance checks
#' - `features`: list feature schemas
#' - `resolve`: materialize one feature value for one row
#' - `collect`: materialize one feature across all rows
#' - `copy`: read a dataset and write a normalized copy
#'
#' Exit codes:
#' - `0`: success
#' - `1`: validation failed
#' - `2`: command usage or runtime error
#'
#' @param args Character vector of command-line arguments. Defaults to
#'   [commandArgs()] trailing arguments.
#'
#' @return Invisibly, an integer exit status.
#' @export
nf_cli <- function(args = commandArgs(trailingOnly = TRUE)) {
  if (!length(args)) {
    .nf_cli_write(.nf_cli_help())
    return(invisible(0L))
  }

  cmd <- args[[1L]]
  rest <- args[-1L]

  if (cmd %in% c("help", "--help", "-h")) {
    topic <- if (length(rest)) rest[[1L]] else NULL
    .nf_cli_write(.nf_cli_help(topic))
    return(invisible(0L))
  }

  handler <- switch(
    cmd,
    info = .nf_cli_info,
    validate = .nf_cli_validate,
    features = .nf_cli_features,
    resolve = .nf_cli_resolve,
    collect = .nf_cli_collect,
    copy = .nf_cli_copy,
    NULL
  )

  if (is.null(handler)) {
    .nf_cli_error(
      paste0("unknown command '", cmd, "'. Use 'help' to see available commands."),
      status = 2L
    )
  }

  tryCatch(
    invisible(as.integer(handler(rest))),
    error = function(e) {
      .nf_cli_error(conditionMessage(e), status = 2L)
    }
  )
}

.nf_cli_info <- function(args) {
  parsed <- .nf_cli_parse_args(
    args,
    value_opts = character(),
    flag_opts = c("json", "no-schema")
  )
  .nf_cli_expect_args(parsed$args, 1L, "info <manifest>")

  ds <- nf_read(parsed$args[[1L]], validate_schema = !parsed$options$`no-schema`)
  summary <- .nf_cli_dataset_summary(ds, normalizePath(parsed$args[[1L]], mustWork = TRUE))

  if (parsed$options$json) {
    .nf_cli_write_json(summary)
  } else {
    .nf_cli_write(c(
      paste0("dataset_id: ", summary$dataset_id),
      paste0("manifest: ", summary$manifest),
      paste0("spec_version: ", summary$spec_version),
      paste0("storage_profile: ", summary$storage_profile),
      paste0("observations: ", summary$n_observations),
      paste0("features: ", paste(summary$features, collapse = ", ")),
      paste0("axes: ", paste(summary$axes, collapse = ", ")),
      paste0("supports: ", summary$n_supports),
      paste0("resources: ", summary$n_resources)
    ))
  }

  0L
}

.nf_cli_validate <- function(args) {
  parsed <- .nf_cli_parse_args(
    args,
    value_opts = c("level"),
    flag_opts = c("json", "no-schema", "progress")
  )
  .nf_cli_expect_args(parsed$args, 1L, "validate <manifest>")

  level <- parsed$options$level %||% "structural"
  ds <- nf_read(parsed$args[[1L]], validate_schema = !parsed$options$`no-schema`)
  result <- suppressMessages(
    nf_validate(ds, level = level, .progress = parsed$options$progress)
  )
  payload <- list(
    valid = isTRUE(result$valid),
    level = level,
    dataset_id = ds$manifest$dataset_id,
    manifest = normalizePath(parsed$args[[1L]], mustWork = TRUE),
    errors = unname(result$errors),
    warnings = unname(result$warnings)
  )

  if (parsed$options$json) {
    .nf_cli_write_json(payload)
  } else if (isTRUE(payload$valid)) {
    .nf_cli_write(c(
      paste0("VALID ", level),
      paste0("dataset_id: ", payload$dataset_id),
      paste0("manifest: ", payload$manifest)
    ))
  } else {
    .nf_cli_write(c(
      paste0("INVALID ", level),
      paste0("dataset_id: ", payload$dataset_id),
      paste0("manifest: ", payload$manifest),
      "errors:"
    ))
    .nf_cli_write(paste0("- ", payload$errors))
    if (length(payload$warnings)) {
      .nf_cli_write("warnings:")
      .nf_cli_write(paste0("- ", payload$warnings))
    }
  }

  if (isTRUE(payload$valid)) 0L else 1L
}

.nf_cli_features <- function(args) {
  parsed <- .nf_cli_parse_args(
    args,
    value_opts = character(),
    flag_opts = c("json", "no-schema")
  )
  .nf_cli_expect_args(parsed$args, 1L, "features <manifest>")

  ds <- nf_read(parsed$args[[1L]], validate_schema = !parsed$options$`no-schema`)
  features <- lapply(names(ds$manifest$features), function(name) {
    feat <- ds$manifest$features[[name]]
    list(
      name = name,
      kind = feat$logical$kind,
      dtype = feat$logical$dtype,
      axes = unname(feat$logical$axes),
      shape = unname(feat$logical$shape),
      nullable = isTRUE(feat$nullable),
      support_ref = feat$logical$support_ref,
      encodings = vapply(feat$encodings, function(enc) enc$type, character(1L))
    )
  })

  if (parsed$options$json) {
    .nf_cli_write_json(features)
  } else {
    lines <- c("name\tkind\tdtype\taxes\tshape\tnullable\tencodings")
    rows <- vapply(features, function(feat) {
      paste(
        feat$name,
        feat$kind,
        feat$dtype,
        paste(feat$axes, collapse = ","),
        paste(feat$shape, collapse = "x"),
        if (isTRUE(feat$nullable)) "true" else "false",
        paste(feat$encodings, collapse = ","),
        sep = "\t"
      )
    }, character(1L))
    .nf_cli_write(c(lines, rows))
  }

  0L
}

.nf_cli_resolve <- function(args) {
  parsed <- .nf_cli_parse_args(
    args,
    value_opts = c("row", "index"),
    flag_opts = c("json", "no-schema")
  )
  .nf_cli_expect_args(parsed$args, 2L, "resolve <manifest> <feature>")

  ds <- nf_read(parsed$args[[1L]], validate_schema = !parsed$options$`no-schema`)
  row_spec <- .nf_cli_row_index(ds, parsed$options$row, parsed$options$index)
  feature <- parsed$args[[2L]]
  value <- nf_resolve(ds, row_spec$index, feature)
  payload <- list(
    dataset_id = ds$manifest$dataset_id,
    feature = feature,
    row_id = row_spec$row_id,
    row_index = row_spec$index,
    value = value
  )

  if (!parsed$options$json) {
    .nf_cli_write_json(payload)
  } else {
    .nf_cli_write_json(payload)
  }

  0L
}

.nf_cli_collect <- function(args) {
  parsed <- .nf_cli_parse_args(
    args,
    value_opts = c("out", "format"),
    flag_opts = c("json", "no-schema", "progress", "no-simplify")
  )
  .nf_cli_expect_args(parsed$args, 2L, "collect <manifest> <feature>")

  ds <- nf_read(parsed$args[[1L]], validate_schema = !parsed$options$`no-schema`)
  feature <- parsed$args[[2L]]
  values <- nf_collect(
    ds,
    feature,
    simplify = !parsed$options$`no-simplify`,
    .progress = parsed$options$progress
  )

  out_path <- parsed$options$out
  format <- .nf_cli_collect_format(
    explicit = parsed$options$format,
    out_path = out_path,
    force_json = parsed$options$json
  )

  if (is.matrix(values) || is.data.frame(values)) {
    payload <- .nf_cli_collect_frame(ds, values)
    .nf_cli_emit_table(payload, format = format, out_path = out_path)
  } else {
    payload <- .nf_cli_collect_list(ds, values)
    if (format != "json") {
      stop("non-simplified collect output requires JSON format", call. = FALSE)
    }
    .nf_cli_emit_json(payload, out_path = out_path)
  }

  0L
}

.nf_cli_copy <- function(args) {
  parsed <- .nf_cli_parse_args(
    args,
    value_opts = c("manifest-name"),
    flag_opts = c("json", "no-schema")
  )
  .nf_cli_expect_args(parsed$args, 2L, "copy <manifest> <out_dir>")

  ds <- nf_read(parsed$args[[1L]], validate_schema = !parsed$options$`no-schema`)
  out_dir <- parsed$args[[2L]]
  manifest_name <- parsed$options$`manifest-name` %||% "nftab.yaml"
  written <- nf_write(ds, out_dir, manifest_name = manifest_name)

  payload <- list(
    dataset_id = ds$manifest$dataset_id,
    output_dir = normalizePath(written, mustWork = TRUE),
    manifest = normalizePath(file.path(written, manifest_name), mustWork = TRUE)
  )

  if (parsed$options$json) {
    .nf_cli_write_json(payload)
  } else {
    .nf_cli_write(c(
      paste0("copied: ", payload$dataset_id),
      paste0("output_dir: ", payload$output_dir),
      paste0("manifest: ", payload$manifest)
    ))
  }

  0L
}

.nf_cli_parse_args <- function(args, value_opts = character(), flag_opts = character()) {
  options <- setNames(vector("list", length(value_opts) + length(flag_opts)),
                      c(value_opts, flag_opts))
  if (length(flag_opts)) {
    for (flag in flag_opts) {
      options[[flag]] <- FALSE
    }
  }
  positionals <- character()
  i <- 1L

  while (i <= length(args)) {
    token <- args[[i]]
    if (!startsWith(token, "--")) {
      positionals <- c(positionals, token)
      i <- i + 1L
      next
    }

    if (token %in% c("--help", "-h")) {
      stop(.nf_cli_help_text_from_args(positionals), call. = FALSE)
    }

    parts <- strsplit(sub("^--", "", token), "=", fixed = TRUE)[[1L]]
    name <- parts[[1L]]
    has_inline <- length(parts) > 1L
    value <- if (has_inline) paste(parts[-1L], collapse = "=") else NULL

    if (name %in% flag_opts) {
      if (has_inline) {
        stop("flag '--", name, "' does not take a value", call. = FALSE)
      }
      options[[name]] <- TRUE
      i <- i + 1L
      next
    }

    if (name %in% value_opts) {
      if (!has_inline) {
        i <- i + 1L
        if (i > length(args)) {
          stop("option '--", name, "' requires a value", call. = FALSE)
        }
        value <- args[[i]]
      }
      options[[name]] <- value
      i <- i + 1L
      next
    }

    stop("unknown option '--", name, "'", call. = FALSE)
  }

  list(args = positionals, options = options)
}

.nf_cli_expect_args <- function(args, n, usage) {
  if (length(args) != n) {
    stop("usage: neurotabs ", usage, call. = FALSE)
  }
}

.nf_cli_row_index <- function(ds, row_id = NULL, index = NULL) {
  if (!is.null(row_id) && !is.null(index)) {
    stop("use either --row or --index, not both", call. = FALSE)
  }

  rid_col <- ds$manifest$row_id

  if (!is.null(row_id)) {
    match_idx <- match(row_id, ds$observations[[rid_col]])
    if (is.na(match_idx)) {
      stop("unknown row_id: ", row_id, call. = FALSE)
    }
    return(list(index = match_idx, row_id = row_id))
  }

  if (!is.null(index)) {
    idx <- suppressWarnings(as.integer(index))
    if (length(idx) != 1L || is.na(idx) || idx < 1L || idx > nrow(ds$observations)) {
      stop("--index must be an integer between 1 and ", nrow(ds$observations), call. = FALSE)
    }
    return(list(index = idx, row_id = as.character(ds$observations[[rid_col]][[idx]])))
  }

  stop("resolve requires --row <row_id> or --index <n>", call. = FALSE)
}

.nf_cli_dataset_summary <- function(ds, manifest_path) {
  list(
    dataset_id = ds$manifest$dataset_id,
    manifest = manifest_path,
    spec_version = ds$manifest$spec_version,
    storage_profile = ds$manifest$storage_profile,
    n_observations = nf_nobs(ds),
    features = unname(nf_feature_names(ds)),
    axes = unname(nf_axes(ds)),
    n_supports = if (is.null(ds$manifest$supports)) 0L else length(ds$manifest$supports),
    n_resources = if (is.null(ds$resources)) 0L else nrow(ds$resources)
  )
}

.nf_cli_collect_frame <- function(ds, values) {
  if (is.data.frame(values)) {
    values <- as.matrix(values)
  }
  if (is.null(colnames(values))) {
    colnames(values) <- paste0("value_", seq_len(ncol(values)))
  }
  out <- as.data.frame(values, stringsAsFactors = FALSE, check.names = FALSE)
  out <- cbind(
    row_id = as.character(ds$observations[[ds$manifest$row_id]]),
    out,
    stringsAsFactors = FALSE
  )
  rownames(out) <- NULL
  out
}

.nf_cli_collect_list <- function(ds, values) {
  row_ids <- as.character(ds$observations[[ds$manifest$row_id]])
  names(values) <- row_ids
  lapply(seq_along(values), function(i) {
    list(
      row_id = row_ids[[i]],
      value = values[[i]]
    )
  })
}

.nf_cli_collect_format <- function(explicit = NULL, out_path = NULL, force_json = FALSE) {
  if (isTRUE(force_json)) {
    return("json")
  }
  if (!is.null(explicit)) {
    explicit <- match.arg(explicit, c("json", "csv", "tsv"))
    return(explicit)
  }
  if (is.null(out_path)) {
    return("json")
  }

  ext <- tolower(tools::file_ext(out_path))
  switch(
    ext,
    json = "json",
    csv = "csv",
    tsv = "tsv",
    txt = "tsv",
    "json"
  )
}

.nf_cli_emit_table <- function(x, format, out_path = NULL) {
  if (format == "json") {
    .nf_cli_emit_json(x, out_path = out_path)
    return(invisible(NULL))
  }

  sep <- if (format == "tsv") "\t" else ","
  if (is.null(out_path)) {
    utils::write.table(x, file = stdout(), sep = sep, row.names = FALSE,
                       col.names = TRUE, quote = FALSE)
  } else {
    data.table::fwrite(x, out_path, sep = sep)
  }
  invisible(NULL)
}

.nf_cli_emit_json <- function(x, out_path = NULL) {
  json <- jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null")
  if (is.null(out_path)) {
    .nf_cli_write(json)
  } else {
    writeLines(json, out_path)
  }
  invisible(NULL)
}

.nf_cli_write_json <- function(x) {
  .nf_cli_emit_json(x, out_path = NULL)
}

.nf_cli_write <- function(x) {
  cat(paste(x, collapse = "\n"), "\n", sep = "")
}

.nf_cli_error <- function(message, status = 2L) {
  message("neurotabs: ", message)
  invisible(as.integer(status))
}

.nf_cli_help <- function(topic = NULL) {
  switch(
    topic %||% "root",
    root = c(
      "neurotabs command-line interface",
      "",
      "Usage:",
      "  neurotabs <command> [options]",
      "",
      "Commands:",
      "  info <manifest>",
      "  validate <manifest> [--level structural|full] [--progress]",
      "  features <manifest>",
      "  resolve <manifest> <feature> (--row <row_id> | --index <n>)",
      "  collect <manifest> <feature> [--out <path>] [--format json|csv|tsv]",
      "  copy <manifest> <out_dir> [--manifest-name <name>]",
      "",
      "Global conventions:",
      "  --no-schema  Skip JSON Schema validation during read",
      "  --json       Emit JSON output when the command supports text and JSON",
      "  --help       Show command help",
      "",
      "Installed invocation:",
      "  Rscript -e 'neurotabs::nf_cli()' -- <command> ...",
      "Source checkout invocation:",
      "  Rscript exec/neurotabs <command> ..."
    ),
    info = c("Usage: neurotabs info <manifest> [--json] [--no-schema]"),
    validate = c(
      "Usage: neurotabs validate <manifest> [--level structural|full]",
      "                          [--progress] [--json] [--no-schema]"
    ),
    features = c("Usage: neurotabs features <manifest> [--json] [--no-schema]"),
    resolve = c(
      "Usage: neurotabs resolve <manifest> <feature>",
      "                            (--row <row_id> | --index <n>) [--json] [--no-schema]"
    ),
    collect = c(
      "Usage: neurotabs collect <manifest> <feature>",
      "                            [--out <path>] [--format json|csv|tsv]",
      "                            [--no-simplify] [--progress] [--json] [--no-schema]"
    ),
    copy = c(
      "Usage: neurotabs copy <manifest> <out_dir>",
      "                         [--manifest-name <name>] [--json] [--no-schema]"
    ),
    c(
      "unknown help topic",
      "",
      paste(.nf_cli_help("root"), collapse = "\n")
    )
  )
}

.nf_cli_help_text_from_args <- function(positionals) {
  topic <- if (length(positionals)) positionals[[1L]] else NULL
  paste(.nf_cli_help(topic), collapse = "\n")
}
