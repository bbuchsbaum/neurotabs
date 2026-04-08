# NIfTI backend adapter
# Resolves ref encodings with backend = "nifti".

.nifti_resolve <- function(locator, selector, logical_schema) {
  if (!file.exists(locator)) {
    stop("NIfTI file not found: ", locator, call. = FALSE)
  }

  # Prefer neuroim2 if available, fall back to RNifti
  if (requireNamespace("neuroim2", quietly = TRUE)) {
    return(.nifti_resolve_neuroim2(locator, selector, logical_schema))
  }
  # nocov start
  if (requireNamespace("RNifti", quietly = TRUE)) {
    return(.nifti_resolve_rnifti(locator, selector, logical_schema))
  }
  # nocov end
  # nocov start
  stop("either 'neuroim2' or 'RNifti' package is required for the nifti backend",
       call. = FALSE)
  # nocov end
}

.nifti_resolve_neuroim2 <- function(locator, selector, logical_schema) {
  if (is.null(selector)) {
    vol <- neuroim2::read_vol(locator)
    return(.neuroim2_to_array(vol))
  }

  # Selector with index.t => read specific volume from 4D
  t_idx <- selector$index$t
  if (!is.null(t_idx)) {
    vec <- neuroim2::read_vec(locator)
    # neuroim2 uses 1-based indexing; spec uses 0-based
    vol <- vec[[t_idx + 1L]]
    return(.neuroim2_to_array(vol))
  }

  stop("unsupported nifti selector: ", jsonlite::toJSON(selector, auto_unbox = TRUE),
       call. = FALSE)
}

# as.array() on a DenseNeuroVol still returns an S4 DenseNeuroVol whose [
# operator does spatial dispatch rather than linear indexing.  Force a plain R
# array so downstream code can use standard linear indexing.
.neuroim2_to_array <- function(vol) {
  array(as.vector(vol), dim = dim(vol))
}

# Native resolver: returns NeuroVol directly (preserves NeuroSpace metadata)
.nifti_native_resolve <- function(locator, selector, logical_schema) {
  # nocov start
  if (!requireNamespace("neuroim2", quietly = TRUE)) {
    stop("neuroim2 is required for native NIfTI resolution (as_array = FALSE)",
         call. = FALSE)
  }
  # nocov end
  if (!file.exists(locator)) {
    stop("NIfTI file not found: ", locator, call. = FALSE)
  }
  if (is.null(selector)) {
    return(neuroim2::read_vol(locator))
  }
  t_idx <- selector$index$t
  if (!is.null(t_idx)) {
    vec <- neuroim2::read_vec(locator)
    return(vec[[t_idx + 1L]])
  }
  stop("unsupported nifti selector: ", jsonlite::toJSON(selector, auto_unbox = TRUE),
       call. = FALSE)
}

.nifti_resolve_rnifti <- function(locator, selector, logical_schema) {
  img <- RNifti::readNifti(locator)

  if (is.null(selector)) {
    return(as.array(img))
  }

  t_idx <- selector$index$t
  if (!is.null(t_idx)) {
    ndim <- length(dim(img))
    if (ndim < 4L) {
      stop("selector specifies index.t but NIfTI is not 4D", call. = FALSE)
    }
    # RNifti: 1-based; spec: 0-based
    vol <- img[, , , t_idx + 1L, drop = TRUE]
    return(as.array(vol))
  }

  stop("unsupported nifti selector: ", jsonlite::toJSON(selector, auto_unbox = TRUE),
       call. = FALSE)
}

# Write functions for the nifti backend

.nifti_write <- function(locator, value, logical_schema, template = NULL, source_ref = NULL) {
  dir.create(dirname(locator), showWarnings = FALSE, recursive = TRUE)
  if (requireNamespace("neuroim2", quietly = TRUE)) {
    return(.nifti_write_neuroim2(locator, value, logical_schema, template, source_ref))
  }
  # nocov start
  if (requireNamespace("RNifti", quietly = TRUE)) {
    return(.nifti_write_rnifti(locator, value, logical_schema, template, source_ref))
  }
  # nocov end
  # nocov start
  stop("either 'neuroim2' or 'RNifti' is required to write NIfTI", call. = FALSE)
  # nocov end
}

.nifti_write_neuroim2 <- function(locator, value, logical_schema, template, source_ref) {
  # Force a plain R numeric array — niftiImage objects are rejected by neuroim2 constructors
  d <- dim(value) %||% length(value)
  plain <- array(as.numeric(value), dim = d)
  space <- if (!is.null(template) && inherits(template, "NeuroSpace")) {
    template
  } else if (!is.null(source_ref) && file.exists(source_ref)) {
    neuroim2::space(neuroim2::read_vol(source_ref))
  } else {
    neuroim2::NeuroSpace(dim = d)
  }
  vol <- neuroim2::NeuroVol(plain, space)
  neuroim2::write_vol(vol, locator)
  invisible(locator)
}

.nifti_write_rnifti <- function(locator, value, logical_schema, template, source_ref) {
  # Force a plain R numeric array — strip niftiImage or other class wrappers
  d <- dim(value) %||% length(value)
  plain <- array(as.numeric(value), dim = d)
  img <- if (!is.null(template)) {
    RNifti::updateNifti(plain, template)
  } else if (!is.null(source_ref) && file.exists(source_ref)) {
    RNifti::updateNifti(plain, RNifti::readNifti(source_ref))
  } else {
    RNifti::asNifti(plain)
  }
  RNifti::writeNifti(img, locator)
  invisible(locator)
}

# Register all backends on package load
# nocov start
.onLoad <- function(libname, pkgname) {
  nf_register_backend("nifti", .nifti_resolve, write_fn = .nifti_write,
                      native_resolve_fn = .nifti_native_resolve)
  nf_register_backend("fmristore-parcel", .fmristore_parcel_resolve)
}
# nocov end
