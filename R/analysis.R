# Exploratory analysis helpers

.nf_analysis_numeric_dtypes <- c("bool", "int32", "int64", "uint8", "uint16", "float32", "float64")

#' Exploratory term tests over an NFTab feature
#'
#' Fits fast exploratory term tests over a numeric NFTab feature and returns the
#' result as a new [nftab]. Rows in the output represent generated tests, while
#' result features hold the corresponding statistic maps or vectors.
#'
#' This helper is intentionally narrow. It supports independent-row fixed
#' effects, plus a constrained repeated-measures mode via a single random term
#' of the form `(1 | subject)`. It is not a general mixed-model engine.
#'
#' @param x An [nftab] object.
#' @param feature Feature name to analyze, as a string or unquoted symbol.
#' @param formula Right-hand-side-only formula, for example `~ group * condition`
#'   or `~ group * condition + (1 | subject)`.
#' @param se_feature Optional standard-error feature. Currently not supported.
#' @param contrasts `"auto"` or `list(auto_max_order = 1L/2L)`.
#' @param .progress Show progress while materializing feature values. Default
#'   `FALSE`.
#'
#' @return An [nftab] with one row per generated test and feature maps/vectors
#'   named `stat`, `p_value`, and `estimate` when a 1-df test has a signed
#'   contrast estimate.
#' @export
nf_analyze <- function(x,
                       feature,
                       formula,
                       se_feature = NULL,
                       contrasts = "auto",
                       .progress = FALSE) {
  stopifnot(inherits(x, "nftab"))
  feature <- .nf_capture_name(
    substitute(feature),
    env = parent.frame(),
    available = names(x$manifest$features),
    arg = "feature"
  )
  if (!inherits(formula, "formula")) {
    stop("'formula' must be a formula", call. = FALSE)
  }
  if (length(formula) != 2L) {
    stop("nf_analyze() requires a right-hand-side-only formula", call. = FALSE)
  }
  if (!is.null(se_feature)) {
    stop("se_feature is not implemented in this pass", call. = FALSE)
  }

  contrast_spec <- .nf_parse_analyze_contrasts(contrasts)
  formula_spec <- .nf_parse_analysis_formula(formula)
  subject_col <- .nf_detect_subject_column(x, formula_spec$random_subject)
  feature_data <- .nf_collect_analysis_feature_matrix(x, feature, .progress = .progress)

  if (formula_spec$mode == "fixed" &&
      !is.null(subject_col) &&
      anyDuplicated(x$observations[[subject_col]]) > 0L) {
    stop(
      "repeated subject rows detected; use '(1 | ", subject_col,
      ")' for subject-blocked repeated-measures analysis",
      call. = FALSE
    )
  }

  result <- if (formula_spec$mode == "fixed") {
    .nf_analyze_fixed(
      x,
      feature_data = feature_data,
      fixed_formula = formula_spec$fixed_formula,
      contrast_spec = contrast_spec
    )
  } else {
    .nf_analyze_subject_block(
      x,
      feature_data = feature_data,
      fixed_formula = formula_spec$fixed_formula,
      subject_col = subject_col,
      contrast_spec = contrast_spec
    )
  }

  .nf_pack_analysis_nftab(
    source_ds = x,
    source_feature = feature,
    result_obs = result$observations,
    result_values = result$values
  )
}

.nf_parse_analyze_contrasts <- function(contrasts) {
  if (is.character(contrasts) && length(contrasts) == 1L && identical(contrasts, "auto")) {
    return(list(auto_max_order = 2L))
  }

  if (is.list(contrasts) && length(contrasts)) {
    unknown <- setdiff(names(contrasts), "auto_max_order")
    if (length(unknown)) {
      stop(
        "nf_analyze() currently supports only 'auto' or list(auto_max_order = ...)",
        call. = FALSE
      )
    }

    auto_max_order <- contrasts$auto_max_order %||% 2L
    auto_max_order <- suppressWarnings(as.integer(auto_max_order[[1L]]))
    if (is.na(auto_max_order) || !auto_max_order %in% c(1L, 2L)) {
      stop("auto_max_order must be 1 or 2", call. = FALSE)
    }
    return(list(auto_max_order = auto_max_order))
  }

  stop(
    "nf_analyze() currently supports only contrasts = 'auto' or list(auto_max_order = ...)",
    call. = FALSE
  )
}

