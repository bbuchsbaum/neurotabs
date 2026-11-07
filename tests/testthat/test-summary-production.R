.summary_dataset <- function() {
  x <- .make_roi_nftab()
  root <- tempfile("summary-source-")
  dir.create(root)
  file.copy(.summary_contract_path("roundtrip.csv"), file.path(root, "summaries.csv"))
  descriptor <- list(version = "0.1.0", tables = list(effects = list(
    table = list(path = "summaries.csv", format = "csv"),
    statistic = "mean", counting_unit = "subject")))
  x$manifest$extensions <- list(`x-summary` = descriptor, `x-other` = list(note = "keep"))
  x$.root <- root
  x
}

test_that("public summary validation exercises every shared canonical row", {
  skip_if_not_installed("jsonvalidate")
  x <- .summary_dataset()
  on.exit(unlink(x$.root, recursive = TRUE))
  expect_true(nf_validate_summary(x)$valid)
  for (class in c("valid", "invalid")) {
    for (case in .summary_contract_json("cases.json")[[class]]) {
      .summary_contract_write_csv(list(case$row), file.path(x$.root, "summaries.csv"))
      result <- nf_validate_summary(x)
      expect_identical(result$valid, class == "valid", info = case$id)
      if (class == "invalid") expect_true(length(result$errors) > 0L, info = case$id)
    }
  }
})

test_that("descriptor files, lists, empty tables and plot references are checked", {
  skip_if_not_installed("jsonvalidate")
  expect_true(nf_validate_summary(.summary_contract_path("descriptor.json"))$valid)
  x <- .summary_dataset()
  on.exit(unlink(x$.root, recursive = TRUE))
  d <- x$manifest$extensions[["x-summary"]]
  expect_false(nf_validate_summary(d)$valid)
  expect_true(nf_validate_summary(d, x$.root)$valid)
  d$tables$effects$design <- list(subject = "subject", within = setNames(list(), character()),
                                 between = character())
  expect_true(nf_validate_summary(d, x$.root)$valid)
  d$tables$effects$plot <- list(mark = "point", x = "region_id",
                                order = list(region_id = "001"))
  expect_true(nf_validate_summary(d, x$.root)$valid)
  d$tables$effects$plot$x <- "missing"
  expect_match(nf_validate_summary(d, x$.root)$errors, "unknown columns")
  d$tables$effects$plot$x <- "region_id"
  d$tables$effects$plot$order <- list(region_id = "002")
  expect_match(nf_validate_summary(d, x$.root)$errors, "omits")
  d$tables$effects$plot <- NULL
  writeLines("estimate,lower,upper,interval_kind", file.path(x$.root, "summaries.csv"))
  expect_true(nf_validate_summary(d, x$.root)$valid)
  writeLines("estimate,lower,upper,interval_kind\nNaN,,,none", file.path(x$.root, "summaries.csv"))
  expect_match(nf_validate_summary(d, x$.root)$errors, "numeric")
})

test_that("summary paths cannot escape through traversal or symlinks", {
  skip_if_not_installed("jsonvalidate")
  x <- .summary_dataset()
  on.exit(unlink(x$.root, recursive = TRUE))
  d <- x$manifest$extensions[["x-summary"]]
  d$tables$effects$table$path <- "../outside.csv"
  expect_false(nf_validate_summary(d, x$.root)$valid)
  outside <- tempfile(fileext = ".csv")
  file.copy(file.path(x$.root, "summaries.csv"), outside)
  on.exit(unlink(outside), add = TRUE)
  link <- file.path(x$.root, "escape.csv")
  skip_if_not(file.symlink(outside, link))
  d$tables$effects$table$path <- "escape.csv"
  expect_match(nf_validate_summary(d, x$.root)$errors, "escapes")
})

