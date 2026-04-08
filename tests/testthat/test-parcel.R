# Tests for parcel support, ingestion, and fmristore backend

# -- nf_support_parcel constructor ---------------------------------------------

test_that("nf_support_parcel() constructs correctly", {
  sp <- nf_support_parcel(
    support_id = "desikan68",
    space      = "MNI152NLin2009cAsym",
    n_parcels  = 68L
  )
  expect_s3_class(sp, "nf_support_schema")
  expect_equal(sp$support_type, "parcel")
  expect_equal(sp$support_id,   "desikan68")
  expect_equal(sp$n_parcels,    68L)
  expect_equal(sp$space,        "MNI152NLin2009cAsym")
  expect_null(sp$parcel_map)
  expect_null(sp$membership_ref)
})

test_that("nf_support_parcel() with optional fields", {
  sp <- nf_support_parcel(
    support_id     = "k10",
    space          = "unknown",
    n_parcels      = 10L,
    parcel_map     = "parcel_map.tsv",
    membership_ref = "scan.h5",
    description    = "Ten parcels"
  )
  expect_equal(sp$parcel_map,     "parcel_map.tsv")
  expect_equal(sp$membership_ref, "scan.h5")
  expect_equal(sp$description,    "Ten parcels")
})

test_that("nf_support_parcel() prints cleanly", {
  sp <- nf_support_parcel("k5", "unknown", 5L, parcel_map = "pm.tsv")
  expect_output(print(sp), "parcel")
  expect_output(print(sp), "k5")
  expect_output(print(sp), "n_parcels.*5")
  expect_output(print(sp), "parcel_map.*pm.tsv")
})

# -- nf_ingest_parcel_csv helpers ----------------------------------------------

.make_parcel_csv_fixture <- function(K = 5L, T_obs = 8L) {
  tmpdir <- tempfile("parcel_csv_")
  dir.create(tmpdir)

  set.seed(42)
  mat <- matrix(rnorm(T_obs * K), nrow = T_obs, ncol = K)
  colnames(mat) <- paste0("parcel_", seq_len(K))

  csv_path <- file.path(tmpdir, "parcel_data.csv")
  write.csv(mat, csv_path, row.names = FALSE)

  design <- data.frame(
    subject   = rep(c("s01", "s02"), length.out = T_obs),
    condition = rep(c("A", "B"), length.out = T_obs),
    run       = seq_len(T_obs),
    stringsAsFactors = FALSE
  )

  list(csv_path = csv_path, design = design, mat = mat,
       K = K, T_obs = T_obs, tmpdir = tmpdir)
}

# -- nf_ingest_parcel_csv -----------------------------------------------------

test_that("nf_ingest_parcel_csv() returns nftab with correct dims", {
  fx <- .make_parcel_csv_fixture()
  on.exit(unlink(fx$tmpdir, recursive = TRUE), add = TRUE)

  ds <- nf_ingest_parcel_csv(fx$csv_path, fx$design)
  expect_s3_class(ds, "nftab")
  expect_equal(nf_nobs(ds), fx$T_obs)
  expect_equal(nf_feature_names(ds), "parcel_signal")
})

test_that("nf_ingest_parcel_csv() feature has correct shape and kind", {
  fx <- .make_parcel_csv_fixture(K = 6L)
  on.exit(unlink(fx$tmpdir, recursive = TRUE), add = TRUE)

  ds   <- nf_ingest_parcel_csv(fx$csv_path, fx$design)
  feat <- ds$manifest$features[["parcel_signal"]]
  expect_equal(feat$logical$kind, "vector")
  expect_equal(feat$logical$axes, "parcel")
  expect_equal(feat$logical$shape, 6L)
})

test_that("nf_ingest_parcel_csv() custom feature name", {
  fx <- .make_parcel_csv_fixture(K = 3L)
  on.exit(unlink(fx$tmpdir, recursive = TRUE), add = TRUE)

  ds <- nf_ingest_parcel_csv(fx$csv_path, fx$design, feature = "my_rois")
  expect_equal(nf_feature_names(ds), "my_rois")
})

