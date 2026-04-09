# dplyr-style grammar verbs for nftab objects
# Phase 1: nf_filter, nf_select, nf_arrange, nf_collect
# Phase 2: nf_group_by, nf_summarize, nf_compare, nf_mutate, nf_drill

# Internal helper: capture column names from NSE `...` or a character vector.
# `expr` should be `substitute(list(...))`.
.nf_capture_names <- function(expr) {
  args <- as.list(expr)[-1L]
  vapply(args, function(e) {
    if (is.character(e)) e
    else if (is.symbol(e)) as.character(e)
    else stop("expected column name or string, got: ", deparse(e), call. = FALSE)
  }, character(1L))
}

#' Group observations by design columns
#'
#' @param x An [nftab] object.
#' @param ... Grouping columns (unquoted or character).
#' @param .by Optional character vector of column names; use instead of `...`
#'   for programmatic grouping.
#'
#' @return A `grouped_nftab` object.
#' @export
nf_group_by <- function(x, ..., .by = NULL) {
  stopifnot(inherits(x, "nftab"))
  if (!is.null(.by)) {
    by <- .by
  } else {
    by <- .nf_capture_names(substitute(list(...)))
  }
  if (!length(by)) {
    stop("nf_group_by requires at least one grouping column", call. = FALSE)
  }
  if (!all(by %in% names(x$observations))) {
    missing <- setdiff(by, names(x$observations))
    stop("unknown grouping columns: ", paste(missing, collapse = ", "), call. = FALSE)
  }

  structure(
    list(
      data = x,
      by = unique(by)
    ),
    class = "grouped_nftab"
  )
}

#' Drop grouping metadata
#'
#' @param x A `grouped_nftab` object.
#' @return The underlying [nftab] object.
#' @export
nf_ungroup <- function(x) {
  if (inherits(x, "grouped_nftab")) {
    return(x$data)
  }
  stop("nf_ungroup() requires a grouped_nftab object", call. = FALSE)
}

#' Drill from a summary nftab back to contributing member rows
#'
#' Returns the original observations that contributed to one or more summary
#' rows. The summary must have been produced by [nf_summarize], which stores
#' contributing row IDs in a `.members` list-column as JSON arrays.
#'
#' @param summary A summarized [nftab] with a `.members` observation column.
#' @param source The original [nftab] that was summarized.
#' @param row_index Integer row position(s) or character row_id value(s) into
#'   `summary`. If `NULL` (default), all summary rows are drilled.
#'
#' @return An [nftab] containing the contributing rows from `source`.
#' @export
nf_drill <- function(summary, source, row_index = NULL) {
  stopifnot(inherits(summary, "nftab"), inherits(source, "nftab"))
  if (!".members" %in% names(summary$observations)) {
    stop(
      "summary nftab has no .members column; ",
      "was it produced by nf_summarize()?",
      call. = FALSE
    )
  }
  rows <- if (is.null(row_index)) {
    seq_len(nrow(summary$observations))
  } else if (is.character(row_index)) {
    rid_col <- summary$manifest$row_id
    match(row_index, summary$observations[[rid_col]])
  } else {
    row_index
  }
  member_id_lists <- lapply(summary$observations$.members[rows], function(m) {
    if (is.null(m) || is.na(m) || !nzchar(m)) character(0L)
    else jsonlite::fromJSON(m)
  })
  member_ids <- unique(unlist(member_id_lists))
  rid_col <- source$manifest$row_id
  keep <- source$observations[[rid_col]] %in% member_ids
  source[which(keep)]
}

#' @export
print.grouped_nftab <- function(x, ...) {
  group_count <- nrow(unique(x$data$observations[, x$by, drop = FALSE]))
  cat("<grouped_nftab>\n")
  cat("  groups:", paste(x$by, collapse = ", "), "\n")
  cat("  n_groups:", group_count, "\n")
  cat("  n_rows:", nrow(x$data$observations), "\n")
  invisible(x)
}

