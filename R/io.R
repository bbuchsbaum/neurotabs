# Read and write NFTab datasets (table-package profile)
# Corresponds to NFTab spec sections 12, 14.

#' Read an NFTab dataset from a manifest file
#'
#' @param path Path to `nftab.yaml` or `nftab.json`.
#' @param validate_schema Whether to validate the manifest against the bundled
#'   JSON Schema. Default `TRUE`.
#' @return An [nftab] object.
#' @export
nf_read <- function(path, validate_schema = TRUE) {
  stopifnot(file.exists(path))
  root <- dirname(normalizePath(path, mustWork = TRUE))
  ext <- tolower(tools::file_ext(path))

  raw <- if (ext %in% c("yaml", "yml")) {
    yaml::read_yaml(path)
  } else if (ext == "json") {
    jsonlite::fromJSON(path, simplifyVector = FALSE)
  } else {
    stop("manifest must be .yaml, .yml, or .json", call. = FALSE)
  }

  if (validate_schema) {
    .validate_manifest_schema(raw)
  }

  manifest <- .parse_manifest(raw)

  # Read observation table
  obs_path <- .resolve_dataset_path(root, manifest$observation_table$path)
  observations <- .read_table(obs_path, manifest$observation_table$format)
  observations <- .coerce_table_to_schema(
    observations,
    manifest$observation_columns,
    table_name = "observation table"
  )

  # Read resource registry if present
  resources <- NULL
  if (!is.null(manifest$resources)) {
    res_path <- .resolve_dataset_path(root, manifest$resources$path)
    resources <- .read_table(res_path, manifest$resources$format)
  }

  nftab(manifest = manifest, observations = observations,
        resources = resources, .root = root)
}

#' Write an NFTab dataset to disk (table-package profile)
#'
#' @param x An [nftab] object.
#' @param path Directory to write the dataset into. Created if it doesn't exist.
#' @param manifest_name Manifest filename. Default `"nftab.yaml"`.
#'
#' @return Invisibly, the path written to.
#' @export
nf_write <- function(x, path, manifest_name = "nftab.yaml") {
  stopifnot(inherits(x, "nftab"))
  dir.create(path, showWarnings = FALSE, recursive = TRUE)

  m <- x$manifest

  # Write observation table
  obs_path <- file.path(path, m$observation_table$path)
  .write_table(x$observations, obs_path, m$observation_table$format)

  # Write resource registry (compute checksums first, write once)
  if (!is.null(x$resources) && !is.null(m$resources)) {
    res_path <- file.path(path, m$resources$path)
    resources <- x$resources
    src_root <- if (!is.null(x$.root)) x$.root else path
    checksums <- vapply(as.character(resources$locator), function(loc) {
      abs_path <- .resolve_dataset_path(src_root, loc)
      if (!is.null(abs_path) && file.exists(abs_path)) {
        paste0("sha256:", digest::digest(file = abs_path, algo = "sha256",
                                         serialize = FALSE))
      } else {
        NA_character_
      }
    }, character(1L))
    resources$checksum <- checksums
    .write_table(resources, res_path, m$resources$format)
  }

  # Write manifest
  manifest_raw <- .manifest_to_list(m)
  manifest_path <- file.path(path, manifest_name)
  ext <- tolower(tools::file_ext(manifest_name))
  if (ext %in% c("yaml", "yml")) {
    yaml::write_yaml(manifest_raw, manifest_path)
  } else if (ext == "json") {
    writeLines(jsonlite::toJSON(manifest_raw, auto_unbox = TRUE, pretty = TRUE),
               manifest_path)
  } else {
    stop("manifest_name must end in .yaml, .yml, or .json", call. = FALSE)
  }

  invisible(path)
}

# -- Internal: table I/O ------------------------------------------------------

.read_table <- function(path, format) {
  switch(format,
    csv = data.table::fread(path, data.table = FALSE),
    tsv = data.table::fread(path, sep = "\t", data.table = FALSE),
    # nocov start
    parquet = {
      if (!requireNamespace("arrow", quietly = TRUE)) {
        stop("arrow package required to read parquet", call. = FALSE)
      }
      as.data.frame(arrow::read_parquet(path))
    # nocov end
    },
    stop("unsupported table format: ", format, call. = FALSE)
  )
}

