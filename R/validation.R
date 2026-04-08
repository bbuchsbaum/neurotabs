# Dataset validation
# Corresponds to NFTab spec section 14.

#' Validate an NFTab dataset
#'
#' Checks structural or full conformance.
#'
#' @param x An [nftab] object.
#' @param level `"structural"` or `"full"`. Full conformance additionally
#'   attempts to resolve every non-missing feature value.
#' @param .progress If `TRUE`, emit progress messages during full validation.
#'   Default `FALSE`.
#'
#' @return A list with `valid` (logical), `errors` (character vector), and
#'   `warnings` (character vector). Returned invisibly.
#' @export
nf_validate <- function(x, level = c("structural", "full"), .progress = FALSE) {
  level <- match.arg(level)
  errors <- character()
  warnings <- character()

  if (!inherits(x, "nftab")) {
    return(invisible(list(valid = FALSE,
                          errors = "input is not an nftab object",
                          warnings = character())))
  }

  m <- x$manifest
  obs <- x$observations

  # -- Structural checks -------------------------------------------------------

  # row_id present and unique
  rid <- m$row_id
  if (!rid %in% names(obs)) {
    errors <- c(errors, paste0("row_id column '", rid, "' not in observations"))
  } else if (anyDuplicated(obs[[rid]])) {
    errors <- c(errors, paste0("row_id column '", rid, "' has duplicates"))
  }

  # observation_axes present, non-null, tuple unique
  for (ax in m$observation_axes) {
    if (!ax %in% names(obs)) {
      errors <- c(errors, paste0("axis column '", ax, "' not in observations"))
    } else if (anyNA(obs[[ax]])) {
      errors <- c(errors, paste0("axis column '", ax, "' contains NAs"))
    }
  }

  ax_present <- all(m$observation_axes %in% names(obs))
  if (ax_present && length(m$observation_axes) > 0L) {
    ax_df <- obs[, m$observation_axes, drop = FALSE]
    if (anyDuplicated(ax_df)) {
      errors <- c(errors, "observation_axes tuple is not unique")
    }
  }

  # All declared observation_columns present
  for (col_name in names(m$observation_columns)) {
    if (!col_name %in% names(obs)) {
      errors <- c(errors, paste0("declared column '", col_name,
                                 "' not in observation table"))
      next
    }

    schema <- m$observation_columns[[col_name]]
    if (!schema$nullable && anyNA(obs[[col_name]])) {
      errors <- c(errors, paste0("non-nullable column '", col_name, "' contains NAs"))
    }

    # Check declared dtype vs actual R column type
    dtype_err <- .check_column_dtype_compat(obs[[col_name]], schema$dtype, col_name)
    if (!is.null(dtype_err)) {
      errors <- c(errors, dtype_err)
    }
  }

  undeclared_cols <- setdiff(names(obs), names(m$observation_columns))
  if (length(undeclared_cols)) {
    errors <- c(errors, paste0(
      "observation table has undeclared columns: ",
      paste(undeclared_cols, collapse = ", ")
    ))
  }

  # Features: validate encoding declarations
  required_support_refs <- character()
  for (fname in names(m$features)) {
    feat <- m$features[[fname]]
    if (feat$logical$kind %in% c("volume", "surface") && is.null(feat$logical$support_ref)) {
      errors <- c(errors, paste0(
        "feature '", fname, "' logical kind '", feat$logical$kind,
        "' requires support_ref"
      ))
    }
    if (!is.null(feat$logical$support_ref)) {
      required_support_refs <- c(required_support_refs, feat$logical$support_ref)
    }
    if (identical(feat$logical$kind, "volume") &&
        identical(feat$logical$alignment, "same_topology")) {
      errors <- c(errors, paste0(
        "feature '", fname, "' volume kind cannot use alignment 'same_topology'"
      ))
    }
    if (identical(feat$logical$kind, "surface") &&
        identical(feat$logical$alignment, "same_grid")) {
      errors <- c(errors, paste0(
        "feature '", fname, "' surface kind cannot use alignment 'same_grid'"
      ))
    }
    if (length(feat$encodings) == 0L) {
      errors <- c(errors, paste0("feature '", fname, "' has no encodings"))
    }

    # columns encoding: check columns exist
    for (enc in feat$encodings) {
      if (enc$type == "columns") {
        missing_cols <- setdiff(enc$binding$columns, names(m$observation_columns))
        if (length(missing_cols)) {
          errors <- c(errors, paste0("feature '", fname,
                                     "' columns encoding references missing columns: ",
                                     paste(missing_cols, collapse = ", ")))
        }
      }
      if (enc$type == "ref") {
        for (field in c("resource_id", "backend", "locator", "selector", "checksum")) {
          vs <- enc$binding[[field]]
          if (.is_column_ref(vs) && !vs$column %in% names(m$observation_columns)) {
            errors <- c(errors, paste0(
              "feature '", fname, "' ref ", field,
              " references undeclared column '", vs$column, "'"
            ))
          }
        }
      }
    }

    errors <- c(errors, .validate_feature_axis_domains(x, feat, fname))
  }

  required_support_refs <- unique(required_support_refs)
  if (length(required_support_refs)) {
    if (is.null(m$supports)) {
      errors <- c(errors, "manifest must define supports when any feature declares support_ref")
    } else {
      missing_supports <- setdiff(required_support_refs, names(m$supports))
      if (length(missing_supports)) {
        errors <- c(errors, paste0(
          "features reference unknown supports: ",
          paste(missing_supports, collapse = ", ")
        ))
      }
    }
  }

  if (!is.null(m$primary_feature) && !m$primary_feature %in% names(m$features)) {
    errors <- c(errors, paste0(
      "primary_feature '", m$primary_feature, "' is not declared in features"
    ))
  }

  # Resource registry: check if needed
  needs_registry <- FALSE
  for (feat in m$features) {
    for (enc in feat$encodings) {
      if (enc$type == "ref" && !is.null(enc$binding$resource_id)) {
        needs_registry <- TRUE
        break
      }
    }
    if (needs_registry) break
  }

  if (needs_registry && is.null(x$resources)) {
    errors <- c(errors, "feature uses resource_id but no resource registry provided")
  }

  errors <- c(errors, .validate_known_extensions(x))

  # -- Full conformance --------------------------------------------------------

  if (level == "full" && length(errors) == 0L) {
    n_features <- length(names(m$features))
    n_rows <- nrow(obs)
    total <- n_features * n_rows
    done <- 0L
    for (fname in names(m$features)) {
      feat <- m$features[[fname]]
      for (i in seq_len(n_rows)) {
        tryCatch({
          val <- nf_resolve(x, i, fname)
          if (is.null(val) && !feat$nullable) {
            errors <- c(errors, sprintf(
              "feature '%s' row %d: no applicable encoding (non-nullable)", fname, i))
          }
        }, error = function(e) {
          errors <<- c(errors, sprintf("feature '%s' row %d: %s", fname, i, e$message))
        })
        done <- done + 1L
        if (.progress && (done %% 10L == 0L || done == total)) {
          message(sprintf("  nf_validate: %d / %d resolutions", done, total))
        }
      }
    }
  }

  result <- list(
    valid = length(errors) == 0L,
    errors = errors,
    warnings = warnings
  )

  if (!result$valid) {
    message("Validation failed with ", length(errors), " error(s):")
    for (e in errors) message("  - ", e)
  } else {
    message("Dataset is ", level, "ly conformant.")
    if (length(warnings)) {
      for (w in warnings) message("  warning: ", w)
    }
  }

  invisible(result)
}

