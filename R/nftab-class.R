# Core NFTab data model: manifest, feature, and dataset classes
# Corresponds to NFTab spec sections 3-4, 7.

# -- Feature schema ------------------------------------------------------------

#' Declare a feature schema
#'
#' @param logical An [nf_logical_schema] object.
#' @param encodings A list of encoding objects created by [nf_ref_encoding()] or
#'   [nf_columns_encoding()].
#' @param nullable Whether missing values are permitted. Default `FALSE`.
#' @param description Optional description.
#'
#' @return An `nf_feature` object.
#' @export
nf_feature <- function(logical, encodings, nullable = FALSE, description = NULL) {

  stopifnot(inherits(logical, "nf_logical_schema"))
  if (inherits(encodings, "nf_encoding")) encodings <- list(encodings)
  stopifnot(is.list(encodings), length(encodings) >= 1L)
  inferred_shape <- logical$shape
  for (enc in encodings) {
    stopifnot(inherits(enc, "nf_encoding"))
    # columns encoding: validate 1D constraint
    if (enc$type == "columns" && length(logical$axes) != 1L) {
      stop("columns encoding is only valid for 1D logical features (draft 0.1)",
           call. = FALSE)
    }
    if (enc$type == "columns" && !is.null(logical$shape)) {
      if (logical$shape[1L] != length(enc$binding$columns)) {
        stop("shape[1] must equal number of bound columns for columns encoding",
             call. = FALSE)
      }
    }
    if (enc$type == "columns" && is.null(inferred_shape)) {
      inferred_shape <- as.integer(length(enc$binding$columns))
    }
  }

  if (!identical(inferred_shape, logical$shape)) {
    logical$shape <- inferred_shape
  }

  structure(
    list(
      logical = logical,
      encodings = encodings,
      nullable = nullable,
      description = description
    ),
    class = "nf_feature"
  )
}

#' @export
print.nf_feature <- function(x, ...) {
  cat("<nf_feature>")
  if (!is.null(x$description)) cat(" ", x$description)
  cat("\n")
  print(x$logical)
  cat("  encodings:", length(x$encodings), "\n")
  if (x$nullable) cat("  nullable: TRUE\n")
  invisible(x)
}

# -- Manifest ------------------------------------------------------------------

