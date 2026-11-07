# Small reference adapter for the draft artifacts, not a public neurotabs API.
.summary_contract_path <- function(name) {
  system.file("schema", "summary", name, package = "neurotabs", mustWork = TRUE)
}
.summary_contract_json <- function(name) {
  jsonlite::fromJSON(.summary_contract_path(name), simplifyVector = FALSE)
}
.summary_contract_schema <- function(value, schema) {
  jsonvalidate::json_validate(
    jsonlite::toJSON(value, auto_unbox = TRUE, null = "null", digits = I(17)),
    .summary_contract_path(schema), engine = "ajv"
  )
}
.summary_contract_valid <- function(row, statistic = "mean") {
  if (!isTRUE(.summary_contract_schema(row, "summary-row.schema.json"))) return(FALSE)
  nums <- Filter(is.numeric, row)
  if (any(!is.finite(unlist(nums)))) return(FALSE)
  if (!is.null(row$lower) && row$lower > row$upper) return(FALSE)
  defs <- .summary_contract_json("interval-kinds.json")$kinds
  def <- Filter(function(x) identical(x$id, row$interval_kind), defs)[[1L]]
  statistic %in% unlist(def$statistics)
}
.summary_contract_label <- function(row) {
  defs <- .summary_contract_json("interval-kinds.json")$kinds
  def <- Filter(function(x) identical(x$id, row$interval_kind), defs)[[1L]]
  if (row$interval_kind == "custom") return(row$interval_definition)
  label <- def$label
  if (!is.null(row$interval_level)) {
    label <- sub("{percent}", format(100 * row$interval_level, trim = TRUE,
                                    scientific = FALSE, digits = 15), label, fixed = TRUE)
  }
  label
}
.summary_contract_import <- function(row, context = NULL) {
  aliases <- c(value = "estimate", conf_level = "interval_level",
               conf.low = "lower", conf.high = "upper", lwr = "lower", upr = "upper")
  for (old in names(aliases)) {
    new <- aliases[[old]]
    if (old %in% names(row)) {
      if (new %in% names(row) && !identical(row[[new]], row[[old]])) stop("Conflicting aliases")
      row[new] <- row[old]
      row[old] <- NULL
    }
  }
  kind <- row$interval_kind
  legacy <- c(ci95_t = "ci_t", wsci95_cm = "wsci_cm")
  if (identical(context, "brainflow-population-v1")) legacy <- c(legacy, ci95 = "ci_t")
  if (identical(context, "brainflow-trace-v1")) legacy <- c(legacy, ci95 = "quantile_range")
  if (!is.null(kind) && kind %in% names(legacy)) {
    if (!is.null(row$interval_level) && row$interval_level != 0.95) stop("Conflicting levels")
    row$interval_kind <- legacy[[kind]]
    row$interval_level <- 0.95
  } else {
    ids <- vapply(.summary_contract_json("interval-kinds.json")$kinds, `[[`, "", "id")
    if (is.null(kind) || !kind %in% ids) {
      row$interval_kind <- "custom"
      if (!is.null(kind)) row$original_kind <- kind
      if (is.null(row$interval_definition)) {
        row$interval_definition <- if (is.null(kind)) "Definition not supplied" else
          paste0("Unknown interval kind: ", kind)
      }
      row$interval_level <- NULL
    }
  }
  if (!.summary_contract_valid(row)) stop("Invalid summary metadata")
  row
}

# Read text first so grouping identifiers (including "001" and "NA") survive.
.summary_contract_read_csv <- function(path) {
  frame <- utils::read.csv(path, colClasses = "character", na.strings = "",
                           check.names = FALSE)
  if (anyDuplicated(names(frame))) stop("Duplicate summary columns")
  schema <- .summary_contract_json("summary-row.schema.json")
  numeric_cols <- names(Filter(function(x) any(unlist(x$type) %in% c("number", "integer")),
                               schema$properties))
  lapply(seq_len(nrow(frame)), function(i) {
    row <- lapply(frame[i, , drop = FALSE], function(x) if (is.na(x)) NULL else x)
    for (name in intersect(names(row), numeric_cols)) {
      if (is.null(row[[name]])) next
      value <- suppressWarnings(as.numeric(row[[name]]))
      if (!is.finite(value)) stop("Invalid numeric summary cell")
      row[[name]] <- value
    }
    if (!.summary_contract_valid(row)) stop("Invalid summary metadata")
    row
  })
}
.summary_contract_write_csv <- function(rows, path) {
  columns <- unique(unlist(lapply(rows, names)))
  cells <- lapply(columns, function(name) vapply(rows, function(row) {
    value <- row[[name]]
    if (is.null(value)) return(NA_character_)
    if (is.numeric(value)) return(sprintf("%.17g", value))
    as.character(value)
  }, ""))
  names(cells) <- columns
  utils::write.csv(as.data.frame(cells, stringsAsFactors = FALSE), path,
                   row.names = FALSE, na = "")
}
