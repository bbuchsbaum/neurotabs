test_that("nf_resolve resolves columns encoding", {
  ds <- .make_roi_nftab()
  val <- nf_resolve(ds, 1L, "roi_beta")
  expect_equal(val, c(0.3, 0.4, 0.3))

  val2 <- nf_resolve(ds, "r3", "roi_beta")
  expect_equal(val2, c(0.4, 0.5, 0.4))
})

test_that("nf_resolve_all returns named list", {
  ds <- .make_roi_nftab()
  all_vals <- nf_resolve_all(ds, "roi_beta")
  expect_length(all_vals, 4L)
  expect_equal(names(all_vals), c("r1", "r2", "r3", "r4"))
  expect_equal(all_vals[["r1"]], c(0.3, 0.4, 0.3))
})

test_that("feature resolvers accept bare symbols and string variables", {
  ds <- .make_roi_nftab()
  feature_name <- "roi_beta"

  expect_equal(nf_resolve(ds, 1L, roi_beta), nf_resolve(ds, 1L, "roi_beta"))
  expect_equal(nf_resolve(ds, "r3", feature_name), nf_resolve(ds, "r3", "roi_beta"))
  expect_equal(nf_resolve_all(ds, roi_beta), nf_resolve_all(ds, "roi_beta"))
})

test_that("nf_resolve errors on unknown feature", {
  ds <- .make_roi_nftab()
  expect_error(nf_resolve(ds, 1L, "nonexistent"), "unknown feature")
})

test_that("nf_resolve errors on unknown row_id", {
  ds <- .make_roi_nftab()
  expect_error(nf_resolve(ds, "no_such_id", "roi_beta"), "not found")
})

test_that("nf_resolve preserves logical dtype for columns encodings", {
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE),
    subject = nf_col_schema("string", nullable = FALSE),
    flag_1 = nf_col_schema("bool", nullable = FALSE),
    flag_2 = nf_col_schema("bool", nullable = FALSE)
  )

  feat <- nf_feature(
    logical = nf_logical_schema("vector", "feature", "bool", shape = 2L),
    encodings = list(nf_columns_encoding(c("flag_1", "flag_2")))
  )

  manifest <- nf_manifest(
    dataset_id = "bool-columns",
    row_id = "row_id",
    observation_axes = "subject",
    observation_columns = obs_cols,
    features = list(flags = feat)
  )

  observations <- data.frame(
    row_id = "r1",
    subject = "s1",
    flag_1 = TRUE,
    flag_2 = FALSE,
    stringsAsFactors = FALSE
  )

  ds <- nftab(manifest, observations)
  val <- nf_resolve(ds, 1L, "flags")
  expect_type(val, "logical")
  expect_equal(val, c(TRUE, FALSE))
})

test_that("nf_resolve_all with .progress does not error", {
  ds <- .make_roi_nftab()
  # Redirect messages so they don't pollute output; just verify no error
  expect_no_error(
    suppressMessages(nf_resolve_all(ds, "roi_beta", .progress = TRUE))
  )
})

test_that(".coerce_columns_value handles string dtype", {
  result <- neurotabs:::.coerce_columns_value(c("a", "b"), "string")
  expect_type(result, "character")
})

test_that(".coerce_columns_value handles bool dtype with numeric input", {
  result <- neurotabs:::.coerce_columns_value(c(1, 0, 1), "bool")
  expect_type(result, "logical")
  expect_equal(result, c(TRUE, FALSE, TRUE))
})

test_that(".coerce_columns_value handles bool dtype with character input", {
  result <- neurotabs:::.coerce_columns_value(c("TRUE", "false", "1", "0"), "bool")
  expect_type(result, "logical")
  expect_equal(result, c(TRUE, FALSE, TRUE, FALSE))
})

test_that(".coerce_columns_value errors on invalid bool numeric values", {
  expect_error(
    neurotabs:::.coerce_columns_value(c(0, 2), "bool"),
    "\\{0, 1\\}"
  )
})