#' Create an NFTab manifest
#'
#' @param spec_version Semantic version string.
#' @param dataset_id Dataset identifier.
#' @param row_id Name of the row ID column.
#' @param observation_axes Character vector of axis column names.
#' @param observation_columns Named list of [nf_col_schema] objects.
#' @param features Named list of [nf_feature] objects.
#' @param storage_profile Storage profile (default `"table-package"`).
#' @param observation_table_path Path to observation table file.
#' @param observation_table_format Format (`"csv"`, `"tsv"`, or `"parquet"`).
#' @param resources_path Optional path to resource registry file.
#' @param resources_format Optional format of resource registry.
#' @param supports Optional named list of support descriptors created by
#'   [nf_support()], keyed by manifest-local support reference.
#' @param primary_feature Optional default feature name for consumers.
#' @param import_recipe Optional non-normative import metadata.
#' @param extensions Optional named list of extension data.
#'
#' @return An `nf_manifest` object.
#' @export
nf_manifest <- function(spec_version = "0.1.0",
                        dataset_id,
                        row_id,
                        observation_axes,
                        observation_columns,
                        features,
                        storage_profile = "table-package",
                        observation_table_path = "observations.csv",
                        observation_table_format = "csv",
                        resources_path = NULL,
                        resources_format = NULL,
                        supports = NULL,
                        primary_feature = NULL,
                        import_recipe = NULL,
                        extensions = NULL) {
  stopifnot(
    is.character(spec_version), length(spec_version) == 1L,
    grepl("^[0-9]+\\.[0-9]+\\.[0-9]+$", spec_version),
    is.character(dataset_id), length(dataset_id) == 1L, nzchar(dataset_id),
    is.character(row_id), length(row_id) == 1L,
    is.character(observation_axes), length(observation_axes) >= 1L,
    anyDuplicated(observation_axes) == 0L,
    is.list(observation_columns), length(observation_columns) >= 1L,
    is.list(features), length(features) >= 1L
  )

  storage_profile <- match.arg(storage_profile, c("table-package"))
  observation_table_format <- match.arg(observation_table_format, c("csv", "tsv", "parquet"))
  if (!is.null(resources_format)) {
    resources_format <- match.arg(resources_format, c("csv", "tsv", "parquet"))
  }

  if (!row_id %in% names(observation_columns)) {
    stop("row_id '", row_id, "' must be declared in observation_columns", call. = FALSE)
  }

  for (ax in observation_axes) {
    if (!ax %in% names(observation_columns)) {
      stop("observation axis '", ax, "' must be declared in observation_columns",
           call. = FALSE)
    }
  }

  for (nm in names(observation_columns)) {
    stopifnot(inherits(observation_columns[[nm]], "nf_col_schema"))
  }
  for (nm in names(features)) {
    stopifnot(inherits(features[[nm]], "nf_feature"))
  }
  if (!is.null(supports)) {
    stopifnot(is.list(supports), length(supports) >= 1L, !is.null(names(supports)))
    for (nm in names(supports)) {
      if (!nzchar(nm)) {
        stop("support references must be non-empty", call. = FALSE)
      }
      stopifnot(inherits(supports[[nm]], "nf_support_schema"))
    }
  }
  if (!is.null(primary_feature)) {
    stopifnot(is.character(primary_feature), length(primary_feature) == 1L, nzchar(primary_feature))
    if (!primary_feature %in% names(features)) {
      stop("primary_feature must reference a declared feature", call. = FALSE)
    }
  }
  if (!is.null(import_recipe)) {
    stopifnot(is.list(import_recipe))
  }

  if (!is.null(extensions)) {
    stopifnot(is.list(extensions), !is.null(names(extensions)))
    bad_extension_keys <- names(extensions)[!grepl("^x-", names(extensions))]
    if (length(bad_extension_keys)) {
      stop("extension keys must begin with 'x-': ",
           paste(bad_extension_keys, collapse = ", "), call. = FALSE)
    }
  }

  declared_cols <- names(observation_columns)
  required_support_refs <- character()
  for (fname in names(features)) {
    feat <- features[[fname]]
    support_ref <- feat$logical$support_ref
    if (feat$logical$kind %in% c("volume", "surface") && is.null(support_ref)) {
      stop("feature '", fname, "' logical kind '", feat$logical$kind,
           "' requires support_ref", call. = FALSE)
    }
    if (!is.null(support_ref)) {
      required_support_refs <- c(required_support_refs, support_ref)
    }
    for (enc in feat$encodings) {
      if (enc$type == "columns") {
        missing_cols <- setdiff(enc$binding$columns, declared_cols)
        if (length(missing_cols)) {
          stop("feature '", fname, "' references undeclared columns: ",
               paste(missing_cols, collapse = ", "), call. = FALSE)
        }
      }
      if (enc$type == "ref") {
        for (field in c("resource_id", "backend", "locator", "selector", "checksum")) {
          vs <- enc$binding[[field]]
          if (.is_column_ref(vs) && !vs$column %in% declared_cols) {
            stop("feature '", fname, "' references undeclared column '", vs$column,
                 "' in ", field, call. = FALSE)
          }
        }
      }
    }
  }
  required_support_refs <- unique(required_support_refs)
  if (length(required_support_refs) && is.null(supports)) {
    stop("manifest must define supports when any feature declares support_ref",
         call. = FALSE)
  }
  if (!is.null(supports)) {
    missing_supports <- setdiff(required_support_refs, names(supports))
    if (length(missing_supports)) {
      stop("features reference unknown supports: ",
           paste(missing_supports, collapse = ", "), call. = FALSE)
    }
  }

  obs_table <- list(path = observation_table_path, format = observation_table_format)

  resources <- NULL
  if (!is.null(resources_path)) {
    resources <- list(
      path = resources_path,
      format = resources_format %||% "csv"
    )
  }

  structure(
    list(
      spec_version = spec_version,
      dataset_id = dataset_id,
      storage_profile = storage_profile,
      observation_table = obs_table,
      row_id = row_id,
      observation_axes = observation_axes,
      observation_columns = observation_columns,
      features = features,
      supports = supports,
      primary_feature = primary_feature,
      import_recipe = import_recipe,
      resources = resources,
      extensions = extensions
    ),
    class = "nf_manifest"
  )
}

#' @export
print.nf_manifest <- function(x, ...) {
  cat("<nf_manifest>", x$dataset_id, "(NFTab", x$spec_version, ")\n")
  cat("  axes:", paste(x$observation_axes, collapse = ", "), "\n")
  cat("  columns:", length(x$observation_columns), "\n")
  cat("  features:", paste(names(x$features), collapse = ", "), "\n")
  if (!is.null(x$primary_feature)) cat("  primary_feature:", x$primary_feature, "\n")
  if (!is.null(x$supports)) cat("  supports:", length(x$supports), "\n")
  if (!is.null(x$resources)) cat("  resources:", x$resources$path, "\n")
  invisible(x)
}

