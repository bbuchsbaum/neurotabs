test_that("nf_register_backend registers and nf_backends lists it", {
  nf_register_backend("x-test-reg", function(l, s, ls) NULL)
  expect_true("x-test-reg" %in% nf_backends())
})

test_that("nf_register_backend stores write_fn", {
  writer <- function(l, v, ls, t, sr) invisible(l)
  nf_register_backend("x-test-writer", function(l, s, ls) NULL, write_fn = writer)
  fn <- neurotabs:::.get_backend_writer("x-test-writer")
  expect_identical(fn, writer)
})

test_that(".get_backend_writer returns NULL for unknown backend", {
  result <- neurotabs:::.get_backend_writer("x-nonexistent-backend")
  expect_null(result)
})

test_that(".get_backend_writer returns NULL when backend has no write_fn", {
  nf_register_backend("x-no-writer", function(l, s, ls) NULL)
  fn <- neurotabs:::.get_backend_writer("x-no-writer")
  expect_null(fn)
})

test_that("nf_register_backend validates arguments", {
  expect_error(nf_register_backend("", function(l, s, ls) NULL))
  expect_error(nf_register_backend("x-ok", "not_a_function"))
  expect_error(nf_register_backend("x-ok", function(l, s, ls) NULL, write_fn = "not_fn"))
})

test_that(".get_backend returns registered backend list", {
  nf_register_backend("x-test-get", function(l, s, ls) "resolved")
  be <- neurotabs:::.get_backend("x-test-get")
  expect_true(is.list(be))
  expect_equal(be$name, "x-test-get")
  expect_true(is.function(be$resolve_fn))
})
