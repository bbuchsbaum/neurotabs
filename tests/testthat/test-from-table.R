test_that("nf_from_table creates nftab from per-row 3D NIfTIs", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("from_table_3d_")
  dir.create(file.path(tmpdir, "maps"), recursive = TRUE)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  d <- c(3L, 3L, 3L)
  for (i in 1:3) {
    RNifti::writeNifti(array(as.numeric(i * 10), dim = d),
                       file.path(tmpdir, "maps", sprintf("s%02d.nii.gz", i)))
  }

  obs <- data.frame(
    subject = c("s01", "s02", "s03"),
    condition = c("A", "B", "A"),
    map = sprintf("maps/s%02d.nii.gz", 1:3),
    stringsAsFactors = FALSE
  )

  ds <- nf_from_table(obs, "statmap", locator_col = "map",
                       space = "MNI152", root = tmpdir)

  expect_s3_class(ds, "nftab")
  expect_equal(nf_nobs(ds), 3L)
  expect_equal(nf_feature_names(ds), "statmap")
  expect_true(all(c("subject", "condition") %in% nf_axes(ds)))

  vol <- nf_resolve(ds, 1L, "statmap")
  expect_equal(dim(vol), d)
  expect_equal(mean(vol), 10, tolerance = 1e-4)
})

test_that("nf_from_table creates nftab from shared 4D NIfTI", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("from_table_4d_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  vol4d <- array(0, dim = c(2L, 2L, 2L, 3L))
  vol4d[, , , 1] <- 1
  vol4d[, , , 2] <- 2
  vol4d[, , , 3] <- 3
  RNifti::writeNifti(vol4d, file.path(tmpdir, "bold.nii.gz"))

  obs <- data.frame(
    subject = c("s01", "s01", "s02"),
    condition = c("A", "B", "A"),
    stringsAsFactors = FALSE
  )

  ds <- nf_from_table(obs, "statmap", locator = "bold.nii.gz",
                       space = "MNI152", root = tmpdir)

  expect_s3_class(ds, "nftab")
  expect_equal(nf_nobs(ds), 3L)
  expect_true(!is.null(ds$resources))

  vol1 <- nf_resolve(ds, 1L, "statmap")
  vol3 <- nf_resolve(ds, 3L, "statmap")
  expect_equal(dim(vol1), c(2, 2, 2))
  expect_equal(as.vector(vol1), rep(1, 8))
  expect_equal(as.vector(vol3), rep(3, 8))
})

test_that("nf_from_table auto-generates row_id", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("from_table_rid_")
  dir.create(file.path(tmpdir, "maps"), recursive = TRUE)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  RNifti::writeNifti(array(1, dim = c(2, 2, 2)),
                     file.path(tmpdir, "maps", "vol.nii.gz"))

  obs <- data.frame(
    subject = "s01",
    map = "maps/vol.nii.gz",
    stringsAsFactors = FALSE
  )

  ds <- nf_from_table(obs, "vol", locator_col = "map", root = tmpdir)
  expect_true("row_id" %in% names(ds$observations))
  expect_equal(nf_nobs(ds), 1L)
})

test_that("nf_from_table errors on missing locator args", {
  obs <- data.frame(subject = "s01", stringsAsFactors = FALSE)
  expect_error(nf_from_table(obs, "f"), "locator_col.*locator")
})

test_that("nf_from_table errors on both locator args", {
  obs <- data.frame(subject = "s01", map = "f.nii.gz", stringsAsFactors = FALSE)
  expect_error(nf_from_table(obs, "f", locator_col = "map", locator = "f.nii.gz"),
               "mutually exclusive")
})

test_that("nf_from_table errors on 4D row count mismatch", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("from_table_mismatch_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  RNifti::writeNifti(array(0, dim = c(2, 2, 2, 5)),
                     file.path(tmpdir, "bold.nii.gz"))

  obs <- data.frame(subject = c("s01", "s02"), stringsAsFactors = FALSE)
  expect_error(
    nf_from_table(obs, "f", locator = "bold.nii.gz", root = tmpdir),
    "2 rows.*5 volumes"
  )
})

test_that("nf_from_table reads CSV observations", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("from_table_csv_")
  dir.create(file.path(tmpdir, "maps"), recursive = TRUE)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  RNifti::writeNifti(array(42, dim = c(2, 2, 2)),
                     file.path(tmpdir, "maps", "vol.nii.gz"))

  data.table::fwrite(
    data.frame(subject = "s01", map = "maps/vol.nii.gz", stringsAsFactors = FALSE),
    file.path(tmpdir, "obs.csv")
  )

  ds <- nf_from_table(file.path(tmpdir, "obs.csv"), "statmap",
                       locator_col = "map")
  expect_s3_class(ds, "nftab")
  expect_equal(nf_nobs(ds), 1L)
})