.nf_parse_analysis_formula <- function(formula) {
  rhs <- formula[[2L]]
  terms <- .nf_split_formula_sum(rhs)
  random_terms <- Filter(.nf_is_random_term, terms)
  fixed_terms <- Filter(function(term) !.nf_is_random_term(term), terms)

  if (length(random_terms) > 1L) {
    stop("nf_analyze() supports at most one random term", call. = FALSE)
  }

  random_subject <- NULL
  if (length(random_terms) == 1L) {
    random_subject <- .nf_random_subject_name(random_terms[[1L]])
  }

  fixed_formula <- .nf_build_rhs_formula(fixed_terms, env = environment(formula))
  list(
    mode = if (is.null(random_subject)) "fixed" else "subject_block",
    fixed_formula = fixed_formula,
    random_subject = random_subject
  )
}

.nf_split_formula_sum <- function(expr) {
  expr <- .nf_strip_parens(expr)
  if (is.call(expr) && identical(expr[[1L]], as.name("+"))) {
    c(.nf_split_formula_sum(expr[[2L]]), .nf_split_formula_sum(expr[[3L]]))
  } else {
    list(expr)
  }
}

.nf_strip_parens <- function(expr) {
  while (is.call(expr) && identical(expr[[1L]], as.name("("))) {
    expr <- expr[[2L]]
  }
  expr
}

.nf_is_random_term <- function(expr) {
  expr <- .nf_strip_parens(expr)
  is.call(expr) && identical(expr[[1L]], as.name("|"))
}

.nf_random_subject_name <- function(expr) {
  expr <- .nf_strip_parens(expr)
  lhs <- expr[[2L]]
  rhs <- expr[[3L]]

  if (!is.numeric(lhs) || length(lhs) != 1L || !identical(as.numeric(lhs), 1)) {
    stop("nf_analyze() only supports random terms of the form '(1 | subject)'", call. = FALSE)
  }
  if (!is.symbol(rhs)) {
    stop("random subject term must reference a single subject column", call. = FALSE)
  }

  as.character(rhs)
}

.nf_build_rhs_formula <- function(terms, env = parent.frame()) {
  rhs <- if (!length(terms)) {
    1
  } else if (length(terms) == 1L) {
    terms[[1L]]
  } else {
    Reduce(function(a, b) call("+", a, b), terms)
  }

  stats::as.formula(call("~", rhs), env = env)
}

.nf_detect_subject_column <- function(x, explicit_subject = NULL) {
  obs_names <- names(x$observations)
  obs_cols <- x$manifest$observation_columns

  if (!is.null(explicit_subject)) {
    if (!explicit_subject %in% obs_names) {
      stop("subject column '", explicit_subject, "' not found in observations", call. = FALSE)
    }
    return(explicit_subject)
  }

  semantic_hits <- names(obs_cols)[vapply(obs_cols, function(col) identical(col$semantic_role, "subject"), logical(1))]
  if (length(semantic_hits)) {
    return(semantic_hits[[1L]])
  }

  if ("subject" %in% obs_names) {
    return("subject")
  }

  NULL
}

