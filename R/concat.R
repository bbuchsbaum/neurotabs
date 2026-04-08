# Dataset concatenation
# Corresponds to NFTab spec section 13.

#' Check strict concatenation compatibility
#'
#' @param a An [nftab] object.
#' @param b An [nftab] object.
#'
#' @return A list with `compatible` (logical) and `reasons` (character vector
#'   of incompatibilities). Returned invisibly.
#' @export
nf_compatible <- function(a, b) {
  stopifnot(inherits(a, "nftab"), inherits(b, "nftab"))
  reasons <- character()

  ma <- a$manifest
  mb <- b$manifest

  # 1. Major spec_version
  va <- strsplit(ma$spec_version, "\\.")[[1L]][1L]
  vb <- strsplit(mb$spec_version, "\\.")[[1L]][1L]
  if (va != vb) {
    reasons <- c(reasons, sprintf("major spec_version mismatch: %s vs %s", va, vb))
  }

  # 2. observation_axes identical
  if (!identical(ma$observation_axes, mb$observation_axes)) {
    reasons <- c(reasons, sprintf(
      "observation_axes differ: [%s] vs [%s]",
      paste(ma$observation_axes, collapse = ","),
      paste(mb$observation_axes, collapse = ",")))
  }

  # 3. Same feature name sets
  fa <- sort(names(ma$features))
  fb <- sort(names(mb$features))
  if (!identical(fa, fb)) {
    reasons <- c(reasons, sprintf(
      "feature name sets differ: {%s} vs {%s}",
      paste(fa, collapse = ","), paste(fb, collapse = ",")))
  }

  # 4. Logical schema compatibility for shared features
  shared_features <- intersect(names(ma$features), names(mb$features))
  for (fname in shared_features) {
    fp_a <- .feature_schema_fingerprint(ma, fname)
    fp_b <- .feature_schema_fingerprint(mb, fname)
    if (fp_a != fp_b) {
      reasons <- c(reasons, paste0("feature '", fname, "': logical schema mismatch"))
    }
  }

  # 5. Shared column compatibility
  shared_cols <- intersect(names(ma$observation_columns), names(mb$observation_columns))
  for (col in shared_cols) {
    ca <- ma$observation_columns[[col]]
    cb <- mb$observation_columns[[col]]
    if (!.compatible_scalar_dtype(ca$dtype, cb$dtype)) {
      reasons <- c(reasons, sprintf(
        "column '%s': incompatible dtypes %s vs %s", col, ca$dtype, cb$dtype))
    }
  }

  result <- list(compatible = length(reasons) == 0L, reasons = reasons)
  invisible(result)
}

#' Concatenate NFTab datasets (strict row-wise)
#'
#' @param ... [nftab] objects to concatenate.
#' @param provenance_col Name of provenance column to add. Default
#'   `"source_dataset"`. Set to `NULL` to skip.
#'
#' @return A new [nftab] object with rows from all inputs.
#' @export
nf_concat <- function(..., provenance_col = "source_dataset") {
  datasets <- list(...)
  if (length(datasets) < 2L) {
    stop("nf_concat requires at least 2 datasets", call. = FALSE)
  }

  # Check pairwise compatibility
  for (i in 2:length(datasets)) {
    compat <- nf_compatible(datasets[[1L]], datasets[[i]])
    if (!compat$compatible) {
      stop("datasets 1 and ", i, " are not compatible:\n  ",
           paste(compat$reasons, collapse = "\n  "), call. = FALSE)
    }
  }

  prepared <- vector("list", length(datasets))
  merged_resources_so_far <- NULL
  for (i in seq_along(datasets)) {
    prepared[[i]] <- .prepare_dataset_for_concat(datasets[[i]], merged_resources_so_far)
    if (!is.null(prepared[[i]]$resources) && nrow(prepared[[i]]$resources) > 0L) {
      merged_resources_so_far <- if (is.null(merged_resources_so_far)) {
        prepared[[i]]$resources
      } else {
        as.data.frame(data.table::rbindlist(
          list(merged_resources_so_far, prepared[[i]]$resources),
          use.names = TRUE,
          fill = TRUE
        ))
      }
    }
  }

  manifests <- lapply(prepared, function(d) d$manifest)
  base_manifest <- manifests[[1L]]

  # Merge observation tables
  all_obs <- lapply(seq_along(prepared), function(i) {
    obs <- prepared[[i]]$observations
    if (!is.null(provenance_col)) {
      obs[[provenance_col]] <- prepared[[i]]$manifest$dataset_id
    }
    obs
  })
  merged_obs <- as.data.frame(data.table::rbindlist(all_obs, use.names = TRUE, fill = TRUE))

  # Ensure unique row_ids
  rid <- base_manifest$row_id
  if (anyDuplicated(merged_obs[[rid]])) {
    merged_obs[[rid]] <- make.unique(as.character(merged_obs[[rid]]), sep = ":")
  }

  # Merge resource registries
  all_resources <- lapply(prepared, function(d) d$resources)
  all_resources <- all_resources[!vapply(all_resources, is.null, logical(1))]

  merged_resources <- NULL
  if (length(all_resources)) {
    merged_resources <- as.data.frame(data.table::rbindlist(
      all_resources,
      use.names = TRUE,
      fill = TRUE
    ))
  }

  merged_cols <- .merge_observation_columns(manifests, provenance_col = provenance_col)
  merged_features <- .merge_features(manifests)
  resource_manifest <- Filter(function(m) !is.null(m$resources), manifests)

  new_manifest <- nf_manifest(
    spec_version = base_manifest$spec_version,
    dataset_id = paste0(base_manifest$dataset_id, "-concat"),
    row_id = rid,
    observation_axes = base_manifest$observation_axes,
    observation_columns = merged_cols,
    features = merged_features,
    storage_profile = base_manifest$storage_profile,
    observation_table_path = base_manifest$observation_table$path,
    observation_table_format = base_manifest$observation_table$format,
    resources_path = if (!is.null(merged_resources) && length(resource_manifest)) {
      resource_manifest[[1L]]$resources$path
    } else {
      NULL
    },
    resources_format = if (!is.null(merged_resources) && length(resource_manifest)) {
      resource_manifest[[1L]]$resources$format
    } else {
      NULL
    },
    supports = base_manifest$supports,
    primary_feature = base_manifest$primary_feature
  )

  nftab(
    manifest = new_manifest,
    observations = merged_obs,
    resources = merged_resources,
    .root = NULL
  )
}

