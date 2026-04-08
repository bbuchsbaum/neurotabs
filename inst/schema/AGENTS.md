<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-07 | Updated: 2026-04-07 -->

# inst/schema/

## Purpose
Bundled JSON Schema for runtime manifest validation. Loaded by `nf_read()` when `validate_schema = TRUE` to verify that a manifest file conforms to the NFTab manifest schema before parsing.

## Key Files

| File | Description |
|------|-------------|
| `nftab-manifest.schema.json` | JSON Schema (draft-07) for NFTab manifest files; used by `jsonvalidate` via AJV engine |

## For AI Agents

### Working In This Directory
- This file must stay in sync with `spec/nftab-manifest.schema.json`. When the spec schema changes, copy or regenerate the file here.
- The schema is loaded at runtime via: `system.file("schema", "nftab-manifest.schema.json", package = "neurotabs")`
- Validation uses the `jsonvalidate` package with the `ajv` engine. Errors are surfaced with instance path and message.

### Testing Requirements
```r
# Schema validation is exercised by io tests with validate_schema = TRUE
Rscript -e 'devtools::test(filter = "io")'
```

### Common Patterns
- Certain fields require JSON arrays even when they contain a single element (e.g., `observation_axes`, `axes`, `columns`). The `I()` wrapper in `io.R` handles this during JSON serialization for validation.

## Dependencies

### Internal
- `R/io.R` — `.validate_manifest_schema()` loads and applies this schema
- `spec/nftab-manifest.schema.json` — authoritative source; keep in sync

### External
- `jsonvalidate` (Suggests) — required at runtime for schema validation

<!-- MANUAL: -->
