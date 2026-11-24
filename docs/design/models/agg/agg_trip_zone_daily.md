---
artifacts: [agg_trip_zone_daily]
---

# agg_trip_zone_daily

Daily zone demand with period-over-period context, and the one place the zone-day aggregation is computed.

## Grain

One row per pickup zone and pickup date (`pickup_date`, `pickup_location_id`). Unchanged by this intent: the billable measures are counted and summed in the same `group by` as the all-trip ones, not in a second build.

## Schema

- `transformation/models/marts/agg`: `agg` (default). Source: user answer.

## Decisions

- `D-01` Gain six billable measures beside the all-trip ones — `billable_trip_count`, `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue`, `billable_toll_revenue`, `billable_total_revenue` — each counted or summed over the rows where `fct_trip.is_billable`, with the same expressions the report uses today, so one build carries both populations and the report's figures do not move. Source: R-01, R-02, [ADR 0018](../../../adr/0018-daily-zone-revenue-covers-every-billable-trip.md), user answer.
- `D-02` The change is additive: every existing column keeps its definition and its value, and the window columns (`prev_day_trip_count`, `same_day_last_week_trip_count`, `trip_count_7d_avg`, `revenue_28d_rolling`, `revenue_rank_that_day`) keep operating on the all-trip `trip_count` and `total_revenue`. Source: R-05, and the semantic layer refuses a row-rolling column for a rolling metric.
- `D-03` The new measures carry a `billable_` prefix so no metric name means two populations, one all trips and one billable. Source: semantic-model rule S3 (a metric name may not mean two populations).
- `D-04` `mart_daily_zone_revenue` reads these measures instead of aggregating `fct_trip`, which is what makes this model the single build of the grouping. Source: R-01, [ADR 0018](../../../adr/0018-daily-zone-revenue-covers-every-billable-trip.md).

## Rejected

- A separate model for the billable measures, leaving this one all-trip — a second build of one grouping, which is what the intent removes.
- Redefining `trip_count` and `total_revenue` as billable — it would move values and break the meaning the semantic layer binds to them.
- Carrying `reporting_region` here so the report need not join the zone dimension — a dimension attribute added to a published boundary model for one consumer's convenience.

## Consumers

- `mart_daily_zone_revenue`, through the six billable measures.
- The semantic layer: the `trips` document's aggregate logical source for the billable population, which supplies `billable_trip_count` and `billable_revenue` and the four new component-revenue metrics; `assert_semantic_content_holds` and `assert_semantic_levels_hold` depend on the model.
- The ODCS contract `contracts/agg/agg_trip_zone_daily.odcs.yaml`: six properties added, none removed or retyped, so the delta is additive and the version moves minor, with no breaking contract.

## Logical Model

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets: []
metrics:
  - {name: billable_fare_revenue, change: added}
  - {name: billable_tip_revenue, change: added}
  - {name: billable_surcharge_revenue, change: added}
  - {name: billable_toll_revenue, change: added}
  - {name: billable_trip_count, change: changed}
  - {name: billable_revenue, change: changed}
logical_sources:
  - {name: LTS10_zone_day_billable, change: added}
ontology: []
```

`billable_trip_count` and `billable_revenue` keep their definitions and gain an aggregate supplier at the zone-day grain; the four component metrics did not exist and read the fare, tip, surcharge and toll amounts under the same billable filter the detail source carries.

## History

- 2026-11-24 — r9-zone-revenue — design record written; billable measures added beside the all-trip ones — D-01, D-02, D-03, D-04 — terms: none new