# -- Internal ------------------------------------------------------------------

.numeric_dtypes <- c("int32", "int64", "float32", "float64")

.compatible_scalar_dtype <- function(a, b) {
  if (a == b) return(TRUE)
  if (a %in% .numeric_dtypes && b %in% .numeric_dtypes) return(TRUE)
  FALSE
}

.feature_schema_fingerprint <- function(manifest, feature_name) {
  feature <- manifest$features[[feature_name]]
  support_id <- .feature_support_id(manifest, feature$logical)
  nf_schema_fingerprint(feature$logical, support_id = support_id)
}

.feature_support_id <- function(manifest, logical_schema) {
  support_ref <- logical_schema$support_ref
  if (is.null(support_ref) || is.null(manifest$supports)) {
    return(NULL)
  }
  support <- manifest$supports[[support_ref]]
  if (is.null(support)) {
    return(NULL)
  }
  support$support_id
}

.merge_observation_columns <- function(manifests, provenance_col = NULL) {
  col_order <- unique(unlist(lapply(manifests, function(m) names(m$observation_columns))))
  merged <- vector("list", length(col_order))
  names(merged) <- col_order

  for (col in col_order) {
    present <- Filter(Negate(is.null), lapply(manifests, function(m) m$observation_columns[[col]]))
    merged_schema <- Reduce(.merge_col_schema, present)
    if (length(present) < length(manifests)) {
      merged_schema$nullable <- TRUE
    }
    merged[[col]] <- merged_schema
  }

  if (!is.null(provenance_col) && !provenance_col %in% names(merged)) {
    merged[[provenance_col]] <- nf_col_schema("string", nullable = FALSE)
  }

  merged
}

.merge_col_schema <- function(a, b) {
  dtype <- .promote_scalar_dtype(a$dtype, b$dtype)
  if (is.null(dtype)) {
    stop("cannot merge incompatible scalar dtypes: ", a$dtype, " vs ", b$dtype,
         call. = FALSE)
  }

  semantic_role <- if (identical(a$semantic_role, b$semantic_role)) {
    a$semantic_role
  } else {
    a$semantic_role %||% b$semantic_role
  }

  levels <- if (identical(a$levels, b$levels)) a$levels else NULL
  unit <- if (identical(a$unit, b$unit)) a$unit else a$unit %||% b$unit
  description <- a$description %||% b$description

  nf_col_schema(
    dtype = dtype,
    nullable = isTRUE(a$nullable) || isTRUE(b$nullable),
    semantic_role = semantic_role,
    levels = levels,
    unit = unit,
    description = description
  )
}

.promote_scalar_dtype <- function(a, b) {
  if (a == b) return(a)
  if (!a %in% .numeric_dtypes || !b %in% .numeric_dtypes) return(NULL)
  order <- c("int32", "int64", "float32", "float64")
  order[max(match(a, order), match(b, order))]
}

