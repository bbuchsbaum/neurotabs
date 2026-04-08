# Ingestion helpers: build nftab objects from common neuroimaging data sources.

# -- Internal helpers ----------------------------------------------------------

# Ensure the design data.frame has a row_id column.
.ensure_row_id <- function(design, col = "row_id") {
  if (col %in% names(design)) return(design)
  n <- nrow(design)
  design[[col]] <- sprintf("obs_%0*d", nchar(n), seq_len(n))
  design[c(col, setdiff(names(design), col))]
}

# Infer nf_col_schema for each column of a data.frame.
.design_to_col_schemas <- function(design) {
  lapply(design, function(col) {
    if (is.logical(col))                  nf_col_schema("bool")
    else if (is.integer(col))             nf_col_schema("int32")
    else if (is.numeric(col))             nf_col_schema("float64")
    else                                  nf_col_schema("string")
  })
}

# Compute per-parcel metadata (n_voxels, grid centroids) from an fmristore
# H5ParcellatedArray or H5ParcellatedMultiScan object.
.compute_parcel_meta <- function(obj) {
  if (inherits(obj, "H5ParcellatedMultiScan")) {
    clvol <- obj@clusters
    msk   <- obj@mask
  } else {
    clvol <- obj@clusters
    msk   <- obj@mask
  }

  d        <- dim(msk)
  msk_arr  <- array(as.vector(msk), dim = d)
  mask_lin <- which(as.vector(msk_arr) > 0)

  # 1-based grid coords for each masked voxel (column-major)
  xi <- ((mask_lin - 1L) %% d[1L]) + 1L
  yi <- (((mask_lin - 1L) %/% d[1L]) %% d[2L]) + 1L
  zi <- ((mask_lin - 1L) %/% (d[1L] * d[2L])) + 1L

  # Cluster assignments (non-zero where parcellated)
  cl_arr     <- array(as.vector(clvol), dim = d)
  cl_ids_all <- as.integer(cl_arr[mask_lin])

  uid <- sort(unique(cl_ids_all[cl_ids_all > 0L]))

  centroids <- lapply(uid, function(k) {
    idx <- cl_ids_all == k
    c(x = mean(xi[idx]), y = mean(yi[idx]), z = mean(zi[idx]))
  })

  data.frame(
    index      = uid,
    label      = as.character(uid),
    n_voxels   = vapply(uid, function(k) sum(cl_ids_all == k), integer(1L)),
    x_centroid = vapply(centroids, `[[`, numeric(1L), "x"),
    y_centroid = vapply(centroids, `[[`, numeric(1L), "y"),
    z_centroid = vapply(centroids, `[[`, numeric(1L), "z"),
    stringsAsFactors = FALSE
  )
}

# Try to get a space name from an fmristore object.
.infer_fmristore_space <- function(obj) {
  tryCatch(
    {
      sp <- if (inherits(obj, "H5ParcellatedMultiScan")) {
        neuroim2::space(obj@mask)
      } else {
        neuroim2::space(obj@mask)
      }
      # neuroim2 NeuroSpace doesn't carry a named space string; return unknown
      "unknown"
    },
    error = function(e) "unknown"
  )
}

# -- nf_ingest_parcel_h5 -------------------------------------------------------

