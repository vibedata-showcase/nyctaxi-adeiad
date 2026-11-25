---
artifacts: [int_trip_quality_flags]
---

# int_trip_quality_flags

Every quality verdict for a trip in one row, so downstream models filter on a named condition rather than re-deriving a rule.

## Grain

One row per trip (`trip_key`).

## Decisions

- `D-01` Flag; never delete. The verdicts are billable, refund, zero distance, implausibly short, implausibly fast, negative duration, zero passenger count, missing passenger count, sparse vendor feed, unresolved pickup zone, unresolved dropoff zone, undocumented rate code and missing airport fee ([ADR 0004](../../../adr/0004-quality-verdicts-flag-trips-and-never-delete-them.md)). Source: docs/requirement/2026-08-29-the-trip-fact.md R-03, [ADR 0004](../../../adr/0004-quality-verdicts-flag-trips-and-never-delete-them.md).
- `D-02` `is_billable` is a positive total and nothing else; it does not look at the payment method ([ADR 0018](../../../adr/0018-zone-day-billable-measures-are-computed-once-in-the-aggregate.md), [ADR 0013](../../../adr/0013-no-charge-and-dispute-payments-are-not-excluded-by-the-billable-rule.md)). Source: [ADR 0018](../../../adr/0018-zone-day-billable-measures-are-computed-once-in-the-aggregate.md), [ADR 0013](../../../adr/0013-no-charge-and-dispute-payments-are-not-excluded-by-the-billable-rule.md).
- `D-03` The implausible-duration and implausible-speed thresholds are the project variables `min_plausible_seconds` and `max_plausible_mph`, so changing one changes flags, not rows. Source: [ADR 0004](../../../adr/0004-quality-verdicts-flag-trips-and-never-delete-them.md).
- `D-04` A trip touching an unresolved zone is flagged on both ends and kept ([ADR 0012](../../../adr/0012-unresolved-zones-are-retained-and-flagged.md)). Source: [ADR 0012](../../../adr/0012-unresolved-zones-are-retained-and-flagged.md).
- `D-05` Materialise as a view. The trip grain is stored once, in `fct_trip`; storing it again here made the seeded Domain file 1,158 MiB for one month, over Studio's 1 GiB upload, and only `fct_trip`'s build reads this model in full. Source: user answer, new-intent seed-domain (2026-10-15).

## Rejected

- Deleting trips with a verdict.
- A quarantine table: a second copy of the trip to keep in step.

## Consumers

Depended on by: `agg_od_flow_matrix`, `agg_trip_band_profile`, `agg_trip_zone_daily`, `agg_trip_zone_daypart_dow`, `agg_weather_demand_daily`, `dim_trip_quality`, `fct_trip`, `mart_daily_zone_revenue`, `mart_monthly_service_summary`, `mart_revenue_component_bridge`, `mart_trip_quality_scorecard`.

## History

- - 2026-10-14 — setup-dlt-ingestion — design record written — D-01, D-02, D-03, D-04
- 2026-10-15 — seed-domain — materialised as a view — D-05