#' Filter observations by design predicates
#'
#' @param x An [nftab] object.
#' @param ... Filter expressions evaluated in the context of the observation
#'   table. Observation column names take precedence over variables in the
#'   calling environment. Multiple expressions are combined with AND.
#'
#' @return A filtered [nftab] object.
#' @export
nf_filter <- function(x, ...) {
  grouped <- inherits(x, "grouped_nftab")
  ds <- if (grouped) x$data else x
  stopifnot(inherits(ds, "nftab"))
  keep <- rep(TRUE, nrow(ds$observations))
  exprs <- as.list(substitute(list(...)))[-1L]
  for (e in exprs) {
    result <- eval(e, envir = ds$observations, enclos = parent.frame())
    keep <- keep & as.logical(result)
  }
  out <- ds[which(keep)]
  if (grouped) {
    return(.nf_regroup(out, x$by))
  }
  out
}

#' Select observation columns
#'
#' Keeps only the named design columns (plus any columns required by feature
#' encodings, which are always retained).
#'
#' @param x An [nftab] object.
#' @param ... Column names (unquoted or character).
#' @param .cols Optional character vector of column names; use instead of `...`
#'   for programmatic selection.
#'
#' @return An [nftab] with fewer observation columns.
#' @export
nf_select <- function(x, ..., .cols = NULL) {
  grouped <- inherits(x, "grouped_nftab")
  ds <- if (grouped) x$data else x
  stopifnot(inherits(ds, "nftab"))
  if (!is.null(.cols)) {
    keep <- .cols
  } else {
    keep <- .nf_capture_names(substitute(list(...)))
  }

  # Always keep row_id, axes, and encoding columns
  required <- c(ds$manifest$row_id, ds$manifest$observation_axes)
  if (grouped) {
    required <- c(required, x$by)
  }
  for (feat in ds$manifest$features) {
    for (enc in feat$encodings) {
      if (enc$type == "columns") {
        required <- c(required, enc$binding$columns)
      }
      if (enc$type == "ref") {
        for (nm in c("resource_id", "backend", "locator", "selector", "checksum")) {
          vs <- enc$binding[[nm]]
          if (inherits(vs, "nf_column_ref") || (is.list(vs) && !is.null(vs$column))) {
            required <- c(required, vs$column)
          }
        }
      }
    }
  }

  all_keep <- unique(c(required, keep))
  all_keep <- intersect(all_keep, names(ds$observations))

  new_obs <- ds$observations[, all_keep, drop = FALSE]
  new_manifest <- ds$manifest
  new_manifest$observation_columns <- ds$manifest$observation_columns[all_keep]

  out <- nftab(
    manifest = new_manifest,
    observations = new_obs,
    resources = ds$resources,
    .root = ds$.root
  )
  if (grouped) {
    return(.nf_regroup(out, x$by))
  }
  out
}

#' Arrange (sort) observations
#'
#' @param x An [nftab] object.
#' @param ... Column names to sort by. Prefix with `-` for descending.
#' @param .by Optional character vector of sort column names; use instead of
#'   `...` for programmatic sorting.
#'
#' @return A reordered [nftab].
#' @export
nf_arrange <- function(x, ..., .by = NULL) {
  grouped <- inherits(x, "grouped_nftab")
  ds <- if (grouped) x$data else x
  stopifnot(inherits(ds, "nftab"))
  if (!is.null(.by)) {
    cols <- .by
  } else {
    cols <- .nf_capture_names(substitute(list(...)))
  }
  if (!length(cols)) return(x)

  desc <- grepl("^-", cols)
  cols <- sub("^-", "", cols)

  ord_args <- lapply(seq_along(cols), function(i) {
    v <- ds$observations[[cols[i]]]
    if (desc[i]) -xtfrm(v) else xtfrm(v)
  })

  idx <- do.call(order, ord_args)
  out <- ds[idx]
  if (grouped) {
    return(.nf_regroup(out, x$by))
  }
  out
}

