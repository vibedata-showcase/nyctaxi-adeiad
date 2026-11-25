---
status: decided
date: 2026-10-14
---

# Unresolved zones are retained and flagged, not removed or remapped

The TLC zone lookup includes zones whose borough is unknown or not applicable. They are real rows, so they join cleanly. The warehouse keeps them, marks them on `dim_zone` (`is_unresolved_zone`) and on each trip (`is_unresolved_pickup_zone`, `is_unresolved_dropoff_zone`), and does not remap or drop them. No mart excludes them on its own; a borough rollup includes an unresolved group unless its consumer filters.

## Considered options

- **Map them to a placeholder borough and exclude it** — rejected: it hides trips whose location the source could not resolve.
- **Drop trips that touch them** — rejected: the trips happened.
- **Retain and flag** — chosen.

## Consequences

- A borough rollup that does not filter the flag reports an unresolved group.
- `mart_trip_quality_scorecard` counts the trips with an unresolved pickup zone.

## Affected designs

- [`models/core/dim_zone.md`](../design/models/core/dim_zone.md)
- [`models/intermediate/int_trip_quality_flags.md`](../design/models/intermediate/int_trip_quality_flags.md)
- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