.nf_collect_analysis_feature_matrix <- function(x, feature, .progress = FALSE) {
  feat <- x$manifest$features[[feature]]
  if (is.null(feat)) {
    stop("unknown feature: '", feature, "'", call. = FALSE)
  }
  if (feat$nullable) {
    stop("nf_analyze() does not support nullable features", call. = FALSE)
  }
  if (!feat$logical$dtype %in% .nf_analysis_numeric_dtypes) {
    stop("nf_analyze() requires a numeric feature", call. = FALSE)
  }

  col_plan <- .nf_columns_plan(x, feature)
  if (!is.null(col_plan) && !is.null(col_plan$numeric_matrix)) {
    if (!all(col_plan$row_ok)) {
      stop("nf_analyze() requires non-missing feature values for all rows", call. = FALSE)
    }
    return(list(
      matrix = col_plan$numeric_matrix,
      logical = feat$logical,
      storage = "columns"
    ))
  }

  if (!identical(feat$logical$kind, "volume")) {
    stop(
      "nf_analyze() currently supports columns-encoded vectors and NIfTI-backed volume features",
      call. = FALSE
    )
  }

  support <- x$manifest$supports[[feat$logical$support_ref]]
  if (is.null(support) || is.null(support$grid_id)) {
    stop("volume analysis requires a declared volume support with grid_id", call. = FALSE)
  }

  plan <- .nf_nifti_plan(x, feature)
  if (is.null(plan)) {
    stop(
      "nf_analyze() currently supports only NIfTI-backed volume features for ref-encoded inputs",
      call. = FALSE
    )
  }

  task_values <- .nf_eval_nifti_tasks(
    plan,
    function(img, selector) {
      arr <- .nifti_extract_cached(img, selector)
      list(data = as.numeric(arr), dim = dim(arr))
    }
  )

  first_dim <- NULL
  n_rows <- nrow(x$observations)
  n_values <- NULL
  out <- NULL
  for (entry in plan) {
    cached <- task_values[[entry$task_key]]
    if (is.null(first_dim)) {
      first_dim <- cached$dim
      n_values <- length(cached$data)
      out <- matrix(NA_real_, nrow = n_rows, ncol = n_values)
    }
    if (!identical(first_dim, cached$dim)) {
      stop("nf_analyze() requires feature values with identical shapes", call. = FALSE)
    }
    out[entry$row_index, ] <- cached$data
  }

  list(
    matrix = out,
    logical = feat$logical,
    storage = "nifti"
  )
}

.nf_prepare_model_data <- function(x, formula, extra_cols = character()) {
  vars <- unique(c(all.vars(formula), extra_cols))
  vars <- vars[vars %in% names(x$observations)]
  data <- x$observations[, vars, drop = FALSE]

  for (nm in names(data)) {
    schema <- x$manifest$observation_columns[[nm]]
    value <- data[[nm]]
    if (is.character(value)) {
      levels <- schema$levels %||% unique(value)
      data[[nm]] <- factor(value, levels = levels)
    } else if (is.factor(value) && !is.null(schema$levels)) {
      data[[nm]] <- factor(as.character(value), levels = schema$levels)
    }
  }

  data
}

.nf_model_matrix <- function(formula, data, sum_contrast_vars = NULL) {
  factors <- stats::model.frame(formula, data = data, na.action = stats::na.fail)
  mm_terms <- stats::terms(formula, data = factors)

  factor_names <- names(factors)[vapply(factors, is.factor, logical(1))]
  if (is.null(sum_contrast_vars)) {
    sum_contrast_vars <- factor_names
  }
  contrasts_arg <- list()
  for (nm in factor_names) {
    n_levels <- nlevels(factors[[nm]])
    if (n_levels < 2L) {
      stop("factor '", nm, "' must have at least 2 levels for analysis", call. = FALSE)
    }
    if (nm %in% sum_contrast_vars) {
      contrasts_arg[[nm]] <- stats::contr.sum(n_levels)
    }
  }

  xmat <- stats::model.matrix(mm_terms, data = factors, contrasts.arg = contrasts_arg)
  list(
    data = factors,
    terms = mm_terms,
    matrix = xmat
  )
}

