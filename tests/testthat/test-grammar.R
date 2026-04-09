test_that("nf_filter subsets by predicate", {
  ds <- .make_roi_nftab()
  filtered <- nf_filter(ds, group == "ctrl")
  expect_equal(nf_nobs(filtered), 2L)
  expect_true(all(filtered$observations$group == "ctrl"))
})

test_that("nf_arrange sorts rows", {
  ds <- .make_roi_nftab()
  sorted <- nf_arrange(ds, roi_1)
  vals <- sorted$observations$roi_1
  expect_equal(vals, sort(ds$observations$roi_1))
})

test_that("nf_collect returns matrix for 1D feature", {
  ds <- .make_roi_nftab()
  mat <- nf_collect(ds, "roi_beta")
  expect_true(is.matrix(mat))
  expect_equal(nrow(mat), 4L)
  expect_equal(ncol(mat), 3L)
  expect_equal(rownames(mat), c("r1", "r2", "r3", "r4"))
})

test_that("nf_collect returns list when simplify=FALSE", {
  ds <- .make_roi_nftab()
  res <- nf_collect(ds, "roi_beta", simplify = FALSE)
  expect_true(is.list(res))
  expect_length(res, 4L)
})

test_that("nf_collect accepts bare symbols and string variables", {
  ds <- .make_roi_nftab()
  feature_name <- "roi_beta"

  expect_equal(nf_collect(ds, roi_beta), nf_collect(ds, "roi_beta"))
  expect_equal(
    nf_collect(ds, feature_name, simplify = FALSE),
    nf_collect(ds, "roi_beta", simplify = FALSE)
  )
})

test_that("nf_select keeps manifest observation columns aligned", {
  ds <- .make_roi_nftab()
  selected <- nf_select(ds, group)
  expect_true(setequal(names(selected$manifest$observation_columns),
                       names(selected$observations)))
})

test_that("nf_group_by creates grouped_nftab and verbs preserve grouping", {
  ds <- .make_roi_nftab()
  grouped <- nf_group_by(ds, group, condition)

  expect_s3_class(grouped, "grouped_nftab")
  mutated <- nf_mutate(grouped, group_flag = group == "pt")
  expect_s3_class(mutated, "grouped_nftab")
  expect_true(all(c("group", "condition") %in% mutated$by))

  filtered <- nf_filter(grouped, condition == "faces")
  expect_s3_class(filtered, "grouped_nftab")
  expect_equal(unique(filtered$data$observations$condition), "faces")
})

test_that("nf_group_by: unquoted names still work (regression)", {
  ds <- .make_roi_nftab()
  g <- nf_group_by(ds, subject)
  expect_s3_class(g, "grouped_nftab")
  expect_equal(g$by, "subject")
})

test_that("nf_group_by: .by character vector gives same result as NSE", {
  ds <- .make_roi_nftab()
  col <- "subject"
  g_nse <- nf_group_by(ds, subject)
  g_by  <- nf_group_by(ds, .by = col)
  expect_equal(g_nse$by, g_by$by)
  expect_equal(g_nse$data$observations, g_by$data$observations)
})

test_that("nf_select: .cols character vector works", {
  ds <- .make_roi_nftab()
  col <- "group"
  sel_nse  <- nf_select(ds, group)
  sel_cols <- nf_select(ds, .cols = col)
  expect_equal(names(sel_nse$observations), names(sel_cols$observations))
})

test_that("nf_arrange: .by character vector works", {
  ds <- .make_roi_nftab()
  arr_nse <- nf_arrange(ds, roi_1)
  arr_by  <- nf_arrange(ds, .by = "roi_1")
  expect_equal(arr_nse$observations, arr_by$observations)
})

test_that("nf_filter works when called inside a helper function", {
  ds <- .make_roi_nftab()
  filter_helper <- function(data, grp) {
    nf_filter(data, group == grp)
  }
  result <- filter_helper(ds, "ctrl")
  expect_equal(nf_nobs(result), 2L)
  expect_true(all(result$observations$group == "ctrl"))
})

