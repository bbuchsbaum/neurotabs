test_that("nf_col_schema validates dtype", {
  expect_s3_class(nf_col_schema("string"), "nf_col_schema")
  expect_s3_class(nf_col_schema("float32", nullable = FALSE), "nf_col_schema")
  expect_error(nf_col_schema("bad_type"))
})

test_that("nf_logical_schema validates shape/axes consistency", {
  ls <- nf_logical_schema("volume", c("x", "y", "z"), "float32",
                          shape = c(91L, 109L, 91L),
                          support_ref = "mni_2mm",
                          space = "MNI152NLin2009cAsym",
                          alignment = "same_grid")
  expect_s3_class(ls, "nf_logical_schema")
  expect_equal(ls$shape, c(91L, 109L, 91L))
  expect_equal(ls$support_ref, "mni_2mm")

  # shape/axes length mismatch

  expect_error(
    nf_logical_schema("volume", c("x", "y", "z"), "float32",
                      shape = c(91L, 109L),
                      support_ref = "mni_2mm"),
    "length\\(shape\\)"
  )
})

test_that("nf_logical_schema validates alignment and support requirements", {
  expect_error(
    nf_logical_schema("volume", c("x","y","z"), "float32", alignment = "bogus",
                      support_ref = "mni_2mm")
  )
  expect_error(
    nf_logical_schema("volume", c("x", "y", "z"), "float32"),
    "support_ref"
  )
  expect_error(
    nf_logical_schema("surface", "vertex", "float32"),
    "support_ref"
  )
  expect_error(
    nf_logical_schema("volume", c("x", "y", "z"), "float32",
                      support_ref = "mni_2mm", alignment = "same_topology"),
    "same_topology"
  )
})

test_that("nf_schema_fingerprint is stable", {
  a <- nf_logical_schema("vector", "roi", "float32", shape = 5L)
  b <- nf_logical_schema("vector", "roi", "float32", shape = 5L)
  expect_equal(nf_schema_fingerprint(a), nf_schema_fingerprint(b))

  # Different shape => different fingerprint
  c <- nf_logical_schema("vector", "roi", "float32", shape = 10L)
  expect_false(nf_schema_fingerprint(a) == nf_schema_fingerprint(c))
})

test_that("nf_axis_domain constructor works", {
  ad <- nf_axis_domain(id = "desikan68", size = 68L)
  expect_s3_class(ad, "nf_axis_domain")
  expect_equal(ad$size, 68L)
})

test_that("support constructors work", {
  vol <- nf_support_volume(
    support_id = "mni152-2mm-grid",
    space = "MNI152NLin2009cAsym",
    grid_id = "mni152-2mm-grid"
  )
  surf <- nf_support_surface(
    support_id = "fsaverage-left",
    template = "fsaverage",
    mesh_id = "fsaverage-32k",
    topology_id = "fsaverage-32k-left",
    hemisphere = "left"
  )

  expect_equal(vol$support_type, "volume")
  expect_equal(surf$support_type, "surface")
})

test_that("nf_support_generic creates generic support", {
  g <- nf_support_generic(support_id = "my-atlas", description = "A generic atlas")
  expect_s3_class(g, "nf_support_schema")
  expect_equal(g$support_type, "generic")
  expect_equal(g$support_id, "my-atlas")
  expect_equal(g$description, "A generic atlas")
})

test_that("nf_support errors on missing required fields", {
  expect_error(
    nf_support("volume", "mni-grid"),
    "volume support requires fields"
  )
  expect_error(
    nf_support("surface", "fs-left"),
    "surface support requires fields"
  )
})

test_that("nf_support_volume stores affine_id", {
  vol <- nf_support_volume(
    support_id = "mni152-2mm",
    space = "MNI152",
    grid_id = "mni-grid",
    affine_id = "mni-affine"
  )
  expect_equal(vol$affine_id, "mni-affine")
})

test_that("print methods produce output without error", {
  vol <- nf_support_volume("mni-grid", "MNI152", "mni-grid-2mm")
  expect_output(print(vol), "nf_support_schema")
  expect_output(print(vol), "volume")

  surf <- nf_support_surface("fs-left", "fsaverage", "fs-mesh", "fs-topo", "left")
  expect_output(print(surf), "surface")
  expect_output(print(surf), "hemisphere")

  ad <- nf_axis_domain(id = "desikan", labels = "labels.tsv", size = 68L, description = "Desikan atlas")
  expect_output(print(ad), "nf_axis_domain")
  expect_output(print(ad), "desikan")

  cs <- nf_col_schema("float32", nullable = FALSE, semantic_role = "covariate")
  expect_output(print(cs), "nf_col_schema")
  expect_output(print(cs), "NOT NULL")

  ls <- nf_logical_schema("vector", "roi", "float32", shape = 10L,
                          support_ref = NULL, space = "MNI152", alignment = "same_space")
  expect_output(print(ls), "nf_logical_schema")
  expect_output(print(ls), "same_space")
})

test_that("nf_axis_domain validates size", {
  expect_error(nf_axis_domain(size = 0L), "size >= 1")
})

test_that("nf_logical_schema surface + same_grid alignment errors", {
  expect_error(
    nf_logical_schema("surface", "vertex", "float32", support_ref = "fs",
                      alignment = "same_grid"),
    "same_grid"
  )
})

test_that("nf_schema_fingerprint changes when support_id differs", {
  ls <- nf_logical_schema("vector", "roi", "float32", shape = 5L)
  fp1 <- nf_schema_fingerprint(ls, support_id = "support-a")
  fp2 <- nf_schema_fingerprint(ls, support_id = "support-b")
  expect_false(identical(fp1, fp2))
})

test_that("nf_col_schema stores all optional fields", {
  cs <- nf_col_schema("string", nullable = FALSE, semantic_role = "subject",
                      levels = c("a", "b"), unit = "N/A", description = "Subject ID")
  expect_equal(cs$levels, c("a", "b"))
  expect_equal(cs$unit, "N/A")
  expect_equal(cs$description, "Subject ID")
})

test_that("print.nf_col_schema without nullable flag omits [NOT NULL]", {
  cs <- nf_col_schema("string")  # nullable = TRUE by default
  out <- capture.output(print(cs))
  expect_false(any(grepl("NOT NULL", out)))
})