# -- Dataset (nftab) -----------------------------------------------------------

#' Create an NFTab dataset object
#'
#' The primary user-facing object. Holds a manifest, the observation table,
#' and an optional resource registry.
#'
#' @param manifest An [nf_manifest] object.
#' @param observations A data.frame with one row per observation.
#' @param resources Optional data.frame with resource registry entries.
#' @param .root Directory root for resolving relative paths.
#'
#' @return An `nftab` object.
#' @export
nftab <- function(manifest, observations, resources = NULL, .root = NULL) {
  stopifnot(inherits(manifest, "nf_manifest"))
  stopifnot(is.data.frame(observations))

  rid_col <- manifest$row_id
  if (!rid_col %in% names(observations)) {
    stop("row_id column '", rid_col, "' not found in observations", call. = FALSE)
  }
  if (anyNA(observations[[rid_col]])) {
    stop("row_id column '", rid_col, "' contains NA values", call. = FALSE)
  }
  if (anyDuplicated(observations[[rid_col]])) {
    stop("row_id column '", rid_col, "' contains duplicate values", call. = FALSE)
  }

  declared_cols <- names(manifest$observation_columns)
  missing_declared <- setdiff(declared_cols, names(observations))
  if (length(missing_declared)) {
    stop("observation table missing declared columns: ",
         paste(missing_declared, collapse = ", "), call. = FALSE)
  }

  extra_cols <- setdiff(names(observations), declared_cols)
  if (length(extra_cols)) {
    stop("observation table has undeclared columns: ",
         paste(extra_cols, collapse = ", "), call. = FALSE)
  }

  for (ax in manifest$observation_axes) {
    if (!ax %in% names(observations)) {
      stop("observation axis '", ax, "' not found in observations", call. = FALSE)
    }
    if (anyNA(observations[[ax]])) {
      stop("observation axis '", ax, "' contains NA values", call. = FALSE)
    }
  }

  for (col_name in declared_cols) {
    schema <- manifest$observation_columns[[col_name]]
    if (!schema$nullable && anyNA(observations[[col_name]])) {
      stop("non-nullable column '", col_name, "' contains NA values", call. = FALSE)
    }
  }

  # Check axes tuple uniqueness
  if (length(manifest$observation_axes) > 0L) {
    ax_df <- observations[, manifest$observation_axes, drop = FALSE]
    if (anyDuplicated(ax_df)) {
      stop("observation_axes tuple is not unique", call. = FALSE)
    }
  }

  if (!is.null(resources)) {
    stopifnot(is.data.frame(resources))
    required_cols <- c("resource_id", "backend", "locator")
    missing <- setdiff(required_cols, names(resources))
    if (length(missing)) {
      stop("resource registry missing columns: ", paste(missing, collapse = ", "),
           call. = FALSE)
    }
    if (anyDuplicated(resources$resource_id)) {
      stop("resource_id values must be unique", call. = FALSE)
    }
  }

  structure(
    list(
      manifest = manifest,
      observations = observations,
      resources = resources,
      .root = .root
    ),
    class = "nftab"
  )
}

#' @export
print.nftab <- function(x, ...) {
  m <- x$manifest
  cat("<nftab>", m$dataset_id, "\n")
  cat("  ", nrow(x$observations), " observations x ",
      length(m$features), " features\n", sep = "")
  cat("  axes:", paste(m$observation_axes, collapse = ", "), "\n")
  cat("  features:", paste(names(m$features), collapse = ", "), "\n")

  # Show unique axis values
  for (ax in m$observation_axes) {
    vals <- unique(x$observations[[ax]])
    n <- length(vals)
    preview <- if (n <= 5) paste(vals, collapse = ", ") else
      paste0(paste(utils::head(vals, 3), collapse = ", "), ", ... (", n, " unique)")
    cat("  ", ax, ": ", preview, "\n", sep = "")
  }

  if (!is.null(x$resources)) {
    cat("  resources:", nrow(x$resources), "registered\n")
  }
  invisible(x)
}

#' Number of observations
#' @param x An nftab object.
#' @return Integer count.
#' @export
nf_nobs <- function(x) {
  stopifnot(inherits(x, "nftab"))
  nrow(x$observations)
}

#' Feature names
#' @param x An nftab object.
#' @return Character vector of feature names.
#' @export
nf_feature_names <- function(x) {
  stopifnot(inherits(x, "nftab"))
  names(x$manifest$features)
}

