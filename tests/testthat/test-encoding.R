test_that("nf_ref_encoding requires resource_id or backend+locator", {
  expect_error(nf_ref_encoding(), "must provide")
  expect_s3_class(nf_ref_encoding(resource_id = nf_col("res")), "nf_encoding")
  expect_s3_class(nf_ref_encoding(backend = "nifti", locator = "file.nii"), "nf_encoding")
})

test_that("nf_columns_encoding validates columns", {
  enc <- nf_columns_encoding(c("a", "b", "c"))
  expect_s3_class(enc, "nf_encoding")
  expect_equal(enc$type, "columns")
  expect_equal(enc$binding$columns, c("a", "b", "c"))
})

test_that("encoding_applicable works for columns", {
  enc <- nf_columns_encoding(c("x", "y"))
  row_ok <- list(x = 1.0, y = 2.0)
  row_missing <- list(x = 1.0, z = 3.0)
  row_na <- list(x = 1.0, y = NA)

  expect_true(encoding_applicable(enc, row_ok))
  expect_false(encoding_applicable(enc, row_missing))
  expect_false(encoding_applicable(enc, row_na))
})

test_that("encoding_applicable works for ref", {
  enc <- nf_ref_encoding(backend = nf_col("bk"), locator = nf_col("loc"))
  row_ok <- list(bk = "nifti", loc = "file.nii")
  row_missing <- list(bk = "nifti", loc = NA)

  expect_true(encoding_applicable(enc, row_ok))
  expect_false(encoding_applicable(enc, row_missing))
})

test_that("encoding_applicable falls back from missing resource_id to backend+locator", {
  enc <- nf_ref_encoding(
    resource_id = nf_col("rid"),
    backend = nf_col("bk"),
    locator = nf_col("loc")
  )
  row <- list(rid = NA, bk = "nifti", loc = "file.nii.gz")
  expect_true(encoding_applicable(enc, row))
})

test_that("nf_col creates column references", {
  cr <- nf_col("subject")
  expect_s3_class(cr, "nf_column_ref")
  expect_equal(cr$column, "subject")
})

test_that("print.nf_encoding prints ref encoding with resource_id", {
  enc <- nf_ref_encoding(resource_id = nf_col("res"))
  expect_output(print(enc), "ref")
  expect_output(print(enc), "resource_id")
})

test_that("print.nf_encoding prints ref encoding with backend+locator", {
  enc <- nf_ref_encoding(backend = "nifti", locator = "file.nii.gz",
                         selector = nf_col("sel"))
  expect_output(print(enc), "backend")
  expect_output(print(enc), "locator")
  expect_output(print(enc), "selector")
})

test_that("print.nf_encoding prints columns encoding", {
  enc <- nf_columns_encoding(c("a", "b", "c", "d", "e", "f"))
  out <- capture.output(print(enc))
  expect_true(any(grepl("columns", out)))
  expect_true(any(grepl("\\.\\.\\.", out)))  # truncation marker for >5 cols
})

test_that(".fmt_vs formats column refs and literals", {
  cr <- nf_col("mycolumn")
  expect_match(neurotabs:::.fmt_vs(cr), "column: mycolumn")
  expect_equal(neurotabs:::.fmt_vs("literal_string"), "literal_string")
  expect_match(neurotabs:::.fmt_vs(42L), "42")  # deparse fallback
})

test_that("resolve_value_source resolves column refs and literals", {
  row <- list(myval = 99.5, other = "x")
  cr <- nf_col("myval")
  expect_equal(neurotabs:::resolve_value_source(cr, row), 99.5)
  expect_equal(neurotabs:::resolve_value_source("static_val", row), "static_val")
})

test_that("encoding_applicable returns FALSE for unknown encoding type", {
  enc <- structure(list(type = "unknown-type", binding = list()), class = "nf_encoding")
  row <- list(x = 1)
  expect_false(neurotabs:::encoding_applicable(enc, row))
})