.validate_manifest_schema <- function(raw) {
  if (!requireNamespace("jsonvalidate", quietly = TRUE)) {
    stop("jsonvalidate package required for manifest schema validation", call. = FALSE)
  }

  schema_path <- system.file("schema", "nftab-manifest.schema.json", package = "neurotabs")
  if (!nzchar(schema_path) || !file.exists(schema_path)) {
    stop("bundled NFTab manifest schema not found", call. = FALSE)
  }

  manifest_json <- jsonlite::toJSON(
    .prepare_manifest_for_schema_json(raw),
    auto_unbox = TRUE,
    null = "null"
  )
  valid <- jsonvalidate::json_validate(
    manifest_json,
    schema = schema_path,
    engine = "ajv",
    verbose = TRUE
  )

  if (isTRUE(valid)) {
    return(invisible(TRUE))
  }

  errors <- if (is.list(valid) && !is.null(valid$errors)) {
    vapply(valid$errors, function(err) {
      instance <- err$instancePath %||% ""
      message <- err$message %||% "schema validation error"
      paste0(if (nzchar(instance)) instance else "$", ": ", message)
    }, character(1))
  } else {
    "manifest failed schema validation"
  }

  stop(
    "manifest does not conform to nftab-manifest.schema.json:\n  ",
    paste(errors, collapse = "\n  "),
    call. = FALSE
  )
}

.prepare_manifest_for_schema_json <- function(x, path = character()) {
  if (is.list(x)) {
    if (is.null(names(x))) {
      return(lapply(x, .prepare_manifest_for_schema_json, path = path))
    }

    out <- lapply(names(x), function(nm) {
      .prepare_manifest_for_schema_json(x[[nm]], c(path, nm))
    })
    names(out) <- names(x)
    return(out)
  }

  if (.schema_array_path(path)) {
    return(I(x))
  }

  x
}

.schema_array_path <- function(path) {
  identical(path, "observation_axes") ||
    .path_ends_with(path, c("import_recipe", "group_columns")) ||
    .path_ends_with(path, c("logical", "axes")) ||
    .path_ends_with(path, c("logical", "shape")) ||
    .path_ends_with(path, c("binding", "columns")) ||
    .path_ends_with(path, "levels")
}

.path_ends_with <- function(path, suffix) {
  n <- length(suffix)
  if (length(path) < n) return(FALSE)
  identical(tail(path, n), suffix)
}

.resolve_dataset_path <- function(root, path) {
  if (grepl("^(/|[a-zA-Z]:|[a-zA-Z][a-zA-Z0-9+.-]*://)", path)) {
    return(path)
  }
  file.path(root, path)
}

.coerce_table_to_schema <- function(df, schema_map, table_name = "table") {
  for (col_name in names(schema_map)) {
    if (!col_name %in% names(df)) next
    df[[col_name]] <- .coerce_column_dtype(
      df[[col_name]],
      dtype = schema_map[[col_name]]$dtype,
      nullable = schema_map[[col_name]]$nullable,
      col_name = col_name,
      table_name = table_name
    )
  }

  df
}

.coerce_column_dtype <- function(values, dtype, nullable, col_name, table_name) {
  values <- .normalize_empty_fields(values)
  original_missing <- is.na(values)

  coerced <- switch(
    dtype,
    string = as.character(values),
    float32 = .coerce_numeric_column(values, dtype, col_name, table_name),
    float64 = .coerce_numeric_column(values, dtype, col_name, table_name),
    int32 = .coerce_integerish_column(values, dtype, col_name, table_name,
                                      min_value = -2147483648, max_value = 2147483647,
                                      as_integer = TRUE),
    int64 = .coerce_integerish_column(values, dtype, col_name, table_name,
                                      as_integer = FALSE),
    uint8 = .coerce_integerish_column(values, dtype, col_name, table_name,
                                      min_value = 0, max_value = 255,
                                      as_integer = TRUE),
    uint16 = .coerce_integerish_column(values, dtype, col_name, table_name,
                                       min_value = 0, max_value = 65535,
                                       as_integer = TRUE),
    bool = .coerce_bool_column(values, col_name, table_name),
    date = .coerce_date_column(values, col_name, table_name),
    datetime = .coerce_datetime_column(values, col_name, table_name),
    json = .coerce_json_column(values, col_name, table_name),
    stop("unsupported declared dtype: ", dtype, call. = FALSE)
  )

  if (!nullable && any(is.na(coerced))) {
    stop(table_name, " column '", col_name, "' is non-nullable but contains missing values",
         call. = FALSE)
  }

  if (any(!original_missing & is.na(coerced))) {
    stop(table_name, " column '", col_name, "' could not be coerced to ", dtype,
         call. = FALSE)
  }

  coerced
}

