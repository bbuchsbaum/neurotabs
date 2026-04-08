<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-07 | Updated: 2026-04-07 -->

# spec/

## Purpose
Normative NFTab specification documents. These define the cross-language contract that all implementations (R, Python, Rust, etc.) must satisfy. The R package is a reference implementation of this spec, not its canonical source — if code and spec diverge, fix the code.

## Key Files

| File | Description |
|------|-------------|
| `nftab-spec.md` | Authoritative prose specification with normative language (MUST/SHOULD/MAY); covers abstract data model, manifest, observation table, scalar column schema, feature schema, encodings, concatenation, resolution algorithm, and conformance levels |
| `nftab-manifest.schema.json` | JSON Schema (draft-07) for manifest validation; machine-readable companion to the prose spec; copied to `inst/schema/` for runtime use |

## For AI Agents

### Working In This Directory
- The spec is the ground truth. Code changes that affect public behavior should be accompanied by spec updates (or a deliberate spec amendment).
- `nftab-manifest.schema.json` here is the **authoritative** copy. After updating it, also update `inst/schema/nftab-manifest.schema.json` (the runtime copy).
- Use normative language consistently: **MUST** (required), **SHOULD** (recommended), **MAY** (optional), **MUST NOT** / **SHOULD NOT**.
- Version the spec with semantic versioning. Breaking changes to the abstract data model require a major version bump.

### Key Spec Sections
| Section | Topic |
|---------|-------|
| S1 | Abstract data model: Dataset = Manifest + ObservationTable + Optional(ResourceRegistry) |
| S2 | Manifest fields: spec_version, dataset_id, storage_profile, row_id, observation_axes, features |
| S3 | Observation table: row_id uniqueness, axes tuple uniqueness |
| S4 | Scalar column schema: dtypes, nullable, semantic_role, levels |
| S5 | Feature schema: logical schema (kind, axes, dtype, shape, space, alignment) |
| S6 | Feature encodings: `ref` (external resource + selector) and `columns` (inline scalars) |
| S7 | Concatenation compatibility rules and algorithm |
| Resolution algorithm | Walk encodings in order; first applicable wins; nullable fallback |
| Conformance levels | Structural vs. full; reader vs. dataset conformance |

### Testing Requirements
- The spec itself is not directly tested, but conformance tests in `tests/testthat/test-conformance-fixtures.R` validate that the R implementation behaves as specified.
- When adding new spec behavior, add a corresponding fixture in `tests/fixtures/` and test in `test-conformance-fixtures.R`.

### Common Patterns
- Alignment levels: `same_grid` > `same_space` > `same_topology` > `loose` > `none`
- Selector syntax is backend-defined, pure data (no code execution), JSON-compatible.
- `ref` encoding: provide either `resource_id` (registry lookup) OR both `backend` + `locator` (direct).
- Cross-language implementability constraint: a core-conformant reader needs only YAML/JSON parser + CSV reader + one backend adapter.

## Dependencies

### Internal
- `inst/schema/nftab-manifest.schema.json` — runtime copy; must be kept in sync with `spec/nftab-manifest.schema.json`
- `inst/examples/` and `tests/fixtures/` — conformance examples referenced from the spec

<!-- MANUAL: -->