#' Ingest a parcellated fmristore HDF5 file into an nftab
#'
#' Builds an [nftab] from an `H5ParcellatedScanSummary`, `H5ParcellatedScan`,
#' or `H5ParcellatedMultiScan` file.  One nftab row is created per observation
#' (timepoint / volume), with a ref encoding that reads a single row of the
#' `T × K` summary matrix via the `"fmristore-parcel"` backend.
#'
#' @param path Path to the HDF5 file.
#' @param design A data.frame with one row per observation (T rows).  Any
#'   columns whose names match `"subject"`, `"session"`, `"run"`, or
#'   `"condition"` are used as observation axes.
#' @param scan_name For multi-scan files: which scan to use.  Defaults to the
#'   first scan.  Ignored for single-scan files.
#' @param feature Name to give the parcel-signal feature.  Default
#'   `"parcel_signal"`.
#' @param dataset_id Dataset identifier for the manifest.  Derived from the
#'   filename by default.
#' @param space Named reference space (e.g. `"MNI152NLin2009cAsym"`).
#'   Default `"unknown"`.
#' @param output_dir Optional directory where the `parcel_map.tsv` will be
#'   written.  If `NULL`, parcel metadata is embedded as in-memory only (not
#'   written to disk).
#'
#' @return An [nftab] object with ref encodings pointing to `path`.
#' @export
nf_ingest_parcel_h5 <- function(path,
                                 design,
                                 scan_name  = NULL,
                                 feature    = "parcel_signal",
                                 dataset_id = NULL,
                                 space      = "unknown",
                                 output_dir = NULL) {
  if (!requireNamespace("fmristore", quietly = TRUE)) {
    stop("'fmristore' package is required for nf_ingest_parcel_h5()", call. = FALSE)
  }
  stopifnot(is.data.frame(design))
  path <- normalizePath(path, mustWork = TRUE)

  obj <- fmristore::read_dataset(path)
  on.exit(tryCatch(close(obj), error = function(e) NULL), add = TRUE)

  is_multi <- inherits(obj, "H5ParcellatedMultiScan")
  if (is_multi) {
    scan_name <- scan_name %||% names(obj@runs)[1L]
    scan      <- obj@runs[[scan_name]]
    if (is.null(scan)) {
      stop("scan '", scan_name, "' not found in '", path, "'", call. = FALSE)
    }
  } else {
    scan      <- obj
    scan_name <- NULL   # single-scan: no scan_name in selector
  }

  K <- length(scan@cluster_ids)
  T <- scan@n_time

  if (nrow(design) != T) {
    stop("nrow(design) [", nrow(design), "] must equal number of observations [",
         T, "] in the scan", call. = FALSE)
  }

  # Parcel metadata — scan always has @clusters and @mask slots
  parcel_meta <- .compute_parcel_meta(scan)

  # Optionally write parcel_map TSV
  parcel_map_relpath <- NULL
  if (!is.null(output_dir)) {
    dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
    pm_path <- file.path(output_dir, "parcel_map.tsv")
    data.table::fwrite(parcel_meta, pm_path, sep = "\t")
    parcel_map_relpath <- "parcel_map.tsv"
  }

  # Support
  support <- nf_support_parcel(
    support_id     = paste0("parcels-k", K),
    space          = space,
    n_parcels      = K,
    parcel_map     = parcel_map_relpath,
    membership_ref = basename(path)
  )

  # Logical schema
  logical <- nf_logical_schema(
    "vector", "parcel", "float32",
    shape       = K,
    support_ref = "parcels"
  )

  # Observation table
  design <- .ensure_row_id(design)
  res_id <- "fmristore_scan"

  selectors <- vapply(seq_len(T), function(i) {
    sel <- list(row_index = i)
    if (!is.null(scan_name)) sel$scan_name <- scan_name
    jsonlite::toJSON(sel, auto_unbox = TRUE)
  }, character(1L))

  obs <- design
  obs$.fmristore_res <- res_id
  obs$.fmristore_sel <- selectors

  # Resources table
  resources <- data.frame(
    resource_id = res_id,
    backend     = "fmristore-parcel",
    locator     = path,
    stringsAsFactors = FALSE
  )

  # Column schemas
  obs_cols <- .design_to_col_schemas(design)
  obs_cols$.fmristore_res <- nf_col_schema("string", nullable = FALSE)
  obs_cols$.fmristore_sel <- nf_col_schema("json",   nullable = FALSE)

  # Feature
  feat <- nf_feature(
    logical   = logical,
    encodings = list(
      nf_ref_encoding(
        resource_id = nf_col(".fmristore_res"),
        selector    = nf_col(".fmristore_sel")
      )
    )
  )

  # Observation axes: any design column whose name matches a semantic role
  axis_candidates <- c("subject", "session", "run", "condition", "group")
  axes <- intersect(axis_candidates, names(design))
  if (!length(axes)) axes <- names(design)[names(design) != "row_id"][1L]

  did <- dataset_id %||%
    paste0("fmristore-", tools::file_path_sans_ext(basename(path)))

  m <- nf_manifest(
    dataset_id          = did,
    row_id              = "row_id",
    observation_axes    = axes,
    observation_columns = obs_cols,
    features            = stats::setNames(list(feat), feature),
    supports            = list(parcels = support),
    resources_path      = "resources.csv",
    resources_format    = "csv"
  )

  nftab(manifest = m, observations = obs, resources = resources,
        .root = output_dir)
}