.normalize_empty_fields <- function(values) {
  if (is.factor(values)) {
    values <- as.character(values)
  }

  if (is.character(values)) {
    values[trimws(values) == ""] <- NA_character_
  }

  values
}

.coerce_numeric_column <- function(values, dtype, col_name, table_name) {
  if (is.numeric(values)) {
    return(as.numeric(values))
  }

  coerced <- suppressWarnings(as.numeric(as.character(values)))
  bad <- !is.na(values) & is.na(coerced)
  if (any(bad)) {
    stop(table_name, " column '", col_name, "' contains non-numeric values for ", dtype,
         call. = FALSE)
  }
  coerced
}

.coerce_integerish_column <- function(values, dtype, col_name, table_name,
                                      min_value = NULL, max_value = NULL,
                                      as_integer = TRUE) {
  numeric_values <- .coerce_numeric_column(values, dtype, col_name, table_name)
  finite <- !is.na(numeric_values)
  if (any(abs(numeric_values[finite] - round(numeric_values[finite])) > 0)) {
    stop(table_name, " column '", col_name, "' must contain whole values for ", dtype,
         call. = FALSE)
  }
  if (!is.null(min_value) && any(numeric_values[finite] < min_value)) {
    stop(table_name, " column '", col_name, "' violates minimum for ", dtype, call. = FALSE)
  }
  if (!is.null(max_value) && any(numeric_values[finite] > max_value)) {
    stop(table_name, " column '", col_name, "' violates maximum for ", dtype, call. = FALSE)
  }

  if (as_integer) as.integer(numeric_values) else numeric_values
}

.coerce_bool_column <- function(values, col_name, table_name) {
  if (is.logical(values)) {
    return(values)
  }

  if (is.numeric(values)) {
    bad <- !is.na(values) & !values %in% c(0, 1)
    if (any(bad)) {
      stop(table_name, " column '", col_name, "' must contain 0/1 for bool dtype",
           call. = FALSE)
    }
    return(as.logical(values))
  }

  normalized <- tolower(trimws(as.character(values)))
  out <- rep(NA, length(normalized))
  true_vals <- c("true", "t", "1")
  false_vals <- c("false", "f", "0")
  out[normalized %in% true_vals] <- TRUE
  out[normalized %in% false_vals] <- FALSE
  bad <- !is.na(values) & !(normalized %in% c(true_vals, false_vals))
  if (any(bad)) {
    stop(table_name, " column '", col_name, "' contains invalid bool values",
         call. = FALSE)
  }
  out
}

.coerce_date_column <- function(values, col_name, table_name) {
  if (inherits(values, "Date")) {
    return(values)
  }

  coerced <- suppressWarnings(as.Date(as.character(values)))
  bad <- !is.na(values) & is.na(coerced)
  if (any(bad)) {
    stop(table_name, " column '", col_name, "' contains invalid date values",
         call. = FALSE)
  }
  coerced
}

.coerce_datetime_column <- function(values, col_name, table_name) {
  if (inherits(values, "POSIXt")) {
    return(as.POSIXct(values, tz = "UTC"))
  }

  coerced <- suppressWarnings(as.POSIXct(as.character(values), tz = "UTC"))
  bad <- !is.na(values) & is.na(coerced)
  if (any(bad)) {
    stop(table_name, " column '", col_name, "' contains invalid datetime values",
         call. = FALSE)
  }
  coerced
}

