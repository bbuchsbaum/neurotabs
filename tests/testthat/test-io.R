test_that("nf_read loads roi-only example", {
  path <- system.file("examples/roi-only/nftab.yaml", package = "neurotabs")
  skip_if(path == "", "example not installed")

  ds <- nf_read(path)
  expect_s3_class(ds, "nftab")
  expect_equal(ds$manifest$dataset_id, "roi-only")
  expect_equal(nf_nobs(ds), 8L)
  expect_equal(nf_feature_names(ds), "roi_beta")
})

test_that("nf_write roundtrips a dataset", {
  ds <- .make_roi_nftab()
  tmpdir <- tempfile("nftab_test_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  nf_write(ds, tmpdir)

  expect_true(file.exists(file.path(tmpdir, "nftab.yaml")))
  expect_true(file.exists(file.path(tmpdir, "observations.csv")))

  ds2 <- nf_read(file.path(tmpdir, "nftab.yaml"))
  expect_s3_class(ds2, "nftab")
  expect_equal(nf_nobs(ds2), nf_nobs(ds))
  expect_equal(nf_feature_names(ds2), nf_feature_names(ds))

  # Data roundtrips
  v1 <- nf_resolve(ds, 1L, "roi_beta")
  v2 <- nf_resolve(ds2, 1L, "roi_beta")
  expect_equal(v1, v2)
})

test_that("nf_read rejects manifests that violate the bundled schema", {
  tmpdir <- tempfile("nftab_bad_manifest_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  yaml::write_yaml(
    list(
      spec_version = "0.1.0",
      dataset_id = "bad-manifest",
      storage_profile = "table-package",
      observation_table = list(path = "observations.csv", format = "csv"),
      row_id = "row_id",
      observation_axes = list("subject"),
      observation_columns = list(
        row_id = list(dtype = "string"),
        subject = list(dtype = "string"),
        roi_1 = list(dtype = "float32")
      ),
      features = list(
        roi_beta = list(
          logical = list(kind = "vector", axes = list("roi"), dtype = "float32", shape = list(1L)),
          encodings = list(list(type = "columns", binding = list(columns = list("roi_1"))))
        )
      ),
      bogus = TRUE
    ),
    file.path(tmpdir, "nftab.yaml")
  )
  writeLines("row_id,subject,roi_1\nr1,s1,0.1\n", file.path(tmpdir, "observations.csv"))

  expect_error(nf_read(file.path(tmpdir, "nftab.yaml")), "schema validation")
})

test_that("nf_read coerces observation columns to declared dtypes", {
  tmpdir <- tempfile("nftab_typed_manifest_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  yaml::write_yaml(
    list(
      spec_version = "0.1.0",
      dataset_id = "typed-demo",
      storage_profile = "table-package",
      observation_table = list(path = "observations.csv", format = "csv"),
      row_id = "row_id",
      observation_axes = list("subject"),
      observation_columns = list(
        row_id = list(dtype = "string", nullable = FALSE),
        subject = list(dtype = "string", nullable = FALSE),
        visit = list(dtype = "int32", nullable = FALSE),
        score = list(dtype = "float64", nullable = FALSE),
        flag = list(dtype = "bool", nullable = FALSE),
        acquired = list(dtype = "date", nullable = FALSE),
        payload = list(dtype = "json", nullable = TRUE),
        roi_1 = list(dtype = "float32", nullable = FALSE)
      ),
      features = list(
        roi_beta = list(
          logical = list(kind = "vector", axes = list("roi"), dtype = "float32", shape = list(1L)),
          encodings = list(list(type = "columns", binding = list(columns = list("roi_1"))))
        )
      )
    ),
    file.path(tmpdir, "nftab.yaml")
  )

  data.table::fwrite(
    data.frame(
      row_id = c("r1", "r2"),
      subject = c("s1", "s2"),
      visit = c("1", "2"),
      score = c("0.5", "1.5"),
      flag = c("TRUE", "0"),
      acquired = c("2026-03-07", "2026-03-08"),
      payload = c("{\"a\":1}", NA),
      roi_1 = c("0.25", "0.75"),
      stringsAsFactors = FALSE
    ),
    file.path(tmpdir, "observations.csv")
  )

  ds <- nf_read(file.path(tmpdir, "nftab.yaml"))

  expect_type(ds$observations$row_id, "character")
  expect_type(ds$observations$visit, "integer")
  expect_type(ds$observations$score, "double")
  expect_type(ds$observations$flag, "logical")
  expect_s3_class(ds$observations$acquired, "Date")
  expect_type(ds$observations$payload, "character")
  expect_equal(ds$observations$flag, c(TRUE, FALSE))
})

test_that("nf_read parses support registries for volume features", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("nftab_support_manifest_")
  dir.create(tmpdir)
  dir.create(file.path(tmpdir, "maps"))
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  nifti_path <- file.path(tmpdir, "maps", "stat.nii.gz")
  RNifti::writeNifti(array(1, dim = c(2, 2, 2)), nifti_path)

  yaml::write_yaml(
    list(
      spec_version = "0.1.0",
      dataset_id = "support-demo",
      storage_profile = "table-package",
      observation_table = list(path = "observations.csv", format = "csv"),
      row_id = "row_id",
      observation_axes = list("subject"),
      observation_columns = list(
        row_id = list(dtype = "string", nullable = FALSE),
        subject = list(dtype = "string", nullable = FALSE),
        stat_res = list(dtype = "string", nullable = FALSE)
      ),
      features = list(
        statmap = list(
          logical = list(
            kind = "volume",
            axes = list("x", "y", "z"),
            dtype = "float32",
            support_ref = "demo_grid",
            shape = list(2L, 2L, 2L),
            alignment = "same_grid"
          ),
          encodings = list(
            list(type = "ref", binding = list(resource_id = list(column = "stat_res")))
          )
        )
      ),
      supports = list(
        demo_grid = list(
          support_type = "volume",
          support_id = "support-demo-grid",
          space = "MNI152NLin2009cAsym",
          grid_id = "support-demo-grid"
        )
      ),
      resources = list(path = "resources.csv", format = "csv")
    ),
    file.path(tmpdir, "nftab.yaml")
  )

  data.table::fwrite(
    data.frame(
      row_id = "r1",
      subject = "s1",
      stat_res = "stat1",
      stringsAsFactors = FALSE
    ),
    file.path(tmpdir, "observations.csv")
  )

  data.table::fwrite(
    data.frame(
      resource_id = "stat1",
      backend = "nifti",
      locator = "maps/stat.nii.gz",
      checksum = paste0(
        "md5:",
        digest::digest(file = nifti_path, algo = "md5", serialize = FALSE)
      ),
      stringsAsFactors = FALSE
    ),
    file.path(tmpdir, "resources.csv")
  )

  ds <- nf_read(file.path(tmpdir, "nftab.yaml"))
  expect_equal(ds$manifest$features$statmap$logical$support_ref, "demo_grid")
  expect_equal(ds$manifest$supports$demo_grid$support_id, "support-demo-grid")
})