.validate_known_extensions <- function(x) {
  extensions <- x$manifest$extensions
  if (is.null(extensions) || length(extensions) == 0L) {
    return(character())
  }

  errors <- character()

  if (!is.null(extensions[["x-masked-volume"]])) {
    errors <- c(errors, .validate_masked_volume_extension(x, extensions[["x-masked-volume"]]))
  }

  errors
}

.validate_masked_volume_extension <- function(x, extension) {
  errors <- character()

  features <- extension$features
  if (is.null(features) || !is.list(features) || is.null(names(features)) ||
      any(!nzchar(names(features)))) {
    return("extension 'x-masked-volume' must contain a named 'features' map")
  }

  for (feature_name in names(features)) {
    spec <- features[[feature_name]]
    feat <- x$manifest$features[[feature_name]]
    if (is.null(feat)) {
      errors <- c(errors, paste0(
        "extension 'x-masked-volume' references unknown feature '", feature_name, "'"
      ))
      next
    }

    errors <- c(errors, .validate_masked_volume_feature(x, feat, feature_name, spec))
  }

  errors
}

.validate_masked_volume_feature <- function(x, feat, feature_name, spec) {
  errors <- character()

  if (!identical(feat$logical$kind, "vector") || !identical(feat$logical$axes, "voxel")) {
    errors <- c(errors, paste0(
      "extension 'x-masked-volume' feature '", feature_name,
      "' must have logical kind 'vector' with axes ['voxel']"
    ))
  }

  grid_axes <- spec$grid_axes
  if (!is.character(grid_axes) || length(grid_axes) != 3L || any(!nzchar(grid_axes))) {
    errors <- c(errors, paste0(
      "extension 'x-masked-volume' feature '", feature_name,
      "' must declare grid_axes as three non-empty strings"
    ))
  }

  grid_shape <- suppressWarnings(as.integer(spec$grid_shape))
  if (length(grid_shape) != 3L || any(is.na(grid_shape)) || any(grid_shape < 1L)) {
    errors <- c(errors, paste0(
      "extension 'x-masked-volume' feature '", feature_name,
      "' must declare grid_shape as three positive integers"
    ))
  }

  index_base <- spec$grid_index_base %||% 0L
  index_base <- suppressWarnings(as.integer(index_base))
  if (length(index_base) != 1L || is.na(index_base) || !index_base %in% c(0L, 1L)) {
    errors <- c(errors, paste0(
      "extension 'x-masked-volume' feature '", feature_name,
      "' grid_index_base must be 0 or 1"
    ))
  }

  index_map <- spec$index_map
  if (is.null(index_map$path) || is.null(index_map$format)) {
    errors <- c(errors, paste0(
      "extension 'x-masked-volume' feature '", feature_name,
      "' must declare index_map.path and index_map.format"
    ))
    return(errors)
  }

  if (!identical(index_map$format, "csv") &&
      !identical(index_map$format, "tsv") &&
      !identical(index_map$format, "parquet")) {
    errors <- c(errors, paste0(
      "extension 'x-masked-volume' feature '", feature_name,
      "' index_map.format must be one of csv, tsv, or parquet"
    ))
    return(errors)
  }

  map_path <- .resolve_axis_labels_path(x$.root, index_map$path)
  if (is.null(map_path)) {
    errors <- c(errors, paste0(
      "extension 'x-masked-volume' feature '", feature_name,
      "' index_map path is relative but dataset root is unknown"
    ))
    return(errors)
  }
  if (!file.exists(map_path)) {
    errors <- c(errors, paste0(
      "extension 'x-masked-volume' feature '", feature_name,
      "' index_map file not found: ", index_map$path
    ))
    return(errors)
  }

  map_df <- tryCatch(
    .read_table(map_path, index_map$format),
    error = function(e) e
  )
  if (inherits(map_df, "error")) {
    errors <- c(errors, paste0(
      "extension 'x-masked-volume' feature '", feature_name,
      "' index_map could not be read: ", map_df$message
    ))
    return(errors)
  }

  required_cols <- c("index", "x", "y", "z")
  missing_cols <- setdiff(required_cols, names(map_df))
  if (length(missing_cols)) {
    errors <- c(errors, paste0(
      "extension 'x-masked-volume' feature '", feature_name,
      "' index_map is missing required columns: ",
      paste(missing_cols, collapse = ", ")
    ))
    return(errors)
  }

  index_values <- suppressWarnings(as.integer(map_df$index))
  if (anyNA(index_values) || anyDuplicated(index_values)) {
    errors <- c(errors, paste0(
      "extension 'x-masked-volume' feature '", feature_name,
      "' index_map index column must contain unique integers"
    ))
  }

  coord_cols <- lapply(c("x", "y", "z"), function(col) suppressWarnings(as.integer(map_df[[col]])))
  if (any(vapply(coord_cols, function(col) anyNA(col), logical(1)))) {
    errors <- c(errors, paste0(
      "extension 'x-masked-volume' feature '", feature_name,
      "' index_map coordinates must be integers"
    ))
    return(errors)
  }

  if (length(grid_shape) == 3L && !any(is.na(grid_shape)) &&
      length(index_base) == 1L && !is.na(index_base)) {
    mins <- rep(index_base, 3L)
    maxs <- grid_shape - 1L + index_base
    for (j in seq_along(coord_cols)) {
      out_of_bounds <- coord_cols[[j]] < mins[[j]] | coord_cols[[j]] > maxs[[j]]
      if (any(out_of_bounds)) {
        errors <- c(errors, paste0(
          "extension 'x-masked-volume' feature '", feature_name,
          "' index_map column '", c("x", "y", "z")[[j]],
          "' contains coordinates outside declared grid_shape"
        ))
      }
    }
  }

  if (length(index_values) && !setequal(index_values, seq_len(nrow(map_df)))) {
    errors <- c(errors, paste0(
      "extension 'x-masked-volume' feature '", feature_name,
      "' index_map index column must cover 1:", nrow(map_df)
    ))
  }

  if (!is.null(feat$logical$shape) && length(feat$logical$shape) == 1L &&
      nrow(map_df) != as.integer(feat$logical$shape[[1L]])) {
    errors <- c(errors, paste0(
      "extension 'x-masked-volume' feature '", feature_name,
      "' index_map has ", nrow(map_df),
      " rows but logical shape expects ", as.integer(feat$logical$shape[[1L]])
    ))
  }

  errors
}

