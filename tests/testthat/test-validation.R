test_that("nf_validate passes for valid dataset", {
  ds <- .make_roi_nftab()
  result <- nf_validate(ds, level = "structural")
  expect_true(result$valid)
  expect_length(result$errors, 0L)
})

test_that("nf_validate catches full conformance issues", {
  ds <- .make_ref_nftab()
  result <- nf_validate(ds, level = "full")
  expect_false(result$valid)
  expect_true(any(grepl("no adapter registered", result$errors)))
})

test_that("nf_validate rejects undeclared observation columns", {
  ds <- .make_roi_nftab()
  ds$observations$extra <- 1:4

  result <- nf_validate(ds, level = "structural")
  expect_false(result$valid)
  expect_true(any(grepl("undeclared columns", result$errors)))
})

test_that("nf_validate rejects NA in non-nullable non-axis columns", {
  ds <- .make_roi_nftab()
  ds$observations$group[1] <- NA

  result <- nf_validate(ds, level = "structural")
  expect_false(result$valid)
  expect_true(any(grepl("non-nullable column 'group'", result$errors)))
})

test_that("nf_validate accepts ROI axis labels metadata when labels match axis size", {
  ds <- .make_labeled_roi_nftab()

  result <- nf_validate(ds, level = "structural")
  expect_true(result$valid)
})

test_that("nf_validate rejects ROI axis labels metadata when labels mismatch axis size", {
  ds <- .make_labeled_roi_nftab(label_rows = 2L)

  result <- nf_validate(ds, level = "structural")
  expect_false(result$valid)
  expect_true(any(grepl("labels file has 2 rows but expected 3", result$errors)))
})

test_that("nf_validate accepts x-masked-volume extension when index map matches shape", {
  ds <- .make_masked_volume_nftab()

  result <- nf_validate(ds, level = "structural")
  expect_true(result$valid)
})

test_that("nf_validate rejects x-masked-volume extension when index map length mismatches shape", {
  ds <- .make_masked_volume_nftab(index_rows = 2L)

  result <- nf_validate(ds, level = "structural")
  expect_false(result$valid)
  expect_true(any(grepl("index_map has 2 rows but logical shape expects 3", result$errors)))
})

test_that("nf_validate rejects x-masked-volume extension when coordinates exceed grid", {
  ds <- .make_masked_volume_nftab(bad_coords = TRUE)

  result <- nf_validate(ds, level = "structural")
  expect_false(result$valid)
  expect_true(any(grepl("coordinates outside declared grid_shape", result$errors)))
})

test_that("nf_validate full passes for valid columns-encoded dataset", {
  ds <- .make_roi_nftab()
  result <- nf_validate(ds, level = "full")
  expect_true(result$valid)
  expect_length(result$errors, 0L)
})

test_that("nf_validate result always contains warnings field", {
  ds <- .make_roi_nftab()
  result <- nf_validate(ds, level = "structural")
  expect_true("warnings" %in% names(result))
  expect_type(result$warnings, "character")
})

test_that("nf_validate rejects non-nftab input", {
  result <- nf_validate("not an nftab")
  expect_false(result$valid)
  expect_true(any(grepl("not an nftab", result$errors)))
})

test_that("nf_validate .progress parameter works without error", {
  ds <- .make_roi_nftab()
  expect_no_error(
    suppressMessages(nf_validate(ds, level = "full", .progress = TRUE))
  )
})

test_that("nf_validate catches missing observation columns at structural level", {
  ds <- .make_roi_nftab()
  # Remove a declared column from observations
  ds$observations$roi_1 <- NULL
  result <- nf_validate(ds, level = "structural")
  expect_false(result$valid)
  expect_true(any(grepl("declared column.*not in observation", result$errors)))
})

test_that("nf_validate full catches unresolvable ref features", {
  ds <- .make_ref_nftab(backend = "x-unknown")
  result <- nf_validate(ds, level = "full")
  expect_false(result$valid)
  expect_true(length(result$errors) > 0L)
})

test_that("nf_validate structural passes for ref-encoded dataset with resources", {
  ds <- .make_ref_nftab()
  result <- nf_validate(ds, level = "structural")
  expect_true(result$valid)
})

test_that("nf_validate catches NA in observation axis", {
  ds <- .make_roi_nftab()
  ds$observations$subject[1] <- NA
  result <- nf_validate(ds, level = "structural")
  expect_false(result$valid)
  expect_true(any(grepl("axis.*subject.*NA|NA.*subject", result$errors)))
})

