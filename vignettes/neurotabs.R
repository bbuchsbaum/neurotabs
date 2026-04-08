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

## ----load-roi-example---------------------------------------------------------
roi_path <- system.file("examples/roi-only/nftab.yaml", package = "neurotabs")
stopifnot(nzchar(roi_path))

roi_ds <- nf_read(roi_path)
roi_ds

## ----inspect-roi-example------------------------------------------------------
nf_axes(roi_ds)
nf_feature_names(roi_ds)

## ----inspect-read-types-------------------------------------------------------
vapply(
  roi_ds$observations[c("row_id", "subject", "age", "roi_1")],
  function(x) paste(class(x), collapse = "/"),
  character(1)
)

## ----validate-roi-example-----------------------------------------------------
structural <- nf_validate(roi_ds, level = "structural")
stopifnot(structural$valid)

structural$valid

## ----validate-roi-full--------------------------------------------------------
full <- nf_validate(roi_ds, level = "full")
stopifnot(full$valid)

full$valid

## ----resolve-roi--------------------------------------------------------------
nf_resolve(roi_ds, 1L, "roi_beta")

## ----collect-roi--------------------------------------------------------------
roi_mat <- nf_collect(roi_ds, "roi_beta")
stopifnot(is.matrix(roi_mat), ncol(roi_mat) == 5L)

dim(roi_mat)

## ----load-faces-example-------------------------------------------------------
faces_path <- system.file("examples/faces-demo/nftab.yaml", package = "neurotabs")
stopifnot(nzchar(faces_path))

faces_ds <- nf_read(faces_path)
nf_feature_names(faces_ds)
nf_resolve(faces_ds, 1L, "roi_beta")

## ----inspect-axis-domain------------------------------------------------------
roi_schema <- nf_feature_schema(faces_ds, "roi_beta")
stopifnot(identical(roi_schema$axes, "roi"))

roi_axis <- nf_axis_info(faces_ds, "roi_beta", "roi")
stopifnot(identical(roi_axis$id, "desikan3-demo"))

roi_axis

## ----read-axis-labels---------------------------------------------------------
roi_labels <- nf_axis_labels(faces_ds, "roi_beta", "roi")
roi_values <- nf_resolve(faces_ds, 1L, "roi_beta")
stopifnot(nrow(roi_labels) == length(roi_values))

data.frame(
  atlas = roi_axis$id,
  label = roi_labels$label,
  value = roi_values,
  row.names = NULL
)