# -- nf_ingest_parcel_csv ------------------------------------------------------

#' Ingest a parcel-signal CSV into an nftab
#'
#' Reads a CSV file where rows are observations and columns are parcel signals,
#' and wraps it into an [nftab] using a `columns` encoding (data stored inline
#' in the observation table).
#'
#' @param path Path to the CSV file.  Every column not present in `design` (or
#'   matched by `parcel_cols`) is treated as a parcel signal column.
#' @param design A data.frame with one row per observation.
#' @param parcel_cols Optional character vector of column names to use as parcel
#'   signals.  If `NULL` (default), all CSV columns absent from `design` are
#'   used.
#' @param parcel_map Optional path to a TSV (or data.frame) with columns
#'   `index`, `label`, `n_voxels`, `x_centroid`, `y_centroid`, `z_centroid`.
#'   When provided, an [nf_support_parcel()] is attached.
#' @param space Named reference space.  Used only when `parcel_map` is
#'   provided.  Default `"unknown"`.
#' @param feature Name to give the parcel-signal feature.  Default
#'   `"parcel_signal"`.
#' @param dataset_id Dataset identifier for the manifest.
#'
#' @return An [nftab] object with a `columns` encoding (data inline).
#' @export
nf_ingest_parcel_csv <- function(path,
                                  design,
                                  parcel_cols = NULL,
                                  parcel_map  = NULL,
                                  space       = "unknown",
                                  feature     = "parcel_signal",
                                  dataset_id  = NULL) {
  stopifnot(is.data.frame(design))

  mat <- data.table::fread(path, header = TRUE, data.table = FALSE)

  # Identify parcel columns
  if (!is.null(parcel_cols)) {
    pcols <- parcel_cols
  } else {
    pcols <- setdiff(names(mat), names(design))
    if (!length(pcols)) pcols <- names(mat)
  }

  K <- length(pcols)
  n <- nrow(mat)

  if (nrow(design) != n) {
    stop("nrow(design) [", nrow(design), "] must equal nrow(csv) [", n, "]",
         call. = FALSE)
  }

  # Optional parcel support
  support     <- NULL
  support_ref <- NULL
  if (!is.null(parcel_map)) {
    pm <- if (is.character(parcel_map)) {
      data.table::fread(parcel_map, header = TRUE, data.table = FALSE)
    } else {
      as.data.frame(parcel_map)
    }
    support <- nf_support_parcel(
      support_id = paste0("parcels-k", K),
      space      = space,
      n_parcels  = K,
      parcel_map = if (is.character(parcel_map)) basename(parcel_map) else NULL
    )
    support_ref <- "parcels"
  }

  # Logical schema + feature
  logical <- nf_logical_schema(
    "vector", "parcel", "float32",
    shape       = K,
    support_ref = support_ref
  )

  feat <- nf_feature(
    logical   = logical,
    encodings = list(nf_columns_encoding(pcols))
  )

  # Observation table
  design  <- .ensure_row_id(design)
  parcel_data <- mat[, pcols, drop = FALSE]
  obs <- cbind(design, parcel_data)

  # Column schemas
  obs_cols <- .design_to_col_schemas(design)
  for (pc in pcols) {
    obs_cols[[pc]] <- nf_col_schema("float32")
  }

  # Observation axes
  axis_candidates <- c("subject", "session", "run", "condition", "group")
  axes <- intersect(axis_candidates, names(design))
  if (!length(axes)) axes <- names(design)[names(design) != "row_id"][1L]

  did <- dataset_id %||% paste0("parcel-csv-k", K)

  m <- nf_manifest(
    dataset_id          = did,
    row_id              = "row_id",
    observation_axes    = axes,
    observation_columns = obs_cols,
    features            = stats::setNames(list(feat), feature),
    supports            = if (!is.null(support)) list(parcels = support) else NULL
  )

  nftab(manifest = m, observations = obs)
}

# -- nf_from_table -------------------------------------------------------------

