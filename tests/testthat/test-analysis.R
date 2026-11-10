.make_analysis_roi_nftab <- function() {
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE, semantic_role = "row_id"),
    subject = nf_col_schema("string", nullable = FALSE, semantic_role = "subject"),
    group = nf_col_schema("string", nullable = FALSE, semantic_role = "group", levels = c("ctrl", "pt")),
    condition = nf_col_schema("string", nullable = FALSE, semantic_role = "condition", levels = c("faces", "houses")),
    roi_1 = nf_col_schema("float32"),
    roi_2 = nf_col_schema("float32")
  )

  feat <- nf_feature(
    logical = nf_logical_schema("vector", "roi", "float32", shape = 2L),
    encodings = list(nf_columns_encoding(c("roi_1", "roi_2")))
  )

  manifest <- nf_manifest(
    dataset_id = "analysis-roi",
    row_id = "row_id",
    observation_axes = c("subject", "condition"),
    observation_columns = obs_cols,
    features = list(roi_beta = feat)
  )

  observations <- data.frame(
    row_id = paste0("r", seq_len(8L)),
    subject = rep(c("s01", "s02", "s03", "s04"), each = 2L),
    group = rep(c("ctrl", "ctrl", "pt", "pt"), each = 2L),
    condition = rep(c("faces", "houses"), times = 4L),
    roi_1 = c(1, 2, 1.5, 2.5, 3, 5, 3.5, 5.5),
    roi_2 = c(2, 3, 2.5, 3.5, 4, 6, 4.5, 6.5),
    stringsAsFactors = FALSE
  )

  nftab(manifest = manifest, observations = observations)
}

.make_fixed_roi_nftab <- function() {
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE, semantic_role = "row_id"),
    subject = nf_col_schema("string", nullable = FALSE, semantic_role = "subject"),
    group = nf_col_schema("string", nullable = FALSE, semantic_role = "group", levels = c("ctrl", "pt")),
    age = nf_col_schema("float64", nullable = FALSE, semantic_role = "covariate"),
    roi_1 = nf_col_schema("float32"),
    roi_2 = nf_col_schema("float32")
  )

  feat <- nf_feature(
    logical = nf_logical_schema("vector", "roi", "float32", shape = 2L),
    encodings = list(nf_columns_encoding(c("roi_1", "roi_2")))
  )

  manifest <- nf_manifest(
    dataset_id = "analysis-fixed-roi",
    row_id = "row_id",
    observation_axes = "subject",
    observation_columns = obs_cols,
    features = list(roi_beta = feat)
  )

  observations <- data.frame(
    row_id = paste0("r", seq_len(6L)),
    subject = paste0("s", sprintf("%02d", seq_len(6L))),
    group = c("ctrl", "ctrl", "ctrl", "pt", "pt", "pt"),
    age = c(20, 24, 28, 21, 25, 29),
    roi_1 = c(1, 1.2, 1.1, 3.0, 3.1, 2.9),
    roi_2 = c(2, 2.1, 2.2, 4.2, 4.0, 4.1),
    stringsAsFactors = FALSE
  )

  nftab(manifest = manifest, observations = observations)
}