test_that("nf_write preserves summary files and descriptor arrays on relocation", {
  skip_if_not_installed("jsonvalidate")
  x <- .summary_dataset()
  out <- tempfile("summary-dest-")
  on.exit(unlink(c(x$.root, out), recursive = TRUE))
  x$manifest$extensions[["x-summary"]]$tables$effects$plot <- list(
    mark = "point", x = "region_id", order = list(region_id = "001"))
  for (name in c("nftab.yaml", "nftab.json")) {
    nf_write(x, out, manifest_name = name)
    copied <- nf_read(file.path(out, name))
    expect_true(nf_validate_summary(copied)$valid)
    expect_true(nf_validate_summary(file.path(out, name))$valid)
    expect_identical(readBin(file.path(out, "summaries.csv"), "raw", n = 100000),
                     readBin(file.path(x$.root, "summaries.csv"), "raw", n = 100000))
  }
  nf_write(x, x$.root)
  expect_true(nf_validate_summary(x)$valid)
})

test_that("nf_write rejects missing, conflicting and escaping summary outputs before core writes", {
  skip_if_not_installed("jsonvalidate")
  x <- .summary_dataset()
  out <- tempfile("summary-dest-")
  dir.create(out)
  on.exit(unlink(c(x$.root, out), recursive = TRUE))
  writeLines("keep this file", file.path(out, "summaries.csv"))
  expect_error(nf_write(x, out), "different data")
  expect_false(file.exists(file.path(out, "observations.csv")))
  expect_identical(readLines(file.path(out, "summaries.csv")), "keep this file")
  unlink(file.path(out, "summaries.csv"))
  file.symlink(x$.root, file.path(out, "nested"))
  d <- x$manifest$extensions[["x-summary"]]
  d$tables$effects$table$path <- "nested/summaries.csv"
  dir.create(file.path(x$.root, "nested"))
  file.copy(file.path(x$.root, "summaries.csv"), file.path(x$.root, "nested", "summaries.csv"))
  x$manifest$extensions[["x-summary"]] <- d
  expect_error(nf_write(x, out), "escapes")
  expect_false(file.exists(file.path(out, "observations.csv")))
  x$manifest$extensions[["x-summary"]]$tables$effects$table$path <- "missing.csv"
  expect_error(nf_write(x, out), "not found")
})

test_that("observation changes drop only x-summary, warn, and leave the source intact", {
  x <- .summary_dataset()
  on.exit(unlink(x$.root, recursive = TRUE))
  operations <- list(
    function() nf_filter(x, condition == "faces"),
    function() nf_select(x, .cols = "subject"),
    function() nf_mutate(x, roi_1 = roi_1 + 1),
    function() nf_arrange(x, .by = "condition"),
    function() nf_compare(x, roi_beta, .ref = list(subject = "s01", condition = "faces")),
    function() nf_mutate_feature(x, shifted, roi_beta, function(v) v + 1),
    function() x[1:2])
  for (op in operations) {
    expect_warning(result <- op(), "dropped x-summary")
    expect_null(nf_extensions(result)[["x-summary"]])
    expect_identical(nf_extensions(result)[["x-other"]], list(note = "keep"))
  }
  alt <- .make_alt_roi_nftab()
  alt$manifest$extensions <- list(`x-other` = list(note = "keep"))
  expect_warning(combined <- nf_concat(x, alt), "dropped x-summary")
  expect_null(nf_extensions(combined)[["x-summary"]])
  expect_identical(nf_extensions(combined)[["x-other"]], list(note = "keep"))
  expect_warning(nf_summarize(x, roi_beta, by = "condition"), "dropped x-summary")
  expect_no_warning(copy <- x[seq_len(nrow(x$observations))])
  expect_identical(nf_extensions(copy), nf_extensions(x))
  expect_true(file.exists(file.path(x$.root, "summaries.csv")))
  expect_false(is.null(nf_extensions(x)[["x-summary"]]))
})