test_that("nf_collect() on parcel_csv nftab returns T x K matrix", {
  K <- 5L; T_obs <- 8L
  fx <- .make_parcel_csv_fixture(K = K, T_obs = T_obs)
  on.exit(unlink(fx$tmpdir, recursive = TRUE), add = TRUE)

  ds  <- nf_ingest_parcel_csv(fx$csv_path, fx$design)
  mat <- nf_collect(ds, "parcel_signal")

  expect_true(is.matrix(mat))
  expect_equal(dim(mat), c(T_obs, K))
  # Values should match the original CSV data
  expect_equal(unname(mat[1L, ]), unname(fx$mat[1L, ]), tolerance = 1e-5)
  expect_equal(unname(mat[T_obs, ]), unname(fx$mat[T_obs, ]), tolerance = 1e-5)
})

test_that("nf_resolve() on parcel_csv returns correct vector per row", {
  fx <- .make_parcel_csv_fixture(K = 4L, T_obs = 6L)
  on.exit(unlink(fx$tmpdir, recursive = TRUE), add = TRUE)

  ds <- nf_ingest_parcel_csv(fx$csv_path, fx$design)

  for (i in c(1L, 3L, 6L)) {
    v <- nf_resolve(ds, i, "parcel_signal")
    expect_equal(length(v), fx$K)
    expect_equal(as.numeric(v), unname(fx$mat[i, ]), tolerance = 1e-5)
  }
})

test_that("nf_ingest_parcel_csv() with explicit parcel_cols selects subset", {
  fx <- .make_parcel_csv_fixture(K = 5L, T_obs = 6L)
  on.exit(unlink(fx$tmpdir, recursive = TRUE), add = TRUE)

  ds <- nf_ingest_parcel_csv(fx$csv_path, fx$design,
                              parcel_cols = c("parcel_1", "parcel_2", "parcel_3"))
  feat <- ds$manifest$features[["parcel_signal"]]
  expect_equal(feat$logical$shape, 3L)

  mat <- nf_collect(ds, "parcel_signal")
  expect_equal(ncol(mat), 3L)
})

test_that("nf_ingest_parcel_csv() with parcel_map attaches parcel support", {
  K <- 4L; T_obs <- 6L
  fx <- .make_parcel_csv_fixture(K = K, T_obs = T_obs)
  on.exit(unlink(fx$tmpdir, recursive = TRUE), add = TRUE)

  pm <- data.frame(
    index      = seq_len(K),
    label      = paste0("roi_", seq_len(K)),
    n_voxels   = c(10L, 20L, 15L, 8L),
    x_centroid = c(10.0, 20.0, 30.0, 40.0),
    y_centroid = c(5.0, 10.0, 15.0, 20.0),
    z_centroid = c(2.0, 4.0, 6.0, 8.0)
  )
  pm_path <- file.path(fx$tmpdir, "pm.tsv")
  write.table(pm, pm_path, sep = "\t", row.names = FALSE, quote = FALSE)

  ds <- nf_ingest_parcel_csv(fx$csv_path, fx$design, parcel_map = pm_path)
  expect_false(is.null(ds$manifest$supports))
  sp <- ds$manifest$supports[["parcels"]]
  expect_s3_class(sp, "nf_support_schema")
  expect_equal(sp$support_type, "parcel")
  expect_equal(sp$n_parcels, K)
})

test_that("nf_ingest_parcel_csv() with data.frame parcel_map", {
  K <- 3L; T_obs <- 4L
  fx <- .make_parcel_csv_fixture(K = K, T_obs = T_obs)
  on.exit(unlink(fx$tmpdir, recursive = TRUE), add = TRUE)

  pm <- data.frame(
    index = 1:3, label = c("a", "b", "c"), n_voxels = c(5L, 6L, 7L),
    x_centroid = 1:3, y_centroid = 4:6, z_centroid = 7:9
  )

  ds <- nf_ingest_parcel_csv(fx$csv_path, fx$design, parcel_map = pm)
  sp <- ds$manifest$supports[["parcels"]]
  expect_equal(sp$n_parcels, K)
  # parcel_map should be NULL since we passed a data.frame (not a path)
  expect_null(sp$parcel_map)
})

test_that("nf_ingest_parcel_csv() errors on row count mismatch", {
  fx <- .make_parcel_csv_fixture(K = 3L, T_obs = 6L)
  on.exit(unlink(fx$tmpdir, recursive = TRUE), add = TRUE)

  bad_design <- fx$design[1:4, ]
  expect_error(
    nf_ingest_parcel_csv(fx$csv_path, bad_design),
    "nrow"
  )
})

