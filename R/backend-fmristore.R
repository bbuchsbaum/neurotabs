# fmristore-parcel backend adapter
#
# Resolves ref encodings with backend = "fmristore-parcel".
# Supports both single-scan (H5ParcellatedScanSummary / H5ParcellatedScan) and
# multi-scan (H5ParcellatedMultiScan) files, detected via the root HDF5
# `fmristore_class` attribute.
#
# Selector fields:
#   row_index  (required) – 1-based row index into the T×K summary matrix
#   scan_name  (required for multi-scan files, ignored for single-scan)

.fmristore_parcel_resolve <- function(locator, selector, logical_schema) {
  if (!requireNamespace("fmristore", quietly = TRUE)) {
    stop("'fmristore' package is required for the 'fmristore-parcel' backend",
         call. = FALSE)
  }

  row_index <- selector$row_index
  if (is.null(row_index)) {
    stop("fmristore-parcel selector must include 'row_index'", call. = FALSE)
  }

  obj <- fmristore::read_dataset(locator)
  on.exit(tryCatch(close(obj), error = function(e) NULL), add = TRUE)

  if (inherits(obj, "H5ParcellatedMultiScan")) {
    scan_name <- selector$scan_name
    if (is.null(scan_name)) {
      stop(
        "fmristore-parcel selector must include 'scan_name' for multi-scan files",
        call. = FALSE
      )
    }
    scan <- obj@runs[[scan_name]]
    if (is.null(scan)) {
      stop("scan '", scan_name, "' not found in '", locator, "'", call. = FALSE)
    }
  } else if (inherits(obj, "H5ParcellatedArray")) {
    scan <- obj
  } else {
    stop(
      "'fmristore-parcel' backend requires H5ParcellatedScanSummary, ",
      "H5ParcellatedScan, or H5ParcellatedMultiScan; got: ",
      paste(class(obj), collapse = ", "),
      call. = FALSE
    )
  }

  as.numeric(scan[row_index, ])
}

# Registration is called from .onLoad in backend-nifti.R