.merge_features <- function(manifests) {
  feature_names <- names(manifests[[1L]]$features)
  merged <- vector("list", length(feature_names))
  names(merged) <- feature_names

  for (fname in feature_names) {
    logical <- manifests[[1L]]$features[[fname]]$logical
    description <- manifests[[1L]]$features[[fname]]$description
    nullable <- FALSE
    encodings <- list()
    seen <- character()

    for (m in manifests) {
      feat <- m$features[[fname]]
      nullable <- nullable || isTRUE(feat$nullable)
      description <- description %||% feat$description

      for (enc in feat$encodings) {
        key <- digest::digest(.encoding_to_list(enc), algo = "xxhash64")
        if (!key %in% seen) {
          encodings[[length(encodings) + 1L]] <- enc
          seen <- c(seen, key)
        }
      }
    }

    merged[[fname]] <- nf_feature(
      logical = logical,
      encodings = encodings,
      nullable = nullable,
      description = description
    )
  }

  merged
}

.prepare_dataset_for_concat <- function(ds, existing_resources = NULL) {
  manifest <- ds$manifest
  observations <- ds$observations
  resources <- ds$resources

  if (is.null(resources) || nrow(resources) == 0L) {
    return(list(
      manifest = manifest,
      observations = observations,
      resources = resources,
      .root = ds$.root
    ))
  }

  resources <- .absolutize_resource_locators(resources, ds$.root)
  keep <- rep(TRUE, nrow(resources))
  mapping <- character()
  seen_ids <- if (is.null(existing_resources)) character() else as.character(existing_resources$resource_id)

  for (i in seq_len(nrow(resources))) {
    rid <- as.character(resources$resource_id[i])
    existing <- if (is.null(existing_resources)) {
      resources[FALSE, , drop = FALSE]
    } else {
      existing_resources[as.character(existing_resources$resource_id) == rid, , drop = FALSE]
    }

    if (nrow(existing) == 0L) {
      seen_ids <- c(seen_ids, rid)
      next
    }

    identical_existing <- any(vapply(seq_len(nrow(existing)), function(j) {
      .resource_rows_identical(existing[j, , drop = FALSE], resources[i, , drop = FALSE])
    }, logical(1)))

    if (identical_existing) {
      keep[i] <- FALSE
      next
    }

    new_rid <- .next_resource_id(rid, c(seen_ids, unname(mapping)))
    mapping[[rid]] <- new_rid
    resources$resource_id[i] <- new_rid
    seen_ids <- c(seen_ids, new_rid)
  }

  resources <- resources[keep, , drop = FALSE]

  if (length(mapping)) {
    observations <- .rewrite_observation_resource_refs(observations, manifest$features, mapping)
    manifest <- .rewrite_manifest_resource_refs(manifest, mapping)
  }

  list(
    manifest = manifest,
    observations = observations,
    resources = resources,
    .root = ds$.root
  )
}

.absolutize_resource_locators <- function(resources, root) {
  if (is.null(root) || !"locator" %in% names(resources)) {
    return(resources)
  }

  locators <- as.character(resources$locator)
  relative <- !is.na(locators) & !grepl("^(/|[a-zA-Z]:|[a-zA-Z][a-zA-Z0-9+.-]*://)", locators)
  resources$locator[relative] <- file.path(root, locators[relative])
  resources
}

.resource_rows_identical <- function(a, b) {
  cols <- union(names(a), names(b))
  lhs <- lapply(cols, function(col) if (col %in% names(a)) a[[col]][[1L]] else NA)
  rhs <- lapply(cols, function(col) if (col %in% names(b)) b[[col]][[1L]] else NA)
  identical(lhs, rhs)
}

.next_resource_id <- function(base_id, used_ids) {
  candidate <- base_id
  i <- 1L
  while (candidate %in% used_ids) {
    candidate <- paste0(base_id, ":", i)
    i <- i + 1L
  }
  candidate
}

.rewrite_observation_resource_refs <- function(observations, features, mapping) {
  ref_cols <- unique(unlist(lapply(features, function(feat) {
    cols <- character()
    for (enc in feat$encodings) {
      if (enc$type == "ref" && .is_column_ref(enc$binding$resource_id)) {
        cols <- c(cols, enc$binding$resource_id$column)
      }
    }
    cols
  })))

  for (col in ref_cols) {
    if (!col %in% names(observations)) next
    values <- as.character(observations[[col]])
    idx <- !is.na(values) & values %in% names(mapping)
    observations[[col]][idx] <- unname(mapping[values[idx]])
  }

  observations
}

.rewrite_manifest_resource_refs <- function(manifest, mapping) {
  manifest$features <- lapply(manifest$features, function(feat) {
    feat$encodings <- lapply(feat$encodings, function(enc) {
      if (enc$type == "ref" &&
          !is.null(enc$binding$resource_id) &&
          !.is_column_ref(enc$binding$resource_id)) {
        rid <- as.character(enc$binding$resource_id)
        if (rid %in% names(mapping)) {
          enc$binding$resource_id <- unname(mapping[[rid]])
        }
      }
      enc
    })
    feat
  })
  manifest
}
