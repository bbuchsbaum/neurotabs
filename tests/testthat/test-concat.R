test_that("nf_compatible detects compatible datasets", {
  ds <- .make_roi_nftab()
  result <- nf_compatible(ds, ds)
  expect_true(result$compatible)
})

test_that("nf_compatible detects schema mismatch", {
  ds1 <- .make_roi_nftab()

  # Build a second dataset with different feature shape
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE, semantic_role = "row_id"),
    subject = nf_col_schema("string", nullable = FALSE, semantic_role = "subject"),
    condition = nf_col_schema("string", nullable = FALSE, semantic_role = "condition"),
    group = nf_col_schema("string", nullable = FALSE, semantic_role = "group"),
    roi_1 = nf_col_schema("float32"),
    roi_2 = nf_col_schema("float32")
  )
  feat2 <- nf_feature(
    logical = nf_logical_schema("vector", "roi", "float32", shape = 2L),
    encodings = list(nf_columns_encoding(c("roi_1", "roi_2")))
  )
  m2 <- nf_manifest(
    dataset_id = "test2",
    row_id = "row_id",
    observation_axes = c("subject", "condition"),
    observation_columns = obs_cols,
    features = list(roi_beta = feat2)
  )
  obs2 <- data.frame(
    row_id = "r1", subject = "s1", condition = "A", group = "g",
    roi_1 = 0.1, roi_2 = 0.2, stringsAsFactors = FALSE
  )
  ds2 <- nftab(m2, obs2)

  result <- nf_compatible(ds1, ds2)
  expect_false(result$compatible)
  expect_true(any(grepl("schema mismatch", result$reasons)))
})

test_that("nf_concat produces valid result", {
  ds <- .make_roi_nftab()

  # Make a second dataset with different row_ids
  obs2 <- ds$observations
  obs2$row_id <- paste0(obs2$row_id, "_b")
  obs2$subject <- c("s03", "s03", "s04", "s04")
  ds2 <- nftab(ds$manifest, obs2)
  # Override dataset_id for provenance
  ds2$manifest$dataset_id <- "test-roi-b"

  merged <- nf_concat(ds, ds2)
  expect_s3_class(merged, "nftab")
  expect_equal(nf_nobs(merged), 8L)
  expect_true("source_dataset" %in% names(merged$observations))
})

test_that("nf_concat unions observation columns and feature encodings", {
  ds1 <- .make_roi_nftab()
  ds2 <- .make_alt_roi_nftab()

  merged <- nf_concat(ds1, ds2)

  expect_true(all(c("roi_1", "roi_2", "roi_3", "alt_1", "alt_2", "alt_3") %in%
                    names(merged$observations)))
  expect_equal(length(merged$manifest$features$roi_beta$encodings), 2L)
  expect_equal(nf_resolve(merged, "r5", "roi_beta"), c(0.9, 0.8, 0.7))
})

test_that("nf_concat rewrites colliding resource_ids and observation references", {
  ds1 <- .make_ref_nftab(
    dataset_id = "ref-a",
    resource_ids = c("shared", "res-a"),
    locators = c("maps/shared-a.nii.gz", "maps/a.nii.gz")
  )
  ds2 <- .make_ref_nftab(
    dataset_id = "ref-b",
    resource_ids = c("shared", "res-b"),
    locators = c("maps/shared-b.nii.gz", "maps/b.nii.gz")
  )
  ds2$observations$subject <- c("s3", "s4")

  merged <- nf_concat(ds1, ds2)

  expect_equal(anyDuplicated(merged$resources$resource_id), 0L)
  second_dataset_rows <- merged$observations$source_dataset == "ref-b"
  expect_true(any(grepl("^shared:", merged$observations$map_res[second_dataset_rows])))
  expect_true(any(grepl("^shared:", merged$resources$resource_id)))
})

test_that("nf_concat works with 3+ datasets", {
  ds <- .make_roi_nftab()
  obs2 <- ds$observations
  obs2$row_id <- paste0(obs2$row_id, "_b")
  obs2$subject <- c("s03", "s03", "s04", "s04")
  ds2 <- nftab(ds$manifest, obs2)
  ds2$manifest$dataset_id <- "ds-b"

  obs3 <- ds$observations
  obs3$row_id <- paste0(obs3$row_id, "_c")
  obs3$subject <- c("s05", "s05", "s06", "s06")
  ds3 <- nftab(ds$manifest, obs3)
  ds3$manifest$dataset_id <- "ds-c"

  merged <- nf_concat(ds, ds2, ds3)
  expect_equal(nf_nobs(merged), 12L)
  expect_equal(length(unique(merged$observations$source_dataset)), 3L)
})

test_that("nf_concat with provenance_col = NULL omits provenance", {
  ds <- .make_roi_nftab()
  obs2 <- ds$observations
  obs2$row_id <- paste0(obs2$row_id, "_b")
  obs2$subject <- c("s03", "s03", "s04", "s04")
  ds2 <- nftab(ds$manifest, obs2)

  merged <- nf_concat(ds, ds2, provenance_col = NULL)
  expect_false("source_dataset" %in% names(merged$observations))
})

test_that("nf_concat handles overlapping row_ids", {
  ds <- .make_roi_nftab()
  ds2 <- nftab(ds$manifest, ds$observations)  # same row_ids
  ds2$manifest$dataset_id <- "dup-ids"
  ds2$observations$subject <- c("s03", "s03", "s04", "s04")
  ds2$observations$condition <- c("faces", "houses", "faces", "houses")

  merged <- nf_concat(ds, ds2)
  expect_equal(anyDuplicated(merged$observations[[merged$manifest$row_id]]), 0L)
  expect_equal(nf_nobs(merged), 8L)
})

test_that("nf_compatible rejects different observation axes", {
  ds1 <- .make_roi_nftab()
  ds2 <- .make_roi_nftab()
  ds2$manifest$observation_axes <- "subject"  # different axes

  result <- nf_compatible(ds1, ds2)
  expect_false(result$compatible)
})

test_that("nf_compatible rejects different feature names", {
  ds1 <- .make_roi_nftab()
  ds2 <- .make_roi_nftab()
  names(ds2$manifest$features) <- "other_feat"

  result <- nf_compatible(ds1, ds2)
  expect_false(result$compatible)
})

test_that("nf_concat errors with single dataset", {
  ds <- .make_roi_nftab()
  expect_error(nf_concat(ds), "at least 2")
})