.make_analysis_nifti_ds <- function(tmpdir, volumes, rows) {
  dir.create(tmpdir, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(tmpdir, "maps"), showWarnings = FALSE)

  nifti_path <- file.path(tmpdir, "maps", "stats.nii.gz")
  RNifti::writeNifti(volumes, nifti_path)

  obs_cols <- list(
    row_id = list(dtype = "string", nullable = FALSE),
    subject = list(dtype = "string", nullable = FALSE),
    group = list(dtype = "string", nullable = FALSE),
    condition = list(dtype = "string", nullable = FALSE),
    stat_res = list(dtype = "string", nullable = FALSE),
    stat_sel = list(dtype = "json", nullable = FALSE)
  )

  yaml::write_yaml(
    list(
      spec_version = "0.1.0",
      dataset_id = "analysis-nifti",
      storage_profile = "table-package",
      observation_table = list(path = "observations.csv", format = "csv"),
      row_id = "row_id",
      observation_axes = list("subject", "condition"),
      observation_columns = obs_cols,
      features = list(
        statmap = list(
          logical = list(
            kind = "volume",
            axes = list("x", "y", "z"),
            dtype = "float32",
            support_ref = "analysis_grid",
            shape = as.list(dim(volumes)[seq_len(3L)]),
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
        analysis_grid = list(
          support_type = "volume",
          support_id = sprintf("analysis-grid-%s", paste(dim(volumes)[seq_len(3L)], collapse = "x")),
          space = "MNI152NLin2009cAsym",
          grid_id = sprintf("analysis-grid-%s", paste(dim(volumes)[seq_len(3L)], collapse = "x"))
        )
      ),
      resources = list(path = "resources.csv", format = "csv")
    ),
    file.path(tmpdir, "nftab.yaml")
  )

  data.table::fwrite(rows, file.path(tmpdir, "observations.csv"))
  data.table::fwrite(
    data.frame(
      resource_id = "stats",
      backend = "nifti",
      locator = "maps/stats.nii.gz",
      checksum = paste0("md5:", digest::digest(file = nifti_path, algo = "md5", serialize = FALSE)),
      stringsAsFactors = FALSE
    ),
    file.path(tmpdir, "resources.csv")
  )

  nf_read(file.path(tmpdir, "nftab.yaml"))
}

test_that("nf_analyze fixed mode errors on repeated subject rows", {
  ds <- .make_analysis_roi_nftab()

  expect_error(
    nf_analyze(ds, "roi_beta", ~ group * condition),
    "repeated subject rows"
  )
})

test_that("nf_analyze fixed mode returns nftab for independent ROI rows", {
  ds <- .make_fixed_roi_nftab()

  result <- nf_analyze(ds, "roi_beta", ~ group + age)

  expect_s3_class(result, "nftab")
  expect_equal(nf_nobs(result), 2L)
  expect_true(all(c("stat", "p_value", "estimate") %in% nf_feature_names(result)))
  expect_equal(result$observations$term, c("group", "age"))

  stat_mat <- nf_collect(result, "stat")
  estimate_mat <- nf_collect(result, "estimate")
  expect_equal(dim(stat_mat), c(2L, 2L))
  expect_equal(dim(estimate_mat), c(2L, 2L))
  expect_true(all(estimate_mat[result$observations$term == "group", ] > 0))

  val <- nf_validate(result, level = "structural")
  expect_true(val$valid)
})

test_that("nf_analyze accepts bare feature symbols and string variables", {
  ds <- .make_fixed_roi_nftab()
  feature_name <- "roi_beta"

  result_symbol <- nf_analyze(ds, roi_beta, ~ group + age)
  result_string <- nf_analyze(ds, feature_name, ~ group + age)

  expect_equal(result_symbol$observations, result_string$observations)
  expect_equal(nf_collect(result_symbol, stat), nf_collect(result_string, "stat"))
})

test_that("nf_analyze subject-blocked mode returns main and interaction tests for ROI features", {
  ds <- .make_analysis_roi_nftab()

  result <- nf_analyze(ds, "roi_beta", ~ group * condition + (1 | subject))

  expect_s3_class(result, "nftab")
  expect_equal(nf_nobs(result), 3L)
  expect_equal(result$observations$term, c("group", "condition", "group:condition"))
  expect_equal(result$observations$stat_kind, c("t", "t", "t"))

  stat_mat <- nf_collect(result, "stat")
  p_mat <- nf_collect(result, "p_value")
  est_mat <- nf_collect(result, "estimate", simplify = FALSE)

  expect_equal(dim(stat_mat), c(3L, 2L))
  expect_equal(dim(p_mat), c(3L, 2L))
  expect_equal(length(est_mat), 3L)
  expect_true(all(vapply(est_mat, function(x) all(x > 0), logical(1))))

  val <- nf_validate(result, level = "structural")
  expect_true(val$valid)
})

test_that("nf_analyze fixed mode returns volumetric nftab results", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("nftab_analysis_fixed_nifti_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  volumes <- array(0, dim = c(2, 2, 2, 4))
  volumes[, , , 1] <- 1
  volumes[, , , 2] <- 1.5
  volumes[, , , 3] <- 3
  volumes[, , , 4] <- 3.5

  rows <- data.frame(
    row_id = paste0("r", seq_len(4L)),
    subject = paste0("s", seq_len(4L)),
    group = c("ctrl", "ctrl", "pt", "pt"),
    condition = "faces",
    stat_res = "stats",
    stat_sel = sprintf('{"index":{"t":%d}}', 0:3),
    stringsAsFactors = FALSE
  )

  ds <- .make_analysis_nifti_ds(tmpdir, volumes, rows)
  result <- nf_analyze(ds, "statmap", ~ group)

  expect_s3_class(result, "nftab")
  expect_equal(nf_nobs(result), 1L)
  expect_equal(result$observations$term, "group")

  stat_vol <- nf_resolve(result, 1L, "stat")
  est_vol <- nf_resolve(result, 1L, "estimate")
  expect_equal(dim(stat_vol), c(2L, 2L, 2L))
  expect_equal(dim(est_vol), c(2L, 2L, 2L))
})

test_that("nf_analyze subject-blocked mode returns volumetric nftab results", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("nftab_analysis_rm_nifti_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  volumes <- array(0, dim = c(2, 2, 2, 8))
  values <- c(1, 2, 1.5, 2.5, 3, 5, 3.5, 5.5)
  for (i in seq_along(values)) {
    volumes[, , , i] <- values[[i]]
  }

  rows <- data.frame(
    row_id = paste0("r", seq_len(8L)),
    subject = rep(c("s01", "s02", "s03", "s04"), each = 2L),
    group = rep(c("ctrl", "ctrl", "pt", "pt"), each = 2L),
    condition = rep(c("faces", "houses"), times = 4L),
    stat_res = "stats",
    stat_sel = sprintf('{"index":{"t":%d}}', 0:7),
    stringsAsFactors = FALSE
  )

  ds <- .make_analysis_nifti_ds(tmpdir, volumes, rows)
  result <- nf_analyze(ds, "statmap", ~ group * condition + (1 | subject))

  expect_s3_class(result, "nftab")
  expect_equal(nf_nobs(result), 3L)
  expect_equal(result$observations$term, c("group", "condition", "group:condition"))

  stat_vol <- nf_resolve(result, 1L, "stat")
  expect_equal(dim(stat_vol), c(2L, 2L, 2L))
})

test_that("nf_analyze warns that it drops x-summary", {
  ds <- .make_fixed_roi_nftab()
  ds$manifest$extensions <- list(`x-summary` = list(version = "0.1.0", tables = list()))
  expect_warning(result <- nf_analyze(ds, "roi_beta", ~ group + age), "nf_analyze dropped x-summary")
  expect_null(nf_extensions(result)[["x-summary"]])
})

# x-backing (spec/extensions/x-backing.md): results record what they came from.

.analysis_on_disk <- function() {
  study <- tempfile("backing-study-")
  dir.create(study)
  nf_write(.make_analysis_roi_nftab(), file.path(study, "betas"))
  list(study = study, ds = nf_read(file.path(study, "betas", "nftab.yaml")))
}

test_that("nf_analyze links its result to the source dataset, and nf_write stores the link relative", {
  src <- .analysis_on_disk()
  on.exit(unlink(src$study, recursive = TRUE))
  result <- nf_analyze(src$ds, "roi_beta", ~ group * condition + (1 | subject))
  link <- result$manifest$extensions[["x-backing"]]
  expect_identical(link$version, "0.1.0")
  expect_identical(link$feature, "roi_beta")
  expect_match(link$formula, "group * condition", fixed = TRUE)
  expect_match(link$source_checksum, "^sha256:[0-9a-f]{64}$")
  expect_true(file.exists(link$source))
  expect_true(nf_validate(result)$valid)

  nf_write(result, file.path(src$study, "group"), manifest_name = "nftab.json")
  written <- jsonlite::fromJSON(file.path(src$study, "group", "nftab.json"), simplifyVector = FALSE)
  stored <- written$extensions[["x-backing"]]
  expect_identical(stored$source, "../betas/nftab.yaml")
  expect_identical(stored$source_checksum, link$source_checksum)

  # Read back and written elsewhere, the link still reaches the source.
  again <- nf_read(file.path(src$study, "group", "nftab.json"))
  nf_write(again, file.path(src$study, "deeper", "copy"), manifest_name = "nftab.json")
  moved <- jsonlite::fromJSON(file.path(src$study, "deeper", "copy", "nftab.json"), simplifyVector = FALSE)
  expect_identical(moved$extensions[["x-backing"]]$source, "../../betas/nftab.yaml")
})

test_that("an in-memory source gets no link, and a vanished source drops it on write", {
  result <- nf_analyze(.make_analysis_roi_nftab(), "roi_beta", ~ group * condition + (1 | subject))
  expect_null(result$manifest$extensions[["x-backing"]])

  src <- .analysis_on_disk()
  on.exit(unlink(src$study, recursive = TRUE))
  linked <- nf_analyze(src$ds, "roi_beta", ~ group * condition + (1 | subject))
  unlink(file.path(src$study, "betas"), recursive = TRUE)
  out <- file.path(src$study, "group")
  expect_warning(nf_write(linked, out, manifest_name = "nftab.json"), "dropped x-backing")
  written <- jsonlite::fromJSON(file.path(out, "nftab.json"), simplifyVector = FALSE)
  expect_null(written$extensions[["x-backing"]])
})

test_that("x-backing survives row subsetting, is dropped when values change, and is validated", {
  src <- .analysis_on_disk()
  on.exit(unlink(src$study, recursive = TRUE))
  result <- nf_analyze(src$ds, "roi_beta", ~ group * condition + (1 | subject))
  expect_false(is.null(result[1L]$manifest$extensions[["x-backing"]]))
  expect_warning(
    changed <- nf_mutate_feature(result, "stat2", "stat", function(v) v * 2),
    "dropped x-backing"
  )
  expect_null(changed$manifest$extensions[["x-backing"]])

  bad <- result
  bad$manifest$extensions[["x-backing"]]$version <- "9.0.0"
  bad$manifest$extensions[["x-backing"]]$feature <- NULL
  errors <- nf_validate(bad)$errors
  expect_true(any(grepl("x-backing.*version", errors)))
  expect_true(any(grepl("x-backing.*'feature'", errors)))
})

test_that("relative paths between sibling and nested directories are computed", {
  root <- tempfile("relpath-")
  dir.create(file.path(root, "a", "b"), recursive = TRUE)
  dir.create(file.path(root, "c"))
  on.exit(unlink(root, recursive = TRUE))
  file.create(file.path(root, "c", "m.yaml"))
  expect_identical(neurotabs:::.nf_relative_path(file.path(root, "a", "b"), file.path(root, "c", "m.yaml")), "../../c/m.yaml")
  expect_identical(neurotabs:::.nf_relative_path(file.path(root, "c"), file.path(root, "c", "m.yaml")), "m.yaml")
})
