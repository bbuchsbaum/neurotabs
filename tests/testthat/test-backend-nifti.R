test_that("nifti backend is registered", {
  skip_if_not_installed("RNifti")
  expect_true("nifti" %in% nf_backends())
})

test_that("nifti write round-trip produces correct values", {
  skip_if_not_installed("RNifti")

  arr <- array(seq_len(27), dim = c(3, 3, 3))
  out_path <- file.path(tempdir(), "neurotabs_test_roundtrip.nii.gz")
  on.exit(unlink(out_path), add = TRUE)

  neurotabs:::.nifti_write(out_path, arr, logical_schema = NULL)
  expect_true(file.exists(out_path))

  read_back <- neurotabs:::.nifti_resolve(out_path, selector = NULL, logical_schema = NULL)
  expect_lt(max(abs(as.vector(arr) - as.vector(read_back))), 1e-4)
})

test_that("nifti write creates intermediate directories", {
  skip_if_not_installed("RNifti")

  arr <- array(1:8, dim = c(2, 2, 2))
  out_path <- file.path(tempdir(), "neurotabs_nested", "a", "b", "c.nii.gz")
  on.exit(unlink(file.path(tempdir(), "neurotabs_nested"), recursive = TRUE), add = TRUE)

  neurotabs:::.nifti_write(out_path, arr, logical_schema = NULL)
  expect_true(file.exists(out_path))
})

test_that("nf_read loads shipped faces-demo and resolves ROI vectors", {
  path <- system.file("examples/faces-demo/nftab.yaml", package = "neurotabs")
  skip_if(path == "", "faces-demo example not installed")

  ds <- nf_read(path)

  expect_s3_class(ds, "nftab")
  expect_true(all(c("statmap", "roi_beta") %in% nf_feature_names(ds)))

  roi <- nf_resolve(ds, 1L, "roi_beta")
  expect_equal(roi, c(0.31, 0.44, 0.29))
})

test_that("nf_read resolves 4D nifti selectors end-to-end", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("nftab_nifti_")
  dir.create(tmpdir)
  dir.create(file.path(tmpdir, "maps"))
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  vol4d <- array(0, dim = c(2, 2, 2, 3))
  vol4d[, , , 1] <- 1
  vol4d[, , , 2] <- 2
  vol4d[, , , 3] <- 3
  RNifti::writeNifti(vol4d, file.path(tmpdir, "maps", "group_stats.nii.gz"))

  yaml::write_yaml(
    list(
      spec_version = "0.1.0",
      dataset_id = "nifti-demo",
      storage_profile = "table-package",
      observation_table = list(path = "observations.csv", format = "csv"),
      row_id = "row_id",
      observation_axes = list("subject", "condition"),
      observation_columns = list(
        row_id = list(dtype = "string", nullable = FALSE),
        subject = list(dtype = "string", nullable = FALSE),
        condition = list(dtype = "string", nullable = FALSE),
        stat_res = list(dtype = "string", nullable = FALSE),
        stat_sel = list(dtype = "json", nullable = FALSE)
      ),
      features = list(
        statmap = list(
          logical = list(
            kind = "volume",
            axes = list("x", "y", "z"),
            dtype = "float32",
            support_ref = "mni_2mm_demo",
            shape = list(2L, 2L, 2L),
            alignment = "same_grid"
          ),
          encodings = list(
            list(
              type = "ref",
              binding = list(
                resource_id = list(column = "stat_res"),
                selector = list(column = "stat_sel")
              )
            )
          )
        )
      ),
      supports = list(
        mni_2mm_demo = list(
          support_type = "volume",
          support_id = "mni152-2mm-grid-2x2x2-demo",
          space = "MNI152NLin2009cAsym",
          grid_id = "mni152-2mm-grid-2x2x2-demo"
        )
      ),
      resources = list(path = "resources.csv", format = "csv")
    ),
    file.path(tmpdir, "nftab.yaml")
  )

  data.table::fwrite(
    data.frame(
      row_id = c("r1", "r2"),
      subject = c("s1", "s2"),
      condition = c("faces", "houses"),
      stat_res = c("group4d", "group4d"),
      stat_sel = c('{"index":{"t":0}}', '{"index":{"t":2}}'),
      stringsAsFactors = FALSE
    ),
    file.path(tmpdir, "observations.csv")
  )

  data.table::fwrite(
    data.frame(
      resource_id = "group4d",
      backend = "nifti",
      locator = "maps/group_stats.nii.gz",
      checksum = paste0(
        "md5:",
        digest::digest(
          file = file.path(tmpdir, "maps", "group_stats.nii.gz"),
          algo = "md5",
          serialize = FALSE
        )
      ),
      stringsAsFactors = FALSE
    ),
    file.path(tmpdir, "resources.csv")
  )

  ds <- nf_read(file.path(tmpdir, "nftab.yaml"))

  vol1 <- as.array(nf_resolve(ds, "r1", "statmap"))
  vol2 <- as.array(nf_resolve(ds, "r2", "statmap"))
  expect_equal(ds$manifest$features$statmap$logical$support_ref, "mni_2mm_demo")
  expect_equal(ds$manifest$supports$mni_2mm_demo$support_id, "mni152-2mm-grid-2x2x2-demo")
  expect_equal(dim(vol1), c(2, 2, 2))
  expect_equal(dim(vol2), c(2, 2, 2))
  expect_equal(as.vector(vol1), rep(1, 8))
  expect_equal(as.vector(vol2), rep(3, 8))

  result <- nf_validate(ds, level = "full")
  expect_true(result$valid)
})

