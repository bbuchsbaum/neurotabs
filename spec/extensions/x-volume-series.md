# `x-volume-series` 0.1.0 (draft): volumes with a non-spatial axis

Some per-observation values are a volume with one more axis that is not
spatial: a finite-impulse-response (FIR) estimate per lag, or the coefficients
of a temporal basis (canonical HRF and derivatives, splines). Core NFTab
describes the axis (`axes`, `shape`) but has no place for the positions of a
non-spatial axis or for the curve a basis stands for (`axis_domains` admits
only `id`, `labels`, `size` and `description`). This extension adds them.

MUST, SHOULD and MAY are used as in the core specification (§2).

## 1. Feature shape

The feature is a volume whose first three axes are spatial (they lie on the
feature's support) and whose fourth is the series axis:

```yaml
features:
  response:
    logical:
      kind: volume
      axes: [x, y, z, lag]
      dtype: float32
      shape: [91, 109, 91, 9]
      support_ref: mni_2mm
    encodings:
      - type: ref
        binding: {backend: nifti, locator: {column: response_file}}
```

With the `nifti` backend and no selector, a row resolves to a 4D image whose
fourth dimension is the series axis (Appendix B: the resource matches the
logical schema without a selector).

## 2. Extension

```yaml
extensions:
  x-volume-series:
    version: "0.1.0"
    features:
      response:
        axis: lag
        values: [0, 2, 4, 6, 8, 10, 12, 14, 16]
        unit: s
```

| Field | Required | Meaning |
| --- | --- | --- |
| `version` | Yes | `"0.1.0"`. |
| `features.<name>.axis` | Yes | The series axis; MUST be the feature's fourth logical axis. |
| `features.<name>.values` | Yes | Numeric position of each index along the axis, in order; length equals the axis length (`shape[3]` when declared). For basis coefficients, the coefficient numbers. |
| `features.<name>.unit` | No | Unit of `values` (e.g. `s`). |
| `features.<name>.basis` | No | For coefficients: the curve they reconstruct (§3). |

## 3. Basis

```yaml
        basis:
          name: time
          unit: s
          values: [0, 0.5, 1, ...]          # the curve's grid, length T
          weights: {path: hrf_basis.tsv, format: tsv}
```

`weights` is a table with one row per grid point (T rows) and one column per
coefficient (in axis order, headed by the coefficient values), or an inline
T × B array of numbers. The reconstructed curve of a row at grid point t is
`sum_b weights[t][b] × coefficient[b]`. Readers MUST use these weights as
given; they MUST NOT refit or resample the basis.

## 4. Constraints

- The series axis is not spatial: spatial operations (probes, clusters,
  resampling) act on the first three axes only.
- `values` MUST be finite and distinct. For an axis plotted on a numeric scale
  (lags, times) they MUST be strictly increasing.
- Paths follow the core rules (§12.2: relative to the manifest).

## 5. Reader behaviour

A plotting reader averages over spatial locations only, then shows the series
along `values` (FIR) or reconstructs each row's curve with `basis.weights`
before averaging across observations (basis). Averaging coefficients and then
reconstructing is equivalent only because reconstruction is linear; readers
SHOULD reconstruct per observation so that intervals describe curves.

## 6. Status

neuroimjs reads this extension (`NFTab.backing()`). It replaces an earlier
neuroimjs convention that put `values`/`unit` inside `axis_domains`, which the
core schema does not allow.
