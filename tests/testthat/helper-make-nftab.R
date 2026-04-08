# Shared test helper: build a minimal ROI-only nftab
.make_roi_nftab <- function() {
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE, semantic_role = "row_id"),
    subject = nf_col_schema("string", nullable = FALSE, semantic_role = "subject"),
    condition = nf_col_schema("string", nullable = FALSE, semantic_role = "condition"),
    group = nf_col_schema("string", nullable = FALSE, semantic_role = "group"),
    roi_1 = nf_col_schema("float32"),
    roi_2 = nf_col_schema("float32"),
    roi_3 = nf_col_schema("float32")
  )

  feat <- nf_feature(
    logical = nf_logical_schema("vector", "roi", "float32", shape = 3L),
    encodings = list(nf_columns_encoding(c("roi_1", "roi_2", "roi_3")))
  )

  m <- nf_manifest(
    dataset_id = "test-roi",
    row_id = "row_id",
    observation_axes = c("subject", "condition"),
    observation_columns = obs_cols,
    features = list(roi_beta = feat)
  )

  obs <- data.frame(
    row_id = c("r1", "r2", "r3", "r4"),
    subject = c("s01", "s01", "s02", "s02"),
    condition = c("faces", "houses", "faces", "houses"),
    group = c("ctrl", "ctrl", "pt", "pt"),
    roi_1 = c(0.3, 0.1, 0.4, 0.2),
    roi_2 = c(0.4, 0.2, 0.5, 0.3),
    roi_3 = c(0.3, 0.1, 0.4, 0.1),
    stringsAsFactors = FALSE
  )

  nftab(manifest = m, observations = obs)
}

.make_alt_roi_nftab <- function() {
  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE, semantic_role = "row_id"),
    subject = nf_col_schema("string", nullable = FALSE, semantic_role = "subject"),
    condition = nf_col_schema("string", nullable = FALSE, semantic_role = "condition"),
    group = nf_col_schema("string", nullable = FALSE, semantic_role = "group"),
    alt_1 = nf_col_schema("float32"),
    alt_2 = nf_col_schema("float32"),
    alt_3 = nf_col_schema("float32")
  )

  feat <- nf_feature(
    logical = nf_logical_schema("vector", "roi", "float32", shape = 3L),
    encodings = list(nf_columns_encoding(c("alt_1", "alt_2", "alt_3")))
  )

  m <- nf_manifest(
    dataset_id = "test-roi-alt",
    row_id = "row_id",
    observation_axes = c("subject", "condition"),
    observation_columns = obs_cols,
    features = list(roi_beta = feat)
  )

  obs <- data.frame(
    row_id = c("r5", "r6"),
    subject = c("s03", "s03"),
    condition = c("faces", "houses"),
    group = c("ctrl", "ctrl"),
    alt_1 = c(0.9, 0.7),
    alt_2 = c(0.8, 0.6),
    alt_3 = c(0.7, 0.5),
    stringsAsFactors = FALSE
  )

  nftab(manifest = m, observations = obs)
}

.make_labeled_roi_nftab <- function(label_rows = 3L) {
  tmpdir <- tempfile("neurotabs-labels-")
  dir.create(tmpdir)

  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE, semantic_role = "row_id"),
    subject = nf_col_schema("string", nullable = FALSE, semantic_role = "subject"),
    condition = nf_col_schema("string", nullable = FALSE, semantic_role = "condition"),
    group = nf_col_schema("string", nullable = FALSE, semantic_role = "group"),
    roi_1 = nf_col_schema("float32"),
    roi_2 = nf_col_schema("float32"),
    roi_3 = nf_col_schema("float32")
  )

  logical <- nf_logical_schema(
    "vector",
    "roi",
    "float32",
    shape = 3L,
    axis_domains = list(
      roi = nf_axis_domain(
        id = "demo-atlas",
        labels = "roi_labels.tsv",
        description = "Demo atlas for ROI vectors"
      )
    )
  )

  feat <- nf_feature(
    logical = logical,
    encodings = list(nf_columns_encoding(c("roi_1", "roi_2", "roi_3")))
  )

  m <- nf_manifest(
    dataset_id = "test-roi-labeled",
    row_id = "row_id",
    observation_axes = c("subject", "condition"),
    observation_columns = obs_cols,
    features = list(roi_beta = feat)
  )

  obs <- data.frame(
    row_id = c("r1", "r2", "r3", "r4"),
    subject = c("s01", "s01", "s02", "s02"),
    condition = c("faces", "houses", "faces", "houses"),
    group = c("ctrl", "ctrl", "pt", "pt"),
    roi_1 = c(0.3, 0.1, 0.4, 0.2),
    roi_2 = c(0.4, 0.2, 0.5, 0.3),
    roi_3 = c(0.3, 0.1, 0.4, 0.1),
    stringsAsFactors = FALSE
  )

  labels <- data.frame(
    index = seq_len(label_rows),
    label = paste0("roi_", seq_len(label_rows)),
    stringsAsFactors = FALSE
  )
  data.table::fwrite(labels, file.path(tmpdir, "roi_labels.tsv"), sep = "\t")

  nftab(manifest = m, observations = obs, .root = tmpdir)
}

