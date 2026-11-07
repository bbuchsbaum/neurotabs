# Summary Profile 0.1: stored values only; no statistical computation.

#' Validate portable stored summaries
#'
#' Validate the optional NFTab Summary Profile, including referenced CSV/TSV
#' tables. This is separate from core [nf_validate()] conformance. Bounds are
#' checked as stored; they are never recalculated. Requires suggested package
#' `jsonvalidate` for the bundled JSON Schemas.
#'
#' @param x An [nftab], a standalone descriptor list, or a path to a JSON/YAML
#'   standalone descriptor or NFTab manifest.
#' @param root Directory containing referenced tables. Defaults to the input
#'   file's directory or an nftab's root. Required for descriptor lists.
#' @return Invisibly, a list with `valid`, `errors`, `warnings`, and `tables`.
#'   `tables` contains successfully validated data frames. Extra columns remain
#'   text; reserved numeric columns are parsed as doubles. Validation failures
#'   are reported in `errors`, including missing files and dependencies.
#' @examples
#' descriptor <- system.file("schema", "summary", "descriptor.json",
#'                           package = "neurotabs")
#' if (requireNamespace("jsonvalidate", quietly = TRUE)) {
#'   nf_validate_summary(descriptor)$valid
#' }
#' @export
nf_validate_summary <- function(x, root = NULL) {
  errors <- character()
  tables <- list()
  result <- tryCatch({
    if (inherits(x, "nftab")) {
      root <- root %||% x$.root
      x <- x$manifest$extensions[["x-summary"]]
    } else if (is.character(x) && length(x) == 1L) {
      root <- root %||% dirname(normalizePath(x, mustWork = TRUE))
      x <- switch(tolower(tools::file_ext(x)),
                  json = jsonlite::fromJSON(x, simplifyVector = FALSE),
                  yaml = yaml::read_yaml(x), yml = yaml::read_yaml(x),
                  stop("summary descriptor must be JSON or YAML"))
      if (!is.null(x$spec_version)) x <- x$extensions[["x-summary"]]
    }
    if (is.null(x)) stop("no x-summary descriptor supplied")
    if (is.null(root)) stop("root is required for a descriptor list")
    .nf_summary_schema(x, "summary.schema.json", descriptor = TRUE)
    for (name in names(x$tables)) {
      tab <- x$tables[[name]]
      checked <- tryCatch({
        path <- .nf_summary_path(root, tab$table$path)
        data <- .nf_summary_read_table(path, tab$table$format, tab$statistic)
        plot <- tab$plot
        channels <- unlist(plot[intersect(names(plot), c("x", "color", "facet", "detail"))])
        refs <- unique(c(channels, names(plot$order)))
        if (!all(refs %in% names(data))) stop("plot references unknown columns")
        for (col in names(plot$order)) {
          if (!all(data[[col]][!is.na(data[[col]])] %in% unlist(plot$order[[col]]))) {
            stop("plot order omits table levels in '", col, "'")
          }
        }
        data
      }, error = function(e) e)
      if (inherits(checked, "error")) {
        errors <- c(errors, paste0("table '", name, "': ", conditionMessage(checked)))
      } else tables[[name]] <- checked
    }
    NULL
  }, error = function(e) conditionMessage(e))
  errors <- c(errors, result)
  invisible(list(valid = !length(errors), errors = errors,
                 warnings = character(), tables = tables))
}

.nf_summary_schema_path <- function(name) {
  system.file("schema", "summary", name, package = "neurotabs", mustWork = TRUE)
}

.nf_summary_registry <- function() {
  jsonlite::fromJSON(.nf_summary_schema_path("interval-kinds.json"),
                    simplifyVector = FALSE)$kinds
}

.nf_summary_schema <- function(value, schema, descriptor = FALSE) {
  if (!requireNamespace("jsonvalidate", quietly = TRUE)) {
    stop("jsonvalidate package required for summary validation")
  }
  if (descriptor) value <- .nf_summary_prepare_descriptor(value)
  encoded <- jsonlite::toJSON(value, auto_unbox = TRUE, null = "null", digits = I(17))
  valid <- jsonvalidate::json_validate(encoded, .nf_summary_schema_path(schema),
                                        engine = "ajv", verbose = TRUE)
  if (!isTRUE(valid)) {
    details <- attr(valid, "errors")
    message <- if (is.data.frame(details)) {
      paste(unique(paste0(details$instancePath, ": ", details$message)), collapse = "; ")
    } else "invalid metadata"
    stop("summary schema validation failed (", schema, "): ", message)
  }
  invisible(TRUE)
}