test_that("nf_ingest_parcel_csv() auto-discovers observation axes", {
  fx <- .make_parcel_csv_fixture(K = 3L, T_obs = 4L)
  on.exit(unlink(fx$tmpdir, recursive = TRUE), add = TRUE)

  ds <- nf_ingest_parcel_csv(fx$csv_path, fx$design)
  axes <- ds$manifest$observation_axes
  expect_true("subject" %in% axes)
  expect_true("condition" %in% axes)
})

test_that("nf_ingest_parcel_csv() adds row_id when missing", {
  fx <- .make_parcel_csv_fixture(K = 3L, T_obs = 4L)
  on.exit(unlink(fx$tmpdir, recursive = TRUE), add = TRUE)

  ds <- nf_ingest_parcel_csv(fx$csv_path, fx$design)
  expect_true("row_id" %in% names(ds$observations))
  expect_equal(ds$manifest$row_id, "row_id")
})

# -- Round-trip: write + read parcel nftab ------------------------------------

test_that("nf_write/nf_read round-trips parcel CSV nftab", {
  K <- 4L; T_obs <- 6L
  fx <- .make_parcel_csv_fixture(K = K, T_obs = T_obs)
  on.exit(unlink(fx$tmpdir, recursive = TRUE), add = TRUE)

  pm_path <- file.path(fx$tmpdir, "pm.tsv")
  pm <- data.frame(
    index = seq_len(K), label = paste0("r", seq_len(K)),
    n_voxels = rep(10L, K),
    x_centroid = seq_len(K), y_centroid = seq_len(K), z_centroid = seq_len(K)
  )
  write.table(pm, pm_path, sep = "\t", row.names = FALSE, quote = FALSE)

  ds <- nf_ingest_parcel_csv(fx$csv_path, fx$design,
                              parcel_map = pm_path, dataset_id = "rt-parcel")

  out_dir <- file.path(fx$tmpdir, "out")
  nf_write(ds, out_dir)

  ds2 <- nf_read(file.path(out_dir, "nftab.yaml"))
  expect_equal(ds2$manifest$dataset_id, "rt-parcel")
  expect_equal(nf_nobs(ds2), T_obs)

  mat1 <- nf_collect(ds, "parcel_signal")
  mat2 <- nf_collect(ds2, "parcel_signal")
  expect_equal(unname(mat2), unname(mat1), tolerance = 1e-5)

  # Parcel support survives round-trip
  sp2 <- ds2$manifest$supports[["parcels"]]
  expect_s3_class(sp2, "nf_support_schema")
  expect_equal(sp2$support_type, "parcel")
  expect_equal(sp2$n_parcels, K)
})

# -- fmristore backend tests --------------------------------------------------

# Helper: create a single-run H5 file via write_parcellated_experiment_h5.
# Returns list(h5_path, scan_data, K, T_obs, tmpdir, mask, clus).
.make_fmristore_h5 <- function(K = 3L, T_obs = 4L, dims = c(3L, 3L, 3L),
                                scan_names = "scan_001", seed = 42) {
  n_vox <- prod(dims)
  sp   <- neuroim2::NeuroSpace(dims)
  mask <- neuroim2::LogicalNeuroVol(array(TRUE, dims), sp)
  cids <- ((seq_len(n_vox) - 1L) %% K) + 1L
  clus <- neuroim2::ClusteredNeuroVol(mask, clusters = cids)

  set.seed(seed)
  runs_data <- lapply(scan_names, function(nm) {
    list(scan_name = nm, type = "summary",
         data = matrix(rnorm(T_obs * K), nrow = T_obs, ncol = K))
  })

  tmpdir  <- tempfile("fmristore_test_")
  dir.create(tmpdir)
  h5_path <- file.path(tmpdir, "experiment.h5")

  fmristore::write_parcellated_experiment_h5(
    filepath = h5_path, mask = mask, clusters = clus,
    runs_data = runs_data, verbose = FALSE
  )

  list(h5_path = h5_path, runs_data = runs_data, K = K, T_obs = T_obs,
       tmpdir = tmpdir, mask = mask, clus = clus)
}

# Helper: design with unique observation axis tuples for T_obs rows.
.fmristore_design <- function(T_obs) {
  data.frame(
    subject = rep("s01", T_obs),
    run     = seq_len(T_obs),
    stringsAsFactors = FALSE
  )
}