test_that("CSV rows must match the header width and use decimal numbers", {
  skip_if_not_installed("jsonvalidate")
  x <- .summary_dataset()
  on.exit(unlink(x$.root, recursive = TRUE))
  csv <- file.path(x$.root, "summaries.csv")
  writeLines(c("estimate,lower,upper,interval_kind,b", "9,1,,,none,z", "8,2,,,none,y"), csv)
  expect_false(nf_validate_summary(x)$valid)
  writeLines(c("estimate,lower,upper,interval_kind,", "1,,,none,z"), csv)
  expect_match(nf_validate_summary(x)$errors, "nonempty names")
  for (bad in c("0x10", " 1", "1.", ".5", "+1")) {
    writeLines(c("estimate,lower,upper,interval_kind", paste0(bad, ",,,none")), csv)
    expect_false(nf_validate_summary(x)$valid, info = bad)
  }
  writeLines(c("estimate,lower,upper,interval_kind", "-1.5e-3,,,none"), csv)
  expect_true(nf_validate_summary(x)$valid)
  writeLines(c("estimate,lower,upper,interval_kind,note", "1,,,none,", "", ""), csv)
  result <- nf_validate_summary(x)
  expect_true(result$valid)
  expect_identical(nrow(result$tables$effects), 1L)
  expect_true(is.na(result$tables$effects$note))
  writeLines(c("estimate,lower,upper,interval_kind", "1,,,none", "", "2,,,none"), csv)
  expect_false(nf_validate_summary(x)$valid)
  writeBin(charToRaw("estimate,lower,upper,interval_kind,note\r\n1,,,none,\"a,b\"\r\n"), csv)
  result <- nf_validate_summary(x)
  expect_true(result$valid)
  expect_identical(result$tables$effects$note, "a,b")
})

test_that("tables are decoded as UTF-8 regardless of locale, with or without a BOM", {
  skip_if_not_installed("jsonvalidate")
  x <- .summary_dataset()
  on.exit(unlink(x$.root, recursive = TRUE))
  csv <- file.path(x$.root, "summaries.csv")
  lines <- enc2utf8(c("estimate,lower,upper,interval_kind,cond", "1,,,none,café"))
  con <- file(csv, "wb")
  writeBin(c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw(paste0(paste(lines, collapse = "\n"), "\n"))), con)
  close(con)
  d <- x$manifest$extensions[["x-summary"]]
  d$tables$effects$plot <- list(mark = "point", x = "cond", order = list(cond = list("café")))
  x$manifest$extensions[["x-summary"]] <- d
  result <- nf_validate_summary(x)
  expect_true(result$valid, info = paste(result$errors, collapse = "; "))
  expect_identical(result$tables$effects$cond, "café")
  expect_identical(names(result$tables$effects)[1], "estimate")
  writeBin(as.raw(c(0x65, 0x0a, 0xff, 0x0a)), csv)
  expect_match(nf_validate_summary(x)$errors, "UTF-8")
})

test_that("nf_write rejects case-insensitive and nested collisions before writing", {
  skip_if_not_installed("jsonvalidate")
  x <- .summary_dataset()
  on.exit(unlink(x$.root, recursive = TRUE), add = TRUE)
  out <- tempfile("summary-collide-")
  on.exit(unlink(out, recursive = TRUE), add = TRUE)
  file.copy(file.path(x$.root, "summaries.csv"), file.path(x$.root, "Observations.csv"))
  x$manifest$extensions[["x-summary"]]$tables$effects$table$path <- "Observations.csv"
  expect_error(nf_write(x, out), "collides")
  expect_false(dir.exists(out))
  unlink(file.path(x$.root, "Observations.csv"))
  dir.create(file.path(x$.root, "observations.csv"))
  file.copy(file.path(x$.root, "summaries.csv"), file.path(x$.root, "observations.csv", "s.csv"))
  x$manifest$extensions[["x-summary"]]$tables$effects$table$path <- "observations.csv/s.csv"
  expect_error(nf_write(x, out), "collides")
  expect_false(dir.exists(out))
  d <- x$manifest$extensions[["x-summary"]]
  d$tables$effects$table$path <- "summaries.csv"
  d$tables$other <- d$tables$effects
  d$tables$other$table$path <- "SUMMARIES.csv"
  file.copy(file.path(x$.root, "summaries.csv"), file.path(x$.root, "SUMMARIES.csv"))
  x$manifest$extensions[["x-summary"]] <- d
  if (!file.exists(file.path(x$.root, "SUMMARIES.csv")) ||
      normalizePath(file.path(x$.root, "SUMMARIES.csv")) != normalizePath(file.path(x$.root, "summaries.csv"))) {
    expect_error(nf_write(x, out), "collide")
  }
  expect_error(nf_write(x, out, manifest_name = "nftab.txt"), "manifest_name")
  expect_false(dir.exists(out))
})