.nf_fit_ols_multiresponse <- function(X, Y) {
  qr_fit <- qr(X)
  if (qr_fit$rank < ncol(X)) {
    stop("analysis design matrix is rank-deficient", call. = FALSE)
  }

  coefficients <- qr.coef(qr_fit, Y)
  if (is.vector(coefficients)) {
    coefficients <- matrix(coefficients, ncol = 1L)
  }

  fitted <- qr.fitted(qr_fit, Y)
  residuals <- Y - fitted
  rss <- colSums(residuals^2)
  df_resid <- nrow(X) - qr_fit$rank
  if (df_resid < 1L) {
    stop("analysis requires positive residual degrees of freedom", call. = FALSE)
  }

  xtx_inv <- chol2inv(qr.R(qr_fit))
  list(
    coefficients = coefficients,
    residuals = residuals,
    rss = rss,
    sigma2 = rss / df_resid,
    df_resid = df_resid,
    xtx_inv = xtx_inv,
    nobs = nrow(X)
  )
}

.nf_term_metadata <- function(terms_obj, data) {
  labels <- attr(terms_obj, "term.labels")
  if (!length(labels)) {
    return(list())
  }

  assign <- attr(stats::model.matrix(terms_obj, data = data), "assign")
  assign <- assign[-1L]
  col_ids <- seq_len(length(assign)) + 1L
  term_order <- attr(terms_obj, "order")
  factor_table <- attr(terms_obj, "factors")

  out <- vector("list", length(labels))
  names(out) <- labels
  for (i in seq_along(labels)) {
    vars <- rownames(factor_table)[factor_table[, i] > 0]
    out[[i]] <- list(
      label = labels[[i]],
      order = term_order[[i]],
      vars = vars,
      cols = col_ids[assign == i]
    )
  }
  out
}

.nf_term_scale <- function(term_info, data) {
  scale <- 1
  binary_count <- 0L
  for (nm in term_info$vars) {
    value <- data[[nm]]
    if (is.factor(value) && nlevels(value) == 2L) {
      scale <- scale * 2
      binary_count <- binary_count + 1L
    }
  }
  scale * if ((binary_count %% 2L) == 1L) -1 else 1
}

.nf_term_test_from_fit <- function(fit, term_info, data, mode, weighted = FALSE) {
  cols <- term_info$cols
  q <- length(cols)
  p <- ncol(fit$coefficients)
  cmat <- matrix(0, nrow = q, ncol = nrow(fit$xtx_inv))
  for (i in seq_along(cols)) {
    cmat[i, cols[[i]]] <- 1
  }

  if (q == 1L) {
    scale <- .nf_term_scale(term_info, data)
    cmat[1L, cols[[1L]]] <- scale
    est <- as.numeric(cmat %*% fit$coefficients)
    v <- as.numeric(cmat %*% fit$xtx_inv %*% t(cmat))
    stderr <- sqrt(pmax(fit$sigma2 * v, 0))
    stat <- est / stderr
    pval <- 2 * stats::pt(-abs(stat), df = fit$df_resid)
    return(list(
      obs = data.frame(
        term = term_info$label,
        test_type = "omnibus",
        stat_kind = "t",
        df_num = 1L,
        df_den = as.integer(fit$df_resid),
        mode = mode,
        weighted = weighted,
        contrast_spec = jsonlite::toJSON(
          list(kind = "auto", term = term_info$label, order = term_info$order),
          auto_unbox = TRUE
        ),
        stringsAsFactors = FALSE
      ),
      values = list(
        stat = stat,
        p_value = pval,
        estimate = est
      )
    ))
  }

  cb <- cmat %*% fit$coefficients
  middle <- solve(cmat %*% fit$xtx_inv %*% t(cmat))
  quad <- colSums(cb * (middle %*% cb))
  stat <- (quad / q) / fit$sigma2
  pval <- stats::pf(stat, df1 = q, df2 = fit$df_resid, lower.tail = FALSE)
  list(
    obs = data.frame(
      term = term_info$label,
      test_type = "omnibus",
      stat_kind = "f",
      df_num = as.integer(q),
      df_den = as.integer(fit$df_resid),
      mode = mode,
      weighted = weighted,
      contrast_spec = jsonlite::toJSON(
        list(kind = "auto", term = term_info$label, order = term_info$order),
        auto_unbox = TRUE
      ),
      stringsAsFactors = FALSE
    ),
    values = list(
      stat = stat,
      p_value = pval,
      estimate = rep(NA_real_, p)
    )
  )
}

