---
artifacts: [fct_trip]
---

# fct_trip

The warehouse trip contract: conformed trip measures, role-playing zone keys, effective-dated reference keys, quality status, and optional fleet attribution.

## Grain

One row per distinct TLC trip, keyed by `trip_key`. Every conformed trip is retained; no join adds or removes one.

## Decisions

- `D-01` Retain every conformed trip and expose `is_billable`; revenue and flow marts apply the billable rule ([ADR 0018](../../../adr/0018-zone-day-billable-measures-are-computed-once-in-the-aggregate.md)), and quality verdicts flag rather than delete ([ADR 0004](../../../adr/0004-quality-verdicts-flag-trips-and-never-delete-them.md)). Filtering the fact would prevent quality and operational analysis of refunds, voids and meter errors. Source: docs/requirement/2026-08-29-the-trip-fact.md R-01, R-03, [ADR 0018](../../../adr/0018-zone-day-billable-measures-are-computed-once-in-the-aggregate.md), [ADR 0004](../../../adr/0004-quality-verdicts-flag-trips-and-never-delete-them.md).
- `D-02` Resolve pickup and dropoff zones separately, and resolve zones and vendors as of the pickup date using half-open validity ranges ([ADR 0009](../../../adr/0009-type-2-only-where-the-source-versions-history.md)). Current-version joins would rewrite history; natural-key-only joins can multiply rows. Source: docs/requirement/2026-08-29-the-trip-fact.md R-04, [ADR 0009](../../../adr/0009-type-2-only-where-the-source-versions-history.md).
- `D-03` A lookup that finds no row in force leaves the key null, with no placeholder member ([ADR 0015](../../../adr/0015-unmatched-dimension-keys-stay-null.md)). Driver, vehicle and shift are null for trips outside the operator's fleet, and `is_fleet_attributed` says so: null is an expected coverage boundary, not a failed lookup. Source: docs/requirement/2026-08-29-the-trip-fact.md R-05, [ADR 0015](../../../adr/0015-unmatched-dimension-keys-stay-null.md).
- `D-04` Materialise incrementally by `trip_key`. The predicate processes only pickups later than the maximum already loaded; a correction or late-arriving trip at or before that boundary, and any change to upstream logic, needs a full refresh. Source: docs/requirement/2026-08-29-the-trip-fact.md R-01.
- `D-05` `measurable_tip_rate` is null where the payment method does not record tips ([ADR 0011](../../../adr/0011-tips-are-measured-only-where-the-meter-records-them.md)). Source: [ADR 0011](../../../adr/0011-tips-are-measured-only-where-the-meter-records-them.md).
- `D-06` `is_billable` looks only at the total amount; no payment method is excluded by it, and each metric decides ([ADR 0013](../../../adr/0013-no-charge-and-dispute-payments-are-not-excluded-by-the-billable-rule.md)). Source: [ADR 0013](../../../adr/0013-no-charge-and-dispute-payments-are-not-excluded-by-the-billable-rule.md).
- `D-07` `trip_key` is the key produced by `int_trips_conformed` ([ADR 0007](../../../adr/0007-trip-key-has-one-definition.md)). Source: docs/requirement/2026-08-29-the-trip-fact.md R-06, [ADR 0007](../../../adr/0007-trip-key-has-one-definition.md).

## Rejected

- Filtering the fact to billable trips: it would hide the trips quality work needs.
- Current-version joins to Type 2 dimensions: they rewrite history.
- A placeholder member for unmatched keys: it joins cleanly and hides the gap ([ADR 0015](../../../adr/0015-unmatched-dimension-keys-stay-null.md)).

## Consumers

Depended on by: `agg_od_flow_matrix`, `agg_trip_band_profile`, `agg_trip_zone_daily`, `agg_trip_zone_daypart_dow`, `agg_weather_demand_daily`, `mart_daily_zone_revenue`, `mart_monthly_service_summary`, `mart_revenue_component_bridge`, `mart_trip_quality_scorecard`.

## Semantic Model

```yaml
metrics:
  - trip_count
  - billable_trip_count
  - billable_revenue
  - fare_residual_total
```

## History

- - 2026-08-29 — trip-fact — design record written (commit 97862f7) — D-01, D-02, D-03, D-04
- - 2026-10-14 — setup-dlt-ingestion — rows come from `int_trips_conformed`; record conformed to the template; ADR links added — D-05, D-06, D-07
