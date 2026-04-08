# Feature resolution engine
# Corresponds to NFTab spec section 11.

#' Resolve a single feature value for one row
#'
#' Evaluates the feature's encodings in priority order and returns the first
#' applicable result.
#'
#' @param x An [nftab] object.
#' @param row_index Integer row index, or a character `row_id` value.
#' @param feature Character name of the feature to resolve.
#' @param as_array If `TRUE` (default), the resolved value is returned as a
#'   plain R array.  If `FALSE`, the backend's native object is returned when
#'   available (e.g., a `NeuroVol` for the `"nifti"` backend with neuroim2),
#'   preserving spatial metadata such as voxel spacing and orientation.  Falls
#'   back to array resolution when the backend has no native resolver.
#'
#' @return The resolved feature value, or `NULL` if the feature is nullable
#'   and no encoding is applicable.
#' @export
nf_resolve <- function(x, row_index, feature, as_array = TRUE) {
  stopifnot(inherits(x, "nftab"))
  feat <- x$manifest$features[[feature]]
  if (is.null(feat)) {
    stop("unknown feature: '", feature, "'", call. = FALSE)
  }

  # Resolve row_index

  if (is.character(row_index)) {
    rid_col <- x$manifest$row_id
    idx <- match(row_index, x$observations[[rid_col]])
    if (is.na(idx)) stop("row_id '", row_index, "' not found", call. = FALSE)
    row_index <- idx
  }
  row <- as.list(x$observations[row_index, , drop = FALSE])

  # Walk encodings in order
  for (enc in feat$encodings) {
    if (!encoding_applicable(enc, row)) next

    if (enc$type == "columns") {
      value <- .materialize_columns(enc$binding$columns, row, feat$logical)
      .validate_resolved(value, feat$logical)
      return(value)
    }

    if (enc$type == "ref") {
      ref_info <- .materialize_ref(enc$binding, row, x$resources)
      # Attempt backend resolution
      value <- .resolve_via_backend(ref_info, feat$logical, x$.root,
                                    as_array = as_array)
      return(value)
    }
  }

  # No applicable encoding

  if (feat$nullable) return(NULL)
  stop("no applicable encoding for non-nullable feature '", feature,
       "' at row ", row_index, call. = FALSE)
}

#' Resolve all rows for a feature
#'
#' @param x An [nftab] object.
#' @param feature Character name of the feature.
#' @param .progress Show progress? Default `FALSE`.
#'
#' @return A list of resolved values, one per row. `NULL` entries indicate
#'   missing (nullable) values.
#' @export
nf_resolve_all <- function(x, feature, .progress = FALSE) {
  stopifnot(inherits(x, "nftab"))
  n <- nrow(x$observations)
  results <- vector("list", n)

  for (i in seq_len(n)) {
    results[i] <- list(nf_resolve(x, i, feature))
    if (.progress && i %% 10L == 0L) {
      message(sprintf("  resolved %d / %d", i, n))
    }
  }

  # Name by row_id
  names(results) <- x$observations[[x$manifest$row_id]]
  results
}

# -- Internal helpers ----------------------------------------------------------

#' Materialize ref binding into a resolution descriptor
#' @keywords internal
.materialize_ref <- function(binding, row, resources = NULL) {
  rid <- resolve_value_source(binding$resource_id, row)
  backend <- resolve_value_source(binding$backend, row)
  locator <- resolve_value_source(binding$locator, row)
  selector <- resolve_value_source(binding$selector, row)
  checksum <- resolve_value_source(binding$checksum, row)

  if (!is.null(rid) && !is.na(rid)) {
    if (is.null(resources)) {
      stop("resource_id '", rid, "' used but no resource registry provided",
           call. = FALSE)
    }
    reg_row <- resources[resources$resource_id == rid, , drop = FALSE]
    if (nrow(reg_row) == 0L) {
      stop("unknown resource_id: '", rid, "'", call. = FALSE)
    }
    backend <- reg_row$backend[1L]
    locator <- reg_row$locator[1L]
    reg_checksum <- if ("checksum" %in% names(reg_row)) reg_row$checksum[1L] else NULL
    if (!is.null(checksum) && !is.null(reg_checksum) &&
        !is.na(reg_checksum) && !is.na(checksum) &&
        checksum != reg_checksum) {
      stop("checksum mismatch for resource_id '", rid, "'", call. = FALSE)
    }
    if ((is.null(checksum) || is.na(checksum)) &&
        !is.null(reg_checksum) && !is.na(reg_checksum)) {
      checksum <- reg_checksum
    }
  }

  # Parse selector if it's a JSON string
  if (is.character(selector) && nzchar(selector)) {
    selector <- jsonlite::fromJSON(selector, simplifyVector = FALSE)
  }

  list(
    backend = backend,
    locator = locator,
    selector = selector,
    checksum = checksum
  )
}