.validate_feature_axis_domains <- function(x, feat, feature_name) {
  errors <- character()
  axis_domains <- feat$logical$axis_domains

  if (is.null(axis_domains) || length(axis_domains) == 0L) {
    return(errors)
  }

  axis_names <- names(axis_domains)
  if (is.null(axis_names) || any(!nzchar(axis_names))) {
    return(paste0("feature '", feature_name, "' axis_domains must be a named list"))
  }

  logical_axes <- feat$logical$axes %||% character()
  for (axis_name in axis_names) {
    if (!axis_name %in% logical_axes) {
      errors <- c(errors, paste0(
        "feature '", feature_name, "' axis_domains entry '", axis_name,
        "' is not present in logical axes"
      ))
      next
    }

    domain <- axis_domains[[axis_name]]
    if (is.null(domain$labels) || !nzchar(domain$labels)) {
      next
    }

    labels_path <- .resolve_axis_labels_path(x$.root, domain$labels)
    if (is.null(labels_path)) {
      errors <- c(errors, paste0(
        "feature '", feature_name, "' axis '", axis_name,
        "' labels path is relative but dataset root is unknown"
      ))
      next
    }

    if (!file.exists(labels_path)) {
      errors <- c(errors, paste0(
        "feature '", feature_name, "' axis '", axis_name,
        "' labels file not found: ", domain$labels
      ))
      next
    }

    label_table <- tryCatch(
      .read_table(labels_path, "tsv"),
      error = function(e) e
    )
    if (inherits(label_table, "error")) {
      errors <- c(errors, paste0(
        "feature '", feature_name, "' axis '", axis_name,
        "' labels file could not be read as TSV: ", label_table$message
      ))
      next
    }

    missing_cols <- setdiff(c("index", "label"), names(label_table))
    if (length(missing_cols)) {
      errors <- c(errors, paste0(
        "feature '", feature_name, "' axis '", axis_name,
        "' labels file is missing required columns: ",
        paste(missing_cols, collapse = ", ")
      ))
      next
    }

    if (anyNA(label_table$label) || any(trimws(as.character(label_table$label)) == "")) {
      errors <- c(errors, paste0(
        "feature '", feature_name, "' axis '", axis_name,
        "' labels file contains missing or empty labels"
      ))
    }

    index_values <- suppressWarnings(as.integer(label_table$index))
    if (anyNA(index_values)) {
      errors <- c(errors, paste0(
        "feature '", feature_name, "' axis '", axis_name,
        "' labels file contains non-integer index values"
      ))
      next
    }

    if (anyDuplicated(index_values)) {
      errors <- c(errors, paste0(
        "feature '", feature_name, "' axis '", axis_name,
        "' labels file contains duplicate index values"
      ))
    }

    expected_size <- .expected_axis_domain_size(feat, axis_name, domain)
    if (!is.null(expected_size) && nrow(label_table) != expected_size) {
      errors <- c(errors, paste0(
        "feature '", feature_name, "' axis '", axis_name,
        "' labels file has ", nrow(label_table),
        " rows but expected ", expected_size
      ))
    }

    if (!is.null(expected_size) && !setequal(index_values, seq_len(expected_size))) {
      errors <- c(errors, paste0(
        "feature '", feature_name, "' axis '", axis_name,
        "' labels file index column must cover 1:", expected_size
      ))
    }
  }

  errors
}