test_that("nf_read rejects volume manifests without support_ref", {
  tmpdir <- tempfile("nftab_missing_support_ref_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  yaml::write_yaml(
    list(
      spec_version = "0.1.0",
      dataset_id = "missing-support-ref",
      storage_profile = "table-package",
      observation_table = list(path = "observations.csv", format = "csv"),
      row_id = "row_id",
      observation_axes = list("subject"),
      observation_columns = list(
        row_id = list(dtype = "string", nullable = FALSE),
        subject = list(dtype = "string", nullable = FALSE),
        stat_res = list(dtype = "string", nullable = FALSE)
      ),
      features = list(
        statmap = list(
          logical = list(
            kind = "volume",
            axes = list("x", "y", "z"),
            dtype = "float32",
            shape = list(2L, 2L, 2L)
          ),
          encodings = list(
            list(type = "ref", binding = list(resource_id = list(column = "stat_res")))
          )
        )
      ),
      resources = list(path = "resources.csv", format = "csv")
    ),
    file.path(tmpdir, "nftab.yaml")
  )

  data.table::fwrite(
    data.frame(row_id = "r1", subject = "s1", stat_res = "stat1", stringsAsFactors = FALSE),
    file.path(tmpdir, "observations.csv")
  )
  data.table::fwrite(
    data.frame(resource_id = "stat1", backend = "nifti", locator = "maps/stat.nii.gz",
               stringsAsFactors = FALSE),
    file.path(tmpdir, "resources.csv")
  )

  expect_error(nf_read(file.path(tmpdir, "nftab.yaml")), "support_ref|schema validation")
})