.nf_bind_test_results <- function(results) {
  results <- Filter(Negate(is.null), results)
  if (!length(results)) {
    stop("no analysis terms selected by the requested contrast rule", call. = FALSE)
  }

  obs <- do.call(rbind, lapply(results, `[[`, "obs"))
  obs$.row_id <- paste0(".t", seq_len(nrow(obs)))
  obs$test_id <- make.unique(obs$term, sep = "_")
  obs <- obs[, c(
    ".row_id", "test_id", "term", "test_type", "stat_kind",
    "df_num", "df_den", "mode", "weighted", "contrast_spec"
  )]
  rownames(obs) <- NULL

  feature_names <- unique(unlist(lapply(results, function(x) names(x$values)), use.names = FALSE))
  value_mats <- vector("list", length(feature_names))
  names(value_mats) <- feature_names

  for (feature_name in feature_names) {
    rows <- lapply(results, function(res) res$values[[feature_name]])
    value_mats[[feature_name]] <- do.call(rbind, rows)
  }

  list(observations = obs, values = value_mats)
}

.nf_analyze_fixed <- function(x, feature_data, fixed_formula, contrast_spec) {
  model_data <- .nf_prepare_model_data(x, fixed_formula)
  mm <- .nf_model_matrix(fixed_formula, model_data)
  fit <- .nf_fit_ols_multiresponse(mm$matrix, feature_data$matrix)
  term_info <- .nf_term_metadata(mm$terms, mm$data)

  selected <- Filter(function(info) info$order <= contrast_spec$auto_max_order, term_info)
  results <- lapply(selected, .nf_term_test_from_fit, fit = fit, data = mm$data, mode = "fixed")
  .nf_bind_test_results(results)
}

