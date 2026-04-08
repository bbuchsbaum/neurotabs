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