test_that("nf_summarise is exported and identical to nf_summarize", {
  expect_identical(nf_summarise, nf_summarize)
})

test_that("nf_write computes sha256 checksums for local resource files", {
  skip_if_not_installed("RNifti")

  tmpdir <- withr::local_tempdir()
  maps_dir <- file.path(tmpdir, "src", "maps")
  dir.create(maps_dir, recursive = TRUE)

  nifti_a <- file.path(maps_dir, "a.nii.gz")
  nifti_b <- file.path(maps_dir, "b.nii.gz")
  RNifti::writeNifti(array(1, dim = c(2, 2, 2)), nifti_a)
  RNifti::writeNifti(array(2, dim = c(2, 2, 2)), nifti_b)

  ds <- .make_ref_nftab(
    dataset_id   = "checksum-test",
    resource_ids = c("res1", "res2"),
    locators     = c("maps/a.nii.gz", "maps/b.nii.gz"),
    backend      = "nifti"
  )
  # Override .root so the locators resolve to our temp files
  ds$.root <- file.path(tmpdir, "src")

  out_dir <- file.path(tmpdir, "out")
  nf_write(ds, out_dir)

  written <- data.table::fread(file.path(out_dir, "resources.csv"),
                                data.table = FALSE)

  expect_true("checksum" %in% names(written))
  non_na <- written$checksum[!is.na(written$checksum)]
  expect_true(length(non_na) > 0L)
  expect_true(all(startsWith(non_na, "sha256:")))
})

test_that("nf_write produces NA checksum for URI locators", {
  ds <- .make_ref_nftab(
    dataset_id   = "uri-checksum-test",
    resource_ids = c("res1", "res2"),
    locators     = c("s3://bucket/a.nii.gz", "s3://bucket/b.nii.gz"),
    backend      = "x-unknown"
  )

  out_dir <- withr::local_tempdir()
  nf_write(ds, out_dir)

  written <- data.table::fread(file.path(out_dir, "resources.csv"),
                                data.table = FALSE)

  expect_true("checksum" %in% names(written))
  expect_true(all(is.na(written$checksum)))
})

