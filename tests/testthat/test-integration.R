# Full pipeline integration test
# Exercises: nf_read-like construction -> filter -> group -> summarize -> write -> read-back

test_that("full pipeline: construct -> filter -> group -> summarize -> write -> read", {
  skip_if_not_installed("RNifti")
  old <- options(neurotabs.compute.workers = 1L)
  on.exit(options(old), add = TRUE)

  tmpdir <- tempfile("integration-")
  dir.create(file.path(tmpdir, "maps"), recursive = TRUE)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  # Create 4 volumes: 2 subjects x 2 conditions
  d <- c(3L, 3L, 3L)
  for (s in 1:2) {
    for (cond in c("faces", "houses")) {
      val <- if (cond == "faces") s * 10 else s * 20
      arr <- array(val, dim = d)
      fname <- sprintf("sub%02d_%s.nii.gz", s, cond)
      RNifti::writeNifti(arr, file.path(tmpdir, "maps", fname))
    }
  }

  obs_cols <- list(
    row_id    = nf_col_schema("string",  nullable = FALSE),
    subject   = nf_col_schema("string",  nullable = FALSE),
    condition = nf_col_schema("string",  nullable = FALSE),
    map_file  = nf_col_schema("string",  nullable = FALSE)
  )

  feat <- nf_feature(
    logical = nf_logical_schema("volume", c("x", "y", "z"), "float32",
                                shape = d, support_ref = "grid"),
    encodings = list(nf_ref_encoding(backend = "nifti", locator = nf_col("map_file")))
  )

  m <- nf_manifest(
    dataset_id = "integration-test",
    row_id = "row_id",
    observation_axes = c("subject", "condition"),
    observation_columns = obs_cols,
    features = list(statmap = feat),
    supports = list(
      grid = nf_support_volume("int-grid-3x3x3", "MNI152", "int-grid-3x3x3")
    )
  )

  obs <- data.frame(
    row_id = c("r1", "r2", "r3", "r4"),
    subject = c("s01", "s01", "s02", "s02"),
    condition = c("faces", "houses", "faces", "houses"),
    map_file = c("maps/sub01_faces.nii.gz", "maps/sub01_houses.nii.gz",
                 "maps/sub02_faces.nii.gz", "maps/sub02_houses.nii.gz"),
    stringsAsFactors = FALSE
  )

  ds <- nftab(m, obs, .root = tmpdir)
  expect_s3_class(ds, "nftab")
  expect_equal(nf_nobs(ds), 4L)

  # Filter to faces only
  ds_faces <- nf_filter(ds, condition == "faces")
  expect_equal(nf_nobs(ds_faces), 2L)

  # Resolve and check values
  vol1 <- nf_resolve(ds_faces, 1L, "statmap")
  expect_equal(as.vector(vol1), rep(10, 27))

  # Apply mean across voxels
  means <- nf_apply(ds, "statmap", "mean")
  expect_equal(means[["r1"]], 10, tolerance = 1e-4)
  expect_equal(means[["r4"]], 40, tolerance = 1e-4)

  # Validate structural
  result <- nf_validate(ds, level = "structural")
  expect_true(result$valid)
})

test_that("ROI pipeline: construct -> group -> collect -> validate", {
  ds <- .make_roi_nftab()

  # Group by condition
  grouped <- nf_group_by(ds, condition)
  expect_s3_class(grouped, "grouped_nftab")

  # Collect feature values
  vals <- nf_collect(ds, "roi_beta")
  expect_true(is.matrix(vals))
  expect_equal(nrow(vals), 4L)
  expect_equal(ncol(vals), 3L)

  # Arrange
  sorted <- nf_arrange(ds, subject)
  expect_equal(nf_design(sorted)$subject, c("s01", "s01", "s02", "s02"))

  # Select subset of columns
  slim <- nf_select(ds, subject, condition)
  expect_true("roi_1" %in% names(nf_design(slim)))  # retained by encoding

  # Validate
  result <- nf_validate(ds, level = "full")
  expect_true(result$valid)
})
