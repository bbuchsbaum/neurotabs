# Split-apply-combine style feature computations

.nf_fixed_apply_ops <- c("mean", "sum", "sd", "min", "max", "nnz", "l2")
.nf_fixed_reduce_ops <- c("mean", "sum", "var", "sd", "se")
.nf_numeric_feature_dtypes <- c("bool", "int32", "int64", "uint8", "uint16", "float32", "float64")

#' Apply a function or fixed operation to a feature row-by-row
#'
#' For character `.f` values in `c("mean", "sum", "sd", "min", "max", "nnz",
#' "l2")`, `neurotabs` uses a fixed-operation path and will batch NIfTI reads
#' when possible. For a function `.f`, values are resolved row-by-row and passed
#' to that function.
#'
#' @param x An [nftab] object.
#' @param feature Feature name as a string or unquoted symbol.
#' @param .f Either a function or a character fixed operation.
#' @param ... Additional arguments passed to `.f` when `.f` is a function.
#' @param .progress Show progress during generic row-wise resolution. Default
#'   `FALSE`.
#'
#' @section Parallelism:
#' For NIfTI-backed features, file reads are automatically parallelized
#' using [parallel::mclapply()] with half the available cores. Set
#' `options(neurotabs.compute.workers = 1L)` to force sequential execution,
#' or a higher value for more parallelism. Disabled on Windows.
#'
#' @return A named vector or list with one result per row.
#' @export
nf_apply <- function(x, feature, .f, ..., .progress = FALSE) {
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

  if (is.character(.f)) {
    if (length(.f) != 1L || !.f %in% .nf_fixed_apply_ops) {
      stop(
        "character .f must be one of: ",
        paste(.nf_fixed_apply_ops, collapse = ", "),
        call. = FALSE
      )
    }
    return(.nf_apply_fixed(x, feature, .f, .progress = .progress))
  }

  if (!is.function(.f)) {
    stop(".f must be either a function or a supported fixed operation name", call. = FALSE)
  }

  values <- .nf_collect_feature_values(x, feature, .progress = .progress)
  out <- lapply(values, function(value) {
    if (is.null(value)) {
      return(NULL)
    }
    .f(value, ...)
  })
  .simplify_apply_result(out, x$observations[[x$manifest$row_id]])
}

#' Summarize a feature across rows or groups
#'
#' For character `.f` values in `c("mean", "sum", "var", "sd", "se")`,
#' `neurotabs` performs an elementwise reduction over resolved feature values
#' and will batch NIfTI reads when possible. `"se"` computes the standard error
#' of the mean (`sd / sqrt(n)`). For a function `.f`, each group receives the
#' list of resolved values for that feature.
#'
#' @param x An [nftab] object.
#' @param feature Feature name as a string or unquoted symbol.
#' @param by Optional character vector of observation columns defining groups.
#' @param .f Either a function or a fixed reducer name (`"mean"`, `"sum"`,
#'   `"var"`, `"sd"`, `"se"`).
#' @param ... Additional arguments passed to `.f` when `.f` is a function.
#' @param .progress Show progress during generic resolution. Default `FALSE`.
#'
#' @return If `by = NULL`, a single reduced value. Otherwise an [nftab] with one
#'   row per group and a summarized feature named `feature`.
#' @export
nf_summarize <- function(x, feature, by = NULL, .f = "mean", ..., .progress = FALSE) {
  grouped <- inherits(x, "grouped_nftab")
  ds <- if (grouped) x$data else x
  stopifnot(inherits(ds, "nftab"))
  feature <- .nf_capture_name(
    substitute(feature),
    env = parent.frame(),
    available = names(ds$manifest$features),
    arg = "feature"
  )
  if (grouped && !is.null(by)) {
    stop("when x is grouped_nftab, supply grouping via nf_group_by() rather than by=", call. = FALSE)
  }
  groups <- if (grouped) .nf_split_groups(ds$observations, x$by) else .nf_split_groups(ds$observations, by)

  if (is.character(.f)) {
    if (length(.f) != 1L || !.f %in% .nf_fixed_reduce_ops) {
      stop(
        "character .f must be one of: ",
        paste(.nf_fixed_reduce_ops, collapse = ", "),
        call. = FALSE
      )
    }

    fast <- .nf_summarize_columns_fast(ds, feature, groups, .f)
    if (!is.null(fast)) {
      return(.nf_pack_grouped_results(groups, fast, feature, ds = if (grouped || !is.null(by)) ds else NULL))
    }

    fast <- .nf_summarize_nifti_fast(ds, feature, groups, .f)
    if (!is.null(fast)) {
      return(.nf_pack_grouped_results(groups, fast, feature, ds = if (grouped || !is.null(by)) ds else NULL))
    }

    all_values <- .nf_collect_feature_values(ds, feature, .progress = .progress)
    results <- lapply(groups$rows, function(row_idx) {
      .nf_reduce_resolved(all_values[row_idx], .f)
    })
    return(.nf_pack_grouped_results(groups, results, feature, ds = if (grouped || !is.null(by)) ds else NULL))
  }

  if (!is.function(.f)) {
    stop(".f must be either a function or a supported fixed reducer name", call. = FALSE)
  }

  all_values <- .nf_collect_feature_values(ds, feature, .progress = .progress)
  results <- lapply(groups$rows, function(row_idx) {
    values <- all_values[row_idx]
    .f(values, ...)
  })
  .nf_pack_grouped_results(groups, results, feature, ds = if (grouped || !is.null(by)) ds else NULL)
}