test_that("nf_write + nf_read roundtrip preserves data", {
  ds <- .make_roi_nftab()
  tmpdir <- tempfile("io_roundtrip_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  nf_write(ds, tmpdir)
  ds2 <- nf_read(file.path(tmpdir, "nftab.yaml"))

  expect_equal(nf_nobs(ds2), nf_nobs(ds))
  expect_equal(nf_feature_names(ds2), nf_feature_names(ds))
  expect_equal(nf_axes(ds2), nf_axes(ds))
  val1 <- nf_resolve(ds2, "r1", "roi_beta")
  expect_equal(val1, c(0.3, 0.4, 0.3), tolerance = 1e-4)
})

test_that("nf_write + nf_read roundtrip preserves manifest metadata", {
  ds <- .make_roi_nftab()
  tmpdir <- tempfile("io_meta_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  nf_write(ds, tmpdir)
  ds2 <- nf_read(file.path(tmpdir, "nftab.yaml"))

  expect_equal(ds2$manifest$spec_version, ds$manifest$spec_version)
  expect_equal(ds2$manifest$dataset_id, ds$manifest$dataset_id)
  expect_equal(ds2$manifest$row_id, ds$manifest$row_id)
  expect_equal(length(ds2$manifest$observation_columns),
               length(ds$manifest$observation_columns))
})

test_that("nf_read coerces bool columns correctly", {
  tmpdir <- tempfile("io_bool_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  yaml::write_yaml(list(
    spec_version = "0.1.0",
    dataset_id = "bool-test",
    storage_profile = "table-package",
    observation_table = list(path = "obs.csv", format = "csv"),
    row_id = "row_id",
    observation_axes = list("subject"),
    observation_columns = list(
      row_id = list(dtype = "string", nullable = FALSE),
      subject = list(dtype = "string", nullable = FALSE),
      flag = list(dtype = "bool", nullable = FALSE),
      v1 = list(dtype = "float32", nullable = FALSE)
    ),
    features = list(
      f = list(
        logical = list(kind = "vector", axes = list("x"), dtype = "float32", shape = list(1L)),
        encodings = list(list(type = "columns", binding = list(columns = list("v1"))))
      )
    )
  ), file.path(tmpdir, "nftab.yaml"))

  data.table::fwrite(
    data.frame(row_id = c("r1", "r2"), subject = c("s1", "s2"),
               flag = c("true", "false"), v1 = c(1.0, 2.0),
               stringsAsFactors = FALSE),
    file.path(tmpdir, "obs.csv")
  )

  ds <- nf_read(file.path(tmpdir, "nftab.yaml"))
  expect_type(ds$observations$flag, "logical")
  expect_equal(ds$observations$flag, c(TRUE, FALSE))
})

test_that("nf_read coerces integer columns correctly", {
  tmpdir <- tempfile("io_int_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  yaml::write_yaml(list(
    spec_version = "0.1.0",
    dataset_id = "int-test",
    storage_profile = "table-package",
    observation_table = list(path = "obs.csv", format = "csv"),
    row_id = "row_id",
    observation_axes = list("subject"),
    observation_columns = list(
      row_id = list(dtype = "string", nullable = FALSE),
      subject = list(dtype = "string", nullable = FALSE),
      age = list(dtype = "int32", nullable = FALSE),
      v1 = list(dtype = "float32", nullable = FALSE)
    ),
    features = list(
      f = list(
        logical = list(kind = "vector", axes = list("x"), dtype = "float32", shape = list(1L)),
        encodings = list(list(type = "columns", binding = list(columns = list("v1"))))
      )
    )
  ), file.path(tmpdir, "nftab.yaml"))

  data.table::fwrite(
    data.frame(row_id = c("r1", "r2"), subject = c("s1", "s2"),
               age = c(25L, 30L), v1 = c(1.0, 2.0),
               stringsAsFactors = FALSE),
    file.path(tmpdir, "obs.csv")
  )

  ds <- nf_read(file.path(tmpdir, "nftab.yaml"))
  expect_type(ds$observations$age, "integer")
  expect_equal(ds$observations$age, c(25L, 30L))
})

test_that("nf_read coerces date columns correctly", {
  tmpdir <- tempfile("io_date_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  yaml::write_yaml(list(
    spec_version = "0.1.0",
    dataset_id = "date-test",
    storage_profile = "table-package",
    observation_table = list(path = "obs.csv", format = "csv"),
    row_id = "row_id",
    observation_axes = list("subject"),
    observation_columns = list(
      row_id = list(dtype = "string", nullable = FALSE),
      subject = list(dtype = "string", nullable = FALSE),
      scan_date = list(dtype = "date", nullable = TRUE),
      v1 = list(dtype = "float32", nullable = FALSE)
    ),
    features = list(
      f = list(
        logical = list(kind = "vector", axes = list("x"), dtype = "float32", shape = list(1L)),
        encodings = list(list(type = "columns", binding = list(columns = list("v1"))))
      )
    )
  ), file.path(tmpdir, "nftab.yaml"))

  data.table::fwrite(
    data.frame(row_id = c("r1", "r2"), subject = c("s1", "s2"),
               scan_date = c("2024-01-15", "2024-06-30"), v1 = c(1.0, 2.0),
               stringsAsFactors = FALSE),
    file.path(tmpdir, "obs.csv")
  )

  ds <- nf_read(file.path(tmpdir, "nftab.yaml"))
  expect_s3_class(ds$observations$scan_date, "Date")
})

