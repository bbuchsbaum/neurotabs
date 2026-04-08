params <-
list(family = "red", preset = "homage")

## ----setup, include = FALSE---------------------------------------------------
if (requireNamespace("ggplot2", quietly = TRUE) && requireNamespace("albersdown", quietly = TRUE)) ggplot2::theme_set(albersdown::theme_albers(family = params$family, preset = params$preset))
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>",
  message = FALSE,
  warning = FALSE
)
pkg_root <- if (file.exists("DESCRIPTION")) {
  "."
} else if (file.exists("../DESCRIPTION")) {
  ".."
} else {
  NULL
}
if (!is.null(pkg_root) && requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(pkg_root, export_all = FALSE, helpers = FALSE, quiet = TRUE)
} else if (!is.null(pkg_root) && requireNamespace("devtools", quietly = TRUE)) {
  devtools::load_all(pkg_root, export_all = FALSE, helpers = FALSE, quiet = TRUE)
} else if (requireNamespace("neurotabs", quietly = TRUE)) {
  library(neurotabs)
} else {
  stop("neurotabs must be installed, or pkgload/devtools must be available for local rendering.")
}

## ----load-spec-examples-------------------------------------------------------
roi_path <- system.file("examples/roi-only/nftab.yaml", package = "neurotabs")
faces_path <- system.file("examples/faces-demo/nftab.yaml", package = "neurotabs")
stopifnot(nzchar(roi_path), nzchar(faces_path))

roi_raw <- yaml::read_yaml(roi_path)
faces_raw <- yaml::read_yaml(faces_path)

roi_ds <- nf_read(roi_path)
faces_ds <- nf_read(faces_path)

## ----abstract-model-----------------------------------------------------------
list(
  dataset_id = roi_raw$dataset_id,
  storage_profile = roi_raw$storage_profile,
  observation_axes = roi_raw$observation_axes,
  features = names(roi_raw$features)
)

## ----manifest-top-level-------------------------------------------------------
roi_raw[c(
  "spec_version",
  "dataset_id",
  "storage_profile",
  "row_id",
  "observation_axes"
)]

## ----observation-table-ref----------------------------------------------------
roi_raw$observation_table

## ----observation-table-preview------------------------------------------------
utils::head(
  roi_ds$observations[c("row_id", "subject", "group", "condition", "age")],
  4
)

## ----scalar-schema------------------------------------------------------------
roi_raw$observation_columns$age

## ----logical-schema-----------------------------------------------------------
roi_schema <- nf_feature_schema(roi_ds, "roi_beta")
roi_schema

## ----logical-value------------------------------------------------------------
roi_value <- nf_resolve(roi_ds, 1L, "roi_beta")
stopifnot(length(roi_value) == 5L)

roi_value

## ----columns-encoding---------------------------------------------------------
roi_raw$features$roi_beta$encodings[[1]]

## ----ref-encoding-------------------------------------------------------------
faces_raw$features$statmap$encodings[[1]]

## ----axis-domain--------------------------------------------------------------
roi_axis <- nf_axis_info(faces_ds, "roi_beta", "roi")
roi_labels <- nf_axis_labels(faces_ds, "roi_beta", "roi")
stopifnot(nrow(roi_labels) == 3L)

roi_axis

## ----axis-labels--------------------------------------------------------------
data.frame(
  atlas = roi_axis$id,
  label = roi_labels$label,
  row.names = NULL
)

## ----masked-volume-extension--------------------------------------------------
masked_manifest <- nf_manifest(
  dataset_id = "masked-demo",
  row_id = "row_id",
  observation_axes = c("subject", "condition"),
  observation_columns = list(
    row_id = nf_col_schema("string", nullable = FALSE),
    subject = nf_col_schema("string", nullable = FALSE),
    condition = nf_col_schema("string", nullable = FALSE),
    v1 = nf_col_schema("float32"),
    v2 = nf_col_schema("float32"),
    v3 = nf_col_schema("float32")
  ),
  features = list(
    statvec = nf_feature(
      logical = nf_logical_schema(
        "vector",
        "voxel",
        "float32",
        shape = 3L,
        space = "MNI152NLin2009cAsym",
        alignment = "same_grid"
      ),
      encodings = list(nf_columns_encoding(c("v1", "v2", "v3")))
    )
  ),
  extensions = list(
    "x-masked-volume" = list(
      features = list(
        statvec = list(
          grid_axes = c("x", "y", "z"),
          grid_shape = c(91L, 109L, 91L),
          grid_index_base = 0L,
          index_map = list(
            path = "voxel_index.tsv",
            format = "tsv"
          )
        )
      )
    )
  )
)

masked_ds <- nftab(
  masked_manifest,
  observations = data.frame(
    row_id = c("r1", "r2"),
    subject = c("s01", "s02"),
    condition = c("faces", "houses"),
    v1 = c(0.1, 0.4),
    v2 = c(0.2, 0.5),
    v3 = c(0.3, 0.6),
    stringsAsFactors = FALSE
  )
)

nf_extension(masked_ds, "x-masked-volume")

## ----resource-registry-manifest-----------------------------------------------
faces_raw$resources

## ----resource-registry-table--------------------------------------------------
faces_ds$resources

## ----conformance--------------------------------------------------------------
structural <- nf_validate(roi_ds, level = "structural")
full <- nf_validate(roi_ds, level = "full")
stopifnot(structural$valid, full$valid)

c(structural = structural$valid, full = full$valid)

## ----compatibility------------------------------------------------------------
compat <- nf_compatible(roi_ds, roi_ds)
stopifnot(compat$compatible)

compat

