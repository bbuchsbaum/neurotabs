# `x-backing` 0.1.0 (draft): the data behind a map

A result dataset (a group statistic map, a contrast map) is usually computed
from another dataset: per-subject or per-condition maps. `x-backing` records
that link, so that a viewer can open the map and, at any location, plot the
observations the map was computed from. It also tells the viewer that a region
chosen by looking at this map is not independent of those observations.

MUST, SHOULD and MAY are used as in the core specification (§2).

## 1. Placement

In the manifest of the result dataset:

```yaml
extensions:
  x-backing:
    version: "0.1.0"
    source: ../betas/nftab.json
    feature: beta
    map: faces − houses
    stat: t
    formula: "~ condition + (1 | subject)"
```

## 2. Fields

| Field | Required | Meaning |
| --- | --- | --- |
| `version` | Yes | `"0.1.0"`. |
| `source` | Yes | Path of the source dataset's manifest, or of a directory holding `nftab.json`/`nftab.yaml`, relative to this manifest. |
| `feature` | Yes | The source feature the map was computed from. It MUST exist in the source manifest. |
| `map` | No | What the map shows, for people (e.g. `faces − houses`). |
| `stat` | No | The map's statistic symbol, for threshold wording (e.g. `t`, `z`, `F`). |
| `formula` | No | The model or computation, as text. No expression language is defined; it is documentation. |
| `source_checksum` | No | `sha256:<hex>` of the source manifest's bytes when the map was written, so a reader can tell that the source changed since. |

The link applies to every volume feature of the result dataset unless a
feature-level form is used:

```yaml
extensions:
  x-backing:
    version: "0.1.0"
    features:
      t:    {source: ../betas/nftab.json, feature: beta, map: faces − houses, stat: t}
      beta: {source: ../betas/nftab.json, feature: beta, map: faces − houses, stat: β}
```

A manifest uses either the dataset-level fields or `features`, not both.

## 3. Constraints

- `source` MUST be a relative path. It MUST NOT be absolute, a URL, or contain a
  drive letter or backslash. Unlike Summary Profile table paths it MAY begin
  with `..`, because result and source datasets are commonly siblings in one
  study folder; it MUST NOT leave the folder that is published or distributed
  with the result.
- The backing feature and the result feature SHOULD share an exact support
  (§8.6): the same `support_id`, so a location in the map is a location in the
  source data without resampling. When they do not, a reader MAY resample and
  MUST say so.
- A writer SHOULD set `source_checksum`. A reader that finds a different
  checksum SHOULD warn that the map may no longer describe its source.

## 4. Reader behaviour

- A viewer that probes the source data at a location chosen on the result map
  SHOULD treat the probe as circular (the region was selected using the same
  observations) unless the user declares the selection independent, and SHOULD
  say so where the data are shown. This is the main reason the link exists.
- A reader MUST NOT recompute the map from the source. The link describes
  provenance; it is not a recipe.
- An unreadable or missing source is reported, not silently ignored; the map
  itself stays readable (core conformance does not depend on this extension).

## 5. Lifecycle

Operations that change the result dataset's observations or the referenced
features MUST drop `x-backing` and warn, as for `x-summary` (Summary Profile
§8), unless they rewrite the link correctly. Copying a result dataset without
its source breaks the link; writers SHOULD copy or relink the source.
Concatenating results that link to different sources is not
strict-concatenation-compatible unless the `features` form keeps each link.

## 6. Relation to other extensions

- `x-summary` stores estimates and intervals already computed; `x-backing`
  points at the observations so a viewer can summarise them at any location.
  A dataset may carry both.
- Implementations: neuroimjs (`NFTab.followBacking()`, the backed-plot viewer)
  reads the dataset-level form. neurotabs does not yet write it; `nf_analyze()`
  is the natural writer.