test_that(".nifti_resolve_rnifti handles 3D volumes", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("rnifti_3d_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  arr <- array(seq_len(27), dim = c(3, 3, 3))
  path <- file.path(tmpdir, "vol.nii.gz")
  RNifti::writeNifti(arr, path)

  result <- neurotabs:::.nifti_resolve_rnifti(path, selector = NULL, logical_schema = NULL)
  expect_equal(dim(result), c(3, 3, 3))
  expect_lt(max(abs(as.vector(result) - as.vector(arr))), 1e-4)
})

test_that(".nifti_resolve_rnifti handles 4D selector", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("rnifti_4d_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  vol4d <- array(0, dim = c(2, 2, 2, 3))
  vol4d[, , , 1] <- 1
  vol4d[, , , 2] <- 2
  vol4d[, , , 3] <- 3
  path <- file.path(tmpdir, "vol4d.nii.gz")
  RNifti::writeNifti(vol4d, path)

  sel <- list(index = list(t = 1L))  # 0-based, so t=1 -> second volume
  result <- neurotabs:::.nifti_resolve_rnifti(path, selector = sel, logical_schema = NULL)
  expect_equal(dim(result), c(2, 2, 2))
  expect_equal(as.vector(result), rep(2, 8))
})

test_that(".nifti_write_rnifti writes and reads back", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("rnifti_write_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  arr <- array(seq_len(8), dim = c(2, 2, 2))
  path <- file.path(tmpdir, "out.nii.gz")

  neurotabs:::.nifti_write_rnifti(path, arr, logical_schema = NULL,
                                   template = NULL, source_ref = NULL)
  expect_true(file.exists(path))

  read_back <- neurotabs:::.nifti_resolve_rnifti(path, NULL, NULL)
  expect_lt(max(abs(as.vector(arr) - as.vector(read_back))), 1e-4)
})

test_that(".nifti_native_resolve returns NeuroVol when neuroim2 available", {
  skip_if_not_installed("neuroim2")
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("native_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  arr <- array(1:8, dim = c(2, 2, 2))
  path <- file.path(tmpdir, "vol.nii.gz")
  RNifti::writeNifti(arr, path)

  vol <- neurotabs:::.nifti_native_resolve(path, NULL, NULL)
  expect_true(inherits(vol, "NeuroVol"))
  expect_equal(dim(vol), c(2, 2, 2))
})

test_that(".nifti_resolve_neuroim2 handles 3D volumes", {
  skip_if_not_installed("neuroim2")
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("neuroim2_3d_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  arr <- array(seq_len(27), dim = c(3, 3, 3))
  path <- file.path(tmpdir, "vol.nii.gz")
  RNifti::writeNifti(arr, path)

  result <- neurotabs:::.nifti_resolve_neuroim2(path, NULL, NULL)
  expect_equal(dim(result), c(3, 3, 3))
})

test_that(".nifti_write_neuroim2 roundtrips correctly", {
  skip_if_not_installed("neuroim2")

  tmpdir <- tempfile("neuroim2_write_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  arr <- array(as.numeric(1:8), dim = c(2, 2, 2))
  path <- file.path(tmpdir, "out.nii.gz")

  neurotabs:::.nifti_write_neuroim2(path, arr, logical_schema = NULL,
                                     template = NULL, source_ref = NULL)
  expect_true(file.exists(path))

  read_back <- neurotabs:::.nifti_resolve_neuroim2(path, NULL, NULL)
  expect_lt(max(abs(as.vector(arr) - as.vector(read_back))), 1e-4)
})
