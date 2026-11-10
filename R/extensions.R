# Carrying manifest extensions through derived datasets.

# Make x-masked-volume index maps absolute so they stay resolvable when the
# derived dataset has a different (or no) root, as for resource locators.
.nf_rebase_extensions <- function(ext, root) {
  if (!is.null(ext[["x-backing"]])) ext[["x-backing"]] <- .nf_backing_rebase(ext[["x-backing"]], root)
  mv <- ext[["x-masked-volume"]]
  if (is.null(mv) || is.null(root) || !is.list(mv$features)) return(ext)
  for (name in names(mv$features)) {
    path <- mv$features[[name]]$index_map$path
    if (is.character(path) && length(path) == 1L) {
      mv$features[[name]]$index_map$path <-
        normalizePath(.resolve_axis_labels_path(root, path), winslash = "/", mustWork = FALSE)
    }
  }
  ext[["x-masked-volume"]] <- mv
  ext
}

# Two masked-volume declarations agree when all fields match and their index
# maps have identical content, wherever those files live.
.nf_masked_volume_equal <- function(a, b) {
  if (is.null(a) || is.null(b)) return(is.null(a) && is.null(b))
  strip <- function(s) { s$index_map$path <- NULL; s }
  if (!identical(strip(a), strip(b))) return(FALSE)
  pa <- a$index_map$path
  pb <- b$index_map$path
  if (identical(pa, pb)) return(TRUE)
  if (!file.exists(pa) || !file.exists(pb)) return(FALSE)
  identical(digest::digest(file = pa, algo = "sha256"), digest::digest(file = pb, algo = "sha256"))
}

.nf_masked_volume_mismatches <- function(a, b) {
  ea <- .nf_rebase_extensions(a$manifest$extensions, a$.root)[["x-masked-volume"]]$features
  eb <- .nf_rebase_extensions(b$manifest$extensions, b$.root)[["x-masked-volume"]]$features
  features <- union(names(ea), names(eb))
  features[!vapply(features, function(f) .nf_masked_volume_equal(ea[[f]], eb[[f]]), logical(1))]
}

# Extensions for a concatenation: x-summary is dropped with a warning,
# x-masked-volume must already agree (checked by nf_compatible), and other
# extensions are kept when identical across inputs, otherwise dropped with a
# warning.
.nf_concat_extensions <- function(datasets) {
  exts <- lapply(datasets, function(d) .nf_rebase_extensions(d$manifest$extensions, d$.root))
  if (any(vapply(exts, function(e) !is.null(e[["x-summary"]]), logical(1)))) {
    warning("nf_concat dropped x-summary because its stored summaries may be stale", call. = FALSE)
  }
  keys <- setdiff(unique(unlist(lapply(exts, names))), "x-summary")
  out <- list()
  dropped <- character()
  for (key in keys) {
    values <- lapply(exts, function(e) e[[key]])
    if (all(vapply(values, identical, logical(1), values[[1L]]))) {
      out[[key]] <- values[[1L]]
    } else if (identical(key, "x-masked-volume")) {
      out[[key]] <- values[[1L]]  # content-equal; nf_compatible rejected the rest
    } else {
      dropped <- c(dropped, key)
    }
  }
  if (length(dropped)) {
    warning("nf_concat dropped extensions that differ between inputs: ",
            paste(dropped, collapse = ", "), call. = FALSE)
  }
  if (length(out)) out else NULL
}

# Extensions for a dataset derived from one feature (e.g. grouped summaries):
# keep other extensions, and keep the feature's masked-volume mapping only if
# its vector length is unchanged.
.nf_derived_extensions <- function(ds, feature, new_feature) {
  manifest <- .nf_drop_backing(.nf_drop_summary(ds$manifest, "nf_summarize"), "nf_summarize")
  ext <- .nf_rebase_extensions(manifest$extensions, ds$.root)
  mv <- ext[["x-masked-volume"]]
  if (!is.null(mv)) {
    entry <- mv$features[[feature]]
    keep <- !is.null(entry) &&
      identical(new_feature$logical$kind, "vector") &&
      identical(as.integer(new_feature$logical$shape),
                as.integer(ds$manifest$features[[feature]]$logical$shape))
    mv$features <- if (keep) stats::setNames(list(entry), feature) else NULL
    ext[["x-masked-volume"]] <- if (keep) mv else NULL
  }
  if (length(ext)) ext else NULL
}
