test_that("draft contract artifact inventory is intact", {
  m <- .summary_contract_json("compatibility.json")
  expect_identical(m$status, "draft")
  expect_length(m$calculator_profiles, 0L)
  for (name in names(m$files)) {
    expect_identical(digest::digest(file = .summary_contract_path(name),
                                   algo = "sha256", serialize = FALSE),
                     m$files[[name]], info = name)
  }
  kinds <- .summary_contract_json("interval-kinds.json")$kinds
  ids <- vapply(kinds, `[[`, "", "id")
  expect_false(anyDuplicated(ids) > 0L)
  row_schema <- .summary_contract_json("summary-row.schema.json")
  expect_setequal(unlist(row_schema$properties$interval_kind$enum), ids)
})

test_that("stored summary fixtures validate, label, and round trip", {
  skip_if_not_installed("jsonvalidate")
  cases <- .summary_contract_json("cases.json")
  for (case in cases$valid) {
    expect_true(.summary_contract_valid(case$row), info = case$id)
    expect_identical(.summary_contract_label(case$row), case$label, info = case$id)
    encoded <- jsonlite::toJSON(case$row, auto_unbox = TRUE, null = "null", digits = I(17))
    decoded <- jsonlite::fromJSON(encoded, simplifyVector = FALSE)
    expect_equal(decoded, case$row, tolerance = 0, info = case$id)
    expect_true(.summary_contract_valid(decoded), info = case$id)
  }
  for (case in cases$invalid) {
    expect_false(.summary_contract_valid(case$row), info = case$id)
  }
  selected <- Filter(function(x) x$id %in% unlist(cases$mixed_rows), cases$valid)
  expect_identical(lapply(selected, function(x) .summary_contract_label(x$row)),
                   lapply(selected, `[[`, "label"))
  # Registry applicability is a semantic check beyond the row schema.
  sd <- Filter(function(x) x$id == "sd", cases$valid)[[1L]]$row
  expect_false(.summary_contract_valid(sd, "median"))
})

test_that("boundary aliases and unknown kinds preserve meaning", {
  skip_if_not_installed("jsonvalidate")
  for (case in .summary_contract_json("cases.json")$imports) {
    if (isTRUE(case$error)) {
      expect_error(.summary_contract_import(case$input, case$context),
                   "Conflicting|Invalid", info = case$id)
    } else {
      actual <- .summary_contract_import(case$input, case$context)
      expect_equal(actual[sort(names(actual))],
                   case$expected[sort(names(case$expected))], info = case$id)
    }
  }
})

test_that("standalone descriptor and CSV example agree", {
  skip_if_not_installed("jsonvalidate")
  descriptor <- .summary_contract_json("descriptor.json")
  expect_true(.summary_contract_schema(descriptor, "summary.schema.json"))
  tab <- descriptor$tables$effects
  expect_true(.summary_contract_schema(tab$plot, "plot.schema.json"))
  frame <- utils::read.csv(.summary_contract_path(tab$table$path),
                           stringsAsFactors = FALSE, check.names = FALSE)
  expect_true(all(c("estimate", "lower", "upper", "interval_kind", tab$plot$x) %in% names(frame)))
  expect_true(all(frame[[tab$plot$x]] %in% unlist(tab$plot$order[[tab$plot$x]])))
  for (i in seq_len(nrow(frame))) expect_true(.summary_contract_valid(as.list(frame[i, ])))
  out <- tempfile(fileext = ".csv")
  on.exit(unlink(out))
  utils::write.csv(frame, out, row.names = FALSE, na = "")
  expect_equal(utils::read.csv(out, stringsAsFactors = FALSE), frame)
  invalid <- descriptor
  invalid$tables$effects$table$path <- "../outside.csv"
  expect_false(.summary_contract_schema(invalid, "summary.schema.json"))
  invalid <- descriptor
  invalid$tables$effects$statistic <- "custom"
  expect_false(.summary_contract_schema(invalid, "summary.schema.json"))
})

test_that("CSV round trips retain precision, unavailable bounds, and identifiers", {
  skip_if_not_installed("jsonvalidate")
  rows <- .summary_contract_read_csv(.summary_contract_path("roundtrip.csv"))
  expected <- lapply(.summary_contract_json("cases.json")$valid, `[[`, "row")
  # CSV has one header for all rows; omitted optional cells become explicit nulls.
  columns <- names(rows[[1L]])
  expected <- lapply(expected, function(row) {
    out <- setNames(vector("list", length(columns)), columns)
    for (name in names(row)) out[name] <- row[name]
    out
  })
  expect_equal(rows, expected, tolerance = 0)
  out <- tempfile(fileext = ".csv")
  on.exit(unlink(out))
  .summary_contract_write_csv(rows, out)
  expect_equal(.summary_contract_read_csv(out), rows, tolerance = 0)
  writeLines(c("estimate,lower,upper,interval_kind", "bogus,0,1,sd"), out)
  expect_error(.summary_contract_read_csv(out), "Invalid numeric")
  writeLines(c("estimate,estimate,lower,upper,interval_kind", "1,1,0,2,sd"), out)
  expect_error(.summary_contract_read_csv(out), "Duplicate")
})