test_that("JSON manifests leave user extension values unchanged", {
  skip_if_not_installed("jsonvalidate")
  x <- .summary_dataset()
  on.exit(unlink(x$.root, recursive = TRUE), add = TRUE)
  x$manifest$extensions[["x-other"]] <- list(levels = 3L, note = "keep")
  out <- tempfile("summary-json-")
  on.exit(unlink(out, recursive = TRUE), add = TRUE)
  nf_write(x, out, manifest_name = "nftab.json")
  back <- nf_read(file.path(out, "nftab.json"))
  expect_identical(nf_extensions(back)[["x-other"]]$levels, 3L)
  expect_true(nf_validate_summary(back)$valid)
})

test_that("nf_concat keeps identical extensions and warns about differing ones", {
  a <- .make_roi_nftab()
  b <- .make_alt_roi_nftab()
  a$manifest$extensions <- list(`x-same` = list(v = 1), `x-diff` = list(v = 1))
  b$manifest$extensions <- list(`x-same` = list(v = 1), `x-diff` = list(v = 2))
  expect_warning(out <- nf_concat(a, b), "differ between inputs: x-diff")
  expect_identical(nf_extensions(out), list(`x-same` = list(v = 1)))
  b$manifest$extensions <- a$manifest$extensions
  expect_no_warning(out <- nf_concat(a, b))
  expect_identical(nf_extensions(out), a$manifest$extensions)
})

test_that("nf_concat carries matching x-masked-volume maps and rejects differing ones", {
  a <- .make_masked_volume_nftab()
  b <- .make_masked_volume_nftab()
  on.exit(unlink(c(a$.root, b$.root), recursive = TRUE))
  b$observations$subject <- paste0(b$observations$subject, "b")
  b$observations$row_id <- paste0(b$observations$row_id, "b")
  out <- nf_concat(a, b)
  map <- nf_extension(out, "x-masked-volume")$features$statvec$index_map$path
  expect_true(file.exists(map))
  expect_true(nf_validate(out, level = "structural")$valid)
  tab <- utils::read.delim(file.path(b$.root, "voxel_index.tsv"))
  tab$x <- rev(tab$x)
  utils::write.table(tab, file.path(b$.root, "voxel_index.tsv"), sep = "\t", row.names = FALSE, quote = FALSE)
  expect_match(nf_compatible(a, b)$reasons, "x-masked-volume mapping mismatch", all = FALSE)
  expect_error(nf_concat(a, b), "x-masked-volume")
})

test_that("grouped nf_summarize keeps other extensions and the summarized masked map", {
  x <- .make_masked_volume_nftab()
  on.exit(unlink(x$.root, recursive = TRUE))
  x$manifest$extensions[["x-other"]] <- list(note = "keep")
  x$manifest$extensions[["x-summary"]] <- list(version = "0.1.0", tables = list())
  expect_warning(out <- nf_summarize(x, statvec, by = "condition"), "dropped x-summary")
  ext <- nf_extensions(out)
  expect_identical(ext[["x-other"]], list(note = "keep"))
  expect_null(ext[["x-summary"]])
  expect_named(ext[["x-masked-volume"]]$features, "statvec")
  expect_true(nf_validate(out, level = "structural")$valid)
  expect_null(suppressWarnings(nf_extensions(
    nf_summarize(x, statvec, by = "condition", .f = function(v) sum(unlist(v))))[["x-masked-volume"]]))
})
