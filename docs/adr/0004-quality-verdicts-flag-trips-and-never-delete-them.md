---
status: decided
date: 2026-10-14
---

# Quality verdicts flag trips; no trip is deleted

Every trip carries its quality verdicts: refund (negative total), zero distance, implausibly short or fast (the thresholds are the dbt vars `min_plausible_seconds` and `max_plausible_mph`), negative duration, zero or missing passenger count, sparse vendor feed, unresolved pickup or dropoff zone, undocumented rate code and missing airport fee. They live in `int_trip_quality_flags`, are summarised by `dim_trip_quality` (a junk dimension over the combinations that occur), and reach `fct_trip` through `trip_quality_key`. No model removes a trip because of a verdict, and a singular test holds `fct_trip` to the row count of `int_trips_conformed`.

## Considered options

- **Delete or filter in silver** — rejected: a trip that happened would vanish from every count, and the share of bad records could not be measured.
- **Quarantine table** — rejected: a second copy of the trip to keep in step with the first.
- **Flag on the trip, filter in the consumer** — chosen.

## Consequences

- A consumer decides which verdicts to exclude, and says so.
- Thresholds are project variables, so changing one changes the flags, not the rows.
- `mart_trip_quality_scorecard` reports how much of the feed each verdict touches.

## Affected designs

- [`models/intermediate/int_trip_quality_flags.md`](../design/models/intermediate/int_trip_quality_flags.md)
- [`models/core/fct_trip.md`](../design/models/core/fct_trip.md)
- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