#' Create an nftab from a table and external feature files
#'
#' The most common entry point for building an nftab from existing data.
#' Supports two patterns:
#'
#' - **One file per row**: each row has a column pointing to a separate 3D file.
#' - **Shared file**: all rows map to successive volumes in a single 4D file.
#'
#' The backend is inferred from file extension (`.nii`, `.nii.gz` -> `"nifti"`)
#' or can be set explicitly.
#'
#' @param observations A data.frame or path to a CSV/TSV file. Each row is one
#'   observation with design metadata columns.
#' @param feature Name to give the feature (e.g. `"statmap"`).
#' @param locator_col Column name in `observations` containing per-row file
#'   paths. Use this for the one-file-per-row pattern. Mutually exclusive with
#'   `locator`.
#' @param locator A single file path shared by all rows (4D file). Row `i` maps
#'   to volume `i-1` (0-based). Mutually exclusive with `locator_col`.
#' @param row_id Name of the row ID column. If the column does not exist, one
#'   is generated automatically. Default `"row_id"`.
#' @param axes Character vector of observation axis column names. If `NULL`,
#'   auto-detected as all string columns except `row_id`, `locator_col`, and
#'   any selector column.
#' @param backend Backend identifier. Default `NULL` (auto-detect from file
#'   extension).
#' @param space Named reference space (e.g. `"MNI152NLin2009cAsym"`).
#' @param dataset_id Dataset identifier for the manifest.
#' @param root Base directory for resolving relative paths. If `NULL` and
#'   `observations` is a file path, uses its parent directory.
#'
#' @return An [nftab] object.
#' @export
nf_from_table <- function(observations,
                           feature = "statmap",
                           locator_col = NULL,
                           locator = NULL,
                           row_id = "row_id",
                           axes = NULL,
                           backend = NULL,
                           space = NULL,
                           dataset_id = "dataset",
                           root = NULL) {
  # -- Read observations -------------------------------------------------------
  if (is.character(observations) && length(observations) == 1L) {
    obs_path <- observations
    if (is.null(root)) root <- dirname(obs_path)
    observations <- .read_table(obs_path, tools::file_ext(obs_path))
  }
  stopifnot(is.data.frame(observations), nrow(observations) >= 1L)

  # -- Validate locator args ---------------------------------------------------
  has_col <- !is.null(locator_col)
  has_loc <- !is.null(locator)
  if (!has_col && !has_loc) {
    stop("provide either locator_col (one file per row) or locator (shared file)",
         call. = FALSE)
  }
  if (has_col && has_loc) {
    stop("locator_col and locator are mutually exclusive", call. = FALSE)
  }

  # -- Resolve a sample file to get shape and detect backend -------------------
  sample_file <- if (has_col) {
    as.character(observations[[locator_col]][1L])
  } else {
    as.character(locator)
  }
  if (!is.null(root) && !grepl("^(/|[a-zA-Z]:)", sample_file)) {
    sample_abs <- file.path(root, sample_file)
  } else {
    sample_abs <- sample_file
  }
  if (!file.exists(sample_abs)) {
    stop("cannot read sample file to detect shape: ", sample_abs, call. = FALSE)
  }

  if (is.null(backend)) {
    backend <- .infer_backend(sample_abs)
  }

  shape <- .read_file_shape(sample_abs, backend)
  is_4d <- length(shape) == 4L
  shape_3d <- shape[1:3]

  # -- Handle shared 4D file ---------------------------------------------------
  if (has_loc) {
    if (!is_4d) {
      stop("locator points to a 3D file; use locator_col for one-file-per-row",
           call. = FALSE)
    }
    n_vols <- shape[4L]
    if (nrow(observations) != n_vols) {
      stop(sprintf(
        "observation table has %d rows but 4D file has %d volumes",
        nrow(observations), n_vols), call. = FALSE)
    }
    # Add resource_id and selector columns
    res_id <- paste0(feature, "_resource")
    sel_col <- paste0(feature, "_sel")
    observations[[res_id]] <- res_id
    observations[[sel_col]] <- vapply(seq_len(n_vols) - 1L, function(t) {
      jsonlite::toJSON(list(index = list(t = t)), auto_unbox = TRUE)
    }, character(1))
  }

  # -- Ensure row_id -----------------------------------------------------------
  observations <- .ensure_row_id(observations, row_id)

  # -- Auto-detect axes --------------------------------------------------------
  exclude_cols <- c(row_id)
  if (has_col) exclude_cols <- c(exclude_cols, locator_col)
  if (has_loc) exclude_cols <- c(exclude_cols, res_id, sel_col)

  if (is.null(axes)) {
    string_cols <- names(observations)[vapply(observations, is.character, logical(1))]
    axes <- setdiff(string_cols, exclude_cols)
    if (length(axes) == 0L) {
      stop("no observation axes detected; provide axes explicitly", call. = FALSE)
    }
  }

  # -- Build column schemas ----------------------------------------------------
  col_schemas <- .design_to_col_schemas(observations)
  # Mark row_id and axes as non-nullable
  col_schemas[[row_id]]$nullable <- FALSE
  for (ax in axes) col_schemas[[ax]]$nullable <- FALSE

  # -- Build encoding ----------------------------------------------------------
  if (has_col) {
    encoding <- nf_ref_encoding(
      backend = backend,
      locator = nf_col(locator_col)
    )
  } else {
    encoding <- nf_ref_encoding(
      resource_id = nf_col(res_id),
      selector    = nf_col(sel_col)
    )
  }

  # -- Build support -----------------------------------------------------------
  support <- NULL
  support_ref <- NULL
  supports <- NULL
  grid_id <- paste0(dataset_id, "-grid-", paste(shape_3d, collapse = "x"))

  if (!is.null(space)) {
    support_ref <- paste0(dataset_id, "_grid")
    support <- nf_support_volume(
      support_id = grid_id,
      space      = space,
      grid_id    = grid_id
    )
    supports <- stats::setNames(list(support), support_ref)
  }

  # -- Build feature -----------------------------------------------------------
  feat_kind <- if (!is.null(space)) "volume" else "array"
  logical <- nf_logical_schema(
    kind        = feat_kind,
    axes        = c("x", "y", "z"),
    dtype       = "float32",
    shape       = as.integer(shape_3d),
    support_ref = support_ref,
    space       = space,
    alignment   = if (!is.null(space)) "same_grid" else NULL
  )
  feat <- nf_feature(logical = logical, encodings = list(encoding))

  # -- Build resource registry (for shared 4D file) ----------------------------
  resources <- NULL
  if (has_loc) {
    resources <- data.frame(
      resource_id = res_id,
      backend     = backend,
      locator     = locator,
      stringsAsFactors = FALSE
    )
  }

  # -- Build manifest and return -----------------------------------------------
  m <- nf_manifest(
    dataset_id          = dataset_id,
    row_id              = row_id,
    observation_axes    = axes,
    observation_columns = col_schemas,
    features            = stats::setNames(list(feat), feature),
    supports            = supports,
    resources_path      = if (!is.null(resources)) "resources.csv" else NULL,
    resources_format    = if (!is.null(resources)) "csv" else NULL
  )

  nftab(manifest = m, observations = observations,
        resources = resources, .root = root)
}