test_that(".coerce_columns_value errors on invalid bool string values", {
  expect_error(
    neurotabs:::.coerce_columns_value(c("yes", "no"), "bool"),
    "TRUE/FALSE"
  )
})

test_that(".coerce_columns_value handles int32 dtype", {
  result <- neurotabs:::.coerce_columns_value(c(1, 2, 3), "int32")
  expect_type(result, "integer")
})

test_that(".coerce_columns_value errors on non-integer values for int32", {
  expect_error(
    neurotabs:::.coerce_columns_value(c(1.5, 2.0), "int32"),
    "whole finite"
  )
})

test_that(".coerce_columns_value handles int64 dtype", {
  result <- neurotabs:::.coerce_columns_value(c(100, 200), "int64")
  expect_type(result, "double")
  expect_equal(result, c(100, 200))
})

test_that(".coerce_columns_value errors on non-integer values for int64", {
  expect_error(
    neurotabs:::.coerce_columns_value(c(1.1), "int64"),
    "whole finite"
  )
})

test_that(".parse_checksum_token parses prefixed tokens", {
  tok <- neurotabs:::.parse_checksum_token(paste0("md5:", strrep("a", 32)))
  expect_equal(tok$algo, "md5")
  expect_equal(tok$value, strrep("a", 32))
})

test_that(".parse_checksum_token auto-detects md5 by length 32", {
  tok <- neurotabs:::.parse_checksum_token(strrep("b", 32))
  expect_equal(tok$algo, "md5")
})

test_that(".parse_checksum_token auto-detects sha1 by length 40", {
  tok <- neurotabs:::.parse_checksum_token(strrep("c", 40))
  expect_equal(tok$algo, "sha1")
})

test_that(".parse_checksum_token auto-detects sha256 by length 64", {
  tok <- neurotabs:::.parse_checksum_token(strrep("d", 64))
  expect_equal(tok$algo, "sha256")
})

test_that(".parse_checksum_token errors on unknown length", {
  expect_error(
    neurotabs:::.parse_checksum_token(strrep("e", 10)),
    "unsupported"
  )
})

test_that(".parse_checksum_token errors on non-hex characters", {
  expect_error(
    neurotabs:::.parse_checksum_token(paste0("md5:", strrep("z", 32))),
    "hexadecimal"
  )
})

test_that(".parse_checksum_token errors on wrong-length prefixed token", {
  expect_error(
    neurotabs:::.parse_checksum_token(paste0("md5:", strrep("a", 10))),
    "wrong length"
  )
})

test_that(".validate_resolved_dtype checks float dtypes", {
  expect_no_error(neurotabs:::.validate_resolved_dtype(c(1.0, 2.0), "float32"))
  expect_no_error(neurotabs:::.validate_resolved_dtype(c(1.0, 2.0), "float64"))
  expect_error(neurotabs:::.validate_resolved_dtype(c("a", "b"), "float32"), "floating")
})

test_that(".validate_resolved_dtype checks bool dtype", {
  expect_no_error(neurotabs:::.validate_resolved_dtype(c(TRUE, FALSE), "bool"))
  expect_error(neurotabs:::.validate_resolved_dtype(c(1L, 0L), "bool"), "bool")
})

test_that(".validate_resolved_dtype checks string dtype", {
  expect_no_error(neurotabs:::.validate_resolved_dtype(c("a", "b"), "string"))
  expect_error(neurotabs:::.validate_resolved_dtype(c(1.0), "string"), "string")
})

test_that(".validate_resolved_dtype checks int32 bounds", {
  expect_no_error(neurotabs:::.validate_resolved_dtype(c(0L, 100L), "int32"))
  expect_error(neurotabs:::.validate_resolved_dtype(2147483648, "int32"), "maximum")
  expect_error(neurotabs:::.validate_resolved_dtype(-2147483649, "int32"), "minimum")
})

