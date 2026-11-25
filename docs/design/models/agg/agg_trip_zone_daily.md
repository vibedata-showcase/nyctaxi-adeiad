---
artifacts: [agg_trip_zone_daily]
---

# agg_trip_zone_daily

Daily zone demand, with period-over-period context. It is the one source Finance's daily zone revenue report and Operations' zone figures both read.

## Grain

One row per pickup zone and trip date, unchanged by this intent. Adding `pickup_date_key` does not split it: agg holds 7,997 rows and 7,997 distinct `(pickup_date, pickup_location_id)` pairs, and 7,997 distinct triples once the key is included (Verification `## Discovery`).

## Schema

- `transformation/models/marts/agg/`: `agg` (default). Source: the approved Requirement's Ask names the `agg` schema as where Operations keeps its daily figures by zone; `dbt_project.yml` `models: nyc_taxi_analytics: marts: agg: +schema: agg`.

## Decisions

- `D-01` Apply the billable rule to the new `billable_*` columns only, leaving every existing all-trip column measuring all trips ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)). This is the whole point of the change: Finance's report must keep its billable-only numbers while Operations' figures must not move, and one relation serves both only if it publishes both populations side by side. Source: `R-01`, `R-07`, `R-02`; user answer (`opt-0`).
- `D-02` Publish `billable_trip_count` beside the billable revenue columns rather than relying on the all-trip `trip_count`. Where a row has no billable trip, its billable revenue is 0 while its all-trip `trip_count` is not, so without the billable count a consumer cannot see the coverage of the revenue columns. Source: `R-01`, the Coverage default; the same shape `agg_trip_zone_daypart_dow` already publishes.
- `D-03` Name the new measures `billable_<existing name>` and compute each as `sum(...) filter (where f.is_billable)`, so the existing `total_revenue` and the new `billable_total_revenue` are visibly the same measure over two populations. A reader of the contract sees the pair, not an unexplained second revenue column. Source: `R-01`; the existing `billable_trip_count` naming in `agg_trip_zone_daypart_dow`.
- `D-04` Return `0`, not `NULL`, for a billable measure on a zone-day with no billable trip. `0` is a real value here: no billable revenue was earned. A `NULL` would make every downstream `sum()` need `coalesce`, and the report's own measures are never null. Source: `R-06`; user answer (`opt-0`).
- `D-05` Carry `reporting_region` from `dim_zone` into the grouped output so the report can publish it without a join. The report may not read any relation other than this one (`R-02`), and `reporting_region` is a `region` level attribute of the `Geography` hierarchy, so it must come from here. Grouping by it does not move the row count: no `zone_natural_key` varies in `zone_name`, `borough_name` or `reporting_region` across its versions (Verification `## Discovery`). Source: `R-01`, `R-02`.
- `D-06` Keep the existing `inner join` to `dim_zone` and add nothing to it. The join is what supplies `zone_name`, `borough_name` and now `reporting_region`, and it has always been inner: a trip whose zone does not resolve is already outside this relation's population, and the report inherits that population exactly. Source: `R-07`; the Unmatched-and-null-keys default with the existing model's behaviour; no billable trip has a null `pickup_zone_key` (Verification `## Discovery`).
- `D-07` Compute the five window columns last, over the completed `daily` CTE, exactly as today, so the new columns cannot disturb an existing row's window value. `revenue_28d_rolling` keeps summing the all-trip `total_revenue`; it is not re-pointed at a billable column, because that would change a value Operations already reads. Source: `R-07`.
- `D-08` Keep the model a `table`. It is read once per day by two consumers and its window functions are the expensive part; a view would recompute them on every read. Source: `dbt_project.yml` `marts: agg: +schema: agg` with the project's `marts: +materialized: table`; `R-07` expects no change here.

## Rejected

- **Publishing only billable measures and dropping the all-trip ones** — Operations' existing figures would change, and the request did not ask for that. The opposite of the accepted option, and the reason the two populations are carried side by side.
- **Re-sourcing the report onto agg unchanged and accepting new numbers** — it fails Ravi Menon's acceptance check, which is the condition of accepting the change at all.
- **Publishing the report's five revenue components under their existing names and moving `total_revenue` to the billable measure** — this would silently redefine a column Operations already reads. `total_revenue` keeps its all-trip meaning; the billable measure takes a new name.
- **Joining `dim_zone` again inside the report** — `R-02` requires the report to read one relation only, and the join is already done here.
- **Building the report from `fct_trip` and leaving agg alone** — that is today's duplicate build, which is what the request asks to remove.

## Consumers

Depended on by: `assert_semantic_content_holds`, `assert_semantic_levels_hold` (via the Ossie LTS2 logical source), and — new in this intent — `mart_daily_zone_revenue`. Its published contract is `contracts/agg/agg_trip_zone_daily.odcs.yaml`.

## Logical Model

The change is additive: no dataset, metric, level or relationship is added, retired or re-populated. LTS2's binding is deliberately left unchanged, because widening `column_map` would let the compiler answer a billable-revenue question from a relation whose population mixes both.

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

- 2026-11-25 — daily-zone-revenue-report-from-agg — design record written; added `billable_trip_count`, `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue`, `billable_toll_revenue`, `billable_total_revenue` and `reporting_region` so Finance's report can be built from this relation without moving any of its numbers — D-01, D-02, D-03, D-04, D-05, D-06, D-07, D-08 — terms: none new