#' Collect (resolve) a feature for all rows
#'
#' Resolves all rows for the named feature and returns results as a list.
#'
#' @param x An [nftab] object.
#' @param feature Feature name as a string or unquoted symbol.
#' @param simplify If `TRUE` and the feature is 1D with fixed shape, return
#'   a matrix instead of a list.
#' @param .progress Show progress? Default `FALSE`.
#'
#' @return A named list of resolved values, or a matrix if simplified.
#' @export
nf_collect <- function(x, feature, simplify = TRUE, .progress = FALSE) {
  if (inherits(x, "grouped_nftab")) {
    x <- x$data
  }
  stopifnot(inherits(x, "nftab"))
  feature <- .nf_capture_name(
    substitute(feature),
    env = parent.frame(),
    available = names(x$manifest$features),
    arg = "feature"
  )

  if (simplify) {
    col_plan <- .nf_columns_plan(x, feature)
    if (!is.null(col_plan) && all(col_plan$row_ok)) {
      out <- col_plan$matrix
      rownames(out) <- x$observations[[x$manifest$row_id]]
      return(out)
    }
  }

  results <- nf_resolve_all(x, feature, .progress = .progress)

  if (simplify) {
    feat <- x$manifest$features[[feature]]
    ls <- feat$logical
    if (length(ls$axes) == 1L && !is.null(ls$shape)) {
      # Try to simplify to matrix
      non_null <- !vapply(results, is.null, logical(1))
      if (all(non_null)) {
        mat <- do.call(rbind, results)
        return(mat)
      }
    }
  }

  results
}

#' Sample feature values at spatial coordinates across all observations
#'
#' Extracts feature values at a fixed set of spatial coordinates for every
#' observation, returning an `[n_obs x n_coords]` matrix.  This is the core
#' spatial query primitive — it maps directly to the `series_fun` contract
#' expected by tools like cluster.explorer.
#'
#' @param x An [nftab] object.
#' @param feature Feature name as a string or unquoted symbol.
#' @param coords An `n_coords x 3` integer matrix of voxel grid coordinates
#'   (1-based) when `coord_type = "voxel"`, or an `n_coords x 3` numeric
#'   matrix of mm world coordinates when `coord_type = "mm"`.
#' @param coord_type `"voxel"` (default) or `"mm"`.  mm conversion requires
#'   neuroim2 and native backend resolution.
#' @param rows Integer vector of row indices to include.  Defaults to all rows.
#' @param .progress Show progress messages every 10 rows?  Default `FALSE`.
#'
#' @return A numeric matrix with `length(rows)` rows and `nrow(coords)` columns.
#'   Row names are set to the corresponding `row_id` values.
#' @export
nf_sample <- function(x, feature, coords,
                       coord_type = c("voxel", "mm"),
                       rows = NULL,
                       .progress = FALSE) {
  coord_type <- match.arg(coord_type)
  ds <- if (inherits(x, "grouped_nftab")) x$data else x
  stopifnot(inherits(ds, "nftab"))
  feature <- .nf_capture_name(
    substitute(feature),
    env = parent.frame(),
    available = names(ds$manifest$features),
    arg = "feature"
  )

  feat <- ds$manifest$features[[feature]]
  if (is.null(feat)) stop("unknown feature: '", feature, "'", call. = FALSE)

  if (!is.matrix(coords) || ncol(coords) != 3L) {
    stop("'coords' must be a matrix with 3 columns (i, j, k)", call. = FALSE)
  }

  row_idx <- rows %||% seq_len(nrow(ds$observations))
  n_obs   <- length(row_idx)
  n_coords <- nrow(coords)

  result <- matrix(NA_real_, nrow = n_obs, ncol = n_coords)
  rownames(result) <- ds$observations[[ds$manifest$row_id]][row_idx]

  # For the voxel path, deduplicate file reads: resolve each unique

  # (locator, selector) once and cache the array.
  if (coord_type == "voxel") {
    .arr_cache <- new.env(parent = emptyenv())
    .cache_keys <- character(n_obs)

    for (ii in seq_along(row_idx)) {
      row <- as.list(ds$observations[row_idx[ii], , drop = FALSE])
      key <- NULL
      for (enc in feat$encodings) {
        if (!encoding_applicable(enc, row)) next
        if (enc$type == "ref") {
          ref_info <- .materialize_ref(enc$binding, row, ds$resources)
          key <- paste0(ref_info$locator, "||",
                        digest::digest(ref_info$selector, algo = "xxhash64"))
        } else {
          # columns or other: unique per row
          key <- paste0(".row:", row_idx[ii])
        }
        break
      }
      if (is.null(key)) key <- paste0(".row:", row_idx[ii])
      .cache_keys[ii] <- key

      if (!exists(key, envir = .arr_cache, inherits = FALSE)) {
        .arr_cache[[key]] <- nf_resolve(ds, row_idx[ii], feature, as_array = TRUE)
      }
    }
  }

  for (ii in seq_along(row_idx)) {
    if (coord_type == "mm") {
      # Needs NeuroSpace for mm -> linear index conversion
      vol <- nf_resolve(ds, row_idx[ii], feature, as_array = FALSE)
      if (!inherits(vol, "NeuroVol")) {
        stop(
          "mm coordinate sampling requires native NeuroVol resolution; ",
          "use a backend that supports as_array = FALSE (e.g. nifti + neuroim2)",
          call. = FALSE
        )
      }
      sp      <- neuroim2::space(vol)
      lin_idx <- neuroim2::coord_to_index(sp, coords)
      arr     <- array(as.vector(vol), dim = dim(vol))
    } else {
      arr <- .arr_cache[[.cache_keys[ii]]]
      d   <- dim(arr)[1:3]
      lin_idx <- coords[, 1L] +
        (coords[, 2L] - 1L) * d[1L] +
        (coords[, 3L] - 1L) * d[1L] * d[2L]
    }

    result[ii, ] <- as.numeric(arr[lin_idx])

    if (.progress && ii %% 10L == 0L) {
      message(sprintf("  nf_sample: %d / %d", ii, n_obs))
    }
  }

  result
}