.resolve_axis_labels_path <- function(root, path) {
  if (grepl("^(/|[a-zA-Z]:|[a-zA-Z][a-zA-Z0-9+.-]*://)", path)) {
    return(path)
  }

  if (is.null(root)) {
    return(NULL)
  }

  file.path(root, path)
}

.expected_axis_domain_size <- function(feat, axis_name, domain) {
  if (length(domain$size) == 1L && !is.na(domain$size)) {
    return(as.integer(domain$size))
  }

  axis_index <- match(axis_name, feat$logical$axes %||% character())
  if (!is.na(axis_index) && length(feat$logical$shape) >= axis_index) {
    return(as.integer(feat$logical$shape[[axis_index]]))
  }

  if (length(feat$logical$axes %||% character()) != 1L) {
    return(NULL)
  }

  columns_encodings <- Filter(function(enc) identical(enc$type, "columns"), feat$encodings)
  if (length(columns_encodings) != 1L) {
    return(NULL)
  }

  length(columns_encodings[[1]]$binding$columns)
}

# Check that an R column's actual type is compatible with its declared dtype.
# Returns NULL if compatible, or a single error string if not.
.check_column_dtype_compat <- function(values, dtype, col_name) {
  # Skip check for columns that are entirely NA (type is ambiguous)
  if (all(is.na(values))) return(NULL)

  ok <- switch(dtype,
    string   = is.character(values),
    int32    = , int64 = , uint8 = , uint16 = is.integer(values) || is.numeric(values),
    float32  = , float64 = is.numeric(values),
    bool     = is.logical(values),
    date     = inherits(values, "Date"),
    datetime = inherits(values, "POSIXt"),
    json     = is.character(values),
    TRUE # unknown dtype — don't flag

  )

  if (!isTRUE(ok)) {
    actual <- paste(class(values), collapse = "/")
    return(paste0(
      "column '", col_name, "' declared as ", dtype,
      " but R type is ", actual
    ))
  }

  NULL
}