.nf_analyze_subject_block <- function(x, feature_data, fixed_formula, subject_col, contrast_spec) {
  if (is.null(subject_col)) {
    stop("subject-blocked mode requires a subject column", call. = FALSE)
  }

  model_data <- .nf_prepare_model_data(x, fixed_formula, extra_cols = subject_col)
  if (!subject_col %in% names(model_data)) {
    stop("subject column '", subject_col, "' not found in observations", call. = FALSE)
  }
  model_data[[subject_col]] <- factor(model_data[[subject_col]], levels = unique(model_data[[subject_col]]))

  fixed_vars <- setdiff(all.vars(fixed_formula), subject_col)
  if (!length(fixed_vars) || length(fixed_vars) > 2L) {
    stop(
      "subject-blocked mode supports one within-subject factor and optionally one between-subject factor",
      call. = FALSE
    )
  }
  if (!all(vapply(model_data[fixed_vars], is.factor, logical(1)))) {
    stop("subject-blocked mode currently supports factor predictors only", call. = FALSE)
  }

  within_flags <- vapply(fixed_vars, function(var) {
    counts <- tapply(as.character(model_data[[var]]), model_data[[subject_col]], function(values) {
      length(unique(values))
    })
    any(counts > 1L)
  }, logical(1))

  within_vars <- fixed_vars[within_flags]
  between_vars <- fixed_vars[!within_flags]

  if (length(within_vars) != 1L || length(between_vars) > 1L) {
    stop(
      "subject-blocked mode requires exactly one within-subject factor and at most one between-subject factor",
      call. = FALSE
    )
  }

  within_var <- within_vars[[1L]]
  between_var <- if (length(between_vars)) between_vars[[1L]] else NULL
  within_levels <- levels(model_data[[within_var]])
  if (length(within_levels) != 2L) {
    stop(
      "the current subject-blocked implementation supports a binary within-subject factor only",
      call. = FALSE
    )
  }

  if (!is.null(between_var)) {
    varying_between <- tapply(as.character(model_data[[between_var]]), model_data[[subject_col]], function(values) {
      length(unique(values))
    })
    if (any(varying_between != 1L)) {
      stop("between-subject factor varies within subject", call. = FALSE)
    }
  }

  group_keys <- data.frame(row.names = seq_len(nrow(model_data)), stringsAsFactors = FALSE)
  group_keys[[subject_col]] <- model_data[[subject_col]]
  group_keys[[within_var]] <- model_data[[within_var]]
  if (!is.null(between_var)) {
    group_keys[[between_var]] <- model_data[[between_var]]
  }
  cell_id <- interaction(group_keys, drop = TRUE, lex.order = TRUE)
  y_cell <- rowsum(feature_data$matrix, group = cell_id, reorder = FALSE)
  cell_n <- as.integer(table(cell_id))
  y_cell <- y_cell / cell_n

  cell_design <- unique(group_keys)
  rownames(cell_design) <- rownames(y_cell)

  expected_per_subject <- nlevels(model_data[[within_var]])
  actual_per_subject <- table(cell_design[[subject_col]])
  if (any(actual_per_subject != expected_per_subject)) {
    stop("subject-blocked mode requires a balanced, complete within-subject design", call. = FALSE)
  }

  results <- list()
  term_labels <- attr(stats::terms(fixed_formula), "term.labels")

  if (!is.null(between_var) && contrast_spec$auto_max_order >= 1L && between_var %in% term_labels) {
    subject_levels <- unique(as.character(cell_design[[subject_col]]))
    subject_index <- match(as.character(cell_design[[subject_col]]), subject_levels)
    y_subject <- rowsum(y_cell, group = subject_index, reorder = FALSE) / expected_per_subject
    subject_design <- data.frame(subject = factor(subject_levels, levels = subject_levels), stringsAsFactors = FALSE)
    subject_design[[between_var]] <- factor(
      tapply(as.character(cell_design[[between_var]]), cell_design[[subject_col]], function(values) values[[1L]])[subject_levels],
      levels = levels(model_data[[between_var]])
    )
    between_formula <- stats::as.formula(paste("~", between_var), env = environment(fixed_formula))
    between_mm <- .nf_model_matrix(between_formula, subject_design, sum_contrast_vars = between_var)
    between_fit <- .nf_fit_ols_multiresponse(between_mm$matrix, y_subject)
    between_info <- .nf_term_metadata(between_mm$terms, between_mm$data)[[between_var]]
    results[[length(results) + 1L]] <- .nf_term_test_from_fit(
      between_fit,
      between_info,
      data = between_mm$data,
      mode = "subject_block"
    )
  }

  ord <- order(
    as.character(cell_design[[subject_col]]),
    match(as.character(cell_design[[within_var]]), within_levels)
  )
  cell_design <- cell_design[ord, , drop = FALSE]
  y_cell <- y_cell[ord, , drop = FALSE]

  subject_levels <- unique(as.character(cell_design[[subject_col]]))
  score_mat <- matrix(NA_real_, nrow = length(subject_levels), ncol = ncol(y_cell))
  between_values <- if (!is.null(between_var)) character(length(subject_levels)) else NULL

  for (i in seq_along(subject_levels)) {
    idx <- which(as.character(cell_design[[subject_col]]) == subject_levels[[i]])
    if (length(idx) != 2L) {
      stop("subject-blocked mode requires exactly one row per subject x within-factor cell", call. = FALSE)
    }

    level_idx <- match(as.character(cell_design[[within_var]][idx]), within_levels)
    if (anyNA(level_idx) || !setequal(level_idx, c(1L, 2L))) {
      stop("subject-blocked mode requires both within-subject levels for every subject", call. = FALSE)
    }

    low <- idx[which(level_idx == 1L)]
    high <- idx[which(level_idx == 2L)]
    score_mat[i, ] <- y_cell[high, ] - y_cell[low, ]

    if (!is.null(between_var)) {
      between_values[[i]] <- as.character(cell_design[[between_var]][low])
    }
  }

  if (contrast_spec$auto_max_order >= 1L && within_var %in% term_labels) {
    results[[length(results) + 1L]] <- .nf_one_sample_t_result(
      score_mat,
      term = within_var,
      mode = "subject_block"
    )
  }

  interaction_term <- NULL
  if (!is.null(between_var)) {
    interaction_term <- term_labels[grepl(":", term_labels) &
      vapply(strsplit(term_labels[grepl(":", term_labels)], ":", fixed = TRUE), function(parts) {
        setequal(parts, c(between_var, within_var))
      }, logical(1))]
    interaction_term <- interaction_term[[1L]] %||% NULL
  }

  if (!is.null(interaction_term) && contrast_spec$auto_max_order >= 2L) {
    interaction_design <- data.frame(row.names = seq_along(between_values), stringsAsFactors = FALSE)
    interaction_design[[between_var]] <- factor(between_values, levels = levels(model_data[[between_var]]))
    interaction_formula <- stats::as.formula(paste("~", between_var), env = environment(fixed_formula))
    interaction_mm <- .nf_model_matrix(interaction_formula, interaction_design, sum_contrast_vars = between_var)
    interaction_fit <- .nf_fit_ols_multiresponse(interaction_mm$matrix, score_mat)
    interaction_info <- .nf_term_metadata(interaction_mm$terms, interaction_mm$data)[[between_var]]
    interaction_result <- .nf_term_test_from_fit(
      interaction_fit,
      interaction_info,
      data = interaction_mm$data,
      mode = "subject_block"
    )
    interaction_result$obs$term <- interaction_term
    results[[length(results) + 1L]] <- interaction_result
  }

  .nf_bind_test_results(results)
}

