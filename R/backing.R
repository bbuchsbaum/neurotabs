# x-backing 0.1.0 (draft, spec/extensions/x-backing.md): the dataset and
# feature a result was computed from.
#
# In memory the link's `source` is an absolute manifest path, like a rebased
# x-masked-volume index map; nf_write() rewrites it relative to the written
# manifest, as the extension requires.

.nf_backing_version <- "0.1.0"

.nf_is_absolute_path <- function(path) grepl("^(/|[a-zA-Z]:)", path)

# The manifest file of a dataset read from (or written to) disk, or NULL.
.nf_manifest_file <- function(root) {
  if (is.null(root)) return(NULL)
  for (name in c("nftab.yaml", "nftab.yml", "nftab.json")) {
    path <- file.path(root, name)
    if (file.exists(path)) return(normalizePath(path, winslash = "/"))
  }
  NULL
}

# The link nf_analyze() attaches to its result, or NULL when the source
# dataset has no manifest on disk to point at.
.nf_backing_link <- function(source_ds, feature, formula) {
  manifest <- .nf_manifest_file(source_ds$.root)
  if (is.null(manifest)) return(NULL)
  list(
    version = .nf_backing_version,
    source = manifest,
    feature = feature,
    formula = paste(deparse(formula, width.cutoff = 500L), collapse = " "),
    source_checksum = paste0("sha256:", digest::digest(file = manifest, algo = "sha256",
                                                       serialize = FALSE))
  )
}

.nf_backing_links <- function(ext) {
  if (is.null(ext)) return(list())
  if (is.list(ext$features)) ext$features else list(ext)
}

.nf_backing_set_links <- function(ext, links) {
  if (is.list(ext$features)) {
    ext$features <- links
    ext
  } else {
    links[[1L]]
  }
}

# Make link sources absolute so they survive a change of root.
.nf_backing_rebase <- function(ext, root) {
  if (is.null(ext) || is.null(root)) return(ext)
  links <- lapply(.nf_backing_links(ext), function(link) {
    if (is.character(link$source) && length(link$source) == 1L && !.nf_is_absolute_path(link$source)) {
      link$source <- normalizePath(file.path(root, link$source), winslash = "/", mustWork = FALSE)
    }
    link
  })
  .nf_backing_set_links(ext, links)
}

# `to` as a path relative to directory `from` ("../betas/nftab.json"), or NULL
# when no relative path exists (different drives).
.nf_relative_path <- function(from, to) {
  split <- function(p) {
    parts <- strsplit(normalizePath(p, winslash = "/", mustWork = FALSE), "/", fixed = TRUE)[[1L]]
    parts[nzchar(parts) | seq_along(parts) == 1L]
  }
  a <- split(from)
  b <- split(to)
  if (!identical(a[[1L]], b[[1L]])) return(NULL)
  n <- 0L
  while (n < min(length(a), length(b)) && identical(a[[n + 1L]], b[[n + 1L]])) n <- n + 1L
  paste(c(rep("..", length(a) - n), b[seq_len(length(b) - n) + n]), collapse = "/")
}

# The extension as nf_write() stores it in a manifest under `path`: sources
# relative to that manifest. A link whose source is gone, or cannot be reached
# by a relative path, is dropped with a warning.
.nf_backing_for_write <- function(ext, root, path) {
  if (is.null(ext)) return(NULL)
  ext <- .nf_backing_rebase(ext, root %||% path)
  links <- .nf_backing_links(ext)
  keep <- rep(TRUE, length(links))
  for (i in seq_along(links)) {
    source <- links[[i]]$source
    rel <- if (is.character(source) && length(source) == 1L && file.exists(source)) {
      .nf_relative_path(path, source)
    }
    if (is.null(rel)) keep[[i]] <- FALSE else links[[i]]$source <- rel
  }
  if (!all(keep)) {
    warning("nf_write dropped x-backing: its source dataset was not found or cannot be linked by a relative path",
            call. = FALSE)
  }
  links <- links[keep]
  if (!length(links)) return(NULL)
  .nf_backing_set_links(ext, links)
}

# Operations that change the linked features' values (or derive new features
# from them) drop the link: the result is no longer what the source produced.
# Subsetting rows or editing design columns leaves the maps as computed.
.nf_drop_backing <- function(manifest, operation) {
  if (!is.null(manifest$extensions[["x-backing"]])) {
    manifest$extensions[["x-backing"]] <- NULL
    if (!length(manifest$extensions)) manifest["extensions"] <- list(NULL)
    warning(operation, " dropped x-backing because the result no longer matches its source",
            call. = FALSE)
  }
  manifest
}

.validate_backing_extension <- function(ext) {
  errors <- character()
  err <- function(...) errors <<- c(errors, paste0("extension 'x-backing': ", ...))
  if (!is.list(ext)) return("extension 'x-backing': must be an object")
  if (!identical(ext$version, .nf_backing_version)) {
    err("version must be \"", .nf_backing_version, "\"")
  }
  per_feature <- !is.null(ext$features)
  if (per_feature && (!is.null(ext$source) || !is.null(ext$feature))) {
    err("use dataset-level fields or 'features', not both")
  }
  if (per_feature && (!is.list(ext$features) || !length(ext$features) || is.null(names(ext$features)))) {
    err("'features' must map feature names to links")
    return(errors)
  }
  links <- .nf_backing_links(ext)
  for (i in seq_along(links)) {
    link <- links[[i]]
    where <- if (per_feature) paste0("feature '", names(links)[[i]], "': ") else ""
    for (field in c("source", "feature")) {
      value <- link[[field]]
      if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) {
        err(where, "'", field, "' must be a non-empty string")
      }
    }
    if (is.character(link$source) && length(link$source) == 1L &&
        grepl("^[a-zA-Z][a-zA-Z0-9+.-]*://|\\\\", link$source)) {
      err(where, "'source' must be a file path, not a URL, and use forward slashes")
    }
    sum <- link$source_checksum
    if (!is.null(sum) && !(is.character(sum) && length(sum) == 1L && grepl("^sha256:[0-9a-f]{64}$", sum))) {
      err(where, "'source_checksum' must be 'sha256:<64 hex digits>'")
    }
  }
  errors
}