.nf_summary_prepare_descriptor <- function(value) {
  if (is.list(value$tables)) {
    # Preserve JSON objects and arrays even for empty or singleton R inputs.
    for (name in names(value$tables)) {
      tab <- value$tables[[name]]
      if (is.list(tab$design)) {
        d <- tab$design
        if (is.list(d$within) && !length(d$within)) d$within <- setNames(list(), character())
        if (!is.null(d$within)) d$within <- lapply(d$within, as.list)
        for (key in intersect(names(d), c("between", "repeat"))) d[[key]] <- as.list(d[[key]])
        tab$design <- d
      }
      if (!is.null(tab$plot$order)) {
        tab$plot$order <- lapply(tab$plot$order, as.list)
        if (!length(tab$plot$order)) tab$plot$order <- setNames(list(), character())
      }
      value$tables[[name]] <- tab
    }
  }
  value
}

.nf_summary_validate_row <- function(row, statistic = "mean") {
  .nf_summary_schema(row, "summary-row.schema.json")
  nums <- Filter(is.numeric, row)
  if (any(!is.finite(unlist(nums)))) stop("summary numbers must be finite")
  if (!is.null(row$lower) && row$lower > row$upper) stop("lower exceeds upper")
  def <- Filter(function(x) identical(x$id, row$interval_kind), .nf_summary_registry())[[1L]]
  if (!statistic %in% unlist(def$statistics)) stop("interval kind is incompatible with statistic")
  invisible(TRUE)
}

.nf_summary_read_table <- function(path, format, statistic) {
  bytes <- readBin(path, "raw", file.info(path)$size)
  if (length(bytes) >= 3L && identical(bytes[1:3], as.raw(c(0xef, 0xbb, 0xbf)))) bytes <- bytes[-(1:3)]
  text <- rawToChar(bytes)
  Encoding(text) <- "UTF-8"
  if (!validUTF8(text)) stop("summary table must be UTF-8")
  # Empty lines after the last record are ignored; empty lines between records stay errors.
  text <- sub("\n+$", "", gsub("\r\n", "\n", text, fixed = TRUE))
  # Read the header as data so rows wider or narrower than it are rejected
  # instead of being shifted into row names.
  raw <- utils::read.table(text = text, header = FALSE, sep = if (format == "csv") "," else "\t",
                          quote = '"', comment.char = "", colClasses = "character",
                          na.strings = character(), check.names = FALSE, fill = FALSE,
                          blank.lines.skip = FALSE, encoding = "UTF-8", strip.white = FALSE)
  header <- unlist(raw[1L, ], use.names = FALSE)
  if (any(!nzchar(header))) stop("summary columns must have nonempty names")
  if (anyDuplicated(header)) stop("duplicate summary columns")
  frame <- raw[-1L, , drop = FALSE]
  names(frame) <- header
  rownames(frame) <- NULL
  frame[] <- lapply(frame, function(v) { v[!nzchar(v)] <- NA_character_; v })
  schema <- jsonlite::fromJSON(.nf_summary_schema_path("summary-row.schema.json"),
                              simplifyVector = FALSE)
  if (!all(unlist(schema$required) %in% names(frame))) stop("missing required summary columns")
  numeric_cols <- names(Filter(function(x) any(unlist(x$type) %in% c("number", "integer")),
                              schema$properties))
  for (name in intersect(names(frame), numeric_cols)) {
    raw <- frame[[name]]
    number <- suppressWarnings(as.numeric(raw))
    bad <- !is.na(raw) & (!grepl("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$", raw) |
                          !is.finite(number))
    if (any(bad)) stop("invalid numeric cell in '", name, "'")
    frame[[name]] <- number
  }
  for (i in seq_len(nrow(frame))) {
    row <- lapply(frame[i, , drop = FALSE], function(v) if (is.na(v)) NULL else v)
    tryCatch(.nf_summary_validate_row(row, statistic), error = function(e) {
      stop("row ", i, ": ", conditionMessage(e), call. = FALSE)
    })
  }
  frame
}