# -- Internal helpers for nf_from_table ----------------------------------------

.infer_backend <- function(path) {
  ext <- tolower(tools::file_ext(path))
  # Handle .nii.gz compound extension
  if (ext == "gz" && grepl("\\.nii\\.gz$", tolower(path))) {
    return("nifti")
  }
  switch(ext,
    nii = "nifti",
    h5  = "hdf5",
    hdf5 = "hdf5",
    zarr = "zarr",
    stop("cannot infer backend from extension '.", ext,
         "'; provide backend explicitly", call. = FALSE)
  )
}

.read_file_shape <- function(path, backend) {
  if (backend == "nifti") {
    if (requireNamespace("RNifti", quietly = TRUE)) {
      hdr <- RNifti::niftiHeader(path)
      dims <- hdr$dim
      # dim[1] is ndim, dim[2:ndim+1] are the actual dimensions
      ndim <- dims[1L]
      return(dims[2L:(ndim + 1L)])
    }
    if (requireNamespace("neuroim2", quietly = TRUE)) {
      info <- neuroim2::read_header(path)
      return(dim(info))
    }
    stop("RNifti or neuroim2 required to read NIfTI header", call. = FALSE)
  }
  stop("shape detection not implemented for backend '", backend, "'",
       call. = FALSE)
}
