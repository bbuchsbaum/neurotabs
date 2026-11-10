# Draft NFTab extensions

Optional `x-` extensions proposed for exchange between tools. Each is
versioned on its own and changes nothing about core NFTab conformance: a
generic reader may ignore them (spec §4.3). They are drafts for review, not
released compatibility promises.

| Extension | Purpose | Status |
| --- | --- | --- |
| [`x-backing`](x-backing.md) | Links a result map to the dataset and feature it was computed from, so a viewer can plot the data behind a map and know when a probe is circular. | Draft 0.1.0; read by neuroimjs |
| [`x-volume-series`](x-volume-series.md) | Volume features with a trailing non-spatial axis (FIR lags, basis coefficients), with the axis positions and, for a basis, the curve it reconstructs. | Draft 0.1.0; read by neuroimjs |

Stored summaries (estimates with interval bounds) have their own profile:
[`x-summary`](../summary/README.md).
