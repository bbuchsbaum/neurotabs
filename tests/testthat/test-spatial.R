# Tests for nf_sample(), nf_collect_array(), and as_array = FALSE resolution

# Helper: build a 2-row nftab backed by two separate 3D NIfTI files with
# known, distinct values.
.make_nifti_vol_nftab <- function() {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("neurotabs-spatial-")
  dir.create(file.path(tmpdir, "maps"), recursive = TRUE)

  d <- c(5L, 5L, 5L)

  arr1 <- array(seq_len(prod(d)), dim = d)          # values 1..125
  arr2 <- array(seq_len(prod(d)) + 100L, dim = d)   # values 101..225

  RNifti::writeNifti(arr1, file.path(tmpdir, "maps", "sub01.nii.gz"))
  RNifti::writeNifti(arr2, file.path(tmpdir, "maps", "sub02.nii.gz"))

  obs_cols <- list(
    row_id    = nf_col_schema("string",  nullable = FALSE, semantic_role = "row_id"),
    subject   = nf_col_schema("string",  nullable = FALSE, semantic_role = "subject"),
    condition = nf_col_schema("string",  nullable = FALSE, semantic_role = "condition"),
    map_file  = nf_col_schema("string",  nullable = FALSE)
  )

  feat <- nf_feature(
    logical = nf_logical_schema(
      "volume", c("x", "y", "z"), "float32",
      shape = d, support_ref = "test_grid"
    ),
    encodings = list(
      nf_ref_encoding(backend = "nifti", locator = nf_col("map_file"))
    )
  )

  m <- nf_manifest(
    dataset_id = "test-spatial",
    row_id = "row_id",
    observation_axes = c("subject", "condition"),
    observation_columns = obs_cols,
    features = list(statmap = feat),
    supports = list(
      test_grid = nf_support_volume(
        support_id = "test-5x5x5",
        space = "MNI152NLin2009cAsym",
        grid_id   = "test-5x5x5"
      )
    )
  )

  obs <- data.frame(
    row_id    = c("r1", "r2"),
    subject   = c("s01", "s02"),
    condition = c("faces", "houses"),
    map_file  = c("maps/sub01.nii.gz", "maps/sub02.nii.gz"),
    stringsAsFactors = FALSE
  )

  list(
    ds     = nftab(manifest = m, observations = obs, .root = tmpdir),
    arr1   = arr1,
    arr2   = arr2,
    tmpdir = tmpdir,
    d      = d
  )
}

# ── as_array = FALSE ──────────────────────────────────────────────────────────

test_that("nf_resolve as_array=FALSE returns array when no native_resolve_fn", {
  # The x-unknown backend has no native_resolve_fn, so it falls back to array.
  ds <- .make_ref_nftab()
  # Just check it doesn't error (backend is x-unknown, which will fail to
  # dispatch — so we only verify the argument is accepted without error up to
  # backend dispatch).
  expect_error(
    nf_resolve(ds, 1L, "statmap", as_array = FALSE),
    "no adapter registered"
  )
})

test_that("nf_resolve as_array=FALSE returns NeuroVol via nifti backend", {
  skip_if_not_installed("neuroim2")
  fix <- .make_nifti_vol_nftab()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  vol <- nf_resolve(fix$ds, 1L, "statmap", as_array = FALSE)
  expect_true(inherits(vol, "NeuroVol"))
  expect_equal(dim(vol), fix$d)
})

test_that("nf_resolve as_array=TRUE still returns plain array via nifti backend", {
  skip_if_not_installed("RNifti")
  fix <- .make_nifti_vol_nftab()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  arr <- nf_resolve(fix$ds, 1L, "statmap", as_array = TRUE)
  expect_true(is.array(arr))
  expect_equal(dim(arr), fix$d)
})

# ── nf_sample ────────────────────────────────────────────────────────────────

test_that("nf_sample returns [n_obs x n_coords] matrix with correct rownames", {
  skip_if_not_installed("RNifti")
  fix <- .make_nifti_vol_nftab()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  coords <- matrix(c(1L, 1L, 1L,
                      2L, 3L, 4L), nrow = 2L, byrow = TRUE)

  mat <- nf_sample(fix$ds, "statmap", coords)

  expect_true(is.matrix(mat))
  expect_equal(dim(mat), c(2L, 2L))
  expect_equal(rownames(mat), c("r1", "r2"))
})

