<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-07 | Updated: 2026-04-07 -->

# tests/fixtures/

## Purpose
Minimal NFTab datasets used by conformance tests. Each subdirectory is a self-contained NFTab dataset (valid or intentionally invalid) that exercises a specific conformance rule. The `test-conformance-fixtures.R` test file iterates over all fixture directories automatically.

## Key Files

| Directory | Type | What it tests |
|-----------|------|---------------|
| `valid-roi/` | Valid | A minimal valid NFTab with ROI vector features; used for positive conformance checks |
| `invalid-bad-json/` | Invalid | Manifest or observation table with malformed JSON content |
| `invalid-extra-column/` | Invalid | Observation table has a column not declared in `observation_columns` |
| `invalid-full-unsupported-backend/` | Invalid | Feature uses a `ref` encoding with a backend that has no registered adapter |
| `invalid-nonnullable-na/` | Invalid | Non-nullable column contains NA values |
| `invalid-schema-unknown-key/` | Invalid | Manifest contains an unknown key that fails JSON Schema validation |

Each fixture directory typically contains:
- `nftab.yaml` — the manifest
- `observations.csv` — the observation table
- `resources.csv` — optional resource registry

## For AI Agents

### Working In This Directory
- Fixture directories are discovered automatically by `helper-fixtures.R` — adding a new directory makes it testable with no other changes.
- **Valid fixtures** must pass `nf_validate(level = "structural")` and `nf_read()` without errors.
- **Invalid fixtures** must cause `nf_validate()` or `nf_read()` to emit a specific error; document the expected error in the fixture's `nftab.yaml` as a comment.
- Keep fixtures minimal — the smallest dataset that exercises the constraint being tested.
- Fixtures are part of the contract surface. Do not change them without updating the test that references them.

### Testing Requirements
```r
Rscript -e 'devtools::test(filter = "conformance-fixtures")'
```

### Common Patterns
- Each fixture is a `table-package` profile dataset (YAML manifest + CSV observation table).
- Invalid fixtures should trigger errors at `nf_read()` or `nf_validate()` time, not silently.
- The `valid-roi/` fixture is also used as a baseline in other tests to confirm round-trip fidelity.

## Dependencies

### Internal
- `tests/testthat/helper-fixtures.R` — loads these directories
- `tests/testthat/test-conformance-fixtures.R` — iterates them

### External
- None (plain YAML + CSV files)

<!-- MANUAL: -->