test_that("nf_read coerces datetime columns correctly", {
  tmpdir <- tempfile("io_datetime_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  yaml::write_yaml(list(
    spec_version = "0.1.0",
    dataset_id = "datetime-test",
    storage_profile = "table-package",
    observation_table = list(path = "obs.csv", format = "csv"),
    row_id = "row_id",
    observation_axes = list("subject"),
    observation_columns = list(
      row_id = list(dtype = "string", nullable = FALSE),
      subject = list(dtype = "string", nullable = FALSE),
      acquired = list(dtype = "datetime", nullable = TRUE),
      v1 = list(dtype = "float32", nullable = FALSE)
    ),
    features = list(
      f = list(
        logical = list(kind = "vector", axes = list("x"), dtype = "float32", shape = list(1L)),
        encodings = list(list(type = "columns", binding = list(columns = list("v1"))))
      )
    )
  ), file.path(tmpdir, "nftab.yaml"))

  data.table::fwrite(
    data.frame(row_id = c("r1", "r2"), subject = c("s1", "s2"),
               acquired = c("2024-01-15T10:30:00", "2024-06-30T14:00:00"),
               v1 = c(1.0, 2.0), stringsAsFactors = FALSE),
    file.path(tmpdir, "obs.csv")
  )

  ds <- nf_read(file.path(tmpdir, "nftab.yaml"))
  expect_s3_class(ds$observations$acquired, "POSIXct")
})

test_that("nf_read + nf_write roundtrip with ref encoding and resources", {
  skip_if_not_installed("RNifti")

  tmpdir <- tempfile("io_ref_rt_")
  dir.create(file.path(tmpdir, "maps"), recursive = TRUE)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  arr <- array(1:8, dim = c(2, 2, 2))
  RNifti::writeNifti(arr, file.path(tmpdir, "maps", "vol.nii.gz"))

  yaml::write_yaml(list(
    spec_version = "0.1.0",
    dataset_id = "ref-rt",
    storage_profile = "table-package",
    observation_table = list(path = "obs.csv", format = "csv"),
    row_id = "row_id",
    observation_axes = list("subject"),
    observation_columns = list(
      row_id = list(dtype = "string", nullable = FALSE),
      subject = list(dtype = "string", nullable = FALSE),
      res = list(dtype = "string", nullable = FALSE)
    ),
    features = list(
      vol = list(
        logical = list(
          kind = "volume", axes = list("x", "y", "z"), dtype = "float32",
          shape = list(2L, 2L, 2L), support_ref = "g"
        ),
        encodings = list(list(
          type = "ref",
          binding = list(resource_id = list(column = "res"))
        ))
      )
    ),
    supports = list(
      g = list(support_type = "volume", support_id = "g", space = "MNI", grid_id = "g")
    ),
    resources = list(path = "resources.csv", format = "csv")
  ), file.path(tmpdir, "nftab.yaml"))

  data.table::fwrite(
    data.frame(row_id = "r1", subject = "s1", res = "v1", stringsAsFactors = FALSE),
    file.path(tmpdir, "obs.csv")
  )
  data.table::fwrite(
    data.frame(resource_id = "v1", backend = "nifti", locator = "maps/vol.nii.gz",
               stringsAsFactors = FALSE),
    file.path(tmpdir, "resources.csv")
  )

  ds <- nf_read(file.path(tmpdir, "nftab.yaml"))
  expect_s3_class(ds, "nftab")

  # Write to new location
  outdir <- tempfile("io_ref_out_")
  on.exit(unlink(outdir, recursive = TRUE), add = TRUE)
  nf_write(ds, outdir)
  expect_true(file.exists(file.path(outdir, "nftab.yaml")))
  expect_true(file.exists(file.path(outdir, "resources.csv")))
})

