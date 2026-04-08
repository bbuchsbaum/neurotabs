# Scalar column schema and logical feature schema constructors
# Corresponds to NFTab spec sections 6 and 8.

# -- Scalar column schema -----------------------------------------------------

.valid_scalar_dtypes <- c(

"string", "int32", "int64", "float32", "float64",
  "bool", "date", "datetime", "json"
)

.valid_semantic_roles <- c(
  "row_id", "subject", "session", "run", "group",
  "condition", "contrast", "site", "covariate"
)

#' Declare a scalar column schema
#'
#' @param dtype Data type. One of `"string"`, `"int32"`, `"int64"`, `"float32"`,
#'   `"float64"`, `"bool"`, `"date"`, `"datetime"`, `"json"`.
#' @param nullable Whether null values are permitted. Default `TRUE`.
#' @param semantic_role Optional semantic role hint (e.g., `"subject"`,
#'   `"group"`, `"condition"`).
#' @param levels Optional character vector of allowed categorical values.
#' @param unit Optional unit of measurement.
#' @param description Optional human-readable description.
#'
#' @return An `nf_col_schema` object.
#' @export
nf_col_schema <- function(dtype,
                          nullable = TRUE,
                          semantic_role = NULL,
                          levels = NULL,
                          unit = NULL,
                          description = NULL) {
  dtype <- match.arg(dtype, .valid_scalar_dtypes)
  stopifnot(is.logical(nullable), length(nullable) == 1L)
  if (!is.null(semantic_role)) {
    stopifnot(is.character(semantic_role), length(semantic_role) == 1L)
  }
  if (!is.null(levels)) {
    stopifnot(is.character(levels))
  }

  structure(
    list(
      dtype = dtype,
      nullable = nullable,
      semantic_role = semantic_role,
      levels = levels,
      unit = unit,
      description = description
    ),
    class = "nf_col_schema"
  )
}

#' @export
print.nf_col_schema <- function(x, ...) {
  cat("<nf_col_schema>", x$dtype)
  if (!x$nullable) cat(" [NOT NULL]")
  if (!is.null(x$semantic_role)) cat(" (", x$semantic_role, ")", sep = "")
  cat("\n")
  invisible(x)
}

# -- Logical feature schema ---------------------------------------------------

.valid_feature_kinds <- c("array", "volume", "vector", "matrix", "surface")

.valid_feature_dtypes <- c(
  "int32", "int64", "float32", "float64",
  "bool", "uint8", "uint16", "string"
)

.valid_alignments <- c("same_grid", "same_space", "same_topology", "loose", "none")
.valid_support_types <- c("volume", "surface", "generic", "parcel")
.valid_surface_hemispheres <- c("left", "right", "both", "midline", "unknown")

#' Declare an axis domain
#'
#' @param id Unique identifier for the label set (e.g., `"desikan68"`).
#' @param labels Relative path to a label table (TSV).
#' @param size Expected axis length.
#' @param description Human-readable description.
#'
#' @return An `nf_axis_domain` object.
#' @export
nf_axis_domain <- function(id = NULL, labels = NULL, size = NULL,
                           description = NULL) {
  if (!is.null(size)) stopifnot(is.numeric(size), length(size) == 1L, size >= 1L)
  structure(
    list(
      id = id,
      labels = labels,
      size = if (is.null(size)) NULL else as.integer(size),
      description = description
    ),
    class = "nf_axis_domain"
  )
}

# -- Support schema -----------------------------------------------------------

#' Declare a generic support descriptor
#'
#' @param support_type Support class: `"volume"`, `"surface"`, or `"generic"`.
#' @param support_id Stable exact identifier for the support.
#' @param description Optional human-readable description.
#' @param metadata Optional named list of extra support metadata.
#' @param ... Additional support-type-specific fields.
#'
#' @return An `nf_support_schema` object.
#' @export
nf_support <- function(support_type,
                       support_id,
                       description = NULL,
                       metadata = NULL,
                       ...) {
  support_type <- match.arg(support_type, .valid_support_types)
  stopifnot(is.character(support_id), length(support_id) == 1L, nzchar(support_id))

  extra <- list(...)
  out <- list(
    support_type = support_type,
    support_id = support_id,
    description = description,
    metadata = metadata
  )

  if (support_type == "volume") {
    required <- c("space", "grid_id")
    missing <- setdiff(required, names(extra))
    if (length(missing)) {
      stop("volume support requires fields: ", paste(missing, collapse = ", "), call. = FALSE)
    }
    out$space <- extra$space
    out$grid_id <- extra$grid_id
    out$affine_id <- extra$affine_id
  } else if (support_type == "surface") {
    required <- c("template", "mesh_id", "topology_id", "hemisphere")
    missing <- setdiff(required, names(extra))
    if (length(missing)) {
      stop("surface support requires fields: ", paste(missing, collapse = ", "), call. = FALSE)
    }
    out$template <- extra$template
    out$mesh_id <- extra$mesh_id
    out$topology_id <- extra$topology_id
    out$hemisphere <- match.arg(extra$hemisphere, .valid_surface_hemispheres)
  } else if (support_type == "parcel") {
    required <- c("space", "n_parcels")
    missing <- setdiff(required, names(extra))
    if (length(missing)) {
      stop("parcel support requires fields: ", paste(missing, collapse = ", "), call. = FALSE)
    }
    out$space          <- extra$space
    out$n_parcels      <- as.integer(extra$n_parcels)
    out$parcel_map     <- extra$parcel_map      # relative path to TSV
    out$membership_ref <- extra$membership_ref  # optional path to H5 voxel data
  }

  structure(out, class = "nf_support_schema")
}