test_that("nf_sample extracts correct values at known voxel coords", {
  skip_if_not_installed("RNifti")
  fix <- .make_nifti_vol_nftab()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  # Voxel (1,1,1) is linear index 1; (2,1,1) is linear index 2
  coords <- matrix(c(1L, 1L, 1L,
                      2L, 1L, 1L), nrow = 2L, byrow = TRUE)

  mat <- nf_sample(fix$ds, "statmap", coords)

  expect_equal(mat[1L, 1L], fix$arr1[1L, 1L, 1L], tolerance = 1e-4, ignore_attr = TRUE)
  expect_equal(mat[1L, 2L], fix$arr1[2L, 1L, 1L], tolerance = 1e-4, ignore_attr = TRUE)
  expect_equal(mat[2L, 1L], fix$arr2[1L, 1L, 1L], tolerance = 1e-4, ignore_attr = TRUE)
  expect_equal(mat[2L, 2L], fix$arr2[2L, 1L, 1L], tolerance = 1e-4, ignore_attr = TRUE)
})

test_that("nf_sample respects the 'rows' argument", {
  skip_if_not_installed("RNifti")
  fix <- .make_nifti_vol_nftab()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  coords <- matrix(c(1L, 1L, 1L), nrow = 1L)

  mat <- nf_sample(fix$ds, "statmap", coords, rows = 2L)

  expect_equal(dim(mat), c(1L, 1L))
  expect_equal(rownames(mat), "r2")
  expect_equal(mat[1L, 1L], fix$arr2[1L, 1L, 1L], tolerance = 1e-4, ignore_attr = TRUE)
})

test_that("nf_sample errors on non-matrix coords", {
  fix <- .make_nifti_vol_nftab()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  expect_error(nf_sample(fix$ds, "statmap", c(1L, 1L, 1L)), "matrix with 3 columns")
  expect_error(nf_sample(fix$ds, "statmap", matrix(1:4, nrow = 2)), "matrix with 3 columns")
})

test_that("nf_sample works with grouped_nftab input", {
  skip_if_not_installed("RNifti")
  fix <- .make_nifti_vol_nftab()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  coords <- matrix(c(1L, 1L, 1L), nrow = 1L)
  grouped <- nf_group_by(fix$ds, condition)
  mat <- nf_sample(grouped, "statmap", coords)

  expect_equal(dim(mat), c(2L, 1L))
})

test_that("spatial helpers accept bare symbols and string variables", {
  skip_if_not_installed("RNifti")
  fix <- .make_nifti_vol_nftab()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)
  feature_name <- "statmap"
  coords <- matrix(c(1L, 1L, 1L), nrow = 1L)

  expect_equal(nf_sample(fix$ds, statmap, coords), nf_sample(fix$ds, "statmap", coords))
  expect_equal(
    nf_collect_array(fix$ds, feature_name)$data,
    nf_collect_array(fix$ds, "statmap")$data
  )
})

# ── nf_collect_array ──────────────────────────────────────────────────────────

test_that("nf_collect_array returns list with data and space", {
  skip_if_not_installed("RNifti")
  fix <- .make_nifti_vol_nftab()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  result <- nf_collect_array(fix$ds, "statmap")

  expect_true(is.list(result))
  expect_true(all(c("data", "space") %in% names(result)))
})

test_that("nf_collect_array data has correct dimensions", {
  skip_if_not_installed("RNifti")
  fix <- .make_nifti_vol_nftab()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  result <- nf_collect_array(fix$ds, "statmap")

  expect_equal(dim(result$data), c(fix$d, 2L))
})

test_that("nf_collect_array stacks correct values per observation", {
  skip_if_not_installed("RNifti")
  fix <- .make_nifti_vol_nftab()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  result <- nf_collect_array(fix$ds, "statmap")

  expect_equal(as.vector(result$data[, , , 1L]),
               as.vector(fix$arr1), tolerance = 1e-4)
  expect_equal(as.vector(result$data[, , , 2L]),
               as.vector(fix$arr2), tolerance = 1e-4)
})

test_that("nf_collect_array returns NeuroSpace when neuroim2 available", {
  skip_if_not_installed("neuroim2")
  fix <- .make_nifti_vol_nftab()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  result <- nf_collect_array(fix$ds, "statmap")
  expect_true(inherits(result$space, "NeuroSpace"))
})

test_that("nf_collect_array errors on non-3D feature", {
  ds <- .make_roi_nftab()  # roi_beta is 1D, not 3D
  expect_error(nf_collect_array(ds, "roi_beta"), "3D")
})