test_that("nf_ingest_parcel_h5() creates nftab from single-run H5", {
  skip_if_not_installed("fmristore")
  skip_if_not_installed("neuroim2")

  fx <- .make_fmristore_h5(K = 3L, T_obs = 6L)
  on.exit(unlink(fx$tmpdir, recursive = TRUE), add = TRUE)

  design <- .fmristore_design(fx$T_obs)
  ds <- nf_ingest_parcel_h5(fx$h5_path, design, output_dir = fx$tmpdir)

  expect_s3_class(ds, "nftab")
  expect_equal(nf_nobs(ds), fx$T_obs)
  expect_equal(nf_feature_names(ds), "parcel_signal")
  expect_equal(ds$manifest$features[["parcel_signal"]]$logical$shape, fx$K)
})

test_that("nf_resolve() returns correct vector for fmristore single-run", {
  skip_if_not_installed("fmristore")
  skip_if_not_installed("neuroim2")

  fx <- .make_fmristore_h5(K = 4L, T_obs = 5L, dims = c(4L, 4L, 4L), seed = 7)
  on.exit(unlink(fx$tmpdir, recursive = TRUE), add = TRUE)

  design <- .fmristore_design(fx$T_obs)
  ds     <- nf_ingest_parcel_h5(fx$h5_path, design, output_dir = fx$tmpdir)

  expected <- fx$runs_data[[1]]$data
  for (i in seq_len(fx$T_obs)) {
    v <- nf_resolve(ds, i, "parcel_signal")
    expect_equal(length(v), fx$K)
    expect_equal(as.numeric(v), expected[i, ], tolerance = 1e-5)
  }
})

test_that("nf_ingest_parcel_h5() handles multi-run H5", {
  skip_if_not_installed("fmristore")
  skip_if_not_installed("neuroim2")

  fx <- .make_fmristore_h5(K = 3L, T_obs = 4L,
                             scan_names = c("run_01", "run_02"), seed = 11)
  on.exit(unlink(fx$tmpdir, recursive = TRUE), add = TRUE)

  design <- .fmristore_design(fx$T_obs)

  # Ingest first run
  ds1 <- nf_ingest_parcel_h5(fx$h5_path, design, scan_name = "run_01",
                               output_dir = fx$tmpdir)
  expect_s3_class(ds1, "nftab")
  expect_equal(nf_nobs(ds1), fx$T_obs)

  v1 <- nf_resolve(ds1, 1L, "parcel_signal")
  expect_equal(as.numeric(v1), fx$runs_data[[1]]$data[1L, ], tolerance = 1e-5)

  # Ingest second run
  ds2 <- nf_ingest_parcel_h5(fx$h5_path, design, scan_name = "run_02",
                               output_dir = fx$tmpdir)
  v2 <- nf_resolve(ds2, 1L, "parcel_signal")
  expect_equal(as.numeric(v2), fx$runs_data[[2]]$data[1L, ], tolerance = 1e-5)
})

test_that("nf_ingest_parcel_h5() errors on design row mismatch", {
  skip_if_not_installed("fmristore")
  skip_if_not_installed("neuroim2")

  fx <- .make_fmristore_h5(K = 2L, T_obs = 4L, dims = c(2L, 2L, 2L), seed = 1)
  on.exit(unlink(fx$tmpdir, recursive = TRUE), add = TRUE)

  bad_design <- data.frame(subject = c("s01", "s02"), run = 1:2,
                            stringsAsFactors = FALSE)
  expect_error(
    nf_ingest_parcel_h5(fx$h5_path, bad_design, output_dir = fx$tmpdir),
    "nrow"
  )
})

test_that("nf_ingest_parcel_h5() writes parcel_map.tsv when output_dir set", {
  skip_if_not_installed("fmristore")
  skip_if_not_installed("neuroim2")

  fx <- .make_fmristore_h5(K = 3L, T_obs = 4L, seed = 0)
  on.exit(unlink(fx$tmpdir, recursive = TRUE), add = TRUE)

  design <- .fmristore_design(fx$T_obs)
  ds     <- nf_ingest_parcel_h5(fx$h5_path, design, output_dir = fx$tmpdir)

  pm_path <- file.path(fx$tmpdir, "parcel_map.tsv")
  expect_true(file.exists(pm_path))

  pm <- read.delim(pm_path)
  expect_true("index" %in% names(pm))
  expect_true("n_voxels" %in% names(pm))
  expect_true("x_centroid" %in% names(pm))
  expect_equal(nrow(pm), fx$K)
})
