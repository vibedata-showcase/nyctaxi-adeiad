---
artifacts: [mart_daily_zone_revenue]
---

# mart_daily_zone_revenue

Daily revenue by pickup zone. Finance reads it every morning.

## Grain

One row per pickup zone and trip date.

## Schema

- `transformation/models/marts/finance/`: `finance` (default). Source: the approved Requirement's Ask names the finance report; `dbt_project.yml` `models: nyc_taxi_analytics: marts: finance: +schema: finance`.

## Decisions

- `D-01` Apply the billable rule and the reporting window here, in gold, and nowhere upstream, so quality work can still see the rows this excludes ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)). Source: docs/requirement/2026-08-29-the-trip-fact.md R-03, [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-02` Read `agg_trip_zone_daily` and no other relation ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md) is still the rule, applied one layer down). One build now serves Finance's report and Operations' zone figures, which is what the request asks: two builds of the same numbers is the cost being removed. Source: `R-02`; user answer (`opt-0`). Supersedes the sourcing in `D-01`: the billable rule is now applied by the upstream relation, and this model selects its `billable_*` measures rather than re-filtering trips.
- `D-03` Re-point the report's `trip_count` at `billable_trip_count` and its `total_revenue` at `billable_total_revenue`; add no `where` clause. The report has always counted billable trips only (its `is_billable` filter ran before the grouping), so the column keeps its meaning and its values while its source changes. Source: `R-03`, `R-04`; the existing model's filter.
- `D-04` Apply `where billable_trip_count > 0` to drop zone-days with no billable trip. Agg now carries a row for every zone-day including those with none, where the old model's pre-grouping filter never produced a row; without this the report would gain 36 rows it does not have today. Source: `R-06`; user answer (`opt-0`).
- `D-05` Keep every published column exactly as it is: the same 11 names, logical types and grain, with `borough` still aliased from `borough_name` and `trip_date` still aliased from `pickup_date`. The report's contract and its three column tests are otherwise untouched. Source: `R-03`, `R-08`.
- `D-06` Correct the report's own descriptions, which this change would otherwise leave false. `_finance.yml` calls `trip_count` "Trips, billable or not" when the model has always filtered to billable, and the model and its description both claim the billable rule is applied "here and nowhere upstream", which stops being true once agg publishes billable measures. Source: `R-09`.
- `D-07` Keep the model a `table`, and keep its three existing column tests (`not_null` on `trip_date` and `total_revenue`, `relationships` from `pickup_location_id` to `dim_zone.zone_natural_key`). The relationships test still holds without a join: every `pickup_location_id` in agg resolves to `dim_zone` (Verification `## Discovery`). Source: `R-03`, `R-07`; the existing properties file.

## Rejected

- **Re-sourcing onto `agg_trip_zone_daily` unchanged, with its all-trip measures** — it fails Ravi Menon's acceptance check (97,184 trips and 2,597,120.92 revenue against the required 95,958 and 2,629,185.82), and it would delete four of the report's five revenue columns for want of a source column.
- **Making `agg_trip_zone_daily` billable-only so the two agree** — Operations' own figures would move, which the request did not ask for and its owner did not sanction.
- **Re-deriving the report from `fct_trip` while also building agg** — that is the duplicate build the request exists to remove.
- **Emitting zero-billable zone-days as zero rows (`where billable_trip_count >= 0`)** — it would add 36 rows to a report Finance reads daily, changing its shape without changing its totals. Available under `R-06`'s user answer, not taken.
- **Applying the rule in silver** — the excluded rows would be invisible to quality work ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)).

## Consumers

None in this repo beyond its own column tests and the two semantic-layer assertion models (`assert_semantic_content_holds`, `assert_semantic_levels_hold`). Outside the repository: the finance team's morning report read, and Ravi Menon's Q1 2024 acceptance check.

## Logical Model

The report's published shape does not change, so no dataset, metric, level or relationship is added, retired or changed. LTS7's existing binding (`column_map`: `pickup_date`→`trip_date`, `billable_trip_count`→`trip_count`, `billable_revenue`→`total_revenue`; `content_filter` naming `is_billable`) stays correct in meaning, since the new column still carries the billable measure over the billable population. It needs no edit for that binding to remain honest; the model change is therefore invisible to the semantic layer.

The ontology reaches the report only through the `Geography` hierarchy (`region` / `borough` / `zone`) and `Time` (`day`); `reporting_region` remains a `region`-level attribute of the same `dim_zone`-backed dimension, now also carried on this relation, so no concept is added or re-identified.

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets: []
metrics: []
logical_sources: []
concepts: []
mappings: []
```

## History

- 2026-11-25 — daily-zone-revenue-report-from-agg — re-sourced from `agg_trip_zone_daily`'s billable measures instead of `fct_trip`, dropping zero-billable zone-days and correcting two false descriptions; published shape and every value preserved — D-02 supersedes the sourcing in D-01, D-03, D-04, D-05, D-06, D-07 — terms: none new
- 2026-10-14 — trip-fact — design record written; audience wording removed from the model description — D-01
