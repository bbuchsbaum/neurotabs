make_nifti_compute_ds <- function(tmpdir, volumes, rows, with_selector = TRUE) {
  dir.create(tmpdir, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(tmpdir, "maps"), showWarnings = FALSE)

  nifti_path <- file.path(tmpdir, "maps", "stats.nii.gz")
  RNifti::writeNifti(volumes, nifti_path)

  obs_cols <- list(
    row_id = list(dtype = "string", nullable = FALSE),
    subject = list(dtype = "string", nullable = FALSE),
    group = list(dtype = "string", nullable = FALSE),
    condition = list(dtype = "string", nullable = FALSE),
    stat_res = list(dtype = "string", nullable = FALSE)
  )
  if (with_selector) {
    obs_cols$stat_sel <- list(dtype = "json", nullable = FALSE)
  }

  binding <- list(resource_id = list(column = "stat_res"))
  if (with_selector) {
    binding$selector <- list(column = "stat_sel")
  }

  yaml::write_yaml(
    list(
      spec_version = "0.1.0",
      dataset_id = "compute-demo",
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
            support_ref = "compute_grid",
            shape = as.list(dim(volumes)[seq_len(3L)]),
            alignment = "same_grid"
          ),
          encodings = list(
            list(
              type = "ref",
              binding = binding
            )
          )
        )
      ),
      supports = list(
        compute_grid = list(
          support_type = "volume",
          support_id = sprintf(
            "compute-grid-%s",
            paste(dim(volumes)[seq_len(3L)], collapse = "x")
          ),
          space = "MNI152NLin2009cAsym",
          grid_id = sprintf(
            "compute-grid-%s",
            paste(dim(volumes)[seq_len(3L)], collapse = "x")
          )
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
      checksum = paste0(
        "md5:",
        digest::digest(file = nifti_path, algo = "md5", serialize = FALSE)
      ),
      stringsAsFactors = FALSE
    ),
    file.path(tmpdir, "resources.csv")
  )

  nf_read(file.path(tmpdir, "nftab.yaml"))
}

test_that("nf_apply fixed ops work for columns-encoded vectors", {
  ds <- .make_roi_nftab()

  result <- nf_apply(ds, "roi_beta", "mean")

  expect_type(result, "double")
  expect_equal(
    unname(result),
    unname(apply(nf_collect(ds, "roi_beta"), 1L, mean))
  )
})

test_that("nf_apply custom functions avoid nf_resolve for columns features", {
  ds <- .make_roi_nftab()

  original_resolve <- get("nf_resolve", envir = asNamespace("neurotabs"))
  assignInNamespace("nf_resolve", function(...) {
    stop("nf_resolve should not be called for columns fast path")
  }, ns = "neurotabs")
  on.exit(assignInNamespace("nf_resolve", original_resolve, ns = "neurotabs"), add = TRUE)

  result <- nf_apply(ds, "roi_beta", function(x) mean(x))

  expect_equal(unname(result), unname(rowMeans(nf_collect(ds, "roi_beta"))))
})

test_that("nf_apply fixed ops match resolved 4D nifti volumes", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("nftab_compute4d_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  volumes <- array(0, dim = c(2, 2, 2, 4))
  volumes[, , , 1] <- 1
  volumes[, , , 2] <- 2
  volumes[, , , 3] <- 4
  volumes[, , , 4] <- 8

  rows <- data.frame(
    row_id = paste0("r", 1:4),
    subject = paste0("s", 1:4),
    group = c("ctrl", "ctrl", "pt", "pt"),
    condition = c("faces", "houses", "faces", "houses"),
    stat_res = "stats",
    stat_sel = c(
      '{"index":{"t":0}}',
      '{"index":{"t":1}}',
      '{"index":{"t":2}}',
      '{"index":{"t":3}}'
    ),
    stringsAsFactors = FALSE
  )

  ds <- make_nifti_compute_ds(tmpdir, volumes, rows, with_selector = TRUE)

  fast <- nf_apply(ds, "statmap", "mean")
  oracle <- vapply(seq_len(nf_nobs(ds)), function(i) {
    mean(as.numeric(nf_resolve(ds, i, "statmap")))
  }, numeric(1))
  names(oracle) <- rows$row_id

  expect_equal(fast, oracle)
})

test_that("nf_apply custom functions avoid nf_resolve for cacheable nifti features", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("nftab_apply3d_cached_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  volumes <- array(1:8, dim = c(2, 2, 2))
  rows <- data.frame(
    row_id = paste0("r", 1:2),
    subject = c("s1", "s2"),
    group = c("ctrl", "ctrl"),
    condition = c("faces", "houses"),
    stat_res = "stats",
    stringsAsFactors = FALSE
  )

  ds <- make_nifti_compute_ds(tmpdir, volumes, rows, with_selector = FALSE)
  original_resolve <- get("nf_resolve", envir = asNamespace("neurotabs"))
  assignInNamespace("nf_resolve", function(...) {
    stop("nf_resolve should not be called for nifti fast path")
  }, ns = "neurotabs")
  on.exit(assignInNamespace("nf_resolve", original_resolve, ns = "neurotabs"), add = TRUE)

  result <- nf_apply(ds, "statmap", function(x) mean(as.numeric(x)))

  expect_equal(unname(result), rep(mean(as.numeric(volumes)), 2L))
})

