---
status: decided
date: 2026-10-14
---

# A dimension is Type 2 only where the source versions its history

`dim_zone` and `dim_vendor` are Type 2 because the master-data platform delivers `valid_from_date`, `valid_to_date` and a version for them: TLC re-designates zones and vendors are renamed. `dim_driver` and `dim_vehicle` are Type 1 because the operator keeps no history, so a Type 2 dimension would have history that was never recorded. Facts resolve Type 2 dimensions as of the trip's own date through a half-open interval (from inclusive, to exclusive).

## Considered options

- **Type 2 everywhere** — rejected: it would invent history for drivers and vehicles.
- **Type 1 everywhere** — rejected: it would rewrite old trips against a zone or vendor as it is today.
- **Type 2 where the source versions, Type 1 elsewhere** — chosen.

## Consequences

- A join to a Type 2 dimension carries the fact's date and uses `>=` and `<`; `between` double-counts on a changeover date.
- Joining on the natural key alone multiplies facts for entities with more than one version.
- A new dimension is Type 2 only if its source supplies validity dates.

## Affected designs

- [`models/core/dim_zone.md`](../design/models/core/dim_zone.md)
- [`models/core/fct_trip.md`](../design/models/core/fct_trip.md)
- [`pipelines/mdm.md`](../design/pipelines/mdm.md)
- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
