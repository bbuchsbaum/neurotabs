<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-07 | Updated: 2026-04-07 -->

# inst/examples/

## Purpose
Complete, runnable NFTab example datasets shipped with the package. These serve as both user-facing demonstrations and contract-level test fixtures. Each subdirectory is a self-contained `table-package` profile dataset.

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `faces-demo/` | Multi-subject faces paradigm dataset with NIfTI stat maps + ROI vectors; demonstrates `ref` and `columns` encodings with a resource registry |
| `roi-only/` | Minimal dataset with only inline ROI vectors via `columns` encoding; no external resources needed |

### faces-demo/ contents
| File | Description |
|------|-------------|
| `nftab.yaml` | Manifest with `ref` (nifti backend) and `columns` encodings |
| `observations.csv` | Observation table: subjects × conditions with locator and ROI columns |
| `resources.csv` | Resource registry mapping `resource_id` to NIfTI file locators |
| `roi_labels.tsv` | Axis domain label table for the ROI feature axis |

### roi-only/ contents
| File | Description |
|------|-------------|
| `nftab.yaml` | Manifest with `columns` encoding only |
| `observations.csv` | Observation table with inline ROI scalar columns |

## For AI Agents

### Working In This Directory
- These examples are part of the package's **contract surface** — they must stay schema-valid and fully resolvable at all times.
- After any change to the NFTab spec, manifest schema, or encoding behavior, verify these examples still pass:
  ```r
  ds <- nf_read(system.file("examples", "faces-demo", "nftab.yaml", package = "neurotabs"))
  nf_validate(ds, level = "structural")
  ```
- The `faces-demo` example exercises the most complete feature set (resource registry, both encoding types, axis domain labels). Use it as the primary integration smoke-test.
- The `roi-only` example is the minimal baseline — if this breaks, something fundamental is wrong.

### Testing Requirements
```r
Rscript -e 'devtools::test(filter = "io")'
```

### Common Patterns
- Both datasets use `table-package` storage profile (YAML + CSV).
- Relative locators in `observations.csv` and `resources.csv` are resolved relative to the manifest directory.
- Selector syntax for 4D NIfTI volumes: `{"index": {"t": 0}}` (0-based, JSON string in CSV cell).

## Dependencies

### Internal
- `inst/schema/nftab-manifest.schema.json` — validated on `nf_read()`
- `R/io.R` — reads these datasets
- `R/backend-nifti.R` — resolves NIfTI features in `faces-demo`

### External
- `neuroim2` or `RNifti` — required to resolve NIfTI `ref` features in `faces-demo`

<!-- MANUAL: -->
