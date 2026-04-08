test_that("valid fixture dataset reads and validates structurally", {
  ds <- nf_read(.fixture_path("valid-roi", "nftab.yaml"))

  expect_s3_class(ds, "nftab")
  expect_equal(nf_feature_names(ds), "roi_beta")

  result <- nf_validate(ds, level = "structural")
  expect_true(result$valid)
})

test_that("invalid schema fixture is rejected at read time", {
  expect_error(
    nf_read(.fixture_path("invalid-schema-unknown-key", "nftab.yaml")),
    "schema validation"
  )
})

test_that("invalid extra-column fixture is rejected at read time", {
  expect_error(
    nf_read(.fixture_path("invalid-extra-column", "nftab.yaml")),
    "undeclared columns"
  )
})

test_that("invalid non-nullable fixture is rejected at read time", {
  expect_error(
    nf_read(.fixture_path("invalid-nonnullable-na", "nftab.yaml")),
    "non-nullable"
  )
})

test_that("invalid json fixture is rejected at read time", {
  expect_error(
    nf_read(.fixture_path("invalid-bad-json", "nftab.yaml")),
    "invalid JSON text"
  )
})

test_that("unsupported-backend fixture fails full conformance", {
  ds <- nf_read(.fixture_path("invalid-full-unsupported-backend", "nftab.yaml"))

  structural <- nf_validate(ds, level = "structural")
  expect_true(structural$valid)

  full <- nf_validate(ds, level = "full")
  expect_false(full$valid)
  expect_true(any(grepl("no adapter registered", full$errors)))
})