.nf_one_sample_t_result <- function(Y, term, mode) {
  n <- nrow(Y)
  if (n < 2L) {
    stop("analysis requires at least 2 subjects for subject-blocked inference", call. = FALSE)
  }

  est <- colMeans(Y)
  sum_vec <- colSums(Y)
  sumsq <- colSums(Y * Y)
  var_vec <- (sumsq - (sum_vec * sum_vec) / n) / (n - 1L)
  stderr <- sqrt(pmax(var_vec, 0)) / sqrt(n)
  stat <- est / stderr
  pval <- 2 * stats::pt(-abs(stat), df = n - 1L)

  list(
    obs = data.frame(
      term = term,
      test_type = "omnibus",
      stat_kind = "t",
      df_num = 1L,
      df_den = as.integer(n - 1L),
      mode = mode,
      weighted = FALSE,
      contrast_spec = jsonlite::toJSON(
        list(kind = "auto", term = term, order = 1L),
        auto_unbox = TRUE
      ),
      stringsAsFactors = FALSE
    ),
    values = list(
      stat = stat,
      p_value = pval,
      estimate = est
    )
  )
}

.nf_pack_analysis_nftab <- function(source_ds, source_feature, result_obs, result_values) {
  source_feat <- source_ds$manifest$features[[source_feature]]
  if (length(source_feat$logical$axes) == 1L) {
    return(.nf_pack_analysis_columns(source_ds, source_feat, result_obs, result_values))
  }
  .nf_pack_analysis_nifti(source_ds, source_feat, result_obs, result_values)
}

.nf_analysis_obs_schemas <- function(result_obs) {
  list(
    .row_id = nf_col_schema("string", nullable = FALSE, semantic_role = "row_id"),
    test_id = nf_col_schema("string", nullable = FALSE, semantic_role = "contrast"),
    term = nf_col_schema("string", nullable = FALSE),
    test_type = nf_col_schema("string", nullable = FALSE),
    stat_kind = nf_col_schema("string", nullable = FALSE),
    df_num = nf_col_schema("int32", nullable = FALSE),
    df_den = nf_col_schema("int32", nullable = FALSE),
    mode = nf_col_schema("string", nullable = FALSE),
    weighted = nf_col_schema("bool", nullable = FALSE),
    contrast_spec = nf_col_schema("json", nullable = FALSE)
  )
}

