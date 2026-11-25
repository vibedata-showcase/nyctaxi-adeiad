---
artifacts: [mart_daily_zone_revenue]
---

# mart_daily_zone_revenue

Daily revenue by pickup zone. Now built from the single daily-zone aggregation, `agg_trip_zone_daily`, instead of aggregating the trip fact directly, so the daily-zone figure is computed once in the warehouse ([ADR 0018](../../../adr/0018-daily-zone-aggregation-is-built-once.md)).

## Grain

One row per pickup zone and trip date. Keys: `trip_date` + `pickup_location_id`.

## Schema

- `marts/finance`: `finance` (default). Accepted by the user as the folder's current schema. Source: user answer at the schema question, this intent.

## Decisions

- `D-01` Apply the billable rule and the reporting window here, in gold, and nowhere upstream, so quality work can still see the rows this excludes ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)). Source: docs/requirement/2026-08-29-the-trip-fact.md R-03, [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md). Superseded in part by `D-02`: the rule stays here, the window moves upstream.
- `D-02` The report selects from `ref('agg_trip_zone_daily')` and reads no trip-grain relation, which is what makes the daily zone aggregation a single build. The reporting window is applied in that upstream relation, so this model carries no window filter of its own; it still publishes only the window's rows. Source: R-01; [ADR 0018](../../../adr/0018-daily-zone-aggregation-is-built-once.md).
- `D-03` The billable rule is still applied to the report, now reading the upstream billable measures: the model keeps only rows with `billable_trip_count > 0`. [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md) names this mart among those that apply the rule, and a zone-day with no billable trip must stay absent from the report as it is today. Source: R-05, R-06; [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-04` Exactly the same 11 columns are published, with the same names and types, mapped from the new upstream: `trip_count` from `billable_trip_count`, `total_revenue` from `billable_revenue`, `fare_revenue`, `tip_revenue`, `surcharge_revenue` and `toll_revenue` from their `billable_*` counterparts, and `borough`, `zone_name` and `reporting_region` straight through. No column is added, removed or retyped, so the published shape does not move. Source: R-02, R-08.
- `D-05` `trip_count`'s description is corrected to state that it counts billable trips. The model has always filtered on `is_billable`, but the description read "Trips, billable or not", which contradicts the data. Source: R-06; this intent's `F-01`.
- `D-06` Every output expression is cast to its contract's declared `data_type`, because DuckDB does not coerce an expression to a contract type. Source: R-08; platform dialect card, `## Type fidelity`.
- `D-07` The model stays a table with the same enforced contract. Source: repository convention (`dbt_project.yml` sets `marts` to table); R-08.

## Rejected

- Applying the rule in silver: the excluded rows would be invisible to quality work.

## Logical Model

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets:
  added: []
  changed:
    - trips
  retired: []
metrics:
  added: []
  changed: []
  retired: []
logical_sources:
  added: []
  changed:
    - LTS7_daily_zone_revenue
  retired: []
```

`LTS7_daily_zone_revenue`'s binding of `billable_trip_count` and `billable_revenue` to `trip_count` and `total_revenue` does not change, but its `note` refuses the fare, tip, surcharge and toll revenue "no metric declared", and this intent declares those metrics for `LTS2_zone_day_agg`. The four are bound here too, so the report's component columns stop being unrepresented. The dataset `trips` is listed `changed` because it carries the four new metrics.

Ontology: no concept or mapping changes; the report adds no identity or relationship.

## Consumers

No consumer in this repository beyond its own tests and the canonical semantic model's logical source `LTS7_daily_zone_revenue`, which binds `billable_trip_count` and `billable_revenue` to this table. Finance reads the report every morning outside the repository.

## History

- 2026-11-25 — v-w-2-a4d2091d — rebuilt on `agg_trip_zone_daily`; published shape and every number unchanged; `trip_count` description corrected — D-02, D-03, D-04, D-05, D-06, D-07 (D-01 superseded in part) — terms: none new
- 2026-10-14 — trip-fact — design record written; audience wording removed from the model description — D-01
