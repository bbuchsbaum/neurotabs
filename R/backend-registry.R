# Backend adapter registry
# Adapters know how to materialize ref encodings for specific backends.

.backend_registry <- new.env(parent = emptyenv())

#' Register a backend adapter
#'
#' @param name Backend identifier (e.g., `"nifti"`, `"hdf5"`).
#' @param resolve_fn Function with signature
#'   `function(locator, selector, logical_schema)` returning the resolved
#'   array/value.
#' @param detect_fn Optional function `function(locator)` returning `TRUE`
#'   if this backend can handle the given locator.
#' @param write_fn Optional function with signature
#'   `function(locator, value, logical_schema, template = NULL, source_ref = NULL)`
#'   that materializes a derived feature value to `locator`.
#' @param native_resolve_fn Optional function with the same signature as
#'   `resolve_fn` but returning a native R object (e.g., a `NeuroVol`) rather
#'   than a plain array.  Used by [nf_resolve()] when `as_array = FALSE`.
#'
#' @export
nf_register_backend <- function(name, resolve_fn, detect_fn = NULL,
                                write_fn = NULL, native_resolve_fn = NULL) {
  stopifnot(
    is.character(name), length(name) == 1L, nzchar(name),
    is.function(resolve_fn)
  )
  if (!is.null(write_fn)) {
    stopifnot(is.function(write_fn))
  }
  if (!is.null(native_resolve_fn)) {
    stopifnot(is.function(native_resolve_fn))
  }
  .backend_registry[[name]] <- list(
    name = name,
    resolve_fn = resolve_fn,
    detect_fn = detect_fn,
    write_fn = write_fn,
    native_resolve_fn = native_resolve_fn
  )
  invisible(name)
}

#' List registered backends
#' @return Character vector of backend names.
#' @export
nf_backends <- function() {
  ls(.backend_registry)
}

#' @keywords internal
.get_backend <- function(name) {
  .backend_registry[[name]]
}

#' @keywords internal
.get_backend_writer <- function(name) {
  backend <- .get_backend(name)
  if (is.null(backend)) {
    return(NULL)
  }
  backend$write_fn
}