test_that("nf_write with JSON manifest format", {
  ds <- .make_roi_nftab()
  tmpdir <- tempfile("io_json_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  nf_write(ds, tmpdir, manifest_name = "nftab.json")
  expect_true(file.exists(file.path(tmpdir, "nftab.json")))

  content <- jsonlite::fromJSON(file.path(tmpdir, "nftab.json"),
                                 simplifyVector = FALSE)
  expect_equal(content$dataset_id, "test-roi")
})

test_that("nf_write roundtrip preserves axis_domains and alignment", {
  ds <- .make_labeled_roi_nftab()
  tmpdir <- tempfile("io_schema_rt_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  nf_write(ds, tmpdir)
  ds2 <- nf_read(file.path(tmpdir, "nftab.yaml"))

  schema2 <- nf_feature_schema(ds2, "roi_beta")
  expect_equal(schema2$axes, "roi")
  expect_true(!is.null(schema2$axis_domains))
  expect_equal(schema2$axis_domains$roi$id, "demo-atlas")
})

test_that("nf_write roundtrip preserves supports", {
  skip_if_not_installed("RNifti")
  ds <- .make_ref_nftab()
  tmpdir <- tempfile("io_support_rt_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  nf_write(ds, tmpdir)
  ds2 <- nf_read(file.path(tmpdir, "nftab.yaml"))

  expect_true("test_grid" %in% names(ds2$manifest$supports))
  expect_equal(ds2$manifest$supports$test_grid$support_type, "volume")
  expect_equal(ds2$manifest$supports$test_grid$space, "MNI152NLin2009cAsym")
})

test_that("nf_read with validate_schema=FALSE skips JSON schema validation", {
  path <- system.file("examples/roi-only/nftab.yaml", package = "neurotabs")
  skip_if(path == "", "example not installed")
  ds <- nf_read(path, validate_schema = FALSE)
  expect_s3_class(ds, "nftab")
})

test_that("nf_write with TSV format observation table", {
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE),
    subject = nf_col_schema("string", nullable = FALSE),
    v1 = nf_col_schema("float32")
  )
  feat <- nf_feature(
    logical = nf_logical_schema("vector", "roi", "float32", shape = 1L),
    encodings = list(nf_columns_encoding("v1"))
  )
  m <- nf_manifest(
    dataset_id = "tsv-test", row_id = "row_id",
    observation_axes = "subject",
    observation_columns = obs_cols,
    features = list(f = feat),
    observation_table_format = "tsv",
    observation_table_path = "observations.tsv"
  )
  obs <- data.frame(row_id = "r1", subject = "s1", v1 = 1.5, stringsAsFactors = FALSE)
  ds <- nftab(m, obs)

  tmpdir <- tempfile("io_tsv_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)
  nf_write(ds, tmpdir)
  expect_true(file.exists(file.path(tmpdir, "observations.tsv")))

  ds2 <- nf_read(file.path(tmpdir, "nftab.yaml"))
  expect_equal(nf_nobs(ds2), 1L)
})

test_that("nf_write roundtrip with extensions", {
  ds <- .make_masked_volume_nftab()
  tmpdir <- tempfile("io_ext_rt_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  nf_write(ds, tmpdir)
  ds2 <- nf_read(file.path(tmpdir, "nftab.yaml"))

  expect_true("x-masked-volume" %in% names(nf_extensions(ds2)))
})

test_that("nf_write roundtrip with ref+columns dual encoding", {
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE),
    subject = nf_col_schema("string", nullable = FALSE),
    bk = nf_col_schema("string", nullable = TRUE),
    loc = nf_col_schema("string", nullable = TRUE),
    roi_1 = nf_col_schema("float32"),
    roi_2 = nf_col_schema("float32")
  )
  feat <- nf_feature(
    logical = nf_logical_schema("vector", "roi", "float32", shape = 2L),
    encodings = list(
      nf_ref_encoding(backend = nf_col("bk"), locator = nf_col("loc")),
      nf_columns_encoding(c("roi_1", "roi_2"))
    )
  )
  m <- nf_manifest(dataset_id = "dual-enc", row_id = "row_id",
    observation_axes = "subject", observation_columns = obs_cols,
    features = list(data = feat))
  obs <- data.frame(row_id = c("r1", "r2"), subject = c("s1", "s2"),
    bk = c(NA, NA), loc = c(NA, NA), roi_1 = c(1.0, 3.0),
    roi_2 = c(2.0, 4.0), stringsAsFactors = FALSE)
  ds <- nftab(m, obs)

  tmpdir <- tempfile("dual_enc_rt_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)
  nf_write(ds, tmpdir)
  ds2 <- nf_read(file.path(tmpdir, "nftab.yaml"))

  val <- nf_resolve(ds2, "r1", "data")
  expect_equal(val, c(1.0, 2.0), tolerance = 1e-4)
  expect_equal(length(ds2$manifest$features$data$encodings), 2L)
})

test_that("nf_write roundtrip preserves nullable feature", {
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE),
    subject = nf_col_schema("string", nullable = FALSE),
    roi_1 = nf_col_schema("float32", nullable = TRUE)
  )
  feat <- nf_feature(
    logical = nf_logical_schema("vector", "roi", "float32", shape = 1L),
    encodings = list(nf_columns_encoding("roi_1")),
    nullable = TRUE,
    description = "A nullable feature"
  )
  m <- nf_manifest(dataset_id = "nullable-ft", row_id = "row_id",
    observation_axes = "subject", observation_columns = obs_cols,
    features = list(f = feat))
  obs <- data.frame(row_id = "r1", subject = "s1", roi_1 = NA_real_,
    stringsAsFactors = FALSE)
  ds <- nftab(m, obs)

  tmpdir <- tempfile("nullable_ft_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)
  nf_write(ds, tmpdir)
  ds2 <- nf_read(file.path(tmpdir, "nftab.yaml"))
  expect_true(ds2$manifest$features$f$nullable)
  expect_equal(ds2$manifest$features$f$description, "A nullable feature")
})

test_that("nf_write roundtrip with surface support", {
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE),
    subject = nf_col_schema("string", nullable = FALSE),
    v1 = nf_col_schema("float32")
  )
  feat <- nf_feature(
    logical = nf_logical_schema("surface", "vertex", "float32", shape = 1L,
      support_ref = "fs", alignment = "same_topology"),
    encodings = list(nf_columns_encoding("v1"))
  )
  sup <- nf_support_surface("fs-left", "fsaverage", "fs-mesh", "fs-topo", "left")
  m <- nf_manifest(dataset_id = "surf-test", row_id = "row_id",
    observation_axes = "subject", observation_columns = obs_cols,
    features = list(f = feat),
    supports = list(fs = sup))
  obs <- data.frame(row_id = "r1", subject = "s1", v1 = 0.5,
    stringsAsFactors = FALSE)
  ds <- nftab(m, obs)

  tmpdir <- tempfile("surf_rt_")
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)
  nf_write(ds, tmpdir)
  ds2 <- nf_read(file.path(tmpdir, "nftab.yaml"))
  expect_equal(ds2$manifest$supports$fs$support_type, "surface")
  expect_equal(ds2$manifest$supports$fs$hemisphere, "left")
})