test_that("nf_group_by: error on unknown column name in .by", {
  ds <- .make_roi_nftab()
  expect_error(nf_group_by(ds, .by = "nonexistent_col"), "unknown grouping columns")
})

test_that("nf_drill returns contributing rows from source", {
  ds <- .make_roi_nftab()
  summary <- nf_group_by(ds, group) |> nf_summarize("roi_beta")
  drilled <- nf_drill(summary, ds)
  expect_s3_class(drilled, "nftab")
  expect_equal(nrow(drilled$observations), nrow(ds$observations))
})

test_that("nf_drill with row_index returns only that group's rows", {
  ds <- .make_roi_nftab()
  summary <- nf_group_by(ds, group) |> nf_summarize("roi_beta")
  drilled <- nf_drill(summary, ds, row_index = 1L)
  expect_s3_class(drilled, "nftab")
  expect_true(nrow(drilled$observations) < nrow(ds$observations))
  expect_equal(nrow(drilled$observations), 2L)  # 2 rows per group in test data
})

test_that("nf_drill errors when .members column is absent", {
  ds <- .make_roi_nftab()
  expect_error(nf_drill(ds, ds), ".members")
})

test_that("nf_ungroup returns underlying nftab", {
  ds <- .make_roi_nftab()
  grouped <- nf_group_by(ds, group)
  ungrouped <- nf_ungroup(grouped)
  expect_s3_class(ungrouped, "nftab")
  expect_false(inherits(ungrouped, "grouped_nftab"))
})

test_that("nf_ungroup errors on non-grouped input", {
  ds <- .make_roi_nftab()
  expect_error(nf_ungroup(ds), "grouped_nftab")
})

test_that("print.grouped_nftab produces output", {
  ds <- .make_roi_nftab()
  grouped <- nf_group_by(ds, group)
  expect_output(print(grouped), "grouped_nftab")
})

test_that("nf_arrange descending with minus prefix", {
  ds <- .make_roi_nftab()
  sorted <- nf_arrange(ds, .by = "-roi_1")
  vals <- sorted$observations$roi_1
  expect_equal(vals, sort(ds$observations$roi_1, decreasing = TRUE))
})

test_that("nf_select on grouped_nftab preserves grouping", {
  ds <- .make_roi_nftab()
  grouped <- nf_group_by(ds, group)
  selected <- nf_select(grouped, subject)
  expect_s3_class(selected, "grouped_nftab")
  expect_true("group" %in% names(selected$data$observations))
})

test_that("nf_arrange on grouped_nftab preserves grouping", {
  ds <- .make_roi_nftab()
  grouped <- nf_group_by(ds, group)
  sorted <- nf_arrange(grouped, roi_1)
  expect_s3_class(sorted, "grouped_nftab")
})

test_that("nf_filter on grouped_nftab preserves grouping", {
  ds <- .make_roi_nftab()
  grouped <- nf_group_by(ds, group)
  filtered <- nf_filter(grouped, subject == "s01")
  expect_s3_class(filtered, "grouped_nftab")
})

test_that("nf_group_by errors with no columns", {
  ds <- .make_roi_nftab()
  expect_error(nf_group_by(ds, .by = character(0)), "at least one")
})

test_that("nf_matched_cohort filters by exact column values", {
  ds <- .make_roi_nftab()
  cohort <- nf_matched_cohort(ds, list(group = "ctrl"))
  expect_equal(nf_nobs(cohort), 2L)
  expect_true(all(cohort$observations$group == "ctrl"))
})

test_that("nf_collect with .progress does not error", {
  ds <- .make_roi_nftab()
  expect_no_error(
    suppressMessages(nf_collect(ds, "roi_beta", .progress = TRUE))
  )
})
