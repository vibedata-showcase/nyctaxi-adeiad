---
artifacts: [mart_daily_zone_revenue]
---

# mart_daily_zone_revenue

Daily revenue by pickup zone. Built from the operations daily zone figures, one source for both.

## Grain

One row per pickup zone and trip date, over billable trips only.

## Schema

- `transformation/models/marts/finance/`: `finance` (default). Source: user answer.

## Decisions

- `D-01` Apply the billable rule and the reporting window here, in gold, and nowhere upstream, so quality work can still see the rows this excludes ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)). Source: docs/requirement/2026-08-29-the-trip-fact.md R-03, [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-02` Supersedes `D-01`: the billable rule and the reporting window are applied in `agg_trip_zone_daily`, and this model reads their verdict. `D-01`'s placement is what had to change — leaving the rule here would keep this a second aggregation of `fct_trip`, the thing this change removes. The population `D-01` states is unchanged: billable trips in the reporting window ([ADR 0018](../../../adr/0018-the-billable-rule-moves-into-the-operations-daily-zone-aggregate.md), [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)). Source: R-01, R-02, R-05; user answer.
- `D-03` The model reads `agg_trip_zone_daily` and no other relation. It takes `zone_name`, `borough_name` and `reporting_region` from that table rather than joining `dim_zone`, because 7 zone natural keys carry two SCD2 versions and a natural-key join to `dim_zone` would return two rows for those zone-days and double their revenue. Source: R-01, R-02; Verification `## Discovery`.
- `D-04` A zone-day whose trips are all non-billable is not published: the model filters on the aggregate's billable trip count. Keeping those rows would publish zone-days with no revenue and grow the report's row count without changing a total. Source: R-05; user answer.
- `D-05` The published shape does not move: the same name, schema, grain and eleven columns with the same names and types, so the ODCS contract, the canonical model's `LTS7_daily_zone_revenue` logical source and the generated semantic tests keep resolving. `trip_count`, `fare_revenue`, `tip_revenue`, `surcharge_revenue`, `toll_revenue` and `total_revenue` are the billable figures, as they were before this change; nothing about their meaning moves. Source: R-06.
- `D-06` The model keeps its own reporting-window filter alongside the aggregate's. The aggregate already applies the window, so the filter here is redundant rather than load-bearing; it stays because dropping it would make the model's population depend on a setting it does not name, and a reader could not then tell from this file what window it answers. Source: R-05.
- `D-07` `trip_count`'s description is corrected: it says "Trips, billable or not" but the model has only ever published billable trips. The corrected text states the billable population and the window. Source: R-07.

## Rejected

- Keeping the report as its own aggregation of `fct_trip` — it is the second build the request exists to remove.
- Reading `agg_trip_zone_daily` unchanged and subtracting non-billable trips in the report — a non-billable trip carries a negative total and the aggregate publishes only whole totals, so the billable population cannot be recovered by arithmetic downstream.
- Re-joining `dim_zone` for zone attributes — the natural-key join fans out across SCD2 versions.
- Publishing the 36 all-non-billable zone-days with zero revenue — they add rows and no revenue, and change the report's shape.
- Renaming or restructuring the report so its name reflects the new source — the name is a published promise its consumers resolve, and the request asked for no number to change.

## Consumers

None in this repo: no model reads it. Outside the repository, the finance team reads the daily zone revenue report every morning. Inside the semantic layer, the canonical model's `LTS7_daily_zone_revenue` logical source binds `billable_trip_count` and `billable_revenue` to it, and `assert_semantic_content_holds` and `assert_semantic_levels_hold` hold that binding. `contracts/finance/mart_daily_zone_revenue.odcs.yaml` carries its contract, version 1.0.1.

## Logical Model

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets: []
metrics: []
logical_sources:
  - name: LTS7_daily_zone_revenue
    change: changed
concepts: []
mappings: []
```

`LTS7_daily_zone_revenue` keeps its `column_map` (`billable_trip_count` → `trip_count`, `billable_revenue` → `total_revenue`), its levels and its content filter: the published values and their meaning do not move, so the binding that describes them does not either. Its `note` is rewritten, because it explains the report's population by saying the mart applies `f.is_billable` — after this change the mart inherits the verdict from the aggregate. The `note` must not claim a second reason the binding is valid, and the content filter it cites still holds because the published values are unchanged. Source: R-06.

## History

- 2026-10-14 — trip-fact — design record written; audience wording removed from the model description — D-01
- 2026-11-25 — zone-revenue-report-from-operations-figures-2 — rebuilt on `agg_trip_zone_daily`; billable rule read from the aggregate instead of applied here; `trip_count` description corrected — D-02 (supersedes D-01), D-03, D-04, D-05, D-06, D-07 — terms: none new