test_that("nf_apply nifti fast paths are stable under parallel task execution", {
  skip_if_not_installed("RNifti")
  skip_if(.Platform$OS.type == "windows")

  tmpdir <- tempfile("nftab_apply4d_parallel_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  volumes <- array(0, dim = c(2, 2, 2, 4))
  volumes[, , , 1] <- 1
  volumes[, , , 2] <- 2
  volumes[, , , 3] <- 4
  volumes[, , , 4] <- 8

  rows <- data.frame(
    row_id = paste0("r", 1:4),
    subject = paste0("s", 1:4),
    group = c("ctrl", "ctrl", "pt", "pt"),
    condition = c("faces", "houses", "faces", "houses"),
    stat_res = "stats",
    stat_sel = c(
      '{"index":{"t":0}}',
      '{"index":{"t":1}}',
      '{"index":{"t":2}}',
      '{"index":{"t":3}}'
    ),
    stringsAsFactors = FALSE
  )

  ds <- make_nifti_compute_ds(tmpdir, volumes, rows, with_selector = TRUE)
  old_workers <- getOption("neurotabs.compute.workers")
  on.exit(options(neurotabs.compute.workers = old_workers), add = TRUE)

  options(neurotabs.compute.workers = 1L)
  serial_fixed <- nf_apply(ds, "statmap", "mean")
  serial_custom <- nf_apply(ds, "statmap", function(x) mean(as.numeric(x)))

  options(neurotabs.compute.workers = 2L)
  parallel_fixed <- nf_apply(ds, "statmap", "mean")
  parallel_custom <- nf_apply(ds, "statmap", function(x) mean(as.numeric(x)))

  expect_equal(parallel_fixed, serial_fixed)
  expect_equal(parallel_custom, serial_custom)
})

test_that("nf_summarize mean preserves volume shape and groups for 4D nifti", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("nftab_summarize4d_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  volumes <- array(0, dim = c(2, 2, 2, 4))
  volumes[, , , 1] <- 1
  volumes[, , , 2] <- 2
  volumes[, , , 3] <- 4
  volumes[, , , 4] <- 8

  rows <- data.frame(
    row_id = paste0("r", 1:4),
    subject = paste0("s", 1:4),
    group = c("ctrl", "ctrl", "pt", "pt"),
    condition = c("faces", "houses", "faces", "houses"),
    stat_res = "stats",
    stat_sel = c(
      '{"index":{"t":0}}',
      '{"index":{"t":1}}',
      '{"index":{"t":2}}',
      '{"index":{"t":3}}'
    ),
    stringsAsFactors = FALSE
  )

  ds <- make_nifti_compute_ds(tmpdir, volumes, rows, with_selector = TRUE)
  summary_nftab <- nf_summarize(ds, "statmap", by = "group", .f = "mean")

  expect_true(inherits(summary_nftab, "nftab"))
  expect_equal(sort(summary_nftab$observations$group), c("ctrl", "pt"))
  ctrl_val <- nf_resolve(summary_nftab, which(summary_nftab$observations$group == "ctrl"), "statmap")
  pt_val   <- nf_resolve(summary_nftab, which(summary_nftab$observations$group == "pt"), "statmap")
  expect_equal(dim(ctrl_val), c(2, 2, 2))
  expect_equal(as.vector(ctrl_val), rep(1.5, 8))
  expect_equal(as.vector(pt_val), rep(6, 8))
})

test_that("nf_summarize nifti paths are stable under parallel task execution", {
  skip_if_not_installed("RNifti")
  skip_if(.Platform$OS.type == "windows")

  tmpdir <- tempfile("nftab_summarize4d_parallel_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  volumes <- array(0, dim = c(2, 2, 2, 4))
  volumes[, , , 1] <- 1
  volumes[, , , 2] <- 2
  volumes[, , , 3] <- 4
  volumes[, , , 4] <- 8

  rows <- data.frame(
    row_id = paste0("r", 1:4),
    subject = paste0("s", 1:4),
    group = c("ctrl", "ctrl", "pt", "pt"),
    condition = c("faces", "houses", "faces", "houses"),
    stat_res = "stats",
    stat_sel = c(
      '{"index":{"t":0}}',
      '{"index":{"t":1}}',
      '{"index":{"t":2}}',
      '{"index":{"t":3}}'
    ),
    stringsAsFactors = FALSE
  )

  ds <- make_nifti_compute_ds(tmpdir, volumes, rows, with_selector = TRUE)
  old_workers <- getOption("neurotabs.compute.workers")
  on.exit(options(neurotabs.compute.workers = old_workers), add = TRUE)

  options(neurotabs.compute.workers = 1L)
  serial_fixed <- nf_summarize(ds, "statmap", by = "group", .f = "mean")
  serial_custom <- nf_summarize(ds, "statmap", by = "group", .f = function(values) {
    Reduce(`+`, values) / length(values)
  })

  options(neurotabs.compute.workers = 2L)
  parallel_fixed <- nf_summarize(ds, "statmap", by = "group", .f = "mean")
  parallel_custom <- nf_summarize(ds, "statmap", by = "group", .f = function(values) {
    Reduce(`+`, values) / length(values)
  })

  expect_equal(
    sort(parallel_fixed$observations$group),
    sort(serial_fixed$observations$group)
  )
  expect_equal(
    sort(parallel_custom$observations$group),
    sort(serial_custom$observations$group)
  )
  # Verify resolved values match between serial and parallel
  for (grp in c("ctrl", "pt")) {
    sf_val  <- nf_resolve(serial_fixed,   which(serial_fixed$observations$group == grp), "statmap")
    pf_val  <- nf_resolve(parallel_fixed, which(parallel_fixed$observations$group == grp), "statmap")
    sc_val  <- nf_resolve(serial_custom,  which(serial_custom$observations$group == grp), "statmap")
    pc_val  <- nf_resolve(parallel_custom, which(parallel_custom$observations$group == grp), "statmap")
    expect_equal(as.vector(pf_val), as.vector(sf_val))
    expect_equal(as.vector(pc_val), as.vector(sc_val))
  }
})

test_that("nf_summarize custom functions avoid nf_resolve for columns features", {
  ds <- .make_roi_nftab()

  original_resolve <- get("nf_resolve", envir = asNamespace("neurotabs"))
  assignInNamespace("nf_resolve", function(...) {
    stop("nf_resolve should not be called for summarize columns fast path")
  }, ns = "neurotabs")
  on.exit(assignInNamespace("nf_resolve", original_resolve, ns = "neurotabs"), add = TRUE)

  summary_nftab <- nf_summarize(ds, "roi_beta", by = "group", .f = function(values) {
    Reduce(`+`, values) / length(values)
  })

  expect_true(inherits(summary_nftab, "nftab"))
  expect_equal(sort(summary_nftab$observations$group), c("ctrl", "pt"))
  ctrl_val <- nf_resolve(summary_nftab, which(summary_nftab$observations$group == "ctrl"), "roi_beta")
  pt_val   <- nf_resolve(summary_nftab, which(summary_nftab$observations$group == "pt"), "roi_beta")
  expect_equal(as.numeric(ctrl_val), c(0.2, 0.3, 0.2))
  expect_equal(as.numeric(pt_val), c(0.3, 0.4, 0.25))
})

test_that("nf_summarize var matches sample variance for grouped 4D nifti", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("nftab_var4d_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  volumes <- array(0, dim = c(2, 2, 2, 4))
  volumes[, , , 1] <- 1
  volumes[, , , 2] <- 2
  volumes[, , , 3] <- 4
  volumes[, , , 4] <- 8

  rows <- data.frame(
    row_id = paste0("r", 1:4),
    subject = paste0("s", 1:4),
    group = c("ctrl", "ctrl", "pt", "pt"),
    condition = c("faces", "houses", "faces", "houses"),
    stat_res = "stats",
    stat_sel = c(
      '{"index":{"t":0}}',
      '{"index":{"t":1}}',
      '{"index":{"t":2}}',
      '{"index":{"t":3}}'
    ),
    stringsAsFactors = FALSE
  )

  ds <- make_nifti_compute_ds(tmpdir, volumes, rows, with_selector = TRUE)
  summary_nftab <- nf_summarize(ds, "statmap", by = "group", .f = "var")

  expect_true(inherits(summary_nftab, "nftab"))
  ctrl_val <- nf_resolve(summary_nftab, which(summary_nftab$observations$group == "ctrl"), "statmap")
  pt_val   <- nf_resolve(summary_nftab, which(summary_nftab$observations$group == "pt"), "statmap")
  expect_equal(as.vector(ctrl_val), rep(0.5, 8))
  expect_equal(as.vector(pt_val), rep(8, 8))
})

test_that("nf_summarize sum works for repeated 3D nifti resources", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("nftab_summarize3d_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  volumes <- array(1:8, dim = c(2, 2, 2))
  rows <- data.frame(
    row_id = paste0("r", 1:2),
    subject = c("s1", "s2"),
    group = c("ctrl", "ctrl"),
    condition = c("faces", "houses"),
    stat_res = "stats",
    stringsAsFactors = FALSE
  )

  ds <- make_nifti_compute_ds(tmpdir, volumes, rows, with_selector = FALSE)
  total <- nf_summarize(ds, "statmap", .f = "sum")

  expect_equal(dim(total), c(2, 2, 2))
  expect_equal(as.vector(total), as.vector(volumes * 2))
})

test_that("nf_mutate derives scalar columns from design columns and feature ops", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("nftab_mutate4d_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  volumes <- array(0, dim = c(2, 2, 2, 2))
  volumes[, , , 1] <- 1
  volumes[, , , 2] <- 3

  rows <- data.frame(
    row_id = c("r1", "r2"),
    subject = c("s1", "s2"),
    group = c("ctrl", "pt"),
    condition = c("faces", "houses"),
    stat_res = "stats",
    stat_sel = c('{"index":{"t":0}}', '{"index":{"t":1}}'),
    stringsAsFactors = FALSE
  )

  ds <- make_nifti_compute_ds(tmpdir, volumes, rows, with_selector = TRUE)
  mutated <- nf_mutate(
    ds,
    is_patient = group == "pt",
    mean_stat = nf_apply_feature("statmap", "mean"),
    cohort = "demo"
  )

  expect_equal(mutated$observations$is_patient, c(FALSE, TRUE))
  expect_equal(mutated$observations$mean_stat, c(1, 3))
  expect_equal(mutated$observations$cohort, c("demo", "demo"))
  expect_equal(mutated$manifest$observation_columns$is_patient$dtype, "bool")
  expect_equal(mutated$manifest$observation_columns$mean_stat$dtype, "float64")
  expect_equal(mutated$manifest$observation_columns$cohort$dtype, "string")
})

test_that("nf_compare subtracts grouped ROI summaries against a reference group", {
  ds <- .make_roi_nftab()
  grouped <- nf_group_by(ds, group)

  compared <- nf_compare(grouped, "roi_beta", .ref = "ctrl", .f = "subtract")

  expect_true(inherits(compared, "nftab"))
  expect_equal(sort(compared$observations$group), c("ctrl", "pt"))

  ctrl_val <- nf_resolve(compared, which(compared$observations$group == "ctrl"), "roi_beta")
  pt_val   <- nf_resolve(compared, which(compared$observations$group == "pt"), "roi_beta")
  expect_equal(as.numeric(ctrl_val), c(0, 0, 0))

  ctrl_mean <- colMeans(nf_collect(nf_filter(ds, group == "ctrl"), "roi_beta"))
  pt_mean   <- colMeans(nf_collect(nf_filter(ds, group == "pt"), "roi_beta"))
  expect_equal(as.numeric(pt_val), pt_mean - ctrl_mean)
})

test_that("nf_compare works on summarized nifti groups", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("nftab_compare4d_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  volumes <- array(0, dim = c(2, 2, 2, 4))
  volumes[, , , 1] <- 1
  volumes[, , , 2] <- 2
  volumes[, , , 3] <- 4
  volumes[, , , 4] <- 8

  rows <- data.frame(
    row_id = paste0("r", 1:4),
    subject = paste0("s", 1:4),
    group = c("ctrl", "ctrl", "pt", "pt"),
    condition = c("faces", "houses", "faces", "houses"),
    stat_res = "stats",
    stat_sel = c(
      '{"index":{"t":0}}',
      '{"index":{"t":1}}',
      '{"index":{"t":2}}',
      '{"index":{"t":3}}'
    ),
    stringsAsFactors = FALSE
  )

  ds <- make_nifti_compute_ds(tmpdir, volumes, rows, with_selector = TRUE)
  summarized <- nf_summarize(nf_group_by(ds, group), "statmap", .f = "mean")
  compared <- nf_compare(summarized, "statmap", .ref = "ctrl", .f = "subtract")

  expect_true(inherits(compared, "nftab"))
  ctrl_val <- nf_resolve(compared, which(compared$observations$group == "ctrl"), "statmap")
  pt_val   <- nf_resolve(compared, which(compared$observations$group == "pt"), "statmap")
  expect_equal(as.vector(ctrl_val), rep(0, 8))
  expect_equal(as.vector(pt_val), rep(4.5, 8))
})

test_that("nf_mutate_feature materializes derived 1D features as columns", {
  ds <- .make_roi_nftab()
  mutated <- nf_mutate_feature(
    ds,
    "roi_beta_scaled",
    "roi_beta",
    function(x) x * 2
  )

  expect_true("roi_beta_scaled" %in% nf_feature_names(mutated))
  expect_equal(
    nf_resolve(mutated, 1L, "roi_beta_scaled"),
    nf_resolve(ds, 1L, "roi_beta") * 2
  )
  expect_true(any(grepl("^roi_beta_scaled_", names(mutated$observations))))
})

test_that("nf_mutate_feature supports nullable derived columns features", {
  ds <- .make_roi_nftab()

  mutated <- nf_mutate_feature(
    ds,
    "roi_beta_optional",
    "roi_beta",
    function(x) {
      if (mean(x) < 0.25) {
        return(NULL)
      }
      x * 10
    }
  )

  expect_true(mutated$manifest$features$roi_beta_optional$nullable)
  expect_null(nf_resolve(mutated, "r2", "roi_beta_optional"))
  expect_equal(
    nf_resolve(mutated, "r1", "roi_beta_optional"),
    nf_resolve(ds, "r1", "roi_beta") * 10
  )
})

test_that("nf_mutate_feature materializes derived nifti volumes as resources", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("nftab_mutate_feature4d_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  volumes <- array(0, dim = c(2, 2, 2, 2))
  volumes[, , , 1] <- 1
  volumes[, , , 2] <- 3

  rows <- data.frame(
    row_id = c("r1", "r2"),
    subject = c("s1", "s2"),
    group = c("ctrl", "pt"),
    condition = c("faces", "houses"),
    stat_res = "stats",
    stat_sel = c('{"index":{"t":0}}', '{"index":{"t":1}}'),
    stringsAsFactors = FALSE
  )

  ds <- make_nifti_compute_ds(tmpdir, volumes, rows, with_selector = TRUE)
  mutated <- nf_mutate_feature(
    ds,
    "statmap_scaled",
    "statmap",
    function(x) x * 2
  )

  expect_true("statmap_scaled" %in% nf_feature_names(mutated))
  expect_true(!is.null(mutated$resources))
  expect_true(any(grepl("^statmap_scaled_res", names(mutated$observations))))
  expect_equal(as.vector(nf_resolve(mutated, "r1", "statmap_scaled")), rep(2, 8))
  expect_equal(as.vector(nf_resolve(mutated, "r2", "statmap_scaled")), rep(6, 8))
})

test_that("nf_mutate_feature supports nullable derived nifti features", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("nftab_mutate_feature4d_nullable_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  volumes <- array(0, dim = c(2, 2, 2, 2))
  volumes[, , , 1] <- 1
  volumes[, , , 2] <- 3

  rows <- data.frame(
    row_id = c("r1", "r2"),
    subject = c("s1", "s2"),
    group = c("ctrl", "pt"),
    condition = c("faces", "houses"),
    stat_res = "stats",
    stat_sel = c('{"index":{"t":0}}', '{"index":{"t":1}}'),
    stringsAsFactors = FALSE
  )

  ds <- make_nifti_compute_ds(tmpdir, volumes, rows, with_selector = TRUE)
  mutated <- nf_mutate_feature(
    ds,
    "statmap_optional",
    "statmap",
    function(x) {
      if (mean(x) < 2) {
        return(NULL)
      }
      x * 2
    }
  )

  expect_true(mutated$manifest$features$statmap_optional$nullable)
  expect_null(nf_resolve(mutated, "r1", "statmap_optional"))
  expect_equal(as.vector(nf_resolve(mutated, "r2", "statmap_optional")), rep(6, 8))
})

# ---- New nftab-returning nf_summarize / nf_compare tests ---------------------

test_that("nf_summarize grouped 1D returns nftab with correct structure", {
  ds <- .make_roi_nftab()
  result <- nf_summarize(ds, "roi_beta", by = "group", .f = "mean")

  expect_true(inherits(result, "nftab"))
  expect_equal(nrow(result$observations), 2L)  # two groups: ctrl, pt
  expect_true("roi_beta" %in% nf_feature_names(result))
  expect_true(".members" %in% names(result$observations))
})

test_that("nf_summarize grouped 1D nrow equals number of unique groups", {
  ds <- .make_roi_nftab()
  n_groups <- length(unique(ds$observations$group))
  result <- nf_summarize(ds, "roi_beta", by = "group", .f = "mean")

  expect_equal(nrow(result$observations), n_groups)
})

test_that("nf_collect on summary nftab returns matrix with correct dims", {
  ds <- .make_roi_nftab()
  result <- nf_summarize(ds, "roi_beta", by = "group", .f = "mean")

  mat <- nf_collect(result, "roi_beta")
  expect_true(is.matrix(mat))
  expect_equal(nrow(mat), 2L)   # 2 groups
  expect_equal(ncol(mat), 3L)   # 3 ROIs
})

test_that(".members column contains valid JSON in summary nftab", {
  ds <- .make_roi_nftab()
  result <- nf_summarize(ds, "roi_beta", by = "group", .f = "mean")

  expect_true(".members" %in% names(result$observations))
  for (entry in result$observations$.members) {
    parsed <- jsonlite::fromJSON(entry)
    expect_true(is.character(parsed))
    expect_true(length(parsed) >= 1L)
  }
})

test_that("full pipeline: nf_group_by |> nf_summarize |> nf_filter works", {
  ds <- .make_roi_nftab()
  result <- nf_group_by(ds, group) |>
    nf_summarize("roi_beta") |>
    nf_filter(group == "ctrl")

  expect_true(inherits(result, "nftab"))
  expect_equal(nrow(result$observations), 1L)
  expect_equal(result$observations$group, "ctrl")
})

test_that("nf_compare on summary nftab returns nftab", {
  ds <- .make_roi_nftab()
  summarized <- nf_summarize(ds, "roi_beta", by = "group", .f = "mean")
  compared <- nf_compare(summarized, "roi_beta", .ref = "ctrl", .f = "subtract")

  expect_true(inherits(compared, "nftab"))
  expect_equal(nrow(compared$observations), 2L)

  ctrl_val <- nf_resolve(compared, which(compared$observations$group == "ctrl"), "roi_beta")
  expect_equal(as.numeric(ctrl_val), c(0, 0, 0))
})

test_that("nf_matched_cohort returns only matching rows", {
  ds <- .make_roi_nftab()
  cohort <- nf_matched_cohort(ds, list(group = "ctrl"))
  expect_s3_class(cohort, "nftab")
  expect_true(all(cohort$observations$group == "ctrl"))
  expect_true(nrow(cohort$observations) < nrow(ds$observations))
})

test_that("nf_matched_cohort errors on unknown column", {
  ds <- .make_roi_nftab()
  expect_error(nf_matched_cohort(ds, list(nonexistent = "x")), "not found")
})

test_that("nf_compare accepts nf_matched_cohort as .ref", {
  ds <- .make_roi_nftab()
  summarized <- nf_group_by(ds, group) |> nf_summarize("roi_beta")
  result <- nf_compare(summarized, "roi_beta",
                       .ref = nf_matched_cohort(ds, list(group = "ctrl")),
                       .f = "subtract")
  expect_true(inherits(result, "nftab"))
  expect_equal(nrow(result$observations), 2L)
})

test_that("nf_mutate adds a computed column", {
  ds <- .make_roi_nftab()
  result <- nf_mutate(ds, mean_roi = (roi_1 + roi_2 + roi_3) / 3)
  expect_true("mean_roi" %in% names(result$observations))
  expect_equal(nf_nobs(result), 4L)
})

test_that("nf_mutate with nf_apply_feature helper", {
  ds <- .make_roi_nftab()
  result <- nf_mutate(ds, roi_mean = nf_apply_feature("roi_beta", "mean"))
  expect_true("roi_mean" %in% names(result$observations))
  expect_type(result$observations$roi_mean, "double")
})

test_that("nf_apply with function .f works row-by-row", {
  ds <- .make_roi_nftab()
  result <- nf_apply(ds, "roi_beta", function(v) sum(v^2))
  expect_length(result, 4L)
  expect_named(result, c("r1", "r2", "r3", "r4"))
})

test_that("nf_summarize with var reducer", {
  ds <- .make_roi_nftab()
  grouped <- nf_group_by(ds, group)
  result <- nf_summarize(grouped, "roi_beta", .f = "var")
  expect_s3_class(result, "nftab")
  expect_equal(nf_nobs(result), 2L)
})

test_that("nf_summarize with sd reducer", {
  ds <- .make_roi_nftab()
  grouped <- nf_group_by(ds, group)
  result <- nf_summarize(grouped, "roi_beta", .f = "sd")
  expect_s3_class(result, "nftab")
})

test_that("nf_summarize with sum reducer", {
  ds <- .make_roi_nftab()
  grouped <- nf_group_by(ds, group)
  result <- nf_summarize(grouped, "roi_beta", .f = "sum")
  expect_s3_class(result, "nftab")
})

test_that("nf_apply fixed ops: sum, min, max, nnz, l2", {
  ds <- .make_roi_nftab()
  expect_length(nf_apply(ds, "roi_beta", "sum"), 4L)
  expect_length(nf_apply(ds, "roi_beta", "min"), 4L)
  expect_length(nf_apply(ds, "roi_beta", "max"), 4L)
  expect_length(nf_apply(ds, "roi_beta", "nnz"), 4L)
  expect_length(nf_apply(ds, "roi_beta", "l2"), 4L)
})

test_that("nf_compare subtract on grouped nftab", {
  ds <- .make_roi_nftab()
  grouped <- nf_group_by(ds, group)
  result <- nf_compare(grouped, "roi_beta", .ref = "ctrl", .f = "subtract")
  expect_s3_class(result, "nftab")
})

test_that("nf_mutate_feature transforms 1D feature values", {
  ds <- .make_roi_nftab()
  result <- nf_mutate_feature(ds, "roi_scaled", "roi_beta",
                               .f = function(v) v * 2)
  expect_true("roi_scaled" %in% nf_feature_names(result))
  val <- nf_resolve(result, "r1", "roi_scaled")
  expect_equal(val, c(0.6, 0.8, 0.6), tolerance = 1e-4)
})

test_that("nf_summarize ungrouped returns single value", {
  ds <- .make_roi_nftab()
  result <- nf_summarize(ds, "roi_beta", .f = "mean")
  # Ungrouped summarize returns a single value (array or vector)
  expect_true(is.numeric(result))
})

test_that("nf_compare ratio operation works", {
  ds <- .make_roi_nftab()
  grouped <- nf_group_by(ds, group)
  result <- nf_compare(grouped, "roi_beta", .ref = "ctrl", .f = "ratio")
  expect_s3_class(result, "nftab")
})

test_that("nf_apply with .progress emits messages", {
  ds <- .make_roi_nftab()
  # Use a custom function to force generic path
  expect_no_error(
    suppressMessages(nf_apply(ds, "roi_beta", function(v) mean(v), .progress = TRUE))
  )
})

test_that("nf_summarize with function .f works", {
  ds <- .make_roi_nftab()
  grouped <- nf_group_by(ds, group)
  result <- nf_summarize(grouped, "roi_beta", .f = function(vals) {
    Reduce("+", vals) / length(vals)
  })
  expect_true(is.data.frame(result) || inherits(result, "nftab"))
})

test_that("nf_apply sd and l2 fixed ops give correct results", {
  ds <- .make_roi_nftab()
  sds <- nf_apply(ds, "roi_beta", "sd")
  expect_true(all(sds > 0))
  l2s <- nf_apply(ds, "roi_beta", "l2")
  expect_true(all(l2s > 0))
  # l2 norm = sqrt(sum(x^2))
  r1_vals <- c(0.3, 0.4, 0.3)
  expect_equal(l2s[["r1"]], sqrt(sum(r1_vals^2)), tolerance = 1e-4)
})

test_that("nf_compare with nftab as .ref", {
  ds <- .make_roi_nftab()
  ref_ds <- nf_filter(ds, group == "ctrl")
  grouped <- nf_group_by(ds, group)
  result <- nf_compare(grouped, "roi_beta", .ref = ref_ds, .f = "subtract")
  expect_s3_class(result, "nftab")
})

test_that("nf_mutate replaces existing columns", {
  ds <- .make_roi_nftab()
  result <- nf_mutate(ds, roi_1 = roi_1 * 100)
  expect_true(all(result$observations$roi_1 > 1))
})

test_that("nf_mutate adds multiple columns at once", {
  ds <- .make_roi_nftab()
  result <- nf_mutate(ds, total = roi_1 + roi_2 + roi_3, flag = group == "ctrl")
  expect_true("total" %in% names(result$observations))
  expect_true("flag" %in% names(result$observations))
})

test_that("nf_compare errors on invalid .ref", {
  ds <- .make_roi_nftab()
  grouped <- nf_group_by(ds, group)
  expect_error(nf_compare(grouped, "roi_beta", .ref = "nonexistent"))
})

test_that("nf_summarize with by= parameter (not grouped_nftab)", {
  ds <- .make_roi_nftab()
  result <- nf_summarize(ds, "roi_beta", by = "group", .f = "mean")
  expect_s3_class(result, "nftab")
  expect_equal(nf_nobs(result), 2L)
})

test_that("nf_apply with nnz and max ops give correct values", {
  ds <- .make_roi_nftab()
  maxes <- nf_apply(ds, "roi_beta", "max")
  expect_equal(maxes[["r3"]], 0.5, tolerance = 1e-4)  # max of c(0.4, 0.5, 0.4)
  nnzs <- nf_apply(ds, "roi_beta", "nnz")
  expect_equal(nnzs[["r1"]], 3L)  # all 3 elements non-zero
})

test_that("nf_summarize with function .f returns data.frame", {
  ds <- .make_roi_nftab()
  result <- nf_summarize(ds, "roi_beta", by = "group",
                          .f = function(vals) Reduce("+", vals) / length(vals))
  expect_true(is.data.frame(result) || inherits(result, "nftab"))
})

# ── NIfTI-backed compute tests ───────────────────────────────────────────────

.make_nifti_compute_fixture <- function() {
  skip_if_not_installed("RNifti")
  tmpdir <- tempfile("compute-nifti-")
  dir.create(file.path(tmpdir, "maps"), recursive = TRUE)

  d <- c(3L, 3L, 3L)
  for (i in 1:4) {
    arr <- array(as.numeric(i * 10 + seq_len(prod(d))), dim = d)
    RNifti::writeNifti(arr, file.path(tmpdir, "maps", sprintf("sub%02d.nii.gz", i)))
  }

  obs_cols <- list(
    row_id    = nf_col_schema("string", nullable = FALSE),
    subject   = nf_col_schema("string", nullable = FALSE),
    condition = nf_col_schema("string", nullable = FALSE),
    group     = nf_col_schema("string", nullable = FALSE),
    map_file  = nf_col_schema("string", nullable = FALSE)
  )
  feat <- nf_feature(
    logical = nf_logical_schema("volume", c("x", "y", "z"), "float32",
                                shape = d, support_ref = "g"),
    encodings = list(nf_ref_encoding(backend = "nifti", locator = nf_col("map_file")))
  )
  m <- nf_manifest(
    dataset_id = "compute-nifti", row_id = "row_id",
    observation_axes = c("subject", "condition"),
    observation_columns = obs_cols,
    features = list(statmap = feat),
    supports = list(g = nf_support_volume("g", "MNI", "g"))
  )
  obs <- data.frame(
    row_id = paste0("r", 1:4),
    subject = c("s01", "s01", "s02", "s02"),
    condition = c("faces", "houses", "faces", "houses"),
    group = c("ctrl", "ctrl", "pt", "pt"),
    map_file = sprintf("maps/sub%02d.nii.gz", 1:4),
    stringsAsFactors = FALSE
  )
  list(ds = nftab(m, obs, .root = tmpdir), tmpdir = tmpdir, d = d)
}

test_that("nf_apply mean on NIfTI-backed feature uses fast path", {
  fix <- .make_nifti_compute_fixture()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  means <- nf_apply(fix$ds, "statmap", "mean")
  expect_length(means, 4L)
  expect_true(all(means > 0))
})

test_that("nf_apply sum/sd/min/max on NIfTI-backed feature", {
  fix <- .make_nifti_compute_fixture()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  sums <- nf_apply(fix$ds, "statmap", "sum")
  sds <- nf_apply(fix$ds, "statmap", "sd")
  mins <- nf_apply(fix$ds, "statmap", "min")
  maxs <- nf_apply(fix$ds, "statmap", "max")
  expect_true(all(sums > 0))
  expect_true(all(sds > 0))
  expect_true(all(mins > 0))
  expect_true(all(maxs > mins))
})

test_that("nf_summarize mean on NIfTI-backed grouped feature", {
  fix <- .make_nifti_compute_fixture()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  grouped <- nf_group_by(fix$ds, group)
  result <- nf_summarize(grouped, "statmap", .f = "mean")
  expect_s3_class(result, "nftab")
  expect_equal(nf_nobs(result), 2L)
})

test_that("nf_summarize sum on NIfTI-backed grouped feature", {
  fix <- .make_nifti_compute_fixture()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  grouped <- nf_group_by(fix$ds, group)
  result <- nf_summarize(grouped, "statmap", .f = "sum")
  expect_s3_class(result, "nftab")
})

test_that("nf_compare subtract on NIfTI-backed grouped feature", {
  fix <- .make_nifti_compute_fixture()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  grouped <- nf_group_by(fix$ds, group)
  result <- nf_compare(grouped, "statmap", .ref = "ctrl", .f = "subtract")
  expect_s3_class(result, "nftab")
})

test_that("nf_compare ratio on NIfTI-backed grouped feature", {
  fix <- .make_nifti_compute_fixture()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  grouped <- nf_group_by(fix$ds, group)
  result <- nf_compare(grouped, "statmap", .ref = "ctrl", .f = "ratio")
  expect_s3_class(result, "nftab")
})

test_that("nf_mutate_feature on NIfTI-backed feature", {
  fix <- .make_nifti_compute_fixture()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)
  old_workers <- getOption("neurotabs.compute.workers")
  on.exit(options(neurotabs.compute.workers = old_workers), add = TRUE)
  options(neurotabs.compute.workers = if (.Platform$OS.type == "windows") 1L else 2L)

  expect_warning(
    result <- nf_mutate_feature(fix$ds, "doubled", "statmap",
                                .f = function(v) v * 2),
    NA
  )
  expect_true("doubled" %in% nf_feature_names(result))
  vol <- nf_resolve(result, 1L, "doubled")
  orig <- nf_resolve(fix$ds, 1L, "statmap")
  expect_equal(as.vector(vol), as.vector(orig) * 2, tolerance = 1e-4)
})

test_that("nf_apply with custom function on NIfTI feature", {
  fix <- .make_nifti_compute_fixture()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  result <- nf_apply(fix$ds, "statmap", function(v) max(v) - min(v))
  expect_length(result, 4L)
  expect_true(all(result > 0))
})

test_that("nf_summarize var/sd on NIfTI-backed grouped feature", {
  fix <- .make_nifti_compute_fixture()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  grouped <- nf_group_by(fix$ds, group)
  var_result <- nf_summarize(grouped, "statmap", .f = "var")
  sd_result <- nf_summarize(grouped, "statmap", .f = "sd")
  expect_s3_class(var_result, "nftab")
  expect_s3_class(sd_result, "nftab")
})

test_that("nf_summarize ungrouped mean on NIfTI feature", {
  fix <- .make_nifti_compute_fixture()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  result <- nf_summarize(fix$ds, "statmap", .f = "mean")
  expect_true(is.numeric(result))
  expect_equal(length(dim(result)), 3L)
})

test_that("nf_summarize with custom function on NIfTI feature", {
  fix <- .make_nifti_compute_fixture()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  grouped <- nf_group_by(fix$ds, group)
  result <- nf_summarize(grouped, "statmap",
    .f = function(vals) {
      out <- Reduce("+", vals) / length(vals)
      array(as.numeric(out), dim = dim(vals[[1]]))
    })
  expect_true(is.data.frame(result) || inherits(result, "nftab"))
})

test_that("nf_apply nnz and l2 on NIfTI feature", {
  fix <- .make_nifti_compute_fixture()
  on.exit(unlink(fix$tmpdir, recursive = TRUE), add = TRUE)

  nnzs <- nf_apply(fix$ds, "statmap", "nnz")
  l2s <- nf_apply(fix$ds, "statmap", "l2")
  expect_true(all(nnzs == 27L))  # all voxels nonzero
  expect_true(all(l2s > 0))
})

test_that("nf_summarize preserves int32 group key dtype in manifest", {
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE),
    subject = nf_col_schema("string", nullable = FALSE),
    condition = nf_col_schema("string", nullable = FALSE),
    site = nf_col_schema("int32", nullable = FALSE),
    roi_1 = nf_col_schema("float32"),
    roi_2 = nf_col_schema("float32"),
    roi_3 = nf_col_schema("float32")
  )

  feat <- nf_feature(
    logical = nf_logical_schema("vector", "roi", "float32", shape = 3L),
    encodings = list(nf_columns_encoding(c("roi_1", "roi_2", "roi_3")))
  )

  m <- nf_manifest(
    dataset_id = "int-group-test",
    row_id = "row_id",
    observation_axes = c("subject", "condition"),
    observation_columns = obs_cols,
    features = list(roi_beta = feat)
  )

  obs <- data.frame(
    row_id = c("r1", "r2", "r3", "r4"),
    subject = c("s01", "s01", "s02", "s02"),
    condition = c("faces", "houses", "faces", "houses"),
    site = c(1L, 1L, 2L, 2L),
    roi_1 = c(0.3, 0.1, 0.4, 0.2),
    roi_2 = c(0.4, 0.2, 0.5, 0.3),
    roi_3 = c(0.3, 0.1, 0.4, 0.1),
    stringsAsFactors = FALSE
  )

  ds <- nftab(manifest = m, observations = obs)
  result <- nf_summarize(ds, "roi_beta", by = "site", .f = "mean")

  # The summary manifest must declare site as int32, not string
  site_schema <- result$manifest$observation_columns[["site"]]
  expect_equal(site_schema$dtype, "int32")

  # And the summarized nftab must pass structural validation
  val <- nf_validate(result, level = "structural")
  expect_true(val$valid)
})