#' Observation axes
#' @param x An nftab object.
#' @return Character vector of axis column names.
#' @export
nf_axes <- function(x) {
  stopifnot(inherits(x, "nftab"))
  x$manifest$observation_axes
}

#' Manifest extension entries
#' @param x An nftab object.
#' @return A named list of manifest extensions, or `NULL`.
#' @export
nf_extensions <- function(x) {
  stopifnot(inherits(x, "nftab"))
  x$manifest$extensions
}

#' Manifest supports
#' @param x An nftab object.
#' @return A named list of support descriptors, or `NULL`.
#' @export
nf_supports <- function(x) {
  stopifnot(inherits(x, "nftab"))
  x$manifest$supports
}

#' Retrieve one manifest support
#' @param x An nftab object.
#' @param ref Manifest-local support reference.
#' @return An `nf_support_schema` object.
#' @export
nf_support_info <- function(x, ref) {
  stopifnot(inherits(x, "nftab"))
  supports <- x$manifest$supports
  if (is.null(supports) || is.null(supports[[ref]])) {
    stop("unknown support: ", ref, call. = FALSE)
  }
  supports[[ref]]
}

#' Retrieve one manifest extension
#' @param x An nftab object.
#' @param key Extension key, including the `x-` prefix.
#' @return The extension value.
#' @export
nf_extension <- function(x, key) {
  stopifnot(inherits(x, "nftab"))
  ext <- x$manifest$extensions
  if (is.null(ext) || is.null(ext[[key]])) {
    stop("unknown extension: ", key, call. = FALSE)
  }
  ext[[key]]
}

#' Logical schema for a feature
#' @param x An nftab object.
#' @param feature Feature name.
#' @return An `nf_logical_schema` object.
#' @export
nf_feature_schema <- function(x, feature) {
  stopifnot(inherits(x, "nftab"))
  feat <- x$manifest$features[[feature]]
  if (is.null(feat)) {
    stop("unknown feature: ", feature, call. = FALSE)
  }
  feat$logical
}

#' Axis metadata for a feature axis
#' @param x An nftab object.
#' @param feature Feature name.
#' @param axis Axis name from the feature's logical schema.
#' @return An `nf_axis_domain` object.
#' @export
nf_axis_info <- function(x, feature, axis) {
  stopifnot(inherits(x, "nftab"))
  schema <- nf_feature_schema(x, feature)
  if (!axis %in% schema$axes) {
    stop("feature '", feature, "' has no axis '", axis, "'", call. = FALSE)
  }

  domain <- schema$axis_domains[[axis]]
  if (is.null(domain)) {
    stop("feature '", feature, "' axis '", axis, "' has no axis metadata", call. = FALSE)
  }

  domain
}

#' Read axis labels for a feature axis
#' @param x An nftab object.
#' @param feature Feature name.
#' @param axis Axis name from the feature's logical schema.
#' @return A data.frame with at least `index` and `label`.
#' @export
nf_axis_labels <- function(x, feature, axis) {
  stopifnot(inherits(x, "nftab"))
  domain <- nf_axis_info(x, feature, axis)

  if (is.null(domain$labels) || !nzchar(domain$labels)) {
    stop("feature '", feature, "' axis '", axis, "' has no labels table", call. = FALSE)
  }
  if (is.null(x$.root)) {
    stop("dataset root is unknown; cannot resolve labels path", call. = FALSE)
  }

  labels_path <- .resolve_dataset_path(x$.root, domain$labels)
  if (!file.exists(labels_path)) {
    stop("axis labels file not found: ", domain$labels, call. = FALSE)
  }

  label_table <- .read_table(labels_path, "tsv")
  missing_cols <- setdiff(c("index", "label"), names(label_table))
  if (length(missing_cols)) {
    stop(
      "axis labels file is missing required columns: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  label_table[order(suppressWarnings(as.integer(label_table$index))), , drop = FALSE]
}

#' Design columns (observation table as data.frame)
#' @param x An nftab object.
#' @return A data.frame.
#' @export
nf_design <- function(x) {
  stopifnot(inherits(x, "nftab"))
  x$observations
}

#' Subset an nftab by row indices
#' @param x An nftab object.
#' @param i Row indices.
#' @param ... Ignored.
#' @export
`[.nftab` <- function(x, i, ...) {
  nftab(
    manifest = x$manifest,
    observations = x$observations[i, , drop = FALSE],
    resources = x$resources,
    .root = x$.root
  )
}