#' Mutate observation columns
#'
#' Expressions are evaluated in the observation-table context. Inside
#' `nf_mutate()`, the helper `nf_apply_feature(feature, .f, ...)` is available
#' for deriving scalar columns from NFTab features, including fast fixed
#' operations over NIfTI-backed features.
#'
#' @param x An [nftab] object.
#' @param ... Named expressions yielding one scalar value per row (or a length-1
#'   value that can be recycled).
#'
#' @return An [nftab] object with additional or replaced observation columns.
#' @export
nf_mutate <- function(x, ...) {
  grouped <- inherits(x, "grouped_nftab")
  ds <- if (grouped) x$data else x
  stopifnot(inherits(ds, "nftab"))
  exprs <- as.list(substitute(list(...)))[-1L]
  if (!length(exprs)) {
    return(x)
  }

  expr_names <- names(exprs)
  if (is.null(expr_names) || any(!nzchar(expr_names))) {
    stop("all nf_mutate expressions must be named", call. = FALSE)
  }

  new_obs <- ds$observations
  eval_env <- list2env(as.list(new_obs), parent = parent.frame())
  feature_cache <- new.env(parent = emptyenv())
  eval_env$nf_apply_feature <- function(feature, .f, ..., .progress = FALSE) {
    feature <- .nf_capture_name(
      substitute(feature),
      env = parent.frame(),
      available = names(ds$manifest$features),
      arg = "feature"
    )
    key <- paste("apply", feature, .f, digest::digest(list(...), algo = "xxhash64"), sep = "::")
    if (!exists(key, envir = feature_cache, inherits = FALSE)) {
      feature_cache[[key]] <- nf_apply(ds, feature, .f, ..., .progress = .progress)
    }
    feature_cache[[key]]
  }
  eval_env$nf_collect_feature <- function(feature, simplify = TRUE, .progress = FALSE) {
    feature <- .nf_capture_name(
      substitute(feature),
      env = parent.frame(),
      available = names(ds$manifest$features),
      arg = "feature"
    )
    key <- paste("collect", feature, simplify, sep = "::")
    if (!exists(key, envir = feature_cache, inherits = FALSE)) {
      feature_cache[[key]] <- nf_collect(ds, feature, simplify = simplify, .progress = .progress)
    }
    feature_cache[[key]]
  }

  for (nm in expr_names) {
    value <- eval(exprs[[nm]], envir = eval_env, enclos = parent.frame())
    value <- .nf_normalize_mutate_value(value, nrow(new_obs), nm)
    new_obs[[nm]] <- value
    assign(nm, value, envir = eval_env)
  }

  new_manifest <- ds$manifest
  for (nm in expr_names) {
    new_manifest$observation_columns[[nm]] <- .nf_infer_col_schema(new_obs[[nm]])
  }

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

#' Build a matched reference cohort by exact column matching
#'
#' Returns the subset of `x` where observation columns exactly match the
#' provided values. Intended for use as the `.ref` argument in [nf_compare].
#'
#' @param x An [nftab] object providing the reference pool.
#' @param match_on Named list: column name -> one or more allowed values.
#'
#' @return An [nftab] containing only the matching observations.
#' @export
nf_matched_cohort <- function(x, match_on) {
  stopifnot(
    inherits(x, "nftab"),
    is.list(match_on),
    !is.null(names(match_on)),
    all(nzchar(names(match_on)))
  )
  obs <- x$observations
  keep <- rep(TRUE, nrow(obs))
  for (col in names(match_on)) {
    if (!col %in% names(obs)) {
      stop("match_on column '", col, "' not found in observations", call. = FALSE)
    }
    keep <- keep & obs[[col]] %in% match_on[[col]]
  }
  x[which(keep)]
}

#' Compare summarized feature values to a reference group
#'
#' If `x` is a `grouped_nftab`, `nf_compare()` first summarizes `feature`
#' within each group using `.reduce`, then compares every group to the reference
#' group `.ref`. If `x` is already a summary [nftab], the comparison is applied
#' directly to its feature values. If `x` is a summarized `data.frame`, it must
#' contain a list-column named `feature`.
#'
#' @param x A `grouped_nftab`, summary [nftab], or summarized `data.frame`.
#' @param feature Feature name / list-column name as a string or unquoted symbol.
#' @param .ref Reference group. If there is exactly one grouping column, this may
#'   be a scalar value. Otherwise provide a named list of grouping values.
#' @param .f Comparison operation: `"subtract"` or `"ratio"`.
#' @param .reduce Reducer used when `x` is grouped. Default `"mean"`.
#'
#' @return An [nftab] when `x` is a `grouped_nftab` or [nftab]. A summarized
#'   `data.frame` when `x` is already a summarized `data.frame`.
#' @export
nf_compare <- function(x, feature, .ref, .f = c("subtract", "ratio"), .reduce = "mean") {
  op <- match.arg(.f)
  feature <- .nf_capture_name(
    substitute(feature),
    env = parent.frame(),
    available = if (inherits(x, "grouped_nftab")) {
      names(x$data$manifest$features)
    } else if (inherits(x, "nftab")) {
      names(x$manifest$features)
    } else if (is.data.frame(x)) {
      names(x)
    } else {
      NULL
    },
    arg = "feature"
  )

  if (inherits(x, "grouped_nftab")) {
    x <- nf_summarize(x, feature, .f = .reduce)
  }

  # nftab path: resolve all feature values, compare, return nftab
  if (inherits(x, "nftab")) {
    # If .ref is itself an nftab, resolve and reduce it to a reference value
    if (inherits(.ref, "nftab")) {
      ref_values <- nf_collect(.ref, feature, simplify = TRUE)
      ref_value <- if (is.matrix(ref_values)) {
        apply(ref_values, 2, mean)
      } else {
        Reduce("+", ref_values) / length(ref_values)
      }
      all_values <- .nf_collect_feature_values(x, feature)
      compared <- lapply(all_values, .nf_compare_value, ref = ref_value, op = op)
      # Materialize back: columns encoding path for 1D features
      feat <- x$manifest$features[[feature]]
      is_1d <- length(feat$logical$axes) == 1L
      if (is_1d) {
        new_obs <- x$observations
        col_names <- feat$encodings[[1L]]$binding$columns
        if (is.null(col_names)) {
          stop("nf_compare with nftab .ref requires columns-encoded 1D feature", call. = FALSE)
        }
        for (i in seq_len(nrow(new_obs))) {
          if (!is.null(compared[[i]])) {
            for (j in seq_along(col_names)) {
              new_obs[[col_names[[j]]]][[i]] <- as.numeric(compared[[i]])[[j]]
            }
          }
        }
        return(nftab(manifest = x$manifest, observations = new_obs,
                     resources = x$resources, .root = x$.root))
      } else {
        stop("nf_compare with nftab .ref is only supported for 1D features", call. = FALSE)
      }
    }
    return(.nf_compare_nftab(x, feature, .ref, op))
  }

  if (!is.data.frame(x) || !feature %in% names(x)) {
    stop("nf_compare() requires a grouped_nftab, nftab, or summarized data.frame", call. = FALSE)
  }

  group_cols <- setdiff(names(x), feature)
  if (!length(group_cols)) {
    stop("nf_compare() requires grouping columns in the summarized data", call. = FALSE)
  }

  ref_idx <- .nf_match_reference_row(x, feature, .ref)
  ref_value <- x[[feature]][[ref_idx]]
  compared <- lapply(x[[feature]], .nf_compare_value, ref = ref_value, op = op)
  x[[feature]] <- compared
  x
}

.nf_compare_nftab <- function(x, feature, .ref, op) {
  feat <- x$manifest$features[[feature]]
  if (is.null(feat)) {
    stop("unknown feature: ", feature, call. = FALSE)
  }

  # Identify group columns: all observation_axes columns
  group_cols <- x$manifest$observation_axes
  if (!length(group_cols)) {
    stop("nf_compare() on an nftab requires observation_axes as group columns", call. = FALSE)
  }

  # Resolve all feature values
  all_values <- .nf_collect_feature_values(x, feature)

  # Find reference row
  obs <- x$observations
  if (length(group_cols) == 1L && length(.ref) == 1L && !is.list(.ref) && !is.data.frame(.ref)) {
    ref_idx <- which(obs[[group_cols[[1L]]]] == .ref)
  } else if (is.list(.ref)) {
    matches <- rep(TRUE, nrow(obs))
    for (nm in names(.ref)) {
      matches <- matches & obs[[nm]] == .ref[[nm]]
    }
    ref_idx <- which(matches)
  } else {
    stop("reference must be a scalar or named list of grouping values", call. = FALSE)
  }

  if (length(ref_idx) != 1L) {
    stop("reference specification must identify exactly one row", call. = FALSE)
  }

  ref_value <- all_values[[ref_idx]]

  compared_values <- lapply(all_values, .nf_compare_value, ref = ref_value, op = op)

  # Materialize compared values back as a new feature in a copy of x
  # Replace the feature values: use columns or nifti path depending on feature type
  is_1d <- length(feat$logical$axes) == 1L
  if (is_1d) {
    new_obs <- x$observations
    col_names <- feat$encodings[[1L]]$binding$columns
    if (is.null(col_names)) {
      stop("nf_compare on nftab requires columns-encoded 1D feature", call. = FALSE)
    }
    for (i in seq_len(nrow(new_obs))) {
      if (!is.null(compared_values[[i]])) {
        for (j in seq_along(col_names)) {
          new_obs[[col_names[[j]]]][[i]] <- as.numeric(compared_values[[i]])[[j]]
        }
      }
    }
    nftab(manifest = x$manifest, observations = new_obs,
          resources = x$resources, .root = x$.root)
  } else {
    # multi-dim: write new temp files and create a new nftab
    if (!requireNamespace("RNifti", quietly = TRUE)) {
      stop("RNifti is required for comparing multi-dimensional features", call. = FALSE)
    }
    tmpdir <- tempfile("nftab_compare_", tmpdir = tempdir())
    dir.create(tmpdir, recursive = TRUE)

    writer <- .get_backend_writer("nifti")
    n_rows <- nrow(x$observations)
    res_col <- paste0(feature, "_cmp_res")
    resource_ids <- paste0("cmp", seq_len(n_rows))
    locators <- character(n_rows)

    for (i in seq_len(n_rows)) {
      loc <- file.path(tmpdir, paste0("row_", i, ".nii.gz"))
      val <- compared_values[[i]]
      if (is.null(val)) val <- array(0, dim = feat$logical$shape)
      writer(loc, array(as.numeric(val), dim = dim(val)), feat$logical)
      locators[[i]] <- loc
    }

    new_obs <- x$observations
    new_obs[[res_col]] <- resource_ids

    new_resources <- data.frame(
      resource_id = resource_ids,
      backend     = "nifti",
      locator     = locators,
      checksum    = vapply(locators, function(path) {
        paste0("md5:", digest::digest(file = path, algo = "md5", serialize = FALSE))
      }, character(1)),
      stringsAsFactors = FALSE
    )
    resources <- if (is.null(x$resources)) new_resources else {
      as.data.frame(data.table::rbindlist(list(x$resources, new_resources), use.names = TRUE, fill = TRUE))
    }

    new_manifest <- x$manifest
    new_manifest$observation_columns[[res_col]] <- nf_col_schema("string", nullable = FALSE)
    if (is.null(new_manifest$resources)) {
      new_manifest$resources <- list(path = "resources.csv", format = "csv")
    }
    new_manifest$features[[feature]] <- nf_feature(
      logical   = feat$logical,
      encodings = list(nf_ref_encoding(resource_id = nf_col(res_col))),
      nullable  = feat$nullable
    )

    nftab(new_manifest, new_obs, resources = resources, .root = tmpdir)
  }
}

#' Mutate a derived feature
#'
#' Applies `.f` row-by-row to an existing feature and materializes the result as
#' a new NFTab feature. By default, the derived feature preserves the source
#' logical schema and uses storage selected from that schema:
#'
#' - 1D features use `columns` encoding
#' - volumetric features use temporary NIfTI resources
#'
#' @param x An [nftab] object or `grouped_nftab`.
#' @param name Name of the derived feature to create, as a string or unquoted symbol.
#' @param feature Source feature name as a string or unquoted symbol.
#' @param .f Function applied to each resolved feature value.
#' @param ... Additional arguments passed to `.f`.
#' @param logical Optional [nf_logical_schema] describing the derived feature.
#'   If omitted, the source logical schema is reused and outputs must conform to
#'   it.
#' @param storage Storage strategy: `"auto"`, `"columns"`, or `"nifti"`.
#' @param description Optional description for the new feature.
#' @param .progress Show progress during generic row-wise resolution. Default
#'   `FALSE`.
#'
#' Rows where `.f` returns `NULL` are encoded as missing values, and the derived
#' feature is marked nullable.
#'
#' @return An updated [nftab] object, or `grouped_nftab` when input is grouped.
#' @export
nf_mutate_feature <- function(x, name, feature, .f, ..., logical = NULL,
                              storage = c("auto", "columns", "nifti"),
                              description = NULL, .progress = FALSE) {
  grouped <- inherits(x, "grouped_nftab")
  ds <- if (grouped) x$data else x
  stopifnot(inherits(ds, "nftab"))
  name <- .nf_capture_name(substitute(name), env = parent.frame(), arg = "name")
  feature <- .nf_capture_name(
    substitute(feature),
    env = parent.frame(),
    available = names(ds$manifest$features),
    arg = "feature"
  )
  if (!is.function(.f)) {
    stop(".f must be a function", call. = FALSE)
  }
  if (!is.null(ds$manifest$features[[name]])) {
    stop("feature '", name, "' already exists", call. = FALSE)
  }

  transformed <- .nf_transform_feature_rows(ds, feature, .f, ..., .progress = .progress)
  sample_value <- transformed$sample
  if (is.null(sample_value)) {
    stop("derived feature produced no non-missing values", call. = FALSE)
  }

  source_logical <- nf_feature_schema(ds, feature)
  if (is.null(logical)) {
    logical <- .nf_derive_feature_logical(source_logical, sample_value)
  } else {
    stopifnot(inherits(logical, "nf_logical_schema"))
  }

  for (value in transformed$values) {
    if (!is.null(value)) {
      .validate_resolved(value, logical)
    }
  }

  storage <- match.arg(storage)
  if (storage == "auto") {
    storage <- if (length(logical$axes) == 1L) {
      "columns"
    } else if (identical(logical$kind, "volume")) {
      "nifti"
    } else {
      stop(
        "auto storage only supports 1D features or volume features; provide storage explicitly",
        call. = FALSE
      )
    }
  }

  out <- switch(
    storage,
    columns = .nf_materialize_columns_feature(
      ds, name, logical, transformed$values,
      description = description %||% paste("derived from", feature)
    ),
    nifti = .nf_materialize_nifti_feature(
      ds, name, logical, transformed$values, transformed$templates,
      description = description %||% paste("derived from", feature)
    ),
    stop("unsupported storage strategy: ", storage, call. = FALSE)
  )

  if (grouped) {
    return(.nf_regroup(out, x$by))
  }
  out
}

.nf_apply_fixed <- function(x, feature, op, .progress = FALSE) {
  fast <- .nf_apply_columns_fast(x, feature, op)
  if (!is.null(fast)) {
    return(fast)
  }

  fast <- .nf_apply_nifti_fast(x, feature, op)
  if (!is.null(fast)) {
    return(fast)
  }

  values <- nf_resolve_all(x, feature, .progress = .progress)
  out <- vapply(values, .nf_scalar_stat, numeric(1), op = op)
  names(out) <- names(values)
  out
}

.nf_apply_columns_fast <- function(x, feature, op) {
  plan <- .nf_columns_plan(x, feature)
  if (is.null(plan) || is.null(plan$numeric_matrix)) {
    return(NULL)
  }

  results <- rep(NA_real_, nrow(x$observations))
  if (any(plan$row_ok)) {
    results[plan$row_ok] <- cpp_matrix_row_stat(
      plan$numeric_matrix[plan$row_ok, , drop = FALSE],
      op
    )
  }
  names(results) <- x$observations[[x$manifest$row_id]]
  results
}

.nf_apply_nifti_fast <- function(x, feature, op) {
  plan <- .nf_nifti_plan(x, feature)
  if (is.null(plan)) {
    return(NULL)
  }

  results <- rep(NA_real_, nrow(x$observations))
  task_values <- .nf_eval_nifti_tasks(
    plan,
    function(img, selector) {
      value <- .nifti_extract_cached(img, selector)
      .nf_scalar_stat(value, op = op)
    }
  )

  for (entry in plan) {
    results[[entry$row_index]] <- task_values[[entry$task_key]]
  }

  names(results) <- x$observations[[x$manifest$row_id]]
  results
}

.nf_summarize_nifti_fast <- function(x, feature, groups, op) {
  plan <- .nf_nifti_plan(x, feature)
  if (is.null(plan)) {
    return(NULL)
  }

  states <- vector("list", length(groups$rows))
  for (group_index in seq_along(groups$rows)) {
    states[[group_index]] <- .nf_make_reduce_state(op)
  }

  group_lookup <- integer(nrow(x$observations))
  for (group_index in seq_along(groups$rows)) {
    group_lookup[groups$rows[[group_index]]] <- group_index
  }

  task_values <- .nf_eval_nifti_tasks(
    plan,
    function(img, selector) {
      arr <- .nifti_extract_cached(img, selector)
      list(data = as.numeric(arr), dim = dim(arr))
    }
  )

  for (entry in plan) {
    cached <- task_values[[entry$task_key]]
    group_index <- group_lookup[[entry$row_index]]
    states[[group_index]] <- .nf_update_reduce_state(states[[group_index]], cached$data, cached$dim, op)
  }

  lapply(states, function(state) .nf_finalize_reduce_state(state, op))
}

.nf_summarize_columns_fast <- function(x, feature, groups, op) {
  plan <- .nf_columns_plan(x, feature)
  if (is.null(plan) || is.null(plan$numeric_matrix)) {
    return(NULL)
  }

  matrix <- plan$numeric_matrix
  lapply(groups$rows, function(row_idx) {
    keep <- row_idx[plan$row_ok[row_idx]]
    if (!length(keep)) {
      return(NULL)
    }

    block <- matrix[keep, , drop = FALSE]
    sum_vec <- colSums(block)
    n <- nrow(block)

    switch(
      op,
      sum = sum_vec,
      mean = sum_vec / n,
      var = {
        if (n < 2L) {
          sum_vec * 0
        } else {
          sumsq <- colSums(block * block)
          (sumsq - (sum_vec * sum_vec) / n) / (n - 1L)
        }
      },
      sd = {
        if (n < 2L) {
          sum_vec * 0
        } else {
          sumsq <- colSums(block * block)
          sqrt(pmax((sumsq - (sum_vec * sum_vec) / n) / (n - 1L), 0))
        }
      },
      se = {
        if (n < 2L) {
          sum_vec * 0
        } else {
          sumsq <- colSums(block * block)
          sqrt(pmax((sumsq - (sum_vec * sum_vec) / n) / (n - 1L), 0)) / sqrt(n)
        }
      },
      stop("unsupported reducer: ", op, call. = FALSE)
    )
  })
}

.nf_nifti_plan <- function(x, feature) {
  if (!requireNamespace("RNifti", quietly = TRUE)) {
    return(NULL)
  }

  feat <- x$manifest$features[[feature]]
  if (is.null(feat) || length(feat$encodings) != 1L || feat$encodings[[1L]]$type != "ref") {
    return(NULL)
  }

  enc <- feat$encodings[[1L]]
  checksum_cache <- new.env(parent = emptyenv())
  plan <- vector("list", nrow(x$observations))

  for (i in seq_len(nrow(x$observations))) {
    row <- as.list(x$observations[i, , drop = FALSE])
    if (!encoding_applicable(enc, row)) {
      return(NULL)
    }

    ref_info <- .materialize_ref(enc$binding, row, x$resources)
    if (!identical(ref_info$backend, "nifti")) {
      return(NULL)
    }

    locator <- ref_info$locator
    if (!is.null(x$.root) && !grepl("^(/|[a-zA-Z]:|[a-zA-Z][a-zA-Z0-9+.-]*://)", locator)) {
      locator <- file.path(x$.root, locator)
    }

    selector_key <- .nf_nifti_selector_key(ref_info$selector)
    if (is.null(selector_key)) {
      return(NULL)
    }

    checksum_key <- paste(locator, ref_info$checksum %||% "", sep = "::")
    if (!exists(checksum_key, envir = checksum_cache, inherits = FALSE)) {
      .validate_resource_checksum(locator, ref_info$checksum)
      checksum_cache[[checksum_key]] <- TRUE
    }

    plan[[i]] <- list(
      row_index = i,
      locator = locator,
      selector = ref_info$selector,
      key = selector_key,
      task_key = paste(locator, selector_key, sep = "::")
    )
  }

  plan
}

.nf_nifti_selector_key <- function(selector) {
  if (is.null(selector)) {
    return("full")
  }

  t_idx <- selector$index$t
  if (length(t_idx) == 1L && is.numeric(t_idx) && is.finite(t_idx)) {
    return(paste0("t:", as.integer(t_idx)))
  }

  NULL
}

.nifti_extract_cached <- function(img, selector) {
  if (is.null(selector)) {
    return(as.array(img))
  }

  t_idx <- selector$index$t
  if (!is.null(t_idx)) {
    ndim <- length(dim(img))
    if (ndim < 4L) {
      stop("selector specifies index.t but NIfTI is not 4D", call. = FALSE)
    }
    return(as.array(img[, , , as.integer(t_idx) + 1L, drop = TRUE]))
  }

  stop("unsupported nifti selector in compute path", call. = FALSE)
}

.nf_scalar_stat <- function(value, op) {
  if (is.null(value)) {
    return(NA_real_)
  }
  storage.mode(value) <- "double"
  cpp_numeric_stat(as.numeric(value), op)
}

.nf_reduce_resolved <- function(values, op) {
  non_null <- Filter(Negate(is.null), values)
  if (!length(non_null)) {
    return(NULL)
  }

  state <- .nf_make_reduce_state(op)
  for (value in non_null) {
    state <- .nf_update_reduce_state(state, as.numeric(value), dim(value), op)
  }
  .nf_finalize_reduce_state(state, op)
}

.nf_make_reduce_state <- function(op) {
  list(
    sum = NULL,
    sumsq = NULL,
    dim = NULL,
    count = 0L,
    op = op
  )
}

.nf_update_reduce_state <- function(state, value, value_dim, op) {
  if (is.null(state$sum)) {
    state$sum <- as.numeric(value)
    if (op %in% c("var", "sd", "se")) {
      state$sumsq <- as.numeric(value) * as.numeric(value)
    }
    state$dim <- value_dim
    state$count <- 1L
    return(state)
  }

  if (!identical(state$dim, value_dim)) {
    stop("cannot summarize feature values with different shapes", call. = FALSE)
  }

  state$sum <- cpp_accumulate_sum(state$sum, as.numeric(value))
  if (op %in% c("var", "sd", "se")) {
    state$sumsq <- cpp_accumulate_sumsq(state$sumsq, as.numeric(value))
  }
  state$count <- state$count + 1L
  state
}

.nf_finalize_reduce_state <- function(state, op) {
  if (is.null(state$sum)) {
    return(NULL)
  }

  out <- switch(
    op,
    sum = state$sum,
    mean = state$sum / state$count,
    var = {
      if (state$count < 2L) {
        state$sum * 0
      } else {
        numerator <- state$sumsq - (state$sum * state$sum) / state$count
        numerator / (state$count - 1L)
      }
    },
    sd = {
      if (state$count < 2L) {
        state$sum * 0
      } else {
        numerator <- state$sumsq - (state$sum * state$sum) / state$count
        sqrt(pmax(numerator / (state$count - 1L), 0))
      }
    },
    se = {
      if (state$count < 2L) {
        state$sum * 0
      } else {
        numerator <- state$sumsq - (state$sum * state$sum) / state$count
        sqrt(pmax(numerator / (state$count - 1L), 0)) / sqrt(state$count)
      }
    },
    stop("unsupported reducer: ", op, call. = FALSE)
  )

  .nf_restore_shape(out, state$dim)
}

.nf_restore_shape <- function(x, dims) {
  if (is.null(dims)) {
    return(x)
  }
  array(x, dim = dims)
}

.nf_split_groups <- function(observations, by) {
  if (is.null(by) || !length(by)) {
    return(list(
      keys = data.frame(.all = "all", stringsAsFactors = FALSE)[FALSE, , drop = FALSE],
      rows = list(seq_len(nrow(observations))),
      by = character()
    ))
  }

  if (!all(by %in% names(observations))) {
    missing <- setdiff(by, names(observations))
    stop("unknown grouping columns: ", paste(missing, collapse = ", "), call. = FALSE)
  }

  key_df <- observations[, by, drop = FALSE]
  split_idx <- split(seq_len(nrow(observations)), interaction(key_df, drop = TRUE, lex.order = TRUE))
  key_rows <- vapply(split_idx, `[`, integer(1), 1L)

  list(
    keys = key_df[key_rows, , drop = FALSE],
    rows = unname(split_idx),
    by = by
  )
}

.nf_pack_grouped_results <- function(groups, results, feature, ds = NULL) {
  if (!length(groups$by)) {
    return(results[[1L]])
  }

  if (!is.null(ds)) {
    return(.nf_pack_grouped_nftab(groups, results, feature, ds))
  }

  out <- groups$keys
  out[[feature]] <- I(results)
  rownames(out) <- NULL
  out
}

.nf_pack_grouped_nftab <- function(groups, results, feature, ds) {
  feat <- ds$manifest$features[[feature]]
  is_1d <- length(feat$logical$axes) == 1L

  new_obs <- groups$keys
  rownames(new_obs) <- NULL
  n_groups <- nrow(new_obs)
  new_obs$.row_id <- paste0(".s", seq_len(n_groups))

  # .members: JSON array of contributing row_ids per group
  row_id_col <- ds$manifest$row_id
  new_obs$.members <- vapply(groups$rows, function(idx) {
    jsonlite::toJSON(as.character(ds$observations[[row_id_col]][idx]))
  }, character(1L))

  if (is_1d) {
    # columns encoding path
    non_null <- Filter(Negate(is.null), results)
    if (!length(non_null)) {
      stop("all group summaries produced NULL results", call. = FALSE)
    }
    vec_len <- length(non_null[[1L]])
    col_names <- paste0(feature, "_", seq_len(vec_len))

    mat <- matrix(NA_real_, nrow = n_groups, ncol = vec_len)
    for (i in seq_len(n_groups)) {
      if (!is.null(results[[i]])) {
        mat[i, ] <- as.numeric(results[[i]])
      }
    }

    for (j in seq_len(vec_len)) {
      new_obs[[col_names[[j]]]] <- mat[, j]
    }

    scalar_dtype <- .nf_scalar_dtype_for_feature_dtype(feat$logical$dtype)
    obs_cols <- vector("list", length(names(new_obs)))
    names(obs_cols) <- names(new_obs)

    for (grp_col in groups$by) {
      src_schema <- ds$manifest$observation_columns[[grp_col]]
      obs_cols[[grp_col]] <- if (!is.null(src_schema)) src_schema else nf_col_schema("string", nullable = FALSE)
    }
    obs_cols[[".row_id"]] <- nf_col_schema("string", nullable = FALSE)
    obs_cols[[".members"]] <- nf_col_schema("json", nullable = TRUE)
    for (col_name in col_names) {
      obs_cols[[col_name]] <- nf_col_schema(scalar_dtype, nullable = TRUE)
    }

    new_logical <- feat$logical
    new_logical$shape <- as.integer(vec_len)

    new_feat <- nf_feature(
      logical = new_logical,
      encodings = list(nf_columns_encoding(col_names)),
      nullable = any(vapply(results, is.null, logical(1L)))
    )

    new_manifest <- nf_manifest(
      spec_version = ds$manifest$spec_version,
      dataset_id   = paste0(ds$manifest$dataset_id, "-summary"),
      row_id       = ".row_id",
      observation_axes = groups$by,
      observation_columns = obs_cols,
      features     = stats::setNames(list(new_feat), feature)
    )

    return(nftab(manifest = new_manifest, observations = new_obs))
  }

  # multi-dim path: write each result to a temp NIfTI file
  if (!requireNamespace("RNifti", quietly = TRUE)) {
    stop("RNifti is required for summarizing multi-dimensional features", call. = FALSE)
  }

  tmpdir <- tempfile("nftab_summary_", tmpdir = tempdir())
  dir.create(tmpdir, recursive = TRUE)

  writer <- .get_backend_writer("nifti")
  locators <- character(n_groups)
  resource_ids <- paste0("g", seq_len(n_groups))

  for (i in seq_len(n_groups)) {
    loc <- file.path(tmpdir, paste0("group_", i, ".nii.gz"))
    val <- results[[i]]
    if (is.null(val)) {
      val <- array(0, dim = feat$logical$shape)
    } else {
      val <- array(as.numeric(val), dim = dim(val))
    }
    writer(loc, val, feat$logical)
    locators[[i]] <- loc
  }

  new_obs$resource_id <- resource_ids

  resources <- data.frame(
    resource_id = resource_ids,
    backend     = "nifti",
    locator     = locators,
    checksum    = vapply(locators, function(path) {
      paste0("md5:", digest::digest(file = path, algo = "md5", serialize = FALSE))
    }, character(1)),
    stringsAsFactors = FALSE
  )

  obs_cols <- vector("list", length(names(new_obs)))
  names(obs_cols) <- names(new_obs)
  for (grp_col in groups$by) {
    src_schema <- ds$manifest$observation_columns[[grp_col]]
    obs_cols[[grp_col]] <- if (!is.null(src_schema)) src_schema else nf_col_schema("string", nullable = FALSE)
  }
  obs_cols[[".row_id"]]    <- nf_col_schema("string", nullable = FALSE)
  obs_cols[[".members"]]   <- nf_col_schema("json", nullable = TRUE)
  obs_cols[["resource_id"]] <- nf_col_schema("string", nullable = FALSE)

  new_feat <- nf_feature(
    logical   = feat$logical,
    encodings = list(nf_ref_encoding(resource_id = nf_col("resource_id"))),
    nullable  = any(vapply(results, is.null, logical(1L)))
  )

  new_manifest <- nf_manifest(
    spec_version = ds$manifest$spec_version,
    dataset_id   = paste0(ds$manifest$dataset_id, "-summary"),
    row_id       = ".row_id",
    observation_axes = groups$by,
    observation_columns = obs_cols,
    features     = stats::setNames(list(new_feat), feature),
    supports     = ds$manifest$supports,
    resources_path = "resources.csv"
  )

  nftab(manifest = new_manifest, observations = new_obs,
        resources = resources, .root = tmpdir)
}

.nf_match_reference_row <- function(x, feature, ref) {
  group_cols <- setdiff(names(x), feature)

  if (length(group_cols) == 1L && length(ref) == 1L && !is.list(ref) && !is.data.frame(ref)) {
    matches <- which(x[[group_cols[[1L]]]] == ref)
  } else if (is.list(ref)) {
    matches <- rep(TRUE, nrow(x))
    for (nm in names(ref)) {
      if (!nm %in% group_cols) {
        stop("reference specifies unknown grouping column '", nm, "'", call. = FALSE)
      }
      matches <- matches & x[[nm]] == ref[[nm]]
    }
    matches <- which(matches)
  } else {
    stop("reference must be a scalar or named list of grouping values", call. = FALSE)
  }

  if (length(matches) != 1L) {
    stop("reference specification must identify exactly one summarized row", call. = FALSE)
  }

  matches
}

.nf_compare_value <- function(value, ref, op) {
  if (is.null(value) || is.null(ref)) {
    return(NULL)
  }

  switch(
    op,
    subtract = value - ref,
    ratio = value / ref,
    stop("unsupported compare op: ", op, call. = FALSE)
  )
}

.nf_collect_feature_values <- function(x, feature, .progress = FALSE) {
  transformed <- .nf_transform_feature_rows(
    x,
    feature,
    function(value) value,
    .progress = .progress
  )
  values <- transformed$values
  names(values) <- x$observations[[x$manifest$row_id]]
  values
}

.nf_nifti_task_table <- function(plan) {
  tasks <- lapply(plan, function(entry) {
    list(
      task_key = entry$task_key,
      locator = entry$locator,
      selector = entry$selector
    )
  })
  task_keys <- vapply(tasks, `[[`, character(1), "task_key")
  tasks[!duplicated(task_keys)]
}

.nf_eval_nifti_tasks <- function(plan, fun) {
  tasks <- .nf_nifti_task_table(plan)

  # Group tasks by locator to read each file only once
  locators <- vapply(tasks, `[[`, character(1), "locator")
  unique_locators <- unique(locators)
  workers <- .nf_parallel_workers(length(unique_locators))

  eval_file <- function(loc) {
    img <- RNifti::readNifti(loc)
    file_tasks <- tasks[locators == loc]
    lapply(file_tasks, function(task) {
      list(task_key = task$task_key, value = fun(img, task$selector))
    })
  }

  raw_results <- if (workers > 1L) {
    parallel::mclapply(unique_locators, eval_file, mc.cores = workers)
  } else {
    lapply(unique_locators, eval_file)
  }

  # Flatten and index by task_key
  all_results <- unlist(raw_results, recursive = FALSE)
  stats::setNames(
    lapply(all_results, `[[`, "value"),
    vapply(all_results, `[[`, character(1), "task_key")
  )
}

.nf_parallel_workers <- function(task_count) {
  workers <- getOption("neurotabs.compute.workers", NULL)
  if (is.null(workers)) {
    # Auto-detect: half the available cores, minimum 1
    workers <- max(parallel::detectCores(logical = FALSE) %/% 2L, 1L)
  }
  workers <- suppressWarnings(as.integer(workers[[1L]]))
  if (length(workers) != 1L || is.na(workers) || workers < 1L) {
    workers <- 1L
  }
  # nocov start
  if (.Platform$OS.type == "windows") {
    return(1L)
  }
  # nocov end
  min(workers, max(task_count, 1L))
}

.nf_transform_feature_rows <- function(x, feature, .f, ..., .progress = FALSE) {
  plan <- .nf_nifti_plan(x, feature)
  values <- vector("list", nrow(x$observations))
  templates <- vector("list", nrow(x$observations))
  sample <- NULL

  if (is.null(plan)) {
    col_plan <- .nf_columns_plan(x, feature)
    if (!is.null(col_plan)) {
      for (i in seq_len(nrow(x$observations))) {
        source_value <- .nf_columns_row_value(col_plan, i)
        transformed <- if (is.null(source_value)) NULL else .f(source_value, ...)
        values[i] <- list(transformed)
        if (is.null(sample) && !is.null(transformed)) {
          sample <- transformed
        }
        if (.progress && i %% 10L == 0L) {
          message(sprintf("  transformed %d / %d", i, nrow(x$observations)))
        }
      }
      return(list(values = values, templates = templates, sample = sample))
    }
  }

  if (is.null(plan)) {
    for (i in seq_len(nrow(x$observations))) {
      source_value <- nf_resolve(x, i, feature)
      transformed <- if (is.null(source_value)) NULL else .f(source_value, ...)
      values[i] <- list(transformed)
      if (is.null(sample) && !is.null(transformed)) {
        sample <- transformed
      }
      if (.progress && i %% 10L == 0L) {
        message(sprintf("  transformed %d / %d", i, nrow(x$observations)))
      }
    }
    return(list(values = values, templates = templates, sample = sample))
  }

  task_values <- .nf_eval_nifti_tasks(
    plan,
    function(img, selector) {
      materialized <- .nifti_materialize_with_template(img, selector)
      .f(materialized$value, ...)
    }
  )

  for (i in seq_along(plan)) {
    entry <- plan[[i]]
    transformed <- task_values[[entry$task_key]]
    values[entry$row_index] <- list(transformed)
    templates[entry$row_index] <- list(list(
      locator = entry$locator,
      selector = entry$selector,
      task_key = entry$task_key
    ))
    if (is.null(sample) && !is.null(transformed)) {
      sample <- transformed
    }
  }

  list(values = values, templates = templates, sample = sample)
}

.nf_derive_feature_logical <- function(source_logical, sample_value) {
  out_shape <- dim(sample_value)
  if (is.null(out_shape)) {
    out_shape <- as.integer(length(sample_value))
  } else {
    out_shape <- as.integer(out_shape)
  }

  expected_shape <- source_logical$shape
  if (is.null(expected_shape)) {
    expected_shape <- if (length(source_logical$axes) == 1L) {
      as.integer(length(sample_value))
    } else {
      out_shape
    }
  }

  if (!identical(as.integer(expected_shape), as.integer(out_shape))) {
    stop(
      "derived feature output does not match source logical shape; supply logical= explicitly",
      call. = FALSE
    )
  }

  source_logical
}

.nf_materialize_columns_feature <- function(x, name, logical, values, description) {
  if (length(logical$axes) != 1L) {
    stop("columns storage requires a 1D logical feature", call. = FALSE)
  }

  is_null <- vapply(values, is.null, logical(1))
  first_value <- values[[which.max(!is_null)]]
  column_count <- if (!is.null(logical$shape)) logical$shape[[1L]] else length(first_value)
  col_names <- .nf_unique_names(names(x$observations), paste0(name, "_", seq_len(column_count)))
  new_obs <- x$observations
  matrix_data <- matrix(.nf_column_fun_value(logical$dtype), nrow = length(values), ncol = column_count)

  for (i in which(!is_null)) {
    matrix_data[i, ] <- .nf_cast_feature_value(values[[i]], logical$dtype)
  }

  for (j in seq_len(column_count)) {
    new_obs[[col_names[[j]]]] <- matrix_data[, j]
  }

  new_manifest <- x$manifest
  scalar_dtype <- .nf_scalar_dtype_for_feature_dtype(logical$dtype)
  for (col_name in col_names) {
    new_manifest$observation_columns[[col_name]] <- nf_col_schema(
      scalar_dtype,
      nullable = anyNA(new_obs[[col_name]])
    )
  }
  new_manifest$features[[name]] <- nf_feature(
    logical = logical,
    encodings = list(nf_columns_encoding(col_names)),
    nullable = any(is_null),
    description = description
  )

  nftab(new_manifest, new_obs, resources = x$resources, .root = x$.root)
}

.nf_materialize_nifti_feature <- function(x, name, logical, values, templates, description) {
  if (!requireNamespace("RNifti", quietly = TRUE)) {
    stop("RNifti package is required for nifti feature materialization", call. = FALSE)
  }
  if (!identical(logical$kind, "volume")) {
    stop("nifti storage currently supports logical kind 'volume' only", call. = FALSE)
  }

  out_dir <- file.path(tempdir(), "neurotabs-derived", paste0(name, "-", as.integer(Sys.time())))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  res_col <- .nf_unique_names(names(x$observations), paste0(name, "_res"))[[1L]]
  is_null <- vapply(values, is.null, logical(1))
  non_null_idx <- which(!is_null)
  resource_ids <- rep(NA_character_, length(values))
  locators <- character(length(non_null_idx))
  template_cache <- new.env(parent = emptyenv())

  for (j in seq_along(non_null_idx)) {
    i <- non_null_idx[[j]]
    resource_ids[[i]] <- paste0(name, "_", i)
    locator <- file.path(out_dir, paste0(resource_ids[[i]], ".nii.gz"))
    template <- .nf_rehydrate_nifti_template(templates[[i]], cache = template_cache)
    if (is.null(template)) {
      RNifti::writeNifti(values[[i]], locator)
    } else {
      RNifti::writeNifti(values[[i]], locator, template = template)
    }
    locators[[j]] <- locator
  }

  new_obs <- x$observations
  new_obs[[res_col]] <- resource_ids

  new_resources <- data.frame(
    resource_id = resource_ids[non_null_idx],
    backend = rep("nifti", length(non_null_idx)),
    locator = locators,
    checksum = vapply(locators, function(path) {
      paste0("md5:", digest::digest(file = path, algo = "md5", serialize = FALSE))
    }, character(1)),
    stringsAsFactors = FALSE
  )
  resources <- if (is.null(x$resources)) new_resources else {
    as.data.frame(data.table::rbindlist(list(x$resources, new_resources), use.names = TRUE, fill = TRUE))
  }

  new_manifest <- x$manifest
  new_manifest$observation_columns[[res_col]] <- nf_col_schema("string", nullable = any(is_null))
  if (is.null(new_manifest$resources)) {
    new_manifest$resources <- list(path = "resources.csv", format = "csv")
  }
  new_manifest$features[[name]] <- nf_feature(
    logical = logical,
    encodings = list(nf_ref_encoding(resource_id = nf_col(res_col))),
    nullable = any(is_null),
    description = description
  )

  nftab(new_manifest, new_obs, resources = resources, .root = x$.root)
}

.nf_unique_names <- function(existing, proposed) {
  out <- proposed
  taken <- unique(existing)
  for (i in seq_along(out)) {
    base <- out[[i]]
    candidate <- base
    suffix <- 1L
    while (candidate %in% taken || (i > 1L && candidate %in% out[seq_len(i - 1L)])) {
      candidate <- paste0(base, "_", suffix)
      suffix <- suffix + 1L
    }
    out[[i]] <- candidate
  }
  out
}

.nf_scalar_dtype_for_feature_dtype <- function(dtype) {
  switch(
    dtype,
    uint8 = "int32",
    uint16 = "int32",
    dtype
  )
}

.nf_cast_feature_value <- function(value, dtype) {
  scalar_dtype <- .nf_scalar_dtype_for_feature_dtype(dtype)
  flat <- as.vector(value)
  switch(
    scalar_dtype,
    string = as.character(flat),
    int32 = as.integer(flat),
    int64 = as.numeric(flat),
    float32 = as.numeric(flat),
    float64 = as.numeric(flat),
    bool = as.logical(flat),
    flat
  )
}

.nf_column_fun_value <- function(dtype) {
  switch(
    .nf_scalar_dtype_for_feature_dtype(dtype),
    string = NA_character_,
    int32 = NA_integer_,
    int64 = NA_real_,
    float32 = NA_real_,
    float64 = NA_real_,
    bool = NA,
    numeric(1)
  )
}

.nf_cast_feature_scalar <- function(value, index, dtype) {
  scalar_dtype <- .nf_scalar_dtype_for_feature_dtype(dtype)
  if (is.null(value)) {
    return(.nf_column_fun_value(dtype))
  }

  scalar <- as.vector(value)[[index]]
  switch(
    scalar_dtype,
    string = as.character(scalar),
    int32 = as.integer(scalar),
    int64 = as.numeric(scalar),
    float32 = as.numeric(scalar),
    float64 = as.numeric(scalar),
    bool = as.logical(scalar),
    scalar
  )
}

.nf_columns_plan <- function(x, feature) {
  feat <- x$manifest$features[[feature]]
  if (is.null(feat) || length(feat$encodings) != 1L || feat$encodings[[1L]]$type != "columns") {
    return(NULL)
  }
  if (!feat$logical$dtype %in% c(.nf_numeric_feature_dtypes, "string")) {
    return(NULL)
  }

  cols <- feat$encodings[[1L]]$binding$columns
  if (!all(cols %in% names(x$observations))) {
    return(NULL)
  }

  raw_block <- x$observations[, cols, drop = FALSE]
  row_ok <- stats::complete.cases(raw_block)
  typed_cols <- lapply(cols, function(col) .coerce_columns_value(x$observations[[col]], feat$logical$dtype))
  matrix_data <- do.call(cbind, typed_cols)

  numeric_matrix <- NULL
  if (feat$logical$dtype %in% .nf_numeric_feature_dtypes) {
    numeric_matrix <- do.call(cbind, lapply(typed_cols, as.numeric))
    storage.mode(numeric_matrix) <- "double"
  }

  list(
    matrix = matrix_data,
    numeric_matrix = numeric_matrix,
    row_ok = row_ok,
    dtype = feat$logical$dtype,
    logical = feat$logical
  )
}

.nf_columns_row_value <- function(plan, row_index) {
  if (!plan$row_ok[[row_index]]) {
    return(NULL)
  }

  out <- plan$matrix[row_index, , drop = TRUE]
  if (is.matrix(out)) {
    out <- as.vector(out)
  }
  out
}

.nifti_materialize_with_template <- function(img, selector) {
  if (is.null(selector)) {
    return(list(value = as.array(img), template = img))
  }

  t_idx <- selector$index$t
  if (!is.null(t_idx)) {
    ndim <- length(dim(img))
    if (ndim < 4L) {
      stop("selector specifies index.t but NIfTI is not 4D", call. = FALSE)
    }
    template <- img[, , , as.integer(t_idx) + 1L, drop = TRUE]
    return(list(value = as.array(template), template = template))
  }

  stop("unsupported nifti selector in mutate_feature path", call. = FALSE)
}

.nf_rehydrate_nifti_template <- function(template_ref, cache = NULL) {
  if (is.null(template_ref)) {
    return(NULL)
  }

  key <- template_ref$task_key %||% paste(
    template_ref$locator,
    .nf_nifti_selector_key(template_ref$selector) %||% "full",
    sep = "::"
  )
  if (!is.null(cache) && exists(key, envir = cache, inherits = FALSE)) {
    return(cache[[key]])
  }

  img <- RNifti::readNifti(template_ref$locator)
  template <- if (is.null(template_ref$selector)) {
    img
  } else {
    t_idx <- template_ref$selector$index$t
    if (is.null(t_idx)) {
      stop("unsupported nifti selector in mutate_feature path", call. = FALSE)
    }
    img[, , , as.integer(t_idx) + 1L, drop = TRUE]
  }

  if (!is.null(cache)) {
    cache[[key]] <- template
  }
  template
}

.simplify_apply_result <- function(values, names_out) {
  atomic <- vapply(values, function(value) length(value) == 1L && is.atomic(value), logical(1))
  if (all(atomic)) {
    out <- unlist(values, recursive = FALSE, use.names = FALSE)
    names(out) <- names_out
    return(out)
  }

  names(values) <- names_out
  values
}

.nf_normalize_mutate_value <- function(value, n, name) {
  if (is.matrix(value) || is.data.frame(value)) {
    stop("nf_mutate column '", name, "' must yield a scalar vector, not a matrix/data.frame",
         call. = FALSE)
  }

  if (length(value) == 1L) {
    value <- rep(value, n)
  }

  if (length(value) != n) {
    stop(
      "nf_mutate column '", name, "' must yield length 1 or ", n,
      ", got ", length(value),
      call. = FALSE
    )
  }

  if (is.factor(value)) {
    value <- as.character(value)
  }

  if (!(is.atomic(value) || inherits(value, "Date") || inherits(value, "POSIXt"))) {
    stop("nf_mutate column '", name, "' produced an unsupported type", call. = FALSE)
  }

  value
}

.nf_infer_col_schema <- function(value) {
  nullable <- anyNA(value)
  if (inherits(value, "Date")) {
    return(nf_col_schema("date", nullable = nullable))
  }
  if (inherits(value, "POSIXt")) {
    return(nf_col_schema("datetime", nullable = nullable))
  }
  if (is.logical(value)) {
    return(nf_col_schema("bool", nullable = nullable))
  }
  if (is.integer(value)) {
    return(nf_col_schema("int32", nullable = nullable))
  }
  if (is.numeric(value)) {
    return(nf_col_schema("float64", nullable = nullable))
  }
  if (is.character(value)) {
    return(nf_col_schema("string", nullable = nullable))
  }

  stop("could not infer NFTab scalar schema for mutated column", call. = FALSE)
}

#' @rdname nf_summarize
#' @export
nf_summarise <- nf_summarize
