<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-07 | Updated: 2026-04-07 -->

# inst/

## Purpose
Package installation data — files shipped with the package and accessible at runtime via `system.file()`. Contains working example NFTab datasets and the bundled JSON Schema for manifest validation.

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `examples/` | Complete, runnable NFTab example datasets (see `examples/AGENTS.md`) |
| `schema/` | Bundled JSON Schema for manifest validation (see `schema/AGENTS.md`) |

## For AI Agents

### Working In This Directory
- Files here are part of the package's public contract surface. Changes must be backward-compatible and schema-valid.
- The JSON Schema in `schema/` is loaded at runtime by `nf_read()` (when `validate_schema = TRUE`). Keep it in sync with `spec/nftab-manifest.schema.json`.
- The examples in `examples/` are verified in tests — they must remain schema-valid and fully resolvable.

### Testing Requirements
```r
# Verify examples are still valid after changes
Rscript -e 'devtools::test(filter = "io")'
Rscript -e 'devtools::test(filter = "conformance")'
```

### Common Patterns
- Access at runtime: `system.file("schema", "nftab-manifest.schema.json", package = "neurotabs")`
- Access examples: `system.file("examples", "faces-demo", package = "neurotabs")`

## Dependencies

### Internal
- `R/io.R` — loads the bundled schema via `system.file()`
- `R/validation.R` — uses the schema for manifest validation

<!-- MANUAL: -->