#' Declare a volume support descriptor
#'
#' @param support_id Stable exact identifier for the volume support.
#' @param space Named reference space.
#' @param grid_id Stable identifier for the voxel lattice.
#' @param affine_id Optional stable identifier for the affine or transform.
#' @param description Optional human-readable description.
#' @param metadata Optional named list of extra support metadata.
#'
#' @return An `nf_support_schema` object with `support_type = "volume"`.
#' @export
nf_support_volume <- function(support_id,
                              space,
                              grid_id,
                              affine_id = NULL,
                              description = NULL,
                              metadata = NULL) {
  nf_support(
    support_type = "volume",
    support_id = support_id,
    description = description,
    metadata = metadata,
    space = space,
    grid_id = grid_id,
    affine_id = affine_id
  )
}

#' Declare a surface support descriptor
#'
#' @param support_id Stable exact identifier for the surface support.
#' @param template Surface template family.
#' @param mesh_id Stable identifier for the surface mesh embedding.
#' @param topology_id Stable identifier for the topology basis.
#' @param hemisphere Hemisphere identity.
#' @param description Optional human-readable description.
#' @param metadata Optional named list of extra support metadata.
#'
#' @return An `nf_support_schema` object with `support_type = "surface"`.
#' @export
nf_support_surface <- function(support_id,
                               template,
                               mesh_id,
                               topology_id,
                               hemisphere,
                               description = NULL,
                               metadata = NULL) {
  nf_support(
    support_type = "surface",
    support_id = support_id,
    description = description,
    metadata = metadata,
    template = template,
    mesh_id = mesh_id,
    topology_id = topology_id,
    hemisphere = hemisphere
  )
}

#' Declare a parcel support descriptor
#'
#' Describes a brain parcellation — a set of named ROIs, each comprising one or
#' more voxels.  The `parcel_map` TSV (columns: `index`, `label`, `n_voxels`,
#' `x_centroid`, `y_centroid`, `z_centroid`) provides the lightweight spatial
#' summary used by downstream tools.  Full voxel membership lives in the source
#' file and can be referenced via `membership_ref`.
#'
#' @param support_id Stable identifier for this parcellation version.
#' @param space Named reference space (e.g., `"MNI152NLin2009cAsym"`).
#' @param n_parcels Number of parcels (integer).
#' @param parcel_map Optional relative path to a TSV with columns `index`,
#'   `label`, `n_voxels`, `x_centroid`, `y_centroid`, `z_centroid`.
#' @param membership_ref Optional path to an HDF5 file containing full voxel
#'   membership (e.g., the source fmristore file).
#' @param description Optional human-readable description.
#' @param metadata Optional named list of extra metadata.
#'
#' @return An `nf_support_schema` object with `support_type = "parcel"`.
#' @export
nf_support_parcel <- function(support_id,
                               space,
                               n_parcels,
                               parcel_map     = NULL,
                               membership_ref = NULL,
                               description    = NULL,
                               metadata       = NULL) {
  nf_support(
    support_type   = "parcel",
    support_id     = support_id,
    description    = description,
    metadata       = metadata,
    space          = space,
    n_parcels      = n_parcels,
    parcel_map     = parcel_map,
    membership_ref = membership_ref
  )
}

#' Declare a generic support descriptor
#'
#' @param support_id Stable exact identifier for the support.
#' @param description Optional human-readable description.
#' @param metadata Optional named list of extra support metadata.
#'
#' @return An `nf_support_schema` object with `support_type = "generic"`.
#' @export
nf_support_generic <- function(support_id,
                               description = NULL,
                               metadata = NULL) {
  nf_support(
    support_type = "generic",
    support_id = support_id,
    description = description,
    metadata = metadata
  )
}

#' @export
print.nf_support_schema <- function(x, ...) {
  cat("<nf_support_schema>", x$support_type, x$support_id, "\n")
  if (!is.null(x$space))          cat("  space:", x$space, "\n")
  if (!is.null(x$grid_id))        cat("  grid_id:", x$grid_id, "\n")
  if (!is.null(x$template))       cat("  template:", x$template, "\n")
  if (!is.null(x$mesh_id))        cat("  mesh_id:", x$mesh_id, "\n")
  if (!is.null(x$topology_id))    cat("  topology_id:", x$topology_id, "\n")
  if (!is.null(x$hemisphere))     cat("  hemisphere:", x$hemisphere, "\n")
  if (!is.null(x$n_parcels))      cat("  n_parcels:", x$n_parcels, "\n")
  if (!is.null(x$parcel_map))     cat("  parcel_map:", x$parcel_map, "\n")
  if (!is.null(x$membership_ref)) cat("  membership_ref:", x$membership_ref, "\n")
  invisible(x)
}