.materialize_columns <- function(columns, row, logical_schema) {
  values <- unlist(row[columns], use.names = FALSE)
  .coerce_columns_value(values, logical_schema$dtype)
}

.coerce_columns_value <- function(values, dtype) {
  if (dtype == "string") {
    return(as.character(values))
  }

  if (dtype == "bool") {
    if (is.logical(values)) {
      return(values)
    }
    if (is.numeric(values)) {
      if (any(!values %in% c(0, 1))) {
        stop("boolean columns encoding requires values in {0, 1}", call. = FALSE)
      }
      return(as.logical(values))
    }
    if (is.character(values)) {
      normalized <- tolower(values)
      valid <- normalized %in% c("true", "false", "t", "f", "1", "0")
      if (!all(valid)) {
        stop("boolean columns encoding requires TRUE/FALSE-style strings", call. = FALSE)
      }
      return(normalized %in% c("true", "t", "1"))
    }
    stop("boolean columns encoding produced unsupported R type", call. = FALSE)
  }

  if (dtype %in% c("float32", "float64")) {
    return(as.numeric(values))
  }

  if (dtype %in% c("int32", "uint8", "uint16")) {
    numeric_values <- as.numeric(values)
    if (any(!is.finite(numeric_values)) || any(abs(numeric_values - round(numeric_values)) > 0)) {
      stop("integer columns encoding requires whole finite values", call. = FALSE)
    }
    return(as.integer(numeric_values))
  }

  if (dtype == "int64") {
    numeric_values <- as.numeric(values)
    if (any(!is.finite(numeric_values)) || any(abs(numeric_values - round(numeric_values)) > 0)) {
      stop("int64 columns encoding requires whole finite values", call. = FALSE)
    }
    return(numeric_values)
  }

  values
}

#' Dispatch to backend adapter for resolution
#' @keywords internal
.resolve_via_backend <- function(ref_info, logical_schema, root = NULL,
                                  as_array = TRUE) {
  backend <- ref_info$backend

  # Resolve relative path
  locator <- ref_info$locator
  if (!is.null(root) && !grepl("^(/|[a-zA-Z]:|[a-zA-Z][a-zA-Z0-9+.-]*://)", locator)) {
    locator <- file.path(root, locator)
  }
  .validate_resource_checksum(locator, ref_info$checksum)

  adapter <- .get_backend(backend)
  if (is.null(adapter)) {
    stop("no adapter registered for backend '", backend, "'", call. = FALSE)
  }

  if (!as_array && !is.null(adapter$native_resolve_fn)) {
    return(adapter$native_resolve_fn(locator, ref_info$selector, logical_schema))
  }

  value <- adapter$resolve_fn(locator, ref_info$selector, logical_schema)
  .validate_resolved(value, logical_schema)
  value
}

.validate_resource_checksum <- function(locator, checksum) {
  if (is.null(checksum) || is.na(checksum) || !nzchar(checksum)) {
    return(invisible(NULL))
  }

  parsed <- .parse_checksum_token(checksum)
  if (grepl("^[a-zA-Z][a-zA-Z0-9+.-]*://", locator) && !grepl("^file://", locator)) {
    stop("cannot validate checksum for non-file locator '", locator, "'", call. = FALSE)
  }

  file_path <- sub("^file://", "", locator)
  if (!file.exists(file_path)) {
    stop("cannot validate checksum: file not found '", file_path, "'", call. = FALSE)
  }

  actual <- digest::digest(file = file_path, algo = parsed$algo, serialize = FALSE)
  if (!identical(tolower(actual), parsed$value)) {
    stop(
      "checksum mismatch for locator '", locator, "' (expected ",
      parsed$token, ", got ", parsed$algo, ":", tolower(actual), ")",
      call. = FALSE
    )
  }

  invisible(NULL)
}

