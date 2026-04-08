<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-04-07 | Updated: 2026-04-07 -->

# vignettes/

## Purpose
R Markdown vignettes that document how to use the neurotabs package. Built into the pkgdown site as articles and distributed with the package via `knitr`/`rmarkdown`.

## Key Files

| File | Description |
|------|-------------|
| `neurotabs.Rmd` | Main introductory vignette: getting started, core concepts, basic workflows |
| `specification.Rmd` | Specification guide vignette: NFTab spec concepts explained with R examples |
| `albers.css` | Custom CSS styling for vignettes (from albersdown theme) |
| `albers.js` | Custom JavaScript for vignettes |

## For AI Agents

### Working In This Directory
- If user-facing behavior changes (new function, changed argument, modified grammar verb), update the relevant vignette in the same pass.
- Vignettes run during `R CMD check` — they must execute without errors using only packages listed in `Suggests`.
- The `Config/Needs/website: albersdown` in DESCRIPTION handles the custom CSS/JS theme for pkgdown.

### Testing Requirements
```r
# Build vignettes locally
Rscript -e 'devtools::build_vignettes()'

# Check that vignettes run clean
Rscript -e 'devtools::check(vignettes = TRUE)'
```

### Common Patterns
- Use `system.file("examples", ..., package = "neurotabs")` to reference example datasets in vignette code.
- Vignette YAML header should include `VignetteIndexEntry` for the package vignette index.
- Guard NIfTI-dependent code chunks with `eval = requireNamespace("neuroim2", quietly = TRUE)`.

## Dependencies

### Internal
- `inst/examples/` — example datasets used in vignette code
- `R/` — all package functions demonstrated in vignettes

### External
- `knitr`, `rmarkdown` — vignette building
- `albersdown` (website only, via `Config/Needs/website`)

<!-- MANUAL: -->