#' @export
print.nf_axis_domain <- function(x, ...) {
  cat("<nf_axis_domain>\n")
  if (!is.null(x$id)) cat("  id:", x$id, "\n")
  if (!is.null(x$labels)) cat("  labels:", x$labels, "\n")
  if (!is.null(x$size)) cat("  size:", x$size, "\n")
  if (!is.null(x$description)) cat("  description:", x$description, "\n")
  invisible(x)
}

#' Declare a logical feature schema
#'
#' Describes what a resolved feature value IS, independent of how it is stored.
#'
#' @param kind Descriptive kind: `"volume"`, `"vector"`, `"matrix"`,
#'   `"surface"`, or `"array"`.
#' @param axes Character vector of semantic axis names (e.g., `c("x","y","z")`).
#' @param dtype Element data type.
#' @param support_ref Optional manifest-local reference to an exact support
#'   descriptor.
#' @param shape Optional integer vector of expected dimensions.
#' @param axis_domains Optional named list of [nf_axis_domain] objects.
#' @param space Optional named coordinate space (e.g., `"MNI152NLin2009cAsym"`).
#' @param alignment Optional alignment guarantee: `"same_grid"`, `"same_space"`,
#'   `"loose"`, or `"none"`.
#' @param unit Optional unit of measurement.
#' @param description Optional human-readable description.
#'
#' @return An `nf_logical_schema` object.
#' @export
nf_logical_schema <- function(kind,
                              axes,
                              dtype,
                              support_ref = NULL,
                              shape = NULL,
                              axis_domains = NULL,
                              space = NULL,
                              alignment = NULL,
                              unit = NULL,
                              description = NULL) {
  kind <- match.arg(kind, .valid_feature_kinds)
  stopifnot(is.character(axes), length(axes) >= 1L)
  dtype <- match.arg(dtype, .valid_feature_dtypes)

  if (!is.null(shape)) {
    shape <- as.integer(shape)
    if (length(shape) != length(axes)) {
      stop("length(shape) must equal length(axes)", call. = FALSE)
    }
    if (any(shape < 1L)) {
      stop("all shape dimensions must be >= 1", call. = FALSE)
    }
  }

  if (!is.null(alignment)) {
    alignment <- match.arg(alignment, .valid_alignments)
  }

  if (!is.null(support_ref)) {
    stopifnot(is.character(support_ref), length(support_ref) == 1L, nzchar(support_ref))
  }
  if (kind %in% c("volume", "surface") && is.null(support_ref)) {
    stop("logical kind '", kind, "' requires support_ref", call. = FALSE)
  }
  if (identical(kind, "volume") && identical(alignment, "same_topology")) {
    stop("volume features cannot use alignment = 'same_topology'", call. = FALSE)
  }
  if (identical(kind, "surface") && identical(alignment, "same_grid")) {
    stop("surface features cannot use alignment = 'same_grid'", call. = FALSE)
  }

  structure(
    list(
      kind = kind,
      axes = axes,
      dtype = dtype,
      support_ref = support_ref,
      shape = shape,
      axis_domains = axis_domains,
      space = space,
      alignment = alignment,
      unit = unit,
      description = description
    ),
    class = "nf_logical_schema"
  )
}

#' @export
print.nf_logical_schema <- function(x, ...) {
  shape_str <- if (!is.null(x$shape)) paste0("[", paste(x$shape, collapse = ","), "]") else "?"
  cat("<nf_logical_schema>", x$kind, shape_str, x$dtype, "\n")
  cat("  axes:", paste(x$axes, collapse = ", "), "\n")
  if (!is.null(x$support_ref)) cat("  support_ref:", x$support_ref, "\n")
  if (!is.null(x$space)) cat("  space:", x$space, "\n")
  if (!is.null(x$alignment)) cat("  alignment:", x$alignment, "\n")
  invisible(x)
}

#' Compute a schema fingerprint for compatibility checking
#'
#' Two features are concatenation-compatible iff their fingerprints are
#' identical.
#'
#' @param x An [nf_logical_schema] object.
#' @param support_id Optional exact support identifier used for compatibility
#'   fingerprints.
#' @return A character string (hex digest).
#' @export
nf_schema_fingerprint <- function(x, support_id = NULL) {
  stopifnot(inherits(x, "nf_logical_schema"))
  key <- list(
    kind = x$kind,
    axes = x$axes,
    dtype = x$dtype,
    shape = x$shape,
    support_id = support_id,
    space = x$space,
    alignment = x$alignment,
    axis_domains = x$axis_domains,
    unit = x$unit
  )
  digest::digest(key, algo = "xxhash64")
}