test_that(".validate_resolved_dtype checks uint8 bounds", {
  expect_no_error(neurotabs:::.validate_resolved_dtype(c(0, 255), "uint8"))
  expect_error(neurotabs:::.validate_resolved_dtype(c(256), "uint8"), "maximum")
  expect_error(neurotabs:::.validate_resolved_dtype(c(-1), "uint8"), "minimum")
})

test_that(".validate_resolved_dtype checks uint16 bounds", {
  expect_no_error(neurotabs:::.validate_resolved_dtype(c(0, 65535), "uint16"))
  expect_error(neurotabs:::.validate_resolved_dtype(c(65536), "uint16"), "maximum")
})

test_that(".validate_resolved checks multi-axis shape", {
  arr <- array(1:8, dim = c(2, 2, 2))
  schema <- nf_logical_schema("volume", c("x", "y", "z"), "float32",
                              shape = c(2L, 2L, 2L), support_ref = "g")
  expect_no_error(neurotabs:::.validate_resolved(arr, schema))

  arr_bad <- array(1:27, dim = c(3, 3, 3))
  expect_error(neurotabs:::.validate_resolved(arr_bad, schema), "shape")
})

test_that(".materialize_ref errors when resource_id used but no registry", {
  binding <- list(
    resource_id = "res1",
    backend = NULL,
    locator = NULL,
    selector = NULL,
    checksum = NULL
  )
  row <- list()
  expect_error(
    neurotabs:::.materialize_ref(binding, row, resources = NULL),
    "no resource registry"
  )
})

test_that(".materialize_ref errors on unknown resource_id", {
  binding <- list(
    resource_id = "missing_res",
    backend = NULL,
    locator = NULL,
    selector = NULL,
    checksum = NULL
  )
  row <- list()
  resources <- data.frame(resource_id = "other", backend = "nifti",
                          locator = "f.nii", stringsAsFactors = FALSE)
  expect_error(
    neurotabs:::.materialize_ref(binding, row, resources = resources),
    "unknown resource_id"
  )
})

test_that("nf_resolve validates resource checksum before backend dispatch", {
  tmpdir <- tempfile("nftab_checksum_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  resource_path <- file.path(tmpdir, "payload.bin")
  writeBin(as.raw(c(1, 2, 3, 4)), resource_path)

  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE),
    subject = nf_col_schema("string", nullable = FALSE),
    condition = nf_col_schema("string", nullable = FALSE),
    res_id = nf_col_schema("string", nullable = FALSE)
  )

  feat <- nf_feature(
    logical = nf_logical_schema(
      "volume",
      c("x", "y", "z"),
      "float32",
      shape = c(1L, 1L, 1L),
      support_ref = "checksum_grid"
    ),
    encodings = list(nf_ref_encoding(resource_id = nf_col("res_id")))
  )

  manifest <- nf_manifest(
    dataset_id = "checksum-demo",
    row_id = "row_id",
    observation_axes = c("subject", "condition"),
    observation_columns = obs_cols,
    features = list(statmap = feat),
    supports = list(
      checksum_grid = nf_support_volume(
        support_id = "checksum-grid-1x1x1",
        space = "MNI152NLin2009cAsym",
        grid_id = "checksum-grid-1x1x1"
      )
    ),
    resources_path = "resources.csv",
    resources_format = "csv"
  )

  observations <- data.frame(
    row_id = "r1",
    subject = "s1",
    condition = "faces",
    res_id = "res1",
    stringsAsFactors = FALSE
  )

  resources <- data.frame(
    resource_id = "res1",
    backend = "x-unknown",
    locator = resource_path,
    checksum = "md5:00000000000000000000000000000000",
    stringsAsFactors = FALSE
  )

  ds <- nftab(manifest, observations, resources = resources, .root = tmpdir)
  expect_error(nf_resolve(ds, 1L, "statmap"), "checksum mismatch")
})