.parse_checksum_token <- function(token) {
  token <- tolower(trimws(as.character(token)))
  if (!nzchar(token)) {
    stop("checksum token must be non-empty", call. = FALSE)
  }

  if (grepl("^[a-z0-9]+:", token)) {
    parts <- strsplit(token, ":", fixed = TRUE)[[1L]]
    algo <- parts[1L]
    value <- paste(parts[-1L], collapse = ":")
  } else {
    n <- nchar(token)
    algo <- switch(
      as.character(n),
      `32` = "md5",
      `40` = "sha1",
      `64` = "sha256",
      NULL
    )
    value <- token
  }

  if (is.null(algo) || !algo %in% c("md5", "sha1", "sha256")) {
    stop("unsupported checksum token '", token,
         "'; use md5:, sha1:, or sha256:", call. = FALSE)
  }

  if (!grepl("^[0-9a-f]+$", value)) {
    stop("checksum token '", token, "' must contain lowercase hexadecimal digits",
         call. = FALSE)
  }

  expected_nchar <- c(md5 = 32L, sha1 = 40L, sha256 = 64L)[[algo]]
  if (nchar(value) != expected_nchar) {
    stop("checksum token '", token, "' has wrong length for ", algo, call. = FALSE)
  }

  list(algo = algo, value = value, token = paste0(algo, ":", value))
}

#' Validate resolved value against logical schema
#' @keywords internal
.validate_resolved <- function(value, logical_schema) {
  if (is.null(value)) return(invisible(NULL))

  .validate_resolved_dtype(value, logical_schema$dtype)

  # Shape check for arrays/vectors
  if (!is.null(logical_schema$shape) && length(logical_schema$axes) == 1L) {
    if (is.atomic(value) && length(value) != logical_schema$shape[1L]) {
      stop(sprintf("resolved value length %d != declared shape %d",
                   length(value), logical_schema$shape[1L]), call. = FALSE)
    }
  }

  if (!is.null(logical_schema$shape) && length(logical_schema$axes) > 1L) {
    if (is.array(value)) {
      actual <- dim(value)
      expected <- logical_schema$shape
      if (!identical(as.integer(actual), as.integer(expected))) {
        stop(sprintf("resolved value shape [%s] != declared shape [%s]",
                     paste(actual, collapse = ","),
                     paste(expected, collapse = ",")), call. = FALSE)
      }
    }
  }

  invisible(NULL)
}

.validate_resolved_dtype <- function(value, dtype) {
  flat <- if (is.array(value)) c(value) else value

  if (dtype == "string") {
    if (!is.character(flat)) {
      stop("resolved value dtype does not match declared string dtype", call. = FALSE)
    }
    return(invisible(NULL))
  }

  if (dtype == "bool") {
    if (!is.logical(flat)) {
      stop("resolved value dtype does not match declared bool dtype", call. = FALSE)
    }
    return(invisible(NULL))
  }

  if (dtype %in% c("float32", "float64")) {
    if (!is.numeric(flat)) {
      stop("resolved value dtype does not match declared floating dtype", call. = FALSE)
    }
    return(invisible(NULL))
  }

  if (dtype == "int32") {
    .validate_whole_numeric(flat, dtype, min_value = -2147483648, max_value = 2147483647)
    return(invisible(NULL))
  }

  if (dtype == "int64") {
    .validate_whole_numeric(flat, dtype)
    return(invisible(NULL))
  }

  if (dtype == "uint8") {
    .validate_whole_numeric(flat, dtype, min_value = 0, max_value = 255)
    return(invisible(NULL))
  }

  if (dtype == "uint16") {
    .validate_whole_numeric(flat, dtype, min_value = 0, max_value = 65535)
    return(invisible(NULL))
  }

  invisible(NULL)
}

.validate_whole_numeric <- function(values, dtype, min_value = NULL, max_value = NULL) {
  if (!is.numeric(values)) {
    stop("resolved value dtype does not match declared ", dtype, " dtype", call. = FALSE)
  }
  finite <- values[!is.na(values)]
  if (length(finite) && any(abs(finite - round(finite)) > 0)) {
    stop("resolved value contains non-integer values for declared ", dtype, " dtype",
         call. = FALSE)
  }
  if (!is.null(min_value) && length(finite) && any(finite < min_value)) {
    stop("resolved value violates minimum for declared ", dtype, " dtype", call. = FALSE)
  }
  if (!is.null(max_value) && length(finite) && any(finite > max_value)) {
    stop("resolved value violates maximum for declared ", dtype, " dtype", call. = FALSE)
  }
}