.nf_analysis_result_logical <- function(source_logical) {
  source_logical$dtype <- "float64"
  source_logical
}

.nf_pack_analysis_columns <- function(source_ds, source_feat, result_obs, result_values) {
  new_obs <- result_obs
  obs_cols <- .nf_analysis_obs_schemas(result_obs)
  feature_defs <- list()
  logical_template <- .nf_analysis_result_logical(source_feat$logical)

  for (feature_name in names(result_values)) {
    mat <- result_values[[feature_name]]
    col_names <- paste0(feature_name, "_", seq_len(ncol(mat)))
    for (j in seq_len(ncol(mat))) {
      new_obs[[col_names[[j]]]] <- as.numeric(mat[, j])
      obs_cols[[col_names[[j]]]] <- nf_col_schema("float64", nullable = anyNA(new_obs[[col_names[[j]]]]))
    }
    feature_defs[[feature_name]] <- nf_feature(
      logical = logical_template,
      encodings = list(nf_columns_encoding(col_names)),
      nullable = anyNA(mat)
    )
  }

  manifest <- nf_manifest(
    spec_version = source_ds$manifest$spec_version,
    dataset_id = paste0(source_ds$manifest$dataset_id, "-analysis"),
    row_id = ".row_id",
    observation_axes = "test_id",
    observation_columns = obs_cols,
    features = feature_defs,
    primary_feature = "stat"
  )

  nftab(manifest = manifest, observations = new_obs)
}

.nf_pack_analysis_nifti <- function(source_ds, source_feat, result_obs, result_values) {
  if (!requireNamespace("RNifti", quietly = TRUE)) {
    stop("RNifti is required for volumetric analysis outputs", call. = FALSE)
  }

  new_obs <- result_obs
  obs_cols <- .nf_analysis_obs_schemas(result_obs)
  feature_defs <- list()
  logical_template <- .nf_analysis_result_logical(source_feat$logical)
  writer <- .get_backend_writer("nifti")
  out_dir <- tempfile("nftab_analysis_", tmpdir = tempdir())
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  resource_rows <- list()
  for (feature_name in names(result_values)) {
    mat <- result_values[[feature_name]]
    res_col <- paste0(feature_name, "_res")
    new_obs[[res_col]] <- NA_character_
    obs_cols[[res_col]] <- nf_col_schema("string", nullable = TRUE)

    for (i in seq_len(nrow(mat))) {
      row_value <- mat[i, ]
      if (all(is.na(row_value))) {
        next
      }

      rid <- paste0(feature_name, "_", i)
      loc <- file.path(out_dir, paste0(rid, ".nii.gz"))
      writer(loc, array(as.numeric(row_value), dim = logical_template$shape), logical_template)
      new_obs[[res_col]][i] <- rid
      resource_rows[[length(resource_rows) + 1L]] <- data.frame(
        resource_id = rid,
        backend = "nifti",
        locator = basename(loc),
        checksum = paste0("md5:", digest::digest(file = loc, algo = "md5", serialize = FALSE)),
        stringsAsFactors = FALSE
      )
    }

    feature_defs[[feature_name]] <- nf_feature(
      logical = logical_template,
      encodings = list(nf_ref_encoding(resource_id = nf_col(res_col))),
      nullable = any(is.na(new_obs[[res_col]]))
    )
  }

  resources <- if (length(resource_rows)) do.call(rbind, resource_rows) else NULL
  manifest <- nf_manifest(
    spec_version = source_ds$manifest$spec_version,
    dataset_id = paste0(source_ds$manifest$dataset_id, "-analysis"),
    row_id = ".row_id",
    observation_axes = "test_id",
    observation_columns = obs_cols,
    features = feature_defs,
    supports = source_ds$manifest$supports,
    resources_path = "resources.csv",
    primary_feature = "stat"
  )

  nftab(manifest = manifest, observations = new_obs, resources = resources, .root = out_dir)
}