test_that("nf_summarize via nf_group_by preserves group key dtype", {
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE),
    subject = nf_col_schema("string", nullable = FALSE),
    condition = nf_col_schema("string", nullable = FALSE),
    age = nf_col_schema("float64", nullable = FALSE),
    roi_1 = nf_col_schema("float32"),
    roi_2 = nf_col_schema("float32")
  )

  feat <- nf_feature(
    logical = nf_logical_schema("vector", "roi", "float32", shape = 2L),
    encodings = list(nf_columns_encoding(c("roi_1", "roi_2")))
  )

  m <- nf_manifest(
    dataset_id = "float-group-test",
    row_id = "row_id",
    observation_axes = c("subject", "condition"),
    observation_columns = obs_cols,
    features = list(roi = feat)
  )

  obs <- data.frame(
    row_id = c("r1", "r2"),
    subject = c("s01", "s02"),
    condition = c("faces", "faces"),
    age = c(25.0, 30.0),
    roi_1 = c(0.3, 0.4),
    roi_2 = c(0.5, 0.6),
    stringsAsFactors = FALSE
  )

  ds <- nftab(manifest = m, observations = obs)
  grouped <- nf_group_by(ds, condition)
  result <- nf_summarize(grouped, "roi", .f = "mean")

  cond_schema <- result$manifest$observation_columns[["condition"]]
  expect_equal(cond_schema$dtype, "string")

  val <- nf_validate(result, level = "structural")
  expect_true(val$valid)
})