.coerce_json_column <- function(values, col_name, table_name) {
  chars <- as.character(values)
  chars[is.na(values)] <- NA_character_
  non_missing <- !is.na(chars)
  valid_json <- rep(TRUE, length(chars))
  valid_json[non_missing] <- vapply(chars[non_missing], jsonlite::validate, logical(1))
  repaired <- !valid_json & non_missing
  if (any(repaired)) {
    chars[repaired] <- gsub('""', '"', chars[repaired], fixed = TRUE)
    valid_json[repaired] <- vapply(chars[repaired], jsonlite::validate, logical(1))
  }
  if (any(!valid_json)) {
    stop(table_name, " column '", col_name, "' contains invalid JSON text",
         call. = FALSE)
  }
  chars
}

.write_table <- function(df, path, format) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  switch(format,
    csv = data.table::fwrite(df, path),
    tsv = data.table::fwrite(df, path, sep = "\t"),
    # nocov start
    parquet = {
      if (!requireNamespace("arrow", quietly = TRUE)) {
        stop("arrow package required to write parquet", call. = FALSE)
      }
      arrow::write_parquet(df, path)
    # nocov end
    },
    stop("unsupported table format: ", format, call. = FALSE)
  )
}

# -- Internal: manifest parsing ------------------------------------------------

.parse_manifest <- function(raw) {
  # Parse observation_columns
  obs_cols <- lapply(raw$observation_columns, function(col) {
    nf_col_schema(
      dtype = col$dtype,
      nullable = col$nullable %||% TRUE,
      semantic_role = col$semantic_role,
      levels = col$levels,
      unit = col$unit,
      description = col$description
    )
  })

  # Parse features
  features <- lapply(raw$features, function(f) {
    logical <- .parse_logical_schema(f$logical)
    encodings <- lapply(f$encodings, .parse_encoding)
    nf_feature(
      logical = logical,
      encodings = encodings,
      nullable = f$nullable %||% FALSE,
      description = f$description
    )
  })

  supports <- .parse_supports(raw$supports)

  resources_path <- raw$resources$path
  resources_format <- raw$resources$format

  nf_manifest(
    spec_version = raw$spec_version,
    dataset_id = raw$dataset_id,
    row_id = raw$row_id,
    observation_axes = as.character(raw$observation_axes),
    observation_columns = obs_cols,
    features = features,
    storage_profile = raw$storage_profile %||% "table-package",
    observation_table_path = raw$observation_table$path,
    observation_table_format = raw$observation_table$format,
    resources_path = resources_path,
    resources_format = resources_format,
    supports = supports,
    primary_feature = raw$primary_feature,
    import_recipe = raw$import_recipe,
    extensions = raw$extensions
  )
}

.parse_logical_schema <- function(raw) {
  nf_logical_schema(
    kind = raw$kind,
    axes = as.character(raw$axes),
    dtype = raw$dtype,
    support_ref = raw$support_ref,
    shape = if (!is.null(raw$shape)) as.integer(raw$shape) else NULL,
    axis_domains = .parse_axis_domains(raw$axis_domains),
    space = raw$space,
    alignment = raw$alignment,
    unit = raw$unit,
    description = raw$description
  )
}

.parse_axis_domains <- function(raw) {
  if (is.null(raw)) return(NULL)
  lapply(raw, function(ad) {
    nf_axis_domain(
      id = ad$id,
      labels = ad$labels,
      size = ad$size,
      description = ad$description
    )
  })
}

.parse_supports <- function(raw) {
  if (is.null(raw)) return(NULL)
  lapply(raw, .parse_support)
}

.parse_support <- function(raw) {
  nf_support(
    support_type = raw$support_type,
    support_id = raw$support_id,
    description = raw$description,
    metadata = raw$metadata,
    space = raw$space,
    grid_id = raw$grid_id,
    affine_id = raw$affine_id,
    template = raw$template,
    mesh_id = raw$mesh_id,
    topology_id = raw$topology_id,
    hemisphere = raw$hemisphere,
    n_parcels = raw$n_parcels,
    parcel_map = raw$parcel_map,
    membership_ref = raw$membership_ref
  )
}

.parse_encoding <- function(raw) {
  if (raw$type == "ref") {
    nf_ref_encoding(
      backend = .parse_value_source(raw$binding$backend),
      locator = .parse_value_source(raw$binding$locator),
      selector = .parse_value_source(raw$binding$selector),
      resource_id = .parse_value_source(raw$binding$resource_id),
      checksum = .parse_value_source(raw$binding$checksum)
    )
  } else if (raw$type == "columns") {
    nf_columns_encoding(columns = as.character(raw$binding$columns))
  } else {
    stop("unsupported encoding type: ", raw$type, call. = FALSE)
  }
}

