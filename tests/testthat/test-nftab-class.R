test_that("nftab constructs correctly", {
  ds <- .make_roi_nftab()
  expect_s3_class(ds, "nftab")
  expect_equal(nf_nobs(ds), 4L)
  expect_equal(nf_feature_names(ds), "roi_beta")
  expect_equal(nf_axes(ds), c("subject", "condition"))
})

test_that("feature and axis accessors return public metadata views", {
  ds <- .make_labeled_roi_nftab()
  feature_name <- "roi_beta"

  schema <- nf_feature_schema(ds, roi_beta)
  expect_s3_class(schema, "nf_logical_schema")
  expect_equal(schema$axes, "roi")

  axis_info <- nf_axis_info(ds, roi_beta, "roi")
  expect_s3_class(axis_info, "nf_axis_domain")
  expect_equal(axis_info$id, "demo-atlas")
  expect_null(axis_info$size)

  labels <- nf_axis_labels(ds, feature_name, "roi")
  expect_equal(names(labels), c("index", "label"))
  expect_equal(labels$label, c("roi_1", "roi_2", "roi_3"))
})

test_that("extension accessors return manifest extension data", {
  ds <- .make_masked_volume_nftab()

  ext <- nf_extensions(ds)
  expect_true("x-masked-volume" %in% names(ext))
  expect_identical(nf_extension(ds, "x-masked-volume"), ext[["x-masked-volume"]])
})

test_that("nftab rejects duplicate row_ids", {
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE),
    subject = nf_col_schema("string", nullable = FALSE)
  )
  feat <- nf_feature(
    logical = nf_logical_schema("vector", "roi", "float32", shape = 1L),
    encodings = list(nf_columns_encoding("roi_1"))
  )
  # Add roi_1 to obs_cols so manifest is valid
  obs_cols$roi_1 <- nf_col_schema("float32")
  m <- nf_manifest(
    dataset_id = "dup",
    row_id = "row_id",
    observation_axes = "subject",
    observation_columns = obs_cols,
    features = list(x = feat)
  )
  obs <- data.frame(row_id = c("a", "a"), subject = c("s1", "s2"),
                    roi_1 = c(1, 2), stringsAsFactors = FALSE)
  expect_error(nftab(m, obs), "duplicate")
})

test_that("nftab rejects non-unique axes tuples", {
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE),
    subject = nf_col_schema("string", nullable = FALSE),
    roi_1 = nf_col_schema("float32")
  )
  feat <- nf_feature(
    logical = nf_logical_schema("vector", "roi", "float32", shape = 1L),
    encodings = list(nf_columns_encoding("roi_1"))
  )
  m <- nf_manifest(
    dataset_id = "dup-ax",
    row_id = "row_id",
    observation_axes = "subject",
    observation_columns = obs_cols,
    features = list(x = feat)
  )
  obs <- data.frame(row_id = c("a", "b"), subject = c("s1", "s1"),
                    roi_1 = c(1, 2), stringsAsFactors = FALSE)
  expect_error(nftab(m, obs), "not unique")
})

test_that("[.nftab subsets rows", {
  ds <- .make_roi_nftab()
  sub <- ds[1:2]
  expect_equal(nf_nobs(sub), 2L)
  expect_s3_class(sub, "nftab")
})

test_that("print methods produce output without error", {
  ds <- .make_roi_nftab()
  expect_output(print(ds), "nftab")
  expect_output(print(ds), "observations")
  expect_output(print(ds$manifest), "nf_manifest")
  expect_output(print(ds$manifest), "features")

  feat <- ds$manifest$features$roi_beta
  expect_output(print(feat), "nf_feature")
  expect_output(print(feat), "encodings")
})

test_that("nf_design returns observation data.frame", {
  ds <- .make_roi_nftab()
  d <- nf_design(ds)
  expect_s3_class(d, "data.frame")
  expect_equal(nrow(d), 4L)
})

test_that("nf_supports returns support list", {
  ds <- .make_ref_nftab()
  supports <- nf_supports(ds)
  expect_true(is.list(supports))
  expect_true("test_grid" %in% names(supports))
})

test_that("nf_support_info retrieves a support descriptor", {
  ds <- .make_ref_nftab()
  info <- nf_support_info(ds, "test_grid")
  expect_s3_class(info, "nf_support_schema")
  expect_equal(info$support_id, "test-grid-2x2x2")
})

