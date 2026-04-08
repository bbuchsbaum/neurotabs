# Feature encoding constructors
# Corresponds to NFTab spec sections 9-10.

# -- Value source helpers ------------------------------------------------------

#' Create a column reference (ValueSource)
#'
#' @param column_name Name of the observation table column.
#' @return A list with class `nf_column_ref`.
#' @export
nf_col <- function(column_name) {
  stopifnot(is.character(column_name), length(column_name) == 1L, nzchar(column_name))
  structure(list(column = column_name), class = "nf_column_ref")
}

.is_column_ref <- function(x) {
  inherits(x, "nf_column_ref") || (is.list(x) && !is.null(x$column))
}

#' Resolve a ValueSource for a given row
#' @keywords internal
resolve_value_source <- function(source, row) {
  if (.is_column_ref(source)) {
    row[[source$column]]
  } else {
    source
  }
}

# -- ref encoding --------------------------------------------------------------

#' Create a ref encoding
#'
#' Declares that a feature is stored in an external resource, resolved via a
#' backend adapter.
#'
#' @param backend Backend identifier or [nf_col] reference.
#' @param locator Path/URI or [nf_col] reference.
#' @param selector Optional selector (literal or [nf_col] reference).
#' @param resource_id Optional resource registry ID (literal or [nf_col] reference).
#' @param checksum Optional checksum (literal or [nf_col] reference).
#'
#' @return An `nf_encoding` object with `type = "ref"`.
#' @export
nf_ref_encoding <- function(backend = NULL,
                            locator = NULL,
                            selector = NULL,
                            resource_id = NULL,
                            checksum = NULL) {
  has_rid <- !is.null(resource_id)
  has_bl <- !is.null(backend) && !is.null(locator)
  if (!has_rid && !has_bl) {
    stop("ref encoding must provide either resource_id, or both backend and locator",
         call. = FALSE)
  }

  structure(
    list(
      type = "ref",
      binding = list(
        resource_id = resource_id,
        backend = backend,
        locator = locator,
        selector = selector,
        checksum = checksum
      )
    ),
    class = "nf_encoding"
  )
}

# -- columns encoding ----------------------------------------------------------

#' Create a columns encoding
#'
#' Declares that a 1D feature is stored as an ordered set of scalar columns
#' in the observation table.
#'
#' @param columns Character vector of column names, in order.
#'
#' @return An `nf_encoding` object with `type = "columns"`.
#' @export
nf_columns_encoding <- function(columns) {
  stopifnot(is.character(columns), length(columns) >= 1L)
  structure(
    list(
      type = "columns",
      binding = list(columns = columns)
    ),
    class = "nf_encoding"
  )
}

#' @export
print.nf_encoding <- function(x, ...) {
  if (x$type == "ref") {
    cat("<nf_encoding> ref\n")
    if (!is.null(x$binding$resource_id)) {
      cat("  resource_id:", .fmt_vs(x$binding$resource_id), "\n")
    } else {
      cat("  backend:", .fmt_vs(x$binding$backend), "\n")
      cat("  locator:", .fmt_vs(x$binding$locator), "\n")
    }
    if (!is.null(x$binding$selector)) {
      cat("  selector:", .fmt_vs(x$binding$selector), "\n")
    }
  } else if (x$type == "columns") {
    cat("<nf_encoding> columns [", length(x$binding$columns), "]\n")
    cat("  columns:", paste(utils::head(x$binding$columns, 5), collapse = ", "))
    if (length(x$binding$columns) > 5) cat(", ...")
    cat("\n")
  }
  invisible(x)
}

.fmt_vs <- function(vs) {
  if (.is_column_ref(vs)) {
    paste0("{column: ", vs$column, "}")
  } else if (is.character(vs)) {
    vs
  } else {
    deparse(vs, width.cutoff = 60L)
  }
}

# -- Applicability checks -----------------------------------------------------

#' Check if an encoding is applicable for a given row
#' @keywords internal
encoding_applicable <- function(encoding, row) {
  if (encoding$type == "ref") {
    b <- encoding$binding
    rid_val <- resolve_value_source(b$resource_id, row)
    backend_val <- resolve_value_source(b$backend, row)
    locator_val <- resolve_value_source(b$locator, row)
    has_rid <- !is.null(rid_val) && !is.na(rid_val)
    has_backend_locator <- !is.null(backend_val) && !is.na(backend_val) &&
      !is.null(locator_val) && !is.na(locator_val)
    return(has_rid || has_backend_locator)
  }

  if (encoding$type == "columns") {
    cols <- encoding$binding$columns
    return(all(cols %in% names(row)) &&
           all(!is.na(row[cols])))
  }

  FALSE
}