.parse_value_source <- function(raw) {
  if (is.null(raw)) return(NULL)
  if (is.list(raw) && !is.null(raw$column)) {
    nf_col(raw$column)
  } else {
    raw
  }
}

# -- Internal: manifest serialization -----------------------------------------

.manifest_to_list <- function(m) {
  obs_cols <- lapply(m$observation_columns, function(cs) {
    out <- list(dtype = cs$dtype)
    if (!cs$nullable) out$nullable <- FALSE
    if (!is.null(cs$semantic_role)) out$semantic_role <- cs$semantic_role
    if (!is.null(cs$levels)) out$levels <- cs$levels
    if (!is.null(cs$unit)) out$unit <- cs$unit
    if (!is.null(cs$description)) out$description <- cs$description
    out
  })

  features <- lapply(m$features, function(f) {
    logical <- .logical_schema_to_list(f$logical)
    encodings <- lapply(f$encodings, .encoding_to_list)
    out <- list(logical = logical, encodings = encodings)
    if (f$nullable) out$nullable <- TRUE
    if (!is.null(f$description)) out$description <- f$description
    out
  })

  out <- list(
    spec_version = m$spec_version,
    dataset_id = m$dataset_id,
    storage_profile = m$storage_profile,
    observation_table = m$observation_table,
    row_id = m$row_id,
    observation_axes = m$observation_axes,
    observation_columns = obs_cols,
    features = features
  )
  if (!is.null(m$supports)) {
    out$supports <- lapply(m$supports, .support_to_list)
  }
  if (!is.null(m$primary_feature)) out$primary_feature <- m$primary_feature
  if (!is.null(m$import_recipe)) out$import_recipe <- m$import_recipe
  if (!is.null(m$resources)) out$resources <- m$resources
  if (!is.null(m$extensions)) out$extensions <- m$extensions
  out
}

.logical_schema_to_list <- function(ls) {
  out <- list(kind = ls$kind, axes = ls$axes, dtype = ls$dtype)
  if (!is.null(ls$support_ref)) out$support_ref <- ls$support_ref
  if (!is.null(ls$shape)) out$shape <- ls$shape
  if (!is.null(ls$axis_domains)) {
    out$axis_domains <- lapply(ls$axis_domains, function(ad) {
      o <- list()
      if (!is.null(ad$id)) o$id <- ad$id
      if (!is.null(ad$labels)) o$labels <- ad$labels
      if (!is.null(ad$size)) o$size <- ad$size
      if (!is.null(ad$description)) o$description <- ad$description
      o
    })
  }
  if (!is.null(ls$space)) out$space <- ls$space
  if (!is.null(ls$alignment)) out$alignment <- ls$alignment
  if (!is.null(ls$unit)) out$unit <- ls$unit
  if (!is.null(ls$description)) out$description <- ls$description
  out
}

.support_to_list <- function(support) {
  out <- list(
    support_type = support$support_type,
    support_id = support$support_id
  )
  for (nm in c("space", "grid_id", "affine_id", "template", "mesh_id",
               "topology_id", "hemisphere", "n_parcels", "parcel_map",
               "membership_ref", "description", "metadata")) {
    if (!is.null(support[[nm]])) {
      out[[nm]] <- support[[nm]]
    }
  }
  out
}

.encoding_to_list <- function(enc) {
  if (enc$type == "ref") {
    binding <- list()
    for (nm in c("resource_id", "backend", "locator", "selector", "checksum")) {
      val <- enc$binding[[nm]]
      if (!is.null(val)) {
        binding[[nm]] <- .value_source_to_list(val)
      }
    }
    list(type = "ref", binding = binding)
  } else if (enc$type == "columns") {
    list(type = "columns", binding = list(columns = enc$binding$columns))
  }
}

.value_source_to_list <- function(vs) {
  if (inherits(vs, "nf_column_ref")) {
    list(column = vs$column)
  } else {
    vs
  }
}
