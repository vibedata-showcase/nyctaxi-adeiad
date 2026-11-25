---
artifacts: [agg_trip_zone_daily]
---

# agg_trip_zone_daily

Daily zone demand, one row per zone and pickup date, with period-over-period context. The window functions are the point: a raw daily count answers "how many", and the lag and rolling average answer "is that normal".

## Grain

One row per pickup date and pickup location. The four descriptive columns (`zone_name`, `borough_name` and the new `reporting_region`, beside `pickup_location_id`) do not split it: grouping the window's trips by date, zone and region yields the same rows as grouping by date and zone. Adding a billable measure changes no key, so the grain is recorded here rather than decided.

## Schema

- `transformation/models/marts/agg`: `agg` (default). Source: user answer at design, batched schema question.

## Decisions

- `D-01` The billable measures are aggregated here, once, so the finance report and the demand aggregate read one build instead of two. The all-trips measures keep their own definition beside them. Source: requirement R-02 and R-03; the user's answer to the `one source` question.
- `D-02` The billable rule ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)) is applied inside the aggregates, as a `filter (where f.is_billable)` on each, in the same scan as the all-trips measures; the reporting window is applied once, in the CTE. One trip scan, one definition of billable, and the report no longer recomputes either. Source: requirement R-02; [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-03` The new columns are named `billable_trip_count`, `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue`, `billable_toll_revenue` and `billable_total_revenue`, and the existing `trip_count` and `total_revenue` are not renamed. Reason: `trip_count` and `total_revenue` already mean all trips on this relation (the semantic model binds `trip_count` to them), and a rename would break the demand consumers; the prefix states which population a measure counts. Source: requirement R-03; `logical-model/nyc_taxi_analytics.ossie.yaml` LTS2_zone_day_agg.
- `D-04` A zone-day with no billable trip carries `billable_trip_count = 0` and zero, not null, in every billable revenue column. Reason: the trips exist and none of them is billable, so zero is the value rather than an absence, and a consumer summing the column needs no `coalesce`. Source: requirement R-06.
- `D-05` `reporting_region` is added, joined from `dim_zone` in the same CTE that already joins it for the zone's name and borough. Reason: the report publishes it and this relation is now its only source. Source: requirement R-01 and R-02.
- `D-06` The relation stays a full-rebuild `table` with its enforced contract, and its contract moves to version 1.1.0 for the seven added properties — an additive, minor move with no property removed or retyped. Source: requirement R-02; `data-contract` skill, "Which version? Added: minor".
- `D-07` The `trip_count` description in the canonical model's `trips` dataset ("Trips, billable or not") is correct as it stands and does not change; only this relation's own column descriptions state the billable population. Source: requirement R-07; `logical-model/nyc_taxi_analytics.ossie.yaml` `trips.trip_count`.

## Rejected

- **A separate billable aggregate beside this one** — rejected: it is the second build the request exists to remove.
- **Keeping the billable aggregation in the finance mart and only adding the descriptive columns here** — rejected: the report would still aggregate `fct_trip` itself, so there would still be two builds of the same numbers.
- **Renaming `trip_count` to `all_trip_count` so the populations are symmetric** — rejected: it retypes nothing but breaks the demand consumers and the canonical source for a naming symmetry alone.

## Consumers

- `finance.mart_daily_zone_revenue`, which now reads this relation and nothing else.
- `transformation/tests/assert_semantic_content_holds.sql` and `assert_semantic_levels_hold.sql`, generated from the canonical model's LTS2 binding.
- Demand and period-over-period analysis through the canonical model (`LTS2_zone_day_agg`) and directly by `agg_od_flow_matrix`'s peer marts.

## Logical Model

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets: {}
metrics: {}
logical_sources:
  LTS2_zone_day_agg: changed
```

The new `billable_trip_count` and `billable_total_revenue` join that source's `column_map`; both metrics they compute already exist (`billable_trip_count` and `billable_revenue`), so no metric is added. The document's `trips` dataset, its levels and its relationships are unchanged: no field is added to it.

## History

- 2026-11-25 — tarun-ex2 — record written; billable measures and `reporting_region` added so the finance report reads this relation — D-01 to D-06 — terms: none new
