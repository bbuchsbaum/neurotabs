#' @keywords internal
"_PACKAGE"

#' @useDynLib neurotabs, .registration = TRUE
#' @importFrom Rcpp evalCpp
#' @importFrom data.table fread
#' @importFrom yaml read_yaml write_yaml
#' @importFrom jsonlite fromJSON toJSON
#' @importFrom utils head tail
NULL

#' @importFrom data.table :=
NULL

`%||%` <- function(a, b) if (is.null(a)) b else a

.nf_capture_name <- function(expr, env = parent.frame(), available = NULL, arg = "value") {
  value <- if (is.character(expr)) {
    expr
  } else if (is.symbol(expr)) {
    symbol_name <- as.character(expr)
    if (!is.null(available) && symbol_name %in% available) {
      symbol_name
    } else if (exists(symbol_name, envir = env, inherits = TRUE)) {
      get(symbol_name, envir = env, inherits = TRUE)
    } else {
      symbol_name
    }
  } else {
    eval(expr, envir = env)
  }

  if (!is.character(value) || length(value) != 1L || !nzchar(value)) {
    stop(
      "`", arg, "` must be a single non-empty string or unquoted symbol",
      call. = FALSE
    )
  }

  value
}