# Check both lexical paths and resolved ancestors, including symlink escapes.
.nf_summary_path <- function(root, path, must_exist = TRUE) {
  if (length(path) != 1L || is.na(path) || !nzchar(path) ||
      grepl("^/|[:\\\\]", path) || any(strsplit(path, "/", fixed = TRUE)[[1L]] == "..")) {
    stop("summary path must stay inside the package")
  }
  parts <- strsplit(path, "/", fixed = TRUE)[[1L]]
  path <- paste(parts[!parts %in% c("", ".")], collapse = "/")
  if (!nzchar(path)) stop("summary path must name a file")
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  target <- file.path(root, path)
  ancestor <- target
  suffix <- character()
  while (!file.exists(ancestor)) {
    link <- Sys.readlink(ancestor)
    if (!is.na(link) && nzchar(link)) stop("broken symlink in summary path")
    suffix <- c(basename(ancestor), suffix)
    ancestor <- dirname(ancestor)
  }
  if (length(suffix) && !dir.exists(ancestor)) stop("summary path parent is not a directory")
  actual <- normalizePath(ancestor, winslash = "/", mustWork = TRUE)
  if (!identical(actual, root) && !startsWith(actual, paste0(root, "/"))) {
    stop("summary path escapes the package")
  }
  if (must_exist && (!file.exists(target) || dir.exists(target))) stop("summary table file not found: ", path)
  do.call(file.path, c(list(actual), as.list(suffix)))
}

.nf_drop_summary <- function(manifest, operation) {
  if (!is.null(manifest$extensions[["x-summary"]])) {
    manifest$extensions[["x-summary"]] <- NULL
    warning(operation, " dropped x-summary because its stored summaries may be stale", call. = FALSE)
  }
  manifest
}

# Preflight all sources, destinations, and collisions before nf_write writes files.
.nf_summary_copy_plan <- function(x, path, manifest_name) {
  ext <- x$manifest$extensions[["x-summary"]]
  if (is.null(ext)) return(list())
  root <- x$.root %||% path
  result <- nf_validate_summary(ext, root)
  if (!result$valid) stop(paste(result$errors, collapse = "\n"), call. = FALSE)
  reserved <- c(x$manifest$observation_table$path, x$manifest$resources$path, manifest_name)
  refs <- unique(vapply(ext$tables, function(t) t$table$path, ""))
  # Compare case-insensitively: macOS and Windows filesystems usually are.
  reserved <- tolower(vapply(reserved, function(ref) .nf_summary_path(path, ref, FALSE), ""))
  destinations <- tolower(vapply(refs, function(ref) .nf_summary_path(path, ref, FALSE), ""))
  nested <- function(a, b) any(outer(a, b, function(p, q) startsWith(p, paste0(q, "/"))))
  if (any(destinations %in% reserved) || nested(destinations, reserved) || nested(reserved, destinations)) {
    stop("summary table path collides with a core output file", call. = FALSE)
  }
  if (anyDuplicated(destinations) || nested(destinations, destinations)) {
    stop("summary table paths collide with each other", call. = FALSE)
  }
  plan <- lapply(refs, function(ref) {
    src <- .nf_summary_path(root, ref)
    dest <- .nf_summary_path(path, ref, must_exist = FALSE)
    if (file.exists(dest) && !identical(normalizePath(src), normalizePath(dest)) &&
        !identical(digest::digest(file = src, algo = "sha256"), digest::digest(file = dest, algo = "sha256"))) {
      stop("summary destination already contains different data: ", ref)
    }
    list(src = src, dest = dest)
  })
  plan
}

.nf_summary_copy <- function(plan) {
  for (item in plan) {
    if (file.exists(item$dest) && identical(normalizePath(item$src), normalizePath(item$dest))) next
    dir.create(dirname(item$dest), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(item$src, item$dest, overwrite = TRUE)) stop("could not copy summary table")
  }
}