.make_masked_volume_nftab <- function(index_rows = 3L, bad_coords = FALSE) {
  tmpdir <- tempfile("neurotabs-masked-volume-")
  dir.create(tmpdir)

  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE, semantic_role = "row_id"),
    subject = nf_col_schema("string", nullable = FALSE, semantic_role = "subject"),
    condition = nf_col_schema("string", nullable = FALSE, semantic_role = "condition"),
    value_1 = nf_col_schema("float32"),
    value_2 = nf_col_schema("float32"),
    value_3 = nf_col_schema("float32")
  )

  feat <- nf_feature(
    logical = nf_logical_schema("vector", "voxel", "float32", shape = 3L),
    encodings = list(nf_columns_encoding(c("value_1", "value_2", "value_3")))
  )

  m <- nf_manifest(
    dataset_id = "test-masked-volume",
    row_id = "row_id",
    observation_axes = c("subject", "condition"),
    observation_columns = obs_cols,
    features = list(statvec = feat),
    extensions = list(
      "x-masked-volume" = list(
        features = list(
          statvec = list(
            grid_axes = c("x", "y", "z"),
            grid_shape = c(2L, 2L, 2L),
            index_map = list(
              path = "voxel_index.tsv",
              format = "tsv"
            )
          )
        )
      )
    )
  )

  obs <- data.frame(
    row_id = c("r1", "r2"),
    subject = c("s01", "s02"),
    condition = c("faces", "houses"),
    value_1 = c(0.1, 0.4),
    value_2 = c(0.2, 0.5),
    value_3 = c(0.3, 0.6),
    stringsAsFactors = FALSE
  )

  coords <- data.frame(
    index = seq_len(index_rows),
    x = c(0L, 0L, if (bad_coords) 2L else 1L)[seq_len(index_rows)],
    y = c(0L, 1L, 1L)[seq_len(index_rows)],
    z = c(0L, 0L, 1L)[seq_len(index_rows)],
    stringsAsFactors = FALSE
  )
  data.table::fwrite(coords, file.path(tmpdir, "voxel_index.tsv"), sep = "\t")

  nftab(manifest = m, observations = obs, .root = tmpdir)
}

.make_ref_nftab <- function(dataset_id = "test-ref",
                            resource_ids = c("res1", "res2"),
                            locators = c("maps/a.nii.gz", "maps/b.nii.gz"),
                            backend = "x-unknown") {
  stopifnot(length(resource_ids) == length(locators))

  obs_cols <- list(
    row_id = nf_col_schema("string", nullable = FALSE, semantic_role = "row_id"),
    subject = nf_col_schema("string", nullable = FALSE, semantic_role = "subject"),
    condition = nf_col_schema("string", nullable = FALSE, semantic_role = "condition"),
    map_res = nf_col_schema("string", nullable = FALSE),
    map_sel = nf_col_schema("json", nullable = TRUE)
  )

  feat <- nf_feature(
    logical = nf_logical_schema(
      "volume",
      c("x", "y", "z"),
      "float32",
      shape = c(2L, 2L, 2L),
      support_ref = "test_grid"
    ),
    encodings = list(
      nf_ref_encoding(
        resource_id = nf_col("map_res"),
        selector = nf_col("map_sel")
      )
    )
  )

  m <- nf_manifest(
    dataset_id = dataset_id,
    row_id = "row_id",
    observation_axes = c("subject", "condition"),
    observation_columns = obs_cols,
    features = list(statmap = feat),
    supports = list(
      test_grid = nf_support_volume(
        support_id = "test-grid-2x2x2",
        space = "MNI152NLin2009cAsym",
        grid_id = "test-grid-2x2x2"
      )
    ),
    resources_path = "resources.csv",
    resources_format = "csv"
  )

  obs <- data.frame(
    row_id = paste0(dataset_id, c("-1", "-2")),
    subject = paste0("s", seq_along(resource_ids)),
    condition = c("faces", "houses")[seq_along(resource_ids)],
    map_res = resource_ids,
    map_sel = c("{\"index\":{\"t\":0}}", "{\"index\":{\"t\":1}}")[seq_along(resource_ids)],
    stringsAsFactors = FALSE
  )

  resources <- data.frame(
    resource_id = resource_ids,
    backend = rep(backend, length(resource_ids)),
    locator = locators,
    stringsAsFactors = FALSE
  )

  nftab(manifest = m, observations = obs, resources = resources, .root = tempdir())
}