test_that("nf_support_info errors on unknown ref", {
  ds <- .make_roi_nftab()  # no supports
  expect_error(nf_support_info(ds, "no_such_ref"), "unknown support")
})

test_that("nf_extension errors on unknown key", {
  ds <- .make_roi_nftab()  # no extensions
  expect_error(nf_extension(ds, "x-missing"), "unknown extension")
})

test_that("nf_feature_schema errors on unknown feature", {
  ds <- .make_roi_nftab()
  expect_error(nf_feature_schema(ds, "nonexistent"), "unknown feature")
})

test_that("nf_axis_info errors on unknown axis", {
  ds <- .make_labeled_roi_nftab()
  expect_error(nf_axis_info(ds, "roi_beta", "bad_axis"), "no axis")
})

test_that("nf_axis_info errors when no axis_domains", {
  ds <- .make_roi_nftab()  # no axis_domains
  expect_error(nf_axis_info(ds, "roi_beta", "roi"), "no axis metadata")
})

test_that("nf_axis_labels errors without root", {
  # Build a dataset with axis_domains but no .root
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE),
    subject = nf_col_schema("string", nullable = FALSE),
    roi_1 = nf_col_schema("float32")
  )
  logical <- nf_logical_schema(
    "vector", "roi", "float32", shape = 1L,
    axis_domains = list(roi = nf_axis_domain(id = "a", labels = "labels.tsv"))
  )
  feat <- nf_feature(logical = logical, encodings = list(nf_columns_encoding("roi_1")))
  m <- nf_manifest(
    dataset_id = "no-root",
    row_id = "row_id",
    observation_axes = "subject",
    observation_columns = obs_cols,
    features = list(f = feat)
  )
  obs <- data.frame(row_id = "r1", subject = "s1", roi_1 = 1.0, stringsAsFactors = FALSE)
  ds <- nftab(m, obs)  # no .root
  expect_error(nf_axis_labels(ds, "f", "roi"), "root is unknown")
})

test_that("nf_manifest rejects invalid extension keys", {
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE),
    subject = nf_col_schema("string", nullable = FALSE)
  )
  feat <- nf_feature(
    logical = nf_logical_schema("vector", "roi", "float32", shape = 1L),
    encodings = list(nf_ref_encoding(backend = "x-test", locator = "f.bin"))
  )
  obs_cols$f <- nf_col_schema("float32")  # not used but needed for encoding check skipped
  expect_error(
    nf_manifest(
      dataset_id = "ext-test",
      row_id = "row_id",
      observation_axes = "subject",
      observation_columns = list(
        row_id = nf_col_schema("string", nullable = FALSE),
        subject = nf_col_schema("string", nullable = FALSE)
      ),
      features = list(f = feat),
      extensions = list("bad_key" = list())
    ),
    "x-"
  )
})

test_that("nf_manifest rejects missing support_refs", {
  feat <- nf_feature(
    logical = nf_logical_schema("volume", c("x", "y", "z"), "float32",
                                support_ref = "missing_sup"),
    encodings = list(nf_ref_encoding(backend = "nifti", locator = "f.nii.gz"))
  )
  expect_error(
    nf_manifest(
      dataset_id = "missing-sup",
      row_id = "row_id",
      observation_axes = "subject",
      observation_columns = list(
        row_id = nf_col_schema("string", nullable = FALSE),
        subject = nf_col_schema("string", nullable = FALSE)
      ),
      features = list(vol = feat)
    ),
    "supports"
  )
})

test_that("nf_manifest rejects feature with columns encoding referencing undeclared column", {
  feat <- nf_feature(
    logical = nf_logical_schema("vector", "roi", "float32", shape = 1L),
    encodings = list(nf_columns_encoding("not_declared"))
  )
  expect_error(
    nf_manifest(
      dataset_id = "bad-col",
      row_id = "row_id",
      observation_axes = "subject",
      observation_columns = list(
        row_id = nf_col_schema("string", nullable = FALSE),
        subject = nf_col_schema("string", nullable = FALSE)
      ),
      features = list(f = feat)
    ),
    "undeclared columns"
  )
})

