test_that("nf_cli info reports dataset summary as JSON", {
  path <- system.file("examples/roi-only/nftab.yaml", package = "neurotabs")
  skip_if(path == "", "example not installed")

  out <- capture.output(status <- nf_cli(c("info", path, "--json")))
  payload <- jsonlite::fromJSON(paste(out, collapse = "\n"))

  expect_equal(status, 0L)
  expect_equal(payload$dataset_id, "roi-only")
  expect_equal(payload$n_observations, 8L)
  expect_equal(payload$features[[1]], "roi_beta")
})

test_that("nf_cli validate distinguishes valid and invalid datasets", {
  valid <- system.file("examples/roi-only/nftab.yaml", package = "neurotabs")
  invalid <- .fixture_path("invalid-schema-unknown-key", "nftab.yaml")
  skip_if(valid == "", "example not installed")

  ok_out <- capture.output(ok_status <- nf_cli(c("validate", valid, "--json")))
  bad_out <- capture.output(
    bad_status <- nf_cli(c("validate", invalid, "--json")),
    type = "message"
  )

  ok_payload <- jsonlite::fromJSON(paste(ok_out, collapse = "\n"))
  expect_equal(ok_status, 0L)
  expect_true(ok_payload$valid)

  expect_equal(bad_status, 2L)
  expect_true(any(grepl("schema validation", bad_out)))
})

test_that("nf_cli features emits feature metadata", {
  path <- system.file("examples/roi-only/nftab.yaml", package = "neurotabs")
  skip_if(path == "", "example not installed")

  out <- capture.output(status <- nf_cli(c("features", path, "--json")))
  payload <- jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE)

  expect_equal(status, 0L)
  expect_length(payload, 1L)
  expect_equal(payload[[1]]$name, "roi_beta")
  expect_equal(payload[[1]]$kind, "vector")
})

test_that("nf_cli resolve returns a single row value", {
  path <- system.file("examples/roi-only/nftab.yaml", package = "neurotabs")
  skip_if(path == "", "example not installed")

  out <- capture.output(status <- nf_cli(c("resolve", path, "roi_beta", "--row", "r01")))
  payload <- jsonlite::fromJSON(paste(out, collapse = "\n"))

  expect_equal(status, 0L)
  expect_equal(payload$row_id, "r01")
  expect_equal(as.numeric(payload$value), c(0.31, 0.44, 0.29, 0.18, 0.22), tolerance = 1e-6)
})

test_that("nf_cli collect writes JSON to a file", {
  path <- system.file("examples/roi-only/nftab.yaml", package = "neurotabs")
  skip_if(path == "", "example not installed")

  out_path <- tempfile(fileext = ".json")
  on.exit(unlink(out_path), add = TRUE)

  status <- nf_cli(c("collect", path, "roi_beta", "--out", out_path))
  payload <- jsonlite::fromJSON(out_path)

  expect_equal(status, 0L)
  expect_equal(nrow(payload), 8L)
  expect_equal(payload$row_id[[1]], "r01")
})

test_that("nf_cli copy writes a normalized dataset", {
  path <- system.file("examples/roi-only/nftab.yaml", package = "neurotabs")
  skip_if(path == "", "example not installed")

  out_dir <- tempfile("neurotabs-cli-copy-")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  status <- nf_cli(c("copy", path, out_dir))
  ds <- nf_read(file.path(out_dir, "nftab.yaml"))

  expect_equal(status, 0L)
  expect_equal(ds$manifest$dataset_id, "roi-only")
  expect_equal(nf_nobs(ds), 8L)
})

test_that("exec/neurotabs wrapper runs from a source checkout", {
  script <- testthat::test_path("..", "..", "exec", "neurotabs")
  valid <- system.file("examples/roi-only/nftab.yaml", package = "neurotabs")
  skip_if(valid == "", "example not installed")

  res <- system2(
    command = file.path(R.home("bin"), "Rscript"),
    args = c(script, "info", valid, "--json"),
    stdout = TRUE,
    stderr = TRUE
  )

  json_start <- grep("^\\s*\\{", res)[1L]
  json_end <- tail(grep("^\\s*\\}", res), 1L)
  payload <- jsonlite::fromJSON(paste(res[json_start:json_end], collapse = "\n"))
  expect_equal(payload$dataset_id, "roi-only")
})