#' Collect a volumetric feature as a stacked array with spatial metadata
#'
#' Resolves all observations for a 3D (volumetric) feature and stacks them
#' into a 4D array `[x, y, z, n_obs]`, preserving the `NeuroSpace` from the
#' first resolved volume.
#'
#' @param x An [nftab] object.
#' @param feature Feature name as a string or unquoted symbol.
#' @param .progress Show progress messages every 10 rows?  Default `FALSE`.
#'
#' @return A named list with two elements:
#'   \describe{
#'     \item{`data`}{A 4D numeric array with dimensions `c(x, y, z, n_obs)`.}
#'     \item{`space`}{The `NeuroSpace` object from the first resolved volume,
#'       or `NULL` if neuroim2 is not available or native resolution is not
#'       supported by the backend.}
#'   }
#' @export
nf_collect_array <- function(x, feature, .progress = FALSE) {
  if (inherits(x, "grouped_nftab")) x <- x$data
  stopifnot(inherits(x, "nftab"))
  feature <- .nf_capture_name(
    substitute(feature),
    env = parent.frame(),
    available = names(x$manifest$features),
    arg = "feature"
  )

  feat <- x$manifest$features[[feature]]
  if (is.null(feat)) stop("unknown feature: '", feature, "'", call. = FALSE)

  n <- nrow(x$observations)
  if (n == 0L) stop("nftab has no observations", call. = FALSE)

  first <- nf_resolve(x, 1L, feature, as_array = FALSE)
  d <- dim(first)

  if (is.null(d) || length(d) != 3L) {
    stop(
      "nf_collect_array() requires a 3D (volume) feature; ",
      "feature '", feature, "' resolved to dim [",
      paste(d, collapse = ", "), "]",
      call. = FALSE
    )
  }

  sp <- if (inherits(first, "NeuroVol")) neuroim2::space(first) else NULL

  # Fill using plain array resolution to avoid DenseNeuroVol S4 assignment
  # Cache the first row's array since we already resolved it above
  first_arr <- as.array(first)
  out <- array(NA_real_, dim = c(d, n))
  out[, , , 1L] <- first_arr
  if (n > 1L) {
    for (i in 2L:n) {
      out[, , , i] <- nf_resolve(x, i, feature, as_array = TRUE)
      if (.progress && i %% 10L == 0L) {
        message(sprintf("  nf_collect_array: %d / %d", i, n))
      }
    }
  }

  list(data = out, space = sp)
}

.nf_regroup <- function(x, by) {
  missing <- setdiff(by, names(x$observations))
  if (length(missing)) {
    stop("cannot preserve grouping; missing columns: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }

  structure(
    list(
      data = x,
      by = unique(by)
    ),
    class = "grouped_nftab"
  )
}