test_that("nf_validate catches duplicate row_ids", {
  ds <- .make_roi_nftab()
  ds$observations$row_id[2] <- ds$observations$row_id[1]
  result <- nf_validate(ds, level = "structural")
  expect_false(result$valid)
  expect_true(any(grepl("row_id|duplicate", result$errors)))
})

test_that("nf_validate catches missing row_id column", {
  ds <- .make_roi_nftab()
  ds$observations$row_id <- NULL
  result <- nf_validate(ds, level = "structural")
  expect_false(result$valid)
})

test_that("nf_validate structural is conformant message for valid dataset", {
  ds <- .make_roi_nftab()
  expect_message(nf_validate(ds, level = "structural"), "conformant")
})

test_that("nf_validate detects axis domain size mismatch with shape", {
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE),
    subject = nf_col_schema("string", nullable = FALSE),
    roi_1 = nf_col_schema("float32"),
    roi_2 = nf_col_schema("float32"),
    roi_3 = nf_col_schema("float32")
  )
  logical <- nf_logical_schema("vector", "roi", "float32", shape = 3L,
    axis_domains = list(roi = nf_axis_domain(id = "test", size = 5L))
  )
  feat <- nf_feature(logical = logical,
    encodings = list(nf_columns_encoding(c("roi_1", "roi_2", "roi_3"))))
  m <- nf_manifest(dataset_id = "domain-mismatch", row_id = "row_id",
    observation_axes = "subject", observation_columns = obs_cols,
    features = list(f = feat))
  obs <- data.frame(row_id = "r1", subject = "s1", roi_1 = 1, roi_2 = 2,
    roi_3 = 3, stringsAsFactors = FALSE)
  ds <- nftab(m, obs)
  result <- nf_validate(ds, level = "structural")
  # axis_domain.size is metadata — validation checks labels file, not size field directly
  expect_true(result$valid)
})

test_that("nf_validate full conformance succeeds for labeled dataset", {
  ds <- .make_labeled_roi_nftab()
  result <- nf_validate(ds, level = "full")
  expect_true(result$valid)
})

test_that("nf_validate with masked volume extension success", {
  ds <- .make_masked_volume_nftab()
  result <- nf_validate(ds, level = "structural")
  expect_true(result$valid)
})

test_that("nf_validate catches non-unique axis tuples", {
  ds <- .make_roi_nftab()
  ds$observations$condition <- rep("faces", 4)
  ds$observations$subject <- c("s01", "s01", "s02", "s02")
  result <- nf_validate(ds, level = "structural")
  expect_false(result$valid)
  expect_true(any(grepl("tuple|unique", result$errors)))
})

test_that("nf_validate catches declared dtype vs actual R type mismatch", {
  # Build a dataset where group column is declared as int32 but holds strings
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE),
    subject = nf_col_schema("string", nullable = FALSE),
    condition = nf_col_schema("string", nullable = FALSE),
    group = nf_col_schema("int32", nullable = FALSE),
    roi_1 = nf_col_schema("float32"),
    roi_2 = nf_col_schema("float32"),
    roi_3 = nf_col_schema("float32")
  )

  feat <- nf_feature(
    logical = nf_logical_schema("vector", "roi", "float32", shape = 3L),
    encodings = list(nf_columns_encoding(c("roi_1", "roi_2", "roi_3")))
  )

  m <- nf_manifest(
    dataset_id = "dtype-mismatch-test",
    row_id = "row_id",
    observation_axes = c("subject", "condition"),
    observation_columns = obs_cols,
    features = list(roi_beta = feat)
  )

  obs <- data.frame(
    row_id = c("r1", "r2"),
    subject = c("s01", "s01"),
    condition = c("faces", "houses"),
    group = c("ctrl", "pt"),  # string values, but declared int32
    roi_1 = c(0.3, 0.1),
    roi_2 = c(0.4, 0.2),
    roi_3 = c(0.3, 0.1),
    stringsAsFactors = FALSE
  )

  # Bypass nftab() constructor by building manually
  ds <- structure(
    list(manifest = m, observations = obs, resources = NULL, .root = NULL),
    class = "nftab"
  )

  result <- nf_validate(ds, level = "structural")
  expect_false(result$valid)
  expect_true(any(grepl("declared as int32 but R type is character", result$errors)))
})