test_that("print.nftab shows resources count when present", {
  ds <- .make_ref_nftab()
  out <- capture.output(print(ds))
  expect_true(any(grepl("resources", out)))
})

test_that("nf_feature print shows description and nullable flag", {
  feat <- nf_feature(
    logical = nf_logical_schema("vector", "roi", "float32", shape = 3L),
    encodings = list(nf_columns_encoding(c("a", "b", "c"))),
    nullable = TRUE,
    description = "my feature"
  )
  out <- capture.output(print(feat))
  expect_true(any(grepl("my feature", out)))
  expect_true(any(grepl("nullable", out)))
})

test_that("nf_manifest with primary_feature", {
  ds <- .make_roi_nftab()
  m <- ds$manifest
  m2 <- nf_manifest(
    dataset_id = m$dataset_id, row_id = m$row_id,
    observation_axes = m$observation_axes,
    observation_columns = m$observation_columns,
    features = m$features,
    primary_feature = "roi_beta"
  )
  expect_equal(m2$primary_feature, "roi_beta")
})

test_that("nf_manifest rejects invalid primary_feature", {
  ds <- .make_roi_nftab()
  m <- ds$manifest
  expect_error(
    nf_manifest(
      dataset_id = m$dataset_id, row_id = m$row_id,
      observation_axes = m$observation_axes,
      observation_columns = m$observation_columns,
      features = m$features,
      primary_feature = "nonexistent"
    ),
    "primary_feature"
  )
})

test_that("nf_feature infers shape from columns encoding", {
  logical <- nf_logical_schema("vector", "roi", "float32")
  feat <- nf_feature(
    logical = logical,
    encodings = list(nf_columns_encoding(c("a", "b", "c")))
  )
  expect_equal(feat$logical$shape, 3L)
})

test_that("nf_feature rejects columns encoding on multi-axis logical", {
  logical <- nf_logical_schema("array", c("x", "y"), "float32")
  expect_error(
    nf_feature(logical = logical, encodings = list(nf_columns_encoding(c("a", "b")))),
    "1D"
  )
})

test_that("print.nftab truncates many unique axis values", {
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE),
    subject = nf_col_schema("string", nullable = FALSE),
    roi_1 = nf_col_schema("float32")
  )
  feat <- nf_feature(
    logical = nf_logical_schema("vector", "roi", "float32", shape = 1L),
    encodings = list(nf_columns_encoding("roi_1"))
  )
  m <- nf_manifest(
    dataset_id = "many-subjects", row_id = "row_id",
    observation_axes = "subject",
    observation_columns = obs_cols,
    features = list(f = feat)
  )
  obs <- data.frame(
    row_id = paste0("r", 1:10),
    subject = paste0("s", 1:10),
    roi_1 = 1:10,
    stringsAsFactors = FALSE
  )
  ds <- nftab(m, obs)
  out <- capture.output(print(ds))
  expect_true(any(grepl("unique", out)))
})

test_that("nftab rejects resources with missing required columns", {
  ds <- .make_ref_nftab()
  bad_res <- data.frame(resource_id = "r1", stringsAsFactors = FALSE)
  expect_error(nftab(ds$manifest, ds$observations, resources = bad_res), "missing columns")
})

test_that("nf_manifest with import_recipe", {
  ds <- .make_roi_nftab()
  m <- ds$manifest
  m2 <- nf_manifest(
    dataset_id = m$dataset_id, row_id = m$row_id,
    observation_axes = m$observation_axes,
    observation_columns = m$observation_columns,
    features = m$features,
    import_recipe = list(source = "bids", version = "1.0")
  )
  expect_equal(m2$import_recipe$source, "bids")
})

test_that("nf_manifest ref encoding undeclared column error", {
  feat <- nf_feature(
    logical = nf_logical_schema("vector", "roi", "float32", shape = 1L),
    encodings = list(nf_ref_encoding(resource_id = nf_col("undeclared_col")))
  )
  expect_error(
    nf_manifest(
      dataset_id = "bad", row_id = "row_id",
      observation_axes = "subject",
      observation_columns = list(
        row_id = nf_col_schema("string", nullable = FALSE),
        subject = nf_col_schema("string", nullable = FALSE)
      ),
      features = list(f = feat)
    ),
    "undeclared column"
  )
})
